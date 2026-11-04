import subprocess, shutil, sys, os
MUTS = [
 ("mod_arith.sv",      "14'd5039",                     "14'd5040"),
 ("codec.sv",          "44'd2580335",                  "44'd2580336"),
 ("sponge.sv",         "st[i] <= st[i] ^ tail_word;",  "st[i] <= st[i];"),
 ("sampler.sv",        "push = (d1 < 12'd3329)",       "push = (d1 <= 12'd3329)"),
 ("mlkem_pkg.sv",      "localparam int BF_LAT   = 7;", "localparam int BF_LAT   = 6;"),
 ("bf_pwm.sv",         "u_sa3 (.clk(clk), .d(sa),    .q(sa_3));", "u_sa3 (.clk(clk), .d(sb),    .q(sa_3));"),
 ("bf_intt.sv",        "12'd1665",                     "12'd1664"),
 ("bf_ntt.sv",         "delay #(.W(12), .N(3)) u_x",  "delay #(.W(12), .N(2)) u_x"),
 ("butterfly_core.sv", "dout2 <= {intt_y1, intt_y0};", "dout2 <= {intt_y0, intt_y1};"),
 ("bf_addsub.sv",      ".d(sub ? dif : sum)",          ".d(sub ? sum : dif)"),
 ("delay.sv",          "for (int i = 1; i < N; i++)",  "for (int i = 2; i < N; i++)"),
 ("bufops.sv",         "if (is_cmp && (va != b_rdata)) flag <= 1'b1;", "if (1'b0) flag <= 1'b1;"),
 ("poly_alu.sv",       "if (drain_cnt == 4'(ALU_LAT - 1)) begin", "if (drain_cnt == 4'(ALU_LAT - 2)) begin"),
]
for f, a, b in MUTS:
    p = next(os.path.join("rtl", l.strip()) for l in open("rtl/filelist.f") if l.strip().endswith("/" + f)); src = open(p).read(); assert a in src, (f, a)
    shutil.copy(p, p + ".bak"); open(p, "w").write(src.replace(a, b, 1))
    try:
        r = subprocess.run([sys.executable, "sim/run_kat.py", "full"], capture_output=True, text=True, timeout=900)
        out = r.stdout + r.stderr
        verdict = "caught" if ("FAIL" in out or "Error" in out or "timeout" in out) else "MISSED"
        print(f"{verdict:7s} {f}: {a[:40]!r}  -> {out.strip().splitlines()[-1][:90]}")
    finally:
        shutil.move(p + ".bak", p)
