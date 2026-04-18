`timescale 1ns/1ps

module contest_reset_sync #(
    parameter integer STAGES = 2
) (
    input  wire i_clk,
    input  wire i_rst_n_async,
    output wire o_rst_n_sync
);

    initial begin
        if (STAGES < 2) begin
            $error("contest_reset_sync requires STAGES >= 2");
            $finish;
        end
    end

    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [STAGES-1:0] sync_q = {STAGES{1'b0}};

    always @(posedge i_clk or negedge i_rst_n_async) begin
        if (!i_rst_n_async) begin
            sync_q <= {STAGES{1'b0}};
        end else begin
            sync_q <= {sync_q[STAGES-2:0], 1'b1};
        end
    end

    assign o_rst_n_sync = sync_q[STAGES-1];

endmodule
