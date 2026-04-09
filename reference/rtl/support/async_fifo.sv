// =============================================================================
// Project: Hetero_SoC_2026
// Design: Asynchronous FIFO (Gray Code & 2-FF Sync)
// Day: 02 - 跨时钟域逻辑实现
// =============================================================================

module async_fifo #(
    parameter ADDR_WIDTH = 4,  // 深度为 2^ADDR_WIDTH
    parameter DATA_WIDTH = 8
)(
    // 写时钟域 (Write Domain)
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  wen,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,
    
    // 读时钟域 (Read Domain)
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  ren,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty
);

    // 定义内部指针 (多出一位用于判断空满)
    logic [ADDR_WIDTH:0] wptr_bin, rptr_bin;
    logic [ADDR_WIDTH:0] wptr_gray, rptr_gray;
    logic [ADDR_WIDTH:0] wptr_gray_sync, rptr_gray_sync;

    // 存储阵列 (Dual-Port RAM)
    logic [DATA_WIDTH-1:0] mem [2**ADDR_WIDTH-1:0];

    // --- 1. 写时钟域逻辑 ---
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr_bin <= 0;
        end else if (wen && !wfull) begin
            mem[wptr_bin[ADDR_WIDTH-1:0]] <= wdata;
            wptr_bin <= wptr_bin + 1'b1;
        end
    end

    // 二进制转格雷码: (bin >> 1) ^ bin
    assign wptr_gray = (wptr_bin >> 1) ^ wptr_bin;

    // --- 2. 读时钟域逻辑 ---
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rptr_bin <= 0;
        end else if (ren && !rempty) begin
            rptr_bin <= rptr_bin + 1'b1;
        end
    end
    assign rdata = mem[rptr_bin[ADDR_WIDTH-1:0]];
    assign rptr_gray = (rptr_bin >> 1) ^ rptr_bin;

    // --- 3. 跨时钟域同步 (2-FF Synchronizer) ---
    // 将读指针同步到写时钟域
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] rptr_gray_s1, rptr_gray_s2;
    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) {rptr_gray_s2, rptr_gray_s1} <= '0;
        else         {rptr_gray_s2, rptr_gray_s1} <= {rptr_gray_s1, rptr_gray};
    end
    assign rptr_gray_sync = rptr_gray_s2;

    // 将写指针同步到读时钟域
    (* ASYNC_REG = "TRUE" *) logic [ADDR_WIDTH:0] wptr_gray_s1, wptr_gray_s2;
    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) {wptr_gray_s2, wptr_gray_s1} <= '0;
        else         {wptr_gray_s2, wptr_gray_s1} <= {wptr_gray_s1, wptr_gray};
    end
    assign wptr_gray_sync = wptr_gray_s2;

    // --- 4. 空满标志判断 (核心审计点) ---
    // 空标志：格雷码完全相等
    assign rempty = (rptr_gray == wptr_gray_sync);

    // 满标志：格雷码最高位与次高位不同，其余位相等
    assign wfull  = (wptr_gray == {~rptr_gray_sync[ADDR_WIDTH:ADDR_WIDTH-1], rptr_gray_sync[ADDR_WIDTH-2:0]});

endmodule