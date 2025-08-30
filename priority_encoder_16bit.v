/******************************************************************
* 모듈: priority_encoder_16bit (Corrected and Improved)
* 설명: 16비트 입력에서 최상위 비트(MSB)의 위치를 반환하는
*       우선순위 인코더.
*       입력이 0일 경우를 구분하기 위한 zero 플래그 추가.
******************************************************************/
module priority_encoder_16bit (
    input  wire [15:0] in,
    output reg  [3:0]  pos,
    output reg         zero // 추가된 출력: in이 0이면 1, 아니면 0
);

    always @(*) begin
        // 기본값 설정
        pos = 4'd0;
        zero = 1'b1; // 기본적으로 입력이 0이라고 가정

        // casex를 사용하여 MSB 위치 탐색
        // casex는 x(don't care)를 와일드카드로 처리하여 비교
        casex (in)
            16'b1xxx_xxxx_xxxx_xxxx: begin pos = 4'd15; zero = 1'b0; end
            16'b01xx_xxxx_xxxx_xxxx: begin pos = 4'd14; zero = 1'b0; end
            16'b001x_xxxx_xxxx_xxxx: begin pos = 4'd13; zero = 1'b0; end
            16'b0001_xxxx_xxxx_xxxx: begin pos = 4'd12; zero = 1'b0; end
            16'b0000_1xxx_xxxx_xxxx: begin pos = 4'd11; zero = 1'b0; end
            16'b0000_01xx_xxxx_xxxx: begin pos = 4'd10; zero = 1'b0; end
            16'b0000_001x_xxxx_xxxx: begin pos = 4'd9;  zero = 1'b0; end
            16'b0000_0001_xxxx_xxxx: begin pos = 4'd8;  zero = 1'b0; end
            16'b0000_0000_1xxx_xxxx: begin pos = 4'd7;  zero = 1'b0; end
            16'b0000_0000_01xx_xxxx: begin pos = 4'd6;  zero = 1'b0; end
            16'b0000_0000_001x_xxxx: begin pos = 4'd5;  zero = 1'b0; end
            16'b0000_0000_0001_xxxx: begin pos = 4'd4;  zero = 1'b0; end
            16'b0000_0000_0000_1xxx: begin pos = 4'd3;  zero = 1'b0; end
            16'b0000_0000_0000_01xx: begin pos = 4'd2;  zero = 1'b0; end
            16'b0000_0000_0000_001x: begin pos = 4'd1;  zero = 1'b0; end
            16'b0000_0000_0000_0001: begin pos = 4'd0;  zero = 1'b0; end
            default: begin
                pos = 4'd0;   // 입력이 0일 경우 pos는 0
                zero = 1'b1;  // 입력이 0임을 나타내는 플래그는 1
            end
        endcase
    end

endmodule // 