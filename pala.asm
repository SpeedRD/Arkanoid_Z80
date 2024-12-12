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
        dec d
        jr nz,teclado1
        ld b,0
        ret
teclado2:
        bit 3, a ; Detectar tecla "F"
        jr nz,teclado3
        call Fin_Juego ; Llamar a Fin_Juego si se pulsa "F"
        ret
teclado3:
        bit 0, a ; Detectar tecla "A"
        jr nz,teclado4
        ld b, -1
        jr tecladofin
teclado4:
        bit 2, a ; Detectar tecla "D"
        jr nz,teclado1
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
