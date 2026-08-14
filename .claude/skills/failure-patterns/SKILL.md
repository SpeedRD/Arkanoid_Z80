---
name: failure-patterns
description: Use when debugging anything that looks broken, when you are about to add a debug hook or a stub file, when reading git history or blame here, or when a change feels like it is repeating something the project already tried. Also read before concluding you have found a new bug — most "new" bugs here are known ones.
---

# Failure patterns

Seven commits, 29 Nov – 12 Dec 2024. This is a student project that stopped mid-build; the point of
this file is the transferable lesson in each case, not blame. Every claim below was verified against
git.

Each entry: **what happened → why → the rule now → how to notice you are doing it again.**

## 1. Reverted-by-overwrite

**What happened.** Seven commits, one branch (`develop`), **no merges, no `git revert`, no tags
beyond `pre-audit`.** Everything that was undone was undone by overwriting files in place. An entire
paddle implementation, a `COORD` variable, a debug hook and a halt loop were all removed this way.

**Why.** Small team, short deadline, no branching habit. Overwriting is the path of least resistance
when you are not thinking of the history as a record.

**The rule now.** Experiments get a real commit or a branch. If you try an approach and abandon it,
the history should say so — a reverted commit is a signpost; an overwritten file is a silent gap.

**How to notice.** You are about to delete a block of working code and replace it wholesale, with the
old version existing nowhere but your editor's undo buffer.

**Consequence for readers:** `git log --follow` and `git blame` are misleading here. The only record
of an abandoned approach is a deleted block inside a diff, so **searching diffs (`git log -p`) finds
things that searching the tree cannot.**

## 2. The paddle that owned the game loop

**What happened.** `43848fe` rewrote `pala.asm` — **115 deletions, 79 insertions**, verified by
diffstat. The old implementation, `posicionpala` (`63aa40f:pala.asm:9`), had:

- its own `di` and `ld sp,0` (`:10-11`), duplicating `main.asm`
- its own `leerteclas` polling loop (`:25`)
- a `mueveizquierda` / `muevederecha` / `parademover` state machine (`:41,52,63`) that never returned

**The game *was* the paddle routine.** Nothing else could run, which made adding a ball impossible.

The same shape appeared in the ball a commit later: `ball` originally ended in `jr ball`
(`43848fe:pelota.asm:56`) — a self-contained infinite loop. `561cc23` changed it to `ret`, verified
in the diff.

**Why.** The natural first shape for "make the paddle move" is a loop that reads keys and redraws.
It only becomes a problem when a second entity needs to exist.

**The rule now.** **Every gameplay routine returns each frame. No routine owns the loop.** The loop
lives in `Pala_Juego` (`Partida.asm:8-15`) and calls out to `ball`, `teclado`, `nuevaposicion`,
`dibujarpala`, `esperar`. → **timing-and-frame-loop**

**How to notice.** You are writing `jr <your own label>` at the end of a routine, or a `di`/`ld sp`
outside `main.asm`.

**Also lost in that rewrite:** the named constants `LIMITEDERECHO EQU 31 - LONGITUDPALA` and
`LIMITEIZQUIERDO EQU 1` (`63aa40f:pala.asm:2-3`) became inlined literals in `nuevaposicion`
(`pala.asm:75`, `32-LONGITUDPALA`, plus an implicit zero test). Same behaviour, less legible. A
rewrite that fixes the structure can still lose the documentation that was encoded in names.

## 3. The misdiagnosed DeZog bug

**What happened.** The old `leerteclas` carried this comment **three times**, at
`63aa40f:pala.asm:29`, `:32` and `:35`:

> *"hay un problema en el dzog y me lo guarda negado, por eso en el siguiente ponemos "z" y no "nz""*
> — "there's a problem in DeZog and it stores it negated, so we use `z` and not `nz`"

**It was a misdiagnosis.** The debugger was innocent. **The ZX Spectrum keyboard is active-low:** you
read a half-row with `IN A,(C)` on a port like `$FDFE` or `$7FFE`, and bits 0-4 report the five keys
with **0 = pressed, 1 = released**. The old code's `jr z` was correct for exactly that reason.

**Why.** "Pressed = 1" is the intuitive model. When the hardware disagrees, the tool is the easier
thing to blame — especially when the code works after you flip the condition, which "confirms" the
wrong theory.

**Where it stands today.** The rewrite happens to be correct. `teclado` reads the half-row, masks
with `and $1F`, and compares against `$1F` (`pala.asm:36-38`) — if *any* of the five bits is 0, a key
is down. It then dispatches with `bit n,a` + `jr nz` to **skip** when the bit is 1, i.e. not pressed
(`:45-46,50-51,55-56`). Correct throughout. The bug is gone, but nobody wrote down why.

**The rule now.** When the tool seems wrong, **verify your model of the hardware first.** And write
the convention down at the point the code depends on it — this file and
**state-and-register-contracts** are where it now lives.

**How to notice.** You are writing a comment that blames a tool for a behaviour you have not
independently confirmed, or you flipped a condition until it worked without understanding why.

## 4. The debug hook that became the feature

**What happened.** `7d39c74` added to `main.asm:27`:

```asm
call Pantalla_Reinicio  ;esta pantalla funciona, se puede probar pulsando f dentro del "juego"
```

— "this screen works, you can test it by pressing F inside the game". `63aa40f` removed that call
(verified: gone from `63aa40f:main.asm`). **But the F-key handling stayed**, and it is still there at
`pala.asm:44-48`, still the **only** way to advance a level, twenty months later.

**Why.** The hook was genuinely useful, removing it had no urgency, and no real completion detection
ever arrived to replace it. Nothing forced the question.

**The rule now.** **A debug hook gets a removal plan the day it is added** — a TODO at the hook, an
issue, or a note in the skill that owns the feature. A temporary mechanism with no owner becomes
permanent.

**How to notice.** You are adding a keypress, a hardcoded value or a shortcut "just to test", and you
have not written down what removes it. → **collision-and-physics** §9 retires the F key.

## 5. Empty stub files as intent markers

**What happened.** `MapaJuego.asm` was created empty in `2532582` and deleted in `7d39c74` — verified
by `--diff-filter=AD`: added, then deleted, **never having had any content.**

`colisiones.asm` is the identical pattern one file later. Created empty in `43848fe`, `INCLUDE`d at
`main.asm:35`, and **still 0 bytes at HEAD.**

**Why.** Creating the file feels like starting the work, and the `INCLUDE` line assembles cleanly, so
nothing ever complains.

**The rule now.** An empty included file is not progress. It costs zero bytes, produces zero errors,
and looks like a plan.

**How to notice.** You are creating a file to hold work you are not about to do.

**The one genuine upside:** because the `INCLUDE` already exists, collision code needs **no build
change** — just write into `colisiones.asm`. → **assembler-conventions** §8

## 6. Committing known-broken work with the problem only in the message

**What happened.** Three of seven commit messages state a known defect:

| Commit | Message | Meaning |
|---|---|---|
| `7d39c74` | "Mapas cambiando, **pala medio corregida**" | paddle **half-fixed** |
| `43848fe` | "Nueva pala **para corregir**, pelota **para integrar**" | paddle **to be fixed**, ball **to be integrated** |
| `561cc23` (HEAD) | "**falta optimizar** el codigo de la pelota" | **still need to optimise** the ball |

**The project's final commit message says the ball is unfinished.** That is the most important
sentence in the repository's history, and it is in the one place nobody re-reads.

**Why.** The commit message is where the defect is on your mind. It feels recorded.

**The rule now.** Committing work in progress is fine. **The known defect belongs somewhere durable**
— a skill, AUDIT.md, or a comment at the defect itself. Not only in a commit message.

**How to notice.** Your commit message contains "still need to", "half-", "to be fixed", or "TODO"
and nothing in the tree says the same thing.

**A sharper variant, from the same commit:** `561cc23` *added* the comments
`; Coordenadas iniciales de la pelota (fila, columna)` and `; Vector de movimiento inicial (X, Y)` to
`pelota.asm:1-2` — and **both are wrong** (the ball actually starts at row 20, column 16, and byte 0
of `Vector` is the row delta). A comment added in haste is worse than no comment, because the next
reader trusts it. → **state-and-register-contracts** §1

## 7. The focused-file build bug — fixed, but know the shape

**What happened.** `.vscode/tasks.json` used to build `${file}` — **whatever source file had editor
focus** — with no fixed entry point. Build with `pelota.asm` focused and you got a broken
`pelota.bin`. `launch.json` had the matching problem with `${fileBasenameNoExtension}`, so the
**debugger loaded the wrong binary** too.

