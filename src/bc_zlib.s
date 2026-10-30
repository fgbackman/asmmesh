// bc_zlib.s — _bc_inflate for bc_packet.s: bitchat's compressed payloads are raw DEFLATE
// (Apple's COMPRESSION_ZLIB, no zlib header), unpacked here with libz (-lz on the Mac and
// iPhone). Under qemu, tools/qemu/inflate.c stands in for this file.

.include "macros.inc"

.text
.p2align 2

// long _bc_inflate(uint8 *dst, long dcap, const uint8 *src, long slen) -> bytes made, or -1
//   if the stream is broken, runs out, or wants more than dcap. It must end properly.
.globl _bc_inflate
_bc_inflate:
    ENTER 112                             // [96] z_stream: next_in 0, avail_in 8, next_out 24,
    mov  x19, x0                          //   avail_out 32, total_out 40; 112 bytes in all
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x9, #0xffffffff                  // the counts are 32-bit
    cmp  x20, x9
    b.hi Lzi_bad
    cmp  x22, x9
    b.hi Lzi_bad
    add  x23, sp, #96
    mov  x9, #0
1:  str  xzr, [x23, x9]
    add  x9, x9, #8
    cmp  x9, #112
    b.lo 1b
    str  x21, [x23]
    str  w22, [x23, #8]
    str  x19, [x23, #24]
    str  w20, [x23, #32]
    mov  x0, x23
    mov  w1, #-15                         // raw DEFLATE, 32 KB window
    ADRL x2, Lzi_version
    mov  x3, #112
    bl   _inflateInit2_
    cbnz w0, Lzi_bad
    mov  x0, x23
    mov  w1, #4                           // Z_FINISH
    bl   _inflate
    mov  x24, x0
    ldr  x21, [x23, #40]                  // total_out
    mov  x0, x23
    bl   _inflateEnd
    cmp  w24, #1                          // Z_STREAM_END: it ended, and fitted
    b.ne Lzi_bad
    mov  x0, x21
    LEAVE 112
Lzi_bad:
    mov  x0, #-1
    LEAVE 112

.section __TEXT,__cstring,cstring_literals
Lzi_version: .asciz "1.2.12"              // libz only checks the first digit
