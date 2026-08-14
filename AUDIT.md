# Arkanoid_Z80 — Incoming Engineer Audit

Audit date: 2026-08-12. HEAD: `561cc23` (`develop`), tag `pre-audit`. Investigation only; no source
files were modified. Verification was done by reading source, the committed `.lst` listings, the full
git history, and by assembling the project to a scratch directory.

---

## 1. Platform & toolchain

### Target platform — confirmed

**ZX Spectrum 48K.** Confirmed from three independent places in the repo, not assumed:

- `main.asm:8` — `DEVICE ZXSPECTRUM48`.
- `.vscode/launch.json` — DeZog `zsim` config with `"memoryModel": "ZX48K"`, `ulaScreen`,
  `zxKeyboard`, `zxBeeper`, `vsyncInterrupt: true`.
- The code itself: writes to `$4000` (pixel bitmap) and `$5800–$5AFF` (attribute file), and reads
  keyboard half-rows via `IN A,(C)` on ports `$FDFE` / `$7FFE`. These are 48K ULA addresses.

The program is a raw binary loaded at `$8000` with `execAddress 0x8000` and `topOfStack 0`. There is
no tape/TAP/SNA/Z80 loader, no BASIC stub, and no `.tap` build step — it is only runnable by having a
debugger/emulator load the raw image at `$8000` and jump there.

### Assembler & dialect

**sjasmplus**, and the source uses sjasmplus-specific dialect, so it is not portable to pasmo/z80asm
without edits:

- `DEVICE ZXSPECTRUM48` and `SLDOPT COMMENT ...` (`main.asm:8-9`) are sjasmplus directives.
- Multi-statement lines with `:` as a separator (`mensaje_inicio.asm:57`, `59`;
  `Pantalla_Inicio.asm:20`).
- `add b` / `add hl,de` mixed forms — sjasmplus accepts `add b` for `add a,b`
  (`pala.asm:73`, `pelota.asm:13`).
- SLD (source-level debug) output for DeZog.

`.vscode/tasks.json` pins `sjasmplus118.exe` — **version 1.18, Windows-only, absolute path on the
original author's machine** (`D:/UFV/Arquitectura/sjasmplus118.exe`). That path does not exist here.

### How it is built today

The only build definition is the VS Code task in `.vscode/tasks.json`:

```
sjasmplus118.exe --lst=<file>.lst --sld=<file>.sld --raw=<file>.bin --fullpath <file>
```

Two problems with it, both visible in the committed artifacts:

1. It builds `${file}` — **whatever source file currently has editor focus**, not `main.asm`. There
   is no fixed entry point. If `pelota.asm` is focused when you press build, you get a broken
   `pelota.bin`.
2. That has actually happened, repeatedly, and the broken output is committed. `Partida.lst`,
   `pelota.lst`, `pala.lst`, `PintarMapa.lst`, `mensaje_inicio.lst`, `Pantalla_Inicio.lst` are
   standalone builds of include-fragments, riddled with `error: Label not found: dibujar_tablero`,
   `Label not found: PosXY`, etc., with all `call` targets assembled as `CD 00 00`. The matching
   `.bin` files (e.g. `Partida.bin`, 34 bytes) are garbage and must never be loaded.

The only meaningful build artifacts are **`main.bin` / `main.lst` / `main.sld`**.

There is no Makefile, no shell/batch script, no CI, and no `.gitignore` — every build artifact is
committed, which is why 5 of the 7 commits are dominated by thousands of lines of `.lst`/`.sld` churn.

**Verified build status:** the project assembles cleanly from `main.asm` with a modern sjasmplus
(v1.23.1, available on this machine as `sjasmplus`): *0 errors, 0 warnings, 998 lines*. The produced
7923-byte image is **byte-identical to the committed `main.bin`**, so the committed artifact is
current and the source tree is self-consistent. Nothing here requires the pinned v1.18.

To build on this machine without touching the repo's committed artifacts:

```
sjasmplus --raw=<outdir>/main.bin --lst=<outdir>/main.lst main.asm
```

### How it is run / tested

Running is via **DeZog** (VS Code Z80 debug extension) with the internal `zsim` simulator, per
`.vscode/launch.json`. Note that `launch.json` also uses `${fileBasenameNoExtension}` for both the
`.sld` and the loaded `.bin` — so **debugging also depends on `main.asm` being the focused file**.
With any other file focused, DeZog loads the wrong (broken) binary.

**There is no test procedure of any kind.** No unit tests, no assertions, no golden screenshots, no
harness, no regression checks. Despite `SLDOPT COMMENT WPMEM, LOGPOINT, ASSETION` on `main.asm:9`
enabling DeZog's watchpoint/logpoint/assertion comment syntax, there is not a single `WPMEM`,
`LOGPOINT` or `ASSERTION` comment anywhere in the sources. (The directive also misspells `ASSERTION`
as `ASSETION`, so that half would not have worked anyway.)

Testing today is: build, launch the simulator, look at the screen, press keys. Nothing more. Any
statement about whether a mechanic "works" — including everything in section 5 below — comes from
reading the code, because there is no artifact in the repo that records a behavioural result.

---

## 2. Memory map & hardware interfaces