It happened repeatedly and **the wreckage is committed**: `mensaje_inicio.lst`, `Partida.lst`,
`PintarMapa.lst` and `pala.lst` are standalone builds of INCLUDE fragments carrying 6, 4, 3 and 1
`error: Label not found` respectively (`PRINTAT`, `dibujar_tablero`, `Mostrar_Mapa`, `Fin_Juego`, …),
with the unresolved `call`s assembled as `CD 00 00`. `Partida.bin` is 34 bytes of garbage.
`pelota.lst` and `Pantalla_Inicio.lst` assemble cleanly — those two files are self-contained — but
their `.bin`s are still fragments and must not be loaded. → **build-and-verify** §3

**Status: already fixed.** Verified on disk — `.vscode/tasks.json` now hardcodes `main.asm` →
`main.lst`/`main.sld`/`main.bin`, and `.vscode/launch.json` points at fixed paths.
**AUDIT.md §1 describes the pre-fix state and is stale on this point.**

**The rule now.** **A build has exactly one entry point.** Every other `.asm` here is an INCLUDE
fragment and is not independently assemblable.

**How to notice — this is the regression signal:** if `${file}` or `${fileBasenameNoExtension}` ever
reappears in `tasks.json` or `launch.json`, the bug is back. Also: never load any per-file `.bin`.
→ **build-and-verify**

## 8. Ping-ponging absolute paths

**What happened.** `.vscode/tasks.json` had its `command` edited in **4 of 7 commits**, alternating:

```
2532582   C:/UFV Tercero~Cuarto/Arquitectura/sjasmplus118       (no .exe)
7d39c74   D:/UFV/Arquitectura/sjasmplus118.exe
43848fe   C:/UFV Tercero~Cuarto/Arquitectura/sjasmplus118.exe
561cc23   D:/UFV/Arquitectura/sjasmplus118.exe
```

Two machines fighting over one hardcoded path, committing over each other. A third stale directory
name (`Pantalla_InicioyFinal`) survives inside the `.lst` files.

**Why.** The tool was not on `PATH`, so the quickest fix was to point at it directly — on your
machine.

**The rule now.** **No absolute machine-specific paths in checked-in build config.** The current
`tasks.json` invokes plain `sjasmplus` and resolves via `PATH`. Keep it that way.

**How to notice.** You are editing a checked-in config to make it work on your machine, and the edit
contains a drive letter or a home directory.

## 9. Eyeball tuning, all at once, at the end

**What happened.** `561cc23` — the final commit — changed **four** behavioural constants in one
sitting, all verified in the diff:

| Change | From | To |
|---|---|---|
| `ball`'s terminal instruction | `jr ball` | `ret` |
| `Esperar_pelota` delay | `$1f00` | `$1100` |
| `LONGITUDPALA` | 4 | 7 |
| `CONTADOR` | `$01FF` | `$03FF` |

**So the current speed and size numbers are one evening of eyeballing, done the day before work
stopped.** They are not a considered baseline.

**Why.** Tuning feel is genuinely iterative and you only notice the interactions when playing.

**The rule now.** **Retune freely, but deliberately, and one axis at a time.** Ball and paddle speed
are coupled through a single frame loop via two unrelated constants in two files —
**timing-and-frame-loop** §5 owns the interaction, and §6 owns the hard constraint that speed changes
go into the delays, never the step size.

**How to notice.** Your diff changes more than one feel constant and you cannot say which one caused
the improvement.

## 10. Dead code left in place

All verified present at HEAD:

| Dead thing | Where | Why it misleads |
|---|---|---|
| `fin_dibujar_tablero: jr fin_dibujar_tablero` | `tablero.asm:38` | Unreferenced and unreachable. Looks like a halt state; the project has none. |
| `call Pala_Juego` | `PintarMapa.asm:40` | Sits after an unconditional `jr Fila` (`:39`). Never executes. Suggests the renderer calls the game loop. It does not. |
| `maxLevelsMask: EQU 3` | `Mapas.asm:15` | Grep-verified never referenced. Suggests a mask-based level wrap that does not exist. |
| `maplist` | `Mapas.asm:14` | Read **once** at `main.asm:17`, never indexed. Looks like the level table; level advance actually walks raw map data. → **map-data-format** §7 |
| `COORD: DB 0` | removed in `43848fe` (was `63aa40f:pala.asm:7`) | Was never read or written. |
| `fin: jr fin` | added in `43848fe:pala.asm`, removed in `561cc23` | An infinite-loop halt that existed for one commit. **The project currently has no halt state at all.** |

