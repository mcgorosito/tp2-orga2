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
	push rbp
	mov rbp, rsp

	movd xmm0, ecx
	movd xmm1, edx
	pmuldq xmm0, xmm1  ; obtener tamaño en px  height*width
	movq r8, xmm0

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

	; Imagen espejo: obtener puntero al final
	mov rax, r8       ; rax -> size
	shl rax, 2        ; size*4 (cantidad de bytes)
	add rax, rdi      ; posicion inmediatamente posterior al fin de la imagen
	sub rax, 16       ; dir de memoria de últimos 4 px

	; Trabajar 8 píxeles a la vez
	shr r8, 1        ; r8 -> cant ciclos: size/2 porque se cargan 4 bytes por registro (pero se incrementa de a dos)
	xor rcx, rcx     ; contador para recorrer la imagen cada 4 px y se incrementa de a 4 en cada ciclo

.ciclo:
	; Cargar 16 px de src    
    movdqa xmm0, [rdi+rcx*8]       ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+(rcx+2)*8]   ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|
    movdqa xmm8, [rdi+(rcx+4)*8]   ; xmm8 -> px 8-11
    movdqa xmm9, [rdi+(rcx+6)*8]   ; xmm9 -> px 12-15

	; Extraer últimos dos bits de componentes B, G y R con |0x00 0x03 0x03 0x03| x4
    pand xmm0, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4
    pand xmm8, filtroBits2y3
    pand xmm9, filtroBits2y3

; Desencriptar
    ; Cargar últimos 8 px
    movdqa xmm2, [rax]    ; xmm2 -> ultimos 4 px
    sub rax, 16
    movdqa xmm3, [rax]    ; xmm3 -> anteultimos 4 px
    sub rax, 16
    movdqa xmm6, [rax]
    sub rax, 16
    movdqa xmm7, [rax]
    sub rax, 16

    ; Invertir orden
    pshufd xmm4, xmm2, 0x1B    ; | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B    ; | p56 | p57 | p58 | p59 |
    pshufd xmm2, xmm6, 0x1B
    pshufd xmm3, xmm7, 0x1B

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en las pos menos significativas
    psrlw xmm5, 2
    psrlw xmm2, 2
    psrlw xmm3, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3
	pand xmm2, filtroBits2y3
	pand xmm3, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4         ; xor ultimos 4 con primeros 4
	pxor xmm1, xmm5         ; xor anteultimos 4 con segundos 4
	pxor xmm8, xmm2
	pxor xmm9, xmm3
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0   ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	movdqa xmm6, xmm8
	movdqa xmm7, xmm9
	pand xmm2, xmm10    ; filtrar con mascara
	pand xmm3, xmm10
	pand xmm6, xmm10
	pand xmm7, xmm10
	psrld xmm2, 15      ; shiftear de pos 17 a 2
	psrld xmm3, 15
	psrld xmm6, 15
	psrld xmm7, 15

	; Separar bit 3 con mascara 0x0000_0200
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der (para evitar saltar)
	movdqa xmm4, xmm0    ; copiar reg con bits desencriptados
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6        ; shiftear de pos 9 a 3
	psrld xmm5, 6
	por xmm2, xmm4       ; combinar con bit 2
	por xmm3, xmm5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6
	psrld xmm5, 6
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 4 con mascara 0x0000_0002
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	pslld xmm4, 3        ; shiftear de pos 1 a 4
	pslld xmm5, 3
	por xmm2, xmm4       ; combinar con bits 2 y 3
	por xmm3, xmm5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 3
	psrld xmm5, 3
	por xmm6, xmm4
	por xmm7, xmm5
	
	; Separar bit 5 con mascara 0x0001_0000
	pslld xmm10, 15      ; shiftear mascara
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11       ; shiftear de pos 16 a 5
	psrld xmm5, 11
	por xmm2, xmm4
	por xmm3, xmm5       ; combinar con bits 2:4

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11
	psrld xmm5, 11
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 6 con mascara 0x0000_0100
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2         ; shiftear de pos 8 a 6
	psrld xmm5, 2
	por xmm2, xmm4
	por xmm3, xmm5        ; combinar con bits 2:5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2
	psrld xmm5, 2
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1       ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pand xmm8, xmm10
	pand xmm9, xmm10
	pslld xmm0, 7         ; shiftear de pos 0 a 7
	pslld xmm1, 7
	pslld xmm8, 7
	pslld xmm9, 7
	por xmm0, xmm2
	por xmm1, xmm3        ; combinar con bits 2:6
	por xmm8, xmm6
	por xmm9, xmm7

	movdqa xmm2, shuffleLow
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	pshufb xmm8, xmm2
	pshufb xmm9, xmm2
	por xmm0, componenteA   ; rellenar componente A
	por xmm1, componenteA
	por xmm8, componenteA
	por xmm9, componenteA

	movdqa [rsi+rcx*8], xmm0     ; guardar en destino
	movdqa [rsi+(rcx+2)*8], xmm1
	movdqa [rsi+(rcx+4)*8], xmm8
	movdqa [rsi+(rcx+6)*8], xmm9

	add rcx, 8

	; Cargar 8 px de src    
    movdqa xmm0, [rdi+rcx*8]       ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+(rcx+2)*8]   ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|
    movdqa xmm8, [rdi+(rcx+4)*8]   ; xmm8 -> px 8-11
    movdqa xmm9, [rdi+(rcx+6)*8]   ; xmm9 -> px 12-15

	; Extraer últimos dos bits de componentes B, G y R con |0x00 0x03 0x03 0x03| x4
    pand xmm0, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4
    pand xmm8, filtroBits2y3
    pand xmm9, filtroBits2y3

