Mostrar_Mapa:   
    LD A, (IX)
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

    sla a       ; Multiplicamos por 8
    sla a
    sla a
    
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




   
