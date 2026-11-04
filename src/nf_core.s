// nf_core.s — Ninefold's rules, pure (no globals, no system calls): the word table, the seed
// that becomes a puzzle, what a typed word is, points and the commitments claims carry.
// The same seed gives the same puzzle on every Mac and iPhone. tools/ninefold/nf.py is the
// Python copy; tools/qemu/run.sh runs the self-tests (196-199) and `run.sh nfdiff` checks this
// file against nf.py seed by seed.
.include "macros.inc"
.include "nf_defs.inc"

.macro NFK reg, v                         // a 64-bit constant
    movz \reg, #((\v) & 0xffff)
    movk \reg, #(((\v) >> 16) & 0xffff), lsl #16
    movk \reg, #(((\v) >> 32) & 0xffff), lsl #32
    movk \reg, #(((\v) >> 48) & 0xffff), lsl #48
.endm

.text
.p2align 2

// long _nf_puzzle(uint64 seed, puzzle *p) -> 0, or -1 if no seed tried gives one
//   1. a nine-letter answer, picked by the seed, with no other nine-letter answer of the
//      same letters (else the next pick)
//   2. a centre letter, picked among those that leave 15-60 answers; a puzzle with more
//      than 250 words in all is skipped (an index is one byte)
//   3. the other eight letters shuffled (Fisher-Yates); the centre goes in the middle
//   Family words never count towards the answers here, so the filter can't change a puzzle.
.globl _nf_puzzle
_nf_puzzle:
    ENTER 320                             // [96] letter counts  [128] u32 per[26]
    mov  x19, x1                          // [240] candidates  [272] the word  [280] nines
    mov  x20, x0                          // [288] centre (0-25)  [296] candidates  [304] rest
    mov  x21, #0
    bl   Lnf_tab
    mov  x22, x0
    mov  x23, x1
    mov  x24, #0                          // how many nine-letter answers
    mov  x12, #0