; Desencriptar
    ; Cargar últimos 8 px
    movdqa xmm2, [rax]    ; xmm2 -> ultimos 4 px
    sub rax, 16
    movdqa xmm3, [rax]    ; xmm3 -> anteultimos 4 px
    sub rax, 16
    movdqa xmm6, [rax]
    sub rax, 16
    movdqa xmm7, [rax]
    sub rax, 16

    ; Invertir orden
    pshufd xmm4, xmm2, 0x1B    ; | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B    ; | p56 | p57 | p58 | p59 |
    pshufd xmm2, xmm6, 0x1B
    pshufd xmm3, xmm7, 0x1B

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en las pos menos significativas
    psrlw xmm5, 2
    psrlw xmm2, 2
    psrlw xmm3, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3
	pand xmm2, filtroBits2y3
	pand xmm3, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4         ; xor ultimos 4 con primeros 4
	pxor xmm1, xmm5         ; xor anteultimos 4 con segundos 4
	pxor xmm8, xmm2
	pxor xmm9, xmm3
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0   ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	movdqa xmm6, xmm8
	movdqa xmm7, xmm9
	pand xmm2, xmm10    ; filtrar con mascara
	pand xmm3, xmm10
	pand xmm6, xmm10
	pand xmm7, xmm10
	psrld xmm2, 15      ; shiftear de pos 17 a 2
	psrld xmm3, 15
	psrld xmm6, 15
	psrld xmm7, 15

	; Separar bit 3 con mascara 0x0000_0200
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der (para evitar saltar)
	movdqa xmm4, xmm0    ; copiar reg con bits desencriptados
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6        ; shiftear de pos 9 a 3
	psrld xmm5, 6
	por xmm2, xmm4       ; combinar con bit 2
	por xmm3, xmm5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6
	psrld xmm5, 6
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 4 con mascara 0x0000_0002
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	pslld xmm4, 3        ; shiftear de pos 1 a 4
	pslld xmm5, 3
	por xmm2, xmm4       ; combinar con bits 2 y 3
	por xmm3, xmm5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 3
	psrld xmm5, 3
	por xmm6, xmm4
	por xmm7, xmm5
	
	; Separar bit 5 con mascara 0x0001_0000
	pslld xmm10, 15      ; shiftear mascara
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11       ; shiftear de pos 16 a 5
	psrld xmm5, 11
	por xmm2, xmm4
	por xmm3, xmm5       ; combinar con bits 2:4

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11
	psrld xmm5, 11
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 6 con mascara 0x0000_0100
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2         ; shiftear de pos 8 a 6
	psrld xmm5, 2
	por xmm2, xmm4
	por xmm3, xmm5        ; combinar con bits 2:5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2
	psrld xmm5, 2
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1       ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pand xmm8, xmm10
	pand xmm9, xmm10
	pslld xmm0, 7         ; shiftear de pos 0 a 7
	pslld xmm1, 7
	pslld xmm8, 7
	pslld xmm9, 7
	por xmm0, xmm2
	por xmm1, xmm3        ; combinar con bits 2:6
	por xmm8, xmm6
	por xmm9, xmm7

	movdqa xmm2, shuffleLow
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	pshufb xmm8, xmm2
	pshufb xmm9, xmm2
	por xmm0, componenteA   ; rellenar componente A
	por xmm1, componenteA
	por xmm8, componenteA
	por xmm9, componenteA

	movdqa [rsi+rcx*8], xmm0     ; guardar en destino
	movdqa [rsi+(rcx+2)*8], xmm1
	movdqa [rsi+(rcx+4)*8], xmm8
	movdqa [rsi+(rcx+6)*8], xmm9

	add rcx, 8

	; Cargar 16 px de src    
    movdqa xmm0, [rdi+rcx*8]       ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+(rcx+2)*8]   ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|
    movdqa xmm8, [rdi+(rcx+4)*8]   ; xmm8 -> px 8-11
    movdqa xmm9, [rdi+(rcx+6)*8]   ; xmm9 -> px 12-15

	; Extraer últimos dos bits de componentes B, G y R con |0x00 0x03 0x03 0x03| x4
    pand xmm0, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4
    pand xmm8, filtroBits2y3
    pand xmm9, filtroBits2y3

