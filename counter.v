`timescale 1ns/1ps

module counter #(
    parameter WIDTH = 8,   // 출력 비트폭
    parameter integer CNT_MAX  = 8
)(
    input  wire              clk,    // 클럭
    input  wire              rst_n,  // 비동기 active-low reset
    input  wire              inc,    // 증가 신호
    output reg [WIDTH-1:0]   out     // 카운터 값
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out <= {WIDTH{1'b0}};   // 리셋 시 0으로 초기화
        end else if (inc) begin
             if (out == (CNT_MAX-1)) begin
                out <= 1'b0;
             end else begin
                 out <= out + 1'b1;  // inc=1일 때만 카운트 증가
             end
        end
    end

endmodule