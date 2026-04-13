`timescale 1ns/1ps

module tb_uart_crypto_probe_stream_v3;
    import crypto_vectors_pkg::*;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;
    localparam [7:0]  STREAM_ERR_STATE = 8'h02;

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
    reg [7:0] pmu_rx_bytes [0:47];
    reg       saw_credit_block_q;

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

    task automatic uart_read_byte(output [7:0] actual);
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
            actual = sample;
        end
    endtask

    task automatic uart_read_pmu_snapshot;
        integer idx;
        begin
            for (idx = 0; idx < 48; idx = idx + 1) begin
                uart_read_byte(pmu_rx_bytes[idx]);
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

    task automatic expect_stream_error(input [7:0] code);
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h02);
            uart_expect_byte(8'h45);
            uart_expect_byte(code);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            saw_credit_block_q <= 1'b0;
        end else begin
            if (dut.u_probe.stream_session_active_q &&
                (dut.u_probe.stream_seq_count_q == 4'd8) &&
                dut.u_probe.pmu_crypto_active_w &&
                dut.u_probe.pmu_stream_credit_block_w) begin
                $fatal(1, "credit_block asserted while crypto_active at full window");
            end
            if (dut.u_probe.pmu_stream_credit_block_w) begin
                saw_credit_block_q <= 1'b1;
            end
        end
    end

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

        #(20 * BIT_PERIODNS);

        stage_q = 6;
        fork
            begin
                send_stream_chunk(8'h06, AES_8BLOCK_PT);
            end
            begin
                expect_stream_error(STREAM_ERR_STATE);
            end
        join

        #(20 * BIT_PERIODNS);

        stage_q = 7;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd4);
                uart_send_byte(8'h4D);
                uart_send_byte(8'h41);
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

        stage_q = 8;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd4);
                uart_send_byte(8'h4D);
                uart_send_byte(8'h41);
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

        stage_q = 9;
        fork
            begin
                send_stream_chunk(8'h41, AES_8BLOCK_PT);
            end
            begin
                expect_stream_cipher(8'h41, AES_8BLOCK_CT);
            end
        join

        #(20 * BIT_PERIODNS);

        stage_q = 10;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd1);
                uart_send_byte(8'h50);
            end
            begin
                uart_read_pmu_snapshot();
            end
        join
        if ((pmu_rx_bytes[0] !== 8'h55) || (pmu_rx_bytes[1] !== 8'h2E) ||
            (pmu_rx_bytes[2] !== 8'h50) || (pmu_rx_bytes[3] !== 8'h01)) begin
            $fatal(1, "stream PMU snapshot header mismatch");
        end
        if ((pmu_rx_bytes[4] !== 8'h00) || (pmu_rx_bytes[5] !== 8'h0F) ||
            (pmu_rx_bytes[6] !== 8'h42) || (pmu_rx_bytes[7] !== 8'h40)) begin
            $fatal(1, "stream PMU snapshot clk_hz mismatch");
        end
        if ({pmu_rx_bytes[8], pmu_rx_bytes[9], pmu_rx_bytes[10], pmu_rx_bytes[11],
             pmu_rx_bytes[12], pmu_rx_bytes[13], pmu_rx_bytes[14], pmu_rx_bytes[15]} == 64'd0) begin
            $fatal(1, "stream PMU global cycle counter stayed at zero");
        end
        if ({pmu_rx_bytes[16], pmu_rx_bytes[17], pmu_rx_bytes[18], pmu_rx_bytes[19],
             pmu_rx_bytes[20], pmu_rx_bytes[21], pmu_rx_bytes[22], pmu_rx_bytes[23]} == 64'd0) begin
            $fatal(1, "stream PMU crypto-active counter stayed at zero");
        end
        if ({pmu_rx_bytes[40], pmu_rx_bytes[41], pmu_rx_bytes[42], pmu_rx_bytes[43],
             pmu_rx_bytes[44], pmu_rx_bytes[45], pmu_rx_bytes[46], pmu_rx_bytes[47]} != 64'd1) begin
            $fatal(1, "stream PMU ACL block event counter mismatch");
        end
        if (!saw_credit_block_q) begin
            $display("tb_uart_crypto_probe_stream_v3: credit_block window not observed in this UART-level run");
        end

        $display("uart crypto probe stream v3 test passed.");
        $finish;
    end
endmodule
