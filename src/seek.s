// seek.s — finding someone on the mesh. The core only carries the messages: SEEK packets,
// sealed for one person with the key only the two of you share. What's in them (asking to
// find someone, yes / stop, locations, Ultra Wideband tokens) is the iPhone's business
// (FindView.swift); every Mac and phone passes them on, and a Mac someone asks to find
// says so in Main.
//
//   SEEK  +12 target id  +20 sender id  +28 n  +29 nick, then the sealed payload

.include "macros.inc"

.zerofill __DATA,__bss,_g_seekbuf,256,4

.text
.p2align 2

// long _seek_send(uint64 target, const uint8 *data, long len) -> peers written, -1 not sent
//   (no key from them yet, no identity yet, or too long for one packet)
.globl _seek_send
_seek_send:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_nick_len              // header, our name, the data and its tag must fit
    ldr  x9, [x8]
    add  x9, x9, x21
    add  x9, x9, #(29 + 8 + TRAILER)
    cmp  x9, #PKT_MAX
    b.hi Lss_fail
    ADRL x8, _g_id_ready
    ldr  x9, [x8]
    cbz  x9, Lss_fail
    mov  x0, x19                      // the secret only they and we can compute
    ADRL x1, _g_pairkey
    bl   _pair_key
    cbz  x0, Lss_fail
    ADRL x0, _g_pkt
    mov  w1, #T_SEEK
    bl   _pkt_begin
    ADRL x22, _g_pkt
    str  x19, [x22, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x22, #20]
    add  x0, x22, #28
    bl   _put_nick
    mov  x23, x0
    mov  x1, x20
    mov  x2, x21
    bl   _memcpy
    ADRL x0, _g_pairkey
    mov  x1, x23
    mov  x2, x21
    add  x3, x22, #4                  // id, target and sender are bound in
    bl   _seal_key
    add  x1, x23, x0
    sub  x1, x1, x22                  // packet length
    mov  x0, x22
    bl   _pkt_finish
    cbz  x0, Lss_fail
    mov  x1, x0
    mov  x0, x22
    bl   _ble_broadcast
    LEAVE 0
Lss_fail:
    mov  x0, #-1
    LEAVE 0

// long _seek_rx(const uint8 *pkt, size_t body_len, long nick_len) -> 1 if it was for us (or
//   unreadable): not passed on. Nick already in _g_nickbuf.
.globl _seek_rx
_seek_rx:
    ENTER 0
    mov  x19, x0
    ldr  x9, [x19, #12]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne Lsr_pass                     // someone else's: pass it on
    add  x20, x2, #29                 // the sealed part
    subs x21, x1, x20
    b.le Lsr_mine
    ldr  x0, [x19, #20]
    ADRL x1, _g_pairkey
    bl   _pair_key
    cbz  x0, Lsr_mine
    ADRL x0, _g_pairkey
    add  x1, x19, x20
    mov  x2, x21
    add  x3, x19, #4
    ADRL x4, _g_seekbuf
    bl   _open_key
    tbnz x0, #63, Lsr_mine
    cbz  x0, Lsr_mine
    mov  x3, x0
    ldr  x0, [x19, #20]
    ADRL x1, _g_nickbuf
    ADRL x2, _g_seekbuf
    bl   _seek_in                     // the platform's: Finder.swift on iPhone, a note on the Mac
Lsr_mine:
    mov  x0, #1
    LEAVE 0
Lsr_pass:
    mov  x0, #0
    LEAVE 0
