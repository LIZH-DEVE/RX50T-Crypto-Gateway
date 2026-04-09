`timescale 1ns/1ps

module tb_contest_acl_core;

    reg clk;
    reg rst_n;
    reg parser_valid;
    reg [7:0] parser_match_key;
    reg [7:0] parser_payload;
    reg parser_last;
    wire acl_valid;
    wire [7:0] acl_data;
    wire acl_last;

    reg [7:0] capture_data [0:31];
    reg       capture_last [0:31];
    integer   capture_idx;

    contest_acl_core dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .parser_valid   (parser_valid),
        .parser_match_key(parser_match_key),
        .parser_payload (parser_payload),
        .parser_last    (parser_last),
        .acl_valid      (acl_valid),
        .acl_data       (acl_data),
        .acl_last       (acl_last)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            capture_idx <= 0;
        end else if (acl_valid) begin
            capture_data[capture_idx] <= acl_data;
            capture_last[capture_idx] <= acl_last;
            capture_idx <= capture_idx + 1;
        end
    end

    task automatic drive_byte(
        input [7:0] key,
        input [7:0] payload,
        input       last_flag
    );
        begin
            @(posedge clk);
            parser_valid     <= 1'b1;
            parser_match_key <= key;
            parser_payload   <= payload;
            parser_last      <= last_flag;
            @(posedge clk);
            parser_valid     <= 1'b0;
            parser_match_key <= 8'd0;
            parser_payload   <= 8'd0;
            parser_last      <= 1'b0;
        end
    endtask

    task automatic expect_capture_count(input integer expected);
        integer wait_cycles;
        begin
            wait_cycles = 0;
            while ((capture_idx != expected) && (wait_cycles < 64)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (capture_idx != expected) begin
                $fatal(1, "Expected capture count %0d, got %0d", expected, capture_idx);
            end
        end
    endtask

    initial begin
        rst_n            = 1'b0;
        parser_valid     = 1'b0;
        parser_match_key = 8'd0;
        parser_payload   = 8'd0;
        parser_last      = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Pass-through frame: ABC
        drive_byte(8'h41, 8'h41, 1'b0);
        drive_byte(8'h41, 8'h42, 1'b0);
        drive_byte(8'h41, 8'h43, 1'b1);
        repeat (8) @(posedge clk);

        expect_capture_count(3);
        if (capture_data[0] != 8'h41 || capture_last[0] != 1'b0) $fatal(1, "Pass-through byte0 mismatch");
        if (capture_data[1] != 8'h42 || capture_last[1] != 1'b0) $fatal(1, "Pass-through byte1 mismatch");
        if (capture_data[2] != 8'h43 || capture_last[2] != 1'b1) $fatal(1, "Pass-through byte2 mismatch");

        // Blocked frame: key X, payload XYZ -> D\n
        drive_byte(8'h58, 8'h58, 1'b0);
        drive_byte(8'h58, 8'h59, 1'b0);
        drive_byte(8'h58, 8'h5A, 1'b1);
        repeat (8) @(posedge clk);

        expect_capture_count(5);
        if (capture_data[3] != 8'h44 || capture_last[3] != 1'b0) $fatal(1, "Drop byte0 mismatch");
        if (capture_data[4] != 8'h0A || capture_last[4] != 1'b1) $fatal(1, "Drop byte1 mismatch");

        // Single-byte blocked frame should still emit D\n
        drive_byte(8'h58, 8'h58, 1'b1);
        repeat (8) @(posedge clk);

        expect_capture_count(7);
        if (capture_data[5] != 8'h44 || capture_last[5] != 1'b0) $fatal(1, "Single drop byte0 mismatch");
        if (capture_data[6] != 8'h0A || capture_last[6] != 1'b1) $fatal(1, "Single drop byte1 mismatch");

        // Additional fixed rules: Y, Z, W should all block.
        drive_byte(8'h59, 8'h59, 1'b1);
        repeat (8) @(posedge clk);
        expect_capture_count(9);
        if (capture_data[7] != 8'h44 || capture_last[7] != 1'b0) $fatal(1, "Y rule byte0 mismatch");
        if (capture_data[8] != 8'h0A || capture_last[8] != 1'b1) $fatal(1, "Y rule byte1 mismatch");

        drive_byte(8'h5A, 8'h5A, 1'b1);
        repeat (8) @(posedge clk);
        expect_capture_count(11);
        if (capture_data[9] != 8'h44 || capture_last[9] != 1'b0) $fatal(1, "Z rule byte0 mismatch");
        if (capture_data[10] != 8'h0A || capture_last[10] != 1'b1) $fatal(1, "Z rule byte1 mismatch");

        drive_byte(8'h57, 8'h57, 1'b1);
        repeat (8) @(posedge clk);
        expect_capture_count(13);
        if (capture_data[11] != 8'h44 || capture_last[11] != 1'b0) $fatal(1, "W rule byte0 mismatch");
        if (capture_data[12] != 8'h0A || capture_last[12] != 1'b1) $fatal(1, "W rule byte1 mismatch");

        // Expanded default BRAM-backed rules: P, R, T, U should also block.
        drive_byte(8'h50, 8'h50, 1'b1);
        repeat (8) @(posedge clk);
        expect_capture_count(15);
        if (capture_data[13] != 8'h44 || capture_last[13] != 1'b0) $fatal(1, "P rule byte0 mismatch");
        if (capture_data[14] != 8'h0A || capture_last[14] != 1'b1) $fatal(1, "P rule byte1 mismatch");

        drive_byte(8'h52, 8'h52, 1'b1);
        repeat (8) @(posedge clk);
        expect_capture_count(17);
        if (capture_data[15] != 8'h44 || capture_last[15] != 1'b0) $fatal(1, "R rule byte0 mismatch");
        if (capture_data[16] != 8'h0A || capture_last[16] != 1'b1) $fatal(1, "R rule byte1 mismatch");

        drive_byte(8'h54, 8'h54, 1'b1);
        repeat (8) @(posedge clk);
        expect_capture_count(19);
        if (capture_data[17] != 8'h44 || capture_last[17] != 1'b0) $fatal(1, "T rule byte0 mismatch");
        if (capture_data[18] != 8'h0A || capture_last[18] != 1'b1) $fatal(1, "T rule byte1 mismatch");

        drive_byte(8'h55, 8'h55, 1'b1);
        repeat (8) @(posedge clk);
        expect_capture_count(21);
        if (capture_data[19] != 8'h44 || capture_last[19] != 1'b0) $fatal(1, "U rule byte0 mismatch");
        if (capture_data[20] != 8'h0A || capture_last[20] != 1'b1) $fatal(1, "U rule byte1 mismatch");

        // Recovery after BRAM-backed lookup and drop: legal frame should still pass.
        drive_byte(8'h51, 8'h51, 1'b0);
        drive_byte(8'h51, 8'h52, 1'b1);
        repeat (8) @(posedge clk);
        expect_capture_count(23);
        if (capture_data[21] != 8'h51 || capture_last[21] != 1'b0) $fatal(1, "Recovery byte0 mismatch");
        if (capture_data[22] != 8'h52 || capture_last[22] != 1'b1) $fatal(1, "Recovery byte1 mismatch");

        $display("contest_acl_core test passed.");
        $finish;
    end

endmodule
