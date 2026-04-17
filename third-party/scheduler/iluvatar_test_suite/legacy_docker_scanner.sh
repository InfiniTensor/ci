#!/bin/bash

TEST_TYPE=$1
SHUTDOWN=$2

if [ -z $SHUTDOWN ]; then
    SHUTDOWN=0
fi

if [ $SHUTDOWN -ne 0 ] && [ $SHUTDOWN -ne 1 ]; then
    echo "Parameter SHUTDOWN is wrong!"
    exit 1
fi

declare -A npu_server_list=(
    ["aicc001"]="10.9.1.78"
    ["aicc003"]="10.9.1.106"
    ["aicc004"]="10.9.1.114"
    ["aicc005"]="10.9.1.98"
    ["aicc006"]="10.9.1.110"
    ["aicc007"]="10.9.1.86"
    ["aicc008"]="10.9.1.94"
    ["aicc009"]="10.9.1.82"
    ["aicc010"]="10.9.1.102"
)

for key in "${!npu_server_list[@]}"; do
    echo "$key => ${npu_server_list[$key]}"
    ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -p 14735 zkjh@${npu_server_list[$key]} "# 处理${TEST_TYPE} Test容器
        container_list=\$(docker ps -a --format \"{{.Names}}\" | grep \"infiniTensor_iluvatar_${TEST_TYPE}Test_\")
        for container in \$container_list; do
            if [ $SHUTDOWN -eq 1 ]; then
                docker stop \$container
                docker rm \$container
                echo '容器清理完成！'
            else
                echo \$container
            fi
        done
    "
    err=$?
    if [ $err -ne 0 ]; then
        echo "服务器访问失败！"
    fi
    sleep 1
done
