`timescale 1ns/1ps

module contest_uart_acl_probe #(
    parameter integer CLK_HZ     = 50_000_000,
    parameter integer BAUD       = 115200,
    parameter integer FIFO_DEPTH = 32,
    parameter [7:0]   BLOCK_KEY  = 8'h58
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    localparam [7:0] ASCII_ERROR = 8'h45; // E
    localparam [7:0] ASCII_NL    = 8'h0A;

    wire       rx_valid;
    wire [7:0] rx_data;
    wire       rx_frame_error;

    wire       parser_payload_valid;
    wire [7:0] parser_payload_byte;
    wire       parser_frame_done;
    wire       parser_error;

    reg  [7:0] frame_key_q;
    reg        frame_key_valid_q;
    wire [7:0] acl_match_key;

    wire       acl_valid;
    wire [7:0] acl_data;
    wire       acl_last;

    wire [7:0] tx_fifo_rd_data;
    wire       tx_fifo_full;
    wire       tx_fifo_empty;
    wire       tx_fifo_overflow;
    wire       tx_ready;

    reg        tx_fifo_wr_en_q;
    reg [7:0]  tx_fifo_wr_data_q;
    reg        tx_fifo_rd_en_q;
    reg        tx_valid_q;
    reg [7:0]  tx_data_q;
    reg        tx_launch_pending_q;
    reg [7:0]  tx_launch_byte_q;
    reg        pending_error_q;
    reg        pending_error_nl_q;

    assign acl_match_key = frame_key_valid_q ? frame_key_q : parser_payload_byte;

    contest_uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_rx (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_uart_rx     (i_uart_rx),
        .o_valid       (rx_valid),
        .o_data        (rx_data),
        .o_frame_error (rx_frame_error)
    );

    contest_parser_core #(
        .SOF_BYTE         (8'h55),
        .MAX_PAYLOAD_BYTES(32)
    ) u_parser (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .i_valid        (rx_valid),
        .i_byte         (rx_data),
        .o_in_frame     (),
        .o_frame_start  (),
        .o_payload_valid(parser_payload_valid),
        .o_payload_byte (parser_payload_byte),
        .o_frame_done   (parser_frame_done),
        .o_error        (parser_error),
        .o_payload_len  (),
        .o_payload_count()
    );

    contest_acl_core #(
        .BLOCK_KEY(BLOCK_KEY)
    ) u_acl (
        .clk            (i_clk),
        .rst_n          (i_rst_n),
        .parser_valid   (parser_payload_valid),
        .parser_match_key(acl_match_key),
        .parser_payload (parser_payload_byte),
        .parser_last    (parser_frame_done),
        .acl_valid      (acl_valid),
        .acl_data       (acl_data),
        .acl_last       (acl_last)
    );

    contest_uart_fifo #(
        .DEPTH(FIFO_DEPTH)
    ) u_tx_fifo (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_wr_en    (tx_fifo_wr_en_q),
        .i_wr_data  (tx_fifo_wr_data_q),
        .i_rd_en    (tx_fifo_rd_en_q),
        .o_rd_data  (tx_fifo_rd_data),
        .o_full     (tx_fifo_full),
        .o_empty    (tx_fifo_empty),
        .o_overflow (tx_fifo_overflow),
        .o_underflow()
    );

    contest_uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_tx (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_valid  (tx_valid_q),
        .i_data   (tx_data_q),
        .o_ready  (tx_ready),
        .o_uart_tx(o_uart_tx)
    );

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            frame_key_q         <= 8'd0;
            frame_key_valid_q   <= 1'b0;
            tx_fifo_wr_en_q     <= 1'b0;
            tx_fifo_wr_data_q   <= 8'd0;
            tx_fifo_rd_en_q     <= 1'b0;
            tx_valid_q          <= 1'b0;
            tx_data_q           <= 8'd0;
            tx_launch_pending_q <= 1'b0;
            tx_launch_byte_q    <= 8'd0;
            pending_error_q     <= 1'b0;
            pending_error_nl_q  <= 1'b0;
        end else begin
            tx_fifo_wr_en_q <= 1'b0;
            tx_fifo_rd_en_q <= 1'b0;
            tx_valid_q      <= 1'b0;

            if (parser_payload_valid && !frame_key_valid_q) begin
                frame_key_q       <= parser_payload_byte;
                frame_key_valid_q <= 1'b1;
            end

            if (parser_frame_done || parser_error) begin
                frame_key_valid_q <= 1'b0;
            end

            if (acl_valid) begin
                if (!tx_fifo_full) begin
                    tx_fifo_wr_en_q   <= 1'b1;
                    tx_fifo_wr_data_q <= acl_data;
                end
            end else if (pending_error_q) begin
                if (!tx_fifo_full) begin
                    tx_fifo_wr_en_q   <= 1'b1;
                    tx_fifo_wr_data_q <= ASCII_ERROR;
                    pending_error_q   <= 1'b0;
                    pending_error_nl_q<= 1'b1;
                end
            end else if (pending_error_nl_q) begin
                if (!tx_fifo_full) begin
                    tx_fifo_wr_en_q    <= 1'b1;
                    tx_fifo_wr_data_q  <= ASCII_NL;
                    pending_error_nl_q <= 1'b0;
                end
            end

            if (parser_error || rx_frame_error) begin
                pending_error_q <= 1'b1;
            end

            if (tx_launch_pending_q && tx_ready) begin
                tx_valid_q          <= 1'b1;
                tx_data_q           <= tx_launch_byte_q;
                tx_launch_pending_q <= 1'b0;
            end else if (!tx_launch_pending_q && tx_ready && !tx_fifo_empty) begin
                tx_fifo_rd_en_q     <= 1'b1;
                tx_launch_byte_q    <= tx_fifo_rd_data;
                tx_launch_pending_q <= 1'b1;
            end

            if (tx_fifo_overflow) begin
                pending_error_q <= 1'b1;
            end
        end
    end

endmodule
