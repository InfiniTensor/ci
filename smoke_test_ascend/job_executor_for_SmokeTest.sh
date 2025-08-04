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

    LATEST_TAG=$(sort -k2 -r tag_dates.txt | head -n1 | awk '{print $1}')
    echo "The latest version : $LATEST_TAG"
else
    LATEST_TAG=$VERSION
    echo "The specified version : $LATEST_TAG"
fi

docker pull docker.xcoresigma.com/docker/siginfer-aarch64-ascend:$LATEST_TAG
if [ $? -ne 0 ]; then
  exit 1;
fi

ret=`docker ps -a | grep siginfer_ascend_SmokeTest_${JOB_COUNT}`
if [ $? -eq 0 ]; then
  docker stop siginfer_ascend_SmokeTest_${JOB_COUNT}
  docker rm siginfer_ascend_SmokeTest_${JOB_COUNT}
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

# Slave节点需要等待Master节点的HTTP Server启动完成......
if [ $NODE_RANK -ne 0 ]; then
  sleep 30
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

    # 使用 npu-smi 获取 GPU 使用情况
    GPU_INFO=$(npu-smi info | grep "No\ running\ processes\ found\ in\ NPU" | awk '{print $8}')
    # 检查空闲 GPU 数量
    FREE_COUNT=$(echo "$GPU_INFO" | wc -w)
    echo "当前空闲 GPU 数量：$FREE_COUNT, 索引: $GPU_INFO"
    # 如果找到足够的空闲 GPU, 则返回结果并退出
    if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
        echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 索引：$GPU_INFO"
        break
    fi

    # 等待一段时间后重新扫描（例如 10 秒）
    echo "未找到足够的空闲 GPU, 10秒后重试..."
    sleep 10
done

ASCEND_RT_VISIBLE_DEVICES=$(echo $GPU_INFO | sed -E 's/\s+/\,/g')
echo "ASCEND_RT_VISIBLE_DEVICES=$ASCEND_RT_VISIBLE_DEVICES"

LOG_NAME="server_log_SmokeTest_$(date +'%Y%m%d_%H%M%S').log"

EXEC_COMMAND="docker run --name=siginfer_ascend_SmokeTest_${JOB_COUNT} \
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
     -u root \
     -e ASCEND_RT_VISIBLE_DEVICES=$ASCEND_RT_VISIBLE_DEVICES    \
     docker.xcoresigma.com/docker/siginfer-aarch64-ascend:$LATEST_TAG"

if [ $model == "DeepSeek-R1-0528" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --port $((6543+$JOB_COUNT)) --weight-dtype=FP16 --platform-type ascend --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 2 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --port $((6543+$JOB_COUNT)) --weight-dtype=FP16 --platform-type ascend --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 2 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-W8A8" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/DeepSeek-R1-Channel-INT8/ -tp $GPU_QUANITY --port $((6543+$JOB_COUNT)) --weight-dtype=FP16 --platform-type ascend --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 2 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/DeepSeek-R1-Channel-INT8/ -tp $GPU_QUANITY --port $((6543+$JOB_COUNT)) --weight-dtype=FP16 --platform-type ascend --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 2 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --port $((6543+$JOB_COUNT)) --platform-type ascend --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) $USE_PREFIX_CACHE --nnodes 1 --node-rank $NODE_RANK --quantization awq --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --port $((6543+$JOB_COUNT)) --platform-type ascend --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) $USE_PREFIX_CACHE --nnodes 1 --node-rank $NODE_RANK --quantization awq --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Llama-70B" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Qwen-32B" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen3-30B-A3B" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/Qwen3/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/Qwen3/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-32B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-72B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Meta-Llama-3.1-70B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) $USE_PREFIX_CACHE --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT)) --nnodes 1 --node-rank $NODE_RANK --platform-type ascend $SWAP_SPACE_OPTION --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Qwen-14B" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Llama-8B" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Meta-Llama-3.1-8B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-0.5B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-1.5B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-3B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-7B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-14B-Instruct" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY  --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY  --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "QwQ-32B" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY  --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY  --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-0.5B-Instruct-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-1.5B-Instruct-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-3B-Instruct-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-7B-Instruct-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-14B-Instruct-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-32B-Instruct-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-72B-Instruct-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "QwQ-32B-AWQ" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen3-32B" ]; then
    echo "./start.sh --model llama --tokenizer /home/weight/Qwen3/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT))"
    EXEC_COMMAND+=" --model llama --tokenizer /home/weight/Qwen3/$model -tp $GPU_QUANITY --block-size 128 --weight-dtype=FP16 --schedule-policy $SCHEDULE_POLICY --max-num-batched-tokens 8192 --port $((6543+$JOB_COUNT)) --use-prefix-cache --master-addr $MASTER_IP --master-port $((8438+$JOB_COUNT))  --nnodes 1 --node-rank $NODE_RANK --platform-type ascend --prometheus-port $((8321+$JOB_COUNT)) > $LOG_NAME 2>&1 &"
fi

eval "$EXEC_COMMAND"
if [ $? -ne 0 ]; then
  exit 1;
fi

if [ $NODE_RANK -eq 0 ]; then
    tail -F $LOG_NAME | grep --line-buffered -m 1 -E "INFO:\s+Application startup complete\."
    echo ">>> Detected master service startup completion!"
else
    tail -F $LOG_NAME | grep --line-buffered -m 8 -E "worker initialization done!"
    echo ">>> Detected worker service startup completion!"
fi

exit 0
