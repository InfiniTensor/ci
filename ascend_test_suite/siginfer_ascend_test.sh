#!/bin/bash

# 接收参数
send_report=$1
server_list=($2)
candidate_models=$3
job_count=$4
TEST_TYPE=$5

if [ $TEST_TYPE == "Performance" ]; then
    TEST_PARAM=$6
    version=$7
else
    version=$6
fi

full_model_list=(DeepSeek-R1-AWQ:8 DeepSeek-R1-W8A8:16 DeepSeek-R1-Distill-Qwen-14B:1 DeepSeek-R1-Distill-Qwen-32B:2 DeepSeek-R1-Distill-Llama-8B:1 DeepSeek-R1-Distill-Llama-70B:4 Meta-Llama-3.1-8B-Instruct:1 Meta-Llama-3.1-70B-Instruct:4 Qwen2.5-0.5B-Instruct:1 Qwen2.5-1.5B-Instruct:1 Qwen2.5-3B-Instruct:1 Qwen2.5-7B-Instruct:1 Qwen2.5-14B-Instruct:1 QwQ-32B:2 Qwen2.5-0.5B-Instruct-AWQ:1 Qwen2.5-1.5B-Instruct-AWQ:1 Qwen2.5-3B-Instruct-AWQ:1 Qwen2.5-7B-Instruct-AWQ:1 Qwen2.5-14B-Instruct-AWQ:1 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct-AWQ:2 QwQ-32B-AWQ:1 Qwen3-32B:2 Qwen2.5-32B-Instruct:2 Qwen2.5-72B-Instruct:4 Qwen3-30B-A3B:2)
full_model_list_for_performance=(Qwen3-235B-A22B:8 DeepSeek-R1-Distill-Qwen-32B:2 DeepSeek-R1-Distill-Llama-70B:4 Qwen2.5-72B-Instruct-AWQ:2 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct:4 DeepSeek-R1:16)
# full_model_list=(DeepSeek-R1-AWQ:8 DeepSeek-R1-W8A8:16 DeepSeek-R1-Distill-Qwen-1.5B:1 Qwen3-235B-A22B:8 DeepSeek-R1-Distill-Qwen-32B:2 DeepSeek-R1-Distill-Llama-8B:1 DeepSeek-R1-Distill-Llama-70B:4 Meta-Llama-3.1-8B-Instruct:1 Qwen2.5-72B-Instruct-AWQ:2 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct:4 Meta-Llama-3.1-70B-Instruct:4 Qwen2.5-0.5B-Instruct:1 QwQ-32B:2 Qwen2.5-0.5B-Instruct-AWQ:1 QwQ-32B-AWQ:1 Qwen3-32B:2 Qwen3-30B-A3B:2)

curr_dir=/home/s_limingge/ascend_test_suite
log_name_suffix=$(date +"%Y%m%d")

declare -A npu_server_list=(
    ["10.9.1.6"]="AICC_001"
    ["10.9.1.74"]="AICC_003"
    ["10.9.1.34"]="AICC_004"
    ["10.9.1.26"]="AICC_005"
    ["10.9.1.46"]="AICC_006"
    ["10.9.1.58"]="AICC_007"
    ["10.9.1.30"]="AICC_008"
    ["10.9.1.38"]="AICC_009"
    ["10.9.1.70"]="AICC_010"
    ["10.9.1.42"]="AICC_011"
    ["10.9.1.66"]="AICC_012"
    ["10.9.1.50"]="AICC_013"
    ["10.9.1.62"]="AICC_014"
    ["10.9.1.54"]="AICC_015"
)

