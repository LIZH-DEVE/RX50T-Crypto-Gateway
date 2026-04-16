`timescale 1ns/1ps

module contest_trace_buffer #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer DEPTH = 256,
    parameter integer PAGE_ENTRIES = 16
) (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_event_valid,
    input  wire [7:0]   i_event_code,
    input  wire [7:0]   i_event_arg0,
    input  wire [15:0]  i_event_arg1,
    output wire [15:0]  o_valid_count,
    output wire [7:0]   o_write_ptr,
    output wire [7:0]   o_flags,
    input  wire         i_page_req,
    input  wire [3:0]   i_page_idx,
    output reg          o_page_busy,
    output reg          o_page_done,
    output reg  [3:0]   o_page_idx,
    output reg  [4:0]   o_page_entry_count,
    output reg  [7:0]   o_page_flags,
    output reg  [1023:0] o_page_entries_flat
);

    localparam integer TRACE_MS_DIV = CLK_HZ / 1000;

    integer i;
    integer page_start;
    integer remaining;

    (* ram_style = "block" *) reg [63:0] trace_mem_q [0:DEPTH-1];

    reg [15:0] tick_div_q;
    reg [31:0] trace_timestamp_ms_q;
    reg [7:0]  trace_wr_ptr_q;
    reg [15:0] trace_valid_count_q;
    reg        trace_wrapped_q;

    reg [7:0]  trace_rd_addr_q;
    reg [63:0] trace_rd_data_q;

    reg [4:0]  page_issue_count_q;
    reg [3:0]  page_capture_count_q;
    reg        page_capture_valid_q;
    reg [7:0]  page_base_addr_q;
    reg [15:0] page_valid_total_q;
    reg        page_wrapped_q;

    function automatic [7:0] flags_byte(input wrapped);
        begin
            flags_byte = {6'd0, 1'b1, wrapped};
        end
    endfunction

    function automatic [7:0] ptr_add(input [7:0] base, input [3:0] offset);
        begin
            ptr_add = base + {4'd0, offset};
        end
    endfunction

    initial begin
        if ((CLK_HZ % 1000) != 0) begin
            $error("contest_trace_buffer requires CLK_HZ divisible by 1000, got %0d", CLK_HZ);
            $finish;
        end
        if (DEPTH != 256) begin
            $error("contest_trace_buffer currently expects DEPTH=256, got %0d", DEPTH);
            $finish;
        end
        if (PAGE_ENTRIES != 16) begin
            $error("contest_trace_buffer currently expects PAGE_ENTRIES=16, got %0d", PAGE_ENTRIES);
            $finish;
        end
    end

    assign o_valid_count = trace_valid_count_q;
    assign o_write_ptr   = trace_wr_ptr_q;
    assign o_flags       = flags_byte(trace_wrapped_q);

    always @(posedge i_clk) begin
        if (i_event_valid) begin
            trace_mem_q[trace_wr_ptr_q] <= {trace_timestamp_ms_q, i_event_code, i_event_arg0, i_event_arg1};
        end

        trace_rd_data_q <= trace_mem_q[trace_rd_addr_q];
    end

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            tick_div_q             <= 16'd0;
            trace_timestamp_ms_q   <= 32'd0;
            trace_wr_ptr_q         <= 8'd0;
            trace_valid_count_q    <= 16'd0;
            trace_wrapped_q        <= 1'b0;
            trace_rd_addr_q        <= 8'd0;
            o_page_busy            <= 1'b0;
            o_page_done            <= 1'b0;
            o_page_idx             <= 4'd0;
            o_page_entry_count     <= 5'd0;
            o_page_flags           <= 8'd0;
            o_page_entries_flat    <= 1024'd0;
            page_issue_count_q     <= 5'd0;
            page_capture_count_q   <= 4'd0;
            page_capture_valid_q   <= 1'b0;
            page_base_addr_q       <= 8'd0;
            page_valid_total_q     <= 16'd0;
            page_wrapped_q         <= 1'b0;
        end else begin
            o_page_done <= 1'b0;

            if (tick_div_q == TRACE_MS_DIV - 1) begin
                tick_div_q <= 16'd0;
                trace_timestamp_ms_q <= trace_timestamp_ms_q + 32'd1;
            end else begin
                tick_div_q <= tick_div_q + 16'd1;
            end

            if (i_event_valid) begin
                trace_wr_ptr_q <= trace_wr_ptr_q + 8'd1;
                if (trace_valid_count_q == DEPTH) begin
                    trace_wrapped_q <= 1'b1;
                end else begin
                    trace_valid_count_q <= trace_valid_count_q + 16'd1;
                    if (trace_valid_count_q == (DEPTH - 1)) begin
                        trace_wrapped_q <= 1'b1;
                    end
                end
            end

            if (!o_page_busy && i_page_req) begin
                o_page_busy          <= 1'b1;
                o_page_idx           <= i_page_idx;
                o_page_entries_flat  <= 1024'd0;
                page_issue_count_q   <= 5'd1;
                page_capture_count_q <= 4'd0;
                page_capture_valid_q <= 1'b0;
                page_base_addr_q     <= {i_page_idx, 4'd0};
                page_valid_total_q   <= trace_valid_count_q;
                page_wrapped_q       <= trace_wrapped_q;
                trace_rd_addr_q      <= {i_page_idx, 4'd0};
                o_page_flags         <= flags_byte(trace_wrapped_q);
                page_start = {i_page_idx, 4'd0};
                if (trace_wrapped_q) begin
                    o_page_entry_count <= 5'd16;
                end else if (trace_valid_count_q <= page_start) begin
                    o_page_entry_count <= 5'd0;
                end else begin
                    remaining = trace_valid_count_q - page_start;
                    if (remaining >= 16) begin
                        o_page_entry_count <= 5'd16;
                    end else begin
                        o_page_entry_count <= remaining[4:0];
                    end
                end
            end else if (o_page_busy) begin
                if (page_capture_valid_q) begin
                    o_page_entries_flat[(page_capture_count_q * 64) +: 64] <= trace_rd_data_q;
                    if (page_capture_count_q == 4'd15) begin
                        o_page_busy          <= 1'b0;
                        o_page_done          <= 1'b1;
                        page_capture_valid_q <= 1'b0;
                    end else begin
                        page_capture_count_q <= page_capture_count_q + 4'd1;
                    end
                end

                if (page_issue_count_q < 5'd16) begin
                    trace_rd_addr_q      <= ptr_add(page_base_addr_q, page_issue_count_q);
                    page_issue_count_q   <= page_issue_count_q + 5'd1;
                    page_capture_valid_q <= 1'b1;
                end
            end
        end
    end

endmodule