### Address map

| Range | Contents | Notes |
|---|---|---|
| `$0000–$3FFF` | Spectrum ROM | Never called. Interrupts are off; the ROM is unused entirely. |
| `$4000–$57FF` | Screen pixel bitmap (6144 B) | Written by the RLE splash and by `PRINTCHAR`. |
| `$5800–$5AFF` | Attribute file (768 B) | **This is the game's real playfield** (see below). |
| `$5B00–$7FFF` | Free RAM | Unused. |
| `$8000–$9EF2` | Program image (7923 B) | Code + data + charset, all one blob. |
| `$9EF3–~$FFF0` | Free RAM | Unused. |
| `~$FFFE` downward | Stack | `ld sp,0` at `main.asm:13`; first push lands at `$FFFE`. |

Key data addresses (from `main.lst`):

| Symbol | Addr | Size | Purpose |
|---|---|---|---|
| `RLEData` | `$803B` | ~5.6 KB | RLE-compressed title screen bitmap |
| `CHARSET` | `$96EA` | 768 B | `incbin "charset.bin"` — 8×8 font, 96 chars |
| `SCR_CUR_PTR` / `SCR_ATTR_PTR` / `PRINT_ATTR` | `$96E4`+ | 5 B | PRINTAT library state |
| `POSICION` | `$9AD5` | 2 B | Paddle column, and **previous** paddle column |
| `maplist` | `$9BAC` | 8 B | `DEFW map0,map1,map2,map3` |
| `map0..map3` | `$9BB4`, `$9C39`, `$9CDA`, `$9D4B` | — | Level data, laid out contiguously |
| `levelCounter` | `$9E3E` | 1 B | Levels completed this run |
| `Coord` | `$9E6E` | 2 B | Ball position (row, col) |
| `Vector` | `$9E70` | 2 B | Ball velocity (drow, dcol) |

All mutable game state is **eight bytes** (`POSICION`, `levelCounter`, `Coord`, `Vector`), stored
inline in the code image. There is no zero-page-style variable block and no state-reset routine.

### The playfield is the attribute file

This is the single most important architectural fact about the codebase, and it is documented
nowhere. **The game does not render sprites.** Everything in play — bricks, borders, paddle, ball —
is drawn as coloured 8×8 attribute cells in `$5800–$5AFF`. The play area is therefore a
**32×24 character grid**, and every entity is exactly one or more whole cells:

- Ball = 1 cell (`pelota.asm:8`, attribute `8*7` = white paper).
- Paddle = 7 cells on row 23 (`pala.asm:2`, `21` — `$5B00-32` = `$5AE0` = row 23).
- Brick = 2 cells wide (`PintarMapa.asm:27-30` writes the colour twice).
- Border = 1 cell (`tablero.asm`).

The consequences are pervasive: motion is quantised to 8 pixels, collision is a cell-address
comparison rather than a box intersection, and — critically — **erasing an entity means writing 0
over whatever was underneath it**, because there is no background layer to restore. See section 5.

Pixel memory (`$4000–$57FF`) is used only by the title-screen RLE decoder and by text printing, and
is never touched during gameplay.

### Memory-mapped / port I/O

Only the ULA keyboard port is used. Two half-rows:

| Port | Keys (bits 0→4) | Used by |
|---|---|---|
| `$FDFE` | A, S, D, F, G | `pala.asm:35` (gameplay: A/D move, F advances level), `mensaje_inicio.asm:78` (S = yes) |
| `$7FFE` | Space, SymShift, M, N, B | `mensaje_inicio.asm:74` (N = no) |

No border/beeper writes (`OUT ($FE)`) anywhere, so there is **no sound** and the border is never set,
despite `zxBeeper` being enabled in the DeZog config.

### Interrupts

**None.** `di` at `main.asm:12` is executed at startup and interrupts are never re-enabled. There is
no `IM 1`/`IM 2` setup, no vector table, no ISR, no `halt`. `launch.json` sets `vsyncInterrupt: true`
but the program ignores it.

This means: no frame sync, no clock, no `HALT`-based pacing.

### Timing dependencies

All pacing is **busy-wait delay loops**, and all of them are calibrated by feel:

| Loop | Iterations | ≈ T-states | ≈ ms @3.5 MHz |
|---|---|---|---|
| `Esperar_pelota` (`pelota.asm:66`) | `$1100` = 4352 | ~113,000 | ~32 |
| `esperar` (`pala.asm:85`, `CONTADOR=$03FF`) | 1023 | ~26,600 | ~7.6 |
| `teclado` poll (`pala.asm:33`) | up to 255 | ~15,000 | ~4.3 |

Total frame ≈ **44 ms, i.e. ~23 fps**, with the ball advancing one 8-pixel cell per frame.

Three things follow, and all three are timing-critical dependencies the code silently relies on:

1. **Nothing is synchronised to the raster.** Attribute writes land mid-scan, so the display tears.
2. **The ball is only visible for part of each frame.** `ball` draws, waits ~32 ms, then *erases*
   (`pelota.asm:8-10`) and returns; the remaining ~12 ms of the frame is spent in `teclado` and
   `esperar` with the ball erased. That is a ~27% off-duty cycle — visible flicker, by design.
