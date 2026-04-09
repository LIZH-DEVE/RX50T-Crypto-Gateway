`timescale 1ns/1ps

module tb_contest_crypto_bridge;
    import crypto_vectors_pkg::*;

    localparam integer CLK_PERIODNS = 10;

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

    integer idx;

    contest_crypto_bridge dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .acl_valid    (acl_valid),
        .acl_data     (acl_data),
        .acl_last     (acl_last),
        .i_algo_sel   (algo_sel),
        .uart_tx_ready(uart_tx_ready),
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
            while (bridge_valid !== 1'b1) begin
                @(posedge clk);
            end
            if (bridge_data !== expected) begin
                $fatal(1, "bridge data mismatch exp=0x%02x got=0x%02x", expected, bridge_data);
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
        send_acl_byte(8'h44, 1'b0);
        send_acl_byte(8'h0A, 1'b1);
        expect_bridge_byte(8'h44, 1'b0);
        expect_bridge_byte(8'h0A, 1'b1);

        repeat (20) @(posedge clk);

        // 16-byte SM4 block should encrypt with the fixed test key.
        algo_sel = 1'b0;
        for (idx = 0; idx < 16; idx = idx + 1) begin
            send_acl_byte(SM4_PT[127 - (idx*8) -: 8], (idx == 15));
        end

        for (idx = 0; idx < 16; idx = idx + 1) begin
            expect_bridge_byte(SM4_CT[127 - (idx*8) -: 8], (idx == 15));
        end

        repeat (20) @(posedge clk);

        // AES 16-byte block should encrypt with the fixed AES-128 test key.
        algo_sel = 1'b1;
        for (idx = 0; idx < 16; idx = idx + 1) begin
            send_acl_byte(AES128_PT[127 - (idx*8) -: 8], (idx == 15));
        end

        for (idx = 0; idx < 16; idx = idx + 1) begin
            expect_bridge_byte(AES128_CT[127 - (idx*8) -: 8], (idx == 15));
        end

        $display("contest_crypto_bridge test passed.");
        $finish;
    end

endmodule
