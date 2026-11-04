"""Functional, bit-exact model of the hardware executing the microprogram."""
import isa, ref_mlkem as R
Q = 3329; M64 = (1 << 64) - 1

# ---------------- Keccak-f[1600] (lanes x + 5y)
RC = []
def _rc():
    r = 1; out = []
    for _ in range(24):
        v = 0
        for j in range(7):
            if r & 1: v |= 1 << ((1 << j) - 1)
            r = ((r << 1) ^ 0x71) & 0xFF if r & 0x80 else (r << 1)
        out.append(v)
    return out
RC = _rc()
ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]  # ROT[x][y]
rol = lambda v, n: ((v << n) | (v >> (64 - n))) & M64 if n else v
def keccak_round(A, rc):
    C = [A[x] ^ A[x+5] ^ A[x+10] ^ A[x+15] ^ A[x+20] for x in range(5)]
    D = [C[(x-1) % 5] ^ rol(C[(x+1) % 5], 1) for x in range(5)]
    A = [A[i] ^ D[i % 5] for i in range(25)]
    B = [0] * 25
    for x in range(5):
        for y in range(5): B[y + 5*((2*x + 3*y) % 5)] = rol(A[x + 5*y], ROT[x][y])
    A = [B[i] ^ ((~B[(i % 5 + 1) % 5 + 5*(i//5)]) & B[(i % 5 + 2) % 5 + 5*(i//5)]) & M64 for i in range(25)]
    A[0] ^= rc; return A
def keccak_f(A):
    for r in range(24): A = keccak_round(A, RC[r])
    return A

RATE = {isa.SHA3_256: 17, isa.SHA3_512: 9, isa.SHAKE128: 21, isa.SHAKE256: 17}
SUFFIX = {isa.SHA3_256: 0x06, isa.SHA3_512: 0x06, isa.SHAKE128: 0x1F, isa.SHAKE256: 0x1F}

# ---------------- hardware arithmetic formulas
COMP_M, COMP_S = None, None
def find_magic():
    nmax = (3328 << 10) + 1664
    for s in range(20, 40):
        m = -(-(1 << s) // Q)
        if all((n * m) >> s == n // Q for n in range(nmax - 20000, nmax + 1)) and \
           all((n * m) >> s == n // Q for n in range(0, nmax + 1, 7)):
            return m, s
COMP_M, COMP_S = 2580335, 33   # floor(n/3329) for n < 2^22, checked exhaustively
def hw_compress(x, d):  return ((((x << d) + 1664) * COMP_M) >> COMP_S) & ((1 << d) - 1)
def hw_decompress(y, d): return (y * Q + (1 << (d - 1))) >> d
def hw_mulmod(a, b):
    c = a * b; t = (c * 5039) >> 24; r = c - t * Q
    return r - Q if r >= Q else r

def check_formulas():
    for n in range((3328 << 10) + 1665):
        assert (n * COMP_M) >> COMP_S == n // Q, n
    for d in (1, 4, 10):
        for x in range(Q): assert hw_compress(x, d) == R.compress(x, d)
        for y in range(1 << d): assert hw_decompress(y, d) == R.decompress(y, d)
    import random
    for _ in range(300000):
        a, b = random.randrange(Q), random.randrange(Q); assert hw_mulmod(a, b) == a * b % Q
    for a in (0, 1, Q - 1):
        for b in range(Q): assert hw_mulmod(a, b) == a * b % Q
    print("formulas OK")

# ---------------- machine
class Machine:
    def __init__(s):
        s.buf = [0] * isa.BUF_LANES; s.poly = [[0] * 256 for _ in range(16)]
        s.st = [0] * 25; s.flag = 0
    def bytes_in(s, lane, b):
        for i in range(0, len(b), 8): s.buf[lane + i // 8] = int.from_bytes(b[i:i+8], "little")
    def bytes_out(s, lane, n):
        return b"".join(s.buf[lane + i].to_bytes(8, "little") for i in range(n // 8))
    def stream(s):
        while True:
            if s.sq == s.rate * 8: s.st = keccak_f(s.st); s.sq = 0
            b = (s.st[s.sq // 8] >> (8 * (s.sq % 8))) & 0xFF; s.sq += 1
            yield b
    def run(s, prog):
        for ins in prog.ins:
            op, sa, sb, sd, la, lb, n, imm = (ins[k] for k in ("op", "sa", "sb", "sd", "la", "lb", "n", "imm"))
            if op == "END": return
            elif op == "HINIT": s.st = [0] * 25; s.pos = 0; s.rate = RATE[imm]; s.suf = SUFFIX[imm]
            elif op == "ABSORB":
                for i in range(n):
                    s.st[s.pos] ^= s.buf[la + i]; s.pos += 1
                    if s.pos == s.rate: s.st = keccak_f(s.st); s.pos = 0
            elif op == "FINAL":
                s.st[s.pos] ^= (imm & ((1 << 8 * n) - 1)) | (s.suf << (8 * n))
                s.st[s.rate - 1] ^= 0x80 << 56
                s.st = keccak_f(s.st); s.sq = 0
            elif op == "SQUEEZE":
                for i in range(n):
                    if s.sq == s.rate * 8: s.st = keccak_f(s.st); s.sq = 0
                    s.buf[la + i] = s.st[s.sq // 8]; s.sq += 8
            elif op == "SNTT":
                g = s.stream(); out = []
                while len(out) < 256:
                    b0, b1, b2 = next(g), next(g), next(g)
                    for d in (b0 | (b1 & 15) << 8, b1 >> 4 | b2 << 4):
                        if d < Q and len(out) < 256: out.append(d)
                s.poly[sd] = out
            elif op == "SCBD":
                g = s.stream(); bits = []
                for _ in range(64 * imm):
                    b = next(g); bits += [(b >> i) & 1 for i in range(8)]
                s.poly[sd] = R.sample_cbd(bytes(sum(bits[8*i+j] << j for j in range(8)) for i in range(64*imm)), imm)
            elif op == "NTT":  s.poly[sd] = R.ntt(s.poly[sd])
            elif op == "INTT": s.poly[sd] = R.intt(s.poly[sd])
            elif op == "PWM":  s.poly[sd] = R.mul_ntt(s.poly[sa], s.poly[sb])
            elif op == "ADD":  s.poly[sd] = R.add(s.poly[sa], s.poly[sb])
            elif op == "SUB":  s.poly[sd] = R.sub(s.poly[sa], s.poly[sb])
            elif op == "ENC":
                d = imm; vals = s.poly[sa] if d == 12 else [hw_compress(x, d) for x in s.poly[sa]]
                bitbuf, cnt, lane = 0, 0, la
                for v in vals:
                    bitbuf |= v << cnt; cnt += d
                    if cnt >= 64: s.buf[lane] = bitbuf & M64; lane += 1; bitbuf >>= 64; cnt -= 64
                assert cnt == 0
            elif op == "DEC":
                d = imm; out = []; bitbuf, cnt, lane = 0, 0, la
                for _ in range(256):
                    if cnt < d: bitbuf |= s.buf[lane] << cnt; lane += 1; cnt += 64
                    v = bitbuf & ((1 << d) - 1); bitbuf >>= d; cnt -= d
                    out.append((v - Q if v >= Q else v) if d == 12 else hw_decompress(v, d))
                s.poly[sd] = out
            elif op == "CMP":  s.flag = int(any(s.buf[la+i] != s.buf[lb+i] for i in range(n)))
            elif op == "CSEL":
                for i in range(n):
                    if s.flag: s.buf[la + i] = s.buf[lb + i]
            else: raise ValueError(op)

def hw_keygen(d, z):
    m = Machine(); m.bytes_in(isa.D_SEED, d); m.bytes_in(isa.Z, z); m.run(isa.prog_keygen())
    return m.bytes_out(isa.EK, 800), m.bytes_out(isa.DK, 1632)
def hw_encaps(ek, msg):
    m = Machine(); m.bytes_in(isa.EK, ek); m.bytes_in(isa.MSG, msg); m.run(isa.prog_encaps())
    return m.bytes_out(isa.KR, 32), m.bytes_out(isa.CT, 768)
def hw_decaps(dk, c):
    m = Machine(); m.bytes_in(isa.DK, dk); m.bytes_in(isa.CT, c); m.run(isa.prog_decaps())
    return m.bytes_out(isa.KR, 32)

if __name__ == "__main__":
    import os, hashlib
    # keccak self-check vs hashlib
    st = [0]*25; st[0] ^= 0x06; st[16] ^= 0x80 << 56; st = keccak_f(st)
    assert b"".join(x.to_bytes(8, "little") for x in st[:4]) == hashlib.sha3_256(b"").digest()
    check_formulas()
    for t in range(4):
        d, z, msg = os.urandom(32), os.urandom(32), os.urandom(32)
        ek, dk = hw_keygen(d, z);  assert (ek, dk) == R.keygen(d, z)
        Kk, c = hw_encaps(ek, msg); assert (Kk, c) == R.encaps(ek, msg)
        assert hw_decaps(dk, c) == Kk == R.decaps(dk, c)
        bad = bytearray(c); bad[t * 100] ^= 0x10; bad = bytes(bad)
        assert hw_decaps(bad and dk, bad) == R.decaps(dk, bad) != Kk
    print("architecture model == reference")
