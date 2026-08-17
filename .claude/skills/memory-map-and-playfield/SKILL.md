---
name: memory-map-and-playfield
description: Use when drawing, erasing or reading anything on screen, when converting a row/column to an address, when deciding where new state lives in RAM, or when something visual is going wrong — bricks disappearing, the border developing holes, a trail left behind an entity. Also read before any collision work.
---

# Memory map and the playfield

## 1. THE GOVERNING FACT

**The playfield IS the attribute file. There is no background layer. Erasing an entity by writing 0
therefore destroys whatever was underneath it.**

Everything else in this file is detail. That sentence governs the design of every drawing routine and
every collision test.

The game renders **no sprites**. Border, bricks, paddle and ball are all coloured 8×8 attribute cells
in `$5800-$5AFF`. The play area is a **32×24 character grid**. Three consequences:

- **Motion is quantised to 8 pixels.** An entity is at a cell or it is not. (The ball keeps a
  *sub-cell* position in `CoordFrac` so it can travel at varied angles, but what gets **drawn** is
  always one whole cell — the integer part.)
- **Collision is a cell-address comparison**, not a box intersection. Two things collide when they
  want the same cell.
- **Erasing is overwriting.** `ld (hl),0` does not "remove the ball" — it paints the cell black,
  whatever was there before.

Every entity's footprint:

| Entity | Cells | Where | Drawn with |
|---|---|---|---|
| Ball | 1 | `pelota.asm`, in `ball` | `ld (hl), 8*7` = `$38` |
| Paddle | 7 (`LONGITUDPALA`) on row 23 | `pala.asm` | `ld (hl),c`, c = `COLORPALA` = `2*8` = `$10` |
| Brick | 2 wide | `PintarMapa.asm` — writes the byte, `inc hl`, writes it again | colour `<< 3` |
| Border | 1 | `tablero.asm` | `1*8+7` = `$0F` |

The paddle's row: `pala.asm` loads `$5B00-32` = `$5AE0`, and `$5AE0 - $5800 = 736 = 23 × 32`, so
that is **row 23** — the bottom row of the grid.

## 2. How the game handles this — and what it used to get wrong

**The ball reads the attribute at the cell it is about to occupy, saves it in `BallSaved`, draws
itself, waits, and writes that saved byte back.** Not 0. That is the erase-restore mechanism, and it
is the reason nothing gets damaged.

**Second, and equally important: the ball is confined to rows 1-22 and columns 1-30**, so it never
lands on a border cell or the paddle row at all. It bounces one cell early. Restore alone would not
have been enough — the ball was previously *drawn* on the border cells before bouncing away.

This is what it used to do, and the symptoms are worth recognising because they were convincing:

- **Bricks vanished as the ball passed through them.** They were not being destroyed — there was no
  collision code, no bounce, no counter. They were being *painted over* by the ball's erase, leaving
  a trail of holes along its diagonal.
- **The border developed gaps**, because the ball was drawn at column 0, column 31 and row 0 before
  the bounce moved it away.
- **The paddle survived** only because `dibujarpala` repaints it every frame. It was not immune, just
  redrawn faster than it was damaged.

If any of those reappear, the erase-restore or the bounds have regressed.
`tests/test_pelota.py` asserts the attribute file is **byte-identical after 200 frames** on an empty
field, which catches it immediately. → **collision-and-physics** §2

## 3. Address map

| Range | Contents | Notes |
|---|---|---|
| `$0000-$3FFF` | Spectrum ROM | Never called. Interrupts are off, so the ROM is entirely unused. |
| `$4000-$57FF` | Screen pixel bitmap, 6144 B | Written only by the RLE title decoder and by `PRINTCHAR`. **Never touched during gameplay.** |
| `$5800-$5AFF` | **Attribute file, 768 B** | The playfield. See §1. |
| `$5B00-$7FFF` | Free RAM, 9472 B | Unused. See §7. |
| `$8000-$A0CE` | Program image, 8399 B | Code + data + charset, one contiguous blob from `org $8000`. |
| `$A0CF-~$FFF0` | Free RAM | Unused. |
| `~$FFFE` downward | Stack | `ld sp,0`; the first push wraps to `$FFFE`. |

Key addresses from the current build. **They all move whenever anything earlier in the include order
changes size — resolve them from `main.lst` rather than copying them from here:**

| Symbol | Address | Size |
|---|---|---|
| `SCR_CUR_PTR` / `SCR_ATTR_PTR` / `PRINT_ATTR` | `$96E5` / `$96E7` / `$96E9` | 5 B — PRINTAT state |
| `CHARSET` | `$96EA` | 768 B (`incbin charset.bin`) |
| `POSICION` | `$9B10` | 2 B |
| `maplist` | `$9BE2` | 8 B |
| `map0` / `map1` / `map2` / `map3` | `$9BEA` / `$9C6F` / `$9D10` / `$9D81` | — |
| `levelCounter` | `$9E74` | 1 B |
| `Coord` / `CoordFrac` / `Vector` | `$9ECA` / `$9ECC` / `$9ECE` | 2 / 2 / **4** B |
| `bricks_left` / `lives` / `ball_lost` | `$9F51` / `$9F52` / `$9F53` | 1 B each |

(AUDIT.md's §2 table lists the *pre-collision* addresses — `POSICION` at `$9AD5`, `Coord` at `$9E6E`,
image ending at `$9EF2`. Those were correct when written and are all stale now.)

## 4. The attribute byte

| Bit | 7 | 6 | 5 4 3 | 2 1 0 |
|---|---|---|---|---|
| Meaning | FLASH | BRIGHT | PAPER (0-7) | INK (0-7) |

