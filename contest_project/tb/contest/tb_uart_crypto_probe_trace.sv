`timescale 1ns/1ps

module tb_uart_crypto_probe_trace;

    localparam integer CLK_HZ          = 1_000_000;
    localparam integer BAUD            = 100_000;
    localparam integer BENCH_BYTES     = 64;
    localparam integer BENCH_TO_CLKS   = 4096;
    localparam integer CLK_PERIODNS    = 1000;
    localparam integer BIT_PERIODNS    = 10000;
    localparam integer STREAM_WDG_TIMEOUT = CLK_HZ;

    localparam logic [127:0] BLOCK_SIG = 128'h5152535455565758_595A303132333435;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    integer stage_q;

    reg [7:0]  bench_rx_bytes [0:21];
    reg [15:0] trace_meta_valid_count_q;
    reg [7:0]  trace_meta_write_ptr_q;
    reg [7:0]  trace_meta_flags_q;
    reg [63:0] trace_entries_q [0:31];
    reg [31:0] bench_bytes_be;
    reg [63:0] bench_cycles_be;
    reg [31:0] ts_prev_q;
    reg [31:0] ts_curr_q;

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
        #(400_000_000);
        $fatal(1, "tb_uart_crypto_probe_trace timeout at stage %0d ce=%0b valid=%0d write_ptr=%0d",
               stage_q,
               dut.u_probe.crypto_clk_ce_q,
               dut.u_probe.trace_valid_count_w,
               dut.u_probe.trace_write_ptr_w);
    end

    task automatic wait_clks(input integer count);
        begin
            repeat (count) @(posedge clk);
        end
    endtask

    task automatic wait_crypto_gated;
        integer cycle_idx;
        begin : WAIT_FOR_GATE
            for (cycle_idx = 0; cycle_idx < 5000; cycle_idx = cycle_idx + 1) begin
                @(posedge clk);
                if (dut.u_probe.crypto_clk_ce_q === 1'b0) begin
                    disable WAIT_FOR_GATE;
                end
            end
            $fatal(1, "crypto clock did not gate within timeout");
        end
    endtask

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
        begin : WAIT_LOOP
            forever begin
                @(negedge uart_tx);
                #(BIT_PERIODNS/2);
                if (uart_tx === 1'b0) begin
                    disable WAIT_LOOP;
                end
            end
        end
    endtask

    task automatic uart_read_byte(output [7:0] data);
        integer bit_idx;
        begin
            data = 8'd0;
            uart_wait_for_start();
            #(BIT_PERIODNS);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                data[bit_idx] = uart_tx;
                #(BIT_PERIODNS);
            end
            if (uart_tx !== 1'b1) begin
                $fatal(1, "UART stop bit invalid");
            end
        end
    endtask

    task automatic uart_expect_byte(input [7:0] expected);
        reg [7:0] actual;
        begin
            uart_read_byte(actual);
            if (actual !== expected) begin
                $fatal(1, "UART byte mismatch expected=0x%02x actual=0x%02x", expected, actual);
            end
        end
    endtask

    task automatic uart_send_acl_v2_write(input [2:0] slot, input [127:0] sig);
        integer idx;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h12);
            uart_send_byte(8'h43);
            uart_send_byte({5'd0, slot});
            for (idx = 0; idx < 16; idx = idx + 1) begin
                uart_send_byte(sig[127 - (idx * 8) -: 8]);
            end
        end
    endtask

    task automatic uart_expect_acl_v2_write_ack(input [2:0] slot, input [127:0] sig);
        integer idx;
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h12);
            uart_expect_byte(8'h43);
            uart_expect_byte({5'd0, slot});
            for (idx = 0; idx < 16; idx = idx + 1) begin
                uart_expect_byte(sig[127 - (idx * 8) -: 8]);
            end
        end
    endtask

    task automatic uart_send_raw_frame(input [127:0] payload, input integer byte_count);
        integer idx;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(byte_count[7:0]);
            for (idx = 0; idx < byte_count; idx = idx + 1) begin
                uart_send_byte(payload[127 - (idx * 8) -: 8]);
            end
        end
    endtask

    task automatic uart_send_bench_start(input [7:0] algo);
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'd2);
            uart_send_byte(8'h62);
            uart_send_byte(algo);
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

    task automatic uart_expect_bench_success;
        begin
            bench_bytes_be  = {bench_rx_bytes[6], bench_rx_bytes[7], bench_rx_bytes[8], bench_rx_bytes[9]};
            bench_cycles_be = {bench_rx_bytes[10], bench_rx_bytes[11], bench_rx_bytes[12], bench_rx_bytes[13],
                               bench_rx_bytes[14], bench_rx_bytes[15], bench_rx_bytes[16], bench_rx_bytes[17]};
            if ((bench_rx_bytes[0] !== 8'h55) ||
                (bench_rx_bytes[1] !== 8'h14) ||
                (bench_rx_bytes[2] !== 8'h62) ||
                (bench_rx_bytes[3] !== 8'h01) ||
                (bench_rx_bytes[4] !== 8'h00) ||
                (bench_rx_bytes[5] !== 8'h53) ||
                (bench_bytes_be !== BENCH_BYTES[31:0]) ||
                (bench_cycles_be == 64'd0)) begin
                $fatal(1,
                       "bench result mismatch status=%02x algo=%02x bytes=%0d cycles=%0d",
                       bench_rx_bytes[4],
                       bench_rx_bytes[5],
                       bench_bytes_be,
                       bench_cycles_be);
            end
        end
    endtask

    task automatic send_stream_start(input [7:0] algo, input [15:0] total_chunks);
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h04);
            uart_send_byte(8'h4D);
            uart_send_byte(algo);
            uart_send_byte(total_chunks[15:8]);
            uart_send_byte(total_chunks[7:0]);
        end
    endtask

    task automatic expect_stream_start_ack;
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h02);
            uart_expect_byte(8'h4D);
            uart_expect_byte(8'h00);
        end
    endtask

    task automatic expect_fatal_frame(input [7:0] code);
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h02);
            uart_expect_byte(8'hEE);
            uart_expect_byte(code);
        end
    endtask

    task automatic uart_query_trace_meta;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h01);
            uart_send_byte(8'h54);
        end
    endtask

    task automatic uart_query_trace_page(input [3:0] page_idx);
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h02);
            uart_send_byte(8'h54);
            uart_send_byte({4'd0, page_idx});
        end
    endtask

    task automatic uart_read_trace_meta;
        reg [7:0] valid_hi;
        reg [7:0] valid_lo;
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h06);
            uart_expect_byte(8'h54);
            uart_expect_byte(8'h01);
            uart_read_byte(valid_hi);
            uart_read_byte(valid_lo);
            uart_read_byte(trace_meta_write_ptr_q);
            uart_read_byte(trace_meta_flags_q);
            trace_meta_valid_count_q = {valid_hi, valid_lo};
        end
    endtask

    task automatic uart_read_trace_page(
        input [3:0] exp_page_idx,
        input [4:0] exp_entry_count,
        input [7:0] exp_flags,
        input integer base_idx
    );
        integer entry_idx;
        integer byte_idx;
        reg [7:0] data;
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h85);
            uart_expect_byte(8'h54);
            uart_expect_byte(8'h02);
            uart_expect_byte({4'd0, exp_page_idx});
            uart_expect_byte({3'd0, exp_entry_count});
            uart_expect_byte(exp_flags);
            for (entry_idx = 0; entry_idx < 16; entry_idx = entry_idx + 1) begin
                trace_entries_q[base_idx + entry_idx] = 64'd0;
                for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
                    uart_read_byte(data);
                    trace_entries_q[base_idx + entry_idx][63 - (byte_idx * 8) -: 8] = data;
                end
            end
        end
    endtask

    task automatic expect_trace_entry(
        input integer entry_idx,
        input [7:0] exp_event_code,
        input [7:0] exp_arg0,
        input [15:0] exp_arg1,
        input [31:0] prev_timestamp,
        output [31:0] timestamp_out
    );
        reg [63:0] entry_raw;
        begin
            entry_raw = trace_entries_q[entry_idx];
            timestamp_out = entry_raw[63:32];
            if ((entry_idx != 0) && (timestamp_out < prev_timestamp)) begin
                $fatal(1,
                       "Trace timestamp regressed at idx=%0d prev=%0d curr=%0d",
                       entry_idx,
                       prev_timestamp,
                       timestamp_out);
            end
            if ((entry_raw[31:24] !== exp_event_code) ||
                (entry_raw[23:16] !== exp_arg0) ||
                (entry_raw[15:0]  !== exp_arg1)) begin
                $fatal(1,
                       "Trace entry mismatch idx=%0d raw=%016x expected event=%02x arg0=%02x arg1=%04x",
                       entry_idx,
                       entry_raw,
                       exp_event_code,
                       exp_arg0,
                       exp_arg1);
            end
        end
    endtask

    initial begin
        rst_n                    = 1'b0;
        uart_rx                  = 1'b1;
        stage_q                  = 0;
        trace_meta_valid_count_q = 16'd0;
        trace_meta_write_ptr_q   = 8'd0;
        trace_meta_flags_q       = 8'd0;
        bench_bytes_be           = 32'd0;
        bench_cycles_be          = 64'd0;
        ts_prev_q                = 32'd0;
        ts_curr_q                = 32'd0;

        wait_clks(20);
        rst_n = 1'b1;

        stage_q = 1;
        wait_crypto_gated();
        $display("tb_uart_crypto_probe_trace: initial clock gate observed");

        stage_q = 2;
        fork
            begin
                uart_send_acl_v2_write(3'd3, BLOCK_SIG);
            end
            begin
                uart_expect_acl_v2_write_ack(3'd3, BLOCK_SIG);
            end
        join
        $display("tb_uart_crypto_probe_trace: ACL write ack passed");

        stage_q = 3;
        fork
            begin
                uart_send_raw_frame(BLOCK_SIG, 16);
            end
            begin
                uart_expect_byte(8'h44);
                uart_expect_byte(8'h0A);
            end
        join
        $display("tb_uart_crypto_probe_trace: ACL block response passed");

        stage_q = 4;
        fork
            begin
                uart_send_bench_start(8'h53);
            end
            begin
                uart_read_bench_result();
            end
        join
        uart_expect_bench_success();
        $display("tb_uart_crypto_probe_trace: bench run passed");

        stage_q = 5;
        fork
            begin
                send_stream_start(8'h41, 16'd1);
            end
            begin
                expect_stream_start_ack();
            end
        join
        @(negedge clk);
        force dut.u_probe.stream_wdg_counter_q = STREAM_WDG_TIMEOUT - 1;
        @(posedge clk);
        #1;
        release dut.u_probe.stream_wdg_counter_q;
        expect_fatal_frame(8'h01);
        wait_crypto_gated();
        $display("tb_uart_crypto_probe_trace: stream fatal passed");

        stage_q = 6;
        fork
            begin
                uart_query_trace_meta();
            end
            begin
                uart_read_trace_meta();
            end
        join

        if ((trace_meta_valid_count_q !== 16'd17) ||
            (trace_meta_write_ptr_q !== 8'd17) ||
            (trace_meta_flags_q !== 8'h02)) begin
            $fatal(1,
                   "trace meta mismatch valid=%0d write_ptr=%0d flags=0x%02x",
                   trace_meta_valid_count_q,
                   trace_meta_write_ptr_q,
                   trace_meta_flags_q);
        end

        stage_q = 7;
        fork
            begin
                uart_query_trace_page(4'd0);
            end
            begin
                uart_read_trace_page(4'd0, 5'd16, 8'h02, 0);
            end
        join

        stage_q = 8;
        fork
            begin
                uart_query_trace_page(4'd1);
            end
            begin
                uart_read_trace_page(4'd1, 5'd1, 8'h02, 16);
            end
        join

        expect_trace_entry(0,  8'h08, 8'h00, 16'h0000, 32'd0,    ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(1,  8'h09, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(2,  8'h08, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(3,  8'h09, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(4,  8'h07, 8'h03, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(5,  8'h08, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(6,  8'h09, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(7,  8'h03, 8'h03, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(8,  8'h08, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(9,  8'h09, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(10, 8'h05, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(11, 8'h06, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(12, 8'h08, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(13, 8'h01, 8'h01, 16'h0001, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(14, 8'h04, 8'h01, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(15, 8'h09, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;
        expect_trace_entry(16, 8'h08, 8'h00, 16'h0000, ts_prev_q, ts_curr_q); ts_prev_q = ts_curr_q;

        $display("tb_uart_crypto_probe_trace: BENCH/FATAL trace snapshot passed");
        $display("PASS: tb_uart_crypto_probe_trace ACL/BENCH/FATAL coverage verified");
        $finish;
    end

endmodule