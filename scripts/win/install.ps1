#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib.ps1")
$Root = Get-RepoRoot
$EnvFile = Join-Path $Root ".env"
$VenvDir = Join-Path $Root ".venv"
$RuntimeDir = Join-Path $Root "runtime"

Write-Host "=== BKG BitTTS Worker — Install (Windows) ===" -ForegroundColor Cyan
Write-Host "Repo: $Root"

$python = Find-Python
if (-not $python) {
    Write-InstallHint
    exit 1
}
Write-Host "Python: $python" -ForegroundColor Green

if (-not (Test-Path $EnvFile)) {
    Copy-Item (Join-Path $Root ".env.example") $EnvFile
    Write-Host ".env erstellt — BITTTS_WORKER_TOKEN und BITTTS_SHUTUP_ROOT eintragen." -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

if (-not (Test-Path $VenvDir)) {
    Write-Host "Erstelle venv …"
    & $python -m venv $VenvDir
}

$venvPython = Join-Path $VenvDir "Scripts\python.exe"
& $venvPython -m pip install --upgrade pip wheel
& $venvPython -m pip install -e $Root

$shutup = (Import-DotEnv $EnvFile)["BITTTS_SHUTUP_ROOT"]
if (-not $shutup -or -not (Test-Path $shutup)) {
    Write-Host ""
    Write-Host "BITTTS_SHUTUP_ROOT fehlt in .env oder Ordner existiert nicht." -ForegroundColor Yellow
    Write-Host "Beispiel: BITTTS_SHUTUP_ROOT=C:\src\bkg-bittts-shutup"
    Write-Host "Oder WSL-Pfad wenn Training über WSL/bash läuft."
}

Write-Host ""
Write-Host "Install fertig." -ForegroundColor Green
Write-Host "  Start:  .\scripts\win\start.ps1"
Write-Host "  Status: .\scripts\win\status.ps1"
Write-Host "  Stop:   .\scripts\win\stop.ps1"
Write-Host "  Logs:   .\scripts\win\connect.ps1"
