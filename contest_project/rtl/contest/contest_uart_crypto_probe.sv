`timescale 1ns/1ps

module contest_uart_crypto_probe #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 2_000_000
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    localparam [7:0] ASCII_CFG_ACK = 8'h43; // C
    localparam [7:0] ASCII_CFG_OP  = 8'h03;
    localparam [7:0] ASCII_ERROR   = 8'h45; // E
    localparam [7:0] ASCII_KEYMAP  = 8'h4B; // K
    localparam [7:0] ASCII_NL      = 8'h0A;
    localparam [7:0] ASCII_RULE    = 8'h48; // H
    localparam [7:0] ASCII_STAT    = 8'h53; // S
    localparam [7:0] ASCII_QUERY   = 8'h3F; // ?
    localparam [7:0] MODE_AES      = 8'h41; // A
    localparam [7:0] MODE_SM4      = 8'h53; // S
    localparam       ALG_SM4       = 1'b0;
    localparam       ALG_AES       = 1'b1;

    function automatic is_explicit_mode_length(input [7:0] payload_len);
        begin
            is_explicit_mode_length = (payload_len >= 8'd17) && (payload_len[3:0] == 4'h1);
        end
    endfunction

    function automatic [7:0] stats_byte(
        input [2:0] idx,
        input [7:0] total_frames,
        input [7:0] acl_frames,
        input [7:0] aes_frames,
        input [7:0] sm4_frames,
        input [7:0] err_frames
    );
        begin
            case (idx)
                3'd0: stats_byte = ASCII_STAT;
                3'd1: stats_byte = total_frames;
                3'd2: stats_byte = acl_frames;
                3'd3: stats_byte = aes_frames;
                3'd4: stats_byte = sm4_frames;
                3'd5: stats_byte = err_frames;
                3'd6: stats_byte = ASCII_NL;
                default: stats_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [7:0] flat_rule_byte(input [3:0] idx, input [63:0] flat_bus);
        begin
            case (idx)
                4'd0: flat_rule_byte = ASCII_RULE;
                4'd1: flat_rule_byte = flat_bus[7:0];
                4'd2: flat_rule_byte = flat_bus[15:8];
                4'd3: flat_rule_byte = flat_bus[23:16];
                4'd4: flat_rule_byte = flat_bus[31:24];
                4'd5: flat_rule_byte = flat_bus[39:32];
                4'd6: flat_rule_byte = flat_bus[47:40];
                4'd7: flat_rule_byte = flat_bus[55:48];
                4'd8: flat_rule_byte = flat_bus[63:56];
                4'd9: flat_rule_byte = ASCII_NL;
                default: flat_rule_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [7:0] flat_keymap_byte(input [3:0] idx, input [63:0] flat_bus);
        begin
            case (idx)
                4'd0: flat_keymap_byte = ASCII_KEYMAP;
                4'd1: flat_keymap_byte = flat_bus[7:0];
                4'd2: flat_keymap_byte = flat_bus[15:8];
                4'd3: flat_keymap_byte = flat_bus[23:16];
                4'd4: flat_keymap_byte = flat_bus[31:24];
                4'd5: flat_keymap_byte = flat_bus[39:32];
                4'd6: flat_keymap_byte = flat_bus[47:40];
                4'd7: flat_keymap_byte = flat_bus[55:48];
                4'd8: flat_keymap_byte = flat_bus[63:56];
                4'd9: flat_keymap_byte = ASCII_NL;
                default: flat_keymap_byte = 8'h00;
            endcase
        end
    endfunction

    wire       rx_valid;
    wire [7:0] rx_data;
    wire       rx_frame_error;

    wire       parser_payload_valid;
    wire [7:0] parser_payload_byte;
    wire       parser_frame_done;
    wire       parser_error;
    wire [7:0] parser_payload_len;
    wire [7:0] parser_payload_count;

    reg  [7:0] frame_key_q;
    reg        frame_key_valid_q;
    reg        frame_proto_error_q;
    reg        frame_query_q;
    reg        frame_rule_query_q;
    reg        frame_keymap_query_q;
    reg        frame_cfg_q;
    reg  [7:0] frame_cfg_index_q;
    reg  [7:0] frame_cfg_key_q;
    reg        frame_cfg_key_seen_q;
    reg        frame_algo_sel_q;
    reg        acl_block_seen_q;
    reg        acl_frame_algo_q;
    reg        acl_frame_active_q;

    reg        acl_in_valid_q;
    reg  [7:0] acl_in_data_q;
    reg        acl_in_last_q;
    reg        acl_feed_valid_q;
    reg  [7:0] acl_feed_data_q;
    reg        acl_feed_last_q;
    reg  [7:0] acl_feed_key_q;

    wire       acl_valid;
    wire [7:0] acl_data;
    wire       acl_last;
    wire       acl_blocked;
    wire       acl_block_slot_valid;
    wire [2:0] acl_block_slot;
    wire       acl_cfg_busy;
    wire       acl_cfg_done;
    wire       acl_cfg_error;
    wire [63:0] acl_rule_keys_flat;
    wire [63:0] acl_rule_counts_flat;

    reg        acl_cfg_valid_q;
    reg  [2:0] acl_cfg_index_q;
    reg  [7:0] acl_cfg_key_q;
    reg  [2:0] pending_cfg_ack_idx_q;
    reg  [7:0] pending_cfg_ack_key_q;

    reg        bridge_in_valid_q;
    reg [7:0]  bridge_in_data_q;
    reg        bridge_in_last_q;
    reg        bridge_in_algo_q;
    reg        pending_error_q;
    reg        pending_error_nl_q;
    reg        pending_cfg_ack_q;
    reg  [1:0] pending_cfg_ack_pos_q;
    reg        pending_stats_q;
    reg  [2:0] pending_stats_idx_q;
    reg        pending_rule_stats_q;
    reg  [3:0] pending_rule_stats_idx_q;
    reg        pending_keymap_q;
    reg  [3:0] pending_keymap_idx_q;

    reg  [7:0] stat_total_frames_q;
    reg  [7:0] stat_acl_blocks_q;
    reg  [7:0] stat_aes_frames_q;
    reg  [7:0] stat_sm4_frames_q;
    reg  [7:0] stat_error_frames_q;

    wire       bridge_valid;
    wire [7:0] bridge_data;
    wire       bridge_last;
    wire       tx_ready;

    contest_uart_rx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_rx (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_uart_rx     (i_uart_rx),
        .o_valid       (rx_valid),
        .o_data        (rx_data),
        .o_frame_error (rx_frame_error)
    );

    contest_parser_core #(
        .SOF_BYTE              (8'h55),
        .MAX_PAYLOAD_BYTES     (255),
        .INTERBYTE_TIMEOUT_CLKS((CLK_HZ / BAUD) * 20)
    ) u_parser (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .i_valid        (rx_valid),
        .i_byte         (rx_data),
        .o_in_frame     (),
        .o_frame_start  (),
        .o_payload_valid(parser_payload_valid),
        .o_payload_byte (parser_payload_byte),
        .o_frame_done   (parser_frame_done),
        .o_error        (parser_error),
        .o_payload_len  (parser_payload_len),
        .o_payload_count(parser_payload_count)
    );

    contest_acl_core u_acl (
        .clk               (i_clk),
        .rst_n             (i_rst_n),
        .parser_valid      (acl_feed_valid_q),
        .parser_match_key  (acl_feed_key_q),
        .parser_payload    (acl_feed_data_q),
        .parser_last       (acl_feed_last_q),
        .cfg_valid         (acl_cfg_valid_q),
        .cfg_index         (acl_cfg_index_q),
        .cfg_key           (acl_cfg_key_q),
        .acl_valid         (acl_valid),
        .acl_data          (acl_data),
        .acl_last          (acl_last),
        .acl_blocked       (acl_blocked),
        .acl_block_slot_valid(acl_block_slot_valid),
        .acl_block_slot    (acl_block_slot),
        .cfg_busy          (acl_cfg_busy),
        .cfg_done          (acl_cfg_done),
        .cfg_error         (acl_cfg_error),
        .o_rule_keys_flat  (acl_rule_keys_flat),
        .o_rule_counts_flat(acl_rule_counts_flat)
    );

    contest_crypto_bridge u_bridge (
        .clk          (i_clk),
        .rst_n        (i_rst_n),
        .acl_valid    (bridge_in_valid_q),
        .acl_data     (bridge_in_data_q),
        .acl_last     (bridge_in_last_q),
        .i_algo_sel   (bridge_in_algo_q),
        .uart_tx_ready(tx_ready),
        .bridge_valid (bridge_valid),
        .bridge_data  (bridge_data),
        .bridge_last  (bridge_last)
    );

    contest_uart_tx #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_tx (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_valid  (bridge_valid),
        .i_data   (bridge_data),
        .o_ready  (tx_ready),
        .o_uart_tx(o_uart_tx)
    );

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            acl_feed_valid_q <= 1'b0;
            acl_feed_data_q  <= 8'd0;
            acl_feed_last_q  <= 1'b0;
            acl_feed_key_q   <= 8'd0;
        end else begin
            acl_feed_valid_q <= acl_in_valid_q;
            acl_feed_data_q  <= acl_in_data_q;
            acl_feed_last_q  <= acl_in_last_q;
            acl_feed_key_q   <= frame_key_valid_q ? frame_key_q : acl_in_data_q;
        end
    end

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            frame_key_q            <= 8'd0;
            frame_key_valid_q      <= 1'b0;
            frame_proto_error_q    <= 1'b0;
            frame_query_q          <= 1'b0;
            frame_rule_query_q     <= 1'b0;
            frame_keymap_query_q   <= 1'b0;
            frame_cfg_q            <= 1'b0;
            frame_cfg_index_q      <= 8'd0;
            frame_cfg_key_q        <= 8'd0;
            frame_cfg_key_seen_q   <= 1'b0;
            frame_algo_sel_q       <= ALG_SM4;
            acl_block_seen_q       <= 1'b0;
            acl_frame_algo_q       <= ALG_SM4;
            acl_frame_active_q     <= 1'b0;
            acl_in_valid_q         <= 1'b0;
            acl_in_data_q          <= 8'd0;
            acl_in_last_q          <= 1'b0;
            acl_cfg_valid_q        <= 1'b0;
            acl_cfg_index_q        <= 3'd0;
            acl_cfg_key_q          <= 8'd0;
            pending_cfg_ack_idx_q  <= 3'd0;
            pending_cfg_ack_key_q  <= 8'd0;
            bridge_in_valid_q      <= 1'b0;
            bridge_in_data_q       <= 8'd0;
            bridge_in_last_q       <= 1'b0;
            bridge_in_algo_q       <= ALG_SM4;
            pending_error_q        <= 1'b0;
            pending_error_nl_q     <= 1'b0;
            pending_cfg_ack_q      <= 1'b0;
            pending_cfg_ack_pos_q  <= 2'd0;
            pending_stats_q        <= 1'b0;
            pending_stats_idx_q    <= 3'd0;
            pending_rule_stats_q   <= 1'b0;
            pending_rule_stats_idx_q <= 4'd0;
            pending_keymap_q       <= 1'b0;
            pending_keymap_idx_q   <= 4'd0;
            stat_total_frames_q    <= 8'd0;
            stat_acl_blocks_q      <= 8'd0;
            stat_aes_frames_q      <= 8'd0;
            stat_sm4_frames_q      <= 8'd0;
            stat_error_frames_q    <= 8'd0;
        end else begin
            acl_in_valid_q    <= 1'b0;
            acl_in_data_q     <= 8'd0;
            acl_in_last_q     <= 1'b0;
            acl_cfg_valid_q   <= 1'b0;
            acl_cfg_index_q   <= 3'd0;
            acl_cfg_key_q     <= 8'd0;
            bridge_in_valid_q <= 1'b0;
            bridge_in_data_q  <= 8'd0;
            bridge_in_last_q  <= 1'b0;
            bridge_in_algo_q  <= ALG_SM4;

            if (parser_error || rx_frame_error) begin
                pending_error_q     <= 1'b1;
                stat_error_frames_q <= stat_error_frames_q + 8'd1;
                frame_key_valid_q   <= 1'b0;
                frame_proto_error_q <= 1'b0;
                frame_query_q       <= 1'b0;
                frame_rule_query_q  <= 1'b0;
                frame_keymap_query_q <= 1'b0;
                frame_cfg_q         <= 1'b0;
                frame_cfg_key_seen_q <= 1'b0;
                frame_algo_sel_q    <= ALG_SM4;
            end

            if (parser_payload_valid) begin
                if (acl_cfg_busy) begin
                    frame_proto_error_q <= 1'b1;
                end else if (parser_payload_count == 8'd1) begin
                    frame_key_q          <= 8'd0;
                    frame_key_valid_q    <= 1'b0;
                    acl_block_seen_q     <= 1'b0;
                    frame_cfg_index_q    <= 8'd0;
                    frame_cfg_key_q      <= 8'd0;
                    frame_cfg_key_seen_q <= 1'b0;

                    if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_QUERY)) begin
                        frame_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_RULE)) begin
                        frame_rule_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_KEYMAP)) begin
                        frame_keymap_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd3) && (parser_payload_byte == ASCII_CFG_OP)) begin
                        frame_cfg_q <= 1'b1;
                    end else if (is_explicit_mode_length(parser_payload_len)) begin
                        if (parser_payload_byte == MODE_AES) begin
                            frame_algo_sel_q <= ALG_AES;
                        end else if (parser_payload_byte == MODE_SM4) begin
                            frame_algo_sel_q <= ALG_SM4;
                        end else begin
                            frame_proto_error_q <= 1'b1;
                        end
                    end else begin
                        frame_algo_sel_q   <= ALG_SM4;
                        frame_key_q        <= parser_payload_byte;
                        frame_key_valid_q  <= 1'b1;
                        acl_frame_algo_q   <= ALG_SM4;
                        acl_frame_active_q <= 1'b1;
                        acl_in_valid_q     <= 1'b1;
                        acl_in_data_q      <= parser_payload_byte;
                        acl_in_last_q      <= parser_frame_done;
                    end
                end else if (frame_cfg_q) begin
                    if (parser_payload_count == 8'd2) begin
                        frame_cfg_index_q <= parser_payload_byte;
                    end else if (parser_payload_count == 8'd3) begin
                        frame_cfg_key_q      <= parser_payload_byte;
                        frame_cfg_key_seen_q <= 1'b1;
                    end
                end else if (!frame_query_q && !frame_rule_query_q && !frame_keymap_query_q && !frame_proto_error_q) begin
                    if (!frame_key_valid_q) begin
                        frame_key_q       <= parser_payload_byte;
                        frame_key_valid_q <= 1'b1;
                    end
                    if (!acl_frame_active_q) begin
                        acl_frame_algo_q   <= frame_algo_sel_q;
                        acl_frame_active_q <= 1'b1;
                    end
                    acl_in_valid_q <= 1'b1;
                    acl_in_data_q  <= parser_payload_byte;
                    acl_in_last_q  <= parser_frame_done;
                end
            end

            if (parser_frame_done) begin
                if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                      (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_QUERY))) ||
                    frame_query_q) begin
                    pending_stats_q     <= 1'b1;
                    pending_stats_idx_q <= 3'd0;
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                               (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_RULE))) ||
                              frame_rule_query_q) begin
                    pending_rule_stats_q     <= 1'b1;
                    pending_rule_stats_idx_q <= 4'd0;
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                               (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_KEYMAP))) ||
                              frame_keymap_query_q) begin
                    pending_keymap_q     <= 1'b1;
                    pending_keymap_idx_q <= 4'd0;
                end else if (frame_cfg_q) begin
                    if ((!frame_cfg_key_seen_q &&
                         !(parser_payload_valid && (parser_payload_count == 8'd3))) ||
                        (((parser_payload_valid && (parser_payload_count == 8'd2)) ?
                          parser_payload_byte : frame_cfg_index_q) > 8'd7)) begin
                        pending_error_q     <= 1'b1;
                        stat_error_frames_q <= stat_error_frames_q + 8'd1;
                    end else begin
                        acl_cfg_valid_q       <= 1'b1;
                        acl_cfg_index_q       <= (parser_payload_valid && (parser_payload_count == 8'd2)) ?
                                                 parser_payload_byte[2:0] : frame_cfg_index_q[2:0];
                        acl_cfg_key_q         <= (parser_payload_valid && (parser_payload_count == 8'd3)) ?
                                                 parser_payload_byte : frame_cfg_key_q;
                        pending_cfg_ack_idx_q <= (parser_payload_valid && (parser_payload_count == 8'd2)) ?
                                                 parser_payload_byte[2:0] : frame_cfg_index_q[2:0];
                        pending_cfg_ack_key_q <= (parser_payload_valid && (parser_payload_count == 8'd3)) ?
                                                 parser_payload_byte : frame_cfg_key_q;
                    end
                end else if (frame_proto_error_q) begin
                    pending_error_q     <= 1'b1;
                    stat_error_frames_q <= stat_error_frames_q + 8'd1;
                end else if (frame_key_valid_q) begin
                    stat_total_frames_q <= stat_total_frames_q + 8'd1;
                    if (acl_block_seen_q) begin
                        stat_acl_blocks_q <= stat_acl_blocks_q + 8'd1;
                    end else if (frame_algo_sel_q == ALG_AES) begin
                        stat_aes_frames_q <= stat_aes_frames_q + 8'd1;
                    end else begin
                        stat_sm4_frames_q <= stat_sm4_frames_q + 8'd1;
                    end
                end

                frame_key_q           <= 8'd0;
                frame_key_valid_q     <= 1'b0;
                frame_proto_error_q   <= 1'b0;
                frame_query_q         <= 1'b0;
                frame_rule_query_q    <= 1'b0;
                frame_keymap_query_q  <= 1'b0;
                frame_cfg_q           <= 1'b0;
                frame_cfg_index_q     <= 8'd0;
                frame_cfg_key_q       <= 8'd0;
                frame_cfg_key_seen_q  <= 1'b0;
                frame_algo_sel_q      <= ALG_SM4;
                acl_block_seen_q      <= 1'b0;
            end

            if (acl_blocked) begin
                acl_block_seen_q <= 1'b1;
            end

            if (acl_valid && acl_last) begin
                acl_frame_active_q <= 1'b0;
                acl_frame_algo_q   <= ALG_SM4;
            end

            if (acl_cfg_done) begin
                pending_cfg_ack_q     <= 1'b1;
                pending_cfg_ack_pos_q <= 2'd0;
            end else if (acl_cfg_error) begin
                pending_error_q     <= 1'b1;
                stat_error_frames_q <= stat_error_frames_q + 8'd1;
            end

            if (pending_error_q) begin
                bridge_in_valid_q  <= 1'b1;
                bridge_in_data_q   <= ASCII_ERROR;
                bridge_in_last_q   <= 1'b0;
                bridge_in_algo_q   <= ALG_SM4;
                pending_error_q    <= 1'b0;
                pending_error_nl_q <= 1'b1;
            end else if (pending_error_nl_q) begin
                bridge_in_valid_q  <= 1'b1;
                bridge_in_data_q   <= ASCII_NL;
                bridge_in_last_q   <= 1'b1;
                bridge_in_algo_q   <= ALG_SM4;
                pending_error_nl_q <= 1'b0;
            end else if (pending_cfg_ack_q) begin
                bridge_in_valid_q <= 1'b1;
                bridge_in_algo_q  <= ALG_SM4;
                case (pending_cfg_ack_pos_q)
                    2'd0: bridge_in_data_q <= ASCII_CFG_ACK;
                    2'd1: bridge_in_data_q <= {5'd0, pending_cfg_ack_idx_q};
                    2'd2: bridge_in_data_q <= pending_cfg_ack_key_q;
                    default: bridge_in_data_q <= ASCII_NL;
                endcase
                bridge_in_last_q <= (pending_cfg_ack_pos_q == 2'd3);
                if (pending_cfg_ack_pos_q == 2'd3) begin
                    pending_cfg_ack_q     <= 1'b0;
                    pending_cfg_ack_pos_q <= 2'd0;
                end else begin
                    pending_cfg_ack_pos_q <= pending_cfg_ack_pos_q + 2'd1;
                end
            end else if (pending_keymap_q) begin
                bridge_in_valid_q <= 1'b1;
                bridge_in_data_q  <= flat_keymap_byte(pending_keymap_idx_q, acl_rule_keys_flat);
                bridge_in_last_q  <= (pending_keymap_idx_q == 4'd9);
                bridge_in_algo_q  <= ALG_SM4;
                if (pending_keymap_idx_q == 4'd9) begin
                    pending_keymap_q     <= 1'b0;
                    pending_keymap_idx_q <= 4'd0;
                end else begin
                    pending_keymap_idx_q <= pending_keymap_idx_q + 4'd1;
                end
            end else if (pending_rule_stats_q) begin
                bridge_in_valid_q <= 1'b1;
                bridge_in_data_q  <= flat_rule_byte(pending_rule_stats_idx_q, acl_rule_counts_flat);
                bridge_in_last_q  <= (pending_rule_stats_idx_q == 4'd9);
                bridge_in_algo_q  <= ALG_SM4;
                if (pending_rule_stats_idx_q == 4'd9) begin
                    pending_rule_stats_q     <= 1'b0;
                    pending_rule_stats_idx_q <= 4'd0;
                end else begin
                    pending_rule_stats_idx_q <= pending_rule_stats_idx_q + 4'd1;
                end
            end else if (pending_stats_q) begin
                bridge_in_valid_q <= 1'b1;
                bridge_in_data_q  <= stats_byte(
                    pending_stats_idx_q,
                    stat_total_frames_q,
                    stat_acl_blocks_q,
                    stat_aes_frames_q,
                    stat_sm4_frames_q,
                    stat_error_frames_q
                );
                bridge_in_last_q  <= (pending_stats_idx_q == 3'd6);
                bridge_in_algo_q  <= ALG_SM4;
                if (pending_stats_idx_q == 3'd6) begin
                    pending_stats_q     <= 1'b0;
                    pending_stats_idx_q <= 3'd0;
                end else begin
                    pending_stats_idx_q <= pending_stats_idx_q + 3'd1;
                end
            end else if (acl_valid) begin
                bridge_in_valid_q <= 1'b1;
                bridge_in_data_q  <= acl_data;
                bridge_in_last_q  <= acl_last;
                bridge_in_algo_q  <= acl_frame_algo_q;
            end
        end
    end

endmodule
