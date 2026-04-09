`timescale 1ns / 1ps

module tb_sm4_keyexp_gmt;
    import crypto_vectors_pkg::*;

    localparam int CLK_PERIOD_NS = 10;
    localparam int KEYEXP_TIMEOUT = 200;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic         sm4_enable_in;
    logic         encdec_enable_in;
    logic         encdec_sel_in;
    logic         valid_in;
    logic [127:0] data_in;
    logic         enable_key_exp_in;
    logic         user_key_valid_in;
    logic [127:0] user_key_in;
    logic         key_exp_ready_out;
    logic         ready_out;
    logic [127:0] result_out;

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    sm4_top dut (
        .clk(clk),
        .reset_n(reset_n),
        .sm4_enable_in(sm4_enable_in),
        .encdec_enable_in(encdec_enable_in),
        .encdec_sel_in(encdec_sel_in),
        .valid_in(valid_in),
        .data_in(data_in),
        .enable_key_exp_in(enable_key_exp_in),
        .user_key_valid_in(user_key_valid_in),
        .user_key_in(user_key_in),
        .key_exp_ready_out(key_exp_ready_out),
        .ready_out(ready_out),
        .result_out(result_out)
    );

    task automatic clear_keyexp_flag;
        begin
            enable_key_exp_in <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic trigger_keyexp(input logic dec_mode);
        int cycles;
        begin
            encdec_sel_in      <= dec_mode;
            user_key_in        <= SM4_KEY;
            enable_key_exp_in  <= 1'b1;
            user_key_valid_in  <= 1'b0;
            @(posedge clk);
            user_key_valid_in  <= 1'b1;
            @(posedge clk);
            user_key_valid_in  <= 1'b0;

            cycles = 0;
            while ((key_exp_ready_out !== 1'b1) && (cycles < KEYEXP_TIMEOUT)) begin
                @(posedge clk);
                cycles++;
            end
            if (key_exp_ready_out !== 1'b1) begin
                $fatal(1, "[SM4-KEYEXP] timeout waiting key_exp_ready_out");
            end
        end
    endtask

    task automatic check_enc_layout;
        begin
            if (dut.u_key.rk00_out !== SM4_RK_ENC_FIRST4[0]) $fatal(1, "rk00 exp=%08h got=%08h", SM4_RK_ENC_FIRST4[0], dut.u_key.rk00_out);
            if (dut.u_key.rk01_out !== SM4_RK_ENC_FIRST4[1]) $fatal(1, "rk01 exp=%08h got=%08h", SM4_RK_ENC_FIRST4[1], dut.u_key.rk01_out);
            if (dut.u_key.rk02_out !== SM4_RK_ENC_FIRST4[2]) $fatal(1, "rk02 exp=%08h got=%08h", SM4_RK_ENC_FIRST4[2], dut.u_key.rk02_out);
            if (dut.u_key.rk03_out !== SM4_RK_ENC_FIRST4[3]) $fatal(1, "rk03 exp=%08h got=%08h", SM4_RK_ENC_FIRST4[3], dut.u_key.rk03_out);
            if (dut.u_key.rk28_out !== SM4_RK_ENC_LAST4[0])  $fatal(1, "rk28 exp=%08h got=%08h", SM4_RK_ENC_LAST4[0], dut.u_key.rk28_out);
            if (dut.u_key.rk29_out !== SM4_RK_ENC_LAST4[1])  $fatal(1, "rk29 exp=%08h got=%08h", SM4_RK_ENC_LAST4[1], dut.u_key.rk29_out);
            if (dut.u_key.rk30_out !== SM4_RK_ENC_LAST4[2])  $fatal(1, "rk30 exp=%08h got=%08h", SM4_RK_ENC_LAST4[2], dut.u_key.rk30_out);
            if (dut.u_key.rk31_out !== SM4_RK_ENC_LAST4[3])  $fatal(1, "rk31 exp=%08h got=%08h", SM4_RK_ENC_LAST4[3], dut.u_key.rk31_out);
        end
    endtask

    task automatic check_dec_layout;
        begin
            if (dut.u_key.rk00_out !== SM4_RK_DEC_FIRST4[0]) $fatal(1, "dec rk00 exp=%08h got=%08h", SM4_RK_DEC_FIRST4[0], dut.u_key.rk00_out);
            if (dut.u_key.rk01_out !== SM4_RK_DEC_FIRST4[1]) $fatal(1, "dec rk01 exp=%08h got=%08h", SM4_RK_DEC_FIRST4[1], dut.u_key.rk01_out);
            if (dut.u_key.rk02_out !== SM4_RK_DEC_FIRST4[2]) $fatal(1, "dec rk02 exp=%08h got=%08h", SM4_RK_DEC_FIRST4[2], dut.u_key.rk02_out);
            if (dut.u_key.rk03_out !== SM4_RK_DEC_FIRST4[3]) $fatal(1, "dec rk03 exp=%08h got=%08h", SM4_RK_DEC_FIRST4[3], dut.u_key.rk03_out);
            if (dut.u_key.rk28_out !== SM4_RK_DEC_LAST4[0])  $fatal(1, "dec rk28 exp=%08h got=%08h", SM4_RK_DEC_LAST4[0], dut.u_key.rk28_out);
            if (dut.u_key.rk29_out !== SM4_RK_DEC_LAST4[1])  $fatal(1, "dec rk29 exp=%08h got=%08h", SM4_RK_DEC_LAST4[1], dut.u_key.rk29_out);
            if (dut.u_key.rk30_out !== SM4_RK_DEC_LAST4[2])  $fatal(1, "dec rk30 exp=%08h got=%08h", SM4_RK_DEC_LAST4[2], dut.u_key.rk30_out);
            if (dut.u_key.rk31_out !== SM4_RK_DEC_LAST4[3])  $fatal(1, "dec rk31 exp=%08h got=%08h", SM4_RK_DEC_LAST4[3], dut.u_key.rk31_out);
        end
    endtask

    initial begin
        sm4_enable_in      = 1'b1;
        encdec_enable_in   = 1'b0;
        encdec_sel_in      = 1'b0;
        valid_in           = 1'b0;
        data_in            = 128'd0;
        enable_key_exp_in  = 1'b0;
        user_key_valid_in  = 1'b0;
        user_key_in        = 128'd0;

        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        repeat (2) @(posedge clk);

        trigger_keyexp(1'b0);
        check_enc_layout();

        clear_keyexp_flag();
        trigger_keyexp(1'b1);
        check_dec_layout();

        $display("[PASS] tb_sm4_keyexp_gmt");
        $finish;
    end
endmodule
