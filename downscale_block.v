module downscale_block #(
    parameter C_MAX   = 1024,
    parameter ADDR_W  = 10
)(
    input  wire         clk,
    input  wire         rst_n,

    // FP32 입력 스트림
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    input  wire [31:0]  s_axis_tdata,
    input  wire         s_axis_tlast,

    // Q7.8 출력 스트림: (Xi - Xmax)
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire [15:0]  m_axis_tdata,
    output wire         m_axis_tlast
);
    // 1) FP32 -> Q7.8
    wire         c_valid;
    wire [15:0]  c_data;
    wire         c_last;
	wire accept_conv = ~out_valid_i;  // 입력 벡터 처리 후 출력중일 땐 출력 x

    fp32_to_q78_stream u_conv (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tvalid(c_valid),
        .m_axis_tready(accept_conv),       // 1'b1 -> ~out_valid_i
        .m_axis_tdata(c_data),
        .m_axis_tlast(c_last)
    );

    // 2) MAX DETECTOR (입력과 동시에 1패스)
    wire        md_done;
    wire [15:0] md_xmax;

    max_detector u_max (
        .clk(clk), .rst_n(rst_n),
		.reset_vec(reset_xmax),
        .in_valid(c_valid),
        .in_data(c_data),
        .in_last(c_last),
        .in_ready(),                // 사용 안함
        .vec_done(md_done),
        .xmax_q78(md_xmax)
    );

    // 3) BUFFER
    wire             buf_we;
    wire [ADDR_W-1:0] buf_waddr, buf_raddr;
    wire [15:0]       buf_rdata;
    wire [ADDR_W:0]   vec_len;

    line_buffer #(.C_MAX(C_MAX), .ADDR_W(ADDR_W)) u_buf (
        .clk(clk),
        .we(buf_we),
        .waddr(buf_waddr),
        .wdata(c_data),
        .raddr(buf_raddr),
        .rdata(buf_rdata)
    );

    // 4) FSM (모듈)
    wire out_valid_i, out_last_i, reset_xmax;

    downscale_ctrl #(.C_MAX(C_MAX), .ADDR_W(ADDR_W)) u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .in_fire(c_valid),
        .in_last(c_last),
        .max_vec_done(md_done),      // 마지막 샘플에서 확정 펄스
        .out_ready(m_axis_tready),
        .out_valid(out_valid_i),
        .out_last(out_last_i),
        .buf_we(buf_we),
        .buf_waddr(buf_waddr),
        .buf_raddr(buf_raddr),
        .vec_len(vec_len),
        .reset_xmax(reset_xmax)
    );

    // 5) Xmax 래치 (★ 중복 제거: max_detector 결과만 사용)
    reg  [15:0] xmax_q78;
    localparam signed [15:0] SNEG_INF = 16'sh8000;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xmax_q78 <= SNEG_INF;
        end else if (reset_xmax) begin
            // 새 벡터 시작: 초기화
            xmax_q78 <= SNEG_INF;
        end else if (md_done) begin
            // 벡터 끝에서 확정된 최대값을 래치
            xmax_q78 <= md_xmax;
        end
        // 그 외에는 유지(OUT 단계 동안 고정)
    end

    // 6) Subtractor (탑 내부, 포화)
    wire signed [15:0] s_xi   = buf_rdata;
    wire signed [15:0] s_xmax = xmax_q78;
    wire signed [16:0] sdiff  = s_xi - s_xmax;

    reg		   out_last_q, out_valid_q;
    reg [15:0] diff_q78_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_last_q  <= 1'b0;
            diff_q78_r  <= 16'd0;
			out_valid_q <= 1'b0;
        end else begin
            if (out_valid_i) begin
                if      (sdiff >  17'sd32767) diff_q78_r <= 16'sd32767;
                else if (sdiff < -17'sd32768) diff_q78_r <= -16'sd32768;
                else                          diff_q78_r <= sdiff[15:0];
            end
            out_last_q <= out_last_i;
			out_valid_q <= out_valid_i;
        end
    end

    assign m_axis_tdata  = diff_q78_r;
	assign m_axis_tlast  = out_last_q;
	
	// (기존 레지스터 out_valid_q/out_last_q 제거)
	assign m_axis_tvalid = out_valid_q;
	

endmodule
