---
name: build-and-verify
description: Use when building, running or debugging this project, or when you need to confirm a change actually works. There is no automated test suite — this file is the verification procedure. Read it before claiming any change is done.
---

# Build, run and verify

## 1. Toolchain on this machine

| Tool | Status | Where |
|---|---|---|
| **SjASMPlus 1.23.1** | installed, on `PATH` | `/usr/local/bin/sjasmplus` |
| **DeZog 3.7.4** | installed | `~/.vscode/extensions/maziac.dezog-3.7.4` |
| **ZEsarUX 13.0** | **installed, but NOT on `PATH`** | `/opt/homebrew/Caskroom/zesarux/13.0/ZEsarUX.app` |

ZEsarUX was installed as a Homebrew **cask** (an `.app` bundle), so there is no `zesarux` command.
The binary is at:

```
/opt/homebrew/Caskroom/zesarux/13.0/ZEsarUX.app/Contents/MacOS/zesarux
```

Verified runnable — `--help` responds. Two things to know:

- Homebrew marks this cask **deprecated because it fails the macOS Gatekeeper check**, with removal
  scheduled for 2026-09-01. It works today. If a future reinstall fails, get it from
  <https://github.com/chernandezba/zesarux> directly.
- Adding a shell alias or a `PATH` entry for that binary makes the run step below much less painful.

## 2. Building

One command, from the repo root:

```
sjasmplus --fullpath --lst=main.lst --sld=main.sld --raw=main.bin main.asm
```

That is exactly what the VS Code task runs (`.vscode/tasks.json:5-15`, label
**`sjasmplus: build main`**, the default build task, `cwd` = workspace folder). `launch.json` wires it
as `preLaunchTask`, so **F5 rebuilds automatically.**

To build **without touching the repo's committed artifacts**:

```
sjasmplus --fullpath --raw=/tmp/scratch/main.bin --lst=/tmp/scratch/main.lst main.asm
```

### Current baseline

```
Errors: 0, warnings: 0, compiled: 991 lines
7923 bytes, $8000-$9EF2
```

**Verified: the freshly built binary is byte-identical to the committed `main.bin`.** The working
tree has modifications (`main.asm` lost a 7-line comment header, and `main.lst`/`main.sld` were
rebuilt), but the *binary* is unchanged, because comments emit no bytes. AUDIT.md §1 records 998
lines — that was before the header removal; **991 is correct now.**

Hold that baseline. A new warning is a regression, and the line count should move by roughly what
you added.

> **One warning that is not your fault:** `--sld` without `--fullpath` prints
> `warning: missing --fullpath with --sld may produce incomplete file paths`. The repo's task passes
> `--fullpath`, so the real build is clean. Pass it in ad-hoc builds too.

## 3. The one build rule: always build `main.asm`

**Every other `.asm` in this repo is an `INCLUDE` fragment, not a standalone program.** Assembling
one directly produces a cascade of `error: Label not found` (`dibujar_tablero`, `PosXY`,
`CalcularAtributo`, …) and a garbage binary whose every `call` target is assembled as `CD 00 00`.

This is not hypothetical — **the wreckage is committed**, though it varies by file. Measured error
counts in the committed listings:

| File | `Label not found` errors |
|---|---|
| `mensaje_inicio.lst` | 6 (`PRINTAT` ×3, `CLEARSCR` ×2, …) |
| `Partida.lst` | 4 (`dibujar_tablero`, `Mostrar_Mapa`, `posicionpala`, `Pantalla_Reinicio`) |
| `PintarMapa.lst` | 3 |
| `pala.lst` | 1 (`Fin_Juego`) |
| `pelota.lst` | 0 — `pelota.asm` happens to be self-contained |
| `Pantalla_Inicio.lst` | 0 — likewise |

`Partida.bin` is 34 bytes of nothing. Note that a **clean** standalone build is not a safe one:
`pelota.bin` assembles without errors but is a fragment `org`'d at `$8000` containing only the ball
code, so loading it runs whatever those bytes decode to. **Never load any per-file `.bin`.** The only
valid artifacts are `main.bin` / `main.lst` / `main.sld`.

**Regression signal:** the historical cause was `tasks.json` building `${file}` — whatever file had
editor focus — and `launch.json` loading `${fileBasenameNoExtension}`. Both are **already fixed** on
disk (verified: they hardcode `main.asm` / `main.sld` / `main.bin`), so AUDIT.md §1's description of
this is stale. **If `${file}` or `${fileBasenameNoExtension}` ever reappears in either file, the bug
is back.** → **failure-patterns** §7

