---
name: assembler-conventions
description: Use when writing or editing any .asm file in this repo — adding a routine, a constant, a data table, an INCLUDE line — or when the build errors, an instruction assembles to bytes you did not expect, or you need to know which sjasmplus syntax this tree actually uses and what naming new code should follow.
---

# Assembler conventions (sjasmplus, Arkanoid_Z80)

## 1. Toolchain and baseline

**SjASMPlus v1.23.1**, at `/usr/local/bin/sjasmplus`. The repo's historical pin to
`sjasmplus118.exe` at a dead Windows path is **gone** — `.vscode/tasks.json:7` now invokes plain
`sjasmplus`. Nothing here needs v1.18.

Current regression baseline: **0 errors, 0 warnings, 991 compiled lines.** Treat that as the line to
hold — a new warning is a regression, and the line count must move by roughly what you added.

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
| `SLDOPT` | `main.asm:2` `SLDOPT COMMENT WPMEM, LOGPOINT, ASSETION` | Enables DeZog comment directives | **`ASSETION` is a typo for `ASSERTION`** — assertions are currently not enabled. See **build-and-verify**. |
| `org` | `main.asm:3` `org $8000` | Sets the assembly address | **The only `org` in the tree.** Everything is one contiguous image. |
| `INCLUDE` | `main.asm:26-35` (10 lines) | Textual inclusion | See §7. |
| `incbin` | `L30.3 - printat.asm:162` | Embeds a binary inline | `charset.bin`, 768 bytes, lands at `CHARSET` = `$96EA`. |
| `EQU` | `pala.asm:2-4`, `Partida.asm:2`, `Mapas.asm:15` | Compile-time constant | **Emits no bytes.** `LONGITUDPALA EQU 7` reserves no storage. |
| `DB` / `db` | `pala.asm:1`, `pelota.asm:1-2`, `mensaje_inicio.asm:91-94` | Define bytes | Accepts strings: `db "ADIOS!!!!",0`. |
| `DEFB` | `Partida.asm:1`, `Mapas.asm:20` and all map rows | Define bytes | Same thing as `DB`. |
| `DEFW` | `Mapas.asm:14` `maplist: DEFW map0, map1, map2, map3` | Define 16-bit words, little-endian | The only `DEFW` in the tree. |

**Both the `DB` and `DEFB` families are in use here.** That differs from the sibling Tetris tree,
which uses only `DB`/`DW`. Roughly: the game-logic files use `DB`, the machine-generated map data and
`Partida.asm` use `DEFB`/`DEFW`. Match the file you are in.

**Verified absent from this tree** (grep-confirmed): no `MACRO`/`ENDM`, no `MODULE`, no `STRUCT`, no
`IFDEF`/`IF`/conditional assembly, no `REPT`/`DUP`, no `SAVESNA`/`SAVETAP`/`SAVEBIN`, no `ALIGN`, no
`DS`/`DEFS`. **There is no macro layer — do not go looking for one, and do not introduce one.** If
you need a sequence three times, write it three times or make it a routine.

## 5. Relaxed mnemonics — read this before "fixing" anything

sjasmplus accepts `add r` as shorthand for `add a,r`. This tree depends on it in three places:

| Source | Where | Emits | Real meaning |
|---|---|---|---|
| `add b` | `pala.asm:73` | `80` | `add a,b` |
| `add h` | `pelota.asm:13` | `84` | `add a,h` |
| `add l` | `pelota.asm:35` | `85` | `add a,l` |

All three are **single-byte real Z80 instructions** — this is source-level sugar only, with no hidden
cost and no surprising side effect. It is *not portable*: pasmo and z80asm will reject it. **Do not
"correct" these to `add a,b` in existing lines** — it changes nothing but the diff. In new code,
writing `add a,b` explicitly is fine and slightly clearer.

The same shorthand appears for `or`: `or l` (`pelota.asm:71,85`), `or c` (`pala.asm:89`).

**`add ix,de` (`Partida.asm:21`) is a genuine Z80 instruction**, `DD 19`, two bytes. It is not sugar
and not a fake. Do not treat it as suspect.

**Fake instructions — the class to know about, even though this tree has none.** sjasmplus also
accepts register-pair loads that are *not* Z80 instructions at all and silently expands them into
several real ones, with no warning:

| Fake source | Silently becomes | Cost |
|---|---|---|
| `ld iy, ix` | `push ix` : `pop iy` | **Touches the stack** |
| `ld hl, ix` | `push ix` : `pop hl` | **Touches the stack** |
| `ld ix, de` | `ld ixh,d` : `ld ixl,e` | 4 bytes, 2 instructions |

**Grep-verified: this tree contains none of them.** Every 16-bit load here is a real instruction.
Keep it that way — if you write `ld iy, ix` it will assemble cleanly and quietly push and pop, which
matters in a codebase whose stack discipline is already broken in two places
(**state-and-register-contracts** §4). If you need the copy, write `push ix` / `pop iy` so the cost
is visible.

## 6. Syntax quirks present in this tree

