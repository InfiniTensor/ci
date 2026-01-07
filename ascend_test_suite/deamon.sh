#!/usr/bin/env bash
set -m

cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    kill -SIGTERM -$CHILD_PID
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

git fetch --all
git reset --hard origin/main
git pull origin main

cd ./ascend_test_suite
./ascend_resource_monitor.sh $@ &
CHILD_PID=$!

echo -n "Running"
while kill -0 $CHILD_PID 2>/dev/null; do
    # echo -ne "\r\033[KRunning..."
    echo -n "."
    sleep 1
done
