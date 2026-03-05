#!/bin/bash

# 导入NPU锁管理器
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/npu_lock_manager_for_ci.sh"
LOCK_DIR="/home/s_limingge/.npu_locks"
LOCK_FILE="server_config.lock"

# 接收参数
MODEL=$1
GPU_QUANITY=$2
SERVER_LIST=$3
NODE_RANK=$4
JOB_COUNT=$5
SESSION_ID=$6
VERSION=$7

echo "MODEL=$MODEL"
echo "GPU_QUANITY=$GPU_QUANITY"
echo "SERVER_LIST=$SERVER_LIST"
echo "NODE_RANK=$NODE_RANK"
echo "JOB_COUNT=$JOB_COUNT"
echo "SESSION_ID=$SESSION_ID"
echo "VERSION=$VERSION"

# 生成唯一的任务ID
TASK_ID="<<<TEST_TYPE>>>_${MODEL}_${JOB_COUNT}"
JOB_ID="<<<TEST_TYPE>>>_${MODEL}_${SESSION_ID}_${JOB_COUNT}"
LOCAL_IP=$(hostname -I | xargs printf "%s\n" | grep "10.0.0")
SERVER_NAME=$(echo $LOCAL_IP | sed 's/\./_/g')

# 设置清理函数，确保异常退出时释放锁
cleanup_locks() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "中止job executor测试任务......"
        if [ ! -z "$LOCKED_NPUS" ]; then
            echo "检测到异常退出（退出码: $exit_code），正在释放Server Config文件锁: ${LOCK_DIR}/${LOCK_FILE}"
            # 获取文件锁（阻塞）
            exec 200>"${LOCK_DIR}/${LOCK_FILE}"    # 打开文件描述符 200
            if ! flock -x 200; then    # 获取独占锁
                echo "无法获取锁，退出..."
            fi
            # 删除Server端配置信息，如果存在的话
            # sed -i "/${LOCAL_IP}:${JOB_ID}:/d" "${LOCK_DIR}/server_config.txt"
            new_config=`sed "/${LOCAL_IP}:${JOB_ID}:/d" "${LOCK_DIR}/server_config.txt"`
            echo "${new_config}" > "${LOCK_DIR}/server_config.txt"
            # 锁会自动在脚本退出或文件描述符关闭时释放
            exec 200>&-  # 关闭文件描述符
            echo "正在释放NPU锁: ${LOCKED_NPUS}"
            release_npu_locks_batch "$SERVER_NAME" "$LOCKED_NPUS" "$TASK_ID" "$SESSION_ID"
        fi
    else
        echo "正常退出（退出码: 0），保留NPU锁"
    fi
}

# 注册退出时的清理函数
trap cleanup_locks EXIT INT TERM

if [ -z $VERSION ]; then
    echo "MindIE version is not specified!"
    exit 1;
fi

free_port=""

get_free_port() {
    local PORT_RANGE_START=20000
    local PORT_RANGE_END=20999

    for port in $(seq $PORT_RANGE_START $PORT_RANGE_END); do
        if ! lsof -i :"$port" >/dev/null 2>&1; then
            if [[ " ${server_ports[@]} " =~ " $port " ]]; then
                continue
            fi
            server_ports+=($port)
            free_port="$port"
            return
        fi
    done
    free_port=""
}

# 配置参数
MODEL_WEIGHT_PATH=""
RANK_TABLE_PATH="/home/s_limingge/rank_table/$JOB_ID"
CONFIG_FILE="/usr/local/Ascend/mindie/latest/mindie-service/conf/config.json"
CONTAINER_NAME="mindie_ascend_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}"
DOCKER_IMAGE="swr.cn-south-1.myhuaweicloud.com/ascendhub/mindie:${VERSION}"
SHM_SIZE="500g"
NUM_NPUS=8
SERVER_COUNT=$(echo $SERVER_LIST | tr '_' '\n' | wc -l)
LOCAL_SERVER_IP=$(hostname -I | xargs printf "%s\n" | grep "10.0.0")
CONTAINER_IP="${LOCAL_SERVER_IP}"  # 容器IP，默认与节点IP相同
LOG_NAME="server_log_<<<TEST_TYPE>>>_$(date +'%Y%m%d_%H%M%S').log"

# 全局变量：NPU IP地址数组
declare -a NPU_IPS

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 命令未找到，请先安装"
        exit 1
    fi
}

