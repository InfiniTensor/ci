#!/bin/bash

# 接收参数
send_report=$1
server_list=($2)
candidate_models=$3
job_count=$4
version=$5

full_model_list=(DeepSeek-R1-AWQ:8 DeepSeek-R1-W8A8:16 DeepSeek-R1-Distill-Qwen-14B:1 DeepSeek-R1-Distill-Qwen-32B:2 DeepSeek-R1-Distill-Llama-8B:1 DeepSeek-R1-Distill-Llama-70B:4 Meta-Llama-3.1-8B-Instruct:1 Meta-Llama-3.1-70B-Instruct:4 Qwen2.5-0.5B-Instruct:1 Qwen2.5-1.5B-Instruct:1 Qwen2.5-3B-Instruct:1 Qwen2.5-7B-Instruct:1 Qwen2.5-14B-Instruct:1 QwQ-32B:2 Qwen2.5-0.5B-Instruct-AWQ:1 Qwen2.5-1.5B-Instruct-AWQ:1 Qwen2.5-3B-Instruct-AWQ:1 Qwen2.5-7B-Instruct-AWQ:1 Qwen2.5-14B-Instruct-AWQ:1 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct-AWQ:2 QwQ-32B-AWQ:1 Qwen3-32B:2 Qwen2.5-32B-Instruct:2 Qwen2.5-72B-Instruct:4 Qwen3-30B-A3B:2)
curr_dir=/home/s_limingge/performance_test_ascend
concurrency_list=(1 5 10 20 50 100)
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

echo "*************开始执行冒烟测试任务，日期时间:$(date +"%Y%m%d_%H%M%S")***************"
echo "测试模型列表: ${model_list[@]}"

if [ -z $version ]; then
    echo "引擎版本: Latest"
else
    echo "引擎版本: ${version}"
fi

processed_models=${curr_dir}/"processed_models"_$(date +"%Y%m%d")
touch ${processed_models}

