; ----------------------------------------------------------------------------------------
; Collisions.
;
; The ball is one attribute cell and moves at most one cell per axis per frame, so a
; collision is a cell lookup, not a box intersection. Everything here classifies the cell
; the ball is about to move into and reacts.
;
; Classification is BY POSITION FIRST, attribute second, because attribute values are
; ambiguous: $10 is both the paddle and a colour-2 brick, $38 is both the ball and a
; colour-7 brick, and $00 is both an empty cell and a destroyed one.
; ----------------------------------------------------------------------------------------

CELL_EMPTY      EQU 0       ; nothing there
CELL_BORDER     EQU 1       ; the frame drawn by dibujar_tablero
CELL_BRICK      EQU 2       ; destructible, colours 1-7
CELL_HARD       EQU 3       ; colour 8, indestructible (rendered as $78 -- PintarMapa.asm)
CELL_PADDLEROW  EQU 4       ; row 23, where the paddle lives

INITIAL_LIVES   EQU 3
BALL_START_ROW  EQU 20
BALL_START_COL  EQU 16
PADDLE_START    EQU 14      ; POSICION's own initial value

bricks_left:    DB 0        ; destructible bricks still standing. Loaded from the map's
                            ; byte 0 by Mostrar_Mapa; the level ends when it reaches 0.
lives:          DB INITIAL_LIVES    ; reset per GAME, never per level. The DB only runs
                            ; once per LOAD, so reset_game has to set it explicitly.
ball_lost:      DB 0        ; set when the paddle missed; the frame loop acts on it
cand_cell:      DW 0        ; the cell probe_cell last looked at: byte 0 = column, 1 = row
bounce_flags:   DB 0        ; bit 0 = row velocity flipped, bit 1 = column velocity flipped

; ----------------------------------------------------------------------------------------
; resolve_collisions - decide what the ball hit and bounce it.
;
; Three candidate cells, tested in this order. It is the standard resolution and it is what
; a player expects:
;     vertical   = (new row, old column)  -> flip the row velocity
;     horizontal = (old row, new column)  -> flip the column velocity
;     diagonal   = (new row, new column)  -> only when neither orthogonal cell was solid;
;                                            flip both. The corner clip is genuinely
;                                            ambiguous; this convention is deterministic
;                                            and symmetric, so it stays consistent.
;
; Two bricks CAN be destroyed in one frame (vertical and horizontal both hit). That is
; correct, and the counter is decremented twice.
;
; After any flip the position is re-derived by calling step_ball again, so the ball moves
; with the NEW velocity. That is also why a destroyed brick is never restored underneath
; the ball: the ball always ends up moving AWAY from whatever it just hit, so its final
; cell is never a cell this routine cleared.
;
;   IN  - NewRow/NewCol from step_ball, Coord = the cell the ball is leaving
;   OUT - Vector possibly changed, NewRow/NewCol re-derived
;   Clobbers AF, DE, HL. Preserves BC, IX.
; ----------------------------------------------------------------------------------------
resolve_collisions:
        xor a
        ld (bounce_flags), a

        ; ---- vertical candidate: (tentative row, current column) ----------
        ld a, (NewRow+1)
        ld h, a
        ld a, (Coord)
        ld l, a
        call probe_cell
        or a
        jr z, rc_horizontal             ; CELL_EMPTY
        cp CELL_PADDLEROW
        jr z, rc_paddle
        call destroy_if_brick
        call flip_row_velocity
        ld hl, bounce_flags
        set 0, (hl)
        jr rc_horizontal

rc_paddle:
        call paddle_hit                 ; sets both velocities when it catches
        ld hl, bounce_flags
        set 0, (hl)

rc_horizontal:
        ; ---- horizontal candidate: (current row, tentative column) --------
        ld a, (Coord+1)
        ld h, a
        ld a, (NewCol+1)
        ld l, a
        call probe_cell
        or a
        jr z, rc_diagonal
        call destroy_if_brick
        call flip_col_velocity
        ld hl, bounce_flags
        set 1, (hl)

