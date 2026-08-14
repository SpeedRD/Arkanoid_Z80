---
name: project-orientation
description: Use when starting any work on this repo — opening an .asm file for the first time, asking what already works and what is missing, deciding which sibling skill applies, planning what to implement next, or reading AUDIT.md and needing to know where it is stale. This is the index; it routes, it does not explain in depth.
---

# Arkanoid_Z80 — Project Orientation

## 1. What this is

A ZX Spectrum 48K Arkanoid clone in Z80 assembly. `DEVICE ZXSPECTRUM48` and `org $8000`
(`main.asm:1,3`) produce a **raw binary** — no tape image, no BASIC stub, no loader. The only way to
run it is to have an emulator/debugger load `main.bin` at `$8000` and jump there. Built with
**sjasmplus** (dialect-specific, not portable to pasmo/z80asm). Run under **ZEsarUX + DeZog over
zrcp** (`.vscode/launch.json:5-17`, `.vscode/tasks.json:5-15`). Total source: ~975 lines across 11
`.asm` files plus a 768-byte font blob.

## 2. Current state, honestly

**Working scaffolding, missing core.** These work: title screen, text/menu rendering, playfield
border, level data, map drawing, keyboard input, paddle motion, ball motion with four-wall bounce.

These do not exist:

- **Collision detection.** `colisiones.asm` is a **0-byte file**, `INCLUDE`d at `main.asm:35`. Nothing
  reads `POSICION` from `pelota.asm`, nothing looks up a brick. The paddle is decorative.
- **Ball loss.** The floor bounces unconditionally (`pelota.asm:15-21`: `cp 24` → negate vector →
  force row 22). You cannot miss.
- **Lives, game over by losing.** No such variable exists anywhere in the sources.
- **Win detection.** Nothing counts bricks. `Partida.asm:10` is a comment — `;mirar si fin partida` —
  marking where it was meant to go.
- **Real level advance.** Levels only advance when you press **F** (`pala.asm:45-48`, `bit 3,a` on
  port `$FDFE` → `call Fin_Juego`). Per AUDIT.md §4 this is a leftover debug hook from November 2024.

What exists in place of a game-over is a *completion* screen: after 4 level changes `levelCounter`
hits `CantidadNiveles` (`Partida.asm:2,27`) and `ReinicioJuego` shows "La partida ha finalizado".
That is a different thing and must stay distinct from the game-over path you are going to add.

Total mutable game state is **seven bytes**, stored inline in the code image: `POSICION` (`$9AD5`,
2 B), `levelCounter` (`$9E3E`, 1 B), `Coord` (`$9E6E`, 2 B), `Vector` (`$9E70`, 2 B). There is no
variable block and no reset routine.

## 3. File map

| File | Lines | Role | Status |
|---|---|---|---|
| `main.asm` | 35 | Entry at `$8000`; `di` + `ld sp,0`; title screen; `flujo_juego` loop reloads `IX` from `maplist` and `CALL Juego`; all `INCLUDE`s (26-35) | Working |
| `Pantalla_Inicio.asm` | 293 | `Main_Pantalla` — RLE decoder writing the title bitmap to `$4000`; `RLEData` (line 34+) | Complete, self-contained |
| `L30.3 - printat.asm` | 164 | Third-party text library (Daniel León, UFV): `PRINTAT`, `PRINTSTR`, `PRINTCHAR`, `CRtoSCREEN`, `CRtoATTR`, `INK2PAPER`, `CLEARSCR`, `CHARSET` (`incbin charset.bin`, line 162) | Complete — **shared, do not edit** |
| `mensaje_inicio.asm` | 93 | `Pantalla_Ini`, `Pantalla_Reinicio`, `FinDelJuego`, plus `CalcularAtributo` (52) and `EsperarTecla`/`LeerTecla`/`SoltarTecla` | Menus work; `FinDelJuego` falls through into `CalcularAtributo` (48→52); `Pantalla_Reinicio` ends `call flujo_juego` (39) which never returns |
| `tablero.asm` | 37 | `dibujar_tablero` — clears screen, paints left/right/top border | Works; top loop runs `b,32` from `$5801` (27-29) so it spills one cell into row 1 col 0; `fin_dibujar_tablero` (38) is dead |
| `Mapas.asm` | 82 | `maplist` (14) + `map0..map3` (20, 33, 49, 65) | Data complete. **Byte 0 of each map is the destructible-brick count** — verified 82/71/78/153 against the data. `maxLevelsMask` (15) is unused |
| `PintarMapa.asm` | 50 | `Mostrar_Mapa` — walks the map at `IX`, paints bricks 2 cells wide from column 1 | Works, with defects: reads byte 0 into `A` (2-3) then discards it (6); colour 8 → `sla a`×3 = `$40` (23-25) = bright black on black, invisible; `call Pala_Juego` (40) is unreachable; exits with `IX` **on** the `$FF` terminator |
| `pala.asm` | 92 | `POSICION` (1), `dibujarpala`/`dibujarpalacolor`, `teclado`, `nuevaposicion`, `esperar` | Draw and bounds are correct; `teclado` hangs on S or G (54-56) |
| `pelota.asm` | 93 | `Coord`/`Vector` (1-2), `ball`, `PosXY` (77), `Esperar_pelota` (63) | Motion and wall bounce work; no collision of any kind; the erase at line 10 writes 0 over whatever was under the ball |
| `Partida.asm` | 38 | `Juego` + `Pala_Juego` frame loop (4-15), `Fin_Juego` (19), `ReinicioJuego` (32) | Loop works; no end-of-round detection (10); `Fin_Juego` reachable only from `pala.asm:47` |
| `colisiones.asm` | **0** | Intended home of ball↔paddle and ball↔brick | **Empty.** The single largest gap |
| `charset.bin` | — | 768-byte 8×8 font, 96 chars | Binary asset |

