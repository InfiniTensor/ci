#!/bin/bash

# 导入NPU锁管理器
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/npu_lock_manager_for_ci.sh"
LOCK_DIR="/home/zkjh/.npu_locks"
LOCK_FILE="server_config.lock"

# 接收参数
MODEL=$1
GPU_QUANITY=$2
SERVER_LIST=$3
NODE_RANK=$4
JOB_COUNT=$5
SESSION_ID=$6
VERSION=$7

# 生成唯一的任务ID
TASK_ID="<<<TEST_TYPE>>>_${MODEL}_${JOB_COUNT}"
JOB_ID="<<<TEST_TYPE>>>_${MODEL}_${SESSION_ID}_${JOB_COUNT}"
LOCAL_IP=$(hostname -I | xargs printf "%s\n" | head -n 1)
SERVER_NAME=$(echo $LOCAL_IP | sed 's/\./_/g')

# 设置清理函数，确保异常退出时释放锁
cleanup_locks() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "中止job executor测试任务......"
        if [ ! -z "$LOCKED_NPUS" ]; then
            echo "检测到异常退出（退出码: $exit_code），正在释放Server Config文件锁: ${LOCK_DIR}/${LOCK_FILE}"
            # 获取文件锁（阻塞）
            exec 200>"${LOCK_DIR}/${LOCK_FILE}"    # 打开文件描述符 200
            if ! flock -x 200; then    # 获取独占锁
                echo "无法获取锁，退出..."
            fi
            # 删除Server端配置信息，如果存在的话
            # sed -i "/${LOCAL_IP}:${JOB_ID}:/d" "${LOCK_DIR}/server_config.txt"
            new_config=`sed "/${LOCAL_IP}:${JOB_ID}:/d" "${LOCK_DIR}/server_config.txt"`
            echo "${new_config}" > "${LOCK_DIR}/server_config.txt"
            # 锁会自动在脚本退出或文件描述符关闭时释放
            exec 200>&-  # 关闭文件描述符
            echo "正在释放NPU锁: ${LOCKED_NPUS}"
            release_npu_locks_batch "$SERVER_NAME" "$LOCKED_NPUS" "$TASK_ID" "$SESSION_ID"
        fi
    else
        echo "正常退出（退出码: 0），保留NPU锁"
    fi
}

# 注册退出时的清理函数
trap cleanup_locks EXIT INT TERM

free_port=""

get_free_port() {
    local PORT_RANGE_START=20000
    local PORT_RANGE_END=20999

    for port in $(seq $PORT_RANGE_START $PORT_RANGE_END); do
        if ! lsof -i :"$port" >/dev/null 2>&1; then
            if [[ " ${server_ports[@]} " =~ " $port " ]]; then
                continue
            fi
            server_ports+=($port)
            free_port="$port"
            return
        fi
    done
    free_port=""
}

LATEST_TAG=""
if [ -z $VERSION ]; then
    # 先拿到所有 tag 并按字母升序
    TAGS=$(/home/zkjh/jfrog rt curl \
        --server-id=my-jcr \
        /api/docker/docker-local/v2/infiniTensor-aarch64-cambricon/tags/list \
    | jq -r '.tags[]' | sort)

    # 遍历每个 tag，查询 Storage API 并输出 tag + 创建时间
    for tag in $TAGS; do
    created=$(/home/zkjh/jfrog rt curl \
        --server-id=my-jcr \
        /api/storage/docker-local/infiniTensor-aarch64-cambricon/$tag \
        | jq -r '.created')
    echo "$tag $created"
    done > tag_dates.txt

    LATEST_TAG=$(sort -k2 -r tag_dates.txt | grep main- | head -n1 | awk '{print $1}')
    echo "The latest version : $LATEST_TAG"
else
    LATEST_TAG=$VERSION
    echo "The specified version : $LATEST_TAG"
fi

if [ "<<<TEST_TYPE>>>" != "UnitTest" ]; then
    docker pull docker.xcoresigma.com/docker/infiniTensor-aarch64-cambricon:$LATEST_TAG
    if [ $? -ne 0 ]; then
        exit 1;
    fi
fi

ret=`docker ps -a | grep infiniTensor_cambricon_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}`
if [ $? -eq 0 ]; then
  docker stop infiniTensor_cambricon_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}
  docker rm infiniTensor_cambricon_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}
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

