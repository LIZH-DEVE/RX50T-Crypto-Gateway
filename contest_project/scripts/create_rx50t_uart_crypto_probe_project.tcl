if {[info exists ::env(RX50T_CRYPTO_BUILD_DIR)] && $::env(RX50T_CRYPTO_BUILD_DIR) ne ""} {
    set project_dir [file normalize $::env(RX50T_CRYPTO_BUILD_DIR)]
} else {
    set project_dir [file normalize "D:/FPGAhanjia/jichuangsai/contest_project/build/rx50t_uart_crypto_probe"]
}
file mkdir $project_dir

create_project rx50t_uart_crypto_probe $project_dir -part xc7a50tfgg484-1 -force

add_files -norecurse {
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_core.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_encipher_block.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_decipher_block.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_key_mem.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_sbox.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/aes_inv_sbox.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/sbox_replace.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/one_round_for_encdec.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/transform_for_encdec.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/one_round_for_key_exp.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/transform_for_key_exp.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/get_cki.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/key_expansion.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/sm4_encdec.v
    D:/FPGAhanjia/jichuangsai/reference/rtl/core/crypto/sm4_top.v
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_uart_rx.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_uart_tx.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_parser_core.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_acl_core.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_block_fifo.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_crypto_bridge.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_uart_crypto_probe.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/rx50t_uart_crypto_probe_top.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/rx50t_uart_crypto_probe_board_top.sv
}

add_files -fileset constrs_1 -norecurse {
    D:/FPGAhanjia/jichuangsai/contest_project/constraints/rx50t_uart_echo.xdc
}

add_files -fileset sim_1 -norecurse {
    D:/FPGAhanjia/jichuangsai/reference/tb/crypto_vectors_pkg.sv
    D:/FPGAhanjia/jichuangsai/contest_project/tb/contest/tb_uart_crypto_probe.sv
}

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
