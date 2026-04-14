`timescale 1ns/1ps

module contest_axis_block_packer (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_soft_reset,

    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [7:0]   s_axis_tdata,
    input  wire         s_axis_tlast,
    input  wire [0:0]   s_axis_tuser,

    output reg          m_axis_tvalid,
    input  wire         m_axis_tready,
    output reg  [127:0] m_axis_tdata,
    output reg          m_axis_tlast,
    output reg  [5:0]   m_axis_tuser
);

    reg [127:0] gather_shift_q;
    reg [4:0]   gather_count_q;

    function automatic [127:0] block_insert_byte(
        input [127:0] cur,
        input [4:0]   byte_idx,
        input [7:0]   byte_val
    );
        reg [127:0] tmp;
        begin
            tmp = cur;
            tmp[127 - (byte_idx * 8) -: 8] = byte_val;
            block_insert_byte = tmp;
        end
    endfunction

    assign s_axis_tready = !m_axis_tvalid;

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            gather_shift_q <= 128'd0;
            gather_count_q <= 5'd0;
            m_axis_tvalid  <= 1'b0;
            m_axis_tdata   <= 128'd0;
            m_axis_tlast   <= 1'b0;
            m_axis_tuser   <= 6'd0;
        end else if (i_soft_reset) begin
            gather_shift_q <= 128'd0;
            gather_count_q <= 5'd0;
            m_axis_tvalid  <= 1'b0;
            m_axis_tdata   <= 128'd0;
            m_axis_tlast   <= 1'b0;
            m_axis_tuser   <= 6'd0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end

            if (s_axis_tvalid && s_axis_tready) begin
                gather_shift_q <= block_insert_byte(gather_shift_q, gather_count_q, s_axis_tdata);
                if (s_axis_tlast || (gather_count_q == 5'd15)) begin
                    m_axis_tvalid    <= 1'b1;
                    m_axis_tdata     <= block_insert_byte(gather_shift_q, gather_count_q, s_axis_tdata);
                    m_axis_tlast     <= s_axis_tlast;
                    m_axis_tuser[0]  <= s_axis_tuser[0];
                    m_axis_tuser[1]  <= (gather_count_q != 5'd15);
                    m_axis_tuser[5:2] <= gather_count_q[3:0];
                    gather_shift_q   <= 128'd0;
                    gather_count_q   <= 5'd0;
                end else begin
                    gather_count_q <= gather_count_q + 5'd1;
                end
            end
        end
    end

endmodule
