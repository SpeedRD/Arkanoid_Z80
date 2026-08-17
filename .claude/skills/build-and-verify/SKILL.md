---
name: build-and-verify
description: Use when building, running or debugging this project, or when you need to confirm a change actually works. Covers the build script, the ZEsarUX/DeZog run procedure, and the automated test suites in tests/. Read it before claiming any change is done.
---

# Build, run and verify

## 1. Toolchain on this machine

| Tool | Status | Where |
|---|---|---|
| **SjASMPlus 1.23.1** | installed, on `PATH` | `/usr/local/bin/sjasmplus` |
| **DeZog 3.7.4** | installed | `~/.vscode/extensions/maziac.dezog-3.7.4` |
| **ZEsarUX 13.0** | **installed, but NOT on `PATH`** | `/opt/homebrew/Caskroom/zesarux/13.0/ZEsarUX.app` |
| **Python 3** | for the test harness | `tests/` |

ZEsarUX was installed as a Homebrew **cask** (an `.app` bundle), so there is no `zesarux` command:

```
/opt/homebrew/Caskroom/zesarux/13.0/ZEsarUX.app/Contents/MacOS/zesarux
```

Homebrew marks this cask **deprecated because it fails the macOS Gatekeeper check**, with removal
scheduled for 2026-09-01. It works today. If a future reinstall fails, get it from
<https://github.com/chernandezba/zesarux> directly.

## 2. Building

```
./build.sh              # builds main.bin / main.lst / main.sld in place
./build.sh /tmp/out     # builds into another directory, leaving the repo clean
```

`build.sh` wraps the one real command and adds the check that matters:

```
sjasmplus --fullpath --lst=main.lst --sld=main.sld --raw=main.bin main.asm
```

**sjasmplus exits 0 even when it emits warnings**, so the script reads the `Errors:` summary line and
fails unless it is `Errors: 0, warnings: 0`. Use the script rather than the raw command — a build
that "succeeded" with warnings is a regression you will not otherwise notice.

The VS Code task (`.vscode/tasks.json`, label **`sjasmplus: build main`**, the default build task)
runs the same sjasmplus invocation, and `launch.json` wires it as `preLaunchTask`, so **F5 rebuilds
automatically.**

### Current baseline

```
Errors: 0, warnings: 0, compiled: 1538 lines
8399 bytes, $8000-$A0CE
```

Hold that baseline. A new warning is a regression, and the line count should move by roughly what you
added. (It was 991 lines / 7923 bytes before collision work; `colisiones.asm` accounts for most of
the difference.)

> **One warning that is not your fault:** `--sld` without `--fullpath` prints
> `warning: missing --fullpath with --sld may produce incomplete file paths`. `build.sh` passes
> `--fullpath`, so the real build is clean. Pass it in ad-hoc builds too.

## 3. The one build rule: always build `main.asm`

**Every other `.asm` in this repo is an `INCLUDE` fragment, not a standalone program.** Assembling
one directly produces a cascade of `error: Label not found` and a garbage binary whose every `call`
target is assembled as `CD 00 00`. Note that a *clean* standalone build is not a safe one either:
`pelota.asm` used to assemble without errors but produced a fragment `org`'d at `$8000` containing
only the ball code.

The wreckage from this used to be committed. It is now deleted, and `.gitignore` covers
`*.bin`/`*.lst`/`*.sld` — with `!charset.bin` excepted, because that is a **source asset**
(`incbin`'d by the text library), not build output. Deleting or ignoring it breaks the build.

**`main.bin`/`main.lst`/`main.sld` are no longer committed.** `main.lst` is how you look up addresses,
and the test harness resolves every symbol from it, so **build before you read addresses or run
tests**. `run_all.py` does this for you.

**Regression signal:** the historical cause of wrong-binary debugging was `tasks.json` building
`${file}` — whatever file had editor focus — and `launch.json` loading `${fileBasenameNoExtension}`.
Both are fixed. **If `${file}` or `${fileBasenameNoExtension}` ever reappears in either file, the bug
is back.** → **failure-patterns** §7

## 4. Running

**Step 1 — start ZEsarUX with the remote protocol enabled**, in its own terminal:

```
/opt/homebrew/Caskroom/zesarux/13.0/ZEsarUX.app/Contents/MacOS/zesarux \
    --enable-remoteprotocol --remoteprotocol-port 10000 --machine 48k &
```

ZRCP listens on **port 10000**, which is what `.vscode/launch.json` expects. Leave it running — DeZog
connects to it, it does not launch it. 48K is ZEsarUX's default machine, but pass `--machine 48k`
anyway in case a saved config says otherwise.

**Step 2 — launch from VS Code.** Press **F5** with the **`Arkanoid (ZEsarUX)`** configuration
selected. That runs the build task, connects over ZRCP, loads `main.bin` at `$8000` and starts there.

**Step 3 — what a working run looks like:**

1. RLE title screen decodes into the bitmap.
2. `Quieres Jugar (S/N)?` prompt on row 23, with a flashing yellow cell.
3. Press **S** → screen clears, border drawn, bricks painted, paddle on row 23, ball moving.
4. The ball bounces off bricks and destroys them, two cells at a time.
5. Miss the ball and you lose one of three lives; lose all three and you get **GAME OVER**.
6. Clear every destructible brick and the level advances by itself.

### Failure modes

| Symptom | Cause |
|---|---|
| Connection refused / DeZog hangs connecting | ZEsarUX not running, or not started with `--enable-remoteprotocol`, or not on port 10000 |
| `close-all-menus` / `enter-cpu-step` return errors; the CPU sits frozen at one PC; keys have no effect | **ZEsarUX is wedged with a menu open.** Nothing you did in the game causes this. Restart it: `pkill -f 'zesarux --enable-remoteprotocol'`. This is the single most common way to waste an hour here — see §7 |
| Blank or garbage screen, immediate crash | Stale or wrong binary — rebuild; confirm you built `main.asm` (§3) |
| Everything runs far too fast | Emulator not at 3.5 MHz. All pacing is busy-wait → **timing-and-frame-loop** §8 |

### Keyboard reference

| Key | Effect |
|---|---|
| **A** / **D** | Move paddle left / right, one cell per frame |
| **S** | "Yes" at menu prompts |
| **N** | "No" — shows the goodbye screen and **now genuinely stops** |
| **F** | Nothing. The level-advance debug hook is **retired**; levels advance on their own |
| **S** or **G** during play | Nothing. They **no longer freeze the game** |

## 5. The automated suites

`tests/` drives ZEsarUX over ZRCP directly — no VS Code, no DeZog, no human at the keyboard. Start
ZEsarUX as in §4, then:

```
python3 tests/run_all.py                 # build + every suite
python3 tests/run_all.py test_colisiones # just one
```

`run_all.py` builds first and refuses to run anything if the build is not clean.

| Suite | Covers |
|---|---|
| `test_pelota.py` | `classify_cell`'s truth table and `IX` preservation; wall geometry confining the ball to rows 1-22 / columns 1-30; fractional velocity never moving more than one cell per axis per frame; and the headline check — **the attribute file is byte-identical after 200 completed frames on an empty field** |
| `test_colisiones.py` | Byte 0 of all four maps reaching `bricks_left`; both cells of a brick clearing with exactly one decrement, for odd and even columns; colour-8 bricks bouncing without being destroyed or counted; vertical/horizontal/diagonal resolution including two bricks in one frame; every entry of the rebound table and its two invariants |
| `test_juego.py` | `teclado` dispatch, and that S/G/F **return instead of freezing**; no `call Fin_Juego` left in `pala.asm`; `reset_round`/`reset_game` byte by byte; the ball-lost flag; and that `FinDelJuego` stops instead of falling through |
| `checklist.py` | §6 below, end to end on a live game — plus two **SP-stability guards**, one per route out of the game, that catch any `CALL` to a routine that never returns |

Two properties make this testable at all: **the attribute file at `$5800` IS the playfield**, so
768 bytes is the whole game state; and **`set-ui-io-ports` sets the keyboard matrix**, which is
exactly what `teclado` polls.

`tests/README.md` documents the harness gotchas. The two that cost the most time:

- **ZRCP stops the emulated CPU whenever it receives a command** (`run`'s help lists "data sent" as a
  stopping event), so you cannot free-run and poll for a result — the polling starves the machine.
  Drive the CPU with `run N` from inside cpu-step mode.
- **`run N` runs N opcodes at emulated speed and knows nothing about where you wanted to stop**, so a
  large limit costs real wall-clock time. And **`run 1` advances nothing**; `cpu-step` is the exact
  single-step.

## 6. The manual verification protocol

`checklist.py` automates this list. Run it. The list is kept here because it is also what you check by
eye when something looks wrong.

### Every change, without exception

- [ ] `./build.sh` is **0 errors, 0 warnings**.
- [ ] `compiled: N lines` moved by roughly what you added (baseline **1538**).
- [ ] `python3 tests/run_all.py` says **EVERY SUITE PASSED**.
- [ ] The game still boots to the title screen, prompt, and a playable board.

### Behaviour that should hold

| Behaviour | Why |
|---|---|
| The ball leaves **no trail** through bricks or border | Erase-restore. The clearest single signal that the ball code is sound |
| Destroyed bricks clear **both** cells | A brick is 2 cells wide; an odd count of lit brick cells means a half-destroyed brick |
| `bricks_left × 2` equals the lit brick cells | The counter and the display cannot drift apart |
| The ball never occupies row 0, row 23, column 0 or column 31 | It bounces one cell early, which is what stops the border eroding |
| The rebound direction varies with **where** on the paddle it hit | Without this, levels are completable or not before the player touches a key |
| Losing all lives reaches **GAME OVER**, not the completion screen | They are different events |
| SP is identical after every restart and after every completed run | Nothing may `CALL` a routine that does not return. Sample at a fixed call depth (the GAME OVER key-wait) — mid-frame readings are noise |

### Known remaining quirks — do NOT report these as regressions

| Behaviour | Why |
|---|---|
| `map2`'s indestructible bricks are **invisible** | Colour 8 → `$40`, bright black on black. Pre-existing rendering bug → **map-data-format** §3 |
| Ball flickers (~27% off-duty) and the display tears | Structural to the busy-wait model → **timing-and-frame-loop** §7 |
| The top border writes one cell too many, into row 1 column 0 | `tablero.asm`; harmless, the cell is already border colour |
| `call Pala_Juego` in `PintarMapa.asm` is unreachable | Dead code sitting after an unconditional `jr` |
| Paddle movement speed varies slightly frame to frame | `teclado`'s delay counter depends on how fast the key was detected → **timing-and-frame-loop** §4 |

### Collision or physics change

- [ ] Empty-field erase-restore still byte-identical over 200 frames.
- [ ] Both cells of each brick still clear together; counter decrements exactly once per brick.
- [ ] Colour-8 bricks still bounce without being destroyed (test on `map2` — they are invisible, so
      watch for the bounce, not the brick).
- [ ] Rebound still varies across the paddle; row velocity never zero; no component over `$0100`.
- [ ] Counter reaches exactly zero — not negative, not stuck at 1.

### Map change

- [ ] All levels render; step through every one.
- [ ] Bricks start at column **1** and no row overruns column **30** (max 15 entries/row).
- [ ] Byte 0 matches the destructible-brick count exactly, or the level never completes.
- [ ] Rows land where you specified; nothing overlaps the paddle row 23 or the top border row 0.
- [ ] After the last level, the "La partida ha finalizado" screen appears rather than garbage.

## 7. When ZEsarUX wedges

Worth its own section, because the symptoms look like a bug in the game and are not.

If ZEsarUX gets into a state with a menu open, then: `close-all-menus` answers
`ERROR. Can not close all menus`, `enter-cpu-step` answers `Can not enter cpu step mode. You can try
closing the menu`, **`set-ui-io-ports` stores values that never reach the emulated ULA** (so the game
appears to ignore every key), and the CPU stops advancing — `get-registers` returns the same PC every
time.

There is no way to recover over ZRCP. Kill it and start again:

```
pkill -f 'zesarux --enable-remoteprotocol'
```

`tests/unit.py` detects this at construction and raises `NotHealthy` with that command, rather than
letting a suite fail in a confusing way.

**A healthy instance reads the keyboard correctly**, and it is worth knowing what correct looks like,
because the values are not what the code originally assumed. An idle half-row on `$FDFE` reads
**`$1F`**, not `$FF` — bits 5-7 are not keyboard bits and do not read as 1. Pressed keys clear their
bit: S → `$1D`, A → `$1E`, D → `$1B`, F → `$17`, G → `$0F`. Any code that compares the **whole port
byte** against `$FF` will therefore never match. That was a real defect in `SoltarTecla` and it hung
the menu so the game could not be started at all. → **failure-patterns** §13

## 8. DeZog comment directives

`main.asm:2` reads `SLDOPT COMMENT WPMEM, LOGPOINT, ASSERTION`. **It said `ASSETION` for twenty
months**, and sjasmplus strips those comments out of the SLD file entirely when the `SLDOPT` info is
missing — so the directives were silently disabled the whole time. Nobody noticed, because there are
still no `WPMEM`/`LOGPOINT`/`ASSERTION` comments anywhere in the sources, so nothing ever exercised
it. A misspelled directive fails by doing nothing, which is the worst way to fail.

The spelling is now correct, so adding such a comment will actually take effect. Nothing depends on
it — `tests/` is the regression suite and runs outside a debug session — but it is available:

| Directive | zsim | **ZEsarUX** |
|---|---|---|
| `WPMEM` (watchpoints) | yes | **yes** — 16-bit addresses only |
| `ASSERTION` | yes | **documentation contradicts itself** — the capability table says yes, a note in `Usage.md` says no. Confirm empirically |
| `LOGPOINT` | yes | **no** |

`${Remote.tStates}` and `${Remote.cpuFrequency}` are **zsim-only**, which is a real limitation given
how much of this project is T-state arithmetic.

An ASSERTION becomes a breakpoint evaluated **before** the instruction on its line, so to check the
*result* of an instruction you attach it to the **next** one. And these are debugger-side breakpoints
read from the SLD at debug start: change one and you must rebuild and restart the debugger. **They are
not a regression suite.** `tests/` is.
