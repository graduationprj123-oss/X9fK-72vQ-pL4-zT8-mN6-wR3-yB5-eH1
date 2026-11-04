"""Independent ML-KEM-512 reference (FIPS 203), straightforward implementation."""
import hashlib
Q = 3329; N = 256; K = 2; ETA1 = 3; ETA2 = 2; DU = 10; DV = 4

def bitrev7(x): return int(f"{x:07b}"[::-1], 2)
ZETAS = [pow(17, bitrev7(i), Q) for i in range(128)]
GAMMAS = [pow(17, 2 * bitrev7(i) + 1, Q) for i in range(128)]

def G(b):   h = hashlib.sha3_512(b).digest(); return h[:32], h[32:]
def H(b):   return hashlib.sha3_256(b).digest()
def J(b):   return hashlib.shake_256(b).digest(32)
def PRF(eta, s, n): return hashlib.shake_256(s + bytes([n])).digest(64 * eta)

def bits_le(bs):
    return [(byte >> i) & 1 for byte in bs for i in range(8)]

def byte_encode(f, d):
    bits = []
    for a in f:
        for i in range(d): bits.append((a >> i) & 1)
    return bytes(sum(bits[8*i + j] << j for j in range(8)) for i in range(len(bits) // 8))

def byte_decode(b, d):
    m = Q if d == 12 else (1 << d)
    bits = bits_le(b)
    return [sum(bits[i*d + j] << j for j in range(d)) % m for i in range(N)]

def compress(x, d):   return ((x << d) + Q // 2) // Q % (1 << d)      # round(2^d/q * x)
def decompress(y, d): return (y * Q + (1 << (d - 1))) >> d             # round(q/2^d * y)

def sample_ntt(seed34):
    xof = hashlib.shake_128(seed34).digest(1680)   # plenty
    a = []; i = 0
    while len(a) < N:
        c0, c1, c2 = xof[i], xof[i+1], xof[i+2]; i += 3
        d1 = c0 + 256 * (c1 % 16); d2 = (c1 // 16) + 16 * c2
        if d1 < Q: a.append(d1)
        if d2 < Q and len(a) < N: a.append(d2)
    return a

def sample_cbd(b, eta):
    bits = bits_le(b)
    return [(sum(bits[2*i*eta + j] for j in range(eta)) - sum(bits[2*i*eta + eta + j] for j in range(eta))) % Q
            for i in range(N)]

def ntt(f):
    f = list(f); k = 1; ln = 128
    while ln >= 2:
        for st in range(0, N, 2 * ln):
            z = ZETAS[k]; k += 1
            for j in range(st, st + ln):
                t = z * f[j + ln] % Q
                f[j + ln] = (f[j] - t) % Q; f[j] = (f[j] + t) % Q
        ln //= 2
    return f

def intt(f):
    f = list(f); k = 127; ln = 2
    while ln <= 128:
        for st in range(0, N, 2 * ln):
            z = ZETAS[k]; k -= 1
            for j in range(st, st + ln):
                t = f[j]; f[j] = (t + f[j + ln]) % Q; f[j + ln] = z * (f[j + ln] - t) % Q
        ln *= 2
    return [x * 3303 % Q for x in f]

def mul_ntt(f, g):
    h = [0] * N
    for i in range(128):
        a0, a1, b0, b1, gm = f[2*i], f[2*i+1], g[2*i], g[2*i+1], GAMMAS[i]
        h[2*i] = (a0 * b0 + a1 * b1 * gm) % Q; h[2*i+1] = (a0 * b1 + a1 * b0) % Q
    return h

add = lambda a, b: [(x + y) % Q for x, y in zip(a, b)]
sub = lambda a, b: [(x - y) % Q for x, y in zip(a, b)]

def pke_keygen(d):
    rho, sigma = G(d + bytes([K]))
    A = [[sample_ntt(rho + bytes([j, i])) for j in range(K)] for i in range(K)]
    s = [sample_cbd(PRF(ETA1, sigma, n), ETA1) for n in range(K)]
    e = [sample_cbd(PRF(ETA1, sigma, K + n), ETA1) for n in range(K)]
    sh = [ntt(x) for x in s]; eh = [ntt(x) for x in e]
    th = []
    for i in range(K):
        acc = [0] * N
        for j in range(K): acc = add(acc, mul_ntt(A[i][j], sh[j]))
        th.append(add(acc, eh[i]))
    ek = b"".join(byte_encode(t, 12) for t in th) + rho
    dk = b"".join(byte_encode(x, 12) for x in sh)
    return ek, dk

def pke_encrypt(ek, m, r):
    th = [byte_decode(ek[384*i:384*(i+1)], 12) for i in range(K)]
    rho = ek[384*K:]
    A = [[sample_ntt(rho + bytes([j, i])) for j in range(K)] for i in range(K)]
    y = [sample_cbd(PRF(ETA1, r, n), ETA1) for n in range(K)]
    e1 = [sample_cbd(PRF(ETA2, r, K + n), ETA2) for n in range(K)]
    e2 = sample_cbd(PRF(ETA2, r, 2 * K), ETA2)
    yh = [ntt(x) for x in y]
    u = []
    for i in range(K):
        acc = [0] * N
        for j in range(K): acc = add(acc, mul_ntt(A[j][i], yh[j]))
        u.append(add(intt(acc), e1[i]))
    mu = [decompress(x, 1) for x in byte_decode(m, 1)]
    acc = [0] * N
    for j in range(K): acc = add(acc, mul_ntt(th[j], yh[j]))
    v = add(add(intt(acc), e2), mu)
    c1 = b"".join(byte_encode([compress(x, DU) for x in ui], DU) for ui in u)
    c2 = byte_encode([compress(x, DV) for x in v], DV)
    return c1 + c2

def pke_decrypt(dk, c):
    u = [[decompress(x, DU) for x in byte_decode(c[320*i:320*(i+1)], DU)] for i in range(K)]
    v = [decompress(x, DV) for x in byte_decode(c[320*K:], DV)]
    sh = [byte_decode(dk[384*i:384*(i+1)], 12) for i in range(K)]
    acc = [0] * N
    for j in range(K): acc = add(acc, mul_ntt(sh[j], ntt(u[j])))
    w = sub(v, intt(acc))
    return byte_encode([compress(x, 1) for x in w], 1)

def keygen(d, z):
    ek, dkp = pke_keygen(d)
    return ek, dkp + ek + H(ek) + z

def encaps(ek, m):
    Kk, r = G(m + H(ek))
    return Kk, pke_encrypt(ek, m, r)

def decaps(dk, c):
    dkp, ek, h, z = dk[:384*K], dk[384*K:768*K+32], dk[768*K+32:768*K+64], dk[768*K+64:]
    mp = pke_decrypt(dkp, c)
    Kp, rp = G(mp + h)
    Kbar = J(z + c)
    cp = pke_encrypt(ek, mp, rp)
    return Kp if cp == c else Kbar

if __name__ == "__main__":
    import os
    for _ in range(3):
        d, z, m = os.urandom(32), os.urandom(32), os.urandom(32)
        ek, dk = keygen(d, z)
        Kk, c = encaps(ek, m)
        assert len(ek) == 800 and len(dk) == 1632 and len(c) == 768
        assert decaps(dk, c) == Kk
        bad = bytearray(c); bad[5] ^= 1
        assert decaps(dk, bytes(bad)) == J(z + bytes(bad))
    # NTT sanity
    import random
    a = [random.randrange(Q) for _ in range(N)]; assert intt(ntt(a)) == a
    print("reference OK", H(ek)[:4].hex())
