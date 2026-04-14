`timescale 1ns/1ps

module tb_uart_crypto_probe_onchip_bench;
    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer BENCH_BYTES  = 64;
    localparam integer BENCH_TO_CLKS = 4096;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    integer stage_q;
    reg [7:0] bench_rx_bytes [0:21];
    reg [7:0] bench_rx_bytes_2 [0:21];
    reg [7:0] bench_rx_bytes_3 [0:21];
    reg [7:0] bench_rx_bytes_4 [0:21];
    reg [7:0] stream_ack_bytes [0:3];
    reg [31:0] bench_bytes_be;
    reg [63:0] bench_cycles_be;
    reg [31:0] bench_crc32_be;
    reg [31:0] bench_bytes_be_2;
    reg [63:0] bench_cycles_be_2;
    reg [31:0] bench_crc32_be_2;
    event bench_response_started;

    rx50t_uart_crypto_probe_top #(
        .CLK_HZ            (CLK_HZ),
        .BAUD              (BAUD),
        .BENCH_TOTAL_BYTES (BENCH_BYTES),
        .BENCH_TIMEOUT_CLKS(BENCH_TO_CLKS)
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
        #(150_000_000);
        $fatal(1,
               "tb_uart_crypto_probe_onchip_bench timeout at stage %0d state=%0d bytes_in=%0d bytes_out=%0d tx_idx=%0d",
               stage_q,
               dut.u_probe.bench_state_q,
               dut.u_probe.bench_bytes_in_q,
               dut.u_probe.bench_bytes_out_q,
               dut.u_probe.bench_tx_idx_q);
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

    task automatic uart_read_bench_result;
        integer idx;
        begin
            for (idx = 0; idx < 22; idx = idx + 1) begin
                uart_read_byte(bench_rx_bytes[idx]);
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
                uart_send_byte(8'h62);
            end
            begin
                uart_read_bench_result();
            end
        join

        if ((bench_rx_bytes[0] !== 8'h55) ||
            (bench_rx_bytes[1] !== 8'h14) ||
            (bench_rx_bytes[2] !== 8'h62) ||
            (bench_rx_bytes[3] !== 8'h01) ||
            (bench_rx_bytes[4] !== 8'h04)) begin
            $fatal(1,
                   "bench query after reset should return NO_RESULT frame. got=%02x %02x %02x %02x %02x",
                   bench_rx_bytes[0],
                   bench_rx_bytes[1],
                   bench_rx_bytes[2],
                   bench_rx_bytes[3],
                   bench_rx_bytes[4]);
        end

        $display("tb_uart_crypto_probe_onchip_bench: initial NO_RESULT query passed");

        stage_q = 2;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd2);
                uart_send_byte(8'h62);
                uart_send_byte(8'h53);
            end
            begin
                uart_read_bench_result();
            end
        join

        bench_bytes_be  = {bench_rx_bytes[6], bench_rx_bytes[7], bench_rx_bytes[8], bench_rx_bytes[9]};
        bench_cycles_be = {bench_rx_bytes[10], bench_rx_bytes[11], bench_rx_bytes[12], bench_rx_bytes[13],
                           bench_rx_bytes[14], bench_rx_bytes[15], bench_rx_bytes[16], bench_rx_bytes[17]};
        bench_crc32_be  = {bench_rx_bytes[18], bench_rx_bytes[19], bench_rx_bytes[20], bench_rx_bytes[21]};

        if ((bench_rx_bytes[0] !== 8'h55) ||
            (bench_rx_bytes[1] !== 8'h14) ||
            (bench_rx_bytes[2] !== 8'h62) ||
            (bench_rx_bytes[3] !== 8'h01) ||
            (bench_rx_bytes[4] !== 8'h00) ||
            (bench_rx_bytes[5] !== 8'h53) ||
            (bench_bytes_be !== BENCH_BYTES[31:0]) ||
            (bench_cycles_be == 64'd0)) begin
            $fatal(1,
                   "bench run should return SUCCESS with %0d bytes. got status=%02x algo=%02x bytes=%0d cycles=%0d",
                   BENCH_BYTES,
                   bench_rx_bytes[4],
                   bench_rx_bytes[5],
                   bench_bytes_be,
                   bench_cycles_be);
        end

        stage_q = 3;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd1);
                uart_send_byte(8'h62);
            end
            begin
                for (integer idx = 0; idx < 22; idx = idx + 1) begin
                    uart_read_byte(bench_rx_bytes_2[idx]);
                end
            end
        join

        bench_bytes_be_2  = {bench_rx_bytes_2[6], bench_rx_bytes_2[7], bench_rx_bytes_2[8], bench_rx_bytes_2[9]};
        bench_cycles_be_2 = {bench_rx_bytes_2[10], bench_rx_bytes_2[11], bench_rx_bytes_2[12], bench_rx_bytes_2[13],
                             bench_rx_bytes_2[14], bench_rx_bytes_2[15], bench_rx_bytes_2[16], bench_rx_bytes_2[17]};
        bench_crc32_be_2  = {bench_rx_bytes_2[18], bench_rx_bytes_2[19], bench_rx_bytes_2[20], bench_rx_bytes_2[21]};

        if ((bench_rx_bytes_2[4] !== 8'h00) ||
            (bench_rx_bytes_2[5] !== 8'h53) ||
            (bench_bytes_be_2 !== bench_bytes_be) ||
            (bench_cycles_be_2 !== bench_cycles_be) ||
            (bench_crc32_be_2 !== bench_crc32_be)) begin
            $fatal(1,
                   "bench latest-result query mismatch. status=%02x algo=%02x bytes=%0d cycles=%0d crc=%08x expected bytes=%0d cycles=%0d crc=%08x",
                   bench_rx_bytes_2[4],
                   bench_rx_bytes_2[5],
                   bench_bytes_be_2,
                   bench_cycles_be_2,
                   bench_crc32_be_2,
                   bench_bytes_be,
                   bench_cycles_be,
                   bench_crc32_be);
        end

        $display("tb_uart_crypto_probe_onchip_bench: run + latest result query passed");

        stage_q = 4;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd2);
                uart_send_byte(8'h62);
                uart_send_byte(8'h53);
            end
            begin
                @bench_response_started;
                #(4 * 10 * BIT_PERIODNS);
                uart_send_byte(8'h55);
                uart_send_byte(8'd1);
                uart_send_byte(8'h62);
            end
            begin
                for (integer idx = 0; idx < 22; idx = idx + 1) begin
                    uart_read_byte(bench_rx_bytes_3[idx]);
                    if (idx == 0) begin
                        -> bench_response_started;
                    end
                end
                for (integer idx = 0; idx < 22; idx = idx + 1) begin
                    uart_read_byte(bench_rx_bytes_4[idx]);
                end
            end
        join

        if ((bench_rx_bytes_3[0] !== 8'h55) ||
            (bench_rx_bytes_3[1] !== 8'h14) ||
            (bench_rx_bytes_3[2] !== 8'h62) ||
            (bench_rx_bytes_3[3] !== 8'h01) ||
            (bench_rx_bytes_3[4] !== 8'h00) ||
            (bench_rx_bytes_3[5] !== 8'h53)) begin
            $fatal(1,
                   "mid-frame bench query corrupted first bench result. got=%02x %02x %02x %02x %02x %02x",
                   bench_rx_bytes_3[0],
                   bench_rx_bytes_3[1],
                   bench_rx_bytes_3[2],
                   bench_rx_bytes_3[3],
                   bench_rx_bytes_3[4],
                   bench_rx_bytes_3[5]);
        end

        for (integer idx = 0; idx < 22; idx = idx + 1) begin
            if (bench_rx_bytes_4[idx] !== bench_rx_bytes_3[idx]) begin
                $fatal(1,
                       "mid-frame bench query should queue a clean second result. idx=%0d first=%02x second=%02x",
                       idx,
                       bench_rx_bytes_3[idx],
                       bench_rx_bytes_4[idx]);
            end
        end

        $display("tb_uart_crypto_probe_onchip_bench: bench serializer atomicity passed");

        stage_q = 5;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h20);
            uart_send_byte(8'h01);
            uart_send_byte(8'h23);
            uart_send_byte(8'h45);
            uart_send_byte(8'h67);
            uart_send_byte(8'h89);
            uart_send_byte(8'hAB);
            uart_send_byte(8'hCD);
            uart_send_byte(8'hEF);
            #(10 * 10 * BIT_PERIODNS);
        end

        if (dut.u_probe.acl_frame_active_q !== 1'b1) begin
            $fatal(1, "partial timed-out frame should leave datapath busy before force recovery");
        end

        stage_q = 6;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd3);
                uart_send_byte(8'h62);
                uart_send_byte(8'hFF);
                uart_send_byte(8'h53);
            end
            begin
                uart_read_bench_result();
            end
        join

        bench_bytes_be  = {bench_rx_bytes[6], bench_rx_bytes[7], bench_rx_bytes[8], bench_rx_bytes[9]};
        bench_cycles_be = {bench_rx_bytes[10], bench_rx_bytes[11], bench_rx_bytes[12], bench_rx_bytes[13],
                           bench_rx_bytes[14], bench_rx_bytes[15], bench_rx_bytes[16], bench_rx_bytes[17]};
        bench_crc32_be  = {bench_rx_bytes[18], bench_rx_bytes[19], bench_rx_bytes[20], bench_rx_bytes[21]};

        if ((bench_rx_bytes[4] !== 8'h00) ||
            (bench_rx_bytes[5] !== 8'h53) ||
            (bench_bytes_be !== BENCH_BYTES[31:0]) ||
            (bench_cycles_be == 64'd0) ||
            (bench_crc32_be !== bench_crc32_be_2)) begin
            $fatal(1,
                   "force bench run should flush poisoned datapath and reproduce the same CRC. status=%02x algo=%02x bytes=%0d cycles=%0d crc=%08x ref_crc=%08x",
                   bench_rx_bytes[4],
                   bench_rx_bytes[5],
                   bench_bytes_be,
                   bench_cycles_be,
                   bench_crc32_be,
                   bench_crc32_be_2);
        end

        $display("tb_uart_crypto_probe_onchip_bench: force flush of poisoned datapath passed");

        stage_q = 7;
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
                for (integer idx = 0; idx < 4; idx = idx + 1) begin
                    uart_read_byte(stream_ack_bytes[idx]);
                end
            end
        join

        if ((stream_ack_bytes[0] !== 8'h55) ||
            (stream_ack_bytes[1] !== 8'h02) ||
            (stream_ack_bytes[2] !== 8'h4D) ||
            (stream_ack_bytes[3] !== 8'h00)) begin
            $fatal(1,
                   "stream start ack mismatch. got=%02x %02x %02x %02x",
                   stream_ack_bytes[0],
                   stream_ack_bytes[1],
                   stream_ack_bytes[2],
                   stream_ack_bytes[3]);
        end

        stage_q = 8;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd2);
                uart_send_byte(8'h62);
                uart_send_byte(8'h53);
            end
            begin
                uart_read_bench_result();
            end
        join

        if ((bench_rx_bytes[4] !== 8'h01) || (bench_rx_bytes[5] !== 8'h53)) begin
            $fatal(1,
                   "busy bench run should return BUSY. got status=%02x algo=%02x",
                   bench_rx_bytes[4],
                   bench_rx_bytes[5]);
        end

        stage_q = 9;
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd3);
                uart_send_byte(8'h62);
                uart_send_byte(8'hFF);
                uart_send_byte(8'h53);
            end
            begin
                uart_read_bench_result();
            end
        join

        bench_bytes_be  = {bench_rx_bytes[6], bench_rx_bytes[7], bench_rx_bytes[8], bench_rx_bytes[9]};
        bench_cycles_be = {bench_rx_bytes[10], bench_rx_bytes[11], bench_rx_bytes[12], bench_rx_bytes[13],
                           bench_rx_bytes[14], bench_rx_bytes[15], bench_rx_bytes[16], bench_rx_bytes[17]};

        if ((bench_rx_bytes[4] !== 8'h00) ||
            (bench_rx_bytes[5] !== 8'h53) ||
            (bench_bytes_be !== BENCH_BYTES[31:0]) ||
            (bench_cycles_be == 64'd0)) begin
            $fatal(1,
                   "force bench run should recover and succeed. got status=%02x algo=%02x bytes=%0d cycles=%0d",
                   bench_rx_bytes[4],
                   bench_rx_bytes[5],
                   bench_bytes_be,
                   bench_cycles_be);
        end

        $display("tb_uart_crypto_probe_onchip_bench: busy + force-run recovery passed");
        #(20 * BIT_PERIODNS);
        $display("tb_uart_crypto_probe_onchip_bench passed.");
        $finish;
    end
endmodule
