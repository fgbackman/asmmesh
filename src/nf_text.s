// nf_text.s — Ninefold's words on screen, pure (no globals, no system calls, no printf): the
// status line, the grid, what a typed word got, a round's results, your words, the players.
// The Mac shows them in the game room's header and transcript, the iPhone in its game screen
// (nf_mesh.s). Every function writes a NUL-terminated string of at most cap bytes and
// returns its length. Self-test 204 (in nf_play.s's game); `harness nfdemo` prints a game.
.include "macros.inc"
.include "nf_defs.inc"

.macro SB_S lbl                           // append a string
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    ADRL x3, \lbl
    bl   Lsb_s
    mov  x20, x1
.endm
.macro SB_R reg                           // append the string at reg (not x0-x2)
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, \reg
    bl   Lsb_s
    mov  x20, x1
.endm
.macro SB_N reg                           // append a number (reg not x0-x2)
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, \reg
    bl   Lsb_n
    mov  x20, x1
.endm
.macro SB_C ch                            // append one byte
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, #\ch
    bl   Lsb_c
    mov  x20, x1
.endm
.macro SB_RB wreg                         // append the byte in wreg (not w0-w3)
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  w3, \wreg
    bl   Lsb_c
    mov  x20, x1
.endm
.macro SB_W ptr, len                      // append letters in capitals (not x0-x2)
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, \ptr
    mov  x4, \len
    bl   Lsb_w
    mov  x20, x1
.endm

.text
.p2align 2

