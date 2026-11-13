;==============================================================================
; sxbin_1600.asm -- SXBIN for the Sharp PC-1600: resident binary receiver
;                   of the Serial Loader kit (same .sxb format as PC-G8xx / PC-E220)
;
; WHAT IT DOES
;   Receives ONE file in the SXB format from COM1: and stores it straight at its
;   load address. The BASIC stub (sxrecv1600.bas) puts this image at C0C5 (the
;   start of the machine-code area reserved with NEW "S0:",&1000), sets the
;   allowed address range and calls it with CALL &C0C5+16. It returns to BASIC
;   when the CRC has been checked, or at the first error / BREAK.
;
; HOW IT READS THE PORT
;   Through the ROM serial IOCS (CALL 01D8h, C = 07h CRCV1, D = 01h COM1:):
;   the ROM interrupt handler collects the bytes in the COM1: receive buffer
;   (INIT "COM1:",n), this code only fetches them. So interrupts stay ON, no
;   bit timing is needed, and the sender may be as fast as 9600 baud and more
;   (whatever SETCOM set). Same line settings as BASIC LOAD "COM1:".
;   CRCV1 returns ZF=1 when the buffer is empty, CF=1 on a receive error
;   (TRM 3.6.3). A CF error is only NOTED here (sx_serr); the CRC decides if
;   the data are good.
;
; THE SXB FORMAT (same layout as the Casio .vxb, marker "SX")
;   +0  'S' 'E'        marker ("SX" escaped); anything before it is skipped
;   +2  load address   low byte first
;   +4  length n       low byte first, 1..65535
;   +6  exec address   low byte first, 0xFFFF = none
;   +8  header check   bytes +2..+8 add up to 0 (mod 256)
;   +9  n data bytes
;   then the CRC-16/XMODEM of the data, high byte first
;   ESCAPING (whole file after the marker): 0Ah 0Dh 0Eh 0Fh 11h 13h 1Ah 7Dh are sent as
;   7Dh, (byte xor 20h). Header check, length and CRC refer to the UNESCAPED bytes.
;   Make such files (.sxe) with bin2sxe.py.
;
; ADDRESS GUARD
;   The whole block must lie in sx_lo .. sx_hi or in sx_lo2 .. sx_hi2 (inclusive). The stub POKEs
;   them before the call. Default sx_hi = 0 = everything is refused (status 3); the second range is
;   off by default (sx_lo2 = 1, sx_hi2 = 0: no block can lie in it).
;
; BLOCK AT SX_BASE (read/written by the BASIC stub with PEEK/POKE)
;   +0   STATUS  out  0 OK, 2 CRC wrong (bytes stored, damaged), 3 address refused
;                     (nothing stored), 4 bad header (nothing stored), 6 serial error
;                     seen and CRC wrong, 7 BREAK, 8 timeout, 9 = never ran
;   +1   spare
;   +2/3 LEFT    out  data bytes not yet received (0 = complete)
;   +4.. HDR     out  the 7 header bytes: load, length, exec, check
;   +11  SERERR  out  nonzero = CRCV1 reported CF (receive error) at least once
;   +12  SIGN    -    'S' 'X' '1' '6', marks an installed copy
;   +16  entry   -    JP SX_MAIN (CALL &C0C5+16)
;   +19  LO      in   lowest allowed address (word)
;   +21  HI      in   highest allowed address (word, inclusive)
;   +23  LO2     in   second allowed range, lowest address (word); default 1
;   +25  HI2     in   second allowed range, highest address (word, inclusive); default 0 = no second range
;                     (the stub sets 80C5..BFFF for a LARGE SBC program in a memory module, see sxrecv1600.bas)
;
; Registers: AF BC DE HL and the interrupt state are kept. IX/IY/shadow set not used.
; Build: python z80asm.py sxbin_1600.asm  (-> sxbin_1600.bin, loads at 0xC0C5)
;   -D SX_BASE=n  another load address
; Test hook: define SERIELL before including to replace the ROM entry (see
;   PC-1600/sxbin tests in SharpPocketLib).
;==============================================================================

	.if !defined(SX_BASE)
SX_BASE   = 0xc0c5
	.endif
	.if !defined(SERIELL)
