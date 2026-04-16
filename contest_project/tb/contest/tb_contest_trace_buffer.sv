`timescale 1ns/1ps

module tb_contest_trace_buffer;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg event_valid = 1'b0;
    reg [7:0] event_code = 8'd0;
    reg [7:0] event_arg0 = 8'd0;
    reg [15:0] event_arg1 = 16'd0;
    reg page_req = 1'b0;
    reg [3:0] page_idx = 4'd0;

    wire [15:0] valid_count;
    wire [7:0] write_ptr;
    wire [7:0] flags;
    wire page_busy;
    wire page_done;
    wire [3:0] page_idx_out;
    wire [4:0] page_entry_count;
    wire [7:0] page_flags;
    wire [1023:0] page_entries_flat;

    integer i;

    contest_trace_buffer #(
        .CLK_HZ(1000),
        .DEPTH(256),
        .PAGE_ENTRIES(16)
    ) dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_event_valid(event_valid),
        .i_event_code(event_code),
        .i_event_arg0(event_arg0),
        .i_event_arg1(event_arg1),
        .o_valid_count(valid_count),
        .o_write_ptr(write_ptr),
        .o_flags(flags),
        .i_page_req(page_req),
        .i_page_idx(page_idx),
        .o_page_busy(page_busy),
        .o_page_done(page_done),
        .o_page_idx(page_idx_out),
        .o_page_entry_count(page_entry_count),
        .o_page_flags(page_flags),
        .o_page_entries_flat(page_entries_flat)
    );

    always #5 clk = ~clk;

    task tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task push_event(
        input [7:0] code,
        input [7:0] arg0,
        input [15:0] arg1
    );
        begin
            event_code  <= code;
            event_arg0  <= arg0;
            event_arg1  <= arg1;
            event_valid <= 1'b1;
            tick();
            event_valid <= 1'b0;
            event_code  <= 8'd0;
            event_arg0  <= 8'd0;
            event_arg1  <= 16'd0;
        end
    endtask

    task request_page(input [3:0] idx);
        begin
            page_idx <= idx;
            page_req <= 1'b1;
            tick();
            page_req <= 1'b0;
            wait (page_done == 1'b1);
            #1;
        end
    endtask

    function [63:0] page_entry(input integer idx);
        begin
            page_entry = page_entries_flat[(idx * 64) +: 64];
        end
    endfunction

    initial begin
        repeat (3) tick();
        rst_n <= 1'b1;
        tick();

        if (valid_count !== 16'd0 || write_ptr !== 8'd0 || flags !== 8'h02) begin
            $display("FAIL: reset metadata wrong valid=%0d ptr=%0d flags=0x%02x", valid_count, write_ptr, flags);
            $finish(1);
        end

        push_event(8'h08, 8'h00, 16'h0000);
        if (valid_count !== 16'd1 || write_ptr !== 8'd1) begin
            $display("FAIL: single write metadata wrong valid=%0d ptr=%0d", valid_count, write_ptr);
            $finish(1);
        end

        request_page(4'd0);
        if (page_idx_out !== 4'd0 || page_entry_count !== 5'd1 || page_flags !== 8'h02) begin
            $display("FAIL: page0 metadata wrong idx=%0d count=%0d flags=0x%02x", page_idx_out, page_entry_count, page_flags);
            $finish(1);
        end
        if (page_entries_flat[31:24] !== 8'h08) begin
            $display("FAIL: first event code mismatch 0x%02x", page_entries_flat[31:24]);
            $finish(1);
        end

        for (i = 0; i < 16; i = i + 1) begin
            push_event(8'h07, i[7:0], i[15:0]);
        end

        if (valid_count !== 16'd17 || write_ptr !== 8'd17 || flags !== 8'h02) begin
            $display("FAIL: nonwrapped page1 metadata wrong valid=%0d ptr=%0d flags=0x%02x", valid_count, write_ptr, flags);
            $finish(1);
        end

        request_page(4'd1);
        if (page_idx_out !== 4'd1 || page_entry_count !== 5'd1 || page_flags !== 8'h02) begin
            $display("FAIL: page1 metadata wrong idx=%0d count=%0d flags=0x%02x", page_idx_out, page_entry_count, page_flags);
            $finish(1);
        end
        if (page_entries_flat[31:24] !== 8'h07 || page_entries_flat[23:16] !== 8'h0F || page_entries_flat[15:0] !== 16'h000F) begin
            $display("FAIL: page1 first entry mismatch raw=%016x", page_entries_flat[63:0]);
            $finish(1);
        end

        rst_n <= 1'b0;
        tick();
        rst_n <= 1'b1;
        tick();

        if (valid_count !== 16'd0 || write_ptr !== 8'd0 || flags !== 8'h02) begin
            $display("FAIL: reset-after-page1 metadata wrong valid=%0d ptr=%0d flags=0x%02x", valid_count, write_ptr, flags);
            $finish(1);
        end

        push_event(8'h08, 8'h00, 16'h0000);

        for (i = 0; i < 260; i = i + 1) begin
            push_event(8'h07, i[7:0], i[15:0]);
        end

        if (valid_count !== 16'd256) begin
            $display("FAIL: wrap valid_count mismatch %0d", valid_count);
            $finish(1);
        end
        if (write_ptr !== 8'd5) begin
            $display("FAIL: wrap write_ptr mismatch %0d", write_ptr);
            $finish(1);
        end
        if (flags[0] !== 1'b1 || flags[1] !== 1'b1) begin
            $display("FAIL: wrap flags mismatch 0x%02x", flags);
            $finish(1);
        end

        request_page(4'd0);
        if (page_entry_count !== 5'd16) begin
            $display("FAIL: wrapped page count mismatch %0d", page_entry_count);
            $finish(1);
        end
        if (page_entries_flat[31:24] !== 8'h07) begin
            $display("FAIL: wrapped page first code mismatch 0x%02x", page_entries_flat[31:24]);
            $finish(1);
        end

        if (page_entries_flat[63:32] == 32'd0) begin
            $display("FAIL: timestamp_ms did not advance");
            $finish(1);
        end

        $display("PASS: contest_trace_buffer metadata/page/wrap behavior verified");
        $finish(0);
    end
endmodule
