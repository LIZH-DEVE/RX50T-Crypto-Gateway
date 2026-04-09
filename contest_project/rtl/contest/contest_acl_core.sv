`timescale 1ns/1ps

module contest_acl_core #(
    parameter [7:0] BLOCK_KEY0 = 8'h58, // 'X'
    parameter [7:0] BLOCK_KEY1 = 8'h59, // 'Y'
    parameter [7:0] BLOCK_KEY2 = 8'h5A, // 'Z'
    parameter [7:0] BLOCK_KEY3 = 8'h57  // 'W'
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       parser_valid,
    input  wire [7:0] parser_match_key,
    input  wire [7:0] parser_payload,
    input  wire       parser_last,

    output reg        acl_valid,
    output reg [7:0]  acl_data,
    output reg        acl_last
);

    localparam [1:0] ST_PASS      = 2'd0;
    localparam [1:0] ST_DROP_D    = 2'd1;
    localparam [1:0] ST_DROP_NL   = 2'd2;
    localparam [1:0] ST_DROP_DRAIN= 2'd3;

    localparam [7:0] ASCII_D      = 8'h44;
    localparam [7:0] ASCII_NL     = 8'h0A;

    reg [1:0] state_q;
    reg       drop_seen_last_q;

    wire rule_hit =
        (parser_match_key == BLOCK_KEY0) ||
        (parser_match_key == BLOCK_KEY1) ||
        (parser_match_key == BLOCK_KEY2) ||
        (parser_match_key == BLOCK_KEY3);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q           <= ST_PASS;
            drop_seen_last_q  <= 1'b0;
            acl_valid         <= 1'b0;
            acl_data          <= 8'd0;
            acl_last          <= 1'b0;
        end else begin
            acl_valid <= 1'b0;
            acl_data  <= 8'd0;
            acl_last  <= 1'b0;

            if (parser_valid && parser_last && (state_q != ST_PASS)) begin
                drop_seen_last_q <= 1'b1;
            end

            case (state_q)
                ST_PASS: begin
                    drop_seen_last_q <= 1'b0;
                    if (parser_valid) begin
                        if (rule_hit) begin
                            state_q          <= ST_DROP_D;
                            drop_seen_last_q <= parser_last;
                        end else begin
                            acl_valid <= 1'b1;
                            acl_data  <= parser_payload;
                            acl_last  <= parser_last;
                        end
                    end
                end

                ST_DROP_D: begin
                    acl_valid <= 1'b1;
                    acl_data  <= ASCII_D;
                    acl_last  <= 1'b0;
                    state_q   <= ST_DROP_NL;
                end

                ST_DROP_NL: begin
                    acl_valid <= 1'b1;
                    acl_data  <= ASCII_NL;
                    acl_last  <= 1'b1;
                    if (drop_seen_last_q || (parser_valid && parser_last)) begin
                        state_q          <= ST_PASS;
                        drop_seen_last_q <= 1'b0;
                    end else begin
                        state_q <= ST_DROP_DRAIN;
                    end
                end

                ST_DROP_DRAIN: begin
                    if (parser_valid && parser_last) begin
                        state_q          <= ST_PASS;
                        drop_seen_last_q <= 1'b0;
                    end
                end

                default: begin
                    state_q          <= ST_PASS;
                    drop_seen_last_q <= 1'b0;
                end
            endcase
        end
    end

endmodule
