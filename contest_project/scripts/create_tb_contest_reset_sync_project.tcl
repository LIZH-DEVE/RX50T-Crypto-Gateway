set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set contest_root [file join $repo_root contest_project]

if {[info exists ::env(RX50T_RESET_SYNC_SIM_DIR)] && $::env(RX50T_RESET_SYNC_SIM_DIR) ne ""} {
    set project_dir [file normalize $::env(RX50T_RESET_SYNC_SIM_DIR)]
} else {
    set project_dir [file normalize [file join $contest_root build sim_tb_contest_reset_sync]]
}
file mkdir $project_dir

set run_dir [file normalize [file join $project_dir xsim_cli]]
file mkdir $run_dir
set prev_dir [pwd]
cd $run_dir

set rtl_files [list \
    [file join $contest_root rtl contest contest_reset_sync.sv] \
    [file join $contest_root tb contest tb_contest_reset_sync.sv] \
]

if {[catch {exec xvlog -sv {*}$rtl_files} result options]} {
    puts $result
    cd $prev_dir
    return -options $options $result
}
puts $result

if {[catch {exec xelab tb_contest_reset_sync -s tb_contest_reset_sync_behav --debug typical} result options]} {
    puts $result
    cd $prev_dir
    return -options $options $result
}
puts $result

if {[catch {exec xsim tb_contest_reset_sync_behav -runall} result options]} {
    puts $result
    cd $prev_dir
    return -options $options $result
}
puts $result

cd $prev_dir
exit
