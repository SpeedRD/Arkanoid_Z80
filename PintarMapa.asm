Mostrar_Mapa:   
    ld IX, map0
    LD A, (IX)
    INC IX

Fila:
    ld a, (IX)  ; Leemos Y
    INC IX
    cp $FF
    jr z, Fin

    ld B, a     ; Guardamos Y en B
    ld C, 1     ; Columna = 1
    call CalcularAtributo

    ld a, (IX)  ; Leemos numero de ladrillos en la fila
    INC IX
    ld B, a

    

Fila_Ladrillo:
    ld a, (IX)  ; Leemos color
    INC IX
    ;or a       ; Revisa si es 0
    ;jr z, Salto_Ladrillo  

    sla a       ; Multiplicamos por 8
    sla a
    sla a

    ;PUSH bc     ; Guardamos B (Fila), C (Ladrillos)
    ;PUSH de     ; D (Columna)

    
    ld (hl), a
    INC HL
    LD (HL), A
    INC HL      

    ;pop bc
    ;pop de

;Salto_Ladrillo:
    ;inc d   ; Mover a siguiente columna
    ;inc hl  ; Mover a siguiente color
    ;dec c

    DJNZ Fila_Ladrillo    ; Sigue hasta que termine la fila

    jr Fila


Fin:    
RET




   
