# 自托管 Runner 系统服务配置（README 简版）

当前在所有 CI 服务器（Nvidia、Metax、Moore、Cambricon）上，已分别配置 3 个自托管 Runner。

## 1) 停止 Runner（如正在运行）

```bash
./run.sh # 若前台运行，先 Ctrl+C 停止
```

## 2) 进入每个自托管 Runner 的安装目录

```bash
cd /home/zkjh/actions-runner[-num]
```

## 3) 安装系统服务

```bash
sudo ./svc.sh install
```

## 4) 配置代理（可选）

编辑服务配置：

```bash
sudo systemctl edit <actions.runner.<org>-<repo>.<runner>.service>
```

添加以下内容：

```ini
[Service]
Environment="http_proxy=http://localhost:9990"
Environment="https_proxy=http://localhost:9990"
Environment="no_proxy=localhost,127.0.0.1,::1"
```

重载并重启服务：

```bash
sudo systemctl daemon-reload
sudo systemctl restart <actions.runner.<org>-<repo>.<runner>.service>
```

检查环境变量是否生效：

```bash
sudo systemctl show <actions.runner.<org>-<repo>.<runner>.service> --property=Environment
```

## 5) 启动服务

```bash
sudo ./svc.sh start
```

## 6) 查看服务状态

```bash
sudo ./svc.sh status
```

## 7) 停止服务

```bash
sudo ./svc.sh stop
```

## 8) 卸载服务

```bash
sudo ./svc.sh uninstall
```
