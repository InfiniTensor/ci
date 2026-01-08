#!/bin/bash

# NPU锁管理工具 - 提供友好的命令行界面

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/npu_lock_manager.sh"

# 显示帮助信息
show_help() {
    cat << EOF
NPU锁管理工具
============

用法: $0 [命令] [参数...]

命令:
  status                    显示所有NPU锁的状态
  list                      列出所有锁（详细信息）
  check <server> <npu_id>   检查特定NPU的锁状态
  info <server> <npu_id>    显示特定NPU锁的详细信息
  
  unlock <server> <npu_id>  手动释放特定NPU的锁（谨慎使用）
  unlock-all                清理所有锁（非常危险！）
  cleanup-timeout           清理超时的锁
  
  watch                     实时监控NPU锁状态（每5秒刷新）
  stats                     显示锁统计信息
  
  help                      显示此帮助信息

示例:
  $0 status                   # 查看所有锁状态
  $0 check 10_9_1_74 0        # 检查服务器10.9.1.74的NPU 0
  $0 info 10_9_1_74 0         # 查看锁的详细信息
  $0 cleanup-timeout          # 清理超时的锁
  $0 watch                    # 实时监控

注意:
  - server参数应为IP地址（用下划线替代点），例如: 10_9_1_74
  - npu_id为NPU索引，例如: 0, 1, 2, ...
  - 手动释放锁前请确认任务已经结束，否则可能导致冲突
EOF
}

