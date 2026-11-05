// ff_core.s — Fivefold's rules, pure (no globals, no system calls): five-letter words from
// the same lists as Ninefold (ff_words.bin, made by tools/ninefold/ff.py pack), a guess's
// colours (2 right place, 1 in the word elsewhere, 0 not in it; repeated letters counted
// right), the day's word, a race's word from its seed, and a duel's sealed word. ff.py is the
// Python copy. Self-test 220.
.include "macros.inc"

.set FF_EPOCH,      1767225600       // 2026-01-01 00:00 UTC: day 0

.macro FFK reg, v                         // a 32-bit constant (MOVI clashes with GNU's movi)
    movz \reg, #((\v) & 0xffff)
    movk \reg, #(((\v) >> 16) & 0xffff), lsl #16
.endm

.text
.p2align 2

// long _ff_counts(void) -> x0 hidden words, x1 every word a guess may be (leaf)
.globl _ff_counts
_ff_counts:
    ADRL x9, Lff_bin
    ldr  w0, [x9, #8]
    ldr  w1, [x9, #12]
    ret

// const char *_ff_hidden(long i) -> hidden word i (mod their count), 5 letters, no NUL (leaf)
.globl _ff_hidden
_ff_hidden:
    ADRL x9, Lff_bin
    ldr  w10, [x9, #8]
    udiv x11, x0, x10
    msub x0, x11, x10, x0
    mov  x11, #5
    madd x0, x0, x11, x9
    add  x0, x0, #16
    ret

// long _ff_daily(long unix_time) -> the day's hidden word's number (UTC days since 2026) (leaf)
.globl _ff_daily
_ff_daily:
    FFK  x9, FF_EPOCH
    subs x0, x0, x9
    csel x0, xzr, x0, lt
    FFK  x9, 86400
    udiv x0, x0, x9
    ret

// long _ff_pick(uint64 seed) -> a hidden word's number for a race (splitmix64 of the seed)
.globl _ff_pick
_ff_pick:
    movz x9, #0x7C15
    movk x9, #0x7F4A, lsl #16
    movk x9, #0x79B9, lsl #32
    movk x9, #0x9E37, lsl #48
    add  x0, x0, x9
    eor  x1, x0, x0, lsr #30
    movz x9, #0xE5B9
    movk x9, #0x1CE4, lsl #16
    movk x9, #0x476D, lsl #32
    movk x9, #0xBF58, lsl #48
    mul  x1, x1, x9
    eor  x1, x1, x1, lsr #27
    movz x9, #0x11EB
    movk x9, #0x1331, lsl #16
    movk x9, #0xD049, lsl #32
    movk x9, #0x94D0, lsl #48
    mul  x1, x1, x9
    eor  x1, x1, x1, lsr #31
    ADRL x9, Lff_bin
    ldr  w10, [x9, #8]
    udiv x11, x1, x10
    msub x0, x11, x10, x1
    ret

// long _ff_norm(const char *text, long len, char out[6]) -> 0 and out: five letters, small,
//   NUL-terminated (spaces around them allowed); -1 if it isn't five letters (leaf)
.globl _ff_norm
_ff_norm:
    mov  x9, #0                           // in
    mov  x10, #0                          // letters out
1:  cmp  x9, x1
    b.hs 4f
    ldrb w11, [x0, x9]
    add  x9, x9, #1
    cbz  w11, 4f
    cmp  w11, #' '
    b.ne 2f
    cbz  x10, 1b                          // before the word
    b    3f                               // after it: only spaces may follow
2:  orr  w12, w11, #0x20
    sub  w13, w12, #'a'
    cmp  w13, #25
    b.hi 8f
    cmp  x10, #5
    b.hs 8f
    strb w12, [x2, x10]
    add  x10, x10, #1
    b    1b
3:  cmp  x9, x1
    b.hs 4f
    ldrb w11, [x0, x9]
    add  x9, x9, #1
    cbz  w11, 4f
    cmp  w11, #' '
    b.eq 3b
    b    8f
4:  cmp  x10, #5
    b.ne 8f
    strb wzr, [x2, #5]
    mov  x0, #0
    ret
8:  mov  x0, #-1
    ret

// long _ff_valid(const char word[5]) -> 1 if it's a word a guess may be (binary search) (leaf)
.globl _ff_valid
_ff_valid:
    ADRL x9, Lff_bin
    ldr  w10, [x9, #8]
    ldr  w11, [x9, #12]
    mov  x12, #5
    madd x9, x10, x12, x9
    add  x9, x9, #16                      // the sorted list
    mov  x10, #0                          // lo
1:  cmp  x10, x11
    b.hs 8f
    add  x12, x10, x11
    lsr  x12, x12, #1
    mov  x13, #5
    madd x13, x12, x13, x9
    mov  x14, #0
2:  ldrb w15, [x0, x14]
    ldrb w16, [x13, x14]
    cmp  w15, w16
    b.lo 3f
    b.hi 4f
    add  x14, x14, #1
    cmp  x14, #5
    b.lo 2b
    mov  x0, #1
    ret
3:  mov  x11, x12                         // before it
    b    1b
4:  add  x10, x12, #1                     // after it
    b    1b
8:  mov  x0, #0
    ret

// long _ff_score(const char guess[5], const char word[5], uint8 out[5]) -> 1 if guessed;
//   out: 2 right place, 1 in the word elsewhere, 0 not (as many 1s as the word has left) (leaf)
.globl _ff_score
_ff_score:
    sub  sp, sp, #32                      // the word's letters not matched yet (26)
    stp  xzr, xzr, [sp]
    stp  xzr, xzr, [sp, #16]
    mov  x9, #0
    mov  x14, #0                          // right places
1:  ldrb w10, [x0, x9]
    ldrb w11, [x1, x9]
    cmp  w10, w11
    b.ne 2f
    mov  w12, #2
    strb w12, [x2, x9]
    add  x14, x14, #1
    b    3f
2:  strb wzr, [x2, x9]
    sub  w11, w11, #'a'
    and  w11, w11, #31
    ldrb w12, [sp, x11]
    add  w12, w12, #1
    strb w12, [sp, x11]
3:  add  x9, x9, #1
    cmp  x9, #5
    b.lo 1b
    mov  x9, #0                           // then the others, from what's left
4:  ldrb w12, [x2, x9]
    cmp  w12, #2
    b.eq 5f
    ldrb w10, [x0, x9]
    sub  w10, w10, #'a'
    and  w10, w10, #31
    ldrb w12, [sp, x10]
    cbz  w12, 5f
    sub  w12, w12, #1
    strb w12, [sp, x10]
    mov  w12, #1
    strb w12, [x2, x9]
5:  add  x9, x9, #1
    cmp  x9, #5
    b.lo 4b
    add  sp, sp, #32
    cmp  x14, #5
    cset x0, eq
    ret

// void _ff_commit(const uint8 salt[16], uint64 player, const char word[5], uint8 out[16])
//   a duel's sealed word: SHA-256(salt | player id (8, little-endian) | word), first 16 bytes
.globl _ff_commit
_ff_commit:
    ENTER 64                              // [96] the message (29)  [128] the digest
    mov  x19, x3
    ldp  x9, x10, [x0]
    stp  x9, x10, [sp, #96]
    str  x1, [sp, #112]
    ldr  w9, [x2]
    str  w9, [sp, #120]
    ldrb w9, [x2, #4]
    strb w9, [sp, #124]
    add  x0, sp, #96
    mov  x1, #29
    add  x2, sp, #128
    bl   _bc_sha256
    ldp  x9, x10, [sp, #128]
    stp  x9, x10, [x19]
    LEAVE 64

// ---------------------------------------------------------------------------
// self-test 220, called from test.s (vectors from tools/ninefold/ff.py)

.globl _ff_core_selftest
_ff_core_selftest:
    ENTER 96                              // [96] colours  [104] a word  [128] digest
    mov  x19, #0
    mov  x20, #1
    ADRL x21, Lft_scores                  // guess, word, colours as 5 digits
1:  ldrb w9, [x21]
    cbz  w9, 2f
    mov  x0, x21
    add  x1, x21, #5
    add  x2, sp, #96
    bl   _ff_score
    mov  x22, x0
    mov  x9, #0
    mov  x23, #1                          // all five right?
11: add  x10, sp, #96
    ldrb w10, [x10, x9]
    add  x11, x21, #10
    ldrb w11, [x11, x9]
    sub  w11, w11, #'0'
    cmp  w10, w11
    csel x20, xzr, x20, ne
    cmp  w10, #2
    csel x23, xzr, x23, ne
    add  x9, x9, #1
    cmp  x9, #5
    b.lo 11b
    cmp  x22, x23
    csel x20, xzr, x20, ne
    add  x21, x21, #15
    b    1b
2:  ADRL x0, Lft_crane                    // words, and not
    bl   _ff_valid
    and  x20, x20, x0
    ADRL x0, Lft_aback
    bl   _ff_valid
    and  x20, x20, x0
    ADRL x0, Lft_xxxxx
    bl   _ff_valid
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lft_typed                    // " Crane " -> "crane"; "cr4ne", "cran" refused
    mov  x1, #7
    add  x2, sp, #104
    bl   _ff_norm
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #104
    ADRL x1, Lft_crane
    bl   Lft_same
    and  x20, x20, x0
    ADRL x0, Lft_bad1
    mov  x1, #5
    add  x2, sp, #104
    bl   _ff_norm
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lft_bad2
    mov  x1, #4
    add  x2, sp, #104
    bl   _ff_norm
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    FFK  x0, FF_EPOCH                     // day 0, day 1; the list wraps round
    bl   _ff_daily
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    FFK  x0, (FF_EPOCH + 86400 + 3600)
    bl   _ff_daily
    cmp  x0, #1
    cset x9, eq
    and  x20, x20, x9
    bl   _ff_counts
    mov  x22, x0
    bl   _ff_hidden
    mov  x23, x0
    mov  x0, #0
    bl   _ff_hidden
    cmp  x0, x23
    cset x9, eq
    and  x20, x20, x9
    mov  x0, x22                          // every hidden word is a valid guess (the first
    bl   _ff_hidden                       //   and one far in)
    bl   _ff_valid
    and  x20, x20, x0
    mov  x0, #1000
    bl   _ff_hidden
    bl   _ff_valid
    and  x20, x20, x0
    add  x0, sp, #104                     // a sealed word
    mov  x9, #0
3:  strb w9, [x0, x9]
    add  x9, x9, #1
    cmp  x9, #16
    b.lo 3b
    movz x1, #0x7788
    movk x1, #0x5566, lsl #16
    movk x1, #0x3344, lsl #32
    movk x1, #0x1122, lsl #48
    ADRL x2, Lft_crane
    add  x3, sp, #128
    bl   _ff_commit
    ldp  x9, x10, [sp, #128]
    ADRL x11, Lft_commit
    ldp  x12, x13, [x11]
    cmp  x9, x12
    ccmp x10, x13, #0, eq
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_ff220
    bl   _t_report
    add  x19, x19, x0
    mov  x0, x19
    LEAVE 96

// Lft_same(a, b) -> 1 if equal (leaf)
Lft_same:
    ldrb w9, [x0], #1
    ldrb w10, [x1], #1
    cmp  w9, w10
    b.ne 1f
    cbnz w9, Lft_same
    mov  x0, #1
    ret
1:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lft_commit:     .byte 0xca, 0x15, 0x39, 0x5c, 0x5c, 0xa3, 0xd5, 0xbc, 0xc2, 0xf9, 0x7d, 0xba, 0x35, 0x3a, 0x04, 0xee
Lft_scores:     .ascii "speedabide00101"     // guess, word, colours (ff.py score)
                .ascii "eeriegeese12002"
                .ascii "geeseeerie02102"
                .ascii "llamaallay12101"
                .ascii "robotrobot22222"
                .ascii "abbeykebab11210"
                .byte 0
.p2align 3
Lff_bin:
.incbin "ff_words.bin"
Lff_bin_end:

.section __TEXT,__cstring,cstring_literals
Lft_crane:      .asciz "crane"
Lft_aback:      .asciz "aback"
Lft_xxxxx:      .asciz "xxxxx"
Lft_typed:      .asciz " Crane "
Lft_bad1:       .asciz "cr4ne"
Lft_bad2:       .asciz "cran"
Ln_ff220:       .asciz "220 fivefold: colours with repeated letters, words, the day's word, a sealed word"
