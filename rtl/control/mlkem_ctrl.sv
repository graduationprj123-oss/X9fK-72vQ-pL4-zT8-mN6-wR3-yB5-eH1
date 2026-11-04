// ============================================================================
// mlkem_ctrl.sv
// Micro-sequencer: runs the KeyGen / Encaps / Decaps program from
// mlkem_prog_pkg, one instruction at a time.
//   FETCH : read the instruction ROM
//   EXEC  : pulse the start of the unit that owns the opcode
//   WAIT  : wait for that unit's done, then pc + 1
// ============================================================================
module mlkem_ctrl
    import mlkem_pkg::*;
    import mlkem_prog_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [1:0]  cmd,
    output logic        busy,
    output logic        done,
    // current instruction and the unit that executes it
    output instr_t      ins,
    output group_t      grp,
    // unit handshake
    input  logic        unit_done,
    output logic        st_sponge,
    output logic        st_sampler,
    output logic        st_alu,
    output logic        st_codec,
    output logic        st_bufops
);

    typedef enum logic [2:0] {Q_IDLE, Q_FETCH, Q_EXEC, Q_WAIT, Q_DONE} qstate_t;

    qstate_t    qs;
    logic [7:0] pc;
    logic       unit_start;

    // ---------------- opcode -> unit ----------------------------------------
    always_comb begin
        case (ins.op)
            OP_HINIT, OP_ABSORB, OP_FINAL, OP_SQUEEZE: grp = G_SPONGE;
            OP_SNTT, OP_SCBD:                         grp = G_SAMPLER;
            OP_ENC, OP_DEC:                           grp = G_CODEC;
            OP_CMP, OP_CSEL:                          grp = G_BUFOPS;
            default:                                  grp = G_ALU;   // NTT INTT PWM ADD SUB
        endcase
    end

    assign busy       = (qs != Q_IDLE);
    assign unit_start = (qs == Q_EXEC) && (ins.op != OP_END);

    assign st_sponge  = unit_start && (grp == G_SPONGE);
    assign st_sampler = unit_start && (grp == G_SAMPLER);
    assign st_alu     = unit_start && (grp == G_ALU);
    assign st_codec   = unit_start && (grp == G_CODEC);
    assign st_bufops  = unit_start && (grp == G_BUFOPS);

    // ---------------- sequencer FSM -----------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            qs   <= Q_IDLE;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (qs)
                Q_IDLE: if (start && cmd != 2'd0) begin
                    case (cmd)
                        CMD_KEYGEN: pc <= PC_KEYGEN;
                        CMD_ENCAPS: pc <= PC_ENCAPS;
                        default:    pc <= PC_DECAPS;
                    endcase
                    qs <= Q_FETCH;
                end
                Q_FETCH: begin
                    ins <= prog_rom(pc);
                    qs  <= Q_EXEC;
                end
                Q_EXEC:  qs <= (ins.op == OP_END) ? Q_DONE : Q_WAIT;
                Q_WAIT:  if (unit_done) begin
                    pc <= pc + 8'd1;
                    qs <= Q_FETCH;
                end
                Q_DONE: begin
                    done <= 1'b1;
                    qs   <= Q_IDLE;
                end
                default: qs <= Q_IDLE;
            endcase
        end
    end

endmodule
