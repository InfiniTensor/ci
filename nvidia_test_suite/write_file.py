import argparse
import os
from generate_model_comparison_table import generate_model_comparison_excel, fill_model_comparison_data

parser = argparse.ArgumentParser(description="写入结果文件")
parser.add_argument('--file', type=str)
parser.add_argument('--framework', type=str)
parser.add_argument('--engine', type=str)

args=parser.parse_args()
# 读取 txt 文件，按 '+' 分割列
input_file = args.file
output_file = args.framework
engine = args.engine

curr_dir = os.getcwd()
output_file = f"{curr_dir}/report_{os.environ['TASK_START_TIME']}/{output_file}_result.xlsx"
data_dict = {}

with open(input_file, "r", encoding="utf-8") as file:
    for row_idx, line in enumerate(file, start=1):  # 从第1行开始
        columns = line.strip().split('+')  # 去除换行符并按 '+' 分割
        print(columns)
        if len(columns[1].split('} {')) == 2:
            columns[1] = columns[1].replace("} {", "} \n{")
        # 在"gsm8k"前添加换行符
        if 'gsm8k' in columns[2]:
            columns[2] = columns[2].replace("gsm8k", "\ngsm8k")
        if engine == "SigInfer":
            data_dict[columns[0]] = {
                "SigInfer_opencompass": columns[1],
                "SigInfer_SGLang": columns[2]
            }
        elif engine == "vLLM":
            data_dict[columns[0]] = {
                "VLLM_opencompass": columns[1],
                "VLLM_SGLang": columns[2]
            }
        else:
            raise ValueError(f"不支持的引擎类型: {engine}，支持的值为: SigInfer, VLLM")

generate_model_comparison_excel(output_file, engine)
fill_model_comparison_data(output_file, data_dict, engine)
