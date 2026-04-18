`timescale 1ns/1ps

module tb_uart_crypto_probe_cdc_ingress;
    import crypto_vectors_pkg::*;
    import contest_cdc_ingress_pkg::*;

    localparam integer CLK_HZ       = 50_000_000;
    localparam integer BAUD         = 2_000_000;
    localparam integer CLK_PERIODNS = 20;
    localparam integer BIT_PERIODNS = 500;
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
    integer wake_pulse_count_q;
    reg stage1_payload_forward_seen_q;
    reg stage2_bookkeeping_done_q;
    reg stage2_axis_core_seen_q;
    reg stage2_axis_out_seen_q;

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
        #(20_000_000);
        $display("timeout diag stage=%0d wake=%0d s2_book=%0b s2_axis_in=%0b s2_axis_out=%0b acl_active=%0b stream_active=%0b stream_fault=%0b tx_owner=%0d action_src=%0b action_dst=%0b dispatch=%0b axis_out=%0b",
                 stage_q, wake_pulse_count_q, stage2_bookkeeping_done_q, stage2_axis_core_seen_q, stage2_axis_out_seen_q,
                 dut.u_probe.acl_frame_active_q, dut.u_probe.stream_session_active_q, dut.u_probe.stream_session_fault_q,
                 dut.u_probe.tx_owner_q, dut.u_probe.cdc_action_mailbox_src_valid_q, dut.u_probe.cdc_action_mailbox_dst_valid_w,
                 dut.u_probe.cdc_dispatch_tvalid_w, dut.u_probe.axis_out_tvalid_w);
        $fatal(1, "tb_uart_crypto_probe_cdc_ingress timeout at stage %0d", stage_q);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wake_pulse_count_q <= 0;
            stage1_payload_forward_seen_q <= 1'b0;
            stage2_bookkeeping_done_q <= 1'b0;
            stage2_axis_core_seen_q <= 1'b0;
            stage2_axis_out_seen_q <= 1'b0;
        end else begin
            if (dut.u_probe.cdc_payload_root_wake_pulse_w) begin
                wake_pulse_count_q <= wake_pulse_count_q + 1;
            end
            if (stage_q != 2) begin
                stage2_bookkeeping_done_q <= 1'b0;
                stage2_axis_core_seen_q <= 1'b0;
                stage2_axis_out_seen_q <= 1'b0;
            end else begin
                if (dut.u_probe.axis_core_in_tvalid_w) begin
                    stage2_axis_core_seen_q <= 1'b1;
                end
                if (dut.u_probe.axis_out_tvalid_w) begin
                    stage2_axis_out_seen_q <= 1'b1;
                end
            end
            if (stage_q != 1) begin
                stage1_payload_forward_seen_q <= 1'b0;
            end else if (dut.u_probe.axis_core_in_tvalid_w) begin
                stage1_payload_forward_seen_q <= 1'b1;
            end
        end
    end

    task automatic wait_clks(input integer n);
        begin
            repeat (n) @(posedge clk);
        end
    endtask

    task automatic wait_crypto_gated;
        integer wait_idx;
        begin
            wait_idx = 0;
            while ((dut.u_probe.crypto_clk_ce_q !== 1'b0) && (wait_idx < 2048)) begin
                wait_clks(1);
                wait_idx = wait_idx + 1;
            end
            if (dut.u_probe.crypto_clk_ce_q !== 1'b0) begin
                $fatal(1, "crypto clock failed to gate during stage %0d", stage_q);
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

    task automatic send_normal_aes_frame;
        integer send_idx;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'd17);
            uart_send_byte(8'h41);
            for (send_idx = 0; send_idx < 16; send_idx = send_idx + 1) begin
                uart_send_byte(AES128_PT[127 - (send_idx*8) -: 8]);
            end
        end
    endtask

    task automatic expect_normal_aes_frame;
        integer recv_idx;
        begin
            for (recv_idx = 0; recv_idx < 16; recv_idx = recv_idx + 1) begin
                uart_expect_byte(AES128_CT[127 - (recv_idx*8) -: 8]);
            end
        end
    endtask

    task automatic send_stream_start(input [7:0] algo_ascii, input [15:0] total_chunks);
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'd4);
            uart_send_byte(8'h4D);
            uart_send_byte(algo_ascii);
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

    task automatic check_stream_drain_bookkeeping;
        integer wait_idx;
        begin
            wait_idx = 0;
            while ((dut.u_probe.stream_session_fault_q !== 1'b1) && (wait_idx < 100000)) begin
                wait_clks(1);
                wait_idx = wait_idx + 1;
            end
            if (dut.u_probe.stream_session_fault_q !== 1'b1) begin
                $fatal(1, "stream drain bookkeeping never faulted the session during stage %0d", stage_q);
            end
            if (dut.u_probe.frame_stream_error_code_q !== STREAM_ERR_STATE) begin
                $fatal(1, "stream drain bookkeeping produced the wrong error code during stage %0d", stage_q);
            end
        end
    endtask

    task automatic check_normal_accept_bookkeeping;
        integer wait_idx;
        begin
            wait_idx = 0;
            while ((dut.u_probe.acl_frame_active_q !== 1'b1) && (wait_idx < 100000)) begin
                wait_clks(1);
                wait_idx = wait_idx + 1;
            end
            if (dut.u_probe.acl_frame_active_q !== 1'b1) begin
                $fatal(1, "normal payload did not arm ACL frame bookkeeping during stage %0d", stage_q);
            end
            if (dut.u_probe.acl_frame_stream_q !== 1'b0) begin
                $fatal(1, "normal payload incorrectly marked itself as stream traffic during stage %0d", stage_q);
            end
            if (dut.u_probe.acl_frame_algo_q !== 1'b1) begin
                $fatal(1, "normal payload bookkeeping captured the wrong algorithm during stage %0d", stage_q);
            end
            stage2_bookkeeping_done_q = 1'b1;
        end
    endtask

    task automatic check_stream_accept_bookkeeping(input [7:0] seq, input [7:0] next_seq);
        integer wait_idx;
        begin
            wait_idx = 0;
            while (((dut.u_probe.stream_seq_count_q !== 4'd1) ||
                    (dut.u_probe.stream_expected_valid_q !== 1'b1) ||
                    (dut.u_probe.stream_expected_seq_q !== next_seq)) &&
                   (wait_idx < 100000)) begin
                wait_clks(1);
                wait_idx = wait_idx + 1;
            end
            if (dut.u_probe.stream_seq_count_q !== 4'd1) begin
                $fatal(1, "stream chunk bookkeeping did not enqueue the accepted sequence during stage %0d", stage_q);
            end
            if (dut.u_probe.stream_expected_valid_q !== 1'b1) begin
                $fatal(1, "stream chunk bookkeeping did not arm the expected-seq tracker during stage %0d", stage_q);
            end
            if (dut.u_probe.stream_expected_seq_q !== next_seq) begin
                $fatal(1, "stream chunk bookkeeping captured the wrong next sequence during stage %0d", stage_q);
            end
            if (dut.u_probe.acl_frame_stream_q !== 1'b1) begin
                $fatal(1, "stream chunk bookkeeping did not mark ACL frame as stream traffic during stage %0d", stage_q);
            end
            if (dut.u_probe.acl_frame_stream_seq_q !== seq) begin
                $fatal(1, "stream chunk bookkeeping captured the wrong stream sequence during stage %0d", stage_q);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        uart_rx = 1'b1;
        stage_q = 0;
        wake_pulse_count_q = 0;
        stage1_payload_forward_seen_q = 1'b0;
        stage2_bookkeeping_done_q = 1'b0;
        stage2_axis_core_seen_q = 1'b0;
        stage2_axis_out_seen_q = 1'b0;

        wait_clks(100);
        rst_n = 1'b1;
        wait_clks(256);
        wait_crypto_gated();

        stage_q = 1;
        fork
            begin
                send_stream_chunk(8'h05, AES_8BLOCK_PT);
            end
            begin
                expect_stream_error(STREAM_ERR_STATE);
            end
            begin
                check_stream_drain_bookkeeping();
            end
        join
        if (stage1_payload_forward_seen_q) begin
            $fatal(1, "reject stream chunk payload reached the crypto core before drain handling completed");
        end
        if (wake_pulse_count_q == 0) begin
            $fatal(1, "invalid gated stream chunk did not produce any CDC wake activity");
        end

        wait_crypto_gated();

        stage_q = 2;
        fork
            begin
                send_normal_aes_frame();
            end
            begin
                expect_normal_aes_frame();
            end
            begin
                check_normal_accept_bookkeeping();
            end
        join

        wait_crypto_gated();

        stage_q = 3;
        fork
            begin
                send_stream_start(8'h41, 16'h0001);
            end
            begin
                expect_stream_start_ack();
            end
        join

        wait_crypto_gated();

        stage_q = 4;
        fork
            begin
                send_stream_chunk(8'h00, AES_8BLOCK_PT);
            end
            begin
                expect_stream_cipher(8'h00, AES_8BLOCK_CT);
            end
            begin
                check_stream_accept_bookkeeping(8'h00, 8'h01);
            end
        join

        $display("tb_uart_crypto_probe_cdc_ingress: PASS");
        $finish;
    end

endmodule


