create_clock -period 20.000 [get_ports i_clk]
create_generated_clock -name clk_crypto_gated \
    -source [get_pins u_top/u_probe/u_bufgce_crypto/I] \
    -divide_by 1 \
    [get_pins u_top/u_probe/u_bufgce_crypto/O]
create_generated_clock -name clk_ingress_125m \
    -source [get_pins u_top/u_probe/u_ingress_clk_gen/u_mmcm/CLKIN1] \
    -multiply_by 5 -divide_by 2 \
    [get_pins u_top/u_probe/u_ingress_clk_gen/u_bufg_out/O]

set payload_wr_gray_src_cells [get_cells {\
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[0] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[1] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[2] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[3] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[4] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[5] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[6] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[7] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[8] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_q_reg[9] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_bin_q_reg[10] \
}]
set payload_wr_gray_sync1_cells [get_cells {\
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[0] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[1] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[2] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[3] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[4] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[5] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[6] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[7] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[8] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[9] \
    u_top/u_probe/u_payload_bridge/u_afifo/wr_gray_sync1_q_reg[10] \
}]
set payload_rd_gray_src_cells [get_cells {\
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[0] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[1] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[2] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[3] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[4] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[5] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[6] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[7] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[8] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_q_reg[9] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_bin_q_reg[10] \
}]
set payload_rd_gray_sync1_cells [get_cells {\
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[0] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[1] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[2] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[3] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[4] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[5] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[6] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[7] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[8] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[9] \
    u_top/u_probe/u_payload_bridge/u_afifo/rd_gray_sync1_q_reg[10] \
}]

set ingress_meta_wr_gray_src_cells [get_cells {\
    u_top/u_probe/u_ingress_meta_mailbox/u_mailbox_fifo/wr_gray_q_reg[0] \
    u_top/u_probe/u_ingress_meta_mailbox/u_mailbox_fifo/wr_bin_q_reg[1] \
}]
set ingress_meta_wr_gray_sync1_cells [get_cells {\
    u_top/u_probe/u_ingress_meta_mailbox/u_mailbox_fifo/wr_gray_sync1_q_reg[0] \
    u_top/u_probe/u_ingress_meta_mailbox/u_mailbox_fifo/wr_gray_sync1_q_reg[1] \
}]
set ingress_meta_rd_gray_src_cells [get_cells {\
    u_top/u_probe/u_ingress_meta_mailbox/u_mailbox_fifo/rd_gray_q_reg[0] \
    u_top/u_probe/u_ingress_meta_mailbox/u_mailbox_fifo/rd_bin_q_reg[1] \
}]
set ingress_meta_rd_gray_sync1_cells [get_cells {\
    u_top/u_probe/u_ingress_meta_mailbox/u_mailbox_fifo/rd_gray_sync1_q_reg[0] \
    u_top/u_probe/u_ingress_meta_mailbox/u_mailbox_fifo/rd_gray_sync1_q_reg[1] \
}]

set action_wr_gray_src_cells [get_cells {\
    u_top/u_probe/u_action_mailbox/u_mailbox_fifo/wr_gray_q_reg[0] \
    u_top/u_probe/u_action_mailbox/u_mailbox_fifo/wr_bin_q_reg[1] \
}]
set action_wr_gray_sync1_cells [get_cells {\
    u_top/u_probe/u_action_mailbox/u_mailbox_fifo/wr_gray_sync1_q_reg[0] \
    u_top/u_probe/u_action_mailbox/u_mailbox_fifo/wr_gray_sync1_q_reg[1] \
}]
set action_rd_gray_src_cells [get_cells {\
    u_top/u_probe/u_action_mailbox/u_mailbox_fifo/rd_gray_q_reg[0] \
    u_top/u_probe/u_action_mailbox/u_mailbox_fifo/rd_bin_q_reg[1] \
}]
set action_rd_gray_sync1_cells [get_cells {\
    u_top/u_probe/u_action_mailbox/u_mailbox_fifo/rd_gray_sync1_q_reg[0] \
    u_top/u_probe/u_action_mailbox/u_mailbox_fifo/rd_gray_sync1_q_reg[1] \
}]

