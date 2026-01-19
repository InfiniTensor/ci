#!/bin/bash

# NPU锁管理器
# 用于在分布式环境中管理NPU资源的互斥访问

# 锁文件存储目录（使用共享目录，确保所有服务器都能访问）
LOCK_DIR="/home/s_limingge/.npu_locks"

# 创建锁目录（如果不存在）
mkdir -p "$LOCK_DIR"

# 锁的超时时间（秒）- 防止死锁
LOCK_TIMEOUT=86400  # 24小时

# 是否启用超时检查(0: 不启用, 1: 启用)，默认不启用
ENABLE_TIMEOUT_CHECK=0

# 生成锁目录名（使用目录而不是文件）
# 参数: $1=服务器名或IP, $2=NPU索引
get_lock_file() {
    local server=$1
    local npu_id=$2
    echo "${LOCK_DIR}/${server}_npu_${npu_id}.lock"
}

# 尝试获取NPU锁
# 参数: $1=服务器名或IP, $2=NPU索引, $3=任务ID（用于标识哪个任务持有锁）, $4=SessionID
# 返回: 0=成功获取锁, 1=锁已被占用
acquire_npu_lock() {
    local server=$1
    local npu_id=$2
    local task_id=$3
    local session_id=$4
    local lock_dir=$(get_lock_file "$server" "$npu_id")
    
    # 使用 mkdir 的原子性来创建锁目录
    # mkdir 失败说明目录已存在（被其他进程锁定）
    if mkdir "$lock_dir" 2>/dev/null; then
        # 成功创建锁目录，写入锁信息
        cat > "${lock_dir}/info" << EOF
task_id=$task_id
timestamp=$(date +%s)
session_id=$session_id
hostname=$(hostname)
EOF
        return 0
    else
        # 如果task_id相同，则复用已经存在的锁
        if [ ! -z "$task_id" ] && [ -d "$lock_dir" ] && [ -f "${lock_dir}/info" ]; then
            local lock_task_id=$(grep "^task_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            local lock_session_id=$(grep "^session_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            if [ "$lock_task_id" == "$task_id" ] && [ "$lock_session_id" == "$session_id" ]; then
                echo "锁已存在，复用锁: ${server} NPU ${npu_id}, ${lock_task_id} == ${task_id}, ${lock_session_id} == ${session_id}" >&2
                return 0
            fi
        fi

        # 锁已被占用，检查是否超时
        if [ $ENABLE_TIMEOUT_CHECK -eq 1 ] && [ -d "$lock_dir" ] && [ -f "${lock_dir}/info" ]; then
            local lock_timestamp=$(grep "^timestamp=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            if [ ! -z "$lock_timestamp" ]; then
                local current_time=$(date +%s)
                local elapsed=$((current_time - lock_timestamp))
                
                # 如果锁超时，强制释放并重新获取
                if [ $elapsed -ge $LOCK_TIMEOUT ]; then
                    echo "警告: NPU锁超时 (${server} NPU ${npu_id}), 强制释放" >&2
                    rm -rf "$lock_dir"
                    # 递归调用重新获取锁
                    acquire_npu_lock "$server" "$npu_id" "$task_id" "$session_id"
                    return $?
                fi
            fi
        fi

        return 1
    fi
}

# 批量获取NPU锁（原子操作 - 要么全部成功，要么全部失败）
# 参数: $1=服务器名或IP, $2=NPU索引列表（空格分隔）, $3=任务ID, $4=SessionID
# 返回: 0=成功, 1=失败
acquire_npu_locks_batch() {
    local server=$1
    local npu_list=$2
    local task_id=$3
    local session_id=$4

    local acquired_locks=()
    local all_success=true
    
    # 尝试获取所有锁
    for npu_id in $npu_list; do
        if acquire_npu_lock "$server" "$npu_id" "$task_id" "$session_id"; then
            acquired_locks+=("$npu_id")
        else
            all_success=false
            break
        fi
    done
    
    # 如果没有全部成功，释放已获取的锁
    if [ "$all_success" = false ]; then
        for npu_id in "${acquired_locks[@]}"; do
            release_npu_lock "$server" "$npu_id" "$task_id" "$session_id"
        done
        return 1
    fi
    
    return 0
}

# 释放NPU锁
# 参数: $1=服务器名或IP, $2=NPU索引, $3=任务ID（可选，用于验证）, $4=SessionID
release_npu_lock() {
    local server=$1
    local npu_id=$2
    local task_id=$3
    local session_id=$4
    local lock_dir=$(get_lock_file "$server" "$npu_id")
    
    # 如果提供了task_id，验证锁是否属于当前任务
    if [ ! -z "$task_id" ] && [ -d "$lock_dir" ] && [ -f "${lock_dir}/info" ]; then
        local lock_task_id=$(grep "^task_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
        local lock_session_id=$(grep "^session_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
        if [ "$lock_task_id" != "$task_id" ] || [ "$lock_session_id" != "$session_id" ]; then
            echo "警告: 尝试释放不属于当前任务的锁 (${server} NPU ${npu_id}), ${lock_task_id} != ${task_id}" >&2
            return 1
        fi
    fi
    
    # 删除锁目录即可释放锁
    rm -rf "$lock_dir"
    return 0
}

# 批量释放NPU锁
# 参数: $1=服务器名或IP, $2=NPU索引列表（空格分隔）, $3=任务ID，$4=SessionID
release_npu_locks_batch() {
    local server=$1
    local npu_list=$2
    local task_id=$3
    local session_id=$4
    
    for npu_id in $npu_list; do
        release_npu_lock "$server" "$npu_id" "$task_id" "$session_id"
    done
}

# 检查NPU锁状态
# 参数: $1=服务器名或IP, $2=NPU索引, $3=任务ID $4=SessionID
# 返回: 0=锁空闲, 1=锁被占用
check_npu_lock() {
    local server=$1
    local npu_id=$2
    local task_id=$3
    local session_id=$4
    local lock_dir=$(get_lock_file "$server" "$npu_id")
    
    # 简单检查目录是否存在
    if [ ! -d "$lock_dir" ]; then
        # 锁目录不存在，说明未被锁定
        return 0
    else
        # 如果task_id相同，则复用已经存在的锁
        if [ ! -z "$task_id" ] && [ -d "$lock_dir" ] && [ -f "${lock_dir}/info" ]; then
            local lock_task_id=$(grep "^task_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            local lock_session_id=$(grep "^session_id=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            if [ "$lock_task_id" == "$task_id" ] && [ "$lock_session_id" == "$session_id" ]; then
                echo "锁已存在，可以复用锁: ${server} NPU ${npu_id}, ${lock_task_id} == ${task_id}, ${lock_session_id} == ${session_id}" >&2
                return 0
            fi
        fi

        # 检查锁是否超时
        if [ $ENABLE_TIMEOUT_CHECK -eq 1 ] && [ -f "${lock_dir}/info" ]; then
            local lock_timestamp=$(grep "^timestamp=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
            if [ ! -z "$lock_timestamp" ]; then
                local current_time=$(date +%s)
                local elapsed=$((current_time - lock_timestamp))
                if [ $elapsed -ge $LOCK_TIMEOUT ]; then
                    # 超时，视为空闲
                    return 0
                fi
            fi
        fi

        # 锁被占用且未超时
        return 1
    fi
}

# 批量检查NPU锁
# 参数: $1=服务器名或IP, $2=NPU索引列表（空格分隔）, $3=任务ID, $4=SessionID
check_npu_locks_batch() {
    local server=$1
    local npu_list=$2
    local task_id=$3
    local session_id=$4
    local -n npu_list_found=$5     # 传名引用
    
    npu_list_found=()
    for npu_id in $npu_list; do
        if check_npu_lock "$server" "$npu_id" "$task_id" "$session_id"; then
            npu_list_found+=("$npu_id")
        fi
    done

    return 0
}

# 获取锁信息
# 参数: $1=服务器名或IP, $2=NPU索引
get_lock_info() {
    local server=$1
    local npu_id=$2
    local lock_dir=$(get_lock_file "$server" "$npu_id")
    
    if [ -d "$lock_dir" ] && [ -f "${lock_dir}/info" ]; then
        cat "${lock_dir}/info"
    else
        echo "Lock not found"
        return 1
    fi
}

# 列出所有锁
list_all_locks() {
    echo "=== 所有NPU锁状态 ==="
    for lock_dir in "$LOCK_DIR"/*.lock; do
        if [ -d "$lock_dir" ]; then
            local basename=$(basename "$lock_dir")
            echo "锁目录: $basename"
            if [ -f "${lock_dir}/info" ]; then
                cat "${lock_dir}/info"
            else
                echo "信息文件不存在"
            fi
            echo "---"
        fi
    done
}

# 清理所有锁（谨慎使用！）
cleanup_all_locks() {
    echo "警告: 正在清理所有NPU锁..."
    rm -rf "$LOCK_DIR"/*.lock
    echo "所有锁已清理完成"
}

# 清理超时的锁
cleanup_timeout_locks() {
    local current_time=$(date +%s)
    local cleaned_count=0
    
    if [ $ENABLE_TIMEOUT_CHECK -eq 0 ]; then
        echo "超时检查未启用, 跳过清理超时锁"
        return
    fi

    for lock_dir in "$LOCK_DIR"/*.lock; do
        if [ -d "$lock_dir" ]; then
            if [ -f "${lock_dir}/info" ]; then
                local lock_timestamp=$(grep "^timestamp=" "${lock_dir}/info" 2>/dev/null | cut -d= -f2)
                if [ ! -z "$lock_timestamp" ]; then
                    local elapsed=$((current_time - lock_timestamp))
                    if [ $elapsed -ge $LOCK_TIMEOUT ]; then
                        echo "清理超时锁: $(basename "$lock_dir") (超时 ${elapsed} 秒)"
                        rm -rf "$lock_dir"
                        ((cleaned_count++))
                    fi
                fi
            fi
        fi
    done
    
    echo "清理了 $cleaned_count 个超时锁"
}

# 主函数 - 用于命令行调用
main() {
    local command=$1
    shift
    
    case "$command" in
        acquire)
            if [ $# -lt 3 ]; then
                echo "用法: $0 acquire <server> <npu_id> <task_id> <session_id>"
                exit 1
            fi
            acquire_npu_lock "$1" "$2" "$3" "$4"
            ;;
        acquire_batch)
            if [ $# -lt 3 ]; then
                echo "用法: $0 acquire_batch <server> '<npu_list>' <task_id> <session_id>"
                exit 1
            fi
            acquire_npu_locks_batch "$1" "$2" "$3" "$4"
            ;;
        release)
            if [ $# -lt 2 ]; then
                echo "用法: $0 release <server> <npu_id> <task_id> <session_id>"
                exit 1
            fi
            release_npu_lock "$1" "$2" "$3" "$4"
            ;;
        release_batch)
            if [ $# -lt 3 ]; then
                echo "用法: $0 release_batch <server> '<npu_list>' <task_id> <session_id>"
                exit 1
            fi
            release_npu_locks_batch "$1" "$2" "$3" "$4"
            ;;
        check)
            if [ $# -lt 2 ]; then
                echo "用法: $0 check <server> <npu_id>"
                exit 1
            fi
            check_npu_lock "$1" "$2"
            ;;
        info)
            if [ $# -lt 2 ]; then
                echo "用法: $0 info <server> <npu_id>"
                exit 1
            fi
            get_lock_info "$1" "$2"
            ;;
        list)
            list_all_locks
            ;;
        cleanup_all)
            cleanup_all_locks
            ;;
        cleanup_timeout)
            cleanup_timeout_locks
            ;;
        *)
            echo "用法: $0 {acquire|acquire_batch|release|release_batch|check|info|list|cleanup_all|cleanup_timeout} [args...]"
            exit 1
            ;;
    esac
}

# 如果直接执行此脚本（而非source）
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi

