#!/usr/bin/env python3
"""Keyboard dispatch, the state resets, and the lose/complete paths."""
from unit import Unit

u = Unit()
L = u.L
fails = []

ONE = 256


def check(name, got, want):
    ok = got == want
    print(f"  {'ok  ' if ok else 'FAIL'} {name}: got {got}, want {want}")
    if not ok:
        fails.append(name)


def direction(keys):
    """teclado returns the paddle direction in B: -1, 0 or +1."""
    b = u.call("teclado", keys=keys)["BC"] >> 8
    return b - 256 if b > 127 else b


print("teclado dispatch")
check("no key -> 0", direction([]), 0)
check("A -> -1", direction(["A"]), -1)
check("D -> +1", direction(["D"]), 1)

print("\nteclado no longer hangs on a key it does not handle")
# Holding S or G used to freeze the whole game -- ball and paddle both stopped --
# because teclado looped back to the poll without decrementing its counter. S sits
# right next to A and D, so this was easy to hit by accident. If the bug comes back
# these calls never return and u.call raises.
check("S returns instead of freezing", direction(["S"]), 0)
check("G returns instead of freezing", direction(["G"]), 0)
check("A and S together still moves left", direction(["A", "S"]), -1)
check("D and G together still moves right", direction(["D", "G"]), 1)

print("\nthe F debug hook is gone -- F is just an unhandled key now")
check("F does nothing", direction(["F"]), 0)
# Strip comments first: the explanation of why the hook was removed naturally
# mentions Fin_Juego by name, and that must not count as a call site.
code = "\n".join(line.split(";")[0] for line in open("../pala.asm"))
check("no call to Fin_Juego survives in teclado", "Fin_Juego" in code, False)

print("\nreset_round -- ball and paddle, not bricks or lives")
u.set_ball(3, 27, frac_col=0x77, frac_row=0x99)
u.set_velocity(123, -45)
u.poke(L["POSICION"], [24, 24])
u.poke(L["bricks_left"], [17])
u.poke(L["lives"], [2])
u.call("reset_round")
check("ball back to the serve cell", u.ball(), (20, 16))
check("fractions cleared", list(u.var("CoordFrac", 2)), [0, 0])
check("velocity back to up-and-right", u.velocity(), (-ONE, ONE))
check("paddle back to centre", u.var("POSICION", 1)[0], 14)
check("previous-column shadow points at the old column so it gets erased",
      u.var("POSICION", 2)[1], 24)
check("bricks untouched", u.var("bricks_left")[0], 17)
check("lives untouched", u.var("lives")[0], 2)

print("\nreset_game -- everything a new game needs")
u.poke(L["lives"], [0])
u.poke(L["levelCounter"], [3])
u.poke(L["ball_lost"], [1])
u.set_ball(5, 5)
u.call("reset_game")
check("lives restored", u.var("lives")[0], 3)
check("level counter cleared", u.var("levelCounter")[0], 0)
check("ball_lost cleared", u.var("ball_lost")[0], 0)
check("ball reset too", u.ball(), (20, 16))

print("\nlosing the ball sets the flag rather than jumping out of the collision code")
u.call("dibujar_tablero")
u.poke(L["ball_lost"], [0])
u.poke(L["POSICION"], [2, 0])            # paddle at columns 2-8
u.set_ball(22, 25)                       # ball coming down at column 25: a miss
u.set_velocity(ONE, 0)
u.call("ball")
check("ball_lost set on a miss", u.var("ball_lost")[0], 1)

u.poke(L["ball_lost"], [0])
u.poke(L["POSICION"], [22, 0])           # paddle at columns 22-28
u.set_ball(22, 25)                       # same ball, now caught
u.set_velocity(ONE, 0)
u.call("ball")
check("ball_lost clear on a catch", u.var("ball_lost")[0], 0)
check("catch sent the ball back up", u.velocity()[0] < 0, True)

print("\nthe brick counter is what ends the level")
u.call("Mostrar_Mapa", regs={"IX": L["map0"]})
check("map0 loads 82", u.var("bricks_left")[0], 82)
u.call("Mostrar_Mapa", regs={"IX": L["map3"]})
check("map3 loads 153", u.var("bricks_left")[0], 153)

print("\nFinDelJuego stops for good instead of falling into CalcularAtributo")
# It used to run straight on into CalcularAtributo, whose RET consumed the return
# address EsperarTecla had left, dropping control back into the key-wait loop -- so
# pressing N showed the goodbye screen and then silently carried on. A short budget
# is enough: if it ever returns to the trap again, the fall-through is back.
try:
    u.call("FinDelJuego", tries=3)
    check("FinDelJuego does not return", True, False)
except AssertionError:
    check("FinDelJuego does not return", True, True)

u.close()
print("\n" + ("ALL PASS" if not fails else f"FAILURES: {fails}"))
