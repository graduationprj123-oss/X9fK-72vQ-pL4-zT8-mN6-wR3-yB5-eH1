`timescale 1ns / 1ps

module ARITHMETIC_UNIT_N_BU_1 (
    input               clk,
    input               rst,
    input   [255:0]     i_seed_0, // d / rho
    input   [255:0]     i_seed_1, // r
    output  [255:0]     o_seed_0, // rho
    output  [255:0]     o_seed_1, // sigma
    input   [7:0]       i,
    input   [7:0]       j,
    input  [255:0]      i_hek,
    input  [255:0]      i_ss,
    output [255:0]      o_hek,
    output [255:0]      o_ss,
    input   [1087:0]    ek_in,
    input   [11:0]      ctl_keccak,
    output              end_op_keccak,
    input   [7:0]       ctl_cbd,
    output              end_op_cbd,
    input   [3:0]       ctl_rej,
    input   [3:0]       off_rej,
    input   [15:0]      off_rej_dmu,
    output  [3:0]       end_op_rej,
    input   [19:0]      ctl_bu,
    output  [3:0]       end_op_bu,
    input   [40:0]      control_dmu,
    input   [31:0]      off_ram,

    input   [15:0]          mode_encdec,
    input   [16*10-1:0]    add_ram,
    input                   start_encoder,
    output                  d_valid_encoder,
    output  [63:0]          out_encoder,

    input   [63:0]          input_decoder,
    input                   start_decoder,
    input                   d_valid_decoder,
    output                  d_ready_decoder,
    output                  upd_add_decoder
);

   wire  [35:0] out_1_01;
   wire  [35:0] out_2_01;
   wire  [35:0] out_1_11;
   wire  [35:0] out_2_11;

   wire  [9:0] ad_1_01;
   wire  [9:0] ad_2_01;
   wire  [9:0] ad_1_11;
   wire  [9:0] ad_2_11;

   assign ad_1_01 = add_ram[9:0];
   assign ad_2_01 = add_ram[19:10];
   assign ad_1_11 = add_ram[29:20];
   assign ad_2_11 = add_ram[39:30];

    // --- SHA-512/256 / SHAKE-128/256 --- //
    wire reset_gen;
    wire start_gen;
    wire load_gen;
    wire read_gen;
    wire [3:0] mode_gen;
    wire [1599:0] do_keccak;
    wire [1599:0] di_keccak;

    assign reset_gen    = ctl_keccak[4];
    assign load_gen     = ctl_keccak[5];
    assign start_gen    = ctl_keccak[6];
    assign read_gen     = ctl_keccak[7];
    assign mode_gen     = ctl_keccak[11:8];

    gen_input_keccak gen_input_keccak (
        .clk        (   clk                 ),
        .rst        (   rst & !reset_gen    ),
        .load       (   load_gen            ),
        .read       (   read_gen            ),
        .mode_gen   (   mode_gen            ),
        .ek_pke_in  (   ek_in               ),
        .i_seed_0   (   i_seed_0            ),
        .i_seed_1   (   i_seed_1            ),
        .o_seed_0   (   o_seed_0            ),
        .o_seed_1   (   o_seed_1            ),
        .i          (   i                   ),
        .j          (   j                   ),
        .i_hek      (   i_hek               ),
        .o_hek      (   o_hek               ),
        .i_ss       (   i_ss                ),
        .o_ss       (   o_ss                ),
        .do_keccak  (   do_keccak           ),
        .di_keccak  (   di_keccak           )
    );

    wire reset_keccak;
    wire load_keccak;
    wire start_keccak;
    wire read_keccak;

    wire [1599:0] keccak_out;

    assign reset_keccak  = ctl_keccak[0];
    assign load_keccak   = ctl_keccak[1];
    assign start_keccak  = ctl_keccak[2];
    assign read_keccak   = ctl_keccak[3];

    keccak keccak (
        .clk        (   clk                 ),
        .rst        (   rst & !reset_keccak ),
        .load       (   load_keccak         ),
        .start      (   start_keccak        ),
        .read       (   read_keccak         ),
        .input_data (   di_keccak           ),
        .keccak_out (   keccak_out          ),
        .end_op     (   end_op_keccak       )
    );

    assign do_keccak = keccak_out;

    // --- cbd --- //
    wire        reset_cbd;
    wire [1:0]  eta;
    wire        scnd;
    wire        load_cbd;
    wire        start_cbd;
    wire        en_write_cbd;
    wire [23:0] data_in_1_cbd;
    wire [23:0] data_in_2_cbd;
    wire [7:0]  addr_1_cbd;
    wire [7:0]  addr_2_cbd;

    assign reset_cbd    = ctl_cbd[0];
    assign eta          = ctl_cbd[2:1];
    assign scnd         = ctl_cbd[3];
    assign load_cbd     = ctl_cbd[4];
    assign start_cbd    = ctl_cbd[5];

    CBD CBD (
        .clk            (   clk                     ),
        .rst            (   rst & !reset_cbd        ),
        .eta            (   eta                     ),
        .scnd           (   scnd                    ),
        .in_shake       (   keccak_out[1087:0]      ),
        .load           (   load_cbd                ),
        .start          (   start_cbd               ),
        .end_op         (   end_op_cbd              ),
        .en_write       (   en_write_cbd            ),
        .data_in_1      (   data_in_1_cbd           ),
        .data_in_2      (   data_in_2_cbd           ),
        .addr_1         (   addr_1_cbd              ),
        .addr_2         (   addr_2_cbd              )
    );

    // --- Rej Uniform --- //

    wire reset_r0;
    wire selw_r0;
    wire load_r0;
    wire start_r0;
    wire end_op_r0;
    wire end_rd_r0;
    wire [3:0] off_r0;
    wire [3:0] off_r1;

    wire [23:0] do_1_0_r0;
    wire [23:0] do_2_0_r0;
    wire [9:0] ar_1_0_r0;
    wire [9:0] ar_2_0_r0;
    wire [23:0] do_1_0_r1;
    wire [23:0] do_2_0_r1;
    wire [9:0] ar_1_0_r1;
    wire [9:0] ar_2_0_r1;

    assign reset_rej    = ctl_rej[0];
    assign selw_rej     = ctl_rej[1];
    assign load_rej     = ctl_rej[2];
    assign start_rej    = ctl_rej[3];

    assign off_r0       = off_rej[3:0];
    assign off_r1       = off_rej[3:0];

    REJ_UNIFORM_SHORT REJ_UNIFORM_SHORT (
        .clk            (   clk                 ),
        .rst            (   rst & !reset_rej    ),
        .selw           (   selw_rej            ),
        .in_shake       (   keccak_out[1343:0]  ),
        .off_r0         (   off_r0              ),
        .off_r1         (   off_r1              ),
        .load           (   load_rej            ),
        .start          (   start_rej           ),
        .end_op         (   end_op_rej[0]       ),
        .end_read       (   end_op_rej[1]       ),
        .do_1_0         (   do_1_0_r0           ),
        .do_2_0         (   do_2_0_r0           ),
        .ar_1_0         (   ar_1_0_r0           ),
        .ar_2_0         (   ar_2_0_r0           ),
        .do_3_0         (   do_1_0_r1           ),
        .do_4_0         (   do_2_0_r1           ),
        .ar_3_0         (   ar_1_0_r1           ),
        .ar_4_0         (   ar_2_0_r1           )
    );

    // ---- BU ENGINE ---- //
    wire    [3:0]   start_bu;
    wire    [15:0]  mode_bu;

    assign start_bu    = ctl_bu[3:0];
    assign mode_bu     = ctl_bu[19:4];

    wire [7:0]       en_ram;
    wire [4*24-1:0]  di_1;
    wire [4*24-1:0]  do_1;
    wire [4*8-1:0]   ad_1;

    BU_ENGINE_N_BU_1
    BU_ENGINE_N_BU_1 (
        .clk        (   clk         ),
        .rst        (   rst         ),
        .start      (   start_bu    ),
        .mode       (   mode_bu     ),
        .end_op     (   end_op_bu   ),
        .en_ram     (   en_ram      ),
        .ad_1       (   ad_1        ),
        .di_1       (   di_1        ),
        .do_1       (   do_1        )
    );

    // --- RAM BANK --- //
    wire            enable_1_01;
    wire            enable_2_01;
    wire [9:0]      addr_1_01;
    wire [9:0]      addr_2_01;
    wire [35:0]     data_in_1_01;
    wire [35:0]     data_in_2_01;
    wire [35:0]     data_out_1_01;
    wire [35:0]     data_out_2_01;

    wire            enable_1_11;
    wire            enable_2_11;
    wire [9:0]      addr_1_11;
    wire [9:0]      addr_2_11;
    wire [35:0]     data_in_1_11;
    wire [35:0]     data_in_2_11;
    wire [35:0]     data_out_1_11;
    wire [35:0]     data_out_2_11;

    assign out_1_01 = data_out_1_01;
    assign out_2_01 = data_out_2_01;
    assign out_1_11 = data_out_1_11;
    assign out_2_11 = data_out_2_11;

    RAM_BANK_N_BU_1
    RAM_BANK_N_BU_1 (
    .clk            (   clk             ),

    .enable_1_01    (   enable_1_01     ),
    .enable_2_01    (   enable_2_01     ),
    .addr_1_01      (   addr_1_01       ),
    .addr_2_01      (   addr_2_01       ),
    .data_in_1_01   (   data_in_1_01    ),
    .data_in_2_01   (   data_in_2_01    ),
    .data_out_1_01  (   data_out_1_01   ),
    .data_out_2_01  (   data_out_2_01   ),

    .enable_1_11    (   enable_1_11     ),
    .enable_2_11    (   enable_2_11     ),
    .addr_1_11      (   addr_1_11       ),
    .addr_2_11      (   addr_2_11       ),
    .data_in_1_11   (   data_in_1_11    ),
    .data_in_2_11   (   data_in_2_11    ),
    .data_out_1_11  (   data_out_1_11   ),
    .data_out_2_11  (   data_out_2_11   )
    );

    // ---- DMU ---- //
    wire [3:0] off_ram01;
    wire [3:0] off_ram11;

    assign off_ram01 = off_ram[3:0];
    assign off_ram11 = off_ram[7:4];

    wire [3:0] off_r1_dmu;
    wire [3:0] off_r2_dmu;
    assign off_r1_dmu = off_rej_dmu[3:0];
    assign off_r2_dmu = off_rej_dmu[7:4];

    wire [2*24-1:0] out_decoder;

    DMU_N_BU_1
    DMU_N_BU_1 (
    .clk(clk),
    // CONTROL
    .control_dmu (  control_dmu ),

    .off_r1   (   off_r1_dmu  ),
    .off_ram01   (   off_ram01    ),
    .off_ram11   (   off_ram11    ),

    .ad_1_01    (   ad_1_01     ),
    .ad_2_01    (   ad_2_01     ),
    .ad_1_11    (   ad_1_11     ),
    .ad_2_11    (   ad_2_11     ),

    // CBD
    .en_write           (   en_write_cbd            ),
    .data_in_1_cbd      (   data_in_1_cbd           ),
    .data_in_2_cbd      (   data_in_2_cbd           ),
    .addr_1_cbd         (   addr_1_cbd              ),
    .addr_2_cbd         (   addr_2_cbd              ),

    // REJ UNIFORM
    .do_1_0_r0       (   do_1_0_r0     ),
    .ar_1_0_r0       (   ar_1_0_r0     ),

    .do_1_0_r1       (   do_1_0_r1     ),
    .ar_1_0_r1       (   ar_1_0_r1     ),

    // BU - ENGINE
    .en_ram     (   en_ram      ),
    .ad_1       (   ad_1        ),
    .di_1       (   di_1        ),
    .do_1       (   do_1        ),

    // DECODER
    .input_decoder  (   out_decoder     ),

    // RAM BANK
    .enable_1_01    (   enable_1_01     ),
    .enable_2_01    (   enable_2_01     ),
    .addr_1_01      (   addr_1_01       ),
    .addr_2_01      (   addr_2_01       ),
    .data_in_1_01   (   data_in_1_01    ),
    .data_in_2_01   (   data_in_2_01    ),
    .data_out_1_01  (   data_out_1_01   ),
    .data_out_2_01  (   data_out_2_01   ),

    .enable_1_11    (   enable_1_11     ),
    .enable_2_11    (   enable_2_11     ),
    .addr_1_11      (   addr_1_11       ),
    .addr_2_11      (   addr_2_11       ),
    .data_in_1_11   (   data_in_1_11    ),
    .data_in_2_11   (   data_in_2_11    ),
    .data_out_1_11  (   data_out_1_11   ),
    .data_out_2_11  (   data_out_2_11   )

    );

    // --- ENCODING / DECODING --- //
    wire [16*24-1:0] input_encoder;
    assign input_encoder = {
            24'h000000, 24'h000000, 24'h000000, 24'h000000,
            24'h000000, 24'h000000, 24'h000000, 24'h000000,
            24'h000000, 24'h000000, 24'h000000, 24'h000000,
            out_2_11[23:0], out_1_11[23:0], out_2_01[23:0], out_1_01[23:0]};

    ENCODER_COMPRESS ENCODER_COMPRESS (
        .clk        (   clk             ),
        .rst        (   rst             ),
        .start      (   start_encoder   ),
        .mode       (   mode_encdec     ),
        .d_valid    (   d_valid_encoder ),
        .input_data (   input_encoder   ),
        .out_data   (   out_encoder     )
    );

    // DECODER_DECOMPRESS DECODER_DECOMPRESS (
    DECODER_DECOMPRESS_4 DECODER_DECOMPRESS_4 (
        .clk            (   clk             ),
        .rst            (   rst             ),
        .input_data     (   input_decoder   ),
        .start_decod    (   start_decoder   ),
        .mode           (   mode_encdec     ),
        .d_valid        (   d_valid_decoder ),
        .d_ready        (   d_ready_decoder ),
        .upd_add        (   upd_add_decoder ),
        .out_data       (   out_decoder     )
    );

endmodule
