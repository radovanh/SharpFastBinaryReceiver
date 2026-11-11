# SXRECV1600 - fast binary transfer from a PC to a Sharp PC-1600

Loads a machine-code program from a PC into a Sharp **PC-1600** over its RS-232C port (`COM1:`)
as binary, with the `.sxb` header/CRC of the PC-G8xx and PC-E220 kits, but **escaped** (`.sxe`, see below). A small BASIC
stub installs, starts and reports; a **385-byte machine-code receiver, SXBIN**, sits at
`C0C5` (the start of the machine-code area). It checks the header, the target address and a CRC-16.

Status: **tested on a real PC-1600** (stub load, install, `hello_1600.sxe` received and run: `PROG RAN`),
2026-11-09, plus 10 scripted runs in Calc-U-1600 (there the serial IOCS is replaced by a test shim, the
emulator's Windows build has no serial link). The 23-byte sample and the 2749-byte graphics demo have been run on hardware;
other baud rates and the timeout length are untested. Please report the screen text if something fails.

## How it differs from the G8xx receiver

SXBIN does not touch the UART. It reads the bytes through the ROM's serial IOCS (`CRCV1`, `CALL 01D8h`),
so the ROM interrupt handler fills the `COM1:` receive buffer (the stub sets 512 bytes with `INIT`) and
SXBIN only fetches them. Interrupts stay on, there is no bit timing and no stop-bit trick. The line
settings are those of BASIC `SETCOM`. The stub uses `SETCOM "COM1:",9600,8,N,1,N,N`:
**no XON/XOFF and no SI/SO**, which would eat bytes of binary data.

## Files

| File | What it is |
|---|---|
| `sxrecv1600.bas` | The BASIC stub (receiver as DATA lines, 3.2 KB), for the emulator's File menu |
| `sxrecv1600_serial.bas` | The same plus the EOF byte `1Ah`: send this over the serial port to `LOAD "COM1:"` |
| `sxbin_1600.asm` | The receiver's source (z80asm / zasm dialect); `sxbin_1600.bin` / `.lst` are its build |
| `make_stub.py` | Rebuilds the stub from the `.bin` + `.lst` (`python make_stub.py sxbin_1600.bin sxbin_1600.lst`) |
| `bin2sxe.py`, `bin2sxe.bat` | PC tool: `.bin` to `.sxe` (escaped transfer file) |
| `samples\` | `hello_1600.sxe` (prints `PROG RAN`, load `C300`) and its source |
| `samples\gfxdemo_1600.sxe` | 2.7 KB graphics demo built on the PC-1600 graphics library (load/start `C250`) |
| `pc-settings\` | Tera Term settings (9600 8N1, no flow control) |

Make `.sxe` files with **`bin2sxe.bat` / `bin2sxe.py`** (Python 3). Do **not** send plain `.sxb` files from the G8xx kit: the PC-1600 serial layer eats some bytes (see below).

## Quick start (everything you type or set)

**Tera Term** (Setup > Serial port): 9600 baud, 8 data bits, parity none, 1 stop bit, **flow control none**.
Or merge `pc-settings\TeraTerm_SXRECV1600_9600.INI`. Setup > General: `Transmit delay` 0 ms/char, and
**50-100 ms/line** only while sending the stub (see step 2).

**PC-1600, once after a reset** (PRO mode for `NEW`; `MODE` key switches PRO/RUN):
```
NEW "S0:",&1000                      reserves C0C5-CFFF for machine code, ERASES the BASIC program
INIT "COM1:",4096                    big receive buffer for the stub transfer
SETCOM "COM1:",9600,8,N,1,N,N        9600 8N1, no XON/XOFF, no SI/SO
LOAD "COM1:"                         now it waits (BUSY) for the stub
```
**Tera Term**: File > Send file > `sxrecv1600_serial.bas`, **Binary unticked**, delay 50-100 ms per line.
The file ends with the EOF byte `1Ah` that finishes `LOAD` (if it stays BUSY press Ctrl+Z in the terminal window).

**PC-1600**: `RUN`. The first run installs the receiver (a while), the screen shows the waiting text.
**Tera Term**: File > Send file > `prog.sxe`, **Binary ticked**, delay 0.
**PC-1600**: answer `Y` to `Run &C300 ?`.

After the stub is loaded you only need `RUN` and the second send for every further program. The stub sets
`SETCOM` and `INIT "COM1:",512` itself on each run, and **opens the channel** (`MAXFILES=1`, then `OPEN "COM1:" FOR INPUT AS #1`;
without MAXFILES the OPEN gives error 150 "too many files",
`CLOSE` afterwards). Without an open channel the ROM does not fill the receive buffer: a freshly switched-on
PC-1600 (where the stub was not loaded by `LOAD "COM1:"`) just waited forever. If an older stub does this,
type `LOAD "COM1:"`, press BREAK, and run it again, or reload the current `sxrecv1600.bas`.

