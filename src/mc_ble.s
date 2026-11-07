// mc_ble.s — a MeshCore companion radio over Bluetooth, and its chat, walled off like
// bitchat's. Behind the MeshCore switch (SVC_MESHCORE, off by default, never with "enable all",
// never from the mesh). mc_core.s builds and reads the frames; this file connects, sends one
// command at a time, shows what comes in, and keeps the radio's contacts.
//
//   the radio      a Bluetooth device named "MeshCore-…" (companion firmware), its Nordic
//                  UART service: write 6E400002 (one frame per write), notify 6E400003
//   start          APP_START, DEVICE_QUERY, GET_CONTACTS, then SYNC_NEXT until NO_MORE
//   messages       "messages waiting" (0x83) or a 30 s poll: SYNC_NEXT until NO_MORE
//   the room       MeshCore (MESHCORE_ID, local, there while the switch is on): MeshCore's
//                  Public channel, and direct messages to and from you ("@Anna hi" sends one)
//
// The wall: what comes from a radio is shown in that room only, cleaned (no fake lines, no
// turned-round text), filtered, never a command, never passed to asmmesh rooms or the mesh.
// What you type there goes to the radio only. Every frame written passes _mc_allowed first
// (mc_core.s): a radio can't be asked to change its settings, reboot, reset or give up keys.
// A frame from the radio is read under _guard_call. Contacts are blocked by their key.
// The simulated radio: _g_mc_test 1 keeps written frames in _g_mc_sim instead of sending
// them; tests feed frames to _mc_frame_in (tools/qemu/mcsim.c, run.sh mcsim).
.include "macros.inc"
.include "mc_defs.inc"

.set MS_OFF,        0
.set MS_CONNECTING, 1
.set MS_STARTING,   2        // APP_START sent
.set MS_READY,      3        // SELF_INFO came back
.set MQ_N,          8        // frames waiting to be written, one at a time
.set MQ_SIZE,       192      // +0 length, +8 the frame
.set MC_CN,         64       // contacts kept
.set CT_KEY,        0        // [32]
.set CT_NAME,       32       // [40] cleaned, NUL-terminated
.set CT_TYPE,       72
.set CT_SEEN,       76       // u32: their last advert
.set CT_SIZE,       80
.set MC_WAIT_S,     3        // no reply in 3 s: on to the next frame
.set MC_POLL_S,     30       // ask for messages every 30 s anyway
.set MC_SIM_N,      32

.data
.p2align 3
.globl _g_mc_test
_g_mc_test:     .quad 0               // 1: the simulated radio (tests)
.globl _g_mc_sim_n
_g_mc_sim_n:    .quad 0               // frames "written" to it
.globl _g_mc_refused
_g_mc_refused:  .quad 0               // frames _mc_allowed stopped (should stay 0)
.globl _g_mc_state
_g_mc_state:    .quad 0
_g_mc_p:        .quad 0               // the radio (retained)
_g_mc_wr:       .quad 0               // its write characteristic (retained)
_g_mc_nt:       .quad 0               // its notify characteristic (retained)
_g_mc_u_svc:    .quad 0               // CBUUIDs
_g_mc_u_wr:     .quad 0
_g_mc_u_nt:     .quad 0
_g_mc_waiting:  .quad 0               // the time a frame was written and no reply yet, or 0
_g_mc_polled:   .quad 0
_g_mc_syncing:  .quad 0               // 1 while pulling messages
.globl _g_mc_cn
_g_mc_cn:       .quad 0               // contacts kept
_g_mc_qh:       .quad 0               // queue: head, count
_g_mc_qn:       .quad 0
_g_mc_maxch:    .quad 0
.zerofill __DATA,__bss,_g_mc_q,(MQ_N * MQ_SIZE),4
.globl _g_mc_sim
.zerofill __DATA,__bss,_g_mc_sim,(MC_SIM_N * MQ_SIZE),4
.globl _g_mc_contacts
.zerofill __DATA,__bss,_g_mc_contacts,(MC_CN * CT_SIZE),4
.globl _g_mc_radio
.zerofill __DATA,__bss,_g_mc_radio,48,4          // the radio's name, cleaned
.zerofill __DATA,__bss,_g_mc_mf,MF_SIZE,4
.zerofill __DATA,__bss,_g_mc_frame,256,4
.zerofill __DATA,__bss,_g_mc_text,640,4
.zerofill __DATA,__bss,_g_mc_line,800,4

.text
.p2align 2

// ---------------------------------------------------------------------------
// On and off (services.s)