for option in 'DynamicSplitFuseV2'; do
    use_prefix_cache_flag=1
    for ((i=1; i<=1; i=i+1)); do
        swap_space=0
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

                filename=$(date +"%Y%m%d")_${model}_
                if [ $use_prefix_cache_flag -eq 1 ]; then
                    if [ $swap_space -eq 0 ]; then
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option, --use-prefix-cache"
                        filename+=${option}"_use-prefix-cache.log"
                    else
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option, --use-prefix-cache, --swap-space=40"
                        filename+=${option}"_use-prefix-cache_swap-space.log"
                    fi
                else
                    if [ $swap_space -eq 0 ]; then 
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option"
                        filename+=${option}".log"
                    else
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option, --swap-space=40"
                        filename+=${option}"_swap-space.log"
                    fi
                fi

                cd $curr_dir
                touch ${filename}

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

                    if [ $ip == "10.9.1.6" ]; then
                        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 /home/s_limingge/job_executor_for_PerformanceTest.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $version &
                        pid_map[$!]="10.9.1.6"
                    else
                        ssh -o ConnectionAttempts=3 s_limingge@$ip /home/s_limingge/job_executor_for_PerformanceTest.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $version &
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
                                sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker stop siginfer_ascend_PerformanceTest_${job_count}
                                sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker rm siginfer_ascend_PerformanceTest_${job_count}
                            else
                                ssh -o ConnectionAttempts=3 s_limingge@$ip docker stop siginfer_ascend_PerformanceTest_${job_count}
                                ssh -o ConnectionAttempts=3 s_limingge@$ip docker rm siginfer_ascend_PerformanceTest_${job_count}
                            fi
                        done
                        success=1
                        break
                    fi

                    ((remaining--))
                done

                # 任务启动失败
                if [ $success -eq 1 ]; then
                    continue
                fi

                echo "开始执行模型精度测试任务......"
                
                # 开始执行测试
                # Random
                ssh -o ConnectionAttempts=3 s_limingge@${server_list[0]} "
                    docker exec siginfer_ascend_PerformanceTest_${job_count} /bin/bash -c \"
                        pip3 install dataSets pillow aiohttp

                        for pair in ${length_pairs[@]}; do
                            input_len=\\\$(echo \\\$pair | cut -d ':' -f 1)
                            output_len=\\\$(echo \\\$pair | cut -d ':' -f 2)

                            echo \\\"========================================================\\\"
                            echo \\\"Random Testing input=\\\$input_len, output=\\\$output_len\\\"
                            echo \\\"========================================================\\\"

                            for concurrency in ${concurrency_list[@]}; do
                                prompts=\\\$((concurrency * 4))
                                echo "Testing concurrency=\\\$concurrency, prompts=\\\$prompts"

                                python3 /SigInfer/script/benchmark/benchmark_serving.py \
                                --port 9701 \
                                --host 127.0.0.1 \
                                --model ${model} \
                                --tokenizer /home/weight/DeepSeek-R1-0528/ \
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

                # Sharegpt
                # ssh -o ConnectionAttempts=3 s_limingge@$local_master_ip "
                #     docker exec -it siginfer_nvidia_PerformanceTest_${job_count} /bin/bash \"
                #         for pair in \"${length_pairs[@]}\"; do
                #             input_len=$(echo \$pair | cut -d ' ' -f 1)
                #             output_len=$(echo \$pair | cut -d ' ' -f 2)

                #             echo "============================================================="
                #             echo "ShareGPT Testing input=\$input_len, output=\$output_len"
                #             echo "============================================================="

                #             for concurrency in \"${concurrency_list[@]}\"; do
                #                 prompts=\$((concurrency * 4))
                #                 echo "Testing concurrency=\$concurrency, prompts=\$prompts"

                #                 python3 /SigInfer/script/benchmark/benchmark_serving.py \
                #                 --port 28881 \
                #                 --host 127.0.0.1 \
                #                 --model deepseek \
                #                 --tokenizer /home/weight/DeepSeek-R1-0528/ \
                #                 --endpoint /v1/completions \
                #                 --dataset-name sharegpt \
                #                 --dataset-path /home/weight/ShareGPT_V3_unfiltered_cleaned_split.json \
                #                 --random-input-len \$input_len \
                #                 --random-output-len \$output_len \
                #                 --num-prompts \$prompts \
                #                 --request-rate inf \
                #                 --max-concurrency \$concurrency \
                #                 --ignore-eos
                #             done
                #         done
                #     \"
                # "

                echo "测试完成！"

                # 测试完成，清理工作
                for ip in ${server_list[@]}; do
                    if [ $ip == "10.9.1.6" ]; then
                        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker stop siginfer_ascend_PerformanceTest_${job_count}
                        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker rm siginfer_ascend_PerformanceTest_${job_count}
                    else
                        ssh -o ConnectionAttempts=3 s_limingge@$ip docker stop siginfer_ascend_PerformanceTest_${job_count}
                        ssh -o ConnectionAttempts=3 s_limingge@$ip docker rm siginfer_ascend_PerformanceTest_${job_count}
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

                    if [ $use_prefix_cache_flag -eq 1 ]; then
                        if [ $swap_space -eq 0 ]; then
                            python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}_${option}_Use-prefix-cache" "$curr_dir/$filename"
                        else
                            python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}_${option}_Use-prefix-cache_Swap-Space=40" "$curr_dir/$filename"
                        fi
                    else
                        if [ $swap_space -eq 0 ]; then
                            python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}_${option}" "$curr_dir/$filename"
                        else
                            python3 $curr_dir/SendMsgToBot.py "$latest_tag" "${model}_${option}_Swap-Space=40" "$curr_dir/$filename"
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
            swap_space=40
        done
        use_prefix_cache_flag=$((-use_prefix_cache_flag))
    done
done

echo "测试全部完成！"