| Quirk | Real example | Rule |
|---|---|---|
| `:` is both label terminator **and** statement separator | `mensaje_inicio.asm:57` `SRL H : SRL H : SRL H`; `:59` `SLA A : SLA A : ...`; `Pantalla_Inicio.asm:20` `INC IX : INC IX` | A second `:` on a line starts another statement; it does not define a label. Used in `mensaje_inicio.asm` and `Pantalla_Inicio.asm`. |
| Two hex prefixes | `$5800` everywhere; `#40`, `#F8`, `#E0` in `L30.3 - printat.asm:47,48,83` | Both valid. **`#` appears only in the printat library; `$` in every other file.** Match the file. |
| Mixed case, no convention | `LD A, (IX)` (`PintarMapa.asm:2`) vs `ld hl, (Coord)` (`pelota.asm:6`) | Both assemble identically. Do not normalise — it buries the real change in noise. |
| Mixed indentation | 8 spaces in `pelota.asm`, 4 in `Partida.asm`, tabs in `L30.3 - printat.asm` | Match the file you are editing. |
| Labels | Code/data labels end in `:`. `L30.3 - printat.asm:158` has a space before it (`SCR_CUR_PTR : db ...`) — still valid. | Write `label:`. |
| Comments | `;` to end of line. No `//`, no block comments. | Source is UTF-8 with accented Spanish (`Código`, `dirección`, `posición`). **Leave those bytes intact** — do not let an editor re-encode the file. |

## 7. Include order

`main.asm:26-35` includes ten files. Three things follow:

1. **Forward references resolve fine.** sjasmplus runs multiple passes. `main.asm:19` calls `Juego`,
   defined in `Partida.asm`, included at line 33 — fourteen lines later. Verified: it assembles. You
   do **not** need to order includes by dependency.
2. **Reordering relocates every address.** All ten files are concatenated into one `org $8000` image,
   so swapping two `INCLUDE` lines moves `CHARSET` (`$96EA`), `POSICION` (`$9AD5`), the map data
   (`$9BB4`+), `Coord`/`Vector` (`$9E6E`/`$9E70`) and every routine entry point.
3. **One ordering constraint is genuinely load-bearing**, and it is not about includes so much as
   about what `Mapas.asm` emits: `map0..map3` must stay back-to-back in memory, because
   `Partida.asm:19-21` walks off the end of one map into the next. **map-data-format** §6 owns this;
   do not re-derive it, and do not move `Mapas.asm` in the include list.

Also note a cross-file dependency that is easy to break: **`CalcularAtributo` is defined in
`mensaje_inicio.asm:52`** but called from `PintarMapa.asm:11` — a menu file is a load-bearing
dependency of the map renderer. It resolves regardless of order (see point 1), but do not be
surprised by it. (AUDIT.md §3 also lists `tablero.asm` as a caller. It is not one — `tablero.asm`
computes its addresses inline at `:5,16,27`, and its only `call` is to `CLEARSCR`.)

## 8. Where new code goes

**Collision code goes in `colisiones.asm`.** It already exists (0 bytes) and is already `INCLUDE`d at
`main.asm:35` — **no build change is needed**, just write into the file.

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
| `POSICION` | `pala.asm:1` | `$9AD5` |
| `Coord` / `Vector` | `pelota.asm:1-2` | `$9E6E` / `$9E70` |
| `levelCounter` | `Partida.asm:1` | `$9E3E` |

That works — the declarations sit before the routine's entry label, so execution never falls through
them — but it scatters state across five files with no central inventory.

**The hazard to avoid: never put a `DB` in the middle of a code path.** Execution will run straight
into the data and interpret it as opcodes. Data goes after a `ret`, or before the entry label.

Where *new* state (saved attribute byte, brick counter, lives) should live is a real decision with
tradeoffs — **state-and-register-contracts** §6 owns it, and **memory-map-and-playfield** §7 owns the
free-RAM ranges.

## 10. Common mistakes

- **Putting a directive at column 0** — it silently becomes a label, then errors on the operands.
- **"Fixing" `add b` / `add h` / `add l`** into `add a,b` in existing lines. They already mean that.
- **Introducing a fake pair load** (`ld iy,ix`, `ld hl,ix`) without realising it pushes and pops.
- **Normalising case, indentation or hex prefix** across a file — huge diff, zero change.
- **Re-encoding a file** and mangling the accented Spanish comments.
- **Adding a `DB` inside a routine's code path.**
- **Reordering `INCLUDE` lines** to tidy them, or moving `Mapas.asm`.
- **Looking for a macro system.** There is none.
- **Renaming Spanish identifiers to English.** Existing names stay.
- **Assembling a file other than `main.asm`.** Every other `.asm` is an INCLUDE fragment and will
  produce `Label not found` errors and a garbage binary. → **build-and-verify**

## 11. Worked example — a new routine, written correctly for this tree

Illustrative. English name and comments (new code), Spanish names only where it calls existing
routines. Data after the `ret`. This would go in `colisiones.asm`.

```asm
; ----------------------------------------------------------------------------------------
; read_cell_attr - reads the attribute byte at a given cell and saves it
;   IN  - H = row (0..23), L = column (0..31)
;   OUT - A = attribute byte found there, HL = its address in $5800..$5AFF
;   Clobbers AF, HL. Preserves BC, DE, IX.
; ----------------------------------------------------------------------------------------
read_cell_attr:
        call PosXY              ; existing routine, pelota.asm:77 — H,L -> HL = attr address
        ld a, (hl)              ; read whatever is currently drawn there
        ld (saved_attr), a      ; stash it so the erase can put it back
        ret

saved_attr: DB 0                ; data AFTER the ret, never in the code path
```

`PosXY` preserves `AF` (`pelota.asm:78,93`) and takes H=row, L=column — **the opposite of what
`pelota.asm:1`'s comment claims**. See **state-and-register-contracts** §1 before you trust any
comment about `Coord`.
