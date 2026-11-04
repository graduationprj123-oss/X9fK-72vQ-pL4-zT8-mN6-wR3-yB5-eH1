#!/usr/bin/env python3
"""PC side: talk to the Zynq board (sw/main.c) over UART.
   pip install pyserial
   python3 mlkem_uart.py /dev/ttyUSB1          (Windows: COM5)
Runs KeyGen -> Encaps -> Decaps on the FPGA and checks both shared secrets match.
"""
import os, sys

class Board:
    def __init__(self, port=None, baud=115200, stream=None):
        if stream is None:
            import serial
            stream = serial.Serial(port, baud, timeout=10)
        self.s = stream
    def _cmd(self, line):
        self.s.write((line + "\r\n").encode()); self.s.flush()
        out = {}
        while True:
            l = self.s.readline().decode(errors="replace").strip()
            if not l: raise TimeoutError(f"no reply to {line[:20]}")
            tag, _, val = l.partition(" ")
            if tag == "OK":  out["cycles"] = int(val); return out
            if tag == "ERR": raise RuntimeError(val)
            if tag in ("EK", "DK", "CT", "SS"): out[tag] = bytes.fromhex(val)
    def keygen(self, d, z):  r = self._cmd(f"K {d.hex()} {z.hex()}");   return r["EK"], r["DK"], r["cycles"]
    def encaps(self, ek, m): r = self._cmd(f"E {ek.hex()} {m.hex()}");  return r["CT"], r["SS"], r["cycles"]
    def decaps(self, dk, c): r = self._cmd(f"D {dk.hex()} {c.hex()}");  return r["SS"], r["cycles"]

def demo(board):
    d, z, m = os.urandom(32), os.urandom(32), os.urandom(32)   # randomness comes from the PC
    ek, dk, c1 = board.keygen(d, z)
    ct, ss_a, c2 = board.encaps(ek, m)
    ss_b, c3 = board.decaps(dk, ct)
    print(f"KeyGen {c1} cyc, Encaps {c2} cyc, Decaps {c3} cyc")
    print("shared secret A:", ss_a.hex()); print("shared secret B:", ss_b.hex())
    print("MATCH" if ss_a == ss_b else "MISMATCH")
    return ss_a == ss_b

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(__doc__)
    sys.exit(0 if demo(Board(sys.argv[1])) else 1)
