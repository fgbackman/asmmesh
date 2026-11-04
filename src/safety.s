// safety.s — block, report and the chat filter (Mac and iPhone), as App Review asks of apps
// where people chat (guideline 1.2):
//   block      a blocked person's messages, invitations, game moves and asks to join are
//              not shown or taken (their packets are still passed on: the mesh needs it).
//              People on asmmesh and on bitchat. Kept between launches.
//   report     an email to the address set with "report address …", with their name, key
//              fingerprint and their last messages here; and they're blocked
//   filter     words Wiktionary labels vulgar or slurs, in what others send, show as
//              f*** (cf_core.s); on unless "filter off"
// Home: block Anna · unblock Anna · unblock all · blocked · report Anna · report address
//   you@example.com · filter · filter on · filter off. In a private bitchat chat: block,
//   unblock, report. Mac: Mesh › Block Person / Report Person… (People's selection).
.include "macros.inc"

.set BLK_MAX,       64
.set REC_N,         32
.set REC_TEXT,      184
.set REC_SIZE,      200          // id (8), room id (8), text (184)

.data
.p2align 3
_g_blk_loaded:  .quad 0
_g_blk_n:       .quad 0
_g_filter:      .quad -1          // -1 not read yet, 0 off, 1 on
_g_rec_pos:     .quad 0
.zerofill __DATA,__bss,_g_blocked,(BLK_MAX * 8),4
.zerofill __DATA,__bss,_g_rec,(REC_N * REC_SIZE),4
.zerofill __DATA,__bss,_g_sf_buf,2048,4
.zerofill __DATA,__bss,_g_sf_url,6144,4
.zerofill __DATA,__bss,_g_sf_to,128,4

.text
.p2align 2

// ---------------------------------------------------------------------------
// Blocked

// long _blk_has(uint64 id) -> 1 if blocked
.globl _blk_has
_blk_has:
    ENTER 0
    mov  x19, x0
    cbz  x19, 8f
    bl   Lblk_load
    ADRL x8, _g_blk_n
    ldr  x9, [x8]
    ADRL x8, _g_blocked
    mov  x10, #0
