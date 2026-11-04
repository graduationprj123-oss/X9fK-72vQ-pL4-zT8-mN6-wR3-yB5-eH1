// ============================================================================
// bf_ntt.sv  -  NTT butterfly (Cooley-Tukey), one coefficient pair
//
//     x_o = x + zeta * y
//     y_o = x - zeta * y
//
// Pipeline (BF_LAT = 7 cycles, same for every butterfly unit):
//     cycle 1-3 : t = zeta * y
//     cycle 4   : x + t , x - t
//     cycle 5-7 : wait
// ============================================================================
module bf_ntt
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  logic [11:0] x,
    input  logic [11:0] y,
    input  logic [11:0] zeta,
    output logic [11:0] x_o,
    output logic [11:0] y_o
);

    logic [11:0] t;        // zeta * y
    logic [11:0] x_3;      // x, 3 cycles later (arrives together with t)
    logic [11:0] sum, dif;

    // cycle 1-3
    mod_mul u_mul (.clk(clk), .a(y), .b(zeta), .t(t));
    delay #(.W(12), .N(3)) u_x (.clk(clk), .d(x), .q(x_3));

    // cycle 4
    mod_add u_add (.a(x_3), .b(t), .c(sum));
    mod_sub u_sub (.a(x_3), .b(t), .c(dif));

    // register (cycle 4) + wait (cycle 5-7)
    delay #(.W(12), .N(4)) u_xo (.clk(clk), .d(sum), .q(x_o));
    delay #(.W(12), .N(4)) u_yo (.clk(clk), .d(dif), .q(y_o));

endmodule
