---
name: collision-and-physics
description: Use when implementing anything in colisiones.asm — ball/brick or ball/paddle collision, brick destruction, rebound angle, lethal floor, lives, game over, or level-completion detection. Also read before changing pelota.asm's movement or bounce code, or before designing a new level, since level completability depends on the physics.
---

# Collision and physics — design guidance

This file is **design guidance, not an implementation**. All code below is **illustrative** — it
shows shape and intent, not lines to paste. `colisiones.asm` is still 0 bytes and that is the correct
state until the work below is done deliberately.

## 1. Where the game is now

- `colisiones.asm` is **empty**, and already `INCLUDE`d at `main.asm:35` — no build change needed.
- **Nothing reads `POSICION` from the ball code.** The ball has no idea the paddle exists.
- **The floor bounces unconditionally.** `pelota.asm:15-21`: tentative row 24 → negate the row delta,
  force row 22. **You cannot lose.** The paddle is decorative.
- **Bricks vanish, but nothing is colliding.** `pelota.asm:10` erases the ball by writing 0, and since
  the attribute file is the only layer, that write destroys the brick underneath. No bounce, no
  count, no destruction logic. → **memory-map-and-playfield** §2

## 2. Build order

Each step exists because the next one cannot be done without it.

| # | Step | Why it blocks the next |
|---|---|---|
| 1 | **Erase-restore** (§3) | While the ball's erase destroys whatever it touches, "is there a brick here?" has no reliable answer — the ball destroys the evidence before you can test it. **No collision logic can be written or trusted until this changes.** |
| 2 | **Fix the wall bounds, convert equality to range tests** (§4) | Keeps the ball off the border cells, so restore has something correct to restore instead of a border cell the ball should never have occupied. The range conversion also makes the tests robust rather than depending on the step being exactly ±1 — not because §6 needs a bigger step (it does not), but because a test that silently requires an invariant nobody stated is how the ball escapes the playfield. |
| 3 | **Ball↔brick** (§5) | Produces the decrementing counter that completion detection reads. |
| 4 | **Ball↔paddle with rebound angle** (§6) | Gives the player control over the trajectory. Must precede step 6 — see §7. |
| 5 | **Lethal floor, lives, game over** (§8) | Makes losing possible, without which completion detection is a demo that advances by itself. |
| 6 | **Automatic completion detection, retiring the F key** (§9) | Nothing depends on it, but it must not land before step 4. |

## 3. Erase-restore — the centrepiece

**The decided approach: before drawing the ball, read the attribute byte at the cell it is about to
occupy and save it; on erase, write that saved byte back instead of 0.**

Two reasons this is the right fix for the immediate need:

**(a) Minimal new state.** One byte, versus a parallel data structure that must be kept in sync with
the display forever.

**(b) The saved byte *is* the collision information.** It tells you **what** was there, not merely
that something was. The read that makes erasing safe is the same read that drives the collision
dispatch — the two problems collapse into one. That is the argument for this design, not just its
convenience.

### Which files this actually touches

**This work is not confined to `colisiones.asm`.** Be clear about that before you start, because the
rest of the library correctly tells you not to churn existing files:

| File | What must change |
|---|---|
| `pelota.asm` | **`ball` must be restructured.** Today it draws at the *current* cell, delays, erases, *then* moves (`:5-10`). The sequence below draws at the *target* cell after testing it. This is a rewrite of `ball`'s body, not a routine you can bolt on beside it. |
| `colisiones.asm` | New routines: cell read/classify, brick destruction, paddle rebound, and the new state bytes. |
| `Partida.asm` | The completion check at `:10` (§9). |
| `PintarMapa.asm` | **`Mostrar_Mapa` must stop discarding byte 0** (`:2-6`) and store it into the brick counter (§9). |

**One register fact you need and will not find elsewhere:** `ball` keeps the ball's *attribute
address* live in `HL` across the delay — `Esperar_pelota` pushes and pops `HL` (`pelota.asm:64,74`)
specifically so that `ld (hl),0` at `:10` can erase the cell it drew at `:8`. Any restore routine you
insert there must preserve `HL` or recompute the address via `PosXY`.

### Per-frame sequence

Order matters, and two orderings are wrong in ways that are easy to miss.

```
1. compute the target cell   (Coord + Vector, with the bounds handling of §4)
2. READ the attribute at the target cell        <- classification input
3. CLASSIFY it (see below) and act:
     - empty        -> nothing
     - border       -> bounce, do not destroy
     - brick 1-7    -> bounce, destroy, decrement counter, mark cell as now-empty
     - brick 8      -> bounce, do NOT destroy, do NOT decrement
     - paddle       -> paddle rebound (§6)
4. move the ball to its (possibly re-derived) new cell
5. DRAW the ball there, saving what step 2 read
6. delay
7. RESTORE: write the saved byte back
```

**The two ordering traps:**

- **The read must be against the cell the ball is about to occupy**, not the cell it is leaving. Read
  after moving and you have already lost the information.
- **A cell you just decided to destroy must not then be restored.** If you destroy a brick and then
  restore the saved brick attribute on erase, the brick comes back. On a destroy, the saved byte must
  be set to **0**, not to what was read.

### Classification — position, not colour

**memory-map-and-playfield** §4 has the full attribute table. The problem it exposes:

| Attribute | Could be |
|---|---|
| `$00` | empty cell **or** already-destroyed brick |
| `$10` | the paddle **or** a colour-2 brick (`2 << 3` = `$10`) |
| `$0F` | border |
| `$40` | colour-8 indestructible brick (invisible — bright black on black) |

**Attribute value alone is not a sufficient discriminator.** Use position first, attribute second:

```
if row == 23                      -> paddle row      (pala.asm:21)
else if row == 0 or col == 0 or col == 31  -> border (tablero.asm)
else if attribute == 0            -> empty
else if attribute == $40          -> indestructible brick
else                              -> destructible brick
```

Rows 3-18 are where the maps actually place bricks, and rows 19-22 are clear
(**map-data-format** §4) — but do not hard-code the brick rows. Position-first classification works
for any map.

**This is the same set of position tests as §4's detect/force table, and it must be written once.**
§4 decides *whether the ball may move into a cell*; this decides *what it hit*. Implement one
routine that answers both — a single "classify the target cell" call whose result drives the bounce
and the destruction — or you will double-handle every wall bounce.

### The shadow-map fallback — an informed option with a trigger

A shadow brick map — an authoritative grid in free RAM at `$5B00+`, with the attribute file as a pure
view of it — is **not** being kept open as a hedge. It is a specific answer to specific problems, and
you should revisit it if and only if one of these actually arrives:

- **Per-brick state beyond one attribute byte** is needed — the clearest case being multi-hit bricks,
  where an attribute byte cannot carry a hit counter.
- **The position-first classification rule stops being reliable** — for example if bricks are ever
  drawn on row 23, or the border geometry changes.
- **Brick lookup or counting cannot be done cheaply from the attribute alone** — e.g. if you need to
  scan for "are any destructible bricks left?" rather than maintaining a counter.

**Cost if adopted:** roughly one byte per brick cell (or a bitmap) in `$5B00+`, plus the permanent
obligation to keep it in sync with every write to the attribute file — a second source of truth is a
second thing to get wrong. **Benefit:** brick identity, count and state become unambiguous and
independent of what is drawn.

Until one of those triggers fires, the single saved byte is the design.

## 4. Wall bounds — and a correction to AUDIT.md

**AUDIT.md §5.3 is wrong about the forced values, and the code wins.** It claims the bounces force
the ball "2 away instead of 1" and that the ball "skips a cell on every bounce". Re-derived from
`pelota.asm:11-55`, that is not what happens.

Trace the bottom edge: the ball is at row 23 with row delta +1. `add h` gives tentative 24, `cp 24`
matches, the delta is negated to −1, and the row is forced to **22**. From row 23 with a delta of −1,
22 is exactly right. The sequence is `21, 22, 23, 22, 21` — a clean mirror, no skip, the wall row
occupied once. The same holds on all four edges. **The forced values are correct mirror reflections.**
(Forcing to 23 instead, as AUDIT.md suggests, would make the ball sit on row 23 for two consecutive
frames — that would be the stutter.)

**The real defect is different: the ball is allowed onto the border cells at all.** Rows 0 and 23 and
columns 0 and 31 are drawn by `dibujar_tablero`, and the ball reaches every one of them before
bouncing away — which is exactly what erases the border (§1, and **memory-map-and-playfield** §2).

The ball's playable interior is **rows 1-22, columns 1-30**, with row 23 reserved for the paddle. The
corrected detect/force pairs bounce one cell earlier:

| Edge | Wall at | Detect tentative | New delta | Force position | Resulting sequence |
|---|---|---|---|---|---|
| Top | row 0 | `== 0` | `+1` | row **2** | 3, 2, 1, 2, 3 |
| Left | col 0 | `== 0` | `+1` | col **2** | 3, 2, 1, 2, 3 |
| Right | col 31 | `== 31` | `−1` | col **29** | 28, 29, 30, 29, 28 |
| Bottom | row 23 = paddle | `== 23` | — | **paddle test (§6) or ball lost (§8)** | — |

