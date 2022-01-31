section .rodata
ALIGN 16
mascaraBits2y3: times 4 dd 0x0003_0303
mascaraBitsEncriptados: times 4 dd 0x0002_0000
mascaraShuffleLow: dq 0x80040404_80000000
mascaraShuffleHigh: dq 0x800C0C0C_80080808
mascaraComponenteA: times 4 dd 0xFF00_0000

section .text
global Descubrir_asm

Descubrir_asm:

 	; -- Parámetros de entrada --
	; rdi <- *src  -> imagen color que contiene imagen oculta
	; rsi <- *dst  -> imagen en escala de grises
	; edx <- width
	; ecx <- height

	push rbp
	mov rbp, rsp

	; -- Máscaras --

	%define filtroBits2y3 xmm15
	%define filtroBitsEncriptados xmm14
	%define shuffleLow xmm13
	%define shuffleHigh xmm12
	%define componenteA xmm11

	%define px_size 4

	movd xmm0, ecx
	movd xmm1, edx
	pmuldq xmm0, xmm1     ; obtener tamaño en px: height*width
	movq r8, xmm0

	; Imagen espejo: obtener puntero al final
	mov rax, r8       ; rax -> size
	shl rax, 2        ; size*4 (cantidad de bytes)
	add rax, rdi      ; posición inmediatamente posterior al fin de la imagen
	sub rax, 16       ; puntero a últimos 4 px

	xor rcx, rcx      ; contador de px procesados (+8 en cada ciclo)

ciclo:
	cmp rcx, r8
	je fin

	add rsi, 8*px_size
	add rdi, 8*px_size
	sub rax, 8*px_size
	add rcx, 8
	jmp ciclo

fin:
	pop rbp
	ret
