`timescale 1ns/1ps

module tb_contest_crypto_cdc_ingress_bridge;

    localparam integer WR_PERIOD_NS = 8;
    localparam integer RD_PERIOD_NS = 20;
    localparam integer ROOT_PERIOD_NS = 20;
    localparam integer FRAME_BYTES = 24;
    localparam integer NASTY_BYTES = 32;
    localparam integer TAIL_STALL_CYCLES = 6;

    reg wr_clk;
    reg root_clk;
    reg crypto_clk_en;
    wire crypto_clk;
    reg rst_n_async;
    reg link_flush_req;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg [7:0] s_axis_tdata;
    reg s_axis_tlast;
    reg [0:0] s_axis_tuser;
    wire m_axis_tvalid;
    reg  m_axis_tready;
    wire [7:0] m_axis_tdata;
    wire m_axis_tlast;
    wire [0:0] m_axis_tuser;
    wire root_wake_pulse;
    wire wr_full;
    wire wr_almost_full;
    wire rd_empty;

    reg [7:0] expected_data [0:FRAME_BYTES-1];
    reg       expected_last [0:FRAME_BYTES-1];
    integer   idx;
    integer   out_idx;
    integer   wake_pulse_count;
    integer   nasty_out_idx;
    integer   nasty_last_count;
    integer   stall_cycles_left;
    reg       nasty_mode;
    reg       tail_stall_started;
    reg       prev_stall_valid_q;
    reg [7:0] prev_stall_data_q;
    reg       prev_stall_last_q;

    assign crypto_clk = crypto_clk_en ? root_clk : 1'b0;

    contest_crypto_cdc_ingress_bridge #(
        .DATA_W            (8),
        .USER_W            (1),
        .DEPTH             (128),
        .ALMOST_FULL_MARGIN(8)
    ) dut (
        .i_ingress_clk      (wr_clk),
        .i_ingress_rst_n_async(rst_n_async),
        .i_root_clk         (root_clk),
        .i_root_rst_n_async (rst_n_async),
        .i_crypto_clk       (crypto_clk),
        .i_crypto_rst_n_async(rst_n_async),
        .i_link_flush_req   (link_flush_req),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tlast       (s_axis_tlast),
        .s_axis_tuser       (s_axis_tuser),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tready      (m_axis_tready),
        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tlast       (m_axis_tlast),
        .m_axis_tuser       (m_axis_tuser),
        .o_root_wake_pulse  (root_wake_pulse),
        .o_wr_full          (wr_full),
        .o_wr_almost_full   (wr_almost_full),
        .o_rd_empty         (rd_empty)
    );

    initial begin
        #200000;
        $fatal(1, "tb_contest_crypto_cdc_ingress_bridge timeout");
    end

    initial begin
        wr_clk = 1'b0;
        forever #(WR_PERIOD_NS/2) wr_clk = ~wr_clk;
    end

    initial begin
        root_clk = 1'b0;
        forever #(ROOT_PERIOD_NS/2) root_clk = ~root_clk;
    end

    always @(posedge root_clk) begin
        if (root_wake_pulse) begin
            wake_pulse_count <= wake_pulse_count + 1;
        end
    end

    always @(negedge root_clk) begin
        if (!rst_n_async || !crypto_clk_en || !nasty_mode) begin
            m_axis_tready <= 1'b1;
            stall_cycles_left = 0;
            tail_stall_started <= 1'b0;
        end else if ((stall_cycles_left == 0) && !tail_stall_started && m_axis_tvalid && (nasty_out_idx >= NASTY_BYTES - 2)) begin
            m_axis_tready <= 1'b0;
            stall_cycles_left = TAIL_STALL_CYCLES - 1;
            tail_stall_started <= 1'b1;
        end else if (stall_cycles_left > 0) begin
            m_axis_tready <= 1'b0;
            stall_cycles_left = stall_cycles_left - 1;
        end else begin
            m_axis_tready <= 1'b1;
        end
    end

    always @(posedge crypto_clk) begin
        if (prev_stall_valid_q && m_axis_tvalid) begin
            if (m_axis_tdata !== prev_stall_data_q) begin
                $fatal(1, "bridge nasty stall changed data during backpressure hold");
            end
            if (m_axis_tlast !== prev_stall_last_q) begin
                $fatal(1, "bridge nasty stall changed TLAST during backpressure hold");
            end
        end

        prev_stall_valid_q <= nasty_mode && m_axis_tvalid && !m_axis_tready;
        if (nasty_mode && m_axis_tvalid && !m_axis_tready) begin
            prev_stall_data_q <= m_axis_tdata;
            prev_stall_last_q <= m_axis_tlast;
        end
    end

    task automatic drive_word(input [7:0] data_value, input last_value, input [0:0] user_value);
        begin
            @(negedge wr_clk);
            s_axis_tvalid = 1'b1;
            s_axis_tdata  = data_value;
            s_axis_tlast  = last_value;
            s_axis_tuser  = user_value;
            do begin
                @(posedge wr_clk);
            end while (dut.slice_push_w !== 1'b1);
            @(negedge wr_clk);
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = 8'd0;
            s_axis_tlast  = 1'b0;
            s_axis_tuser  = 1'b0;
        end
    endtask

    initial begin
        rst_n_async = 1'b0;
        link_flush_req = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata = 8'd0;
        s_axis_tlast = 1'b0;
        s_axis_tuser = 1'b0;
        crypto_clk_en = 1'b0;
        m_axis_tready = 1'b1;
        out_idx = 0;
        wake_pulse_count = 0;
        nasty_out_idx = 0;
        nasty_last_count = 0;
        stall_cycles_left = 0;
        nasty_mode = 1'b0;
        tail_stall_started = 1'b0;
        prev_stall_valid_q = 1'b0;
        prev_stall_data_q = 8'd0;
        prev_stall_last_q = 1'b0;

        repeat (5) @(posedge wr_clk);
        rst_n_async = 1'b1;
        repeat (5) @(posedge wr_clk);
        repeat (5) @(posedge root_clk);

        for (idx = 0; idx < FRAME_BYTES; idx = idx + 1) begin
            expected_data[idx] = 8'h80 + idx;
            expected_last[idx] = (idx == FRAME_BYTES - 1);
            drive_word(expected_data[idx], expected_last[idx], 1'b1);
        end

        for (idx = 0; idx < 16 && wake_pulse_count == 0; idx = idx + 1) begin
            @(posedge root_clk);
        end
        if (wake_pulse_count == 0) begin
            $fatal(1, "bridge failed to generate a root wake pulse while crypto clock was gated");
        end
        if (m_axis_tvalid) begin
            $fatal(1, "bridge exposed read-side data while crypto clock was gated off");
        end

        crypto_clk_en = 1'b1;
        while (out_idx < FRAME_BYTES) begin
            @(posedge crypto_clk);
            if (m_axis_tvalid && m_axis_tready) begin
                if (m_axis_tdata !== expected_data[out_idx]) begin
                    $fatal(1, "bridge data mismatch at index %0d expected=0x%02x got=0x%02x", out_idx, expected_data[out_idx], m_axis_tdata);
                end
                if (m_axis_tlast !== expected_last[out_idx]) begin
                    $fatal(1, "bridge tlast mismatch at index %0d", out_idx);
                end
                if (m_axis_tuser !== 1'b1) begin
                    $fatal(1, "bridge tuser mismatch at index %0d", out_idx);
                end
                out_idx = out_idx + 1;
            end
        end

        nasty_mode = 1'b1;
        nasty_out_idx = 0;
        nasty_last_count = 0;
        tail_stall_started = 1'b0;
        stall_cycles_left = 0;
        prev_stall_valid_q = 1'b0;
        m_axis_tready = 1'b1;
        fork
            begin
                for (idx = 0; idx < NASTY_BYTES; idx = idx + 1) begin
                    drive_word(8'h40 + idx[7:0], (idx == NASTY_BYTES - 1), 1'b1);
                end
            end
            begin
                while (nasty_out_idx < NASTY_BYTES) begin
                    @(posedge crypto_clk);
                    if (m_axis_tvalid && m_axis_tready) begin
                        if (m_axis_tdata !== (8'h40 + nasty_out_idx[7:0])) begin
                            $fatal(1, "bridge nasty stall data mismatch at index %0d expected=0x%02x got=0x%02x", nasty_out_idx, (8'h40 + nasty_out_idx[7:0]), m_axis_tdata);
                        end
                        if (m_axis_tuser !== 1'b1) begin
                            $fatal(1, "bridge nasty stall tuser mismatch at index %0d", nasty_out_idx);
                        end
                        if (m_axis_tlast) begin
                            nasty_last_count = nasty_last_count + 1;
                            if (nasty_out_idx != NASTY_BYTES - 1) begin
                                $fatal(1, "bridge nasty stall observed TLAST on beat %0d, expected %0d", nasty_out_idx + 1, NASTY_BYTES);
                            end
                        end else if (nasty_out_idx == NASTY_BYTES - 1) begin
                            $fatal(1, "bridge nasty stall missing TLAST on final beat");
                        end
                        nasty_out_idx = nasty_out_idx + 1;
                    end
                end
            end
        join
        if (nasty_last_count != 1) begin
            $fatal(1, "bridge nasty stall expected one TLAST, got %0d", nasty_last_count);
        end
        nasty_mode = 1'b0;
        m_axis_tready = 1'b1;

        crypto_clk_en = 1'b0;
        out_idx = 0;
        drive_word(8'h11, 1'b0, 1'b0);
        drive_word(8'h22, 1'b1, 1'b0);
        #3;
        link_flush_req = 1'b1;
        #17;
        link_flush_req = 1'b0;
        repeat (4) @(posedge wr_clk);
        repeat (4) @(posedge root_clk);
        if (!rd_empty || m_axis_tvalid) begin
            $fatal(1, "bridge failed to flush the AFIFO cleanly");
        end

        crypto_clk_en = 1'b1;
        drive_word(8'h33, 1'b0, 1'b0);
        drive_word(8'h44, 1'b1, 1'b0);
        while (out_idx < 2) begin
            @(posedge crypto_clk);
            if (m_axis_tvalid && m_axis_tready) begin
                case (out_idx)
                    0: if (m_axis_tdata !== 8'h33 || m_axis_tlast !== 1'b0) $fatal(1, "bridge failed to recover after flush on first byte");
                    1: if (m_axis_tdata !== 8'h44 || m_axis_tlast !== 1'b1) $fatal(1, "bridge failed to recover after flush on second byte");
                endcase
                out_idx = out_idx + 1;
            end
        end

        $display("tb_contest_crypto_cdc_ingress_bridge: PASS");
        $finish;
    end

endmodule