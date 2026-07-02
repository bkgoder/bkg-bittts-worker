#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib.ps1")
$Root = Get-RepoRoot
$EnvFile = Join-Path $Root ".env"
$VenvPython = Join-Path $Root ".venv\Scripts\python.exe"
$PidFile = Get-WorkerPidFile $Root
$LogFile = Get-WorkerLogFile $Root
$RuntimeDir = Join-Path $Root "runtime"

if (-not (Test-Path $VenvPython)) {
    Write-Host "Zuerst installieren: .\scripts\win\install.ps1" -ForegroundColor Red
    exit 1
}

Import-DotEnv $EnvFile | Out-Null
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -Raw
    if ($oldPid -match '^\d+$') {
        $proc = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "Worker läuft bereits. PID: $oldPid"
            exit 0
        }
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

$env:BITTTS_WORKER_RUNTIME = $RuntimeDir
"" | Set-Content $LogFile -Encoding utf8

$cmd = "Set-Location -LiteralPath '$Root'; & '$venvPython' -m worker.launcher *>> '$LogFile' 2>&1"
$proc = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-Command", $cmd `
    -PassThru

$proc.Id | Set-Content $PidFile -Encoding ascii -NoNewline
Write-Host "Worker gestartet. PID: $($proc.Id)"
Write-Host "Log: $LogFile"

for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if ($proc.HasExited) {
        Write-Host "Worker sofort beendet — Log:" -ForegroundColor Red
        Get-Content $LogFile -Tail 40
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
    if (Select-String -Path $LogFile -Pattern "Worker registriert:" -Quiet -ErrorAction SilentlyContinue) {
        Write-Host "Worker registriert am Koordinator." -ForegroundColor Green
        exit 0
    }
}

Write-Host "Worker läuft, Registrierung noch offen — Log prüfen." -ForegroundColor Yellow
