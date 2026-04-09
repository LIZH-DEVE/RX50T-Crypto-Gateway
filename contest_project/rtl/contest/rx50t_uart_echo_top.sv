`timescale 1ns/1ps

module rx50t_uart_echo_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_uart_rx,
    output wire       o_uart_tx,
    output wire [7:0] o_dbg_last_rx_byte,
    output wire [7:0] o_dbg_last_tx_byte,
    output wire       o_dbg_rx_pulse,
    output wire       o_dbg_tx_pulse,
    output wire       o_dbg_frame_error,
    output wire       o_dbg_overrun
);

    contest_uart_io #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_uart_echo (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_uart_rx     (i_uart_rx),
        .o_uart_tx     (o_uart_tx),
        .o_last_rx_byte(o_dbg_last_rx_byte),
        .o_last_tx_byte(o_dbg_last_tx_byte),
        .o_rx_pulse    (o_dbg_rx_pulse),
        .o_tx_pulse    (o_dbg_tx_pulse),
        .o_frame_error (o_dbg_frame_error),
        .o_overrun     (o_dbg_overrun)
    );

endmodule