# 获取NPU IP地址（公共函数）
get_npu_ips() {
    log_info "获取每张NPU卡的IP地址..."
    NPU_IPS=()  # 清空数组
    for i in $(seq 0 $((NUM_NPUS-1))); do
        npu_ip=$(hccn_tool -i $i -ip -g | grep -oP 'ipaddr:\K[0-9.]+' || echo "")
        if [ -n "$npu_ip" ]; then
            NPU_IPS[$i]=$npu_ip
            log_info "NPU卡 $i IP地址: ${NPU_IPS[$i]}"
        else
            log_error "无法获取NPU卡 $i 的IP地址"
            exit 1
        fi
    done
}

get_model_weight_path() {
    log_info "获取模型权重路径..."

    <<<generated source code>>>
}

# 步骤1: 检查网络情况
check_network() {
    log_info "步骤1: 检查NPU网络情况..."
    
    for i in $(seq 0 $((NUM_NPUS-1))); do
        log_info "检查NPU卡 $i 的物理链接..."
        hccn_tool -i $i -lldp -g | grep Ifname || log_warn "NPU卡 $i 物理链接检查失败"
        
        log_info "检查NPU卡 $i 的链接状态..."
        hccn_tool -i $i -link -g || log_warn "NPU卡 $i 链接状态检查失败"
        
        log_info "检查NPU卡 $i 的网络健康情况..."
        hccn_tool -i $i -net_health -g || log_warn "NPU卡 $i 网络健康检查失败"
        
        log_info "检查NPU卡 $i 的侦测IP配置..."
        hccn_tool -i $i -netdetect -g || log_warn "NPU卡 $i 侦测IP配置检查失败"
        
        log_info "检查NPU卡 $i 的网关配置..."
        hccn_tool -i $i -gateway -g || log_warn "NPU卡 $i 网关配置检查失败"
    done
    
    log_info "检查NPU底层TLS校验行为一致性..."
    for i in $(seq 0 $((NUM_NPUS-1))); do
        tls_status=$(hccn_tool -i $i -tls -g | grep switch || echo "")
        if [ -n "$tls_status" ]; then
            log_warn "NPU卡 $i TLS状态: $tls_status"
        fi
    done
    
    log_info "设置NPU底层TLS校验行为为0（避免HCCL报错）..."
    for i in $(seq 0 $((NUM_NPUS-1))); do
        hccn_tool -i $i -tls -s enable 0 || log_warn "NPU卡 $i TLS设置失败"
    done
    
    # 获取NPU IP地址
    get_npu_ips
}

