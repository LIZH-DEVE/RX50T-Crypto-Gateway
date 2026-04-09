`timescale 1ns / 1ps

module crypto_bridge_top #(
    parameter int NUM_INSTANCES = 16
)(
    input  logic         clk,
    input  logic         rst_n,

    input  logic         i_algo_sel,
    input  logic         i_encdec,
    input  logic         i_aes256_en,
    input  logic [127:0] i_key,
    input  logic [127:0] i_key_hi,
    output logic         o_system_ready,
    output logic [127:0] o_debug_last_plaintext,
    output logic [127:0] o_debug_key_lo_active,

    input  logic [31:0]  i_pbm_data,
    input  logic         i_pbm_empty,
    input  logic         i_pbm_valid,
    input  logic         i_pkt_start,
    input  logic         i_pkt_end,
    input  logic         i_cbc_mode,
    input  logic [127:0] i_iv_header,
    output logic         o_pbm_rd_en,

    output logic [31:0]  o_tx_data,
    output logic         o_tx_last,
    output logic         o_tx_empty,
    input  logic         i_tx_rd_en
);

    localparam INST_WIDTH = (NUM_INSTANCES > 1) ? $clog2(NUM_INSTANCES) : 1;
    localparam SEQ_WIDTH = 16;
    localparam logic [15:0] TIMEOUT_CYCLES = 16'd2000;
    localparam ROB_DEPTH = 32;
    localparam ROB_PTR_WIDTH = $clog2(ROB_DEPTH);

    logic [NUM_INSTANCES-1:0] inst_start;
    logic [NUM_INSTANCES-1:0] inst_ready;
    logic [NUM_INSTANCES-1:0] inst_result_valid;
    logic [127:0] inst_plaintext [NUM_INSTANCES];
    logic [127:0] inst_result [NUM_INSTANCES];
    logic [NUM_INSTANCES-1:0] inst_busy;
    logic [NUM_INSTANCES-1:0] inst_key_init_done;
    logic [SEQ_WIDTH-1:0] inst_seq_num [NUM_INSTANCES];
    
    logic [INST_WIDTH-1:0] sched_next_inst;
    logic sched_valid;
    logic [NUM_INSTANCES-1:0] inst_available;
    
    logic [127:0] plaintext_reg;
    logic [2:0]   cap_cnt;
    logic [2:0]   req_cnt;
    
    logic [127:0] rob_data [ROB_DEPTH];
    logic         rob_valid [ROB_DEPTH];
    
    logic         mid_fifo_wr_en;
    logic [127:0] mid_fifo_din;
    logic         mid_fifo_full;
    logic         mid_fifo_empty;
    logic         mid_fifo_rd_en;
    logic [127:0] mid_fifo_dout;
    
    logic         gb_din_valid;
    logic         gb_din_ready;
    logic [31:0]  gb_dout;
    logic         gb_dout_valid;
    logic         gb_dout_last;
    logic         gb_dout_ready;
    logic         out_fifo_full;
    logic [32:0]  out_fifo_dout;
    
    logic [15:0] timeout_cnt [NUM_INSTANCES];
    logic [NUM_INSTANCES-1:0] timeout_hit;
    
    logic         algo_reg;
    logic         encdec_reg;
    logic         aes256_reg;
    logic [127:0] key_shadow_lo_reg;
    logic [127:0] key_shadow_hi_reg;
    logic [127:0] key_mask_lo_reg;
    logic [127:0] key_mask_hi_reg;
    logic [255:0] key_lfsr;
    logic [255:0] key_active;
    logic [127:0] key_lo_active;
    logic [127:0] key_hi_active;
    logic [127:0] debug_last_plaintext_q;
    logic         bridge_pbm_fire;
    logic         cbc_pkt_active;
    logic [127:0] cbc_iv_header;
    
    logic [31:0]  context_fp_cache;
    logic [31:0]  context_fp_now;
    logic         context_reload;
    
    logic [SEQ_WIDTH-1:0] input_seq_counter;
    logic [SEQ_WIDTH-1:0] output_seq_expected;

    function automatic [31:0] context_fp_fn;
        input [127:0] key_lo;
        input [127:0] key_hi;
        input         algo;
        input         encd;
        input         aes256;
        begin
            context_fp_fn = key_lo[31:0] ^ key_lo[63:32] ^ key_lo[95:64] ^ key_lo[127:96] ^
                            key_hi[31:0] ^ key_hi[63:32] ^ key_hi[95:64] ^ key_hi[127:96] ^
                            {29'd0, aes256, encd, algo};
        end
    endfunction

    assign context_fp_now = context_fp_fn(i_key, i_key_hi, i_algo_sel, i_encdec, i_aes256_en);
    assign key_lo_active = key_shadow_lo_reg ^ key_mask_lo_reg;
    assign key_hi_active = key_shadow_hi_reg ^ key_mask_hi_reg;
    assign key_active = aes256_reg ? {key_hi_active, key_lo_active} : {128'd0, key_lo_active};
    assign o_debug_last_plaintext = debug_last_plaintext_q;
    assign o_debug_key_lo_active = key_lo_active;
    assign bridge_pbm_fire = i_pbm_valid && o_pbm_rd_en;

    // CBC mode is packet-atomic on the active shadow path.
    // Readiness stage only: latch packet metadata here without introducing
    // XOR/chaining data dependencies until the bridge becomes truly CBC-aware.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cbc_pkt_active <= 1'b0;
            cbc_iv_header <= 128'd0;
        end else if (bridge_pbm_fire) begin
            if (i_pkt_start) begin
                cbc_pkt_active <= i_cbc_mode;
                cbc_iv_header <= i_iv_header;
            end
            if (i_pkt_end) begin
                cbc_pkt_active <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            context_fp_cache <= 32'd0;
            context_reload <= 1'b0;
        end else begin
            context_reload <= 1'b0;
            if (!i_pbm_empty && (|inst_available) && (cap_cnt == 3'd0)) begin
                if (context_fp_cache != context_fp_now) begin
                    context_reload  <= 1'b1;
                    context_fp_cache <= context_fp_now;
                end
            end
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_seq_counter <= {SEQ_WIDTH{1'b0}};
            debug_last_plaintext_q <= 128'd0;
        end else if (sched_valid) begin
            input_seq_counter <= input_seq_counter + 1'b1;
            debug_last_plaintext_q <= plaintext_reg;
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_seq_expected <= {SEQ_WIDTH{1'b0}};
        end else if (mid_fifo_wr_en) begin
            output_seq_expected <= output_seq_expected + 1'b1;
        end
    end
    
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_COLLECT,
        ST_DISPATCH
    } input_state_t;
    
    input_state_t input_state, input_next_state;
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            input_state <= ST_IDLE;
            plaintext_reg <= 128'd0;
            cap_cnt <= 3'd0;
            req_cnt <= 3'd0;
            algo_reg <= 1'b0;
            encdec_reg <= 1'b1;
            aes256_reg <= 1'b0;
            key_shadow_lo_reg <= 128'd0;
            key_shadow_hi_reg <= 128'd0;
            key_mask_lo_reg <= 128'd0;
            key_mask_hi_reg <= 128'd0;
            key_lfsr <= 256'h1;
        end else begin
            input_state <= input_next_state;
            key_lfsr <= {key_lfsr[254:0], key_lfsr[255] ^ key_lfsr[21] ^ key_lfsr[1] ^ key_lfsr[0]};
            
            case (input_state)
                ST_IDLE: begin
                    if (!i_pbm_empty && (|inst_available)) begin
                        plaintext_reg <= 128'd0;
                        cap_cnt <= 3'd0;
                        req_cnt <= 3'd0;
                        algo_reg <= i_algo_sel;
                        encdec_reg <= i_encdec;
                        aes256_reg <= i_aes256_en;
                        key_shadow_lo_reg <= i_key ^ key_lfsr[127:0];
                        key_shadow_hi_reg <= i_key_hi ^ key_lfsr[255:128];
                        key_mask_lo_reg <= key_lfsr[127:0];
                        key_mask_hi_reg <= key_lfsr[255:128];
                    end
                end
                
                ST_COLLECT: begin
                    if (o_pbm_rd_en) begin
                        req_cnt <= req_cnt + 1'b1;
                    end
                    if (i_pbm_valid && (cap_cnt < 3'd4)) begin
                        cap_cnt <= cap_cnt + 1'b1;
                        plaintext_reg <= {plaintext_reg[95:0], i_pbm_data};
                    end
                end
                
                ST_DISPATCH: begin
                end
                
                default: ;
            endcase
        end
    end
    
    always_comb begin
        input_next_state = ST_IDLE;
        o_pbm_rd_en = 1'b0;
        sched_valid = 1'b0;
        
        case (input_state)
            ST_IDLE: begin
                if (!i_pbm_empty && (|inst_available)) begin
                    input_next_state = ST_COLLECT;
                end
            end
            
            ST_COLLECT: begin
                // Only request more reads when we haven't fully collected yet.
                // Critical fix: suppress read when the 4th word is arriving this cycle
                // (cap_cnt==3 && i_pbm_valid means we're about to dispatch).
                if (!i_pbm_empty && (req_cnt < 3'd4) && !(i_pbm_valid && cap_cnt == 3'd3)) begin
                    o_pbm_rd_en = 1'b1;
                end
                
                if (i_pbm_valid && (cap_cnt == 3'd3)) begin
                    input_next_state = ST_DISPATCH;
                end else begin
                    input_next_state = ST_COLLECT;
                end
            end
            
            ST_DISPATCH: begin
                if (|inst_available) begin
                    sched_valid = 1'b1;
                    input_next_state = ST_IDLE;
                end else begin
                    input_next_state = ST_DISPATCH;
                end
            end
            
            default: input_next_state = ST_IDLE;
        endcase
    end
    
    logic rob_not_full;
    assign rob_not_full = (input_seq_counter - output_seq_expected) < ROB_DEPTH[SEQ_WIDTH-1:0];
    assign inst_available = {NUM_INSTANCES{rob_not_full}} & ~inst_busy & inst_ready;
    
    logic [INST_WIDTH-1:0] rr_ptr;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr <= {INST_WIDTH{1'b0}};
        end else if (sched_valid) begin
            rr_ptr <= (rr_ptr == NUM_INSTANCES - 1) ? {INST_WIDTH{1'b0}} : rr_ptr + 1'b1;
        end
    end
    
    always_comb begin
        sched_next_inst = {INST_WIDTH{1'b0}};
        for (int offset = 0; offset < NUM_INSTANCES; offset++) begin
            automatic int idx = (rr_ptr + offset) % NUM_INSTANCES;
            if (inst_available[idx]) begin
                sched_next_inst = idx[INST_WIDTH-1:0];
                break;
            end
        end
    end
    
    genvar gi_ctrl;
    generate
        for (gi_ctrl = 0; gi_ctrl < NUM_INSTANCES; gi_ctrl++) begin : gen_inst_ctrl
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    inst_start[gi_ctrl] <= 1'b0;
                end else begin
                    inst_start[gi_ctrl] <= sched_valid && (sched_next_inst == gi_ctrl) && inst_available[gi_ctrl];
                end
            end
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    inst_busy[gi_ctrl] <= 1'b0;
                end else begin
                    if (inst_start[gi_ctrl]) begin
                        inst_busy[gi_ctrl] <= 1'b1;
                    end else if (inst_result_valid[gi_ctrl] && inst_busy[gi_ctrl]) begin
                        inst_busy[gi_ctrl] <= 1'b0;
                    end
                end
            end
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    inst_plaintext[gi_ctrl] <= 128'd0;
                end else if (inst_start[gi_ctrl]) begin
                    inst_plaintext[gi_ctrl] <= plaintext_reg;
                end
            end
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    inst_seq_num[gi_ctrl] <= {SEQ_WIDTH{1'b0}};
                end else if (inst_start[gi_ctrl]) begin
                    inst_seq_num[gi_ctrl] <= input_seq_counter - 1'b1;
                end
            end
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    timeout_cnt[gi_ctrl] <= 16'd0;
                    timeout_hit[gi_ctrl] <= 1'b0;
                end else begin
                    if (inst_start[gi_ctrl]) begin
                        timeout_cnt[gi_ctrl] <= 16'd0;
                        timeout_hit[gi_ctrl] <= 1'b0;
                    end else if (inst_busy[gi_ctrl] && !timeout_hit[gi_ctrl]) begin
                        if (timeout_cnt[gi_ctrl] >= TIMEOUT_CYCLES) begin
                            timeout_hit[gi_ctrl] <= 1'b1;
                        end else begin
                            timeout_cnt[gi_ctrl] <= timeout_cnt[gi_ctrl] + 1'b1;
                        end
                    end
                end
            end
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    inst_key_init_done[gi_ctrl] <= 1'b0;
                end else begin
                    if (context_reload) begin
                        inst_key_init_done[gi_ctrl] <= 1'b0;
                    end else if (inst_result_valid[gi_ctrl] && inst_busy[gi_ctrl]) begin
                        inst_key_init_done[gi_ctrl] <= 1'b1;
                    end
                end
            end
        end
    endgenerate
    
    genvar gi_crypto;
    generate
        for (gi_crypto = 0; gi_crypto < NUM_INSTANCES; gi_crypto++) begin : gen_crypto_cores
            logic aes_init, aes_next, aes_ready, aes_result_valid;
            logic [127:0] aes_result;
            
            logic sm4_key_exp_en, sm4_user_key_valid, sm4_valid_in, sm4_encdec_en;
            logic sm4_key_ready, sm4_ready;
            logic [127:0] sm4_result;
            logic sm4_busy_seen;
            
            localparam AES_IDLE      = 3'd0;
            localparam AES_INIT      = 3'd1;
            localparam AES_WAIT_INIT = 3'd2;
            localparam AES_NEXT      = 3'd3;
            localparam AES_WAIT_NEXT = 3'd4;
            localparam AES_WAIT_DONE = 3'd5;
            
            localparam SM4_IDLE      = 3'd0;
            localparam SM4_KEY_EXP   = 3'd1;
            localparam SM4_WAIT_KEY  = 3'd2;
            localparam SM4_ENCRYPT   = 3'd3;
            localparam SM4_WAIT_NEXT = 3'd4;
            localparam SM4_WAIT_DONE = 3'd5;
            
            logic [2:0] aes_state;
            logic [2:0] sm4_state;
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    aes_state <= AES_IDLE;
                end else begin
                    if (algo_reg == 1'b0) begin
                        case (aes_state)
                            AES_IDLE: begin
                                if (inst_start[gi_crypto]) begin
                                    if (!inst_key_init_done[gi_crypto]) begin
                                        aes_state <= AES_INIT;
                                    end else begin
                                        aes_state <= AES_NEXT;
                                    end
                                end
                            end
                            
                            AES_INIT: begin
                                aes_state <= AES_WAIT_INIT;
                            end
                            
                            AES_WAIT_INIT: begin
                                if (!aes_init && aes_ready) begin
                                    aes_state <= AES_NEXT;
                                end
                            end
                            
                            AES_NEXT: begin
                                aes_state <= AES_WAIT_NEXT;
                            end
                            
                            AES_WAIT_NEXT: begin
                                // Wait for core to drop ready as it accepts NEXT
                                if (!aes_ready) begin
                                    aes_state <= AES_WAIT_DONE;
                                end
                            end
                            
                            AES_WAIT_DONE: begin
                                if (!aes_next && aes_result_valid) begin
                                    aes_state <= AES_IDLE;
                                end
                            end
                            
                            default: aes_state <= AES_IDLE;
                        endcase
                    end else begin
                        aes_state <= AES_IDLE;
                    end
                end
            end
            
            assign aes_init = (aes_state == AES_INIT);
            assign aes_next = (aes_state == AES_NEXT);
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    sm4_state <= SM4_IDLE;
                    sm4_busy_seen <= 1'b0;
                end else begin
                    if (algo_reg == 1'b1) begin
                        case (sm4_state)
                            SM4_IDLE: begin
                                sm4_busy_seen <= 1'b0;
                                if (inst_start[gi_crypto]) begin
                                    if (!inst_key_init_done[gi_crypto]) begin
                                        sm4_state <= SM4_KEY_EXP;
                                    end else begin
                                        sm4_state <= SM4_ENCRYPT;
                                    end
                                end
                            end
                            
                            SM4_KEY_EXP: begin
                                sm4_state <= SM4_WAIT_KEY;
                            end
                            
                            SM4_WAIT_KEY: begin
                                // Ensure SM4 has started and is not holding a ready from a prior operation.
                                if (!sm4_user_key_valid && sm4_key_ready) begin
                                    sm4_state <= SM4_ENCRYPT;
                                end
                            end
                            
                            SM4_ENCRYPT: begin
                                sm4_busy_seen <= 1'b0;
                                sm4_state <= SM4_WAIT_NEXT;
                            end
                            
                            SM4_WAIT_NEXT: begin
                                // Must first see the core go busy (!ready),
                                // then wait for it to finish (ready pulse).
                                if (!sm4_ready) begin
                                    sm4_busy_seen <= 1'b1;
                                end
                                if (sm4_busy_seen && sm4_ready) begin
                                    sm4_state <= SM4_IDLE;
                                end
                            end
                            
                            SM4_WAIT_DONE: begin
                                // Legacy state - redirect to IDLE
                                sm4_state <= SM4_IDLE;
                            end
                            
                            default: sm4_state <= SM4_IDLE;
                        endcase
                    end else begin
                        sm4_state <= SM4_IDLE;
                    end
                end
            end
            
            assign sm4_key_exp_en = inst_key_init_done[gi_crypto] || (sm4_state != SM4_IDLE);
            assign sm4_user_key_valid = (sm4_state == SM4_KEY_EXP);
            assign sm4_valid_in = (sm4_state == SM4_ENCRYPT);
            assign sm4_encdec_en = inst_key_init_done[gi_crypto] || (sm4_state != SM4_IDLE);
            
            aes_core u_aes (
                .clk(clk),
                .reset_n(rst_n),
                .encdec(encdec_reg),
                .init(aes_init),
                .next(aes_next),
                .ready(aes_ready),
                .key(aes256_reg ? key_active : {key_active[127:0], 128'd0}),
                .keylen(aes256_reg),
                .block(inst_plaintext[gi_crypto]),
                .result(aes_result),
                .result_valid(aes_result_valid)
            );
            
            sm4_top u_sm4 (
                .clk(clk),
                .reset_n(rst_n),
                .sm4_enable_in(1'b1),
                .encdec_enable_in(sm4_encdec_en),
                .encdec_sel_in(~encdec_reg),
                .valid_in(sm4_valid_in),
                .data_in(inst_plaintext[gi_crypto]),
                .enable_key_exp_in(sm4_key_exp_en),
                .user_key_valid_in(sm4_user_key_valid),
                .user_key_in(key_active[127:0]),
                .key_exp_ready_out(sm4_key_ready),
                .ready_out(sm4_ready),
                .result_out(sm4_result)
            );
            
            always_comb begin
                if (algo_reg == 1'b0) begin
                    inst_ready[gi_crypto] = (aes_state == AES_IDLE);
                    inst_result_valid[gi_crypto] = aes_result_valid && (aes_state == AES_WAIT_DONE);
                    inst_result[gi_crypto] = aes_result;
                end else begin
                    inst_ready[gi_crypto] = (sm4_state == SM4_IDLE);
                    inst_result_valid[gi_crypto] = sm4_busy_seen && sm4_ready && (sm4_state == SM4_WAIT_NEXT);
                    inst_result[gi_crypto] = sm4_result;
                end
            end
        end
    endgenerate
    
    integer i_rob;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i_rob = 0; i_rob < ROB_DEPTH; i_rob++) begin
                rob_valid[i_rob] <= 1'b0;
                rob_data[i_rob] <= 128'd0;
            end
        end else begin
            // 先清除读出的 ROB 项
            if (mid_fifo_wr_en) begin
                rob_valid[output_seq_expected[ROB_PTR_WIDTH-1:0]] <= 1'b0;
            end
            
            // 后写入完成的结果 (SystemVerilog: 同一 always_ff 内后赋值覆盖先赋值, 写入优先)
            for (i_rob = 0; i_rob < NUM_INSTANCES; i_rob++) begin
                if (inst_result_valid[i_rob] && inst_busy[i_rob]) begin
                    rob_valid[inst_seq_num[i_rob][ROB_PTR_WIDTH-1:0]] <= 1'b1;
                    rob_data[inst_seq_num[i_rob][ROB_PTR_WIDTH-1:0]] <= inst_result[i_rob];
                end
            end
        end
    end
    
    logic rob_ready_to_pop;
    assign rob_ready_to_pop = rob_valid[output_seq_expected[ROB_PTR_WIDTH-1:0]];
    
    assign mid_fifo_wr_en = rob_ready_to_pop && !mid_fifo_full;
    assign mid_fifo_din = rob_data[output_seq_expected[ROB_PTR_WIDTH-1:0]];
    
    sync_fifo #(.WIDTH(128), .DEPTH(16)) u_mid_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(mid_fifo_wr_en),
        .din(mid_fifo_din),
        .full(mid_fifo_full),
        .rd_en(mid_fifo_rd_en),
        .dout(mid_fifo_dout),
        .empty(mid_fifo_empty)
    );
    
    assign mid_fifo_rd_en = !mid_fifo_empty && gb_din_ready;
    assign gb_din_valid = !mid_fifo_empty;
    
    gearbox_128_to_32 u_gearbox (
        .clk(clk),
        .rst_n(rst_n),
        .din(mid_fifo_dout),
        .din_valid(gb_din_valid),
        .din_ready(gb_din_ready),
        .dout(gb_dout),
        .dout_valid(gb_dout_valid),
        .dout_last(gb_dout_last),
        .dout_ready(gb_dout_ready)
    );
    
    sync_fifo #(.WIDTH(33), .DEPTH(16)) u_out_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(gb_dout_valid),
        .din({gb_dout_last, gb_dout}),
        .full(out_fifo_full),
        .rd_en(i_tx_rd_en),
        .dout(out_fifo_dout),
        .empty(o_tx_empty)
    );
    
    assign gb_dout_ready = !out_fifo_full;
    assign o_tx_last = out_fifo_dout[32];
    assign o_tx_data = out_fifo_dout[31:0];
    
    assign o_system_ready = (|inst_available) && !mid_fifo_full && !out_fifo_full;

endmodule