Note the forced value is always `old ± 1` with the **new** delta applied — the same rule the current
code follows, just one cell further in.

### Equality → range

The four tests are exact equality (`cp 24`, `cp -1`, `cp 32`, `cp -1` at `pelota.asm:15,24,37,46`).
They are safe **only** while the step is exactly ±1. Convert them to range comparisons:

```asm
; illustrative — right edge, tentative column in A
    cp 31
    jr c, no_bounce_right      ; A < 31, still inside
    ; A >= 31: bounce
```

This conversion is a **prerequisite** for §6 and for any speed work.
**timing-and-frame-loop** §6 owns the rule that speed changes go into the delay constants, never into
the step size.

## 5. Ball↔brick

**Detection** is the read-back byte from §3, classified by position.

**Destruction must clear both cells.** A brick is 2 cells wide (**map-data-format** §4): entry `i` of
a row occupies columns `1 + 2i` and `2 + 2i`. Given the ball's column `c`, the partner cell is:

- `c` **odd** → the ball is on the brick's **left** cell → partner is `c + 1`
- `c` **even** → the ball is on the brick's **right** cell → partner is `c − 1`

(Check: `c=1` → brick 0 spans 1,2 → partner 2. `c=2` → brick 0 → partner 1. Correct.) That is a
single `bit 0, c` test.

Write 0 to both cells, and **decrement the remaining-brick counter exactly once** — one brick, not
two cells' worth.

**Only destructible bricks decrement.** Colour 8 (`$40`) bounces the ball and leaves the brick and
the counter alone. Get this wrong and the counter never reaches zero, so the level never completes.

### Bounce direction

A 1-cell ball moving diagonally has three candidate cells. Test them in this order — it is the
standard resolution and it produces the behaviour a player expects:

```
vertical   = (new_row, old_col)   -> if brick: flip row delta,    destroy
horizontal = (old_row, new_col)   -> if brick: flip column delta, destroy
diagonal   = (new_row, new_col)   -> only if neither of the above hit:
                                     flip both deltas, destroy
```

Two consequences worth stating plainly:

- **Two bricks can be destroyed in one frame** (vertical *and* horizontal). That is correct — decrement
  twice.
- **The pure-diagonal case is genuinely ambiguous** — the ball clips a corner with no orthogonal
  contact. The convention above (flip both, destroy the diagonal brick) is the recommended choice:
  it is deterministic, symmetric, and cheap. Pick it and stay consistent; do not let it vary by code
  path.

Three cell reads per frame is nothing against a ~32 ms budget (**timing-and-frame-loop** §3).

## 6. Ball↔paddle and rebound angle

The defining Arkanoid mechanic, and **entirely absent** today.

**The constraints you are working inside:** the paddle is 7 cells (`LONGITUDPALA`, `pala.asm:2`) on
row 23, positions are whole cells, `Vector` is two signed bytes, and the ball moves one cell per
frame.

**Impact zone:** `POSICION` byte 0 is the paddle's leftmost column (**state-and-register-contracts**
§1), so the paddle spans `POSICION .. POSICION+6`. Subtracting gives the hit index 0-6 — three cells
left of centre, centre, three right.

### The real difficulty, stated honestly

With integer `Vector` components of ±1, **there are only two column directions and therefore only two
angles.** "Rebound angle" cannot come from the existing representation at all. Something has to
change.

**Recommended: a fixed-point sub-cell accumulator.**

Give each axis a position in fractional units — e.g. 8.8 fixed point, one byte whole plus one byte
fraction — and a velocity in the same units. Each frame, add velocity to position; the **cell** the
ball occupies is the integer part.

```asm
; illustrative — one axis, 8.8 fixed point
;   ball_col_frac / ball_col   = position
;   vel_col_frac  / vel_col    = signed velocity
    ld a, (ball_col_frac)
    ld hl, vel_col_frac
    add a, (hl)
    ld (ball_col_frac), a      ; carry propagates into the whole part below
    ld a, (ball_col)
    ld hl, vel_col
    adc a, (hl)
    ld (ball_col), a
```

Why this is the right shape here:

- **The physical step stays at most one cell per axis per frame**, so the ball never skips a cell.
  That keeps collision detection sound (it cannot pass *through* a brick) and keeps the §4 range tests
  simple.
- **It gives a real range of angles** in both axes — steeper and shallower than 45° — driven by the
  hit index. Map hit index 0-6 to a set of velocity pairs, steepest at the centre, shallowest at the
  edges (or the reverse, whichever plays better; that is a tuning decision, not a design one).
