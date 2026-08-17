---
name: collision-and-physics
description: Use when implementing anything in colisiones.asm — ball/brick or ball/paddle collision, brick destruction, rebound angle, lethal floor, lives, game over, or level-completion detection. Also read before changing pelota.asm's movement or bounce code, or before designing a new level, since level completability depends on the physics.
---

# Collision and physics

This file **describes the implementation**, and keeps the reasoning that constrains any change to
it. It used to be forward-looking design guidance for an empty `colisiones.asm`; that work is done.

## 1. Where the game is now

`colisiones.asm` is 408 lines and holds the core of the game: cell classification, bounce resolution,
brick destruction, the paddle rebound angle, the lives/loss path, and the three reset routines.
`pelota.asm` owns the ball's motion and its draw/erase. Everything below is covered by
`tests/test_pelota.py` and `tests/test_colisiones.py`.

## 2. The per-frame sequence

`ball` (`pelota.asm`) runs once per frame:

```
1. step_ball          NewRow/NewCol = (Coord,CoordFrac) + Vector, per axis
2. resolve_collisions classify up to three candidate cells, bounce, destroy,
                      and re-run step_ball if any velocity changed
3. commit             Coord/CoordFrac = NewRow/NewCol
4. draw               read the attribute at the ball's cell into BallSaved, write $38
5. Esperar_pelota     ~32 ms busy-wait (preserves HL)
6. restore            write BallSaved back -- NOT 0
```

**Step 6 is the whole erase-restore fix.** The playfield is the attribute file with no background
layer, so writing 0 there does not "remove the ball", it paints the cell black and destroys whatever
was under it. That is why the ball used to leave a trail of holes through the bricks and chew gaps in
the border *with no collision code existing at all*.
→ **memory-map-and-playfield** §1

`tests/test_pelota.py` asserts the consequence directly: on an empty playfield the attribute file is
**byte-identical after 200 completed frames**. That single check is the pass/fail signal for this
mechanism; if it ever fails, nothing downstream can be trusted.

### Why a destroyed brick is never restored

The obvious trap is destroying a brick and then writing the saved brick attribute back on erase,
which resurrects it. It does not arise here, and the reason is structural rather than lucky: the ball
always ends up moving **away** from whatever it just hit, because `resolve_collisions` flips the
velocity and then re-derives the position with `step_ball`. Its final cell is therefore never a cell
it just cleared. Keep that property if you restructure this.

## 3. Position and velocity are 8.8 fixed point

| Variable | Bytes | Meaning |
|---|---|---|
| `Coord` | 2 | byte 0 = **column**, byte 1 = **row** — the cell the ball occupies |
| `CoordFrac` | 2 | sub-cell fraction, same order: column, row |
| `Vector` | **4** | `Vector` = row velocity (signed 8.8), `Vector+2` = column velocity |

`Vector` used to be two bytes of ±1. It is four bytes now, because with integer ±1 components there
are only two column directions and therefore only two angles — "rebound angle" could not come from
that representation at all.

The whole part and the fraction sit in `H` and `L` of one register pair, so a step is just
`add hl,de` with a two's-complement `DE`, and the new cell is `H`.

**Three hard invariants, all asserted in the tests:**

- **`|velocity| ≤ $0100` on each axis** — one cell per frame. Exceed it and the ball skips cells: a
  ball stepping from column 10 to 12 never occupies 11, so it passes straight through a brick there
  without colliding.
- **The row velocity must never reach 0.** A ball travelling purely horizontally never comes back to
  the paddle and the game live-locks.
- **The velocity MAGNITUDE must be the same everywhere — `|v| = 256`.** A bounce changes *direction*,
  never *speed*. This applies to the serve (`reset_ball`), the inline `Vector` declaration in
  `pelota.asm`, and every entry of `rebound_table`. Wall and brick bounces only negate a component,
  so they preserve whatever magnitude they are handed.

> **This third invariant was missing from this document, and that omission is what caused the bug.**
> The original design was written up with the first two only. The rebound table was then built to
> satisfy exactly those — every component ≤ 256, every row velocity non-zero — while quietly ranging
> from `|v|` 250 to 286, and the ball was served at `(-256,+256)`, `|v|` = **362**. So the ball
> launched 41% faster than any rebound could ever return it and dropped to walking pace for good on
> first contact with the paddle. Players described it as "erratic, inconsistent speed". Nothing was
> wrong with the fixed-point arithmetic; the *values* were wrong, in a way the written design did not
> forbid.
>
> The ceiling is what makes this non-obvious: `|v|` cannot simply be raised to 362 for every angle,
> because a shallow rebound would then need a column component of 324, which breaks invariant one.
> **256 is the largest magnitude every angle in the table can actually reach.** If you want the ball
> faster, shorten the delay — → **timing-and-frame-loop** §6.

