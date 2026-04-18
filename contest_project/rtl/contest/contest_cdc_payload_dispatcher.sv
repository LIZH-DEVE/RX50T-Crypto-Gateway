`timescale 1ns/1ps

import contest_cdc_ingress_pkg::*;

module contest_cdc_payload_dispatcher (
    input  wire                    i_crypto_clk,
    input  wire                    i_crypto_rst_n_async,
    input  wire                    i_link_flush_req,

    input  wire                    s_axis_tvalid,
    output wire                    s_axis_tready,
    input  wire [7:0]              s_axis_tdata,
    input  wire                    s_axis_tlast,
    input  wire [0:0]              s_axis_tuser,

    input  wire                    i_action_valid,
    output wire                    o_action_ready,
    input  wire [CDC_ACTION_W-1:0] i_action_payload,

    output wire                    m_axis_tvalid,
    input  wire                    m_axis_tready,
    output wire [7:0]              m_axis_tdata,
    output wire                    m_axis_tlast,
    output wire [0:0]              m_axis_tuser,

    output wire                    o_accept_done_pulse,
    output wire                    o_busy
);

    localparam [1:0] ST_IDLE   = 2'd0;
    localparam [1:0] ST_ACCEPT = 2'd1;
    localparam [1:0] ST_DRAIN  = 2'd2;

    wire crypto_rst_n_sync;
    wire link_rst_n_async;
    wire [1:0] action_kind_w;
    wire [7:0] action_payload_len_w;
    wire action_fire_w;
    wire payload_fire_w;
    wire final_payload_fire_w;

    reg [1:0] state_q;
    reg [7:0] bytes_left_q;
    reg       accept_done_q;
    reg       crypto_port_active_q;

    assign link_rst_n_async     = i_crypto_rst_n_async && !i_link_flush_req;
    assign action_kind_w        = i_action_payload[CDC_ACTION_W-1 -: 2];
    assign action_payload_len_w = i_action_payload[7:0];
    assign o_action_ready       = (state_q == ST_IDLE) && crypto_port_active_q;
    assign action_fire_w        = i_action_valid && o_action_ready;

    assign m_axis_tvalid        = crypto_rst_n_sync && crypto_port_active_q && (state_q == ST_ACCEPT) && s_axis_tvalid;
    assign m_axis_tdata         = s_axis_tdata;
    assign m_axis_tlast         = (bytes_left_q == 8'd1);
    assign m_axis_tuser         = s_axis_tuser;

    assign s_axis_tready        = crypto_port_active_q && (((state_q == ST_ACCEPT) && m_axis_tready) ||
                                  (state_q == ST_DRAIN));
    assign payload_fire_w       = s_axis_tvalid && s_axis_tready;
    assign final_payload_fire_w = payload_fire_w && (bytes_left_q == 8'd1);
    assign o_accept_done_pulse  = accept_done_q;
    assign o_busy               = crypto_port_active_q && (state_q != ST_IDLE);

    contest_reset_sync u_crypto_reset_sync (
        .i_clk        (i_crypto_clk),
        .i_rst_n_async(link_rst_n_async),
        .o_rst_n_sync (crypto_rst_n_sync)
    );

    always @(posedge i_crypto_clk) begin
        if (!crypto_rst_n_sync) begin
            state_q              <= ST_IDLE;
            bytes_left_q         <= 8'd0;
            accept_done_q        <= 1'b0;
            crypto_port_active_q <= 1'b0;
        end else begin
            accept_done_q        <= 1'b0;
            crypto_port_active_q <= 1'b1;

            if (action_fire_w) begin
                bytes_left_q <= action_payload_len_w;
                case (action_kind_w)
                    CDC_ACTION_KIND_ACCEPT: state_q <= ST_ACCEPT;
                    CDC_ACTION_KIND_DRAIN:  state_q <= ST_DRAIN;
                    default: begin
                        state_q      <= ST_IDLE;
                        bytes_left_q <= 8'd0;
                    end
                endcase
            end else if (payload_fire_w) begin
                if (bytes_left_q != 8'd0) begin
                    bytes_left_q <= bytes_left_q - 8'd1;
                end
                if (final_payload_fire_w) begin
                    if (state_q == ST_ACCEPT) begin
                        accept_done_q <= 1'b1;
                    end
                    state_q <= ST_IDLE;
                end
            end
        end
    end

endmodule