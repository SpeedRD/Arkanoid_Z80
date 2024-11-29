dibujar_tablero:
    call CLEARSCR   ; Limpiar toda la pantalla

    ; Dibujar el borde izquierdo
    ld hl, $5800 + 0 * 32 + 0 ; Dirección de memoria de la pantalla para el borde izquierdo
    ld de, $0020              ; Posición vertical (Y)
    ld a, 1 * 8 + 7           ; Color del borde
    ld b, 24                  ; Número de filas del borde izquierdo

borde_izquierdo:
    ld (hl), a               ; Escribir el color en la pantalla
    add hl, de               ; Mover la posición a la siguiente fila
    djnz borde_izquierdo     ; Decrementar B y repetir hasta que B sea cero

    ; Dibujar el borde derecho
    ld hl, $5800 + 0 * 32 + 31 ; Dirección de memoria de la pantalla para el borde derecho
    ld de, $0020               ; Posición vertical (Y)
    ld a, 1 * 8 + 7            ; Color del borde
    ld b, 24                   ; Número de filas del borde derecho

borde_derecho:
    ld (hl), a               ; Escribir el color en la pantalla
    add hl, de               ; Mover la posición a la siguiente fila
    djnz borde_derecho       ; Decrementar B y repetir hasta que B sea cero

    ; Dibujar la parte de arriba
    ld hl, $5800 + 0 * 32 + 1 ; Dirección de memoria de la pantalla para la base
    ld a, 1 * 8 + 7            ; Color de la base
    ld b, 32               ; Número de columnas de la base

base:
    ld (hl), a              ; Escribir el color en la pantalla
    inc hl                   ; Mover la posición a la siguiente columna
    djnz base                ; Decrementar B y repetir hasta que B sea cero

    ret

fin_dibujar_tablero: jr fin_dibujar_tablero