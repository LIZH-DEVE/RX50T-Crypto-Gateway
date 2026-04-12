`timescale 1ns/1ps

module contest_parser_core #(
    parameter integer SOF_BYTE          = 8'h55,
    parameter integer MAX_PAYLOAD_BYTES = 32,
    parameter integer INTERBYTE_TIMEOUT_CLKS = 0
) (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_valid,
    input  wire [7:0] i_byte,
    output reg        o_in_frame,
    output reg        o_frame_start,
    output reg        o_payload_valid,
    output reg [7:0]  o_payload_byte,
    output reg        o_frame_done,
    output reg        o_error,
    output reg [7:0]  o_payload_len,
    output reg [7:0]  o_payload_count
);

    localparam [1:0] ST_IDLE       = 2'd0;
    localparam [1:0] ST_WAIT_LEN   = 2'd1;
    localparam [1:0] ST_WAIT_DATA  = 2'd2;

    reg [1:0] state_q;
    reg [7:0] payload_len_q;
    reg [7:0] payload_count_q;
    reg [31:0] timeout_count_q;

    wire timeout_enabled = (INTERBYTE_TIMEOUT_CLKS > 0);
    wire timeout_hit = timeout_enabled &&
                       (state_q != ST_IDLE) &&
                       !i_valid &&
                       (timeout_count_q >= (INTERBYTE_TIMEOUT_CLKS - 1));

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_q          <= ST_IDLE;
            payload_len_q    <= 8'd0;
            payload_count_q  <= 8'd0;
            timeout_count_q  <= 32'd0;
            o_in_frame       <= 1'b0;
            o_frame_start    <= 1'b0;
            o_payload_valid  <= 1'b0;
            o_payload_byte   <= 8'd0;
            o_frame_done     <= 1'b0;
            o_error          <= 1'b0;
            o_payload_len    <= 8'd0;
            o_payload_count  <= 8'd0;
        end else begin
            o_frame_start   <= 1'b0;
            o_payload_valid <= 1'b0;
            o_frame_done    <= 1'b0;
            o_error         <= 1'b0;

            if (timeout_hit) begin
                state_q         <= ST_IDLE;
                payload_len_q   <= 8'd0;
                payload_count_q <= 8'd0;
                timeout_count_q <= 32'd0;
                o_in_frame      <= 1'b0;
                o_payload_len   <= 8'd0;
                o_payload_count <= 8'd0;
                o_error         <= 1'b1;
            end else if (i_valid) begin
                timeout_count_q <= 32'd0;
                case (state_q)
                    ST_IDLE: begin
                        if (i_byte == SOF_BYTE[7:0]) begin
                            state_q       <= ST_WAIT_LEN;
                            o_in_frame    <= 1'b1;
                            o_frame_start <= 1'b1;
                        end
                    end

                    ST_WAIT_LEN: begin
                        if ((i_byte == 8'd0) || (i_byte > MAX_PAYLOAD_BYTES[7:0])) begin
                            state_q         <= ST_IDLE;
                            payload_len_q   <= 8'd0;
                            payload_count_q <= 8'd0;
                            timeout_count_q <= 32'd0;
                            o_in_frame      <= 1'b0;
                            o_payload_len   <= 8'd0;
                            o_payload_count <= 8'd0;
                            o_error         <= 1'b1;
                        end else begin
                            state_q         <= ST_WAIT_DATA;
                            payload_len_q   <= i_byte;
                            payload_count_q <= 8'd0;
                            o_payload_len   <= i_byte;
                            o_payload_count <= 8'd0;
                        end
                    end

                    ST_WAIT_DATA: begin
                        o_payload_valid <= 1'b1;
                        o_payload_byte  <= i_byte;
                        payload_count_q <= payload_count_q + 8'd1;
                        o_payload_count <= payload_count_q + 8'd1;

                        if ((payload_count_q + 8'd1) == payload_len_q) begin
                            state_q         <= ST_IDLE;
                            payload_len_q   <= 8'd0;
                            payload_count_q <= 8'd0;
                            timeout_count_q <= 32'd0;
                            o_in_frame      <= 1'b0;
                            o_frame_done    <= 1'b1;
                        end
                    end

                    default: begin
                        state_q      <= ST_IDLE;
                        o_in_frame   <= 1'b0;
                        o_error      <= 1'b1;
                    end
                endcase
            end else if ((state_q != ST_IDLE) && timeout_enabled) begin
                timeout_count_q <= timeout_count_q + 32'd1;
            end
        end
    end

endmodule
