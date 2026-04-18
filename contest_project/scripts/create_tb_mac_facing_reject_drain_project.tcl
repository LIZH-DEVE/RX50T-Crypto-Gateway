set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set contest_root [file join $repo_root contest_project]
set reference_root [file join $repo_root reference]
set project_dir [file normalize [file join $contest_root build sim_tb_mac_facing_reject_drain]]
file mkdir $project_dir
set run_dir [file normalize [file join $project_dir xsim_cli]]
file mkdir $run_dir
set prev_dir [pwd]
cd $run_dir
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
    [file join $contest_root rtl contest contest_async_mailbox.sv] \
    [file join $contest_root rtl contest contest_cdc_ingress_pkg.sv] \
    [file join $contest_root rtl contest contest_cdc_payload_dispatcher.sv] \
    [file join $contest_root rtl contest contest_crypto_cdc_ingress_bridge.sv] \
    [file join $contest_root rtl contest contest_mac_facing_ingress_top.sv] \
    [file join $contest_root tb contest tb_mac_facing_reject_drain.sv] \
]
if {[catch {exec xvlog -sv {*}$rtl_files} result options]} {
    puts $result
    cd $prev_dir
    return -options $options $result
}
puts $result
if {[catch {exec xelab tb_mac_facing_reject_drain -s tb_mac_facing_reject_drain_behav --debug typical} result options]} {
    puts $result
    cd $prev_dir
    return -options $options $result
}
puts $result
if {[catch {exec xsim tb_mac_facing_reject_drain_behav -runall} result options]} {
    puts $result
    cd $prev_dir
    return -options $options $result
}
puts $result
cd $prev_dir
exit