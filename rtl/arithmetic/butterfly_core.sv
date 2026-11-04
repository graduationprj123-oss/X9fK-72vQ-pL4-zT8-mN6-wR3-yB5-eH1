// ============================================================================
// butterfly_core.sv  -  the butterfly unit (BU)
//
// One RAM word holds two coefficients:  din1 = {x1, x0},  din2 = {y1, y0}.
// Every sub-unit gets the same inputs and has the same latency (BF_LAT = 7),
// so this module only has to pick the result of the active operation.
//
//   op    | units used          | dout1 (-> addr1)  | dout2 (-> addr2)
//   ------+---------------------+-------------------+-----------------
//   NTT   | bf_ntt  x2 (lanes)  | {x1', x0'}        | {y1', y0'}
//   INTT  | bf_intt x2 (lanes)  | {x1', x0'}        | {y1', y0'}
//   PWM   | bf_pwm  x1          | {c1, c0}          | -
//   ADD   | bf_addsub x2        | {x1+y1, x0+y0}    | -
//   SUB   | bf_addsub x2        | {x1-y1, x0-y0}    | -
//
// Latency: BU_LAT = 1 (input reg) + BF_LAT + 1 (output reg) = 9 cycles
// ============================================================================
module butterfly_core
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  bu_op_t      op,
    input  logic [23:0] din1,
    input  logic [23:0] din2,
    input  logic [11:0] zeta,
    output logic [23:0] dout1,
    output logic [23:0] dout2
);

    // ---------------- input registers ---------------------------------------
    logic [11:0] x0, x1, y0, y1, z;

    always_ff @(posedge clk) begin
        x0 <= din1[11:0];
        x1 <= din1[23:12];
        y0 <= din2[11:0];
        y1 <= din2[23:12];
        z  <= zeta;
    end

    // ---------------- sub-units ---------------------------------------------
    logic [11:0] ntt_x0,  ntt_y0,  ntt_x1,  ntt_y1;
    logic [11:0] intt_x0, intt_y0, intt_x1, intt_y1;
    logic [11:0] pwm_c0,  pwm_c1;
    logic [11:0] as_z0,   as_z1;

    bf_ntt    u_ntt0  (.clk(clk), .x(x0), .y(y0), .zeta(z), .x_o(ntt_x0),  .y_o(ntt_y0));
    bf_ntt    u_ntt1  (.clk(clk), .x(x1), .y(y1), .zeta(z), .x_o(ntt_x1),  .y_o(ntt_y1));

    bf_intt   u_intt0 (.clk(clk), .x(x0), .y(y0), .zeta(z), .x_o(intt_x0), .y_o(intt_y0));
    bf_intt   u_intt1 (.clk(clk), .x(x1), .y(y1), .zeta(z), .x_o(intt_x1), .y_o(intt_y1));

    bf_pwm    u_pwm   (.clk(clk), .a0(x0), .a1(x1), .b0(y0), .b1(y1), .gamma(z),
                       .c0(pwm_c0), .c1(pwm_c1));

    bf_addsub u_as0   (.clk(clk), .sub(op == BU_SUB), .x(x0), .y(y0), .z(as_z0));
    bf_addsub u_as1   (.clk(clk), .sub(op == BU_SUB), .x(x1), .y(y1), .z(as_z1));

    // ---------------- output select -----------------------------------------
    always_ff @(posedge clk) begin
        case (op)
            BU_NTT:  begin dout1 <= {ntt_x1,  ntt_x0};  dout2 <= {ntt_y1,  ntt_y0};  end
            BU_INTT: begin dout1 <= {intt_x1, intt_x0}; dout2 <= {intt_y1, intt_y0}; end
            BU_PWM:  begin dout1 <= {pwm_c1,  pwm_c0};  dout2 <= '0;                 end
            default: begin dout1 <= {as_z1,   as_z0};   dout2 <= '0;                 end
        endcase
    end

endmodule
