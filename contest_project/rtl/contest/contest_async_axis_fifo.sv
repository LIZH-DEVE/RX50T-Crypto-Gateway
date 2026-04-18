`timescale 1ns/1ps

module contest_async_axis_fifo #(
    parameter integer DATA_W             = 8,
    parameter integer USER_W             = 1,
    parameter integer DEPTH              = 128,
    parameter integer ALMOST_FULL_MARGIN = 8
) (
    input  wire                   i_wr_clk,
    input  wire                   i_rd_clk,
    input  wire                   i_rst_n_async,

    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire [DATA_W-1:0]      s_axis_tdata,
    input  wire                   s_axis_tlast,
    input  wire [USER_W-1:0]      s_axis_tuser,

    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire [DATA_W-1:0]      m_axis_tdata,
    output wire                   m_axis_tlast,
    output wire [USER_W-1:0]      m_axis_tuser,

    output wire                   o_wr_full,
    output wire                   o_wr_almost_full,
    output wire                   o_rd_empty,
    output wire [$clog2(DEPTH):0] o_wr_level,
    output wire [$clog2(DEPTH):0] o_rd_level
);

    localparam integer ADDR_W    = $clog2(DEPTH);
    localparam integer PAYLOAD_W = DATA_W + USER_W + 1;

    function automatic [ADDR_W:0] bin2gray(input [ADDR_W:0] bin_value);
        begin
            bin2gray = (bin_value >> 1) ^ bin_value;
        end
    endfunction

    function automatic [ADDR_W:0] gray2bin(input [ADDR_W:0] gray_value);
        integer idx;
        begin
            gray2bin[ADDR_W] = gray_value[ADDR_W];
            for (idx = ADDR_W - 1; idx >= 0; idx = idx - 1) begin
                gray2bin[idx] = gray2bin[idx + 1] ^ gray_value[idx];
            end
        end
    endfunction

    initial begin
        if ((DEPTH < 2) || ((DEPTH & (DEPTH - 1)) != 0)) begin
            $error("contest_async_axis_fifo DEPTH must be a power of two, got %0d", DEPTH);
            $finish;
        end
        if ((ALMOST_FULL_MARGIN < 1) || (ALMOST_FULL_MARGIN >= DEPTH)) begin
            $error("contest_async_axis_fifo ALMOST_FULL_MARGIN must be in [1, DEPTH-1], got %0d", ALMOST_FULL_MARGIN);
            $finish;
        end
    end

    reg [PAYLOAD_W-1:0] mem_q [0:DEPTH-1];

    wire wr_rst_n_sync;
    wire rd_rst_n_sync;

    reg             wr_local_rst_n_q = 1'b0;
    reg             rd_local_rst_n_q = 1'b0;
    reg  [ADDR_W:0] wr_bin_q = {ADDR_W + 1{1'b0}};
    reg  [ADDR_W:0] wr_gray_q = {ADDR_W + 1{1'b0}};
    reg  [ADDR_W:0] rd_bin_q = {ADDR_W + 1{1'b0}};
    reg  [ADDR_W:0] rd_gray_q = {ADDR_W + 1{1'b0}};
    reg             rd_payload_valid_q = 1'b0;
    reg  [PAYLOAD_W-1:0] rd_payload_q = {PAYLOAD_W{1'b0}};
    (* DONT_TOUCH = "TRUE", KEEP = "TRUE" *) reg wr_port_active_q = 1'b0;
    (* DONT_TOUCH = "TRUE", KEEP = "TRUE" *) reg rd_port_active_q = 1'b0;

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [ADDR_W:0] rd_gray_sync1_q = {ADDR_W + 1{1'b0}};
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [ADDR_W:0] rd_gray_sync2_q = {ADDR_W + 1{1'b0}};
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [ADDR_W:0] wr_gray_sync1_q = {ADDR_W + 1{1'b0}};
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [ADDR_W:0] wr_gray_sync2_q = {ADDR_W + 1{1'b0}};

    wire [ADDR_W:0] rd_bin_sync_w;
    wire [ADDR_W:0] wr_bin_sync_w;
    wire [ADDR_W:0] wr_level_raw_w;
    wire [ADDR_W:0] rd_level_raw_w;
    wire [ADDR_W:0] rd_visible_level_w;
    wire            wr_full_raw_w;
    wire            wr_almost_full_raw_w;
    wire            rd_empty_raw_w;
    wire            wr_accept_w;
    wire            rd_accept_w;
    wire            wr_fire_w;
    wire            rd_fire_w;
    wire            rd_load_w;
    wire            rd_drain_only_w;
    wire [PAYLOAD_W-1:0] wr_payload_w;
    wire [ADDR_W:0] rd_bin_next_w;

    contest_reset_sync u_wr_reset_sync (
        .i_clk        (i_wr_clk),
        .i_rst_n_async(i_rst_n_async),
        .o_rst_n_sync (wr_rst_n_sync)
    );

    contest_reset_sync u_rd_reset_sync (
        .i_clk        (i_rd_clk),
        .i_rst_n_async(i_rst_n_async),
        .o_rst_n_sync (rd_rst_n_sync)
    );

    assign rd_bin_sync_w = gray2bin(rd_gray_sync2_q);
    assign wr_bin_sync_w = gray2bin(wr_gray_sync2_q);

    assign wr_level_raw_w       = wr_bin_q - rd_bin_sync_w;
    assign rd_level_raw_w       = wr_bin_sync_w - rd_bin_q;
    assign rd_visible_level_w   = rd_level_raw_w + {{ADDR_W{1'b0}}, rd_payload_valid_q};
    assign wr_full_raw_w        = (wr_level_raw_w == DEPTH);
    assign wr_almost_full_raw_w = (wr_level_raw_w >= (DEPTH - ALMOST_FULL_MARGIN));
    assign rd_empty_raw_w       = (rd_visible_level_w == {ADDR_W + 1{1'b0}});

    assign o_wr_level       = (wr_rst_n_sync && wr_local_rst_n_q) ? wr_level_raw_w : {ADDR_W + 1{1'b0}};
    assign o_rd_level       = (rd_rst_n_sync && rd_local_rst_n_q) ? rd_visible_level_w : {ADDR_W + 1{1'b0}};
    assign o_wr_full        = wr_rst_n_sync && wr_local_rst_n_q && wr_full_raw_w;
    assign o_wr_almost_full = wr_rst_n_sync && wr_local_rst_n_q && wr_almost_full_raw_w;
    assign o_rd_empty       = !rd_rst_n_sync || !rd_local_rst_n_q || rd_empty_raw_w;

    assign wr_accept_w   = wr_local_rst_n_q && wr_port_active_q && !wr_almost_full_raw_w;
    assign s_axis_tready = wr_rst_n_sync && wr_accept_w;
    assign wr_fire_w     = s_axis_tvalid && wr_accept_w;
    assign wr_payload_w  = {s_axis_tlast, s_axis_tuser, s_axis_tdata};

    assign m_axis_tvalid = rd_rst_n_sync && rd_local_rst_n_q && rd_payload_valid_q;
    assign m_axis_tdata  = rd_payload_q[DATA_W-1:0];
    assign m_axis_tuser  = rd_payload_q[DATA_W + USER_W - 1:DATA_W];
    assign m_axis_tlast  = rd_payload_q[PAYLOAD_W-1];
    assign rd_accept_w     = rd_local_rst_n_q && rd_port_active_q && m_axis_tready;
    assign rd_fire_w       = rd_payload_valid_q && rd_accept_w;

    assign rd_load_w       = rd_accept_w &&
                             ((!rd_payload_valid_q && (rd_level_raw_w != {ADDR_W + 1{1'b0}})) ||
                              ( rd_fire_w         && (rd_level_raw_w != {ADDR_W + 1{1'b0}})));
    assign rd_drain_only_w = rd_fire_w && (rd_level_raw_w == {ADDR_W + 1{1'b0}});
    assign rd_bin_next_w   = rd_bin_q + {{ADDR_W{1'b0}}, 1'b1};

    always @(posedge i_wr_clk) begin
        if (!wr_rst_n_sync) begin
            wr_local_rst_n_q <= 1'b0;
        end else begin
            wr_local_rst_n_q <= 1'b1;
        end
    end

    always @(posedge i_rd_clk) begin
        if (!rd_rst_n_sync) begin
            rd_local_rst_n_q <= 1'b0;
        end else begin
            rd_local_rst_n_q <= 1'b1;
        end
    end

    always @(posedge i_wr_clk) begin
        if (wr_fire_w) begin
            mem_q[wr_bin_q[ADDR_W-1:0]] <= wr_payload_w;
        end
    end

    always @(posedge i_wr_clk) begin
        if (!wr_local_rst_n_q) begin
            wr_bin_q        <= {ADDR_W + 1{1'b0}};
            wr_gray_q       <= {ADDR_W + 1{1'b0}};
            rd_gray_sync1_q <= {ADDR_W + 1{1'b0}};
            rd_gray_sync2_q <= {ADDR_W + 1{1'b0}};
            wr_port_active_q <= 1'b0;
        end else begin
            rd_gray_sync1_q  <= rd_gray_q;
            rd_gray_sync2_q  <= rd_gray_sync1_q;
            wr_port_active_q <= 1'b1;

            if (wr_fire_w) begin
                wr_bin_q  <= wr_bin_q + {{ADDR_W{1'b0}}, 1'b1};
                wr_gray_q <= bin2gray(wr_bin_q + {{ADDR_W{1'b0}}, 1'b1});
            end
        end
    end

    always @(posedge i_rd_clk) begin
        if (rd_load_w) begin
            rd_payload_q <= mem_q[rd_bin_q[ADDR_W-1:0]];
        end
    end

    always @(posedge i_rd_clk) begin
        if (!rd_local_rst_n_q) begin
            rd_bin_q           <= {ADDR_W + 1{1'b0}};
            rd_gray_q          <= {ADDR_W + 1{1'b0}};
            rd_payload_valid_q <= 1'b0;
            wr_gray_sync1_q    <= {ADDR_W + 1{1'b0}};
            wr_gray_sync2_q    <= {ADDR_W + 1{1'b0}};
            rd_port_active_q   <= 1'b0;
        end else begin
            wr_gray_sync1_q  <= wr_gray_q;
            wr_gray_sync2_q  <= wr_gray_sync1_q;
            rd_port_active_q <= 1'b1;

            if (rd_load_w) begin
                rd_payload_valid_q <= 1'b1;
                rd_bin_q           <= rd_bin_next_w;
                rd_gray_q          <= bin2gray(rd_bin_next_w);
            end else if (rd_drain_only_w) begin
                rd_payload_valid_q <= 1'b0;
            end
        end
    end

endmodule
