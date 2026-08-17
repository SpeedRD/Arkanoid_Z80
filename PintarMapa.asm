Mostrar_Mapa:
    LD A, (IX)
    ld (bricks_left), a   ; Byte 0 del mapa = numero de ladrillos destructibles.
                          ; Antes se leia aqui y se tiraba en la linea siguiente; es
                          ; exactamente el contador que necesita la deteccion de nivel
                          ; completado, asi que se guarda.
    INC IX

Fila:
    ld a, (IX)  ; Leemos Y
    INC IX

    ld B, a     ; Guardamos Y en B
    ld C, 1     ; Columna = 1
    call CalcularAtributo

    ld a, (IX)  ; Leemos numero de ladrillos en la fila
    INC IX
    ld B, a

    

Fila_Ladrillo:
    ld a, (IX)  ; Leemos color
    INC IX

    cp 8
    jr z, Color_Indestructible

    sla a       ; Multiplicamos por 8
    sla a
    sla a
    jr Pintar_Atributo

Color_Indestructible:
    ; Colour 8 << 3 would be $40 (BRIGHT set, paper 0, ink 0) -- bright black on
    ; black, invisible. $78 (BRIGHT, paper 7, ink 0) keeps the same paper-only
    ; convention as colours 1-7 but stays visible, and matches classify_cell's
    ; CELL_HARD check in colisiones.asm -- change one, change both.
    ld a, $78

Pintar_Atributo:
    ld (hl), a
    INC HL
    LD (HL), A
    INC HL

    DJNZ Fila_Ladrillo    ; Sigue hasta que termine la fila

    ld a, (IX)
    cp $FF                ; Si A es 255, va a Fin_Dibujo
    jr z, Fin_Dibujo

    
    jr Fila
    call Pala_Juego


Fin_Dibujo:  
    
    RET




   
