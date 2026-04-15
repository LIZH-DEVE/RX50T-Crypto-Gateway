set project_dir [file normalize "D:/FPGAhanjia/jichuangsai/contest_project/build/sim_tb_contest_acl_axis_core"]
file mkdir $project_dir
create_project sim_tb_contest_acl_axis_core $project_dir -part xc7a50tfgg484-1 -force
add_files -norecurse {
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_acl_axis_core.sv
}
add_files -fileset sim_1 -norecurse {
    D:/FPGAhanjia/jichuangsai/contest_project/tb/contest/tb_contest_acl_axis_core.sv
}
set_property top tb_contest_acl_axis_core [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit
