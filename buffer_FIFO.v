`timescale 1ns/1ps
`default_nettype none

module buffer_FIFO #(
  parameter integer DEPTH  = 64,                       // 최대 수신 길이
  parameter integer ADDR_W = $clog2(DEPTH)
)(
  input  wire         clk,
  input  wire         rst_n,

  // 전단 입력 (수집 단계)
  input  wire         s_valid_i,
  input  wire [31:0]  s_data_i,
  input  wire         s_last_i,      // 이 입력까지 포함해서 저장

  output wire         s_ready_o,     // 수집 단계에서만 1(=수신 가능)

  // 후단 출력 (드레인 단계)
  input  wire         m_ready_i,     // 1일 때만 한 항목씩 내보냄
  output reg          m_valid_o,     // 반드시 1사이클 펄스
  output reg  [31:0]  m_data_o
);

  // 내부 FIFO 메모리
  reg [31:0] fifo_mem [0:DEPTH-1];

  reg [ADDR_W-1:0] wr_ptr;
  reg [ADDR_W-1:0] rd_ptr;
  reg [ADDR_W:0]   count;    // 0..DEPTH

  localparam ST_COLLECT = 2'b00;
  localparam ST_DRAIN   = 2'b01;
  localparam REST   = 2'b10;
  reg [1:0]    state;

  // 전단 수신 가능 조건: 수집 단계 & not full
  wire fifo_full  = (count == DEPTH[ADDR_W:0]);
  wire fifo_empty = (count == { (ADDR_W+1){1'b0} });
  assign s_ready_o = (state == ST_COLLECT) && !fifo_full;

  // 수집: s_valid & s_ready 에서만 수신
  wire take_in  = s_valid_i && s_ready_o;

  // 드레인: ready가 1일 때만 내보내며 valid를 1사이클 펄스
  wire give_out = (state == ST_DRAIN) && m_ready_i && !fifo_empty;

  // 상태/포인터/카운트/메모리
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= ST_COLLECT;
      wr_ptr       <= {ADDR_W{1'b0}};
      rd_ptr       <= {ADDR_W{1'b0}};
      count        <= {(ADDR_W+1){1'b0}};
      m_valid_o    <= 1'b0;
      m_data_o     <= 32'd0;
      // 메모리 초기화는 필수 아님(하드웨어에선 don't-care)
    end else begin
      // 기본값
      m_valid_o <= 1'b0; // 펄스 보장

      case (state)
        // -----------------------------
        // 수집 단계: last 포함해 저장
        // -----------------------------
        ST_COLLECT: begin

          if (take_in) begin
            // write
            fifo_mem[wr_ptr] <= s_data_i;
            wr_ptr <= (wr_ptr == DEPTH-1) ? {ADDR_W{1'b0}} : (wr_ptr + 1'b1);
            count  <= count + 1'b1;

            // 마지막 입력을 저장했으면 다음 싸이클부터 드레인으로 전환
            if (s_last_i) begin
              state        <= ST_DRAIN;
            end
          end
        end

        // -----------------------------
        // 드레인 단계: ready가 1일 때마다 1개씩, valid는 1사이클
        // -----------------------------
        ST_DRAIN: begin

          if (give_out) begin
            // 현재 rd_ptr 위치를 즉시 출력(조합 읽기)
            m_data_o  <= fifo_mem[rd_ptr];
            m_valid_o <= 1'b1; // 1사이클 펄스

            // pop
            rd_ptr <= (rd_ptr == DEPTH-1) ? {ADDR_W{1'b0}} : (rd_ptr + 1'b1);
            count  <= count - 1'b1;

            // 마지막을 내보냈다면 다음 싸이클부터 수집으로
            if (count == 1) begin
              // count가 1이면 이번 pop 후 0이 됨
              state      <= ST_COLLECT;
              wr_ptr     <= {ADDR_W{1'b0}};    // 다음 패킷을 위해 포인터/카운트 리셋
              rd_ptr     <= {ADDR_W{1'b0}};
            end
            else state <= REST;
          end
        end
      REST: state <= ST_DRAIN;
      endcase
    end
  end

endmodule

`default_nettype wire