SERIELL   = 0x01d8          ; ROM RS-232C IOCS dispatch, IOCS number in C, channel in D
	.endif
BREAKCHK  = 0x016f          ; CF=1: BREAK key pressed (clears the key buffer)
BREAKRESET = 0x018a         ; clear the BREAK latch
IOCS_CRCV1 = 0x07           ; receive one byte, do not wait
IOCS_CCLRRB = 0x1c          ; clear the receive buffer and error flags
CH_COM1   = 0x01

IDLE_RLD  = 64              ; empty polls per idle tick (BREAK check, timeout step)
TMO_TICKS = 200             ; ticks without a byte in the data phase -> status 8 (~4 s: one poll
                            ; through the ROM takes ~0.3 ms in the emulator, 64 polls per tick)

	org SX_BASE

sx_status:  db 9
sx_spare:   db 0
sx_left:    dw 0
sx_hdr:     ds 7, 0
sx_serr:    db 0
sx_sign:    db 'S', 'X', '1', '6'
sx_entry:   jp sx_main          ; at SX_BASE + 16
sx_lo:      dw sx_end           ; at SX_BASE + 19
sx_hi:      dw 0                ; at SX_BASE + 21
sx_lo2:     dw 1                ; at SX_BASE + 23
sx_hi2:     dw 0                ; at SX_BASE + 25
sx_last:    dw 0

sx_sp:      dw 0
sx_idle:    dw 0
sx_tmo:     db 0
sx_crc:     dw 0

;------------------------------------------------------------------------
sx_main:
	push AF
	push BC
	push DE
	push HL
	ld (sx_sp), SP          ; stack at entry, for the exits

	ld C, #IOCS_CCLRRB      ; drop stale bytes (e.g. the end of the stub transfer)
	ld D, #CH_COM1
	call SERIELL

	ld A, #9
	ld (sx_status), A
	ld BC, #0               ; BC = data bytes left; 0 until the data phase
	ld (sx_left), BC
	ld HL, #IDLE_RLD
	ld (sx_idle), HL
	xor A
	ld (sx_tmo), A          ; no timeout while waiting for the file
	ld (sx_serr), A

;--- find the marker "SX" ----------------------------------------------------
sync:
	call getc
sync_s:
	cp #'S'
	jr NZ, sync
	call getc
	cp #'E'
	jr NZ, sync_s           ; "SS..." : the second S may start the marker

;--- the 7 header bytes into sx_hdr, summing them ------------------------------
	ld HL, #sx_hdr
	ld D, #7
	ld E, #0
hdr_lp:
	call getc
	ld (HL), A
	inc HL
	add A, E
	ld E, A
	dec D
	jr NZ, hdr_lp
	ld A, E
	or A
	ld A, #4
	jp NZ, sx_exit          ; header bytes do not add up to 0
	ld DE, (sx_hdr + 2)
	ld A, D
	or E
	ld A, #4
	jp Z, sx_exit           ; length 0

;--- address guard: the block must lie in sx_lo..sx_hi or in sx_lo2..sx_hi2 ------------------
	ld HL, (sx_hdr)
	ld DE, (sx_hdr + 2)
	add HL, DE              ; load + n
	ld A, #3
	jp C, sx_exit           ; runs past 0xFFFF
	dec HL                  ; last byte
	ld (sx_last), HL
	ld DE, (sx_lo)
	ld BC, (sx_hi)
	call inrange
	jr NC, guard_ok
	ld DE, (sx_lo2)
	ld BC, (sx_hi2)
	call inrange
	jr NC, guard_ok
	ld A, #3
	jp sx_exit              ; outside both ranges
guard_ok:

;--- the data ---------------------------------------------------------------------
	ld HL, (sx_hdr)
	ld BC, (sx_hdr + 2)
	ld (sx_left), BC
dloop:
	ld A, #TMO_TICKS
	ld (sx_tmo), A
	call getc
	ld (HL), A
	inc HL
	dec BC
	ld A, B
	or C
	jr NZ, dloop
	ld (sx_left), BC        ; 0

	call getc               ; CRC, high byte first
	ld (sx_crc + 1), A
	call getc
	ld (sx_crc), A

