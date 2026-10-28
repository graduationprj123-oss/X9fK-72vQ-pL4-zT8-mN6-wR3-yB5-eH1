
`timescale 1ns / 1ps

module TOP_MLKEM #(
    parameter N_BU = 1
) (
    input  wire          clk,
    input  wire          rst,
    input  wire [7:0]    control,

    // Control signals
    input  wire          start_core,
    output wire          end_op_core,
    input  wire          sel_io,

    // Control Keccak
    output wire          start_keccak,
    output wire          start_read_ek,
    input  wire          start_hek,
    input  wire          last_hek,

    // Input Keccak
    input  wire [255:0]  i_seed_0,       // d / rho
    input  wire [255:0]  i_seed_1,       // r
    output wire [255:0]  o_seed_0,       // rho
    output wire [255:0]  o_seed_1,       // sigma
    input  wire [255:0]  i_hek,
    input  wire [255:0]  i_ss,
    output wire [255:0]  o_hek,
    output wire [255:0]  o_ss,
    input  wire [1087:0] ek_in,

    // Encoder / Decoder signals
    input  wire [15:0]   mode_encdec,
    output wire          d_valid_encoder,
    input  wire          start_encoder,
    input  wire          start_decoder,
    output wire          d_ready_decoder,
    input  wire          d_valid_decoder,
    output wire          upd_add_decoder,
    input  wire [159:0]  add_ram,
    output wire [63:0]   out_encoder,
    input  wire [63:0]   input_decoder,

    // DMU
    input  wire [40:0]   control_dmu_io,

    // Encap / Decap signals
    input  wire          rst_ed,
    input  wire          gmh_decap,
    input  wire          start_encap_decap
);

    // ================================================================
    // Internal signals
    // ================================================================

    // Input Keccak
    wire [7:0] i;
    wire [7:0] j;

    // Keccak signals
    wire [11:0] ctl_keccak;
    wire        end_op_keccak;

    // CBD signals
    wire [7:0] ctl_cbd;
    wire       end_op_cbd;

    // Rejection Sampler signals
    wire [3:0]  ctl_rej;
    wire [3:0]  off_rej;
    wire [15:0] off_rej_dmu;
    wire [3:0]  end_op_rej;

    // Butterfly Unit (BU) signals
    wire [19:0] ctl_bu;
    wire [3:0]  end_op_bu;

    // DMU signals
    wire [31:0] off_ram;
    wire [40:0] control_dmu;
    wire [40:0] control_dmu_core;

    // ================================================================
    // Arithmetic Unit - 1 BU
    // ================================================================

    ARITHMETIC_UNIT_N_BU_1 ARITHMETIC_UNIT (
        .clk             (clk),
        .rst             (rst),

        // Input Keccak
        .i_seed_0        (i_seed_0),
        .i_seed_1        (i_seed_1),
        .o_seed_0        (o_seed_0),
        .o_seed_1        (o_seed_1),
        .i               (i),
        .j               (j),
        .i_hek           (i_hek),
        .o_hek           (o_hek),
        .i_ss            (i_ss),
        .o_ss            (o_ss),
        .ek_in           (ek_in),

        // Keccak
        .ctl_keccak      (ctl_keccak),
        .end_op_keccak   (end_op_keccak),

        // CBD
        .ctl_cbd         (ctl_cbd),
        .end_op_cbd      (end_op_cbd),

        // Rejection Sampler
        .ctl_rej         (ctl_rej),
        .off_rej         (off_rej),
        .off_rej_dmu     (off_rej_dmu),
        .end_op_rej      (end_op_rej),

        // BU
        .ctl_bu          (ctl_bu),
        .end_op_bu       (end_op_bu),

        // DMU
        .control_dmu     (control_dmu),
        .off_ram         (off_ram),

        // Encoder
        .mode_encdec     (mode_encdec),
        .add_ram         (add_ram),
        .start_encoder   (start_encoder),
        .d_valid_encoder (d_valid_encoder),
        .out_encoder     (out_encoder),

        // Decoder
        .input_decoder   (input_decoder),
        .start_decoder   (start_decoder),
        .d_valid_decoder (d_valid_decoder),
        .d_ready_decoder (d_ready_decoder),
        .upd_add_decoder (upd_add_decoder)
    );

    // ================================================================
    // Main Control
    // ================================================================

    MAIN_CONTROL #(
        .N_BU (1)
    ) MAIN_CONTROL (
        // Control signals
        .clk             (clk),
        .rst             (rst & !rst_ed),
        .control         (control),
        .start_core      (start_core),
        .end_op_core     (end_op_core),

        // Input Keccak
        .i               (i),
        .j               (j),

        // Keccak
        .ctl_keccak      (ctl_keccak),
        .end_op_keccak   (end_op_keccak),

        // CBD
        .ctl_cbd         (ctl_cbd),
        .end_op_cbd      (end_op_cbd),

        // Rejection Sampler
        .ctl_rej         (ctl_rej),
        .off_rej         (off_rej),
        .off_rej_dmu     (off_rej_dmu),
        .end_op_rej      (end_op_rej),

        // BU
        .ctl_bu          (ctl_bu),
        .end_op_bu       (end_op_bu),

        // DMU
        .control_dmu     (control_dmu_core),
        .off_ram         (off_ram),

        // Hek signals
        .start_read_ek   (start_read_ek),
        .start_hek       (start_hek),
        .last_hek        (last_hek),

        // Encap / Decap
        .gmh_decap       (gmh_decap),
        .start_ed        (start_encap_decap)
    );

    // ================================================================
    // Signal Assignments
    // ================================================================

    assign control_dmu = sel_io ? control_dmu_io : control_dmu_core;

    assign start_keccak = ctl_keccak[2];

endmodule
