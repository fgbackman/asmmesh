// mt_ble.s — a Meshtastic radio over Bluetooth, and its chat, walled off like MeshCore's and
// bitchat's. Behind the Meshtastic switch (SVC_MESHTASTIC, off by default, never with "enable
// all", never from the mesh). mt_core.s builds and reads the protobufs; this file connects,
// reads what the radio has, shows what comes in, and keeps the nodes it knows.
//
//   the radio      a Bluetooth device advertising Meshtastic's service 6ba1b218-…: write
//                  ToRadio (f75c76d2-…), read FromRadio (2c55e69e-…) until it comes back empty,
//                  FromNum (ed9da18c-…) notifies when there's more
//   start          want_config_id (a random number), then read: my node, the nodes, channels,
//                  config…, and config_complete_id with our number: ready
//   messages       FromNum: read until empty; a 30 s read anyway; a heartbeat every 5 minutes
//   the room       Meshtastic (MESHTASTIC_ID, local, there while the switch is on): the primary
//                  channel, and direct messages ("@Anna hi" sends one, acknowledged)
//
// The wall: text from the radio is shown in that room only, cleaned and filtered, never a
// command, never passed on. Only plain text (TEXT_MESSAGE_APP) is shown; other ports are
// ignored. What you type goes to the radio only, and every message written passes _mt_allowed
// first: start-up, a heartbeat or plain text — never admin, config, keys or raw packets. A
// message from the radio is read under _guard_call. Nodes are blocked by their node number.
// The simulated radio: _g_mt_test 1 keeps written messages in _g_mt_sim and counts reads;
// tests feed messages to _mt_frame_in (tools/qemu/mtsim.c, run.sh mtsim).
.include "macros.inc"
.include "mt_defs.inc"

.set TS_OFF,        0
.set TS_CONNECTING, 1
.set TS_STARTING,   2        // want_config sent: reading
.set TS_READY,      3        // config_complete_id came back
.set MT_NN,         128      // nodes kept
.set NT_NUM,        0        // u32
.set NT_SEEN,       4        // u32: last heard
.set NT_NAME,       8        // [40] cleaned, NUL-terminated
.set NT_SIZE,       48
.set MT_POLL_S,     30
.set MT_BEAT_S,     300
.set MT_SIM_N,      32
.set MT_SIM_SIZE,   528      // +0 length, +8 the message
.set MT_BCAST,      0xFFFFFFFF

.data
.p2align 3
.globl _g_mt_test
_g_mt_test:     .quad 0               // 1: the simulated radio (tests)
.globl _g_mt_sim_n
_g_mt_sim_n:    .quad 0
.globl _g_mt_reads
_g_mt_reads:    .quad 0               // reads asked of the simulated radio
.globl _g_mt_refused
_g_mt_refused:  .quad 0               // messages _mt_allowed stopped (should stay 0)
.globl _g_mt_state
_g_mt_state:    .quad 0
_g_mt_p:        .quad 0               // the radio, and its three characteristics (retained)
_g_mt_to:       .quad 0
_g_mt_from:     .quad 0
_g_mt_num:      .quad 0
_g_mt_u_svc:    .quad 0               // CBUUIDs
_g_mt_u_to:     .quad 0
_g_mt_u_from:   .quad 0
_g_mt_u_num:    .quad 0
.globl _g_mt_nonce
_g_mt_nonce:    .quad 0
.globl _g_mt_me
_g_mt_me:       .quad 0               // our node number
_g_mt_reading:  .quad 0
_g_mt_polled:   .quad 0
_g_mt_beat:     .quad 0
.globl _g_mt_nn
_g_mt_nn:       .quad 0
.globl _g_mt_sim
.zerofill __DATA,__bss,_g_mt_sim,(MT_SIM_N * MT_SIM_SIZE),4
.globl _g_mt_nodes
.zerofill __DATA,__bss,_g_mt_nodes,(MT_NN * NT_SIZE),4
.zerofill __DATA,__bss,_g_mt_mt,MT_SIZE,4
.zerofill __DATA,__bss,_g_mt_frame,528,4
.zerofill __DATA,__bss,_g_mt_text,640,4
.zerofill __DATA,__bss,_g_mt_line,800,4

.text
.p2align 2

// ---------------------------------------------------------------------------
// On and off (services.s)

// void _mt_start(void) — the switch on: the room, and look for a radio
.globl _mt_start
_mt_start:
    ENTER 0
    bl   Ltt_uuids
    bl   Ltt_room_on
    ADRL x8, _g_mt_state
    ldr  x9, [x8]
    cbnz x9, 9f
    ADRL x0, Ls_looking
    bl   Ltt_say
    ADRL x8, _g_mt_test
    ldr  x9, [x8]
    cbnz x9, 9f
    bl   _ble_scan                        // a radio is picked up from the scan (_mt_seen)
9:  LEAVE 0

// void _mt_stop(void) — the switch off: the radio let go, the room and nodes gone
.globl _mt_stop
_mt_stop:
    ENTER 0
    ADRL x8, _g_mt_p
    ldr  x0, [x8]
    cbz  x0, 1f
    bl   _ble_cancel
1:  bl   Ltt_forget
    ADRL x8, _g_mt_nn
    str  xzr, [x8]
    bl   Ltt_room_off
    bl   _ui_lists_changed
    LEAVE 0

// Ltt_forget — the link gone: what we held of it released
Ltt_forget:
    ENTER 0
    ADRL x19, _g_mt_p
    mov  x20, #0
1:  ldr  x0, [x19, x20, lsl #3]           // _g_mt_p, _to, _from, _num: next to each other
    cbz  x0, 2f
    MSG0 Ls_release
2:  str  xzr, [x19, x20, lsl #3]
    add  x20, x20, #1
    cmp  x20, #4
    b.lo 1b
    ADRL x8, _g_mt_state
    str  xzr, [x8]
    ADRL x8, _g_mt_reading
    str  xzr, [x8]
    LEAVE 0

// Ltt_uuids — the CBUUIDs, once
Ltt_uuids:
    ENTER 0
    ADRL x8, _g_mt_u_svc
    ldr  x9, [x8]
    cbnz x9, 9f
    ADRL x19, Ls_uuids
    ADRL x20, _g_mt_u_svc
    mov  x21, #0
1:  mov  x0, x19
    bl   _nsstr
    mov  x22, x0
    CLS  Ls_CBUUID
    mov  x2, x22
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    str  x0, [x20, x21, lsl #3]
    add  x19, x19, #37                    // the next (36 characters and a NUL)
    add  x21, x21, #1
    cmp  x21, #4
    b.lo 1b
9:  LEAVE 0

// ---------------------------------------------------------------------------
// Bluetooth (ble.s calls these, as it does mc_ble.s's)

// long _mt_seen(id peripheral, const char *name, id adv) -> 1 if it advertises Meshtastic's
//   service and the switch is on (then, if we have none, we connect)
.globl _mt_seen
_mt_seen:
    ENTER 0
    mov  x19, x0
    mov  x20, x2
    cbz  x20, 8f
    mov  x0, #SVC_MESHTASTIC
    bl   _svc_on
    cbz  x0, 8f
    bl   Ltt_uuids
    LDGOT x8, _CBAdvertisementDataServiceUUIDsKey
    ldr  x2, [x8]
    mov  x0, x20
    MSG1 Ls_objectForKey
    cbz  x0, 8f
    ADRL x8, _g_mt_u_svc
    ldr  x2, [x8]
    MSG1 Ls_containsObject
    tst  w0, #0xff
    b.eq 8f
    ADRL x8, _g_mt_p                      // one radio at a time
    ldr  x9, [x8]
    cbnz x9, 7f
    mov  x0, x19
    MSG0 Ls_retain
    ADRL x8, _g_mt_p
    str  x0, [x8]
    mov  x9, #TS_CONNECTING
    ADRL x8, _g_mt_state
    str  x9, [x8]
    ADRL x8, _g_cm
    ldr  x0, [x8]
    mov  x2, x19
    mov  x3, #0
    MSG2 Ls_connectPeripheral
7:  mov  x0, #1
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// long _mt_connected(id peripheral) -> 1 if it's our radio: find its service
.globl _mt_connected
_mt_connected:
    ENTER 0
    mov  x19, x0
    bl   Ltt_ours
    cbz  x0, 9f
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x19
    MSG1 Ls_setDelegate
    ADRL x8, _g_mt_u_svc
    ldr  x0, [x8]
    bl   _array1
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_discoverServices
    mov  x0, #1
9:  LEAVE 0

// long _mt_services(id peripheral, id err) -> 1 if ours: its characteristics
.globl _mt_services
_mt_services:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   Ltt_ours
    cbz  x0, 9f
    cbnz x20, 8f
    mov  x0, x19
    MSG0 Ls_services
    MSG0 Ls_firstObject
    cbz  x0, 8f
    mov  x3, x0
    mov  x2, #0
    mov  x0, x19
    MSG2 Ls_discoverCharacteristics
8:  mov  x0, #1
9:  LEAVE 0

// long _mt_chars(id peripheral, id service, id err) -> 1 if ours: keep ToRadio, FromRadio and
//   FromNum, listen to FromNum, start
.globl _mt_chars
_mt_chars:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    bl   Ltt_ours
    cbz  x0, Ltch_no
    cbnz x21, Ltch_yes
    mov  x0, x20
    MSG0 Ls_characteristics
    mov  x21, x0
    MSG0 Ls_count
    mov  x22, x0
1:  cbz  x22, 4f
    sub  x22, x22, #1
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_objectAtIndex
    mov  x23, x0
    MSG0 Ls_UUID
    str  x0, [sp, #96]
    mov  x24, #1                          // which: 1 ToRadio, 2 FromRadio, 3 FromNum
2:  ADRL x8, _g_mt_u_svc
    ldr  x2, [x8, x24, lsl #3]
    ldr  x0, [sp, #96]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.ne 3f
    add  x24, x24, #1
    cmp  x24, #4
    b.lo 2b
    b    1b
3:  mov  x0, x23
    MSG0 Ls_retain
    ADRL x8, _g_mt_p
    str  x0, [x8, x24, lsl #3]
    cmp  x24, #3
    b.ne 1b
    mov  x0, x19                          // FromNum: tell us when there's more
    mov  x2, #1
    mov  x3, x23
    MSG2 Ls_setNotifyValue
    b    1b
4:  ADRL x8, _g_mt_to                     // all three, or it isn't a radio we can talk to
    ldr  x9, [x8]
    ldr  x10, [x8, #8]
    ldr  x11, [x8, #16]
    cbz  x9, Ltch_drop
    cbz  x10, Ltch_drop
    cbz  x11, Ltch_drop
    bl   _mt_begin
Ltch_yes:
    mov  x0, #1
    LEAVE 16
Ltch_drop:
    ADRL x0, Ls_not_radio
    bl   Ltt_say
    mov  x0, x19
    bl   _ble_cancel
    b    Ltch_yes
Ltch_no:
    mov  x0, #0
    LEAVE 16

// long _mt_value(id peripheral, id chr, id err) -> 1 if it was our radio. FromRadio: one
//   message (read under _guard_call), then the next read; empty: done. FromNum: more to read.
.globl _mt_value
_mt_value:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    bl   Ltt_ours
    cbz  x0, 9f
    ADRL x8, _g_mt_num
    ldr  x9, [x8]
    cmp  x9, x20
    b.ne 1f
    bl   Ltt_read                         // FromNum changed: read
    b    8f
1:  ADRL x8, _g_mt_from
    ldr  x9, [x8]
    cmp  x9, x20
    b.ne 8f
    ADRL x8, _g_mt_reading
    str  xzr, [x8]
    cbnz x21, 8f
    mov  x0, x20
    MSG0 Ls_value
    cbz  x0, 8f
    mov  x21, x0
    MSG0 Ls_length
    mov  x22, x0
    cbz  x22, 8f                          // empty: nothing more for now
    cmp  x22, #MT_FRAME_MAX
    b.hi 7f
    mov  x0, x21
    MSG0 Ls_bytes
    mov  x1, x0                           // a copy: the NSData is the radio's
    ADRL x0, _g_mt_frame
    mov  x2, x22
    bl   _memcpy
    ADRL x0, _mt_frame_in
    ADRL x1, _g_mt_frame
    mov  x2, x22
    bl   _guard_call
7:  bl   Ltt_read                         // and the next
8:  mov  x0, #1
9:  LEAVE 0

// void _mt_lost(id peripheral) — the radio went away (or we let it go)
.globl _mt_lost
_mt_lost:
    ENTER 0
    mov  x19, x0
    bl   Ltt_ours
    cbz  x0, 9f
    ADRL x8, _g_mt_state
    ldr  x20, [x8]
    bl   Ltt_forget
    cmp  x20, #TS_READY
    b.ne 9f
    ADRL x0, Ls_lost
    bl   Ltt_say
9:  LEAVE 0

// long Ltt_ours(x19 peripheral) -> 1 if it's the radio we hold (leaf)
Ltt_ours:
    ADRL x8, _g_mt_p
    ldr  x9, [x8]
    cmp  x9, #0
    ccmp x9, x19, #0, ne
    cset x0, eq
    ret

// ---------------------------------------------------------------------------
// Talking to the radio

// void _mt_begin(void) — linked: ask for everything, with a number of ours, and read
.globl _mt_begin
_mt_begin:
    ENTER 0
    mov  x9, #TS_STARTING
    ADRL x8, _g_mt_state
    str  x9, [x8]
    bl   _arc4random
    orr  w19, w0, #1                      // never 0
    ADRL x8, _g_mt_nonce
    str  x19, [x8]
    ADRL x0, _g_mt_frame
    mov  w1, w19
    bl   _mt_want_config
    mov  x1, x0
    ADRL x0, _g_mt_frame
    bl   _mt_write
    bl   Ltt_read
    LEAVE 0

// long _mt_write(const uint8 *msg, long len) -> 1 written, 0 refused. The allowlist right before
//   the write: nothing reaches a radio around it
.globl _mt_write
_mt_write:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _mt_allowed
    cbz  x0, 8f
    ADRL x8, _g_mt_test
    ldr  x9, [x8]
    cbnz x9, 2f
    ADRL x8, _g_mt_to
    ldr  x21, [x8]
    cbz  x21, 9f
    CLS  Ls_NSData
    mov  x2, x19
    mov  x3, x20
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    ADRL x8, _g_mt_p
    ldr  x0, [x8]
    mov  x3, x21
    mov  x4, #0                           // with response
    MSG3 Ls_writeValue
    b    9f
2:  ADRL x8, _g_mt_sim_n
    ldr  x9, [x8]
    cmp  x9, #MT_SIM_N
    b.hs 9f
    add  x10, x9, #1
    str  x10, [x8]
    mov  x10, #MT_SIM_SIZE
    ADRL x8, _g_mt_sim
    madd x21, x9, x10, x8
    str  x20, [x21]
    add  x0, x21, #8
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
9:  mov  x0, #1
    LEAVE 0
8:  ADRL x8, _g_mt_refused
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    mov  x0, #0
    LEAVE 0

// Ltt_read — read FromRadio (once at a time)
Ltt_read:
    ENTER 0
    ADRL x8, _g_mt_reading
    ldr  x9, [x8]
    cbnz x9, 9f
    ADRL x8, _g_mt_test
    ldr  x9, [x8]
    cbnz x9, 1f
    ADRL x8, _g_mt_from
    ldr  x2, [x8]
    cbz  x2, 9f
    ADRL x8, _g_mt_reading
    mov  x9, #1
    str  x9, [x8]
    ADRL x8, _g_mt_p
    ldr  x0, [x8]
    MSG1 Ls_readValue
    b    9f
1:  ADRL x8, _g_mt_reads                  // simulated: counted
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
9:  LEAVE 0

// void _mt_tick(void) — every second: a read every 30 s (a missed FromNum), a heartbeat every 5 min
.globl _mt_tick
_mt_tick:
    ENTER 0
    ADRL x8, _g_mt_state
    ldr  x9, [x8]
    cmp  x9, #TS_STARTING
    b.lo 9f
    mov  x0, #0
    bl   _time
    mov  x19, x0
    ADRL x8, _g_mt_polled
    ldr  x9, [x8]
    sub  x10, x19, x9
    cmp  x10, #MT_POLL_S
    b.lo 1f
    str  x19, [x8]
    ADRL x8, _g_mt_reading                // (a read that never came back: try again)
    str  xzr, [x8]
    bl   Ltt_read
1:  ADRL x8, _g_mt_beat
    ldr  x9, [x8]
    sub  x10, x19, x9
    cmp  x10, #MT_BEAT_S
    b.lo 9f
    str  x19, [x8]
    ADRL x0, _g_mt_frame
    bl   _mt_heartbeat
    mov  x1, x0
    ADRL x0, _g_mt_frame
    bl   _mt_write
9:  LEAVE 0

// ---------------------------------------------------------------------------
// What the radio sends

// long _mt_frame_in(const uint8 *f, long len) — one FromRadio
.globl _mt_frame_in
_mt_frame_in:
    ENTER 16
    ADRL x2, _g_mt_mt
    bl   _mt_parse
    mov  x21, x0
    ADRL x22, _g_mt_mt
    cmp  x21, #MTK_MYINFO
    b.eq Ltf_my
    cmp  x21, #MTK_NODE
    b.eq Ltf_node
    cmp  x21, #MTK_DONE
    b.eq Ltf_done
    cmp  x21, #MTK_PACKET
    b.eq Ltf_packet
    b    9f
Ltf_my:
    ldr  x9, [x22, #MT_HAS]
    tbz  x9, #5, 9f
    ldr  x9, [x22, #MT_NUM]
    ADRL x8, _g_mt_me
    str  x9, [x8]
    b    9f
Ltf_node:
    ldr  x9, [x22, #MT_HAS]
    tbz  x9, #5, 9f
    ldr  w9, [x22, #MT_NUM]
    ADRL x8, _g_mt_me                     // not ourselves
    ldr  x10, [x8]
    cmp  x9, x10
    b.eq 9f
    bl   Ltt_node_add
    b    9f
Ltf_done:
    ldr  x9, [x22, #MT_NUM]
    ADRL x8, _g_mt_nonce
    ldr  x10, [x8]
    cmp  x9, x10                          // our number: ready
    b.ne 9f
    ADRL x8, _g_mt_state
    ldr  x10, [x8]
    mov  x9, #TS_READY
    str  x9, [x8]
    cmp  x10, #TS_READY
    b.eq 9f
    ADRL x8, _g_mt_nn
    ldr  x9, [x8]
    str  x9, [sp]
    ADRL x0, _g_mt_line
    mov  x1, #400
    ADRL x2, Ls_ready
    bl   _snprintf
    ADRL x0, _g_mt_line
    bl   Ltt_say
    bl   _ui_update_status
    b    9f
Ltf_packet:
    bl   Ltt_show
9:  mov  x0, #0
    LEAVE 16

// Ltt_node_add — a NodeInfo (_g_mt_mt): added or updated by number; its long name, or its
//   short one, or "!1a2b3c4d"
Ltt_node_add:
    ENTER 16
    ADRL x19, _g_mt_mt
    ldr  w20, [x19, #MT_NUM]
    mov  x0, x20
    bl   Ltt_node_find
    mov  x21, x0
    cbnz x21, 2f
    ADRL x8, _g_mt_nn                     // new: at the end, if there's room
    ldr  x9, [x8]
    cmp  x9, #MT_NN
    b.hs 9f
    add  x10, x9, #1
    str  x10, [x8]
    mov  x10, #NT_SIZE
    ADRL x8, _g_mt_nodes
    madd x21, x9, x10, x8
    str  w20, [x21, #NT_NUM]
2:  ldr  x9, [x19, #MT_HAS]
    tbz  x9, #10, 3f
    ldr  x10, [x19, #MT_SEEN]
    str  w10, [x21, #NT_SEEN]
3:  ldr  x1, [x19, #MT_LLEN]              // the long name, else the short one
    ldr  x0, [x19, #MT_LONG]
    tbz  x9, #7, 4f
    cbnz x1, 5f
4:  ldr  x1, [x19, #MT_SLEN]
    ldr  x0, [x19, #MT_SHORT]
    tbz  x9, #8, 6f
    cbz  x1, 6f
5:  add  x2, x21, #NT_NAME
    mov  x3, #33
    bl   _mc_show_text
    b    8f
6:  ldrb w9, [x21, #NT_NAME]              // no name: keep one we had, else its number
    cbnz w9, 8f
    str  x20, [sp]
    add  x0, x21, #NT_NAME
    mov  x1, #40
    ADRL x2, Ls_num_fmt
    bl   _snprintf
8:  bl   _ui_lists_changed
9:  LEAVE 16

// long Ltt_node_find(x0 number) -> the node (pointer), or 0
Ltt_node_find:
    ENTER 0
    mov  w19, w0
    mov  x20, #0
1:  ADRL x8, _g_mt_nn
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 8f
    mov  x10, #NT_SIZE
    ADRL x8, _g_mt_nodes
    madd x0, x20, x10, x8
    ldr  w9, [x0, #NT_NUM]
    cmp  w9, w19
    b.eq 9f
    add  x20, x20, #1
    b    1b
8:  mov  x0, #0
9:  LEAVE 0

// Ltt_show — a packet (_g_mt_mt): plain text to everyone or to us, from someone else, shown
//   ("Name: text", "Name → you: text"); anything else (other ports, encrypted, for others) not
Ltt_show:
    ENTER 32                              // [96] name (48)
    ADRL x19, _g_mt_mt
    ldr  x9, [x19, #MT_HAS]
    tbnz x9, #12, 9f                      // still encrypted: not for us to read
    tbz  x9, #3, 9f
    tbz  x9, #6, 9f
    ldr  x10, [x19, #MT_PORT]
    cmp  x10, #MT_PORT_TEXT
    b.ne 9f
    ldr  w20, [x19, #MT_FROM]             // from (0 if missing)
    ADRL x8, _g_mt_me
    ldr  x10, [x8]
    cmp  x20, x10
    b.eq 9f                               // our own, echoed
    ldr  w21, [x19, #MT_TO]
    mov  w10, #MT_BCAST
    cmp  w21, w10
    b.eq 1f
    ADRL x8, _g_mt_me                     // to someone: only if it's us
    ldr  x10, [x8]
    cmp  x21, x10
    b.ne 9f
1:  mov  x0, x20                          // blocked? (by node number)
    bl   _am_mt_id_of
    mov  x22, x0
    bl   _blk_has
    cbnz x0, 9f
    mov  x0, x20                          // the name
    bl   Ltt_node_find
    cbz  x0, 2f
    add  x1, x0, #NT_NAME
    add  x0, sp, #96
    mov  x2, #48
    bl   _strlcpy
    b    3f
2:  str  x20, [sp]
    add  x0, sp, #96
    mov  x1, #48
    ADRL x2, Ls_num_fmt
    bl   _snprintf
3:  ldr  x0, [x19, #MT_TEXT]
    ldr  x1, [x19, #MT_TLEN]
    ADRL x2, _g_mt_text
    mov  x3, #400
    bl   _mc_show_text
    ADRL x0, _g_mt_text
    bl   _chat_clean
    mov  x0, x22
    mov  x1, #MESHTASTIC_ID
    ADRL x2, _g_mt_text
    bl   _rec_note
    add  x9, sp, #96
    str  x9, [sp]
    ADRL x9, _g_mt_text
    str  x9, [sp, #8]
    ldr  x9, [x19, #MT_CHAN]
    str  x9, [sp, #16]
    ADRL x2, Lf_said
    mov  w10, #MT_BCAST
    cmp  w21, w10
    b.eq 4f
    ADRL x2, Lf_dm
    b    5f
4:  cbz  x9, 5f                           // another channel than the primary: say which
    ADRL x2, Lf_said_ch
5:  ADRL x0, _g_mt_line
    mov  x1, #700
    bl   _snprintf
    ADRL x0, _g_mt_line
    mov  x1, #0
    bl   Ltt_line
9:  LEAVE 32

// ---------------------------------------------------------------------------
// The Meshtastic room

// void _mt_say(const char *text) — typed in the Meshtastic room (mesh.s): to everyone on the
//   primary channel, or "@Name text" to that node (acknowledged). Only chat, never a command.
.globl _mt_say
_mt_say:
    ENTER 32                              // [96] length  [104] name shown
    mov  x19, x0
    ADRL x8, _g_mt_state
    ldr  x9, [x8]
    cmp  x9, #TS_READY
    ADRL x0, Ls_not_ready
    b.ne Ltsay_note
    ldrb w9, [x19]
    cmp  w9, #'@'
    b.eq Ltsay_dm
    mov  x0, x19                          // everyone, channel 0
    bl   _strlen
    str  x0, [sp, #96]
    bl   _arc4random
    mov  w3, w0
    ADRL x0, _g_mt_frame
    mov  w1, #MT_BCAST
    mov  x2, #0
    mov  x4, x19
    ldr  x5, [sp, #96]
    mov  x6, #0
    bl   _mt_send_text
    mov  x1, x0
    ADRL x0, _g_mt_frame
    bl   _mt_write
    mov  x0, x19
    ADRL x1, Lf_me
    b    Ltsay_show
Ltsay_dm:                                 // "@Name text": the node whose name it starts with
    add  x20, x19, #1
    mov  x21, #0
1:  ADRL x8, _g_mt_nn
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Ltsay_who
    mov  x10, #NT_SIZE
    ADRL x8, _g_mt_nodes
    madd x22, x21, x10, x8
    add  x0, x22, #NT_NAME
    bl   _strlen
    mov  x23, x0
    cbz  x23, 2f
    add  x0, x22, #NT_NAME
    mov  x1, x20
    mov  x2, x23
    bl   _strncasecmp
    cbnz w0, 2f
    ldrb w9, [x20, x23]
    cmp  w9, #' '
    b.eq 3f
2:  add  x21, x21, #1
    b    1b
3:  add  x24, x20, x23
4:  ldrb w9, [x24]
    cmp  w9, #' '
    b.ne 5f
    add  x24, x24, #1
    b    4b
5:  cbz  w9, Ltsay_who
    mov  x0, x24
    bl   _strlen
    str  x0, [sp, #96]
    bl   _arc4random
    mov  w3, w0
    ADRL x0, _g_mt_frame
    ldr  w1, [x22, #NT_NUM]
    mov  x2, #0
    mov  x4, x24
    ldr  x5, [sp, #96]
    mov  x6, #1                           // acknowledged
    bl   _mt_send_text
    mov  x1, x0
    ADRL x0, _g_mt_frame
    bl   _mt_write
    add  x9, x22, #NT_NAME
    str  x9, [sp, #104]
    mov  x0, x24
    ADRL x1, Lf_me_dm
    b    Ltsay_show
Ltsay_who:
    ADRL x0, Ls_no_node
Ltsay_note:
    bl   Ltt_say
    LEAVE 32
Ltsay_show:                               // our line, cleaned like anyone's
    mov  x20, x1
    mov  x22, x0
    bl   _strlen
    mov  x1, x0
    mov  x0, x22
    ADRL x2, _g_mt_text
    mov  x3, #400
    bl   _mc_show_text
    ADRL x8, _g_mt_text
    str  x8, [sp]
    ldr  x9, [sp, #104]
    str  x9, [sp, #8]
    ADRL x0, _g_mt_line
    mov  x1, #700
    mov  x2, x20
    bl   _snprintf
    ADRL x0, _g_mt_line
    mov  x1, #0
    bl   Ltt_line
    LEAVE 32

// Ltt_line(x0 text, x1 sys) — into the Meshtastic room
Ltt_line:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, #MESHTASTIC_ID
    bl   _room_find
    tbnz x0, #63, 9f
    mov  x1, x19
    mov  x2, x20
    bl   _room_line
9:  LEAVE 0

// Ltt_say(x0 text) — a system line in the Meshtastic room (or Main, without it)
Ltt_say:
    ENTER 0
    mov  x19, x0
    mov  x0, #MESHTASTIC_ID
    bl   _room_find
    tbnz x0, #63, 1f
    mov  x1, x19
    mov  x2, #1
    bl   _room_line
    LEAVE 0
1:  mov  x0, x19
    bl   _chat_line
    LEAVE 0

// Ltt_room_on / Ltt_room_off — the room comes and goes with the switch (local, never saved)
Ltt_room_on:
    ENTER 0
    mov  x0, #MESHTASTIC_ID
    bl   _room_find
    tbz  x0, #63, 9f
    mov  x0, #MESHTASTIC_ID
    ADRL x1, Ls_room
    mov  x2, #0
    bl   _room_add
    tbnz x0, #63, 9f
    bl   _ui_rooms_changed
9:  LEAVE 0
Ltt_room_off:
    ENTER 0
    mov  x0, #MESHTASTIC_ID
    bl   _room_find
    tbnz x0, #63, 9f
    mov  x19, x0
    ADRL x8, _g_cur_room                  // looking at it, or a room after it: go to Main
    ldr  x9, [x8]
    cmp  x9, x19
    b.lo 1f
    mov  x0, #0
    bl   _ui_select_room
1:  mov  x0, x19
    bl   _room_drop
    bl   _ui_rooms_changed
9:  LEAVE 0

// ---------------------------------------------------------------------------
// For the screens, People and blocking

.globl _am_mt_state
_am_mt_state:
    ADRL x8, _g_mt_state
    ldr  x0, [x8]
    ret
.globl _am_mt_nodes
_am_mt_nodes:
    ADRL x8, _g_mt_nn
    ldr  x0, [x8]
    ret
.globl _am_mt_node_name
_am_mt_node_name:
    mov  x10, #NT_SIZE
    ADRL x8, _g_mt_nodes
    madd x0, x0, x10, x8
    add  x0, x0, #NT_NAME
    ret
.globl _am_mt_node_seen
_am_mt_node_seen:
    mov  x10, #NT_SIZE
    ADRL x8, _g_mt_nodes
    madd x0, x0, x10, x8
    ldr  w0, [x0, #NT_SEEN]
    ret
// long am_mt_node_id(long i) -> an id for blocking node i
.globl _am_mt_node_id
_am_mt_node_id:
    mov  x10, #NT_SIZE
    ADRL x8, _g_mt_nodes
    madd x0, x0, x10, x8
    ldr  w0, [x0, #NT_NUM]
    b    _am_mt_id_of
// long am_mt_id_of(uint32 number) -> its id for blocking: the number, tagged 0x54 ('T') in the
//   top byte so it can't be an asmmesh, bitchat or MeshCore id (leaf)
.globl _am_mt_id_of
_am_mt_id_of:
    mov  w0, w0
    mov  x10, #0x5400000000000000
    orr  x0, x0, x10
    ret

// ---------------------------------------------------------------------------
// service, ToRadio, FromRadio, FromNum: each 36 characters and a NUL, in this order. A list read
//   in order: in __TEXT,__const, not __cstring (the Mac's linker takes those apart; lint.py)
.section __TEXT,__const
Ls_uuids:       .asciz "6BA1B218-15A8-461F-9FA8-5DCAE273EAFD"
                .asciz "F75C76D2-129E-4DAD-A1DD-7866124401E7"
                .asciz "2C55E69E-4993-11ED-B878-0242AC120002"
                .asciz "ED9DA18C-A800-4F66-A670-AA7547E34453"

.section __TEXT,__cstring,cstring_literals
Ls_room:        .asciz "Meshtastic"
Ls_num_fmt:     .asciz "!%08lx"
Lf_said:        .asciz "%s: %s"
Lf_said_ch:     .asciz "%1$s (channel %3$ld): %2$s"
Lf_dm:          .asciz "%s \342\206\222 you: %s"
Lf_me:          .asciz "me: %s"
Lf_me_dm:       .asciz "me \342\206\222 %2$s: %1$s"
Ls_looking:     .asciz "\302\267 Meshtastic is on: looking for a Meshtastic radio over Bluetooth. Your Mac or iPhone may ask for its PIN once (shown on the radio, or 123456)."
Ls_ready:       .asciz "\302\267 \360\237\223\241 Meshtastic radio linked: %ld nodes known. This room is its primary channel; @Name text sends a direct message. Nothing from LoRa runs here as a command."
Ls_lost:        .asciz "\302\267 The Meshtastic radio went out of reach; it\342\200\231s picked up again when it\342\200\231s back."
Ls_not_radio:   .asciz "\302\267 That device advertises Meshtastic but isn\342\200\231t a radio asmmesh can talk to."
Ls_not_ready:   .asciz "\302\267 No Meshtastic radio linked yet: nothing was sent."
Ls_no_node:     .asciz "\302\267 Nobody by that name among the radio\342\200\231s nodes (and a direct message needs some text)."
Ls_CBUUID:      .asciz "CBUUID"
Ls_UUIDWithString: .asciz "UUIDWithString:"
Ls_objectForKey: .asciz "objectForKey:"
Ls_containsObject: .asciz "containsObject:"
Ls_NSData:      .asciz "NSData"
Ls_dataWithBytes: .asciz "dataWithBytes:length:"
Ls_writeValue:  .asciz "writeValue:forCharacteristic:type:"
Ls_readValue:   .asciz "readValueForCharacteristic:"
Ls_setNotifyValue: .asciz "setNotifyValue:forCharacteristic:"
Ls_connectPeripheral: .asciz "connectPeripheral:options:"
Ls_setDelegate: .asciz "setDelegate:"
Ls_discoverServices: .asciz "discoverServices:"
Ls_discoverCharacteristics: .asciz "discoverCharacteristics:forService:"
Ls_services:    .asciz "services"
Ls_firstObject: .asciz "firstObject"
Ls_characteristics: .asciz "characteristics"
Ls_count:       .asciz "count"
Ls_objectAtIndex: .asciz "objectAtIndex:"
Ls_UUID:        .asciz "UUID"
Ls_isEqual:     .asciz "isEqual:"
Ls_value:       .asciz "value"
Ls_length:      .asciz "length"
Ls_bytes:       .asciz "bytes"
Ls_retain:      .asciz "retain"
Ls_release:     .asciz "release"
