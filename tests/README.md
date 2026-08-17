# tests

Automated verification for Arkanoid_Z80, driving **ZEsarUX over ZRCP** — its
remote debug protocol on `localhost:10000`. No VS Code, no DeZog, no human at
the keyboard.

Two properties of this project make it testable at all:

- **The attribute file at `$5800` *is* the playfield.** Border, bricks, paddle
  and ball are all just coloured 8×8 cells, so reading 768 bytes gives the
  entire game state. `ark.Z.board()` renders it as ASCII.
- **`set-ui-io-ports` sets the keyboard matrix**, which is exactly what
  `teclado` polls with `IN A,(C)` on `$FDFE`.

## Running

Start ZEsarUX with ZRCP enabled (it is not on `PATH` — it was installed as a
Homebrew cask, so there is only an `.app` bundle):

```bash
/opt/homebrew/Caskroom/zesarux/13.0/ZEsarUX.app/Contents/MacOS/zesarux \
    --enable-remoteprotocol --remoteprotocol-port 10000 --machine 48k &
nc -z localhost 10000 && echo LISTENING
```

Then, from the repo root:

```bash
python3 tests/run_all.py              # build + every suite
python3 tests/run_all.py test_pelota  # just one
```

`run_all.py` builds via `./build.sh` first and refuses to run the suites if the
build is not `Errors: 0, warnings: 0` — sjasmplus exits 0 even with warnings, so
the summary line is read rather than the exit code.

## What each suite covers

| Suite | Covers |
|---|---|
| `test_pelota.py` | `classify_cell`'s position-first truth table and its `IX` preservation; the wall geometry that confines the ball to rows 1–22 and columns 1–30; fractional velocity never moving more than one cell per axis per frame; and the headline check — **the attribute file is byte-identical after 200 completed frames**, which is what proves erase-restore landed |
| `test_colisiones.py` | Byte 0 of all four maps reaching `bricks_left`; both cells of a brick clearing together for odd and even columns with exactly one decrement; colour-8 bricks bouncing without being destroyed or counted; vertical/horizontal/diagonal bounce resolution including two bricks in one frame; and every entry of the paddle rebound table, plus the two invariants it must satisfy (row velocity never zero, no component over one cell/frame) |
| `test_juego.py` | `teclado` dispatch, and specifically that S, G and F **return instead of freezing**; that no `call Fin_Juego` survives in `pala.asm`; `reset_round` / `reset_game` byte by byte; the ball-lost flag being set rather than jumped on; and that `FinDelJuego` now stops for good instead of falling through into `CalcularAtributo` |
| `checklist.py` | `build-and-verify` §6 end to end on a live game: title, prompt, board, paddle movement, bricks being destroyed with the border intact, losing a life, GAME OVER at zero lives, automatic level advance with no F press, the completion screen after four levels, and S/G not freezing play |

## Harness notes

`ark.py` is the ZRCP client, the board renderer and a small script interpreter.
`unit.py` calls a single Z80 routine with chosen registers.

Five details cost real time to rediscover:

1. **ZRCP stops the emulated CPU whenever it receives a command.** `run`'s own
   help lists "data sent" as a stopping event. So you cannot free-run and poll
   for a result — the polling starves the machine and PC never leaves the
   routine's first instruction. `unit.call` stays in cpu-step mode and drives
   the CPU with `run N` instead.
2. **`run N` executes N opcodes at emulated speed and knows nothing about the
   trap.** Once the routine returns, the trap's `JR $` burns whatever budget is
   left, so a large limit costs real wall-clock time even for a routine that
   finished instantly (80 000 opcodes ≈ 240 ms). Keep `limit` modest and loop.
   Also note **`run 1` advances nothing at all**; `cpu-step` is the exact
   single-step.
3. **No breakpoints.** A fired ZEsarUX breakpoint opens its debug menu, and an
   open menu makes `enter-cpu-step` fail, which makes everything else fail.
   Routines return onto a `DI : JR $` trap instead. If `Unit()` raises
   `NotHealthy`, the emulator is wedged — restart it.
4. **Mode switches are expensive**: `exit-cpu-step` ≈ 110 ms, `enter-cpu-step`
   ≈ 540 ms. Do not put them in a loop.
5. **The ball cannot be found by searching for its attribute.** It is drawn as
   `$38`, which is byte-identical to a colour-7 brick — and colour 7 is the
   commonest brick colour in these maps. Always locate it by `Coord`
   (byte 0 = column, byte 1 = row). `checklist.snapshot()` freezes the machine
   so the attribute file and `Coord` describe the same instant.

Addresses are always resolved from `main.lst` by label — never hardcoded. All
ten source files are concatenated into one `org $8000` image, so every symbol
moves whenever anything earlier in the include order changes size.

## Limits

These suites do not prove the game is fun, and they cannot see tearing or
flicker — the ball is deliberately erased for ~27% of every frame, and whether a
write lands mid-scan still needs a human watching. They also do not prove a
level is *completable*: that depends on the ball actually reaching every brick,
which the rebound angle makes player-dependent rather than fixed.