- Cost: a few more bytes of state and two 16-bit adds per frame. Negligible against the frame budget.

**The alternative, and why it is a trap:** allowing `|dcol| = 2`. It is simpler, but it requires the
range-comparison conversion of §4 *first*, and — fatally — **it makes the ball skip cells**. A ball
stepping from column 10 to column 12 never occupies column 11, so it passes straight through a brick
there without ever colliding. You would then have to test the intermediate cells anyway, which is
strictly more work than the accumulator. **Do not take this route.**

**One hard invariant either way: the row velocity must never reach zero.** A ball travelling purely
horizontally never comes back to the paddle and the game hangs in a live-lock. Clamp the row
component away from zero when you compute the rebound.

## 7. The parity constraint — why §6 must land before §9

This is the subtlest thing in the library. Read it before designing a level or shipping completion
detection.

### The invariant

With `Vector` restricted to `(±1, ±1)`, every step changes the row by ±1 **and** the column by ±1. So
`row + col` changes by −2, 0 or +2 — always even. **`(row + col) mod 2` is invariant.** The ball
starts at row 20, column 16 (**state-and-register-contracts** §1), sum 36, even. It can therefore
occupy **only the even-parity half of the grid, permanently.**

### Does the 2-cell brick width rescue it?

**Mostly, and it is worth being precise about why.** A brick occupies columns `1+2i` and `2+2i`,
which differ by 1 — so its two cells have **opposite** parity. For any row, **every brick has exactly
one cell on the ball's reachable parity class.** So parity alone makes no brick unreachable, and
there are no single-cell bricks in this game to be parity-locked.

### The residual risk, which is worse

Parity is not the real hazard. **Determinism is.**

With a paddle that only mirrors the row delta and never changes the column delta, the ball's
direction set is just four values, and its trajectory is fully determined by its starting position
and the map. **The player has no influence on the ball's path whatsoever** — pressing A and D moves a
paddle that changes nothing about where the ball goes. Whether a given brick is ever reached is
decided *before the player touches a key*.

A 45° billiard path on a bounded grid is eventually periodic. Once the ball settles into its orbit,
any brick not on that orbit is unreachable **no matter how well the game is played**. Destroyed
bricks do perturb the geometry, which helps — but nothing in the design guarantees the orbit ever
covers the last remaining brick.

### What follows

**This does not matter today** — there is no completion detection, so nobody notices that some bricks
never get hit. **It becomes a hard bug the moment §9 lands**, because "clear all bricks" turns an
invisible geometric quirk into a level that cannot be finished and a game that cannot proceed.

> **Rule: rebound variety (§6) must land with or before completion detection (§9).** Variable rebound
> angle is what gives the player control over the trajectory, and control is what makes "clear the
> level" a solvable problem rather than a fixed property of the map.

### Checking a map for the hazard

Because the fixed-45° system is fully deterministic, you can check it exactly — no play required.
Simulate it: from the starting `Coord`/`Vector`, step the ball with the bounce rules of §4, marking
every cell visited, until the state `(row, col, drow, dcol)` repeats. Any brick with **neither** cell
in the visited set is unreachable, and any level containing one is uncompletable under fixed 45°.
`map2` (the staircase, with its wall of indestructible colour-8 bricks) and `map3` (the UFV logo,
with long isolated column runs) are the ones AUDIT.md §5.7 flags as likely candidates — worth
checking first. → **map-data-format** §9

## 8. Lethal floor, lives, game over

**Replace the unconditional floor bounce** (`pelota.asm:15-21`). When the ball's tentative row
reaches 23 (the paddle row):

- **paddle is under the ball** → rebound per §6.
- **paddle is not** → the ball is lost.

On loss: decrement a lives counter, and if lives remain, reset the round and continue.

**New state required** (declare per **state-and-register-contracts** §6 — inline `DB` in
`colisiones.asm`, explicitly initialised, never relied on from the loader):

- `lives` — reset on new **game** only, not on new level
- the round reset must set `Coord`, `Vector`, `POSICION` byte 0, and `POSICION` byte 1 back to its
  0 sentinel (otherwise the next `dibujarpala` erases a stale column)

**Note what does not exist today:** there is no reset routine at all. Nothing resets `Coord`,
`Vector` or `POSICION` between levels or between games, so a new level starts with the ball wherever
it was and a second game starts with everything where the first one ended
(**state-and-register-contracts** §5). This step is where that gets fixed, and the same routine
serves level change, ball loss and new game.

### Game over must be a distinct path

