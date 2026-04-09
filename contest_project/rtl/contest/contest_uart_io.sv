`timescale 1ns/1ps

module contest_uart_io #(
    parameter integer CLK_HZ     = 50_000_000,
    parameter integer BAUD       = 115200,
    parameter integer FIFO_DEPTH = 16
) (
    input  wire      i_clk,
    input  wire      i_rst_n,
    input  wire      i_uart_rx,
    output wire      o_uart_tx,
    output reg [7:0] o_last_rx_byte,
    output reg [7:0] o_last_tx_byte,
    output reg       o_rx_pulse,
    output reg       o_tx_pulse,
    output reg       o_frame_error,
    output reg       o_overrun
);

    wire       rx_valid;
    wire [7:0] rx_data;
    wire       rx_frame_error;
    wire [7:0] fifo_rd_data;
    wire       fifo_full;
    wire       fifo_empty;
    wire       fifo_overflow;
    wire       fifo_underflow;
    wire       tx_ready;

    reg        fifo_rd_en_q;
    reg        tx_valid_q;
    reg [7:0]  tx_data_q;

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

    contest_uart_fifo #(
        .DEPTH(FIFO_DEPTH)
    ) u_fifo (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_wr_en    (rx_valid),
        .i_wr_data  (rx_data),
        .i_rd_en    (fifo_rd_en_q),
        .o_rd_data  (fifo_rd_data),
        .o_full     (fifo_full),
        .o_empty    (fifo_empty),
        .o_overflow (fifo_overflow),
        .o_underflow(fifo_underflow)
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
            fifo_rd_en_q   <= 1'b0;
            tx_valid_q     <= 1'b0;
            tx_data_q      <= 8'd0;
            o_last_rx_byte <= 8'd0;
            o_last_tx_byte <= 8'd0;
            o_rx_pulse     <= 1'b0;
            o_tx_pulse     <= 1'b0;
            o_frame_error  <= 1'b0;
            o_overrun      <= 1'b0;
        end else begin
            fifo_rd_en_q <= 1'b0;
            tx_valid_q   <= 1'b0;
            o_rx_pulse   <= 1'b0;
            o_tx_pulse   <= 1'b0;

            if (rx_valid) begin
                o_last_rx_byte <= rx_data;
                o_rx_pulse     <= 1'b1;
            end

            if (rx_frame_error) begin
                o_frame_error <= 1'b1;
            end

            if (fifo_overflow) begin
                o_overrun <= 1'b1;
            end

            if (tx_ready && !fifo_empty) begin
                tx_data_q      <= fifo_rd_data;
                tx_valid_q     <= 1'b1;
                fifo_rd_en_q   <= 1'b1;
                o_last_tx_byte <= fifo_rd_data;
                o_tx_pulse     <= 1'b1;
            end
        end
    end

endmodule
