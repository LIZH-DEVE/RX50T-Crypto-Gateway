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

    localparam [7:0] ASCII_CFG_ACK = 8'h43;
    localparam [7:0] ASCII_CFG_OP  = 8'h03;
    localparam [7:0] ASCII_ERROR   = 8'h45;
    localparam [7:0] ASCII_KEYMAP  = 8'h4B;
    localparam [7:0] ASCII_NL      = 8'h0A;
    localparam [7:0] ASCII_PMU_CLR = 8'h4A;
    localparam [7:0] ASCII_PMU_QRY = 8'h50;
    localparam [7:0] ASCII_QUERY   = 8'h3F;
    localparam [7:0] ASCII_RULE    = 8'h48;
    localparam [7:0] ASCII_STAT    = 8'h53;
    localparam [7:0] MODE_AES      = 8'h41;
    localparam [7:0] MODE_SM4      = 8'h53;
    localparam       ALG_SM4       = 1'b0;
    localparam       ALG_AES       = 1'b1;

    localparam [7:0] STREAM_CAP_QUERY = 8'h57;
    localparam [7:0] STREAM_START_OP  = 8'h4D;
    localparam [7:0] STREAM_CIPHER_OP = 8'h52;
    localparam [7:0] STREAM_BLOCK_OP  = 8'h42;

    localparam integer STREAM_CHUNK_BYTES = 128;
    localparam integer STREAM_WINDOW      = 8;
    localparam [31:0] PMU_CLK_HZ          = CLK_HZ;

    localparam [7:0] STREAM_ERR_FORMAT = 8'h01;
    localparam [7:0] STREAM_ERR_STATE  = 8'h02;
    localparam [7:0] STREAM_ERR_SEQ    = 8'h03;
    localparam [7:0] STREAM_ERR_WINDOW = 8'h04;

    localparam [2:0] STREAM_TX_NONE       = 3'd0;
    localparam [2:0] STREAM_TX_CAP        = 3'd1;
    localparam [2:0] STREAM_TX_START_ACK  = 3'd2;
    localparam [2:0] STREAM_TX_BLOCK      = 3'd3;
    localparam [2:0] STREAM_TX_ERROR      = 3'd4;
    localparam [2:0] STREAM_TX_CIPHER_HDR = 3'd5;
    localparam [1:0] PMU_TX_NONE          = 2'd0;
    localparam [1:0] PMU_TX_SNAPSHOT      = 2'd1;
    localparam [1:0] PMU_TX_CLEAR_ACK     = 2'd2;

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

    function automatic [7:0] stream_tx_byte(
        input [2:0] kind,
        input [2:0] idx,
        input [7:0] seq,
        input [2:0] slot,
        input [7:0] code
    );
        begin
            case (kind)
                STREAM_TX_CAP: begin
                    case (idx)
                        3'd0: stream_tx_byte = 8'h55;
                        3'd1: stream_tx_byte = 8'h04;
                        3'd2: stream_tx_byte = STREAM_CAP_QUERY;
                        3'd3: stream_tx_byte = STREAM_CHUNK_BYTES[7:0];
                        3'd4: stream_tx_byte = STREAM_WINDOW[7:0];
                        default: stream_tx_byte = 8'h07;
                    endcase
                end
                STREAM_TX_START_ACK: begin
                    case (idx)
                        3'd0: stream_tx_byte = 8'h55;
                        3'd1: stream_tx_byte = 8'h02;
                        3'd2: stream_tx_byte = STREAM_START_OP;
                        default: stream_tx_byte = 8'h00;
                    endcase
                end
                STREAM_TX_BLOCK: begin
                    case (idx)
                        3'd0: stream_tx_byte = 8'h55;
                        3'd1: stream_tx_byte = 8'h03;
                        3'd2: stream_tx_byte = STREAM_BLOCK_OP;
                        3'd3: stream_tx_byte = seq;
                        default: stream_tx_byte = {5'd0, slot};
                    endcase
                end
                STREAM_TX_ERROR: begin
                    case (idx)
                        3'd0: stream_tx_byte = 8'h55;
                        3'd1: stream_tx_byte = 8'h02;
                        3'd2: stream_tx_byte = ASCII_ERROR;
                        default: stream_tx_byte = code;
                    endcase
                end
                STREAM_TX_CIPHER_HDR: begin
                    case (idx)
                        3'd0: stream_tx_byte = 8'h55;
                        3'd1: stream_tx_byte = 8'h82;
                        3'd2: stream_tx_byte = STREAM_CIPHER_OP;
                        default: stream_tx_byte = seq;
                    endcase
                end
                default: stream_tx_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [2:0] stream_tx_last_idx(input [2:0] kind);
        begin
            case (kind)
                STREAM_TX_CAP:        stream_tx_last_idx = 3'd5;
                STREAM_TX_START_ACK:  stream_tx_last_idx = 3'd3;
                STREAM_TX_BLOCK:      stream_tx_last_idx = 3'd4;
                STREAM_TX_ERROR:      stream_tx_last_idx = 3'd3;
                STREAM_TX_CIPHER_HDR: stream_tx_last_idx = 3'd3;
                default:              stream_tx_last_idx = 3'd0;
            endcase
        end
    endfunction

    function automatic [7:0] be32_byte(input [1:0] idx, input [31:0] value);
        begin
            case (idx)
                2'd0: be32_byte = value[31:24];
                2'd1: be32_byte = value[23:16];
                2'd2: be32_byte = value[15:8];
                default: be32_byte = value[7:0];
            endcase
        end
    endfunction

    function automatic [7:0] be64_byte(input [2:0] idx, input [63:0] value);
        begin
            case (idx)
                3'd0: be64_byte = value[63:56];
                3'd1: be64_byte = value[55:48];
                3'd2: be64_byte = value[47:40];
                3'd3: be64_byte = value[39:32];
                3'd4: be64_byte = value[31:24];
                3'd5: be64_byte = value[23:16];
                3'd6: be64_byte = value[15:8];
                default: be64_byte = value[7:0];
            endcase
        end
    endfunction

    function automatic [7:0] pmu_tx_byte(
        input [1:0]  kind,
        input [5:0]  idx,
        input [63:0] global_cycles,
        input [63:0] crypto_active_cycles,
        input [63:0] uart_tx_stall_cycles,
        input [63:0] credit_block_cycles,
        input [63:0] acl_block_events
    );
        begin
            case (kind)
                PMU_TX_CLEAR_ACK: begin
                    case (idx)
                        6'd0: pmu_tx_byte = 8'h55;
                        6'd1: pmu_tx_byte = 8'h02;
                        6'd2: pmu_tx_byte = ASCII_PMU_CLR;
                        default: pmu_tx_byte = 8'h00;
                    endcase
                end
                PMU_TX_SNAPSHOT: begin
                    case (idx)
                        6'd0: pmu_tx_byte = 8'h55;
                        6'd1: pmu_tx_byte = 8'h2E;
                        6'd2: pmu_tx_byte = ASCII_PMU_QRY;
                        6'd3: pmu_tx_byte = 8'h01;
                        6'd4,
                        6'd5,
                        6'd6,
                        6'd7: pmu_tx_byte = be32_byte(idx[1:0], PMU_CLK_HZ);
                        6'd8,
                        6'd9,
                        6'd10,
                        6'd11,
                        6'd12,
                        6'd13,
                        6'd14,
                        6'd15: pmu_tx_byte = be64_byte(idx[2:0], global_cycles);
                        6'd16,
                        6'd17,
                        6'd18,
                        6'd19,
                        6'd20,
                        6'd21,
                        6'd22,
                        6'd23: pmu_tx_byte = be64_byte(idx[2:0], crypto_active_cycles);
                        6'd24,
                        6'd25,
                        6'd26,
                        6'd27,
                        6'd28,
                        6'd29,
                        6'd30,
                        6'd31: pmu_tx_byte = be64_byte(idx[2:0], uart_tx_stall_cycles);
                        6'd32,
                        6'd33,
                        6'd34,
                        6'd35,
                        6'd36,
                        6'd37,
                        6'd38,
                        6'd39: pmu_tx_byte = be64_byte(idx[2:0], credit_block_cycles);
                        6'd40,
                        6'd41,
                        6'd42,
                        6'd43,
                        6'd44,
                        6'd45,
                        6'd46,
                        6'd47: pmu_tx_byte = be64_byte(idx[2:0], acl_block_events);
                        default: pmu_tx_byte = 8'h00;
                    endcase
                end
                default: pmu_tx_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [5:0] pmu_tx_last_idx(input [1:0] kind);
        begin
            case (kind)
                PMU_TX_SNAPSHOT:  pmu_tx_last_idx = 6'd47;
                PMU_TX_CLEAR_ACK: pmu_tx_last_idx = 6'd3;
                default:          pmu_tx_last_idx = 6'd0;
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
    reg        frame_pmu_query_q;
    reg        frame_pmu_clear_q;
    reg        frame_cfg_q;
    reg  [7:0] frame_cfg_index_q;
    reg  [7:0] frame_cfg_key_q;
    reg        frame_cfg_key_seen_q;
    reg        frame_algo_sel_q;
    reg        frame_stream_cap_q;
    reg        frame_stream_start_q;
    reg        frame_stream_chunk_q;
    reg        frame_stream_error_q;
    reg  [7:0] frame_stream_error_code_q;
    reg        frame_stream_start_alg_q;
    reg [15:0] frame_stream_start_total_q;
    reg  [7:0] frame_stream_seq_q;
    reg        frame_stream_block_q;
    reg  [2:0] frame_stream_block_slot_q;
    reg        acl_block_seen_q;
    reg        acl_frame_algo_q;
    reg        acl_frame_active_q;
    reg        acl_frame_stream_q;
    reg        acl_stream_drop_q;
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
    reg        stream_session_active_q;
    reg        stream_session_fault_q;
    reg        stream_session_algo_q;
    reg  [7:0] stream_expected_seq_q;
    reg        stream_expected_valid_q;
    reg [15:0] stream_session_total_q;
    reg  [7:0] stream_seq_fifo_q [0:7];
    reg  [2:0] stream_seq_wr_ptr_q;
    reg  [2:0] stream_seq_rd_ptr_q;
    reg  [3:0] stream_seq_count_q;
    reg  [7:0] stream_payload_bytes_left_q;
    reg  [2:0] stream_tx_kind_q;
    reg  [2:0] stream_tx_idx_q;
    reg  [7:0] stream_tx_seq_q;
    reg  [2:0] stream_tx_slot_q;
    reg  [7:0] stream_tx_code_q;
    reg        pmu_armed_q;
    reg [63:0] pmu_global_cycles_q;
    reg [63:0] pmu_crypto_active_cycles_q;
    reg [63:0] pmu_uart_tx_stall_cycles_q;
    reg [63:0] pmu_stream_credit_block_cycles_q;
    reg [63:0] pmu_acl_block_events_q;
    reg [63:0] pmu_snap_global_cycles_q;
    reg [63:0] pmu_snap_crypto_active_cycles_q;
    reg [63:0] pmu_snap_uart_tx_stall_cycles_q;
    reg [63:0] pmu_snap_stream_credit_block_cycles_q;
    reg [63:0] pmu_snap_acl_block_events_q;
    reg  [1:0] pmu_tx_kind_q;
    reg  [5:0] pmu_tx_idx_q;

    wire       bridge_valid;
    wire [7:0] bridge_data;
    wire       bridge_last;
    wire       pmu_crypto_active_w;
    wire       tx_ready;
    wire       pmu_tx_active_w;
    wire [7:0] pmu_tx_data_w;
    wire       stream_tx_active_w;
    wire [7:0] stream_tx_data_w;
    wire       bridge_tx_ready_w;
    wire       tx_mux_valid_w;
    wire [7:0] tx_mux_data_w;
    wire       pmu_uart_tx_stall_w;
    wire       pmu_stream_credit_block_w;
    wire       pmu_count_enable_w;

    assign pmu_tx_active_w    = (pmu_tx_kind_q != PMU_TX_NONE);
    assign pmu_tx_data_w      = pmu_tx_byte(
                                    pmu_tx_kind_q,
                                    pmu_tx_idx_q,
                                    pmu_snap_global_cycles_q,
                                    pmu_snap_crypto_active_cycles_q,
                                    pmu_snap_uart_tx_stall_cycles_q,
                                    pmu_snap_stream_credit_block_cycles_q,
                                    pmu_snap_acl_block_events_q
                                );
    assign stream_tx_active_w = (stream_tx_kind_q != STREAM_TX_NONE);
    assign stream_tx_data_w   = stream_tx_byte(stream_tx_kind_q, stream_tx_idx_q, stream_tx_seq_q, stream_tx_slot_q, stream_tx_code_q);
    assign bridge_tx_ready_w = tx_ready &&
                               !pmu_tx_active_w &&
                               !stream_tx_active_w &&
                               !frame_stream_chunk_q &&
                               !((stream_payload_bytes_left_q == 8'd0) && (stream_seq_count_q != 4'd0));
    assign tx_mux_valid_w    = pmu_tx_active_w ? 1'b1 :
                               (stream_tx_active_w ? 1'b1 :
                               (bridge_valid && !frame_stream_chunk_q &&
                                ((stream_payload_bytes_left_q != 8'd0) || (stream_seq_count_q == 4'd0))));
    assign tx_mux_data_w     = pmu_tx_active_w ? pmu_tx_data_w :
                               (stream_tx_active_w ? stream_tx_data_w : bridge_data);
    assign pmu_uart_tx_stall_w = tx_mux_valid_w && !tx_ready;
    assign pmu_stream_credit_block_w =
        stream_session_active_q &&
        (stream_seq_count_q == STREAM_WINDOW[3:0]) &&
        !pmu_crypto_active_w &&
        !pmu_uart_tx_stall_w;
    assign pmu_count_enable_w =
        pmu_armed_q &&
        !frame_pmu_query_q &&
        !frame_pmu_clear_q &&
        !pmu_tx_active_w;

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
        .clk                 (i_clk),
        .rst_n               (i_rst_n),
        .parser_valid        (acl_feed_valid_q),
        .parser_match_key    (acl_feed_key_q),
        .parser_payload      (acl_feed_data_q),
        .parser_last         (acl_feed_last_q),
        .cfg_valid           (acl_cfg_valid_q),
        .cfg_index           (acl_cfg_index_q),
        .cfg_key             (acl_cfg_key_q),
        .acl_valid           (acl_valid),
        .acl_data            (acl_data),
        .acl_last            (acl_last),
        .acl_blocked         (acl_blocked),
        .acl_block_slot_valid(acl_block_slot_valid),
        .acl_block_slot      (acl_block_slot),
        .cfg_busy            (acl_cfg_busy),
        .cfg_done            (acl_cfg_done),
        .cfg_error           (acl_cfg_error),
        .o_rule_keys_flat    (acl_rule_keys_flat),
        .o_rule_counts_flat  (acl_rule_counts_flat)
    );

    contest_crypto_bridge u_bridge (
        .clk          (i_clk),
        .rst_n        (i_rst_n),
        .acl_valid    (bridge_in_valid_q),
        .acl_data     (bridge_in_data_q),
        .acl_last     (bridge_in_last_q),
        .i_algo_sel   (bridge_in_algo_q),
        .uart_tx_ready(bridge_tx_ready_w),
        .o_pmu_crypto_active(pmu_crypto_active_w),
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
        .i_valid  (tx_mux_valid_w),
        .i_data   (tx_mux_data_w),
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
            frame_key_q               <= 8'd0;
            frame_key_valid_q         <= 1'b0;
            frame_proto_error_q       <= 1'b0;
            frame_query_q             <= 1'b0;
            frame_rule_query_q        <= 1'b0;
            frame_keymap_query_q      <= 1'b0;
            frame_pmu_query_q         <= 1'b0;
            frame_pmu_clear_q         <= 1'b0;
            frame_cfg_q               <= 1'b0;
            frame_cfg_index_q         <= 8'd0;
            frame_cfg_key_q           <= 8'd0;
            frame_cfg_key_seen_q      <= 1'b0;
            frame_algo_sel_q          <= ALG_SM4;
            frame_stream_cap_q        <= 1'b0;
            frame_stream_start_q      <= 1'b0;
            frame_stream_chunk_q      <= 1'b0;
            frame_stream_error_q      <= 1'b0;
            frame_stream_error_code_q <= 8'd0;
            frame_stream_start_alg_q  <= ALG_SM4;
            frame_stream_start_total_q <= 16'd0;
            frame_stream_seq_q        <= 8'd0;
            frame_stream_block_q      <= 1'b0;
            frame_stream_block_slot_q <= 3'd0;
            acl_block_seen_q          <= 1'b0;
            acl_frame_algo_q          <= ALG_SM4;
            acl_frame_active_q        <= 1'b0;
            acl_frame_stream_q        <= 1'b0;
            acl_stream_drop_q         <= 1'b0;
            acl_in_valid_q            <= 1'b0;
            acl_in_data_q             <= 8'd0;
            acl_in_last_q             <= 1'b0;
            acl_cfg_valid_q           <= 1'b0;
            acl_cfg_index_q           <= 3'd0;
            acl_cfg_key_q             <= 8'd0;
            pending_cfg_ack_idx_q     <= 3'd0;
            pending_cfg_ack_key_q     <= 8'd0;
            bridge_in_valid_q         <= 1'b0;
            bridge_in_data_q          <= 8'd0;
            bridge_in_last_q          <= 1'b0;
            bridge_in_algo_q          <= ALG_SM4;
            pending_error_q           <= 1'b0;
            pending_error_nl_q        <= 1'b0;
            pending_cfg_ack_q         <= 1'b0;
            pending_cfg_ack_pos_q     <= 2'd0;
            pending_stats_q           <= 1'b0;
            pending_stats_idx_q       <= 3'd0;
            pending_rule_stats_q      <= 1'b0;
            pending_rule_stats_idx_q  <= 4'd0;
            pending_keymap_q          <= 1'b0;
            pending_keymap_idx_q      <= 4'd0;
            stat_total_frames_q       <= 8'd0;
            stat_acl_blocks_q         <= 8'd0;
            stat_aes_frames_q         <= 8'd0;
            stat_sm4_frames_q         <= 8'd0;
            stat_error_frames_q       <= 8'd0;
            stream_session_active_q   <= 1'b0;
            stream_session_fault_q    <= 1'b0;
            stream_session_algo_q     <= ALG_SM4;
            stream_expected_seq_q     <= 8'd0;
            stream_expected_valid_q   <= 1'b0;
            stream_session_total_q    <= 16'd0;
            stream_seq_wr_ptr_q       <= 3'd0;
            stream_seq_rd_ptr_q       <= 3'd0;
            stream_seq_count_q        <= 4'd0;
            stream_payload_bytes_left_q <= 8'd0;
            stream_tx_kind_q          <= STREAM_TX_NONE;
            stream_tx_idx_q           <= 3'd0;
            stream_tx_seq_q           <= 8'd0;
            stream_tx_slot_q          <= 3'd0;
            stream_tx_code_q          <= 8'd0;
            pmu_armed_q               <= 1'b0;
            pmu_global_cycles_q       <= 64'd0;
            pmu_crypto_active_cycles_q <= 64'd0;
            pmu_uart_tx_stall_cycles_q <= 64'd0;
            pmu_stream_credit_block_cycles_q <= 64'd0;
            pmu_acl_block_events_q    <= 64'd0;
            pmu_snap_global_cycles_q  <= 64'd0;
            pmu_snap_crypto_active_cycles_q <= 64'd0;
            pmu_snap_uart_tx_stall_cycles_q <= 64'd0;
            pmu_snap_stream_credit_block_cycles_q <= 64'd0;
            pmu_snap_acl_block_events_q <= 64'd0;
            pmu_tx_kind_q             <= PMU_TX_NONE;
            pmu_tx_idx_q              <= 6'd0;
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

            if (pmu_count_enable_w) begin
                pmu_global_cycles_q <= pmu_global_cycles_q + 64'd1;
                if (pmu_crypto_active_w) begin
                    pmu_crypto_active_cycles_q <= pmu_crypto_active_cycles_q + 64'd1;
                end
                if (pmu_uart_tx_stall_w) begin
                    pmu_uart_tx_stall_cycles_q <= pmu_uart_tx_stall_cycles_q + 64'd1;
                end
                if (pmu_stream_credit_block_w) begin
                    pmu_stream_credit_block_cycles_q <= pmu_stream_credit_block_cycles_q + 64'd1;
                end
            end

            if (pmu_tx_active_w && tx_ready) begin
                if (pmu_tx_idx_q == pmu_tx_last_idx(pmu_tx_kind_q)) begin
                    pmu_tx_kind_q <= PMU_TX_NONE;
                    pmu_tx_idx_q  <= 6'd0;
                end else begin
                    pmu_tx_idx_q <= pmu_tx_idx_q + 6'd1;
                end
            end

            if (stream_tx_active_w && tx_ready) begin
                if (stream_tx_idx_q == stream_tx_last_idx(stream_tx_kind_q)) begin
                    stream_tx_kind_q <= STREAM_TX_NONE;
                    stream_tx_idx_q  <= 3'd0;
                end else begin
                    stream_tx_idx_q <= stream_tx_idx_q + 3'd1;
                end
            end

            if (!stream_tx_active_w &&
                (stream_payload_bytes_left_q == 8'd0) &&
                (stream_seq_count_q != 4'd0) &&
                bridge_valid &&
                !frame_stream_chunk_q) begin
                stream_tx_kind_q          <= STREAM_TX_CIPHER_HDR;
                stream_tx_idx_q           <= 3'd0;
                stream_tx_seq_q           <= stream_seq_fifo_q[stream_seq_rd_ptr_q];
                stream_seq_rd_ptr_q       <= stream_seq_rd_ptr_q + 3'd1;
                stream_seq_count_q        <= stream_seq_count_q - 4'd1;
                stream_payload_bytes_left_q <= 8'd128;
            end else if (!stream_tx_active_w &&
                         tx_ready &&
                         bridge_valid &&
                         !frame_stream_chunk_q &&
                         (stream_payload_bytes_left_q != 8'd0)) begin
                stream_payload_bytes_left_q <= stream_payload_bytes_left_q - 8'd1;
            end

            if (parser_error || rx_frame_error) begin
                pending_error_q           <= 1'b1;
                stat_error_frames_q       <= stat_error_frames_q + 8'd1;
                frame_key_valid_q         <= 1'b0;
                frame_proto_error_q       <= 1'b0;
                frame_query_q             <= 1'b0;
                frame_rule_query_q        <= 1'b0;
                frame_keymap_query_q      <= 1'b0;
                frame_pmu_query_q         <= 1'b0;
                frame_pmu_clear_q         <= 1'b0;
                frame_cfg_q               <= 1'b0;
                frame_cfg_key_seen_q      <= 1'b0;
                frame_algo_sel_q          <= ALG_SM4;
                frame_stream_cap_q        <= 1'b0;
                frame_stream_start_q      <= 1'b0;
                frame_stream_chunk_q      <= 1'b0;
                frame_stream_error_q      <= 1'b0;
                frame_stream_error_code_q <= 8'd0;
                frame_stream_block_q      <= 1'b0;
                if (stream_session_active_q) begin
                    stream_session_active_q <= 1'b0;
                    stream_session_fault_q  <= 1'b1;
                    stream_expected_valid_q <= 1'b0;
                end
            end

            if (parser_payload_valid) begin
                if (acl_cfg_busy) begin
                    frame_proto_error_q <= 1'b1;
                end else if (parser_payload_count == 8'd1) begin
                    frame_key_q               <= 8'd0;
                    frame_key_valid_q         <= 1'b0;
                    acl_block_seen_q          <= 1'b0;
                    frame_cfg_index_q         <= 8'd0;
                    frame_cfg_key_q           <= 8'd0;
                    frame_cfg_key_seen_q      <= 1'b0;
                    frame_stream_cap_q        <= 1'b0;
                    frame_pmu_query_q         <= 1'b0;
                    frame_pmu_clear_q         <= 1'b0;
                    frame_stream_start_q      <= 1'b0;
                    frame_stream_chunk_q      <= 1'b0;
                    frame_stream_error_q      <= 1'b0;
                    frame_stream_error_code_q <= 8'd0;
                    frame_stream_start_alg_q  <= ALG_SM4;
                    frame_stream_start_total_q <= 16'd0;
                    frame_stream_seq_q        <= 8'd0;
                    frame_stream_block_q      <= 1'b0;
                    frame_stream_block_slot_q <= 3'd0;

                    if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_QUERY)) begin
                        frame_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_RULE)) begin
                        frame_rule_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_KEYMAP)) begin
                        frame_keymap_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_PMU_QRY)) begin
                        frame_pmu_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_PMU_CLR)) begin
                        frame_pmu_clear_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == STREAM_CAP_QUERY)) begin
                        frame_stream_cap_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd3) && (parser_payload_byte == ASCII_CFG_OP)) begin
                        frame_cfg_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd4) && (parser_payload_byte == STREAM_START_OP)) begin
                        frame_stream_start_q <= 1'b1;
                    end else if ((parser_payload_len == 8'h81) &&
                                 (stream_session_active_q ||
                                  stream_session_fault_q ||
                                  (parser_payload_byte != MODE_AES))) begin
                        frame_stream_chunk_q <= 1'b1;
                        frame_stream_seq_q   <= parser_payload_byte;
                        if (!stream_session_active_q) begin
                            frame_stream_error_q      <= 1'b1;
                            frame_stream_error_code_q <= STREAM_ERR_STATE;
                        end else if (stream_expected_valid_q &&
                                     (parser_payload_byte != stream_expected_seq_q)) begin
                            frame_stream_error_q      <= 1'b1;
                            frame_stream_error_code_q <= STREAM_ERR_SEQ;
                        end else begin
                            acl_frame_algo_q   <= stream_session_algo_q;
                            acl_frame_active_q <= 1'b1;
                            acl_frame_stream_q <= 1'b1;
                        end
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
                        acl_frame_stream_q <= 1'b0;
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
                end else if (frame_stream_start_q) begin
                    if (parser_payload_count == 8'd2) begin
                        if (parser_payload_byte == MODE_AES) begin
                            frame_stream_start_alg_q <= ALG_AES;
                        end else if (parser_payload_byte == MODE_SM4) begin
                            frame_stream_start_alg_q <= ALG_SM4;
                        end else begin
                            frame_stream_error_q      <= 1'b1;
                            frame_stream_error_code_q <= STREAM_ERR_FORMAT;
                        end
                    end else if (parser_payload_count == 8'd3) begin
                        frame_stream_start_total_q[15:8] <= parser_payload_byte;
                    end else if (parser_payload_count == 8'd4) begin
                        frame_stream_start_total_q[7:0] <= parser_payload_byte;
                    end
                end else if (frame_stream_chunk_q) begin
                    if (!frame_stream_error_q) begin
                        if (!frame_key_valid_q) begin
                            frame_key_q       <= parser_payload_byte;
                            frame_key_valid_q <= 1'b1;
                        end
                        acl_in_valid_q <= 1'b1;
                        acl_in_data_q  <= parser_payload_byte;
                        acl_in_last_q  <= parser_frame_done;
                    end
                end else if (!frame_query_q &&
                             !frame_rule_query_q &&
                             !frame_keymap_query_q &&
                             !frame_pmu_query_q &&
                             !frame_pmu_clear_q &&
                             !frame_stream_cap_q &&
                             !frame_proto_error_q) begin
                    if (!frame_key_valid_q) begin
                        frame_key_q       <= parser_payload_byte;
                        frame_key_valid_q <= 1'b1;
                    end
                    if (!acl_frame_active_q) begin
                        acl_frame_algo_q   <= frame_algo_sel_q;
                        acl_frame_active_q <= 1'b1;
                        acl_frame_stream_q <= 1'b0;
                    end
                    acl_in_valid_q <= 1'b1;
                    acl_in_data_q  <= parser_payload_byte;
                    acl_in_last_q  <= parser_frame_done;
                end
            end

            if (parser_frame_done) begin
                if (!frame_pmu_query_q && !frame_pmu_clear_q) begin
                    pmu_armed_q <= 1'b1;
                end

                if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                      (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_PMU_QRY))) ||
                    frame_pmu_query_q) begin
                    pmu_snap_global_cycles_q             <= pmu_global_cycles_q;
                    pmu_snap_crypto_active_cycles_q      <= pmu_crypto_active_cycles_q;
                    pmu_snap_uart_tx_stall_cycles_q      <= pmu_uart_tx_stall_cycles_q;
                    pmu_snap_stream_credit_block_cycles_q <= pmu_stream_credit_block_cycles_q;
                    pmu_snap_acl_block_events_q          <= pmu_acl_block_events_q;
                    pmu_tx_kind_q                        <= PMU_TX_SNAPSHOT;
                    pmu_tx_idx_q                         <= 6'd0;
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                               (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_PMU_CLR))) ||
                              frame_pmu_clear_q) begin
                    pmu_armed_q                         <= 1'b0;
                    pmu_global_cycles_q                 <= 64'd0;
                    pmu_crypto_active_cycles_q          <= 64'd0;
                    pmu_uart_tx_stall_cycles_q          <= 64'd0;
                    pmu_stream_credit_block_cycles_q    <= 64'd0;
                    pmu_acl_block_events_q              <= 64'd0;
                    pmu_snap_global_cycles_q            <= 64'd0;
                    pmu_snap_crypto_active_cycles_q     <= 64'd0;
                    pmu_snap_uart_tx_stall_cycles_q     <= 64'd0;
                    pmu_snap_stream_credit_block_cycles_q <= 64'd0;
                    pmu_snap_acl_block_events_q         <= 64'd0;
                    pmu_tx_kind_q                       <= PMU_TX_CLEAR_ACK;
                    pmu_tx_idx_q                        <= 6'd0;
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                      (parser_payload_len == 8'd1) && (parser_payload_byte == STREAM_CAP_QUERY))) ||
                    frame_stream_cap_q) begin
                    stream_tx_kind_q <= STREAM_TX_CAP;
                    stream_tx_idx_q  <= 3'd0;
                end else if (frame_stream_start_q) begin
                    if (frame_stream_error_q) begin
                        stream_tx_kind_q    <= STREAM_TX_ERROR;
                        stream_tx_idx_q     <= 3'd0;
                        stream_tx_code_q    <= frame_stream_error_code_q;
                        stat_error_frames_q <= stat_error_frames_q + 8'd1;
                    end else begin
                        stream_session_active_q <= 1'b1;
                        stream_session_fault_q  <= 1'b0;
                        stream_session_algo_q   <= frame_stream_start_alg_q;
                        stream_expected_valid_q <= 1'b0;
                        stream_expected_seq_q   <= 8'd0;
                        stream_session_total_q  <= frame_stream_start_total_q;
                        stream_seq_wr_ptr_q     <= 3'd0;
                        stream_seq_rd_ptr_q     <= 3'd0;
                        stream_seq_count_q      <= 4'd0;
                        stream_payload_bytes_left_q <= 8'd0;
                        stream_tx_kind_q        <= STREAM_TX_START_ACK;
                        stream_tx_idx_q         <= 3'd0;
                    end
                end else if (frame_stream_chunk_q) begin
                    if (frame_stream_error_q) begin
                        stream_tx_kind_q    <= STREAM_TX_ERROR;
                        stream_tx_idx_q     <= 3'd0;
                        stream_tx_code_q    <= frame_stream_error_code_q;
                        stat_error_frames_q <= stat_error_frames_q + 8'd1;
                        if (stream_session_active_q || stream_session_fault_q) begin
                            stream_session_active_q <= 1'b0;
                            stream_session_fault_q  <= 1'b1;
                            stream_expected_valid_q <= 1'b0;
                        end
                    end else if (frame_stream_block_q) begin
                        stat_total_frames_q     <= stat_total_frames_q + 8'd1;
                        stat_acl_blocks_q       <= stat_acl_blocks_q + 8'd1;
                        pmu_acl_block_events_q  <= pmu_acl_block_events_q + 64'd1;
                        stream_session_active_q <= 1'b0;
                        stream_session_fault_q  <= 1'b1;
                        stream_expected_valid_q <= 1'b0;
                        stream_tx_kind_q        <= STREAM_TX_BLOCK;
                        stream_tx_idx_q         <= 3'd0;
                        stream_tx_seq_q         <= frame_stream_seq_q;
                        stream_tx_slot_q        <= frame_stream_block_slot_q;
                    end else if (frame_key_valid_q) begin
                        stat_total_frames_q     <= stat_total_frames_q + 8'd1;
                        stream_expected_valid_q <= 1'b1;
                        stream_expected_seq_q   <= frame_stream_seq_q + 8'd1;
                        if (stream_seq_count_q == STREAM_WINDOW[3:0]) begin
                            stream_tx_kind_q       <= STREAM_TX_ERROR;
                            stream_tx_idx_q        <= 3'd0;
                            stream_tx_code_q       <= STREAM_ERR_WINDOW;
                            stat_error_frames_q    <= stat_error_frames_q + 8'd1;
                            stream_session_active_q <= 1'b0;
                            stream_session_fault_q  <= 1'b1;
                            stream_expected_valid_q <= 1'b0;
                        end else begin
                            stream_seq_fifo_q[stream_seq_wr_ptr_q] <= frame_stream_seq_q;
                            stream_seq_wr_ptr_q <= stream_seq_wr_ptr_q + 3'd1;
                            stream_seq_count_q  <= stream_seq_count_q + 4'd1;
                        end
                        if (stream_session_algo_q == ALG_AES) begin
                            stat_aes_frames_q <= stat_aes_frames_q + 8'd1;
                        end else begin
                            stat_sm4_frames_q <= stat_sm4_frames_q + 8'd1;
                        end
                    end
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
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
                        acl_cfg_index_q       <= (parser_payload_valid && (parser_payload_count == 8'd2)) ? parser_payload_byte[2:0] : frame_cfg_index_q[2:0];
                        acl_cfg_key_q         <= (parser_payload_valid && (parser_payload_count == 8'd3)) ? parser_payload_byte : frame_cfg_key_q;
                        pending_cfg_ack_idx_q <= (parser_payload_valid && (parser_payload_count == 8'd2)) ? parser_payload_byte[2:0] : frame_cfg_index_q[2:0];
                        pending_cfg_ack_key_q <= (parser_payload_valid && (parser_payload_count == 8'd3)) ? parser_payload_byte : frame_cfg_key_q;
                    end
                end else if (frame_proto_error_q) begin
                    pending_error_q     <= 1'b1;
                    stat_error_frames_q <= stat_error_frames_q + 8'd1;
                end else if (frame_key_valid_q) begin
                    stat_total_frames_q <= stat_total_frames_q + 8'd1;
                    if (acl_block_seen_q) begin
                        stat_acl_blocks_q <= stat_acl_blocks_q + 8'd1;
                        pmu_acl_block_events_q <= pmu_acl_block_events_q + 64'd1;
                    end else if (frame_algo_sel_q == ALG_AES) begin
                        stat_aes_frames_q <= stat_aes_frames_q + 8'd1;
                    end else begin
                        stat_sm4_frames_q <= stat_sm4_frames_q + 8'd1;
                    end
                end

                frame_key_q               <= 8'd0;
                frame_key_valid_q         <= 1'b0;
                frame_proto_error_q       <= 1'b0;
                frame_query_q             <= 1'b0;
                frame_rule_query_q        <= 1'b0;
                frame_keymap_query_q      <= 1'b0;
                frame_pmu_query_q         <= 1'b0;
                frame_pmu_clear_q         <= 1'b0;
                frame_cfg_q               <= 1'b0;
                frame_cfg_index_q         <= 8'd0;
                frame_cfg_key_q           <= 8'd0;
                frame_cfg_key_seen_q      <= 1'b0;
                frame_algo_sel_q          <= ALG_SM4;
                frame_stream_cap_q        <= 1'b0;
                frame_stream_start_q      <= 1'b0;
                frame_stream_chunk_q      <= 1'b0;
                frame_stream_error_q      <= 1'b0;
                frame_stream_error_code_q <= 8'd0;
                frame_stream_start_alg_q  <= ALG_SM4;
                frame_stream_start_total_q <= 16'd0;
                frame_stream_seq_q        <= 8'd0;
                frame_stream_block_q      <= 1'b0;
                frame_stream_block_slot_q <= 3'd0;
                acl_block_seen_q          <= 1'b0;
            end

            if (acl_blocked) begin
                acl_block_seen_q <= 1'b1;
                if (acl_frame_stream_q) begin
                    frame_stream_block_q      <= 1'b1;
                    frame_stream_block_slot_q <= acl_block_slot_valid ? acl_block_slot : 3'd0;
                    acl_stream_drop_q         <= 1'b1;
                    stream_session_active_q   <= 1'b0;
                    stream_expected_valid_q   <= 1'b0;
                end
            end

            if (acl_valid && acl_last) begin
                acl_frame_active_q <= 1'b0;
                acl_frame_algo_q   <= ALG_SM4;
                acl_frame_stream_q <= 1'b0;
                acl_stream_drop_q  <= 1'b0;
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
                bridge_in_last_q <= (pending_stats_idx_q == 3'd6);
                bridge_in_algo_q <= ALG_SM4;
                if (pending_stats_idx_q == 3'd6) begin
                    pending_stats_q     <= 1'b0;
                    pending_stats_idx_q <= 3'd0;
                end else begin
                    pending_stats_idx_q <= pending_stats_idx_q + 3'd1;
                end
            end else if (acl_valid && !(acl_stream_drop_q || (acl_blocked && acl_frame_stream_q))) begin
                bridge_in_valid_q <= 1'b1;
                bridge_in_data_q  <= acl_data;
                bridge_in_last_q  <= acl_last;
                bridge_in_algo_q  <= acl_frame_algo_q;
            end
        end
    end

endmodule
