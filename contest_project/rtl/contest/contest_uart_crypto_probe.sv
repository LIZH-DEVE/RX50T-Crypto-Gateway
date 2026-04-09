`timescale 1ns/1ps

module contest_uart_crypto_probe #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    localparam [7:0] ASCII_ERROR = 8'h45; // E
    localparam [7:0] ASCII_NL    = 8'h0A;
    localparam [7:0] ASCII_STAT  = 8'h53; // S
    localparam [7:0] ASCII_QUERY = 8'h3F; // ?
    localparam [7:0] MODE_AES    = 8'h41; // A
    localparam [7:0] MODE_SM4    = 8'h53; // S
    localparam       ALG_SM4     = 1'b0;
    localparam       ALG_AES     = 1'b1;

    wire       rx_valid;
    wire [7:0] rx_data;
    wire       rx_frame_error;

    wire       parser_payload_valid;
    wire [7:0] parser_payload_byte;
    wire       parser_frame_done;
    wire       parser_error;
    wire [7:0] parser_payload_len;

    reg  [7:0] frame_key_q;
    reg        frame_key_valid_q;
    reg        frame_selector_seen_q;
    reg        frame_proto_error_q;
    reg        frame_query_q;
    reg        frame_block_q;
    reg        frame_algo_sel_q;

    reg        acl_in_valid_q;
    reg  [7:0] acl_in_data_q;
    reg        acl_in_last_q;
    wire [7:0] acl_match_key;

    wire       acl_valid;
    wire [7:0] acl_data;
    wire       acl_last;

    reg        bridge_in_valid_q;
    reg [7:0]  bridge_in_data_q;
    reg        bridge_in_last_q;
    reg        pending_error_q;
    reg        pending_error_nl_q;
    reg        pending_stats_q;
    reg  [2:0] pending_stats_idx_q;

    reg  [7:0] stat_total_frames_q;
    reg  [7:0] stat_acl_blocks_q;
    reg  [7:0] stat_aes_frames_q;
    reg  [7:0] stat_sm4_frames_q;
    reg  [7:0] stat_error_frames_q;

    wire       bridge_valid;
    wire [7:0] bridge_data;
    wire       bridge_last;
    wire       tx_ready;

    assign acl_match_key = frame_key_valid_q ? frame_key_q : acl_in_data_q;

    function automatic bit is_block_key(input [7:0] key);
        begin
            is_block_key = (key == 8'h58) || // X
                           (key == 8'h59) || // Y
                           (key == 8'h5A) || // Z
                           (key == 8'h57);   // W
        end
    endfunction

    function automatic [7:0] stats_byte(input [2:0] idx);
        begin
            case (idx)
                3'd0: stats_byte = ASCII_STAT;
                3'd1: stats_byte = stat_total_frames_q;
                3'd2: stats_byte = stat_acl_blocks_q;
                3'd3: stats_byte = stat_aes_frames_q;
                3'd4: stats_byte = stat_sm4_frames_q;
                3'd5: stats_byte = stat_error_frames_q;
                3'd6: stats_byte = ASCII_NL;
                default: stats_byte = 8'h00;
            endcase
        end
    endfunction

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
        .SOF_BYTE         (8'h55),
        .MAX_PAYLOAD_BYTES(64)
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
        .o_payload_count()
    );

    contest_acl_core u_acl (
        .clk             (i_clk),
        .rst_n           (i_rst_n),
        .parser_valid    (acl_in_valid_q),
        .parser_match_key(acl_match_key),
        .parser_payload  (acl_in_data_q),
        .parser_last     (acl_in_last_q),
        .acl_valid       (acl_valid),
        .acl_data        (acl_data),
        .acl_last        (acl_last)
    );

    contest_crypto_bridge u_bridge (
        .clk          (i_clk),
        .rst_n        (i_rst_n),
        .acl_valid    (bridge_in_valid_q),
        .acl_data     (bridge_in_data_q),
        .acl_last     (bridge_in_last_q),
        .i_algo_sel   (frame_algo_sel_q),
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

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            frame_key_q           <= 8'd0;
            frame_key_valid_q     <= 1'b0;
            frame_selector_seen_q <= 1'b0;
            frame_proto_error_q   <= 1'b0;
            frame_query_q         <= 1'b0;
            frame_block_q         <= 1'b0;
            frame_algo_sel_q      <= ALG_SM4;
            acl_in_valid_q        <= 1'b0;
            acl_in_data_q         <= 8'd0;
            acl_in_last_q         <= 1'b0;
            bridge_in_valid_q     <= 1'b0;
            bridge_in_data_q      <= 8'd0;
            bridge_in_last_q      <= 1'b0;
            pending_error_q       <= 1'b0;
            pending_error_nl_q    <= 1'b0;
            pending_stats_q       <= 1'b0;
            pending_stats_idx_q   <= 3'd0;
            stat_total_frames_q   <= 8'd0;
            stat_acl_blocks_q     <= 8'd0;
            stat_aes_frames_q     <= 8'd0;
            stat_sm4_frames_q     <= 8'd0;
            stat_error_frames_q   <= 8'd0;
        end else begin
            acl_in_valid_q    <= 1'b0;
            acl_in_data_q     <= 8'd0;
            acl_in_last_q     <= 1'b0;
            bridge_in_valid_q <= 1'b0;
            bridge_in_data_q  <= 8'd0;
            bridge_in_last_q  <= 1'b0;

            if (parser_error || rx_frame_error) begin
                pending_error_q       <= 1'b1;
                stat_error_frames_q   <= stat_error_frames_q + 8'd1;
                frame_key_valid_q     <= 1'b0;
                frame_selector_seen_q <= 1'b0;
                frame_proto_error_q   <= 1'b0;
                frame_query_q         <= 1'b0;
                frame_block_q         <= 1'b0;
                frame_algo_sel_q      <= ALG_SM4;
            end

            if (parser_payload_valid) begin
                if (!frame_selector_seen_q) begin
                    frame_selector_seen_q <= 1'b1;
                    if (parser_payload_len == 8'd1 && parser_payload_byte == ASCII_QUERY) begin
                        frame_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd17) || (parser_payload_len == 8'd33)) begin
                        if (parser_payload_byte == MODE_AES) begin
                            frame_algo_sel_q <= ALG_AES;
                        end else if (parser_payload_byte == MODE_SM4) begin
                            frame_algo_sel_q <= ALG_SM4;
                        end else begin
                            frame_proto_error_q <= 1'b1;
                        end
                    end else begin
                        frame_algo_sel_q <= ALG_SM4;
                        if (!frame_key_valid_q) begin
                            frame_key_q       <= parser_payload_byte;
                            frame_key_valid_q <= 1'b1;
                            frame_block_q     <= is_block_key(parser_payload_byte);
                        end
                        acl_in_valid_q <= 1'b1;
                        acl_in_data_q  <= parser_payload_byte;
                        acl_in_last_q  <= parser_frame_done;
                    end
                end else if (!frame_proto_error_q) begin
                    if (!frame_key_valid_q) begin
                        frame_key_q       <= parser_payload_byte;
                        frame_key_valid_q <= 1'b1;
                        frame_block_q     <= is_block_key(parser_payload_byte);
                    end
                    acl_in_valid_q <= 1'b1;
                    acl_in_data_q  <= parser_payload_byte;
                    acl_in_last_q  <= parser_frame_done;
                end
            end

            if (parser_frame_done) begin
                if ((parser_payload_valid && !frame_selector_seen_q &&
                     (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_QUERY)) ||
                    frame_query_q) begin
                    pending_stats_q     <= 1'b1;
                    pending_stats_idx_q <= 3'd0;
                end else if (frame_proto_error_q) begin
                    pending_error_q <= 1'b1;
                    stat_error_frames_q <= stat_error_frames_q + 8'd1;
                end else begin
                    stat_total_frames_q <= stat_total_frames_q + 8'd1;
                    if (frame_block_q) begin
                        stat_acl_blocks_q <= stat_acl_blocks_q + 8'd1;
                    end else if (frame_algo_sel_q == ALG_AES) begin
                        stat_aes_frames_q <= stat_aes_frames_q + 8'd1;
                    end else begin
                        stat_sm4_frames_q <= stat_sm4_frames_q + 8'd1;
                    end
                end
                frame_key_valid_q     <= 1'b0;
                frame_selector_seen_q <= 1'b0;
                frame_proto_error_q   <= 1'b0;
                frame_query_q         <= 1'b0;
                frame_block_q         <= 1'b0;
            end

            if (pending_error_q) begin
                bridge_in_valid_q  <= 1'b1;
                bridge_in_data_q   <= ASCII_ERROR;
                bridge_in_last_q   <= 1'b0;
                pending_error_q    <= 1'b0;
                pending_error_nl_q <= 1'b1;
            end else if (pending_error_nl_q) begin
                bridge_in_valid_q  <= 1'b1;
                bridge_in_data_q   <= ASCII_NL;
                bridge_in_last_q   <= 1'b1;
                pending_error_nl_q <= 1'b0;
            end else if (pending_stats_q) begin
                bridge_in_valid_q <= 1'b1;
                bridge_in_data_q  <= stats_byte(pending_stats_idx_q);
                bridge_in_last_q  <= (pending_stats_idx_q == 3'd6);
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
            end
        end
    end

endmodule
