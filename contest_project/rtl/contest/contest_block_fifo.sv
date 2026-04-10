`timescale 1ns/1ps

module contest_block_fifo #(
    parameter integer WIDTH  = 130,
    parameter integer DEPTH  = 64,
    parameter integer ADDR_W = 6
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               wr_en,
    input  wire [WIDTH-1:0]   wr_data,
    output wire               full,
    input  wire               rd_en,
    output reg  [WIDTH-1:0]   rd_data,
    output reg                rd_valid,
    output wire               empty,
    output wire [ADDR_W:0]    level
);

    (* ram_style = "block" *) reg [WIDTH-1:0] mem_q [0:DEPTH-1];

    reg [ADDR_W-1:0] wr_ptr_q;
    reg [ADDR_W-1:0] rd_ptr_q;
    reg [ADDR_W:0]   count_q;

    wire wr_fire_w;
    wire rd_fire_w;

    function automatic [ADDR_W-1:0] ptr_inc(input [ADDR_W-1:0] ptr);
        begin
            if (ptr == DEPTH - 1) begin
                ptr_inc = {ADDR_W{1'b0}};
            end else begin
                ptr_inc = ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
            end
        end
    endfunction

    assign full  = (count_q == DEPTH);
    assign empty = (count_q == 0);
    assign level = count_q;
    assign wr_fire_w = wr_en && !full;
    assign rd_fire_w = rd_en && !empty;

    // Keep RAM on a dedicated sync process so synthesis can infer BRAM.
    always @(posedge clk) begin
        if (wr_fire_w) begin
            mem_q[wr_ptr_q] <= wr_data;
        end

        if (rd_fire_w) begin
            rd_data <= mem_q[rd_ptr_q];
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr_q <= {ADDR_W{1'b0}};
            rd_ptr_q <= {ADDR_W{1'b0}};
            count_q  <= {(ADDR_W+1){1'b0}};
            rd_valid <= 1'b0;
        end else begin
            rd_valid <= 1'b0;

            if (wr_fire_w) begin
                wr_ptr_q <= ptr_inc(wr_ptr_q);
            end

            if (rd_fire_w) begin
                rd_valid <= 1'b1;
                rd_ptr_q <= ptr_inc(rd_ptr_q);
            end

            case ({wr_fire_w, rd_fire_w})
                2'b10: count_q <= count_q + {{ADDR_W{1'b0}}, 1'b1};
                2'b01: count_q <= count_q - {{ADDR_W{1'b0}}, 1'b1};
                default: count_q <= count_q;
            endcase
        end
    end

endmodule
