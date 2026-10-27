; prog_hello.asm -- tiny payload for the stub's "Run?" test: prints PROG RAN on row 4, returns to BASIC.
	org 0x1000
	ld HL, #msg
	ld B, #8
	ld D, #4
	ld E, #0
	call 0xbff1             ; ROM putstr
	ret
msg:
	db "PROG RAN"
