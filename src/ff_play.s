// ff_play.s — a Fivefold game, pure (no globals, no system calls). Three ways to play:
//   solo   the day's word, alone (the same for everyone that day)
//   race   everyone in a room the same word; each row's colours (never its letters) are
//          shown to the others as they go
//   duel   each player seals a word for the other (SHA-256 with a salt and their id); their
//          device answers every guess with its colours; at the end both words are revealed
//          and every answer checked, so a dishonest answer is caught
// ff_mesh.s moves the packets and draws the screens. Self-tests 221-223.
.include "macros.inc"
.include "ff_defs.inc"

.text
.p2align 2

// void _ffp_begin(game *g, long mode, long word (-1: a duel), uint64 room, uint32 game,
//   uint64 me, uint64 other) — other: a duel's opponent, a race's host
.globl _ffp_begin
_ffp_begin:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    str  x5, [sp, #96]
    str  x6, [sp, #104]
    mov  x9, #0
1:  str  xzr, [x19, x9]
    add  x9, x9, #8
    cmp  x9, #FG_SIZE
    b.lo 1b
    str  x20, [x19, #FG_MODE]
    str  x22, [x19, #FG_ROOM]
    str  x23, [x19, #FG_GID]
    ldr  x9, [sp, #96]
    str  x9, [x19, #FG_ME]
    ldr  x9, [sp, #104]
    str  x9, [x19, #FG_OPP]
    str  x9, [x19, #FG_HOST]
    mov  x9, #FFS_CHOOSE
    cmp  x20, #FFM_DUEL
    b.eq 2f
    str  x21, [x19, #FG_DAY]
    mov  x0, x21
    bl   _ff_hidden
    ldr  w9, [x0]
    str  w9, [x19, #FG_WORD]
    ldrb w9, [x0, #4]
    strb w9, [x19, #(FG_WORD + 4)]
    mov  x9, #FFS_PLAY
2:  str  x9, [x19, #FG_STATE]
    LEAVE 16

// long _ffp_guess(game *g, const char *text, long len, uint8 out[16]) -> x0 the row it went
//   in (0-5) or FFG_*; x1 the length of a packet to send in out (race: our row's colours;
//   duel: the guess, for them to answer; solo: 0)
.globl _ffp_guess
_ffp_guess:
    ENTER 16                              // [96] the word (8)
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldr  x9, [x19, #FG_STATE]
    cmp  x9, #FFS_PLAY
    b.ne Lfg_over
    ldr  x9, [x19, #FG_MODE]
    cmp  x9, #FFM_DUEL
    b.ne 1f
    ldr  x9, [x19, #FG_PEND]              // a duel: one guess at a time, and their word sealed
    cbnz x9, Lfg_wait
    ldp  x9, x10, [x19, #FG_THEIRC]
    orr  x9, x9, x10
    cbz  x9, Lfg_wait
1:  mov  x0, x20
    mov  x1, x21
    add  x2, sp, #96
    bl   _ff_norm
    tbnz x0, #63, Lfg_not5
    add  x0, sp, #96
    bl   _ff_valid
    cbz  x0, Lfg_notword
    ldr  x23, [x19, #FG_N]                // the row
    mov  x9, #5
    mul  x24, x23, x9
    add  x10, x19, #FG_GUESS
    add  x10, x10, x24
    ldr  w11, [sp, #96]
    str  w11, [x10]
    ldrb w11, [sp, #100]
    strb w11, [x10, #4]
    ldr  x9, [x19, #FG_MODE]
    cmp  x9, #FFM_DUEL
    b.eq Lfg_duel
    add  x0, x19, #FG_GUESS               // solo, race: we know the word
    add  x0, x0, x24
    add  x1, x19, #FG_WORD
    add  x2, x19, #FG_COL
    add  x2, x2, x24
    bl   _ff_score
    mov  x1, x0
    mov  x0, x19
    bl   Lfg_row_done
    mov  x1, #0
    ldr  x9, [x19, #FG_MODE]
    cmp  x9, #FFM_RACE
    b.ne 2f
    mov  x0, x19                          // race: our row, colours only
    mov  x1, x23
    mov  x2, x22
    bl   Lfg_pkt_row
    mov  x1, x0
2:  mov  x0, x23
    LEAVE 16
Lfg_duel:                                 // a duel: they answer it
    mov  x9, #1
    str  x9, [x19, #FG_PEND]
    mov  x0, x19
    mov  x1, x22
    bl   _ffp_pending
    mov  x1, x0
    mov  x0, x23
    LEAVE 16
Lfg_over:
    mov  x0, #FFG_OVER
    b    Lfg_ret
Lfg_wait:
    mov  x0, #FFG_WAIT
    b    Lfg_ret
Lfg_not5:
    mov  x0, #FFG_NOT5
    b    Lfg_ret
Lfg_notword:
    mov  x0, #FFG_NOTWORD
Lfg_ret:
    mov  x1, #0
    LEAVE 16

// Lfg_row_done(x0 g, x1 1 if that row guessed it) — the row counted; done if guessed or six
Lfg_row_done:
    ldr  x9, [x0, #FG_N]
    add  x9, x9, #1
    str  x9, [x0, #FG_N]
    mov  x10, #1
    cbnz x1, 1f
    cmp  x9, #FF_ROWS
    b.lo 2f
    mov  x10, #2
1:  str  x10, [x0, #FG_SOLVED]
    mov  x10, #FFS_DONE
    str  x10, [x0, #FG_STATE]
2:  ret

// Lfg_pkt_row(x0 g, x1 row, x2 out) -> 13: a race's ROW packet for that row (leaf)
Lfg_pkt_row:
    mov  w9, #'F'
    strb w9, [x2]
    mov  w9, #FK_ROW
    strb w9, [x2, #1]
    ldr  x9, [x0, #FG_GID]
    stur w9, [x2, #2]
    add  w9, w1, #1
    strb w9, [x2, #6]
    mov  x9, #5
    mul  x10, x1, x9
    add  x10, x10, #FG_COL
    add  x10, x0, x10
    mov  x9, #0
1:  ldrb w11, [x10, x9]
    add  x12, x2, #7
    strb w11, [x12, x9]
    add  x9, x9, #1
    cmp  x9, #5
    b.lo 1b
    ldr  x9, [x0, #FG_SOLVED]
    cmp  x9, #1
    cset w9, eq
    strb w9, [x2, #12]
    mov  x0, #13
    ret

// long _ffp_pending(const game *g, uint8 out[12]) -> 12: a duel's guess still unanswered, as
//   its GUESS packet (sent again until the colours come), else 0 (leaf)
.globl _ffp_pending
_ffp_pending:
    ldr  x9, [x0, #FG_PEND]
    cbz  x9, 8f
    mov  w9, #'F'
    strb w9, [x1]
    mov  w9, #FK_GUESS
    strb w9, [x1, #1]
    ldr  x9, [x0, #FG_GID]
    stur w9, [x1, #2]
    ldr  x9, [x0, #FG_N]
    add  w10, w9, #1
    strb w10, [x1, #6]
    mov  x10, #5
    mul  x9, x9, x10
    add  x9, x9, #FG_GUESS
    add  x9, x0, x9
    ldr  w10, [x9]
    stur w10, [x1, #7]
    ldrb w10, [x9, #4]
    strb w10, [x1, #11]
    mov  x0, #12
    ret
8:  mov  x0, #0
    ret

// long _ffp_choose(game *g, const char *text, long len, const uint8 salt[16], uint8 out[22])
//   -> 22 and our DUEL packet (our word for them, sealed), or FFG_NOT5 / FFG_NOTWORD /
//   FFG_OVER (not choosing)
.globl _ffp_choose
_ffp_choose:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    ldr  x9, [x19, #FG_STATE]
    cmp  x9, #FFS_CHOOSE
    b.ne 7f
    mov  x0, x20
    mov  x1, x21
    add  x2, sp, #96
    bl   _ff_norm
    tbnz x0, #63, 5f
    add  x0, sp, #96
    bl   _ff_valid
    cbz  x0, 6f
    ldr  w9, [sp, #96]
    str  w9, [x19, #FG_MINE]
    ldrb w9, [sp, #100]
    strb w9, [x19, #(FG_MINE + 4)]
    ldp  x9, x10, [x22]
    stp  x9, x10, [x19, #FG_SALT]
    mov  x9, #FFS_PLAY
    str  x9, [x19, #FG_STATE]
    mov  x0, x19
    mov  x1, x23
    bl   _ffp_pkt_duel
    LEAVE 16
5:  mov  x0, #FFG_NOT5
    LEAVE 16
6:  mov  x0, #FFG_NOTWORD
    LEAVE 16
7:  mov  x0, #FFG_OVER
    LEAVE 16

// long _ffp_pkt_duel(const game *g, uint8 out[22]) -> 22: our word, sealed (sent again until
//   they're guessing), or 0 before we picked one
.globl _ffp_pkt_duel
_ffp_pkt_duel:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ldrb w9, [x19, #FG_MINE]
    cbz  w9, 8f
    mov  w9, #'F'
    strb w9, [x20]
    mov  w9, #FK_DUEL
    strb w9, [x20, #1]
    ldr  x9, [x19, #FG_GID]
    stur w9, [x20, #2]
    add  x0, x19, #FG_SALT
    ldr  x1, [x19, #FG_ME]
    add  x2, x19, #FG_MINE
    add  x3, x20, #6
    bl   _ff_commit
    mov  x0, #22
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// long _ffp_pkt_reveal(const game *g, uint8 out[27]) -> 27: our word and salt, once both
//   boards are finished (a duel), else 0
.globl _ffp_pkt_reveal
_ffp_pkt_reveal:
    ldr  x9, [x0, #FG_MODE]
    cmp  x9, #FFM_DUEL
    b.ne 8f
    ldr  x9, [x0, #FG_STATE]
    cmp  x9, #FFS_DONE
    b.ne 8f
    ldr  x9, [x0, #FG_TDONE]
    cbz  x9, 8f
    mov  w9, #'F'
    strb w9, [x1]
    mov  w9, #FK_REVEAL
    strb w9, [x1, #1]
    ldr  x9, [x0, #FG_GID]
    stur w9, [x1, #2]
    ldr  w9, [x0, #FG_MINE]
    stur w9, [x1, #6]
    ldrb w9, [x0, #(FG_MINE + 4)]
    strb w9, [x1, #10]
    ldp  x9, x10, [x0, #FG_SALT]
    stur x9, [x1, #11]
    stur x10, [x1, #19]
    mov  x0, #27
    ret
8:  mov  x0, #0
    ret

// long _ffp_pkt_in(game *g, uint64 sender, const char *nick, long nlen, const uint8 *pkt,
//   long len, uint8 out[16]) -> x0 1 if the game changed (redraw), x1 a packet to send back
//   in out (a duel's colours for their guess), or 0. Only this game's other player(s).
.globl _ffp_pkt_in
_ffp_pkt_in:
    ENTER 80                              // [96] colours (8)  [104] a word (8)  [112] digest
    mov  x19, x0                          //   [128] nick  [136] nlen  [144] reply length
    mov  x20, x1                          //   [152] a guess's number
    mov  x21, x4
    mov  x22, x5
    mov  x23, x6                          // out (kept)
    stp  x2, x3, [sp, #128]
    mov  x24, #0
    str  xzr, [sp, #144]
    cmp  x22, #6
    b.lo Lpi_out
    ldrb w9, [x21]
    cmp  w9, #'F'
    b.ne Lpi_out
    ldr  x9, [x19, #FG_MODE]
    cbz  x9, Lpi_out
    ldur w9, [x21, #2]
    ldr  x10, [x19, #FG_GID]
    cmp  x9, x10
    b.ne Lpi_out
    ldr  x9, [x19, #FG_ME]
    cmp  x20, x9
    b.eq Lpi_out                          // our own
    ldrb w9, [x21, #1]
    cmp  w9, #FK_ROW
    b.eq Lpi_row
    ldr  x10, [x19, #FG_MODE]             // the rest: a duel's opponent only
    cmp  x10, #FFM_DUEL
    b.ne Lpi_out
    ldr  x10, [x19, #FG_OPP]
    cmp  x20, x10
    b.ne Lpi_out
    cmp  w9, #FK_DUEL
    b.eq Lpi_duel
    cmp  w9, #FK_GUESS
    b.eq Lpi_guess
    cmp  w9, #FK_FEED
    b.eq Lpi_feed
    cmp  w9, #FK_REVEAL
    b.eq Lpi_reveal
    b    Lpi_out
Lpi_row:                                  // a race: someone's row, colours only
    cmp  x22, #13
    b.lo Lpi_out
    ldr  x9, [x19, #FG_MODE]
    cmp  x9, #FFM_RACE
    b.ne Lpi_out
    ldrb w9, [x21, #6]                    // row 1-6
    str  x9, [sp, #152]
    sub  w9, w9, #1
    cmp  w9, #5
    b.hi Lpi_out
    mov  x10, #0                          // colours 0-2
1:  add  x11, x21, #7
    ldrb w11, [x11, x10]
    cmp  w11, #2
    b.hi Lpi_out
    add  x10, x10, #1
    cmp  x10, #5
    b.lo 1b
    mov  x0, x19
    mov  x1, x20
    ldp  x2, x3, [sp, #128]
    bl   Lfp_player
    tbnz x0, #63, Lpi_out
    mov  x9, #PF_SIZE
    madd x24, x0, x9, x19
    add  x24, x24, #FG_PL
    ldr  x12, [sp, #152]
    sub  x9, x12, #1
    mov  x10, #5
    mul  x9, x9, x10
    add  x9, x9, #PF_COL
    add  x9, x24, x9
    mov  x10, #0
2:  add  x11, x21, #7
    ldrb w11, [x11, x10]
    strb w11, [x9, x10]
    add  x10, x10, #1
    cmp  x10, #5
    b.lo 2b
    ldr  x9, [x24, #PF_N]
    cmp  x12, x9
    csel x9, x12, x9, hi
    str  x9, [x24, #PF_N]
    ldrb w9, [x21, #12]
    cbz  w9, 3f
    mov  x9, #1
    str  x9, [x24, #PF_SOLVED]
3:  mov  x24, #1
    b    Lpi_out
Lpi_duel:                                 // their word, sealed: kept once
    cmp  x22, #22
    b.lo Lpi_out
    ldp  x9, x10, [x19, #FG_THEIRC]
    orr  x9, x9, x10
    cbnz x9, Lpi_out
    ldur x9, [x21, #6]
    ldur x10, [x21, #14]
    stp  x9, x10, [x19, #FG_THEIRC]
    mov  x24, #1
    b    Lpi_out
Lpi_guess:                                // their guess at our word: its colours, back
    cmp  x22, #12
    b.lo Lpi_out
    ldrb w9, [x19, #FG_MINE]
    cbz  w9, Lpi_out                      // we haven't picked ours yet
    ldrb w9, [x21, #6]                    // its number, 1-6
    str  x9, [sp, #152]
    cbz  x9, Lpi_out
    sub  x9, x9, #1
    ldr  x10, [x19, #FG_TN]
    cmp  x9, x10
    b.lo Lpi_again                        // one we answered: the same answer again
    b.hi Lpi_out                          // out of order
    ldr  x11, [x19, #FG_TDONE]
    cbnz x11, Lpi_out
    cmp  x10, #FF_ROWS
    b.hs Lpi_out
    add  x0, x21, #7                      // five letters, a word
    mov  x1, #5
    add  x2, sp, #104
    bl   _ff_norm
    tbnz x0, #63, Lpi_out
    add  x0, sp, #104
    bl   _ff_valid
    cbz  x0, Lpi_out
    ldr  x10, [x19, #FG_TN]
    mov  x9, #5
    mul  x10, x10, x9
    add  x0, x19, #FG_TGUESS
    add  x0, x0, x10
    ldr  w11, [sp, #104]
    str  w11, [x0]
    ldrb w11, [sp, #108]
    strb w11, [x0, #4]
    add  x1, x19, #FG_MINE
    add  x2, x19, #FG_TCOL
    add  x2, x2, x10
    bl   _ff_score
    ldr  x10, [x19, #FG_TN]
    add  x10, x10, #1
    str  x10, [x19, #FG_TN]
    mov  x11, #1
    cbnz x0, 4f
    cmp  x10, #FF_ROWS
    b.lo Lpi_again
    mov  x11, #2
4:  str  x11, [x19, #FG_TDONE]
Lpi_again:                                // FEED: guess number [152], our colours for it
    ldr  x9, [sp, #152]
    mov  w10, #'F'
    strb w10, [x23]
    mov  w10, #FK_FEED
    strb w10, [x23, #1]
    ldr  x10, [x19, #FG_GID]
    stur w10, [x23, #2]
    strb w9, [x23, #6]
    sub  x9, x9, #1
    mov  x10, #5
    mul  x9, x9, x10
    add  x9, x9, #FG_TCOL
    add  x9, x19, x9
    mov  x10, #0
5:  ldrb w11, [x9, x10]
    add  x12, x23, #7
    strb w11, [x12, x10]
    add  x10, x10, #1
    cmp  x10, #5
    b.lo 5b
    mov  x9, #12
    str  x9, [sp, #144]
    mov  x24, #1
    b    Lpi_out
Lpi_feed:                                 // the colours for our guess
    cmp  x22, #12
    b.lo Lpi_out
    ldr  x9, [x19, #FG_PEND]
    cbz  x9, Lpi_out
    ldrb w9, [x21, #6]
    ldr  x10, [x19, #FG_N]
    add  x11, x10, #1
    cmp  x9, x11
    b.ne Lpi_out
    mov  x9, #5
    mul  x10, x10, x9
    add  x10, x10, #FG_COL
    add  x10, x19, x10
    mov  x9, #0
    mov  x12, #0                          // how many right places
6:  add  x11, x21, #7
    ldrb w11, [x11, x9]
    cmp  w11, #2
    b.hi Lpi_out                          // (nothing stored yet: checked first)
    cinc x12, x12, eq
    add  x9, x9, #1
    cmp  x9, #5
    b.lo 6b
    mov  x9, #0
7:  add  x11, x21, #7
    ldrb w11, [x11, x9]
    strb w11, [x10, x9]
    add  x9, x9, #1
    cmp  x9, #5
    b.lo 7b
    str  xzr, [x19, #FG_PEND]
    mov  x0, x19
    cmp  x12, #5
    cset x1, eq
    bl   Lfg_row_done
    mov  x24, #1
    b    Lpi_out
Lpi_reveal:                               // their word and salt: was every answer honest?
    cmp  x22, #27
    b.lo Lpi_out
    ldr  x9, [x19, #FG_CHECK]
    cbnz x9, Lpi_out
    add  x0, x21, #6
    mov  x1, #5
    add  x2, sp, #104
    bl   _ff_norm
    mov  x24, #1
    mov  x9, #-1
    str  x9, [x19, #FG_CHECK]             // dishonest unless shown otherwise
    tbnz x0, #63, Lpi_out
    ldr  w9, [sp, #104]                   // the word, as they said
    str  w9, [x19, #FG_TWORD]
    ldrb w9, [sp, #108]
    strb w9, [x19, #(FG_TWORD + 4)]
    add  x0, sp, #104
    bl   _ff_valid
    cbz  x0, Lpi_out
    add  x0, x21, #11                     // the seal: the one they sent first?
    mov  x1, x20
    add  x2, sp, #104
    add  x3, sp, #112
    bl   _ff_commit
    ldp  x9, x10, [sp, #112]
    ldp  x11, x12, [x19, #FG_THEIRC]
    cmp  x9, x11
    ccmp x10, x12, #0, eq
    b.ne Lpi_out
    mov  x9, #0                           // every colour they gave us
8:  ldr  x10, [x19, #FG_N]
    cmp  x9, x10
    b.hs 10f
    str  x9, [sp, #152]
    mov  x10, #5
    mul  x10, x9, x10
    add  x0, x19, #FG_GUESS
    add  x0, x0, x10
    add  x1, sp, #104
    add  x2, sp, #96
    bl   _ff_score
    ldr  x9, [sp, #152]
    mov  x10, #5
    mul  x10, x9, x10
    add  x10, x10, #FG_COL
    add  x10, x19, x10
    mov  x11, #0
9:  add  x12, sp, #96
    ldrb w12, [x12, x11]
    ldrb w13, [x10, x11]
    cmp  w12, w13
    b.ne Lpi_out
    add  x11, x11, #1
    cmp  x11, #5
    b.lo 9b
    add  x9, x9, #1
    b    8b
10: mov  x9, #1
    str  x9, [x19, #FG_CHECK]
Lpi_out:
    mov  x0, x24
    ldr  x1, [sp, #144]
    LEAVE 80

// Lfp_player(x0 g, x1 id, x2 nick, x3 nlen) -> a race player's slot (added if new), or -1
//   (leaf)
Lfp_player:
    ldr  x9, [x0, #FG_NPL]
    mov  x10, #0
1:  cmp  x10, x9
    b.hs 2f
    mov  x11, #PF_SIZE
    madd x11, x10, x11, x0
    ldr  x12, [x11, #(FG_PL + PF_ID)]
    cmp  x12, x1
    b.eq 5f
    add  x10, x10, #1
    b    1b
2:  cmp  x9, #FF_PLAYERS
    b.hs 8f
    add  x12, x9, #1
    str  x12, [x0, #FG_NPL]
    mov  x10, x9
    mov  x11, #PF_SIZE
    madd x11, x10, x11, x0
    add  x11, x11, #FG_PL
    mov  x12, #0
3:  str  xzr, [x11, x12]
    add  x12, x12, #8
    cmp  x12, #PF_SIZE
    b.lo 3b
    str  x1, [x11, #PF_ID]
    cbz  x2, 6f                           // no name given
    mov  x12, #23
    cmp  x3, x12
    csel x3, x12, x3, hi
    mov  x12, #0
4:  cmp  x12, x3
    b.hs 6f
    ldrb w13, [x2, x12]
    cbz  w13, 6f
    add  x14, x11, #PF_NICK
    strb w13, [x14, x12]
    add  x12, x12, #1
    b    4b
5:  mov  x0, x10
    ret
6:  mov  x0, x10
    ret
8:  mov  x0, #-1
    ret

// ---------------------------------------------------------------------------
// Words for the screens

.macro FS_S lbl
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    ADRL x3, \lbl
    bl   Lfs_s
    mov  x20, x1
.endm
.macro FS_N reg
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, \reg
    bl   Lfs_n
    mov  x20, x1
.endm

// long _ffpt_share(const game *g, char *buf, long cap) — the result as coloured squares
//   only (nothing that gives the word away): "Fivefold 309 4/6" and a row of squares a guess
.globl _ffpt_share
_ffpt_share:
    ENTER 0
    mov  x22, x0
    mov  x19, x1
    mov  x21, x2
    mov  x20, #0
    cbz  x21, 9f
    strb wzr, [x19]
    FS_S Lfs_name
    ldr  x9, [x22, #FG_MODE]
    cmp  x9, #FFM_SOLO
    b.ne 1f
    ldr  x9, [x22, #FG_DAY]
    FS_N x9
    b    2f
1:  ADRL x10, Lfs_race
    cmp  x9, #FFM_RACE
    ADRL x11, Lfs_duel
    csel x10, x11, x10, ne
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, x10
    bl   Lfs_s
    mov  x20, x1
2:  FS_S Lfs_space
    ldr  x9, [x22, #FG_SOLVED]
    cmp  x9, #1
    b.eq 3f
    FS_S Lfs_x
    b    4f
3:  ldr  x9, [x22, #FG_N]
    FS_N x9
4:  FS_S Lfs_of6
    mov  x23, #0                          // the rows
5:  ldr  x9, [x22, #FG_N]
    cmp  x23, x9
    b.hs 9f
    FS_S Lfs_nl
    mov  x24, #0
6:  mov  x9, #5
    madd x9, x23, x9, x24
    add  x9, x9, #FG_COL
    ldrb w9, [x22, x9]
    ADRL x10, Lfs_sq0
    cmp  w9, #1
    ADRL x11, Lfs_sq1
    csel x10, x11, x10, eq
    cmp  w9, #2
    ADRL x11, Lfs_sq2
    csel x10, x11, x10, eq
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, x10
    bl   Lfs_s
    mov  x20, x1
    add  x24, x24, #1
    cmp  x24, #5
    b.lo 6b
    add  x23, x23, #1
    b    5b
9:  mov  x0, x20
    LEAVE 0

// long _ffpt_status(const game *g, char *buf, long cap) — what's happening, in a line
.globl _ffpt_status
_ffpt_status:
    ENTER 16
    mov  x22, x0
    mov  x19, x1
    mov  x21, x2
    mov  x20, #0
    cbz  x21, 9f
    strb wzr, [x19]
    ldr  x9, [x22, #FG_MODE]
    cbz  x9, 9f
    ldr  x10, [x22, #FG_STATE]
    cmp  x10, #FFS_CHOOSE
    b.ne 1f
    FS_S Lfs_choose
    b    9f
1:  cmp  x10, #FFS_DONE
    b.eq Lfst_done
    cmp  x9, #FFM_DUEL                    // playing
    b.ne 3f
    ldp  x11, x12, [x22, #FG_THEIRC]
    orr  x11, x11, x12
    cbnz x11, 2f
    FS_S Lfs_waitpick
    b    9f
2:  ldr  x11, [x22, #FG_PEND]
    cbz  x11, 3f
    FS_S Lfs_waitans
    b    9f
3:  FS_S Lfs_guess
    ldr  x9, [x22, #FG_N]
    add  x9, x9, #1
    FS_N x9
    FS_S Lfs_of6b
    b    9f
Lfst_done:
    ldr  x11, [x22, #FG_SOLVED]
    cmp  x11, #1
    b.ne 4f
    FS_S Lfs_got
    ldr  x9, [x22, #FG_N]
    FS_N x9
    b    5f
4:  ldr  x9, [x22, #FG_MODE]              // the word, if we know it
    cmp  x9, #FFM_DUEL
    b.eq 41f
    FS_S Lfs_was
    add  x9, x22, #FG_WORD
    bl   Lfs_word
    b    5f
41: FS_S Lfs_notgot
5:  ldr  x9, [x22, #FG_MODE]
    cmp  x9, #FFM_DUEL
    b.ne 9f
    ldr  x9, [x22, #FG_TDONE]             // a duel: them, and the result
    cbnz x9, 6f
    FS_S Lfs_theystill
    b    9f
6:  ldr  x9, [x22, #FG_CHECK]
    cbnz x9, 7f
    FS_S Lfs_revealing
    b    9f
7:  tbz  x9, #63, 8f
    FS_S Lfs_cheated
    b    9f
8:  FS_S Lfs_theirs                       // "· theirs was PLAIN" and who won
    add  x9, x22, #FG_TWORD
    bl   Lfs_word
    bl   Lfs_winner
    mov  x9, x0
    ADRL x10, Lfs_tie
    cmp  x9, #0
    b.eq 81f
    ADRL x10, Lfs_youwin
    cmp  x9, #1
    b.eq 81f
    ADRL x10, Lfs_theywin
81: mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, x10
    bl   Lfs_s
    mov  x20, x1
9:  mov  x0, x20
    LEAVE 16

// Lfs_word (inside the status: x9 five letters) — them, in capitals
Lfs_word:
    stp  x29, x30, [sp, #-32]!
    ldr  w10, [x9]
    ldrb w11, [x9, #4]
    and  w10, w10, #0xDFDFDFDF
    bic  w11, w11, #0x20
    str  w10, [sp, #16]
    strb w11, [sp, #20]
    strb wzr, [sp, #21]
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    add  x3, sp, #16
    bl   Lfs_s
    mov  x20, x1
    ldp  x29, x30, [sp], #32
    ret

// Lfs_winner (x22 g) -> 1 we won, -1 they did, 0 even: fewer guesses wins; not guessing loses
Lfs_winner:
    ldr  x9, [x22, #FG_SOLVED]
    ldr  x10, [x22, #FG_TDONE]
    cmp  x9, #1
    cset x11, eq                          // we guessed it
    cmp  x10, #1
    cset x12, eq                          // they did
    cmp  x11, x12
    b.eq 1f
    mov  x0, #1
    cbnz x11, 2f
    mov  x0, #-1
    ret
1:  mov  x0, #0
    cbz  x11, 2f                          // neither
    ldr  x9, [x22, #FG_N]
    ldr  x10, [x22, #FG_TN]
    cmp  x9, x10
    mov  x0, #1
    b.lo 2f
    mov  x0, #-1
    b.hi 2f
    mov  x0, #0
2:  ret

// Lfs_s(x0 buf, x1 pos, x2 cap, x3 string) -> x1 (leaf)
Lfs_s:
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

// Lfs_n(x0 buf, x1 pos, x2 cap, x3 number) -> x1 (leaf)
Lfs_n:
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
// self-tests 221-223, called from test.s

.set FA_ID,     0xA1
.set FB_ID,     0xB2

.macro FT_OK cond
    cset x9, \cond
    and  x20, x20, x9
.endm

.macro FT_DUEL                            // a fresh duel: Ann picks CRANE, Bea PLAIN, sealed
    ldr  x0, [sp, #96]
    mov  x1, #FFM_DUEL
    mov  x2, #-1
    mov  x3, #9
    mov  x4, #0x77
    mov  x5, #FA_ID
    mov  x6, #FB_ID
    bl   _ffp_begin
    ldr  x0, [sp, #104]
    mov  x1, #FFM_DUEL
    mov  x2, #-1
    mov  x3, #9
    mov  x4, #0x77
    mov  x5, #FB_ID
    mov  x6, #FA_ID
    bl   _ffp_begin
    ldr  x0, [sp, #96]
    ADRL x1, Lft2_crane
    mov  x2, #5
    ADRL x3, Lft2_salt_a
    add  x4, sp, #112
    bl   _ffp_choose
    cmp  x0, #22
    FT_OK eq
    ldr  x0, [sp, #104]
    mov  x1, #FA_ID
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, #22
    add  x6, sp, #144
    bl   _ffp_pkt_in
    ldr  x0, [sp, #104]
    ADRL x1, Lft2_plain
    mov  x2, #5
    ADRL x3, Lft2_salt_b
    add  x4, sp, #112
    bl   _ffp_choose
    ldr  x0, [sp, #96]
    mov  x1, #FB_ID
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, #22
    add  x6, sp, #144
    bl   _ffp_pkt_in
.endm

.macro FT_GUESS from, to, fromid, toid, word   // \from guesses; \to answers; \from takes it
    ldr  x0, [sp, #\from]
    ADRL x1, \word
    mov  x2, #5
    add  x3, sp, #112
    bl   _ffp_guess
    cmp  x1, #12
    FT_OK eq
    ldr  x0, [sp, #\to]
    mov  x1, #\fromid
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, #12
    add  x6, sp, #144
    bl   _ffp_pkt_in
    cmp  x1, #12
    FT_OK eq
    ldr  x0, [sp, #\from]
    mov  x1, #\toid
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #144
    mov  x5, #12
    add  x6, sp, #176
    bl   _ffp_pkt_in
.endm

.globl _ff_play_selftest
_ff_play_selftest:
    ENTER 256                             // [96] Ann  [104] Bea  [112] a packet (32)
    mov  x19, #0                          //   [144] the reply (32)  [176] spare (32)
    mov  x0, #1                           //   [208] text (128: to 336)
    mov  x1, #FG_SIZE
    bl   _calloc
    str  x0, [sp, #96]
    mov  x0, #1
    mov  x1, #FG_SIZE
    bl   _calloc
    str  x0, [sp, #104]

    // 221. solo: not five letters, not a word, a word, then the word: 2/6, done
    mov  x20, #1
    ldr  x0, [sp, #96]
    mov  x1, #FFM_SOLO
    mov  x2, #5
    mov  x3, #0
    mov  x4, #0
    mov  x5, #FA_ID
    mov  x6, #0
    bl   _ffp_begin
    ldr  x0, [sp, #96]
    ADRL x1, Lft2_abc
    mov  x2, #3
    add  x3, sp, #112
    bl   _ffp_guess
    cmp  x0, #FFG_NOT5
    FT_OK eq
    ldr  x0, [sp, #96]
    ADRL x1, Lft2_xxxxx
    mov  x2, #5
    add  x3, sp, #112
    bl   _ffp_guess
    cmp  x0, #FFG_NOTWORD
    FT_OK eq
    mov  x0, #6                           // another hidden word: a guess that isn't it
    bl   _ff_hidden
    mov  x1, x0
    ldr  x0, [sp, #96]
    mov  x2, #5
    add  x3, sp, #112
    bl   _ffp_guess
    cmp  x0, #0
    FT_OK eq
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #FG_STATE]
    cmp  x10, #FFS_PLAY
    FT_OK eq
    ldr  x0, [sp, #96]
    ldr  x1, [sp, #96]
    add  x1, x1, #FG_WORD
    mov  x2, #5
    add  x3, sp, #112
    bl   _ffp_guess
    cmp  x0, #1
    FT_OK eq
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #FG_SOLVED]
    cmp  x10, #1
    FT_OK eq
    ldr  x0, [sp, #96]                    // over: no more
    ADRL x1, Lft2_crane
    mov  x2, #5
    add  x3, sp, #112
    bl   _ffp_guess
    cmp  x0, #FFG_OVER
    FT_OK eq
    ldr  x0, [sp, #96]
    add  x1, sp, #208
    mov  x2, #128
    bl   _ffpt_share
    add  x0, sp, #208
    ADRL x1, Lft2_share
    bl   Lft2_prefix
    and  x20, x20, x0
    mov  w1, w20
    ADRL x0, Ln_ff221
    bl   _t_report
    add  x19, x19, x0

    // 222. an honest duel: sealed words cross; Ann SLATE then PLAIN, Bea CRANE: each
    //      device answers the other's guesses; both reveal; every answer checks out
    mov  x20, #1
    FT_DUEL
    ldr  x0, [sp, #96]                    // Ann can't guess before... she can: both sealed
    add  x1, sp, #208
    mov  x2, #128
    bl   _ffpt_status
    FT_GUESS 96, 104, FA_ID, FB_ID, Lft2_slate
    ldr  x9, [sp, #96]                    // SLATE against PLAIN: the colours Bea's device gave
    ldr  x10, [x9, #FG_N]
    cmp  x10, #1
    FT_OK eq
    ADRL x0, Lft2_slate
    ADRL x1, Lft2_plain
    add  x2, sp, #176
    bl   _ff_score
    ldr  x9, [sp, #96]
    ldr  w10, [x9, #FG_COL]
    ldr  w11, [sp, #176]
    cmp  w10, w11
    FT_OK eq
    FT_GUESS 96, 104, FA_ID, FB_ID, Lft2_plain
    FT_GUESS 104, 96, FB_ID, FA_ID, Lft2_crane
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #FG_SOLVED]
    cmp  x10, #1
    FT_OK eq
    ldr  x0, [sp, #96]                    // Ann reveals to Bea, Bea to Ann
    add  x1, sp, #112
    bl   _ffp_pkt_reveal
    cmp  x0, #27
    FT_OK eq
    ldr  x0, [sp, #104]
    mov  x1, #FA_ID
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, #27
    add  x6, sp, #144
    bl   _ffp_pkt_in
    ldr  x0, [sp, #104]
    add  x1, sp, #112
    bl   _ffp_pkt_reveal
    cmp  x0, #27
    FT_OK eq
    ldr  x0, [sp, #96]
    mov  x1, #FB_ID
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, #27
    add  x6, sp, #144
    bl   _ffp_pkt_in
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #FG_CHECK]
    cmp  x10, #1
    FT_OK eq
    ldr  x9, [sp, #104]
    ldr  x10, [x9, #FG_CHECK]
    cmp  x10, #1
    FT_OK eq
    ldr  x0, [sp, #104]                   // Bea: in 1, Ann in 2: Bea wins
    add  x1, sp, #208
    mov  x2, #128
    bl   _ffpt_status
    add  x0, sp, #208
    ADRL x1, Lfs_youwin
    bl   Lft2_has
    and  x20, x20, x0
    mov  w1, w20
    ADRL x0, Ln_ff222
    bl   _t_report
    add  x19, x19, x0

    // 223. cheating: Bea answers Ann's PLAIN with all grey; a stranger's guess is ignored;
    //      Bea's reveal then shows her answers lied; a word that isn't the sealed one fails
    mov  x20, #1
    FT_DUEL
    ldr  x0, [sp, #96]
    ADRL x1, Lft2_plain
    mov  x2, #5
    add  x3, sp, #112
    bl   _ffp_guess
    ldr  x0, [sp, #104]                   // a stranger's copy of that guess: not answered
    mov  x1, #0xC3
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, #12
    add  x6, sp, #144
    bl   _ffp_pkt_in
    cmp  x1, #0
    FT_OK eq
    mov  w9, #'F'                         // Bea's lie: FEED 1, all 0
    strb w9, [sp, #144]
    mov  w9, #FK_FEED
    strb w9, [sp, #145]
    mov  w9, #0x77
    str  w9, [sp, #146]
    mov  w9, #1
    strb w9, [sp, #150]
    str  wzr, [sp, #151]
    strb wzr, [sp, #155]
    ldr  x0, [sp, #96]
    mov  x1, #FB_ID
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #144
    mov  x5, #12
    add  x6, sp, #176
    bl   _ffp_pkt_in
    cmp  x0, #1
    FT_OK eq
    ldr  x0, [sp, #104]                   // her reveal, made by hand: PLAIN and her salt
    mov  w9, #'F'
    strb w9, [sp, #112]
    mov  w9, #FK_REVEAL
    strb w9, [sp, #113]
    mov  w9, #0x77
    str  w9, [sp, #114]
    ADRL x9, Lft2_plain
    ldr  w10, [x9]
    str  w10, [sp, #118]
    ldrb w10, [x9, #4]
    strb w10, [sp, #122]
    ADRL x9, Lft2_salt_b
    ldp  x10, x11, [x9]
    stur x10, [sp, #123]
    stur x11, [sp, #131]
    ldr  x0, [sp, #96]
    mov  x1, #FB_ID
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, #27
    add  x6, sp, #176
    bl   _ffp_pkt_in
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #FG_CHECK]
    cmp  x10, #-1
    FT_OK eq
    ldr  x0, [sp, #96]
    add  x1, sp, #208
    mov  x2, #128
    bl   _ffpt_status
    FT_DUEL                               // and a word that isn't the one sealed
    mov  w9, #'F'
    strb w9, [sp, #112]
    mov  w9, #FK_REVEAL
    strb w9, [sp, #113]
    mov  w9, #0x77
    str  w9, [sp, #114]
    ADRL x9, Lft2_slate
    ldr  w10, [x9]
    str  w10, [sp, #118]
    ldrb w10, [x9, #4]
    strb w10, [sp, #122]
    ADRL x9, Lft2_salt_b
    ldp  x10, x11, [x9]
    stur x10, [sp, #123]
    stur x11, [sp, #131]
    ldr  x0, [sp, #96]
    mov  x1, #FB_ID
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, #27
    add  x6, sp, #176
    bl   _ffp_pkt_in
    ldr  x9, [sp, #96]
    ldr  x10, [x9, #FG_CHECK]
    cmp  x10, #-1
    FT_OK eq
    mov  w1, w20
    ADRL x0, Ln_ff223
    bl   _t_report
    add  x19, x19, x0

    ldr  x0, [sp, #96]
    bl   _free
    ldr  x0, [sp, #104]
    bl   _free
    mov  x0, x19
    LEAVE 256

// Lft2_prefix(s, p) -> 1 if s starts with p (leaf)
Lft2_prefix:
    ldrb w10, [x1], #1
    cbz  w10, 1f
    ldrb w9, [x0], #1
    cmp  w9, w10
    b.eq Lft2_prefix
    mov  x0, #0
    ret
1:  mov  x0, #1
    ret

// Lft2_has(s, p) -> 1 if p is somewhere in s (leaf)
Lft2_has:
    mov  x11, x0
1:  mov  x12, #0
2:  ldrb w10, [x1, x12]
    cbz  w10, 3f
    ldrb w9, [x11, x12]
    cbz  w9, 4f
    cmp  w9, w10
    b.ne 5f
    add  x12, x12, #1
    b    2b
3:  mov  x0, #1
    ret
5:  ldrb w9, [x11], #1
    cbnz w9, 1b
4:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lft2_salt_a:    .byte 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
Lft2_salt_b:    .byte 31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46

.section __TEXT,__cstring,cstring_literals
Lfs_name:       .asciz "Fivefold "
Lfs_race:       .asciz "race"
Lfs_duel:       .asciz "duel"
Lfs_space:      .asciz " "
Lfs_x:          .asciz "X"
Lfs_of6:        .asciz "/6"
Lfs_nl:         .asciz "\n"
Lfs_sq0:        .asciz "\342\254\233"           // a dark square: not in the word
Lfs_sq1:        .asciz "\360\237\237\246"       // blue: in the word, elsewhere
Lfs_sq2:        .asciz "\360\237\237\247"       // amber: right place
Lfs_choose:     .asciz "Pick a five-letter word for them to guess"
Lfs_waitpick:   .asciz "Waiting for them to pick their word"
Lfs_waitans:    .asciz "Waiting for their device to answer\342\200\246"
Lfs_guess:      .asciz "Guess the five-letter word: try "
Lfs_of6b:       .asciz " of 6"
Lfs_got:        .asciz "Got it in "
Lfs_was:        .asciz "The word was "
Lfs_notgot:     .asciz "Not this time"
Lfs_theystill:  .asciz " \302\267 they\342\200\231re still guessing"
Lfs_revealing:  .asciz " \302\267 checking their answers\342\200\246"
Lfs_cheated:    .asciz " \302\267 their answers didn\342\200\231t match their word: they cheated"
Lfs_theirs:     .asciz " \302\267 theirs was "
Lfs_youwin:     .asciz " \302\267 you win"
Lfs_theywin:    .asciz " \302\267 they win"
Lfs_tie:        .asciz " \302\267 a tie"
Lft2_abc:       .asciz "abc"
Lft2_xxxxx:     .asciz "xxxxx"
Lft2_crane:     .asciz "crane"
Lft2_plain:     .asciz "plain"
Lft2_slate:     .asciz "slate"
Lft2_share:     .asciz "Fivefold 5 2/6\n"
Ln_ff221:       .asciz "221 fivefold solo: not five letters, not a word, a miss, the word: 2/6, shared as squares"
Ln_ff222:       .asciz "222 fivefold duel: sealed words, each device answers the other, reveals check out"
Ln_ff223:       .asciz "223 fivefold duel: a lying answer and a word not the sealed one caught; strangers ignored"