rc_diagonal:
        ld a, (bounce_flags)
        or a
        jr nz, rc_restep                ; already resolved orthogonally

        ld a, (NewRow+1)
        ld h, a
        ld a, (NewCol+1)
        ld l, a
        call probe_cell
        or a
        ret z                           ; empty: the move stands, no re-step needed
        cp CELL_PADDLEROW
        jr z, rc_diag_paddle
        call destroy_if_brick
        call flip_row_velocity
        call flip_col_velocity
        jr rc_restep
rc_diag_paddle:
        call paddle_hit

rc_restep:
        jp step_ball                    ; re-derive position from the new velocity

; ----------------------------------------------------------------------------------------
; probe_cell - classify a candidate cell, remembering which cell it was so that
;              destroy_brick can find it again.
;   IN  - H = row, L = column
;   OUT - A = CELL_*, HL = the cell's attribute address
; ----------------------------------------------------------------------------------------
probe_cell:
        ld (cand_cell), hl              ; byte 0 = column (L), byte 1 = row (H)
        jp classify_cell

; ----------------------------------------------------------------------------------------
; classify_cell - what is at a cell?
;   IN  - H = row (0..23), L = column (0..31)
;   OUT - A = CELL_*, HL = that cell's attribute address
;   Clobbers AF, HL. Preserves BC, DE, IX.
;
; The tests are range comparisons (jr nc), not the exact-equality tests the ball used to
; use. Equality was only safe while the step was exactly +/-1; with fractional velocities
; that assumption is gone.
; ----------------------------------------------------------------------------------------
classify_cell:
        ld a, h
        cp 23
        jr nc, cc_paddlerow             ; row 23 or beyond: the paddle's row
        or a
        jr z, cc_border                 ; row 0: top border
        ld a, l
        or a
        jr z, cc_border                 ; column 0: left border
        cp 31
        jr nc, cc_border                ; column 31 or beyond: right border

        ; interior: now the attribute can be trusted, because position has already
        ; ruled out the paddle and the border.
        call PosXY
        ld a, (hl)
        or a
        ret z                           ; A = 0 = CELL_EMPTY
        cp $78                          ; colour 8's rendered attribute -- PintarMapa.asm
        jr z, cc_hard
        ld a, CELL_BRICK
        ret
cc_hard:
        ld a, CELL_HARD
        ret
cc_border:
        ld a, CELL_BORDER
        jp PosXY                        ; PosXY preserves AF
cc_paddlerow:
        ld a, CELL_PADDLEROW
        jp PosXY

; ----------------------------------------------------------------------------------------
; destroy_if_brick - clear the probed cell only if it was destructible.
;   IN  - A = the class probe_cell returned
;   Colour 8 (CELL_HARD) bounces the ball and is deliberately left alone. Get that wrong
;   and bricks_left never reaches zero, so the level never completes.
;   Clobbers AF, DE, HL.
; ----------------------------------------------------------------------------------------
destroy_if_brick:
        cp CELL_BRICK
        ret nz
        ; fall through

; ----------------------------------------------------------------------------------------
; destroy_brick - clear BOTH cells of the brick at cand_cell and count it once.
;
; A brick is 2 cells wide and entry i of a row occupies columns 1+2i and 2+2i. So an ODD
; column is the brick's LEFT cell and its partner is on the right; an EVEN column is the
; RIGHT cell and its partner is on the left. One brick, two cells, ONE decrement.
;   Clobbers AF, DE, HL.
; ----------------------------------------------------------------------------------------
destroy_brick:
        ld a, (cand_cell)               ; column
        ld l, a
        ld a, (cand_cell+1)             ; row
        ld h, a
        push hl
        call PosXY
        ld (hl), 0                      ; the cell the ball actually hit
        pop hl
        bit 0, l
        jr z, db_even
        inc l                           ; odd column  -> left cell  -> partner to the right
        jr db_partner
