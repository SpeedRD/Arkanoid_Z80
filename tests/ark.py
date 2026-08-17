#!/usr/bin/env python3
"""Drive Arkanoid_Z80 under ZEsarUX over ZRCP (its remote debug protocol).

Two things make this project testable without a human at the keyboard:

  * the attribute file at $5800 IS the playfield -- border, bricks, paddle and
    ball are all just coloured 8x8 cells -- so reading 768 bytes gives the
    entire game state. See Z.board() for an ASCII rendering.
  * ZEsarUX's set-ui-io-ports command sets the keyboard matrix directly, which
    is exactly what `teclado` polls with IN A,(C) on $FDFE.

One difference from the sibling Tetris harness worth knowing: this game runs
with interrupts DISABLED for its whole life (`di` at main.asm:5, never an
`ei`). There is no ROM 50 Hz tick, so there is no FRAMES counter to measure
with and no HALT to wait on. Pacing is busy-wait delay loops only.

Run as a script to replay a small command file:

    python3 tests/ark.py tests/scripts/whatever.txt

Script lines ('#' starts a comment):
  boot             reset, load main.bin at $8000, set PC, free-run
  press <NAMES>    hold keys, comma separated: 'press A'
  release          release every key
  tap <NAMES> [ms] press, wait, release
  wait <ms>        sleep
  board            print the attribute file as an ASCII playfield
  regs             print the CPU registers
  shot <name>      save a screenshot (into a temp dir, never the repo)
  poke <LBL|hex> <hexbytes>    write memory; labels come from main.lst
  peek <LBL|hex> <len>         read memory
  cmd <zrcp...>    send a raw ZRCP command
"""
import os
import re
import socket
import subprocess
import sys
import tempfile
import time

HOST, PORT = "localhost", 10000

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
BIN = os.path.join(REPO, "main.bin")
LST = os.path.join(REPO, "main.lst")
# Screenshots are build artefacts. They go to a temp dir, not the repo.
SHOTS = os.path.join(tempfile.gettempdir(), "arkanoid-z80-shots")

ZESARUX = ("/opt/homebrew/Caskroom/zesarux/13.0/ZEsarUX.app"
           "/Contents/MacOS/zesarux")

# Keyboard half-rows, most significant key first: bit4, bit3, bit2, bit1, bit0.
ROWS = [
    ("V", "C", "X", "Z", "SHIFT"),
    ("G", "F", "D", "S", "A"),
    ("T", "R", "E", "W", "Q"),
    ("5", "4", "3", "2", "1"),
    ("6", "7", "8", "9", "0"),
    ("Y", "U", "I", "O", "P"),
    ("H", "J", "K", "L", "ENTER"),
    ("B", "N", "M", "SYM", "SPACE"),
]

# ---- the attribute values this game actually writes -------------------------
# memory-map-and-playfield section 4 owns this table; it is duplicated here
# only so the renderer can name what it sees.
BORDER = 0x0F           # tablero.asm  1*8+7 -- blue paper, white ink
PADDLE = 0x10           # pala.asm     COLORPALA = 2*8 -- red paper
BALL = 0x38             # pelota.asm   8*7 -- white paper
EMPTY = 0x00

ATTRS = 0x5800


def matrix(names):
    """Key names -> the 9 hex bytes set-ui-io-ports wants. A pressed key is 0.

    The Spectrum keyboard is active-low: reading a half-row gives 0 for a
    pressed key and 1 for a released one. failure-patterns section 3 is the
    story of this being misdiagnosed as a debugger bug.
    """
    rows = [0x1F] * 8
    for n in [x.strip().upper() for x in names if x.strip()]:
        found = False
        for r, keys in enumerate(ROWS):
            for i, k in enumerate(keys):
                if k == n:
                    rows[r] &= ~(1 << (4 - i)) & 0x1F
                    found = True
        if not found:
            raise SystemExit(f"unknown key {n!r}")
    return "".join(f"{v:02x}" for v in rows) + "00"


