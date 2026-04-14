`timescale 1ns/1ps

module rx50t_uart_crypto_probe_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 2_000_000,
    parameter integer BENCH_TOTAL_BYTES = 1_048_576,
    parameter integer BENCH_TIMEOUT_CLKS = 16_777_215
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    contest_uart_crypto_probe #(
        .CLK_HZ             (CLK_HZ),
        .BAUD               (BAUD),
        .BENCH_TOTAL_BYTES_P(BENCH_TOTAL_BYTES),
        .BENCH_TIMEOUT_CLKS_P(BENCH_TIMEOUT_CLKS)
    ) u_probe (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_uart_rx(i_uart_rx),
        .o_uart_tx(o_uart_tx)
    );

endmodule