db_even:
        dec l                           ; even column -> right cell -> partner to the left
db_partner:
        call PosXY
        ld (hl), 0

        ld hl, bricks_left
        ld a, (hl)
        or a
        ret z                           ; already zero: never wrap round to 255
        dec (hl)
        ret

; ----------------------------------------------------------------------------------------
; paddle_hit - the ball reached row 23.
;
; POSICION byte 0 is the paddle's leftmost column, so the paddle spans
; POSICION .. POSICION+6 and subtracting gives the hit index 0-6: three cells left of
; centre, centre, three right. Where on the paddle the ball lands is what sets the rebound
; angle -- without that the player has no influence on the trajectory at all, and whether
; a level can be cleared would be fixed before anyone pressed a key.
;
;   IN  - NewCol+1 = the column the ball is heading for
;   Clobbers AF, DE, HL.
; ----------------------------------------------------------------------------------------
paddle_hit:
        ld a, (NewCol+1)                ; the column the ball is heading for
        ld hl, POSICION
        sub (hl)                        ; hit index = ball column - paddle left column
        cp LONGITUDPALA
        jr nc, ph_missed                ; unsigned, so this also catches "left of it"

        push af                         ; keep the index for the centre test below
        add a, a
        add a, a                        ; x4: each table entry is two 16-bit words
        ld e, a
        ld d, 0
        ld hl, rebound_table
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld (Vector), de                 ; row velocity, always upward
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)                      ; DE = column velocity from the table
        pop af

        cp 3                            ; dead centre?
        jr nz, ph_store
        ; The exact middle of the paddle keeps the ball's current horizontal direction
        ; rather than forcing one, so the centre cell is not arbitrarily biased one way.
        ld hl, (Vector+2)
        bit 7, h
        jr z, ph_store                  ; was moving right: the table entry is already +
        ld a, d                         ; was moving left: mirror it
        cpl
        ld d, a
        ld a, e
        cpl
        ld e, a
        inc de
ph_store:
        ld (Vector+2), de
        ret

ph_missed:
        ; The paddle was not under the ball: the ball is lost. The floor used to bounce
        ; unconditionally, which is precisely what made the game impossible to lose.
        ;
        ; Only a FLAG is set here. Jumping to a game-over screen from inside the ball's
        ; collision code would abandon everything already on the stack, which is the same
        ; mistake the old F key made (teclado called Fin_Juego, which never came back).
        ; The frame loop in Partida.asm reads the flag and acts, where it can do so
        ; without unbalancing anything.
        ld a, 1
        ld (ball_lost), a
        jp flip_row_velocity    ; bounce anyway, so this frame still ends somewhere legal

; ----------------------------------------------------------------------------------------
; reset_ball - back to the serve position, travelling up and to the right.
;   Clobbers AF, HL.
; ----------------------------------------------------------------------------------------
reset_ball:
        ld a, BALL_START_COL
        ld (Coord), a
        ld a, BALL_START_ROW
        ld (Coord+1), a
        xor a
        ld (CoordFrac), a
        ld (CoordFrac+1), a
        ; 45 degrees up and to the right, at the SAME magnitude as every rebound_table
        ; entry: |(-181,181)| = 256 = one cell per frame of travel. Serving at
        ; (-256,+256) instead would be |v| = 362, i.e. 41% faster than the ball can ever
        ; travel after touching the paddle, so it would visibly slow down for good on
        ; first contact.
        ld hl, -181
        ld (Vector), hl
        ld hl, 181
        ld (Vector+2), hl
        ret

