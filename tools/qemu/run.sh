#!/bin/sh
# run.sh — build the pure bitchat files (src/bc_crypto.s, src/bc_link.s) for Linux on
# ARM64 and run them under qemu-aarch64.
#   tools/qemu/run.sh            the self-tests (the same ones `asmmesh --selftest` runs)
#   tools/qemu/run.sh diff [N]   N random cases each, checked against Python's `cryptography`
# Needs: gcc-aarch64-linux-gnu, qemu-user, python3 with cryptography (for diff).
set -e
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../../src"
out="${TMPDIR:-/tmp}/asmmesh-qemu"
mkdir -p "$out"
# Mach-O -> ELF: the macros file, section names and libc's leading underscore
for f in bc_crypto bc_link; do
    sed -e 's/^\.include "macros\.inc"/.include "elf.inc"/' \
        -e 's/^\.section __TEXT,__const/.section .rodata/' \
        -e 's/bl   _\(memcpy\|calloc\|free\)$/bl   \1/' \
        "$src/$f.s" > "$out/$f.s"
done
aarch64-linux-gnu-gcc -O1 -static -I "$here" -I "$src" -o "$out/harness" "$here/harness.c" "$out/bc_crypto.s" "$out/bc_link.s"
case "$1" in
    diff) python3 "$here/diff.py" "$out/harness" "${2:-200}" ;;
    *)    qemu-aarch64 "$out/harness" selftest ;;
esac
