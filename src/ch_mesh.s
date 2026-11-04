// ch_mesh.s — chess on the mesh and over bitchat (Mac and iPhone): one game at a time. The
// rules are ch_core.s's, the game ch_play.s's; this file moves it:
//   asmmesh   Home: "chess with Anna" (add "black" to play black) makes an invite-only
//             room; moves are game packets sealed with the room's key (MSGF_GAME, 'C')
//   bitchat   in a private bitchat chat: "chess" (or "chess black"). bitchat itself has no
//             chess, so moves go as text ("♟ 12. Nf3 · your move") and theirs are read from
//             what they type ("e5", "Nf6", "O-O", "resign", "draw"). Only text crosses the
//             wall: the game never touches asmmesh's rooms, devices, rules or keys.
//   in the game's room or chat: a move (e4, Nf3, O-O, e2e4), resign, draw, board, moves
// Platform hooks: _ch_ui_show (redraw), _ch_ui_pop (bring the board up).
.include "macros.inc"
.include "ch_defs.inc"

.data
.p2align 3
.globl _g_chg
.zerofill __DATA,__bss,_g_chg,CG_SIZE,4
.zerofill __DATA,__bss,_g_chm_pkt,128,4
.zerofill __DATA,__bss,_g_chm_buf,1200,4
.zerofill __DATA,__bss,_g_chm_line,1200,4
.zerofill __DATA,__bss,_g_chm_nick,32,4     // the other player's name
.zerofill __DATA,__bss,_g_chm_word,32,4
_g_chm_host:    .quad 0                     // 1: we made this game (we send NEW until it's taken)

.text
.p2align 2

// ---------------------------------------------------------------------------
// asmmesh: game packets in the game's room

