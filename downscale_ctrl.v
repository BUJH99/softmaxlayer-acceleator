// Downscale FSM + 카운터/주소 제어 모듈 (ready 상승엣지 1회당 1전송)
module downscale_ctrl #(
    parameter C_MAX  = 1024,
    parameter ADDR_W = 10          // $clog2(C_MAX)
)(
    input  wire              clk,
    input  wire              rst_n,

    // 입력 스트림 측
    input  wire              in_fire,       // 변환 스트림에서 1샘플 수신 완료 (valid && ready)
    input  wire              in_last,       // 해당 샘플이 벡터 마지막인지 (현재 로직에선 사용 안함)
    input  wire              max_vec_done,  // 최대값 탐색 완료 펄스(마지막 샘플의 다음 클럭)

    // 출력 스트림 측
    input  wire              out_ready,     // 소비자(m_axis_tready)
    output reg               out_valid,
    output reg               out_last,

    // 버퍼 제어 (주소/WE)
    output reg               buf_we,
    output reg [ADDR_W-1:0]  buf_waddr,
    output reg [ADDR_W-1:0]  buf_raddr,

    // 상태/정보
    output reg [ADDR_W:0]    vec_len,       // 현재 벡터 길이
    output reg               reset_xmax     // 새 벡터 시작 시 xmax 초기화 펄스
);
    localparam ST_IDLE = 2'd0,
               ST_LOAD = 2'd1,
               ST_OUT  = 2'd2;

    reg [1:0]      st, nst;
    reg [ADDR_W:0] sent_cnt;     // 지금까지 '전송 완료'한 개수 (이번 싸이클 보낼 인덱스 = sent_cnt)
    //reg            ready_q;      // out_ready 지연 샘플
	reg			   out_valid_q;

    // fire: 전송 후보 / fire_edge: 이번 ready 상승엣지에서의 단 1회 전송 트리거
    wire fire      = out_valid_q && out_ready;
    //wire fire_edge = out_valid && out_ready && !ready_q;

    // 상태 전이
    always @(*) begin
        nst = st;
        case (st)
            ST_IDLE: if (in_fire) nst = ST_LOAD;
            ST_LOAD: if (max_vec_done) nst = ST_OUT;
            ST_OUT : if (out_valid && out_ready && out_last) nst = ST_IDLE;
        endcase
    end

    // 순차 로직
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st         <= ST_IDLE;
            buf_we     <= 1'b0;
            buf_waddr  <= {ADDR_W{1'b0}};
            buf_raddr  <= {ADDR_W{1'b0}};
            vec_len    <= {(ADDR_W+1){1'b0}};
            sent_cnt   <= {(ADDR_W+1){1'b0}};
            out_valid  <= 1'b0;
			out_valid_q <= 1'b0;
            out_last   <= 1'b0;
            reset_xmax <= 1'b1;
            //ready_q    <= 1'b0;
        end else begin
            st      <= nst;
            //ready_q <= out_ready;  // ★ ready 지연 샘플

            // 기본값
            buf_we     <= 1'b0;
            out_valid  <= 1'b0;
			out_valid_q <= 1'b0;
            out_last   <= 1'b0;
            reset_xmax <= 1'b0;

            case (st)
                ST_IDLE: begin
                    buf_waddr  <= 0;
                    buf_raddr  <= 0;
                    vec_len    <= 0;
                    sent_cnt   <= 0;
					//ready_q    <= 1'b0;
                    reset_xmax <= 1'b1; // 새 벡터 시작

                    if (in_fire) begin
                        buf_we    <= 1'b1;
                        buf_waddr <= 0;
                        vec_len   <= 1;
                    end
                end

                ST_LOAD: begin
                    if (in_fire) begin
                        buf_we    <= 1'b1;
                        buf_waddr <= buf_waddr + 1'b1;
                        vec_len   <= vec_len   + 1'b1;
                    end
                end

                ST_OUT: begin
                    // 출력 핸드셰이크
                    out_valid <= 1'b1;
					out_valid_q <= out_valid;
                    // 이번 싸이클에 '보낼' 인덱스가 마지막인가?
                    out_last  <= (sent_cnt == vec_len - 1);

                    // ★ 같은 ready-high 구간에서 1개만 소모
                    if (fire) begin
                        buf_raddr <= buf_raddr + 1'b1;
                        sent_cnt  <= sent_cnt  + 1'b1;
                    end
                end
            endcase
        end
    end
endmodule
