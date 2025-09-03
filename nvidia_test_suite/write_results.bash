#!/bin/bash
full_model_list=(DeepSeek-R1:8 DeepSeek-V3-0324:8 Qwen3-235B-A22B:8 Qwen3-235B-A22B-FP8:4 DeepSeek-R1-AWQ:8 DeepSeek-R1-Distill-Qwen-1.5B:1 DeepSeek-R1-Distill-Qwen-7B:1 DeepSeek-R1-Distill-Qwen-14B:1 DeepSeek-R1-Distill-Qwen-32B:1 DeepSeek-R1-Distill-Llama-8B:1 DeepSeek-R1-Distill-Llama-70B:4 Meta-Llama-3.1-8B-Instruct:1 Meta-Llama-3.1-70B-Instruct:4 
Qwen2.5-0.5B-Instruct:1 Qwen2.5-1.5B-Instruct:1 Qwen2.5-3B-Instruct:1 Qwen2.5-7B-Instruct:1 Qwen2.5-14B-Instruct:1 Qwen2.5-32B-Instruct:2 Qwen2.5-72B-Instruct:4 QwQ-32B:2 Qwen2.5-0.5B-Instruct-AWQ:1 Qwen2.5-1.5B-Instruct-AWQ:1 Qwen2.5-3B-Instruct-AWQ:1 Qwen2.5-7B-Instruct-AWQ:1 Qwen2.5-14B-Instruct-AWQ:1 Qwen2.5-32B-Instruct-AWQ:1 Qwen2.5-72B-Instruct-AWQ:41 QwQ-32B-AWQ:1 Qwen3-30B-A3B-Instruct:2)

# 接收参数
framework=$1
res_file="${framework}_result.txt"
result_dir=$2
touch $res_file
echo "模型+evalscope(对话)+SGLang(文本补全)" >> $res_file

echo "******创建结果汇总文件******"
curr_dir=$(pwd)
echo $curr_dir

for item in ${full_model_list[@]};do
    model=`echo "$item" | awk -F : '{print $1}'`
    eval_1="$curr_dir/$result_dir/20250812_${model}_DynamicSplitFuseV2_use-prefix-cache_swap-space_evalscope_1.log"
    eval_2="$curr_dir/$result_dir/20250812_${model}_DynamicSplitFuseV2_use-prefix-cache_swap-space_evalscope_2.log"
    sglang="$curr_dir/$result_dir/20250812_${model}_DynamicSplitFuseV2_use-prefix-cache_swap-space_SGLang_3.log"
    if [ -f "$eval_1" ];then
        eval_res_1=$(tail -n 1 $eval_1)
    else
        eval_res_1="无结果"
    fi
    if [ -f "$eval_2" ];then
        eval_res_2=$(tail -n 1 $eval_2)

    else
        eval_res_2="无结果"
    fi
    if [ -f "$sglang" ];then
        sglang_res_3=$(tail -n 5 $sglang)
    else
        sglang_res_3="无结果"
    fi
    echo "$model+$eval_res_1 $eval_res_2+${sglang_res_3//$'\n'/}" >> $curr_dir/$res_file
done

python3 $curr_dir/write_file.py --file $curr_dir/$res_file --framework $framework
