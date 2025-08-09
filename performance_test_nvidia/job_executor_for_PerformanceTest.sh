#!/bin/bash

# 接收参数
model=$1
GPU_QUANITY=$2
USE_PREFIX_CACHE=$3
SCHEDULE_POLICY=$4
SWAP_SPACE=$5
MASTER_IP=$6
NODE_RANK=$7
JOB_COUNT=$8
GPU_MODEL=$9
TEST_TYPE=${10}
VERSION=${11}

if [ $USE_PREFIX_CACHE -eq 1 ]; then
    USE_PREFIX_CACHE="--use-prefix-cache"
else
    USE_PREFIX_CACHE=""
fi

SWAP_SPACE_OPTION=""
if [ $SWAP_SPACE -gt 0 ]; then
    SWAP_SPACE_OPTION="--swap-space $SWAP_SPACE"
fi

if [ $TEST_TYPE == "smoke" ]; then
    MASTER_PORT=27642
    PORT=8000
    PROMETHEUS_PORT=28880
elif [ $TEST_TYPE == "performance" ]; then
    MASTER_PORT=$((9642+${JOB_COUNT}))
    PORT=$((8765+${JOB_COUNT}))
    PROMETHEUS_PORT=$((28765+${JOB_COUNT}))
elif [ $TEST_TYPE == "stability" ]; then
    MASTER_PORT=27642
    PORT=8000
    PROMETHEUS_PORT=28880
elif [ $TEST_TYPE == "accuracy" ]; then
    MASTER_PORT=27642
    PORT=8000
    PROMETHEUS_PORT=28880
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

    LATEST_TAG=$(sort -k2 -r tag_dates.txt | head -n1 | awk '{print $1}')
    echo "The latest version : $LATEST_TAG"
else
    LATEST_TAG=$VERSION
    echo "The specified version : $LATEST_TAG"
fi

docker pull docker.xcoresigma.com:80/docker/siginfer-x86_64-nvidia:$LATEST_TAG
if [ $? -ne 0 ]; then
    exit 1;
fi

ret=`docker ps -a | grep siginfer_nvidia_PerformanceTest_${JOB_COUNT}`
if [ $? -eq 0 ]; then
  docker stop siginfer_nvidia_PerformanceTest_${JOB_COUNT}
  docker rm siginfer_nvidia_PerformanceTest_${JOB_COUNT}
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
    if [ $GPU_MODEL == "H100" ]; then
        # 过滤掉第5块和第6块L20 GPU卡, 对应ID是0, 1
        GPU_INFO=$(echo "$GPU_INFO" | sed -E 's/\b4\b//g' | sed -E 's/\b5\b//g' | sed -E 's/\s+/ /g' | xargs)
    elif [ $GPU_MODEL == "L20" ]; then
        # 过滤掉第1块到第4块H100 GPU卡, 对应ID是2, 3, 4, 5
        GPU_INFO=$(echo "$GPU_INFO" | sed -E 's/\b0\b//g' | sed -E 's/\b1\b//g' | sed -E 's/\b2\b//g' | sed -E 's/\b3\b//g' | sed -E 's/\s+/ /g' | xargs)
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
            echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 索引：${FREE_GPU_INFO[@]}"
            CUDA_VISIBLE_DEVICES=$(echo ${FREE_GPU_INFO[@]} | sed -E 's/\s+/\,/g')
            break
        fi
    elif [ $GPU_MODEL == "L20" ]; then
        ((TOTAL_COUNT-=4))
        FREE_COUNT=$(($TOTAL_COUNT-$USE_COUNT))
        FREE_GPU_INFO=($(seq 0 $(($TOTAL_COUNT-1)) | grep -vxFf <(printf "%s\\n" "${GPU_INFO[@]}")))
        # 如果找到足够的空闲 GPU, 则返回结果并退出
        if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
            echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 索引：${FREE_GPU_INFO[@]}"
            CUDA_VISIBLE_DEVICES=$(echo ${FREE_GPU_INFO[@]} | sed -E 's/\s+/\,/g')
            break
        fi
    else
        FREE_COUNT=$(($TOTAL_COUNT-$USE_COUNT))
        FREE_GPU_INFO=($(seq 0 $(($TOTAL_COUNT-1)) | grep -vxFf <(printf "%s\\n" "${GPU_INFO[@]}")))
        if [ $TARGET_FREE_GPUS -gt 4 ]; then
            # 如果找到足够的空闲 GPU, 则返回结果并退出
            if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
                echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 索引：${FREE_GPU_INFO[@]}"
                CUDA_VISIBLE_DEVICES=$(echo ${FREE_GPU_INFO[@]} | sed -E 's/\s+/\,/g')
                break
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
                    echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 索引：${CPU_1_GROUP[@]}"
                    CUDA_VISIBLE_DEVICES=$(echo ${CPU_1_GROUP[@]} | sed -E 's/\s+/\,/g')
                    break
                fi
                # 如果在 CPU2 组中找到足够的空闲 GPU, 则返回结果并退出
                if [ "${#CPU_2_GROUP[@]}" -ge "$TARGET_FREE_GPUS" ]; then
                    echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 索引：${CPU_2_GROUP[@]}"
                    CUDA_VISIBLE_DEVICES=$(echo ${CPU_2_GROUP[@]} | sed -E 's/\s+/\,/g')
                    break
                fi
            fi
        fi
    fi

    # 等待一段时间后重新扫描（例如 10 秒）
    echo "未找到足够的空闲 GPU, 10秒后重试..."
    sleep 10
