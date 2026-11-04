// ============================================================================
// sponge.sv
// SHA3-256 / SHA3-512 / SHAKE128 / SHAKE256 sponge on top of Keccak-f[1600].
// Driven by micro-instructions:
//   HINIT   (imm = mode)  : clear state
//   ABSORB  (la, n)       : XOR n lanes from the I/O buffer (lane-aligned data)
//   FINAL   (n, imm)      : XOR n (0..2) tail bytes + domain/pad, permute
//   SQUEEZE (la, n)       : write n lanes to the I/O buffer
// After FINAL the sponge also serves a byte stream (for the samplers) while
// stream_en = 1, permuting whenever the rate is exhausted.
// ============================================================================
module sponge
    import mlkem_pkg::*;
    import keccak_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  opcode_t     opc,
    input  logic [8:0]  la,
    input  logic [8:0]  n,
    input  logic [15:0] imm,
    output logic        done,
    // I/O buffer (1-cycle read latency)
    output logic [8:0]  b_addr,
    output logic        b_we,
    output logic [63:0] b_wdata,
    input  logic [63:0] b_rdata,
    // byte stream to the samplers
    input  logic        stream_en,
    output logic [7:0]  s_byte,
    output logic        s_valid,
    input  logic        s_ready
);

    typedef enum logic [2:0] {S_IDLE, S_ABS_RD, S_ABS_XOR, S_SQ, S_PERM} state_t;
    typedef enum logic [1:0] {R_IDLE, R_DONE, R_ABS, R_SQ} ret_t;

    state_t      state;
    ret_t        ret;
    lanes_t      st;
    logic [4:0]  rate;          // rate in lanes: 9 / 17 / 21
    logic [7:0]  suffix;        // 0x06 (SHA3) or 0x1F (SHAKE)
    logic [4:0]  pos;           // absorb lane position
    logic [7:0]  sq;            // squeeze byte position
    logic [8:0]  cnt, r_n, r_la;
    logic [4:0]  rnd;

    logic        sq_empty;
    logic [63:0] sq_lane;
    logic [63:0] tail_word;

    assign sq_empty  = (sq == {rate, 3'b000});
    assign sq_lane   = st[sq[7:3]];
    assign s_byte    = 8'(sq_lane >> {sq[2:0], 3'b000});
    assign s_valid   = (state == S_IDLE) && stream_en && !sq_empty;

    // tail bytes followed by the domain-separation suffix
    always_comb begin
        case (n[1:0])
            2'd0:    tail_word = {56'd0, suffix};
            2'd1:    tail_word = {48'd0, suffix, imm[7:0]};
            default: tail_word = {40'd0, suffix, imm[15:0]};
        endcase
    end

    // buffer port
    assign b_addr  = r_la + cnt;
    assign b_we    = (state == S_SQ) && !sq_empty;
    assign b_wdata = sq_lane;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done  <= 1'b0;
            sq    <= '0;
            rate  <= 5'd17;
        end else begin
            done <= 1'b0;
            case (state)
                // ---------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        r_la <= la;
                        r_n  <= n;
                        cnt  <= '0;
                        case (opc)
                            OP_HINIT: begin
                                for (int i = 0; i < 25; i++) st[i] <= '0;
                                pos <= '0;
                                sq  <= '0;
                                case (imm[1:0])
                                    H_SHA3_256: begin rate <= 5'd17; suffix <= 8'h06; end
                                    H_SHA3_512: begin rate <= 5'd9;  suffix <= 8'h06; end
                                    H_SHAKE128: begin rate <= 5'd21; suffix <= 8'h1F; end
                                    default:    begin rate <= 5'd17; suffix <= 8'h1F; end
                                endcase
                                done <= 1'b1;
                            end
                            OP_ABSORB: state <= S_ABS_RD;
                            OP_FINAL: begin
                                for (int i = 0; i < 25; i++) begin
                                    if (i == pos && i == rate - 1)
                                        st[i] <= st[i] ^ tail_word ^ {8'h80, 56'd0};
                                    else if (i == pos)
                                        st[i] <= st[i] ^ tail_word;
                                    else if (i == rate - 1)
                                        st[i] <= st[i] ^ {8'h80, 56'd0};
                                end
                                sq    <= '0;
                                rnd   <= '0;
                                ret   <= R_DONE;
                                state <= S_PERM;
                            end
                            default: state <= S_SQ;      // OP_SQUEEZE
                        endcase
                    end else if (stream_en) begin
                        if (sq_empty) begin
                            sq    <= '0;
                            rnd   <= '0;
                            ret   <= R_IDLE;
                            state <= S_PERM;
                        end else if (s_ready) begin
                            sq <= sq + 8'd1;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_ABS_RD: state <= S_ABS_XOR;      // buffer read in flight
                S_ABS_XOR: begin
                    st[pos] <= st[pos] ^ b_rdata;
                    cnt     <= cnt + 9'd1;
                    if (pos == rate - 5'd1) begin
                        pos   <= '0;
                        rnd   <= '0;
                        ret   <= (cnt == r_n - 9'd1) ? R_DONE : R_ABS;
                        state <= S_PERM;
                    end else begin
                        pos <= pos + 5'd1;
                        if (cnt == r_n - 9'd1) begin
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            state <= S_ABS_RD;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_SQ: begin
                    if (sq_empty) begin
                        sq    <= '0;
                        rnd   <= '0;
                        ret   <= R_SQ;
                        state <= S_PERM;
                    end else begin
                        sq  <= sq + 8'd8;
                        cnt <= cnt + 9'd1;
                        if (cnt == r_n - 9'd1) begin
                            done  <= 1'b1;
                            state <= S_IDLE;
                        end
                    end
                end
                // ---------------------------------------------------------
                S_PERM: begin
                    st  <= keccak_round(st, rnd);
                    rnd <= rnd + 5'd1;
                    if (rnd == 5'd23) begin
                        case (ret)
                            R_DONE:  begin done <= 1'b1; state <= S_IDLE; end
                            R_ABS:   state <= S_ABS_RD;
                            R_SQ:    state <= S_SQ;
                            default: state <= S_IDLE;
                        endcase
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
