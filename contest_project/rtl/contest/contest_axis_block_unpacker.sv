`timescale 1ns/1ps

module contest_axis_block_unpacker (
    input  wire         i_clk,
    input  wire         i_rst_n,

    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [127:0] s_axis_tdata,
    input  wire         s_axis_tlast,
    input  wire [5:0]   s_axis_tuser,

    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire [7:0]   m_axis_tdata,
    output wire         m_axis_tlast
);

    reg [127:0] block_data_q;
    reg         block_last_q;
    reg [4:0]   block_valid_bytes_q;
    reg         block_valid_q;
    reg [4:0]   byte_idx_q;

    function automatic [7:0] select_byte(
        input [127:0] data,
        input [4:0]   idx
    );
        begin
            select_byte = data[127 - (idx * 8) -: 8];
        end
    endfunction

    assign s_axis_tready = !block_valid_q;
    assign m_axis_tvalid = block_valid_q;
    assign m_axis_tdata  = select_byte(block_data_q, byte_idx_q);
    assign m_axis_tlast  = block_valid_q &&
                           block_last_q &&
                           (byte_idx_q == (block_valid_bytes_q - 5'd1));

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            block_data_q        <= 128'd0;
            block_last_q        <= 1'b0;
            block_valid_bytes_q <= 5'd0;
            block_valid_q       <= 1'b0;
            byte_idx_q          <= 5'd0;
        end else begin
            if (block_valid_q && m_axis_tready) begin
                if (byte_idx_q == (block_valid_bytes_q - 5'd1)) begin
                    block_valid_q       <= 1'b0;
                    byte_idx_q          <= 5'd0;
                    block_valid_bytes_q <= 5'd0;
                    block_last_q        <= 1'b0;
                    block_data_q        <= 128'd0;
                end else begin
                    byte_idx_q <= byte_idx_q + 5'd1;
                end
            end

            if (s_axis_tvalid && s_axis_tready) begin
                block_data_q        <= s_axis_tdata;
                block_last_q        <= s_axis_tlast;
                block_valid_bytes_q <= {1'b0, s_axis_tuser[5:2]} + 5'd1;
                block_valid_q       <= 1'b1;
                byte_idx_q          <= 5'd0;
            end
        end
    end

endmodule
