#!/bin/bash

# NPU锁机制演示脚本

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/npu_lock_manager.sh"

echo "=========================================="
echo "      NPU锁机制演示"
echo "=========================================="
echo ""

# 模拟任务信息
TASK_ID="Demo_Task_$$"
SERVER_NAME="demo_server"
NPU_LIST="0 1 2 3"

echo "步骤1: 尝试锁定NPU"
echo "  任务ID: $TASK_ID"
echo "  服务器: $SERVER_NAME"
echo "  需要的NPU: $NPU_LIST"
echo ""

# 设置清理函数
cleanup_locks() {
    if [ ! -z "$LOCKED_NPUS" ]; then
        echo ""
        echo "清理: 释放NPU锁..."
        release_npu_locks_batch "$SERVER_NAME" "$LOCKED_NPUS" "$TASK_ID"
        echo "✅ 锁已释放"
    fi
}
trap cleanup_locks EXIT INT TERM

# 尝试获取锁
LOCKED_NPUS=""
if acquire_npu_locks_batch "$SERVER_NAME" "$NPU_LIST" "$TASK_ID"; then
    LOCKED_NPUS="$NPU_LIST"
    echo "✅ 成功锁定所有NPU!"
    echo ""
    
    echo "步骤2: 查看当前锁状态"
    echo ""
    ./npu_lock_admin.sh status
    echo ""
    
    echo "步骤3: 模拟任务执行"
    echo "  正在使用NPU执行任务..."
    for i in {5..1}; do
        echo "  剩余 $i 秒..."
        sleep 1
    done
    echo "  任务执行完成"
    echo ""
    
    echo "步骤4: 查看锁的详细信息"
    for npu_id in 0 1; do
        echo "  NPU $npu_id 的锁信息:"
        get_lock_info "$SERVER_NAME" "$npu_id" | sed 's/^/    /'
    done
    echo ""
    
else
    echo "❌ 无法获取NPU锁（可能被其他任务占用）"
    exit 1
fi

echo "步骤5: 锁将在脚本退出时自动释放（通过trap）"
echo ""
echo "=========================================="
echo "       演示完成"
echo "=========================================="

