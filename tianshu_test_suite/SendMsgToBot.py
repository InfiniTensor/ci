import requests
import sys
import re
from datetime import datetime

current_time = datetime.now().strftime("%Y%m%d")

def extract_test_summary(log_file_path):
    try:
        with open(log_file_path, 'r', encoding='utf-8') as file:
            lines = file.readlines()
        
        # 标记是否找到目标部分
        found_summary = False
        index = 0
        summary_lines = [[], []]
        total_failed = 0
        
        for line in lines:
            # 检查是否是目标部分的开始
            if " short test summary info " in line:
                found_summary = True
                summary_lines[index].append(line.strip())
            # 如果已经找到目标部分，继续收集后续行凭证
            elif found_summary:
                # 如果遇到结束标记，停止收集
                if line.strip().startswith("=") and ("failed" in line or "passed" in line or "warning" in line):
                    # 如果failed指标存在并且其数量大于0
                    match = re.search(r'(\d+)\s+failed', line.strip())
                    if match:
                        failed_count = int(match.group(1))
                        if failed_count > 0:
                            total_failed += failed_count
                    summary_lines[index].append(line.strip())
                    index += 1
                    if index >= 2:
                        break
                    found_summary = False
                else:
                    summary_lines[index].append(line.strip())
        
        if index == 0:
            return "No test summary info found in the log file. Please check status of test tasks if it's been successfully executed.", total_failed
        elif index == 1:
            return "\n".join(str(item) for item in summary_lines[0]), total_failed
        else:
            return "\n".join(str(item) for item in summary_lines[0]) + "\n\n" + "\n".join(str(item) for item in summary_lines[1]), total_failed
        
    except FileNotFoundError:
        print(f"Error: Log file '{log_file_path}' not found.")
    except Exception as e:
        print(f"Error reading file: {str(e)}")

def send_summary_to_server(version_text, model_name, summary_text):
    if not summary_text:
        print("No summary to send.")
        return

    print(summary_text)
    
    server_url = 'https://open.feishu.cn/open-apis/bot/v2/hook/9c267c92-100a-40c6-ab32-cc1ca57df84e'  # 替换为实际的服务端 URL

    try:
        # 构造 POST 请求的数据
        headers = {"Content-Type": "application/json"}
        payload = {"msg_type":"text", "content": {"text": version_text + "\n" + model_name + "\n" + summary_text}}
        
        # 发送 POST 请求
        response = requests.post(server_url, json=payload, headers=headers)
        
        # 检查响应状态
        if response.status_code == 200:
            print("Successfully sent summary to server.")
            print("Server response:", response.text)
        else:
            print(f"Failed to send summary. Status code: {response.status_code}")
            print("Server response:", response.text)
            
    except requests.exceptions.RequestException as e:
        print(f"Error sending POST request: {str(e)}")

def save_summary_to_log(version_text, model_name, summary_text, failed_count):
    if not summary_text:
        print("No summary to send.")
        return

    print(summary_text)
    
    filename = f"report_{current_time}.txt"
    
    with open(f"./{filename}", 'a') as file:
        file.write('Docker image version: ' + version_text + '\n')
        file.write('Model name: ' + model_name + '\n')
        file.write(summary_text + '\n\n')
        
    statistics_filename = f"statistics_{current_time}.txt"
    
    with open(f"./{statistics_filename}", 'a') as file:
        file.write(model_name + ':' + str(failed_count) + '\n')

def main():
    if len(sys.argv) != 4:
        print("Usage: python SendMsgToBot <docker_image_version> <log_file_path>")
        sys.exit(1)
    
    docker_image_version = sys.argv[1]
    model_name = sys.argv[2]
    log_file_path = sys.argv[3]
    
    # 提取 summary 连同版本信息一并发送或保存到本地
    summary, failed_count = extract_test_summary(log_file_path)
    # send_summary_to_server("docker.xcoresigma.com/docker/siginfer-x86_64-tianshu:" + docker_image_version, model_name, summary)
    save_summary_to_log("docker.xcoresigma.com/docker/siginfer-x86_64-tianshu:" + docker_image_version, model_name, summary, failed_count)

if __name__ == "__main__":
    main()
