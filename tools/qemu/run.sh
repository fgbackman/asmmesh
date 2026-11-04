#!/bin/sh
# run.sh — build the pure bitchat files (src/bc_crypto.s, bc_link.s, bc_packet.s, bc_peer.s) for Linux on
# ARM64 and run them under qemu-aarch64.
#   tools/qemu/run.sh            the self-tests (the same ones `asmmesh --selftest` runs)
#   tools/qemu/run.sh chmesh     chess's glue (ch_mesh.s) with stand-ins for the app: both transports
#   tools/qemu/run.sh chperft    chess perft, deeper than the self-tests, against published counts
#   tools/qemu/run.sh nfdiff [N] N random seeds: Ninefold's puzzles against tools/ninefold/nf.py
#   tools/qemu/run.sh diff [N]   N random cases each, checked against Python's `cryptography`,
#                                zlib and tools/qemu/bcwire.py (bitchat's rules)
# Needs: gcc-aarch64-linux-gnu, qemu-user, python3 with cryptography (for diff).
set -e
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../../src"
out="${TMPDIR:-/tmp}/asmmesh-qemu"
mkdir -p "$out"
python3 "$here/lint.py" >/dev/null || { python3 "$here/lint.py"; exit 1; }   # ENTER/LEAVE, LINK
# Mach-O -> ELF: the macros file, section names and libc's leading underscore
for f in bc_crypto bc_link bc_packet bc_peer bc_noise term_core hue_core nf_core nf_play nf_text ch_core ch_play cf_core; do
    sed -e 's/^\.include "macros\.inc"/.include "elf.inc"/' \
        -e 's/^\.section __TEXT,__const/.section .rodata/' \
        -e 's/^\.section __TEXT,__cstring,cstring_literals/.section .rodata/' \
        -e 's/^\.section __DATA,__const/.section .data.rel.ro/' \
        -e 's/bl   _\(memcpy\|calloc\|free\)$/bl   \1/' \
        "$src/$f.s" > "$out/$f.s"
done
aarch64-linux-gnu-gcc -O1 -static -I "$here" -I "$src" -o "$out/harness" "$here/harness.c" "$here/inflate.c" "$out/bc_crypto.s" "$out/bc_link.s" "$out/bc_packet.s" "$out/bc_peer.s" "$out/bc_noise.s" "$out/term_core.s" "$out/hue_core.s" "$out/nf_core.s" "$out/nf_play.s" "$out/nf_text.s" "$out/ch_core.s" "$out/ch_play.s" "$out/cf_core.s"
case "$1" in
    diff) python3 "$here/diff.py" "$out/harness" "${2:-200}" ;;
    chperft) qemu-aarch64 "$out/harness" chperft ;;
    chmesh)                    # chess's glue with stand-ins for the app
        sed -e 's/^\.include "macros\.inc"/.include "elf.inc"\n.include "chmesh.inc"/' \
            -e 's/^\.section __TEXT,__cstring,cstring_literals/.section .rodata/' \
            -e 's/^\.zerofill __DATA,__bss,\([_a-z]*\),\([A-Z_0-9]*\),4.*/.comm \1,\2,16/' \
            -e 's/bl   _memcpy$/bl   memcpy/' -e 's/bl   _snprintf$/bl   Lsnprintf_apple/' \
            "$src/ch_mesh.s" > "$out/ch_mesh.s"
        printf '.text\nLsnprintf_apple:\n    ldr x3, [sp]\n    ldr x4, [sp, #8]\n    ldr x5, [sp, #16]\n    b snprintf\n' >> "$out/ch_mesh.s"
        aarch64-linux-gnu-gcc -O1 -static -I "$here" -I "$src" -o "$out/chmesh" "$here/chmesh.c" "$out/bc_crypto.s" "$out/ch_core.s" "$out/ch_play.s" "$out/ch_mesh.s" && qemu-aarch64 "$out/chmesh" ;;
    nfdemo) qemu-aarch64 "$out/harness" nfdemo ;;
    nfdiff) python3 "$here/nfdiff.py" "$out/harness" "${2:-200}" ;;
    *)    qemu-aarch64 "$out/harness" selftest ;;
esac