## 1. Reserve the machine-code area (once after a reset)

`NEW "S0:",&1000` in PRO mode reserves `C0C5-CFFF` for machine code (n minus `&C5` bytes) and **erases the
BASIC program**, so do it before loading the stub. SXBIN uses `C0C5-C245`; your program may use
`C246-CFFF`. For a bigger area use a bigger number: **n is a size, not an address** (`NEW "S0:",&1200` gives
`C0C5-D1FF`; `&D1FF` is refused, the largest is about `&2EFF`). The stub reads the reserved size itself at
run time (the word at `F8BEh` = `C000h` + n) and shows the free range on the waiting screen, e.g. `C246-D1FF free`;
With a memory module (e.g. CE-161) in S0 the word points into the module (`NEW "S0:",&1200` gave `9200`, seen on a real
PC-1600): the reservation is then in the module, internal RAM is **not protected** by `NEW`, and the stub uses
`C246-DFFF` (variables grow down from `EFFF`).
nothing to edit. (`make_stub.py --top EFFF` makes a stub with a fixed top instead.)

## 2. Load the BASIC stub (once)

- **Real PC-1600**: the commands above. `LOAD "COM1:"` tokenizes each line, which is slower than 9600 baud:
  without the big buffer and the per-line delay it stops with **ERROR 142** (receive error / buffer full)
  part-way (seen at about line 190 with a 512-byte buffer). Send **`sxrecv1600_serial.bas`**; without its
  EOF byte `1Ah` the `LOAD` stays BUSY. `LOAD` receives, `SAVE "COM1:",A` sends.
  (The PB-100 Data Communicator is reported not to work for this.)
- **Calc-U-1600**: File menu > load BASIC program, pick the plain `sxrecv1600.bas`.

`RUN`. The first run installs the receiver from the DATA lines; later runs find it already there
(signature and byte sum are checked every time) and start at once. The screen shows:

```
SXRECV1600 9600 8N1
C246-CFFF free
Send .SXE as binary
BREAK=stop
```

## 3. Send the program

`bin2sxe prog.bin C300 --exec C300` makes `prog.sxe`. While the waiting screen is up, send it as
**binary**, 9600 baud 8N1, no flow control, **no transmit delay** (`pc-settings\TeraTerm_SXRECV1600_9600.INI`).

## The .sxe file format (why escaped)

On a real PC-1600 the byte `11h` (XON) was swallowed by the serial layer even with XON/XOFF switched off in
`SETCOM` (seen with `hello_1600`: both `11h` bytes missing, then `ERR 8`). So the sender escapes every byte
that a serial layer or terminal might eat: `0Ah 0Dh 0Eh 0Fh 11h 13h 1Ah 7Dh` are sent as `7Dh`, then the byte
xor `20h`. Everything else is the `.sxb` layout of `..\PC-G8xx\README.md`: marker **`SE`** (not `SX`),
load address, length, start address, header check, data, CRC-16/XMODEM (high byte first). The header
check, length and CRC refer to the **unescaped** bytes. A plain `.sxb` is not recognised (nothing happens).

