// bc_ble.s — the Bluetooth link to bitchat's mesh (docs/bitchat_roadmap.md, Phase 2),
// behind its own switch (SVC_BITCHAT, off by default).
//
// The wall: bitchat has its own CBCentralManager, its own CBPeripheralManager and
// its own delegate object (class AMeshBitchat, built here), so none of its
// callbacks pass through asmmesh's controller, and nothing here calls the mesh,
// rooms, Home devices, rules or asmmesh's keys. Packets are read (bc_packet.s) and
// counted ("bitchat" in Home says what was heard); announces and leaves keep a list of
// bitchat people (bc_peer.s), shown in People with a bitchat badge. Nothing else yet.
//
// Our bitchat identity (Milestone 1): an X25519 key and an Ed25519 key of its own, random,
// in its own Keychain item ("asmmesh.bitchat"), never derived from or linked to the
// asmmesh identity. Read only while the switch is on, wiped from memory when it goes off;
// "bitchat forget" deletes it. We announce our name and those keys, signed, when a link
// comes up and every 15-19 s after, and say we're leaving when switched off.
//
//   central     scans for bitchat's service, connects, subscribes to the
//               characteristic's notifications, and writes to it
//   peripheral  publishes the same service and characteristic (notify, write,
//               write without response, read). Advertising it is off until
//               "bitchat advertise on": two peripheral managers advertising at
//               once must first be tried on a Mac (asmmesh's own advert must keep
//               working). Without it this Mac still links: it connects to them.
//
// Link table: BC_LINKS entries of L_SIZE bytes
//   +0   kind: 0 free, 1 we connected to it (it is the peripheral), 2 it connected to us
//   +8   CBPeripheral * / CBCentral *  retained
//   +16  its CBCharacteristic * (kind 1), retained
//   +24  state: 1 connecting, 2 discovering, 3 ready
//   +32  bytes per write or notification
//   +40  frames in   +48 bytes in   +56 writes refused   +64 frames out
//   +72  inbound write buffer (bc_defs.inc IB_*)
//   +600 send queue (Q_*), then when it was made and (kind 2) whether it subscribed
//
// Both managers use queue:nil, so every callback runs on the main thread.

.include "macros.inc"
.include "bc_defs.inc"

.set BC_LINKS,      8
.set L_KIND,        0
.set L_OBJ,         8
.set L_CHR,         16
.set L_STATE,       24
.set L_MAX,         32
.set L_IN,          40
.set L_BYTES,       48
.set L_REFUSED,     56
.set L_OUT,         64
.set L_IB,          72
.set L_Q,           600
.set L_SINCE,       (L_Q + Q_SIZE)          // when it was made (ms, _fm_now_ms)
.set L_SUB,         (L_SINCE + 8)           // 1: the central subscribed (kind 2)
.set L_PEER,        (L_SUB + 8)             // the bitchat person at the other end: the first
                                            //   to send a good announce on it with TTL 7
.set L_VL,          (L_PEER + 8)            // its limit on signature checks (RL_*)
.set L_SIZE,        (L_VL + RL_SIZE)
.set L_VERIFY_PS,   15          // signature checks a second, per link
.set L_PENDING,     2           // links of ours still coming up, at most
.set L_PER_KIND,    5           // links of one kind (ours / theirs), at most

.set K_THEY_PERIPH, 1
.set K_THEY_CENTRAL, 2
.set S_CONNECTING,  1
.set S_DISCOVERING, 2
.set S_READY,       3
.set CB_POWERED_ON, 5

// what has been heard, for "bitchat"
.set C_FRAMES,      0
.set C_BYTES,       8
.set C_ANNOUNCE,    16
.set C_MESSAGE,     24
.set C_PRIVATE,     32
.set C_FRAGMENT,    40
.set C_JOINED,      48          // packets put back together from fragments
.set C_OTHER,       56
.set C_REFUSED,     64
.set C_LINKS,       72          // links made since the switch went on
.set C_ANN_OK,      80          // announces taken
.set C_ANN_BAD,     88          // announces refused (not counting our own coming back)
.set C_SENT,        96          // announces and leaves we sent
.set C_RELAYED,     104         // packets passed on for other bitchat users
.set C_SHOWN,       112         // public messages shown in the bitchat room
.set C_SAID,        120         // public messages we sent
.set C_LIMITED,     128         // packets not checked: over the 30-a-second limit
.set C_SIZE,        136

// our bitchat keys (_g_bc_keys)
.set KS_NONE,       0
.set KS_LOADING,    1
.set KS_READY,      2
.set KS_REFUSED,    3           // the Keychain wouldn't hand them over: we stay quiet
.set CLOCK_WALL,    0           // CLOCK_REALTIME

.data
.p2align 3
_g_bc_cm:       .quad 0
_g_bc_pm:       .quad 0
_g_bc_dlg:      .quad 0
_g_bc_svc:      .quad 0         // CBUUID, retained
_g_bc_chu:      .quad 0         // CBUUID, retained
_g_bc_chr:      .quad 0         // our CBMutableCharacteristic, retained
.globl _g_bc_adv
_g_bc_adv:      .quad 0         // 1: advertise bitchat's service too
.zerofill __DATA,__bss,_g_bc_links,(BC_LINKS * L_SIZE),4
.zerofill __DATA,__bss,_g_bc_cnt,C_SIZE,4
.zerofill __DATA,__bss,_g_bc_fa,FA_SIZE,4
.zerofill __DATA,__bss,_g_bc_joined,FA_BYTES,4
.zerofill __DATA,__bss,_g_bc_dp,DP_SIZE,4                 // the packet just read (bc_packet.s)
.zerofill __DATA,__bss,_g_bc_pay,8192,4                   // its payload, if it came compressed
.zerofill __DATA,__bss,_g_bc_types,2048,4                 // packets read, by type
_g_bc_keys:     .quad 0         // KS_*
_g_bc_kcst:     .quad 0         // what the Keychain said when they were read
_g_bc_kclen:    .quad 0
_g_bc_ann_at:   .quad 0         // when the next announce goes (ms, _fm_now_ms); 0: next tick
_g_bc_quiet:    .quad 0         // 1: "bitchat announce off", for testing (listen only)
_g_bc_kcq:      .quad 0         // the Keychain queue (serial)
_g_bc_kcgen:    .quad 0         // which read is the current one
_g_bc_rxlink:   .quad 0         // the link the packet being read came on
_g_bc_ann_last: .quad 0         // when we last announced (ms, _fm_now_ms)
_g_bc_pinlen:   .quad 0         // what the Keychain gave for the pins (hex length)
_g_bc_pinsave:  .quad 0         // when the pins were last saved (ms, _fm_now_ms)
_g_bc_pinbusy:  .quad 0         // 1 while a save is under way on the Keychain queue
.zerofill __DATA,__bss,_g_bc_sk,64,4                      // X25519 secret, Ed25519 seed
.zerofill __DATA,__bss,_g_bc_xpub,32,4
.zerofill __DATA,__bss,_g_bc_edpub,32,4
.zerofill __DATA,__bss,_g_bc_myid,8,4                     // first 8 bytes of SHA-256(xpub)
.zerofill __DATA,__bss,_g_bc_kcbuf,160,4                  // the keys as hex, briefly (read)
.zerofill __DATA,__bss,_g_bc_kcw,160,4                    // the same, being saved
.globl _g_bc_peers
.zerofill __DATA,__bss,_g_bc_peers,BT_SIZE,4              // bitchat people (bc_peer.s)
.zerofill __DATA,__bss,_g_bc_scr,4096,4                   // what a signature covers
.zerofill __DATA,__bss,_g_bc_mydp,DP_SIZE,4               // a packet of ours
.zerofill __DATA,__bss,_g_bc_pl,128,4                     // its payload
.zerofill __DATA,__bss,_g_bc_out,512,4                    // and its bytes
.zerofill __DATA,__bss,_g_bc_dd,DD_SIZE,4                 // the duplicate filter (bc_packet.s)
.zerofill __DATA,__bss,_g_bc_rl,RL_SIZE,4                 // the relay limit (bc_peer.s)
.zerofill __DATA,__bss,_g_bc_vl,RL_SIZE,4                 // and the one for checking signatures
.zerofill __DATA,__bss,_g_bc_fwd,512,4                    // a packet being passed on
.zerofill __DATA,__bss,_g_bc_line,720,4                   // a line for the bitchat room
.globl _g_bc_pins
.zerofill __DATA,__bss,_g_bc_pins,PN_SIZE,4               // signing keys seen, for good
.zerofill __DATA,__bss,_g_bc_pinhex,14400,4               // the pins as hex (read)
.zerofill __DATA,__bss,_g_bc_pinw,14400,4                 // the same, being saved
.zerofill __DATA,__bss,_g_bc_hl,RL_SIZE,4                 // "is around" lines in Home: a few
.zerofill __DATA,__bss,_g_bc_name,32,4                    // our name on bitchat

.section __DATA,__const
.p2align 3
Lbc_methods:
    .quad Lm_cmState,    _bc_cm_state,    Lty_v1
    .quad Lm_cmDiscover, _bc_g_discover,  Lty_v4
    .quad Lm_cmConnect,  _bc_cm_connect,  Lty_v2
    .quad Lm_cmFail,     _bc_cm_lost,     Lty_v3
    .quad Lm_cmDisconn,  _bc_cm_lost,     Lty_v3
    .quad Lm_pServices,  _bc_p_services,  Lty_v2
    .quad Lm_pChars,     _bc_p_chars,     Lty_v3
    .quad Lm_pValue,     _bc_g_value,     Lty_v3
    .quad Lm_pModify,    _bc_p_modify,    Lty_v2
    .quad Lm_pReady,     _bc_p_ready,     Lty_v1
    .quad Lm_pmState,    _bc_pm_state,    Lty_v1
    .quad Lm_pmAdded,    _bc_pm_added,    Lty_v3
    .quad Lm_pmSub,      _bc_pm_sub,      Lty_v3
    .quad Lm_pmUnsub,    _bc_pm_unsub,    Lty_v3
    .quad Lm_pmWrites,   _bc_g_writes,    Lty_v2
    .quad Lm_pmRead,     _bc_pm_read,     Lty_v2
    .quad Lm_pmReady,    _bc_pm_ready,    Lty_v1
    .quad 0
Lbc_protos:
    .quad Lp_cm, Lp_p, Lp_pm, 0
// bitchat's packet types (MessageType.swift), for "bitchat"
Lbc_kind_tab:
    .quad 0x03, Lk_leave,   0x04, Lk_courier, 0x21, Lk_sync,   0x22, Lk_file
    .quad 0x23, Lk_board,   0x24, Lk_prekeys, 0x25, Lk_group,  0x26, Lk_ping
    .quad 0x27, Lk_pong,    0x28, Lk_nostr,   0x29, Lk_voice,  0x2c, Lk_presence
    .quad 0x100, Lk_unknown

.text
.p2align 2

// The doors a stranger's bytes come through run under the guard (guard.s): a fault
// drops that one advert, value or write, and asmmesh keeps going.
.macro BC_GUARDED name, real
\name:
    mov  x6, x5
    mov  x5, x4
    mov  x4, x3
    mov  x3, x2
    mov  x2, x1
    mov  x1, x0
    ADRL x0, \real
    b    _guard_call
.endm

    BC_GUARDED _bc_g_discover, _bc_cm_discover
    BC_GUARDED _bc_g_value, _bc_p_value
    BC_GUARDED _bc_g_writes, _bc_pm_writes

// x0 = &link[i]
.macro LINK reg, idx
    ADRL \reg, _g_bc_links
    mov  x9, #L_SIZE
    madd \reg, \idx, x9, \reg
.endm

// ---------------------------------------------------------------------------
// switching on and off

// void _bc_ble_start(void) — called by services.s when the bitchat switch is on
.globl _bc_ble_start
_bc_ble_start:
    ENTER 0
    ADRL x8, _g_bc_cm
    ldr  x9, [x8]
    cbnz x9, Lbs_done                     // already running
    ADRL x8, _g_bc_dlg                    // the delegate class, once per run
    ldr  x9, [x8]
    cbnz x9, Lbs_uuids
    bl   _bc_make_delegate
    ADRL x8, _g_bc_dlg
    str  x0, [x8]
Lbs_uuids:
    ADRL x8, _g_bc_svc
    ldr  x9, [x8]
    cbnz x9, Lbs_managers
    CLS  Ls_CBUUID
    mov  x19, x0
    ADRL x0, Ls_svc_str
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    ADRL x8, _g_bc_svc
    str  x0, [x8]
    ADRL x0, Ls_chr_str
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    ADRL x8, _g_bc_chu
    str  x0, [x8]
Lbs_managers:
    ADRL x8, _g_bc_dlg
    ldr  x20, [x8]
    CLS  Ls_CBCentralManager
    MSG0 Ls_alloc
    mov  x2, x20
    mov  x3, #0
    MSG2 Ls_initWithDelegate
    ADRL x8, _g_bc_cm
    str  x0, [x8]
    CLS  Ls_CBPeripheralManager
    MSG0 Ls_alloc
    mov  x2, x20
    mov  x3, #0
    MSG2 Ls_initWithDelegate
    ADRL x8, _g_bc_pm
    str  x0, [x8]
    ADRL x0, _g_bc_cnt
    mov  x1, #C_SIZE
    bl   _bc_wipe
    bl   Lbc_keys_load
    bl   Lbc_room_on
Lbs_done:
    LEAVE 0

