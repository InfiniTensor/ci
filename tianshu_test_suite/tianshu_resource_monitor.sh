#!/bin/bash

USER=$1
TEST_TYPE=$2
curr_dir=$(pwd)

if [ -z $TEST_TYPE ]; then
    echo "Parameter Test_Type required!"
    exit 1
elif [ $TEST_TYPE != "Smoke" ] && [ $TEST_TYPE != "Performance" ] && [ $TEST_TYPE != "Stability" ] && [ $TEST_TYPE != "Accuracy" ]; then
    echo "Test_Type is wrong!"
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

if [ -z $version ]; then
    python3 $curr_dir/script_generator.py ${TEST_TYPE} "latest"
else
    python3 $curr_dir/script_generator.py ${TEST_TYPE} $version
fi

# full_model_list=(DeepSeek-R1:8:H20 DeepSeek-V3-0324:8:H20 Qwen3-235B-A22B-FP8:4:H20 DeepSeek-R1-Distill-Qwen-32B:2:A800 DeepSeek-R1-Distill-Llama-70B:4:A800 Meta-Llama-3.1-70B-Instruct:4:A800 Qwen2.5-32B-Instruct:2:A800 QwQ-32B:2:A800 Qwen2.5-32B-Instruct-AWQ:1:A800 QwQ-32B-AWQ:1:A800)
# full_model_list=(DeepSeek-R1:8:H20 DeepSeek-V3-0324:8:H20 Qwen3-235B-A22B-FP8:4:H20)
# full_model_list=(DeepSeek-R1-Distill-Qwen-32B:2:A800 DeepSeek-R1-Distill-Llama-70B:4:A800 Meta-Llama-3.1-70B-Instruct:4:A800 Qwen2.5-32B-Instruct:2:A800 QwQ-32B:2:A800 Qwen2.5-32B-Instruct-AWQ:1:A800 QwQ-32B-AWQ:1:A800 DeepSeek-R1-Distill-Llama-70B:4:H20 Qwen2.5-72B-Instruct:4:H20)
# full_model_list=(DeepSeek-R1-0528:8:H20 Qwen3-235B-A22B:8:H20 DeepSeek-R1-Distill-Qwen-32B:1:H20 DeepSeek-R1-Distill-Llama-70B:4:H20 Qwen2.5-72B-Instruct-AWQ:1:H20 Qwen2.5-32B-Instruct-AWQ:1:H20 Qwen2.5-72B-Instruct:4:H20 Qwen3-235B-A22B-FP8:4:H20)
full_model_list=(DeepSeek-R1-Distill-Qwen-1.5B:1:V100 DeepSeek-R1-Distill-Qwen-7B:1:V100 DeepSeek-R1-Distill-Qwen-14B:2:V100 DeepSeek-R1-Distill-Qwen-32B:4:V100 DeepSeek-R1-Distill-Llama-8B:1:V100 DeepSeek-R1-Distill-Llama-70B:8:V100 Meta-Llama-3.1-8B-Instruct:1:V100
Meta-Llama-3.1-70B-Instruct:8:V100 Qwen2.5-0.5B-Instruct:1:V100 Qwen2.5-1.5B-Instruct:1:V100 Qwen2.5-3B-Instruct:1:V100 Qwen2.5-7B-Instruct:1:V100 Qwen2.5-14B-Instruct:2:V100 Qwen2.5-32B-Instruct:4:V100 Qwen2.5-72B-Instruct:8:V100 QwQ-32B:4:V100 
Qwen2.5-0.5B-Instruct-AWQ:1:V100 Qwen2.5-1.5B-Instruct-AWQ:1:V100 Qwen2.5-3B-Instruct-AWQ:1:V100 Qwen2.5-7B-Instruct-AWQ:1:V100 Qwen2.5-14B-Instruct-AWQ:1:V100 Qwen2.5-32B-Instruct-AWQ:2:V100 Qwen2.5-72B-Instruct-AWQ:4:V100 QwQ-32B-AWQ:2:V100)

log_name_suffix=$(date +"%Y%m%d")
parallel=3

