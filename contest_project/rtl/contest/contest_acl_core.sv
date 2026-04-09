`timescale 1ns/1ps

module contest_acl_core (
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

    localparam [2:0] ST_IDLE      = 3'd0;
    localparam [2:0] ST_LOOKUP    = 3'd1;
    localparam [2:0] ST_PASS      = 3'd2;
    localparam [2:0] ST_DROP_D    = 3'd3;
    localparam [2:0] ST_DROP_NL   = 3'd4;
    localparam [2:0] ST_DROP_DRAIN= 3'd5;

    localparam [7:0] ASCII_D      = 8'h44;
    localparam [7:0] ASCII_NL     = 8'h0A;

    (* ram_style = "block" *) reg [7:0] rule_table_q [0:255];

    reg [2:0] state_q;
    reg       drop_seen_last_q;
    reg [7:0] first_payload_q;
    reg       first_last_q;
    reg [7:0] lookup_addr_q;
    reg       lookup_req_q;
    reg [7:0] lookup_data_q;
    reg       lookup_valid_q;
    reg       hold_valid_q;
    reg [7:0] hold_payload_q;
    reg       hold_last_q;

    wire rule_hit = lookup_data_q[0];

    integer idx;

    initial begin
        for (idx = 0; idx < 256; idx = idx + 1) begin
            rule_table_q[idx] = 8'h00;
        end

        // Current default rules:
        // X / Y / Z / W => block.
        rule_table_q[8'h58] = 8'h01;
        rule_table_q[8'h59] = 8'h01;
        rule_table_q[8'h5A] = 8'h01;
        rule_table_q[8'h57] = 8'h01;
    end

    always @(posedge clk) begin
        if ((state_q == ST_IDLE) && parser_valid) begin
            lookup_addr_q <= parser_match_key;
            lookup_req_q  <= 1'b1;
        end else begin
            lookup_req_q <= 1'b0;
        end

        if (lookup_req_q) begin
            lookup_data_q  <= rule_table_q[lookup_addr_q];
            lookup_valid_q <= 1'b1;
        end else begin
            lookup_valid_q <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q           <= ST_IDLE;
            drop_seen_last_q  <= 1'b0;
            first_payload_q   <= 8'd0;
            first_last_q      <= 1'b0;
            hold_valid_q      <= 1'b0;
            hold_payload_q    <= 8'd0;
            hold_last_q       <= 1'b0;
            acl_valid         <= 1'b0;
            acl_data          <= 8'd0;
            acl_last          <= 1'b0;
        end else begin
            acl_valid <= 1'b0;
            acl_data  <= 8'd0;
            acl_last  <= 1'b0;

            if (parser_valid && parser_last && (state_q != ST_IDLE) && (state_q != ST_LOOKUP) && (state_q != ST_PASS)) begin
                drop_seen_last_q <= 1'b1;
            end

            case (state_q)
                ST_IDLE: begin
                    drop_seen_last_q <= 1'b0;
                    if (parser_valid) begin
                        first_payload_q <= parser_payload;
                        first_last_q    <= parser_last;
                        state_q         <= ST_LOOKUP;
                    end
                end

                ST_LOOKUP: begin
                    if (lookup_valid_q) begin
                        if (rule_hit) begin
                            state_q          <= ST_DROP_D;
                            drop_seen_last_q <= first_last_q || (parser_valid && parser_last);
                        end else begin
                            acl_valid <= 1'b1;
                            acl_data  <= first_payload_q;
                            acl_last  <= first_last_q;
                            if (parser_valid && !first_last_q) begin
                                hold_valid_q   <= 1'b1;
                                hold_payload_q <= parser_payload;
                                hold_last_q    <= parser_last;
                            end
                            if (first_last_q) begin
                                state_q <= ST_IDLE;
                            end else begin
                                state_q <= ST_PASS;
                            end
                        end
                    end
                end

                ST_PASS: begin
                    if (hold_valid_q) begin
                        acl_valid      <= 1'b1;
                        acl_data       <= hold_payload_q;
                        acl_last       <= hold_last_q;
                        hold_valid_q   <= 1'b0;
                        hold_payload_q <= 8'd0;
                        hold_last_q    <= 1'b0;
                        if (hold_last_q) begin
                            state_q <= ST_IDLE;
                        end
                    end else if (parser_valid) begin
                        acl_valid <= 1'b1;
                        acl_data  <= parser_payload;
                        acl_last  <= parser_last;
                        if (parser_last) begin
                            state_q <= ST_IDLE;
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
                        state_q          <= ST_IDLE;
                        drop_seen_last_q <= 1'b0;
                    end else begin
                        state_q <= ST_DROP_DRAIN;
                    end
                end

                ST_DROP_DRAIN: begin
                    if (parser_valid && parser_last) begin
                        state_q          <= ST_IDLE;
                        drop_seen_last_q <= 1'b0;
                    end
                end

                default: begin
                    state_q          <= ST_IDLE;
                    drop_seen_last_q <= 1'b0;
                end
            endcase
        end
    end

endmodule
