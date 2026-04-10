`timescale 1ns/1ps

module tb_contest_block_fifo;

    localparam WIDTH = 16;
    localparam DEPTH = 16;
    localparam AW    = 4;

    reg              clk;
    reg              rst_n;
    reg              wr_en;
    reg  [WIDTH-1:0] wr_data;
    wire             full;
    reg              rd_en;
    wire [WIDTH-1:0] rd_data;
    wire             rd_valid;
    wire             empty;
    wire [AW:0]      level;

    contest_block_fifo #(
        .WIDTH (WIDTH),
        .DEPTH (DEPTH),
        .ADDR_W(AW)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (wr_en),
        .wr_data(wr_data),
        .full   (full),
        .rd_en  (rd_en),
        .rd_data(rd_data),
        .rd_valid(rd_valid),
        .empty  (empty),
        .level  (level)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic fifo_write(input [WIDTH-1:0] value);
        begin
            @(negedge clk);
            wr_data <= value;
            wr_en   <= 1'b1;
            @(negedge clk);
            wr_en   <= 1'b0;
            wr_data <= {WIDTH{1'b0}};
        end
    endtask

    task automatic fifo_read_expect(input [WIDTH-1:0] value);
        begin
            @(negedge clk);
            rd_en <= 1'b1;
            @(posedge rd_valid);
            #1;
            if (rd_data !== value) begin
                $display("FIFO data mismatch. expected=%h got=%h", value, rd_data);
                $fatal(1);
            end
            @(negedge clk);
            rd_en <= 1'b0;
        end
    endtask

    initial begin
        rst_n   = 1'b0;
        wr_en   = 1'b0;
        wr_data = {WIDTH{1'b0}};
        rd_en   = 1'b0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        fifo_write(16'h1234);
        fifo_write(16'habcd);

        if (level !== 2) begin
            $display("FIFO level mismatch after writes. expected=2 got=%0d", level);
            $fatal(1);
        end

        fifo_read_expect(16'h1234);
        fifo_read_expect(16'habcd);

        if (!empty) begin
            $display("FIFO expected empty after reads.");
            $fatal(1);
        end

        @(negedge clk);
        wr_data <= 16'h55aa;
        wr_en   <= 1'b1;
        rd_en   <= 1'b1;
        @(negedge clk);
        wr_en   <= 1'b0;
        wr_data <= {WIDTH{1'b0}};
        rd_en   <= 1'b0;

        fifo_read_expect(16'h55aa);

        $display("contest_block_fifo test passed.");
        $finish;
    end

endmodule