Build artifacts: only `main.bin` / `main.lst` / `main.sld` are valid. The per-file `.bin`/`.lst`/
`.sld` (e.g. `Partida.bin`, 34 bytes) are broken standalone builds of include-fragments, and
`plantilla.*` is orphaned output whose `.asm` never existed in the repo. Never load any of them. →
**build-and-verify**

## 4. The three governing facts

Internalise these before touching anything. Each has an owning skill; do not learn them from here.

**1. The playfield IS the attribute file.** Everything in play — border, bricks, paddle, ball — is a
coloured 8×8 attribute cell in `$5800-$5AFF`. There are no sprites and no background layer. The play
area is a 32×24 character grid; motion is quantised to 8 pixels. Ball = 1 cell (`pelota.asm:8`,
attribute `8*7`); paddle = 7 cells on row 23 (`pala.asm:2,21` — `$5B00-32` = `$5AE0` = 23×32);
brick = 2 cells (`PintarMapa.asm:27-30`). **Consequence: erasing an entity by writing 0 destroys
whatever was underneath it.** That is why the ball currently eats bricks and chews holes in the
border without any collision code existing. → **memory-map-and-playfield**

**2. `IX` is a global "current map pointer" held across the entire game loop.** Loaded at
`main.asm:17` (`ld ix,(maplist)`), advanced through the map data by `Mostrar_Mapa`, left sitting on
the `$FF` terminator, and then incremented past it by `Fin_Juego` (`Partida.asm:20-21`) to reach the
next map. Any routine that clobbers `IX` corrupts level state — and `PRINTAT` uses `IX` as its string
pointer (`printat.asm:12,20`), which is safe today only because it is never called during play.
→ **state-and-register-contracts**

**3. All pacing is busy-wait delay loops. This is the architecture.** `di` at `main.asm:5`; there is
no `ei`, no `IM`, no `halt`, no ISR anywhere in the sources (grep-verified). Frame time is the sum of
`Esperar_pelota` (`pelota.asm:63-66`, `$1100` iterations), the `teclado` poll (`pala.asm:32-43`), and
`esperar` (`pala.asm:84-91`, `CONTADOR EQU $03FF` at `pala.asm:4`) — roughly 44 ms, about 23 fps,
with the ball advancing one cell per frame. Everything is CPU-clock-dependent; on a faster machine
the game runs faster. **Do not propose replacing this with an interrupt-driven frame loop.** The
rendering rewrite (AUDIT.md §5.8) is explicitly deferred and out of scope. Work within the busy-wait
model. → **timing-and-frame-loop**

## 5. Routing table

