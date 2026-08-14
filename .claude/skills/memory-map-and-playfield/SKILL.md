---
name: memory-map-and-playfield
description: Use when drawing, erasing or reading anything on screen, when converting a row/column to an address, when deciding where new state lives in RAM, or when something visual is going wrong — bricks disappearing, the border developing holes, a trail left behind an entity. Also read before any collision work.
---

# Memory map and the playfield

## 1. THE GOVERNING FACT

**The playfield IS the attribute file. There is no background layer. Erasing an entity therefore
destroys whatever was underneath it.**

Everything else in this file is detail. That sentence is the thing that governs the design of every
drawing routine, every collision test, and the entire build order in **project-orientation** §6.

The game renders **no sprites**. Border, bricks, paddle and ball are all coloured 8×8 attribute cells
in `$5800-$5AFF`. The play area is a **32×24 character grid**. Three consequences:

- **Motion is quantised to 8 pixels.** An entity is at a cell or it is not; there are no sub-cell
  positions. The ball advances exactly one cell per frame.
- **Collision is a cell-address comparison**, not a box intersection. Two things collide when they
  want the same cell.
- **Erasing is overwriting.** `ld (hl),0` does not "remove the ball" — it paints the cell black,
  whatever was there before.

Every entity's footprint, verified:

| Entity | Cells | Where | Drawn with |
|---|---|---|---|
| Ball | 1 | `pelota.asm:8` | `ld (hl), 8*7` = `$38` |
| Paddle | 7 (`LONGITUDPALA`, `pala.asm:2`) on row 23 | `pala.asm:19-30` | `ld (hl),c`, c = `COLORPALA` = `2*8` = `$10` |
| Brick | 2 wide | `PintarMapa.asm:27-30` — writes the byte, `inc hl`, writes it again | colour `<< 3` |
| Border | 1 | `tablero.asm:10-34` | `1*8+7` = `$0F` |

The paddle's row: `pala.asm:21` loads `$5B00-32` = `$5AE0`. Since `$5AE0 - $5800 = 736 = 23 × 32`,
that is **row 23** — the bottom row of the grid.

## 2. What this currently breaks, concretely

This is not theoretical — though note it is derived from reading the code, like everything else in
this library, and has not been watched running (**build-and-verify** §6). It is the most consequential
predicted defect in the game today, and it exists **without any collision code at all**:

`pelota.asm:8-10` draws the ball, waits, then writes **0** to the same cell. Because the attribute
file is the only layer:

- **Bricks vanish as the ball passes through them.** They are not being destroyed — there is no
  collision code, no bounce, no counter. They are being *painted over* by the ball's erase. The ball
  flies straight along its diagonal leaving a trail of holes. → **failure-patterns**
- **The border develops gaps.** The ball is drawn at column 0, column 31 and row 0 before the bounce
  moves it away (see **collision-and-physics** §4 for why it reaches the wall cells at all), so it
  erases the border cells it bounces off.
- **The paddle survives** only because `dibujarpala` (`pala.asm:6-17`) repaints it every single
  frame. It is not immune — it is just redrawn faster than it is damaged.

**The fix, decided:** read the attribute byte under the ball before drawing, and write that byte back
on erase instead of 0. The same read doubles as the collision test — it tells you *what* was there.
**collision-and-physics** §3 owns the design; this file owns the constraint that makes it necessary.

## 3. Address map

| Range | Contents | Notes |
|---|---|---|
| `$0000-$3FFF` | Spectrum ROM | Never called. Interrupts are off (`main.asm:5`), so the ROM is entirely unused. |
| `$4000-$57FF` | Screen pixel bitmap, 6144 B | Written only by the RLE title decoder and by `PRINTCHAR`. **Never touched during gameplay.** |
| `$5800-$5AFF` | **Attribute file, 768 B** | The playfield. See §1. |
| `$5B00-$7FFF` | Free RAM, 9472 B (≈9.25 KB) | Unused. See §7. |
| `$8000-$9EF2` | Program image, 7923 B | Code + data + charset, one contiguous blob from `org $8000`. |
| `$9EF3-~$FFF0` | Free RAM | Unused. |
| `~$FFFE` downward | Stack | `ld sp,0` (`main.asm:6`); the first push wraps to `$FFFE`. |

Key addresses, verified from a fresh listing:

| Symbol | Address | Size |
|---|---|---|
| `CHARSET` | `$96EA` | 768 B (`incbin charset.bin`) |
| `SCR_CUR_PTR` / `SCR_ATTR_PTR` / `PRINT_ATTR` | `$96E5` / `$96E7` / `$96E9` | 5 B — PRINTAT state |
| `POSICION` | `$9AD5` | 2 B |
| `maplist` | `$9BAC` | 8 B |
| `map0` / `map1` / `map2` / `map3` | `$9BB4` / `$9C39` / `$9CDA` / `$9D4B` | — |
| `levelCounter` | `$9E3E` | 1 B |
| `Coord` | `$9E6E` | 2 B |
| `Vector` | `$9E70` | 2 B |

These match AUDIT.md §2 exactly. The 7-line comment header removed from `main.asm` shifted nothing,
because comments emit no bytes.

## 4. The attribute byte

| Bit | 7 | 6 | 5 4 3 | 2 1 0 |
|---|---|---|---|---|
| Meaning | FLASH | BRIGHT | PAPER (0-7) | INK (0-7) |

What each drawer actually writes:

| Entity | Expression | Value | Meaning |
|---|---|---|---|
| Border | `1*8+7` (`tablero.asm:7,18,28`) | `$0F` | blue paper, white ink |
| Paddle | `COLORPALA` = `2*8` (`pala.asm:3`) | `$10` | red paper, black ink |
| Paddle erase | `c=0` (`pala.asm:10`) | `$00` | black |
| Ball | `8*7` (`pelota.asm:8`) | `$38` | white paper, black ink |
| Ball erase | `ld (hl),0` (`pelota.asm:10`) | `$00` | black — **this is the destructive write** |
| Brick | map colour `sla a` ×3 (`PintarMapa.asm:23-25`) | colour `<< 3` | colour as PAPER |

**Two hazards anyone writing collision code must know:**

**(a) Brick colour 8 is invisible.** `8 << 3` = `$40` — that is BRIGHT set, with PAPER 0 and INK 0,
i.e. bright black on black. `map2`'s four indestructible bricks (`Mapas.asm:53`) are drawn and
cannot be seen. This is a real rendering bug, not something you caused. (The colour → attribute
shift itself is **map-data-format** §3's; this file owns the byte layout that explains why `$40` is
invisible.)

**(b) Brick colour 2 is byte-identical to the paddle.** `2 << 3` = `$10` = `COLORPALA`. So **the
attribute value alone cannot tell a brick from the paddle**, and `map0`, `map1` and `map2` all
contain colour-2 bricks. Worse, empty (`0`) and already-erased (`0`) are also indistinguishable,
because `Mostrar_Mapa` paints colour 0 over empty cells rather than skipping them.

The discriminator has to be **position, not colour**: the paddle is only ever on row 23, bricks only
occupy the rows the maps use (3-18), borders only column 0, column 31 and row 0.
**collision-and-physics** §3 turns this into a classification rule.

## 5. Cell → address arithmetic

`address = $5800 + row × 32 + column`

Two independent implementations exist, and you will meet both:

### `PosXY` — `pelota.asm:77-94`

```
IN   H = row, L = column
OUT  HL = attribute address
Preserves AF (push/pop at :78,:93). Clobbers HL only.
```

It builds `L` as `(row << 5) | col` and `H` as `(row >> 3) | $58`.

Two things to know:

- **`H` is the row and `L` is the column** — the opposite of what `pelota.asm:1`'s comment
  (`Coord: DB 16, 20 ; (fila, columna)`) leads you to expect, because `ld hl,(Coord)` puts the first
  byte in `L`. **The code wins.** → **state-and-register-contracts** §1
- The row shift uses `sra` (`:88-90`), which is an *arithmetic* shift and preserves the sign bit.
  That is safe only while row ≤ 127. With rows 0-23 it is fine, but if a bug ever puts a negative row
  in `H`, `sra` will not do what a `srl` would, and the address will land outside the attribute file.

### `CalcularAtributo` — `mensaje_inicio.asm:52-65`

```
IN   B = row, C = column
OUT  HL = attribute address
Preserves AF (push/pop at :55,:64). CLOBBERS BC — it does `ld bc,$5800` at :62.
```

**The `BC` clobber matters** — `Mostrar_Mapa` calls it inside a loop that uses both registers.
**state-and-register-contracts** §3 owns the trace and the consequences.

Note it lives in a *menu* file but is called from the map renderer, `PintarMapa.asm:11`. (AUDIT.md §3
also names `tablero.asm` as a caller; it is not one — `tablero.asm` computes addresses inline.)

The library also provides `CRtoATTR` (`L30.3 - printat.asm:72-88`), a third implementation of the
same conversion, which additionally stores the result in `SCR_ATTR_PTR`.

## 6. Pixel memory

`$4000-$57FF` is used by exactly two things:

- `Main_Pantalla` (`Pantalla_Inicio.asm`) — decodes the RLE title bitmap into it. It fills **pixels
  only** and never sets attributes, relying on whatever attribute state already exists.
- `PRINTCHAR` (`L30.3 - printat.asm:112-128`) — text output.

**Nothing touches pixel memory during gameplay.** If you find yourself writing to `$4000` in a game
routine, you have taken a wrong turn.

`CLEARSCR` (`L30.3 - printat.asm:150-155`) blanks **all 6912 bytes** of pixels *and* attributes
(`$4000-$5AFF`) — one `ld (hl),0` plus an `LDIR` of 6911. `dibujar_tablero` calls it
(`tablero.asm:2`), which is why entering a level wipes everything including the title screen.

## 7. Free RAM for new state

Collision work needs new bytes: a saved attribute under the ball, a remaining-brick counter, a lives
counter, possibly more. Two regions are available, and they behave **differently**:

| Region | Size | Initialised by loading `main.bin`? |
|---|---|---|
| `$5B00-$7FFF` | 9472 B (≈9.25 KB) contiguous, immediately above the attribute file | **No.** Outside the image. Contents are whatever the emulator left there. |
| `$9EF3` upward | ~24 KB to the stack | **No**, unless you declare it inside the image with `DB`. |
| Inline `DB` in the image | as declared | **Yes** — but only once per *load*, not once per game. |

The distinction that bites: a `DB 3` for a lives counter is initialised to 3 when the binary loads,
and **never again**. Start a second game and it holds whatever the first game left. That is exactly
the class of bug the codebase already has — nothing resets `Coord`, `Vector` or `POSICION` between
games. Anything that must be fresh per round needs an explicit reset routine regardless of where it
lives.

**state-and-register-contracts** §6 owns the declaration decision; **assembler-conventions** §9 owns
the syntax.

## 8. Before you write to `$5800-$5AFF`

- [ ] Do you know what is currently in the cell? If you are erasing, you are destroying it (§1).
- [ ] Is the address inside `$5800-$5AFF`? Rows 0-23, columns 0-31 only.
- [ ] Are you about to write over the border (column 0/31, row 0) or the paddle row (23)?
- [ ] If it's a brick, are you handling **both** of its two cells?
- [ ] Did the routine you called preserve the registers you still need — especially `BC` across
      `CalcularAtributo`, and `IX` across anything (**state-and-register-contracts**)?
- [ ] Are you writing an attribute value that collides with another entity's (`$10` is both paddle
      and colour-2 brick)? Discriminate by position.
