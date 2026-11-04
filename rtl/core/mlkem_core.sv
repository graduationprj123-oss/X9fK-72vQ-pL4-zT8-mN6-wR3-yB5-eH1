// ============================================================================
// mlkem_core.sv
// ML-KEM-512 core: wires the sequencer, the functional units and poly RAM.
// The I/O buffer (keys, ciphertext, seeds) lives outside, on port 'b_*'.
//
//   cmd = 1 : KeyGen   in : d, z          out : ek, dk
//   cmd = 2 : Encaps   in : ek, m         out : ct, K
//   cmd = 3 : Decaps   in : dk, ct        out : K
// ============================================================================
module mlkem_core
    import mlkem_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [1:0]  cmd,
    output logic        busy,
    output logic        done,
    // I/O buffer, core port (1-cycle read latency)
    output logic [8:0]  b_addr,
    output logic        b_we,
    output logic [63:0] b_wdata,
    input  logic [63:0] b_rdata
);

    // ======================================================================
    // Sequencer (control/mlkem_ctrl.sv)
    // ======================================================================
    instr_t   ins;
    group_t   grp;
    logic     unit_done;
    logic     st_sponge, st_sampler, st_alu, st_codec, st_bufops;

    mlkem_ctrl u_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .cmd        (cmd),
        .busy       (busy),
        .done       (done),
        .ins        (ins),
        .grp        (grp),
        .unit_done  (unit_done),
        .st_sponge  (st_sponge),
        .st_sampler (st_sampler),
        .st_alu     (st_alu),
        .st_codec   (st_codec),
        .st_bufops  (st_bufops)
    );

    // ======================================================================
    // Units
    // ======================================================================
    logic dn_sponge, dn_sampler, dn_alu, dn_codec, dn_bufops;
    assign unit_done = dn_sponge | dn_sampler | dn_alu | dn_codec | dn_bufops;

    // buffer ports of the units
    logic [8:0]  sp_addr, cd_addr, bo_addr;
    logic        sp_we,   cd_we,   bo_we;
    logic [63:0] sp_wd,   cd_wd,   bo_wd;

    // sponge -> sampler byte stream
    logic        stream_en, s_valid, s_ready;
    logic [7:0]  s_byte;

    // poly RAM ports of the units
    logic        al_we_a, al_we_b, sm_we, cd_pwe;
    logic [10:0] al_addr_a, al_addr_b, sm_addr, cd_paddr;
    logic [23:0] al_din_a, al_din_b, sm_din, cd_pdin;
    logic [23:0] pr_dout_a, pr_dout_b;

    sponge u_sponge (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (st_sponge),
        .opc       (ins.op),
        .la        (ins.la),
        .n         (ins.n),
        .imm       (ins.imm),
        .done      (dn_sponge),
        .b_addr    (sp_addr),
        .b_we      (sp_we),
        .b_wdata   (sp_wd),
        .b_rdata   (b_rdata),
        .stream_en (stream_en),
        .s_byte    (s_byte),
        .s_valid   (s_valid),
        .s_ready   (s_ready)
    );

    sampler u_sampler (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (st_sampler),
        .opc       (ins.op),
        .sd        (ins.sd),
        .eta       (ins.imm[1:0]),
        .done      (dn_sampler),
        .stream_en (stream_en),
        .s_byte    (s_byte),
        .s_valid   (s_valid),
        .s_ready   (s_ready),
        .p_we      (sm_we),
        .p_addr    (sm_addr),
        .p_din     (sm_din)
    );

    poly_alu u_alu (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (st_alu),
        .opc     (ins.op),
        .sa      (ins.sa),
        .sb      (ins.sb),
        .sd      (ins.sd),
        .done    (dn_alu),
        .pa_we   (al_we_a),
        .pa_addr (al_addr_a),
        .pa_din  (al_din_a),
        .pa_dout (pr_dout_a),
        .pb_we   (al_we_b),
        .pb_addr (al_addr_b),
        .pb_din  (al_din_b),
        .pb_dout (pr_dout_b)
    );

    codec u_codec (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (st_codec),
        .opc     (ins.op),
        .slot    ((ins.op == OP_ENC) ? ins.sa : ins.sd),
        .la      (ins.la),
        .d       (ins.imm[3:0]),
        .done    (dn_codec),
        .p_we    (cd_pwe),
        .p_addr  (cd_paddr),
        .p_din   (cd_pdin),
        .p_dout  (pr_dout_a),
        .b_addr  (cd_addr),
        .b_we    (cd_we),
        .b_wdata (cd_wd),
        .b_rdata (b_rdata)
    );

    bufops u_bufops (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (st_bufops),
        .opc     (ins.op),
        .la      (ins.la),
        .lb      (ins.lb),
        .n       (ins.n),
        .done    (dn_bufops),
        .b_addr  (bo_addr),
        .b_we    (bo_we),
        .b_wdata (bo_wd),
        .b_rdata (b_rdata)
    );

    // ======================================================================
    // Shared memories: owner = group of the current instruction
    // ======================================================================
    always_comb begin
        case (grp)
            G_CODEC:  begin b_addr = cd_addr; b_we = cd_we & busy; b_wdata = cd_wd; end
            G_BUFOPS: begin b_addr = bo_addr; b_we = bo_we & busy; b_wdata = bo_wd; end
            default:  begin b_addr = sp_addr; b_we = sp_we & busy; b_wdata = sp_wd; end
        endcase
    end

    logic        pr_we_a;
    logic [10:0] pr_addr_a;
    logic [23:0] pr_din_a;
    always_comb begin
        case (grp)
            G_SAMPLER: begin pr_we_a = sm_we;   pr_addr_a = sm_addr;   pr_din_a = sm_din;   end
            G_CODEC:   begin pr_we_a = cd_pwe;  pr_addr_a = cd_paddr;  pr_din_a = cd_pdin;  end
            default:   begin pr_we_a = al_we_a; pr_addr_a = al_addr_a; pr_din_a = al_din_a; end
        endcase
    end

    poly_ram u_poly_ram (
        .clk    (clk),
        .we_a   (pr_we_a),
        .addr_a (pr_addr_a),
        .din_a  (pr_din_a),
        .dout_a (pr_dout_a),
        .we_b   (al_we_b),
        .addr_b (al_addr_b),
        .din_b  (al_din_b),
        .dout_b (pr_dout_b)
    );

endmodule
