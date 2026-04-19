`timescale 1ns/1ps

module contest_uart_cdc_egress_bridge #(
    parameter integer EGRESS_CLK_HZ       = 125_000_000,
    parameter integer BAUD                = 115200,
    parameter integer DEPTH               = 128,
    parameter integer ALMOST_FULL_MARGIN  = 8
) (
    input  wire                   i_root_clk,
    input  wire                   i_root_rst_n_async,
    input  wire                   i_egress_clk,
    input  wire                   i_egress_rst_n_async,
    input  wire                   i_valid,
    output wire                   o_ready,
    input  wire [7:0]             i_data,
    output wire                   o_uart_tx,
    output wire                   o_wr_full,
    output wire                   o_wr_almost_full,
    output wire                   o_rd_empty,
    output wire [$clog2(DEPTH):0] o_wr_level
);

    localparam integer WR_LEVEL_W = $clog2(DEPTH) + 1;

    wire link_rst_n_async = i_root_rst_n_async && i_egress_rst_n_async;
    wire root_rst_n_sync;
    wire egress_rst_n_sync;

    reg root_local_rst_n_q   = 1'b0;
    reg egress_local_rst_n_q = 1'b0;
    reg tx_domain_ready_q    = 1'b0;
    reg egress_ready_pulse_q = 1'b0;

    wire egress_ready_pulse_root_w;
    wire skid_rst_n_w;
    wire skid_s_ready_w;
    wire skid_m_valid_w;
    wire [7:0] skid_m_data_w;
    wire afifo_s_tready_w;
    wire afifo_m_tvalid_w;
    wire afifo_m_tready_w;
    wire [7:0] afifo_m_tdata_w;
    wire [WR_LEVEL_W-1:0] afifo_wr_level_w;
    wire [WR_LEVEL_W-1:0] afifo_rd_level_w;

    contest_reset_sync u_root_reset_sync (
        .i_clk        (i_root_clk),
        .i_rst_n_async(link_rst_n_async),
        .o_rst_n_sync (root_rst_n_sync)
    );

    contest_reset_sync u_egress_reset_sync (
        .i_clk        (i_egress_clk),
        .i_rst_n_async(link_rst_n_async),
        .o_rst_n_sync (egress_rst_n_sync)
    );

    contest_async_pulse u_egress_ready_pulse (
        .i_src_clk        (i_egress_clk),
        .i_src_rst_n_async(link_rst_n_async),
        .i_dst_clk        (i_root_clk),
        .i_dst_rst_n_async(link_rst_n_async),
        .i_pulse          (egress_ready_pulse_q),
        .o_pulse          (egress_ready_pulse_root_w)
    );

    always @(posedge i_root_clk) begin
        if (!root_rst_n_sync) begin
            root_local_rst_n_q <= 1'b0;
            tx_domain_ready_q  <= 1'b0;
        end else begin
            root_local_rst_n_q <= 1'b1;
            if (egress_ready_pulse_root_w) begin
                tx_domain_ready_q <= 1'b1;
            end
        end
    end

    always @(posedge i_egress_clk) begin
        if (!egress_rst_n_sync) begin
            egress_local_rst_n_q <= 1'b0;
            egress_ready_pulse_q <= 1'b0;
        end else begin
            egress_ready_pulse_q <= !egress_local_rst_n_q;
            egress_local_rst_n_q <= 1'b1;
        end
    end

    assign skid_rst_n_w             = root_local_rst_n_q && tx_domain_ready_q;

    contest_byte_skid_buffer u_skid (
        .i_clk  (i_root_clk),
        .i_rst_n(skid_rst_n_w),
        .s_valid(i_valid),
        .s_ready(skid_s_ready_w),
        .s_data (i_data),
        .m_valid(skid_m_valid_w),
        .m_ready(afifo_s_tready_w),
        .m_data (skid_m_data_w)
    );

    contest_async_axis_fifo #(
        .DATA_W            (8),
        .USER_W            (1),
        .DEPTH             (DEPTH),
        .ALMOST_FULL_MARGIN(ALMOST_FULL_MARGIN)
    ) u_afifo (
        .i_wr_clk         (i_root_clk),
        .i_rd_clk         (i_egress_clk),
        .i_rst_n_async    (link_rst_n_async),
        .s_axis_tvalid    (skid_m_valid_w),
        .s_axis_tready    (afifo_s_tready_w),
        .s_axis_tdata     (skid_m_data_w),
        .s_axis_tlast     (1'b0),
        .s_axis_tuser     (1'b0),
        .m_axis_tvalid    (afifo_m_tvalid_w),
        .m_axis_tready    (afifo_m_tready_w),
        .m_axis_tdata     (afifo_m_tdata_w),
        .m_axis_tlast     (),
        .m_axis_tuser     (),
        .o_wr_full        (o_wr_full),
        .o_wr_almost_full (o_wr_almost_full),
        .o_rd_empty       (o_rd_empty),
        .o_wr_level       (afifo_wr_level_w),
        .o_rd_level       (afifo_rd_level_w)
    );

    contest_uart_tx #(
        .CLK_HZ(EGRESS_CLK_HZ),
        .BAUD  (BAUD)
    ) u_uart_tx (
        .i_clk    (i_egress_clk),
        .i_rst_n  (egress_local_rst_n_q),
        .i_valid  (afifo_m_tvalid_w),
        .i_data   (afifo_m_tdata_w),
        .o_ready  (afifo_m_tready_w),
        .o_uart_tx(o_uart_tx)
    );

    assign o_ready    = tx_domain_ready_q && skid_s_ready_w;
    assign o_wr_level = afifo_wr_level_w;

endmodule
