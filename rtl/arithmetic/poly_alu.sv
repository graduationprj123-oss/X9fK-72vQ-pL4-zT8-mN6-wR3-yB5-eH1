// ============================================================================
// poly_alu.sv
// Polynomial arithmetic with ONE butterfly unit, working in place on poly RAM.
//   NTT / INTT : 7 layers x 64 word-pairs
//   PWM / ADD / SUB : 128 words, sd = sa (op) sb
//
// Both RAM ports are used: a read pair is issued every other cycle (phase 0);
// results come back ALU_LAT (odd) cycles later and are written on phase 1,
// so reads and writes never collide on a port. Between NTT layers the
// pipeline is drained.
// ============================================================================
module poly_alu
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  opcode_t     opc,          // OP_NTT / OP_INTT / OP_PWM / OP_ADD / OP_SUB
    input  logic [3:0]  sa,
    input  logic [3:0]  sb,
    input  logic [3:0]  sd,
    output logic        done,
    // poly RAM, port A / port B
    output logic        pa_we,
    output logic [10:0] pa_addr,
    output logic [23:0] pa_din,
    input  logic [23:0] pa_dout,
    output logic        pb_we,
    output logic [10:0] pb_addr,
    output logic [23:0] pb_din,
    input  logic [23:0] pb_dout
);

    typedef enum logic [1:0] {A_IDLE, A_ISSUE, A_DRAIN} state_t;

    state_t      state;
    bu_op_t      bu_op;
    logic        is_bf;                 // NTT or INTT
    logic        is_intt;
    logic [3:0]  r_sa, r_sb, r_sd;
    logic [2:0]  layer;
    logic [6:0]  cnt;
    logic        phase;
    logic [3:0]  drain_cnt;

    // ---------------- address generation -----------------------------------
    logic [2:0]  shift;                 // log2(len), len in words
    logic [6:0]  len, j, jp;
    logic [7:0]  k;
    logic        issue, last_issue;
    logic [10:0] rd_a1, rd_a2, wr_a1;

    assign shift = is_intt ? layer : 3'(3'd6 - layer);
    assign len   = 7'd1 << shift;
    // butterfly index -> j : insert a zero bit at position 'shift'
    assign j     = ((cnt & ~(len - 7'd1)) << 1) | (cnt & (len - 7'd1));
    assign jp    = j | len;
    assign k     = is_intt ? (8'd129 - (8'd128 >> shift) + (8'(cnt) >> shift))
                           : ((8'd64 >> shift) + (8'(cnt) >> shift));

    assign issue      = (state == A_ISSUE) && !phase;
    assign last_issue = is_bf ? (cnt == 7'd63) : (cnt == 7'd127);

    assign rd_a1 = is_bf ? {r_sd, j}  : {r_sa, cnt};
    assign rd_a2 = is_bf ? {r_sd, jp} : {r_sb, cnt};
    assign wr_a1 = is_bf ? {r_sd, j}  : {r_sd, cnt};

    // ---------------- control ----------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= A_IDLE;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                A_IDLE: if (start) begin
                    r_sa      <= sa;
                    r_sb      <= sb;
                    r_sd      <= sd;
                    is_bf     <= (opc == OP_NTT) || (opc == OP_INTT);
                    is_intt   <= (opc == OP_INTT);
                    case (opc)
                        OP_NTT:  bu_op <= BU_NTT;
                        OP_INTT: bu_op <= BU_INTT;
                        OP_PWM:  bu_op <= BU_PWM;
                        OP_ADD:  bu_op <= BU_ADD;
                        default: bu_op <= BU_SUB;
                    endcase
                    layer     <= '0;
                    cnt       <= '0;
                    phase     <= 1'b0;
                    state     <= A_ISSUE;
                end
                A_ISSUE: begin
                    phase <= ~phase;
                    if (issue) begin
                        cnt <= cnt + 7'd1;
                        if (last_issue) begin
                            cnt       <= '0;
                            drain_cnt <= '0;
                            state     <= A_DRAIN;
                        end
                    end
                end
                A_DRAIN: begin           // wait until the last write is done
                    drain_cnt <= drain_cnt + 4'd1;
                    if (drain_cnt == 4'(ALU_LAT - 1)) begin
                        phase <= 1'b0;
                        if (is_bf && layer != 3'd6) begin
                            layer <= layer + 3'd1;
                            state <= A_ISSUE;
                        end else begin
                            done  <= 1'b1;
                            state <= A_IDLE;
                        end
                    end
                end
                default: state <= A_IDLE;
            endcase
        end
    end

    // ---------------- write-back delay line --------------------------------
    logic        wv1_d [ALU_LAT];
    logic        wv2_d [ALU_LAT];
    logic [10:0] wa1_d [ALU_LAT];
    logic [10:0] wa2_d [ALU_LAT];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < ALU_LAT; i++) begin
                wv1_d[i] <= 1'b0;
                wv2_d[i] <= 1'b0;
            end
        end else begin
            wv1_d[0] <= issue;
            wv2_d[0] <= issue && is_bf;
            for (int i = 1; i < ALU_LAT; i++) begin
                wv1_d[i] <= wv1_d[i-1];
                wv2_d[i] <= wv2_d[i-1];
            end
        end
    end

    always_ff @(posedge clk) begin
        wa1_d[0] <= wr_a1;
        wa2_d[0] <= rd_a2;
        for (int i = 1; i < ALU_LAT; i++) begin
            wa1_d[i] <= wa1_d[i-1];
            wa2_d[i] <= wa2_d[i-1];
        end
    end

    // ---------------- twiddles + BU ----------------------------------------
    logic [35:0] zeta_w;
    logic [11:0] zeta;
    zeta_rom u_zeta (.clk(clk), .addr(is_bf ? k[6:0] : cnt), .zeta_q(zeta_w));

    always_comb begin
        case (bu_op)
            BU_NTT:  zeta = zeta_w[11:0];
            BU_INTT: zeta = zeta_w[23:12];
            default: zeta = zeta_w[35:24];
        endcase
    end

    logic [23:0] bu_o1, bu_o2;
    butterfly_core u_bu (
        .clk   (clk),
        .op    (bu_op),
        .din1  (pa_dout),
        .din2  (pb_dout),
        .zeta  (zeta),
        .dout1 (bu_o1),
        .dout2 (bu_o2)
    );

    // ---------------- RAM ports --------------------------------------------
    assign pa_we   = wv1_d[ALU_LAT-1];
    assign pb_we   = wv2_d[ALU_LAT-1];
    assign pa_addr = pa_we ? wa1_d[ALU_LAT-1] : rd_a1;
    assign pb_addr = pb_we ? wa2_d[ALU_LAT-1] : rd_a2;
    assign pa_din  = bu_o1;
    assign pb_din  = bu_o2;

endmodule
