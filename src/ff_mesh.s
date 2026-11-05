// ff_mesh.s — Fivefold on the Mac and iPhone: the day's word alone, a race or a duel in an
// invite-only room. The rules are ff_core.s's, the game ff_play.s's; this file starts games,
// moves their packets (room messages flagged MSGF_GAME, byte 0 'F'), keeps sending what
// hasn't arrived, saves the day's game (so it can't be played again by reopening the app),
// and gives the screens what to show.
//   Home: fivefold · fivefold race with Anna, Sam · fivefold duel with Anna · fivefold share
//   in the game's room: a five-letter word (a duel: first the word for them)
// Platform hooks: _ff_ui_show (redraw), _ff_ui_pop (bring the game up).
.include "macros.inc"
.include "ff_defs.inc"

.data
.p2align 3
.globl _g_ffs
.globl _g_ffg
.zerofill __DATA,__bss,_g_ffs,FG_SIZE,4     // the day's game, alone
.zerofill __DATA,__bss,_g_ffg,FG_SIZE,4     // a race or a duel
.zerofill __DATA,__bss,_g_ff_pkt,64,4
.zerofill __DATA,__bss,_g_ff_reply,64,4
.zerofill __DATA,__bss,_g_ff_buf,1024,4
.zerofill __DATA,__bss,_g_ff_names,160,4
_g_ff_seed:     .quad 0                     // a race's seed (the host sends it)
_g_ff_last:     .quad 0                     // when we last sent again
_g_ff_res:      .quad 0                     // what the last typed guess gave (the screens)

.text
.p2align 2

// ---------------------------------------------------------------------------
// The day's word

