`timescale 1ns/1ps

module tb_uart_crypto_probe_watchdog;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;
    localparam integer STREAM_WDG_TIMEOUT = CLK_HZ;
    localparam integer CRYPTO_WDG_TIMEOUT = CLK_HZ / 20;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;

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
        uart_rx = 1'b1;
        $dumpfile("tb_uart_crypto_probe_watchdog.vcd");
        $dumpvars(0, tb_uart_crypto_probe_watchdog);
    end

    initial begin
        #(200_000_000);
        $display("FATAL: watchdog TB timeout");
        $fatal(1, "Watchdog TB timeout");
    end

    task automatic wait_clks(input integer n);
        begin
            repeat (n) @(posedge clk);
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

    task automatic uart_wait_for_byte(output [7:0] data, input integer timeout_ns);
        integer bit_idx;
        integer waited_ns;
        begin : WAIT_FOR_BYTE
            data = 8'hXX;
            waited_ns = 0;
            while (uart_tx !== 1'b0) begin
                if (waited_ns >= timeout_ns) begin
                    disable WAIT_FOR_BYTE;
                end
                #(CLK_PERIODNS);
                waited_ns = waited_ns + CLK_PERIODNS;
            end

            #(BIT_PERIODNS/2);
            if (uart_tx !== 1'b0) begin
                disable WAIT_FOR_BYTE;
            end

            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                #(BIT_PERIODNS);
                data[bit_idx] = uart_tx;
            end
            #(BIT_PERIODNS);
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

    task automatic expect_bytes(
        input [7:0] exp0,
        input [7:0] exp1,
        input [7:0] exp2,
        input [7:0] exp3,
        input integer timeout_ns,
        input [255:0] label
    );
        reg [7:0] b0, b1, b2, b3;
        begin
            uart_wait_for_byte(b0, timeout_ns);
            uart_wait_for_byte(b1, timeout_ns);
            uart_wait_for_byte(b2, timeout_ns);
            uart_wait_for_byte(b3, timeout_ns);
            if (b0 !== exp0 || b1 !== exp1 || b2 !== exp2 || b3 !== exp3) begin
                $display("FAIL %0s: expected %02X %02X %02X %02X, got %02X %02X %02X %02X", label, exp0, exp1, exp2, exp3, b0, b1, b2, b3);
                $fatal(1, "Unexpected UART frame");
            end
            $display("PASS %0s: %02X %02X %02X %02X", label, b0, b1, b2, b3);
        end
    endtask

    task automatic expect_stream_start_ack;
        begin
            expect_bytes(8'h55, 8'h02, 8'h4D, 8'h00, 20_000_000, "stream start ack");
        end
    endtask

    initial begin
        rst_n = 1'b0;
        wait_clks(100);
        rst_n = 1'b1;
        wait_clks(100);

        $display("[TEST 1] Stream watchdog timeout");
        send_stream_start(8'h41, 16'd1);
        expect_stream_start_ack();
        force dut.u_probe.stream_wdg_counter_q = STREAM_WDG_TIMEOUT - 1;
        wait_clks(1);
        release dut.u_probe.stream_wdg_counter_q;
        expect_bytes(8'h55, 8'h02, 8'hEE, 8'h01, 20_000_000, "stream watchdog fatal");

        wait_clks(32);

        $display("[TEST 2] Recovery after stream watchdog fatal");
        send_stream_start(8'h41, 16'd1);
        expect_stream_start_ack();

        wait_clks(32);

        $display("[TEST 3] Crypto watchdog timeout via forced block-engine busy");
        force dut.u_probe.u_axis_core.u_block_engine.worker_busy_q = 1'b1;
        force dut.u_probe.u_axis_core.u_block_engine.worker_bypass_q = 1'b0;
        force dut.u_probe.crypto_wdg_counter_q = CRYPTO_WDG_TIMEOUT - 1;
        wait_clks(1);
        release dut.u_probe.crypto_wdg_counter_q;
        wait_clks(1);
        release dut.u_probe.u_axis_core.u_block_engine.worker_busy_q;
        release dut.u_probe.u_axis_core.u_block_engine.worker_bypass_q;
        expect_bytes(8'h55, 8'h02, 8'hEE, 8'h02, 20_000_000, "crypto watchdog fatal");

        wait_clks(32);

        $display("[TEST 4] Recovery after crypto watchdog fatal");
        send_stream_start(8'h41, 16'd1);
        expect_stream_start_ack();

        $display("[ALL TESTS DONE]");
        $finish;
    end

endmodule
