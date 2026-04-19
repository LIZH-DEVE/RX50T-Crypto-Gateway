param(
    [string]$Port = "",
    [int]$Baud = 2000000,
    [switch]$BoardSmoke,
    [int]$HwDeviceIndex = -1,
    [string]$VivadoBat = ""
)

$ErrorActionPreference = "Stop"

function Find-SystemPython {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        return @($pythonCmd.Source)
    }

    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
        return @($pyCmd.Source, "-3")
    }

    throw "Python 3.12 not found. Install Python 3.12 and ensure 'python' or 'py -3' is available."
}

function Invoke-SystemPython {
    param(
        [string[]]$PythonLauncher,
        [string[]]$Arguments
    )

    $cmd = $PythonLauncher[0]
    $prefix = @()
    if ($PythonLauncher.Length -gt 1) {
        $prefix = $PythonLauncher[1..($PythonLauncher.Length - 1)]
    }

    & $cmd @prefix @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code $LASTEXITCODE"
    }
}

function Get-SelectedPort {
    param(
        [string[]]$Ports,
        [string]$RequestedPort,
        [switch]$BoardSmokeEnabled
    )

    if (-not $BoardSmokeEnabled) {
        return $null
    }

    if ($RequestedPort) {
        if ($Ports -notcontains $RequestedPort) {
            throw "Requested port '$RequestedPort' is not available. Detected ports: $($Ports -join ', ')"
        }
        return $RequestedPort
    }

    if ($Ports.Count -eq 1) {
        return $Ports[0]
    }

    if ($Ports.Count -eq 0) {
        throw "No serial ports detected. Connect the board and retry."
    }

    throw "Multiple serial ports detected. Pass -Port <PORT>. Detected ports: $($Ports -join ', ')"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path

if ($repoRoot.Length -gt 40) {
    throw "Hard requirement violated: repository root path length must be <= 40 characters. Move the repo to D:\rx50t_gateway."
}

$pythonLauncher = Find-SystemPython
$venvDir = Join-Path $repoRoot ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"
$requirements = Join-Path $repoRoot "requirements-dev.txt"
$programScript = Join-Path $scriptDir "program_hw_target.ps1"
$cryptoProbe = Join-Path $repoRoot "contest_project\tools\send_rx50t_crypto_probe.py"

Write-Host "== Hard Requirement =="
Write-Host "Repo root: $repoRoot"
Write-Host "Repo root length: $($repoRoot.Length)"

if (!(Test-Path $venvPython)) {
    Write-Host "== Creating .venv =="
    Invoke-SystemPython -PythonLauncher $pythonLauncher -Arguments @("-m", "venv", $venvDir)
}

Write-Host "== Installing requirements-dev.txt =="
& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed with exit code $LASTEXITCODE" }
& $venvPython -m pip install -r $requirements
if ($LASTEXITCODE -ne 0) { throw "dependency installation failed with exit code $LASTEXITCODE" }

Write-Host "== Checking tkinter =="
& $venvPython -c "import tkinter"
if ($LASTEXITCODE -ne 0) {
    throw "tkinter is required and must be available from the Python installation."
}

Write-Host "== Python sanity =="
& $venvPython -m pytest (Join-Path $repoRoot "contest_project\tools") -q
if ($LASTEXITCODE -ne 0) { throw "pytest sanity failed with exit code $LASTEXITCODE" }

$tbScripts = @(
    "build_tb_uart_crypto_probe_cdc_ingress.ps1",
    "build_tb_uart_crypto_probe_cdc_egress.ps1",
    "build_tb_uart_crypto_probe_trace.ps1",
    "build_tb_uart_crypto_probe_watchdog.ps1"
)

foreach ($tb in $tbScripts) {
    Write-Host "== Running $tb =="
    & powershell -ExecutionPolicy Bypass -File (Join-Path $scriptDir $tb)
    if ($LASTEXITCODE -ne 0) {
        throw "$tb failed with exit code $LASTEXITCODE"
    }
}

$ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
Write-Host "== Serial Ports =="
if ($ports.Count -eq 0) {
    Write-Host "none"
} else {
    $ports | ForEach-Object { Write-Host $_ }
}

Write-Host "== JTAG Devices =="
$listArgs = @("-ExecutionPolicy", "Bypass", "-File", $programScript, "-ListDevices")
if ($VivadoBat) {
    $listArgs += @("-VivadoBat", $VivadoBat)
}
& powershell @listArgs
if ($LASTEXITCODE -ne 0) {
    throw "JTAG device enumeration failed with exit code $LASTEXITCODE"
}

$selectedPort = Get-SelectedPort -Ports $ports -RequestedPort $Port -BoardSmokeEnabled:$BoardSmoke

if ($BoardSmoke) {
    Write-Host "== Programming board =="
    $programArgs = @("-ExecutionPolicy", "Bypass", "-File", $programScript)
    if ($VivadoBat) {
        $programArgs += @("-VivadoBat", $VivadoBat)
    }
    if ($HwDeviceIndex -ge 0) {
        $programArgs += @("-HwDeviceIndex", "$HwDeviceIndex")
    }
    & powershell @programArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Board programming failed with exit code $LASTEXITCODE"
    }

    $smokeCmds = @(
        @("--query-pmu"),
        @("--query-trace"),
        @("--run-onchip-bench", "--algo", "sm4"),
        @("--query-bench"),
        @("--query-trace")
    )

    foreach ($smokeArgs in $smokeCmds) {
        Write-Host "== Running board smoke: $($smokeArgs -join ' ') =="
        & $venvPython $cryptoProbe --port $selectedPort --baud $Baud @smokeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Board smoke failed while running: $($smokeArgs -join ' ')"
        }
    }
}

Write-Host "== teammate_init complete =="
