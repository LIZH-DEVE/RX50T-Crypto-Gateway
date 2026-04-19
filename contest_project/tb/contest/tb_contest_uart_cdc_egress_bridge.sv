`timescale 1ns/1ps

module tb_contest_uart_cdc_egress_bridge;

    localparam integer ROOT_PERIOD_NS       = 20;
    localparam integer EGRESS_PERIOD_NS     = 8;
    localparam integer BAUD                 = 2_000_000;
    localparam integer BIT_PERIOD_NS        = 500;
    localparam integer DEPTH                = 128;
    localparam integer ALMOST_FULL_MARGIN   = 8;
    localparam integer FRAME_BYTES          = 160;
    localparam integer SIM_TIMEOUT_NS       = 2_500_000;

    reg root_clk = 1'b0;
    reg egress_clk = 1'b0;
    reg root_rst_n_async = 1'b0;
    reg egress_rst_n_async = 1'b0;
    reg in_valid = 1'b0;
    wire in_ready;
    reg [7:0] in_data = 8'd0;
    wire uart_tx;
    wire wr_full;
    wire wr_almost_full;
    wire rd_empty;
    wire [$clog2(DEPTH):0] wr_level;

    integer tx_idx = 0;
    integer rx_idx = 0;
    integer max_wr_level_q = 0;
    integer almost_full_trip_level_q = -1;
    reg prev_hold_valid_q = 1'b0;
    reg [7:0] prev_hold_data_q = 8'd0;

    contest_uart_cdc_egress_bridge #(
        .EGRESS_CLK_HZ      (125_000_000),
        .BAUD               (BAUD),
        .DEPTH              (DEPTH),
        .ALMOST_FULL_MARGIN (ALMOST_FULL_MARGIN)
    ) dut (
        .i_root_clk         (root_clk),
        .i_root_rst_n_async (root_rst_n_async),
        .i_egress_clk       (egress_clk),
        .i_egress_rst_n_async(egress_rst_n_async),
        .i_valid            (in_valid),
        .o_ready            (in_ready),
        .i_data             (in_data),
        .o_uart_tx          (uart_tx),
        .o_wr_full          (wr_full),
        .o_wr_almost_full   (wr_almost_full),
        .o_rd_empty         (rd_empty),
        .o_wr_level         (wr_level)
    );

    always #(ROOT_PERIOD_NS/2) root_clk = ~root_clk;
    always #(EGRESS_PERIOD_NS/2) egress_clk = ~egress_clk;

    initial begin
        #SIM_TIMEOUT_NS;
        $fatal(1, "tb_contest_uart_cdc_egress_bridge timeout tx=%0d rx=%0d ready=%0b level=%0d trip=%0d",
                 tx_idx, rx_idx, dut.tx_domain_ready_q, wr_level, almost_full_trip_level_q);
    end

    task automatic uart_wait_for_start;
        begin : wait_loop
            forever begin
                @(negedge uart_tx);
                #(BIT_PERIOD_NS/2);
                if (uart_tx === 1'b0) begin
                    disable wait_loop;
                end
            end
        end
    endtask

    task automatic uart_read_byte(output [7:0] data);
        integer bit_idx;
        begin
            data = 8'd0;
            uart_wait_for_start();
            #(BIT_PERIOD_NS);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                data[bit_idx] = uart_tx;
                #(BIT_PERIOD_NS);
            end
            if (uart_tx !== 1'b1) begin
                $fatal(1, "egress UART stop bit invalid");
            end
        end
    endtask

    task automatic drive_byte(input [7:0] data_value);
        begin
            @(negedge root_clk);
            in_valid <= 1'b1;
            in_data  <= data_value;
            do begin
                @(posedge root_clk);
            end while (!(in_valid && in_ready));
            @(negedge root_clk);
            in_valid <= 1'b0;
            in_data  <= 8'd0;
        end
    endtask

    always @(posedge root_clk) begin
        if (!root_rst_n_async || !egress_rst_n_async) begin
            max_wr_level_q <= 0;
            almost_full_trip_level_q <= -1;
        end else begin
            if (wr_level > max_wr_level_q[$bits(wr_level)-1:0]) begin
                max_wr_level_q <= wr_level;
            end
            if ((almost_full_trip_level_q < 0) && wr_almost_full) begin
                almost_full_trip_level_q <= wr_level;
            end
            if (!dut.tx_domain_ready_q && (wr_level != 0)) begin
                $fatal(1, "bridge accepted data before tx_domain_ready went high");
            end
        end
    end

    always @(posedge egress_clk) begin
        if (prev_hold_valid_q && dut.afifo_m_tvalid_w) begin
            if (dut.afifo_m_tdata_w !== prev_hold_data_q) begin
                $fatal(1, "bridge changed AFIFO output data while UART TX backpressured it");
            end
        end

        prev_hold_valid_q <= dut.afifo_m_tvalid_w && !dut.afifo_m_tready_w;
        if (dut.afifo_m_tvalid_w && !dut.afifo_m_tready_w) begin
            prev_hold_data_q <= dut.afifo_m_tdata_w;
        end
    end

    initial begin
        reg [7:0] actual;

        repeat (8) @(posedge root_clk);
        in_valid <= 1'b1;
        in_data  <= 8'hA5;
        repeat (6) @(posedge root_clk);
        if (wr_level != 0 || dut.tx_domain_ready_q) begin
            $fatal(1, "startup gating failed before release ready=%0b level=%0d", dut.tx_domain_ready_q, wr_level);
        end
        in_valid <= 1'b0;
        in_data  <= 8'd0;

        root_rst_n_async   <= 1'b1;
        egress_rst_n_async <= 1'b1;

        wait (dut.tx_domain_ready_q == 1'b1);
        repeat (4) @(posedge root_clk);

        fork
            begin
                for (tx_idx = 0; tx_idx < FRAME_BYTES; tx_idx = tx_idx + 1) begin
                    drive_byte(8'h40 + tx_idx[7:0]);
                end
            end
            begin
                for (rx_idx = 0; rx_idx < FRAME_BYTES; rx_idx = rx_idx + 1) begin
                    uart_read_byte(actual);
                    if (actual !== (8'h40 + rx_idx[7:0])) begin
                        $fatal(1, "egress UART byte mismatch idx=%0d exp=0x%02x got=0x%02x", rx_idx, (8'h40 + rx_idx[7:0]), actual);
                    end
                end
            end
        join

        repeat (8) @(posedge root_clk);

        if (almost_full_trip_level_q < (DEPTH - ALMOST_FULL_MARGIN)) begin
            $fatal(1, "bridge never reached almost_full threshold trip=%0d", almost_full_trip_level_q);
        end
        if (max_wr_level_q > DEPTH) begin
            $fatal(1, "bridge FIFO overfilled max_level=%0d", max_wr_level_q);
        end
        if ((max_wr_level_q - almost_full_trip_level_q) > 3) begin
            $fatal(1, "bridge overshoot too large max=%0d trip=%0d", max_wr_level_q, almost_full_trip_level_q);
        end
        if (!rd_empty || (wr_level != 0)) begin
            $fatal(1, "bridge failed to drain cleanly rd_empty=%0b wr_level=%0d", rd_empty, wr_level);
        end

        $display("tb_contest_uart_cdc_egress_bridge: PASS");
        $finish;
    end

endmodule
