---
name: map-data-format
description: Use when adding, editing, reordering or debugging a level; when reading Mapas.asm or PintarMapa.asm; when you need the destructible-brick count for completion detection; or before moving anything in Mapas.asm — level progression depends on the maps being physically adjacent in memory.
---

# Map data format

## 1. The real format

`Mapas.asm:5-11` carries a header comment from the Python converter that generated the data. **It is
incomplete: it does not mention that every map begins with an extra byte before the first row.**

The true layout of one map:

```
byte 0            : destructible-brick count for the whole map   <- UNDOCUMENTED, see §2
then, per row:
  byte 0          : Y coordinate (row)
  byte 1          : number of entries in this row
  bytes 2..n      : colour of each entry, 0..8
$FF in the Y position terminates the map
```

Verified against `Mapas.asm:20-30` (map0 opens `DEFB 82`, then `DEFB 3, 12, 0, 0, 2, ...` — Y=3,
12 entries, then 12 colours). `Mostrar_Mapa` reads that first byte and **now stores it into
`bricks_left`**; it used to load it into `A` and immediately overwrite `A` two lines later.

Colour semantics: **0 = no brick**, **1-7 = destructible**, **8 = indestructible**.

## 2. Byte 0 is the destructible-brick count — verified

AUDIT.md §3 concludes this. **Independently re-verified here by counting every cell in all four
maps:**

| Map | Declared byte 0 | Non-empty cells | Non-empty **and** destructible | Matches |
|---|---|---|---|---|
| `map0` (`:20`) | 82 | 82 | 82 | both (no colour-8 bricks) |
| `map1` (`:33`) | 71 | 71 | 71 | both (no colour-8 bricks) |
| `map2` (`:49`) | **78** | **82** | **78** | **destructible only** |
| `map3` (`:65`) | 153 | 153 | 153 | both (no colour-8 bricks) |

`map2` is the discriminating case: it has 82 non-empty cells, four of which are the colour-8
indestructible bricks at `Mapas.asm:53`, leaving 78 destructible. The header says 78.

**Conclusion: byte 0 is the count of destructible bricks, and it is correct for all four maps.** It
**is** the completion counter: `Mostrar_Mapa` loads it into `bricks_left` at level start,
`destroy_brick` decrements it once per brick, and the frame loop advances the level when it reaches
zero. `tests/test_colisiones.py` asserts all four values load correctly, and `checklist.py` asserts
`bricks_left × 2` always equals the lit brick cells on screen.

**So byte 0 is load-bearing now, not just descriptive.** Get it wrong in a new map and the level
either ends early or can never be completed. → **collision-and-physics** §9

(Also verified: every row's declared entry count matches the number of colour bytes that follow. The
data is internally consistent.)

## 3. Colour → attribute, and two rendering consequences

`Mostrar_Mapa` shifts colours 1-7 left three times to move them into the PAPER bits
(`PintarMapa.asm:27-29`):

```
sla a
sla a
sla a          ; A = colour << 3
```

**Consequence (a): colour 8 used to be invisible — fixed.** `8 << 3` = `$40` — BRIGHT set, PAPER 0,
INK 0. Bright black on black. `map2`'s four indestructible bricks were drawn and **could not be
seen**. Paper is only 3 bits wide, so colour 8 can never fit the same `colour << 3` formula as 1-7 —
it necessarily overflows into the BRIGHT bit, and PAPER 0 is black regardless of BRIGHT or INK, so no
value of that formula could ever make it visible.

`PintarMapa.asm` now special-cases colour 8 (`Fila_Ladrillo`/`Color_Indestructible`,
`PintarMapa.asm:23-34`): instead of shifting, it loads the attribute `$78` directly — BRIGHT set,
PAPER 7 (white), INK 0. Same paper-only convention as colours 1-7 (still no reliance on INK), still
distinct from every one of their attributes (none of `$08..$38` has the BRIGHT bit set), and visible.

**This value is load-bearing in `colisiones.asm` too, not just cosmetic.** `classify_cell`
(`colisiones.asm`) has no separate brick registry — the attribute byte painted on screen *is* what it
reads back to classify a cell — so its `CELL_HARD` check is `cp $78`, matching this exactly. If you
ever change what colour 8 renders as, `classify_cell`'s comparison must change with it, or colour-8
bricks silently misclassify as ordinary destructible ones (`CELL_BRICK`) and `bricks_left` decrements
for a brick the map's byte-0 count didn't budget for — the level then completes with indestructible
bricks still standing, or never completes at all. `tests/test_colisiones.py` and `tests/test_pelota.py`
hardcode `$78` for the same reason; `tests/ark.py`'s board renderer keys its `*` display character off
it too.

