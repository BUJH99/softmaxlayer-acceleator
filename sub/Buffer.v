`timescale 1ns/1ps
// Parameterized Buffer
// - Single clock, synchronous write
// - 1-cycle registered read (data_valid marks valid cycle)
// - Active-low reset (rst_n)

module buffer_sync #(
    parameter integer DATA_WIDTH = 16,
    parameter integer ADDR_WIDTH = 8              // depth = 2^ADDR_WIDTH
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // write port
    input  wire [DATA_WIDTH-1:0]      data_i,
    input  wire                       save_en,
    input  wire [ADDR_WIDTH-1:0]      addr_i,

    // read port
    input  wire                       load_en,
    input  wire [ADDR_WIDTH-1:0]      addr_o,

    // outputs
    output reg                        data_valid,
    output reg  [DATA_WIDTH-1:0]      data_o
);

    localparam integer DEPTH = (1 << ADDR_WIDTH);

    // Memory array
    // Xilinx: add ram_style = "block" if BRAM 유도 원하면 주석 해제
    // (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Write port (sync)
    always @(posedge clk) begin
        if (!rst_n) begin
            // 메모리 내용은 보통 리셋하지 않음 (대부분의 RAM primitive가 미지원)
        end else if (save_en) begin
            mem[addr_i] <= data_i;
        end
    end

    // Read address capture
    always @(posedge clk) begin
        if (!rst_n) begin
            data_valid<= 1'b0;
            data_o    <= {DATA_WIDTH{1'b0}};
        end else begin
            // 다음 사이클에 data_valid를 해당 요청에 맞춰 갱신
            data_valid <= load_en;

            // 1-cycle 지연 데이터 출력
            // RAW(read-after-write) 같은 주소 동시 접근 시 갓 쓴 값이 보이도록 우선순위 부여
            // (동일 클럭에 write&read가 교차할 경우, 많은 FPGA가 "write-first" 모드로 추론되도록 아래와 같이 처리)
            if (load_en) begin
                if (save_en && (addr_i == addr_o)) begin
                    // 동일 사이클 write/read 같은 주소: write-through
                    data_o <= data_i;
                end else begin
                    data_o <= mem[addr_o];
                end
            end
        end
    end

endmodule
