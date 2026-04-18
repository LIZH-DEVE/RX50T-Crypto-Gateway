`timescale 1ns/1ps

module tb_mac_facing_nasty_random_stall;
    localparam integer ROOT_PERIOD_NS = 20;
    localparam integer INGRESS_PERIOD_NS = 8;
    localparam integer FRAME_BYTES = 32;
    localparam integer TAIL_STALL_CYCLES = 6;

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

    integer dispatch_count = 0;
    integer dispatch_last_count = 0;
    integer out_count = 0;
    integer last_count = 0;
    integer stall_cycles_left = 0;
    reg tail_stall_started = 1'b0;
    reg prev_stall_valid_q = 1'b0;
    reg [7:0] prev_stall_data_q = 8'd0;
    reg prev_stall_last_q = 1'b0;

    contest_mac_facing_ingress_top dut (
        .i_root_clk(root_clk), .i_root_rst_n_async(root_rst_n_async), .i_ingress_clk(ingress_clk), .i_ingress_locked(ingress_locked), .i_link_flush_req(link_flush_req),
        .s_ingress_tvalid(s_ingress_tvalid), .s_ingress_tready(s_ingress_tready), .s_ingress_tdata(s_ingress_tdata), .s_ingress_tlast(s_ingress_tlast), .s_ingress_tuser(s_ingress_tuser),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tdata(m_axis_tdata), .m_axis_tlast(m_axis_tlast),
        .o_root_wake_pulse(), .o_crypto_clk_ce(), .o_crypto_idle_sync(), .o_wr_full(), .o_wr_almost_full(), .o_rd_empty(),
        .o_cnt_ingress_active_cycles(), .o_cnt_ingress_stall_cycles(), .o_cnt_ingress_total_bytes()
    );

    always #(ROOT_PERIOD_NS/2) root_clk = ~root_clk;
    always #(INGRESS_PERIOD_NS/2) ingress_clk = ~ingress_clk;

    task automatic send_frame(input integer count);
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(negedge ingress_clk);
                s_ingress_tvalid <= 1'b1;
                s_ingress_tdata <= 8'h40 + i[7:0];
                s_ingress_tlast <= (i == count - 1);
                s_ingress_tuser <= 1'b1;
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
        fork
            send_frame(FRAME_BYTES);
        join_none

        wait ((out_count == FRAME_BYTES) && (last_count == 1));
        repeat (8) @(posedge root_clk);
        if (dispatch_count != FRAME_BYTES) $fatal(1, "nasty stall dispatch count mismatch exp=%0d got=%0d", FRAME_BYTES, dispatch_count);
        if (dispatch_last_count != 1) $fatal(1, "nasty stall dispatch expected exactly one TLAST, got %0d", dispatch_last_count);
        if (out_count != FRAME_BYTES) $fatal(1, "nasty stall lost bytes: expected %0d got %0d", FRAME_BYTES, out_count);
        if (last_count != 1) $fatal(1, "nasty stall expected exactly one TLAST, got %0d", last_count);
        $display("tb_mac_facing_nasty_random_stall: PASS");
        $finish;
    end

    always @(negedge root_clk) begin
        if (!root_rst_n_async || !ingress_locked) begin
            m_axis_tready <= 1'b1;
            stall_cycles_left = 0;
            tail_stall_started <= 1'b0;
        end else if ((stall_cycles_left == 0) && !tail_stall_started && m_axis_tvalid && (out_count >= FRAME_BYTES - 2)) begin
            m_axis_tready <= 1'b0;
            stall_cycles_left = TAIL_STALL_CYCLES - 1;
            tail_stall_started <= 1'b1;
        end else if (stall_cycles_left > 0) begin
            m_axis_tready <= 1'b0;
            stall_cycles_left = stall_cycles_left - 1;
        end else begin
            m_axis_tready <= 1'b1;
        end
    end

    always @(posedge root_clk) begin
        if (dut.dispatch_axis_tvalid_w && dut.crypto_core_tready_w && !dut.bridge_m_axis_tready_w) begin
            $fatal(1, "dispatcher exposed payload to crypto_core while bridge beat was not consumed");
        end

        if (dut.dispatch_axis_tvalid_w && dut.dispatch_axis_tready_w) begin
            if (dut.dispatch_axis_tdata_w !== (8'h40 + dispatch_count[7:0])) begin
                $fatal(1, "dispatch data mismatch at beat %0d exp=0x%02x got=0x%02x", dispatch_count + 1, (8'h40 + dispatch_count[7:0]), dut.dispatch_axis_tdata_w);
            end
            if (dut.dispatch_axis_tuser_w !== 1'b1) begin
                $fatal(1, "dispatch tuser mismatch at beat %0d", dispatch_count + 1);
            end
            dispatch_count <= dispatch_count + 1;
            if (dut.dispatch_axis_tlast_w) begin
                dispatch_last_count <= dispatch_last_count + 1;
                if (dispatch_count != FRAME_BYTES - 1) begin
                    $fatal(1, "dispatch observed TLAST on beat %0d, expected %0d", dispatch_count + 1, FRAME_BYTES);
                end
            end
        end

        if (prev_stall_valid_q && m_axis_tvalid) begin
            if (m_axis_tdata !== prev_stall_data_q) $fatal(1, "nasty stall changed data during backpressure hold");
            if (m_axis_tlast !== prev_stall_last_q) $fatal(1, "nasty stall changed TLAST during backpressure hold");
        end

        if (m_axis_tvalid && m_axis_tready) begin
            out_count <= out_count + 1;
            if (m_axis_tlast) begin
                last_count <= last_count + 1;
                if (out_count != FRAME_BYTES - 1) $fatal(1, "nasty stall observed TLAST on beat %0d, expected %0d", out_count + 1, FRAME_BYTES);
            end
        end

        prev_stall_valid_q <= m_axis_tvalid && !m_axis_tready;
        if (m_axis_tvalid && !m_axis_tready) begin
            prev_stall_data_q <= m_axis_tdata;
            prev_stall_last_q <= m_axis_tlast;
        end
    end

    initial begin
        #6000000;
        $fatal(1, "tb_mac_facing_nasty_random_stall timeout dispatch=%0d dispatch_last=%0d out=%0d last=%0d", dispatch_count, dispatch_last_count, out_count, last_count);
    end
endmodule