They still work as gameplay, as before: `classify_cell` returns `CELL_HARD` for the indestructible
attribute, so the ball bounces off them and they are never destroyed or counted — now visibly.

**Consequence (b): empty and erased are indistinguishable.** Colour 0 shifts to `$00`, and
`Mostrar_Mapa` *paints* it rather than skipping the cell — so an empty map cell and a destroyed brick
both read back as attribute 0. Per **failure-patterns**, this was a deliberate retreat: a
commented-out zero-skip path (`Salto_Ladrillo`) was tried and deleted in `7d39c74`. It is harmless
now, because "empty" and "destroyed" mean the same thing to the collision code.

Both consequences constrain collision design — the attribute alone is not a sufficient classifier.
This file owns the **colour → attribute mapping**; **memory-map-and-playfield** §4 owns the
**attribute byte layout** and the full per-entity table, including the two aliases that matter most:
**colour 2 renders as `$10`, byte-identical to the paddle, and colour 7 renders as `$38`,
byte-identical to the ball.**

## 4. Geometry

Bricks are **2 attribute cells wide**. `PintarMapa.asm:31-34` writes the attribute, `inc hl`, writes
the same attribute again, `inc hl`. Each row starts at **column 1** (`PintarMapa.asm:14`, `ld C,1`).

So **entry `i` of a row (0-based) occupies attribute columns `1 + 2i` and `2 + 2i`.**

The right border sits at column 31, so the last usable column is 30, giving `1 + 2i ≤ 29`, i.e.
**i ≤ 14 — a maximum of 15 entries per row.**

Verified against the existing data: the largest row is `count = 14` (map3, e.g. `Mapas.asm:66`),
occupying columns 1-28. **No existing map overruns.** There are 2 columns of headroom (29-30) before
the border.

**Legal Y range:** row 0 is the top border (`tablero.asm:26-34`) and row 23 is the paddle
(`pala.asm:21`). Rows 1-22 are available. The existing maps use **rows 3-18** (map0 uses 3-13, map1
3-14, map2 3-14, map3 3-18), leaving rows 19-22 clear above the paddle. That gap is what gives the
ball room to travel; do not fill it without thinking about playability.

## 5. How `Mostrar_Mapa` walks the data

```
Entry:  IX = pointer to a map's byte 0
Exit:   IX = pointer to the $FF terminator  (ON it, not past it)
```

Sequence:

1. Read byte 0 into `A` and **store it in `bricks_left`**, then `inc ix`. (This step used to discard
   the count — `A` was overwritten two instructions later.)
2. `Fila:` `:9-11` read Y into `A`, `inc ix`.
3. `:13-15` set `B` = Y, `C` = 1, `call CalcularAtributo` → `HL` = address of column 1 on that row.
4. `:17-19` read the entry count into `B`.
5. `Fila_Ladrillo:` `:23-36` read a colour, `inc ix`, shift left 3, write it to `(HL)` twice with two
   `inc hl`, `djnz`.
6. `:38-40` peek at the next byte; if `$FF`, `jr z, Fin_Dibujo` — **without advancing `IX`**.
7. Otherwise `jr Fila` (`:43`).

**`CalcularAtributo` destroys `BC`**, which is harmless here only because `B` is reloaded at `:17-19`
and `C` is never read again. → **state-and-register-contracts** §3

**Dead code:** `call Pala_Juego` at `PintarMapa.asm:44` sits immediately after the unconditional
`jr Fila` at `:43` and is unreachable. Ignore it; do not "restore" it.

## 6. THE ADJACENCY DEPENDENCY — read before touching `Mapas.asm`

`Fin_Juego` advances the level like this (`Partida.asm:54-56`):

```asm
Fin_Juego:
    ld de, 1
    add ix, de           ; comment claims: "Sumamos a IX (maplist)"
```

**The comment is wrong.** `IX` does not point into `maplist`. It points into the **map data**, parked
on the `$FF` terminator by `Mostrar_Mapa` (§5). Adding 1 steps off the terminator and onto the next
map's byte 0 — **and that only works because the maps are physically back-to-back in memory.**

Verified addresses from a fresh listing. **They all shifted when `colisiones.asm` grew** — the shape
is what matters, not the numbers, and you should re-read them from `main.lst`:

| Map | Starts at | `$FF` terminator at | Next byte |
|---|---|---|---|
| `map0` | `$9BEA` | `$9C6E` | `$9C6F` = **`map1`** |
| `map1` | `$9C6F` | `$9D0F` | `$9D10` = **`map2`** |
| `map2` | `$9D10` | `$9D80` | `$9D81` = **`map3`** |
| `map3` | `$9D81` | `$9E73` | `$9E74` = **`levelCounter`** (!) |

Every terminator is immediately followed by the next map's first byte, with **zero padding**.

