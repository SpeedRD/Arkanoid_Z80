#!/usr/bin/env python3
"""Call one Z80 routine at a time under ZEsarUX, with controlled registers.

How a call works: put a return address on a stack we control, point PC at the
routine, and let it run. When the routine RETs it lands on a two-instruction
trap poked into free RAM -- DI then JR $ -- which parks the CPU deterministically
so "did it return?" is a single register read.

Things here that were learned the hard way and are load-bearing:

  * No breakpoints. A fired ZEsarUX breakpoint opens the debug menu, and an
    open menu makes enter-cpu-step fail, which makes everything else fail --
    the emulator then needs restarting. See Unit.healthy().

  * `run N` is not a reliable opcode count on this build. It stops on "a
    breakpoint, key press or data sent, menu opening, N opcodes run, or other
    event", and `run 1` in particular advances PC by nothing at all. So calls
    free-run and poll for the trap instead of counting opcodes. `cpu-step` IS
    exact, and is used for the two-opcode prologue.

  * main.asm's prologue (`di` / `ld sp,0`) is executed before every test. This
    game runs with interrupts disabled for its entire life -- there is no `ei`,
    no IM, no ISR and no halt anywhere in the sources. Skip the `di` and the
    ROM's 50 Hz handler fires in the middle of routines under test.
"""
import time

from ark import BIN, Z, labels, matrix

STACK = 0xFF00


class NotHealthy(RuntimeError):
    """ZEsarUX is wedged -- almost always a menu left open. Restart it."""


class Unit:
    def __init__(self):
        self.z = Z()
        self.L = labels()
        self.TRAP = 0xFE00      # DI : JR $   -- free RAM, well above the image
        self.PARKED = 0xFE01    # PC settles on the JR
        self.z.cmd("disable-breakpoints")
        self.z.cmd("close-all-menus")
        if "Error" in self.z.cmd("enter-cpu-step"):
            raise NotHealthy(
                "ZEsarUX will not enter cpu-step mode (a menu is probably "
                "open). Restart the emulator:\n"
                "  pkill -f 'zesarux --enable-remoteprotocol'")
        self.z.cmd("hard-reset-cpu")
        self.z.cmd(f'load-binary "{BIN}" 8000H 0')
        self.z.cmd("set-register PC=8000H")
        self.z.cmd("cpu-step")          # di
        self.z.cmd("cpu-step")          # ld sp,0
        self.z.cmd(f"write-memory-raw {self.TRAP:04X}H f318fe")
        self.z.release()

    def regs(self):
        return self.z.regs()

    def call(self, name, regs=None, keys=None, limit=3000, tries=200):
        """Run routine `name`; return its registers. Raises if it never RETs.

        Stays in cpu-step mode and drives the CPU with `run N`. Do NOT be
        tempted to exit cpu-step and poll instead: ZRCP stops the emulated CPU
        whenever it receives a command (`run`'s own help lists "data sent" as a
        stopping event), so a polling loop starves the machine -- PC never
        leaves the routine's first instruction, and each mode switch costs
        110 ms leaving plus 540 ms re-entering.

        `run N` executes N opcodes at EMULATED speed and has no idea about the
        trap -- once the routine returns, the trap's `JR $` just spins through
        whatever budget is left. So a big limit costs real wall-clock time even
        for a routine that finished immediately (80000 opcodes ~= 240 ms).
        Keep `limit` modest and loop: a real ball frame is ~17k opcodes (the
        busy-wait runs 4352 times through a 4-instruction loop), so it parks
        after a handful of iterations, while a short routine parks on the first.
        """
        addr = self.L[name]
        if keys is not None:
            self.z.cmd(f"set-ui-io-ports {matrix(keys)}")
        self.z.write_mem(STACK, [self.TRAP & 0xFF, self.TRAP >> 8])
        self.z.cmd(f"set-register SP={STACK:04X}H")
        for r, v in (regs or {}).items():
            self.z.cmd(f"set-register {r}={v:04X}H")
        self.z.cmd(f"set-register PC={addr:04X}H")

        parked = False
        for _ in range(tries):
            self.z.cmd(f"run {limit}")
            if self.regs().get("PC") in (self.TRAP, self.PARKED):
                parked = True
                break
        r = self.regs()
        r["_returned"] = parked
        if not parked:
            raise AssertionError(
                f"{name} did not return within {tries}x{limit} opcodes "
                f"(PC={r.get('PC'):04X}); it is looping")
        return r

    # ---- memory ----------------------------------------------------------
    def poke(self, addr, data):
        self.z.write_mem(addr, data)

    def peek(self, addr, n):
        return self.z.read_mem(addr, n)

    def var(self, name, n=1):
        return self.peek(self.L[name], n)

    def setvar(self, name, data):
        self.poke(self.L[name], data)

    # ---- the playfield ---------------------------------------------------
    def attrs(self):
        return self.z.attrs()

    def cell(self, row, col):
        return self.z.cell(row, col)

    def set_cell(self, row, col, value):
        self.poke(0x5800 + row * 32 + col, [value])

    def board(self):
        return self.z.board(ball=self.ball())

    # ---- ball state ------------------------------------------------------
    def ball(self):
        """(row, col) -- Coord byte 0 is the COLUMN, byte 1 is the ROW."""
        col, row = self.var("Coord", 2)
        return row, col

    def set_ball(self, row, col, frac_col=0, frac_row=0):
        self.setvar("Coord", [col, row])
        self.setvar("CoordFrac", [frac_col, frac_row])

    def velocity(self):
        """(row_velocity, column_velocity) as signed 8.8, in raw units."""
        b = self.var("Vector", 4)
        vr = b[0] | b[1] << 8
        vc = b[2] | b[3] << 8
        return (vr - 65536 if vr > 32767 else vr,
                vc - 65536 if vc > 32767 else vc)

    def set_velocity(self, vrow, vcol):
        vr = vrow & 0xFFFF
        vc = vcol & 0xFFFF
        self.setvar("Vector", [vr & 0xFF, vr >> 8, vc & 0xFF, vc >> 8])

    def close(self):
        self.z.cmd("exit-cpu-step")
        self.z.close()
