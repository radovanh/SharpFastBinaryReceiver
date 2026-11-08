# SXRECVB - fast binary transfer from a PC to a Sharp Z80 pocket computer

SXRECVB loads a machine-code program from a PC into a Sharp **PC-G850V/VS** (also built for
the **PC-G850/G850S** and the **PC-G815**, see "Models") over the 11-pin port, as raw binary at
9600 baud. The receiver is a small BASIC program (it only installs, starts and reports) plus a
**421-byte machine-code receiver, SXBIN**, that sits at `0x0100-0x02A4`. It checks the header,
the target address and a CRC-16. Programs go straight into the machine-code area, so a big
program is not limited by the size of a BASIC loader. About 1 second per kilobyte.

Status: **tested on a real PC-G850V** (BASIC stub, a 21-byte test program and a 1000-byte file).
The PC-G815 and PC-G850/G850S builds are written and tested in a Z80 model only, **not yet on a
real device**.

## Files

| File | What it is |
|---|---|
| `sxrecvb.bas` | The BASIC stub for the **PC-G850V/VS** (with the receiver as DATA lines). Load it into BASIC once |
| `sxrecvb_g850.bas` | The same for the **PC-G850/G850S** (bit-banged receive; untested on a real device) |
| `sxrecvb_g815.bas` | The same for the **PC-G815** (bit-banged receive; needs 2 stop bits; untested on a real device) |
| `bin2sxb.bat`, `bin2sxb.ps1` | PC tool (Windows): makes an `.sxb` file from a `.bin`. The `.bat` runs the PowerShell script; nothing to install |
| `bin2sxb.py` | The same in Python 3 (any OS) |
| `sxsend.py` | Optional PC sender (`pip install pyserial`) with 2 stop bits / header pause options |
| `ihx\` | The receiver alone as Intel HEX at `0x0100`, for `MON` `R` (no BASIC needed), one file per model |
| `samples\` | `hello.sxb` (prints `PROG RAN`), `rand1000.sxb` (1000 bytes), and the source of `hello` |
| `sxbin.asm` | The receiver's source (z80asm / zasm dialect; `SX_MODEL` selects the model) |
| `pc-settings\` | Tera Term settings for sending an `.sxb` |
| `LICENSE` | MIT License |

## What you need

- A Sharp **PC-G850V/VS** and a cable from its 11-pin port to the PC (an RS-232 level or
  USB-serial adapter; the port's signals are the inverted kind, so the same cable as for any Sharp
  PC-G8xx serial transfer).
- On the PC a program that can send a file **unchanged** (binary) at **9600 baud 8N1, with
  no flow control**, for example [Tera Term](https://teratermproject.github.io/) (File > Send file,
  "Binary" ticked) or `sxsend.py`.
- To make `.sxb` files: Windows PowerShell (`bin2sxb.bat`), or Python 3 (`bin2sxb.py`).
- Your program as a `.bin`, assembled for the address where it will run.

## 1. Reserve the machine-code area (once after a reset)

On the pocket computer: `MON`, then `USER1FFF`. It answers `FREE:0100-1FFF`. Leave MON with the
BASIC key. This reserves `0100-1FFF` for machine code: SXBIN uses `0100-02A4`, your program may
use the rest. For a bigger program use a higher address (`USER3FFF`, ...). Without it the
receiver refuses every file (status 3), because it takes its upper limit from the word at `0x7FFE`
that `USER` moves.

## 2. Load the BASIC stub (once)

Get `sxrecvb.bas` into BASIC any way you like (TEXT mode > Sio receive and convert to BASIC,
`LOAD` from a RAM file, or type it in). It is a plain numbered BASIC listing, about 2.9 KB.
Check that all lines arrived: `LIST 9000` should show 18 DATA lines (9000 to 9170, then the
`"*"` line 9180). A damaged copy shows up on the first `RUN` as `ERR SXBIN DATA damaged` with
two numbers: bytes installed `/421` and the byte sum `/35658`.

`RUN`. The first run installs the receiver from the DATA lines (about a minute); later runs find
it already there and start at once. The screen then shows:

```
SXRECVB 9600 2A5-1FFF
Send .SXB as binary,
No flow ctl. BRK=stop
```

`2A5-1FFF` is the area your program may occupy.

## 3. Make the .sxb file

```
bin2sxb prog.bin 1000 --exec 1000
```

writes `prog.sxb`: load address `1000` (hex), and with `--exec` the stub offers to run it
afterwards. Without `--exec` it only loads.

## 4. Send it

While the waiting screen is up, send `prog.sxb` as binary, 9600 baud, 8N1, no flow control,
**no transmit delay** (Tera Term: use `pc-settings\TeraTerm_SXRECVB_9600.INI`; or
`python sxsend.py COM5 prog.sxb`). Do not use XON/XOFF.

## 5. Result

```
OK 1000 bytes at &H1000
Run &H1000 ? (Y/N)         (only when the file has a start address)
```

`Y` runs the program with `CALL`; it should end with `RET` to return to BASIC. On an error the
screen shows `ERR<n>` and a text:

| Number | Text | Meaning |
|---|---|---|
| 2 | `CRC - send again` | CRC wrong. The bytes are stored but damaged: send again |
| 3 | `address refused` | outside the allowed area (below `02A5`, at or above the `USER` limit, or no `USER` done). Nothing stored |
| 4 | `bad header` | the 9-byte header is damaged or the length is 0. Nothing stored |
| 6 | `serial n` | UART error; n = the USART status (bit 4 overrun, bit 5 framing, bit 3 parity). Wrong baud rate or format |
| 7 | `stopped (BRK)` | BREAK pressed (BASIC may print its own `BREAK IN ...` as well) |
| 8 | (timeout) | nothing received for about 2 seconds after the header; `n of m bytes` shows how far it got |
| 9 | `SXBIN did not run` | the receiver never started |

## Where programs may go

From **`02A5`** (just after the receiver) up to the address the `USER` command set: with
`USER1FFF` that is `02A5-1FFF`. The usual choice is `1000`. `0100-02A4` is the receiver itself and
is refused. The area `0000-00FF` and everything from `2000` up (BASIC, files, system) is refused.

## Using the receiver without BASIC

SXBIN is a plain machine-code routine; the stub is only a front end.

- **Calling it by hand:** with the receiver in memory (`PRINT PEEK(&H10C)` gives 83) and `USER`
  done: `CALL &H110`, then send the file. There is no screen output; the call returns when the
  file has arrived, at an error, or when you press BREAK. Interrupts are off meanwhile, so the
  keyboard seems dead.
- **Installing it without the BASIC stub:** `MON`, `USER1FFF`, `R`, send `ihx\sxbin_g850v.ihx`
  as text, then `CALL &H110` (or `G110` in MON).
- **Result block** at `0100` (read it with `PEEK`, or `D0100,010F` in MON):

| Address | Meaning |
|---|---|
| `0100` | status: 0 OK, 2 CRC, 3 address, 4 header, 6 UART error, 7 BREAK, 8 timeout, 9 = never ran |
| `0101` | USART baud byte for port `70h` (`0D` = 9600, the default; `0C` = 4800, `0E` = 19200); G850V only |
| `0102-0103` | data bytes not received (0 = complete) |
| `0104-010A` | the header as received: load address (2), length (2), start address (2), check byte |
| `010B` | UART status when status 6 happened |
| `010C-010F` | `SXB1`, marks an installed receiver |
| `0110` | entry point (`JP`); `CALL &H110` |

All registers and the interrupt state are restored on return.

## The .sxb file format

For use from your own tools. All numbers low byte first except the CRC.

| Offset | Bytes | Meaning |
|---|---|---|
| 0 | 2 | `SX`, the marker. The receiver skips anything before it |
| 2 | 2 | load address |
| 4 | 2 | length n (1-65535) |
| 6 | 2 | start address (`0xFFFF` = none) |
| 8 | 1 | header check: bytes 2-8 add up to 0 (mod 256) |
| 9 | n | the program |
| 9+n | 2 | CRC-16/XMODEM (polynomial 0x1021, start 0) of the program, high byte first |

The header is checked before anything is stored. The CRC is checked at the end over the stored
bytes, so a bad CRC means the program is already in memory but damaged.

## Models

| Model | Stub / image | How it receives | Stop bits |
|---|---|---|---|
| PC-G850V/VS | `sxrecvb.bas`, `ihx\sxbin_g850v.ihx` | the USART (ports `70h-74h`) polled | 1 |
| PC-G850/G850S | `sxrecvb_g850.bas`, `ihx\sxbin_g850.ihx` | software UART on port `18h`/`1Fh`, 8 MHz | 1 |
| PC-G815 | `sxrecvb_g815.bas`, `ihx\sxbin_g815.ihx` | software UART on port `18h`/`1Fh`, 3.09 MHz | **2** |

The PC-G815 has no USART. At 322 T per bit the receiver cannot check the address between the
header and the first data byte within one stop bit, so send with **2 stop bits**
(`pc-settings\TeraTerm_SXRECVB_G815_9600_2stop.INI`, or `sxsend.py --stop 2`), or give it a pause
after the header (`sxsend.py --pause 5`). Before using the G815 build check that `MON` and
`USER1FFF` exist on your unit and move the word at `7FFE` (`D7FFE,7FFF` before and after).
The **PC-E220** has no BASIC `PEEK`/`POKE`/`CALL`, so it has its own kit without a stub: see `../PC-E220`.
The G815 and G850/G850S builds have only been run on a Z80 model so far; if one fails on a real
unit, please report the screen text.

## Troubleshooting

- **`ERR SXBIN DATA damaged`**: the listing was not loaded completely or was changed. Load it
  again and compare line 9000 onward (the two numbers show how much was installed).
- **`Need MON, USER1FFF`**: do step 1.
- **`ERR6 serial 32`** (or similar): the PC is not at 9600 8N1, or the cable/adapter is wrong.
- **`ERR3 address refused`**: the load address is outside `02A5` up to the `USER` limit. Use
  `1000` or raise the limit with a higher `USER` address.
- Nothing happens when sending: start the transfer only after the waiting screen shows.
  The receiver has no buffer; it only listens while that screen is up.
- BASIC quirks worth knowing if you edit the stub on a G850V: `VAL("&H..")` needs the `H`;
  `A$`-`Z$` hold only 7 characters (the stub uses `DIM HX$(0)*48`); `BEEP` needs an argument.

## Limits

- Total loaded size 1 to 65535 bytes, in one block, into the area above.
- 9600 baud, 8 data bits, no parity (the G850V also accepts the baud byte at `0101` for other
  rates, untested).
- No flow control. The PC must not use XON/XOFF.
- Interrupts are off while receiving.

Copyright (c) 2026 Radovan Hrebicek. MIT License (see LICENSE).