declare -A local_ip_map=(
    ["10.9.1.6"]="192.168.0.156"
    ["10.9.1.74"]="192.168.0.123"
    ["10.9.1.34"]="192.168.0.77"
    ["10.9.1.26"]="192.168.0.247"
    ["10.9.1.46"]="192.168.0.93"
    ["10.9.1.58"]="192.168.0.100"
    ["10.9.1.30"]="192.168.0.87"
    ["10.9.1.38"]="192.168.0.236"
    ["10.9.1.70"]="192.168.0.185"
    ["10.9.1.42"]="192.168.0.61"
    ["10.9.1.66"]="192.168.0.166"
    ["10.9.1.50"]="192.168.0.127"
    ["10.9.1.62"]="192.168.0.171"
    ["10.9.1.54"]="192.168.0.246"
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

model_list=()

if [ ! -z "$candidate_models" ]; then
    for name in $candidate_models; do
        for item in "${full_model_list[@]}"; do
            model=`echo "$item" | awk -F : '{print $1}'`
            if [[ "$model" =~ ^$name$ ]]; then
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

processed_models="${curr_dir}/processed_models_${log_name_suffix}"
touch ${processed_models}

# schedule_policies=('DynamicSplitFuseV2' 'PrefillFirst')
schedule_policies=('DynamicSplitFuseV2')
ret_code=0

for option in "${schedule_policies[@]}"; do
    use_prefix_cache_flag=1
    for ((i=1; i<=2; i=i+1)); do
        swap_space=40
        for ((j=1; j<=1; j=j+1)); do
            for item in "${model_list[@]}"; do
                model=`echo "$item" | awk -F : '{print $1}'`
                gpu_quantity=`echo "$item" | awk -F : '{print $2}'`

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
                    if [ $TEST_TYPE != "Smoke" ]; then
                        touch ${filename}
                    fi
                fi

                echo "尝试同时在${server_list[@]}服务器上面启动测试......"
                
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
                        if [ $ip == "10.9.1.6" ]; then
                            sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@10.9.1.6 /home/s_limingge/job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $version > "$curr_dir/${filename}_${seq_num}" &
                            pid_map[$!]="10.9.1.6"
                        else
                            ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@$ip /home/s_limingge/job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $version > "$curr_dir/${filename}_${seq_num}" &
                            pid_map[$!]=$ip
                        fi
                    else
                        if [ $ip == "10.9.1.6" ]; then
                            sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@10.9.1.6 /home/s_limingge/job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $version &
                            pid_map[$!]="10.9.1.6"
                        else
                            ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@$ip /home/s_limingge/job_executor_for_${TEST_TYPE}Test.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $version &
                            pid_map[$!]=$ip
                        fi
                    fi
                    
                    ((seq_num++))
                done

                success=0
                # 等待所有服务器任务启动完成
                remaining=${#server_list[@]}
                while (( remaining > 0 )); do
                    wait -n -p done_pid
                    err=$?
                    
                    echo "任务启动结束，服务器：${pid_map[$done_pid]} (PID=$done_pid)"

                    if [ $err -ne 0 ]; then
                        if [ $err -eq 10 ]; then
                            echo "${pid_map[$done_pid]}暂无资源, 中止当前模型测试任务，尝试进行下一个测试任务......"
                        else
                            echo "${pid_map[$done_pid]}测试环境配置失败, 中止当前模型测试任务，尝试进行下一个测试任务......"
                        fi
                        
                        # 启动失败，清理工作
                        for ip in ${server_list[@]}; do
                            if [ $ip == "10.9.1.6" ]; then
                                sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker stop siginfer_ascend_${TEST_TYPE}Test_${job_count}
                                sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker rm siginfer_ascend_${TEST_TYPE}Test_${job_count}
                            else
                                ssh -o ConnectionAttempts=3 s_limingge@$ip docker stop siginfer_ascend_${TEST_TYPE}Test_${job_count}
                                ssh -o ConnectionAttempts=3 s_limingge@$ip docker rm siginfer_ascend_${TEST_TYPE}Test_${job_count}
                            fi
                        done

                        ret_code=$err
                        success=1
                        break
                    fi

                    ((remaining--))
                done

                # 任务启动失败
                if [ $success -eq 1 ]; then
                    continue
                fi

                echo "开始执行模型${TEST_TYPE}测试任务......"

                if [ $TEST_TYPE == "Smoke" ]; then
                    # 获取模型启动命令，并做为参数传入
                    exec_cmd=""
                    for ((k=0; k<$seq_num; k=k+1)); do
                        launch_cmd=`tail -n 3 "$curr_dir/${filename}_${k}" | head -n 1`
                        exec_cmd+="$launch_cmd\n"
                    done

                    full_cmd=${exec_cmd%??}

                    echo "docker run --rm --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${npu_server_list[${server_list[0]}]} --url http://${server_list[0]}:$((6543+${job_count}))/v1 --model $model --gpu 910B --cmd \"$full_cmd\""
                    docker run --rm --entrypoint /test/start.sh openai:0826 --file $filename --email limingge@xcoresigma.com --env=${npu_server_list[${server_list[0]}]} --url http://${server_list[0]}:$((6543+${job_count}))/v1 --model $model --gpu 910B --cmd "\"$full_cmd\""
                elif [ $TEST_TYPE == "Performance" ]; then
                    if [ $model == "Qwen3-235B-A22B" ]; then
                        data_path="/home/weight/Qwen3"
                    else
                        data_path="/home/weight"
                    fi
                    
                    # 开始执行测试
                    if [ $TEST_PARAM == "Random" ]; then
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
                        ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@${server_list[0]} "
                            docker exec siginfer_ascend_PerformanceTest_${job_count} /bin/bash -c \"
                                pip3 install dataSets pillow aiohttp

                                for pair in ${length_pairs[@]}; do
                                    input_len=\\\$(echo \\\$pair | cut -d ':' -f 1)
                                    output_len=\\\$(echo \\\$pair | cut -d ':' -f 2)

                                    echo \\\"========================================================\\\"
                                    echo \\\"Random Testing input=\\\$input_len, output=\\\$output_len\\\"
                                    echo \\\"========================================================\\\"

                                    for concurrency in ${concurrency_list[@]}; do
                                        if [ \\\$input_len -gt 30000 ] && [ \\\$concurrency -gt 5 ]; then
                                            break
                                        fi
                                        
                                        prompts=\\\$((concurrency * 4))
                                        echo \\\"Testing concurrency=\\\$concurrency, prompts=\\\$prompts\\\"
                                        echo \\\"python3 /SigInfer/script/benchmark/benchmark_serving.py --backend openai --port \\\$((8765+${job_count})) --host 0.0.0.0 --model ${model} --tokenizer ${data_path}/${model}/ --endpoint /v1/completions --dataset-name random --random-input-len \\\$input_len --random-output-len \\\$output_len --num-prompts \\\$prompts --request-rate inf --max-concurrency \\\$concurrency --ignore-eos\\\"

                                        python3 /SigInfer/script/benchmark/benchmark_serving.py \
                                        --backend openai \
                                        --port \\\$((8765+${job_count})) \
                                        --host 0.0.0.0 \
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
                        " > "$curr_dir/$filename"
                    else
                        concurrency_list=(100 200 300 400 500 600 700 800 900 1000)
                        # Sharegpt
                        ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@${server_list[0]} "
                            docker exec siginfer_ascend_PerformanceTest_${job_count} /bin/bash -c \"
                                pip3 install dataSets pillow aiohttp

                                for concurrency in ${concurrency_list[@]}; do
                                    prompts=\\\$((concurrency * 4))
                                    echo \\\"Testing concurrency=\\\$concurrency, prompts=\\\$prompts\\\"
                                    echo \\\"python3 /SigInfer/script/benchmark/benchmark_serving.py --backend openai --port \\\$((8765+${job_count})) --host 127.0.0.1 --model ${model} --tokenizer ${data_path}/${model}/ --endpoint /v1/completions --dataset-name sharegpt --dataset-path /home/weight/ShareGPT_V3_unfiltered_cleaned_split.json --num-prompts \\\$prompts --request-rate inf --max-concurrency \\\$concurrency\\\"

                                    python3 /SigInfer/script/benchmark/benchmark_serving.py \
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
                        " > "$curr_dir/$filename"
                    fi
                elif [ $TEST_TYPE == "Accuracy" ]; then
                    unset pid_map
                    declare -A pid_map
                    # 开始执行测试
                    docker run -i --rm --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /evalscope.sh  evalscope:0616 -M $model --port $((9701+$job_count)) --host $local_master_ip --number 10 -P 10 --dataset mmlu,ceval > "./logs/${filename}_evalscope_1.log" 2>&1 &
                    pid_map[$!]="evalscope_mmlu,ceval"
                    docker run -i --rm --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /evalscope.sh  evalscope:0616 -M $model --port $((9701+$job_count)) --host $local_master_ip --number 200 -P 10 --dataset gsm8k,ARC_c > "./logs/${filename}_evalscope_2.log" 2>&1 &
                    pid_map[$!]="evalscope_gsm8k,ARC_c"
                    docker run -i --rm --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /sglang.sh  evalscope:0616 -M $model --port $((9701+$job_count)) --host $local_master_ip > "./logs/${filename}_SGLang_3.log" 2>&1 &
                    pid_map[$!]="SGLang_mmlu,gsm8k"
                    
                    # 等待所有后台测试任务结束
                    remaining=3
                    while (( remaining > 0 )); do
                        wait -n -p done_pid
                        err=$?

                        echo "测试任务：${pid_map[$done_pid]}结束!"
                        if [ $err -ne 0 ]; then
                            echo "测试结果失败！请检查......"
                        fi

                        ((remaining--))
                    done

                    touch "$curr_dir/report/${log_name_suffix}_result.txt"

                    eval_res_1=$(tail -n 1 "./logs/${filename}_evalscope_1.log")
                    eval_res_2=$(tail -n 1 "./logs/${filename}_evalscope_2.log")
                    sglang_res_3=$(tail -n 5 "./logs/${filename}_SGLang_3.log")
                    
                    echo "$model+$eval_res_1 $eval_res_2+${sglang_res_3//$'\n'/}" >> "$curr_dir/report/${log_name_suffix}_result.txt"
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
                    if [ $ip == "10.9.1.6" ]; then
                        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker stop siginfer_ascend_${TEST_TYPE}Test_${job_count}
                        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker rm siginfer_ascend_${TEST_TYPE}Test_${job_count}
                    else
                        ssh -o ConnectionAttempts=3 s_limingge@$ip docker stop siginfer_ascend_${TEST_TYPE}Test_${job_count}
                        ssh -o ConnectionAttempts=3 s_limingge@$ip docker rm siginfer_ascend_${TEST_TYPE}Test_${job_count}
                    fi
                done
                
                # 发送测试报告
                if [ $send_report -eq 1 ]; then
                    if [ -z $version ]; then
                        latest_tag=$(jfrog rt curl --server-id=my-jcr /api/docker/docker-local/v2/siginfer-aarch64-ascend/tags/list | jq -r '.tags[]' \
                        | xargs -I% sh -c "echo -n \"%  \"; \
                            jfrog rt curl --server-id=my-jcr \
                            /api/storage/docker-local/siginfer-aarch64-ascend/% \
                        | jq -r '.created'" | sort -k2 -r | head -n1 | awk '{print $1}')
                    else
                        latest_tag=$version
                    fi

                    if [ $TEST_TYPE == "Smoke" ]; then
                        if [ $use_prefix_cache_flag -eq 1 ]; then
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}_${option}_Use-prefix-cache" "$curr_dir/$filename"
                            else
                                python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}_${option}_Use-prefix-cache_Swap-space" "$curr_dir/$filename"
                            fi
                        else
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}_${option}" "$curr_dir/$filename"
                            else
                                python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}_${option}_Swap-space" "$curr_dir/$filename"
                            fi
                        fi
                    elif [ $TEST_TYPE == "Performance" ]; then
                        # 获取模型启动命令，并做为参数传入
                        exec_cmd=`cat "$curr_dir/cron_job_${log_name_suffix}_${job_count}.log" | grep "docker run"`
                        # 获取测试命令，并做为参数传入
                        test_cmd=`cat "$curr_dir/$filename" | grep "benchmark_serving.py" | head -n 1 | sed -E 's/--(random-input-len|random-output-len|num-prompts|max-concurrency)\s+[0-9]+/--\1 xxx/g'`
                        if [ $use_prefix_cache_flag -eq 1 ]; then
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}_${option}_Use-prefix-cache" "$exec_cmd" "$test_cmd" "$curr_dir/$filename"
                            else
                                python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}_${option}_Use-prefix-cache_Swap-space" "$exec_cmd" "$test_cmd" "$curr_dir/$filename"
                            fi
                        else
                            if [ $swap_space -eq 0 ]; then
                                python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}_${option}" "$exec_cmd" "$test_cmd" "$curr_dir/$filename"
                            else
                                python3 $curr_dir/WriteReportToExcel.py "$TEST_PARAM" "${model}_${option}_Swap-space" "$exec_cmd" "$test_cmd" "$curr_dir/$filename"
                            fi
                        fi
                    fi
                fi
                
                # 记录测试进度
                if [ $use_prefix_cache_flag -eq 1 ]; then
                    if [ $swap_space -eq 0 ]; then
                        echo ${model}_${option}"_use-prefix-cache" >> ${processed_models}
                    else
                        echo ${model}_${option}"_use-prefix-cache_swap-space" >> ${processed_models}
                    fi
                else
                    if [ $swap_space -eq 0 ]; then
                        echo ${model}_${option} >> ${processed_models}
                    else
                        echo ${model}_${option}"_swap-space" >> ${processed_models}
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
