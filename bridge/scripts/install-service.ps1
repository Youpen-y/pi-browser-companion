# ─────────────────────────────────────────────────────────────────────────────
# pi Bridge Service Installer for Windows (Task Scheduler)
#
# Usage (from repo root):
#   powershell -NoProfile -ExecutionPolicy Bypass -File bridge/scripts/install-service.ps1
#
# Effect:
#   1. Installs dependencies if missing (npm install at repo root)
#   2. Builds the bridge (npm run build)
#   3. Registers a Task Scheduler job "pi-bridge" that:
#      - starts at user logon, headless (no console window)
#      - auto-restarts on failure (handled by run-bridge.ps1 supervisor loop, 5s apart)
#      - has no execution time limit (runs indefinitely)
#   4. Starts the task immediately and checks /health
#
# After install:
#   Start-ScheduledTask pi-bridge                        # Start
#   Stop-ScheduledTask  pi-bridge                        # Stop (or stop-bridge.ps1)
#   Get-ScheduledTask   pi-bridge                        # Status
#   Get-Content bridge\logs\bridge.log -Tail 20 -Wait    # Logs
#
# To uninstall:
#   powershell -NoProfile -ExecutionPolicy Bypass -File bridge/scripts/uninstall-service.ps1
# ─────────────────────────────────────────────────────────────────────────────
param([int]$Port = 18731)

$ErrorActionPreference = "Stop"

$TaskName = "pi-bridge"

# ── Resolve paths ──────────────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgeDir = Split-Path -Parent $ScriptDir
$RepoDir   = Split-Path -Parent $BridgeDir
$RunCmd    = Join-Path $ScriptDir "run-bridge.ps1"

# ── Detect node binary ─────────────────────────────────────────────────────
$NodeBin = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $NodeBin) {
    Write-Host "[ERROR] node not found on PATH. Please install Node.js 22+."
    exit 1
}

Write-Host "== pi Bridge - Task Scheduler Service Installer =="
Write-Host "  Bridge dir:  $BridgeDir"
Write-Host "  Node binary: $NodeBin"
Write-Host "  Task name:   $TaskName"
Write-Host ""

# ── Install deps + build ───────────────────────────────────────────────────
if (-not (Test-Path (Join-Path $RepoDir "node_modules"))) {
    Write-Host "-> Installing dependencies (repo root)..."
    Push-Location $RepoDir
    npm install
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "[ERROR] npm install failed."; exit 1 }
    Pop-Location
}

Write-Host "-> Building bridge..."
Push-Location $BridgeDir
npm run build
if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "[ERROR] build failed."; exit 1 }
Pop-Location

# ── Register scheduled task ────────────────────────────────────────────────
# Wrap in `conhost.exe --headless` so the task NEVER shows a console window,
# even with the Interactive principal (S4U is denied on locked-down machines).
# Without it, a visible PowerShell window appears on the desktop and closing
# it kills the whole service tree.
$Conhost = "${env:SystemRoot}\System32\conhost.exe"
if (-not (Test-Path $Conhost)) { $Conhost = (Get-Command conhost.exe -ErrorAction SilentlyContinue).Source }
if (-not $Conhost) {
    Write-Host "[ERROR] conhost.exe not found (Windows 10 1809+ required)."
    exit 1
}
$Action = New-ScheduledTaskAction -Execute $Conhost `
    -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$RunCmd`"" `
    -WorkingDirectory $BridgeDir
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
    -MultipleInstances IgnoreNew

# S4U = headless (runs whether user is logged on or not, no console window)
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Limited

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

try {
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal | Out-Null
} catch {
    # Some locked-down environments deny S4U registration - retry as Interactive
    Write-Host "[WARN] S4U principal rejected ($($_.Exception.Message)); retrying as Interactive..."
    $Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal | Out-Null
}
Write-Host "OK  Task registered"
Write-Host ""

# ── Start now + verify ─────────────────────────────────────────────────────
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 4

$state = (Get-ScheduledTask -TaskName $TaskName).State
Write-Host "-> Task state: $state"

try {
    $health = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 5
    Write-Host "-> Health: $($health.status) (v$($health.version), port $($health.port))"
} catch {
    Write-Host "[WARN] /health not reachable yet on port $Port - check bridge\logs\bridge.log"
}

Write-Host ""
Write-Host "--------------------------------------------------"
Write-Host "  Start:      Start-ScheduledTask $TaskName"
Write-Host "  Stop:       powershell -File bridge/scripts/stop-bridge.ps1"
Write-Host "              (also: npm run kill -w bridge)"
Write-Host "  Status:     Get-ScheduledTask   $TaskName"
Write-Host "  Logs:       Get-Content bridge\logs\bridge.log -Tail 20 -Wait"
Write-Host "  Uninstall:  powershell -File bridge/scripts/uninstall-service.ps1"
Write-Host "--------------------------------------------------"
Write-Host ""
Write-Host "OK  Done."
