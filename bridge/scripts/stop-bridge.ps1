# ─────────────────────────────────────────────────────────────────────────────
# pi Bridge - universal stopper for Windows
#
# Stops every bridge-related process, no matter how it was started:
#   1. the Task Scheduler service instance ("pi-bridge" task)
#   2. whatever still listens on the bridge port (dev instance / leftovers)
#   3. orphaned dev-mode chains (npm run dev:bridge / tsx watch)
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File bridge/scripts/stop-bridge.ps1
#   powershell ... -File stop-bridge.ps1 -Port 18732   # custom port
#
# Why this exists: on Windows, Ctrl+C does NOT kill the dev bridge - the whole
# process chain (npm -> cmd -> tsx watch -> node) ignores the console event.
# taskkill /T /F (kill process tree) is the only reliable cleanup.
# ─────────────────────────────────────────────────────────────────────────────
param([int]$Port = 18731)

$TaskName = "pi-bridge"

# ── 1) Stop the Task Scheduler instance (kills its whole tree via job object) ──
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task -and $task.State -ne "Disabled") {
    Write-Host "-> Stopping scheduled task '$TaskName'..."
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

# ── 2) Kill whatever still listens on the port ──────────────────────────────
$listeners = @()
foreach ($line in (netstat -ano -p tcp)) {
    if ($line -match "LISTENING" -and $line -match ":(\d+)\s" -and $Matches[1] -eq $Port) {
        $cols = ($line.Trim() -split "\s+")
        $procId = [int]$cols[-1]
        if ($procId -gt 0 -and $listeners -notcontains $procId) { $listeners += $procId }
    }
}

# ── 3) Kill orphaned dev-mode chains (npm run dev:bridge / tsx watch) ───────
$devProcs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match "^(node|cmd|npm|conhost|powershell)\.exe$" -and
    $_.CommandLine -match "watch src/index|run dev:bridge|run-bridge"
})

foreach ($procId in $listeners) {
    Write-Host "-> Killing port $Port listener PID $procId (tree)..."
    taskkill /PID $procId /T /F 2>$null | Out-Null
}
foreach ($proc in $devProcs) {
    Write-Host "-> Killing leftover PID $($proc.ProcessId) [$($proc.Name)]..."
    taskkill /PID $($proc.ProcessId) /T /F 2>$null | Out-Null
}

if (-not $listeners -and -not $devProcs) {
    Write-Host "No bridge processes found."
} else {
    Write-Host "OK  Bridge stopped."
}
