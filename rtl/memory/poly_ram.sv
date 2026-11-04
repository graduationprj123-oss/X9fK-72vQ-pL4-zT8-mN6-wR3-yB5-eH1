// ============================================================================
// poly_ram.sv
// Polynomial RAM: 16 slots x 128 words x 24 bit (2 coefficients per word).
// True dual port, 2-cycle read latency (output register). Infers BRAM.
// ============================================================================
module poly_ram (
    input  logic        clk,
    input  logic        we_a,
    input  logic [10:0] addr_a,
    input  logic [23:0] din_a,
    output logic [23:0] dout_a,
    input  logic        we_b,
    input  logic [10:0] addr_b,
    input  logic [23:0] din_b,
    output logic [23:0] dout_b
);
    logic [23:0] mem [2048];
    logic [23:0] qa, qb;

    // plain 'always': 'mem' is written from two processes (TDP template)
    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= din_a;
        qa     <= mem[addr_a];
        dout_a <= qa;                    // output register (DOA_REG)
    end

    always @(posedge clk) begin
        if (we_b) mem[addr_b] <= din_b;
        qb     <= mem[addr_b];
        dout_b <= qb;                    // output register (DOB_REG)
    end
endmodule