// void _bc_ble_stop(void) — switch off: links dropped, managers gone, buffers wiped
.globl _bc_ble_stop
_bc_ble_stop:
    ENTER 0
    mov  x0, #0x03                        // "leaving": empty, signed (if we have keys)
    mov  x1, #0
    mov  x2, #0
    bl   Lbc_send_own
    mov  x0, #1                           // pins that changed: saved before they're wiped
    bl   Lbc_pins_save
    ADRL x8, _g_bc_adv                    // the test settings don't outlive the switch
    str  xzr, [x8]
    ADRL x8, _g_bc_quiet
    str  xzr, [x8]
    ADRL x8, _g_bc_cm
    ldr  x19, [x8]
    cbz  x19, Lbt_pm
    mov  x0, x19
    MSG0 Ls_stopScan
Lbt_pm:
    ADRL x8, _g_bc_pm
    ldr  x20, [x8]
    cbz  x20, Lbt_links
    mov  x0, x20
    MSG0 Ls_stopAdvertising
    mov  x0, x20
    MSG0 Ls_removeAllServices
Lbt_links:
    mov  x21, #0
1:  cmp  x21, #BC_LINKS
    b.hs 2f
    mov  x0, x21
    mov  x1, #1                           // and cancel the connections we made
    bl   _bc_link_free
    add  x21, x21, #1
    b    1b
2:  cbz  x19, 3f
    mov  x0, x19
    mov  x2, #0
    MSG1 Ls_setDelegate
    mov  x0, x19
    MSG0 Ls_release
    ADRL x8, _g_bc_cm
    str  xzr, [x8]
3:  cbz  x20, 4f
    mov  x0, x20
    mov  x2, #0
    MSG1 Ls_setDelegate
    mov  x0, x20
    MSG0 Ls_release
    ADRL x8, _g_bc_pm
    str  xzr, [x8]
4:  ADRL x8, _g_bc_chr
    ldr  x0, [x8]
    str  xzr, [x8]
    cbz  x0, 5f
    MSG0 Ls_release
5:  ADRL x0, _g_bc_fa
    mov  x1, #(FA_SIZE & 0xffff)
    movk x1, #(FA_SIZE >> 16), lsl #16
    bl   _bc_wipe
    ADRL x0, _g_bc_joined
    mov  x1, #FA_BYTES
    bl   _bc_wipe
    bl   Lbc_keys_wipe
    bl   Lbc_room_off
    bl   _ui_lists_changed
    LEAVE 0

// void Lbc_room_on(void) — the bitchat room comes with the switch
Lbc_room_on:
    ENTER 0
    mov  x0, #BITCHAT_ID
    bl   _room_find
    tbz  x0, #63, 1f                      // there already
    mov  x0, #BITCHAT_ID
    ADRL x1, Ls_bc_room
    mov  x2, #0
    bl   _room_add
    tbz  x0, #63, 2f
    ADRL x0, Ls_bc_noroom
    bl   Lbc_note0
    b    1f
2:  bl   _ui_rooms_changed
1:  LEAVE 0

// void Lbc_room_off(void) — and goes with it, transcript and all. It's local and never
//   saved, so it's dropped without saving anything (no Keychain write, unlike _room_remove).
Lbc_room_off:
    ENTER 0
    mov  x0, #BITCHAT_ID
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

// id _bc_make_delegate(void) — registers AMeshBitchat and returns a new one
_bc_make_delegate:
    ENTER 0
    CLS  Ls_NSObject
    ADRL x1, Ls_cls
    mov  x2, #0
    bl   _objc_allocateClassPair
    mov  x19, x0
    ADRL x20, Lbc_methods
