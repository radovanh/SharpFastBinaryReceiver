;==============================================================================
; sxbin.asm -- SXBIN, the resident binary receiver of the G8xx Serial Loader
;              (SX_MODEL 1: PC-G850V/VS, USART; 2: PC-G850/G850S, bit-bang;
;               3: PC-G815, bit-bang; 4: PC-E220, bit-bang + screen)
;
; WHAT IT DOES
;   Receives ONE file in the SXB format over the 11-pin port and stores it
;   straight at its load address. The BASIC stub (or MON R, see README) puts
;   this 0x0100-based image in RAM and calls it with CALL &H110. It returns to
;   the caller when the CRC has been checked, or at the first error / BREAK.
;
; THE SXB FORMAT (same layout as the Casio .vxb, marker "SX")
;   +0  'S' 'X'        marker; anything before it is skipped
;   +2  load address   low byte first
;   +4  length n       low byte first, 1..65535
;   +6  exec address   low byte first, 0xFFFF = none
;   +8  header check   bytes +2..+8 add up to 0 (mod 256)
;   +9  n data bytes
;   then the CRC-16/XMODEM of the data, high byte first
;   The header is checked BEFORE anything is stored. A bad CRC is only found
;   at the end, when the bytes are already in place: send the file again.
;
; ADDRESS GUARD
;   The whole block must lie in SX_END .. (word at 0x7FFE)-1. The word at
;   0x7FFE is the start of the file area; MON USER1FFF moves it from 0x0100
;   to 0x2000, which is what reserves the machine-code area. Without USER the
;   limit is 0x0100 and everything is refused (status 3).
;
;
; MODELS (define SX_MODEL before assembling, default 1; the image of model 1 is
;   byte-identical to the one tested on a real PC-G850V)
;   1  PC-G850V/VS  USART ports 70h-74h, 63h, 60h (see SERIAL)
;   2  PC-G850/G850S  software UART on pins 7/6 (port 18h / 1Fh), 8 MHz, 9600 baud
;   3  PC-G815        the same, ~3.09 MHz (322 T per bit), 9600 baud
;   4  PC-E220        the receiver of model 3 (its ROM serial driver is the G815's) plus a screen front
;                     (fe_main at +16, bare receiver at +19). The E220 BASIC has no PEEK/POKE/CALL, so
;                     no stub: MON R installs it, MON G0110 runs it. -D SX_BIT_T=n sets another clock
;                     (cycles per bit = Hz / 9600; default 322 = 3.09 MHz, not measured on an E220)
;   The bit-banged receive is the one of link_bitbang.asm (confirmed on real
;   hardware); here it is a single routine (bb_recv) that keeps every register
;   (it works in the shadow set) so the store between two bytes takes ~100 T:
;   less than the time from the middle of the stop bit to the next start bit
;   (0.45 bit = 145 T on the G815). Polarity as the 11-pin port: start bit HIGH
;   (needs the inverting RS-232 cable). Line: 8N1; a 2nd stop bit on the PC side
;   only adds margin. No flow control.
;
; SERIAL (model 1)
;   The PC-G850V USART is POLLED with interrupts off (as link_sio.asm), 8N1,
;   no flow control: one byte takes ~8000 T at 9600 baud, the loop needs ~100.
;   The CRC is not computed per byte but over the stored block at the end.
;
; BLOCK AT SX_BASE (read/written by the BASIC stub with PEEK/POKE)
;   +0   STATUS  out  0 OK, 2 CRC wrong (bytes stored, damaged), 3 address
;                     refused (nothing stored), 4 bad header (nothing stored),
;                     6 UART error (bits in +11), 7 BREAK, 8 timeout,
;                     9 = receiver never ran
;   +1   BAUD    in   USART baud byte for port 70h: 0Dh = 9600 (default),
;                     0Ch = 4800, 0Eh = 19200 (08h|n -> 300 << n)
;   +2/3 LEFT    out  data bytes not yet received (0 = complete)
;   +4.. HDR     out  the 7 header bytes: load, length, exec, check
;   +11  SERERR  out  USART status when status 6 happened
;   +12  SIGN    -    'S' 'X' 'B' '1', marks an installed copy
;   +16  entry   -    JP SX_MAIN (CALL &H110)
;
; Registers: AF BC DE HL and the interrupt state are restored on return.
; Build: python z80asm.py sxbin.asm  (-> sxbin.bin, loads at 0x0100)
;==============================================================================

	.if !defined(SX_MODEL)
SX_MODEL  = 1
	.endif
	#assert SX_MODEL >= 1 && SX_MODEL <= 4

SX_BASE   = 0x0100
SX_LIMIT  = 0x7ffe          ; word = start of the file area (MON USER moves it)
IDLE_RLD  = 1024            ; empty polls per idle tick (~20 ms at 8 MHz)
	.if SX_MODEL = 1
TMO_TICKS = 100             ; ticks without a byte before status 8 (data phase)
	.else
TMO_TICKS = 3               ; 65536-poll windows (51 T each) without a byte -> status 8
	.endif
	.if SX_MODEL = 2
BB_BIT_T  = 833             ; T-states per bit at 9600 baud, 8 MHz
	.endif
	.if SX_MODEL >= 3
	.if defined(SX_BIT_T)
BB_BIT_T  = SX_BIT_T        ; -D SX_BIT_T=n: another clock (n = clock in Hz / 9600)
	.else
BB_BIT_T  = 322             ; T-states per bit at 9600 baud, ~3.09 MHz (G815 measured; E220 assumed)
	.endif
	.endif
	.if SX_MODEL = 2
BB_RXD    = (BB_BIT_T - 65 + 8) / 16             ; data bit = 65 + 16 * BB_RXD (with the pad)
	.endif
	.if SX_MODEL >= 3
BB_RXD    = (BB_BIT_T - 50 + 8) / 16             ; data bit = 50 + 16 * BB_RXD (no pad)
	.endif
	.if SX_MODEL > 1                             ; same formulas as link_bitbang.asm
BB_RX1    = (BB_BIT_T * 3 / 2 - 25 - 49) / 16    ; edge -> middle of bit 0
BB_RXSTP  = 2 * BB_BIT_T / 38                    ; wait-for-stop polls (~2 bits)
	.endif

	org SX_BASE

sx_status:  db 9
sx_baud:    db 0x0d
sx_left:    dw 0
sx_hdr:     ds 7, 0
sx_serr:    db 0
sx_sign:    db 'S', 'X', 'B', '1'
	.if SX_MODEL = 4
sx_entry:   jp fe_main          ; at SX_BASE + 16: the receiver with its screen (CALL / MON G 0110)
sx_raw:     jp sx_main          ; at SX_BASE + 19: the bare receiver, no screen output
	.else
sx_entry:   jp sx_main          ; at SX_BASE + 16
	.endif

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
	ld A, I
	push AF                 ; P/V = IFF2: were interrupts on?
	di
	.if SX_MODEL > 1
	exx                     ; bb_recv works in the shadow set: keep the caller's
	push HL
	push DE
	push BC
	exx
	.endif
	ld (sx_sp), SP          ; stack at entry, for the exits

	ld A, #9
	ld (sx_status), A
	ld BC, #0               ; BC = data bytes left; 0 until the data phase
	ld (sx_left), BC
	ld HL, #IDLE_RLD
	ld (sx_idle), HL
	xor A
	ld (sx_tmo), A          ; no timeout while waiting for the file

	.if SX_MODEL = 1
	; USART on, 8N1, receiver enabled, RTS/DTR on
	ld A, #0x02
	out (#0x60), A          ; 11-pin I/F = USART
	ld A, #0x01
	out (#0x74), A          ; USART on
	xor A
	out (#0x73), A          ; reset pulse -> expects a mode byte
	inc A
	out (#0x73), A
	xor A
	out (#0x73), A
	ld A, (sx_baud)
	out (#0x70), A
	ld A, #0x4e
	out (#0x71), A          ; mode: 8 data, no parity, 1 stop, x16
	ld A, #0x10
	out (#0x71), A          ; error reset
	xor A
	out (#0x63), A
	ld A, #0x04
	out (#0x71), A          ; RxE
	ld A, #0x14
	out (#0x63), A          ; RTS, DTR on
	in A, (#0x72)           ; discard anything stale
	.else
	.if SX_MODEL = 2
	xor A
	out (#0x60), A          ; 11-pin I/F = 3in3out (not USART / PIO)
	.endif
	ld A, #0x80
	out (#0x15), A          ; port 15h bit 7 = 1: Xin input enabled
	ld A, #0x03
	out (#0x18), A          ; BUSY/Dout HIGH, Xout LOW = idle (mark)
	.endif

;--- find the marker "SX" ----------------------------------------------------
sync:
	call getc
sync_s:
	cp #'S'
	jr NZ, sync
	call getc
	cp #'X'
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

;--- address guard: SX_END <= A and A + n <= (0x7FFE) ----------------------------
	ld HL, (sx_hdr)
	ld DE, #sx_end
	or A
	sbc HL, DE
	ld A, #3
	jp C, sx_exit           ; below the end of the receiver
	ld HL, (sx_hdr)
	ld DE, (sx_hdr + 2)
	add HL, DE              ; A + n
	jp C, sx_exit           ; runs past 0xFFFF
	ld DE, (SX_LIMIT)       ; start of the file area
	or A
	sbc HL, DE              ; (A + n) - limit
	jr C, guard_ok
	jr Z, guard_ok
	jp sx_exit              ; last byte >= limit
guard_ok:

;--- the data ---------------------------------------------------------------------
	ld HL, (sx_hdr)
	ld BC, (sx_hdr + 2)
	ld (sx_left), BC
	ld A, #TMO_TICKS
	ld (sx_tmo), A
	.if SX_MODEL > 1
dloop:
	call bb_recv
	ld (HL), A
	inc HL
	dec BC
	ld A, #TMO_TICKS
	ld (sx_tmo), A
	ld A, B
	or C
	jr NZ, dloop
	.else
dloop:
	in A, (#0x71)
	and #0x3a               ; RxRDY (02h) and the PE/OE/FE bits
	jr Z, dwait
	cp #2
	jp NZ, ser_err
	in A, (#0x72)
	ld (HL), A
	inc HL
	dec BC
	ld A, #TMO_TICKS
	ld (sx_tmo), A
	ld A, B
	or C
	jr NZ, dloop
	jr dend
dwait:
	call idle
	jr dloop
	.endif
dend:
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
	ld A, #2

;--- exit: A = status ----------------------------------------------------------------
sx_exit:
	ld SP, (sx_sp)
	ld (sx_status), A
	ld (sx_left), BC
	xor A
	.if SX_MODEL = 1
	out (#0x63), A          ; RTS/DTR off
	out (#0x74), A          ; USART off
	out (#0x60), A          ; back to 3in3out
	.else
	out (#0x18), A          ; all outputs LOW
	exx
	pop BC
	pop DE
	pop HL
	exx
	.endif
	pop AF
	jp PO, sx_ret
	ei
sx_ret:
	pop HL
	pop DE
	pop BC
	pop AF
	ret

	.if SX_MODEL = 1
ser_err:
	in A, (#0x71)
	ld (sx_serr), A
	ld A, #6
	jr sx_exit

;------------------------------------------------------------------------
; getc -- next byte in A (waits; BREAK and timeout leave through sx_exit).
; Preserves BC, DE, HL.
;------------------------------------------------------------------------
getc:
	in A, (#0x71)
	and #0x3a
	jr Z, getc_wait
	cp #2
	jr NZ, ser_err
	in A, (#0x72)
	ret
getc_wait:
	call idle
	jr getc

;------------------------------------------------------------------------
; idle -- one empty poll. Every IDLE_RLD polls: BREAK check and the timeout.
; Preserves BC, DE, HL.
;------------------------------------------------------------------------
idle:
	push HL
	ld HL, (sx_idle)
	dec HL
	ld (sx_idle), HL
	ld A, H
	or L
	jr NZ, idle_ret
	ld HL, #IDLE_RLD
	ld (sx_idle), HL
	in A, (#0x1f)
	rlca
	jr C, idle_brk          ; BREAK
	ld A, (sx_tmo)
	or A
	jr Z, idle_ret          ; timeout not armed yet
	dec A
	ld (sx_tmo), A
	jr Z, idle_tmo
idle_ret:
	pop HL
	ret
idle_brk:
	ld A, #7
	jp sx_exit
idle_tmo:
	ld A, #8
	jp sx_exit
	.endif

	.if SX_MODEL > 1
;------------------------------------------------------------------------
; bb_recv (= getc) -- receive one 8N1 frame in A; every other register and the
; flags except A are kept (the work is done in the shadow set). Waits for a start
; bit; BREAK, timeout (armed in the data phase) and a framing error leave through
; sx_exit. Bit timing as link_bitbang.asm phy_recv_byte.
;------------------------------------------------------------------------
getc:
bb_recv:
	exx
bb_w0:
	ld DE, #0               ; window of 65536 polls
bb_wait:                    ; 51 T per poll
	in A, (#0x1f)
	and #0x84               ; bit 7 = BREAK, bit 2 = Xin
	jr NZ, bb_edge
	dec DE
	ld A, D
	or E
	jr NZ, bb_wait
	ld A, (sx_tmo)          ; window over: armed?
	or A
	jr Z, bb_w0
	dec A
	ld (sx_tmo), A
	jr NZ, bb_w0
	exx
	ld A, #8
	jp sx_exit
bb_edge:
	jp P, bb_start          ; not BREAK: a start bit
	exx
	ld A, #7
	jp sx_exit
bb_start:
	ld D, #BB_RX1           ; first sample 1.5 bits after the edge
bb_d1:
	dec D
	jr NZ, bb_d1
	ld B, #8
bb_bit:                     ; one data bit = 50 (+15 pad on the G850) + 16 * BB_RXD
	in A, (#0x1f)           ; sample
	cpl                     ; Xin LOW = 1
	rra
	rra
	rra                     ; bit 2 -> Cy
	rr C                    ; LSB first
	.if SX_MODEL = 2
	cp #0                   ; pad
	nop
	nop
	.endif
	ld D, #BB_RXD
bb_d:
	dec D
	jr NZ, bb_d
	djnz bb_bit
	ld B, #BB_RXSTP         ; stop bit: the line must be LOW again within ~2 bits
bb_stop:                    ; 38 T per poll
	in A, (#0x1f)
	and #0x04
	jr Z, bb_ok
	djnz bb_stop
	exx
	ld A, #1
	ld (sx_serr), A         ; framing error
	ld A, #6
	jp sx_exit
bb_ok:
	ld A, C
	exx
	ret
	.endif

	.if SX_MODEL = 4
;==============================================================================
; PC-E220 front end. The E220's BASIC has no PEEK, POKE or CALL, so there is no BASIC stub:
; the image is loaded with MON R and started with MON G0110. fe_main shows the waiting screen,
; runs the receiver (sx_main), shows the result, and offers to run the program (Y/N) if the
; file has a start address. Uses three ROM entries (bank 0, the same addresses as the PC-G815):
;   BFF1h  putstr  HL = text, B = length, D = row, E = column
;   BFEEh  rptchr  A = character, B = count, D = row, E = column
;   BE53h  key scan: Cy = 1 and A = key code (Y = 07h) when a key is down
; Every text line is at most 24 characters (no wrap, no scroll).
;==============================================================================
ROM_KEY   = 0xbe53
ROM_PUTS  = 0xbff1
ROM_RPT   = 0xbfee
KEY_Y     = 0x07

fe_main:
	push AF
	push BC
	push DE
	push HL
	call fe_cls

	ld HL, #t_title
	ld B, #t_title_e - t_title
	ld C, #0
	call fe_line
	ld DE, #fe_buf              ; "Free 0300-1FFF": the area the program may occupy
	ld HL, #t_free
	ld B, #5
	call fe_cat
	ld HL, #sx_end
	call fe_h16
	ld A, #'-'
	ld (DE), A
	inc DE
	ld HL, (SX_LIMIT)
	dec HL
	call fe_h16
	ld C, #1
	call fe_out
	ld HL, #t_send
	ld B, #t_send_e - t_send
	ld C, #2
	call fe_line
	ld HL, #t_brk
	ld B, #t_brk_e - t_brk
	ld C, #3
	call fe_line

	call sx_main                ; ---- the transfer ----

	call fe_cls
	ld A, (sx_status)
	or A
	jr NZ, fe_err

	ld DE, #fe_buf              ; "OK 03E8 bytes at 1000"
	ld HL, #t_ok
	ld B, #3
	call fe_cat
	ld HL, (sx_hdr + 2)
	call fe_h16
	ld HL, #t_at
	ld B, #t_at_e - t_at
	call fe_cat
	ld HL, (sx_hdr)
	call fe_h16
	ld C, #0
	call fe_out
	ld HL, (sx_hdr + 4)         ; start address
	ld A, H
	and L
	inc A
	jr Z, fe_done               ; 0FFFFh = none
	ld DE, #fe_buf              ; "Run 1000 ? (Y/N)"
	ld HL, #t_run
	ld B, #4
	call fe_cat
	ld HL, (sx_hdr + 4)
	call fe_h16
	ld HL, #t_yn
	ld B, #t_yn_e - t_yn
	call fe_cat
	ld C, #1
	call fe_out
fk1:
	call ROM_KEY                ; wait until all keys are up,
	jr C, fk1
fk2:
	call ROM_KEY                ; then for one
	jr NC, fk2
	cp #KEY_Y
	jr Z, fe_run
	cp #KEY_Y + 0x80            ; SHIFT-Y
	jr NZ, fe_done
fe_run:
	ld HL, (sx_hdr + 4)
	call fe_jp                  ; the program ends with RET
fe_done:
	pop HL
	pop DE
	pop BC
	pop AF
	ret
fe_jp:
	jp (HL)

fe_err:                         ; A = status: "ERR2 CRC - send again"
	ld C, A
	ld DE, #fe_buf
	ld HL, #t_err
	ld B, #3
	call fe_cat
	ld A, C
	add A, #'0'
	ld (DE), A
	inc DE
	ld A, #' '
	ld (DE), A
	inc DE
	ld HL, #fe_et               ; record = status, length, text; 0FFh = "error"
fe_f1:
	ld A, (HL)
	cp #0xff
	jr Z, fe_f2
	cp C
	jr Z, fe_f2
	inc HL
	ld A, (HL)
	inc HL
	add A, L
	ld L, A
	jr NC, fe_f1
	inc H
	jr fe_f1
fe_f2:
	inc HL
	ld B, (HL)
	inc HL
	call fe_cat
	ld C, #0
	call fe_out
	ld A, (sx_status)
	cp #6
	jr C, fe_done               ; 2, 3, 4: nothing to add
	ld HL, (sx_left)
	ld A, H
	or L
	jr Z, fe_done               ; the data phase never began
	ld DE, #fe_buf              ; "01F4 of 03E8 bytes"
	ld HL, (sx_hdr + 2)
	ld BC, (sx_left)
	or A
	sbc HL, BC
	call fe_h16
	ld HL, #t_of
	ld B, #t_of_e - t_of
	call fe_cat
	ld HL, (sx_hdr + 2)
	call fe_h16
	ld HL, #t_bytes
	ld B, #t_bytes_e - t_bytes
	call fe_cat
	ld C, #1
	call fe_out
	jr fe_done

;--- fe_cls: blank the four rows -------------------------------------------------------
fe_cls:
	ld C, #0
fe_cl1:
	push BC
	ld A, #' '
	ld B, #24
	ld D, C
	ld E, #0
	call ROM_RPT
	pop BC
	inc C
	ld A, C
	cp #4
	jr NZ, fe_cl1
	ret

;--- fe_cat: append B characters at (HL) to the line buffer at (DE) -----------------------
fe_cat:
	ld A, B
	or A
	ret Z
fe_ca1:
	ld A, (HL)
	ld (DE), A
	inc HL
	inc DE
	djnz fe_ca1
	ret

;--- fe_h16: append HL as 4 hex digits at (DE) -------------------------------------------
fe_h16:
	ld A, H
	call fe_hb
	ld A, L
fe_hb:
	push AF
	rrca
	rrca
	rrca
	rrca
	call fe_nib
	pop AF
fe_nib:
	and #0x0f
	add A, #'0'
	cp #'9' + 1
	jr C, fe_nb1
	add A, #7
fe_nb1:
	ld (DE), A
	inc DE
	ret

;--- fe_line: HL / B = text, C = row; fe_out: the buffer up to (DE) on row C ----------------
fe_line:
	ld DE, #fe_buf
	call fe_cat
fe_out:
	ld HL, #fe_buf
	ex DE, HL
	or A
	sbc HL, DE                  ; HL = length
	ld B, L
	ld D, C
	ld E, #0
	ld HL, #fe_buf
	jp ROM_PUTS

t_title:  db "SXBIN E220 9600 8N2"
t_title_e:
t_free:   db "Free "
t_send:   db "Send .SXB as binary"
t_send_e:
t_brk:    db "No flow ctl. BRK=stop"
t_brk_e:
t_ok:     db "OK "
t_at:     db " bytes at "
t_at_e:
t_run:    db "Run "
t_yn:     db " ? (Y/N)"
t_yn_e:
t_err:    db "ERR"
t_of:     db " of "
t_of_e:
t_bytes:  db " bytes"
t_bytes_e:

fe_et:
	db 2, e2_e - e2
e2:	db "CRC - send again"
e2_e:
	db 3, e3_e - e3
e3:	db "address refused"
e3_e:
	db 4, e4_e - e4
e4:	db "bad header"
e4_e:
	db 6, e6_e - e6
e6:	db "framing - baud?"
e6_e:
	db 7, e7_e - e7
e7:	db "stopped (BRK)"
e7_e:
	db 8, e8_e - e8
e8:	db "timeout"
e8_e:
	db 0xff, ef_e - ef
ef:	db "error"
ef_e:

fe_buf:   ds 28, 0
	.endif

sx_end:
