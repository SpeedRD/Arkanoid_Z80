---
name: project-orientation
description: Use when starting any work on this repo — opening an .asm file for the first time, asking what already works and what is missing, deciding which sibling skill applies, planning what to implement next, or reading AUDIT.md and needing to know where it is stale. This is the index; it routes, it does not explain in depth.
---

# Arkanoid_Z80 — Project Orientation

## 1. What this is

A ZX Spectrum 48K Arkanoid clone in Z80 assembly. `DEVICE ZXSPECTRUM48` and `org $8000`
(`main.asm:1,3`) produce a **raw binary** — no tape image, no BASIC stub, no loader. The only way to
run it is to have an emulator/debugger load `main.bin` at `$8000` and jump there. Built with
**sjasmplus** (dialect-specific, not portable to pasmo/z80asm) via `./build.sh`. Run under
**ZEsarUX + DeZog over zrcp** (`.vscode/launch.json:5-17`, `.vscode/tasks.json:5-15`). Total source:
~1476 lines across 11 `.asm` files plus a 768-byte font blob, and a Python test harness in `tests/`.

## 2. Current state

**The game is playable and finishable.** Title screen, menus, border, level data, map drawing,
keyboard input, paddle motion, ball motion, ball↔brick and ball↔paddle collision, brick destruction,
a paddle-relative rebound angle, a lethal floor, lives, game over, and automatic level completion all
work — and all of it is covered by the suites in `tests/`. → **build-and-verify**

What this used to say — that `colisiones.asm` was a 0-byte file, that the paddle was decorative, that
you could not lose and levels only advanced on the F key — is **no longer true**. `colisiones.asm` is
now the largest source file in the tree (377 lines).

Mutable game state is **fifteen bytes**, still declared inline next to the routine that owns it:
`POSICION` (`$9B10`, 2 B), `levelCounter` (`$9E74`, 1 B), `Coord` (`$9ECA`, 2 B), `CoordFrac`
(`$9ECC`, 2 B), `Vector` (`$9ECE`, 4 B), `bricks_left` (`$9F51`), `lives` (`$9F52`), `ball_lost`
(`$9F53`). Plus per-frame scratch (`NewRow`, `NewCol`, `BallSaved`, `cand_cell`, `bounce_flags`).
There **is** now a reset routine — three, in fact: `reset_ball`, `reset_round`, `reset_game`.
→ **state-and-register-contracts**

### What is still deliberately absent

- **Score and an on-screen HUD.** Out of scope. Do not add them, and do not design the brick counter
  as if a HUD will read it.
- **Sound.** No `OUT ($FE)` anywhere; the border is never set either.
- **Interrupts.** `di` at `main.asm:5` and never an `ei`. Busy-wait is the architecture (§4).
- **Multi-hit bricks, power-ups, more than four levels.**

## 3. File map