| If you are… | Read first |
|---|---|
| Editing any `.asm` at all | **assembler-conventions** (sjasmplus dialect, `add b` forms, `:` multi-statement lines, `INCLUDE` order at `main.asm:26-35`, Spanish-existing / English-new naming rule) |
| Adding, reordering or editing a level | **map-data-format** (row encoding, `$FF` terminator, byte 0 = brick count, and the hard requirement that `map0..map3` stay contiguous because `Partida.asm:20-21` walks off the end of one map into the next) |
| Changing ball or paddle speed | **timing-and-frame-loop** (two unrelated constants in two files: `pelota.asm:66` and `pala.asm:4`), then **collision-and-physics** (raising the *step size* rather than shortening the delay breaks the exact-equality wall checks at `pelota.asm:15,24,37,46`) |
| Implementing collisions, destruction or rebound angle | **collision-and-physics**, but only after the erase fix in **memory-map-and-playfield** — collision cannot be built on top of the current erase strategy |
| Drawing anything to the screen | **memory-map-and-playfield** (`CalcularAtributo` at `mensaje_inicio.asm:52`, `PosXY` at `pelota.asm:77`, cell↔address arithmetic) |
| Adding a routine, a `call`, or touching `IX`/`HL`/`B` across a call boundary | **state-and-register-contracts** |
| Building, running, or checking a change actually works | **build-and-verify** (fixed build of `main.asm`; ZEsarUX with `--enable-remoteprotocol`; DeZog over zrcp — **not** zsim) |
| Debugging something weird — bricks vanishing, game freezing, level state scrambled, text not printing | **failure-patterns** first. Most "new" bugs here are one of a handful of known mechanisms |
| Printing text or drawing menu screens | **memory-map-and-playfield** plus **failure-patterns** (`PRINTCHAR` advances the cursor with `INC (HL)` on the low byte only, `printat.asm:124-127`, so strings cannot wrap a line or cross a 256-byte screen-third boundary) |

## 6. Order of work

Each step blocks the next. Do not reorder.

1. **Erase-restore fix.** Before drawing an entity, read the attribute byte under it and save it;
   write it back on erase. Today `ball` unconditionally writes 0 (`pelota.asm:10`), which is why the
   ball paints holes through bricks and border. *Blocks everything else:* while erasure destroys the
   playfield, "is there a brick at this cell?" has no reliable answer, so no collision test can be
   trusted. The decided approach is read-back-and-restore; a shadow brick map in RAM is a documented
   future fallback, not a hedge to keep open. → **memory-map-and-playfield**

2. **Ball↔brick collision + destruction.** Test the target cell before moving into it, bounce, clear
   the brick, decrement a RAM counter initialised from the map's byte 0. *Blocks:* completion
   detection needs a count that goes down; nothing else can decrement it.

3. **Ball↔paddle collision with variable rebound angle.** Compare the ball cell against `POSICION`
   (`pala.asm:1`) and the 7-cell span, and derive the new `Vector+1` from where on the paddle it hit.
   *Blocks:* step 4 needs a paddle that can actually save the ball, and step 5 needs angle variety —
   see the parity note below.

4. **Lethal floor + lives + game over.** Replace the unconditional floor bounce (`pelota.asm:15-21`)
   with ball loss; add a lives counter; on zero lives take a real game-over path, distinct from the
   existing `ReinicioJuego` completion screen (`Partida.asm:32-36`). *Blocks:* step 5 — automatic
   level completion only makes sense once losing is possible, otherwise the game is a demo that
   advances by itself.

5. **Automatic completion detection, replacing the F key.** When the brick counter from step 2 hits
   zero, call `Fin_Juego`; delete the F-key hook at `pala.asm:44-48`. *Blocks:* nothing after it, but
   it must not land before step 3.

6. **The smaller correctness fixes**, once the core is in:
   - The `teclado` hang — holding S or G freezes the whole game (`pala.asm:54-56`).
     → **timing-and-frame-loop** §4
   - `FinDelJuego` falls straight through into `CalcularAtributo` (`mensaje_inicio.asm:48` → `52`),
     so pressing "N" never quits. Must be fixed **as part of step 4** if the game-over path reuses
     it. → **collision-and-physics** §8
   - The top-border off-by-one (`tablero.asm:29`) and the wrong `Coord`/`Vector` comments
     (`pelota.asm:1-2`). → **failure-patterns** §12

   Note that **resetting `Coord`/`Vector`/`POSICION` is not on this list** — it is not a cleanup. It
   is required by step 4, because you cannot respawn a ball after a loss without it.
   → **collision-and-physics** §8, **state-and-register-contracts** §5

