`timescale 1ns/1ps

module contest_uart_rx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_uart_rx,
    output reg        o_valid,
    output reg [7:0]  o_data,
    output reg        o_frame_error
);

    localparam integer CLKS_PER_BIT  = CLK_HZ / BAUD;
    localparam integer HALF_BIT_TICK = CLKS_PER_BIT / 2;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0] state_q;
    reg [15:0] clk_count_q;
    reg [2:0] bit_index_q;
    reg [7:0] shift_q;
    reg rx_meta_q;
    reg rx_sync_q;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rx_meta_q      <= 1'b1;
            rx_sync_q      <= 1'b1;
            state_q        <= ST_IDLE;
            clk_count_q    <= 16'd0;
            bit_index_q    <= 3'd0;
            shift_q        <= 8'd0;
            o_valid        <= 1'b0;
            o_data         <= 8'd0;
            o_frame_error  <= 1'b0;
        end else begin
            rx_meta_q <= i_uart_rx;
            rx_sync_q <= rx_meta_q;

            o_valid <= 1'b0;

            case (state_q)
                ST_IDLE: begin
                    clk_count_q <= 16'd0;
                    bit_index_q <= 3'd0;
                    if (!rx_sync_q) begin
                        state_q <= ST_START;
                    end
                end

                ST_START: begin
                    if (clk_count_q == HALF_BIT_TICK - 1) begin
                        clk_count_q <= 16'd0;
                        if (!rx_sync_q) begin
                            state_q <= ST_DATA;
                        end else begin
                            state_q <= ST_IDLE;
                        end
                    end else begin
                        clk_count_q <= clk_count_q + 16'd1;
                    end
                end

                ST_DATA: begin
                    if (clk_count_q == CLKS_PER_BIT - 1) begin
                        clk_count_q <= 16'd0;
                        shift_q[bit_index_q] <= rx_sync_q;
                        if (bit_index_q == 3'd7) begin
                            bit_index_q <= 3'd0;
                            state_q     <= ST_STOP;
                        end else begin
                            bit_index_q <= bit_index_q + 3'd1;
                        end
                    end else begin
                        clk_count_q <= clk_count_q + 16'd1;
                    end
                end

                ST_STOP: begin
                    if (clk_count_q == CLKS_PER_BIT - 1) begin
                        clk_count_q <= 16'd0;
                        state_q     <= ST_IDLE;
                        o_data      <= shift_q;
                        o_valid     <= 1'b1;
                        o_frame_error <= !rx_sync_q;
                    end else begin
                        clk_count_q <= clk_count_q + 16'd1;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
