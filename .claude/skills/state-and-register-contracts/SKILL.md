---
name: state-and-register-contracts
description: Use before adding a routine, a call, or a variable — or whenever you need to know what a routine reads, returns and destroys, who owns IX, where the game's mutable bytes live, or why level state got corrupted after an apparently unrelated change.
---

# State and register contracts

## 1. The complete mutable-state inventory

State is still declared inline in the code image next to the routine that owns it. There is no
variable block. Addresses move whenever anything earlier in the include order changes size — **resolve
them from `main.lst`, never hardcode them.** The ones below are from the current build.

| Variable | Addr | Size | Declared | Written by | Read by |
|---|---|---|---|---|---|
| `POSICION` | `$9B10` | 2 | `pala.asm:1` | `nuevaposicion`, `reset_round` | `dibujarpala`, `nuevaposicion`, `paddle_hit` |
| `levelCounter` | `$9E74` | 1 | `Partida.asm:1` | `Fin_Juego`, `reset_game` | `Fin_Juego` |
| `Coord` | `$9ECA` | 2 | `pelota.asm` | `ball`, `reset_ball` | `ball`, `resolve_collisions` |
| `CoordFrac` | `$9ECC` | 2 | `pelota.asm` | `ball`, `reset_ball` | `step_ball` |
| `Vector` | `$9ECE` | **4** | `pelota.asm` | `flip_*_velocity`, `paddle_hit`, `reset_ball` | `step_ball` |
| `bricks_left` | `$9F51` | 1 | `colisiones.asm` | `Mostrar_Mapa`, `destroy_brick` | `Pala_Juego` |
| `lives` | `$9F52` | 1 | `colisiones.asm` | `Ball_Lost`, `reset_game` | `Ball_Lost` |
| `ball_lost` | `$9F53` | 1 | `colisiones.asm` | `paddle_hit`, `Ball_Lost`, `reset_game` | `Pala_Juego` |

Per-frame scratch, not game state: `NewRow`/`NewCol` (`$9ED2`/`$9ED4`), `BallSaved` (`$9ED6`),
`cand_cell` (`$9F54`), `bounce_flags` (`$9F56`).

### `Coord`, `CoordFrac` and `Vector` — the byte order

The easiest thing in the codebase to get backwards. `ld hl,(Coord)` is a little-endian 16-bit load —
**the first byte goes in `L`, the second in `H`** — and `PosXY` treats **`H` as the row**.

| Declaration | Byte 0 | Byte 1 | **Truth** |
|---|---|---|---|
| `Coord: DB 16, 20` | → `L` = 16 | → `H` = 20 | **column 16, row 20** |
| `CoordFrac: DB 0, 0` | column fraction | row fraction | same order as `Coord` |

`Vector` is **four bytes: two signed 8.8 words.** `Vector` is the **row** velocity, `Vector+2` the
**column** velocity. It used to be two bytes of ±1; that could express only two angles, which is why
it changed. The comments that used to sit on these declarations claimed `(fila, columna)` and
`(X, Y)` and were both wrong; they now say what the code does.

Position is 8.8 fixed point: the whole part in `Coord`, the fraction in `CoordFrac`. A step loads the
pair into `HL` (`H` = whole, `L` = fraction), adds the velocity with `add hl,de`, and the new cell is
`H`. → **collision-and-physics** §3

### `POSICION` — two bytes, not one

- **Byte 0** = the paddle's **current** leftmost column.
- **Byte 1** = the **previous** column, used only so `dibujarpala` knows which cells to erase.

Byte 1 is initialised to **0 as a sentinel** meaning "nothing to erase yet", which is safe because
column 0 is never a legal paddle position: `nuevaposicion` rejects a landing on column 0 (`ret z`)
and on column ≥ 25 (`ret nc`), giving a legal range of columns **1-24**, so a 7-cell paddle spans
1-30 and never touches the borders. **The bounds are correct — do not "fix" them.**

Note that `reset_round` deliberately sets byte 1 to the paddle's **current** column rather than to 0,
so the paddle gets erased where it actually is before being redrawn at the centre.