**This list is the summary. collision-and-physics §2 is the authoritative build order** and carries
one step this list folds in silently: fixing the wall bounds and converting the exact-equality wall
tests to range comparisons, which sits between steps 1 and 2 here. Use its numbering when a skill
cites a step number.

**Why rebound variety must land with or before step 5:** `Vector` is only ever `(±1,±1)`
(`pelota.asm:2`), so every step changes row and column by exactly 1 and `row + col` parity is
invariant — the ball occupies only one parity class of cells. That alone turns out **not** to strand
any brick (bricks are 2 cells wide, so each spans both parities), but the deeper problem does: with a
paddle that only mirrors, **the player has no influence on the ball's path at all**, so whether a
level can be cleared is fixed before anyone presses a key. Ship completion detection before rebound
variety and levels become uncompletable the moment they become completable at all.
**collision-and-physics** §7 owns the full argument — read it there rather than relying on this
summary.

## 7. Spanish → English glossary

Existing identifiers stay in Spanish — **never rename them**. New code uses English identifiers and
English comments. The codebase is accepted as mixed-language going forward.

Appearing as **labels/identifiers**:

| Spanish | English | Where |
|---|---|---|
| `pala` | paddle | `dibujarpala`, `dibujarpalacolor`, `LONGITUDPALA`, `COLORPALA`, `Pala_Juego` |
| `pelota` | ball | `Esperar_pelota` (`pelota.asm:63`); the routine itself is `ball` (`pelota.asm:5`) |
| `ladrillo` | brick | `Fila_Ladrillo` (`PintarMapa.asm:19`) |
| `tablero` | board / border frame | `dibujar_tablero` (`tablero.asm:1`) |
| `mapa` | map | `Mostrar_Mapa` (`PintarMapa.asm:1`) |
| `juego` | game | `Juego`, `Fin_Juego`, `ReinicioJuego`, `flujo_juego`, `FinDelJuego` |
| `dibujar` | draw | `dibujarpala`, `dibujar_tablero`, `Fin_Dibujo` |
| `esperar` | wait | `esperar`, `Esperar_pelota`, `EsperarTecla`, `Bucle_esperar` |
| `teclado` | keyboard | `teclado`, `teclado1`..`teclado4`, `tecladofin` (`pala.asm:32-66`) |
| `nueva posicion` | new position | `nuevaposicion` (`pala.asm:68`), `POSICION` (`pala.asm:1`) |
| `fin` | end | `Fin_Juego`, `Fin_Dibujo`, `FinDelJuego`, `fin` (`Pantalla_Inicio.asm:11`), `tecladofin` |
| `reinicio` | restart | `ReinicioJuego`, `Pantalla_Reinicio`, `MensajeReiniciar` |
| `pantalla` | screen | `Main_Pantalla`, `Pantalla_Ini`, `Pantalla_Reinicio` |
| `mensaje` | message | `MensajeIniciar`, `MensajeFinal`, `MensajeFinDeJuego`, `MensajeReiniciar` |
| `fila` | row | `Fila`, `Fila_Ladrillo` (`PintarMapa.asm:5,19`) |
| `contador` | counter | `CONTADOR` (`pala.asm:4`) — the frame delay, *not* a game counter |
| `longitud` | length | `LONGITUDPALA EQU 7` (`pala.asm:2`) |
| `color` | colour | `COLORPALA` (`pala.asm:3`), `dibujarpalacolor` |
| `nivel` | level | `CantidadNiveles` (`Partida.asm:2`); note `levelCounter` is already English |
| `cantidad` | quantity / count | `CantidadNiveles` (`Partida.asm:2`) |
| `izquierdo` / `derecho` | left / right | `borde_izquierdo`, `borde_derecho` (`tablero.asm:10,21`) |
| `bucle` | loop | `bucle_principal` (`Pantalla_Inicio.asm:5`), `Bucle_esperar` (`pelota.asm:68`) |
| `atributo` | attribute | `CalcularAtributo` (`mensaje_inicio.asm:52`) |
| `empezar` | start | `empezar:` (`main.asm:12`) |
| `seguir` | continue | `seguir1`..`seguir4` (`pelota.asm:23,31,45,53`) — the wall-bounce fall-through chain |

Appearing only in **comments / on-screen prose**, not as identifiers:

