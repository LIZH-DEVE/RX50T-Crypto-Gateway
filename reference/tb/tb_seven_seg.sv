`timescale 1ns / 1ps

module tb_seven_seg();

    logic clk, rst_n;
    logic [15:0] data;
    logic [3:0] an;
    logic [7:0] seg;

    // 实例化驱动
    seven_seg_driver dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_data(data),
        .i_dots(4'b0000),
        .o_an(an),
        .o_seg(seg)
    );

    // 时钟
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    initial begin
        rst_n = 0;
        data = 16'h1234; // 我们想显示 "1234"
        #100 rst_n = 1;

        // 这里的仿真时间要足够长，才能看到计数器溢出后的切换
        // 我们的计数器是 18位，2^18 * 10ns ≈ 2.6ms
        // 跑 10ms 应该能看到所有位轮一遍
        #10000000; 
        
        // 换个数据试试
        data = 16'hABCD;
        #10000000;
        
        $stop;
    end

endmodule