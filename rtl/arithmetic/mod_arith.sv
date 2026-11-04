// ============================================================================
// mod_arith.sv
// Arithmetic modulo q = 3329. Inputs are always in [0, q-1].
// ============================================================================

// c = (a + b) mod q   (combinational)
module mod_add (
    input  logic [11:0] a,
    input  logic [11:0] b,
    output logic [11:0] c
);
    logic [12:0] s;
    logic [13:0] r;
    assign s = {1'b0, a} + {1'b0, b};
    assign r = {1'b0, s} - 14'd3329;
    assign c = r[13] ? s[11:0] : r[11:0];       // s < q  ->  keep s
endmodule

// c = (a - b) mod q   (combinational)
module mod_sub (
    input  logic [11:0] a,
    input  logic [11:0] b,
    output logic [11:0] c
);
    logic [12:0] d;
    logic [12:0] r;
    assign d = {1'b0, a} - {1'b0, b};
    assign r = d + 13'd3329;
    assign c = d[12] ? r[11:0] : d[11:0];       // negative -> add q
endmodule

// t = (a * b) mod q, Barrett reduction, 3-cycle latency
//   cycle 1 : p = a * b
//   cycle 2 : e = floor(p * 5039 / 2^24)   (estimate of p / q, error <= 1)
//   cycle 3 : t = p - e*q, then one conditional subtraction
module mod_mul (
    input  logic        clk,
    input  logic [11:0] a,
    input  logic [11:0] b,
    output logic [11:0] t
);
    logic [23:0] p1, p2;
    logic [11:0] e2;
    logic [37:0] pm;
    logic [13:0] r;
    logic [14:0] rq;

    assign pm = p1 * 14'd5039;
    assign r  = 14'(p2 - e2 * 12'd3329);        // r in [0, 2q)
    assign rq = {1'b0, r} - 15'd3329;

    always_ff @(posedge clk) begin
        p1 <= a * b;
        p2 <= p1;
        e2 <= pm[35:24];
        t  <= rq[14] ? r[11:0] : rq[11:0];
    end
endmodule
