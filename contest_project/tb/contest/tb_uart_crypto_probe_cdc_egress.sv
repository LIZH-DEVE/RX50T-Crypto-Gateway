`timescale 1ns/1ps

module tb_uart_crypto_probe_cdc_egress;
    import crypto_vectors_pkg::*;

    localparam integer CLK_HZ       = 50_000_000;
    localparam integer BAUD         = 2_000_000;
    localparam integer CLK_PERIODNS = 20;
    localparam integer BIT_PERIODNS = 500;
    localparam integer BENCH_BYTES  = 64;
    localparam integer BENCH_TO_CLKS = 4096;
    localparam logic [127:0] DEFAULT_SIG0 = 128'h58595A5750525455_58595A5750525455;
    localparam logic [127:0] DEFAULT_SIG1 = 128'h0000000000000000_0000000000000000;
    localparam logic [127:0] DEFAULT_SIG2 = 128'hFFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF;
    localparam logic [127:0] DEFAULT_SIG3 = 128'h1111111111111111_2222222222222222;
    localparam logic [127:0] DEFAULT_SIG4 = 128'h3333333333333333_4444444444444444;
    localparam logic [127:0] DEFAULT_SIG5 = 128'h5555555555555555_6666666666666666;
    localparam logic [127:0] DEFAULT_SIG6 = 128'h7777777777777777_8888888888888888;
    localparam logic [127:0] DEFAULT_SIG7 = 128'h9999999999999999_AAAAAAAAAAAAAAAA;
    localparam logic [127:0] BLOCK_SIG    = 128'h5152535455565758_595A303132333435;
    localparam integer TRACE_PAGE_ENTRIES = 16;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    integer stage_q;

    reg [7:0] pmu_rx_bytes [0:87];
    reg [7:0] bench_rx_bytes [0:21];
    reg [63:0] trace_entries_q [0:15];
    reg [15:0] trace_meta_valid_count_q;
    reg [7:0] trace_meta_write_ptr_q;
    reg [7:0] trace_meta_flags_q;
    reg [31:0] bench_bytes_be;
    reg [63:0] bench_cycles_be;
    reg [7:0] max_egress_wr_level_q;

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

    function automatic [127:0] slot_signature(input integer slot, input [127:0] slot3_sig);
        begin
            case (slot)
                0: slot_signature = DEFAULT_SIG0;
                1: slot_signature = DEFAULT_SIG1;
                2: slot_signature = DEFAULT_SIG2;
                3: slot_signature = slot3_sig;
                4: slot_signature = DEFAULT_SIG4;
                5: slot_signature = DEFAULT_SIG5;
                6: slot_signature = DEFAULT_SIG6;
                7: slot_signature = DEFAULT_SIG7;
                default: slot_signature = 128'd0;
            endcase
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIODNS/2) clk = ~clk;
    end

    initial begin
        #(30_000_000);
        $fatal(1,
               "tb_uart_crypto_probe_cdc_egress timeout at stage %0d locked=%0b tx_ready=%0b tx_owner=%0d wr_level=%0d",
               stage_q,
               dut.u_probe.ingress_locked_w,
               dut.u_probe.tx_ready,
               dut.u_probe.tx_owner_q,
               dut.u_probe.u_tx_egress_bridge.o_wr_level);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            max_egress_wr_level_q <= 8'd0;
        end else if (dut.u_probe.u_tx_egress_bridge.o_wr_level > max_egress_wr_level_q) begin
            max_egress_wr_level_q <= dut.u_probe.u_tx_egress_bridge.o_wr_level;
        end
    end

    task automatic wait_clks(input integer count);
        begin
            repeat (count) @(posedge clk);
        end
    endtask

    task automatic wait_tx_egress_ready;
        integer wait_idx;
        begin
            wait_idx = 0;
            while (((dut.u_probe.ingress_locked_w !== 1'b1) ||
                    (dut.u_probe.u_tx_egress_bridge.tx_domain_ready_q !== 1'b1)) &&
                   (wait_idx < 200000)) begin
                @(posedge clk);
                wait_idx = wait_idx + 1;
            end
            if ((dut.u_probe.ingress_locked_w !== 1'b1) ||
                (dut.u_probe.u_tx_egress_bridge.tx_domain_ready_q !== 1'b1)) begin
                $fatal(1,
                       "egress startup failed locked=%0b tx_domain_ready=%0b after %0d cycles",
                       dut.u_probe.ingress_locked_w,
                       dut.u_probe.u_tx_egress_bridge.tx_domain_ready_q,
                       wait_idx);
            end
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

    task automatic uart_expect_byte(input [7:0] expected);
        reg [7:0] actual;
        begin
            uart_read_byte(actual);
            if (actual !== expected) begin
                $fatal(1, "UART mismatch expected=0x%02x actual=0x%02x", expected, actual);
            end
        end
    endtask

    task automatic uart_send_sm4_known_vector;
        integer send_idx;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'd16);
            for (send_idx = 0; send_idx < 16; send_idx = send_idx + 1) begin
                uart_send_byte(SM4_PT[127 - (send_idx * 8) -: 8]);
            end
        end
    endtask

    task automatic uart_expect_sm4_known_vector;
        integer recv_idx;
        begin
            for (recv_idx = 0; recv_idx < 16; recv_idx = recv_idx + 1) begin
                uart_expect_byte(SM4_CT[127 - (recv_idx * 8) -: 8]);
            end
        end
    endtask

    task automatic uart_send_aes_known_vector;
        integer send_idx;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'd17);
            uart_send_byte(8'h41);
            for (send_idx = 0; send_idx < 16; send_idx = send_idx + 1) begin
                uart_send_byte(AES128_PT[127 - (send_idx * 8) -: 8]);
            end
        end
    endtask

    task automatic uart_expect_aes_known_vector;
        integer recv_idx;
        begin
            for (recv_idx = 0; recv_idx < 16; recv_idx = recv_idx + 1) begin
                uart_expect_byte(AES128_CT[127 - (recv_idx * 8) -: 8]);
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

    task automatic uart_query_acl_v2_keymap;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h01);
            uart_send_byte(8'h4B);
        end
    endtask

    task automatic uart_expect_acl_v2_keymap(input [127:0] slot3_sig);
        integer idx;
        integer slot_idx;
        integer byte_off;
        reg [127:0] sig;
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h81);
            uart_expect_byte(8'h4B);
            for (idx = 0; idx < 128; idx = idx + 1) begin
                slot_idx = idx / 16;
                byte_off = idx % 16;
                sig = slot_signature(slot_idx, slot3_sig);
                uart_expect_byte(sig[127 - (byte_off * 8) -: 8]);
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
                (bench_bytes_be  == 32'd0) ||
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

    task automatic uart_query_pmu;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h01);
            uart_send_byte(8'h50);
        end
    endtask

    task automatic uart_read_pmu_snapshot;
        integer idx;
        begin
            for (idx = 0; idx < 88; idx = idx + 1) begin
                uart_read_byte(pmu_rx_bytes[idx]);
            end
        end
    endtask

    task automatic check_pmu_snapshot_header(input [63:0] exp_acl_block_events);
        reg [63:0] acl_block_events;
        begin
            acl_block_events = {pmu_rx_bytes[40], pmu_rx_bytes[41], pmu_rx_bytes[42], pmu_rx_bytes[43],
                                pmu_rx_bytes[44], pmu_rx_bytes[45], pmu_rx_bytes[46], pmu_rx_bytes[47]};
            if ((pmu_rx_bytes[0] !== 8'h55) ||
                (pmu_rx_bytes[1] !== 8'h56) ||
                (pmu_rx_bytes[2] !== 8'h50) ||
                (pmu_rx_bytes[3] !== 8'h03) ||
                (pmu_rx_bytes[4] !== 8'h02) ||
                (pmu_rx_bytes[5] !== 8'hFA) ||
                (pmu_rx_bytes[6] !== 8'hF0) ||
                (pmu_rx_bytes[7] !== 8'h80) ||
                (acl_block_events != exp_acl_block_events)) begin
                $fatal(1,
                       "PMU snapshot mismatch hdr=%02x %02x %02x %02x clk=%02x%02x%02x%02x acl=%0d",
                       pmu_rx_bytes[0], pmu_rx_bytes[1], pmu_rx_bytes[2], pmu_rx_bytes[3],
                       pmu_rx_bytes[4], pmu_rx_bytes[5], pmu_rx_bytes[6], pmu_rx_bytes[7],
                       acl_block_events);
            end
        end
    endtask

    task automatic check_pmu_snapshot_after_activity;
        reg [63:0] global_cycles;
        begin
            global_cycles = {pmu_rx_bytes[8], pmu_rx_bytes[9], pmu_rx_bytes[10], pmu_rx_bytes[11],
                             pmu_rx_bytes[12], pmu_rx_bytes[13], pmu_rx_bytes[14], pmu_rx_bytes[15]};
            check_pmu_snapshot_header(64'd1);
            if (global_cycles == 64'd0) begin
                $fatal(1, "PMU global cycle counter did not advance after activity");
            end
        end
    endtask

    task automatic uart_query_trace_meta;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h01);
            uart_send_byte(8'h54);
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

    task automatic uart_query_trace_page(input [3:0] page_idx);
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h02);
            uart_send_byte(8'h54);
            uart_send_byte({4'd0, page_idx});
        end
    endtask

    task automatic uart_read_trace_page(
        input [3:0] exp_page_idx,
        input [4:0] exp_entry_count,
        input [7:0] exp_flags
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
            for (entry_idx = 0; entry_idx < TRACE_PAGE_ENTRIES; entry_idx = entry_idx + 1) begin
                trace_entries_q[entry_idx] = 64'd0;
                for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
                    uart_read_byte(data);
                    trace_entries_q[entry_idx][63 - (byte_idx * 8) -: 8] = data;
                end
            end
        end
    endtask

    task automatic check_trace_page_nonempty(input integer entry_count);
        integer idx;
        reg [31:0] prev_ts;
        reg [31:0] curr_ts;
        begin
            prev_ts = 32'd0;
            for (idx = 0; idx < entry_count; idx = idx + 1) begin
                curr_ts = trace_entries_q[idx][63:32];
                if (trace_entries_q[idx][31:24] == 8'h00) begin
                    $fatal(1, "trace entry %0d has zero event code raw=%016x", idx, trace_entries_q[idx]);
                end
                if ((idx != 0) && (curr_ts < prev_ts)) begin
                    $fatal(1, "trace timestamp regressed idx=%0d prev=%0d curr=%0d", idx, prev_ts, curr_ts);
                end
                prev_ts = curr_ts;
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

        wait_clks(20);
        rst_n = 1'b1;
        wait_tx_egress_ready();
        wait_clks(100);

        stage_q = 1;
        fork
            begin
                uart_query_pmu();
            end
            begin
                uart_read_pmu_snapshot();
            end
        join
        check_pmu_snapshot_header(64'd0);
        $display("tb_uart_crypto_probe_cdc_egress: initial PMU snapshot passed");

        #(20 * BIT_PERIODNS);

        stage_q = 2;
        fork
            begin
                uart_send_sm4_known_vector();
            end
            begin
                uart_expect_sm4_known_vector();
            end
        join
        $display("tb_uart_crypto_probe_cdc_egress: SM4 known vector passed");

        #(20 * BIT_PERIODNS);

        stage_q = 3;
        fork
            begin
                uart_send_aes_known_vector();
            end
            begin
                uart_expect_aes_known_vector();
            end
        join
        $display("tb_uart_crypto_probe_cdc_egress: AES known vector passed");

        #(20 * BIT_PERIODNS);

        stage_q = 4;
        fork
            begin
                uart_send_acl_v2_write(3'd3, BLOCK_SIG);
            end
            begin
                uart_expect_acl_v2_write_ack(3'd3, BLOCK_SIG);
            end
        join
        $display("tb_uart_crypto_probe_cdc_egress: ACL write ack passed");

        #(20 * BIT_PERIODNS);

        stage_q = 5;
        fork
            begin
                uart_query_acl_v2_keymap();
            end
            begin
                uart_expect_acl_v2_keymap(BLOCK_SIG);
            end
        join
        $display("tb_uart_crypto_probe_cdc_egress: ACL keymap passed");

        #(20 * BIT_PERIODNS);

        stage_q = 6;
        fork
            begin
                uart_send_raw_frame(BLOCK_SIG, 16);
            end
            begin
                uart_expect_byte(8'h44);
                uart_expect_byte(8'h0A);
            end
        join
        $display("tb_uart_crypto_probe_cdc_egress: ACL block response passed");

        #(20 * BIT_PERIODNS);

        stage_q = 7;
        fork
            begin
                uart_send_bench_start(8'h53);
            end
            begin
                uart_read_bench_result();
            end
        join
        uart_expect_bench_success();
        $display("tb_uart_crypto_probe_cdc_egress: bench result passed");

        #(20 * BIT_PERIODNS);

        stage_q = 8;
        fork
            begin
                uart_query_pmu();
            end
            begin
                uart_read_pmu_snapshot();
            end
        join
        check_pmu_snapshot_after_activity();
        $display("tb_uart_crypto_probe_cdc_egress: PMU activity snapshot passed");

        #(20 * BIT_PERIODNS);

        stage_q = 9;
        fork
            begin
                uart_query_trace_meta();
            end
            begin
                uart_read_trace_meta();
            end
        join
        if ((trace_meta_valid_count_q < 16'd4) ||
            (trace_meta_write_ptr_q != trace_meta_valid_count_q[7:0]) ||
            (trace_meta_flags_q != 8'h02)) begin
            $fatal(1,
                   "trace meta mismatch valid=%0d write_ptr=%0d flags=0x%02x",
                   trace_meta_valid_count_q,
                   trace_meta_write_ptr_q,
                   trace_meta_flags_q);
        end
        $display("tb_uart_crypto_probe_cdc_egress: trace meta passed");

        #(20 * BIT_PERIODNS);

        stage_q = 10;
        fork
            begin
                uart_query_trace_page(4'd0);
            end
            begin
                uart_read_trace_page(
                    4'd0,
                    (trace_meta_valid_count_q >= TRACE_PAGE_ENTRIES) ? TRACE_PAGE_ENTRIES[4:0] : trace_meta_valid_count_q[4:0],
                    8'h02
                );
            end
        join
        check_trace_page_nonempty((trace_meta_valid_count_q >= TRACE_PAGE_ENTRIES) ? TRACE_PAGE_ENTRIES : trace_meta_valid_count_q);
        $display("tb_uart_crypto_probe_cdc_egress: trace page passed");

        if (max_egress_wr_level_q <= 8'd1) begin
            $fatal(1, "egress bridge never buffered beyond one byte, max level=%0d", max_egress_wr_level_q);
        end

        $display("PASS: tb_uart_crypto_probe_cdc_egress protocol + long-response egress CDC coverage verified");
        $finish;
    end

endmodule
