`timescale 1ns / 1ps

module MEM_ZETAS_COMPLETE #(
    parameter int unsigned DATA_WIDTH = 36,
    parameter int unsigned ADDR_WIDTH = 7
) (
    input  logic                  clk,
    input  logic [ADDR_WIDTH-1:0] addr_zeta,
    output logic [DATA_WIDTH-1:0] data_out_zeta
);

    ROM_ZETAS_COMPLETE #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_rom_zetas_complete (
        .clk      (clk),
        .addr     (addr_zeta),
        .data_out (data_out_zeta)
    );

endmodule


module ROM_ZETAS_COMPLETE #(
    parameter int unsigned DATA_WIDTH = 36,
    parameter int unsigned ADDR_WIDTH = 7
) (
    input  logic                  clk,
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [DATA_WIDTH-1:0] data_out
);

    localparam int unsigned DEPTH = 2 ** ADDR_WIDTH;

    // ROM: 128 entries, 36 bits per entry by default.
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Registered ROM output: one clock-cycle read latency.
    always_ff @(posedge clk) begin
        data_out <= mem[addr];
    end

    // ROM initialization.
    initial begin
        mem[0]   = {12'h011, 12'h001, 12'h001};
        mem[1]   = {12'hCF0, 12'h497, 12'h6C1};
        mem[2]   = {12'hAC9, 12'h98C, 12'hA14};
        mem[3]   = {12'h238, 12'h18A, 12'hCD9};
        mem[4]   = {12'h247, 12'h4C3, 12'hA52};
        mem[5]   = {12'hABA, 12'h8FC, 12'h276};
        mem[6]   = {12'hA59, 12'h5AF, 12'h769};
        mem[7]   = {12'h2A8, 12'h845, 12'h350};
        mem[8]   = {12'h665, 12'h647, 12'h426};
        mem[9]   = {12'h69C, 12'h98B, 12'h77F};
        mem[10]  = {12'h2D3, 12'h22A, 12'h0C1};
        mem[11]  = {12'hA2E, 12'h49B, 12'h31D};
        mem[12]  = {12'h8F0, 12'h88A, 12'hAE2};
        mem[13]  = {12'h411, 12'h8FF, 12'hCBC};
        mem[14]  = {12'h44C, 12'hB6E, 12'h239};
        mem[15]  = {12'h8B5, 12'h8BD, 12'h6D2};

        mem[16]  = {12'h581, 12'h20D, 12'h128};
        mem[17]  = {12'h780, 12'h2DF, 12'h98F};
        mem[18]  = {12'hA66, 12'h35F, 12'h53B};
        mem[19]  = {12'h29B, 12'hAD0, 12'h5C4};
        mem[20]  = {12'hCD1, 12'h4CE, 12'hBE6};
        mem[21]  = {12'h030, 12'hA0C, 12'h038};
        mem[22]  = {12'h0E9, 12'h22C, 12'h8C0};
        mem[23]  = {12'hC18, 12'hBC2, 12'h535};
        mem[24]  = {12'h2F4, 12'h8DA, 12'h592};
        mem[25]  = {12'hA0D, 12'h694, 12'h82E};
        mem[26]  = {12'h86C, 12'h4D7, 12'h217};
        mem[27]  = {12'h495, 12'h30C, 12'hB42};
        mem[28]  = {12'hBC7, 12'hB8A, 12'h959};
        mem[29]  = {12'h13A, 12'h06D, 12'hB3F};
        mem[30]  = {12'hBEA, 12'h50C, 12'h7B6};
        mem[31]  = {12'h117, 12'h407, 12'h335};

        mem[32]  = {12'h6A7, 12'h6D1, 12'h121};
        mem[33]  = {12'h65A, 12'hA80, 12'h14B};
        mem[34]  = {12'h673, 12'hBF5, 12'hCB5};
        mem[35]  = {12'h68E, 12'h3E0, 12'h6DC};
        mem[36]  = {12'hAE5, 12'hA24, 12'h4AD};
        mem[37]  = {12'h21C, 12'h3AD, 12'h900};
        mem[38]  = {12'h6FD, 12'h37C, 12'h8E5};
        mem[39]  = {12'h604, 12'h3FD, 12'h807};
        mem[40]  = {12'h737, 12'h956, 12'h28A};
        mem[41]  = {12'h5CA, 12'h282, 12'h7B9};
        mem[42]  = {12'h3B8, 12'h74C, 12'h9D1};
        mem[43]  = {12'h949, 12'h949, 12'h278};
        mem[44]  = {12'h5B5, 12'h5CA, 12'hB31};
        mem[45]  = {12'h74C, 12'h604, 12'h021};
        mem[46]  = {12'hA7F, 12'h21C, 12'h528};
        mem[47]  = {12'h282, 12'h68E, 12'h77B};
        mem[48]  = {12'h3AB, 12'h65A, 12'h90F};
        mem[49]  = {12'h956, 12'h117, 12'h59B};
        mem[50]  = {12'h904, 12'h13A, 12'h327};
        mem[51]  = {12'h3FD, 12'h495, 12'h1C4};
        mem[52]  = {12'h985, 12'hA0D, 12'h59E};
        mem[53]  = {12'h37C, 12'hC18, 12'hB34};
        mem[54]  = {12'h954, 12'h030, 12'h5FE};
        mem[55]  = {12'h3AD, 12'h29B, 12'h962};
        mem[56]  = {12'h2DD, 12'h780, 12'hA57};
        mem[57]  = {12'hA24, 12'h8B5, 12'hA39};
        mem[58]  = {12'h921, 12'h411, 12'h5C9};
        mem[59]  = {12'h3E0, 12'hA2E, 12'h288};
        mem[60]  = {12'h10C, 12'h69C, 12'h9AA};
        mem[61]  = {12'hBF5, 12'h2A8, 12'hC26};
        mem[62]  = {12'h281, 12'hABA, 12'h4CB};
        mem[63]  = {12'hA80, 12'h238, 12'h38E};

        mem[64]  = {12'h630, 12'hCF0, 12'h011};
        mem[65]  = {12'h6D1, 12'h973, 12'hAC9};
        mem[66]  = {12'h8FA, 12'h836, 12'h247};
        mem[67]  = {12'h407, 12'h0DB, 12'hA59};
        mem[68]  = {12'h7F5, 12'h357, 12'h665};
        mem[69]  = {12'h50C, 12'hA79, 12'h2D3};
        mem[70]  = {12'hC94, 12'h738, 12'h8F0};
        mem[71]  = {12'h06D, 12'h2C8, 12'h44C};
        mem[72]  = {12'h177, 12'h2AA, 12'h581};
        mem[73]  = {12'hB8A, 12'h39F, 12'hA66};
        mem[74]  = {12'h9F5, 12'h703, 12'hCD1};
        mem[75]  = {12'h30C, 12'h1CD, 12'h0E9};
        mem[76]  = {12'h82A, 12'h763, 12'h2F4};
        mem[77]  = {12'h4D7, 12'hB3D, 12'h86C};
        mem[78]  = {12'h66D, 12'h9DA, 12'hBC7};
        mem[79]  = {12'h694, 12'h766, 12'hBEA};
        mem[80]  = {12'h427, 12'h3F2, 12'h6A7};
        mem[81]  = {12'h8DA, 12'h586, 12'h673};
        mem[82]  = {12'h13F, 12'h7D9, 12'hAE5};
        mem[83]  = {12'hBC2, 12'hCE0, 12'h6FD};
        mem[84]  = {12'hAD5, 12'h1D0, 12'h737};
        mem[85]  = {12'h22C, 12'hA89, 12'h3B8};
        mem[86]  = {12'h2F5, 12'h330, 12'h5B5};
        mem[87]  = {12'hA0C, 12'h548, 12'hA7F};
        mem[88]  = {12'h833, 12'hA77, 12'h3AB};
        mem[89]  = {12'h4CE, 12'h4FA, 12'h904};
        mem[90]  = {12'h231, 12'h41C, 12'h985};
        mem[91]  = {12'hAD0, 12'h401, 12'h954};
        mem[92]  = {12'h9A2, 12'h854, 12'h2DD};
        mem[93]  = {12'h35F, 12'h625, 12'h921};
        mem[94]  = {12'hA22, 12'h04C, 12'h10C};
        mem[95]  = {12'h2DF, 12'hBB6, 12'h281};

        mem[96]  = {12'hAF4, 12'hBE0, 12'h630};
        mem[97]  = {12'h20D, 12'h9CC, 12'h8FA};
        mem[98]  = {12'h444, 12'h54B, 12'h7F5};
        mem[99]  = {12'h8BD, 12'h1C2, 12'hC94};
        mem[100] = {12'h193, 12'h3A8, 12'h177};
        mem[101] = {12'hB6E, 12'h1BF, 12'h9F5};
        mem[102] = {12'h402, 12'hAEA, 12'h82A};
        mem[103] = {12'h8FF, 12'h4D3, 12'h66D};
        mem[104] = {12'h477, 12'h76F, 12'h427};
        mem[105] = {12'h88A, 12'h7CC, 12'h13F};
        mem[106] = {12'h866, 12'h441, 12'hAD5};
        mem[107] = {12'h49B, 12'hCC9, 12'h2F5};
        mem[108] = {12'hAD7, 12'h11B, 12'h833};
        mem[109] = {12'h22A, 12'h73D, 12'h231};
        mem[110] = {12'h376, 12'h7C6, 12'h9A2};
        mem[111] = {12'h98B, 12'h372, 12'hA22};
        mem[112] = {12'h6BA, 12'hBD9, 12'hAF4};
        mem[113] = {12'h647, 12'h62F, 12'h444};
        mem[114] = {12'h4BC, 12'hAC8, 12'h193};
        mem[115] = {12'h845, 12'h045, 12'h402};
        mem[116] = {12'h752, 12'h21F, 12'h477};
        mem[117] = {12'h5AF, 12'h9E4, 12'h866};
        mem[118] = {12'h405, 12'hC40, 12'hAD7};
        mem[119] = {12'h8FC, 12'h582, 12'h376};
        mem[120] = {12'h83E, 12'h8DB, 12'h6BA};
        mem[121] = {12'h4C3, 12'h9B1, 12'h4BC};
        mem[122] = {12'hB77, 12'h598, 12'h752};
        mem[123] = {12'h18A, 12'hA8B, 12'h405};
        mem[124] = {12'h375, 12'h2AF, 12'h83E};
        mem[125] = {12'h98C, 12'h028, 12'hB77};
        mem[126] = {12'h86A, 12'h2ED, 12'h375};
        mem[127] = {12'h497, 12'h640, 12'h86A};
    end

endmodule