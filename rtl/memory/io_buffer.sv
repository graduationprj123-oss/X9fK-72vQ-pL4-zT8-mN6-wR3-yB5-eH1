// ============================================================================
// io_buffer.sv
// I/O buffer: 512 x 64 bit (keys, ciphertext, seeds, shared secret).
// True dual port, 1-cycle read. Port A = AXI (byte enables), port B = core.
// ============================================================================
module io_buffer (
    input  logic        clk,
    // port A : AXI
    input  logic [7:0]  be_a,
    input  logic [8:0]  addr_a,
    input  logic [63:0] din_a,
    output logic [63:0] dout_a,
    // port B : core
    input  logic        we_b,
    input  logic [8:0]  addr_b,
    input  logic [63:0] din_b,
    output logic [63:0] dout_b
);
    logic [63:0] mem [512];

    always @(posedge clk) begin
        for (int i = 0; i < 8; i++)
            if (be_a[i]) mem[addr_a][8*i +: 8] <= din_a[8*i +: 8];
        dout_a <= mem[addr_a];
    end

    always @(posedge clk) begin
        for (int i = 0; i < 8; i++)
            if (we_b) mem[addr_b][8*i +: 8] <= din_b[8*i +: 8];   // same byte-write style as port A
        dout_b <= mem[addr_b];
    end
endmodule
