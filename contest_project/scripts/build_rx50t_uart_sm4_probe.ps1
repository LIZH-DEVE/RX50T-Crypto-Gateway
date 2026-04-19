$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tcl = Join-Path $scriptDir "create_rx50t_uart_sm4_probe_project.tcl"

$vivadoCandidates = @(
    $env:RX50T_VIVADO_BAT,
    "D:\Xilinx\Vivado\2024.1\bin\vivado.bat",
    "C:\Xilinx\Vivado\2024.1\bin\vivado.bat"
) | Where-Object { $_ }

$vivado = $null
foreach ($candidate in $vivadoCandidates) {
    if (Test-Path $candidate) {
        $vivado = $candidate
        break
    }
}

if (-not $vivado) {
    throw "Vivado 2024.1 not found. Set RX50T_VIVADO_BAT or install Vivado 2024.1."
}

if (!(Test-Path $tcl)) {
    throw "Build script not found: $tcl"
}

& $vivado -mode batch -source $tcl
if ($LASTEXITCODE -ne 0) {
    throw "Vivado build failed with exit code $LASTEXITCODE"
}