// void _mc_start(void) — the switch on: the room, and look for a radio
.globl _mc_start
_mc_start:
    ENTER 0
    bl   Lmc_uuids
    bl   Lmc_room_on
    ADRL x8, _g_mc_state
    ldr  x9, [x8]
    cbnz x9, 9f
    ADRL x0, Ls_looking
    bl   Lmc_say
    ADRL x8, _g_mc_test
    ldr  x9, [x8]
    cbnz x9, 9f
    bl   _ble_scan                        // a radio is picked up from the scan (_mc_seen)
9:  LEAVE 0

// void _mc_stop(void) — the switch off: the radio let go, the room and contacts gone
.globl _mc_stop
_mc_stop:
    ENTER 0
    ADRL x8, _g_mc_p
    ldr  x0, [x8]
    cbz  x0, 1f
    bl   _ble_cancel
1:  bl   Lmc_forget
    ADRL x8, _g_mc_cn
    str  xzr, [x8]
    bl   Lmc_room_off
    bl   _ui_lists_changed
    LEAVE 0

// Lmc_forget — the radio's link gone: what we held of it released
Lmc_forget:
    ENTER 0
    ADRL x19, _g_mc_p
    mov  x20, #0
1:  ldr  x0, [x19, x20, lsl #3]           // _g_mc_p, _g_mc_wr, _g_mc_nt: next to each other
    cbz  x0, 2f
    MSG0 Ls_release
2:  str  xzr, [x19, x20, lsl #3]
    add  x20, x20, #1
    cmp  x20, #3
    b.lo 1b
    ADRL x8, _g_mc_state
    str  xzr, [x8]
    ADRL x8, _g_mc_waiting
    str  xzr, [x8]
    ADRL x8, _g_mc_qn
    str  xzr, [x8]
    ADRL x8, _g_mc_syncing
    str  xzr, [x8]
    LEAVE 0

// Lmc_uuids — the CBUUIDs, once
Lmc_uuids:
    ENTER 0
    ADRL x8, _g_mc_u_svc
    ldr  x9, [x8]
    cbnz x9, 9f
    ADRL x0, Ls_u_svc
    bl   Lmc_uuid
    ADRL x8, _g_mc_u_svc
    str  x0, [x8]
    ADRL x0, Ls_u_wr
    bl   Lmc_uuid
    ADRL x8, _g_mc_u_wr
    str  x0, [x8]
    ADRL x0, Ls_u_nt
    bl   Lmc_uuid
    ADRL x8, _g_mc_u_nt
    str  x0, [x8]
9:  LEAVE 0

Lmc_uuid:
    ENTER 0
    bl   _nsstr
    mov  x19, x0
    CLS  Ls_CBUUID
    mov  x2, x19
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    LEAVE 0

// ---------------------------------------------------------------------------
// Bluetooth (ble.s calls these, as it does spin.s's)

// long _mc_seen(id peripheral, const char *name, id adv) -> 1 if it's a MeshCore radio
//   ("MeshCore-…") and the switch is on (then, if we have none, we connect)
.globl _mc_seen
_mc_seen:
    ENTER 0
    mov  x19, x0
    cbz  x1, 8f
    mov  x0, x1
    ADRL x1, Ls_prefix
    mov  x2, #9
    bl   _strncmp
    cbnz w0, 8f
    mov  x0, #SVC_MESHCORE
    bl   _svc_on
    cbz  x0, 8f
    ADRL x8, _g_mc_p                      // one radio at a time
    ldr  x9, [x8]
    cbnz x9, 7f
    mov  x0, x19
    MSG0 Ls_retain
    ADRL x8, _g_mc_p
    str  x0, [x8]
    mov  x9, #MS_CONNECTING
    ADRL x8, _g_mc_state
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

// long _mc_connected(id peripheral) -> 1 if it's our radio: find its UART service
.globl _mc_connected
_mc_connected:
    ENTER 0
    mov  x19, x0
    bl   Lmc_ours
    cbz  x0, 9f
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x19
    MSG1 Ls_setDelegate
    ADRL x8, _g_mc_u_svc
    ldr  x0, [x8]
    bl   _array1
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_discoverServices
    mov  x0, #1
9:  LEAVE 0

// long _mc_services(id peripheral, id err) -> 1 if ours: its characteristics
.globl _mc_services
_mc_services:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   Lmc_ours
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

// long _mc_chars(id peripheral, id service, id err) -> 1 if ours: keep write and notify,
//   listen, start talking
.globl _mc_chars
_mc_chars:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    bl   Lmc_ours
    cbz  x0, Lmch_no
    cbnz x21, Lmch_yes
    mov  x0, x20
    MSG0 Ls_characteristics
    mov  x21, x0
    MSG0 Ls_count
    mov  x22, x0
1:  cbz  x22, 3f
    sub  x22, x22, #1
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_objectAtIndex
    mov  x23, x0
    MSG0 Ls_UUID
    mov  x24, x0
    ADRL x8, _g_mc_u_wr
    ldr  x2, [x8]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.eq 2f
    mov  x0, x23
    MSG0 Ls_retain
    ADRL x8, _g_mc_wr
    str  x0, [x8]
    b    1b
2:  mov  x0, x24
    ADRL x8, _g_mc_u_nt
    ldr  x2, [x8]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.eq 1b
    mov  x0, x23
    MSG0 Ls_retain
    ADRL x8, _g_mc_nt
    str  x0, [x8]
    mov  x0, x19
    mov  x2, #1
    mov  x3, x23
    MSG2 Ls_setNotifyValue
    b    1b
3:  ADRL x8, _g_mc_wr                     // both, or it isn't a radio we can talk to
    ldr  x9, [x8]
    ADRL x8, _g_mc_nt
    ldr  x10, [x8]
    cbz  x9, Lmch_drop
    cbz  x10, Lmch_drop
    bl   _mc_begin
Lmch_yes:
    mov  x0, #1
    LEAVE 0
Lmch_drop:
    ADRL x0, Ls_not_radio
    bl   Lmc_say
    mov  x0, x19
    bl   _ble_cancel
    b    Lmch_yes
Lmch_no:
    mov  x0, #0
    LEAVE 0

// long _mc_value(id peripheral, id chr, id err) -> 1 if it was our radio: one frame, read
//   under _guard_call (a bug can't take asmmesh down)
.globl _mc_value
_mc_value:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    bl   Lmc_ours
    cbz  x0, 9f
    cbnz x21, 8f
    mov  x0, x20
    MSG0 Ls_value
    cbz  x0, 8f
    mov  x21, x0
    MSG0 Ls_length
    mov  x22, x0
    cbz  x22, 8f
    cmp  x22, #255
    b.hi 8f
    mov  x0, x21
    MSG0 Ls_bytes
    mov  x1, x0                           // a copy: the NSData is the radio's
    ADRL x0, _g_mc_frame
    mov  x2, x22
    bl   _memcpy
    ADRL x0, _mc_frame_in
    ADRL x1, _g_mc_frame
    mov  x2, x22
    bl   _guard_call
8:  mov  x0, #1
9:  LEAVE 0

// void _mc_lost(id peripheral) — the radio went away (or we let it go)
.globl _mc_lost
_mc_lost:
    ENTER 0
    mov  x19, x0
    bl   Lmc_ours
    cbz  x0, 9f
    ADRL x8, _g_mc_state
    ldr  x20, [x8]
    bl   Lmc_forget
    cmp  x20, #MS_READY
    b.ne 9f
    ADRL x0, Ls_lost
    bl   Lmc_say
9:  LEAVE 0

// long Lmc_ours(x19 peripheral) -> 1 if it's the radio we hold
Lmc_ours:
    ADRL x8, _g_mc_p
    ldr  x9, [x8]
    cmp  x9, #0
    ccmp x9, x19, #0, ne
    cset x0, eq
    ret

// ---------------------------------------------------------------------------
// Talking to the radio: one frame at a time

// void _mc_begin(void) — linked: who we are, what it is, its contacts, its messages
.globl _mc_begin
_mc_begin:
    ENTER 0
    mov  x9, #MS_STARTING
    ADRL x8, _g_mc_state
    str  x9, [x8]
    ADRL x0, _g_mc_frame
    bl   _mc_app_start
    bl   Lmc_send_frame
    ADRL x0, _g_mc_frame
    bl   _mc_device_query
    bl   Lmc_send_frame
    ADRL x0, _g_mc_frame
    mov  w1, #0
    bl   _mc_get_contacts
    bl   Lmc_send_frame
    bl   Lmc_sync
    LEAVE 0

// Lmc_send_frame(x0 length of _g_mc_frame) — queued
Lmc_send_frame:
    mov  x1, x0
    ADRL x0, _g_mc_frame
    b    _mc_send

// Lmc_sync — pull messages (once at a time)
Lmc_sync:
    ENTER 0
    ADRL x8, _g_mc_syncing
    ldr  x9, [x8]
    cbnz x9, 9f
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, _g_mc_frame
    bl   _mc_sync_next
    bl   Lmc_send_frame
9:  LEAVE 0

// long _mc_send(const uint8 *frame, long len) -> 1 queued, 0 refused (the allowlist) or full
.globl _mc_send
_mc_send:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x2, #0                           // (no channel slot of ours yet: SET_CHANNEL refused)
    bl   _mc_allowed
    cbnz x0, 1f
    ADRL x8, _g_mc_refused
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    mov  x0, #0
    LEAVE 0
1:  ADRL x8, _g_mc_qn
    ldr  x9, [x8]
    cmp  x9, #MQ_N
    b.hs 8f
    ADRL x10, _g_mc_qh
    ldr  x10, [x10]
    add  x10, x10, x9
    and  x10, x10, #(MQ_N - 1)
    add  x9, x9, #1
    str  x9, [x8]
    mov  x11, #MQ_SIZE
    ADRL x8, _g_mc_q
    madd x21, x10, x11, x8
    str  x20, [x21]
    add  x0, x21, #8
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    bl   Lmc_pump
    mov  x0, #1
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// Lmc_pump — nothing waiting for a reply: write the next frame
Lmc_pump:
    ENTER 0
    ADRL x8, _g_mc_waiting
    ldr  x9, [x8]
    cbnz x9, 9f
    ADRL x8, _g_mc_qn
    ldr  x9, [x8]
    cbz  x9, 9f
    sub  x9, x9, #1
    str  x9, [x8]
    ADRL x8, _g_mc_qh
    ldr  x10, [x8]
    add  x11, x10, #1
    and  x11, x11, #(MQ_N - 1)
    str  x11, [x8]
    mov  x11, #MQ_SIZE
    ADRL x8, _g_mc_q
    madd x19, x10, x11, x8
    mov  x0, #0
    bl   _time
    ADRL x8, _g_mc_waiting
    str  x0, [x8]
    add  x0, x19, #8
    ldr  x1, [x19]
    bl   Lmc_write
9:  LEAVE 0

// Lmc_write(x0 frame, x1 len) — to the radio (or the simulated one). The allowlist again,
//   right before the write: nothing reaches a radio around it
Lmc_write:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x2, #0
    bl   _mc_allowed
    cbz  x0, 8f
    ADRL x8, _g_mc_test
    ldr  x9, [x8]
    cbnz x9, Lmw_sim
    ADRL x8, _g_mc_wr
    ldr  x21, [x8]
    cbz  x21, 9f
    CLS  Ls_NSData
    mov  x2, x19
    mov  x3, x20
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    ADRL x8, _g_mc_p
    ldr  x0, [x8]
    mov  x3, x21
    mov  x4, #0                           // with response
    MSG3 Ls_writeValue
    b    9f
Lmw_sim:
    ADRL x8, _g_mc_sim_n
    ldr  x9, [x8]
    cmp  x9, #MC_SIM_N
    b.hs 9f
    add  x10, x9, #1
    str  x10, [x8]
    mov  x10, #MQ_SIZE
    ADRL x8, _g_mc_sim
    madd x21, x9, x10, x8
    str  x20, [x21]
    add  x0, x21, #8
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    b    9f
8:  ADRL x8, _g_mc_refused
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
9:  LEAVE 0

// void _mc_tick(void) — every second: a reply that never came, and the poll for messages
.globl _mc_tick
_mc_tick:
    ENTER 0
    ADRL x8, _g_mc_state
    ldr  x9, [x8]
    cmp  x9, #MS_STARTING
    b.lo 9f
    mov  x0, #0
    bl   _time
    mov  x19, x0
    ADRL x8, _g_mc_waiting
    ldr  x9, [x8]
    cbz  x9, 1f
    sub  x10, x19, x9
    cmp  x10, #MC_WAIT_S
    b.lo 1f
    str  xzr, [x8]                        // no reply: on with the next
    ADRL x8, _g_mc_syncing
    str  xzr, [x8]
    bl   Lmc_pump
1:  ADRL x8, _g_mc_state
    ldr  x9, [x8]
    cmp  x9, #MS_READY
    b.ne 9f
    ADRL x8, _g_mc_polled
    ldr  x9, [x8]
    sub  x10, x19, x9
    cmp  x10, #MC_POLL_S
    b.lo 9f
    str  x19, [x8]
    bl   Lmc_sync
9:  LEAVE 0

// ---------------------------------------------------------------------------
// What the radio sends

// long _mc_frame_in(const uint8 *f, long len) — one frame from the radio
.globl _mc_frame_in
_mc_frame_in:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    ADRL x2, _g_mc_mf
    bl   _mc_parse
    mov  x21, x0
    tbnz x21, #63, 9f                     // malformed: ignored
    cmp  x21, #0x80                       // a reply (not a push): the next frame may go
    b.hs 1f
    ADRL x8, _g_mc_waiting
    str  xzr, [x8]
1:  ADRL x22, _g_mc_mf
    cmp  x21, #MCR_SELF
    b.eq Lfi_self
    cmp  x21, #MCR_DEVINFO
    b.eq Lfi_dev
    cmp  x21, #MCR_CONTACT
    b.eq Lfi_contact
    cmp  x21, #MCR_NEWADV
    b.eq Lfi_contact
    cmp  x21, #MCR_WAITING
    b.eq Lfi_waiting
    cmp  x21, #MCR_ADVERT
    b.eq Lfi_advert
    cmp  x21, #MCR_NOMORE
    b.eq Lfi_nomore
    cmp  x21, #MCR_CHAN
    b.eq Lfi_chan
    cmp  x21, #MCR_CHAN3
    b.eq Lfi_chan
    cmp  x21, #MCR_DM
    b.eq Lfi_dm
    cmp  x21, #MCR_DM3
    b.eq Lfi_dm
    cmp  x21, #MCR_DATA                   // channel data: asmmesh over LoRa (to come); taken
    b.eq Lfi_more
    b    8f
Lfi_self:                                 // APP_START answered: ready
    ldr  x0, [x22, #MF_NAME]
    ldr  x1, [x22, #MF_NLEN]
    ADRL x2, _g_mc_radio
    mov  x3, #33
    bl   _mc_show_text
    mov  x9, #MS_READY
    ADRL x8, _g_mc_state
    ldr  x10, [x8]
    str  x9, [x8]
    cmp  x10, #MS_READY
    b.eq 8f
    ADRL x8, _g_mc_radio
    str  x8, [sp]
    ADRL x0, _g_mc_line
    mov  x1, #400
    ADRL x2, Ls_ready
    bl   _snprintf
    ADRL x0, _g_mc_line
    bl   Lmc_say
    bl   _ui_update_status
    b    8f
Lfi_dev:
    ldr  x9, [x22, #MF_VAL2]
    ADRL x8, _g_mc_maxch
    str  x9, [x8]
    b    8f
Lfi_contact:
    bl   Lmc_contact_add
    b    8f
Lfi_waiting:
    bl   Lmc_sync
    b    8f
Lfi_advert:                               // someone known spoke up: their record again
    ADRL x0, _g_mc_frame
    mov  w1, #0
    bl   _mc_get_contacts
    bl   Lmc_send_frame
    b    8f
Lfi_nomore:
    ADRL x8, _g_mc_syncing
    str  xzr, [x8]
    b    8f
Lfi_chan:
    ldr  x9, [x22, #MF_CHAN]              // the Public channel only (slot 0) for now
    cbnz x9, Lfi_more
    bl   Lmc_show_chan
    b    Lfi_more
Lfi_dm:
    ldr  x9, [x22, #MF_TT]                // plain or signed text; never a CLI reply as chat
    cmp  x9, #1
    b.eq Lfi_more
    cmp  x9, #3
    b.eq Lfi_more
    bl   Lmc_show_dm
Lfi_more:                                 // a message taken: ask for the next
    ADRL x8, _g_mc_syncing
    str  xzr, [x8]
    bl   Lmc_sync
8:  bl   Lmc_pump
9:  mov  x0, #0
    LEAVE 16

// Lmc_contact_add — a contact record (_g_mc_mf): added or updated by key
Lmc_contact_add:
    ENTER 0
    ADRL x19, _g_mc_mf
    ldr  x20, [x19, #MF_KEY]
    mov  x21, #0
1:  ADRL x8, _g_mc_cn
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs 2f
    mov  x10, #CT_SIZE
    ADRL x8, _g_mc_contacts
    madd x22, x21, x10, x8
    mov  x0, x22
    mov  x1, x20
    mov  x2, #32
    bl   _memcmp
    cbz  w0, 3f
    add  x21, x21, #1
    b    1b
2:  cmp  x21, #MC_CN                      // new: at the end, if there's room
    b.hs 9f
    add  x9, x21, #1
    ADRL x8, _g_mc_cn
    str  x9, [x8]
    mov  x10, #CT_SIZE
    ADRL x8, _g_mc_contacts
    madd x22, x21, x10, x8
    mov  x0, x22
    mov  x1, x20
    mov  x2, #32
    bl   _memcpy
3:  ldr  x0, [x19, #MF_NAME]             // (src, n, dst, cap)
    ldr  x1, [x19, #MF_NLEN]
    add  x2, x22, #CT_NAME
    mov  x3, #33
    bl   _mc_show_text
    ldr  x9, [x19, #MF_VAL2]
    strb w9, [x22, #CT_TYPE]
    ldr  x9, [x19, #MF_TS]
    str  w9, [x22, #CT_SEEN]
    bl   _ui_lists_changed
9:  LEAVE 0

// Lmc_show_chan — a Public channel message: "Name: text" in the MeshCore room
Lmc_show_chan:
    ENTER 16
    ADRL x19, _g_mc_mf
    ldr  x20, [x19, #MF_TEXT]
    ldr  x21, [x19, #MF_TLEN]
    mov  x0, x20
    mov  x1, x21
    bl   _mc_sender                       // "Name: text"
    mov  x22, x0
    cbz  x22, 1f
    mov  x0, x20                          // the name
    mov  x1, x22
    ADRL x2, _g_mc_line
    mov  x3, #33
    bl   _mc_show_text
    add  x9, x22, #2
    add  x20, x20, x9
    sub  x21, x21, x9
    b    2f
1:  ADRL x0, Ls_someone                   // no name given
    ADRL x1, _g_mc_line
    mov  x2, #33
    bl   Lmc_strcpy
2:  ADRL x0, _g_mc_line                   // a contact with that name, blocked?
    bl   Lmc_name_id
    mov  x23, x0
    cbz  x23, 3f
    bl   _blk_has
    cbnz x0, 9f
3:  mov  x0, x20
    mov  x1, x21
    ADRL x2, _g_mc_text
    mov  x3, #400
    bl   _mc_show_text
    ADRL x0, _g_mc_text
    bl   _chat_clean
    mov  x0, x23
    mov  x1, #MESHCORE_ID
    ADRL x2, _g_mc_text
    bl   _rec_note
    ADRL x8, _g_mc_line
    str  x8, [sp]
    ADRL x8, _g_mc_text
    str  x8, [sp, #8]
    ADRL x0, _g_mc_line
    add  x0, x0, #48
    mov  x1, #700
    ADRL x2, Lf_said
    bl   _snprintf
    ADRL x0, _g_mc_line
    add  x0, x0, #48
    mov  x1, #0
    bl   Lmc_line
9:  LEAVE 16

// Lmc_show_dm — a direct message to us: "Name → you: text" (unknown senders by key)
Lmc_show_dm:
    ENTER 16
    ADRL x19, _g_mc_mf
    ldr  x0, [x19, #MF_KEY]               // 6-byte prefix: whose?
    bl   Lmc_prefix_contact
    mov  x20, x0
    cbz  x20, 1f
    mov  x0, x20                          // blocked?
    bl   Lmc_contact_id
    mov  x21, x0
    bl   _blk_has
    cbnz x0, 9f
    add  x9, x20, #CT_NAME
    b    2f
1:  mov  x21, #0
    ADRL x9, Ls_someone
2:  str  x9, [sp]
    ldr  x0, [x19, #MF_TEXT]
    ldr  x1, [x19, #MF_TLEN]
    ADRL x2, _g_mc_text
    mov  x3, #400
    bl   _mc_show_text
    ADRL x0, _g_mc_text
    bl   _chat_clean
    mov  x0, x21
    mov  x1, #MESHCORE_ID
    ADRL x2, _g_mc_text
    bl   _rec_note
    ADRL x8, _g_mc_text
    str  x8, [sp, #8]
    ADRL x0, _g_mc_line
    mov  x1, #700
    ADRL x2, Lf_dm
    bl   _snprintf
    ADRL x0, _g_mc_line
    mov  x1, #0
    bl   Lmc_line
9:  LEAVE 16

// long Lmc_prefix_contact(x0 6-byte key prefix) -> the contact (pointer), or 0
Lmc_prefix_contact:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
1:  ADRL x8, _g_mc_cn
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 8f
    mov  x10, #CT_SIZE
    ADRL x8, _g_mc_contacts
    madd x21, x20, x10, x8
    mov  x0, x21
    mov  x1, x19
    mov  x2, #6
    bl   _memcmp
    cbz  w0, 9f
    add  x20, x20, #1
    b    1b
8:  mov  x21, #0
9:  mov  x0, x21
    LEAVE 0

// long Lmc_name_id(x0 name) -> the id of the contact with that name (for blocking), or 0
Lmc_name_id:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
1:  ADRL x8, _g_mc_cn
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 8f
    mov  x10, #CT_SIZE
    ADRL x8, _g_mc_contacts
    madd x21, x20, x10, x8
    add  x0, x21, #CT_NAME
    mov  x1, x19
    bl   _strcmp
    cbz  w0, 2f
    add  x20, x20, #1
    b    1b
2:  mov  x0, x21
    bl   Lmc_contact_id
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// long Lmc_contact_id(x0 contact) -> an id for blocking: their key's first 7 bytes, tagged
//   0x4D ('M') in the top byte so it can't be an asmmesh or bitchat id (leaf)
Lmc_contact_id:
    ldr  x9, [x0]
    and  x9, x9, #0x00FFFFFFFFFFFFFF
    mov  x10, #0x4D00000000000000
    orr  x0, x9, x10
    ret

// ---------------------------------------------------------------------------
// The MeshCore room

// void _mc_say(const char *text) — typed in the MeshCore room (mesh.s): to the Public
//   channel, or "@Name text" to that contact. Only chat: nothing typed here is ever a command.
.globl _mc_say
_mc_say:
    ENTER 32
    mov  x19, x0
    ADRL x8, _g_mc_state
    ldr  x9, [x8]
    cmp  x9, #MS_READY
    ADRL x0, Ls_not_ready
    b.ne Lsay_note
    ldrb w9, [x19]
    cmp  w9, #'@'
    b.eq Lsay_dm
    mov  x0, x19                          // the Public channel (slot 0)
    bl   _strlen
    mov  x4, x0
    mov  x3, x19
    str  x4, [sp, #96]
    mov  x0, #0
    bl   _time
    mov  x2, x0
    ADRL x0, _g_mc_frame
    mov  x1, #0
    ldr  x4, [sp, #96]
    mov  x3, x19
    bl   _mc_send_chan_txt
    bl   Lmc_send_frame
    mov  x0, x19                          // shown as ours
    ADRL x1, Lf_me
    b    Lsay_show
Lsay_dm:                                  // "@Name text": the contact whose name it starts with
    add  x20, x19, #1
    mov  x21, #0
1:  ADRL x8, _g_mc_cn
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lsay_who
    mov  x10, #CT_SIZE
    ADRL x8, _g_mc_contacts
    madd x22, x21, x10, x8
    add  x0, x22, #CT_NAME
    bl   _strlen
    mov  x23, x0
    cbz  x23, 2f
    add  x0, x22, #CT_NAME
    mov  x1, x20
    mov  x2, x23
    bl   _strncasecmp
    cbnz w0, 2f
    ldrb w9, [x20, x23]
    cmp  w9, #' '
    b.eq 3f
2:  add  x21, x21, #1
    b    1b
3:  add  x24, x20, x23                    // the text after the name
4:  ldrb w9, [x24]
    cmp  w9, #' '
    b.ne 5f
    add  x24, x24, #1
    b    4b
5:  cbz  w9, Lsay_who
    mov  x0, x24
    bl   _strlen
    str  x0, [sp, #96]
    mov  x0, #0
    bl   _time
    mov  x2, x0
    ADRL x0, _g_mc_frame
    mov  x1, x22                          // their key's first 6 bytes
    mov  x3, x24
    ldr  x4, [sp, #96]
    bl   _mc_send_txt
    bl   Lmc_send_frame
    add  x9, x22, #CT_NAME
    str  x9, [sp, #104]
    mov  x0, x24
    ADRL x1, Lf_me_dm
    b    Lsay_show
Lsay_who:
    ADRL x0, Ls_no_contact
Lsay_note:
    bl   Lmc_say
    LEAVE 32
Lsay_show:                                // our line, cleaned like anyone's
    mov  x20, x1
    mov  x22, x0
    bl   _strlen
    mov  x1, x0
    mov  x0, x22
    ADRL x2, _g_mc_text
    mov  x3, #400
    bl   _mc_show_text
    ADRL x8, _g_mc_text
    str  x8, [sp]
    ldr  x9, [sp, #104]
    str  x9, [sp, #8]
    ADRL x0, _g_mc_line
    mov  x1, #700
    mov  x2, x20
    bl   _snprintf
    ADRL x0, _g_mc_line
    mov  x1, #0
    bl   Lmc_line
    LEAVE 32

// Lmc_line(x0 text, x1 sys) — into the MeshCore room
Lmc_line:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, #MESHCORE_ID
    bl   _room_find
    tbnz x0, #63, 9f
    mov  x1, x19
    mov  x2, x20
    bl   _room_line
9:  LEAVE 0

// Lmc_say(x0 text) — a system line in the MeshCore room (or Main, without it)
Lmc_say:
    ENTER 0
    mov  x19, x0
    mov  x0, #MESHCORE_ID
    bl   _room_find
    tbnz x0, #63, 1f
    mov  x1, x19
    mov  x2, #1
    bl   _room_line
    LEAVE 0
1:  mov  x0, x19
    bl   _chat_line
    LEAVE 0

// Lmc_room_on — the MeshCore room comes with the switch
Lmc_room_on:
    ENTER 0
    mov  x0, #MESHCORE_ID
    bl   _room_find
    tbz  x0, #63, 9f
    mov  x0, #MESHCORE_ID
    ADRL x1, Ls_room
    mov  x2, #0
    bl   _room_add
    tbnz x0, #63, 9f
    bl   _ui_rooms_changed
9:  LEAVE 0

// Lmc_room_off — and goes with it (local, never saved)
Lmc_room_off:
    ENTER 0
    mov  x0, #MESHCORE_ID
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

// Lmc_strcpy(x0 src, x1 dst, x2 cap) (leaf)
Lmc_strcpy:
    sub  x2, x2, #1
1:  cbz  x2, 2f
    ldrb w9, [x0], #1
    strb w9, [x1], #1
    cbz  w9, 3f
    sub  x2, x2, #1
    b    1b
2:  strb wzr, [x1]
3:  ret

// ---------------------------------------------------------------------------
// For the screens and People

// long am_mc_state(void) -> 0 off, 1 connecting, 2 starting, 3 ready
.globl _am_mc_state
_am_mc_state:
    ADRL x8, _g_mc_state
    ldr  x0, [x8]
    ret

// const char *am_mc_radio(void) — the radio's name
.globl _am_mc_radio
_am_mc_radio:
    ADRL x0, _g_mc_radio
    ret

// long am_mc_contacts(void); const char *am_mc_contact_name(long i);
//   long am_mc_contact_seen(long i) -> unix time of their last advert
.globl _am_mc_contacts
_am_mc_contacts:
    ADRL x8, _g_mc_cn
    ldr  x0, [x8]
    ret
.globl _am_mc_contact_name
_am_mc_contact_name:
    mov  x10, #CT_SIZE
    ADRL x8, _g_mc_contacts
    madd x0, x0, x10, x8
    add  x0, x0, #CT_NAME
    ret
.globl _am_mc_contact_seen
_am_mc_contact_seen:
    mov  x10, #CT_SIZE
    ADRL x8, _g_mc_contacts
    madd x0, x0, x10, x8
    ldr  w0, [x0, #CT_SEEN]
    ret
.globl _am_mc_contact_id
_am_mc_contact_id:
    mov  x10, #CT_SIZE
    ADRL x8, _g_mc_contacts
    madd x0, x0, x10, x8
    b    Lmc_contact_id

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_room:        .asciz "MeshCore"
Ls_prefix:      .asciz "MeshCore-"
Ls_u_svc:       .asciz "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
Ls_u_wr:        .asciz "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
Ls_u_nt:        .asciz "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
Ls_someone:     .asciz "someone"
Lf_said:        .asciz "%s: %s"
Lf_dm:          .asciz "%s \342\206\222 you: %s"
Lf_me:          .asciz "me: %s"
Lf_me_dm:       .asciz "me \342\206\222 %2$s: %1$s"
Ls_looking:     .asciz "\302\267 MeshCore is on: looking for a radio named \342\200\234MeshCore-\342\200\246\342\200\235 (companion firmware, Bluetooth). Your Mac or iPhone may ask for its PIN once."
Ls_ready:       .asciz "\302\267 \360\237\223\241 MeshCore radio \342\200\234%s\342\200\235 is linked. This room is MeshCore\342\200\231s Public channel; @Name text sends a direct message. Nothing from LoRa runs here as a command."
Ls_lost:        .asciz "\302\267 The MeshCore radio went out of reach; it\342\200\231s picked up again when it\342\200\231s back."
Ls_not_radio:   .asciz "\302\267 That \342\200\234MeshCore-\342\200\246\342\200\235 device isn\342\200\231t a companion radio asmmesh can talk to."
Ls_not_ready:   .asciz "\302\267 No MeshCore radio linked yet: nothing was sent."
Ls_no_contact:  .asciz "\302\267 Nobody by that name among the radio\342\200\231s contacts (and a direct message needs some text)."
Ls_CBUUID:      .asciz "CBUUID"
Ls_UUIDWithString: .asciz "UUIDWithString:"
Ls_NSData:      .asciz "NSData"
Ls_dataWithBytes: .asciz "dataWithBytes:length:"
Ls_writeValue:  .asciz "writeValue:forCharacteristic:type:"
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