What each drawer writes:

| Entity | Expression | Value | Meaning |
|---|---|---|---|
| Border | `1*8+7` | `$0F` | blue paper, white ink |
| Paddle | `COLORPALA` = `2*8` | `$10` | red paper, black ink |
| Ball | `8*7` | `$38` | white paper, black ink |
| Brick | map colour `sla a` ×3 | colour `<< 3` | colour as PAPER |
| Erase (paddle, destroyed brick) | — | `$00` | black |

**Attribute values are ambiguous, and this is the single most important thing to know before writing
any code that reads the screen:**

**(a) `$38` is the ball AND a colour-7 brick.** `7 << 3` = `$38` = the ball's own attribute — and
colour 7 is the **commonest brick colour in these maps**. You cannot find the ball by searching for
`$38`, and you cannot tell "brick" from "ball" by value. Locate the ball from `Coord`.

**(b) `$10` is the paddle AND a colour-2 brick.** `2 << 3` = `$10` = `COLORPALA`, and `map0`, `map1`
and `map2` all contain colour-2 bricks.

**(c) `$00` is empty AND already-destroyed.** `Mostrar_Mapa` paints colour 0 over empty cells rather
than skipping them, so the two are indistinguishable.

**(d) Colour 8 is invisible.** `8 << 3` = `$40` — BRIGHT set, PAPER 0, INK 0: bright black on black.
`map2`'s four indestructible bricks are drawn and cannot be seen. A real rendering bug that predates
the collision work; do not report it as a regression. → **map-data-format** §3

The discriminator has to be **position, not colour**: the paddle is only ever on row 23, the border
is only column 0, column 31 and row 0, and bricks live in between. `classify_cell` implements exactly
that, and its ordering is why bricks must not be drawn on row 23.
→ **collision-and-physics** §5

## 5. Cell → address arithmetic

`address = $5800 + row × 32 + column`

Three implementations exist and you will meet all of them:

### `PosXY` — `pelota.asm`

```
IN   H = row, L = column
OUT  HL = attribute address
Preserves AF. Clobbers HL only.
```

Builds `L` as `(row << 5) | col` and `H` as `(row >> 3) | $58`.

- **`H` is the row and `L` is the column.** `ld hl,(Coord)` puts `Coord`'s byte 0 in `L`, and byte 0
  is the column. → **state-and-register-contracts** §1
- The row shift uses `sra` (an *arithmetic* shift, preserving the sign bit), which is safe only while
  row ≤ 127. Fine for rows 0-23, but a negative row in `H` would land outside the attribute file.

### `CalcularAtributo` — `mensaje_inicio.asm`

```
IN   B = row, C = column
OUT  HL = attribute address
Preserves AF. CLOBBERS BC -- it does `ld bc,$5800`.
```

**The `BC` clobber matters** — `Mostrar_Mapa` calls it inside a loop that uses both registers.
→ **state-and-register-contracts** §3

It lives in a *menu* file but is called from the map renderer. (AUDIT.md §3 also names `tablero.asm`
as a caller; it is not one — `tablero.asm` computes its addresses inline.)

### `CRtoATTR` — `L30.3 - printat.asm`

Same conversion, and additionally stores the result in `SCR_ATTR_PTR`. **Preserves `BC`**, unlike
`CalcularAtributo`, so prefer it when you need `BC` to survive.

## 6. Pixel memory

`$4000-$57FF` is used by exactly two things:

- `Main_Pantalla` — decodes the RLE title bitmap into it. It fills **pixels only** and never sets
  attributes, relying on whatever attribute state already exists (which is why the title screen shows
  in whatever colours the ROM left behind).
- `PRINTCHAR` — text output. It writes the character's 8 pixel rows **and** sets that cell's
  attribute from `PRINT_ATTR`, which is how on-screen messages can be detected from the attribute
  file alone.

**Nothing touches pixel memory during gameplay.** If you find yourself writing to `$4000` in a game
routine, you have taken a wrong turn.

`CLEARSCR` blanks **all 6912 bytes** of pixels *and* attributes. `dibujar_tablero` calls it, which is
why entering a level wipes everything including the title screen.

## 7. Free RAM for new state

| Region | Size | Initialised by loading `main.bin`? |
|---|---|---|
| `$5B00-$7FFF` | 9472 B contiguous, immediately above the attribute file | **No.** Outside the image; holds whatever the emulator left there. |
| `$A0CF` upward | ~24 KB to the stack | **No**, unless declared inside the image with `DB`. |
| Inline `DB` in the image | as declared | **Yes** — but only once per *load*, not once per game. |

The distinction that bites: a `DB 3` for a lives counter is 3 when the binary loads and **never
again**. That is why `reset_game` writes every such byte explicitly.
→ **state-and-register-contracts** §6

`$5B00+` becomes the right answer only if a shadow brick map is ever adopted, where the size makes
inline declaration wasteful. → **collision-and-physics** §11

## 8. Before you write to `$5800-$5AFF`

- [ ] Do you know what is currently in the cell? If you are erasing, you are destroying it (§1).
- [ ] Is the address inside `$5800-$5AFF`? Rows 0-23, columns 0-31 only.
- [ ] Are you about to write over the border (column 0/31, row 0) or the paddle row (23)?
- [ ] If it's a brick, are you handling **both** of its two cells?
- [ ] Did the routine you called preserve the registers you still need — especially `BC` across
      `CalcularAtributo`, and `IX` across anything?
- [ ] Are you identifying an entity by its attribute value? Don't — `$38` and `$10` are each two
      different things (§4). Discriminate by position.
