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

declare -A gpu_server_list=(
	["A800-001"]="10.208.130.44"
	["H20-001"]="10.9.1.14"
	["H100-001"]="192.168.100.106"
    # ["H800-001"]="10.9.1.54"
    ["H800-002"]="10.9.1.62"
)

for key in "${!gpu_server_list[@]}"; do
    echo "$key => ${gpu_server_list[$key]}"
    ssh -q -o ConnectionAttempts=3 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 zkjh@${gpu_server_list[$key]} "# 处理${TEST_TYPE} Test容器
        container_list=\$(docker ps -a --format \"{{.Names}}\" | grep \"siginfer_nvidia_${TEST_TYPE}Test_\")
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
