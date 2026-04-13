`timescale 1ns/1ps

module tb_contest_crypto_bridge;
    import crypto_vectors_pkg::*;

    localparam integer CLK_PERIODNS = 10;
    localparam logic [255:0] SM4_2BLOCK_PT = {
        128'h0123456789abcdeffedcba9876543210,
        128'h00112233445566778899aabbccddeeff
    };
    localparam logic [255:0] SM4_2BLOCK_CT = {
        128'h681edf34d206965e86b3e94f536e4246,
        128'h09325c4853832dcb9337a5984f671b9a
    };
    localparam logic [511:0] SM4_4BLOCK_PT = {
        128'h0123456789abcdeffedcba9876543210,
        128'h00112233445566778899aabbccddeeff,
        128'h0123456789abcdeffedcba9876543210,
        128'h00112233445566778899aabbccddeeff
    };
    localparam logic [511:0] SM4_4BLOCK_CT = {
        128'h681edf34d206965e86b3e94f536e4246,
        128'h09325c4853832dcb9337a5984f671b9a,
        128'h681edf34d206965e86b3e94f536e4246,
        128'h09325c4853832dcb9337a5984f671b9a
    };
    localparam logic [1023:0] SM4_8BLOCK_PT = {SM4_4BLOCK_PT, SM4_4BLOCK_PT};
    localparam logic [1023:0] SM4_8BLOCK_CT = {SM4_4BLOCK_CT, SM4_4BLOCK_CT};
    localparam logic [255:0] AES_2BLOCK_PT = {
        128'h00112233445566778899aabbccddeeff,
        128'hffeeddccbbaa99887766554433221100
    };
    localparam logic [255:0] AES_2BLOCK_CT = {
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h1b872378795f4ffd772855fc87ca964d
    };
    localparam logic [511:0] AES_4BLOCK_PT = {
        128'h00112233445566778899aabbccddeeff,
        128'hffeeddccbbaa99887766554433221100,
        128'h00112233445566778899aabbccddeeff,
        128'hffeeddccbbaa99887766554433221100
    };
    localparam logic [511:0] AES_4BLOCK_CT = {
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h1b872378795f4ffd772855fc87ca964d,
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h1b872378795f4ffd772855fc87ca964d
    };
    localparam logic [1023:0] AES_8BLOCK_PT = {AES_4BLOCK_PT, AES_4BLOCK_PT};
    localparam logic [1023:0] AES_8BLOCK_CT = {AES_4BLOCK_CT, AES_4BLOCK_CT};

    reg clk;
    reg rst_n;

    reg        acl_valid;
    reg [7:0]  acl_data;
    reg        acl_last;
    reg        algo_sel;
    reg        uart_tx_ready;

    wire       bridge_valid;
    wire [7:0] bridge_data;
    wire       bridge_last;
    wire       pmu_crypto_active;

    integer idx;

    contest_crypto_bridge dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .acl_valid    (acl_valid),
        .acl_data     (acl_data),
        .acl_last     (acl_last),
        .i_algo_sel   (algo_sel),
        .uart_tx_ready(uart_tx_ready),
        .o_pmu_crypto_active(pmu_crypto_active),
        .bridge_valid (bridge_valid),
        .bridge_data  (bridge_data),
        .bridge_last  (bridge_last)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIODNS/2) clk = ~clk;
    end

    task automatic send_acl_byte(input [7:0] data, input bit last_flag);
        begin
            acl_valid = 1'b1;
            acl_data  = data;
            acl_last  = last_flag;
            @(posedge clk);
            acl_valid = 1'b0;
            acl_data  = 8'd0;
            acl_last  = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic expect_bridge_byte(input [7:0] expected, input bit expected_last);
        begin
            @(posedge bridge_valid);
            #1;
            if (bridge_data !== expected) begin
                $fatal(1,
                       "bridge data mismatch exp=0x%02x got=0x%02x active_algo=%0b crypto_block=%032h sm4_done=%0b sm4_result=%032h aes_result_valid=%0b aes_result=%032h tx_shift=%032h tx_count=%0d gather_count=%0d ingress_count=%0d egress_count=%0d",
                       expected,
                       bridge_data,
                       dut.active_algo_q,
                       dut.crypto_block_q,
                       dut.sm4_done,
                       dut.sm4_result,
                       dut.aes_result_valid,
                       dut.aes_result,
                       dut.tx_shift_q,
                       dut.tx_count_q,
                       dut.gather_count_q,
                       dut.ingress_level_w,
                       dut.egress_level_w);
            end
            if (bridge_last !== expected_last) begin
                $fatal(1, "bridge last mismatch exp=%0d got=%0d", expected_last, bridge_last);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n         = 1'b0;
        acl_valid     = 1'b0;
        acl_data      = 8'd0;
        acl_last      = 1'b0;
        algo_sel      = 1'b0;
        uart_tx_ready = 1'b1;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // Give the internal key-expansion sequencer time to finish.
        repeat (120) @(posedge clk);

        // Short control frame bypass: D\n should stay D\n.
        fork
            begin
                send_acl_byte(8'h44, 1'b0);
                send_acl_byte(8'h0A, 1'b1);
            end
            begin
                expect_bridge_byte(8'h44, 1'b0);
                expect_bridge_byte(8'h0A, 1'b1);
            end
        join

        repeat (20) @(posedge clk);

        // 16-byte SM4 block should encrypt with the fixed test key.
        algo_sel = 1'b0;
        fork
            begin
                for (int send_idx = 0; send_idx < 16; send_idx = send_idx + 1) begin
                    send_acl_byte(SM4_PT[127 - (send_idx*8) -: 8], (send_idx == 15));
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 16; recv_idx = recv_idx + 1) begin
                    expect_bridge_byte(SM4_CT[127 - (recv_idx*8) -: 8], (recv_idx == 15));
                end
            end
        join

        if (pmu_crypto_active !== dut.worker_busy_q) begin
            $fatal(1, "PMU crypto-active tap mismatch after SM4 block");
        end

        repeat (20) @(posedge clk);

        // AES 16-byte block should encrypt with the fixed AES-128 test key.
        algo_sel = 1'b1;
        fork
            begin
                for (int send_idx = 0; send_idx < 16; send_idx = send_idx + 1) begin
                    send_acl_byte(AES128_PT[127 - (send_idx*8) -: 8], (send_idx == 15));
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 16; recv_idx = recv_idx + 1) begin
                    expect_bridge_byte(AES128_CT[127 - (recv_idx*8) -: 8], (recv_idx == 15));
                end
            end
        join

        if (pmu_crypto_active !== dut.worker_busy_q) begin
            $fatal(1, "PMU crypto-active tap mismatch after AES block");
        end

        repeat (20) @(posedge clk);

        // 32-byte SM4 frame should encrypt block-by-block and emit 32 ciphertext bytes.
        algo_sel = 1'b0;
        fork
            begin
                for (int send_idx = 0; send_idx < 32; send_idx = send_idx + 1) begin
                    send_acl_byte(SM4_2BLOCK_PT[255 - (send_idx*8) -: 8], (send_idx == 31));
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 32; recv_idx = recv_idx + 1) begin
                    expect_bridge_byte(SM4_2BLOCK_CT[255 - (recv_idx*8) -: 8], (recv_idx == 31));
                end
            end
        join

        repeat (20) @(posedge clk);

        // 32-byte AES frame should encrypt block-by-block and emit 32 ciphertext bytes.
        algo_sel = 1'b1;
        fork
            begin
                for (int send_idx = 0; send_idx < 32; send_idx = send_idx + 1) begin
                    send_acl_byte(AES_2BLOCK_PT[255 - (send_idx*8) -: 8], (send_idx == 31));
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 32; recv_idx = recv_idx + 1) begin
                    expect_bridge_byte(AES_2BLOCK_CT[255 - (recv_idx*8) -: 8], (recv_idx == 31));
                end
            end
        join

        repeat (20) @(posedge clk);

        // 64-byte SM4 frame should encrypt four blocks and emit 64 ciphertext bytes.
        algo_sel = 1'b0;
        fork
            begin
                for (int send_idx = 0; send_idx < 64; send_idx = send_idx + 1) begin
                    send_acl_byte(SM4_4BLOCK_PT[511 - (send_idx*8) -: 8], (send_idx == 63));
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 64; recv_idx = recv_idx + 1) begin
                    expect_bridge_byte(SM4_4BLOCK_CT[511 - (recv_idx*8) -: 8], (recv_idx == 63));
                end
            end
        join

        repeat (20) @(posedge clk);

        // 64-byte AES frame should encrypt four blocks and emit 64 ciphertext bytes.
        algo_sel = 1'b1;
        fork
            begin
                for (int send_idx = 0; send_idx < 64; send_idx = send_idx + 1) begin
                    send_acl_byte(AES_4BLOCK_PT[511 - (send_idx*8) -: 8], (send_idx == 63));
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 64; recv_idx = recv_idx + 1) begin
                    expect_bridge_byte(AES_4BLOCK_CT[511 - (recv_idx*8) -: 8], (recv_idx == 63));
                end
            end
        join

        repeat (20) @(posedge clk);

        // 128-byte SM4 frame should stream eight blocks without widening the interface.
        algo_sel = 1'b0;
        fork
            begin
                for (int send_idx = 0; send_idx < 128; send_idx = send_idx + 1) begin
                    send_acl_byte(SM4_8BLOCK_PT[1023 - (send_idx*8) -: 8], (send_idx == 127));
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 128; recv_idx = recv_idx + 1) begin
                    expect_bridge_byte(SM4_8BLOCK_CT[1023 - (recv_idx*8) -: 8], (recv_idx == 127));
                end
            end
        join

        repeat (20) @(posedge clk);

        // 128-byte AES frame should stream eight blocks without widening the interface.
        algo_sel = 1'b1;
        fork
            begin
                for (int send_idx = 0; send_idx < 128; send_idx = send_idx + 1) begin
                    send_acl_byte(AES_8BLOCK_PT[1023 - (send_idx*8) -: 8], (send_idx == 127));
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 128; recv_idx = recv_idx + 1) begin
                    expect_bridge_byte(AES_8BLOCK_CT[1023 - (recv_idx*8) -: 8], (recv_idx == 127));
                end
            end
        join

        if (pmu_crypto_active !== dut.worker_busy_q) begin
            $fatal(1, "PMU crypto-active tap mismatch at end of test");
        end

        $display("contest_crypto_bridge test passed.");
        $finish;
    end

endmodule
