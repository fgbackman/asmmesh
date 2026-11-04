// nf_mesh.s — Ninefold on the mesh (Mac and iPhone): one game at a time, in an invite-only
// room. The rules are nf_play.s's and the words on screen nf_text.s's; this file moves the
// packets (room messages flagged MSGF_GAME, sealed with the room's key), keeps the clock,
// takes typed words, and gives the screens what to show:
//   Home: "ninefold with Anna, Sam [3 rounds] [2 minutes] [family off]"
//   in the game room: start · shuffle · words · any single word while a round is on
// Platform hook: _nf_ui_show(status) (ui.s on the Mac, ios_ui.s on the iPhone).
.include "macros.inc"
.include "nf_defs.inc"

.data
.p2align 3
.globl _g_nfg
.zerofill __DATA,__bss,_g_nfg,G_SIZE,4
.zerofill __DATA,__bss,_g_nf_buf,1200,4    // text for the screens
.zerofill __DATA,__bss,_g_nf_pkt,128,4     // a packet being made
.zerofill __DATA,__bss,_g_nf_start,32,4    // the host's START, sent again every 15 s
.zerofill __DATA,__bss,_g_nf_view,16,4     // the tiles as shown (shuffle moves them)
.zerofill __DATA,__bss,_g_nf_names,160,4   // who was invited, for the room's first line
_g_nf_next:     .quad 0                    // host: when the next round starts (0: not yet)
_g_nf_warned:   .quad 0                    // the game we said "other word lists" about

.text
.p2align 2

// ---------------------------------------------------------------------------
// From the mesh

