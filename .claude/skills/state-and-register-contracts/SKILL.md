---
name: state-and-register-contracts
description: Use before adding a routine, a call, or a variable — or whenever you need to know what a routine reads, returns and destroys, who owns IX, where the game's mutable bytes live, or why level state got corrupted after an apparently unrelated change.
---

# State and register contracts

## 1. The complete mutable-state inventory

All game state is **seven bytes**, declared inline in the code image next to the routine that owns
them. There is no variable block, no zero-page equivalent, and **no reset routine**.

| Variable | Address | Size | Declared | Written by | Read by |
|---|---|---|---|---|---|
| `POSICION` | `$9AD5` | 2 | `pala.asm:1` `DB 14,0` | `nuevaposicion` (`pala.asm:79,81`) | `dibujarpala` (`pala.asm:7,14`), `nuevaposicion` (`:72,78`) |
| `levelCounter` | `$9E3E` | 1 | `Partida.asm:1` `DEFB 0` | `Fin_Juego` (`:25`), `ReinicioJuego` (`:34`) | `Fin_Juego` (`:26`) |
| `Coord` | `$9E6E` | 2 | `pelota.asm:1` `DB 16, 20` | `ball` (`pelota.asm:56`) | `ball` (`:6,11`) |
| `Vector` | `$9E70` | 2 | `pelota.asm:2` `DB -1, 1` | `ball` (`:19,28,41,50`) | `ball` (`:12,17,26,34,39,48`) |

### `POSICION` — two bytes, not one

- **Byte 0** (`$9AD5`) = the paddle's **current** leftmost column.
- **Byte 1** (`$9AD6`) = the **previous** column, used only so `dibujarpala` knows which cells to
  erase before redrawing (`pala.asm:7-11`).

Byte 1 is initialised to **0 as a sentinel** meaning "nothing to erase yet". That is safe because
column 0 is never a legal paddle position: `nuevaposicion` does `add b` then `ret z` (`pala.asm:73-74`),
rejecting any move that lands on column 0, and `cp 32-LONGITUDPALA` / `ret nc` (`:75-76`) rejects
column ≥ 25. Legal range is columns **1-24**, so a 7-cell paddle spans columns 1-30 and never touches
the borders at 0 and 31. **The bounds are correct — do not "fix" them.**

### `Coord` and `Vector` — the comments are wrong

This is the single easiest thing in the codebase to get backwards, and both comments mislead.

`ld hl,(Coord)` (`pelota.asm:6`) is a little-endian 16-bit load: **the first byte goes in `L`, the
second in `H`**. `PosXY` then treats **`H` as the row** (`pelota.asm:79-92`, and see
**memory-map-and-playfield** §5).

| Declaration | Byte 0 | Byte 1 | Comment claims | **Truth** |
|---|---|---|---|---|
| `Coord: DB 16, 20` | → `L` = 16 | → `H` = 20 | `(fila, columna)` = row 16, col 20 | **row 20, column 16** |
| `Vector: DB -1, 1` | → row delta = −1 | → col delta = +1 | `(X, Y)` | byte 0 is the **row** delta, byte 1 the **column** delta |

Confirmed by the arithmetic: `pelota.asm:12-13` loads `(Vector)` and does `add h` — adding byte 0 to
the row. `pelota.asm:34-35` loads `(Vector+1)` and does `add l` — adding byte 1 to the column.

So **the ball starts at row 20, column 16, travelling up and to the right.**

**The code wins; the comments are wrong.** Correcting those two comment lines is a good, safe first
change — it costs nothing and removes a trap. → **assembler-conventions** §2 for the English-comment
rule.

### Not gameplay state

`SCR_CUR_PTR`, `SCR_ATTR_PTR`, `PRINT_ATTR` (`L30.3 - printat.asm:158-160`, `$96E5`-`$96E9`) belong to the
text library. `PRINTCHAR` advances the cursor with `INC (HL)` on the pointer's **low byte only**
(`:125,127`), so printed strings cannot wrap a line or cross a 256-byte boundary. Not a concern
during gameplay — nothing prints while the ball is moving.

## 2. The `IX` contract — the most dangerous coupling here

**`IX` is a global "current map pointer" held across the entire game loop.**

1. `main.asm:17` — `ld ix,(maplist)` loads the address of `map0`. This happens **once per pass
   through `flujo_juego`**, not once per level.
2. `Mostrar_Mapa` (`PintarMapa.asm`) walks `IX` forward through the map data and **leaves it sitting
   on the `$FF` terminator** (`:34-36` reads it, `jr z` exits without advancing past it).
