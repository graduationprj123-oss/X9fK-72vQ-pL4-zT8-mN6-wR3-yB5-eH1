"""ISA + memory map + program generator for the ML-KEM-512 sequencer."""
# ------------------------------------------------------------------ opcodes
OPS = ["END", "HINIT", "ABSORB", "FINAL", "SQUEEZE", "SNTT", "SCBD", "NTT", "INTT",
       "PWM", "ADD", "SUB", "ENC", "DEC", "CMP", "CSEL"]
OPC = {n: i for i, n in enumerate(OPS)}
# hash modes
SHA3_256, SHA3_512, SHAKE128, SHAKE256 = 0, 1, 2, 3

# ------------------------------------------------------------------ buffer map (64-bit lanes)
DK, EK, HEK, Z = 0, 96, 196, 200        # dk = s^(0..95) | ek(96..195) | H(ek) | z
RHO = EK + 96                           # 192
CT, CT2 = 204, 300                      # c1 (u0 204, u1 244), c2 (v 284)
D_SEED, MSG, KR, SIGMA, KBAR = 396, 400, 404, 412, 420   # K = KR[0..3], r = KR[4..7]
BUF_LANES = 512

# ------------------------------------------------------------------ poly slots
SA, SP, S0, S1, E0, E1, T0, T1, U0, U1, SV, SE2, SW = range(13)

class Prog:
    def __init__(s): s.ins = []
    def emit(s, op, sa=0, sb=0, sd=0, la=0, lb=0, n=0, imm=0, cmt=""):
        s.ins.append(dict(op=op, sa=sa, sb=sb, sd=sd, la=la, lb=lb, n=n, imm=imm, cmt=cmt))
    # -- helpers
    def hash_(s, mode, segs, tail=b"", outs=(), cmt=""):
        s.emit("HINIT", imm=mode, cmt=cmt)
        for la, n in segs: s.emit("ABSORB", la=la, n=n)
        s.emit("FINAL", n=len(tail), imm=int.from_bytes(tail, "little"))
        for la, n in outs: s.emit("SQUEEZE", la=la, n=n)
    def cbd(s, slot, seed_lane, nonce, eta):
        s.hash_(SHAKE256, [(seed_lane, 4)], bytes([nonce]), cmt=f"PRF(seed,{nonce}) -> CBD{eta}")
        s.emit("SCBD", sd=slot, imm=eta)
    def gen_a(s, slot, b0, b1):
        s.hash_(SHAKE128, [(RHO, 4)], bytes([b0, b1]), cmt=f"XOF(rho,{b0},{b1}) -> SampleNTT")
        s.emit("SNTT", sd=slot)

def encrypt(p, rlane, ct):
    """K-PKE.Encrypt using ek in buffer (EK), m in MSG, randomness r at rlane; writes ct."""
    p.emit("DEC", sd=T0, la=EK, imm=12, cmt="t^0 = ByteDecode12(ek)")
    p.emit("DEC", sd=T1, la=EK + 48, imm=12)
    p.cbd(S0, rlane, 0, 3); p.cbd(S1, rlane, 1, 3)            # y
    p.cbd(E0, rlane, 2, 2); p.cbd(E1, rlane, 3, 2)            # e1
    p.cbd(SE2, rlane, 4, 2)                                   # e2
    p.emit("NTT", sd=S0); p.emit("NTT", sd=S1)
    for i, (u, e) in enumerate(((U0, E0), (U1, E1))):
        for j, y in enumerate((S0, S1)):
            p.gen_a(SA, i, j)                                 # A[j][i] = XOF(rho, i, j)
            p.emit("PWM", sa=SA, sb=y, sd=(u if j == 0 else SP))
            if j: p.emit("ADD", sa=u, sb=SP, sd=u)
        p.emit("INTT", sd=u); p.emit("ADD", sa=u, sb=e, sd=u)
        p.emit("ENC", sa=u, la=ct + 40 * i, imm=10, cmt=f"c1[{i}] = Compress10(u{i})")
    p.emit("PWM", sa=T0, sb=S0, sd=SV); p.emit("PWM", sa=T1, sb=S1, sd=SP)
    p.emit("ADD", sa=SV, sb=SP, sd=SV); p.emit("INTT", sd=SV)
    p.emit("ADD", sa=SV, sb=SE2, sd=SV)
    p.emit("DEC", sd=SW, la=MSG, imm=1, cmt="mu = Decompress1(m)")
    p.emit("ADD", sa=SV, sb=SW, sd=SV)
    p.emit("ENC", sa=SV, la=ct + 80, imm=4, cmt="c2 = Compress4(v)")

