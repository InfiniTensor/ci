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
curr_dir=$(pwd)

if [ -z $TEST_TYPE ]; then
    echo "Parameter Test_Type required!"
    exit 1
elif [ $TEST_TYPE != "Smoke" ] && [ $TEST_TYPE != "Performance" ] && [ $TEST_TYPE != "Stability" ] && [ $TEST_TYPE != "Accuracy" ] && [ $TEST_TYPE != "Unit" ]; then
    echo "Test_Type is wrong!"
    exit 1
fi

if [ -z $ENGINE_TYPE ]; then
    echo "Parameter PLATFORM required!"
    exit 1
elif [ $ENGINE_TYPE != "InfiniTensor" ] && [ $ENGINE_TYPE != "vLLM" ] && [ $ENGINE_TYPE != "MindIE" ]; then
    echo "Inference Engine Type is wrong!"
    exit 1
fi

if [ $TEST_TYPE != "Unit" ]; then
    MODEL_LIST=$3
    DOCKER_ARGS="$4"
    SESSION_ID=$5
    if [ -z $MODEL_LIST ]; then
        echo "Parameter Model List required!"
        exit 1
    fi
    arg_idx=6
else
    DOCKER_ARGS="$3"
    SESSION_ID=$4
    arg_idx=5
fi

if [ $TEST_TYPE == "Performance" ]; then
    TEST_PARAM=${!arg_idx}
    ((arg_idx++))
    version=${!arg_idx}
    ((arg_idx++))
    if [ -z $TEST_PARAM ]; then
        echo "Parameter Test_Param required!"
        exit 1
    elif [ $TEST_PARAM != "Random" ] && [ $TEST_PARAM != "SharedGPT" ]; then
        echo "Test_Param is wrong!"
        exit 1
    fi
else
    version=${!arg_idx}
    ((arg_idx++))
fi

echo "$TEST_TYPE $ENGINE_TYPE $MODEL_LIST $DOCKER_ARGS $SESSION_ID $version"

if [ $ENGINE_TYPE == "InfiniTensor" ]; then
    declare -A npu_server_list=(
        ["aicc001"]="10.9.1.78"
        ["aicc002"]="10.9.1.106"
        ["aicc003"]="10.9.1.114"
        ["aicc004"]="10.9.1.110"
        ["aicc005"]="10.9.1.86"
    )
    if [ -z $version ]; then
        model_config_list=(`python3 $curr_dir/script_generator_for_InfiniTensor.py ${TEST_TYPE} "${DOCKER_ARGS}" "latest"`)
    else
        model_config_list=(`python3 $curr_dir/script_generator_for_InfiniTensor.py ${TEST_TYPE} "${DOCKER_ARGS}" $version`)
    fi
elif [ $ENGINE_TYPE == "vLLM" ]; then
    declare -A npu_server_list=(
        ["aicc001"]="10.9.1.78"
        ["aicc002"]="10.9.1.106"
        ["aicc003"]="10.9.1.114"
        ["aicc004"]="10.9.1.110"
        ["aicc005"]="10.9.1.86"
    )
    if [ -z $version ]; then
        model_config_list=(`python3 $curr_dir/script_generator_for_vLLM.py ${TEST_TYPE} "${DOCKER_ARGS}" "latest"`)
    else
        model_config_list=(`python3 $curr_dir/script_generator_for_vLLM.py ${TEST_TYPE} "${DOCKER_ARGS}" $version`)
    fi
elif [ $ENGINE_TYPE == "MindIE" ]; then
    declare -A npu_server_list=(
        ["aicc001"]="192.168.162.8"
    )
    if [ -z $version ]; then
        model_config_list=(`python3 $curr_dir/script_generator_for_MindIE.py ${TEST_TYPE} "${DOCKER_ARGS}" "latest"`)
    else
        model_config_list=(`python3 $curr_dir/script_generator_for_MindIE.py ${TEST_TYPE} "${DOCKER_ARGS}" $version`)
    fi
fi

exit 0

