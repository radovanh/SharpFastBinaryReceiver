; prog_hello_e220.asm -- tiny payload for the PC-E220: prints PROG RAN on the last row (3), returns to MON.
	org 0x1000
	ld HL, #msg
	ld B, #8
	ld D, #3
	ld E, #0
	call 0xbff1             ; ROM putstr
	ret
msg:
	db "PROG RAN"
