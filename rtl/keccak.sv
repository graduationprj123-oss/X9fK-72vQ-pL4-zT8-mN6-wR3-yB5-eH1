`timescale 1ns / 1ps

// SystemVerilog version of gen_input_keccak modules.
// Original algorithm and interface intent are retained.

module gen_input_keccak (
    input  logic          clk,
    input  logic          rst,
    input  logic          load,
    input  logic          read,
    input  logic [1087:0] ek_pke_in,
    input  logic [3:0]    mode_gen,
    input  logic [7:0]    i,
    input  logic [7:0]    j,
    input  logic [255:0]  i_seed_0,
    input  logic [255:0]  i_seed_1,
    output logic [255:0]  o_seed_0,
    output logic [255:0]  o_seed_1,
    input  logic [255:0]  i_hek,
    input  logic [255:0]  i_ss,
    output logic [255:0]  o_hek,
    output logic [255:0]  o_ss,
    input  logic [1599:0] do_keccak,
    output logic [1599:0] di_keccak
);

    // mode_gen:
    // 0: NONE
    // 1: G(d/k)
    // 2: SHAKE128(rho,i,j)
    // 3: SHAKE256(sigma,N)
    // 6: H(ek)
    // 7/8/9: H(ek) with seed loading for k=2/3/4
    // A: G(m,H(ek))

    logic [255:0] hek;
    logic [255:0] ss;

    assign o_hek = hek;
    assign o_ss  = ss;

    always_ff @(posedge clk) begin
        if (!rst) begin
            o_seed_0 <= '0;
            o_seed_1 <= '0;
        end else if (load) begin
            o_seed_0 <= i_seed_0;
            o_seed_1 <= o_seed_1;
        end else if (read) begin
            case (mode_gen)
                4'h1: begin
                    o_seed_0 <= do_keccak[255:0];
                    o_seed_1 <= do_keccak[511:256];
                end
                4'hA: begin
                    o_seed_0 <= o_seed_0;
                    o_seed_1 <= do_keccak[511:256];
                end
                default: begin
                    o_seed_0 <= o_seed_0;
                    o_seed_1 <= o_seed_1;
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rst)
            hek <= '0;
        else if (load)
            hek <= i_hek;
        else if (read && ((mode_gen == 4'h7) ||
                          (mode_gen == 4'h8) ||
                          (mode_gen == 4'h9)))
            hek <= do_keccak[255:0];
    end

    always_ff @(posedge clk) begin
        if (!rst)
            ss <= '0;
        else if (read && (mode_gen == 4'hA))
            ss <= do_keccak[255:0];
    end

    always_ff @(posedge clk) begin
        if (!rst) begin
            di_keccak <= '0;
        end else begin
            case (mode_gen)
                4'h1: di_keccak <= {
                    {128{8'h00}}, 8'h80, {37{8'h00}},
                    8'h06, i, i_seed_0
                };
                4'h2: di_keccak <= {
                    {32{8'h00}}, 8'h80, {132{8'h00}},
                    8'h1F, j, i, o_seed_0
                };
                4'h3: di_keccak <= {
                    {64{8'h00}}, 8'h80, {101{8'h00}},
                    8'h1F, i, o_seed_1
                };
                4'h6: di_keccak <= {{64{8'h00}}, ek_pke_in} ^ do_keccak;
                4'h7: di_keccak <= {
                    {64{8'h00}}, 8'h80, {14{8'h00}},
                    8'h06, o_seed_0, ek_pke_in[703:0]
                } ^ do_keccak;
                4'h8: di_keccak <= {
                    {64{8'h00}}, 8'h80, {38{8'h00}},
                    8'h06, o_seed_0, ek_pke_in[511:0]
                } ^ do_keccak;
                4'h9: di_keccak <= {
                    {64{8'h00}}, 8'h80, {62{8'h00}},
                    8'h06, o_seed_0, ek_pke_in[319:0]
                } ^ do_keccak;
                4'hA: di_keccak <= {
                    {128{8'h00}}, 8'h80, {6{8'h00}},
                    8'h06, hek, i_ss
                };
                default: di_keccak <= di_keccak;
            endcase
        end
    end

endmodule


module gen_input_keccak_MASKED_KECCAK (
    input  logic          clk,
    input  logic          rst,
    input  logic          load,
    input  logic          read,
    input  logic [1087:0] ek_pke_in,
    input  logic [3:0]    mode_gen,
    input  logic [7:0]    i,
    input  logic [7:0]    j,
    input  logic [255:0]  i_seed_0,
    input  logic [255:0]  i_seed_1,
    output logic [255:0]  o_seed_0,
    output logic [255:0]  o_seed_1,
    input  logic [255:0]  i_hek,
    input  logic [255:0]  i_ss,
    output logic [255:0]  o_hek,
    output logic [255:0]  o_ss,
    input  logic [1599:0] do_keccak,
    input  logic [1599:0] do_keccak_s1,
    input  logic [1599:0] do_keccak_s2,
    input  logic [1599:0] do_keccak_s3,
    input  logic [1599:0] do_keccak_s4,
    output logic [1599:0] di_keccak,
    output logic [1599:0] di_keccak_s1,
    output logic [1599:0] di_keccak_s2,
    output logic [1599:0] di_keccak_s3,
    output logic [1599:0] di_keccak_s4,
    input  logic [1599:0] random_data_1,
    input  logic [1599:0] random_data_2,
    input  logic [1599:0] random_data_3,
    output logic          flag_masked_prf,
    input  logic          flag_update_keccak
);

    logic [255:0] o_seed_1_s1;
    logic [255:0] o_seed_1_s2;
    logic [255:0] o_seed_1_s3;
    logic [255:0] o_seed_1_s4;

    logic [1599:0] masked_prf_1;
    logic [1599:0] masked_prf_2;

    logic [255:0] hek;
    logic [255:0] ss;

    assign o_seed_1 = o_seed_1_s1 ^ o_seed_1_s2 ^
                      o_seed_1_s3 ^ o_seed_1_s4;
    assign o_hek = hek;
    assign o_ss  = ss;

    assign masked_prf_1 = {
        {64{8'h00}}, 8'h80, {101{8'h00}},
        8'h1F, i, o_seed_1
    };
    assign masked_prf_2 = {
        {128{8'h00}}, 8'h80, {37{8'h00}},
        8'h06, i, i_seed_0
    };

    always_ff @(posedge clk) begin
        if (!rst) begin
            o_seed_0   <= '0;
            o_seed_1_s1 <= '0;
            o_seed_1_s2 <= '0;
            o_seed_1_s3 <= '0;
            o_seed_1_s4 <= '0;
        end else if (load) begin
            o_seed_0 <= i_seed_0;
        end else if (read) begin
            case (mode_gen)
                4'h1: begin
                    o_seed_0 <= do_keccak_s1[255:0] ^
                                do_keccak_s2[255:0] ^
                                do_keccak_s3[255:0] ^
                                do_keccak_s4[255:0];
                    o_seed_1_s1 <= do_keccak_s1[511:256];
                    o_seed_1_s2 <= do_keccak_s2[511:256];
                    o_seed_1_s3 <= do_keccak_s3[511:256];
                    o_seed_1_s4 <= do_keccak_s4[511:256];
                end
                4'hA: begin
                    o_seed_1_s1 <= do_keccak_s1[511:256];
                    o_seed_1_s2 <= do_keccak_s2[511:256];
                    o_seed_1_s3 <= do_keccak_s3[511:256];
                    o_seed_1_s4 <= do_keccak_s4[511:256];
                end
                default: begin
                    // Hold current values.
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rst) begin
            di_keccak_s1 <= '0;
            di_keccak_s2 <= '0;
            di_keccak_s3 <= '0;
            di_keccak_s4 <= '0;
            flag_masked_prf <= 1'b0;
        end else if (flag_update_keccak) begin
            case (mode_gen)
                4'h1: begin
                    di_keccak_s1 <= masked_prf_2 ^
                                    random_data_1 ^
                                    random_data_2 ^
                                    random_data_3;
                    di_keccak_s2 <= random_data_1;
                    di_keccak_s3 <= random_data_2;
                    di_keccak_s4 <= random_data_3;
                    flag_masked_prf <= 1'b1;
                end
                4'h3: begin
                    di_keccak_s1 <= masked_prf_1 ^
                                    random_data_1 ^
                                    random_data_2 ^
                                    random_data_3;
                    di_keccak_s2 <= random_data_1;
                    di_keccak_s3 <= random_data_2;
                    di_keccak_s4 <= random_data_3;
                    flag_masked_prf <= 1'b1;
                end
                default: begin
                    flag_masked_prf <= 1'b0;
                end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (!rst)
            hek <= '0;
        else if (load)
            hek <= i_hek;
        else if (read && ((mode_gen == 4'h7) ||
                          (mode_gen == 4'h8) ||
                          (mode_gen == 4'h9)))
            hek <= do_keccak[255:0];
    end

    always_ff @(posedge clk) begin
        if (!rst)
            ss <= '0;
        else if (read && (mode_gen == 4'hA))
            ss <= do_keccak[255:0];
    end

    always_ff @(posedge clk) begin
        if (!rst) begin
            di_keccak <= '0;
        end else begin
            case (mode_gen)
                4'h2: di_keccak <= {
                    {32{8'h00}}, 8'h80, {132{8'h00}},
                    8'h1F, j, i, o_seed_0
                };
                4'h6: di_keccak <= {{64{8'h00}}, ek_pke_in} ^ do_keccak;
                4'h7: di_keccak <= {
                    {64{8'h00}}, 8'h80, {14{8'h00}},
                    8'h06, o_seed_0, ek_pke_in[703:0]
                } ^ do_keccak;
                4'h8: di_keccak <= {
                    {64{8'h00}}, 8'h80, {38{8'h00}},
                    8'h06, o_seed_0, ek_pke_in[511:0]
                } ^ do_keccak;
                4'h9: di_keccak <= {
                    {64{8'h00}}, 8'h80, {62{8'h00}},
                    8'h06, o_seed_0, ek_pke_in[319:0]
                } ^ do_keccak;
                4'hA: di_keccak <= {
                    {128{8'h00}}, 8'h80, {6{8'h00}},
                    8'h06, hek, i_ss
                };
                default: di_keccak <= di_keccak;
            endcase
        end
    end

endmodule
