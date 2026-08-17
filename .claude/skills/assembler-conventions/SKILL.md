---
name: assembler-conventions
description: Use when writing or editing any .asm file in this repo — adding a routine, a constant, a data table, an INCLUDE line — or when the build errors, an instruction assembles to bytes you did not expect, or you need to know which sjasmplus syntax this tree actually uses and what naming new code should follow.
---

# Assembler conventions (sjasmplus, Arkanoid_Z80)

## 1. Toolchain and baseline

**SjASMPlus v1.23.1**, at `/usr/local/bin/sjasmplus`. The repo's historical pin to
`sjasmplus118.exe` at a dead Windows path is **gone** — `.vscode/tasks.json:7` now invokes plain
`sjasmplus`. Nothing here needs v1.18.

Current regression baseline: **0 errors, 0 warnings, 1538 compiled lines.** Treat that as the line to
hold — a new warning is a regression, and the line count must move by roughly what you added.

**Build with `./build.sh`, not raw sjasmplus.** sjasmplus exits 0 even when it emits warnings, so the
script reads the summary line and fails unless it is `Errors: 0, warnings: 0`.

**build-and-verify** §2 owns the build command, the full baseline (byte count, address range) and the
`--sld`/`--fullpath` warning. Do not duplicate them here.

## 2. Naming policy for new code

Existing identifiers are Spanish (`dibujarpala`, `nuevaposicion`, `Fin_Juego`, `POSICION`) and
comments are Spanish. **Never rename them** — a rename touches every reference, produces an enormous
diff, and buys nothing.

**New code uses English identifiers and English comments.** The codebase is accepted as
mixed-language going forward; this is a deliberate decision, not drift to be cleaned up later. A new
routine called `check_brick_hit` sitting next to `dibujarpala` is correct.

**project-orientation** §7 has the Spanish→English glossary for reading the existing names.

## 3. The column rule

**Column 0 is for labels only.** Every instruction and directive must be indented. `--dirbol` is not
used, so a directive at column 0 is parsed as a label and then fails on its operands. Verified
against v1.23.1:

```asm
DB 1,2,3            ; error: Unrecognized instruction: 1,2,3   (DB became a label)
    DB 1,2,3        ; correct
POSICION: DB 14,0   ; correct — label + directive on one line, as at pala.asm:1
```

**`EQU` is the exception**, and this tree is inconsistent about it — both spellings assemble
identically, verified:

| Form | Example | Assembles |
|---|---|---|
| Bare symbol, no colon | `LONGITUDPALA EQU 7` (`pala.asm:2`) | Yes |
| Symbol with colon | `CantidadNiveles: EQU 4` (`Partida.asm:2`) | Yes |

Both work. Match the file you are editing rather than normalising.

## 4. Directives used in this tree

| Directive | Real example | Meaning | Note |
|---|---|---|---|
| `DEVICE` | `main.asm:1` `DEVICE ZXSPECTRUM48` | Selects the 48K target | Appears once, before `org`. Never add a second. |
| `SLDOPT` | `main.asm:2` `SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION` | Enables DeZog comment directives | Spelled `ASSETION` for twenty months, which silently disabled the lot — sjasmplus strips those comments from the SLD when the `SLDOPT` info is missing. See **build-and-verify** §8. |
| `org` | `main.asm:3` `org $8000` | Sets the assembly address | **The only `org` in the tree.** Everything is one contiguous image. |
| `INCLUDE` | `main.asm:27-36` (10 lines) | Textual inclusion | See §7. |
| `incbin` | `L30.3 - printat.asm:162` | Embeds a binary inline | `charset.bin`, 768 bytes, lands at `CHARSET` = `$96EA`. |
| `EQU` | `pala.asm:2-4`, `Partida.asm:2`, `Mapas.asm:15` | Compile-time constant | **Emits no bytes.** `LONGITUDPALA EQU 7` reserves no storage. |
| `DB` / `db` | `pala.asm:1`, `pelota.asm`, `colisiones.asm`, `mensaje_inicio.asm` | Define bytes | Accepts strings: `db "ADIOS!!!!",0`. |
| `DEFB` | `Partida.asm:1`, `Mapas.asm:20` and all map rows | Define bytes | Same thing as `DB`. |
| `DW` | `pelota.asm` (`Vector`, `NewRow`, `NewCol`), `colisiones.asm` (`cand_cell`, `rebound_table`) | Define 16-bit words, little-endian | Used for the 8.8 fixed-point velocities and the rebound table. |
| `DEFW` | `Mapas.asm:14` `maplist: DEFW map0, map1, map2, map3` | Same thing as `DW` | The only `DEFW` in the tree. |

**All four families are in use.** Roughly: the game-logic files use `DB`/`DW`, and the
machine-generated map data plus `Partida.asm` use `DEFB`/`DEFW`. Match the file you are in.

Note the little-endian layout is load-bearing, not incidental: `Vector: DW -256` puts `$00` at
`Vector` and `$FF` at `Vector+1`, which is exactly what `ld de,(Vector)` then `add hl,de` needs for
signed 8.8 arithmetic. → **state-and-register-contracts** §1

