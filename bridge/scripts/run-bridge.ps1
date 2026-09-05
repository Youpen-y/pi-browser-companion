# ─────────────────────────────────────────────────────────────────────────────
# pi Browser Companion Bridge - supervisor for the Windows Task Scheduler job
#
# Runs the production build in a loop: if node exits with a non-zero code
# (crash), it is restarted after 5 seconds (like systemd's Restart=on-failure).
# A clean exit (code 0) ends the loop. Output is appended to logs\bridge.log.
#
# Why a supervisor loop: Task Scheduler's built-in "restart on failure"
# (RestartCount/RestartInterval) proved unreliable when the process is
# killed/terminated externally - the restart never fired in practice.
#
# Why <nul and cmd: node hangs at startup in console-less environments
# (e.g. Task Scheduler) unless stdin is redirected; cmd handles the
# redirection and propagates the exit code.
# ─────────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Continue"

$BridgeDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $BridgeDir
if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" | Out-Null }

while ($true) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content "logs\bridge.log" "[$stamp] bridge starting"

    cmd /c "node dist\index.js <nul >> logs\bridge.log 2>&1"
    $code = $LASTEXITCODE

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content "logs\bridge.log" "[$stamp] bridge exited with code $code"

    if ($code -eq 0) { break }
    Start-Sleep -Seconds 5
}