| File | Lines | Role | Status |
|---|---|---|---|
| `main.asm` | 35 | Entry at `$8000`; `di` + `ld sp,0`; title screen; `flujo_juego` reloads `IX` from `maplist` and `JP Juego` (never `CALL` — `Juego` does not return); all `INCLUDE`s | Working |
| `Pantalla_Inicio.asm` | 293 | `Main_Pantalla` — RLE decoder writing the title bitmap to `$4000` | Complete, self-contained |
| `L30.3 - printat.asm` | 163 | Third-party text library (Daniel León, UFV) | Complete — **shared, do not edit** |
| `mensaje_inicio.asm` | 133 | `Pantalla_Ini`, `Pantalla_Reinicio`, **`Pantalla_GameOver`**, `FinDelJuego`, `CalcularAtributo`, `EsperarTecla`/`LeerTecla`/`SoltarTecla` | Working. All three historical defects here are fixed — see §6 |
| `tablero.asm` | 37 | `dibujar_tablero` — clears screen, paints left/right/top border | Works; top loop still runs `b,32` from `$5801` so it spills one cell into row 1 col 0 (harmless); `fin_dibujar_tablero` is dead |
| `Mapas.asm` | 82 | `maplist` + `map0..map3` | Data complete. **Byte 0 of each map is the destructible-brick count** — 82/71/78/153. `maxLevelsMask` is unused |
| `PintarMapa.asm` | 54 | `Mostrar_Mapa` — walks the map at `IX`, paints bricks 2 cells wide from column 1 | Works. **Now stores byte 0 into `bricks_left`** instead of discarding it. Colour 8 still renders invisible; `call Pala_Juego` is still unreachable dead code |
| `pala.asm` | 98 | `POSICION`, `dibujarpala`/`dibujarpalacolor`, `teclado`, `nuevaposicion`, `esperar` | Working. **The S/G hang is fixed and the F-key hook is gone** |
| `pelota.asm` | 123 | `Coord`/`CoordFrac`/`Vector`, `ball`, `step_ball`, `PosXY`, `Esperar_pelota` | Working. Rewritten for read-back-and-restore and 8.8 fixed-point motion |
| `Partida.asm` | 81 | `Juego` + `Pala_Juego` frame loop, `Ball_Lost`, `Game_Over`, `Fin_Juego`, `ReinicioJuego` | Working. Completion and ball-loss are checked in the frame loop; every exit uses `jp`, never `call` |
| `colisiones.asm` | 377 | `classify_cell`, `probe_cell`, `resolve_collisions`, `destroy_brick`, `paddle_hit`, `rebound_table`, the resets, and all the new state | Working — the core of the game |
| `charset.bin` | — | 768-byte 8×8 font | Binary asset |
| `tests/` | — | ZRCP-driven Python suites | `python3 tests/run_all.py` |

Build artifacts (`main.bin`/`main.lst`/`main.sld`) are **no longer committed** — `.gitignore` covers
`*.bin`/`*.lst`/`*.sld`, with `!charset.bin` excepted because it is a source asset. The broken
per-file artifacts and the orphaned `plantilla.*` are deleted. **`main.lst` is generated, and the
test harness resolves every address from it, so build before you read addresses.**
→ **build-and-verify**

## 4. The three governing facts

Internalise these before touching anything. Each has an owning skill; do not learn them from here.

**1. The playfield IS the attribute file.** Everything in play — border, bricks, paddle, ball — is a
coloured 8×8 attribute cell in `$5800-$5AFF`. There are no sprites and no background layer. The play
area is a 32×24 character grid. Ball = 1 cell (`$38`); paddle = 7 cells on row 23 (`$10`);
brick = 2 cells (colour `<< 3`); border = `$0F`.
**Consequence: erasing an entity by writing 0 would destroy whatever was underneath it.** That is why
`ball` now reads the attribute under itself before drawing and writes that byte back on erase, and
why the ball is confined to rows 1-22 / columns 1-30 so it never lands on the border or the paddle at
all. → **memory-map-and-playfield**

**2. `IX` is a global "current map pointer" held across the entire game loop.** Loaded at
`main.asm:17`, advanced through the map data by `Mostrar_Mapa`, left sitting on the `$FF` terminator,
then incremented past it by `Fin_Juego` to reach the next map. Any routine that clobbers `IX`
corrupts level state — and `PRINTAT` uses `IX` as its string pointer, which is safe only because it
is never called during play. **Every routine in `colisiones.asm` preserves `IX`, and there is a test
that says so.** → **state-and-register-contracts**

**3. All pacing is busy-wait delay loops. This is the architecture.** `di` at `main.asm:5`; no `ei`,
no `IM`, no `halt`, no ISR anywhere (grep-verified). Frame time is `Esperar_pelota` + the `teclado`
poll + `esperar` ≈ 44 ms, about 23 fps. **Do not propose replacing this with an interrupt-driven
frame loop.** The rendering rewrite (AUDIT.md §5.8) is explicitly deferred and out of scope.
→ **timing-and-frame-loop**

## 5. Routing table