// void _ffm_solo(void) — today's game, as far as it got (restored from the defaults)
.globl _ffm_solo
_ffm_solo:
    ENTER 16
    mov  x0, #0
    bl   _time
    bl   _ff_daily
    mov  x19, x0                          // today
    ADRL x20, _g_ffs
    ldr  x9, [x20, #FG_MODE]
    cbz  x9, 1f
    ldr  x9, [x20, #FG_DAY]
    cmp  x9, x19
    b.eq 9f                               // today's, going already
1:  mov  x0, x20
    mov  x1, #FFM_SOLO
    mov  x2, x19
    mov  x3, #0
    mov  x4, #0
    ADRL x8, _g_node_id
    ldr  x5, [x8]
    mov  x6, #0
    bl   _ffp_begin
    ADRL x0, Ls_k_solo                    // "day:guess,guess,..." for today: played again
    ADRL x1, _g_ff_buf
    mov  x2, #128
    bl   _pref_get
    ADRL x21, _g_ff_buf
    mov  x22, #0                          // the day written there
2:  ldrb w9, [x21], #1
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.hi 3f
    mov  x11, #10
    madd x22, x22, x11, x10
    b    2b
3:  cmp  w9, #':'
    b.ne 9f
    cmp  x22, x19
    b.ne 9f
4:  ldrb w9, [x21]                        // each guess (5 letters, then , or the end)
    cbz  w9, 9f
    mov  x0, x20
    mov  x1, x21
    mov  x2, #5
    ADRL x3, _g_ff_pkt
    bl   _ffp_guess
    tbnz x0, #63, 9f
    add  x21, x21, #5
    ldrb w9, [x21]
    cbz  w9, 9f
    add  x21, x21, #1
    b    4b
9:  LEAVE 16

// Lffm_solo_save — today's guesses into the defaults
Lffm_solo_save:
    ENTER 32                              // [96] "day:"
    ADRL x19, _g_ffs
    ADRL x0, _g_ff_buf
    mov  x1, #32
    ADRL x2, Ls_dayfmt
    ldr  x9, [x19, #FG_DAY]
    str  x9, [sp]
    bl   _snprintf
    mov  x20, #0
1:  ldr  x9, [x19, #FG_N]
    cmp  x20, x9
    b.hs 3f
    cbz  x20, 2f
    ADRL x0, _g_ff_buf
    ADRL x1, Ls_comma
    mov  x2, #128
    bl   _strlcat
2:  mov  x9, #5
    mul  x9, x20, x9
    add  x9, x9, #FG_GUESS
    add  x9, x19, x9
    ldr  w10, [x9]
    str  w10, [sp, #96]
    ldrb w10, [x9, #4]
    strb w10, [sp, #100]
    strb wzr, [sp, #101]
    ADRL x0, _g_ff_buf
    add  x1, sp, #96
    mov  x2, #128
    bl   _strlcat
    add  x20, x20, #1
    b    1b
3:  ADRL x0, Ls_k_solo
    ADRL x1, _g_ff_buf
    bl   _pref_set
    LEAVE 32

// ---------------------------------------------------------------------------
// Home: fivefold · fivefold race with ... · fivefold duel with ... · fivefold share

// _h_fivefold(arg, rest_lc, rest_orig) — arg: 1 the day's word, 2 race, 3 duel, 4 share
.globl _h_fivefold
_h_fivefold:
    ENTER 288                             // [96] the text (160)  [256] the people (8)
    mov  x19, x0                          //   [264] how many
    mov  x20, x2
    ADRL x8, _g_remote_active
    ldr  x9, [x8]
    cbnz x9, Lhf_remote
    cmp  x19, #4
    b.eq Lhf_share
    cmp  x19, #5
    b.eq Lhf_how
    cmp  x19, #1
    b.ne Lhf_people
    bl   _ffm_solo
    ADRL x0, Ls_solo_line
    bl   _home_say0
    bl   _ff_ui_pop
    b    Lhf_done
Lhf_people:                               // names, by commas (or spaces)
    ADRL x8, _g_ffg
    ldr  x9, [x8, #FG_STATE]
    cmp  x9, #FFS_CHOOSE
    b.lo 1f
    cmp  x9, #FFS_DONE
    b.lo Lhf_busy
1:  add  x0, sp, #96
    mov  x1, x20
    mov  x2, #160
    bl   _strlcpy
    strb wzr, [sp, #264]
    add  x0, sp, #96
    bl   Lff_trim
    mov  x21, x0
    mov  x0, x21                          // "with " is optional
    ADRL x1, Ls_with
    mov  x2, #5
    bl   _strncasecmp
    cbnz w0, 2f
    add  x21, x21, #5
2:  ldrb w9, [x21]                        // each name
    cbz  w9, Lhf_go
    mov  x22, x21
3:  ldrb w9, [x22]
    cbz  w9, 4f
    cmp  w9, #','
    b.eq 4f
    add  x22, x22, #1
    b    3b
4:  mov  x23, x22
    cbz  w9, 5f
    strb wzr, [x22]
    add  x23, x22, #1
5:  mov  x0, x21
    bl   Lff_trim
    mov  x21, x0
    ldrb w9, [x21]
    cbz  w9, 6f
    mov  x0, x21
    bl   Lff_node
    tbnz x0, #63, Lhf_nobody
    ldrb w9, [sp, #264]                   // 8 at most (a duel: 1)
    cmp  w9, #(FF_PLAYERS - 1)
    b.hs 6f
    add  x10, sp, #256
    strb w0, [x10, x9]
    add  w9, w9, #1
    strb w9, [sp, #264]
6:  mov  x21, x23
    b    2b
Lhf_go:
    ldrb w24, [sp, #264]
    cbz  w24, Lhf_how
    cmp  x19, #3
    b.ne 7f
    cmp  w24, #1
    b.ne Lhf_onlyone
7:  ADRL x0, _g_ff_buf                    // the room: "Fivefold" and our name
    mov  x1, #(ROOMNAME_MAX + 1)
    ADRL x2, Ls_room
    ADRL x3, _g_nick
    str  x3, [sp]
    bl   _snprintf
    ADRL x0, _g_ff_buf
    bl   _utf8_fix
    bl   _new_id
    mov  x22, x0
    ADRL x1, _g_ff_buf
    mov  x2, #1
    bl   _room_add
    tbnz x0, #63, Lhf_full
    mov  x21, x0
    bl   _room_own
    mov  x0, x21
    bl   _ui_select_room
    mov  x23, #0                          // invited
8:  cmp  x23, x24
    b.hs 9f
    add  x9, sp, #256
    ldrb w0, [x9, x23]
    mov  x1, x21
    bl   _mesh_send_invite
    add  x23, x23, #1
    b    8b
9:  bl   _arc4random                      // the game
    mov  w23, w0
    cmp  x19, #2
    b.ne Lhf_duel
    add  x0, sp, #272                     // a race: a seed, the word from it
    mov  x1, #8
    bl   _arc4random_buf
    ldr  x9, [sp, #272]
    ADRL x8, _g_ff_seed
    str  x9, [x8]
    mov  x0, x9
    bl   _ff_pick
    mov  x2, x0
    ADRL x0, _g_ffg
    mov  x1, #FFM_RACE
    mov  x3, x22
    mov  x4, x23
    ADRL x8, _g_node_id
    ldr  x5, [x8]
    mov  x6, x5
    bl   _ffp_begin
    ADRL x8, _g_ff_last
    str  xzr, [x8]
    mov  x0, x21
    ADRL x1, Ls_race_line
    mov  x2, #1
    bl   _room_line
    bl   _ff_ui_pop
    b    Lhf_done
Lhf_duel:
    ldrb w9, [sp, #256]
    ADRL x8, _g_nodes
    add  x9, x8, x9, lsl #NODE_SHIFT
    ldr  x6, [x9, #N_ID]
    ADRL x0, _g_ffg
    mov  x1, #FFM_DUEL
    mov  x2, #-1
    mov  x3, x22
    mov  x4, x23
    ADRL x8, _g_node_id
    ldr  x5, [x8]
    bl   _ffp_begin
    mov  x0, x21
    ADRL x1, Ls_duel_line
    mov  x2, #1
    bl   _room_line
    bl   _ff_ui_pop
    b    Lhf_done
Lhf_share:                                // the last finished game's squares, to Main
    bl   Lff_current
    cbz  x0, 1f
    ldr  x9, [x0, #FG_STATE]
    cmp  x9, #FFS_DONE
    b.ne 1f
    ADRL x1, _g_ff_buf
    mov  x2, #400
    bl   _ffpt_share
    ADRL x9, _g_ff_buf                    // one line: rows by spaces (chat has no new lines)
2:  ldrb w10, [x9]
    cbz  w10, 3f
    cmp  w10, #10
    b.ne 21f
    mov  w10, #' '
    strb w10, [x9]
21: add  x9, x9, #1
    b    2b
3:  mov  x0, #0
    ADRL x1, _g_ff_buf
    mov  w2, #0
    bl   _mesh_send_msg
    ADRL x0, Ls_shared
    bl   _home_say0
    b    Lhf_done
1:  ADRL x0, Ls_noshare
    bl   _home_say0
    b    Lhf_done
Lhf_how:
    ADRL x0, Ls_how
    bl   _home_say0
    b    Lhf_done
Lhf_onlyone:
    ADRL x0, Ls_onlyone
    bl   _home_say0
    b    Lhf_done
Lhf_nobody:
    ADRL x0, Ls_nobody
    mov  x1, x21
    bl   _home_say
    b    Lhf_done
Lhf_busy:
    ADRL x0, Ls_busy
    bl   _home_say0
    b    Lhf_done
Lhf_full:
    ADRL x0, Ls_full
    bl   _home_say0
    b    Lhf_done
Lhf_remote:
    ADRL x0, Ls_remote
    bl   _home_say0
Lhf_done:
    LEAVE 288

// Lff_node(x0 name) -> the node's index, or -1
Lff_node:
    ENTER 0
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
    LEAVE 0
3:  mov  x0, x20
    LEAVE 0

// Lff_trim(x0 s) -> s without spaces around it (leaf)
Lff_trim:
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

// game *Lff_current -> the game the screens show: a race or duel whose room is here, else
//   the day's word (0: neither)
Lff_current:
    ENTER 0
    ADRL x19, _g_ffg
    ldr  x9, [x19, #FG_MODE]
    cbz  x9, 1f
    ldr  x0, [x19, #FG_ROOM]
    bl   _room_find
    tbnz x0, #63, 1f
    mov  x0, x19
    LEAVE 0
1:  ADRL x0, _g_ffs
    ldr  x9, [x0, #FG_MODE]
    cmp  x9, #0
    csel x0, xzr, x0, eq
    LEAVE 0

// ---------------------------------------------------------------------------
// From the mesh, and every second

// void _ffm_rx(uint64 room, uint64 sender, const char *nick, const uint8 *data, long len)
//   mesh.s: an 'F' packet in a room we're in
.globl _ffm_rx
_ffm_rx:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    cmp  x23, #6
    b.lo 9f
    ADRL x24, _g_ffg
    ldur w9, [x22, #2]                    // a game we don't have yet?
    ldr  x10, [x24, #FG_GID]
    ldr  x11, [x24, #FG_MODE]
    cbz  x11, 1f
    cmp  x9, x10
    b.eq 3f
    ldr  x11, [x24, #FG_STATE]            // another game: only once ours is over
    cmp  x11, #FFS_DONE
    b.ne 9f
1:  ldrb w10, [x22, #1]
    cmp  w10, #FK_RACE
    b.eq 2f
    cmp  w10, #FK_DUEL
    b.ne 9f
    mov  x0, x24                          // their sealed word: a duel with us
    mov  x1, #FFM_DUEL
    mov  x2, #-1
    mov  x3, x19
    mov  w4, w9
    ADRL x8, _g_node_id
    ldr  x5, [x8]
    mov  x6, x20
    bl   _ffp_begin
    mov  x0, x19
    bl   _room_find
    tbnz x0, #63, 3f
    ADRL x1, Ls_duel_line
    mov  x2, #1
    bl   _room_line
    bl   _ff_ui_pop
    b    3f
2:  cmp  x23, #14                         // a race: the word from its seed
    b.lo 9f
    str  x9, [sp, #96]
    ldur x0, [x22, #6]
    bl   _ff_pick
    mov  x2, x0
    mov  x0, x24
    mov  x1, #FFM_RACE
    mov  x3, x19
    ldr  x4, [sp, #96]
    ADRL x8, _g_node_id
    ldr  x5, [x8]
    mov  x6, x20
    bl   _ffp_begin
    mov  x0, x19
    bl   _room_find
    tbnz x0, #63, 9f
    ADRL x1, Ls_race_line
    mov  x2, #1
    bl   _room_line
    bl   _ff_ui_pop
    b    9f
3:  ldr  x9, [x24, #FG_ROOM]              // our game's packet
    cmp  x9, x19
    b.ne 9f
    ldrb w9, [x22, #1]                    // their reveal again: they may not have ours
    cmp  w9, #FK_REVEAL
    b.ne 4f
    ldr  x9, [x24, #FG_CHECK]
    cbz  x9, 4f
    ADRL x8, _g_ff_last
    str  xzr, [x8]
4:  mov  x0, x21
    bl   _strlen
    mov  x3, x0
    mov  x0, x24
    mov  x1, x20
    mov  x2, x21
    mov  x4, x22
    mov  x5, x23
    ADRL x6, _g_ff_reply
    bl   _ffp_pkt_in
    mov  x21, x0
    cbz  x1, 5f
    mov  x23, x1                          // (the reply's length, kept across the call)
    mov  x0, x19
    bl   _room_find
    tbnz x0, #63, 5f
    ADRL x1, _g_ff_reply
    mov  x2, x23
    bl   _mesh_send_game
5:  cbz  x21, 9f
    bl   Lffm_after
9:  LEAVE 16

// Lffm_after — something changed in the race or duel: a line if it ended, the screens
Lffm_after:
    ENTER 0
    ADRL x19, _g_ffg
    ldr  x0, [x19, #FG_ROOM]
    bl   _room_find
    tbnz x0, #63, 8f
    mov  x20, x0
    ldr  x9, [x19, #FG_CHECK]             // a duel decided: say so once
    cbz  x9, 8f
    ldr  x9, [x19, #FG_AUX]
    cbnz x9, 8f
    mov  x9, #1
    str  x9, [x19, #FG_AUX]
    mov  x0, x19
    ADRL x1, _g_ff_buf
    mov  x2, #400
    bl   _ffpt_status
    mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_said
    ADRL x3, _g_ff_buf
    bl   _room_fmt
8:  bl   _ff_ui_show
    LEAVE 0

// void _ffm_tick(void) — every second: send again what hasn't been taken (every 10 s): a
//   race's word (the host), our sealed word until they guess, a guess not answered, our
//   reveal until theirs comes
.globl _ffm_tick
_ffm_tick:
    ENTER 0
    ADRL x19, _g_ffg
    ldr  x9, [x19, #FG_MODE]
    cbz  x9, 9f
    ldr  x0, [x19, #FG_ROOM]              // the room gone: so is the game
    bl   _room_find
    tbz  x0, #63, 1f
    str  xzr, [x19, #FG_MODE]
    str  xzr, [x19, #FG_STATE]
    bl   _ff_ui_show
    b    9f
1:  mov  x20, x0
    mov  x0, #0
    bl   _time
    ADRL x8, _g_ff_last
    ldr  x9, [x8]
    sub  x10, x0, x9
    cmp  x10, #10
    b.lo 9f
    str  x0, [x8]
    ldr  x9, [x19, #FG_MODE]
    cmp  x9, #FFM_RACE
    b.ne 3f
    ldr  x9, [x19, #FG_HOST]              // the host: the race's word, for late joiners
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne 9f
    ADRL x21, _g_ff_pkt
    mov  w9, #'F'
    strb w9, [x21]
    mov  w9, #FK_RACE
    strb w9, [x21, #1]
    ldr  x9, [x19, #FG_GID]
    stur w9, [x21, #2]
    ADRL x8, _g_ff_seed
    ldr  x9, [x8]
    stur x9, [x21, #6]
    mov  x0, x20
    mov  x1, x21
    mov  x2, #14
    bl   _mesh_send_game
    b    9f
3:  ldr  x9, [x19, #FG_TN]                // a duel: our word, sealed, until they guess
    cbnz x9, 4f
    mov  x0, x19
    ADRL x1, _g_ff_pkt
    bl   _ffp_pkt_duel
    cbz  x0, 4f
    mov  x2, x0
    mov  x0, x20
    ADRL x1, _g_ff_pkt
    bl   _mesh_send_game
4:  mov  x0, x19                          // a guess not answered yet
    ADRL x1, _g_ff_pkt
    bl   _ffp_pending
    cbz  x0, 5f
    mov  x2, x0
    mov  x0, x20
    ADRL x1, _g_ff_pkt
    bl   _mesh_send_game
5:  ldr  x9, [x19, #FG_CHECK]             // our reveal, until theirs came
    cbnz x9, 9f
    mov  x0, x19
    ADRL x1, _g_ff_pkt
    bl   _ffp_pkt_reveal
    cbz  x0, 9f
    mov  x2, x0
    mov  x0, x20
    ADRL x1, _g_ff_pkt
    bl   _mesh_send_game
9:  LEAVE 0

// long _ffm_typed(long room, const char *text) -> 1 if it was for the game in this room
//   (mesh.s: else chat). A duel: first the word for them, then guesses. A race: guesses.
.globl _ffm_typed
_ffm_typed:
    ENTER 32                              // [96] salt (16)
    mov  x19, x0
    mov  x20, x1
    ADRL x21, _g_ffg
    ldr  x9, [x21, #FG_MODE]
    cbz  x9, Lfty_no
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    ldr  x10, [x21, #FG_ROOM]
    cmp  x9, x10
    b.ne Lfty_no
    mov  x0, x20
    bl   _strlen
    mov  x22, x0
    mov  x0, x20                          // five letters, else it's chat
    mov  x1, x22
    ADRL x2, _g_ff_buf
    bl   _ff_norm
    tbnz x0, #63, Lfty_no
    ldr  x9, [x21, #FG_STATE]
    cmp  x9, #FFS_CHOOSE
    b.ne 2f
    add  x0, sp, #96                      // our word for them, sealed with a fresh salt
    mov  x1, #16
    bl   _arc4random_buf
    mov  x0, x21
    mov  x1, x20
    mov  x2, x22
    add  x3, sp, #96
    ADRL x4, _g_ff_pkt
    bl   _ffp_choose
    cmp  x0, #22
    b.ne Lfty_why
    ADRL x8, _g_ff_res
    str  xzr, [x8]
    mov  x2, x0
    mov  x0, x19
    ADRL x1, _g_ff_pkt
    bl   _mesh_send_game
    mov  x0, x19
    ADRL x1, Ls_picked
    mov  x2, #1
    bl   _room_line
    b    Lfty_yes
2:  mov  x0, x21
    mov  x1, x20
    mov  x2, x22
    ADRL x3, _g_ff_pkt
    bl   _ffp_guess
    ADRL x8, _g_ff_res
    str  x0, [x8]
    tbnz x0, #63, Lfty_why
    cbz  x1, Lfty_yes
    mov  x2, x1
    mov  x0, x19
    ADRL x1, _g_ff_pkt
    bl   _mesh_send_game
    b    Lfty_yes
Lfty_why:
    ADRL x8, _g_ff_res
    str  x0, [x8]
    bl   Lff_why
    mov  x1, x0
    mov  x0, x19
    mov  x2, #1
    bl   _room_line
Lfty_yes:
    bl   _ff_ui_show
    mov  x0, #1
    LEAVE 32
Lfty_no:
    mov  x0, #0
    LEAVE 32

// const char *Lff_why(x0 an FFG_ code) -> the line that says why (leaf)
Lff_why:
    ADRL x9, Ls_why_word
    cmp  x0, #FFG_NOTWORD
    b.eq 1f
    ADRL x9, Ls_why_wait
    cmp  x0, #FFG_WAIT
    b.eq 1f
    ADRL x9, Ls_why_over
    cmp  x0, #FFG_OVER
    b.eq 1f
    ADRL x9, Ls_why_5
1:  mov  x0, x9
    ret

// ---------------------------------------------------------------------------
// For the screens (Mac window, iPhone)

// long am_ff_mode(void) -> the game shown: 0 none, 1 the day's word, 2 race, 3 duel
.globl _am_ff_mode
_am_ff_mode:
    ENTER 0
    bl   Lff_current
    cbz  x0, 9f
    ldr  x0, [x0, #FG_MODE]
9:  LEAVE 0

// long am_ff_room(void) -> a race or duel's room (its index), or -1
.globl _am_ff_room
_am_ff_room:
    ENTER 0
    ADRL x8, _g_ffg
    ldr  x9, [x8, #FG_MODE]
    mov  x0, #-1
    cbz  x9, 9f
    ldr  x0, [x8, #FG_ROOM]
    bl   _room_find
9:  LEAVE 0

// long am_ff_state(void) -> its FFS_ state
.globl _am_ff_state
_am_ff_state:
    ENTER 0
    bl   Lff_current
    cbz  x0, 9f
    ldr  x0, [x0, #FG_STATE]
9:  LEAVE 0

// long am_ff_cell(long row, long col) -> a letter (a-z) << 8 | its colour (0 1 2, 3 none yet);
//   0 an empty cell
.globl _am_ff_cell
_am_ff_cell:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   Lff_current
    cbz  x0, 9f
    mov  x9, #5
    madd x10, x19, x9, x20
    ldr  x11, [x0, #FG_N]
    cmp  x19, x11
    b.lo 1f
    b.hi 8f                               // a pending duel guess: its letters, no colour
    ldr  x12, [x0, #FG_PEND]
    cbz  x12, 8f
    add  x12, x0, #FG_GUESS
    ldrb w12, [x12, x10]
    lsl  w12, w12, #8
    orr  w0, w12, #3
    b    9f
1:  add  x12, x0, #FG_GUESS
    ldrb w12, [x12, x10]
    add  x13, x0, #FG_COL
    ldrb w13, [x13, x10]
    orr  w0, w13, w12, lsl #8
    b    9f
8:  mov  x0, #0
9:  LEAVE 0

// long am_ff_key(long letter) -> what's known of a letter: 3 not tried, else its best colour
.globl _am_ff_key
_am_ff_key:
    ENTER 0
    mov  x19, x0
    bl   Lff_current
    mov  x20, #3
    cbz  x0, 9f
    ldr  x9, [x0, #FG_N]
    mov  x10, #5
    mul  x9, x9, x10
    mov  x10, #0
1:  cmp  x10, x9
    b.hs 9f
    add  x11, x0, #FG_GUESS
    ldrb w11, [x11, x10]
    cmp  x11, x19
    b.ne 2f
    add  x12, x0, #FG_COL
    ldrb w12, [x12, x10]
    cmp  x20, #3
    csel x20, x12, x20, eq
    cmp  x12, x20
    csel x20, x12, x20, hi
2:  add  x10, x10, #1
    b    1b
9:  mov  x0, x20
    LEAVE 0

// long am_ff_status(char *buf, long cap), am_ff_share(char *buf, long cap)
.globl _am_ff_status
_am_ff_status:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    strb wzr, [x19]
    bl   Lff_current
    cbz  x0, 9f
    mov  x1, x19
    mov  x2, x20
    bl   _ffpt_status
9:  LEAVE 0
.globl _am_ff_share
_am_ff_share:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    strb wzr, [x19]
    bl   Lff_current
    cbz  x0, 9f
    mov  x1, x19
    mov  x2, x20
    bl   _ffpt_share
9:  LEAVE 0

// long am_ff_try(const char *text) -> what typing it gave: the row (0-5), or an FFG_ code;
//   in a race or duel as if typed in its room, else the day's word
.globl _am_ff_try
_am_ff_try:
    ENTER 0
    mov  x19, x0
    ADRL x20, _g_ffg
    ldr  x9, [x20, #FG_MODE]
    cbz  x9, 2f
    ldr  x0, [x20, #FG_ROOM]
    bl   _room_find
    tbnz x0, #63, 2f
    ADRL x8, _g_ff_res                    // (not five letters: it says nothing)
    mov  x9, #FFG_NOT5
    str  x9, [x8]
    mov  x1, x19
    bl   _ffm_typed
    ADRL x8, _g_ff_res
    ldr  x0, [x8]
    LEAVE 0
2:  ADRL x20, _g_ffs                      // the day's word (a new day: the new one)
    bl   _ffm_solo
    mov  x0, x19
    bl   _strlen
    mov  x2, x0
    mov  x0, x20
    mov  x1, x19
    ADRL x3, _g_ff_pkt
    bl   _ffp_guess
    mov  x21, x0
    tbnz x21, #63, 4f
    bl   Lffm_solo_save
4:  bl   _ff_ui_show
    mov  x0, x21
    LEAVE 0

// const char *am_ff_why(long code) -> the words for an FFG_ code
.globl _am_ff_why
_am_ff_why:
    b    Lff_why

// void am_ff_solo(void) — the day's word, on the screen
.globl _am_ff_solo
_am_ff_solo:
    ENTER 0
    ADRL x8, _g_ffg                       // (a race or duel over: the day's word shows)
    ldr  x9, [x8, #FG_STATE]
    cmp  x9, #FFS_DONE
    b.ne 1f
    str  xzr, [x8, #FG_MODE]
1:  bl   _ffm_solo
    bl   _ff_ui_pop
    LEAVE 0

// long am_ff_others(char *buf, long cap) — a race's other players: "Anna 🟧🟦⬛⬛⬛ …\n"
.globl _am_ff_others
_am_ff_others:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    strb wzr, [x19]
    ADRL x21, _g_ffg
    ldr  x9, [x21, #FG_MODE]
    cmp  x9, #FFM_RACE
    b.ne 9f
    mov  x22, #0
1:  ldr  x9, [x21, #FG_NPL]
    cmp  x22, x9
    b.hs 9f
    mov  x9, #PF_SIZE
    madd x23, x22, x9, x21
    add  x23, x23, #FG_PL
    add  x22, x22, #1
    mov  x0, x19
    add  x1, x23, #PF_NICK
    mov  x2, x20
    bl   _strlcat
    ldr  x9, [x23, #PF_SOLVED]
    ADRL x1, Ls_solved
    cbnz x9, 2f
    ADRL x1, Ls_rows
2:  mov  x0, x19
    mov  x2, x20
    bl   _strlcat
    mov  x24, #0                          // their rows, squares only
3:  ldr  x9, [x23, #PF_N]
    mov  x10, #5
    mul  x9, x9, x10
    cmp  x24, x9
    b.hs 5f
    add  x9, x23, #PF_COL
    ldrb w9, [x9, x24]
    ADRL x1, Ls_sq0
    cmp  w9, #1
    ADRL x10, Ls_sq1
    csel x1, x10, x1, eq
    cmp  w9, #2
    ADRL x10, Ls_sq2
    csel x1, x10, x1, eq
    mov  x0, x19
    mov  x2, x20
    bl   _strlcat
    add  x24, x24, #1
    mov  x9, #5                           // a space between rows
    udiv x10, x24, x9
    msub x10, x10, x9, x24
    cbnz x10, 3b
    mov  x0, x19
    ADRL x1, Ls_space
    mov  x2, x20
    bl   _strlcat
    b    3b
5:  mov  x0, x19
    ADRL x1, Ls_nl
    mov  x2, x20
    bl   _strlcat
    b    1b
9:  LEAVE 16

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_k_solo:      .asciz "fivefoldToday"
Ls_dayfmt:      .asciz "%ld:"
Ls_comma:       .asciz ","
Ls_with:        .asciz "with "
Ls_room:        .asciz "Fivefold %s"
Ls_space:       .asciz " "
Ls_nl:          .asciz "\n"
Ls_said:        .asciz "\302\267 %s"
Ls_solved:      .asciz " \342\234\223 "
Ls_rows:        .asciz "  "
Ls_sq0:         .asciz "\342\254\233"
Ls_sq1:         .asciz "\360\237\237\246"
Ls_sq2:         .asciz "\360\237\237\247"
Ls_solo_line:   .asciz "\302\267 Fivefold: today\342\200\231s word (the same for everyone today). Six tries; amber is the right letter in the right place, blue is in the word somewhere else. fivefold share puts your squares (never the word) in Main."
Ls_race_line:   .asciz "\302\267 Fivefold race: the same word for everyone here. Type five-letter guesses; the others see your colours, never your letters."
Ls_duel_line:   .asciz "\302\267 Fivefold duel: type a five-letter word for them to guess (it\342\200\231s sealed: they can\342\200\231t see it, and you can\342\200\231t change it). Then guess theirs. At the end both words are shown and every answer is checked."
Ls_picked:      .asciz "\302\267 Your word is sealed and sent. Now guess theirs."
Ls_why_5:       .asciz "\302\267 Five letters, please."
Ls_why_word:    .asciz "\302\267 That isn\342\200\231t in Fivefold\342\200\231s word list."
Ls_why_wait:    .asciz "\302\267 Waiting for their word, or the answer to your last guess."
Ls_why_over:    .asciz "\302\267 This board is finished."
Ls_how:         .asciz "\302\267 fivefold (today\342\200\231s word), fivefold race with Anna, Sam, fivefold duel with Anna, fivefold share."
Ls_onlyone:     .asciz "\302\267 A duel is with one person: fivefold duel with Anna."
Ls_nobody:      .asciz "\302\267 Nobody called \342\200\234%s\342\200\235 is on the mesh right now."
Ls_busy:        .asciz "\302\267 A Fivefold race or duel is going already."
Ls_full:        .asciz "\302\267 No room for another room: leave one first."
Ls_remote:      .asciz "\302\267 Fivefold starts on the device it\342\200\231s played on."
Ls_shared:      .asciz "\302\267 Your squares are in Main (not the word)."
Ls_noshare:     .asciz "\302\267 Finish a board first: fivefold share sends its squares."