# 显示锁状态摘要
show_status() {
    echo "=========================================="
    echo "         NPU锁状态监控面板"
    echo "=========================================="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    local lock_count=0
    local timeout_count=0
    local current_time=$(date +%s)
    
    # 按服务器分组显示
    declare -A server_locks
    
    for lock_dir in "$LOCK_DIR"/*.lock; do
        if [ -d "$lock_dir" ] && [ -f "${lock_dir}/info" ]; then
            ((lock_count++))
            local basename=$(basename "$lock_dir" .lock)
            local server=$(echo "$basename" | sed -E 's/_npu_[0-9]+$//')
            local npu_id=$(echo "$basename" | grep -oE '[0-9]+$')
            
            # 读取锁信息
            local task_id=$(grep "^task_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            local timestamp=$(grep "^timestamp=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            local session_id=$(grep "^session_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            local hostname=$(grep "^hostname=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            
            # 计算持续时间
            local duration="未知"
            local status="🟢 正常"
            if [ ! -z "$timestamp" ]; then
                local elapsed=$((current_time - timestamp))
                local hours=$((elapsed / 3600))
                local minutes=$(((elapsed % 3600) / 60))
                local seconds=$((elapsed % 60))
                duration="${hours}h ${minutes}m ${seconds}s"
                
                # 检查是否超时
                if [ $ENABLE_TIMEOUT_CHECK -eq 1 ] && [ $elapsed -ge $LOCK_TIMEOUT ]; then
                    status="🔴 超时"
                    ((timeout_count++))
                fi
            fi
            
            server_locks["$server"]+="  NPU $npu_id | $status | 持续: $duration | 任务: $task_id | 主机: $hostname | Session: $session_id\n"
        fi
    done
    
    # 显示统计信息
    echo "📊 统计信息:"
    echo "  总锁数量: $lock_count"
    if [ $ENABLE_TIMEOUT_CHECK -eq 1 ]; then
        echo "  超时锁数: $timeout_count"
    fi
    echo ""
    
    if [ $lock_count -eq 0 ]; then
        echo "✅ 当前没有NPU被锁定"
        echo ""
        return
    fi
    
    # 按服务器显示锁信息
    echo "📍 锁详情 (按服务器分组):"
    echo ""
    for server in "${!server_locks[@]}"; do
        local server_ip=$(echo "$server" | sed 's/_/\./g')
        echo "服务器: $server_ip"
        echo -e "${server_locks[$server]}"
    done
    
    if [ $ENABLE_TIMEOUT_CHECK -eq 1 ] && [ $timeout_count -gt 0 ]; then
        echo ""
        echo "⚠️  警告: 发现 $timeout_count 个超时锁，建议执行: $0 cleanup-timeout"
    fi
    
    echo "=========================================="
}

# 显示统计信息
show_stats() {
    echo "=========================================="
    echo "         NPU锁统计信息"
    echo "=========================================="
    
    local total_locks=0
    local timeout_locks=0
    local current_time=$(date +%s)
    
    declare -A task_type_count
    declare -A server_count
    
    for lock_dir in "$LOCK_DIR"/*.lock; do
        if [ -d "$lock_dir" ] && [ -f "${lock_dir}/info" ]; then
            ((total_locks++))
            
            local basename=$(basename "$lock_dir" .lock)
            local server=$(echo "$basename" | sed -E 's/_npu_[0-9]+$//')
            
            # 统计服务器锁数量
            ((server_count[$server]++))
            
            # 读取任务类型
            local task_id=$(grep "^task_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            local task_type=$(echo "$task_id" | cut -d_ -f1)
            ((task_type_count[$task_type]++))
            
            # 检查超时
            if [ $ENABLE_TIMEOUT_CHECK -eq 1 ]; then
                local timestamp=$(grep "^timestamp=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
                if [ ! -z "$timestamp" ]; then
                    local elapsed=$((current_time - timestamp))
                    if [ $elapsed -ge $LOCK_TIMEOUT ]; then
                        ((timeout_locks++))
                    fi
                fi
            fi
        fi
    done
    
    echo "总锁数量: $total_locks"
    if [ $ENABLE_TIMEOUT_CHECK -eq 1 ]; then
        echo "超时锁数: $timeout_locks"
    fi
    echo ""
    
    if [ $total_locks -gt 0 ]; then
        echo "按任务类型分布:"
        for task_type in "${!task_type_count[@]}"; do
            echo "  $task_type: ${task_type_count[$task_type]}"
        done
        echo ""
        
        echo "按服务器分布:"
        for server in "${!server_count[@]}"; do
            local server_ip=$(echo "$server" | sed 's/_/\./g')
            echo "  $server_ip: ${server_count[$server]}"
        done
    fi
    
    echo "=========================================="
}

# 实时监控
watch_status() {
    echo "开始实时监控NPU锁状态（按Ctrl+C退出）..."
    echo ""
    
    while true; do
        clear
        show_status
        sleep 5
    done
}

# 主函数
main() {
    local command=${1:-help}
    shift
    
    case "$command" in
        status)
            show_status
            ;;
        list)
            list_all_locks
            ;;
        check)
            if [ $# -lt 2 ]; then
                echo "错误: 缺少参数"
                echo "用法: $0 check <server> <npu_id>"
                exit 1
            fi
            if check_npu_lock "$1" "$2"; then
                echo "✅ NPU $2 @ $1 当前未被锁定"
            else
                echo "🔒 NPU $2 @ $1 当前已被锁定"
                echo ""
                get_lock_info "$1" "$2"
            fi
            ;;
        info)
            if [ $# -lt 2 ]; then
                echo "错误: 缺少参数"
                echo "用法: $0 info <server> <npu_id>"
                exit 1
            fi
            get_lock_info "$1" "$2"
            ;;
        unlock)
            if [ $# -lt 2 ]; then
                echo "错误: 缺少参数"
                echo "用法: $0 unlock <server> <npu_id>"
                exit 1
            fi
            echo "警告: 即将手动释放 NPU $2 @ $1 的锁"
            read -p "确认操作？(yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                release_npu_lock "$1" "$2" ""
                echo "✅ 锁已释放"
            else
                echo "❌ 操作已取消"
            fi
            ;;
        unlock-all)
            echo "⚠️  危险操作: 即将清理所有NPU锁！"
            echo "这可能导致正在运行的任务出现问题！"
            read -p "确认操作？输入 'YES' 继续: " confirm
            if [ "$confirm" = "YES" ]; then
                cleanup_all_locks
            else
                echo "❌ 操作已取消"
            fi
            ;;
        cleanup-timeout)
            cleanup_timeout_locks
            ;;
        watch)
            watch_status
            ;;
        stats)
            show_stats
            ;;
        help)
            show_help
            ;;
        *)
            echo "错误: 未知命令 '$command'"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"