Lnp_n:
    cmp  x24, x23
    b.hs Lnp_n_done
    mov  x9, #NF_REC
    madd x10, x24, x9, x22
    ldrb w11, [x10, #8]
    cbz  w11, Lnp_n_next
    ldrb w11, [x10, #9]
    and  w11, w11, #7                  // an answer, not a family word: 1
    cmp  w11, #NFF_ANSWER
    b.ne Lnp_n_next
    add  x12, x12, #1
Lnp_n_next:
    add  x24, x24, #1
    b    Lnp_n
Lnp_n_done:
    str  x12, [sp, #280]
    cbz  x12, Lnp_fail

Lnp_try:
    add  x21, x21, #1
    cmp  x21, #NF_TRIES
    b.hi Lnp_fail
    mov  x0, x20
    bl   Lnf_mix
    mov  x20, x0
    ldr  x9, [sp, #280]
    udiv x10, x1, x9
    msub x10, x10, x9, x1                 // the k-th nine-letter answer
    mov  x24, #0
Lnp_walk:
    mov  x9, #NF_REC
    madd x11, x24, x9, x22
    ldrb w12, [x11, #8]
    cbz  w12, Lnp_walk_next
    ldrb w12, [x11, #9]
    and  w12, w12, #7                  // an answer, not a family word: 1
    cmp  w12, #NFF_ANSWER
    b.ne Lnp_walk_next
    cbz  x10, Lnp_got
    sub  x10, x10, #1
Lnp_walk_next:
    add  x24, x24, #1
    b    Lnp_walk
Lnp_got:
    str  x11, [sp, #272]
    mov  x0, x11
    mov  x1, #9
    add  x2, sp, #96
    bl   Lnf_counts

    mov  x24, #0                          // another nine-letter answer, same letters?
Lnp_ana:
    cmp  x24, x23
    b.hs Lnp_ana_done
    mov  x9, #NF_REC
    madd x0, x24, x9, x22
    ldrb w12, [x0, #8]
    cbz  w12, Lnp_ana_next
    ldrb w12, [x0, #9]
    and  w12, w12, #7                  // an answer, not a family word: 1
    cmp  w12, #NFF_ANSWER
    b.ne Lnp_ana_next
    ldr  x9, [sp, #272]
    cmp  x0, x9
    b.eq Lnp_ana_next
    mov  x1, #9
    add  x2, sp, #96
    bl   Lnf_fits
    cbnz x3, Lnp_try
Lnp_ana_next:
    add  x24, x24, #1
    b    Lnp_ana
Lnp_ana_done:

    add  x9, sp, #128                     // answers each centre letter would leave
    mov  x10, #0
1:  str  xzr, [x9, x10]
    add  x10, x10, #8
    cmp  x10, #104
    b.lo 1b
    mov  x24, #0
Lnp_per:
    cmp  x24, x23
    b.hs Lnp_per_done
    mov  x9, #NF_REC
    madd x0, x24, x9, x22
    ldrb w12, [x0, #9]
    and  w12, w12, #7                  // an answer, not a family word: 1
    cmp  w12, #NFF_ANSWER
    b.ne Lnp_per_next
    bl   Lnf_len
    add  x2, sp, #96
    bl   Lnf_fits
    cbz  x3, Lnp_per_next
    mov  x9, #0
    mov  x13, #0                          // letters counted already
3:  cmp  x9, x1
    b.hs Lnp_per_next
    ldrb w10, [x0, x9]
    sub  w10, w10, #'a'
    lsr  x11, x13, x10
    tbnz x11, #0, 4f
    mov  x11, #1
    lsl  x11, x11, x10
    orr  x13, x13, x11
    add  x12, sp, #128
    ldr  w11, [x12, x10, lsl #2]
    add  w11, w11, #1
    str  w11, [x12, x10, lsl #2]
4:  add  x9, x9, #1
    b    3b
Lnp_per_next:
    add  x24, x24, #1
    b    Lnp_per
Lnp_per_done:

    mov  x9, #0                           // the centre letters that work
    mov  x10, #0
Lnp_c:
    cmp  x9, #26
    b.hs Lnp_c_done
    add  x11, sp, #96
    ldrb w12, [x11, x9]
    cbz  w12, Lnp_c_next
    add  x11, sp, #128
    ldr  w12, [x11, x9, lsl #2]
    cmp  w12, #NF_MINANS
    b.lo Lnp_c_next
    cmp  w12, #NF_MAXANS
    b.hi Lnp_c_next
    add  x11, sp, #240
    strb w9, [x11, x10]
    add  x10, x10, #1
Lnp_c_next:
    add  x9, x9, #1
    b    Lnp_c
Lnp_c_done:
    cbz  x10, Lnp_try
    str  x10, [sp, #296]
    mov  x0, x20
    bl   Lnf_mix
    mov  x20, x0
    ldr  x9, [sp, #296]
    udiv x10, x1, x9
    msub x10, x10, x9, x1
    add  x11, sp, #240
    ldrb w12, [x11, x10]
    str  x12, [sp, #288]

    str  xzr, [x19, #NP_N]                // the puzzle's words: centre letter, these tiles
    str  xzr, [x19, #NP_ANS]
    mov  x24, #0
Lnp_f:
    cmp  x24, x23
    b.hs Lnp_f_done
    mov  x9, #NF_REC
    madd x0, x24, x9, x22
    bl   Lnf_len
    ldr  x12, [sp, #288]
    add  w12, w12, #'a'
    mov  x9, #0
5:  cmp  x9, x1
    b.hs Lnp_f_next
    ldrb w10, [x0, x9]
    cmp  w10, w12
    b.eq 6f
    add  x9, x9, #1
    b    5b
6:  add  x2, sp, #96
    bl   Lnf_fits
    cbz  x3, Lnp_f_next
    ldr  x9, [x19, #NP_N]
    cmp  x9, #NF_MAXW
    b.hs Lnp_try                          // too many words for one-byte indexes
    add  x10, x19, #NP_IDX
    strh w24, [x10, x9, lsl #1]
    add  x9, x9, #1
    str  x9, [x19, #NP_N]
    ldrb w10, [x0, #9]
    and  w10, w10, #7                  // an answer, not a family word: 1
    cmp  w10, #NFF_ANSWER
    b.ne Lnp_f_next
    ldr  x9, [x19, #NP_ANS]
    add  x9, x9, #1
    str  x9, [x19, #NP_ANS]
Lnp_f_next:
    add  x24, x24, #1
    b    Lnp_f
Lnp_f_done:

    ldr  x0, [sp, #272]                   // the other eight letters, in the word's order
    ldr  x12, [sp, #288]
    add  w12, w12, #'a'
    add  x14, sp, #304
    mov  x9, #0
    mov  x10, #0
    mov  x13, #0
7:  cmp  x9, #9
    b.hs 8f
    ldrb w11, [x0, x9]
    cbnz x13, 71f
    cmp  w11, w12
    b.ne 71f
    mov  x13, #1                          // the first copy of the centre letter
    b    72f
71: strb w11, [x14, x10]
    add  x10, x10, #1
72: add  x9, x9, #1
    b    7b
8:  mov  x24, #7                          // shuffled
Lnp_sh:
    mov  x0, x20
    bl   Lnf_mix
    mov  x20, x0
    add  x9, x24, #1
    udiv x10, x1, x9
    msub x10, x10, x9, x1
    add  x14, sp, #304
    ldrb w11, [x14, x24]
    ldrb w12, [x14, x10]
    strb w12, [x14, x24]
    strb w11, [x14, x10]
    subs x24, x24, #1
    b.ne Lnp_sh
    add  x14, sp, #304
    ldr  w9, [x14]
    str  w9, [x19, #NP_TILES]
    ldr  w9, [x14, #4]
    stur w9, [x19, #(NP_TILES + 5)]
    ldr  x12, [sp, #288]
    add  w12, w12, #'a'
    strb w12, [x19, #(NP_TILES + 4)]
    strb w12, [x19, #NP_CENTRE]
    ldr  x0, [sp, #272]
    ldr  x9, [x0]
    stur x9, [x19, #NP_WORD]
    ldrb w9, [x0, #8]
    strb w9, [x19, #(NP_WORD + 8)]
    strb wzr, [x19, #(NP_WORD + 9)]
    str  wzr, [x19, #(NP_WORD + 10)]       // and the padding, so two puzzles compare equal
    str  x21, [x19, #NP_TRIES]
    mov  x0, #0
    LEAVE 320
Lnp_fail:
    mov  x0, #-1
    LEAVE 320

// long _nf_find(const puzzle *p, const char *text, long len) -> x0 the word's index in the
//   puzzle and x1 its flags (NFF_*), or x0 NF_LENGTH (not 4-9 letters), NF_TILES (a letter
//   that isn't a-z or isn't on the tiles, or used too often), NF_NOCENTRE, NF_NOTWORD.
//   Capitals count as small letters.
.globl _nf_find
_nf_find:
    ENTER 64                              // [96] the word, zero-padded  [112] tile counts
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x1, #0
    sub  x9, x21, #4
    cmp  x9, #5
    b.hi Lnd_len
    stp  xzr, xzr, [sp, #96]
    mov  x9, #0
1:  cmp  x9, x21
    b.hs 2f
    ldrb w10, [x20, x9]
    orr  w10, w10, #0x20
    sub  w11, w10, #'a'
    cmp  w11, #25
    b.hi Lnd_tiles
    add  x11, sp, #96
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    1b
2:  ldrb w12, [x19, #NP_CENTRE]
    mov  x9, #0
3:  cmp  x9, x21
    b.hs Lnd_centre
    add  x11, sp, #96
    ldrb w10, [x11, x9]
    cmp  w10, w12
    b.eq 4f
    add  x9, x9, #1
    b    3b
4:  add  x0, x19, #NP_TILES
    mov  x1, #9
    add  x2, sp, #112
    bl   Lnf_counts
    add  x0, sp, #96
    mov  x1, x21
    add  x2, sp, #112
    bl   Lnf_fits
    mov  x1, #0
    cbz  x3, Lnd_tiles
    bl   Lnf_tab
    mov  x22, x0
    mov  x23, #0
5:  ldr  x9, [x19, #NP_N]
    cmp  x23, x9
    b.hs Lnd_not
    add  x10, x19, #NP_IDX
    ldrh w11, [x10, x23, lsl #1]
    mov  x12, #NF_REC
    madd x13, x11, x12, x22
    ldr  x9, [x13]
    ldr  x10, [sp, #96]
    cmp  x9, x10
    b.ne 6f
    ldrb w9, [x13, #8]
    ldrb w10, [sp, #104]
    cmp  w9, w10
    b.ne 6f
    mov  x0, x23
    ldrb w1, [x13, #9]
    LEAVE 64
6:  add  x23, x23, #1
    b    5b
Lnd_len:
    mov  x0, #NF_LENGTH
    LEAVE 64
Lnd_tiles:
    mov  x1, #0
    mov  x0, #NF_TILES
    LEAVE 64
Lnd_centre:
    mov  x1, #0
    mov  x0, #NF_NOCENTRE
    LEAVE 64
Lnd_not:
    mov  x1, #0
    mov  x0, #NF_NOTWORD
    LEAVE 64

// const char *_nf_word(const puzzle *p, long i) -> x0 the word's letters (not NUL-terminated
//   when 9 long), x1 its length, x2 its flags
.globl _nf_word
_nf_word:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   Lnf_tab
    add  x9, x19, #NP_IDX
    ldrh w10, [x9, x20, lsl #1]
    mov  x11, #NF_REC
    madd x0, x10, x11, x0
    bl   Lnf_len
    ldrb w2, [x0, #9]
    LEAVE 0

// long _nf_points(long length) -> 1 for four letters, one more for each letter after; the
//   nine-letter word is worth 10 (leaf)
.globl _nf_points
_nf_points:
    cmp  x0, #9
    mov  x9, #10
    sub  x0, x0, #3
    csel x0, x9, x0, eq
    ret

// void _nf_commit(const uint8 salt[16], uint64 player, long round, long index, uint8 out[16])
//   SHA-256(salt | player id (8, little-endian) | round | index), first 16 bytes. The id is in
//   it so nobody can copy another player's claims and reveal them with that player's salt.
.globl _nf_commit
_nf_commit:
    ENTER 64                              // [96] message (26)  [128] digest
    mov  x19, x4
    ldp  x9, x10, [x0]
    stp  x9, x10, [sp, #96]
    str  x1, [sp, #112]
    strb w2, [sp, #120]
    strb w3, [sp, #121]
    add  x0, sp, #96
    mov  x1, #26
    add  x2, sp, #128
    bl   _bc_sha256
    ldp  x9, x10, [sp, #128]
    stp  x9, x10, [x19]
    LEAVE 64

// void _nf_hash(uint8 out[8]) — the word lists' fingerprint (SHA-256 of the table, first 8
//   bytes). START carries it: devices with other lists don't play together.
.globl _nf_hash
_nf_hash:
    ENTER 32
    mov  x19, x0
    ADRL x0, Lnf_bin
    ADRL x1, Lnf_bin_end
    sub  x1, x1, x0
    add  x2, sp, #96
    bl   _bc_sha256
    ldr  x9, [sp, #96]
    str  x9, [x19]
    LEAVE 32

// long _nf_count(void) -> how many words the table has
.globl _nf_count
_nf_count:
    ENTER 0
    bl   Lnf_tab
    mov  x0, x1
    LEAVE 0

// ---------------------------------------------------------------------------
// leaves (no stack; x9-x14)

// Lnf_tab -> x0 the first record, x1 how many
Lnf_tab:
    ADRL x0, Lnf_bin
    ldr  w1, [x0, #8]
    add  x0, x0, #NF_HDR
    ret

// Lnf_mix(x0 state) -> x0 the next state, x1 a random value (splitmix64)
Lnf_mix:
    NFK  x9, 0x9E3779B97F4A7C15
    add  x0, x0, x9
    eor  x1, x0, x0, lsr #30
    NFK  x9, 0xBF58476D1CE4E5B9
    mul  x1, x1, x9
    eor  x1, x1, x1, lsr #27
    NFK  x9, 0x94D049BB133111EB
    mul  x1, x1, x9
    eor  x1, x1, x1, lsr #31
    ret

// Lnf_len(x0 record) -> x1 its length; x0 kept
Lnf_len:
    mov  x1, #0
1:  cmp  x1, #9
    b.eq 2f
    ldrb w9, [x0, x1]
    cbz  w9, 2f
    add  x1, x1, #1
    b    1b
2:  ret

// Lnf_counts(x0 letters, x1 length, x2 out[32]) — how many of each letter
Lnf_counts:
    stp  xzr, xzr, [x2]
    stp  xzr, xzr, [x2, #16]
    mov  x9, #0
1:  cmp  x9, x1
    b.hs 2f
    ldrb w10, [x0, x9]
    sub  w10, w10, #'a'
    ldrb w11, [x2, x10]
    add  w11, w11, #1
    strb w11, [x2, x10]
    add  x9, x9, #1
    b    1b
2:  ret

// Lnf_fits(x0 letters a-z, x1 length, x2 counts) -> x3 1 if the letters can be made from
//   the counts; x0-x2 kept
Lnf_fits:
    mov  x9, #0
1:  cmp  x9, x1
    b.hs 8f
    ldrb w10, [x0, x9]
    mov  x11, #0
    mov  x12, #0
2:  ldrb w13, [x0, x11]                   // copies of this letter so far, itself included
    cmp  w13, w10
    cinc x12, x12, eq
    add  x11, x11, #1
    cmp  x11, x9
    b.ls 2b
    sub  w10, w10, #'a'
    ldrb w13, [x2, x10]
    cmp  x12, x13
    b.hi 9f
    add  x9, x9, #1
    b    1b
8:  mov  x3, #1
    ret
9:  mov  x3, #0
    ret

// ---------------------------------------------------------------------------
// self-tests 196-199, called from test.s

.globl _nf_core_selftest
_nf_core_selftest:
    ENTER 1216                            // [96] puzzle  [656] another  [1216] scratch (96)
    mov  x19, #0

    // 196. the table: its header, 10 bytes a word, in order, letters only, flags known
    mov  x20, #1
    ADRL x0, Lnf_bin
    ldr  x9, [x0]
    NFK  x10, 0x444C4F46454E494E          // "NINEFOLD"
    cmp  x9, x10
    cset x9, eq
    and  x20, x20, x9
    ADRL x1, Lnf_bin_end
    sub  x1, x1, x0
    ldr  w9, [x0, #8]
    mov  x10, #NF_REC
    madd x9, x9, x10, x10
    add  x9, x9, #(NF_HDR - NF_REC)
    cmp  x1, x9
    cset x9, eq
    and  x20, x20, x9
    bl   Lnf_tab
    cmp  x1, #1000
    cset x9, hi
    and  x20, x20, x9
    mov  x21, x0
    mov  x22, #0
Lnt_tab:
    add  x9, x22, #1
    cmp  x9, x1
    b.hs Lnt_tab_last
    mov  x9, #NF_REC
    madd x10, x22, x9, x21
    add  x11, x10, #NF_REC
    mov  x12, #0                          // compare with the next one: must be later
1:  ldrb w13, [x10, x12]
    ldrb w14, [x11, x12]
    cmp  w13, w14
    b.lo 2f
    b.hi Lnt_tab_bad
    add  x12, x12, #1
    cmp  x12, #9
    b.lo 1b
    b    Lnt_tab_bad                      // the same word twice
2:  ldrb w13, [x10, #9]
    tst  w13, #(NFF_ANSWER | NFF_EXTRA)
    b.eq Lnt_tab_bad
    tst  w13, #0xF8
    b.ne Lnt_tab_bad
    ldrb w13, [x10, #3]                   // four letters at least
    sub  w13, w13, #'a'
    cmp  w13, #25
    b.hi Lnt_tab_bad
    add  x22, x22, #1
    b    Lnt_tab
Lnt_tab_bad:
    mov  x20, #0
Lnt_tab_last:
    mov  w1, w20
    ADRL x0, Ln_nf196
    bl   _t_report
    add  x19, x19, x0

    // 197. a puzzle: the tiles are the word's letters, centre in the middle, 15-60 answers;
    //      every word uses the centre and fits; the same seed gives the same puzzle again
    mov  x20, #1
    NFK  x0, 0x0123456789ABCDEF
    add  x1, sp, #96
    bl   _nf_puzzle
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    NFK  x0, 0x0123456789ABCDEF
    add  x1, sp, #656
    bl   _nf_puzzle
    add  x21, sp, #96
    add  x22, sp, #656
    ldr  x12, [x21, #NP_N]                // the header and the words in use
    lsl  x12, x12, #1
    add  x12, x12, #NP_IDX
    mov  x9, #0
1:  ldrb w10, [x21, x9]
    ldrb w11, [x22, x9]
    cmp  w10, w11
    b.ne 2f
    add  x9, x9, #1
    cmp  x9, x12
    b.lo 1b
    b    3f
2:  mov  x20, #0
3:  add  x0, x21, #NP_TILES               // tiles and word: the same letters
    mov  x1, #9
    add  x2, sp, #1216
    bl   Lnf_counts
    add  x0, x21, #NP_WORD
    mov  x1, #9
    add  x2, sp, #1216
    bl   Lnf_fits
    and  x20, x20, x3
    ldrb w9, [x21, #(NP_TILES + 4)]
    ldrb w10, [x21, #NP_CENTRE]
    cmp  w9, w10
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [x21, #NP_ANS]
    cmp  x9, #NF_MINANS
    cset x10, hs
    and  x20, x20, x10
    cmp  x9, #NF_MAXANS
    cset x10, ls
    and  x20, x20, x10
    ldr  x10, [x21, #NP_N]
    cmp  x10, x9
    cset x10, hs
    and  x20, x20, x10
    mov  x22, #0                          // each word: uses the centre, fits the tiles
Lnt_w:
    ldr  x9, [x21, #NP_N]
    cmp  x22, x9
    b.hs Lnt_w_done
    mov  x0, x21
    mov  x1, x22
    bl   _nf_word
    mov  x23, x0
    mov  x24, x1
    mov  x0, x21
    mov  x1, x23
    mov  x2, x24
    bl   _nf_find                         // ... and is found as itself
    cmp  x0, x22
    cset x9, eq
    and  x20, x20, x9
    add  x22, x22, #1
    b    Lnt_w
Lnt_w_done:
    mov  w1, w20
    ADRL x0, Ln_nf197
    bl   _t_report
    add  x19, x19, x0

    // 198. typed words: the nine-letter word in capitals, too short, too long, no centre
    //      letter, a letter not on the tiles, a tile used twice, not a letter
    mov  x20, #1
    add  x22, sp, #1216
    ldur x9, [x21, #NP_WORD]
    NFK  x10, 0xDFDFDFDFDFDFDFDF          // capitals
    and  x9, x9, x10
    str  x9, [x22]
    ldrb w9, [x21, #(NP_WORD + 8)]
    bic  w9, w9, #0x20
    strb w9, [x22, #8]
    mov  x0, x21
    mov  x1, x22
    mov  x2, #9
    bl   _nf_find
    tbnz x0, #63, 1f
    and  x9, x1, #NFF_ANSWER
    and  x20, x20, x9
    b    2f
1:  mov  x20, #0
2:  mov  x0, x21
    mov  x1, x22
    mov  x2, #3
    bl   _nf_find
    cmp  x0, #NF_LENGTH
    cset x9, eq
    and  x20, x20, x9
    mov  x0, x21
    mov  x1, x22
    mov  x2, #10
    bl   _nf_find
    cmp  x0, #NF_LENGTH
    cset x9, eq
    and  x20, x20, x9
    ldrb w9, [x21, #NP_CENTRE]            // "qqqq" or "zzzz": no centre letter
    mov  w10, #'q'
    cmp  w9, w10
    mov  w11, #'z'
    csel w10, w11, w10, eq
    mov  w11, #0x01010101
    mul  w10, w10, w11
    str  w10, [x22, #16]
    mov  x0, x21
    add  x1, x22, #16
    mov  x2, #4
    bl   _nf_find
    cmp  x0, #NF_NOCENTRE
    cset x9, eq
    and  x20, x20, x9
    ldrb w9, [x21, #NP_CENTRE]            // the centre ten times over: more than the tiles
    mov  w11, #0x01010101
    mul  w9, w9, w11
    str  w9, [x22, #16]
    str  w9, [x22, #20]
    mov  x0, x21
    add  x1, x22, #16
    mov  x2, #8
    bl   _nf_find
    cmp  x0, #NF_TILES
    cset x9, eq
    and  x20, x20, x9
    ldrb w9, [x21, #NP_CENTRE]            // the centre and digits
    mov  w10, #0x3131
    movk w10, #0x3131, lsl #16
    str  w10, [x22, #16]
    strb w9, [x22, #16]
    mov  x0, x21
    add  x1, x22, #16
    mov  x2, #4
    bl   _nf_find
    cmp  x0, #NF_TILES
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_nf198
    bl   _t_report
    add  x19, x19, x0

    // 199. points; a commitment (vector from nf.py); the lists' fingerprint is steady
    mov  x20, #1
    mov  x0, #4
    bl   _nf_points
    cmp  x0, #1
    cset x9, eq
    and  x20, x20, x9
    mov  x0, #8
    bl   _nf_points
    cmp  x0, #5
    cset x9, eq
    and  x20, x20, x9
    mov  x0, #9
    bl   _nf_points
    cmp  x0, #10
    cset x9, eq
    and  x20, x20, x9
    add  x22, sp, #1216
    mov  x9, #0
1:  strb w9, [x22, x9]
    add  x9, x9, #1
    cmp  x9, #16
    b.lo 1b
    mov  x0, x22
    NFK  x1, 0x1122334455667788
    mov  x2, #3
    mov  x3, #17
    add  x4, x22, #32
    bl   _nf_commit
    ldp  x9, x10, [x22, #32]
    ADRL x11, Lnt_commit
    ldp  x12, x13, [x11]
    cmp  x9, x12
    ccmp x10, x13, #0, eq
    cset x9, eq
    and  x20, x20, x9
    add  x0, x22, #64
    bl   _nf_hash
    add  x0, x22, #72
    bl   _nf_hash
    ldr  x9, [x22, #64]
    ldr  x10, [x22, #72]
    cmp  x9, x10
    cset x9, eq
    and  x20, x20, x9
    cmp  x10, #0
    cset x9, ne
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_nf199
    bl   _t_report
    add  x19, x19, x0

    mov  x0, x19
    LEAVE 1216

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lnt_commit:     .byte 0x95,0x6d,0x13,0x36,0x2f,0xcf,0x84,0x0b,0xaa,0xdb,0xb3,0xe1,0xf1,0x5b,0x73,0x1a
.p2align 3
Lnf_bin:
.incbin "nf_words.bin"
Lnf_bin_end:

.section __TEXT,__cstring,cstring_literals
Ln_nf196:       .asciz "196 ninefold: the word table is whole and in order"
Ln_nf197:       .asciz "197 ninefold: a seed makes a sound puzzle, the same each time"
Ln_nf198:       .asciz "198 ninefold: typed words: capitals, length, centre, tiles"
Ln_nf199:       .asciz "199 ninefold: points, commitments, the lists' fingerprint"
