#!/bin/bash

# 这是一个测试脚本，演示如何在主进程被终止时自动清理所有子进程

# 存储所有子进程PID
declare -a child_pids=()

# 清理函数：终止所有子进程
cleanup() {
    echo ""
    echo "=== 接收到终止信号，正在清理所有子进程 ==="
    
    # 显示要清理的子进程
    echo "子进程列表: ${child_pids[@]}"
    
    # 方法1：kill所有记录的子进程
    for pid in "${child_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "终止子进程: $pid"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    
    # 方法2：kill当前进程组的所有进程
    kill 0 2>/dev/null || true
    
    # 等待进程优雅退出
    sleep 2
    
    # 强制kill仍然存活的子进程
    for pid in "${child_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "强制终止子进程: $pid"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    
    echo "=== 清理完成 ==="
    exit 0
}

# 捕获各种终止信号
trap cleanup SIGINT SIGTERM SIGHUP EXIT

echo "主进程PID: $$"
echo "启动多个子进程进行测试..."
echo "按 Ctrl+C 终止主进程并观察子进程清理过程"
echo ""

# 启动几个模拟的子进程
for i in {1..5}; do
    (
        echo "子进程 $i (PID: $$) 已启动"
        # 模拟长时间运行的任务
        while true; do
            sleep 5
            echo "子进程 $i (PID: $$) 正在运行..."
        done
    ) &
    child_pids+=($!)
    echo "已启动子进程 $i, PID: ${child_pids[-1]}"
done

echo ""
echo "所有子进程已启动: ${child_pids[@]}"
echo "主进程等待中... (按 Ctrl+C 测试清理功能)"

# 主进程等待
wait

echo "所有子进程已完成"

