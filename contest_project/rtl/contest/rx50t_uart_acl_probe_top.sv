`timescale 1ns/1ps

module rx50t_uart_acl_probe_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200,
    parameter [7:0]   BLOCK_KEY = 8'h58
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    contest_uart_acl_probe #(
        .CLK_HZ   (CLK_HZ),
        .BAUD     (BAUD),
        .BLOCK_KEY(BLOCK_KEY)
    ) u_probe (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_uart_rx(i_uart_rx),
        .o_uart_tx(o_uart_tx)
    );

endmodule
