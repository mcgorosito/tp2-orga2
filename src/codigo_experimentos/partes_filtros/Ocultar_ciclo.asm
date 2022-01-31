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
	;movdqa xmm15, [mascaraComponentes]
	;movdqa xmm14, [mascaraSepararBits]
	;movdqa xmm13, [mascaraDejarUlt2Bits]
	;movdqa xmm12, [mascaraBorrarUlt2BitsRGB]

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

ciclo:
	cmp rbx, r12
	je fin

	; CONVERTIR LA IMAGEN A ESCALA DE GRISES -> (b + 2g + 4)/4

	; 1) Levantar 8 px de src2
	;movdqa xmm1, [rsi]            ; xmm1 -> |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0|
	;movdqa xmm2, [rsi+4*px_size]  ; xmm2 -> |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|

    ;movdqa xmm3, [rax]              ; |px size-1|px size-2|px size-3|px size-4|
    ;movdqa xmm4, [rax-4*px_size]

	;movdqa xmm3, [rdi]              ; levantar 8 px de src
	;movdqa xmm4, [rdi+4*px_size]

	;movdqa [rdx], xmm1              ; guardar en destino
	;movdqa [rdx+4*px_size], xmm2

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
