levelCounter: DEFB 0     ; Para contar los niveles que van pasando
CantidadNiveles: EQU 4

Juego:
    call dibujar_tablero
    call Mostrar_Mapa

Pala_Juego:
    call ball

    ; mirar si fin partida: el nivel termina cuando cae el ultimo ladrillo
    ; destructible. Se comprueba aqui, dentro del bucle de frame, y NO desde
    ; teclado: Fin_Juego no vuelve, asi que tiene que ser jp y no call.
    ld a, (bricks_left)
    or a
    jp z, Fin_Juego

    ; La pala ha fallado la bola. Igual que arriba: jp, nunca call.
    ld a, (ball_lost)
    or a
    jp nz, Ball_Lost

    call teclado
    call nuevaposicion
    call dibujarpala
    call esperar
    jr Pala_Juego


; ----------------------------------------------------------------------------------------
; Ball_Lost - una vida menos. Si quedan vidas se sirve otra bola en el mismo nivel, con
; los ladrillos como estaban; si no, se acaba la partida. Se entra aqui con jp desde el
; bucle de frame, asi que la pila sigue equilibrada.
; ----------------------------------------------------------------------------------------
Ball_Lost:
    xor a
    ld (ball_lost), a
    ld hl, lives
    dec (hl)
    jp z, Game_Over

    call reset_round     ; nueva bola y pala al centro; los ladrillos no se tocan
    jp Pala_Juego

; ----------------------------------------------------------------------------------------
; Game_Over - derrota. Es un camino DISTINTO de ReinicioJuego: aquel es la pantalla de
; partida COMPLETADA, a la que se llega contando cuatro cambios de nivel. Perder y ganar
; no son lo mismo y no comparten mensaje.
; ----------------------------------------------------------------------------------------
Game_Over:
    call reset_game
    jp Pantalla_GameOver

Fin_Juego:
    ld de, 1
    add ix, de           ; Sumamos a IX (maplist) para pasar al siguiente mapa

    ; Incrementar levelCounter
    ; OJO: el incremento va ANTES de comparar. Invertir el orden hace que tras el
    ; ultimo mapa se lea levelCounter y codigo ejecutable como si fueran datos de mapa.
    ld hl, levelCounter
    inc (hl)
    ld a, (hl)           ; Cargar el valor incrementado a levelCounter
    cp CantidadNiveles     ; Comparar con el numero maximo de niveles (4)
    jr z, ReinicioJuego  ; Si alcanzamos el maximo, ir a ReinicioJuego

    call reset_round     ; bola y pala al inicio para el nivel nuevo
    jr Juego             ; Continuar con el juego

ReinicioJuego:
    call reset_game      ; vidas, contador de nivel, bola y pala

    ; JP, no CALL, por lo mismo que flujo_juego -> Juego: Pantalla_Reinicio no vuelve
    ; nunca (acaba en jp flujo_juego), asi que con CALL se abandonaba la direccion de
    ; retorno en la pila -- medido: 2 bytes por partida completa. Ademas aqui no hay
    ; nada detras: Partida.asm se acaba en esta linea y lo siguiente en la imagen son
    ; los datos de pelota.asm, asi que si alguna vez volviera se ejecutarian Coord y
    ; Vector como si fueran codigo. Con jp eso es imposible por construccion.
    jp Pantalla_Reinicio