; Desencriptar
    ; Cargar últimos 8 px
    movdqa xmm2, [rax]    ; xmm2 -> ultimos 4 px
    sub rax, 16
    movdqa xmm3, [rax]    ; xmm3 -> anteultimos 4 px
    sub rax, 16
    movdqa xmm6, [rax]
    sub rax, 16
    movdqa xmm7, [rax]
    sub rax, 16

    ; Invertir orden
    pshufd xmm4, xmm2, 0x1B    ; | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B    ; | p56 | p57 | p58 | p59 |
    pshufd xmm2, xmm6, 0x1B
    pshufd xmm3, xmm7, 0x1B

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en las pos menos significativas
    psrlw xmm5, 2
    psrlw xmm2, 2
    psrlw xmm3, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3
	pand xmm2, filtroBits2y3
	pand xmm3, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4         ; xor ultimos 4 con primeros 4
	pxor xmm1, xmm5         ; xor anteultimos 4 con segundos 4
	pxor xmm8, xmm2
	pxor xmm9, xmm3
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0   ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	movdqa xmm6, xmm8
	movdqa xmm7, xmm9
	pand xmm2, xmm10    ; filtrar con mascara
	pand xmm3, xmm10
	pand xmm6, xmm10
	pand xmm7, xmm10
	psrld xmm2, 15      ; shiftear de pos 17 a 2
	psrld xmm3, 15
	psrld xmm6, 15
	psrld xmm7, 15

	; Separar bit 3 con mascara 0x0000_0200
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der (para evitar saltar)
	movdqa xmm4, xmm0    ; copiar reg con bits desencriptados
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6        ; shiftear de pos 9 a 3
	psrld xmm5, 6
	por xmm2, xmm4       ; combinar con bit 2
	por xmm3, xmm5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6
	psrld xmm5, 6
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 4 con mascara 0x0000_0002
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	pslld xmm4, 3        ; shiftear de pos 1 a 4
	pslld xmm5, 3
	por xmm2, xmm4       ; combinar con bits 2 y 3
	por xmm3, xmm5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 3
	psrld xmm5, 3
	por xmm6, xmm4
	por xmm7, xmm5
	
	; Separar bit 5 con mascara 0x0001_0000
	pslld xmm10, 15      ; shiftear mascara
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11       ; shiftear de pos 16 a 5
	psrld xmm5, 11
	por xmm2, xmm4
	por xmm3, xmm5       ; combinar con bits 2:4

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11
	psrld xmm5, 11
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 6 con mascara 0x0000_0100
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2         ; shiftear de pos 8 a 6
	psrld xmm5, 2
	por xmm2, xmm4
	por xmm3, xmm5        ; combinar con bits 2:5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2
	psrld xmm5, 2
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1       ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pand xmm8, xmm10
	pand xmm9, xmm10
	pslld xmm0, 7         ; shiftear de pos 0 a 7
	pslld xmm1, 7
	pslld xmm8, 7
	pslld xmm9, 7
	por xmm0, xmm2
	por xmm1, xmm3        ; combinar con bits 2:6
	por xmm8, xmm6
	por xmm9, xmm7

	movdqa xmm2, shuffleLow
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	pshufb xmm8, xmm2
	pshufb xmm9, xmm2
	por xmm0, componenteA   ; rellenar componente A
	por xmm1, componenteA
	por xmm8, componenteA
	por xmm9, componenteA

	movdqa [rsi+rcx*8], xmm0     ; guardar en destino
	movdqa [rsi+(rcx+2)*8], xmm1
	movdqa [rsi+(rcx+4)*8], xmm8
	movdqa [rsi+(rcx+6)*8], xmm9

	add rcx, 8

	; Cargar 8 px de src    
    movdqa xmm0, [rdi+rcx*8]       ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+(rcx+2)*8]   ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|
    movdqa xmm8, [rdi+(rcx+4)*8]   ; xmm8 -> px 8-11
    movdqa xmm9, [rdi+(rcx+6)*8]   ; xmm9 -> px 12-15

	; Extraer últimos dos bits de componentes B, G y R con |0x00 0x03 0x03 0x03| x4
    pand xmm0, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4
    pand xmm8, filtroBits2y3
    pand xmm9, filtroBits2y3

