#!/usr/bin/env python3
"""Build, then run every suite. Usage: python3 tests/run_all.py [name ...]"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

SUITES = [
    ("test_pelota",     "cell classification, wall geometry, erase-restore"),
    ("test_colisiones", "brick destruction, the counter, paddle rebound angle"),
    ("test_juego",      "keyboard dispatch, state resets, lose/complete paths"),
    ("checklist",       "build-and-verify section 6, end to end on a live game"),
]


def build():
    r = subprocess.run(["./build.sh"], cwd=REPO, capture_output=True, text=True)
    out = (r.stdout or "") + (r.stderr or "")
    line = ([l for l in out.splitlines() if l.startswith("Errors:")] or
            out.strip().splitlines() or ["no output"])[-1]
    print(f"build: {line}")
    # build.sh already refuses to exit 0 unless the build is clean, because
    # sjasmplus itself exits 0 even when it emits warnings.
    if r.returncode != 0:
        print("BUILD NOT CLEAN -- fix that before trusting any suite below.")
        return False
    return True


def main():
    if not build():
        return 1
    wanted = sys.argv[1:] or [n for n, _ in SUITES]
    failed = []
    for name, blurb in SUITES:
        if name not in wanted:
            continue
        print(f"\n=== {name}  ({blurb})")
        r = subprocess.run([sys.executable, "-u", f"{name}.py"],
                           cwd=HERE, capture_output=True, text=True)
        for l in r.stdout.splitlines():
            if l.strip().startswith("FAIL") or "ALL PASS" in l or "FAILURES" in l:
                print("   ", l.strip())
        if r.returncode != 0 or "ALL PASS" not in r.stdout:
            failed.append(name)
            if r.stderr.strip():
                print("   ", r.stderr.strip().splitlines()[-1])
    print("\n" + ("EVERY SUITE PASSED" if not failed else f"FAILED: {failed}"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
