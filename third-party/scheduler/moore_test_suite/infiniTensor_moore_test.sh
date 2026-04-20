#!/bin/bash

# 接收参数
send_report=$1
server_list=($2)
candidate_models=$3
job_count=$4
TEST_TYPE=$5
ENGINE_TYPE=$6
session_id=$7

if [ $TEST_TYPE == "Performance" ]; then
    TEST_PARAM=$8
    version=$9
else
    version=$8
fi

curr_dir=$(pwd)
log_name_suffix=${TASK_START_TIME}
LOCK_DIR="/home/zkjh/.npu_locks"
LOCK_FILE="server_config.lock"

declare -A npu_server_list=(
    ["172.22.162.95"]="AICC_001"
)

declare -A local_ip_map=(
    ["172.22.162.95"]="192.168.162.95"
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

# 存储后台 ssh 进程 PID，用于信号传递
declare -A SSH_PID_MAP

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
    engine_type=$(echo "${ENGINE_TYPE}" | tr '[:upper:]' '[:lower:]')
    echo ""
    echo "=========================================="
    echo "${engine_type}_moore_test.sh 退出，开始清理资源..."
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
        source $curr_dir/npu_lock_manager_for_ci.sh
        for ip in ${server_list[@]}; do
            SERVER_NAME=$(echo ${local_ip_map[$ip]} | sed 's/\./_/g')
            release_npu_locks_batch "$SERVER_NAME" "0 1 2 3 4 5 6 7" "${TEST_TYPE}Test_${model}_${job_count}" "${session_id}"
        done
        echo "NPU 锁释放完成"
        # 获取文件锁（阻塞）
        exec 200>"${LOCK_DIR}/${LOCK_FILE}"    # 打开文件描述符 200
        if ! flock -x 200; then    # 获取独占锁
            echo "无法获取锁，退出..."
        fi
        for ip in ${server_list[@]}; do
            job_id="${TEST_TYPE}Test_${model}_${session_id}_${job_count}"
            # 删除Server端配置信息
            # sed -i "/${local_ip_map[$ip]}:${job_id}:/d" "${LOCK_DIR}/server_config.txt"
            new_config=`sed "/${local_ip_map[$ip]}:${job_id}:/d" "${LOCK_DIR}/server_config.txt"`
            echo "${new_config}" > "${LOCK_DIR}/server_config.txt"
        done
        # 锁会自动在脚本退出或文件描述符关闭时释放
        exec 200>&-  # 关闭文件描述符
        echo "Server Config文件锁释放完成"
        exec 300>&-  # 关闭文件描述符
    fi
    
    # 3. 清理远程 Docker 容器
    for ip in ${server_list[@]}; do
        ssh -q -o ConnectionAttempts=3  zkjh@$ip "
            name=${engine_type}_moore_${TEST_TYPE}Test_${session_id}_${job_count}
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
    echo ""
    echo "收到中断信号，正在向所有远程进程发送中断信号..."
    # 从 SSH_PID_MAP 中收集唯一的 IP 地址
    declare -A unique_ips
    for pid in "${!SSH_PID_MAP[@]}"; do
        remote_ip="${SSH_PID_MAP[$pid]}"
        unique_ips["$remote_ip"]=1
    done
    # 对每个唯一的 IP 地址，通过 ssh 找到并终止远程脚本进程
    for remote_ip in "${!unique_ips[@]}"; do
        echo "  向远程服务器 $remote_ip 上的脚本进程发送 SIGINT..."
        # 通过 ssh 找到远程脚本进程并发送信号
        ssh -o ConnectionAttempts=3 -o ConnectTimeout=5  zkjh@$remote_ip "
            pids=\$(ps -ef --forest | grep '${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh' | grep -v grep | awk '{print \$2}' 2>/dev/null || true)
            if [ ! -z \"\$pids\" ]; then
                for pid in \$pids; do
                    # 检查进程是否仍在运行
                    if kill -0 \$pid 2>/dev/null; then
                        echo \"找到远程脚本进程 PID: \$pid, 发送 SIGINT 信号\"
                        kill -TERM -\$pid 2>/dev/null || true
                    fi
                done
            else
                echo \"未找到远程脚本进程（可能已结束）\"
            fi
        " 2>/dev/null || true
    done
    # 等待一小段时间，让远程脚本有机会处理信号
    sleep 2
    if [ -v JMETER_PID ]; then
        kill -SIGTERM $JMETER_PID
    fi
    cleanup_all_resources
}

# 注册信号处理函数
trap handle_interrupt SIGINT SIGTERM
# EXIT 信号仍然调用 cleanup（正常退出时 INTERRUPTED=0，不会额外 exit）
trap cleanup_all_resources EXIT


if [ $TEST_TYPE == "Unit" ]; then
    echo "*************开始执行 UnitTest 任务，日期时间:$(date +"%Y%m%d_%H%M%S")***************"
    model="None"
    gpu_quantity=1
    
    filename="${log_name_suffix}_UnitTest.log"

    cd $curr_dir

    echo "尝试同时在${server_list[@]}服务器上面启动测试......"
    
    # 将 server_list 数组合并为用下划线分隔的字符串
    server_list_str=$(
        for i in "${server_list[@]}"; do
            printf '%s\n' "${local_ip_map[$i]}"
        done | paste -sd '_' -
    )

    unset pid_map
    declare -A pid_map
    ip=${server_list[0]}

    ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3  zkjh@$ip chmod a+x /home/zkjh/${ENGINE_TYPE}_job_executor_for_UnitTest.sh
    ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3  zkjh@$ip /home/zkjh/${ENGINE_TYPE}_job_executor_for_UnitTest.sh $model $gpu_quantity $server_list_str 0 0 $session_id $version > "$curr_dir/logs/unit/$session_id/${filename}" &
    ssh_pid=$!
    pid_map[$ssh_pid]=$ip
    SSH_PID_MAP[$ssh_pid]=$ip

    wait $ssh_pid
    err=$?
    
    echo "UnitTest 任务结束，服务器：${pid_map[$ssh_pid]} (PID=$ssh_pid)"

    # 从 SSH_PID_MAP 中移除已完成的进程
    unset SSH_PID_MAP[$ssh_pid]
    
    if [ $err -ne 0 ]; then
        if [ $err -eq 10 ]; then
            echo "${pid_map[$ssh_pid]}暂无资源, 中止当前模型测试任务，尝试进行下一个测试任务......"
        else
            echo "${pid_map[$ssh_pid]}测试环境配置失败, 中止当前模型测试任务，尝试进行下一个测试任务......"
        fi
    fi

    # 清理工作
    for ip in ${server_list[@]}; do
        if [ $ENGINE_TYPE == "InfiniTensor" ]; then
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop infiniTensor_moore_UnitTest_${session_id}_0
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm infiniTensor_moore_UnitTest_${session_id}_0
        fi
    done

    if [ $err -eq 0 ]; then
        # 发送测试报告
        # 获取模型启动命令，并做为参数传入
        launch_cmd=`sed -n '/docker run /,/exit \$failed'\''/p' "$curr_dir/logs/unit/$session_id/${filename}"`

        python3 ./get_info.py \
            --file "$curr_dir/logs/unit/$session_id/${filename}" \
            --email "limingge@xcoresigma.com" \
            --model "InfiniOps" \
            --gpu "A100" \
            --cmd "${launch_cmd}"
    fi
    
    exit $err
fi

model_list=($candidate_models)

echo "*************开始执行${TEST_TYPE}测试任务，日期时间:$(date +"%Y%m%d_%H%M%S")***************"
echo "测试模型列表: ${model_list[@]}"

if [ -z $version ]; then
    version=$(jfrog rt curl --server-id=my-jcr /api/docker/docker-local/v2/infiniTensor-aarch64-moore/tags/list | jq -r '.tags[]' \
                        | xargs -I% sh -c "echo -n \"%  \"; \
                            jfrog rt curl --server-id=my-jcr \
                            /api/storage/docker-local/infiniTensor-aarch64-moore/% \
                        | jq -r '.created'" | sort -k2 -r | grep main- | head -n1 | awk '{print $1}')
fi

echo "推理引擎版本: ${version}"

test_type=$(echo "${TEST_TYPE}" | tr '[:upper:]' '[:lower:]')
processed_models="${curr_dir}/logs/${test_type}/$session_id/processed_models_${log_name_suffix}"
touch ${processed_models}

ret_code=0
for item in "${model_list[@]}"; do
    model=`echo "$item" | awk -F : '{print $1}'`
    gpu_quantity=`echo "$item" | awk -F : '{print $2}'`
    if [ ! -z `cat ${processed_models} | grep -w ${model}` ]; then
        continue
    fi
    
    filename=${log_name_suffix}_${model}
    echo "开始测试模型: $model"

    cd $curr_dir

    if [ $TEST_TYPE != "Accuracy" ]; then
        filename+=".log"
    fi

    echo "尝试同时在${server_list[@]}服务器上面启动测试......"
    
    # 将 server_list 数组合并为用下划线分隔的字符串
    server_list_str=$(
        for i in "${server_list[@]}"; do
            printf '%s\n' "${local_ip_map[$i]}"
        done | paste -sd '_' -
    )

    unset pid_map
    declare -A pid_map
    seq_num=0
    # 依次在所有服务器上面启动任务
    for ip in ${server_list[@]}; do
        echo "启动第${seq_num}台服务器: $ip......"

        if [ $ip == ${server_list[0]} ]; then
            local_master_ip=${local_ip_map[$ip]}
        fi

        if [ $TEST_TYPE == "Smoke" ]; then
            if [ $ENGINE_TYPE == "MindIE" ]; then
                ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3  zkjh@$ip /home/zkjh/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $server_list_str $seq_num $job_count $session_id $version > "$curr_dir/logs/smoke/$session_id/${filename}_${seq_num}" &
            else
                ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3  zkjh@$ip /home/zkjh/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $server_list_str $seq_num $job_count $session_id $version > "$curr_dir/logs/smoke/$session_id/${filename}_${seq_num}" &
            fi
            ssh_pid=$!
            pid_map[$ssh_pid]=$ip
            SSH_PID_MAP[$ssh_pid]=$ip
        else
            if [ $ENGINE_TYPE == "MindIE" ]; then
                ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3  zkjh@$ip /home/zkjh/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $server_list_str $seq_num $job_count $session_id $version &
            else
                ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3  zkjh@$ip /home/zkjh/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $server_list_str $seq_num $job_count $session_id $version &
            fi
            ssh_pid=$!
            pid_map[$ssh_pid]=$ip
            SSH_PID_MAP[$ssh_pid]=$ip
        fi
        
        ((seq_num++))
    done

    # 接收各个节点的rank_table.json并进行合并与分发
    if [ $ENGINE_TYPE == "MindIE" ]; then
        job_id="${TEST_TYPE}Test_${model}_${session_id}_${job_count}"
        mkdir -p $curr_dir/controller/$job_id
        cd $curr_dir/controller/$job_id
        rm -rf *
        npm init -y
        # npm install express multer
        npm install express multer
        cp $curr_dir/controller.js .
        if [ "${TEST_TYPE}" == "Smoke" ]; then
            http_server_port=8686
        elif [ "${TEST_TYPE}" == "Performance" ]; then
            http_server_port=8787
        elif [ "${TEST_TYPE}" == "Accuracy" ]; then
            http_server_port=8888
        elif [ "${TEST_TYPE}" == "Stablity" ]; then
            http_server_port=8989
        fi
        # 获取文件锁（阻塞），防止多任务并发执行时发生端口冲突
        exec 300>"${LOCK_DIR}/http_port_$(($http_server_port+$job_count)).lock"    # 打开文件描述符 300
        if ! flock -x 300; then    # 获取独占锁
            echo "无法获取锁，退出..."
            exit 1
        fi
        node controller.js $(($http_server_port+$job_count)) ${#server_list[@]}
        # 锁会自动在脚本退出或文件描述符关闭时释放
        exec 300>&-  # 关闭文件描述符
        arguments=""
        for ip in ${server_list[@]}; do
            node_name=$(echo ${local_ip_map[$ip]} | sed 's/\./_/g')
            arguments+=" ./ranks/${node_name}.json"
        done
        python3 $curr_dir/merge_hccl.py $arguments
        merged_rank_table=`ls hccl_*.json`
        if [ ! -f $merged_rank_table ]; then
            echo "Rank Table文件合并失败，无法找到输出文件..."
            exit 1
        fi
        for ip in ${server_list[@]}; do
            scp  $merged_rank_table zkjh@$ip:/home/zkjh/rank_table/$job_id/merged_rank_table.json
        done
        cd $curr_dir
    fi

    success=0
    # 等待所有服务器任务启动完成
    remaining=${#server_list[@]}
    while (( remaining > 0 )); do
        wait -n -p done_pid
        err=$?
        
        if [ -v pid_map[$done_pid] ]; then
            echo "任务启动结束，服务器：${pid_map[$done_pid]} (PID=$done_pid)"

            # 从 SSH_PID_MAP 中移除已完成的进程
            unset SSH_PID_MAP[$done_pid]
            
            if [ $err -ne 0 ]; then
                if [ $err -eq 10 ]; then
                    echo "${pid_map[$done_pid]}暂无资源, 中止当前模型测试任务，尝试进行下一个测试任务......"
                else
                    echo "${pid_map[$done_pid]}测试环境配置失败, 中止当前模型测试任务，尝试进行下一个测试任务......"
                fi
                
                # ...

                # 启动失败，清理工作
                for ip in ${server_list[@]}; do
                    if [ $ENGINE_TYPE == "InfiniTensor" ]; then
                        ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop infiniTensor_moore_${TEST_TYPE}Test_${session_id}_${job_count}
                        ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm infiniTensor_moore_${TEST_TYPE}Test_${session_id}_${job_count}
                    elif [ $ENGINE_TYPE == "vLLM" ]; then
                        ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop vllm_moore_${TEST_TYPE}Test_${session_id}_${job_count}
                        ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm vllm_moore_${TEST_TYPE}Test_${session_id}_${job_count}
                    elif [ $ENGINE_TYPE == "MindIE" ]; then
                        ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop mindie_moore_${TEST_TYPE}Test_${session_id}_${job_count}
                        ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm mindie_moore_${TEST_TYPE}Test_${session_id}_${job_count}
                    fi
                done
                
                ret_code=$err
                success=1
                break
            fi

            ((remaining--))
        else
            echo "PID=${done_pid}不在pid_map中, 致命错误!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        fi
    done

    # 任务启动失败
    if [ $success -eq 1 ]; then
        continue
    fi

    if [ -f "${LOCK_DIR}/${LOCK_FILE}" ]; then
        # 获取文件锁（阻塞）
        exec 200>"${LOCK_DIR}/${LOCK_FILE}"    # 打开文件描述符 200
        if ! flock -x 200; then    # 获取独占锁
            echo "无法获取锁，退出..."
            exit 1
        fi
        # 读取Server端配置信息
        job_id="${TEST_TYPE}Test_${model}_${session_id}_${job_count}"
        server_port=`cat "${LOCK_DIR}/server_config.txt" | grep "${local_master_ip}:${job_id}:" | awk -F ':' '{print $3}' | awk '{print $1}' | tail -n 1`
        # 锁会自动在脚本退出或文件描述符关闭时释放
        exec 200>&-  # 关闭文件描述符
    else
        echo "无法找到远端推理引擎服务端口号文件！中止此模型测试任务！"
        if [ $ENGINE_TYPE == "InfiniTensor" ]; then
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop infiniTensor_moore_${TEST_TYPE}Test_${session_id}_${job_count}
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm infiniTensor_moore_${TEST_TYPE}Test_${session_id}_${job_count}
        elif [ $ENGINE_TYPE == "vLLM" ]; then
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop vllm_moore_${TEST_TYPE}Test_${session_id}_${job_count}
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm vllm_moore_${TEST_TYPE}Test_${session_id}_${job_count}
        elif [ $ENGINE_TYPE == "MindIE" ]; then
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop mindie_moore_${TEST_TYPE}Test_${session_id}_${job_count}
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm mindie_moore_${TEST_TYPE}Test_${session_id}_${job_count}
        fi
        continue
    fi

    echo "Starting the model ${TEST_TYPE} testing task..."

    if [ $TEST_TYPE == "Smoke" ]; then
        # 获取模型启动命令，并做为参数传入
        exec_cmd=""
        for ((k=0; k<$seq_num; k=k+1)); do
            launch_cmd=`tail -n 4 "$curr_dir/logs/smoke/$session_id/${filename}_${k}" | head -n 1`
            exec_cmd+="$launch_cmd\n"
        done

        full_cmd=${exec_cmd%??}
        container_name="OpenaiTest_$$"
        model_name=${model}

        unset pid_map
        declare -A pid_map
        
        echo "docker run --rm --name $container_name --volume /home/zkjh/CI_Workspace/ci_autotest/moore_test_suite/report_${log_name_suffix}/$session_id:/test/report_${log_name_suffix} -e TASK_START_TIME=${log_name_suffix} --entrypoint /test/start.sh openai:1110 --file $filename --email limingge@xcoresigma.com --env=${npu_server_list[${server_list[0]}]} --url http://${server_list[0]}:${server_port}/v1 --model=$model_name --gpu 910B --cmd \"$full_cmd\""
        docker run --rm --name $container_name --volume /home/zkjh/CI_Workspace/ci_autotest/moore_test_suite/report_${log_name_suffix}/$session_id:/test/report_${log_name_suffix} -e TASK_START_TIME=${log_name_suffix} --entrypoint /test/start.sh openai:1110 --file $filename --email limingge@xcoresigma.com --env=${npu_server_list[${server_list[0]}]} --url http://${server_list[0]}:${server_port}/v1 --model=$model_name --gpu 910B --cmd "\"$full_cmd\"" 2>&1 &
        pid=$!
        pid_map[$pid]="$container_name"
        DOCKER_CONTAINER_NAMES+=("$container_name")

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
    elif [ $TEST_TYPE == "Performance" ]; then
        if [ $model == "Qwen3-235B-A22B" ] || [[ $model =~ ^Qwen3-32B(-v[0-9]+)?$ ]] || [ $model == "Qwen3-30B-A3B" ] || [ $model == "Qwen3-14B" ]; then
            data_path="/home/zkjh/weight/Qwen3"
        else
            data_path="/home/zkjh/weight"
        fi

        if [ $ENGINE_TYPE == "InfiniTensor" ]; then
            engine_type="infiniTensor"
            benchmark_cmd="python3 /InfiniTensor/script/benchmark/benchmark_serving.py"
        elif [ $ENGINE_TYPE == "vLLM" ]; then
            engine_type="vllm"
            benchmark_cmd="vllm bench serve"
        elif [ $ENGINE_TYPE == "MindIE" ]; then
            engine_type="mindie"
            benchmark_cmd="vllm bench serve"
        fi
        
        # 开始执行测试
        if [ $TEST_PARAM == "Random" ]; then
            multiplier=4
            # concurrency_list=(1 5 10 20 50 100 150 200)
            concurrency_list=(1 5 10)
            length_pairs=(
                "128:128"
                # "128:1024"
                # "128:2048"
                # "1024:1024"
                # "2048:2048"
                # "4096:1024"
                # "1024:4096"
                # "30000:2048"
                # "126000:2048"
            )
            # Random
            ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3  zkjh@${server_list[0]} "
                docker exec ${engine_type}_moore_PerformanceTest_${session_id}_${job_count} /bin/bash -c \"
                    export https_proxy=http://localhost:9991 http_proxy=http://localhost:9991
                    if [ ${engine_type} == \\\"infiniTensor\\\" ]; then
                        pip3 install dataSets pillow aiohttp
                    elif [ ${engine_type} == \\\"mindie\\\" ]; then
                        python3 -m venv venv_vllm
                        source venv_vllm/bin/activate
                        unset PYTHONPATH
                        pip3 install --upgrade pip
                        pip3 install -i https://pypi.org/simple vllm
                    fi
                    unset https_proxy http_proxy

                    for pair in ${length_pairs[@]}; do
                        input_len=\\\$(echo \\\$pair | cut -d ':' -f 1)
                        output_len=\\\$(echo \\\$pair | cut -d ':' -f 2)

                        echo \\\"========================================================\\\"
                        echo \\\"Random Testing input=\\\$input_len, output=\\\$output_len\\\"
                        echo \\\"========================================================\\\"

                        for concurrency in ${concurrency_list[@]}; do
                            if [ \\\$input_len -ge 30000 ] && [ \\\$concurrency -gt 5 ]; then
                                break
                            fi
                            
                            prompts=\\\$((concurrency * ${multiplier}))
                            echo \\\"Testing concurrency=\\\$concurrency, prompts=\\\$prompts\\\"
                            echo \\\"${benchmark_cmd} --backend openai --port ${server_port} --host ${local_master_ip} --model ${model} --tokenizer ${data_path}/${model}/ --endpoint /v1/completions --dataset-name random --random-input-len \\\$input_len --random-output-len \\\$output_len --num-prompts \\\$prompts --request-rate inf --max-concurrency \\\$concurrency --ignore-eos\\\"

                            ${benchmark_cmd} \
                            --backend openai \
                            --port ${server_port} \
                            --host ${local_master_ip} \
                            --model ${model} \
                            --tokenizer ${data_path}/$(echo $model | sed -E 's/-v[0-9]+$//')/ \
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
            " > "$curr_dir/logs/performance/$session_id/$filename"
        else
            concurrency_list=(100 200 300 400 500 600 700 800 900 1000)
            # Sharegpt
            ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3  zkjh@${server_list[0]} "
                docker exec ${engine_type}_moore_PerformanceTest_${session_id}_${job_count} /bin/bash -c \"
                    if [ ${engine_type} == \\\"infiniTensor\\\" ]; then
                        pip3 install dataSets pillow aiohttp
                    elif [ ${engine_type} == \\\"mindie\\\" ]; then
                        python3 -m venv venv_vllm
                        source venv_vllm/bin/activate
                        unset PYTHONPATH
                        pip3 install vllm
                    fi

                    for concurrency in ${concurrency_list[@]}; do
                        prompts=\\\$((concurrency * 4))
                        echo \\\"Testing concurrency=\\\$concurrency, prompts=\\\$prompts\\\"
                        echo \\\"${benchmark_cmd} --backend openai --port ${server_port} --host ${local_master_ip} --model ${model} --tokenizer ${data_path}/${model}/ --endpoint /v1/completions --dataset-name sharegpt --dataset-path /home/weight/ShareGPT_V3_unfiltered_cleaned_split.json --num-prompts \\\$prompts --request-rate inf --max-concurrency \\\$concurrency\\\"

                        ${benchmark_cmd} \
                        --backend openai \
                        --port ${server_port} \
                        --host ${local_master_ip} \
                        --model ${model} \
                        --tokenizer ${data_path}/$(echo $model | sed -E 's/-v[0-9]+$//')/ \
                        --endpoint /v1/completions \
                        --dataset-name sharegpt \
                        --dataset-path /home/weight/ShareGPT_V3_unfiltered_cleaned_split.json \
                        --num-prompts \\\$prompts \
                        --request-rate inf \
                        --max-concurrency \\\$concurrency
                    done
                \"
            " > "$curr_dir/logs/performance/$session_id/$filename"
        fi
    elif [ $TEST_TYPE == "Accuracy" ]; then
        unset pid_map
        declare -A pid_map
        
        # 开始执行测试
        # 容器1: Evalscope mmlu,ceval
        container_name_1="Evalscope_mmlu_ceval_$$"
        docker run -i --rm --name "$container_name_1" --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/zkjh/weight/:/home/weight/ --entrypoint /evalscope.sh  evalscope:0624 -M $model --port ${server_port} --host ${server_list[0]} --number 10 -P 10 --dataset mmlu,ceval > "$curr_dir/logs/accuracy/$session_id/${filename}_evalscope_1.log" 2>&1 &
        pid1=$!
        pid_map[$pid1]="$container_name_1"
        DOCKER_CONTAINER_NAMES+=("$container_name_1")
        
        # 容器2: Evalscope gsm8k,ARC_c
        container_name_2="Evalscope_gsm8k_ARC_c_$$"
        docker run -i --rm --name "$container_name_2" --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/zkjh/weight/:/home/weight/ --entrypoint /evalscope.sh  evalscope:0624 -M $model --port ${server_port} --host ${server_list[0]} --number 200 -P 10 --dataset gsm8k,ARC_c > "$curr_dir/logs/accuracy/$session_id/${filename}_evalscope_2.log" 2>&1 &
        pid2=$!
        pid_map[$pid2]="$container_name_2"
        DOCKER_CONTAINER_NAMES+=("$container_name_2")
        
        # 容器3: SGLang mmlu,gsm8k
        container_name_3="SGLang_mmlu_gsm8k_$$"
        docker run -i --rm --name "$container_name_3" --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/zkjh/weight/:/home/weight/ --entrypoint /sglang.sh  evalscope:0624 -M $model --port ${server_port} --host ${server_list[0]} > "$curr_dir/logs/accuracy/$session_id/${filename}_SGLang_3.log" 2>&1 &
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

        touch "$curr_dir/report_${log_name_suffix}/$session_id/${log_name_suffix}_result.txt"

        eval_res_1=$(tail -n 1 "$curr_dir/logs/accuracy/$session_id/${filename}_evalscope_1.log")
        eval_res_2=$(tail -n 1 "$curr_dir/logs/accuracy/$session_id/${filename}_evalscope_2.log")
        sglang_res_3=$(tail -n 5 "$curr_dir/logs/accuracy/$session_id/${filename}_SGLang_3.log")

        echo "${model}+$eval_res_1 $eval_res_2+${sglang_res_3//$'\n'/}" >> "$curr_dir/report_${log_name_suffix}/$session_id/${log_name_suffix}_result.txt"
    elif [ $TEST_TYPE == "Stability" ]; then
        # 调用JMeter或者Locust工具
        export JVM_ARGS="-Xms4g -Xmx4g -XX:+UseG1GC"
        jmeter -n -t smoke.jmx
        jmeter -n -t test.jmx -l result.jtl
        /opt/apache-jmeter-5.6.3/bin/jmeter \
            -n \
            -t /data/test/llm_perf.jmx \
            -l /data/jtl/result_$(date +\%F).jtl  \
            -e \
            -o report/  \
            -Jmodel=${model} \
            -Jbatch_size=16 \
            -Jcontext_len=8192 \
            -Jqps=30    \
            > /data/log/jmeter_$(date +\%F).log 2>&1 &

            # 在 JMX 中使用：
            # ${__P(model)}
            # ${__P(batch_size)}
            # ${__P(context_len)}

            JMETER_PID=$!
            wait $JMETER_PID
    fi

    echo "测试完成！"

    # 测试完成，清理工作
    for ip in ${server_list[@]}; do
        if [ $ENGINE_TYPE == "InfiniTensor" ]; then
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop infiniTensor_moore_${TEST_TYPE}Test_${session_id}_${job_count}
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm infiniTensor_moore_${TEST_TYPE}Test_${session_id}_${job_count}
        elif [ $ENGINE_TYPE == "vLLM" ]; then
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop vllm_moore_${TEST_TYPE}Test_${session_id}_${job_count}
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm vllm_moore_${TEST_TYPE}Test_${session_id}_${job_count}
        elif [ $ENGINE_TYPE == "MindIE" ]; then
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker stop mindie_moore_${TEST_TYPE}Test_${session_id}_${job_count}
            ssh -q -o ConnectionAttempts=3  zkjh@$ip docker rm mindie_moore_${TEST_TYPE}Test_${session_id}_${job_count}
        fi
    done
    
    # 发送测试报告
    if [ $send_report -eq 1 ]; then
        latest_tag=$version
        if [ $TEST_TYPE == "Smoke" ]; then
            # 保存docker镜像版本信息
            touch "$curr_dir/report_${log_name_suffix}/$session_id/version.txt"
            echo "$latest_tag" > "$curr_dir/report_${log_name_suffix}/$session_id/version.txt"
        elif [ $TEST_TYPE == "Performance" ]; then
            # 保存docker镜像版本信息
            touch "$curr_dir/report_${log_name_suffix}/$session_id/version.txt"
            echo "$latest_tag" > "$curr_dir/report_${log_name_suffix}/$session_id/version.txt"
            # 获取模型启动命令，并做为参数传入
            exec_cmd=`cat "$curr_dir/logs/performance/$session_id/cron_job_${log_name_suffix}_${job_count}.log" | grep "docker run"`
            # 获取测试命令，并做为参数传入
            if [ $ENGINE_TYPE == "InfiniTensor" ]; then
                test_cmd=`cat "$curr_dir/logs/performance/$session_id/$filename" | grep "benchmark_serving.py" | head -n 1 | sed -E 's/--(random-input-len|random-output-len|num-prompts|max-concurrency)\s+[0-9]+/--\1 xxx/g'`
            elif [ $ENGINE_TYPE == "vLLM" ] || [ $ENGINE_TYPE == "MindIE" ]; then
                test_cmd=`cat "$curr_dir/logs/performance/$session_id/$filename" | grep "vllm bench serve" | head -n 1 | sed -E 's/--(random-input-len|random-output-len|num-prompts|max-concurrency)\s+[0-9]+/--\1 xxx/g'`
            fi
            
            # 生成本次测试的Excel报告，并比较上一次Excel报告
            python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}" "$session_id" "$exec_cmd" "$test_cmd" "$curr_dir/logs/performance/$session_id/$filename"
            CI_report_folder="/artifacts/CI_moore_test/${session_id}_moore_npu_performancetest"
            cp "$curr_dir/report_${log_name_suffix}/$session_id/${model}.xlsx" $CI_report_folder

            # last_date=$(date -d "$TASK_START_TIME -1 day" +"%Y%m%d")
            # if [ -f $curr_dir/report_${last_date}/$session_id/version.txt ]; then
            #     last_version=$(cat $curr_dir/report_${last_date}/$session_id/version.txt)
            # else
            #     last_version="unknown"
            # fi
            # if [ -f "$curr_dir/report_${last_date}/$session_id/${model}.xlsx" ]; then
            #     python3 $curr_dir/compare_excel_data.py "${model}" "$latest_tag" "$curr_dir/report_${log_name_suffix}/$session_id/${model}.xlsx" "$last_version" "$curr_dir/report_${last_date}/$session_id/${model}.xlsx"
            # fi
        fi
    fi
    
    # 记录测试进度
    echo "${model}" >> ${processed_models}
done

echo "All tests have completed"

exit $ret_code