# 检查 cnmon 命令是否存在
if ! command -v cnmon &> /dev/null; then
    echo "错误: cnmon 未找到，请确保 cambricon MLU590 驱动已安装"
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

    # 使用 cnmon 获取 GPU 使用情况
    GPU_INFO=($(cnmon | awk '/Processes:/,/\+/{ if ($1 ~ /^[|]/ && $2 ~ /^[0-9]+$/) print $2 }'))
    # 去重
    GPU_INFO=($(echo "${GPU_INFO[@]}" | tr ' ' '\n' | sort -u))
    # 检查使用中的 GPU 数量
    USE_COUNT=$(echo "${GPU_INFO[@]}" | wc -w)
    echo "当前使用中的 GPU 数量：$USE_COUNT, 索引: ${GPU_INFO[@]}"
    TOTAL_COUNT=$(cnmon -l | grep MLU | wc -l)
    FREE_COUNT=$(($TOTAL_COUNT-$USE_COUNT))
    FREE_GPU_INFO=($(seq 0 $(($TOTAL_COUNT-1)) | grep -vxFf <(printf "%s\\n" "${GPU_INFO[@]}")))
    echo "当前空闲 GPU 数量：$FREE_COUNT, 索引: ${FREE_GPU_INFO[@]}"
    # 如果找到足够的空闲 GPU, 则返回结果并退出
    if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
        echo "发现 $TARGET_FREE_GPUS 张空闲 GPU, 索引: ${FREE_GPU_INFO[@]}"
        echo "尝试锁定其中 $TARGET_FREE_GPUS 张 GPU"

        # 尝试原子性地获取所有NPU的锁
        if acquire_npu_locks_batch "$SERVER_NAME" "${FREE_GPU_INFO[*]}" "$TARGET_FREE_GPUS" "$TASK_ID" "$SESSION_ID" ACUQIRED_LOCKS; then
            echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${ACUQIRED_LOCKS[@]}"
            LOCKED_NPUS="${ACUQIRED_LOCKS[@]}"
            GPU_INFO=(${ACUQIRED_LOCKS[@]})
            break
        else
            echo "锁定失败（可能被其他任务占用），继续扫描......"
        fi
    fi

    # 等待一段时间后重新扫描（例如 10 秒）
    echo "未找到足够的空闲 GPU, 10秒后重试......"
    sleep 10
done

MLU_VISIBLE_DEVICES=$(echo "${GPU_INFO[@]}" | sed -E 's/\s+/\,/g')
echo "MLU_VISIBLE_DEVICES=$MLU_VISIBLE_DEVICES"

LOG_NAME="server_log_<<<TEST_TYPE>>>_$(date +'%Y%m%d_%H%M%S').log"

if [ "<<<TEST_TYPE>>>" != "UnitTest" ]; then
    MASTER_IP=`echo $SERVER_LIST | tr '_' '\n' | head -n 1`
    if [ $LOCAL_IP == $MASTER_IP ]; then        # 获取Master节点的端口号
        # 获取文件锁（阻塞）
        exec 200>"${LOCK_DIR}/${LOCK_FILE}"    # 打开文件描述符 200
        if ! flock -x 200; then    # 获取独占锁
            echo "无法获取锁，退出..."
            exit 1
        fi

        # 确保文件存在 & 权限正确
        if [ ! -f "${LOCK_DIR}/server_config.txt" ]; then
            touch "${LOCK_DIR}/server_config.txt"
        fi

        server_ports=(`cat "${LOCK_DIR}/server_config.txt" | grep $LOCAL_IP | awk -F ':' '{print $3}'`)

        get_free_port
        PORT=$free_port
        get_free_port
        PROMETHEUS_PORT=$free_port
        get_free_port
        MASTER_PORT=$free_port

        if [ -z $PORT ] || [ -z $PROMETHEUS_PORT ] || [ -z $MASTER_PORT ]; then
            exit 1
        fi

        echo "$LOCAL_IP:$JOB_ID:$PORT $PROMETHEUS_PORT $MASTER_PORT" >> "${LOCK_DIR}/server_config.txt"

        # 锁会自动在脚本退出或文件描述符关闭时释放
        exec 200>&-  # 关闭文件描述符
    else    # Slave节点同步到master节点的端口配置
        while true; do
            # 获取文件锁（阻塞）
            exec 200>"${LOCK_DIR}/${LOCK_FILE}"    # 打开文件描述符 200
            if ! flock -x 200; then    # 获取独占锁
                echo "无法获取锁，退出..."
                exit 1
            fi

            # 读取Master节点配置信息
            server_ports=`cat "${LOCK_DIR}/server_config.txt" | grep "${MASTER_IP}:${JOB_ID}:" | awk -F ':' '{print $3}' | tail -n 1`
            if [ ! -z "$server_ports" ]; then
                PORT=$(echo $server_ports | awk '{print $1}')
                PROMETHEUS_PORT=$(echo $server_ports | awk '{print $2}')
                MASTER_PORT=$(echo $server_ports | awk '{print $3}')
                # 锁会自动在脚本退出或文件描述符关闭时释放
                exec 200>&-  # 关闭文件描述符
                break
            fi

            # 锁会自动在脚本退出或文件描述符关闭时释放
            exec 200>&-  # 关闭文件描述符

            sleep 1
        done
    fi
fi

EXEC_COMMAND="docker run --name=infiniTensor_cambricon_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT} "
EXEC_COMMAND+="-e MLU_VISIBLE_DEVICES=$MLU_VISIBLE_DEVICES "
EXEC_COMMAND+=$(cat <<'EOF'
    <<<DOCKER_ARGS>>>
EOF
)

<<<generated source code>>>

echo "$EXEC_COMMAND"

eval "$EXEC_COMMAND"
if [ $? -ne 0 ]; then
    exit 1
fi

if [ "<<<TEST_TYPE>>>" != "UnitTest" ]; then
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
else
    exit 0
fi