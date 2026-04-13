$ErrorActionPreference = "Stop"

$vivado = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat"
$tcl    = "D:\FPGAhanjia\jichuangsai\contest_project\scripts\create_tb_contest_crypto_axis_core_project.tcl"

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