def prog_keygen():
    p = Prog()
    p.hash_(SHA3_512, [(D_SEED, 4)], bytes([2]), outs=[(RHO, 4), (SIGMA, 4)], cmt="(rho,sigma) = G(d||k)")
    p.cbd(S0, SIGMA, 0, 3); p.cbd(S1, SIGMA, 1, 3)
    p.cbd(E0, SIGMA, 2, 3); p.cbd(E1, SIGMA, 3, 3)
    for s in (S0, S1, E0, E1): p.emit("NTT", sd=s)
    for i, (t, e) in enumerate(((T0, E0), (T1, E1))):
        for j, sv in enumerate((S0, S1)):
            p.gen_a(SA, j, i)                                 # A[i][j] = XOF(rho, j, i)
            p.emit("PWM", sa=SA, sb=sv, sd=(t if j == 0 else SP))
            if j: p.emit("ADD", sa=t, sb=SP, sd=t)
        p.emit("ADD", sa=t, sb=e, sd=t)
    p.emit("ENC", sa=T0, la=EK, imm=12, cmt="ek = t^ | rho");  p.emit("ENC", sa=T1, la=EK + 48, imm=12)
    p.emit("ENC", sa=S0, la=DK, imm=12, cmt="dk_pke = s^");    p.emit("ENC", sa=S1, la=DK + 48, imm=12)
    p.hash_(SHA3_256, [(EK, 100)], outs=[(HEK, 4)], cmt="H(ek)")
    p.emit("END"); return p

def prog_encaps():
    p = Prog()
    p.hash_(SHA3_256, [(EK, 100)], outs=[(HEK, 4)], cmt="H(ek)")
    p.hash_(SHA3_512, [(MSG, 4), (HEK, 4)], outs=[(KR, 8)], cmt="(K,r) = G(m||H(ek))")
    encrypt(p, KR + 4, CT)
    p.emit("END"); return p

def prog_decaps():
    p = Prog()
    p.emit("DEC", sd=S0, la=DK, imm=12, cmt="s^ = ByteDecode12(dk_pke)")
    p.emit("DEC", sd=S1, la=DK + 48, imm=12)
    p.emit("DEC", sd=U0, la=CT, imm=10, cmt="u' = Decompress10(c1)")
    p.emit("DEC", sd=U1, la=CT + 40, imm=10)
    p.emit("DEC", sd=SV, la=CT + 80, imm=4, cmt="v' = Decompress4(c2)")
    p.emit("NTT", sd=U0); p.emit("NTT", sd=U1)
    p.emit("PWM", sa=S0, sb=U0, sd=SW); p.emit("PWM", sa=S1, sb=U1, sd=SP)
    p.emit("ADD", sa=SW, sb=SP, sd=SW); p.emit("INTT", sd=SW)
    p.emit("SUB", sa=SV, sb=SW, sd=SW, cmt="w = v' - INTT(s^ o NTT(u'))")
    p.emit("ENC", sa=SW, la=MSG, imm=1, cmt="m' = Compress1(w)")
    p.hash_(SHA3_512, [(MSG, 4), (HEK, 4)], outs=[(KR, 8)], cmt="(K',r') = G(m'||h)")
    p.hash_(SHAKE256, [(Z, 4), (CT, 96)], outs=[(KBAR, 4)], cmt="Kbar = J(z||c)")
    encrypt(p, KR + 4, CT2)
    p.emit("CMP", la=CT, lb=CT2, n=96, cmt="c == c' ?")
    p.emit("CSEL", la=KR, lb=KBAR, n=4, cmt="K = mismatch ? Kbar : K'")
    p.emit("END"); return p

PROGRAMS = {"keygen": prog_keygen, "encaps": prog_encaps, "decaps": prog_decaps}
