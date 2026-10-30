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
//   +600 send queue (Q_*)
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
.set L_SIZE,        (L_Q + Q_SIZE)

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
.set C_SIZE,        104

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
.zerofill __DATA,__bss,_g_bc_sk,64,4                      // X25519 secret, Ed25519 seed
.zerofill __DATA,__bss,_g_bc_xpub,32,4
.zerofill __DATA,__bss,_g_bc_edpub,32,4
.zerofill __DATA,__bss,_g_bc_myid,8,4                     // first 8 bytes of SHA-256(xpub)
.zerofill __DATA,__bss,_g_bc_kcbuf,160,4                  // the keys as hex, briefly
.globl _g_bc_peers
.zerofill __DATA,__bss,_g_bc_peers,BT_SIZE,4              // bitchat people (bc_peer.s)
.zerofill __DATA,__bss,_g_bc_scr,4096,4                   // what a signature covers
.zerofill __DATA,__bss,_g_bc_mydp,DP_SIZE,4               // a packet of ours
.zerofill __DATA,__bss,_g_bc_pl,128,4                     // its payload
.zerofill __DATA,__bss,_g_bc_out,512,4                    // and its bytes

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
    bl   _ui_lists_changed
    LEAVE 0

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
    mov  x0, x20                          // a fragment: its payload
    mov  x1, x21
    bl   _bc_frame_payload
    tbnz x0, #63, Lfi_done                // compressed: Phase 3
    mov  x24, x1
    add  x22, x20, x0                     // payload
    bl   _fm_now_ms
    mov  x1, x0
    ADRL x0, _g_bc_fa
    ldrb w9, [x20]                        // the sender id follows the header
    mov  x10, #14
    cmp  w9, #2
    mov  x11, #16
    csel x10, x11, x10, eq
    add  x2, x20, x10
    mov  x3, x22
    mov  x4, x24
    ADRL x5, _g_bc_joined
    bl   _bc_frag_put
    cmp  x0, #0
    b.eq Lfi_done
    b.lt Lfi_refused
    mov  x1, x0
    ldr  x9, [x23, #C_JOINED]
    add  x9, x9, #1
    str  x9, [x23, #C_JOINED]
    ADRL x0, _g_bc_joined                 // what it was: read that too
    bl   Lbc_read
    b    Lfi_done
Lfi_refused:
    ldr  x9, [x23, #C_REFUSED]
    add  x9, x9, #1
    str  x9, [x23, #C_REFUSED]
Lfi_done:
    LEAVE 0

// long Lbc_read(const uint8 *p, long n) -> 0, counted by type in _g_bc_types, or -1 if
//   bc_packet.s refuses it. Nothing else is done with it yet (Milestone 1).
Lbc_read:
    ENTER 0
    ADRL x2, _g_bc_dp
    ADRL x3, _g_bc_pay
    mov  x4, #8192
    bl   _bc_decode
    tbnz x0, #63, 1f
    ADRL x8, _g_bc_dp
    ldr  x9, [x8, #DP_TYPE]
    ADRL x8, _g_bc_types
    ldr  x10, [x8, x9, lsl #3]
    add  x10, x10, #1
    str  x10, [x8, x9, lsl #3]
    cmp  x9, #0x01
    b.ne 2f
    bl   Lbc_heard
    b    3f
2:  cmp  x9, #0x03
    b.ne 3f
    bl   Lbc_left
3:  mov  x0, #0
1:  LEAVE 0

// ---------------------------------------------------------------------------
// our bitchat identity, announces, and the people heard (Milestone 1)

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

// void Lbc_keys_load(void) — main thread, switch on: read our keys off the main thread
//   (macOS may ask first), then Lbc_kc_ready
Lbc_keys_load:
    ENTER 0
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    cbnz x9, 1f                           // loading, ready, or refused already
    mov  x9, #KS_LOADING
    str  x9, [x8]
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, #0
    ADRL x2, Lbc_kc_worker
    bl   _dispatch_async_f
1:  LEAVE 0

// void Lbc_kc_worker(void *unused) — background
Lbc_kc_worker:
    ENTER 0
    ADRL x0, Ls_bc_kc
    ADRL x1, _g_bc_kcbuf
    mov  x2, #160
    bl   _kc_get
    ADRL x8, _g_bc_kclen
    str  x0, [x8]
    ADRL x8, _g_kc_status
    ldrsw x9, [x8]
    ADRL x8, _g_bc_kcst
    str  x9, [x8]
    LDGOT x0, __dispatch_main_q
    mov  x1, #0
    ADRL x2, Lbc_kc_ready
    bl   _dispatch_async_f
    LEAVE 0

// void Lbc_kc_ready(void *unused) — main thread: use our keys, or make them if the
//   Keychain truly has none (never because it said no: that would change who we are)
Lbc_kc_ready:
    ENTER 0
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
    b    Lkr_new                          // there, but not keys: make new ones
Lkr_none:
    ADRL x8, _g_bc_kcst
    ldr  x9, [x8]
    cbz  x9, Lkr_new
    mov  x10, #-25300                     // errSecItemNotFound
    cmp  x9, x10
    b.eq Lkr_new
    ADRL x8, _g_bc_keys
    mov  x10, #KS_REFUSED
    str  x10, [x8]
    mov  x1, x9
    ADRL x0, Lf_bc_kc_no
    bl   _home_say
    b    Lkr_done
Lkr_new:
    mov  x0, #0                           // kSecRandomDefault
    mov  x1, #64
    ADRL x2, _g_bc_sk
    bl   _SecRandomCopyBytes
    cbnz w0, Lkr_fail
    ADRL x0, _g_bc_sk
    mov  x1, #64
    ADRL x2, _g_bc_kcbuf
    bl   _hex_enc
    ADRL x0, Ls_bc_kc
    ADRL x1, _g_bc_kcbuf
    bl   _kc_set
    ADRL x0, Ls_bc_newkeys
    bl   _home_say0
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
    b    Lkr_done
Lkr_fail:
    ADRL x8, _g_bc_keys
    mov  x9, #KS_REFUSED
    str  x9, [x8]
    ADRL x0, Ls_bc_norandom
    bl   _home_say0
    b    Lkr_done
Lkr_off:
    bl   Lbc_keys_wipe
Lkr_done:
    ADRL x0, _g_bc_kcbuf
    mov  x1, #160
    bl   _bc_wipe
    LEAVE 0

// void Lbc_keys_wipe(void) — our keys, and everyone we heard, out of memory
Lbc_keys_wipe:
    ENTER 0
    ADRL x8, _g_bc_keys
    str  xzr, [x8]
    ADRL x0, _g_bc_sk
    mov  x1, #64
    bl   _bc_wipe
    ADRL x0, _g_bc_kcbuf
    mov  x1, #160
    bl   _bc_wipe
    ADRL x0, _g_bc_myid
    mov  x1, #8
    bl   _bc_wipe
    ADRL x0, _g_bc_peers
    mov  x1, #BT_SIZE
    bl   _bc_wipe
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
    ADRL x0, _g_nick
    bl   _strlen
    mov  x1, x0
    ADRL x0, _g_nick
    ADRL x2, _g_bc_xpub
    ADRL x3, _g_bc_edpub
    ADRL x4, _g_bc_pl
    bl   _bc_ann_make
    mov  x2, x0
    mov  x0, #0x01
    ADRL x1, _g_bc_pl
    bl   Lbc_send_own
    LEAVE 0

// void _bc_tick(void) — once a second (scanner.s, ios_ui.s): forget people gone quiet,
//   and announce when it's time
.globl _bc_tick
_bc_tick:
    ENTER 0
    ADRL x8, _g_bc_keys
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    b.ne 9f
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
    mov  w0, #4000                        // the next in 15 to 19 s, as bitchat does
    bl   _arc4random_uniform
    mov  w0, w0
    add  x9, x19, x0
    mov  x10, #15000
    add  x9, x9, x10
    ADRL x8, _g_bc_ann_at
    str  x9, [x8]
9:  LEAVE 0

// void Lbc_heard(void) — an announce was read into _g_bc_dp
Lbc_heard:
    ENTER 0
    ADRL x8, _g_bc_keys                   // without our id we can't tell our own apart
    ldr  x9, [x8]
    cmp  x9, #KS_READY
    b.ne 9f
    bl   Lbc_wall_ms
    mov  x1, x0
    ADRL x0, _g_bc_peers
    ADRL x2, _g_bc_myid
    ADRL x3, _g_bc_dp
    ADRL x4, _g_bc_scr
    mov  x5, #4096
    bl   _bc_peer_heard
    ADRL x8, _g_bc_cnt
    tbnz x0, #63, 2f
    mov  x19, x0
    mov  x20, x1
    ldr  x9, [x8, #C_ANN_OK]
    add  x9, x9, #1
    str  x9, [x8, #C_ANN_OK]
    cbz  x20, 9f
    ADRL x8, _g_bc_peers                  // someone new: say so once, and warn about a name
    add  x0, x8, x19, lsl #BT_SHIFT       //   an asmmesh person also has
    bl   Lbc_say_person
    bl   _ui_lists_changed
    b    9f
2:  cmn  x0, #3                           // our own, come back round: not a refusal
    b.eq 9f
    ldr  x9, [x8, #C_ANN_BAD]
    add  x9, x9, #1
    str  x9, [x8, #C_ANN_BAD]
9:  LEAVE 0

// void Lbc_left(void) — a leave was read into _g_bc_dp
Lbc_left:
    ENTER 0
    ADRL x0, _g_bc_peers
    ADRL x1, _g_bc_dp
    ADRL x2, _g_bc_scr
    mov  x3, #4096
    bl   _bc_peer_leave
    tbnz x0, #63, 1f
    bl   _ui_lists_changed
1:  LEAVE 0

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

// long _bc_person_clash(const uint8 *e) -> 1 if an asmmesh person has the same name
.globl _bc_person_clash
_bc_person_clash:
    ENTER 0
    add  x19, x0, #BT_NICK
    mov  x20, #0
1:  ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 2f
    ADRL x8, _g_nodes
    add  x0, x8, x20, lsl #NODE_SHIFT
    bl   _node_name
    mov  x1, x19
    bl   _strcasecmp
    add  x20, x20, #1
    cbnz w0, 1b
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
    ADRL x22, Ls_bc_near
    ldr  x9, [x19, #BT_HOPS]
    cmp  x9, #1
    b.ls 1f
    str  x9, [sp]
    add  x0, sp, #128
    mov  x1, #32
    ADRL x2, Lf_bc_hops
    bl   _snprintf
    add  x22, sp, #128
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

// void Lbc_say_person(const uint8 *e) — "· bitchat: Anna is around (bitchat · ...)"
Lbc_say_person:
    ENTER 128                             // [96] their line
    mov  x19, x0
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
    bl   _home_say
    LEAVE 128

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
    ADRL x8, _g_bc_ann_at                 // a new link: announce at the next tick
    str  xzr, [x8]
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
    mov  x0, x19
    mov  x1, #K_THEY_CENTRAL
    mov  x2, #S_READY
    bl   _bc_link_new
    tbnz x0, #63, 1f
    mov  x20, x0
    ADRL x8, _g_bc_ann_at                 // a new link: announce at the next tick
    str  xzr, [x8]
    mov  x0, x19                          // what one notification can carry
    MSG0 Ls_maxUpdateLen
    cmp  x0, #BC_WRITE_MAX
    mov  x9, #BC_WRITE_MAX
    csel x0, x9, x0, hi
    LINK x21, x20
    str  x0, [x21, #L_MAX]
    mov  x0, x20
1:  LEAVE 0

// - (void)peripheralManager:pm central:c didSubscribeToCharacteristic:ch
_bc_pm_sub:
    ENTER 0
    mov  x0, x3
    bl   _bc_central_link
    tbnz x0, #63, 1f
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
    ADRL x1, _g_nick
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

// "bitchat people" — everyone heard, with their fingerprint
.globl _h_bitchat_people
_h_bitchat_people:
    ENTER 144                             // [96] a line
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
    ADRL x0, Ls_bc_kc
    bl   _kc_del
    bl   Lbc_keys_wipe
    ADRL x0, _g_bc_cnt
    mov  x1, #C_SIZE
    bl   _bc_wipe
    bl   _ui_lists_changed
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
Ls_bc_ann_on: .asciz "\302\267 bitchat: this Mac announces itself again"
Ls_bc_ann_off: .asciz "\302\267 bitchat: this Mac only listens for now, without announcing itself (\342\200\234bitchat announce on\342\200\235 to undo)"
Ls_bc_newkeys: .asciz "\302\267 bitchat: this Mac has its own bitchat keys now, kept apart from its asmmesh identity"
Ls_bc_norandom: .asciz "\302\267 bitchat: couldn't make keys, so this Mac stays quiet on bitchat"
Lf_bc_kc_no:  .asciz "\302\267 bitchat: the Keychain didn't hand over this Mac's bitchat keys (error %ld), so it stays quiet on bitchat. Switch bitchat off and on to ask again."
Ls_bc_nokeys: .asciz "\302\267 this Mac isn't announcing itself on bitchat (no keys)"
Ls_bc_loading: .asciz "\302\267 this Mac's bitchat keys are being read"
Lf_bc_me:     .asciz "\302\267 this Mac on bitchat: \342\200\234%s\342\200\235 \302\267 %s \302\267 %ld announces sent"
Lf_bc_people_n: .asciz "\302\267 bitchat people: %ld around (%ld announces taken, %ld refused); say \342\200\234bitchat people\342\200\235"
Ls_bc_people_hdr: .asciz "\302\267 bitchat people (walled off: a name and a fingerprint, nothing more):"
Lf_bc_person: .asciz "\302\267 %s \342\200\224 %s"
Ls_bc_nobody: .asciz "\302\267 no bitchat people heard yet"
Lf_bc_new:    .asciz "\302\267 bitchat: %s is around (%s)"
Ls_bc_forgot: .asciz "\302\267 bitchat: this Mac's bitchat keys, the people heard and the counts are forgotten. With bitchat on it has new keys now, so bitchat phones see someone new."
Lf_bc_line:   .asciz "bitchat \302\267 %s \302\267 %s"
Lf_bc_line_clash: .asciz "\342\232\240\357\270\217 not the asmmesh person with this name \302\267 bitchat \302\267 %s \302\267 %s"
Ls_bc_near:   .asciz "nearby"
Lf_bc_hops:   .asciz "%ld hops"
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
