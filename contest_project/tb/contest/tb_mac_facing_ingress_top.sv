`timescale 1ns/1ps

module tb_mac_facing_ingress_top;
    localparam integer ROOT_PERIOD_NS = 20;
    localparam integer INGRESS_PERIOD_NS = 8;
    localparam integer FRAME_BYTES = 16;
    reg root_clk = 1'b0;
    reg ingress_clk = 1'b0;
    reg root_rst_n_async = 1'b0;
    reg ingress_locked = 1'b0;
    reg link_flush_req = 1'b0;
    reg s_ingress_tvalid = 1'b0;
    wire s_ingress_tready;
    reg [7:0] s_ingress_tdata = 8'd0;
    reg s_ingress_tlast = 1'b0;
    reg [0:0] s_ingress_tuser = 1'b0;
    wire m_axis_tvalid;
    reg m_axis_tready = 1'b1;
    wire [7:0] m_axis_tdata;
    wire m_axis_tlast;
    wire root_wake_pulse;
    wire crypto_clk_ce;
    wire crypto_idle_sync;
    wire wr_full;
    wire wr_almost_full;
    wire rd_empty;
    wire [63:0] cnt_active;
    wire [63:0] cnt_stall;
    wire [63:0] cnt_bytes;
    integer out_count = 0;
    integer last_count = 0;
    integer wake_count = 0;
    integer i;

    contest_mac_facing_ingress_top dut (
        .i_root_clk(root_clk), .i_root_rst_n_async(root_rst_n_async), .i_ingress_clk(ingress_clk), .i_ingress_locked(ingress_locked), .i_link_flush_req(link_flush_req),
        .s_ingress_tvalid(s_ingress_tvalid), .s_ingress_tready(s_ingress_tready), .s_ingress_tdata(s_ingress_tdata), .s_ingress_tlast(s_ingress_tlast), .s_ingress_tuser(s_ingress_tuser),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tdata(m_axis_tdata), .m_axis_tlast(m_axis_tlast),
        .o_root_wake_pulse(root_wake_pulse), .o_crypto_clk_ce(crypto_clk_ce), .o_crypto_idle_sync(crypto_idle_sync), .o_wr_full(wr_full), .o_wr_almost_full(wr_almost_full), .o_rd_empty(rd_empty),
        .o_cnt_ingress_active_cycles(cnt_active), .o_cnt_ingress_stall_cycles(cnt_stall), .o_cnt_ingress_total_bytes(cnt_bytes)
    );

    always #(ROOT_PERIOD_NS/2) root_clk = ~root_clk;
    always #(INGRESS_PERIOD_NS/2) ingress_clk = ~ingress_clk;

    task automatic send_frame(input integer count, input [0:0] algo_sel);
        integer idx;
        begin
            for (idx = 0; idx < count; idx = idx + 1) begin
                @(negedge ingress_clk);
                s_ingress_tvalid <= 1'b1;
                s_ingress_tdata <= 8'h80 + idx[7:0];
                s_ingress_tlast <= (idx == count - 1);
                s_ingress_tuser <= algo_sel;
                @(posedge ingress_clk);
                while (!s_ingress_tready) @(posedge ingress_clk);
                @(negedge ingress_clk);
                s_ingress_tvalid <= 1'b0;
                s_ingress_tdata <= 8'd0;
                s_ingress_tlast <= 1'b0;
                s_ingress_tuser <= 1'b0;
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge root_clk);
        root_rst_n_async = 1'b1;
        repeat (4) @(posedge ingress_clk);
        if (s_ingress_tready !== 1'b0) $fatal(1, "MAC ingress top released before ingress lock");
        ingress_locked = 1'b1;
        repeat (64) @(posedge root_clk);
        if (crypto_clk_ce !== 1'b0) $fatal(1, "MAC ingress top failed to gate crypto clock while idle");
        send_frame(FRAME_BYTES, 1'b1);
        wait (out_count == FRAME_BYTES);
        repeat (8) @(posedge root_clk);
        if (last_count != 1) $fatal(1, "expected exactly one output TLAST, saw %0d", last_count);
        if (cnt_bytes != FRAME_BYTES) $fatal(1, "expected %0d ingress bytes, got %0d", FRAME_BYTES, cnt_bytes);
        if (cnt_active == 0) $fatal(1, "active-cycle counter did not advance");
        if (wake_count == 0) $fatal(1, "root wake pulse was never observed");
        $display("tb_mac_facing_ingress_top: PASS");
        $finish;
    end

    always @(posedge root_clk) begin
        if (root_wake_pulse) wake_count <= wake_count + 1;
        if (m_axis_tvalid && m_axis_tready) begin
            out_count <= out_count + 1;
            if (m_axis_tlast) last_count <= last_count + 1;
        end
    end

    initial begin
        #3000000;
        $fatal(1, "tb_mac_facing_ingress_top timeout out=%0d last=%0d wake=%0d cnt_bytes=%0d cnt_active=%0d cnt_stall=%0d ce=%0b consume=%0b busy=%0b wr_full=%0b rd_empty=%0b bridge_valid=%0b dispatch_valid=%0b core_tready=%0b action_valid=%0b action_src=%0b launch_grant=%0b mb_wr_level=%0d mb_rd_level=%0d mb_wr_bin=%0d mb_rd_bin=%0d",
            out_count, last_count, wake_count, cnt_bytes, cnt_active, cnt_stall,
            crypto_clk_ce, dut.crypto_consume_enable_q, dut.dispatch_busy_w, wr_full, rd_empty,
            dut.bridge_m_axis_tvalid_w, dut.dispatch_axis_tvalid_w, dut.crypto_core_tready_w, dut.action_mailbox_dst_valid_w,
            dut.action_mailbox_src_valid_q, dut.frame_launch_granted_q,
            dut.u_action_mailbox.u_mailbox_fifo.o_wr_level, dut.u_action_mailbox.u_mailbox_fifo.o_rd_level,
            dut.u_action_mailbox.u_mailbox_fifo.wr_bin_q, dut.u_action_mailbox.u_mailbox_fifo.rd_bin_q);
    end
endmodule