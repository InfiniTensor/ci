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
version=$7

export https_proxy=http://localhost:9991 http_proxy=http://localhost:9991

mkdir -p ~/.ssh/
cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

cd /CI_Workspace

if [ ! -d ci_autotest ]; then
    git clone git@github.com:Vincent777/ci_autotest.git ci_autotest
    cd ci_autotest
else
    cd ci_autotest
    git fetch --all
    git reset --hard origin/main
    git pull origin main
fi

if [ $platform == "Ascend" ]; then
    cd ascend_test_suite
    mkdir -p $version
    cp latest/model_list.yml $version
    ./ascend_resource_monitor.sh $test_type $engine $model_list "$docker_args" $CI_job_id $version &
    CHILD_PID=$!
elif [ $platform == "Nvidia" ]; then
    cd nvidia_test_suite
    mkdir -p $version
    cp latest/model_list.yml $version
    ./nvidia_resource_monitor.sh $test_type $engine $model_list "$docker_args" $CI_job_id $version &
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
