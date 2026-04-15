`timescale 1ns/1ps

module tb_contest_acl_axis_core;
    localparam integer CLK_PERIODNS = 10;
    localparam integer MAX_WAIT_CYCLES = 200;
    localparam logic [127:0] DEFAULT_SIG0 = 128'h58595A575052545558595A5750525455;
    localparam logic [127:0] NEW_SIG0     = 128'h5152535455565758595A303132333435;

    reg clk;
    reg rst_n;
    reg soft_reset;

    reg        s_axis_tvalid;
    wire       s_axis_tready;
    reg  [7:0] s_axis_tdata;
    reg        s_axis_tlast;
    reg  [0:0] s_axis_tuser;

    wire       m_axis_tvalid;
    reg        m_axis_tready;
    wire [7:0] m_axis_tdata;
    wire       m_axis_tlast;
    wire [0:0] m_axis_tuser;

    reg         cfg_valid;
    reg  [2:0]  cfg_index;
    reg  [127:0] cfg_key;
    wire        cfg_busy;
    wire        cfg_done;
    wire        cfg_error;
    wire        acl_block_pulse;
    wire        acl_block_slot_valid;
    wire [2:0]  acl_block_slot;
    wire [1023:0] rule_keys_flat;
    wire [255:0]  rule_counts_flat;

    integer pulse_count_q;
    reg [2:0] pulse_slot_q;
    reg pulse_slot_valid_q;
    integer wait_cycles_q;

    contest_acl_axis_core dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_soft_reset(soft_reset),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .i_cfg_valid(cfg_valid),
        .i_cfg_index(cfg_index),
        .i_cfg_key(cfg_key),
        .o_cfg_busy(cfg_busy),
        .o_cfg_done(cfg_done),
        .o_cfg_error(cfg_error),
        .o_acl_block_pulse(acl_block_pulse),
        .o_acl_block_slot_valid(acl_block_slot_valid),
        .o_acl_block_slot(acl_block_slot),
        .o_rule_keys_flat(rule_keys_flat),
        .o_rule_counts_flat(rule_counts_flat)
    );


    initial begin
        clk = 1'b0;
        forever #(CLK_PERIODNS/2) clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pulse_count_q <= 0;
            pulse_slot_q <= 3'd0;
            pulse_slot_valid_q <= 1'b0;
        end else if (acl_block_pulse) begin
            pulse_count_q <= pulse_count_q + 1;
            pulse_slot_q <= acl_block_slot;
            pulse_slot_valid_q <= acl_block_slot_valid;
        end
    end

    task automatic wait_cycles(input integer count);
        integer idx;
        begin
            for (idx = 0; idx < count; idx = idx + 1) begin
                @(posedge clk);
            #1;
            end
        end
    endtask

    task automatic send_byte(input [7:0] data, input bit last_flag);
        begin
            @(negedge clk);
            s_axis_tvalid = 1'b1;
            s_axis_tdata = data;
            s_axis_tlast = last_flag;
            s_axis_tuser = 1'b0;
            while (!s_axis_tready) begin
                @(negedge clk);
            end
            @(posedge clk);
            #1;
            s_axis_tvalid = 1'b0;
            s_axis_tdata = 8'd0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task automatic send_frame(input logic [255:0] payload_bits, input integer byte_count);
        integer idx;
        begin
            for (idx = 0; idx < byte_count; idx = idx + 1) begin
                send_byte(payload_bits[255 - (idx * 8) -: 8], idx == byte_count - 1);
            end
        end
    endtask

    task automatic expect_byte(input [7:0] expected_data, input bit expected_last);
        begin
            wait_cycles_q = 0;
            while (!(m_axis_tvalid && m_axis_tready)) begin
                @(negedge clk);
                wait_cycles_q = wait_cycles_q + 1;
                if (wait_cycles_q > MAX_WAIT_CYCLES) begin
                    $fatal(1, "timed out waiting for m_axis_tvalid");
                end
            end
            if (m_axis_tdata !== expected_data) begin
                $fatal(1, "m_axis_tdata mismatch exp=0x%02x got=0x%02x", expected_data, m_axis_tdata);
            end
            if (m_axis_tlast !== expected_last) begin
                $fatal(1, "m_axis_tlast mismatch exp=%0d got=%0d", expected_last, m_axis_tlast);
            end
            @(posedge clk);
            #1;
        end
    endtask

    task automatic expect_no_output(input integer cycles);
        integer idx;
        begin
            for (idx = 0; idx < cycles; idx = idx + 1) begin
                @(posedge clk);
                if (m_axis_tvalid) begin
                    $fatal(1, "unexpected output 0x%02x while expecting silence", m_axis_tdata);
                end
            end
        end
    endtask

    task automatic expect_block(input integer expected_count, input [2:0] expected_slot);
        begin
            wait_cycles_q = 0;
            while (pulse_count_q != expected_count) begin
                @(posedge clk);
                wait_cycles_q = wait_cycles_q + 1;
                if (wait_cycles_q > MAX_WAIT_CYCLES) begin
                    $fatal(1, "timed out waiting for ACL block pulse");
                end
            end
            if (!pulse_slot_valid_q || (pulse_slot_q !== expected_slot)) begin
                $fatal(1, "unexpected block slot valid=%0d slot=%0d", pulse_slot_valid_q, pulse_slot_q);
            end
        end
    endtask

    task automatic write_slot(input [2:0] slot, input [127:0] signature);
        begin
            cfg_valid = 1'b1;
            cfg_index = slot;
            cfg_key = signature;
            @(posedge clk);
            @(negedge clk);
            cfg_valid = 1'b0;
            cfg_index = 3'd0;
            cfg_key = 128'd0;
            wait_cycles_q = 0;
            while (!cfg_done && !cfg_error) begin
                @(posedge clk);
                wait_cycles_q = wait_cycles_q + 1;
                if (wait_cycles_q > MAX_WAIT_CYCLES) begin
                    $fatal(1, "timed out waiting for cfg_done/cfg_error");
                end
            end
            if (cfg_error) begin
                $fatal(1, "unexpected cfg_error while writing slot %0d", slot);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        soft_reset = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata = 8'd0;
        s_axis_tlast = 1'b0;
        s_axis_tuser = 1'b0;
        m_axis_tready = 1'b1;
        cfg_valid = 1'b0;
        cfg_index = 3'd0;
        cfg_key = 128'd0;

        wait_cycles(8);
        rst_n = 1'b1;
        wait_cycles(4);

        // Short frame (<16B) must pass through unchanged.
        fork
            begin
                send_frame({8'h44, 8'h0A, 240'd0}, 2);
            end
            begin
                expect_byte(8'h44, 1'b0);
                expect_byte(8'h0A, 1'b1);
            end
        join

        wait_cycles(8);

        // Default slot 0 exact 16B signature must block.
        fork
            begin
                send_frame({DEFAULT_SIG0, 128'd0}, 16);
            end
            begin
                expect_no_output(40);
            end
        join
        expect_block(1, 3'd0);

        wait_cycles(8);

        // Sliding-window hit at offset 1: first byte passes, then block fires.
        fork
            begin
                send_frame({8'hAA, DEFAULT_SIG0, 120'd0}, 17);
            end
            begin
                expect_byte(8'hAA, 1'b0);
                expect_no_output(40);
            end
        join
        expect_block(2, 3'd0);

        wait_cycles(8);

        // Rewrite slot 0 and reset its counter.
        write_slot(3'd0, NEW_SIG0);
        if (rule_keys_flat[127:0] !== NEW_SIG0) begin
            $fatal(1, "slot 0 signature did not update");
        end
        if (rule_counts_flat[31:0] !== 32'd0) begin
            $fatal(1, "slot 0 hit counter did not reset");
        end

        // <16B prefix of rewritten signature must pass.
        fork
            begin
                send_frame({8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h56, 8'h57, 8'h58, 192'd0}, 8);
            end
            begin
                expect_byte(8'h51, 1'b0);
                expect_byte(8'h52, 1'b0);
                expect_byte(8'h53, 1'b0);
                expect_byte(8'h54, 1'b0);
                expect_byte(8'h55, 1'b0);
                expect_byte(8'h56, 1'b0);
                expect_byte(8'h57, 1'b0);
                expect_byte(8'h58, 1'b1);
            end
        join

        wait_cycles(8);

        // Benign >16B frame must pass through unchanged across compare/emit/fill cycles.
        fork
            begin
                send_frame({8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07,
                            8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F,
                            8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
                            8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F}, 32);
            end
            begin
                expect_byte(8'h00, 1'b0);
                expect_byte(8'h01, 1'b0);
                expect_byte(8'h02, 1'b0);
                expect_byte(8'h03, 1'b0);
                expect_byte(8'h04, 1'b0);
                expect_byte(8'h05, 1'b0);
                expect_byte(8'h06, 1'b0);
                expect_byte(8'h07, 1'b0);
                expect_byte(8'h08, 1'b0);
                expect_byte(8'h09, 1'b0);
                expect_byte(8'h0A, 1'b0);
                expect_byte(8'h0B, 1'b0);
                expect_byte(8'h0C, 1'b0);
                expect_byte(8'h0D, 1'b0);
                expect_byte(8'h0E, 1'b0);
                expect_byte(8'h0F, 1'b0);
                expect_byte(8'h10, 1'b0);
                expect_byte(8'h11, 1'b0);
                expect_byte(8'h12, 1'b0);
                expect_byte(8'h13, 1'b0);
                expect_byte(8'h14, 1'b0);
                expect_byte(8'h15, 1'b0);
                expect_byte(8'h16, 1'b0);
                expect_byte(8'h17, 1'b0);
                expect_byte(8'h18, 1'b0);
                expect_byte(8'h19, 1'b0);
                expect_byte(8'h1A, 1'b0);
                expect_byte(8'h1B, 1'b0);
                expect_byte(8'h1C, 1'b0);
                expect_byte(8'h1D, 1'b0);
                expect_byte(8'h1E, 1'b0);
                expect_byte(8'h1F, 1'b1);
            end
        join

        wait_cycles(8);

        // Rewritten exact match must block and increment 32-bit counter.
        fork
            begin
                send_frame({NEW_SIG0, 128'd0}, 16);
            end
            begin
                expect_no_output(40);
            end
        join
        expect_block(3, 3'd0);
        if (rule_counts_flat[31:0] !== 32'd1) begin
            $fatal(1, "slot 0 hit counter did not increment after rewritten block");
        end

        $display("contest_acl_axis_core Phase B test passed.");
        $finish;
    end
endmodule
