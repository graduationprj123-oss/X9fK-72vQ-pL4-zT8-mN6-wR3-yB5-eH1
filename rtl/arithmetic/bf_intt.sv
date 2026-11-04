// ============================================================================
// bf_intt.sv  -  inverse NTT butterfly (Gentleman-Sande), one coefficient pair
//
//     x_o = (x + y) / 2
//     y_o = zeta * (x - y) / 2
//
// The "/2" in each of the 7 layers gives the final 1/128 of the inverse NTT.
//
// Pipeline (BF_LAT = 7 cycles, same for every butterfly unit):
//     cycle 1   : s = x + y , d = x - y
//     cycle 2-4 : p = zeta * d
//     cycle 5   : s / 2 , p / 2
//     cycle 6-7 : wait
// ============================================================================
module bf_intt
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  logic [11:0] x,
    input  logic [11:0] y,
    input  logic [11:0] zeta,
    output logic [11:0] x_o,
    output logic [11:0] y_o
);

    // v / 2 mod q   (if v is odd: (v + q) / 2 = (v >> 1) + 1665)
    function automatic logic [11:0] half(input logic [11:0] v);
        return v[0] ? (12'(v >> 1) + 12'd1665) : 12'(v >> 1);
    endfunction

    logic [11:0] s, d;          // x + y, x - y
    logic [11:0] d_1, zeta_1;   // after cycle 1
    logic [11:0] p;             // zeta * d
    logic [11:0] s_4;           // s, 4 cycles later (arrives together with p)

    // cycle 1
    mod_add u_add (.a(x), .b(y), .c(s));
    mod_sub u_sub (.a(x), .b(y), .c(d));
    delay #(.W(12), .N(1)) u_d    (.clk(clk), .d(d),    .q(d_1));
    delay #(.W(12), .N(1)) u_zeta (.clk(clk), .d(zeta), .q(zeta_1));

    // cycle 2-4
    mod_mul u_mul (.clk(clk), .a(d_1), .b(zeta_1), .t(p));
    delay #(.W(12), .N(4)) u_s (.clk(clk), .d(s), .q(s_4));

    // register (cycle 5) + wait (cycle 6-7)
    delay #(.W(12), .N(3)) u_xo (.clk(clk), .d(half(s_4)), .q(x_o));
    delay #(.W(12), .N(3)) u_yo (.clk(clk), .d(half(p)),   .q(y_o));

endmodule
