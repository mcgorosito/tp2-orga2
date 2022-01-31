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
	movdqa xmm15, [mascaraBits2y3]
	movdqa xmm14, [mascaraBitsEncriptados]
	movdqa xmm13, [mascaraShuffleLow]
	movdqu xmm12, [mascaraShuffleHigh]
	movdqa xmm11, [mascaraComponenteA]

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

	; Cargar 8 px de src    
    movdqa xmm0, [rdi]              ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+4*px_size]    ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|

	; 1) Desencriptar
    movdqa xmm2, [rax]              ; cargar últimos 4 px
    movdqa xmm3, [rax-4*px_size]    ; cargar anteúltimos 4 px
    
	movdqa [rsi], xmm0          ; guardar en destino
	movdqa [rsi+4*px_size], xmm1

	add rsi, 8*px_size
	add rdi, 8*px_size
	sub rax, 8*px_size
	add rcx, 8
	jmp ciclo

fin:
	pop rbp
	ret
