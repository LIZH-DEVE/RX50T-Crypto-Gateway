`timescale 1ns/1ps

module tb_uart_crypto_probe_acl_short;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;

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
                $fatal(1,
                       "ACL short response mismatch expected=0x%02x actual=0x%02x bridge_in_valid=%0b bridge_in_data=0x%02x bridge_in_last=%0b acl_valid=%0b acl_data=0x%02x acl_last=%0b acl_blocked=%0b gather_count=%0d raw_pending=%0b raw_count=%0d tx_count=%0d pending_stats=%0b selector_seen=%0b proto_err=%0b",
                       expected,
                       sample,
                       dut.u_probe.bridge_in_valid_q,
                       dut.u_probe.bridge_in_data_q,
                       dut.u_probe.bridge_in_last_q,
                       dut.u_probe.acl_valid,
                       dut.u_probe.acl_data,
                       dut.u_probe.acl_last,
                       dut.u_probe.acl_blocked,
                       dut.u_probe.u_bridge.gather_count_q,
                       dut.u_probe.u_bridge.raw_pending_q,
                       dut.u_probe.u_bridge.raw_count_q,
                       dut.u_probe.u_bridge.tx_count_q,
                       dut.u_probe.pending_data_stats_q,
                       dut.u_probe.frame_selector_seen_q,
                       dut.u_probe.frame_proto_error_q);
            end
        end
    endtask

    initial begin
        rst_n   = 1'b0;
        uart_rx = 1'b1;

        #(20 * CLK_PERIODNS);
        rst_n = 1'b1;
        #(200 * CLK_PERIODNS);

        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd3);
                uart_send_byte(8'h58);
                uart_send_byte(8'h59);
                uart_send_byte(8'h5A);
            end
            begin
                uart_expect_byte(8'h44);
                uart_expect_byte(8'h0A);
            end
        join

        $display("tb_uart_crypto_probe_acl_short passed.");
        $finish;
    end

    initial begin
        #(20_000_000);
        $fatal(1,
               "tb_uart_crypto_probe_acl_short timeout: bridge_in_valid=%0b bridge_in_data=0x%02x bridge_in_last=%0b acl_valid=%0b acl_data=0x%02x acl_last=%0b acl_blocked=%0b state=%0d gather=%0d raw_pending=%0b raw_count=%0d tx_count=%0d pending_stats=%0b",
               dut.u_probe.bridge_in_valid_q,
               dut.u_probe.bridge_in_data_q,
               dut.u_probe.bridge_in_last_q,
               dut.u_probe.acl_valid,
               dut.u_probe.acl_data,
               dut.u_probe.acl_last,
               dut.u_probe.acl_blocked,
               dut.u_probe.u_acl.state_q,
               dut.u_probe.u_bridge.gather_count_q,
               dut.u_probe.u_bridge.raw_pending_q,
               dut.u_probe.u_bridge.raw_count_q,
               dut.u_probe.u_bridge.tx_count_q,
               dut.u_probe.pending_data_stats_q);
    end

    always @(posedge clk) begin
        if (dut.u_probe.acl_in_valid_q) begin
            $display("[%0t] acl_in  data=%02x last=%0b", $time, dut.u_probe.acl_in_data_q, dut.u_probe.acl_in_last_q);
        end
        if (dut.u_probe.acl_feed_valid_q) begin
            $display("[%0t] acl_feed data=%02x last=%0b key=%02x", $time, dut.u_probe.acl_feed_data_q, dut.u_probe.acl_feed_last_q, dut.u_probe.acl_feed_key_q);
        end
        if (dut.u_probe.acl_valid) begin
            $display("[%0t] acl_out data=%02x last=%0b blocked=%0b", $time, dut.u_probe.acl_data, dut.u_probe.acl_last, dut.u_probe.acl_blocked);
        end
        if (dut.u_probe.bridge_in_valid_q) begin
            $display("[%0t] bridge_in data=%02x last=%0b", $time, dut.u_probe.bridge_in_data_q, dut.u_probe.bridge_in_last_q);
        end
        if (dut.u_probe.u_bridge.bridge_valid) begin
            $display("[%0t] bridge_out data=%02x last=%0b", $time, dut.u_probe.u_bridge.bridge_data, dut.u_probe.u_bridge.bridge_last);
        end
        if (dut.u_probe.pending_data_stats_q) begin
            $display("[%0t] pending_stats key=%02x algo=%0b acl_seen=%0b", $time, dut.u_probe.pending_frame_key_q, dut.u_probe.pending_data_algo_q, dut.u_probe.acl_block_seen_q);
        end
    end

endmodule