### Not gameplay state

`SCR_CUR_PTR` / `SCR_ATTR_PTR` / `PRINT_ATTR` (`$96E5`-`$96E9`) belong to the text library.
`PRINTCHAR` advances the cursor with `INC (HL)` on the pointer's **low byte only**, so printed
strings cannot wrap a line or cross a 256-byte boundary. Not a concern during gameplay — nothing
prints while the ball is moving.

## 2. The `IX` contract — the most dangerous coupling here

**`IX` is a global "current map pointer" held across the entire game loop.**

1. `main.asm:17` — `ld ix,(maplist)` loads the address of `map0`, **once per pass through
   `flujo_juego`**, not once per level.
2. `Mostrar_Mapa` walks `IX` forward and **leaves it sitting on the `$FF` terminator**.
3. `Fin_Juego` does `ld de,1` / `add ix,de` — stepping off the terminator onto the next map's first
   byte.

**The rule: any routine called during gameplay must preserve `IX`.** Clobber it and level state is
silently corrupted — the next `Mostrar_Mapa` walks garbage. Every routine in `colisiones.asm`
preserves it, and `tests/test_pelota.py` asserts that for `classify_cell` specifically.

`PRINTAT` uses `IX` as its string pointer and destroys it. That is safe **only** because nothing
prints during play. The screens that do print (`Pantalla_GameOver`, `Pantalla_Reinicio`) are reached
by leaving the frame loop, and `flujo_juego` reloads `IX` on the way back in.

Why `add ix,de` reaches the next map at all is the memory-adjacency dependency owned by
**map-data-format** §6.

## 3. Per-routine register contracts

Derived by reading each routine body — not from comments.

### `pelota.asm`

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `ball` | — | — | `AF`, `DE`, `HL` | `BC`, `IX`, `IY` | One frame: step, resolve, commit, draw, delay, restore. **Now clobbers `DE`** — it did not before. Nothing depends on that. |
| `step_ball` | — (reads `Coord`, `CoordFrac`, `Vector`) | `NewRow`, `NewCol` | `AF`, `DE`, `HL` | `BC`, `IX` | Called again after any bounce, so position is always derived from the current velocity. |
| `PosXY` | `H` = row, `L` = column | `HL` = attribute address | `HL` | **`AF`**, `BC`, `DE`, `IX` | `H` is the row. Uses `sra` for the row shift — safe only for row ≤ 127. |
| `Esperar_pelota` | — | — | — | **everything** | Pure delay; pushes `HL` and `AF` specifically so the ball's attribute address survives it. |

### `colisiones.asm`

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `resolve_collisions` | `NewRow`/`NewCol`, `Coord` | `Vector` maybe changed, `NewRow`/`NewCol` re-derived | `AF`, `DE`, `HL` | `BC`, `IX` | Tests up to three candidate cells. |
| `classify_cell` | `H` = row, `L` = column | `A` = `CELL_*`, `HL` = attribute address | `AF`, `HL` | `BC`, `DE`, **`IX`** | Position first, attribute second. |
| `probe_cell` | as `classify_cell` | as `classify_cell`, plus `cand_cell` set | `AF`, `HL` | `BC`, `DE`, `IX` | The wrapper that lets `destroy_brick` find the cell again. |
| `destroy_if_brick` | `A` = class | — | `AF`, `DE`, `HL` | `BC`, `IX` | No-op unless `A` is `CELL_BRICK`. |
| `destroy_brick` | `cand_cell` | — | `AF`, `DE`, `HL` | `BC`, `IX` | Clears both cells, decrements `bricks_left` once, floored at 0. |
| `paddle_hit` | `NewCol+1`, `POSICION` | `Vector` set, or `ball_lost` set | `AF`, `DE`, `HL` | `BC`, `IX` | Hit index from the column the ball is **heading for**. |
| `flip_row_velocity` / `flip_col_velocity` | — | one `Vector` component negated | `AF`, `HL` | `BC`, `DE`, `IX` | |
| `reset_ball` / `reset_round` / `reset_game` | — | see §5 | `AF`, `HL` | `BC`, `DE`, `IX` | |

