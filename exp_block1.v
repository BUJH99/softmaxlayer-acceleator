`timescale 1ns / 1ps

/**
 * @모듈 exp_Block1
 * @brief LUT 기반의 순차 곱셈 방식을 사용하여 e^x를 계산하며, ready/valid 핸드셰이크를 지원합니다.
 * @상세설명
 *  - 알고리즘: 입력값 n의 각 비트를 순회하며, 해당 비트가 1일 경우 미리 계산된 e^(-2^k) 값을 누적 곱셈합니다.
 *  - 입력 (iData): 16비트 부호 있는 Q7.8 형식. (7 정수부, 8 소수부)
 *  - 출력 (oData): 16비트 부호 없는 Q0.16 형식. (결과는 항상 0과 1 사이)
 *  - 흐름 제어: oReady 신호를 통해 데이터 소스에게 데이터를 받을 수 있는 상태임을 알립니다.
 *              데이터 전송은 iValid와 oReady가 모두 1일 때 발생합니다.
 */
module exp_Block1 (
    // --- 시스템 신호 ---
    input wire          iClk,           // 시스템 클럭
    input wire          iRsn,           // 비동기 리셋 (Active Low)

    // --- 입력 인터페이스 (AXI-Stream Slave 스타일) ---
    input wire          iValid,         // 입력 데이터(iData)가 유효함을 나타내는 신호
    output wire         oReady,         // 모듈이 새로운 데이터를 받을 준비가 되었음을 나타내는 신호
    input wire          iLast,          // 데이터 스트림의 마지막 데이터임을 표시
    input wire signed   [15:0] iData,   // e^x 계산을 위한 입력 데이터 (Q7.8 형식)

    // --- 출력 인터페이스 (AXI-Stream Master 스타일) ---
    output wire         oValid,         // 출력 데이터(oData)가 유효함을 나타내는 신호
	input  wire         iReady,
    output wire         oLast,          // 출력 스트림의 마지막 데이터임을 표시
    output wire [15:0]  oData           // 계산 결과 (Q0.16 형식)
);

    /**********************************************************************
     * 와이어 및 데이터 경로 레지스터
     **********************************************************************/
    // 데이터 경로 레지스터
    reg signed [15:0] rDataIn;          // 입력 데이터를 래칭하기 위한 레지스터
    reg [31:0]        rProductAcc;      // 중간 곱셈 결과를 누적하는 레지스터 (Q0.32 형식, 정밀도 손실 방지)
    reg [3:0]         rBitCounter;      // 현재 처리 중인 비트 위치를 추적하는 카운터 (k값)
    reg               rIsLast;          // iLast 신호를 래칭하여 출력 시점에 동기화

    // 조합 논리 와이어
    wire [15:0] wAbsN;                  // 입력 데이터의 절대값 (알고리즘은 양수 기반으로 동작)
    wire [15:0] wLutVal;                // 비트 카운터 값에 해당하는 LUT 값 (e^(-2^k))
    wire        wHandshake;             // 데이터 전송이 실제로 일어나는 조건 (iValid && oReady)

    // LUT (Look-Up Table) 정의: e^(-2^k) 값을 Q0.16 형식으로 미리 계산
    // k = 3  (2^3 = 8)  -> e^-8   ~= 0.000335 -> 16'h0015 -> 16'd21
    // k = -8 (2^-8=0.0039) -> e^-0.0039 ~= 0.996101 -> 16'hFEF7 -> 16'd65271
    assign wLutVal = 
        (rBitCounter == 4'd11) ? 16'd22    : // k=3,  e^-8
        (rBitCounter == 4'd10) ? 16'd1200  : // k=2,  e^-4
        (rBitCounter == 4'd9)  ? 16'd8870  : // k=1,  e^-2
        (rBitCounter == 4'd8)  ? 16'd24108 : // k=0,  e^-1
        (rBitCounter == 4'd7)  ? 16'd39749 : // k=-1, e^-0.5
        (rBitCounter == 4'd6)  ? 16'd51039 : // k=-2, e^-0.25
        (rBitCounter == 4'd5)  ? 16'd57835 : // k=-3, e^-0.125
        (rBitCounter == 4'd4)  ? 16'd61564 : // k=-4, e^-0.0625
        (rBitCounter == 4'd3)  ? 16'd63518 : // k=-5, e^-0.03125
        (rBitCounter == 4'd2)  ? 16'd64518 : // k=-6, e^-0.015625
        (rBitCounter == 4'd1)  ? 16'd65024 : // k=-7, e^-0.0078125
        (rBitCounter == 4'd0)  ? 16'd65279 : // k=-8, e^-0.00390625
                                 16'hFFFF;  // 기본값 (사용되지 않음)

    // 입력값이 음수일 경우 2의 보수를 취하여 절대값을 계산
    assign wAbsN = (rDataIn[15]) ? -rDataIn : rDataIn;

    /**********************************************************************
     * 유한 상태 머신 (FSM)
     **********************************************************************/
    // FSM 상태 정의
    parameter [1:0] p_Idle = 2'b00; // 대기 상태: 새로운 입력을 기다림
    parameter [1:0] p_Calc = 2'b01; // 계산 상태: 순차 곱셈 수행
    parameter [1:0] p_Done = 2'b10; // 완료 상태: 결과 출력

    // FSM 레지스터 선언
    reg [1:0] rCurState;
    reg [1:0] rNxtState;
    
    // 핸드셰이크 로직: 모듈은 대기(Idle) 상태일 때만 새로운 데이터를 받을 준비가 됨
    assign oReady = (rCurState == p_Idle);
    assign wHandshake = iValid && oReady;

    // FSM 상태 업데이트 (순차 로직): 클럭 엣지에서 현재 상태를 다음 상태로 변경
    always @(posedge iClk or negedge iRsn) begin
        if (!iRsn)
            rCurState <= p_Idle;
        else
            rCurState <= rNxtState;
    end

    // FSM 다음 상태 결정 (조합 논리): 현재 상태와 입력에 따라 다음 상태를 결정
    always @(*) begin
        rNxtState = rCurState; 
        case (rCurState)
            p_Idle:
                // 유효한 데이터가 들어오면 계산 상태로 전환
                if (wHandshake)
                    rNxtState = p_Calc;
            p_Calc:
                // 비트 카운터가 0이 되면 모든 비트 처리가 완료되었으므로 완료 상태로 전환
                if (rBitCounter == 4'd0)
                    rNxtState = p_Done;
            p_Done:
                // 결과 출력이 끝나면 다시 대기 상태로 전환
                rNxtState = p_Idle;
            default:
                rNxtState = p_Idle;
        endcase
    end

    /**********************************************************************
     * 데이터 경로 로직
     **********************************************************************/
    always @(posedge iClk or negedge iRsn) begin
        if (!iRsn) begin
            rDataIn     <= 16'd0;
            rProductAcc <= 32'd0;
            rBitCounter <= 4'd0;
            rIsLast     <= 1'b0;
        end else begin
            // 핸드셰이크가 성공했을 때만 입력 데이터를 래치
            if (wHandshake) begin
                rDataIn <= iData;
                rIsLast <= iLast;
            end

            case (rCurState)
                p_Idle: begin
                    // 새로운 데이터가 들어오면 계산을 위한 초기화 수행
                    if (wHandshake) begin
                        // 누적 곱셈기는 곱셈의 항등원인 1.0 (Q0.32 형식)으로 초기화
                        rProductAcc <= 32'hFFFFFFFF; 
                        // 비트 카운터는 최상위 비트부터 시작 (k=3, 정수부)
                        rBitCounter <= 4'd11; 
                    end
                end
                p_Calc: begin
					if (iReady) begin
                    // 입력값의 현재 비트(rBitCounter 위치)가 1이면, 해당 LUT 값을 누적 곱셈
                    if (wAbsN[rBitCounter]) begin
                        // Q0.16 * Q0.16 곱셈. 결과는 Q0.32. 누적기의 상위 16비트와 LUT 값을 곱함.
                        rProductAcc <= (rProductAcc[31:16] * wLutVal);
                    end
                    // 다음 비트를 처리하기 위해 카운터 감소
                    rBitCounter <= rBitCounter - 1;
					end
                end
                p_Done: begin
                    // 완료 상태에서는 특별한 동작 없음. 값 유지.
                    rBitCounter <= 4'd0;
                end
            endcase
        end
    end

    /**********************************************************************
     * 출력 로직
     ***************************************x*******************************/
    // 최종 결과(Q0.32)의 상위 16비트를 출력 (Q0.16 형식)
    assign oData  = rProductAcc[31:16];
    // 계산이 완료된 상태(Done)일 때만 출력이 유효함
    assign oValid = (rCurState == p_Done);
    // 계산 완료 및 입력이 마지막 데이터였을 경우 oLast 신호 생성
    assign oLast  = (rCurState == p_Done) && rIsLast;

endmodule