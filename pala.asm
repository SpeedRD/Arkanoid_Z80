POSICION: DB 14,0
LONGITUDPALA EQU 4
COLORPALA EQU 2*8
CONTADOR EQU $01FF

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
        bit 0,a ;z=!A0
        jr nz,teclado3
        ld b,-1
        jr tecladofin
teclado3:
        bit 2,a
        jr nz,teclado1
        ld b,1
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
fin:            jr fin          ; Bucle infinito