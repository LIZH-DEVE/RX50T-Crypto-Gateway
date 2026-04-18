`timescale 1ns/1ps

module tb_mac_facing_sustained_throughput;
    localparam integer ROOT_PERIOD_NS = 20;
    localparam integer INGRESS_PERIOD_NS = 8;
    localparam integer FRAME_COUNT = 4;
    localparam integer FRAME_BYTES = 96;
    localparam integer TOTAL_BYTES = FRAME_COUNT * FRAME_BYTES;
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
    reg m_axis_tready = 1'b0;
    wire [7:0] m_axis_tdata;
    wire m_axis_tlast;
    wire [63:0] cnt_active;
    wire [63:0] cnt_stall;
    wire [63:0] cnt_bytes;
    integer out_count = 0;
    integer out_last_count = 0;
    integer frame_idx;

    contest_mac_facing_ingress_top dut (
        .i_root_clk(root_clk), .i_root_rst_n_async(root_rst_n_async), .i_ingress_clk(ingress_clk), .i_ingress_locked(ingress_locked), .i_link_flush_req(link_flush_req),
        .s_ingress_tvalid(s_ingress_tvalid), .s_ingress_tready(s_ingress_tready), .s_ingress_tdata(s_ingress_tdata), .s_ingress_tlast(s_ingress_tlast), .s_ingress_tuser(s_ingress_tuser),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tdata(m_axis_tdata), .m_axis_tlast(m_axis_tlast),
        .o_root_wake_pulse(), .o_crypto_clk_ce(), .o_crypto_idle_sync(), .o_wr_full(), .o_wr_almost_full(), .o_rd_empty(),
        .o_cnt_ingress_active_cycles(cnt_active), .o_cnt_ingress_stall_cycles(cnt_stall), .o_cnt_ingress_total_bytes(cnt_bytes)
    );

    always #(ROOT_PERIOD_NS/2) root_clk = ~root_clk;
    always #(INGRESS_PERIOD_NS/2) ingress_clk = ~ingress_clk;

    task automatic send_frame(input integer frame_no, input integer count);
        integer idx;
        begin
            for (idx = 0; idx < count; idx = idx + 1) begin
                @(negedge ingress_clk);
                s_ingress_tvalid <= 1'b1;
                s_ingress_tdata <= (frame_no * FRAME_BYTES + idx) & 8'hFF;
                s_ingress_tlast <= (idx == count - 1);
                s_ingress_tuser <= frame_no[0];
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
        ingress_locked = 1'b1;
        repeat (160) @(posedge root_clk);
        m_axis_tready = 1'b1;
        fork
            begin
                for (frame_idx = 0; frame_idx < FRAME_COUNT; frame_idx = frame_idx + 1) begin
                    send_frame(frame_idx, FRAME_BYTES);
                end
            end
            begin
                repeat (900) begin
                    @(posedge root_clk);
                    if (($time % 160) == 0) m_axis_tready <= 1'b0;
                    else if (($time % 80) == 0) m_axis_tready <= 1'b1;
                end
                m_axis_tready <= 1'b1;
            end
        join
        wait (out_count == TOTAL_BYTES);
        repeat (12) @(posedge root_clk);
        if (out_last_count != FRAME_COUNT) $fatal(1, "expected %0d TLAST beats, got %0d", FRAME_COUNT, out_last_count);
        if (cnt_bytes != TOTAL_BYTES) $fatal(1, "total byte counter mismatch: expected %0d got %0d", TOTAL_BYTES, cnt_bytes);
        if (cnt_stall == 0) $fatal(1, "stall counter never advanced under sustained traffic");
        if (cnt_active == 0) $fatal(1, "active counter never advanced under sustained traffic");
        $display("tb_mac_facing_sustained_throughput: PASS");
        $finish;
    end

    always @(posedge root_clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            out_count <= out_count + 1;
            if (m_axis_tlast) out_last_count <= out_last_count + 1;
        end
    end

    initial begin
        #12000000;
        $fatal(1, "tb_mac_facing_sustained_throughput timeout");
    end
endmodule