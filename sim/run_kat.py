import sys, os, harness, ref_mlkem as R, isa
def trace_on(t):
    S = t.sim; pcid = S.names["u_core.pc"]; last = [None]
    orig = S.step
    def step():
        orig()
        pc = S.V[pcid]
        if pc != last[0]: last[0] = pc; print(f"    cyc {t.cyc:6d} pc {pc}")
    S.step = step

def keygen(t, d, z):
    t.write_bytes(isa.D_SEED * 8, d); t.write_bytes(isa.Z * 8, z)
    c = t.run(1); return t.read_bytes(isa.EK * 8, 800), t.read_bytes(0, 1632), c
def encaps(t, ek, m):
    t.write_bytes(isa.EK * 8, ek); t.write_bytes(isa.MSG * 8, m)
    c = t.run(2); return t.read_bytes(isa.KR * 8, 32), t.read_bytes(isa.CT * 8, 768), c
def decaps(t, dk, ct):
    t.write_bytes(0, dk); t.write_bytes(isa.CT * 8, ct)
    c = t.run(3); return t.read_bytes(isa.KR * 8, 32), c

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "keygen"
    seed = (3).to_bytes(32, "little") if "-q" in sys.argv else bytes(range(32)); z = bytes(range(32, 64)); m = bytes(range(64, 96))
    t = harness.Top()
    if "-t" in sys.argv: trace_on(t)
    ek_r, dk_r = R.keygen(seed, z)
    if which == "keygen":
        ek, dk, c = keygen(t, seed, z)
        print("ek match:", ek == ek_r, " dk match:", dk == dk_r)
        if dk != dk_r:
            for name, a, b in (("s^", dk[:768], dk_r[:768]), ("ek", dk[768:1568], dk_r[768:1568]), ("h", dk[1568:1600], dk_r[1568:1600])):
                print("  ", name, a == b, a[:16].hex(), b[:16].hex())

def full(t, seed, z, m, verbose=True):
    ek_r, dk_r = R.keygen(seed, z); K_r, ct_r = R.encaps(ek_r, m)
    ek, dk, c1 = keygen(t, seed, z)
    K, ct, c2 = encaps(t, ek_r, m)
    K2, c3 = decaps(t, dk_r, ct_r)
    bad = bytearray(ct_r); bad[(seed[0] * 7) % 768] ^= 1 << (seed[1] % 8); bad = bytes(bad)
    K3, c4 = decaps(t, dk_r, bad)
    res = dict(keygen=(ek, dk) == (ek_r, dk_r), encaps=(K, ct) == (K_r, ct_r), decaps=K2 == K_r,
               reject=K3 == R.decaps(dk_r, bad) and K3 != K_r)
    return res, (c1, c2, c3, c4)

if __name__ == "__main__" and which == "full":
    import os as _o
    ok = True
    for i in range(int(sys.argv[2]) if len(sys.argv) > 2 else 1):
        s, zz, mm = (_o.urandom(32) for _ in range(3)) if i else (seed, z, m)
        res, cyc = full(t, s, zz, mm)
        print(f"run {i}: {res}  cycles {cyc}"); ok &= all(res.values())
    print("ALL PASS" if ok else "FAIL")
