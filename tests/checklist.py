#!/usr/bin/env python3
"""build-and-verify section 6, end to end, on the real running game.

Unlike the other suites this one does not call routines: it boots the image and
plays it in real time, driving the keyboard matrix and reading the attribute
file, which IS the playfield. A frame is ~44 ms (~23 fps), so a couple of
seconds is a few dozen frames.

Two habits this file has to keep, both learned by getting them wrong:

  * The game can now be LOST. Any test that just wants to watch the ball run
    for a few seconds must top up `lives` first, or the run ends on the
    GAME OVER screen and every later assertion reads a cleared playfield.
  * Never assert on a value the polling loop itself pokes. Drive the state,
    stop driving, then read.

Exact post-reset positions are asserted in test_juego.py, which can freeze the
machine between calls. Here the ball has moved on by the time a poll notices
anything, so this file checks the things that hold still.
"""
import time

from ark import Z, labels

z = Z()
L = labels()
fails = []

BORDER = 0x0F
PADDLE = 0x10


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


def var(name, n=1):
    return z.read_mem(L[name], n)


def poke(name, data):
    z.write_mem(L[name], data)


def wait_for(pred, timeout=15.0, poll=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if pred():
            return True
        time.sleep(poll)
    return False


def snapshot():
    """Freeze the machine, read the playfield and the ball cell, thaw.

    Reading 768 bytes takes a few milliseconds, during which a running game can
    move the ball, redraw the paddle and destroy another brick, so the attribute
    file, Coord and bricks_left would not agree. Stopping the CPU makes them one
    consistent picture -- which is why the counter is read in HERE and not by the
    caller a moment earlier.
    """
    z.cmd("enter-cpu-step")
    at = z.attrs()
    col, row = z.read_mem(L["Coord"], 2)
    left = z.read_mem(L["bricks_left"], 1)[0]
    z.cmd("exit-cpu-step")
    return at, (row, col), left


def brick_cells(at, ball):
    """Lit playfield cells, excluding the border and the ball.

    The ball must be excluded by POSITION: it is drawn as $38, which is exactly
    what a colour-7 brick looks like, and colour 7 is the commonest brick colour
    in these maps. Excluding its cell is always safe -- the ball never enters a
    brick cell, it bounces off, so what sits under it is always empty.
    """
    return sum(1 for i, v in enumerate(at)
               if v not in (0x00, BORDER)
               and 1 <= i // 32 <= 22
               and (i // 32, i % 32) != ball)


def restart_from_menu():
    """Answer a menu prompt with S and wait for the next level to be loaded.

    `bricks_left` is zeroed FIRST, and that is the whole point: after a game
    over it still holds the interrupted level's count, so simply waiting for it
    to be non-zero returns instantly and the caller carries on believing a
    restart happened when it has not. Zeroing it first means the return to
    non-zero can only have come from Mostrar_Mapa running again.
    """
    poke("bricks_left", [0])
    z.press("S")
    time.sleep(0.25)
    z.release()
    return wait_for(lambda: var("bricks_left")[0] != 0, timeout=6, poll=0.02)


def clear_one_level():
    """Clear the current level, syncing on the next one being loaded.

    Between Fin_Juego bumping levelCounter and Mostrar_Mapa reloading the count,
    bricks_left is still the 0 we poked -- poke again in that window and the run
    advances an extra level.
    """
    if not wait_for(lambda: var("bricks_left")[0] != 0, timeout=6, poll=0.02):
        return False
    poke("bricks_left", [0])
    return True


def drop_ball_away_from_paddle():
    """Park the paddle far left and drop the ball on the right."""
    poke("POSICION", [1, 1])
    poke("Coord", [28, 22])                     # column 28, row 22
    poke("CoordFrac", [0, 0])
    poke("Vector", [0x00, 0x01, 0x00, 0x01])    # heading down and right


def force_game_over():
    poke("lives", [1])
    for _ in range(80):
        drop_ball_away_from_paddle()
        time.sleep(0.12)
        if z.cell(8, 11) == 2:
            return True
    return False


def start_game(lives=99):
    """Boot, answer the prompt, and return as soon as the map is loaded.

    `lives` defaults to a stack the ball cannot exhaust, so observation tests
    are not cut short by the game legitimately ending.
    """
    z.boot()
    time.sleep(1.2)
    z.press("S")
    time.sleep(0.25)
    z.release()
    # bricks_left is set at the top of Mostrar_Mapa, before a single brick is
    # painted, so a fine-grained poll catches the pristine value.
    wait_for(lambda: var("bricks_left")[0] != 0, timeout=5, poll=0.02)
    fresh = var("bricks_left")[0]
    poke("lives", [lives])
    return fresh


print("boot -> title screen")
z.boot()
time.sleep(1.5)
check("title bitmap decoded into pixel memory", any(z.read_mem(0x4000, 256)), True)
check("start prompt has its flashing cell", z.cell(23, 21), 0x86)

print("\npress S -> a playable board")
z.press("S")
time.sleep(0.25)
z.release()
wait_for(lambda: var("bricks_left")[0] != 0, timeout=5, poll=0.02)
check("brick counter loaded from the map", var("bricks_left")[0], 82)
check("three lives at the start of a game", var("lives")[0], 3)
# That poll fires at the top of Mostrar_Mapa, before a brick is painted and
# before the first dibujarpala, so give the opening frames time to draw.
time.sleep(0.5)
at, _, _ = snapshot()
check("top border drawn", all(at[c] == BORDER for c in range(1, 31)), True)
check("side borders drawn",
      all(at[r * 32] == BORDER and at[r * 32 + 31] == BORDER for r in range(24)),
      True)
check("paddle on row 23", sorted(c for c in range(32)
                                 if at[23 * 32 + c] == PADDLE), list(range(14, 21)))
check("bricks painted", sum(1 for v in at if v not in (0x00, BORDER)) > 100, True)

print("\nthe ball moves")
first = tuple(var("Coord", 2))
check("Coord advances",
      wait_for(lambda: tuple(var("Coord", 2)) != first, timeout=3), True)

print("\nA and D move the paddle")
start_game()
z.press("A")
time.sleep(1.5)
left = var("POSICION")[0]
z.release()
z.press("D")
time.sleep(2.5)
right = var("POSICION")[0]
z.release()
check("A moves left", left < 14, True)
check("D moves right", right > left, True)
check("paddle never leaves columns 1-24", 1 <= left <= 24 and 1 <= right <= 24, True)

print("\nthe ball destroys bricks -- and leaves nothing else damaged")
before = start_game()
time.sleep(6.0)
at, ball, after = snapshot()
check("brick counter goes down", after < before, True)
check("border still intact after play",
      all(at[c] == BORDER for c in range(1, 31)) and
      all(at[r * 32] == BORDER and at[r * 32 + 31] == BORDER for r in range(24)),
      True)
# Every destroyed brick clears BOTH of its cells, so the brick cells still lit
# must stay even. An odd count means a half-destroyed brick.
lit = brick_cells(at, ball)
check("brick cells still come in pairs", lit % 2, 0)
check("counter matches the bricks actually left", after * 2, lit)

print("\nlosing a ball costs a life and re-serves")
start_game(lives=3)
lives_before = var("lives")[0]


lost = False
for _ in range(80):
    drop_ball_away_from_paddle()
    time.sleep(0.12)
    if var("lives")[0] < lives_before:
        lost = True
        break
check("a missed ball costs a life", lost, True)
# Stop driving before reading. reset_round re-centres the paddle, and POSICION
# holds still afterwards because no key is pressed.
time.sleep(0.3)
check("the paddle is re-centred", var("POSICION")[0], 14)
check("the ball is back in play, not stuck on the paddle row",
      var("Coord", 2)[1] < 23, True)

print("\nzero lives -> GAME OVER, a different screen from level completion")
poke("lives", [1])
over = False
for _ in range(80):
    drop_ball_away_from_paddle()
    time.sleep(0.12)
    if z.cell(8, 11) == 2:
        over = True
        break
check("GAME OVER message printed", over, True)
check("all nine characters of it", [z.cell(8, c) for c in range(11, 20)], [2] * 9)
check("lives restored for the next game", var("lives")[0], 3)
check("level counter cleared", var("levelCounter")[0], 0)
check("this is NOT the completion screen", z.cell(4, 4), 0)

print("\nclearing the last brick advances the level, with no F key involved")
start_game()
check("starts on level 0", var("levelCounter")[0], 0)
poke("bricks_left", [0])
check("level counter incremented",
      wait_for(lambda: var("levelCounter")[0] == 1, timeout=5), True)
check("next map's brick count loaded", var("bricks_left")[0], 71)
time.sleep(0.3)
check("paddle reset for the new level", var("POSICION")[0], 14)

print("\nfour levels -> the completion screen (not game over)")
for want in (2, 3):
    poke("bricks_left", [0])
    wait_for(lambda w=want: var("levelCounter")[0] == w, timeout=5)
poke("bricks_left", [0])
check("completion screen reached",
      wait_for(lambda: z.cell(4, 4) == 3, timeout=5), True)
check("its message is at row 4, not row 8", z.cell(8, 11), 0)
check("level counter reset", var("levelCounter")[0], 0)

# ---------------------------------------------------------------------------
# Stack stability. Both routes out of the game reach a screen that never comes
# back, so both must be entered with JP and neither may leave a return address
# behind. Each was measured leaking exactly 2 bytes per cycle before its fix,
# and 0 after.
#
# SP is sampled in the GAME OVER key-wait for both. That is a fixed call depth;
# a running frame sits at whatever depth its current nested call has reached,
# which makes a mid-frame reading meaningless.
#
# Every restart is verified to have ACTUALLY happened, by asserting the menu
# text is gone afterwards. Without that check these tests pass vacuously: if the
# game never restarts, the GAME OVER screen is still up, the next iteration
# "detects" it immediately, and SP is trivially identical every time.
# ---------------------------------------------------------------------------

print("\nthe stack does not grow across games (flujo_juego -> Juego)")
start_game(lives=1)
sps, restarts_real = [], []
for _ in range(4):
    if not force_game_over():
        break
    time.sleep(0.3)
    sps.append(z.regs()["SP"])
    if not restart_from_menu():
        break
    restarts_real.append(z.cell(8, 11) == 0)
check("reached game over on every cycle", len(sps), 4)
check("every restart really happened", restarts_real, [True] * 4)
check("SP identical at every restart", len(set(sps)), 1)

print("\n...nor across completed runs (ReinicioJuego -> Pantalla_Reinicio)")
start_game()
sps, restarts_real = [], []
for _ in range(3):
    cleared = True
    for lvl in range(4):
        if not clear_one_level():
            cleared = False
            break
        if lvl < 3:
            wait_for(lambda w=lvl + 1: var("levelCounter")[0] == w,
                     timeout=5, poll=0.02)
    if not cleared:
        break
    if not wait_for(lambda: z.cell(4, 4) == 3, timeout=6):
        break
    if not restart_from_menu():
        break
    restarts_real.append(z.cell(4, 4) == 0)
    if not force_game_over():
        break
    time.sleep(0.3)
    sps.append(z.regs()["SP"])
    if not restart_from_menu():
        break
check("completed four levels on every cycle", len(sps), 3)
check("every completion restart really happened", restarts_real, [True] * 3)
check("SP identical after every completed run", len(set(sps)), 1)

print("\nholding S or G during play does not freeze the game")
start_game()
for key in ("S", "G"):
    z.press(key)
    before = tuple(var("Coord", 2))
    time.sleep(1.5)
    check(f"ball still moving while {key} is held",
          tuple(var("Coord", 2)) != before, True)
    z.release()

z.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
