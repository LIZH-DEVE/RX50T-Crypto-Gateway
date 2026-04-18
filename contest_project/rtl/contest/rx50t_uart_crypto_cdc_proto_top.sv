`timescale 1ns/1ps

module rx50t_uart_crypto_cdc_proto_top #(
    parameter integer CLK_HZ                     = 50_000_000,
    parameter integer CDC_FIFO_DEPTH            = 128,
    parameter integer CDC_ALMOST_FULL_MARGIN    = 8,
    parameter integer CRYPTO_SLEEP_HOLDOFF      = 16,
    parameter integer CRYPTO_WAKE_SETTLE_CYCLES = 2
) (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_ingress_tvalid,
    output wire       o_ingress_tready,
    input  wire [7:0] i_ingress_tdata,
    input  wire       i_ingress_tlast,
    input  wire       i_ingress_tuser,
    input  wire       i_link_flush_req,
    output wire       o_cdc_axis_tvalid,
    output wire [7:0] o_cdc_axis_tdata,
    output wire       o_cdc_axis_tlast,
    output wire       o_cdc_axis_tuser,
    output wire       o_cdc_axis_accept,
    output wire       o_axis_tvalid,
    input  wire       i_axis_tready,
    output wire [7:0] o_axis_tdata,
    output wire       o_axis_tlast,
    output wire       o_root_wake_pulse,
    output wire       o_crypto_clk_ce,
    output wire       o_crypto_idle_sync,
    output wire       o_ingress_clk_locked,
    output wire       o_wr_full,
    output wire       o_wr_almost_full,
    output wire       o_rd_empty
);

    wire ingress_clk_w;
    wire ingress_locked_w;

    contest_ingress_clk_gen #(
        .ROOT_CLKIN_PERIOD_NS(1.0e9 / CLK_HZ),
        .BYPASS_MMCM         (CLK_HZ != 50_000_000)
    ) u_clk_gen (
        .i_root_clk    (i_clk),
        .i_rst_n_async (i_rst_n),
        .o_ingress_clk (ingress_clk_w),
        .o_locked      (ingress_locked_w)
    );

    contest_crypto_cdc_proto #(
        .CLK_HZ                    (CLK_HZ),
        .CDC_FIFO_DEPTH            (CDC_FIFO_DEPTH),
        .CDC_ALMOST_FULL_MARGIN    (CDC_ALMOST_FULL_MARGIN),
        .CRYPTO_SLEEP_HOLDOFF      (CRYPTO_SLEEP_HOLDOFF),
        .CRYPTO_WAKE_SETTLE_CYCLES (CRYPTO_WAKE_SETTLE_CYCLES)
    ) u_proto (
        .i_root_clk           (i_clk),
        .i_root_rst_n_async   (i_rst_n),
        .i_ingress_clk        (ingress_clk_w),
        .i_ingress_locked     (ingress_locked_w),
        .i_link_flush_req     (i_link_flush_req),
        .i_cdc_consume_enable (1'b1),
        .s_axis_tvalid        (i_ingress_tvalid),
        .s_axis_tready        (o_ingress_tready),
        .s_axis_tdata         (i_ingress_tdata),
        .s_axis_tlast         (i_ingress_tlast),
        .s_axis_tuser         (i_ingress_tuser),
        .o_cdc_axis_tvalid    (o_cdc_axis_tvalid),
        .o_cdc_axis_tdata     (o_cdc_axis_tdata),
        .o_cdc_axis_tlast     (o_cdc_axis_tlast),
        .o_cdc_axis_tuser     (o_cdc_axis_tuser),
        .o_cdc_axis_accept    (o_cdc_axis_accept),
        .m_axis_tvalid        (o_axis_tvalid),
        .m_axis_tready        (i_axis_tready),
        .m_axis_tdata         (o_axis_tdata),
        .m_axis_tlast         (o_axis_tlast),
        .o_root_wake_pulse    (o_root_wake_pulse),
        .o_crypto_clk_ce      (o_crypto_clk_ce),
        .o_crypto_idle_sync   (o_crypto_idle_sync),
        .o_ingress_ready      (),
        .o_ingress_locked_out (o_ingress_clk_locked),
        .o_wr_full            (o_wr_full),
        .o_wr_almost_full     (o_wr_almost_full),
        .o_rd_empty           (o_rd_empty)
    );

endmodule
