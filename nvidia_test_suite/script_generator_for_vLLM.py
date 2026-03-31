import yaml
import re
import os
import sys

def clean_card_type(card_type):
    """清理卡型，去掉括号中的内容和额外描述"""
    if not card_type:
        return None
    
    card_type = str(card_type).strip()
    # 去掉括号及其内容，例如 'H20 (96G)' -> 'H20'
    card_type = re.sub(r'\s*\([^)]*\)', '', card_type)
    # 去掉额外的描述文本（如"长上下文"等）
    # 只保留卡型名称部分（通常是字母数字组合，可能包含斜杠）
    card_type = re.sub(r'\s+[^\w/]+.*$', '', card_type)
    return card_type.strip()

def extract_card_types(card_type_str):
    """从卡型字符串中提取所有卡型（可能包含多个，用顿号分隔）"""
    if not card_type_str:
        return []
    
    card_type_str = str(card_type_str).strip()
    # 按顿号分割
    card_types = [ct.strip() for ct in card_type_str.split('、')]
    
    # 清理每个卡型并过滤
    cleaned_cards = []
    for ct in card_types:
        cleaned = clean_card_type(ct)
        if cleaned:
            # 如果卡型包含斜杠（如H100/A100），需要分别处理
            if '/' in cleaned:
                parts = [p.strip() for p in cleaned.split('/')]
                for part in parts:
                    cleaned_cards.append(part)
            else:
                cleaned_cards.append(cleaned)
    
    return cleaned_cards

def main():
    if len(sys.argv) != 4:
        print("Usage: python script_generator_for_vLLM.py <test_type> <docker_args> <version>")
        sys.exit(1)
    
    test_type = sys.argv[1]
    docker_args = sys.argv[2]
    version = sys.argv[3]
    
    curr_dir = os.getcwd()

    yaml_candidates = [
        f'{curr_dir}/{version}/model_list.yml',
        f'{curr_dir}/{version}/model_list.yaml',
    ]

    file_path = None
    for candidate in yaml_candidates:
        if os.path.exists(candidate):
            file_path = candidate
            break
    
    if not file_path:
        print(f"Error: YAML config not found for version '{version}'. Tried: {', '.join(yaml_candidates)}")
        sys.exit(1)

    with open(file_path, 'r', encoding='utf-8') as f:
        cfg = yaml.safe_load(f) or {}

    models = cfg.get('models', [])
    if not isinstance(models, list):
        print("Error: YAML key 'models' must be a list.")
        sys.exit(1)
    
    target_file = ""
    src_code = ""
    
    if test_type == "Smoke":
        target_file = "vLLM_job_executor_for_SmokeTest.sh"
        src_code += "docker exec vllm_nvidia_SmokeTest_${SESSION_ID}_${JOB_COUNT} /bin/bash -c \"\n"
    elif test_type == "Performance":
        target_file = "vLLM_job_executor_for_PerformanceTest.sh"
        src_code += "docker exec vllm_nvidia_PerformanceTest_${SESSION_ID}_${JOB_COUNT} /bin/bash -c \"\n"
    elif test_type == "Stability":
        target_file = "vLLM_job_executor_for_StabilityTest.sh"
        src_code += "docker exec vllm_nvidia_StabilityTest_${SESSION_ID}_${JOB_COUNT} /bin/bash -c \"\n"
    elif test_type == "Accuracy":
        target_file = "vLLM_job_executor_for_AccuracyTest.sh"
        src_code += "docker exec vllm_nvidia_AccuracyTest_${SESSION_ID}_${JOB_COUNT} /bin/bash -c \"\n"
    
    start = True
    for model in models:
        # Expected YAML schema:
        # - model_name (str)
        # - card_type (str)
        # - default_params (str): docker run ... command fragment
        name = (model or {}).get('model_name')
        GPU = (model or {}).get('card_type')
        args = (model or {}).get('default_params') or ''

        if not name or not GPU or not args:
            continue

        args = str(args).splitlines()[0].strip()

        result = re.sub(r"--model\s+", "", args)
        result = re.sub(r"--port\s+\d+", "--port $PORT", result)
        result = re.sub(r"--served-model-name\s+\S+", f"--served-model-name {name}", result)
        
        card_types = extract_card_types(GPU)
        for card_type in card_types:
            if start:
                src_code += f"if [ \\\"${{MODEL}}_${{GPU_MODEL}}\\\" == \\\"{name}_{card_type}\\\" ]; then\n"
                start = False
            else:
                src_code += f"elif [ \\\"${{MODEL}}_${{GPU_MODEL}}\\\" == \\\"{name}_{card_type}\\\" ]; then\n"
            src_code += "    echo \\\"vllm serve "
            src_code += result
            src_code += " > $LOG_NAME 2>&1 &"
            src_code += "\\\"\n"
            src_code += "    nohup env CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES vllm serve "
            src_code += result
            src_code += " > $LOG_NAME 2>&1 &\n"
    src_code += "fi\n"

    # print(src_code)

    template_file = "job_executor_template_for_vLLM.sh"

    try:
        with open(f"{curr_dir}/{template_file}", 'r', encoding='utf-8') as file:
            lines = file.readlines()
        
        line_num = 0
        for line in lines:
            if "<<<generated source code>>>" in line:
                lines[line_num] = src_code
                with open(f"{curr_dir}/{target_file}", 'w') as file:
                    file.write(''.join(lines))
                # print(lines)
                break
            elif "<<<TEST_TYPE>>>" in line:
                if test_type == "Smoke":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "SmokeTest")
                elif test_type == "Performance":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "PerformanceTest")
                elif test_type == "Accuracy":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "AccuracyTest")
                elif test_type == "Stability":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "StabilityTest")
            elif "<<<DOCKER_ARGS>>>" in line:
                lines[line_num] = docker_args + " \\"
            line_num += 1
    except FileNotFoundError:
        print(f"Error: Log file '{curr_dir}/{template_file}' not found.")
    except Exception as e:
        print(f"Error reading file: {str(e)}")
    
    os.system(f"chmod 777 {target_file}")

if __name__ == "__main__":
    main()
