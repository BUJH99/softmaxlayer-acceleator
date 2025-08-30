`timescale 1ns/1ps
// FSMD Subtractor (Verilog-2001)
// - Q7.8(16-bit, signed two's complement)
// - Handshake:
//    * data2_en : latch data2_i (only in IDLE)
//    * data1_req: request data1 frames while running
//    * data1_en : when high, accept data1_i
//      -> same cycle: outc=1 (counter increments externally)
//      -> next cycle: data_valid_o=1 with data_o = (data1_i - latched_data2)
// - count_i is external counter value; we continue until count_i reaches CNT_MAX
//   (implementation: when count_i == CNT_MAX-1 and we accept data1_en, that was the last one)
// - Further data2_en during RUN/DONE is ignored.

module fsmd_subtractor #(
    parameter integer SATURATE = 1,      // 1: saturate on overflow, 0: wrap
    parameter integer count_width  = 8      // 반복할 총 개수(외부 counter 목표치)
)(
    input  wire         clk,
    input  wire         rst_n,       // active-low

    // stream-2 (trigger/latch)
    input  wire         data2_en,
    input  wire [15:0]  data2_i,

    // stream-1 (data frames)
    output reg          data1_req,   // 요청 유지(런 중에는 1)
    input  wire         data1_en,    // data1_i 유효
    input  wire [15:0]  data1_i,

    // external counter feedback
    input  wire [count_width - 1:0]  count_i,     // 외부 카운터 값 (증분은 outc에 의해)
	
	input  wire 		ready,
	
	input  wire [count_width - 1:0]  last_count,

    // results
    output reg  [15:0]  data_o,       // Q7.8 결과
    output reg          data_valid_o, // 결과 유효 1펄스 (data1_en 수신 다음 사이클)
    output reg          outc,          // 카운터 증가 펄스 (data1_en 수신 사이클)
    output reg          last
);

    // Q7.8 범위 상수
    localparam [15:0] Q16_POS_MAX = 16'h7FFF; // +127.99609375
    localparam [15:0] Q16_NEG_MIN = 16'h8000; // -128.0

    // 상태
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] REQ  = 2'd1;
    localparam [1:0] RUN  = 2'd2;  // 결과 내보내는 사이클 (valid 펄스)

    reg [1:0] state, state_n;

    // data2 래치
    reg [15:0] d2_q;

    // 결과 파이프 (data1_en 수신 직후 계산 -> 다음 사이클 OUT에서 valid)
    reg [15:0] result_q;
    
    reg waiting;

    // 마지막 트랜잭션 여부 플래그

    // -----------------------------
    // Q7.8 subtract (선택적 포화)
    // -----------------------------
    function [15:0] sub_q7p8;
        input [15:0] a;
        input [15:0] b;
        reg signed [16:0] wide;
        reg s_a, s_b, s_r;
        reg ovf;
    begin
        if (SATURATE) begin
            // sign-extend and subtract in 17 bits
            wide = $signed({a[15], a}) - $signed({b[15], b});
            s_a  = a[15];
            s_b  = b[15];
            s_r  = wide[16];
            // overflow rule for a - b == a + (~b+1)
            ovf  = ((s_a == ~s_b) && (s_r != s_a));
            if (ovf)
                sub_q7p8 = s_a ? Q16_NEG_MIN : Q16_POS_MAX;
            else
                sub_q7p8 = wide[15:0];
        end else begin
            sub_q7p8 = a - b; // wrap-around
        end
    end
    endfunction

    // -----------------------------
    // 순차 로직
    // -----------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            d2_q         <= 16'd0;
            result_q     <= 16'd0;

            data1_req    <= 1'b0;
            data_o       <= 16'd0;
            data_valid_o <= 1'b0;
            outc         <= 1'b0;
            last         <= 1'b0;
            waiting      <= 1'b0;
        end else begin
            state        <= state_n;

            // 기본 펄스 신호들 0으로
            data_valid_o <= 1'b0;
            outc         <= 1'b0;
			data1_req    <= 1'b0;
			last         <= 1'b0;
			waiting      <= 1'b0;
            case (state)
                // ----------------- IDLE -----------------
                IDLE: begin
                    data1_req <= 1'b0;
                    
                    if (data2_en) begin
                        // data2_en 들어온 그 사이클 data2_i 래치
                        d2_q      <= data2_i;
                        data1_req <= 1'b1;   // 요청 시작
                    end
                end

                // ----------------- RUN ------------------
                // 런 중에는 새로운 data2_en 무시, data1_req 유지
                // data1_en 수신 시:
                //   - 같은 사이클에 outc=1 (외부 카운터 증가)
                //   - 결과 계산해 result_q 저장
                //   - count_i == CNT_MAX-1 인지 봐서 마지막여부 기록
                REQ: begin
                    data1_req <= 1'b1; // 계속 요청 유지
                    if (data1_en && ready && !waiting) begin
                        outc         <= 1'b1;
                        //last_tran_d <= (count_i == (CNT_MAX-1));
                    end
                end

                // ----------------- S_OUT ----------------
                // data_valid_o 한 사이클 펄스, data_o 출력
                RUN: begin   
                    data_o    <= sub_q7p8(data1_i, d2_q);
                    data_valid_o <= 1'b1;               
                    if (count_i == last_count - 1'b1) begin
                        data1_req <= 1'b0;
                        last <= 1'b1;
                    end else begin
                        data1_req <= 1'b1; // 계속 다음 프레임 요청
                        waiting      <= 1'b1;
                    end
                end

                // ----------------- DONE -----------------
                // 한 시퀀스 종료, 다음 data2_en을 기다림

                default: begin
                    data1_req <= 1'b0;
                end
            endcase
        end
    end

    // -----------------------------
    // 조합: 다음 상태 & last_tran_d 기본값
    // -----------------------------
    always @* begin
        state_n     = state;

        case (state)
            IDLE: begin
                if (data2_en)
                    state_n = REQ;
                else
                    state_n = IDLE;
            end

            REQ: begin
                if (data1_en && ready && !waiting)
                    state_n = RUN;
                else
                    state_n = REQ;   
            end

            RUN: begin
                if (count_i == last_count - 1'b1)
                    state_n = IDLE;    // 이번이 마지막 처리였음
                else
                    state_n = REQ;     // 계속 수신 반복
            end

            default: state_n = IDLE;
        endcase
    end

endmodule