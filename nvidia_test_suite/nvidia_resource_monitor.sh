#!/bin/bash

# 捕获 SIGINT (Ctrl+C)、SIGTERM、SIGHUP (SSH Disconn)、SIGPIPE 和 EXIT 信号
# trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT
cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    kill -- -$$
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

TEST_TYPE=$1
ENGINE_TYPE=$2
MODEL_LIST=$3
SESSION_ID=$4
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
elif [ $ENGINE_TYPE != "SigInfer" ] && [ $ENGINE_TYPE != "vLLM" ]; then
    echo "Inference Engine Type is wrong!"
    exit 1
fi

if [ -z $MODEL_LIST ]; then
    echo "Parameter Model List required!"
    exit 1
fi

if [ $TEST_TYPE == "Performance" ]; then
    TEST_PARAM=$5
    version=$6
    if [ -z $TEST_PARAM ]; then
        echo "Parameter Test_Param required!"
        exit 1
    elif [ $TEST_PARAM != "Random" ] && [ $TEST_PARAM != "SharedGPT" ]; then
        echo "Test_Param is wrong!"
        exit 1
    fi
else
    version=$5
fi

if [ $ENGINE_TYPE == "SigInfer" ]; then
    if [ -z $version ]; then
        python3 $curr_dir/script_generator_for_SigInfer.py ${TEST_TYPE} "latest"
    else
        python3 $curr_dir/script_generator_for_SigInfer.py ${TEST_TYPE} $version
    fi
elif [ $ENGINE_TYPE == "vLLM" ]; then
    if [ -z $version ]; then
        python3 $curr_dir/script_generator_for_vLLM.py ${TEST_TYPE} "latest"
    else
        python3 $curr_dir/script_generator_for_vLLM.py ${TEST_TYPE} $version
    fi
fi

full_model_list_for_smoke=(DeepSeek-R1-0528:8:H20 Qwen3-235B-A22B:8:H20 Qwen3-235B-A22B-FP8:4:H20 Qwen3-32B:1:H20 Qwen3-32B-FP8:1:H20 DeepSeek-R1-Distill-Qwen-1.5B:1:H20 DeepSeek-R1-Distill-Qwen-32B:1:H20 DeepSeek-R1-Distill-Llama-8B:1:H100 DeepSeek-R1-Distill-Llama-70B:4:H20 Meta-Llama-3.1-8B-Instruct:1:H100 Meta-Llama-3.1-70B-Instruct:4:H20 Qwen2.5-0.5B-Instruct:1:H100 Qwen2.5-72B-Instruct:4:H20 QwQ-32B:2:H20 Qwen2.5-0.5B-Instruct-AWQ:1:H20 Qwen2.5-72B-Instruct-AWQ:1:H20 QwQ-32B-AWQ:1:H20 DeepSeek-V3.1:8:H20 DeepSeek-V3-0324:8:H20 DeepSeek-R1-Distill-Qwen-7B:1:H100 DeepSeek-R1-Distill-Qwen-14B:1:H100 Qwen2.5-1.5B-Instruct:1:H100 Qwen2.5-3B-Instruct:1:H100 Qwen2.5-7B-Instruct:1:H100 Qwen2.5-14B-Instruct:1:H100 Qwen2.5-1.5B-Instruct-AWQ:1:H20 Qwen2.5-3B-Instruct-AWQ:1:H20 Qwen2.5-7B-Instruct-AWQ:1:H20 Qwen2.5-14B-Instruct-AWQ:1:H20 Qwen2.5-32B-Instruct-AWQ:1:H20 Qwen2.5-72B-Instruct-AWQ:2:L20 Qwen3-30B-A3B-Instruct-2507:2:H20 Qwen3-32B-AWQ:1:H20 Qwen2.5-32B-Instruct-AWQ:1:H100 Qwen2.5-72B-Instruct-AWQ:1:H100 QwQ-32B-AWQ:1:H100 Qwen2.5-72B-Instruct:4:H100 Qwen2.5-32B-Instruct:2:H100)
# full_model_list_for_smoke=(Qwen2.5-72B-Instruct:4:L20 Qwen2.5-72B-Instruct-AWQ:2:L20 Qwen2.5-32B-Instruct:4:L20 QwQ-32B:4:L20 Qwen2.5-32B-Instruct:2:H100 Qwen2.5-72B-Instruct:4:H100 Qwen2.5-32B-Instruct-AWQ:1:H100 Qwen2.5-72B-Instruct-AWQ:1:H100 QwQ-32B-AWQ:1:H100 Qwen2.5-32B-Instruct:2:H20 QwQ-32B:4:L20)
# full_model_list_for_performance=(DeepSeek-V3.1:8:H20 Qwen3-235B-A22B:8:H20 Qwen3-235B-A22B-FP8:4:H20 Qwen3-32B-FP8:1:H20 Qwen3-32B:1:H20 Qwen2.5-72B-Instruct-AWQ:1:H20)
full_model_list_for_performance=(DeepSeek-R1-0528:8:H20)
full_model_list_for_stability=(DeepSeek-R1-Distill-Qwen-32B:1:H100)

