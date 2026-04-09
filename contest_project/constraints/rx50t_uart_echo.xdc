create_clock -period 20.000 [get_ports i_clk]
set_property IOSTANDARD LVCMOS33 [get_ports i_clk]
set_property PACKAGE_PIN Y18 [get_ports i_clk]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property IOSTANDARD LVCMOS33 [get_ports i_rst_n]
set_property PACKAGE_PIN J20 [get_ports i_rst_n]

# Second-pass UART mapping.
# The first-pass mapping (i_uart_rx=J1, o_uart_tx=K1) produced no echo
# on COM11/COM12/COM13 during board bring-up, so this variant swaps J1/K1.
set_property IOSTANDARD LVCMOS33 [get_ports i_uart_rx]
set_property PACKAGE_PIN K1 [get_ports i_uart_rx]

set_property IOSTANDARD LVCMOS33 [get_ports o_uart_tx]
set_property PACKAGE_PIN J1 [get_ports o_uart_tx]
