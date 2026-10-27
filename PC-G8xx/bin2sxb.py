#!/usr/bin/env python3
"""bin2sxb - make a .sxb file (for the G8xx Serial Loader, SXBIN) from a .bin.

    python bin2sxb.py prog.bin 1000                 -> prog.sxb, no start address
    python bin2sxb.py prog.bin 1000 --exec 1000     -> the BASIC stub offers to run &H1000
    python bin2sxb.py prog.bin 1000 -o game.sxb

Addresses in hex, with or without &H / 0x / $. Then send the .sxb as binary, without
flow control (see README.md).

SXB format (same layout as the Casio .vxb, marker "SX"):
  +0  'S' 'X'        marker
  +2  load address   low byte first
  +4  length n       low byte first, 1..65535
  +6  exec address   low byte first, 0xFFFF = none
  +8  header check   bytes +2..+8 add up to 0 (mod 256)
  +9  n data bytes
  then the CRC-16/XMODEM of the data, high byte first

Part of SharpPocketLib (projects/G8xx Serial Loader). MIT License.
"""
import argparse
import os
import sys


def crc16_xmodem(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def make_sxb(addr: int, data: bytes, exec_addr=None) -> bytes:
    if not 1 <= len(data) <= 0xFFFF:
        raise ValueError("an .sxb holds 1..65535 bytes")
    if not 0 <= addr <= 0xFFFF or addr + len(data) > 0x10000:
        raise ValueError(f"0x{addr:04X} + {len(data)} bytes runs past 0xFFFF")
    ex = 0xFFFF if exec_addr is None else exec_addr
    hdr = bytes([addr & 255, addr >> 8, len(data) & 255, len(data) >> 8, ex & 255, ex >> 8])
    crc = crc16_xmodem(data)
    return b"SX" + hdr + bytes([(-sum(hdr)) & 255]) + data + bytes([crc >> 8, crc & 255])


def hexaddr(s: str) -> int:
    s = s.strip()
    for p in ("&H", "&h", "0x", "0X", "$"):
        if s.startswith(p):
            s = s[len(p):]
    v = int(s, 16)
    if not 0 <= v <= 0xFFFF:
        raise argparse.ArgumentTypeError(f"{s}: not a 16-bit address")
    return v


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="make an .sxb (G8xx Serial Loader) from a .bin")
    ap.add_argument("bin", help="the machine-code file")
    ap.add_argument("addr", type=hexaddr, help="load address (hex), e.g. 1000")
    ap.add_argument("--exec", dest="exec_addr", type=hexaddr, help="start address (hex)")
    ap.add_argument("-o", "--out", help="output file (default: the .bin name with .sxb)")
    a = ap.parse_args(argv)
    with open(a.bin, "rb") as f:
        data = f.read()
    try:
        sxb = make_sxb(a.addr, data, a.exec_addr)
    except ValueError as e:
        sys.exit(f"bin2sxb: {e}")
    out = a.out or os.path.splitext(a.bin)[0] + ".sxb"
    with open(out, "wb") as f:
        f.write(sxb)
    crc = sxb[-2] << 8 | sxb[-1]
    print(f"{out}: 0x{a.addr:04X}-0x{a.addr + len(data) - 1:04X} ({len(data)} bytes), "
          + (f"exec 0x{a.exec_addr:04X}, " if a.exec_addr is not None else "no exec, ")
          + f"CRC 0x{crc:04X}, {len(sxb)} bytes to send")
    return 0


if __name__ == "__main__":
    sys.exit(main())
