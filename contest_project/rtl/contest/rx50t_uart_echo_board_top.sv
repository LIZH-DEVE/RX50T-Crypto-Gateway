`timescale 1ns/1ps

module rx50t_uart_echo_board_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    wire [7:0] unused_last_rx_byte;
    wire [7:0] unused_last_tx_byte;
    wire       unused_rx_pulse;
    wire       unused_tx_pulse;
    wire       unused_frame_error;
    wire       unused_overrun;

    contest_uart_io #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_uart_echo (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_uart_rx     (i_uart_rx),
        .o_uart_tx     (o_uart_tx),
        .o_last_rx_byte(unused_last_rx_byte),
        .o_last_tx_byte(unused_last_tx_byte),
        .o_rx_pulse    (unused_rx_pulse),
        .o_tx_pulse    (unused_tx_pulse),
        .o_frame_error (unused_frame_error),
        .o_overrun     (unused_overrun)
    );

endmodule
