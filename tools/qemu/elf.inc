// elf.inc — stands in for src/macros.inc when bc_crypto.s is built for Linux/qemu
// (tools/qemu/run.sh). Only what the pure crypto file uses.

.macro ENTER locals
    sub  sp, sp, #(96 + \locals)
    stp  x29, x30, [sp, #32]
    add  x29, sp, #32
    stp  x19, x20, [sp, #48]
    stp  x21, x22, [sp, #64]
    stp  x23, x24, [sp, #80]
.endm

.macro LEAVE locals
    ldp  x19, x20, [sp, #48]
    ldp  x21, x22, [sp, #64]
    ldp  x23, x24, [sp, #80]
    ldp  x29, x30, [sp, #32]
    add  sp, sp, #(96 + \locals)
    ret
.endm

.macro ADRL reg, sym
    adrp \reg, \sym
    add  \reg, \reg, :lo12:\sym
.endm
