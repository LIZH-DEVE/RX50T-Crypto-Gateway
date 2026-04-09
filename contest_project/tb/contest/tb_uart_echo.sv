`timescale 1ns/1ps

module tb_uart_echo;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    wire [7:0] dbg_last_rx_byte;
    wire [7:0] dbg_last_tx_byte;
    wire dbg_rx_pulse;
    wire dbg_tx_pulse;
    wire dbg_frame_error;
    wire dbg_overrun;

    rx50t_uart_echo_top #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) dut (
        .i_clk            (clk),
        .i_rst_n          (rst_n),
        .i_uart_rx        (uart_rx),
        .o_uart_tx        (uart_tx),
        .o_dbg_last_rx_byte(dbg_last_rx_byte),
        .o_dbg_last_tx_byte(dbg_last_tx_byte),
        .o_dbg_rx_pulse   (dbg_rx_pulse),
        .o_dbg_tx_pulse   (dbg_tx_pulse),
        .o_dbg_frame_error(dbg_frame_error),
        .o_dbg_overrun    (dbg_overrun)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIODNS/2) clk = ~clk;
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
                $fatal(1, "UART echo mismatch. expected=0x%02x actual=0x%02x", expected, sample);
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
                uart_send_byte(8'h48); // H
                uart_send_byte(8'h69); // i
                uart_send_byte(8'h21); // !
            end
            begin
                uart_expect_byte(8'h48);
                uart_expect_byte(8'h69);
                uart_expect_byte(8'h21);
            end
        join

        #(20 * BIT_PERIODNS);

        if (dbg_frame_error !== 1'b0) begin
            $fatal(1, "Unexpected frame error");
        end

        if (dbg_overrun !== 1'b0) begin
            $fatal(1, "Unexpected UART overrun");
        end

        $display("UART echo test passed.");
        $finish;
    end

endmodule
