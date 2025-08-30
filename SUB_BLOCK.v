`timescale 1ns/1ps

// Top wrapper that wires: BUFFER + COUNTERs + FSMD(Subtractor)
// Inputs : clk, rst_n,
//          downscale_data_i(16), downscale_data_valid_i,
//          in_data_i(16), in_data_valid_i
// Outputs: data_o(16), data_valid_o
//
// 연결 규칙 (블록도 참조):
//  - Downscale → BUFFER(save)
//  - Ln → FSMD(data2_* 트리거)
//  - FSMD.data1_req → BUFFER.load_en
//  - counter1: Downscale 저장 주소 증가 (addr_i)
//  - counter2: FSMD 처리 수 만큼 증가 → BUFFER.addr_o & FSMD.count_i

module Sub_block #(
    parameter integer CNT_MAX    = 8,       // FSMD 반복 수
    parameter integer ADDR_WIDTH = $clog2(CNT_MAX)                      // buffer depth = 2^
)(
    input  wire         clk,
    input  wire         rst_n,

    // Downscale 쪽 입력 (먼저 끝나는 경로 → 버퍼에 저장)
    input  wire [15:0]  downscale_data_i,
    input  wire         downscale_data_valid_i,
    input  wire         downscale_last_i,

    // Ln 쪽 입력 (나중 도착 → FSMD의 data2_*로 트리거)
    input  wire [15:0]  in_data_i,
    input  wire         in_data_valid_i,
    
    input  wire 		ready,

    // 결과
    output wire [15:0]  data_o,
    output wire         data_valid_o,
    output wire         last
);

    // -------------------------------
    // 내부 배선
    // -------------------------------
    wire                      buf_data_valid;
    wire [15:0]               buf_data_o;

    wire                      fsmd_data1_req;
    wire                      fsmd_outc;

    wire [ADDR_WIDTH-1:0]     cnt1_out;  // write address
    wire [ADDR_WIDTH-1:0]     cnt2_out;  // read address & count_i

    // -------------------------------
    // Counter1 : BUFFER write address
    // inc = downscale_data_valid_i
    // -------------------------------
    counter #(
        .WIDTH(ADDR_WIDTH),
        .CNT_MAX (CNT_MAX)
    ) counter1 (
        .clk (clk),
        .rst_n (rst_n),
        .inc (downscale_data_valid_i),
        .out (cnt1_out)
    );

    // -------------------------------
    // Counter2 : FSMD 진행 카운터
    // inc = fsmd_outc
    // -------------------------------
    counter #(
        .WIDTH(ADDR_WIDTH),
        .CNT_MAX (CNT_MAX)
    ) counter2 (
        .clk (clk),
        .rst_n (rst_n),
        .inc (fsmd_outc),
        .out (cnt2_out)
    );

    // -------------------------------
    // BUFFER
    // - Downscale 결과를 저장 (save_en=valid, addr_i=counter1)
    // - FSMD가 요청(data1_req) 시 읽기 (load_en=data1_req, addr_o=counter2)
    // -------------------------------
    buffer_sync #(
        .DATA_WIDTH(16),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_buffer (
        .clk      (clk),
        .rst_n    (rst_n),

        // write
        .data_i   (downscale_data_i),
        .save_en  (downscale_data_valid_i),
        .addr_i   (cnt1_out),

        // read
        .load_en  (fsmd_data1_req),
        .addr_o   (cnt2_out),

        // outputs to FSMD (as data1 stream)
        .data_valid (buf_data_valid),
        .data_o     (buf_data_o)
    );

    // -------------------------------
    // FSMD (subtractor)
    // - data2_* : Ln 경로 (나중 도착)
    // - data1_* : BUFFER 출력 연결
    // - count_i : counter2 값
    // - outc    : counter2 증가 펄스
    // -------------------------------
    fsmd_subtractor #(
        .SATURATE(1),
        .count_width(ADDR_WIDTH)
    ) u_fsmd (
        .clk        (clk),
        .rst_n      (rst_n),

        // data2 (Ln)
        .data2_en   (in_data_valid_i),
        .data2_i    (in_data_i),

        // data1 (from BUFFER)
        .data1_req  (fsmd_data1_req),
        .data1_en   (buf_data_valid),
        .data1_i    (buf_data_o),

        // external counter feedback (counter2)
        .count_i    (cnt2_out),
        
        .ready      (ready),
        
        .last_count(cnt1_out),
        // results
        .data_o       (data_o),
        .data_valid_o (data_valid_o),
        .outc         (fsmd_outc),
        .last         (last)
    );

endmodule
