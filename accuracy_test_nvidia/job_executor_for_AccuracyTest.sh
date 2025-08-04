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
VERSION=$9

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

    LATEST_TAG=$(sort -k2 -r tag_dates.txt | head -n1 | awk '{print $1}')
    echo "The latest version : $LATEST_TAG"
else
    LATEST_TAG=$VERSION
    echo "The specified version : $LATEST_TAG"
fi

docker pull docker.xcoresigma.com:80/docker/siginfer-x86_64-nvidia:$LATEST_TAG
if [ $? -ne 0 ]; then
    docker pull docker.xcoresigma.com/docker/siginfer-x86_64-nvidia:$LATEST_TAG
    if [ $? -ne 0 ]; then
        exit 1;
    fi
fi

ret=`docker ps -a | grep siginfer_nvidia_AccuracyTest_${JOB_COUNT}`
if [ $? -eq 0 ]; then
  docker stop siginfer_nvidia_AccuracyTest_${JOB_COUNT}
  docker rm siginfer_nvidia_AccuracyTest_${JOB_COUNT}
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
    # 检查使用中的 GPU 数量
    USE_COUNT=$(echo "${GPU_INFO[@]}" | wc -w)
    echo "当前使用中的 GPU 数量：$USE_COUNT, 索引: ${GPU_INFO[@]}"
    TOTAL_COUNT=$(nvidia-smi -L | wc -l)
    FREE_COUNT=$(($TOTAL_COUNT-$USE_COUNT))
    FREE_GPU_INFO=($(seq 0 $(($TOTAL_COUNT-1)) | grep -vxFf <(printf "%s\\n" "${GPU_INFO[@]}")))
    # 如果找到足够的空闲 GPU, 则返回结果并退出
    if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
        echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 索引：${FREE_GPU_INFO[@]}"
        break
    fi

    # 等待一段时间后重新扫描（例如 10 秒）
    echo "未找到足够的空闲 GPU, 10秒后重试..."
    sleep 10
done

CUDA_VISIBLE_DEVICES=$(echo ${FREE_GPU_INFO[@]} | sed -E 's/\s+/\,/g')
echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"

LOG_NAME="server_log_AccuracyTest_$(date +'%Y%m%d_%H%M%S').log"

EXEC_COMMAND="docker run --name=siginfer_nvidia_AccuracyTest_${JOB_COUNT} \
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
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model llama --tokenizer /home/weight/DeepSeek-R1/ -ep 8 --port 8000 --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port 27642 --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port 28880 --use-group-gemm --platform-type nvidia $USE_PREFIX_CACHE --tokens-per-prediction 2 $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/DeepSeek-R1/ -ep 8 --port 8000 --platform-type nvidia --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port 27642 --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port 28880 --use-group-gemm --platform-type nvidia $USE_PREFIX_CACHE --tokens-per-prediction 2 $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-V3-0324" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model llama --tokenizer /home/weight/DeepSeek-V3-0324 -ep 8 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 4096 --reset-max-seq-len 4096 --gpu-memory-utilization 0.98 --port 8000 --master-port 27642 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/DeepSeek-V3-0324 -ep 8 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 4096 --reset-max-seq-len 4096 --gpu-memory-utilization 0.98 --port 8000 --master-port 27642 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen3-235B-A22B-FP8" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model llama --tokenizer /shared/weights/Qwen3/Qwen/Qwen3-235B-A22B-FP8 -ep 4 --port 8000 --platform-type nvidia $USE_PREFIX_CACHE --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port 27642 --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port 28880 $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model llama --tokenizer /shared/weights/Qwen3/Qwen/Qwen3-235B-A22B-FP8 -ep 4 --port 8000 --platform-type nvidia $USE_PREFIX_CACHE --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 2048 --master-port 27642 --nnodes 1 --node-rank 0 --gpu-memory-utilization 0.98 --prometheus-port 28880 $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-awq" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /data/weight/DeepSeek-R1-awq/ --expert-parallel-size 8 --port 8000 --max-num-batched-tokens 2048 --gpu-memory-utilization 0.98 --platform-type nvidia $USE_PREFIX_CACHE --use-marlin --use-marlin-wna16 --weight-dtype=FP16 $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /data/weight/DeepSeek-R1-awq/ --expert-parallel-size 8 --port 8000 --max-num-batched-tokens 2048 --gpu-memory-utilization 0.98 --platform-type nvidia $USE_PREFIX_CACHE --use-marlin --use-marlin-wna16 --weight-dtype=FP16 $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Qwen-32B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/DeepSeek-R1-Distill-Qwen-32B -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/DeepSeek-R1-Distill-Qwen-32B -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Llama-70B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model llama --tokenizer /shared/weights/DeepSeek-R1-Distill-Llama-70B -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --master-port 27642 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --model llama --tokenizer /shared/weights/DeepSeek-R1-Distill-Llama-70B -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --master-port 27642 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Meta-Llama-3.1-70B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/Meta-Llama-3.1-70B-Instruct -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/Meta-Llama-3.1-70B-Instruct -tp 4 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-32B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /home/weight/Qwen2.5-32B-Instruct -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /home/weight/Qwen2.5-32B-Instruct -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "QwQ-32B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/QwQ-32B -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/QwQ-32B -tp 2 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-32B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/Qwen2.5-32B-Instruct-AWQ -tp 1 --disable-turbomind --use-marlin --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/Qwen2.5-32B-Instruct-AWQ -tp 1 --disable-turbomind --use-marlin --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
elif [ $model == "QwQ-32B-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/QwQ-32B-AWQ -tp 1 --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION"
    EXEC_COMMAND+=" --schedule-policy $SCHEDULE_POLICY --master-port 27642 --nnodes 1 --node-rank 0 --model llama --tokenizer /shared/weights/QwQ-32B-AWQ -tp 1 --weight-dtype=FP16 --max-num-batched-tokens 8192 --gpu-memory-utilization 0.9 --port 8000 --prometheus-port 8001 --platform-type nvidia $USE_PREFIX_CACHE $SWAP_SPACE_OPTION > $LOG_NAME 2>&1 &"
fi

eval "$EXEC_COMMAND"
if [ $? -ne 0 ]; then
    exit 1;
fi

tail -F $LOG_NAME | grep --line-buffered -m 1 -E "INFO:\s+Application startup complete\."
echo ">>> Detected master service startup completion!"

exit 0
