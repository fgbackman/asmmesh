#!/bin/sh
# run.sh — build src/bc_crypto.s for Linux on ARM64 and run it under qemu-aarch64.
#   tools/qemu/run.sh            the self-tests (the same ones `asmmesh --selftest` runs)
#   tools/qemu/run.sh diff [N]   N random cases each, checked against Python's `cryptography`
# Needs: gcc-aarch64-linux-gnu, qemu-user, python3 with cryptography (for diff).
set -e
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../../src"
out="${TMPDIR:-/tmp}/asmmesh-qemu"
mkdir -p "$out"
# Mach-O -> ELF: the macros file and section names are all that differ
sed -e 's/^\.include "macros\.inc"/.include "elf.inc"/' \
    -e 's/^\.section __TEXT,__const/.section .rodata/' \
    "$src/bc_crypto.s" > "$out/bc_crypto.s"
aarch64-linux-gnu-gcc -O1 -static -I "$here" -o "$out/harness" "$here/harness.c" "$out/bc_crypto.s"
case "$1" in
    diff) python3 "$here/diff.py" "$out/harness" "${2:-200}" ;;
    *)    qemu-aarch64 "$out/harness" selftest ;;
esac
