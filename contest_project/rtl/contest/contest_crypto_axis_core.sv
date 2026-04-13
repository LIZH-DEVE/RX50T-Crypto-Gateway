`timescale 1ns/1ps

module contest_crypto_axis_core (
    input  wire       i_clk,
    input  wire       i_rst_n,

    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tlast,
    input  wire [0:0] s_axis_tuser,

    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tlast,

    input  wire       i_acl_cfg_valid,
    input  wire [2:0] i_acl_cfg_index,
    input  wire [7:0] i_acl_cfg_key,
    output wire       o_acl_cfg_busy,
    output wire       o_acl_cfg_done,
    output wire       o_acl_cfg_error,
    output wire [63:0] o_rule_keys_flat,
    output wire [63:0] o_rule_counts_flat,
    output wire       o_acl_block_pulse,
    output wire       o_acl_block_slot_valid,
    output wire [2:0] o_acl_block_slot,
    output wire       o_pmu_crypto_active
);

    wire       acl_axis_tvalid;
    wire       acl_axis_tready;
    wire [7:0] acl_axis_tdata;
    wire       acl_axis_tlast;
    wire [0:0] acl_axis_tuser;

    wire         blk_in_tvalid;
    wire         blk_in_tready;
    wire [127:0] blk_in_tdata;
    wire         blk_in_tlast;
    wire [5:0]   blk_in_tuser;

    wire         blk_out_tvalid;
    wire         blk_out_tready;
    wire [127:0] blk_out_tdata;
    wire         blk_out_tlast;
    wire [5:0]   blk_out_tuser;

    contest_acl_axis_core u_acl_axis (
        .i_clk                 (i_clk),
        .i_rst_n               (i_rst_n),
        .s_axis_tvalid         (s_axis_tvalid),
        .s_axis_tready         (s_axis_tready),
        .s_axis_tdata          (s_axis_tdata),
        .s_axis_tlast          (s_axis_tlast),
        .s_axis_tuser          (s_axis_tuser),
        .m_axis_tvalid         (acl_axis_tvalid),
        .m_axis_tready         (acl_axis_tready),
        .m_axis_tdata          (acl_axis_tdata),
        .m_axis_tlast          (acl_axis_tlast),
        .m_axis_tuser          (acl_axis_tuser),
        .i_cfg_valid           (i_acl_cfg_valid),
        .i_cfg_index           (i_acl_cfg_index),
        .i_cfg_key             (i_acl_cfg_key),
        .o_cfg_busy            (o_acl_cfg_busy),
        .o_cfg_done            (o_acl_cfg_done),
        .o_cfg_error           (o_acl_cfg_error),
        .o_acl_block_pulse     (o_acl_block_pulse),
        .o_acl_block_slot_valid(o_acl_block_slot_valid),
        .o_acl_block_slot      (o_acl_block_slot),
        .o_rule_keys_flat      (o_rule_keys_flat),
        .o_rule_counts_flat    (o_rule_counts_flat)
    );

    contest_axis_block_packer u_packer (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .s_axis_tvalid(acl_axis_tvalid),
        .s_axis_tready(acl_axis_tready),
        .s_axis_tdata (acl_axis_tdata),
        .s_axis_tlast (acl_axis_tlast),
        .s_axis_tuser (acl_axis_tuser),
        .m_axis_tvalid(blk_in_tvalid),
        .m_axis_tready(blk_in_tready),
        .m_axis_tdata (blk_in_tdata),
        .m_axis_tlast (blk_in_tlast),
        .m_axis_tuser (blk_in_tuser)
    );

    contest_crypto_block_engine u_block_engine (
        .i_clk             (i_clk),
        .i_rst_n           (i_rst_n),
        .s_axis_tvalid     (blk_in_tvalid),
        .s_axis_tready     (blk_in_tready),
        .s_axis_tdata      (blk_in_tdata),
        .s_axis_tlast      (blk_in_tlast),
        .s_axis_tuser      (blk_in_tuser),
        .m_axis_tvalid     (blk_out_tvalid),
        .m_axis_tready     (blk_out_tready),
        .m_axis_tdata      (blk_out_tdata),
        .m_axis_tlast      (blk_out_tlast),
        .m_axis_tuser      (blk_out_tuser),
        .o_pmu_crypto_active(o_pmu_crypto_active)
    );

    contest_axis_block_unpacker u_unpacker (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .s_axis_tvalid(blk_out_tvalid),
        .s_axis_tready(blk_out_tready),
        .s_axis_tdata (blk_out_tdata),
        .s_axis_tlast (blk_out_tlast),
        .s_axis_tuser (blk_out_tuser),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tlast (m_axis_tlast)
    );

endmodule
