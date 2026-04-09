`timescale 1ns / 1ps

/**
 * 模块: seven_seg_driver
 * 描述: 4位七段数码管动态扫描驱动
 * 逻辑: 
 * 1. 使用计数器产生扫描时钟 (Refresh Clock)。
 * 2. 轮流拉低 AN (位选)，同时输出对应的 SEG (段选)。
 */
module seven_seg_driver (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] i_data,      // 要显示的 16位 数据 (例如 16'h0064)
    input  logic [3:0]  i_dots,      // 小数点控制 (1=亮)
    
    output logic [3:0]  o_an,        // 位选 (0有效，控制哪一位亮)
    output logic [7:0]  o_seg        // 段选 (0有效，控制显示什么字) {dp, g, f, e, d, c, b, a}
);

    // ==========================================================
    // 1. 扫描分频计数器
    // ==========================================================
    // 假设主频 100MHz。为了人眼看着不闪，扫描频率需 > 60Hz。
    // 我们让每位显示约 1ms ~ 2ms。2^17 / 100MHz ≈ 1.3ms
    // 仿真时为了波形好看，我们可以把这个常数改小，或者只看低位
    localparam CNT_WIDTH = 18; 
    logic [CNT_WIDTH-1:0] refresh_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) refresh_cnt <= 0;
        else        refresh_cnt <= refresh_cnt + 1;
    end

    // 使用计数器的高 2 位作为“当前扫描位”的选择信号
    // 00->Digit0, 01->Digit1, 10->Digit2, 11->Digit3
    logic [1:0] scan_sel;
    assign scan_sel = refresh_cnt[CNT_WIDTH-1 : CNT_WIDTH-2];

    // ==========================================================
    // 2. 多路复用 (MUX): 选出当前要显示的 4bit 数字
    // ==========================================================
    logic [3:0] current_hex;
    logic       current_dot;

    always_comb begin
        case (scan_sel)
            2'b00: begin // 最右边 (Digit 0)
                current_hex = i_data[3:0];
                current_dot = i_dots[0];
                o_an        = 4'b1110; // 拉低 bit 0
            end
            2'b01: begin // Digit 1
                current_hex = i_data[7:4];
                current_dot = i_dots[1];
                o_an        = 4'b1101;
            end
            2'b10: begin // Digit 2
                current_hex = i_data[11:8];
                current_dot = i_dots[2];
                o_an        = 4'b1011;
            end
            2'b11: begin // 最左边 (Digit 3)
                current_hex = i_data[15:12];
                current_dot = i_dots[3];
                o_an        = 4'b0111;
            end
            default: begin
                current_hex = 4'h0;
                current_dot = 0;
                o_an        = 4'b1111; // 全灭
            end
        endcase
    end

    // ==========================================================
    // 3. 译码器 (Decoder): Hex -> 7-Seg 码
    // ==========================================================
    // 共阳极数码管：0亮，1灭
    // 顺序: {dp, g, f, e, d, c, b, a}
    logic [6:0] seg_code;

    always_comb begin
        case (current_hex)
            4'h0: seg_code = 7'b1000000; // 0
            4'h1: seg_code = 7'b1111001; // 1
            4'h2: seg_code = 7'b0100100; // 2
            4'h3: seg_code = 7'b0110000; // 3
            4'h4: seg_code = 7'b0011001; // 4
            4'h5: seg_code = 7'b0010010; // 5
            4'h6: seg_code = 7'b0000010; // 6
            4'h7: seg_code = 7'b1111000; // 7
            4'h8: seg_code = 7'b0000000; // 8
            4'h9: seg_code = 7'b0010000; // 9
            4'hA: seg_code = 7'b0001000; // A
            4'hB: seg_code = 7'b0000011; // b
            4'hC: seg_code = 7'b1000110; // C
            4'hD: seg_code = 7'b0100001; // d
            4'hE: seg_code = 7'b0000110; // E
            4'hF: seg_code = 7'b0001110; // F
            default: seg_code = 7'b1111111; // Off
        endcase
    end

    // 组合最终输出 (加上小数点)
    assign o_seg = {~current_dot, seg_code}; // dot 也是 0 亮

endmodule