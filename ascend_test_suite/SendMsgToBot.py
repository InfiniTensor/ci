import requests
import sys


def read_and_format_summary(file_path, version_text=""):
    """
    读取summary文件并格式化输出
    
    Args:
        file_path: summary文件路径
        version_text: 版本信息文本，显示在第一行
        
    Returns:
        格式化后的字符串，第一行显示版本信息，第二行显示列标题，
        第一列模型名称按最长名称宽度对齐，冒号后面是4列：passed, failed, warning, skipped
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            lines = file.readlines()
    except FileNotFoundError:
        print(f"Error: File '{file_path}' not found.")
        return ""
    except Exception as e:
        print(f"Error reading file: {str(e)}")
        return ""
    
    # 解析所有行，提取模型名称和数据
    parsed_data = []
    max_model_name_length = 0
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        # 按冒号分割模型名称和数据
        if ':' in line:
            parts = line.split(':', 1)
            model_name = parts[0].strip()
            data_part = parts[1].strip()
            
            # 提取4个数字
            numbers = data_part.split()
            if len(numbers) >= 4:
                parsed_data.append({
                    'model_name': model_name,
                    'passed': numbers[0],
                    'failed': numbers[1],
                    'warning': numbers[2],
                    'skipped': numbers[3]
                })
                # 更新最长模型名称长度
                max_model_name_length = max(max_model_name_length, len(model_name))
    
    # 构建输出字符串
    formatted_lines = []
    
    # 第一行：标题
    title_line = "冒烟测试报告"
    formatted_lines.append(title_line)
    
    # 第二行：版本信息
    if version_text:
        formatted_lines.append(version_text)
    
    # 第三行：列标题
    header_line = f"{'Model Name':<{max_model_name_length}} :{'Passed':>8} {'Failed':>8} {'Warning':>8} {'Skipped':>8}"
    formatted_lines.append(header_line)
    
    # 数据行
    for data in parsed_data:
        # 模型名称列按最长名称宽度对齐，后面是4列数据
        formatted_line = f"{data['model_name']:<{max_model_name_length}} :{data['passed']:>8} {data['failed']:>8} {data['warning']:>8} {data['skipped']:>8}"
        formatted_lines.append(formatted_line)
    
    # 返回格式化后的字符串
    return '\n'.join(formatted_lines)


def send_summary_to_server(version_text, model_name, summary_text):
    if not summary_text:
        print("No summary to send.")
        return

    print(summary_text)
    
    server_url = 'https://open.feishu.cn/open-apis/bot/v2/hook/9c267c92-100a-40c6-ab32-cc1ca57df84e'  # 替换为实际的服务端 URL

    try:
        # 构造 POST 请求的数据
        headers = {"Content-Type": "application/json"}
        if model_name is not None and version_text is not None:
            payload = {"msg_type":"text", "content": {"text": version_text + "\n" + model_name + "\n" + summary_text}}
        else:
            payload = {"msg_type":"text", "content": {"text": summary_text}}
        
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


def compare_summary_files(version_text1, file_path1, version_text2, file_path2):
    """
    比较两个summary文件，打印对应指标数值的差异
    
    Args:
        version_text1: 第一个版本信息
        version_text2: 第二个版本信息
        file_path1: 第一个summary文件路径
        file_path2: 第二个summary文件路径
    """
    def parse_summary_file(file_path):
        """解析summary文件，返回解析后的数据列表"""
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                lines = file.readlines()
        except FileNotFoundError:
            print(f"Error: File '{file_path}' not found.")
            return None
        except Exception as e:
            print(f"Error reading file '{file_path}': {str(e)}")
            return None
        
        parsed_data = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            # 按冒号分割模型名称和数据
            if ':' in line:
                parts = line.split(':', 1)
                model_name = parts[0].strip()
                data_part = parts[1].strip()
                
                # 提取4个数字
                numbers = data_part.split()
                if len(numbers) >= 4:
                    try:
                        parsed_data.append({
                            'model_name': model_name,
                            'passed': int(numbers[0]),
                            'failed': int(numbers[1]),
                            'warning': int(numbers[2]),
                            'skipped': int(numbers[3])
                        })
                    except ValueError:
                        print(f"Warning: Invalid number format in line: {line}")
                        continue
        
        # 按 model_name 进行字母排序（不区分大小写）
        parsed_data.sort(key=lambda x: x['model_name'].lower())
        
        return parsed_data
    
    # 解析两个文件
    data1 = parse_summary_file(file_path1)
    data2 = parse_summary_file(file_path2)
    
    if data1 is None or data2 is None:
        return
    
    result = ""
    # 打印文件路径信息
    result += f"版本差异报告: \n"
    result += f"  当前版本：{version_text1}\n"
    result += f"  上一版本：{version_text2}\n"
    
    # 将数据转换为字典，以 model_name 为键，方便查找
    dict1 = {item['model_name']: item for item in data1}
    dict2 = {item['model_name']: item for item in data2}
    
    # 获取所有唯一的 model_name，并排序
    all_model_names = sorted(set(list(dict1.keys()) + list(dict2.keys())), key=str.lower)
    
    max_model_name_length = 0
    # 计算最长模型名称长度（用于格式化输出）
    for model_name in all_model_names:
        max_model_name_length = max(max_model_name_length, len(model_name))
    
    # 格式化差异值（正数显示+，负数显示-）
    def format_diff(val):
        if val > 0:
            return f"+{val}"
        elif val < 0:
            return str(val)
        else:
            return "0"
    
    # 打印表头（只显示Diff列）
    header = f"{'Model Name':<{max_model_name_length}} | {'Passed':>8} {'Failed':>8} {'Warning':>8} {'Skipped':>8}"
    result += header + "\n"
    
    # 按 model_name 逐个比较（只比较相同 model_name 的指标）
    has_diff = False
    for model_name in all_model_names:
        if model_name in dict1 and model_name in dict2:
            # 两个文件中都有该模型，进行比较
            item1 = dict1[model_name]
            item2 = dict2[model_name]
            
            # 计算差异
            diff_passed = item1['passed'] - item2['passed']
            diff_failed = item1['failed'] - item2['failed']
            diff_warning = item1['warning'] - item2['warning']
            diff_skipped = item1['skipped'] - item2['skipped']
            
            # 检查是否有差异
            if diff_passed != 0 or diff_failed != 0 or diff_warning != 0 or diff_skipped != 0:
                has_diff = True
                # 打印比较结果（只显示Diff）
                line = (f"{model_name:<{max_model_name_length}} | "
                    f"{format_diff(diff_passed):>8} {format_diff(diff_failed):>8} {format_diff(diff_warning):>8} {format_diff(diff_skipped):>8}")
                result += line + "\n"
        elif model_name in dict1:
            has_diff = True
            # 只在文件1中存在
            line = (f"{model_name:<{max_model_name_length}} | "
                 f"{'N/A':>8} {'N/A':>8} {'N/A':>8} {'N/A':>8}")
            result += line + "\n"
        elif model_name in dict2:
            has_diff = True
            # 只在文件2中存在
            line = (f"{model_name:<{max_model_name_length}} | "
                 f"{'N/A':>8} {'N/A':>8} {'N/A':>8} {'N/A':>8}")
            result += line + "\n"
    
    if not has_diff:
        result += "\n两个报告中的数据完全一致，没有差异。"
    else:
        result += "\n比较完成，已显示所有差异。"
    
    return result


def main():
    if len(sys.argv) != 3:
        print("Usage: python SendMsgToBot <docker_image_version> <log_file_path>")
        sys.exit(1)
    
    docker_image_version = sys.argv[1]
    log_file_path = sys.argv[2]
    
    # 提取 summary 连同版本信息一并发送或保存到本地
    summary = read_and_format_summary(log_file_path, "siginfer-aarch64-ascend:" + docker_image_version)
    send_summary_to_server(None, None, summary)
    
if __name__ == "__main__":
    main()
