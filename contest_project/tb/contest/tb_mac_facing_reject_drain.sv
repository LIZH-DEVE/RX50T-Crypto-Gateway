`timescale 1ns/1ps

import contest_cdc_ingress_pkg::*;

module tb_mac_facing_reject_drain;
    localparam integer CRYPTO_PERIOD_NS = 20;
    reg crypto_clk = 1'b0;
    reg crypto_rst_n_async = 1'b0;
    reg link_flush_req = 1'b0;
    reg s_axis_tvalid = 1'b0;
    wire s_axis_tready;
    reg [7:0] s_axis_tdata = 8'd0;
    reg s_axis_tlast = 1'b0;
    reg [0:0] s_axis_tuser = 1'b0;
    reg action_valid = 1'b0;
    wire action_ready;
    cdc_action_t action_payload;
    wire m_axis_tvalid;
    reg m_axis_tready = 1'b1;
    wire [7:0] m_axis_tdata;
    wire m_axis_tlast;
    wire [0:0] m_axis_tuser;
    wire accept_done;
    wire busy;
    integer accept_count = 0;
    integer accept_last_count = 0;

    contest_cdc_payload_dispatcher dut (
        .i_crypto_clk(crypto_clk),
        .i_crypto_rst_n_async(crypto_rst_n_async),
        .i_link_flush_req(link_flush_req),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .i_action_valid(action_valid),
        .o_action_ready(action_ready),
        .i_action_payload(action_payload),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser),
        .o_accept_done_pulse(accept_done),
        .o_busy(busy)
    );

    always #(CRYPTO_PERIOD_NS/2) crypto_clk = ~crypto_clk;

    task automatic send_action(input [1:0] kind, input [7:0] payload_len);
        begin
            @(posedge crypto_clk);
            while (!action_ready) @(posedge crypto_clk);
            action_payload.kind <= kind;
            action_payload.payload_len <= payload_len;
            action_valid <= 1'b1;
            @(posedge crypto_clk);
            while (!(action_valid && action_ready)) @(posedge crypto_clk);
            action_valid <= 1'b0;
            action_payload <= '0;
        end
    endtask

    task automatic send_payload(input integer count, input [7:0] base);
        integer idx;
        begin
            for (idx = 0; idx < count; idx = idx + 1) begin
                @(posedge crypto_clk);
                while (!s_axis_tready) @(posedge crypto_clk);
                s_axis_tvalid <= 1'b1;
                s_axis_tdata <= base + idx[7:0];
                s_axis_tlast <= (idx == count - 1);
                s_axis_tuser <= 1'b1;
                @(posedge crypto_clk);
                while (!(s_axis_tvalid && s_axis_tready)) @(posedge crypto_clk);
                s_axis_tvalid <= 1'b0;
                s_axis_tdata <= 8'd0;
                s_axis_tlast <= 1'b0;
                s_axis_tuser <= 1'b0;
            end
        end
    endtask

    initial begin
        action_payload = '0;
        repeat (4) @(posedge crypto_clk);
        crypto_rst_n_async = 1'b1;
        repeat (4) @(posedge crypto_clk);

        send_action(CDC_ACTION_KIND_DRAIN, 8'd100);
        send_payload(4, 8'h20);
        repeat (6) @(posedge crypto_clk);
        if (busy) $fatal(1, "dispatcher stayed busy after early TLAST drain");

        send_action(CDC_ACTION_KIND_ACCEPT, 8'd0);
        send_payload(3, 8'h40);
        wait (accept_count == 3);
        repeat (4) @(posedge crypto_clk);
        if (accept_last_count != 1) $fatal(1, "accept frame lost TLAST after drain recovery");
        if (busy) $fatal(1, "dispatcher remained busy after accepted frame");
        $display("tb_mac_facing_reject_drain: PASS");
        $finish;
    end

    always @(posedge crypto_clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            accept_count <= accept_count + 1;
            if (m_axis_tlast) accept_last_count <= accept_last_count + 1;
        end
    end

    initial begin
        #500000;
        $fatal(1, "tb_mac_facing_reject_drain timeout");
    end
endmodule