3. **Ball and paddle speed are coupled to the same frame loop** but tuned by two unrelated constants
   in two files. Changing `CONTADOR` to make the paddle more responsive also speeds up the ball.

Everything above is CPU-clock-dependent. On a 128K machine or an accelerated emulator, the game
speeds up proportionally.

---

## 3. Module inventory

Include order is fixed by `main.asm:33-42` and matters — `Fin_Juego`'s level advance depends on the
data layout it produces (see §5.5).

### `main.asm` — entry point — **working**
Sets `di` / `sp=0`, shows title, then an endless `flujo_juego` loop: reload `IX`, `CALL Juego`, repeat.
No `halt`, no exit path. 4 lines of real code; the rest is `INCLUDE`s.

### `Pantalla_Inicio.asm` — title screen — **complete and working**
`Main_Pantalla` decodes an RLE stream (`RLEData`) into the pixel bitmap at `$4000`. Format is
(count, byte) pairs, terminated by count 0. Clean, self-contained, no dependencies. Note it fills
pixels only and never sets attributes — it relies on whatever attribute state exists.

### `L30.3 - printat.asm` — text library — **complete and working (shared, do not edit)**
Third-party course library (Daniel León, UFV) shared with the team's Tetris project. Provides
`PRINTAT`, `PRINTSTR`, `PRINTCHAR`, `CRtoSCREEN`, `CRtoATTR`, `INK2PAPER`, `CLEARSCR`, and the
charset. Two inherited limitations worth knowing: `PRINTCHAR` advances the cursor with `INC (HL)` on
the pointer's **low byte only** (`printat.asm:125,127`), so strings cannot wrap a line or cross a
256-byte screen-third boundary; and `CLEARSCR` blanks all 6911 bytes of screen+attributes.

### `mensaje_inicio.asm` — menu screens + `CalcularAtributo` — **broken (one path)**
Contains `Pantalla_Ini` (start prompt), `Pantalla_Reinicio` (restart prompt), `FinDelJuego`
(quit screen), the shared `CalcularAtributo` helper, and `EsperarTecla`/`LeerTecla`/`SoltarTecla`.

- `Pantalla_Ini` / `Pantalla_Reinicio` — working.
- **`FinDelJuego` is broken.** It clears the screen, prints `ADIOS!!!!`, and then **falls straight
  through into `CalcularAtributo`** (`mensaje_inicio.asm:48 → 52`). `CalcularAtributo` ends in `RET`,
  which pops `LeerTecla`'s return address and lands back inside `EsperarTecla`, which resumes waiting
  for a key over the goodbye screen. **Pressing "N" does not quit the game** — it shows the goodbye
  message and then silently keeps polling; pressing "S" afterwards starts a game. There is no `halt`
  or infinite loop to terminate on.
- `Pantalla_Reinicio` ends with `call flujo_juego` (`mensaje_inicio.asm:39`) — a `call` into a label
  that never returns. See "stack" note below.

### `tablero.asm` — playfield border — **working, one off-by-one**
`dibujar_tablero` clears the screen and paints left border (col 0, rows 0–23), right border (col 31,
rows 0–23), top border (row 0). The top loop uses `ld b,32` starting at `$5801` (`tablero.asm:27-29`),
so it writes 32 cells from col 1 — one cell too many, spilling into row 1 col 0. Harmless in practice
because that cell is already left-border colour, but it is wrong. There is deliberately **no bottom
border** (that is the paddle's row).
Trailing `fin_dibujar_tablero: jr fin_dibujar_tablero` at line 38 is dead code — unreferenced,
unreachable.

### `Mapas.asm` — level data — **complete and working (data)**
Four maps, machine-generated by a Python converter (Daniel León, UFV). Per-row encoding is documented
in the file header: `Y, count, colour...`, `$FF` terminates. Colour 8 = indestructible, 0 = empty.

**Undocumented and important:** each map's *byte 0* is a header the file comment does not describe.
Verified by counting: map0's is 82 and map0 contains exactly 82 destructible bricks; map2's is 78 and
map2 has 82 non-empty cells of which 4 are colour-8 indestructible → 78 destructible. **Byte 0 is the
destructible-brick count — exactly the value level-completion detection needs.** `Mostrar_Mapa` reads
it and throws it away (see below).

`maxLevelsMask: EQU 3` (line 15) is defined and never used anywhere — leftover from an intended
mask-based level wrap.

### `PintarMapa.asm` — map renderer — **working, with defects**
`Mostrar_Mapa` walks the map at `IX` and paints bricks 2 cells wide starting at column 1.

- **Discards the brick count.** `LD A,(IX) / INC IX` (lines 2-3) loads byte 0 into `A` and
  immediately overwrites `A` on line 6. The one number needed for win detection is read and dropped.
- **Colour 8 renders invisible.** Line 23-25 does `sla a` ×3 to shift colour into the paper bits.
  For colour 8 that gives `$40` — bit 6, which is BRIGHT, with paper 0 and ink 0. Indestructible
  bricks in `map2` are drawn as **bright black on black**, i.e. invisible.
- Dead code: `call Pala_Juego` on line 40 sits immediately after an unconditional `jr Fila` and is
  unreachable.
- Leaves `IX` pointing **at** the `$FF` terminator on exit. `Fin_Juego` depends on this; see §5.5.

### `pala.asm` — paddle + keyboard + frame delay — **working**
The most-revised file in the repo (touched by all 5 content commits).

- `dibujarpala` / `dibujarpalacolor` — erase-at-old / draw-at-new, 7 cells on row 23. Working.
- `teclado` — polls `$FDFE`, returns direction in `B`. **Has a hang bug** (see §5.4).
- `nuevaposicion` — applies `B` to `POSICION` with bounds checks. Working; bounds are correct.
- `esperar` — frame delay. Working.

`POSICION+1` is a shadow "previous position" used for erasure, initialised to 0 and used as a
sentinel; since column 0 is never a legal paddle position, the sentinel is safe.

### `pelota.asm` — ball — **incomplete**
`ball` draws the ball, delays, erases, then advances `Coord` by `Vector` with wall bounces on all
four edges. `PosXY` converts (row, col) → attribute address; `Esperar_pelota` is the frame delay.

The movement and wall-bounce arithmetic works. What is missing is everything else: **no collision
with the paddle, no collision with bricks, no ball loss.** Details in §5.

Comment/code mismatch: `Coord: DB 16, 20` is annotated `(fila, columna)`, but `ld hl,(Coord)` puts
16 in `L` and 20 in `H`, and `PosXY` treats `H` as the row. The ball actually starts at **row 20,
column 16**, not row 16 column 20. Likewise `Vector` is annotated `(X, Y)` but the first byte is the
row delta. Fix the comments before anyone builds on them.

### `Partida.asm` — game loop & level flow — **broken**
`Juego` draws board+map then runs `Pala_Juego`: `ball → teclado → nuevaposicion → dibujarpala →
esperar → repeat`. The `;mirar si fin partida` comment on line 10 marks where end-of-round detection
was meant to go and never went.

`Fin_Juego` advances the level; `ReinicioJuego` resets and shows the restart screen. Both are only
reachable by **pressing F** — there is no automatic progression. See §5.5 and §5.6.

### `colisiones.asm` — **stub, 0 bytes**
Created empty in `43848fe`, `INCLUDE`d by `main.asm:42`, still empty at HEAD. This is where
ball↔paddle and ball↔brick collision was supposed to live. **The single largest gap in the project.**

### Cross-module coupling (mostly undocumented)

| Coupling | Where | Risk |
|---|---|---|
| **`IX` is a global "current map pointer"** held across the entire game loop | `main.asm:24` → `Mostrar_Mapa` → `Fin_Juego` | Any routine that clobbers `IX` corrupts level state. `PRINTAT` uses `IX` for its string pointer — safe only because it is never called during play. |
| **`Fin_Juego` relies on `map0..map3` being contiguous in memory** | `Partida.asm:21` | `add ix,1` past the `$FF` terminator only reaches the next map because `Mapas.asm` lays them back-to-back. Reordering or separating the maps silently breaks level progression. |
| **`maplist` table is effectively vestigial** | `Mapas.asm:14` | Read once at `main.asm:24`, never indexed again. The pointer table is dead weight that looks live. |
| **Map byte 0 (brick count) is undocumented** | `Mapas.asm:20` etc. | Read and discarded by `Mostrar_Mapa`; the file header comment does not mention it. |
| `CalcularAtributo` lives in `mensaje_inicio.asm` but is used by `tablero.asm` and `PintarMapa.asm` | — | Include-order dependency; a menu file is a load-bearing dependency of the renderer. |
| `Fin_Juego` (Partida) is called from `teclado` (pala) | `pala.asm:47` | Level progression is invoked from the keyboard handler, and never returns to it — see stack note. |
| Frame timing split across `CONTADOR` (pala) and `$1100` (pelota) | — | Two files must be edited in sync to retune speed. |

**Stack discipline is broken in two places.** `teclado` does `call Fin_Juego`, and `Fin_Juego` exits
via `jr Juego` (`Partida.asm:30`) — so the return addresses for `call teclado` *and* `call Fin_Juego`
are left on the stack forever. Likewise `Pantalla_Reinicio` ends with `call flujo_juego`
(`mensaje_inicio.asm:39`), which never returns. Roughly 4 bytes leak per level change and a few more
per restart. With `SP=0` and ~24 KB of headroom above the code this takes on the order of a thousand
game cycles to matter, so it is not a practical crash risk — but it is a genuine structural defect and
it will bite anyone who adds recursion or a deeper call tree.

---

## 4. Dead ends and history

Seven commits, 29 Nov – 12 Dec 2024, two author identities for the same person (`Eduardo C
<9101265@alumnos.ufv.es>` and `SpeedRD <eduardojcabreja@gmail.com>`). `main.asm:1-5` credits four
students with participation percentages, one of them at **0%**. No branches other than `develop`; no
merges, no reverts in git terms. All "reverting" happened by overwriting files in place.

| Commit | Date | What actually happened |
|---|---|---|
| `8ef7f41` | Nov 29 | Empty initial commit. |
| `2532582` | Nov 29 | "Commit Inicial" — the whole starting skeleton: printat library, title screen, maps, board, first paddle, and the course template artifacts. |
| `7d39c74` | Nov 30 | "Mapas cambiando, pala medio corregida" — map switching wired up; `Partida.asm` created. |
| `c380a80` | Dec 1 | "Pala corregida" — `borrarpala` rewritten to use `add hl,de`/`djnz`. |
| `63aa40f` | Dec 1 | "Cambio de mapa corregido, reinicio de juego funcionando" — `levelCounter` introduced. |
| `43848fe` | Dec 11 | "Nueva pala para corregir, pelota para integrar" — paddle **rewritten from scratch**; ball added; `colisiones.asm` created empty. |
| `561cc23` | Dec 12 | "Pelota y Pala implementada, falta optimizar el codigo de la pelota" — ball integrated into the game loop. |

### Abandoned: the entire first paddle implementation

`43848fe` deleted ~124 lines and replaced them with 88. The **old paddle owned the game loop**: it
had its own `di / ld sp,0` (duplicating `main.asm`), its own `leerteclas` polling loop, and its own
`mueveizquierda`/`muevederecha`/`parademover` state machine that never returned — the game *was*
`posicionpala`. That design made a ball impossible, which is presumably why it was replaced when the
ball arrived. The replacement is a proper `teclado → nuevaposicion → dibujarpala` pipeline that
returns each frame.

Two things were lost in the rewrite and are worth knowing:

- **`LIMITEDERECHO` / `LIMITEIZQUIERDO` named constants disappeared.** The old code had
  `LIMITEDERECHO EQU 31 - LONGITUDPALA` and `LIMITEIZQUIERDO EQU 1`. The new `nuevaposicion` inlines
  `32-LONGITUDPALA` and an implicit zero test. Same behaviour, less legible.
- **A revealing comment was deleted**, repeated three times in the old `leerteclas`:
  *"hay un problema en el dzog y me lo guarda negado, por eso en el siguiente ponemos `z` y no `nz`"*
  ("there's a problem in DeZog and it stores it negated, so we use `z` instead of `nz`"). This was a
  **misdiagnosis**. The Spectrum keyboard is active-low: a pressed key reads 0. The old code's `jr z`
  was correct and DeZog was innocent. The rewrite silently switched to the equally correct
  "test-all-bits-then-dispatch-on-nz" idiom (`and $1F / cp $1F`), so the bug is gone — but the
  original confusion tells you the keyboard convention was never properly understood, and that is
  worth remembering when reading `teclado`.

### Abandoned: `COORD: DB 0`

The old `pala.asm` declared a `COORD` variable that was never read or written. Removed in `43848fe`.

### Abandoned: per-brick skip logic in the map renderer

`7d39c74` deleted a commented-out block from `PintarMapa.asm` — an `or a / jr z, Salto_Ladrillo`
zero-colour skip plus `push bc/push de` register saving and a `Salto_Ladrillo` column-advance path.
The author tried to *skip* empty cells and gave up, settling on painting colour 0 over them instead.
That decision is why the renderer cannot distinguish "empty" from "erased" — relevant to §5.2.

### Abandoned: `MapaJuego.asm`

Created empty in `2532582`, deleted in `7d39c74`. Never had content. `colisiones.asm` is the same
pattern one file later — and that one is still there, still empty.

### Reverted-by-overwrite: `fin: jr fin`

`43848fe` added an infinite-loop halt at the end of `pala.asm`; `561cc23` deleted it again. The
project currently has **no halt state at all**.

### Reverted-by-overwrite: the debug restart call

`7d39c74` added `call Pantalla_Reinicio` to `main.asm` with the comment *"esta pantalla funciona, se
puede probar pulsando f dentro del juego"* ("this screen works, you can test it by pressing F inside
the game"). `63aa40f` removed it. **This is the origin of the F key** — it was a debug hook for
testing the restart screen, and it was never replaced by real completion detection. It is still the
only way to advance a level.

### Ball tuning, one commit apart

`561cc23` changed `ball`'s terminal `jr ball` (a self-contained infinite loop — the ball, like the
old paddle, originally owned the whole loop) to `ret`, and dropped `Esperar_pelota` from `$1F00` to
`$1100`. In the same commit `LONGITUDPALA` went 4 → 7 and `CONTADOR` `$01FF` → `$03FF`. So the
current speed/size numbers are one evening's worth of eyeball tuning, done the day before the
project stopped.

