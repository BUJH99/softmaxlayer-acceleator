module max_detector (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reset_vec,   // ★ 벡터 시작용 리셋 추가

    input  wire        in_valid,
    input  wire [15:0] in_data,
    input  wire        in_last,
    output wire        in_ready,

    output reg         vec_done,
    output reg  [15:0] xmax_q78
);
    assign in_ready = 1'b1;
    localparam signed [15:0] SNEG_INF = 16'sh8000;
    wire signed [15:0] sdata = in_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xmax_q78 <= SNEG_INF;
            vec_done <= 1'b0;
        end else begin
            // ★ 벡터 시작 시마다 최대값 초기화
            if (reset_vec) begin
                xmax_q78 <= SNEG_INF;
            end

            vec_done <= 1'b0;
            if (in_valid) begin
                if (sdata > $signed(xmax_q78)) xmax_q78 <= sdata;
                if (in_last) vec_done <= 1'b1;
            end
        end
    end
endmodule
