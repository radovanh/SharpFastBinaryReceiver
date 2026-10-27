#!/usr/bin/env python3
"""sxsend - send a .sxb file to SXBIN over a serial port (needs: pip install pyserial).

    python sxsend.py COM5 prog.sxb [--baud 9600] [--stop 1|2] [--pause MS] [--delay MS] [--rtscts]

Raw binary, 8N1, no XON/XOFF. PC-G850V: the defaults. PC-G815 (bit-banged receiver): use
--stop 2, or --pause 5 (silence after the header, where the receiver checks the address);
--delay adds a pause after every byte.
Start it only when the pocket computer shows the waiting screen.
"""
import argparse
import sys
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port")
    ap.add_argument("file")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--stop", type=int, choices=(1, 2), default=1)
    ap.add_argument("--delay", type=float, default=0.0, help="ms after every byte")
    ap.add_argument("--pause", type=float, default=0.0,
                    help="ms of silence after the 9-byte header (instead of 2 stop bits on the PC-G815)")
    ap.add_argument("--rtscts", action="store_true", help="hardware flow control (RTS/CTS)")
    a = ap.parse_args()
    try:
        import serial
    except ImportError:
        sys.exit("pyserial missing: pip install pyserial")
    data = open(a.file, "rb").read()
    if data[:2] != b"SX":
        sys.exit(f"{a.file} is not an .sxb file (no 'SX' marker); make one with bin2sxb.py")
    s = serial.Serial(a.port, a.baud, bytesize=8, parity="N", stopbits=a.stop, xonxoff=False,
                      rtscts=a.rtscts, dsrdtr=False, timeout=1, write_timeout=30)
    t0 = time.time()
    if a.pause:
        s.write(data[:9])
        s.flush()
        while s.out_waiting:
            time.sleep(0.001)
        time.sleep(a.pause / 1000)
        data = data[9:]
    if a.delay:
        for b in data:
            s.write(bytes([b]))
            s.flush()
            time.sleep(a.delay / 1000)
    else:
        s.write(data)
        s.flush()
    while s.out_waiting:
        time.sleep(0.01)
    time.sleep(0.2)
    s.close()
    print(f"sent {len(data)} bytes in {time.time() - t0:.1f} s ({a.baud} baud, {a.stop} stop bit(s))")


if __name__ == "__main__":
    sys.exit(main())
