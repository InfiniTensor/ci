#!/usr/bin/env bash
set -m

cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    docker stop --time 60 lmg_test
    # docker kill --signal=SIGTERM lmg_test
    # docker kill -s TERM lmg_test
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

docker run --name="lmg_test" -v /home/s_limingge/.npu_locks:/home/s_limingge/.npu_locks -v /var/run/docker.sock:/var/run/docker.sock auto-test:latest &
CHILD_PID=$!

echo -n "Running"
while kill -0 $CHILD_PID 2>/dev/null; do
    # echo -ne "\r\033[KRunning..."
    echo -n "."
    sleep 1
done
