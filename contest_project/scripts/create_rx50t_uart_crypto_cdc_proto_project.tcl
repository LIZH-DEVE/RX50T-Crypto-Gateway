set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set contest_root [file join $repo_root contest_project]
set reference_root [file join $repo_root reference]
set part_name xc7a50tfgg484-1

if {[info exists ::env(RX50T_CDC_PROTO_BUILD_DIR)] && $::env(RX50T_CDC_PROTO_BUILD_DIR) ne ""} {
    set project_dir [file normalize $::env(RX50T_CDC_PROTO_BUILD_DIR)]
} else {
    set project_dir [file normalize [file join $contest_root build rx50t_uart_crypto_cdc_proto]]
}
file mkdir $project_dir

set rtl_files [list \
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
    [file join $contest_root rtl contest contest_block_fifo.sv] \
    [file join $contest_root rtl contest contest_acl_axis_core.sv] \
    [file join $contest_root rtl contest contest_axis_block_packer.sv] \
    [file join $contest_root rtl contest contest_axis_block_unpacker.sv] \
    [file join $contest_root rtl contest contest_crypto_block_engine.sv] \
    [file join $contest_root rtl contest contest_crypto_axis_core.sv] \
    [file join $contest_root rtl contest contest_reset_sync.sv] \
    [file join $contest_root rtl contest contest_async_axis_fifo.sv] \
    [file join $contest_root rtl contest contest_crypto_cdc_ingress_bridge.sv] \
    [file join $contest_root rtl contest contest_ingress_clk_gen.sv] \
    [file join $contest_root rtl contest contest_crypto_cdc_proto.sv] \
    [file join $contest_root rtl contest rx50t_uart_crypto_cdc_proto_top.sv] \
]

set xdc_files [list [file join $contest_root constraints rx50t_uart_crypto_cdc_proto.xdc]]

read_verilog -sv $rtl_files
read_xdc $xdc_files

synth_design -top rx50t_uart_crypto_cdc_proto_top -part $part_name
write_checkpoint -force [file join $project_dir rx50t_uart_crypto_cdc_proto_post_synth.dcp]
report_utilization -file [file join $project_dir rx50t_uart_crypto_cdc_proto_util_synth.rpt]
report_timing_summary -file [file join $project_dir rx50t_uart_crypto_cdc_proto_timing_synth.rpt]
report_cdc -details -file [file join $project_dir rx50t_uart_crypto_cdc_proto_cdc_synth.rpt]

opt_design
place_design
route_design
write_checkpoint -force [file join $project_dir rx50t_uart_crypto_cdc_proto_post_route.dcp]
report_drc -file [file join $project_dir rx50t_uart_crypto_cdc_proto_drc_impl.rpt]
report_timing_summary -file [file join $project_dir rx50t_uart_crypto_cdc_proto_timing_impl.rpt]
report_bus_skew -sort_by_slack -file [file join $project_dir rx50t_uart_crypto_cdc_proto_bus_skew_impl.rpt]
report_utilization -file [file join $project_dir rx50t_uart_crypto_cdc_proto_util_impl.rpt]
report_cdc -details -file [file join $project_dir rx50t_uart_crypto_cdc_proto_cdc_impl.rpt]

exit
