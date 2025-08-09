#!/bin/bash

version=$1

# full_model_list=(DeepSeek-R1:8:H20 DeepSeek-V3-0324:8:H20 Qwen3-235B-A22B-FP8:4:H20 DeepSeek-R1-Distill-Qwen-32B:2:A800 DeepSeek-R1-Distill-Llama-70B:4:A800 Meta-Llama-3.1-70B-Instruct:4:A800 Qwen2.5-32B-Instruct:2:A800 QwQ-32B:2:A800 Qwen2.5-32B-Instruct-AWQ:1:A800 QwQ-32B-AWQ:1:A800)
# full_model_list=(DeepSeek-R1:8:H20 DeepSeek-V3-0324:8:H20 Qwen3-235B-A22B-FP8:4:H20)
# full_model_list=(DeepSeek-R1-Distill-Qwen-32B:2:A800 DeepSeek-R1-Distill-Llama-70B:4:A800 Meta-Llama-3.1-70B-Instruct:4:A800 Qwen2.5-32B-Instruct:2:A800 QwQ-32B:2:A800 Qwen2.5-32B-Instruct-AWQ:1:A800 QwQ-32B-AWQ:1:A800 DeepSeek-R1-Distill-Llama-70B:4:H20 Qwen2.5-72B-Instruct:4:H20)
# full_model_list=(DeepSeek-R1-0528:8:H20 Qwen3-235B-A22B:8:H20 DeepSeek-R1-Distill-Qwen-32B:1:H20 DeepSeek-R1-Distill-Llama-70B:4:H20 Qwen2.5-72B-Instruct-AWQ:1:H20 Qwen2.5-32B-Instruct-AWQ:1:H20 Qwen2.5-72B-Instruct:4:H20 Qwen3-235B-A22B-FP8:4:H20)
full_model_list=(Qwen3-235B-A22B:8:H20 DeepSeek-R1-Distill-Qwen-32B:1:H20 DeepSeek-R1-Distill-Llama-70B:4:H20 Qwen2.5-72B-Instruct-AWQ:1:H20 Qwen2.5-32B-Instruct-AWQ:1:H20 Qwen2.5-72B-Instruct:4:H20 Qwen3-235B-A22B-FP8:4:H20)

