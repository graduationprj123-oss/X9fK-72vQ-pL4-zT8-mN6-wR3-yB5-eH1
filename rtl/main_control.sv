`timescale 1ns / 1ps

module MAIN_CONTROL #(
    parameter N_BU = 1
) (
    input           clk,
    input           rst,
    input   [7:0]   control,
    input           start_core,
    output          end_op_core,

    output  [7:0]   i,
    output  [7:0]   j,

    output  [11:0]  ctl_keccak,
    input           end_op_keccak,
    output  [7:0]   ctl_cbd,
    input           end_op_cbd,
    output  [3:0]   ctl_rej,
    output  [3:0]   off_rej,
    output  [15:0]  off_rej_dmu,
    input   [1:0]   end_op_rej,
    output  [19:0]  ctl_bu,
    input   [3:0]   end_op_bu,
    output  [40:0]  control_dmu,
    output  [31:0]  off_ram,

    output          start_read_ek,
    input           start_hek,
    input           last_hek,

    input           gmh_decap,
    input           start_ed
);

    // ------------------------------------------------------------------
    // Global control
    // ------------------------------------------------------------------
    wire            end_op_op;
    wire            end_op_bu_1;
    wire [11:0]     ctl_k_global;
    wire [7:0]      i_global;
    wire            start_op;
    wire            sel_global;

    // Only one Butterfly Unit is instantiated.
    assign end_op_op = end_op_bu_1;

    GLOBAL_CONTROL u_global_control (
        .clk             (clk),
        .rst             (rst),
        .control         (control),
        .start_op        (start_op),
        .i_global        (i_global),
        .start_core      (start_core),
        .end_op_core     (end_op_op),
        .end_op_keccak   (end_op_keccak),
        .control_keccak  (ctl_k_global),
        .sel_global      (sel_global),
        .start_read_ek   (start_read_ek),
        .start_hek       (start_hek),
        .last_hek        (last_hek),
        .end_op          (end_op_core),
        .gmh             (gmh_decap),
        .start_ed        (start_ed)
    );

    // ------------------------------------------------------------------
    // Keccak, CBD and rejection-sampling control
    // ------------------------------------------------------------------
    wire [11:0] ctl_k;
    wire [7:0]  i_k;
    wire [34:0] control_dmu_cbd;
    wire [15:0] off_ram_cbd;

    wire [1:0] eta;
    wire       scnd;
    wire       sel_rej;
    wire       reset_cbd;
    wire       reset_rej;
    wire       load_cbd;
    wire       load_rej;
    wire       start_cbd;
    wire       start_rej;

    wire [3:0] busy_bu;

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
    assign i          = sel_global ? i_global : i_k;

    assign ctl_cbd = {start_cbd, load_cbd, scnd, eta, reset_cbd};
    assign ctl_rej = {start_rej, load_rej, sel_rej, reset_rej};

    // ------------------------------------------------------------------
    // Single Butterfly Unit control
    // ------------------------------------------------------------------
    wire [34:0] control_dmu_bu;
    wire [31:0] off_ram_bu;

    wire       start_bu_1;
    wire [3:0] mode_bu_1;
    wire [3:0] busy_bu_1;

    wire busy_r0 = start_rej & ~sel_rej & ~end_op_rej[1];
    wire busy_r1 = start_rej &  sel_rej & ~end_op_rej[1];

    // The single BU occupies lane 0. Unused BU lanes are tied low.
    assign busy_bu = {3'b000, (start_bu_1 & ~end_op_bu[0])};

    // Read-request indicators for the single instantiated BU.
    // The remaining lanes are unused in this single-BU configuration.
    wire [3:0] read_1 = {
        control_dmu_bu[28], control_dmu_bu[20],
        control_dmu_bu[12], control_dmu_bu[4]
    };

    assign control_dmu_bu[34:8] = 27'b0;
    assign off_ram_bu[31:8]     = 24'b0;

    PRIORITY_ENCODER u_priority_encoder_1 (
        .busy_bu   (busy_bu),
        .cond1     (read_1[0]),
        .cond2     (read_1[1]),
        .cond3     (read_1[2]),
        .cond4     (read_1[3]),
        .busy_bu_N (busy_bu_1)
    );

    CONTROL_BU #(
        .UNIT    (1),
        .N_UNITS (1)
    ) u_control_bu_1 (
        .clk          (clk),
        .rst          (rst),
        .mode         (control[7:4]),
        .start        (start_core),
        .busy_r0      (busy_r0),
        .busy_r1      (busy_r1),
        .busy_bu      (busy_bu_1),
        .end_op_bu    (end_op_bu[0]),
        .start_bu     (start_bu_1),
        .mode_bu      (mode_bu_1),
        .control_dmu  (control_dmu_bu[7:0]),
        .off_ram      (off_ram_bu[7:0]),
        .off_rej      (off_rej_dmu[3:0]),
        .end_op       (end_op_bu_1),
        .start_ed     (start_ed)
    );

    // Only the first BU lane is active. Other DMU control lanes retain
    // the CBD/REJ controller outputs, as in the original interface layout.
    assign control_dmu[7:0]   = start_bu_1 ? control_dmu_bu[7:0] : control_dmu_cbd[7:0];
    assign control_dmu[15:8]  = control_dmu_cbd[15:8];
    assign control_dmu[23:16] = control_dmu_cbd[23:16];
    assign control_dmu[31:24] = control_dmu_cbd[31:24];
    assign control_dmu[40:32] = 9'b0;

    assign off_ram[3:0]   = start_bu_1 ? off_ram_bu[3:0] : off_ram_cbd[3:0];
    assign off_ram[7:4]   = start_bu_1 ? off_ram_bu[7:4] : off_ram_cbd[3:0];
    assign off_ram[15:8]  = {off_ram_cbd[7:4], off_ram_cbd[7:4]};
    assign off_ram[23:16] = {off_ram_cbd[11:8], off_ram_cbd[11:8]};
    assign off_ram[31:24] = {off_ram_cbd[15:12], off_ram_cbd[15:12]};

    // off_rej_dmu is 16 bits wide, but only one BU drives its low nibble.
    assign off_rej_dmu[15:4] = 12'b0;

    // Keep the original 20-bit port layout: mode fields [19:4], start fields [3:0].
    assign ctl_bu = {12'b0, mode_bu_1, 3'b000, start_bu_1};

endmodule
