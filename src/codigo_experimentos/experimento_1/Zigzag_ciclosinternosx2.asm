section .rodata
ALIGN 16
marcoBlanco: times 16 db 0xFF
cincoFsp: times 4 dd 5.0

section .text
global Zigzag_asm

Zigzag_asm:
	push rbp
	mov rbp, rsp
	push rbx
	push r12
	push r13
	push r14

	mov r9, rdx    ; mover width a rcx
	xor rbx, rbx   ; inicalizar contador para cantidad de filas (num_fila)

	%define ptr_src rdi
	%define ptr_dst rsi
	%define cant_filas rcx
	%define width r9
	%define row_size r8
	%define num_fila rbx
	%define px_size 4

	movdqa xmm7, [marcoBlanco]     ; cargar máscaras
	%define marco xmm7
	movaps xmm9, [cincoFsp]
	%define cincoFloat xmm9

	xor rax, rax            ; offset fila 0 para la primera fila

	; FILA 0
	lea r13, [rsi+rax]      ; Calcular direccion de inicio de fila en dst
	xor r14, r14            ; Inicializar contador para ciclo fila
	mov rdx, width          ; copiar width en rdx (para poder modificarla)

		.cicloFilaBlanca0:
		movdqa [r13], marco
		movdqa [r13+4*px_size], marco
		add r13, 8*px_size      ; Avanzar pos de memoria 4 pixeles
		add r14, 8              ; Incrementar contador
		cmp r14, rdx
		jne .cicloFilaBlanca0

	inc num_fila
	mov rax, row_size          ; Si no, calcular offset de fila
	mul num_fila               ; res en rax
	
	; FILA 1
	lea r13, [rsi+rax]         ; Calcular direccion de inicio de fila en dst
	xor r14, r14            ; Inicializar contador para ciclo fila
	mov rdx, width          ; copiar width en rdx (para poder modificarla)

		.cicloFilaBlanca1:
		movdqa [r13], marco
		movdqa [r13+4*px_size], marco
		add r13, 8*px_size      ; Avanzar pos de memoria 4 pixeles
		add r14, 8              ; Incrementar contador
		cmp r14, rdx
		jne .cicloFilaBlanca1

	inc num_fila
	mov rax, row_size          ; Si no, calcular offset de fila
	mul num_fila               ; res en rax