// void _nf_rx(uint64 room, uint64 sender, const char *nick, const uint8 *data, long len)
//   mesh.s: a game packet in a room we're in, opened with the room's key
.globl _nf_rx
_nf_rx:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    cmp  x23, #2
    b.lo Lnx_out
    ldrb w9, [x22]
    cmp  w9, #'N'
    b.ne Lnx_out
    ldrb w24, [x22, #1]
    cmp  w24, #NK_START
    b.eq Lnx_start
    ADRL x8, _g_nfg                       // claims and reveals: our game's room only
    ldr  x9, [x8, #G_ROOM]
    cmp  x9, x19
    b.ne Lnx_out
    ldr  x9, [x8, #G_STATE]
    cmp  x9, #NFS_WAIT
    b.lo Lnx_out
    cmp  w24, #NK_CLAIM
    b.eq Lnx_claim
    cmp  w24, #NK_REVEAL
    b.ne Lnx_out
    ADRL x0, _g_nfg
    mov  x1, x20
    mov  x2, x22
    mov  x3, x23
    bl   _nfp_reveal_in
    b    Lnx_out
Lnx_claim:
    mov  x0, x21
    bl   _strlen
    str  x0, [sp, #96]
    mov  x0, #0
    bl   _time
    mov  x6, x0
    ldr  x3, [sp, #96]
    ADRL x0, _g_nfg
    mov  x1, x20
    mov  x2, x21
    mov  x4, x22
    mov  x5, x23
    bl   _nfp_claim_in
    bl   Lnf_show
    b    Lnx_out
Lnx_start:
    ADRL x0, _g_nfg
    ADRL x8, _g_node_id
    ldr  x1, [x8]
    mov  x2, x20
    mov  x3, x22
    mov  x4, x23
    bl   _nfp_start_in
    cmp  x0, #-2
    b.eq Lnx_lists
    tbnz x0, #63, Lnx_out
    mov  x24, x0
    mov  x0, x21                          // the host's name, as the mesh has it
    bl   _strlen
    mov  x3, x0
    ADRL x0, _g_nfg
    mov  x1, x20
    mov  x2, x21
    bl   _nfp_player
    cbz  x24, Lnx_out                     // a START we have
    ADRL x8, _g_nfg
    str  x19, [x8, #G_ROOM]
    bl   Lnf_round_set
    b    Lnx_out
Lnx_lists:                                // once per game: say why we can't play
    ldur w9, [x22, #2]
    ADRL x8, _g_nf_warned
    ldr  x10, [x8]
    cmp  x9, x10
    b.eq Lnx_out
    str  x9, [x8]
    mov  x0, x19
    bl   _room_find
    tbnz x0, #63, Lnx_out
    mov  x1, #1
    ADRL x2, Ls_nf_lists
    mov  x3, x21
    bl   _room_fmt
Lnx_out:
    LEAVE 16

// ---------------------------------------------------------------------------
// Every second (scanner.s on the Mac, ios_ui.s on the iPhone)

// void _nf_tick(void)
.globl _nf_tick
_nf_tick:
    ENTER 16
    ADRL x19, _g_nfg
    ldr  x9, [x19, #G_STATE]
    cbz  x9, Ltk2_out
    ldr  x0, [x19, #G_ROOM]               // the room left or deleted: the game is over here
    bl   _room_find
    tbz  x0, #63, 1f
    str  xzr, [x19, #G_STATE]
    ADRL x0, Ls_empty
    bl   _nf_ui_show
    b    Ltk2_out
1:  mov  x20, x0                          // the room's index
    mov  x0, #0
    bl   _time
    mov  x21, x0
    ldr  x9, [x19, #G_STATE]
    cmp  x9, #NFS_LOBBY
    b.eq Ltk2_show
    mov  x0, x19
    mov  x1, x21
    bl   _nfp_tick
    cmp  x0, #1
    b.eq Ltk2_began
    cmp  x0, #2
    b.eq Ltk2_ended
    cmp  x0, #3
    b.eq Ltk2_scored
    b    Ltk2_host
Ltk2_began:
    mov  x0, x20
    bl   Lnf_board
    mov  x0, x20
    ADRL x1, Ls_nf_go
    mov  x2, #1
    bl   _room_line
    b    Ltk2_host
Ltk2_ended:
    mov  x0, x20
    ADRL x1, Ls_nf_time
    mov  x2, #1
    bl   _room_line
    mov  x22, #0                          // our REVEAL, in parts, to everyone and to us
2:  mov  x0, x19
    mov  x1, x22
    ADRL x2, _g_nf_pkt
    bl   _nfp_pkt_reveal
    cbz  x0, Ltk2_host
    mov  x23, x0
    mov  x0, x20
    ADRL x1, _g_nf_pkt
    mov  x2, x23
    bl   _mesh_send_game
    mov  x0, x19
    ADRL x8, _g_node_id
    ldr  x1, [x8]
    ADRL x2, _g_nf_pkt
    mov  x3, x23
    bl   _nfp_reveal_in
    add  x22, x22, #1
    b    2b
Ltk2_scored:
    mov  x22, #0
3:  mov  x0, x19
    mov  x1, x22
    ADRL x2, _g_nf_buf
    mov  x3, #1200
    bl   _nft_result
    cbz  x0, 4f
    mov  x0, x20
    ADRL x1, _g_nf_buf
    mov  x2, #1
    bl   _room_line
    add  x22, x22, #1
    b    3b
4:  ldr  x9, [x19, #G_HOST]               // the host: the next round in 15 s
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne Ltk2_show
    ldr  x9, [x19, #G_ROUND]
    ldr  x10, [x19, #G_ROUNDS]
    cmp  x9, x10
    b.hs Ltk2_show
    add  x9, x21, #15
    ADRL x8, _g_nf_next
    str  x9, [x8]
Ltk2_host:
    ldr  x9, [x19, #G_HOST]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne Ltk2_show
    ldr  x9, [x19, #G_STATE]
    cmp  x9, #NFS_DONE
    b.eq Ltk2_next
    cmp  x9, #NFS_PLAY                    // START again every 15 s: for slow hops and late
    b.hi Ltk2_show                        //   joiners, who start where the round has got to
    ldr  x10, [x19, #G_AUX]
    sub  x10, x21, x10
    cmp  x10, #15
    b.lo Ltk2_show
    str  x21, [x19, #G_AUX]
    mov  x0, x20
    ADRL x1, _g_nf_start
    mov  x2, #NK_START_LEN
    bl   _mesh_send_game
    b    Ltk2_show
Ltk2_next:
    ADRL x8, _g_nf_next
    ldr  x9, [x8]
    cbz  x9, Ltk2_show
    cmp  x21, x9
    b.lo Ltk2_show
    str  xzr, [x8]
    ldr  x1, [x19, #G_ROUND]
    add  x1, x1, #1
    mov  x0, x20
    bl   Lnf_begin
Ltk2_show:
    bl   Lnf_show
Ltk2_out:
    LEAVE 16

// ---------------------------------------------------------------------------
// Typed in the game room

// long _nf_typed(long room, const char *text) -> 1 if it was for the game (mesh.s: else chat)
//   start · shuffle · words; and while a round is on, any single word is a guess, never chat
.globl _nf_typed
_nf_typed:
    ENTER 48                              // [96] the word in small letters (32)
    mov  x19, x0
    mov  x20, x1
    ADRL x22, _g_nfg
    ldr  x9, [x22, #G_STATE]
    cbz  x9, Lty_no
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    ldr  x10, [x22, #G_ROOM]
    cmp  x9, x10
    b.ne Lty_no
1:  ldrb w9, [x20]                        // spaces around it don't count
    cmp  w9, #' '
    b.ne 2f
    add  x20, x20, #1
    b    1b
2:  mov  x21, #0                          // one word, 31 bytes at most, letters only?
    mov  x23, #1
3:  ldrb w9, [x20, x21]
    cbz  w9, 5f
    cmp  w9, #' '
    b.eq 4f
    cmp  x21, #31
    b.hs Lty_no
    orr  w10, w9, #0x20
    sub  w11, w10, #'a'
    cmp  w11, #25
    csel x23, xzr, x23, hi
    add  x11, sp, #96
    strb w10, [x11, x21]
    add  x21, x21, #1
    b    3b
4:  add  x9, x20, x21                     // only spaces may follow
41: ldrb w10, [x9], #1
    cbz  w10, 5f
    cmp  w10, #' '
    b.eq 41b
    b    Lty_no
5:  cbz  x21, Lty_no
    add  x9, sp, #96
    strb wzr, [x9, x21]
    add  x0, sp, #96
    ADRL x1, Ls_nf_w_start
    bl   _strcmp
    cbz  w0, Lty_start
    add  x0, sp, #96
    ADRL x1, Ls_nf_w_shuffle
    bl   _strcmp
    cbz  w0, Lty_shuffle
    add  x0, sp, #96
    ADRL x1, Ls_nf_w_words
    bl   _strcmp
    cbz  w0, Lty_words
    ldr  x9, [x22, #G_STATE]
    cmp  x9, #NFS_PLAY
    b.ne Lty_no
    cbz  x23, Lty_no                      // not all letters: chat
    mov  x0, #0
    bl   _time
    mov  x3, x0
    mov  x0, x22
    mov  x1, x20
    mov  x2, x21
    ADRL x4, _g_nf_pkt
    bl   _nfp_try
    mov  x23, x0
    mov  x24, x1
    tbnz x23, #63, 6f
    mov  x0, x19                          // the claim: length and commitment, not the word
    ADRL x1, _g_nf_pkt
    mov  x2, #NK_CLAIM_LEN
    bl   _mesh_send_game
6:  mov  x0, x22
    mov  x1, x23
    mov  x2, x24
    mov  x3, x20
    mov  x4, x21
    ADRL x5, _g_nf_buf
    mov  x6, #300
    bl   _nft_try
    mov  x0, x19
    ADRL x1, _g_nf_buf
    mov  x2, #1
    bl   _room_line
    bl   Lnf_show
    b    Lty_yes
Lty_start:
    ldr  x9, [x22, #G_STATE]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, #NFS_LOBBY
    b.eq 7f
    cmp  x9, #NFS_DONE
    b.ne Lty_busy
    ldr  x10, [x22, #G_ROUND]             // after the last round: a new game, by whoever
    ldr  x11, [x22, #G_ROUNDS]
    cmp  x10, x11
    b.lo 7f
    str  x8, [x22, #G_HOST]
    mov  x0, x19
    mov  x1, #1
    bl   Lnf_begin
    b    Lty_yes
7:  ldr  x10, [x22, #G_HOST]              // the lobby or between rounds: the host only
    cmp  x10, x8
    b.ne Lty_nothost
    ldr  x1, [x22, #G_ROUND]
    add  x1, x1, #1
    cmp  x9, #NFS_LOBBY
    mov  x10, #1
    csel x1, x10, x1, eq
    ADRL x8, _g_nf_next
    str  xzr, [x8]
    mov  x0, x19
    bl   Lnf_begin
    b    Lty_yes
Lty_busy:
    mov  x0, x19
    ADRL x1, Ls_nf_busy
    mov  x2, #1
    bl   _room_line
    b    Lty_yes
Lty_nothost:
    mov  x0, x19
    ADRL x1, Ls_nf_nothost
    mov  x2, #1
    bl   _room_line
    b    Lty_yes
Lty_shuffle:
    bl   _nf_shuffle
    mov  x0, x19
    bl   Lnf_board
    b    Lty_yes
Lty_words:
    mov  x0, x22
    ADRL x1, _g_nf_buf
    mov  x2, #1200
    bl   _nft_mine
    ADRL x3, _g_nf_buf
    ADRL x8, Ls_nf_none
    cmp  x0, #0
    csel x3, x8, x3, eq
    mov  x0, x19
    mov  x1, #1
    ADRL x2, Ls_nf_yours
    bl   _room_fmt
Lty_yes:
    mov  x0, #1
    LEAVE 48
Lty_no:
    mov  x0, #0
    LEAVE 48

// void _nf_shuffle(void) — the eight outer tiles in a new order (on this screen only)
.globl _nf_shuffle
_nf_shuffle:
    ENTER 0
    mov  x19, #8
1:  mov  x0, x19                          // Fisher-Yates over positions 0-3, 5-8
    bl   _arc4random_uniform
    ADRL x8, _g_nf_view
    ADRL x9, Lnf_outer
    sub  x11, x19, #1
    ldrb w11, [x9, x11]
    ldrb w12, [x9, x0]
    ldrb w13, [x8, x11]
    ldrb w14, [x8, x12]
    strb w14, [x8, x11]
    strb w13, [x8, x12]
    subs x19, x19, #1
    cmp  x19, #1
    b.hi 1b
    bl   Lnf_show
    LEAVE 0

// ---------------------------------------------------------------------------
// Home: "ninefold with Anna, Sam [3 rounds] [2 minutes] [family off]"

// _h_ninefold(arg, rest_lc, rest_orig) — rules.s's word table
.globl _h_ninefold
_h_ninefold:
    ENTER 288                             // [96] a copy of the text (160)  [256] invitees (12)
    mov  x19, x2                          //   [268] how many  [272] rounds  [280] minutes
    ADRL x8, _g_remote_active             //   [288] family  [296] a number not placed yet
    ldr  x9, [x8]
    cbnz x9, Lhn_remote
    ADRL x8, _g_nfg
    ldr  x9, [x8, #G_STATE]
    cmp  x9, #NFS_WAIT
    b.lo 1f
    cmp  x9, #NFS_DONE
    b.lo Lhn_busy
1:  mov  x9, #3
    str  x9, [sp, #272]
    mov  x9, #4
    str  x9, [sp, #280]
    mov  x9, #1
    str  x9, [sp, #288]
    str  xzr, [sp, #296]
    strb wzr, [sp, #268]
    add  x0, sp, #96
    mov  x1, x19
    mov  x2, #160
    bl   _strlcpy
    add  x20, sp, #96                     // pieces between commas
Lhn_piece:
    ldrb w9, [x20]
    cbz  w9, Lhn_go
    mov  x21, x20
1:  ldrb w9, [x21]
    cbz  w9, 2f
    cmp  w9, #','
    b.eq 2f
    add  x21, x21, #1
    b    1b
2:  mov  x22, x21                         // x20..x21: the piece; x22: past its comma
    cbz  w9, 3f
    strb wzr, [x21]
    add  x22, x21, #1
3:  mov  x0, x20
    bl   Lhn_trim
    mov  x20, x0
    ldrb w9, [x20]
    cbz  w9, Lhn_pnext
    mov  x0, x20                          // a whole name, spaces and all ("Fred's iPhone")?
    bl   Lhn_node
    tbz  x0, #63, Lhn_pname
Lhn_words:                                // else word by word
    ldrb w9, [x20]
    cbz  w9, Lhn_pnext
    mov  x21, x20
4:  ldrb w9, [x21]
    cbz  w9, 5f
    cmp  w9, #' '
    b.eq 5f
    add  x21, x21, #1
    b    4b
5:  mov  x23, x21
    cbz  w9, 6f
    strb wzr, [x21]
    add  x23, x21, #1
6:  ldrb w9, [x20]
    cbz  w9, Lhn_wnext
    mov  x0, x20
    bl   Lhn_word
    cbnz x0, Lhn_wnext
    mov  x0, x20
    bl   Lhn_node
    tbnz x0, #63, Lhn_nobody
    bl   Lhn_add
Lhn_wnext:
    mov  x20, x23
    b    Lhn_words
Lhn_pname:
    bl   Lhn_add
Lhn_pnext:
    mov  x20, x22
    b    Lhn_piece

Lhn_go:                                   // the room, the game, the invitations
    ADRL x0, _g_nf_buf
    mov  x1, #(ROOMNAME_MAX + 1)
    ADRL x2, Ls_nf_room
    ADRL x3, _g_nick
    str  x3, [sp]
    bl   _snprintf
    ADRL x0, _g_nf_buf
    bl   _utf8_fix
    bl   _new_id
    mov  x24, x0
    mov  x0, x24
    ADRL x1, _g_nf_buf
    mov  x2, #1
    bl   _room_add
    tbnz x0, #63, Lhn_full
    mov  x20, x0
    bl   _room_own
    ADRL x22, _g_nfg
    mov  x0, x22                          // a fresh game, in the lobby
    mov  x1, #0
    mov  x2, #G_PUZ
    bl   _memset
    mov  x9, #NFS_LOBBY
    str  x9, [x22, #G_STATE]
    str  x24, [x22, #G_ROOM]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x22, #G_HOST]
    str  x9, [x22, #G_ME]
    ldr  x9, [sp, #272]
    str  x9, [x22, #G_ROUNDS]
    ldr  x9, [sp, #280]
    mov  x10, #60
    mul  x9, x9, x10
    str  x9, [x22, #G_SECS]
    ldr  x9, [sp, #288]
    str  x9, [x22, #G_FAMILY]
    mov  x0, x20
    bl   _ui_select_room
    ADRL x8, _g_nf_names
    strb wzr, [x8]
    mov  x21, #0
7:  ldrb w9, [sp, #268]
    cmp  x21, x9
    b.hs 8f
    add  x9, sp, #256
    ldrb w23, [x9, x21]
    mov  x0, x23
    mov  x1, x20
    bl   _mesh_send_invite
    mov  x24, x0
    ADRL x8, _g_nodes
    add  x0, x8, x23, lsl #NODE_SHIFT
    bl   _node_name
    mov  x23, x0
    tbz  x24, #63, 71f
    mov  x0, x20                          // no key from them yet
    mov  x1, #1
    ADRL x2, Ls_nf_nokey
    mov  x3, x23
    bl   _room_fmt
    b    72f
71: ADRL x0, _g_nf_names
    ldrb w9, [x0]
    cbz  w9, 73f
    ADRL x1, Ls_comma
    mov  x2, #160
    bl   _strlcat
73: ADRL x0, _g_nf_names
    mov  x1, x23
    mov  x2, #160
    bl   _strlcat
72: add  x21, x21, #1
    b    7b
8:  ADRL x0, _g_nf_buf                    // "3 rounds of 4 minutes, family filter on"
    mov  x1, #200
    ADRL x2, Ls_nf_opts
    ldr  x9, [sp, #272]
    str  x9, [sp]
    ldr  x9, [sp, #280]
    str  x9, [sp, #8]
    ADRL x9, Ls_on
    ADRL x10, Ls_off
    ldr  x11, [sp, #288]
    cmp  x11, #0
    csel x9, x10, x9, eq
    str  x9, [sp, #16]
    bl   _snprintf
    ADRL x8, _g_nf_names
    ldrb w9, [x8]
    cbz  w9, 9f
    mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_nf_lobby
    ADRL x3, _g_nf_names
    ADRL x4, _g_nf_buf
    bl   _room_fmt
    b    Lhn_done
9:  mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_nf_alone
    ADRL x3, _g_nf_buf
    bl   _room_fmt
    b    Lhn_done
Lhn_nobody:
    ADRL x0, Ls_nf_nobody
    mov  x1, x20
    bl   _home_say
    b    Lhn_done
Lhn_busy:
    ADRL x0, Ls_nf_busy_home
    bl   _home_say0
    b    Lhn_done
Lhn_full:
    ADRL x0, Ls_nf_full
    bl   _home_say0
    b    Lhn_done
Lhn_remote:
    ADRL x0, Ls_nf_remote
    bl   _home_say0
Lhn_done:
    LEAVE 288

// Lhn_add(x0 node) — one more invitee (inside _h_ninefold: its frame), once each, 11 at most
Lhn_add:
    ldrb w9, [sp, #268]
    cmp  w9, #(NF_PLAYERS - 1)
    b.hs 3f
    add  x10, sp, #256
    mov  x11, #0
1:  cmp  x11, x9
    b.hs 2f
    ldrb w12, [x10, x11]
    cmp  x12, x0
    b.eq 3f
    add  x11, x11, #1
    b    1b
2:  strb w0, [x10, x9]
    add  w9, w9, #1
    strb w9, [sp, #268]
3:  ret

// Lhn_word(x0 word) -> 1 if it was "with", "and", or an option (inside _h_ninefold's frame:
//   [272] rounds [280] minutes [288] family [296] what a number goes with: 0 nothing yet,
//   1 "rounds" came first, 2 "minutes" came first, 100 + n: the number n came first)
Lhn_word:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    ldrb w9, [x19]                        // one digit, 1-9
    sub  w9, w9, #'1'
    cmp  w9, #8
    b.hi Lhw_kw
    ldrb w9, [x19, #1]
    cbnz w9, Lhw_kw
    ldrb w9, [x19]
    sub  w9, w9, #'0'
    ldr  x10, [sp, #(32 + 296)]
    cmp  x10, #1
    b.eq Lhw_rounds_n
    cmp  x10, #2
    b.eq Lhw_minutes_n
    add  x9, x9, #100
    str  x9, [sp, #(32 + 296)]
    b    Lhw_yes
Lhw_rounds_n:
    str  xzr, [sp, #(32 + 296)]
    cmp  x9, #5
    b.hi Lhw_yes
    str  x9, [sp, #(32 + 272)]
    b    Lhw_yes
Lhw_minutes_n:
    str  xzr, [sp, #(32 + 296)]
    str  x9, [sp, #(32 + 280)]
    b    Lhw_yes
Lhw_kw:
    ADRL x20, Lhw_table
Lhw_look:
    ldr  x1, [x20]
    cbz  x1, Lhw_no
    mov  x0, x19
    bl   _strcasecmp
    cbz  w0, Lhw_found
    add  x20, x20, #16
    b    Lhw_look
Lhw_found:
    ldr  x9, [x20, #8]                    // 0 skip, 1 rounds, 2 minutes, 3 family off, 4 on
    cbz  x9, Lhw_yes
    cmp  x9, #3
    b.lo Lhw_unit
    cmp  x9, #4
    cset x10, eq
    str  x10, [sp, #(32 + 288)]
    b    Lhw_yes
Lhw_unit:
    ldr  x10, [sp, #(32 + 296)]
    cmp  x10, #100
    b.lo Lhw_wait
    sub  x10, x10, #100                   // "3 rounds": the number came first
    str  xzr, [sp, #(32 + 296)]
    cmp  x9, #1
    b.ne Lhw_unit_min
    cmp  x10, #5
    b.hi Lhw_yes
    str  x10, [sp, #(32 + 272)]
    b    Lhw_yes
Lhw_unit_min:
    str  x10, [sp, #(32 + 280)]
    b    Lhw_yes
Lhw_wait:
    str  x9, [sp, #(32 + 296)]            // "rounds 3": the number comes next
Lhw_yes:
    mov  x0, #1
    b    Lhw_ret
Lhw_no:
    mov  x0, #0
Lhw_ret:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// Lhn_node(x0 name) -> the node's index, or -1: someone on the mesh by that name
Lhn_node:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    mov  x20, #0
1:  ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 2f
    ADRL x8, _g_nodes
    add  x0, x8, x20, lsl #NODE_SHIFT
    add  x0, x0, #N_NICK
    mov  x1, x19
    bl   _strcasecmp
    cbz  w0, 3f
    add  x20, x20, #1
    b    1b
2:  mov  x0, #-1
    b    4f
3:  mov  x0, x20
4:  ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// Lhn_trim(x0 s) -> s without spaces before and after (cut in place) (leaf)
Lhn_trim:
1:  ldrb w9, [x0]
    cmp  w9, #' '
    b.ne 2f
    add  x0, x0, #1
    b    1b
2:  mov  x9, x0
3:  ldrb w10, [x9]
    cbz  w10, 4f
    add  x9, x9, #1
    b    3b
4:  cmp  x9, x0
    b.ls 5f
    ldrb w10, [x9, #-1]
    cmp  w10, #' '
    b.ne 5f
    sub  x9, x9, #1
    strb wzr, [x9]
    b    4b
5:  ret

// void _nf_dialog(id sender) — Mesh › Play Ninefold…: who to invite (everyone on the mesh
//   now, filled in), then what "ninefold with ..." does
.globl _nf_dialog
_nf_dialog:
    ENTER 288                             // [96] the names (192)
    strb wzr, [sp, #96]
    mov  x19, #0
1:  ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs 3f
    ADRL x8, _g_nodes
    add  x20, x8, x19, lsl #NODE_SHIFT
    add  x19, x19, #1
    ldrb w9, [x20, #N_NICK]
    cbz  w9, 1b
    ldrb w9, [sp, #96]
    cbz  w9, 2f
    add  x0, sp, #96
    ADRL x1, Ls_comma
    mov  x2, #192
    bl   _strlcat
2:  add  x0, sp, #96
    add  x1, x20, #N_NICK
    mov  x2, #192
    bl   _strlcat
    b    1b
3:  ADRL x0, Ls_nf_dlg_title
    ADRL x1, Ls_nf_dlg_info
    ADRL x2, Ls_nf_dlg_ph
    add  x3, sp, #96
    mov  x4, #0
    add  x5, sp, #96
    mov  x6, #192
    bl   _ask_text
    cbz  x0, 9f                           // cancelled
    mov  x0, #0
    add  x1, sp, #96
    add  x2, sp, #96
    bl   _h_ninefold
9:  LEAVE 288

// ---------------------------------------------------------------------------
// Rounds

// Lnf_begin(x0 room index, x1 round) — the host starts a round: a new game for round 1
Lnf_begin:
    ENTER 16                              // [96] the seed
    mov  x19, x0
    mov  x20, x1
    ADRL x22, _g_nfg
    add  x0, sp, #96
    mov  x1, #8
    bl   _arc4random_buf
    ldr  x21, [sp, #96]
    ldr  x23, [x22, #G_GID]
    cmp  x20, #1
    b.ne 1f
    bl   _arc4random                      // a new game
    mov  w23, w0
1:  mov  x0, #0
    bl   _time
    mov  x24, x0
    add  x6, x24, #10                     // everyone starts on their own clock, 10 s ahead
    ADRL x0, _g_nf_start
    mov  x1, x23
    mov  x2, x20
    ldr  x3, [x22, #G_ROUNDS]
    ldr  x4, [x22, #G_SECS]
    mov  x5, x21
    ldr  x7, [x22, #G_FAMILY]
    bl   _nfp_pkt_start
    mov  x0, x22
    ADRL x8, _g_node_id
    ldr  x1, [x8]
    mov  x2, x1
    ADRL x3, _g_nf_start
    mov  x4, #NK_START_LEN
    bl   _nfp_start_in
    cmp  x0, #1
    b.ne 2f
    bl   Lnf_round_set
    mov  x0, x19
    ADRL x1, _g_nf_start
    mov  x2, #NK_START_LEN
    bl   _mesh_send_game
    str  x24, [x22, #G_AUX]
    LEAVE 16
2:  mov  x0, x19
    ADRL x1, Ls_nf_cant
    mov  x2, #1
    bl   _room_line
    LEAVE 16

// Lnf_round_set — a round was set (ours or the host's START): a new salt, the tiles as
//   dealt, our name in the players, and a line in the room
Lnf_round_set:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    ADRL x19, _g_nfg
    add  x0, x19, #G_SALT
    mov  x1, #16
    bl   _arc4random_buf
    ADRL x8, _g_nf_view
    ldr  x9, [x19, #(G_PUZ + NP_TILES)]
    str  x9, [x8]
    ldrb w9, [x19, #(G_PUZ + NP_TILES + 8)]
    strb w9, [x8, #8]
    strb wzr, [x8, #9]
    mov  x0, x19
    ADRL x8, _g_node_id
    ldr  x1, [x8]
    ADRL x2, _g_nick
    ADRL x8, _g_nick_len
    ldr  x3, [x8]
    bl   _nfp_player
    ldr  x0, [x19, #G_ROOM]
    bl   _room_find
    tbnz x0, #63, 1f
    mov  x20, x0
    mov  x0, #0
    bl   _time
    mov  x1, x0
    mov  x0, x19
    ADRL x2, _g_nf_buf
    mov  x3, #300
    bl   _nft_status
    mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_nf_set
    ADRL x3, _g_nf_buf
    bl   _room_fmt
    ldr  x9, [x19, #G_ROUND]
    cmp  x9, #1
    b.ne 1f
    mov  x0, x20
    ADRL x1, Ls_nf_howto
    mov  x2, #1
    bl   _room_line
1:  bl   Lnf_show
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// Lnf_board(x0 room index) — the grid, three lines
Lnf_board:
    stp  x29, x30, [sp, #-32]!
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    mov  x20, #0
1:  ADRL x0, _g_nfg
    ADRL x1, _g_nf_view
    mov  x2, x20
    ADRL x3, _g_nf_buf
    mov  x4, #200
    bl   _nft_board
    mov  x0, x19
    ADRL x1, _g_nf_buf
    mov  x2, #1
    bl   _room_line
    add  x20, x20, #1
    cmp  x20, #3
    b.lo 1b
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// Lnf_show — the status line to the screen (the Mac's room header, the iPhone's game view)
Lnf_show:
    stp  x29, x30, [sp, #-16]!
    mov  x0, #0
    bl   _time
    mov  x1, x0
    ADRL x0, _g_nfg
    ADRL x2, _g_nf_buf
    mov  x3, #300
    bl   _nft_status
    ADRL x0, _g_nf_buf
    bl   _nf_ui_show
    ldp  x29, x30, [sp], #16
    ret

// ---------------------------------------------------------------------------
// For the iPhone's game screen (Swift calls these; the Mac has them too)

// long am_nf_state(void) -> NFS_*
.globl _am_nf_state
_am_nf_state:
    ADRL x8, _g_nfg
    ldr  x0, [x8, #G_STATE]
    ret

// long am_nf_room(void) -> the game room's index, or -1
.globl _am_nf_room
_am_nf_room:
    ADRL x8, _g_nfg
    ldr  x9, [x8, #G_STATE]
    cbz  x9, 1f
    ldr  x0, [x8, #G_ROOM]
    b    _room_find
1:  mov  x0, #-1
    ret

// long am_nf_host(void) -> 1 if we start the rounds
.globl _am_nf_host
_am_nf_host:
    ADRL x8, _g_nfg
    ldr  x9, [x8, #G_HOST]
    ADRL x10, _g_node_id
    ldr  x10, [x10]
    cmp  x9, x10
    cset x0, eq
    ret

// char *am_nf_tiles(char buf[10]) — the nine letters as shown, in capitals, the centre 5th
.globl _am_nf_tiles
_am_nf_tiles:
    ADRL x8, _g_nf_view
    mov  x9, #0
1:  ldrb w10, [x8, x9]
    bic  w10, w10, #0x20
    strb w10, [x0, x9]
    add  x9, x9, #1
    cmp  x9, #9
    b.lo 1b
    strb wzr, [x0, #9]
    ret

// long am_nf_left(void) -> seconds until the round starts (waiting) or ends (playing)
.globl _am_nf_left
_am_nf_left:
    stp  x29, x30, [sp, #-16]!
    mov  x0, #0
    bl   _time
    ADRL x8, _g_nfg
    ldr  x9, [x8, #G_START]
    ldr  x10, [x8, #G_STATE]
    cmp  x10, #NFS_PLAY
    b.ne 1f
    ldr  x11, [x8, #G_SECS]
    add  x9, x9, x11
1:  subs x0, x9, x0
    csel x0, xzr, x0, lt
    ldp  x29, x30, [sp], #16
    ret

// long am_nf_status(char *buf, long cap), am_nf_mine(buf, cap), am_nf_players(buf, cap),
//   am_nf_result(k, buf, cap) — nf_text.s's lines
.globl _am_nf_status
_am_nf_status:
    stp  x29, x30, [sp, #-32]!
    stp  x0, x1, [sp, #16]
    mov  x0, #0
    bl   _time
    mov  x1, x0
    ldp  x2, x3, [sp, #16]
    ADRL x0, _g_nfg
    bl   _nft_status
    ldp  x29, x30, [sp], #32
    ret
.globl _am_nf_mine
_am_nf_mine:
    mov  x2, x1
    mov  x1, x0
    ADRL x0, _g_nfg
    b    _nft_mine
.globl _am_nf_players
_am_nf_players:
    mov  x2, x1
    mov  x1, x0
    ADRL x0, _g_nfg
    b    _nft_players
.globl _am_nf_result
_am_nf_result:
    mov  x3, x2
    mov  x2, x1
    mov  x1, x0
    ADRL x0, _g_nfg
    b    _nft_result

// long am_nf_new(const long *people, long n, long rounds, long minutes, long family)
//   -> the game room's index, or -1: what "ninefold with ..." does, for the iPhone's sheet
.globl _am_nf_new
_am_nf_new:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    ADRL x0, _g_nf_buf                    // the same words as typed: names by index
    strb wzr, [x0]
    mov  x24, #0
1:  cmp  x24, x20
    b.hs 2f
    ldr  x9, [x19, x24, lsl #3]
    ADRL x8, _g_node_count
    ldr  x10, [x8]
    cmp  x9, x10
    b.hs 3f
    ADRL x8, _g_nodes
    add  x1, x8, x9, lsl #NODE_SHIFT
    add  x1, x1, #N_NICK
    ADRL x0, _g_nf_buf
    mov  x2, #600
    bl   _strlcat
    ADRL x0, _g_nf_buf
    ADRL x1, Ls_comma
    mov  x2, #600
    bl   _strlcat
3:  add  x24, x24, #1
    b    1b
2:  ADRL x0, _g_nf_pkt                     // ", 3 rounds, 4 minutes, family on"
    mov  x1, #120
    ADRL x2, Ls_nf_newopts
    str  x21, [sp]
    str  x22, [sp, #8]
    ADRL x9, Ls_on
    ADRL x10, Ls_off
    cmp  x23, #0
    csel x9, x10, x9, eq
    str  x9, [sp, #16]
    bl   _snprintf
    ADRL x0, _g_nf_buf
    ADRL x1, _g_nf_pkt
    mov  x2, #600
    bl   _strlcat
    mov  x0, #0                           // _h_ninefold copies it before cutting it up
    mov  x1, #0
    ADRL x2, _g_nf_buf
    bl   _h_ninefold
    bl   _am_nf_room
    LEAVE 32

// ---------------------------------------------------------------------------
.section __TEXT,__const
Lnf_outer:      .byte 0, 1, 2, 3, 5, 6, 7, 8, 0

.section __DATA,__const                   // a table of addresses: the linker fills them in
.p2align 3
Lhw_table:
    .quad Lhw_with, 0, Lhw_and, 0, Lhw_rounds, 1, Lhw_round, 1, Lhw_minutes, 2, Lhw_minute, 2
    .quad Lhw_min, 2, Lhw_mins, 2, Lhw_family, 0, Lhw_off, 3, Lhw_on, 4, Lhw_filter, 0, 0, 0

.section __TEXT,__cstring,cstring_literals
Ls_empty:       .asciz ""
Ls_comma:       .asciz ", "
Ls_on:          .asciz "on"
Ls_off:         .asciz "off"
Lhw_with:       .asciz "with"
Lhw_and:        .asciz "and"
Lhw_rounds:     .asciz "rounds"
Lhw_round:      .asciz "round"
Lhw_minutes:    .asciz "minutes"
Lhw_minute:     .asciz "minute"
Lhw_min:        .asciz "min"
Lhw_mins:       .asciz "mins"
Lhw_family:     .asciz "family"
Lhw_filter:     .asciz "filter"
Lhw_off:        .asciz "off"
Lhw_on:         .asciz "on"
Ls_nf_w_start:  .asciz "start"
Ls_nf_w_shuffle: .asciz "shuffle"
Ls_nf_w_words:  .asciz "words"
Ls_nf_room:     .asciz "Ninefold %s"
Ls_nf_dlg_title: .asciz "Play Ninefold"
Ls_nf_dlg_info: .asciz "A word game with people on the mesh: nine letters, words of 4 to 9 letters using the centre one, nobody sees your words until the round ends. Who to invite, with commas between names (everyone on the mesh now is filled in). You can add \342\200\2343 rounds\342\200\235, \342\200\2342 minutes\342\200\235 or \342\200\234family off\342\200\235."
Ls_nf_dlg_ph:   .asciz "Anna, Sam"
Ls_nf_newopts:  .asciz "%ld rounds, %ld minutes, family %s"
Ls_nf_opts:     .asciz "%ld rounds of %ld minutes, family filter %s"
Ls_nf_lobby:    .asciz "\302\267 \360\237\247\251 Ninefold: %s invited (%s). When they\342\200\231ve joined, type start."
Ls_nf_alone:    .asciz "\302\267 \360\237\247\251 Ninefold (%s). Invite people (Mesh \342\200\272 Invite\342\200\246), then type start."
Ls_nf_nokey:    .asciz "\302\267 Can\342\200\231t invite %s yet: their key hasn\342\200\231t arrived. Invite them from the room in a few seconds."
Ls_nf_set:      .asciz "\302\267 \360\237\247\251 %s"
Ls_nf_howto:    .asciz "\302\267 Make words of 4 to 9 letters from the tiles; each uses the centre letter, each tile once. Type a word and press Enter: nobody sees your words until the round ends. shuffle moves the tiles; words lists yours."
Ls_nf_go:       .asciz "\302\267 Go!"
Ls_nf_time:     .asciz "\302\267 Time! Checking everyone\342\200\231s words\342\200\246"
Ls_nf_yours:    .asciz "\302\267 Your words: %s"
Ls_nf_none:     .asciz "none yet"
Ls_nf_busy:     .asciz "\302\267 A round is on: wait for it to end."
Ls_nf_nothost:  .asciz "\302\267 The host starts the rounds."
Ls_nf_cant:     .asciz "\302\267 Couldn\342\200\231t start the round."
Ls_nf_lists:    .asciz "\302\267 Can\342\200\231t play %s\342\200\231s game: their word lists aren\342\200\231t the same as yours. Update asmmesh on both."
Ls_nf_nobody:   .asciz "\302\267 Nobody called \342\200\234%s\342\200\235 is on the mesh right now. Names are as People shows them; put commas between them."
Ls_nf_busy_home: .asciz "\302\267 A Ninefold game is being played already."
Ls_nf_full:     .asciz "\302\267 No room for another room: leave one first."
Ls_nf_remote:   .asciz "\302\267 A Ninefold game starts on the device it\342\200\231s played on."