3. `Fin_Juego` (`Partida.asm:20-21`) does `ld de,1` / `add ix,de` — stepping off the terminator onto
   the next map's first byte.

**The rule: any routine called during gameplay must preserve `IX`.** Clobber it and level state is
silently corrupted — the next `Mostrar_Mapa` walks garbage.

`PRINTAT` uses `IX` as its string pointer (`L30.3 - printat.asm:12,20,24`) and destroys it. That is
safe **only** because nothing prints during play. If you add a HUD or an in-game message, you must
save and restore `IX` around it. (Score and HUD are out of scope — but this is why.)

Why `add ix,de` reaches the next map at all is the memory-adjacency dependency owned by
**map-data-format** §6. Do not re-derive it; do read it before touching `Mapas.asm`.

## 3. Per-routine register contracts

Derived by reading each routine body — not from comments, which are unreliable here.

### `pelota.asm`

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `ball` (`:5`) | — (reads `Coord`, `Vector`) | — (updates both) | `AF`, `HL` | `BC`, `DE`, `IX`, `IY` | Draws, delays ~32 ms, erases, then moves. The erase at `:10` is the destructive write. |
| `PosXY` (`:77`) | `H` = row, `L` = column | `HL` = attribute address | `HL` | **`AF`** (push/pop `:78,:93`), `BC`, `DE`, `IX` | `H` is the row. Uses `sra` for the row shift — safe only for row ≤ 127. |
| `Esperar_pelota` (`:63`) | — | — | — | **everything** (`push hl`/`push af` `:64-65`) | Pure delay. |

### `pala.asm`

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `dibujarpala` (`:6`) | — (reads `POSICION`) | — | `AF`, `BC`, `DE`, `HL` | `IX` | Erases at the old column (if byte 1 ≠ 0), then draws at the new one. |
| `dibujarpalacolor` (`:19`) | **`A` = column, `C` = colour** | — | `B` (→0), `DE`, `HL`, **flags** | `A`, `C` | Unusual signature: the column arrives in `A`, the colour in `C`. Called with `c=0` to erase. **Preserves `A` but not `F`** — `add hl,de` (`:24`) writes H/N/C. |
| `teclado` (`:32`) | — | **`B` = direction: `-1`, `0` or `1`** | `AF`, `BC`, `D` | `HL`, `IX` | May `call Fin_Juego` (`:47`) and **never return** — see §4. Hangs if S or G is held (`:54-56`). |
| `nuevaposicion` (`:68`) | **`B` = direction** | — (updates `POSICION`) | `AF`, `B` | `C`, `DE`, `HL`, `IX` | Returns early without moving on `B=0`, on column 0, or on column ≥ 25. Bounds are correct. |
| `esperar` (`:84`) | — | — | `AF`, `BC` | `DE`, `HL`, `IX` | **Destroys `BC`.** Harmless today only because `Pala_Juego` runs `teclado → nuevaposicion → dibujarpala` first, so `B` is already consumed. Do not reorder the loop without checking this. |

### Other game files

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `Mostrar_Mapa` (`PintarMapa.asm:1`) | `IX` = map pointer | `IX` **on** the `$FF` terminator | `AF`, `BC`, `HL`, `IX` | `DE` | Reads byte 0 into `A` (`:2`) then discards it at `:6` — that is the brick count. `call Pala_Juego` at `:40` is unreachable dead code. |
| `dibujar_tablero` (`tablero.asm:1`) | — | — | `AF`, `BC`, `DE`, `HL` | `IX` | Calls `CLEARSCR` first, so it wipes the whole screen. |
| `CalcularAtributo` (`mensaje_inicio.asm:52`) | `B` = row, `C` = column | `HL` = attribute address | **`BC`**, `HL` | **`AF`** (push/pop `:55,:64`), `DE`, `IX` | **Destroys `BC`** via `ld bc,$5800` at `:62`. See the note below. |

### Shared library (`L30.3 - printat.asm`) — do not edit these files

| Routine | In | Out | Clobbers | Preserves | Notes |
|---|---|---|---|---|---|
| `PRINTAT` (`:14`) | `A` = attribute, `B` = row, `C` = column, `IX` = string address | — | `AF`, `B`, `DE`, `HL`, **`IX`** | `C` | **Destroys `IX`.** Never call during gameplay without saving it (§2). `C` survives, but do not rely on it. |
| `CRtoATTR` (`:72`) | `B` = row, `C` = column | `HL` = attribute address, also stored in `SCR_ATTR_PTR` | `AF`, `HL` | **`BC`**, `DE`, `IX` | **Preserves `BC`**, unlike `CalcularAtributo`. Prefer it when you need `BC` to survive. |
| `CLEARSCR` (`:150`) | — | — | `BC`, `DE`, `HL`, flags | `A`, `IX` | `LDIR` over 6911 bytes — pixels **and** attributes. |

