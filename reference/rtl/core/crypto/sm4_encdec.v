`default_nettype wire
`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/10 10:37:43
// Design Name: 
// Module Name: sm4_encdec
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: SM4 Encryption/Decryption - Folded Architecture
//              2 rounds per clock cycle, 16 iterations for 32 rounds total.
//              Target: 75MHz (13.333ns). Logic ~3ns + routing budget ~10ns.
// 
// Dependencies: one_round_for_encdec
// 
// Revision:
// Revision 2.0 - Folded from 4-round to 2-round per cycle for timing
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module sm4_encdec(
    input  wire           clk                 ,
    input  wire           reset_n             ,
    input  wire           sm4_enable_in       ,
    input  wire           encdec_enable_in    ,
    input  wire           key_exp_ready_in    ,
    input  wire           valid_in            ,
    input  wire  [127: 0] data_in             ,
    input  wire  [31 : 0] rk_00_in            ,
    input  wire  [31 : 0] rk_01_in            ,
    input  wire  [31 : 0] rk_02_in            ,
    input  wire  [31 : 0] rk_03_in            ,
    input  wire  [31 : 0] rk_04_in            ,
    input  wire  [31 : 0] rk_05_in            ,
    input  wire  [31 : 0] rk_06_in            ,
    input  wire  [31 : 0] rk_07_in            ,
    input  wire  [31 : 0] rk_08_in            ,
    input  wire  [31 : 0] rk_09_in            ,
    input  wire  [31 : 0] rk_10_in            ,
    input  wire  [31 : 0] rk_11_in            ,
    input  wire  [31 : 0] rk_12_in            ,
    input  wire  [31 : 0] rk_13_in            ,
    input  wire  [31 : 0] rk_14_in            ,
    input  wire  [31 : 0] rk_15_in            ,
    input  wire  [31 : 0] rk_16_in            ,
    input  wire  [31 : 0] rk_17_in            ,
    input  wire  [31 : 0] rk_18_in            ,
    input  wire  [31 : 0] rk_19_in            ,
    input  wire  [31 : 0] rk_20_in            ,
    input  wire  [31 : 0] rk_21_in            ,
    input  wire  [31 : 0] rk_22_in            ,
    input  wire  [31 : 0] rk_23_in            ,
    input  wire  [31 : 0] rk_24_in            ,
    input  wire  [31 : 0] rk_25_in            ,
    input  wire  [31 : 0] rk_26_in            ,
    input  wire  [31 : 0] rk_27_in            ,
    input  wire  [31 : 0] rk_28_in            ,
    input  wire  [31 : 0] rk_29_in            ,
    input  wire  [31 : 0] rk_30_in            ,
    input  wire  [31 : 0] rk_31_in            ,
    output wire  [127: 0] result_out          ,   
    output wire           ready_out          
);
    
    localparam IDLE            = 2'b00;
    localparam WAITING_FOR_KEY = 2'b01;
    localparam ENCRYPTION      = 2'b10;
    
    // ==============================================================
    // 2-Round Folded Architecture
    // - 2 rounds of combinational logic per clock cycle
    // - 4-bit counter (0~15) iterates 16 cycles to complete 32 rounds
    // - Target: 75MHz (13.333ns). Logic delay ~3ns, routing ~10ns.
    // ==============================================================
    
    reg     [31  : 0] reg_tmp           ;
    reg     [1   : 0] current           ;
    reg     [1   : 0] next              ;
    
    reg     [3:0]   round_cnt;          // 0-15 for 16 iterations
    wire    [127:0] iter_data_in;
    wire    [127:0] iter_result_0;
    wire    [127:0] iter_result_1;
    wire    [127:0] result_31;
    
    // State register: holds result after each 2-round iteration
    reg     [127:0] current_state_reg;
    
    // Input MUX: first iteration takes external data, rest from feedback
    assign iter_data_in = (round_cnt == 4'd0) ? data_in : current_state_reg;
    
    // Dynamic round key selection (2 keys per iteration cycle)
    reg [31:0] sel_rk_0, sel_rk_1;
    always @(*) begin
        case(round_cnt)
            4'd0:    begin sel_rk_0 = rk_00_in; sel_rk_1 = rk_01_in; end
            4'd1:    begin sel_rk_0 = rk_02_in; sel_rk_1 = rk_03_in; end
            4'd2:    begin sel_rk_0 = rk_04_in; sel_rk_1 = rk_05_in; end
            4'd3:    begin sel_rk_0 = rk_06_in; sel_rk_1 = rk_07_in; end
            4'd4:    begin sel_rk_0 = rk_08_in; sel_rk_1 = rk_09_in; end
            4'd5:    begin sel_rk_0 = rk_10_in; sel_rk_1 = rk_11_in; end
            4'd6:    begin sel_rk_0 = rk_12_in; sel_rk_1 = rk_13_in; end
            4'd7:    begin sel_rk_0 = rk_14_in; sel_rk_1 = rk_15_in; end
            4'd8:    begin sel_rk_0 = rk_16_in; sel_rk_1 = rk_17_in; end
            4'd9:    begin sel_rk_0 = rk_18_in; sel_rk_1 = rk_19_in; end
            4'd10:   begin sel_rk_0 = rk_20_in; sel_rk_1 = rk_21_in; end
            4'd11:   begin sel_rk_0 = rk_22_in; sel_rk_1 = rk_23_in; end
            4'd12:   begin sel_rk_0 = rk_24_in; sel_rk_1 = rk_25_in; end
            4'd13:   begin sel_rk_0 = rk_26_in; sel_rk_1 = rk_27_in; end
            4'd14:   begin sel_rk_0 = rk_28_in; sel_rk_1 = rk_29_in; end
            4'd15:   begin sel_rk_0 = rk_30_in; sel_rk_1 = rk_31_in; end
            default: begin sel_rk_0 = 32'd0;    sel_rk_1 = 32'd0;    end
        endcase
    end
    
    // 2-round combinational chain
    one_round_for_encdec u_iter_0 ( .data_in(iter_data_in),  .round_key_in(sel_rk_0), .result_out(iter_result_0) );
    one_round_for_encdec u_iter_1 ( .data_in(iter_result_0), .round_key_in(sel_rk_1), .result_out(iter_result_1) );
    
    // FSM: IDLE -> WAITING_FOR_KEY -> ENCRYPTION
    reg working;
    
    always@(posedge clk or negedge reset_n)
    if(!reset_n)
        current <= IDLE;
    else if(sm4_enable_in)
        current <= next;
        
    always@(*)        
        begin
            next = IDLE;
            case(current)
                IDLE :
                        if(sm4_enable_in && encdec_enable_in)
                            next = WAITING_FOR_KEY;
                        else
                            next = IDLE;
                WAITING_FOR_KEY :
                        if(key_exp_ready_in)
                            next = ENCRYPTION;
                        else
                            next = WAITING_FOR_KEY;
                ENCRYPTION :
                        if(!encdec_enable_in || !sm4_enable_in)
                            next = IDLE;
                        else 
                            next = ENCRYPTION;
                default :
                        next = IDLE;
            endcase
        end
                
    always@(posedge clk or negedge reset_n)
    if(!reset_n)
        reg_tmp <= 32'b0;
    else if(current == IDLE)
        reg_tmp <= 32'b0;
    else if(current == ENCRYPTION && valid_in)
        reg_tmp <= {reg_tmp[30 : 0], 1'b1};
    else
        reg_tmp <= {reg_tmp[30 : 0], 1'b0};

    // Iteration controller: 16 cycles x 2 rounds = 32 rounds total
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            working <= 1'b0;
            round_cnt <= 4'd0;
            current_state_reg <= 128'd0;
        end else if (current == ENCRYPTION) begin
            if (working) begin
                if (round_cnt == 4'd15) begin
                    // All 32 rounds complete
                    working <= 1'b0;
                    round_cnt <= 4'd0;
                end else begin
                    round_cnt <= round_cnt + 4'd1;
                end
                // Register the 2-round combinational result
                current_state_reg <= iter_result_1;
            end else if (valid_in) begin
                working <= 1'b1;
                round_cnt <= 4'd0;
                current_state_reg <= data_in;
            end
        end else begin
            working <= 1'b0;
            round_cnt <= 4'd0;
        end
    end
    
    // Final result = last iteration output (combinational)
    assign result_31 = iter_result_1;
    
    // Output byte-reversal (SM4 spec: reverse word order)
    wire    [31  : 0] word_0            ;
    wire    [31  : 0] word_1            ;
    wire    [31  : 0] word_2            ;
    wire    [31  : 0] word_3            ;
    wire    [127 : 0] reversed_result_31;

    assign { word_0, word_1, word_2, word_3} = result_31;
    assign reversed_result_31 = {word_3, word_2, word_1, word_0};

    // Pipeline register on output: breaks critical path to ROB
    // Adds 1-cycle latency but does NOT affect throughput
    reg [127:0] result_out_reg;
    reg         ready_out_reg;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            result_out_reg <= 128'd0;
            ready_out_reg  <= 1'b0;
        end else begin
            ready_out_reg  <= working && (round_cnt == 4'd15);
            result_out_reg <= reversed_result_31;
        end
    end
    
    assign result_out = result_out_reg;
    assign ready_out  = ready_out_reg;
        
                                                    
endmodule