**A flooring asymmetry that looks like a bug and is not:** the cell index is `floor(position)`, so
from row 10.0 a velocity of −0.25 lands on 9.75 — already cell 9, on the very first frame — while
from column 15.0 a velocity of +0.25 takes four frames to reach cell 16. Both are correct. The
property that matters is that neither axis ever moves more than one cell in a frame.

## 4. Wall bounds

The ball's playable interior is **rows 1-22, columns 1-30**, with row 23 reserved for the paddle. It
never occupies a border cell, which is why the border no longer erodes.

There is no separate wall-bounce code: `classify_cell` returns `CELL_BORDER` for row 0, column 0 and
column 31, and `resolve_collisions` bounces off it exactly as it bounces off a brick. One mechanism,
not two.

The tests are **range comparisons** (`jr nc`), not the exact-equality tests (`cp 24`, `cp 32`) the
ball used to use. Equality was safe only while the step was exactly ±1; with fractional velocities
that assumption is gone, and a test that silently requires an invariant nobody stated is how the ball
escapes the playfield.

Observed geometry, one cell in from each wall:

| Edge | Ball at | Tentative | Result |
|---|---|---|---|
| Top | row 1, dy −1 | row 0 | dy → +1, ball to row 2 |
| Left | col 1, dx −1 | col 0 | dx → +1, ball to col 2 |
| Right | col 30, dx +1 | col 31 | dx → −1, ball to col 29 |
| Bottom | row 22, dy +1 | row 23 | paddle test (§6) |

> **AUDIT.md §5.3 was wrong about this and the point is now moot.** It claimed each bounce forced the
> ball 2 cells in instead of 1 and so "skipped a cell". The forced values were correct mirror
> reflections — the detection fires on the *tentative* value. Implementing its "Should be" column
> would have parked the ball on the wall for two frames, creating the stutter it described. The real
> defect was that the ball was allowed onto the border cells at all, and that is what was fixed.

## 5. Classification — position first, attribute second

```asm
CELL_EMPTY EQU 0 / CELL_BORDER EQU 1 / CELL_BRICK EQU 2
CELL_HARD  EQU 3 / CELL_PADDLEROW EQU 4
```

`classify_cell` takes `H` = row, `L` = column and returns the class in `A` and the cell's attribute
address in `HL`. It preserves `BC`, `DE` and **`IX`**.

Attribute value alone is **not** a sufficient discriminator, and this is worse than it first looks:

| Attribute | Could be |
|---|---|
| `$00` | empty cell **or** already-destroyed brick |
| `$10` | the paddle **or** a colour-2 brick |
| `$38` | **the ball** **or** a colour-7 brick — and colour 7 is the commonest brick colour here |
| `$0F` | border |
| `$40` | colour-8 indestructible brick (invisible — bright black on black) |

So position is tested first, and only once row 23, row 0 and columns 0/31 are ruled out is the
attribute consulted. This is why bricks may not be drawn on row 23 without revisiting the rule.

## 6. Ball↔brick and ball↔paddle

**Bounce resolution.** Three candidate cells, in this order:

```
vertical   = (new row, old column)  -> flip the row velocity
horizontal = (old row, new column)  -> flip the column velocity
diagonal   = (new row, new column)  -> only if neither orthogonal cell was solid; flip both
```

The pure-diagonal case is genuinely ambiguous — the ball clips a corner with no orthogonal contact.
Flipping both and destroying the diagonal brick is deterministic, symmetric and cheap; it is the
convention, and it must not vary by code path.

**Two bricks can be destroyed in one frame** (vertical *and* horizontal). That is correct, and the
counter is decremented twice.

**Destruction clears both cells.** A brick is 2 cells wide and entry `i` of a row occupies columns
`1+2i` and `2+2i`, so an **odd** column is the brick's left cell (partner on the right) and an
**even** column is its right cell (partner on the left) — a single `bit 0,l`. One brick, two cells,
**one** decrement. `bricks_left` is floored at 0 so it can never wrap to 255.