`main.lst` is also how you look up addresses — symbol locations, instruction encodings, the map
terminator addresses in **map-data-format** §6. Keep it around.

## 4. Running

**Step 1 — start ZEsarUX with the remote protocol enabled**, in its own terminal:

```
/opt/homebrew/Caskroom/zesarux/13.0/ZEsarUX.app/Contents/MacOS/zesarux --enable-remoteprotocol
```

`--enable-remoteprotocol` is the documented flag (DeZog's own `Usage.md` uses exactly
`./zesarux --enable-remoteprotocol &`). ZRCP listens on **port 10000**, which is what
`.vscode/launch.json:9` expects. Leave it running — DeZog connects to it, it does not launch it.

The target is a 48K Spectrum, which is ZEsarUX's default machine, so no `--machine` flag is needed.
If your ZEsarUX has a saved config that boots something else, add `--machine 48k`.

**Step 2 — launch from VS Code.** Press **F5** with the **`Arkanoid (ZEsarUX)`** configuration
selected. That runs the build task, connects over ZRCP, loads `main.bin` at `$8000`, and starts at
`execAddress` `$8000` (`launch.json:8-17`).

**Step 3 — what a working run looks like:**

1. RLE title screen decodes into the bitmap.
2. `Quieres Jugar (S/N)?` prompt on row 23, with a flashing yellow cell.
3. Press **S** → screen clears, border drawn, bricks painted, paddle on row 23, ball moving.

### Failure modes

| Symptom | Cause |
|---|---|
| Connection refused / DeZog hangs connecting | ZEsarUX not running, or not started with `--enable-remoteprotocol`, or not on port 10000 |
| Blank or garbage screen, immediate crash | Stale or wrong binary — rebuild; confirm you built `main.asm` (§3) |
| Nothing happens at all | Loaded a per-file `.bin` (§3) |
| Game freezes, ball and paddle both stop | **Known bug**, not yours: you are holding **S** or **G** (`pala.asm:54-56`). Release the key. → **timing-and-frame-loop** §4 |
| Everything runs far too fast | Emulator not at 3.5 MHz. All pacing is busy-wait. → **timing-and-frame-loop** §8 |

### Keyboard reference

| Key | Effect |
|---|---|
| **A** / **D** | Move paddle left / right, one cell per frame |
| **F** | Advance to next level — **debug hook**, the only level advance that exists (`pala.asm:44-48`) |
| **S** | "Yes" at menu prompts |
| **N** | "No" — **does not actually quit.** `FinDelJuego` falls through into `CalcularAtributo` (`mensaje_inicio.asm:48`→`52`) and silently resumes polling. → **failure-patterns** §12 |
| **S** or **G** during play | **Freezes the game** until released (known bug) |

## 5. Lightweight verification: DeZog comment directives

This is the closest thing to a test harness that exists today.

### First: fix the typo

`main.asm:2` reads:

```asm
	SLDOPT COMMENT WPMEM, LOGPOINT, ASSETION
```

**`ASSETION` is a misspelling of `ASSERTION`.** DeZog's documentation gives the correct line as
`SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION`, and notes that if the `SLDOPT` info is missing,
**sjasmplus strips those comments out of the SLD file entirely**. So assertions are currently not
enabled at all — and grep confirms there is not a single `WPMEM`, `LOGPOINT` or `ASSERTION` comment
anywhere in the sources, so nothing has ever exercised it.

**Fixing that one word is the cheapest possible improvement to this project's testability.** This
skill documents it; it does not make the change.

### What actually works on ZEsarUX

From DeZog 3.7.4's remote-capability table — **this matters, because the project uses ZEsarUX, not
zsim:**

| Directive | zsim | **ZEsarUX** |
|---|---|---|
| `WPMEM` (watchpoints) | yes | **yes** — 16-bit addresses only |
| `ASSERTION` | yes | **yes**, per the table |
| `LOGPOINT` | yes | **no** |

Three consequences you need before you plan a debugging session:

- **`LOGPOINT` does not work on ZEsarUX.** Do not build a verification approach around it. If you
  want log output you must temporarily switch the launch config to `zsim`, accepting that its timing
  is not cycle-accurate.