set egress_wr_gray_src_cells [get_cells {\
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_q_reg[0] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_q_reg[1] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_q_reg[2] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_q_reg[3] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_q_reg[4] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_q_reg[5] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_q_reg[6] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_bin_q_reg[7] \
}]
set egress_wr_gray_sync1_cells [get_cells {\
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_sync1_q_reg[0] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_sync1_q_reg[1] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_sync1_q_reg[2] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_sync1_q_reg[3] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_sync1_q_reg[4] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_sync1_q_reg[5] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_sync1_q_reg[6] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/wr_gray_sync1_q_reg[7] \
}]
set egress_rd_gray_src_cells [get_cells {\
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_q_reg[0] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_q_reg[1] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_q_reg[2] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_q_reg[3] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_q_reg[4] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_q_reg[5] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_q_reg[6] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_bin_q_reg[7] \
}]
set egress_rd_gray_sync1_cells [get_cells {\
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_sync1_q_reg[0] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_sync1_q_reg[1] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_sync1_q_reg[2] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_sync1_q_reg[3] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_sync1_q_reg[4] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_sync1_q_reg[5] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_sync1_q_reg[6] \
    u_top/u_probe/u_tx_egress_bridge/u_afifo/rd_gray_sync1_q_reg[7] \
}]

set_max_delay -datapath_only 20.000 -from $payload_wr_gray_src_cells -to $payload_wr_gray_sync1_cells
set_bus_skew 20.000 -from $payload_wr_gray_src_cells -to $payload_wr_gray_sync1_cells

set_max_delay -datapath_only 8.000 -from $payload_rd_gray_src_cells -to $payload_rd_gray_sync1_cells
set_bus_skew 8.000 -from $payload_rd_gray_src_cells -to $payload_rd_gray_sync1_cells

set_max_delay -datapath_only 20.000 -from $ingress_meta_wr_gray_src_cells -to $ingress_meta_wr_gray_sync1_cells
set_bus_skew 20.000 -from $ingress_meta_wr_gray_src_cells -to $ingress_meta_wr_gray_sync1_cells

set_max_delay -datapath_only 8.000 -from $ingress_meta_rd_gray_src_cells -to $ingress_meta_rd_gray_sync1_cells
set_bus_skew 8.000 -from $ingress_meta_rd_gray_src_cells -to $ingress_meta_rd_gray_sync1_cells

set_max_delay -datapath_only 20.000 -from $action_wr_gray_src_cells -to $action_wr_gray_sync1_cells
set_bus_skew 20.000 -from $action_wr_gray_src_cells -to $action_wr_gray_sync1_cells

set_max_delay -datapath_only 20.000 -from $action_rd_gray_src_cells -to $action_rd_gray_sync1_cells
set_bus_skew 20.000 -from $action_rd_gray_src_cells -to $action_rd_gray_sync1_cells

set_max_delay -datapath_only 8.000 -from $egress_wr_gray_src_cells -to $egress_wr_gray_sync1_cells
set_bus_skew 8.000 -from $egress_wr_gray_src_cells -to $egress_wr_gray_sync1_cells

set_max_delay -datapath_only 20.000 -from $egress_rd_gray_src_cells -to $egress_rd_gray_sync1_cells
set_bus_skew 20.000 -from $egress_rd_gray_src_cells -to $egress_rd_gray_sync1_cells

set_property IOSTANDARD LVCMOS33 [get_ports i_clk]
set_property PACKAGE_PIN Y18 [get_ports i_clk]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property IOSTANDARD LVCMOS33 [get_ports i_rst_n]
set_property PACKAGE_PIN J20 [get_ports i_rst_n]

# Second-pass UART mapping.
# The first-pass mapping (i_uart_rx=J1, o_uart_tx=K1) produced no echo
# across the enumerated host UART ports during board bring-up, so this
# variant swaps J1/K1.
set_property IOSTANDARD LVCMOS33 [get_ports i_uart_rx]
set_property PACKAGE_PIN K1 [get_ports i_uart_rx]

set_property IOSTANDARD LVCMOS33 [get_ports o_uart_tx]
set_property PACKAGE_PIN J1 [get_ports o_uart_tx]
