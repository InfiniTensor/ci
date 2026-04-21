#!/usr/bin/env bash
set -m

cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    kill -SIGTERM -$CHILD_PID
    sleep 60
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

platform=$1
test_type=$2
engine=$3
model_list=$4
docker_args="$5"
CI_job_id=$6

if [ "$test_type" == "Performance" ]; then
    test_param=$7
    version=$8
else
    version=$7
fi

export https_proxy=http://localhost:9990 http_proxy=http://localhost:9990

mkdir -p ~/.ssh/
cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

cd /CI_Workspace

if [ ! -d ci_autotest ]; then
    git clone git@github.com:InfiniTensor/ci.git ci_autotest
    cd ci_autotest/third-party/scheduler
else
    cd ci_autotest/third-party/scheduler
    git fetch --all
    git reset --hard origin/master
    git pull origin master
fi

if [ $platform == "Ascend" ]; then
    cd ascend_test_suite
    mkdir -p $version
    cp latest/model_list.yml $version
    ./ascend_resource_monitor.sh $test_type $engine $model_list "$docker_args" $CI_job_id $test_param $version &
    CHILD_PID=$!
elif [ $platform == "Nvidia" ]; then
    cd nvidia_test_suite
    mkdir -p $version
    cp latest/model_list.yml $version
    ./nvidia_resource_monitor.sh $test_type $engine $model_list "$docker_args" $CI_job_id $test_param $version &
    CHILD_PID=$!
fi

echo -n "Running"
while kill -0 $CHILD_PID 2>/dev/null; do
    # echo -ne "\r\033[KRunning..."
    echo -n "."
    sleep 1
done

wait $CHILD_PID
EXIT_CODE=$?

exit $EXIT_CODE
