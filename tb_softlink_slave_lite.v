`timescale 1ns/1ps

module tb_softlink_slave_lite;

  // ───────────────────────────────── Clock / Reset ───────────────────────────
  reg S_AXI_ACLK;
  reg S_AXI_ARESETN;

  initial begin
    S_AXI_ACLK = 1'b0;
    forever #5 S_AXI_ACLK = ~S_AXI_ACLK; // 100MHz 클럭 생성
  end

  initial begin
    S_AXI_ARESETN = 1'b0;
    repeat (10) @(posedge S_AXI_ACLK); // 10 클럭 사이클 동안 리셋 유지
    S_AXI_ARESETN = 1'b1;
  end

  // ──────────────────────────────── AXI-Lite I/F ─────────────────────────────
  // Write Channel
  reg  [3:0]  S_AXI_AWADDR;
  reg  [2:0]  S_AXI_AWPROT;
  reg         S_AXI_AWVALID;
  wire        S_AXI_AWREADY;
  reg  [31:0] S_AXI_WDATA;
  reg  [3:0]  S_AXI_WSTRB;
  reg         S_AXI_WVALID;
  wire        S_AXI_WREADY;
  wire [1:0]  S_AXI_BRESP;
  wire        S_AXI_BVALID;
  reg         S_AXI_BREADY;

  // Read Channel (Unused in this test)
  reg  [3:0]  S_AXI_ARADDR;
  reg  [2:0]  S_AXI_ARPROT;
  reg         S_AXI_ARVALID;
  wire        S_AXI_ARREADY;
  wire [31:0] S_AXI_RDATA;
  wire [1:0]  S_AXI_RRESP;
  wire        S_AXI_RVALID;
  reg         S_AXI_RREADY;

  // ─────────────────────────────────── DUT ───────────────────────────────────
  softlink_slave_lite_v1_0_S00_AXI dut (
    .S_AXI_ACLK   (S_AXI_ACLK),
    .S_AXI_ARESETN(S_AXI_ARESETN),

    .S_AXI_AWADDR (S_AXI_AWADDR),
    .S_AXI_AWPROT (S_AXI_AWPROT),
    .S_AXI_AWVALID(S_AXI_AWVALID),
    .S_AXI_AWREADY(S_AXI_AWREADY),

    .S_AXI_WDATA  (S_AXI_WDATA),
    .S_AXI_WSTRB  (S_AXI_WSTRB),
    .S_AXI_WVALID (S_AXI_WVALID),
    .S_AXI_WREADY (S_AXI_WREADY),

    .S_AXI_BRESP  (S_AXI_BRESP),
    .S_AXI_BVALID (S_AXI_BVALID),
    .S_AXI_BREADY (S_AXI_BREADY),

    .S_AXI_ARADDR (S_AXI_ARADDR),
    .S_AXI_ARPROT (S_AXI_ARPROT),
    .S_AXI_ARVALID(S_AXI_ARVALID),
    .S_AXI_ARREADY(S_AXI_ARREADY),

    .S_AXI_RDATA  (S_AXI_RDATA),
    .S_AXI_RRESP  (S_AXI_RRESP),
    .S_AXI_RVALID (S_AXI_RVALID),
    .S_AXI_RREADY (S_AXI_RREADY)
  );

  // ───────────────────────────── Stimulus 패턴 ───────────────────────────────
  initial begin
    // 신호 초기화
    S_AXI_AWADDR  = 4'h0;
    S_AXI_AWPROT  = 3'b0;
    S_AXI_AWVALID = 1'b0;
    S_AXI_WDATA   = 32'h0;
    S_AXI_WSTRB   = 4'hF;
    S_AXI_WVALID  = 1'b0;
    S_AXI_BREADY  = 1'b0;
    S_AXI_ARADDR  = 4'h0;
    S_AXI_ARPROT  = 3'b0;
    S_AXI_ARVALID = 1'b0;
    S_AXI_RREADY  = 1'b0;

    // 리셋 해제 대기
    @(posedge S_AXI_ARESETN);
    repeat (2) @(posedge S_AXI_ACLK);

    // ===================== 조건부 쓰기 신호 전송 =====================
    for (integer i = 0; i < (4*30); i = i + 1) begin
      
      // *** 핵심 수정: 주소값이 0이 될 경우에만 트랜잭션을 시작 ***
      if ((i * 4) % 16 == 0) begin
        $display("[%0t] TB: 주소가 0이므로 쓰기 시작 (Transaction #%0d)...", $time, i);

        // 1. 주소 단계 (Address Phase)
        S_AXI_AWADDR  <= 0; // 조건이 참이므로 주소는 항상 0
        S_AXI_AWVALID <= 1'b1;

        // AWREADY가 1이 될 때까지 대기
        @(posedge S_AXI_ACLK);
        while (!S_AXI_AWREADY) begin
          @(posedge S_AXI_ACLK);
        end
        S_AXI_AWVALID <= 1'b0;

        // 2. 데이터 단계 (Data Phase)
        S_AXI_WDATA   <= 32'h40800000 + (i<<15);
        S_AXI_WSTRB   <= 4'hF;
        S_AXI_WVALID  <= 1'b1;
        S_AXI_BREADY  <= 1'b1;

        // WREADY가 1이 될 때까지 대기
        @(posedge S_AXI_ACLK);
        while (!S_AXI_WREADY) begin
          @(posedge S_AXI_ACLK);
        end
        S_AXI_WVALID  <= 1'b0;

        // 3. 응답 단계 (Response Phase)
        while (!S_AXI_BVALID) begin
          @(posedge S_AXI_ACLK);
        end
        @(posedge S_AXI_ACLK);
        S_AXI_BREADY  <= 1'b0;

        // 다음 트랜잭션 전 지연
        repeat(2) @(posedge S_AXI_ACLK);
      end else begin
        // 주소가 0이 아닐 경우, 아무 동작도 하지 않고 넘어감
        $display("[%0t] TB: 주소가 0이 아니므로 건너뜀 (Transaction #%0d).", $time, i);
        @(posedge S_AXI_ACLK);
      end
    end

    // 시뮬레이션 종료
    $display("[%0t] TB: 모든 조건부 신호 전송 완료. 시뮬레이션을 종료합니다.", $time);
    repeat (10) @(posedge S_AXI_ACLK);
  end

  // ───────────────────────── 파형/모니터(선택) ───────────────────────────────
  initial begin
    $dumpfile("waveform_conditional_writes.vcd");
    $dumpvars(0, tb_softlink_slave_lite);
  end

endmodule