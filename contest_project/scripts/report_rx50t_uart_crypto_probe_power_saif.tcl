set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set contest_root [file join $repo_root contest_project]

if {[info exists ::env(RX50T_CRYPTO_BUILD_DIR)] && $::env(RX50T_CRYPTO_BUILD_DIR) ne ""} {
    set build_dir [file normalize $::env(RX50T_CRYPTO_BUILD_DIR)]
} else {
    set build_dir [file normalize [file join $contest_root build rx50t_uart_crypto_probe]]
}

if {[info exists ::env(RX50T_CLOCK_GATING_POWER_SAIF)] && $::env(RX50T_CLOCK_GATING_POWER_SAIF) ne ""} {
    set saif_file [file normalize $::env(RX50T_CLOCK_GATING_POWER_SAIF)]
} else {
    set saif_file [file normalize [file join $contest_root build sim_tb_uart_crypto_probe_clock_gating_power tb_uart_crypto_probe_clock_gating_power.saif]]
}

set xpr_file [file join $build_dir rx50t_uart_crypto_probe.xpr]
if {![file exists $xpr_file]} {
    error "Build project not found: $xpr_file"
}
if {![file exists $saif_file]} {
    error "SAIF not found: $saif_file"
}

open_project $xpr_file
open_run impl_1
read_saif $saif_file -strip_path tb_uart_crypto_probe_clock_gating_power/dut
report_power -file [file join $build_dir rx50t_uart_crypto_probe_power_saif_impl.rpt]
close_project
exit
