`timescale 1ns / 1ps
/**
 * 模块名称: gearbox_128_to_32 (Big Endian Fixed)
 * 描述: [Task 4.2] 修正版输出侧位宽转换器
 * 核心修复: 强制先发高位 [127:96]，确保网络字节序正确。
 */
module gearbox_128_to_32 (
    input  logic           clk,
    input  logic           rst_n,

    // 上游接口 (来自 Crypto/FIFO 128-bit)
    input  logic [127:0]   din,
    input  logic           din_valid,
    output logic           din_ready,

    // 下游接口 (去往 DMA/FIFO 32-bit)
    output logic [31:0]    dout,
    output logic           dout_valid,
    output logic           dout_last, // TLAST 信号
    input  logic           dout_ready
);

    logic [1:0]   cnt;
    logic [127:0] data_reg;
    logic         active;

    // ==========================================================
    // FSM Logic
    // ==========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
            active <= 0;
            data_reg <= 0;
        end else begin
            if (!active) begin
                // IDLE: 接收新数据
                if (din_valid && dout_ready) begin
                    active   <= 1;
                    data_reg <= din; // 锁存数据
                    cnt      <= 1;   // 下一拍处理第 2 个字
                end
            end else begin
                // BUSY: 发送剩余数据
                if (dout_ready) begin
                    if (cnt == 3) begin
                        active <= 0; // 发完，回 IDLE
                        cnt    <= 0;
                    end else begin
                        cnt    <= cnt + 1;
                    end
                end
            end
        end
    end

    // ==========================================================
    // Output Logic (Big Endian: MSB First)
    // ==========================================================
    always_comb begin
        dout_last = 0; // 默认不拉高

        if (!active) begin
            // --------------------------------------------------
            // Beat 1 (IDLE): 核心修正点 -> 直接输出最高位 [127:96]
            // --------------------------------------------------
            dout       = din[127:96]; 
            dout_valid = din_valid;
            din_ready  = dout_ready; // 直通握手
        end else begin
            // --------------------------------------------------
            // Beat 2, 3, 4 (BUSY): 从高到低依次移出
            // --------------------------------------------------
            case (cnt)
                2'd1: dout = data_reg[95:64];
                2'd2: dout = data_reg[63:32];
                2'd3: begin
                    dout = data_reg[31:0]; // 最后发最低位
                    dout_last = 1'b1;      // 第 4 拍拉高 Last
                end
                default: dout = 32'd0;
            endcase
            
            dout_valid = 1'b1; // 寄存器数据始终有效
            din_ready  = 1'b0; // 忙碌时反压上游
        end
    end

endmodule