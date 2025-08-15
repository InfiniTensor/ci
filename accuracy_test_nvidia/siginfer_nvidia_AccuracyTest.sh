#!/bin/bash

# 接收参数
send_report=$1
server_list=($2)
candidate_models=$3
job_count=$4
version=$5

# full_model_list=(DeepSeek-R1:8 DeepSeek-R1-AWQ:8 DeepSeek-R1-W8A8:8 DeepSeek-R1-Distill-Qwen-14B:1 DeepSeek-R1-Distill-Qwen-32B:1 DeepSeek-R1-Distill-Llama-8B:1 DeepSeek-R1-Distill-Llama-70B:4 Meta-Llama-3.1-8B-Instruct:1 Meta-Llama-3.1-70B-Instruct:4 Qwen2.5-0.5B-Instruct:1 Qwen2.5-1.5B-Instruct:1 Qwen2.5-3B-Instruct:1 Qwen2.5-7B-Instruct:1 Qwen2.5-14B-Instruct:1 QwQ-32B:2 Qwen2.5-0.5B-Instruct-AWQ:1 Qwen2.5-1.5B-Instruct-AWQ:1 Qwen2.5-3B-Instruct-AWQ:1 Qwen2.5-7B-Instruct-AWQ:1 Qwen2.5-14B-Instruct-AWQ:1 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct-AWQ:2 QwQ-32B-AWQ:1 Qwen3-32B:2 Qwen2.5-32B-Instruct:2 Qwen2.5-72B-Instruct:4 Qwen3-30B-A3B:2 DeepSeek-R1-Distill-Qwen-7B:1 DeepSeek-R1-Distill-Qwen-1.5B:1 Qwen3-235B-A22B-FP8:4 DeepSeek-V3-0324:8 Qwen3-30B-A3B-Instruct:2)
full_model_list=(Qwen3-235B-A22B:8:H20 DeepSeek-R1-Distill-Qwen-32B:1:H20 DeepSeek-R1-Distill-Llama-70B:4:H20 Qwen2.5-72B-Instruct-AWQ:1:H20 Qwen2.5-32B-Instruct-AWQ:1:H20 Qwen2.5-72B-Instruct:4:H20 Qwen3-235B-A22B-FP8:4:H20)
curr_dir=/home/s_limingge/accuracy_test_nvidia
GPU_MODEL="H20"

declare -A A800_server_list=(
    ["A800-001"]="10.208.130.44"
)

declare -A H20_server_list=(
    ["H20-001"]="10.9.1.14"
)

declare -A H100_server_list=(
    ["H100-001"]="192.168.100.106"
)

declare -A L20_server_list=(
    ["L20-001"]="192.168.100.106"
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
    for name in "${candidate_models[@]}"; do
        for item in "${full_model_list[@]}"; do
            model=`echo "$item" | awk -F : '{print $1}'`
            if [[ "$model" =~ ^$name$ ]]; then
                model_list+=($item)
                break
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

schedule_policies=('DynamicSplitFuseV2')

for option in "${schedule_policies[@]}"; do
    use_prefix_cache_flag=1
    for ((i=1; i<=1; i=i+1)); do
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

                filename=$(date +"%Y%m%d")_${model}_
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
                        filename+=${option}""
                    else
                        echo "开始测试模型: $model, 启动选项: --schedule-policy $option, --swap-space=40"
                        filename+=${option}"_swap-space"
                    fi
                fi

                cd $curr_dir

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

                    ssh -o ConnectionAttempts=3 s_limingge@$ip /home/s_limingge/job_executor_for_AccuracyTest.sh $model $gpu_quantity $use_prefix_cache_flag $option $swap_space $local_master_ip $seq_num $job_count $GPU_MODEL $version &
                    pid_map[$!]=$ip
                    
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
                                sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker stop siginfer_nvidia_AccuracyTest_${job_count}
                                sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker rm siginfer_nvidia_AccuracyTest_${job_count}
                            else
                                ssh -o ConnectionAttempts=3 s_limingge@$ip docker stop siginfer_nvidia_AccuracyTest_${job_count}
                                ssh -o ConnectionAttempts=3 s_limingge@$ip docker rm siginfer_nvidia_AccuracyTest_${job_count}
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

                unset pid_map
                declare -A pid_map
                # 开始执行测试
                nohup docker run -i --rm --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /evalscope.sh  evalscope:0616 -M $model --port $((9701+$job_count)) --host $local_master_ip --number 10 -P 10 --dataset mmlu,ceval > "./logs/${filename}_evalscope_1.log" 2>&1 &
                pid_map[$!]="evalscope_mmlu,ceval"
                nohup docker run -i --rm --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /evalscope.sh  evalscope:0616 -M $model --port $((9701+$job_count)) --host $local_master_ip --number 200 -P 10 --dataset gsm8k,ARC_c > "./logs/${filename}_evalscope_2.log" 2>&1 &
                pid_map[$!]="evalscope_gsm8k,ARC_c"
                nohup docker run -i --rm --privileged=true --cap-add=ALL --pid=host --gpus=all --network=host  -v /home/weight/:/home/weight/ --entrypoint /sglang.sh  evalscope:0616 -M $model --port $((9701+$job_count)) --host $local_master_ip > "./logs/${filename}_SGLang_3.log" 2>&1 &
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

                touch "$curr_dir/report/$(date +"%Y%m%d")_result.txt"

                eval_res_1=$(tail -n 1 "./logs/${filename}_evalscope_1.log")
                eval_res_2=$(tail -n 1 "./logs/${filename}_evalscope_2.log")
                sglang_res_3=$(tail -n 5 "./logs/${filename}_SGLang_3.log")
                echo "$model+$eval_res_1 $eval_res_2+${sglang_res_3//$'\n'/}" >> "$curr_dir/report/$(date +"%Y%m%d")_result.txt"

                echo "测试完成！"

                # 测试完成，清理工作
                for ip in ${server_list[@]}; do
                    if [ $ip == "10.9.1.6" ]; then
                        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker stop siginfer_nvidia_AccuracyTest_${job_count}
                        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@10.9.1.6 docker rm siginfer_nvidia_AccuracyTest_${job_count}
                    else
                        ssh -o ConnectionAttempts=3 s_limingge@$ip docker stop siginfer_nvidia_AccuracyTest_${job_count}
                        ssh -o ConnectionAttempts=3 s_limingge@$ip docker rm siginfer_nvidia_AccuracyTest_${job_count}
                    fi
                done
                
                # 发送测试报告
                # if [ $send_report -eq 1 ]; then
                #     if [ -z $version ]; then
                #         latest_tag=$(jfrog rt curl --server-id=my-jcr /api/docker/docker-local/v2/siginfer-x86_64-nvidia/tags/list | jq -r '.tags[]' \
                #         | xargs -I% sh -c "echo -n \"%  \"; \
                #             jfrog rt curl --server-id=my-jcr \
                #             /api/storage/docker-local/siginfer-x86_64-nvidia/% \
                #         | jq -r '.created'" | sort -k2 -r | head -n1 | awk '{print $1}')
                #     else
                #         latest_tag=$version
                #     fi

                #     if [ $use_prefix_cache_flag -eq 1 ]; then
                #         if [ $swap_space -eq 0 ]; then
                #             #...
                #         else
                #             #...
                #         fi
                #     else
                #         if [ $swap_space -eq 0 ]; then
                #             #...
                #         else
                #             #...
                #         fi
                #     fi
                # fi
                
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