// void _chm_rx(uint64 room, uint64 sender, const char *nick, const uint8 *data, long len)
//   mesh.s: a 'C' packet in a room we're in, opened with the room's key
.globl _chm_rx
_chm_rx:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    cmp  x23, #2
    b.lo 9f
    ldrb w9, [x22, #1]
    cmp  w9, #CK_NEW
    b.ne 2f
    ADRL x0, _g_chg                       // a new game: are we in it?
    ADRL x8, _g_node_id
    ldr  x1, [x8]
    mov  x2, x20
    mov  x3, x22
    mov  x4, x23
    mov  x5, x19
    bl   _cg_new_in
    cmp  x0, #1
    b.ne 9f
    ADRL x8, _g_chm_host
    str  xzr, [x8]
    ADRL x0, _g_chm_nick
    mov  x1, x21
    mov  x2, #24
    bl   _strlcpy
    bl   Lchm_begun
    b    9f
2:  ADRL x24, _g_chg                      // our game's room, our game's other player
    ldr  x9, [x24, #CG_STATE]
    cbz  x9, 9f
    ldr  x9, [x24, #CG_VIA]
    cmp  x9, #CGV_MESH
    b.ne 9f
    ldr  x9, [x24, #CG_ROOM]
    cmp  x9, x19
    b.ne 9f
    ldr  x9, [x24, #CG_STATE]             // over already: only to know it ended
    str  x9, [sp, #96]
    mov  x0, x24
    mov  x1, x20
    mov  x2, x22
    mov  x3, x23
    ADRL x4, _g_chm_pkt
    bl   _cg_pkt_in
    mov  x20, x0
    cbz  x1, 3f                           // an answer to send (an ASK, or our history)
    mov  x2, x1
    bl   Lchm_room
    tbnz x0, #63, 3f
    ADRL x1, _g_chm_pkt
    bl   _mesh_send_game
3:  cbz  x20, 9f
    ldrb w9, [x22, #1]
    cmp  w9, #CK_MOVE
    b.eq 4f
    cmp  w9, #CK_HIST
    b.eq 4f
    bl   Lchm_state_line                  // resigned, a draw offered or agreed
    b    9f
4:  mov  x0, #0                           // their move
    bl   Lchm_moved
9:  LEAVE 16

// ---------------------------------------------------------------------------
// bitchat: what they typed in the game's chat

// void _chm_bc_text(long room index, uint64 peer, const char *text, long len) — bc_ble.s:
//   a private message shown in its chat. If a chess game against them is going there and
//   it's their move, a move in it is played. Nothing else is done with it.
.globl _chm_bc_text
_chm_bc_text:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ADRL x24, _g_chg
    ldr  x9, [x24, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne 9f
    ldr  x9, [x24, #CG_VIA]
    cmp  x9, #CGV_BITCHAT
    b.ne 9f
    ldr  x9, [x24, #CG_OPP]
    cmp  x9, x20
    b.ne 9f
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    ldr  x10, [x24, #CG_ROOM]
    cmp  x9, x10
    b.ne 9f
    ldrb w9, [x21]                        // "e5" alone, or our own format from another
    cmp  w9, #0xE2                        //   asmmesh ("♟ 12... Nf3 · your move"): a
    b.eq 1f                               //   sentence that starts with a square is chat
    mov  x0, x21
    bl   Lchm_oneword
    cbz  x0, 9f
1:  mov  x0, x21
    mov  x1, x22
    bl   Lchm_word
    cbz  x0, 9f
    ADRL x0, _g_chm_word
    ADRL x1, Ls_w_resign
    bl   _strcasecmp
    cbz  w0, Lbt_resign
    ADRL x0, _g_chm_word
    ADRL x1, Ls_w_draw
    bl   _strcasecmp
    cbz  w0, Lbt_draw
    ADRL x0, _g_chm_word
    bl   _strlen
    mov  x2, x0
    ADRL x1, _g_chm_word
    mov  x0, x24
    bl   _cg_text_in
    cbz  x0, 9f
    mov  x0, #0
    bl   Lchm_moved
    b    9f
Lbt_resign:                               // as their RESIGN packet would
    mov  w9, #CK_RESIGN
    b    Lbt_pkt
Lbt_draw:
    mov  w9, #CK_DRAW
Lbt_pkt:
    ADRL x0, _g_chm_pkt
    mov  w10, #'C'
    strb w10, [x0]
    strb w9, [x0, #1]
    ldr  x10, [x24, #CG_GID]
    stur w10, [x0, #2]
    ldr  x10, [x24, #CG_PLY]
    sturh w10, [x0, #6]
    mov  x0, x24
    mov  x1, x20
    ADRL x2, _g_chm_pkt
    mov  x3, #8
    ADRL x4, _g_chm_buf
    bl   _cg_pkt_in
    cbz  x0, 9f
    bl   Lchm_state_line
9:  LEAVE 16

// Lchm_word(x0 text, x1 len) -> 1 and _g_chm_word: the first word that isn't the ♟ sign or a
//   move number ("12." "12..."); 0 if none
Lchm_word:
    ENTER 0
    mov  x19, x0
    add  x20, x0, x1
1:  cmp  x19, x20                         // skip spaces and the sign (E2 99 9F)
    b.hs 8f
    ldrb w9, [x19]
    cmp  w9, #' '
    b.ne 2f
    add  x19, x19, #1
    b    1b
2:  cmp  w9, #0xE2
    b.ne 3f
    add  x19, x19, #3
    b    1b
3:  mov  x21, x19                         // a word: x19..x21
4:  cmp  x21, x20
    b.hs 5f
    ldrb w9, [x21]
    cmp  w9, #' '
    b.eq 5f
    add  x21, x21, #1
    b    4b
5:  sub  x9, x21, #1                      // ends with '.': a move number, the next one
    ldrb w9, [x9]
    cmp  w9, #'.'
    b.ne 6f
    mov  x19, x21
    b    1b
6:  sub  x2, x21, x19
    cmp  x2, #24
    b.hs 8f
    ADRL x0, _g_chm_word
    mov  x1, x19
    bl   _memcpy
    ADRL x9, _g_chm_word
    sub  x10, x21, x19
    strb wzr, [x9, x10]
    mov  x0, #1
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// ---------------------------------------------------------------------------
// Typed in the game's room or chat

// long _chm_typed(long room, const char *text) -> 1 if it was for chess (mesh.s: else chat)
.globl _chm_typed
_chm_typed:
    ENTER 64                              // [96] the first word, small (32)
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x21, [x8, #R_ID]                 // the room's id
    ADRL x22, _g_chg
1:  ldrb w9, [x20]
    cmp  w9, #' '
    b.ne 2f
    add  x20, x20, #1
    b    1b
2:  mov  x9, #0                           // the first word, in small letters
3:  ldrb w10, [x20, x9]
    cbz  w10, 4f
    cmp  w10, #' '
    b.eq 4f
    cmp  x9, #30
    b.hs 4f
    orr  w11, w10, #0x20
    sub  w12, w10, #'A'
    cmp  w12, #25
    csel w10, w11, w10, ls
    add  x11, sp, #96
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    3b
4:  add  x11, sp, #96
    strb wzr, [x11, x9]
    add  x0, sp, #96                      // "chess" in a bitchat chat: a game there
    ADRL x1, Ls_w_chess
    bl   _strcmp
    cbz  w0, Lty_chess
    mov  x0, x20                          // more than one word: chat, never a move
    bl   Lchm_oneword
    cbz  x0, Lty_no
    ldr  x9, [x22, #CG_STATE]
    cbz  x9, Lty_no
    ldr  x9, [x22, #CG_ROOM]
    cmp  x9, x21
    b.ne Lty_no
    add  x0, sp, #96
    ADRL x1, Ls_w_resign
    bl   _strcmp
    cbz  w0, Lty_resign
    add  x0, sp, #96
    ADRL x1, Ls_w_draw
    bl   _strcmp
    cbz  w0, Lty_draw
    add  x0, sp, #96
    ADRL x1, Ls_w_board
    bl   _strcmp
    cbz  w0, Lty_board
    add  x0, sp, #96
    ADRL x1, Ls_w_moves
    bl   _strcmp
    cbz  w0, Lty_moves
    mov  x0, x20                          // a move?
    bl   _strlen
    mov  x2, x0
    mov  x0, x22
    mov  x1, x20
    ADRL x3, _g_chm_pkt
    bl   _cg_try
    cmp  x0, #CHP_UNREADABLE
    b.eq Lty_no                           // not a move: chat
    cmp  x0, #20
    b.ne Lty_why
    ldr  x9, [x22, #CG_VIA]
    cmp  x9, #CGV_MESH
    b.ne 5f
    mov  x0, x19
    ADRL x1, _g_chm_pkt
    mov  x2, #20
    bl   _mesh_send_game
    mov  x0, #0
    bl   _time
    str  x0, [x22, #CG_AUX]
5:  mov  x0, #1
    bl   Lchm_moved
    b    Lty_yes
Lty_why:
    ADRL x1, Ls_ch_notyours
    cmp  x0, #CGT_NOTYOURS
    b.eq 6f
    ADRL x1, Ls_ch_over
    cmp  x0, #CGT_NOTPLAYING
    b.eq 6f
    ADRL x1, Ls_ch_ambiguous
    cmp  x0, #CHP_AMBIGUOUS
    b.eq 6f
    ADRL x1, Ls_ch_illegal
6:  mov  x0, x19
    mov  x2, #1
    bl   _room_line
    b    Lty_yes
Lty_resign:
    mov  x0, x22
    ADRL x1, _g_chm_pkt
    bl   _cg_resign
    cbz  x0, Lty_yes
    mov  x2, x0
    ADRL x1, _g_chm_pkt
    ADRL x3, Ls_bc_resign
    bl   Lchm_send
    bl   Lchm_state_line
    b    Lty_yes
Lty_draw:
    mov  x0, x22
    ADRL x1, _g_chm_pkt
    bl   _cg_draw
    cbz  x0, Lty_yes
    mov  x2, x0
    ADRL x1, _g_chm_pkt
    ADRL x3, Ls_bc_draw
    bl   Lchm_send
    bl   Lchm_state_line
    b    Lty_yes
Lty_board:
    mov  x0, x19
    bl   Lchm_board
    b    Lty_yes
Lty_moves:
    mov  x0, x22
    mov  x1, #0
    ADRL x2, _g_chm_buf
    mov  x3, #1200
    bl   _cgt_moves
    ADRL x3, _g_chm_buf
    ADRL x8, Ls_ch_nomoves
    cmp  x0, #0
    csel x3, x8, x3, eq
    mov  x0, x19
    mov  x1, #1
    ADRL x2, Ls_ch_movesfmt
    bl   _room_fmt
    b    Lty_yes
Lty_chess:                                // a game in this bitchat chat (or a new one)
    sub  x9, x21, #BCPM_FIRST
    cmp  x9, #(PM_CHATS - 1)
    b.hi Lty_no                           // elsewhere it's Home's "chess with ..."
    ldr  x9, [x22, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.eq Lty_busy
    mov  x0, x21
    bl   _bc_pm_peer
    cbz  x0, Lty_no
    mov  x23, x0
    mov  x24, #0                          // our colour: "chess black" makes it black
    ldrb w9, [x20, #5]
    cbz  w9, 7f
    add  x0, x20, #6
    ADRL x1, Ls_w_black
    bl   _strcasecmp
    cmp  w0, #0
    mov  x9, #8
    csel x24, x9, x24, eq
7:  bl   _arc4random
    mov  w3, w0
    mov  x0, x22
    mov  x1, #CGV_BITCHAT
    mov  x2, x21
    mov  x4, x24
    ADRL x8, _g_node_id
    ldr  x5, [x8]
    mov  x6, x23
    bl   _cg_start
    ADRL x8, _g_chm_host
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, _g_chm_nick                  // their name: the chat's
    ADRL x8, _g_rooms
    add  x1, x8, x19, lsl #ROOM_SHIFT
    add  x1, x1, #R_NAME
    mov  x2, #24
    bl   _strlcpy
    ADRL x1, Ls_bc_intro_w
    ADRL x8, Ls_bc_intro_b
    cmp  x24, #0
    csel x1, x8, x1, ne
    mov  x0, x21
    bl   _bc_pm_say
    bl   Lchm_begun
    b    Lty_yes
Lty_busy:
    mov  x0, x19
    ADRL x1, Ls_ch_busy
    mov  x2, #1
    bl   _room_line
Lty_yes:
    mov  x0, #1
    LEAVE 64
Lty_no:
    mov  x0, #0
    LEAVE 64

// Lchm_oneword(x0 text) -> 1 if it is one word (spaces around it allowed) (leaf)
Lchm_oneword:
1:  ldrb w9, [x0]                         // spaces before
    cmp  w9, #' '
    b.ne 2f
    add  x0, x0, #1
    b    1b
2:  ldrb w9, [x0]                         // the word
    cbz  w9, 4f
    cmp  w9, #' '
    b.eq 3f
    add  x0, x0, #1
    b    2b
3:  ldrb w9, [x0], #1                     // only spaces after it
    cbz  w9, 4f
    cmp  w9, #' '
    b.eq 3b
    mov  x0, #0
    ret
4:  mov  x0, #1
    ret

// Lchm_send(x1 packet, x2 its length, x3 the same said as text for bitchat)
Lchm_send:
    ENTER 0
    mov  x19, x1
    mov  x20, x2
    mov  x21, x3
    ADRL x8, _g_chg
    ldr  x9, [x8, #CG_VIA]
    cmp  x9, #CGV_MESH
    b.ne 1f
    bl   Lchm_room
    tbnz x0, #63, 9f
    mov  x1, x19
    mov  x2, x20
    bl   _mesh_send_game
    b    9f
1:  ldr  x0, [x8, #CG_ROOM]
    mov  x1, x21
    bl   _bc_pm_say
9:  LEAVE 0

// ---------------------------------------------------------------------------
// Home: "chess with Anna" ("chess with Anna black")

// _h_chess(arg, rest_lc, rest_orig) — rules.s's word table
.globl _h_chess
_h_chess:
    ENTER 96                              // [96] the name (64)  [160] our colour
    mov  x19, x2
    ADRL x8, _g_remote_active
    ldr  x9, [x8]
    cbnz x9, Lhc_remote
    ADRL x22, _g_chg
    ldr  x9, [x22, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.eq Lhc_busy
1:  ldrb w9, [x19]                        // "with " is optional
    cmp  w9, #' '
    b.ne 2f
    add  x19, x19, #1
    b    1b
2:  mov  x0, x19
    ADRL x1, Ls_w_with
    mov  x2, #5
    bl   _strncasecmp
    cbnz w0, 3f
    add  x19, x19, #5
3:  add  x0, sp, #96
    mov  x1, x19
    mov  x2, #64
    bl   _strlcpy
    str  xzr, [sp, #160]
    add  x0, sp, #96                      // a last word "black" or "white"
    bl   _strlen
    mov  x20, x0
    cmp  x20, #6
    b.lo 5f
    add  x0, sp, #96
    add  x0, x0, x20
    sub  x0, x0, #6
    ldrb w9, [x0]
    cmp  w9, #' '
    b.ne 5f
    add  x0, x0, #1
    mov  x21, x0
    ADRL x1, Ls_w_black
    bl   _strcasecmp
    cbnz w0, 4f
    mov  x9, #8
    str  x9, [sp, #160]
    strb wzr, [x21, #-1]
    b    5f
4:  mov  x0, x21
    ADRL x1, Ls_w_white
    bl   _strcasecmp
    cbnz w0, 5f
    strb wzr, [x21, #-1]
5:  ldrb w9, [sp, #96]
    cbz  w9, Lhc_how
    mov  x20, #0                          // who: by name on the mesh
6:  ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lhc_nobody
    ADRL x8, _g_nodes
    add  x0, x8, x20, lsl #NODE_SHIFT
    add  x0, x0, #N_NICK
    add  x1, sp, #96
    bl   _strcasecmp
    cbz  w0, 7f
    add  x20, x20, #1
    b    6b
7:  ADRL x0, _g_chm_buf                   // the room: "Chess" and our name
    mov  x1, #(ROOMNAME_MAX + 1)
    ADRL x2, Ls_ch_room
    ADRL x3, _g_nick
    str  x3, [sp]
    bl   _snprintf
    ADRL x0, _g_chm_buf
    bl   _utf8_fix
    bl   _new_id
    mov  x23, x0
    ADRL x1, _g_chm_buf
    mov  x2, #1
    bl   _room_add
    tbnz x0, #63, Lhc_full
    mov  x21, x0
    bl   _room_own
    mov  x0, x21
    bl   _ui_select_room
    mov  x0, x20                          // invited
    mov  x1, x21
    bl   _mesh_send_invite
    bl   _arc4random                      // the game, set up now; NEW goes until it's taken
    mov  w3, w0
    mov  x0, x22
    mov  x1, #CGV_MESH
    mov  x2, x23
    ldr  x4, [sp, #160]
    ADRL x8, _g_node_id
    ldr  x5, [x8]
    ADRL x8, _g_nodes
    add  x9, x8, x20, lsl #NODE_SHIFT
    ldr  x6, [x9, #N_ID]
    bl   _cg_start
    ADRL x8, _g_chm_host
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, _g_chm_nick
    ADRL x8, _g_nodes
    add  x1, x8, x20, lsl #NODE_SHIFT
    add  x1, x1, #N_NICK
    mov  x2, #24
    bl   _strlcpy
    bl   Lchm_begun
    b    Lhc_done
Lhc_how:
    ADRL x0, Ls_ch_how
    bl   _home_say0
    b    Lhc_done
Lhc_nobody:
    ADRL x0, Ls_ch_nobody
    add  x1, sp, #96
    bl   _home_say
    b    Lhc_done
Lhc_busy:
    ADRL x0, Ls_ch_busy
    bl   _home_say0
    b    Lhc_done
Lhc_full:
    ADRL x0, Ls_ch_full
    bl   _home_say0
    b    Lhc_done
Lhc_remote:
    ADRL x0, Ls_ch_remote
    bl   _home_say0
Lhc_done:
    LEAVE 96

// ---------------------------------------------------------------------------
// Every second (scanner.s, ios_ui.s)

// void _chm_tick(void) — NEW until the game is taken, our last move again until answered
.globl _chm_tick
_chm_tick:
    ENTER 0
    ADRL x19, _g_chg
    ldr  x9, [x19, #CG_STATE]
    cbz  x9, 9f
    ldr  x0, [x19, #CG_ROOM]              // the room or chat gone: so is the game
    bl   _room_find
    tbz  x0, #63, 1f
    str  xzr, [x19, #CG_STATE]
    bl   _ch_ui_show
    b    9f
1:  mov  x20, x0
    ldr  x9, [x19, #CG_STATE]
    cmp  x9, #CGS_PLAY
    b.ne 9f
    ldr  x9, [x19, #CG_VIA]
    cmp  x9, #CGV_MESH
    b.ne 9f
    mov  x0, #0
    bl   _time
    mov  x21, x0
    ldr  x9, [x19, #CG_AUX]
    sub  x9, x21, x9
    cmp  x9, #10
    b.lo 9f
    str  x21, [x19, #CG_AUX]
    ADRL x8, _g_chm_host                  // NEW, until they've made a move
    ldr  x9, [x8]
    cbz  x9, 2f
    ldr  x9, [x19, #CG_PLY]
    ldr  x10, [x19, #CG_ME]
    mov  x11, #2                          // white: their first move is the second
    cbz  x10, 11f
    mov  x11, #1
11: cmp  x9, x11
    b.hs 2f
    mov  x0, x19
    ADRL x1, _g_chm_pkt
    bl   _cg_pkt_new
    mov  x2, x0
    mov  x0, x20
    ADRL x1, _g_chm_pkt
    bl   _mesh_send_game
2:  ldrb w9, [x19, #(CG_POS + CP_SIDE)]   // their move: ours again, in case it was lost
    ldr  x10, [x19, #CG_ME]
    cmp  x9, x10
    b.eq 9f
    mov  x0, x19
    ADRL x1, _g_chm_pkt
    bl   _cg_pkt_last
    cbz  x0, 9f
    mov  x2, x0
    mov  x0, x20
    ADRL x1, _g_chm_pkt
    bl   _mesh_send_game
9:  LEAVE 0

// ---------------------------------------------------------------------------
// Lines in the room, and the screens

// Lchm_begun — a game was set up (ours or theirs): say so, bring the board up
Lchm_begun:
    ENTER 0
    bl   Lchm_room
    tbnz x0, #63, 9f
    mov  x19, x0
    ADRL x8, _g_chg
    ldr  x9, [x8, #CG_ME]
    ADRL x4, Ls_ch_white
    ADRL x10, Ls_ch_black
    cmp  x9, #0
    csel x4, x10, x4, ne
    mov  x0, x19
    mov  x1, #1
    ADRL x2, Ls_ch_begun
    ADRL x3, _g_chm_nick
    bl   _room_fmt
9:  bl   _ch_ui_pop
    LEAVE 0

// Lchm_moved(x0 1 ours, 0 theirs) — the move in the room ("♟ Anna: 12... Nf3+"); over
//   bitchat ours goes as text too; if that ended the game, how
Lchm_moved:
    ENTER 0
    mov  x19, x0
    bl   Lchm_room
    tbnz x0, #63, 9f
    mov  x20, x0
    ADRL x21, _g_chg
    mov  x0, x21                          // the last move, numbered
    ldr  x1, [x21, #CG_PLY]
    sub  x1, x1, #1
    ADRL x2, _g_chm_buf
    mov  x3, #200
    bl   _cgt_moves
    ADRL x3, Ls_ch_you
    cbnz x19, 1f
    ADRL x3, _g_chm_nick
1:  mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_ch_movedfmt
    ADRL x4, _g_chm_buf
    bl   _room_fmt
    cbz  x19, 3f                          // ours, over bitchat: as text for them
    ldr  x9, [x21, #CG_VIA]
    cmp  x9, #CGV_BITCHAT
    b.ne 3f
    ADRL x0, _g_chm_line
    mov  x1, #300
    ADRL x2, Ls_bc_movefmt
    ADRL x3, _g_chm_buf
    str  x3, [sp]
    ADRL x3, Ls_bc_yourmove
    ldr  x9, [x21, #CG_STATE]
    cmp  x9, #CGS_OVER
    b.ne 2f
    ADRL x3, Ls_bc_over
2:  str  x3, [sp, #8]
    bl   _snprintf
    ldr  x0, [x21, #CG_ROOM]
    ADRL x1, _g_chm_line
    bl   _bc_pm_say
3:  ldr  x9, [x21, #CG_STATE]
    cmp  x9, #CGS_OVER
    b.ne 9f
    bl   Lchm_state_line
9:  bl   _ch_ui_pop
    LEAVE 0

// Lchm_state_line — the status as a line in the room (game over, a draw offered...)
Lchm_state_line:
    ENTER 0
    bl   Lchm_room
    tbnz x0, #63, 9f
    mov  x19, x0
    ADRL x0, _g_chg
    ADRL x1, _g_chm_buf
    mov  x2, #300
    bl   _cgt_status
    mov  x0, x19
    mov  x1, #1
    ADRL x2, Ls_ch_statefmt
    ADRL x3, _g_chm_buf
    bl   _room_fmt
9:  bl   _ch_ui_show
    LEAVE 0

// Lchm_board(x0 room) — the board as nine lines, from our side
Lchm_board:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
1:  ADRL x0, _g_chg
    mov  x1, x20
    ADRL x2, _g_chm_buf
    mov  x3, #200
    bl   _cgt_row
    mov  x0, x19
    ADRL x1, _g_chm_buf
    mov  x2, #1
    bl   _room_line
    add  x20, x20, #1
    cmp  x20, #9
    b.lo 1b
    LEAVE 0

// Lchm_room -> x0 the game's room index, or -1
Lchm_room:
    ENTER 0
    ADRL x8, _g_chg
    ldr  x9, [x8, #CG_STATE]
    mov  x0, #-1
    cbz  x9, 9f
    ldr  x0, [x8, #CG_ROOM]
    bl   _room_find
9:  LEAVE 0

// ---------------------------------------------------------------------------
// For the boards (Mac window, iPhone screen)

// long am_ch_state(void) -> 0 none, 2 playing, 3 over
.globl _am_ch_state
_am_ch_state:
    ADRL x8, _g_chg
    ldr  x0, [x8, #CG_STATE]
    ret

// long am_ch_room(void) -> the game's room index, or -1
.globl _am_ch_room
_am_ch_room:
    b    Lchm_room

// long am_ch_me(void) -> 0 we're white, 8 black
.globl _am_ch_me
_am_ch_me:
    ADRL x8, _g_chg
    ldr  x0, [x8, #CG_ME]
    ret

// long am_ch_piece(long square) -> the piece on it (0 empty, 1-6 white, 9-14 black)
.globl _am_ch_piece
_am_ch_piece:
    and  x0, x0, #0x7F                    // on the 128-byte board
    ADRL x8, _g_chg
    add  x8, x8, #CG_POS
    ldrb w0, [x8, x0]
    ret

// long am_ch_last(void) -> the last move (from | to << 8), or -1 before the first
.globl _am_ch_last
_am_ch_last:
    ADRL x8, _g_chg
    ldr  x9, [x8, #CG_PLY]
    mov  x0, #-1
    cbz  x9, 1f
    sub  x9, x9, #1
    add  x10, x8, #CG_MOVES
    ldr  w0, [x10, x9, lsl #2]
    and  w0, w0, #0xFFFF
1:  ret

// long am_ch_targets(long square, uint8 out[32]) -> where the piece there may go now
.globl _am_ch_targets
_am_ch_targets:
    mov  x2, x1
    mov  x1, x0
    ADRL x0, _g_chg
    b    _cg_targets

// long am_ch_status(char *buf, long cap), am_ch_moves(buf, cap) — the words
.globl _am_ch_status
_am_ch_status:
    mov  x2, x1
    mov  x1, x0
    ADRL x0, _g_chg
    b    _cgt_status
.globl _am_ch_moves
_am_ch_moves:
    mov  x3, x1
    mov  x2, x0
    mov  x1, #0
    ADRL x0, _g_chg
    b    _cgt_moves

// const char *am_ch_opponent(void) — their name
.globl _am_ch_opponent
_am_ch_opponent:
    ADRL x0, _g_chm_nick
    ret

// long am_ch_move(long from, long to) -> 1 if played: a move made on the board, sent as if
//   typed ("e2e4", a pawn reaching the end becoming a queen)
.globl _am_ch_move
_am_ch_move:
    ENTER 16                              // [96] "e2e4q"
    and  x19, x0, #0x7F
    and  x20, x1, #0x7F
    and  w9, w19, #7
    add  w9, w9, #'a'
    strb w9, [sp, #96]
    lsr  w9, w19, #4
    add  w9, w9, #'1'
    strb w9, [sp, #97]
    and  w9, w20, #7
    add  w9, w9, #'a'
    strb w9, [sp, #98]
    lsr  w9, w20, #4
    add  w9, w9, #'1'
    strb w9, [sp, #99]
    strb wzr, [sp, #100]
    ADRL x8, _g_chg
    add  x9, x8, #CG_POS
    ldrb w10, [x9, x19]
    and  w10, w10, #7
    cmp  w10, #1
    b.ne 1f
    lsr  w11, w20, #4
    cbz  w11, 2f
    cmp  w11, #7
    b.ne 1f
2:  mov  w9, #'q'
    strb w9, [sp, #100]
    strb wzr, [sp, #101]
1:  ldr  x21, [x8, #CG_PLY]
    bl   Lchm_room
    tbnz x0, #63, 8f
    add  x1, sp, #96
    bl   _chm_typed
    ADRL x8, _g_chg
    ldr  x9, [x8, #CG_PLY]
    cmp  x9, x21
    cset x0, hi
    LEAVE 16
8:  mov  x0, #0
    LEAVE 16

// void am_ch_say(const char *word) — resign / draw from a button, as if typed in the room
.globl _am_ch_say
_am_ch_say:
    ENTER 0
    mov  x19, x0
    bl   Lchm_room
    tbnz x0, #63, 9f
    mov  x1, x19
    bl   _chm_typed
9:  LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_w_chess:     .asciz "chess"
Ls_w_resign:    .asciz "resign"
Ls_w_draw:      .asciz "draw"
Ls_w_board:     .asciz "board"
Ls_w_moves:     .asciz "moves"
Ls_w_black:     .asciz "black"
Ls_w_white:     .asciz "white"
Ls_w_with:      .asciz "with "
Ls_ch_room:     .asciz "Chess %s"
Ls_ch_white:    .asciz "white (you move first)"
Ls_ch_black:    .asciz "black"
Ls_ch_begun:    .asciz "\342\231\237 Chess with %s: you play %s. Type moves here (e4, Nf3, O-O, e2e4), or resign, draw, board, moves."
Ls_ch_you:      .asciz "you"
Ls_ch_movedfmt: .asciz "\342\231\237 %s: %s"
Ls_ch_statefmt: .asciz "\342\231\237 %s"
Ls_ch_movesfmt: .asciz "\342\231\237 %s"
Ls_ch_nomoves:  .asciz "no moves yet"
Ls_ch_notyours: .asciz "\302\267 It\342\200\231s their move."
Ls_ch_over:     .asciz "\302\267 The game is over."
Ls_ch_illegal:  .asciz "\302\267 That isn\342\200\231t a legal move here."
Ls_ch_ambiguous: .asciz "\302\267 That could be more than one move: say which piece (Nbd2, R1e2)."
Ls_ch_busy:     .asciz "\302\267 A chess game is being played already."
Ls_ch_how:      .asciz "\302\267 Chess: chess with Anna (as People shows the name; add black to play black). In a private bitchat chat: chess."
Ls_ch_nobody:   .asciz "\302\267 Nobody called \342\200\234%s\342\200\235 is on the mesh right now."
Ls_ch_full:     .asciz "\302\267 No room for another room: leave one first."
Ls_ch_remote:   .asciz "\302\267 A chess game starts on the device it\342\200\231s played on."
Ls_bc_intro_w:  .asciz "\342\231\237 Chess? I\342\200\231m white, you\342\200\231re black. Type your moves here (e5, Nf6, O-O), or resign or draw. (On asmmesh: type chess black.)"
Ls_bc_intro_b:  .asciz "\342\231\237 Chess? I\342\200\231m black: you\342\200\231re white, your move. Type moves here (e4, Nf3, O-O), or resign or draw. (On asmmesh: type chess.)"
Ls_bc_movefmt:  .asciz "\342\231\237 %s \302\267 %s"
Ls_bc_yourmove: .asciz "your move"
Ls_bc_over:     .asciz "game over"
Ls_bc_resign:   .asciz "\342\231\237 resign (I give up)"
Ls_bc_draw:     .asciz "\342\231\237 draw (I offer a draw, or accept yours)"
