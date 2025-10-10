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
VERSION=${10}

if [ $USE_PREFIX_CACHE -eq 1 ]; then
    USE_PREFIX_CACHE="--use-prefix-cache"
else
    USE_PREFIX_CACHE=""
fi

SWAP_SPACE_OPTION=""
if [ $SWAP_SPACE -gt 0 ]; then
    SWAP_SPACE_OPTION="--swap-space $SWAP_SPACE"
fi

LATEST_TAG=$VERSION
DOCKER_IMAGE_URL="docker.xcoresigma.com/docker/siginfer-x86_64-tianshu:$LATEST_TAG"

ret=`docker ps -a | grep siginfer_tianshu_SmokeTest_${JOB_COUNT}`
if [ $? -eq 0 ]; then
  docker stop siginfer_tianshu_SmokeTest_${JOB_COUNT}
  docker rm siginfer_tianshu_SmokeTest_${JOB_COUNT}
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

echo "开始扫描 GPU, 目标: 寻找 $TARGET_FREE_GPUS 张空闲 GPU..."

while true; do
    # 检查是否超时
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
        echo "超时（${TIMEOUT}秒）未找到 $TARGET_FREE_GPUS 张空闲 GPU, 退出"
        exit 10
    fi

    # 使用 ixsmi 获取 GPU 使用情况
    GPU_INFO=($(docker exec automation_test ixsmi | awk '/Processes:/,/\+/{ if ($1 ~ /^[|]/ && $2 ~ /^[0-9]+$/) print $2 }'))
    # 去重
    GPU_INFO=($(echo "${GPU_INFO[@]}" | tr ' ' '\n' | sort -u))
    # 检查使用中的 GPU 数量
    USE_COUNT=$(echo "${GPU_INFO[@]}" | wc -w)
    echo "当前使用中的 GPU 数量：$USE_COUNT, 索引: ${GPU_INFO[@]}"
    TOTAL_COUNT=$(docker exec automation_test ixsmi -L | wc -l)
    FREE_COUNT=$(($TOTAL_COUNT-$USE_COUNT))
    FREE_GPU_INFO=($(seq 0 $(($TOTAL_COUNT-1)) | grep -vxFf <(printf "%s\\n" "${GPU_INFO[@]}")))
    if [ SmokeTest == "PerformanceTest" ]; then
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
    else
        # 如果找到足够的空闲 GPU, 则返回结果并退出
        if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
            echo "成功找到 $TARGET_FREE_GPUS 张空闲 GPU, 索引：${FREE_GPU_INFO[@]}"
            CUDA_VISIBLE_DEVICES=$(echo ${FREE_GPU_INFO[@]} | sed -E 's/\s+/\,/g')
            break
        fi
    fi

    # 等待一段时间后重新扫描（例如 10 秒）
    echo "未找到足够的空闲 GPU, 10秒后重试..."
    sleep 10
done

echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
LOG_NAME="server_log_SmokeTest_$(date +'%Y%m%d_%H%M%S').log"

EXEC_COMMAND="docker run --name=siginfer_tianshu_SmokeTest_${JOB_COUNT} \
    --network host \
    --pid=host \
    --ipc=host	\
    --shm-size="80g" \
    -v /nfs2/weight:/home/weight \
    -v /usr/src:/usr/src \
    -v /lib/modules:/lib/modules \
    -v /dev:/dev \
    --privileged \
    --cap-add=ALL \
    --env LICENSE_LOCATION=/SigInfer/lib/trial-20260101.lic \
    -e CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES \
    -e SIG_LOG_LEVEL='warn,console_logger=info' \
    $DOCKER_IMAGE_URL"

PORT=$((8000+${JOB_COUNT}))
PROMETHEUS_PORT=$((26541+${JOB_COUNT}))
MASTER_PORT=$((27642+${JOB_COUNT}))
LOG_NAME="server_log_SmokeTest_$(date +'%Y%m%d_%H%M%S').log"

if [ $model == "DeepSeek-R1-Distill-Qwen-1.5B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-R1-Distill-Qwen-1.5B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-1.5B -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model DeepSeek-R1-Distill-Qwen-1.5B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-1.5B -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Qwen-7B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-R1-Distill-Qwen-7B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-7B -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model DeepSeek-R1-Distill-Qwen-7B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-7B -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Qwen-14B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-R1-Distill-Qwen-14B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-14B -tp 2 --port $PORT --platform-type tianshu --block-size 16 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model DeepSeek-R1-Distill-Qwen-14B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-14B -tp 2 --port $PORT --platform-type tianshu --block-size 16 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Qwen-32B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-R1-Distill-Qwen-32B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-32B -tp 4 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model DeepSeek-R1-Distill-Qwen-32B --tokenizer /home/weight/DeepSeek-R1-Distill-Qwen-32B -tp 4 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Llama-8B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-R1-Distill-Llama-8B --tokenizer /home/weight/DeepSeek-R1-Distill-Llama-8B -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model DeepSeek-R1-Distill-Llama-8B --tokenizer /home/weight/DeepSeek-R1-Distill-Llama-8B -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "DeepSeek-R1-Distill-Llama-70B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model DeepSeek-R1-Distill-Llama-70B --tokenizer /home/weight/DeepSeek-R1-Distill-Llama-70B -tp 8 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model DeepSeek-R1-Distill-Llama-70B --tokenizer /home/weight/DeepSeek-R1-Distill-Llama-70B -tp 8 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Meta-Llama-3.1-8B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Meta-Llama-3.1-8B-Instruct --tokenizer /home/weight/Meta-Llama-3.1-8B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Meta-Llama-3.1-8B-Instruct --tokenizer /home/weight/Meta-Llama-3.1-8B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Meta-Llama-3.1-70B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Meta-Llama-3.1-70B-Instruct --tokenizer /home/weight/Meta-Llama-3.1-70B-Instruct -tp 8 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Meta-Llama-3.1-70B-Instruct --tokenizer /home/weight/Meta-Llama-3.1-70B-Instruct -tp 8 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-0.5B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-0.5B-Instruct --tokenizer /home/weight/Qwen2.5-0.5B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-0.5B-Instruct --tokenizer /home/weight/Qwen2.5-0.5B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-1.5B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-1.5B-Instruct --tokenizer /home/weight/Qwen2.5-1.5B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-1.5B-Instruct --tokenizer /home/weight/Qwen2.5-1.5B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-3B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-3B-Instruct --tokenizer /home/weight/Qwen2.5-3B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-3B-Instruct --tokenizer /home/weight/Qwen2.5-3B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-7B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-7B-Instruct --tokenizer /home/weight/Qwen2.5-7B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-7B-Instruct --tokenizer /home/weight/Qwen2.5-7B-Instruct -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-14B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-14B-Instruct --tokenizer /home/weight/Qwen2.5-14B-Instruct -tp 2 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-14B-Instruct --tokenizer /home/weight/Qwen2.5-14B-Instruct -tp 2 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-32B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-32B-Instruct --tokenizer /home/weight/Qwen2.5-32B-Instruct -tp 4 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-32B-Instruct --tokenizer /home/weight/Qwen2.5-32B-Instruct -tp 4 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-72B-Instruct" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-72B-Instruct --tokenizer /home/weight/Qwen2.5-72B-Instruct -tp 8 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-72B-Instruct --tokenizer /home/weight/Qwen2.5-72B-Instruct -tp 8 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "QwQ-32B" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model QwQ-32B --tokenizer /home/weight/QwQ-32B -tp 4 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model QwQ-32B --tokenizer /home/weight/QwQ-32B -tp 4 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-0.5B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-0.5B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-0.5B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-0.5B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-0.5B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-1.5B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-1.5B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-1.5B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-1.5B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-1.5B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-3B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-3B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-3B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-3B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-3B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-7B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-7B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-7B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-7B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-7B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-14B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-14B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-14B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-14B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-14B-Instruct-AWQ -tp 1 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-32B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-32B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-32B-Instruct-AWQ -tp 2 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-32B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-32B-Instruct-AWQ -tp 2 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "Qwen2.5-72B-Instruct-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model Qwen2.5-72B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-72B-Instruct-AWQ -tp 4 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model Qwen2.5-72B-Instruct-AWQ --tokenizer /home/weight/Qwen2.5-72B-Instruct-AWQ -tp 4 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
elif [ $model == "QwQ-32B-AWQ" ]; then
    echo "SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh --model QwQ-32B-AWQ --tokenizer /home/weight/QwQ-32B-AWQ -tp 2 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT"
    EXEC_COMMAND+=" --model QwQ-32B-AWQ --tokenizer /home/weight/QwQ-32B-AWQ -tp 2 --port $PORT --platform-type tianshu --block-size 128 --weight-dtype=FP16 --ignore-eos --max-num-batched-tokens 8192 --prometheus-port $PROMETHEUS_PORT --gpu-memory-utilization 0.9 $SWAP_SPACE_OPTION --prometheus-port $PROMETHEUS_PORT > $LOG_NAME 2>&1 &"
fi

echo "服务启动命令:"
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
