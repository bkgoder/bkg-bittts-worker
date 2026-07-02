#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib.ps1")
$Root = Get-RepoRoot
$LogFile = Get-WorkerLogFile $Root

if (-not (Test-Path $LogFile)) {
    Write-Host "Noch kein Log: $LogFile"
    exit 0
}

Write-Host "Live-Log (Strg+C beenden): $LogFile" -ForegroundColor Cyan
Get-Content $LogFile -Wait -Tail 50
