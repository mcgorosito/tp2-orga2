section .rodata
ALIGN 16
mascaraBits2y3: times 4 dd 0x0003_0303
mascaraBitsEncriptados: times 4 dd 0x0002_0000
mascaraShuffleLow: dq 0x80040404_80000000
mascaraShuffleHigh: dq 0x800C0C0C_80080808
mascaraComponenteA: times 4 dd 0xFF00_0000

section .text
global Descubrir_asm

;void Descubrir_asm (uint8_t *src, uint8_t *dst, int width, int height,
;    int src_row_size, int dst_row_size);

Descubrir_asm:
	push rbp
	mov rbp, rsp

	; rdi <- *src  -> imagen color que contiene imagen oculta
	; rsi <- *dst  -> imagen en escala de grises
	; edx <- width
	; ecx <- height

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
	cmp rcx, r8
	je .fin

	; Cargar 8 px de src    
    movdqa xmm0, [rdi+rcx*8]       ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+(rcx+2)*8]   ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|

	; Extraer últimos dos bits de componentes B, G y R con |0x00 0x03 0x03 0x03| x4
    pand xmm0, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4

; Desencriptar
    ; Cargar últimos 8 px
    movdqa xmm2, [rax]    ; xmm2 -> ultimos 4 px
    sub rax, 16
    movdqa xmm3, [rax]    ; xmm3 -> anteultimos 4 px
    sub rax, 16

    ; Invertir orden
    pshufd xmm4, xmm2, 0x1B    ; | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B    ; | p56 | p57 | p58 | p59 |

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en las pos menos significativas
    psrlw xmm5, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4            ; xor ultimos 4 con primeros 4
	pxor xmm1, xmm5            ; xor anteultimos 4 con segundos 4

; CHECKPOINT: bits desencriptados en xmm0 y xmm1
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4 
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4
; Objetivo: Armar pixel en escala de grises:  |b7 b6 b5 b4 b3 b2 0 0|
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0   ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	pand xmm2, xmm10    ; filtrar con mascara
	pand xmm3, xmm10
	psrld xmm2, 15      ; shiftear de pos 17 a 2
	psrld xmm3, 15

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

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1       ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pslld xmm0, 7         ; shiftear de pos 0 a 7
	pslld xmm1, 7
	por xmm0, xmm2
	por xmm1, xmm3        ; combinar con bits 2:6

; CHECKPOINT: bits desencriptados en xmm0 y xmm1
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 0 0|0 0 0 0 0 0 0 0|b7 b6 b5 b4 b3 b2 0 0| x4 
; Vista más amplia
;| 0 | 0 | 0 | GS3 | 0 | 0 | 0 | GS2 | 0 | 0 | 0 | GS1 | 0 | 0 | 0 | GS0 | x4 
;| 0 | 0 | 0 | GS7 | 0 | 0 | 0 | GS6 | 0 | 0 | 0 | GS5 | 0 | 0 | 0 | GS4 | x4
; Objetivo (copiar el bit de grises en todas las componentes y completar componente A):
;| FF | G3 | G3 | G3 | FF | G2 | G2 | G2 | FF | G1 | G1 | G1 | FF | G0 | G0 | G0 | x4 

	movdqa xmm2, shuffleLow
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	por xmm0, componenteA   ; rellenar componente A
	por xmm1, componenteA

	movdqa [rsi+rcx*8], xmm0     ; guardar en destino
	movdqa [rsi+(rcx+2)*8], xmm1

	add rcx, 4

	cmp rcx, r8
	je .fin

	; Cargar 8 px de src    
    movdqa xmm0, [rdi+rcx*8]       ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+(rcx+2)*8]   ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|

	; Extraer últimos dos bits de componentes B, G y R con |0x00 0x03 0x03 0x03| x4
    pand xmm0, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4

; Desencriptar
    ; Cargar últimos 8 px
    movdqa xmm2, [rax]    ; xmm2 -> ultimos 4 px
    sub rax, 16
    movdqa xmm3, [rax]    ; xmm3 -> anteultimos 4 px
    sub rax, 16

    ; Invertir orden
    pshufd xmm4, xmm2, 0x1B    ; | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B    ; | p56 | p57 | p58 | p59 |

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en las pos menos significativas
    psrlw xmm5, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4            ; xor ultimos 4 con primeros 4
	pxor xmm1, xmm5            ; xor anteultimos 4 con segundos 4

; CHECKPOINT: bits desencriptados en xmm0 y xmm1
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4 
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4
; Objetivo: Armar pixel en escala de grises:  |b7 b6 b5 b4 b3 b2 0 0|
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0   ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	pand xmm2, xmm10    ; filtrar con mascara
	pand xmm3, xmm10
	psrld xmm2, 15      ; shiftear de pos 17 a 2
	psrld xmm3, 15

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

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1       ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pslld xmm0, 7         ; shiftear de pos 0 a 7
	pslld xmm1, 7
	por xmm0, xmm2
	por xmm1, xmm3        ; combinar con bits 2:6

; CHECKPOINT: bits desencriptados en xmm0 y xmm1
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 0 0|0 0 0 0 0 0 0 0|b7 b6 b5 b4 b3 b2 0 0| x4 
; Vista más amplia
;| 0 | 0 | 0 | GS3 | 0 | 0 | 0 | GS2 | 0 | 0 | 0 | GS1 | 0 | 0 | 0 | GS0 | x4 
;| 0 | 0 | 0 | GS7 | 0 | 0 | 0 | GS6 | 0 | 0 | 0 | GS5 | 0 | 0 | 0 | GS4 | x4
; Objetivo (copiar el bit de grises en todas las componentes y completar componente A):
;| FF | G3 | G3 | G3 | FF | G2 | G2 | G2 | FF | G1 | G1 | G1 | FF | G0 | G0 | G0 | x4 

	movdqa xmm2, shuffleLow
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	por xmm0, componenteA   ; rellenar componente A
	por xmm1, componenteA

	movdqa [rsi+rcx*8], xmm0     ; guardar en destino
	movdqa [rsi+(rcx+2)*8], xmm1

	add rcx, 4

	cmp rcx, r8
	je .fin

	; Cargar 8 px de src    
    movdqa xmm0, [rdi+rcx*8]       ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+(rcx+2)*8]   ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|

	; Extraer últimos dos bits de componentes B, G y R con |0x00 0x03 0x03 0x03| x4
    pand xmm0, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4

; Desencriptar
    ; Cargar últimos 8 px
    movdqa xmm2, [rax]    ; xmm2 -> ultimos 4 px
    sub rax, 16
    movdqa xmm3, [rax]    ; xmm3 -> anteultimos 4 px
    sub rax, 16

    ; Invertir orden
    pshufd xmm4, xmm2, 0x1B    ; | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B    ; | p56 | p57 | p58 | p59 |

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en las pos menos significativas
    psrlw xmm5, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4            ; xor ultimos 4 con primeros 4
	pxor xmm1, xmm5            ; xor anteultimos 4 con segundos 4

; CHECKPOINT: bits desencriptados en xmm0 y xmm1
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4 
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4
; Objetivo: Armar pixel en escala de grises:  |b7 b6 b5 b4 b3 b2 0 0|
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0   ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	pand xmm2, xmm10    ; filtrar con mascara
	pand xmm3, xmm10
	psrld xmm2, 15      ; shiftear de pos 17 a 2
	psrld xmm3, 15

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

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1       ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pslld xmm0, 7         ; shiftear de pos 0 a 7
	pslld xmm1, 7
	por xmm0, xmm2
	por xmm1, xmm3        ; combinar con bits 2:6

; CHECKPOINT: bits desencriptados en xmm0 y xmm1
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 0 0|0 0 0 0 0 0 0 0|b7 b6 b5 b4 b3 b2 0 0| x4 
; Vista más amplia
;| 0 | 0 | 0 | GS3 | 0 | 0 | 0 | GS2 | 0 | 0 | 0 | GS1 | 0 | 0 | 0 | GS0 | x4 
;| 0 | 0 | 0 | GS7 | 0 | 0 | 0 | GS6 | 0 | 0 | 0 | GS5 | 0 | 0 | 0 | GS4 | x4
; Objetivo (copiar el bit de grises en todas las componentes y completar componente A):
;| FF | G3 | G3 | G3 | FF | G2 | G2 | G2 | FF | G1 | G1 | G1 | FF | G0 | G0 | G0 | x4 

	movdqa xmm2, shuffleLow
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	por xmm0, componenteA   ; rellenar componente A
	por xmm1, componenteA

	movdqa [rsi+rcx*8], xmm0     ; guardar en destino
	movdqa [rsi+(rcx+2)*8], xmm1

	add rcx, 4

	cmp rcx, r8
	je .fin

	; Cargar 8 px de src    
    movdqa xmm0, [rdi+rcx*8]       ; xmm0 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
    movdqa xmm1, [rdi+(rcx+2)*8]   ; xmm1 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|

	; Extraer últimos dos bits de componentes B, G y R con |0x00 0x03 0x03 0x03| x4
    pand xmm0, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4 
    pand xmm1, filtroBits2y3         ; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b5 b2|0 0 0 0 0 0 b6 b3|0 0 0 0 0 0 b7 b4| x4

; Desencriptar
    ; Cargar últimos 8 px
    movdqa xmm2, [rax]    ; xmm2 -> ultimos 4 px
    sub rax, 16
    movdqa xmm3, [rax]    ; xmm3 -> anteultimos 4 px
    sub rax, 16

    ; Invertir orden
    pshufd xmm4, xmm2, 0x1B    ; | p60 | p61 | p62 | p63 |
    pshufd xmm5, xmm3, 0x1B    ; | p56 | p57 | p58 | p59 |

    ; Recuperar bits 2 y 3
    psrlw xmm4, 2              ; poner b2 y b3 en las pos menos significativas
    psrlw xmm5, 2
	pand xmm4, filtroBits2y3
	pand xmm5, filtroBits2y3

	; Hacer el xor
	pxor xmm0, xmm4            ; xor ultimos 4 con primeros 4
	pxor xmm1, xmm5            ; xor anteultimos 4 con segundos 4

; CHECKPOINT: bits desencriptados en xmm0 y xmm1
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4 
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x4
; Objetivo: Armar pixel en escala de grises:  |b7 b6 b5 b4 b3 b2 0 0|
	
	; Separar bit 2 con mascara 0x0002_0000
	movdqa xmm10, filtroBitsEncriptados
	movdqa xmm2, xmm0   ; copiar reg con bits desencriptados
	movdqa xmm3, xmm1
	pand xmm2, xmm10    ; filtrar con mascara
	pand xmm3, xmm10
	psrld xmm2, 15      ; shiftear de pos 17 a 2
	psrld xmm3, 15

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

	; Separar bit 7 con mascara 0x0000_0001
	psrldq xmm10, 1       ; shiftear mascara 1 byte a der
	pand xmm0, xmm10
	pand xmm1, xmm10
	pslld xmm0, 7         ; shiftear de pos 0 a 7
	pslld xmm1, 7
	por xmm0, xmm2
	por xmm1, xmm3        ; combinar con bits 2:6

; CHECKPOINT: bits desencriptados en xmm0 y xmm1
; |0 0 0 0 0 0 0 0|0 0 0 0 0 0 0 0|0 0 0 0 0 0 0 0|b7 b6 b5 b4 b3 b2 0 0| x4 
; Vista más amplia
;| 0 | 0 | 0 | GS3 | 0 | 0 | 0 | GS2 | 0 | 0 | 0 | GS1 | 0 | 0 | 0 | GS0 | x4 
;| 0 | 0 | 0 | GS7 | 0 | 0 | 0 | GS6 | 0 | 0 | 0 | GS5 | 0 | 0 | 0 | GS4 | x4
; Objetivo (copiar el bit de grises en todas las componentes y completar componente A):
;| FF | G3 | G3 | G3 | FF | G2 | G2 | G2 | FF | G1 | G1 | G1 | FF | G0 | G0 | G0 | x4 

	movdqa xmm2, shuffleLow
	movdqa xmm3, shuffleHigh
	punpcklqdq xmm2, xmm3
	pshufb xmm0, xmm2
	pshufb xmm1, xmm2
	por xmm0, componenteA   ; rellenar componente A
	por xmm1, componenteA

	movdqa [rsi+rcx*8], xmm0     ; guardar en destino
	movdqa [rsi+(rcx+2)*8], xmm1

	add rcx, 4
	
	jmp .ciclo

.fin:
	pop rbp
	ret
