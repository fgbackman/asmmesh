// term_core.s — the input field's memory and suggestions, the parts that only move bytes
// (term.s does the Cocoa). Pure functions on caller-owned memory, no libc, so they run
// under qemu too (tools/qemu/run.sh).
//
// History: the last TH_N lines typed, newest first, like a terminal's. ↑ walks back, ↓
// forward, and past the newest you get back what you were typing (the draft). Each line
// says whether it may be kept across launches (not lines from private or bitchat rooms).
//
//   header  +0 count  +8 newest slot  +16 where ↑ has got to (-1: not browsing)
//           +24 the draft (TH_LEN)
//   slot    +0 keep (1: may be saved)  +8 the text, 0-terminated (TH_LEN)
//
// Suggestions: Home's commands that start with what's typed, then ones that contain it,
// case-insensitive, each once. The word list is (text, kind) pairs, 16 bytes each, ending
// with text 0; kind 1 or 3 means "first words, then more" (rules.s).

.include "macros.inc"

.set TH_N,      100
.set TH_LEN,    256
.set TH_ESZ,    (8 + TH_LEN)
.set TH_COUNT,  0
.set TH_NEWEST, 8
.set TH_POS,    16
.set TH_DRAFT,  24
.set TH_HDR,    (TH_DRAFT + TH_LEN)
.set TH_SIZE,   (TH_HDR + TH_N * TH_ESZ)

.text
.p2align 2

// long _th_size(void) -> how many bytes a history needs (term.s allocates it)
.globl _th_size
_th_size:
    mov  x0, #(TH_SIZE & 0xffff)
    ret

// long Lcut(const char *s) -> its length, at most TH_LEN - 1, cut before a character rather
//   than inside one (leaf: x9-x11)
Lcut:
    mov  x9, #0
1:  ldrb w10, [x0, x9]
    cbz  w10, 2f
    add  x9, x9, #1
    cmp  x9, #(TH_LEN - 1)
    b.lo 1b
2:  cmp  x9, #(TH_LEN - 1)
    b.lo 4f
    ldrb w10, [x0, x9]                    // cut: not inside a character
    cbz  w10, 4f
3:  cbz  x9, 4f
    ldrb w10, [x0, x9]
    and  w10, w10, #0xc0
    cmp  w10, #0x80
    b.ne 4f
    sub  x9, x9, #1
    b    3b
4:  mov  x0, x9
    ret

// void Lput(char *dst, const char *src, long n) — n bytes, then 0 (leaf: x9, x10)
Lput:
    mov  x9, #0
1:  cmp  x9, x2
    b.hs 2f
    ldrb w10, [x1, x9]
    strb w10, [x0, x9]
    add  x9, x9, #1
    b    1b
2:  strb wzr, [x0, x9]
    ret

// long Lsame(const char *a, const char *b) -> 1 if equal (leaf: x9-x11)
Lsame:
    mov  x9, #0
1:  ldrb w10, [x0, x9]
    ldrb w11, [x1, x9]
    cmp  w10, w11
    b.ne 2f
    add  x9, x9, #1
    cbnz w10, 1b
    mov  x0, #1
    ret
2:  mov  x0, #0
    ret

