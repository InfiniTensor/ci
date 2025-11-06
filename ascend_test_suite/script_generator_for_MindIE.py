from openpyxl import load_workbook
import re
import os
import sys


def main():
    verison = ""
    if len(sys.argv) != 2:
        print("Usage: python script_generator <test_type>")
        sys.exit(1)
    
    test_type = sys.argv[1]
    
    curr_dir = os.getcwd()
    
    target_file = ""
    src_code = ""
    
    if test_type == "Smoke":
        src_code += "docker exec siginfer_ascend_SmokeTest_${JOB_COUNT} /bin/bash -c \"\n"
        target_file = "job_executor_for_SmokeTest.sh"
    elif test_type == "Performance":
        src_code += "docker exec siginfer_ascend_PerformanceTest_${JOB_COUNT} /bin/bash -c \"\n"
        target_file = "job_executor_for_PerformanceTest.sh"
    elif test_type == "Stability":
        src_code += "docker exec siginfer_ascend_StabilityTest_${JOB_COUNT} /bin/bash -c \"\n"
        target_file = "job_executor_for_StabilityTest.sh"
    elif test_type == "Accuracy":
        src_code += "docker exec siginfer_ascend_AccuracyTest_${JOB_COUNT} /bin/bash -c \"\n"
        target_file = "job_executor_for_AccuracyTest.sh"
    
    src_code += "\
        source /usr/local/Ascend/ascend-toolkit/set_env.sh\n\
        source /usr/local/Ascend/nnal/atb/set_env.sh\n\
        source /usr/local/Ascend/atb-models/set_env.sh\n\
        source /usr/local/Ascend/mindie/set_env.sh\n\
        export ATB_LLM_HCCL_ENABLE=1\n\
        export ATB_LLM_COMM_BACKEND=\"hccl\"\n\
        export HCCL_CONNECT_TIMEOUT=7200\n\
        export WORLD_SIZE=16\n\
        export HCCL_EXEC_TIMEOUT=0\n\
        export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True\n\
        export OMP_NUM_THREADS=1\n\
        export NPU_MEMORY_FRACTION=0.96\n\
        export RANK_TABLE_FILE=/ranktable.json\n\
        export HCCL_DETERMINISTIC=true\n\
        export MIES_CONTAINER_IP=\$(hostname -I | awk '{print \$1}')\n\n"
    
    src_code += "cd /usr/local/Ascend/mindie/latest/mindie-service/\n"
    src_code += "nohup ./bin/mindieservice_daemon > $LOG_NAME 2>&1 &\n"
    
    # print(src_code)

    template_file = "job_executor_template_for_MindIE.sh"

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
            line_num += 1
    except FileNotFoundError:
        print(f"Error: Log file '{curr_dir}/{template_file}' not found.")
    except Exception as e:
        print(f"Error reading file: {str(e)}")
    
    os.system(f"chmod 777 {target_file}")

if __name__ == "__main__":
    main()
