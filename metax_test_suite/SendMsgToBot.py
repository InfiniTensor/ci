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
    
    # 列标题（等宽对齐）
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
    
    server_url = 'https://open.feishu.cn/open-apis/bot/v2/hook/2b7196ec-7bf5-4b17-ac16-a4c97c59007c'  # 替换为实际的服务端 URL

    try:
        # 构造 POST 请求的数据
        headers = {"Content-Type": "application/json"}
        if model_name is not None:
            summary_text = "Model Name: " + model_name + "\n" + summary_text
            title_text = "性能测试报告"
        else:
            title_text = "冒烟测试报告"
        
        # 表头与数据在同一等宽代码块中，确保列对齐
        summary_md = f"```\n{summary_text}\n```"
        payload = {
            "msg_type":"interactive","card":{
                "schema": "2.0", # 卡片 JSON 结构的版本。默认为 1.0。要使用 JSON 2.0 结构，必须显示声明 2.0。
                "config": {
                    "streaming_mode": True, # 卡片是否处于流式更新模式，默认值为 False。
                    "streaming_config": {}, # 流式更新配置。详情参考下文。
                    "summary": {  # 卡片摘要信息。可通过该参数自定义客户端聊天栏消息预览中的展示文案。
                        "content": "自定义内容", # 自定义摘要信息。如果开启了流式更新模式，该参数将默认为“生成中”。
                        "i18n_content": { # 摘要信息的多语言配置。了解支持的所有语种。参考配置卡片多语言文档。
                            "zh_cn": "",
                            "en_us": "",
                            "ja_jp": ""
                        }
                    },
                    "locales": [ # JSON 2.0 新增属性。用于指定生效的语言。如果配置 locales，则只有 locales 中的语言会生效。
                        "en_us",
                        "ja_jp"
                    ],
                    "enable_forward": True, # 是否支持转发卡片。默认值为 True。
                    "update_multi": True, # 是否为共享卡片。默认值为 True，JSON 2.0 暂时仅支持设为 True，即更新卡片的内容对所有收到这张卡片的人员可见。
                    "width_mode": "fill", # 卡片宽度模式。支持 "compact"（紧凑宽度 400px）模式 或 "fill"（撑满聊天窗口宽度）模式。默认不填时的宽度为 600px。
                    "use_custom_translation": False, # 是否使用自定义翻译数据。默认值 False。为 True 时，在用户点击消息翻译后，使用 i18n 对应的目标语种作为翻译结果。若 i18n 取不到，则使用当前内容请求翻译，不使用自定义翻译数据。
                    "enable_forward_interaction": False, # 转发的卡片是否仍然支持回传交互。默认值 False。
                    "style": { # 添加自定义字号和颜色。可应用在组件 JSON 数据中，设置字号和颜色属性。
                        "text_size": { # 分别为移动端和桌面端添加自定义字号，同时添加兜底字号。用于在组件 JSON 中设置字号属性。支持添加多个自定义字号对象。
                            "cus-0": {
                                "default": "medium", # 在无法差异化配置字号的旧版飞书客户端上，生效的字号属性。选填。
                                "pc": "medium", # 桌面端的字号。
                                "mobile": "large" # 移动端的字号。
                            }
                        },
                        "color": { # 分别为飞书客户端浅色主题和深色主题添加 RGBA 语法。用于在组件 JSON 中设置颜色属性。支持添加多个自定义颜色对象。
                            "cus-0": {
                                "light_mode": "rgba(5,157,178,0.52)", # 浅色主题下的自定义颜色语法
                                "dark_mode": "rgba(78,23,108,0.49)" # 深色主题下的自定义颜色语法
                            }
                        }
                    }
                },
                "header": {
                    "title": {
                        # 卡片主标题。必填。要为标题配置多语言，参考配置卡片多语言文档。
                        "tag": "plain_text", # 文本类型的标签。可选值：plain_text 和 lark_md。
                        "content": title_text # 标题内容。
                    },
                    "subtitle": {
                        # 卡片副标题。可选。
                        "tag": "plain_text", # 文本类型的标签。可选值：plain_text 和 lark_md。
                        "content": version_text # 副标题内容。
                    },
                    "i18n_text_tag_list": {
                        # 多语言标题后缀标签。每个语言环境最多设置 3 个 tag，超出不展示。可选。同时配置原字段和国际化字段，优先生效多语言配置。
                        "zh_cn": [],
                        "en_us": [],
                        "ja_jp": [],
                        "zh_hk": [],
                        "zh_tw": []
                    },
                    "template": "blue", # 标题主题样式颜色。支持 "blue"|"wathet"|"turquoise"|"green"|"yellow"|"orange"|"red"|"carmine"|"violet"|"purple"|"indigo"|"grey"|"default"。默认值 default。
                    "padding": "12px 8px 12px 8px" # 标题组件的内边距。JSON 2.0 新增属性。默认值 "12px"，支持范围 [0,99]px。    
                },
                "body": {
                    "elements": [
                        {
                            "tag": "div",
                            "element_id": "custom_id", # 操作组件的唯一标识。JSON 2.0 新增属性。用于在调用组件相关接口中指定组件。需开发者自定义。
                            "margin": "0px 0px 0px 0px", # 组件的外边距，默认值 "0"。JSON 2.0 新增属性。支持范围 [-99,99]px。
                            "width": "fill", # 文本宽度。JSON 2.0 新增属性。支持 "fill"、"auto"、"[16,999]px"。默认值为 fill。
                            "text": { # 配置普通文本信息。
                                "tag": "lark_md", # 文本类型的标签。可取值：plain_text 和 lark_md。
                                "element_id": "custom_id", # 普通文本元素的 ID。JSON 2.0 新增属性。在调用流式更新文本接口时，需传入该参数值指定要流式更新的文本内容。
                                "content": summary_md, # 文本内容。当 tag 为 lark_md 时，支持部分 Markdown 语法的文本内容。
                                "text_size": "normal", # 文本大小。默认值 normal。支持自定义在移动端和桌面端的不同字号。
                                "text_color": "default", # 文本颜色。仅在 tag 为 plain_text 时生效。默认值 default。
                                "text_align": "left", # 文本对齐方式。默认值 left。
                            }
                        }
                    ]
                }
            }
        }

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
    summary = read_and_format_summary(log_file_path, "aarch64-metax-910B3:" + docker_image_version)
    send_summary_to_server("aarch64-metax-910B3:" + docker_image_version, None, summary)
    
if __name__ == "__main__":
    main()