done

echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
LOG_NAME="server_log_PerformanceTest_$(date +'%Y%m%d_%H%M%S').log"

EXEC_COMMAND="docker run --name=siginfer_nvidia_PerformanceTest_${JOB_COUNT} \
    --gpus all \
    --privileged \
    --cap-add=ALL \
    --network host \
    --pid=host \
    --shm-size="80g" \
    --volume /home:/home \
    --volume /dev:/dev \
    --volume /home/weight:/home/weight \
    --volume /shared/weights:/shared/weights \
    --ipc=host	\
    -u root \
    -e CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES    \
    -e SIG_LOG_LEVEL='warn,console_logger=info' \
    docker.xcoresigma.com:80/docker/siginfer-x86_64-nvidia:$LATEST_TAG"

if [ $model == "DeepSeek-R1" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-R1 --tokenizer /home/weight/DeepSeek-R1/ --port $PORT --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port $PROMETHEUS_PORT --use-group-gemm -ep 8 --attn-dp-size 8 --tokens-per-prediction 2 $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model DeepSeek-R1 --tokenizer /home/weight/DeepSeek-R1/ --port $PORT --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port $PROMETHEUS_PORT --use-group-gemm -ep 8 --attn-dp-size 8 --tokens-per-prediction 2 $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-0528" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-R1-0528 --tokenizer /home/weight/DeepSeek-R1-0528/ --port $PORT --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.99 --prometheus-port $PROMETHEUS_PORT --use-group-gemm -ep 8 --split-embedding --tokens-per-prediction 2 $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model DeepSeek-R1-0528 --tokenizer /home/weight/DeepSeek-R1-0528/ --port $PORT --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.99 --prometheus-port $PROMETHEUS_PORT --use-group-gemm -ep 8 --split-embedding --tokens-per-prediction 2 $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-V3-0324" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-V3-0324 --tokenizer /home/weight/DeepSeek-V3-0324 -ep 8 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 4096 --reset-max-seq-len 4096 --gpu-memory-utilization 0.98 --port $PORT --master-port $MASTER_PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model DeepSeek-V3-0324 --tokenizer /home/weight/DeepSeek-V3-0324 -ep 8 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 4096 --reset-max-seq-len 4096 --gpu-memory-utilization 0.98 --port $PORT --master-port $MASTER_PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen3-235B-A22B-FP8" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen3-235B-A22B-FP8 --tokenizer /home/weight/Qwen3/Qwen3-235B-A22B-FP8 -ep 4 --port $PORT --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port $PROMETHEUS_PORT $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model Qwen3-235B-A22B-FP8 --tokenizer /home/weight/Qwen3/Qwen3-235B-A22B-FP8 -ep 4 --port $PORT --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port $PROMETHEUS_PORT $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-awq" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model DeepSeek-R1-awq --tokenizer /data/weight/DeepSeek-R1-awq/ --expert-parallel-size 8 --port $PORT --max-num-batched-tokens 2048 --gpu-memory-utilization 0.98 --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE --use-marlin --use-marlin-wna16 --weight-dtype=FP16 $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model DeepSeek-R1-awq --tokenizer /data/weight/DeepSeek-R1-awq/ --expert-parallel-size 8 --port $PORT --max-num-batched-tokens 2048 --gpu-memory-utilization 0.98 --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE --use-marlin --use-marlin-wna16 --weight-dtype=FP16 $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Qwen-32B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model DeepSeek-R1-Distill-Qwen-32B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-32B -tp 1 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model DeepSeek-R1-Distill-Qwen-32B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-32B -tp 1 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Llama-70B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model DeepSeek-R1-Distill-Llama-70B --tokenizer /home/weight/DeepSeek-R1-Distill-Llama-70B -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model DeepSeek-R1-Distill-Llama-70B --tokenizer /home/weight/DeepSeek-R1-Distill-Llama-70B -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Meta-Llama-3.1-70B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Meta-Llama-3.1-70B-Instruct --tokenizer /shared/weights/Meta-Llama-3.1-70B-Instruct -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Meta-Llama-3.1-70B-Instruct --tokenizer /shared/weights/Meta-Llama-3.1-70B-Instruct -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-32B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Qwen2.5-32B-Instruct --tokenizer /home/weight/Qwen2.5-32B-Instruct -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Qwen2.5-32B-Instruct --tokenizer /home/weight/Qwen2.5-32B-Instruct -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "QwQ-32B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model QwQ-32B --tokenizer /shared/weights/QwQ-32B -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model QwQ-32B --tokenizer /shared/weights/QwQ-32B -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-32B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Qwen2.5-32B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-32B-Instruct-AWQ -tp 1 --disable-turbomind --use-marlin --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Qwen2.5-32B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-32B-Instruct-AWQ -tp 1 --disable-turbomind --use-marlin --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "QwQ-32B-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model QwQ-32B-AWQ --tokenizer /shared/weights/QwQ-32B-AWQ -tp 1 --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model QwQ-32B-AWQ --tokenizer /shared/weights/QwQ-32B-AWQ -tp 1 --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-72B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Qwen2.5-72B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-72B-Instruct-AWQ -tp 1 --disable-turbomind --use-marlin --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Qwen2.5-72B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-72B-Instruct-AWQ -tp 1 --disable-turbomind --use-marlin --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-72B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Qwen2.5-72B-Instruct --tokenizer /home/weight/Qwen2.5-72B-Instruct -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --model Qwen2.5-72B-Instruct --tokenizer /home/weight/Qwen2.5-72B-Instruct -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port $PORT --prometheus-port $PROMETHEUS_PORT --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen3-235B-A22B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen3-235B-A22B --tokenizer /home/weight/Qwen3/Qwen3-235B-A22B -ep 8 --port $PORT --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port $PROMETHEUS_PORT $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model Qwen3-235B-A22B --tokenizer /home/weight/Qwen3/Qwen3-235B-A22B -ep 8 --port $PORT --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port $MASTER_PORT --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port $PROMETHEUS_PORT $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
fi

eval "$EXEC_COMMAND"
if [ $? -ne 0 ]; then
    exit 1;
fi

tail -F $LOG_NAME | grep --line-buffered -m 1 -E "INFO:\s+Application startup complete\."
echo ">>> Detected master service startup completion!"

exit 0