**Colour 8 bounces and is never destroyed or counted.** Get that wrong and `bricks_left` never
reaches zero, so the level never completes.

**Paddle rebound.** `POSICION` byte 0 is the paddle's leftmost column, so the paddle spans
`POSICION .. POSICION+6` and subtracting gives the hit index 0-6. The index is taken from the column
the ball is **heading for**, not the one it is leaving — a detail that is easy to get wrong when
writing tests. `rebound_table` maps the index to a velocity pair:

| Index | 0 | 1 | 2 | 3 (centre) | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| row | −128 | −181 | −222 | −248 | −222 | −181 | −128 |
| column | −222 | −181 | −128 | ±64 | +128 | +181 | +222 |
| angle from vertical | 60° | 45° | 30° | 14° | 30° | 45° | 60° |
| **\|v\|** | 256 | 256 | 256 | 256 | 256 | 256 | 256 |

Steep at the centre, shallow and wide at the edges — and **the same speed at every index**. Dead
centre keeps the ball's existing horizontal direction rather than forcing one, so the middle cell is
not arbitrarily biased.

`reset_ball` serves at `(−181, +181)`, the same magnitude, 45° up and to the right. So does the
inline `Vector` declaration in `pelota.asm` — and that one is easy to forget, because inline data is
initialised **once per LOAD**, so it is what the very first ball of a fresh session flies at,
long before `reset_ball` ever runs.

## 7. Why rebound variety had to land WITH completion detection

This is the subtlest constraint in the library, and it still governs level design.

With `Vector` restricted to `(±1,±1)`, every step changed row and column by exactly 1, so
`(row + col) mod 2` was invariant and the ball could reach only one parity class of cells. Bricks are
2 cells wide and their two cells have opposite parity, so parity alone stranded no brick.

**Parity was never the real hazard. Determinism was.** With a paddle that only mirrors the row delta,
the ball's direction set is four values and its trajectory is fully determined by its starting
position and the map — **the player has no influence on the ball's path at all**. A 45° billiard path
on a bounded grid is eventually periodic, so any brick off that orbit is unreachable no matter how
well the game is played. That is invisible while nothing checks for completion, and becomes an
unfinishable level the moment "clear all bricks" is the win condition.

Variable rebound angle is what makes "clear the level" a solvable problem rather than a fixed
property of the map. **If you ever flatten the rebound table back to a single angle, you reintroduce
this.**

Note what the tests do **not** prove: that any given level is completable. They prove the mechanism,
not the geometry.

## 8. Lethal floor, lives, game over

`paddle_hit` on a miss sets `ball_lost` and bounces; it does **not** jump anywhere. The frame loop in
`Partida.asm` reads the flag:

```
Pala_Juego: call ball
            bricks_left == 0 ?  -> jp Fin_Juego
            ball_lost ?         -> jp Ball_Lost
            teclado / nuevaposicion / dibujarpala / esperar / loop
```

**Everything that leaves the frame loop uses `jp`, never `call`.** Jumping to a screen from inside
the ball's collision code would abandon everything on the stack — which is exactly the mistake the
old F key made: `teclado` did `call Fin_Juego`, and `Fin_Juego` exits via `jr Juego`, leaking two
return addresses per level change, forever.

`Ball_Lost` decrements `lives`, and either `reset_round`s and keeps playing the same level with the
bricks as they are, or falls to `Game_Over`.

**Game over is a distinct path.** `ReinicioJuego` shows "La partida ha finalizado" and is reached by
`levelCounter` hitting `CantidadNiveles` — that is a **completion** screen, reached by counting four
level changes. `Pantalla_GameOver` prints "GAME OVER" at row 8. Losing and winning are not the same
event and do not share a message. `checklist.py` asserts both, and asserts each one does *not* print
where the other does.

`FinDelJuego` (the "N, I don't want to play" path) used to fall straight through into
`CalcularAtributo`, whose `RET` consumed the return address `EsperarTecla` had left, dropping control
back into the key-wait loop — so pressing N showed the goodbye screen and silently carried on
playing. It now ends in `FinDelJuego_Parada: jr FinDelJuego_Parada`, the program's only real stop.

## 9. Completion detection

Byte 0 of every map is the destructible-brick count — 82 / 71 / 78 / 153, verified against the data.
`Mostrar_Mapa` stores it into `bricks_left` (it used to read it into `A` and immediately overwrite
it). The frame loop advances the level when it reaches 0.

