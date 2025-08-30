/******************************************************************************
*
* 모듈: ln_block (Q5.11 입력 대응: FXP→FP 정규화 수정판)
*
* 입력 포맷: Q5.11 (unsigned, 16b)
* 정규화:
*   - msb_pos = 입력의 최상위 1의 위치(0..15)
*   - exp = msb_pos - 11
*   - E(addr) = exp + 15 = msb_pos + 4          // ln_lut_exp 주소
*   - 1.mant 구성: MSB를 bit15로 정렬 후, 가수 상위 10비트 추출
*
******************************************************************************/

module ln_block (
    // --- 시스템 신호 ---
    input wire          iClk,
    input wire          iRsn,

    // --- 입력 인터페이스 (AXI-Stream Slave 스타일) ---
    input wire          iValid,
    output wire         oReady,
    input wire [15:0]   iData,   // Q5.11 (unsigned)

    // --- 출력 인터페이스 (AXI-Stream Master 스타일) ---
    output wire         oValid,
    input  wire         iReady,
    output wire signed [15:0]  oData  // Q7.8 (signed)
);

    // --- 핸드셰이크 신호 (4단 파이프라인) ---
    wire pipe1_ready, pipe2_ready, pipe3_ready, pipe4_ready;

    reg rPipe1_valid, rPipe2_valid, rPipe3_valid, rPipe4_valid;

    assign pipe4_ready = !rPipe4_valid || iReady;
    assign pipe3_ready = !rPipe3_valid || pipe4_ready;
    assign pipe2_ready = !rPipe2_valid || pipe3_ready;
    assign pipe1_ready = !rPipe1_valid || pipe2_ready;
    assign oReady      = pipe1_ready;

    /**********************************************************************
     * Stage 1: FXP(Q5.11) → 정규화(1.mant, exp)
     **********************************************************************/
    reg  [4:0] rPipe1_E;        // E = exp + 15 = msb_pos + 4
    reg  [9:0] rPipe1_mant;     // 1.mant의 가수 상위 10비트

    wire [3:0] msb_pos;
    wire       is_zero;
    priority_encoder_16bit u_pe (.in(iData), .pos(msb_pos), .zero(is_zero));

    // Q5.11 입력 → exp = msb_pos - 11 → E = msb_pos + 4
    wire [4:0] wPipe1_E = msb_pos + 5'd4;

    // MSB를 bit15로 정렬 후, 가수 상위 10비트 추출
    wire [15:0] wShiftedMant = iData << (15 - msb_pos);
    wire [9:0]  wPipe1_mant  = wShiftedMant[14:5];

    always @(posedge iClk or negedge iRsn) begin
        if (!iRsn) begin
            rPipe1_valid <= 1'b0;
        end else if (pipe1_ready) begin
            rPipe1_valid <= iValid;
            if (iValid) begin
                if (is_zero) begin
                    rPipe1_E    <= 5'd0;     // 보호적 값(실사용 경로에서는 0 입력이 나오지 않음 가정)
                    rPipe1_mant <= 10'd0;
                end else begin
                    rPipe1_E    <= wPipe1_E;
                    rPipe1_mant <= wPipe1_mant;
                end
            end
        end
    end

    /**********************************************************************
     * Stage 2: LUT 조회 (ln(2)*exp, ln(1.mant) 테이블 & 보간 준비)
     **********************************************************************/
    // rPipe2_ln2_exp_val: signed Q4.11 (16b), 이후 <<5로 Q4.16에 정렬
    reg signed [15:0] rPipe2_ln2_exp_val;   // Q4.11
    reg [15:0]        rPipe2_y0;            // Q0.16
    reg [15:0]        rPipe2_y1;            // Q0.16
    reg [1:0]         rPipe2_frac;
    reg [7:0]         rPipe2_mant_addr_base;

    wire [7:0] mant_addr_base = rPipe1_mant[9:2];  // 상위 8비트
    wire [7:0] mant_addr_next = mant_addr_base + 1;

    wire signed [15:0] wLn2ExpVal;
    wire [15:0]        wLnMant_y0;
    wire [15:0]        wLnMant_y1;

    ln_lut_exp   u_lut_exp  (.addr(rPipe1_E),       .data(wLn2ExpVal));
    ln_lut_mant  u_lut_mant0(.addr(mant_addr_base), .data(wLnMant_y0));
    ln_lut_mant  u_lut_mant1(.addr(mant_addr_next), .data(wLnMant_y1));

    always @(posedge iClk or negedge iRsn) begin
        if (!iRsn) begin
            rPipe2_valid <= 1'b0;
        end else if (pipe2_ready) begin
            rPipe2_valid <= rPipe1_valid;
            if (rPipe1_valid) begin
                rPipe2_ln2_exp_val   <= wLn2ExpVal;
                rPipe2_y0            <= wLnMant_y0;
                rPipe2_y1            <= wLnMant_y1;
                rPipe2_frac          <= rPipe1_mant[1:0];
                rPipe2_mant_addr_base<= mant_addr_base;
            end
        end
    end

    /**********************************************************************
     * Stage 3: 선형 보간(Q0.16) + ln2*exp(Q4.11) 정렬 후 합산(Q4.16) → Q7.8
     **********************************************************************/
    reg signed [15:0] rPipe3_data_out;

    // 선형 보간 (addr_base==255 경계 클램프)
    wire signed [16:0] delta_y = (rPipe2_mant_addr_base == 8'd255) ? 17'sd0
                              : $signed(rPipe2_y1) - $signed(rPipe2_y0);
    wire signed [18:0] product      = delta_y * rPipe2_frac;    // 2비트 frac
    wire signed [16:0] interp_term  = product >>> 2;            // >>2
    wire [15:0]        ln_mant_interp_q0_16 = rPipe2_y0 + interp_term;

    // 포맷 정렬 및 합산
    wire signed [20:0] ln2_exp_q4_16  = {rPipe2_ln2_exp_val, 5'b0};     // Q4.11 -> Q4.16
    wire signed [20:0] ln_mant_q4_16  = {5'b0, ln_mant_interp_q0_16};   // Q0.16 -> Q4.16
    wire signed [20:0] sum_q4_16      = ln2_exp_q4_16 + ln_mant_q4_16;

    // Q4.16 -> Q7.8 (half-up 반올림)
    wire signed [15:0] temp_q7_8   = {{3{sum_q4_16[20]}}, sum_q4_16[20:8]};
    wire signed [15:0] wFinalResult= temp_q7_8 + sum_q4_16[7];

    always @(posedge iClk or negedge iRsn) begin
        if (!iRsn) begin
            rPipe3_valid <= 1'b0;
        end else if (pipe3_ready) begin
            rPipe3_valid <= rPipe2_valid;
            if (rPipe2_valid) begin
                rPipe3_data_out <= wFinalResult;
            end
        end
    end

    /**********************************************************************
     * Stage 4: 최종 출력 레지스터링
     **********************************************************************/
    reg signed [15:0] rPipe4_data_out;

    always @(posedge iClk or negedge iRsn) begin
        if (!iRsn) begin
            rPipe4_valid <= 1'b0;
        end else if (pipe4_ready) begin
            rPipe4_valid <= rPipe3_valid;
            if (rPipe3_valid) begin
                rPipe4_data_out <= rPipe3_data_out;
            end
        end
    end

    // --- 최종 출력 ---
    assign oData  = rPipe4_data_out;  // Q7.8
    assign oValid = rPipe4_valid;

endmodule
