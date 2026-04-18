`timescale 1ns/1ps

module tb_contest_reset_sync;

    reg clk_a;
    reg clk_b;
    reg rst_n_async;
    wire rst_a_n;
    wire rst_b_n;
    integer a_edges_after_release;
    integer b_edges_after_release;

    contest_reset_sync u_rst_a (
        .i_clk        (clk_a),
        .i_rst_n_async(rst_n_async),
        .o_rst_n_sync (rst_a_n)
    );

    contest_reset_sync u_rst_b (
        .i_clk        (clk_b),
        .i_rst_n_async(rst_n_async),
        .o_rst_n_sync (rst_b_n)
    );

    initial begin
        clk_a = 1'b0;
        forever #4 clk_a = ~clk_a;
    end

    initial begin
        clk_b = 1'b0;
        forever #10 clk_b = ~clk_b;
    end

    always @(posedge clk_a) begin
        if (!rst_n_async) begin
            a_edges_after_release <= 0;
        end else if (!rst_a_n) begin
            a_edges_after_release <= a_edges_after_release + 1;
        end
    end

    always @(posedge clk_b) begin
        if (!rst_n_async) begin
            b_edges_after_release <= 0;
        end else if (!rst_b_n) begin
            b_edges_after_release <= b_edges_after_release + 1;
        end
    end

    initial begin
        rst_n_async = 1'b0;
        a_edges_after_release = 0;
        b_edges_after_release = 0;

        #13;
        rst_n_async = 1'b1;

        #1;
        if (rst_a_n !== 1'b0 || rst_b_n !== 1'b0) begin
            $fatal(1, "reset outputs must remain asserted immediately after async release");
        end

        @(posedge clk_a);
        @(posedge clk_a);
        #1;
        if (rst_a_n !== 1'b1) begin
            $fatal(1, "rst_a_n did not release synchronously after two clk_a edges");
        end

        if (rst_b_n !== 1'b0) begin
            $fatal(1, "rst_b_n released too early");
        end

        @(posedge clk_b);
        @(posedge clk_b);
        #1;
        if (rst_b_n !== 1'b1) begin
            $fatal(1, "rst_b_n did not release synchronously after two clk_b edges");
        end

        #3;
        rst_n_async = 1'b0;
        #1;
        if (rst_a_n !== 1'b0 || rst_b_n !== 1'b0) begin
            $fatal(1, "reset outputs must assert asynchronously");
        end

        #17;
        rst_n_async = 1'b1;
        repeat (3) @(posedge clk_a);
        repeat (3) @(posedge clk_b);

        if (rst_a_n !== 1'b1 || rst_b_n !== 1'b1) begin
            $fatal(1, "reset outputs failed to recover after second release");
        end

        $display("tb_contest_reset_sync: PASS");
        $finish;
    end

endmodule
