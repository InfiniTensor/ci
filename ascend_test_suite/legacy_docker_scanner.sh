#!/bin/bash

TEST_TYPE=$1

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

for key in "${!npu_server_list[@]}"; do
    echo "$key => ${npu_server_list[$key]}"
    if [ $key == 'aicc001' ]; then
        sshpass -p 's_limingge' ssh -o ConnectionAttempts=3 s_limingge@${npu_server_list['aicc001']} "# 处理${TEST_TYPE} Test容器
            docker ps -a | grep -i ${TEST_TYPE} | awk '{print $2}'"
        err=$?
        if [ $err -ne 0 ]; then
            echo "服务器访问失败！"
        fi
    else
        ssh -o ConnectionAttempts=3 s_limingge@${npu_server_list[$key]} "# 处理${TEST_TYPE} Test容器
            docker ps -a | grep -i ${TEST_TYPE} | awk '{print $2}'"
        err=$?
        if [ $err -ne 0 ]; then
            echo "服务器访问失败！"
        fi
    fi
    sleep 1
done
