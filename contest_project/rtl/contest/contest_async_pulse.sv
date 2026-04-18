`timescale 1ns/1ps

module contest_async_pulse (
    input  wire i_src_clk,
    input  wire i_src_rst_n_async,
    input  wire i_dst_clk,
    input  wire i_dst_rst_n_async,
    input  wire i_pulse,
    output wire o_pulse
);

    wire src_rst_n_sync;
    wire dst_rst_n_sync;

    reg src_toggle_q;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg dst_sync1_q;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg dst_sync2_q;
    reg dst_sync3_q;

    contest_reset_sync u_src_reset_sync (
        .i_clk        (i_src_clk),
        .i_rst_n_async(i_src_rst_n_async),
        .o_rst_n_sync (src_rst_n_sync)
    );

    contest_reset_sync u_dst_reset_sync (
        .i_clk        (i_dst_clk),
        .i_rst_n_async(i_dst_rst_n_async),
        .o_rst_n_sync (dst_rst_n_sync)
    );

    always @(posedge i_src_clk or negedge i_src_rst_n_async) begin
        if (!i_src_rst_n_async) begin
            src_toggle_q <= 1'b0;
        end else if (!src_rst_n_sync) begin
            src_toggle_q <= 1'b0;
        end else if (i_pulse) begin
            src_toggle_q <= ~src_toggle_q;
        end
    end

    always @(posedge i_dst_clk) begin
        if (!dst_rst_n_sync) begin
            dst_sync1_q <= 1'b0;
            dst_sync2_q <= 1'b0;
            dst_sync3_q <= 1'b0;
        end else begin
            dst_sync1_q <= src_toggle_q;
            dst_sync2_q <= dst_sync1_q;
            dst_sync3_q <= dst_sync2_q;
        end
    end

    assign o_pulse = dst_sync2_q ^ dst_sync3_q;

endmodule