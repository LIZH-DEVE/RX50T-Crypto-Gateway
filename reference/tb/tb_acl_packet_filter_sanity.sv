`timescale 1ns / 1ps

module tb_acl_packet_filter_sanity;

    logic clk;
    logic rst_n;

    logic [31:0] s_tdata;
    logic        s_tvalid;
    logic        s_tlast;
    logic        s_tready;

    logic [31:0] m_tdata;
    logic        m_tvalid;
    logic        m_tlast;
    logic        m_tready;

    logic        acl_en;
    logic        acl_write_en;
    logic [11:0] acl_write_addr;
    logic [103:0] acl_write_data;
    logic        acl_clear;
    logic        acl_hit;
    logic        acl_drop;
    logic        acl_drop_pulse;
    logic [31:0] acl_hit_count;
    logic [31:0] acl_miss_count;
    logic        clear_monitors_req;

    logic [31:0] out_words [0:6];
    integer      out_count;
    integer      drop_pulse_count;

    logic [31:0] hit_packet [0:6];
    logic [31:0] miss_packet [0:6];
    logic [103:0] hit_tuple;
    logic [15:0] hit_hash;

    function automatic [15:0] tuple_hash(input [103:0] data);
        logic [15:0] h;
        begin
            h = data[15:0] ^ data[31:16] ^ data[47:32] ^ data[63:48] ^
                data[79:64] ^ data[95:80] ^ {8'h00, data[103:96]};
            h = h ^ {h[7:0], h[15:8]} ^ 16'h9E37;
            tuple_hash = h ^ {h[10:0], h[15:11]} ^ (h >> 3);
        end
    endfunction

    acl_packet_filter dut (
        .clk(clk),
        .rst_n(rst_n),
        .acl_en(acl_en),
        .s_tdata(s_tdata),
        .s_tvalid(s_tvalid),
        .s_tlast(s_tlast),
        .s_tready(s_tready),
        .m_tdata(m_tdata),
        .m_tvalid(m_tvalid),
        .m_tlast(m_tlast),
        .m_tready(m_tready),
        .acl_write_en(acl_write_en),
        .acl_write_addr(acl_write_addr),
        .acl_write_data(acl_write_data),
        .acl_clear(acl_clear),
        .acl_hit(acl_hit),
        .acl_drop(acl_drop),
        .acl_drop_pulse(acl_drop_pulse),
        .acl_hit_count(acl_hit_count),
        .acl_miss_count(acl_miss_count)
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_count <= 0;
            drop_pulse_count <= 0;
            for (int idx = 0; idx < 7; idx = idx + 1) begin
                out_words[idx] <= 32'd0;
            end
        end else if (clear_monitors_req) begin
            out_count <= 0;
            drop_pulse_count <= 0;
            for (int idx = 0; idx < 7; idx = idx + 1) begin
                out_words[idx] <= 32'd0;
            end
        end else begin
            if (m_tvalid && m_tready && out_count < 7) begin
                out_words[out_count] <= m_tdata;
                out_count <= out_count + 1;
            end

            if (acl_drop_pulse) begin
                drop_pulse_count <= drop_pulse_count + 1;
            end
        end
    end

    task automatic clear_monitors;
        begin
            clear_monitors_req <= 1'b1;
            @(posedge clk);
            clear_monitors_req <= 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic send_word(input [31:0] data, input bit last);
        begin
            s_tdata  <= data;
            s_tvalid <= 1'b1;
            s_tlast  <= last;
            do @(posedge clk); while (!s_tready);
            s_tvalid <= 1'b0;
            s_tlast  <= 1'b0;
            s_tdata  <= '0;
        end
    endtask

    task automatic send_packet(input logic [31:0] words [0:6]);
        integer idx;
        begin
            for (idx = 0; idx < 7; idx = idx + 1) begin
                send_word(words[idx], idx == 6);
            end
        end
    endtask

    task automatic program_hit_entry;
        begin
            acl_write_addr <= hit_hash[11:0];
            acl_write_data <= hit_tuple;
            acl_write_en <= 1'b1;
            @(posedge clk);
            acl_write_en <= 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        integer idx;

        s_tdata = '0;
        s_tvalid = 1'b0;
        s_tlast = 1'b0;
        m_tready = 1'b1;
        acl_en = 1'b1;
        acl_write_en = 1'b0;
        acl_write_addr = '0;
        acl_write_data = '0;
        acl_clear = 1'b0;
        clear_monitors_req = 1'b0;

        hit_packet[0] = 32'h4500_0000;
        hit_packet[1] = 32'd40;
        hit_packet[2] = 32'h0000_0000;
        hit_packet[3] = {8'd64, 8'd6, 16'h0000};
        hit_packet[4] = 32'hC0A8_0001;
        hit_packet[5] = 32'hC0A8_0002;
        hit_packet[6] = {16'd1234, 16'd80};

        miss_packet[0] = hit_packet[0];
        miss_packet[1] = hit_packet[1];
        miss_packet[2] = hit_packet[2];
        miss_packet[3] = hit_packet[3];
        miss_packet[4] = hit_packet[4];
        miss_packet[5] = hit_packet[5];
        miss_packet[6] = {16'd5678, 16'd80};

        hit_tuple = {8'd6, 32'hC0A8_0001, 16'd1234, 32'hC0A8_0002, 16'd80};
        hit_hash = tuple_hash(hit_tuple);

        wait(rst_n);
        repeat (2) @(posedge clk);

        program_hit_entry();

        clear_monitors();
        send_packet(hit_packet);
        repeat (8) @(posedge clk);

        if (drop_pulse_count != 1 || out_count != 0 || acl_hit_count != 32'd1 || acl_miss_count != 32'd0) begin
            $fatal(1, "ACL hit/drop path failed: drop_pulse_count=%0d out_count=%0d hit_count=%0d miss_count=%0d acl_hit=%0d acl_drop=%0d",
                   drop_pulse_count, out_count, acl_hit_count, acl_miss_count, acl_hit, acl_drop);
        end

        clear_monitors();
        send_packet(miss_packet);
        wait (out_count == 7);
        repeat (2) @(posedge clk);

        if (drop_pulse_count != 0 || acl_hit_count != 32'd1 || acl_miss_count != 32'd1) begin
            $fatal(1, "ACL miss/forward stats failed: drop_pulse_count=%0d hit_count=%0d miss_count=%0d acl_hit=%0d acl_drop=%0d",
                   drop_pulse_count, acl_hit_count, acl_miss_count, acl_hit, acl_drop);
        end

        for (idx = 0; idx < 7; idx = idx + 1) begin
            if (out_words[idx] !== miss_packet[idx]) begin
                $fatal(1, "Forwarded packet mismatch at word %0d: got=%h expected=%h",
                       idx, out_words[idx], miss_packet[idx]);
            end
        end

        clear_monitors();
        clear_monitors();
        send_packet(hit_packet);
        repeat (8) @(posedge clk);
        if (drop_pulse_count != 1 || out_count != 0 || acl_hit_count != 32'd2 || acl_miss_count != 32'd1) begin
            $fatal(1, "Repeated clear + hit path failed: drop_pulse_count=%0d out_count=%0d hit_count=%0d miss_count=%0d",
                   drop_pulse_count, out_count, acl_hit_count, acl_miss_count);
        end

        clear_monitors();
        clear_monitors();
        send_packet(miss_packet);
        wait (out_count == 7);
        repeat (2) @(posedge clk);
        if (drop_pulse_count != 0 || acl_hit_count != 32'd2 || acl_miss_count != 32'd2) begin
            $fatal(1, "Repeated clear + miss path failed: drop_pulse_count=%0d hit_count=%0d miss_count=%0d",
                   drop_pulse_count, acl_hit_count, acl_miss_count);
        end

        $display("PASS: acl_packet_filter sanity");
        $finish;
    end

endmodule
