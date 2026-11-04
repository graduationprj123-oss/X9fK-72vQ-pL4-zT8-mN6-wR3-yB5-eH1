// ============================================================================
// sampler.sv
// SampleNTT (rejection sampling, FIPS 203 Alg. 7) and SamplePolyCBD_eta
// (Alg. 8, eta = 2 or 3). Consumes the sponge byte stream, writes 256
// coefficients (two per 24-bit word) into a poly RAM slot.
// ============================================================================
module sampler
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  opcode_t     opc,          // OP_SNTT / OP_SCBD
    input  logic [3:0]  sd,
    input  logic [1:0]  eta,
    output logic        done,
    // byte stream from the sponge
    output logic        stream_en,
    input  logic [7:0]  s_byte,
    input  logic        s_valid,
    output logic        s_ready,
    // poly RAM write port
    output logic        p_we,
    output logic [10:0] p_addr,
    output logic [23:0] p_din
);

    typedef enum logic [2:0] {M_IDLE, M_GET, M_REJ1, M_REJ2, M_CBD} state_t;

    state_t      state;
    logic [3:0]  r_sd;
    logic [1:0]  r_eta;
    logic [8:0]  ncoef;              // coefficients produced so far
    logic [11:0] low;                // even coefficient waiting for its pair
    logic [1:0]  bcnt;               // SampleNTT: bytes collected (0..2)
    logic [7:0]  b0, b1, b2;
    logic [15:0] bits;               // CBD bit buffer
    logic [4:0]  nbits;

    // ---------------- candidates -----------------------------------------
    logic [11:0] d1, d2;
    assign d1 = {b1[3:0], b0};
    assign d2 = {b2, b1[7:4]};

    // ---------------- CBD -------------------------------------------------
    logic [2:0]  cx, cy;
    logic [11:0] cbd_val;
    always_comb begin
        if (r_eta == 2'd2) begin
            cx = 3'(bits[0]) + 3'(bits[1]);
            cy = 3'(bits[2]) + 3'(bits[3]);
        end else begin
            cx = 3'(bits[0]) + 3'(bits[1]) + 3'(bits[2]);
            cy = 3'(bits[3]) + 3'(bits[4]) + 3'(bits[5]);
        end
        cbd_val = (cx >= cy) ? 12'(cx - cy) : 12'(12'd3329 - 12'(cy - cx));
    end
    logic [4:0] need;                // 2*eta bits per coefficient
    assign need = (r_eta == 2'd2) ? 5'd4 : 5'd6;

    // ---------------- stream handshake -----------------------------------
    assign stream_en = (state == M_GET) || (state == M_CBD && nbits < need);
    assign s_ready   = stream_en;

    // ---------------- coefficient push (pairs -> RAM words) --------------
    logic        push;
    logic [11:0] push_val;
    always_comb begin
        push     = 1'b0;
        push_val = cbd_val;
        case (state)
            M_REJ1: begin push = (d1 < 12'd3329); push_val = d1; end
            M_REJ2: begin push = (d2 < 12'd3329); push_val = d2; end
            M_CBD:  push = (nbits >= need);
            default: ;
        endcase
    end

    assign p_we   = push && ncoef[0];
    assign p_addr = {r_sd, ncoef[7:1]};
    assign p_din  = {push_val, low};

    logic last_coef;
    assign last_coef = push && (ncoef == 9'd255);

    // ---------------- control --------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= M_IDLE;
            done  <= 1'b0;
        end else begin
            done <= 1'b0;
            if (push) begin
                ncoef <= ncoef + 9'd1;
                if (!ncoef[0]) low <= push_val;
            end
            case (state)
                M_IDLE: if (start) begin
                    r_sd   <= sd;
                    r_eta  <= eta;
                    ncoef  <= '0;
                    bcnt   <= '0;
                    nbits  <= '0;
                    bits   <= '0;
                    state  <= (opc == OP_SCBD) ? M_CBD : M_GET;
                end
                M_GET: if (s_valid) begin
                    case (bcnt)
                        2'd0: b0 <= s_byte;
                        2'd1: b1 <= s_byte;
                        default: b2 <= s_byte;
                    endcase
                    bcnt <= (bcnt == 2'd2) ? 2'd0 : bcnt + 2'd1;
                    if (bcnt == 2'd2) state <= M_REJ1;
                end
                M_REJ1: begin
                    if (last_coef) begin
                        done  <= 1'b1;
                        state <= M_IDLE;
                    end else begin
                        state <= M_REJ2;
                    end
                end
                M_REJ2: begin
                    if (last_coef) begin
                        done  <= 1'b1;
                        state <= M_IDLE;
                    end else begin
                        state <= M_GET;
                    end
                end
                M_CBD: begin
                    if (nbits >= need) begin            // emit one coefficient
                        bits  <= bits >> need;
                        nbits <= nbits - need;
                        if (last_coef) begin
                            done  <= 1'b1;
                            state <= M_IDLE;
                        end
                    end else if (s_valid) begin         // fetch one byte
                        bits  <= bits | (16'(s_byte) << nbits);
                        nbits <= nbits + 5'd8;
                    end
                end
                default: state <= M_IDLE;
            endcase
        end
    end

endmodule
