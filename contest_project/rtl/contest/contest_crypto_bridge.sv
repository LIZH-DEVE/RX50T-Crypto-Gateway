`timescale 1ns/1ps

module contest_crypto_bridge (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       acl_valid,
    input  wire [7:0] acl_data,
    input  wire       acl_last,
    input  wire       i_algo_sel,

    input  wire       uart_tx_ready,
    output reg        bridge_valid,
    output reg [7:0]  bridge_data,
    output reg        bridge_last
);

    localparam [127:0] TEST_SM4_KEY = 128'h0123456789ABCDEFFEDCBA9876543210;
    localparam [127:0] TEST_AES_KEY = 128'h000102030405060708090A0B0C0D0E0F;

    localparam ALG_SM4 = 1'b0;
    localparam ALG_AES = 1'b1;

    localparam integer BLOCK_BYTES      = 16;
    localparam integer BLOCK_FIFO_DEPTH = 64;
    localparam integer BLOCK_FIFO_AW    = 6;

    localparam [2:0] AES_BOOT_INIT      = 3'd0;
    localparam [2:0] AES_BOOT_WAIT_BUSY = 3'd1;
    localparam [2:0] AES_BOOT_WAIT_RDY  = 3'd2;
    localparam [2:0] AES_IDLE           = 3'd3;
    localparam [2:0] AES_RUN_PULSE      = 3'd4;
    localparam [2:0] AES_RUN_WAIT_BUSY  = 3'd5;
    localparam [2:0] AES_RUN_WAIT_DONE  = 3'd6;

    function automatic [127:0] block_insert_byte(
        input [127:0] cur,
        input [3:0]   byte_idx,
        input [7:0]   byte_val
    );
        reg [127:0] tmp;
        begin
            tmp = cur;
            tmp[127 - (byte_idx * 8) -: 8] = byte_val;
            block_insert_byte = tmp;
        end
    endfunction

    reg [127:0] gather_shift_q;
    reg [3:0]   gather_count_q;

    reg [127:0] raw_shift_q;
    reg [4:0]   raw_count_q;
    reg         raw_pending_q;

    reg [127:0] tx_shift_q;
    reg [4:0]   tx_count_q;
    reg         tx_last_q;
    reg [7:0]   tx_byte_q;
    reg         tx_byte_valid_q;
    reg         tx_byte_last_q;

    reg         worker_busy_q;
    reg         ingress_fetch_pending_q;
    reg         egress_fetch_pending_q;
    reg         active_algo_q;
    reg         worker_last_q;
    reg [127:0] crypto_block_q;

    reg         sm4_key_sent_q;
    reg         sm4_user_key_valid_q;
    reg         sm4_start_seen_q;
    reg         sm4_wait_done_clear_q;
    reg [2:0]   sm4_valid_burst_q;

    reg [2:0]   aes_state_q;
    reg         aes_init_q;
    reg         aes_next_q;

    wire         sm4_key_ready;
    wire         sm4_done;
    wire [127:0] sm4_result;
    wire         sm4_valid_in;
    wire         aes_ready;
    wire         aes_result_valid;
    wire [127:0] aes_result;

    wire [4:0]   gather_count_next_w;
    wire         short_raw_flush_w;

    assign gather_count_next_w = gather_count_q + 5'd1;
    assign short_raw_flush_w   = acl_valid && acl_last && (gather_count_next_w < BLOCK_BYTES);

    reg          ingress_wr_en_q;
    reg  [129:0] ingress_wr_data_q;
    reg          ingress_rd_en_q;
    wire [129:0] ingress_rd_data_w;
    wire         ingress_rd_valid_w;
    wire         ingress_full_w;
    wire         ingress_empty_w;
    wire [BLOCK_FIFO_AW:0] ingress_level_w;

    reg          egress_wr_en_q;
    reg  [128:0] egress_wr_data_q;
    reg          egress_rd_en_q;
    wire [128:0] egress_rd_data_w;
    wire         egress_rd_valid_w;
    wire         egress_full_w;
    wire         egress_empty_w;
    wire [BLOCK_FIFO_AW:0] egress_level_w;

    assign sm4_valid_in =
        worker_busy_q &&
        (active_algo_q == ALG_SM4) &&
        sm4_start_seen_q &&
        (sm4_valid_burst_q != 3'd0);

    contest_block_fifo #(
        .WIDTH (130),
        .DEPTH (BLOCK_FIFO_DEPTH),
        .ADDR_W(BLOCK_FIFO_AW)
    ) u_ingress_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (ingress_wr_en_q),
        .wr_data(ingress_wr_data_q),
        .full   (ingress_full_w),
        .rd_en  (ingress_rd_en_q),
        .rd_data(ingress_rd_data_w),
        .rd_valid(ingress_rd_valid_w),
        .empty  (ingress_empty_w),
        .level  (ingress_level_w)
    );

    contest_block_fifo #(
        .WIDTH (129),
        .DEPTH (BLOCK_FIFO_DEPTH),
        .ADDR_W(BLOCK_FIFO_AW)
    ) u_egress_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (egress_wr_en_q),
        .wr_data(egress_wr_data_q),
        .full   (egress_full_w),
        .rd_en  (egress_rd_en_q),
        .rd_data(egress_rd_data_w),
        .rd_valid(egress_rd_valid_w),
        .empty  (egress_empty_w),
        .level  (egress_level_w)
    );

    aes_core u_aes (
        .clk         (clk),
        .reset_n     (rst_n),
        .encdec      (1'b1),
        .init        (aes_init_q),
        .next        (aes_next_q),
        .ready       (aes_ready),
        .key         ({TEST_AES_KEY, 128'd0}),
        .keylen      (1'b0),
        .block       (crypto_block_q),
        .result      (aes_result),
        .result_valid(aes_result_valid)
    );

    sm4_top u_sm4 (
        .clk               (clk),
        .reset_n           (rst_n),
        .sm4_enable_in     (1'b1),
        .encdec_enable_in  (worker_busy_q && (active_algo_q == ALG_SM4)),
        .encdec_sel_in     (1'b0),
        .valid_in          (sm4_valid_in),
        .data_in           (crypto_block_q),
        .enable_key_exp_in (1'b1),
        .user_key_valid_in (sm4_user_key_valid_q),
        .user_key_in       (TEST_SM4_KEY),
        .key_exp_ready_out (sm4_key_ready),
        .ready_out         (sm4_done),
        .result_out        (sm4_result)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            gather_shift_q       <= 128'd0;
            gather_count_q       <= 4'd0;

            raw_shift_q          <= 128'd0;
            raw_count_q          <= 5'd0;
            raw_pending_q        <= 1'b0;

            tx_shift_q           <= 128'd0;
            tx_count_q           <= 5'd0;
            tx_last_q            <= 1'b0;
            tx_byte_q            <= 8'd0;
            tx_byte_valid_q      <= 1'b0;
            tx_byte_last_q       <= 1'b0;

            worker_busy_q        <= 1'b0;
            ingress_fetch_pending_q <= 1'b0;
            egress_fetch_pending_q  <= 1'b0;
            active_algo_q        <= ALG_SM4;
            worker_last_q        <= 1'b0;
            crypto_block_q       <= 128'd0;

            sm4_key_sent_q       <= 1'b0;
            sm4_user_key_valid_q <= 1'b0;
            sm4_start_seen_q     <= 1'b0;
            sm4_wait_done_clear_q<= 1'b0;
            sm4_valid_burst_q    <= 3'd0;

            aes_state_q          <= AES_BOOT_INIT;
            aes_init_q           <= 1'b0;
            aes_next_q           <= 1'b0;
            ingress_wr_en_q      <= 1'b0;
            ingress_wr_data_q    <= 130'd0;
            ingress_rd_en_q      <= 1'b0;
            egress_wr_en_q       <= 1'b0;
            egress_wr_data_q     <= 129'd0;
            egress_rd_en_q       <= 1'b0;

            bridge_valid         <= 1'b0;
            bridge_data          <= 8'd0;
            bridge_last          <= 1'b0;
        end else begin
            bridge_valid         <= tx_byte_valid_q;
            bridge_data          <= tx_byte_q;
            bridge_last          <= tx_byte_last_q;
            sm4_user_key_valid_q <= 1'b0;
            aes_init_q           <= 1'b0;
            aes_next_q           <= 1'b0;
            ingress_wr_en_q      <= 1'b0;
            ingress_wr_data_q    <= 130'd0;
            ingress_rd_en_q      <= 1'b0;
            egress_wr_en_q       <= 1'b0;
            egress_wr_data_q     <= 129'd0;
            egress_rd_en_q       <= 1'b0;

            if (!sm4_key_sent_q) begin
                sm4_user_key_valid_q <= 1'b1;
                sm4_key_sent_q       <= 1'b1;
            end

            case (aes_state_q)
                AES_BOOT_INIT: begin
                    aes_init_q  <= 1'b1;
                    aes_state_q <= AES_BOOT_WAIT_BUSY;
                end

                AES_BOOT_WAIT_BUSY: begin
                    if (!aes_ready) begin
                        aes_state_q <= AES_BOOT_WAIT_RDY;
                    end
                end

                AES_BOOT_WAIT_RDY: begin
                    if (aes_ready) begin
                        aes_state_q <= AES_IDLE;
                    end
                end

                AES_IDLE: begin
                    if (worker_busy_q && (active_algo_q == ALG_AES)) begin
                        aes_state_q <= AES_RUN_PULSE;
                    end
                end

                AES_RUN_PULSE: begin
                    aes_next_q  <= 1'b1;
                    aes_state_q <= AES_RUN_WAIT_BUSY;
                end

                AES_RUN_WAIT_BUSY: begin
                    if (!aes_ready) begin
                        aes_state_q <= AES_RUN_WAIT_DONE;
                    end
                end

                AES_RUN_WAIT_DONE: begin
                    if (aes_result_valid) begin
                        aes_state_q <= AES_IDLE;
                    end
                end

                default: begin
                    aes_state_q <= AES_BOOT_INIT;
                end
            endcase

            if (sm4_wait_done_clear_q && !sm4_done) begin
                sm4_wait_done_clear_q <= 1'b0;
            end

            if (acl_valid) begin
                if (gather_count_next_w == BLOCK_BYTES) begin
                    if (!ingress_full_w) begin
                        ingress_wr_en_q   <= 1'b1;
                        ingress_wr_data_q <= {i_algo_sel, acl_last,
                                              block_insert_byte(gather_shift_q, gather_count_q, acl_data)};
                    end
                    gather_shift_q <= 128'd0;
                    gather_count_q <= 4'd0;
                end else begin
                    gather_shift_q <= block_insert_byte(gather_shift_q, gather_count_q, acl_data);
                    gather_count_q <= gather_count_next_w[3:0];
                    if (acl_last) begin
                        raw_shift_q   <= block_insert_byte(gather_shift_q, gather_count_q, acl_data);
                        raw_count_q   <= gather_count_next_w[4:0];
                        raw_pending_q <= 1'b1;
                        gather_shift_q<= 128'd0;
                        gather_count_q<= 4'd0;
                    end
                end
            end

            if (!worker_busy_q && !ingress_fetch_pending_q && !ingress_empty_w &&
                (aes_state_q == AES_IDLE) && !sm4_wait_done_clear_q) begin
                ingress_rd_en_q          <= 1'b1;
                ingress_fetch_pending_q  <= 1'b1;
            end

            if (ingress_rd_valid_w) begin
                crypto_block_q           <= ingress_rd_data_w[127:0];
                worker_last_q            <= ingress_rd_data_w[128];
                active_algo_q            <= ingress_rd_data_w[129];
                worker_busy_q            <= 1'b1;
                ingress_fetch_pending_q  <= 1'b0;
                sm4_start_seen_q         <= 1'b0;
                sm4_valid_burst_q        <= 3'd0;
            end

            if (worker_busy_q) begin
                if (active_algo_q == ALG_SM4) begin
                    if (!sm4_wait_done_clear_q) begin
                        if (sm4_key_ready && !sm4_start_seen_q) begin
                            sm4_start_seen_q  <= 1'b1;
                            sm4_valid_burst_q <= 3'd4;
                        end else if (sm4_valid_burst_q != 3'd0) begin
                            sm4_valid_burst_q <= sm4_valid_burst_q - 3'd1;
                        end
                    end

                    if (sm4_done && !egress_full_w) begin
                        egress_wr_en_q         <= 1'b1;
                        egress_wr_data_q       <= {worker_last_q, sm4_result};
                        worker_busy_q          <= 1'b0;
                        sm4_start_seen_q       <= 1'b0;
                        sm4_valid_burst_q      <= 3'd0;
                        sm4_wait_done_clear_q  <= 1'b1;
                    end
                end else if (aes_result_valid && (aes_state_q == AES_RUN_WAIT_DONE) && !egress_full_w) begin
                    egress_wr_en_q    <= 1'b1;
                    egress_wr_data_q  <= {worker_last_q, aes_result};
                    worker_busy_q     <= 1'b0;
                end
            end

            if (tx_count_q == 5'd0) begin
                if (raw_pending_q) begin
                    tx_shift_q    <= raw_shift_q;
                    tx_count_q    <= raw_count_q;
                    tx_last_q     <= 1'b1;
                    raw_pending_q <= 1'b0;
                    raw_shift_q   <= 128'd0;
                    raw_count_q   <= 5'd0;
                end else if (egress_rd_valid_w) begin
                    tx_shift_q            <= egress_rd_data_w[127:0];
                    tx_count_q            <= 5'd16;
                    tx_last_q             <= egress_rd_data_w[128];
                    egress_fetch_pending_q<= 1'b0;
                end else if (!egress_fetch_pending_q && !egress_empty_w && !short_raw_flush_w) begin
                    egress_rd_en_q         <= 1'b1;
                    egress_fetch_pending_q <= 1'b1;
                end
            end

            if (tx_byte_valid_q && uart_tx_ready) begin
                tx_byte_valid_q <= 1'b0;
                tx_byte_last_q  <= 1'b0;
            end

            if (!tx_byte_valid_q && (tx_count_q != 5'd0)) begin
                tx_byte_q       <= tx_shift_q[127:120];
                tx_byte_valid_q <= 1'b1;
                tx_byte_last_q  <= (tx_count_q == 5'd1) && tx_last_q;
                tx_shift_q      <= {tx_shift_q[119:0], 8'h00};
                tx_count_q      <= tx_count_q - 5'd1;
                if (tx_count_q == 5'd1) begin
                    tx_last_q <= 1'b0;
                end
            end
        end
    end

endmodule