**The check lives at `Partida.asm`'s `;mirar si fin partida` point**, inside the frame loop, where it
can act without unbalancing the stack. It is emphatically **not** in `teclado`.

The F key is retired. Per **failure-patterns** it was a debug hook from November 2024 that became the
only level-advance mechanism by accident.

`Fin_Juego` calls `reset_round` before re-entering `Juego`; `ReinicioJuego` calls `reset_game`. Lives
carry across levels and reset per game.

## 10. The reset routines

| Routine | Resets | Leaves alone |
|---|---|---|
| `reset_ball` | `Coord`, `CoordFrac`, `Vector` | everything else |
| `reset_round` | the above, plus the paddle: erases it, re-centres it, redraws it | `bricks_left`, `lives` |
| `reset_game` | the above, plus `lives`, `ball_lost`, `levelCounter` | — |

**`reset_round` erases and redraws the paddle ITSELF, and leaves `POSICION+1` at 0.** It must not
defer that erase, and this is the second bug this file has had to record:

`POSICION+1` is a single-slot "pending erase" — written by `nuevaposicion` *and* by `reset_round`,
consumed only by `dibujarpala`. Nothing guarantees the consumer runs between two producers, and on
the one frame that matters it does not: **the frame a ball is lost leaves `Pala_Juego` via
`jp Ball_Lost`, so `dibujarpala` never runs that frame.** `reset_round` used to record the pending
erase there, and on the next frame `nuevaposicion` — which runs first — overwrote `POSICION+1` with
the current column before anything consumed it. The old paddle stayed painted, every later move only
erased one column behind it, and the leftovers survived on screen as "duplicate paddles".

**Rule: a pending erase must never have to survive a frame boundary.** Anything that moves the paddle
outside the normal `nuevaposicion` → `dibujarpala` pair does its own erase and redraw on the spot.
`reset_round` ends `jp dibujarpala` so the paddle does not blink out for a frame between the two.

Inline `DB` initialisers run **once per load, not once per game**, which is why `reset_game` sets
every one of these explicitly rather than trusting the declaration.

## 11. The shadow-map fallback — still an option, still not needed

An authoritative brick grid in free RAM at `$5B00+`, with the attribute file as a pure view of it,
remains the documented fallback. Revisit it if and only if one of these actually arrives:

- **Per-brick state beyond one attribute byte** — the clearest case being multi-hit bricks, where an
  attribute byte cannot carry a hit counter.
- **Position-first classification stops being reliable** — e.g. bricks drawn on row 23, or changed
  border geometry.
- **Counting cannot be done cheaply** — e.g. needing to scan for "are any destructible bricks left?"
  rather than maintaining a counter.

Cost: a byte per brick cell plus the permanent obligation to keep it in sync with every attribute
write — a second source of truth is a second thing to get wrong.

## 12. Before you change collision code

- [ ] Does the empty-field erase-restore test still pass byte-identical? If not, stop.
- [ ] Does classification still test **position** before attribute? (`$38` is ball *and* colour-7.)
- [ ] Are you clearing **both** cells of a brick, and decrementing **once**?
- [ ] Does colour 8 still bounce without decrementing?
- [ ] Are the wall tests still **range** comparisons?
- [ ] Is the step still at most one cell per axis per frame, and `|velocity| ≤ $0100`?
- [ ] Can the row velocity reach zero? (It must not.)
- [ ] Is `|v|` still **256 at every source** — serve, inline `Vector`, and all seven table entries?
      A bounce changes direction, never speed.
- [ ] Does anything move the paddle outside `nuevaposicion` → `dibujarpala`? If so, does it erase and
      redraw itself rather than leaving a pending erase in `POSICION+1`?
- [ ] Does every new routine preserve **`IX`**?
- [ ] Are you using `jp`, not `call`, for anything that leaves the frame loop?
- [ ] Is the rebound table still varied? (Flattening it makes levels unfinishable — §7.)
- [ ] `python3 tests/run_all.py` green?

## 13. What not to do

- **Do not increase ball speed via step size.** → **timing-and-frame-loop** §6
- **Do not flatten the rebound angles.** → §7
- **Do not put game-logic calls in `teclado`.** That is how the F key and the stack leak happened.
- **Do not add a debug key "just to test"** without a removal plan. That is precisely the origin of
  the F key. → **failure-patterns**
- **Do not identify entities by attribute value.** → §5
- **Do not add score or a HUD.** Out of scope.