// long _nft_status(const game *g, long now, char *buf, long cap)
//   "Round 1 of 3 · 3:12 left · you 7 · Anna 5"; "... starts in 8 s"; "... time! checking
//   words…"; "... scored · Anna 23 · you 11"; in the lobby "waiting for players"
.globl _nft_status
_nft_status:
    ENTER 32                              // [96] ranking (12)
    mov  x22, x0
    mov  x23, x1
    mov  x19, x2
    mov  x21, x3
    mov  x20, #0
    cbz  x21, Lst_out
    strb wzr, [x19]
    ldr  x9, [x22, #G_STATE]
    cbz  x9, Lst_out
    cmp  x9, #NFS_LOBBY
    b.ne 1f
    SB_S Lt_lobby
    b    Lst_out
1:  SB_S Lt_round
    ldr  x9, [x22, #G_ROUND]
    SB_N x9
    SB_S Lt_of
    ldr  x9, [x22, #G_ROUNDS]
    SB_N x9
    ldr  x9, [x22, #G_STATE]
    cmp  x9, #NFS_WAIT
    b.ne 2f
    SB_S Lt_starts
    ldr  x9, [x22, #G_START]
    subs x9, x9, x23
    csel x9, xzr, x9, lt
    SB_N x9
    SB_S Lt_s
    b    Lst_out
2:  cmp  x9, #NFS_PLAY
    b.ne 4f
    SB_S Lt_dot
    ldr  x9, [x22, #G_START]
    ldr  x10, [x22, #G_SECS]
    add  x9, x9, x10
    subs x24, x9, x23
    csel x24, xzr, x24, lt
    bl   Lst_clock
    SB_S Lt_left
    SB_S Lt_you
    ldr  x9, [x22, #G_MYN]
    SB_N x9
    mov  x24, #0                          // the others: how many words, never which
3:  ldr  x9, [x22, #G_NPL]
    cmp  x24, x9
    b.hs Lst_out
    mov  x9, #PL_SIZE
    madd x23, x24, x9, x22
    add  x23, x23, #G_PL
    add  x24, x24, #1
    ldr  x9, [x23, #PL_ID]
    ldr  x10, [x22, #G_ME]
    cmp  x9, x10
    b.eq 3b
    SB_S Lt_dot
    mov  x0, x23
    bl   Lnt_nick
    mov  x9, x0
    SB_R x9
    SB_C ' '
    ldr  x9, [x23, #PL_CLAIMS]
    SB_N x9
    b    3b
4:  cmp  x9, #NFS_REVEAL
    b.ne 5f
    SB_S Lt_checking
    b    Lst_out
5:  SB_S Lt_scored                        // scored: the game so far, best first
    mov  x0, x22
    add  x1, sp, #96
    bl   _nfp_rank
    mov  x24, #0
6:  ldr  x9, [x22, #G_NPL]
    cmp  x24, x9
    b.hs Lst_out
    add  x9, sp, #96
    ldrb w9, [x9, x24]
    mov  x10, #PL_SIZE
    madd x23, x9, x10, x22
    add  x23, x23, #G_PL
    add  x24, x24, #1
    SB_S Lt_dot
    mov  x0, x22
    mov  x1, x23
    bl   Lnt_who
    mov  x9, x0
    SB_R x9
    SB_C ' '
    ldr  x9, [x23, #PL_SCORE]
    SB_N x9
    b    6b
Lst_out:
    mov  x0, x20
    LEAVE 32

// Lst_clock — append x24 seconds as m:ss (inside _nft_status)
Lst_clock:
    stp  x29, x30, [sp, #-16]!
    mov  x10, #60
    udiv x9, x24, x10
    msub x24, x9, x10, x24
    SB_N x9
    SB_C ':'
    cmp  x24, #10
    b.hs 1f
    SB_C '0'
1:  SB_N x24
    ldp  x29, x30, [sp], #16
    ret

// long _nft_board(const game *g, const char view[9], long row, char *buf, long cap)
//   one row of the grid in capitals, the centre letter in brackets: "T   O   O", "L  [G]  I"
.globl _nft_board
_nft_board:
    ENTER 16                              // [96] the letter
    mov  x22, x1
    mov  x23, x2
    mov  x19, x3
    mov  x21, x4
    mov  x20, #0
    cbz  x21, 9f
    strb wzr, [x19]
    cmp  x23, #2
    b.hi 9f
    mov  x9, #3
    mul  x23, x23, x9
    mov  x24, #0
1:  cmp  x24, #3
    b.hs 9f
    cbz  x24, 2f
    SB_S Lt_gap
2:  add  x9, x23, x24
    ldrb w10, [x22, x9]
    bic  w10, w10, #0x20
    str  x10, [sp, #96]
    cmp  x9, #4
    b.ne 3f
    SB_C '['
    ldr  x10, [sp, #96]
    SB_RB w10
    SB_C ']'
    b    4f
3:  SB_C ' '
    ldr  x10, [sp, #96]
    SB_RB w10
    SB_C ' '
4:  add  x24, x24, #1
    b    1b
9:  mov  x0, x20
    LEAVE 16

// long _nft_try(const game *g, long result, long points, const char *text, long len,
//   char *buf, long cap) — what a typed word got (_nfp_try's answer): "✓ TOOLING +4",
//   "✗ TOOLNG isn't in the word list", ...
.globl _nft_try
_nft_try:
    ENTER 16
    mov  x22, x0
    mov  x23, x1
    str  x2, [sp, #96]
    mov  x24, x3
    str  x4, [sp, #104]
    mov  x19, x5
    mov  x21, x6
    mov  x20, #0
    cbz  x21, Ltt_out
    strb wzr, [x19]
    ldr  x9, [sp, #104]                   // as typed, in capitals, 20 at most
    mov  x10, #20
    cmp  x9, x10
    csel x9, x10, x9, hi
    str  x9, [sp, #104]
    tbnz x23, #63, Ltt_bad
    SB_S Lt_tick
    add  x0, x22, #G_PUZ
    mov  x1, x23
    bl   _nf_word
    mov  x9, x0
    mov  x10, x1
    SB_W x9, x10
    SB_S Lt_plus
    ldr  x9, [sp, #96]
    SB_N x9
    b    Ltt_out
Ltt_bad:
    cmp  x23, #NF_NOTWORD
    b.ne 1f
    SB_S Lt_cross
    ldr  x10, [sp, #104]
    SB_W x24, x10
    SB_S Lt_notword
    b    Ltt_out
1:  cmp  x23, #NF_LENGTH
    b.ne 2f
    SB_S Lt_length
    b    Ltt_out
2:  cmp  x23, #NF_NOCENTRE
    b.ne 3f
    SB_S Lt_nocentre
    ldrb w9, [x22, #(G_PUZ + NP_CENTRE)]
    bic  w9, w9, #0x20
    SB_RB w9
    b    Ltt_out
3:  cmp  x23, #NF_TILES
    b.ne 4f
    SB_S Lt_cross
    ldr  x10, [sp, #104]
    SB_W x24, x10
    SB_S Lt_tiles
    b    Ltt_out
4:  cmp  x23, #NF_DUP
    b.ne 5f
    SB_S Lt_dot0
    ldr  x10, [sp, #104]
    SB_W x24, x10
    SB_S Lt_dup
    b    Ltt_out
5:  cmp  x23, #NF_HIDDEN
    b.ne 6f
    SB_S Lt_dot0
    ldr  x10, [sp, #104]
    SB_W x24, x10
    SB_S Lt_hidden
    b    Ltt_out
6:  cmp  x23, #NF_FULL
    b.ne 7f
    SB_S Lt_full
    b    Ltt_out
7:  SB_S Lt_closed
Ltt_out:
    mov  x0, x20
    LEAVE 16

// long _nft_result(const game *g, long k, char *buf, long cap) -> line k of the round's
//   results, or 0 after the last: 0 the nine-letter word; then each player, best first, with
//   the game score, the round's, and the words that checked out (★ first to find it, + nobody
//   else did); then the answers nobody found; then who won, after the last round
.globl _nft_result
_nft_result:
    ENTER 48                              // [96] ranking (12)  [112] k  [120] word  [128] length
    mov  x22, x0
    str  x1, [sp, #112]
    mov  x19, x2
    mov  x21, x3
    mov  x20, #0
    cbz  x21, Lrs_out
    strb wzr, [x19]
    ldr  x9, [x22, #G_STATE]
    cmp  x9, #NFS_DONE
    b.ne Lrs_out
    mov  x0, x22
    add  x1, sp, #96
    bl   _nfp_rank
    ldr  x23, [sp, #112]
    cbnz x23, Lrs_player
    SB_S Lt_round                         // 0. "Round 1 of 3: the nine-letter word was ..."
    ldr  x9, [x22, #G_ROUND]
    SB_N x9
    SB_S Lt_of
    ldr  x9, [x22, #G_ROUNDS]
    SB_N x9
    SB_S Lt_nine
    add  x9, x22, #(G_PUZ + NP_WORD)
    mov  x10, #9
    SB_W x9, x10
    SB_S Lt_legend
    b    Lrs_out
Lrs_player:
    ldr  x9, [x22, #G_NPL]
    cmp  x23, x9
    b.hi Lrs_missed
    sub  x10, x23, #1                     // "1. Anna 23 (+15): MOONLIGHT★ TOOLING★+ MOON"
    add  x9, sp, #96
    ldrb w24, [x9, x10]
    SB_N x23
    SB_S Lt_rank
    mov  x9, #PL_SIZE
    madd x1, x24, x9, x22
    add  x1, x1, #G_PL
    mov  x0, x22
    bl   Lnt_who
    mov  x9, x0
    SB_R x9
    SB_C ' '
    mov  x9, #PL_SIZE
    madd x23, x24, x9, x22
    add  x23, x23, #G_PL
    ldr  x9, [x23, #PL_SCORE]
    SB_N x9
    SB_S Lt_open
    ldr  x9, [x23, #PL_RSCORE]
    SB_N x9
    SB_S Lt_close
    ldr  x9, [x23, #PL_WORDS]
    cbnz x9, 1f
    SB_S Lt_nowords
    b    Lrs_out
1:  mov  x23, #0                          // each word this player found, alphabetical
2:  ldr  x9, [x22, #(G_PUZ + NP_N)]
    cmp  x23, x9
    b.hs Lrs_out
    add  x9, x22, #G_FIND
    ldrh w10, [x9, x23, lsl #1]
    lsr  w11, w10, w24
    tbz  w11, #0, 3f
    SB_C ' '
    add  x0, x22, #G_PUZ
    mov  x1, x23
    bl   _nf_word
    mov  x9, x0
    mov  x10, x1
    SB_W x9, x10
    add  x9, x22, #G_FIRST
    ldrh w10, [x9, x23, lsl #1]
    lsr  w10, w10, w24
    tbz  w10, #0, 4f
    SB_S Lt_star
4:  add  x9, x22, #G_FIND
    ldrh w10, [x9, x23, lsl #1]
    sub  w11, w10, #1
    tst  w10, w11
    b.ne 3f
    SB_C '+'
3:  add  x23, x23, #1
    b    2b
Lrs_missed:
    add  x9, x9, #1
    cmp  x23, x9
    b.ne Lrs_won
    SB_S Lt_missed                        // the answers nobody found
    mov  x24, #0                          // how many listed
    mov  x23, #0
1:  ldr  x9, [x22, #(G_PUZ + NP_N)]
    cmp  x23, x9
    b.hs 3f
    add  x9, x22, #G_FIND
    ldrh w10, [x9, x23, lsl #1]
    cbnz w10, 2f
    add  x0, x22, #G_PUZ
    mov  x1, x23
    bl   _nf_word
    tbz  w2, #0, 2f                       // answers only
    ldr  x9, [x22, #G_FAMILY]
    cbz  x9, 4f
    tbnz w2, #2, 2f
4:  stp  x0, x1, [sp, #120]
    SB_C ' '
    ldp  x9, x10, [sp, #120]
    SB_W x9, x10
    add  x24, x24, #1
2:  add  x23, x23, #1
    b    1b
3:  cbnz x24, Lrs_out
    mov  x20, #0
    strb wzr, [x19]
    SB_S Lt_allfound
    b    Lrs_out
Lrs_won:
    add  x9, x9, #1
    cmp  x23, x9
    b.ne Lrs_none
    ldr  x9, [x22, #G_ROUND]
    ldr  x10, [x22, #G_ROUNDS]
    cmp  x9, x10
    b.lo 1f
    SB_S Lt_over                          // "Game over: Anna wins with 41."
    ldrb w9, [sp, #96]
    mov  x10, #PL_SIZE
    madd x1, x9, x10, x22
    add  x1, x1, #G_PL
    mov  x23, x1
    mov  x0, x22
    bl   Lnt_who
    mov  x9, x0
    SB_R x9
    ldr  x9, [x23, #PL_ID]
    ldr  x10, [x22, #G_ME]
    ADRL x11, Lt_wins
    ADRL x12, Lt_win
    cmp  x9, x10
    csel x11, x12, x11, eq
    SB_R x11
    ldr  x9, [x23, #PL_SCORE]
    SB_N x9
    SB_C '.'
    b    Lrs_out
1:  SB_S Lt_next
    b    Lrs_out
Lrs_none:
    mov  x20, #0
    strb wzr, [x19]
Lrs_out:
    mov  x0, x20
    LEAVE 48

// long _nft_mine(const game *g, char *buf, long cap) — my words this round, in capitals,
//   alphabetical, separated by spaces
.globl _nft_mine
_nft_mine:
    ENTER 0
    mov  x22, x0
    mov  x19, x1
    mov  x21, x2
    mov  x20, #0
    cbz  x21, 9f
    strb wzr, [x19]
    mov  x23, #0
1:  ldr  x9, [x22, #(G_PUZ + NP_N)]
    cmp  x23, x9
    b.hs 9f
    add  x9, x22, #G_MINE
    ldrb w9, [x9, x23]
    cbz  w9, 2f
    cbz  x20, 3f
    SB_C ' '
3:  add  x0, x22, #G_PUZ
    mov  x1, x23
    bl   _nf_word
    mov  x9, x0
    mov  x10, x1
    SB_W x9, x10
2:  add  x23, x23, #1
    b    1b
9:  mov  x0, x20
    LEAVE 0

// long _nft_players(const game *g, char *buf, long cap) — "name\twords this round\tscore\n"
//   for each player, best game score first; "you" for us
.globl _nft_players
_nft_players:
    ENTER 32                              // [96] ranking
    mov  x22, x0
    mov  x19, x1
    mov  x21, x2
    mov  x20, #0
    cbz  x21, 9f
    strb wzr, [x19]
    mov  x0, x22
    add  x1, sp, #96
    bl   _nfp_rank
    mov  x24, #0
1:  ldr  x9, [x22, #G_NPL]
    cmp  x24, x9
    b.hs 9f
    add  x9, sp, #96
    ldrb w9, [x9, x24]
    mov  x10, #PL_SIZE
    madd x23, x9, x10, x22
    add  x23, x23, #G_PL
    mov  x0, x22
    mov  x1, x23
    bl   Lnt_who
    mov  x9, x0
    SB_R x9
    SB_C 9
    ldr  x9, [x23, #PL_CLAIMS]
    ldr  x10, [x23, #PL_ID]               // ours: the words we found (the claims are ours too)
    ldr  x11, [x22, #G_ME]
    cmp  x10, x11
    b.ne 2f
    ldr  x9, [x22, #G_MYN]
2:  SB_N x9
    SB_C 9
    ldr  x9, [x23, #PL_SCORE]
    SB_N x9
    SB_C 10
    add  x24, x24, #1
    b    1b
9:  mov  x0, x20
    LEAVE 32

// ---------------------------------------------------------------------------
// leaves

// Lnt_who(x0 g, x1 player) -> x0 "you" for us, else the nick (leaf)
Lnt_who:
    ldr  x9, [x1, #PL_ID]
    ldr  x10, [x0, #G_ME]
    cmp  x9, x10
    b.ne 1f
    ADRL x0, Lt_you_name
    ret
1:  mov  x0, x1
    b    Lnt_nick

// Lnt_nick(x0 player) -> x0 its nick, "?" if not known yet (leaf)
Lnt_nick:
    ldrb w9, [x0, #PL_NICK]
    cbz  w9, 1f
    add  x0, x0, #PL_NICK
    ret
1:  ADRL x0, Lt_unknown
    ret

// Lsb_s(x0 buf, x1 pos, x2 cap, x3 string) -> x1 the new length; NUL-terminated
Lsb_s:
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

// Lsb_c(x0 buf, x1 pos, x2 cap, x3 byte) -> x1
Lsb_c:
    add  x10, x1, #1
    cmp  x10, x2
    b.hs 1f
    strb w3, [x0, x1]
    strb wzr, [x0, x10]
    mov  x1, x10
1:  ret

// Lsb_w(x0 buf, x1 pos, x2 cap, x3 letters, x4 length) -> x1; a-z in capitals
Lsb_w:
    mov  x9, #0
1:  cmp  x9, x4
    b.hs 3f
    add  x10, x1, #1
    cmp  x10, x2
    b.hs 3f
    ldrb w11, [x3, x9]
    sub  w12, w11, #'a'
    cmp  w12, #25
    b.hi 2f
    sub  w11, w11, #0x20
2:  strb w11, [x0, x1]
    strb wzr, [x0, x10]
    mov  x1, x10
    add  x9, x9, #1
    b    1b
3:  ret

// Lsb_n(x0 buf, x1 pos, x2 cap, x3 number) -> x1; in decimal
Lsb_n:
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
.section __TEXT,__cstring,cstring_literals
Lt_lobby:       .asciz "Ninefold \302\267 waiting for players to join \302\267 the host types start"
Lt_round:       .asciz "Round "
Lt_of:          .asciz " of "
Lt_starts:      .asciz " \302\267 starts in "
Lt_s:           .asciz " s"
Lt_dot:         .asciz " \302\267 "
Lt_dot0:        .asciz "\302\267 "
Lt_left:        .asciz " left"
Lt_you:         .asciz " \302\267 you "
Lt_you_name:    .asciz "you"
Lt_unknown:     .asciz "?"
Lt_checking:    .asciz " \302\267 time! checking words\342\200\246"
Lt_scored:      .asciz " \302\267 scored"
Lt_gap:         .asciz "  "
Lt_tick:        .asciz "\342\234\223 "
Lt_cross:       .asciz "\342\234\227 "
Lt_plus:        .asciz " +"
Lt_notword:     .asciz " isn\342\200\231t in Ninefold\342\200\231s word list"
Lt_length:      .asciz "\342\234\227 Words have 4 to 9 letters"
Lt_nocentre:    .asciz "\342\234\227 Every word uses the centre letter, "
Lt_tiles:       .asciz " uses letters that aren\342\200\231t on the tiles (each tile once)"
Lt_dup:         .asciz ": you have it already"
Lt_hidden:      .asciz " is left out: the family filter is on"
Lt_full:        .asciz "\302\267 That\342\200\231s the most words one round takes"
Lt_closed:      .asciz "\302\267 No round is being played"
Lt_nine:        .asciz ": the nine-letter word was "
Lt_legend:      .asciz ". \342\230\205 first to find it, + nobody else did"
Lt_rank:        .asciz ". "
Lt_open:        .asciz " (+"
Lt_close:       .asciz "):"
Lt_nowords:     .asciz ": no words"
Lt_star:        .asciz "\342\230\205"
Lt_missed:      .asciz "Nobody found:"
Lt_allfound:    .asciz "Every answer was found."
Lt_over:        .asciz "Game over: "
Lt_wins:        .asciz " wins with "
Lt_win:         .asciz " win with "
Lt_next:        .asciz "Next round in a few seconds."
