set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set contest_root [file join $repo_root contest_project]

if {[info exists ::env(RX50T_CDC_BRIDGE_SIM_DIR)] && $::env(RX50T_CDC_BRIDGE_SIM_DIR) ne ""} {
    set project_dir [file normalize $::env(RX50T_CDC_BRIDGE_SIM_DIR)]
} else {
    set project_dir [file normalize [file join $contest_root build sim_tb_contest_crypto_cdc_ingress_bridge]]
}
file mkdir $project_dir

create_project sim_tb_contest_crypto_cdc_ingress_bridge $project_dir -part xc7a50tfgg484-1 -force

add_files -norecurse [list \
    [file join $contest_root rtl contest contest_reset_sync.sv] \
    [file join $contest_root rtl contest contest_async_axis_fifo.sv] \
    [file join $contest_root rtl contest contest_crypto_cdc_ingress_bridge.sv] \
]
add_files -fileset sim_1 -norecurse [list \
    [file join $contest_root tb contest tb_contest_crypto_cdc_ingress_bridge.sv] \
]

set_property top tb_contest_crypto_cdc_ingress_bridge [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit
