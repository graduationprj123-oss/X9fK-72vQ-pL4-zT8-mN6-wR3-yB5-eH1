// ============================================================================
// bf_addsub.sv  -  coefficient add / subtract
//
//     z = x + y   (sub = 0)
//     z = x - y   (sub = 1)
//
// Pipeline (BF_LAT = 7 cycles, same for every butterfly unit):
//     cycle 1   : x +/- y
//     cycle 2-7 : wait
// ============================================================================
module bf_addsub (
    input  logic        clk,
    input  logic        sub,
    input  logic [11:0] x,
    input  logic [11:0] y,
    output logic [11:0] z
);

    logic [11:0] sum, dif;

    mod_add u_add (.a(x), .b(y), .c(sum));
    mod_sub u_sub (.a(x), .b(y), .c(dif));

    delay #(.W(12), .N(7)) u_z (.clk(clk), .d(sub ? dif : sum), .q(z));

endmodule
