set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set contest_root [file join $repo_root contest_project]
set reference_root [file join $repo_root reference]

create_project sim_tb_mac_facing_ingress_top [file normalize [file join $contest_root build sim_tb_mac_facing_ingress_top]] -part xc7a50tfgg484-1 -force

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
    [file join $contest_root rtl contest contest_block_fifo.sv] \
    [file join $contest_root rtl contest contest_acl_axis_core.sv] \
    [file join $contest_root rtl contest contest_axis_block_packer.sv] \
    [file join $contest_root rtl contest contest_axis_block_unpacker.sv] \
    [file join $contest_root rtl contest contest_crypto_block_engine.sv] \
    [file join $contest_root rtl contest contest_crypto_axis_core.sv] \
    [file join $contest_root rtl contest contest_cdc_ingress_pkg.sv] \
    [file join $contest_root rtl contest contest_reset_sync.sv] \
    [file join $contest_root rtl contest contest_async_axis_fifo.sv] \
    [file join $contest_root rtl contest contest_async_mailbox.sv] \
    [file join $contest_root rtl contest contest_cdc_payload_dispatcher.sv] \
    [file join $contest_root rtl contest contest_crypto_cdc_ingress_bridge.sv] \
    [file join $contest_root rtl contest contest_mac_facing_ingress_top.sv] \
]
add_files -norecurse $source_files

add_files -fileset sim_1 -norecurse [list [file join $contest_root tb contest tb_mac_facing_ingress_top.sv]]

set_property top tb_mac_facing_ingress_top [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit