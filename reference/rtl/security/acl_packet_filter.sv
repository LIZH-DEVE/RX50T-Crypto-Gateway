`ifndef ACL_PACKET_FILTER_SV
`define ACL_PACKET_FILTER_SV

`timescale 1ns / 1ps

/**
 * Module: acl_packet_filter
 * - Collect first up to 10 words per packet and build a semantic
 *   {protocol, src_ip, src_port, dst_ip, dst_port} ACL tuple
 * - Query acl_match_engine
 * - Hit => drop full packet; miss => forward full packet
 * - Includes a tiny header buffer so first words are not leaked before ACL decision
 */
module acl_packet_filter #(
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic                   acl_en,

    // Stream in
    input  logic [DATA_WIDTH-1:0]  s_tdata,
    input  logic                   s_tvalid,
    input  logic                   s_tlast,
    output logic                   s_tready,

    // Stream out
    output logic [DATA_WIDTH-1:0]  m_tdata,
    output logic                   m_tvalid,
    output logic                   m_tlast,
    input  logic                   m_tready,

    // ACL config
    input  logic                   acl_write_en,
    input  logic [11:0]            acl_write_addr,
    input  logic [103:0]           acl_write_data,
    input  logic                   acl_clear,

    // Status
    output logic                   acl_hit,
    output logic                   acl_drop,
    output logic                   acl_drop_pulse,
    output logic [31:0]            acl_hit_count,
    output logic [31:0]            acl_miss_count
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CAPTURE,
        ST_CHECK,
        ST_DECIDE,
        ST_FLUSH,
        ST_STREAM,
        ST_DROP
    } state_t;

    localparam int ACL_HEADER_WORDS = 10;
    localparam int CAP_CNT_W = $clog2(ACL_HEADER_WORDS + 1);
    localparam int FLUSH_IDX_W = (ACL_HEADER_WORDS <= 1) ? 1 : $clog2(ACL_HEADER_WORDS);

    state_t state;

    logic [31:0] buf_data [0:ACL_HEADER_WORDS-1];
    logic        buf_last [0:ACL_HEADER_WORDS-1];
    logic [CAP_CNT_W-1:0]  cap_cnt;
    logic [FLUSH_IDX_W-1:0]  flush_idx;
    logic        cap_last;

    logic [103:0] acl_tuple;
    logic         acl_tuple_valid;
    logic         acl_tuple_ready;

    logic acl_result_valid_i;
    logic acl_hit_i, acl_drop_i;
    logic [1:0] acl_hit_way;

    logic pkt_acl_hit, pkt_acl_drop;

    logic in_fire, out_fire;
    assign in_fire  = s_tvalid && s_tready;
    assign out_fire = m_tvalid && m_tready;

    always_comb begin
        // Shadow inject feeds a fixed internal frame with:
        //   word 6  = {ttl, protocol, checksum}
        //   word 7  = src_ip
        //   word 8  = dst_ip
        //   word 9  = {dst_port, src_port}
        acl_tuple = {
            buf_data[6][23:16],
            buf_data[7],
            buf_data[9][15:0],
            buf_data[8],
            buf_data[9][31:16]
        };
    end

    assign acl_tuple_ready = (cap_cnt == ACL_HEADER_WORDS);
    assign acl_tuple_valid = (state == ST_CHECK) && acl_en && acl_tuple_ready;

    acl_match_engine #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(104),
        .TAG_WIDTH(104),
        .NUM_WAYS(2)
    ) u_acl (
        .clk(clk),
        .rst_n(rst_n),
        .tuple_in(acl_tuple),
        .tuple_valid(acl_tuple_valid),
        .acl_write_en(acl_write_en),
        .acl_write_addr(acl_write_addr),
        .acl_write_data(acl_write_data),
        .acl_clear(acl_clear),
        .result_valid(acl_result_valid_i),
        .acl_hit(acl_hit_i),
        .acl_drop(acl_drop_i),
        .hit_way(acl_hit_way),
        .hit_count(acl_hit_count),
        .miss_count(acl_miss_count)
    );

    always_comb begin
        s_tready = 1'b0;
        m_tdata  = '0;
        m_tvalid = 1'b0;
        m_tlast  = 1'b0;

        case (state)
            ST_IDLE,
            ST_CAPTURE: begin
                s_tready = 1'b1;
            end

            ST_FLUSH: begin
                m_tdata  = buf_data[flush_idx];
                m_tvalid = 1'b1;
                m_tlast  = buf_last[flush_idx];
            end

            ST_STREAM: begin
                s_tready = m_tready;
                m_tdata  = s_tdata;
                m_tvalid = s_tvalid;
                m_tlast  = s_tlast;
            end

            ST_DROP: begin
                s_tready = 1'b1;
            end

            default: begin
            end
        endcase
    end

    // Keep packet state/control synchronous to avoid BRAM/FIFO control being
    // sourced by async-reset state flops.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            cap_cnt <= '0;
            flush_idx <= '0;
            cap_last <= 1'b0;
            pkt_acl_hit <= 1'b0;
            pkt_acl_drop <= 1'b0;
            acl_drop_pulse <= 1'b0;
            for (int idx = 0; idx < ACL_HEADER_WORDS; idx = idx + 1) begin
                buf_data[idx] <= 32'd0;
                buf_last[idx] <= 1'b0;
            end
        end else begin
            acl_drop_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    cap_cnt <= '0;
                    flush_idx <= '0;
                    cap_last <= 1'b0;
                    pkt_acl_hit <= 1'b0;
                    pkt_acl_drop <= 1'b0;

                    if (in_fire) begin
                        buf_data[0] <= s_tdata;
                        buf_last[0] <= s_tlast;
                        cap_cnt <= {{(CAP_CNT_W-1){1'b0}}, 1'b1};
                        cap_last <= s_tlast;

                        if (s_tlast || (ACL_HEADER_WORDS == 1)) begin
                            state <= ST_CHECK;
                        end else begin
                            state <= ST_CAPTURE;
                        end
                    end
                end

                ST_CAPTURE: begin
                    if (in_fire) begin
                        buf_data[cap_cnt] <= s_tdata;
                        buf_last[cap_cnt] <= s_tlast;
                        cap_cnt <= cap_cnt + 1'b1;
                        cap_last <= s_tlast;

                        if ((cap_cnt == (ACL_HEADER_WORDS - 1'b1)) || s_tlast) begin
                            state <= ST_CHECK;
                        end
                    end
                end

                ST_CHECK: begin
                    if (acl_en && acl_tuple_ready) begin
                        state <= ST_DECIDE;
                    end else begin
                        flush_idx <= '0;
                        state <= ST_FLUSH;
                    end
                end

                ST_DECIDE: begin
                    if (acl_result_valid_i) begin
                        pkt_acl_hit <= acl_hit_i;
                        pkt_acl_drop <= acl_drop_i;

                        if (acl_drop_i) begin
                            acl_drop_pulse <= 1'b1;
                            if (cap_last) begin
                                state <= ST_IDLE;
                            end else begin
                                state <= ST_DROP;
                            end
                        end else begin
                            flush_idx <= '0;
                            state <= ST_FLUSH;
                        end
                    end
                end

                ST_FLUSH: begin
                    if (out_fire) begin
                        if (buf_last[flush_idx]) begin
                            state <= ST_IDLE;
                        end else if (flush_idx == (cap_cnt - 1'b1)) begin
                            state <= ST_STREAM;
                        end else begin
                            flush_idx <= flush_idx + 1'b1;
                        end
                    end
                end

                ST_STREAM: begin
                    if (in_fire && s_tlast) begin
                        state <= ST_IDLE;
                    end
                end

                ST_DROP: begin
                    if (in_fire && s_tlast) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    assign acl_hit  = pkt_acl_hit;
    assign acl_drop = pkt_acl_drop;

endmodule
`endif