; ----------------------------------------------------------------------------------------
; reset_round - ball and paddle back to their start positions.
;   Used on level change AND after losing a ball. Bricks and lives are left alone.
;   Nothing in this game reset anything before: a new level began with the ball wherever
;   it happened to be, and a second game started with everything where the first ended.
;   Clobbers AF, HL.
; ----------------------------------------------------------------------------------------
reset_round:
        call reset_ball
        ; Erase the paddle where it is RIGHT NOW, immediately, instead of recording a
        ; pending erase in POSICION+1 for dibujarpala to pick up later.
        ;
        ; POSICION+1 is a single-slot pending erase written by BOTH nuevaposicion and
        ; this routine, and consumed only by dibujarpala. On the frame a ball is lost
        ; the loop leaves via `jp Ball_Lost`, so dibujarpala never runs that frame --
        ; and on the next frame nuevaposicion overwrites POSICION+1 first, discarding
        ; the pending erase. The old paddle then stayed painted, and every later move
        ; only erased one column behind, so the leftovers survived on screen.
        ; Erasing here means a pending erase never has to survive a frame boundary.
        ld a, (POSICION)
        ld c, 0
        call dibujarpalacolor
        ld a, PADDLE_START
        ld (POSICION), a
        xor a
        ld (POSICION+1), a      ; nothing pending
        jp dibujarpala          ; ...and draw it at the centre now, so the paddle does
                                ; not blink out for a frame between erase and redraw

; ----------------------------------------------------------------------------------------
; reset_game - everything a brand-new game needs, including the bytes the loader only
;   ever initialises once.
;   Clobbers AF, HL.
; ----------------------------------------------------------------------------------------
reset_game:
        call reset_round
        ld a, INITIAL_LIVES
        ld (lives), a
        xor a
        ld (ball_lost), a
        ld (levelCounter), a
        ret

; ----------------------------------------------------------------------------------------
; flip_row_velocity / flip_col_velocity - negate one 16-bit signed 8.8 component.
;   Clobbers AF, HL.
; ----------------------------------------------------------------------------------------
flip_row_velocity:
        ld hl, (Vector)
        call negate_hl
        ld (Vector), hl
        ret

flip_col_velocity:
        ld hl, (Vector+2)
        call negate_hl
        ld (Vector+2), hl
        ret

negate_hl:
        ld a, h
        cpl
        ld h, a
        ld a, l
        cpl
        ld l, a
        inc hl
        ret

; ----------------------------------------------------------------------------------------
; Rebound angles, indexed by where on the 7-cell paddle the ball landed.
;
; Centre sends the ball steeply up, the edges send it out shallow and wide -- the classic
; Arkanoid feel. Both components are 8.8 fixed point, and the table obeys the two hard
; invariants: every row velocity is NON-ZERO (a horizontal ball never comes back and the
; game live-locks), and no magnitude exceeds $0100 = one cell per frame (or the ball skips
; cells and can pass straight through a brick).
; ----------------------------------------------------------------------------------------
; SPEED IS CONSTANT. Every entry has |v| = 256 +/- 1, i.e. exactly one cell per frame of
; travel, and reset_ball serves at the same magnitude. Only the DIRECTION varies.
;
; This is the whole point and it is easy to get wrong: a rebound must change where the
; ball is going without changing how fast it is going. The first version of this table
; varied from 250 to 286 and, worse, the serve was 362 (-1.00,+1.00 at 45 degrees) -- so
; the ball was launched 26-45% faster than any rebound could ever return it, and dropped
; to walking pace the instant it first touched the paddle, permanently. Wall and brick
; bounces only negate a component, so they preserve whatever magnitude they are given and
; the ball never recovered.
;
; 256 is the ceiling: no single component may exceed $0100 (one cell per axis per frame)
; or the ball skips cells, and the shallowest entries here are already at 222.
;
;                row velocity     column velocity    angle from vertical
rebound_table:
        DW -128  : DW -222          ; 0  far left     60 deg  -- shallow, hard left
        DW -181  : DW -181          ; 1               45 deg
        DW -222  : DW -128          ; 2               30 deg
        DW -248  : DW   64          ; 3  centre       14 deg  -- steep; sign follows the
                                    ;                            incoming ball
        DW -222  : DW  128          ; 4               30 deg
        DW -181  : DW  181          ; 5               45 deg
        DW -128  : DW  222          ; 6  far right    60 deg  -- shallow, hard right
