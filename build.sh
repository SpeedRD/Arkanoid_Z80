#!/bin/sh
# Build Arkanoid_Z80.
#
# There is exactly ONE entry point: main.asm. Every other .asm in this tree is
# an INCLUDE fragment and is not independently assemblable -- assembling one
# directly produces a cascade of "Label not found" and a garbage binary whose
# every call target is CD 00 00. The repo used to build ${file} (whatever had
# editor focus), and the wreckage from that was committed for twenty months.
#
# sjasmplus exits 0 even when it emits warnings, so this script reads the
# summary line rather than trusting the exit code.
#
# Usage:  ./build.sh            build in place (main.bin/.lst/.sld)
#         ./build.sh OUTDIR     build into OUTDIR instead, leaving the repo clean
set -eu

cd "$(dirname "$0")"

OUT="${1:-.}"
[ "$OUT" = "." ] || mkdir -p "$OUT"

log=$(sjasmplus --fullpath \
        --lst="$OUT/main.lst" \
        --sld="$OUT/main.sld" \
        --raw="$OUT/main.bin" \
        main.asm 2>&1) || {
    printf '%s\n' "$log"
    echo "build.sh: sjasmplus failed" >&2
    exit 1
}

printf '%s\n' "$log"

summary=$(printf '%s\n' "$log" | grep '^Errors:' | tail -1)
case "$summary" in
    "Errors: 0, warnings: 0"*) ;;
    *)
        echo "build.sh: build not clean -- fix this before trusting a run" >&2
        exit 1
        ;;
esac
