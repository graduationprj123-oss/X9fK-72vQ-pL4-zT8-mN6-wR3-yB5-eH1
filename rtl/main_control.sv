`timescale 1ns / 1ps

// =============================================================================
// MAIN_CONTROL : single-BU version
// =============================================================================
module MAIN_CONTROL (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  control,
    input  logic        start_core,
    output logic        end_op_core,

    output logic [7:0]  i,
    output logic [7:0]  j,

    output logic [11:0] ctl_keccak,
    input  logic        end_op_keccak,
    output logic [7:0]  ctl_cbd,
    input  logic        end_op_cbd,
    output logic [3:0]  ctl_rej,
    output logic [3:0]  off_rej,
    output logic [15:0] off_rej_dmu,
    input  logic [1:0]  end_op_rej,
    output logic [19:0] ctl_bu,
    input  logic [3:0]  end_op_bu,
    output logic [40:0] control_dmu,
    output logic [31:0] off_ram,

    output logic        start_read_ek,
    input  logic        start_hek,
    input  logic        last_hek,

    input  logic        gmh_decap,
    input  logic        start_ed
);

    // -------------------------------------------------------------------------
    // GLOBAL CONTROL
    // -------------------------------------------------------------------------
    logic        end_op_op;
    logic [11:0] ctl_k_global;
    logic [7:0]  i_global;
    logic        start_op;
    logic        sel_global;

    GLOBAL_CONTROL u_global_control (
        .clk            (clk),
        .rst            (rst),
        .control        (control),
        .start_core     (start_core),
        .end_op_core    (end_op_op),
        .end_op_keccak  (end_op_keccak),
        .control_keccak (ctl_k_global),
        .sel_global     (sel_global),
        .i_global       (i_global),
        .start_op       (start_op),
        .start_read_ek  (start_read_ek),
        .start_hek      (start_hek),
        .last_hek       (last_hek),
        .gmh            (gmh_decap),
        .start_ed       (start_ed),
        .end_op         (end_op_core)
    );

    // -------------------------------------------------------------------------
    // CONTROL KECCAK + CBD + REJ
    // -------------------------------------------------------------------------
    logic [11:0] ctl_k;
    logic [7:0]  i_k;
    logic [34:0] control_dmu_cbd;
    logic [15:0] off_ram_cbd;

    logic [1:0]  eta;
    logic        scnd;
    logic        sel_rej;

    logic        reset_cbd, reset_rej;
    logic        load_cbd,  load_rej;
    logic        start_cbd, start_rej;

    CONTROL_KECCAK #(
        .MASKED (0),
        .N_BU   (1)
    ) u_control_keccak (
        .clk             (clk),
        .rst             (rst),
        .start           (start_op),
        .mode            (control[7:4]),
        .ctl_k           (ctl_k),
        .i               (i_k),
        .j               (j),
        .reset_cbd       (reset_cbd),
        .reset_rej       (reset_rej),
        .load_cbd        (load_cbd),
        .load_rej        (load_rej),
        .start_cbd       (start_cbd),
        .start_rej       (start_rej),
        .eta             (eta),
        .scnd            (scnd),
        .sel_rej         (sel_rej),
        .control_dmu_cbd (control_dmu_cbd),
        .off_ram_cbd     (off_ram_cbd),
        .off_rej         (off_rej),
        .end_op_cbd      (end_op_cbd),
        .end_op_rej      (end_op_rej[0]),
        .end_rd_rej      (end_op_rej[1]),
        .end_op_keccak   (end_op_keccak),
        .end_op_bu       ({3'b000, end_op_bu[0]})
    );

    assign ctl_keccak = sel_global ? ctl_k_global : ctl_k;
    assign i          = sel_global ? i_global     : i_k;

    assign ctl_cbd = {start_cbd, load_cbd, scnd, eta, reset_cbd};
    assign ctl_rej = {start_rej, load_rej, sel_rej, reset_rej};

    // -------------------------------------------------------------------------
    // CONTROL BUTTERFLY UNIT (1 BU)
    // -------------------------------------------------------------------------
    logic [7:0] control_dmu_bu;
    logic [7:0] off_ram_bu;
    logic       start_bu;
    logic [3:0] mode_bu;
    logic [3:0] busy_bu_arb;   // ket qua arbitration cho BU

    logic busy_cbd, busy_r0, busy_r1;
    logic busy_bu;

    assign busy_cbd = start_cbd & ~end_op_cbd;
    assign busy_r0  = start_rej & ~sel_rej & ~end_op_rej[1];
    assign busy_r1  = start_rej &  sel_rej & ~end_op_rej[1];
    assign busy_bu  = start_bu  & ~end_op_bu[0];

    // Chi con 1 BU nen chi can PE1; cond1..4 = bit [7:4] cua control_dmu_bu
    PRIORITY_ENCODER u_pe1 (
        .busy_bu   ({3'b000, busy_bu}),
        .cond1     (control_dmu_bu[4]),
        .cond2     (control_dmu_bu[5]),
        .cond3     (control_dmu_bu[6]),
        .cond4     (control_dmu_bu[7]),
        .busy_bu_N (busy_bu_arb)
    );

    CONTROL_BU #(
        .UNIT    (1),
        .N_UNITS (1)
    ) u_control_bu (
        .clk         (clk),
        .rst         (rst),
        .mode        (control[7:4]),
        .start       (start_core),
        .busy_r0     (busy_r0),
        .busy_r1     (busy_r1),
        .busy_bu     (busy_bu_arb),
        .end_op_bu   (end_op_bu[0]),
        .start_bu    (start_bu),
        .mode_bu     (mode_bu),
        .control_dmu (control_dmu_bu),
        .off_ram     (off_ram_bu),
        .off_rej     (off_rej_dmu[3:0]),
        .end_op      (end_op_op),
        .start_ed    (start_ed)
    );

    assign off_rej_dmu[15:4] = '0;

    // -------------------------------------------------------------------------
    // MUX BU / CBD -> DMU, RAM
    // -------------------------------------------------------------------------
    assign control_dmu[7:0]   = start_bu ? control_dmu_bu : control_dmu_cbd[7:0];
    assign control_dmu[31:8]  = control_dmu_cbd[31:8];
    assign control_dmu[40:32] = '0;

    assign off_ram[3:0]   = start_bu ? off_ram_bu[3:0] : off_ram_cbd[3:0];    // off_ram_01
    assign off_ram[7:4]   = start_bu ? off_ram_bu[7:4] : off_ram_cbd[3:0];    // off_ram_11
    assign off_ram[11:8]  = off_ram_cbd[7:4];                                 // off_ram_02
    assign off_ram[15:12] = off_ram_cbd[7:4];                                 // off_ram_12
    assign off_ram[19:16] = off_ram_cbd[11:8];                                // off_ram_03
    assign off_ram[23:20] = off_ram_cbd[11:8];                                // off_ram_13
    assign off_ram[27:24] = off_ram_cbd[15:12];                               // off_ram_04
    assign off_ram[31:28] = off_ram_cbd[15:12];                               // off_ram_14

    assign ctl_bu = {12'b0, mode_bu, 3'b000, start_bu};

endmodule


// =============================================================================
// GLOBAL_CONTROL
// =============================================================================
module GLOBAL_CONTROL (
    input  logic        clk,
    input  logic        rst,          // active-low
    input  logic [7:0]  control,
    input  logic        start_core,
    input  logic        end_op_core,
    input  logic        end_op_keccak,
    output logic [11:0] control_keccak,
    output logic        sel_global,
    output logic [7:0]  i_global,
    output logic        start_op,
    output logic        start_read_ek,
    input  logic        start_hek,
    input  logic        last_hek,
    input  logic        gmh,
    input  logic        start_ed,
    output logic        end_op
);

    // -------------------------------------------------------------------------
    // Mode decode
    // -------------------------------------------------------------------------
    logic [3:0] mode;
    logic       k_2, k_3, k_4;
    logic       gen_keys, encap, decap;

    assign mode     = control[7:4];
    assign k_2      = (mode[1:0] == 2'b01);
    assign k_3      = (mode[1:0] == 2'b10);
    assign k_4      = (mode[1:0] == 2'b11);
    assign gen_keys = (mode[3:2] == 2'b01);
    assign encap    = (mode[3:2] == 2'b10);
    assign decap    = (mode[3:2] == 2'b11);

    always_comb begin
        if      (k_2) i_global = 8'h02;
        else if (k_3) i_global = 8'h03;
        else if (k_4) i_global = 8'h04;
        else          i_global = 8'h02;
    end

    // -------------------------------------------------------------------------
    // Keccak control word
    // -------------------------------------------------------------------------
    logic       reset_k, load_k, start_k, read_k;
    logic       reset_gen, load_gen, start_gen, read_gen;
    logic [3:0] mode_gen;

    assign control_keccak = {mode_gen, read_gen, start_gen, load_gen, reset_gen,
                             read_k, start_k, load_k, reset_k};

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [7:0] {
        IDLE           = 8'h00,
        GDK_LOAD_GEN   = 8'h10,
        GDK_LOAD       = 8'h11,
        GDK_START      = 8'h12,
        GDK_SAVE       = 8'h13,
        HEK_START_READ = 8'h20,
        HEK_SEL_LOAD   = 8'h21,
        HEK_LOAD_BASIC = 8'h22,
        HEK_LOAD_K_2   = 8'h23,
        HEK_LOAD_K_3   = 8'h24,
        HEK_LOAD_K_4   = 8'h25,
        HEK_LOAD       = 8'h26,
        HEK_START      = 8'h27,
        HEK_EVAL       = 8'h28,
        HEK_ADD        = 8'h29,
        HEK_SAVE       = 8'h2A,
        GMH_LOAD_GEN   = 8'h30,
        GMH_LOAD       = 8'h31,
        GMH_START      = 8'h32,
        GMH_SAVE       = 8'h33,
        START_OP       = 8'h40,
        END_OP         = 8'h41,
        SAVE_SEED      = 8'h60,
        UPDATE_SEED    = 8'h61
    } state_t;

    state_t cs, ns;

    always_ff @(posedge clk) begin
        if (!rst) cs <= IDLE;
        else      cs <= ns;
    end

    assign start_op      = (cs == START_OP);
    assign start_read_ek = (cs == HEK_START_READ);

    logic do_last;
    always_ff @(posedge clk) begin
        if (cs == IDLE)                       do_last <= 1'b0;
        else if (cs == HEK_EVAL && last_hek)  do_last <= 1'b1;
    end

    // Next-state logic
    always_comb begin
        ns = cs;
        unique case (cs)
            IDLE: begin
                ns = IDLE;
                if (start_core) begin
                    if      (gen_keys)        ns = GDK_LOAD_GEN;
                    else if (encap)           ns = SAVE_SEED;
                    else if (decap && !gmh)   ns = START_OP;
                    else if (decap &&  gmh)   ns = UPDATE_SEED;
                end
            end

            SAVE_SEED:   ns = start_ed ? START_OP : HEK_SEL_LOAD;
            UPDATE_SEED: ns = GMH_LOAD_GEN;

            START_OP: begin
                ns = START_OP;
                if (end_op_core) begin
                    if      (gen_keys)        ns = HEK_START_READ;
                    else if (encap)           ns = END_OP;
                    else if (decap && !gmh)   ns = END_OP;
                    else if (decap &&  gmh)   ns = GMH_LOAD_GEN;
                end
            end

            HEK_START_READ: ns = start_hek ? HEK_SEL_LOAD : HEK_START_READ;

            HEK_SEL_LOAD: begin
                if (last_hek) begin
                    if      (k_2) ns = HEK_LOAD_K_2;
                    else if (k_3) ns = HEK_LOAD_K_3;
                    else          ns = HEK_LOAD_K_4;
                end
                else ns = HEK_LOAD_BASIC;
            end

            HEK_LOAD_K_2,
            HEK_LOAD_K_3,
            HEK_LOAD_K_4,
            HEK_LOAD_BASIC: ns = HEK_LOAD;

            HEK_LOAD:  ns = HEK_START;
            HEK_START: ns = end_op_keccak ? HEK_ADD : HEK_START;
            HEK_ADD:   ns = HEK_EVAL;
            HEK_EVAL:  ns = do_last ? HEK_SAVE : HEK_SEL_LOAD;
            HEK_SAVE:  ns = gen_keys ? END_OP : GMH_LOAD_GEN;

            GDK_LOAD_GEN: ns = GDK_LOAD;
            GDK_LOAD:     ns = GDK_START;
            GDK_START:    ns = end_op_keccak ? GDK_SAVE : GDK_START;
            GDK_SAVE:     ns = START_OP;

            GMH_LOAD_GEN: ns = GMH_LOAD;
            GMH_LOAD:     ns = GMH_START;
            GMH_START:    ns = end_op_keccak ? GMH_SAVE : GMH_START;
            GMH_SAVE:     ns = encap ? START_OP : END_OP;

            default:      ns = IDLE;
        endcase
    end

    // Output logic (default 0, chi gan nhung tin hieu khac 0 cua tung state)
    always_comb begin
        reset_k    = 1'b0;
        load_k     = 1'b0;
        start_k    = 1'b0;
        read_k     = 1'b0;
        reset_gen  = 1'b0;
        load_gen   = 1'b0;
        start_gen  = 1'b0;
        read_gen   = 1'b0;
        mode_gen   = 4'h0;
        sel_global = 1'b0;
        end_op     = 1'b0;

        case (cs)
            IDLE: begin
                reset_k   = 1'b1;
                reset_gen = 1'b1;
            end

            SAVE_SEED,
            UPDATE_SEED: begin
                reset_k    = 1'b1;
                load_gen   = 1'b1;
                sel_global = 1'b1;
            end

            GDK_LOAD_GEN: begin
                mode_gen   = 4'h1;
                sel_global = 1'b1;
            end
            GDK_LOAD: begin
                load_k     = 1'b1;
                mode_gen   = 4'h1;
                sel_global = 1'b1;
            end
            GDK_START: begin
                start_k    = 1'b1;
                mode_gen   = 4'h1;
                sel_global = 1'b1;
            end
            GDK_SAVE: begin
                read_k     = 1'b1;
                read_gen   = 1'b1;
                mode_gen   = 4'h1;
                sel_global = 1'b1;
            end

            HEK_SEL_LOAD:   sel_global = 1'b1;
            HEK_LOAD_BASIC: begin mode_gen = 4'h6; sel_global = 1'b1; end
            HEK_LOAD_K_2:   begin mode_gen = 4'h7; sel_global = 1'b1; end
            HEK_LOAD_K_3:   begin mode_gen = 4'h8; sel_global = 1'b1; end
            HEK_LOAD_K_4:   begin mode_gen = 4'h9; sel_global = 1'b1; end
            HEK_LOAD: begin
                load_k     = 1'b1;
                sel_global = 1'b1;
            end
            HEK_START,
            HEK_ADD,
            HEK_EVAL: begin
                start_k    = 1'b1;
                sel_global = 1'b1;
            end
            HEK_SAVE: begin
                read_k     = 1'b1;
                read_gen   = 1'b1;
                mode_gen   = 4'h7;
                sel_global = 1'b1;
            end

            GMH_LOAD_GEN: begin
                mode_gen   = 4'hA;
                sel_global = 1'b1;
            end
            GMH_LOAD: begin
                load_k     = 1'b1;
                mode_gen   = 4'hA;
                sel_global = 1'b1;
            end
            GMH_START: begin
                start_k    = 1'b1;
                sel_global = 1'b1;
            end
            GMH_SAVE: begin
                read_k     = 1'b1;
                read_gen   = 1'b1;
                mode_gen   = 4'hA;
                sel_global = 1'b1;
            end

            START_OP: reset_k = 1'b1;

            END_OP: begin
                reset_k   = 1'b1;
                reset_gen = 1'b1;
                end_op    = 1'b1;
            end

            // Bao gom ca HEK_START_READ (giong ban goc: roi vao default)
            default: begin
                reset_k   = 1'b1;
                reset_gen = 1'b1;
            end
        endcase
    end

endmodule
