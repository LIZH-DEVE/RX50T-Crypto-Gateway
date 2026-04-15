set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set contest_root [file join $repo_root contest_project]
set reference_root [file join $repo_root reference]

if {[info exists ::env(RX50T_CRYPTO_BUILD_DIR)] && $::env(RX50T_CRYPTO_BUILD_DIR) ne ""} {
    set project_dir [file normalize $::env(RX50T_CRYPTO_BUILD_DIR)]
} else {
    set project_dir [file normalize [file join $contest_root build rx50t_uart_crypto_probe]]
}
file mkdir $project_dir

create_project rx50t_uart_crypto_probe $project_dir -part xc7a50tfgg484-1 -force

set source_files [list \
    [file join $reference_root rtl core crypto aes_core.v] \
    [file join $reference_root rtl core crypto aes_encipher_block.v] \
    [file join $reference_root rtl core crypto aes_decipher_block.v] \
    [file join $reference_root rtl core crypto aes_key_mem.v] \
    [file join $reference_root rtl core crypto aes_sbox.v] \
    [file join $reference_root rtl core crypto aes_inv_sbox.v] \
    [file join $reference_root rtl core crypto sbox_replace.v] \
    [file join $reference_root rtl core crypto one_round_for_encdec.v] \
    [file join $reference_root rtl core crypto transform_for_encdec.v] \
    [file join $reference_root rtl core crypto one_round_for_key_exp.v] \
    [file join $reference_root rtl core crypto transform_for_key_exp.v] \
    [file join $reference_root rtl core crypto get_cki.v] \
    [file join $reference_root rtl core crypto key_expansion.v] \
    [file join $reference_root rtl core crypto sm4_encdec.v] \
    [file join $reference_root rtl core crypto sm4_top.v] \
    [file join $contest_root rtl contest contest_uart_rx.sv] \
    [file join $contest_root rtl contest contest_uart_tx.sv] \
    [file join $contest_root rtl contest contest_parser_core.sv] \
    [file join $contest_root rtl contest contest_block_fifo.sv] \
    [file join $contest_root rtl contest contest_acl_axis_core.sv] \
    [file join $contest_root rtl contest contest_axis_block_packer.sv] \
    [file join $contest_root rtl contest contest_axis_block_unpacker.sv] \
    [file join $contest_root rtl contest contest_crypto_block_engine.sv] \
    [file join $contest_root rtl contest contest_crypto_axis_core.sv] \
    [file join $contest_root rtl contest contest_uart_crypto_probe.sv] \
    [file join $contest_root rtl contest rx50t_uart_crypto_probe_top.sv] \
    [file join $contest_root rtl contest rx50t_uart_crypto_probe_board_top.sv] \
]
add_files -norecurse $source_files

set constr_files [list [file join $contest_root constraints rx50t_uart_echo.xdc]]
add_files -fileset constrs_1 -norecurse $constr_files

set sim_files [list \
    [file join $reference_root tb crypto_vectors_pkg.sv] \
    [file join $contest_root tb contest tb_uart_crypto_probe.sv] \
]
add_files -fileset sim_1 -norecurse $sim_files

set_property top rx50t_uart_crypto_probe_board_top [current_fileset]
set_property top tb_uart_crypto_probe [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
open_run synth_1
report_utilization -file [file join $project_dir rx50t_uart_crypto_probe_util_synth.rpt]
report_timing_summary -file [file join $project_dir rx50t_uart_crypto_probe_timing_synth.rpt]

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
report_drc -file [file join $project_dir rx50t_uart_crypto_probe_drc_impl.rpt]
report_timing_summary -file [file join $project_dir rx50t_uart_crypto_probe_timing_impl.rpt]
report_utilization -file [file join $project_dir rx50t_uart_crypto_probe_util_impl.rpt]