- **The documentation contradicts itself on `ASSERTION`.** The capability table says ZEsarUX supports
  it, but a note further down (`Usage.md`, in the ASSERTION section) states "ASSERTION is not
  available in ZEsarUX." **Unresolved — confirm empirically before relying on it**, and if it does
  not fire, that note is the reason, not your syntax.
- `${Remote.tStates}` and `${Remote.cpuFrequency}` are **zsim-only**. Given how much of this project
  is T-state arithmetic (**timing-and-frame-loop** §3), that is a real limitation.

### Syntax, and three examples for this codebase

```
; WPMEM [addr [, length [, access]]]        access: r, w, or rw
; ASSERTION <expression>
; LOGPOINT [group] text ${expression[:format]}
```

**(a) The ball stays inside the playfield** — the highest-value assertion here. Per
**collision-and-physics** §4, the wall checks are exact-equality tests that hold only while the step
is ±1; if that ever breaks, the ball leaves the attribute file and writes into arbitrary memory. This
catches it immediately.

`Coord` is at `$9E6E` with the **column in byte 0 and the row in byte 1**
(**state-and-register-contracts** §1 — the declaration comment is wrong):

```asm
        ld (Coord), hl
        ret             ; ASSERTION b@(Coord) <= 31 && b@(Coord+1) <= 23
```

> **Critical gotcha:** an ASSERTION becomes a breakpoint and is evaluated **before** the instruction
> on its line. To check the *result* of an instruction, attach it to the **next instruction** — above,
> the `ret` at `pelota.asm:57`, by which point `ld (Coord),hl` has run.
>
> Attach it to a real instruction, not a comment-only line. DeZog resolves directives through the SLD
> file, which maps source lines to addresses; a bare comment line may have no address to bind to.
> **Unconfirmed on this setup** — if the assertion never fires, try moving it onto an instruction
> line before assuming the expression is wrong. And see the ZEsarUX caveat above: DeZog's own docs
> contradict themselves on whether ASSERTION works on this remote at all.

**(b) Catch an unintended write to paddle state.** `POSICION` is 2 bytes at `$9AD5`. Only
`nuevaposicion` should ever write it:

```asm
POSICION: DB 14,0       ; WPMEM, 2, w
```

The `2` covers both bytes. That matters: DeZog's docs warn that a 16-bit write (`LD (nn),HL`) only
checks the **upper** address, so a watchpoint covering just the first byte can miss a word write
entirely. Always cover the whole variable.

**(c) Log the brick counter each frame** — useful once collision work starts and the counter from
**collision-and-physics** §9 exists:

```asm
; LOGPOINT [BALL] bricks=${b@(bricks_left)} cell=${b@(Coord+1)},${b@(Coord)}
```

**But per the table above, this will not fire on ZEsarUX.** It is here so you know the syntax and
know to switch remotes deliberately if you want it.

### Honest limitations

DeZog directives are **debugger-side breakpoints attached to source lines**. They do not run outside
a debug session, they do not produce a pass/fail artifact, and **they are not a regression suite**.
Also, they are read from the SLD file at debug start — **change one and you must rebuild and restart
the debugger** before it takes effect.

## 6. The manual verification protocol

There is no automated test. This checklist *is* the verification, and it only works if run honestly.

### Every change, without exception

- [ ] Build is **0 errors, 0 warnings**.
- [ ] `compiled: N lines` moved by roughly what you added (baseline **991**).
- [ ] The game still boots to the title screen, prompt, and a playable board.

### Known-bad baseline — do NOT report these as regressions

> **These are code-derived predictions, not observations.** AUDIT.md §5 is explicit that *"none of it
> has been observed running, because no test procedure exists"*, and that is still true of this whole
> table — every entry was derived by reading source. **Check them, do not assume them.** If one does
> not reproduce, the analysis is wrong and that is worth knowing; if you see a symptom that is not
> here, do not force it onto the nearest row.

Confirm these are *unchanged*, not fixed, unless fixing them was your task:

| Behaviour | Why |
|---|---|
| Ball erases a trail through bricks and the border | The erase writes 0 with no restore (`pelota.asm:10`). → **memory-map-and-playfield** §2 |
| Bricks "disappear" when the ball passes through | Same cause. **This is not collision working** |
| Ball cannot be lost; floor always bounces | `pelota.asm:15-21` |
| `map2`'s indestructible bricks are invisible | Colour 8 → `$40`, bright black on black. → **map-data-format** §3 |
| Levels advance only on **F** | Debug hook. → **failure-patterns** §4 |
| Holding **S** or **G** freezes the game | `pala.asm:54-56` |
| Pressing **N** does not quit | `mensaje_inicio.asm:48`→`52` |
| Ball flickers (~27% off-duty) and display tears | Structural to the busy-wait model. → **timing-and-frame-loop** §7 |
| Second game starts with ball/paddle where the last ended | No reset routine. → **state-and-register-contracts** §5 |

### Paddle change

- [ ] A and D move the paddle exactly **one cell per frame**.
- [ ] Paddle stays within columns **1-24** (7 cells spanning 1-30); it never overwrites the border at
      column 0 or 31.
- [ ] No trail left behind — the old position is fully erased each frame.
- [ ] Held key repeats smoothly; released key stops it.

### Ball change

- [ ] Ball advances exactly **one cell per frame** (count against a wall bounce).
- [ ] Bounces off all four edges and keeps moving.
- [ ] **Never leaves the attribute area** — no corruption elsewhere on screen, no crash. Use
      assertion (a) above.
- [ ] Speed feels unchanged unless you meant to change it — and if you did, check the *paddle* too;
      they are coupled. → **timing-and-frame-loop** §5

### Map change

- [ ] All levels render; step through every one with **F** (or with whatever replaced it, once
      completion detection has landed and the F key is retired).
- [ ] Bricks start at column **1** and no row overruns column **30** (max 15 entries/row).
- [ ] Each brick is 2 cells wide.
- [ ] Rows land where you specified; nothing overlaps the paddle row 23 or the top border row 0.
- [ ] After the last level, the "La partida ha finalizado" screen appears rather than garbage —
      that path is order-sensitive. → **map-data-format** §8

### Collision change (once that work starts)

- [ ] **Erase-restore first**: the ball leaves **no trail** through bricks or border. This is the
      single clearest pass/fail signal that step 1 landed.
- [ ] Ball bounces off bricks and destroys them; **both cells** of each brick clear together.
- [ ] Colour-8 bricks bounce the ball and are **not** destroyed (test on `map2` — they are invisible,
      so watch for the bounce, not the brick).
- [ ] Ball bounces off the paddle, and the rebound direction varies with **where** on the paddle it
      hit.
- [ ] Ball is lost when the paddle misses; lives decrement; a fresh ball is served.
- [ ] At zero lives, the game-over path is reached — and it is **distinct** from the level-completion
      screen.
- [ ] Level completes automatically when the last destructible brick is destroyed, with no F press.
- [ ] Counter reaches exactly zero — not negative, not stuck at 1. This is where an off-by-one in the
      2-cells-per-brick logic shows up.

## 7. What is deliberately not here

No automated tests, no CI, no golden screenshots, no scripted ZRCP harness. Building a scripted
harness now would mean writing assertions about behaviour that has not been designed yet, so the
sensible point to reconsider it is **once real collision and game logic exist to test against**. That
is a judgement recorded here, not a commitment anyone has made — there is no such plan in the repo,
the history, or AUDIT.md, so do not wait on one. Until then, verification is the protocol in §6, run
honestly.

## 8. Repo hygiene — recommendations, not requirements

Every build artifact is committed and there is no `.gitignore`, which is why five of seven commits
are dominated by thousands of lines of `.lst`/`.sld` churn. Three cheap improvements are available;
**the decision is the maintainer's.**

1. **A `.gitignore`** for `*.bin`, `*.lst`, `*.sld`. Caveat worth weighing: `main.lst` is genuinely
   useful for looking up addresses and encodings, and several skills cite it. If it stops being
   committed, anyone needing those numbers must build first — which is fine, as long as they know
   that is where the numbers come from.
2. **Delete the broken per-file artifacts** — `Partida.*`, `pelota.*`, `pala.*`, `PintarMapa.*`,
   `mensaje_inicio.*`, `Pantalla_Inicio.*` (`.bin`/`.lst`/`.sld` only, never the `.asm`). They are
   error-riddled standalone builds and actively dangerous to load (§3).
3. **Delete the orphaned `plantilla.*`** — `plantilla.asm` never existed in this repo, so these three
   files are output with no source. Also `.tmp/disasm.list`, an empty DeZog scratch file.
   → **failure-patterns** §11

None of this is required to make progress on the game. It is listed because each one removes a way to
waste time.
