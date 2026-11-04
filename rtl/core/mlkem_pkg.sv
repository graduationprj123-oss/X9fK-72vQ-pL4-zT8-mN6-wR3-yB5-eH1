// ============================================================================
// mlkem_pkg.sv
// ML-KEM-512 accelerator : shared constants, types and memory map
// ============================================================================
package mlkem_pkg;

    // ------------------------------------------------------------------ //
    // ML-KEM parameters (FIPS 203, ML-KEM-512)
    // ------------------------------------------------------------------ //
    localparam int Q = 3329;

    // ------------------------------------------------------------------ //
    // Micro-instruction set
    // ------------------------------------------------------------------ //
    typedef enum logic [3:0] {
        OP_END     = 4'd0,   // end of program
        OP_HINIT   = 4'd1,   // sponge: clear state, imm = hash mode
        OP_ABSORB  = 4'd2,   // sponge: absorb n lanes from buffer[la]
        OP_FINAL   = 4'd3,   // sponge: absorb n tail bytes (imm) + padding, permute
        OP_SQUEEZE = 4'd4,   // sponge: squeeze n lanes into buffer[la]
        OP_SNTT    = 4'd5,   // SampleNTT (from SHAKE128 stream) -> slot sd
        OP_SCBD    = 4'd6,   // SamplePolyCBD_eta (eta = imm)   -> slot sd
        OP_NTT     = 4'd7,   // in-place NTT  of slot sd
        OP_INTT    = 4'd8,   // in-place INTT of slot sd
        OP_PWM     = 4'd9,   // sd = sa o sb  (NTT-domain multiply)
        OP_ADD     = 4'd10,  // sd = sa + sb
        OP_SUB     = 4'd11,  // sd = sa - sb
        OP_ENC     = 4'd12,  // buffer[la..] = ByteEncode_d(Compress_d(sa)),  d = imm
        OP_DEC     = 4'd13,  // sd = Decompress_d(ByteDecode_d(buffer[la..])), d = imm
        OP_CMP     = 4'd14,  // flag = (buffer[la..+n] != buffer[lb..+n])
        OP_CSEL    = 4'd15   // if (flag) buffer[la..+n] = buffer[lb..+n]  (constant time)
    } opcode_t;

    typedef struct packed {
        opcode_t     op;
        logic [3:0]  sa;     // poly slot A
        logic [3:0]  sb;     // poly slot B
        logic [3:0]  sd;     // poly slot destination
        logic [8:0]  la;     // buffer lane address A
        logic [8:0]  lb;     // buffer lane address B
        logic [8:0]  n;      // lane count / tail length
        logic [15:0] imm;    // immediate
    } instr_t;

    // hash modes (imm of OP_HINIT)
    localparam logic [1:0] H_SHA3_256 = 2'd0;
    localparam logic [1:0] H_SHA3_512 = 2'd1;
    localparam logic [1:0] H_SHAKE128 = 2'd2;
    localparam logic [1:0] H_SHAKE256 = 2'd3;

    // butterfly-unit operations
    typedef enum logic [2:0] {
        BU_NTT  = 3'd0,
        BU_INTT = 3'd1,
        BU_PWM  = 3'd2,
        BU_ADD  = 3'd3,
        BU_SUB  = 3'd4
    } bu_op_t;

    // functional unit that executes an instruction
    typedef enum logic [2:0] {
        G_SPONGE, G_SAMPLER, G_ALU, G_CODEC, G_BUFOPS
    } group_t;

    // top-level commands
    localparam logic [1:0] CMD_KEYGEN = 2'd1;
    localparam logic [1:0] CMD_ENCAPS = 2'd2;
    localparam logic [1:0] CMD_DECAPS = 2'd3;

    // ------------------------------------------------------------------ //
    // I/O buffer map (64-bit lanes; byte address = lane * 8)
    //   dk  = s^ (768 B) | ek (800 B) | H(ek) (32 B) | z (32 B)     1632 B
    //   ct  = c1 (640 B) | c2 (128 B)                               768 B
    // ------------------------------------------------------------------ //
    localparam int L_DK    = 0;     // 0x000  dk  (1632 B)
    localparam int L_EK    = 96;    // 0x300  ek  (800 B)  (inside dk)
    localparam int L_RHO   = 192;   // 0x600  rho          (inside ek)
    localparam int L_HEK   = 196;   // 0x620  H(ek)        (inside dk)
    localparam int L_Z     = 200;   // 0x640  z            (inside dk)
    localparam int L_CT    = 204;   // 0x660  ct  (768 B)
    localparam int L_CT2   = 300;   // 0x960  re-encrypted ct (decaps)
    localparam int L_D     = 396;   // 0xC60  d   (keygen seed)
    localparam int L_MSG   = 400;   // 0xC80  m   (encaps input / decaps m')
    localparam int L_KR    = 404;   // 0xCA0  K (32 B) | r (32 B)   -> shared secret K
    localparam int L_SIGMA = 412;   // 0xCE0  sigma
    localparam int L_KBAR  = 420;   // 0xD20  K-bar (implicit rejection key)

    // ------------------------------------------------------------------ //
    // Latencies
    // ------------------------------------------------------------------ //
    localparam int PRAM_LAT = 2;    // poly RAM read latency (output register)
    localparam int MUL_LAT  = 3;    // mod_mul latency

    localparam int BF_LAT   = 7;    // every butterfly sub-unit (bf_ntt/intt/pwm/addsub)
                                    // the cycle tables in those files assume MUL_LAT = 3

    // butterfly_core: input reg + sub-unit + output reg
    localparam int BU_LAT   = 1 + BF_LAT + 1;    // 9
    // read address -> write; MUST be odd (reads on phase 0, writes on phase 1)
    localparam int ALU_LAT  = PRAM_LAT + BU_LAT; // 11

endpackage
