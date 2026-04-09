`timescale 1ns/1ps

module tb_uart_sm4_probe;
    import crypto_vectors_pkg::*;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;

    integer idx;

    rx50t_uart_sm4_probe_top #(
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

    task automatic uart_expect_byte(input [7:0] expected);
        integer bit_idx;
        reg [7:0] sample;
        begin
            sample = 8'd0;
            @(negedge uart_tx);
            #(BIT_PERIODNS + (BIT_PERIODNS/2));
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

    task automatic uart_expect_byte_timeout(
        input [7:0] expected,
        input integer timeout_bits,
        input integer stage_id
    );
        integer bit_idx;
        reg [7:0] sample;
        reg got_start;
        begin
            sample = 8'd0;
            got_start = 1'b0;

            fork : wait_for_start_or_timeout
                begin
                    @(negedge uart_tx);
                    got_start = 1'b1;
                end
                begin
                    #(timeout_bits * BIT_PERIODNS);
                end
            join_any
            disable wait_for_start_or_timeout;

            if (!got_start) begin
                $fatal(1,
                       "Timeout waiting UART byte at stage %0d. bridge_state=%0d bridge_valid=%0b bridge_data=0x%02x bridge_last=%0b tx_ready=%0b tx_state=%0d acl_valid=%0b acl_last=%0b parser_valid=%0b parser_done=%0b parser_error=%0b",
                       stage_id,
                       dut.u_probe.u_bridge.state_q,
                       dut.u_probe.bridge_valid,
                       dut.u_probe.bridge_data,
                       dut.u_probe.bridge_last,
                       dut.u_probe.tx_ready,
                       dut.u_probe.u_tx.state_q,
                       dut.u_probe.acl_valid,
                       dut.u_probe.acl_last,
                       dut.u_probe.parser_payload_valid,
                       dut.u_probe.parser_frame_done,
                       dut.u_probe.parser_error);
            end

            #(BIT_PERIODNS + (BIT_PERIODNS/2));
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                sample[bit_idx] = uart_tx;
                #(BIT_PERIODNS);
            end
            if (uart_tx !== 1'b1) begin
                $fatal(1, "UART stop bit invalid");
            end
            if (sample !== expected) begin
                $fatal(1, "UART output mismatch at stage %0d. expected=0x%02x actual=0x%02x", stage_id, expected, sample);
            end
        end
    endtask

    initial begin
        rst_n   = 1'b0;
        uart_rx = 1'b1;

        #(20 * CLK_PERIODNS);
        rst_n = 1'b1;
        #(200 * CLK_PERIODNS);

        // Blocked frame should still bypass crypto and return D\n.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd3);
                uart_send_byte(8'h58);
                uart_send_byte(8'h59);
                uart_send_byte(8'h5A);
            end
            begin
                uart_expect_byte_timeout(8'h44, 50, 1);
                uart_expect_byte_timeout(8'h0A, 50, 2);
            end
        join

        #(20 * BIT_PERIODNS);

        // Valid 16-byte SM4 frame should return the 16-byte ciphertext.
        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd16);
                for (idx = 0; idx < 16; idx = idx + 1) begin
                    uart_send_byte(SM4_PT[127 - (idx*8) -: 8]);
                end
            end
            begin
                for (idx = 0; idx < 16; idx = idx + 1) begin
                    uart_expect_byte_timeout(SM4_CT[127 - (idx*8) -: 8], 300, 100 + idx);
                end
            end
        join

        #(20 * BIT_PERIODNS);

        $display("uart sm4 probe test passed.");
        $finish;
    end

    initial begin
        #(20_000_000);
        $fatal(1,
               "Global timeout. bridge_state=%0d gather_count=%0d tx_count=%0d sm4_key_ready=%0b sm4_done=%0b tx_ready=%0b tx_state=%0d pending_err=%0b pending_err_nl=%0b frame_key_valid=%0b parser_valid=%0b parser_done=%0b parser_error=%0b acl_valid=%0b acl_last=%0b",
               dut.u_probe.u_bridge.state_q,
               dut.u_probe.u_bridge.gather_count_q,
               dut.u_probe.u_bridge.tx_count_q,
               dut.u_probe.u_bridge.sm4_key_ready,
               dut.u_probe.u_bridge.sm4_done,
               dut.u_probe.tx_ready,
               dut.u_probe.u_tx.state_q,
               dut.u_probe.pending_error_q,
               dut.u_probe.pending_error_nl_q,
               dut.u_probe.frame_key_valid_q,
               dut.u_probe.parser_payload_valid,
               dut.u_probe.parser_frame_done,
               dut.u_probe.parser_error,
               dut.u_probe.acl_valid,
               dut.u_probe.acl_last);
    end

endmodule