**Verified absent from this tree** (grep-confirmed): no `MACRO`/`ENDM`, no `MODULE`, no `STRUCT`, no
`IFDEF`/`IF`/conditional assembly, no `REPT`/`DUP`, no `SAVESNA`/`SAVETAP`/`SAVEBIN`, no `ALIGN`, no
`DS`/`DEFS`. **There is no macro layer — do not go looking for one, and do not introduce one.** If
you need a sequence three times, write it three times or make it a routine.

## 5. Relaxed mnemonics — read this before "fixing" anything

sjasmplus accepts `add r` as shorthand for `add a,r`. One place in this tree still depends on it:

| Source | Where | Emits | Real meaning |
|---|---|---|---|
| `add b` | `pala.asm:79`, inside `nuevaposicion` | `80` | `add a,b` |

It is a **single-byte real Z80 instruction** — source-level sugar only, with no hidden cost and no
surprising side effect. It is *not portable*: pasmo and z80asm will reject it. **Do not "correct" it
to `add a,b`** — it changes nothing but the diff.

(`pelota.asm` used to carry `add h` and `add l` for the ball's integer movement. Both are gone: the
rewrite moved to 8.8 fixed point, where a step is a 16-bit `add hl,de`. New collision code writes
`add a,a` and `add hl,de` explicitly.)

The same shorthand still appears for `or`: `or l` (`pelota.asm:100,114`), `or c` (`pala.asm:95`).
In new code, writing `add a,b` / `or a,c` explicitly is fine and slightly clearer.

**`add ix,de` (`Partida.asm:56`) is a genuine Z80 instruction**, `DD 19`, two bytes. It is not sugar
and not a fake. Do not treat it as suspect.

**Fake instructions — the class to know about, even though this tree has none.** sjasmplus also
accepts register-pair loads that are *not* Z80 instructions at all and silently expands them into
several real ones, with no warning:

| Fake source | Silently becomes | Cost |
|---|---|---|
| `ld iy, ix` | `push ix` : `pop iy` | **Touches the stack** |
| `ld hl, ix` | `push ix` : `pop hl` | **Touches the stack** |
| `ld ix, de` | `ld ixh,d` : `ld ixl,e` | 4 bytes, 2 instructions |

**Grep-verified: this tree still contains none of them**, including the new collision code. Every
16-bit load here is a real instruction. Keep it that way — if you write `ld iy, ix` it will assemble
cleanly and quietly push and pop. If you need the copy, write `push ix` / `pop iy` so the cost is
visible — the same principle as `destroy_brick`'s explicit `push hl` / `pop hl` around `PosXY`
(`colisiones.asm:196,199`), where the saving is visible in the source rather than hidden in a
mnemonic.

## 6. Syntax quirks present in this tree

| Quirk | Real example | Rule |
|---|---|---|
| `:` is both label terminator **and** statement separator | `mensaje_inicio.asm` `SRL H : SRL H : SRL H`; `Pantalla_Inicio.asm` `INC IX : INC IX`; `colisiones.asm` `DW -128 : DW -256` | A second `:` on a line starts another statement; it does not define a label. Handy for keeping paired table entries on one line. |
| Two hex prefixes | `$5800` everywhere; `#40`, `#F8`, `#E0` in `L30.3 - printat.asm:47,48,83` | Both valid. **`#` appears only in the printat library; `$` in every other file.** Match the file. |
| Mixed case, no convention | `LD A, (IX)` (`PintarMapa.asm:2`) vs `ld hl, (Coord)` (`pelota.asm:56`) | Both assemble identically. Do not normalise — it buries the real change in noise. |
| Mixed indentation | 8 spaces in `pelota.asm`, 4 in `Partida.asm`, tabs in `L30.3 - printat.asm` | Match the file you are editing. |
| Labels | Code/data labels end in `:`. `L30.3 - printat.asm:158` has a space before it (`SCR_CUR_PTR : db ...`) — still valid. | Write `label:`. |
| Comments | `;` to end of line. No `//`, no block comments. | Source is UTF-8 with accented Spanish (`Código`, `dirección`, `posición`). **Leave those bytes intact** — do not let an editor re-encode the file. |

## 7. Include order

`main.asm:27-36` includes ten files. Three things follow:

1. **Forward references resolve fine.** sjasmplus runs multiple passes. `main.asm:19` calls `Juego`,
   defined in `Partida.asm`, included at line 33 — fourteen lines later. Verified: it assembles. You
   do **not** need to order includes by dependency.
2. **Reordering relocates every address.** All ten files are concatenated into one `org $8000` image,
   so swapping two `INCLUDE` lines moves `CHARSET` (`$96EA`), `POSICION` (`$9B10`), the map data
   (`$9BEA`+), `Coord`/`Vector` (`$9ECA`/`$9ECE`) and every routine entry point. This is not
   hypothetical: every one of those addresses changed when `colisiones.asm` went from 0 bytes to 408
   lines, which is why nothing should hardcode them.
