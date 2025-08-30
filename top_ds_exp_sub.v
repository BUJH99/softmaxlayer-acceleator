`timescale 1ns/1ps

module top_ds_exp_sub #(
    parameter integer C_MAX    = 1024,
    parameter integer ADDR_W   = 10   // downscale 내부 버퍼 주소폭
)(
    input  wire         clk,
    input  wire         rst_n,

    // ── FP32 입력 (downscale 입력)
    input  wire         s_axis_tvalid,
    input  wire [31:0]  s_axis_tdata,
    input  wire         s_axis_tlast,   
    
    // ── 최종 결과 (fp32):
    output wire [31:0]  final_data_o,
    output wire         final_vaild_o,
    input wire          ready
);

    // ───────── downscale 출력
    wire        ds_ready;
    wire        add_ready_o;
    wire        ln_ready_o;
    wire        buffer_ready_o;
    
    wire         s_axis_tready;
    
    // ── down 결과 (Q7.8)
    wire        ds_valid;
    wire [15:0] ds_data;  // Q7.8 : (xi - xmax)
    wire        ds_last;

    // ── exp1 결과 (Q0.16)
    wire         exp_valid_o;
    wire         exp_last_o;
    wire [15:0]  exp_data_o;
    
    // ── ADD 결과
    wire         add_valid_o;
    wire [15:0]  add_data_o;
    
    // ── ln 결과
    wire         ln_valid_o;
    wire [15:0]  ln_data_i;

    // ── sub 결과: (xi-xmax) - ln_sum  (Q7.8)
    wire         sub_valid_o;
    wire [15:0]  sub_data_o;
    wire         sub_last;
    
    // ── exp2 결과 (Q0.16):
    wire         exp2_valid_o;
    wire         exp2_last_o;
    wire [15:0]  exp2_data_o;
    
    // ── fp32 결과:
    wire         fp32_valid_o;
    wire [31:0]  fp32_data_o;
    

    downscale_block #(.C_MAX(C_MAX), .ADDR_W(ADDR_W)) u_down (
        .clk(clk), .rst_n(rst_n),

        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tlast (s_axis_tlast),

        .m_axis_tvalid(ds_valid),
        .m_axis_tready(ds_ready),
        .m_axis_tdata (ds_data),
        .m_axis_tlast (ds_last)
    );

    // ───────── exp1 (Q7.8 → Q0.16)

    exp_Block1 u_exp1 (
        .iClk  (clk),
        .iRsn  (rst_n),

        .iValid(ds_valid),      // downscale가 내보내는 동안 valid=1 유지
        .oReady(ds_ready),    // 여기서 한 번만 수락하도록 펄스
        .iLast (ds_last),
        .iData (ds_data),

        .oValid(exp_valid_o),
        .iReady(add_ready_o),
        .oLast (exp_last_o),
        .oData (exp_data_o)
    );

    // ───────── sub : (xi-xmax) - ln_sum
    Sub_block #(
        .CNT_MAX   (C_MAX)
    ) u_sub (
        .clk  (clk),
        .rst_n(rst_n),

        // downscale에서 '실제 수락된' 사이클만 저장
        .downscale_data_i       (ds_data),
        .downscale_data_valid_i (ds_valid & ds_ready),

        // ln 입력(외부 1펄스)
        .in_data_i      (ln_data_i),
        .in_data_valid_i(ln_valid_o),
        .ready(ds_ready2),
        .data_o       (sub_data_o),
        .data_valid_o (sub_valid_o),
        .last(sub_last)
    );
    
    exp_Block1 u_exp2 (
        .iClk  (clk),
        .iRsn  (rst_n),

        .iValid(sub_valid_o),      // downscale가 내보내는 동안 valid=1 유지
        .oReady(ds_ready2),    // 여기서 한 번만 수락하도록 펄스
        .iLast (sub_last),
        .iData (sub_data_o),

        .oValid(exp2_valid_o),
        .iReady(buffer_ready_o),
        .oLast (exp2_last_o),
        .oData (exp2_data_o)
    );
    
    Adder_block adder (
        .iClk  (clk),
        .iRsn  (rst_n),
        
        .iValid(exp_valid_o),
        .oReady(add_ready_o),
        .iLast(exp_last_o),
        .iData(exp_data_o),
        
        .oValid(add_valid_o),
        .iReady(ln_ready_o),
        .oData(add_data_o)       
    );
    
    ln_block ln (
        .iClk  (clk),
        .iRsn  (rst_n),
        
        .iValid(add_valid_o),
        .oReady(ln_ready_o),
        .iData(add_data_o),
        
        .oValid(ln_valid_o),
        .iReady(1),
        .oData(ln_data_i)        
    );
    
    u016_to_fp32 fp32 (
        .in_u016(exp2_data_o),
        .in_valid(exp2_valid_o),
        .out_fp32(fp32_data_o),
        .out_valid(fp32_valid_o)
    );
    
    buffer_FIFO #(
        .DEPTH   (C_MAX)
    ) buffer_FIFO_1 (
        .clk  (clk),
        .rst_n(rst_n),
        
        .s_valid_i(fp32_valid_o),
        .s_data_i(fp32_data_o),
        .s_last_i(exp2_last_o),
        .s_ready_o(buffer_ready_o),
        
        .m_ready_i(ready),
        .m_valid_o(final_vaild_o),
        .m_data_o(final_data_o)
    );

endmodule
