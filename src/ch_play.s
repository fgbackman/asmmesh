// ch_play.s — a chess game, pure (no globals, no system calls): whose move it is, each
// move checked against the rules (ch_core.s) whoever sends it, the packets between two
// asmmesh devices (moves, resign, draw, catching up after a lost move), moves typed as
// text over bitchat, how the game ends (mate, stalemate, fifty moves, bare kings,
// threefold repetition, resign, agreed draw), and the words and board for the screens.
// ch_mesh.s moves the packets. Self-tests 210-213: two devices play.
.include "macros.inc"
.include "ch_defs.inc"

.macro CP_COPY2 dst, src                  // copy a position (136 bytes)
    mov  x9, #0
Lcq_\@:
    ldr  x10, [\src, x9]
    str  x10, [\dst, x9]
    add  x9, x9, #8
    cmp  x9, #CP_SIZE
    b.lo Lcq_\@
.endm

.text
.p2align 2

// void _cg_start(game *g, long via, uint64 room, uint32 game, long colour, uint64 me,
//   uint64 them) — a new game from the starting position, being played
.globl _cg_start
_cg_start:
    ENTER 16
    mov  x19, x0
    str  x1, [sp, #96]
    str  x2, [sp, #104]
    mov  x20, x3
    mov  x21, x4
    mov  x22, x5
    mov  x23, x6
    mov  x9, #0
    mov  x10, #CG_SIZE
1:  str  xzr, [x19, x9]
    add  x9, x9, #8
    cmp  x9, x10
    b.lo 1b
    ldr  x9, [sp, #96]
    str  x9, [x19, #CG_VIA]
    ldr  x9, [sp, #104]
    str  x9, [x19, #CG_ROOM]
    str  x20, [x19, #CG_GID]
    str  x21, [x19, #CG_ME]
    str  x22, [x19, #CG_ME_ID]
    str  x23, [x19, #CG_OPP]
    add  x0, x19, #CG_POS
    bl   _ch_start
    add  x0, x19, #CG_POS
    bl   _ch_hash
    str  x0, [x19, #CG_HIST]
    mov  x9, #CGS_PLAY
    str  x9, [x19, #CG_STATE]
    LEAVE 16

// long _cg_try(game *g, const char *text, long len, uint8 out[20]) -> x0 20 and the MOVE
//   packet in out, x1 the move; or CGT_NOTPLAYING, CGT_NOTYOURS, or _ch_parse's answer
.globl _cg_try
_cg_try:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldr  x9, [x19, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne Ltr_notplaying
    ldrb w9, [x19, #(CG_POS + CP_SIDE)]
    ldr  x10, [x19, #CG_ME]
    cmp  x9, x10
    b.ne Ltr_notyours
    add  x0, x19, #CG_POS
    mov  x1, x20
    mov  x2, x21
    bl   _ch_parse
    tbnz x0, #63, Ltr_ret
    mov  w23, w0
    mov  x0, x19
    mov  w1, w23
    bl   Lcg_apply
    mov  x0, x19
    mov  x1, x22
    bl   _cg_pkt_last
    mov  w1, w23
    LEAVE 0
Ltr_notplaying:
    mov  x0, #CGT_NOTPLAYING
    b    Ltr_ret
Ltr_notyours:
    mov  x0, #CGT_NOTYOURS
Ltr_ret:
    mov  x1, #0
    LEAVE 0

// long _cg_text_in(game *g, const char *text, long len) -> 1 if it was the other player's
//   move, legal, and played (bitchat: they type moves); 0 if it isn't a move for now
.globl _cg_text_in
_cg_text_in:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ldr  x9, [x19, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne 9f
    ldrb w9, [x19, #(CG_POS + CP_SIDE)]
    ldr  x10, [x19, #CG_ME]
    cmp  x9, x10
    b.eq 9f                               // our move, not theirs
    add  x0, x19, #CG_POS
    mov  x1, x20
    mov  x2, x21
    bl   _ch_parse
    tbnz x0, #63, 9f
    mov  w1, w0
    mov  x0, x19
    bl   Lcg_apply
    mov  x0, #1
    LEAVE 0
9:  mov  x0, #0
    LEAVE 0

// long _cg_pkt_last(const game *g, uint8 out[20]) -> 20: the last move as a MOVE packet
//   (sent again until the reply comes), or 0 before the first move (leaf)
.globl _cg_pkt_last
_cg_pkt_last:
    ldr  x9, [x0, #CG_PLY]
    cbz  x9, 1f
    mov  w10, #'C'
    strb w10, [x1]
    mov  w10, #CK_MOVE
    strb w10, [x1, #1]
    ldr  x10, [x0, #CG_GID]
    stur w10, [x1, #2]
    sturh w9, [x1, #6]
    sub  x10, x9, #1
    add  x11, x0, #CG_MOVES
    ldr  w10, [x11, x10, lsl #2]
    stur w10, [x1, #8]
    add  x11, x0, #CG_HIST
    ldr  x10, [x11, x9, lsl #3]
    stur x10, [x1, #12]
    mov  x0, #20
    ret
1:  mov  x0, #0
    ret

// long _cg_pkt_new(const game *g, uint8 out[22]) -> 22: NEW, who plays white and black (leaf)
.globl _cg_pkt_new
_cg_pkt_new:
    mov  w10, #'C'
    strb w10, [x1]
    mov  w10, #CK_NEW
    strb w10, [x1, #1]
    ldr  x10, [x0, #CG_GID]
    stur w10, [x1, #2]
    ldr  x10, [x0, #CG_ME_ID]
    ldr  x11, [x0, #CG_OPP]
    ldr  x12, [x0, #CG_ME]
    cbz  x12, 1f
    mov  x13, x10
    mov  x10, x11
    mov  x11, x13
1:  stur x10, [x1, #6]
    stur x11, [x1, #14]
    mov  x0, #22
    ret

// long _cg_new_in(game *g, uint64 me, uint64 sender, const uint8 *pkt, long len, uint64 room)
//   -> 1 a new game with us in it, 0 the one we're playing, -1 not taken (not ours, or
//   another game is being played)
.globl _cg_new_in
_cg_new_in:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    str  x5, [sp, #96]
    cmp  x23, #22
    b.lo Lni_bad
    ldrb w9, [x22]
    cmp  w9, #'C'
    b.ne Lni_bad
    ldrb w9, [x22, #1]
    cmp  w9, #CK_NEW
    b.ne Lni_bad
    ldur w24, [x22, #2]
    ldr  x9, [x19, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne 1f
    ldr  x10, [x19, #CG_GID]
    cmp  x10, x24
    b.ne Lni_bad                          // busy with another
    mov  x0, #0
    LEAVE 16
1:  ldur x10, [x22, #6]                   // white
    ldur x11, [x22, #14]                  // black
    cmp  x10, x11
    b.eq Lni_bad
    mov  x4, #0                           // we're white: the sender is black
    mov  x6, x11
    cmp  x10, x20
    b.eq 2f
    mov  x4, #8
    mov  x6, x10
    cmp  x11, x20
    b.ne Lni_bad
2:  cmp  x6, x21                          // only the other player sets up our game
    b.ne Lni_bad
    mov  x0, x19
    mov  x1, #CGV_MESH
    ldr  x2, [sp, #96]
    mov  x3, x24
    mov  x5, x20
    bl   _cg_start
    mov  x0, #1
    LEAVE 16
Lni_bad:
    mov  x0, #-1
    LEAVE 16

// long _cg_pkt_in(game *g, uint64 sender, const uint8 *pkt, long len, uint8 out[105])
//   -> x0 1 if the game changed (redraw), else 0; x1 the length of a packet to send back in
//   out (0 none). Only the other player of this game is heard; every move is checked.
.globl _cg_pkt_in
_cg_pkt_in:
    ENTER 1056                            // [96] the legal moves (1024)
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    mov  x24, #0                          // changed
    str  xzr, [sp, #1120]
    cmp  x22, #6
    b.lo Lpi_out
    ldrb w9, [x21]
    cmp  w9, #'C'
    b.ne Lpi_out
    ldr  x9, [x19, #CG_STATE]
    cbz  x9, Lpi_out
    ldur w9, [x21, #2]
    ldr  x10, [x19, #CG_GID]
    cmp  x9, x10
    b.ne Lpi_out
    ldr  x10, [x19, #CG_OPP]
    cmp  x20, x10
    b.ne Lpi_out
    ldrb w9, [x21, #1]
    cmp  w9, #CK_MOVE
    b.eq Lpi_move
    cmp  w9, #CK_RESIGN
    b.eq Lpi_resign
    cmp  w9, #CK_ASK
    b.eq Lpi_ask
    cmp  w9, #CK_HIST
    b.eq Lpi_hist
    cmp  w9, #CK_DRAW
    b.eq Lpi_draw
    b    Lpi_out
Lpi_move:
    cmp  x22, #20
    b.lo Lpi_out
    ldurh w9, [x21, #6]
    ldr  x10, [x19, #CG_PLY]
    cmp  x9, x10
    b.ls Lpi_out                          // one we have
    add  x11, x10, #1
    cmp  x9, x11
    b.hi Lpi_gap                          // we missed one: ask for the rest
    ldr  x9, [x19, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne Lpi_out
    ldrb w9, [x19, #(CG_POS + CP_SIDE)]
    ldr  x10, [x19, #CG_ME]
    cmp  x9, x10
    b.eq Lpi_out                          // it's our move, not theirs
    ldur w1, [x21, #8]
    mov  x0, x19
    bl   Lcg_legal_apply
    mov  x24, x0
    b    Lpi_out
Lpi_gap:
    mov  w9, #'C'
    strb w9, [x23]
    mov  w9, #CK_ASK
    strb w9, [x23, #1]
    ldr  x9, [x19, #CG_GID]
    stur w9, [x23, #2]
    ldr  x9, [x19, #CG_PLY]
    sturh w9, [x23, #6]
    mov  x9, #8
    str  x9, [sp, #1120]
    b    Lpi_out
Lpi_resign:
    ldr  x9, [x19, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne Lpi_out
    ldr  x9, [x19, #CG_ME]                // they gave up: our colour wins
    mov  x10, #CGR_WHITE
    cbz  x9, 1f
    mov  x10, #CGR_BLACK
1:  mov  x0, x19
    mov  x1, x10
    mov  x2, #CGE_RESIGN
    bl   Lcg_over
    mov  x24, #1
    b    Lpi_out
Lpi_ask:
    cmp  x22, #8
    b.lo Lpi_out
    ldurh w9, [x21, #6]                   // they have this many: the rest, 24 at most
    ldr  x10, [x19, #CG_PLY]
    cmp  x9, x10
    b.hs Lpi_out
    sub  x11, x10, x9
    cmp  x11, #CK_HIST_MAX
    mov  x12, #CK_HIST_MAX
    csel x11, x12, x11, hi
    mov  w12, #'C'
    strb w12, [x23]
    mov  w12, #CK_HIST
    strb w12, [x23, #1]
    ldr  x12, [x19, #CG_GID]
    stur w12, [x23, #2]
    sturh w9, [x23, #6]
    strb w11, [x23, #8]
    mov  x12, #0
2:  cmp  x12, x11
    b.hs 3f
    add  x13, x9, x12
    add  x14, x19, #CG_MOVES
    ldr  w14, [x14, x13, lsl #2]
    add  x15, x23, #9
    add  x15, x15, x12, lsl #2
    str  w14, [x15]
    add  x12, x12, #1
    b    2b
3:  add  x11, x11, x11
    add  x11, x11, x11
    add  x11, x11, #9
    str  x11, [sp, #1120]
    b    Lpi_out
Lpi_hist:
    cmp  x22, #9
    b.lo Lpi_out
    ldrb w9, [x21, #8]
    cmp  w9, #CK_HIST_MAX
    b.hi Lpi_out
    lsl  x10, x9, #2
    add  x10, x10, #9
    cmp  x22, x10
    b.lo Lpi_out
    ldurh w20, [x21, #6]                  // (the sender is checked: x20 is free now)
    mov  x22, x9
    mov  x9, #0
4:  cmp  x9, x22
    b.hs Lpi_out
    str  x9, [sp, #1112]
    add  x10, x20, x9                     // this move's place in the game
    ldr  x11, [x19, #CG_PLY]
    cmp  x10, x11
    b.lo 5f                               // one we have
    b.hi Lpi_out                          // a gap even here: stop
    ldr  x11, [x19, #CG_STATE]
    cmp  x11, #CGS_PLAY
    b.ne Lpi_out
    ldrb w11, [x19, #(CG_POS + CP_SIDE)]  // only their moves: ours we always have, and
    ldr  x12, [x19, #CG_ME]               //   nobody else may make them for us
    cmp  x11, x12
    b.eq Lpi_out
    add  x11, x21, #9
    ldr  w1, [x11, x9, lsl #2]
    mov  x0, x19
    bl   Lcg_legal_apply
    cbz  x0, Lpi_out                      // not legal: stop there
    mov  x24, #1
5:  ldr  x9, [sp, #1112]
    add  x9, x9, #1
    b    4b
Lpi_draw:
    ldr  x9, [x19, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne Lpi_out
    ldr  x9, [x19, #CG_DRAW]
    cmp  x9, #1
    b.ne 6f
    mov  x0, x19                          // we offered, they say yes
    mov  x1, #CGR_DRAW
    mov  x2, #CGE_AGREED
    bl   Lcg_over
    mov  x24, #1
    b    Lpi_out
6:  mov  x9, #2
    str  x9, [x19, #CG_DRAW]
    mov  x24, #1
Lpi_out:
    mov  x0, x24
    ldr  x1, [sp, #1120]
    LEAVE 1056

// Lcg_legal_apply(g, move) -> 1 if it is legal now and was played, else 0
Lcg_legal_apply:
    ENTER 1040                            // [96] the legal moves
    mov  x19, x0
    mov  w20, w1
    add  x0, x19, #CG_POS
    add  x1, sp, #96
    bl   _ch_legal
    mov  x9, #0
1:  cmp  x9, x0
    b.hs 8f
    add  x10, sp, #96
    ldr  w10, [x10, x9, lsl #2]
    add  x9, x9, #1
    cmp  w10, w20
    b.ne 1b
    mov  x0, x19
    mov  w1, w20
    bl   Lcg_apply
    mov  x0, #1
    LEAVE 1040
8:  mov  x0, #0
    LEAVE 1040

// Lcg_apply(g, move) — play a legal move and see whether that ends the game
Lcg_apply:
    ENTER 0
    mov  x19, x0
    mov  w20, w1
    ldr  x21, [x19, #CG_PLY]
    cmp  x21, #CG_MAXPLY
    b.hs Lap_long
    add  x0, x19, #CG_POS
    mov  w1, w20
    bl   _ch_make
    add  x9, x19, #CG_MOVES
    str  w20, [x9, x21, lsl #2]
    add  x21, x21, #1
    str  x21, [x19, #CG_PLY]
    add  x0, x19, #CG_POS
    bl   _ch_hash
    add  x9, x19, #CG_HIST
    str  x0, [x9, x21, lsl #3]
    mov  x22, x0
    str  xzr, [x19, #CG_DRAW]             // a move answers a draw offer
    add  x0, x19, #CG_POS
    bl   _ch_status
    cmp  x0, #CHS_MATE
    b.eq Lap_mate
    mov  x2, #CGE_STALE
    cmp  x0, #CHS_STALE
    b.eq Lap_draw
    mov  x2, #CGE_FIFTY
    cmp  x0, #CHS_FIFTY
    b.eq Lap_draw
    mov  x2, #CGE_MATERIAL
    cmp  x0, #CHS_MATERIAL
    b.eq Lap_draw
    mov  x9, #0                           // the same position a third time
    mov  x10, #0
    add  x11, x19, #CG_HIST
1:  cmp  x9, x21
    b.hi 2f
    ldr  x12, [x11, x9, lsl #3]
    cmp  x12, x22
    cinc x10, x10, eq
    add  x9, x9, #1
    b    1b
2:  cmp  x10, #3
    b.lo 9f
    mov  x2, #CGE_REPEAT
Lap_draw:
    mov  x0, x19
    mov  x1, #CGR_DRAW
    bl   Lcg_over
    b    9f
Lap_mate:
    ldrb w9, [x19, #(CG_POS + CP_SIDE)]   // the side to move is mated
    mov  x1, #CGR_BLACK
    cbz  w9, 3f
    mov  x1, #CGR_WHITE
3:  mov  x0, x19
    mov  x2, #CGE_MATE
    bl   Lcg_over
    b    9f
Lap_long:
    mov  x0, x19
    mov  x1, #CGR_DRAW
    mov  x2, #CGE_LONG
    bl   Lcg_over
9:  LEAVE 0

// Lcg_over(x0 g, x1 result, x2 reason) (leaf)
Lcg_over:
    str  x1, [x0, #CG_RESULT]
    str  x2, [x0, #CG_REASON]
    mov  x9, #CGS_OVER
    str  x9, [x0, #CG_STATE]
    ret

// long _cg_resign(game *g, uint8 out[6]) -> 6: we give up (RESIGN in out), or 0 (leaf)
.globl _cg_resign
_cg_resign:
    ldr  x9, [x0, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne 1f
    ldr  x9, [x0, #CG_ME]
    mov  x10, #CGR_BLACK
    cbz  x9, 2f
    mov  x10, #CGR_WHITE
2:  str  x10, [x0, #CG_RESULT]
    mov  x10, #CGE_RESIGN
    str  x10, [x0, #CG_REASON]
    mov  x10, #CGS_OVER
    str  x10, [x0, #CG_STATE]
    mov  w10, #'C'
    strb w10, [x1]
    mov  w10, #CK_RESIGN
    strb w10, [x1, #1]
    ldr  x10, [x0, #CG_GID]
    stur w10, [x1, #2]
    mov  x0, #6
    ret
1:  mov  x0, #0
    ret

// long _cg_draw(game *g, uint8 out[8]) -> 8: offer a draw, or accept theirs (DRAW in out);
//   0 if no game is being played (leaf)
.globl _cg_draw
_cg_draw:
    ldr  x9, [x0, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne 2f
    ldr  x9, [x0, #CG_DRAW]
    mov  x10, #1
    cmp  x9, #2
    b.ne 1f
    mov  x10, #CGR_DRAW                   // theirs: agreed
    str  x10, [x0, #CG_RESULT]
    mov  x10, #CGE_AGREED
    str  x10, [x0, #CG_REASON]
    mov  x10, #CGS_OVER
    str  x10, [x0, #CG_STATE]
    mov  x10, #0
1:  str  x10, [x0, #CG_DRAW]
    mov  w10, #'C'
    strb w10, [x1]
    mov  w10, #CK_DRAW
    strb w10, [x1, #1]
    ldr  x10, [x0, #CG_GID]
    stur w10, [x1, #2]
    ldr  x10, [x0, #CG_PLY]
    sturh w10, [x1, #6]
    mov  x0, #8
    ret
2:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
// Words and the board

.macro SBC_S lbl
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    ADRL x3, \lbl
    bl   Lsc_s
    mov  x20, x1
.endm
.macro SBC_R reg                          // (not x0-x2)
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, \reg
    bl   Lsc_s
    mov  x20, x1
.endm
.macro SBC_N reg
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, \reg
    bl   Lsc_n
    mov  x20, x1
.endm

// long _cgt_status(const game *g, char *buf, long cap) — "Your move (white) · check",
//   "Their move", "Checkmate: you win", "Draw: stalemate", "They offer a draw"...
.globl _cgt_status
_cgt_status:
    ENTER 0
    mov  x22, x0
    mov  x19, x1
    mov  x21, x2
    mov  x20, #0
    cbz  x21, 9f
    strb wzr, [x19]
    ldr  x9, [x22, #CG_STATE]
    cbz  x9, 9f
    cmp  x9, #CGS_OVER
    b.eq Lst_over
    ldrb w9, [x22, #(CG_POS + CP_SIDE)]
    ldr  x10, [x22, #CG_ME]
    ADRL x11, Lct_your
    ADRL x12, Lct_their
    cmp  x9, x10
    csel x11, x12, x11, ne
    SBC_R x11
    ADRL x11, Lct_white
    ADRL x12, Lct_black
    ldr  x10, [x22, #CG_ME]
    cmp  x10, #0
    csel x11, x12, x11, ne
    SBC_R x11
    add  x0, x22, #CG_POS                 // check?
    bl   _ch_status
    cmp  x0, #CHS_CHECK
    b.ne 1f
    SBC_S Lct_check
1:  ldr  x9, [x22, #CG_DRAW]
    cmp  x9, #2
    b.ne 2f
    SBC_S Lct_offered
    b    9f
2:  cmp  x9, #1
    b.ne 9f
    SBC_S Lct_youoffered
    b    9f
Lst_over:
    ldr  x9, [x22, #CG_REASON]
    ldr  x10, [x22, #CG_RESULT]
    cmp  x10, #CGR_DRAW
    b.eq Lst_draw
    ldr  x11, [x22, #CG_ME]               // did we win?
    mov  x12, #CGR_WHITE
    cbz  x11, 3f
    mov  x12, #CGR_BLACK
3:  cmp  x10, x12
    cset x23, eq
    ADRL x11, Lct_mate
    ADRL x12, Lct_resigned
    cmp  x9, #CGE_RESIGN
    csel x11, x12, x11, eq
    SBC_R x11
    ADRL x11, Lct_lose
    ADRL x12, Lct_win
    cmp  x23, #0
    csel x11, x12, x11, ne
    SBC_R x11
    b    9f
Lst_draw:
    SBC_S Lct_draw
    ADRL x11, Lct_why
    sub  x9, x9, #CGE_STALE
    cmp  x9, #5
    b.hi 9f
    ldr  x11, [x11, x9, lsl #3]
    SBC_R x11
9:  mov  x0, x20
    LEAVE 0

// long _cgt_row(const game *g, long row, char *buf, long cap) — one row of the board as
//   seen from our side (row 0 the far one), in chess symbols: "8 ♜ ♞ ♝ ♛ ♚ ♝ ♞ ♜";
//   row 8: the files, "  a b c d e f g h"
.globl _cgt_row
_cgt_row:
    ENTER 16
    mov  x22, x0
    mov  x23, x1
    mov  x19, x2
    mov  x21, x3
    mov  x20, #0
    cbz  x21, 9f
    strb wzr, [x19]
    ldr  x24, [x22, #CG_ME]               // 8: we're black, the board turned round
    cmp  x23, #8
    b.eq Lrw_files
    b.hi 9f
    mov  x9, #7                           // the rank shown on this row
    sub  x9, x9, x23
    cbz  x24, 1f
    mov  x9, x23
1:  str  x9, [sp, #96]
    add  w10, w9, #'1'
    strb w10, [sp, #104]
    strb wzr, [sp, #105]
    add  x9, sp, #104
    SBC_R x9
    mov  x23, #0                          // each file
2:  cmp  x23, #8
    b.hs 9f
    SBC_S Lct_space
    mov  x9, x23
    cbz  x24, 3f
    mov  x10, #7
    sub  x9, x10, x23
3:  ldr  x10, [sp, #96]
    add  x9, x9, x10, lsl #4
    add  x10, x22, #CG_POS
    ldrb w9, [x10, x9]
    ADRL x10, Lct_glyphs                  // 16 entries of 4 bytes, by piece code
    add  x9, x10, x9, lsl #2
    SBC_R x9
    add  x23, x23, #1
    b    2b
Lrw_files:
    SBC_S Lct_space
    mov  x23, #0
4:  cmp  x23, #8
    b.hs 9f
    SBC_S Lct_space
    mov  x9, x23
    cbz  x24, 5f
    mov  x10, #7
    sub  x9, x10, x23
5:  add  w9, w9, #'a'
    strb w9, [sp, #104]
    strb wzr, [sp, #105]
    add  x9, sp, #104
    SBC_R x9
    add  x23, x23, #1
    b    4b
9:  mov  x0, x20
    LEAVE 16

// long _cgt_moves(const game *g, long from, char *buf, long cap) — the moves from move
//   number `from` (0: all) on: "1. e4 e5 2. Nf3 Nc6"; one move: from = the last
.globl _cgt_moves
_cgt_moves:
    ENTER 1200                            // [96] a position (136)  [240] a move (16)
    mov  x22, x0
    mov  x23, x1
    mov  x19, x2
    mov  x21, x3
    mov  x20, #0
    cbz  x21, 9f
    strb wzr, [x19]
    add  x0, sp, #96
    bl   _ch_start
    mov  x24, #0
1:  ldr  x9, [x22, #CG_PLY]
    cmp  x24, x9
    b.hs 9f
    cmp  x24, x23
    b.lo 4f                               // before what's wanted: just play it
    cbz  x20, 2f
    SBC_S Lct_space
2:  tst  x24, #1
    b.ne 3f                               // white's: "12. "
    lsr  x9, x24, #1
    add  x9, x9, #1
    SBC_N x9
    SBC_S Lct_dot
    b    31f
3:  cmp  x24, x23                         // black's first: "12... "
    b.ne 31f
    lsr  x9, x24, #1
    add  x9, x9, #1
    SBC_N x9
    SBC_S Lct_dots
31: add  x9, x22, #CG_MOVES
    ldr  w1, [x9, x24, lsl #2]
    add  x0, sp, #96
    add  x2, sp, #240
    bl   _ch_san
    add  x9, sp, #240
    SBC_R x9
4:  add  x9, x22, #CG_MOVES
    ldr  w1, [x9, x24, lsl #2]
    add  x0, sp, #96
    bl   _ch_make
    add  x24, x24, #1
    b    1b
9:  mov  x0, x20
    LEAVE 1200

// long _cg_targets(const game *g, long from, uint8 out[32]) -> where the piece on that
//   square may go now (for the board you click), if it's ours and our move
.globl _cg_targets
_cg_targets:
    ENTER 1040
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, #0
    ldr  x9, [x19, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne 9f
    ldrb w9, [x19, #(CG_POS + CP_SIDE)]
    ldr  x10, [x19, #CG_ME]
    cmp  x9, x10
    b.ne 9f
    add  x0, x19, #CG_POS
    add  x1, sp, #96
    bl   _ch_legal
    mov  x23, x0
    mov  x9, #0
1:  cmp  x9, x23
    b.hs 9f
    add  x10, sp, #96
    ldr  w10, [x10, x9, lsl #2]
    add  x9, x9, #1
    and  w11, w10, #0xFF
    cmp  x11, x20
    b.ne 1b
    ubfx w11, w10, #8, #8
    mov  x12, #0                          // once each (four promotions, one square)
2:  cmp  x12, x22
    b.hs 3f
    ldrb w13, [x21, x12]
    cmp  w13, w11
    b.eq 1b
    add  x12, x12, #1
    b    2b
3:  cmp  x22, #32
    b.hs 9f
    strb w11, [x21, x22]
    add  x22, x22, #1
    b    1b
9:  mov  x0, x22
    LEAVE 1040

// Lsc_s(x0 buf, x1 pos, x2 cap, x3 string) -> x1 (leaf)
Lsc_s:
1:  ldrb w9, [x3], #1
    cbz  w9, 2f
    add  x10, x1, #1
    cmp  x10, x2
    b.hs 2f
    strb w9, [x0, x1]
    mov  x1, x10
    b    1b
2:  cmp  x1, x2
    b.hs 3f
    strb wzr, [x0, x1]
3:  ret

// Lsc_n(x0 buf, x1 pos, x2 cap, x3 number) -> x1 (leaf)
Lsc_n:
    mov  x9, x3
    mov  x10, #0
    mov  x11, #10
1:  add  x10, x10, #1
    udiv x9, x9, x11
    cbnz x9, 1b
    add  x12, x1, x10
    add  x13, x12, #1
    cmp  x13, x2
    b.hi 3f
    mov  x9, x3
    mov  x14, x12
2:  sub  x14, x14, #1
    udiv x13, x9, x11
    msub x15, x13, x11, x9
    add  w15, w15, #'0'
    strb w15, [x0, x14]
    mov  x9, x13
    cmp  x14, x1
    b.gt 2b
    mov  x1, x12
    strb wzr, [x0, x1]
3:  ret

// ---------------------------------------------------------------------------
// self-tests 210-213, called from test.s: Ann (white) and Bea (black) on two devices

.set CA_ID,     0xA1
.set CB_ID,     0xB2

.macro CGM g, other, text                 // \g plays text; \other takes the packet
    ldr  x0, [sp, #\g]
    ADRL x1, \text
    mov  x2, #12
    add  x3, sp, #112
    bl   _cg_try
    cmp  x0, #20
    cset x9, eq
    and  x20, x20, x9
    ldr  x0, [sp, #\other]
    ldr  x1, [sp, #\g]                    // the sender: \g's own id
    ldr  x1, [x1, #CG_ME_ID]
    add  x2, sp, #112
    mov  x3, #20
    add  x4, sp, #144
    bl   _cg_pkt_in
    cmp  x0, #1
    cset x9, eq
    and  x20, x20, x9
.endm

.macro CG_SAMEPOS                         // both devices: the same position
    ldr  x0, [sp, #96]
    add  x0, x0, #CG_POS
    bl   _ch_hash
    mov  x21, x0
    ldr  x0, [sp, #104]
    add  x0, x0, #CG_POS
    bl   _ch_hash
    cmp  x0, x21
    cset x9, eq
    and  x20, x20, x9
.endm

.macro CG_FRESH                           // a new game on both, Ann white
    ldr  x0, [sp, #96]
    mov  x1, #CGV_MESH
    mov  x2, #77
    mov  x3, #0x55
    mov  x4, #0
    mov  x5, #CA_ID
    mov  x6, #CB_ID
    bl   _cg_start
    ldr  x9, [sp, #104]                   // Bea's device: the last game is over
    str  xzr, [x9, #CG_STATE]
    ldr  x0, [sp, #96]                    // Ann's NEW sets up Bea's
    add  x1, sp, #112
    bl   _cg_pkt_new
    ldr  x0, [sp, #104]
    mov  x1, #CB_ID
    mov  x2, #CA_ID
    add  x3, sp, #112
    mov  x4, #22
    mov  x5, #77
    bl   _cg_new_in
    cmp  x0, #1
    cset x9, eq
    and  x20, x20, x9
.endm

.globl _ch_play_selftest
_ch_play_selftest:
    ENTER 512                             // [96] Ann's  [104] Bea's  [112] a packet (32)
    mov  x19, #0                          //   [144] the reply (112)  [256] text (256)
    mov  x0, #1
    mov  x1, #CG_SIZE
    bl   _calloc
    str  x0, [sp, #96]
    mov  x0, #1
    mov  x1, #CG_SIZE
    bl   _calloc
    str  x0, [sp, #104]

    // 210. NEW sets up the other device with the colours swapped; moves cross; out of turn,
    //      an illegal move and a stranger are refused; a scholar's mate ends it on both
    mov  x20, #1
    CG_FRESH
    ldr  x9, [sp, #104]
    ldr  x9, [x9, #CG_ME]
    cmp  x9, #8
    cset x9, eq
    and  x20, x20, x9
    ldr  x0, [sp, #104]                   // Bea can't move first
    ADRL x1, Lpt_e5
    mov  x2, #2
    add  x3, sp, #112
    bl   _cg_try
    cmp  x0, #CGT_NOTYOURS
    cset x9, eq
    and  x20, x20, x9
    CGM  96, 104, Lpt_e4
    CGM  104, 96, Lpt_e5
    ldr  x0, [sp, #96]                    // illegal
    ADRL x1, Lpt_ke3
    mov  x2, #3
    add  x3, sp, #112
    bl   _cg_try
    cmp  x0, #CHP_ILLEGAL
    cset x9, eq
    and  x20, x20, x9
    CGM  96, 104, Lpt_bc4
    CGM  104, 96, Lpt_nc6
    CGM  96, 104, Lpt_qh5
    ldr  x0, [sp, #104]                   // a stranger's move for Bea's game: not heard
    add  x1, sp, #112
    bl   _cg_pkt_last
    ldr  x0, [sp, #96]
    mov  x1, #0xC3
    add  x2, sp, #112
    mov  x3, #20
    add  x4, sp, #144
    bl   _cg_pkt_in
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    CGM  104, 96, Lpt_nf6
    CGM  96, 104, Lpt_qxf7
    CG_SAMEPOS
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #CG_STATE]
    cmp  x10, #CGS_OVER
    cset x10, eq
    and  x20, x20, x10
    ldr  x10, [x9, #CG_RESULT]
    cmp  x10, #CGR_WHITE
    cset x10, eq
    and  x20, x20, x10
    ldr  x9, [sp, #104]
    ldr  x10, [x9, #CG_RESULT]
    cmp  x10, #CGR_WHITE
    cset x10, eq
    and  x20, x20, x10
    mov  w1, w20
    ADRL x0, Ln_ch210
    bl   _t_report
    add  x19, x19, x0

    // 211. a lost move comes again and is taken once; a gap is asked about; a history
    //      that would move Bea's pieces for her is refused
    mov  x20, #1
    CG_FRESH
    ldr  x0, [sp, #96]                    // Ann: d4, lost on the way
    ADRL x1, Lpt_d4
    mov  x2, #2
    add  x3, sp, #112
    bl   _cg_try
    ldr  x0, [sp, #96]                    // sent again (nf_mesh.s does it every 15 s)
    add  x1, sp, #112
    bl   _cg_pkt_last
    ldr  x0, [sp, #104]
    mov  x1, #CA_ID
    add  x2, sp, #112
    mov  x3, #20
    add  x4, sp, #144
    bl   _cg_pkt_in
    cmp  x0, #1
    cset x9, eq
    and  x20, x20, x9
    ldr  x0, [sp, #104]                   // and again: nothing
    mov  x1, #CA_ID
    add  x2, sp, #112
    mov  x3, #20
    add  x4, sp, #144
    bl   _cg_pkt_in
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    mov  w9, #3                           // a move numbered 3: a gap, so an ASK (have 1)
    strh w9, [sp, #(112 + 6)]
    ldr  x0, [sp, #104]
    mov  x1, #CA_ID
    add  x2, sp, #112
    mov  x3, #20
    add  x4, sp, #144
    bl   _cg_pkt_in
    cmp  x1, #8
    cset x9, eq
    and  x20, x20, x9
    ldrb w9, [sp, #145]
    cmp  w9, #CK_ASK
    cset x9, eq
    and  x20, x20, x9
    ldrh w9, [sp, #(144 + 6)]
    cmp  w9, #1
    cset x9, eq
    and  x20, x20, x9
    ldr  x0, [sp, #96]                    // Ann's device makes Bea's e5 itself, then Nf3,
    ADRL x1, Lpt_e5                       //   and answers Bea's ASK with both
    mov  x2, #2
    bl   _cg_text_in
    ldr  x0, [sp, #96]
    ADRL x1, Lpt_nf3
    mov  x2, #3
    add  x3, sp, #112
    bl   _cg_try
    ldr  x0, [sp, #96]
    mov  x1, #CB_ID
    add  x2, sp, #144
    mov  x3, #8
    add  x4, sp, #256
    bl   _cg_pkt_in
    cmp  x1, #(9 + 8)
    cset x9, eq
    and  x20, x20, x9
    ldr  x0, [sp, #104]                   // Bea: the first is hers to make: refused
    mov  x1, #CA_ID
    add  x2, sp, #256
    mov  x3, #(9 + 8)
    add  x4, sp, #144
    bl   _cg_pkt_in
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #104]
    ldr  x9, [x9, #CG_PLY]
    cmp  x9, #1
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_ch211
    bl   _t_report
    add  x19, x19, x0

    // 212. resign; a draw offered and accepted; threefold repetition
    mov  x20, #1
    CG_FRESH
    ldr  x0, [sp, #104]
    add  x1, sp, #112
    bl   _cg_resign
    ldr  x0, [sp, #96]
    mov  x1, #CB_ID
    add  x2, sp, #112
    mov  x3, #6
    add  x4, sp, #144
    bl   _cg_pkt_in
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #CG_RESULT]
    cmp  x10, #CGR_WHITE
    cset x10, eq
    and  x20, x20, x10
    ldr  x10, [x9, #CG_REASON]
    cmp  x10, #CGE_RESIGN
    cset x10, eq
    and  x20, x20, x10
    CG_FRESH
    ldr  x0, [sp, #96]                    // Ann offers
    add  x1, sp, #112
    bl   _cg_draw
    ldr  x0, [sp, #104]
    mov  x1, #CA_ID
    add  x2, sp, #112
    mov  x3, #8
    add  x4, sp, #144
    bl   _cg_pkt_in
    ldr  x9, [sp, #104]
    ldr  x9, [x9, #CG_DRAW]
    cmp  x9, #2
    cset x9, eq
    and  x20, x20, x9
    ldr  x0, [sp, #104]                   // Bea accepts
    add  x1, sp, #112
    bl   _cg_draw
    ldr  x0, [sp, #96]
    mov  x1, #CB_ID
    add  x2, sp, #112
    mov  x3, #8
    add  x4, sp, #144
    bl   _cg_pkt_in
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #CG_REASON]
    cmp  x10, #CGE_AGREED
    cset x10, eq
    and  x20, x20, x10
    ldr  x9, [sp, #104]
    ldr  x10, [x9, #CG_REASON]
    cmp  x10, #CGE_AGREED
    cset x10, eq
    and  x20, x20, x10
    CG_FRESH                              // knights out and back, twice: the third time
    CGM  96, 104, Lpt_nf3
    CGM  104, 96, Lpt_nf6
    CGM  96, 104, Lpt_ng1
    CGM  104, 96, Lpt_ng8
    CGM  96, 104, Lpt_nf3
    CGM  104, 96, Lpt_nf6
    CGM  96, 104, Lpt_ng1
    CGM  104, 96, Lpt_ng8
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #CG_REASON]
    cmp  x10, #CGE_REPEAT
    cset x10, eq
    and  x20, x20, x10
    ldr  x9, [sp, #104]
    ldr  x10, [x9, #CG_STATE]
    cmp  x10, #CGS_OVER
    cset x10, eq
    and  x20, x20, x10
    mov  w1, w20
    ADRL x0, Ln_ch212
    bl   _t_report
    add  x19, x19, x0

    // 213. the words: the moves, the last one, the status, the board both ways round,
    //      where a piece may go
    mov  x20, #1
    CG_FRESH
    CGM  96, 104, Lpt_e4
    CGM  104, 96, Lpt_e5
    CGM  96, 104, Lpt_nf3
    ldr  x0, [sp, #96]
    mov  x1, #0
    add  x2, sp, #256
    mov  x3, #200
    bl   _cgt_moves
    add  x0, sp, #256
    ADRL x1, Lpt_moves
    bl   Lpt_same
    and  x20, x20, x0
    ldr  x0, [sp, #96]                    // from Bea's move on: "1... e5 2. Nf3"
    mov  x1, #1
    add  x2, sp, #256
    mov  x3, #200
    bl   _cgt_moves
    add  x0, sp, #256
    ADRL x1, Lpt_moves1
    bl   Lpt_same
    and  x20, x20, x0
    ldr  x0, [sp, #104]
    add  x1, sp, #256
    mov  x2, #200
    bl   _cgt_status
    add  x0, sp, #256
    ADRL x1, Lpt_st_bea
    bl   Lpt_same
    and  x20, x20, x0
    ldr  x0, [sp, #96]                    // Ann's far row: black's back rank
    mov  x1, #0
    add  x2, sp, #256
    mov  x3, #200
    bl   _cgt_row
    add  x0, sp, #256
    ADRL x1, Lpt_row8
    bl   Lpt_same
    and  x20, x20, x0
    ldr  x0, [sp, #104]                   // Bea's far row: white's, turned round
    mov  x1, #0
    add  x2, sp, #256
    mov  x3, #200
    bl   _cgt_row
    add  x0, sp, #256
    ADRL x1, Lpt_row1b
    bl   Lpt_same
    and  x20, x20, x0
    ldr  x0, [sp, #104]
    mov  x1, #8
    add  x2, sp, #256
    mov  x3, #200
    bl   _cgt_row
    add  x0, sp, #256
    ADRL x1, Lpt_filesb
    bl   Lpt_same
    and  x20, x20, x0
    ldr  x0, [sp, #104]                   // Bea's knight on b8: a6 and c6
    mov  x1, #0x71
    add  x2, sp, #256
    bl   _cg_targets
    cmp  x0, #2
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_ch213
    bl   _t_report
    add  x19, x19, x0

    ldr  x0, [sp, #96]
    bl   _free
    ldr  x0, [sp, #104]
    bl   _free
    mov  x0, x19
    LEAVE 512

// Lpt_same(a, b) -> 1 if equal (leaf)
Lpt_same:
    ldrb w9, [x0], #1
    ldrb w10, [x1], #1
    cmp  w9, w10
    b.ne 1f
    cbnz w9, Lpt_same
    mov  x0, #1
    ret
1:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lct_why:        .quad Lct_stale, Lct_fifty, Lct_material, Lct_repeat, Lct_agreed, Lct_long

.section __TEXT,__const
// a 4-byte cell for each piece code: the symbol and a NUL (a dot for an empty square)
Lct_glyphs:
    .byte 0xC2, 0xB7, 0, 0                // 0 ·
    .byte 0xE2, 0x99, 0x99, 0             // 1 ♙
    .byte 0xE2, 0x99, 0x98, 0             // 2 ♘
    .byte 0xE2, 0x99, 0x97, 0             // 3 ♗
    .byte 0xE2, 0x99, 0x96, 0             // 4 ♖
    .byte 0xE2, 0x99, 0x95, 0             // 5 ♕
    .byte 0xE2, 0x99, 0x94, 0             // 6 ♔
    .byte '?', 0, 0, 0
    .byte '?', 0, 0, 0
    .byte 0xE2, 0x99, 0x9F, 0             // 9 ♟
    .byte 0xE2, 0x99, 0x9E, 0             // 10 ♞
    .byte 0xE2, 0x99, 0x9D, 0             // 11 ♝
    .byte 0xE2, 0x99, 0x9C, 0             // 12 ♜
    .byte 0xE2, 0x99, 0x9B, 0             // 13 ♛
    .byte 0xE2, 0x99, 0x9A, 0             // 14 ♚
    .byte '?', 0, 0, 0

.section __TEXT,__cstring,cstring_literals
Lct_your:       .asciz "Your move"
Lct_their:      .asciz "Their move"
Lct_white:      .asciz " (you\342\200\231re white)"
Lct_black:      .asciz " (you\342\200\231re black)"
Lct_check:      .asciz " \302\267 check!"
Lct_offered:    .asciz " \302\267 they offer a draw: draw to accept"
Lct_youoffered: .asciz " \302\267 you offered a draw"
Lct_mate:       .asciz "Checkmate: "
Lct_resigned:   .asciz "Resigned: "
Lct_win:        .asciz "you win"
Lct_lose:       .asciz "you lose"
Lct_draw:       .asciz "Draw: "
Lct_stale:      .asciz "stalemate"
Lct_fifty:      .asciz "fifty moves without a capture or a pawn move"
Lct_material:   .asciz "neither side can mate"
Lct_repeat:     .asciz "the same position three times"
Lct_agreed:     .asciz "agreed"
Lct_long:       .asciz "400 moves"
Lct_space:      .asciz " "
Lct_dot:        .asciz ". "
Lct_dots:       .asciz "... "
Lpt_e4:         .asciz "e4"
Lpt_e5:         .asciz "e5"
Lpt_d4:         .asciz "d4"
Lpt_d5:         .asciz "d5"
Lpt_c4:         .asciz "c4"
Lpt_ke3:        .asciz "Ke3"
Lpt_bc4:        .asciz "Bc4"
Lpt_nc6:        .asciz "Nc6"
Lpt_qh5:        .asciz "Qh5"
Lpt_nf6:        .asciz "Nf6"
Lpt_qxf7:       .asciz "Qxf7"
Lpt_nf3:        .asciz "Nf3"
Lpt_ng1:        .asciz "Ng1"
Lpt_ng8:        .asciz "Ng8"
Lpt_moves:      .asciz "1. e4 e5 2. Nf3"
Lpt_moves1:     .asciz "1... e5 2. Nf3"
Lpt_st_bea:     .asciz "Your move (you\342\200\231re black)"
Lpt_row8:       .asciz "8 \342\231\234 \342\231\236 \342\231\235 \342\231\233 \342\231\232 \342\231\235 \342\231\236 \342\231\234"
Lpt_row1b:      .asciz "1 \342\231\226 \302\267 \342\231\227 \342\231\224 \342\231\225 \342\231\227 \342\231\230 \342\231\226"
Lpt_filesb:     .asciz "  h g f e d c b a"
Ln_ch210:       .asciz "210 chess game: moves cross; out of turn, illegal, a stranger refused; mate on both"
Ln_ch211:       .asciz "211 chess game: a lost move sent again; a gap asked about; forged moves for us refused"
Ln_ch212:       .asciz "212 chess game: resign, an agreed draw, threefold repetition"
Ln_ch213:       .asciz "213 chess game: the moves, the status, the board both ways round, targets"