**The rules that follow — none of these mistakes produces an assembler error:**

- **Maps must stay contiguous and in order.** No padding, no `ALIGN`, no `DS`, nothing between them.
- **A new map may only be appended at the end**, after `map3`. Inserting one anywhere else
  renumbers the sequence silently.
- **Do not reorder `map0..map3`.**
- **Do not move `Mapas.asm` in the include list** (`main.asm:33`), and do not split the maps across
  files.
- Adding a comment or blank line between maps is fine — those emit no bytes. Adding a `DEFB` is not.

**The failure is silent and only appears at runtime**, as a level that renders garbage, because
`Mostrar_Mapa` will happily interpret whatever bytes it finds as Y/count/colour triples.

## 7. `maplist` looks live and is not

`Mapas.asm:14`:

```asm
maplist: DEFW map0, map1, map2, map3
```

An 8-byte pointer table at `$9BE2`. It is read **exactly once** — `main.asm:17`, `ld ix,(maplist)`,
which loads only the *first* entry — and **never indexed again**. Level advance walks the raw data
instead (§6). The table is dead weight that looks load-bearing.

`maxLevelsMask: EQU 3` (`Mapas.asm:15`) is grep-verified **never referenced anywhere** — a leftover
from an intended mask-based level wrap.

**What a correct implementation would look like:** keep a level index, multiply by 2, index
`maplist`, and reload `IX` from the table:

```asm
; illustrative only — not current behaviour
    ld a, (levelCounter)
    add a, a                 ; × 2, table of words
    ld e, a
    ld d, 0
    ld hl, maplist
    add hl, de
    ld a, (hl) : inc hl      ; low byte
    ld h, (hl) : ld l, a     ; IX <- (maplist + 2*level)
```

That would **remove the adjacency dependency entirely** and make map order and placement free. It is
a worthwhile cleanup, but it is not required for collision work — note that `CantidadNiveles EQU 4`
(`Partida.asm:2`) is the level count that would have to stay in sync with the table's length.

## 8. The end-of-maps bound is correct by ordering only

`Fin_Juego` increments `IX` **before** testing `levelCounter`. So after `map3` completes, `IX` briefly
holds `$9E74` — which is `levelCounter` itself, followed by `Juego`'s code. That is not map data.

It is never dereferenced: `levelCounter` reaches `CantidadNiveles` = 4 on that same pass and the code
branches to `ReinicioJuego` (`:28`) without ever calling `Mostrar_Mapa` again.

**It works. It is correct by ordering, and fragile if reordered.** Swap those two operations — test
before increment — and the game reads `levelCounter` and executable code as a map. If you touch
`Fin_Juego`, preserve the order.

## 9. Adding or editing a level

- [ ] Append the new map **after `map3`** in `Mapas.asm`, immediately adjacent — no padding.
- [ ] Count your destructible bricks (colours 1-7, excluding 0 and 8) and put that number in
      **byte 0**. Completion detection trusts it absolutely (§2). **Too high and the level can never
      be completed; too low and it completes with bricks still standing.**
- [ ] Every row: `Y, count, <count colour bytes>`. The count must match the number of colours exactly.
- [ ] Keep `count ≤ 15` (§4) — 14 is the largest in use, giving columns 1-28.
- [ ] Keep Y in 1-22; 3-18 matches the existing style and leaves the ball room.
- [ ] Terminate with `DEFB 255`.
- [ ] Add the label to `maplist` (`Mapas.asm:14`) for consistency. **This is cosmetic only** — the
      table is read once and never indexed (§7). It sits *before* `map0`, so adding an entry shifts
      every map address by 2; that is harmless, because the adjacency rule (§6) is about the maps
      being contiguous *with each other*, not about their absolute addresses.
- [ ] Bump `CantidadNiveles` (`Partida.asm:2`) to match the number of maps. **Both directions of
      mismatch are bugs:** too low and the new level is never reached; too high and `Fin_Juego` walks
      `IX` past the last map into `levelCounter` and executable code before the `cp` catches it (§8).
- [ ] Colour 8 now renders visibly (bright white, `$78` — §3a) and is still indestructible. Use it
      freely for indestructible bricks; just don't count it in byte 0 (§2).
- [ ] Check the level is actually completable. This is much less fragile than it was: the paddle now
      gives a **variable rebound angle**, so the trajectory is player-controlled rather than a fixed
      property of the map. The tests prove the mechanism, **not** that your geometry is reachable.
      → **collision-and-physics** §7
- [ ] Build and step through every level to confirm each renders. The F key is gone; levels advance
      when the last destructible brick falls. To step through quickly, poke `bricks_left` to 0 —
      `tests/checklist.py` does exactly that. → **build-and-verify** §6