**The most consequential one:** `7d39c74` deleted a commented-out block from `PintarMapa.asm` — an
`or a / jr z, Salto_Ladrillo` zero-colour skip with register saving and a column-advance path. The
author tried to make the renderer **skip** empty cells, gave up, and settled on painting colour 0
over them instead. **That is why "empty" and "erased" are indistinguishable in the attribute file
today**, which directly constrains collision design. → **map-data-format** §3,
**collision-and-physics** §3

**The rule now.** Delete dead code, or comment why it stays. Unreachable code that looks live sends
the next reader down a false trail — and here, one abandoned optimisation silently set a constraint
that outlived it by twenty months.

## 11. Orphaned artifacts

**What happened.** `plantilla.bin`, `plantilla.lst` and `plantilla.sld` are committed, but
**`plantilla.asm` does not exist in the repo and never did.** They are build output from the
course-provided template, assembled once and then renamed to `main.asm`. The `.lst` still references
`C:\UFV Tercero~Cuarto\Arquitectura\Pantalla_InicioyFinal\plantilla.asm`.

`.tmp/disasm.list` is a committed empty DeZog scratch file.

**Why.** No `.gitignore`, so `git add .` swept in everything.

**The rule now.** Build output should not be committed; if it is, it must correspond to a source file
that exists.

**How to notice — the practical hazard:** you can lose real time searching for the source of a
committed artifact that has none. If you cannot find the `.asm` for a `.bin`, check whether it ever
existed (`git log --all --diff-filter=A -- <name>.asm`) before assuming you are missing something.
→ **build-and-verify** §8

## 12. Structural defects still live

Pointers only — each is owned elsewhere. Do not "discover" these as new bugs.

| Defect | Where | Owner |
|---|---|---|
| `teclado` hangs while S or G is held (`jr teclado1` without `dec d`) | `pala.asm:54-56` | **timing-and-frame-loop** §4 |
| `FinDelJuego` falls through into `CalcularAtributo`; pressing N never quits | `mensaje_inicio.asm:48`→`52` | **collision-and-physics** §8 |
| Stack leak: `call Fin_Juego` + `jr Juego` abandons 2 return addresses per level | `pala.asm:47`, `Partida.asm:30` | **state-and-register-contracts** §4 |
| `Pantalla_Reinicio` ends `call flujo_juego`, which never returns | `mensaje_inicio.asm:39` | **state-and-register-contracts** §4 |
| Top border writes 32 cells from `$5801`, spilling one into row 1 col 0 | `tablero.asm:29` | harmless (the cell is already border colour) but wrong |
| Colour-8 bricks render invisible (bright black on black) | `PintarMapa.asm:23-25` | **map-data-format** §3 |
| `Coord` / `Vector` comments state the wrong axis order | `pelota.asm:1-2` | **state-and-register-contracts** §1 |
| Nothing resets `Coord`/`Vector`/`POSICION` between levels or games | — | **state-and-register-contracts** §5 |

## Smells to check in a diff

- [ ] A routine ending in `jr <its own label>` — something is trying to own the loop again (§2).
- [ ] `di` or `ld sp` anywhere but `main.asm:5-6` (§2).
- [ ] A comment blaming a tool for a behaviour not independently confirmed (§3).
- [ ] A new debug key or hardcoded shortcut with no removal plan (§4).
- [ ] A new empty or near-empty file added to the `INCLUDE` list (§5).
- [ ] A commit message containing "TODO", "half-", "to be fixed" with nothing durable in the tree (§6).
- [ ] `${file}` or `${fileBasenameNoExtension}` in `.vscode/*.json` (§7).
- [ ] A drive letter or home directory in checked-in config (§8).
- [ ] More than one feel constant changed at once (§9).
- [ ] Code added after an unconditional `jr`/`jp`/`ret` (§10).
- [ ] A `call` to something that jumps back into the main loop instead of returning (§12).
- [ ] A comment asserting a register or byte order you have not traced (§6, and `Coord` is the
      cautionary tale).
