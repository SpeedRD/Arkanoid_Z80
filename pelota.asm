Coord:  DB 16, 20
Vector: DB -1, 1

ball:
        ld hl, (Coord)
        call PosXY
        ld (hl), 8*7
        call Esperar_pelota
        ld (hl), 0
        ld hl, (Coord)
        ld a, (Vector)
        add h           ; A = A + H
        
        cp 24           ; A == 24?
        jr nz, seguir1
        ld a, (Vector)
        neg
        ld (Vector), a
        ld a, 22
        jr seguir2 
        
seguir1:
        cp -1
        jr nz, seguir2
        ld a, (Vector)
        neg
        ld (Vector), a
        ld a, 1
        
seguir2:       

        ld h, a
        ld a, (Vector + 1)
        add l
        
        cp 32           
        jr nz, seguir3
        ld a, (Vector + 1)
        neg
        ld (Vector + 1), a
        ld a, 30
        jr seguir4 
        
seguir3:
        cp -1
        jr nz, seguir4
        ld a, (Vector + 1)  ; Rebotar con el limite superior
        neg
        ld (Vector + 1), a
        ld a, 1
        
seguir4:       

        ld l, a
        ld (Coord), hl
        jr ball
        
        

;-------------------------------------------------------------------------------------------------

Esperar_pelota:
        push hl
        push af
        ld hl, $1f00

Bucle_esperar:
        dec hl
        ld a, h
        or l
        jr nz, Bucle_esperar
        pop af
        pop hl
        ret

PosXY:
        push af
        ld a, h
        sla a
        sla a
        sla a
        sla a
        sla a
        or l            ; A = A : L
        ld l, a
        ld a, h
        sra a
        sra a
        sra a
        or $58          ; A = A : $58
        ld h, a
        pop af
        ret