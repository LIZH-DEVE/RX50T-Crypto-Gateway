set script_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file dirname $script_dir]]

if {[llength $argv] >= 1} {
    set part_name [lindex $argv 0]
} else {
    set part_name "xc7a50tfgg484-1"
}

set project_name "rx50t_uart_echo"
set project_dir [file normalize [file join $project_root "build" $project_name]]

file mkdir [file join $project_root "build"]

create_project $project_name $project_dir -part $part_name -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -norecurse [list \
    [file join $project_root "rtl" "contest" "contest_uart_rx.sv"] \
    [file join $project_root "rtl" "contest" "contest_uart_tx.sv"] \
    [file join $project_root "rtl" "contest" "contest_uart_fifo.sv"] \
    [file join $project_root "rtl" "contest" "contest_uart_io.sv"] \
    [file join $project_root "rtl" "contest" "rx50t_uart_echo_top.sv"] \
    [file join $project_root "rtl" "contest" "rx50t_uart_echo_board_top.sv"] \
]

add_files -fileset constrs_1 -norecurse [list \
    [file join $project_root "constraints" "rx50t_uart_echo.xdc"] \
]

add_files -fileset sim_1 -norecurse [list \
    [file join $project_root "tb" "contest" "tb_uart_echo.sv"] \
]

set_property top rx50t_uart_echo_board_top [get_filesets sources_1]
set_property top tb_uart_echo [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1

open_run synth_1
report_utilization -file [file join $project_dir "rx50t_uart_echo_utilization_synth.rpt"]
report_timing_summary -file [file join $project_dir "rx50t_uart_echo_timing_synth.rpt"]

puts "PROJECT_DONE=$project_dir"
puts "PART_USED=$part_name"
