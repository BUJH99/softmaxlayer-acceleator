module fp32_to_q78_stream (
    input  wire        clk,
    input  wire        rst_n,

    // s_axis: FP32 in
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tlast,

    // m_axis: Q7.8 out (signed 16-bit)
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg  [15:0] m_axis_tdata,
    output reg         m_axis_tlast
);

    // 출력 버퍼가 비었거나 소비되면 다음 입력 수용
    assign s_axis_tready = (!m_axis_tvalid) || (m_axis_tvalid && m_axis_tready);

    // -------------------------------
    // FP32 -> Q7.8 (직관적 버전)
    //  x = (1.frac) * 2^(exp-127)
    // Q7.8(x) = x * 2^8
    //         = (1.frac * 2^23) * 2^( (exp-127) - 23 + 8 )
    //         = mant * 2^(exp - 142),  where mant = {1,frac} (24-bit)
    // -------------------------------

    reg        sign;
    reg [7:0]  exp;
    reg [22:0] frac;
    reg [23:0] mant;              // 1.frac (정수 24비트)
    integer    k;                  // 시프트 양 = exp - 142
    reg  signed [31:0] shifted;    // 시프트 결과 (중간값)
    reg  signed [31:0] val32;      // 부호 적용 후
    reg  signed [15:0] q78;        // 최종 Q7.8

    // 조합 로직: 읽기 쉬운 순서로 그대로 기술
    always @(*) begin
        // 기본값
        q78     = 16'sd0;
        shifted = 32'sd0;
        val32   = 32'sd0;

        // 비트 분리
        sign = s_axis_tdata[31];
        exp  = s_axis_tdata[30:23];
        frac = s_axis_tdata[22:0];

        // 특수값 처리
        if (exp == 8'hFF) begin
            // Inf/NaN -> 포화
            q78 = sign ? -16'sd32768 : 16'sd32767;

        end else if (exp == 8'd0) begin
            // 0 또는 서브노말 -> 0 근사
            q78 = 16'sd0;

        end else begin
            // 1) mantissa 정수화: 1.frac
            mant = {1'b1, frac}; // 24비트 정수

            // 2) 시프트양: k = exp - 142  (= (exp-127) - 23 + 8)
            k = exp - 142;

            // 3) 한 번만 시프트 (반올림 없이, 직관적으로)
            if (k >= 0)
                shifted = $signed({8'd0, mant}) <<< k;   // 왼쪽 시프트
            else
                shifted = $signed({8'd0, mant}) >>> (-k); // 오른쪽 시프트

            // 4) 부호 적용
            val32 = sign ? -shifted : shifted;

            // 5) 16-bit 포화
            if      (val32 >  32'sd32767)  q78 = 16'sd32767;
            else if (val32 < -32'sd32768)  q78 = -16'sd32768;
            else                           q78 = val32[15:0];
        end
    end

    // 출력 레지스터 (간단 1-stage 파이프라인)
    wire fire = s_axis_tvalid && s_axis_tready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= 16'd0;
            m_axis_tlast  <= 1'b0;
        end else if (!m_axis_tvalid || m_axis_tready) begin
            m_axis_tvalid <= fire;
            m_axis_tdata  <= q78;
            m_axis_tlast  <= s_axis_tlast;
        end
    end

endmodule