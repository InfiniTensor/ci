#!/bin/bash
source ~/.bashrc
export PATH=$PATH:/test/allure-2.10.0/bin
env=""
model=""
for arg in "$@";do
    # 使用双中括号的模式匹配
    if [[ "$arg" == *"--env"* ]]; then
        echo "字符串包含 --env"
        env=`echo "$arg" | awk -F = '{print $2'}`
        echo $env
    elif [[ "$arg" == *"--model"* ]]; then
        echo "字符串包含 --model"
        model=`echo "$arg" | awk -F = '{print $2'}`
        echo $model
        break
    else
        continue
    fi
done
# 判断变量是否为空（最常用）
if [ -z "$env" ]; then
    echo "执行环境未设置或格式错误"
else
    echo "已设置执行环境"
fi
git pull
rm -rf ./allure-results
rm -rf ./allure-report
python3 set_env.py "$@"
pytest --env $env chat --alluredir allure-results | tee test_info.log
pytest --env $env text --alluredir allure-results | tee -a test_info.log
allure generate allure-results/ -o allure-report --clean
python3 get_info.py "$@"
python3 SummaryExtractor.py $model test_info.log
