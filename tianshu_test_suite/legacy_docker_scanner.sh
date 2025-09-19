#!/bin/bash

TEST_TYPE=$1
USER=$2

declare -A gpu_server_list=(
    ["V100-001"]="192.168.100.101"
)

for key in "${!gpu_server_list[@]}"; do
    echo "$key => ${gpu_server_list[$key]}"
    ssh -o ConnectionAttempts=3 $USER@${gpu_server_list[$key]} "# ${TEST_TYPE} Test容器
        docker ps -a | grep -i ${TEST_TYPE} | awk '{print $2}'"
    err=$?
    if [ $err -ne 0 ]; then
        echo "服务器访问失败！"
    fi
    sleep 1
done
