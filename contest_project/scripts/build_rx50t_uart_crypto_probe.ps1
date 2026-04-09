$ErrorActionPreference = "Stop"

$vivado = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat"
$tcl    = "D:\FPGAhanjia\jichuangsai\contest_project\scripts\create_rx50t_uart_crypto_probe_project.tcl"

if (!(Test-Path $vivado)) {
    throw "Vivado not found: $vivado"
}

if (!(Test-Path $tcl)) {
    throw "Build script not found: $tcl"
}

& $vivado -mode batch -source $tcl
if ($LASTEXITCODE -ne 0) {
    throw "Vivado build failed with exit code $LASTEXITCODE"
}
