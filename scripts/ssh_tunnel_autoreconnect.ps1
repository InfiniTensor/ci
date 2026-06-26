# Monitor SSH tunnel and auto-reconnect on disconnect.
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\ssh_tunnel_autoreconnect.ps1 -SshHost nvidia
#   .\ssh_tunnel_autoreconnect.cmd -SshHost nvidia

param(
    [string]$SshHost = "cambricon",
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
    $SshHost
)

$running = $true
$currentDelay = $RetryDelay

Write-Log "开始监控 SSH 隧道: ssh $($sshArgs -join ' ')"
Write-Log "按 Ctrl+C 停止"

try {
    while ($running) {
        Write-Log "正在连接 $SshHost..."

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