; Desencriptar
    ; Cargar últimos 8 px
    movdqa xmm2, [rax]    ; xmm2 -> ultimos 4 px
    sub rax, 16
    movdqa xmm3, [rax]    ; xmm3 -> anteultimos 4 px
    sub rax, 16
    movdqa xmm6, [rax]
    sub rax, 16
    movdqa xmm7, [rax]
    sub rax, 16

    ; Invertir orden
    pshufd xmm4, xmm2, 0x1B    ; | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B    ; | p56 | p57 | p58 | p59 |
    pshufd xmm2, xmm6, 0x1B
    pshufd xmm3, xmm7, 0x1B

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en las pos menos significativas
    psrlw xmm5, 2
    psrlw xmm2, 2
    psrlw xmm3, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3
	pand xmm2, filtroBits2y3
	pand xmm3, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4         ; xor ultimos 4 con primeros 4
	pxor xmm1, xmm5         ; xor anteultimos 4 con segundos 4
	pxor xmm8, xmm2
	pxor xmm9, xmm3
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0   ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	movdqa xmm6, xmm8
	movdqa xmm7, xmm9
	pand xmm2, xmm10    ; filtrar con mascara
	pand xmm3, xmm10
	pand xmm6, xmm10
	pand xmm7, xmm10
	psrld xmm2, 15      ; shiftear de pos 17 a 2
	psrld xmm3, 15
	psrld xmm6, 15
	psrld xmm7, 15

	; Separar bit 3 con mascara 0x0000_0200
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der (para evitar saltar)
	movdqa xmm4, xmm0    ; copiar reg con bits desencriptados
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6        ; shiftear de pos 9 a 3
	psrld xmm5, 6
	por xmm2, xmm4       ; combinar con bit 2
	por xmm3, xmm5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 6
	psrld xmm5, 6
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 4 con mascara 0x0000_0002
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	pslld xmm4, 3        ; shiftear de pos 1 a 4
	pslld xmm5, 3
	por xmm2, xmm4       ; combinar con bits 2 y 3
	por xmm3, xmm5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 3
	psrld xmm5, 3
	por xmm6, xmm4
	por xmm7, xmm5
	
	; Separar bit 5 con mascara 0x0001_0000
	pslld xmm10, 15      ; shiftear mascara
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11       ; shiftear de pos 16 a 5
	psrld xmm5, 11
	por xmm2, xmm4
	por xmm3, xmm5       ; combinar con bits 2:4

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 11
	psrld xmm5, 11
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 6 con mascara 0x0000_0100
	psrldq xmm10, 1      ; shiftear mascara 1 byte a der
	movdqa xmm4, xmm0
	movdqa xmm5, xmm1
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2         ; shiftear de pos 8 a 6
	psrld xmm5, 2
	por xmm2, xmm4
	por xmm3, xmm5        ; combinar con bits 2:5

	movdqa xmm4, xmm8
	movdqa xmm5, xmm9
	pand xmm4, xmm10
	pand xmm5, xmm10
	psrld xmm4, 2
	psrld xmm5, 2
	por xmm6, xmm4
	por xmm7, xmm5

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1       ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pand xmm8, xmm10
	pand xmm9, xmm10
	pslld xmm0, 7         ; shiftear de pos 0 a 7
	pslld xmm1, 7
	pslld xmm8, 7
	pslld xmm9, 7
	por xmm0, xmm2
	por xmm1, xmm3        ; combinar con bits 2:6
	por xmm8, xmm6
	por xmm9, xmm7

	movdqa xmm2, shuffleLow
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	pshufb xmm8, xmm2
	pshufb xmm9, xmm2
	por xmm0, componenteA   ; rellenar componente A
	por xmm1, componenteA
	por xmm8, componenteA
	por xmm9, componenteA

	movdqa [rsi+rcx*8], xmm0     ; guardar en destino
	movdqa [rsi+(rcx+2)*8], xmm1
	movdqa [rsi+(rcx+4)*8], xmm8
	movdqa [rsi+(rcx+6)*8], xmm9

	add rcx, 8
	cmp rcx, r8
	jne .ciclo

.fin:
	pop rbp
	ret
