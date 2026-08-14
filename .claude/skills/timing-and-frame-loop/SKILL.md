---
name: timing-and-frame-loop
description: Use when changing ball or paddle speed, adding work to the per-frame loop, wondering why the display tears or the ball flickers, or reasoning about how long anything takes. Also read before any change that alters how far an entity moves per frame.
---

# Timing and the frame loop

## 1. The model

**All pacing is counted busy-wait delay loops. This is the architecture of this game, not a defect
awaiting repair.** Work within it.

`di` is executed at `main.asm:5` and interrupts are **never re-enabled** — grep-verified: there is no
`ei`, no `IM 1`, no `IM 2`, no interrupt vector table, no ISR and no `halt` anywhere in the sources.
`.vscode/launch.json` does not enable a vsync interrupt for the zrcp target, and the program would
ignore one if it did.

Descriptively, three properties follow from that, and you should expect all three when you run it:

- Frame length is whatever the delay loops add up to, measured in T-states, not in raster frames.
- **Nothing is synchronised to the raster**, so attribute writes land mid-scan and the display tears.
- The ball is drawn and erased inside each frame, so it is visible for part of the frame only (§7).

The interrupt-driven rendering rewrite that AUDIT.md §5.8 raises is **explicitly deferred and out of
scope**. Do not propose it, design toward it, or add a `halt`.

## 2. The frame loop as it exists

`main.asm:15-22`:

```
flujo_juego:
        ld ix, (maplist)     ; reload the map pointer — once per pass, not per level
        CALL Juego
        jr flujo_juego
```

`Partida.asm:4-15`:

```
Juego:
    call dibujar_tablero     ; clear screen + draw border   (once per level)
    call Mostrar_Mapa        ; paint the bricks             (once per level)

Pala_Juego:                  ; ---- the frame loop ----
    call ball                ; draw ball, delay ~32 ms, erase, advance Coord
    ;mirar si fin partida    ; <- end-of-round detection was meant to go here
    call teclado             ; poll keyboard -> B = direction
    call nuevaposicion       ; apply B to POSICION, with bounds checks
    call dibujarpala         ; erase at old column, draw at new
    call esperar             ; ~7.6 ms delay
    jr Pala_Juego
```

Two things to notice:

- **`Partida.asm:10` is the hook point.** The comment `;mirar si fin partida` ("check for end of
  round") marks where completion detection belongs — inside the loop, where it can return normally.
  → **collision-and-physics** §9
- **There is no exit from this loop** except `teclado`'s F-key path, which does `call Fin_Juego`
  (`pala.asm:47`) and never comes back. → **state-and-register-contracts** §4

## 3. The delay budget

Derived from the instruction sequences, at 3.5 MHz. Re-derive these after any change; the arithmetic
is shown so you can.

**`Esperar_pelota` — `pelota.asm:63-75`.** `ld hl,$1100` = **4352** iterations of:

```
dec hl            6 T
ld a,h            4 T
or l              4 T
jr nz,...        12 T taken / 7 T not taken
                 --
                 26 T per iteration
```

4351 taken + 1 not-taken = `4351 × 26 + 21` = **113,147 T**, plus ~62 T of push/pop/ret overhead
→ **≈ 113,209 T ≈ 32.3 ms**.

**`esperar` — `pala.asm:84-91`.** `CONTADOR EQU $03FF` (`pala.asm:4`) = **1023** iterations of the
same 26 T body (`dec bc / ld a,b / or c / jr nz`):

`1022 × 26 + 21 + 20` = **≈ 26,613 T ≈ 7.6 ms**.

**The `teclado` polling loop — `pala.asm:32-43`.** `D` starts at 0 and `dec d` wraps it to 255, so
with **no key pressed** the loop runs **256** iterations of:

```
ld bc,$FDFE      10 T
in a,(c)         12 T
and $1F           7 T
cp $1F            7 T
jr nz,teclado2    7 T (not taken — no key)
dec d             4 T
jr nz,teclado1   12 T
                 --
                 59 T per iteration
```

`255 × 59 + 54 + 24` = **≈ 15,123 T ≈ 4.3 ms**.

**`tecladofin` — `pala.asm:58-65`**, reached only when a key *was* recognised. 5 × `nop` (20 T) +
`dec d` (4 T) + `jr nz` (12 T) = **36 T** per iteration, run `D` times. See §4 — `D` is not a
constant.

**Frame totals:**

| Case | Composition | Total |
|---|---|---|
| No key held | 32.3 + 4.3 + 7.6 + ~0.1 (draw/move) | **≈ 44.3 ms → ≈ 22.6 fps** |
| A or D held | 32.3 + short poll + `tecladofin` + 7.6 | **≈ 42–45 ms**, varying — see §4 |

**The ball advances exactly one 8-pixel cell per frame** (`pelota.asm:12-13,34-35` add `Vector` to
`Coord` once per call). So ball speed ≈ 22.6 cells/second, and **it is a function of the total loop
time, not of `Esperar_pelota` alone.**

## 4. `teclado`'s delay is not a constant — and it is inverted

`D` is used for two different jobs, and this is a genuine timing dependency, not a curiosity.

`jr nz,teclado2` (`pala.asm:39`) branches out of the poll **before** `dec d` (`:40`). So `D` holds
the number of *unsuccessful* polls so far — counted downward from 0, i.e. wrapping:

| Key recognised on poll # | `D` on reaching `tecladofin` | `tecladofin` iterations | Delay |
|---|---|---|---|
| 1st (key already down) | 0 | **256** (wraps) | ≈ 2.6 ms |
| 2nd | 255 | 255 | ≈ 2.6 ms |
| 100th | 157 | 157 | ≈ 1.6 ms |

So the post-keypress delay **varies with how quickly the key was detected**, and is *longest* when
the key is detected *immediately*. Paddle movement speed is therefore inconsistent between frames.
It is not broken, but `teclado` is **not a fixed-cost block**, and you cannot treat it as one when
retuning.

**The hang.** `teclado4` (`pala.asm:54-56`) tests for D; if D is not pressed it does
`jr teclado1` — back to the top of the poll **without decrementing `D`**. A key on the `$FDFE`
half-row that is neither A, D nor F — that is **S or G** — makes the loop run forever. **Holding S
or G freezes the whole game** (ball and paddle both stop) until the key is released. S sits right
next to A and D, so this is easy to hit by accident. → **failure-patterns**

Also: the paddle moves at most **one cell per frame** no matter how long a key is held.

## 5. Retuning: the two constants are coupled

Ball speed and paddle speed are governed by two unrelated magic numbers in two different files:

| Constant | Where | Governs directly |
|---|---|---|
| `$1100` | `pelota.asm:66` (inline, not an `EQU`) | the bulk of the frame — 73% of it |
| `CONTADOR EQU $03FF` | `pala.asm:4` | ~17% of the frame |

They share **one** loop, so changing either changes the feel of both. Practical guidance:

| You want | Do this | Side effect |
|---|---|---|
| Ball slower, paddle unchanged | Raise `$1100` (`pelota.asm:66`) | Frame lengthens, so the paddle also becomes **less** responsive — it still moves one cell per frame, but there are fewer frames per second. There is no way to slow the ball without slowing paddle response. |
| Ball faster | **Lower `$1100`.** Never raise the step size — see §6 | Paddle becomes more responsive too. |
| Paddle more responsive | Lower `CONTADOR` (`pala.asm:4`) | Frame shortens by up to 7.6 ms, so **the ball speeds up** by roughly the same proportion. Compensate by raising `$1100`. |
| Both slower, same ratio | Raise both proportionally | — |

**To retune only one thing, you must adjust both constants together.** Budget the frame first: decide
the target total, then split it.

> **Trap: a delay constant of 0 is the *longest* delay, not the shortest.** Both loops decrement
> *before* testing (`ld bc,CONTADOR` then `dec bc / ld a,b / or c / jr nz`), so `CONTADOR EQU 0`
> wraps to 65536 iterations ≈ **0.49 s per frame**, and `ld hl,$0000` in `Esperar_pelota` does the
> same. The minimum useful value is 1. If the game suddenly crawls after you "removed" a delay, this
> is why.

### "Make the paddle faster" — two different requests

Be clear which one is being asked for:

- **More responsive** (reacts sooner) → shorten the frame, per the table above.
- **Moves further per keypress** → that is not a timing change at all. The paddle moves **at most one
  cell per frame** because `teclado` returns `B ∈ {−1, 0, +1}` (`pala.asm:52,57`) and
  `nuevaposicion` does a single `add b` (`pala.asm:73`). To move two cells per frame you return
  `B = ±2`.
>
> Traced: `B = ±2` **is** safe with the existing bounds. `ret z` (`:74`) still catches a landing on
> column 0 from an even column, and `ret nc` (`:76`) still catches both the ≥25 case and the
> wrap-to-255 from column 1. But it is safe *by luck*, not by design — the checks were written for a
> unit step. If you change the step, re-derive both bounds rather than trusting this note, and note
> that the paddle will then be unable to reach some columns (it can only land on cells of one parity
> from a given start).

**None of this is the ball's step-size rule (§6).** That rule exists because the ball's *wall tests*
depend on a unit step. The paddle has no such tests — it has explicit bounds checks. Do not
over-apply §6 to the paddle.

Per **failure-patterns**, the current values are one evening of eyeball tuning from the final commit
(`561cc23` changed `$1F00`→`$1100`, `CONTADOR` `$01FF`→`$03FF` and `LONGITUDPALA` 4→7 all at once).
They are not a considered baseline — retune freely, but deliberately.

## 6. The hard constraint: change delays, never step size

The ball's four wall checks test **exact equality**, not a range:

| Edge | Test | Where |
|---|---|---|
| Bottom | `cp 24` | `pelota.asm:15` |
| Top | `cp -1` | `pelota.asm:24` |
| Right | `cp 32` | `pelota.asm:37` |
| Left | `cp -1` | `pelota.asm:46` |

> **Before you change these lines, read collision-and-physics §4.** The *forced* values that follow
> each test (22 / 1 / 30 / 1) are correct mirror reflections, despite AUDIT.md §5.3 claiming they are
> off by one — implementing AUDIT's "Should be" column introduces a stutter. The real defect is that
> the ball is allowed onto the border cells at all.

These work **only** because the step is exactly ±1, so the ball cannot skip the boundary value. If
you make the ball faster by giving `Vector` a magnitude of 2, it will step from 23 to 25, miss
`cp 24` entirely, and keep going — off the playfield, through the attribute file, and into arbitrary
memory. **This is the most dangerous latent fragility in the ball code.**

**Rule: change ball speed by changing the delay constants, never by changing the step size** — unless
you first convert those equality tests to range comparisons (`cp 24` / `jr nc` style).
**collision-and-physics** §4 owns that conversion, and §6 owns why variable rebound angle has to
respect this same constraint.

## 7. The ball's visible duty cycle

`ball` (`pelota.asm:5-10`) draws the ball, calls `Esperar_pelota`, then erases it and returns. The
rest of the frame — `teclado`, `nuevaposicion`, `dibujarpala`, `esperar` — runs with **the ball
erased**:

- visible: 32.3 ms of ≈ 44.3 ms → **73%**
- erased: ≈ 12 ms → **27% off-duty**, which reads as flicker

That is a property of the model, not a bug in `ball`. The paddle does not flicker because
`dibujarpala` repaints it every frame.

The read-back-and-restore fix (**collision-and-physics** §3) changes *what byte* gets written during
the erase — the cell's previous contents instead of 0 — which stops the ball destroying bricks and
border (**memory-map-and-playfield** §2). **It does not change this duty cycle**, and it is not
supposed to.

## 8. Everything here is CPU-clock-dependent

The numbers above assume **3.5 MHz**. On a 128K machine, a turbo mode, or a non-cycle-accurate
emulator, the entire game speeds up proportionally — there is no clock, no frame counter and no
compensation anywhere in the code.

This is precisely why the project runs on **ZEsarUX over ZRCP** rather than a simulator that does not
model cycles faithfully: with all pacing calibrated by feel against T-state counts, a simulator that
runs "about right" will not reproduce the timing you tuned. → **build-and-verify**

## 9. Before you change any timing constant

- [ ] Have you worked out the new **total** frame time, not just the one loop you edited?
- [ ] Have you accounted for the *other* constant, in the other file?
- [ ] Are you changing a **delay**, not a step size? (§6 — step size breaks the wall tests.)
- [ ] Does the ball still advance exactly one cell per frame?
- [ ] Have you left `teclado`'s variable cost (§4) out of your budget by mistake?
- [ ] If you added work to the loop, did you add it *inside* `Pala_Juego` — and does it preserve
      `IX`? (**state-and-register-contracts** §2)
- [ ] Did you verify by running, not by arithmetic alone? (**build-and-verify**)
