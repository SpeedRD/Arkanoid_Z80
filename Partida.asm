Juego:
    call dibujar_tablero
    call Mostrar_Mapa

Pala_Juego:
    call posicionpala
    

Fin_Juego:
    ld de, 1
    add ix, de

    ld a, (ix)
    cp 4                  ; Si estamos en el ultimo mapa, vamos a la pantalla final/reinicio
    jr z, ReinicioJuego
    jr Juego

ReinicioJuego:
    call Pantalla_Reinicio 

