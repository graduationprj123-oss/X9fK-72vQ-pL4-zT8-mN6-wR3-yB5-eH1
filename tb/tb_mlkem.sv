// ============================================================================
// tb_mlkem.sv  -  self-checking testbench (Vivado xsim / Questa)
// Drives the AXI4-Lite port exactly like the PS would, runs
// KeyGen -> Encaps -> Decaps -> Decaps(tampered ct) for every vector set in
// tb_vectors_pkg and compares against the FIPS 203 reference results.
// Expected console end: "*** ALL TESTS PASSED ***"
// ============================================================================
`timescale 1ns / 1ps

module tb_mlkem;
    import tb_vectors_pkg::*;

    // byte offsets in the I/O buffer (lane * 8)
    localparam int A_DK   = 0;
    localparam int A_EK   = 96  * 8;
    localparam int A_CT   = 204 * 8;
    localparam int A_D    = 396 * 8;
    localparam int A_Z    = 200 * 8;
    localparam int A_MSG  = 400 * 8;
    localparam int A_K    = 404 * 8;
    localparam int R_CTRL = 13'h1000, R_STATUS = 13'h1004, R_CYCLES = 13'h1008, R_ID = 13'h100C;

    logic        clk = 1'b0, rstn = 1'b0;
    always #5 clk = ~clk;                          // 100 MHz

    logic [12:0] awaddr = '0, araddr = '0;
    logic        awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
    logic [31:0] wdata = '0;
    logic [3:0]  wstrb = '0;
    logic        awready, wready, bvalid, arready, rvalid, irq;
    logic [1:0]  bresp, rresp;
    logic [31:0] rdata;

    mlkem_axi_wrapper dut (
        .s_axi_aclk    (clk),     .s_axi_aresetn (rstn),
        .s_axi_awaddr  (awaddr),  .s_axi_awprot  (3'b000),
        .s_axi_awvalid (awvalid), .s_axi_awready (awready),
        .s_axi_wdata   (wdata),   .s_axi_wstrb   (wstrb),
        .s_axi_wvalid  (wvalid),  .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),   .s_axi_bvalid  (bvalid),  .s_axi_bready (bready),
        .s_axi_araddr  (araddr),  .s_axi_arprot  (3'b000),
        .s_axi_arvalid (arvalid), .s_axi_arready (arready),
        .s_axi_rdata   (rdata),   .s_axi_rresp   (rresp),
        .s_axi_rvalid  (rvalid),  .s_axi_rready  (rready),
        .irq           (irq)
    );

    // ---------------- AXI4-Lite master tasks (drive on negedge) -------------
    task automatic axi_write(input logic [12:0] a, input logic [31:0] d);
        @(negedge clk);
        awaddr = a; wdata = d; wstrb = 4'hF; awvalid = 1; wvalid = 1;
        while (!awready) @(negedge clk);           // transfer on the next posedge
        @(negedge clk);
        awvalid = 0; wvalid = 0;
        while (bvalid) @(negedge clk);             // response accepted (bready = 1)
    endtask

    task automatic axi_read(input logic [12:0] a, output logic [31:0] d);
        @(negedge clk);
        araddr = a; arvalid = 1;
        while (!arready) @(negedge clk);
        @(negedge clk);
        arvalid = 0;
        while (!rvalid) @(negedge clk);
        d = rdata;
        @(negedge clk);                            // rvalid drops (rready = 1)
    endtask

    task automatic put_bytes(input int off, input logic [7:0] b []);
        for (int i = 0; i < b.size(); i += 4)
            axi_write(13'(off + i), {b[i+3], b[i+2], b[i+1], b[i]});
    endtask

    int errors = 0;

    task automatic check_bytes(input string what, input int off, input logic [7:0] exp []);
        logic [31:0] w;
        int bad = 0;
        for (int i = 0; i < exp.size(); i += 4) begin
            axi_read(13'(off + i), w);
            for (int k = 0; k < 4; k++)
                if (w[8*k +: 8] !== exp[i+k]) begin
                    if (bad < 4) $display("    %s byte %0d: got %02h expected %02h", what, i+k, w[8*k +: 8], exp[i+k]);
                    bad++;
                end
        end
        if (bad == 0) $display("    %-10s OK   (%0d bytes)", what, exp.size());
        else begin $display("    %-10s FAIL (%0d wrong bytes)", what, bad); errors++; end
    endtask

    task automatic run_cmd(input int cmd, input string name);
        logic [31:0] cyc;
        axi_write(R_CTRL, cmd);
        @(posedge clk);
        while (!irq) @(posedge clk);
        axi_read(R_CYCLES, cyc);
        $display("  %-8s done in %0d cycles (%0.1f us @100 MHz)", name, cyc, cyc / 100.0);
    endtask

    // ---------------- test sequence -----------------------------------------
    task automatic run_case(input int c,
                            input logic [7:0] d [], input logic [7:0] z [], input logic [7:0] m [],
                            input logic [7:0] ek [], input logic [7:0] dk [], input logic [7:0] ct [],
                            input logic [7:0] k [], input logic [7:0] ctbad [], input logic [7:0] kbar []);
        $display("--- vector set %0d ---", c);
        // KeyGen
        put_bytes(A_D, d);  put_bytes(A_Z, z);
        run_cmd(1, "KeyGen");
        check_bytes("ek", A_EK, ek);
        check_bytes("dk", A_DK, dk);
        // Encaps (fresh ek from the vector)
        put_bytes(A_EK, ek); put_bytes(A_MSG, m);
        run_cmd(2, "Encaps");
        check_bytes("ct", A_CT, ct);
        check_bytes("K", A_K, k);
        // Decaps, valid ciphertext
        put_bytes(A_DK, dk); put_bytes(A_CT, ct);
        run_cmd(3, "Decaps");
        check_bytes("K", A_K, k);
        // Decaps, tampered ciphertext -> implicit rejection key
        put_bytes(A_DK, dk); put_bytes(A_CT, ctbad);
        run_cmd(3, "Decaps*");
        check_bytes("K-bar", A_K, kbar);
    endtask

    initial begin
        logic [31:0] id;
        repeat (5) @(posedge clk);
        rstn = 1'b1;
        repeat (2) @(posedge clk);
        axi_read(R_ID, id);
        $display("ID = %08h", id);
        if (id !== 32'h4D4C4B35) begin $display("bad ID"); errors++; end

        run_case(0, D0, Z0, M0, EK0, DK0, CT0, K0, CTBAD0, KBAR0);
        run_case(1, D1, Z1, M1, EK1, DK1, CT1, K1, CTBAD1, KBAR1);

        if (errors == 0) $display("*** ALL TESTS PASSED ***");
        else             $display("*** %0d CHECKS FAILED ***", errors);
        $finish;
    end

    initial begin
        #50ms;
        $display("*** TIMEOUT ***");
        $finish;
    end

endmodule