1:  ldr  x0, [x20]
    cbz  x0, 2f
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    ldr  x2, [x20, #8]
    ldr  x3, [x20, #16]
    bl   _class_addMethod
    add  x20, x20, #24
    b    1b
2:  ADRL x20, Lbc_protos
3:  ldr  x0, [x20]
    cbz  x0, 5f
    bl   _objc_getProtocol
    cbz  x0, 4f
    mov  x1, x0
    mov  x0, x19
    bl   _class_addProtocol
4:  add  x20, x20, #8
    b    3b
5:  mov  x0, x19
    bl   _objc_registerClassPair
    mov  x0, x19
    MSG0 Ls_new
    LEAVE 0

// ---------------------------------------------------------------------------
// the link table

// long _bc_link_find(id obj) -> index, or -1
_bc_link_find:
    ADRL x8, _g_bc_links
    mov  x9, #0
    mov  x11, #L_SIZE
1:  cmp  x9, #BC_LINKS
    b.hs 3f
    madd x10, x9, x11, x8
    ldr  x12, [x10, #L_KIND]
    cbz  x12, 2f
    ldr  x12, [x10, #L_OBJ]
    cmp  x12, x0
    b.eq 4f
2:  add  x9, x9, #1
    b    1b
3:  mov  x0, #-1
    ret
4:  mov  x0, x9
    ret

// long _bc_link_new(id obj, long kind, long state) -> index, or -1 if the table is full
_bc_link_new:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, #0
1:  cmp  x22, #BC_LINKS
    b.hs 3f
    LINK x23, x22
    ldr  x9, [x23, #L_KIND]
    cbz  x9, 2f
    add  x22, x22, #1
    b    1b
2:  mov  x0, x23
    mov  x1, #L_SIZE
    bl   _bc_wipe
    mov  x0, x19
    MSG0 Ls_retain
    str  x0, [x23, #L_OBJ]
    str  x20, [x23, #L_KIND]
    str  x21, [x23, #L_STATE]
    mov  x9, #20                          // until we learn better: the smallest ATT payload
    str  x9, [x23, #L_MAX]
    bl   _fm_now_ms
    str  x0, [x23, #L_SINCE]
    ADRL x8, _g_bc_cnt
    ldr  x9, [x8, #C_LINKS]
    add  x9, x9, #1
    str  x9, [x8, #C_LINKS]
    mov  x0, x22
    LEAVE 0
3:  mov  x0, #-1
    LEAVE 0

// void _bc_link_free(long i, long cancel) — forget a link (cancel: also drop the
//   connection, for links we made)
_bc_link_free:
    ENTER 0
    mov  x20, x1
    LINK x19, x0
    ldr  x21, [x19, #L_KIND]
    cbz  x21, Llf_done
    ldr  x22, [x19, #L_OBJ]
    cmp  x21, #K_THEY_PERIPH
    b.ne 1f
    mov  x0, x22                          // it must not call us any more
    mov  x2, #0
    MSG1 Ls_setDelegate
    cbz  x20, 1f
    ADRL x8, _g_bc_cm
    ldr  x0, [x8]
    cbz  x0, 1f
    mov  x2, x22
    MSG1 Ls_cancelPeripheralConnection
1:  ldr  x0, [x19, #L_CHR]
    cbz  x0, 2f
    MSG0 Ls_release
2:  mov  x0, x22
    MSG0 Ls_release
    mov  x0, x19
    mov  x1, #L_SIZE
    bl   _bc_wipe
Llf_done:
    LEAVE 0

// void _bc_links_drop(long kind) — forget every link of one kind (its radio went off)
_bc_links_drop:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
1:  cmp  x20, #BC_LINKS
    b.hs 3f
    LINK x21, x20
    ldr  x9, [x21, #L_KIND]
    cmp  x9, x19
    b.ne 2f
    mov  x0, x20
    mov  x1, #0
    bl   _bc_link_free
2:  add  x20, x20, #1
    b    1b
3:  LEAVE 0

// long _bc_link_count(long kind) -> ready links of that kind (0: any kind)
.globl _bc_link_count
_bc_link_count:
    ADRL x8, _g_bc_links
    mov  x9, #0
    mov  x10, #0
    mov  x11, #L_SIZE
1:  cmp  x9, #BC_LINKS
    b.hs 3f
    madd x12, x9, x11, x8
    ldr  x13, [x12, #L_STATE]
    cmp  x13, #S_READY
    b.ne 2f
    ldr  x13, [x12, #L_KIND]
    cmp  x0, #0
    ccmp x13, x0, #4, ne
    b.ne 2f
    add  x10, x10, #1
2:  add  x9, x9, #1
    b    1b
3:  mov  x0, x10
    ret

// ---------------------------------------------------------------------------
// bytes in: one write or notification, possibly in pieces

// void _bc_rx(long i, long offset, const uint8 *p, long n)
_bc_rx:
    ENTER 0
    mov  x19, x0
    LINK x20, x19
    add  x0, x20, #L_IB
    bl   _bc_inbox_put
    cbz  x0, Lrx_done
    tbnz x0, #63, Lrx_refused
    mov  x2, x0
    mov  x0, x19
    add  x1, x20, #L_IB
    add  x1, x1, #IB_DATA
    bl   _bc_frame_in
    LEAVE 0
Lrx_refused:
    ldr  x9, [x20, #L_REFUSED]
    add  x9, x9, #1
    str  x9, [x20, #L_REFUSED]
    ADRL x8, _g_bc_cnt
    ldr  x9, [x8, #C_REFUSED]
    add  x9, x9, #1
    str  x9, [x8, #C_REFUSED]
Lrx_done:
    LEAVE 0

// void _bc_frame_in(long i, const uint8 *p, long n) — one whole bitchat packet arrived.
//   It's read (bc_packet.s; a broken one is refused), counted by type, and fragments are
//   put back together. Checking signatures and relaying need bitchat peers' keys
//   (Milestone 1): until then nothing else sees them.
_bc_frame_in:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    LINK x22, x19
    ldr  x9, [x22, #L_IN]
    add  x9, x9, #1
    str  x9, [x22, #L_IN]
    ldr  x9, [x22, #L_BYTES]
    add  x9, x9, x21
    str  x9, [x22, #L_BYTES]
    ADRL x23, _g_bc_cnt
    ldr  x9, [x23, #C_FRAMES]
    add  x9, x9, #1
    str  x9, [x23, #C_FRAMES]
    ldr  x9, [x23, #C_BYTES]
    add  x9, x9, x21
    str  x9, [x23, #C_BYTES]
    mov  x0, x20                          // read it (bc_packet.s): a broken one goes no further
    mov  x1, x21
    mov  x2, x19
    bl   Lbc_read
    tbnz x0, #63, Lfi_refused
    ldrb w10, [x20, #1]                   // type
    mov  x11, #C_OTHER
    cmp  w10, #0x01
    mov  x12, #C_ANNOUNCE
    csel x11, x12, x11, eq
    cmp  w10, #0x02
    mov  x12, #C_MESSAGE
    csel x11, x12, x11, eq
    cmp  w10, #0x10
    mov  x12, #C_PRIVATE
    csel x11, x12, x11, eq
    cmp  w10, #0x11
    csel x11, x12, x11, eq
    cmp  w10, #0x20
    mov  x12, #C_FRAGMENT
    csel x11, x12, x11, eq
    ldr  x9, [x23, x11]
    add  x9, x9, #1
    str  x9, [x23, x11]
    cmp  w10, #0x20
    b.ne Lfi_done
    ADRL x8, _g_bc_dp                     // a fragment: its sender and payload, as Lbc_read
    ldr  x22, [x8, #DP_PAY]               //   read them (a compressed one already unpacked)
    ldr  x24, [x8, #DP_PLEN]
    ldr  x21, [x8, #DP_SENDER]
    bl   _fm_now_ms
    mov  x1, x0
    ADRL x0, _g_bc_fa
    mov  x2, x21
    mov  x3, x22
    mov  x4, x24
    ADRL x5, _g_bc_joined
    mov  x6, x19                          // the link it came on
    bl   _bc_frag_put
    cmp  x0, #0
    b.eq Lfi_done
    b.lt Lfi_refused
    mov  x1, x0
    ldr  x9, [x23, #C_JOINED]
    add  x9, x9, #1
    str  x9, [x23, #C_JOINED]
    ADRL x0, _g_bc_joined                 // what it was: read that too
    mov  x2, x19
    bl   Lbc_read
    b    Lfi_done
Lfi_refused:
    ldr  x9, [x23, #C_REFUSED]
    add  x9, x9, #1
    str  x9, [x23, #C_REFUSED]
Lfi_done:
    LEAVE 0

// long Lbc_read(const uint8 *p, long n, long link) -> 0, or -1 if bc_packet.s refuses it.
//   Counted by type; then, unless it's a fragment (put back together by the caller) or a
//   duplicate: announces and leaves keep the list of people, public messages go to the
//   bitchat room, and it's passed on for other bitchat users when bitchat's rules say so.
Lbc_read:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x2, _g_bc_dp
    ADRL x3, _g_bc_pay
    mov  x4, #8192
    bl   _bc_decode
    tbnz x0, #63, 9f
    ADRL x8, _g_bc_dp
    ldr  x22, [x8, #DP_TYPE]
    ADRL x8, _g_bc_types
    ldr  x10, [x8, x22, lsl #3]
    add  x10, x10, #1
    str  x10, [x8, x22, lsl #3]
    cmp  x22, #0x20                       // fragments: never relayed, put back together
    b.eq 8f
    ADRL x8, _g_bc_keys                   // without our id we can't tell our own apart
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    b.ne 8f
    ADRL x8, _g_bc_rxlink
    str  x21, [x8]
    bl   Lbc_wall_ms
    mov  x23, x0                          // x23: now
    mov  x1, x23                          // heard it already, by another way? (announces,
    ADRL x0, _g_bc_dd                     //   leaves and messages are only remembered once
    ADRL x2, _g_bc_dp                     //   taken: a forged copy can't block the real one)
    cmp  x22, #0x01
    ccmp x22, #0x02, #4, ne
    ccmp x22, #0x03, #4, ne
    cset x24, ne                          // x24: 1 when no signature is checked
    mov  x3, x24
    bl   _bc_seen
    cbnz x0, 8f
    cbnz x24, 4f
    mov  x0, x21                          // signatures: 15 a second per link, so one link's
    mov  x1, #L_SIZE                      //   flood can't starve the others
    ADRL x9, _g_bc_links
    madd x0, x0, x1, x9
    mov  x9, #L_VL
    add  x0, x0, x9
    mov  x1, x23
    mov  x2, #L_VERIFY_PS
    mov  x3, #1000
    bl   _bc_rate_ok
    cbnz x0, 1f
    ADRL x8, _g_bc_cnt
    ldr  x9, [x8, #C_LIMITED]
    add  x9, x9, #1
    str  x9, [x8, #C_LIMITED]
    b    8f
1:  cmp  x22, #0x01
    b.ne 2f
    bl   Lbc_heard
    b    3f
2:  cmp  x22, #0x03
    b.ne 21f
    bl   Lbc_left
    b    3f
21: bl   Lbc_message
3:  cbz  x0, 8f                           // not taken: not remembered, not passed on
    mov  x1, x23
    ADRL x0, _g_bc_dd
    ADRL x2, _g_bc_dp
    mov  x3, #1
    bl   _bc_seen
4:  mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lbc_forward
8:  mov  x0, #0
9:  LEAVE 0

// void Lbc_forward(const uint8 *p, long n, long link) — pass the packet just read (in
//   _g_bc_dp) on to our other links, as a bitchat phone would: bitchat's TTL rule
//   (bc_packet.s _bc_relay), never back where it came from, 20 a second at most. The TTL
//   isn't signed, so lowering it keeps the signature good. Only to bitchat links: nothing
//   from bitchat ever goes on asmmesh's mesh.
Lbc_forward:
    ENTER 16                              // [96] the phone it came from (0: unknown)
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    LINK x9, x21
    ldr  x9, [x9, #L_PEER]
    str  x9, [sp, #96]
    ADRL x22, _g_bc_dp
    ADRL x8, _g_bc_myid
    ldr  x10, [x8]
    ldr  x9, [x22, #DP_SENDER]
    ldr  x9, [x9]
    cmp  x9, x10
    cset x23, eq                          // sent by us
    mov  x24, #0                          // to us
    ldr  x9, [x22, #DP_RCPT]
    cbz  x9, 1f
    ldr  x9, [x9]
    cmp  x9, x10
    cset x24, eq
1:  bl   Lbc_degree                       // only one phone: nowhere else to pass it
    mov  x3, x0
    cmp  x3, #2
    b.lo 9f
    mov  x0, x22
    mov  x1, x23
    mov  x2, x24
    bl   _bc_relay
    cbz  x0, 9f
    mov  x23, x0                          // the TTL to pass it on with
    bl   Lbc_wall_ms
    mov  x1, x0
    ADRL x0, _g_bc_rl
    bl   _bc_relay_ok
    cbz  x0, 9f
    mov  x0, x19                          // without its padding, at most one write
    mov  x1, x20
    bl   _bc_frame_len
    cmp  x0, #0
    b.le 9f
    cmp  x0, #BC_WRITE_MAX
    b.hi 9f
    mov  x20, x0
    mov  x9, #0
2:  cmp  x9, x20
    b.hs 3f
    ldrb w10, [x19, x9]
    ADRL x11, _g_bc_fwd
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    2b
3:  ADRL x11, _g_bc_fwd
    strb w23, [x11, #2]
    mov  x22, #0                          // every link but the one it came in on
    mov  x24, #0
4:  cmp  x22, #BC_LINKS
    b.hs 6f
    cmp  x22, x21
    b.eq 5f
    ldr  x12, [sp, #96]                   // nor back to the same phone on its other link
    cbz  x12, 41f
    LINK x10, x22
    ldr  x11, [x10, #L_PEER]
    cmp  x11, x12
    b.eq 5f
41: mov  x0, x22
    ADRL x1, _g_bc_fwd
    mov  x2, x20
    bl   _bc_send
    cmp  x0, #1
    cinc x24, x24, eq
5:  add  x22, x22, #1
    b    4b
6:  cbz  x24, 9f
    ADRL x8, _g_bc_cnt
    ldr  x9, [x8, #C_RELAYED]
    add  x9, x9, #1
    str  x9, [x8, #C_RELAYED]
9:  LEAVE 16

// long Lbc_message(void) -> 1 if taken: a public message read into _g_bc_dp goes into the
//   bitchat room as "Anna (1a2b): text" (cleaned: _bc_text_clean; 1a2b: the start of their
//   fingerprint, so nobody passes for someone else, or for "you"), if it's from someone
//   whose announce we took and signed by them.
//   Only shown: never read as a command, whatever it says.
Lbc_message:
    ENTER 800                             // [96] the text [720] room [728] fingerprint
    bl   Lbc_wall_ms
    mov  x1, x0
    ADRL x0, _g_bc_peers
    ADRL x2, _g_bc_myid
    ADRL x3, _g_bc_dp
    ADRL x4, _g_bc_scr
    mov  x5, #4096
    bl   _bc_msg_read
    tbnz x0, #63, 8f
    ADRL x8, _g_bc_peers
    add  x19, x8, x0, lsl #BT_SHIFT       // x19: who said it
    mov  x0, #BITCHAT_ID
    bl   _room_find
    tbnz x0, #63, 7f                      // (taken, but there's no room to show it in)
    str  x0, [sp, #720]
    mov  x0, x19
    add  x1, sp, #728
    bl   _bc_person_fp
    strb wzr, [sp, #732]                  // the first four characters
    ADRL x8, _g_bc_dp                     // the text: at most 600 bytes, between characters
    ldr  x20, [x8, #DP_PAY]
    ldr  x1, [x8, #DP_PLEN]
    mov  x0, x20
    mov  x2, #600
    bl   _bc_utf8_cut
    mov  x21, x0
    add  x22, sp, #96
    mov  x0, x22                          // nothing in it may fake a line or turn text
    mov  x1, x20
    mov  x2, x21
    bl   _bc_text_clean
    strb wzr, [x22, x21]
    mov  x0, x19
    bl   _bc_person_clash
    ADRL x2, Lf_bc_said
    ADRL x10, Lf_bc_said_clash
    cmp  x0, #0
    csel x2, x10, x2, ne
    add  x9, x19, #BT_NICK
    str  x9, [sp]
    add  x9, sp, #728
    str  x9, [sp, #8]
    str  x22, [sp, #16]
    ADRL x0, _g_bc_line
    mov  x1, #720
    bl   _snprintf
    ldr  x0, [sp, #720]
    ADRL x1, _g_bc_line
    mov  w2, #0
    bl   _room_line
    ADRL x8, _g_bc_cnt
    ldr  x9, [x8, #C_SHOWN]
    add  x9, x9, #1
    str  x9, [x8, #C_SHOWN]
7:  mov  x0, #1
    LEAVE 800
8:  mov  x0, #0
    LEAVE 800

// void _bc_say(const char *text) — typed into the bitchat room (mesh.s): a public message
//   to bitchat, in pieces of BT_MSG_MAX bytes (cut at spaces), each signed. Only chat:
//   whatever it says, nothing here runs it as a command.
.globl _bc_say
_bc_say:
    ENTER 144                             // [96] one piece, for showing it
    mov  x19, x0
    mov  x0, #BITCHAT_ID
    bl   _room_find
    mov  x22, x0                          // x22: the bitchat room
    tbnz x22, #63, 9f
    mov  x0, #SVC_BITCHAT
    bl   _svc_on
    ADRL x1, Ls_bc_say_off
    cbz  x0, 8f
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    ADRL x1, Ls_bc_say_nokeys
    b.ne 8f
    mov  x0, #0
    bl   _bc_link_count
    ADRL x1, Ls_bc_say_nolink
    cbz  x0, 8f
    mov  x0, x19
    bl   _strlen
    mov  x20, x0                          // x20: bytes left
1:  cbz  x20, 9f
    ldrb w9, [x19]                        // no piece starts with a space
    cmp  w9, #' '
    b.ne 2f
    add  x19, x19, #1
    sub  x20, x20, #1
    b    1b
2:  mov  x0, x19
    mov  x1, x20
    mov  x2, #BT_MSG_MAX
    bl   _bc_msg_split
    mov  x21, x0
    cbnz x21, 21f                         // (never 0: it would never end)
    mov  x21, #1
21: mov  x0, #0x02
    mov  x1, x19
    mov  x2, x21
    bl   Lbc_send_own
    mov  x23, x0                          // links it went to
    mov  x9, #0                           // show it: "you: piece"
3:  cmp  x9, x21
    b.hs 4f
    ldrb w10, [x19, x9]
    add  x11, sp, #96
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    3b
4:  add  x11, sp, #96
    strb wzr, [x11, x9]
    str  x11, [sp]
    ADRL x0, _g_bc_line
    mov  x1, #720
    ADRL x2, Lf_bc_you
    ADRL x10, Lf_bc_unsent                // no link took it: say so, don't pretend
    cmp  x23, #0
    csel x2, x10, x2, eq
    bl   _snprintf
    mov  x0, x22
    ADRL x1, _g_bc_line
    cmp  x23, #0
    cset w2, eq
    bl   _room_line
    cbz  x23, 22f
    ADRL x8, _g_bc_cnt
    ldr  x9, [x8, #C_SAID]
    add  x9, x9, #1
    str  x9, [x8, #C_SAID]
22:
    add  x19, x19, x21
    sub  x20, x20, x21
    b    1b
8:  mov  x0, x22
    mov  w2, #1
    bl   _room_line
9:  LEAVE 144

// ---------------------------------------------------------------------------
// our bitchat identity, announces, and the people heard (Milestone 1)

// void Lbc_note(const char *fmt, a, b, c) — a line in Home from bitchat's own callbacks:
//   straight into the room, never into the reply to a remote command (the wall)
Lbc_note:
    ENTER 512
    str  x1, [sp]
    str  x2, [sp, #8]
    str  x3, [sp, #16]
    mov  x2, x0
    add  x0, sp, #96
    mov  x1, #400
    bl   _snprintf
    ADRL x8, _g_home_idx
    ldr  x0, [x8]
    add  x1, sp, #96
    mov  w2, #1
    bl   _room_line
    LEAVE 512
Lbc_note0:
    mov  x1, x0
    ADRL x0, Ls_bc_pcts
    b    Lbc_note

// long Lbc_wall_ms(void) -> ms since 1970
Lbc_wall_ms:
    ENTER 16                              // [96] timespec
    mov  w0, #CLOCK_WALL
    add  x1, sp, #96
    bl   _clock_gettime
    ldr  x0, [sp, #96]
    ldr  x1, [sp, #104]
    mov  x2, #1000
    mul  x0, x0, x2
    mov  x2, #16960
    movk x2, #15, lsl #16                 // 1,000,000
    udiv x1, x1, x2
    add  x0, x0, x1
    LEAVE 16

// The Keychain, for our bitchat keys: every read, write and delete runs on one serial queue
// of its own (macOS may ask first, and the app mustn't freeze meanwhile), in the order
// asked. Each read carries a generation number: an answer to an older one (switched off
// and on again meanwhile) is ignored, so it can never make us new keys by mistake.

// dispatch_queue_t Lbc_kcq(void) — the queue, made once
Lbc_kcq:
    ENTER 0
    ADRL x8, _g_bc_kcq
    ldr  x0, [x8]
    cbnz x0, 1f
    ADRL x0, Ls_bc_q
    mov  x1, #0                           // serial
    bl   _dispatch_queue_create
    ADRL x8, _g_bc_kcq
    str  x0, [x8]
1:  LEAVE 0

// void Lbc_keys_load(void) — main thread, switch on: read our keys, then Lbc_kc_ready
Lbc_keys_load:
    ENTER 0
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    cbnz x9, 1f                           // loading, ready, or refused already
    mov  x9, #KS_LOADING
    str  x9, [x8]
    ADRL x8, _g_bc_kcgen
    ldr  x19, [x8]
    add  x19, x19, #1
    str  x19, [x8]
    bl   Lbc_kcq
    mov  x1, x19                          // the generation rides along
    ADRL x2, Lbc_kc_worker
    bl   _dispatch_async_f
1:  LEAVE 0

// void Lbc_kc_worker(long gen) — on the Keychain queue
Lbc_kc_worker:
    ENTER 0
    mov  x19, x0
    ADRL x0, Ls_bc_kc
    ADRL x1, _g_bc_kcbuf
    mov  x2, #160
    bl   _kc_get                          // x1: what the Keychain said, to this read alone
    ADRL x8, _g_bc_kclen
    str  x0, [x8]
    ADRL x8, _g_bc_kcst
    str  x1, [x8]
    ADRL x0, Ls_bc_kcpins                 // and the signing keys of everyone seen before
    ADRL x1, _g_bc_pinhex
    mov  x2, #14400
    bl   _kc_get
    ADRL x8, _g_bc_pinlen
    str  x0, [x8]
    LDGOT x0, __dispatch_main_q
    mov  x1, x19
    ADRL x2, Lbc_kc_ready
    bl   _dispatch_async_f
    LEAVE 0

// void Lbc_kc_write(void *unused) — on the Keychain queue: save new keys (_g_bc_kcw, hex),
//   then wipe that copy
Lbc_kc_write:
    ENTER 0
    ADRL x0, Ls_bc_kc
    ADRL x1, _g_bc_kcw
    bl   _kc_set
    ADRL x0, _g_bc_kcw
    mov  x1, #160
    bl   _bc_wipe
    LEAVE 0

// void Lbc_kc_delete(void *unused) — on the Keychain queue: "bitchat forget"
Lbc_kc_delete:
    ENTER 0
    ADRL x0, Ls_bc_kc
    bl   _kc_del
    ADRL x0, Ls_bc_kcpins
    bl   _kc_del
    LEAVE 0

// void Lbc_kc_pinwrite(void *unused) — on the Keychain queue: save the pins (_g_bc_pinw)
Lbc_kc_pinwrite:
    ENTER 0
    ADRL x0, Ls_bc_kcpins
    ADRL x1, _g_bc_pinw
    bl   _kc_set
    ADRL x8, _g_bc_pinbusy
    str  xzr, [x8]
    LEAVE 0

// void Lbc_pins_load(void) — main thread, after a read: the pins from the Keychain (hex,
//   PN_ESIZE bytes each), as far as they're good
Lbc_pins_load:
    ENTER 0
    ADRL x0, _g_bc_pins
    mov  x1, #(PN_SIZE & 0xffff)
    bl   _bc_wipe
    ADRL x8, _g_bc_pinlen
    ldr  x19, [x8]
    mov  x9, #(PN_ESIZE * 2)
    udiv x19, x19, x9                     // how many
    cmp  x19, #PN_N
    mov  x9, #PN_N
    csel x19, x19, x9, lo
    mov  x20, #0
1:  cmp  x20, x19
    b.hs 9f
    ADRL x0, _g_bc_pinhex
    mov  x9, #(PN_ESIZE * 2)
    madd x0, x20, x9, x0
    mov  x1, #PN_ESIZE
    ADRL x2, _g_bc_pins
    add  x2, x2, #PN_HDR
    mov  x9, #PN_ESIZE
    madd x21, x20, x9, x2
    mov  x2, x21
    bl   _hex_dec
    cbz  x0, 8f
    add  x20, x20, #1
    b    1b
8:  mov  x0, x21                          // a bad one, and the rest: not used
    mov  x1, #PN_ESIZE
    bl   _bc_wipe
9:  LEAVE 0

// void Lbc_pins_save(long now_too) — main thread: the pins, if they changed, to the Keychain
//   queue (every 10 s at most, unless now_too: switching off). Only the pins in use.
Lbc_pins_save:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_bc_pins
    ldr  x9, [x8, #PN_DIRTY]
    cbz  x9, 9f
    ADRL x8, _g_bc_pinbusy                // the last save still under way
    ldr  x9, [x8]
    cbnz x9, 9f
    bl   _fm_now_ms
    mov  x20, x0
    cbnz x19, 1f
    ADRL x8, _g_bc_pinsave
    ldr  x9, [x8]
    sub  x9, x20, x9
    mov  x10, #10000
    cmp  x9, x10
    b.lo 9f
1:  ADRL x8, _g_bc_pinsave
    str  x20, [x8]
    ADRL x8, _g_bc_pins
    str  xzr, [x8, #PN_DIRTY]
    ADRL x21, _g_bc_pins                  // each pin in use, as hex, one after another
    add  x21, x21, #PN_HDR
    ADRL x22, _g_bc_pinw
    mov  x23, #0
2:  cmp  x23, #PN_N
    b.hs 3f
    ldr  x9, [x21, #PN_HEARD]
    cbz  x9, 21f
    mov  x0, x21
    mov  x1, #PN_ESIZE
    mov  x2, x22
    bl   _hex_enc
    add  x22, x22, #(PN_ESIZE * 2)
21: add  x21, x21, #PN_ESIZE
    add  x23, x23, #1
    b    2b
3:  strb wzr, [x22]
    ADRL x8, _g_bc_pinbusy
    mov  x9, #1
    str  x9, [x8]
    bl   Lbc_kcq
    mov  x1, #0
    ADRL x2, Lbc_kc_pinwrite
    bl   _dispatch_async_f
9:  LEAVE 0

// void Lbc_name_load(void) — our name on bitchat: the one set with "bitchat name", or a
//   neutral "anon" and four digits from our bitchat id. Never our asmmesh name: the two
//   identities mustn't be linkable by it.
Lbc_name_load:
    ENTER 0
    ADRL x0, Ls_bc_kname
    ADRL x1, _g_bc_name
    mov  x2, #32
    bl   _pref_get
    ADRL x8, _g_bc_name
    ldrb w9, [x8]
    cbnz w9, 9f
    ADRL x8, _g_bc_myid
    ldrh w9, [x8]
    mov  x10, #10000
    udiv x11, x9, x10
    msub x9, x11, x10, x9
    str  x9, [sp]
    ADRL x0, _g_bc_name
    mov  x1, #32
    ADRL x2, Lf_bc_anon
    bl   _snprintf
9:  LEAVE 0

// void Lbc_kc_scrub(void *unused) — on the Keychain queue: the read buffer wiped, after
//   any read still under way
Lbc_kc_scrub:
    ENTER 0
    ADRL x0, _g_bc_kcbuf
    mov  x1, #160
    bl   _bc_wipe
    LEAVE 0

// void Lbc_kc_ready(long gen) — main thread: use our keys, or make them if the Keychain
//   truly has none (never because it said no: that would change who we are)
Lbc_kc_ready:
    ENTER 0
    ADRL x8, _g_bc_kcgen                  // an answer to an older read: not ours to use
    ldr  x9, [x8]
    cmp  x0, x9
    b.ne Lkr_stale
    mov  x0, #SVC_BITCHAT                 // switched off meanwhile: forget what was read
    bl   _svc_on
    cbz  x0, Lkr_off
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    cmp  x9, #KS_LOADING
    b.ne Lkr_done
    ADRL x8, _g_bc_kclen
    ldr  x9, [x8]
    cmp  x9, #128
    b.ne Lkr_none
    ADRL x0, _g_bc_kcbuf
    mov  x1, #64
    ADRL x2, _g_bc_sk
    bl   _hex_dec
    cbnz x0, Lkr_derive
    b    Lkr_refused                      // there, but not keys: leave it be, say so
Lkr_none:
    ADRL x8, _g_bc_kcst
    ldr  x9, [x8]
    mov  x10, #-25300                     // errSecItemNotFound: there truly are none
    cmp  x9, x10
    b.eq Lkr_new
    cbnz x9, Lkr_refused
    ADRL x8, _g_bc_kclen                  // no error and nothing there: none either
    ldr  x10, [x8]
    cbz  x10, Lkr_new
Lkr_refused:
    ADRL x0, _g_bc_sk                     // whatever _hex_dec got through: gone
    mov  x1, #64
    bl   _bc_wipe
    ADRL x8, _g_bc_keys
    mov  x10, #KS_REFUSED
    str  x10, [x8]
    ADRL x8, _g_bc_kcst
    ldr  x1, [x8]
    ADRL x0, Lf_bc_kc_no
    bl   Lbc_note
    b    Lkr_done
Lkr_new:
    mov  x0, #0                           // kSecRandomDefault
    mov  x1, #64
    ADRL x2, _g_bc_sk
    bl   _SecRandomCopyBytes
    cbnz w0, Lkr_fail
    ADRL x0, _g_bc_sk                     // saved on the Keychain queue, not here
    mov  x1, #64
    ADRL x2, _g_bc_kcw
    bl   _hex_enc
    bl   Lbc_kcq
    mov  x1, #0
    ADRL x2, Lbc_kc_write
    bl   _dispatch_async_f
    ADRL x0, Ls_bc_newkeys
    bl   Lbc_note0
Lkr_derive:
    ADRL x0, _g_bc_xpub
    ADRL x1, _g_bc_sk
    bl   _bc_x25519_base
    ADRL x0, _g_bc_sk
    add  x0, x0, #32
    ADRL x1, _g_bc_edpub
    bl   _bc_ed25519_pub
    ADRL x0, _g_bc_xpub
    mov  x1, #32
    ADRL x2, _g_bc_scr
    bl   _bc_sha256
    ADRL x8, _g_bc_scr
    ldr  x9, [x8]
    ADRL x8, _g_bc_myid
    str  x9, [x8]
    ADRL x8, _g_bc_keys
    mov  x9, #KS_READY
    str  x9, [x8]
    ADRL x8, _g_bc_ann_at
    str  xzr, [x8]
    bl   Lbc_pins_load
    bl   Lbc_name_load
    b    Lkr_done
Lkr_fail:
    ADRL x8, _g_bc_keys
    mov  x9, #KS_REFUSED
    str  x9, [x8]
    ADRL x0, Ls_bc_norandom
    bl   Lbc_note0
    b    Lkr_done
Lkr_off:
    bl   Lbc_keys_wipe
    LEAVE 0
Lkr_done:
    ADRL x0, _g_bc_kcbuf                  // ours, and the read is over: wipe it here
    mov  x1, #160
    bl   _bc_wipe
    ADRL x0, _g_bc_pinhex
    mov  x1, #14400
    bl   _bc_wipe
Lkr_stale:
    LEAVE 0

// void Lbc_keys_wipe(void) — our keys, and everyone we heard, out of memory; any read
//   still under way is ignored when it answers, and its buffer wiped after it
Lbc_keys_wipe:
    ENTER 0
    ADRL x8, _g_bc_keys
    str  xzr, [x8]
    ADRL x8, _g_bc_kcgen
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    ADRL x0, _g_bc_sk
    mov  x1, #64
    bl   _bc_wipe
    ADRL x0, _g_bc_myid
    mov  x1, #8
    bl   _bc_wipe
    ADRL x0, _g_bc_peers
    mov  x1, #BT_SIZE
    bl   _bc_wipe
    ADRL x0, _g_bc_types
    mov  x1, #2048
    bl   _bc_wipe
    ADRL x0, _g_bc_pins
    mov  x1, #(PN_SIZE & 0xffff)
    bl   _bc_wipe
    ADRL x0, _g_bc_name
    mov  x1, #32
    bl   _bc_wipe
    bl   Lbc_kcq
    mov  x1, #0
    ADRL x2, Lbc_kc_scrub
    bl   _dispatch_async_f
    LEAVE 0

// long Lbc_send_own(long type, const uint8 *payload, long n) -> links it went to: a packet
//   of ours (v1, TTL 7, signed), to every link
Lbc_send_own:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    b.ne 9f
    ADRL x22, _g_bc_mydp
    mov  x0, x22
    mov  x1, #DP_SIZE
    bl   _bc_wipe
    mov  x9, #1
    str  x9, [x22, #DP_VER]
    str  x19, [x22, #DP_TYPE]
    mov  x9, #7
    str  x9, [x22, #DP_TTL]
    bl   Lbc_wall_ms
    str  x0, [x22, #DP_TS]
    ADRL x9, _g_bc_myid
    str  x9, [x22, #DP_SENDER]
    str  x20, [x22, #DP_PAY]
    str  x21, [x22, #DP_PLEN]
    mov  x0, x22
    ADRL x1, _g_bc_sk
    add  x1, x1, #32
    ADRL x2, _g_bc_out
    mov  x3, #512
    bl   _bc_build
    cmp  x0, #0
    b.le 9f
    mov  x1, x0                           // sent without its padding: fits one write
    ADRL x0, _g_bc_out
    bl   _bc_frame_len
    cmp  x0, #0
    b.le 9f
    mov  x1, x0
    ADRL x0, _g_bc_out
    bl   _bc_broadcast
    mov  x19, x0
    ADRL x8, _g_bc_cnt
    ldr  x9, [x8, #C_SENT]
    add  x9, x9, #1
    str  x9, [x8, #C_SENT]
    mov  x0, x19
    LEAVE 0
9:  mov  x0, #0
    LEAVE 0

// void Lbc_announce(void) — our name and keys, to every link
Lbc_announce:
    ENTER 0
    ADRL x0, _g_bc_name
    bl   _strlen
    mov  x1, x0
    ADRL x0, _g_bc_name
    ADRL x2, _g_bc_xpub
    ADRL x3, _g_bc_edpub
    ADRL x4, _g_bc_pl
    bl   _bc_ann_make
    mov  x2, x0
    mov  x0, #0x01
    ADRL x1, _g_bc_pl
    bl   Lbc_send_own
    LEAVE 0

// void Lbc_sweep(void) — slots back from links that never came up (a phone that left, or
//   changed its private address, before we connected: CoreBluetooth never gives up on
//   its own) and from centrals that write but never subscribe. There are only BC_LINKS.
Lbc_sweep:
    ENTER 16                              // [96] a link of ours was freed
    str  xzr, [sp, #96]
    bl   _fm_now_ms
    mov  x19, x0
    mov  x20, #0
1:  cmp  x20, #BC_LINKS
    b.hs 8f
    LINK x21, x20
    ldr  x22, [x21, #L_KIND]
    cbz  x22, 5f
    ldr  x10, [x21, #L_SINCE]
    sub  x23, x19, x10                    // its age
    ldr  x11, [x21, #L_STATE]
    cmp  x11, #S_READY
    b.ne 2f
    ldr  x11, [x21, #L_PEER]              // up, but no real bitchat phone on it in 45 s
    cbnz x11, 3f
    mov  x12, #45000
    cmp  x23, x12
    b.hs 6f
    b    3f
2:  cmp  x22, #K_THEY_PERIPH              // ours, still coming up: 15 s
    b.ne 3f
    mov  x12, #15000
    cmp  x23, x12
    b.hs 6f
3:  cmp  x22, #K_THEY_CENTRAL             // theirs: 30 s to subscribe
    b.ne 5f
    ldr  x11, [x21, #L_SUB]
    cbnz x11, 5f
    mov  x12, #30000
    cmp  x23, x12
    b.lo 5f
6:  cmp  x22, #K_THEY_PERIPH
    cset x1, eq                           // ours: cancel the connection too
    cbz  x1, 7f
    str  x1, [sp, #96]
7:  mov  x0, x20
    bl   _bc_link_free
5:  add  x20, x20, #1
    b    1b
8:  ldr  x9, [sp, #96]                    // scan afresh: a phone found while we were full
    cbz  x9, 9f                           //   isn't reported again otherwise
    bl   _bc_scan
9:  LEAVE 16

// long Lbc_kind_count(long kind) -> links of that kind, and in x1 how many of them aren't up
//   yet (leaf)
Lbc_kind_count:
    mov  x13, #0
    mov  x14, #0
    mov  x15, #0
1:  cmp  x15, #BC_LINKS
    b.hs 3f
    LINK x16, x15
    ldr  x10, [x16, #L_KIND]
    cmp  x10, x0
    b.ne 2f
    add  x13, x13, #1
    ldr  x10, [x16, #L_STATE]
    cmp  x10, #S_READY
    cinc x14, x14, ne
2:  add  x15, x15, #1
    b    1b
3:  mov  x0, x13
    mov  x1, x14
    ret

// long Lbc_degree(void) -> the phones we're linked to: links that are up, a phone linked
//   both ways (it found us, we found it) counted once (leaf)
Lbc_degree:
    mov  x13, #0
    mov  x14, #0
1:  cmp  x14, #BC_LINKS
    b.hs 9f
    LINK x15, x14
    ldr  x10, [x15, #L_KIND]
    cbz  x10, 5f
    ldr  x10, [x15, #L_STATE]
    cmp  x10, #S_READY
    b.ne 5f
    ldr  x11, [x15, #L_PEER]
    cbz  x11, 4f
    mov  x12, #0                          // the same phone on an earlier link?
2:  cmp  x12, x14
    b.hs 4f
    LINK x16, x12
    ldr  x10, [x16, #L_KIND]
    cbz  x10, 3f
    ldr  x10, [x16, #L_PEER]
    cmp  x10, x11
    b.eq 5f
3:  add  x12, x12, #1
    b    2b
4:  add  x13, x13, #1
5:  add  x14, x14, #1
    b    1b
9:  mov  x0, x13
    ret

// void Lbc_ann_soon(void) — a new link: announce soon, but not again within 3 s of the last
//   one, however many links come and go (leaf)
Lbc_ann_soon:
    ADRL x8, _g_bc_ann_last
    ldr  x9, [x8]
    mov  x10, #3000
    add  x9, x9, x10
    ADRL x8, _g_bc_ann_at
    ldr  x10, [x8]
    cmp  x9, x10
    csel x10, x9, x10, lo
    str  x10, [x8]
    ret

// void _bc_tick(void) — once a second (scanner.s, ios_ui.s): free stuck links, forget
//   people gone quiet, and announce when it's time
.globl _bc_tick
_bc_tick:
    ENTER 0
    ADRL x8, _g_bc_cm                     // running at all?
    ldr  x9, [x8]
    cbz  x9, 9f
    bl   Lbc_sweep
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    b.ne 9f
    mov  x0, #0                           // pins changed: saved, every 10 s at most
    bl   Lbc_pins_save
    bl   Lbc_wall_ms
    mov  x1, x0
    ADRL x0, _g_bc_peers
    bl   _bc_peer_expire
    cbz  x0, 1f
    bl   _ui_lists_changed
1:  mov  x0, #0
    bl   _bc_link_count
    cbz  x0, 9f
    bl   _fm_now_ms
    mov  x19, x0
    ADRL x8, _g_bc_ann_at
    ldr  x9, [x8]
    cmp  x19, x9
    b.lo 9f
    ADRL x8, _g_bc_quiet
    ldr  x9, [x8]
    cbnz x9, 9f
    bl   Lbc_announce
    ADRL x8, _g_bc_ann_last
    str  x19, [x8]
    mov  w0, #4000                        // the next in 15 to 19 s, as bitchat does
    bl   _arc4random_uniform
    mov  w0, w0
    add  x9, x19, x0
    mov  x10, #15000
    add  x9, x9, x10
    ADRL x8, _g_bc_ann_at
    str  x9, [x8]
9:  LEAVE 0

// long Lbc_heard(void) -> 1 if the announce read into _g_bc_dp was taken. One straight from
//   the phone at the other end of the link (TTL 7) ties the link to that person: the first
//   one only, so a relay can't move it.
Lbc_heard:
    ENTER 0
    ADRL x8, _g_bc_keys                   // without our id we can't tell our own apart
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    b.ne 8f
    bl   Lbc_wall_ms
    mov  x1, x0
    ADRL x0, _g_bc_peers
    ADRL x2, _g_bc_myid
    ADRL x3, _g_bc_dp
    ADRL x4, _g_bc_scr
    mov  x5, #4096
    ADRL x6, _g_bc_pins
    bl   _bc_peer_heard
    ADRL x8, _g_bc_cnt
    tbnz x0, #63, 2f
    mov  x19, x0
    mov  x20, x1
    ldr  x9, [x8, #C_ANN_OK]
    add  x9, x9, #1
    str  x9, [x8, #C_ANN_OK]
    ADRL x8, _g_bc_dp                     // straight from the link's own phone?
    ldr  x9, [x8, #DP_TTL]
    cmp  x9, #7
    b.lo 1f
    ADRL x8, _g_bc_rxlink
    ldr  x9, [x8]
    LINK x21, x9
    ldr  x10, [x21, #L_PEER]
    cbnz x10, 1f
    ADRL x8, _g_bc_peers
    add  x8, x8, x19, lsl #BT_SHIFT
    ldr  x10, [x8, #BT_ID]
    str  x10, [x21, #L_PEER]
1:  cbz  x20, 7f
    ADRL x8, _g_bc_peers                  // someone new: say so (a few a minute), and warn
    add  x0, x8, x19, lsl #BT_SHIFT       //   about a name an asmmesh person also has
    bl   Lbc_say_person
    bl   _ui_lists_changed
7:  mov  x0, #1
    LEAVE 0
2:  cmn  x0, #3                           // our own, come back round: not a refusal
    b.eq 8f
    ldr  x9, [x8, #C_ANN_BAD]
    add  x9, x9, #1
    str  x9, [x8, #C_ANN_BAD]
8:  mov  x0, #0
    LEAVE 0

// long Lbc_left(void) -> 1 if the leave read into _g_bc_dp was taken
Lbc_left:
    ENTER 0
    bl   Lbc_wall_ms
    mov  x1, x0
    ADRL x0, _g_bc_peers
    ADRL x2, _g_bc_dp
    ADRL x3, _g_bc_scr
    mov  x4, #4096
    ADRL x5, _g_bc_pins
    bl   _bc_peer_leave
    tbnz x0, #63, 1f
    bl   _ui_lists_changed
    mov  x0, #1
    LEAVE 0
1:  mov  x0, #0
    LEAVE 0

// char *_bc_person_fp(const uint8 *e, char *buf /*20*/) -> "1a2b 3c4d 5e6f 7a8b": their
//   peer id, which bitchat shows at the start of their fingerprint
.globl _bc_person_fp
_bc_person_fp:
    ENTER 32                              // [96] hex
    mov  x19, x1
    add  x0, x0, #BT_ID
    mov  x1, #8
    add  x2, sp, #96
    bl   _hex_enc
    mov  x9, #0                           // groups of four
    mov  x10, #0
1:  add  x12, sp, #96
    ldrb w11, [x12, x9]
    strb w11, [x19, x10]
    add  x9, x9, #1
    add  x10, x10, #1
    cmp  x9, #16
    b.hs 2f
    tst  x9, #3
    b.ne 1b
    mov  w11, #' '
    strb w11, [x19, x10]
    add  x10, x10, #1
    b    1b
2:  strb wzr, [x19, x10]
    mov  x0, x19
    LEAVE 32

// long _bc_person_clash(const uint8 *e) -> 1 if an asmmesh person has a name that looks the
//   same (bc_peer.s _bc_name_same: look-alike letters, invisible characters, case)
.globl _bc_person_clash
_bc_person_clash:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
1:  ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 2f
    ADRL x8, _g_nodes
    add  x0, x8, x20, lsl #NODE_SHIFT
    bl   _node_name
    mov  x21, x0
    bl   _strlen
    mov  x3, x0
    mov  x2, x21
    add  x0, x19, #BT_NICK
    ldr  x1, [x19, #BT_NLEN]
    bl   _bc_name_same
    add  x20, x20, #1
    cbz  x0, 1b
    mov  x0, #1
    LEAVE 0
2:  mov  x0, #0
    LEAVE 0

// char *_bc_person_line(const uint8 *e, char *buf, long cap) -> "bitchat · 1a2b 3c4d 5e6f
//   7a8b · nearby" (or "· 2 hops"), with a warning first if an asmmesh person has the name
.globl _bc_person_line
_bc_person_line:
    ENTER 64                              // [96] fingerprint [128] where
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x1, sp, #96
    bl   _bc_person_fp
    ADRL x22, Ls_bc_via                   // nearby only if a link of ours is tied to them
    ldr  x10, [x19, #BT_ID]               //   (the TTL isn't signed: a relay could fake hops)
    mov  x9, #0
2:  cmp  x9, #BC_LINKS
    b.hs 1f
    LINK x11, x9
    ldr  x12, [x11, #L_KIND]
    cbz  x12, 3f
    ldr  x12, [x11, #L_PEER]
    cmp  x12, x10
    b.ne 3f
    ADRL x22, Ls_bc_near
    b    1f
3:  add  x9, x9, #1
    b    2b
1:  mov  x0, x19
    bl   _bc_person_clash
    ADRL x2, Lf_bc_line
    ADRL x10, Lf_bc_line_clash
    cmp  x0, #0
    csel x2, x10, x2, ne
    add  x9, sp, #96
    str  x9, [sp]
    str  x22, [sp, #8]
    mov  x0, x20
    mov  x1, x21
    bl   _snprintf
    mov  x0, x20
    LEAVE 64

// void Lbc_say_person(const uint8 *e) — "· bitchat: Anna is around (bitchat · ...)", 3 a
//   minute at most (new people cost nothing to make: they mustn't bury Home)
Lbc_say_person:
    ENTER 128                             // [96] their line
    mov  x19, x0
    bl   _fm_now_ms
    mov  x1, x0
    ADRL x0, _g_bc_hl
    mov  x2, #3
    mov  x3, #60000
    bl   _bc_rate_ok
    cbz  x0, 9f
    add  x1, sp, #96
    mov  x2, #128
    bl   _bc_person_line
    add  x9, x19, #BT_NICK
    str  x9, [sp]
    add  x9, sp, #96
    str  x9, [sp, #8]
    ADRL x0, Lf_bc_new
    add  x1, x19, #BT_NICK
    add  x2, sp, #96
    bl   Lbc_note
9:  LEAVE 128

// long _bc_people_n(void) -> bitchat people to show (0 with the switch off)
.globl _bc_people_n
_bc_people_n:
    ENTER 0
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    mov  x0, #0
    cmp  x9, #KS_READY
    b.ne 1f
    ADRL x0, _g_bc_peers
    bl   _bc_peer_count
1:  LEAVE 0

// uint8 *_bc_person(long k) -> the k-th bitchat person, or 0
.globl _bc_person
_bc_person:
    ENTER 0
    mov  x19, x0
    bl   _bc_people_n
    cmp  x19, x0
    b.hs 1f
    mov  x1, x19
    ADRL x0, _g_bc_peers
    bl   _bc_peer_nth
    LEAVE 0
1:  mov  x0, #0
    LEAVE 0

// for the iPhone's People tab (Mesh.swift): count, name, second line
.globl _am_bc_count
_am_bc_count:
    b    _bc_people_n
.globl _am_bc_nick
_am_bc_nick:                              // const char *am_bc_nick(long k)
    ENTER 0
    bl   _bc_person
    cbz  x0, 1f
    add  x0, x0, #BT_NICK
    LEAVE 0
1:  ADRL x0, Ls_bc_empty
    LEAVE 0
.globl _am_bc_line
_am_bc_line:                              // char *am_bc_line(long k, char *buf /*128*/)
    ENTER 0
    mov  x19, x1
    strb wzr, [x19]
    bl   _bc_person
    cbz  x0, 1f
    mov  x1, x19
    mov  x2, #128
    bl   _bc_person_line
1:  mov  x0, x19
    LEAVE 0

// ---------------------------------------------------------------------------
// bytes out

// long _bc_send(long i, const uint8 *p, long n) -> 1 sent or queued, 0 dropped,
//   -1 too big for this link (the caller sends fragments instead)
.globl _bc_send
_bc_send:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    LINK x22, x19
    ldr  x9, [x22, #L_STATE]
    cmp  x9, #S_READY
    b.ne Lsd_no
    ldr  x9, [x22, #L_MAX]
    cmp  x21, x9
    b.hi Lsd_big
    add  x0, x22, #L_Q
    mov  x1, x20
    mov  x2, x21
    bl   _bc_q_push
    cmp  x0, #1
    b.ne Lsd_no
    mov  x0, x19
    bl   _bc_flush
    mov  x0, #1
    LEAVE 0
Lsd_big:
    mov  x0, #-1
    LEAVE 0
Lsd_no:
    mov  x0, #0
    LEAVE 0

// long _bc_broadcast(const uint8 *p, long n) -> links it went to
.globl _bc_broadcast
_bc_broadcast:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
    mov  x22, #0
1:  cmp  x21, #BC_LINKS
    b.hs 2f
    mov  x0, x21
    mov  x1, x19
    mov  x2, x20
    bl   _bc_send
    cmp  x0, #1
    cinc x22, x22, eq
    add  x21, x21, #1
    b    1b
2:  mov  x0, x22
    LEAVE 0

// void _bc_flush(long i) — send what the radio will take now; the rest waits for
//   "ready" from CoreBluetooth
_bc_flush:
    ENTER 16                              // [96] centrals array
    mov  x19, x0
    LINK x20, x19
Lfl2_loop:
    add  x0, x20, #L_Q
    bl   _bc_q_front
    cbz  x0, Lfl2_done
    mov  x21, x0
    mov  x22, x1
    ldr  x9, [x20, #L_KIND]
    cmp  x9, #K_THEY_PERIPH
    b.ne Lfl2_notify
    ldr  x0, [x20, #L_OBJ]                // we write: without response, when it can take one
    MSG0 Ls_canSendWWR
    tst  w0, #0xff
    b.eq Lfl2_done
    CLS  Ls_NSData
    mov  x2, x21
    mov  x3, x22
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    ldr  x0, [x20, #L_OBJ]
    ldr  x3, [x20, #L_CHR]
    mov  x4, #1                           // CBCharacteristicWriteWithoutResponse
    MSG3 Ls_writeValue
    b    Lfl2_sent
Lfl2_notify:
    ADRL x8, _g_bc_chr                    // they subscribed to us: notify just them
    ldr  x23, [x8]
    cbz  x23, Lfl2_done
    ldr  x0, [x20, #L_OBJ]
    bl   _bc_array1
    mov  x24, x0
    CLS  Ls_NSData
    mov  x2, x21
    mov  x3, x22
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    ADRL x8, _g_bc_pm
    ldr  x0, [x8]
    mov  x3, x23
    mov  x4, x24
    MSG3 Ls_updateValue
    tst  w0, #0xff
    b.eq Lfl2_done                        // its queue is full: peripheralManagerIsReady…
Lfl2_sent:
    ldr  x9, [x20, #L_OUT]
    add  x9, x9, #1
    str  x9, [x20, #L_OUT]
    add  x0, x20, #L_Q
    bl   _bc_q_pop
    b    Lfl2_loop
Lfl2_done:
    LEAVE 16

// id _bc_array1(id obj) — [NSArray arrayWithObject:obj]
_bc_array1:
    ENTER 0
    mov  x19, x0
    CLS  Ls_NSArray
    mov  x2, x19
    MSG1 Ls_arrayWithObject
    LEAVE 0

// ===========================================================================
// central role

// void _bc_scan(void) — (re)start scanning for bitchat's service only
_bc_scan:
    ENTER 0
    ADRL x8, _g_bc_cm
    ldr  x19, [x8]
    cbz  x19, 1f
    mov  x0, x19
    MSG0 Ls_state
    cmp  x0, #CB_POWERED_ON
    b.ne 1f
    mov  x0, x19
    MSG0 Ls_stopScan
    ADRL x8, _g_bc_svc
    ldr  x0, [x8]
    bl   _bc_array1
    mov  x2, x0
    mov  x0, x19
    mov  x3, #0
    MSG2 Ls_scanForPeripherals
1:  LEAVE 0

// - (void)centralManagerDidUpdateState:cm
_bc_cm_state:
    ENTER 0
    mov  x0, x2
    MSG0 Ls_state
    mov  x19, x0
    mov  x0, #K_THEY_PERIPH
    bl   _bc_links_drop
    cmp  x19, #CB_POWERED_ON
    b.ne 1f
    bl   _bc_scan
1:  LEAVE 0

// - (void)centralManager:cm didDiscoverPeripheral:p advertisementData:ad RSSI:rssi
_bc_cm_discover:
    ENTER 0
    mov  x19, x2
    mov  x20, x3
    mov  x0, x20
    bl   _bc_link_find
    tbz  x0, #63, 1f                      // already linked
    mov  x0, #K_THEY_PERIPH               // at most L_PER_KIND of ours, L_PENDING coming up:
    bl   Lbc_kind_count                   //   strangers advertising bitchat's service can't
    cmp  x0, #L_PER_KIND                  //   take every slot
    b.hs 1f
    cmp  x1, #L_PENDING
    b.hs 1f
    mov  x0, x20
    mov  x1, #K_THEY_PERIPH
    mov  x2, #S_CONNECTING
    bl   _bc_link_new
    tbnz x0, #63, 1f                      // table full
    mov  x0, x19
    mov  x2, x20
    mov  x3, #0
    MSG2 Ls_connectPeripheral
1:  LEAVE 0

// - (void)centralManager:cm didConnectPeripheral:p
_bc_cm_connect:
    ENTER 0
    mov  x19, x0
    mov  x20, x3
    mov  x0, x20
    bl   _bc_link_find
    tbnz x0, #63, Lcn_cancel
    LINK x21, x0
    mov  x9, #S_DISCOVERING
    str  x9, [x21, #L_STATE]
    mov  x0, x20
    mov  x2, x19
    MSG1 Ls_setDelegate
    ADRL x8, _g_bc_svc
    ldr  x0, [x8]
    bl   _bc_array1
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_discoverServices
    LEAVE 0
Lcn_cancel:
    ADRL x8, _g_bc_cm
    ldr  x0, [x8]
    mov  x2, x20
    MSG1 Ls_cancelPeripheralConnection
    LEAVE 0

// - (void)centralManager:cm didFailToConnectPeripheral:p error:e  (and didDisconnect…)
_bc_cm_lost:
    ENTER 0
    mov  x0, x3
    bl   _bc_link_find
    tbnz x0, #63, 1f
    mov  x1, #0
    bl   _bc_link_free
1:  bl   _bc_scan                         // so it is found again when it is back
    LEAVE 0

// - (void)peripheral:p didDiscoverServices:error
_bc_p_services:
    ENTER 0
    mov  x19, x2
    cbnz x3, Lps_drop
    mov  x0, x19
    bl   _bc_link_find
    tbnz x0, #63, Lps_drop
    mov  x0, x19
    MSG0 Ls_services
    MSG0 Ls_firstObject                   // we asked for bitchat's service only
    cbz  x0, Lps_drop
    mov  x20, x0
    ADRL x8, _g_bc_chu
    ldr  x0, [x8]
    bl   _bc_array1
    mov  x2, x0
    mov  x0, x19
    mov  x3, x20
    MSG2 Ls_discoverCharacteristics
    LEAVE 0
Lps_drop:
    ADRL x8, _g_bc_cm
    ldr  x0, [x8]
    mov  x2, x19
    MSG1 Ls_cancelPeripheralConnection
    LEAVE 0

// - (void)peripheral:p didDiscoverCharacteristicsForService:s error:e
_bc_p_chars:
    ENTER 0
    mov  x19, x2
    mov  x20, x3
    cbnz x4, Lpc_drop
    mov  x0, x19
    bl   _bc_link_find
    tbnz x0, #63, Lpc_drop
    mov  x21, x0
    mov  x0, x20
    MSG0 Ls_characteristics
    mov  x22, x0
    MSG0 Ls_count
    mov  x23, x0
Lpc_loop:
    cbz  x23, Lpc_drop                    // not there: not a bitchat we can talk to
    sub  x23, x23, #1
    mov  x0, x22
    mov  x2, x23
    MSG1 Ls_objectAtIndex
    mov  x24, x0
    MSG0 Ls_UUID
    ADRL x8, _g_bc_chu
    ldr  x2, [x8]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.eq Lpc_loop
    mov  x0, x24
    MSG0 Ls_retain
    LINK x20, x21
    str  x0, [x20, #L_CHR]
    mov  x0, x19                          // what one write without response can carry
    mov  x2, #1
    MSG1 Ls_maxWriteLen
    cmp  x0, #BC_WRITE_MAX
    mov  x9, #BC_WRITE_MAX
    csel x0, x9, x0, hi
    str  x0, [x20, #L_MAX]
    mov  x9, #S_READY
    str  x9, [x20, #L_STATE]
    bl   Lbc_ann_soon                     // a new link: announce soon
    mov  x0, x19                          // and hear what it sends
    mov  x2, #1
    mov  x3, x24
    MSG2 Ls_setNotify
    mov  x0, x21
    bl   _bc_flush
    LEAVE 0
Lpc_drop:
    ADRL x8, _g_bc_cm
    ldr  x0, [x8]
    mov  x2, x19
    MSG1 Ls_cancelPeripheralConnection
    LEAVE 0

// - (void)peripheral:p didUpdateValueForCharacteristic:c error:e — a notification
_bc_p_value:
    ENTER 0
    mov  x19, x2
    mov  x20, x3
    cbnz x4, 1f
    mov  x0, x19
    bl   _bc_link_find
    tbnz x0, #63, 1f
    mov  x21, x0
    LINK x22, x21
    ldr  x9, [x22, #L_STATE]
    cmp  x9, #S_READY
    b.ne 1f
    mov  x0, x20
    MSG0 Ls_value
    cbz  x0, 1f
    mov  x23, x0
    MSG0 Ls_length
    mov  x24, x0
    mov  x0, x23
    MSG0 Ls_bytes
    mov  x2, x0
    mov  x0, x21
    mov  x1, #0
    mov  x3, x24
    bl   _bc_rx
1:  LEAVE 0

// - (void)peripheral:p didModifyServices:invalidated — it restarted: drop and refind
_bc_p_modify:
    ENTER 0
    ADRL x8, _g_bc_cm
    ldr  x0, [x8]
    cbz  x0, 1f
    MSG1 Ls_cancelPeripheralConnection    // x2 is p already
1:  LEAVE 0

// - (void)peripheralIsReadyToSendWriteWithoutResponse:p
_bc_p_ready:
    ENTER 0
    mov  x0, x2
    bl   _bc_link_find
    tbnz x0, #63, 1f
    bl   _bc_flush
1:  LEAVE 0

// ===========================================================================
// peripheral role

// - (void)peripheralManagerDidUpdateState:pm — powered on: publish the service
_bc_pm_state:
    ENTER 0
    mov  x19, x2
    mov  x0, #K_THEY_CENTRAL
    bl   _bc_links_drop
    mov  x0, x19
    MSG0 Ls_state
    cmp  x0, #CB_POWERED_ON
    b.ne Lpm_done
    mov  x0, x19
    MSG0 Ls_removeAllServices
    ADRL x8, _g_bc_chr
    ldr  x0, [x8]
    str  xzr, [x8]
    cbz  x0, 1f
    MSG0 Ls_release
1:  CLS  Ls_CBMutableCharacteristic
    MSG0 Ls_alloc
    ADRL x8, _g_bc_chu
    ldr  x2, [x8]
    mov  x3, #0x1E                        // read | write without response | write | notify
    mov  x4, #0
    mov  x5, #3                           // readable | writeable
    MSG4 Ls_initCharacteristic
    ADRL x8, _g_bc_chr
    str  x0, [x8]
    mov  x20, x0
    CLS  Ls_CBMutableService
    MSG0 Ls_alloc
    ADRL x8, _g_bc_svc
    ldr  x2, [x8]
    mov  x3, #1
    MSG2 Ls_initWithTypePrimary
    mov  x21, x0
    mov  x0, x20
    bl   _bc_array1
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setCharacteristics
    mov  x0, x19
    mov  x2, x21
    MSG1 Ls_addService
    mov  x0, x21
    MSG0 Ls_release
Lpm_done:
    LEAVE 0

// - (void)peripheralManager:pm didAddService:s error:e
_bc_pm_added:
    ENTER 0
    cbnz x4, 1f
    bl   _bc_advertise
1:  LEAVE 0

// void _bc_advertise(void) — advertise bitchat's service if "bitchat advertise on"
.globl _bc_advertise
_bc_advertise:
    ENTER 0
    ADRL x8, _g_bc_pm
    ldr  x19, [x8]
    cbz  x19, 2f
    mov  x0, x19
    MSG0 Ls_stopAdvertising
    ADRL x8, _g_bc_adv
    ldr  x9, [x8]
    cbz  x9, 2f
    mov  x0, x19
    MSG0 Ls_state
    cmp  x0, #CB_POWERED_ON
    b.ne 2f
    ADRL x8, _g_bc_svc
    ldr  x0, [x8]
    bl   _bc_array1
    mov  x20, x0
    LDGOT x8, _CBAdvertisementDataServiceUUIDsKey
    ldr  x21, [x8]
    CLS  Ls_NSDictionary
    mov  x2, x20
    mov  x3, x21
    MSG2 Ls_dictionaryWithObject
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_startAdvertising
2:  LEAVE 0

// x0 = the link for central (a CBCentral), made if new; -1 if the table is full
_bc_central_link:
    ENTER 0
    mov  x19, x0
    bl   _bc_link_find
    tbz  x0, #63, 1f
    mov  x0, #K_THEY_CENTRAL              // at most L_PER_KIND of theirs
    bl   Lbc_kind_count
    cmp  x0, #L_PER_KIND
    b.hs 2f
    mov  x0, x19
    mov  x1, #K_THEY_CENTRAL
    mov  x2, #S_READY
    bl   _bc_link_new
    tbnz x0, #63, 1f
    mov  x20, x0
    bl   Lbc_ann_soon                     // a new link: announce soon
    mov  x0, x19                          // what one notification can carry
    MSG0 Ls_maxUpdateLen
    cmp  x0, #BC_WRITE_MAX
    mov  x9, #BC_WRITE_MAX
    csel x0, x9, x0, hi
    LINK x21, x20
    str  x0, [x21, #L_MAX]
    mov  x0, x20
1:  LEAVE 0
2:  mov  x0, #-1
    LEAVE 0

// - (void)peripheralManager:pm central:c didSubscribeToCharacteristic:ch
_bc_pm_sub:
    ENTER 0
    mov  x0, x3
    bl   _bc_central_link
    tbnz x0, #63, 1f
    mov  x19, x0
    LINK x20, x19                         // a real link: it keeps its slot
    mov  x9, #1
    str  x9, [x20, #L_SUB]
    mov  x0, x19
    bl   _bc_flush
1:  LEAVE 0

// - (void)peripheralManager:pm central:c didUnsubscribeFromCharacteristic:ch
_bc_pm_unsub:
    ENTER 0
    mov  x0, x3
    bl   _bc_link_find
    tbnz x0, #63, 1f
    mov  x1, #0
    bl   _bc_link_free
1:  LEAVE 0

// - (void)peripheralManager:pm didReceiveWriteRequests:reqs — a write, maybe in pieces
_bc_pm_writes:
    ENTER 32                              // [96] the request to answer [104] value [112] offset [120] length
    mov  x19, x2
    mov  x20, x3
    mov  x0, x20
    MSG0 Ls_firstObject
    str  x0, [sp, #96]
    mov  x0, x20
    MSG0 Ls_count
    mov  x21, x0
    mov  x22, #0
Lpw_loop:
    cmp  x22, x21
    b.hs Lpw_answer
    mov  x0, x20
    mov  x2, x22
    MSG1 Ls_objectAtIndex
    mov  x23, x0
    MSG0 Ls_central
    bl   _bc_central_link
    tbnz x0, #63, Lpw_next
    mov  x24, x0
    mov  x0, x23
    MSG0 Ls_value
    cbz  x0, Lpw_next
    str  x0, [sp, #104]
    mov  x0, x23
    MSG0 Ls_offset
    str  x0, [sp, #112]
    ldr  x0, [sp, #104]
    MSG0 Ls_length
    str  x0, [sp, #120]
    ldr  x0, [sp, #104]
    MSG0 Ls_bytes
    mov  x2, x0
    mov  x0, x24
    ldr  x1, [sp, #112]
    ldr  x3, [sp, #120]
    bl   _bc_rx
Lpw_next:
    add  x22, x22, #1
    b    Lpw_loop
Lpw_answer:
    ldr  x2, [sp, #96]
    cbz  x2, 1f
    mov  x0, x19
    mov  x3, #0                           // CBATTErrorSuccess
    MSG2 Ls_respondToRequest
1:  LEAVE 32

// - (void)peripheralManager:pm didReceiveReadRequest:req — nothing to read: empty
_bc_pm_read:
    ENTER 0
    mov  x19, x2
    mov  x20, x3
    CLS  Ls_NSData
    MSG0 Ls_data
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_setValue
    mov  x0, x19
    mov  x2, x20
    mov  x3, #0
    MSG2 Ls_respondToRequest
    LEAVE 0

// - (void)peripheralManagerIsReadyToUpdateSubscribers:pm — room for notifications again
_bc_pm_ready:
    ENTER 0
    mov  x19, #0
1:  cmp  x19, #BC_LINKS
    b.hs 3f
    LINK x20, x19
    ldr  x9, [x20, #L_KIND]
    cmp  x9, #K_THEY_CENTRAL
    b.ne 2f
    mov  x0, x19
    bl   _bc_flush
2:  add  x19, x19, #1
    b    1b
3:  LEAVE 0

// ===========================================================================
// Home: "bitchat", "bitchat advertise on / off"

// "bitchat" / "bitchat status" — what the link has heard (counts only)
.globl _h_bitchat
_h_bitchat:
    ENTER 0
    ADRL x8, _g_remote_active             // the wall: what bitchat looks like from here never
    ldr  x9, [x8]                         //   goes on asmmesh's mesh (it would link this Mac's
    cbnz x9, Lhb_here                     //   two identities, and carry strangers' names)
    mov  x0, #SVC_BITCHAT
    bl   _svc_gate
    cbz  x0, 1f
    ADRL x19, _g_bc_cnt
    mov  x0, #0
    bl   _bc_link_count
    mov  x20, x0
    mov  x0, #K_THEY_PERIPH
    bl   _bc_link_count
    mov  x2, x0
    mov  x0, #K_THEY_CENTRAL
    bl   _bc_link_count
    mov  x3, x0
    mov  x1, x20
    ADRL x0, Lf_links
    bl   _home_say
    ldr  x1, [x19, #C_FRAMES]
    ldr  x2, [x19, #C_ANNOUNCE]
    ldr  x3, [x19, #C_MESSAGE]
    ADRL x0, Lf_heard
    bl   _home_say
    ldr  x1, [x19, #C_PRIVATE]
    ldr  x2, [x19, #C_FRAGMENT]
    ldr  x3, [x19, #C_JOINED]
    ADRL x0, Lf_heard2
    bl   _home_say
    ldr  x1, [x19, #C_OTHER]
    ldr  x2, [x19, #C_REFUSED]
    ldr  x3, [x19, #C_LINKS]
    ADRL x0, Lf_heard3
    bl   _home_say
    bl   Lbc_kinds
    bl   Lbc_say_me
    ADRL x0, Ls_adv_off
    ADRL x8, _g_bc_adv
    ldr  x9, [x8]
    ADRL x10, Ls_adv_on
    cmp  x9, #0
    csel x0, x10, x0, ne
    bl   _home_say0
    ADRL x0, Ls_wall
    bl   _home_say0
1:  LEAVE 0
Lhb_here:
    ADRL x0, Ls_bc_local
    bl   _home_say0
    LEAVE 0

// void Lbc_say_me(void) — who this Mac is on bitchat, and who it has heard
Lbc_say_me:
    ENTER 32                              // [96] fingerprint
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    b.ne 1f
    ADRL x0, _g_bc_myid                   // (_bc_person_fp reads the id at BT_ID, 0)
    add  x1, sp, #96
    bl   _bc_person_fp
    ADRL x8, _g_bc_cnt
    ADRL x0, Lf_bc_me
    ADRL x1, _g_bc_name
    add  x2, sp, #96
    ldr  x3, [x8, #C_SENT]
    bl   _home_say
    ADRL x8, _g_bc_quiet
    ldr  x9, [x8]
    cbz  x9, 2f
    ADRL x0, Ls_bc_ann_off
    bl   _home_say0
2:
    bl   _bc_people_n
    mov  x1, x0
    ADRL x8, _g_bc_cnt
    ldr  x2, [x8, #C_ANN_OK]
    ldr  x3, [x8, #C_ANN_BAD]
    ADRL x0, Lf_bc_people_n
    bl   _home_say
    ADRL x8, _g_bc_cnt
    ldr  x1, [x8, #C_SHOWN]
    ldr  x2, [x8, #C_SAID]
    ldr  x3, [x8, #C_RELAYED]
    ADRL x0, Lf_bc_chat_n
    bl   _home_say
    ADRL x8, _g_bc_cnt
    ldr  x1, [x8, #C_LIMITED]
    cbz  x1, 2f
    ADRL x0, Lf_bc_limited
    bl   _home_say
2:
    LEAVE 32
1:  ADRL x0, Ls_bc_nokeys
    ADRL x10, Ls_bc_loading
    cmp  x9, #KS_LOADING
    csel x0, x10, x0, eq
    bl   _home_say0
    LEAVE 32

// "bitchat announce on" (0) / "off" (1) — for testing: listen without announcing
.globl _h_bitchat_quiet
_h_bitchat_quiet:
    ENTER 0
    ADRL x8, _g_remote_active
    ldr  x9, [x8]
    cbnz x9, 1f
    ADRL x8, _g_bc_quiet
    str  x0, [x8]
    ADRL x8, _g_bc_ann_at
    str  xzr, [x8]
    ADRL x1, Ls_bc_ann_on
    ADRL x2, Ls_bc_ann_off
    cmp  x0, #0
    csel x0, x2, x1, ne
    bl   _home_say0
    LEAVE 0
1:  ADRL x0, Ls_only_here
    bl   _home_say0
    LEAVE 0

// "bitchat name <name>" — this Mac's name on bitchat (at most BT_NICK_SEND bytes, cleaned
//   like any bitchat name); "bitchat name" alone says it. This Mac only, never the mesh.
.globl _h_bitchat_name
_h_bitchat_name:
    ENTER 48                              // [96] the new name
    mov  x19, x2
    ADRL x8, _g_remote_active
    ldr  x9, [x8]
    cbnz x9, 8f
    cbz  x19, 5f
1:  ldrb w9, [x19]                        // no leading spaces
    cmp  w9, #' '
    b.ne 2f
    add  x19, x19, #1
    b    1b
2:  cbz  w9, 5f
    mov  x0, x19
    bl   _strlen
    mov  x1, x0
    mov  x0, x19
    mov  x2, #BT_NICK_SEND
    bl   _bc_utf8_cut
    mov  x20, x0
    add  x0, sp, #96
    mov  x1, x19
    mov  x2, x20
    bl   _bc_text_clean
    add  x9, sp, #96
    strb wzr, [x9, x20]
    ADRL x0, Ls_bc_kname
    add  x1, sp, #96
    bl   _pref_set
    ADRL x8, _g_bc_keys                   // in use now if bitchat is on
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    b.ne 3f
    ADRL x0, _g_bc_name
    add  x1, sp, #96
    mov  x2, #32
    bl   _strlcpy
    bl   Lbc_ann_soon
3:  ADRL x0, Lf_bc_named
    add  x1, sp, #96
    bl   _home_say
    LEAVE 48
5:  ADRL x8, _g_bc_name                   // just the name, please
    ldrb w9, [x8]
    cbz  w9, 6f
    ADRL x0, Lf_bc_name_is
    ADRL x1, _g_bc_name
    bl   _home_say
    LEAVE 48
6:  ADRL x0, Ls_bc_name_off
    bl   _home_say0
    LEAVE 48
8:  ADRL x0, Ls_bc_local
    bl   _home_say0
    LEAVE 48

// "bitchat people" — everyone heard, with their fingerprint
.globl _h_bitchat_people
_h_bitchat_people:
    ENTER 144                             // [96] a line
    ADRL x8, _g_remote_active             // (not over the mesh: see _h_bitchat)
    ldr  x9, [x8]
    cbnz x9, 4f
    mov  x0, #SVC_BITCHAT
    bl   _svc_gate
    cbz  x0, 3f
    bl   _bc_people_n
    mov  x20, x0
    cbz  x20, 2f
    ADRL x0, Ls_bc_people_hdr
    bl   _home_say0
    mov  x19, #0
1:  cmp  x19, x20
    b.hs 3f
    mov  x0, x19
    bl   _bc_person
    cbz  x0, 3f
    mov  x21, x0
    add  x1, sp, #96
    mov  x2, #128
    bl   _bc_person_line
    ADRL x0, Lf_bc_person
    add  x1, x21, #BT_NICK
    add  x2, sp, #96
    bl   _home_say
    add  x19, x19, #1
    b    1b
2:  ADRL x0, Ls_bc_nobody
    bl   _home_say0
3:  LEAVE 144
4:  ADRL x0, Ls_bc_local
    bl   _home_say0
    LEAVE 144

// "bitchat forget" — delete our bitchat keys and everyone heard (this Mac only). With
//   the switch on, new keys are made: to bitchat phones this Mac is then someone new.
.globl _h_bitchat_forget
_h_bitchat_forget:
    ENTER 0
    ADRL x8, _g_remote_active
    ldr  x9, [x8]
    cbnz x9, 2f
    mov  x0, #0x03                        // say goodbye with the old keys first
    mov  x1, #0
    mov  x2, #0
    bl   Lbc_send_own
    bl   Lbc_kcq                          // deleted on the Keychain queue, before any new read
    mov  x1, #0
    ADRL x2, Lbc_kc_delete
    bl   _dispatch_async_f
    ADRL x8, _g_bc_pins                   // nothing of them is saved again
    str  xzr, [x8, #PN_DIRTY]
    bl   Lbc_keys_wipe
    ADRL x0, _g_bc_cnt
    mov  x1, #C_SIZE
    bl   _bc_wipe
    ADRL x0, _g_bc_dd                     // what was heard: the duplicate filter, fragments,
    mov  x1, #(DD_SIZE & 0xffff)          //   and the bitchat room's transcript
    bl   _bc_wipe
    ADRL x0, _g_bc_fa
    mov  x1, #(FA_SIZE & 0xffff)
    movk x1, #(FA_SIZE >> 16), lsl #16
    bl   _bc_wipe
    ADRL x0, _g_bc_joined
    mov  x1, #FA_BYTES
    bl   _bc_wipe
    bl   Lbc_room_off
    mov  x0, #SVC_BITCHAT
    bl   _svc_on
    cbz  x0, 3f
    bl   Lbc_room_on
3:  bl   _ui_lists_changed
    ADRL x0, Ls_bc_forgot
    bl   _home_say0
    mov  x0, #SVC_BITCHAT
    bl   _svc_on
    cbz  x0, 1f
    bl   Lbc_keys_load
1:  LEAVE 0
2:  ADRL x0, Ls_only_here
    bl   _home_say0
    LEAVE 0

// void Lbc_kinds(void) — "· other kinds: 3 × sync request (0x21), ..." for the types the
//   lines above don't name
Lbc_kinds:
    ENTER 272                             // [96] the line
    add  x19, sp, #96
    strb wzr, [x19]
    mov  x20, #0                          // its length
    mov  x21, #0                          // type
    mov  x22, #0                          // how many listed
1:  cmp  x21, #256
    b.hs 4f
    cmp  x21, #0x01                       // the ones already counted above
    b.eq 3f
    cmp  x21, #0x02
    b.eq 3f
    cmp  x21, #0x10
    b.eq 3f
    cmp  x21, #0x11
    b.eq 3f
    cmp  x21, #0x20
    b.eq 3f
    ADRL x8, _g_bc_types
    ldr  x23, [x8, x21, lsl #3]
    cbz  x23, 3f
    ADRL x9, Lbc_kind_tab                 // its name
2:  ldp  x10, x11, [x9], #16
    cmp  x10, #0x100
    b.eq 21f
    cmp  x10, x21
    b.ne 2b
21: ADRL x10, Ls_kinds_first
    ADRL x12, Ls_kinds_sep
    cmp  x22, #0
    csel x10, x10, x12, eq
    stp  x10, x23, [sp]
    stp  x11, x21, [sp, #16]
    add  x0, x19, x20
    mov  x1, #256
    sub  x1, x1, x20
    ADRL x2, Lf_kind
    bl   _snprintf
    add  x20, x20, x0
    add  x22, x22, #1
    cmp  x20, #255
    b.hs 4f
3:  add  x21, x21, #1
    b    1b
4:  cbz  x22, 5f
    mov  x0, x19
    bl   _home_say0
5:  LEAVE 272

// "bitchat advertise on" (1) / "off" (0) — this Mac only, never from the mesh
.globl _h_bitchat_adv
_h_bitchat_adv:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_remote_active
    ldr  x9, [x8]
    cbnz x9, Lha_here
    mov  x0, #SVC_BITCHAT
    bl   _svc_gate
    cbz  x0, 1f
    ADRL x8, _g_bc_adv
    str  x19, [x8]
    bl   _bc_advertise
    ADRL x0, Ls_adv_off
    ADRL x10, Ls_adv_on
    cmp  x19, #0
    csel x0, x10, x0, ne
    bl   _home_say0
1:  LEAVE 0
Lha_here:
    ADRL x0, Ls_only_here
    bl   _home_say0
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
// bitchat's service and characteristic (bitchat/Services/BLE/BLEService.swift)
Ls_svc_str:            .asciz "F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C"
Ls_chr_str:            .asciz "A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D"
Ls_cls:                .asciz "AMeshBitchat"
Lp_cm:                 .asciz "CBCentralManagerDelegate"
Lp_p:                  .asciz "CBPeripheralDelegate"
Lp_pm:                 .asciz "CBPeripheralManagerDelegate"
Lty_v1:                .asciz "v@:@"
Lty_v2:                .asciz "v@:@@"
Lty_v3:                .asciz "v@:@@@"
Lty_v4:                .asciz "v@:@@@@"
Lm_cmState:            .asciz "centralManagerDidUpdateState:"
Lm_cmDiscover:         .asciz "centralManager:didDiscoverPeripheral:advertisementData:RSSI:"
Lm_cmConnect:          .asciz "centralManager:didConnectPeripheral:"
Lm_cmFail:             .asciz "centralManager:didFailToConnectPeripheral:error:"
Lm_cmDisconn:          .asciz "centralManager:didDisconnectPeripheral:error:"
Lm_pServices:          .asciz "peripheral:didDiscoverServices:"
Lm_pChars:             .asciz "peripheral:didDiscoverCharacteristicsForService:error:"
Lm_pValue:             .asciz "peripheral:didUpdateValueForCharacteristic:error:"
Lm_pModify:            .asciz "peripheral:didModifyServices:"
Lm_pReady:             .asciz "peripheralIsReadyToSendWriteWithoutResponse:"
Lm_pmState:            .asciz "peripheralManagerDidUpdateState:"
Lm_pmAdded:            .asciz "peripheralManager:didAddService:error:"
Lm_pmSub:              .asciz "peripheralManager:central:didSubscribeToCharacteristic:"
Lm_pmUnsub:            .asciz "peripheralManager:central:didUnsubscribeFromCharacteristic:"
Lm_pmWrites:           .asciz "peripheralManager:didReceiveWriteRequests:"
Lm_pmRead:             .asciz "peripheralManager:didReceiveReadRequest:"
Lm_pmReady:            .asciz "peripheralManagerIsReadyToUpdateSubscribers:"
Ls_NSObject:           .asciz "NSObject"
Ls_new:                .asciz "new"
Ls_CBUUID:             .asciz "CBUUID"
Ls_CBCentralManager:   .asciz "CBCentralManager"
Ls_CBPeripheralManager: .asciz "CBPeripheralManager"
Ls_CBMutableCharacteristic: .asciz "CBMutableCharacteristic"
Ls_CBMutableService:   .asciz "CBMutableService"
Ls_NSArray:            .asciz "NSArray"
Ls_NSData:             .asciz "NSData"
Ls_NSDictionary:       .asciz "NSDictionary"
Ls_UUIDWithString:     .asciz "UUIDWithString:"
Ls_alloc:              .asciz "alloc"
Ls_retain:             .asciz "retain"
Ls_release:            .asciz "release"
Ls_initWithDelegate:   .asciz "initWithDelegate:queue:"
Ls_setDelegate:        .asciz "setDelegate:"
Ls_state:              .asciz "state"
Ls_stopScan:           .asciz "stopScan"
Ls_scanForPeripherals: .asciz "scanForPeripheralsWithServices:options:"
Ls_connectPeripheral:  .asciz "connectPeripheral:options:"
Ls_cancelPeripheralConnection: .asciz "cancelPeripheralConnection:"
Ls_discoverServices:   .asciz "discoverServices:"
Ls_services:           .asciz "services"
Ls_firstObject:        .asciz "firstObject"
Ls_discoverCharacteristics: .asciz "discoverCharacteristics:forService:"
Ls_characteristics:    .asciz "characteristics"
Ls_count:              .asciz "count"
Ls_objectAtIndex:      .asciz "objectAtIndex:"
Ls_UUID:               .asciz "UUID"
Ls_isEqual:            .asciz "isEqual:"
Ls_maxWriteLen:        .asciz "maximumWriteValueLengthForType:"
Ls_maxUpdateLen:       .asciz "maximumUpdateValueLength"
Ls_setNotify:          .asciz "setNotifyValue:forCharacteristic:"
Ls_canSendWWR:         .asciz "canSendWriteWithoutResponse"
Ls_writeValue:         .asciz "writeValue:forCharacteristic:type:"
Ls_updateValue:        .asciz "updateValue:forCharacteristic:onSubscribedCentrals:"
Ls_dataWithBytes:      .asciz "dataWithBytes:length:"
Ls_data:               .asciz "data"
Ls_value:              .asciz "value"
Ls_length:             .asciz "length"
Ls_bytes:              .asciz "bytes"
Ls_offset:             .asciz "offset"
Ls_central:            .asciz "central"
Ls_setValue:           .asciz "setValue:"
Ls_respondToRequest:   .asciz "respondToRequest:withResult:"
Ls_removeAllServices:  .asciz "removeAllServices"
Ls_initCharacteristic: .asciz "initWithType:properties:value:permissions:"
Ls_initWithTypePrimary: .asciz "initWithType:primary:"
Ls_setCharacteristics: .asciz "setCharacteristics:"
Ls_addService:         .asciz "addService:"
Ls_arrayWithObject:    .asciz "arrayWithObject:"
Ls_dictionaryWithObject: .asciz "dictionaryWithObject:forKey:"
Ls_startAdvertising:   .asciz "startAdvertising:"
Ls_stopAdvertising:    .asciz "stopAdvertising"

Lf_links:     .asciz "\302\267 bitchat: %ld linked (%ld this Mac found, %ld found this Mac)"
Lf_heard:     .asciz "\302\267 heard %ld packets: %ld hellos, %ld public messages"
Lf_heard2:    .asciz "\302\267 %ld private (sealed), %ld fragments, %ld put back together"
Ls_bc_kc:     .asciz "asmmesh.bitchat"
Ls_bc_kcpins: .asciz "asmmesh.bitchat.pins"
Ls_bc_kname:  .asciz "bitchatName"
Lf_bc_named:  .asciz "\302\267 bitchat: this Mac is \342\200\234%s\342\200\235 on bitchat (not its asmmesh name, so the two can't be linked by it)"
Lf_bc_name_is: .asciz "\302\267 bitchat: this Mac is \342\200\234%s\342\200\235 on bitchat; \342\200\234bitchat name \342\200\246\342\200\235 changes it"
Ls_bc_name_off: .asciz "\302\267 bitchat: this Mac's name on bitchat is chosen when bitchat is on; \342\200\234bitchat name \342\200\246\342\200\235 sets one"
Lf_bc_anon:   .asciz "anon%04ld"
Ls_bc_room:   .asciz "bitchat"
Ls_bc_noroom: .asciz "\302\267 bitchat: no space for the bitchat room (every room slot is taken). Leave a room and switch bitchat off and on."
Ls_bc_q:      .asciz "asmmesh.bitchat.keychain"
Ls_bc_pcts:   .asciz "%s"
Ls_bc_local:  .asciz "\302\267 what bitchat sees is only shown on this Mac, never over the mesh"
Lf_bc_said:   .asciz "%s (%s): %s"
Lf_bc_said_clash: .asciz "\342\232\240\357\270\217 %s (%s, bitchat, not the asmmesh one): %s"
Lf_bc_you:    .asciz "you: %s"
Lf_bc_unsent: .asciz "not sent (no bitchat link could take it): %s"
Ls_bc_say_off: .asciz "bitchat is off: switch it on in Settings (or type \342\200\234enable bitchat\342\200\235 in Home). Not sent."
Ls_bc_say_nokeys: .asciz "This Mac has no bitchat keys yet (type \342\200\234bitchat\342\200\235 in Home to see why). Not sent."
Ls_bc_say_nolink: .asciz "No bitchat phones are linked right now. Not sent."
Ls_bc_ann_on: .asciz "\302\267 bitchat: this Mac announces itself again"
Ls_bc_ann_off: .asciz "\302\267 bitchat: this Mac only listens for now, without announcing itself (\342\200\234bitchat announce on\342\200\235 to undo)"
Ls_bc_newkeys: .asciz "\302\267 bitchat: this Mac has its own bitchat keys now, kept apart from its asmmesh identity"
Ls_bc_norandom: .asciz "\302\267 bitchat: couldn't make keys, so this Mac stays quiet on bitchat"
Lf_bc_kc_no:  .asciz "\302\267 bitchat: the Keychain didn't hand over this Mac's bitchat keys (error %ld), so it stays quiet on bitchat. Switch bitchat off and on to ask again."
Ls_bc_nokeys: .asciz "\302\267 this Mac isn't announcing itself on bitchat (no keys)"
Ls_bc_loading: .asciz "\302\267 this Mac's bitchat keys are being read"
Lf_bc_me:     .asciz "\302\267 this Mac on bitchat: \342\200\234%s\342\200\235 \302\267 %s \302\267 %ld announces sent"
Lf_bc_limited: .asciz "\302\267 %ld packets left unchecked: more than 30 a second came in"
Lf_bc_chat_n: .asciz "\302\267 bitchat room: %ld messages shown, %ld sent; %ld packets passed on for other bitchat users"
Lf_bc_people_n: .asciz "\302\267 bitchat people: %ld around (%ld announces taken, %ld refused); say \342\200\234bitchat people\342\200\235"
Ls_bc_people_hdr: .asciz "\302\267 bitchat people (walled off: a name and a fingerprint, nothing more):"
Lf_bc_person: .asciz "\302\267 %s \342\200\224 %s"
Ls_bc_nobody: .asciz "\302\267 no bitchat people heard yet"
Lf_bc_new:    .asciz "\302\267 bitchat: %s is around (%s)"
Ls_bc_forgot: .asciz "\302\267 bitchat: this Mac's bitchat keys, the people heard and the counts are forgotten. With bitchat on it has new keys now, so bitchat phones see someone new."
Lf_bc_line:   .asciz "bitchat \302\267 %s \302\267 %s"
Lf_bc_line_clash: .asciz "\342\232\240\357\270\217 not the asmmesh person with this name \302\267 bitchat \302\267 %s \302\267 %s"
Ls_bc_near:   .asciz "nearby"
Ls_bc_via:    .asciz "through others"
Ls_bc_empty:  .asciz ""
Ls_kinds_first: .asciz "\302\267 other kinds: "
Ls_kinds_sep: .asciz ", "
Lf_kind:      .asciz "%s%ld \303\227 %s (0x%02lx)"
Lk_leave:     .asciz "leave"
Lk_courier:   .asciz "courier mail"
Lk_sync:      .asciz "sync request"
Lk_file:      .asciz "file"
Lk_board:     .asciz "board post"
Lk_prekeys:   .asciz "prekeys"
Lk_group:     .asciz "group message"
Lk_ping:      .asciz "ping"
Lk_pong:      .asciz "pong"
Lk_nostr:     .asciz "Nostr"
Lk_voice:     .asciz "voice"
Lk_presence:  .asciz "presence"
Lk_unknown:   .asciz "unknown"
Lf_heard3:    .asciz "\302\267 %ld other, %ld refused (broken or too big), %ld links made since it was switched on"
Ls_adv_on:    .asciz "\302\267 advertising bitchat's service: on (say \342\200\234bitchat advertise off\342\200\235 to stop)"
Ls_adv_off:   .asciz "\302\267 advertising bitchat's service: off. This Mac still links to bitchat phones it finds; \342\200\234bitchat advertise on\342\200\235 lets them find it too"
Ls_wall:      .asciz "\302\267 bitchat is walled off: what it sends is only counted for now, and can't reach your rooms, devices or keys"
Ls_only_here: .asciz "\302\267 bitchat's settings can only be changed on this Mac, not from the mesh"
