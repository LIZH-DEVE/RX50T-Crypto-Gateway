param(
    [string]$BitstreamPath = "",
    [int]$HwDeviceIndex = -1,
    [string]$VivadoBat = "",
    [switch]$ListDevices
)

$ErrorActionPreference = "Stop"

function Resolve-VivadoBat {
    param([string]$Override)

    $candidates = @(
        $Override,
        $env:RX50T_VIVADO_BAT,
        "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
        "C:\Xilinx\Vivado\2024.1\bin\vivado.bat"
    ) | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    $command = Get-Command vivado.bat -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Vivado 2024.1 not found. Set RX50T_VIVADO_BAT or pass -VivadoBat."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$tclScript = Join-Path $scriptDir "program_hw_target.tcl"
$vivado = Resolve-VivadoBat -Override $VivadoBat

if ([string]::IsNullOrWhiteSpace($BitstreamPath)) {
    $BitstreamPath = Join-Path $repoRoot "contest_project\build\rx50t_uart_crypto_probe\rx50t_uart_crypto_probe.runs\impl_1\rx50t_uart_crypto_probe_board_top.bit"
}

$vivadoArgs = @("-mode", "batch", "-source", $tclScript, "-tclargs")
if ($ListDevices) {
    $vivadoArgs += "-list-only"
} else {
    $resolvedBitstream = (Resolve-Path $BitstreamPath -ErrorAction Stop).Path
    $vivadoArgs += @("-bitstream", $resolvedBitstream)
    if ($HwDeviceIndex -ge 0) {
        $vivadoArgs += @("-device-index", "$HwDeviceIndex")
    }
}

& $vivado @vivadoArgs
if ($LASTEXITCODE -ne 0) {
    throw "Vivado hardware command failed with exit code $LASTEXITCODE"
}