// char *_th_entry(h, long k) -> the k-th line back from the newest (0: newest), or 0 (leaf)
.globl _th_entry
_th_entry:
    ldr  x9, [x0, #TH_COUNT]
    cmp  x1, x9
    b.hs 1f
    ldr  x10, [x0, #TH_NEWEST]
    sub  x10, x10, x1
    add  x10, x10, #TH_N                  // (newest - k) mod TH_N
    mov  x11, #TH_N
    udiv x12, x10, x11
    msub x10, x12, x11, x10
    mov  x11, #TH_ESZ
    madd x9, x10, x11, x0
    add  x0, x9, #(TH_HDR + 8)
    ret
1:  mov  x0, #0
    ret

// void _th_add(h, const char *text, long keep) — a line typed. Empty lines and repeats of
//   the newest aren't added twice (a repeat may still become one to keep). Browsing ends.
.globl _th_add
_th_add:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x9, #-1
    str  x9, [x19, #TH_POS]
    mov  x0, x20
    bl   Lcut
    cbz  x0, 9f
    mov  x22, x0
    ldr  x9, [x19, #TH_COUNT]
    cbz  x9, 2f
    mov  x0, x19                          // the same as the newest?
    mov  x1, #0
    bl   _th_entry
    mov  x23, x0
    mov  x1, x20
    bl   Lsame
    cbz  x0, 1f
    ldr  x9, [x23, #-8]
    orr  x9, x9, x21
    str  x9, [x23, #-8]
    b    9f
1:  ldr  x9, [x19, #TH_NEWEST]            // the next slot round
    add  x9, x9, #1
    cmp  x9, #TH_N
    csel x9, xzr, x9, hs
    str  x9, [x19, #TH_NEWEST]
    b    3f
2:  str  xzr, [x19, #TH_NEWEST]
3:  ldr  x9, [x19, #TH_COUNT]
    add  x9, x9, #1
    cmp  x9, #TH_N
    mov  x10, #TH_N
    csel x9, x9, x10, ls
    str  x9, [x19, #TH_COUNT]
    mov  x0, x19
    mov  x1, #0
    bl   _th_entry
    str  x21, [x0, #-8]
    mov  x1, x20
    mov  x2, x22
    bl   Lput
9:  LEAVE 0

// char *_th_prev(h, const char *typing) -> the line ↑ brings back, or 0 if there's none.
//   The first ↑ keeps what was being typed, for ↓ to give back.
.globl _th_prev
_th_prev:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ldr  x9, [x19, #TH_COUNT]
    cbz  x9, 8f
    ldr  x21, [x19, #TH_POS]
    tbz  x21, #63, 1f
    mov  x0, x20                          // not browsing yet: keep the draft
    bl   Lcut
    mov  x2, x0
    add  x0, x19, #TH_DRAFT
    mov  x1, x20
    bl   Lput
    mov  x21, #0
    b    2f
1:  add  x10, x21, #1                     // back one, unless at the oldest
    ldr  x9, [x19, #TH_COUNT]
    cmp  x10, x9
    csel x21, x10, x21, lo
2:  str  x21, [x19, #TH_POS]
    mov  x0, x19
    mov  x1, x21
    bl   _th_entry
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// char *_th_next(h) -> the line ↓ brings back (past the newest: the draft), or 0 if not
//   browsing (leaf apart from _th_entry)
.globl _th_next
_th_next:
    ldr  x9, [x0, #TH_POS]
    tbnz x9, #63, 2f
    sub  x9, x9, #1
    str  x9, [x0, #TH_POS]
    tbnz x9, #63, 1f
    mov  x1, x9
    b    _th_entry
1:  add  x0, x0, #TH_DRAFT
    ret
2:  mov  x0, #0
    ret

// void _th_reset(h) — not browsing any more (leaf)
.globl _th_reset
_th_reset:
    mov  x9, #-1
    str  x9, [x0, #TH_POS]
    ret

// long _th_pack(h, char *out, long cap) -> its length: the lines that may be kept, oldest
//   first, one per line, 0-terminated; as many as fit
.globl _th_pack
_th_pack:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, #0                          // length so far
    strb wzr, [x20]
    ldr  x23, [x19, #TH_COUNT]
1:  cbz  x23, 9f
    sub  x23, x23, #1
    mov  x0, x19
    mov  x1, x23
    bl   _th_entry
    ldr  x9, [x0, #-8]
    cbz  x9, 1b
    mov  x24, x0
    bl   Lcut                             // (always under TH_LEN)
    add  x9, x22, x0
    add  x9, x9, #2                       // the line, '\n' and the final 0
    cmp  x9, x21
    b.hi 9f
    mov  x2, x0
    add  x0, x20, x22
    mov  x1, x24
    add  x22, x22, x2
    bl   Lput
    mov  w9, #'\n'
    strb w9, [x20, x22]
    add  x22, x22, #1
    strb wzr, [x20, x22]
    b    1b
9:  mov  x0, x22
    LEAVE 0

// void _th_unpack(h, const char *in) — lines saved by _th_pack, back in (each to keep)
.globl _th_unpack
_th_unpack:
    ENTER TH_LEN                          // [96] one line
    mov  x19, x0
    mov  x20, x1
1:  ldrb w9, [x20]
    cbz  w9, 9f
    mov  x21, #0                          // to the end of the line
2:  ldrb w9, [x20, x21]
    cbz  w9, 3f
    cmp  w9, #'\n'
    b.eq 3f
    add  x21, x21, #1
    b    2b
3:  mov  x22, x21                         // at most TH_LEN - 1 of it
    cmp  x22, #(TH_LEN - 1)
    mov  x9, #(TH_LEN - 1)
    csel x22, x22, x9, lo
    add  x0, sp, #96
    mov  x1, x20
    mov  x2, x22
    bl   Lput
    add  x0, sp, #96                      // (a cut line: not inside a character)
    bl   Lcut
    add  x9, sp, #96
    strb wzr, [x9, x0]
    mov  x0, x19
    add  x1, sp, #96
    mov  x2, #1
    bl   _th_add
    add  x20, x20, x21
    ldrb w9, [x20]
    cbz  w9, 9f
    add  x20, x20, #1                     // past the '\n'
    b    1b
9:  LEAVE TH_LEN

// long Lhas(const char *word, const char *text, long tl, long at_start) -> 1 if word starts
//   with text (at_start) or has it anywhere, ignoring ASCII case (leaf: x9-x15)
Lhas:
    mov  x9, #0                           // where in word
1:  mov  x10, #0
2:  cmp  x10, x2
    b.hs 8f
    add  x11, x9, x10
    ldrb w12, [x0, x11]
    cbz  w12, 9f
    ldrb w13, [x1, x10]
    sub  w14, w12, #'A'
    cmp  w14, #25
    b.hi 3f
    add  w12, w12, #32
3:  sub  w14, w13, #'A'
    cmp  w14, #25
    b.hi 4f
    add  w13, w13, #32
4:  cmp  w12, w13
    b.ne 5f
    add  x10, x10, #1
    b    2b
5:  cbnz x3, 9f
    ldrb w12, [x0, x9]
    cbz  w12, 9f
    add  x9, x9, #1
    b    1b
8:  mov  x0, #1
    ret
9:  mov  x0, #0
    ret

// long _sg_match(const pair *words, const char *text, pair *out, long max) -> how many: the
//   words that start with text, then those that contain it, each text once
.globl _sg_match
_sg_match:
    ENTER 32                              // [96] text length [104] pass (1: starts with)
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, #0                          // found
    mov  x9, #0
1:  ldrb w10, [x20, x9]
    cbz  w10, 2f
    add  x9, x9, #1
    b    1b
2:  cbz  x9, 9f
    str  x9, [sp, #96]
    mov  x9, #1
    str  x9, [sp, #104]
3:  mov  x24, x19                         // one pass over the words
4:  cmp  x23, x22
    b.hs 9f
    ldr  x0, [x24]
    cbz  x0, 7f
    mov  x1, x20
    ldr  x2, [sp, #96]
    ldr  x3, [sp, #104]
    bl   Lhas
    cbz  x0, 6f
    ldr  x9, [sp, #104]                   // the second pass: only those not starting with it
    cbnz x9, 41f
    ldr  x0, [x24]
    mov  x1, x20
    ldr  x2, [sp, #96]
    mov  x3, #1
    bl   Lhas
    cbnz x0, 6f
41: mov  x9, #0                           // listed already?
5:  cmp  x9, x23
    b.hs 51f
    add  x0, x21, x9, lsl #4
    ldr  x0, [x0]
    ldr  x1, [x24]
    str  x9, [sp, #112]
    bl   Lsame
    ldr  x9, [sp, #112]
    cbnz x0, 6f
    add  x9, x9, #1
    b    5b
51: ldp  x9, x10, [x24]
    add  x11, x21, x23, lsl #4
    stp  x9, x10, [x11]
    add  x23, x23, #1
6:  add  x24, x24, #16
    b    4b
7:  ldr  x9, [sp, #104]
    cbz  x9, 9f
    str  xzr, [sp, #104]
    b    3b
9:  mov  x0, x23
    LEAVE 32

// ---------------------------------------------------------------------------
// self-tests 184-187, called from test.s

.macro TM_AND
    cset x9, eq
    and  x20, x20, x9
.endm

.macro TM_REPORT name
    mov  w1, w20
    ADRL x0, \name
    bl   _t_report
    add  x19, x19, x0
.endm

// x0 = 1 if the string at x0 is the one at \lbl (x0 kept in x9)
.macro TM_IS lbl
    ADRL x1, \lbl
    bl   Lsame
    cmp  x0, #1
.endm

.globl _term_selftest
_term_selftest:
    ENTER 16                              // [96] x25
    str  x25, [sp, #96]
    mov  x19, #0
    mov  x0, #1
    mov  x1, #(TH_SIZE & 0xffff)
    bl   _calloc
    mov  x21, x0
    mov  x0, #1
    mov  x1, #4096
    bl   _calloc
    mov  x22, x0
    mov  x9, #-1
    str  x9, [x21, #TH_POS]

    // 184. ↑ walks back, stays at the oldest; ↓ comes forward to what was being typed;
    //      empty lines and repeats aren't added
    mov  x0, x21
    ADRL x1, Lt_one
    mov  x2, #1
    bl   _th_add
    mov  x0, x21
    ADRL x1, Lt_two
    mov  x2, #1
    bl   _th_add
    mov  x0, x21
    ADRL x1, Lt_two                       // a repeat
    mov  x2, #1
    bl   _th_add
    mov  x0, x21
    ADRL x1, Lt_empty
    mov  x2, #1
    bl   _th_add
    mov  x0, x21
    ADRL x1, Lt_three
    mov  x2, #0                           // typed in a private room: not to keep
    bl   _th_add
    ldr  x9, [x21, #TH_COUNT]
    cmp  x9, #3
    cset x20, eq
    mov  x0, x21
    ADRL x1, Lt_draft
    bl   _th_prev
    TM_IS Lt_three
    TM_AND
    mov  x0, x21
    mov  x1, #0
    bl   _th_prev
    TM_IS Lt_two
    TM_AND
    mov  x0, x21
    mov  x1, #0
    bl   _th_prev
    TM_IS Lt_one
    TM_AND
    mov  x0, x21                          // the oldest: stays
    mov  x1, #0
    bl   _th_prev
    TM_IS Lt_one
    TM_AND
    mov  x0, x21
    bl   _th_next
    TM_IS Lt_two
    TM_AND
    mov  x0, x21
    bl   _th_next
    TM_IS Lt_three
    TM_AND
    mov  x0, x21
    bl   _th_next
    TM_IS Lt_draft
    TM_AND
    mov  x0, x21
    bl   _th_next
    cmp  x0, #0
    TM_AND
    TM_REPORT Ln_tm184

    // 185. what's kept across launches: only lines that may be, oldest first, and back
    mov  x0, x21
    mov  x1, x22
    mov  x2, #4096
    bl   _th_pack
    mov  x0, x22
    TM_IS Lt_packed
    cset x20, eq
    mov  x0, x21                          // a fresh history, from it
    mov  x1, #(TH_SIZE & 0xffff)
    bl   Lzero
    mov  x9, #-1
    str  x9, [x21, #TH_POS]
    mov  x0, x21
    mov  x1, x22
    bl   _th_unpack
    ldr  x9, [x21, #TH_COUNT]
    cmp  x9, #2
    TM_AND
    mov  x0, x21
    mov  x1, #0
    bl   _th_entry
    TM_IS Lt_two
    TM_AND
    mov  x0, x21                          // and nothing goes past what fits
    mov  x1, x22
    mov  x2, #10
    bl   _th_pack
    cmp  x0, #0
    TM_AND
    TM_REPORT Ln_tm185

    // 186. the last 100: the 101st line pushes out the first; a long line is cut, not
    //      inside a character
    mov  x0, x21
    mov  x1, #(TH_SIZE & 0xffff)
    bl   Lzero
    mov  x25, #0
1:  strb wzr, [x22, #3]                   // "nnn" from the counter
    mov  x9, #100
    udiv x10, x25, x9
    msub x11, x10, x9, x25
    add  w10, w10, #'0'
    strb w10, [x22]
    mov  x9, #10
    udiv x10, x11, x9
    msub x11, x10, x9, x11
    add  w10, w10, #'0'
    strb w10, [x22, #1]
    add  w11, w11, #'0'
    strb w11, [x22, #2]
    mov  x0, x21
    mov  x1, x22
    mov  x2, #1
    bl   _th_add
    add  x25, x25, #1
    cmp  x25, #101
    b.lo 1b
    ldr  x9, [x21, #TH_COUNT]
    cmp  x9, #TH_N
    cset x20, eq
    mov  x0, x21
    mov  x1, #99
    bl   _th_entry
    TM_IS Lt_001
    TM_AND
    mov  x25, #0                          // 300 bytes: a, then cups
    mov  w9, #'a'
    strb w9, [x22]
    mov  x25, #1
2:  mov  w9, #0xe2
    strb w9, [x22, x25]
    add  x25, x25, #1
    mov  w9, #0x98
    strb w9, [x22, x25]
    add  x25, x25, #1
    mov  w9, #0x95
    strb w9, [x22, x25]
    add  x25, x25, #1
    cmp  x25, #298
    b.lo 2b
    strb wzr, [x22, x25]
    mov  x0, x21
    mov  x1, x22
    mov  x2, #1
    bl   _th_add
    mov  x0, x21
    mov  x1, #0
    bl   _th_entry
    bl   Lcut
    cmp  x0, #253                         // 1 + 84 x 3: the last whole character
    TM_AND
    TM_REPORT Ln_tm186

    // 187. suggestions: those that start with it first, then those that have it, ignoring
    //      case, each once, as many as asked for
    ADRL x0, Lt_words
    ADRL x1, Lt_bat
    mov  x2, x22
    mov  x3, #8
    bl   _sg_match
    cmp  x0, #2
    cset x20, eq
    ldr  x0, [x22]
    TM_IS Lt_w_batteries
    TM_AND
    ldr  x0, [x22, #16]
    TM_IS Lt_w_low
    TM_AND
    ldr  x9, [x22, #8]                    // its kind comes along
    cmp  x9, #2
    TM_AND
    ADRL x0, Lt_words                     // the same text twice: once
    ADRL x1, Lt_bit
    mov  x2, x22
    mov  x3, #8
    bl   _sg_match
    cmp  x0, #1
    TM_AND
    ADRL x0, Lt_words
    ADRL x1, Lt_bat
    mov  x2, x22
    mov  x3, #1
    bl   _sg_match
    cmp  x0, #1
    TM_AND
    ADRL x0, Lt_words
    ADRL x1, Lt_empty
    mov  x2, x22
    mov  x3, #8
    bl   _sg_match
    cmp  x0, #0
    TM_AND
    TM_REPORT Ln_tm187

    mov  x0, x21
    bl   _free
    mov  x0, x22
    bl   _free
    ldr  x25, [sp, #96]
    mov  x0, x19
    LEAVE 16

// void Lzero(p, n) (leaf)
Lzero:
    mov  x9, #0
1:  cmp  x9, x1
    b.hs 2f
    strb wzr, [x0, x9]
    add  x9, x9, #1
    b    1b
2:  ret

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lt_words:
    .quad Lt_w_low, 2
    .quad Lt_w_bitchat, 2
    .quad Lt_w_rules, 0
    .quad Lt_w_batteries, 2
    .quad Lt_w_bitchat2, 2                // the same text again: listed once
    .quad 0, 0

.section __TEXT,__cstring,cstring_literals
Lt_one:         .asciz "kitchen lights off"
Lt_two:         .asciz "batteries"
Lt_three:       .asciz "hello from a private room"
Lt_draft:       .asciz "half-typ"
Lt_empty:       .asciz ""
Lt_packed:      .asciz "kitchen lights off\nbatteries\n"
Lt_001:         .asciz "001"
Lt_bat:         .asciz "BAT"
Lt_bit:         .asciz "bit"
Lt_w_low:       .asciz "low batteries"
Lt_w_bitchat:   .asciz "bitchat"
Lt_w_bitchat2:  .asciz "bitchat"
Lt_w_rules:     .asciz "rules"
Lt_w_batteries: .asciz "batteries"
Ln_tm184:       .asciz "184 typing: up and down walk the history, back to what was being typed"
Ln_tm185:       .asciz "185 typing: only lines that may be kept are saved, oldest first"
Ln_tm186:       .asciz "186 typing: the last 100 lines; a long one cut between characters"
Ln_tm187:       .asciz "187 typing: suggestions start-with first, then contain, each once"
