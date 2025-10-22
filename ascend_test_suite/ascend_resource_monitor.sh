#!/bin/bash

# 捕获 SIGINT (Ctrl+C)、SIGTERM 和 EXIT 信号
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

TEST_TYPE=$1
ENGINE_TYPE=$2
curr_dir=$(pwd)

if [ -z $TEST_TYPE ]; then
    echo "Parameter Test_Type required!"
    exit 1
elif [ $TEST_TYPE != "Smoke" ] && [ $TEST_TYPE != "Performance" ] && [ $TEST_TYPE != "Stability" ] && [ $TEST_TYPE != "Accuracy" ]; then
    echo "Test_Type is wrong!"
    exit 1
fi

if [ -z $ENGINE_TYPE ]; then
    echo "Parameter PLATFORM required!"
    exit 1
elif [ $ENGINE_TYPE != "SigInfer" ] && [ $ENGINE_TYPE != "vLLM" ] && [ $ENGINE_TYPE != "MindIE" ]; then
    echo "Inference Engine Type is wrong!"
    exit 1
fi

if [ $TEST_TYPE == "Performance" ]; then
    TEST_PARAM=$3
    version=$4
    if [ -z $TEST_PARAM ]; then
        echo "Parameter Test_Param required!"
        exit 1
    elif [ $TEST_PARAM != "Random" ] && [ $TEST_PARAM != "SharedGPT" ]; then
        echo "Test_Param is wrong!"
        exit 1
    fi
else
    version=$3
fi

if [ $ENGINE_TYPE == "SigInfer" ]; then
    declare -A npu_server_list=(
        # ["aicc001"]="10.9.1.6"
        ["aicc003"]="10.9.1.74"
        ["aicc004"]="10.9.1.34"
        ["aicc005"]="10.9.1.26"
        ["aicc006"]="10.9.1.46"
        ["aicc007"]="10.9.1.58"
        ["aicc008"]="10.9.1.30"
        ["aicc009"]="10.9.1.38"
        ["aicc010"]="10.9.1.70"
        ["aicc011"]="10.9.1.42"
        ["aicc012"]="10.9.1.66"
        ["aicc013"]="10.9.1.50"
        # ["aicc014"]="10.9.1.62"
        # ["aicc015"]="10.9.1.54"
    )
    if [ -z $version ]; then
        python3 $curr_dir/script_generator_for_SigInfer.py ${TEST_TYPE} "latest"
    else
        python3 $curr_dir/script_generator_for_SigInfer.py ${TEST_TYPE} $version
    fi
elif [ $ENGINE_TYPE == "vLLM" ]; then
    declare -A npu_server_list=(
        # ["aicc001"]="10.9.1.6"
        ["aicc003"]="10.9.1.74"
        ["aicc004"]="10.9.1.34"
        ["aicc005"]="10.9.1.26"
        ["aicc006"]="10.9.1.46"
        ["aicc007"]="10.9.1.58"
        ["aicc008"]="10.9.1.30"
        ["aicc009"]="10.9.1.38"
        ["aicc010"]="10.9.1.70"
        ["aicc011"]="10.9.1.42"
        ["aicc012"]="10.9.1.66"
        ["aicc013"]="10.9.1.50"
        # ["aicc014"]="10.9.1.62"
        # ["aicc015"]="10.9.1.54"
    )
    if [ -z $version ]; then
        python3 $curr_dir/script_generator_for_vLLM.py ${TEST_TYPE} "latest"
    else
        python3 $curr_dir/script_generator_for_vLLM.py ${TEST_TYPE} $version
    fi
elif [ $ENGINE_TYPE == "MindIE" ]; then
    declare -A npu_server_list=(
        ["aicc009"]="10.9.1.38"
        ["aicc010"]="10.9.1.70"
    )
    python3 $curr_dir/script_generator_for_MindIE.py ${TEST_TYPE}
fi

