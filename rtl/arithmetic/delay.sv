// ============================================================================
// delay.sv
// Shift register: q = d delayed by N clock cycles (N >= 1).
// Used to keep values in step with the multi-cycle multipliers.
// ============================================================================
module delay #(
    parameter int W = 12,     // data width
    parameter int N = 1       // number of cycles
)(
    input  logic         clk,
    input  logic [W-1:0] d,
    output logic [W-1:0] q
);

    logic [W-1:0] r [N];

    always_ff @(posedge clk) begin
        r[0] <= d;
        for (int i = 1; i < N; i++) r[i] <= r[i-1];
    end

    assign q = r[N-1];

endmodule
