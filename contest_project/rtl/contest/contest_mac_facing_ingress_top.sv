`timescale 1ns/1ps

import contest_cdc_ingress_pkg::*;

module contest_mac_facing_ingress_top #(
    parameter integer CLK_HZ                    = 50_000_000,
    parameter integer CDC_FIFO_DEPTH            = 128,
    parameter integer CDC_ALMOST_FULL_MARGIN    = 8,
    parameter integer CRYPTO_SLEEP_HOLDOFF      = 16,
    parameter integer CRYPTO_WAKE_SETTLE_CYCLES = 2
) (
    input  wire       i_root_clk,
    input  wire       i_root_rst_n_async,
    input  wire       i_ingress_clk,
    input  wire       i_ingress_locked,
    input  wire       i_link_flush_req,
    input  wire       s_ingress_tvalid,
    output wire       s_ingress_tready,
    input  wire [7:0] s_ingress_tdata,
    input  wire       s_ingress_tlast,
    input  wire [0:0] s_ingress_tuser,
    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tlast,
    output wire       o_root_wake_pulse,
    output wire       o_crypto_clk_ce,
    output wire       o_crypto_idle_sync,
    output wire       o_wr_full,
    output wire       o_wr_almost_full,
    output wire       o_rd_empty,
    output wire [63:0] o_cnt_ingress_active_cycles,
    output wire [63:0] o_cnt_ingress_stall_cycles,
    output wire [63:0] o_cnt_ingress_total_bytes
);

    localparam integer WAKE_SETTLE_W = (CRYPTO_WAKE_SETTLE_CYCLES > 1) ? $clog2(CRYPTO_WAKE_SETTLE_CYCLES + 1) : 1;
    localparam integer SLEEP_COUNT_W = (CRYPTO_SLEEP_HOLDOFF > 1) ? $clog2(CRYPTO_SLEEP_HOLDOFF + 1) : 1;
    localparam [WAKE_SETTLE_W-1:0] WAKE_SETTLE_INIT = CRYPTO_WAKE_SETTLE_CYCLES;

    wire proto_rst_n_async;
    wire root_rst_n_sync;
    wire crypto_link_rst_n_sync;
    wire clk_crypto_gated;
    wire bridge_root_wake_pulse_w;
    wire bridge_s_axis_tvalid_w;
    wire bridge_s_axis_tready_w;
    wire bridge_m_axis_tvalid_w;
    wire bridge_m_axis_tready_w;
    wire [7:0] bridge_m_axis_tdata_w;
    wire bridge_m_axis_tlast_w;
    wire [0:0] bridge_m_axis_tuser_w;
    wire action_mailbox_src_ready_w;
    wire action_mailbox_dst_valid_w;
    wire action_mailbox_dst_ready_w;
    wire [CDC_ACTION_W-1:0] action_mailbox_dst_payload_w;
    wire [CDC_ACTION_W-1:0] action_src_payload_w;
    wire bridge_dispatch_tvalid_w;
    wire dispatch_axis_tvalid_w;
    wire dispatch_axis_tready_w;
    wire [7:0] dispatch_axis_tdata_w;
    wire dispatch_axis_tlast_w;
    wire [0:0] dispatch_axis_tuser_w;
    wire dispatch_busy_w;
    wire crypto_core_tready_w;
    wire crypto_core_idle_w;
    wire crypto_pmu_active_w;
    wire ingress_gate_w;
    wire ingress_fire_w;

    reg crypto_clk_ce_q;
    reg [SLEEP_COUNT_W-1:0] crypto_sleep_count_q;
    reg [WAKE_SETTLE_W-1:0] crypto_wake_settle_count_q;
    reg crypto_consume_enable_q = 1'b0;
    reg crypto_core_rst_n_q = 1'b0;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg crypto_idle_sync1_q;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg crypto_idle_sync2_q;
    reg ingress_frame_active_q = 1'b0;
    reg frame_launch_granted_q = 1'b0;
    reg action_mailbox_src_valid_q = 1'b0;
    reg [63:0] cnt_ingress_active_cycles_q = 64'd0;
    reg [63:0] cnt_ingress_stall_cycles_q = 64'd0;
    reg [63:0] cnt_ingress_total_bytes_q = 64'd0;

    assign proto_rst_n_async = i_root_rst_n_async && i_ingress_locked;
    assign o_root_wake_pulse = bridge_root_wake_pulse_w;
    assign o_crypto_clk_ce = crypto_clk_ce_q;
    assign o_crypto_idle_sync = crypto_idle_sync2_q;
    assign o_cnt_ingress_active_cycles = cnt_ingress_active_cycles_q;
    assign o_cnt_ingress_stall_cycles = cnt_ingress_stall_cycles_q;
    assign o_cnt_ingress_total_bytes = cnt_ingress_total_bytes_q;

    assign ingress_gate_w = ingress_frame_active_q || frame_launch_granted_q;
    assign bridge_s_axis_tvalid_w = s_ingress_tvalid && ingress_gate_w;
    assign s_ingress_tready = bridge_s_axis_tready_w && ingress_gate_w;
    assign ingress_fire_w = bridge_s_axis_tvalid_w && bridge_s_axis_tready_w;

    assign action_src_payload_w = {CDC_ACTION_KIND_ACCEPT, 8'd0};


    contest_reset_sync u_root_reset_sync (
        .i_clk(i_root_clk),
        .i_rst_n_async(proto_rst_n_async),
        .o_rst_n_sync(root_rst_n_sync)
    );

    BUFGCE u_bufgce_crypto (
        .I(i_root_clk),
        .CE(crypto_clk_ce_q),
        .O(clk_crypto_gated)
    );

    contest_reset_sync u_crypto_reset_sync (
        .i_clk(clk_crypto_gated),
        .i_rst_n_async(proto_rst_n_async),
        .o_rst_n_sync(crypto_link_rst_n_sync)
    );

    always @(posedge clk_crypto_gated) begin
        if (!crypto_link_rst_n_sync) begin
            crypto_core_rst_n_q <= 1'b0;
        end else begin
            crypto_core_rst_n_q <= 1'b1;
        end
    end

    contest_crypto_cdc_ingress_bridge #(
        .DATA_W(8),
        .USER_W(1),
        .DEPTH(CDC_FIFO_DEPTH),
        .ALMOST_FULL_MARGIN(CDC_ALMOST_FULL_MARGIN)
    ) u_bridge (
        .i_ingress_clk(i_ingress_clk),
        .i_ingress_rst_n_async(proto_rst_n_async),
        .i_root_clk(i_root_clk),
        .i_root_rst_n_async(proto_rst_n_async),
        .i_crypto_clk(clk_crypto_gated),
        .i_crypto_rst_n_async(proto_rst_n_async),
        .i_link_flush_req(i_link_flush_req),
        .s_axis_tvalid(bridge_s_axis_tvalid_w),
        .s_axis_tready(bridge_s_axis_tready_w),
        .s_axis_tdata(s_ingress_tdata),
        .s_axis_tlast(s_ingress_tlast),
        .s_axis_tuser(s_ingress_tuser),
        .m_axis_tvalid(bridge_m_axis_tvalid_w),
        .m_axis_tready(bridge_m_axis_tready_w),
        .m_axis_tdata(bridge_m_axis_tdata_w),
        .m_axis_tlast(bridge_m_axis_tlast_w),
        .m_axis_tuser(bridge_m_axis_tuser_w),
        .o_root_wake_pulse(bridge_root_wake_pulse_w),
        .o_wr_full(o_wr_full),
        .o_wr_almost_full(o_wr_almost_full),
        .o_rd_empty(o_rd_empty)
    );

    contest_async_mailbox #(
        .WIDTH(CDC_ACTION_W)
    ) u_action_mailbox (
        .i_src_clk(i_ingress_clk),
        .i_src_rst_n_async(proto_rst_n_async),
        .i_dst_clk(clk_crypto_gated),
        .i_dst_rst_n_async(proto_rst_n_async),
        .i_link_flush_req(i_link_flush_req),
        .i_src_valid(action_mailbox_src_valid_q),
        .o_src_ready(action_mailbox_src_ready_w),
        .i_src_payload(action_src_payload_w),
        .o_dst_valid(action_mailbox_dst_valid_w),
        .i_dst_ready(action_mailbox_dst_ready_w),
        .o_dst_payload(action_mailbox_dst_payload_w)
    );

    contest_cdc_payload_dispatcher u_payload_dispatcher (
        .i_crypto_clk(clk_crypto_gated),
        .i_crypto_rst_n_async(proto_rst_n_async),
        .i_link_flush_req(i_link_flush_req),
        .s_axis_tvalid(bridge_dispatch_tvalid_w),
        .s_axis_tready(bridge_m_axis_tready_w),
        .s_axis_tdata(bridge_m_axis_tdata_w),
        .s_axis_tlast(bridge_m_axis_tlast_w),
        .s_axis_tuser(bridge_m_axis_tuser_w),
        .i_action_valid(action_mailbox_dst_valid_w),
        .o_action_ready(action_mailbox_dst_ready_w),
        .i_action_payload(action_mailbox_dst_payload_w),
        .m_axis_tvalid(dispatch_axis_tvalid_w),
        .m_axis_tready(dispatch_axis_tready_w),
        .m_axis_tdata(dispatch_axis_tdata_w),
        .m_axis_tlast(dispatch_axis_tlast_w),
        .m_axis_tuser(dispatch_axis_tuser_w),
        .o_accept_done_pulse(),
        .o_busy(dispatch_busy_w)
    );

    assign bridge_dispatch_tvalid_w = crypto_consume_enable_q && bridge_m_axis_tvalid_w;
    assign bridge_m_axis_tready_w = crypto_consume_enable_q && dispatch_axis_tready_w;
    assign dispatch_axis_tready_w = crypto_core_tready_w;

    contest_crypto_axis_core u_crypto_core (
        .i_clk(clk_crypto_gated),
        .i_rst_n(crypto_core_rst_n_q),
        .i_soft_reset(1'b0),
        .s_axis_tvalid(dispatch_axis_tvalid_w),
        .s_axis_tready(crypto_core_tready_w),
        .s_axis_tdata(dispatch_axis_tdata_w),
        .s_axis_tlast(dispatch_axis_tlast_w),
        .s_axis_tuser(dispatch_axis_tuser_w),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast),
        .i_acl_cfg_valid(1'b0),
        .i_acl_cfg_index(3'd0),
        .i_acl_cfg_key(128'd0),
        .o_acl_cfg_busy(),
        .o_acl_cfg_done(),
        .o_acl_cfg_error(),
        .o_rule_keys_flat(),
        .o_rule_counts_flat(),
        .o_acl_block_pulse(),
        .o_acl_block_slot_valid(),
        .o_acl_block_slot(),
        .o_pmu_crypto_active(crypto_pmu_active_w),
        .o_clock_idle(crypto_core_idle_w)
    );

    always @(posedge i_ingress_clk or negedge proto_rst_n_async) begin
        if (!proto_rst_n_async) begin
            ingress_frame_active_q <= 1'b0;
            frame_launch_granted_q <= 1'b0;
            action_mailbox_src_valid_q <= 1'b0;
            cnt_ingress_active_cycles_q <= 64'd0;
            cnt_ingress_stall_cycles_q <= 64'd0;
            cnt_ingress_total_bytes_q <= 64'd0;
        end else begin
            if (!ingress_frame_active_q && !frame_launch_granted_q && !action_mailbox_src_valid_q && s_ingress_tvalid) begin
                action_mailbox_src_valid_q <= 1'b1;
            end

            if (action_mailbox_src_valid_q && action_mailbox_src_ready_w) begin
                action_mailbox_src_valid_q <= 1'b0;
                frame_launch_granted_q <= 1'b1;
            end

            if (ingress_fire_w) begin
                cnt_ingress_active_cycles_q <= cnt_ingress_active_cycles_q + 64'd1;
                cnt_ingress_total_bytes_q <= cnt_ingress_total_bytes_q + 64'd1;
                if (!ingress_frame_active_q) begin
                    frame_launch_granted_q <= 1'b0;
                end
                ingress_frame_active_q <= !s_ingress_tlast;
            end else if (s_ingress_tvalid && !s_ingress_tready) begin
                cnt_ingress_stall_cycles_q <= cnt_ingress_stall_cycles_q + 64'd1;
            end
        end
    end

    always @(posedge i_root_clk or negedge proto_rst_n_async) begin
        if (!proto_rst_n_async) begin
            crypto_clk_ce_q <= 1'b1;
            crypto_sleep_count_q <= {SLEEP_COUNT_W{1'b0}};
            crypto_wake_settle_count_q <= {WAKE_SETTLE_W{1'b0}};
            crypto_idle_sync1_q <= 1'b0;
            crypto_idle_sync2_q <= 1'b0;
        end else if (!root_rst_n_sync) begin
            crypto_clk_ce_q <= 1'b1;
            crypto_sleep_count_q <= {SLEEP_COUNT_W{1'b0}};
            crypto_wake_settle_count_q <= {WAKE_SETTLE_W{1'b0}};
            crypto_idle_sync1_q <= 1'b0;
            crypto_idle_sync2_q <= 1'b0;
        end else begin
            crypto_idle_sync1_q <= crypto_core_idle_w;
            crypto_idle_sync2_q <= crypto_idle_sync1_q;
            if (i_link_flush_req || bridge_root_wake_pulse_w) begin
                crypto_clk_ce_q <= 1'b1;
                crypto_sleep_count_q <= {SLEEP_COUNT_W{1'b0}};
                crypto_wake_settle_count_q <= WAKE_SETTLE_INIT;
            end else begin
                if (crypto_wake_settle_count_q != {WAKE_SETTLE_W{1'b0}}) begin
                    crypto_wake_settle_count_q <= crypto_wake_settle_count_q - {{WAKE_SETTLE_W-1{1'b0}}, 1'b1};
                end
                if (crypto_clk_ce_q) begin
                    if (crypto_idle_sync2_q && !crypto_pmu_active_w && !dispatch_busy_w && !action_mailbox_dst_valid_w && o_rd_empty) begin
                        if (crypto_sleep_count_q == CRYPTO_SLEEP_HOLDOFF - 1) begin
                            crypto_clk_ce_q <= 1'b0;
                            crypto_sleep_count_q <= {SLEEP_COUNT_W{1'b0}};
                        end else begin
                            crypto_sleep_count_q <= crypto_sleep_count_q + {{SLEEP_COUNT_W-1{1'b0}}, 1'b1};
                        end
                    end else begin
                        crypto_sleep_count_q <= {SLEEP_COUNT_W{1'b0}};
                    end
                end else begin
                    crypto_sleep_count_q <= {SLEEP_COUNT_W{1'b0}};
                end
            end
        end
    end

    always @(posedge i_root_clk) begin
        if (!root_rst_n_sync) begin
            crypto_consume_enable_q <= 1'b0;
        end else if (i_link_flush_req || bridge_root_wake_pulse_w || !crypto_clk_ce_q) begin
            crypto_consume_enable_q <= 1'b0;
        end else if (crypto_wake_settle_count_q == {WAKE_SETTLE_W{1'b0}}) begin
            crypto_consume_enable_q <= 1'b1;
        end
    end
endmodule