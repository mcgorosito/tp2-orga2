section .rodata
ALIGN 16
mascaraComponentes: times 4 dd 0x0000_00FF
mascaraSepararBits: times 8 dw 0x8080
mascaraDejarUlt2Bits: times 16 db 0x03
mascaraBorrarUlt2BitsRGB: times 4 dd 0xFFFC_FCFC

section .text
global Ocultar_asm

Ocultar_asm:

    ; -- Parámetros de entrada --
	; rdi <- uint8_t *src (imagen visible)
	; rsi <- uint8_t *src2 (imagen a ocultar)
	; rdx <- uint8_t *dst (imagen destino)
	; ecx <- width
	; r8d <- height
	; r9d <- src_row_size
	; [rbp+16] <- dst_row_size

	push rbp
	mov rbp, rsp
	push rbx
	push r12

	; -- Máscaras --
	movdqa xmm15, [mascaraComponentes]
	movdqa xmm14, [mascaraSepararBits]
	movdqa xmm13, [mascaraDejarUlt2Bits]
	movdqa xmm12, [mascaraBorrarUlt2BitsRGB]

	%define separarComponentes xmm15
	%define separarBits xmm14
	%define dejarUlt2Bits xmm13
	%define borrarUlt2Bits xmm12

	%define px_size 4

	movd xmm0, ecx
	movd xmm1, r8d
	pmuldq xmm0, xmm1    ; obtener tamaño en px: height*width
	movq r12, xmm0

	; Imagen espejo: obtener puntero al final
	mov rax, r12         ; rax -> size
	shl rax, 2           ; rax -> size*4 (cantidad de bytes por px)
	add rax, rdi         ; rax -> posición inmediatamente posterior al fin de la imagen
	sub rax, 16          ; rax -> Puntero a últimos 4 px

	xor rbx, rbx         ; contador de px procesados (+8 en cada ciclo)
	sub r12, 8           ; restar 8 para equiparar con condición movdqu

