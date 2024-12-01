levelCounter: DEFB 0     ; Para contar los niveles que van pasando
CantidadNiveles: EQU 4

Juego:
    call dibujar_tablero
    call Mostrar_Mapa

Pala_Juego:
    call posicionpala
    

Fin_Juego:
    ld de, 1             
    add ix, de           ; Sumamos a IX (maplist) para pasar al siguiente mapa

    ; Incrementar levelCounter
    ld hl, levelCounter
    inc (hl)             
    ld a, (hl)           ; Cargar el valor incrementado a levelCounter
    cp CantidadNiveles     ; Comparar con el numero maximo de niveles (4)
    jr z, ReinicioJuego  ; Si alcanzamos el maximo, ir a ReinicioJuego

    jr Juego             ; Continuar con el juego

ReinicioJuego:
    ld hl, levelCounter
    ld (hl), 0           ; Restablecer el contador a 0

    call Pantalla_Reinicio


