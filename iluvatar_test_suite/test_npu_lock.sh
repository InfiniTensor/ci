#!/bin/bash

# NPU锁机制测试脚本

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/npu_lock_manager.sh"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试结果函数
test_passed() {
    ((TOTAL_TESTS++))
    ((PASSED_TESTS++))
    echo -e "${GREEN}✓ PASSED${NC}: $1"
}

test_failed() {
    ((TOTAL_TESTS++))
    ((FAILED_TESTS++))
    echo -e "${RED}✗ FAILED${NC}: $1"
}

test_info() {
    echo -e "${YELLOW}ℹ INFO${NC}: $1"
}

# 清理测试环境
cleanup_test_env() {
    echo "清理测试环境..."
    rm -rf "${LOCK_DIR}/test_*"
}

echo "=========================================="
echo "       NPU锁机制自动化测试"
echo "=========================================="
echo ""

# 测试1: 获取单个锁
echo "测试1: 获取单个锁"
cleanup_test_env
if acquire_npu_lock "test_server" "0" "test_task_1"; then
    test_passed "成功获取单个NPU锁"
else
    test_failed "无法获取单个NPU锁"
fi
release_npu_lock "test_server" "0" "test_task_1"
echo ""

# 测试2: 重复获取同一个锁（应该失败）
echo "测试2: 重复获取同一个锁（应该失败）"
cleanup_test_env
acquire_npu_lock "test_server" "0" "test_task_1" > /dev/null 2>&1
if ! acquire_npu_lock "test_server" "0" "test_task_2" 2>/dev/null; then
    test_passed "正确阻止了重复锁定"
else
    test_failed "重复锁定应该失败但成功了"
fi
release_npu_lock "test_server" "0" "test_task_1"
echo ""

# 测试3: 批量获取锁
echo "测试3: 批量获取多个NPU锁"
cleanup_test_env
if acquire_npu_locks_batch "test_server" "0 1 2 3" "test_task_3"; then
    test_passed "成功批量获取4个NPU锁"
else
    test_failed "批量获取NPU锁失败"
fi
release_npu_locks_batch "test_server" "0 1 2 3" "test_task_3"
echo ""

# 测试4: 批量获取锁的原子性（部分冲突应全部失败）
echo "测试4: 批量锁定的原子性测试"
cleanup_test_env
# 先锁定NPU 1
acquire_npu_lock "test_server" "1" "test_task_4a" > /dev/null 2>&1
# 尝试批量锁定 0,1,2,3（由于1已被锁定，应该全部失败）
if ! acquire_npu_locks_batch "test_server" "0 1 2 3" "test_task_4b" 2>/dev/null; then
    # 验证NPU 0,2,3没有被锁定（原子性保证）
    if check_npu_lock "test_server" "0" && check_npu_lock "test_server" "2" && check_npu_lock "test_server" "3"; then
        test_passed "原子性测试通过：部分冲突时全部回滚"
    else
        test_failed "原子性失败：部分NPU被错误锁定"
    fi
else
    test_failed "批量锁定应该失败但成功了"
fi
release_npu_lock "test_server" "1" "test_task_4a"
echo ""

# 测试5: 锁的释放
echo "测试5: 锁的释放"
cleanup_test_env
acquire_npu_lock "test_server" "0" "test_task_5" > /dev/null 2>&1
release_npu_lock "test_server" "0" "test_task_5"
if check_npu_lock "test_server" "0"; then
    test_passed "锁已成功释放"
else
    test_failed "锁释放失败"
fi
echo ""

# 测试6: 检查锁状态
echo "测试6: 检查锁状态"
cleanup_test_env
if check_npu_lock "test_server" "0"; then
    test_passed "正确检测到未锁定状态"
else
    test_failed "锁状态检查错误"
fi
acquire_npu_lock "test_server" "0" "test_task_6" > /dev/null 2>&1
if ! check_npu_lock "test_server" "0"; then
    test_passed "正确检测到已锁定状态"
else
    test_failed "锁状态检查错误"
fi
release_npu_lock "test_server" "0" "test_task_6"
echo ""

