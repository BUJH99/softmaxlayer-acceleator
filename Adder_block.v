/******************************************************************************
*
* 모듈: Adder_block (정밀/안정화 개선 + 출력 Q5.11 버전)
*
* 변경 요약:
*  1) 프레임 종료(iLast) 시 누산기(rSumAcc) 즉시 0 클리어(프레임 간 누수 방지)
*  2) 누적 포맷: Q11.16 (27b) 유지 (입력 Q0.16 안전 누적)
*  3) 최종 출력 포맷: 16b Q5.11 (unsigned)
*     - Q11.16 → Q5.11: 반올림(half-up) 후 >>5
*     - **포화(saturation) 추가**: 16비트 초과 시 0xFFFF로 포화
*
******************************************************************************/
module Adder_block (
    input  wire         iClk,
    input  wire         iRsn,

    // --- 입력 인터페이스 (AXI-Stream Slave 스타일) ---
    input  wire         iValid,
    output wire         oReady,
    input  wire         iLast,
    input  wire [15:0]  iData,  // Q0.16 (unsigned)

    // --- 출력 인터페이스 (AXI-Stream Master 스타일) ---
    output wire         oValid,
    input  wire         iReady,
    output wire [15:0]  oData   // Q5.11 (unsigned)
);

    localparam ST_IDLE    = 1'b0;
    localparam ST_SUMMING = 1'b1;

    // 변환 상수: Q11.16 -> Q5.11
    localparam integer SHIFT_FRAC  = 5;      // 16 → 11
    localparam [26:0]  ROUND_CONST = 27'd16; // +2^(SHIFT_FRAC-1)

    // --- 상태 및 데이터 레지스터 ---
    reg        rState;
    reg [26:0] rSumAcc;      // 누적기: Q11.16 (0..~2047.x)
    reg [15:0] rDataOut;     // 출력 레지스터: Q5.11
    reg        rValidOut;

    // --- 핸드셰이크 신호 ---
    wire fire = iValid && oReady;

    // 입력 확장: Q0.16 → Q11.16 (상위 11비트 제로 확장)
    wire [26:0] wDataExtended  = {11'b0, iData}; // 27b Q11.16

    // 누적 합(이번 샘플 반영)
    wire [26:0] wTransactionSum =
        (rState == ST_IDLE) ? wDataExtended : (rSumAcc + wDataExtended);

    // Q11.16 → Q5.11 : 반올림(+16) 후 >>5
    wire [26:0] wRoundAdd     = wTransactionSum + ROUND_CONST;
    wire [21:0] wShifted      = wRoundAdd[26:5];         // 총 22b로 축소
    wire        overflow_q511 = |wShifted[21:16];         // 16비트 초과 여부
    wire [15:0] wDataOutQ511  = overflow_q511 ? 16'hFFFF // 포화
                                              : wShifted[15:0];

    // 다음 상태
    reg rNextState;
    always @(*) begin
        rNextState = rState;
        case (rState)
            ST_IDLE:    if (fire)            rNextState = ST_SUMMING;
            ST_SUMMING: if (fire && iLast)   rNextState = ST_IDLE;
        endcase
    end

    // 순차 로직
    always @(posedge iClk or negedge iRsn) begin
        if (!iRsn) begin
            rState    <= ST_IDLE;
            rSumAcc   <= 27'b0;
            rValidOut <= 1'b0;
            rDataOut  <= 16'b0;
        end else begin
            rState <= rNextState;

            // 출력 소비되면 valid 낮춤
            if (rValidOut && iReady) begin
                rValidOut <= 1'b0;
            end

            if (fire) begin
                // 누적 진행
                rSumAcc <= wTransactionSum;

                if (iLast) begin
                    // 프레임 종료: 결과 산출 및 valid 세트
                    rDataOut  <= wDataOutQ511; // Q5.11
                    rValidOut <= 1'b1;

                    // 프레임 간 누수 방지
                    rSumAcc   <= 27'd0;
                end
            end
        end
    end

    // 출력 및 준비 신호
    assign oData  = rDataOut;                 // Q5.11
    assign oValid = rValidOut;
    assign oReady = !rValidOut || iReady;     // 출력 홀드 중에는 입력 정지

endmodule
