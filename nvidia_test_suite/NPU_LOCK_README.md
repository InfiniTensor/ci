# Ascend NPU 资源锁定机制使用说明

## 概述

为了解决多个测试任务在Ascend NPU集群上并行运行时的资源争抢问题，我们实现了一个分布式NPU锁定机制。该机制可以确保一旦任务扫描到空闲NPU后，立即进行原子性锁定，防止其他任务争抢相同的NPU资源。

## 核心特性

✅ **原子性锁定**: 使用`flock`实现文件级互斥锁，确保同一NPU不会被多个任务同时占用  
✅ **批量锁定**: 支持原子性地锁定多个NPU（要么全部成功，要么全部失败）  
✅ **自动释放**: 任务结束时自动释放锁（包括异常退出、Ctrl+C等情况）  
✅ **超时保护**: 防止死锁，超时的锁会被自动清理  
✅ **集群支持**: 通过共享文件系统支持跨服务器的锁管理  
✅ **可视化监控**: 提供友好的命令行管理工具

## 文件说明

```
npu_lock_manager.sh    - 核心锁管理库（提供锁定/释放API）
npu_lock_admin.sh      - 管理工具（用于监控和维护锁状态）
job_executor_*Test.sh  - 已集成锁机制的任务执行脚本
```

## 工作原理

### 1. 锁定流程

```bash
任务启动
    ↓
扫描空闲NPU
    ↓
发现满足条件的NPU
    ↓
尝试原子性锁定所有需要的NPU
    ↓
锁定成功？
    ├─ 是 → 执行任务 → 任务结束 → 自动释放锁
    └─ 否 → 继续扫描（其他任务已占用）
```

### 2. 锁文件位置

锁文件存储在: `/home/s_limingge/.npu_locks/`

格式: `<server_ip>_npu_<npu_id>.lock`

例如: `10_9_1_74_npu_0.lock`

### 3. 锁信息内容

每个锁文件包含以下信息：
```
task_id=SmokeTest_DeepSeek-R1_0_12345
timestamp=1697456789
pid=12345
hostname=aicc003
```

## 使用方法

### 自动使用（推荐）

锁机制已经集成到 `job_executor_for_SmokeTest.sh` 和 `job_executor_for_PerformanceTest.sh` 中，无需手动操作。

只需正常启动测试任务即可：

```bash
bash ascend_resource_monitor.sh Smoke SigInfer
bash ascend_resource_monitor.sh Performance SigInfer Random
```

### 监控锁状态

查看当前所有锁的状态：

```bash
./npu_lock_admin.sh status
```

输出示例：
```
==========================================
         NPU锁状态监控面板
==========================================
时间: 2025-10-16 14:23:45

📊 统计信息:
  总锁数量: 3
  超时锁数: 0

📍 锁详情 (按服务器分组):

服务器: 10.9.1.74
  NPU 0 | 🟢 正常 | 持续: 0h 5m 32s | 任务: SmokeTest_DeepSeek-R1_0_12345 | 主机: aicc003
  NPU 1 | 🟢 正常 | 持续: 0h 5m 32s | 任务: SmokeTest_DeepSeek-R1_0_12345 | 主机: aicc003

服务器: 10.9.1.34
  NPU 0 | 🟢 正常 | 持续: 0h 3m 15s | 任务: PerformanceTest_Qwen2.5_1_23456 | 主机: aicc004
==========================================
```

### 实时监控

实时监控锁状态（每5秒刷新）：

```bash
./npu_lock_admin.sh watch
```

按 `Ctrl+C` 退出监控

### 查看统计信息

```bash
./npu_lock_admin.sh stats
```

输出示例：
```
==========================================
         NPU锁统计信息
==========================================
总锁数量: 5
超时锁数: 0

按任务类型分布:
  SmokeTest: 3
  PerformanceTest: 2

按服务器分布:
  10.9.1.74: 2
  10.9.1.34: 2
  10.9.1.26: 1
==========================================
```

### 检查特定NPU

检查某个NPU是否被锁定：

```bash
./npu_lock_admin.sh check 10_9_1_74 0
```

查看特定NPU锁的详细信息：

```bash
./npu_lock_admin.sh info 10_9_1_74 0
```

### 维护操作

#### 清理超时的锁

如果发现有超时的锁（默认2小时），可以清理它们：

```bash
./npu_lock_admin.sh cleanup-timeout
```

#### 手动释放特定锁（谨慎使用）

如果确认某个任务已经异常结束但锁未释放，可以手动释放：

```bash
./npu_lock_admin.sh unlock 10_9_1_74 0
```