ciclo:
	; FILAS MOD 4 = 2 
	lea r12, [rdi+rax]   ; Calcular direccion de inicio de fila en src
	lea r13, [rsi+rax]   ; Calcular direccion de inicio de fila en dst
	xor r14, r14         ; inicializar contador interno a fila
	movq [r13], marco
	add r13, 2*px_size   ; avanzar dos px en pos de memoria en dst
	add r14, 2           ; avanzar dos px en el contador
	mov rdx, width       ; el ciclo termina al llegar a width-2
	sub rdx, 2

	movdqa xmm8, [r12]      ; Cargar los primeros 4 de memoria
	add r12, 4*px_size      ; src siempre está 4 pos adelantada

		.cicloFilas2:
		movdqa xmm0, xmm8          ; | px3 | px2 | px1 | px0 |
		movdqa xmm1, [r12]         ; | px7 | px6 | px5 | px4 | -> en cada uno  | A R G B | -> NO PISAR: se usa en prox ciclo

		movdqa xmm10, xmm0         ; |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0| -> guardar una copia tal cual

		movdqa xmm11, xmm0         ; Objetivo: |A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|
		psrldq xmm11, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|
		pextrd eax, xmm1, 0x00     ; extraer px 4 (pos 00) de xmm1 y guardarlo en xmm2
		pinsrd xmm11, eax, 0x03    ; insertarlo en xmm11 en la última posición

		movdqa xmm12, xmm11        ; Objetivo: |A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2| 
		psrldq xmm12, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2|
		pextrd eax, xmm1, 0x01     ; extraer px 5 (pos 01) de xmm1 y guardarlo en xmm2	
		pinsrd xmm12, eax, 0x03    ; insertarlo en xmm12 en la última posición

		movdqa xmm13, xmm12        ; Objetivo: |A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3| 
		psrldq xmm13, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3|
		pextrd eax, xmm1, 0x02     ; extraer px 6 (pos 10) de xmm1 y guardarlo en xmm2	
		pinsrd xmm13, eax, 0x03    ; insertarlo en xmm13 en la última posición

		movdqa xmm14, xmm1         ; Objetivo: |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4| 

		movdqa xmm8, xmm1          ; guardar xmm1 en xmm15 para usar en prox ciclo

    	; Desempaquetar a words (para no perder precisión)
    	pxor xmm15, xmm15           ; registro con ceros
    	movdqa xmm0, xmm10          ; xmm10 -> low xmm0 (px 0-1), high xmm10 (px 2-3)   (instruccion innecesaria, ya son iguales)
    	punpcklbw xmm0, xmm15
    	punpckhbw xmm10, xmm15

    	movdqa xmm1, xmm11          ; xmm11 -> low xmm1 (px 1-2), high xmm11 (px 3-4)
    	punpcklbw xmm1, xmm15
    	punpckhbw xmm11, xmm15

    	movdqa xmm2, xmm12          ; xmm12 -> low xmm2 (px 2-3), high xmm12 (px 4-5)
    	punpcklbw xmm2, xmm15 
    	punpckhbw xmm12, xmm15

    	movdqa xmm3, xmm13          ; xmm13 -> low xmm3 (px 3-4), high xmm13 (px 5-6)
    	punpcklbw xmm3, xmm15
    	punpckhbw xmm13, xmm15

    	movdqa xmm4, xmm14          ; xmm14 -> low xmm4 (px 4-5), high xmm14 (px 6-7);
    	punpcklbw xmm4, xmm15
    	punpckhbw xmm14, xmm15
  
    	; Sumar todo verticalmente (words):
    	paddw xmm0, xmm1            ; parte baja: px 2 y 3
    	paddw xmm0, xmm2
    	paddw xmm0, xmm3
    	paddw xmm0, xmm4            ; res en xmm0: |Suma px3|Suma px2|
   		paddw xmm10, xmm11          ; parte alta: px 4 y 5
    	paddw xmm10, xmm12
    	paddw xmm10, xmm13
    	paddw xmm10, xmm14          ; res en xmm10: |Suma px5|Suma px4|

    	; Desempaquetar a dw (32 bits)
    	movdqa xmm1, xmm0
    	punpcklwd xmm0, xmm15     ; xmm0  -> |sumaApx2 sumaRpx2 sumaGpx2 sumaBpx2|
    	punpckhwd xmm1, xmm15     ; xmm1  -> |sumaApx3 sumaRpx3 sumaGpx3 sumaBpx3|
    	movdqa xmm11, xmm10
    	punpcklwd xmm10, xmm15    ; xmm10 -> |sumaApx4 sumaRpx3 sumaGpx4 sumaBpx4|
    	punpckhwd xmm11, xmm15    ; xmm11 -> |sumaApx5 sumaRpx5 sumaGpx5 sumaBpx5|

    	; Convertir a single fp (x4)
    	cvtdq2ps xmm2, xmm0
    	cvtdq2ps xmm3, xmm1
    	cvtdq2ps xmm4, xmm10
    	cvtdq2ps xmm5, xmm11

    	; Dividir por 5
    	divps xmm2, cincoFloat           ; |sumaApx2/5 sumaRpx2/5 sumaGpx2/5 sumaBpx2/5|
    	divps xmm3, cincoFloat           ; |sumaApx3/5 sumaRpx3/5 sumaGpx3/5 sumaBpx3/5|
    	divps xmm4, cincoFloat           ; |sumaApx4/5 sumaRpx4/5 sumaGpx4/5 sumaBpx4/5|
    	divps xmm5, cincoFloat           ; |sumaApx5/5 sumaRpx5/5 sumaGpx5/5 sumaBpx5/5|

    	; Convertir de float a int (x4)
    	cvttps2dq xmm0, xmm2
    	cvttps2dq xmm1, xmm3
    	cvttps2dq xmm2, xmm4
    	cvttps2dq xmm3, xmm5

    	; Empaquetar sat de double a word (32 a 16 bits)
    	packusdw xmm0, xmm1   ; |Apx3T Rpx3T Gpx3T Bpx3T|Apx2T Rpx2T Gpx2T Bpx2T|
    	packusdw xmm2, xmm3   ; |Apx5T Rpx5T Gpx5T Bpx5T|Apx4T Rpx4T Gpx4T Bpx4T|
    	packuswb xmm0, xmm2   ; Empaquetar sat a 8 bits: |px5T|px4T|px3T|px2T|

    	movdqu [r13], xmm0    ; Guardar en memoria (no está alineda la pos)
    	
    	add r12, 4*px_size    ; avanzar 8 en imagen src
    	add r13, 4*px_size    ; avanzar 4 en imagen dst
		add r14, 4            ; avanzar el contador de fila 4 pos (está parado en el 6) - DEBUG: CHEQUEAR ESTE VALOR

		cmp r14, rdx          ; ver si llegó a width-2
		je .finCicloFilas2

				movdqa xmm0, xmm8          ; | px3 | px2 | px1 | px0 |
		movdqa xmm1, [r12]         ; | px7 | px6 | px5 | px4 | -> en cada uno  | A R G B | -> NO PISAR: se usa en prox ciclo

		movdqa xmm10, xmm0         ; |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0| -> guardar una copia tal cual

		movdqa xmm11, xmm0         ; Objetivo: |A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|
		psrldq xmm11, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|
		pextrd eax, xmm1, 0x00     ; extraer px 4 (pos 00) de xmm1 y guardarlo en xmm2
		pinsrd xmm11, eax, 0x03    ; insertarlo en xmm11 en la última posición

		movdqa xmm12, xmm11        ; Objetivo: |A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2| 
		psrldq xmm12, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2|
		pextrd eax, xmm1, 0x01     ; extraer px 5 (pos 01) de xmm1 y guardarlo en xmm2	
		pinsrd xmm12, eax, 0x03    ; insertarlo en xmm12 en la última posición

		movdqa xmm13, xmm12        ; Objetivo: |A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3| 
		psrldq xmm13, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3|
		pextrd eax, xmm1, 0x02     ; extraer px 6 (pos 10) de xmm1 y guardarlo en xmm2	
		pinsrd xmm13, eax, 0x03    ; insertarlo en xmm13 en la última posición

		movdqa xmm14, xmm1         ; Objetivo: |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4| 

		movdqa xmm8, xmm1          ; guardar xmm1 en xmm15 para usar en prox ciclo

    	; Desempaquetar a words (para no perder precisión)
    	pxor xmm15, xmm15           ; registro con ceros
    	movdqa xmm0, xmm10          ; xmm10 -> low xmm0 (px 0-1), high xmm10 (px 2-3)   (instruccion innecesaria, ya son iguales)
    	punpcklbw xmm0, xmm15
    	punpckhbw xmm10, xmm15

    	movdqa xmm1, xmm11          ; xmm11 -> low xmm1 (px 1-2), high xmm11 (px 3-4)
    	punpcklbw xmm1, xmm15
    	punpckhbw xmm11, xmm15

    	movdqa xmm2, xmm12          ; xmm12 -> low xmm2 (px 2-3), high xmm12 (px 4-5)
    	punpcklbw xmm2, xmm15 
    	punpckhbw xmm12, xmm15

    	movdqa xmm3, xmm13          ; xmm13 -> low xmm3 (px 3-4), high xmm13 (px 5-6)
    	punpcklbw xmm3, xmm15
    	punpckhbw xmm13, xmm15

    	movdqa xmm4, xmm14          ; xmm14 -> low xmm4 (px 4-5), high xmm14 (px 6-7);
    	punpcklbw xmm4, xmm15
    	punpckhbw xmm14, xmm15
  
    	; Sumar todo verticalmente (words):
    	paddw xmm0, xmm1            ; parte baja: px 2 y 3
    	paddw xmm0, xmm2
    	paddw xmm0, xmm3
    	paddw xmm0, xmm4            ; res en xmm0: |Suma px3|Suma px2|
   		paddw xmm10, xmm11          ; parte alta: px 4 y 5
    	paddw xmm10, xmm12
    	paddw xmm10, xmm13
    	paddw xmm10, xmm14          ; res en xmm10: |Suma px5|Suma px4|

    	; Desempaquetar a dw (32 bits)
    	movdqa xmm1, xmm0
    	punpcklwd xmm0, xmm15     ; xmm0  -> |sumaApx2 sumaRpx2 sumaGpx2 sumaBpx2|
    	punpckhwd xmm1, xmm15     ; xmm1  -> |sumaApx3 sumaRpx3 sumaGpx3 sumaBpx3|
    	movdqa xmm11, xmm10
    	punpcklwd xmm10, xmm15    ; xmm10 -> |sumaApx4 sumaRpx3 sumaGpx4 sumaBpx4|
    	punpckhwd xmm11, xmm15    ; xmm11 -> |sumaApx5 sumaRpx5 sumaGpx5 sumaBpx5|

    	; Convertir a single fp (x4)
    	cvtdq2ps xmm2, xmm0
    	cvtdq2ps xmm3, xmm1
    	cvtdq2ps xmm4, xmm10
    	cvtdq2ps xmm5, xmm11

    	; Dividir por 5
    	divps xmm2, cincoFloat           ; |sumaApx2/5 sumaRpx2/5 sumaGpx2/5 sumaBpx2/5|
    	divps xmm3, cincoFloat           ; |sumaApx3/5 sumaRpx3/5 sumaGpx3/5 sumaBpx3/5|
    	divps xmm4, cincoFloat           ; |sumaApx4/5 sumaRpx4/5 sumaGpx4/5 sumaBpx4/5|
    	divps xmm5, cincoFloat           ; |sumaApx5/5 sumaRpx5/5 sumaGpx5/5 sumaBpx5/5|

    	; Convertir de float a int (x4)
    	cvttps2dq xmm0, xmm2
    	cvttps2dq xmm1, xmm3
    	cvttps2dq xmm2, xmm4
    	cvttps2dq xmm3, xmm5

    	; Empaquetar sat de double a word (32 a 16 bits)
    	packusdw xmm0, xmm1   ; |Apx3T Rpx3T Gpx3T Bpx3T|Apx2T Rpx2T Gpx2T Bpx2T|
    	packusdw xmm2, xmm3   ; |Apx5T Rpx5T Gpx5T Bpx5T|Apx4T Rpx4T Gpx4T Bpx4T|
    	packuswb xmm0, xmm2   ; Empaquetar sat a 8 bits: |px5T|px4T|px3T|px2T|

    	movdqu [r13], xmm0    ; Guardar en memoria (no está alineda la pos)
    	
    	add r12, 4*px_size    ; avanzar 8 en imagen src
    	add r13, 4*px_size    ; avanzar 4 en imagen dst
		add r14, 4            ; avanzar el contador de fila 4 pos (está parado en el 6) - DEBUG: CHEQUEAR ESTE VALOR

		cmp r14, rdx          ; ver si llegó a width-2
		jne .cicloFilas2

	.finCicloFilas2:
	movq [r13], marco

	inc num_fila               ; avanzar fila
	mov rax, row_size          ; calcular offset de fila
	mul num_fila               ; res en rax
	mov rdx, cant_filas        ; si es una de las últimas 2 filas, saltar a filas blancas
	sub rdx, 2
	cmp num_fila, rdx
	je fin

	; FILAS MOD 4 = 3
	lea r12, [rdi+rax]         ; Calcular direccion de inicio de fila en src
	lea r13, [rsi+rax]         ; Calcular direccion de inicio de fila en dst
	xor r14, r14        ; Inicializar contador para ciclo fila (va a la par de dst)

	add r12, 2*px_size           ; Adelantar fila src dos pixeles
	mov rdx, width
	sub rdx, 8                   ; menos 10 del final y 2 que adelanté

		.cicloFilas3:
		movdqu xmm0, [r12]      ; | px5 | px4 | px3 | px2 | (no alineada)
		movdqu xmm2, [r12+4*px_size]
		cmp r14, 0              ; si son los primeros px de la fila, agregar el marco
		jne .seguir
		movdqa xmm1, marco      ; xmm1 -> | FFFF | FFFF | FFFF | FFFF |  
		psrldq xmm1, 8          ; Agregar marco blanco en parte baja
		por xmm0, xmm1

		.seguir:
		movdqa [r13], xmm0       ; Guardarlos en dst -> ALINEADO
		movdqa [r13+4*px_size], xmm2
		add r12, 8*px_size       ; Avanzar pos de memoria 4 pixeles
		add r13, 8*px_size
		add r14, 8               ; Incrementar contador

		cmp r14, rdx             ; comparar contador con width-6. Si es distinto, volver a cicloFila3
		jne .cicloFilas3          ; Si es igual, seguir
	
	movdqu xmm3, [r12]
	movdqa xmm0, [r12+2*px_size]       ; xmm0 -> | px63 | px62 | px61 | px60 |
	psrldq xmm0, 8                   ; | 0000 | 0000 | px63 | px62 |
	movdqa xmm1, marco                 ; xmm1 -> | FFFF | FFFF | FFFF | FFFF |  
	pslldq xmm1, 8           ; Agregar marco blanco (ya está en xmm15)
	por xmm0, xmm1           ; Parte baja del marco ya está en xmm1
	movdqa [r13], xmm3
	movdqa [r13+4*px_size], xmm0       ; Guardar px en memoria

	inc num_fila               ; avanzar fila
	mov rax, row_size          ; calcular offset de fila
	mul num_fila               ; res en rax
	mov rdx, cant_filas        ; si es una de las últimas 2 filas, saltar a filas blancas
	sub rdx, 2
	cmp num_fila, rdx
	je fin

	; FILAS MOD 4 = 0
	lea r12, [rdi+rax]         ; Calcular direccion de inicio de fila en src
	lea r13, [rsi+rax]         ; Calcular direccion de inicio de fila en dst
	xor r14, r14        ; inicializar contador interno a fila
	
	movq [r13], marco
	add r13, 2*px_size  ; avanzar dos px en pos de memoria en dst
	add r14, 2          ; avanzar dos px en el contador
	mov rdx, width      ; el ciclo termina al llegar a width-2
	sub rdx, 2

	movdqa xmm8, [r12]      ; Cargar los primeros 4 de memoria
	add r12, 4*px_size      ; src siempre está 4 pos adelantada

		.cicloFilas0:
		movdqa xmm0, xmm8          ; | px3 | px2 | px1 | px0 |
		movdqa xmm1, [r12]         ; | px7 | px6 | px5 | px4 | -> en cada uno  | A R G B | -> NO PISAR: se usa en prox ciclo

		movdqa xmm10, xmm0         ; |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0| -> guardar una copia tal cual

		movdqa xmm11, xmm0         ; Objetivo: |A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|
		psrldq xmm11, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|
		pextrd eax, xmm1, 0x00     ; extraer px 4 (pos 00) de xmm1 y guardarlo en xmm2
		pinsrd xmm11, eax, 0x03    ; insertarlo en xmm11 en la última posición

		movdqa xmm12, xmm11        ; Objetivo: |A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2| 
		psrldq xmm12, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2|
		pextrd eax, xmm1, 0x01     ; extraer px 5 (pos 01) de xmm1 y guardarlo en xmm2	
		pinsrd xmm12, eax, 0x03    ; insertarlo en xmm12 en la última posición

		movdqa xmm13, xmm12        ; Objetivo: |A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3| 
		psrldq xmm13, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3|
		pextrd eax, xmm1, 0x02     ; extraer px 6 (pos 10) de xmm1 y guardarlo en xmm2	
		pinsrd xmm13, eax, 0x03    ; insertarlo en xmm13 en la última posición

		movdqa xmm14, xmm1         ; Objetivo: |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4| 

		movdqa xmm8, xmm1          ; guardar xmm1 en xmm15 para usar en prox ciclo

    	; Desempaquetar a words (para no perder precisión)
    	pxor xmm15, xmm15           ; registro con ceros
    	movdqa xmm0, xmm10          ; xmm10 -> low xmm0 (px 0-1), high xmm10 (px 2-3)   (instruccion innecesaria, ya son iguales)
    	punpcklbw xmm0, xmm15
    	punpckhbw xmm10, xmm15

    	movdqa xmm1, xmm11          ; xmm11 -> low xmm1 (px 1-2), high xmm11 (px 3-4)
    	punpcklbw xmm1, xmm15
    	punpckhbw xmm11, xmm15

    	movdqa xmm2, xmm12          ; xmm12 -> low xmm2 (px 2-3), high xmm12 (px 4-5)
    	punpcklbw xmm2, xmm15 
    	punpckhbw xmm12, xmm15

    	movdqa xmm3, xmm13          ; xmm13 -> low xmm3 (px 3-4), high xmm13 (px 5-6)
    	punpcklbw xmm3, xmm15
    	punpckhbw xmm13, xmm15

    	movdqa xmm4, xmm14          ; xmm14 -> low xmm4 (px 4-5), high xmm14 (px 6-7);
    	punpcklbw xmm4, xmm15
    	punpckhbw xmm14, xmm15
  
    	; Sumar todo verticalmente (words):
    	paddw xmm0, xmm1            ; parte baja: px 2 y 3
    	paddw xmm0, xmm2
    	paddw xmm0, xmm3
    	paddw xmm0, xmm4            ; res en xmm0: |Suma px3|Suma px2|
   		paddw xmm10, xmm11          ; parte alta: px 4 y 5
    	paddw xmm10, xmm12
    	paddw xmm10, xmm13
    	paddw xmm10, xmm14          ; res en xmm10: |Suma px5|Suma px4|

		; Desempaquetar a dw (32 bits)
    	movdqa xmm1, xmm0
    	punpcklwd xmm0, xmm15     ; xmm0  -> |sumaApx2 sumaRpx2 sumaGpx2 sumaBpx2|
    	punpckhwd xmm1, xmm15     ; xmm1  -> |sumaApx3 sumaRpx3 sumaGpx3 sumaBpx3|
    	movdqa xmm11, xmm10
    	punpcklwd xmm10, xmm15    ; xmm10 -> |sumaApx4 sumaRpx3 sumaGpx4 sumaBpx4|
    	punpckhwd xmm11, xmm15    ; xmm11 -> |sumaApx5 sumaRpx5 sumaGpx5 sumaBpx5|

    	; Convertir a single fp (x4)
    	cvtdq2ps xmm2, xmm0
    	cvtdq2ps xmm3, xmm1
    	cvtdq2ps xmm4, xmm10
    	cvtdq2ps xmm5, xmm11

    	; Dividir por 5
    	divps xmm2, cincoFloat           ; |sumaApx2/5 sumaRpx2/5 sumaGpx2/5 sumaBpx2/5|
    	divps xmm3, cincoFloat           ; |sumaApx3/5 sumaRpx3/5 sumaGpx3/5 sumaBpx3/5|
    	divps xmm4, cincoFloat           ; |sumaApx4/5 sumaRpx4/5 sumaGpx4/5 sumaBpx4/5|
    	divps xmm5, cincoFloat           ; |sumaApx5/5 sumaRpx5/5 sumaGpx5/5 sumaBpx5/5|

    	; Convertir de float a int (x4)
    	cvttps2dq xmm0, xmm2
    	cvttps2dq xmm1, xmm3
    	cvttps2dq xmm2, xmm4
    	cvttps2dq xmm3, xmm5

    	; Empaquetar sat de double a word (32 a 16 bits)
    	packusdw xmm0, xmm1   ; |Apx3T Rpx3T Gpx3T Bpx3T|Apx2T Rpx2T Gpx2T Bpx2T|
    	packusdw xmm2, xmm3   ; |Apx5T Rpx5T Gpx5T Bpx5T|Apx4T Rpx4T Gpx4T Bpx4T|
    	packuswb xmm0, xmm2   ; Empaquetar sat a 8 bits: |px5T|px4T|px3T|px2T|

    	movdqu [r13], xmm0    ; Guardar en memoria (no está alineda la pos)
    	
    	add r12, 4*px_size    ; avanzar 8 en imagen src
    	add r13, 4*px_size    ; avanzar 4 en imagen dst
		add r14, 4            ; avanzar el contador de fila 4 pos (está parado en el 6) - DEBUG: CHEQUEAR ESTE VALOR

		cmp r14, rdx          ; ver si llegó a width-2
		je .finCicloFilas0
		
		movdqa xmm0, xmm8          ; | px3 | px2 | px1 | px0 |
		movdqa xmm1, [r12]         ; | px7 | px6 | px5 | px4 | -> en cada uno  | A R G B | -> NO PISAR: se usa en prox ciclo

		movdqa xmm10, xmm0         ; |A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|A0 R0 G0 B0| -> guardar una copia tal cual

		movdqa xmm11, xmm0         ; Objetivo: |A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|
		psrldq xmm11, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A3 R3 G3 B3|A2 R2 G2 B2|A1 R1 G1 B1|
		pextrd eax, xmm1, 0x00     ; extraer px 4 (pos 00) de xmm1 y guardarlo en xmm2
		pinsrd xmm11, eax, 0x03    ; insertarlo en xmm11 en la última posición

		movdqa xmm12, xmm11        ; Objetivo: |A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2| 
		psrldq xmm12, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A4 R4 G4 B4|A3 R3 G3 B3|A2 R2 G2 B2|
		pextrd eax, xmm1, 0x01     ; extraer px 5 (pos 01) de xmm1 y guardarlo en xmm2	
		pinsrd xmm12, eax, 0x03    ; insertarlo en xmm12 en la última posición

		movdqa xmm13, xmm12        ; Objetivo: |A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3| 
		psrldq xmm13, 4            ; shiftear 8 bytes (1 px) a derecha: |00 00 00 00|A5 R5 G5 B5|A4 R4 G4 B4|A3 R3 G3 B3|
		pextrd eax, xmm1, 0x02     ; extraer px 6 (pos 10) de xmm1 y guardarlo en xmm2	
		pinsrd xmm13, eax, 0x03    ; insertarlo en xmm13 en la última posición

		movdqa xmm14, xmm1         ; Objetivo: |A7 R7 G7 B7|A6 R6 G6 B6|A5 R5 G5 B5|A4 R4 G4 B4| 

		movdqa xmm8, xmm1          ; guardar xmm1 en xmm15 para usar en prox ciclo

    	; Desempaquetar a words (para no perder precisión)
    	pxor xmm15, xmm15           ; registro con ceros
    	movdqa xmm0, xmm10          ; xmm10 -> low xmm0 (px 0-1), high xmm10 (px 2-3)   (instruccion innecesaria, ya son iguales)
    	punpcklbw xmm0, xmm15
    	punpckhbw xmm10, xmm15

    	movdqa xmm1, xmm11          ; xmm11 -> low xmm1 (px 1-2), high xmm11 (px 3-4)
    	punpcklbw xmm1, xmm15
    	punpckhbw xmm11, xmm15

    	movdqa xmm2, xmm12          ; xmm12 -> low xmm2 (px 2-3), high xmm12 (px 4-5)
    	punpcklbw xmm2, xmm15 
    	punpckhbw xmm12, xmm15

    	movdqa xmm3, xmm13          ; xmm13 -> low xmm3 (px 3-4), high xmm13 (px 5-6)
    	punpcklbw xmm3, xmm15
    	punpckhbw xmm13, xmm15

    	movdqa xmm4, xmm14          ; xmm14 -> low xmm4 (px 4-5), high xmm14 (px 6-7);
    	punpcklbw xmm4, xmm15
    	punpckhbw xmm14, xmm15
  
    	; Sumar todo verticalmente (words):
    	paddw xmm0, xmm1            ; parte baja: px 2 y 3
    	paddw xmm0, xmm2
    	paddw xmm0, xmm3
    	paddw xmm0, xmm4            ; res en xmm0: |Suma px3|Suma px2|
   		paddw xmm10, xmm11          ; parte alta: px 4 y 5
    	paddw xmm10, xmm12
    	paddw xmm10, xmm13
    	paddw xmm10, xmm14          ; res en xmm10: |Suma px5|Suma px4|

		; Desempaquetar a dw (32 bits)
    	movdqa xmm1, xmm0
    	punpcklwd xmm0, xmm15     ; xmm0  -> |sumaApx2 sumaRpx2 sumaGpx2 sumaBpx2|
    	punpckhwd xmm1, xmm15     ; xmm1  -> |sumaApx3 sumaRpx3 sumaGpx3 sumaBpx3|
    	movdqa xmm11, xmm10
    	punpcklwd xmm10, xmm15    ; xmm10 -> |sumaApx4 sumaRpx3 sumaGpx4 sumaBpx4|
    	punpckhwd xmm11, xmm15    ; xmm11 -> |sumaApx5 sumaRpx5 sumaGpx5 sumaBpx5|

    	; Convertir a single fp (x4)
    	cvtdq2ps xmm2, xmm0
    	cvtdq2ps xmm3, xmm1
    	cvtdq2ps xmm4, xmm10
    	cvtdq2ps xmm5, xmm11

    	; Dividir por 5
    	divps xmm2, cincoFloat           ; |sumaApx2/5 sumaRpx2/5 sumaGpx2/5 sumaBpx2/5|
    	divps xmm3, cincoFloat           ; |sumaApx3/5 sumaRpx3/5 sumaGpx3/5 sumaBpx3/5|
    	divps xmm4, cincoFloat           ; |sumaApx4/5 sumaRpx4/5 sumaGpx4/5 sumaBpx4/5|
    	divps xmm5, cincoFloat           ; |sumaApx5/5 sumaRpx5/5 sumaGpx5/5 sumaBpx5/5|

    	; Convertir de float a int (x4)
    	cvttps2dq xmm0, xmm2
    	cvttps2dq xmm1, xmm3
    	cvttps2dq xmm2, xmm4
    	cvttps2dq xmm3, xmm5

    	; Empaquetar sat de double a word (32 a 16 bits)
    	packusdw xmm0, xmm1   ; |Apx3T Rpx3T Gpx3T Bpx3T|Apx2T Rpx2T Gpx2T Bpx2T|
    	packusdw xmm2, xmm3   ; |Apx5T Rpx5T Gpx5T Bpx5T|Apx4T Rpx4T Gpx4T Bpx4T|
    	packuswb xmm0, xmm2   ; Empaquetar sat a 8 bits: |px5T|px4T|px3T|px2T|

    	movdqu [r13], xmm0    ; Guardar en memoria (no está alineda la pos)
    	
    	add r12, 4*px_size    ; avanzar 8 en imagen src
    	add r13, 4*px_size    ; avanzar 4 en imagen dst
		add r14, 4            ; avanzar el contador de fila 4 pos (está parado en el 6) - DEBUG: CHEQUEAR ESTE VALOR

		cmp r14, rdx          ; ver si llegó a width-2
		jne .cicloFilas0

	.finCicloFilas0:

	movq [r13], marco

	inc num_fila               ; avanzar fila
	mov rax, row_size          ; calcular offset de fila
	mul num_fila               ; res en rax
	mov rdx, cant_filas        ; si es una de las últimas 2 filas, saltar a filas blancas
	sub rdx, 2
	cmp num_fila, rdx
	je fin

	; FILAS MOD 4 = 1
	lea r12, [rdi+rax]         ; Calcular direccion de inicio de fila en src
	lea r13, [rsi+rax]         ; Calcular direccion de inicio de fila en dst
	xor r14, r14          ; Inicializar contador para ciclo fila

	movq [r13], marco
	add r13, 2*px_size             ; dst está 2 px adelantado respecto de src

	mov rdx, width
	sub rdx, 8

		.cicloFilas1:
		movdqa xmm0, [r12]      ; Cargar 8 px de memoria
		movdqa xmm1, [r12+4*px_size]
		movdqu [r13], xmm0      ; Moverlos a destino -> NO ALINEADO
		movdqu [r13+4*px_size], xmm1
		
		add r12, 8*px_size           ; Avanzar pos de memoria 4 pixeles
		add r13, 8*px_size
		add r14, 8                   ; Incrementar contador

		cmp r14, rdx       ; ver si terminó: si es así, saltar a fila siguiente
		jne .cicloFilas1

	movdqa xmm0, [r12]
	movdqu [r13], xmm0
	movq [r13+4*px_size], marco

	inc num_fila               ; avanzar fila
	mov rax, row_size          ; calcular offset de fila
	mul num_fila               ; res en rax
	mov rdx, cant_filas        ; si es una de las últimas 2 filas, saltar a filas blancas
	sub rdx, 2
	cmp num_fila, rdx
	je fin
	jmp ciclo

