`timescale 1ns / 1ps

module tb_aes_core_encdec;
    import crypto_vectors_pkg::*;

    localparam int CLK_PERIOD_NS = 10;
    localparam int WAIT_TIMEOUT  = 500;

    logic clk = 1'b0;
    logic reset_n = 1'b0;

    logic         encdec;
    logic         init;
    logic         next;
    logic         ready;
    logic [255:0] key;
    logic         keylen;
    logic [127:0] block;
    logic [127:0] result;
    logic         result_valid;

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    aes_core dut (
        .clk(clk),
        .reset_n(reset_n),
        .encdec(encdec),
        .init(init),
        .next(next),
        .ready(ready),
        .key(key),
        .keylen(keylen),
        .block(block),
        .result(result),
        .result_valid(result_valid)
    );

    task automatic pulse_init_and_wait_ready;
        int tmo;
        begin
            init = 1'b1;
            @(posedge clk);
            init = 1'b0;
            tmo = 0;
            while ((ready !== 1'b0) && (tmo < WAIT_TIMEOUT)) begin
                @(posedge clk);
                tmo++;
            end
            if (ready !== 1'b0) $fatal(1, "[AES] key init never entered busy");
            tmo = 0;
            while ((ready !== 1'b1) && (tmo < WAIT_TIMEOUT)) begin
                @(posedge clk);
                tmo++;
            end
            if (ready !== 1'b1) $fatal(1, "[AES] key init timeout");
        end
    endtask

    task automatic pulse_next_and_wait_result;
        int tmo;
        begin
            next = 1'b1;
            @(posedge clk);
            next = 1'b0;
            tmo = 0;
            while ((ready !== 1'b0) && (tmo < WAIT_TIMEOUT)) begin
                @(posedge clk);
                tmo++;
            end
            if (ready !== 1'b0) $fatal(1, "[AES] block operation never entered busy");
            tmo = 0;
            while ((result_valid !== 1'b1) && (tmo < WAIT_TIMEOUT)) begin
                @(posedge clk);
                tmo++;
            end
            if (result_valid !== 1'b1) $fatal(1, "[AES] block result timeout");
        end
    endtask

    initial begin
        encdec = 1'b1;
        init   = 1'b0;
        next   = 1'b0;
        keylen = 1'b0; // AES-128
        key    = {AES128_KEY, 128'd0};
        block  = 128'd0;

        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        repeat (2) @(posedge clk);

        // AES-128 encrypt KAT
        encdec = 1'b1;
        pulse_init_and_wait_ready();
        block = AES128_PT;
        pulse_next_and_wait_result();
        if ((^result) === 1'bx) $fatal(1, "[AES] encrypt result contains X/Z");
        if (result !== AES128_CT) $fatal(1, "[AES] encrypt mismatch exp=%032h got=%032h", AES128_CT, result);

        // AES-128 decrypt inverse check
        encdec = 1'b0;
        pulse_init_and_wait_ready();
        block = AES128_CT;
        pulse_next_and_wait_result();
        if ((^result) === 1'bx) $fatal(1, "[AES] decrypt result contains X/Z");
        if (result !== AES128_PT) $fatal(1, "[AES] decrypt mismatch exp=%032h got=%032h", AES128_PT, result);

        $display("[PASS] tb_aes_core_encdec");
        $finish;
    end
endmodule
