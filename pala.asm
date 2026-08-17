POSICION: DB 14,0
LONGITUDPALA EQU 7
COLORPALA EQU 2*8
CONTADOR EQU $03FF

dibujarpala:
        ld a,(POSICION+1)
        or a
        jr z, dibujarpala1
        ld c,0
        call dibujarpalacolor

dibujarpala1:
        ld a,(POSICION)
        ld c,COLORPALA
        call dibujarpalacolor
        ret

dibujarpalacolor:
        ld b,LONGITUDPALA
        ld hl, $5B00-32
        ld d,0
        ld e,a
        add hl, de

dibujarpalacolor1:
        ld(hl),c
        inc hl
        djnz dibujarpalacolor1
        ret
;----------------------------------------------------------------------------------------------------------------------------
teclado:
        ld d,0
teclado1:
        ld bc,$FDFE
        in a,(c)
        and $1F
        cp $1F  ;si no vale 1F es que algo han pulsado
        jr nz,teclado2
teclado_sigue:
        dec d
        jr nz,teclado1
        ld b,0
        ret
; La tecla "F" pasaba de nivel. Era un hook de depuracion de noviembre de 2024 que
; acabo siendo el unico modo de avanzar, y metia una llamada de logica de juego en
; el manejador de teclado: teclado hacia call Fin_Juego y Fin_Juego sale con jr Juego,
; abandonando dos direcciones de retorno en la pila en cada cambio de nivel. Ahora el
; nivel avanza solo, desde Partida.asm, cuando bricks_left llega a 0.
teclado2:
        bit 0, a ; Detectar tecla "A"
        jr nz,teclado3
        ld b, -1
        jr tecladofin
teclado3:
        bit 2, a ; Detectar tecla "D"
        ; Una tecla de esta media fila que no sea A ni D (o sea S, F o G) volvia aqui a
        ; teclado1 SIN decrementar D, asi que el bucle no terminaba nunca: mantener
        ; pulsada la S congelaba el juego entero -- bola y pala -- hasta soltarla. Y la S
        ; esta justo al lado de la A y la D. Ahora sigue contando como cualquier sondeo
        ; fallido, de modo que el bucle acaba y devuelve b=0.
        jr nz,teclado_sigue
        ld b, 1
tecladofin:
        nop     ;instruccion que pierde ciclos
        nop
        nop
        nop
        nop
        dec d
        jr nz,tecladofin 
        ret
;--------------------------------------------------------------------------------------------------------------------------
nuevaposicion:
        ld a,b
        or a
        ret z
        ld a,(POSICION)
        add b
        ret z
        cp 32-LONGITUDPALA
        ret nc
        ld b,a
        ld a,(POSICION)
        ld (POSICION +1),a
        ld a,b
        ld (POSICION),a
        ret
;----------------------------------------------------------------------------------------------------------------------------
esperar:
        ld bc,CONTADOR
esperar1:
        dec bc
        ld a,b
        or c
        jr nz,esperar1
        ret
;-------------------------------------------------------------------------------------------------
