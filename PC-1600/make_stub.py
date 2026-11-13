#!/usr/bin/env python3
"""make_stub - build the BASIC stub sxrecv1600.bas (SXBIN as DATA lines) from sxbin_1600.bin.

    python z80asm.py sxbin_1600.asm            -> sxbin_1600.bin + sxbin_1600.lst
    python make_stub.py sxbin_1600.bin sxbin_1600.lst -o sxrecv1600.bas [--top CFFF]

The stub installs the image at its load address, checks it by a byte sum on every run,
sets the allowed address range (end of the receiver .. --top) and runs the receiver.
Lines end with CR LF (as sent from a terminal program). Part of the SharpFastBinaryReceiver
kit, MIT License.
"""
import argparse
import re
import sys


def symbols(lst_path):
    sym = {}
    for line in open(lst_path, encoding="utf-8", errors="replace"):
        m = re.match(r"(\w+)\s*=\s*\$([0-9A-Fa-f]+)", line)
        if m:
            sym[m.group(1)] = int(m.group(2), 16)
    return sym


def make_stub(image: bytes, base: int, sym: dict, top: int | None, open_com: bool = True) -> str:
    n = len(image)
    main = sym["sx_main"] - base           # code (constant bytes) starts here
    total = sum(image)
    code_sum = sum(image[main:])
    sig = image[12:16]
    out = []
    out.append("1 REM (c) Radovan Hrebicek 2026")
    out.append("2 REM SXRECV1600 v1 MIT - binary receiver for PC-1600, SXBIN at &%X" % base)
    out.append("3 REM first: NEW \"S0:\",&1000 (reserves &C0C5-&CFFF), then load this")
    if open_com:   # error 150 = too many files without MAXFILES
        out.append("9 MAXFILES=1")
    if top is None:   # end of the area reserved by NEW "S0:",n: word at F8BEh/F8BFh = C000h + n (exclusive)
        out.append("10 Q=&%X:T=PEEK(&F8BF)*256+PEEK(&F8BE)-1:L=Q+%d" % (base, n))
        # LARGE reservation (SBC $MEMORY LARGE): a memory module is the first S0 run (ADTBL entry at F1D5h + (F02Ah) = 01h:
        # bank 0 in slot 1) and NEW "S0:",n with n >= &4000 reaches into internal RAM (pointer >= C000h), so bank 0 is reserved
        # too: programs may also load at 80C5h-BFFFh (second range of SXBIN). Probed in Calc-U-1600: CE-1600M, NEW &8200 -> C200.
        out.append("11 LG=0:IF T>=49152 AND PEEK(61909+PEEK(61482))=1 THEN LET LG=1")
        out.append("12 IF T<49152 THEN LET T=57343")   # S0 is a memory module (pointer in 8000-BFFF): internal RAM is not reserved, use C246-DFFF
        out.append('15 IF T<L THEN CLS:PRINT "NEW S0: too small":END')
    else:
        out.append("10 Q=&%X:T=&%X:L=Q+%d" % (base, top, n))
    out.append('20 INIT "COM1:",512:SETCOM "COM1:",9600,8,N,1,N,N')
    if open_com:   # the channel must be OPEN, else (after power-on) the ROM does not fill the receive buffer
        out.append('22 CLOSE:OPEN "COM1:" FOR INPUT AS #1')
    out.append("30 IF PEEK(Q+12)<>%d OR PEEK(Q+13)<>%d THEN 60" % tuple(sig[:2]))
    out.append("35 IF PEEK(Q+14)<>%d OR PEEK(Q+15)<>%d THEN 60" % tuple(sig[2:]))
    out.append('38 CLS:PRINT "Checking CRC...";')
    out.append("40 S=0:FOR I=%d TO %d:S=S+PEEK(Q+I):NEXT I" % (main, n - 1))
    out.append("50 IF S=%d THEN 120" % code_sum)
    out.append('60 CLS:PRINT "Installing SXBIN...";')
    out.append("70 RESTORE:I=Q:S=0")
    out.append("80 READ A:IF A<0 THEN 100")
    out.append("90 POKE I,A:S=S+A:I=I+1:GOTO 80")
    out.append("100 IF S<>%d OR I-Q<>%d THEN 410" % (total, n))
    out.append("120 POKE Q,9:H=INT(L/256):POKE Q+19,L-256*H:POKE Q+20,H")
    out.append("125 H=INT(T/256):POKE Q+21,T-256*H:POKE Q+22,H")
    if top is None:   # second range: off (1..0), or 80C5-BFFF for a LARGE reservation
        out.append("126 POKE Q+23,1:POKE Q+24,0:POKE Q+25,0:POKE Q+26,0")
        out.append("127 IF LG=1 THEN POKE Q+23,197:POKE Q+24,128:POKE Q+25,255:POKE Q+26,191")
    out.append('130 CLS:PRINT "SXRECV1600 9600 8N1"')
    if top is None:
        out.append('140 CURSOR 0,1:IF LG=1 THEN PRINT "80C5-BFFF,";')
        out.append('141 PRINT HEX$(L);"-";HEX$(T);" free"')
    else:
        out.append('140 CURSOR 0,1:PRINT HEX$(L);"-";HEX$(T);" free"')
    out.append('150 CURSOR 0,2:PRINT "Send .SXE as binary"')
    out.append('160 CURSOR 0,3:PRINT "BREAK=stop";')
    out.append("170 CALL Q+16")
    if open_com:
        out.append("175 CLOSE")
    out.append("180 K=PEEK(Q):N=PEEK(Q+6)+256*PEEK(Q+7)")
    out.append("185 A=PEEK(Q+4)+256*PEEK(Q+5):E=PEEK(Q+8)+256*PEEK(Q+9)")
    out.append("190 IF K<>0 THEN 420")
    out.append('200 BEEP 1:CLS:PRINT "OK ";N;" bytes at &";HEX$(A)')
    out.append("210 IF E=65535 THEN END")
    out.append('220 CURSOR 0,1:PRINT "Run &";HEX$(E);" ? (Y/N)";')
    out.append('230 Y$=INKEY$:IF Y$="" THEN 230')
    out.append('240 IF Y$="Y" OR Y$="y" THEN CALL E')
    out.append("250 END")
    out.append('410 CLS:BEEP 1:PRINT "ERR SXBIN DATA damaged"')
    out.append('412 CURSOR 0,1:PRINT I-Q;"/%d ";S;"/%d"' % (n, total))
    out.append("415 END")
    out.append('420 BEEP 1:CLS:PRINT "ERR";K;" ";')
    out.append('430 IF K=2 THEN PRINT "CRC - send again"')
    out.append('440 IF K=3 THEN PRINT "address refused"')
    out.append('450 IF K=4 THEN PRINT "bad header"')
    out.append('460 IF K=6 THEN PRINT "serial error"')
    out.append('470 IF K=7 THEN PRINT "stopped (BRK)"')
    out.append('480 IF K=8 THEN PRINT "timeout"')
    out.append('490 IF K=9 THEN PRINT "SXBIN did not run"')
    out.append("500 R=PEEK(Q+2)+256*PEEK(Q+3)")
    out.append('502 IF K=8 AND R=0 THEN CURSOR 0,1:PRINT "data ok, CRC missing";')
    out.append('504 IF K>5 AND R>0 THEN CURSOR 0,1:PRINT N-R;" of ";N;" bytes";')
    out.append("506 IF K<>2 AND K<>8 THEN 510")
    out.append('507 CURSOR 0,2:FOR I=0 TO 7:PRINT HEX$(PEEK(A+I));" ";:NEXT I')
    out.append("510 END")
    ln = 9000
    for i in range(0, n, 16):
        out.append("%d DATA %s" % (ln, ",".join(str(b) for b in image[i:i + 16])))
        ln += 10
    out.append("%d DATA -1" % ln)
    return "\r\n".join(out) + "\r\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bin")
    ap.add_argument("lst")
    ap.add_argument("-o", "--out", default="sxrecv1600.bas")
    ap.add_argument("--top", default=None, help="fixed highest address programs may use (hex); default: read from the NEW S0: size at run time")
    ap.add_argument("--base", default="C0C5", help="load address of the image (hex)")
    a = ap.parse_args()
    image = open(a.bin, "rb").read()
    sym = symbols(a.lst)
    text = make_stub(image, int(a.base, 16), sym, int(a.top, 16) if a.top else None)
    with open(a.out, "w", newline="") as f:
        f.write(text)
    print(f"{a.out}: {len(image)} byte image, {len(text)} bytes of BASIC text")
    # the same text plus the end-of-file byte 1Ah, for LOAD "COM1:" on a real PC-1600
    ser = a.out[:-4] + "_serial.bas" if a.out.endswith(".bas") else a.out + "_serial"
    with open(ser, "wb") as f:
        f.write(text.encode("ascii") + b"")
    print(f"{ser}: same + EOF 1Ah (send this one over the serial port)")


if __name__ == "__main__":
    sys.exit(main())
