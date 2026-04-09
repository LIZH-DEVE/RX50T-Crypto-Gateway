`timescale 1ns/1ps

module rx50t_uart_parser_probe_board_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    wire dbg_in_frame_unused;
    wire dbg_frame_start_unused;
    wire dbg_payload_valid_unused;
    wire [7:0] dbg_payload_byte_unused;
    wire dbg_frame_done_unused;
    wire dbg_error_unused;
    wire dbg_tx_overrun_unused;

    rx50t_uart_parser_probe_top #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_top (
        .i_clk            (i_clk),
        .i_rst_n          (i_rst_n),
        .i_uart_rx        (i_uart_rx),
        .o_uart_tx        (o_uart_tx),
        .o_dbg_in_frame   (dbg_in_frame_unused),
        .o_dbg_frame_start(dbg_frame_start_unused),
        .o_dbg_payload_valid(dbg_payload_valid_unused),
        .o_dbg_payload_byte(dbg_payload_byte_unused),
        .o_dbg_frame_done (dbg_frame_done_unused),
        .o_dbg_error      (dbg_error_unused),
        .o_dbg_tx_overrun (dbg_tx_overrun_unused)
    );

endmodule
