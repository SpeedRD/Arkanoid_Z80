;PROBLEMAS: 
        ;1 - La fila está a mitad de pantalla en vez de en la última por abajo
        ;El profe me dijo que lo hiciera con 8 bytes, pongo 5A (mitad pantalla), si pongo 5B ya se sale
                ;(33)
;IMPORTANTE:
        ;Tengo un problema con DeZog y al guardar los bits del teclado me los guardab al revés, por eso 
        ;en las (jr z, mueveizquierda) está puesto z y no nz
        ;alomejor al compilar en otro ordenador que le vaya bien el DeZog bien hay que cambiar eso

LONGPALA EQU 6                          ;define la longitud de la pala, podemos ajustarlo aquí
LIMITEDERECHO EQU 31 - LONGPALA         ;último pixel en el que puede dibujar la tabla
LIMITEIZQUIERDO EQU 1                   ;último pixel donde puede dibujar la tabla
COORD: DB 0                             ;Coordenadas por columnas de para la tabla

posicionpala:
        ld a, (32-LONGPALA) / 2         ;para que la tabla se dibuje a la mitad de la pantalla (columnas)
        ld (COORD), a                   ;guardamos la posicion en COORD
    
       
inicio:
        di                              ;disable interruptions
        ld sp,0                         ;set stack pointer to top of ram (RAMTOP)
        
                                                ;si todo son constantes el compilador de C te lo compila él mismo
          
       
        ld a, (COORD)                   ; Cargar la columna de la pala en A
        ld l, a                         ; Cargar la columna en L
        ld h, $5A                       ; Ajustar la fila de la pala
        ld b, LONGPALA                  ;cargar la longitud de la pala
        ld a,2*8                        ;cargamos color rojo en a
        call pintarpixel                ;llamamos a pintarpixel
        


;MOVER PALA ---------------------------------------------------------------------------------------------------------------------------


leerteclas:
        ld bc, $FDFE                    ;semifila donde esta la letra "A" y la "D"
        in a,(c)

        bit 0,a                         ;hay un problema en el dzog y me lo guarda negado, por eso en el siguiente ponemos "z" y no "nz"
        jr z, mueveizquierda            ;si "A" esta pulsanda se mueve a la izquierda

        bit 2,a                         ;hay un problema en el dzog y me lo guarda negado, por eso en el siguiente ponemos "z" y no "nz"
        jr z, muevederecha              ;si "D" esta pulsada se mueve a la derecha

        bit 3,a                         ;hay un problema en el dzog y me lo guarda negado, por eso en el siguiente ponemos "z" y no "nz"
        jr z, end                       ;si se pulsa "F" se acaba el juego

        jr leerteclas                   ;a no ser que se pulse "F" seguimos en el bucle
        

mueveizquierda:
        ld a,(COORD)                    ;cargamos la posicion
        cp LIMITEIZQUIERDO              ;comprobamos si está en el límmite izquierdo
        jr z, parademover               ;si está en el límite no movemos

        dec a                           ; reducimos la posicion
        ld (COORD),a                    ;guardamos la nueva posicion
        add a, l                        ; ajustamos la columna en base a COORD
        ld l, a                         ; establecemos la posición horizontal
        ld b, LONGPALA + 1              ; Cargar la longitud de la pala en B (ponemos +1 para que borre el pixel de la anterior posicion)
        CALL borrarpala                 ;borramos la anteior
        CALL pintarpala                 ;pintamos la nueva
        jr parademover                  ;detenemos el movimiento

muevederecha:
        ld a, (COORD)                   ; cargamos la posición actual de la pala
        cp LIMITEDERECHO              ; comprobamos si está en el límite izquierdo
        jr z, parademover               ; si está en el límite, no movemos
        ld b,LONGPALA                   ; cargamos la longitud de la pala 
        CALL borrarpala                 ; borramos la pala en la posición anterior
        inc a                           ; aumentamos la posición para mover a la izquierda
        ld (COORD), a                   ; guardamos la nueva posición
        ld l, a                         ; establecemos la posición horizontal


        
        CALL pintarpala                 ; pintamos la pala en la nueva posición
        jr parademover                  ; detenemos el movimiento
parademover:

        jr leerteclas                   ;volvemos al bucle principal      
borrarpala:
    call esperar
    ld a, (COORD)                       ; cargamos la posición de columna de la pala en a
    ld l, a                             ; cargamos columna en L
    
borrarpixel:
    ld (hl), 0                          ; escribimos color negro (0) en la posición actual
    inc l                               ; movemos a la siguiente posición en la fila
    dec b                               ; decrementamos b 
    jp nz, borrarpixel                  ; repetimos hasta borrar toda la pala   
    ret                                 ; volver a donde se la llamó

pintarpala:
 
    ld a, (COORD)                      ; cargamos la posición de la pala en A
    ld l, a                             ; cargamos columna en L
    
    ld b, LONGPALA                      ; cargamos la longitud de la pala en b
    ld a, 2*8                           ; cargamos el rojo (2 * 8)

pintarpixel:
    ld (hl), a                          ; dibujamos la posicion actual de la pala
    inc l                               ; movemos a la siguiente posición en la fila
    dec b                               ; decrementamos b (la longitud de la pala)
    jp nz, pintarpixel                  ; repetimos hasta dibujar toda la pala (que b sea 0)
    ret                                 ; Salir  y volver a donde se llamó

esperar:
        PUSH AF                         ;guardamos los valores 
        PUSH BC                         ;guardamos los valores
        LD BC, $2F00                    ;ponemos el número para que pierda tiempo en lo siguiente
;-------------------------------------------------------------------------------------------------

esperar1:                               ;perdemos tiempo en este bucle
        DEC C                           
        JR NZ, esperar1
        DEC B
        JR NZ,esperar1
        POP BC                          ;recuperamos los valores
        POP AF                          ;recuperamos los valores
        RET                             ;volvemos a donde se llamó


;-------------------------------------------------------------------------------------------------
end:
    call Pantalla_Reinicio