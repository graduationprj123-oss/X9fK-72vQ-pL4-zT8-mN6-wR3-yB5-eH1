// ============================================================================
// codec.sv
// Polynomial <-> byte conversion between poly RAM and the I/O buffer.
//   ENC : buffer[la..] = ByteEncode_d( d == 12 ? f : Compress_d(f) )
//   DEC : f = d == 12 ? ByteDecode_12(buf) mod q : Decompress_d(ByteDecode_d(buf))
//   d in {1, 4, 10, 12}; bit-packing is LSB first (FIPS 203).
// One RAM word (2 coefficients = 2d bits) is handled per step.
// ============================================================================
module codec
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  opcode_t     opc,          // OP_ENC / OP_DEC
    input  logic [3:0]  slot,
    input  logic [8:0]  la,
    input  logic [3:0]  d,
    output logic        done,
    // poly RAM port (2-cycle read latency)
    output logic        p_we,
    output logic [10:0] p_addr,
    output logic [23:0] p_din,
    input  logic [23:0] p_dout,
    // I/O buffer port (1-cycle read latency)
    output logic [8:0]  b_addr,
    output logic        b_we,
    output logic [63:0] b_wdata,
    input  logic [63:0] b_rdata
);

    typedef enum logic [3:0] {
        C_IDLE,
        E_RD, E_W1, E_W2, E_PACK, E_FLUSH,      // encode
        D_CHK, D_RD, D_FILL, D_EMIT             // decode
    } state_t;

    state_t      state;
    logic [3:0]  r_slot, r_d;
    logic [8:0]  lane;
    logic [6:0]  w;                    // word index 0..127
    logic [127:0] bb;                  // bit buffer
    logic [6:0]  nb;                   // valid bits in bb
    logic [23:0] pair;                 // 2 x d bits

    logic [4:0]  d2;
    logic [11:0] dmask;
    assign d2    = {r_d, 1'b0};
    assign dmask = 12'((13'd1 << r_d) - 13'd1);

    // ---------------- Compress_d (x < q) ---------------------------------
    //   round(2^d * x / q) mod 2^d = floor(((x << d) + 1664) / q)
    //   floor(v / 3329) = (v * 2580335) >> 33  exact for v < 2^22
    function automatic logic [11:0] compress(input logic [11:0] x, input logic [3:0] dd);
        logic [21:0] v;
        logic [43:0] m;
        v = (22'(x) << dd) + 22'd1664;
        m = 44'(v) * 44'd2580335;
        return 12'(m >> 33) & 12'((13'd1 << dd) - 13'd1);
    endfunction

    // ---------------- Decompress_d : round(q * y / 2^d) ------------------
    function automatic logic [11:0] decompress(input logic [11:0] y, input logic [3:0] dd);
        logic [23:0] v;
        v = 24'(y) * 24'd3329 + (24'd1 << (dd - 4'd1));
        return 12'(v >> dd);
    endfunction

    function automatic logic [11:0] reduce(input logic [11:0] y);   // y < 4096 -> mod q
        return (y >= 12'd3329) ? 12'(y - 12'd3329) : y;
    endfunction

    // ---------------- encode transform ------------------------------------
    logic [11:0] e0, e1;
    assign e0 = (r_d == 4'd12) ? p_dout[11:0]  : compress(p_dout[11:0],  r_d);
    assign e1 = (r_d == 4'd12) ? p_dout[23:12] : compress(p_dout[23:12], r_d);

    // ---------------- decode transform ------------------------------------
    logic [11:0] v0, v1, f0, f1;
    assign v0 = 12'(bb) & dmask;
    assign v1 = 12'(bb >> r_d) & dmask;
    assign f0 = (r_d == 4'd12) ? reduce(v0) : decompress(v0, r_d);
    assign f1 = (r_d == 4'd12) ? reduce(v1) : decompress(v1, r_d);

    // ---------------- memory ports -----------------------------------------
    assign p_addr  = {r_slot, w};
    assign p_we    = (state == D_EMIT);
    assign p_din   = {f1, f0};
    assign b_addr  = lane;
    assign b_we    = (state == E_FLUSH) && (nb >= 7'd64);
    assign b_wdata = bb[63:0];

    // ---------------- control ----------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= C_IDLE;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                C_IDLE: if (start) begin
                    r_slot <= slot;
                    r_d    <= d;
                    lane   <= la;
                    w      <= '0;
                    bb     <= '0;
                    nb     <= '0;
                    state  <= (opc == OP_ENC) ? E_RD : D_CHK;
                end
                // ------------------------------ encode ----------------------
                E_RD:   state <= E_W1;                 // RAM address presented
                E_W1:   state <= E_W2;
                E_W2: begin                            // RAM data valid
                    pair  <= 24'(e0) | (24'(e1) << r_d);
                    state <= E_PACK;
                end
                E_PACK: begin
                    bb    <= bb | (128'(pair) << nb);
                    nb    <= nb + 7'(d2);
                    state <= E_FLUSH;
                end
                E_FLUSH: begin
                    if (nb >= 7'd64) begin             // lane written this cycle
                        bb   <= bb >> 64;
                        nb   <= nb - 7'd64;
                        lane <= lane + 9'd1;
                    end
                    w <= w + 7'd1;
                    if (w == 7'd127) begin
                        done  <= 1'b1;
                        state <= C_IDLE;
                    end else begin
                        state <= E_RD;
                    end
                end
                // ------------------------------ decode ----------------------
                D_CHK:  state <= (nb < 7'(d2)) ? D_RD : D_EMIT;
                D_RD:   state <= D_FILL;               // buffer read in flight
                D_FILL: begin
                    bb    <= bb | (128'(b_rdata) << nb);
                    nb    <= nb + 7'd64;
                    lane  <= lane + 9'd1;
                    state <= D_EMIT;
                end
                D_EMIT: begin                          // word written this cycle
                    bb <= bb >> d2;
                    nb <= nb - 7'(d2);
                    w  <= w + 7'd1;
                    if (w == 7'd127) begin
                        done  <= 1'b1;
                        state <= C_IDLE;
                    end else begin
                        state <= D_CHK;
                    end
                end
                default: state <= C_IDLE;
            endcase
        end
    end

endmodule