curr_dir=/home/s_limingge/performance_test_nvidia
log_name_suffix=$(date +"%Y%m%d")
parallel=4

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
    if [ $NPU_MODEL == "H20" ]; then
        for key in "${!H20_server_list[@]}"; do
            echo "$key => ${H20_server_list[$key]}"
            ssh s_limingge@${H20_server_list[$key]} "# 目标空闲 GPU 数量
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 nvidia-smi 获取 GPU 使用情况
                GPU_INFO=(\$(nvidia-smi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 检查使用中的 GPU 数量
                USE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前使用中的 GPU 数量：\$USE_COUNT, 索引: \${GPU_INFO[@]}\"
                TOTAL_COUNT=\$(nvidia-smi -L | wc -l)
                FREE_COUNT=\$((\$TOTAL_COUNT-\$USE_COUNT))
                FREE_GPU_INFO=(\$(seq 0 \$((\$TOTAL_COUNT-1)) | grep -vxFf <(printf \"%s\\n\" \"\${GPU_INFO[@]}\")))
                if [ \$TARGET_FREE_GPUS -gt 4 ]; then
                    # 如果找到足够的空闲 GPU, 则返回结果并退出
                    if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                        echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
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
                        echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${CPU_1_GROUP[@]}\"
                        exit 0
                    fi
                    # 如果在 CPU2 组中找到足够的空闲 GPU, 则返回结果并退出
                    if [ \"\${#CPU_2_GROUP[@]}\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                        echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${CPU_2_GROUP[@]}\"
                        exit 0
                    fi
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${H20_server_list[$key]})
                if [ ${#servers_found[@]} -ge $SERVER_QUANTITY ]; then
                    break
                fi
            fi
        done
    elif [ $NPU_MODEL == "A800" ]; then
        for key in "${!A800_server_list[@]}"; do
            echo "$key => ${A800_server_list[$key]}"        
            ssh s_limingge@${A800_server_list[$key]} "# 目标空闲 GPU 数量
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 nvidia-smi 获取 GPU 使用情况
                GPU_INFO=(\$(nvidia-smi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 检查使用中的 GPU 数量
                USE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前使用中的 GPU 数量：\$USE_COUNT, 索引: \${GPU_INFO[@]}\"
                TOTAL_COUNT=\$(nvidia-smi -L | wc -l)
                FREE_COUNT=\$((\$TOTAL_COUNT-\$USE_COUNT))
                FREE_GPU_INFO=(\$(seq 0 \$((\$TOTAL_COUNT-1)) | grep -vxFf <(printf \"%s\\n\" \"\${GPU_INFO[@]}\")))
                if [ \$TARGET_FREE_GPUS -gt 4 ]; then
                    # 如果找到足够的空闲 GPU, 则返回结果并退出
                    if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                        echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
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
                        echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${CPU_1_GROUP[@]}\"
                        exit 0
                    fi
                    # 如果在 CPU2 组中找到足够的空闲 GPU, 则返回结果并退出
                    if [ \"\${#CPU_2_GROUP[@]}\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                        echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${CPU_2_GROUP[@]}\"
                        exit 0
                    fi
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${A800_server_list[$key]})
                if [ ${#servers_found[@]} -ge $SERVER_QUANTITY ]; then
                    break
                fi
            fi
        done
    elif [ $NPU_MODEL == "H100" ]; then
        for key in "${!A800_server_list[@]}"; do
            echo "$key => ${A800_server_list[$key]}"        
            ssh s_limingge@${A800_server_list[$key]} "# 目标空闲 GPU 数量
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 nvidia-smi 获取 GPU 使用情况
                GPU_INFO=(\$(nvidia-smi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 过滤掉第5块和第6块L20 GPU卡, 对应ID是0, 1
                GPU_INFO=\$(echo \"\$GPU_INFO\" | sed -E 's/\b4\b//g' | sed -E 's/\b5\b//g' | sed -E 's/\s+/ /g' | xargs)
                # 检查使用中的 GPU 数量
                USE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前使用中的 GPU 数量：\$USE_COUNT, 索引: \${GPU_INFO[@]}\"
                TOTAL_COUNT=\$(nvidia-smi -L | wc -l)
                ((TOTAL_COUNT-=2))
                FREE_COUNT=\$((\$TOTAL_COUNT-\$USE_COUNT))
                FREE_GPU_INFO=(\$(seq 2 \$((\$TOTAL_COUNT+1)) | grep -vxFf <(printf \"%s\\n\" \"\${GPU_INFO[@]}\")))
                # 如果找到足够的空闲 GPU, 则返回结果并退出
                if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                    echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
                    exit 0
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${A800_server_list[$key]})
                if [ ${#servers_found[@]} -ge $SERVER_QUANTITY ]; then
                    break
                fi
            fi
        done
    elif [ $NPU_MODEL == "L20" ]; then
        for key in "${!A800_server_list[@]}"; do
            echo "$key => ${A800_server_list[$key]}"        
            ssh s_limingge@${A800_server_list[$key]} "# 目标空闲 GPU 数量
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 nvidia-smi 获取 GPU 使用情况
                GPU_INFO=(\$(nvidia-smi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 过滤掉第1块到第4块H100 GPU卡, 对应ID是2, 3, 4, 5
                GPU_INFO=\$(echo \"\$GPU_INFO\" | sed -E 's/\b2\b//g' | sed -E 's/\b3\b//g' | sed -E 's/\b4\b//g' | sed -E 's/\b5\b//g' | sed -E 's/\s+/ /g' | xargs)
                # 检查使用中的 GPU 数量
                USE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前使用中的 GPU 数量：\$USE_COUNT, 索引: \${GPU_INFO[@]}\"
                TOTAL_COUNT=\$(nvidia-smi -L | wc -l)
                ((TOTAL_COUNT-=4))
                FREE_COUNT=\$((\$TOTAL_COUNT-\$USE_COUNT))
                FREE_GPU_INFO=(\$(seq 0 \$((\$TOTAL_COUNT-1)) | grep -vxFf <(printf \"%s\\n\" \"\${GPU_INFO[@]}\")))
                # 如果找到足够的空闲 GPU, 则返回结果并退出
                if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                    echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
                    exit 0
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${A800_server_list[$key]})
                if [ ${#servers_found[@]} -ge $SERVER_QUANTITY ]; then
                    break
                fi
            fi
        done
    fi
}

for name in "${!H20_server_list[@]}"; do
    echo "$name => ${H20_server_list[$name]}"
    scp "${curr_dir}/job_executor_for_PerformanceTest.sh" s_limingge@${H20_server_list[$name]}:/home/s_limingge
done

for name in "${!A800_server_list[@]}"; do
    echo "$name => ${A800_server_list[$name]}"
    scp "${curr_dir}/job_executor_for_PerformanceTest.sh" s_limingge@${A800_server_list[$name]}:/home/s_limingge
done

for name in "${!H100_server_list[@]}"; do
    echo "$name => ${H100_server_list[$name]}"
    scp "${curr_dir}/job_executor_for_PerformanceTest.sh" s_limingge@${H100_server_list[$name]}:/home/s_limingge
done

for name in "${!L20_server_list[@]}"; do
    echo "$name => ${L20_server_list[$name]}"
    scp "${curr_dir}/job_executor_for_PerformanceTest.sh" s_limingge@${L20_server_list[$name]}:/home/s_limingge
done

processed_models=${curr_dir}/"processed_models"_$(date +"%Y%m%d")
touch ${processed_models}

GPU_resource_demand=()

for item in "${full_model_list[@]}"; do
    model=`echo "$item" | awk -F : '{print $1}'`
    found=0
    # for option in 'DynamicSplitFuseV2' 'PrefillFirst'; do
    for option in 'DynamicSplitFuseV2'; do
        use_prefix_cache_flag=1
        for ((i=1; i<=2; i=i+1)); do
            swap_space=0
            for ((j=1; j<=1; j=j+1)); do
                # 模型已经测试过了，检查下一个
                if [ $use_prefix_cache_flag -gt 0 ]; then
                    if [ $swap_space -eq 0 ]; then
                        if [ ! -z `cat ${processed_models} | grep -w ${model}_${option}_use-prefix-cache` ]; then
                            swap_space=40
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
                            swap_space=40
                            continue
                        fi
                    else
                        if [ ! -z `cat ${processed_models} | grep -w ${model}_${option}_swap-space` ]; then
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
    for item in "${GPU_resource_demand[@]}"; do
        model=`echo "$item" | awk -F : '{print $1}'`
        GPU_QUANTITY=`echo "$item" | awk -F : '{print $2}'`
        GPU_MODEL=`echo "$item" | awk -F : '{print $3}'`
        echo "当前模型: $model, GPU数量: $GPU_QUANTITY, GPU型号: $GPU_MODEL"
        search_servers $GPU_QUANTITY $GPU_MODEL servers
        if [ ${#servers[@]} -ge ${SERVER_QUANTITY} ]; then
            echo "已找到满足条件的空闲 GPU, 开始测试模型${model}......"
            echo
            $curr_dir/siginfer_nvidia_PerformanceTest.sh 1 "${servers[*]}" ${item} ${job_count} ${version} > $curr_dir/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
            tail -F /home/s_limingge/performance_test_nvidia/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型性能测试任务"
            ((job_count++))
            if [ $job_count -ge $parallel ]; then
                wait
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
        wait
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
