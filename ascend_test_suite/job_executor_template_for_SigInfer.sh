#!/bin/bash

# 导入NPU锁管理器
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/npu_lock_manager.sh"
LOCK_DIR="/home/s_limingge/.npu_locks"

# 接收参数
MODEL=$1
GPU_QUANITY=$2
USE_PREFIX_CACHE=$3
SCHEDULE_POLICY=$4
SWAP_SPACE=$5
MASTER_IP=$6
NODE_RANK=$7
JOB_COUNT=$8
SESSION_ID=$9
VERSION=${10}

# 生成唯一的任务ID
TASK_ID="<<<TEST_TYPE>>>_${MODEL}_${JOB_COUNT}"
LOCAL_IP=$(hostname -I | awk '{print $1}')
SERVER_NAME=$(echo $LOCAL_IP | sed 's/\./_/g')

# 设置清理函数，确保异常退出时释放锁
cleanup_locks() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        if [ ! -z "$LOCKED_NPUS" ]; then
            rm -f "${LOCK_DIR}/job_${SESSION_ID}_${JOB_COUNT}"
            echo "检测到异常退出（退出码: $exit_code），正在释放NPU锁: ${LOCKED_NPUS}"
            release_npu_locks_batch "$SERVER_NAME" "$LOCKED_NPUS" "$TASK_ID" "$SESSION_ID"
        fi
    else
        echo "正常退出（退出码: 0），保留NPU锁"
    fi
}

# 注册退出时的清理函数
trap cleanup_locks EXIT INT TERM

server_ports=()
FREE_PORT=""

get_free_port() {
    local PORT_RANGE_START=20000
    local PORT_RANGE_END=20999

    for port in $(seq $PORT_RANGE_START $PORT_RANGE_END); do
        if ! lsof -i :"$port" >/dev/null 2>&1; then
            if [[ " ${server_ports[@]} " =~ " $port " ]]; then
                continue
            fi
            server_ports+=($port)
            FREE_PORT="$port"
            break
        fi
    done
}

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
        /api/docker/docker-local/v2/siginfer-aarch64-ascend/tags/list \
    | jq -r '.tags[]' | sort)

    # 遍历每个 tag，查询 Storage API 并输出 tag + 创建时间
    for tag in $TAGS; do
    created=$(/home/s_limingge/jfrog rt curl \
        --server-id=my-jcr \
        /api/storage/docker-local/siginfer-aarch64-ascend/$tag \
        | jq -r '.created')
    echo "$tag $created"
    done > tag_dates.txt

    LATEST_TAG=$(sort -k2 -r tag_dates.txt | grep main- | head -n1 | awk '{print $1}')
    echo "The latest version : $LATEST_TAG"
else
    LATEST_TAG=$VERSION
    echo "The specified version : $LATEST_TAG"
fi

docker pull docker.xcoresigma.com/docker/siginfer-aarch64-ascend:$LATEST_TAG
if [ $? -ne 0 ]; then
  exit 1;
fi

ret=`docker ps -a | grep siginfer_ascend_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}`
if [ $? -eq 0 ]; then
  docker stop siginfer_ascend_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}
  docker rm siginfer_ascend_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}
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

# 检查 npu-smi 命令是否存在
if ! command -v npu-smi &> /dev/null; then
    echo "错误: npu-smi 未找到，请确保 Ascend 910B 驱动已安装"
    exit 1
fi

echo "开始扫描 GPU, 目标: 寻找 $TARGET_FREE_GPUS 张空闲 GPU..."

LOCKED_NPUS=""
while true; do
    # 检查是否超时
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
        echo "超时（${TIMEOUT}秒）未找到 $TARGET_FREE_GPUS 张空闲 GPU, 退出"
        exit 10
    fi

    # 使用 npu-smi 获取 GPU 使用情况
    GPU_INFO=($(npu-smi info | grep "No\ running\ processes\ found\ in\ NPU" | awk '{print $8}'))
    # 检查空闲 GPU 数量
    FREE_COUNT=$(echo "${GPU_INFO[@]}" | wc -w)
    echo "当前空闲 GPU 数量：$FREE_COUNT, 索引: ${GPU_INFO[@]}"
    # 如果找到足够的空闲 GPU, 则返回结果并退出
    if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
        # 只取需要的数量
        SELECTED_GPUS="${GPU_INFO[@]:0:$TARGET_FREE_GPUS}"
        echo "发现 $TARGET_FREE_GPUS 张空闲 GPU, 尝试锁定: ${SELECTED_GPUS}"

        # 尝试原子性地获取所有NPU的锁
        if acquire_npu_locks_batch "$SERVER_NAME" "$SELECTED_GPUS" "$TASK_ID" "$SESSION_ID"; then
            echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${SELECTED_GPUS}"
            LOCKED_NPUS="$SELECTED_GPUS"
            GPU_INFO=($SELECTED_GPUS)
            break
        else
            echo "锁定失败（可能被其他任务占用），继续扫描......"
        fi
    fi

    # 等待一段时间后重新扫描（例如 10 秒）
    echo "未找到足够的空闲 GPU, 10秒后重试......"
    sleep 10
done

ASCEND_RT_VISIBLE_DEVICES=$(echo "${GPU_INFO[@]}" | sed -E 's/\s+/\,/g')
echo "ASCEND_RT_VISIBLE_DEVICES=$ASCEND_RT_VISIBLE_DEVICES"

LOG_NAME="server_log_<<<TEST_TYPE>>>_$(date +'%Y%m%d_%H%M%S').log"
get_free_port || exit 1
PORT=$FREE_PORT
echo "$PORT" > "${LOCK_DIR}/job_${SESSION_ID}_${JOB_COUNT}"
get_free_port || exit 1
PROMETHEUS_PORT=$FREE_PORT
get_free_port || exit 1
MASTER_PORT=$FREE_PORT

EXEC_COMMAND="docker run --name=siginfer_ascend_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT} \
     -u root  \
     -v /usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64 	\
     -v /usr/local/Ascend/driver/include:/usr/local/Ascend/driver/include	\
     -v /usr/local/Ascend/driver/tools:/usr/local/Ascend/driver/tools 	\
     -v /usr/local/Ascend/driver:/usr/local/Ascend/driver   \
     -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi   \
     -v /dev/davinci0:/dev/davinci0      \
     -v /dev/davinci1:/dev/davinci1      \
     -v /dev/davinci2:/dev/davinci2      \
     -v /dev/davinci3:/dev/davinci3      \
     -v /dev/davinci4:/dev/davinci4      \
     -v /dev/davinci5:/dev/davinci5      \
     -v /dev/davinci6:/dev/davinci6      \
     -v /dev/davinci7:/dev/davinci7      \
     --volume /home:/home   \
     --volume /home/weight/:/home/weight/    \
     --volume /shared/weights:/shared/weights    \
     --network host      \
     --privileged \
     --device=/dev/davinci_manager \
     --device=/dev/devmm_svm       \
     --device=/dev/hisi_hdc        \
     --ipc=host	\
     -e HCCL_SOCKET_IFNAME=enp67s0f0 \
     -e ASCEND_RT_VISIBLE_DEVICES=$ASCEND_RT_VISIBLE_DEVICES    \
     docker.xcoresigma.com/docker/siginfer-aarch64-ascend:$LATEST_TAG"

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
