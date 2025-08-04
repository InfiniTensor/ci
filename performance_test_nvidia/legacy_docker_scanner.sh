#!/bin/bash

declare -A npu_server_list=(
	["A800-001"]="10.208.130.44"
	["H20-001"]="10.9.1.14"
	["H100-001"]="192.168.100.106"
)

for key in "${!npu_server_list[@]}"; do
    echo "$key => ${npu_server_list[$key]}"
    if [ $key == 'aicc001' ]; then
        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@${npu_server_list['aicc001']} "# 处理Performance Test容器
            docker ps -a | grep PerformanceTest | awk '{print $2}'"
        err=$?
        if [ $err -ne 0 ]; then
            echo "服务器访问失败！"
        fi
    else
        ssh -o ConnectionAttempts=3 s_limingge@${npu_server_list[$key]} "# 处理Performance Test容器
            docker ps -a | grep PerformanceTest | awk '{print $2}'"
        err=$?
        if [ $err -ne 0 ]; then
            echo "服务器访问失败！"
        fi
    fi
    sleep 1
done
