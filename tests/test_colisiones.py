#!/usr/bin/env python3
"""Ball/brick destruction, the brick counter, and the paddle rebound angle."""
import math

from unit import Unit

u = Unit()
L = u.L
fails = []

ONE = 256           # 1.00 cell/frame in 8.8 fixed point
BRICK = 0x38        # colour 7 << 3
HARD = 0x40         # colour 8 << 3 -- indestructible, and invisible
BORDERC = 0x0F


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


def neuter_delay():
    addr = L["Esperar_pelota"]
    assert u.peek(addr + 2, 1)[0] == 0x21, "Esperar_pelota changed shape"
    u.poke(addr + 3, [0x01, 0x00])


def bricks_left():
    return u.var("bricks_left")[0]


def blank_playfield():
    """Border only -- no map. Gives a clean field to place test bricks on."""
    u.call("dibujar_tablero")


print("Mostrar_Mapa captures byte 0 as the brick count")
for name, want in (("map0", 82), ("map1", 71), ("map2", 78), ("map3", 153)):
    u.poke(L["bricks_left"], [0])
    u.call("Mostrar_Mapa", regs={"IX": L[name]})
    check(f"{name} byte 0", bricks_left(), want)

print("\ndestroy_brick clears BOTH cells and counts the brick once")
neuter_delay()
blank_playfield()

# entry i of a row occupies columns 1+2i and 2+2i, so an odd column is a brick's
# left cell and an even column is its right cell.
for col, partner in ((5, 6), (6, 5), (1, 2), (2, 1)):
    blank_playfield()
    u.set_cell(10, col, BRICK)
    u.set_cell(10, partner, BRICK)
    u.poke(L["bricks_left"], [10])
    u.poke(L["cand_cell"], [col, 10])
    u.call("destroy_brick")
    check(f"col {col}: both cells cleared",
          (u.cell(10, col), u.cell(10, partner)), (0, 0))
    check(f"col {col}: counter decremented once", bricks_left(), 9)

u.poke(L["bricks_left"], [0])
u.poke(L["cand_cell"], [5, 10])
u.call("destroy_brick")
check("counter never wraps below zero", bricks_left(), 0)

print("\ncolour-8 bricks bounce but are never destroyed or counted")
blank_playfield()
u.set_cell(9, 15, HARD)
u.set_cell(9, 16, HARD)
u.poke(L["bricks_left"], [7])
u.set_ball(10, 15)
u.set_velocity(-ONE, 0)
u.call("ball")
check("hard brick still there", (u.cell(9, 15), u.cell(9, 16)), (HARD, HARD))
check("hard brick does not decrement the counter", bricks_left(), 7)
check("hard brick still bounces the ball", u.velocity()[0], ONE)

print("\nbounce direction: vertical hit flips the row, horizontal flips the column")
blank_playfield()
u.set_cell(9, 10, BRICK)
u.set_cell(9, 9, BRICK)
u.poke(L["bricks_left"], [50])
u.set_ball(10, 10)
u.set_velocity(-ONE, ONE)
u.call("ball")
check("vertical brick flipped the row velocity", u.velocity()[0], ONE)
check("vertical brick left the column velocity alone", u.velocity()[1], ONE)
check("vertical brick destroyed", (u.cell(9, 10), u.cell(9, 9)), (0, 0))

blank_playfield()
u.set_cell(10, 11, BRICK)
u.set_cell(10, 12, BRICK)
u.poke(L["bricks_left"], [50])
u.set_ball(10, 10)
u.set_velocity(-ONE, ONE)
u.call("ball")
check("horizontal brick flipped the column velocity", u.velocity()[1], -ONE)
check("horizontal brick left the row velocity alone", u.velocity()[0], -ONE)

print("\ntwo bricks in one frame is legal and counts twice")
blank_playfield()
for r, c in ((9, 10), (9, 9), (10, 11), (10, 12)):
    u.set_cell(r, c, BRICK)
u.poke(L["bricks_left"], [50])
u.set_ball(10, 10)
u.set_velocity(-ONE, ONE)
u.call("ball")
check("both bricks destroyed (4 cells)",
      [u.cell(9, 10), u.cell(9, 9), u.cell(10, 11), u.cell(10, 12)],
      [0, 0, 0, 0])
check("counter dropped by exactly 2", bricks_left(), 48)
check("both velocities flipped", u.velocity(), (ONE, -ONE))

print("\ndiagonal-only contact flips both and destroys the corner brick")
blank_playfield()
u.set_cell(9, 11, BRICK)
u.set_cell(9, 12, BRICK)
u.poke(L["bricks_left"], [50])
u.set_ball(10, 10)
u.set_velocity(-ONE, ONE)
u.call("ball")
check("corner brick destroyed", (u.cell(9, 11), u.cell(9, 12)), (0, 0))
check("counter dropped by 1", bricks_left(), 49)
check("both velocities flipped", u.velocity(), (ONE, -ONE))

print("\nthe border bounces the ball and is never destroyed or counted")
blank_playfield()
u.poke(L["bricks_left"], [50])
u.set_ball(1, 15)
u.set_velocity(-ONE, 0)
u.call("ball")
check("border intact", u.cell(0, 15), BORDERC)
check("border does not decrement the counter", bricks_left(), 50)

print("\npaddle rebound angle -- where it hits decides where it goes")
TABLE = {0: (-128, -222), 1: (-181, -181), 2: (-222, -128), 3: (-248, 64),
         4: (-222, 128), 5: (-181, 181), 6: (-128, 222)}
for idx, want in TABLE.items():
    blank_playfield()
    u.poke(L["POSICION"], [10, 0])
    u.set_ball(22, 10 + idx)
    u.set_velocity(ONE, 0)              # straight down onto the paddle
    u.call("ball")
    check(f"hit index {idx}", u.velocity(), want)

check("every rebound has a non-zero row velocity",
      all(v[0] != 0 for v in TABLE.values()), True)
# A bound, not an exact value: what matters is that no component can push the ball
# more than one cell per axis per frame, not what the largest one happens to be.
check("no rebound component exceeds one cell per frame",
      max(max(abs(v[0]), abs(v[1])) for v in TABLE.values()) <= ONE, True)
check("rebound is steepest at the centre, shallowest at the edges",
      [abs(TABLE[i][0]) for i in range(7)],
      [128, 181, 222, 248, 222, 181, 128])

print("\nSPEED IS CONSTANT -- every velocity source has the same magnitude")
# This is the check that was missing, and its absence is why the ball felt erratic.
# The old suite asserted each COMPONENT was <= 256 and that the table matched a
# hardcoded copy of itself -- both of which a wrong table passes happily. Nothing
# compared magnitudes, so a serve of |v|=362 against rebounds of 250-286 went
# unnoticed: the ball launched 41% too fast and slowed for good on first contact.
#
# Every magnitude below is read back from the RUNNING CODE, never from a table
# literal in this file.
speeds = {}

u.call("reset_ball")
speeds["serve"] = math.hypot(*u.velocity())

for idx in range(7):
    blank_playfield()
    u.poke(L["POSICION"], [10, 0])
    u.poke(L["ball_lost"], [0])
    u.set_ball(22, 10 + idx)
    u.set_velocity(ONE, 0)
    u.call("ball")
    speeds[f"rebound {idx}"] = math.hypot(*u.velocity())

blank_playfield()                       # wall bounce: negation must preserve magnitude
u.set_ball(10, 30)
u.set_velocity(-181, 181)
u.call("ball")
speeds["wall bounce"] = math.hypot(*u.velocity())

blank_playfield()                       # brick bounce: likewise
u.set_cell(9, 15, BRICK)
u.set_cell(9, 16, BRICK)
u.poke(L["bricks_left"], [9])
u.set_ball(10, 15)
u.set_velocity(-181, 181)
u.call("ball")
speeds["brick bounce"] = math.hypot(*u.velocity())

for name, s in speeds.items():
    print(f"       {name:14} |v| = {s:6.1f}")
lo, hi = min(speeds.values()), max(speeds.values())
check("every velocity source is within 2% of the same speed",
      round((hi - lo) / lo, 3) <= 0.02, True)
check("...and that speed is one cell per frame of travel", round(lo), 256)

print("\nthe dead-centre cell keeps the ball's existing horizontal direction")
blank_playfield()
u.poke(L["POSICION"], [10, 0])
# The hit index comes from the column the ball is HEADING FOR, not the one it is
# leaving. Moving left at 0.25/frame from a bare column 13 targets 12.75 -> cell 12,
# which is index 2. Start half a cell in so the target still floors to 13.
u.set_ball(22, 13, frac_col=0x80)
u.set_velocity(ONE, -64)                # arriving while moving LEFT
u.call("ball")
check("centre hit moving left stays left", u.velocity(), (-248, -64))

blank_playfield()
u.poke(L["POSICION"], [10, 0])
u.set_ball(22, 13)
u.set_velocity(ONE, 64)                 # arriving while moving RIGHT
u.call("ball")
check("centre hit moving right stays right", u.velocity(), (-248, 64))

print("\nmissing the paddle -- floor still bounces at this stage")
blank_playfield()
u.poke(L["POSICION"], [2, 0])            # paddle far away, columns 2-8
u.set_ball(22, 25)
u.set_velocity(ONE, 0)
u.call("ball")
check("missed paddle bounces off the floor", u.velocity()[0], -ONE)

print("\nthe ball never lands on the paddle row itself")
blank_playfield()
u.poke(L["POSICION"], [12, 0])
u.set_ball(20, 15)
u.set_velocity(ONE, ONE)
rows = set()
for _ in range(200):
    u.call("ball")
    rows.add(u.ball()[0])
check("row 23 never occupied", 23 in rows, False)
check("row 22 is reached (the ball does get to the paddle)", 22 in rows, True)

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
