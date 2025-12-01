#!/bin/bash

# 导入GPU锁管理器
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/npu_lock_manager.sh"

# 接收参数
MODEL=$1
GPU_QUANITY=$2
USE_PREFIX_CACHE=$3
SCHEDULE_POLICY=$4
SWAP_SPACE=$5
MASTER_IP=$6
NODE_RANK=$7
JOB_COUNT=$8
GPU_MODEL=$9
VERSION=${10}

# 生成唯一的任务ID
TASK_ID="<<<TEST_TYPE>>>_${MODEL}_${JOB_COUNT}"
LOCAL_IP=$(hostname -I | awk '{print $1}')
SERVER_NAME=$(echo $LOCAL_IP | sed 's/\./_/g')

# 设置清理函数，确保异常退出时释放锁
cleanup_locks() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        if [ ! -z "$LOCKED_GPUS" ]; then
            echo "检测到异常退出（退出码: $exit_code），正在释放GPU锁: ${LOCKED_GPUS}"
            release_npu_locks_batch "$SERVER_NAME" "$LOCKED_GPUS" "$TASK_ID"
        fi
    else
        echo "正常退出（退出码: 0），保留GPU锁"
    fi
}

# 注册退出时的清理函数
trap cleanup_locks EXIT INT TERM

if [ $USE_PREFIX_CACHE -eq 1 ]; then
    USE_PREFIX_CACHE="--use-prefix-cache"
else
    USE_PREFIX_CACHE=""
fi

SWAP_SPACE_OPTION=""
if [ $SWAP_SPACE -gt 0 ]; then
    SWAP_SPACE_OPTION="--swap-space $SWAP_SPACE"
fi

LATEST_TAG=""
if [ -z $VERSION ]; then
    # 先拿到所有 tag 并按字母升序
    TAGS=$(/home/s_limingge/jfrog rt curl \
        --server-id=my-jcr \
        /api/docker/docker-local/v2/siginfer-x86_64-nvidia/tags/list \
    | jq -r '.tags[]' | sort)

    # 遍历每个 tag，查询 Storage API 并输出 tag + 创建时间
    for tag in $TAGS; do
    created=$(/home/s_limingge/jfrog rt curl \
        --server-id=my-jcr \
        /api/storage/docker-local/siginfer-x86_64-nvidia/$tag \
        | jq -r '.created')
    echo "$tag $created"
    done > tag_dates.txt

    LATEST_TAG=$(sort -k2 -r tag_dates.txt | grep main- | head -n1 | awk '{print $1}')
    echo "The latest version : $LATEST_TAG"
else
    LATEST_TAG=$VERSION
    echo "The specified version : $LATEST_TAG"
fi

DOCKER_IMAGE_URL=""
docker pull docker.xcoresigma.com:80/docker/siginfer-x86_64-nvidia:$LATEST_TAG
if [ $? -ne 0 ]; then
    docker pull docker.xcoresigma.com/docker/siginfer-x86_64-nvidia:$LATEST_TAG
    if [ $? -ne 0 ]; then
        exit 1;
    fi
    DOCKER_IMAGE_URL="docker.xcoresigma.com/docker/siginfer-x86_64-nvidia:$LATEST_TAG"
else
    DOCKER_IMAGE_URL="docker.xcoresigma.com:80/docker/siginfer-x86_64-nvidia:$LATEST_TAG"
fi

ret=`docker ps -a | grep siginfer_nvidia_<<<TEST_TYPE>>>_${JOB_COUNT}`
if [ $? -eq 0 ]; then
  docker stop siginfer_nvidia_<<<TEST_TYPE>>>_${JOB_COUNT}
  docker rm siginfer_nvidia_<<<TEST_TYPE>>>_${JOB_COUNT}
fi

# Slave节点需要等待Master节点的HTTP Server启动完成......
if [ $NODE_RANK -ne 0 ]; then
  sleep 30
fi

# 设置超时时间(单位:秒, 1小时 = 3600秒)
TIMEOUT=10
START_TIME=$(date +%s)

# 目标空闲 GPU 数量
if [ $GPU_QUANITY -eq 16 ]; then
    TARGET_FREE_GPUS=8
else
    TARGET_FREE_GPUS=$GPU_QUANITY
fi

