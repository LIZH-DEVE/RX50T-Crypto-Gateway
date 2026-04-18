`timescale 1ns/1ps

module tb_contest_crypto_cdc_proto;

    localparam integer ROOT_PERIOD_NS    = 20;
    localparam integer INGRESS_PERIOD_NS = 8;
    localparam integer FRAME_BYTES       = 24;

    reg root_clk;
    reg ingress_clk;
    reg root_rst_n_async;
    reg ingress_locked;
    reg link_flush_req;
    reg cdc_consume_enable;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg [7:0] s_axis_tdata;
    reg s_axis_tlast;
    reg [0:0] s_axis_tuser;
    wire cdc_axis_tvalid;
    wire [7:0] cdc_axis_tdata;
    wire cdc_axis_tlast;
    wire [0:0] cdc_axis_tuser;
    wire cdc_axis_accept;
    wire core_axis_tvalid;
    reg  core_axis_tready;
    wire [7:0] core_axis_tdata;
    wire core_axis_tlast;
    wire root_wake_pulse;
    wire crypto_clk_ce;
    wire crypto_idle_sync;
    wire ingress_ready;
    wire ingress_locked_out;
    wire wr_full;
    wire wr_almost_full;
    wire rd_empty;

    reg [7:0] expected_data [0:FRAME_BYTES-1];
    reg       expected_last [0:FRAME_BYTES-1];
    integer idx;
    integer observed_count;
    integer wake_count;

    contest_crypto_cdc_proto dut (
        .i_root_clk           (root_clk),
        .i_root_rst_n_async   (root_rst_n_async),
        .i_ingress_clk        (ingress_clk),
        .i_ingress_locked     (ingress_locked),
        .i_link_flush_req     (link_flush_req),
        .i_cdc_consume_enable (cdc_consume_enable),
        .s_axis_tvalid        (s_axis_tvalid),
        .s_axis_tready        (s_axis_tready),
        .s_axis_tdata         (s_axis_tdata),
        .s_axis_tlast         (s_axis_tlast),
        .s_axis_tuser         (s_axis_tuser),
        .o_cdc_axis_tvalid    (cdc_axis_tvalid),
        .o_cdc_axis_tdata     (cdc_axis_tdata),
        .o_cdc_axis_tlast     (cdc_axis_tlast),
        .o_cdc_axis_tuser     (cdc_axis_tuser),
        .o_cdc_axis_accept    (cdc_axis_accept),
        .m_axis_tvalid        (core_axis_tvalid),
        .m_axis_tready        (core_axis_tready),
        .m_axis_tdata         (core_axis_tdata),
        .m_axis_tlast         (core_axis_tlast),
        .o_root_wake_pulse    (root_wake_pulse),
        .o_crypto_clk_ce      (crypto_clk_ce),
        .o_crypto_idle_sync   (crypto_idle_sync),
        .o_ingress_ready      (ingress_ready),
        .o_ingress_locked_out (ingress_locked_out),
        .o_wr_full            (wr_full),
        .o_wr_almost_full     (wr_almost_full),
        .o_rd_empty           (rd_empty)
    );

    initial begin
        root_clk = 1'b0;
        forever #(ROOT_PERIOD_NS/2) root_clk = ~root_clk;
    end

    initial begin
        ingress_clk = 1'b0;
        forever #(INGRESS_PERIOD_NS/2) ingress_clk = ~ingress_clk;
    end

    always @(posedge root_clk) begin
        if (root_wake_pulse) begin
            wake_count <= wake_count + 1;
        end
    end

    task automatic push_word(input [7:0] data_value, input last_value, input [0:0] user_value);
        begin
            @(posedge ingress_clk);
            while (!s_axis_tready) begin
                @(posedge ingress_clk);
            end
            s_axis_tvalid <= 1'b1;
            s_axis_tdata  <= data_value;
            s_axis_tlast  <= last_value;
            s_axis_tuser  <= user_value;
            @(posedge ingress_clk);
            while (!(s_axis_tvalid && s_axis_tready)) begin
                @(posedge ingress_clk);
            end
            s_axis_tvalid <= 1'b0;
            s_axis_tdata  <= 8'd0;
            s_axis_tlast  <= 1'b0;
            s_axis_tuser  <= 1'b0;
        end
    endtask

    initial begin
        root_rst_n_async   = 1'b0;
        ingress_locked     = 1'b0;
        link_flush_req     = 1'b0;
        cdc_consume_enable = 1'b0;
        s_axis_tvalid      = 1'b0;
        s_axis_tdata       = 8'd0;
        s_axis_tlast       = 1'b0;
        s_axis_tuser       = 1'b0;
        core_axis_tready   = 1'b1;
        observed_count     = 0;
        wake_count         = 0;

        repeat (5) @(posedge root_clk);
        root_rst_n_async = 1'b1;
        repeat (4) @(posedge ingress_clk);
        if (s_axis_tready !== 1'b0 || ingress_ready !== 1'b0 || ingress_locked_out !== 1'b0) begin
            $fatal(1, "prototype released ingress path before locked asserted");
        end

        ingress_locked = 1'b1;
        repeat (4) @(posedge ingress_clk);
        repeat (3) @(posedge root_clk);
        if (s_axis_tready !== 1'b1 || ingress_ready !== 1'b1 || ingress_locked_out !== 1'b1) begin
            $fatal(1, "prototype failed to release ingress path after locked asserted");
        end

        repeat (48) @(posedge root_clk);
        if (crypto_clk_ce !== 1'b0) begin
            $fatal(1, "prototype crypto clock failed to gate after idle window");
        end

        for (idx = 0; idx < FRAME_BYTES; idx = idx + 1) begin
            expected_data[idx] = 8'h40 + idx[7:0];
            expected_last[idx] = (idx == FRAME_BYTES - 1);
            push_word(expected_data[idx], expected_last[idx], 1'b1);
        end

        repeat (8) @(posedge root_clk);
        if (wake_count == 0) begin
            $fatal(1, "prototype failed to generate root wake pulse on ingress writes");
        end
        if (crypto_clk_ce !== 1'b1) begin
            $fatal(1, "prototype failed to ungate crypto clock after ingress activity");
        end

        cdc_consume_enable = 1'b1;
        while (observed_count < FRAME_BYTES) begin
            @(posedge dut.clk_crypto_gated);
            if (cdc_axis_accept) begin
                if (cdc_axis_tdata !== expected_data[observed_count]) begin
                    $fatal(1, "prototype CDC data mismatch at index %0d", observed_count);
                end
                if (cdc_axis_tlast !== expected_last[observed_count]) begin
                    $fatal(1, "prototype CDC tlast mismatch at index %0d", observed_count);
                end
                if (cdc_axis_tuser !== 1'b1) begin
                    $fatal(1, "prototype CDC tuser mismatch at index %0d", observed_count);
                end
                observed_count = observed_count + 1;
            end
        end

        link_flush_req = 1'b1;
        #3;
        link_flush_req = 1'b0;
        repeat (6) @(posedge ingress_clk);
        repeat (6) @(posedge root_clk);
        if (!rd_empty || cdc_axis_tvalid) begin
            $fatal(1, "prototype failed to flush CDC link cleanly");
        end

        $display("tb_contest_crypto_cdc_proto: PASS");
        $finish;
    end

endmodule