⚠️ **警告**: 只在确认任务已经结束时使用，否则可能导致资源冲突！

#### 清理所有锁（非常危险）

```bash
./npu_lock_admin.sh unlock-all
```

⚠️ **危险操作**: 这会清理所有锁，可能影响正在运行的任务！

### 查看帮助

```bash
./npu_lock_admin.sh help
```

## 配置参数

可在 `npu_lock_manager.sh` 中修改以下参数：

```bash
LOCK_DIR="/home/s_limingge/.npu_locks"  # 锁文件目录
LOCK_TIMEOUT=7200                       # 锁超时时间（秒）
```

## 故障排查

### 问题1: 锁一直无法获取

**现象**: 任务一直提示"锁定失败（可能被其他任务占用），继续扫描..."

**排查步骤**:
1. 检查锁状态: `./npu_lock_admin.sh status`
2. 查看是否有超时锁: 如有，执行 `./npu_lock_admin.sh cleanup-timeout`
3. 确认NPU是否真的在使用: 登录服务器执行 `npu-smi info`

### 问题2: 任务结束后锁未释放

**现象**: 任务已经结束，但锁文件仍然存在

**可能原因**: 
- 任务被强制kill（kill -9）
- 系统崩溃

**解决方法**:
1. 确认任务确实已结束
2. 手动释放锁: `./npu_lock_admin.sh unlock <server> <npu_id>`

### 问题3: 权限问题

**现象**: 无法创建或删除锁文件

**解决方法**:
```bash
# 确保锁目录存在且有正确权限
mkdir -p /home/s_limingge/.npu_locks
chmod 755 /home/s_limingge/.npu_locks

# 确保脚本有执行权限
chmod +x npu_lock_manager.sh
chmod +x npu_lock_admin.sh
```

### 问题4: 锁目录不共享

**现象**: 在不同服务器上看到的锁状态不一致

**原因**: 锁目录必须在共享文件系统上（如NFS、GlusterFS等）

**解决方法**:
- 确保 `/home/s_limingge/` 在所有服务器间共享
- 或修改 `LOCK_DIR` 指向共享目录

## 集成到其他脚本

如果需要在其他脚本中使用锁机制：

```bash
#!/bin/bash

# 导入锁管理器
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_DIR}/npu_lock_manager.sh"

# 生成任务ID
TASK_ID="MyTask_$$"
SERVER_NAME="10_9_1_74"

# 设置清理函数
cleanup_locks() {
    if [ ! -z "$LOCKED_NPUS" ]; then
        release_npu_locks_batch "$SERVER_NAME" "$LOCKED_NPUS" "$TASK_ID"
    fi
}
trap cleanup_locks EXIT INT TERM

# 尝试锁定NPU
NPU_LIST="0 1 2 3"
if acquire_npu_locks_batch "$SERVER_NAME" "$NPU_LIST" "$TASK_ID"; then
    LOCKED_NPUS="$NPU_LIST"
    echo "成功锁定NPU: $LOCKED_NPUS"
    
    # 执行你的任务
    # ...
    
else
    echo "无法获取NPU锁"
    exit 1
fi

# 脚本结束时会自动释放锁（通过trap）
```

## 最佳实践

1. **定期监控**: 建议定期运行 `./npu_lock_admin.sh status` 检查锁状态
2. **清理超时锁**: 可以设置cron任务定期清理超时锁
3. **日志记录**: 任务日志会包含锁定/释放信息，方便问题排查
4. **合理设置超时**: 根据实际任务运行时间调整 `LOCK_TIMEOUT`

## 定时清理（可选）

添加cron任务自动清理超时锁：

```bash
# 编辑crontab
crontab -e

# 添加以下行（每小时清理一次）
0 * * * * /home/s_limingge/ascend_test_suite/npu_lock_admin.sh cleanup-timeout >> /home/s_limingge/ascend_test_suite/lock_cleanup.log 2>&1
```

## 技术细节

### 使用的技术
- **flock**: Linux文件锁机制，保证原子性
- **trap**: Bash信号处理，确保异常时也能释放锁
- **文件系统锁**: 利用共享文件系统实现分布式锁

### 锁的生命周期

```
创建锁 → 写入元数据 → 任务运行 → 任务结束 → 删除锁文件
         ↓
    设置trap捕获信号（EXIT/INT/TERM）
         ↓
    无论如何退出都会触发cleanup_locks
```

## 联系与支持

如有问题或建议，请联系开发团队。

---

**版本**: 1.0  
**更新时间**: 2025-10-16  
**作者**: AI Assistant