log_name_suffix=$(date +"%Y%m%d")
export TASK_START_TIME=${log_name_suffix}
parallel=3

mkdir -p $curr_dir/logs/accuracy/$SESSION_ID $curr_dir/logs/stability/$SESSION_ID $curr_dir/logs/performance/$SESSION_ID $curr_dir/logs/smoke/$SESSION_ID
mkdir -p $curr_dir/report_${log_name_suffix}/$SESSION_ID

if [ $TEST_TYPE == "Smoke" ]; then
    if [ $MODEL_LIST == "default" ]; then
        full_model_list=(${full_model_list_for_smoke[@]})
    else
        model_list=($(echo "$MODEL_LIST" | tr ',' ' '))
        full_model_list=()
        for model in "${model_list[@]}"; do
            for item in "${full_model_list_for_smoke[@]}"; do
                name=`echo "$item" | awk -F : '{print $1}'`
                if [ $model == $name ]; then
                    full_model_list+=($item)
                fi
            done
        done
    fi
    rm -rf $curr_dir/logs/smoke/$SESSION_ID/*.log $curr_dir/logs/smoke/$SESSION_ID/*.log_* $curr_dir/logs/smoke/$SESSION_ID/processed_models_*
    processed_models=${curr_dir}/logs/smoke/$SESSION_ID/"processed_models"_${log_name_suffix}
    touch ${processed_models}
    num_of_prefix_cache_options=2
elif [ $TEST_TYPE == "Performance" ]; then
    if [ $MODEL_LIST == "default" ]; then
        full_model_list=(${full_model_list_for_performance[@]})
    else
        model_list=($(echo "$MODEL_LIST" | tr ',' ' '))
        full_model_list=()
        for model in "${model_list[@]}"; do
            for item in "${full_model_list_for_performance[@]}"; do
                name=`echo "$item" | awk -F : '{print $1}'`
                if [ $model == $name ]; then
                    full_model_list+=($item)
                fi
            done
        done
    fi
    rm -rf $curr_dir/logs/performance/$SESSION_ID/*.log $curr_dir/logs/performance/$SESSION_ID/processed_models_*
    processed_models=${curr_dir}/logs/performance/$SESSION_ID/"processed_models"_${log_name_suffix}
    touch ${processed_models}
    num_of_prefix_cache_options=1
elif [ $TEST_TYPE == "Stability" ]; then
    full_model_list=(${full_model_list_for_stability[@]})
    rm -rf $curr_dir/logs/stability/$SESSION_ID/*.log $curr_dir/logs/stability/$SESSION_ID/processed_models_*
    processed_models=${curr_dir}/logs/stability/$SESSION_ID/"processed_models"_${log_name_suffix}
    touch ${processed_models}
    num_of_prefix_cache_options=1
elif [ $TEST_TYPE == "Accuracy" ]; then
    full_model_list=(${full_model_list_for_accuracy[@]})
    rm -rf $curr_dir/logs/accuracy/$SESSION_ID/*.log $curr_dir/logs/accuracy/$SESSION_ID/processed_models_*
    processed_models=${curr_dir}/logs/accuracy/$SESSION_ID/"processed_models"_${log_name_suffix}
    touch ${processed_models}
    num_of_prefix_cache_options=2
fi

declare -A A800_server_list=(
    ["A800-001"]="10.208.130.44"
)

declare -A H20_server_list=(
    # ["H20-001"]="10.9.1.14"
)

declare -A H100_server_list=(
    ["H100-001"]="192.168.100.106"
)

declare -A L20_server_list=(
    ["L20-001"]="192.168.100.106"
)

declare -A H800_server_list=(
    # ["H800-001"]="10.9.1.54"
    # ["H800-002"]="10.9.1.62"
)

search_servers() {
    local MODEL=$1
    local JOB_COUNT=$2
    local NPU_QUANTITY=$3
    local NPU_MODEL=$4
    local -n servers_found=$5     # 传名引用

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
                source /home/s_limingge/npu_lock_manager_for_ci.sh
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 nvidia-smi 获取 GPU 使用情况
                GPU_INFO=(\$(nvidia-smi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 去重
                GPU_INFO=(\$(echo \"\${GPU_INFO[@]}\" | tr ' ' '\n' | sort -u))
                # 检查使用中的 GPU 数量
                USE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前使用中的 GPU 数量：\$USE_COUNT, 索引: \${GPU_INFO[@]}\"
                TOTAL_COUNT=\$(nvidia-smi -L | wc -l)
                FREE_COUNT=\$((\$TOTAL_COUNT-\$USE_COUNT))
                FREE_GPU_INFO=(\$(seq 0 \$((\$TOTAL_COUNT-1)) | grep -vxFf <(printf \"%s\\n\" \"\${GPU_INFO[@]}\")))
                if [ $TEST_TYPE == "Performance" ]; then
                    if [ \$TARGET_FREE_GPUS -gt 4 ]; then
                        # 如果找到足够的空闲 GPU, 则返回结果并退出
                        if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                            echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
                            echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                            # 生成唯一的任务ID
                            TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                            LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                            SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                            check_npu_locks_batch \${SERVER_NAME} \"\${FREE_GPU_INFO[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                            if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                                SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                                echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                                exit 0
                            else
                                echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                            fi
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
                            echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                            # 生成唯一的任务ID
                            TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                            LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                            SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                            check_npu_locks_batch \${SERVER_NAME} \"\${CPU_1_GROUP[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                            if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                                SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                                echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                                exit 0
                            else
                                echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                            fi
                        fi
                        # 如果在 CPU2 组中找到足够的空闲 GPU, 则返回结果并退出
                        if [ \"\${#CPU_2_GROUP[@]}\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                            echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${CPU_2_GROUP[@]}\"
                            echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                            # 生成唯一的任务ID
                            TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                            LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                            SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                            check_npu_locks_batch \${SERVER_NAME} \"\${CPU_2_GROUP[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                            if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                                SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                                echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                                exit 0
                            else
                                echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                            fi
                        fi
                    fi
                else
                    # 如果找到足够的空闲 GPU, 则返回结果并退出
                    if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                        echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
                        echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                        # 生成唯一的任务ID
                        TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                        LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                        SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                        check_npu_locks_batch \${SERVER_NAME} \"\${FREE_GPU_INFO[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                        if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                            SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                            echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                            exit 0
                        else
                            echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                        fi
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
                source /home/s_limingge/npu_lock_manager_for_ci.sh
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 nvidia-smi 获取 GPU 使用情况
                GPU_INFO=(\$(nvidia-smi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 去重
                GPU_INFO=(\$(echo \"\${GPU_INFO[@]}\" | tr ' ' '\n' | sort -u))
                # 检查使用中的 GPU 数量
                USE_COUNT=\$(echo \"\${GPU_INFO[@]}\" | wc -w)
                echo \"当前使用中的 GPU 数量：\$USE_COUNT, 索引: \${GPU_INFO[@]}\"
                TOTAL_COUNT=\$(nvidia-smi -L | wc -l)
                FREE_COUNT=\$((\$TOTAL_COUNT-\$USE_COUNT))
                FREE_GPU_INFO=(\$(seq 0 \$((\$TOTAL_COUNT-1)) | grep -vxFf <(printf \"%s\\n\" \"\${GPU_INFO[@]}\")))
                if [ $TEST_TYPE == "Performance" ]; then
                    if [ \$TARGET_FREE_GPUS -gt 4 ]; then
                        # 如果找到足够的空闲 GPU, 则返回结果并退出
                        if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                            echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
                            echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                            # 生成唯一的任务ID
                            TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                            LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                            SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                            check_npu_locks_batch \${SERVER_NAME} \"\${FREE_GPU_INFO[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                            if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                                SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                                echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                                exit 0
                            else
                                echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                            fi
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
                            echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                            # 生成唯一的任务ID
                            TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                            LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                            SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                            check_npu_locks_batch \${SERVER_NAME} \"\${CPU_1_GROUP[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                            if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                                SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                                echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                                exit 0
                            else
                                echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                            fi
                        fi
                        # 如果在 CPU2 组中找到足够的空闲 GPU, 则返回结果并退出
                        if [ \"\${#CPU_2_GROUP[@]}\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                            echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${CPU_2_GROUP[@]}\"
                            echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                            # 生成唯一的任务ID
                            TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                            LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                            SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                            check_npu_locks_batch \${SERVER_NAME} \"\${CPU_2_GROUP[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                            if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                                SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                                echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                                exit 0
                            else
                                echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                            fi
                        fi
                    fi
                else
                    # 如果找到足够的空闲 GPU, 则返回结果并退出
                    if [ \"\$FREE_COUNT\" -ge \"\$TARGET_FREE_GPUS\" ]; then
                        echo \"成功找到 \$TARGET_FREE_GPUS 张空闲 GPU, 索引：\${FREE_GPU_INFO[@]}\"
                        echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                        # 生成唯一的任务ID
                        TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                        LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                        SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                        check_npu_locks_batch \${SERVER_NAME} \"\${FREE_GPU_INFO[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                        if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                            SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                            echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                            exit 0
                        else
                            echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                        fi
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
        for key in "${!H100_server_list[@]}"; do
            echo "$key => ${H100_server_list[$key]}"
            ssh s_limingge@${H100_server_list[$key]} "# 目标空闲 GPU 数量
                source /home/s_limingge/npu_lock_manager_for_ci.sh
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 nvidia-smi 获取 GPU 使用情况
                GPU_INFO=(\$(nvidia-smi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 去重
                GPU_INFO=(\$(echo \"\${GPU_INFO[@]}\" | tr ' ' '\n' | sort -u))
                # 过滤掉第5块和第6块L20 GPU卡, 对应ID是0, 1
                GPU_INFO=(\$(echo \"\${GPU_INFO[@]}\" | sed -E 's/\b4\b//g' | sed -E 's/\b5\b//g' | sed -E 's/\s+/ /g' | xargs))
                for ((i=0; i<\${#GPU_INFO[@]}; i++)); do
                    GPU_INFO[\$i]=\$((GPU_INFO[\$i]+2))
                done
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
                    echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                    # 生成唯一的任务ID
                    TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                    LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                    SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                    check_npu_locks_batch \${SERVER_NAME} \"\${FREE_GPU_INFO[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                    if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                        SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                        echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                        exit 0
                    else
                        echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                    fi
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${H100_server_list[$key]})
                if [ ${#servers_found[@]} -ge $SERVER_QUANTITY ]; then
                    break
                fi
            fi
        done
    elif [ $NPU_MODEL == "L20" ]; then
        for key in "${!L20_server_list[@]}"; do
            echo "$key => ${L20_server_list[$key]}"
            ssh s_limingge@${L20_server_list[$key]} "# 目标空闲 GPU 数量
                source /home/s_limingge/npu_lock_manager_for_ci.sh
                if [ $NPU_QUANTITY -eq 16 ]; then
                    TARGET_FREE_GPUS=8
                else
                    TARGET_FREE_GPUS=$NPU_QUANTITY
                fi
                echo \"开始在${key}上扫描 GPU, 目标: 寻找 \$TARGET_FREE_GPUS 张空闲 GPU...\"
                # 使用 nvidia-smi 获取 GPU 使用情况
                GPU_INFO=(\$(nvidia-smi | awk '/Processes:/,/\+/{ if (\$1 ~ /^[|]/ && \$2 ~ /^[0-9]+\$/) print \$2 }'))
                # 去重
                GPU_INFO=(\$(echo \"\${GPU_INFO[@]}\" | tr ' ' '\n' | sort -u))
                # 过滤掉第1块到第4块H100 GPU卡, 对应ID是2, 3, 4, 5
                GPU_INFO=(\$(echo \"\${GPU_INFO[@]}\" | sed -E 's/\b0\b//g' | sed -E 's/\b1\b//g' | sed -E 's/\b2\b//g' | sed -E 's/\b3\b//g' | sed -E 's/\s+/ /g' | xargs))
                for ((i=0; i<\${#GPU_INFO[@]}; i++)); do
                    GPU_INFO[\$i]=\$((GPU_INFO[\$i]-4))
                done
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
                    echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                    # 生成唯一的任务ID
                    TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                    LOCAL_IP=\$(hostname -I | awk '{print \$1}')
                    SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                    check_npu_locks_batch \${SERVER_NAME} \"\${FREE_GPU_INFO[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                    if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                        SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                        echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                        exit 0
                    else
                        echo \"无法锁定（可能被其他任务占用），继续扫描......\"
                    fi
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${L20_server_list[$key]})
                if [ ${#servers_found[@]} -ge $SERVER_QUANTITY ]; then
                    break
                fi
            fi
        done
    fi
}

for name in "${!H20_server_list[@]}"; do
    echo "$name => ${H20_server_list[$name]}"
    scp "${curr_dir}/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh" s_limingge@${H20_server_list[$name]}:/home/s_limingge
    scp "${curr_dir}/npu_lock_manager_for_ci.sh" s_limingge@${H20_server_list[$name]}:/home/s_limingge
done

for name in "${!A800_server_list[@]}"; do
    echo "$name => ${A800_server_list[$name]}"
    scp "${curr_dir}/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh" s_limingge@${A800_server_list[$name]}:/home/s_limingge
    scp "${curr_dir}/npu_lock_manager_for_ci.sh" s_limingge@${A800_server_list[$name]}:/home/s_limingge
done

for name in "${!H100_server_list[@]}"; do
    echo "$name => ${H100_server_list[$name]}"
    scp "${curr_dir}/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh" s_limingge@${H100_server_list[$name]}:/home/s_limingge
    scp "${curr_dir}/npu_lock_manager_for_ci.sh" s_limingge@${H100_server_list[$name]}:/home/s_limingge
done

for name in "${!L20_server_list[@]}"; do
    echo "$name => ${L20_server_list[$name]}"
    scp "${curr_dir}/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh" s_limingge@${L20_server_list[$name]}:/home/s_limingge
    scp "${curr_dir}/npu_lock_manager_for_ci.sh" s_limingge@${L20_server_list[$name]}:/home/s_limingge
done

for name in "${!H800_server_list[@]}"; do
    echo "$name => ${H800_server_list[$name]}"
    scp "${curr_dir}/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh" s_limingge@${H800_server_list[$name]}:/home/s_limingge
    scp "${curr_dir}/npu_lock_manager_for_ci.sh" s_limingge@${H800_server_list[$name]}:/home/s_limingge
done

GPU_resource_demand=()

for item in "${full_model_list[@]}"; do
    model=`echo "$item" | awk -F : '{print $1}'`
    quanity=`echo "$item" | awk -F : '{print $2}'`
    gpu=`echo "$item" | awk -F : '{print $3}'`
    found=0
    # for option in 'DynamicSplitFuseV2' 'PrefillFirst'; do
    for option in 'DynamicSplitFuseV2'; do
        use_prefix_cache_flag=-1
        for ((i=1; i<=${num_of_prefix_cache_options}; i=i+1)); do
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

ret=0

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
        search_servers $model $job_count $GPU_QUANTITY $GPU_MODEL servers
        if [ ${#servers[@]} -ge ${SERVER_QUANTITY} ]; then
            echo "已找到满足条件的空闲 GPU, 开始测试模型${model}......"
            echo
            if [ $TEST_TYPE == "Stability" ]; then
                $curr_dir/siginfer_nvidia_test.sh 0 "${servers[*]}" ${item} ${job_count} ${TEST_TYPE} ${ENGINE_TYPE} ${SESSION_ID} ${version} > $curr_dir/logs/stability/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/logs/stability/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型Stability测试任务|测试全部完成"`
            elif [ $TEST_TYPE == "Performance" ]; then
                $curr_dir/siginfer_nvidia_test.sh 1 "${servers[*]}" ${item} ${job_count} ${TEST_TYPE} ${ENGINE_TYPE} ${SESSION_ID} ${TEST_PARAM} ${version} > $curr_dir/logs/performance/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/logs/performance/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型Performance测试任务|测试全部完成"`
            elif [ $TEST_TYPE == "Smoke" ]; then
                $curr_dir/siginfer_nvidia_test.sh 1 "${servers[*]}" ${item} ${job_count} ${TEST_TYPE} ${ENGINE_TYPE} ${SESSION_ID} ${version} > $curr_dir/logs/smoke/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/logs/smoke/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型Smoke测试任务|测试全部完成"`
            elif [ $TEST_TYPE == "Accuracy" ]; then
                $curr_dir/siginfer_nvidia_test.sh 0 "${servers[*]}" ${item} ${job_count} ${TEST_TYPE} ${ENGINE_TYPE} ${SESSION_ID} ${version} > $curr_dir/logs/accuracy/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/logs/accuracy/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型Accuracy测试任务|测试全部完成"`
            else
                echo "测试类型错误！"
                exit 1
            fi

            if [ $status_msg == "测试全部完成！" ]; then
                echo "模型运行环境配置失败，准备尝试测试下一个模型......"
                echo
                wait $last_pid  # 等待上一个子进程结束
                err=$?          # 保存上一个结束子进程的退出状态
                if [ $err -ne 0 ]; then
                    if [ $err -eq 10 ]; then  # 没有资源，等待超时
                        echo "没有资源，等待超时，加入队列，稍后重试......"
                        temp_list+=(${pid_map[$last_pid]})  # 加入队列，稍后重试
                    fi
                else
                    echo "程序出错！"
                fi
                ret=1
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
        if [ $TEST_TYPE == "Accuracy" ]; then
            python3 $curr_dir/write_file.py --file "$curr_dir/report_${log_name_suffix}/$SESSION_ID/${log_name_suffix}_result.txt" --framework Nvidia --engine ${ENGINE_TYPE} --sessionID ${SESSION_ID}
        elif [ $TEST_TYPE == "Smoke" ]; then
            if [ -f $curr_dir/report_${log_name_suffix}/$SESSION_ID/version.txt ]; then
                latest_tag=$(cat $curr_dir/report_${log_name_suffix}/$SESSION_ID/version.txt)
            else
                latest_tag="unknown"
            fi
            
            python3 $curr_dir/SendMsgToBot.py "$latest_tag" "$curr_dir/report_${log_name_suffix}/$SESSION_ID/summary_${log_name_suffix}.txt"

            last_date=$(date -d "$log_name_suffix -1 day" +"%Y%m%d")
            if [ -f $curr_dir/report_${last_date}/$SESSION_ID/version.txt ]; then
                last_version=$(cat $curr_dir/report_${last_date}/$SESSION_ID/version.txt)
            else
                last_version="unknown"
            fi
            
            if [ -f "$curr_dir/report_${last_date}/$SESSION_ID/summary_${last_date}.txt" ]; then
                console_output_flag=1
                if [ $console_output_flag -eq 1 ]; then
                    python3 -c "from SendMsgToBot import compare_summary_files; result = compare_summary_files(\"$latest_tag\", \"$curr_dir/report_${log_name_suffix}/$SESSION_ID/summary_${log_name_suffix}.txt\", \"$last_version\", \"$curr_dir/report_${last_date}/$SESSION_ID/summary_${last_date}.txt\"); print(result)"
                else
                    python3 -c "from SendMsgToBot import compare_summary_files, send_summary_to_server; result = compare_summary_files(\"$latest_tag\", \"$curr_dir/report_${log_name_suffix}/$SESSION_ID/summary_${log_name_suffix}.txt\", \"$last_version\", \"$curr_dir/report_${last_date}/$SESSION_ID/summary_${last_date}.txt\"); send_summary_to_server(None, None, result)"
                fi
            fi
        fi
        break
    else
        GPU_resource_demand=("${temp_list[@]}")
        echo
        echo "准备尝试进行下一轮模型测试: ${GPU_resource_demand[@]}"
        echo
    fi
done

exit $ret
