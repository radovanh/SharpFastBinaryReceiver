; hello_1600 -- sample program for SXRECV1600: prints PROG RAN on the PC-1600 and returns to BASIC.
; Build:  python z80asm.py hello_1600.asm
; Send:   python ../../PC-G8xx/bin2sxb.py hello_1600.bin C300 --exec C300
	org	0xC300
	ld	de,0x0002	; D = column 0, E = row 2
	call	0x0115		; CRSRSET
	ld	de,msg
	xor	a		; terminator 0
	call	0x00EB		; PRTASTR
	ret
msg:	db	"PROG RAN",0
