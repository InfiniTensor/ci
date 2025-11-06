#!/bin/bash

# 接收参数
send_report=$1
server_list=($2)
candidate_models=$3
job_count=$4
TEST_TYPE=$5
ENGINE_TYPE=$6

if [ $TEST_TYPE == "Performance" ]; then
    TEST_PARAM=$7
    version=$8
else
    version=$7
fi

model_list_for_A800=(DeepSeek-R1-Distill-Qwen-32B:2:A800 DeepSeek-R1-Distill-Llama-70B:4:A800 Meta-Llama-3.1-70B-Instruct:4:A800 Qwen2.5-32B-Instruct:2:A800 QwQ-32B:2:A800 Qwen2.5-32B-Instruct-AWQ:1:A800 QwQ-32B-AWQ:1:A800)
model_list_for_H100=(DeepSeek-R1-Distill-Qwen-32B:1:H100 DeepSeek-R1-Distill-Llama-8B:1:H100 DeepSeek-R1-Distill-Llama-70B:4:H100 Qwen3-32B-FP8:2:H100 DeepSeek-R1-AWQ:8:H100)
model_list_for_H20=(DeepSeek-V3-0324:8:H20 DeepSeek-R1:8:H20 DeepSeek-R1-0528:8:H20 Qwen3-235B-A22B:8:H20 Qwen3-235B-A22B-FP8:4:H20 Qwen3-32B:1:H20 Qwen3-32B-FP8:1:H20 DeepSeek-R1-Distill-Qwen-1.5B:1:H20 DeepSeek-R1-Distill-Qwen-32B:1:H20 DeepSeek-R1-Distill-Llama-8B:1:H20 DeepSeek-R1-Distill-Llama-70B:4:H20 Meta-Llama-3.1-8B-Instruct:1:H20 Meta-Llama-3.1-70B-Instruct:4:H20 Qwen2.5-0.5B-Instruct:1:H20 Qwen2.5-72B-Instruct:4:H20 QwQ-32B:2:H20 Qwen2.5-0.5B-Instruct-AWQ:1:H20 Qwen2.5-72B-Instruct-AWQ:1:H20 QwQ-32B-AWQ:1:H20 DeepSeek-R1-AWQ:8:H20 DeepSeek-R1-Distill-Qwen-32B:2:H20 Qwen2.5-32B-Instruct-AWQ:1:H20 DeepSeek-V3.1:8:H20)
model_list_for_H800=(DeepSeek-V3.1:8:H800)
model_list_for_L20=(Meta-Llama-3.1-70B-Instruct_L-Series:8:L20 Qwen2.5-32B-Instruct_L-Series:4:L20 Qwen2.5-72B-Instruct_L-Series:4:L20 QwQ-32B_L-Series:4:L20 Qwen2.5-72B-Instruct-AWQ_L-Series:2:L20 Qwen3-32B-FP8_L-Series:2:L20)

full_model_list=(${model_list_for_A800[@]} ${model_list_for_H100[@]} ${model_list_for_H20[@]} ${model_list_for_H800[@]} ${model_list_for_L20[@]})
curr_dir=$(pwd)
log_name_suffix=${TASK_START_TIME}

declare -A A800_server_list=(
    ["10.208.130.44"]="A800-001"
)

declare -A H20_server_list=(
    ["10.9.1.14"]="H20-001"
)

declare -A H100_server_list=(
    ["192.168.100.106"]="H100-001"
)

declare -A L20_server_list=(
    ["192.168.100.106"]="L20-001"
)

declare -A H800_server_list=(
    # ["10.9.1.54"]="H800-001"
    ["10.9.1.62"]="H800-002"
)

declare -A local_ip_map=(
    ["10.208.130.44"]="10.208.130.44"
    ["10.9.1.14"]="172.31.0.2"
    ["192.168.100.106"]="192.168.100.106"
    ["10.9.1.54"]="172.16.28.34"
    ["10.9.1.62"]="172.16.21.36"
)

if [ -z $send_report ]; then
    echo "Missing parameter!"
    exit 1
elif [[ ! "$send_report" =~ ^[0-9]+$ ]] || [[ $send_report -ne 1 && $send_report -ne 0 ]]; then
    echo "Parameter 1 is worng!"
    exit 1
fi

if [ -z $server_list ]; then
    echo "Missing parameters!"
    exit 1
fi

# 存储 Docker 容器名称
declare -a DOCKER_CONTAINER_NAMES

# 从数组中删除指定元素的辅助函数
remove_container_from_array() {
    local value_to_remove=$1
    local new_array=()
    
    for item in "${DOCKER_CONTAINER_NAMES[@]}"; do
        if [ "$item" != "$value_to_remove" ]; then
            new_array+=("$item")
        fi
    done
    
    DOCKER_CONTAINER_NAMES=("${new_array[@]}")
    echo "已从跟踪列表中删除容器: $value_to_remove"
}

# 标志变量，用于跟踪是否由信号中断
INTERRUPTED=0

# 统一的清理函数 - 同时处理 NPU 锁、本地容器和远程容器
cleanup_all_resources() {
    echo ""
    echo "=========================================="
    echo "siginfer_ascend_test.sh 退出，开始清理资源..."
    echo "=========================================="
    
    # 1. 清理本地 Docker 容器
    if [ ${#DOCKER_CONTAINER_NAMES[@]} -gt 0 ]; then
        echo "正在清理本地 Docker 容器..."
        for container_name in "${DOCKER_CONTAINER_NAMES[@]}"; do
            if [ ! -z "$container_name" ]; then
                echo "  停止容器: $container_name"
                docker stop "$container_name" 2>/dev/null || true
                # docker rm -f "$container_name" 2>/dev/null || true
            fi
        done
        echo "本地容器清理完成"
    fi
    
    # 2. 释放 NPU 锁
    if [ -v model ]; then
        echo "正在释放 NPU 锁..."
        source $curr_dir/npu_lock_manager.sh
        for ip in ${server_list[@]}; do
            SERVER_NAME=$(echo ${local_ip_map[$ip]} | sed 's/\./_/g')
            release_npu_locks_batch "$SERVER_NAME" "0 1 2 3 4 5 6 7" "${TEST_TYPE}Test_${model}_${job_count}"
        done
        echo "NPU 锁释放完成"
    fi

    # 3. 清理远程 Docker 容器
    for ip in ${server_list[@]}; do
        ssh -o ConnectionAttempts=3 s_limingge@$ip "
            name=siginfer_nvidia_${TEST_TYPE}Test_${job_count}
            if [ ! -z \"\$\(docker ps -a | grep \$name\)\" ]; then
                docker stop \$name
                docker rm \$name
            fi
        "
    done
    
    echo "=========================================="
    echo "资源清理完成"
    echo "=========================================="

    # 如果是由于信号中断，则退出进程
    if [ $INTERRUPTED -eq 1 ]; then
        echo "进程被中断，退出..."
        exit 130  # 130 是 Ctrl+C 的标准退出码 (128 + SIGINT的2)
    fi
}

# 信号处理函数
handle_interrupt() {
    INTERRUPTED=1
    cleanup_all_resources
}

# 注册信号处理函数
trap handle_interrupt SIGINT SIGTERM
# EXIT 信号仍然调用 cleanup（正常退出时 INTERRUPTED=0，不会额外 exit）
trap cleanup_all_resources EXIT

model_list=()

if [ ! -z "$candidate_models" ]; then
    for candidate_item in $candidate_models; do
        candidate_model=`echo "$candidate_item" | awk -F : '{print $1}'`
        candidate_quanity=`echo "$candidate_item" | awk -F : '{print $2}'`
        candidate_gpu=`echo "$candidate_item" | awk -F : '{print $3}'`
        for item in "${full_model_list[@]}"; do
            model=`echo "$item" | awk -F : '{print $1}'`
            quanity=`echo "$item" | awk -F : '{print $2}'`
            gpu=`echo "$item" | awk -F : '{print $3}'`
            if [[ "$model" =~ ^$candidate_model$ ]] && [[ "$quanity" =~ ^$candidate_quanity$ ]] && [[ "$gpu" =~ ^$candidate_gpu$ ]]; then
                model_list+=($item)
            fi
        done
    done
else
    model_list=("${full_model_list[@]}")
fi

echo "*************开始执行${TEST_TYPE}测试任务，日期时间:$(date +"%Y%m%d_%H%M%S")***************"
echo "测试模型列表: ${model_list[@]}"

if [ -z $version ]; then
    echo "推理引擎版本: Latest"
else
    echo "推理引擎版本: ${version}"
fi

test_type=$(echo "${TEST_TYPE}" | tr '[:upper:]' '[:lower:]')
processed_models="${curr_dir}/logs/${test_type}/processed_models_${log_name_suffix}"
touch ${processed_models}

# schedule_policies=('DynamicSplitFuseV2' 'PrefillFirst')
schedule_policies=('DynamicSplitFuseV2')
ret_code=0

# for option in 'DynamicSplitFuseV2' 'PrefillFirst'; do
for option in "${schedule_policies[@]}"; do
    use_prefix_cache_flag=1
    for ((i=1; i<=2; i=i+1)); do
        swap_space=40
        for ((j=1; j<=1; j=j+1)); do
            for item in "${model_list[@]}"; do
                model=`echo "$item" | awk -F : '{print $1}'`
                gpu_quantity=`echo "$item" | awk -F : '{print $2}'`
                gpu_model=`echo "$item" | awk -F : '{print $3}'`
                
                # 模型已经测试过了，检查下一个
                if [ $use_prefix_cache_flag -gt 0 ]; then
                    if [ $swap_space -eq 0 ]; then
                        if [ ! -z `cat ${processed_models} | grep -w ${model}_${option}_use-prefix-cache` ]; then
                            continue
                        fi
                    else
                        if [ ! -z `cat ${processed_models} | grep -w ${model}_${option}_use-prefix-cache_swap-space` ]; then
                            continue
                        fi
                    fi
                else
                    if [ $swap_space -eq 0 ]; then
                        if [ ! -z `cat ${processed_models} | grep -w ${model}_${option}` ]; then
                            continue
                        fi
                    else
                        if [ ! -z `cat ${processed_models} | grep -w ${model}_${option}_swap-space` ]; then
                            continue
                        fi
                    fi
                fi

                filename=${log_name_suffix}_${model}_
                if [ $use_prefix_cache_flag -eq 1 ]; then
                    if [ $swap_space -eq 0 ]; then
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option, --use-prefix-cache"
                        filename+=${option}"_use-prefix-cache"
                    else
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option, --use-prefix-cache, --swap-space=40"
                        filename+=${option}"_use-prefix-cache_swap-space"
                    fi
                else
                    if [ $swap_space -eq 0 ]; then 
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option"
                        filename+=${option}
                    else
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option, --swap-space=40"
                        filename+=${option}"_swap-space"
                    fi
                fi

                cd $curr_dir

                if [ $TEST_TYPE != "Accuracy" ]; then
                    filename+=".log"
                fi

                echo "尝试同时在${server_list[@]}服务器上面启动测试......"
                
                unset pid_map
                declare -A pid_map
                seq_num=0
                # 依次在所有服务器上面启动任务
                for ip in ${server_list[@]}; do
                    echo "启动第${seq_num}台服务器: $ip......"

                    if [ $ip == ${server_list[0]} ]; then
                        local_master_ip=$ip
                    fi

                    if [ $TEST_TYPE == "Smoke" ]; then
                        ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@$ip /home/s_limingge/job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $gpu_model $version > "$curr_dir/logs/smoke/${filename}_${seq_num}" &
                        pid_map[$!]=$ip
                    else
                        ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@$ip /home/s_limingge/job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $gpu_model $version &
                        pid_map[$!]=$ip
                    fi

                    ((seq_num++))
                done

                success=0
                # 等待所有服务器任务启动完成
                remaining=${#server_list[@]}
                while (( remaining > 0 )); do
                    wait -n -p done_pid
                    err=$?
                    
                    if [ -v pid_map[$done_pid] ]; then
                        echo "任务启动结束，服务器：${pid_map[$done_pid]} (PID=$done_pid)"
                        
                        if [ $err -ne 0 ]; then
                            if [ $err -eq 10 ]; then
                                echo "${pid_map[$done_pid]}暂无资源, 中止当前模型测试任务，尝试进行下一个测试任务......"
                            else
                                echo "${pid_map[$done_pid]}测试环境配置失败, 中止当前模型测试任务，尝试进行下一个测试任务......"
                            fi
                            
                            # 启动失败，清理工作
                            for ip in ${server_list[@]}; do
                                ssh -o ConnectionAttempts=3 s_limingge@$ip docker stop siginfer_nvidia_${TEST_TYPE}Test_${job_count}
                                ssh -o ConnectionAttempts=3 s_limingge@$ip docker rm siginfer_nvidia_${TEST_TYPE}Test_${job_count}
                            done

                            ret_code=$err
                            success=1
                            break
                        fi
                    fi

                    ((remaining--))
                done

                # 任务启动失败
                if [ $success -eq 1 ]; then
                    continue
                fi

                echo "开始执行模型${TEST_TYPE}测试任务......"

                if [ $TEST_TYPE == "Performance" ]; then
                    if [ $model == "Qwen3-235B-A22B" ] || [ $model == "Qwen3-235B-A22B-FP8" ] || [ $model == "Qwen3-32B-FP8" ]; then
                        data_path="/home/weight/Qwen3"
                    elif [ $model == "QwQ-32B" ] || [ $model == "QwQ-32B-AWQ" ]; then
                        data_path="/home/weight/Qwen"
                    else
                        data_path="/home/weight"
                    fi

                    if [ $TEST_PARAM == "Random" ]; then
                        multiplier=4
                        concurrency_list=(1 5 10 20 50 100 150)
                        length_pairs=(
                            "128:128"
                            "128:1024"
                            "128:2048"
                            "1024:1024"
                            "2048:2048"
                            "4096:1024"
                            "1024:4096"
                            "30000:2048"
                            "126000:2048"
                        )
                        # Random
                        ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@$local_master_ip "
                            docker exec siginfer_nvidia_PerformanceTest_${job_count} /bin/bash -c \"
                                pip3 install dataSets pillow aiohttp

                                if [ -f \\\"/SigInfer/script/benchmark/benchmark_serving.py\\\" ]; then
                                    benchmark_serving_path=\\\"/SigInfer/script/benchmark/benchmark_serving.py\\\"
                                elif [ -f \\\"/vllm-workspace/benchmarks/benchmark_serving.py\\\" ]; then
                                    benchmark_serving_path=\\\"/vllm-workspace/benchmarks/benchmark_serving.py\\\"
                                else
                                    echo \\\"Error: benchmark_serving.py not found!\\\"
                                    exit 1
                                fi

                                for pair in ${length_pairs[@]}; do
                                    input_len=\\\$(echo \\\$pair | cut -d ':' -f 1)
                                    output_len=\\\$(echo \\\$pair | cut -d ':' -f 2)

                                    echo \\\"========================================================\\\"
                                    echo \\\"Random Testing input=\\\$input_len, output=\\\$output_len\\\"
                                    echo \\\"========================================================\\\"

                                    for concurrency in ${concurrency_list[@]}; do
                                        prompts=\\\$((concurrency * ${multiplier}))
                                        echo \\\"Testing concurrency=\\\$concurrency, prompts=\\\$prompts\\\"
                                        echo \\\"python3 \\\${benchmark_serving_path} --backend openai --port \\\$((8765+${job_count})) --host 0.0.0.0 --model ${model} --tokenizer ${data_path}/${model}/ --endpoint /v1/completions --dataset-name random --random-input-len \\\$input_len --random-output-len \\\$output_len --num-prompts \\\$prompts --request-rate inf --max-concurrency \\\$concurrency --ignore-eos\\\"

                                        python3 \\\${benchmark_serving_path} \
                                        --backend openai \
                                        --port \\\$((8765+${job_count})) \
                                        --host 127.0.0.1 \
                                        --model ${model} \
                                        --tokenizer ${data_path}/${model}/ \
                                        --endpoint /v1/completions \
                                        --dataset-name random \
                                        --random-input-len \\\$input_len \
                                        --random-output-len \\\$output_len \
                                        --num-prompts \\\$prompts \
                                        --request-rate inf \
                                        --max-concurrency \\\$concurrency \
                                        --ignore-eos
                                    done
                                done
                            \"
                        " > "$curr_dir/logs/performance/$filename"
                    else
                        multiplier=4
                        concurrency_list=(100 200 300 400 500 600 700 800 900 1000)
                        # Sharegpt
                        ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@$local_master_ip "
                            docker exec siginfer_nvidia_PerformanceTest_${job_count} /bin/bash -c \"
                                pip3 install dataSets pillow aiohttp

                                if [ -f \\\"/SigInfer/script/benchmark/benchmark_serving.py\\\" ]; then
                                    benchmark_serving_path=\\\"/SigInfer/script/benchmark/benchmark_serving.py\\\"
                                elif [ -f \\\"/vllm-workspace/benchmarks/benchmark_serving.py\\\" ]; then
                                    benchmark_serving_path=\\\"/vllm-workspace/benchmarks/benchmark_serving.py\\\"
                                else
                                    echo \\\"Error: benchmark_serving.py not found!\\\"
                                    exit 1
                                fi

                                for concurrency in ${concurrency_list[@]}; do
                                    prompts=\\\$((concurrency * ${multiplier}))
                                    echo \\\"Testing concurrency=\\\$concurrency, prompts=\\\$prompts\\\"
                                    echo \\\"python3 \\\${benchmark_serving_path} --backend openai --port \\\$((8765+${job_count})) --host 127.0.0.1 --model ${model} --tokenizer ${data_path}/${model}/ --endpoint /v1/completions --dataset-name sharegpt --dataset-path /home/weight/ShareGPT_V3_unfiltered_cleaned_split.json --num-prompts \\\$prompts --request-rate inf --max-concurrency \\\$concurrency\\\"

                                    python3 \\\${benchmark_serving_path} \
                                    --backend openai \
                                    --port \\\$((8765+${job_count})) \
                                    --host 127.0.0.1 \
                                    --model ${model} \
                                    --tokenizer ${data_path}/${model}/ \
                                    --endpoint /v1/completions \
                                    --dataset-name sharegpt \
                                    --dataset-path /home/weight/ShareGPT_V3_unfiltered_cleaned_split.json \
                                    --num-prompts \\\$prompts \
                                    --request-rate inf \
                                    --max-concurrency \\\$concurrency
                                done
                            \"
                        " > "$curr_dir/logs/performance/$filename"
                    fi
                elif [ $TEST_TYPE == "Smoke" ]; then
                    # 获取模型启动命令，并做为参数传入
                    exec_cmd=""
                    for ((k=0; k<$seq_num; k=k+1)); do
                        launch_cmd=`tail -n 4 "$curr_dir/logs/smoke/${filename}_${k}" | head -n 1`
                        exec_cmd+="$launch_cmd\n"
                    done

                    full_cmd=${exec_cmd%??}
                    container_name="OpenaiTest_$$"
                    unset pid_map
                    declare -A pid_map

                    if [ $gpu_model == "H20" ]; then
                        echo "docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${H20_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd \"$full_cmd\""
                        docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${H20_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd "\"$full_cmd\"" 2>&1 &
                        pid=$!
                        pid_map[$pid]="$container_name"
                        DOCKER_CONTAINER_NAMES+=("$container_name")
                    elif [ $gpu_model == "A800" ]; then
                        echo "docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${A800_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd \"$full_cmd\""
                        docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${A800_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd "\"$full_cmd\"" 2>&1 &
                        pid=$!
                        pid_map[$pid]="$container_name"
                        DOCKER_CONTAINER_NAMES+=("$container_name")
                    elif [ $gpu_model == "H100" ]; then
                        echo "docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${H100_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd \"$full_cmd\""
                        docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${H100_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd "\"$full_cmd\"" 2>&1 &
                        pid=$!
                        pid_map[$pid]="$container_name"
                        DOCKER_CONTAINER_NAMES+=("$container_name")
                    elif [ $gpu_model == "L20" ]; then
                        echo "docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${L20_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd \"$full_cmd\""
                        docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${L20_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd "\"$full_cmd\"" 2>&1 &
                        pid=$!
                        pid_map[$pid]="$container_name"
                        DOCKER_CONTAINER_NAMES+=("$container_name")
                    elif [ $gpu_model == "H800" ]; then
                        echo "docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${H800_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd \"$full_cmd\""
                        docker run --rm --name $container_name --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${H800_server_list[$local_master_ip]} --url http://$local_master_ip:$((8000+${job_count}))/v1 --model $model --gpu $gpu_model --cmd "\"$full_cmd\"" 2>&1 &
                        pid=$!
                        pid_map[$pid]="$container_name"
                        DOCKER_CONTAINER_NAMES+=("$container_name")
                    fi

                    # 等待后台测试任务结束
                    wait -n -p done_pid
                    err=$?
                    if [ -v pid_map[$done_pid] ]; then
                        echo "测试任务：${pid_map[$done_pid]}结束!"
                        if [ $err -ne 0 ]; then
                            echo "测试结果失败！请检查......"
                        fi
                        # 从跟踪数组中删除已完成的容器
                        remove_container_from_array "${pid_map[$done_pid]}"
                        unset pid_map[$done_pid]
                    fi
                elif [ $TEST_TYPE == "Accuracy" ]; then
                    unset pid_map
                    declare -A pid_map

                    # 开始执行测试
                    # 容器1: Evalscope mmlu,ceval
                    container_name_1="Evalscope_mmlu_ceval_$$"
                    docker run -i --rm --name "$container_name_1" --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /evalscope.sh  evalscope:0624 -M $model --port $((9701+$job_count)) --host $local_master_ip --number 10 -P 10 --dataset mmlu,ceval > "$curr_dir/logs/accuracy/${filename}_evalscope_1.log" 2>&1 &
                    pid1=$!
                    pid_map[$pid1]="$container_name_1"
                    DOCKER_CONTAINER_NAMES+=("$container_name_1")

                    # 容器2: Evalscope gsm8k,ARC_c
                    container_name_2="Evalscope_gsm8k_ARC_c_$$"
                    docker run -i --rm --name "$container_name_2" --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /evalscope.sh  evalscope:0624 -M $model --port $((9701+$job_count)) --host $local_master_ip --number 200 -P 10 --dataset gsm8k,ARC_c > "$curr_dir/logs/accuracy/${filename}_evalscope_2.log" 2>&1 &
                    pid2=$!
                    pid_map[$pid2]="$container_name_2"
                    DOCKER_CONTAINER_NAMES+=("$container_name_2")

                    # 容器3: SGLang mmlu,gsm8k
                    container_name_3="SGLang_mmlu_gsm8k_$$"
                    docker run -i --rm --name "$container_name_3" --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /sglang.sh  evalscope:0624 -M $model --port $((9701+$job_count)) --host $local_master_ip > "$curr_dir/logs/accuracy/${filename}_SGLang_3.log" 2>&1 &
                    pid3=$!
                    pid_map[$pid3]="$container_name_3"
                    DOCKER_CONTAINER_NAMES+=("$container_name_3")
                    
                    # 等待所有后台测试任务结束
                    remaining=3
                    while (( remaining > 0 )); do
                        wait -n -p done_pid
                        err=$?

                        if [ -v pid_map[$done_pid] ]; then
                            echo "测试任务：${pid_map[$done_pid]}结束!"
                            if [ $err -ne 0 ]; then
                                echo "测试结果失败！请检查......"
                            fi
                            # 从跟踪数组中删除已完成的容器
                            remove_container_from_array "${pid_map[$done_pid]}"
                            unset pid_map[$done_pid]
                        fi

                        ((remaining--))
                    done

                    touch "$curr_dir/report_${log_name_suffix}/${log_name_suffix}_result.txt"

                    eval_res_1=$(tail -n 1 "$curr_dir/logs/accuracy/${filename}_evalscope_1.log")
                    eval_res_2=$(tail -n 1 "$curr_dir/logs/accuracy/${filename}_evalscope_2.log")
                    sglang_res_3=$(tail -n 5 "$curr_dir/logs/accuracy/${filename}_SGLang_3.log")
                    
                    echo "$model+$eval_res_1 $eval_res_2+${sglang_res_3//$'\n'/}" >> "$curr_dir/report_${log_name_suffix}/${log_name_suffix}_result.txt"
                elif [ $TEST_TYPE == "Stability" ]; then
                    # 调用JMeter或者Locust工具
                    # ......

                    echo "按任意键结束......"
                    # read -n 1 -s
                    sleep infinity
                fi

                echo "测试完成！"

                # 测试完成，清理工作
                for ip in ${server_list[@]}; do
                    ssh -o ConnectionAttempts=3 s_limingge@$ip docker stop siginfer_nvidia_${TEST_TYPE}Test_${job_count}
                    ssh -o ConnectionAttempts=3 s_limingge@$ip docker rm siginfer_nvidia_${TEST_TYPE}Test_${job_count}
                done
                
                # 发送测试报告
                if [ $send_report -eq 1 ]; then
                    if [ -z $version ]; then
                        latest_tag=$(jfrog rt curl --server-id=my-jcr /api/docker/docker-local/v2/siginfer-x86_64-nvidia/tags/list | jq -r '.tags[]' \
                        | xargs -I% sh -c "echo -n \"%  \"; \
                            jfrog rt curl --server-id=my-jcr \
                            /api/storage/docker-local/siginfer-x86_64-nvidia/% \
                        | jq -r '.created'" | sort -k2 -r | grep main- | head -n1 | awk '{print $1}')
                    else
                        latest_tag=$version
                    fi

                    if [ $TEST_TYPE == "Performance" ]; then
                        # 保存docker镜像版本信息
                        touch "$curr_dir/report_${log_name_suffix}/version.txt"
                        echo "$latest_tag" > "$curr_dir/report_${log_name_suffix}/version.txt"
                        # 获取模型启动命令，并做为参数传入
                        exec_cmd=`cat "$curr_dir/logs/performance/cron_job_${log_name_suffix}_${job_count}.log" | grep "docker run"`
                        # 获取测试命令，并做为参数传入
                        test_cmd=`cat "$curr_dir/logs/performance/$filename" | grep "benchmark_serving.py" | head -n 1 | sed -E 's/--(random-input-len|random-output-len|num-prompts|max-concurrency)\s+[0-9]+/--\1 xxx/g'`
                        # 生成本次测试的Excel报告，并比较上一次Excel报告
                        if [ $use_prefix_cache_flag -eq 1 ]; then
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}_${option}_Use-prefix-cache" "$exec_cmd" "$test_cmd" "$curr_dir/logs/performance/$filename"
                                last_date=$(date -d "$TASK_START_TIME -1 day" +"%Y%m%d")
                                if [ -f $curr_dir/report_${last_date}/version.txt ]; then
                                    last_version=$(cat $curr_dir/report_${last_date}/version.txt)
                                else
                                    last_version="unknown"
                                fi
                                if [ $latest_tag != $last_version ] && [ -f "$curr_dir/report_${last_date}/${model}_${option}_Use-prefix-cache.xlsx" ]; then
                                    python3 $curr_dir/compare_excel_data.py "${model}_${option}_Use-prefix-cache" "$latest_tag" "$curr_dir/report_${log_name_suffix}/${model}_${option}_Use-prefix-cache.xlsx" "$last_version" "$curr_dir/report_${last_date}/${model}_${option}_Use-prefix-cache.xlsx"
                                fi
                            else
                                python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}_${option}_Use-prefix-cache_Swap-space" "$exec_cmd" "$test_cmd" "$curr_dir/logs/performance/$filename"
                                last_date=$(date -d "$TASK_START_TIME -1 day" +"%Y%m%d")
                                if [ -f $curr_dir/report_${last_date}/version.txt ]; then
                                    last_version=$(cat $curr_dir/report_${last_date}/version.txt)
                                else
                                    last_version="unknown"
                                fi
                                if [ $latest_tag != $last_version ] && [ -f "$curr_dir/report_${last_date}/${model}_${option}_Use-prefix-cache_Swap-space.xlsx" ]; then
                                    python3 $curr_dir/compare_excel_data.py "${model}_${option}_Use-prefix-cache_Swap-space" "$latest_tag" "$curr_dir/report_${log_name_suffix}/${model}_${option}_Use-prefix-cache_Swap-space.xlsx" "$last_version" "$curr_dir/report_${last_date}/${model}_${option}_Use-prefix-cache_Swap-space.xlsx"
                                fi
                            fi
                        else
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}_${option}" "$exec_cmd" "$test_cmd" "$curr_dir/logs/performance/$filename"
                                last_date=$(date -d "$TASK_START_TIME -1 day" +"%Y%m%d")
                                if [ -f $curr_dir/report_${last_date}/version.txt ]; then
                                    last_version=$(cat $curr_dir/report_${last_date}/version.txt)
                                else
                                    last_version="unknown"
                                fi
                                if [ $latest_tag != $last_version ] && [ -f "$curr_dir/report_${last_date}/${model}_${option}.xlsx" ]; then
                                    python3 $curr_dir/compare_excel_data.py "${model}_${option}" "$latest_tag" "$curr_dir/report_${log_name_suffix}/${model}_${option}.xlsx" "$last_version" "$curr_dir/report_${last_date}/${model}_${option}.xlsx"
                                fi
                            else
                                python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}_${option}_Swap-space" "$exec_cmd" "$test_cmd" "$curr_dir/logs/performance/$filename"
                                last_date=$(date -d "$TASK_START_TIME -1 day" +"%Y%m%d")
                                if [ -f $curr_dir/report_${last_date}/version.txt ]; then
                                    last_version=$(cat $curr_dir/report_${last_date}/version.txt)
                                else
                                    last_version="unknown"
                                fi
                                if [ $latest_tag != $last_version ] && [ -f "$curr_dir/report_${last_date}/${model}_${option}_Swap-space.xlsx" ]; then
                                    python3 $curr_dir/compare_excel_data.py "${model}_${option}_Swap-space" "$latest_tag" "$curr_dir/report_${log_name_suffix}/${model}_${option}_Swap-space.xlsx" "$last_version" "$curr_dir/report_${last_date}/${model}_${option}_Swap-space.xlsx"
                                fi
                            fi
                        fi
                    elif [ $TEST_TYPE == "Smoke" ]; then
                        if [ $use_prefix_cache_flag -eq 1 ]; then
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}:${gpu_model}_${option}_Use-prefix-cache" "$curr_dir/logs/smoke/$filename"
                            else
                                python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}:${gpu_model}_${option}_Use-prefix-cache_Swap-space" "$curr_dir/logs/smoke/$filename"
                            fi
                        else
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}:${gpu_model}_${option}" "$curr_dir/logs/smoke/$filename"
                            else
                                python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}:${gpu_model}_${option}_Swap-space" "$curr_dir/logs/smoke/$filename"
                            fi
                        fi
                    elif [ $TEST_TYPE == "Accuracy" ]; then
                        # 生成本次测试的Excel报告
                        if [ $use_prefix_cache_flag -eq 1 ]; then
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/write_file.py --file "$curr_dir/report_${log_name_suffix}/${log_name_suffix}_result.txt" --framework ${model}_${option}_Use-prefix-cache --engine ${ENGINE_TYPE}
                            else
                                python3 $curr_dir/write_file.py --file "$curr_dir/report_${log_name_suffix}/${log_name_suffix}_result.txt" --framework ${model}_${option}_Use-prefix-cache_Swap-space --engine ${ENGINE_TYPE}
                            fi
                        else
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/write_file.py --file "$curr_dir/report_${log_name_suffix}/${log_name_suffix}_result.txt" --framework ${model}_${option} --engine ${ENGINE_TYPE}
                            else
                                python3 $curr_dir/write_file.py --file "$curr_dir/report_${log_name_suffix}/${log_name_suffix}_result.txt" --framework ${model}_${option}_Swap-space --engine ${ENGINE_TYPE}
                            fi
                        fi
                    fi
                fi
                
                # 记录测试进度
                if [ $use_prefix_cache_flag -eq 1 ]; then
                    if [ $swap_space -eq 0 ]; then
                        echo "${model}:${gpu_quantity}:${gpu_model}_${option}_use-prefix-cache" >> ${processed_models}
                    else
                        echo "${model}:${gpu_quantity}:${gpu_model}_${option}_use-prefix-cache_swap-space" >> ${processed_models}
                    fi
                else
                    if [ $swap_space -eq 0 ]; then
                        echo "${model}:${gpu_quantity}:${gpu_model}_${option}" >> ${processed_models}
                    else
                        echo "${model}:${gpu_quantity}:${gpu_model}_${option}_swap-space" >> ${processed_models}
                    fi
                fi
            done
            swap_space=0
        done
        use_prefix_cache_flag=$((-use_prefix_cache_flag))
    done
done

echo "测试全部完成！"

exit $ret_code
