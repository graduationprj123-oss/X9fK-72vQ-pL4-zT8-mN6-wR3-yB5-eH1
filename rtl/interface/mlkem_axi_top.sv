// ============================================================================
// mlkem_axi_top.sv
// ML-KEM-512 accelerator for Zynq-7000 PL, AXI4-Lite slave (32-bit, 8 KB).
//
// Address map (byte offsets from the AXI base address):
//   0x0000 - 0x0FFF : I/O buffer (keys / ciphertext / seeds), see mlkem_pkg
//   0x1000  CTRL   (W) : bits[1:0] = 1 KeyGen, 2 Encaps, 3 Decaps -> start
//                  (R) : last command
//   0x1004  STATUS (R) : bit0 busy, bit1 done (sticky, cleared by a new start)
//   0x1008  CYCLES (R) : clock cycles taken by the last command
//   0x100C  ID     (R) : 0x4D4C4B35 ("MLK5")
//   irq = STATUS.done (level)
// The buffer must only be accessed while busy = 0.
// ============================================================================
module mlkem_axi_top
    import mlkem_pkg::*;
(
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,
    // write address / data / response
    input  logic [12:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    // read address / data
    input  logic [12:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,
    // interrupt to PS (IRQ_F2P)
    output logic        irq
);

    logic clk, rst_n;
    assign clk   = s_axi_aclk;
    assign rst_n = s_axi_aresetn;

    // ---------------- core + buffer ----------------------------------------
    logic        core_start, core_busy, core_done;
    logic [1:0]  cmd_q;
    logic        done_q;
    logic [31:0] cycles_q;

    logic [7:0]  ba_be;
    logic [8:0]  ba_addr;
    logic [63:0] ba_din, ba_dout;
    logic [8:0]  bb_addr;
    logic        bb_we;
    logic [63:0] bb_wdata, bb_rdata;

    io_buffer u_buf (
        .clk    (clk),
        .be_a   (ba_be),
        .addr_a (ba_addr),
        .din_a  (ba_din),
        .dout_a (ba_dout),
        .we_b   (bb_we),
        .addr_b (bb_addr),
        .din_b  (bb_wdata),
        .dout_b (bb_rdata)
    );

    mlkem_core u_core (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (core_start),
        .cmd     (cmd_q),
        .busy    (core_busy),
        .done    (core_done),
        .b_addr  (bb_addr),
        .b_we    (bb_we),
        .b_wdata (bb_wdata),
        .b_rdata (bb_rdata)
    );

    // ---------------- AXI write --------------------------------------------
    logic wr_hs, wr_reg;
    assign wr_hs         = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    assign s_axi_awready = wr_hs;
    assign s_axi_wready  = wr_hs;
    assign s_axi_bresp   = 2'b00;
    assign wr_reg        = s_axi_awaddr[12];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            core_start   <= 1'b0;
            cmd_q        <= 2'd0;
        end else begin
            core_start <= 1'b0;
            if (wr_hs) begin
                s_axi_bvalid <= 1'b1;
                if (wr_reg && s_axi_awaddr[3:2] == 2'd0 && s_axi_wstrb[0] &&
                    !core_busy && s_axi_wdata[1:0] != 2'd0) begin
                    cmd_q      <= s_axi_wdata[1:0];
                    core_start <= 1'b1;
                end
            end else if (s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ---------------- AXI read ---------------------------------------------
    logic       rd_hs, rd_pend, rd_reg_q, rd_hi_q;
    logic [1:0] rd_sel_q;
    assign rd_hs         = s_axi_arvalid && !s_axi_rvalid && !rd_pend && !wr_hs;
    assign s_axi_arready = rd_hs;
    assign s_axi_rresp   = 2'b00;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_pend      <= 1'b0;
            s_axi_rvalid <= 1'b0;
        end else begin
            if (rd_hs) begin                       // buffer read issued this cycle
                rd_pend  <= 1'b1;
                rd_reg_q <= s_axi_araddr[12];
                rd_hi_q  <= s_axi_araddr[2];
                rd_sel_q <= s_axi_araddr[3:2];
            end else if (rd_pend) begin            // buffer data valid
                rd_pend      <= 1'b0;
                s_axi_rvalid <= 1'b1;
                if (rd_reg_q) begin
                    case (rd_sel_q)
                        2'd0:    s_axi_rdata <= {30'd0, cmd_q};
                        2'd1:    s_axi_rdata <= {30'd0, done_q, core_busy};
                        2'd2:    s_axi_rdata <= cycles_q;
                        default: s_axi_rdata <= 32'h4D4C4B35;
                    endcase
                end else begin
                    s_axi_rdata <= rd_hi_q ? ba_dout[63:32] : ba_dout[31:0];
                end
            end else if (s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // buffer port A : write has priority (reads wait one cycle)
    assign ba_addr = wr_hs ? s_axi_awaddr[11:3] : s_axi_araddr[11:3];
    assign ba_din  = {s_axi_wdata, s_axi_wdata};
    assign ba_be   = (wr_hs && !wr_reg) ? (s_axi_awaddr[2] ? {s_axi_wstrb, 4'b0000}
                                                           : {4'b0000, s_axi_wstrb})
                                        : 8'h00;

    // ---------------- status -----------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            done_q   <= 1'b0;
            cycles_q <= '0;
        end else begin
            if (core_start)     begin done_q <= 1'b0; cycles_q <= '0; end
            else if (core_done) done_q <= 1'b1;
            else if (core_busy) cycles_q <= cycles_q + 32'd1;
        end
    end

    assign irq = done_q;

endmodule
