        DEVICE ZXSPECTRUM48
	SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION
        org $8000               ; Programa ubicado a partir de $8000 = 32768

        di              ; Deshabilitar interrupciones
        ld sp,0         ; Establecer el puntero de pila en la parte alta de la memoria
        
;-------------------------------------------------------------------------------------------------
;Código del estudiante

        CALL Main_Pantalla    ;Pantalla de Titulo
empezar:
        CALL Pantalla_Ini

flujo_juego:

        ld ix, (maplist)

        ; JP, no CALL. Juego no vuelve nunca: Partida.asm no contiene ni un solo RET,
        ; y todas sus salidas son jp/jr a sitios que tampoco vuelven (Pantalla_Reinicio
        ; y Pantalla_GameOver acaban las dos en jp flujo_juego). Con CALL, la direccion
        ; de retorno se abandonaba en la pila en cada partida -- medido: 2 bytes por
        ; reinicio. El "jr flujo_juego" que habia aqui detras era inalcanzable por el
        ; mismo motivo.
        JP Juego

        INCLUDE "Pantalla_Inicio.asm"
        INCLUDE "L30.3 - printat.asm"
        INCLUDE "mensaje_inicio.asm"
        INCLUDE "pala.asm"
        INCLUDE "tablero.asm"
        INCLUDE "PintarMapa.asm"
        INCLUDE "Mapas.asm"
        INCLUDE "Partida.asm"
        INCLUDE "pelota.asm"
        INCLUDE "colisiones.asm"