### Commit messages that admit known problems

- `7d39c74` — *"pala medio corregida"* ("paddle half-fixed").
- `43848fe` — *"Nueva pala **para corregir**, pelota **para integrar**"* ("new paddle **to be
  fixed**, ball **to be integrated**"). Both were declared unfinished when committed.
- `561cc23` (HEAD) — *"**falta optimizar** el codigo de la pelota"* ("**still need to optimise** the
  ball code"). **The project's final commit message states the ball is unfinished.**

### Build-config churn

`.vscode/tasks.json` had its `command` path edited in 4 of 7 commits, ping-ponging between
`C:/UFV Tercero~Cuarto/Arquitectura/` and `D:/UFV/Arquitectura/` — two machines fighting over a
hardcoded absolute path. The `.lst` files preserve both, plus a third stale directory name
(`Pantalla_InicioyFinal`). This is pure noise, and the reason a proper build script is the cheapest
first improvement anyone could make here.

### Orphaned artifacts

`plantilla.bin` / `plantilla.lst` / `plantilla.sld` are committed, but **`plantilla.asm` does not
exist in the repo and never did**. They are build output from the course-provided template file, which
was assembled once and then renamed to `main.asm`. Dead weight; the `.lst` still references
`C:\UFV Tercero~Cuarto\Arquitectura\Pantalla_InicioyFinal\plantilla.asm`.

`.tmp/disasm.list` is a committed empty DeZog scratch file.

---

## 5. Known trouble spots

Ordered by severity. Every item below was derived by reading code; **none of it has been observed
running**, because no test procedure exists (§1).

### 5.1 — Ball↔paddle collision: **does not exist. The ball cannot be lost.** (critical)

`colisiones.asm` is empty. Nothing in `ball` or the game loop reads `POSICION`. The ball has no idea
the paddle exists.

Worse, the bottom wall is a *bouncing* wall. `pelota.asm:16-21`: when the row would reach 24, the
vector is negated and the row is forced to 22. So the ball reflects off the floor unconditionally,
whether or not the paddle is there.

**The paddle is decorative.** You cannot miss, you cannot lose, and the rebound angle question is
moot — there is no rebound-angle code to be wrong. The ball travels a fixed 45° diagonal forever.

This also means there is nothing for a "lives" system to hook into; see §5.6.

### 5.2 — Ball↔brick collision: **does not exist, but the ball erases bricks anyway** (critical)

There is no brick lookup, no brick-count decrement, no bounce off a brick. But `ball` erases itself by
writing attribute 0 to its cell (`pelota.asm:10`) — and because the playfield *is* the attribute file
with no background layer (§2), **that write destroys whatever was in that cell**.

The observable result is a convincing-looking bug: bricks vanish as the ball passes through them.
They are not being "destroyed" — they are being painted over, with no bounce, no scoring, and no
count. The ball flies straight through the brick field on its diagonal, leaving a trail of holes.

The same mechanism damages the walls: the ball is drawn at column 0, column 31 and row 0 (traced
below), so **it erases the border cells it bounces off**, chewing gaps in the frame drawn by
`dibujar_tablero`. The paddle survives only because `dibujarpala` repaints it every frame.

Anyone implementing this properly needs to solve the underlying problem first: **read the attribute
cell before drawing the ball and restore it after**, or keep a separate brick map in RAM. The erase
strategy has to change before collision can be added at all.

### 5.3 — Wall bounce: works, but every bounce loses a cell and clips the border (medium)

The four wall bounces (`pelota.asm:13-55`) are structurally correct — detect the out-of-range value,
negate the vector component, force a position back in range — but the forced positions are each one
cell too far in:

| Edge | Detected at | Forced to | Should be |
|---|---|---|---|
| Bottom | row 24 | row 22 | 23 |
| Top | row −1 | row 1 | 0 |
| Right | col 32 | col 30 | 31 |
| Left | col −1 | col 1 | 0 |

Because the bounce forces a value 2 away instead of 1, **the ball skips a cell on every bounce** — a
visible stutter, and the reflection is not geometrically a mirror.

Tracing the actual displayed range: the ball *is* drawn at rows 0–23 and columns 0–31, i.e. **on top
of the border cells**, before the bounce moves it away. That is what causes the border erosion in
§5.2. Since column 0/31 and row 0 are walls, the ball should bounce at 1..30 / 1.. and never occupy
them.

Note also that the checks use `jr nz` on an exact equality (`cp 24`, `cp 32`) rather than a range
comparison. That is safe *only* because the step is exactly ±1. **Any future change to ball speed
(step size ≥ 2) makes the ball skip the boundary value and escape the playfield entirely**, wrapping
into arbitrary attribute addresses or out of the attribute file. This is the single most dangerous
piece of latent fragility in the ball code.

### 5.4 — Paddle: bounds are correct; the keyboard handler can hang the game (medium)

Good news first: `nuevaposicion` (`pala.asm:68-82`) is correct. It rejects a move to column 0
(`ret z` after `add b`) and rejects `>= 32-LONGITUDPALA` = 25 (`ret nc`), giving a legal range of
columns 1–24 with a 7-cell paddle occupying 1–30. That exactly respects the borders at columns 0 and
31. No off-by-one. The `ret nc` also correctly catches the wrap-to-255 case.

The bug is in `teclado` (`pala.asm:32-66`). The dispatch chain tests F, then A, then D. If a key on
the `$FDFE` half-row is held that is **neither A, D nor F — i.e. S or G** — control reaches
`teclado4`, finds D not pressed, and does `jr teclado1` **back to the polling loop without
decrementing `D`**. The loop only exits when `D` hits zero or a recognised key is found, so:

**Holding S or G freezes the game** — the ball stops, the paddle stops — until the key is released.
S is one row over from A and D on a QWERTY keyboard, so this is easy to trigger by accident.

Secondary: at `tecladofin` the delay loop runs `D` times, where `D` is however far the *polling* loop
had already counted down. Paddle movement speed therefore depends on how long the key took to be
detected — inconsistent, though not broken.

Also: the paddle moves at most one cell per frame regardless of how long a key is held.

### 5.5 — Level transitions: no completion detection; advance is manual and structurally fragile (critical)

**There is no win condition.** Nothing counts bricks, nothing detects an empty playfield, nothing
calls `Fin_Juego` automatically. The `;mirar si fin partida` ("check for end of round") comment at
`Partida.asm:10` is where it was meant to go.

**Levels advance only when you press F** (`pala.asm:45-48`), which — per §4 — is a leftover debug hook
for testing the restart screen.

The advance mechanism itself works, but by accident:

```asm
Fin_Juego:
    ld de, 1
    add ix, de           ; "Sumamos a IX (maplist)..."
```

The comment says it is indexing `maplist`. It is not. `IX` does not point into `maplist` — it points
into the *map data*, left by `Mostrar_Mapa` sitting **on** the `$FF` terminator. Adding 1 steps past
the terminator and lands on the next map's header byte, which works **only because `Mapas.asm` places
`map0`–`map3` back-to-back in memory** (verified: `map0` terminator at `$9C38`, `map1` at `$9C39`).

So: the `maplist` `DEFW` table is read exactly once, at `main.asm:24`, and is otherwise dead. A
correct implementation would index the table by 2 and reload `IX` from it. As written, **reordering
the maps, inserting a fifth map anywhere but the end, or adding padding between maps silently breaks
level progression** with no assembler error.

The bounds check is safe by luck: `Fin_Juego` increments `IX` *before* testing `levelCounter`, so
after `map3` the pointer briefly holds garbage (`$9E3E`, which is `levelCounter` itself, followed by
`Juego`'s code) — but `levelCounter` reaches 4 on that same pass and the code branches to
`ReinicioJuego` without ever dereferencing the bad pointer. It works. It would stop working the
moment anyone reorders those two operations.

**Nothing is reset between levels.** `Coord`, `Vector` and `POSICION` carry over — the new level
starts with the ball wherever it happened to be and travelling in whatever direction it had.

**The map's own brick count is sitting right there.** Byte 0 of each map (82/71/78/153, verified to be
the destructible-brick count, §3) is read into `A` by `Mostrar_Mapa` and immediately discarded. Storing
it in a RAM counter and decrementing on each brick hit is the natural completion mechanism, and the
data already supports it.

### 5.6 — Lives and game over: **neither exists** (critical)

No lives counter, no score, no scoring, no HUD, no game-over-by-losing. Grepping the sources for
`vida`/`lives`/`score`/`punt`/`marcador` returns nothing.

What exists is: after 4 levels (or 4 presses of F), `levelCounter` hits `CantidadNiveles` and
`ReinicioJuego` shows "La partida ha finalizado / Quieres jugar otra partida?". That is a
**completion** screen reached by counting level changes, not a game-over. There is no way to lose,
because there is no way to miss the ball (§5.1).

The restart path also has the two structural defects from §3: `ReinicioJuego` → `Pantalla_Reinicio` →
`call flujo_juego` never returns (stack leak), and the "N" answer leads to `FinDelJuego`, which falls
through `CalcularAtributo` and silently resumes the key-wait loop instead of terminating.

`levelCounter` is reset on restart. `Coord`, `Vector` and `POSICION` are not — **a second game starts
with the ball and paddle in their end-of-previous-game positions.**

### 5.7 — Ball speed and angle: fixed 45°, quantised to 8 pixels, unwinnable-by-construction risk (medium)

`Vector` is only ever `±1, ±1`. There is no other angle, and no code path that could produce one —
paddle-relative rebound angle, the defining mechanic of Arkanoid, is entirely absent.

Once collision is implemented, a pure 45° ball on a 32×24 grid is a **known unwinnable-level hazard**:
the ball's trajectory is confined to cells of a single parity class, so with a fixed diagonal it can
be geometrically incapable of reaching certain bricks no matter how the player plays. `map2` (the
staircase, with a row of indestructible colour-8 bricks) and `map3` (the UFV logo, with isolated
single-column brick runs) are the likely candidates. **Any completion-detection work must be paired
with variable rebound angles, or levels will become uncompletable the moment they can be completed at
all.**

Separately, the two speed constants are unrelated magic numbers in two files (`$1100` in
`pelota.asm:66`, `CONTADOR EQU $03FF` in `pala.asm:4`), tuned by eye in the final commit and coupled
through the single frame loop — retuning one changes the feel of the other.

And per §5.3: increasing ball speed by increasing the *step size* rather than shortening the delay
will break the wall-bounce equality checks and let the ball leave the playfield.

### 5.8 — Rendering: flicker and tearing are structural (low, but pervasive)

No interrupt sync, no double buffering, and the ball is erased for ~27% of every frame (§2). Both are
consequences of the busy-wait architecture, not of any single bug. Fixing them properly means moving
to an `IM 1`/`halt`-driven frame loop — a foundational change, worth deciding on before building more
game logic on top of the current timing.

---

## Summary for whoever picks this up

The project is roughly a **skeleton with working scaffolding and a missing core**. Rendering, level
data, map drawing, board drawing, menus, keyboard input, paddle movement and ball motion all work.
What is missing is the game: **collision detection does not exist** (`colisiones.asm` is a 0-byte
file), and with it go brick destruction, ball loss, lives, scoring, and win detection. Level advance
is a debug keypress left over from November.

The final commit message says as much: *"falta optimizar el codigo de la pelota."*

Highest-value first steps, in order:

1. **A real build script** (`sjasmplus --raw=... main.asm`) and a `.gitignore` for `*.bin`/`*.lst`/
   `*.sld`, plus deletion of the broken per-file artifacts and the orphaned `plantilla.*`. Cheap;
   removes the ping-ponging absolute paths and the risk of debugging the wrong binary.
2. **Fix the ball's erase strategy** (§5.2) — save/restore the attribute under the ball, or keep a
   shadow brick map. Nothing else can be built until this is right.
3. **Implement `colisiones.asm`**: ball↔paddle (with a paddle-relative rebound angle, §5.7), and
   ball↔brick (using the map's existing byte-0 brick count for completion, §5.5).
4. **Make the bottom wall lethal** and add lives — the bounce at `pelota.asm:16-21` is currently what
   makes the game unloseable.
5. Fix the `teclado` hang (§5.4), the `FinDelJuego` fall-through (§3), and reset `Coord`/`Vector`/
   `POSICION` on level change and restart (§5.5, §5.6).

---

## Corrections (from skill-authoring pass)

Added 2026-08-14 while building `.claude/skills/`. Everything above this line is the original audit,
unedited. Two of its claims are wrong; both were caught by re-deriving from source, and one of them
would break working code if implemented as written.

### §5.3's "Should be" column is incorrect — do not implement it

The table in §5.3 claims each wall bounce "forces a value 2 away instead of 1" so that "the ball skips
a cell on every bounce", and proposes 23 / 0 / 31 / 0 as the corrected targets. **That is backwards.**

The detection fires on the **tentative** value, not the current one. Tracing `pelota.asm:11-21`: `add
h` computes `row + delta` into `A`, so `cp 24` matching means the ball is currently on row **23** with
a delta of +1. The code negates the delta to −1 and forces the row to 22 — which is exactly
`23 + (−1)`, one cell of travel, a correct mirror. The sequence is `21, 22, 23, 22, 21`. The same
holds on all four edges.

Implementing the proposed value instead would set the new position **equal to the current one**
(row 23 → row 23), parking the ball on the wall for two consecutive frames — **reintroducing the
stutter §5.3 describes as a bug, rather than fixing it.**

§5.3's underlying observation is still right, but the defect is different from the one it names: the
ball is allowed to occupy the border cells (row 0, row 23, columns 0 and 31) at all, which is what
erases them. The fix is to bounce one cell earlier, confining the ball to rows 1–22 and columns 1–30.

**See `collision-and-physics` §4** for the full trace and the corrected detect/force table.

### §3's coupling table: `tablero.asm` does not call `CalcularAtributo`

The cross-module coupling table states that `CalcularAtributo` "lives in `mensaje_inicio.asm` but is
used by `tablero.asm` and `PintarMapa.asm`". **`tablero.asm` contains no such call.** It computes
attribute addresses inline — `ld hl, $5800 + 0 * 32 + 0` and similar at `tablero.asm:5,16,27` — and
its only `call` is to `CLEARSCR` at `:2`.

Grep gives the real callers: `PintarMapa.asm:11`, plus `mensaje_inicio.asm:10` and `:34` within its
own file. The point the row was making survives on `PintarMapa` alone — a menu file *is* a
load-bearing dependency of the map renderer — but the `tablero.asm` half is not real.

### Smaller divergences, for completeness

- **§4** says `43848fe` "deleted ~124 lines and replaced them with 88". The actual diffstat for
  `pala.asm` is **79 insertions, 115 deletions**.
- **§1** records a clean build at "998 lines". The working tree has since had a 7-line comment header
  removed from `main.asm`, so the current figure is **991 lines**. Byte count is unchanged at 7923 —
  comments emit nothing.
- **§1's** description of `.vscode/tasks.json` (building `${file}`, hardcoded `sjasmplus118.exe`) and
  `launch.json` (a `zsim` config) describes the **pre-fix** state. Both files have since been
  rewritten; see the uncommitted-changes note below.
- **§2's** PRINTAT state block is listed at `$96E4`; the actual addresses are `SCR_CUR_PTR` `$96E5`,
  `SCR_ATTR_PTR` `$96E7`, `PRINT_ATTR` `$96E9`. Size (5 B) is right, base is off by one.

### What still holds

Spot-checked and confirmed correct: every address in §2, the map-adjacency chain in §5.5 (terminators
at `$9C38`/`$9CD9`/`$9D4A`/`$9E3D`, each immediately followed by the next map, and `map3`'s followed
by `levelCounter` at `$9E3E`), the byte-0 brick counts in §3 (82/71/78/153, with map2's 78 being
destructible-only out of 82 non-empty), all timing figures in §2, the register and stack analysis in
§3, and every git-history claim in §4 apart from the diffstat above.

§5's own caveat — *"none of it has been observed running"* — still applies to this addendum. These
corrections come from reading and assembling the source, not from watching the game run.
