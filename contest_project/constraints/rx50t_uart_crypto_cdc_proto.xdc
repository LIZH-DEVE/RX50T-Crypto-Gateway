create_clock -period 20.000 [get_ports i_clk]
create_generated_clock -name clk_crypto_gated \
    -source [get_pins u_proto/u_bufgce_crypto/I] \
    -divide_by 1 \
    [get_pins u_proto/u_bufgce_crypto/O]

# Gray-pointer CDC constraints.
# Constrain the synchronizer stage-1 crossings as explicit CDC paths using the
# source Gray-launch cells and the destination sync1 cells.
set afifo_wr_gray_src_cells [get_cells {\
    u_proto/u_bridge/u_afifo/wr_gray_q_reg[0] \
    u_proto/u_bridge/u_afifo/wr_gray_q_reg[1] \
    u_proto/u_bridge/u_afifo/wr_gray_q_reg[2] \
    u_proto/u_bridge/u_afifo/wr_gray_q_reg[3] \
    u_proto/u_bridge/u_afifo/wr_gray_q_reg[4] \
    u_proto/u_bridge/u_afifo/wr_gray_q_reg[5] \
    u_proto/u_bridge/u_afifo/wr_gray_q_reg[6] \
    u_proto/u_bridge/u_afifo/wr_bin_q_reg[7] \
}]
set afifo_wr_gray_sync1_cells [get_cells {\
    u_proto/u_bridge/u_afifo/wr_gray_sync1_q_reg[0] \
    u_proto/u_bridge/u_afifo/wr_gray_sync1_q_reg[1] \
    u_proto/u_bridge/u_afifo/wr_gray_sync1_q_reg[2] \
    u_proto/u_bridge/u_afifo/wr_gray_sync1_q_reg[3] \
    u_proto/u_bridge/u_afifo/wr_gray_sync1_q_reg[4] \
    u_proto/u_bridge/u_afifo/wr_gray_sync1_q_reg[5] \
    u_proto/u_bridge/u_afifo/wr_gray_sync1_q_reg[6] \
    u_proto/u_bridge/u_afifo/wr_gray_sync1_q_reg[7] \
}]

set afifo_rd_gray_src_cells [get_cells {\
    u_proto/u_bridge/u_afifo/rd_gray_q_reg[0] \
    u_proto/u_bridge/u_afifo/rd_gray_q_reg[1] \
    u_proto/u_bridge/u_afifo/rd_gray_q_reg[2] \
    u_proto/u_bridge/u_afifo/rd_gray_q_reg[3] \
    u_proto/u_bridge/u_afifo/rd_gray_q_reg[4] \
    u_proto/u_bridge/u_afifo/rd_gray_q_reg[5] \
    u_proto/u_bridge/u_afifo/rd_gray_q_reg[6] \
    u_proto/u_bridge/u_afifo/rd_bin_q_reg[7] \
}]
set afifo_rd_gray_sync1_cells [get_cells {\
    u_proto/u_bridge/u_afifo/rd_gray_sync1_q_reg[0] \
    u_proto/u_bridge/u_afifo/rd_gray_sync1_q_reg[1] \
    u_proto/u_bridge/u_afifo/rd_gray_sync1_q_reg[2] \
    u_proto/u_bridge/u_afifo/rd_gray_sync1_q_reg[3] \
    u_proto/u_bridge/u_afifo/rd_gray_sync1_q_reg[4] \
    u_proto/u_bridge/u_afifo/rd_gray_sync1_q_reg[5] \
    u_proto/u_bridge/u_afifo/rd_gray_sync1_q_reg[6] \
    u_proto/u_bridge/u_afifo/rd_gray_sync1_q_reg[7] \
}]

set_false_path -from $afifo_wr_gray_src_cells -to $afifo_wr_gray_sync1_cells
set_max_delay -datapath_only 8.000 \
    -from $afifo_wr_gray_src_cells \
    -to $afifo_wr_gray_sync1_cells
set_bus_skew 8.000 \
    -from $afifo_wr_gray_src_cells \
    -to $afifo_wr_gray_sync1_cells

set_false_path -from $afifo_rd_gray_src_cells -to $afifo_rd_gray_sync1_cells
set_max_delay -datapath_only 20.000 \
    -from $afifo_rd_gray_src_cells \
    -to $afifo_rd_gray_sync1_cells
set_bus_skew 20.000 \
    -from $afifo_rd_gray_src_cells \
    -to $afifo_rd_gray_sync1_cells
