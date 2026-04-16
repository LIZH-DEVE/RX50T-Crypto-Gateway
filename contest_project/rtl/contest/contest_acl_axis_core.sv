`timescale 1ns/1ps

module contest_acl_axis_core (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_soft_reset,

    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [7:0]   s_axis_tdata,
    input  wire         s_axis_tlast,
    input  wire [0:0]   s_axis_tuser,

    output reg          m_axis_tvalid,
    input  wire         m_axis_tready,
    output reg  [7:0]   m_axis_tdata,
    output reg          m_axis_tlast,
    output reg  [0:0]   m_axis_tuser,

    input  wire         i_cfg_valid,
    input  wire [2:0]   i_cfg_index,
    input  wire [127:0] i_cfg_key,
    output reg          o_cfg_busy,
    output reg          o_cfg_done,
    output reg          o_cfg_error,

    output reg          o_acl_block_pulse,
    output reg          o_acl_block_slot_valid,
    output reg  [2:0]   o_acl_block_slot,

    output wire [1023:0] o_rule_keys_flat,
    output wire [255:0]  o_rule_counts_flat,
    output wire          o_idle
);

    localparam [2:0] ST_IDLE        = 3'd0;
    localparam [2:0] ST_FILL        = 3'd1;
    localparam [2:0] ST_COMPARE     = 3'd2;
    localparam [2:0] ST_EMIT_ONE    = 3'd3;
    localparam [2:0] ST_PASS_DRAIN  = 3'd4;
    localparam [2:0] ST_DROP_DRAIN  = 3'd5;

    localparam [2:0] CFG_IDLE       = 3'd0;
    localparam [2:0] CFG_WRITE_SLOT = 3'd1;
    localparam [2:0] CFG_RESET_CNT  = 3'd2;
    localparam [2:0] CFG_DONE_PULSE = 3'd3;
    localparam [2:0] CFG_ERR_PULSE  = 3'd4;

    reg [127:0] slot_rule_q [0:7];
    reg [31:0]  slot_count_q [0:7];

    reg [127:0] window_q;
    reg [4:0]   buffer_count_q;
    reg [2:0]   state_q;

    reg [127:0] compare_window_q;
    reg         compare_frame_end_q;
    reg [2:0]   compare_hit_slot_q;
    reg         frame_user_q;

    reg         emit_enter_drain_q;

    reg [2:0]   cfg_state_q;
    reg [2:0]   cfg_slot_q;
    reg [127:0] cfg_new_key_q;

    reg         cfg_duplicate_w;
    integer     idx;

    function automatic [127:0] append_window_byte(
        input [127:0] window,
        input [4:0]   count,
        input [7:0]   data
    );
        reg [127:0] next_window;
        integer     msb;
        begin
            next_window = window;
            if (count < 5'd16) begin
                msb = 127 - (count * 8);
                next_window[msb -: 8] = data;
            end
            append_window_byte = next_window;
        end
    endfunction

    function automatic [127:0] drop_window_byte(input [127:0] window);
        begin
            drop_window_byte = {window[119:0], 8'h00};
        end
    endfunction

    function automatic [2:0] first_match_slot(input [7:0] match_vec);
        begin
            if (match_vec[0]) begin
                first_match_slot = 3'd0;
            end else if (match_vec[1]) begin
                first_match_slot = 3'd1;
            end else if (match_vec[2]) begin
                first_match_slot = 3'd2;
            end else if (match_vec[3]) begin
                first_match_slot = 3'd3;
            end else if (match_vec[4]) begin
                first_match_slot = 3'd4;
            end else if (match_vec[5]) begin
                first_match_slot = 3'd5;
            end else if (match_vec[6]) begin
                first_match_slot = 3'd6;
            end else begin
                first_match_slot = 3'd7;
            end
        end
    endfunction

    wire [127:0] appended_window_w = append_window_byte(window_q, buffer_count_q, s_axis_tdata);
    wire [4:0]   appended_count_w  = buffer_count_q + 5'd1;

    wire [7:0] compare_match_w;
    generate
        genvar gi;
        for (gi = 0; gi < 8; gi = gi + 1) begin : gen_compare
            assign compare_match_w[gi] = (compare_window_q == slot_rule_q[gi]);
        end
    endgenerate

    wire       compare_hit_w      = |compare_match_w;
    wire [2:0] compare_hit_slot_w = first_match_slot(compare_match_w);

    assign o_rule_keys_flat = {
        slot_rule_q[7], slot_rule_q[6], slot_rule_q[5], slot_rule_q[4],
        slot_rule_q[3], slot_rule_q[2], slot_rule_q[1], slot_rule_q[0]
    };

    assign o_rule_counts_flat = {
        slot_count_q[7], slot_count_q[6], slot_count_q[5], slot_count_q[4],
        slot_count_q[3], slot_count_q[2], slot_count_q[1], slot_count_q[0]
    };
    assign o_idle = (cfg_state_q == CFG_IDLE) &&
                    (state_q == ST_IDLE) &&
                    (buffer_count_q == 5'd0) &&
                    !m_axis_tvalid;

    assign s_axis_tready =
        (cfg_state_q == CFG_IDLE) &&
        ((state_q == ST_IDLE) ||
         (state_q == ST_FILL) ||
         (state_q == ST_DROP_DRAIN));

    always @(*) begin
        cfg_duplicate_w = 1'b0;
        for (idx = 0; idx < 8; idx = idx + 1) begin
            if ((i_cfg_index != idx[2:0]) && (slot_rule_q[idx] == i_cfg_key)) begin
                cfg_duplicate_w = 1'b1;
            end
        end
    end

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state_q                <= ST_IDLE;
            window_q               <= 128'd0;
            buffer_count_q         <= 5'd0;
            compare_window_q       <= 128'd0;
            compare_frame_end_q    <= 1'b0;
            compare_hit_slot_q     <= 3'd0;
            frame_user_q           <= 1'b0;
            emit_enter_drain_q     <= 1'b0;
            cfg_state_q            <= CFG_IDLE;
            cfg_slot_q             <= 3'd0;
            cfg_new_key_q          <= 128'd0;
            m_axis_tvalid          <= 1'b0;
            m_axis_tdata           <= 8'd0;
            m_axis_tlast           <= 1'b0;
            m_axis_tuser           <= 1'b0;
            o_cfg_busy             <= 1'b0;
            o_cfg_done             <= 1'b0;
            o_cfg_error            <= 1'b0;
            o_acl_block_pulse      <= 1'b0;
            o_acl_block_slot_valid <= 1'b0;
            o_acl_block_slot       <= 3'd0;
            for (idx = 0; idx < 8; idx = idx + 1) begin
                slot_count_q[idx] <= 32'd0;
            end
            slot_rule_q[0] <= 128'h58595A5750525455_58595A5750525455;
            slot_rule_q[1] <= 128'h0000000000000000_0000000000000000;
            slot_rule_q[2] <= 128'hFFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF;
            slot_rule_q[3] <= 128'h1111111111111111_2222222222222222;
            slot_rule_q[4] <= 128'h3333333333333333_4444444444444444;
            slot_rule_q[5] <= 128'h5555555555555555_6666666666666666;
            slot_rule_q[6] <= 128'h7777777777777777_8888888888888888;
            slot_rule_q[7] <= 128'h9999999999999999_AAAAAAAAAAAAAAAA;
        end else if (i_soft_reset) begin
            state_q                <= ST_IDLE;
            window_q               <= 128'd0;
            buffer_count_q         <= 5'd0;
            compare_window_q       <= 128'd0;
            compare_frame_end_q    <= 1'b0;
            compare_hit_slot_q     <= 3'd0;
            frame_user_q           <= 1'b0;
            emit_enter_drain_q     <= 1'b0;
            cfg_state_q            <= CFG_IDLE;
            cfg_slot_q             <= 3'd0;
            cfg_new_key_q          <= 128'd0;
            m_axis_tvalid          <= 1'b0;
            m_axis_tdata           <= 8'd0;
            m_axis_tlast           <= 1'b0;
            m_axis_tuser           <= 1'b0;
            o_cfg_busy             <= 1'b0;
            o_cfg_done             <= 1'b0;
            o_cfg_error            <= 1'b0;
            o_acl_block_pulse      <= 1'b0;
            o_acl_block_slot_valid <= 1'b0;
            o_acl_block_slot       <= 3'd0;
        end else begin
            o_cfg_done             <= 1'b0;
            o_cfg_error            <= 1'b0;
            o_acl_block_pulse      <= 1'b0;
            o_acl_block_slot_valid <= 1'b0;
            o_cfg_busy             <= (cfg_state_q != CFG_IDLE);

            case (cfg_state_q)
                CFG_IDLE: begin
                    if (i_cfg_valid) begin
                        cfg_slot_q    <= i_cfg_index;
                        cfg_new_key_q <= i_cfg_key;
                        if (cfg_duplicate_w) begin
                            cfg_state_q <= CFG_ERR_PULSE;
                        end else if (slot_rule_q[i_cfg_index] == i_cfg_key) begin
                            cfg_state_q <= CFG_RESET_CNT;
                        end else begin
                            cfg_state_q <= CFG_WRITE_SLOT;
                        end
                    end
                end

                CFG_WRITE_SLOT: begin
                    slot_rule_q[cfg_slot_q] <= cfg_new_key_q;
                    cfg_state_q             <= CFG_RESET_CNT;
                end

                CFG_RESET_CNT: begin
                    slot_count_q[cfg_slot_q] <= 32'd0;
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
                        frame_user_q <= s_axis_tuser[0];
                        if (s_axis_tlast) begin
                            window_q       <= append_window_byte(128'd0, 5'd0, s_axis_tdata);
                            buffer_count_q <= 5'd1;
                            m_axis_tvalid  <= 1'b1;
                            m_axis_tdata   <= s_axis_tdata;
                            m_axis_tlast   <= 1'b1;
                            m_axis_tuser   <= s_axis_tuser[0];
                            state_q        <= ST_PASS_DRAIN;
                        end else begin
                            window_q       <= append_window_byte(128'd0, 5'd0, s_axis_tdata);
                            buffer_count_q <= 5'd1;
                            state_q        <= ST_FILL;
                        end
                    end
                end

                ST_FILL: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (appended_count_w == 5'd16) begin
                            compare_window_q    <= appended_window_w;
                            compare_frame_end_q <= s_axis_tlast;
                            state_q             <= ST_COMPARE;
                        end else begin
                            window_q       <= appended_window_w;
                            buffer_count_q <= appended_count_w;
                            if (s_axis_tlast) begin
                                m_axis_tvalid <= 1'b1;
                                m_axis_tdata  <= appended_window_w[127:120];
                                m_axis_tlast  <= (appended_count_w == 5'd1);
                                m_axis_tuser  <= frame_user_q;
                                state_q       <= ST_PASS_DRAIN;
                            end
                        end
                    end
                end

                ST_COMPARE: begin
                    if (compare_hit_w) begin
                        compare_hit_slot_q                <= compare_hit_slot_w;
                        o_acl_block_pulse                 <= 1'b1;
                        o_acl_block_slot_valid            <= 1'b1;
                        o_acl_block_slot                  <= compare_hit_slot_w;
                        slot_count_q[compare_hit_slot_w]  <= slot_count_q[compare_hit_slot_w] + 32'd1;
                        window_q                          <= 128'd0;
                        buffer_count_q                    <= 5'd0;
                        compare_window_q                  <= 128'd0;
                        if (compare_frame_end_q) begin
                            state_q <= ST_IDLE;
                            frame_user_q <= 1'b0;
                        end else begin
                            state_q <= ST_DROP_DRAIN;
                        end
                    end else if (compare_frame_end_q) begin
                        window_q       <= compare_window_q;
                        buffer_count_q <= 5'd16;
                        m_axis_tvalid  <= 1'b1;
                        m_axis_tdata   <= compare_window_q[127:120];
                        m_axis_tlast   <= 1'b0;
                        m_axis_tuser   <= frame_user_q;
                        state_q        <= ST_PASS_DRAIN;
                    end else begin
                        m_axis_tvalid      <= 1'b1;
                        m_axis_tdata       <= compare_window_q[127:120];
                        m_axis_tlast       <= 1'b0;
                        m_axis_tuser       <= frame_user_q;
                        emit_enter_drain_q <= 1'b0;
                        state_q            <= ST_EMIT_ONE;
                    end
                end

                ST_EMIT_ONE: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        m_axis_tvalid  <= 1'b0;
                        m_axis_tlast   <= 1'b0;
                        m_axis_tuser   <= frame_user_q;
                        window_q       <= drop_window_byte(compare_window_q);
                        buffer_count_q <= 5'd15;
                        state_q        <= ST_FILL;
                    end
                end

                ST_PASS_DRAIN: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (buffer_count_q == 5'd1) begin
                            m_axis_tvalid  <= 1'b0;
                            m_axis_tlast   <= 1'b0;
                            m_axis_tuser   <= 1'b0;
                            frame_user_q   <= 1'b0;
                            window_q       <= 128'd0;
                            buffer_count_q <= 5'd0;
                            state_q        <= ST_IDLE;
                        end else begin
                            window_q       <= drop_window_byte(window_q);
                            buffer_count_q <= buffer_count_q - 5'd1;
                            m_axis_tvalid  <= 1'b1;
                            m_axis_tdata   <= window_q[119:112];
                            m_axis_tlast   <= (buffer_count_q == 5'd2);
                            m_axis_tuser   <= frame_user_q;
                        end
                    end
                end

                ST_DROP_DRAIN: begin
                    if (s_axis_tvalid && s_axis_tready && s_axis_tlast) begin
                        state_q        <= ST_IDLE;
                        frame_user_q   <= 1'b0;
                        window_q       <= 128'd0;
                        buffer_count_q <= 5'd0;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase        end
    end

endmodule
