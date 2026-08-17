Pantalla_Ini:
    ld a, 6     ; Letra verde
    ld b, 23    ; Coordenadas para el mensaje de inicio, Fila
    LD c, 0     ; Columna
    ld ix, MensajeIniciar
    call PRINTAT

    ld b, 23                 ; Fila 
    ld c, 21                 ; Columna
    call CalcularAtributo    ; Calcular la dirección del atributo
    ld a,6+$80               ; Amarillo parpadeante
    ld (hl),a                ; Establecer el atributo

    call EsperarTecla        ; Leer el teclado hasta que se pulse S o N
    ret

Pantalla_Reinicio:
    call CLEARSCR

    ld a, 3               ; Letra azul
    ld b, 4               ; Coordenadas fila
    ld c, 4              ; Coordenadas columna
    ld ix, MensajeFinDeJuego 
    call PRINTAT  

    ld a, 6               ; Letra azul
    ld b, 14               ; Coordenadas fila
    ld c, 2              ; Coordenadas columna
    ld ix, MensajeReiniciar
    call PRINTAT 

    ld b, 14                 ; Fila 
    ld c, 30                 ; Columna
    call CalcularAtributo    ; Calcular la dirección del atributo
    ld a,6+$80               ; Amarillo parpadeante
    ld (hl),a                ; Establecer el atributo

    call EsperarTecla
    jp flujo_juego           ; jp, no call: flujo_juego no vuelve nunca

; ----------------------------------------------------------------------------------------
; Pantalla_GameOver - derrota, al quedarse sin vidas. Distinta de Pantalla_Reinicio, que
; es la de partida completada.
; ----------------------------------------------------------------------------------------
Pantalla_GameOver:
    call CLEARSCR

    ld a, 2                  ; Letra roja
    ld b, 8                  ; Coordenadas fila
    ld c, 11                 ; Coordenadas columna
    ld ix, MensajeGameOver
    call PRINTAT

    ld a, 6
    ld b, 14
    ld c, 2
    ld ix, MensajeReiniciar
    call PRINTAT

    ld b, 14                 ; Fila
    ld c, 30                 ; Columna
    call CalcularAtributo
    ld a,6+$80               ; Amarillo parpadeante
    ld (hl),a

    call EsperarTecla
    jp flujo_juego

FinDelJuego:
    call CLEARSCR

    ld a,2+$80               ; Letra roja
    ld b, 11                 ; Coordenadas Fila
    ld c, 11                 ; Coordenadas Columna
    ld ix,MensajeFinal
    call PRINTAT

    ; Aqui se caia directamente dentro de CalcularAtributo, cuyo RET consumia la
    ; direccion de retorno que habia dejado EsperarTecla, devolviendo el control al
    ; bucle de espera de tecla: pulsar "N" mostraba el adios y seguia jugando. El
    ; programa no tenia ningun estado de parada, asi que este es el unico sitio donde
    ; termina de verdad.
FinDelJuego_Parada:
    jr FinDelJuego_Parada

CalcularAtributo:
                        ; Rutina que recibe en B,C las coordenadas de la pantalla (fila, columna)
                        ; y devuelve en HL la dirección del atributo correspondiente
    PUSH AF             ; Guardamos A en el stack
    LD H,B              ; Los bits 4,5 de B deben ser los bits 0,1 de H
    SRL H : SRL H : SRL H
    LD A,B              ; Los bits 0,1,2 de B deben ser los bits 5,6,7 de L
    SLA A : SLA A : SLA A : SLA A : SLA a
    OR c                ; Y C son los bits 0-4 de L
    LD L,A
    LD BC, $5800        ; Le sumamos la dirección de comienzo de los atributos
    ADD HL,BC
    POP AF
    RET

EsperarTecla:
    call LeerTecla
    cp $1F              ; solo cuentan los 5 bits de teclas (ver SoltarTecla)
    jr nz,EsperarTecla  ; Esperar hasta que no haya tecla pulsada
    ret

LeerTecla:
    ld bc,$7FFE         ; Escanear línea B,N,M,SYMB,Space
    in a,(c)
    bit 3,a
    jr z,FinDelJuego    ; Han pulsado N
    ld bc,$FDFE         ; Escanear línea G,F,D,S,A
    in a,(c)
    bit 1,a             
    jr nz,LeerTecla     ; No han pulsado 'S'
    jr SoltarTecla

SoltarTecla:
    in a,(c)            ; Leer del puerto que se ha definido en LeerTecla
    ; Solo los bits 0-4 son teclas. Los bits 5-7 no son de teclado (bit 6 es
    ; EAR) y no se leen como 1 de forma fiable, asi que comparar el byte
    ; entero con $FF cuelga el menu para siempre. Enmascarar como en teclado
    ; (pala.asm:37-38).
    and $1F
    cp $1F              ; Comprobar que no hay tecla pulsada
    jr nz,SoltarTecla   ; Esperar hasta que no haya tecla pulsada
    ret


MensajeGameOver:  db "GAME OVER",0             ; Derrota: sin vidas
MensajeIniciar:   db "Quieres Jugar (S/N)? ",0  ; Mensaje para iniciar partida
MensajeFinal:     db "ADIOS!!!!",0         
MensajeFinDeJuego:  db "La partida ha finalizado",0        ; Mensaje de fin de juego
MensajeReiniciar: db "Quieres jugar otra partida?",0   ; Mensaje para reiniciar partida