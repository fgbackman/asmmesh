// ch_core.s — the rules of chess, pure (no globals, no system calls): positions on a 0x88
// board, every legal move (castling, en passant, promotion), check, mate, stalemate, the
// fifty-move rule and bare kings, moves read as typed (e4, Nf3, exd5, O-O, e7e8q) and
// written as SAN (Nbd7, exd6, e8=Q+, Qxf7#). Checked by perft: the number of positions a
// few moves deep from standard test positions, against the published counts (self-tests
// 205-209; tools/qemu/run.sh chperft goes deeper).
.include "macros.inc"
.include "ch_defs.inc"

.macro OFF88 reg, label                   // branch if the square is off the board
    tbnz \reg, #7, \label
    tbnz \reg, #3, \label
.endm

.macro CG_ADD rf, rt, rpf                 // _ch_gen: one more move (from, to, promo|flags)
    cmp  x21, #CH_MAXMOVES
    b.hs Lcg_full_\@
    orr  w9, \rpf, \rf
    orr  w9, w9, \rt, lsl #8
    str  w9, [x20, x21, lsl #2]
    add  x21, x21, #1
Lcg_full_\@:
.endm

.macro CP_COPY dst, src                   // copy a position (136 bytes)
    mov  x9, #0
Lcp_\@:
    ldr  x10, [\src, x9]
    str  x10, [\dst, x9]
    add  x9, x9, #8
    cmp  x9, #CP_SIZE
    b.lo Lcp_\@
.endm

.text
.p2align 2

// void _ch_start(pos *p) — the starting position
.globl _ch_start
_ch_start:
    ENTER 0
    mov  x19, x0
    mov  x0, x19
    ADRL x1, Lch_startfen
    bl   _ch_fen_in
    LEAVE 0

// long _ch_attacked(const pos *p, long square, long by) -> 1 if a piece of side `by` (0 white,
//   8 black) attacks that square (leaf)
.globl _ch_attacked
_ch_attacked:
    cbnz x2, 1f
    sub  x10, x1, #15                     // white pawns attack upwards
    OFF88 x10, 3f
    ldrb w11, [x0, x10]
    cmp  w11, #1
    b.eq Lca_yes
3:  sub  x10, x1, #17
    OFF88 x10, 2f
    ldrb w11, [x0, x10]
    cmp  w11, #1
    b.eq Lca_yes
    b    2f
1:  add  x10, x1, #15                     // black pawns downwards
    OFF88 x10, 4f
    ldrb w11, [x0, x10]
    cmp  w11, #9
    b.eq Lca_yes
4:  add  x10, x1, #17
    OFF88 x10, 2f
    ldrb w11, [x0, x10]
    cmp  w11, #9
    b.eq Lca_yes
2:  orr  w12, w2, #2                      // knights
    ADRL x13, Lch_knight
    mov  x14, #0
5:  ldrsb x15, [x13, x14]
    add  x10, x1, x15
    OFF88 x10, 6f
    ldrb w11, [x0, x10]
    cmp  w11, w12
    b.eq Lca_yes
6:  add  x14, x14, #1
    cmp  x14, #8
    b.lo 5b
    orr  w12, w2, #6                      // the king
    ADRL x13, Lch_king
    mov  x14, #0
7:  ldrsb x15, [x13, x14]
    add  x10, x1, x15
    OFF88 x10, 8f
    ldrb w11, [x0, x10]
    cmp  w11, w12
    b.eq Lca_yes
8:  add  x14, x14, #1
    cmp  x14, #8
    b.lo 7b
    orr  w12, w2, #3                      // bishops and queens, on diagonals
    add  w9, w2, #5                       // (w2 is 0 or 8)
    ADRL x13, Lch_diag
    mov  x14, #0
Lca_d:
    ldrsb x15, [x13, x14]
    mov  x10, x1
Lca_d2:
    add  x10, x10, x15
    OFF88 x10, Lca_dn
    ldrb w11, [x0, x10]
    cbz  w11, Lca_d2
    cmp  w11, w12
    b.eq Lca_yes
    cmp  w11, w9
    b.eq Lca_yes
Lca_dn:
    add  x14, x14, #1
    cmp  x14, #4
    b.lo Lca_d
    orr  w12, w2, #4                      // rooks and queens, on ranks and files
    ADRL x13, Lch_orth
    mov  x14, #0
Lca_o:
    ldrsb x15, [x13, x14]
    mov  x10, x1
Lca_o2:
    add  x10, x10, x15
    OFF88 x10, Lca_on
    ldrb w11, [x0, x10]
    cbz  w11, Lca_o2
    cmp  w11, w12
    b.eq Lca_yes
    cmp  w11, w9
    b.eq Lca_yes
Lca_on:
    add  x14, x14, #1
    cmp  x14, #4
    b.lo Lca_o
    mov  x0, #0
    ret
Lca_yes:
    mov  x0, #1
    ret

// long _ch_gen(const pos *p, uint32 out[256]) -> how many: every move by the side to move,
//   before asking whether it leaves its own king in check (castling's squares are checked)
.globl _ch_gen
_ch_gen:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
    ldrb w23, [x19, #CP_SIDE]
    mov  x22, #0
Lcg_sq:
    cmp  x22, #128
    b.hs Lcg_castle
    OFF88 x22, Lcg_next
    ldrb w24, [x19, x22]
    cbz  w24, Lcg_next
    and  w9, w24, #8
    cmp  w9, w23
    b.ne Lcg_next
    and  w24, w24, #7
    cmp  w24, #1
    b.eq Lcg_pawn
    mov  x15, #0                          // knights and kings: one step
    ADRL x13, Lch_knight
    mov  x14, #8
    cmp  w24, #2
    b.eq 1f
    ADRL x13, Lch_king
    cmp  w24, #6
    b.eq 1f
    mov  x15, #1                          // bishops, rooks, queens: rays
    ADRL x13, Lch_diag
    mov  x14, #4
    cmp  w24, #3
    b.eq 1f
    ADRL x13, Lch_orth
    cmp  w24, #4
    b.eq 1f
    ADRL x13, Lch_king                    // the queen: all eight directions
    mov  x14, #8
1:  bl   Lcg_rays
    b    Lcg_next
Lcg_pawn:
    mov  x13, #16
    cbz  w23, 1f
    mov  x13, #-16
1:  add  x10, x22, x13
    OFF88 x10, Lcg_pcap
    ldrb w9, [x19, x10]
    cbnz w9, Lcg_pcap
    mov  w16, #0
    bl   Lcg_pawnadd
    lsr  x11, x22, #4                     // from its first rank: two squares
    mov  x12, #1
    cbz  w23, 2f
    mov  x12, #6
2:  cmp  x11, x12
    b.ne Lcg_pcap
    add  x10, x10, x13
    ldrb w9, [x19, x10]
    cbnz w9, Lcg_pcap
    mov  w16, #(CMF_DOUBLE << 24)
    CG_ADD w22, w10, w16
Lcg_pcap:
    mov  x12, #-1                         // captures, to either side
3:  add  x10, x22, x13
    add  x10, x10, x12
    OFF88 x10, 5f
    ldrb w9, [x19, x10]
    cbz  w9, 4f
    and  w9, w9, #8
    cmp  w9, w23
    b.eq 5f
    mov  w16, #(CMF_CAPTURE << 24)
    bl   Lcg_pawnadd
    b    5f
4:  ldrb w9, [x19, #CP_EP]                // en passant
    cmp  w9, w10
    b.ne 5f
    mov  w16, #((CMF_CAPTURE | CMF_EP) << 24)
    CG_ADD w22, w10, w16
5:  add  x12, x12, #2
    cmp  x12, #1
    b.le 3b
Lcg_next:
    add  x22, x22, #1
    b    Lcg_sq

.macro CG_EMPTY sq, fail
    ldrb w9, [x19, #\sq]
    cbnz w9, \fail
.endm
.macro CG_SAFE sq, by, fail
    mov  x0, x19
    mov  x1, #\sq
    mov  x2, #\by
    bl   _ch_attacked
    cbnz x0, \fail
.endm

Lcg_castle:                               // the king and rook unmoved, between them empty,
    ldrb w24, [x19, #CP_CASTLE]           //   and the king not in, through or into check
    cbnz w23, Lcg_black
    ldrb w9, [x19, #4]
    cmp  w9, #6
    b.ne Lcg_done
    tbz  w24, #0, Lcg_wq
    CG_EMPTY 5, Lcg_wq
    CG_EMPTY 6, Lcg_wq
    ldrb w9, [x19, #7]
    cmp  w9, #4
    b.ne Lcg_wq
    CG_SAFE 4, 8, Lcg_wq
    CG_SAFE 5, 8, Lcg_wq
    CG_SAFE 6, 8, Lcg_wq
    mov  w22, #4
    mov  w10, #6
    mov  w16, #(CMF_CASTLE << 24)
    CG_ADD w22, w10, w16
Lcg_wq:
    tbz  w24, #1, Lcg_done
    CG_EMPTY 3, Lcg_done
    CG_EMPTY 2, Lcg_done
    CG_EMPTY 1, Lcg_done
    ldrb w9, [x19, #0]
    cmp  w9, #4
    b.ne Lcg_done
    CG_SAFE 4, 8, Lcg_done
    CG_SAFE 3, 8, Lcg_done
    CG_SAFE 2, 8, Lcg_done
    mov  w22, #4
    mov  w10, #2
    mov  w16, #(CMF_CASTLE << 24)
    CG_ADD w22, w10, w16
    b    Lcg_done
Lcg_black:
    ldrb w9, [x19, #0x74]
    cmp  w9, #14
    b.ne Lcg_done
    tbz  w24, #2, Lcg_bq
    CG_EMPTY 0x75, Lcg_bq
    CG_EMPTY 0x76, Lcg_bq
    ldrb w9, [x19, #0x77]
    cmp  w9, #12
    b.ne Lcg_bq
    CG_SAFE 0x74, 0, Lcg_bq
    CG_SAFE 0x75, 0, Lcg_bq
    CG_SAFE 0x76, 0, Lcg_bq
    mov  w22, #0x74
    mov  w10, #0x76
    mov  w16, #(CMF_CASTLE << 24)
    CG_ADD w22, w10, w16
Lcg_bq:
    tbz  w24, #3, Lcg_done
    CG_EMPTY 0x73, Lcg_done
    CG_EMPTY 0x72, Lcg_done
    CG_EMPTY 0x71, Lcg_done
    ldrb w9, [x19, #0x70]
    cmp  w9, #12
    b.ne Lcg_done
    CG_SAFE 0x74, 0, Lcg_done
    CG_SAFE 0x73, 0, Lcg_done
    CG_SAFE 0x72, 0, Lcg_done
    mov  w22, #0x74
    mov  w10, #0x72
    mov  w16, #(CMF_CASTLE << 24)
    CG_ADD w22, w10, w16
Lcg_done:
    mov  x0, x21
    LEAVE 16

// Lcg_rays (inside _ch_gen): x13 directions, x14 how many, x15 1 to slide; from x22
Lcg_rays:
    mov  x12, #0
1:  cmp  x12, x14
    b.hs 9f
    ldrsb x11, [x13, x12]
    mov  x10, x22
2:  add  x10, x10, x11
    OFF88 x10, 5f
    ldrb w9, [x19, x10]
    cbz  w9, 3f
    and  w9, w9, #8                       // a piece: theirs is taken, ours stops us
    cmp  w9, w23
    b.eq 5f
    mov  w16, #(CMF_CAPTURE << 24)
    CG_ADD w22, w10, w16
    b    5f
3:  mov  w16, #0
    CG_ADD w22, w10, w16
    cbnz x15, 2b
5:  add  x12, x12, #1
    b    1b
9:  ret

// Lcg_pawnadd (inside _ch_gen): a pawn move to x10 with flags w16; onto the last rank it is
//   four moves, one for each piece it can become
Lcg_pawnadd:
    lsr  x9, x10, #4
    cbz  x9, 1f
    cmp  x9, #7
    b.eq 1f
    CG_ADD w22, w10, w16
    ret
1:  mov  w17, #5                          // queen, rook, bishop, knight
2:  orr  w16, w16, w17, lsl #16
    CG_ADD w22, w10, w16
    and  w16, w16, #0xFF000000
    sub  w17, w17, #1
    cmp  w17, #2
    b.hs 2b
    ret

.macro MK_CLR reg, sq, bits               // _ch_make: a move from or to sq loses those rights
    cmp  \reg, #\sq
    b.ne Lmk_\@
    bic  w16, w16, #\bits
Lmk_\@:
.endm

// void _ch_make(pos *p, uint32 move) — play it (it must be one _ch_gen gave) (leaf)
.globl _ch_make
_ch_make:
    and  w9, w1, #0xFF                    // from
    ubfx w10, w1, #8, #8                  // to
    ubfx w11, w1, #16, #8                 // promotion
    lsr  w12, w1, #24                     // flags
    ldrb w13, [x0, x9]                    // the piece
    ldrb w14, [x0, x10]                   // what it takes
    ldrb w15, [x0, #CP_SIDE]
    strb w13, [x0, x10]
    strb wzr, [x0, x9]
    ldrb w16, [x0, #CP_HALF]              // the fifty-move count
    add  w16, w16, #1
    and  w17, w13, #7
    cmp  w17, #1
    csel w16, wzr, w16, eq
    cmp  w14, #0
    csel w16, wzr, w16, ne
    cmp  w16, #250
    mov  w17, #250
    csel w16, w17, w16, hi
    strb w16, [x0, #CP_HALF]
    tbz  w12, #1, 1f                      // en passant: the pawn taken is beside, not on, to
    sub  w16, w10, #16
    cbz  w15, 11f
    add  w16, w10, #16
11: strb wzr, [x0, x16]
1:  cbz  w11, 2f                          // promotion
    orr  w16, w11, w15
    strb w16, [x0, x10]
2:  tbz  w12, #2, 3f                      // castling: the rook too
    mov  w16, #7
    mov  w17, #5
    cmp  w10, #6
    b.eq 21f
    mov  w16, #0
    mov  w17, #3
    cmp  w10, #2
    b.eq 21f
    mov  w16, #0x77
    mov  w17, #0x75
    cmp  w10, #0x76
    b.eq 21f
    mov  w16, #0x70
    mov  w17, #0x73
21: ldrb w14, [x0, x16]
    strb w14, [x0, x17]
    strb wzr, [x0, x16]
3:  mov  w16, #0xFF                       // en passant square for the reply
    tbz  w12, #3, 4f
    add  w16, w9, w10
    lsr  w16, w16, #1
4:  strb w16, [x0, #CP_EP]
    and  w17, w13, #7                     // the kings' squares
    cmp  w17, #6
    b.ne 5f
    add  x16, x0, #CP_WKING
    cbz  w15, 41f
    add  x16, x0, #CP_BKING
41: strb w10, [x16]
5:  ldrb w16, [x0, #CP_CASTLE]
    MK_CLR w9, 4, 3
    MK_CLR w9, 0x74, 12
    MK_CLR w9, 7, 1
    MK_CLR w9, 0, 2
    MK_CLR w9, 0x77, 4
    MK_CLR w9, 0x70, 8
    MK_CLR w10, 7, 1
    MK_CLR w10, 0, 2
    MK_CLR w10, 0x77, 4
    MK_CLR w10, 0x70, 8
    strb w16, [x0, #CP_CASTLE]
    cbz  w15, 6f                          // black moved: the next move number
    ldrh w17, [x0, #CP_FULL]
    add  w17, w17, #1
    strh w17, [x0, #CP_FULL]
6:  eor  w15, w15, #8
    strb w15, [x0, #CP_SIDE]
    ret

// long _ch_legal(const pos *p, uint32 out[256]) -> how many legal moves
.globl _ch_legal
_ch_legal:
    ENTER 1184                            // [96] every move (1024)  [1120] a copy (136)
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
    mov  x0, x19
    add  x1, sp, #96
    bl   _ch_gen
    mov  x23, x0
    mov  x22, #0
1:  cmp  x22, x23
    b.hs 9f
    add  x24, sp, #1120
    CP_COPY x24, x19
    add  x9, sp, #96
    ldr  w1, [x9, x22, lsl #2]
    mov  x0, x24
    bl   _ch_make
    ldrb w9, [x19, #CP_SIDE]              // the mover's king, attacked by the other side?
    ldrb w1, [x24, #CP_WKING]
    cbz  w9, 2f
    ldrb w1, [x24, #CP_BKING]
2:  eor  w2, w9, #8
    mov  x0, x24
    bl   _ch_attacked
    cbnz x0, 3f
    add  x9, sp, #96
    ldr  w10, [x9, x22, lsl #2]
    str  w10, [x20, x21, lsl #2]
    add  x21, x21, #1
3:  add  x22, x22, #1
    b    1b
9:  mov  x0, x21
    LEAVE 1184

// uint64 _ch_perft(const pos *p, long depth) -> the positions that many moves on
.globl _ch_perft
_ch_perft:
    ENTER 1184                            // [96] the moves  [1120] a copy
    mov  x19, x0
    mov  x20, x1
    mov  x0, #1
    cbz  x20, 9f
    mov  x0, x19
    add  x1, sp, #96
    bl   _ch_legal
    mov  x21, x0
    cmp  x20, #1
    b.eq 9f
    mov  x22, #0                          // the sum
    mov  x23, #0
1:  cmp  x23, x21
    b.hs 2f
    add  x24, sp, #1120
    CP_COPY x24, x19
    add  x9, sp, #96
    ldr  w1, [x9, x23, lsl #2]
    mov  x0, x24
    bl   _ch_make
    mov  x0, x24
    sub  x1, x20, #1
    bl   _ch_perft
    add  x22, x22, x0
    add  x23, x23, #1
    b    1b
2:  mov  x0, x22
9:  LEAVE 1184

// long _ch_status(const pos *p) -> CHS_PLAY, CHS_CHECK, CHS_MATE, CHS_STALE, CHS_FIFTY or
//   CHS_MATERIAL (only kings, or a king and one knight or bishop against a king)
.globl _ch_status
_ch_status:
    ENTER 1040                            // [96] the moves
    mov  x19, x0
    mov  x0, x19
    add  x1, sp, #96
    bl   _ch_legal
    mov  x20, x0
    ldrb w9, [x19, #CP_SIDE]
    ldrb w1, [x19, #CP_WKING]
    cbz  w9, 1f
    ldrb w1, [x19, #CP_BKING]
1:  eor  w2, w9, #8
    mov  x0, x19
    bl   _ch_attacked
    mov  x21, x0                          // in check
    cbnz x20, 2f
    mov  x0, #CHS_STALE
    cbz  x21, 9f
    mov  x0, #CHS_MATE
    b    9f
2:  ldrb w9, [x19, #CP_HALF]
    cmp  w9, #100
    mov  x0, #CHS_FIFTY
    b.hs 9f
    mov  x9, #0                           // what's left besides the kings
    mov  x10, #0                          //   how many
    mov  x11, #0                          //   of them knights or bishops
3:  cmp  x9, #128
    b.hs 5f
    OFF88 x9, 4f
    ldrb w12, [x19, x9]
    and  w12, w12, #7
    cbz  w12, 4f
    cmp  w12, #6
    b.eq 4f
    add  x10, x10, #1
    cmp  w12, #2
    b.eq 31f
    cmp  w12, #3
    b.ne 4f
31: add  x11, x11, #1
4:  add  x9, x9, #1
    b    3b
5:  mov  x0, #CHS_MATERIAL
    cbz  x10, 9f
    cmp  x10, #1
    b.ne 6f
    cbnz x11, 9f
6:  mov  x0, #CHS_PLAY
    cbz  x21, 9f
    mov  x0, #CHS_CHECK
9:  LEAVE 1040

// uint64 _ch_hash(const pos *p) — the position's fingerprint (FNV-1a over the board, the
//   side to move, castling rights and en passant), for repetitions and agreeing (leaf)
.globl _ch_hash
_ch_hash:
    mov  x9, #0x2325
    movk x9, #0x8422, lsl #16
    movk x9, #0x9CE4, lsl #32
    movk x9, #0xCBF2, lsl #48
    mov  x10, #0x01B3
    movk x10, #0x0100, lsl #32
    mov  x11, #0
1:  ldrb w12, [x0, x11]
    eor  x9, x9, x12
    mul  x9, x9, x10
    add  x11, x11, #1
    cmp  x11, #(CP_EP + 1)
    b.lo 1b
    mov  x0, x9
    ret

// long _ch_fen_in(pos *p, const char *fen) -> 0, or -1 if it isn't a position (the board,
//   the side, castling and en passant are needed; the move counts may be left out)
.globl _ch_fen_in
_ch_fen_in:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x9, #0
1:  str  xzr, [x19, x9]
    add  x9, x9, #8
    cmp  x9, #CP_SIZE
    b.lo 1b
    mov  w9, #0xFF
    strb w9, [x19, #CP_EP]
    mov  w9, #1
    strh w9, [x19, #CP_FULL]
    mov  x21, #7                          // rank
    mov  x22, #0                          // file
    mov  x23, #0                          // kings seen: 1 white, 2 black
Lfi_board:
    ldrb w9, [x20], #1
    cbz  w9, Lfi_bad
    cmp  w9, #' '
    b.eq Lfi_side
    cmp  w9, #'/'
    b.ne 2f
    cmp  x22, #8
    b.ne Lfi_bad
    cbz  x21, Lfi_bad
    sub  x21, x21, #1
    mov  x22, #0
    b    Lfi_board
2:  sub  w10, w9, #'1'
    cmp  w10, #7
    b.hi 3f
    add  x22, x22, x10
    add  x22, x22, #1
    cmp  x22, #8
    b.hi Lfi_bad
    b    Lfi_board
3:  ADRL x11, Lch_pieces                  // "PNBRQKpnbrqk"
    mov  x12, #0
4:  ldrb w13, [x11, x12]
    cbz  w13, Lfi_bad
    cmp  w13, w9
    b.eq 5f
    add  x12, x12, #1
    b    4b
5:  cmp  x22, #8
    b.hs Lfi_bad
    add  x13, x12, #1                     // 0-5 white, 6-11 black
    cmp  x12, #6
    b.lo 6f
    add  x13, x12, #3
6:  add  x14, x22, x21, lsl #4
    strb w13, [x19, x14]
    and  w15, w13, #7
    cmp  w15, #6
    b.ne 7f
    tst  w13, #8
    b.ne 61f
    tbnz x23, #0, Lfi_bad                 // one king each
    orr  x23, x23, #1
    strb w14, [x19, #CP_WKING]
    b    7f
61: tbnz x23, #1, Lfi_bad
    orr  x23, x23, #2
    strb w14, [x19, #CP_BKING]
7:  and  w15, w13, #7                     // no pawns on the first or last rank
    cmp  w15, #1
    b.ne 8f
    cbz  x21, Lfi_bad
    cmp  x21, #7
    b.eq Lfi_bad
8:  add  x22, x22, #1
    b    Lfi_board
Lfi_side:
    cbnz x21, Lfi_bad
    cmp  x22, #8
    b.ne Lfi_bad
    cmp  x23, #3
    b.ne Lfi_bad
    ldrb w9, [x20], #1
    mov  w10, #0
    cmp  w9, #'w'
    b.eq 1f
    mov  w10, #8
    cmp  w9, #'b'
    b.ne Lfi_bad
1:  strb w10, [x19, #CP_SIDE]
    ldrb w9, [x20], #1
    cmp  w9, #' '
    b.ne Lfi_bad
    mov  w10, #0                          // castling
2:  ldrb w9, [x20], #1
    cmp  w9, #' '
    b.eq 4f
    cmp  w9, #'-'
    b.eq 2b
    mov  w11, #1
    cmp  w9, #'K'
    b.eq 3f
    mov  w11, #2
    cmp  w9, #'Q'
    b.eq 3f
    mov  w11, #4
    cmp  w9, #'k'
    b.eq 3f
    mov  w11, #8
    cmp  w9, #'q'
    b.ne Lfi_bad
3:  orr  w10, w10, w11
    b    2b
4:  strb w10, [x19, #CP_CASTLE]
    ldrb w9, [x20], #1                    // en passant
    cmp  w9, #'-'
    b.eq 5f
    sub  w9, w9, #'a'
    cmp  w9, #7
    b.hi Lfi_bad
    ldrb w10, [x20], #1
    sub  w10, w10, #'1'
    cmp  w10, #7
    b.hi Lfi_bad
    add  w9, w9, w10, lsl #4
    strb w9, [x19, #CP_EP]
5:  ldrb w9, [x20], #1                    // the counts, if there
    cmp  w9, #' '
    b.ne Lfi_ok
    bl   Lfi_num
    cmp  x0, #250
    mov  x9, #250
    csel x0, x9, x0, hi
    strb w0, [x19, #CP_HALF]
    ldrb w9, [x20]
    cmp  w9, #' '
    b.ne Lfi_ok
    add  x20, x20, #1
    bl   Lfi_num
    cbz  x0, Lfi_ok
    strh w0, [x19, #CP_FULL]
Lfi_ok:
    mov  x0, #0
    LEAVE 0
Lfi_bad:
    mov  x0, #-1
    LEAVE 0

// Lfi_num (inside _ch_fen_in) -> x0 the number at x20 (moved past it), 9999 at most
Lfi_num:
    mov  x0, #0
    mov  x10, #10
1:  ldrb w9, [x20]
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi 2f
    madd x0, x0, x10, x9
    mov  x11, #9999
    cmp  x0, x11
    csel x0, x11, x0, hi
    add  x20, x20, #1
    b    1b
2:  ret

// long _ch_san(const pos *p, uint32 move, char *buf) -> its length: the move in standard
//   notation (Nf3, exd5, Nbd7, R1e2, e8=Q, O-O-O), with + for check and # for mate
.globl _ch_san
_ch_san:
    ENTER 1200                            // [96] the legal moves  [1120] a copy
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, #0
    lsr  w9, w20, #24
    tbz  w9, #2, Lsn_piece
    ubfx w10, w20, #8, #3                 // castling: g or c
    ADRL x1, Lch_oo
    cmp  w10, #6
    b.eq 1f
    ADRL x1, Lch_ooo
1:  ldrb w9, [x1], #1
    cbz  w9, Lsn_check
    strb w9, [x21, x22]
    add  x22, x22, #1
    b    1b
Lsn_piece:
    and  w9, w20, #0xFF
    ldrb w23, [x19, x9]
    and  w23, w23, #7                     // the piece
    cmp  w23, #1
    b.eq Lsn_pawn
    ADRL x10, Lch_letters
    ldrb w10, [x10, x23]
    strb w10, [x21, x22]
    add  x22, x22, #1
    mov  x0, x19                          // another of the same kind able to go there?
    add  x1, sp, #96
    bl   _ch_legal
    mov  x24, x0
    mov  x9, #0
    mov  x13, #0                          // bit 0: one at all, 1: on the same file, 2: rank
1:  cmp  x9, x24
    b.hs 3f
    add  x10, sp, #96
    ldr  w10, [x10, x9, lsl #2]
    add  x9, x9, #1
    cmp  w10, w20
    b.eq 1b
    ubfx w11, w10, #8, #8
    ubfx w12, w20, #8, #8
    cmp  w11, w12
    b.ne 1b
    and  w11, w10, #0xFF
    ldrb w12, [x19, x11]
    and  w12, w12, #7
    cmp  w12, w23
    b.ne 1b
    orr  x13, x13, #1
    and  w12, w20, #0xFF                  // ours
    and  w14, w11, #7
    and  w15, w12, #7
    cmp  w14, w15
    b.ne 2f
    orr  x13, x13, #2
2:  lsr  w14, w11, #4
    lsr  w15, w12, #4
    cmp  w14, w15
    b.ne 1b
    orr  x13, x13, #4
    b    1b
3:  tbz  x13, #0, Lsn_take
    and  w9, w20, #0xFF
    tbnz x13, #1, 4f                      // the file tells them apart
    and  w10, w9, #7
    add  w10, w10, #'a'
    strb w10, [x21, x22]
    add  x22, x22, #1
    b    Lsn_take
4:  tbnz x13, #2, 5f                      // the rank does
    lsr  w10, w9, #4
    add  w10, w10, #'1'
    strb w10, [x21, x22]
    add  x22, x22, #1
    b    Lsn_take
5:  and  w10, w9, #7                      // both are needed
    add  w10, w10, #'a'
    strb w10, [x21, x22]
    add  x22, x22, #1
    lsr  w10, w9, #4
    add  w10, w10, #'1'
    strb w10, [x21, x22]
    add  x22, x22, #1
    b    Lsn_take
Lsn_pawn:
    lsr  w9, w20, #24                     // a pawn's capture: its file first
    tbz  w9, #0, Lsn_to
    and  w10, w20, #7
    add  w10, w10, #'a'
    strb w10, [x21, x22]
    add  x22, x22, #1
Lsn_take:
    lsr  w9, w20, #24
    tbz  w9, #0, Lsn_to
    mov  w10, #'x'
    strb w10, [x21, x22]
    add  x22, x22, #1
Lsn_to:
    ubfx w9, w20, #8, #8
    and  w10, w9, #7
    add  w10, w10, #'a'
    strb w10, [x21, x22]
    add  x22, x22, #1
    lsr  w10, w9, #4
    add  w10, w10, #'1'
    strb w10, [x21, x22]
    add  x22, x22, #1
    ubfx w9, w20, #16, #8                 // =Q
    cbz  w9, Lsn_check
    mov  w10, #'='
    strb w10, [x21, x22]
    add  x22, x22, #1
    ADRL x10, Lch_letters
    ldrb w10, [x10, x9]
    strb w10, [x21, x22]
    add  x22, x22, #1
Lsn_check:
    add  x24, sp, #1120                   // + or #
    CP_COPY x24, x19
    mov  x0, x24
    mov  w1, w20
    bl   _ch_make
    mov  x0, x24
    bl   _ch_status
    mov  w9, #'#'
    cmp  x0, #CHS_MATE
    b.eq 1f
    mov  w9, #'+'
    cmp  x0, #CHS_CHECK
    b.ne 2f
1:  strb w9, [x21, x22]
    add  x22, x22, #1
2:  strb wzr, [x21, x22]
    mov  x0, x22
    LEAVE 1200

// long _ch_parse(const pos *p, const char *text, long len) -> the legal move it means, or
//   CHP_ILLEGAL, CHP_AMBIGUOUS, CHP_UNREADABLE. Takes standard notation (e4, Nf3, exd5,
//   Nbd7, e8=Q, e8Q, O-O, 0-0-0, with or without + # ! ?; n r q k for pieces too) and
//   squares (e2e4, e2-e4, e7e8q). A promotion without its piece becomes a queen.
.globl _ch_parse
_ch_parse:
    ENTER 1136                            // [96] the moves  [1120] the text (16)
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x9, #0                           // the text: spaces before it skipped, 12 at most
1:  cbz  x21, 2f
    ldrb w10, [x20]
    cmp  w10, #' '
    b.ne 2f
    add  x20, x20, #1
    sub  x21, x21, #1
    b    1b
2:  mov  x22, #0
3:  cmp  x22, x21
    b.hs 4f
    ldrb w10, [x20, x22]
    cmp  w10, #' '
    b.eq 4f
    cbz  w10, 4f
    cmp  x22, #12
    b.hs Lps_unread
    add  x11, sp, #1120
    strb w10, [x11, x22]
    add  x22, x22, #1
    b    3b
4:  cbz  x22, Lps_unread                  // + # ! ? at the end don't count
    add  x11, sp, #1120
    sub  x9, x22, #1
    ldrb w10, [x11, x9]
    cmp  w10, #'+'
    b.eq 41f
    cmp  w10, #'#'
    b.eq 41f
    cmp  w10, #'!'
    b.eq 41f
    cmp  w10, #'?'
    b.ne 5f
41: sub  x22, x22, #1
    b    4b
5:  add  x11, sp, #1120
    strb wzr, [x11, x22]
    mov  x0, x19
    add  x1, sp, #96
    bl   _ch_legal
    mov  x23, x0                          // the legal moves, to match against
    // castling
    add  x0, sp, #1120
    bl   Lps_castle
    cbz  x0, Lps_coord
    mov  x13, x0                          // 6 or 2: the king's file
    mov  x10, #-1
    mov  x24, #1
    mov  x9, #0
6:  cmp  x9, x23
    b.hs Lps_one
    add  x11, sp, #96
    ldr  w11, [x11, x9, lsl #2]
    add  x9, x9, #1
    lsr  w12, w11, #24
    tbz  w12, #2, 6b
    ubfx w12, w11, #8, #3
    cmp  x12, x13
    b.ne 6b
    mov  w10, w11
    b    Lps_one
Lps_coord:                                // e2e4, e2-e4, e7e8q
    add  x11, sp, #1120
    mov  x12, x22
    cmp  x12, #5
    b.lo 1f
    ldrb w9, [x11, #2]
    cmp  w9, #'-'
    b.ne 1f
    ldrb w9, [x11, #3]                    // drop the dash
    strb w9, [x11, #2]
    ldrb w9, [x11, #4]
    strb w9, [x11, #3]
    ldrb w9, [x11, #5]
    strb w9, [x11, #4]
    ldrb w9, [x11, #6]
    strb w9, [x11, #5]
    sub  x12, x12, #1
1:  cmp  x12, #4
    b.lo Lps_san
    cmp  x12, #5
    b.hi Lps_san
    mov  x0, x11
    bl   Lps_square
    tbnz x0, #63, Lps_san
    mov  x13, x0
    add  x0, x11, #2
    bl   Lps_square
    tbnz x0, #63, Lps_san
    mov  x14, x0
    mov  x15, #0
    cmp  x12, #5
    b.ne 2f
    ldrb w0, [x11, #4]
    bl   Lps_promo
    cbz  x0, Lps_san
    mov  x15, x0
2:  mov  x24, #0                          // matches
    mov  x10, #-1
    mov  x9, #0
3:  cmp  x9, x23
    b.hs Lps_one
    add  x16, sp, #96
    ldr  w16, [x16, x9, lsl #2]
    add  x9, x9, #1
    and  w17, w16, #0xFF
    cmp  x17, x13
    b.ne 3b
    ubfx w17, w16, #8, #8
    cmp  x17, x14
    b.ne 3b
    ubfx w17, w16, #16, #8
    mov  x0, x15
    cbnz x0, 4f
    cbz  w17, 4f
    mov  x0, #5                           // not said: a queen
4:  cmp  x17, x0
    b.ne 3b
    mov  w10, w16
    add  x24, x24, #1
    b    3b
Lps_san:                                  // standard notation
    add  x11, sp, #1120
    mov  x12, x22
    mov  x13, #1                          // the piece: a pawn unless a letter says
    mov  x14, #0                          // where to read from
    ldrb w0, [x11]
    bl   Lps_piece
    cbz  x0, 1f
    mov  x13, x0
    mov  x14, #1
1:  mov  x15, #0                          // the promotion
    cmp  x12, #3
    b.lo 2f
    sub  x9, x12, #1
    ldrb w0, [x11, x9]
    sub  x9, x12, #2
    ldrb w10, [x11, x9]
    cmp  w10, #'='
    b.eq 11f
    sub  w10, w10, #'1'
    cmp  w10, #7
    b.hi 2f
11: bl   Lps_promo
    cbz  x0, 2f
    mov  x15, x0
    sub  x12, x12, #1
    sub  x9, x12, #1
    ldrb w10, [x11, x9]
    cmp  w10, #'='
    b.ne 2f
    sub  x12, x12, #1
2:  sub  x9, x12, x14                     // the square it goes to: the last two
    cmp  x9, #2
    b.lt Lps_unread
    sub  x9, x12, #2
    add  x0, x11, x9
    bl   Lps_square
    tbnz x0, #63, Lps_unread
    mov  x16, x0                          // to
    mov  x17, #-1                         // from file
    mov  x24, #-1                         //   and rank, if said
    sub  x12, x12, #2
3:  cmp  x14, x12
    b.hs 4f
    ldrb w9, [x11, x14]
    add  x14, x14, #1
    sub  w10, w9, #'a'
    cmp  w10, #7
    b.hi 31f
    mov  x17, x10
    b    3b
31: sub  w10, w9, #'1'
    cmp  w10, #7
    b.hi 32f
    mov  x24, x10
    b    3b
32: cmp  w9, #'x'
    b.eq 3b
    cmp  w9, #':'
    b.eq 3b
    cmp  w9, #'-'
    b.eq 3b
    b    Lps_unread
4:  mov  x12, #0                          // matches
    mov  x10, #-1
    mov  x9, #0
5:  cmp  x9, x23
    b.hs Lps_many
    add  x11, sp, #96
    ldr  w11, [x11, x9, lsl #2]
    add  x9, x9, #1
    ubfx w14, w11, #8, #8                 // to
    cmp  x14, x16
    b.ne 5b
    and  w14, w11, #0xFF                  // from: its piece
    ldrb w0, [x19, x14]
    and  w0, w0, #7
    cmp  x0, x13
    b.ne 5b
    tbnz x17, #63, 51f
    and  w0, w14, #7
    cmp  x0, x17
    b.ne 5b
51: tbnz x24, #63, 52f
    lsr  w0, w14, #4
    cmp  x0, x24
    b.ne 5b
52: ubfx w14, w11, #16, #8                // the promotion
    mov  x0, x15
    cbnz x0, 53f
    cbz  w14, 53f
    mov  x0, #5
53: cmp  x14, x0
    b.ne 5b
    mov  w10, w11
    add  x12, x12, #1
    b    5b
Lps_many:
    mov  x24, x12
Lps_one:                                  // x10 the move found (-1 none), x24 how many
    tbnz x10, #63, Lps_illegal
    cmp  x24, #1
    b.hi Lps_ambiguous
    mov  w0, w10
    LEAVE 1136
Lps_illegal:
    mov  x0, #CHP_ILLEGAL
    LEAVE 1136
Lps_ambiguous:
    mov  x0, #CHP_AMBIGUOUS
    LEAVE 1136
Lps_unread:
    mov  x0, #CHP_UNREADABLE
    LEAVE 1136

// Lps_castle(x0 text) -> 6 for O-O, 2 for O-O-O (also 0-0, o-o), else 0 (leaf)
Lps_castle:
    ldrb w9, [x0]
    orr  w9, w9, #0x20
    cmp  w9, #'o'
    b.eq 1f
    cmp  w9, #'0'
    b.ne 9f
1:  mov  w10, w9                          // that letter, then -, that letter (again)
    ldrb w9, [x0, #1]
    cmp  w9, #'-'
    b.ne 9f
    ldrb w9, [x0, #2]
    orr  w9, w9, #0x20
    cmp  w9, w10
    b.ne 9f
    ldrb w9, [x0, #3]
    cbz  w9, 2f
    cmp  w9, #'-'
    b.ne 9f
    ldrb w9, [x0, #4]
    orr  w9, w9, #0x20
    cmp  w9, w10
    b.ne 9f
    ldrb w9, [x0, #5]
    cbnz w9, 9f
    mov  x0, #2
    ret
2:  mov  x0, #6
    ret
9:  mov  x0, #0
    ret

// Lps_square(x0 two characters) -> the square ("e4" -> 0x34), or -1 (leaf)
Lps_square:
    ldrb w9, [x0]
    sub  w9, w9, #'a'
    cmp  w9, #7
    b.hi 1f
    ldrb w10, [x0, #1]
    sub  w10, w10, #'1'
    cmp  w10, #7
    b.hi 1f
    add  x0, x9, x10, lsl #4
    ret
1:  mov  x0, #-1
    ret

// Lps_promo(w0 letter) -> 5 queen 4 rook 3 bishop 2 knight, either case, or 0 (leaf)
Lps_promo:
    orr  w0, w0, #0x20
    mov  x9, x0
    mov  x0, #5
    cmp  w9, #'q'
    b.eq 1f
    mov  x0, #4
    cmp  w9, #'r'
    b.eq 1f
    mov  x0, #3
    cmp  w9, #'b'
    b.eq 1f
    mov  x0, #2
    cmp  w9, #'n'
    b.eq 1f
    mov  x0, #0
1:  ret

// Lps_piece(w0 first letter) -> 2-6 for N B R Q K (n r q k too: never files), else 0 (leaf)
Lps_piece:
    mov  x9, x0
    mov  x0, #2
    cmp  w9, #'N'
    b.eq 1f
    cmp  w9, #'n'
    b.eq 1f
    mov  x0, #3
    cmp  w9, #'B'                         // a small b is the b file
    b.eq 1f
    mov  x0, #4
    cmp  w9, #'R'
    b.eq 1f
    cmp  w9, #'r'
    b.eq 1f
    mov  x0, #5
    cmp  w9, #'Q'
    b.eq 1f
    cmp  w9, #'q'
    b.eq 1f
    mov  x0, #6
    cmp  w9, #'K'
    b.eq 1f
    cmp  w9, #'k'
    b.eq 1f
    mov  x0, #0
1:  ret

// ---------------------------------------------------------------------------
// self-tests 205-209, called from test.s

.macro CT_PERFT fen, depth, want          // x20 &= (perft(fen, depth) == want)
    add  x0, sp, #96
    ADRL x1, \fen
    bl   _ch_fen_in
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #96
    mov  x1, #\depth
    bl   _ch_perft
    movz x9, #((\want) & 0xffff)
    movk x9, #(((\want) >> 16) & 0xffff), lsl #16
    cmp  x0, x9
    cset x9, eq
    and  x20, x20, x9
.endm

.macro CT_PLAY text                       // x20 &= (the move reads and is played)
    add  x0, sp, #96
    ADRL x1, \text
    mov  x2, #12
    bl   _ch_parse
    tbz  x0, #63, 1f
    mov  x20, #0
    b    2f
1:  mov  w1, w0
    add  x0, sp, #96
    bl   _ch_make
2:
.endm

.macro CT_SAN text, want                  // x20 &= (SAN of what text means == want)
    add  x0, sp, #96
    ADRL x1, \text
    mov  x2, #12
    bl   _ch_parse
    tbnz x0, #63, 1f
    mov  w1, w0
    add  x0, sp, #96
    add  x2, sp, #240
    bl   _ch_san
    add  x0, sp, #240
    ADRL x1, \want
    bl   Lct_same
    and  x20, x20, x0
    b    2f
1:  mov  x20, #0
2:
.endm

.macro CT_PARSE text, want                // x20 &= (_ch_parse(text) == want, a CHP_ code)
    add  x0, sp, #96
    ADRL x1, \text
    mov  x2, #12
    bl   _ch_parse
    cmp  x0, #\want
    cset x9, eq
    and  x20, x20, x9
.endm

.macro CT_FEN fen
    add  x0, sp, #96
    ADRL x1, \fen
    bl   _ch_fen_in
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
.endm

.macro CT_STATUS want
    add  x0, sp, #96
    bl   _ch_status
    cmp  x0, #\want
    cset x9, eq
    and  x20, x20, x9
.endm

.globl _ch_core_selftest
_ch_core_selftest:
    ENTER 256                             // [96] a position (136)  [240] text (32)
    mov  x19, #0

    // 205. perft from the start: 20, 400, 8902
    mov  x20, #1
    CT_PERFT Lct_start, 1, 20
    CT_PERFT Lct_start, 2, 400
    CT_PERFT Lct_start, 3, 8902
    mov  w1, w20
    ADRL x0, Ln_ch205
    bl   _t_report
    add  x19, x19, x0

    // 206. perft from the standard test positions (castling, en passant, promotions, pins)
    mov  x20, #1
    CT_PERFT Lct_kiwi, 1, 48
    CT_PERFT Lct_kiwi, 2, 2039
    CT_PERFT Lct_pos3, 1, 14
    CT_PERFT Lct_pos3, 2, 191
    CT_PERFT Lct_pos3, 3, 2812
    CT_PERFT Lct_pos4, 1, 6
    CT_PERFT Lct_pos4, 2, 264
    CT_PERFT Lct_pos4, 3, 9467
    CT_PERFT Lct_pos5, 1, 44
    CT_PERFT Lct_pos5, 2, 1486
    mov  w1, w20
    ADRL x0, Ln_ch206
    bl   _t_report
    add  x19, x19, x0

    // 207. moves as typed and as written: e4 e5 Nf3 Nc6 Bb5 a6 Bxc6 dxc6 O-O, then a
    //      scholar's mate ends in Qxf7#; bad and illegal ones refused
    mov  x20, #1
    CT_FEN Lct_start
    CT_SAN Lct_t_e4, Lct_s_e4
    CT_PLAY Lct_t_e4
    CT_PLAY Lct_t_e7e5
    CT_SAN Lct_t_nf3, Lct_s_nf3
    CT_PLAY Lct_t_nf3
    CT_PLAY Lct_t_nc6
    CT_PLAY Lct_t_bb5
    CT_PLAY Lct_t_a6
    CT_SAN Lct_t_bxc6, Lct_s_bxc6
    CT_PLAY Lct_t_bxc6
    CT_SAN Lct_t_dxc6, Lct_s_dxc6
    CT_PLAY Lct_t_dxc6
    CT_SAN Lct_t_oo, Lct_s_oo
    CT_PARSE Lct_t_ke2, CHP_ILLEGAL       // the king is on g1 by then, after O-O? not yet
    CT_PARSE Lct_t_junk, CHP_UNREADABLE
    CT_PARSE Lct_t_e5, CHP_ILLEGAL
    CT_FEN Lct_start
    CT_PLAY Lct_t_e4
    CT_PLAY Lct_t_e7e5
    CT_PLAY Lct_t_bc4
    CT_PLAY Lct_t_nc6
    CT_PLAY Lct_t_qh5
    CT_PLAY Lct_t_nf6
    CT_SAN Lct_t_qxf7, Lct_s_qxf7
    CT_PLAY Lct_t_qxf7
    CT_STATUS CHS_MATE
    mov  w1, w20
    ADRL x0, Ln_ch207
    bl   _t_report
    add  x19, x19, x0

    // 208. en passant, promotion, a knight two can reach, castling queenside
    mov  x20, #1
    CT_FEN Lct_ep
    CT_SAN Lct_t_exf6, Lct_s_exf6
    CT_FEN Lct_promo
    CT_SAN Lct_t_e8q, Lct_s_e8q
    CT_SAN Lct_t_e8n, Lct_s_e8n
    CT_SAN Lct_t_e7e8, Lct_s_e8q
    CT_FEN Lct_twon
    CT_PARSE Lct_t_nd2, CHP_AMBIGUOUS
    CT_SAN Lct_t_nbd2, Lct_s_nbd2
    CT_FEN Lct_kiwi
    CT_SAN Lct_t_ooo, Lct_s_ooo
    CT_SAN Lct_t_zero, Lct_s_ooo
    mov  w1, w20
    ADRL x0, Ln_ch208
    bl   _t_report
    add  x19, x19, x0

    // 209. the end: stalemate, bare kings, the fifty-move rule, check; bad positions refused
    mov  x20, #1
    CT_FEN Lct_stale
    CT_STATUS CHS_STALE
    CT_FEN Lct_bare
    CT_STATUS CHS_MATERIAL
    CT_FEN Lct_fifty
    CT_STATUS CHS_FIFTY
    CT_FEN Lct_check
    CT_STATUS CHS_CHECK
    add  x0, sp, #96
    ADRL x1, Lct_badfen
    bl   _ch_fen_in
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #96
    ADRL x1, Lct_twokings
    bl   _ch_fen_in
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_ch209
    bl   _t_report
    add  x19, x19, x0

    mov  x0, x19
    LEAVE 256

// Lct_same(a, b) -> 1 if the strings are equal (leaf)
Lct_same:
    ldrb w9, [x0], #1
    ldrb w10, [x1], #1
    cmp  w9, w10
    b.ne 1f
    cbnz w9, Lct_same
    mov  x0, #1
    ret
1:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
.section __TEXT,__const
Lch_knight:     .byte 33, 31, 18, 14, -33, -31, -18, -14
Lch_king:       .byte 1, 15, 16, 17, -1, -15, -16, -17
Lch_diag:       .byte 15, 17, -15, -17
Lch_orth:       .byte 1, 16, -1, -16

.section __TEXT,__cstring,cstring_literals
Lch_startfen:   .asciz "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
Lch_pieces:     .asciz "PNBRQKpnbrqk"
Lch_letters:    .asciz "  NBRQK"
Lch_oo:         .asciz "O-O"
Lct_start:      .asciz "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
Lct_kiwi:       .asciz "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
Lct_pos3:       .asciz "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
Lct_pos4:       .asciz "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
Lct_pos5:       .asciz "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
Lct_ep:         .asciz "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3"
Lct_promo:      .asciz "8/4P3/8/8/8/8/k7/4K3 w - - 0 1"
Lct_twon:       .asciz "4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1"
Lct_stale:      .asciz "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"
Lct_bare:       .asciz "8/8/8/4k3/8/8/4K3/8 w - - 0 1"
Lct_fifty:      .asciz "4k3/8/8/8/8/8/8/R3K3 w - - 100 80"
Lct_check:      .asciz "4k3/8/8/8/8/8/8/4R1K1 b - - 0 1"
Lct_badfen:     .asciz "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
Lct_twokings:   .asciz "4k3/8/8/8/8/8/8/K3K3 w - - 0 1"
Lct_t_e4:       .asciz "e4"
Lct_s_e4:       .asciz "e4"
Lct_t_e7e5:     .asciz "e7e5"
Lct_t_e5:       .asciz "e5"
Lct_t_nf3:      .asciz "nf3"
Lct_s_nf3:      .asciz "Nf3"
Lct_t_nc6:      .asciz "Nc6"
Lct_t_bb5:      .asciz "Bb5"
Lct_t_a6:       .asciz "a6"
Lct_t_bxc6:     .asciz "Bxc6"
Lct_s_bxc6:     .asciz "Bxc6"
Lct_t_dxc6:     .asciz "dxc6"
Lct_s_dxc6:     .asciz "dxc6"
Lct_t_oo:       .asciz "O-O"
Lct_s_oo:       .asciz "O-O"
Lct_t_ke2:      .asciz "Ke3"
Lct_t_junk:     .asciz "hello"
Lct_t_bc4:      .asciz "Bc4"
Lct_t_qh5:      .asciz "Qh5"
Lct_t_nf6:      .asciz "Nf6??"
Lct_t_qxf7:     .asciz "Qxf7"
Lct_s_qxf7:     .asciz "Qxf7#"
Lct_t_exf6:     .asciz "exf6"
Lct_s_exf6:     .asciz "exf6"
Lct_t_e8q:      .asciz "e8=Q"
Lct_s_e8q:      .asciz "e8=Q"
Lct_t_e8n:      .asciz "e8N"
Lct_s_e8n:      .asciz "e8=N"
Lct_t_e7e8:     .asciz "e7e8"
Lct_t_nd2:      .asciz "Nd2"
Lct_t_nbd2:     .asciz "Nbd2"
Lct_s_nbd2:     .asciz "Nbd2"
Lct_t_ooo:      .asciz "O-O-O"
Lct_s_ooo:      .asciz "O-O-O"
Lct_t_zero:     .asciz "0-0-0"
Ln_ch205:       .asciz "205 chess: perft from the start (20, 400, 8902)"
Ln_ch206:       .asciz "206 chess: perft from the standard test positions"
Ln_ch207:       .asciz "207 chess: moves as typed and written; a mate; bad moves refused"
Ln_ch208:       .asciz "208 chess: en passant, promotion, two knights, castling long"
Ln_ch209:       .asciz "209 chess: stalemate, bare kings, fifty moves, check; bad positions"
Lch_ooo:        .asciz "O-O-O"
