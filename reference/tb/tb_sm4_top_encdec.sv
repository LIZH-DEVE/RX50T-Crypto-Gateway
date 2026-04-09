`timescale 1ns / 1ps

module tb_sm4_top_encdec;
    import crypto_vectors_pkg::*;

    localparam int CLK_PERIOD_NS = 10;
    localparam int WAIT_TIMEOUT  = 400;

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

    task automatic wait_key_ready;
        int tmo;
        begin
            tmo = 0;
            while ((key_exp_ready_out !== 1'b1) && (tmo < WAIT_TIMEOUT)) begin
                @(posedge clk);
                tmo++;
            end
            if (key_exp_ready_out !== 1'b1) $fatal(1, "[SM4] key expansion timeout");
        end
    endtask

    task automatic wait_result_ready;
        int tmo;
        begin
            tmo = 0;
            while ((ready_out !== 1'b1) && (tmo < WAIT_TIMEOUT)) begin
                @(posedge clk);
                tmo++;
            end
            if (ready_out !== 1'b1) $fatal(1, "[SM4] result timeout");
        end
    endtask

    task automatic trigger_keyexp(input logic dec_mode);
        begin
            encdec_sel_in      <= dec_mode;
            enable_key_exp_in  <= 1'b1;
            user_key_in        <= SM4_KEY;
            user_key_valid_in  <= 1'b0;
            @(posedge clk);
            user_key_valid_in  <= 1'b1;
            @(posedge clk);
            user_key_valid_in  <= 1'b0;
            wait_key_ready();
        end
    endtask

    task automatic launch_block(input logic [127:0] block_in);
        begin
            data_in   = block_in;
            valid_in  = 1'b1;
            repeat (4) @(posedge clk);
            valid_in  = 1'b0;
            @(posedge clk);
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
        repeat (3) @(posedge clk);

        // Encrypt: encdec_sel_in=0
        trigger_keyexp(1'b0);
        encdec_enable_in = 1'b1;
        repeat (2) @(posedge clk);
        launch_block(SM4_PT);
        wait_result_ready();
        if ((^result_out) === 1'bx) $fatal(1, "[SM4] encryption result contains X/Z");
        if (result_out !== SM4_CT)  $fatal(1, "[SM4] encrypt mismatch exp=%032h got=%032h", SM4_CT, result_out);

        // Re-key for decrypt: encdec_sel_in=1
        encdec_enable_in  = 1'b0;
        enable_key_exp_in = 1'b0;
        repeat (2) @(posedge clk);
        trigger_keyexp(1'b1);
        encdec_enable_in = 1'b1;
        repeat (2) @(posedge clk);
        launch_block(SM4_CT);
        wait_result_ready();
        if ((^result_out) === 1'bx) $fatal(1, "[SM4] decryption result contains X/Z");
        if (result_out !== SM4_PT)  $fatal(1, "[SM4] decrypt mismatch exp=%032h got=%032h", SM4_PT, result_out);

        $display("[PASS] tb_sm4_top_encdec");
        $finish;
    end
endmodule
