// U0.16 (unsigned 16-bit fractional) -> IEEE-754 single-precision float
module u016_to_fp32 (
    input  wire [15:0] in_u016,   // 0.0000 ~ 0.1111_1111_1111_1111 (U0.16)
    input  wire in_valid,
    output wire [31:0] out_fp32,   // IEEE-754 float
    output wire out_valid
    
);
    // 0 처리
    wire is_zero = (in_u016 == 16'b0);

    // 1) MSB 위치 k (0..15) : function 없이 casez로 우선순위 인코딩
    reg [4:0] k;
    always @* begin
        casez (in_u016)
            16'b1???????????????: k = 5'd15;
            16'b01??????????????: k = 5'd14;
            16'b001?????????????: k = 5'd13;
            16'b0001????????????: k = 5'd12;
            16'b00001???????????: k = 5'd11;
            16'b000001??????????: k = 5'd10;
            16'b0000001?????????: k = 5'd9;
            16'b00000001????????: k = 5'd8;
            16'b000000001???????: k = 5'd7;
            16'b0000000001??????: k = 5'd6;
            16'b00000000001?????: k = 5'd5;
            16'b000000000001????: k = 5'd4;
            16'b0000000000001???: k = 5'd3;
            16'b00000000000001??: k = 5'd2;
            16'b000000000000001?: k = 5'd1;
            16'b0000000000000001: k = 5'd0;
            default:              k = 5'd0; // in_u016 == 0
        endcase
    end

    // 2) 정규화: leading-one을 bit[15]로
    wire [4:0]  shl    = 5'd15 - k;
    wire [15:0] norm16 = in_u016 << shl;   // 비영이면 norm16[15] == 1

    // 3) 지수: E = k + (127 - 16) = k + 111
    wire [7:0] exp_field  = k + 8'd111;

    // 4) 가수: norm16[14:0]을 상위로, 나머지는 0 패딩 (정확 표현)
    wire [22:0] frac_field = { norm16[14:0], 8'b0 };

    // 5) 조립
    assign out_fp32 = is_zero ? 32'b0 : { 1'b0 /*sign*/, exp_field, frac_field };
    assign out_valid = in_valid;

endmodule
