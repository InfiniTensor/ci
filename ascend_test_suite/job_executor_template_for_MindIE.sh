#!/bin/bash

# 接收参数
model=$1
GPU_QUANITY=$2
USE_PREFIX_CACHE=$3
SCHEDULE_POLICY=$4
SWAP_SPACE=$5
MASTER_IP=$6
NODE_RANK=$7
JOB_COUNT=$8
GPU_MODEL=$9
VERSION=${10}

ret=`docker ps -a | grep siginfer_ascend_<<<TEST_TYPE>>>_${JOB_COUNT}`
if [ $? -eq 0 ]; then
    docker stop siginfer_ascend_<<<TEST_TYPE>>>_${JOB_COUNT}
    # docker rm siginfer_ascend_<<<TEST_TYPE>>>_${JOB_COUNT}
fi

LOG_NAME="server_log_SmokeTest_$(date +'%Y%m%d_%H%M%S').log"

# docker create --name=siginfer_ascend_<<<TEST_TYPE>>>_${JOB_COUNT} \
#     -u root \
#     --net=host \
#     --shm-size=1g \
#     --ipc=host \
#     --privileged \
#     --device=/dev/davinci_manager \
#     --device=/dev/devmm_svm \
#     --device=/dev/hisi_hdc \
#     -v /usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64 \
#     -v /usr/local/Ascend/driver/include:/usr/local/Ascend/driver/include \
#     -v /usr/local/Ascend/driver/tools:/usr/local/Ascend/driver/tools \
#     -v /usr/local/bin/npu-smi:/usr/local/bin/npu-smi \
#     -v /dev/davinci0:/dev/davinci0 \
#     -v /dev/davinci1:/dev/davinci1 \
#     -v /dev/davinci2:/dev/davinci2 \
#     -v /dev/davinci3:/dev/davinci3 \
#     -v /dev/davinci4:/dev/davinci4 \
#     -v /dev/davinci5:/dev/davinci5 \
#     -v /dev/davinci6:/dev/davinci6 \
#     -v /dev/davinci7:/dev/davinci7 \
#     -v /usr/local/Ascend/firmware:/usr/local/Ascend/firmware \
#     -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
#     -v /home/weight:/home/weight \
#     docker.xcoresigma.com/docker/mindie:2.1.RC1 \
#     sleep infinity

# if [ $? -ne 0 ]; then
#     exit 1;
# fi

docker start siginfer_ascend_<<<TEST_TYPE>>>_${JOB_COUNT}

<<<generated source code>>>

TIMEOUT_SECONDS=$((60*30)) # 设置启动超时时间为30分钟
if [ $NODE_RANK -eq 0 ]; then
    timeout \$TIMEOUT_SECONDS tail -F $LOG_NAME | grep --line-buffered -m 1 -E \"Daemon start success!\"
    EXIT_STATUS=\$?
    if [ \$EXIT_STATUS -eq 124 ]; then
        echo \"模型启动超时（\${TIMEOUT_SECONDS}秒）\"
    elif [ \$EXIT_STATUS -eq 0 ]; then
        echo \">>> Detected master service startup completion!\"
    else
        echo \"模型启动失败，退出状态码：\$EXIT_STATUS\"
    fi

    exit \$EXIT_STATUS
else
    timeout \$TIMEOUT_SECONDS tail -F $LOG_NAME | grep --line-buffered -m 1 -E \"Daemon start success!\"
    EXIT_STATUS=\$?
    if [ \$EXIT_STATUS -eq 124 ]; then
        echo \"模型启动超时（\${TIMEOUT_SECONDS}秒）\"
    elif [ \$EXIT_STATUS -eq 0 ]; then
        echo \">>> Detected slave instance startup completion!\"
    else
        echo \"模型启动失败，退出状态码：\$EXIT_STATUS\"
    fi

    exit \$EXIT_STATUS
fi
"
