`timescale 1ns/1ps

module contest_ingress_clk_gen #(
    parameter real ROOT_CLKIN_PERIOD_NS = 20.0,
    parameter bit  BYPASS_MMCM          = 1'b0
) (
    input  wire i_root_clk,
    input  wire i_rst_n_async,
    output wire o_ingress_clk,
    output wire o_locked
);

    generate
        if (BYPASS_MMCM) begin : g_bypass
            assign o_ingress_clk = i_root_clk;
            assign o_locked      = i_rst_n_async;
        end else begin : g_mmcm
    wire clkfb_unbuf_w;
    wire clkfb_buf_w;
    wire ingress_mmcm_clk_w;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(ROOT_CLKIN_PERIOD_NS),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(20.0),
        .CLKOUT0_DIVIDE_F(8.0),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT1_DIVIDE(1),
        .CLKOUT2_DIVIDE(1),
        .CLKOUT3_DIVIDE(1),
        .CLKOUT4_DIVIDE(1),
        .CLKOUT5_DIVIDE(1),
        .CLKOUT6_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1   (i_root_clk),
        .CLKFBIN  (clkfb_buf_w),
        .RST      (!i_rst_n_async),
        .PWRDWN   (1'b0),
        .CLKFBOUT (clkfb_unbuf_w),
        .CLKOUT0  (ingress_mmcm_clk_w),
        .CLKOUT0B (),
        .CLKOUT1  (),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .LOCKED   (o_locked)
    );

    BUFG u_bufg_fb (
        .I(clkfb_unbuf_w),
        .O(clkfb_buf_w)
    );

    BUFG u_bufg_out (
        .I(ingress_mmcm_clk_w),
        .O(o_ingress_clk)
    );

        end
    endgenerate

endmodule
