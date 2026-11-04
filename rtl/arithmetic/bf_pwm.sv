// ============================================================================
// bf_pwm.sv  -  pointwise multiply in the NTT domain (BaseCaseMultiply)
//
//     (a0 + a1 X) * (b0 + b1 X)  mod (X^2 - gamma)
//     c0 = a0*b0 + a1*b1*gamma
//     c1 = a0*b1 + a1*b0
//
// Karatsuba trick: c1 = (a0 + a1)(b0 + b1) - a0*b0 - a1*b1
//
// Pipeline (BF_LAT = 7 cycles, same for every butterfly unit):
//     cycle 1-3 : m0 = a0*b0 , m1 = a1*b1
//     cycle 4-6 : k  = (a0+a1)*(b0+b1) , g = m1*gamma
//     cycle 7   : c0 = m0 + g , c1 = k - (m0 + m1)
// ============================================================================
module bf_pwm
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  logic [11:0] a0,
    input  logic [11:0] a1,
    input  logic [11:0] b0,
    input  logic [11:0] b1,
    input  logic [11:0] gamma,
    output logic [11:0] c0,
    output logic [11:0] c1
);

    logic [11:0] m0, m1;              // a0*b0, a1*b1                 (after cycle 3)
    logic [11:0] sa, sb;              // a0+a1, b0+b1
    logic [11:0] sa_3, sb_3, gamma_3; // ... 3 cycles later
    logic [11:0] k, g;                // (a0+a1)(b0+b1), m1*gamma     (after cycle 6)
    logic [11:0] m01;                 // m0 + m1
    logic [11:0] m0_6, m01_6;         // ... 3 cycles later
    logic [11:0] c0_w, c1_w;

    // cycle 1-3
    mod_mul u_m0 (.clk(clk), .a(a0), .b(b0), .t(m0));
    mod_mul u_m1 (.clk(clk), .a(a1), .b(b1), .t(m1));

    mod_add u_sa (.a(a0), .b(a1), .c(sa));
    mod_add u_sb (.a(b0), .b(b1), .c(sb));
    delay #(.W(12), .N(3)) u_sa3 (.clk(clk), .d(sa),    .q(sa_3));
    delay #(.W(12), .N(3)) u_sb3 (.clk(clk), .d(sb),    .q(sb_3));
    delay #(.W(12), .N(3)) u_g3  (.clk(clk), .d(gamma), .q(gamma_3));

    // cycle 4-6
    mod_mul u_k (.clk(clk), .a(sa_3), .b(sb_3),    .t(k));
    mod_mul u_g (.clk(clk), .a(m1),   .b(gamma_3), .t(g));

    mod_add u_m01 (.a(m0), .b(m1), .c(m01));
    delay #(.W(12), .N(3)) u_m0_6  (.clk(clk), .d(m0),  .q(m0_6));
    delay #(.W(12), .N(3)) u_m01_6 (.clk(clk), .d(m01), .q(m01_6));

    // cycle 7
    mod_add u_c0 (.a(m0_6), .b(g),     .c(c0_w));
    mod_sub u_c1 (.a(k),    .b(m01_6), .c(c1_w));
    delay #(.W(12), .N(1)) u_c0o (.clk(clk), .d(c0_w), .q(c0));
    delay #(.W(12), .N(1)) u_c1o (.clk(clk), .d(c1_w), .q(c1));

endmodule