class Z:
    def __init__(self):
        try:
            self.s = socket.create_connection((HOST, PORT), timeout=20)
        except OSError as e:
            raise SystemExit(
                f"cannot reach ZEsarUX on {HOST}:{PORT} ({e}).\n"
                "Start it with ZRCP enabled:\n"
                f"  {ZESARUX} --enable-remoteprotocol "
                "--remoteprotocol-port 10000 --machine 48k &")
        self.s.settimeout(20)
        self._read()

    # ZRCP switches the prompt to "command@cpu-step> " in step mode.
    PROMPTS = (b"command> ", b"command@cpu-step> ")

    def _read(self):
        buf = b""
        while not buf.endswith(self.PROMPTS):
            try:
                c = self.s.recv(65536)
            except socket.timeout:
                break
            if not c:
                break
            buf += c
        t = buf.decode("utf8", "replace")
        for p in self.PROMPTS:
            ps = p.decode()
            if t.endswith(ps):
                return t[: -len(ps)]
        return t

    def cmd(self, c):
        self.s.sendall((c + "\n").encode())
        return self._read().strip()

    # ---- helpers ---------------------------------------------------------
    def read_mem(self, addr, length):
        """Bytes via hexdump, whose lines are 'ADDR xx xx ...  ascii'."""
        out = b""
        done = 0
        while done < length:
            n = min(256, length - done)
            txt = self.cmd(f"hexdump {addr+done:04X}H {n}")
            for line in txt.splitlines():
                parts = line.split()
                if len(parts) < 2:
                    continue
                hx = []
                for p in parts[1:]:
                    if len(p) == 2 and all(ch in "0123456789ABCDEFabcdef"
                                           for ch in p):
                        hx.append(p)
                    else:
                        break
                out += bytes(int(h, 16) for h in hx[:16])
            done += n
        return out[:length]

    def write_mem(self, addr, data):
        self.cmd(f"write-memory-raw {addr:04X}H "
                 f"{''.join(f'{b:02x}' for b in data)}")

    def regs(self):
        t = self.cmd("get-registers")
        return {k: int(v, 16)
                for k, v in re.findall(r"([A-Z]{1,3}'?)=([0-9a-f]{2,4})", t)}

    def boot(self):
        """Cold reset, load the raw image at $8000, jump there, free-run.

        There is no tape, no BASIC stub and no loader -- project-orientation
        section 1. Loading the raw binary and setting PC is the only way in.
        """
        self.cmd("disable-breakpoints")
        self.cmd("close-all-menus")
        self.cmd("enter-cpu-step")
        self.cmd("hard-reset-cpu")
        self.cmd(f'load-binary "{BIN}" 8000H 0')
        self.cmd("set-register PC=8000H")
        self.release()
        self.cmd("exit-cpu-step")

    # ---- input -----------------------------------------------------------
    def press(self, *names):
        self.cmd(f"set-ui-io-ports {matrix(list(names))}")

    def release(self):
        self.cmd(f"set-ui-io-ports {matrix([])}")

    def tap(self, *names, ms=120):
        self.press(*names)
        time.sleep(ms / 1000)
        self.release()

    # ---- reading the playfield -------------------------------------------
    def attrs(self):
        """The whole attribute file: 768 bytes, row-major, 24 rows x 32 cols."""
        return self.read_mem(ATTRS, 768)

    def cell(self, row, col, at=None):
        at = at if at is not None else self.attrs()
        return at[row * 32 + col]

    def ball_cell(self):
        """(row, col) of the ball, from Coord -- NOT by searching for $38.

        `ld hl,(Coord)` puts byte 0 in L and byte 1 in H, and PosXY treats H
        as the row: byte 0 is the COLUMN, byte 1 is the ROW. The declaration
        comment in pelota.asm claims the opposite and is wrong --
        state-and-register-contracts section 1.
        """
        col, row = self.read_mem(resolve("Coord"), 2)
        return row, col

    def board(self, at=None, ball=None):
        """The attribute file as 24 rows of 32 cells.

        '.' empty   '#' border   '=' paddle   'O' ball   '*' invisible
        colour-8 brick   otherwise the brick's PAPER colour digit 1-7.

        The ball is located by `ball` (row, col) rather than by its attribute
        value, because $38 is BOTH the ball and a colour-7 brick -- and
        colour 7 is the most common brick colour in these maps. Pass
        ball=z.ball_cell() to mark it; omit it to render raw attributes.
        """
        at = at if at is not None else self.attrs()
        lines = []
        for r in range(24):
            row = ""
            for c in range(32):
                v = at[r * 32 + c]
                if ball is not None and (r, c) == tuple(ball):
                    row += "O"
                elif v == EMPTY:
                    row += "."
                elif v == BORDER:
                    row += "#"
                elif v == 0x40:            # colour 8 << 3: bright black on black
                    row += "*"
                elif v == PADDLE and r == 23:
                    row += "="
                else:
                    row += str((v >> 3) & 7)
            lines.append(f"{r:2d} |{row}|")
        return "\n".join(lines)

    def find(self, value, at=None):
        """Every (row, col) holding a given attribute byte."""
        at = at if at is not None else self.attrs()
        return [(i // 32, i % 32) for i, v in enumerate(at) if v == value]

    def shot(self, name):
        os.makedirs(SHOTS, exist_ok=True)
        path = os.path.join(SHOTS, f"{name}.bmp")
        if os.path.exists(path):
            os.remove(path)
        self.cmd(f'save-screen "{path}"')
        time.sleep(0.4)
        return path if os.path.exists(path) else None

    def close(self):
        try:
            self.cmd("exit")
        except OSError:
            pass


_LABELS = {}


def labels():
    """Every label in main.lst -> address.

    Never hardcode an address. All ten files are concatenated into one
    `org $8000` image, so every symbol moves whenever anything earlier in the
    include order changes size -- assembler-conventions section 7.
    """
    if not _LABELS:
        pat = re.compile(r"^\s*\d+\+?\s+([0-9A-F]{4})\s+(?:[0-9A-F ]*?\s\s)?"
                         r"([A-Za-z_][A-Za-z0-9_]*):")
        with open(LST, encoding="utf8", errors="replace") as fh:
            for line in fh:
                m = pat.match(line)
                if m:
                    _LABELS.setdefault(m.group(2), int(m.group(1), 16))
    return _LABELS


def resolve(tok):
    """A label from main.lst, or a bare hex address."""
    L = labels()
    return L[tok] if tok in L else int(tok, 16)


def main():
    z = Z()
    script = open(sys.argv[1]).read().splitlines() if len(sys.argv) > 1 else []
    for raw in script:
        line = raw.split("#")[0].strip()
        if not line:
            continue
        op, *a = line.split()
        if op == "boot":
            z.boot()
        elif op == "press":
            z.press(*a[0].split(","))
        elif op == "release":
            z.release()
        elif op == "tap":
            z.tap(*a[0].split(","), ms=int(a[1]) if len(a) > 1 else 120)
        elif op == "wait":
            time.sleep(int(a[0]) / 1000)
        elif op == "board":
            print(z.board(ball=z.ball_cell()))
        elif op == "regs":
            print(z.cmd("get-registers"))
        elif op == "shot":
            print("SHOT:", z.shot(a[0]))
        elif op == "poke":
            z.cmd(f"write-memory-raw {resolve(a[0]):04X}H {a[1]}")
        elif op == "peek":
            print(f"{a[0]} =", z.read_mem(resolve(a[0]), int(a[1])).hex(" "))
        elif op == "cmd":
            print(z.cmd(" ".join(a)))
        else:
            print("?", line)
    z.close()


if __name__ == "__main__":
    main()
