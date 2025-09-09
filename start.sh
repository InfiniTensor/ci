#!/bin/bash
source ~/.bashrc
export PATH=$PATH:/test/allure-2.10.0/bin
pro_dir="openai-test"
cd $pro_dir
env=""
for arg in "$@";do
    # 使用双中括号的模式匹配
    if [[ "$arg" == *"--env"* ]]; then
        echo "字符串包含 --env"
        env=`echo "$arg" | awk -F = '{print $2'}`
        echo $env
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
rm -rf $pro_dir/allure-results
rm -rf $pro_dir/allure-report
python3 set_env.py "$@"
pytest --env $env text/test_completions_accuracy.py --alluredir allure-results | tee test_info.log
allure generate allure-results/ -o allure-report --clean
python3 get_info.py "$@"