# 检查 nvidia-smi 命令是否存在
if ! command -v nvidia-smi &> /dev/null; then
    echo "错误: nvidia-smi 未找到，请确保 Nvidia GPU 驱动已安装"
    exit 1
fi

echo "开始扫描 GPU, 目标: 寻找 $TARGET_FREE_GPUS 张空闲 GPU..."

LOCKED_GPUS=""
while true; do
    # 检查是否超时
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
        echo "超时（${TIMEOUT}秒）未找到 $TARGET_FREE_GPUS 张空闲 GPU, 退出"
        exit 10
    fi

    # 使用 nvidia-smi 获取 GPU 使用情况
    GPU_INFO=($(nvidia-smi | awk '/Processes:/,/\+/{ if ($1 ~ /^[|]/ && $2 ~ /^[0-9]+$/) print $2 }'))
    # 去重
    GPU_INFO=($(echo "${GPU_INFO[@]}" | tr ' ' '\n' | sort -u))
    if [ $GPU_MODEL == "H100" ]; then
        # 过滤掉第3块和第4块L20 GPU卡, 对应ID是0, 1
        GPU_INFO=($(echo "${GPU_INFO[@]}" | sed -E 's/\b2\b//g' | sed -E 's/\b3\b//g' | sed -E 's/\s+/ /g' | xargs))
        for ((i=0; i<${#GPU_INFO[@]}; i++)); do
            GPU_INFO[$i]=$((GPU_INFO[$i]+2))
        done
    elif [ $GPU_MODEL == "L20" ]; then
        # 过滤掉第1块和第2块H100 GPU卡, 对应ID是2, 3
        GPU_INFO=($(echo "${GPU_INFO[@]}" | sed -E 's/\b0\b//g' | sed -E 's/\b1\b//g' | sed -E 's/\s+/ /g' | xargs))
        for ((i=0; i<${#GPU_INFO[@]}; i++)); do
            GPU_INFO[$i]=$((GPU_INFO[$i]-2))
        done
    fi

    # 检查使用中的 GPU 数量
    USE_COUNT=$(echo "${GPU_INFO[@]}" | wc -w)
    echo "当前使用中的 GPU 数量：$USE_COUNT, 索引: ${GPU_INFO[@]}"
    TOTAL_COUNT=$(nvidia-smi -L | wc -l)
    if [ $GPU_MODEL == "H100" ]; then
        ((TOTAL_COUNT-=2))
        FREE_COUNT=$(($TOTAL_COUNT-$USE_COUNT))
        FREE_GPU_INFO=($(seq 2 $(($TOTAL_COUNT+1)) | grep -vxFf <(printf "%s\\n" "${GPU_INFO[@]}")))
        # 如果找到足够的空闲 GPU, 则返回结果并退出
        if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
            # 只取需要的数量
            SELECTED_GPUS="${FREE_GPU_INFO[@]:0:$TARGET_FREE_GPUS}"
            echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 尝试锁定：${SELECTED_GPUS}"
            CUDA_VISIBLE_DEVICES=$(echo ${SELECTED_GPUS} | sed -E 's/\s+/\,/g')
            # 尝试原子性地获取所有GPU的锁
            if acquire_npu_locks_batch "$SERVER_NAME" "$SELECTED_GPUS" "$TASK_ID"; then
                echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${SELECTED_GPUS}"
                LOCKED_GPUS="$SELECTED_GPUS"
                break
            else
                echo "锁定失败（可能被其他任务占用），继续扫描......"
            fi
        fi
    elif [ $GPU_MODEL == "L20" ]; then
        ((TOTAL_COUNT-=2))
        FREE_COUNT=$(($TOTAL_COUNT-$USE_COUNT))
        FREE_GPU_INFO=($(seq 0 $(($TOTAL_COUNT-1)) | grep -vxFf <(printf "%s\\n" "${GPU_INFO[@]}")))
        # 如果找到足够的空闲 GPU, 则返回结果并退出
        if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
            # 只取需要的数量
            SELECTED_GPUS="${FREE_GPU_INFO[@]:0:$TARGET_FREE_GPUS}"
            echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 尝试锁定：${SELECTED_GPUS}"
            CUDA_VISIBLE_DEVICES=$(echo ${SELECTED_GPUS} | sed -E 's/\s+/\,/g')
            # 尝试原子性地获取所有GPU的锁
            if acquire_npu_locks_batch "$SERVER_NAME" "$SELECTED_GPUS" "$TASK_ID"; then
                echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${SELECTED_GPUS}"
                LOCKED_GPUS="$SELECTED_GPUS"
                break
            else
                echo "锁定失败（可能被其他任务占用），继续扫描......"
            fi
        fi
    else
        FREE_COUNT=$(($TOTAL_COUNT-$USE_COUNT))
        FREE_GPU_INFO=($(seq 0 $(($TOTAL_COUNT-1)) | grep -vxFf <(printf "%s\\n" "${GPU_INFO[@]}")))
        if [ <<<TEST_TYPE>>> == "PerformanceTest" ]; then
            if [ $TARGET_FREE_GPUS -gt 4 ]; then
                # 如果找到足够的空闲 GPU, 则返回结果并退出
                if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
                    # 只取需要的数量
                    SELECTED_GPUS="${FREE_GPU_INFO[@]:0:$TARGET_FREE_GPUS}"
                    echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 尝试锁定：${SELECTED_GPUS}"
                    CUDA_VISIBLE_DEVICES=$(echo ${SELECTED_GPUS} | sed -E 's/\s+/\,/g')
                    # 尝试原子性地获取所有GPU的锁
                    if acquire_npu_locks_batch "$SERVER_NAME" "$SELECTED_GPUS" "$TASK_ID"; then
                        echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${SELECTED_GPUS}"
                        LOCKED_GPUS="$SELECTED_GPUS"
                        break
                    else
                        echo "锁定失败（可能被其他任务占用），继续扫描......"
                    fi
                fi
            else
                # 如果找到足够的空闲 GPU，则需要按与 CPU1 和 CPU2 的通信关系进行分组
                if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
                    # 将空闲 GPU 按与 CPU1 和 CPU2 的通信关系分组
                    CPU_1_GROUP=()
                    CPU_2_GROUP=()
                    # 遍历 FREE_GPU_INFO 数组, 分配到对应组
                    for gpu in "${FREE_GPU_INFO[@]}"; do
                        if (( gpu < 4 )); then
                            CPU_1_GROUP+=("$gpu")  # GPU 0-3 与 CPU1 通信
                        else
                            CPU_2_GROUP+=("$gpu")  # GPU 4-7 与 CPU2 通信
                        fi
                    done
                    # 如果在 CPU1 组中找到足够的空闲 GPU, 则返回结果并退出
                    if [ "${#CPU_1_GROUP[@]}" -ge "$TARGET_FREE_GPUS" ]; then
                        # 只取需要的数量
                        SELECTED_GPUS="${CPU_1_GROUP[@]:0:$TARGET_FREE_GPUS}"
                        echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 尝试锁定：${SELECTED_GPUS}"
                        CUDA_VISIBLE_DEVICES=$(echo ${SELECTED_GPUS} | sed -E 's/\s+/\,/g')
                        # 尝试原子性地获取所有GPU的锁
                        if acquire_npu_locks_batch "$SERVER_NAME" "$SELECTED_GPUS" "$TASK_ID"; then
                            echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${SELECTED_GPUS}"
                            LOCKED_GPUS="$SELECTED_GPUS"
                            break
                        else
                            echo "锁定失败（可能被其他任务占用），继续扫描......"
                        fi
                    fi
                    # 如果在 CPU2 组中找到足够的空闲 GPU, 则返回结果并退出
                    if [ "${#CPU_2_GROUP[@]}" -ge "$TARGET_FREE_GPUS" ]; then
                        # 只取需要的数量
                        SELECTED_GPUS="${CPU_2_GROUP[@]:0:$TARGET_FREE_GPUS}"
                        echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 尝试锁定：${SELECTED_GPUS}"
                        CUDA_VISIBLE_DEVICES=$(echo ${SELECTED_GPUS} | sed -E 's/\s+/\,/g')
                        # 尝试原子性地获取所有GPU的锁
                        if acquire_npu_locks_batch "$SERVER_NAME" "$SELECTED_GPUS" "$TASK_ID"; then
                            echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${SELECTED_GPUS}"
                            LOCKED_GPUS="$SELECTED_GPUS"
                            break
                        else
                            echo "锁定失败（可能被其他任务占用），继续扫描......"
                        fi
                    fi
                fi
            fi
        else
            # 如果找到足够的空闲 GPU, 则返回结果并退出
            if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
                # 只取需要的数量
                SELECTED_GPUS="${FREE_GPU_INFO[@]:0:$TARGET_FREE_GPUS}"
                echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 尝试锁定：${SELECTED_GPUS}"
                CUDA_VISIBLE_DEVICES=$(echo ${SELECTED_GPUS} | sed -E 's/\s+/\,/g')
                # 尝试原子性地获取所有GPU的锁
                if acquire_npu_locks_batch "$SERVER_NAME" "$SELECTED_GPUS" "$TASK_ID"; then
                    echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${SELECTED_GPUS}"
                    LOCKED_GPUS="$SELECTED_GPUS"
                    break
                else
                    echo "锁定失败（可能被其他任务占用），继续扫描......"
                fi
            fi
        fi
    fi

    # 等待一段时间后重新扫描（例如 10 秒）
    echo "未找到足够的空闲 GPU, 10秒后重试..."
    sleep 10
done

echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
LOG_NAME="server_log_<<<TEST_TYPE>>>_$(date +'%Y%m%d_%H%M%S').log"

EXEC_COMMAND="docker run --name=siginfer_nvidia_<<<TEST_TYPE>>>_${JOB_COUNT} \
    --gpus all \
    --privileged \
    --cap-add=ALL \
    --network host \
    --pid=host \
    --shm-size="80g" \
    --volume /dev:/dev \
    --volume /home/weight:/home/weight \
    --ipc=host	\
    -u root \
    -e CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES    \
    -e SIG_LOG_LEVEL='warn,console_logger=info' \
    $DOCKER_IMAGE_URL"

<<<generated source code>>>

echo "$EXEC_COMMAND"

eval "$EXEC_COMMAND"
if [ $? -ne 0 ]; then
    exit 1;
fi

TIMEOUT_SECONDS=$((60*30)) # 设置启动超时时间为30分钟
if [ $NODE_RANK -eq 0 ]; then
    timeout $TIMEOUT_SECONDS tail -F $LOG_NAME | grep --line-buffered -m 1 -E "INFO:\s+Application startup complete\."
    EXIT_STATUS=$?
    if [ $EXIT_STATUS -eq 124 ]; then
        echo "模型启动超时（${TIMEOUT_SECONDS}秒）"
    elif [ $EXIT_STATUS -eq 0 ]; then
        echo ">>> Detected master service startup completion!"
    else
        echo "模型启动失败，退出状态码：$EXIT_STATUS"
    fi

    exit $EXIT_STATUS
else
    timeout $TIMEOUT_SECONDS tail -F $LOG_NAME | grep --line-buffered -m 8 -E "worker initialization done!"
    EXIT_STATUS=$?
    if [ $EXIT_STATUS -eq 124 ]; then
        echo "模型启动超时（${TIMEOUT_SECONDS}秒）"
    elif [ $EXIT_STATUS -eq 0 ]; then
        echo ">>> Detected worker service startup completion!"
    else
        echo "模型启动失败，退出状态码：$EXIT_STATUS"
    fi

    exit $EXIT_STATUS
fi

# 超时时间（30分钟）
# TIMEOUT=$((10 * 60))
# START_TIME=$(date +%s)

# while true; do
#     # 检查超时
#     CURRENT_TIME=$(date +%s)
#     ELAPSED=$((CURRENT_TIME - START_TIME))
#     if [ $ELAPSED -ge $TIMEOUT ]; then
#         echo ">>> 超时（${TIMEOUT}秒）。服务可能未正确启动。" >&2
#         exit 1
#     fi

#     # 检查日志
#     if tail -n 50 "$LOG_FILE" | grep -q "Engine core initialization failed" "$LOG_FILE"; then
#         echo ">>> 检测到服务启动失败！"
#         exit 5
#     fi

#     if tail -n 50 "$LOG_FILE" | grep -Eq "INFO:\s+Application startup complete\."; then
#         echo ">>> 检测到服务启动完成！"
#         exit 0
#     fi

#     sleep 5
# done
