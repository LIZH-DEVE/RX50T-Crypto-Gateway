`timescale 1ns/1ps

module contest_async_mailbox #(
    parameter integer WIDTH = 8
) (
    input  wire             i_src_clk,
    input  wire             i_src_rst_n_async,
    input  wire             i_dst_clk,
    input  wire             i_dst_rst_n_async,
    input  wire             i_link_flush_req,
    input  wire             i_src_valid,
    output wire             o_src_ready,
    input  wire [WIDTH-1:0] i_src_payload,
    output wire             o_dst_valid,
    input  wire             i_dst_ready,
    output wire [WIDTH-1:0] o_dst_payload
);

    wire [0:0] fifo_m_tuser_w;
    wire       fifo_m_tlast_w;
    wire [1:0] wr_level_w;
    wire [1:0] rd_level_w;

    contest_async_axis_fifo #(
        .DATA_W            (WIDTH),
        .USER_W            (1),
        .DEPTH             (2),
        .ALMOST_FULL_MARGIN(1)
    ) u_mailbox_fifo (
        .i_wr_clk        (i_src_clk),
        .i_rd_clk        (i_dst_clk),
        .i_rst_n_async   (i_src_rst_n_async && i_dst_rst_n_async && !i_link_flush_req),
        .s_axis_tvalid   (i_src_valid),
        .s_axis_tready   (o_src_ready),
        .s_axis_tdata    (i_src_payload),
        .s_axis_tlast    (1'b1),
        .s_axis_tuser    (1'b0),
        .m_axis_tvalid   (o_dst_valid),
        .m_axis_tready   (i_dst_ready),
        .m_axis_tdata    (o_dst_payload),
        .m_axis_tlast    (fifo_m_tlast_w),
        .m_axis_tuser    (fifo_m_tuser_w),
        .o_wr_full       (),
        .o_wr_almost_full(),
        .o_rd_empty      (),
        .o_wr_level      (wr_level_w),
        .o_rd_level      (rd_level_w)
    );

endmodule