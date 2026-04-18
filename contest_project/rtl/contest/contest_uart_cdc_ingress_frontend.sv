`timescale 1ns/1ps

import contest_cdc_ingress_pkg::*;

module contest_uart_cdc_ingress_frontend #(
    parameter integer INGRESS_CLK_HZ = 125_000_000,
    parameter integer BAUD           = 2_000_000
) (
    input  wire                 i_ingress_clk,
    input  wire                 i_root_rst_n_async,
    input  wire                 i_ingress_locked,
    input  wire                 i_link_flush_req,
    input  wire                 i_uart_rx,
    input  wire                 i_stream_algo,

    output wire                 o_payload_tvalid,
    input  wire                 i_payload_tready,
    output wire [7:0]           o_payload_tdata,
    output wire                 o_payload_tlast,
    output wire [0:0]           o_payload_tuser,

    output wire                 o_meta_valid,
    input  wire                 i_meta_ready,
    output wire [CDC_META_W-1:0] o_meta_payload,
    output wire                 o_wake_hint_pulse
);

    localparam [7:0] ASCII_CFG_ACK = 8'h43;
    localparam [7:0] ASCII_KEYMAP  = 8'h4B;
    localparam [7:0] ASCII_PMU_CLR = 8'h4A;
    localparam [7:0] ASCII_PMU_QRY = 8'h50;
    localparam [7:0] ASCII_QUERY   = 8'h3F;
    localparam [7:0] ASCII_RULE    = 8'h48;
    localparam [7:0] ASCII_TRACE   = 8'h54;
    localparam [7:0] ASCII_BENCH   = 8'h62;
    localparam [7:0] MODE_AES      = 8'h41;
    localparam [7:0] MODE_SM4      = 8'h53;
    localparam       ALG_SM4       = 1'b0;
    localparam       ALG_AES       = 1'b1;

    localparam [7:0] STREAM_CAP_QUERY = 8'h57;
    localparam [7:0] STREAM_START_OP  = 8'h4D;
    localparam integer STREAM_CHUNK_BYTES = 128;

    localparam [2:0] FRAME_IDLE     = 3'd0;
    localparam [2:0] FRAME_NORMAL   = 3'd1;
    localparam [2:0] FRAME_CFG      = 3'd2;
    localparam [2:0] FRAME_STREAM_START = 3'd3;
    localparam [2:0] FRAME_BENCH    = 3'd4;
    localparam [2:0] FRAME_TRACE_PAGE = 3'd5;
    localparam [2:0] FRAME_STREAM_CHUNK = 3'd6;

    function automatic [CDC_META_KIND_W-1:0] classify_first_byte_kind;
        input [7:0] payload_len;
        input [7:0] payload_byte;
        begin
            if ((payload_len == 8'd1) && (payload_byte == ASCII_QUERY)) begin
                classify_first_byte_kind = CDC_META_KIND_QUERY_STATS;
            end else if ((payload_len == 8'd1) && (payload_byte == ASCII_RULE)) begin
                classify_first_byte_kind = CDC_META_KIND_QUERY_HITS;
            end else if ((payload_len == 8'd1) && (payload_byte == ASCII_KEYMAP)) begin
                classify_first_byte_kind = CDC_META_KIND_QUERY_KEYMAP;
            end else if ((payload_len == 8'd1) && (payload_byte == ASCII_TRACE)) begin
                classify_first_byte_kind = CDC_META_KIND_TRACE_META;
            end else if ((payload_len == 8'd2) && (payload_byte == ASCII_TRACE)) begin
                classify_first_byte_kind = CDC_META_KIND_TRACE_PAGE;
            end else if ((payload_len == 8'd1) && (payload_byte == ASCII_PMU_QRY)) begin
                classify_first_byte_kind = CDC_META_KIND_PMU_QUERY;
            end else if ((payload_len == 8'd1) && (payload_byte == ASCII_PMU_CLR)) begin
                classify_first_byte_kind = CDC_META_KIND_PMU_CLEAR;
            end else if ((payload_len == 8'd1) && (payload_byte == ASCII_BENCH)) begin
                classify_first_byte_kind = CDC_META_KIND_BENCH_QUERY;
            end else if ((payload_len == 8'd2) && (payload_byte == ASCII_BENCH)) begin
                classify_first_byte_kind = CDC_META_KIND_BENCH_START;
            end else if ((payload_len == 8'd3) && (payload_byte == ASCII_BENCH)) begin
                classify_first_byte_kind = CDC_META_KIND_BENCH_FORCE;
            end else if ((payload_len == 8'd1) && (payload_byte == STREAM_CAP_QUERY)) begin
                classify_first_byte_kind = CDC_META_KIND_STREAM_CAP;
            end else if ((payload_len == 8'd18) && (payload_byte == ASCII_CFG_ACK)) begin
                classify_first_byte_kind = CDC_META_KIND_ACL_CFG;
            end else if ((payload_len == 8'd4) && (payload_byte == STREAM_START_OP)) begin
                classify_first_byte_kind = CDC_META_KIND_STREAM_START;
            end else if (payload_len == 8'h81) begin
                classify_first_byte_kind = CDC_META_KIND_STREAM_CHUNK;
            end else begin
                classify_first_byte_kind = CDC_META_KIND_NORMAL_PAYLOAD;
            end
        end
    endfunction

    wire ingress_rst_n_async;
    wire ingress_rst_n_sync;
    wire rx_valid;
    wire [7:0] rx_data;
    wire rx_frame_error;
    wire parser_payload_valid;
    wire [7:0] parser_payload_byte;
    wire parser_frame_done;
    wire parser_error;
    wire [7:0] parser_payload_len;
    wire [7:0] parser_payload_count;
    wire [127:0] frame_cfg_key_commit_w;
    wire [CDC_META_KIND_W-1:0] meta_kind_commit_w;
    wire meta_slot_available_w;
    wire [7:0] meta_payload_len_commit_w;
    wire meta_algo_commit_w;
    wire [3:0] frame_trace_page_idx_commit_w;
    wire frame_stream_start_alg_commit_w;
    wire [15:0] frame_stream_start_total_commit_w;
    wire frame_bench_force_seen_commit_w;
    wire frame_bench_algo_valid_commit_w;
    wire frame_bench_algo_commit_w;

    reg payload_valid_q;
    reg [7:0] payload_data_q;
    reg payload_last_q;
    reg [0:0] payload_user_q;

    reg meta_valid_q;
    reg wake_hint_pulse_q;
    cdc_meta_t meta_q;

    reg [2:0] frame_state_q;
    reg frame_proto_error_q;
    reg frame_algo_sel_q;
    reg [2:0] frame_cfg_index_q;
    reg [127:0] frame_cfg_key_q;
    reg [3:0] frame_trace_page_idx_q;
    reg frame_stream_start_alg_q;
    reg [15:0] frame_stream_start_total_q;
    reg [7:0] frame_stream_seq_q;
    reg frame_bench_force_seen_q;
    reg frame_bench_algo_valid_q;
    reg frame_bench_algo_q;
    reg [7:0] frame_normal_payload_len_q;
    reg frame_normal_meta_early_q;

    assign ingress_rst_n_async = i_root_rst_n_async && i_ingress_locked && !i_link_flush_req;
    assign frame_cfg_key_commit_w = ((frame_state_q == FRAME_CFG) && parser_payload_valid && (parser_payload_count == 8'd18)) ? {frame_cfg_key_q[119:0], parser_payload_byte} : frame_cfg_key_q;
    assign meta_kind_commit_w = (parser_payload_valid && (parser_payload_count == 8'd1)) ? classify_first_byte_kind(parser_payload_len, parser_payload_byte) : meta_q.kind;
    assign meta_payload_len_commit_w = (parser_payload_valid && (parser_payload_count == 8'd1) && (classify_first_byte_kind(parser_payload_len, parser_payload_byte) == CDC_META_KIND_NORMAL_PAYLOAD)) ? (((parser_payload_len >= 8'd17) && (parser_payload_len[3:0] == 4'h1)) ? (parser_payload_len - 8'd1) : parser_payload_len) : frame_normal_payload_len_q;
    assign meta_algo_commit_w = (parser_payload_valid && (parser_payload_count == 8'd1) && (classify_first_byte_kind(parser_payload_len, parser_payload_byte) == CDC_META_KIND_NORMAL_PAYLOAD) && !((parser_payload_len >= 8'd17) && (parser_payload_len[3:0] == 4'h1))) ? ALG_SM4 : frame_algo_sel_q;
    assign frame_trace_page_idx_commit_w = ((frame_state_q == FRAME_TRACE_PAGE) && parser_payload_valid && (parser_payload_count == 8'd2)) ? parser_payload_byte[3:0] : frame_trace_page_idx_q;
    assign frame_stream_start_alg_commit_w = ((frame_state_q == FRAME_STREAM_START) && parser_payload_valid && (parser_payload_count == 8'd2) && (parser_payload_byte == MODE_AES)) ? ALG_AES : (((frame_state_q == FRAME_STREAM_START) && parser_payload_valid && (parser_payload_count == 8'd2) && (parser_payload_byte == MODE_SM4)) ? ALG_SM4 : frame_stream_start_alg_q);
    assign frame_stream_start_total_commit_w = ((frame_state_q == FRAME_STREAM_START) && parser_payload_valid && (parser_payload_count == 8'd3)) ? {parser_payload_byte, frame_stream_start_total_q[7:0]} : (((frame_state_q == FRAME_STREAM_START) && parser_payload_valid && (parser_payload_count == 8'd4)) ? {frame_stream_start_total_q[15:8], parser_payload_byte} : frame_stream_start_total_q);
    assign frame_bench_force_seen_commit_w = ((frame_state_q == FRAME_BENCH) && parser_payload_valid && (meta_q.kind == CDC_META_KIND_BENCH_FORCE) && (parser_payload_count == 8'd2) && (parser_payload_byte == 8'hFF)) ? 1'b1 : frame_bench_force_seen_q;
    assign frame_bench_algo_valid_commit_w = ((frame_state_q == FRAME_BENCH) && parser_payload_valid && (((meta_q.kind == CDC_META_KIND_BENCH_START) && (parser_payload_count == 8'd2)) || ((meta_q.kind == CDC_META_KIND_BENCH_FORCE) && (parser_payload_count == 8'd3))) && ((parser_payload_byte == MODE_AES) || (parser_payload_byte == MODE_SM4))) ? 1'b1 : frame_bench_algo_valid_q;
    assign frame_bench_algo_commit_w = ((frame_state_q == FRAME_BENCH) && parser_payload_valid && (((meta_q.kind == CDC_META_KIND_BENCH_START) && (parser_payload_count == 8'd2)) || ((meta_q.kind == CDC_META_KIND_BENCH_FORCE) && (parser_payload_count == 8'd3))) && (parser_payload_byte == MODE_AES)) ? ALG_AES : (((frame_state_q == FRAME_BENCH) && parser_payload_valid && (((meta_q.kind == CDC_META_KIND_BENCH_START) && (parser_payload_count == 8'd2)) || ((meta_q.kind == CDC_META_KIND_BENCH_FORCE) && (parser_payload_count == 8'd3))) && (parser_payload_byte == MODE_SM4)) ? ALG_SM4 : frame_bench_algo_q);

    assign meta_slot_available_w = !meta_valid_q || i_meta_ready;

    assign o_payload_tvalid = payload_valid_q;
    assign o_payload_tdata  = payload_data_q;
    assign o_payload_tlast  = payload_last_q;
    assign o_payload_tuser  = payload_user_q;
    assign o_meta_valid      = meta_valid_q;
    assign o_meta_payload    = meta_q;
    assign o_wake_hint_pulse = wake_hint_pulse_q;

    contest_reset_sync u_ingress_reset_sync (
        .i_clk        (i_ingress_clk),
        .i_rst_n_async(ingress_rst_n_async),
        .o_rst_n_sync (ingress_rst_n_sync)
    );

    contest_uart_rx #(
        .CLK_HZ(INGRESS_CLK_HZ),
        .BAUD  (BAUD)
    ) u_rx (
        .i_clk         (i_ingress_clk),
        .i_rst_n       (ingress_rst_n_async),
        .i_uart_rx     (i_uart_rx),
        .o_valid       (rx_valid),
        .o_data        (rx_data),
        .o_frame_error (rx_frame_error)
    );

    contest_parser_core #(
        .SOF_BYTE              (8'h55),
        .MAX_PAYLOAD_BYTES     (255),
        .INTERBYTE_TIMEOUT_CLKS((INGRESS_CLK_HZ / BAUD) * 20)
    ) u_parser (
        .i_clk          (i_ingress_clk),
        .i_rst_n        (ingress_rst_n_async),
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

    always @(posedge i_ingress_clk or negedge ingress_rst_n_async) begin
        if (!ingress_rst_n_async) begin
            payload_valid_q            <= 1'b0;
            payload_data_q             <= 8'd0;
            payload_last_q             <= 1'b0;
            payload_user_q             <= 1'b0;
            meta_valid_q               <= 1'b0;
            wake_hint_pulse_q         <= 1'b0;
            meta_q                     <= '0;
            frame_state_q              <= FRAME_IDLE;
            frame_proto_error_q        <= 1'b0;
            frame_algo_sel_q           <= ALG_SM4;
            frame_cfg_index_q          <= 3'd0;
            frame_cfg_key_q            <= 128'd0;
            frame_trace_page_idx_q     <= 4'd0;
            frame_stream_start_alg_q   <= ALG_SM4;
            frame_stream_start_total_q <= 16'd0;
            frame_stream_seq_q         <= 8'd0;
            frame_bench_force_seen_q   <= 1'b0;
            frame_bench_algo_valid_q   <= 1'b0;
            frame_bench_algo_q         <= ALG_SM4;
            frame_normal_payload_len_q <= 8'd0;
            frame_normal_meta_early_q  <= 1'b0;
        end else if (!ingress_rst_n_sync) begin
            payload_valid_q            <= 1'b0;
            payload_data_q             <= 8'd0;
            payload_last_q             <= 1'b0;
            payload_user_q             <= 1'b0;
            meta_valid_q               <= 1'b0;
            wake_hint_pulse_q         <= 1'b0;
            meta_q                     <= '0;
            frame_state_q              <= FRAME_IDLE;
            frame_proto_error_q        <= 1'b0;
            frame_algo_sel_q           <= ALG_SM4;
            frame_cfg_index_q          <= 3'd0;
            frame_cfg_key_q            <= 128'd0;
            frame_trace_page_idx_q     <= 4'd0;
            frame_stream_start_alg_q   <= ALG_SM4;
            frame_stream_start_total_q <= 16'd0;
            frame_stream_seq_q         <= 8'd0;
            frame_bench_force_seen_q   <= 1'b0;
            frame_bench_algo_valid_q   <= 1'b0;
            frame_bench_algo_q         <= ALG_SM4;
            frame_normal_payload_len_q <= 8'd0;
            frame_normal_meta_early_q  <= 1'b0;
        end else begin
            wake_hint_pulse_q <= 1'b0;
            if (payload_valid_q && i_payload_tready) begin
                payload_valid_q <= 1'b0;
                payload_last_q  <= 1'b0;
            end
            if (meta_valid_q && i_meta_ready) begin
                meta_valid_q               <= 1'b0;
            wake_hint_pulse_q         <= 1'b0;
            meta_q                     <= '0;
            end

            if ((parser_error || rx_frame_error) && meta_slot_available_w) begin
                meta_valid_q         <= 1'b1;
                meta_q.kind          <= CDC_META_KIND_ABORT_FLUSH;
                meta_q.error_code    <= 8'h01;
                frame_state_q        <= FRAME_IDLE;
                frame_proto_error_q  <= 1'b0;
            end

            if (parser_payload_valid) begin
                if (parser_payload_count == 8'd1) begin
                    frame_state_q              <= FRAME_IDLE;
                    frame_proto_error_q        <= 1'b0;
                    frame_algo_sel_q           <= ALG_SM4;
                    frame_cfg_index_q          <= 3'd0;
                    frame_cfg_key_q            <= 128'd0;
                    frame_trace_page_idx_q     <= 4'd0;
                    frame_stream_start_alg_q   <= ALG_SM4;
                    frame_stream_start_total_q <= 16'd0;
                    frame_stream_seq_q         <= 8'd0;
                    frame_bench_force_seen_q   <= 1'b0;
                    frame_bench_algo_valid_q   <= 1'b0;
                    frame_bench_algo_q         <= ALG_SM4;
                    frame_normal_payload_len_q <= parser_payload_len;
                    frame_normal_meta_early_q  <= 1'b0;

                    if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_QUERY)) begin
                        meta_q.kind <= CDC_META_KIND_QUERY_STATS;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_RULE)) begin
                        meta_q.kind <= CDC_META_KIND_QUERY_HITS;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_KEYMAP)) begin
                        meta_q.kind <= CDC_META_KIND_QUERY_KEYMAP;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_TRACE)) begin
                        meta_q.kind <= CDC_META_KIND_TRACE_META;
                    end else if ((parser_payload_len == 8'd2) && (parser_payload_byte == ASCII_TRACE)) begin
                        frame_state_q <= FRAME_TRACE_PAGE;
                        meta_q.kind   <= CDC_META_KIND_TRACE_PAGE;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_PMU_QRY)) begin
                        meta_q.kind <= CDC_META_KIND_PMU_QUERY;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_PMU_CLR)) begin
                        meta_q.kind <= CDC_META_KIND_PMU_CLEAR;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_BENCH)) begin
                        meta_q.kind <= CDC_META_KIND_BENCH_QUERY;
                    end else if ((parser_payload_len == 8'd2) && (parser_payload_byte == ASCII_BENCH)) begin
                        frame_state_q <= FRAME_BENCH;
                        meta_q.kind   <= CDC_META_KIND_BENCH_START;
                    end else if ((parser_payload_len == 8'd3) && (parser_payload_byte == ASCII_BENCH)) begin
                        frame_state_q <= FRAME_BENCH;
                        meta_q.kind   <= CDC_META_KIND_BENCH_FORCE;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == STREAM_CAP_QUERY)) begin
                        meta_q.kind <= CDC_META_KIND_STREAM_CAP;
                    end else if ((parser_payload_len == 8'd18) && (parser_payload_byte == ASCII_CFG_ACK)) begin
                        frame_state_q     <= FRAME_CFG;
                        meta_q.kind       <= CDC_META_KIND_ACL_CFG;
                        wake_hint_pulse_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd4) && (parser_payload_byte == STREAM_START_OP)) begin
                        frame_state_q <= FRAME_STREAM_START;
                        meta_q.kind   <= CDC_META_KIND_STREAM_START;
                    end else if (parser_payload_len == 8'h81) begin
                        frame_state_q      <= FRAME_STREAM_CHUNK;
                        frame_stream_seq_q <= parser_payload_byte;
                        meta_q.kind        <= CDC_META_KIND_STREAM_CHUNK;
                        meta_q.seq         <= parser_payload_byte;
                        meta_q.payload_len <= STREAM_CHUNK_BYTES[7:0];
                    end else if ((parser_payload_len >= 8'd17) && (parser_payload_len[3:0] == 4'h1)) begin
                        frame_state_q      <= FRAME_NORMAL;
                        if (parser_payload_byte == MODE_AES) begin
                            frame_algo_sel_q <= ALG_AES;
                        end else if (parser_payload_byte == MODE_SM4) begin
                            frame_algo_sel_q <= ALG_SM4;
                        end else begin
                            frame_proto_error_q <= 1'b1;
                        end
                        frame_normal_payload_len_q <= parser_payload_len - 8'd1;
                        meta_q.kind                <= CDC_META_KIND_NORMAL_PAYLOAD;
                        meta_q.payload_len         <= parser_payload_len - 8'd1;
                    end else begin
                        frame_state_q             <= FRAME_NORMAL;
                        frame_algo_sel_q          <= ALG_SM4;
                        frame_normal_meta_early_q <= 1'b1;
                        meta_q.kind               <= CDC_META_KIND_NORMAL_PAYLOAD;
                        meta_q.algo               <= ALG_SM4;
                        meta_q.payload_len        <= parser_payload_len;
                        if (meta_slot_available_w) begin
                            meta_valid_q <= 1'b1;
                        end
                        if (!payload_valid_q) begin
                            payload_valid_q <= 1'b1;
                            payload_data_q  <= parser_payload_byte;
                            payload_last_q  <= (parser_payload_len == 8'd1);
                            payload_user_q  <= ALG_SM4;
                        end
                    end
                end else begin
                    case (frame_state_q)
                        FRAME_CFG: begin
                            if (parser_payload_count == 8'd2) begin
                                frame_cfg_index_q <= parser_payload_byte[2:0];
                            end else if ((parser_payload_count >= 8'd3) && (parser_payload_count <= 8'd18)) begin
                                frame_cfg_key_q <= {frame_cfg_key_q[119:0], parser_payload_byte};
                            end
                        end
                        FRAME_TRACE_PAGE: begin
                            if (parser_payload_count == 8'd2) begin
                                frame_trace_page_idx_q <= parser_payload_byte[3:0];
                            end
                        end
                        FRAME_STREAM_START: begin
                            if (parser_payload_count == 8'd2) begin
                                if (parser_payload_byte == MODE_AES) begin
                                    frame_stream_start_alg_q <= ALG_AES;
                                end else if (parser_payload_byte == MODE_SM4) begin
                                    frame_stream_start_alg_q <= ALG_SM4;
                                end else begin
                                    frame_proto_error_q <= 1'b1;
                                end
                            end else if (parser_payload_count == 8'd3) begin
                                frame_stream_start_total_q[15:8] <= parser_payload_byte;
                            end else if (parser_payload_count == 8'd4) begin
                                frame_stream_start_total_q[7:0] <= parser_payload_byte;
                            end
                        end
                        FRAME_BENCH: begin
                            if (meta_q.kind == CDC_META_KIND_BENCH_FORCE) begin
                                if (parser_payload_count == 8'd2) begin
                                    if (parser_payload_byte == 8'hFF) begin
                                        frame_bench_force_seen_q <= 1'b1;
                                    end else begin
                                        frame_proto_error_q <= 1'b1;
                                    end
                                end else if (parser_payload_count == 8'd3) begin
                                    if (parser_payload_byte == MODE_AES) begin
                                        frame_bench_algo_q       <= ALG_AES;
                                        frame_bench_algo_valid_q <= 1'b1;
                                    end else if (parser_payload_byte == MODE_SM4) begin
                                        frame_bench_algo_q       <= ALG_SM4;
                                        frame_bench_algo_valid_q <= 1'b1;
                                    end else begin
                                        frame_proto_error_q <= 1'b1;
                                    end
                                end
                            end else if (parser_payload_count == 8'd2) begin
                                if (parser_payload_byte == MODE_AES) begin
                                    frame_bench_algo_q       <= ALG_AES;
                                    frame_bench_algo_valid_q <= 1'b1;
                                end else if (parser_payload_byte == MODE_SM4) begin
                                    frame_bench_algo_q       <= ALG_SM4;
                                    frame_bench_algo_valid_q <= 1'b1;
                                end else begin
                                    frame_proto_error_q <= 1'b1;
                                end
                            end
                        end
                        FRAME_STREAM_CHUNK: begin
                            if (!payload_valid_q) begin
                                payload_valid_q <= 1'b1;
                                payload_data_q  <= parser_payload_byte;
                                payload_last_q  <= (parser_payload_count == 8'd129);
                                payload_user_q  <= i_stream_algo;
                            end
                        end
                        FRAME_NORMAL: begin
                            if ((parser_payload_len >= 8'd17) && (parser_payload_len[3:0] == 4'h1) && (parser_payload_count == 8'd2)) begin
                                if (!payload_valid_q && !frame_proto_error_q) begin
                                    payload_valid_q <= 1'b1;
                                    payload_data_q  <= parser_payload_byte;
                                    payload_last_q  <= ((parser_payload_len - 8'd1) == 8'd1);
                                    payload_user_q  <= frame_algo_sel_q;
                                end
                            end else if (!payload_valid_q && !frame_proto_error_q) begin
                                payload_valid_q <= 1'b1;
                                payload_data_q  <= parser_payload_byte;
                                payload_last_q  <= (parser_payload_count == parser_payload_len);
                                payload_user_q  <= frame_algo_sel_q;
                            end
                        end
                        default: begin
                        end
                    endcase
                end
            end

            if (parser_frame_done && meta_slot_available_w) begin
                if (frame_proto_error_q) begin
                    meta_valid_q      <= 1'b1;
                    meta_q.kind       <= CDC_META_KIND_PROTO_ERROR;
                    meta_q.error_code <= 8'h01;
                end else begin
                    case (meta_kind_commit_w)
                        CDC_META_KIND_NORMAL_PAYLOAD: begin
                            if (!frame_normal_meta_early_q) begin
                                meta_valid_q       <= 1'b1;
                                meta_q.algo        <= frame_algo_sel_q;
                                meta_q.payload_len <= frame_normal_payload_len_q;
                            end
                        end
                        CDC_META_KIND_STREAM_START: begin
                            meta_valid_q      <= 1'b1;
                            meta_q.algo       <= frame_stream_start_alg_commit_w;
                            meta_q.total      <= frame_stream_start_total_commit_w;
                        end
                        CDC_META_KIND_STREAM_CHUNK: begin
                            meta_valid_q      <= 1'b1;
                            meta_q.algo       <= i_stream_algo;
                            meta_q.seq        <= frame_stream_seq_q;
                            meta_q.payload_len <= STREAM_CHUNK_BYTES[7:0];
                        end
                        CDC_META_KIND_ACL_CFG: begin
                            meta_valid_q      <= 1'b1;
                            meta_q.cfg_index  <= frame_cfg_index_q;
                            meta_q.cfg_key    <= frame_cfg_key_commit_w;
                        end
                        CDC_META_KIND_TRACE_PAGE: begin
                            meta_valid_q          <= 1'b1;
                            meta_q.trace_page_idx <= frame_trace_page_idx_commit_w;
                        end
                        CDC_META_KIND_BENCH_START,
                        CDC_META_KIND_BENCH_FORCE: begin
                            meta_valid_q            <= 1'b1;
                            meta_q.algo             <= frame_bench_algo_commit_w;
                            meta_q.bench_algo_valid <= frame_bench_algo_valid_commit_w;
                            meta_q.bench_force      <= (meta_kind_commit_w == CDC_META_KIND_BENCH_FORCE) && frame_bench_force_seen_commit_w;
                        end
                        CDC_META_KIND_STREAM_CAP,
                        CDC_META_KIND_PMU_QUERY,
                        CDC_META_KIND_PMU_CLEAR,
                        CDC_META_KIND_BENCH_QUERY,
                        CDC_META_KIND_QUERY_STATS,
                        CDC_META_KIND_QUERY_HITS,
                        CDC_META_KIND_QUERY_KEYMAP,
                        CDC_META_KIND_TRACE_META: begin
                            meta_valid_q <= 1'b1;
                        end
                        default: begin
                        end
                    endcase
                end

                frame_state_q              <= FRAME_IDLE;
                frame_proto_error_q        <= 1'b0;
                frame_algo_sel_q           <= ALG_SM4;
                frame_cfg_index_q          <= 3'd0;
                frame_cfg_key_q            <= 128'd0;
                frame_trace_page_idx_q     <= 4'd0;
                frame_stream_start_alg_q   <= ALG_SM4;
                frame_stream_start_total_q <= 16'd0;
                frame_stream_seq_q         <= 8'd0;
                frame_bench_force_seen_q   <= 1'b0;
                frame_bench_algo_valid_q   <= 1'b0;
                frame_bench_algo_q         <= ALG_SM4;
                frame_normal_payload_len_q <= 8'd0;
                frame_normal_meta_early_q  <= 1'b0;
            end
        end
    end

endmodule

