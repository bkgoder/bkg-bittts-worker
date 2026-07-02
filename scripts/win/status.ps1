#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib.ps1")
$Root = Get-RepoRoot
$EnvFile = Join-Path $Root ".env"
$PidFile = Get-WorkerPidFile $Root
$LogFile = Get-WorkerLogFile $Root

$vars = Import-DotEnv $EnvFile
Write-Host "=== BKG BitTTS Worker Status ===" -ForegroundColor Cyan
Write-Host "Koordinator: $($vars['BITTTS_COORDINATOR_URL'])"
Write-Host "Name:        $($vars['BITTTS_WORKER_NAME'])"
Write-Host "Shutup:      $(if ($vars['BITTTS_SHUTUP_ROOT']) { $vars['BITTTS_SHUTUP_ROOT'] } else { 'Remote-Bundle (automatisch)' })"

if (Test-Path $PidFile) {
    $pidText = (Get-Content $PidFile -Raw).Trim()
    $proc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "Prozess:     LÄUFT (PID $pidText)" -ForegroundColor Green
    } else {
        Write-Host "Prozess:     GESTOPPT (veraltete PID)" -ForegroundColor Yellow
    }
} else {
    Write-Host "Prozess:     GESTOPPT" -ForegroundColor DarkGray
}

if (Test-Path $LogFile) {
    Write-Host ""
    Write-Host "--- Log (letzte 20 Zeilen) ---"
    Get-Content $LogFile -Tail 20
}
