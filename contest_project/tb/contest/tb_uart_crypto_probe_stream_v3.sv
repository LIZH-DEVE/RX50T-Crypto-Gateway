`timescale 1ns/1ps

module tb_uart_crypto_probe_stream_v3;
    import crypto_vectors_pkg::*;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;

    localparam logic [1023:0] AES_8BLOCK_PT = {
        128'h00112233445566778899aabbccddeeff,
        128'hffeeddccbbaa99887766554433221100,
        128'h00112233445566778899aabbccddeeff,
        128'hffeeddccbbaa99887766554433221100,
        128'h00112233445566778899aabbccddeeff,
        128'hffeeddccbbaa99887766554433221100,
        128'h00112233445566778899aabbccddeeff,
        128'hffeeddccbbaa99887766554433221100
    };
    localparam logic [1023:0] AES_8BLOCK_CT = {
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h1b872378795f4ffd772855fc87ca964d,
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h1b872378795f4ffd772855fc87ca964d,
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h1b872378795f4ffd772855fc87ca964d,
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h1b872378795f4ffd772855fc87ca964d
    };

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
        #(250_000_000);
        $fatal(1, "tb_uart_crypto_probe_stream_v3 timeout at stage %0d", stage_q);
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
                $fatal(1, "UART output mismatch. expected=0x%02x actual=0x%02x", expected, sample);
            end
        end
    endtask

    task automatic send_stream_chunk(input [7:0] seq, input logic [1023:0] payload_bits);
        integer send_idx;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h81);
            uart_send_byte(seq);
            for (send_idx = 0; send_idx < 128; send_idx = send_idx + 1) begin
                uart_send_byte(payload_bits[1023 - (send_idx*8) -: 8]);
            end
        end
    endtask

    task automatic expect_stream_cipher(input [7:0] seq, input logic [1023:0] cipher_bits);
        integer recv_idx;
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h82);
            uart_expect_byte(8'h52);
            uart_expect_byte(seq);
            for (recv_idx = 0; recv_idx < 128; recv_idx = recv_idx + 1) begin
                uart_expect_byte(cipher_bits[1023 - (recv_idx*8) -: 8]);
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
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd1);
                uart_send_byte(8'h57);
            end
            begin
                uart_expect_byte(8'h55);
                uart_expect_byte(8'h04);
                uart_expect_byte(8'h57);
                uart_expect_byte(8'h80);
                uart_expect_byte(8'h08);
                uart_expect_byte(8'h07);
            end
        join

        #(20 * BIT_PERIODNS);

        stage_q = 2;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd4);
                uart_send_byte(8'h4D);
                uart_send_byte(8'h41);
                uart_send_byte(8'h00);
                uart_send_byte(8'h04);
            end
            begin
                uart_expect_byte(8'h55);
                uart_expect_byte(8'h02);
                uart_expect_byte(8'h4D);
                uart_expect_byte(8'h00);
            end
        join

        #(20 * BIT_PERIODNS);

        stage_q = 3;
        fork
            begin
                send_stream_chunk(8'hFE, AES_8BLOCK_PT);
                send_stream_chunk(8'hFF, AES_8BLOCK_PT);
                send_stream_chunk(8'h00, AES_8BLOCK_PT);
                send_stream_chunk(8'h01, AES_8BLOCK_PT);
            end
            begin
                expect_stream_cipher(8'hFE, AES_8BLOCK_CT);
                expect_stream_cipher(8'hFF, AES_8BLOCK_CT);
                expect_stream_cipher(8'h00, AES_8BLOCK_CT);
                expect_stream_cipher(8'h01, AES_8BLOCK_CT);
            end
        join

        #(20 * BIT_PERIODNS);

        stage_q = 4;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd4);
                uart_send_byte(8'h4D);
                uart_send_byte(8'h53);
                uart_send_byte(8'h00);
                uart_send_byte(8'h01);
            end
            begin
                uart_expect_byte(8'h55);
                uart_expect_byte(8'h02);
                uart_expect_byte(8'h4D);
                uart_expect_byte(8'h00);
            end
        join

        #(20 * BIT_PERIODNS);

        stage_q = 5;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'h81);
                uart_send_byte(8'h05);
                uart_send_byte(8'h58);
                for (int send_idx = 1; send_idx < 128; send_idx = send_idx + 1) begin
                    uart_send_byte(8'h00);
                end
            end
            begin
                uart_expect_byte(8'h55);
                uart_expect_byte(8'h03);
                uart_expect_byte(8'h42);
                uart_expect_byte(8'h05);
                uart_expect_byte(8'h00);
            end
        join

        $display("uart crypto probe stream v3 test passed.");
        $finish;
    end
endmodule