;--- CRC-16/XMODEM over the stored block (sx_idle = bytes left) ------------------
	ld HL, (sx_hdr)
	ld DE, (sx_hdr + 2)
	ld (sx_idle), DE
	ld DE, #0
crc_byte:
	ld A, (HL)
	inc HL
	xor D
	ld D, A
	ld B, #8
crc_bit:
	sla E
	rl D
	jr NC, crc_nx
	ld A, D
	xor #0x10               ; polynomial 0x1021
	ld D, A
	ld A, E
	xor #0x21
	ld E, A
crc_nx:
	djnz crc_bit
	push HL
	ld HL, (sx_idle)
	dec HL
	ld (sx_idle), HL
	ld A, H
	or L
	pop HL
	jr NZ, crc_byte
	ld HL, (sx_crc)
	or A
	sbc HL, DE
	ld BC, #0               ; (B was the bit counter)
	ld A, #0
	jr Z, sx_exit
	ld A, (sx_serr)         ; CRC wrong: a receive error explains it
	or A
	ld A, #2
	jr Z, sx_exit
	ld A, #6

;--- exit: A = status ----------------------------------------------------------------
sx_exit:
	ld SP, (sx_sp)
	ld (sx_status), A
	ld (sx_left), BC
	pop HL
	pop DE
	pop BC
	pop AF
	ret

;------------------------------------------------------------------------
; inrange -- DE = lowest, BC = highest allowed address: CF=0 when sx_hdr (load) .. sx_last
; lie inside, CF=1 when outside. Clobbers HL, DE.
;------------------------------------------------------------------------
inrange:
	ld HL, (sx_hdr)
	or A
	sbc HL, DE              ; load - lo
	ret C                   ; below
	push BC
	pop HL
	ld DE, (sx_last)
	or A
	sbc HL, DE              ; hi - last
	ret                     ; CF=1: last > hi

;------------------------------------------------------------------------
; getc -- next byte of the file in A, escapes undone: 7Dh, x -> x xor 20h.
; (The sender escapes 0Ah 0Dh 0Eh 0Fh 11h 13h 1Ah and 7Dh: the PC-1600 serial layer
; swallowed 11h = XON on real hardware although SETCOM said no XON/XOFF.)
; Preserves BC, DE, HL.
;------------------------------------------------------------------------
getc:
	call getc_raw
	cp #0x7d
	ret NZ
	call getc_raw
	xor #0x20
	ret

;------------------------------------------------------------------------
; getc_raw -- next byte from COM1: in A (waits; BREAK and timeout leave through
; sx_exit). Preserves BC, DE, HL.
;------------------------------------------------------------------------
getc_raw:
	push BC
	push DE
gc_poll:
	ld C, #IOCS_CRCV1
	ld D, #CH_COM1
	call SERIELL            ; A = byte, ZF=1 empty, CF=1 error
	jr NC, gc_nc
	push AF
	ld A, #1
	ld (sx_serr), A
	pop AF
gc_nc:
	jr NZ, gc_got
	call idle               ; A = 0 go on, else a status code
	or A
	jr Z, gc_poll
	pop DE
	pop BC                  ; BC = bytes left, for sx_left
	jp sx_exit
gc_got:
	pop DE
	pop BC
	ret

;------------------------------------------------------------------------
; idle -- one empty poll. Every IDLE_RLD polls: BREAK check and the timeout.
; Returns A = 0, or 7 (BREAK) / 8 (timeout). Preserves BC, DE, HL.
;------------------------------------------------------------------------
idle:
	push HL
	ld HL, (sx_idle)
	dec HL
	ld (sx_idle), HL
	ld A, H
	or L
	jr NZ, idle_ok
	ld HL, #IDLE_RLD
	ld (sx_idle), HL
	call BREAKCHK
	jr C, idle_brk
	ld A, (sx_tmo)
	or A
	jr Z, idle_ok           ; timeout not armed yet
	dec A
	ld (sx_tmo), A
	jr Z, idle_tmo
idle_ok:
	xor A
	pop HL
	ret
idle_brk:
	call BREAKRESET
	ld A, #7
	pop HL
	ret
idle_tmo:
	ld A, #8
	pop HL
	ret

sx_end:
