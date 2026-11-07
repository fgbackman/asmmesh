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
.set DBL_BYTES,     (16 + 8 * 4096 + 64)
.set DBL_GOSSIP,    8192          // shared over the mesh up to this size (dbl_core.s)
.set DA_TOTAL,      8
.set DA_BUF,        40
.set DA_SIZE,       (40 + 8192)

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
.zerofill __DATA,__bss,_g_dbl,DBL_BYTES,4    // the developer's blocklist taken (dbl_core.s)
_g_dbl_n:       .quad -1          // its ids; -1 not read yet
_g_dbl_ver:     .quad 0
_g_dbl_next:    .quad 0           // when to fetch it next
_g_dbl_src:     .quad 0           // where ours came from: 1 this app, 2 the web, 3 the mesh
_g_dbl_ann:     .quad 0           // when we next say which version we have
_g_dbl_until:   .quad 0           // sending ours to a neighbour until then
_g_dbl_pos:     .quad 0           //   the next piece
.zerofill __DATA,__bss,_g_dbl_da,DA_SIZE,4  // a list coming in pieces (dbl_core.s)
.zerofill __DATA,__bss,_g_dbl_pkt,256,4

.text
.p2align 2

// ---------------------------------------------------------------------------
// Blocked

// long _blk_has(uint64 id) -> 1 if blocked, by us or on the developer's blocklist
.globl _blk_has
_blk_has:
    ENTER 0
    mov  x19, x0
    cbz  x19, 8f
    bl   Ldbl_load
    ADRL x0, _g_dbl
    ADRL x8, _g_dbl_n
    ldr  x1, [x8]
    mov  x2, x19
    bl   _dbl_has
    cbnz x0, 9f
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
9:  LEAVE 0

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
// The developer's blocklist (tools/blocklist/blocklist.py): shipped in the app, fetched daily

// Ldbl_load — once: the list shipped in the app, then the one fetched last, whichever is newer
Ldbl_load:
    ENTER 0
    ADRL x8, _g_dbl_n
    ldr  x9, [x8]
    tbz  x9, #63, 9f
    str  xzr, [x8]
    ADRL x0, Ldbl_ship                    // shipped
    ADRL x1, Ldbl_ship_end
    sub  x1, x1, x0
    bl   Ldbl_take
    cbz  x0, 1f
    ADRL x8, _g_dbl_src
    mov  x9, #1
    str  x9, [x8]
1:
    ADRL x0, Ls_k_dbl                     // fetched (as hex in the defaults)
    bl   _pref_len
    cbz  x0, 9f
    mov  x19, x0
    add  x0, x19, #1
    bl   _malloc
    cbz  x0, 9f
    mov  x20, x0
    ADRL x0, Ls_k_dbl
    mov  x1, x20
    add  x2, x19, #1
    bl   _pref_get
    mov  x0, x20                          // hex to bytes, in place
    bl   Ldbl_unhex
    mov  x1, x0
    mov  x0, x20
    bl   Ldbl_take
    mov  x21, x0
    mov  x0, x20
    bl   _free
    cbz  x21, 9f
    ADRL x0, Ls_k_dblfrom                 // where that one came from (2 web, 3 mesh)
    ADRL x1, _g_sf_to
    mov  x2, #8
    bl   _pref_get
    ADRL x8, _g_sf_to
    ldrb w9, [x8]
    sub  w9, w9, #'0'
    cmp  w9, #3
    mov  w10, #2
    csel w9, w10, w9, hi
    ADRL x8, _g_dbl_src
    str  x9, [x8]
9:  LEAVE 0

// long Ldbl_take(data, len) -> 1 if it was a good list newer than ours, and is ours now
Ldbl_take:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, #DBL_BYTES
    cmp  x20, x0
    b.hi 8f
    mov  x0, x19
    mov  x1, x20
    ADRL x2, Ldbl_pub
    bl   _dbl_verify
    tbnz x0, #63, 8f
    mov  x21, x0
    ADRL x8, _g_dbl_ver                   // newer only: an old list can't unban anyone
    ldr  x9, [x8]
    cmp  x1, x9
    b.ls 8f
    str  x1, [x8]
    ADRL x0, _g_dbl
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    ADRL x8, _g_dbl_n
    str  x21, [x8]
    mov  x0, #1
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// long Ldbl_unhex(char *s) -> bytes written over it (leaf)
.macro DBL_NIB reg                        // a hex digit to its value, in place
    sub  w15, \reg, #'0'
    cmp  w15, #9
    b.ls Ldn_\@
    orr  w15, \reg, #0x20
    sub  w15, w15, #('a' - 10)
Ldn_\@:
    and  \reg, w15, #15
.endm
Ldbl_unhex:
    mov  x9, #0                           // in
    mov  x10, #0                          // out
1:  ldrb w11, [x0, x9]
    cbz  w11, 3f
    add  x12, x9, #1
    ldrb w12, [x0, x12]
    cbz  w12, 3f
    DBL_NIB w11
    DBL_NIB w12
    orr  w13, w12, w11, lsl #4
    strb w13, [x0, x10]
    add  x10, x10, #1
    add  x9, x9, #2
    b    1b
3:  mov  x0, x10
    ret

// long _pref_len(const char *key) -> the length of the string kept under key (0: none)
_pref_len:
    ENTER 0
    mov  x19, x0
    bl   _defaults
    mov  x20, x0
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_stringForKey
    cbz  x0, 8f
    MSG0 Ls_UTF8String
    cbz  x0, 8f
    bl   _strlen
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// void _dbl_tick(void) — every second (scanner.s, ios_ui.s): say which version we have to
//   our neighbours (once a minute), send ours in pieces to one that's behind (2 a second),
//   and, only if switched on (blocklist fetch on), fetch it from the web once a day
.globl _dbl_tick
_dbl_tick:
    ENTER 16
    bl   Ldbl_load
    mov  x0, #0
    bl   _time
    mov  x19, x0
    ADRL x8, _g_dbl_ann                   // which version we have
    ldr  x9, [x8]
    cmp  x19, x9
    b.lo 1f
    add  x9, x19, #60
    str  x9, [x8]
    mov  x0, #0xFFFF
    mov  x1, #0
    mov  x2, #0
    bl   Ldbl_send
1:  ADRL x8, _g_dbl_until                 // ours, to a neighbour that's behind
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs 3f
    mov  x20, #2
2:  bl   Ldbl_bytes
    mov  x21, x0
    cbz  x21, 3f
    ADRL x8, _g_dbl_pos
    ldr  x22, [x8]
    lsl  x9, x22, #7
    cmp  x9, x21
    csel x22, xzr, x22, hs                // round again from the start
    add  x9, x22, #1
    str  x9, [x8]
    ADRL x0, _g_dbl
    mov  x1, x21
    mov  x2, x22
    ADRL x3, _g_sf_buf
    bl   _dbl_piece
    mov  x2, x0
    lsl  x0, x22, #7
    ADRL x1, _g_sf_buf
    bl   Ldbl_send
    subs x20, x20, #1
    b.ne 2b
3:  ADRL x9, Ldbl_url_text                // the web: only if asked for, and a URL is built in
    ldrb w9, [x9]
    cbz  w9, 9f
    ADRL x0, Ls_k_fetch
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #96]
    cmp  w9, #'1'
    b.ne 9f
    ADRL x8, _g_dbl_next
    ldr  x9, [x8]
    cbnz x9, 4f
    add  x9, x19, #30                     // the first time: 30 s after starting
    str  x9, [x8]
    b    9f
4:  cmp  x19, x9
    b.lo 9f
    MOVI x10, 86400
    add  x9, x19, x10
    str  x9, [x8]
    ADRL x0, Ls_get
    ADRL x1, Ldbl_url_text
    mov  x2, #0
    mov  x3, #0
    ADRL x4, Ls_tag_dbl
    bl   _http
9:  LEAVE 16

// long Ldbl_bytes -> how long our list is, if we have one and it can go over the mesh, else 0
Ldbl_bytes:
    ADRL x8, _g_dbl_n
    ldr  x9, [x8]
    mov  x0, #0
    tbnz x9, #63, 1f
    ADRL x8, _g_dbl_ver
    ldr  x10, [x8]
    cbz  x10, 1f
    lsl  x0, x9, #3
    add  x0, x0, #80
    mov  x10, #DBL_GOSSIP
    cmp  x0, x10
    csel x0, xzr, x0, hi
1:  ret

// Ldbl_send(x0 offset (0xFFFF: which version we have), x1 piece, x2 its length) — a T_DBL
//   packet to our neighbours only (TTL 1: not passed on)
Ldbl_send:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_id_ready
    ldr  x9, [x8]
    cbz  x9, 9f
    ADRL x0, _g_dbl_pkt
    mov  w1, #T_DBL
    bl   _pkt_begin
    ADRL x22, _g_dbl_pkt
    mov  w9, #1
    strb w9, [x22, #2]                    // TTL 1
    ADRL x8, _g_dbl_ver
    ldr  x9, [x8]
    str  w9, [x22, #12]
    bl   Ldbl_bytes
    strh w0, [x22, #16]
    strh w19, [x22, #18]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x22, #20]
    add  x0, x22, #28
    mov  x1, x20
    mov  x2, x21
    cbz  x21, 1f
    bl   _memcpy
1:  add  x1, x21, #28
    mov  x0, x22
    bl   _pkt_finish
    cbz  x0, 9f
    mov  x1, x0
    mov  x0, x22
    bl   _ble_broadcast
9:  LEAVE 0

// void _dbl_rx(const uint8 *pkt, long len) — mesh.s: a T_DBL from a neighbour (signed,
//   checked). Which version they have: send ours if it's newer. A piece of a newer one:
//   put it together, and take it once whole and its signature checks out.
.globl _dbl_rx
_dbl_rx:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    cmp  x20, #28
    b.lo 9f
    bl   Ldbl_load
    mov  x0, #0
    bl   _time
    mov  x21, x0
    ldr  w22, [x19, #12]                  // their version
    ldrh w23, [x19, #18]                  // offset
    ADRL x8, _g_dbl_ver
    ldr  x24, [x8]                        // ours
    mov  x9, #0xFFFF
    cmp  x23, x9
    b.ne 2f
    cmp  x22, x24                         // they're behind: send ours for 40 s
    b.hs 9f
    bl   Ldbl_bytes
    cbz  x0, 9f
    ADRL x8, _g_dbl_until
    ldr  x9, [x8]
    cmp  x21, x9
    b.lo 9f                               // sending already
    add  x9, x21, #40
    str  x9, [x8]
    ADRL x8, _g_dbl_pos
    str  xzr, [x8]
    b    9f
2:  cmp  x22, x24                         // a piece: of a newer list only
    b.ls 9f
    ADRL x0, _g_dbl_da
    ldr  x1, [x19, #20]
    mov  x2, x22
    ldrh w3, [x19, #16]
    mov  x4, x23
    add  x5, x19, #28
    sub  x6, x20, #28
    mov  x7, x21
    bl   _dbl_piece_in
    cmp  x0, #1
    b.ne 9f
    ADRL x8, _g_dbl_da
    add  x0, x8, #DA_BUF
    ldr  x1, [x8, #DA_TOTAL]
    bl   Ldbl_take
    ADRL x8, _g_dbl_da                    // whole: taken, or not (a bad signature)
    str  xzr, [x8]
    cbz  x0, 9f
    ADRL x8, _g_dbl_src
    mov  x9, #3
    str  x9, [x8]
    bl   Ldbl_bytes
    mov  x1, x0
    ADRL x0, _g_dbl
    bl   Ldbl_keep
    bl   _ui_lists_changed
9:  LEAVE 0

// void _dbl_response(tag, json, long status, id error, NSData *data) — net.s ('d')
.globl _dbl_response
_dbl_response:
    ENTER 0
    cmp  x2, #200
    b.ne 9f
    cbz  x4, 9f
    mov  x19, x4
    bl   Ldbl_load
    mov  x0, x19
    MSG0 Ls_length
    mov  x20, x0
    mov  x0, x19
    MSG0 Ls_bytes
    mov  x1, x20
    bl   Ldbl_take
    cbz  x0, 9f
    ADRL x8, _g_dbl_src
    mov  x9, #2
    str  x9, [x8]
    ADRL x0, _g_dbl
    mov  x1, x20
    bl   Ldbl_keep
    bl   _ui_lists_changed
9:  LEAVE 0

// Ldbl_keep(data, len) — the list we took, as hex in the defaults, for the next start
Ldbl_keep:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    lsl  x0, x20, #1
    add  x0, x0, #1
    bl   _malloc
    cbz  x0, 9f
    mov  x21, x0
    mov  x9, #0
    ADRL x11, Ls_hex
1:  cmp  x9, x20
    b.hs 2f
    ldrb w10, [x19, x9]
    lsr  w12, w10, #4
    ldrb w12, [x11, x12]
    add  x13, x21, x9, lsl #1
    strb w12, [x13]
    and  w12, w10, #15
    ldrb w12, [x11, x12]
    strb w12, [x13, #1]
    add  x9, x9, #1
    b    1b
2:  add  x13, x21, x20, lsl #1
    strb wzr, [x13]
    ADRL x0, Ls_k_dbl
    mov  x1, x21
    bl   _pref_set
    mov  x0, x21
    bl   _free
    ADRL x8, _g_dbl_src                   // and where it came from
    ldr  x9, [x8]
    add  w9, w9, #'0'
    strb w9, [sp, #-16]!
    strb wzr, [sp, #1]
    ADRL x0, Ls_k_dblfrom
    mov  x1, sp
    bl   _pref_set
    add  sp, sp, #16
9:  LEAVE 0

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
    str  x19, [sp, #16]                   // the full id: what the developer's blocklist takes
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
    cmp  x19, #9
    b.eq Lhs_dbl
    cmp  x19, #10
    b.eq Lhs_fetch_on
    cmp  x19, #11
    b.eq Lhs_fetch_off
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
    b.hs Lhs_mc
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
Lhs_who:                                  // x0 their id, x1 their name
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
Lhs_mc:                                   // not on the mesh: one of the MeshCore radio's contacts?
    mov  x22, #0
1:  bl   _am_mc_contacts
    cmp  x22, x0
    b.hs Lhs_nobody
    mov  x0, x22
    bl   _am_mc_contact_name
    mov  x23, x0
    mov  x1, x21
    bl   _strcasecmp
    cbz  w0, 2f
    add  x22, x22, #1
    b    1b
2:  mov  x0, x22                          // blocked by their key (mc_ble.s), shown by name
    bl   _am_mc_contact_id
    mov  x1, x23
    b    Lhs_who
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
Lhs_dbl:                                  // "blocklist": what this device has
    bl   Ldbl_load
    ADRL x8, Ldbl_pub
    ldp  x9, x10, [x8]
    ldp  x11, x12, [x8, #16]
    orr  x9, x9, x10
    orr  x11, x11, x12
    orr  x9, x9, x11
    cbnz x9, 1f
    ADRL x0, Ls_dbl_nokey
    bl   _home_say0
    b    Lhs_done
1:  ADRL x0, Ls_k_fetch
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ADRL x3, Ls_off
    ldrb w9, [sp, #96]
    cmp  w9, #'1'
    b.ne 2f
    ADRL x3, Ls_on
2:  ADRL x8, _g_dbl_src
    ldr  x9, [x8]
    ADRL x10, Lsrc_names
    ldr  x2, [x10, x9, lsl #3]
    ADRL x8, _g_dbl_n
    ldr  x1, [x8]
    ADRL x8, _g_dbl_ver
    ldr  x0, [x8]
    str  x0, [sp]
    str  x1, [sp, #8]
    str  x2, [sp, #16]
    str  x3, [sp, #24]
    ADRL x0, _g_sf_buf
    mov  x1, #400
    ADRL x2, Ls_dbl_status
    bl   _snprintf
    ADRL x0, _g_sf_buf
    bl   _home_say0
    b    Lhs_done
Lhs_fetch_on:
    ADRL x0, Ls_k_fetch
    ADRL x1, Ls_one
    bl   _pref_set
    ADRL x8, _g_dbl_next
    str  xzr, [x8]
    ADRL x0, Ls_fetch_on
    bl   _home_say0
    b    Lhs_done
Lhs_fetch_off:
    ADRL x0, Ls_k_fetch
    ADRL x1, Ls_zero
    bl   _pref_set
    ADRL x0, Ls_fetch_off
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
.section __DATA,__const
.p2align 3
Lsrc_names:     .quad Lsrc_none, Lsrc_app, Lsrc_web, Lsrc_mesh

.section __TEXT,__const
.p2align 3
.include "dbl_key.inc"                    // the developer's public key and the list's URL
.p2align 3
Ldbl_ship:                                // the list shipped in this build (may be empty)
.incbin "dbl_list.bin"
Ldbl_ship_end:

.section __TEXT,__cstring,cstring_literals
Ls_hex:             .asciz "0123456789abcdef"
Ls_nl:              .asciz "\n"
Ls_one:             .asciz "1"
Ls_zero:            .asciz "0"
Ls_k_blocked:       .asciz "blocked"
Ls_k_filter:        .asciz "chatFilter"
Ls_k_report:        .asciz "reportTo"
Ls_k_dbl:           .asciz "devBlocklist"
Ls_k_fetch:         .asciz "blocklistFetch"
Ls_k_dblfrom:       .asciz "devBlocklistFrom"
Ls_on:              .asciz "on"
Ls_off:             .asciz "off"
Lsrc_none:          .asciz "none yet"
Lsrc_app:           .asciz "built into this app"
Lsrc_web:           .asciz "fetched from the web"
Lsrc_mesh:          .asciz "passed on over the mesh"
Ls_dbl_status:      .asciz "\302\267 \360\237\233\241 Developer blocklist: version %ld, %ld ids (%s). Shared with neighbours over the mesh; fetching from the web: %s."
Ls_dbl_nokey:       .asciz "\302\267 The developer blocklist isn\342\200\231t set up in this build (no key yet: tools/blocklist/blocklist.py keygen)."
Ls_fetch_on:        .asciz "\302\267 The developer blocklist will also be fetched from the web once a day (this shows the web host this device\342\200\231s address)."
Ls_fetch_off:       .asciz "\302\267 The developer blocklist comes only with app updates and over the mesh now."
Ls_get:             .asciz "GET"
Ls_tag_dbl:         .asciz "dbl"
Ls_length:          .asciz "length"
Ls_bytes:           .asciz "bytes"
Ls_stringForKey:    .asciz "stringForKey:"
Ls_UTF8String:      .asciz "UTF8String"
Ls_w_all:           .asciz "all"
Ls_w_block:         .asciz "block"
Ls_w_unblock:       .asciz "unblock"
Ls_w_report:        .asciz "report"
Ls_someone:         .asciz "someone not here now"
Ls_mailto:          .asciz "mailto:"
Ls_q_subject:       .asciz "?subject="
Ls_q_body:          .asciz "&body="
Ls_rep_subject:     .asciz "asmmesh report: "
Ls_rep_head:        .asciz "A report from asmmesh.\n\nAbout: %s (key %s, id %016llx)\n\nWhat they sent here lately:\n"
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
