#!/bin/bash

TEST_TYPE=$1

declare -A gpu_server_list=(
	["A800-001"]="10.208.130.44"
	["H20-001"]="10.9.1.14"
	["H100-001"]="192.168.100.106"
)

for key in "${!gpu_server_list[@]}"; do
    echo "$key => ${gpu_server_list[$key]}"
    ssh -o ConnectionAttempts=3 s_limingge@${gpu_server_list[$key]} "# ${TEST_TYPE} Test容器
        container_list=\$(docker ps -a --format \"{{.Names}}\" | grep \"siginfer_nvidia_${TEST_TYPE}Test_\")
        for container in \$container_list; do
            # echo \$container
            docker stop \$container
            docker rm \$container
        done
        echo '容器清理完成！'
    "
    err=$?
    if [ $err -ne 0 ]; then
        echo "服务器访问失败！"
    fi
    sleep 1
done
