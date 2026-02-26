#!/usr/bin/env bash
set -m

cleanup() {
    trap - SIGINT SIGTERM SIGHUP SIGPIPE
    kill -SIGTERM -$CHILD_PID
    sleep 60
    exit 130
}

trap cleanup SIGINT SIGTERM SIGHUP SIGPIPE

test_type=$1
engine=$2
model_list=$3
CI_job_id=$4
version=$5

mkdir -p ~/.ssh/
cat > ~/.ssh/config <<EOF
Host 10.9.1.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

cd /CI_Workspace

if [ ! -d ci_autotest ]; then
    git clone http://git.xcoresigma.com/xcore-sigma/autotest.git ci_autotest
    cd ci_autotest
else
    cd ci_autotest
    git fetch --all
    git reset --hard origin/main
    git pull origin main
fi

cd ascend_test_suite
mkdir -p $version
cp latest/model_list.xlsx $version

./ascend_resource_monitor.sh $test_type $engine $model_list $CI_job_id $version &
CHILD_PID=$!

echo -n "Running"
while kill -0 $CHILD_PID 2>/dev/null; do
    # echo -ne "\r\033[KRunning..."
    echo -n "."
    sleep 1
done

wait $CHILD_PID
EXIT_CODE=$?

exit $EXIT_CODE
