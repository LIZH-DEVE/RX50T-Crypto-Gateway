`timescale 1ns/1ps

module contest_crypto_cdc_ingress_bridge #(
    parameter integer DATA_W             = 8,
    parameter integer USER_W             = 1,
    parameter integer DEPTH              = 128,
    parameter integer ALMOST_FULL_MARGIN = 8
) (
    input  wire                  i_ingress_clk,
    input  wire                  i_ingress_rst_n_async,
    input  wire                  i_root_clk,
    input  wire                  i_root_rst_n_async,
    input  wire                  i_crypto_clk,
    input  wire                  i_crypto_rst_n_async,
    input  wire                  i_link_flush_req,

    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire [DATA_W-1:0]     s_axis_tdata,
    input  wire                  s_axis_tlast,
    input  wire [USER_W-1:0]     s_axis_tuser,

    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire [DATA_W-1:0]     m_axis_tdata,
    output wire                  m_axis_tlast,
    output wire [USER_W-1:0]     m_axis_tuser,

    output wire                  o_root_wake_pulse,
    output wire                  o_wr_full,
    output wire                  o_wr_almost_full,
    output wire                  o_rd_empty
);

    wire ingress_link_rst_n_async = i_ingress_rst_n_async && !i_link_flush_req;
    wire root_link_rst_n_async    = i_root_rst_n_async && !i_link_flush_req;
    wire fifo_link_rst_n_async    = i_ingress_rst_n_async && i_crypto_rst_n_async && !i_link_flush_req;

    wire ingress_rst_n_sync;
    wire root_rst_n_sync;
    wire crypto_rst_n_sync;

    reg                  ingress_local_rst_n_q = 1'b0;
    reg                  root_local_rst_n_q = 1'b0;
    reg                  crypto_local_rst_n_q = 1'b0;
    reg                  slice_valid_q;
    reg  [DATA_W-1:0]    slice_data_q;
    reg                  slice_last_q;
    reg  [USER_W-1:0]    slice_user_q;
    reg                  wake_req_q;
    reg                  out_valid_q;
    reg                  crypto_port_active_q;
    reg  [DATA_W-1:0]    out_data_q;
    reg                  out_last_q;
    reg  [USER_W-1:0]    out_user_q;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg wake_req_sync1_q;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg wake_req_sync2_q;
    reg                  wake_req_sync3_q;

    wire fifo_s_tvalid_w;
    wire fifo_s_tready_w;
    wire fifo_write_fire_w;
    wire ingress_accept_w;
    wire slice_push_w;
    wire slice_pop_w;
    wire fifo_m_tvalid_w;
    wire fifo_m_tready_w;
    wire [DATA_W-1:0] fifo_m_tdata_w;
    wire fifo_m_tlast_w;
    wire [USER_W-1:0] fifo_m_tuser_w;
    wire [($clog2(DEPTH)):0] wr_level_w;
    wire [($clog2(DEPTH)):0] rd_level_w;
    wire wake_req_clear_w;

    contest_reset_sync u_ingress_reset_sync (
        .i_clk        (i_ingress_clk),
        .i_rst_n_async(ingress_link_rst_n_async),
        .o_rst_n_sync (ingress_rst_n_sync)
    );

    contest_reset_sync u_root_reset_sync (
        .i_clk        (i_root_clk),
        .i_rst_n_async(root_link_rst_n_async),
        .o_rst_n_sync (root_rst_n_sync)
    );

    contest_reset_sync u_crypto_reset_sync (
        .i_clk        (i_crypto_clk),
        .i_rst_n_async(fifo_link_rst_n_async),
        .o_rst_n_sync (crypto_rst_n_sync)
    );

    assign fifo_s_tvalid_w    = slice_valid_q;
    assign fifo_write_fire_w  = fifo_s_tvalid_w && fifo_s_tready_w;
    assign ingress_accept_w   = ingress_local_rst_n_q && (!slice_valid_q || fifo_s_tready_w);
    assign s_axis_tready      = ingress_rst_n_sync && ingress_accept_w;
    assign slice_push_w       = s_axis_tvalid && ingress_accept_w;
    assign slice_pop_w        = slice_valid_q && fifo_s_tready_w;
    assign fifo_m_tready_w    = crypto_local_rst_n_q && crypto_port_active_q && (!out_valid_q || m_axis_tready);
    assign wake_req_clear_w    = !slice_valid_q && (wr_level_w == {($clog2(DEPTH) + 1){1'b0}});
    assign m_axis_tvalid      = crypto_rst_n_sync && crypto_local_rst_n_q && out_valid_q;
    assign m_axis_tdata       = out_data_q;
    assign m_axis_tlast       = out_last_q;
    assign m_axis_tuser       = out_user_q;

    always @(posedge i_ingress_clk) begin
        if (!ingress_rst_n_sync) begin
            ingress_local_rst_n_q <= 1'b0;
        end else begin
            ingress_local_rst_n_q <= 1'b1;
        end
    end

    always @(posedge i_root_clk) begin
        if (!root_rst_n_sync) begin
            root_local_rst_n_q <= 1'b0;
        end else begin
            root_local_rst_n_q <= 1'b1;
        end
    end

    always @(posedge i_crypto_clk) begin
        if (!crypto_rst_n_sync) begin
            crypto_local_rst_n_q <= 1'b0;
        end else begin
            crypto_local_rst_n_q <= 1'b1;
        end
    end

    always @(posedge i_ingress_clk) begin
        if (!ingress_local_rst_n_q) begin
            slice_valid_q        <= 1'b0;
            slice_data_q         <= {DATA_W{1'b0}};
            slice_last_q         <= 1'b0;
            slice_user_q         <= {USER_W{1'b0}};
            wake_req_q           <= 1'b0;
        end else begin
            case ({slice_push_w, slice_pop_w})
                2'b10,
                2'b11: begin
                    slice_valid_q <= 1'b1;
                    slice_data_q  <= s_axis_tdata;
                    slice_last_q  <= s_axis_tlast;
                    slice_user_q  <= s_axis_tuser;
                end
                2'b01: begin
                    slice_valid_q <= 1'b0;
                end
                default: begin
                    slice_valid_q <= slice_valid_q;
                end
            endcase

            if (slice_push_w || fifo_write_fire_w) begin
                wake_req_q <= 1'b1;
            end else if (wake_req_clear_w) begin
                wake_req_q <= 1'b0;
            end else begin
                wake_req_q <= wake_req_q;
            end
        end
    end

    always @(posedge i_root_clk) begin
        if (!root_local_rst_n_q) begin
            wake_req_sync1_q <= 1'b0;
            wake_req_sync2_q <= 1'b0;
            wake_req_sync3_q <= 1'b0;
        end else begin
            wake_req_sync1_q <= wake_req_q;
            wake_req_sync2_q <= wake_req_sync1_q;
            wake_req_sync3_q <= wake_req_sync2_q;
        end
    end

    always @(posedge i_crypto_clk) begin
        if (!crypto_local_rst_n_q) begin
            out_valid_q         <= 1'b0;
            out_data_q          <= {DATA_W{1'b0}};
            out_last_q          <= 1'b0;
            out_user_q          <= {USER_W{1'b0}};
            crypto_port_active_q <= 1'b0;
        end else begin
            crypto_port_active_q <= 1'b1;
            if (fifo_m_tready_w) begin
                out_valid_q <= fifo_m_tvalid_w;
                if (fifo_m_tvalid_w) begin
                    out_data_q <= fifo_m_tdata_w;
                    out_last_q <= fifo_m_tlast_w;
                    out_user_q <= fifo_m_tuser_w;
                end
            end
        end
    end

    assign o_root_wake_pulse = wake_req_sync2_q && !wake_req_sync3_q;

    contest_async_axis_fifo #(
        .DATA_W            (DATA_W),
        .USER_W            (USER_W),
        .DEPTH             (DEPTH),
        .ALMOST_FULL_MARGIN(ALMOST_FULL_MARGIN)
    ) u_afifo (
        .i_wr_clk         (i_ingress_clk),
        .i_rd_clk         (i_crypto_clk),
        .i_rst_n_async    (fifo_link_rst_n_async),
        .s_axis_tvalid    (fifo_s_tvalid_w),
        .s_axis_tready    (fifo_s_tready_w),
        .s_axis_tdata     (slice_data_q),
        .s_axis_tlast     (slice_last_q),
        .s_axis_tuser     (slice_user_q),
        .m_axis_tvalid    (fifo_m_tvalid_w),
        .m_axis_tready    (fifo_m_tready_w),
        .m_axis_tdata     (fifo_m_tdata_w),
        .m_axis_tlast     (fifo_m_tlast_w),
        .m_axis_tuser     (fifo_m_tuser_w),
        .o_wr_full        (o_wr_full),
        .o_wr_almost_full (o_wr_almost_full),
        .o_rd_empty       (o_rd_empty),
        .o_wr_level       (wr_level_w),
        .o_rd_level       (rd_level_w)
    );

endmodule