3. **One ordering constraint is genuinely load-bearing**, and it is not about includes so much as
   about what `Mapas.asm` emits: `map0..map3` must stay back-to-back in memory, because
   `Partida.asm:54-56` walks off the end of one map into the next. **map-data-format** §6 owns this;
   do not re-derive it, and do not move `Mapas.asm` in the include list.

Also note a cross-file dependency that is easy to break: **`CalcularAtributo` is defined in
`mensaje_inicio.asm:52`** but called from `PintarMapa.asm:11` — a menu file is a load-bearing
dependency of the map renderer. It resolves regardless of order (see point 1), but do not be
surprised by it. (AUDIT.md §3 also lists `tablero.asm` as a caller. It is not one — `tablero.asm`
computes its addresses inline at `:5,16,27`, and its only `call` is to `CLEARSCR`.)

## 8. Where new code goes

**Collision code goes in `colisiones.asm`**, which is `INCLUDE`d last and is now the largest source
file in the tree (408 lines). No build change is needed to add to it.

For a genuinely new file:

1. Create `yourfile.asm` in the repo root. The layout is flat; there are no source subdirectories.
2. Open it with a `;` header comment naming the routine and its register contract, matching the
   better-documented existing files (`L30.3 - printat.asm:7-13` is the model).
3. Label at column 0, everything else indented, end with `ret`.
4. Add `        INCLUDE "yourfile.asm"` on its own line in `main.asm`, at the end of the list. Order
   does not matter for symbol resolution — but keep `Mapas.asm` where it is.
5. Rebuild and confirm the line count moved and warnings stayed at 0.

## 9. Data placement

This tree **interleaves mutable variables with code**, at the top of the file that owns them:

| Variable | Declared | Address |
|---|---|---|
| `POSICION` | `pala.asm:1` | `$9B10` |
| `levelCounter` | `Partida.asm:1` | `$9E74` |
| `Coord` / `CoordFrac` / `Vector` | `pelota.asm` | `$9ECA` / `$9ECC` / `$9ECE` |
| `bricks_left` / `lives` / `ball_lost` | `colisiones.asm` | `$9F51` / `$9F52` / `$9F53` |

**These addresses move whenever anything earlier in the include order changes size** — every one of
them shifted when `colisiones.asm` grew from 0 bytes. Resolve symbols from `main.lst`; the test
harness does.

That layout works — the declarations sit before the routine's entry label, so execution never falls
through them — but it scatters state across six files with no central inventory.

**The hazard to avoid: never put a `DB` in the middle of a code path.** Execution will run straight
into the data and interpret it as opcodes. Data goes after a `ret`, or before the entry label.
`rebound_table` at the very end of `colisiones.asm`, after every `ret`, is the pattern to copy.

Where *new* state (saved attribute byte, brick counter, lives) should live is a real decision with
tradeoffs — **state-and-register-contracts** §6 owns it, and **memory-map-and-playfield** §7 owns the
free-RAM ranges.

## 10. Common mistakes

- **Putting a directive at column 0** — it silently becomes a label, then errors on the operands.
- **"Fixing" `add b` / `or c` / `or l`** into `add a,b` / `or a,c` in existing lines. They already
  mean that.
- **Introducing a fake pair load** (`ld iy,ix`, `ld hl,ix`) without realising it pushes and pops.
- **Normalising case, indentation or hex prefix** across a file — huge diff, zero change.
- **Re-encoding a file** and mangling the accented Spanish comments.
- **Adding a `DB` inside a routine's code path.**
- **Reordering `INCLUDE` lines** to tidy them, or moving `Mapas.asm`.
- **Looking for a macro system.** There is none.
- **Renaming Spanish identifiers to English.** Existing names stay.
- **Assembling a file other than `main.asm`.** Every other `.asm` is an INCLUDE fragment and will
  produce `Label not found` errors and a garbage binary. → **build-and-verify**
- **Calling raw `sjasmplus` and trusting the exit code.** It exits 0 with warnings. Use `./build.sh`.
- **Hardcoding an address copied from a skill file.** Every symbol moves when any earlier file
  changes size. Read `main.lst`.

## 11. Worked example — a new routine, written correctly for this tree

Real code from `colisiones.asm`, not a sketch. Note the shape: a banner comment giving the register
contract, an English name and English comments (new code), Spanish names only where it calls existing
routines, label at column 0 and everything else indented.

```asm
; ----------------------------------------------------------------------------------------
; flip_row_velocity / flip_col_velocity - negate one 16-bit signed 8.8 component.
;   Clobbers AF, HL.
; ----------------------------------------------------------------------------------------
flip_row_velocity:
        ld hl, (Vector)
        call negate_hl
        ld (Vector), hl
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
```

Two conventions worth copying: the register contract is stated in the banner because comments in this
tree have a history of being wrong about exactly that, and any new data (`rebound_table`) goes at the
very end of the file, after every `ret`, never inside a code path.

`PosXY` preserves `AF` and takes H=row, L=column. See **state-and-register-contracts** §1 before you
trust any comment about `Coord` — the ones that used to sit on `Coord` and `Vector` were both wrong
about which byte was which.
