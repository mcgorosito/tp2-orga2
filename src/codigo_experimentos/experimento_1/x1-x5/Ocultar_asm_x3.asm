section .rodata
ALIGN 16
mascaraComponentes: times 4 dd 0x0000_00FF
mascaraSepararBits: times 8 dw 0x8080
mascaraDejarUlt2Bits: times 16 db 0x03
mascaraBorrarUlt2BitsRGB: times 4 dd 0xFFFC_FCFC

section .text
global Ocultar_asm

Ocultar_asm:
;void Ocultar_asm (uint8_t *src, uint8_t *src2, uint8_t *dst, int width, int height, 
; int src_row_size, int dst_row_size);

; rdi <- uint8_t *src (imagen visible)
; rsi <- uint8_t *src2 (imagen a ocultar)
; rdx <- uint8_t *dst
; ecx <- width
; r8d <- height
; r9d <- src_row_size
; [rbp+16] <- dst_row_size

	push rbp
	mov rbp, rsp
	push rbx
	push r12

	; Cargar máscaras en registros xmm12-xmm15
	movdqa xmm15, [mascaraComponentes]
	movdqa xmm14, [mascaraSepararBits]
	movdqa xmm13, [mascaraDejarUlt2Bits]
	movdqa xmm12, [mascaraBorrarUlt2BitsRGB]

	%define separarComponentes xmm15
	%define separarBits xmm14
	%define dejarUlt2Bits xmm13
	%define borrarUlt2Bits xmm12

	movd xmm0, ecx
	movd xmm1, r8d
	pmuldq xmm0, xmm1  ; obtener tamaño en px  height*width
	movq r12, xmm0

	; Imagen espejo: obtener puntero al final
	mov rax, r12      ; rax -> size
	shl rax, 2        ; size*4 (cantidad de bytes)
	add rax, rdi      ; posicion inmediatamente posterior al fin de la imagen
	sub rax, 16       ; dir de memoria de últimos 4 px

	; Trabajar 16 píxeles a la vez
	shr r12, 1        ; r12 -> cant ciclos: size/2 porque se cargan 4 bytes por registro (pero se incrementa de a dos)
	xor rbx, rbx      ; contador para recorrer la imagen cada 4 px y se incrementa de a 8 en cada ciclo

.ciclo:
	cmp rbx, r12
	je .fin

	; CONVERTIR LA IMAGEN A ESCALA DE GRISES
	; pixelGris = (src2[i][j].b + 2 * src2[i][j].g + src2[i][j].r) / 4
	; Extender a word (16 bits) y luego empaquetar saturado a byte

	; 1) Levantar 16 px de src2
	movdqa xmm0, [rsi+rbx*8]      ; xmm0 -> | A3 R3 G3 B3 | A2 R2 G2 B2 | A1 R1 G1 B1 | A0 R0 G0 B0 |
	movdqa xmm1, [rsi+(rbx+2)*8]  ; xmm1 -> | A7 R7 G7 B7 | A6 R6 G6 B6 | A5 R5 G5 B5 | A4 R4 G4 B4 |
	movdqa xmm2, [rsi+(rbx+4)*8]  ; xmm2 -> | AB RB GB BB | AA RA GA BA | A9 R9 G9 B9 | A8 R8 G8 B8 |
	movdqa xmm3, [rsi+(rbx+6)*8]  ; xmm3 -> | AF RF GF BF | AE RE GE BE | AD RD GD BD | AC RC GC BC |

	; 1) Filtrar B
	movdqa xmm11, separarComponentes ; Máscara: 0x0000_00FF x4
	movdqa xmm4, xmm0   ; copiar primeros 4 px
	movdqa xmm6, xmm1   ; copiar segundos 4 px
	movdqa xmm5, xmm2   ; copiar terceros 4 px
	movdqa xmm7, xmm3  ; copiar cuartos 4 px
	pand xmm4, xmm11    ; xmm4 -> |0000 00B3|0000 00B2|0000 00B1|0000 00B0|
	pand xmm6, xmm11    ; xmm5 -> |0000 00B7|0000 00B6|0000 00B5|0000 00B4|
	pand xmm5, xmm11   ;
	pand xmm7, xmm11
	; 1.1) Juntar las 8 words de B en dos registro
	packusdw xmm4, xmm6 ; xmm4 -> |00B7|00B6|00B5|00B4|00B3|00B2|00B1|00B0|
	packusdw xmm5, xmm7 ; xmm5 ->

	; 2) Filtrar G	
	pslldq xmm11, 1     ; shiftear máscara para filtrar G: 0x0000_FF00 x4
	movdqa xmm6, xmm0   ; copiar primeros 4 px
	movdqa xmm8, xmm1   ; copiar segundos 4 px
	movdqa xmm7, xmm2   ; 
	movdqa xmm9, xmm3
	pand xmm6, xmm11    ; xmm6 -> |0000 G300|0000 G200|0000 G100|0000 G000|
	pand xmm8, xmm11    ; xmm8 -> |0000 G700|0000 G600|0000 G500|0000 G400|
	pand xmm7, xmm11
	pand xmm9, xmm11
	; 2.1) Shiftear G a der a pos menos significativa (1 byte)
	psrldq xmm6, 1      ; xmm6 -> |0000 00G3|0000 00G2|0000 00G1|0000 00G0|
	psrldq xmm8, 1       ; xmm8 -> |0000 00G7|0000 00G6|0000 00G5|0000 00G4|
	psrldq xmm7, 1
	psrldq xmm9, 1
	; 2.2) Multiplicar x 2: shiftear a izq 1 bits (ahora ocupa word)
	psllw xmm6, 1       ; xmm5 -> |0000|G3*2|0000|G2*2|0000|G1*2|0000|G0*2|
	psllw xmm8, 1       ; xmmB -> |0000|G7*2|0000|G6*2|0000|G5*2|0000|G4*2|
	psllw xmm7, 1
	psllw xmm9, 1
	; 2.3) Juntar las 8 words de G en un registro
	packusdw xmm6, xmm8  ; xmm6 -> |G7*2|G6*2|G5*2|G4*2|G3*2|G2*2|G1*2|G0*2|
	packusdw xmm7, xmm9  ; xmm7

	; 3) Filtrar R
	pslldq xmm11, 1     ; shiftear máscara para filtrar R: 0x00FF_0000 x4
	pand xmm0, xmm11    ; xmm0 -> |00R3 0000|00R2 0000|00R1 0000|00R0 0000|
	pand xmm1, xmm11    ; xmm1 -> |00R7 0000|00R6 0000|00R5 0000|00R4 0000|
	pand xmm2, xmm11
	pand xmm3, xmm11
	; 3.1) Shiftear B a der a pos menos significativa (2 bytes)
	psrldq xmm0, 2      ; xmm0 -> |0000 00R3|0000 00R2|0000 00R1|0000 00R0|
	psrldq xmm1, 2      ; xmm1 -> |0000 00R7|0000 00R6|0000 00R5|0000 00R4|
	psrldq xmm2, 2
	psrldq xmm3, 2
	; 3.2) Juntar las 8 words de R en un registro
	packusdw xmm0, xmm1 ; xmm0 -> |00R7|00R6|00R5|00R4|00R3|00R2|00R1|00R0|
	packusdw xmm2, xmm3 ; xmm2

	; 4) Hacer sumas verticales saturadas
	;G:   | 2*G7 | 2*G6 | 2*G5 | 2*G4 | 2*G3 | 2*G2 | 2*G1 | 2*G0 |
	;B:   |   B7 |   B6 |   B5 |   B4 |   B3 |   B2 |   B1 |   B0 |
	;R:   |   R7 |   R6 |   R5 |   R4 |   R3 |   R2 |   R1 |   R0 |
	;Res: |2G7+B7+R7| ... |2G0+B0+R0|
	paddusw xmm4, xmm6   ; sumar B + 2G
	paddusw xmm0, xmm4   ; sumar (B + 2G) + R
	paddusw xmm5, xmm7
	paddusw xmm2, xmm5
	; 5) Dividir por 4: shiftear words a derecha 2 bits
	psrlw xmm0, 2
	psrlw xmm2, 2
	;pxor xmm0, xmm0
	; 6) Empaquetar saturado
	packuswb xmm0, xmm2  ; xmm0 -> |GSF GSE GSD GSC|GSB GSA GS9 GS8|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|

; CHECKPOINT: Pixeles escala de grises 0:15 en xmm1

; ARMAR IMAGEN DE SALIDA
; 1) Obtener los bits para guardar en cada color de la escala

; |GSF GSE GSD GSC|GSB GSA GS9 GS8|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|
	
	movdqa xmm10, separarBits

	; --BLUE-- en xmm1
	movdqa xmm1, xmm0   ; hacer una copia y filtrarlo con AND -> |b7 0 0 0 0 0 0 0| x 16
	pand xmm1, xmm10
	psrlw xmm1, 7       ; shiftear a la derecha 7 bits -> |0 0 0 0 0 0 0 b7| x 16
	psrlw xmm10, 3      ; máscara para obtener b4: shift right 3 bits (0x10 x 16)
	movdqa xmm2, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 0 b4 0 0 0 0| x 16
	pand xmm2, xmm10
	psrlw xmm2, 3       ; shiftear a la derecha 3 bits -> |0 0 0 0 0 0 b4 0| x 16
	por xmm1, xmm2      ; combinar con el b7: xmm1 -> |0 0 0 0 0 0 b4 b7| x 16
	
	; --GREEN-- en xmm2
	psllw xmm10, 2      ; máscara para obtener b6: shift left 2 bits (0x40 x 16)
	movdqa xmm2, xmm0   ; hacer una copia y filtrarlo con AND -> |0 b6 0 0 0 0 0 0| x 16
	pand xmm2, xmm10
	psrlw xmm2, 6   	; shiftear a la derecha 6 bits -> |0 0 0 0 0 0 0 b6| x 16
    psrlw xmm10, 3      ; máscara para obtener b3: shift right 3 bits (0x08)
    movdqa xmm3, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 0 0 b3 0 0 0| x 16
    pand xmm3, xmm10
    psrlw xmm3, 2       ; shiftear a la derecha 2 bits -> |0 0 0 0 0 0 b3 0| x 16
    por xmm2, xmm3      ; combinar con el b6: xmm2 -> |0 0 0 0 0 0 b3 b6| x 16
	
	; --RED-- en xmm3
	psllw xmm10, 2      ; máscara para obtener b5: shift left 2 bits (0x20 x 16)
	movdqa xmm3, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 b5 0 0 0 0 0| x 16
	pand xmm3, xmm10
	psrlw xmm3, 5       ; shiftear a la derecha 5 bits -> |0 0 0 0 0 0 0 b5| x 16
	psrlw xmm10, 3      ; máscara para obtener b2: shift right 3 bits (0x04)
	pand xmm0, xmm10    ; filtrarlo con AND -> |0 0 0 0 0 b2 0 0| x 16
	psrlw xmm0, 1       ; shiftear a la derecha 1 bit -> |0 0 0 0 0 0 b2 0| x 16
	por xmm3, xmm0      ; combinar con el b5: xmm3 -> |0 0 0 0 0 0 b2 b5| x 16

	; TENEMOS:
	; xmm3 -> |0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b2 b5| x 8 (pos menos sig)
	; xmm2 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b3 b6| x 8 (pos menos sig)
	; xmm1 -> |0 0 0 0 0 0 b4 b7|0 0 0 0 0 0 b4 b7| x 8 (pos menos sig)

	; OBJETIVO
	; reg1 (pixel 0-3) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
	; reg2 (pixel 4-7) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
	; reg3 (pixel 8-11) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
    ; reg4 (pixel 12-15) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
    movdqa xmm0, xmm1
    punpcklbw xmm0, xmm2  ; xmm0 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:7
    punpckhbw xmm1, xmm2  ; xmm1 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 8:15
    pxor xmm4, xmm4
    movdqa xmm2, xmm3
    punpcklbw xmm2, xmm4  ; xmm2 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5| de px 0:7
    punpckhbw xmm3, xmm4  ; xmm3 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5| de px 8:15

    ;Combinar xmm0 y xmm2
    movdqa xmm4, xmm0
    punpcklwd xmm0, xmm2  ; xmm0 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:3
	punpckhwd xmm4, xmm2  ; xmm4 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 4:7
	;Combinar xmm1 y xmm3
	movdqa xmm5, xmm1
	punpcklwd xmm1, xmm3  ; xmm1 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 8:11
	punpckhwd xmm5, xmm3  ; xmm5 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 12:15
	
; CHECKPOINT: bits a guardar en xmm0 (0:3), xmm4 (4:7), xmm1 (8:11), xmm5 (9:15)

; 2) Encriptar con xor
    ; Cargar los últimos 16 pixeles de la imagen
    movdqa xmm2, [rax]               ; | p63  | p62  | p61  | p60  |
    movdqa xmm3, [rax-16]            ; | p59  | p58  | p57  | p56  |
    movdqa xmm6, [rax-32]           ; | p55  | p54  | p53  | p52  |
    movdqa xmm7, [rax-48]           ; | p51  | p50  | p49  | p48  |
    sub rax, 64
    pshufd xmm8, xmm2, 0x1B          ; | p60 | p61 | p62 | p63 |
    pshufd xmm9, xmm3, 0x1B          ; | p56 | p57 | p58 | p59 |
    pshufd xmm10, xmm6, 0x1B        ; | p52 | p53 | p54 | p55 |
    pshufd xmm11, xmm7, 0x1B        ; | p48 | p49 | p50 | p51 |
    psrlw xmm8, 2             ; poner b2 y b3 en las pos menos significativas
    psrlw xmm9, 2
	psrlw xmm10, 2
	psrlw xmm11, 2
	pand xmm8, dejarUlt2Bits
	pand xmm9, dejarUlt2Bits
	pand xmm10, dejarUlt2Bits
	pand xmm11, dejarUlt2Bits
	pxor xmm0, xmm8                  ; xor ultimos 4 con primeros 4
	pxor xmm4, xmm9                  ; xor anteultimos 4 con segundos 4
	pxor xmm1, xmm10
	pxor xmm5, xmm11

; CHECKPOINT: bits encriptados en xmm0 (0:3), xmm4 (4:7), xmm1 (8:11), xmm5 (12:15)

	; 3) Cargar de src los 16 pixeles que se van a guardar en dst
	movdqa xmm2, [rdi+rbx*8]  ; levantar 8 px de src
	movdqa xmm3, [rdi+(rbx+2)*8]
	movdqa xmm6, [rdi+(rbx+4)*8]
	movdqa xmm7, [rdi+(rbx+6)*8]

	; 4) Borrarle los últimos dos bits a cada color con máscara |0xFF|0xFC|0xFC|0xFC| x 4
 	; (Componente A tiene que estar todo en uno)
 	
	pand xmm2, borrarUlt2Bits     ; Hacer AND con los px levantado de src
	pand xmm3, borrarUlt2Bits
	pand xmm6, borrarUlt2Bits
	pand xmm7, borrarUlt2Bits

	; 5) Combinar los 4 pixeles de destino con los bits de la imagen oculta y guardar en dst
	por xmm0, xmm2       ; combinar px de src con px encriptados
	por xmm4, xmm3
	por xmm1, xmm6
	por xmm5, xmm7

	movdqa [rdx+rbx*8], xmm0     ; guardar en destino
	movdqa [rdx+(rbx+2)*8], xmm4
	movdqa [rdx+(rbx+4)*8], xmm1
	movdqa [rdx+(rbx+6)*8], xmm5

	add rbx, 8

	cmp rbx, r12
	je .fin

	; CONVERTIR LA IMAGEN A ESCALA DE GRISES
	; pixelGris = (src2[i][j].b + 2 * src2[i][j].g + src2[i][j].r) / 4
	; Extender a word (16 bits) y luego empaquetar saturado a byte

	; 1) Levantar 16 px de src2
	movdqa xmm0, [rsi+rbx*8]      ; xmm0 -> | A3 R3 G3 B3 | A2 R2 G2 B2 | A1 R1 G1 B1 | A0 R0 G0 B0 |
	movdqa xmm1, [rsi+(rbx+2)*8]  ; xmm1 -> | A7 R7 G7 B7 | A6 R6 G6 B6 | A5 R5 G5 B5 | A4 R4 G4 B4 |
	movdqa xmm2, [rsi+(rbx+4)*8]  ; xmm2 -> | AB RB GB BB | AA RA GA BA | A9 R9 G9 B9 | A8 R8 G8 B8 |
	movdqa xmm3, [rsi+(rbx+6)*8]  ; xmm3 -> | AF RF GF BF | AE RE GE BE | AD RD GD BD | AC RC GC BC |

	; 1) Filtrar B
	movdqa xmm11, separarComponentes ; Máscara: 0x0000_00FF x4
	movdqa xmm4, xmm0   ; copiar primeros 4 px
	movdqa xmm6, xmm1   ; copiar segundos 4 px
	movdqa xmm5, xmm2   ; copiar terceros 4 px
	movdqa xmm7, xmm3  ; copiar cuartos 4 px
	pand xmm4, xmm11    ; xmm4 -> |0000 00B3|0000 00B2|0000 00B1|0000 00B0|
	pand xmm6, xmm11    ; xmm5 -> |0000 00B7|0000 00B6|0000 00B5|0000 00B4|
	pand xmm5, xmm11   ;
	pand xmm7, xmm11
	; 1.1) Juntar las 8 words de B en dos registro
	packusdw xmm4, xmm6 ; xmm4 -> |00B7|00B6|00B5|00B4|00B3|00B2|00B1|00B0|
	packusdw xmm5, xmm7 ; xmm5 ->

	; 2) Filtrar G	
	pslldq xmm11, 1     ; shiftear máscara para filtrar G: 0x0000_FF00 x4
	movdqa xmm6, xmm0   ; copiar primeros 4 px
	movdqa xmm8, xmm1   ; copiar segundos 4 px
	movdqa xmm7, xmm2   ; 
	movdqa xmm9, xmm3
	pand xmm6, xmm11    ; xmm6 -> |0000 G300|0000 G200|0000 G100|0000 G000|
	pand xmm8, xmm11    ; xmm8 -> |0000 G700|0000 G600|0000 G500|0000 G400|
	pand xmm7, xmm11
	pand xmm9, xmm11
	; 2.1) Shiftear G a der a pos menos significativa (1 byte)
	psrldq xmm6, 1      ; xmm6 -> |0000 00G3|0000 00G2|0000 00G1|0000 00G0|
	psrldq xmm8, 1       ; xmm8 -> |0000 00G7|0000 00G6|0000 00G5|0000 00G4|
	psrldq xmm7, 1
	psrldq xmm9, 1
	; 2.2) Multiplicar x 2: shiftear a izq 1 bits (ahora ocupa word)
	psllw xmm6, 1       ; xmm5 -> |0000|G3*2|0000|G2*2|0000|G1*2|0000|G0*2|
	psllw xmm8, 1       ; xmmB -> |0000|G7*2|0000|G6*2|0000|G5*2|0000|G4*2|
	psllw xmm7, 1
	psllw xmm9, 1
	; 2.3) Juntar las 8 words de G en un registro
	packusdw xmm6, xmm8  ; xmm6 -> |G7*2|G6*2|G5*2|G4*2|G3*2|G2*2|G1*2|G0*2|
	packusdw xmm7, xmm9  ; xmm7

	; 3) Filtrar R
	pslldq xmm11, 1     ; shiftear máscara para filtrar R: 0x00FF_0000 x4
	pand xmm0, xmm11    ; xmm0 -> |00R3 0000|00R2 0000|00R1 0000|00R0 0000|
	pand xmm1, xmm11    ; xmm1 -> |00R7 0000|00R6 0000|00R5 0000|00R4 0000|
	pand xmm2, xmm11
	pand xmm3, xmm11
	; 3.1) Shiftear B a der a pos menos significativa (2 bytes)
	psrldq xmm0, 2      ; xmm0 -> |0000 00R3|0000 00R2|0000 00R1|0000 00R0|
	psrldq xmm1, 2      ; xmm1 -> |0000 00R7|0000 00R6|0000 00R5|0000 00R4|
	psrldq xmm2, 2
	psrldq xmm3, 2
	; 3.2) Juntar las 8 words de R en un registro
	packusdw xmm0, xmm1 ; xmm0 -> |00R7|00R6|00R5|00R4|00R3|00R2|00R1|00R0|
	packusdw xmm2, xmm3 ; xmm2

	; 4) Hacer sumas verticales saturadas
	;G:   | 2*G7 | 2*G6 | 2*G5 | 2*G4 | 2*G3 | 2*G2 | 2*G1 | 2*G0 |
	;B:   |   B7 |   B6 |   B5 |   B4 |   B3 |   B2 |   B1 |   B0 |
	;R:   |   R7 |   R6 |   R5 |   R4 |   R3 |   R2 |   R1 |   R0 |
	;Res: |2G7+B7+R7| ... |2G0+B0+R0|
	paddusw xmm4, xmm6   ; sumar B + 2G
	paddusw xmm0, xmm4   ; sumar (B + 2G) + R
	paddusw xmm5, xmm7
	paddusw xmm2, xmm5
	; 5) Dividir por 4: shiftear words a derecha 2 bits
	psrlw xmm0, 2
	psrlw xmm2, 2
	;pxor xmm0, xmm0
	; 6) Empaquetar saturado
	packuswb xmm0, xmm2  ; xmm0 -> |GSF GSE GSD GSC|GSB GSA GS9 GS8|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|

; CHECKPOINT: Pixeles escala de grises 0:15 en xmm1

; ARMAR IMAGEN DE SALIDA
; 1) Obtener los bits para guardar en cada color de la escala

; |GSF GSE GSD GSC|GSB GSA GS9 GS8|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|
	
	movdqa xmm10, separarBits

	; --BLUE-- en xmm1
	movdqa xmm1, xmm0   ; hacer una copia y filtrarlo con AND -> |b7 0 0 0 0 0 0 0| x 16
	pand xmm1, xmm10
	psrlw xmm1, 7       ; shiftear a la derecha 7 bits -> |0 0 0 0 0 0 0 b7| x 16
	psrlw xmm10, 3      ; máscara para obtener b4: shift right 3 bits (0x10 x 16)
	movdqa xmm2, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 0 b4 0 0 0 0| x 16
	pand xmm2, xmm10
	psrlw xmm2, 3       ; shiftear a la derecha 3 bits -> |0 0 0 0 0 0 b4 0| x 16
	por xmm1, xmm2      ; combinar con el b7: xmm1 -> |0 0 0 0 0 0 b4 b7| x 16
	
	; --GREEN-- en xmm2
	psllw xmm10, 2      ; máscara para obtener b6: shift left 2 bits (0x40 x 16)
	movdqa xmm2, xmm0   ; hacer una copia y filtrarlo con AND -> |0 b6 0 0 0 0 0 0| x 16
	pand xmm2, xmm10
	psrlw xmm2, 6   	; shiftear a la derecha 6 bits -> |0 0 0 0 0 0 0 b6| x 16
    psrlw xmm10, 3      ; máscara para obtener b3: shift right 3 bits (0x08)
    movdqa xmm3, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 0 0 b3 0 0 0| x 16
    pand xmm3, xmm10
    psrlw xmm3, 2       ; shiftear a la derecha 2 bits -> |0 0 0 0 0 0 b3 0| x 16
    por xmm2, xmm3      ; combinar con el b6: xmm2 -> |0 0 0 0 0 0 b3 b6| x 16
	
	; --RED-- en xmm3
	psllw xmm10, 2      ; máscara para obtener b5: shift left 2 bits (0x20 x 16)
	movdqa xmm3, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 b5 0 0 0 0 0| x 16
	pand xmm3, xmm10
	psrlw xmm3, 5       ; shiftear a la derecha 5 bits -> |0 0 0 0 0 0 0 b5| x 16
	psrlw xmm10, 3      ; máscara para obtener b2: shift right 3 bits (0x04)
	pand xmm0, xmm10    ; filtrarlo con AND -> |0 0 0 0 0 b2 0 0| x 16
	psrlw xmm0, 1       ; shiftear a la derecha 1 bit -> |0 0 0 0 0 0 b2 0| x 16
	por xmm3, xmm0      ; combinar con el b5: xmm3 -> |0 0 0 0 0 0 b2 b5| x 16

	; TENEMOS:
	; xmm3 -> |0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b2 b5| x 8 (pos menos sig)
	; xmm2 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b3 b6| x 8 (pos menos sig)
	; xmm1 -> |0 0 0 0 0 0 b4 b7|0 0 0 0 0 0 b4 b7| x 8 (pos menos sig)

	; OBJETIVO
	; reg1 (pixel 0-3) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
	; reg2 (pixel 4-7) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
	; reg3 (pixel 8-11) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
    ; reg4 (pixel 12-15) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
    movdqa xmm0, xmm1
    punpcklbw xmm0, xmm2  ; xmm0 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:7
    punpckhbw xmm1, xmm2  ; xmm1 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 8:15
    pxor xmm4, xmm4
    movdqa xmm2, xmm3
    punpcklbw xmm2, xmm4  ; xmm2 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5| de px 0:7
    punpckhbw xmm3, xmm4  ; xmm3 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5| de px 8:15

    ;Combinar xmm0 y xmm2
    movdqa xmm4, xmm0
    punpcklwd xmm0, xmm2  ; xmm0 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:3
	punpckhwd xmm4, xmm2  ; xmm4 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 4:7
	;Combinar xmm1 y xmm3
	movdqa xmm5, xmm1
	punpcklwd xmm1, xmm3  ; xmm1 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 8:11
	punpckhwd xmm5, xmm3  ; xmm5 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 12:15
	
; CHECKPOINT: bits a guardar en xmm0 (0:3), xmm4 (4:7), xmm1 (8:11), xmm5 (9:15)

; 2) Encriptar con xor
    ; Cargar los últimos 16 pixeles de la imagen
    movdqa xmm2, [rax]               ; | p63  | p62  | p61  | p60  |
    movdqa xmm3, [rax-16]            ; | p59  | p58  | p57  | p56  |
    movdqa xmm6, [rax-32]           ; | p55  | p54  | p53  | p52  |
    movdqa xmm7, [rax-48]           ; | p51  | p50  | p49  | p48  |
    sub rax, 64
    pshufd xmm8, xmm2, 0x1B          ; | p60 | p61 | p62 | p63 |
    pshufd xmm9, xmm3, 0x1B          ; | p56 | p57 | p58 | p59 |
    pshufd xmm10, xmm6, 0x1B        ; | p52 | p53 | p54 | p55 |
    pshufd xmm11, xmm7, 0x1B        ; | p48 | p49 | p50 | p51 |
    psrlw xmm8, 2             ; poner b2 y b3 en las pos menos significativas
    psrlw xmm9, 2
	psrlw xmm10, 2
	psrlw xmm11, 2
	pand xmm8, dejarUlt2Bits
	pand xmm9, dejarUlt2Bits
	pand xmm10, dejarUlt2Bits
	pand xmm11, dejarUlt2Bits
	pxor xmm0, xmm8                  ; xor ultimos 4 con primeros 4
	pxor xmm4, xmm9                  ; xor anteultimos 4 con segundos 4
	pxor xmm1, xmm10
	pxor xmm5, xmm11

; CHECKPOINT: bits encriptados en xmm0 (0:3), xmm4 (4:7), xmm1 (8:11), xmm5 (12:15)

	; 3) Cargar de src los 16 pixeles que se van a guardar en dst
	movdqa xmm2, [rdi+rbx*8]  ; levantar 8 px de src
	movdqa xmm3, [rdi+(rbx+2)*8]
	movdqa xmm6, [rdi+(rbx+4)*8]
	movdqa xmm7, [rdi+(rbx+6)*8]

	; 4) Borrarle los últimos dos bits a cada color con máscara |0xFF|0xFC|0xFC|0xFC| x 4
 	; (Componente A tiene que estar todo en uno)
 	
	pand xmm2, borrarUlt2Bits     ; Hacer AND con los px levantado de src
	pand xmm3, borrarUlt2Bits
	pand xmm6, borrarUlt2Bits
	pand xmm7, borrarUlt2Bits

	; 5) Combinar los 4 pixeles de destino con los bits de la imagen oculta y guardar en dst
	por xmm0, xmm2       ; combinar px de src con px encriptados
	por xmm4, xmm3
	por xmm1, xmm6
	por xmm5, xmm7

	movdqa [rdx+rbx*8], xmm0     ; guardar en destino
	movdqa [rdx+(rbx+2)*8], xmm4
	movdqa [rdx+(rbx+4)*8], xmm1
	movdqa [rdx+(rbx+6)*8], xmm5

	add rbx, 8


	cmp rbx, r12
	je .fin

	; CONVERTIR LA IMAGEN A ESCALA DE GRISES
	; pixelGris = (src2[i][j].b + 2 * src2[i][j].g + src2[i][j].r) / 4
	; Extender a word (16 bits) y luego empaquetar saturado a byte

	; 1) Levantar 16 px de src2
	movdqa xmm0, [rsi+rbx*8]      ; xmm0 -> | A3 R3 G3 B3 | A2 R2 G2 B2 | A1 R1 G1 B1 | A0 R0 G0 B0 |
	movdqa xmm1, [rsi+(rbx+2)*8]  ; xmm1 -> | A7 R7 G7 B7 | A6 R6 G6 B6 | A5 R5 G5 B5 | A4 R4 G4 B4 |
	movdqa xmm2, [rsi+(rbx+4)*8]  ; xmm2 -> | AB RB GB BB | AA RA GA BA | A9 R9 G9 B9 | A8 R8 G8 B8 |
	movdqa xmm3, [rsi+(rbx+6)*8]  ; xmm3 -> | AF RF GF BF | AE RE GE BE | AD RD GD BD | AC RC GC BC |

	; 1) Filtrar B
	movdqa xmm11, separarComponentes ; Máscara: 0x0000_00FF x4
	movdqa xmm4, xmm0   ; copiar primeros 4 px
	movdqa xmm6, xmm1   ; copiar segundos 4 px
	movdqa xmm5, xmm2   ; copiar terceros 4 px
	movdqa xmm7, xmm3  ; copiar cuartos 4 px
	pand xmm4, xmm11    ; xmm4 -> |0000 00B3|0000 00B2|0000 00B1|0000 00B0|
	pand xmm6, xmm11    ; xmm5 -> |0000 00B7|0000 00B6|0000 00B5|0000 00B4|
	pand xmm5, xmm11   ;
	pand xmm7, xmm11
	; 1.1) Juntar las 8 words de B en dos registro
	packusdw xmm4, xmm6 ; xmm4 -> |00B7|00B6|00B5|00B4|00B3|00B2|00B1|00B0|
	packusdw xmm5, xmm7 ; xmm5 ->

	; 2) Filtrar G	
	pslldq xmm11, 1     ; shiftear máscara para filtrar G: 0x0000_FF00 x4
	movdqa xmm6, xmm0   ; copiar primeros 4 px
	movdqa xmm8, xmm1   ; copiar segundos 4 px
	movdqa xmm7, xmm2   ; 
	movdqa xmm9, xmm3
	pand xmm6, xmm11    ; xmm6 -> |0000 G300|0000 G200|0000 G100|0000 G000|
	pand xmm8, xmm11    ; xmm8 -> |0000 G700|0000 G600|0000 G500|0000 G400|
	pand xmm7, xmm11
	pand xmm9, xmm11
	; 2.1) Shiftear G a der a pos menos significativa (1 byte)
	psrldq xmm6, 1      ; xmm6 -> |0000 00G3|0000 00G2|0000 00G1|0000 00G0|
	psrldq xmm8, 1       ; xmm8 -> |0000 00G7|0000 00G6|0000 00G5|0000 00G4|
	psrldq xmm7, 1
	psrldq xmm9, 1
	; 2.2) Multiplicar x 2: shiftear a izq 1 bits (ahora ocupa word)
	psllw xmm6, 1       ; xmm5 -> |0000|G3*2|0000|G2*2|0000|G1*2|0000|G0*2|
	psllw xmm8, 1       ; xmmB -> |0000|G7*2|0000|G6*2|0000|G5*2|0000|G4*2|
	psllw xmm7, 1
	psllw xmm9, 1
	; 2.3) Juntar las 8 words de G en un registro
	packusdw xmm6, xmm8  ; xmm6 -> |G7*2|G6*2|G5*2|G4*2|G3*2|G2*2|G1*2|G0*2|
	packusdw xmm7, xmm9  ; xmm7

	; 3) Filtrar R
	pslldq xmm11, 1     ; shiftear máscara para filtrar R: 0x00FF_0000 x4
	pand xmm0, xmm11    ; xmm0 -> |00R3 0000|00R2 0000|00R1 0000|00R0 0000|
	pand xmm1, xmm11    ; xmm1 -> |00R7 0000|00R6 0000|00R5 0000|00R4 0000|
	pand xmm2, xmm11
	pand xmm3, xmm11
	; 3.1) Shiftear B a der a pos menos significativa (2 bytes)
	psrldq xmm0, 2      ; xmm0 -> |0000 00R3|0000 00R2|0000 00R1|0000 00R0|
	psrldq xmm1, 2      ; xmm1 -> |0000 00R7|0000 00R6|0000 00R5|0000 00R4|
	psrldq xmm2, 2
	psrldq xmm3, 2
	; 3.2) Juntar las 8 words de R en un registro
	packusdw xmm0, xmm1 ; xmm0 -> |00R7|00R6|00R5|00R4|00R3|00R2|00R1|00R0|
	packusdw xmm2, xmm3 ; xmm2

	; 4) Hacer sumas verticales saturadas
	;G:   | 2*G7 | 2*G6 | 2*G5 | 2*G4 | 2*G3 | 2*G2 | 2*G1 | 2*G0 |
	;B:   |   B7 |   B6 |   B5 |   B4 |   B3 |   B2 |   B1 |   B0 |
	;R:   |   R7 |   R6 |   R5 |   R4 |   R3 |   R2 |   R1 |   R0 |
	;Res: |2G7+B7+R7| ... |2G0+B0+R0|
	paddusw xmm4, xmm6   ; sumar B + 2G
	paddusw xmm0, xmm4   ; sumar (B + 2G) + R
	paddusw xmm5, xmm7
	paddusw xmm2, xmm5
	; 5) Dividir por 4: shiftear words a derecha 2 bits
	psrlw xmm0, 2
	psrlw xmm2, 2
	;pxor xmm0, xmm0
	; 6) Empaquetar saturado
	packuswb xmm0, xmm2  ; xmm0 -> |GSF GSE GSD GSC|GSB GSA GS9 GS8|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|

; CHECKPOINT: Pixeles escala de grises 0:15 en xmm1

; ARMAR IMAGEN DE SALIDA
; 1) Obtener los bits para guardar en cada color de la escala

; |GSF GSE GSD GSC|GSB GSA GS9 GS8|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|
	
	movdqa xmm10, separarBits

	; --BLUE-- en xmm1
	movdqa xmm1, xmm0   ; hacer una copia y filtrarlo con AND -> |b7 0 0 0 0 0 0 0| x 16
	pand xmm1, xmm10
	psrlw xmm1, 7       ; shiftear a la derecha 7 bits -> |0 0 0 0 0 0 0 b7| x 16
	psrlw xmm10, 3      ; máscara para obtener b4: shift right 3 bits (0x10 x 16)
	movdqa xmm2, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 0 b4 0 0 0 0| x 16
	pand xmm2, xmm10
	psrlw xmm2, 3       ; shiftear a la derecha 3 bits -> |0 0 0 0 0 0 b4 0| x 16
	por xmm1, xmm2      ; combinar con el b7: xmm1 -> |0 0 0 0 0 0 b4 b7| x 16
	
	; --GREEN-- en xmm2
	psllw xmm10, 2      ; máscara para obtener b6: shift left 2 bits (0x40 x 16)
	movdqa xmm2, xmm0   ; hacer una copia y filtrarlo con AND -> |0 b6 0 0 0 0 0 0| x 16
	pand xmm2, xmm10
	psrlw xmm2, 6   	; shiftear a la derecha 6 bits -> |0 0 0 0 0 0 0 b6| x 16
    psrlw xmm10, 3      ; máscara para obtener b3: shift right 3 bits (0x08)
    movdqa xmm3, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 0 0 b3 0 0 0| x 16
    pand xmm3, xmm10
    psrlw xmm3, 2       ; shiftear a la derecha 2 bits -> |0 0 0 0 0 0 b3 0| x 16
    por xmm2, xmm3      ; combinar con el b6: xmm2 -> |0 0 0 0 0 0 b3 b6| x 16
	
	; --RED-- en xmm3
	psllw xmm10, 2      ; máscara para obtener b5: shift left 2 bits (0x20 x 16)
	movdqa xmm3, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 b5 0 0 0 0 0| x 16
	pand xmm3, xmm10
	psrlw xmm3, 5       ; shiftear a la derecha 5 bits -> |0 0 0 0 0 0 0 b5| x 16
	psrlw xmm10, 3      ; máscara para obtener b2: shift right 3 bits (0x04)
	pand xmm0, xmm10    ; filtrarlo con AND -> |0 0 0 0 0 b2 0 0| x 16
	psrlw xmm0, 1       ; shiftear a la derecha 1 bit -> |0 0 0 0 0 0 b2 0| x 16
	por xmm3, xmm0      ; combinar con el b5: xmm3 -> |0 0 0 0 0 0 b2 b5| x 16

	; TENEMOS:
	; xmm3 -> |0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b2 b5| x 8 (pos menos sig)
	; xmm2 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b3 b6| x 8 (pos menos sig)
	; xmm1 -> |0 0 0 0 0 0 b4 b7|0 0 0 0 0 0 b4 b7| x 8 (pos menos sig)

	; OBJETIVO
	; reg1 (pixel 0-3) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
	; reg2 (pixel 4-7) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
	; reg3 (pixel 8-11) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
    ; reg4 (pixel 12-15) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
    movdqa xmm0, xmm1
    punpcklbw xmm0, xmm2  ; xmm0 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:7
    punpckhbw xmm1, xmm2  ; xmm1 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 8:15
    pxor xmm4, xmm4
    movdqa xmm2, xmm3
    punpcklbw xmm2, xmm4  ; xmm2 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5| de px 0:7
    punpckhbw xmm3, xmm4  ; xmm3 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5| de px 8:15

    ;Combinar xmm0 y xmm2
    movdqa xmm4, xmm0
    punpcklwd xmm0, xmm2  ; xmm0 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:3
	punpckhwd xmm4, xmm2  ; xmm4 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 4:7
	;Combinar xmm1 y xmm3
	movdqa xmm5, xmm1
	punpcklwd xmm1, xmm3  ; xmm1 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 8:11
	punpckhwd xmm5, xmm3  ; xmm5 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 12:15
	
; CHECKPOINT: bits a guardar en xmm0 (0:3), xmm4 (4:7), xmm1 (8:11), xmm5 (9:15)

; 2) Encriptar con xor
    ; Cargar los últimos 16 pixeles de la imagen
    movdqa xmm2, [rax]               ; | p63  | p62  | p61  | p60  |
    movdqa xmm3, [rax-16]            ; | p59  | p58  | p57  | p56  |
    movdqa xmm6, [rax-32]           ; | p55  | p54  | p53  | p52  |
    movdqa xmm7, [rax-48]           ; | p51  | p50  | p49  | p48  |
    sub rax, 64
    pshufd xmm8, xmm2, 0x1B          ; | p60 | p61 | p62 | p63 |
    pshufd xmm9, xmm3, 0x1B          ; | p56 | p57 | p58 | p59 |
    pshufd xmm10, xmm6, 0x1B        ; | p52 | p53 | p54 | p55 |
    pshufd xmm11, xmm7, 0x1B        ; | p48 | p49 | p50 | p51 |
    psrlw xmm8, 2             ; poner b2 y b3 en las pos menos significativas
    psrlw xmm9, 2
	psrlw xmm10, 2
	psrlw xmm11, 2
	pand xmm8, dejarUlt2Bits
	pand xmm9, dejarUlt2Bits
	pand xmm10, dejarUlt2Bits
	pand xmm11, dejarUlt2Bits
	pxor xmm0, xmm8                  ; xor ultimos 4 con primeros 4
	pxor xmm4, xmm9                  ; xor anteultimos 4 con segundos 4
	pxor xmm1, xmm10
	pxor xmm5, xmm11

; CHECKPOINT: bits encriptados en xmm0 (0:3), xmm4 (4:7), xmm1 (8:11), xmm5 (12:15)

	; 3) Cargar de src los 16 pixeles que se van a guardar en dst
	movdqa xmm2, [rdi+rbx*8]  ; levantar 8 px de src
	movdqa xmm3, [rdi+(rbx+2)*8]
	movdqa xmm6, [rdi+(rbx+4)*8]
	movdqa xmm7, [rdi+(rbx+6)*8]

	; 4) Borrarle los últimos dos bits a cada color con máscara |0xFF|0xFC|0xFC|0xFC| x 4
 	; (Componente A tiene que estar todo en uno)
 	
	pand xmm2, borrarUlt2Bits     ; Hacer AND con los px levantado de src
	pand xmm3, borrarUlt2Bits
	pand xmm6, borrarUlt2Bits
	pand xmm7, borrarUlt2Bits

	; 5) Combinar los 4 pixeles de destino con los bits de la imagen oculta y guardar en dst
	por xmm0, xmm2       ; combinar px de src con px encriptados
	por xmm4, xmm3
	por xmm1, xmm6
	por xmm5, xmm7

	movdqa [rdx+rbx*8], xmm0     ; guardar en destino
	movdqa [rdx+(rbx+2)*8], xmm4
	movdqa [rdx+(rbx+4)*8], xmm1
	movdqa [rdx+(rbx+6)*8], xmm5

	add rbx, 8

	
	cmp rbx, r12
	je .fin

	; CONVERTIR LA IMAGEN A ESCALA DE GRISES
	; pixelGris = (src2[i][j].b + 2 * src2[i][j].g + src2[i][j].r) / 4
	; Extender a word (16 bits) y luego empaquetar saturado a byte

	; 1) Levantar 16 px de src2
	movdqa xmm0, [rsi+rbx*8]      ; xmm0 -> | A3 R3 G3 B3 | A2 R2 G2 B2 | A1 R1 G1 B1 | A0 R0 G0 B0 |
	movdqa xmm1, [rsi+(rbx+2)*8]  ; xmm1 -> | A7 R7 G7 B7 | A6 R6 G6 B6 | A5 R5 G5 B5 | A4 R4 G4 B4 |
	movdqa xmm2, [rsi+(rbx+4)*8]  ; xmm2 -> | AB RB GB BB | AA RA GA BA | A9 R9 G9 B9 | A8 R8 G8 B8 |
	movdqa xmm3, [rsi+(rbx+6)*8]  ; xmm3 -> | AF RF GF BF | AE RE GE BE | AD RD GD BD | AC RC GC BC |

	; 1) Filtrar B
	movdqa xmm11, separarComponentes ; Máscara: 0x0000_00FF x4
	movdqa xmm4, xmm0   ; copiar primeros 4 px
	movdqa xmm6, xmm1   ; copiar segundos 4 px
	movdqa xmm5, xmm2   ; copiar terceros 4 px
	movdqa xmm7, xmm3  ; copiar cuartos 4 px
	pand xmm4, xmm11    ; xmm4 -> |0000 00B3|0000 00B2|0000 00B1|0000 00B0|
	pand xmm6, xmm11    ; xmm5 -> |0000 00B7|0000 00B6|0000 00B5|0000 00B4|
	pand xmm5, xmm11   ;
	pand xmm7, xmm11
	; 1.1) Juntar las 8 words de B en dos registro
	packusdw xmm4, xmm6 ; xmm4 -> |00B7|00B6|00B5|00B4|00B3|00B2|00B1|00B0|
	packusdw xmm5, xmm7 ; xmm5 ->

	; 2) Filtrar G	
	pslldq xmm11, 1     ; shiftear máscara para filtrar G: 0x0000_FF00 x4
	movdqa xmm6, xmm0   ; copiar primeros 4 px
	movdqa xmm8, xmm1   ; copiar segundos 4 px
	movdqa xmm7, xmm2   ; 
	movdqa xmm9, xmm3
	pand xmm6, xmm11    ; xmm6 -> |0000 G300|0000 G200|0000 G100|0000 G000|
	pand xmm8, xmm11    ; xmm8 -> |0000 G700|0000 G600|0000 G500|0000 G400|
	pand xmm7, xmm11
	pand xmm9, xmm11
	; 2.1) Shiftear G a der a pos menos significativa (1 byte)
	psrldq xmm6, 1      ; xmm6 -> |0000 00G3|0000 00G2|0000 00G1|0000 00G0|
	psrldq xmm8, 1       ; xmm8 -> |0000 00G7|0000 00G6|0000 00G5|0000 00G4|
	psrldq xmm7, 1
	psrldq xmm9, 1
	; 2.2) Multiplicar x 2: shiftear a izq 1 bits (ahora ocupa word)
	psllw xmm6, 1       ; xmm5 -> |0000|G3*2|0000|G2*2|0000|G1*2|0000|G0*2|
	psllw xmm8, 1       ; xmmB -> |0000|G7*2|0000|G6*2|0000|G5*2|0000|G4*2|
	psllw xmm7, 1
	psllw xmm9, 1
	; 2.3) Juntar las 8 words de G en un registro
	packusdw xmm6, xmm8  ; xmm6 -> |G7*2|G6*2|G5*2|G4*2|G3*2|G2*2|G1*2|G0*2|
	packusdw xmm7, xmm9  ; xmm7

	; 3) Filtrar R
	pslldq xmm11, 1     ; shiftear máscara para filtrar R: 0x00FF_0000 x4
	pand xmm0, xmm11    ; xmm0 -> |00R3 0000|00R2 0000|00R1 0000|00R0 0000|
	pand xmm1, xmm11    ; xmm1 -> |00R7 0000|00R6 0000|00R5 0000|00R4 0000|
	pand xmm2, xmm11
	pand xmm3, xmm11
	; 3.1) Shiftear B a der a pos menos significativa (2 bytes)
	psrldq xmm0, 2      ; xmm0 -> |0000 00R3|0000 00R2|0000 00R1|0000 00R0|
	psrldq xmm1, 2      ; xmm1 -> |0000 00R7|0000 00R6|0000 00R5|0000 00R4|
	psrldq xmm2, 2
	psrldq xmm3, 2
	; 3.2) Juntar las 8 words de R en un registro
	packusdw xmm0, xmm1 ; xmm0 -> |00R7|00R6|00R5|00R4|00R3|00R2|00R1|00R0|
	packusdw xmm2, xmm3 ; xmm2

	; 4) Hacer sumas verticales saturadas
	;G:   | 2*G7 | 2*G6 | 2*G5 | 2*G4 | 2*G3 | 2*G2 | 2*G1 | 2*G0 |
	;B:   |   B7 |   B6 |   B5 |   B4 |   B3 |   B2 |   B1 |   B0 |
	;R:   |   R7 |   R6 |   R5 |   R4 |   R3 |   R2 |   R1 |   R0 |
	;Res: |2G7+B7+R7| ... |2G0+B0+R0|
	paddusw xmm4, xmm6   ; sumar B + 2G
	paddusw xmm0, xmm4   ; sumar (B + 2G) + R
	paddusw xmm5, xmm7
	paddusw xmm2, xmm5
	; 5) Dividir por 4: shiftear words a derecha 2 bits
	psrlw xmm0, 2
	psrlw xmm2, 2
	;pxor xmm0, xmm0
	; 6) Empaquetar saturado
	packuswb xmm0, xmm2  ; xmm0 -> |GSF GSE GSD GSC|GSB GSA GS9 GS8|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|

; CHECKPOINT: Pixeles escala de grises 0:15 en xmm1

; ARMAR IMAGEN DE SALIDA
; 1) Obtener los bits para guardar en cada color de la escala

; |GSF GSE GSD GSC|GSB GSA GS9 GS8|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|
	
	movdqa xmm10, separarBits

	; --BLUE-- en xmm1
	movdqa xmm1, xmm0   ; hacer una copia y filtrarlo con AND -> |b7 0 0 0 0 0 0 0| x 16
	pand xmm1, xmm10
	psrlw xmm1, 7       ; shiftear a la derecha 7 bits -> |0 0 0 0 0 0 0 b7| x 16
	psrlw xmm10, 3      ; máscara para obtener b4: shift right 3 bits (0x10 x 16)
	movdqa xmm2, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 0 b4 0 0 0 0| x 16
	pand xmm2, xmm10
	psrlw xmm2, 3       ; shiftear a la derecha 3 bits -> |0 0 0 0 0 0 b4 0| x 16
	por xmm1, xmm2      ; combinar con el b7: xmm1 -> |0 0 0 0 0 0 b4 b7| x 16
	
	; --GREEN-- en xmm2
	psllw xmm10, 2      ; máscara para obtener b6: shift left 2 bits (0x40 x 16)
	movdqa xmm2, xmm0   ; hacer una copia y filtrarlo con AND -> |0 b6 0 0 0 0 0 0| x 16
	pand xmm2, xmm10
	psrlw xmm2, 6   	; shiftear a la derecha 6 bits -> |0 0 0 0 0 0 0 b6| x 16
    psrlw xmm10, 3      ; máscara para obtener b3: shift right 3 bits (0x08)
    movdqa xmm3, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 0 0 b3 0 0 0| x 16
    pand xmm3, xmm10
    psrlw xmm3, 2       ; shiftear a la derecha 2 bits -> |0 0 0 0 0 0 b3 0| x 16
    por xmm2, xmm3      ; combinar con el b6: xmm2 -> |0 0 0 0 0 0 b3 b6| x 16
	
	; --RED-- en xmm3
	psllw xmm10, 2      ; máscara para obtener b5: shift left 2 bits (0x20 x 16)
	movdqa xmm3, xmm0   ; hacer una copia y filtrarlo con AND -> |0 0 b5 0 0 0 0 0| x 16
	pand xmm3, xmm10
	psrlw xmm3, 5       ; shiftear a la derecha 5 bits -> |0 0 0 0 0 0 0 b5| x 16
	psrlw xmm10, 3      ; máscara para obtener b2: shift right 3 bits (0x04)
	pand xmm0, xmm10    ; filtrarlo con AND -> |0 0 0 0 0 b2 0 0| x 16
	psrlw xmm0, 1       ; shiftear a la derecha 1 bit -> |0 0 0 0 0 0 b2 0| x 16
	por xmm3, xmm0      ; combinar con el b5: xmm3 -> |0 0 0 0 0 0 b2 b5| x 16

	; TENEMOS:
	; xmm3 -> |0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b2 b5| x 8 (pos menos sig)
	; xmm2 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b3 b6| x 8 (pos menos sig)
	; xmm1 -> |0 0 0 0 0 0 b4 b7|0 0 0 0 0 0 b4 b7| x 8 (pos menos sig)

	; OBJETIVO
	; reg1 (pixel 0-3) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
	; reg2 (pixel 4-7) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
	; reg3 (pixel 8-11) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
    ; reg4 (pixel 12-15) -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| x 4
    movdqa xmm0, xmm1
    punpcklbw xmm0, xmm2  ; xmm0 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:7
    punpckhbw xmm1, xmm2  ; xmm1 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 8:15
    pxor xmm4, xmm4
    movdqa xmm2, xmm3
    punpcklbw xmm2, xmm4  ; xmm2 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5| de px 0:7
    punpckhbw xmm3, xmm4  ; xmm3 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5| de px 8:15

    ;Combinar xmm0 y xmm2
    movdqa xmm4, xmm0
    punpcklwd xmm0, xmm2  ; xmm0 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:3
	punpckhwd xmm4, xmm2  ; xmm4 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 4:7
	;Combinar xmm1 y xmm3
	movdqa xmm5, xmm1
	punpcklwd xmm1, xmm3  ; xmm1 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 8:11
	punpckhwd xmm5, xmm3  ; xmm5 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 12:15
	
; CHECKPOINT: bits a guardar en xmm0 (0:3), xmm4 (4:7), xmm1 (8:11), xmm5 (9:15)

; 2) Encriptar con xor
    ; Cargar los últimos 16 pixeles de la imagen
    movdqa xmm2, [rax]               ; | p63  | p62  | p61  | p60  |
    movdqa xmm3, [rax-16]            ; | p59  | p58  | p57  | p56  |
    movdqa xmm6, [rax-32]           ; | p55  | p54  | p53  | p52  |
    movdqa xmm7, [rax-48]           ; | p51  | p50  | p49  | p48  |
    sub rax, 64
    pshufd xmm8, xmm2, 0x1B          ; | p60 | p61 | p62 | p63 |
    pshufd xmm9, xmm3, 0x1B          ; | p56 | p57 | p58 | p59 |
    pshufd xmm10, xmm6, 0x1B        ; | p52 | p53 | p54 | p55 |
    pshufd xmm11, xmm7, 0x1B        ; | p48 | p49 | p50 | p51 |
    psrlw xmm8, 2             ; poner b2 y b3 en las pos menos significativas
    psrlw xmm9, 2
	psrlw xmm10, 2
	psrlw xmm11, 2
	pand xmm8, dejarUlt2Bits
	pand xmm9, dejarUlt2Bits
	pand xmm10, dejarUlt2Bits
	pand xmm11, dejarUlt2Bits
	pxor xmm0, xmm8                  ; xor ultimos 4 con primeros 4
	pxor xmm4, xmm9                  ; xor anteultimos 4 con segundos 4
	pxor xmm1, xmm10
	pxor xmm5, xmm11

; CHECKPOINT: bits encriptados en xmm0 (0:3), xmm4 (4:7), xmm1 (8:11), xmm5 (12:15)

	; 3) Cargar de src los 16 pixeles que se van a guardar en dst
	movdqa xmm2, [rdi+rbx*8]  ; levantar 8 px de src
	movdqa xmm3, [rdi+(rbx+2)*8]
	movdqa xmm6, [rdi+(rbx+4)*8]
	movdqa xmm7, [rdi+(rbx+6)*8]

	; 4) Borrarle los últimos dos bits a cada color con máscara |0xFF|0xFC|0xFC|0xFC| x 4
 	; (Componente A tiene que estar todo en uno)
 	
	pand xmm2, borrarUlt2Bits     ; Hacer AND con los px levantado de src
	pand xmm3, borrarUlt2Bits
	pand xmm6, borrarUlt2Bits
	pand xmm7, borrarUlt2Bits

	; 5) Combinar los 4 pixeles de destino con los bits de la imagen oculta y guardar en dst
	por xmm0, xmm2       ; combinar px de src con px encriptados
	por xmm4, xmm3
	por xmm1, xmm6
	por xmm5, xmm7

	movdqa [rdx+rbx*8], xmm0     ; guardar en destino
	movdqa [rdx+(rbx+2)*8], xmm4
	movdqa [rdx+(rbx+4)*8], xmm1
	movdqa [rdx+(rbx+6)*8], xmm5

	add rbx, 8



	jmp .ciclo

.fin:
	pop r12
	pop rbx
	pop rbp
	ret
