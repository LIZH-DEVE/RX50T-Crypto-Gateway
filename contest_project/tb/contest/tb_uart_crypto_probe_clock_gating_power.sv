`timescale 1ns/1ps

module tb_uart_crypto_probe_clock_gating_power;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;
    localparam logic [127:0] WORK_PT = 128'h0011223344556677_8899AABBCCDDEEFF;
    localparam logic [127:0] CFG_SIG = 128'h1021324354657687_98A9BACBDCEDFE0F;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;

    rx50t_uart_crypto_probe_board_top #(
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
        #(500_000_000);
        $fatal(1, "tb_uart_crypto_probe_clock_gating_power timeout");
    end

    task automatic wait_clks(input integer n);
        begin
            repeat (n) @(posedge clk);
        end
    endtask

    task automatic uart_write_byte(input [7:0] value);
        integer bit_idx;
        begin
            uart_rx = 1'b0;
            #(BIT_PERIODNS);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx = value[bit_idx];
                #(BIT_PERIODNS);
            end
            uart_rx = 1'b1;
            #(BIT_PERIODNS);
        end
    endtask

    task automatic uart_send_frame(input integer payload_len, input logic [2047:0] payload_bits);
        integer idx;
        begin
            uart_write_byte(8'h55);
            uart_write_byte(payload_len[7:0]);
            for (idx = 0; idx < payload_len; idx = idx + 1) begin
                uart_write_byte(payload_bits[idx*8 +: 8]);
            end
            #(BIT_PERIODNS * 4);
        end
    endtask

    task automatic uart_send_raw_frame(input logic [127:0] payload_bits, input integer payload_len);
        begin
            uart_send_frame(payload_len, payload_bits);
        end
    endtask

    task automatic uart_send_acl_v2_write(input [2:0] slot, input logic [127:0] sig);
        logic [151:0] payload;
        begin
            payload = {sig, slot, 8'h43};
            uart_send_frame(18, payload);
        end
    endtask

    initial begin
        integer wake_wait;
        integer frame_idx;

        rst_n = 1'b0;
        uart_rx = 1'b1;

        wait_clks(100);
        rst_n = 1'b1;
        wait_clks(64);

        for (frame_idx = 0; frame_idx < 8; frame_idx = frame_idx + 1) begin
            uart_send_raw_frame(WORK_PT ^ frame_idx, 16);
        end

        wait_clks(4096);
        if (dut.u_top.u_probe.crypto_clk_ce_q !== 1'b0) begin
            $fatal(1, "crypto clock failed to gate during power scenario idle window");
        end

        fork
            begin
                uart_send_acl_v2_write(3'd1, CFG_SIG);
            end
            begin
                wake_wait = 0;
                while ((dut.u_top.u_probe.crypto_clk_ce_q !== 1'b1) && (wake_wait < 1024)) begin
                    wait_clks(1);
                    wake_wait = wake_wait + 1;
                end
                if (dut.u_top.u_probe.crypto_clk_ce_q !== 1'b1) begin
                    $fatal(1, "crypto clock did not wake during power scenario ACL cfg write");
                end
            end
        join

        wait_clks(256);
        $display("tb_uart_crypto_probe_clock_gating_power: PASS");
        $finish;
    end

endmodule
