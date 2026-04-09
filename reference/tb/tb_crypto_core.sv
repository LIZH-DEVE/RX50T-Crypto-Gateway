`timescale 1ns / 1ps

module tb_crypto_core;

    // --- 信号定义 ---
    logic           clk;
    logic           rst_n;
    logic           algo_sel; // 0: AES, 1: SM4
    logic           start;
    logic           done;
    logic           busy;
    logic [127:0]   key;
    logic [127:0]   din;
    logic [127:0]   dout;

    // --- 实例化 DUT (被测模块) ---
    crypto_engine u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .algo_sel   (algo_sel),
        .start      (start),
        .done       (done),
        .busy       (busy),
        .key        (key),
        .din        (din),
        .dout       (dout)
    );

    // --- 时钟生成 (100MHz) ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- 测试主流程 ---
    initial begin
        // 1. 初始化
        rst_n = 0;
        start = 0;
        algo_sel = 0;
        key = 0;
        din = 0;
        
        // 复位 100ns
        #100;
        rst_n = 1;
        #20;

        // ============================================================
        // 🧪 测试用例 1: SM4 (中国国标 GM/T 0002-2012)
        // ============================================================
        $display("\n[TEST] Starting SM4 Validation...");
        
        // 1.1 设置输入 (标准测试向量)
        algo_sel = 1'b1; // 选择 SM4
        key      = 128'h0123456789abcdeffedcba9876543210;
        din      = 128'h0123456789abcdeffedcba9876543210;
        
        // 1.2 发送启动脉冲
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;

        // 1.3 等待完成
        wait(done);
        @(posedge clk); // 多读一拍确保数据稳定

        // 1.4 自动比对结果
        // 标准结果: 681edf34d206965e86b3e94f536e4246
        if (dout == 128'h681edf34d206965e86b3e94f536e4246) begin
            $display("[PASS] SM4 Output Matches Golden Vector!");
            $display("       Result: %h", dout);
        end else begin
            $display("[FAIL] SM4 Output Mismatch!");
            $display("       Expected: 681edf34d206965e86b3e94f536e4246");
            $display("       Got     : %h", dout);
        end
        
        #100; // 两个测试之间休息一下

        // ============================================================
        // 🧪 测试用例 2: AES (NIST FIPS 197) - 回归测试
        // ============================================================
        $display("\n[TEST] Starting AES Validation (Regression)...");

        // 2.1 设置输入
        algo_sel = 1'b0; // 切回 AES
        key      = 128'h2b7e151628aed2a6abf7158809cf4f3c;
        din      = 128'h6bc1bee22e409f96e93d7e117393172a;

        // 2.2 发送启动脉冲
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;

        // 2.3 等待完成
        wait(done);
        @(posedge clk);

        // 2.4 自动比对结果
        // 标准结果: 3ad77bb40d7a3660a89ecaf32466ef97
        if (dout == 128'h3ad77bb40d7a3660a89ecaf32466ef97) begin
            $display("[PASS] AES Output Matches Golden Vector!");
            $display("       Result: %h", dout);
        end else begin
            $display("[FAIL] AES Output Mismatch!");
            $display("       Expected: 3ad77bb40d7a3660a89ecaf32466ef97");
            $display("       Got     : %h", dout);
        end

        // --- 结束仿真 ---
        #100;
        $display("\n[INFO] All Tests Completed.");
        $finish;
    end

endmodule