`timescale 1ns/1ps

module contest_byte_skid_buffer (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       s_valid,
    output wire       s_ready,
    input  wire [7:0] s_data,
    output wire       m_valid,
    input  wire       m_ready,
    output wire [7:0] m_data
);

    reg       main_valid_q = 1'b0;
    reg [7:0] main_data_q  = 8'd0;
    reg       skid_valid_q = 1'b0;
    reg [7:0] skid_data_q  = 8'd0;

    wire up_fire_w   = s_valid && s_ready;
    wire down_fire_w = m_valid && m_ready;

    assign s_ready = i_rst_n && !skid_valid_q;
    assign m_valid = main_valid_q;
    assign m_data  = main_data_q;

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            main_valid_q <= 1'b0;
            main_data_q  <= 8'd0;
            skid_valid_q <= 1'b0;
            skid_data_q  <= 8'd0;
        end else if (down_fire_w) begin
            if (skid_valid_q) begin
                main_valid_q <= 1'b1;
                main_data_q  <= skid_data_q;
                skid_valid_q <= 1'b0;
            end else if (up_fire_w) begin
                main_valid_q <= 1'b1;
                main_data_q  <= s_data;
            end else begin
                main_valid_q <= 1'b0;
            end
        end else if (up_fire_w) begin
            if (!main_valid_q) begin
                main_valid_q <= 1'b1;
                main_data_q  <= s_data;
            end else begin
                skid_valid_q <= 1'b1;
                skid_data_q  <= s_data;
            end
        end
    end

endmodule
