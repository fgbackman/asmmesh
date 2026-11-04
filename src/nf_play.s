// nf_play.s — a Ninefold game, pure (no globals, no system calls): rounds started by the
// host's START, claims (word length and a commitment, never the word), reveals checked
// against the claims, and scores that come out the same on every device. nf_mesh.s moves
// the packets and draws the screens; tools/qemu/run.sh runs the self-tests (200-203), in
// which two devices play a round and a third tries to cheat.
.include "macros.inc"
.include "nf_defs.inc"

.macro NFOK cond                          // x20 &= (flags say \cond)
    cset x9, \cond
    and  x20, x20, x9
.endm

.macro NFK2 reg, v                        // a constant up to 32 bits
    movz \reg, #((\v) & 0xffff)
    movk \reg, #(((\v) >> 16) & 0xffff), lsl #16
.endm

.macro NFK reg, v                         // a 64-bit constant
    movz \reg, #((\v) & 0xffff)
    movk \reg, #(((\v) >> 16) & 0xffff), lsl #16
    movk \reg, #(((\v) >> 32) & 0xffff), lsl #32
    movk \reg, #(((\v) >> 48) & 0xffff), lsl #48
.endm

.text
.p2align 2

// long _nfp_pkt_start(out, game, round, rounds, secs, seed, start, family) -> its length
.globl _nfp_pkt_start
_nfp_pkt_start:
    ENTER 0
    mov  x19, x0
    mov  w9, #'N'
    strb w9, [x19]
    mov  w9, #NK_START
    strb w9, [x19, #1]
    stur w1, [x19, #2]
    strb w2, [x19, #6]
    strb w3, [x19, #7]
    sturh w4, [x19, #8]
    stur x5, [x19, #10]
    stur w6, [x19, #18]
    strb w7, [x19, #30]
    add  x0, x19, #22
    bl   _nf_hash
    mov  x0, #NK_START_LEN
    LEAVE 0

// long _nfp_start_in(game *g, uint64 me, uint64 sender, const uint8 *pkt, long len)
//   -> 1 a new round is set (state WAIT), 0 one we have, -1 not taken, -2 other word lists.
//   A new game is taken only while none is being played; a game's later rounds only from
//   whoever started it. Scores carry over from round to round.
.globl _nfp_start_in
_nfp_start_in:
    ENTER 32                              // [96] our lists' fingerprint
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    cmp  x23, #NK_START_LEN
    b.lo Lsi_bad
    ldrb w9, [x22]
    cmp  w9, #'N'
    b.ne Lsi_bad
    ldrb w9, [x22, #1]
    cmp  w9, #NK_START
    b.ne Lsi_bad
    ldrb w10, [x22, #6]                   // round 1..rounds, rounds 1..5
    ldrb w11, [x22, #7]
    cbz  w10, Lsi_bad
    cmp  w10, w11
    b.hi Lsi_bad
    cmp  w11, #5
    b.hi Lsi_bad
    ldurh w12, [x22, #8]                  // 30 s to 15 minutes
    cmp  w12, #30
    b.lo Lsi_bad
    cmp  w12, #900
    b.hi Lsi_bad
    ldrb w13, [x22, #30]
    cmp  w13, #1
    b.hi Lsi_bad
    add  x0, sp, #96
    bl   _nf_hash
    ldr  x9, [sp, #96]
    ldur x10, [x22, #22]
    cmp  x9, x10
    b.ne Lsi_lists
    ldur w24, [x22, #2]                   // the game's id
    ldr  x9, [x19, #G_STATE]
    cbz  x9, Lsi_new
    ldr  x10, [x19, #G_GID]
    cmp  x10, x24
    b.ne Lsi_other
    ldr  x10, [x19, #G_HOST]              // only its host moves it on
    cmp  x10, x21
    b.ne Lsi_bad
    ldrb w10, [x22, #6]
    ldr  x11, [x19, #G_ROUND]
    cmp  x10, x11
    b.ls Lsi_have
    b    Lsi_round
Lsi_other:                                // another game: only once ours isn't being played
    cmp  x9, #NFS_WAIT
    b.lo Lsi_new
    cmp  x9, #NFS_DONE
    b.lo Lsi_bad
Lsi_new:
    str  xzr, [x19, #G_NPL]
    add  x9, x19, #G_PL
    mov  x10, #0
1:  str  xzr, [x9, x10]
    add  x10, x10, #8
    cmp  x10, #(NF_PLAYERS * PL_SIZE)
    b.lo 1b
Lsi_round:
    str  x24, [x19, #G_GID]
    str  x21, [x19, #G_HOST]
    str  x20, [x19, #G_ME]
    ldrb w9, [x22, #6]
    str  x9, [x19, #G_ROUND]
    ldrb w9, [x22, #7]
    str  x9, [x19, #G_ROUNDS]
    ldurh w9, [x22, #8]
    str  x9, [x19, #G_SECS]
    ldur x9, [x22, #10]
    str  x9, [x19, #G_SEED]
    ldur w9, [x22, #18]
    str  x9, [x19, #G_START]
    ldrb w9, [x22, #30]
    str  x9, [x19, #G_FAMILY]
    ldr  x9, [sp, #96]
    str  x9, [x19, #G_HASH]
    str  xzr, [x19, #G_NCL]
    str  xzr, [x19, #G_MYN]
    add  x9, x19, #G_MINE                 // found, checked, first: all cleared
    mov  x10, #0
2:  str  xzr, [x9, x10]
    add  x10, x10, #8
    cmp  x10, #(G_PL - G_MINE)
    b.lo 2b
    mov  x10, #0                          // and each player's round
3:  ldr  x11, [x19, #G_NPL]
    cmp  x10, x11
    b.hs 4f
    mov  x12, #PL_SIZE
    madd x12, x10, x12, x19
    add  x12, x12, #G_PL
    str  xzr, [x12, #PL_CLAIMS]
    str  xzr, [x12, #PL_RSCORE]
    str  xzr, [x12, #PL_WORDS]
    str  xzr, [x12, #PL_REVEALED]
    stp  xzr, xzr, [x12, #PL_SALT]
    add  x10, x10, #1
    b    3b
4:  ldr  x0, [x19, #G_SEED]
    add  x1, x19, #G_PUZ
    bl   _nf_puzzle
    tbnz x0, #63, Lsi_nopuz
    mov  x0, x19                          // the host and we are players
    mov  x1, x21
    mov  x2, #0
    mov  x3, #0
    bl   _nfp_player
    mov  x0, x19
    mov  x1, x20
    mov  x2, #0
    mov  x3, #0
    bl   _nfp_player
    mov  x9, #NFS_WAIT
    str  x9, [x19, #G_STATE]
    mov  x0, #1
    LEAVE 32
Lsi_nopuz:
    str  xzr, [x19, #G_STATE]
Lsi_bad:
    mov  x0, #-1
    LEAVE 32
Lsi_have:
    mov  x0, #0
    LEAVE 32
Lsi_lists:
    mov  x0, #-2
    LEAVE 32

// long _nfp_player(game *g, uint64 id, const char *nick, long nlen) -> the player's slot
//   (added if new; the nick, if given, kept up to date), or -1 when 12 are playing
.globl _nfp_player
_nfp_player:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, #0
1:  ldr  x9, [x19, #G_NPL]
    cmp  x23, x9
    b.hs 2f
    mov  x10, #PL_SIZE
    madd x24, x23, x10, x19
    add  x24, x24, #G_PL
    ldr  x10, [x24, #PL_ID]
    cmp  x10, x20
    b.eq Lpp_nick
    add  x23, x23, #1
    b    1b
2:  cmp  x9, #NF_PLAYERS
    b.hs Lpp_full
    add  x10, x9, #1
    str  x10, [x19, #G_NPL]
    mov  x10, #PL_SIZE
    madd x24, x23, x10, x19
    add  x24, x24, #G_PL
    mov  x10, #0
3:  str  xzr, [x24, x10]
    add  x10, x10, #8
    cmp  x10, #PL_SIZE
    b.lo 3b
    str  x20, [x24, #PL_ID]
Lpp_nick:
    cbz  x21, Lpp_done
    cbz  x22, Lpp_done
    mov  x9, #23
    cmp  x22, x9
    csel x22, x9, x22, hi
    add  x11, x24, #PL_NICK
    mov  x9, #0
4:  cmp  x9, x22
    b.hs 5f
    ldrb w10, [x21, x9]
    cbz  w10, 5f
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    4b
5:  strb wzr, [x11, x9]
Lpp_done:
    mov  x0, x23
    LEAVE 0
Lpp_full:
    mov  x0, #-1
    LEAVE 0

// long _nfp_try(game *g, const char *text, long len, long now, uint8 out[28]) -> x0 the word's
//   index and x1 its points, its CLAIM packet in out; or x0 one of _nf_find's answers,
//   NF_DUP, NF_CLOSED (no round being played), NF_HIDDEN (family filter), NF_FULL
.globl _nfp_try
_nfp_try:
    ENTER 16                              // [96] the word's length  [104] our slot
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    ldr  x9, [x19, #G_STATE]
    cmp  x9, #NFS_PLAY
    b.ne Ltr_closed
    ldr  x9, [x19, #G_START]
    ldr  x10, [x19, #G_SECS]
    add  x9, x9, x10
    cmp  x22, x9
    b.hs Ltr_closed
    add  x0, x19, #G_PUZ
    mov  x1, x20
    mov  x2, x21
    bl   _nf_find
    tbnz x0, #63, Ltr_ret
    mov  x24, x0
    ldr  x9, [x19, #G_FAMILY]
    cbz  x9, 1f
    tbnz w1, #2, Ltr_hidden               // NFF_FAMILY
1:  add  x9, x19, #G_MINE
    ldrb w10, [x9, x24]
    cbnz w10, Ltr_dup
    mov  x0, x19
    ldr  x1, [x19, #G_ME]
    mov  x2, #0
    mov  x3, #0
    bl   _nfp_player
    tbnz x0, #63, Ltr_full
    str  x0, [sp, #104]
    mov  x9, #PL_SIZE
    madd x9, x0, x9, x19
    add  x9, x9, #G_PL
    ldr  x10, [x9, #PL_CLAIMS]
    cmp  x10, #NF_PLCL
    b.hs Ltr_full
    ldr  x10, [x19, #G_NCL]
    cmp  x10, #NF_CLMAX
    b.hs Ltr_full
    add  x9, x19, #G_MINE
    mov  w10, #1
    strb w10, [x9, x24]
    ldr  x9, [x19, #G_MYN]
    add  x9, x9, #1
    str  x9, [x19, #G_MYN]
    add  x0, x19, #G_PUZ
    mov  x1, x24
    bl   _nf_word
    str  x1, [sp, #96]
    mov  w9, #'N'
    strb w9, [x23]
    mov  w9, #NK_CLAIM
    strb w9, [x23, #1]
    ldr  x9, [x19, #G_GID]
    stur w9, [x23, #2]
    ldr  x9, [x19, #G_ROUND]
    strb w9, [x23, #6]
    ldr  x9, [sp, #96]
    strb w9, [x23, #7]
    stur w22, [x23, #8]
    add  x0, x19, #G_SALT
    ldr  x1, [x19, #G_ME]
    ldr  x2, [x19, #G_ROUND]
    mov  x3, x24
    add  x4, x23, #12
    bl   _nf_commit
    mov  x0, x19                          // our own claim, as everyone else will have it
    ldr  x1, [sp, #104]
    ldr  x2, [sp, #96]
    mov  x3, x22
    add  x4, x23, #12
    bl   Lpl_claim_add
    ldr  x0, [sp, #96]
    bl   _nf_points
    mov  x1, x0
    mov  x0, x24
    LEAVE 16
Ltr_closed:
    mov  x0, #NF_CLOSED
    b    Ltr_ret
Ltr_hidden:
    mov  x0, #NF_HIDDEN
    b    Ltr_ret
Ltr_dup:
    mov  x0, #NF_DUP
    b    Ltr_ret
Ltr_full:
    mov  x0, #NF_FULL
Ltr_ret:
    mov  x1, #0
    LEAVE 16

// long _nfp_claim_in(game *g, uint64 sender, const char *nick, long nlen, const uint8 *pkt,
//   long len, long now) -> the sender's slot, or -1 if not taken (another game or round,
//   too late, a bad length, too many). Its time is kept within the round.
.globl _nfp_claim_in
_nfp_claim_in:
    ENTER 16                              // [96] now, then the time  [104] the length
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    mov  x24, x5
    str  x6, [sp, #96]
    cmp  x24, #NK_CLAIM_LEN
    b.lo Lci_bad
    ldrb w9, [x23]
    cmp  w9, #'N'
    b.ne Lci_bad
    ldrb w9, [x23, #1]
    cmp  w9, #NK_CLAIM
    b.ne Lci_bad
    ldur w9, [x23, #2]
    ldr  x10, [x19, #G_GID]
    cmp  x9, x10
    b.ne Lci_bad
    ldrb w9, [x23, #6]
    ldr  x10, [x19, #G_ROUND]
    cmp  x9, x10
    b.ne Lci_bad
    ldr  x9, [x19, #G_STATE]
    cmp  x9, #NFS_WAIT
    b.lo Lci_bad
    cmp  x9, #NFS_REVEAL
    b.hi Lci_bad
    ldr  x9, [x19, #G_START]
    ldr  x10, [x19, #G_SECS]
    add  x10, x9, x10                     // the round's end
    ldr  x11, [sp, #96]
    add  x12, x10, #NF_GRACE
    cmp  x11, x12
    b.hi Lci_bad
    ldr  x11, [x19, #G_ME]
    cmp  x20, x11
    b.eq Lci_bad
    ldrb w11, [x23, #7]
    sub  w12, w11, #4
    cmp  w12, #5
    b.hi Lci_bad
    ldur w12, [x23, #8]
    cmp  x12, x9
    csel x12, x9, x12, lo
    cmp  x12, x10
    csel x12, x10, x12, hi
    str  x12, [sp, #96]
    str  x11, [sp, #104]
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, x22
    bl   _nfp_player
    tbnz x0, #63, Lci_bad
    mov  x20, x0
    mov  x9, #PL_SIZE
    madd x9, x20, x9, x19
    add  x9, x9, #G_PL
    ldr  x10, [x9, #PL_CLAIMS]
    cmp  x10, #NF_PLCL
    b.hs Lci_bad
    ldr  x10, [x19, #G_NCL]
    cmp  x10, #NF_CLMAX
    b.hs Lci_bad
    mov  x0, x19
    mov  x1, x20
    ldr  x2, [sp, #104]
    ldr  x3, [sp, #96]
    add  x4, x23, #12
    bl   Lpl_claim_add
    mov  x0, x20
    LEAVE 16
Lci_bad:
    mov  x0, #-1
    LEAVE 16

// long _nfp_pkt_reveal(game *g, long part, uint8 *out) -> the length of our REVEAL's part
//   (80 words each; one part even with none), or 0 past the last
.globl _nfp_pkt_reveal
_nfp_pkt_reveal:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ldr  x9, [x19, #G_MYN]
    add  x10, x9, #(NK_REV_MAX - 1)
    mov  x11, #NK_REV_MAX
    udiv x10, x10, x11
    cmp  x10, #0
    csinc x10, x10, xzr, ne
    cmp  x20, x10
    b.hs Lpr_none
    mov  w9, #'N'
    strb w9, [x21]
    mov  w9, #NK_REVEAL
    strb w9, [x21, #1]
    ldr  x9, [x19, #G_GID]
    stur w9, [x21, #2]
    ldr  x9, [x19, #G_ROUND]
    strb w9, [x21, #6]
    strb w20, [x21, #7]
    strb w10, [x21, #8]
    ldp  x9, x10, [x19, #G_SALT]
    add  x11, x21, #9
    stp  x9, x10, [x11]
    mov  x11, #NK_REV_MAX
    mul  x22, x20, x11                    // words to skip
    mov  x9, #0                           // word index
    mov  x10, #0                          // ours seen
    mov  x12, #0                          // in this part
1:  cmp  x9, #256
    b.hs 3f
    add  x13, x19, #G_MINE
    ldrb w14, [x13, x9]
    cbz  w14, 2f
    cmp  x10, x22
    add  x10, x10, #1
    b.lo 2f
    cmp  x12, #NK_REV_MAX
    b.hs 3f
    add  x13, x21, #NK_REV_HDR
    strb w9, [x13, x12]
    add  x12, x12, #1
2:  add  x9, x9, #1
    b    1b
3:  strb w12, [x21, #25]
    add  x0, x12, #NK_REV_HDR
    LEAVE 0
Lpr_none:
    mov  x0, #0
    LEAVE 0

// long _nfp_reveal_in(game *g, uint64 sender, const uint8 *pkt, long len) -> how many of its
//   words check out (a claim by that player, of that length, with that commitment, not used
//   yet), or -1 if not taken (another game or round, a salt unlike its first part's)
.globl _nfp_reveal_in
_nfp_reveal_in:
    ENTER 64                              // [96] commitment  [112] length  [120] i  [128] n
    mov  x19, x0                          //   [136] checked  [144] word index
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    cmp  x22, #NK_REV_HDR
    b.lo Lri_bad
    ldrb w9, [x21]
    cmp  w9, #'N'
    b.ne Lri_bad
    ldrb w9, [x21, #1]
    cmp  w9, #NK_REVEAL
    b.ne Lri_bad
    ldur w9, [x21, #2]
    ldr  x10, [x19, #G_GID]
    cmp  x9, x10
    b.ne Lri_bad
    ldrb w9, [x21, #6]
    ldr  x10, [x19, #G_ROUND]
    cmp  x9, x10
    b.ne Lri_bad
    ldr  x9, [x19, #G_STATE]
    cmp  x9, #NFS_PLAY
    b.lo Lri_bad
    cmp  x9, #NFS_REVEAL
    b.hi Lri_bad
    ldrb w9, [x21, #25]
    cmp  w9, #NK_REV_MAX
    b.hi Lri_bad
    add  x10, x9, #NK_REV_HDR
    cmp  x22, x10
    b.lo Lri_bad
    str  x9, [sp, #128]
    str  xzr, [sp, #120]
    str  xzr, [sp, #136]
    mov  x0, x19
    mov  x1, x20
    bl   Lpl_find
    tbnz x0, #63, Lri_done                // made no claims: nothing to check
    mov  x23, x0
    mov  x9, #PL_SIZE
    madd x24, x23, x9, x19
    add  x24, x24, #G_PL
    add  x12, x21, #9
    ldp  x10, x11, [x12]
    ldr  x9, [x24, #PL_REVEALED]
    cbnz x9, 1f
    stp  x10, x11, [x24, #PL_SALT]
    mov  x9, #1
    str  x9, [x24, #PL_REVEALED]
    b    Lri_loop
1:  ldp  x13, x14, [x24, #PL_SALT]        // every part: the same salt
    cmp  x10, x13
    ccmp x11, x14, #0, eq
    b.ne Lri_bad
Lri_loop:
    ldr  x9, [sp, #120]
    ldr  x10, [sp, #128]
    cmp  x9, x10
    b.hs Lri_done
    add  x10, x21, #NK_REV_HDR
    ldrb w11, [x10, x9]
    str  x11, [sp, #144]
    ldr  x12, [x19, #(G_PUZ + NP_N)]
    cmp  x11, x12
    b.hs Lri_next
    add  x12, x19, #G_FIND                // this player's already
    ldrh w13, [x12, x11, lsl #1]
    lsr  w13, w13, w23
    tbnz w13, #0, Lri_next
    add  x0, x19, #G_PUZ
    mov  x1, x11
    bl   _nf_word
    str  x1, [sp, #112]
    ldr  x9, [x19, #G_FAMILY]
    cbz  x9, 2f
    tbnz w2, #2, Lri_next
2:  add  x0, x24, #PL_SALT
    mov  x1, x20
    ldr  x2, [x19, #G_ROUND]
    ldr  x3, [sp, #144]
    add  x4, sp, #96
    bl   _nf_commit
    ldp  x13, x14, [sp, #96]
    mov  x9, #0
3:  ldr  x10, [x19, #G_NCL]
    cmp  x9, x10
    b.hs Lri_next
    mov  x11, #CL_SIZE
    madd x11, x9, x11, x19
    add  x11, x11, #G_CL
    ldrb w12, [x11, #CL_SLOT]
    cmp  x12, x23
    b.ne 4f
    ldrb w12, [x11, #CL_USED]
    cbnz w12, 4f
    ldrb w12, [x11, #CL_LEN]
    ldr  x15, [sp, #112]
    cmp  x12, x15
    b.ne 4f
    ldr  x12, [x11, #CL_COMMIT]
    cmp  x12, x13
    b.ne 4f
    ldr  x12, [x11, #(CL_COMMIT + 8)]
    cmp  x12, x14
    b.ne 4f
    mov  w12, #1
    strb w12, [x11, #CL_USED]
    ldr  x12, [sp, #144]
    strb w12, [x11, #CL_IDX]
    add  x15, x19, #G_FIND
    ldrh w10, [x15, x12, lsl #1]
    mov  w9, #1
    lsl  w9, w9, w23
    orr  w10, w10, w9
    strh w10, [x15, x12, lsl #1]
    ldr  x9, [sp, #136]
    add  x9, x9, #1
    str  x9, [sp, #136]
    b    Lri_next
4:  add  x9, x9, #1
    b    3b
Lri_next:
    ldr  x9, [sp, #120]
    add  x9, x9, #1
    str  x9, [sp, #120]
    b    Lri_loop
Lri_done:
    ldr  x0, [sp, #136]
    LEAVE 64
Lri_bad:
    mov  x0, #-1
    LEAVE 64

// long _nfp_tick(game *g, long now) -> 1 the round began, 2 it ended (send our REVEAL),
//   3 it is scored; 0 nothing new
.globl _nfp_tick
_nfp_tick:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ldr  x9, [x19, #G_STATE]
    ldr  x10, [x19, #G_START]
    ldr  x11, [x19, #G_SECS]
    add  x11, x10, x11
    cmp  x9, #NFS_WAIT
    b.ne 1f
    cmp  x20, x10
    b.lo Ltk_none
    mov  x9, #NFS_PLAY
    str  x9, [x19, #G_STATE]
    mov  x0, #1
    LEAVE 0
1:  cmp  x9, #NFS_PLAY
    b.ne 2f
    cmp  x20, x11
    b.lo Ltk_none
    mov  x9, #NFS_REVEAL
    str  x9, [x19, #G_STATE]
    mov  x0, #2
    LEAVE 0
2:  cmp  x9, #NFS_REVEAL
    b.ne Ltk_none
    add  x12, x11, #NF_REVEAL_WAIT
    cmp  x20, x12
    b.lo Ltk_none
    mov  x0, x19
    bl   _nfp_score
    mov  x9, #NFS_DONE
    str  x9, [x19, #G_STATE]
    mov  x0, #3
    LEAVE 0
Ltk_none:
    mov  x0, #0
    LEAVE 0

// void _nfp_score(game *g) — the round's points: each checked word its length's points; +1
//   to whoever claimed it first (within 2 s of the earliest claim); +2 if nobody else found
//   it. Only the claims' signed times and the reveals count, so every device agrees.
.globl _nfp_score
_nfp_score:
    ENTER 0
    mov  x19, x0
    mov  x9, #0
1:  ldr  x10, [x19, #G_NPL]
    cmp  x9, x10
    b.hs 2f
    mov  x11, #PL_SIZE
    madd x11, x9, x11, x19
    add  x11, x11, #G_PL
    str  xzr, [x11, #PL_RSCORE]
    str  xzr, [x11, #PL_WORDS]
    add  x9, x9, #1
    b    1b
2:  add  x9, x19, #G_FIRST
    mov  x10, #0
3:  str  xzr, [x9, x10]
    add  x10, x10, #8
    cmp  x10, #512
    b.lo 3b
    mov  x20, #0
Lsc_w:
    ldr  x9, [x19, #(G_PUZ + NP_N)]
    cmp  x20, x9
    b.hs Lsc_tot
    add  x9, x19, #G_FIND
    ldrh w21, [x9, x20, lsl #1]
    cbz  w21, Lsc_next
    mov  x22, #-1                         // the earliest claim of it
    mov  x9, #0
4:  ldr  x10, [x19, #G_NCL]
    cmp  x9, x10
    b.hs 5f
    mov  x11, #CL_SIZE
    madd x11, x9, x11, x19
    add  x11, x11, #G_CL
    add  x9, x9, #1
    ldrb w12, [x11, #CL_USED]
    cbz  w12, 4b
    ldrb w12, [x11, #CL_IDX]
    cmp  x12, x20
    b.ne 4b
    ldr  w12, [x11, #CL_TIME]
    cmp  x12, x22
    csel x22, x12, x22, lo
    b    4b
5:  add  x0, x19, #G_PUZ
    mov  x1, x20
    bl   _nf_word
    mov  x0, x1
    bl   _nf_points
    mov  x23, x0
    sub  w9, w21, #1                      // found by one player only
    tst  w21, w9
    cset x24, eq
    add  x22, x22, #NF_FIRST_WINDOW
    mov  x9, #0
6:  ldr  x10, [x19, #G_NCL]
    cmp  x9, x10
    b.hs Lsc_next
    mov  x11, #CL_SIZE
    madd x11, x9, x11, x19
    add  x11, x11, #G_CL
    add  x9, x9, #1
    ldrb w12, [x11, #CL_USED]
    cbz  w12, 6b
    ldrb w12, [x11, #CL_IDX]
    cmp  x12, x20
    b.ne 6b
    mov  x13, x23
    ldrb w14, [x11, #CL_SLOT]
    ldr  w12, [x11, #CL_TIME]
    cmp  x12, x22
    b.hi 7f
    add  x13, x13, #1
    add  x15, x19, #G_FIRST
    ldrh w10, [x15, x20, lsl #1]
    mov  w12, #1
    lsl  w12, w12, w14
    orr  w10, w10, w12
    strh w10, [x15, x20, lsl #1]
7:  add  x13, x13, x24, lsl #1
    mov  x12, #PL_SIZE
    madd x12, x14, x12, x19
    add  x12, x12, #G_PL
    ldr  x10, [x12, #PL_RSCORE]
    add  x10, x10, x13
    str  x10, [x12, #PL_RSCORE]
    ldr  x10, [x12, #PL_WORDS]
    add  x10, x10, #1
    str  x10, [x12, #PL_WORDS]
    b    6b
Lsc_next:
    add  x20, x20, #1
    b    Lsc_w
Lsc_tot:
    mov  x9, #0
8:  ldr  x10, [x19, #G_NPL]
    cmp  x9, x10
    b.hs 9f
    mov  x11, #PL_SIZE
    madd x11, x9, x11, x19
    add  x11, x11, #G_PL
    ldr  x10, [x11, #PL_SCORE]
    ldr  x12, [x11, #PL_RSCORE]
    add  x10, x10, x12
    str  x10, [x11, #PL_SCORE]
    add  x9, x9, #1
    b    8b
9:  LEAVE 0

// long _nfp_rank(const game *g, uint8 out[12]) -> players; out: their slots, best game score
//   first (ties: whoever joined first) (leaf)
.globl _nfp_rank
_nfp_rank:
    ldr  x9, [x0, #G_NPL]
    mov  x10, #0
1:  cmp  x10, x9
    b.hs 2f
    strb w10, [x1, x10]
    add  x10, x10, #1
    b    1b
2:  mov  x10, #0                          // insertion sort
3:  add  x10, x10, #1
    cmp  x10, x9
    b.hs 6f
    mov  x11, x10
4:  cbz  x11, 3b
    sub  x12, x11, #1
    ldrb w13, [x1, x12]
    ldrb w14, [x1, x11]
    mov  x15, #PL_SIZE
    madd x16, x13, x15, x0
    ldr  x16, [x16, #(G_PL + PL_SCORE)]
    madd x17, x14, x15, x0
    ldr  x17, [x17, #(G_PL + PL_SCORE)]
    cmp  x17, x16
    b.le 3b
    strb w14, [x1, x12]
    strb w13, [x1, x11]
    mov  x11, x12
    b    4b
6:  mov  x0, x9
    ret

// long _nfp_slot(const game *g, uint64 id) -> the player's slot, or -1 (leaf)
.globl _nfp_slot
_nfp_slot:
    b    Lpl_find

// ---------------------------------------------------------------------------
// leaves

// Lpl_find(x0 g, x1 id) -> x0 slot or -1
Lpl_find:
    ldr  x9, [x0, #G_NPL]
    mov  x10, #0
1:  cmp  x10, x9
    b.hs 2f
    mov  x11, #PL_SIZE
    madd x11, x10, x11, x0
    ldr  x11, [x11, #(G_PL + PL_ID)]
    cmp  x11, x1
    b.eq 3f
    add  x10, x10, #1
    b    1b
2:  mov  x0, #-1
    ret
3:  mov  x0, x10
    ret

// Lpl_claim_add(x0 g, x1 slot, x2 length, x3 time, x4 commitment) — room checked already
Lpl_claim_add:
    ldr  x9, [x0, #G_NCL]
    mov  x10, #CL_SIZE
    madd x10, x9, x10, x0
    add  x10, x10, #G_CL
    strb w1, [x10, #CL_SLOT]
    strb w2, [x10, #CL_LEN]
    strb wzr, [x10, #CL_USED]
    strb wzr, [x10, #CL_IDX]
    str  w3, [x10, #CL_TIME]
    ldp  x11, x12, [x4]
    stp  x11, x12, [x10, #CL_COMMIT]
    add  x9, x9, #1
    str  x9, [x0, #G_NCL]
    mov  x11, #PL_SIZE
    madd x11, x1, x11, x0
    add  x11, x11, #G_PL
    ldr  x12, [x11, #PL_CLAIMS]
    add  x12, x12, #1
    str  x12, [x11, #PL_CLAIMS]
    ret

// ---------------------------------------------------------------------------
// self-tests 200-203, called from test.s: Ann (host) and Bea play a round on two devices;
// Cat tries to cheat on Ann's

.set T0,        1000000
.set ANN,       0xA1
.set BEA,       0xB2
.set CAT,       0xC3

.globl _nf_play_selftest
_nf_play_selftest:
    // [96] Ann's game  [104] Bea's  [112] START (32)  [144] Bea's claim  [176] Ann's
    // [208] Ann's 2nd  [240] Ann's reveal (112)  [352] Bea's (112)  [464] scratch (32)
    // [496] Ann's 2nd word's index  [504] its length
    ENTER 512
    mov  x19, #0
    mov  x0, #1
    mov  x1, #G_SIZE
    bl   _calloc
    str  x0, [sp, #96]
    mov  x0, #1
    mov  x1, #G_SIZE
    bl   _calloc
    str  x0, [sp, #104]
    ldr  x9, [sp, #96]
    cbz  x9, Lpt_nomem
    ldr  x9, [sp, #104]
    cbz  x9, Lpt_nomem

    // 200. START: built, taken once, a copy changes nothing, other lists and bad ones refused;
    //      no words before the start; the round begins on time
    mov  x20, #1
    add  x0, sp, #112
    mov  x1, #0x1234
    mov  x2, #1
    mov  x3, #2
    mov  x4, #120
    NFK  x5, 0x0123456789ABCDEF
    NFK2 x6, (T0 + 10)
    mov  x7, #0
    bl   _nfp_pkt_start
    cmp  x0, #NK_START_LEN
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #ANN
    mov  x2, #ANN
    add  x3, sp, #112
    mov  x4, #NK_START_LEN
    bl   _nfp_start_in
    cmp  x0, #1
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #ANN
    mov  x2, #ANN
    add  x3, sp, #112
    mov  x4, #NK_START_LEN
    bl   _nfp_start_in
    cmp  x0, #0
    NFOK eq
    ldr  x0, [sp, #104]                   // Bea: too short; then other lists
    mov  x1, #BEA
    mov  x2, #ANN
    add  x3, sp, #112
    mov  x4, #30
    bl   _nfp_start_in
    cmp  x0, #-1
    NFOK eq
    ldrb w9, [sp, #(112 + 22)]
    eor  w9, w9, #1
    strb w9, [sp, #(112 + 22)]
    ldr  x0, [sp, #104]
    mov  x1, #BEA
    mov  x2, #ANN
    add  x3, sp, #112
    mov  x4, #NK_START_LEN
    bl   _nfp_start_in
    cmp  x0, #-2
    NFOK eq
    ldrb w9, [sp, #(112 + 22)]
    eor  w9, w9, #1
    strb w9, [sp, #(112 + 22)]
    ldr  x0, [sp, #96]                    // a word before the start
    ldr  x1, [sp, #96]
    add  x1, x1, #(G_PUZ + NP_WORD)
    mov  x2, #9
    NFK2 x3, (T0 + 5)
    add  x4, sp, #464
    bl   _nfp_try
    cmp  x0, #NF_CLOSED
    NFOK eq
    ldr  x0, [sp, #96]
    NFK2 x1, (T0 + 5)
    bl   _nfp_tick
    cmp  x0, #0
    NFOK eq
    ldr  x0, [sp, #96]
    NFK2 x1, (T0 + 10)
    bl   _nfp_tick
    cmp  x0, #1
    NFOK eq
    ldr  x9, [sp, #96]
    ldr  x9, [x9, #G_STATE]
    cmp  x9, #NFS_PLAY
    NFOK eq
    mov  w1, w20
    ADRL x0, Ln_nf200
    bl   _t_report
    add  x19, x19, x0

    // 201. Bea's device makes the same puzzle; she finds the nine-letter word and Ann's device
    //      takes her claim; again is "found already"; junk is refused
    mov  x20, #1
    ldr  x0, [sp, #104]
    mov  x1, #BEA
    mov  x2, #ANN
    add  x3, sp, #112
    mov  x4, #NK_START_LEN
    bl   _nfp_start_in
    cmp  x0, #1
    NFOK eq
    ldr  x0, [sp, #104]
    NFK2 x1, (T0 + 11)
    bl   _nfp_tick
    cmp  x0, #1
    NFOK eq
    ldr  x10, [sp, #96]
    ldr  x11, [sp, #104]
    ldr  x9, [x10, #(G_PUZ + NP_TILES)]
    ldr  x12, [x11, #(G_PUZ + NP_TILES)]
    cmp  x9, x12
    NFOK eq
    ldr  x9, [x10, #(G_PUZ + NP_N)]
    ldr  x12, [x11, #(G_PUZ + NP_N)]
    cmp  x9, x12
    NFOK eq
    mov  x9, #0x1111                      // salts (nf_mesh.s makes random ones)
    stp  x9, x9, [x10, #G_SALT]
    mov  x9, #0x2222
    stp  x9, x9, [x11, #G_SALT]
    ldr  x0, [sp, #104]
    ldr  x1, [sp, #104]
    add  x1, x1, #(G_PUZ + NP_WORD)
    mov  x2, #9
    NFK2 x3, (T0 + 20)
    add  x4, sp, #144
    bl   _nfp_try
    tbnz x0, #63, 1f
    cmp  x1, #10
    NFOK eq
    b    2f
1:  mov  x20, #0
2:  ldr  x0, [sp, #96]
    mov  x1, #BEA
    ADRL x2, Lpt_bea
    mov  x3, #3
    add  x4, sp, #144
    mov  x5, #NK_CLAIM_LEN
    NFK2 x6, (T0 + 21)
    bl   _nfp_claim_in
    cmp  x0, #1
    NFOK eq
    ldr  x0, [sp, #104]
    ldr  x1, [sp, #104]
    add  x1, x1, #(G_PUZ + NP_WORD)
    mov  x2, #9
    NFK2 x3, (T0 + 22)
    add  x4, sp, #464
    bl   _nfp_try
    cmp  x0, #NF_DUP
    NFOK eq
    ldr  x0, [sp, #104]
    ADRL x1, Lpt_zzzz
    mov  x2, #4
    NFK2 x3, (T0 + 22)
    add  x4, sp, #464
    bl   _nfp_try
    cmp  x0, #0
    NFOK lt
    ldp  x9, x10, [sp, #144]              // Bea's claim, said to be for round 2
    stp  x9, x10, [sp, #464]
    ldp  x9, x10, [sp, #160]
    stp  x9, x10, [sp, #480]
    ldrb w9, [sp, #(464 + 6)]
    add  w9, w9, #1
    strb w9, [sp, #(464 + 6)]
    ldr  x0, [sp, #96]
    mov  x1, #BEA
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #464
    mov  x5, #NK_CLAIM_LEN
    NFK2 x6, (T0 + 22)
    bl   _nfp_claim_in
    cmp  x0, #-1
    NFOK eq
    mov  w1, w20
    ADRL x0, Ln_nf201
    bl   _t_report
    add  x19, x19, x0

    // 202. Ann finds it too, later, and a word of her own; the round ends; both reveal and
    //      each device checks both reveals; a second part doesn't exist
    mov  x20, #1
    ldr  x0, [sp, #96]
    ldr  x1, [sp, #96]
    add  x1, x1, #(G_PUZ + NP_WORD)
    mov  x2, #9
    NFK2 x3, (T0 + 25)
    add  x4, sp, #176
    bl   _nfp_try
    cmp  x0, #0
    NFOK ge
    mov  x21, x0                          // the nine-letter word's index
    mov  x9, #0                           // Ann's own: word 0, or 1 if 0 is the nine
    cmp  x21, #0
    cinc x9, x9, eq
    str  x9, [sp, #496]
    ldr  x0, [sp, #96]
    add  x0, x0, #G_PUZ
    mov  x1, x9
    bl   _nf_word
    str  x1, [sp, #504]
    mov  x2, x1
    mov  x1, x0
    ldr  x0, [sp, #96]
    NFK2 x3, (T0 + 30)
    add  x4, sp, #208
    bl   _nfp_try
    ldr  x9, [sp, #496]
    cmp  x0, x9
    NFOK eq
    ldr  x0, [sp, #104]                   // Bea's device takes both
    mov  x1, #ANN
    ADRL x2, Lpt_ann
    mov  x3, #3
    add  x4, sp, #176
    mov  x5, #NK_CLAIM_LEN
    NFK2 x6, (T0 + 26)
    bl   _nfp_claim_in
    cmp  x0, #0
    NFOK eq
    ldr  x0, [sp, #104]
    mov  x1, #ANN
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #208
    mov  x5, #NK_CLAIM_LEN
    NFK2 x6, (T0 + 31)
    bl   _nfp_claim_in
    cmp  x0, #0
    NFOK eq
    ldr  x0, [sp, #96]                    // the end
    NFK2 x1, (T0 + 130)
    bl   _nfp_tick
    cmp  x0, #2
    NFOK eq
    ldr  x0, [sp, #104]
    NFK2 x1, (T0 + 131)
    bl   _nfp_tick
    cmp  x0, #2
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #0
    add  x2, sp, #240
    bl   _nfp_pkt_reveal
    cmp  x0, #(NK_REV_HDR + 2)
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #1
    add  x2, sp, #464
    bl   _nfp_pkt_reveal
    cmp  x0, #0
    NFOK eq
    ldr  x0, [sp, #104]
    mov  x1, #0
    add  x2, sp, #352
    bl   _nfp_pkt_reveal
    cmp  x0, #(NK_REV_HDR + 1)
    NFOK eq
    ldr  x0, [sp, #96]                    // Ann's device: Ann's, then Bea's
    mov  x1, #ANN
    add  x2, sp, #240
    mov  x3, #(NK_REV_HDR + 2)
    bl   _nfp_reveal_in
    cmp  x0, #2
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #BEA
    add  x2, sp, #352
    mov  x3, #(NK_REV_HDR + 1)
    bl   _nfp_reveal_in
    cmp  x0, #1
    NFOK eq
    ldr  x0, [sp, #104]                   // Bea's device: the other way round
    mov  x1, #BEA
    add  x2, sp, #352
    mov  x3, #(NK_REV_HDR + 1)
    bl   _nfp_reveal_in
    cmp  x0, #1
    NFOK eq
    ldr  x0, [sp, #104]
    mov  x1, #ANN
    add  x2, sp, #240
    mov  x3, #(NK_REV_HDR + 2)
    bl   _nfp_reveal_in
    cmp  x0, #2
    NFOK eq
    mov  w1, w20
    ADRL x0, Ln_nf202
    bl   _t_report
    add  x19, x19, x0

    // 203. cheating on Ann's device: the same reveal again counts nothing; Bea's reveal with
    //      another salt is refused; Cat copies Bea's claim, then reveals it with Bea's salt:
    //      nothing (her id is in the commitment). Then both devices score alike:
    //      Bea 11 (10, first), Ann 10 + her word's points + 3 (first, nobody else), Cat 0
    mov  x20, #1
    ldr  x0, [sp, #96]
    mov  x1, #ANN
    add  x2, sp, #240
    mov  x3, #(NK_REV_HDR + 2)
    bl   _nfp_reveal_in
    cmp  x0, #0
    NFOK eq
    ldrb w9, [sp, #(352 + 9)]
    eor  w9, w9, #0x80
    strb w9, [sp, #(352 + 9)]
    ldr  x0, [sp, #96]
    mov  x1, #BEA
    add  x2, sp, #352
    mov  x3, #(NK_REV_HDR + 1)
    bl   _nfp_reveal_in
    cmp  x0, #-1
    NFOK eq
    ldrb w9, [sp, #(352 + 9)]
    eor  w9, w9, #0x80
    strb w9, [sp, #(352 + 9)]
    ldr  x0, [sp, #96]                    // too late for a claim...
    mov  x1, #CAT
    mov  x2, #0
    mov  x3, #0
    add  x4, sp, #144
    mov  x5, #NK_CLAIM_LEN
    NFK2 x6, (T0 + 140)
    bl   _nfp_claim_in
    cmp  x0, #-1
    NFOK eq
    ldr  x0, [sp, #96]                    // ... so Cat's copy arrived in time
    mov  x1, #CAT
    ADRL x2, Lpt_cat
    mov  x3, #3
    add  x4, sp, #144
    mov  x5, #NK_CLAIM_LEN
    NFK2 x6, (T0 + 120)
    bl   _nfp_claim_in
    cmp  x0, #2
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #CAT
    add  x2, sp, #352
    mov  x3, #(NK_REV_HDR + 1)
    bl   _nfp_reveal_in
    cmp  x0, #0
    NFOK eq
    ldr  x0, [sp, #96]
    NFK2 x1, (T0 + 142)
    bl   _nfp_tick
    cmp  x0, #3
    NFOK eq
    ldr  x0, [sp, #104]
    NFK2 x1, (T0 + 143)
    bl   _nfp_tick
    cmp  x0, #3
    NFOK eq
    ldr  x0, [sp, #504]
    bl   _nf_points
    add  x21, x0, #13                     // Ann's
    ldr  x0, [sp, #96]
    mov  x1, #BEA
    bl   Lpt_score
    cmp  x0, #11
    NFOK eq
    ldr  x0, [sp, #104]
    mov  x1, #BEA
    bl   Lpt_score
    cmp  x0, #11
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #ANN
    bl   Lpt_score
    cmp  x0, x21
    NFOK eq
    ldr  x0, [sp, #104]
    mov  x1, #ANN
    bl   Lpt_score
    cmp  x0, x21
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #CAT
    bl   Lpt_score
    cmp  x0, #0
    NFOK eq
    ldr  x0, [sp, #96]                    // the ranking: Ann, Bea, Cat
    add  x1, sp, #464
    bl   _nfp_rank
    cmp  x0, #3
    NFOK eq
    ldrb w9, [sp, #464]
    cmp  w9, #0
    NFOK eq
    ldrb w9, [sp, #465]
    cmp  w9, #1
    NFOK eq
    mov  w1, w20
    ADRL x0, Ln_nf203
    bl   _t_report
    add  x19, x19, x0

    // 204. the words on screen (nf_text.s): the status line, the results, a refusal
    mov  x20, #1
    ldr  x0, [sp, #96]
    NFK2 x1, (T0 + 142)
    add  x2, sp, #240
    mov  x3, #200
    bl   _nft_status
    add  x0, sp, #240
    ADRL x1, Lpt_status
    bl   Lpt_prefix
    and  x20, x20, x0
    ldr  x0, [sp, #96]
    mov  x1, #0
    add  x2, sp, #240
    mov  x3, #200
    bl   _nft_result
    add  x0, sp, #240
    ADRL x1, Lpt_res0
    bl   Lpt_prefix
    and  x20, x20, x0
    ldr  x0, [sp, #96]
    mov  x1, #1
    add  x2, sp, #240
    mov  x3, #200
    bl   _nft_result
    add  x0, sp, #240
    ADRL x1, Lpt_res1
    bl   Lpt_prefix
    and  x20, x20, x0
    ldr  x0, [sp, #96]                    // Bea's line on Ann's device: second, 11 points
    mov  x1, #2
    add  x2, sp, #240
    mov  x3, #200
    bl   _nft_result
    add  x0, sp, #240
    ADRL x1, Lpt_res2
    bl   Lpt_prefix
    and  x20, x20, x0
    ldr  x0, [sp, #96]                    // past the last line: nothing
    mov  x1, #9
    add  x2, sp, #240
    mov  x3, #200
    bl   _nft_result
    cmp  x0, #0
    NFOK eq
    ldr  x0, [sp, #96]
    mov  x1, #NF_LENGTH
    mov  x2, #0
    ADRL x3, Lpt_zzzz
    mov  x4, #2
    add  x5, sp, #240
    mov  x6, #200
    bl   _nft_try
    add  x0, sp, #240
    ADRL x1, Lpt_length
    bl   Lpt_prefix
    and  x20, x20, x0
    ldr  x0, [sp, #96]                    // a tiny buffer: cut, still terminated
    mov  x1, #0
    add  x2, sp, #240
    mov  x3, #8
    bl   _nft_result
    cmp  x0, #7
    NFOK eq
    ldrb w9, [sp, #247]
    cmp  w9, #0
    NFOK eq
    mov  w1, w20
    ADRL x0, Ln_nf204
    bl   _t_report
    add  x19, x19, x0

Lpt_free:
    ldr  x0, [sp, #96]
    bl   _free
    ldr  x0, [sp, #104]
    bl   _free
    mov  x0, x19
    LEAVE 512
Lpt_nomem:
    mov  w1, #0
    ADRL x0, Ln_nf200
    bl   _t_report
    add  x19, x19, x0
    b    Lpt_free

// Lpt_prefix(s, prefix) -> 1 if s starts with prefix (leaf)
Lpt_prefix:
    ldrb w10, [x1], #1
    cbz  w10, 1f
    ldrb w9, [x0], #1
    cmp  w9, w10
    b.eq Lpt_prefix
    mov  x0, #0
    ret
1:  mov  x0, #1
    ret

// Lpt_score(g, id) -> that player's game score, or -1
Lpt_score:
    mov  x12, x0
    stp  x29, x30, [sp, #-16]!
    bl   Lpl_find
    ldp  x29, x30, [sp], #16
    tbnz x0, #63, 1f
    mov  x11, #PL_SIZE
    madd x11, x0, x11, x12
    ldr  x0, [x11, #(G_PL + PL_SCORE)]
1:  ret


// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lpt_ann:        .asciz "Ann"
Lpt_bea:        .asciz "Bea"
Lpt_cat:        .asciz "Cat"
Lpt_zzzz:       .asciz "zzzz"
Lpt_status:     .asciz "Round 1 of 2 \302\267 scored \302\267 you "
Lpt_res0:       .asciz "Round 1 of 2: the nine-letter word was "
Lpt_res1:       .asciz "1. you "
Lpt_res2:       .asciz "2. Bea 11 (+11): "
Lpt_length:     .asciz "\342\234\227 Words have 4 to 9 letters"
Ln_nf204:       .asciz "204 ninefold screens: status, results, refusals, short buffers"
Ln_nf200:       .asciz "200 ninefold game: START taken once, other lists refused, the round starts on time"
Ln_nf201:       .asciz "201 ninefold game: two devices, one puzzle; a claim crosses; found already; junk"
Ln_nf202:       .asciz "202 ninefold game: the round ends; reveals checked on both devices"
Ln_nf203:       .asciz "203 ninefold game: cheats get nothing; both devices score alike; the ranking"
