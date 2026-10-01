// fm_defs.inc — definitions for the FM radio code (ported from asmfm).
// Kept separate from macros.inc: these files use their own frame macros
// (FENTER/FLEAVE save x19..x28), since the modem needs every callee-saved register.

.set LOC,       96
.set O_RDONLY,  0
.set O_RDWR,    2
.set O_WR_CREAT_TRUNC, 0x601
.set CLOCK_MONO, 6

// ---- modem state block offsets ----
.set M_BAUD,    0
.set M_SPB,     4
.set M_STEPM,   8
.set M_STEPS,   12
.set M_PLLSTEP, 16
.set M_NPRE,    20
.set M_TXPH,    24
.set M_TXTONE,  28
.set M_RXPM,    44
.set M_RXPS,    48
.set M_RPOS,    52
.set M_PLL,     56
.set M_PREV,    60
.set M_LAST,    64
.set M_SR,      68
.set M_ONES,    72
.set M_INF,     76
.set M_NBIT,    80
.set M_BYTE,    84
.set M_BLEN,    88
.set M_SINCE,   92                  // bits since the last HDLC flag
.set M_IM,      96
.set M_QM,      104
.set M_IS,      112
.set M_QS,      120
.set M_RIM,     128
.set M_RQM,     384
.set M_RIS,     640
.set M_RQS,     896
.set M_FBUF,    1152
.set M_SIZE,    1536

.set FS,        48000
.set FM_MAGIC0,  0x4D                // every mesh packet starts 'M', protocol 3
.set FM_MAGIC1,  3
.set MAXFRAME,  260
.set TXCAP,     (1<<20)
.set MODBUF,    480000              // two error-corrected copies at 1200 baud

.macro LA reg, sym
    adrp \reg, \sym\()@PAGE
    add  \reg, \reg, \sym\()@PAGEOFF
.endm

.macro BSS name, size
    .globl \name
    .zerofill __DATA,__bss,\name,\size,4
.endm

.macro FENTER locals=0
    stp x29, x30, [sp, #-(96+\locals)]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]
.endm
.macro FLEAVE locals=0
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x23, x24, [sp, #48]
    ldp x25, x26, [sp, #64]
    ldp x27, x28, [sp, #80]
    ldp x29, x30, [sp], #(96+\locals)
    ret
.endm

.macro MOVL reg, val
    movz \reg, #((\val) & 0xFFFF)
    movk \reg, #(((\val) >> 16) & 0xFFFF), lsl #16
.endm