| If you are… | Read first |
|---|---|
| Editing any `.asm` at all | **assembler-conventions** (sjasmplus dialect, `add b` forms, `:` multi-statement lines, `INCLUDE` order, Spanish-existing / English-new naming rule) |
| Adding, reordering or editing a level | **map-data-format** (row encoding, `$FF` terminator, byte 0 = brick count, and the hard requirement that `map0..map3` stay contiguous) |
| Changing ball or paddle speed | **timing-and-frame-loop** (two unrelated constants in two files), then **collision-and-physics** (speed goes in the delays, never in the step size) |
| Touching collisions, destruction, rebound angle, lives or completion | **collision-and-physics** |
| Drawing anything to the screen | **memory-map-and-playfield** (`CalcularAtributo`, `PosXY`, cell↔address arithmetic) |
| Adding a routine, a `call`, or touching `IX`/`HL`/`B` across a call boundary | **state-and-register-contracts** |
| Building, running, or checking a change actually works | **build-and-verify** (`./build.sh`; ZEsarUX with `--enable-remoteprotocol`; `python3 tests/run_all.py`) |
| Debugging something weird | **failure-patterns** first |
| Printing text or drawing menu screens | **memory-map-and-playfield** plus **failure-patterns** (`PRINTCHAR` advances the cursor on the low byte only, so strings cannot wrap a line or cross a 256-byte screen-third boundary) |

## 6. What was built, and what it replaced

The ordered plan this file used to carry has been executed. Recorded here because the *reasons* still
constrain anything built next:

1. **Erase-restore.** `ball` reads the attribute under itself, saves it in `BallSaved`, and writes it
   back instead of 0. Blocked everything else: while erasure destroyed the playfield, "is there a
   brick at this cell?" had no reliable answer.
2. **Wall bounds as range tests.** The ball is confined to rows 1-22, columns 1-30; the old
   exact-equality tests (`cp 24`, `cp 32`) are gone, because they were only safe while the step was
   exactly ±1 and the step is now fractional.
3. **Ball↔brick.** `classify_cell` position-first, `destroy_brick` clearing both cells and
   decrementing `bricks_left` once.
4. **Ball↔paddle with a real rebound angle.** 8.8 fixed-point velocity and a 7-entry
   `rebound_table`. This had to land *with* completion detection, not after it — see
   **collision-and-physics** §7 for why.
5. **Lethal floor, lives, game over.** `paddle_hit` sets `ball_lost`; the frame loop acts on it.
   `Game_Over` is a genuinely separate path from `ReinicioJuego`'s completion screen.
6. **Automatic completion**, and the F key retired.

Fixed along the way, each verified by a test rather than by reading:

- **`SoltarTecla` compared the whole port byte against `$FF`** and so never matched — the game hung
  in the menu and could not be started at all. Now masks with `and $1F` / `cp $1F`, the idiom
  `teclado` already used. → **failure-patterns** §13
- **`teclado` froze the game while S or G was held** (`jr teclado1` without `dec d`).
- **`FinDelJuego` fell through into `CalcularAtributo`**, so pressing N never quit. It now stops.
- **Nothing reset `Coord`/`Vector`/`POSICION`** between levels or games. `reset_round` and
  `reset_game` do.
- **`flujo_juego` reached `Juego` with `CALL`**, and **`ReinicioJuego` reached `Pantalla_Reinicio`
  with `call`** — neither of which returns, so both abandoned a return address: 2 bytes per restart
  and 2 bytes per completed four-level run respectively. Both are `jp` now, the unreachable
  `jr flujo_juego` is gone, and **no known stack growth remains anywhere**. `checklist.py` carries an
  SP-stability guard for each route.
- **`main.asm`'s `SLDOPT` line said `ASSETION`**, which silently disabled DeZog's `WPMEM` /
  `LOGPOINT` / `ASSERTION` comments for the life of the project. Spelled correctly now.

## 7. Spanish → English glossary

Existing identifiers stay in Spanish — **never rename them**. New code uses English identifiers and
English comments; the codebase is accepted as mixed-language going forward. A routine called
`classify_cell` sitting next to `dibujarpala` is correct.

