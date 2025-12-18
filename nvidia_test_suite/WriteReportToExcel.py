import sys
import re
import os
from openpyxl import load_workbook
from generate_excel_template import generate_excel, fill_benchmark_results


def main():
    if len(sys.argv) != 8:
        print("Usage: python3 WriteReportToExcel.py <test_type> <model_name> <gpu_model> <server_name> <exec_cmd> <test_cmd> <log_file_path>")
        sys.exit(1)

    test_type = sys.argv[1]
    model_name = sys.argv[2]
    gpu_model = sys.argv[3]
    server_name = sys.argv[4]
    exec_cmd = sys.argv[5]
    test_cmd = sys.argv[6]
    log_file_path = sys.argv[7]

    # context_lengths = ["128+128", "128+1024", "128+2048", "1024+1024", "2048+2048", "4096+1024", "1024+4096", "30000+2048", "126000+2048"]
    # batch_sizes = [1, 5, 10, 20, 50, 100, 150]
    context_lengths = []
    batch_sizes = []
    multiplier = 0

    # 读取日志文件内容
    try:
        with open(log_file_path, 'r', encoding='utf-8') as file:
            text = file.read()
    except FileNotFoundError:
        print(
            f"Error: Log file '{log_file_path}' not found. Please provide the correct file path.")
        exit(1)
    except Exception as e:
        print(f"Error reading log file: {e}")
        exit(1)

    # 定义正则表达式模式
    '''
    patterns = [
        # 匹配 Serving Benchmark Result 中的指标
        r"(?P<key>[A-Za-z\s\(\)/.-]+):\s+(?P<value>[0-9.]+)",
        # 匹配 Random Testing input=128, output=128
        r"(?P<key>input|output)=(?P<value>\d+)",
        # 匹配 Testing concurrency=1, prompts=4
        r"(?P<key>concurrency|prompts)=(?P<value>\d+)"
    ]
    '''

    # 定义正则表达式模式
    patterns = [
        # 匹配 Random Testing input 和 output
        r"Random Testing input=(\d+), output=(\d+)",
        # 匹配 Testing concurrency 和 prompts
        r"Testing concurrency=(\d+), prompts=(\d+)",
        # 匹配 Serving Benchmark Result 中的指标
        r"(?P<key>[A-Za-z\s\(\)/.-]+):\s+(?P<value>[0-9.]+)"
    ]

    # 存储提取的结果
    results = {}
    current_config = {}

    if test_type == "SharedGPT":
        in_out_length_key = "SharedGPT"
        context_lengths.append("SharedGPT")

    # 对文本进行匹配
    matches = re.finditer(
        r"(Random Testing [^\n]+|Testing concurrency=[^\n]+|[\=]+ Serving Benchmark Result [\=]+.*?[\=]+)", text, re.DOTALL)
    for match in matches:
        section = match.group(0)

        if test_type == "Random":
            # 匹配 input 和 output
            input_output_match = re.search(
                r"Random Testing input=(\d+), output=(\d+)", section)
            if input_output_match:
                current_config["input"] = int(input_output_match.group(1))
                current_config["output"] = int(input_output_match.group(2))
                in_out_length_key = f"{current_config['input']}+{current_config['output']}"
                context_lengths.append(in_out_length_key)
                # print(section)

        # 匹配 concurrency 和 prompts
        concurrency_prompt_match = re.search(
            r"Testing concurrency=(\d+), prompts=(\d+)", section)
        if concurrency_prompt_match:
            current_config["concurrency"] = int(
                concurrency_prompt_match.group(1))
            current_config["prompts"] = int(concurrency_prompt_match.group(2))
            concurrency_key = current_config['concurrency']  # 直接使用整数
            batch_sizes.append(concurrency_key)
            multiplier = current_config["prompts"] / concurrency_key
            results[(in_out_length_key, concurrency_key)] = {}
            # print(section)

        # 匹配基准测试结果
        benchmark_match = re.search(
            r"[\=]+ Serving Benchmark Result [\=]+.*?[\=]+", section, re.DOTALL)
        if benchmark_match:
            metrics = re.finditer(
                r"(?P<key>[A-Za-z0-9\s\(\)/]+):\s+(?P<value>[0-9.]+)", benchmark_match.group(0))
            for metric in metrics:
                key = metric.group("key").strip()
                value = float(metric.group("value"))
                # print(f"{key}=>{value}")
                results[(in_out_length_key, concurrency_key)][key] = value

    # 打印结果
    for key_tuple, value_map in results.items():
        print(f"{key_tuple}:")
        for key, value in value_map.items():
            print(f"  {key}: {value}")

    # 生成模板
    unique_batch_sizes = sorted(set(batch_sizes))  # 去重并排序
    generate_excel(model_name, exec_cmd, test_cmd, context_lengths, tuple(unique_batch_sizes), 
                   multiplier, f"./report_{os.environ['TASK_START_TIME']}/" + model_name + '.xlsx')
    # 填充数据
    fill_benchmark_results(
            f"./report_{os.environ['TASK_START_TIME']}/" + model_name + '.xlsx', results, context_lengths, unique_batch_sizes)

if __name__ == "__main__":
    main()
