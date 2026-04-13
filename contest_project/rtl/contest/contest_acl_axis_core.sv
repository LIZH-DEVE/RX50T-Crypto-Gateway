`timescale 1ns/1ps

module contest_acl_axis_core (
    input  wire       i_clk,
    input  wire       i_rst_n,

    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tlast,
    input  wire [0:0] s_axis_tuser,

    output reg        m_axis_tvalid,
    input  wire       m_axis_tready,
    output reg  [7:0] m_axis_tdata,
    output reg        m_axis_tlast,
    output reg  [0:0] m_axis_tuser,

    input  wire       i_cfg_valid,
    input  wire [2:0] i_cfg_index,
    input  wire [7:0] i_cfg_key,
    output reg        o_cfg_busy,
    output reg        o_cfg_done,
    output reg        o_cfg_error,

    output reg        o_acl_block_pulse,
    output reg        o_acl_block_slot_valid,
    output reg  [2:0] o_acl_block_slot,

    output wire [63:0] o_rule_keys_flat,
    output wire [63:0] o_rule_counts_flat
);

    localparam [1:0] ST_IDLE       = 2'd0;
    localparam [1:0] ST_LOOKUP     = 2'd1;
    localparam [1:0] ST_PASS       = 2'd2;
    localparam [1:0] ST_DROP_DRAIN = 2'd3;

    localparam [2:0] CFG_IDLE        = 3'd0;
    localparam [2:0] CFG_CLEAR_OLD   = 3'd1;
    localparam [2:0] CFG_WRITE_SLOT  = 3'd2;
    localparam [2:0] CFG_SET_NEW     = 3'd3;
    localparam [2:0] CFG_RESET_COUNT = 3'd4;
    localparam [2:0] CFG_DONE_PULSE  = 3'd5;
    localparam [2:0] CFG_ERR_PULSE   = 3'd6;

    (* ram_style = "block" *) reg membership_q [0:255];

    reg [7:0] slot_key_q [0:7];
    reg [7:0] slot_count_q [0:7];

    reg [1:0] state_q;
    reg [7:0] first_data_q;
    reg       first_last_q;
    reg [0:0] first_user_q;
    reg [7:0] lookup_addr_q;
    reg       lookup_req_q;
    reg       lookup_data_q;
    reg       lookup_valid_q;
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

    assign s_axis_tready =
        (cfg_state_q == CFG_IDLE) &&
        (
            (state_q == ST_IDLE) ||
            (state_q == ST_DROP_DRAIN) ||
            (((state_q == ST_PASS)) && !m_axis_tvalid)
        );

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
            if ((i_cfg_index != idx[2:0]) && (slot_key_q[idx] == i_cfg_key)) begin
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

    always @(posedge i_clk) begin
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

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state_q                 <= ST_IDLE;
            first_data_q            <= 8'd0;
            first_last_q            <= 1'b0;
            first_user_q            <= 1'b0;
            lookup_addr_q           <= 8'd0;
            lookup_req_q            <= 1'b0;
            drop_slot_q             <= 3'd0;
            cfg_state_q             <= CFG_IDLE;
            cfg_slot_q              <= 3'd0;
            cfg_old_key_q           <= 8'd0;
            cfg_new_key_q           <= 8'd0;
            mem_wr_en_q             <= 1'b0;
            mem_wr_addr_q           <= 8'd0;
            mem_wr_data_q           <= 1'b0;
            m_axis_tvalid           <= 1'b0;
            m_axis_tdata            <= 8'd0;
            m_axis_tlast            <= 1'b0;
            m_axis_tuser            <= 1'b0;
            o_cfg_busy              <= 1'b0;
            o_cfg_done              <= 1'b0;
            o_cfg_error             <= 1'b0;
            o_acl_block_pulse       <= 1'b0;
            o_acl_block_slot_valid  <= 1'b0;
            o_acl_block_slot        <= 3'd0;
        end else begin
            lookup_req_q           <= 1'b0;
            mem_wr_en_q            <= 1'b0;
            o_cfg_done             <= 1'b0;
            o_cfg_error            <= 1'b0;
            o_acl_block_pulse      <= 1'b0;
            o_acl_block_slot_valid <= 1'b0;
            o_cfg_busy             <= (cfg_state_q != CFG_IDLE);

            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                if (m_axis_tlast) begin
                    state_q <= ST_IDLE;
                end
            end

            case (cfg_state_q)
                CFG_IDLE: begin
                    if (i_cfg_valid) begin
                        cfg_slot_q    <= i_cfg_index;
                        cfg_old_key_q <= slot_key_q[i_cfg_index];
                        cfg_new_key_q <= i_cfg_key;
                        if (cfg_duplicate_w) begin
                            cfg_state_q <= CFG_ERR_PULSE;
                        end else if (slot_key_q[i_cfg_index] == i_cfg_key) begin
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
                    o_cfg_done  <= 1'b1;
                    cfg_state_q <= CFG_IDLE;
                end

                CFG_ERR_PULSE: begin
                    o_cfg_error <= 1'b1;
                    cfg_state_q <= CFG_IDLE;
                end

                default: begin
                    cfg_state_q <= CFG_IDLE;
                end
            endcase

            case (state_q)
                ST_IDLE: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        first_data_q  <= s_axis_tdata;
                        first_last_q  <= s_axis_tlast;
                        first_user_q  <= s_axis_tuser;
                        lookup_addr_q <= s_axis_tdata;
                        lookup_req_q  <= 1'b1;
                        state_q       <= ST_LOOKUP;
                    end
                end

                ST_LOOKUP: begin
                    if (lookup_valid_q) begin
                        if (lookup_data_q) begin
                            drop_slot_q                    <= lookup_slot_w;
                            slot_count_q[lookup_slot_w]   <= slot_count_q[lookup_slot_w] + 8'd1;
                            o_acl_block_pulse             <= 1'b1;
                            o_acl_block_slot_valid        <= 1'b1;
                            o_acl_block_slot              <= lookup_slot_w;
                            if (first_last_q) begin
                                state_q <= ST_IDLE;
                            end else begin
                                state_q <= ST_DROP_DRAIN;
                            end
                        end else begin
                            m_axis_tvalid <= 1'b1;
                            m_axis_tdata  <= first_data_q;
                            m_axis_tlast  <= first_last_q;
                            m_axis_tuser  <= first_user_q;
                            state_q       <= ST_PASS;
                        end
                    end
                end

                ST_PASS: begin
                    if (!m_axis_tvalid && s_axis_tvalid && s_axis_tready) begin
                        m_axis_tvalid <= 1'b1;
                        m_axis_tdata  <= s_axis_tdata;
                        m_axis_tlast  <= s_axis_tlast;
                        m_axis_tuser  <= s_axis_tuser;
                    end
                end

                ST_DROP_DRAIN: begin
                    if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                        state_q <= ST_IDLE;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
