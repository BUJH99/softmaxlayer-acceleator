    module line_buffer #(
        parameter C_MAX  = 1024,
        parameter ADDR_W = 10          // $clog2(C_MAX)
    )(
        input  wire              clk,
        // Write
        input  wire              we,
        input  wire [ADDR_W-1:0] waddr,
        input  wire [15:0]       wdata,
        // Read
        input  wire [ADDR_W-1:0] raddr,
        output reg  [15:0]       rdata
    );
        reg [15:0] mem [0:C_MAX-1];
        always @(posedge clk) begin
            if (we) mem[waddr] <= wdata;
            rdata <= mem[raddr];
        end
    endmodule
