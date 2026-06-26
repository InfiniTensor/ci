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

Write-Log "Monitoring SSH tunnel: ssh $($sshArgs -join ' ')"
Write-Log "Press Ctrl+C to stop"

try {
    while ($running) {
        Write-Log "Connecting to $SshHost..."

        & ssh @sshArgs
        $exitCode = $LASTEXITCODE

        if (-not $running) { break }

        Write-Log "Connection lost (exit=$exitCode), reconnecting in ${currentDelay}s..."
        Start-Sleep -Seconds $currentDelay

        $currentDelay = [Math]::Min($currentDelay * 2, $MaxRetryDelay)
    }
}
finally {
    Write-Log "Exited"
}
