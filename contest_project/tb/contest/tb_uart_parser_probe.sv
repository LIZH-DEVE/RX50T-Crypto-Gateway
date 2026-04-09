`timescale 1ns/1ps

module tb_uart_parser_probe;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    wire dbg_in_frame;
    wire dbg_frame_start;
    wire dbg_payload_valid;
    wire [7:0] dbg_payload_byte;
    wire dbg_frame_done;
    wire dbg_error;
    wire dbg_tx_overrun;
    integer payload_pulse_count;
    integer error_pulse_count;
    integer frame_done_count;

    rx50t_uart_parser_probe_top #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) dut (
        .i_clk             (clk),
        .i_rst_n           (rst_n),
        .i_uart_rx         (uart_rx),
        .o_uart_tx         (uart_tx),
        .o_dbg_in_frame    (dbg_in_frame),
        .o_dbg_frame_start (dbg_frame_start),
        .o_dbg_payload_valid(dbg_payload_valid),
        .o_dbg_payload_byte(dbg_payload_byte),
        .o_dbg_frame_done  (dbg_frame_done),
        .o_dbg_error       (dbg_error),
        .o_dbg_tx_overrun  (dbg_tx_overrun)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIODNS/2) clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            payload_pulse_count <= 0;
            error_pulse_count   <= 0;
            frame_done_count    <= 0;
        end else begin
            if (dbg_payload_valid) begin
                payload_pulse_count <= payload_pulse_count + 1;
            end
            if (dbg_error) begin
                error_pulse_count <= error_pulse_count + 1;
            end
            if (dbg_frame_done) begin
                frame_done_count <= frame_done_count + 1;
            end
        end
    end

    task automatic uart_send_byte(input [7:0] data);
        integer idx;
        begin
            uart_rx = 1'b0;
            #(BIT_PERIODNS);
            for (idx = 0; idx < 8; idx = idx + 1) begin
                uart_rx = data[idx];
                #(BIT_PERIODNS);
            end
            uart_rx = 1'b1;
            #(BIT_PERIODNS);
        end
    endtask

    task automatic uart_expect_byte(input [7:0] expected);
        integer idx;
        reg [7:0] sample;
        begin
            sample = 8'd0;
            @(negedge uart_tx);
            #(BIT_PERIODNS + (BIT_PERIODNS/2));
            for (idx = 0; idx < 8; idx = idx + 1) begin
                sample[idx] = uart_tx;
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

    initial begin
        rst_n   = 1'b0;
        uart_rx = 1'b1;

        #(20 * CLK_PERIODNS);
        rst_n = 1'b1;
        #(20 * CLK_PERIODNS);

        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd3);
                uart_send_byte(8'h41);
                uart_send_byte(8'h42);
                uart_send_byte(8'h43);
            end
            begin
                uart_expect_byte(8'h41);
                uart_expect_byte(8'h42);
                uart_expect_byte(8'h43);
                uart_expect_byte(8'h0A);
            end
        join

        #(20 * BIT_PERIODNS);

        if (dbg_tx_overrun !== 1'b0) begin
            $fatal(1, "Unexpected TX overrun after valid frame");
        end

        fork
            begin
                uart_send_byte(8'h55);
                uart_send_byte(8'd0);
            end
            begin
                uart_expect_byte(8'h45);
                uart_expect_byte(8'h0A);
            end
        join

        #(20 * BIT_PERIODNS);

        if (dbg_error !== 1'b0) begin
            // dbg_error is a pulse, so it should be back low here.
            $fatal(1, "dbg_error stuck high");
        end

        $display("uart parser probe test passed.");
        $finish;
    end

    initial begin
        #(5_000_000);
        $fatal(1,
               "Timeout waiting for parser probe completion. payload_pulses=%0d error_pulses=%0d frame_done=%0d in_frame=%0b payload_valid=%0b payload_byte=0x%02x tx=%0b tx_valid_q=%0b tx_ready=%0b fifo_empty=%0b fifo_full=%0b fifo_wr=%0b fifo_rd=%0b pending_nl=%0b pending_err=%0b tx_state=%0d",
               payload_pulse_count,
               error_pulse_count,
               frame_done_count,
               dbg_in_frame,
               dbg_payload_valid,
               dbg_payload_byte,
               uart_tx,
               dut.u_probe.tx_valid_q,
               dut.u_probe.tx_ready,
               dut.u_probe.tx_fifo_empty,
               dut.u_probe.tx_fifo_full,
               dut.u_probe.tx_fifo_wr_en_q,
               dut.u_probe.tx_fifo_rd_en_q,
               dut.u_probe.pending_newline_q,
               dut.u_probe.pending_error_q,
               dut.u_probe.u_tx.state_q);
    end

endmodule
