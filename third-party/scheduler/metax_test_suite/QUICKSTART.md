# NPU锁机制快速入门

## 1分钟快速开始

### 安装（已完成）

NPU锁机制已经集成到测试脚本中，无需额外安装。

### 使用测试系统（自动使用锁）

直接运行现有的测试命令，锁机制会自动工作：

```bash
# 运行冒烟测试
bash ascend_resource_monitor.sh Smoke SigInfer

# 运行性能测试
bash ascend_resource_monitor.sh Performance SigInfer Random
```

**✅ 改进效果：**
- 多个测试任务不再争抢相同的NPU
- 每个任务获取的NPU会立即被锁定
- 任务结束后自动释放锁
- 支持异常退出时自动清理锁

### 监控锁状态

查看当前所有NPU锁的状态：

```bash
./npu_lock_admin.sh status
```

输出示例：
```
==========================================
         NPU锁状态监控面板
==========================================
时间: 2025-10-16 18:39:19

📊 统计信息:
  总锁数量: 4
  超时锁数: 0

📍 锁详情 (按服务器分组):

服务器: 10.9.1.74
  NPU 0 | 🟢 正常 | 持续: 0h 5m 32s | 任务: SmokeTest_DeepSeek-R1_0_12345
  NPU 1 | 🟢 正常 | 持续: 0h 5m 32s | 任务: SmokeTest_DeepSeek-R1_0_12345
==========================================
```

### 实时监控（推荐）

实时查看锁状态变化：

```bash
./npu_lock_admin.sh watch
```

按 `Ctrl+C` 退出监控。

### 常见问题处理

#### 问题：任务一直等待NPU

**解决方法：**
```bash
# 1. 查看锁状态
./npu_lock_admin.sh status

# 2. 如果发现超时的锁，清理它们
./npu_lock_admin.sh cleanup-timeout
```

#### 问题：任务异常退出后锁未释放

**解决方法：**
```bash
# 查看具体NPU的锁信息
./npu_lock_admin.sh info 10_9_1_74 0

# 确认任务已结束后，手动释放锁
./npu_lock_admin.sh unlock 10_9_1_74 0
```

## 详细文档

查看完整文档了解更多功能：
```bash
less NPU_LOCK_README.md
```

或查看帮助：
```bash
./npu_lock_admin.sh help
```

## 演示

运行演示脚本查看完整工作流程：
```bash
./demo_npu_lock.sh
```

## 工作原理

```
┌─────────────────────────────────────────────────────┐
│  任务1启动                        任务2启动           │
│      ↓                                ↓             │
│  扫描空闲NPU                      扫描空闲NPU        │
│      ↓                                ↓             │
│  发现NPU 0,1空闲                  发现NPU 0,1空闲   │
│      ↓                                ↓             │
│  尝试锁定NPU 0,1                  尝试锁定NPU 0,1   │
│      ↓                                ↓             │
│  ✅ 锁定成功                        ❌ 锁定失败      │
│      ↓                                ↓             │
│  执行任务                          继续扫描其他NPU   │
│      ↓                                               │
│  任务完成                                            │
│      ↓                                               │
│  自动释放锁                                          │
└─────────────────────────────────────────────────────┘
```

**关键特性：**
- ⚡ 原子性锁定：使用`mkdir`的原子性保证
- 🔒 批量锁定：要么全部成功，要么全部失败
- 🧹 自动清理：任务结束自动释放（包括异常退出）
- ⏱️ 超时保护：防止死锁
- 🌐 集群支持：跨服务器工作

## 定期维护（可选）

添加cron任务自动清理超时锁：

```bash
# 编辑crontab
crontab -e

# 添加以下行（每小时清理一次）
0 * * * * /home/s_limingge/ascend_test_suite/npu_lock_admin.sh cleanup-timeout >> /home/s_limingge/ascend_test_suite/lock_cleanup.log 2>&1
```

## 故障排查

如果遇到问题，请按以下顺序检查：

1. **查看锁状态**
   ```bash
   ./npu_lock_admin.sh status
   ```

2. **查看统计信息**
   ```bash
   ./npu_lock_admin.sh stats
   ```

3. **清理超时锁**
   ```bash
   ./npu_lock_admin.sh cleanup-timeout
   ```

4. **查看具体任务日志**
   ```bash
   tail -f cron_job_*.log
   ```

5. **检查NPU实际使用情况**
   ```bash
   ssh s_limingge@<server_ip> "npu-smi info"
   ```

## 性能影响

- 锁获取时间：< 1ms（本地文件系统）
- 锁释放时间：< 1ms
- 存储开销：每个锁约 4KB
- CPU开销：可忽略不计

## 配置

锁配置在 `npu_lock_manager.sh` 中：

```bash
LOCK_DIR="/home/s_limingge/.npu_locks"  # 锁目录
LOCK_TIMEOUT=7200                       # 超时时间（2小时）
```

根据实际情况调整：
- 如果任务通常运行很长时间，增加 `LOCK_TIMEOUT`
- 如果需要更改锁目录位置，修改 `LOCK_DIR`

## 支持的测试类型

当前支持的测试类型：
- ✅ 冒烟测试（SmokeTest）
- ✅ 性能测试（PerformanceTest）
- 🔄 稳定性测试（StabilityTest）- 需要添加集成
- 🔄 精度测试（AccuracyTest）- 需要添加集成

## 下一步

1. 阅读完整文档：`less NPU_LOCK_README.md`
2. 运行演示脚本：`./demo_npu_lock.sh`
3. 查看所有命令：`./npu_lock_admin.sh help`
4. 开始使用：直接运行你的测试任务

---

**需要帮助？** 查看 `NPU_LOCK_README.md` 获取详细信息。

