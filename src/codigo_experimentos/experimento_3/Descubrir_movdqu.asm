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

	add rsi, 2*px_size
	add rdi, 2*px_size
	sub rax, 2*px_size
	add rcx, 2
	sub r8, 6

ciclo:
	cmp rcx, r8
	je fin

	; Cargar 8 px de src    
    movdqu xmm0, [rdi]              ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqu xmm1, [rdi+4*px_size]    ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|

	; Extraer últimos dos bits de componentes B, G y R con máscara
    pand xmm0, filtroBits2y3        ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3        ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4

	; 1) Desencriptar
    movdqu xmm2, [rax]              ; cargar últimos 4 px
    movdqu xmm3, [rax-4*px_size]    ; cargar anteúltimos 4 px
    pshufd xmm4, xmm2, 0x1B         ; invertir orden: | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B         ;                 | p56 | p57 | p58 | p59 |

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en pos menos significativas
    psrlw xmm5, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4           ; xor últimos 4 con primeros 4
	pxor xmm1, xmm5           ; xor anteúltimos 4 con segundos 4

	; Bits desencriptados en xmm0 y xmm1
    ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4 
    ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4
    ; Objetivo: Armar pixel en escala de grises:  |b7 b6 b5 b4 b3 b2 0 0|
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0         ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	pand xmm2, xmm10          ; filtrar con máscara
	pand xmm3, xmm10
	psrld xmm2, 15            ; shiftear de pos 17 a 2
	psrld xmm3, 15

	; Separar bit 3 con mascara 0x0000_0200
	psrldq xmm10, 1           ; shiftear mascara 1 byte a der (para evitar saltar)
	movdqa xmm4, xmm0         ; copiar reg con bits desencriptados
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6             ; shiftear de pos 9 a 3
	psrld xmm5, 6
	por xmm2, xmm4            ; combinar con bit 2
	por xmm3, xmm5

	; Separar bit 4 con mascara 0x0000_0002
	psrldq xmm10, 1           ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	pslld xmm4, 3             ; shiftear de pos 1 a 4
	pslld xmm5, 3
	por xmm2, xmm4            ; combinar con bits 2 y 3
	por xmm3, xmm5
	
	; Separar bit 5 con mascara 0x0001_0000
	pslld xmm10, 15           ; shiftear mascara
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11            ; shiftear de pos 16 a 5
	psrld xmm5, 11
	por xmm2, xmm4
	por xmm3, xmm5            ; combinar con bits 2:4

	; Separar bit 6 con mascara 0x0000_0100
	psrldq xmm10, 1           ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2             ; shiftear de pos 8 a 6
	psrld xmm5, 2
	por xmm2, xmm4
	por xmm3, xmm5            ; combinar con bits 2:5

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1           ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pslld xmm0, 7             ; shiftear de pos 0 a 7
	pslld xmm1, 7
	por xmm0, xmm2
	por xmm1, xmm3            ; combinar con bits 2:6

	movdqa xmm2, shuffleLow     ; copiar el bit de grises en las 3 componentes
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	por xmm0, componenteA       ; rellenar componente A con FF
	por xmm1, componenteA

	movdqu [rsi], xmm0          ; guardar en destino
	movdqu [rsi+4*px_size], xmm1

	add rsi, 8*px_size
	add rdi, 8*px_size
	sub rax, 8*px_size
	add rcx, 8
	jmp ciclo

fin:
	pop rbp
	ret
