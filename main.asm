; Integrantes y porcentajes
; Alba Garcia Rivas -> 31%
; Eduardo Jose Cabreja Perez -> 38%
; Francisco Javier Zaballa Gutierrez -> 31%
; Jaime Fernandez Alonso -> 0%

        
        DEVICE ZXSPECTRUM48
	SLDOPT COMMENT WPMEM, LOGPOINT, ASSETION
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
        
        CALL Juego


        jr flujo_juego

        

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