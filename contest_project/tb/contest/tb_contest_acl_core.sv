`timescale 1ns/1ps

module tb_contest_acl_core;

    reg clk;
    reg rst_n;
    reg parser_valid;
    reg [7:0] parser_match_key;
    reg [7:0] parser_payload;
    reg parser_last;
    reg cfg_valid;
    reg [2:0] cfg_index;
    reg [7:0] cfg_key;
    wire acl_valid;
    wire [7:0] acl_data;
    wire acl_last;
    wire acl_blocked;
    wire acl_block_slot_valid;
    wire [2:0] acl_block_slot;
    wire cfg_busy;
    wire cfg_done;
    wire cfg_error;
    wire [63:0] rule_keys_flat;
    wire [63:0] rule_counts_flat;

    reg [7:0] capture_data [0:63];
    reg       capture_last [0:63];
    integer   capture_idx;
    reg       last_block_slot_valid_q;
    reg [2:0] last_block_slot_q;

    function automatic [7:0] flat_key(input integer slot_idx);
        begin
            flat_key = rule_keys_flat[slot_idx*8 +: 8];
        end
    endfunction

    function automatic [7:0] flat_count(input integer slot_idx);
        begin
            flat_count = rule_counts_flat[slot_idx*8 +: 8];
        end
    endfunction

    contest_acl_core dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .parser_valid      (parser_valid),
        .parser_match_key  (parser_match_key),
        .parser_payload    (parser_payload),
        .parser_last       (parser_last),
        .cfg_valid         (cfg_valid),
        .cfg_index         (cfg_index),
        .cfg_key           (cfg_key),
        .acl_valid         (acl_valid),
        .acl_data          (acl_data),
        .acl_last          (acl_last),
        .acl_blocked       (acl_blocked),
        .acl_block_slot_valid(acl_block_slot_valid),
        .acl_block_slot    (acl_block_slot),
        .cfg_busy          (cfg_busy),
        .cfg_done          (cfg_done),
        .cfg_error         (cfg_error),
        .o_rule_keys_flat  (rule_keys_flat),
        .o_rule_counts_flat(rule_counts_flat)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            capture_idx <= 0;
            last_block_slot_valid_q <= 1'b0;
            last_block_slot_q <= 3'd0;
        end else if (acl_valid) begin
            capture_data[capture_idx] <= acl_data;
            capture_last[capture_idx] <= acl_last;
            capture_idx <= capture_idx + 1;
            if (acl_block_slot_valid) begin
                last_block_slot_valid_q <= 1'b1;
                last_block_slot_q <= acl_block_slot;
            end
        end else if (acl_block_slot_valid) begin
            last_block_slot_valid_q <= 1'b1;
            last_block_slot_q <= acl_block_slot;
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

    task automatic drive_two_byte_frame(
        input [7:0] key,
        input [7:0] b0,
        input [7:0] b1
    );
        begin
            drive_byte(key, b0, 1'b0);
            drive_byte(key, b1, 1'b1);
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

    task automatic expect_cfg_success(input [2:0] slot_idx, input [7:0] key_value);
        integer wait_cycles;
        begin
            @(posedge clk);
            cfg_valid <= 1'b1;
            cfg_index <= slot_idx;
            cfg_key   <= key_value;
            @(posedge clk);
            cfg_valid <= 1'b0;
            cfg_index <= 3'd0;
            cfg_key   <= 8'd0;

            wait_cycles = 0;
            while (!cfg_done && !cfg_error && (wait_cycles < 64)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (cfg_error) begin
                $fatal(1, "Expected cfg_done for slot %0d key %02x, but cfg_error asserted", slot_idx, key_value);
            end
            if (!cfg_done) begin
                $fatal(1, "Timed out waiting for cfg_done");
            end
        end
    endtask

    task automatic expect_cfg_error(input [2:0] slot_idx, input [7:0] key_value);
        integer wait_cycles;
        begin
            @(posedge clk);
            cfg_valid <= 1'b1;
            cfg_index <= slot_idx;
            cfg_key   <= key_value;
            @(posedge clk);
            cfg_valid <= 1'b0;
            cfg_index <= 3'd0;
            cfg_key   <= 8'd0;

            wait_cycles = 0;
            while (!cfg_done && !cfg_error && (wait_cycles < 64)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (cfg_done) begin
                $fatal(1, "Expected cfg_error for slot %0d key %02x, but cfg_done asserted", slot_idx, key_value);
            end
            if (!cfg_error) begin
                $fatal(1, "Timed out waiting for cfg_error");
            end
        end
    endtask

    initial begin
        rst_n            = 1'b0;
        parser_valid     = 1'b0;
        parser_match_key = 8'd0;
        parser_payload   = 8'd0;
        parser_last      = 1'b0;
        cfg_valid        = 1'b0;
        cfg_index        = 3'd0;
        cfg_key          = 8'd0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        if (flat_key(0) != 8'h58 || flat_key(1) != 8'h59 || flat_key(2) != 8'h5A || flat_key(3) != 8'h57 ||
            flat_key(4) != 8'h50 || flat_key(5) != 8'h52 || flat_key(6) != 8'h54 || flat_key(7) != 8'h55) begin
            $fatal(1, "Default ACL key map mismatch");
        end

        // Pass-through frame: AB
        drive_two_byte_frame(8'h41, 8'h41, 8'h42);
        repeat (8) @(posedge clk);
        expect_capture_count(2);
        if (capture_data[0] != 8'h41 || capture_last[0] != 1'b0) $fatal(1, "Pass-through byte0 mismatch");
        if (capture_data[1] != 8'h42 || capture_last[1] != 1'b1) $fatal(1, "Pass-through byte1 mismatch");

        // Blocked frame: W -> D\n and slot 3 counter increments.
        drive_two_byte_frame(8'h57, 8'h57, 8'h58);
        repeat (8) @(posedge clk);
        expect_capture_count(4);
        if (capture_data[2] != 8'h44 || capture_last[2] != 1'b0) $fatal(1, "W drop byte0 mismatch");
        if (capture_data[3] != 8'h0A || capture_last[3] != 1'b1) $fatal(1, "W drop byte1 mismatch");
        if (flat_count(3) != 8'd1) begin
            $fatal(1, "Expected slot 3 counter to increment before rewrite");
        end

        // Rewrite slot 3 from W -> Q, and reset slot counter.
        expect_cfg_success(3'd3, 8'h51);
        repeat (4) @(posedge clk);
        if (flat_key(3) != 8'h51) begin
            $fatal(1, "Expected slot 3 key to change to Q");
        end
        if (flat_count(3) != 8'd0) begin
            $fatal(1, "Expected slot 3 counter reset after rewrite");
        end

        // Old key W must no longer block.
        drive_two_byte_frame(8'h57, 8'h57, 8'h58);
        repeat (8) @(posedge clk);
        expect_capture_count(6);
        if (capture_data[4] != 8'h57 || capture_last[4] != 1'b0) $fatal(1, "Old W key should pass byte0");
        if (capture_data[5] != 8'h58 || capture_last[5] != 1'b1) $fatal(1, "Old W key should pass byte1");

        // New key Q must block immediately and attribute to slot 3.
        drive_two_byte_frame(8'h51, 8'h51, 8'h52);
        repeat (8) @(posedge clk);
        expect_capture_count(8);
        if (capture_data[6] != 8'h44 || capture_last[6] != 1'b0) $fatal(1, "New Q key byte0 mismatch");
        if (capture_data[7] != 8'h0A || capture_last[7] != 1'b1) $fatal(1, "New Q key byte1 mismatch");
        if (!last_block_slot_valid_q || (last_block_slot_q != 3'd3)) begin
            $fatal(1, "Expected block slot attribution for slot 3");
        end
        if (flat_count(3) != 8'd1) begin
            $fatal(1, "Expected slot 3 counter increment after Q block");
        end

        // Duplicate key reject: slot 0 cannot be rewritten to Y because slot 1 already owns Y.
        expect_cfg_error(3'd0, 8'h59);
        repeat (4) @(posedge clk);
        if (flat_key(0) != 8'h58 || flat_key(1) != 8'h59) begin
            $fatal(1, "Duplicate-key reject should not mutate key map");
        end
        if (flat_count(0) != 8'd0 || flat_count(1) != 8'd0) begin
            $fatal(1, "Duplicate-key reject should not mutate counters");
        end

        $display("contest_acl_core test passed.");
        $finish;
    end

endmodule