log_name_suffix=$(date +"%Y%m%d")
export TASK_START_TIME=${log_name_suffix}
parallel=3

mkdir -p $curr_dir/logs/accuracy/$SESSION_ID $curr_dir/logs/stability/$SESSION_ID $curr_dir/logs/performance/$SESSION_ID $curr_dir/logs/smoke/$SESSION_ID
mkdir -p $curr_dir/report_${log_name_suffix}/$SESSION_ID

if [ $TEST_TYPE == "Smoke" ]; then
    rm -rf $curr_dir/logs/smoke/$SESSION_ID/*.log $curr_dir/logs/smoke/$SESSION_ID/*.log_* $curr_dir/logs/smoke/$SESSION_ID/processed_models_*
    processed_models=${curr_dir}/logs/smoke/$SESSION_ID/"processed_models"_${log_name_suffix}
    touch ${processed_models}
elif [ $TEST_TYPE == "Performance" ]; then
    rm -rf $curr_dir/logs/performance/$SESSION_ID/*.log $curr_dir/logs/performance/$SESSION_ID/processed_models_*
    processed_models=${curr_dir}/logs/performance/$SESSION_ID/"processed_models"_${log_name_suffix}
    touch ${processed_models}
elif [ $TEST_TYPE == "Stability" ]; then
    rm -rf $curr_dir/logs/stability/$SESSION_ID/*.log $curr_dir/logs/stability/$SESSION_ID/processed_models_*
    processed_models=${curr_dir}/logs/stability/$SESSION_ID/"processed_models"_${log_name_suffix}
    touch ${processed_models}
elif [ $TEST_TYPE == "Accuracy" ]; then
    rm -rf $curr_dir/logs/accuracy/$SESSION_ID/*.log $curr_dir/logs/accuracy/$SESSION_ID/processed_models_*
    processed_models=${curr_dir}/logs/accuracy/$SESSION_ID/"processed_models"_${log_name_suffix}
    touch ${processed_models}
fi

full_model_list=()
model_list=($(echo "$MODEL_LIST" | tr ',' ' '))
for model in "${model_list[@]}"; do
    for item in "${model_config_list[@]}"; do
        name=`echo "$item" | awk -F : '{print $1}'`
        if [ $model == $name ]; then
            full_model_list+=($item)
        fi
    done
done

search_servers() {
    local MODEL=$1
    local JOB_COUNT=$2
    local NPU_QUANTITY=$3
    local -n servers_found=$4     # 传名引用

    if [ $NPU_QUANTITY -lt 8 ]; then
        SERVER_QUANTITY=1
    else
        SERVER_QUANTITY=$(($NPU_QUANTITY/8))
    fi

    echo "正在搜索 ${SERVER_QUANTITY} 台GPU服务器......"
    
    servers_found=()
    for key in "${!npu_server_list[@]}"; do
        echo "$key => ${npu_server_list[$key]}"
        if [ $key == 'aicc002' ]; then
            sshpass -p 'zkjh' ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 zkjh@${npu_server_list['aicc002']} "# 目标空闲 GPU 数量
                source /home/zkjh/npu_lock_manager_for_ci.sh
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
                    echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                    # 生成唯一的任务ID
                    TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                    LOCAL_IP=\$(hostname -I | xargs printf \"%s\\n\" | head -n 1)
                    SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                    check_npu_locks_batch \${SERVER_NAME} \"\${GPU_INFO[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                    if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                        SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                        echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                        exit 0
                    else
                        echo \"锁定失败（可能被其他任务占用），继续扫描......\"
                    fi
                fi
                exit 1"
            err=$?
            if [ $err -eq 0 ]; then
                servers_found+=(${npu_server_list[$key]})
            fi
        else
            ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -p 14735 zkjh@${npu_server_list[$key]} "# 目标空闲 GPU 数量
                source /home/zkjh/npu_lock_manager_for_ci.sh
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
                    echo \"检查是否可以锁定其中 \$TARGET_FREE_GPUS 张 GPU\"
                    # 生成唯一的任务ID
                    TASK_ID=\"${TEST_TYPE}Test_${MODEL}_${JOB_COUNT}\"
                    LOCAL_IP=\$(hostname -I | xargs printf \"%s\\n\" | head -n 1)
                    SERVER_NAME=\$(echo \$LOCAL_IP | sed 's/\./_/g')
                    check_npu_locks_batch \${SERVER_NAME} \"\${GPU_INFO[*]}\" \${TASK_ID} ${SESSION_ID} NPU_LIST_FOUND
                    if [ \${#NPU_LIST_FOUND[@]} -ge \$TARGET_FREE_GPUS ]; then
                        SELECTED_NPUS=\"\${NPU_LIST_FOUND[@]:0:\$TARGET_FREE_GPUS}\"
                        echo \"可以锁定其中 \$TARGET_FREE_GPUS 张 GPU, 索引：\${SELECTED_NPUS}\"
                        exit 0
                    else
                        echo \"锁定失败（可能被其他任务占用），继续扫描......\"
                    fi
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
    scp -P 14735 "${curr_dir}/${ENGINE_TYPE}_job_executor_for_${TEST_TYPE}Test.sh" zkjh@${npu_server_list[$name]}:/home/zkjh
    scp -P 14735 "${curr_dir}/npu_lock_manager_for_ci.sh" zkjh@${npu_server_list[$name]}:/home/zkjh
done

GPU_resource_demand=()

for item in "${full_model_list[@]}"; do
    model=`echo "$item" | awk -F : '{print $1}'`
    if [ -z `cat ${processed_models} | grep -w ${model}` ]; then
        GPU_resource_demand+=(${item})
    fi
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
        echo "当前模型: $model, GPU数量: $GPU_QUANTITY"
        search_servers $model $job_count $GPU_QUANTITY servers
        if [ ${#servers[@]} -ge ${SERVER_QUANTITY} ]; then
            echo "已找到满足条件的空闲 GPU, 开始测试模型${model}......"
            echo
            if [ $TEST_TYPE == "Stability" ]; then
                $curr_dir/InfiniTensor_ascend_test.sh 0 "${servers[*]}" ${model} ${job_count} ${TEST_TYPE} ${ENGINE_TYPE} ${SESSION_ID} ${version} > $curr_dir/logs/stability/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/logs/stability/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型Stability测试任务|测试全部完成"`
            elif [ $TEST_TYPE == "Performance" ]; then
                $curr_dir/InfiniTensor_ascend_test.sh 1 "${servers[*]}" ${model} ${job_count} ${TEST_TYPE} ${ENGINE_TYPE} ${SESSION_ID} ${TEST_PARAM} ${version} > $curr_dir/logs/performance/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/logs/performance/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型Performance测试任务|测试全部完成"`
            elif [ $TEST_TYPE == "Smoke" ]; then
                $curr_dir/InfiniTensor_ascend_test.sh 1 "${servers[*]}" ${item} ${job_count} ${TEST_TYPE} ${ENGINE_TYPE} ${SESSION_ID} ${version} > $curr_dir/logs/smoke/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
                last_pid=$!
                pid_map[$last_pid]=$item
                status_msg=`tail -F $curr_dir/logs/smoke/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log | grep --line-buffered -m 1 -E "开始执行模型Smoke测试任务|测试全部完成"`
            elif [ $TEST_TYPE == "Accuracy" ]; then
                $curr_dir/InfiniTensor_ascend_test.sh 0 "${servers[*]}" ${model} ${job_count} ${TEST_TYPE} ${ENGINE_TYPE} ${SESSION_ID} ${version} > $curr_dir/logs/accuracy/$SESSION_ID/cron_job_${log_name_suffix}_${job_count}.log 2>&1 &
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
            python3 $curr_dir/write_file.py --file "$curr_dir/report_${log_name_suffix}/$SESSION_ID/${log_name_suffix}_result.txt" --framework Ascend_910B1 --engine ${ENGINE_TYPE} --sessionID ${SESSION_ID}
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
                console_output_flag=0
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
