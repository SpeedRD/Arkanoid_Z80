LONGITUDPALA EQU 7                          ;define la longitud de la pala, podemos ajustarlo aquí
LIMITEDERECHO EQU 31 - LONGITUDPALA         ;último pixel en el que puede dibujar la tabla
LIMITEIZQUIERDO EQU 1                   ;último pixel donde puede dibujar la tabla
POSICION: DB 14,3                       ;variable para la posicion de la pala
COLORPALA EQU 2*8                       ;color de la pala
CONTADOR EQU $06FF                      ;ajustar para cambiar la velocidad de la pala
COORD: DB 0  

posicionpala:
        di                              ;disable interruptions
        ld sp,0                         ;set stack pointer to top of ram (RAMTOP)


        ld a, (POSICION)                   ; Cargar la columna de la pala en A
        ld l, a                         ; Cargar la columna en L
        ld h, $5A                       ; Ajustar la fila de la pala
        ld b,LONGITUDPALA                   ;cargar la longitud de la pala
        call pintarpala                ;llamamos a pintarpixel
        


;MOVER PALA ---------------------------------------------------------------------------------------------------------------------------


leerteclas:
        ld bc, $FDFE                    ;semifila donde esta la letra "A" y la "D"
        in a,(c)

        bit 0,a                         ;hay un problema en el dzog y me lo guarda negado, por eso en el siguiente ponemos "z" y no "nz"
        jr z, mueveizquierda            ;si "A" esta pulsanda se mueve a la izquierda

        bit 2,a                         ;hay un problema en el dzog y me lo guarda negado, por eso en el siguiente ponemos "z" y no "nz"
        jr z, muevederecha              ;si "D" esta pulsada se mueve a la derecha

        bit 3,a                         ;hay un problema en el dzog y me lo guarda negado, por eso en el siguiente ponemos "z" y no "nz"
        jr z, end                        ;si se pulsa "F" se acaba el juego

        jr leerteclas                   ;a no ser que se pulse "F" seguimos en el bucle
        

mueveizquierda:
    ld a, (POSICION)                ; Cargamos la posición actual de la pala
    cp LIMITEIZQUIERDO              ; Comprobamos si está en el límite izquierdo
    jr z, parademover               ; Si está en el límite, no movemos
    CALL borrarpala                 ; Borramos la pala en la posición anterior
    dec a                           ; Reducimos la posición
    ld (POSICION), a                ; Guardamos la nueva posición
    CALL pintarpala                 ; Pintamos la pala en la nueva posición
    CALL esperar                    ; Añadimos un retraso para reducir la sensibilidad
    jr parademover                  ; Salimos del movimiento

muevederecha:
    ld a, (POSICION)                ; Cargamos la posición actual de la pala
    cp LIMITEDERECHO                ; Comprobamos si está en el límite derecho
    jr z, parademover               ; Si está en el límite, no movemos
    CALL borrarpala                 ; Borramos la pala en la posición anterior
    inc a                           ; Aumentamos la posición
    ld (POSICION), a                ; Guardamos la nueva posición
    CALL pintarpala                 ; Pintamos la pala en la nueva posición
    CALL esperar                    ; Añadimos un retraso para reducir la sensibilidad
    jr parademover                  ; Salimos del movimiento

parademover:
        jr leerteclas                   ;volvemos al bucle principal      
;------------------------------------------------------------------------------------------------------------------------------
borrarpala:
    call esperar                        ; reduce la velocidad
    ld a, (POSICION)                    ; carga la posición de columna de la pala 
    ld d, 0                             ; Parte alta de DE a 0
    ld e, a                             ; carga posición de la columna 
    ld hl, $5B00-32                     ; direccion de la última fila
    add hl, de                          ; ajusta HL a la posición la pala
    ld b, LONGITUDPALA                  ; carga la longitud de la pala

borrarpixel:
    ld (hl), 0                          ; Escribir negro (0) en la posición actual
    inc hl                              ; Mover a la siguiente posición en la fila
    djnz borrarpixel                    ; Repetir hasta que B sea 0
    ret                                 ; Volver a la llamada

;------------------------------------------------------------------------------------------------------
pintarpala:
        ld a,(POSICION+1)               ;cargamos la siguiente posicion en a
        or a
        jr nz, pintarpala1              ;vamos a pinterapala1
        ld c,0                          ;cargamos el color negro
        call dibujarpalacolor           ;vamos a dibujarpalacolor

pintarpala1:
        ld a,(POSICION)                 ;cargamos la posicion de la pala en a
        ld c,COLORPALA                  ;cargamos el color de la pala
        call dibujarpalacolor           ;vamos a dibujarcolor
        ret                             ;volvemos a donde se llamó a la etiqueta

dibujarpalacolor:
        ld b,LONGITUDPALA               ;cargamos la longitud de la pala en b
        ld hl, $5B00-32                 ;en la última fila
        ld d,0                          ;cargamos el negro en d
        ld e,a                          ;cargamos la posicion en e
        add hl, de                      ;colocamos color y posicion

dibujarpalacolor1:
        ld(hl),c                        ;cargamos el color de la pala
        inc hl                          ;aumentamos hl
        djnz dibujarpalacolor1          ;repetimoshasta que esté pintada
        ret                             ;volvemos a donde se llamó a la función
;-------------------------------------------------------------------------------------------------
esperar:
        PUSH AF                         ;guardamos los valores 
        PUSH BC                         ;guardamos los valores
        LD BC, CONTADOR                 ;ponemos el contador para que se repita y pierda el tiempo establecido

esperar1:                               ;perdemos tiempo en este bucle
        DEC C                           
        JR NZ, esperar1
        DEC B
        JR NZ,esperar1
        POP BC                          ;recuperamos los valores
        POP AF                          ;recuperamos los valores
        RET                             ;volvemos a donde se llamó

;-------------------------------------------------------------------------------------------------
end:
    call Fin_Juego