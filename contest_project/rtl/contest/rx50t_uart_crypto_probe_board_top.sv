`timescale 1ns/1ps

module rx50t_uart_crypto_probe_board_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 2_000_000
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    rx50t_uart_crypto_probe_top #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_top (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_uart_rx(i_uart_rx),
        .o_uart_tx(o_uart_tx)
    );

endmodule
