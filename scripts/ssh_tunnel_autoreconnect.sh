#!/usr/bin/env bash
# 监控 SSH 隧道连接，断开后自动重连。
# 用法: ./ssh_tunnel_autoreconnect.sh [SSH_HOST]
# 示例: ./ssh_tunnel_autoreconnect.sh cambricon

set -euo pipefail

SSH_HOST="${1:-cambricon}"
RETRY_DELAY="${RETRY_DELAY:-5}"
MAX_RETRY_DELAY="${MAX_RETRY_DELAY:-60}"

SSH_OPTS=(
    -N
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=3
    -o ExitOnForwardFailure=yes
    -o TCPKeepAlive=yes
)

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

running=true
retry_delay="$RETRY_DELAY"

cleanup() {
    running=false
    log "收到退出信号，正在关闭 SSH 连接..."
    if [[ -n "${ssh_pid:-}" ]] && kill -0 "$ssh_pid" 2>/dev/null; then
        kill "$ssh_pid" 2>/dev/null || true
        wait "$ssh_pid" 2>/dev/null || true
    fi
    log "已退出"
    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP

log "开始监控 SSH 隧道: ssh ${SSH_OPTS[*]} ${SSH_HOST}"
log "按 Ctrl+C 停止"

while $running; do
    log "正在连接 ${SSH_HOST}..."

    ssh "${SSH_OPTS[@]}" "$SSH_HOST" &
    ssh_pid=$!

    wait "$ssh_pid" 2>/dev/null || true
    exit_code=$?

    if ! $running; then
        break
    fi

    log "连接断开 (exit=${exit_code})，${retry_delay}s 后重连..."
    sleep "$retry_delay"

    retry_delay=$((retry_delay * 2))
    if (( retry_delay > MAX_RETRY_DELAY )); then
        retry_delay=$MAX_RETRY_DELAY
    fi
done
