$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$tclPath = Join-Path $scriptDir "create_tb_contest_acl_axis_core_project.tcl"
$vivado = "D:\Xilinx\Vivado\2024.1\bin\vivado.bat"
if (-not (Test-Path $vivado)) {
    throw "Vivado not found at $vivado"
}
Push-Location $repoRoot
try {
    & $vivado -mode batch -source $tclPath
} finally {
    Pop-Location
}