### `pala.asm`

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `dibujarpala` | — (reads `POSICION`) | — | `AF`, `BC`, `DE`, `HL` | `IX` | Erases at the old column (if byte 1 ≠ 0), then draws at the new one. |
| `dibujarpalacolor` | **`A` = column, `C` = colour** | — | `B` (→0), `DE`, `HL`, **flags** | `A`, `C` | Unusual signature. Called with `c=0` to erase. **Preserves `A` but not `F`.** |
| `teclado` | — | **`B` = `-1`, `0` or `1`** | `AF`, `BC`, `D` | `HL`, `IX` | **Always returns now.** It no longer calls anything, and no longer hangs on S or G. |
| `nuevaposicion` | **`B` = direction** | — (updates `POSICION`) | `AF`, `B` | `C`, `DE`, `HL`, `IX` | Bounds are correct. |
| `esperar` | — | — | `AF`, `BC` | `DE`, `HL`, `IX` | **Destroys `BC`.** Harmless only because it runs after `B` has been consumed. Do not reorder the loop without checking this. |

### Other game files

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `Mostrar_Mapa` | `IX` = map pointer | `IX` **on** the `$FF` terminator, `bricks_left` set | `AF`, `BC`, `HL`, `IX` | `DE` | **Now stores byte 0 into `bricks_left`** instead of discarding it. |
| `dibujar_tablero` | — | — | `AF`, `BC`, `DE`, `HL` | `IX` | Calls `CLEARSCR`, so it wipes the whole screen. |
| `CalcularAtributo` | `B` = row, `C` = column | `HL` = attribute address | **`BC`**, `HL` | **`AF`**, `DE`, `IX` | **Destroys `BC`** via `ld bc,$5800`. |

### Shared library (`L30.3 - printat.asm`) — do not edit

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `PRINTAT` | `A` = attribute, `B` = row, `C` = column, `IX` = string | — | `AF`, `B`, `DE`, `HL`, **`IX`** | `C` | **Destroys `IX`.** Never call during gameplay without saving it (§2). |
| `CRtoATTR` | `B` = row, `C` = column | `HL` = attribute address | `AF`, `HL` | **`BC`**, `DE`, `IX` | **Preserves `BC`**, unlike `CalcularAtributo`. Prefer it when you need `BC`. |
| `CLEARSCR` | — | — | `BC`, `DE`, `HL`, flags | `A`, `IX` | `LDIR` over 6911 bytes — pixels **and** attributes. |

**The `CalcularAtributo` `BC` clobber, traced:** `Mostrar_Mapa` calls it with `B` = row and `C` = 1,
and the call destroys both. Harmless — `B` is immediately reloaded with the brick count and `C` is
never read again in that loop. But it works by accident, and new code that expects `B` or `C` to
survive that call will break silently. Use `CRtoATTR` if you need `BC`.

## 4. Stack discipline

**Every historical leak is fixed. There is no known stack growth left anywhere.**

| Was | Cost | Now |
|---|---|---|
| `teclado` did `call Fin_Juego`, and `Fin_Juego` exits via `jr Juego` | 4 bytes per level change | The F-key hook is gone; completion is checked in the frame loop and reached with `jp` |
| `Pantalla_Reinicio` ended `call flujo_juego` | a few bytes per restart | `jp flujo_juego` |
| `flujo_juego` did `CALL Juego` | **2 bytes per restart** | `JP Juego`; the unreachable `jr flujo_juego` behind it is gone |
| `ReinicioJuego` did `call Pantalla_Reinicio` | **2 bytes per completed four-level run** | `jp Pantalla_Reinicio` |

`Pantalla_GameOver`, added with the game-over path, ends `jp flujo_juego` for the same reason.

**The rules that produced those fixes, and still apply:**

