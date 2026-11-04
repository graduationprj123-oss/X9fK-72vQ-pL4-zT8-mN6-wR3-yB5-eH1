// ============================================================================
// bufops.sv
// Buffer operations used by Decaps (Fujisaki-Okamoto check):
//   CMP  : flag = (buffer[la .. la+n-1] != buffer[lb .. lb+n-1])
//   CSEL : buffer[la+i] = flag ? buffer[lb+i] : buffer[la+i]
// Both always touch every lane -> constant time.
// ============================================================================
module bufops
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  opcode_t     opc,          // OP_CMP / OP_CSEL
    input  logic [8:0]  la,
    input  logic [8:0]  lb,
    input  logic [8:0]  n,
    output logic        done,
    // I/O buffer port (1-cycle read latency)
    output logic [8:0]  b_addr,
    output logic        b_we,
    output logic [63:0] b_wdata,
    input  logic [63:0] b_rdata
);

    typedef enum logic [1:0] {B_IDLE, B_RD_A, B_RD_B, B_GOT_B} state_t;

    state_t      state;
    logic        is_cmp;
    logic        flag;
    logic [8:0]  r_la, r_lb, r_n, i;
    logic [63:0] va;

    always_comb begin
        b_addr = r_la + i;
        if (state == B_RD_B) b_addr = r_lb + i;
    end

    // CSEL writes lane A in state B_GOT_B (lane B data valid)
    assign b_we    = (state == B_GOT_B) && !is_cmp;
    assign b_wdata = flag ? b_rdata : va;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= B_IDLE;
            done  <= 1'b0;
            flag  <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                B_IDLE: if (start) begin
                    is_cmp <= (opc == OP_CMP);
                    if (opc == OP_CMP) flag <= 1'b0;
                    r_la  <= la;
                    r_lb  <= lb;
                    r_n   <= n;
                    i     <= '0;
                    state <= B_RD_A;
                end
                B_RD_A:  state <= B_RD_B;          // read A issued
                B_RD_B: begin                       // A data valid, read B issued
                    va    <= b_rdata;
                    state <= B_GOT_B;
                end
                B_GOT_B: begin                      // B data valid
                    if (is_cmp && (va != b_rdata)) flag <= 1'b1;
                    i <= i + 9'd1;
                    if (i == r_n - 9'd1) begin
                        done  <= 1'b1;
                        state <= B_IDLE;
                    end else begin
                        state <= B_RD_A;
                    end
                end
                default: state <= B_IDLE;
            endcase
        end
    end

endmodule