# full_model_list=(DeepSeek-R1-0528:16 DeepSeek-R1-W8A8:16 DeepSeek-R1-AWQ:8 DeepSeek-R1-Distill-Llama-70B:4 DeepSeek-R1-Distill-Qwen-32B:2 Qwen3-30B-A3B:2 Qwen2.5-32B-Instruct:2 Qwen2.5-72B-Instruct:4 Meta-Llama-3.1-70B-Instruct:4)
# full_model_list=(DeepSeek-R1-Distill-Qwen-14B:1 DeepSeek-R1-Distill-Llama-8B:1 Meta-Llama-3.1-8B-Instruct:1 Qwen2.5-0.5B-Instruct:1 Qwen2.5-1.5B-Instruct:1 Qwen2.5-3B-Instruct:1 Qwen2.5-7B-Instruct:1 Qwen2.5-14B-Instruct:1 QwQ-32B:2 Qwen2.5-0.5B-Instruct-AWQ:1 Qwen2.5-1.5B-Instruct-AWQ:1 Qwen2.5-3B-Instruct-AWQ:1 Qwen2.5-7B-Instruct-AWQ:1 Qwen2.5-14B-Instruct-AWQ:1 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct-AWQ:2 QwQ-32B-AWQ:1 Qwen3-32B:2)
full_model_list=(DeepSeek-R1-AWQ:8 DeepSeek-R1-W8A8:16 DeepSeek-R1-Distill-Qwen-14B:1 DeepSeek-R1-Distill-Qwen-32B:2 DeepSeek-R1-Distill-Llama-8B:1 DeepSeek-R1-Distill-Llama-70B:4 Meta-Llama-3.1-8B-Instruct:1 Meta-Llama-3.1-70B-Instruct:4 Qwen2.5-0.5B-Instruct:1 Qwen2.5-1.5B-Instruct:1 Qwen2.5-3B-Instruct:1 Qwen2.5-7B-Instruct:1 Qwen2.5-14B-Instruct:1 QwQ-32B:2 Qwen2.5-0.5B-Instruct-AWQ:1 Qwen2.5-1.5B-Instruct-AWQ:1 Qwen2.5-3B-Instruct-AWQ:1 Qwen2.5-7B-Instruct-AWQ:1 Qwen2.5-14B-Instruct-AWQ:1 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct-AWQ:2 QwQ-32B-AWQ:1 Qwen3-32B:2 Qwen2.5-32B-Instruct:2 Qwen2.5-72B-Instruct:4 Qwen3-30B-A3B:2)
full_model_list_for_performance=(Qwen3-235B-A22B:8 DeepSeek-R1-Distill-Qwen-32B:2 DeepSeek-R1-Distill-Llama-70B:4 Qwen2.5-72B-Instruct-AWQ:2 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct:4 DeepSeek-R1:16)
# full_model_list=(DeepSeek-R1-AWQ:8 DeepSeek-R1-W8A8:16 DeepSeek-R1-Distill-Qwen-1.5B:1 Qwen3-235B-A22B:8 DeepSeek-R1-Distill-Qwen-32B:2 DeepSeek-R1-Distill-Llama-8B:1 DeepSeek-R1-Distill-Llama-70B:4 Meta-Llama-3.1-8B-Instruct:1 Qwen2.5-72B-Instruct-AWQ:2 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct:4 Meta-Llama-3.1-70B-Instruct:4 Qwen2.5-0.5B-Instruct:1 QwQ-32B:2 Qwen2.5-0.5B-Instruct-AWQ:1 QwQ-32B-AWQ:1 Qwen3-32B:2 Qwen3-30B-A3B:2)
full_model_list_for_stability=(DeepSeek-R1-Distill-Llama-70B:4 DeepSeek-R1-Distill-Qwen-32B:2 Qwen2.5-32B-Instruct-AWQ:1)

log_name_suffix=$(date +"%Y%m%d")
export TASK_START_TIME=${log_name_suffix}
parallel=3