- **Never `call` a routine that does not come back.** Everything that leaves `Pala_Juego` —
  `Fin_Juego`, `Ball_Lost`, `Game_Over` — is entered with `jp`, and so are both end-of-game screens.
- **Game logic does not belong in the keyboard handler.**

### The two-check method for converting a `CALL` to a `JP`

This is the part worth copying, because "it never returns" is exactly the kind of claim that is
obviously true right up until it isn't.

**Static — trace it.** For `Juego` this was decisive and cheap: `Partida.asm` contains **no `RET` at
all**, and every branch out of it is a `jp`/`jr` into something that does not come back either —
`Fin_Juego` loops to `Juego`, `Ball_Lost` loops to `Pala_Juego`, and `Game_Over`/`ReinicioJuego`
reach screens that both end `jp flujo_juego`. For `Pantalla_Reinicio`, the same: its last instruction
is `jp flujo_juego`, and the only diversion before it (`call EsperarTecla`) either falls through to
that `jp` or ends in `FinDelJuego_Parada`'s infinite loop.

**Also check what follows the call site.** `call Pantalla_Reinicio` was the **last line of
`Partida.asm`**, and `pelota.asm` is included immediately after — so the next byte in the image is
`Coord`. A return would have executed the ball's state bytes as opcodes. The `jp` makes that
impossible by construction rather than merely unobserved.

**Empirical — measure SP.** Sample at a **fixed call depth**: the GAME OVER key-wait. A running frame
sits at whatever depth its current nested call has reached, so a mid-frame reading is noise (the
first attempt at this produced deltas of `[2, -4, 8, 2]` and meant nothing). Both conversions
measured **exactly 2 bytes per cycle before, 0 after.**

`checklist.py` guards both permanently — and **verifies each restart actually happened** by asserting
the menu text cleared. Without that the tests pass vacuously: if the game never restarts, the
GAME OVER screen is still up, the next iteration "detects" it instantly, and SP is trivially
identical every time. (Related trap in the same tests: **`bricks_left` is not a valid "game
restarted" signal** — after a game over it still holds the interrupted level's count, so waiting for
it to be non-zero returns immediately. Zero it first, then wait.)

## 5. The reset routines

There used to be none, and that was a bug: a new level began with the ball wherever it happened to be
travelling in whatever direction it had, and a second game started with everything where the first
one ended.

| Routine | Sets | Called from |
|---|---|---|
| `reset_ball` | `Coord` → (row 20, col 16), `CoordFrac` → 0, `Vector` → up-and-right at one cell/frame | `reset_round` |
| `reset_round` | the above, plus `POSICION` byte 0 → 14 and byte 1 → the paddle's *current* column | `Fin_Juego` (level change), `Ball_Lost` |
| `reset_game` | the above, plus `lives` → 3, `ball_lost` → 0, `levelCounter` → 0 | `Game_Over`, `ReinicioJuego` |

`bricks_left` is not in any of them: it is reloaded from the new map's byte 0 by `Mostrar_Mapa`, which
runs on entry to every level.

**Lives reset per game, never per level.** Bricks are not restored when a ball is lost — you continue
the same level as you left it.

## 6. Where new state lives

The pattern is an inline `DB` at the top of the owning file, before its first label. That is what the
tree does and what the new collision state follows.

**The cost that bites: inline data is initialised by the loader, once per LOAD — not once per game.**
A `DB 3` for a lives counter is 3 when the binary loads and never again; start a second game and it
holds whatever the first left. That is exactly why `reset_game` writes every one of those bytes
explicitly rather than trusting the declaration. **Anything that must be fresh per round needs an
explicit reset regardless of where it lives.**

Do not reach for free RAM at `$5B00+` for a handful of bytes — it is outside the image, so it is *not*
initialised by loading `main.bin` and holds emulator garbage until written, which buys nothing over an
inline `DB` you also have to initialise. `$5B00+` becomes the right answer only if a shadow brick map
is ever adopted. → **collision-and-physics** §11

**Never interleave a `DB` inside a code path** — execution runs into it and interprets data as
opcodes. → **assembler-conventions** §9
