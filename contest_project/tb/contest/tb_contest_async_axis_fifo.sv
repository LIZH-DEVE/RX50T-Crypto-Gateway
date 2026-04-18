`timescale 1ns/1ps

module tb_contest_async_axis_fifo;

    localparam integer DATA_W             = 8;
    localparam integer USER_W             = 1;
    localparam integer DEPTH              = 128;
    localparam integer ALMOST_FULL_MARGIN = 8;
    localparam integer WR_PERIOD_NS       = 8;
    localparam integer RD_PERIOD_NS       = 20;
    localparam integer FRAME_BYTES        = DEPTH - ALMOST_FULL_MARGIN;
    localparam integer SIM_TIMEOUT_NS     = 1_000_000;

    reg                  wr_clk;
    reg                  rd_clk;
    reg                  rst_n_async;
    reg                  s_axis_tvalid;
    wire                 s_axis_tready;
    reg  [DATA_W-1:0]    s_axis_tdata;
    reg                  s_axis_tlast;
    reg  [USER_W-1:0]    s_axis_tuser;
    wire                 m_axis_tvalid;
    reg                  m_axis_tready;
    wire [DATA_W-1:0]    m_axis_tdata;
    wire                 m_axis_tlast;
    wire [USER_W-1:0]    m_axis_tuser;
    wire                 wr_full;
    wire                 wr_almost_full;
    wire                 rd_empty;
    wire [$clog2(DEPTH):0] wr_level;
    wire [$clog2(DEPTH):0] rd_level;

    reg [DATA_W-1:0] expected_data [0:FRAME_BYTES-1];
    reg              expected_last [0:FRAME_BYTES-1];
    reg [USER_W-1:0] expected_user [0:FRAME_BYTES-1];
    integer write_idx;
    integer read_idx;

    contest_async_axis_fifo #(
        .DATA_W            (DATA_W),
        .USER_W            (USER_W),
        .DEPTH             (DEPTH),
        .ALMOST_FULL_MARGIN(ALMOST_FULL_MARGIN)
    ) dut (
        .i_wr_clk        (wr_clk),
        .i_rd_clk        (rd_clk),
        .i_rst_n_async   (rst_n_async),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tready   (s_axis_tready),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tlast    (s_axis_tlast),
        .s_axis_tuser    (s_axis_tuser),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tlast    (m_axis_tlast),
        .m_axis_tuser    (m_axis_tuser),
        .o_wr_full       (wr_full),
        .o_wr_almost_full(wr_almost_full),
        .o_rd_empty      (rd_empty),
        .o_wr_level      (wr_level),
        .o_rd_level      (rd_level)
    );

    initial begin
        #SIM_TIMEOUT_NS;
        $fatal(1, "tb_contest_async_axis_fifo timeout after %0d ns", SIM_TIMEOUT_NS);
    end

    initial begin
        wr_clk = 1'b0;
        forever #(WR_PERIOD_NS/2) wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 1'b0;
        forever #(RD_PERIOD_NS/2) rd_clk = ~rd_clk;
    end

    task automatic drive_word(input [DATA_W-1:0] data_value, input last_value, input [USER_W-1:0] user_value);
        begin
            @(posedge wr_clk);
            while (!s_axis_tready) begin
                @(posedge wr_clk);
            end
            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= data_value;
            s_axis_tlast  <= last_value;
            s_axis_tuser  <= user_value;
            @(posedge wr_clk);
            while (!(s_axis_tvalid && s_axis_tready)) begin
                @(posedge wr_clk);
            end
            s_axis_tvalid <= 1'b0;
            s_axis_tdata  <= {DATA_W{1'b0}};
            s_axis_tlast  <= 1'b0;
            s_axis_tuser  <= {USER_W{1'b0}};
        end
    endtask

    initial begin
        rst_n_async   = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = {DATA_W{1'b0}};
        s_axis_tlast  = 1'b0;
        s_axis_tuser  = {USER_W{1'b0}};
        m_axis_tready = 1'b0;
        write_idx     = 0;
        read_idx      = 0;

        repeat (5) @(posedge wr_clk);
        #3;
        rst_n_async = 1'b1;

        repeat (3) @(posedge wr_clk);
        repeat (2) @(posedge rd_clk);

        for (write_idx = 0; write_idx < FRAME_BYTES; write_idx = write_idx + 1) begin
            expected_data[write_idx] = 8'h30 + write_idx[7:0];
            expected_last[write_idx] = (write_idx == FRAME_BYTES - 1);
            expected_user[write_idx] = 1'b1;
            drive_word(expected_data[write_idx], expected_last[write_idx], expected_user[write_idx]);
        end

        repeat (3) @(posedge wr_clk);
        if (!wr_almost_full) begin
            $fatal(1, "FIFO failed to assert almost_full at configured threshold");
        end
        if (wr_level < FRAME_BYTES) begin
            $fatal(1, "FIFO write level did not reflect sustained write pressure");
        end

        m_axis_tready <= 1'b1;
        while (read_idx < FRAME_BYTES) begin
            @(posedge rd_clk);
            if (m_axis_tvalid && m_axis_tready) begin
                if (m_axis_tdata !== expected_data[read_idx]) begin
                    $fatal(1, "FIFO data mismatch at index %0d expected=0x%02x got=0x%02x", read_idx, expected_data[read_idx], m_axis_tdata);
                end
                if (m_axis_tlast !== expected_last[read_idx]) begin
                    $fatal(1, "FIFO tlast mismatch at index %0d", read_idx);
                end
                if (m_axis_tuser !== expected_user[read_idx]) begin
                    $fatal(1, "FIFO tuser mismatch at index %0d", read_idx);
                end
                read_idx = read_idx + 1;
            end
        end

        repeat (3) @(posedge rd_clk);
        if (!rd_empty || m_axis_tvalid) begin
            $fatal(1, "FIFO failed to drain cleanly after readback");
        end

        m_axis_tready <= 1'b0;
        drive_word(8'hA5, 1'b1, 1'b0);
        #1;
        rst_n_async <= 1'b0;
        #3;
        if (wr_level !== 0 || rd_level !== 0 || m_axis_tvalid !== 1'b0) begin
            $fatal(1, "FIFO failed to clear on async flush/reset");
        end
        rst_n_async <= 1'b1;
        repeat (4) @(posedge wr_clk);
        repeat (3) @(posedge rd_clk);

        m_axis_tready <= 1'b1;
        drive_word(8'h5A, 1'b1, 1'b1);
        wait (m_axis_tvalid);
        @(posedge rd_clk);
        if (m_axis_tdata !== 8'h5A || m_axis_tlast !== 1'b1 || m_axis_tuser !== 1'b1) begin
            $fatal(1, "FIFO failed to recover after reset/flush");
        end

        $display("tb_contest_async_axis_fifo: PASS");
        $finish;
    end

endmodule
