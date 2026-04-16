`timescale 1ns/1ps

module contest_crypto_block_engine (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_soft_reset,

    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [127:0] s_axis_tdata,
    input  wire         s_axis_tlast,
    input  wire [5:0]   s_axis_tuser,

    output reg          m_axis_tvalid,
    input  wire         m_axis_tready,
    output reg  [127:0] m_axis_tdata,
    output reg          m_axis_tlast,
    output reg  [5:0]   m_axis_tuser,

    output wire         o_pmu_crypto_active,
    output wire         o_idle
);

    localparam [127:0] TEST_SM4_KEY = 128'h0123456789ABCDEFFEDCBA9876543210;
    localparam [127:0] TEST_AES_KEY = 128'h000102030405060708090A0B0C0D0E0F;

    localparam ALG_SM4 = 1'b0;
    localparam ALG_AES = 1'b1;

    localparam integer BLOCK_FIFO_DEPTH = 64;
    localparam integer BLOCK_FIFO_AW    = 6;

    localparam [2:0] AES_BOOT_INIT      = 3'd0;
    localparam [2:0] AES_BOOT_WAIT_BUSY = 3'd1;
    localparam [2:0] AES_BOOT_WAIT_RDY  = 3'd2;
    localparam [2:0] AES_IDLE           = 3'd3;
    localparam [2:0] AES_RUN_PULSE      = 3'd4;
    localparam [2:0] AES_RUN_WAIT_BUSY  = 3'd5;
    localparam [2:0] AES_RUN_WAIT_DONE  = 3'd6;

    reg          ingress_rd_en_q;
    wire [134:0] ingress_rd_data_w;
    wire         ingress_rd_valid_w;
    wire         ingress_full_w;
    wire         ingress_empty_w;

    reg          egress_wr_en_q;
    reg  [134:0] egress_wr_data_q;
    reg          egress_rd_en_q;
    wire [134:0] egress_rd_data_w;
    wire         egress_rd_valid_w;
    wire         egress_full_w;
    wire         egress_empty_w;

    reg         ingress_fetch_pending_q;
    reg         egress_fetch_pending_q;
    reg [127:0] crypto_block_q;
    reg [5:0]   worker_user_q;
    reg         worker_last_q;
    reg         worker_busy_q;
    reg         worker_bypass_q;
    reg         active_algo_q;

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

    assign s_axis_tready = !ingress_full_w;
    assign sm4_valid_in =
        worker_busy_q &&
        !worker_bypass_q &&
        (active_algo_q == ALG_SM4) &&
        sm4_start_seen_q &&
        (sm4_valid_burst_q != 3'd0);
    assign o_pmu_crypto_active = worker_busy_q && !worker_bypass_q;
    assign o_idle =
        sm4_key_sent_q &&
        !worker_busy_q &&
        !ingress_fetch_pending_q &&
        !egress_fetch_pending_q &&
        ingress_empty_w &&
        egress_empty_w &&
        !m_axis_tvalid &&
        !sm4_start_seen_q &&
        !sm4_wait_done_clear_q &&
        (sm4_valid_burst_q == 3'd0) &&
        (aes_state_q == AES_IDLE) &&
        !ingress_rd_en_q &&
        !egress_wr_en_q &&
        !egress_rd_en_q;

    contest_block_fifo #(
        .WIDTH (135),
        .DEPTH (BLOCK_FIFO_DEPTH),
        .ADDR_W(BLOCK_FIFO_AW)
    ) u_ingress_fifo (
        .clk     (i_clk),
        .rst_n   (i_rst_n),
        .soft_reset(i_soft_reset),
        .wr_en   (s_axis_tvalid && s_axis_tready),
        .wr_data ({s_axis_tuser, s_axis_tlast, s_axis_tdata}),
        .full    (ingress_full_w),
        .rd_en   (ingress_rd_en_q),
        .rd_data (ingress_rd_data_w),
        .rd_valid(ingress_rd_valid_w),
        .empty   (ingress_empty_w),
        .level   ()
    );

    contest_block_fifo #(
        .WIDTH (135),
        .DEPTH (BLOCK_FIFO_DEPTH),
        .ADDR_W(BLOCK_FIFO_AW)
    ) u_egress_fifo (
        .clk     (i_clk),
        .rst_n   (i_rst_n),
        .soft_reset(i_soft_reset),
        .wr_en   (egress_wr_en_q),
        .wr_data (egress_wr_data_q),
        .full    (egress_full_w),
        .rd_en   (egress_rd_en_q),
        .rd_data (egress_rd_data_w),
        .rd_valid(egress_rd_valid_w),
        .empty   (egress_empty_w),
        .level   ()
    );

    aes_core u_aes (
        .clk         (i_clk),
        .reset_n     (i_rst_n),
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
        .clk               (i_clk),
        .reset_n           (i_rst_n),
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

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            ingress_rd_en_q          <= 1'b0;
            egress_wr_en_q           <= 1'b0;
            egress_wr_data_q         <= 135'd0;
            egress_rd_en_q           <= 1'b0;
            ingress_fetch_pending_q  <= 1'b0;
            egress_fetch_pending_q   <= 1'b0;
            crypto_block_q           <= 128'd0;
            worker_user_q            <= 6'd0;
            worker_last_q            <= 1'b0;
            worker_busy_q            <= 1'b0;
            worker_bypass_q          <= 1'b0;
            active_algo_q            <= ALG_SM4;
            sm4_key_sent_q           <= 1'b0;
            sm4_user_key_valid_q     <= 1'b0;
            sm4_start_seen_q         <= 1'b0;
            sm4_wait_done_clear_q    <= 1'b0;
            sm4_valid_burst_q        <= 3'd0;
            aes_state_q              <= AES_BOOT_INIT;
            aes_init_q               <= 1'b0;
            aes_next_q               <= 1'b0;
            m_axis_tvalid            <= 1'b0;
            m_axis_tdata             <= 128'd0;
            m_axis_tlast             <= 1'b0;
            m_axis_tuser             <= 6'd0;
        end else if (i_soft_reset) begin
            ingress_rd_en_q          <= 1'b0;
            egress_wr_en_q           <= 1'b0;
            egress_wr_data_q         <= 135'd0;
            egress_rd_en_q           <= 1'b0;
            ingress_fetch_pending_q  <= 1'b0;
            egress_fetch_pending_q   <= 1'b0;
            crypto_block_q           <= 128'd0;
            worker_user_q            <= 6'd0;
            worker_last_q            <= 1'b0;
            worker_busy_q            <= 1'b0;
            worker_bypass_q          <= 1'b0;
            active_algo_q            <= ALG_SM4;
            sm4_key_sent_q           <= 1'b0;
            sm4_user_key_valid_q     <= 1'b0;
            sm4_start_seen_q         <= 1'b0;
            sm4_wait_done_clear_q    <= 1'b0;
            sm4_valid_burst_q        <= 3'd0;
            aes_state_q              <= AES_BOOT_INIT;
            aes_init_q               <= 1'b0;
            aes_next_q               <= 1'b0;
            m_axis_tvalid            <= 1'b0;
            m_axis_tdata             <= 128'd0;
            m_axis_tlast             <= 1'b0;
            m_axis_tuser             <= 6'd0;
        end else begin
            ingress_rd_en_q      <= 1'b0;
            egress_wr_en_q       <= 1'b0;
            egress_wr_data_q     <= 135'd0;
            egress_rd_en_q       <= 1'b0;
            sm4_user_key_valid_q <= 1'b0;
            aes_init_q           <= 1'b0;
            aes_next_q           <= 1'b0;

            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end

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
                    if (worker_busy_q && !worker_bypass_q && (active_algo_q == ALG_AES)) begin
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

            if (!worker_busy_q &&
                !ingress_fetch_pending_q &&
                !ingress_empty_w &&
                (aes_state_q == AES_IDLE) &&
                !sm4_wait_done_clear_q) begin
                ingress_rd_en_q         <= 1'b1;
                ingress_fetch_pending_q <= 1'b1;
            end

            if (ingress_rd_valid_w) begin
                crypto_block_q          <= ingress_rd_data_w[127:0];
                worker_last_q           <= ingress_rd_data_w[128];
                worker_user_q           <= ingress_rd_data_w[134:129];
                worker_bypass_q         <= ingress_rd_data_w[130];
                active_algo_q           <= ingress_rd_data_w[129];
                worker_busy_q           <= 1'b1;
                ingress_fetch_pending_q <= 1'b0;
                sm4_start_seen_q        <= 1'b0;
                sm4_valid_burst_q       <= 3'd0;
            end

            if (worker_busy_q) begin
                if (worker_bypass_q) begin
                    if (!egress_full_w) begin
                        egress_wr_en_q  <= 1'b1;
                        egress_wr_data_q <= {worker_user_q, worker_last_q, crypto_block_q};
                        worker_busy_q   <= 1'b0;
                    end
                end else if (active_algo_q == ALG_SM4) begin
                    if (!sm4_wait_done_clear_q) begin
                        if (sm4_key_ready && !sm4_start_seen_q) begin
                            sm4_start_seen_q  <= 1'b1;
                            sm4_valid_burst_q <= 3'd4;
                        end else if (sm4_valid_burst_q != 3'd0) begin
                            sm4_valid_burst_q <= sm4_valid_burst_q - 3'd1;
                        end
                    end

                    if (sm4_done && !egress_full_w) begin
                        egress_wr_en_q        <= 1'b1;
                        egress_wr_data_q      <= {worker_user_q, worker_last_q, sm4_result};
                        worker_busy_q         <= 1'b0;
                        sm4_start_seen_q      <= 1'b0;
                        sm4_valid_burst_q     <= 3'd0;
                        sm4_wait_done_clear_q <= 1'b1;
                    end
                end else if (aes_result_valid && (aes_state_q == AES_RUN_WAIT_DONE) && !egress_full_w) begin
                    egress_wr_en_q    <= 1'b1;
                    egress_wr_data_q  <= {worker_user_q, worker_last_q, aes_result};
                    worker_busy_q     <= 1'b0;
                end
            end

            if (!m_axis_tvalid) begin
                if (egress_rd_valid_w) begin
                    m_axis_tvalid          <= 1'b1;
                    m_axis_tdata           <= egress_rd_data_w[127:0];
                    m_axis_tlast           <= egress_rd_data_w[128];
                    m_axis_tuser           <= egress_rd_data_w[134:129];
                    egress_fetch_pending_q <= 1'b0;
                end else if (!egress_fetch_pending_q && !egress_empty_w) begin
                    egress_rd_en_q         <= 1'b1;
                    egress_fetch_pending_q <= 1'b1;
                end
            end
        end
    end

endmodule