# 测试7: 获取锁信息
echo "测试7: 获取锁信息"
cleanup_test_env
acquire_npu_lock "test_server" "0" "test_task_7" > /dev/null 2>&1
lock_info=$(get_lock_info "test_server" "0")
if echo "$lock_info" | grep -q "task_id=test_task_7"; then
    test_passed "锁信息正确包含任务ID"
else
    test_failed "锁信息不完整或错误"
fi
release_npu_lock "test_server" "0" "test_task_7"
echo ""

# 测试8: 并发锁定测试（模拟竞争条件）
echo "测试8: 并发锁定测试（模拟两个任务同时抢占）"
cleanup_test_env
test_info "启动两个并发进程尝试锁定同一个NPU..."

# 启动两个后台进程竞争锁定
(
    if acquire_npu_lock "test_server" "0" "concurrent_task_1" 2>/dev/null; then
        echo "TASK1_SUCCESS" > /tmp/npu_lock_test_result_1
        sleep 0.5
        release_npu_lock "test_server" "0" "concurrent_task_1"
    else
        echo "TASK1_FAILED" > /tmp/npu_lock_test_result_1
    fi
) &

(
    sleep 0.1  # 稍微延迟，确保第一个任务先执行
    if acquire_npu_lock "test_server" "0" "concurrent_task_2" 2>/dev/null; then
        echo "TASK2_SUCCESS" > /tmp/npu_lock_test_result_2
        sleep 0.5
        release_npu_lock "test_server" "0" "concurrent_task_2"
    else
        echo "TASK2_FAILED" > /tmp/npu_lock_test_result_2
    fi
) &

wait

# 检查结果
result1=$(cat /tmp/npu_lock_test_result_1 2>/dev/null)
result2=$(cat /tmp/npu_lock_test_result_2 2>/dev/null)

if [ "$result1" = "TASK1_SUCCESS" ] && [ "$result2" = "TASK2_FAILED" ]; then
    test_passed "并发锁定测试通过：正确处理竞争条件"
elif [ "$result1" = "TASK1_FAILED" ] && [ "$result2" = "TASK2_SUCCESS" ]; then
    test_passed "并发锁定测试通过：正确处理竞争条件"
else
    test_failed "并发锁定测试失败：$result1, $result2"
fi

rm -f /tmp/npu_lock_test_result_*
echo ""

# 测试9: 批量释放
echo "测试9: 批量释放多个NPU锁"
cleanup_test_env
acquire_npu_locks_batch "test_server" "0 1 2" "test_task_9" > /dev/null 2>&1
release_npu_locks_batch "test_server" "0 1 2" "test_task_9"
if check_npu_lock "test_server" "0" && check_npu_lock "test_server" "1" && check_npu_lock "test_server" "2"; then
    test_passed "批量释放成功"
else
    test_failed "批量释放失败"
fi
echo ""

# 测试10: 任务ID验证（防止错误释放其他任务的锁）
echo "测试10: 任务ID验证机制"
cleanup_test_env
acquire_npu_lock "test_server" "0" "test_task_10a" > /dev/null 2>&1
# 尝试用错误的任务ID释放锁
if ! release_npu_lock "test_server" "0" "test_task_10b" 2>/dev/null; then
    # 验证锁仍然存在
    if ! check_npu_lock "test_server" "0"; then
        test_passed "任务ID验证成功：防止错误释放"
    else
        test_failed "任务ID验证失败：锁被错误释放"
    fi
else
    # 某些版本可能允许释放，检查锁是否还在
    if ! check_npu_lock "test_server" "0"; then
        test_info "任务ID验证：警告但允许释放"
        ((TOTAL_TESTS++))
        ((PASSED_TESTS++))
    else
        test_failed "任务ID验证异常"
    fi
fi
release_npu_lock "test_server" "0" "test_task_10a"
echo ""

# 清理测试环境
cleanup_test_env

# 显示测试总结
echo "=========================================="
echo "           测试总结"
echo "=========================================="
echo "总测试数: $TOTAL_TESTS"
echo -e "通过: ${GREEN}$PASSED_TESTS${NC}"
echo -e "失败: ${RED}$FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ 所有测试通过！NPU锁机制工作正常。${NC}"
    exit 0
else
    echo -e "${RED}✗ 部分测试失败，请检查日志。${NC}"
    exit 1
fi

