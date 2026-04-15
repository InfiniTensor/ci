import yaml
import re
import os
import sys


def main():
    if len(sys.argv) != 4:
        print("Usage: python script_generator_for_InfiniTensor.py <test_type> <docker_args> <version>")
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
        target_file = "infiniTensor_job_executor_for_SmokeTest.sh"
    if test_type == "Unit":
        target_file = "infiniTensor_job_executor_for_UnitTest.sh"
    elif test_type == "Performance":
        target_file = "infiniTensor_job_executor_for_PerformanceTest.sh"
    elif test_type == "Stability":
        target_file = "infiniTensor_job_executor_for_StabilityTest.sh"
    elif test_type == "Accuracy":
        target_file = "infiniTensor_job_executor_for_AccuracyTest.sh"

    if test_type != "Unit":
        model_list = ""
        start = True
        for model in models:
            name = (model or {}).get('model_name')
            args = (model or {}).get('default_params') or ''

            if not name or not args:
                continue

            args = str(args).splitlines()[0].strip()

            match = re.search(r"-tp\s+(\d+)", args)
            npu_quantity = match.group(1) if match else "0"

            model_list += f"{name}:{npu_quantity} "

            result = re.sub(
                r"^.*docker\.xcoresigma\.com/docker/infiniTensor-aarch64-moore\:\S+",
                "",
                args,
            )
            result = re.sub(r"--prometheus-port\s+\d+", "--prometheus-port $PROMETHEUS_PORT", result)
            result = re.sub(r"--port\s+\d+", "--port $PORT", result)
            result = re.sub(r"--master-addr\s+\S+", "--master-addr $MASTER_IP", result)
            result = re.sub(r"--node-rank\s+\d+", "--node-rank $NODE_RANK", result)
            result = re.sub(r"--schedule-policy\s+\S+", "--schedule-policy $SCHEDULE_POLICY", result)
            result = re.sub(r"--master-port\s+\d+", "--master-port $MASTER_PORT", result)
            
            if start:
                src_code += f"if [ $MODEL == \"{name}\" ]; then\n"
                start = False
            else:
                src_code += f"elif [ $MODEL == \"{name}\" ]; then\n"
            src_code += "    echo \"SIG_LOG_LEVEL='warn,console_logger=info' ./start.sh "
            src_code += result
            src_code += "\"\n"

            src_code += "    EXEC_COMMAND+=\" "
            src_code += result
            src_code += " > $LOG_NAME 2>&1 &\"\n"

        src_code += "fi\n"

    template_file = "job_executor_template_for_InfiniTensor.sh"

    try:
        with open(f"{curr_dir}/{template_file}", 'r', encoding='utf-8') as file:
            lines = file.readlines()

        line_num = 0
        for line in lines:
            if "<<<generated source code>>>" in line:
                if test_type == "Unit":
                    lines[line_num] = line.replace("<<<generated source code>>>", "")
                else:
                    lines[line_num] = src_code
            elif "<<<TEST_TYPE>>>" in line:
                if test_type == "Smoke":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "SmokeTest")
                elif type_type == "Unit":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "UnitTest")    
                elif test_type == "Performance":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "PerformanceTest")
                elif test_type == "Accuracy":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "AccuracyTest")
                elif test_type == "Stability":
                    lines[line_num] = line.replace("<<<TEST_TYPE>>>", "StabilityTest")
            elif "<<<DOCKER_ARGS>>>" in line:
                if test_type == "Unit":
                    lines[line_num] = line.replace("<<<DOCKER_ARGS>>>", docker_args)
                else:
                    lines[line_num] = line.replace("<<<DOCKER_ARGS>>>", docker_args + " -e ASCEND_RT_VISIBLE_DEVICES=$ASCEND_RT_VISIBLE_DEVICES docker.infinitensor.com/docker/infiniTensor-aarch64-moore:$LATEST_TAG")
            line_num += 1

        with open(f"{curr_dir}/{target_file}", 'w') as file:
            file.write(''.join(lines))
    except FileNotFoundError:
        print(f"Error: Log file '{curr_dir}/{template_file}' not found.")
    except Exception as e:
        print(f"Error reading file: {str(e)}")

    os.system(f"chmod 777 {target_file}")

    if test_type != "Unit":
        print(model_list.rstrip())
    else:
        print("None")

if __name__ == "__main__":
    main()
