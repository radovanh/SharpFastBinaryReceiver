#!/usr/bin/env python3
"""bin2sxe - make an .sxe file (escaped .sxb for SXRECV1600 on the PC-1600) from a .bin.

    python bin2sxe.py prog.bin C300 --exec C300       -> prog.sxe
    python bin2sxe.py prog.bin C300 -o game.sxe

Same header/CRC as bin2sxb.py (../PC-G8xx), but the marker is "SE" and the bytes
0Ah 0Dh 0Eh 0Fh 11h 13h 1Ah 7Dh are sent as 7Dh, byte xor 20h: the PC-1600 serial layer
swallows some of them (11h/13h = XON/XOFF, 0Eh/0Fh = SI/SO) even with SETCOM switched
off, and 1Ah is the end-of-file code. Part of the SharpFastBinaryReceiver kit, MIT License.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bin2sxb", os.path.join(HERE, "..", "PC-G8xx", "bin2sxb.py"))
bin2sxb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bin2sxb)

ESC = 0x7D
SPECIAL = {0x0A, 0x0D, 0x0E, 0x0F, 0x11, 0x13, 0x1A, ESC}


def escape(sxb: bytes) -> bytes:
    """sxb = a plain .sxb (marker SX): returns the .sxe bytes."""
    out = bytearray(b"SE")
    for b in sxb[2:]:
        if b in SPECIAL:
            out += bytes([ESC, b ^ 0x20])
        else:
            out.append(b)
    return bytes(out)


def make_sxe(addr, data, exec_addr=None):
    return escape(bin2sxb.make_sxb(addr, data, exec_addr))


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="make an .sxe (escaped .sxb for the PC-1600) from a .bin")
    ap.add_argument("bin")
    ap.add_argument("addr", type=bin2sxb.hexaddr)
    ap.add_argument("--exec", dest="exec_addr", type=bin2sxb.hexaddr)
    ap.add_argument("-o", "--out")
    a = ap.parse_args(argv)
    data = open(a.bin, "rb").read()
    try:
        sxe = make_sxe(a.addr, data, a.exec_addr)
    except ValueError as e:
        sys.exit(f"bin2sxe: {e}")
    out = a.out or os.path.splitext(a.bin)[0] + ".sxe"
    open(out, "wb").write(sxe)
    print(f"{out}: 0x{a.addr:04X}-0x{a.addr + len(data) - 1:04X} ({len(data)} bytes), "
          + (f"exec 0x{a.exec_addr:04X}, " if a.exec_addr is not None else "no exec, ")
          + f"{len(sxe)} bytes to send")
    return 0


if __name__ == "__main__":
    sys.exit(main())
