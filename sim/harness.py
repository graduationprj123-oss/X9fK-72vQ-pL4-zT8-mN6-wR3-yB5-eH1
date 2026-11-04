import sys, time, os
sys.path.insert(0, os.path.dirname(__file__)); sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../model"))
from svsim import Sim
RTL = os.path.join(os.path.dirname(__file__), "../rtl")
FILES = [l.strip() for l in open(os.path.join(RTL, "filelist.f"))
         if l.strip() and not l.strip().startswith("//")]

class Top:
    def __init__(s):
        t = time.time()
        s.sim = Sim([os.path.join(RTL, f) for f in FILES], "mlkem_axi_wrapper")
        s.cyc = 0
        for n in ("s_axi_awvalid", "s_axi_wvalid", "s_axi_arvalid", "s_axi_bready", "s_axi_rready"): s.sim.set(n, 0)
        s.sim.set("s_axi_aresetn", 0); s.clk(3); s.sim.set("s_axi_aresetn", 1); s.clk(1)
        print(f"elaborated in {time.time()-t:.1f}s: {len(s.sim.V)} signals, {len(s.sim.comb)} comb, {len(s.sim.seq)} seq")
    def clk(s, n=1):
        for _ in range(n): s.sim.step(); s.cyc += 1
    def wr(s, addr, data, strb=0xF):
        S = s.sim
        S.set("s_axi_awaddr", addr); S.set("s_axi_wdata", data); S.set("s_axi_wstrb", strb)
        S.set("s_axi_awvalid", 1); S.set("s_axi_wvalid", 1); S.set("s_axi_bready", 1)
        for _ in range(10):
            hs = S.get("s_axi_awready"); s.clk()
            if hs: break
        else: raise RuntimeError("no awready")
        S.set("s_axi_awvalid", 0); S.set("s_axi_wvalid", 0)
        for _ in range(10):
            if S.get("s_axi_bvalid"): s.clk(); break
            s.clk()
        S.set("s_axi_bready", 0)
    def rd(s, addr):
        S = s.sim
        S.set("s_axi_araddr", addr); S.set("s_axi_arvalid", 1); S.set("s_axi_rready", 1)
        for _ in range(10):
            hs = S.get("s_axi_arready"); s.clk()
            if hs: break
        else: raise RuntimeError("no arready")
        S.set("s_axi_arvalid", 0)
        for _ in range(10):
            if S.get("s_axi_rvalid"):
                v = S.get("s_axi_rdata"); s.clk(); S.set("s_axi_rready", 0); return v
            s.clk()
        raise RuntimeError("no rvalid")
    def write_bytes(s, off, b):
        for i in range(0, len(b), 4): s.wr(off + i, int.from_bytes(b[i:i+4], "little"))
    def read_bytes(s, off, n):
        return b"".join(s.rd(off + i).to_bytes(4, "little") for i in range(0, n, 4))
    def run(s, cmd, limit=400000, verbose=True):
        s.wr(0x1000, cmd); t = time.time(); c0 = s.cyc
        while not s.sim.get("irq"):
            s.clk()
            if s.cyc - c0 > limit: raise RuntimeError("timeout")
        cyc = s.rd(0x1008)
        if verbose: print(f"  cmd {cmd}: {cyc} cycles (sim {time.time()-t:.0f}s)")
        return cyc
