`timescale 1ns/1ps

module tb_uart_crypto_probe_clock_gating;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;
    localparam logic [127:0] CFG_SIG = 128'h5152535455565758_595A303132333435;

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
        #(200_000_000);
        $fatal(1, "tb_uart_crypto_probe_clock_gating timeout");
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

    initial begin
        rst_n = 1'b0;
        uart_rx = 1'b1;

        wait_clks(100);
        rst_n = 1'b1;
        wait_clks(128);

        if (dut.u_probe.crypto_clk_ce_q !== 1'b0) begin
            $fatal(1, "crypto clock failed to gate after idle window");
        end

        fork
            begin
                uart_send_acl_v2_write(3'd2, CFG_SIG);
            end
            begin
                uart_expect_acl_v2_write_ack(3'd2, CFG_SIG);
            end
            begin
                integer wake_wait;
                wake_wait = 0;
                while ((dut.u_probe.crypto_clk_ce_q !== 1'b1) && (wake_wait < 512)) begin
                    wait_clks(1);
                    wake_wait = wake_wait + 1;
                end
                if (dut.u_probe.crypto_clk_ce_q !== 1'b1) begin
                    $fatal(1, "crypto clock did not wake for ACL cfg write");
                end
            end
        join

        wait_clks(128);
        if (dut.u_probe.crypto_clk_ce_q !== 1'b0) begin
            $fatal(1, "crypto clock failed to re-gate after ACL cfg write");
        end

        $display("tb_uart_crypto_probe_clock_gating: PASS");
        $finish;
    end

endmodule
