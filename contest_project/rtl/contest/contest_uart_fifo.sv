`timescale 1ns/1ps

module contest_uart_fifo #(
    parameter integer DEPTH = 16
) (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_wr_en,
    input  wire [7:0] i_wr_data,
    input  wire       i_rd_en,
    output wire [7:0] o_rd_data,
    output wire       o_full,
    output wire       o_empty,
    output reg        o_overflow,
    output reg        o_underflow
);

    localparam integer ADDR_W = $clog2(DEPTH);

    reg [7:0] mem [0:DEPTH-1];
    reg [ADDR_W-1:0] wr_ptr_q;
    reg [ADDR_W-1:0] rd_ptr_q;
    reg [ADDR_W:0] count_q;

    assign o_rd_data = mem[rd_ptr_q];
    assign o_full    = (count_q == DEPTH);
    assign o_empty   = (count_q == 0);

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            wr_ptr_q    <= {ADDR_W{1'b0}};
            rd_ptr_q    <= {ADDR_W{1'b0}};
            count_q     <= {(ADDR_W+1){1'b0}};
            o_overflow  <= 1'b0;
            o_underflow <= 1'b0;
        end else begin
            o_overflow  <= 1'b0;
            o_underflow <= 1'b0;

            case ({i_wr_en && !o_full, i_rd_en && !o_empty})
                2'b10: begin
                    mem[wr_ptr_q] <= i_wr_data;
                    wr_ptr_q      <= wr_ptr_q + {{(ADDR_W-1){1'b0}}, 1'b1};
                    count_q       <= count_q + {{ADDR_W{1'b0}}, 1'b1};
                end

                2'b01: begin
                    rd_ptr_q <= rd_ptr_q + {{(ADDR_W-1){1'b0}}, 1'b1};
                    count_q  <= count_q - {{ADDR_W{1'b0}}, 1'b1};
                end

                2'b11: begin
                    mem[wr_ptr_q] <= i_wr_data;
                    wr_ptr_q      <= wr_ptr_q + {{(ADDR_W-1){1'b0}}, 1'b1};
                    rd_ptr_q      <= rd_ptr_q + {{(ADDR_W-1){1'b0}}, 1'b1};
                end

                default: begin
                end
            endcase

            if (i_wr_en && o_full) begin
                o_overflow <= 1'b1;
            end

            if (i_rd_en && o_empty) begin
                o_underflow <= 1'b1;
            end
        end
    end

endmodule
