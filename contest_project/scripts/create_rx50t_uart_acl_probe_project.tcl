set project_dir [file normalize "D:/FPGAhanjia/jichuangsai/contest_project/build/rx50t_uart_acl_probe"]
file mkdir $project_dir

create_project rx50t_uart_acl_probe $project_dir -part xc7a50tfgg484-1 -force

add_files -norecurse {
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_uart_rx.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_uart_tx.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_uart_fifo.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_parser_core.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_acl_core.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/contest_uart_acl_probe.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/rx50t_uart_acl_probe_top.sv
    D:/FPGAhanjia/jichuangsai/contest_project/rtl/contest/rx50t_uart_acl_probe_board_top.sv
}

add_files -fileset constrs_1 -norecurse {
    D:/FPGAhanjia/jichuangsai/contest_project/constraints/rx50t_uart_echo.xdc
}

add_files -fileset sim_1 -norecurse {
    D:/FPGAhanjia/jichuangsai/contest_project/tb/contest/tb_uart_acl_probe.sv
}

set_property top rx50t_uart_acl_probe_board_top [current_fileset]
set_property top tb_uart_acl_probe [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
open_run synth_1
report_utilization -file [file join $project_dir rx50t_uart_acl_probe_util_synth.rpt]
report_timing_summary -file [file join $project_dir rx50t_uart_acl_probe_timing_synth.rpt]

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
report_drc -file [file join $project_dir rx50t_uart_acl_probe_drc_impl.rpt]
report_timing_summary -file [file join $project_dir rx50t_uart_acl_probe_timing_impl.rpt]
report_utilization -file [file join $project_dir rx50t_uart_acl_probe_util_impl.rpt]