ciclo:
	cmp rbx, r12
	je fin

	; CONVERTIR LA IMAGEN A ESCALA DE GRISES -> (b + 2g + 4)/4

	; 1) Levantar 8 px de src2
	movdqa xmm1, [rsi]            ; xmm1 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
	movdqa xmm2, [rsi+4*px_size]  ; xmm2 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|

	; 1) Filtrar B
	movdqa xmm10, separarComponentes
	movdqa xmm3, xmm1        ; copiar primeros 4 px
	movdqa xmm4, xmm2        ; copiar segundos 4 px
	pand xmm3, xmm10         ; xmm3 -> |0000 00B3|0000 00B2|0000 00B1|0000 00B0|
	pand xmm4, xmm10         ; xmm4 -> |0000 00B7|0000 00B6|0000 00B5|0000 00B4|
	; Juntar las 8 words de B en un registro
	packusdw xmm3, xmm4      ; xmm3 -> |00B7|00B6|00B5|00B4|00B3|00B2|00B1|00B0|

	; 2) Filtrar G	
	pslldq xmm10, 1          ; shiftear máscara para filtrar G: 0x0000_FF00 x4
	movdqa xmm4, xmm1        ; copiar primeros 4 px
	movdqa xmm5, xmm2        ; copiar segundos 4 px
	pand xmm4, xmm10         ; xmm4 -> |0000 G300|0000 G200|0000 G100|0000 G000|
	pand xmm5, xmm10         ; xmm5 -> |0000 G700|0000 G600|0000 G500|0000 G400|
	; Shiftear G a der a pos menos significativa (1 byte)
	psrldq xmm4, 1           ; xmm4 -> |0000 00G3|0000 00G2|0000 00G1|0000 00G0|
	psrldq xmm5, 1           ; xmm5 -> |0000 00G7|0000 00G6|0000 00G5|0000 00G4|
	; Multiplicar x 2: shiftear a izq 1 bits (ahora ocupa word)
	psllw xmm4, 1            ; xmm4 -> |0000|G3*2|0000|G2*2|0000|G1*2|0000|G0*2|
	psllw xmm5, 1            ; xmm5 -> |0000|G7*2|0000|G6*2|0000|G5*2|0000|G4*2|
	; Juntar las 8 words de G en un registro
	packusdw xmm4, xmm5  ; xmm4 -> |G7*2|G6*2|G5*2|G4*2|G3*2|G2*2|G1*2|G0*2|

	; 3) Filtrar R
	pslldq xmm10, 1          ; shiftear máscara para filtrar R: 0x00FF_0000 x4
	pand xmm1, xmm10         ; xmm1 -> |00R3 0000|00R2 0000|00R1 0000|00R0 0000|
	pand xmm2, xmm10         ; xmm2 -> |00R7 0000|00R6 0000|00R5 0000|00R4 0000|
	; Shiftear B a der a pos menos significativa (2 bytes)
	psrldq xmm1, 2           ; xmm1 -> |0000 00R3|0000 00R2|0000 00R1|0000 00R0|
	psrldq xmm2, 2           ; xmm2 -> |0000 00R7|0000 00R6|0000 00R5|0000 00R4|
	; Juntar las 8 words de R en un registro
	packusdw xmm1, xmm2      ; xmm2 -> |00R7|00R6|00R5|00R4|00R3|00R2|00R1|00R0|

	; 4) Hacer sumas verticales saturadas y dividir por 4
	paddusw xmm3, xmm4       ; sumar B + 2G
	paddusw xmm1, xmm3       ; sumar (B + 2G) + R
	psrlw xmm1, 2
	pxor xmm0, xmm0

	; 5) Empaquetar con saturación
	packuswb xmm1, xmm0  ; xmm1 -> |0 0 0 0|0 0 0 0|GS7 GS6 GS5 GS4|GS3 GS2 GS1 GS0|
	
	; ARMAR IMAGEN DE SALIDA
	; 1) Obtener los bits para guardar en cada color de la escala
	movdqa xmm11, separarBits

	; --BLUE-- en xmm1
	movdqa xmm0, xmm1     ; hacer una copia y filtrarlo con AND -> |b7 0 0 0 0 0 0 0| x 16
	pand xmm1, xmm11
	psrlw xmm1, 7         ; shiftear a la derecha 7 bits -> |0 0 0 0 0 0 0 b7| x 8
	psrlw xmm11, 3        ; máscara para obtener b4: shift right 3 bits (0x10 x 16)
	movdqa xmm2, xmm0     ; hacer una copia y filtrarlo con AND -> |0 0 0 b4 0 0 0 0| x 8
	pand xmm2, xmm11
	psrlw xmm2, 3         ; shiftear a la derecha 3 bits -> |0 0 0 0 0 0 b4 0| x 16
	por xmm1, xmm2        ; combinar con el b7: xmm1 -> |0 0 0 0 0 0 b4 b7| x 8
	
	; --GREEN-- en xmm2
	psllw xmm11, 2        ; máscara para obtener b6: shift left 2 bits (0x40 x 16)
	movdqa xmm2, xmm0     ; hacer una copia y filtrarlo con AND -> |0 b6 0 0 0 0 0 0| x 8
	pand xmm2, xmm11
	psrlw xmm2, 6   	  ; shiftear a la derecha 6 bits -> |0 0 0 0 0 0 0 b6| x 8
    psrlw xmm11, 3        ; máscara para obtener b3: shift right 3 bits (0x08)
    movdqa xmm3, xmm0     ; hacer una copia y filtrarlo con AND -> |0 0 0 0 b3 0 0 0| x 8
    pand xmm3, xmm11
    psrlw xmm3, 2         ; shiftear a la derecha 2 bits -> |0 0 0 0 0 0 b3 0| x 8
    por xmm2, xmm3        ; combinar con el b6: xmm2 -> |0 0 0 0 0 0 b3 b6| x 8
	
	; --RED-- en xmm3
	psllw xmm11, 2        ; máscara para obtener b5: shift left 2 bits (0x20 x 16)
	movdqa xmm3, xmm0     ; hacer una copia y filtrarlo con AND -> |0 0 b5 0 0 0 0 0| x 8
	pand xmm3, xmm11
	psrlw xmm3, 5         ; shiftear a la derecha 5 bits -> |0 0 0 0 0 0 0 b5| x 8
	psrlw xmm11, 3        ; máscara para obtener b2: shift right 3 bits (0x04)
	pand xmm0, xmm11      ; filtrarlo con AND -> |0 0 0 0 0 b2 0 0| x 8
	psrlw xmm0, 1         ; shiftear a la derecha 1 bit -> |0 0 0 0 0 0 b2 0| x 8
	por xmm3, xmm0        ; combinar con el b5: xmm3 -> |0 0 0 0 0 0 b2 b5| x 8

	; Combinar todo
	pxor xmm0, xmm0
    punpcklbw xmm1, xmm2  ; xmm1 -> |0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:7
    punpcklbw xmm3, xmm0  ; xmm3 -> |0 0 0 0 0 0  0  0|0 0 0 0 0 0 b2 b5| de px 0:7
    movdqa xmm2, xmm1
    punpcklwd xmm1, xmm3  ; xmm1 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 0:3
	punpckhwd xmm2, xmm3  ; xmm2 -> |0 0 0 0 0 0 0 0|0 0 0 0 0 0 b2 b5|0 0 0 0 0 0 b3 b6|0 0 0 0 0 0 b4 b7| de px 4:7
	
	; 2) Encriptar con xor
    ; Cargar los últimos 8 pixeles de la imagen
    movdqa xmm3, [rax]              ; |px size-1|px size-2|px size-3|px size-4|
    movdqa xmm4, [rax-4*px_size]
    pshufd xmm5, xmm3, 0x1B         ; |px size-4|px size-3|px size-2|px size-1|
    pshufd xmm6, xmm4, 0x1B
    psrlw xmm5, 2                   ; poner b2 y b3 en las pos menos significativas
    psrlw xmm6, 2
	pand xmm5, dejarUlt2Bits
	pand xmm6, dejarUlt2Bits
	pxor xmm1, xmm5                 ; xor últimos 4 con primeros 4
	pxor xmm2, xmm6                 ; xor anteúltimos 4 con segundos 4

	; 3) Cargar de src los 8 pixeles que se van a guardar en dst
	movdqa xmm3, [rdi]              ; levantar 8 px de src
	movdqa xmm4, [rdi+4*px_size]

	; 4) Borrarle los últimos dos bits a cada color con máscara
	pand xmm3, borrarUlt2Bits
	pand xmm4, borrarUlt2Bits       

	; 5) Combinar los 4 pixeles de destino con los bits de la imagen oculta y guardar en dst
	por xmm1, xmm3                  ; combinar px de src con px encriptados
	por xmm2, xmm4

	movdqa [rdx], xmm1              ; guardar en destino
	movdqa [rdx+4*px_size], xmm2

	add rsi, 8*px_size
	add rdi, 8*px_size
	add rdx, 8*px_size
	sub rax, 8*px_size
	add rbx, 8
	jmp ciclo

fin:
	pop r12
	pop rbx
	pop rbp
	ret
