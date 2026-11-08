# SXBIN for the Sharp PC-E220 - fast binary transfer from a PC

**Update 2026-11-08:** the owner found on a real E220 that `PEEK`, `POKE` and `CALL` work in its BASIC
(the manual omits them), so there are two ways in: the **BASIC stub `sxrecvb_e220.bas`** (the same
idea as on the PC-G8xx kit: untested on a real unit; it avoids `HEX$` and `VAL("&H")`, which
the E220 BASIC lacks or may lack, so addresses are shown in decimal; line 3 `CLS:WAIT 60` is needed for `INKEY$`), and the Monitor install below,
which gives a hex screen and is for devices without `PEEK`/`POKE`/`CALL`.

Loads a machine-code program from a PC into a Sharp **PC-E220** over the 11-pin port, as raw
binary at 9600 baud, into the machine-code area. The receiver, **SXBIN**, is a 996-byte
machine-code program at `0100-04E3` that draws its own 4 x 24 screen, checks the header, the
target address and a CRC-16, and offers to run the program afterwards. It is the E220 version of
the PC-G8xx loader in `../PC-G8xx` (same `.sxb` file format, same PC tools).

Status: the BASIC stub `sxrecvb_e220.bas` is **tested on a real PC-E220**, and the same receiver also works
on a **PC-E200** (owner, 2026-11-08; set the user area first). The Monitor-installed version with its own
screen (Way B) is tested in a Z80 model only (ROM text and key calls simulated). The 8 KB models (**PC-G801**, G802, G803, G820; only about 2 KB is free) have too little
RAM for a binary loader and are not supported. The **PC-G830** (32 KB) should work with this kit, same as
the E220/E200: **not tested yet** (run the stub, or the probe in the session notes, and report).

## What is different from the PC-G8xx kit

The E220's BASIC has **no `PEEK`, `POKE` or `CALL`**, so there is no BASIC stub that installs the
receiver. The receiver is installed once with the Monitor's `R` command (Intel HEX over the same
port, at the slow ROM speed) and started with the Monitor's `G`. After that, files go in at 9600
baud. Everything else - receive code, `.sxb` format, status codes, address guard - is the PC-G815
build of the PC-G8xx kit, because the E220 has no USART and its ROM serial driver is the G815's
byte for byte.

## Files

