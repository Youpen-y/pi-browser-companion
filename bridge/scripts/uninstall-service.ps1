# ─────────────────────────────────────────────────────────────────────────────
# pi Bridge Service Uninstaller for Windows
#
# Usage (from repo root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File bridge/scripts/uninstall-service.ps1
# ─────────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"

$TaskName = "pi-bridge"

Write-Host "== pi Bridge - Task Scheduler Service Uninstaller =="

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "Task not found: $TaskName (nothing to uninstall.)"
    exit 0
}

Write-Host "-> Stopping task..."
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Write-Host "-> Removing task..."
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

Write-Host "OK  Service uninstalled."
Write-Host "   (Log file bridge\logs\bridge.log was left in place.)"
