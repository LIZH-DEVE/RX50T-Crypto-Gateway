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

    localparam [1:0] ST_RX_GATHER  = 2'd0;
    localparam [1:0] ST_ENCRYPT    = 2'd1;
    localparam [1:0] ST_TX_SCATTER = 2'd2;

    localparam integer BLOCK_BYTES = 16;
    localparam integer MAX_BYTES   = 64;
    localparam integer MAX_BLOCKS  = 4;

    localparam [2:0] AES_BOOT_INIT      = 3'd0;
    localparam [2:0] AES_BOOT_WAIT_BUSY = 3'd1;
    localparam [2:0] AES_BOOT_WAIT_RDY  = 3'd2;
    localparam [2:0] AES_IDLE           = 3'd3;
    localparam [2:0] AES_RUN_PULSE      = 3'd4;
    localparam [2:0] AES_RUN_WAIT_BUSY  = 3'd5;
    localparam [2:0] AES_RUN_WAIT_DONE  = 3'd6;

    reg [1:0]   state_q;
    reg [511:0] gather_shift_q;
    reg [6:0]   gather_count_q;
    reg [511:0] frame_data_q;
    reg [511:0] result_shift_q;
    reg [511:0] tx_shift_q;
    reg [6:0]   tx_count_q;
    reg [2:0]   block_count_q;
    reg [2:0]   block_index_q;
    reg [127:0] crypto_block_q;
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

    function automatic [127:0] block_from_frame(
        input [511:0] frame,
        input [2:0]   idx
    );
        begin
            case (idx)
                3'd0: block_from_frame = frame[511:384];
                3'd1: block_from_frame = frame[383:256];
                3'd2: block_from_frame = frame[255:128];
                3'd3: block_from_frame = frame[127:0];
                default: block_from_frame = 128'd0;
            endcase
        end
    endfunction

    function automatic [511:0] store_block_into_frame(
        input [511:0] frame,
        input [2:0]   idx,
        input [127:0] block
    );
        begin
            store_block_into_frame = frame;
            case (idx)
                3'd0: store_block_into_frame[511:384] = block;
                3'd1: store_block_into_frame[383:256] = block;
                3'd2: store_block_into_frame[255:128] = block;
                3'd3: store_block_into_frame[127:0]   = block;
                default: begin
                end
            endcase
        end
    endfunction

    assign sm4_valid_in =
        (state_q == ST_ENCRYPT) &&
        (active_algo_q == ALG_SM4) &&
        sm4_start_seen_q &&
        (sm4_valid_burst_q != 3'd0);

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
        .encdec_enable_in  ((state_q == ST_ENCRYPT) && (active_algo_q == ALG_SM4)),
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

    always @(posedge clk or negedge rst_n) begin
        reg [511:0] next_shift;
        reg [511:0] aligned_frame;
        reg [511:0] next_result_shift;
        reg [6:0]   next_count;
        reg [2:0]   next_block_count;
        if (!rst_n) begin
            state_q              <= ST_RX_GATHER;
            gather_shift_q       <= 512'd0;
            gather_count_q       <= 7'd0;
            frame_data_q         <= 512'd0;
            result_shift_q       <= 512'd0;
            tx_shift_q           <= 512'd0;
            tx_count_q           <= 7'd0;
            block_count_q        <= 3'd0;
            block_index_q        <= 3'd0;
            crypto_block_q       <= 128'd0;
            active_algo_q        <= ALG_SM4;
            sm4_key_sent_q       <= 1'b0;
            sm4_user_key_valid_q <= 1'b0;
            sm4_start_seen_q     <= 1'b0;
            sm4_wait_done_clear_q<= 1'b0;
            sm4_valid_burst_q    <= 3'd0;
            aes_state_q          <= AES_BOOT_INIT;
            aes_init_q           <= 1'b0;
            aes_next_q           <= 1'b0;
            bridge_valid         <= 1'b0;
            bridge_data          <= 8'd0;
            bridge_last          <= 1'b0;
        end else begin
            sm4_user_key_valid_q <= 1'b0;
            aes_init_q           <= 1'b0;
            aes_next_q           <= 1'b0;

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
                    if ((state_q == ST_ENCRYPT) && (active_algo_q == ALG_AES)) begin
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

            case (state_q)
                ST_RX_GATHER: begin
                    bridge_valid      <= 1'b0;
                    bridge_data       <= 8'd0;
                    bridge_last       <= 1'b0;
                    active_algo_q     <= ALG_SM4;
                    sm4_start_seen_q  <= 1'b0;
                    sm4_wait_done_clear_q <= 1'b0;
                    sm4_valid_burst_q <= 3'd0;

                    if (acl_valid) begin
                        next_shift = {gather_shift_q[503:0], acl_data};
                        next_count = gather_count_q + 7'd1;

                        if (next_count <= MAX_BYTES) begin
                            if (acl_last && ((next_count < BLOCK_BYTES) || ((next_count % BLOCK_BYTES) != 0))) begin
                                tx_shift_q     <= next_shift << ((MAX_BYTES - next_count) * 8);
                                tx_count_q     <= next_count;
                                gather_shift_q <= 512'd0;
                                gather_count_q <= 7'd0;
                                state_q        <= ST_TX_SCATTER;
                            end else if (acl_last && ((next_count % BLOCK_BYTES) == 0)) begin
                                aligned_frame    = next_shift << ((MAX_BYTES - next_count) * 8);
                                next_block_count = next_count / BLOCK_BYTES;
                                active_algo_q    <= i_algo_sel;
                                frame_data_q     <= aligned_frame;
                                result_shift_q   <= 512'd0;
                                block_count_q    <= next_block_count;
                                block_index_q    <= 3'd0;
                                crypto_block_q   <= aligned_frame[511:384];
                                gather_shift_q   <= 512'd0;
                                gather_count_q   <= 7'd0;
                                state_q          <= ST_ENCRYPT;
                            end else begin
                                gather_shift_q <= next_shift;
                                gather_count_q <= next_count;
                            end
                        end
                    end
                end

                ST_ENCRYPT: begin
                    bridge_valid <= 1'b0;
                    bridge_data  <= 8'd0;
                    bridge_last  <= 1'b0;

                    if (active_algo_q == ALG_SM4) begin
                        if (sm4_wait_done_clear_q) begin
                            if (!sm4_done) begin
                                sm4_wait_done_clear_q <= 1'b0;
                            end
                        end else if (sm4_key_ready && !sm4_start_seen_q) begin
                            sm4_start_seen_q  <= 1'b1;
                            sm4_valid_burst_q <= 3'd4;
                        end else if (sm4_valid_burst_q != 3'd0) begin
                            sm4_valid_burst_q <= sm4_valid_burst_q - 3'd1;
                        end

                        if (sm4_done) begin
                            next_result_shift = store_block_into_frame(result_shift_q, block_index_q, sm4_result);
                            result_shift_q <= next_result_shift;

                            sm4_start_seen_q  <= 1'b0;
                            sm4_valid_burst_q <= 3'd0;

                            if ((block_index_q + 3'd1) < block_count_q) begin
                                block_index_q         <= block_index_q + 3'd1;
                                crypto_block_q        <= block_from_frame(frame_data_q, block_index_q + 3'd1);
                                sm4_wait_done_clear_q <= 1'b1;
                            end else begin
                                tx_shift_q <= next_result_shift;
                                tx_count_q <= block_count_q * BLOCK_BYTES;
                                state_q    <= ST_TX_SCATTER;
                            end
                        end
                    end else begin
                        sm4_start_seen_q      <= 1'b0;
                        sm4_wait_done_clear_q <= 1'b0;
                        sm4_valid_burst_q     <= 3'd0;

                        if (aes_result_valid && (aes_state_q == AES_RUN_WAIT_DONE)) begin
                            next_result_shift = store_block_into_frame(result_shift_q, block_index_q, aes_result);
                            result_shift_q <= next_result_shift;

                            if ((block_index_q + 3'd1) < block_count_q) begin
                                block_index_q  <= block_index_q + 3'd1;
                                crypto_block_q <= block_from_frame(frame_data_q, block_index_q + 3'd1);
                            end else begin
                                tx_shift_q <= next_result_shift;
                                tx_count_q <= block_count_q * BLOCK_BYTES;
                                state_q    <= ST_TX_SCATTER;
                            end
                        end
                    end
                end

                ST_TX_SCATTER: begin
                    if (!bridge_valid && (tx_count_q != 7'd0)) begin
                        bridge_valid <= 1'b1;
                        bridge_data  <= tx_shift_q[511:504];
                        bridge_last  <= (tx_count_q == 7'd1);
                    end else if (bridge_valid && uart_tx_ready) begin
                        bridge_valid <= 1'b0;
                        tx_shift_q   <= {tx_shift_q[503:0], 8'h00};
                        tx_count_q   <= tx_count_q - 7'd1;

                        if (tx_count_q == 7'd1) begin
                            bridge_data   <= 8'd0;
                            bridge_last   <= 1'b0;
                            frame_data_q  <= 512'd0;
                            result_shift_q<= 512'd0;
                            block_count_q <= 3'd0;
                            block_index_q <= 3'd0;
                            state_q       <= ST_RX_GATHER;
                        end
                    end
                end

                default: begin
                    state_q <= ST_RX_GATHER;
                end
            endcase
        end
    end

endmodule