| File | What it is |
|---|---|
| `sxrecvb_e220.bas` | BASIC stub with the receiver (389 bytes, the PC-G815 image) as decimal DATA lines. `RUN` installs it the first time. Needs `USER1FFF` done |
| `ihx\sxbin_e220.ihx` | The receiver as Intel HEX at `0100`, for `MON` `R` |
| `sxbin.asm` | Its source (z80asm / zasm dialect). `-D SX_MODEL=4` builds this one |
| `samples\hello_e220.sxb` | Test file: prints `PROG RAN` on the last row and returns. Source and `.bin` beside it |
| `pc-settings\` | Tera Term settings: `..._MONR_1200.INI` to install, `..._9600_2stop.INI` to send files |
| `LICENSE` | MIT License |

The PC tools (`bin2sxb.bat/.ps1/.py`, `sxsend.py`) are the ones in `../PC-G8xx`; they are not
copied here.

## What you need

- A PC-E220 and a cable from its 11-pin port to the PC with an inverting level converter (the
  CE-T801 or any USB-serial adapter wired the Sharp way; the signals are the inverted kind, see
  the E220 knowledgebase). Same cable as for `TEXT > Sio`.
- On the PC: Tera Term or `sxsend.py` (`pip install pyserial`), and your program as a `.bin`.

## Way A: the BASIC stub

`MON`, `USER1FFF` (reserves `0100-1FFF`), back to BASIC, get `sxrecvb_e220.bas` into BASIC (TEXT > Sio, or
type it), `RUN` (the first run installs the receiver, which takes a while; it shows `ERR SXBIN DATA damaged`
if a line was lost, with byte counts). The waiting screen shows `SXRECVB 9600 645-8191` (decimal: the area
your program may use). Send the `.sxb` as in step 4 below (9600 8N2, binary). The result is
`OK n bytes at a` (decimal) and, if the file has a start address, `Run a ? (Y/N)` answered with one key (`Y`). Errors are the same as below. Lines 51 and 52 of the stub test the installed copy, so after
the first run it starts at once.

## Way B: the Monitor install (no BASIC needed)

### 1. Reserve the machine-code area

On the E220: `MON`, then `USER1FFF`. It answers `FREE:0100-1FFF`. SXBIN occupies `0100-04E3`;
your program may use the rest, so the usual load address is `1000`. For a bigger program use a
higher `USER` address. Without `USER` the receiver refuses every file (status 3), because its
upper limit is the word at `7FFE`, which `USER` moves. (To check: `D7FFE` before and after.)

### 2. Install the receiver (once)

Still in MON: type `R`, then send `ihx\sxbin_e220.ihx` **as text** with the E220's own serial
settings (end of line CR and end of file 1Ah, in `TEXT > Sio`, if `I/O ERROR` appears after a few characters;
that fixed it on a PC-G801) (`TEXT` > `Sio`; the default is 1200 baud, 8 bits, 1 stop bit, no parity), a pause of
**at least 100 ms after each line** (`pc-settings\TeraTerm_SXBIN_E220_MONR_1200.INI`), and no flow
control. It takes about half a minute. MON shows an error (`I/O DEVICE ERROR`) if a line was bad:
send it again.

Check with `D010C`: the bytes at `010C-010F` must be `53 58 42 31` (`SXB1`). The receiver stays in
RAM like any machine-code area, until memory is cleared or the `USER` area is removed.

### 3. Make the .sxb file

```
bin2sxb prog.bin 1000 --exec 1000
```

(`../PC-G8xx/bin2sxb.bat`; load address in hex; `--exec` makes the receiver offer to run it.)

### 4. Send it

In MON: `G0110`. The screen shows

```
SXBIN E220 9600 8N2
Free 04E4-1FFF
Send .SXB as binary
No flow ctl. BRK=stop
```

Send the `.sxb` as **binary, 9600 baud, 8 data bits, no parity, 2 stop bits, no flow control, no
transmit delay**: `pc-settings\TeraTerm_SXRECVB_E220_9600_2stop.INI` (File > Send file, "Binary"
ticked), or `python sxsend.py COM5 prog.sxb --stop 2`.

**Two stop bits are needed.** At 322 T per bit the receiver checks the load address between the
header and the first data byte, and that takes about 430 T - longer than the 145 T it has before
the next start bit with one stop bit. (A pause of 5 ms after the header does the same:
`sxsend.py --pause 5`.) Interrupts are off while receiving; the keyboard seems dead, BREAK works.

### 5. Result

```
OK 03E8 bytes at 1000
Run 1000 ? (Y/N)           (only when the file has a start address)
```

Lengths and addresses are in hex. `Y` runs the program with `CALL`; it must end with `RET`, which
returns to MON. Any other key returns to MON at once. On an error:

| Screen | Meaning |
|---|---|
| `ERR2 CRC - send again` | CRC wrong. The bytes are stored but damaged: send again |
| `ERR3 address refused` | outside `04E4` .. the `USER` limit, or no `USER` done. Nothing stored |
| `ERR4 bad header` | header damaged, or length 0. Nothing stored |
| `ERR6 framing - baud?` | a stop bit was not where expected: wrong baud rate or format, or a too slow/fast PC clock |
| `ERR7 stopped (BRK)` | BREAK pressed |
| `ERR8 timeout` | nothing received for about 3 s after the header |

Errors 6 to 8 add a second line `n of m bytes` if the data had begun.

## Using the receiver from your own code

- `G0113` (or `CALL 0113`) is the bare receiver without the screen: it returns at the end of the
  file, at an error or at BREAK. All registers and the interrupt state are restored.
- The result block at `0100` (read with `D0100`): `0100` status (0 OK, 2 CRC, 3 address, 4 header,
  6 framing, 7 BREAK, 8 timeout, 9 never ran), `0102-0103` bytes not received (0 = complete),
  `0104-010A` the header as received (load address, length, start address, check byte),
  `0110` the entry with the screen (`JP`), `0113` the bare entry (`JP`).

## The .sxb file format

Unchanged from the PC-G8xx kit: `SX`, load address (2, low byte first), length (2), start
address (2, `FFFF` = none), header check byte (bytes 2-8 add up to 0), data, CRC-16/XMODEM of the
data (high byte first). The header is checked before anything is stored; the CRC at the end over
the stored bytes.

## The clock: an open point

The receiver counts CPU cycles. It is built for **3.09 MHz** (322 T per bit at 9600 baud), the
PC-G815's measured clock, because the E220's ROM serial driver is the G815's with the same cycle
counts per bit, and a 9600-baud setting that works needs about that clock. The E220's crystal is
marked 3.58 MHz and nobody has measured the effective CPU clock yet. The receiver tolerates +-3 %
of timing error. If every transfer ends with `ERR6` while the PC is surely at 9600 8N2, the clock
differs: rebuild with the right cycles per bit (clock in Hz / 9600), e.g. for 3.58 MHz

```
python z80asm.py sxbin.asm --ihx 0x0100 -D SX_MODEL=4 -D SX_BIT_T=373
```

and install that image. Tell the maintainer what you found.

## Not tested on a real E220

- the whole thing; in particular that `USER` moves the word at `7FFE` (documented for the E220
  ROM, not yet seen), and the ROM entries `BFF1h` / `BFEEh` / `BE53h` (documented, confirmed on a
  real PC-G815);
- the effective CPU clock (above);

Copyright (c) 2026 Radovan Hrebicek. MIT License (see LICENSE).