**The `CalcularAtributo` `BC` clobber, traced:** `Mostrar_Mapa` calls it at `PintarMapa.asm:11` with
`B` = row and `C` = 1, and the call destroys both. This turns out to be **harmless** — `:13-15`
immediately reload `B` with the brick count, and `C` is never read again in that loop. It works. But
it works by accident, and any new code that expects `B` or `C` to survive that call will break
silently. Use `CRtoATTR` if you need `BC`.

## 4. Stack discipline is broken in two places

Both are real structural defects. Understand them so you do not copy the pattern.

**(a) `call Fin_Juego` that never returns.** `teclado` does `call Fin_Juego` (`pala.asm:47`), and
`Fin_Juego` exits via `jr Juego` (`Partida.asm:30`). So the return address pushed by
`call Fin_Juego` — *and* the one pushed by whoever called `teclado` — are abandoned on the stack
forever. **4 bytes leak per level change.**

**(b) `call flujo_juego` that never returns.** `Pantalla_Reinicio` ends with `call flujo_juego`
(`mensaje_inicio.asm:39`), calling into a label that loops forever. A few more bytes per restart.

**How bad is it, honestly?** `SP` starts at 0 and wraps to `$FFFE`; the program image ends at
`$9EF2`, leaving roughly 24 KB of headroom. At 4 bytes per level change that is on the order of a
thousand game cycles before it could reach anything. **It is not a practical crash risk today.** It
is still a genuine defect, and it will bite the moment anyone adds a deeper call tree or recursion.

**The rules that follow:**

- **Never `call` a routine that jumps back into the main loop.** If control is not coming back, use
  `jp`, not `call`.
- **Level progression must not be invoked from inside the keyboard handler.** Completion detection
  belongs at the `;mirar si fin partida` point in the frame loop (`Partida.asm:10`), where it can
  return normally. → **collision-and-physics** §9

## 5. There is no reset routine — and that is a bug you will have to fix

| Transition | What resets | What does **not** |
|---|---|---|
| Level change (`Fin_Juego` → `Juego`) | nothing | `Coord`, `Vector`, `POSICION` |
| Game restart (`ReinicioJuego`, `Partida.asm:32-36`) | `levelCounter` only (`:34`) | `Coord`, `Vector`, `POSICION` |

So a new level starts with the ball wherever it happened to be, travelling in whatever direction it
had, and a **second game starts with the ball and paddle in their end-of-previous-game positions.**

Collision work has to fix this. A `reset_round` routine needs to own, at minimum:

- `Coord` — back to a defined start cell
- `Vector` — back to a defined start direction, with a non-zero row delta
- `POSICION` byte 0 — paddle back to centre; byte 1 — back to the 0 sentinel, or the first
  `dibujarpala` will erase a stale column
- the remaining-brick counter — reloaded from the new map's byte 0 (**map-data-format** §2)
- lives — reset on new *game* only, not on new level

Design belongs to **collision-and-physics**; the byte list is here.

## 6. Where new state should live

Existing pattern: inline `DB` at the top of the owning file, before its first label. It works and is
what the tree does. Its costs are that state is scattered across five files with no inventory, and
that inline data is initialised **by the loader, once per load — not once per game**.

For the variables collision work introduces:

| Variable | Suggested home | Why |
|---|---|---|
| Saved attribute under the ball (1 B) | inline `DB` in `colisiones.asm` | Per-frame scratch; initial value irrelevant. |
| Remaining destructible bricks (1 B) | inline `DB` in `colisiones.asm` | Must be **loaded from map byte 0 at level start** anyway, so its initial value never matters. |
| Lives (1 B) | inline `DB` in `colisiones.asm` | Must be reset by `reset_game`, not relied on from the loader. |

**Recommendation: keep new state inline with `DB` in `colisiones.asm`, and initialise every byte
explicitly in a reset routine.** Do not reach for free RAM at `$5B00+` for a handful of bytes — it is
outside the image, so it is *not* initialised by loading `main.bin` and holds emulator garbage until
you write it, which buys you nothing over an inline `DB` you also have to initialise.

`$5B00+` becomes the right answer only if a shadow brick map is ever adopted, where the size (hundreds
of bytes) makes inline declaration wasteful. That is a documented fallback with a stated trigger —
**collision-and-physics** §3.

**Never interleave a `DB` inside a code path** — execution runs into it and interprets data as
opcodes. → **assembler-conventions** §9. Address ranges → **memory-map-and-playfield** §7.
