`timescale 1ns/1ps

module contest_acl_core (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       parser_valid,
    input  wire [7:0] parser_match_key,
    input  wire [7:0] parser_payload,
    input  wire       parser_last,

    input  wire       cfg_valid,
    input  wire [2:0] cfg_index,
    input  wire [7:0] cfg_key,

    output reg        acl_valid,
    output reg [7:0]  acl_data,
    output reg        acl_last,
    output reg        acl_blocked,
    output reg        acl_block_slot_valid,
    output reg [2:0]  acl_block_slot,

    output reg        cfg_busy,
    output reg        cfg_done,
    output reg        cfg_error,

    output wire [63:0] o_rule_keys_flat,
    output wire [63:0] o_rule_counts_flat
);

    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_LOOKUP     = 3'd1;
    localparam [2:0] ST_PASS       = 3'd2;
    localparam [2:0] ST_DROP_D     = 3'd3;
    localparam [2:0] ST_DROP_NL    = 3'd4;
    localparam [2:0] ST_DROP_DRAIN = 3'd5;

    localparam [2:0] CFG_IDLE        = 3'd0;
    localparam [2:0] CFG_CLEAR_OLD   = 3'd1;
    localparam [2:0] CFG_WRITE_SLOT  = 3'd2;
    localparam [2:0] CFG_SET_NEW     = 3'd3;
    localparam [2:0] CFG_RESET_COUNT = 3'd4;
    localparam [2:0] CFG_DONE_PULSE  = 3'd5;
    localparam [2:0] CFG_ERR_PULSE   = 3'd6;

    localparam [7:0] ASCII_D  = 8'h44;
    localparam [7:0] ASCII_NL = 8'h0A;

    (* ram_style = "block" *) reg membership_q [0:255];

    reg [7:0] slot_key_q [0:7];
    reg [7:0] slot_count_q [0:7];

    reg [2:0] state_q;
    reg       drop_seen_last_q;
    reg [7:0] first_payload_q;
    reg       first_last_q;
    reg [7:0] lookup_addr_q;
    reg       lookup_req_q;
    reg       lookup_data_q;
    reg       lookup_valid_q;
    reg       hold_valid_q;
    reg [7:0] hold_payload_q;
    reg       hold_last_q;
    reg [2:0] drop_slot_q;

    reg [2:0] cfg_state_q;
    reg [2:0] cfg_slot_q;
    reg [7:0] cfg_old_key_q;
    reg [7:0] cfg_new_key_q;

    reg       mem_wr_en_q;
    reg [7:0] mem_wr_addr_q;
    reg       mem_wr_data_q;

    reg       cfg_duplicate_w;
    reg [2:0] lookup_slot_w;

    integer idx;

    assign o_rule_keys_flat = {
        slot_key_q[7], slot_key_q[6], slot_key_q[5], slot_key_q[4],
        slot_key_q[3], slot_key_q[2], slot_key_q[1], slot_key_q[0]
    };

    assign o_rule_counts_flat = {
        slot_count_q[7], slot_count_q[6], slot_count_q[5], slot_count_q[4],
        slot_count_q[3], slot_count_q[2], slot_count_q[1], slot_count_q[0]
    };

    initial begin
        for (idx = 0; idx < 256; idx = idx + 1) begin
            membership_q[idx] = 1'b0;
        end
        for (idx = 0; idx < 8; idx = idx + 1) begin
            slot_count_q[idx] = 8'd0;
        end

        slot_key_q[0] = 8'h58; // X
        slot_key_q[1] = 8'h59; // Y
        slot_key_q[2] = 8'h5A; // Z
        slot_key_q[3] = 8'h57; // W
        slot_key_q[4] = 8'h50; // P
        slot_key_q[5] = 8'h52; // R
        slot_key_q[6] = 8'h54; // T
        slot_key_q[7] = 8'h55; // U

        membership_q[8'h58] = 1'b1;
        membership_q[8'h59] = 1'b1;
        membership_q[8'h5A] = 1'b1;
        membership_q[8'h57] = 1'b1;
        membership_q[8'h50] = 1'b1;
        membership_q[8'h52] = 1'b1;
        membership_q[8'h54] = 1'b1;
        membership_q[8'h55] = 1'b1;
    end

    always @(*) begin
        cfg_duplicate_w = 1'b0;
        for (idx = 0; idx < 8; idx = idx + 1) begin
            if ((cfg_index != idx[2:0]) && (slot_key_q[idx] == cfg_key)) begin
                cfg_duplicate_w = 1'b1;
            end
        end
    end

    always @(*) begin
        lookup_slot_w = 3'd0;
        if (lookup_addr_q == slot_key_q[0]) begin
            lookup_slot_w = 3'd0;
        end else if (lookup_addr_q == slot_key_q[1]) begin
            lookup_slot_w = 3'd1;
        end else if (lookup_addr_q == slot_key_q[2]) begin
            lookup_slot_w = 3'd2;
        end else if (lookup_addr_q == slot_key_q[3]) begin
            lookup_slot_w = 3'd3;
        end else if (lookup_addr_q == slot_key_q[4]) begin
            lookup_slot_w = 3'd4;
        end else if (lookup_addr_q == slot_key_q[5]) begin
            lookup_slot_w = 3'd5;
        end else if (lookup_addr_q == slot_key_q[6]) begin
            lookup_slot_w = 3'd6;
        end else if (lookup_addr_q == slot_key_q[7]) begin
            lookup_slot_w = 3'd7;
        end
    end

    always @(posedge clk) begin
        if (lookup_req_q) begin
            lookup_data_q  <= membership_q[lookup_addr_q];
            lookup_valid_q <= 1'b1;
        end else begin
            lookup_valid_q <= 1'b0;
        end

        if (mem_wr_en_q) begin
            membership_q[mem_wr_addr_q] <= mem_wr_data_q;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state_q              <= ST_IDLE;
            drop_seen_last_q     <= 1'b0;
            first_payload_q      <= 8'd0;
            first_last_q         <= 1'b0;
            lookup_addr_q        <= 8'd0;
            lookup_req_q         <= 1'b0;
            hold_valid_q         <= 1'b0;
            hold_payload_q       <= 8'd0;
            hold_last_q          <= 1'b0;
            drop_slot_q          <= 3'd0;
            cfg_state_q          <= CFG_IDLE;
            cfg_slot_q           <= 3'd0;
            cfg_old_key_q        <= 8'd0;
            cfg_new_key_q        <= 8'd0;
            mem_wr_en_q          <= 1'b0;
            mem_wr_addr_q        <= 8'd0;
            mem_wr_data_q        <= 1'b0;
            acl_valid            <= 1'b0;
            acl_data             <= 8'd0;
            acl_last             <= 1'b0;
            acl_blocked          <= 1'b0;
            acl_block_slot_valid <= 1'b0;
            acl_block_slot       <= 3'd0;
            cfg_busy             <= 1'b0;
            cfg_done             <= 1'b0;
            cfg_error            <= 1'b0;
        end else begin
            lookup_req_q         <= 1'b0;
            mem_wr_en_q          <= 1'b0;
            acl_valid            <= 1'b0;
            acl_data             <= 8'd0;
            acl_last             <= 1'b0;
            acl_blocked          <= 1'b0;
            acl_block_slot_valid <= 1'b0;
            cfg_done             <= 1'b0;
            cfg_error            <= 1'b0;
            cfg_busy             <= (cfg_state_q != CFG_IDLE);

            case (cfg_state_q)
                CFG_IDLE: begin
                    if (cfg_valid) begin
                        cfg_slot_q    <= cfg_index;
                        cfg_old_key_q <= slot_key_q[cfg_index];
                        cfg_new_key_q <= cfg_key;
                        if (cfg_duplicate_w) begin
                            cfg_state_q <= CFG_ERR_PULSE;
                        end else if (slot_key_q[cfg_index] == cfg_key) begin
                            cfg_state_q <= CFG_RESET_COUNT;
                        end else begin
                            cfg_state_q <= CFG_CLEAR_OLD;
                        end
                    end
                end

                CFG_CLEAR_OLD: begin
                    mem_wr_en_q   <= 1'b1;
                    mem_wr_addr_q <= cfg_old_key_q;
                    mem_wr_data_q <= 1'b0;
                    cfg_state_q   <= CFG_WRITE_SLOT;
                end

                CFG_WRITE_SLOT: begin
                    slot_key_q[cfg_slot_q] <= cfg_new_key_q;
                    cfg_state_q            <= CFG_SET_NEW;
                end

                CFG_SET_NEW: begin
                    mem_wr_en_q   <= 1'b1;
                    mem_wr_addr_q <= cfg_new_key_q;
                    mem_wr_data_q <= 1'b1;
                    cfg_state_q   <= CFG_RESET_COUNT;
                end

                CFG_RESET_COUNT: begin
                    slot_count_q[cfg_slot_q] <= 8'd0;
                    cfg_state_q              <= CFG_DONE_PULSE;
                end

                CFG_DONE_PULSE: begin
                    cfg_done   <= 1'b1;
                    cfg_state_q <= CFG_IDLE;
                end

                CFG_ERR_PULSE: begin
                    cfg_error  <= 1'b1;
                    cfg_state_q <= CFG_IDLE;
                end

                default: begin
                    cfg_state_q <= CFG_IDLE;
                end
            endcase

            case (state_q)
                ST_IDLE: begin
                    drop_seen_last_q <= 1'b0;
                    if (parser_valid && (cfg_state_q == CFG_IDLE)) begin
                        first_payload_q <= parser_payload;
                        first_last_q    <= parser_last;
                        lookup_addr_q   <= parser_match_key;
                        lookup_req_q    <= 1'b1;
                        state_q         <= ST_LOOKUP;
                    end
                end

                ST_LOOKUP: begin
                    if (lookup_valid_q) begin
                        if (lookup_data_q) begin
                            drop_slot_q               <= lookup_slot_w;
                            slot_count_q[lookup_slot_w] <= slot_count_q[lookup_slot_w] + 8'd1;
                            drop_seen_last_q          <= first_last_q || (parser_valid && parser_last);
                            state_q                   <= ST_DROP_D;
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
                    end else if (parser_valid && (cfg_state_q == CFG_IDLE)) begin
                        acl_valid <= 1'b1;
                        acl_data  <= parser_payload;
                        acl_last  <= parser_last;
                        if (parser_last) begin
                            state_q <= ST_IDLE;
                        end
                    end
                end

                ST_DROP_D: begin
                    acl_valid            <= 1'b1;
                    acl_data             <= ASCII_D;
                    acl_last             <= 1'b0;
                    acl_blocked          <= 1'b1;
                    acl_block_slot_valid <= 1'b1;
                    acl_block_slot       <= drop_slot_q;
                    state_q              <= ST_DROP_NL;
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
