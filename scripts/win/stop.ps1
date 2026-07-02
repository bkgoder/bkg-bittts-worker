#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib.ps1")
$Root = Get-RepoRoot
$PidFile = Get-WorkerPidFile $Root

if (-not (Test-Path $PidFile)) {
    Write-Host "Kein Worker aktiv."
    exit 0
}

$pidText = (Get-Content $PidFile -Raw).Trim()
if ($pidText -notmatch '^\d+$') {
    Remove-Item $PidFile -Force
    Write-Host "Ungültige PID-Datei entfernt."
    exit 0
}

$proc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
if (-not $proc) {
    Remove-Item $PidFile -Force
    Write-Host "Worker nicht mehr aktiv."
    exit 0
}

Stop-Process -Id ([int]$pidText) -Force
Remove-Item $PidFile -Force
Write-Host "Worker gestoppt (PID $pidText)."