## 4. Result

```
OK 23 bytes at &C300
Run &C300 ? (Y/N)          (only when the file has a start address)
```
`Y` runs it with `CALL`; end the program with `RET`. Errors show `ERR<n>` and a text:

| n | Text | Meaning |
|---|---|---|
| 2 | `CRC - send again` | CRC wrong; the bytes are stored but damaged |
| 3 | `address refused` | outside `C246..T` (nothing stored) |
| 4 | `bad header` | header check failed or length 0 (nothing stored) |
| 6 | `serial error` | the ROM reported receive errors and the CRC is wrong: check baud/format/cable |
| 7 | `stopped (BRK)` | BREAK pressed |
| 8 | `timeout` | no byte for ~4 s in the data phase. Line 2: `n of m bytes` (data stopped), or `data ok, CRC missing` (data complete, the 2 CRC bytes did not come: a byte was lost earlier). Line 3 shows the first 8 bytes stored at the load address (compare with your program) |
| 9 | `SXBIN did not run` | |

A receive error that does not damage the data (CRC OK) is ignored: status 0.

## Larger sample: graphics demo

`samples\gfxdemo_1600.sxe` (2749 bytes to send, about 3 s) is a demo made with SharpPocketLib's
`PC-1600/graphics/plot_1600.asm`: nested boxes and a line fan, string art, concentric circles, a bouncing
ball, a marching block, a final disc. It loads at `C250` (start `C250`), so after the usual setup
(`NEW "S0:",&1000`, stub, `RUN`) send it and answer `Y` to `Run &C250 ?`. BREAK stops it; it returns to
BASIC by itself. Its 624-byte screen buffer lives at `CD00-CF6F`, inside the reserved area but not in the
file. Source: SharpPocketLib `PC-1600/sxbin/demo/gfxdemo_1600.asm` (the same `bin2sxe` command with
`C250` makes the `.sxe`). Confirmed on a real PC-1600.

## Using the receiver without the stub

Receiver at `C0C5`, entry `CALL &C0C5+16` (= `&C0D5`) after `POKE`ing the allowed range: word at
`&C0D8` = lowest address, word at `&C0DA` = highest (inclusive); default highest = 0 refuses everything.
Result block: `C0C5` status, `C0C7/8` bytes not received, `C0C9-C0CF` header (load, length, exec, check),
`C0D0` nonzero = a receive error was seen. Layout and details: header of `sxbin_1600.asm`.

## Troubleshooting

- `ERR SXBIN DATA damaged`: the stub was not loaded completely; load it again.
- Nothing arrives: if `SNDSTAT/RCVSTAT` handshaking is on and the cable has no CTS, try
  `RCVSTAT "COM1:",28` (checks off). Send only after the waiting screen shows (the 512-byte buffer
  overflows if you send before SXBIN fetches).
- The timeout is counted in polls (one ROM poll ~0.3 ms in the emulator, so ~4 s); not measured on real hardware.
- Error 8 after a good header, with `data ok, CRC missing` and stored bytes that lack some value (e.g. all
  `11h`): the file was not an escaped `.sxe`, or the sender does not send Binary / adds delays.
- Keep every stub line short if you retype it (the emulator editor refused lines of about 80+ characters).

## Tests

In SharpPocketLib: `PC-1600/sxbin/run_tests.py` (10 runs in Calc-U-1600: good file with junk before
the marker, bad CRC, address below/above range, bad header, truncated, receive-error flag with good and
bad CRC, and the whole stub end to end). The serial IOCS is shimmed there.

Copyright (c) 2026 Radovan Hrebicek. MIT License (see `..\LICENSE`).
