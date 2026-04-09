`timescale 1ns/1ps

module contest_uart_tx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_valid,
    input  wire [7:0] i_data,
    output wire       o_ready,
    output reg        o_uart_tx
);

    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0]  state_q;
    reg [15:0] clk_count_q;
    reg [3:0]  bit_index_q;
    reg [7:0]  shift_q;

    assign o_ready = (state_q == ST_IDLE);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_q     <= ST_IDLE;
            clk_count_q <= 16'd0;
            bit_index_q <= 4'd0;
            shift_q     <= 8'd0;
            o_uart_tx   <= 1'b1;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    clk_count_q <= 16'd0;
                    bit_index_q <= 4'd0;
                    o_uart_tx   <= 1'b1;
                    if (i_valid) begin
                        shift_q   <= i_data;
                        o_uart_tx <= 1'b0;
                        state_q   <= ST_START;
                    end
                end

                ST_START: begin
                    if (clk_count_q == CLKS_PER_BIT - 1) begin
                        clk_count_q <= 16'd0;
                        o_uart_tx   <= shift_q[0];
                        bit_index_q <= 4'd1;
                        state_q     <= ST_DATA;
                    end else begin
                        clk_count_q <= clk_count_q + 16'd1;
                    end
                end

                ST_DATA: begin
                    if (clk_count_q == CLKS_PER_BIT - 1) begin
                        clk_count_q <= 16'd0;
                        if (bit_index_q == 4'd8) begin
                            o_uart_tx <= 1'b1;
                            state_q   <= ST_STOP;
                        end else begin
                            o_uart_tx   <= shift_q[bit_index_q];
                            bit_index_q <= bit_index_q + 4'd1;
                        end
                    end else begin
                        clk_count_q <= clk_count_q + 16'd1;
                    end
                end

                ST_STOP: begin
                    o_uart_tx <= 1'b1;
                    if (clk_count_q == CLKS_PER_BIT - 1) begin
                        clk_count_q <= 16'd0;
                        state_q     <= ST_IDLE;
                    end else begin
                        clk_count_q <= clk_count_q + 16'd1;
                    end
                end

                default: begin
                    state_q   <= ST_IDLE;
                    o_uart_tx <= 1'b1;
                end
            endcase
        end
    end

endmodule
