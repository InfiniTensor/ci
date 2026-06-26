# 监控 SSH 隧道连接，断开后自动重连。
# 用法: .\ssh_tunnel_autoreconnect.ps1 [-Host cambricon] [-RetryDelay 5]
# 示例: .\ssh_tunnel_autoreconnect.ps1 -Host cambricon

param(
    [string]$Host = "cambricon",
    [int]$RetryDelay = 5,
    [int]$MaxRetryDelay = 60
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

$sshArgs = @(
    "-N",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=3",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "TCPKeepAlive=yes",
    $Host
)

$running = $true
$currentDelay = $RetryDelay

Write-Log "开始监控 SSH 隧道: ssh $($sshArgs -join ' ')"
Write-Log "按 Ctrl+C 停止"

try {
    while ($running) {
        Write-Log "正在连接 $Host..."

        & ssh @sshArgs
        $exitCode = $LASTEXITCODE

        if (-not $running) { break }

        Write-Log "连接断开 (exit=$exitCode)，${currentDelay}s 后重连..."
        Start-Sleep -Seconds $currentDelay

        $currentDelay = [Math]::Min($currentDelay * 2, $MaxRetryDelay)
    }
}
finally {
    Write-Log "已退出"
}
