`timescale 1ns / 1ps

module tb_acl_match_engine_sanity;

    logic clk;
    logic rst_n;
    logic [103:0] tuple_in;
    logic tuple_valid;
    logic acl_write_en;
    logic [11:0] acl_write_addr;
    logic [103:0] acl_write_data;
    logic acl_clear;
    logic result_valid;
    logic acl_hit;
    logic acl_drop;
    logic [1:0] hit_way;
    logic [31:0] hit_count;
    logic [31:0] miss_count;

    function automatic [15:0] tuple_hash(input [103:0] data);
        logic [15:0] h;
        begin
            h = data[15:0] ^ data[31:16] ^ data[47:32] ^ data[63:48] ^
                data[79:64] ^ data[95:80] ^ {8'h00, data[103:96]};
            h = h ^ {h[7:0], h[15:8]} ^ 16'h9E37;
            tuple_hash = h ^ {h[10:0], h[15:11]} ^ (h >> 3);
        end
    endfunction

    acl_match_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .tuple_in(tuple_in),
        .tuple_valid(tuple_valid),
        .acl_write_en(acl_write_en),
        .acl_write_addr(acl_write_addr),
        .acl_write_data(acl_write_data),
        .acl_clear(acl_clear),
        .result_valid(result_valid),
        .acl_hit(acl_hit),
        .acl_drop(acl_drop),
        .hit_way(hit_way),
        .hit_count(hit_count),
        .miss_count(miss_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        #40;
        rst_n = 1'b1;
    end

    task automatic do_lookup(input [103:0] tuple);
        begin
            tuple_in <= tuple;
            tuple_valid <= 1'b1;
            @(posedge clk);
            tuple_valid <= 1'b0;
            tuple_in <= '0;
            do @(posedge clk); while (!result_valid);
        end
    endtask

    initial begin
        logic [103:0] hit_tuple;
        logic [103:0] miss_tuple;
        logic [15:0] hit_hash;
        logic [11:0] hit_addr;

        tuple_in = '0;
        tuple_valid = 1'b0;
        acl_write_en = 1'b0;
        acl_write_addr = '0;
        acl_write_data = '0;
        acl_clear = 1'b0;

        hit_tuple  = {8'd17, 32'hC0A8_0001, 16'd1234, 32'hC0A8_0002, 16'd4321};
        miss_tuple = {8'd6,  32'hC0A8_0001, 16'd1111, 32'hC0A8_0002, 16'd80};
        hit_hash   = tuple_hash(hit_tuple);
        hit_addr   = hit_hash[11:0];

        wait(rst_n);
        repeat (2) @(posedge clk);

        acl_write_addr <= hit_addr;
        acl_write_data <= hit_tuple;
        acl_write_en <= 1'b1;
        @(posedge clk);
        acl_write_en <= 1'b0;
        repeat (2) @(posedge clk);

        do_lookup(hit_tuple);
        if (!acl_hit || !acl_drop || hit_count != 32'd1 || miss_count != 32'd0) begin
            $fatal(1, "ACL hit path failed: hit=%0d drop=%0d hit_count=%0d miss_count=%0d hit_way=%0d",
                   acl_hit, acl_drop, hit_count, miss_count, hit_way);
        end

        do_lookup(miss_tuple);
        if (acl_hit || acl_drop || hit_count != 32'd1 || miss_count != 32'd1) begin
            $fatal(1, "ACL miss path failed: hit=%0d drop=%0d hit_count=%0d miss_count=%0d",
                   acl_hit, acl_drop, hit_count, miss_count);
        end

        $display("PASS: acl_match_engine sanity");
        $finish;
    end

endmodule
