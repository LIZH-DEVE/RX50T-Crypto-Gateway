`timescale 1ns/1ps

module tb_uart_crypto_probe_acl_v2;

    localparam integer CLK_HZ       = 1_000_000;
    localparam integer BAUD         = 100_000;
    localparam integer CLK_PERIODNS = 1000;
    localparam integer BIT_PERIODNS = 10000;

    localparam logic [127:0] DEFAULT_SIG0 = 128'h58595A5750525455_58595A5750525455;
    localparam logic [127:0] DEFAULT_SIG1 = 128'h0000000000000000_0000000000000000;
    localparam logic [127:0] DEFAULT_SIG2 = 128'hFFFFFFFFFFFFFFFF_FFFFFFFFFFFFFFFF;
    localparam logic [127:0] DEFAULT_SIG3 = 128'h1111111111111111_2222222222222222;
    localparam logic [127:0] DEFAULT_SIG4 = 128'h3333333333333333_4444444444444444;
    localparam logic [127:0] DEFAULT_SIG5 = 128'h5555555555555555_6666666666666666;
    localparam logic [127:0] DEFAULT_SIG6 = 128'h7777777777777777_8888888888888888;
    localparam logic [127:0] DEFAULT_SIG7 = 128'h9999999999999999_AAAAAAAAAAAAAAAA;
    localparam logic [127:0] BLOCK_SIG    = 128'h5152535455565758_595A303132333435;
    localparam logic [127:0] BENIGN_PT    = 128'h0123456789abcdeffedcba9876543210;
    localparam logic [127:0] BENIGN_CT    = 128'h681edf34d206965e86b3e94f536e4246;

    reg clk;
    reg rst_n;
    reg uart_rx;
    wire uart_tx;
    integer stage_q;

    rx50t_uart_crypto_probe_top #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
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

    function automatic [31:0] slot_hit_count(input integer slot, input [31:0] slot3_count);
        begin
            case (slot)
                3: slot_hit_count = slot3_count;
                default: slot_hit_count = 32'd0;
            endcase
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIODNS/2) clk = ~clk;
    end

            initial begin
        #(300_000_000);
        $fatal(1, "tb_uart_crypto_probe_acl_v2 timeout at stage %0d", stage_q);
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

    task automatic uart_query_acl_v2_hits;
        begin
            uart_send_byte(8'h55);
            uart_send_byte(8'h01);
            uart_send_byte(8'h48);
        end
    endtask

    task automatic uart_expect_acl_v2_hits(input [31:0] slot3_count);
        integer idx;
        integer slot_idx;
        integer byte_off;
        reg [31:0] count;
        begin
            uart_expect_byte(8'h55);
            uart_expect_byte(8'h21);
            uart_expect_byte(8'h48);
            for (idx = 0; idx < 32; idx = idx + 1) begin
                slot_idx = idx / 4;
                byte_off = idx % 4;
                count = slot_hit_count(slot_idx, slot3_count);
                uart_expect_byte(count[31 - (byte_off * 8) -: 8]);
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

    task automatic uart_expect_raw_frame(input [127:0] payload, input integer byte_count);
        integer idx;
        begin
            for (idx = 0; idx < byte_count; idx = idx + 1) begin
                uart_expect_byte(payload[127 - (idx * 8) -: 8]);
            end
        end
    endtask

    initial begin
        rst_n   = 1'b0;
        uart_rx = 1'b1;
        stage_q = 0;

        #(20 * CLK_PERIODNS);
        rst_n = 1'b1;
        #(200 * CLK_PERIODNS);

        stage_q = 1;
        fork
            begin
                uart_query_acl_v2_keymap();
            end
            begin
                uart_expect_acl_v2_keymap(DEFAULT_SIG3);
            end
        join
        $display("tb_uart_crypto_probe_acl_v2: initial keymap passed");

        #(20 * BIT_PERIODNS);

        stage_q = 2;
        fork
            begin
                uart_send_acl_v2_write(3'd3, BLOCK_SIG);
            end
            begin
                uart_expect_acl_v2_write_ack(3'd3, BLOCK_SIG);
            end
        join
        $display("tb_uart_crypto_probe_acl_v2: write ack passed");

        #(20 * BIT_PERIODNS);

        stage_q = 3;
        fork
            begin
                uart_query_acl_v2_keymap();
            end
            begin
                uart_expect_acl_v2_keymap(BLOCK_SIG);
            end
        join
        $display("tb_uart_crypto_probe_acl_v2: rewritten keymap passed");

        #(20 * BIT_PERIODNS);

        stage_q = 4;
        fork
            begin
                uart_query_acl_v2_hits();
            end
            begin
                uart_expect_acl_v2_hits(32'd0);
            end
        join
        $display("tb_uart_crypto_probe_acl_v2: zero hits passed");

        #(20 * BIT_PERIODNS);

        stage_q = 5;
        fork
            begin
                uart_send_raw_frame(BENIGN_PT, 16);
            end
            begin
                uart_expect_raw_frame(BENIGN_CT, 16);
            end
        join
        $display("tb_uart_crypto_probe_acl_v2: benign pass-through encrypt passed");

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
        $display("tb_uart_crypto_probe_acl_v2: exact block passed");

        #(20 * BIT_PERIODNS);

        stage_q = 7;
        fork
            begin
                uart_query_acl_v2_hits();
            end
            begin
                uart_expect_acl_v2_hits(32'd1);
            end
        join
        $display("tb_uart_crypto_probe_acl_v2: hit counter passed");

        $display("tb_uart_crypto_probe_acl_v2 passed.");
        $finish;
    end

endmodule