| Spanish | English | Where |
|---|---|---|
| `pala` | paddle | `dibujarpala`, `LONGITUDPALA`, `COLORPALA`, `Pala_Juego` |
| `pelota` | ball | `Esperar_pelota`; the routine itself is `ball` |
| `ladrillo` | brick | `Fila_Ladrillo` |
| `tablero` | board / border frame | `dibujar_tablero` |
| `mapa` | map | `Mostrar_Mapa` |
| `juego` | game | `Juego`, `Fin_Juego`, `ReinicioJuego`, `flujo_juego`, `FinDelJuego` |
| `dibujar` | draw | `dibujarpala`, `dibujar_tablero`, `Fin_Dibujo` |
| `esperar` | wait | `esperar`, `Esperar_pelota`, `EsperarTecla`, `Bucle_esperar` |
| `teclado` | keyboard | `teclado`, `teclado1`..`teclado3`, `teclado_sigue`, `tecladofin` |
| `nueva posicion` | new position | `nuevaposicion`, `POSICION` |
| `fin` | end | `Fin_Juego`, `Fin_Dibujo`, `FinDelJuego`, `tecladofin` |
| `reinicio` | restart | `ReinicioJuego`, `Pantalla_Reinicio`, `MensajeReiniciar` |
| `pantalla` | screen | `Main_Pantalla`, `Pantalla_Ini`, `Pantalla_Reinicio`, `Pantalla_GameOver` |
| `mensaje` | message | `MensajeIniciar`, `MensajeFinal`, `MensajeGameOver`, `MensajeReiniciar` |
| `fila` | row | `Fila`, `Fila_Ladrillo` |
| `contador` | counter | `CONTADOR` — the frame delay, *not* a game counter |
| `longitud` | length | `LONGITUDPALA EQU 7` |
| `color` | colour | `COLORPALA`, `dibujarpalacolor` |
| `nivel` | level | `CantidadNiveles`; note `levelCounter` is already English |
| `izquierdo` / `derecho` | left / right | `borde_izquierdo`, `borde_derecho` |
| `bucle` | loop | `bucle_principal`, `Bucle_esperar` |
| `atributo` | attribute | `CalcularAtributo` |
| `parada` | stop / halt | `FinDelJuego_Parada` |
| `vida` | life | **now exists, and is named in English:** `lives` |

## 8. What NOT to assume

- **AUDIT.md is now substantially historical.** It describes the pre-fix codebase. Its §5 trouble
  spots are all addressed; its "Highest-value first steps" list has been executed. Read it for the
  *history* and the *reasoning*, not for current behaviour. Its own corrections addendum is still
  accurate about what it corrects.
- **AUDIT.md §5.3's wall-bounce table was WRONG, and the point is now moot.** It claimed the bounces
  forced the ball 2 cells in instead of 1. The forced values were correct mirrors; the real defect
  was that the ball was allowed onto the border cells at all. That is what got fixed.
  → **collision-and-physics** §4
- **Do not assume AUDIT.md line numbers or addresses are current — the code wins, always.** Every
  address moved when `colisiones.asm` grew: `POSICION` is now `$9B10` (was `$9AD5`), `Coord` `$9ECA`
  (was `$9E6E`), and the image ends at `$A0CE` (was `$9EF2`). Resolve symbols from `main.lst`.
- **Do not assume the ball "destroying" bricks is the erase bug.** It was, before. It is now real
  collision code with a counter. The distinguishing test: destroyed bricks clear **both** cells and
  `bricks_left` goes down. → **collision-and-physics**
- **Do not assume `Vector` is two bytes of ±1.** It is now **four** bytes: two signed 8.8 words, row
  velocity at `Vector`, column velocity at `Vector+2`. → **state-and-register-contracts** §1
- **Do not assume an attribute value identifies an entity.** `$10` is both the paddle and a colour-2
  brick; **`$38` is both the ball and a colour-7 brick**, and colour 7 is the commonest brick colour
  in these maps. Classify by position. → **memory-map-and-playfield** §4
- **Do not assume `maplist` is live.** It is read exactly once (`main.asm:17`) and never indexed
  again; level advance walks the raw map data. → **map-data-format**
- **Do not assume the interrupt rewrite is on the table.** Deferred. Busy-wait is the architecture.
- **Do not assume `main.bin` exists or matches your edit.** It is no longer committed. Build first.
- **Score and an on-screen HUD remain out of scope.**
