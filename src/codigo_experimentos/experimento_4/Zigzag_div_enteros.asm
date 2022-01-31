section .rodata
ALIGN 16
marcoBlanco: times 16 db 0xFF
numParaMulDivPor5: times 8 dw 13108

section .text
global Zigzag_asm

Zigzag_asm:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    ; -- Parámetros de entrada --
    ; rdi <- *src
    ; rsi <- *dst
    ; edx <- width
    ; ecx <- height
    ; r8d <- row_size en bytes

    ; -- Uso de los registros de propósito general --
    ; rax y rdx quedan libres para operar:
    ;    - rax es usado para offsets de filas
    ;    - rdx para límite de los ciclos de fila (no siempre coincide con width)
    ; rbx contador de filas
    ; r12 puntero a fila src (src+offset correspondiente)
    ; r13 puntero a fila dst (dst+offset correspondiente)
    ; r14 contador de columnas (interno a filas)

    ; Trabajar con 64 bits para operar con memoria. No hay que extender:
    ; parte alta de rdx, rcx y r8d ya vienen en 0 por tener datos de 32 bits
    mov r9, rdx    ; mover width a rcx
    xor rbx, rbx   ; inicalizar contador para cantidad de filas (num_fila)

    %define ptr_src rdi
    %define ptr_dst rsi
    %define cant_filas rcx
    %define width r9
    %define row_size r8
    %define num_fila rbx
    %define px_size 4

    ; --- Máscaras ---
    movdqa xmm7, [marcoBlanco]
    %define marco xmm7
    movdqa xmm9, [numParaMulDivPor5]
    %define mulDivPor5 xmm9

    xor rax, rax                ; offset fila 0 para la primera fila

    filasBlancas:               ; marco: filas 0, 1, height-1, height-2
    lea r13, [rsi+rax]
    xor r14, r14                ; inicializar contador para ciclo fila

        .cicloFilasBlancas:
        movdqa [r13], marco
        add r13, 4*px_size      ; avanzar pos de memoria 4 pixeles
        add r14, 4              ; incrementar contador
        cmp r14, width
        jne .cicloFilasBlancas
    
    distribuidorFilas:
    inc num_fila               ; avanzar fila
    cmp num_fila, cant_filas   ; si se terminaron las filas, saltar a fin
    je fin                  
    mov rax, row_size          ; si no, calcular offset de fila
    mul num_fila               ; res en rax
    lea r12, [rdi+rax]         ; calcular direccion de inicio de fila en src
    lea r13, [rsi+rax]         ; calcular direccion de inicio de fila en dst

    ; Decidir a qué fila ir:
    cmp num_fila, 1            ; si todavía falta pintar la fila 1, saltar a filasBlancas
    je filasBlancas
    mov rdx, cant_filas        ; si es una de las últimas 2 filas, saltar a filas blancas
    sub rdx, 2
    cmp num_fila, rdx
    jge filasBlancas
    
    ; Calcular num_fila mod 4
    xor rax, rax               ; poner rax en 0
    add rax, 3                 ; sumarle 3 para hacer mascara: 0000 0000 0000 0003
    mov r14, num_fila          ; dejar solo últimos 2 bits de num_fila
    and rax, r14               ; poner resultado en rax
    cmp rax, 1                 ; si es 1, saltar a filas1
    je filas1
    cmp rax, 3                 ; si es 3, saltar a filas3
    je filas3
    jmp filasPares             ; si no, saltar a filasPares

    filasPares:
    xor r14, r14               ; inicializar contador interno a fila
    movq [r13], marco
    add r13, 2*px_size         ; avanzar 2 px en ptr a dst
    add r14, 2                 ; avanzar 2 px en el contador
    mov rdx, width             ; el ciclo termina al llegar a width-2
    sub rdx, 2

    movdqa xmm8, [r12]         ; cargar los primeros 4 de memoria
    add r12, 4*px_size         ; NOTA: src siempre está 4 pos adelantada

        .cicloFilasPares:
        movdqa xmm0, xmm8          ; | px3 | px2 | px1 | px0 |
        movdqa xmm1, [r12]         ; | px7 | px6 | px5 | px4 | -> en cada uno |A R G B|
        
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
        pxor xmm15, xmm15          ; registro con ceros
        movdqa xmm0, xmm10         ; xmm10 -> low xmm0 (px 0-1), high xmm10 (px 2-3)   (instruccion innecesaria, ya son iguales)
        punpcklbw xmm0, xmm15
        punpckhbw xmm10, xmm15

        movdqa xmm1, xmm11         ; xmm11 -> low xmm1 (px 1-2), high xmm11 (px 3-4)
        punpcklbw xmm1, xmm15
        punpckhbw xmm11, xmm15

        movdqa xmm2, xmm12         ; xmm12 -> low xmm2 (px 2-3), high xmm12 (px 4-5)
        punpcklbw xmm2, xmm15 
        punpckhbw xmm12, xmm15

        movdqa xmm3, xmm13         ; xmm13 -> low xmm3 (px 3-4), high xmm13 (px 5-6)
        punpcklbw xmm3, xmm15
        punpckhbw xmm13, xmm15

        movdqa xmm4, xmm14         ; xmm14 -> low xmm4 (px 4-5), high xmm14 (px 6-7);
        punpcklbw xmm4, xmm15
        punpckhbw xmm14, xmm15
  
        ; Sumar todo verticalmente (words):
        paddw xmm0, xmm1           ; parte baja: px 2 y 3
        paddw xmm0, xmm2
        paddw xmm0, xmm3
        paddw xmm0, xmm4           ; res en xmm0: |Suma px3|Suma px2|
        paddw xmm10, xmm11         ; parte alta: px 4 y 5
        paddw xmm10, xmm12
        paddw xmm10, xmm13
        paddw xmm10, xmm14         ; res en xmm10: |Suma px5|Suma px4|

        ; Sumas en xmm0 (px 2 y 3) y en xmm10 (px 4 y 5)  
        pmulhw xmm0, mulDivPor5    ; divide 8 words (entre 0 y 255*5) sin signo por 5
        pmulhw xmm10, mulDivPor5
        packuswb xmm0, xmm10        ; empaquetar sat a 8 bits: |px5T|px4T|px3T|px2T|

        movdqu [r13], xmm0          ; guardar en memoria (posición no alineada)
        
        add r12, 4*px_size          ; avanzar 8 en imagen src
        add r13, 4*px_size          ; avanzar 4 en imagen dst
        add r14, 4                  ; avanzar el contador de fila 4 pos

        cmp r14, rdx                ; ver si llegó a width-2
        jne .cicloFilasPares

    movq [r13], marco

    jmp distribuidorFilas

    filas1:
    ; IDEA GENERAL: Copiar src[i,j-2] --> a derecha.
    ; Agregar el marco y recorrer con el ptr a dst dos px adelantado
    ; Ciclar de a 4 hasta llegar a width-4 (contador va con src).
    ; Al final, pintar 2 px más de blanco

    xor r14, r14                 ; inicializar contador para ciclo fila

    movq [r13], marco
    add r13, 2*px_size           ; NOTA: dst está 2 px adelantado respecto de src

    mov rdx, width
    sub rdx, 4

        .cicloFilas1:
        movdqa xmm0, [r12]       ; cargar 4 px de memoria
        movdqu [r13], xmm0       ; moverlos a destino (posición no alineada)
        
        add r12, 4*px_size       ; avanzar pos de memoria 4 pixeles
        add r13, 4*px_size
        add r14, 4               ; incrementar contador

        cmp r14, rdx             ; ver si terminó: si es así, saltar a fila siguiente
        jne .cicloFilas1

    movq [r13], marco

    jmp distribuidorFilas

    filas3:
    ; IDEA GENERAL: copiar src[i,j+2] ---> a izquierda
    ; Ciclar de a 4 hasta llegar a width-2 (contador va con dst)
    ; Fin: guardar los 2 que quedan + el marco

    xor r14, r14                 ; inicializar contador para ciclo fila

    ; Recorrer src y dst con src adelantada dos posiciones: src+2*px_size
    add r12, 2*px_size           ; NOTA: src está 2 px adelantado respecto de dst
    mov rdx, width
    sub rdx, 4                   ; menos 6 del final y + 2 que adelanté

        .cicloFilas3:
        movdqu xmm0, [r12]      ; | px5 | px4 | px3 | px2 | (no alineada)
        cmp r14, 0              ; si son los primeros px de la fila, agregar el marco
        jne .seguir
        movdqa xmm1, marco      ; xmm1 -> | FFFF | FFFF | FFFF | FFFF |  
        psrldq xmm1, 8          ; agregar marco blanco en parte baja
        por xmm0, xmm1

        .seguir:
        movdqa [r13], xmm0      ; guardarlos en dst -> ALINEADO
        add r12, 4*px_size      ; avanzar pos de memoria 4 pixeles
        add r13, 4*px_size
        add r14, 4              ; incrementar contador

        cmp r14, rdx            ; comparar contador con width-6. Si es distinto, volver a cicloFila3
        jne .cicloFilas3        ; si es igual, seguir
    
    ; Cargar últimos 2 y llenar 2 posiciones restantes con blanco
    ; (ir dos hacia atras para no cargar posiciones inválidas)
    movdqa xmm0, [r12-2*px_size]       ; xmm0 -> | px size-1 | px size-2 | px size-3 | px size-4 |
    psrldq xmm0, 8                     ; | 0000 | 0000 | px size-1 | px size-2 |
    movdqa xmm1, marco                 ; xmm1 -> | FFFF | FFFF | FFFF | FFFF |  
    pslldq xmm1, 8                     ; agregar marco blanco (ya está en xmm15)
    por xmm0, xmm1                     ; parte baja del marco ya está en xmm1
    movdqa [r13], xmm0                 ; guardar px en memoria

    jmp distribuidorFilas

fin:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