fin:
	;FILA WIDTH-2
	lea r13, [rsi+rax]      ; Calcular direccion de inicio de fila en dst
	xor r14, r14            ; Inicializar contador para ciclo fila
	mov rdx, width          ; copiar width en rdx (para poder modificarla)

		.cicloAnteultimaFila:
		movdqa [r13], marco
		movdqa [r13+4*px_size], marco
		add r13, 8*px_size      ; Avanzar pos de memoria 4 pixeles
		add r14, 8              ; Incrementar contador
		cmp r14, rdx
		jne .cicloAnteultimaFila

	inc num_fila
	mov rax, row_size          ; Si no, calcular offset de fila
	mul num_fila               ; res en rax
	;add r13, row_size
	
	;FILA WIDTH-1
	lea r13, [rsi+rax]         ; Calcular direccion de inicio de fila en dst
	xor r14, r14            ; Inicializar contador para ciclo fila
	mov rdx, width          ; copiar width en rdx (para poder modificarla)

		.cicloUltimaFila:
		movdqa [r13], marco
		movdqa [r13+4*px_size], marco
		add r13, 8*px_size      ; Avanzar pos de memoria 4 pixeles
		add r14, 8              ; Incrementar contador
		cmp r14, rdx
		jne .cicloUltimaFila

	pop r14
	pop r13
	pop r12
	pop rbx
	pop rbp
	ret