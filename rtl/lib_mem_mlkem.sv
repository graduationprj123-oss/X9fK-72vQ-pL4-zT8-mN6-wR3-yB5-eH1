`timescale 1ns / 1ps

// Generic single-port synchronous-read RAM.
// Read data updates on the rising edge when en_read is asserted.
module RAM #(
    parameter int unsigned SIZE  = 64,
    parameter int unsigned WIDTH = 32,
    localparam int unsigned ADDR_WIDTH = (SIZE <= 1) ? 1 : $clog2(SIZE)
) (
    input  logic                  clk,
    input  logic                  en_write,
    input  logic                  en_read,
    input  logic [ADDR_WIDTH-1:0] addr_write,
    input  logic [ADDR_WIDTH-1:0] addr_read,
    input  logic [WIDTH-1:0]      data_in,
    output logic [WIDTH-1:0]      data_out
);

    logic [WIDTH-1:0] mem [0:SIZE-1];

    always_ff @(posedge clk) begin
        if (en_write)
            mem[addr_write] <= data_in;
    end

    always_ff @(posedge clk) begin
        if (en_read)
            data_out <= mem[addr_read];
    end

endmodule


// Two-port RAM with one address/data port per side.
// Each port writes when its enable is asserted and reads every clock.
// If both ports write the same address on the same edge, the result is
// implementation-dependent; avoid that condition in the surrounding design.
module RAM_DUAL #(
    parameter int unsigned SIZE  = 51200 / 32,
    parameter int unsigned WIDTH = 32,
    localparam int unsigned ADDR_WIDTH = (SIZE <= 1) ? 1 : $clog2(SIZE)
) (
    input  logic                  clk,
    input  logic                  enable_1,
    input  logic                  enable_2,
    input  logic [ADDR_WIDTH-1:0] addr_1,
    input  logic [ADDR_WIDTH-1:0] addr_2,
    input  logic [WIDTH-1:0]      data_in_1,
    input  logic [WIDTH-1:0]      data_in_2,
    output logic [WIDTH-1:0]      data_out_1,
    output logic [WIDTH-1:0]      data_out_2
);

    logic [WIDTH-1:0] mem [0:SIZE-1];

    always_ff @(posedge clk) begin
        if (enable_1)
            mem[addr_1] <= data_in_1;
        if (enable_2)
            mem[addr_2] <= data_in_2;

        data_out_1 <= mem[addr_1];
        data_out_2 <= mem[addr_2];
    end

endmodule


// 32-word, 32-bit RAM with asynchronous read.
module RAMD (
    input  logic        clk,
    input  logic        en_w,
    input  logic [4:0]  add_w,
    input  logic [4:0]  add_r,
    input  logic [31:0] d_i,
    output logic [31:0] d_o
);

    logic [31:0] reg_mem [0:31];

    assign d_o = reg_mem[add_r];

    always_ff @(posedge clk) begin
        if (en_w)
            reg_mem[add_w] <= d_i;
    end

endmodule


// 32-word, 64-bit RAM built from two 32-bit RAMD instances.
module RAMD64 (
    input  logic        clk,
    input  logic        en_w,
    input  logic [4:0]  add_w,
    input  logic [4:0]  add_r,
    input  logic [63:0] d_i,
    output logic [63:0] d_o
);

    RAMD ramd_low (
        .clk   (clk),
        .en_w  (en_w),
        .add_w (add_w),
        .add_r (add_r),
        .d_i   (d_i[31:0]),
        .d_o   (d_o[31:0])
    );

    RAMD ramd_high (
        .clk   (clk),
        .en_w  (en_w),
        .add_w (add_w),
        .add_r (add_r),
        .d_i   (d_i[63:32]),
        .d_o   (d_o[63:32])
    );

endmodule


// ROWS banks, each containing 32 words of COLS * 64 bits.
// Each bank is built from COLS instances of RAMD64.
// Address bits [4:0] select a word within a bank; upper bits select the bank.
module RAMD64_CR #(
    parameter int unsigned COLS = 17,
    parameter int unsigned ROWS = 1,
    localparam int unsigned DEPTH = ROWS * 32,
    localparam int unsigned ADDR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
) (
    input  logic                      clk,
    input  logic                      en_w,
    input  logic [ADDR_WIDTH-1:0]     add_w,
    input  logic [ADDR_WIDTH-1:0]     add_r,
    input  logic [COLS*64-1:0]        d_i,
    output logic [COLS*64-1:0]        d_o
);

    logic [COLS*64-1:0] row_data [0:ROWS-1];

    genvar r;
    genvar c;
    generate
        for (r = 0; r < ROWS; r++) begin : gen_row
            wire row_write_enable;

            if (ROWS == 1) begin : gen_single_row
                assign row_write_enable = en_w;
            end else begin : gen_multiple_rows
                assign row_write_enable = en_w && (add_w[ADDR_WIDTH-1:5] == r);
            end

            for (c = 0; c < COLS; c++) begin : gen_col
                RAMD64 ramd64_inst (
                    .clk   (clk),
                    .en_w  (row_write_enable),
                    .add_w (add_w[4:0]),
                    .add_r (add_r[4:0]),
                    .d_i   (d_i[c*64 +: 64]),
                    .d_o   (row_data[r][c*64 +: 64])
                );
            end
        end
    endgenerate

    // Select the row/bank using the upper address bits.
    always_comb begin
        if (ROWS == 1)
            d_o = row_data[0];
        else
            d_o = row_data[add_r[ADDR_WIDTH-1:5]];
    end

endmodule