| Spanish | English | Where |
|---|---|---|
| `partida` | round / match | `;mirar si fin partida` (`Partida.asm:10`); "La partida ha finalizado" (`mensaje_inicio.asm:93`) |
| `columna` | column | `; Columna = 1` (`PintarMapa.asm:10`), menu coordinate comments |
| `limite` | limit / boundary | `; Rebotar con el limite superior` (`pelota.asm:48`) |
| `arriba` | up / top | `; Dibujar la parte de arriba` (`tablero.asm:26`) |

**Not present anywhere in the current sources** — you will meet them in AUDIT.md's history section or
in Spanish prose, but there is no code to look up: `borrar` (erase — an old `borrarpala` existed and
was deleted; today erasure is `dibujarpalacolor` with `c=0`, `pala.asm:10-11`), `salto` (skip/jump —
a deleted `Salto_Ladrillo` in the map renderer), `abajo` (down), `vida` (life — no lives system
exists at all; when you add one, name it in English).

## 8. What NOT to assume

- **The sibling TETRIS_Z80 project is not a reference.** It shares exactly two things with this repo:
  the sjasmplus dialect and the `L30.3 - printat.asm` library (same course, same author). Its
  register conventions, memory map, entity model and game mechanics do **not** apply here. Do not
  copy patterns across.
- **AUDIT.md §5.3's wall-bounce table is WRONG. Do not implement its "Should be" column.** It claims
  each bounce forces the ball 2 cells in instead of 1 and so "skips a cell on every bounce". Traced
  against `pelota.asm:11-55`, the forced values (22 / 1 / 30 / 1) are **correct mirror
  reflections** — the detection fires on the *tentative* value, so `cp 24` matching means the ball is
  on row 23, and forcing 22 is exactly one cell of travel with the negated delta. AUDIT's proposed
  values (23 / 0 / 31 / 0) would each set the new position **equal to the current one**, producing
  precisely the stutter it accuses the code of. The real defect is different: the ball is allowed
  onto the border cells at all, which is what erases them. → **collision-and-physics** §4
- **Do not assume AUDIT.md line numbers are current — the code wins, always.** Known divergences
  at the time of writing: (a) AUDIT.md §2 cites `di` at `main.asm:12` and `ld sp,0` at `main.asm:13`;
  a 7-line credits header has since been removed from the working tree, so they are now
  **`main.asm:5` and `main.asm:6`**. (b) AUDIT.md §1 describes `.vscode/tasks.json` as building
  `${file}` with a hardcoded Windows `sjasmplus118.exe` path and `launch.json` as a zsim config —
  **both have already been fixed on disk**: the task now builds `main.asm` → `main.lst`/`main.sld`/
  `main.bin` with plain `sjasmplus` (`tasks.json:5-15`) and the launch config is ZEsarUX over zrcp
  (`launch.json:5-17`). (c) AUDIT.md §4 says `43848fe` "deleted ~124 lines and replaced them with
  88"; the actual diffstat is **79 insertions, 115 deletions**. (d) AUDIT.md §3 lists `tablero.asm`
  as a caller of `CalcularAtributo`; it is not — grep gives only `PintarMapa.asm:11` and
  `mensaje_inicio.asm` itself. Verify any AUDIT.md citation before relying on it.
- **Do not assume any behavioural claim here has been observed running.** AUDIT.md §5 states it
  plainly and it still holds: everything about how this game *behaves* was derived by reading code,
  not by watching it. That includes the known-bad baseline in **build-and-verify** §6. Treat those
  as predictions to check, not facts to confirm.
- **Do not assume there is a background layer, a sprite system, or double buffering.** There is one
  layer: the attribute file.
- **Do not assume the ball "destroying" bricks means collision works.** It is the erase writing 0
  (`pelota.asm:10`). There is no bounce, no count, no logic. → **failure-patterns**
- **Do not assume `maplist` is live.** It is read exactly once (`main.asm:17`) and never indexed
  again; level advance walks the raw map data instead (`Partida.asm:20-21`). The `DEFW` table looks
  load-bearing and is not. → **map-data-format**
- **Do not assume the interrupt rewrite is on the table.** It is deferred. Busy-wait is the
  architecture. → **timing-and-frame-loop**
- **Do not assume `main.bin` matches whatever you just edited.** Every build artifact is committed
  and there is no `.gitignore`. Rebuild before you draw conclusions from a run. → **build-and-verify**
- **Score and an on-screen HUD are out of scope.** Do not add them, and do not design the brick
  counter as if a HUD will read it.
