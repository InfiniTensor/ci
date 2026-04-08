import yaml
import re
import os
import sys


def main():
    if len(sys.argv) != 4:
        print("Usage: python script_generator_for_MindIE.py <test_type> <docker_args> <version>")
        sys.exit(1)
    
    test_type = sys.argv[1]
    docker_args = sys.argv[2]
    version = sys.argv[3]
    
    curr_dir = os.getcwd()
    
    # Load YAML config (do NOT use .xlsx)
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
        target_file = "MindIE_job_executor_for_SmokeTest.sh"
    elif test_type == "Performance":
        target_file = "MindIE_job_executor_for_PerformanceTest.sh"
    elif test_type == "Stability":
        target_file = "MindIE_job_executor_for_StabilityTest.sh"
    elif test_type == "Accuracy":
        target_file = "MindIE_job_executor_for_AccuracyTest.sh"
    
    model_list = ""
    start = True
    for model in models:
        name = (model or {}).get('model_name')
        args = (model or {}).get('default_params') or ''

        if not name or not args:
            continue

        # Keep the first line (Excel-like behavior of using split('\\n')[0])
        args = str(args).splitlines()[0].strip()
        
        pattern = "--tokenizer\s+(\S+)"
        match = re.search(pattern, args)
        if match:
            model_weight_path = match.group(1)
        else:
            model_weight_path = ""
        
        pattern = "-tp\s+(\d+)"
        match = re.search(pattern, args)
        if match:
            npu_quantity = match.group(1)
        else:
            npu_quantity = "0"

        model_list += f"{model}:{npu_quantity} "

        if start:
            src_code += f"    if [ $MODEL == \"{name}\" ]; then\n"
            start = False
        else:
            src_code += f"    elif [ $MODEL == \"{name}\" ]; then\n"
        src_code += f"        MODEL_WEIGHT_PATH=\"{model_weight_path}\"\n"
    src_code += "    fi\n"
    
    # print(src_code)

    template_file = "job_executor_template_for_MindIE.sh"

    try:
        with open(f"{curr_dir}/{template_file}", 'r', encoding='utf-8') as file:
            lines = file.readlines()
        
        line_num = 0
        for line in lines:
            if "<<<generated source code>>>" in line:
                lines[line_num] = src_code
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
                lines[line_num] = line.replace("<<<DOCKER_ARGS>>>", docker_args)
            line_num += 1

        with open(f"{curr_dir}/{target_file}", 'w') as file:
            file.write(''.join(lines))
    except FileNotFoundError:
        print(f"Error: Log file '{curr_dir}/{template_file}' not found.")
    except Exception as e:
        print(f"Error reading file: {str(e)}")
    
    os.system(f"chmod 777 {target_file}")

    print(model_list.rstrip())

if __name__ == "__main__":
    main()
