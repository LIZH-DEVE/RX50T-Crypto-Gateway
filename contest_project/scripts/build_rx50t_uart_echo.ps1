$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$vivado = "D:\\Xilinx\\Vivado\\2024.1\\bin\\vivado.bat"

if (!(Test-Path -LiteralPath $vivado)) {
    throw "Vivado not found: $vivado"
}

$part = if ($args.Count -ge 1) { $args[0] } else { "xc7a50tfgg484-1" }
$tcl  = Join-Path $scriptDir "create_rx50t_uart_echo_project.tcl"

Push-Location $projectRoot
try {
    & $vivado -mode batch -source $tcl -tclargs $part
} finally {
    Pop-Location
}