rm -rf $curr_dir/*.log
rm -rf $curr_dir/*.txt
# rm -rf $curr_dir/processed_models_$(date +"%Y%m%d")
rm -rf $curr_dir/report/*

declare -A V100_server_list=(
    ["V100-001"]="192.168.100.101"
)

search_servers() {
    NPU_QUANTITY=$1
    NPU_MODEL=$2
    local -n servers_found=$3     # 传名引用

    if [ $NPU_QUANTITY -lt 8 ]; then
        SERVER_QUANTITY=1
    else
        SERVER_QUANTITY=$(($NPU_QUANTITY/8))
    fi

    echo "正在搜索 ${SERVER_QUANTITY} 台GPU服务器......"
    
    servers_found=()
    if [ $NPU_MODEL == "V100" ]; then
        for key in "${!V100_server_list[@]}"; do
            echo "$key => ${V100_server_list[$key]}"
            ssh $user@${V100_server_list[$key]} "# 目标空闲 GPU 数量
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                
                # 使用 nvidia-smi 获取 GPU 使用情况

                GPU_INFO=(\$(docker exec automation_test ixsmi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 去重
                echo \${GPU_INFO[@]}
                GPU_INFO=(\$(echo \"\${GPU_INFO[@]}\" | tr ' ' '\n' | sort -u))
                # 检查使用中的 GPU 数量
                USE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前使用中的 GPU 数量：\$USE_COUNT, 索引: \${GPU_INFO[@]}\"
                TOTAL_COUNT=\$(docker exec automation_test ixsmi -L | wc -l)
                FREE_COUNT=\$((\$TOTAL_COUNT-\$USE_COUNT))
                FREE_GPU_INFO=(\$(seq 0 \$((\$TOTAL_COUNT-1)) | grep -vxFf <(printf \"%s\\n\" \"\${GPU_INFO[@]}\")))
                if [ $TEST_TYPE == "Performance" ]; then
                    if [ \$TARGET_FREE_GPUS -gt 4 ]; then
                        # 如果找到足够的空闲 GPU, 则返回结果并退出
                        if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                            echo \"resource moniter 成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
                            exit 0
                        fi
                    else
                        if [ \$FREE_COUNT -lt \$TARGET_FREE_GPUS ]; then
                            exit 1
                        fi
                        # 将空闲 GPU 按与 CPU1 和 CPU2 的通信关系分组
                        CPU_1_GROUP=()
                        CPU_2_GROUP=()
                        # 遍历 FREE_GPU_INFO 数组, 分配到对应组
                        for gpu in "\${FREE_GPU_INFO[@]}"; do
                            if (( gpu < 4 )); then
                                CPU_1_GROUP+=("\$gpu")  # GPU 0-3 与 CPU1 通信
                            else
                                CPU_2_GROUP+=("\$gpu")  # GPU 4-7 与 CPU2 通信
                            fi
                        done
                        # 如果在 CPU1 组中找到足够的空闲 GPU, 则返回结果并退出
                        if [ \"\${#CPU_1_GROUP[@]}\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                            echo \"resource moniter 成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${CPU_1_GROUP[@]}\"
                            exit 0
                        fi
                        # 如果在 CPU2 组中找到足够的空闲 GPU, 则返回结果并退出
                        if [ \"\${#CPU_2_GROUP[@]}\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                            echo \"resource moniter 成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${CPU_2_GROUP[@]}\"
                            exit 0
                        fi
                    fi
                else
                    # 如果找到足够的空闲 GPU, 则返回结果并退出
                    if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                        echo \"resource moniter 成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
                        exit 0
                    fi
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${V100_server_list[$key]})
                if [ ${#servers_found[@]} -ge $SERVER_QUANTITY ]; then
                    break
                fi
            fi
        done
    fi
}

for name in "${!V100_server_list[@]}"; do
    echo "$name => ${V100_server_list[$name]}"
    scp "${curr_dir}/job_executor_for_${TEST_TYPE}Test.sh" $USER@${V100_server_list[$name]}:/home/$USER
done

> "$curr_dir/report/${log_name_suffix}_result.txt"

processed_models=${curr_dir}/"processed_models"_${log_name_suffix}
touch ${processed_models}

GPU_resource_demand=()

for item in "${full_model_list[@]}"; do
    model=`echo "$item" | awk -F : '{print $1}'`
    quanity=`echo "$item" | awk -F : '{print $2}'`
    gpu=`echo "$item" | awk -F : '{print $3}'`
    found=0
    for option in 'DynamicSplitFuseV2' 'PrefillFirst'; do
        use_prefix_cache_flag=1
        for ((i=1; i<=1; i=i+1)); do
            swap_space=40
            for ((j=1; j<=1; j=j+1)); do
                # 模型已经测试过了，检查下一个
                if [ $use_prefix_cache_flag -gt 0 ]; then
                    if [ $swap_space -eq 0 ]; then
                        if [ ! -z `cat ${processed_models} | grep -w ${item}_${option}_use-prefix-cache` ]; then
                            continue
                        fi
                    else
                        if [ ! -z `cat ${processed_models} | grep -w ${item}_${option}_use-prefix-cache_swap-space` ]; then
                            swap_space=0
                            continue
                        fi
                    fi
                else
                    if [ $swap_space -eq 0 ]; then
                        if [ ! -z `cat ${processed_models} | grep -w ${item}_${option}` ]; then
                            continue
                        fi
                    else
                        if [ ! -z `cat ${processed_models} | grep -w ${item}_${option}_swap-space` ]; then
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
        GPU_MODEL=`echo "$item" | awk -F : '{print $3}'`
        echo "当前模型: $model, GPU数量: $GPU_QUANTITY, GPU型号: $GPU_MODEL"
        search_servers $GPU_QUANTITY $GPU_MODEL servers
        if [ ${#servers[@]} -ge ${SERVER_QUANTITY} ]; then
            echo "已找到满足条件的空闲 GPU, 开始测试模型${model}......"
            echo
            if [ $TEST_TYPE == "Stability" ]; then
                $curr_dir/siginfer_nvidia_test.sh ${USER} 0 "${servers[*]}" ${item} ${job_count} ${TEST_TYPE} ${version} > $curr_dir/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "按任意键结束|测试全部完成"`
            elif [ $TEST_TYPE == "Performance" ]; then
                $curr_dir/siginfer_nvidia_test.sh ${USER} 1 "${servers[*]}" ${item} ${job_count} ${TEST_TYPE} ${TEST_PARAM} ${version} > $curr_dir/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型${TEST_TYPE}测试任务|测试全部完成"`
            else
                if [ $TEST_TYPE == "Smoke" ]; then
                    send_report=0
                else
                    send_report=1
                fi
                $curr_dir/siginfer_nvidia_test.sh ${USER} ${send_report} "${servers[*]}" ${item} ${job_count} ${TEST_TYPE} ${version} > $curr_dir/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
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
                        temp_list+=(${pid_map[$done_pid]})  # 加入队列，稍后重试
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
            # 等待一段时间后重新扫描（例如 5 秒）
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

# python3 $curr_dir/send_bot.py ${version}

exit 0
