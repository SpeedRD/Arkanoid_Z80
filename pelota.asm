; ----------------------------------------------------------------------------------------
; Ball.
;
; The playfield IS the attribute file ($5800-$5AFF) and there is no background layer, so
; erasing the ball by writing 0 destroys whatever cell it was sitting on. That is why the
; ball used to chew holes through the bricks and the border without any collision code
; existing at all. This file therefore READS the attribute under the ball before drawing
; and writes that same byte back on erase.
;
; Position is 8.8 fixed point per axis. The whole part is the cell the ball occupies and
; lives in Coord; the fraction lives in CoordFrac. Velocity in Vector is signed 8.8 too.
; That is what lets the ball travel at angles other than 45 degrees while still advancing
; at most ONE cell per axis per frame -- so it can never step over a brick without
; touching it, and the range tests in classify_cell stay sound.
;
; Hard invariants:
;   * |velocity| on each axis must stay <= $0100 (one cell/frame), or the ball skips cells.
;   * the ROW velocity must never reach 0, or the ball never returns to the paddle.
; ----------------------------------------------------------------------------------------

; Byte 0 is the COLUMN and byte 1 is the ROW. `ld hl,(Coord)` puts byte 0 in L, and PosXY
; takes H as the row -- so the ball starts at row 20, column 16. The comment that used to
; sit here said "(fila, columna)", which is backwards, and the one on Vector said "(X, Y)"
; when byte 0 was the row delta.
Coord:      DB 16, 20       ; column, row -- the cell the ball occupies
CoordFrac:  DB 0, 0         ; sub-cell fraction, same order: column, row

Vector:     DW -256         ; ROW velocity,    8.8 signed. -256 = -1.00 cells/frame (up)
            DW  256         ; COLUMN velocity, 8.8 signed. +256 = +1.00 cells/frame (right)

NewRow:     DW 0            ; scratch: tentative row position this frame, 8.8
NewCol:     DW 0            ; scratch: tentative column position this frame, 8.8
BallSaved:  DB 0            ; the attribute that was under the ball before it drew

; ----------------------------------------------------------------------------------------
; ball - advance, resolve collisions, draw, wait, restore. One frame.
;   IN  - reads Coord, CoordFrac, Vector
;   OUT - updates them
;   Clobbers AF, DE, HL. Preserves BC, IX, IY.
; ----------------------------------------------------------------------------------------
ball:
        call step_ball          ; NewRow/NewCol = position + velocity
        call resolve_collisions ; bounce / destroy; re-steps if it flipped anything

        ; --- commit the resolved position ---
        ld a, (NewRow+1)
        ld (Coord+1), a
        ld a, (NewRow)
        ld (CoordFrac+1), a
        ld a, (NewCol+1)
        ld (Coord), a
        ld a, (NewCol)
        ld (CoordFrac), a

        ; --- draw, wait, restore ---
        ld hl, (Coord)          ; L = column, H = row
        call PosXY              ; HL = attribute address
        ld a, (hl)
        ld (BallSaved), a       ; whatever was here before the ball landed on it
        ld (hl), 8*7            ; white paper
        call Esperar_pelota     ; preserves HL
        ld a, (BallSaved)
        ld (hl), a              ; put it back -- NOT 0. This is the whole fix.
        ret

; ----------------------------------------------------------------------------------------
; step_ball - NewRow/NewCol = (Coord,CoordFrac) + Vector, one axis at a time.
;   Called again by resolve_collisions after a bounce, so the new position is always
;   derived from the CURRENT velocity rather than patched up afterwards.
;   Clobbers AF, DE, HL.
; ----------------------------------------------------------------------------------------
step_ball:
        ld a, (Coord+1)         ; row: H = whole, L = fraction
        ld h, a
        ld a, (CoordFrac+1)
        ld l, a
        ld de, (Vector)         ; row velocity
        add hl, de
        ld (NewRow), hl         ; NewRow = fraction, NewRow+1 = whole

        ld a, (Coord)           ; column
        ld h, a
        ld a, (CoordFrac)
        ld l, a
        ld de, (Vector+2)       ; column velocity
        add hl, de
        ld (NewCol), hl
        ret

;-------------------------------------------------------------------------------------------------

Esperar_pelota:
        push hl
        push af
        ld hl, $1100      ; Ajustar el tiempo de espera

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
