`timescale 1ns/1ps

module rx50t_uart_parser_probe_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_uart_rx,
    output wire       o_uart_tx,
    output wire       o_dbg_in_frame,
    output wire       o_dbg_frame_start,
    output wire       o_dbg_payload_valid,
    output wire [7:0] o_dbg_payload_byte,
    output wire       o_dbg_frame_done,
    output wire       o_dbg_error,
    output wire       o_dbg_tx_overrun
);

    contest_uart_parser_probe #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_probe (
        .i_clk            (i_clk),
        .i_rst_n          (i_rst_n),
        .i_uart_rx        (i_uart_rx),
        .o_uart_tx        (o_uart_tx),
        .o_dbg_in_frame   (o_dbg_in_frame),
        .o_dbg_frame_start(o_dbg_frame_start),
        .o_dbg_payload_valid(o_dbg_payload_valid),
        .o_dbg_payload_byte(o_dbg_payload_byte),
        .o_dbg_frame_done (o_dbg_frame_done),
        .o_dbg_error      (o_dbg_error),
        .o_dbg_tx_overrun (o_dbg_tx_overrun)
    );

endmodule
