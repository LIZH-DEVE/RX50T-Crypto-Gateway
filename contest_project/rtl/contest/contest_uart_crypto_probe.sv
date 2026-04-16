`timescale 1ns/1ps

module contest_uart_crypto_probe #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 2_000_000,
    parameter integer BENCH_TOTAL_BYTES_P = 1_048_576,
    parameter integer BENCH_TIMEOUT_CLKS_P = 16_777_215
) (
    input  wire i_clk,
    input  wire i_rst_n,
    input  wire i_uart_rx,
    output wire o_uart_tx
);

    localparam [7:0] ASCII_CFG_ACK = 8'h43;
    localparam [7:0] ASCII_CFG_OP  = 8'h12;
    localparam [7:0] ASCII_ERROR   = 8'h45;
    localparam [7:0] ASCII_KEYMAP  = 8'h4B;
    localparam [7:0] ASCII_NL      = 8'h0A;
    localparam [7:0] ASCII_PMU_CLR = 8'h4A;
    localparam [7:0] ASCII_PMU_QRY = 8'h50;
    localparam [7:0] ASCII_QUERY   = 8'h3F;
    localparam [7:0] ASCII_RULE    = 8'h48;
    localparam [7:0] ASCII_STAT    = 8'h53;
    localparam [7:0] ASCII_BENCH   = 8'h62;
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
    localparam [31:0] BENCH_TOTAL_BYTES   = BENCH_TOTAL_BYTES_P[31:0];
    localparam [23:0] BENCH_TIMEOUT_CLKS  = BENCH_TIMEOUT_CLKS_P[23:0];

    localparam [7:0] STREAM_ERR_FORMAT = 8'h01;
    localparam [7:0] STREAM_ERR_STATE  = 8'h02;
    localparam [7:0] STREAM_ERR_SEQ    = 8'h03;
    localparam [7:0] STREAM_ERR_WINDOW = 8'h04;

    localparam [7:0] BENCH_SCHEMA_VER  = 8'h01;
    localparam [7:0] BENCH_STATUS_OK        = 8'h00;
    localparam [7:0] BENCH_STATUS_BUSY      = 8'h01;
    localparam [7:0] BENCH_STATUS_TIMEOUT   = 8'h02;
    localparam [7:0] BENCH_STATUS_INTERNAL  = 8'h03;
    localparam [7:0] BENCH_STATUS_NO_RESULT = 8'h04;

    localparam [2:0] TX_OWNER_NONE   = 3'd0;
    localparam [2:0] TX_OWNER_PMU    = 3'd1;
    localparam [2:0] TX_OWNER_STREAM = 3'd2;
    localparam [2:0] TX_OWNER_BENCH  = 3'd3;
    localparam [2:0] TX_OWNER_CTRL   = 3'd4;
    localparam [2:0] TX_OWNER_AXIS   = 3'd5;
    localparam [2:0] TX_OWNER_FATAL  = 3'd6;

    localparam [7:0] FATAL_STREAM_WATCHDOG = 8'h01;
    localparam [7:0] FATAL_CRYPTO_WATCHDOG = 8'h02;
    localparam integer STREAM_WDG_TIMEOUT = CLK_HZ;
    localparam integer CRYPTO_WDG_TIMEOUT = CLK_HZ / 20;
    localparam [2:0] QUIESCE_CYCLES = 3'd4;
    localparam [4:0] CRYPTO_SLEEP_HOLDOFF = 5'd16;
    localparam [1:0] CRYPTO_WAKE_SETTLE_CYCLES = 2'd2;

    localparam [2:0] BENCH_IDLE       = 3'd0;
    localparam [2:0] BENCH_PICK_HEAD  = 3'd1;
    localparam [2:0] BENCH_ARM        = 3'd2;
    localparam [2:0] BENCH_RUN        = 3'd3;
    localparam [2:0] BENCH_DRAIN_CRC  = 3'd4;
    localparam [2:0] BENCH_LATCH      = 3'd5;
    localparam [2:0] BENCH_TX_RESULT  = 3'd6;

    localparam [2:0] STREAM_TX_NONE       = 3'd0;
    localparam [2:0] STREAM_TX_CAP        = 3'd1;
    localparam [2:0] STREAM_TX_START_ACK  = 3'd2;
    localparam [2:0] STREAM_TX_BLOCK      = 3'd3;
    localparam [2:0] STREAM_TX_ERROR      = 3'd4;
    localparam [2:0] STREAM_TX_CIPHER_HDR = 3'd5;
    localparam [1:0] PMU_TX_NONE          = 2'd0;
    localparam [1:0] PMU_TX_SNAPSHOT      = 2'd1;
    localparam [1:0] PMU_TX_CLEAR_ACK     = 2'd2;
    localparam [2:0] CTRL_TX_NONE         = 3'd0;
    localparam [2:0] CTRL_TX_ERROR        = 3'd1;
    localparam [2:0] CTRL_TX_BLOCK        = 3'd2;
    localparam [2:0] CTRL_TX_CFG_ACK      = 3'd3;
    localparam [2:0] CTRL_TX_KEYMAP       = 3'd4;
    localparam [2:0] CTRL_TX_RULE_STATS   = 3'd5;
    localparam [2:0] CTRL_TX_STATS        = 3'd6;
    localparam [2:0] CTRL_TX_HIT_STATS    = 3'd7;

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

    function automatic [7:0] acl_v2_cfg_ack_byte(input [4:0] idx, input [2:0] slot, input [127:0] key);
        begin
            case (idx)
                5'd0: acl_v2_cfg_ack_byte = 8'h55;
                5'd1: acl_v2_cfg_ack_byte = 8'h12;
                5'd2: acl_v2_cfg_ack_byte = ASCII_CFG_ACK;
                5'd3: acl_v2_cfg_ack_byte = {5'd0, slot};
                5'd4: acl_v2_cfg_ack_byte = key[127:120];
                5'd5: acl_v2_cfg_ack_byte = key[119:112];
                5'd6: acl_v2_cfg_ack_byte = key[111:104];
                5'd7: acl_v2_cfg_ack_byte = key[103:96];
                5'd8: acl_v2_cfg_ack_byte = key[95:88];
                5'd9: acl_v2_cfg_ack_byte = key[87:80];
                5'd10: acl_v2_cfg_ack_byte = key[79:72];
                5'd11: acl_v2_cfg_ack_byte = key[71:64];
                5'd12: acl_v2_cfg_ack_byte = key[63:56];
                5'd13: acl_v2_cfg_ack_byte = key[55:48];
                5'd14: acl_v2_cfg_ack_byte = key[47:40];
                5'd15: acl_v2_cfg_ack_byte = key[39:32];
                5'd16: acl_v2_cfg_ack_byte = key[31:24];
                5'd17: acl_v2_cfg_ack_byte = key[23:16];
                5'd18: acl_v2_cfg_ack_byte = key[15:8];
                5'd19: acl_v2_cfg_ack_byte = key[7:0];
                default: acl_v2_cfg_ack_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [7:0] acl_v2_keymap_byte(input [7:0] idx, input [1023:0] keys_flat);
        integer slot_idx;
        integer byte_idx;
        integer byte_off;
        begin
            if (idx == 8'd0) begin
                acl_v2_keymap_byte = 8'h55;
            end else if (idx == 8'd1) begin
                acl_v2_keymap_byte = 8'h81;
            end else if (idx == 8'd2) begin
                acl_v2_keymap_byte = ASCII_KEYMAP;
            end else if (idx <= 8'd130) begin
                byte_idx = idx - 8'd3;
                slot_idx = byte_idx / 16;
                byte_off = byte_idx % 16;
                acl_v2_keymap_byte = keys_flat[(slot_idx * 128) + 127 - (byte_off * 8) -: 8];
            end else begin
                acl_v2_keymap_byte = 8'h00;
            end
        end
    endfunction

    function automatic [7:0] acl_v2_hits_byte(input [5:0] idx, input [255:0] hits_flat);
        integer ctr_idx;
        integer byte_off;
        integer flat_idx;
        begin
            if (idx == 6'd0) begin
                acl_v2_hits_byte = 8'h55;
            end else if (idx == 6'd1) begin
                acl_v2_hits_byte = 8'h21;
            end else if (idx == 6'd2) begin
                acl_v2_hits_byte = ASCII_RULE;
            end else if (idx <= 6'd34) begin
                flat_idx = idx - 6'd3;
                ctr_idx = flat_idx / 4;
                byte_off = flat_idx % 4;
                acl_v2_hits_byte = hits_flat[(ctr_idx * 32) + 31 - (byte_off * 8) -: 8];
            end else begin
                acl_v2_hits_byte = 8'h00;
            end
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
        input [6:0]  idx,
        input [63:0] global_cycles,
        input [63:0] crypto_active_cycles,
        input [63:0] uart_tx_stall_cycles,
        input [63:0] credit_block_cycles,
        input [63:0] acl_block_events,
        input [63:0] stream_bytes_in,
        input [63:0] stream_bytes_out,
        input [63:0] stream_chunk_count,
        input [63:0] crypto_clock_gated_cycles,
        input [63:0] crypto_clock_status_flags
    );
        begin
            case (kind)
                PMU_TX_CLEAR_ACK: begin
                    case (idx)
                        7'd0: pmu_tx_byte = 8'h55;
                        7'd1: pmu_tx_byte = 8'h02;
                        7'd2: pmu_tx_byte = ASCII_PMU_CLR;
                        default: pmu_tx_byte = 8'h00;
                    endcase
                end
                PMU_TX_SNAPSHOT: begin
                    case (idx)
                        7'd0: pmu_tx_byte = 8'h55;
                        7'd1: pmu_tx_byte = 8'h56;
                        7'd2: pmu_tx_byte = ASCII_PMU_QRY;
                        7'd3: pmu_tx_byte = 8'h03;
                        7'd4,
                        7'd5,
                        7'd6,
                        7'd7: pmu_tx_byte = be32_byte(idx[1:0], PMU_CLK_HZ);
                        7'd8,
                        7'd9,
                        7'd10,
                        7'd11,
                        7'd12,
                        7'd13,
                        7'd14,
                        7'd15: pmu_tx_byte = be64_byte(idx[2:0], global_cycles);
                        7'd16,
                        7'd17,
                        7'd18,
                        7'd19,
                        7'd20,
                        7'd21,
                        7'd22,
                        7'd23: pmu_tx_byte = be64_byte(idx[2:0], crypto_active_cycles);
                        7'd24,
                        7'd25,
                        7'd26,
                        7'd27,
                        7'd28,
                        7'd29,
                        7'd30,
                        7'd31: pmu_tx_byte = be64_byte(idx[2:0], uart_tx_stall_cycles);
                        7'd32,
                        7'd33,
                        7'd34,
                        7'd35,
                        7'd36,
                        7'd37,
                        7'd38,
                        7'd39: pmu_tx_byte = be64_byte(idx[2:0], credit_block_cycles);
                        7'd40,
                        7'd41,
                        7'd42,
                        7'd43,
                        7'd44,
                        7'd45,
                        7'd46,
                        7'd47: pmu_tx_byte = be64_byte(idx[2:0], acl_block_events);
                        7'd48,
                        7'd49,
                        7'd50,
                        7'd51,
                        7'd52,
                        7'd53,
                        7'd54,
                        7'd55: pmu_tx_byte = be64_byte(idx[2:0], stream_bytes_in);
                        7'd56,
                        7'd57,
                        7'd58,
                        7'd59,
                        7'd60,
                        7'd61,
                        7'd62,
                        7'd63: pmu_tx_byte = be64_byte(idx[2:0], stream_bytes_out);
                        7'd64,
                        7'd65,
                        7'd66,
                        7'd67,
                        7'd68,
                        7'd69,
                        7'd70,
                        7'd71: pmu_tx_byte = be64_byte(idx[2:0], stream_chunk_count);
                        7'd72,
                        7'd73,
                        7'd74,
                        7'd75,
                        7'd76,
                        7'd77,
                        7'd78,
                        7'd79: pmu_tx_byte = be64_byte(idx[2:0], crypto_clock_gated_cycles);
                        7'd80,
                        7'd81,
                        7'd82,
                        7'd83,
                        7'd84,
                        7'd85,
                        7'd86,
                        7'd87: pmu_tx_byte = be64_byte(idx[2:0], crypto_clock_status_flags);
                        default: pmu_tx_byte = 8'h00;
                    endcase
                end
                default: pmu_tx_byte = 8'h00;
            endcase
        end
    endfunction

    function automatic [6:0] pmu_tx_last_idx(input [1:0] kind);
        begin
            case (kind)
                PMU_TX_SNAPSHOT:  pmu_tx_last_idx = 7'd87;
                PMU_TX_CLEAR_ACK: pmu_tx_last_idx = 7'd3;
                default:          pmu_tx_last_idx = 7'd0;
            endcase
        end
    endfunction

    function automatic [7:0] fatal_tx_byte(input [1:0] idx, input [7:0] code);
        begin
            case (idx)
                2'd0: fatal_tx_byte = 8'h55;
                2'd1: fatal_tx_byte = 8'h02;
                2'd2: fatal_tx_byte = 8'hEE;
                default: fatal_tx_byte = code;
            endcase
        end
    endfunction

    function automatic [1:0] fatal_tx_last_idx(input [7:0] code);
        begin
            fatal_tx_last_idx = 2'd3;
        end
    endfunction

    function automatic [127:0] bench_candidate_prefix(input [3:0] idx);
        begin
            case (idx)
                4'd0: bench_candidate_prefix = 128'h00000000000000000000000000000000;
                4'd1: bench_candidate_prefix = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
                4'd2: bench_candidate_prefix = 128'h11111111111111112222222222222222;
                4'd3: bench_candidate_prefix = 128'h33333333333333334444444444444444;
                4'd4: bench_candidate_prefix = 128'h55555555555555556666666666666666;
                4'd5: bench_candidate_prefix = 128'h77777777777777778888888888888888;
                4'd6: bench_candidate_prefix = 128'h9999999999999999AAAAAAAAAAAAAAAA;
                4'd7: bench_candidate_prefix = 128'hBBBBBBBBBBBBBBBBCCCCCCCCCCCCCCCC;
                4'd8: bench_candidate_prefix = 128'hDDDDDDDDEEEEEEEEFFFFFFFFFFFFFFFF;
                4'd9: bench_candidate_prefix = 128'h0123456789ABCDEF0123456789ABCDEF;
                4'd10: bench_candidate_prefix = 128'hFEDCBA9876543210FEDCBA9876543210;
                4'd11: bench_candidate_prefix = 128'hAAAAAAAA5555555555555555AAAAAAAA;
                4'd12: bench_candidate_prefix = 128'h123456789ABCDEF123456789ABCDEF12;
                4'd13: bench_candidate_prefix = 128'hDEADBEEFCAFEBABEDECAFFEE0BADF00D;
                4'd14: bench_candidate_prefix = 128'hFEEEFEEEFEEEFEEEFEEEFEEEFEEEFEEE;
                default: bench_candidate_prefix = 128'h0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C0C;
            endcase
        end
    endfunction

    function automatic [7:0] bench_prefix_byte(input [127:0] prefix, input [3:0] idx);
        reg [127:0] shifted;
        begin
            shifted = prefix >> ((4'd15 - idx) * 8);
            bench_prefix_byte = shifted[7:0];
        end
    endfunction

    function automatic [7:0] bench_lfsr_next(input [7:0] state);
        begin
            bench_lfsr_next = {state[6:0], 1'b0};
            if (state[7]) begin
                bench_lfsr_next = ({state[6:0], 1'b0} ^ 8'h1D);
            end
        end
    endfunction

    function automatic [31:0] bench_crc32_next(input [31:0] crc_in, input [7:0] data_in);
        reg [31:0] crc;
        integer bit_idx;
        begin
            crc = crc_in ^ {24'd0, data_in};
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                if (crc[0]) begin
                    crc = (crc >> 1) ^ 32'hEDB8_8320;
                end else begin
                    crc = (crc >> 1);
                end
            end
            bench_crc32_next = crc;
        end
    endfunction

    function automatic [7:0] bench_tx_byte(
        input [4:0] idx,
        input [7:0] status,
        input       algo,
        input [31:0] byte_count,
        input [63:0] cycle_count,
        input [31:0] crc32
    );
        begin
            case (idx)
                5'd0: bench_tx_byte = 8'h55;
                5'd1: bench_tx_byte = 8'h14;
                5'd2: bench_tx_byte = ASCII_BENCH;
                5'd3: bench_tx_byte = BENCH_SCHEMA_VER;
                5'd4: bench_tx_byte = status;
                5'd5: bench_tx_byte = algo ? MODE_AES : MODE_SM4;
                5'd6: bench_tx_byte = be32_byte(2'd0, byte_count);
                5'd7: bench_tx_byte = be32_byte(2'd1, byte_count);
                5'd8: bench_tx_byte = be32_byte(2'd2, byte_count);
                5'd9: bench_tx_byte = be32_byte(2'd3, byte_count);
                5'd10: bench_tx_byte = be64_byte(3'd0, cycle_count);
                5'd11: bench_tx_byte = be64_byte(3'd1, cycle_count);
                5'd12: bench_tx_byte = be64_byte(3'd2, cycle_count);
                5'd13: bench_tx_byte = be64_byte(3'd3, cycle_count);
                5'd14: bench_tx_byte = be64_byte(3'd4, cycle_count);
                5'd15: bench_tx_byte = be64_byte(3'd5, cycle_count);
                5'd16: bench_tx_byte = be64_byte(3'd6, cycle_count);
                5'd17: bench_tx_byte = be64_byte(3'd7, cycle_count);
                5'd18: bench_tx_byte = be32_byte(2'd0, crc32);
                5'd19: bench_tx_byte = be32_byte(2'd1, crc32);
                5'd20: bench_tx_byte = be32_byte(2'd2, crc32);
                default: bench_tx_byte = be32_byte(2'd3, crc32);
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
    wire       parser_in_frame_w;
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
    reg        frame_bench_query_q;
    reg        frame_bench_start_q;
    reg        frame_bench_force_q;
    reg        frame_bench_force_seen_q;
    reg        frame_bench_algo_valid_q;
    reg        frame_bench_algo_q;
    reg        frame_cfg_q;
    reg  [7:0] frame_cfg_index_q;
    reg  [127:0] frame_cfg_key_q;
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
    reg        acl_in_valid_q;
    reg  [7:0] acl_in_data_q;
    reg        acl_in_last_q;
    reg        axis_in_pending_valid_q;
    reg  [7:0] axis_in_pending_data_q;
    reg        axis_in_pending_last_q;
    reg  [0:0] axis_in_pending_user_q;
    reg        axis_in_pending_clear_q;
    reg        axis_soft_reset_q;

    wire       axis_in_tready_w;
    wire       axis_out_tvalid_w;
    wire [7:0] axis_out_tdata_w;
    wire       axis_out_tlast_w;
    wire       axis_out_tready_w;
    wire       axis_acl_block_pulse_w;
    wire       axis_acl_block_slot_valid_w;
    wire [2:0] axis_acl_block_slot_w;
    wire       acl_cfg_busy;
    wire       acl_cfg_done;
    wire       acl_cfg_error;
    wire [1023:0] acl_rule_keys_flat;
    wire [255:0] acl_rule_counts_flat;

    reg        acl_cfg_valid_q;
    reg  [2:0] acl_cfg_index_q;
    reg  [127:0] acl_cfg_key_q;
    reg        acl_cfg_pending_q;
    reg  [2:0] acl_cfg_pending_index_q;
    reg  [127:0] acl_cfg_pending_key_q;
    reg  [2:0] pending_cfg_ack_idx_q;
    reg  [127:0] pending_cfg_ack_key_q;
    reg        pending_error_q;
    reg        pending_block_q;
    reg        pending_cfg_ack_q;
    reg        pending_stats_q;
    reg  [7:0] pending_stats_total_q;
    reg  [7:0] pending_stats_acl_q;
    reg  [7:0] pending_stats_aes_q;
    reg  [7:0] pending_stats_sm4_q;
    reg  [7:0] pending_stats_err_q;
    reg        pending_rule_stats_q;
    reg [63:0] pending_rule_stats_flat_q;
    reg        pending_hit_stats_q;
    reg [255:0] pending_hit_stats_flat_q;
    reg        pending_keymap_q;
    reg [1023:0] pending_keymap_flat_q;
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
    reg  [2:0] stream_pending_kind_q;
    reg  [7:0] stream_pending_seq_q;
    reg  [2:0] stream_pending_slot_q;
    reg  [7:0] stream_pending_code_q;
    reg        pmu_armed_q;
    reg [63:0] pmu_global_cycles_q;
    reg [63:0] pmu_crypto_active_cycles_q;
    reg [63:0] pmu_uart_tx_stall_cycles_q;
    reg [63:0] pmu_stream_credit_block_cycles_q;
    reg [63:0] pmu_acl_block_events_q;
    reg [63:0] pmu_stream_bytes_in_q;
    reg [63:0] pmu_stream_bytes_out_q;
    reg [63:0] pmu_stream_chunk_count_q;
    reg [63:0] pmu_crypto_clock_gated_cycles_q;
    reg [63:0] pmu_snap_global_cycles_q;
    reg [63:0] pmu_snap_crypto_active_cycles_q;
    reg [63:0] pmu_snap_uart_tx_stall_cycles_q;
    reg [63:0] pmu_snap_stream_credit_block_cycles_q;
    reg [63:0] pmu_snap_acl_block_events_q;
    reg [63:0] pmu_snap_stream_bytes_in_q;
    reg [63:0] pmu_snap_stream_bytes_out_q;
    reg [63:0] pmu_snap_stream_chunk_count_q;
    reg [63:0] pmu_snap_crypto_clock_gated_cycles_q;
    reg [63:0] pmu_snap_crypto_clock_status_flags_q;
    reg        pmu_pending_q;
    reg  [1:0] pmu_pending_kind_q;
    reg  [1:0] pmu_tx_kind_q;
    reg  [6:0] pmu_tx_idx_q;
    reg [63:0] pmu_tx_global_cycles_q;
    reg [63:0] pmu_tx_crypto_active_cycles_q;
    reg [63:0] pmu_tx_uart_tx_stall_cycles_q;
    reg [63:0] pmu_tx_stream_credit_block_cycles_q;
    reg [63:0] pmu_tx_acl_block_events_q;
    reg [63:0] pmu_tx_stream_bytes_in_q;
    reg [63:0] pmu_tx_stream_bytes_out_q;
    reg [63:0] pmu_tx_stream_chunk_count_q;
    reg [63:0] pmu_tx_crypto_clock_gated_cycles_q;
    reg [63:0] pmu_tx_crypto_clock_status_flags_q;
    reg  [2:0] bench_state_q;
    reg  [4:0] bench_tx_idx_q;
    reg  [3:0] bench_pick_idx_q;
    reg        bench_algo_q;
    reg [31:0] bench_bytes_in_q;
    reg [31:0] bench_bytes_out_q;
    reg [63:0] bench_cycles_q;
    reg [23:0] bench_watchdog_q;
    reg  [7:0] bench_latch_status_q;
    reg  [127:0] bench_safe_head_prefix_q;
    reg  [7:0] bench_lfsr_q;
    reg [31:0] bench_crc32_q;
    reg        bench_result_valid_q;
    reg        bench_last_algo_q;
    reg  [7:0] bench_last_status_q;
    reg [31:0] bench_last_bytes_q;
    reg [63:0] bench_last_cycles_q;
    reg [31:0] bench_last_crc32_q;
    reg        bench_pending_q;
    reg        bench_pending_algo_q;
    reg  [7:0] bench_pending_status_q;
    reg [31:0] bench_pending_bytes_q;
    reg [63:0] bench_pending_cycles_q;
    reg [31:0] bench_pending_crc32_q;
    reg        bench_tx_active_q;
    reg        bench_tx_algo_q;
    reg  [7:0] bench_tx_status_q;
    reg [31:0] bench_tx_bytes_q;
    reg [63:0] bench_tx_cycles_q;
    reg [31:0] bench_tx_crc32_q;
    reg  [2:0] ctrl_tx_kind_q;
    reg  [7:0] ctrl_tx_idx_q;
    reg  [2:0] tx_owner_q;
    reg  [7:0] ctrl_tx_cfg_ack_idx_q;
    reg [127:0] ctrl_tx_cfg_ack_key_q;
    reg  [7:0] ctrl_tx_stats_total_q;
    reg  [7:0] ctrl_tx_stats_acl_q;
    reg  [7:0] ctrl_tx_stats_aes_q;
    reg  [7:0] ctrl_tx_stats_sm4_q;
    reg  [7:0] ctrl_tx_stats_err_q;
    reg [63:0] ctrl_tx_rule_stats_flat_q;
    reg [255:0] ctrl_tx_hit_stats_flat_q;
    reg [1023:0] ctrl_tx_keymap_flat_q;
    reg        crc_pipe_valid_q;
    reg        crc_pipe_last_q;
    reg  [7:0] crc_pipe_data_q;

    wire       pmu_crypto_active_w;
    wire       tx_ready;
    wire       pmu_tx_active_w;
    wire [7:0] pmu_tx_data_w;
    wire       stream_tx_active_w;
    wire [7:0] stream_tx_data_w;
    wire       bench_tx_active_w;
    wire [7:0] bench_tx_data_w;
    reg  [7:0] ctrl_tx_data_r;
    reg        ctrl_tx_last_r;
    reg        fatal_pending_q;
    reg  [7:0] fatal_code_q;
    reg  [2:0] quiesce_count_q;
    reg        quiesce_active_q;
    reg        drain_committed_q;
    reg [31:0] stream_wdg_counter_q;
    reg [31:0] crypto_wdg_counter_q;
    reg        fatal_tx_active_q;
    reg  [1:0] fatal_tx_idx_q;
    reg        crypto_wake_req_q;
    reg        crypto_clk_ce_q;
    reg        crypto_clock_gated_q;
    reg  [4:0] crypto_sleep_count_q;
    reg  [1:0] crypto_wake_settle_count_q;
    reg        crypto_idle_sync1_q;
    reg        crypto_idle_sync2_q;
    wire       ctrl_tx_valid_w;
    wire [7:0] ctrl_tx_data_w;
    wire       ctrl_tx_last_w;
    wire       axis_in_fire_w;
    wire       axis_out_fire_w;
    wire       bench_source_mode_w;
    wire       bench_sink_mode_w;
    wire       axis_core_in_tvalid_w;
    wire [7:0] axis_core_in_tdata_w;
    wire       axis_core_in_tlast_w;
    wire [0:0] axis_core_in_tuser_w;
    wire       bench_source_fire_w;
    wire [7:0] bench_source_data_w;
    wire       bench_source_last_w;
    wire       bench_candidate_hit_w;
    wire       tx_mux_valid_w;
    wire [7:0] tx_mux_data_w;
    wire       tx_fire_w;
    wire       pmu_uart_tx_stall_w;
    wire       pmu_stream_credit_block_w;
    wire       pmu_count_enable_w;
    wire       stream_payload_active_w;
    wire       stream_source_valid_w;
    wire [7:0] stream_source_data_w;
    wire       stream_source_last_w;
    wire       axis_direct_allowed_w;
    wire       ctrl_active_w;
    wire       bench_last_fire_w;
    wire       pmu_last_fire_w;
    wire       ctrl_last_fire_w;
    wire       stream_last_fire_w;
    wire       clk_crypto_gated;
    wire       crypto_clock_idle_w;
    wire       crypto_idle_sync_w;
    wire       crypto_wake_event_w;
    wire       crypto_clk_ce_w;
    wire       crypto_datapath_ready_w;
    wire [63:0] pmu_crypto_clock_status_flags_w;

    assign pmu_tx_active_w    = (pmu_tx_kind_q != PMU_TX_NONE);
    assign pmu_tx_data_w      = pmu_tx_byte(
                                    pmu_tx_kind_q,
                                    pmu_tx_idx_q,
                                    pmu_tx_global_cycles_q,
                                    pmu_tx_crypto_active_cycles_q,
                                    pmu_tx_uart_tx_stall_cycles_q,
                                    pmu_tx_stream_credit_block_cycles_q,
                                    pmu_tx_acl_block_events_q,
                                    pmu_tx_stream_bytes_in_q,
                                    pmu_tx_stream_bytes_out_q,
                                    pmu_tx_stream_chunk_count_q,
                                    pmu_tx_crypto_clock_gated_cycles_q,
                                    pmu_tx_crypto_clock_status_flags_q
                                 );
    assign stream_tx_active_w = (stream_tx_kind_q != STREAM_TX_NONE);
    assign stream_tx_data_w   = stream_tx_byte(stream_tx_kind_q, stream_tx_idx_q, stream_tx_seq_q, stream_tx_slot_q, stream_tx_code_q);
    assign bench_tx_active_w  = bench_tx_active_q;
    assign bench_tx_data_w    = bench_tx_byte(
                                    bench_tx_idx_q,
                                    bench_tx_status_q,
                                    bench_tx_algo_q,
                                    bench_tx_bytes_q,
                                    bench_tx_cycles_q,
                                    bench_tx_crc32_q
                                );
    assign ctrl_active_w      = (ctrl_tx_kind_q != CTRL_TX_NONE);
    assign ctrl_tx_valid_w    = ctrl_active_w;
    assign ctrl_tx_data_w     = ctrl_tx_data_r;
    assign ctrl_tx_last_w     = ctrl_tx_last_r;
    assign bench_source_mode_w = (bench_state_q == BENCH_RUN);
    assign bench_sink_mode_w   = (bench_state_q == BENCH_RUN) || (bench_state_q == BENCH_DRAIN_CRC);
    assign bench_source_data_w = (bench_bytes_in_q < 32'd16) ?
        bench_prefix_byte(bench_safe_head_prefix_q, bench_bytes_in_q[3:0]) :
        bench_lfsr_q;
    assign bench_source_last_w = (bench_bytes_in_q == (BENCH_TOTAL_BYTES - 32'd1));
    assign axis_core_in_tvalid_w = crypto_datapath_ready_w && (bench_source_mode_w ? (bench_bytes_in_q < BENCH_TOTAL_BYTES) : axis_in_pending_valid_q);
    assign axis_core_in_tdata_w  = bench_source_mode_w ? bench_source_data_w : axis_in_pending_data_q;
    assign axis_core_in_tlast_w  = bench_source_mode_w ? bench_source_last_w : axis_in_pending_last_q;
    assign axis_core_in_tuser_w  = bench_source_mode_w ? bench_algo_q : axis_in_pending_user_q;
    assign crypto_idle_sync_w    = crypto_idle_sync2_q;
    assign crypto_wake_event_w   = crypto_wake_req_q ||
                                   axis_in_pending_valid_q ||
                                   acl_in_valid_q ||
                                   acl_cfg_pending_q ||
                                   (bench_state_q != BENCH_IDLE) ||
                                   frame_bench_start_q ||
                                   frame_bench_force_q ||
                                   axis_soft_reset_q ||
                                   fatal_pending_q;
    assign crypto_clk_ce_w        = !i_rst_n ? 1'b1 : crypto_clk_ce_q;
    assign crypto_datapath_ready_w = crypto_clk_ce_q && (crypto_wake_settle_count_q == 2'd0);
    assign pmu_crypto_clock_status_flags_w = {62'd0, 1'b1, crypto_clock_gated_q};
    assign axis_in_fire_w      = !bench_source_mode_w && axis_in_pending_valid_q && axis_in_tready_w && crypto_datapath_ready_w;
    assign bench_source_fire_w = bench_source_mode_w && (bench_bytes_in_q < BENCH_TOTAL_BYTES) && axis_in_tready_w && crypto_datapath_ready_w;
    assign stream_payload_active_w =
        (tx_owner_q == TX_OWNER_STREAM) &&
        !stream_tx_active_w &&
        (stream_payload_bytes_left_q != 8'd0) &&
        axis_out_tvalid_w;
    assign stream_source_valid_w =
        stream_tx_active_w || stream_payload_active_w;
    assign stream_source_data_w =
        stream_tx_active_w ? stream_tx_data_w : axis_out_tdata_w;
    assign stream_source_last_w =
        stream_tx_active_w ?
            ((stream_tx_idx_q == stream_tx_last_idx(stream_tx_kind_q)) &&
             (stream_payload_bytes_left_q == 8'd0)) :
            (stream_payload_bytes_left_q == 8'd1);
    assign axis_direct_allowed_w =
        !bench_sink_mode_w &&
        !stream_session_active_q &&
        !stream_session_fault_q &&
        !acl_frame_stream_q &&
        (stream_seq_count_q == 4'd0) &&
        (stream_payload_bytes_left_q == 8'd0);
    assign axis_out_tready_w  = !crypto_datapath_ready_w ? 1'b0 :
                                (bench_sink_mode_w ? 1'b1 :
                                ((tx_owner_q == TX_OWNER_STREAM) ?
                                    (tx_ready &&
                                     !stream_tx_active_w &&
                                     (stream_payload_bytes_left_q != 8'd0)) :
                                 ((tx_owner_q == TX_OWNER_AXIS) ?
                                    (tx_ready && axis_direct_allowed_w) :
                                    1'b0)));
    assign axis_out_fire_w    = axis_out_tvalid_w && axis_out_tready_w;
    assign bench_candidate_hit_w =
        (bench_candidate_prefix(bench_pick_idx_q) == acl_rule_keys_flat[127:0])   ||
        (bench_candidate_prefix(bench_pick_idx_q) == acl_rule_keys_flat[255:128]) ||
        (bench_candidate_prefix(bench_pick_idx_q) == acl_rule_keys_flat[383:256]) ||
        (bench_candidate_prefix(bench_pick_idx_q) == acl_rule_keys_flat[511:384]) ||
        (bench_candidate_prefix(bench_pick_idx_q) == acl_rule_keys_flat[639:512]) ||
        (bench_candidate_prefix(bench_pick_idx_q) == acl_rule_keys_flat[767:640]) ||
        (bench_candidate_prefix(bench_pick_idx_q) == acl_rule_keys_flat[895:768]) ||
        (bench_candidate_prefix(bench_pick_idx_q) == acl_rule_keys_flat[1023:896]);
    assign tx_mux_valid_w    = (tx_owner_q == TX_OWNER_BENCH)  ? bench_tx_active_w :
                               (tx_owner_q == TX_OWNER_PMU)    ? pmu_tx_active_w :
                               (tx_owner_q == TX_OWNER_STREAM) ? stream_source_valid_w :
                               (tx_owner_q == TX_OWNER_CTRL)   ? ctrl_tx_valid_w :
                               (tx_owner_q == TX_OWNER_AXIS)   ? (axis_out_tvalid_w &&
                                                                  axis_direct_allowed_w) :
                               (tx_owner_q == TX_OWNER_FATAL)  ? fatal_tx_active_q :
                                                                  1'b0;
    assign tx_mux_data_w     = (tx_owner_q == TX_OWNER_BENCH)  ? bench_tx_data_w :
                               (tx_owner_q == TX_OWNER_PMU)    ? pmu_tx_data_w :
                               (tx_owner_q == TX_OWNER_STREAM) ? stream_source_data_w :
                               (tx_owner_q == TX_OWNER_CTRL)   ? ctrl_tx_data_w :
                               (tx_owner_q == TX_OWNER_FATAL)  ? fatal_tx_byte(fatal_tx_idx_q, fatal_code_q) :
                                                                  axis_out_tdata_w;
    assign tx_fire_w         = tx_mux_valid_w && tx_ready;
    assign bench_last_fire_w  = (tx_owner_q == TX_OWNER_BENCH) &&
                                tx_fire_w &&
                                (bench_tx_idx_q == 5'd21);
    assign pmu_last_fire_w    = (tx_owner_q == TX_OWNER_PMU) &&
                                tx_fire_w &&
                                (pmu_tx_idx_q == pmu_tx_last_idx(pmu_tx_kind_q));
    assign ctrl_last_fire_w   = (tx_owner_q == TX_OWNER_CTRL) &&
                                tx_fire_w &&
                                ctrl_tx_last_w;
    assign stream_last_fire_w = (tx_owner_q == TX_OWNER_STREAM) &&
                                tx_fire_w &&
                                stream_source_last_w;
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

    always @(*) begin
        ctrl_tx_data_r  = 8'h00;
        ctrl_tx_last_r  = 1'b0;

        case (ctrl_tx_kind_q)
            CTRL_TX_ERROR: begin
                ctrl_tx_data_r = (ctrl_tx_idx_q == 7'd0) ? ASCII_ERROR : ASCII_NL;
                ctrl_tx_last_r = (ctrl_tx_idx_q == 7'd1);
            end

            CTRL_TX_BLOCK: begin
                ctrl_tx_data_r = (ctrl_tx_idx_q == 7'd0) ? 8'h44 : ASCII_NL;
                ctrl_tx_last_r = (ctrl_tx_idx_q == 7'd1);
            end

            CTRL_TX_CFG_ACK: begin
                ctrl_tx_data_r = acl_v2_cfg_ack_byte(ctrl_tx_idx_q[4:0], ctrl_tx_cfg_ack_idx_q[2:0], ctrl_tx_cfg_ack_key_q);
                ctrl_tx_last_r = (ctrl_tx_idx_q == 8'd19);
            end

            CTRL_TX_KEYMAP: begin
                ctrl_tx_data_r = acl_v2_keymap_byte(ctrl_tx_idx_q[7:0], ctrl_tx_keymap_flat_q);
                ctrl_tx_last_r = (ctrl_tx_idx_q == 8'd130);
            end

            CTRL_TX_RULE_STATS: begin
                ctrl_tx_data_r = flat_rule_byte(ctrl_tx_idx_q[3:0], ctrl_tx_rule_stats_flat_q);
                ctrl_tx_last_r = (ctrl_tx_idx_q == 5'd9);
            end

            CTRL_TX_STATS: begin
                ctrl_tx_data_r = stats_byte(
                                    ctrl_tx_idx_q[2:0],
                                    ctrl_tx_stats_total_q,
                                    ctrl_tx_stats_acl_q,
                                    ctrl_tx_stats_aes_q,
                                    ctrl_tx_stats_sm4_q,
                                    ctrl_tx_stats_err_q
                                 );
                ctrl_tx_last_r = (ctrl_tx_idx_q == 4'd6);
            end

            CTRL_TX_HIT_STATS: begin
                ctrl_tx_data_r = acl_v2_hits_byte(ctrl_tx_idx_q[5:0], ctrl_tx_hit_stats_flat_q);
                ctrl_tx_last_r = (ctrl_tx_idx_q == 6'd34);
            end

            default: begin
                ctrl_tx_data_r = 8'h00;
                ctrl_tx_last_r = 1'b0;
            end
        endcase
    end

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
        .o_in_frame     (parser_in_frame_w),
        .o_frame_start  (),
        .o_payload_valid(parser_payload_valid),
        .o_payload_byte (parser_payload_byte),
        .o_frame_done   (parser_frame_done),
        .o_error        (parser_error),
        .o_payload_len  (parser_payload_len),
        .o_payload_count(parser_payload_count)
    );

    BUFGCE u_bufgce_crypto (
        .I (i_clk),
        .CE(crypto_clk_ce_w),
        .O (clk_crypto_gated)
    );

    contest_crypto_axis_core u_axis_core (
        .i_clk                 (clk_crypto_gated),
        .i_rst_n               (i_rst_n),
        .i_soft_reset          (axis_soft_reset_q && crypto_datapath_ready_w),
        .s_axis_tvalid         (axis_core_in_tvalid_w),
        .s_axis_tready         (axis_in_tready_w),
        .s_axis_tdata          (axis_core_in_tdata_w),
        .s_axis_tlast          (axis_core_in_tlast_w),
        .s_axis_tuser          (axis_core_in_tuser_w),
        .m_axis_tvalid         (axis_out_tvalid_w),
        .m_axis_tready         (axis_out_tready_w),
        .m_axis_tdata          (axis_out_tdata_w),
        .m_axis_tlast          (axis_out_tlast_w),
        .i_acl_cfg_valid       (acl_cfg_valid_q),
        .i_acl_cfg_index       (acl_cfg_index_q),
        .i_acl_cfg_key         (acl_cfg_key_q),
        .o_acl_cfg_busy        (acl_cfg_busy),
        .o_acl_cfg_done        (acl_cfg_done),
        .o_acl_cfg_error       (acl_cfg_error),
        .o_rule_keys_flat      (acl_rule_keys_flat),
        .o_rule_counts_flat    (acl_rule_counts_flat),
        .o_acl_block_pulse     (axis_acl_block_pulse_w),
        .o_acl_block_slot_valid(axis_acl_block_slot_valid_w),
        .o_acl_block_slot      (axis_acl_block_slot_w),
        .o_pmu_crypto_active   (pmu_crypto_active_w),
        .o_clock_idle          (crypto_clock_idle_w)
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
            crypto_clk_ce_q            <= 1'b1;
            crypto_clock_gated_q       <= 1'b0;
            crypto_sleep_count_q       <= 5'd0;
            crypto_wake_settle_count_q <= 2'd0;
            crypto_idle_sync1_q        <= 1'b0;
            crypto_idle_sync2_q        <= 1'b0;
        end else begin
            crypto_idle_sync1_q <= crypto_clock_idle_w;
            crypto_idle_sync2_q <= crypto_idle_sync1_q;

            if (crypto_wake_event_w) begin
                if (!crypto_clk_ce_q) begin
                    crypto_clk_ce_q            <= 1'b1;
                    crypto_clock_gated_q       <= 1'b0;
                    crypto_wake_settle_count_q <= CRYPTO_WAKE_SETTLE_CYCLES;
                end else if (crypto_wake_settle_count_q != 2'd0) begin
                    crypto_wake_settle_count_q <= crypto_wake_settle_count_q - 2'd1;
                end
                crypto_sleep_count_q <= 5'd0;
            end else if (crypto_wake_settle_count_q != 2'd0) begin
                crypto_wake_settle_count_q <= crypto_wake_settle_count_q - 2'd1;
                crypto_sleep_count_q <= 5'd0;
            end else if (crypto_clk_ce_q) begin
                if (crypto_idle_sync_w) begin
                    if (crypto_sleep_count_q == (CRYPTO_SLEEP_HOLDOFF - 5'd1)) begin
                        crypto_clk_ce_q      <= 1'b0;
                        crypto_clock_gated_q <= 1'b1;
                        crypto_sleep_count_q <= 5'd0;
                    end else begin
                        crypto_sleep_count_q <= crypto_sleep_count_q + 5'd1;
                    end
                end else begin
                    crypto_sleep_count_q <= 5'd0;
                end
            end
        end
    end

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            axis_in_pending_valid_q <= 1'b0;
            axis_in_pending_data_q  <= 8'd0;
            axis_in_pending_last_q  <= 1'b0;
            axis_in_pending_user_q  <= 1'b0;
        end else begin
            if (axis_in_pending_clear_q) begin
                axis_in_pending_valid_q <= 1'b0;
                axis_in_pending_data_q  <= 8'd0;
                axis_in_pending_last_q  <= 1'b0;
                axis_in_pending_user_q  <= 1'b0;
            end

            if (axis_in_fire_w) begin
                axis_in_pending_valid_q <= 1'b0;
            end

            if (acl_in_valid_q) begin
                axis_in_pending_valid_q <= 1'b1;
                axis_in_pending_data_q  <= acl_in_data_q;
                axis_in_pending_last_q  <= acl_in_last_q;
                axis_in_pending_user_q  <= acl_frame_algo_q;
            end
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
            frame_bench_query_q       <= 1'b0;
            frame_bench_start_q       <= 1'b0;
            frame_bench_force_q       <= 1'b0;
            frame_bench_force_seen_q  <= 1'b0;
            frame_bench_algo_valid_q  <= 1'b0;
            frame_bench_algo_q        <= ALG_SM4;
            frame_cfg_q               <= 1'b0;
            frame_cfg_index_q         <= 8'd0;
            frame_cfg_key_q           <= 128'd0;
            frame_cfg_key_seen_q      <= 1'b0;
            acl_cfg_pending_q         <= 1'b0;
            acl_cfg_pending_index_q   <= 3'd0;
            acl_cfg_pending_key_q     <= 128'd0;
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
            acl_in_valid_q            <= 1'b0;
            acl_in_data_q             <= 8'd0;
            acl_in_last_q             <= 1'b0;
            acl_cfg_valid_q           <= 1'b0;
            acl_cfg_index_q           <= 3'd0;
            acl_cfg_key_q             <= 128'd0;
            pending_cfg_ack_idx_q     <= 3'd0;
            pending_cfg_ack_key_q     <= 128'd0;
            pending_error_q           <= 1'b0;
            pending_block_q           <= 1'b0;
            pending_cfg_ack_q         <= 1'b0;
            pending_stats_q           <= 1'b0;
            pending_stats_total_q     <= 8'd0;
            pending_stats_acl_q       <= 8'd0;
            pending_stats_aes_q       <= 8'd0;
            pending_stats_sm4_q       <= 8'd0;
            pending_stats_err_q       <= 8'd0;
            pending_rule_stats_q      <= 1'b0;
            pending_rule_stats_flat_q <= 64'd0;
            pending_hit_stats_q       <= 1'b0;
            pending_hit_stats_flat_q  <= 256'd0;
            pending_keymap_q          <= 1'b0;
            pending_keymap_flat_q     <= 1024'd0;
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
            stream_pending_kind_q     <= STREAM_TX_NONE;
            stream_pending_seq_q      <= 8'd0;
            stream_pending_slot_q     <= 3'd0;
            stream_pending_code_q     <= 8'd0;
            pmu_armed_q               <= 1'b0;
            pmu_global_cycles_q       <= 64'd0;
            pmu_crypto_active_cycles_q <= 64'd0;
            pmu_uart_tx_stall_cycles_q <= 64'd0;
            pmu_stream_credit_block_cycles_q <= 64'd0;
            pmu_acl_block_events_q    <= 64'd0;
            pmu_stream_bytes_in_q     <= 64'd0;
            pmu_stream_bytes_out_q    <= 64'd0;
            pmu_stream_chunk_count_q  <= 64'd0;
            pmu_crypto_clock_gated_cycles_q <= 64'd0;
            pmu_snap_global_cycles_q  <= 64'd0;
            pmu_snap_crypto_active_cycles_q <= 64'd0;
            pmu_snap_uart_tx_stall_cycles_q <= 64'd0;
            pmu_snap_stream_credit_block_cycles_q <= 64'd0;
            pmu_snap_acl_block_events_q <= 64'd0;
            pmu_snap_stream_bytes_in_q  <= 64'd0;
            pmu_snap_stream_bytes_out_q <= 64'd0;
            pmu_snap_stream_chunk_count_q <= 64'd0;
            pmu_snap_crypto_clock_gated_cycles_q <= 64'd0;
            pmu_snap_crypto_clock_status_flags_q <= 64'd0;
            pmu_pending_q             <= 1'b0;
            pmu_pending_kind_q        <= PMU_TX_NONE;
            pmu_tx_kind_q             <= PMU_TX_NONE;
            pmu_tx_idx_q              <= 7'd0;
            pmu_tx_global_cycles_q    <= 64'd0;
            pmu_tx_crypto_active_cycles_q <= 64'd0;
            pmu_tx_uart_tx_stall_cycles_q <= 64'd0;
            pmu_tx_stream_credit_block_cycles_q <= 64'd0;
            pmu_tx_acl_block_events_q <= 64'd0;
            pmu_tx_stream_bytes_in_q  <= 64'd0;
            pmu_tx_stream_bytes_out_q <= 64'd0;
            pmu_tx_stream_chunk_count_q <= 64'd0;
            pmu_tx_crypto_clock_gated_cycles_q <= 64'd0;
            pmu_tx_crypto_clock_status_flags_q <= 64'd0;
            bench_state_q             <= BENCH_IDLE;
            bench_tx_idx_q            <= 5'd0;
            bench_pick_idx_q          <= 4'd0;
            bench_algo_q              <= ALG_SM4;
            bench_bytes_in_q          <= 32'd0;
            bench_bytes_out_q         <= 32'd0;
            bench_cycles_q            <= 64'd0;
            bench_watchdog_q          <= 24'd0;
            bench_latch_status_q      <= BENCH_STATUS_OK;
            bench_safe_head_prefix_q   <= 128'h00000000000000000000000000000000;
            bench_lfsr_q              <= 8'hB8;
            bench_crc32_q             <= 32'hFFFF_FFFF;
            bench_result_valid_q      <= 1'b0;
            bench_last_algo_q         <= ALG_SM4;
            bench_last_status_q       <= BENCH_STATUS_NO_RESULT;
            bench_last_bytes_q        <= 32'd0;
            bench_last_cycles_q       <= 64'd0;
            bench_last_crc32_q        <= 32'd0;
            bench_pending_q           <= 1'b0;
            bench_pending_algo_q      <= ALG_SM4;
            bench_pending_status_q    <= BENCH_STATUS_NO_RESULT;
            bench_pending_bytes_q     <= 32'd0;
            bench_pending_cycles_q    <= 64'd0;
            bench_pending_crc32_q     <= 32'd0;
            bench_tx_active_q         <= 1'b0;
            bench_tx_algo_q           <= ALG_SM4;
            bench_tx_status_q         <= BENCH_STATUS_NO_RESULT;
            bench_tx_bytes_q          <= 32'd0;
            bench_tx_cycles_q         <= 64'd0;
            bench_tx_crc32_q          <= 32'd0;
            ctrl_tx_kind_q            <= CTRL_TX_NONE;
            ctrl_tx_idx_q             <= 8'd0;
            tx_owner_q                <= TX_OWNER_NONE;
            ctrl_tx_cfg_ack_idx_q     <= 8'd0;
            ctrl_tx_cfg_ack_key_q     <= 128'd0;
            ctrl_tx_stats_total_q     <= 8'd0;
            ctrl_tx_stats_acl_q       <= 8'd0;
            ctrl_tx_stats_aes_q       <= 8'd0;
            ctrl_tx_stats_sm4_q       <= 8'd0;
            ctrl_tx_stats_err_q       <= 8'd0;
            ctrl_tx_rule_stats_flat_q <= 64'd0;
            ctrl_tx_hit_stats_flat_q  <= 256'd0;
            ctrl_tx_keymap_flat_q     <= 1024'd0;
            axis_soft_reset_q         <= 1'b0;
            crc_pipe_valid_q          <= 1'b0;
            crc_pipe_last_q           <= 1'b0;
            fatal_pending_q           <= 1'b0;
            fatal_code_q              <= 8'd0;
            quiesce_count_q           <= 3'd0;
            quiesce_active_q          <= 1'b0;
            drain_committed_q         <= 1'b0;
            stream_wdg_counter_q      <= 32'd0;
            crypto_wdg_counter_q      <= 32'd0;
            fatal_tx_active_q         <= 1'b0;
            fatal_tx_idx_q            <= 2'd0;
            crypto_wake_req_q         <= 1'b0;
            crc_pipe_data_q           <= 8'd0;
        end else begin
            acl_in_valid_q    <= 1'b0;
            acl_in_data_q     <= 8'd0;
            acl_in_last_q     <= 1'b0;
            if (fatal_pending_q && !fatal_tx_active_q && !quiesce_active_q && !drain_committed_q) begin
                axis_soft_reset_q         <= 1'b1;
                stream_session_active_q   <= 1'b0;
                stream_session_fault_q    <= 1'b1;
                acl_frame_active_q        <= 1'b0;
                acl_in_valid_q           <= 1'b0;
                stream_seq_wr_ptr_q       <= 3'd0;
                stream_seq_rd_ptr_q       <= 3'd0;
                stream_seq_count_q        <= 4'd0;
                stream_payload_bytes_left_q <= 8'd0;
                stream_tx_kind_q          <= STREAM_TX_NONE;
                stream_pending_kind_q     <= STREAM_TX_NONE;
                quiesce_active_q          <= 1'b1;
                quiesce_count_q           <= 3'd0;
                drain_committed_q         <= 1'b0;
            end else begin
                axis_soft_reset_q <= 1'b0;
            end

            if (quiesce_active_q) begin
                if (quiesce_count_q < QUIESCE_CYCLES) begin
                    quiesce_count_q <= quiesce_count_q + 3'd1;
                end else if (tx_owner_q == TX_OWNER_NONE && !drain_committed_q) begin
                    fatal_tx_active_q <= 1'b1;
                    fatal_tx_idx_q    <= 2'd0;
                    tx_owner_q        <= TX_OWNER_FATAL;
                    drain_committed_q <= 1'b1;
                    quiesce_active_q  <= 1'b0;
                end
            end

            if (tx_owner_q == TX_OWNER_FATAL && tx_fire_w) begin
                if (fatal_tx_idx_q == fatal_tx_last_idx(fatal_code_q)) begin
                    fatal_tx_active_q <= 1'b0;
                    fatal_tx_idx_q    <= 2'd0;
                    tx_owner_q        <= TX_OWNER_NONE;
                    fatal_pending_q   <= 1'b0;
                    fatal_code_q      <= 8'd0;
                    drain_committed_q <= 1'b0;
                    quiesce_count_q   <= 3'd0;
                end else begin
                    fatal_tx_idx_q <= fatal_tx_idx_q + 2'd1;
                end
            end

            acl_cfg_valid_q   <= 1'b0;
            acl_cfg_index_q   <= 3'd0;
            acl_cfg_key_q     <= 128'd0;
            axis_in_pending_clear_q <= 1'b0;

            if (crypto_wake_req_q && crypto_datapath_ready_w) begin
                crypto_wake_req_q <= 1'b0;
            end

            if (acl_cfg_pending_q && crypto_datapath_ready_w && !acl_cfg_busy) begin
                acl_cfg_valid_q       <= 1'b1;
                acl_cfg_index_q       <= acl_cfg_pending_index_q;
                acl_cfg_key_q         <= acl_cfg_pending_key_q;
                acl_cfg_pending_q     <= 1'b0;
            end

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
                if (crypto_clock_gated_q) begin
                    pmu_crypto_clock_gated_cycles_q <= pmu_crypto_clock_gated_cycles_q + 64'd1;
                end
            end

            if (acl_in_valid_q && acl_frame_stream_q) begin
                pmu_stream_bytes_in_q <= pmu_stream_bytes_in_q + 64'd1;
            end

            if ((tx_owner_q == TX_OWNER_STREAM) && tx_fire_w &&
                !stream_tx_active_w && (stream_payload_bytes_left_q != 8'd0)) begin
                pmu_stream_bytes_out_q <= pmu_stream_bytes_out_q + 64'd1;
            end

            if (stream_last_fire_w && !stream_tx_active_w) begin
                pmu_stream_chunk_count_q <= pmu_stream_chunk_count_q + 64'd1;
            end

            if (stream_session_active_q && !fatal_pending_q) begin
                stream_wdg_counter_q <= stream_wdg_counter_q + 32'd1;
                if (stream_wdg_counter_q == 32'(STREAM_WDG_TIMEOUT - 1)) begin
                    fatal_pending_q <= 1'b1;
                    fatal_code_q <= FATAL_STREAM_WATCHDOG;
                end
            end else begin
                stream_wdg_counter_q <= 32'd0;
            end

            if ((stream_tx_kind_q == STREAM_TX_CIPHER_HDR) && tx_fire_w) begin
                stream_wdg_counter_q <= 32'd0;
            end

            if (pmu_crypto_active_w && !fatal_pending_q) begin
                crypto_wdg_counter_q <= crypto_wdg_counter_q + 32'd1;
                if (crypto_wdg_counter_q == 32'(CRYPTO_WDG_TIMEOUT - 1)) begin
                    fatal_pending_q <= 1'b1;
                    fatal_code_q <= FATAL_CRYPTO_WATCHDOG;
                end
            end else begin
                crypto_wdg_counter_q <= 32'd0;
            end

            if ((stream_tx_kind_q == STREAM_TX_NONE) &&
                (stream_payload_bytes_left_q == 8'd0) &&
                (stream_pending_kind_q != STREAM_TX_NONE)) begin
                stream_tx_kind_q      <= stream_pending_kind_q;
                stream_tx_idx_q       <= 3'd0;
                stream_tx_seq_q       <= stream_pending_seq_q;
                stream_tx_slot_q      <= stream_pending_slot_q;
                stream_tx_code_q      <= stream_pending_code_q;
                stream_pending_kind_q <= STREAM_TX_NONE;
            end

            if (tx_owner_q == TX_OWNER_BENCH && tx_fire_w) begin
                if (bench_last_fire_w) begin
                    bench_tx_active_q <= 1'b0;
                    bench_tx_idx_q    <= 5'd0;
                    tx_owner_q        <= TX_OWNER_NONE;
                end else begin
                    bench_tx_idx_q <= bench_tx_idx_q + 5'd1;
                end
            end

            if (tx_owner_q == TX_OWNER_PMU && tx_fire_w) begin
                if (pmu_last_fire_w) begin
                    pmu_tx_kind_q <= PMU_TX_NONE;
                    pmu_tx_idx_q  <= 7'd0;
                    tx_owner_q    <= TX_OWNER_NONE;
                end else begin
                    pmu_tx_idx_q <= pmu_tx_idx_q + 7'd1;
                end
            end

            if (tx_owner_q == TX_OWNER_CTRL && tx_fire_w) begin
                if (ctrl_last_fire_w) begin
                    ctrl_tx_kind_q <= CTRL_TX_NONE;
                    ctrl_tx_idx_q  <= 8'd0;
                    tx_owner_q     <= TX_OWNER_NONE;
                end else begin
                    ctrl_tx_idx_q <= ctrl_tx_idx_q + 8'd1;
                end
            end

            if (tx_owner_q == TX_OWNER_STREAM && tx_fire_w) begin
                if (stream_tx_active_w) begin
                    if (stream_tx_idx_q == stream_tx_last_idx(stream_tx_kind_q)) begin
                        stream_tx_kind_q <= STREAM_TX_NONE;
                        stream_tx_idx_q  <= 3'd0;
                        if (stream_payload_bytes_left_q == 8'd0) begin
                            tx_owner_q <= TX_OWNER_NONE;
                        end
                    end else begin
                        stream_tx_idx_q <= stream_tx_idx_q + 3'd1;
                    end
                end else if (stream_payload_bytes_left_q != 8'd0) begin
                    if (stream_payload_bytes_left_q == 8'd1) begin
                        stream_payload_bytes_left_q <= 8'd0;
                        tx_owner_q <= TX_OWNER_NONE;
                    end else begin
                        stream_payload_bytes_left_q <= stream_payload_bytes_left_q - 8'd1;
                    end
                end
            end

            if ((tx_owner_q == TX_OWNER_AXIS) && tx_fire_w && axis_out_tlast_w) begin
                tx_owner_q <= TX_OWNER_NONE;
            end

            if ((tx_owner_q == TX_OWNER_NONE) && tx_ready) begin
                if (bench_pending_q) begin
                    bench_pending_q   <= 1'b0;
                    bench_tx_active_q <= 1'b1;
                    bench_tx_idx_q    <= 5'd0;
                    bench_tx_status_q <= bench_pending_status_q;
                    bench_tx_algo_q   <= bench_pending_algo_q;
                    bench_tx_bytes_q  <= bench_pending_bytes_q;
                    bench_tx_cycles_q <= bench_pending_cycles_q;
                    bench_tx_crc32_q  <= bench_pending_crc32_q;
                    tx_owner_q        <= TX_OWNER_BENCH;
                end else if (pmu_pending_q) begin
                    pmu_pending_q      <= 1'b0;
                    pmu_tx_kind_q      <= pmu_pending_kind_q;
                    pmu_tx_idx_q       <= 7'd0;
                    pmu_tx_global_cycles_q <= pmu_snap_global_cycles_q;
                    pmu_tx_crypto_active_cycles_q <= pmu_snap_crypto_active_cycles_q;
                    pmu_tx_uart_tx_stall_cycles_q <= pmu_snap_uart_tx_stall_cycles_q;
                    pmu_tx_stream_credit_block_cycles_q <= pmu_snap_stream_credit_block_cycles_q;
                    pmu_tx_acl_block_events_q <= pmu_snap_acl_block_events_q;
                    pmu_tx_stream_bytes_in_q <= pmu_snap_stream_bytes_in_q;
                    pmu_tx_stream_bytes_out_q <= pmu_snap_stream_bytes_out_q;
                    pmu_tx_stream_chunk_count_q <= pmu_snap_stream_chunk_count_q;
                    pmu_tx_crypto_clock_gated_cycles_q <= pmu_snap_crypto_clock_gated_cycles_q;
                    pmu_tx_crypto_clock_status_flags_q <= pmu_snap_crypto_clock_status_flags_q;
                    tx_owner_q         <= TX_OWNER_PMU;
                end else if (!stream_tx_active_w &&
                             (stream_payload_bytes_left_q == 8'd0) &&
                             (stream_seq_count_q != 4'd0) &&
                             axis_out_tvalid_w &&
                             !frame_stream_chunk_q) begin
                    stream_tx_kind_q            <= STREAM_TX_CIPHER_HDR;
                    stream_tx_idx_q             <= 3'd0;
                    stream_tx_seq_q             <= stream_seq_fifo_q[stream_seq_rd_ptr_q];
                    stream_seq_rd_ptr_q         <= stream_seq_rd_ptr_q + 3'd1;
                    stream_seq_count_q          <= stream_seq_count_q - 4'd1;
                    stream_payload_bytes_left_q <= 8'd128;
                    tx_owner_q                  <= TX_OWNER_STREAM;
                end else if (stream_source_valid_w) begin
                    tx_owner_q <= TX_OWNER_STREAM;
                end else if (pending_error_q) begin
                    pending_error_q <= 1'b0;
                    ctrl_tx_kind_q  <= CTRL_TX_ERROR;
                    ctrl_tx_idx_q   <= 8'd0;
                    tx_owner_q      <= TX_OWNER_CTRL;
                end else if (pending_block_q) begin
                    pending_block_q <= 1'b0;
                    ctrl_tx_kind_q  <= CTRL_TX_BLOCK;
                    ctrl_tx_idx_q   <= 8'd0;
                    tx_owner_q      <= TX_OWNER_CTRL;
                end else if (pending_cfg_ack_q) begin
                    pending_cfg_ack_q     <= 1'b0;
                    ctrl_tx_kind_q        <= CTRL_TX_CFG_ACK;
                    ctrl_tx_idx_q         <= 8'd0;
                    ctrl_tx_cfg_ack_idx_q <= pending_cfg_ack_idx_q;
                    ctrl_tx_cfg_ack_key_q <= pending_cfg_ack_key_q;
                    tx_owner_q            <= TX_OWNER_CTRL;
                end else if (pending_keymap_q) begin
                    pending_keymap_q          <= 1'b0;
                    ctrl_tx_kind_q            <= CTRL_TX_KEYMAP;
                    ctrl_tx_idx_q             <= 8'd0;
                    ctrl_tx_keymap_flat_q     <= pending_keymap_flat_q;
                    tx_owner_q                <= TX_OWNER_CTRL;
                end else if (pending_rule_stats_q) begin
                    pending_rule_stats_q      <= 1'b0;
                    ctrl_tx_kind_q            <= CTRL_TX_RULE_STATS;
                    ctrl_tx_idx_q             <= 8'd0;
                    ctrl_tx_rule_stats_flat_q <= pending_rule_stats_flat_q;
                    tx_owner_q                <= TX_OWNER_CTRL;
                end else if (pending_hit_stats_q) begin
                    pending_hit_stats_q      <= 1'b0;
                    ctrl_tx_kind_q           <= CTRL_TX_HIT_STATS;
                    ctrl_tx_idx_q            <= 8'd0;
                    ctrl_tx_hit_stats_flat_q <= pending_hit_stats_flat_q;
                    tx_owner_q               <= TX_OWNER_CTRL;
                end else if (pending_stats_q) begin
                    pending_stats_q       <= 1'b0;
                    ctrl_tx_kind_q        <= CTRL_TX_STATS;
                    ctrl_tx_idx_q         <= 8'd0;
                    ctrl_tx_stats_total_q <= pending_stats_total_q;
                    ctrl_tx_stats_acl_q   <= pending_stats_acl_q;
                    ctrl_tx_stats_aes_q   <= pending_stats_aes_q;
                    ctrl_tx_stats_sm4_q   <= pending_stats_sm4_q;
                    ctrl_tx_stats_err_q   <= pending_stats_err_q;
                    tx_owner_q            <= TX_OWNER_CTRL;
                end else if (axis_out_tvalid_w && axis_direct_allowed_w) begin
                    tx_owner_q <= TX_OWNER_AXIS;
                end
            end

            crc_pipe_valid_q <= 1'b0;

            if (bench_sink_mode_w && axis_out_fire_w) begin
                crc_pipe_valid_q <= 1'b1;
                crc_pipe_last_q  <= axis_out_tlast_w;
                crc_pipe_data_q  <= axis_out_tdata_w;
                if (axis_out_tlast_w) begin
                    bench_state_q <= BENCH_DRAIN_CRC;
                end
            end

            if (crc_pipe_valid_q) begin
                bench_bytes_out_q <= bench_bytes_out_q + 32'd1;
                bench_crc32_q     <= bench_crc32_next(bench_crc32_q, crc_pipe_data_q);
                if ((bench_state_q == BENCH_DRAIN_CRC) && crc_pipe_last_q) begin
                    bench_latch_status_q <= BENCH_STATUS_OK;
                    bench_state_q        <= BENCH_LATCH;
                end
            end

            case (bench_state_q)
                BENCH_IDLE: begin
                end

                BENCH_PICK_HEAD: begin
                    bench_cycles_q   <= bench_cycles_q + 64'd1;
                    bench_watchdog_q <= bench_watchdog_q + 24'd1;
                    if (!bench_candidate_hit_w) begin
                        bench_safe_head_prefix_q <= bench_candidate_prefix(bench_pick_idx_q);
                        bench_state_q          <= BENCH_ARM;
                    end else if (bench_pick_idx_q == 4'd15) begin
                        bench_latch_status_q <= BENCH_STATUS_INTERNAL;
                        bench_state_q        <= BENCH_LATCH;
                    end else begin
                        bench_pick_idx_q <= bench_pick_idx_q + 4'd1;
                    end
                end

                BENCH_ARM: begin
                    bench_bytes_in_q   <= 32'd0;
                    bench_bytes_out_q  <= 32'd0;
                    bench_cycles_q     <= 64'd0;
                    bench_watchdog_q   <= 24'd0;
                    bench_lfsr_q       <= 8'hB8;
                    bench_crc32_q      <= 32'hFFFF_FFFF;
                    crc_pipe_valid_q   <= 1'b0;
                    bench_latch_status_q <= BENCH_STATUS_OK;
                    bench_state_q      <= BENCH_RUN;
                end

                BENCH_RUN: begin
                    bench_cycles_q   <= bench_cycles_q + 64'd1;
                    bench_watchdog_q <= bench_watchdog_q + 24'd1;
                    if (bench_source_fire_w) begin
                        bench_bytes_in_q <= bench_bytes_in_q + 32'd1;
                        bench_lfsr_q     <= bench_lfsr_next(bench_lfsr_q);
                    end
                    if (bench_watchdog_q == BENCH_TIMEOUT_CLKS) begin
                        bench_latch_status_q <= BENCH_STATUS_TIMEOUT;
                        bench_state_q        <= BENCH_LATCH;
                    end
                end

                BENCH_DRAIN_CRC: begin
                    bench_cycles_q   <= bench_cycles_q + 64'd1;
                    bench_watchdog_q <= bench_watchdog_q + 24'd1;
                    if (bench_watchdog_q == BENCH_TIMEOUT_CLKS) begin
                        bench_latch_status_q <= BENCH_STATUS_TIMEOUT;
                        bench_state_q        <= BENCH_LATCH;
                    end
                end

                BENCH_LATCH: begin
                    bench_last_status_q  <= bench_latch_status_q;
                    bench_last_algo_q    <= bench_algo_q;
                    bench_last_bytes_q   <= bench_bytes_out_q;
                    bench_last_cycles_q  <= bench_cycles_q;
                    bench_last_crc32_q   <= bench_crc32_q ^ 32'hFFFF_FFFF;
                    bench_result_valid_q <= 1'b1;
                    bench_pending_q      <= 1'b1;
                    bench_pending_status_q <= bench_latch_status_q;
                    bench_pending_algo_q   <= bench_algo_q;
                    bench_pending_bytes_q  <= bench_bytes_out_q;
                    bench_pending_cycles_q <= bench_cycles_q;
                    bench_pending_crc32_q  <= bench_crc32_q ^ 32'hFFFF_FFFF;
                    bench_state_q        <= BENCH_IDLE;
                end

                default: begin
                end
            endcase

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
                frame_bench_query_q       <= 1'b0;
                frame_bench_start_q       <= 1'b0;
                frame_bench_force_q       <= 1'b0;
                frame_bench_force_seen_q  <= 1'b0;
                frame_bench_algo_valid_q  <= 1'b0;
                frame_bench_algo_q        <= ALG_SM4;
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
                    frame_cfg_key_q           <= 128'd0;
                    frame_cfg_key_seen_q      <= 1'b0;
                    frame_stream_cap_q        <= 1'b0;
                    frame_pmu_query_q         <= 1'b0;
                    frame_pmu_clear_q         <= 1'b0;
                    frame_bench_query_q       <= 1'b0;
                    frame_bench_start_q       <= 1'b0;
                    frame_bench_force_q       <= 1'b0;
                    frame_bench_force_seen_q  <= 1'b0;
                    frame_bench_algo_valid_q  <= 1'b0;
                    frame_bench_algo_q        <= ALG_SM4;
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
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_BENCH)) begin
                        frame_bench_query_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd2) && (parser_payload_byte == ASCII_BENCH)) begin
                        frame_bench_start_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd3) && (parser_payload_byte == ASCII_BENCH)) begin
                        frame_bench_force_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd1) && (parser_payload_byte == STREAM_CAP_QUERY)) begin
                        frame_stream_cap_q <= 1'b1;
                    end else if ((parser_payload_len == 8'd18) && (parser_payload_byte == ASCII_CFG_ACK)) begin
                        frame_cfg_q <= 1'b1;
                        crypto_wake_req_q <= 1'b1;
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
                    end else if (parser_payload_count >= 8'd3 && parser_payload_count <= 8'd18) begin
                        frame_cfg_key_q <= {frame_cfg_key_q[119:0], parser_payload_byte};
                        if (parser_payload_count == 8'd18) begin
                            frame_cfg_key_seen_q <= 1'b1;
                        end
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
                end else if (frame_bench_start_q) begin
                    if (parser_payload_count == 8'd2) begin
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
                end else if (frame_bench_force_q) begin
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
                if (!frame_pmu_query_q && !frame_pmu_clear_q && !frame_bench_query_q) begin
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
                    pmu_snap_stream_bytes_in_q           <= pmu_stream_bytes_in_q;
                    pmu_snap_stream_bytes_out_q          <= pmu_stream_bytes_out_q;
                    pmu_snap_stream_chunk_count_q        <= pmu_stream_chunk_count_q;
                    pmu_snap_crypto_clock_gated_cycles_q <= pmu_crypto_clock_gated_cycles_q;
                    pmu_snap_crypto_clock_status_flags_q <= pmu_crypto_clock_status_flags_w;
                    pmu_pending_q                        <= 1'b1;
                    pmu_pending_kind_q                   <= PMU_TX_SNAPSHOT;
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                               (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_PMU_CLR))) ||
                              frame_pmu_clear_q) begin
                    pmu_armed_q                         <= 1'b0;
                    pmu_global_cycles_q                 <= 64'd0;
                    pmu_crypto_active_cycles_q          <= 64'd0;
                    pmu_uart_tx_stall_cycles_q          <= 64'd0;
                    pmu_stream_credit_block_cycles_q    <= 64'd0;
                    pmu_acl_block_events_q              <= 64'd0;
                    pmu_stream_bytes_in_q               <= 64'd0;
                    pmu_stream_bytes_out_q              <= 64'd0;
                    pmu_stream_chunk_count_q            <= 64'd0;
                    pmu_crypto_clock_gated_cycles_q     <= 64'd0;
                    pmu_snap_global_cycles_q            <= 64'd0;
                    pmu_snap_crypto_active_cycles_q     <= 64'd0;
                    pmu_snap_uart_tx_stall_cycles_q     <= 64'd0;
                    pmu_snap_stream_credit_block_cycles_q <= 64'd0;
                    pmu_snap_acl_block_events_q         <= 64'd0;
                    pmu_snap_stream_bytes_in_q          <= 64'd0;
                    pmu_snap_stream_bytes_out_q         <= 64'd0;
                    pmu_snap_stream_chunk_count_q       <= 64'd0;
                    pmu_snap_crypto_clock_gated_cycles_q <= 64'd0;
                    pmu_snap_crypto_clock_status_flags_q <= 64'd0;
                    pmu_pending_q                       <= 1'b1;
                    pmu_pending_kind_q                  <= PMU_TX_CLEAR_ACK;
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                               (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_BENCH))) ||
                              frame_bench_query_q) begin
                    bench_pending_q      <= 1'b1;
                    bench_pending_status_q <= bench_result_valid_q ? bench_last_status_q : BENCH_STATUS_NO_RESULT;
                    bench_pending_algo_q   <= bench_result_valid_q ? bench_last_algo_q : ALG_SM4;
                    bench_pending_bytes_q  <= bench_result_valid_q ? bench_last_bytes_q : 32'd0;
                    bench_pending_cycles_q <= bench_result_valid_q ? bench_last_cycles_q : 64'd0;
                    bench_pending_crc32_q  <= bench_result_valid_q ? bench_last_crc32_q : 32'd0;
                end else if (frame_bench_start_q || frame_bench_force_q) begin
                    if ((!(frame_bench_algo_valid_q ||
                           (frame_bench_start_q &&
                            parser_payload_valid &&
                            (parser_payload_count == 8'd2) &&
                            ((parser_payload_byte == MODE_AES) || (parser_payload_byte == MODE_SM4))) ||
                           (frame_bench_force_q &&
                            parser_payload_valid &&
                            (parser_payload_count == 8'd3) &&
                            ((parser_payload_byte == MODE_AES) || (parser_payload_byte == MODE_SM4))))) ||
                        (frame_bench_force_q &&
                         !(frame_bench_force_seen_q ||
                           (parser_payload_valid &&
                            (parser_payload_count == 8'd2) &&
                            (parser_payload_byte == 8'hFF))))) begin
                        pending_error_q     <= 1'b1;
                        stat_error_frames_q <= stat_error_frames_q + 8'd1;
                    end else if (frame_bench_force_q) begin
                        axis_soft_reset_q       <= 1'b1;
                        axis_in_pending_clear_q   <= 1'b1;
                        acl_frame_active_q        <= 1'b0;
                        acl_frame_algo_q          <= ALG_SM4;
                        acl_frame_stream_q        <= 1'b0;
                        acl_in_valid_q            <= 1'b0;
                        acl_in_data_q             <= 8'd0;
                        acl_in_last_q             <= 1'b0;
                        frame_stream_block_q      <= 1'b0;
                        frame_stream_block_slot_q <= 3'd0;
                        stream_session_active_q   <= 1'b0;
                        stream_session_fault_q    <= 1'b0;
                        stream_expected_valid_q   <= 1'b0;
                        stream_expected_seq_q     <= 8'd0;
                        stream_seq_wr_ptr_q       <= 3'd0;
                        stream_seq_rd_ptr_q       <= 3'd0;
                        stream_seq_count_q        <= 4'd0;
                        stream_payload_bytes_left_q <= 8'd0;
                        stream_tx_kind_q          <= STREAM_TX_NONE;
                        stream_tx_idx_q           <= 3'd0;
                        stream_pending_kind_q     <= STREAM_TX_NONE;
                        stream_pending_seq_q      <= 8'd0;
                        stream_pending_slot_q     <= 3'd0;
                        stream_pending_code_q     <= 8'd0;
                        if ((tx_owner_q == TX_OWNER_STREAM) || (tx_owner_q == TX_OWNER_AXIS)) begin
                            tx_owner_q            <= TX_OWNER_NONE;
                        end
                        bench_algo_q              <=
                            (parser_payload_valid &&
                             (parser_payload_count == 8'd3) &&
                             (parser_payload_byte == MODE_AES)) ? ALG_AES :
                            ((parser_payload_valid &&
                              (parser_payload_count == 8'd3) &&
                              (parser_payload_byte == MODE_SM4)) ? ALG_SM4 :
                             frame_bench_algo_q);
                        bench_pick_idx_q          <= 4'd0;
                        bench_state_q             <= BENCH_PICK_HEAD;
                    end else if (parser_in_frame_w ||
                                 axis_in_pending_valid_q ||
                                 acl_frame_active_q ||
                                 stream_session_active_q ||
                                 (stream_pending_kind_q != STREAM_TX_NONE) ||
                                 stream_tx_active_w ||
                                 ctrl_active_w ||
                                 pending_error_q ||
                                 pending_block_q ||
                                 pending_cfg_ack_q ||
                                 pending_keymap_q ||
                                 pending_rule_stats_q ||
                                 pending_stats_q ||
                                 pmu_pending_q ||
                                 pmu_tx_active_w ||
                                 bench_pending_q ||
                                 bench_tx_active_w ||
                                 axis_out_tvalid_w ||
                                 pmu_crypto_active_w ||
                                 (bench_state_q != BENCH_IDLE)) begin
                        bench_pending_q      <= 1'b1;
                        bench_pending_status_q <= BENCH_STATUS_BUSY;
                        bench_pending_algo_q   <=
                            (parser_payload_valid &&
                             (parser_payload_count == 8'd2) &&
                             (parser_payload_byte == MODE_AES)) ? ALG_AES :
                            ((parser_payload_valid &&
                              (parser_payload_count == 8'd2) &&
                              (parser_payload_byte == MODE_SM4)) ? ALG_SM4 :
                             frame_bench_algo_q);
                        bench_pending_bytes_q  <= 32'd0;
                        bench_pending_cycles_q <= 64'd0;
                        bench_pending_crc32_q  <= 32'd0;
                    end else begin
                        bench_algo_q     <=
                            (parser_payload_valid &&
                             (parser_payload_count == 8'd2) &&
                             (parser_payload_byte == MODE_AES)) ? ALG_AES :
                            ((parser_payload_valid &&
                              (parser_payload_count == 8'd2) &&
                              (parser_payload_byte == MODE_SM4)) ? ALG_SM4 :
                             frame_bench_algo_q);
                        bench_pick_idx_q <= 4'd0;
                        bench_state_q    <= BENCH_PICK_HEAD;
                    end
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                      (parser_payload_len == 8'd1) && (parser_payload_byte == STREAM_CAP_QUERY))) ||
                    frame_stream_cap_q) begin
                    stream_pending_kind_q <= STREAM_TX_CAP;
                    stream_pending_seq_q  <= 8'd0;
                    stream_pending_slot_q <= 3'd0;
                    stream_pending_code_q <= 8'd0;
                end else if (frame_stream_start_q) begin
                    if (frame_stream_error_q) begin
                        stream_pending_kind_q <= STREAM_TX_ERROR;
                        stream_pending_seq_q  <= 8'd0;
                        stream_pending_slot_q <= 3'd0;
                        stream_pending_code_q <= frame_stream_error_code_q;
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
                        stream_pending_kind_q   <= STREAM_TX_START_ACK;
                        stream_pending_seq_q    <= 8'd0;
                        stream_pending_slot_q   <= 3'd0;
                        stream_pending_code_q   <= 8'd0;
                    end
                end else if (frame_stream_chunk_q) begin
                    if (frame_stream_error_q) begin
                        stream_pending_kind_q <= STREAM_TX_ERROR;
                        stream_pending_seq_q  <= 8'd0;
                        stream_pending_slot_q <= 3'd0;
                        stream_pending_code_q <= frame_stream_error_code_q;
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
                        stream_pending_kind_q   <= STREAM_TX_BLOCK;
                        stream_pending_seq_q    <= frame_stream_seq_q;
                        stream_pending_slot_q   <= frame_stream_block_slot_q;
                        stream_pending_code_q   <= 8'd0;
                    end else if (frame_key_valid_q) begin
                        stat_total_frames_q     <= stat_total_frames_q + 8'd1;
                        stream_expected_valid_q <= 1'b1;
                        stream_expected_seq_q   <= frame_stream_seq_q + 8'd1;
                        if (stream_seq_count_q == STREAM_WINDOW[3:0]) begin
                            stream_pending_kind_q   <= STREAM_TX_ERROR;
                            stream_pending_seq_q    <= 8'd0;
                            stream_pending_slot_q   <= 3'd0;
                            stream_pending_code_q   <= STREAM_ERR_WINDOW;
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
                    pending_stats_q       <= 1'b1;
                    pending_stats_total_q <= stat_total_frames_q;
                    pending_stats_acl_q   <= stat_acl_blocks_q;
                    pending_stats_aes_q   <= stat_aes_frames_q;
                    pending_stats_sm4_q   <= stat_sm4_frames_q;
                    pending_stats_err_q   <= stat_error_frames_q;
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                               (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_RULE))) ||
                              frame_rule_query_q) begin
                    pending_hit_stats_q       <= 1'b1;
                    pending_hit_stats_flat_q <= acl_rule_counts_flat;
                end else if (((parser_payload_valid && (parser_payload_count == 8'd1) &&
                               (parser_payload_len == 8'd1) && (parser_payload_byte == ASCII_KEYMAP))) ||
                              frame_keymap_query_q) begin
                    pending_keymap_q      <= 1'b1;
                    pending_keymap_flat_q <= acl_rule_keys_flat;
                end else if (frame_cfg_q) begin
                    if ((!frame_cfg_key_seen_q &&
                         !(parser_payload_valid && (parser_payload_count == 8'd18))) ||
                        (((parser_payload_valid && (parser_payload_count == 8'd2)) ?
                          parser_payload_byte : frame_cfg_index_q) > 8'd7)) begin
                        pending_error_q     <= 1'b1;
                        stat_error_frames_q <= stat_error_frames_q + 8'd1;
                    end else begin
                        acl_cfg_pending_q       <= 1'b1;
                        acl_cfg_pending_index_q <= frame_cfg_index_q[2:0];
                        acl_cfg_pending_key_q   <= ((parser_payload_valid && (parser_payload_count == 8'd18)) ?
                                                     {frame_cfg_key_q[119:0], parser_payload_byte} : frame_cfg_key_q);
                        pending_cfg_ack_idx_q   <= frame_cfg_index_q[2:0];
                        pending_cfg_ack_key_q   <= ((parser_payload_valid && (parser_payload_count == 8'd18)) ?
                                                     {frame_cfg_key_q[119:0], parser_payload_byte} : frame_cfg_key_q);
                        crypto_wake_req_q       <= 1'b1;
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
                frame_bench_query_q       <= 1'b0;
                frame_bench_start_q       <= 1'b0;
                frame_bench_force_q       <= 1'b0;
                frame_bench_force_seen_q  <= 1'b0;
                frame_bench_algo_valid_q  <= 1'b0;
                frame_bench_algo_q        <= ALG_SM4;
                frame_cfg_q               <= 1'b0;
                frame_cfg_index_q         <= 8'd0;
                frame_cfg_key_q           <= 128'd0;
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

            if (axis_acl_block_pulse_w) begin
                acl_block_seen_q <= 1'b1;
                if (acl_frame_stream_q) begin
                    frame_stream_block_q      <= 1'b1;
                    frame_stream_block_slot_q <= axis_acl_block_slot_valid_w ? axis_acl_block_slot_w : 3'd0;
                    stream_session_active_q   <= 1'b0;
                    stream_expected_valid_q   <= 1'b0;
                end else begin
                    pending_block_q <= 1'b1;
                end
            end

            if (axis_in_fire_w && axis_in_pending_last_q) begin
                acl_frame_active_q <= 1'b0;
                acl_frame_algo_q   <= ALG_SM4;
                acl_frame_stream_q <= 1'b0;
            end

            if (acl_cfg_done) begin
                pending_cfg_ack_q     <= 1'b1;
            end else if (acl_cfg_error) begin
                pending_error_q     <= 1'b1;
                stat_error_frames_q <= stat_error_frames_q + 8'd1;
            end
        end
    end

endmodule
