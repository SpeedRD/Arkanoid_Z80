#!/usr/bin/env python3
"""The ball: cell classification, wall geometry, and erase-restore.

The headline test is `no trail`: because `ball` restores the cell it borrowed
before it returns, the attribute file must be BYTE-IDENTICAL after any number
of complete frames. That single assertion is what proves the erase-restore fix
landed -- it is the difference between the ball painting holes through the
bricks and the border, and the ball leaving the playfield alone.
"""
from unit import Unit

u = Unit()
L = u.L
fails = []

CELL_EMPTY, CELL_BORDER, CELL_BRICK, CELL_HARD, CELL_PADDLEROW = range(5)
NAMES = {CELL_EMPTY: "EMPTY", CELL_BORDER: "BORDER", CELL_BRICK: "BRICK",
         CELL_HARD: "HARD", CELL_PADDLEROW: "PADDLEROW"}

ONE = 256           # 1.00 cell/frame in 8.8 fixed point


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


def draw_level():
    """Border + map0, exactly as entering a level does."""
    u.call("dibujar_tablero")
    map0 = u.peek(L["maplist"], 2)
    u.call("Mostrar_Mapa", regs={"IX": map0[0] | map0[1] << 8})


def neuter_delay():
    """Shorten Esperar_pelota so a frame costs microseconds, not 32 ms.

    The operand of `ld hl,$1100` sits at Esperar_pelota+3, after `push hl` and
    `push af`. Assert the opcode first so this fails loudly rather than
    silently poking the wrong byte if the routine is ever reshaped.
    """
    addr = L["Esperar_pelota"]
    opcode = u.peek(addr + 2, 1)[0]
    assert opcode == 0x21, (
        f"expected `ld hl,nn` ($21) at Esperar_pelota+2, found ${opcode:02X} "
        "-- the delay loop changed shape, fix neuter_delay()")
    u.poke(addr + 3, [0x01, 0x00])


def classify(row, col):
    return u.call("classify_cell", regs={"HL": (row << 8) | col})["AF"] >> 8


print("classify_cell -- position first, attribute second")
draw_level()
check("row 0 is border", NAMES[classify(0, 10)], "BORDER")
check("column 0 is border", NAMES[classify(10, 0)], "BORDER")
check("column 31 is border", NAMES[classify(10, 31)], "BORDER")
check("row 23 is the paddle row", NAMES[classify(23, 10)], "PADDLEROW")
check("row 23 col 0 is the paddle row (row wins)",
      NAMES[classify(23, 0)], "PADDLEROW")

u.set_cell(10, 10, 0x00)
check("empty interior cell", NAMES[classify(10, 10)], "EMPTY")
u.set_cell(10, 10, 0x38)                    # colour 7 brick -- same byte as the ball
check("colour-7 brick ($38)", NAMES[classify(10, 10)], "BRICK")
u.set_cell(10, 10, 0x10)                    # colour 2 brick -- same byte as the paddle
check("colour-2 brick ($10) off row 23", NAMES[classify(10, 10)], "BRICK")
u.set_cell(10, 10, 0x40)
check("colour-8 brick ($40) is indestructible", NAMES[classify(10, 10)], "HARD")
u.set_cell(10, 10, 0x00)

print("\nclassify_cell returns the attribute address in HL")
r = u.call("classify_cell", regs={"HL": (10 << 8) | 5})
check("HL for (10,5)", f"{r['HL']:04X}", f"{0x5800 + 10 * 32 + 5:04X}")
r = u.call("classify_cell", regs={"HL": (0 << 8) | 7})
check("HL for border cell (0,7)", f"{r['HL']:04X}", f"{0x5800 + 7:04X}")

print("\nclassify_cell preserves IX (it is the global map pointer)")
r = u.call("classify_cell", regs={"HL": (10 << 8) | 10, "IX": 0x1234})
check("preserves IX", f"{r['IX']:04X}", "1234")

print("\nwall geometry -- the ball is confined to rows 1-22, columns 1-30")
neuter_delay()


def one_frame(row, col, vrow, vcol):
    """Place the ball, run exactly one frame, report where it ended up."""
    draw_level()
    u.set_ball(row, col)
    u.set_velocity(vrow, vcol)
    u.call("ball")
    return u.ball(), u.velocity()


cell, vel = one_frame(1, 15, -ONE, 0)
check("top: row 1 going up -> row 2", cell, (2, 15))
check("top: row velocity flipped", vel[0], ONE)

cell, vel = one_frame(10, 1, -ONE, -ONE)
check("left: col 1 going left -> col 2", cell[1], 2)
check("left: column velocity flipped", vel[1], ONE)

cell, vel = one_frame(10, 30, -ONE, ONE)
check("right: col 30 going right -> col 29", cell[1], 29)
check("right: column velocity flipped", vel[1], -ONE)

# Row 23 is the paddle's row, so a ball arriving there is a paddle question, not a
# wall one. Park the paddle out of the way to get the plain floor bounce; the
# rebound angle when it IS there belongs to test_colisiones.
u.poke(L["POSICION"], [2, 0])
cell, vel = one_frame(22, 15, ONE, 0)
check("bottom: row 22 going down -> row 21", cell, (21, 15))
check("bottom: row velocity flipped", vel[0], -ONE)
check("...and the miss was flagged as a lost ball", u.var("ball_lost")[0], 1)
u.poke(L["ball_lost"], [0])
u.poke(L["POSICION"], [14, 0])

print("\nfractional velocity advances at most one cell per axis per frame")
draw_level()
u.set_ball(10, 15)
u.set_velocity(-64, 64)                     # 0.25 cell/frame on each axis
seen = []
for _ in range(9):
    u.call("ball")
    seen.append(u.ball())
# The cell index is floor(position), so the two axes look asymmetric and both
# are right: going DOWN from row 10.0 the first -0.25 lands on 9.75, already
# cell 9; going UP from column 15.0 it takes four steps to reach 16.0. What
# matters is that neither axis ever moves by more than one cell in a frame --
# that is what stops the ball passing through a brick without touching it.
check("cell sequence follows floor(position)",
      seen, [(9, 15), (9, 15), (9, 15), (9, 16),
             (8, 16), (8, 16), (8, 16), (8, 17), (7, 17)])
steps = [(abs(b[0] - a[0]), abs(b[1] - a[1]))
         for a, b in zip([(10, 15)] + seen, seen)]
check("no axis ever moves more than one cell in a frame",
      max(max(s) for s in steps), 1)

print("\nthe ball never occupies a border or paddle cell")
draw_level()
u.set_ball(20, 16)
u.set_velocity(-ONE, ONE)
visited = set()
for _ in range(300):
    u.call("ball")
    visited.add(u.ball())
bad = sorted(c for c in visited
             if c[0] in (0, 23) or c[1] in (0, 31))
check("no visit to row 0/23 or column 0/31 in 300 frames", bad, [])
check("stayed inside rows 1-22", (min(r for r, _ in visited),
                                  max(r for r, _ in visited)), (1, 22))

print("\nERASE-RESTORE: a completed frame leaves the playfield exactly as it was")
# On an empty field there is nothing for the ball to legitimately change, so the
# attribute file must come back byte-identical. This is the single clearest
# pass/fail signal that the erase writes back what it borrowed instead of 0 --
# the ball used to paint a trail of holes through everything it flew over.
u.call("dibujar_tablero")               # border only, no map
u.set_ball(20, 16)
u.set_velocity(-ONE, ONE)
before = u.attrs()
for _ in range(200):
    u.call("ball")
after = u.attrs()
diff = [(i // 32, i % 32, before[i], after[i])
        for i in range(768) if before[i] != after[i]]
check("no cell changed across 200 frames on an empty field", diff, [])

print("\n...and over a brick field it changes ONLY what it destroyed")
draw_level()
u.poke(L["bricks_left"], [82])
u.set_ball(20, 16)
u.set_velocity(-ONE, ONE)
before = u.attrs()
for _ in range(400):
    u.call("ball")
after = u.attrs()
changed = [i for i in range(768) if before[i] != after[i]]
check("every changed cell went to 0 (destroyed, never overwritten)",
      all(after[i] == 0 for i in changed), True)
check("every changed cell was a brick, never border or paddle row",
      all(before[i] not in (0x00, 0x0F) and 1 <= i // 32 <= 22 for i in changed),
      True)
check("cells cleared in pairs (both halves of each brick)", len(changed) % 2, 0)
destroyed = 82 - u.var("bricks_left")[0]
check("counter agrees with the cells cleared", destroyed * 2, len(changed))
border_ok = all(after[c] == 0x0F for c in range(32)) and \
            all(after[r * 32] == 0x0F and after[r * 32 + 31] == 0x0F
                for r in range(24))
check("border is intact (no holes chewed in it)", border_ok, True)

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
