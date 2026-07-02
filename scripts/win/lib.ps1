# BKG BitTTS Worker — PowerShell-Hilfsfunktionen

function Get-RepoRoot {
    $root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (-not (Test-Path (Join-Path $root "pyproject.toml"))) {
        throw "Repo-Root nicht gefunden (pyproject.toml fehlt)."
    }
    return (Resolve-Path $root).Path
}

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @{} }
    $vars = @{}
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { return }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
        $vars[$key] = $val
        Set-Item -Path "env:$key" -Value $val
    }
    return $vars
}

function Find-Python {
    $candidates = @(
        @{ Cmd = "py"; Args = @("-3.12", "-c", "import sys; print(sys.executable)") },
        @{ Cmd = "py"; Args = @("-3", "-c", "import sys; print(sys.executable)") },
        @{ Cmd = "python"; Args = @("-c", "import sys; print(sys.executable)") },
        @{ Cmd = "python3"; Args = @("-c", "import sys; print(sys.executable)") }
    )
    foreach ($item in $candidates) {
        if (-not (Get-Command $item.Cmd -ErrorAction SilentlyContinue)) { continue }
        try {
            $exe = & $item.Cmd @($item.Args) 2>$null
            if ($exe -and (Test-Path $exe)) { return $exe.Trim() }
        } catch { }
    }
    return $null
}

function Write-InstallHint {
    Write-Host ""
    Write-Host "Python nicht gefunden. Optionen:" -ForegroundColor Yellow
    Write-Host "  1) Microsoft Store: 'Python 3.12' installieren"
    Write-Host "  2) winget install Python.Python.3.12"
    Write-Host "  3) https://www.python.org/downloads/"
    Write-Host "Danach PowerShell neu öffnen und erneut ausführen."
    Write-Host ""
}

function Get-WorkerPidFile {
    param([string]$Root)
    return Join-Path $Root "runtime\worker.pid"
}

function Get-WorkerLogFile {
    param([string]$Root)
    return Join-Path $Root "runtime\worker.log"
}