# 步骤2: 创建本地rank_table_file.json
create_rank_table() {
    log_info "步骤2: 创建本地rank_table_file.json..."
    
    # 如果NPU_IPS数组为空，则获取NPU IP地址
    if [ ${#NPU_IPS[@]} -eq 0 ]; then
        get_npu_ips
    else
        log_info "使用已获取的NPU IP地址"
    fi
    
    # 计算当前节点的rank起始值
    # 假设每个节点有8张卡，节点0的rank是0-7，节点1的rank是8-15，以此类推
    NPU_RANK_START=$((NODE_RANK*NUM_NPUS))

    log_info "创建rank_table_file.json (节点${NODE_RANK}的IP: $LOCAL_SERVER_IP, NPU Rank起始: $NPU_RANK_START)..."
    
    mkdir -p $RANK_TABLE_PATH
    RANK_TABLE_FILE=$RANK_TABLE_PATH/rank_table_file.json

    if [ -f "$RANK_TABLE_FILE" ]; then
        rm -f "$RANK_TABLE_FILE"
    fi

    # 创建JSON文件
    cat > "$RANK_TABLE_FILE" <<EOF
{
   "server_count": "1",
   "server_list": [
EOF
    
    # 生成当前节点的device配置
    echo "      {" >> "$RANK_TABLE_FILE"
    echo "         \"device\": [" >> "$RANK_TABLE_FILE"
    for i in $(seq 0 $((NUM_NPUS-1))); do
        rank_id=$((NPU_RANK_START + i))
        echo "            {" >> "$RANK_TABLE_FILE"
        echo "               \"device_id\": \"$i\"," >> "$RANK_TABLE_FILE"
        echo "               \"device_ip\": \"${NPU_IPS[$i]}\"," >> "$RANK_TABLE_FILE"
        echo "               \"rank_id\": \"$rank_id\"" >> "$RANK_TABLE_FILE"
        if [ $i -lt $((NUM_NPUS-1)) ]; then
            echo "            }," >> "$RANK_TABLE_FILE"
        else
            echo "            }" >> "$RANK_TABLE_FILE"
        fi
    done
    echo "         ]," >> "$RANK_TABLE_FILE"
    echo "         \"server_id\": \"$LOCAL_SERVER_IP\"," >> "$RANK_TABLE_FILE"
    echo "         \"container_ip\": \"$CONTAINER_IP\"" >> "$RANK_TABLE_FILE"
    echo "      }" >> "$RANK_TABLE_FILE"
    echo "   ]," >> "$RANK_TABLE_FILE"
    echo "   \"status\": \"completed\"," >> "$RANK_TABLE_FILE"
    echo "   \"version\": \"1.0\"" >> "$RANK_TABLE_FILE"
    echo "}" >> "$RANK_TABLE_FILE"
    
    # 修改权限 - 设置为 640 让所有用户（包括 root）都可以读取
    chmod 640 "$RANK_TABLE_FILE"
    # 尝试修改所有者为 root（如果可能），避免权限检查失败
    chown root:root "$RANK_TABLE_FILE" 2>/dev/null || log_warn "无法修改文件所有者（可能需要root权限）"
    log_info "rank_table_file.json 已创建: $RANK_TABLE_FILE"
}

# 步骤3: 生成全局rank_table_file.json
generate_merged_rank_table() {
    log_info "步骤3: 生成全局rank_table_file.json..."
    
    curl -X POST http://192.168.100.106:$((8080+$JOB_COUNT))/rank/$SERVER_NAME -F "file=@$RANK_TABLE_FILE"
    
    GLOBAL_RANK_TABLE_FILE=$RANK_TABLE_PATH/merged_rank_table.json
    
    while [ ! -f $GLOBAL_RANK_TABLE_FILE ]; do sleep 1; done

    mv $GLOBAL_RANK_TABLE_FILE $RANK_TABLE_PATH/rank_table.json
}

# 步骤4: 修改模型文件夹权限
fix_model_permissions() {
    log_info "步骤4: 修改模型文件夹权限..."
    
    if [ ! -d "$MODEL_WEIGHT_PATH" ]; then
        log_error "模型路径不存在: $MODEL_WEIGHT_PATH"
        exit 1
    fi
    
    log_info "修改模型文件夹属组为1001:HwHiAiUser..."
    chown -R 1001:1001 "$MODEL_WEIGHT_PATH" || log_warn "修改属组失败（可能需要root权限）"
    
    log_info "修改模型文件夹权限为750..."
    chmod -R 750 "$MODEL_WEIGHT_PATH" || log_warn "修改权限失败"
    
    log_info "模型文件夹权限设置完成"
}

# 步骤5: 加载Docker镜像
load_docker_image() {
    log_info "步骤5: 检查Docker镜像..."
    
    if docker images | grep -q "${VERSION}"; then
        log_info "Docker镜像已存在: ${VERSION}"
    else
        log_error "Docker镜像不存在: ${VERSION}"
        exit 1
    fi
}

# 步骤6: 启动容器
start_container() {
    log_info "步骤6: 启动Docker容器..."
    log_info "创建并启动容器: $CONTAINER_NAME"
    
    docker run -itd --privileged \
        --name="$CONTAINER_NAME" \
        --net=host \
        --shm-size="$SHM_SIZE" \
        --ipc=host \
        --device=/dev/davinci0 \
        --device=/dev/davinci1 \
        --device=/dev/davinci2 \
        --device=/dev/davinci3 \
        --device=/dev/davinci4 \
        --device=/dev/davinci5 \
        --device=/dev/davinci6 \
        --device=/dev/davinci7 \
        --device=/dev/davinci_manager \
        --device=/dev/hisi_hdc \
        --device=/dev/devmm_svm \
        -v /usr/local/Ascend/driver/lib64:/usr/local/Ascend/driver/lib64 \
        -v /usr/local/Ascend/driver/include:/usr/local/Ascend/driver/include \
        -v /usr/local/Ascend/driver/tools:/usr/local/Ascend/driver/tools \
        -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
        -v /usr/local/Ascend/firmware:/usr/local/Ascend/firmware \
        -v /usr/local/sbin/npu-smi:/usr/local/sbin/npu-smi \
        -v /usr/local/sbin:/usr/local/sbin \
        -v /etc/hccn.conf:/etc/hccn.conf \
        -v /home/weight:/home/weight \
        -v /home/s_limingge:/home/s_limingge \
        -v "$RANK_TABLE_FILE:$RANK_TABLE_FILE" \
        swr.cn-south-1.myhuaweicloud.com/ascendhub/mindie:$VERSION \
        bash
    
    if [ $? -eq 0 ]; then
        log_info "容器启动成功"
    else
        log_error "容器启动失败"
        exit 1
    fi
}

# 步骤7: 创建服务化配置文件
create_service_config() {
    log_info "步骤7: 创建服务化配置文件..."

    MASTER_IP=`echo $SERVER_LIST | tr '_' '\n' | head -n 1`
    if [ $LOCAL_IP == $MASTER_IP ]; then        # 获取Master节点的端口号
        # 获取文件锁（阻塞）
        exec 200>"${LOCK_DIR}/${LOCK_FILE}"    # 打开文件描述符 200
        if ! flock -x 200; then    # 获取独占锁
            echo "无法获取锁，退出..."
            exit 1
        fi

        # 确保文件存在 & 权限正确
        if [ ! -f "${LOCK_DIR}/server_config.txt" ]; then
            touch "${LOCK_DIR}/server_config.txt"
        fi

        server_ports=(`cat "${LOCK_DIR}/server_config.txt" | grep $LOCAL_IP | awk -F ':' '{print $3}'`)

        get_free_port
        PORT=$free_port     # ... 多个节点如何实现端口号保持一致？
        get_free_port
        MULTI_NODES_INFER_PORT=$free_port      # ... 如何使用多个节点的端口号保持一致？

        if [ -z $PORT ] || [ -z $MULTI_NODES_INFER_PORT ]; then
            exit 1
        fi

        echo "$LOCAL_IP:$JOB_ID:$PORT $MULTI_NODES_INFER_PORT" >> "${LOCK_DIR}/server_config.txt"

        # 锁会自动在脚本退出或文件描述符关闭时释放
        exec 200>&-  # 关闭文件描述符
    else    # Slave节点同步到master节点的端口配置
        while true; do
            # 获取文件锁（阻塞）
            exec 200>"${LOCK_DIR}/${LOCK_FILE}"    # 打开文件描述符 200
            if ! flock -x 200; then    # 获取独占锁
                echo "无法获取锁，退出..."
                exit 1
            fi

            # 读取Master节点配置信息
            server_ports=`cat "${LOCK_DIR}/server_config.txt" | grep "${MASTER_IP}:${JOB_ID}:" | awk -F ':' '{print $3}' | tail -n 1`
            if [ ! -z "$server_ports" ]; then
                PORT=$(echo $server_ports | awk '{print $1}')
                MULTI_NODES_INFER_PORT=$(echo $server_ports | awk '{print $2}')
                # 锁会自动在脚本退出或文件描述符关闭时释放
                exec 200>&-  # 关闭文件描述符
                break
            fi

            # 锁会自动在脚本退出或文件描述符关闭时释放
            exec 200>&-  # 关闭文件描述符

            sleep 1
        done
    fi
    
    # 配置参数（可根据需要修改）
    IP_ADDRESS="${IP_ADDRESS:-$LOCAL_SERVER_IP}"  # 本机IP，默认使用LOCAL_SERVER_IP
    HTTPS_ENABLED="${HTTPS_ENABLED:-false}"  # 是否启用HTTPS
    MULTI_NODES_INFER_PORT="${MULTI_NODES_INFER_PORT:-1120}"  # 多节点推理端口
    INTER_NODE_TLS_ENABLED="${INTER_NODE_TLS_ENABLED:-true}"  # 节点间TLS
    MAX_ITER_TIMES="${MAX_ITER_TIMES:-5120}"  # 最大迭代次数
    MAX_SEQ_LEN="${MAX_SEQ_LEN:-5120}"  # 最大序列长度
    MAX_INPUT_TOKEN_LEN="${MAX_INPUT_TOKEN_LEN:-5120}"  # 最大输入token长度
    TRUNCATION="${TRUNCATION:-false}"  # 是否截断
    MAX_PREFILL_TOKENS="${MAX_PREFILL_TOKENS:-5120}"  # 最大预填充token数
    
    # 构建NPU设备ID数组（根据实际使用的NPU）
    # GPU_INFO 包含实际使用的NPU索引
    if [ ${#GPU_INFO[@]} -gt 0 ]; then
        NPU_DEVICE_IDS_LIST=$(seq -s, 0 $((${#GPU_INFO[@]}-1)))
        # WORLD_SIZE=$((${#GPU_INFO[@]}*SERVER_COUNT))
        WORLD_SIZE=${#GPU_INFO[@]}
    else
        # 如果没有指定，使用所有NPU
        NPU_DEVICE_IDS_LIST=$(seq -s, 0 $((NUM_NPUS-1)))
        # WORLD_SIZE=$(($NUM_NPUS*SERVER_COUNT))
        WORLD_SIZE=$NUM_NPUS
    fi

    if [ $SERVER_COUNT -gt 1 ]; then
        MULTI_NODES_ENABLED="True"
    else
        MULTI_NODES_ENABLED="False"
    fi

    log_info "配置参数:"
    log_info "  - ipAddress: $IP_ADDRESS"
    log_info "  - port: $PORT"
    log_info "  - npuDeviceIds: [$NPU_DEVICE_IDS_LIST]"
    log_info "  - worldSize: $WORLD_SIZE"
    log_info "  - modelName: $MODEL"
    log_info "  - modelWeightPath: $MODEL_WEIGHT_PATH"
    log_info "  - multiNodesInferEnabled: $MULTI_NODES_ENABLED"
    
    # 使用Python在容器内生成或修改config.json
    log_info "生成/更新config.json配置文件..."
    
    docker exec -i "$CONTAINER_NAME" python3 <<EOF
import json
import os
# import pwd
# import grp

config_file = "$CONFIG_FILE"

# 读取现有配置文件（如果存在）
config = {}
if os.path.exists(config_file):
    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            config = json.load(f)
        print(f"读取现有配置文件: {config_file}")
    except Exception as e:
        print(f"读取配置文件失败: {e}")
        config = {}

# 确保BackendConfig存在
if "BackendConfig" not in config:
    config["BackendConfig"] = {}

backend_config = config["BackendConfig"]

# 设置基础配置
# backend_config["backendName"] = backend_config.get("backendName", "mindieservice_llm_engine")
# backend_config["modelInstanceNumber"] = backend_config.get("modelInstanceNumber", 1)
npu_ids_list = [$NPU_DEVICE_IDS_LIST]
backend_config["npuDeviceIds"] = [npu_ids_list]
# backend_config["tokenizerProcessNumber"] = backend_config.get("tokenizerProcessNumber", 8)
backend_config["multiNodesInferEnabled"] = str("$MULTI_NODES_ENABLED").lower() == "true"
backend_config["multiNodesInferPort"] = $MULTI_NODES_INFER_PORT
backend_config["interNodeTLSEnabled"] = str("$INTER_NODE_TLS_ENABLED").lower() == "true"

# 设置ModelDeployConfig
if "ModelDeployConfig" not in backend_config:
    backend_config["ModelDeployConfig"] = {}

model_deploy = backend_config["ModelDeployConfig"]
model_deploy["maxSeqLen"] = $MAX_SEQ_LEN
model_deploy["maxInputTokenLen"] = $MAX_INPUT_TOKEN_LEN
model_deploy["truncation"] = str("$TRUNCATION").lower() == "true"

# 设置ModelConfig
if "ModelConfig" not in model_deploy:
    model_deploy["ModelConfig"] = [{}]

if len(model_deploy["ModelConfig"]) == 0:
    model_deploy["ModelConfig"] = [{}]

model_config = model_deploy["ModelConfig"][0]
# model_config["modelInstanceType"] = model_config.get("modelInstanceType", "Standard")
model_config["modelName"] = "$MODEL"
model_config["modelWeightPath"] = "$MODEL_WEIGHT_PATH"
model_config["worldSize"] = $WORLD_SIZE
# model_config["cpuMemSize"] = model_config.get("cpuMemSize", 5)
# model_config["npuMemSize"] = model_config.get("npuMemSize", -1)
# model_config["backendType"] = model_config.get("backendType", "atb")
# model_config["trustRemoteCode"] = model_config.get("trustRemoteCode", False)

# 设置ScheduleConfig
if "ScheduleConfig" not in backend_config:
    backend_config["ScheduleConfig"] = {}

schedule_config = backend_config["ScheduleConfig"]
# schedule_config["templateType"] = schedule_config.get("templateType", "Standard")
# schedule_config["templateName"] = schedule_config.get("templateName", "Standard_LLM")
# schedule_config["cacheBlockSize"] = schedule_config.get("cacheBlockSize", 128)
# schedule_config["maxPrefillBatchSize"] = schedule_config.get("maxPrefillBatchSize", 50)
schedule_config["maxPrefillTokens"] = $MAX_PREFILL_TOKENS
# schedule_config["prefillTimeMsPerReq"] = schedule_config.get("prefillTimeMsPerReq", 150)
# schedule_config["prefillPolicyType"] = schedule_config.get("prefillPolicyType", 0)
# schedule_config["decodeTimeMsPerReq"] = schedule_config.get("decodeTimeMsPerReq", 50)
# schedule_config["decodePolicyType"] = schedule_config.get("decodePolicyType", 0)
# schedule_config["maxBatchSize"] = schedule_config.get("maxBatchSize", 200)
schedule_config["maxIterTimes"] = $MAX_ITER_TIMES
# schedule_config["maxPreemptCount"] = schedule_config.get("maxPreemptCount", 0)
# schedule_config["supportSelectBatch"] = schedule_config.get("supportSelectBatch", False)
# schedule_config["maxQueueDelayMicroseconds"] = schedule_config.get("maxQueueDelayMicroseconds", 5000)

# 设置ServerConfig（如果存在）
if "ServerConfig" not in config:
    config["ServerConfig"] = {}

service_config = config["ServerConfig"]
service_config["ipAddress"] = "$IP_ADDRESS"
service_config["port"] = $PORT
service_config["httpsEnabled"] = str("$HTTPS_ENABLED").lower() == "true"

# 确保目录存在
os.makedirs(os.path.dirname(config_file), exist_ok=True)

# 写入配置文件
with open(config_file, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)

# uid = pwd.getpwnam("root").pw_uid
# gid = grp.getgrnam("root").gr_gid
# os.chown(config_file, uid, gid)

# os.chmod(config_file, 0o640)

print(f"配置文件已更新: {config_file}")
EOF

    if [ $? -eq 0 ]; then
        log_info "config.json配置完成"
        log_info "配置文件路径: $CONFIG_FILE"
        
        # 显示配置摘要
        log_info "配置摘要:"
        docker exec -i "$CONTAINER_NAME" python3 <<EOF
import json
with open("$CONFIG_FILE", 'r') as f:
    config = json.load(f)
    print(f"  ipAddress: {config.get('ServerConfig', {}).get('ipAddress', 'N/A')}")
    print(f"  port: {config.get('ServerConfig', {}).get('port', 'N/A')}")
    print(f"  npuDeviceIds: {config.get('BackendConfig', {}).get('npuDeviceIds', 'N/A')}")
    print(f"  worldSize: {config.get('BackendConfig', {}).get('ModelDeployConfig', {}).get('ModelConfig', [{}])[0].get('worldSize', 'N/A')}")
    print(f"  modelName: {config.get('BackendConfig', {}).get('ModelDeployConfig', {}).get('ModelConfig', [{}])[0].get('modelName', 'N/A')}")
    print(f"  multiNodesInferEnabled: {config.get('BackendConfig', {}).get('multiNodesInferEnabled', 'N/A')}")
EOF
    else
        log_error "config.json配置失败"
        exit 1
    fi
}

# 步骤8: 配置容器内环境
configure_container() {
    log_info "步骤8: 配置容器内执行环境..."
    
    # log_info "进入容器并升级transformers..."
    # docker exec "$CONTAINER_NAME" pip install transformers==4.51.0 || log_warn "transformers升级失败"
    
    log_info "设置基础环境变量..."
    docker exec "$CONTAINER_NAME" bash -c "
        source /usr/local/Ascend/ascend-toolkit/set_env.sh
        source /usr/local/Ascend/nnal/atb/set_env.sh
        source /usr/local/Ascend/atb-models/set_env.sh
        source /usr/local/Ascend/mindie/set_env.sh
    " || log_warn "环境变量设置失败"
    
    log_info "配置通信环境变量..."
    docker exec "$CONTAINER_NAME" bash -c "
        export ATB_LLM_HCCL_ENABLE=1
        export ATB_LLM_COMM_BACKEND=\"hccl\"
        export HCCL_CONNECT_TIMEOUT=7200
        export HCCL_EXEC_TIMEOUT=0
        export WORLD_SIZE=$WORLD_SIZE
        export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
        export OMP_NUM_THREADS=1
        export NPU_MEMORY_FRACTION=0.98
        export RANK_TABLE_FILE=$RANK_TABLE_FILE
        export RANKTABLEFILE=$RANK_TABLE_FILE
        export HCCL_DETERMINISTIC=true
        export MIES_CONTAINER_IP=$LOCAL_SERVER_IP
    " || log_warn "通信环境变量配置失败"
    
    log_info "容器环境配置完成"
}

# 步骤9: 启动服务化
start_service() {
    log_info "步骤9: 启动MindIE服务化..."
    log_info "在所有机器上同时执行以下命令启动服务化..."
    log_info "日志文件: $LOG_NAME"

    touch /home/s_limingge/$LOG_NAME
    chmod 777 /home/s_limingge/$LOG_NAME
    
    docker exec -d "$CONTAINER_NAME" bash -c "
        source /usr/local/Ascend/ascend-toolkit/set_env.sh
        source /usr/local/Ascend/nnal/atb/set_env.sh
        source /usr/local/Ascend/atb-models/set_env.sh
        source /usr/local/Ascend/mindie/set_env.sh
        export ATB_LLM_HCCL_ENABLE=1
        export ATB_LLM_COMM_BACKEND=\"hccl\"
        export HCCL_CONNECT_TIMEOUT=7200
        export HCCL_EXEC_TIMEOUT=0
        export WORLD_SIZE=$WORLD_SIZE
        export PYTORCH_NPU_ALLOC_CONF=expandable_segments:True
        export OMP_NUM_THREADS=1
        export NPU_MEMORY_FRACTION=0.98
        export RANK_TABLE_FILE=$RANK_TABLE_FILE
        export RANKTABLEFILE=$RANK_TABLE_FILE
        export HCCL_DETERMINISTIC=true
        export MIES_CONTAINER_IP=$LOCAL_SERVER_IP
        # 设置库路径，确保能找到 libtorch.so 等依赖库
        export LD_LIBRARY_PATH=/usr/local/lib64/python3.11/site-packages/torch/lib:\$LD_LIBRARY_PATH
        # 验证 rank_table_file 是否存在且可读
        if [ ! -f \"\$RANK_TABLE_FILE\" ]; then
            echo \"ERROR: rank_table_file not found: \$RANK_TABLE_FILE\" > /home/s_limingge/$LOG_NAME
            exit 1
        fi
        if [ ! -r \"\$RANK_TABLE_FILE\" ]; then
            echo \"ERROR: rank_table_file not readable: \$RANK_TABLE_FILE\" > /home/s_limingge/$LOG_NAME
            exit 1
        fi
        # 确保文件权限正确（容器内以 root 运行）
        chmod 640 \"\$RANK_TABLE_FILE\" 2>/dev/null || true
        chown root:root \"\$RANK_TABLE_FILE\" 2>/dev/null || true
        cd /usr/local/Ascend/mindie/latest/mindie-service/
        nohup ./bin/mindieservice_daemon > /home/s_limingge/$LOG_NAME 2>&1 &
    "
    
    log_info "服务化已启动，等待服务就绪..."
    log_info "等待出现 'Daemon start success!' 表示服务启动成功"
}

########################################################################## Main ##########################################################################
# 获取模型权重路径
get_model_weight_path

# 显示配置信息
log_info "配置信息:"
log_info "  模型名称: $MODEL"
log_info "  模型路径: $MODEL_WEIGHT_PATH"
log_info "  Rank表文件: $RANK_TABLE_FILE"
log_info "  容器名称: $CONTAINER_NAME"
log_info "  Docker镜像: $DOCKER_IMAGE"
log_info "  节点数量: $SERVER_COUNT"
log_info "  当前节点IP: $LOCAL_SERVER_IP"
log_info "  MindIE版本: $VERSION"

docker pull swr.cn-south-1.myhuaweicloud.com/ascendhub/mindie:${VERSION}
if [ $? -ne 0 ]; then
    exit 1;
fi

ret=`docker ps -a | grep mindie_ascend_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}`
if [ $? -eq 0 ]; then
    docker stop mindie_ascend_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}
    docker rm mindie_ascend_<<<TEST_TYPE>>>_${SESSION_ID}_${JOB_COUNT}
fi

# 设置超时时间(单位:秒, 1小时 = 3600秒)
TIMEOUT=10
START_TIME=$(date +%s)

# 目标空闲 GPU 数量
if [ $GPU_QUANITY -eq 16 ]; then
    TARGET_FREE_GPUS=8
else
    TARGET_FREE_GPUS=$GPU_QUANITY
fi

# 检查必要命令
check_command docker
check_command hccn_tool

echo "开始扫描 GPU, 目标: 寻找 $TARGET_FREE_GPUS 张空闲 GPU..."

LOCKED_NPUS=""
while true; do
    # 检查是否超时
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ $ELAPSED_TIME -ge $TIMEOUT ]; then
        echo "超时（${TIMEOUT}秒）未找到 $TARGET_FREE_GPUS 张空闲 GPU, 退出"
        exit 10
    fi

    # 使用 npu-smi 获取 GPU 使用情况
    GPU_INFO=($(npu-smi info | grep "No\ running\ processes\ found\ in\ NPU" | awk '{print $8}'))
    # 检查空闲 GPU 数量
    FREE_COUNT=$(echo "${GPU_INFO[@]}" | wc -w)
    echo "当前空闲 GPU 数量：$FREE_COUNT, 索引: ${GPU_INFO[@]}"
    # 如果找到足够的空闲 GPU, 则返回结果并退出
    if [ "$FREE_COUNT" -ge "$TARGET_FREE_GPUS" ]; then
        echo "发现 $TARGET_FREE_GPUS 张空闲 GPU, 索引: ${GPU_INFO[@]}"
        echo "尝试锁定其中 $TARGET_FREE_GPUS 张 GPU"

        # 尝试原子性地获取所有NPU的锁
        if acquire_npu_locks_batch "$SERVER_NAME" "${GPU_INFO[*]}" "$TARGET_FREE_GPUS" "$TASK_ID" "$SESSION_ID" ACUQIRED_LOCKS; then
            echo "成功锁定 $TARGET_FREE_GPUS 张 GPU, 索引：${ACUQIRED_LOCKS[@]}"
            LOCKED_NPUS="${ACUQIRED_LOCKS[@]}"
            GPU_INFO=(${ACUQIRED_LOCKS[@]})
            break
        else
            echo "锁定失败（可能被其他任务占用），继续扫描......"
        fi
    fi

    # 等待一段时间后重新扫描（例如 10 秒）
    echo "未找到足够的空闲 GPU, 10秒后重试......"
    sleep 10
done

ASCEND_RT_VISIBLE_DEVICES=$(echo "${GPU_INFO[@]}" | sed -E 's/\s+/\,/g')
echo "ASCEND_RT_VISIBLE_DEVICES=$ASCEND_RT_VISIBLE_DEVICES"

# 执行部署步骤
# check_network
create_rank_table
generate_merged_rank_table
# fix_model_permissions
load_docker_image
start_container
create_service_config
# configure_container
start_service

TIMEOUT_SECONDS=$((60*30)) # 设置启动超时时间为30分钟
if [ $NODE_RANK -eq 0 ]; then
    timeout $TIMEOUT_SECONDS tail -F $LOG_NAME | grep --line-buffered -m 1 -E "Daemon start success!"
    EXIT_STATUS=$?
    if [ $EXIT_STATUS -eq 124 ]; then
        echo "模型启动超时（${TIMEOUT_SECONDS}秒）"
    elif [ $EXIT_STATUS -eq 0 ]; then
        echo ">>> Detected master service startup completion!"
    else
        echo "模型启动失败，退出状态码：$EXIT_STATUS"
    fi

    exit $EXIT_STATUS
else
    timeout $TIMEOUT_SECONDS tail -F $LOG_NAME | grep --line-buffered -m 8 -E "Daemon start success!"
    EXIT_STATUS=$?
    if [ $EXIT_STATUS -eq 124 ]; then
        echo "模型启动超时（${TIMEOUT_SECONDS}秒）"
    elif [ $EXIT_STATUS -eq 0 ]; then
        echo ">>> Detected slave $NODE_RANK service startup completion!"
    else
        echo "模型启动失败，退出状态码：$EXIT_STATUS"
    fi

    exit $EXIT_STATUS
fi