rm -rf $curr_dir/*.log
rm -rf $curr_dir/*.log_*
rm -rf $curr_dir/*.txt
rm -rf $curr_dir/processed_models_*

if [ ! -d "$curr_dir/report_${log_name_suffix}" ]; then
    mkdir $curr_dir/report_${log_name_suffix}
fi

search_servers() {
    NPU_QUANTITY=$1
    local -n servers_found=$2     # 传名引用

    if [ $NPU_QUANTITY -lt 8 ]; then
        SERVER_QUANTITY=1
    else
        SERVER_QUANTITY=$(($NPU_QUANTITY/8))
    fi

    echo "正在搜索 ${SERVER_QUANTITY} 台GPU服务器......"
    
    servers_found=()
    for key in "${!npu_server_list[@]}"; do
        echo "$key => ${npu_server_list[$key]}"
        if [ $key == 'aicc001' ]; then
            sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@${npu_server_list['aicc001']} "# 目标空闲 GPU 数量
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 npu-smi 获取 GPU 使用情况
                GPU_INFO=(\$(npu-smi info | grep \"No\ running\ processes\ found\ in\ NPU\" | awk '{print \$8}'))
                # 检查空闲 GPU 数量
                FREE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前空闲 GPU 数量：\$FREE_COUNT, 索引: \${GPU_INFO[@]}\"
                # 如果找到足够的空闲 GPU, 则返回结果并退出
                if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                    echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${GPU_INFO[@]}\"
                    exit 0
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${npu_server_list[$key]})
            fi
        else
            ssh -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 s_limingge@${npu_server_list[$key]} "# 目标空闲 GPU 数量
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 npu-smi 获取 GPU 使用情况
                GPU_INFO=(\$(npu-smi info | grep \"No\ running\ processes\ found\ in\ NPU\" | awk '{print \$8}'))
                # if [ $NPU_QUANTITY -ne 16 ]; then
                #    过滤掉第7块和第8块GPU卡
                #    GPU_INFO=\$(echo \"\${GPU_INFO[@]}\" | sed -E 's/\b6\b//g' | sed -E 's/\b7\b//g' | sed -E 's/\s+/ /g' | xargs)
                # fi
                # 检查空闲 GPU 数量
                FREE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前空闲 GPU 数量：\$FREE_COUNT, 索引: \${GPU_INFO[@]}\"
                # 如果找到足够的空闲 GPU, 则返回结果并退出
                if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                    echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${GPU_INFO[@]}\"
                    exit 0
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${npu_server_list[$key]})
            fi
        fi

        if [ ${#servers_found[@]} -ge $SERVER_QUANTITY ]; then
            break
        fi
    done
}

for name in "${!npu_server_list[@]}"; do
    echo "$name => ${npu_server_list[$name]}"
    if [ $name == 'aicc001' ]; then
        sshpass -p 's_limingge' scp "${curr_dir}/job_executor_for_${TEST_TYPE}Test.sh" s_limingge@${npu_server_list['aicc001']}:/home/s_limingge
        sshpass -p 's_limingge' scp "${curr_dir}/npu_lock_manager.sh" s_limingge@${npu_server_list['aicc001']}:/home/s_limingge
    else
        scp "${curr_dir}/job_executor_for_${TEST_TYPE}Test.sh" s_limingge@${npu_server_list[$name]}:/home/s_limingge
        scp "${curr_dir}/npu_lock_manager.sh" s_limingge@${npu_server_list[$name]}:/home/s_limingge
    fi
done

processed_models=${curr_dir}/"processed_models"_${log_name_suffix}
touch ${processed_models}

GPU_resource_demand=()

for item in "${full_model_list[@]}"; do
    model=`echo "$item" | awk -F : '{print $1}'`
    found=0
    # for option in 'DynamicSplitFuseV2' 'PrefillFirst'; do
    for option in 'DynamicSplitFuseV2'; do
        use_prefix_cache_flag=1
        for ((i=1; i<=2; i=i+1)); do
            swap_space=40
            for ((j=1; j<=1; j=j+1)); do
                # 模型已经测试过了，检查下一个
                if [ $use_prefix_cache_flag -gt 0 ]; then
                    if [ $swap_space -eq 0 ]; then
                        if [ ! -z `cat ${processed_models} | grep -w ${model}_${option}_use-prefix-cache` ]; then
                            continue
                        fi
                    else
                        if [ ! -z `cat ${processed_models} | grep -w ${model}_${option}_use-prefix-cache_swap-space` ]; then
                            swap_space=0
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
                            swap_space=0
                            continue
                        fi
                    fi
                fi
                GPU_resource_demand+=(${item})
                found=1
                break
            done
            if [ $found -eq 1 ]; then
                break
            fi
            use_prefix_cache_flag=$((-use_prefix_cache_flag))
        done
        if [ $found -eq 1 ]; then
            break
        fi
    done
done

GPU_resource_demand=($(printf "%s\n" "${GPU_resource_demand[@]}" | uniq))

echo "开始测试模型列表：${GPU_resource_demand[@]}"

if [ -z $version ]; then
    echo "推理引擎版本: Latest"
else
    echo "推理引擎版本: ${version}"
fi

while true; do
    job_count=0
    temp_list=()
    unset pid_map
    declare -A pid_map
    for item in "${GPU_resource_demand[@]}"; do
        model=`echo "$item" | awk -F : '{print $1}'`
        GPU_QUANTITY=`echo "$item" | awk -F : '{print $2}'`
        echo "当前模型: $model, GPU数量: $GPU_QUANTITY"
        search_servers $GPU_QUANTITY servers
        if [ ${#servers[@]} -ge ${SERVER_QUANTITY} ]; then
            echo "已找到满足条件的空闲 GPU, 开始测试模型${model}......"
            echo
            if [ $TEST_TYPE == "Stability" ]; then
                $curr_dir/siginfer_ascend_test.sh 0 "${servers[*]}" ${model} ${job_count} ${TEST_TYPE} ${version} > $curr_dir/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "按任意键结束|测试全部完成"`
            elif [ $TEST_TYPE == "Performance" ]; then
                $curr_dir/siginfer_ascend_test.sh 1 "${servers[*]}" ${model} ${job_count} ${TEST_TYPE} ${TEST_PARAM} ${version} > $curr_dir/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型${TEST_TYPE}测试任务|测试全部完成"`
            else
                if [ $TEST_TYPE == "Smoke" ]; then
                    send_report=0
                else
                    send_report=1
                fi
                $curr_dir/siginfer_ascend_test.sh ${send_report} "${servers[*]}" ${model} ${job_count} ${TEST_TYPE} ${version} > $curr_dir/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型${TEST_TYPE}测试任务|测试全部完成"`
            fi

            if [ $status_msg == "测试全部完成！" ]; then
                echo "模型运行环境配置失败，准备尝试测试下一个模型......"
                echo
                wait $last_pid  # 等待上一个子进程结束
                err=$?          # 保存上一个结束子进程的退出状态
                if [ $err -ne 0 ]; then
                    if [ $err -eq 10 ]; then  # 没有资源，等待超时
                        temp_list+=(${pid_map[$last_pid]})  # 加入队列，稍后重试
                    fi
                else
                    echo "程序出错！"
                fi
                continue
            else
                echo $status_msg
            fi

            ((job_count++))
            if [ $job_count -ge $parallel ]; then
                # 等待所有后台子任务结束
                remaining=$job_count
                while (( remaining > 0 )); do
                    wait -n -p done_pid  # 等待任意一个子进程结束
                    err=$?               # 保存最先结束子进程的退出状态
                    if [ $err -ne 0 ]; then
                        if [ $err -eq 10 ]; then  # 没有资源，等待超时
                            temp_list+=(${pid_map[$done_pid]})  # 加入队列，稍后重试
                        fi
                    fi
                    ((remaining--))
                done

                job_count=0
                echo "当前批量模型测试完成！"
                echo
            fi
        else
            temp_list+=(${item})
            echo "未找到足够的空闲 GPU, 无法测试模型${model}, 准备尝试测试下一个模型......"
            echo
            # 等待一段时间后重新扫描（例如 10 秒）
            sleep 10
        fi
    done

    if [ $job_count -gt 0 ] && [ $job_count -lt $parallel ]; then
        # 等待所有后台子任务结束
        remaining=$job_count
        while (( remaining > 0 )); do
            wait -n -p done_pid  # 等待任意一个子进程结束
            err=$?               # 保存最先结束子进程的退出状态
            if [ $err -ne 0 ]; then
                if [ $err -eq 10 ]; then  # 没有资源，等待超时
                    temp_list+=(${pid_map[$done_pid]})  # 加入队列，稍后重试
                fi
            fi
            ((remaining--))
        done

        echo "当前批量模型测试完成！"
        echo
    fi

    if [[ ${#temp_list[@]} -eq 0 ]]; then
        echo "全部测试完成！"
        break
    else
        GPU_resource_demand=("${temp_list[@]}")
        echo
        echo "准备尝试进行下一轮模型测试: ${GPU_resource_demand[@]}"
        echo
    fi
done

exit 0
