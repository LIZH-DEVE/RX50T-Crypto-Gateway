$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$tcl = Join-Path $scriptDir 'create_tb_uart_crypto_probe_cdc_egress_project.tcl'
if ($env:VIVADO_BIN -and (Test-Path $env:VIVADO_BIN)) {
    $vivado = $env:VIVADO_BIN
} else {
    $vivado = 'D:\Xilinx\Vivado\2024.1\bin\vivado.bat'
}

if (!(Test-Path $vivado)) {
    throw "Vivado not found: $vivado"
}

if (!(Test-Path $tcl)) {
    throw "Simulation script not found: $tcl"
}

& $vivado -mode batch -source $tcl
if ($LASTEXITCODE -ne 0) {
    throw "Vivado simulation failed with exit code $LASTEXITCODE"
}
