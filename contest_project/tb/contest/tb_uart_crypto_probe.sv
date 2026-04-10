`timescale 1ns/1ps

module tb_uart_crypto_probe;
    import crypto_vectors_pkg::*;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;
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
    reg uart_rx;
    wire uart_tx;
    integer stage_q;

    rx50t_uart_crypto_probe_top #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) dut (
        .i_clk    (clk),
        .i_rst_n  (rst_n),
        .i_uart_rx(uart_rx),
        .o_uart_tx(uart_tx)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIODNS/2) clk = ~clk;
    end

    initial begin
        #(200_000_000);
        $fatal(1, "tb_uart_crypto_probe timeout at stage %0d", stage_q);
    end

    task automatic uart_send_byte(input [7:0] data);
        integer bit_idx;
        begin
            uart_rx = 1'b0;
            #(BIT_PERIODNS);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx = data[bit_idx];
                #(BIT_PERIODNS);
            end
            uart_rx = 1'b1;
            #(BIT_PERIODNS);
        end
    endtask

    task automatic uart_wait_for_start;
        begin : wait_loop
            forever begin
                @(negedge uart_tx);
                #(BIT_PERIODNS/2);
                if (uart_tx === 1'b0) begin
                    disable wait_loop;
                end
            end
        end
    endtask

    task automatic uart_expect_byte(input [7:0] expected);
        integer bit_idx;
        reg [7:0] sample;
        begin
            sample = 8'd0;
            uart_wait_for_start();
            #(BIT_PERIODNS);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                sample[bit_idx] = uart_tx;
                #(BIT_PERIODNS);
            end
            if (uart_tx !== 1'b1) begin
                $fatal(1, "UART stop bit invalid");
            end
            if (sample !== expected) begin
                $fatal(1,
                       "UART output mismatch. expected=0x%02x actual=0x%02x active_algo=%0b frame_algo=%0b crypto_block=%032h tx_shift=%032h tx_count=%0d acl_in_valid=%0b acl_in_data=0x%02x acl_valid=%0b acl_data=0x%02x parser_len=%0d selector_seen=%0b proto_err=%0b",
                       expected,
                       sample,
                       dut.u_probe.u_bridge.active_algo_q,
                       dut.u_probe.frame_algo_sel_q,
                       dut.u_probe.u_bridge.crypto_block_q,
                       dut.u_probe.u_bridge.tx_shift_q,
                       dut.u_probe.u_bridge.tx_count_q,
                       dut.u_probe.acl_in_valid_q,
                       dut.u_probe.acl_in_data_q,
                       dut.u_probe.acl_valid,
                       dut.u_probe.acl_data,
                       dut.u_probe.parser_payload_len,
                       dut.u_probe.frame_selector_seen_q,
                       dut.u_probe.frame_proto_error_q);
            end
        end
    endtask

    initial begin
        rst_n   = 1'b0;
        uart_rx = 1'b1;
        stage_q = 0;

        #(20 * CLK_PERIODNS);
        rst_n = 1'b1;
        #(200 * CLK_PERIODNS);

        stage_q = 1;
        // ACL blocked frame -> D\n
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd3);
                uart_send_byte(8'h58);
                uart_send_byte(8'h59);
                uart_send_byte(8'h5A);
            end
            begin
                uart_expect_byte(8'h44);
                uart_expect_byte(8'h0A);
            end
        join
        $display("tb_uart_crypto_probe: ACL block passed");

        #(20 * BIT_PERIODNS);

        stage_q = 2;
        // Default 16-byte frame -> SM4 ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd16);
                for (int send_idx = 0; send_idx < 16; send_idx = send_idx + 1) begin
                    uart_send_byte(SM4_PT[127 - (send_idx*8) -: 8]);
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 16; recv_idx = recv_idx + 1) begin
                    uart_expect_byte(SM4_CT[127 - (recv_idx*8) -: 8]);
                end
            end
        join
        $display("tb_uart_crypto_probe: SM4 16B passed");

        #(20 * BIT_PERIODNS);

        stage_q = 3;
        // Explicit AES mode: 'A' + 16-byte plaintext -> AES ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd17);
                uart_send_byte(8'h41);
                for (int send_idx = 0; send_idx < 16; send_idx = send_idx + 1) begin
                    uart_send_byte(AES128_PT[127 - (send_idx*8) -: 8]);
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 16; recv_idx = recv_idx + 1) begin
                    uart_expect_byte(AES128_CT[127 - (recv_idx*8) -: 8]);
                end
            end
        join
        $display("tb_uart_crypto_probe: AES 16B passed");

        #(20 * BIT_PERIODNS);

        stage_q = 4;
        // Default 32-byte frame -> two-block SM4 ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd32);
                for (int send_idx = 0; send_idx < 32; send_idx = send_idx + 1) begin
                    uart_send_byte(SM4_2BLOCK_PT[255 - (send_idx*8) -: 8]);
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 32; recv_idx = recv_idx + 1) begin
                    uart_expect_byte(SM4_2BLOCK_CT[255 - (recv_idx*8) -: 8]);
                end
            end
        join
        $display("tb_uart_crypto_probe: SM4 32B passed");

        #(20 * BIT_PERIODNS);

        stage_q = 5;
        // Explicit AES mode: 'A' + 32-byte plaintext -> two-block AES ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd33);
                uart_send_byte(8'h41);
                for (int send_idx = 0; send_idx < 32; send_idx = send_idx + 1) begin
                    uart_send_byte(AES_2BLOCK_PT[255 - (send_idx*8) -: 8]);
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 32; recv_idx = recv_idx + 1) begin
                    uart_expect_byte(AES_2BLOCK_CT[255 - (recv_idx*8) -: 8]);
                end
            end
        join
        $display("tb_uart_crypto_probe: AES 32B passed");

        #(20 * BIT_PERIODNS);

        stage_q = 6;
        // Default 64-byte frame -> four-block SM4 ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd64);
                for (int send_idx = 0; send_idx < 64; send_idx = send_idx + 1) begin
                    uart_send_byte(SM4_4BLOCK_PT[511 - (send_idx*8) -: 8]);
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 64; recv_idx = recv_idx + 1) begin
                    uart_expect_byte(SM4_4BLOCK_CT[511 - (recv_idx*8) -: 8]);
                end
            end
        join
        $display("tb_uart_crypto_probe: SM4 64B passed");

        #(20 * BIT_PERIODNS);

        stage_q = 7;
        // Explicit AES mode: 'A' + 64-byte plaintext -> four-block AES ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd65);
                uart_send_byte(8'h41);
                for (int send_idx = 0; send_idx < 64; send_idx = send_idx + 1) begin
                    uart_send_byte(AES_4BLOCK_PT[511 - (send_idx*8) -: 8]);
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 64; recv_idx = recv_idx + 1) begin
                    uart_expect_byte(AES_4BLOCK_CT[511 - (recv_idx*8) -: 8]);
                end
            end
        join
        $display("tb_uart_crypto_probe: AES 64B passed");

        #(20 * BIT_PERIODNS);

        stage_q = 8;
        // Default 128-byte frame -> eight-block SM4 ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd128);
                for (int send_idx = 0; send_idx < 128; send_idx = send_idx + 1) begin
                    uart_send_byte(SM4_8BLOCK_PT[1023 - (send_idx*8) -: 8]);
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 128; recv_idx = recv_idx + 1) begin
                    uart_expect_byte(SM4_8BLOCK_CT[1023 - (recv_idx*8) -: 8]);
                end
            end
        join
        $display("tb_uart_crypto_probe: SM4 128B passed");

        #(20 * BIT_PERIODNS);

        stage_q = 9;
        // Explicit AES mode: 'A' + 128-byte plaintext -> eight-block AES ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd129);
                uart_send_byte(8'h41);
                for (int send_idx = 0; send_idx < 128; send_idx = send_idx + 1) begin
                    uart_send_byte(AES_8BLOCK_PT[1023 - (send_idx*8) -: 8]);
                end
            end
            begin
                for (int recv_idx = 0; recv_idx < 128; recv_idx = recv_idx + 1) begin
                    uart_expect_byte(AES_8BLOCK_CT[1023 - (recv_idx*8) -: 8]);
                end
            end
        join
        $display("tb_uart_crypto_probe: AES 128B passed");

        #(20 * BIT_PERIODNS);

        stage_q = 10;
        // New default BRAM-backed rule: P should also block.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd3);
                uart_send_byte(8'h50);
                uart_send_byte(8'h51);
                uart_send_byte(8'h52);
            end
            begin
                uart_expect_byte(8'h44);
                uart_expect_byte(8'h0A);
            end
        join
        $display("tb_uart_crypto_probe: BRAM rule P passed");

        #(20 * BIT_PERIODNS);

        stage_q = 11;
        // Invalid explicit selector -> E\n
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd17);
                uart_send_byte(8'h51);
                for (int send_idx = 0; send_idx < 16; send_idx = send_idx + 1) begin
                    uart_send_byte(AES128_PT[127 - (send_idx*8) -: 8]);
                end
            end
            begin
                uart_expect_byte(8'h45);
                uart_expect_byte(8'h0A);
            end
        join
        $display("tb_uart_crypto_probe: invalid selector passed");

        #(20 * BIT_PERIODNS);

        stage_q = 12;
        // Add one extra BRAM-backed rule dynamically and verify the top-level
        // stats follow the ACL output instead of a hardcoded key list.
        dut.u_probe.u_acl.rule_table_q[8'h51] = 8'h01; // Q -> block
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd3);
                uart_send_byte(8'h51);
                uart_send_byte(8'h52);
                uart_send_byte(8'h53);
            end
            begin
                uart_expect_byte(8'h44);
                uart_expect_byte(8'h0A);
            end
        join
        $display("tb_uart_crypto_probe: dynamic rule Q counter query passed");

        #(20 * BIT_PERIODNS);

        stage_q = 13;
        // Query counters -> S total acl aes sm4 err \n
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd1);
                uart_send_byte(8'h48);
            end
            begin
                uart_expect_byte(8'h48);
                uart_expect_byte(8'h01);
                uart_expect_byte(8'h00);
                uart_expect_byte(8'h00);
                uart_expect_byte(8'h00);
                uart_expect_byte(8'h01);
                uart_expect_byte(8'h00);
                uart_expect_byte(8'h00);
                uart_expect_byte(8'h00);
                uart_expect_byte(8'h0A);
            end
        join
        $display("tb_uart_crypto_probe: aggregate stats query passed");

        #(20 * BIT_PERIODNS);

        stage_q = 14;
        // Query aggregate counters -> S total acl aes sm4 err \n
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd1);
                uart_send_byte(8'h3F);
            end
            begin
                uart_expect_byte(8'h53);
                uart_expect_byte(8'h0B);
                uart_expect_byte(8'h03);
                uart_expect_byte(8'h04);
                uart_expect_byte(8'h04);
                uart_expect_byte(8'h01);
                uart_expect_byte(8'h0A);
            end
        join

        #(20 * BIT_PERIODNS);

        $display("uart crypto probe test passed.");
        $finish;
    end
endmodule