1:  cmp  x10, x9
    b.hs 8f
    ldr  x11, [x8, x10, lsl #3]
    add  x10, x10, #1
    cmp  x11, x19
    b.ne 1b
    mov  x0, #1
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// void _blk_set(uint64 id, long on) — block or unblock, and remember it
.globl _blk_set
_blk_set:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    cbz  x19, 9f
    bl   Lblk_load
    ADRL x21, _g_blocked
    ADRL x8, _g_blk_n
    ldr  x22, [x8]
    mov  x10, #0                          // there already?
1:  cmp  x10, x22
    b.hs 3f
    ldr  x11, [x21, x10, lsl #3]
    cmp  x11, x19
    b.eq 2f
    add  x10, x10, #1
    b    1b
2:  cbnz x20, 9f                          // blocked already
    sub  x22, x22, #1                     // unblock: the last one takes its place
    ldr  x11, [x21, x22, lsl #3]
    str  x11, [x21, x10, lsl #3]
    b    4f
3:  cbz  x20, 9f                          // not blocked: nothing to undo
    cmp  x22, #BLK_MAX
    b.lo 31f
    mov  x22, #(BLK_MAX - 1)              // full: the oldest goes
    mov  x10, #0
32: add  x11, x10, #1
    cmp  x11, #BLK_MAX
    b.hs 31f
    ldr  x12, [x21, x11, lsl #3]
    str  x12, [x21, x10, lsl #3]
    mov  x10, x11
    b    32b
31: str  x19, [x21, x22, lsl #3]
    add  x22, x22, #1
4:  ADRL x8, _g_blk_n
    str  x22, [x8]
    bl   Lblk_save
    bl   _ui_lists_changed
9:  LEAVE 0

// Lblk_load — the list from the defaults ("blocked": 16 hex digits each, by commas), once
Lblk_load:
    ENTER 0
    ADRL x8, _g_blk_loaded
    ldr  x9, [x8]
    cbnz x9, 9f
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, Ls_k_blocked
    ADRL x1, _g_sf_buf
    mov  x2, #2048
    bl   _pref_get
    ADRL x19, _g_sf_buf
    mov  x20, #0                          // how many
1:  ldrb w9, [x19]
    cbz  w9, 8f
    cmp  w9, #','
    b.ne 2f
    add  x19, x19, #1
    b    1b
2:  mov  x21, #0                          // 16 hex digits
    mov  x22, #0
3:  cmp  x22, #16
    b.hs 4f
    ldrb w9, [x19, x22]
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.ls 31f
    orr  w9, w9, #0x20
    sub  w10, w9, #'a'
    cmp  w10, #5
    b.hi 8f                               // not what we write: stop reading
    add  w10, w10, #10
31: lsl  x21, x21, #4
    orr  x21, x21, x10
    add  x22, x22, #1
    b    3b
4:  add  x19, x19, #16
    cmp  x20, #BLK_MAX
    b.hs 8f
    ADRL x8, _g_blocked
    str  x21, [x8, x20, lsl #3]
    add  x20, x20, #1
    b    1b
8:  ADRL x8, _g_blk_n
    str  x20, [x8]
9:  LEAVE 0

// Lblk_save — the list into the defaults
Lblk_save:
    ENTER 0
    ADRL x19, _g_sf_buf
    strb wzr, [x19]
    mov  x20, #0                          // written
    mov  x21, #0
1:  ADRL x8, _g_blk_n
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs 8f
    ADRL x8, _g_blocked
    ldr  x22, [x8, x21, lsl #3]
    add  x21, x21, #1
    cbz  x20, 2f
    mov  w9, #','
    strb w9, [x19, x20]
    add  x20, x20, #1
2:  mov  x9, #60                          // 16 hex digits, the top one first
3:  lsr  x10, x22, x9
    and  x10, x10, #15
    ADRL x11, Ls_hex
    ldrb w10, [x11, x10]
    strb w10, [x19, x20]
    add  x20, x20, #1
    subs x9, x9, #4
    b.pl 3b
    b    1b
8:  strb wzr, [x19, x20]
    ADRL x0, Ls_k_blocked
    ADRL x1, _g_sf_buf
    bl   _pref_set
    LEAVE 0

// ---------------------------------------------------------------------------
// The filter, and what people said lately (for reports)

// void _chat_clean(char *text) — the filter on what someone sent, unless it's off
.globl _chat_clean
_chat_clean:
    ENTER 16                              // [96] the setting
    mov  x19, x0
    ADRL x8, _g_filter
    ldr  x9, [x8]
    tbz  x9, #63, 1f
    ADRL x0, Ls_k_filter                  // "0": off; anything else (or nothing): on
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #96]
    cmp  w9, #'0'
    cset x9, ne
    ADRL x8, _g_filter
    str  x9, [x8]
1:  cbz  x9, 9f
    mov  x0, x19
    bl   _cf_filter
9:  LEAVE 16

// void _rec_note(uint64 who, uint64 room, const char *text) — kept for a report (the last
//   32 messages heard, from anyone)
.globl _rec_note
_rec_note:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    cbz  x19, 9f
    ADRL x8, _g_rec_pos
    ldr  x9, [x8]
    add  x10, x9, #1
    cmp  x10, #REC_N
    csel x10, xzr, x10, hs
    str  x10, [x8]
    mov  x10, #REC_SIZE
    ADRL x8, _g_rec
    madd x22, x9, x10, x8
    str  x19, [x22]
    str  x20, [x22, #8]
    add  x0, x22, #16
    mov  x1, x21
    mov  x2, #REC_TEXT
    bl   _strlcpy
    add  x0, x22, #16                     // cut between characters, not inside one
    bl   _utf8_fix
9:  LEAVE 0

// ---------------------------------------------------------------------------
// Report

// void _sf_report(uint64 who, const char *name) — an email with what they said here, to
//   the address set for reports; then they're blocked
.globl _sf_report
_sf_report:
    ENTER 32                              // [96] their key fingerprint (16)
    mov  x19, x0
    mov  x20, x1
    cbz  x19, 9f
    mov  x0, x19
    add  x1, sp, #96
    bl   _fp
    ADRL x21, _g_sf_buf                   // the report
    mov  x0, x21
    mov  x1, #2048
    ADRL x2, Ls_rep_head
    str  x20, [sp]
    add  x9, sp, #96
    str  x9, [sp, #8]
    bl   _snprintf
    mov  x22, #0                          // their lines, oldest first
    mov  x23, #0                          //   how many
1:  cmp  x22, #REC_N
    b.hs 3f
    ADRL x8, _g_rec_pos
    ldr  x9, [x8]
    add  x9, x9, x22
    mov  x10, #REC_N
    udiv x11, x9, x10
    msub x9, x11, x10, x9
    mov  x10, #REC_SIZE
    ADRL x8, _g_rec
    madd x24, x9, x10, x8
    add  x22, x22, #1
    ldr  x9, [x24]
    cmp  x9, x19
    b.ne 1b
    mov  x0, x21
    ADRL x1, Ls_rep_dash
    mov  x2, #2048
    bl   _strlcat
    mov  x0, x21
    add  x1, x24, #16
    mov  x2, #2048
    bl   _strlcat
    mov  x0, x21
    ADRL x1, Ls_nl
    mov  x2, #2048
    bl   _strlcat
    add  x23, x23, #1
    b    1b
3:  cbnz x23, 4f
    mov  x0, x21
    ADRL x1, Ls_rep_nolines
    mov  x2, #2048
    bl   _strlcat
4:  mov  x0, x21
    ADRL x1, Ls_rep_tail
    mov  x2, #2048
    bl   _strlcat
    ADRL x0, Ls_k_report                  // where to
    ADRL x1, _g_sf_to
    mov  x2, #128
    bl   _pref_get
    ADRL x8, _g_sf_to
    ldrb w9, [x8]
    cbz  w9, Lrp_noaddr
    ADRL x22, _g_sf_url                   // mailto:to?subject=...&body=...
    mov  x0, x22
    ADRL x1, Ls_mailto
    mov  x2, #6144
    bl   _strlcpy
    mov  x0, x22
    ADRL x1, _g_sf_to
    mov  x2, #6144
    bl   _strlcat
    mov  x0, x22
    ADRL x1, Ls_q_subject
    mov  x2, #6144
    bl   _strlcat
    mov  x0, x22
    ADRL x1, Ls_rep_subject
    bl   Lsf_enc
    mov  x0, x22
    mov  x1, x20
    bl   Lsf_enc
    mov  x0, x22
    ADRL x1, Ls_q_body
    mov  x2, #6144
    bl   _strlcat
    mov  x0, x22
    mov  x1, x21
    bl   Lsf_enc
    mov  x0, x22
    bl   _open_url
    ADRL x0, Ls_rep_sent
    mov  x1, x20
    bl   _home_say
    b    8f
Lrp_noaddr:
    ADRL x0, Ls_rep_noaddr
    mov  x1, x20
    bl   _home_say
8:  mov  x0, x19
    mov  x1, #1
    bl   _blk_set
9:  LEAVE 32

// Lsf_enc(x0 url, x1 text) — text added to the URL, %-escaped (letters, digits, - _ . ~ as
//   they are); stops short of 6100 bytes
Lsf_enc:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    bl   _strlen
    mov  x21, x0
1:  ldrb w9, [x20], #1
    cbz  w9, 8f
    mov  x10, #6100
    cmp  x21, x10
    b.hs 8f
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.ls 3f
    orr  w10, w9, #0x20
    sub  w10, w10, #'a'
    cmp  w10, #25
    b.ls 3f
    cmp  w9, #'-'
    b.eq 3f
    cmp  w9, #'_'
    b.eq 3f
    cmp  w9, #'.'
    b.eq 3f
    cmp  w9, #'~'
    b.eq 3f
    mov  w10, #'%'                        // %XX
    strb w10, [x19, x21]
    ADRL x11, Ls_hex
    lsr  w10, w9, #4
    ldrb w10, [x11, x10]
    add  x12, x21, #1
    strb w10, [x19, x12]
    and  w10, w9, #15
    ldrb w10, [x11, x10]
    add  x12, x21, #2
    strb w10, [x19, x12]
    add  x21, x21, #3
    b    1b
3:  strb w9, [x19, x21]
    add  x21, x21, #1
    b    1b
8:  strb wzr, [x19, x21]
    LEAVE 0

// ---------------------------------------------------------------------------
// Home's words: block, unblock, blocked, report, report address, filter

// _h_safety(arg, rest_lc, rest_orig) — arg: 1 block 2 unblock 3 blocked 4 report
//   5 filter on 6 filter off 7 filter 8 report address
.globl _h_safety
_h_safety:
    ENTER 96                              // [96] a name or address (64)
    mov  x19, x0
    mov  x20, x2
    ADRL x8, _g_remote_active             // only on this device, not from the mesh
    ldr  x9, [x8]
    cbnz x9, Lhs_remote
    cmp  x19, #3
    b.eq Lhs_list
    cmp  x19, #5
    b.eq Lhs_on
    cmp  x19, #6
    b.eq Lhs_off
    cmp  x19, #7
    b.eq Lhs_status
    cmp  x19, #8
    b.eq Lhs_addr
    add  x0, sp, #96                      // block / unblock / report: who
    mov  x1, x20
    mov  x2, #64
    bl   _strlcpy
    add  x0, sp, #96
    bl   Lsf_trim
    mov  x21, x0
    ldrb w9, [x21]
    cbz  w9, Lhs_how
    cmp  x19, #2                          // "unblock all"
    b.ne 1f
    mov  x0, x21
    ADRL x1, Ls_w_all
    bl   _strcasecmp
    cbnz w0, 1f
    ADRL x8, _g_blk_n
    str  xzr, [x8]
    bl   Lblk_save
    ADRL x0, Ls_unblocked_all
    bl   _home_say0
    b    Lhs_done
1:  mov  x22, #0                          // someone on the mesh, by name
2:  ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs Lhs_nobody
    ADRL x8, _g_nodes
    add  x23, x8, x22, lsl #NODE_SHIFT
    add  x0, x23, #N_NICK
    mov  x1, x21
    bl   _strcasecmp
    cbz  w0, 3f
    add  x22, x22, #1
    b    2b
3:  ldr  x0, [x23, #N_ID]
    add  x1, x23, #N_NICK
    cmp  x19, #4
    b.eq Lhs_report
    mov  x24, x1
    cmp  x19, #1
    cset x1, eq
    bl   _blk_set
    ADRL x0, Ls_blocked_now
    cmp  x19, #1
    ADRL x9, Ls_unblocked_now
    csel x0, x9, x0, ne
    mov  x1, x24
    bl   _home_say
    b    Lhs_done
Lhs_report:
    bl   _sf_report
    b    Lhs_done
Lhs_list:
    bl   Lblk_load
    ADRL x8, _g_blk_n
    ldr  x9, [x8]
    cbnz x9, 1f
    ADRL x0, Ls_blocked_none
    bl   _home_say0
    b    Lhs_done
1:  ADRL x0, Ls_blocked_head
    bl   _home_say0
    mov  x22, #0
2:  ADRL x8, _g_blk_n
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs Lhs_done
    ADRL x8, _g_blocked
    ldr  x23, [x8, x22, lsl #3]
    add  x22, x22, #1
    mov  x0, x23
    add  x1, sp, #96
    bl   _fp
    ADRL x24, Ls_someone                  // their name, if they're on the mesh now
    mov  x0, x23
    bl   _node_find
    tbnz x0, #63, 3f
    ADRL x8, _g_nodes
    add  x0, x8, x0, lsl #NODE_SHIFT
    add  x24, x0, #N_NICK
3:  ADRL x0, Ls_blocked_one
    mov  x1, x24
    add  x2, sp, #96
    bl   _home_say
    b    2b
Lhs_on:
    ADRL x0, Ls_k_filter
    ADRL x1, Ls_one
    bl   _pref_set
    ADRL x8, _g_filter
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, Ls_filter_on
    bl   _home_say0
    b    Lhs_done
Lhs_off:
    ADRL x0, Ls_k_filter
    ADRL x1, Ls_zero
    bl   _pref_set
    ADRL x8, _g_filter
    str  xzr, [x8]
    ADRL x0, Ls_filter_off
    bl   _home_say0
    b    Lhs_done
Lhs_status:
    bl   _am_filter
    mov  x10, x0
    ADRL x9, Ls_filter_on
    ADRL x0, Ls_filter_off
    cmp  x10, #0
    csel x0, x9, x0, ne
    bl   _home_say0
    b    Lhs_done
Lhs_addr:
    add  x0, sp, #96
    mov  x1, x20
    mov  x2, #64
    bl   _strlcpy
    add  x0, sp, #96
    bl   Lsf_trim
    mov  x21, x0
    mov  x0, x21                          // something@something
    mov  w1, #'@'
    bl   _strchr
    cbz  x0, Lhs_badaddr
    ADRL x0, Ls_k_report
    mov  x1, x21
    bl   _pref_set
    ADRL x0, Ls_addr_set
    mov  x1, x21
    bl   _home_say
    b    Lhs_done
Lhs_badaddr:
    ADRL x0, Ls_addr_how
    bl   _home_say0
    b    Lhs_done
Lhs_how:
    ADRL x0, Ls_sf_how
    bl   _home_say0
    b    Lhs_done
Lhs_nobody:
    ADRL x0, Ls_sf_nobody
    mov  x1, x21
    bl   _home_say
    b    Lhs_done
Lhs_remote:
    ADRL x0, Ls_sf_remote
    bl   _home_say0
Lhs_done:
    LEAVE 96

// Lsf_trim(x0 s) -> s without spaces around it (cut in place) (leaf)
Lsf_trim:
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

// long _sf_bc_typed(long room, const char *text) -> 1 if it was block, unblock or report,
//   typed in a private bitchat chat (mesh.s): about the person it's with
.globl _sf_bc_typed
_sf_bc_typed:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x20
    bl   Lsf_word
    mov  x21, x0                          // 1 block 2 unblock 4 report, 0 none
    cbz  x21, 8f
    ADRL x8, _g_rooms
    add  x22, x8, x19, lsl #ROOM_SHIFT
    ldr  x0, [x22, #R_ID]
    bl   _bc_pm_peer
    cbz  x0, 8f
    mov  x23, x0
    cmp  x21, #4
    b.ne 1f
    mov  x0, x23
    add  x1, x22, #R_NAME
    bl   _sf_report
    b    7f
1:  mov  x0, x23
    cmp  x21, #1
    cset x1, eq
    bl   _blk_set
    ADRL x1, Ls_bc_blocked
    cmp  x21, #1
    ADRL x9, Ls_bc_unblocked
    csel x1, x9, x1, ne
    mov  x0, x19
    mov  x2, #1
    bl   _room_line
7:  mov  x0, #1
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// Lsf_word(x0 text) -> 1 "block", 2 "unblock", 4 "report" (alone, any case), else 0
Lsf_word:
    ENTER 32                              // [96] the text, trimmed (32)
    mov  x1, x0
    add  x0, sp, #96
    mov  x2, #32
    bl   _strlcpy
    add  x0, sp, #96
    bl   Lsf_trim
    mov  x19, x0
    mov  x20, #1
    ADRL x1, Ls_w_block
    bl   _strcasecmp
    cbz  w0, 9f
    mov  x20, #2
    mov  x0, x19
    ADRL x1, Ls_w_unblock
    bl   _strcasecmp
    cbz  w0, 9f
    mov  x20, #4
    mov  x0, x19
    ADRL x1, Ls_w_report
    bl   _strcasecmp
    cbz  w0, 9f
    mov  x20, #0
9:  mov  x0, x20
    LEAVE 32

// ---------------------------------------------------------------------------
// For the screens (iPhone; the Mac's menu goes through ui.s)

// long am_blk_node(long node) -> 1 if that person on the People list is blocked
.globl _am_blk_node
_am_blk_node:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs 1f
    ADRL x8, _g_nodes
    add  x8, x8, x0, lsl #NODE_SHIFT
    ldr  x0, [x8, #N_ID]
    b    _blk_has
1:  mov  x0, #0
    ret

// void am_blk_set_node(long node, long on), am_report_node(long node)
.globl _am_blk_set_node
_am_blk_set_node:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs 1f
    ADRL x8, _g_nodes
    add  x8, x8, x0, lsl #NODE_SHIFT
    ldr  x0, [x8, #N_ID]
    b    _blk_set
1:  ret
.globl _am_report_node
_am_report_node:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs 1f
    ADRL x8, _g_nodes
    add  x8, x8, x0, lsl #NODE_SHIFT
    ldr  x0, [x8, #N_ID]
    add  x1, x8, #N_NICK
    b    _sf_report
1:  ret

// long am_filter(void) -> 1 if the chat filter is on; void am_filter_set(long on)
.globl _am_filter
_am_filter:
    ENTER 16
    ADRL x8, _g_filter
    ldr  x9, [x8]
    tbz  x9, #63, 1f
    ADRL x0, Ls_k_filter
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #96]
    cmp  w9, #'0'
    cset x9, ne
    ADRL x8, _g_filter
    str  x9, [x8]
1:  mov  x0, x9
    LEAVE 16
.globl _am_filter_set
_am_filter_set:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_filter
    cmp  x19, #0
    cset x9, ne
    str  x9, [x8]
    ADRL x0, Ls_k_filter
    ADRL x1, Ls_one
    ADRL x9, Ls_zero
    cmp  x19, #0
    csel x1, x9, x1, eq
    bl   _pref_set
    LEAVE 0

// const char *am_report_to(void) — the address reports go to, or ""
.globl _am_report_to
_am_report_to:
    ENTER 0
    ADRL x0, Ls_k_report
    ADRL x1, _g_sf_to
    mov  x2, #128
    bl   _pref_get
    ADRL x0, _g_sf_to
    LEAVE 0

// void am_report_to_set(const char *address)
.globl _am_report_to_set
_am_report_to_set:
    ENTER 0
    mov  x1, x0
    ADRL x0, Ls_k_report
    bl   _pref_set
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_hex:             .asciz "0123456789abcdef"
Ls_nl:              .asciz "\n"
Ls_one:             .asciz "1"
Ls_zero:            .asciz "0"
Ls_k_blocked:       .asciz "blocked"
Ls_k_filter:        .asciz "chatFilter"
Ls_k_report:        .asciz "reportTo"
Ls_w_all:           .asciz "all"
Ls_w_block:         .asciz "block"
Ls_w_unblock:       .asciz "unblock"
Ls_w_report:        .asciz "report"
Ls_someone:         .asciz "someone not here now"
Ls_mailto:          .asciz "mailto:"
Ls_q_subject:       .asciz "?subject="
Ls_q_body:          .asciz "&body="
Ls_rep_subject:     .asciz "asmmesh report: "
Ls_rep_head:        .asciz "A report from asmmesh.\n\nAbout: %s (key %s)\n\nWhat they sent here lately:\n"
Ls_rep_dash:        .asciz "- "
Ls_rep_nolines:     .asciz "(nothing this device still has)\n"
Ls_rep_tail:        .asciz "\nThey are blocked on the device that sent this report. Write what happened above."
Ls_rep_sent:        .asciz "\302\267 \360\237\232\251 Reported %s (your mail app has the report: send it) and blocked them."
Ls_rep_noaddr:      .asciz "\302\267 \360\237\232\251 Blocked %s. To send reports too, set where they go: report address you@example.com, then report them again."
Ls_blocked_now:     .asciz "\302\267 \360\237\232\253 Blocked %s: you won\342\200\231t see their messages, invitations or game moves (unblock to undo)."
Ls_unblocked_now:   .asciz "\302\267 Unblocked %s."
Ls_unblocked_all:   .asciz "\302\267 Nobody is blocked now."
Ls_blocked_none:    .asciz "\302\267 Nobody is blocked."
Ls_blocked_head:    .asciz "\302\267 \360\237\232\253 Blocked:"
Ls_blocked_one:     .asciz "\302\267   %s (key %s)"
Ls_filter_on:       .asciz "\302\267 The chat filter is on: vulgar words and slurs in what others send show as f***."
Ls_filter_off:      .asciz "\302\267 The chat filter is off: messages show as they were sent."
Ls_addr_set:        .asciz "\302\267 Reports go to %s."
Ls_addr_how:        .asciz "\302\267 report address you@example.com: where reports are sent."
Ls_sf_how:          .asciz "\302\267 block Anna, unblock Anna, unblock all, blocked, report Anna, report address you@example.com, filter on/off. In a private bitchat chat: block, unblock, report."
Ls_sf_nobody:       .asciz "\302\267 Nobody called \342\200\234%s\342\200\235 is on the mesh right now (names as People shows them)."
Ls_sf_remote:       .asciz "\302\267 Blocking, reporting and the filter are set on the device itself, not from the mesh."
Ls_bc_blocked:      .asciz "\302\267 \360\237\232\253 Blocked: you won\342\200\231t see what they send (unblock to undo)."
Ls_bc_unblocked:    .asciz "\302\267 Unblocked."
