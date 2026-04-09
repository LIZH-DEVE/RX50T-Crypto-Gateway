`timescale 1ns/1ps

module tb_contest_parser_core;

    reg clk;
    reg rst_n;
    reg in_valid;
    reg [7:0] in_byte;
    wire in_frame;
    wire frame_start;
    wire payload_valid;
    wire [7:0] payload_byte;
    wire frame_done;
    wire error_pulse;
    wire [7:0] payload_len;
    wire [7:0] payload_count;

    reg [7:0] capture_mem [0:7];
    integer capture_idx;
    integer start_count;
    integer done_count;
    integer error_count;

    contest_parser_core #(
        .SOF_BYTE         (8'h55),
        .MAX_PAYLOAD_BYTES(8)
    ) dut (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .i_valid        (in_valid),
        .i_byte         (in_byte),
        .o_in_frame     (in_frame),
        .o_frame_start  (frame_start),
        .o_payload_valid(payload_valid),
        .o_payload_byte (payload_byte),
        .o_frame_done   (frame_done),
        .o_error        (error_pulse),
        .o_payload_len  (payload_len),
        .o_payload_count(payload_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            capture_idx  <= 0;
            start_count  <= 0;
            done_count   <= 0;
            error_count  <= 0;
        end else begin
            if (frame_start) begin
                start_count <= start_count + 1;
            end
            if (payload_valid) begin
                capture_mem[capture_idx] <= payload_byte;
                capture_idx <= capture_idx + 1;
            end
            if (frame_done) begin
                done_count <= done_count + 1;
            end
            if (error_pulse) begin
                error_count <= error_count + 1;
            end
        end
    end

    task automatic drive_byte(input [7:0] value);
        begin
            @(posedge clk);
            in_valid <= 1'b1;
            in_byte  <= value;
            @(posedge clk);
            in_valid <= 1'b0;
            in_byte  <= 8'd0;
        end
    endtask

    task automatic send_valid_frame;
        begin
            drive_byte(8'h55);
            drive_byte(8'd3);
            drive_byte(8'h41);
            drive_byte(8'h42);
            drive_byte(8'h43);
        end
    endtask

    task automatic send_zero_length_frame;
        begin
            drive_byte(8'h55);
            drive_byte(8'd0);
        end
    endtask

    task automatic send_oversize_frame;
        begin
            drive_byte(8'h55);
            drive_byte(8'd9);
        end
    endtask

    initial begin
        rst_n    = 1'b0;
        in_valid = 1'b0;
        in_byte  = 8'd0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        send_valid_frame();
        repeat (4) @(posedge clk);

        if (start_count != 1) begin
            $fatal(1, "Expected one frame_start pulse, got %0d", start_count);
        end
        if (done_count != 1) begin
            $fatal(1, "Expected one frame_done pulse, got %0d", done_count);
        end
        if (error_count != 0) begin
            $fatal(1, "Unexpected error pulses after valid frame: %0d", error_count);
        end
        if (capture_idx != 3) begin
            $fatal(1, "Expected 3 payload bytes, got %0d", capture_idx);
        end
        if ((capture_mem[0] != 8'h41) || (capture_mem[1] != 8'h42) || (capture_mem[2] != 8'h43)) begin
            $fatal(1, "Payload capture mismatch: %02x %02x %02x", capture_mem[0], capture_mem[1], capture_mem[2]);
        end

        send_zero_length_frame();
        repeat (2) @(posedge clk);

        if (error_count != 1) begin
            $fatal(1, "Expected one error after zero-length frame, got %0d", error_count);
        end

        send_oversize_frame();
        repeat (2) @(posedge clk);

        if (error_count != 2) begin
            $fatal(1, "Expected second error after oversize frame, got %0d", error_count);
        end

        send_valid_frame();
        repeat (4) @(posedge clk);

        if (start_count != 4) begin
            $fatal(1, "Expected four frame_start pulses total, got %0d", start_count);
        end
        if (done_count != 2) begin
            $fatal(1, "Expected two completed valid frames, got %0d", done_count);
        end
        if (capture_idx != 6) begin
            $fatal(1, "Expected 6 total payload bytes after second valid frame, got %0d", capture_idx);
        end
        if ((capture_mem[3] != 8'h41) || (capture_mem[4] != 8'h42) || (capture_mem[5] != 8'h43)) begin
            $fatal(1, "Second payload capture mismatch: %02x %02x %02x", capture_mem[3], capture_mem[4], capture_mem[5]);
        end

        $display("contest_parser_core test passed.");
        $finish;
    end

endmodule
