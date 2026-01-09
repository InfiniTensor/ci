#!/usr/bin/env bash
set -m

# trap 'echo "[PID $$] received SIGTERM"; exit 0' TERM
# trap 'echo "[PID $$] received SIGINT"; exit 0' INT

# echo "PID 1 started: $$"

# while true; do
#     echo "Running..."
#     sleep 5
# done

cleanup() {
    touch "ci_test.txt"
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    kill -SIGTERM -$CHILD_PID
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

echo "PID 1 started: $$"

while true; do
    echo "Running..."
    sleep 5
done

# echo "Args from docker run: $@"

# mkdir -p ~/.ssh/
# cat > ~/.ssh/config <<EOF
# Host 10.9.1.*
#     StrictHostKeyChecking no
#     UserKnownHostsFile /dev/null
# EOF

# cd /workspace

# git clone http://git.xcoresigma.com/xcore-sigma/autotest.git ci_autotest

# cd ci_autotest/ascend_test_suite
# mkdir -p $5
# sed -i '254s/False/True/' SendMsgToBot.py
# cp latest/model_list.xlsx $5

# ./ascend_resource_monitor.sh $@ &
# CHILD_PID=$!

# echo -n "Running"
# while kill -0 $CHILD_PID 2>/dev/null; do
#     # echo -ne "\r\033[KRunning..."
#     echo -n "."
#     sleep 1
# done
