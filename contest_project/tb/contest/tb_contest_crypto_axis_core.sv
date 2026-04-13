`timescale 1ns/1ps

module tb_contest_crypto_axis_core;
    localparam integer CLK_PERIODNS = 10;
    localparam integer MAX_WAIT_CYCLES = 4000;

    localparam logic [127:0] SM4_PT = 128'h0123456789abcdeffedcba9876543210;
    localparam logic [127:0] SM4_CT = 128'h681edf34d206965e86b3e94f536e4246;

    localparam logic [255:0] AES_2BLOCK_PT = {
        128'h00112233445566778899aabbccddeeff,
        128'hffeeddccbbaa99887766554433221100
    };
    localparam logic [255:0] AES_2BLOCK_CT = {
        128'h69c4e0d86a7b0430d8cdb78070b4c55a,
        128'h1b872378795f4ffd772855fc87ca964d
    };

    reg clk;
    reg rst_n;

    reg        s_axis_tvalid;
    wire       s_axis_tready;
    reg  [7:0] s_axis_tdata;
    reg        s_axis_tlast;
    reg  [0:0] s_axis_tuser;

    wire       m_axis_tvalid;
    reg        m_axis_tready;
    wire [7:0] m_axis_tdata;
    wire       m_axis_tlast;

    reg        acl_cfg_valid;
    reg  [2:0] acl_cfg_index;
    reg  [7:0] acl_cfg_key;
    wire       acl_cfg_busy;
    wire       acl_cfg_done;
    wire       acl_cfg_error;
    wire [63:0] rule_keys_flat;
    wire [63:0] rule_counts_flat;
    wire       acl_block_pulse;
    wire       acl_block_slot_valid;
    wire [2:0] acl_block_slot;
    wire       pmu_crypto_active;

    integer cycle_wait_q;
    integer pulse_count_q;
    reg [2:0] pulse_slot_q;
    reg       pulse_slot_valid_q;

    contest_crypto_axis_core dut (
        .i_clk                (clk),
        .i_rst_n              (rst_n),
        .s_axis_tvalid        (s_axis_tvalid),
        .s_axis_tready        (s_axis_tready),
        .s_axis_tdata         (s_axis_tdata),
        .s_axis_tlast         (s_axis_tlast),
        .s_axis_tuser         (s_axis_tuser),
        .m_axis_tvalid        (m_axis_tvalid),
        .m_axis_tready        (m_axis_tready),
        .m_axis_tdata         (m_axis_tdata),
        .m_axis_tlast         (m_axis_tlast),
        .i_acl_cfg_valid      (acl_cfg_valid),
        .i_acl_cfg_index      (acl_cfg_index),
        .i_acl_cfg_key        (acl_cfg_key),
        .o_acl_cfg_busy       (acl_cfg_busy),
        .o_acl_cfg_done       (acl_cfg_done),
        .o_acl_cfg_error      (acl_cfg_error),
        .o_rule_keys_flat     (rule_keys_flat),
        .o_rule_counts_flat   (rule_counts_flat),
        .o_acl_block_pulse    (acl_block_pulse),
        .o_acl_block_slot_valid(acl_block_slot_valid),
        .o_acl_block_slot     (acl_block_slot),
        .o_pmu_crypto_active  (pmu_crypto_active)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIODNS/2) clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pulse_count_q <= 0;
            pulse_slot_q  <= 3'd0;
            pulse_slot_valid_q <= 1'b0;
        end else if (acl_block_pulse) begin
            pulse_count_q <= pulse_count_q + 1;
            pulse_slot_q  <= acl_block_slot;
            pulse_slot_valid_q <= acl_block_slot_valid;
        end
    end

    task automatic wait_cycles(input integer count);
        integer idx;
        begin
            for (idx = 0; idx < count; idx = idx + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task automatic axis_send_byte(
        input [7:0] data,
        input bit last_flag,
        input bit algo_sel
    );
        begin
            s_axis_tvalid = 1'b1;
            s_axis_tdata  = data;
            s_axis_tlast  = last_flag;
            s_axis_tuser  = algo_sel;
            do begin
                @(posedge clk);
            end while (!(s_axis_tvalid && s_axis_tready));
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = 8'd0;
            s_axis_tlast  = 1'b0;
            s_axis_tuser  = 1'b0;
        end
    endtask

    task automatic axis_send_frame(
        input logic [1023:0] payload_bits,
        input integer byte_count,
        input bit algo_sel
    );
        integer idx;
        begin
            for (idx = 0; idx < byte_count; idx = idx + 1) begin
                axis_send_byte(
                    payload_bits[1023 - (idx*8) -: 8],
                    (idx == byte_count - 1),
                    algo_sel
                );
            end
        end
    endtask

    task automatic axis_expect_byte(
        input [7:0] expected_data,
        input bit expected_last
    );
        begin
            cycle_wait_q = 0;
            while (!(m_axis_tvalid && m_axis_tready)) begin
                @(posedge clk);
                cycle_wait_q = cycle_wait_q + 1;
                if (cycle_wait_q > MAX_WAIT_CYCLES) begin
                    $display(
                        "%0t timeout debug: acl_state=%0d packer_count=%0d packer_valid=%0d engine_busy=%0d in_level=%0d out_level=%0d unpacker_valid=%0d",
                        $time,
                        dut.u_acl_axis.state_q,
                        dut.u_packer.gather_count_q,
                        dut.u_packer.m_axis_tvalid,
                        dut.u_block_engine.worker_busy_q,
                        dut.u_block_engine.u_ingress_fifo.count_q,
                        dut.u_block_engine.u_egress_fifo.count_q,
                        dut.u_unpacker.block_valid_q
                    );
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
        end
    endtask

    task automatic axis_expect_frame(
        input logic [1023:0] payload_bits,
        input integer byte_count
    );
        integer idx;
        begin
            for (idx = 0; idx < byte_count; idx = idx + 1) begin
                axis_expect_byte(
                    payload_bits[1023 - (idx*8) -: 8],
                    (idx == byte_count - 1)
                );
            end
        end
    endtask

    task automatic axis_expect_no_output(input integer count);
        integer idx;
        begin
            for (idx = 0; idx < count; idx = idx + 1) begin
                @(posedge clk);
                if (m_axis_tvalid) begin
                    $fatal(1, "unexpected output while expecting silence: 0x%02x", m_axis_tdata);
                end
            end
        end
    endtask

    task automatic expect_block_pulse(
        input integer expected_total_pulses,
        input [2:0] expected_slot
    );
        begin
            cycle_wait_q = 0;
            while (pulse_count_q != expected_total_pulses) begin
                @(posedge clk);
                cycle_wait_q = cycle_wait_q + 1;
                if (cycle_wait_q > MAX_WAIT_CYCLES) begin
                    $fatal(1, "timed out waiting for acl_block_pulse");
                end
            end
            if (!pulse_slot_valid_q) begin
                $fatal(1, "acl_block_slot_valid not asserted on pulse");
            end
            if (pulse_slot_q !== expected_slot) begin
                $fatal(1, "acl_block_slot mismatch exp=%0d got=%0d", expected_slot, pulse_slot_q);
            end
        end
    endtask

    task automatic drive_m_ready_pattern(
        input integer low_cycles,
        input integer high_cycles,
        input integer repeats
    );
        integer rep_idx;
        integer cyc_idx;
        begin
            for (rep_idx = 0; rep_idx < repeats; rep_idx = rep_idx + 1) begin
                m_axis_tready <= 1'b0;
                for (cyc_idx = 0; cyc_idx < low_cycles; cyc_idx = cyc_idx + 1) begin
                    @(posedge clk);
                end
                m_axis_tready <= 1'b1;
                for (cyc_idx = 0; cyc_idx < high_cycles; cyc_idx = cyc_idx + 1) begin
                    @(posedge clk);
                end
            end
            m_axis_tready <= 1'b1;
        end
    endtask

    task automatic acl_write_slot(
        input [2:0] slot,
        input [7:0] key
    );
        begin
            acl_cfg_valid <= 1'b1;
            acl_cfg_index <= slot;
            acl_cfg_key   <= key;
            @(posedge clk);
            acl_cfg_valid <= 1'b0;
            acl_cfg_index <= 3'd0;
            acl_cfg_key   <= 8'd0;

            cycle_wait_q = 0;
            while (!acl_cfg_done && !acl_cfg_error) begin
                @(posedge clk);
                cycle_wait_q = cycle_wait_q + 1;
                if (cycle_wait_q > MAX_WAIT_CYCLES) begin
                    $fatal(1, "timed out waiting for acl_cfg_done/acl_cfg_error");
                end
            end
            if (acl_cfg_error) begin
                $fatal(1, "unexpected acl_cfg_error while writing slot");
            end
        end
    endtask

    initial begin
        rst_n         = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = 8'd0;
        s_axis_tlast  = 1'b0;
        s_axis_tuser  = 1'b0;
        m_axis_tready = 1'b1;
        acl_cfg_valid = 1'b0;
        acl_cfg_index = 3'd0;
        acl_cfg_key   = 8'd0;

        wait_cycles(10);
        rst_n = 1'b1;
        wait_cycles(20);

        // Short raw flush must pass through unchanged with TLAST on the real final byte.
        fork
            begin
                axis_send_frame({8'h44, 8'h0A, 1008'd0}, 2, 1'b0);
            end
            begin
                axis_expect_byte(8'h44, 1'b0);
                axis_expect_byte(8'h0A, 1'b1);
            end
        join

        wait_cycles(20);

        // 16B SM4 must encrypt and align TLAST on the final ciphertext byte.
        fork
            begin
                axis_send_frame({SM4_PT, 896'd0}, 16, 1'b0);
            end
            begin
                axis_expect_frame({SM4_CT, 896'd0}, 16);
            end
        join

        if (!pmu_crypto_active && (rule_keys_flat === 64'dx)) begin
            $fatal(1, "sanity check failed: core sideband is X");
        end

        wait_cycles(20);

        // 32B AES must encrypt two blocks.
        fork
            begin
                axis_send_frame({AES_2BLOCK_PT, 768'd0}, 32, 1'b1);
            end
            begin
                axis_expect_frame({AES_2BLOCK_CT, 768'd0}, 32);
            end
        join

        wait_cycles(20);

        // Output backpressure must preserve byte order and TLAST alignment.
        fork
            begin
                drive_m_ready_pattern(3, 5, 12);
            end
            begin
                axis_send_frame({SM4_PT, 896'd0}, 16, 1'b0);
            end
            begin
                axis_expect_frame({SM4_CT, 896'd0}, 16);
            end
        join

        wait_cycles(20);

        // Default slot 0 = X should block on first byte X and emit no payload.
        fork
            begin
                axis_send_frame({8'h58, 8'h59, 8'h5A, 1000'd0}, 3, 1'b0);
            end
            begin
                axis_expect_no_output(40);
            end
        join
        expect_block_pulse(1, 3'd0);

        wait_cycles(20);

        // Rewrite slot 0 from X to Q, then XYZ must pass and Qxx must block.
        acl_write_slot(3'd0, 8'h51);
        if (rule_keys_flat[7:0] !== 8'h51) begin
            $fatal(1, "rule key slot 0 did not update to Q");
        end
        if (rule_counts_flat[7:0] !== 8'd0) begin
            $fatal(1, "rule count slot 0 was not reset on rewrite");
        end

        fork
            begin
                axis_send_frame({8'h58, 8'h59, 8'h5A, 1000'd0}, 3, 1'b0);
            end
            begin
                axis_expect_byte(8'h58, 1'b0);
                axis_expect_byte(8'h59, 1'b0);
                axis_expect_byte(8'h5A, 1'b1);
            end
        join

        wait_cycles(20);

        fork
            begin
                axis_send_frame({8'h51, 8'h31, 8'h32, 1000'd0}, 3, 1'b0);
            end
            begin
                axis_expect_no_output(40);
            end
        join
        expect_block_pulse(2, 3'd0);
        if (rule_counts_flat[7:0] !== 8'd1) begin
            $fatal(1, "rule count slot 0 did not increment after rewritten block");
        end

        wait_cycles(20);
        $display("contest_crypto_axis_core test passed.");
        $finish;
    end

endmodule