`ReinicioJuego` (`Partida.asm:32-36`) shows "La partida ha finalizado" and is reached by
`levelCounter` hitting `CantidadNiveles` — i.e. by **counting four level changes**. That is a
**completion** screen, not a defeat screen. A game over at zero lives means something different and
needs its own path and its own message.

**Do not reuse the existing quit path without fixing it first.** `FinDelJuego`
(`mensaje_inicio.asm:41-48`) prints "ADIOS!!!!" and then **falls straight through into
`CalcularAtributo`** at `:52`. `CalcularAtributo` ends in `RET`, which consumes the return address
left by `EsperarTecla`'s `call LeerTecla` (`LeerTecla` *jumps* to `FinDelJuego` at `:77` rather than
calling it) — so control lands back inside the key-wait loop. The goodbye screen silently keeps
polling, and pressing "S" afterwards starts a new game. **Pressing N does not quit.**
→ **failure-patterns** §12

## 9. Completion detection

**The counter already exists in the data.** Byte 0 of every map is the destructible-brick count —
independently verified as 82 / 71 / 78 / 153 and correct for all four maps
(**map-data-format** §2). `Mostrar_Mapa` reads it into `A` at `PintarMapa.asm:2` and discards it at
`:6`.

The mechanism: **store it in a RAM counter at level start, decrement once per destroyed destructible
brick (§5), advance the level at zero.**

Capturing it means **editing `Mostrar_Mapa`** — insert an `ld (bricks_left),a` between
`PintarMapa.asm:2` and the `ld a,(IX)` at `:6` that currently overwrites `A`. That is a two-line
change to a file the rest of this library otherwise only describes; it is expected and correct.

### Where it goes — and where it must not

**Put the check at `Partida.asm:10`**, the `;mirar si fin partida` comment inside the frame loop.
That is where it can test a counter and return normally.

**Do not follow the existing pattern.** Today the level advance is invoked from the keyboard handler:
`teclado` does `call Fin_Juego` (`pala.asm:47`) and `Fin_Juego` exits via `jr Juego`
(`Partida.asm:30`), abandoning two return addresses on the stack every single level change
(**state-and-register-contracts** §4). Reusing that path for automatic completion means leaking on
every level, forever.

**Retire the F key** (`pala.asm:44-48`) once this works. Per **failure-patterns** it is a debug hook
from November 2024 that became the only level-advance mechanism by accident; it has no place in a
finished game.

**Reset on level change:** the new map's brick count into the counter, plus `Coord`, `Vector` and
`POSICION` (§8). Lives carry over.

## 10. Before you write collision code

- [ ] Is erase-restore (§3) in and working? If not, stop — nothing else can be trusted.
- [ ] Does your classification use **position first**, not attribute value? (`$10` is both paddle and
      colour-2 brick.)
- [ ] On destroy, are you saving **0** rather than the brick attribute, so it does not come back?
- [ ] Are you clearing **both** cells of a brick, and decrementing **once**?
- [ ] Does colour 8 bounce without decrementing?
- [ ] Are the wall tests **range** comparisons, and does the ball stay in rows 1-22 / columns 1-30?
- [ ] Is the physical step still at most one cell per axis per frame?
- [ ] Can the row velocity ever become zero? (It must not.)
- [ ] Does every new routine preserve **`IX`**? (**state-and-register-contracts** §2)
- [ ] Are you using `jp`, not `call`, for anything that jumps back into the main loop?
- [ ] Is completion detection at `Partida.asm:10`, not in `teclado`?
- [ ] Have you checked your levels for reachability (§7)?

## 11. What not to do

Every item here is a mistake this codebase has already made or is one edit away from.

- **Do not build collision on the current erase strategy.** It destroys the evidence.
- **Do not increase ball speed via step size.** → **timing-and-frame-loop** §6
- **Do not ship completion detection before rebound variety.** → §7
- **Do not put game-logic calls in `teclado`.** That is how the F key and the stack leak happened.
- **Do not reuse `FinDelJuego`** without fixing the fall-through at `mensaje_inicio.asm:48→52`.
- **Do not add a debug key "just to test"** without a removal plan. That is precisely the origin of
  the F key. → **failure-patterns**
- **Do not leave `colisiones.asm` empty-but-included as a marker of intent.** That is what
  `MapaJuego.asm` was, and it was deleted having never had content.
- **Do not add score or a HUD.** Out of scope — a reasonable later addition, but do not design the
  brick counter around a display that does not exist. (For the record: grep finds no `vida`, `lives`,
  `score`, `punt` or `marcador` anywhere in the sources, so *neither* lives nor scoring has any
  precedent in the code. Lives are in scope because they were asked for, not because the history
  implies them.)
