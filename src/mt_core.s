// mt_core.s — a Meshtastic radio's messages, pure (no globals, no system calls): what asmmesh
// sends it over Bluetooth (ToRadio protobufs, built here) and the allowlist every one passes
// before it's written (_mt_allowed: start-up, a heartbeat, or plain text — never admin, config,
// raw or encrypted payloads), and what it sends back (FromRadio, read here with every length
// and varint checked). Protobuf by hand, the few fields used, from Meshtastic's published field
// numbers (meshtastic/protobufs 85f3f43: mesh.proto, channel.proto, portnums.proto); no
// Meshtastic code is used. tools/meshcore/mt.py is the Python copy; mtdiff.py checks the two
// agree on random messages. Text is shown through mc_core.s's _mc_show_text. Self-tests 237-238.
.include "macros.inc"
.include "mt_defs.inc"

// PBV dst — a varint at x9[x10] (x11 the end) into dst: at most 10 bytes, bits past 64 dropped;
//   off the end or too long: to Lpn_bad. Uses x12-x15
.macro PBV dst
    mov  \dst, #0
    mov  x12, #0
    mov  x14, #0
1:  cmp  x10, x11
    b.hs Lpn_bad
    cmp  x14, #10
    b.hs Lpn_bad
    ldrb w13, [x9, x10]
    add  x10, x10, #1
    add  x14, x14, #1
    and  x15, x13, #0x7F
    cmp  x12, #63
    b.hi 2f
    lsl  x15, x15, x12
    orr  \dst, \dst, x15
2:  add  x12, x12, #7
    tbnz w13, #7, 1b
.endm

.text
.p2align 2

// ---------------------------------------------------------------------------
// Protobuf, by hand

// Lpb_next(x0 base, x1 i, x2 end) -> x0 the next field's number (0 at the end, -1 malformed),
//   x1 its wire type, x2 its value (varint, fixed) or, for bytes, where they start, x3 how
//   many, x4 where the next field starts (leaf)
Lpb_next:
    mov  x9, x0
    mov  x10, x1
    mov  x11, x2
    cmp  x10, x11
    b.hs Lpn_end
    PBV  x5
    lsr  x0, x5, #3
    and  x1, x5, #7
    cbz  x0, Lpn_bad
    cbz  x1, Lpn_v
    cmp  x1, #2
    b.eq Lpn_b
    cmp  x1, #1
    b.eq Lpn_64
    cmp  x1, #5
    b.ne Lpn_bad
    sub  x12, x11, x10                    // fixed32
    cmp  x12, #4
    b.lo Lpn_bad
    ldr  w2, [x9, x10]
    add  x10, x10, #4
    b    Lpn_ok
Lpn_64:
    sub  x12, x11, x10
    cmp  x12, #8
    b.lo Lpn_bad
    ldr  x2, [x9, x10]
    add  x10, x10, #8
    b    Lpn_ok
Lpn_v:
    PBV  x2
    b    Lpn_ok
Lpn_b:
    PBV  x3                               // length, then the bytes: all within the end
    sub  x12, x11, x10
    cmp  x3, x12
    b.hi Lpn_bad
    mov  x2, x10
    add  x10, x10, x3
Lpn_ok:
    mov  x4, x10
    ret
Lpn_end:
    mov  x0, #0
    ret
Lpn_bad:
    mov  x0, #-1
    ret

// Lpb_key(x0 out, x1 byte) / Lpb_varint(x0 out, x1 value) -> x0 past it (leaf)
Lpb_varint:
1:  and  x9, x1, #0x7F
    lsr  x1, x1, #7
    cbz  x1, 2f
    orr  x9, x9, #0x80
    strb w9, [x0], #1
    b    1b
2:  strb w9, [x0], #1
    ret

// long Lpb_vlen(x0 value) -> its varint's length (leaf)
Lpb_vlen:
    mov  x9, #1
1:  lsr  x0, x0, #7
    cbz  x0, 2f
    add  x9, x9, #1
    b    1b
2:  mov  x0, x9
    ret

// ---------------------------------------------------------------------------
// What we send (each -> its length)

// long _mt_want_config(uint8 *out, uint32 nonce) — ToRadio{want_config_id}: send me everything
.globl _mt_want_config
_mt_want_config:
    ENTER 0
    mov  x19, x0
    mov  w9, #0x18
    strb w9, [x0], #1
    mov  w1, w1                           // (32 bits)
    bl   Lpb_varint
    sub  x0, x0, x19
    LEAVE 0

// long _mt_heartbeat(uint8 *out) — ToRadio{heartbeat{}} (leaf)
.globl _mt_heartbeat
_mt_heartbeat:
    mov  w9, #0x3A
    strb w9, [x0]
    strb wzr, [x0, #1]
    mov  x0, #2
    ret

// long _mt_send_text(uint8 *out, uint32 to, long chan, uint32 id, const char *text, long n,
//   long ack) — ToRadio{packet{to, channel, decoded{TEXT_MESSAGE_APP, text}, id, want_ack}}:
//   to 0xFFFFFFFF is everyone; the text cut to 200 bytes between characters
.globl _mt_send_text
_mt_send_text:
    ENTER 32                              // [96] ack [104] id
    mov  x19, x0
    mov  w20, w1                          // to
    and  x21, x2, #7                      // channel 0-7
    str  x6, [sp, #96]
    str  x3, [sp, #104]
    mov  x22, x4                          // text
    mov  x0, x4
    mov  x1, x5
    mov  x2, #MT_TEXT_MAX
    bl   _mc_cut_utf8
    mov  x23, x0                          // its length
    bl   Lpb_vlen
    add  x24, x0, x23
    add  x24, x24, #3                     // Data: 08 01 12 len text
    mov  x0, x24
    bl   Lpb_vlen
    add  x9, x0, x24
    add  x9, x9, #11                      // packet: 15 to(4) 22 len data 35 id(4)
    cmp  x21, #0
    cinc x9, x9, ne                       //   18 chan
    cinc x9, x9, ne
    ldr  x10, [sp, #96]
    cmp  x10, #0
    cinc x9, x9, ne                       //   50 01
    cinc x9, x9, ne
    mov  x10, x9
    mov  x0, x19
    mov  w11, #0x0A                       // ToRadio.packet
    strb w11, [x0], #1
    mov  x1, x10
    bl   Lpb_varint
    mov  w11, #0x15                       // to
    strb w11, [x0], #1
    str  w20, [x0], #4
    cbz  x21, 1f
    mov  w11, #0x18                       // channel
    strb w11, [x0], #1
    strb w21, [x0], #1
1:  mov  w11, #0x22                       // decoded
    strb w11, [x0], #1
    mov  x1, x24
    bl   Lpb_varint
    mov  w11, #0x08                       // portnum: text
    strb w11, [x0], #1
    mov  w11, #MT_PORT_TEXT
    strb w11, [x0], #1
    mov  w11, #0x12                       // payload
    strb w11, [x0], #1
    mov  x1, x23
    bl   Lpb_varint
    mov  x9, #0
2:  cmp  x9, x23
    b.hs 3f
    ldrb w11, [x22, x9]
    strb w11, [x0], #1
    add  x9, x9, #1
    b    2b
3:  mov  w11, #0x35                       // id
    strb w11, [x0], #1
    ldr  x11, [sp, #104]
    str  w11, [x0], #4
    ldr  x10, [sp, #96]
    cbz  x10, 4f
    mov  w11, #0x50                       // want_ack
    strb w11, [x0], #1
    mov  w11, #1
    strb w11, [x0], #1
4:  sub  x0, x0, x19
    LEAVE 32

// ---------------------------------------------------------------------------
// The allowlist

// long _mt_allowed(const uint8 *f, long len) -> 1 if asmmesh may write this ToRadio to a radio:
//   exactly one of want_config_id, an empty heartbeat, or a packet holding only to, channel
//   (0-7), id, want_ack and decoded {portnum TEXT_MESSAGE_APP, payload <= 233} — each once.
//   Never admin (port 6) or any other port, config, XModem, MQTT, raw, encrypted or keyed packets
.globl _mt_allowed
_mt_allowed:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    cmp  x20, #1
    b.lo Lma_no
    cmp  x20, #MT_FRAME_MAX
    b.hi Lma_no
    mov  x1, #0
    mov  x2, x20
    bl   Lpb_next
    cmp  x0, #1
    b.lt Lma_no
    mov  x21, x0                          // the one field
    mov  x22, x1
    stp  x2, x3, [sp, #96]
    mov  x0, x19                          // and nothing after it
    mov  x1, x4
    mov  x2, x20
    bl   Lpb_next
    cbnz x0, Lma_no
    cmp  x21, #3                          // want_config_id
    ccmp x22, #0, #0, eq
    b.eq Lma_yes
    cmp  x21, #7                          // heartbeat, empty
    b.ne 1f
    cmp  x22, #2
    b.ne Lma_no
    ldr  x9, [sp, #104]
    cbz  x9, Lma_yes
    b    Lma_no
1:  cmp  x21, #1                          // a packet
    ccmp x22, #2, #0, eq
    b.ne Lma_no
    ldp  x23, x24, [sp, #96]
    add  x24, x23, x24                    // x23..x24: the packet
    mov  x21, #0                          // fields seen
    mov  x22, #-1                         // where its Data is
    str  xzr, [sp, #112]
2:  mov  x0, x19
    mov  x1, x23
    mov  x2, x24
    bl   Lpb_next
    tbnz x0, #63, Lma_no
    cbz  x0, 5f
    mov  x23, x4
    cmp  x0, #63
    b.hi Lma_no
    mov  x9, #1
    lsl  x9, x9, x0
    tst  x21, x9                          // once each
    b.ne Lma_no
    orr  x21, x21, x9
    cmp  x0, #2                           // to
    b.ne 3f
    cmp  x1, #5
    b.eq 2b
    b    Lma_no
3:  cmp  x0, #6                           // id
    b.ne 31f
    cmp  x1, #5
    b.eq 2b
    b    Lma_no
31: cmp  x0, #3                           // channel 0-7
    b.ne 32f
    cbnz x1, Lma_no
    cmp  x2, #7
    b.ls 2b
    b    Lma_no
32: cmp  x0, #10                          // want_ack
    b.ne 33f
    cbnz x1, Lma_no
    cmp  x2, #1
    b.ls 2b
    b    Lma_no
33: cmp  x0, #4                           // decoded
    b.ne Lma_no
    cmp  x1, #2
    b.ne Lma_no
    mov  x22, x2
    add  x9, x2, x3
    str  x9, [sp, #112]
    b    2b
5:  tbnz x22, #63, Lma_no                 // the Data: portnum text, a payload, nothing else
    ldr  x24, [sp, #112]
    mov  x23, x22
    mov  x21, #0
    mov  x22, #-1                         // the port
6:  mov  x0, x19
    mov  x1, x23
    mov  x2, x24
    bl   Lpb_next
    tbnz x0, #63, Lma_no
    cbz  x0, 8f
    mov  x23, x4
    cmp  x0, #63
    b.hi Lma_no
    mov  x9, #1
    lsl  x9, x9, x0
    tst  x21, x9
    b.ne Lma_no
    orr  x21, x21, x9
    cmp  x0, #1
    b.ne 7f
    cbnz x1, Lma_no
    mov  x22, x2
    b    6b
7:  cmp  x0, #2
    b.ne Lma_no
    cmp  x1, #2
    b.ne Lma_no
    cmp  x3, #MT_PAYLOAD_MAX
    b.hi Lma_no
    b    6b
8:  cmp  x22, #MT_PORT_TEXT
    b.ne Lma_no
Lma_yes:
    mov  x0, #1
    LEAVE 32
Lma_no:
    mov  x0, #0
    LEAVE 32

// ---------------------------------------------------------------------------
// What the radio sends

// long _mt_parse(const uint8 *f, long len, uint8 mt[MT_SIZE]) -> what the FromRadio holds (its
//   field: MTK_*), 0 for an empty read, -1 if malformed; its fields in mt (MT_HAS says which)
.globl _mt_parse
_mt_parse:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, #0                          // kind
    mov  x23, #0                          // where we are
    bl   Lmt_clear
    cmp  x20, #MT_FRAME_MAX
    b.hi Lmp2_bad
1:  mov  x0, x19
    mov  x1, x23
    mov  x2, x20
    bl   Lpb_next
    tbnz x0, #63, Lmp2_bad
    cbz  x0, Lmp2_done
    mov  x23, x4
    cmp  x0, #1                           // FromRadio.id
    b.eq 1b
    mov  x22, x0
    stp  x1, x2, [sp, #96]
    str  x3, [sp, #112]
    bl   Lmt_clear                        // a later one replaces what was read
    ldp  x1, x2, [sp, #96]
    ldr  x3, [sp, #112]
    cmp  x22, #MTK_DONE
    b.ne 2f
    cbnz x1, 1b
    str  x2, [x21, #MT_NUM]
    mov  x9, #(1 << 5)
    str  x9, [x21, #MT_HAS]
    b    1b
2:  cmp  x1, #2                           // the rest are messages: bytes
    b.ne 1b
    mov  x0, x19
    mov  x1, x2
    add  x2, x2, x3
    mov  x3, x21
    cmp  x22, #MTK_PACKET
    b.eq 3f
    cmp  x22, #MTK_MYINFO
    b.eq 4f
    cmp  x22, #MTK_NODE
    b.eq 5f
    cmp  x22, #MTK_CHANNEL
    b.eq 6f
    b    1b
3:  bl   Lmt_packet
    b    7f
4:  bl   Lmt_myinfo
    b    7f
5:  bl   Lmt_node
    b    7f
6:  bl   Lmt_channel
7:  tbnz x0, #63, Lmp2_bad
    b    1b
Lmp2_done:
    mov  x0, x22
    LEAVE 16
Lmp2_bad:
    bl   Lmt_clear
    mov  x0, #-1
    LEAVE 16

// Lmt_clear (x21 mt) (leaf)
Lmt_clear:
    mov  x9, #0
1:  str  xzr, [x21, x9]
    add  x9, x9, #8
    cmp  x9, #MT_SIZE
    b.lo 1b
    ret

// SETF reg, off, bit — mt[off] = reg; MT_HAS |= 1 << bit (x22 mt; uses x9)
.macro SETF reg, off, bit
    str  \reg, [x22, #\off]
    ldr  x9, [x22, #MT_HAS]
    orr  x9, x9, #(1 << \bit)
    str  x9, [x22, #MT_HAS]
.endm

// Each part's reader: (x0 f, x1 start, x2 end, x3 mt) -> 0, or -1 if malformed. Inside:
//   x19 f, x20 where we are, x21 the end, x22 mt

// Lmt_packet — MeshPacket: from, to, channel, id, decoded {portnum, payload}, encrypted
Lmt_packet:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
1:  mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lpb_next
    tbnz x0, #63, 9f
    cbz  x0, 8f
    mov  x20, x4
    cmp  x0, #1
    b.ne 2f
    cmp  x1, #5
    b.ne 1b
    SETF x2, MT_FROM, 0
    b    1b
2:  cmp  x0, #2
    b.ne 3f
    cmp  x1, #5
    b.ne 1b
    SETF x2, MT_TO, 1
    b    1b
3:  cmp  x0, #3
    b.ne 4f
    cbnz x1, 1b
    SETF x2, MT_CHAN, 2
    b    1b
4:  cmp  x0, #6
    b.ne 5f
    cmp  x1, #5
    b.ne 1b
    SETF x2, MT_PID, 4
    b    1b
5:  cmp  x0, #5
    b.ne 6f
    cmp  x1, #2
    b.ne 1b
    mov  x9, #1
    SETF x9, MT_ENC, 12
    b    1b
6:  cmp  x0, #4
    b.ne 1b
    cmp  x1, #2
    b.ne 1b
    mov  x0, x19
    mov  x1, x2
    add  x2, x2, x3
    mov  x3, x22
    bl   Lmt_data
    tbnz x0, #63, 9f
    b    1b
8:  mov  x0, #0
    LEAVE 0
9:  mov  x0, #-1
    LEAVE 0

// Lmt_data — Data: portnum, payload
Lmt_data:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
1:  mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lpb_next
    tbnz x0, #63, 9f
    cbz  x0, 8f
    mov  x20, x4
    cmp  x0, #1
    b.ne 2f
    cbnz x1, 1b
    SETF x2, MT_PORT, 3
    b    1b
2:  cmp  x0, #2
    b.ne 1b
    cmp  x1, #2
    b.ne 1b
    add  x2, x19, x2
    str  x3, [x22, #MT_TLEN]
    SETF x2, MT_TEXT, 6
    b    1b
8:  mov  x0, #0
    LEAVE 0
9:  mov  x0, #-1
    LEAVE 0

// Lmt_myinfo — MyNodeInfo: my_node_num
Lmt_myinfo:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
1:  mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lpb_next
    tbnz x0, #63, 9f
    cbz  x0, 8f
    mov  x20, x4
    cmp  x0, #1
    b.ne 1b
    cbnz x1, 1b
    SETF x2, MT_NUM, 5
    b    1b
8:  mov  x0, #0
    LEAVE 0
9:  mov  x0, #-1
    LEAVE 0

// Lmt_node — NodeInfo: num, user {id, long_name, short_name}, last_heard
Lmt_node:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
1:  mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lpb_next
    tbnz x0, #63, 9f
    cbz  x0, 8f
    mov  x20, x4
    cmp  x0, #1
    b.ne 2f
    cbnz x1, 1b
    SETF x2, MT_NUM, 5
    b    1b
2:  cmp  x0, #5
    b.ne 3f
    cmp  x1, #5
    b.ne 1b
    SETF x2, MT_SEEN, 10
    b    1b
3:  cmp  x0, #2
    b.ne 1b
    cmp  x1, #2
    b.ne 1b
    mov  x0, x19
    mov  x1, x2
    add  x2, x2, x3
    mov  x3, x22
    bl   Lmt_user
    tbnz x0, #63, 9f
    b    1b
8:  mov  x0, #0
    LEAVE 0
9:  mov  x0, #-1
    LEAVE 0

// Lmt_user — User: id, long_name, short_name (strings)
Lmt_user:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
1:  mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lpb_next
    tbnz x0, #63, 9f
    cbz  x0, 8f
    mov  x20, x4
    cmp  x1, #2
    b.ne 1b
    add  x2, x19, x2
    cmp  x0, #1
    b.ne 2f
    str  x3, [x22, #MT_ULEN]
    SETF x2, MT_UID, 9
    b    1b
2:  cmp  x0, #2
    b.ne 3f
    str  x3, [x22, #MT_LLEN]
    SETF x2, MT_LONG, 7
    b    1b
3:  cmp  x0, #3
    b.ne 1b
    str  x3, [x22, #MT_SLEN]
    SETF x2, MT_SHORT, 8
    b    1b
8:  mov  x0, #0
    LEAVE 0
9:  mov  x0, #-1
    LEAVE 0

// Lmt_channel — Channel: index, settings {name}, role
Lmt_channel:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
1:  mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lpb_next
    tbnz x0, #63, 9f
    cbz  x0, 8f
    mov  x20, x4
    cmp  x0, #1
    b.ne 2f
    cbnz x1, 1b
    SETF x2, MT_NUM, 5
    b    1b
2:  cmp  x0, #3
    b.ne 3f
    cbnz x1, 1b
    SETF x2, MT_ROLE, 11
    b    1b
3:  cmp  x0, #2
    b.ne 1b
    cmp  x1, #2
    b.ne 1b
    mov  x0, x19
    mov  x1, x2
    add  x2, x2, x3
    mov  x3, x22
    bl   Lmt_chset
    tbnz x0, #63, 9f
    b    1b
8:  mov  x0, #0
    LEAVE 0
9:  mov  x0, #-1
    LEAVE 0

// Lmt_chset — ChannelSettings: name
Lmt_chset:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
1:  mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lpb_next
    tbnz x0, #63, 9f
    cbz  x0, 8f
    mov  x20, x4
    cmp  x0, #3
    b.ne 1b
    cmp  x1, #2
    b.ne 1b
    add  x2, x19, x2
    str  x3, [x22, #MT_LLEN]
    SETF x2, MT_LONG, 7
    b    1b
8:  mov  x0, #0
    LEAVE 0
9:  mov  x0, #-1
    LEAVE 0

// ---------------------------------------------------------------------------
// self-tests 237-238, called from test.s (vectors from tools/meshcore/mt.py vectors)

.globl _mt_core_selftest
_mt_core_selftest:
    ENTER 512                             // [96] a message (256)  [352] mt (144)
    mov  x19, #0
    // 237. what we send, byte for byte; and the allowlist
    mov  x20, #1
    add  x0, sp, #96
    mov  w1, #0x5678
    movk w1, #0x1234, lsl #16
    bl   _mt_want_config
    mov  x21, x0
    add  x0, sp, #96
    ADRL x1, Lv_config
    mov  x2, #6
    bl   Lmt_is
    cmp  x21, #6
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #96
    bl   _mt_heartbeat
    add  x0, sp, #96
    ADRL x1, Lv_heart
    mov  x2, #2
    bl   Lmt_is
    add  x0, sp, #96                      // to everyone, channel 0, no ack
    mov  w1, #-1
    mov  x2, #0
    mov  w3, #0xC3D4
    movk w3, #0xA1B2, lsl #16
    ADRL x4, Lv_hiall
    mov  x5, #6
    mov  x6, #0
    bl   _mt_send_text
    mov  x21, x0
    add  x0, sp, #96
    ADRL x1, Lv_text
    mov  x2, #24
    bl   Lmt_is
    cmp  x21, #24
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #96                      // to one node, channel 1, with an ack
    mov  w1, #0x0C0D
    movk w1, #0x0A0B, lsl #16
    mov  x2, #1
    mov  w3, #7
    ADRL x4, Lv_hello
    mov  x5, #6
    mov  x6, #1
    bl   _mt_send_text
    mov  x21, x0
    add  x0, sp, #96
    ADRL x1, Lv_dm
    mov  x2, #28
    bl   Lmt_is
    cmp  x21, #28
    cset x9, eq
    and  x20, x20, x9
    ADRL x21, Lv_allow                    // cases: length, allowed?, message
1:  ldrb w22, [x21]
    cbz  w22, 2f
    add  x0, x21, #2
    mov  x1, x22
    bl   _mt_allowed
    ldrb w9, [x21, #1]
    cmp  x0, x9
    cset x9, eq
    and  x20, x20, x9
    add  x21, x21, #2
    add  x21, x21, x22
    b    1b
2:  mov  w1, w20
    ADRL x0, Ln_237
    bl   _t_report
    add  x19, x19, x0
    // 238. what the radio sends: a text packet, a node's names, the done id; malformed refused
    mov  x20, #1
    ADRL x0, Lv_rx_text
    mov  x1, #29
    add  x2, sp, #352
    bl   _mt_parse
    cmp  x0, #MTK_PACKET
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MT_FROM)]
    cmp  x9, #0x11
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MT_PORT)]
    cmp  x9, #1
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MT_TLEN)]
    cmp  x9, #2
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MT_TEXT)]
    ldrh w9, [x9]
    mov  w10, #0x6F79                     // "yo"
    cmp  w9, w10
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lv_rx_node
    mov  x1, #21
    add  x2, sp, #352
    bl   _mt_parse
    cmp  x0, #MTK_NODE
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MT_NUM)]
    cmp  x9, #0x2A
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MT_LLEN)]
    cmp  x9, #4
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MT_SLEN)]
    cmp  x9, #2
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lv_rx_done
    mov  x1, #2
    add  x2, sp, #352
    bl   _mt_parse
    cmp  x0, #MTK_DONE
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MT_NUM)]
    cmp  x9, #0x45
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #96                      // an empty read: nothing (0)
    mov  x1, #0
    add  x2, sp, #352
    bl   _mt_parse
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    ADRL x21, Lv_bad                      // malformed: length, message
3:  ldrb w22, [x21]
    cbz  w22, 4f
    add  x0, x21, #1
    mov  x1, x22
    add  x2, sp, #352
    bl   _mt_parse
    cmn  x0, #1
    cset x9, eq
    and  x20, x20, x9
    add  x21, x21, #1
    add  x21, x21, x22
    b    3b
4:  mov  w1, w20
    ADRL x0, Ln_238
    bl   _t_report
    add  x19, x19, x0
    mov  x0, x19
    LEAVE 512

// Lmt_is(x0 a, x1 b, x2 n) — x20 &= (n bytes the same) (leaf)
Lmt_is:
    cbz  x2, 2f
1:  ldrb w9, [x0], #1
    ldrb w10, [x1], #1
    cmp  w9, w10
    b.ne 3f
    subs x2, x2, #1
    b.ne 1b
2:  ret
3:  mov  x20, #0
    ret

// ---------------------------------------------------------------------------
.section __TEXT,__const
Lv_config:  .byte 0x18, 0xf8, 0xac, 0xd1, 0x91, 0x01
Lv_heart:   .byte 0x3a, 0x00
Lv_hiall:   .ascii "hi all"
Lv_text:    .byte 0x0a, 0x16, 0x15, 0xff, 0xff, 0xff, 0xff, 0x22, 0x0a, 0x08, 0x01, 0x12, 0x06
            .ascii "hi all"
            .byte 0x35, 0xd4, 0xc3, 0xb2, 0xa1
Lv_hello:   .byte 0x68, 0xc3, 0xa9, 0x6c, 0x6c, 0x6f              // héllo
Lv_dm:      .byte 0x0a, 0x1a, 0x15, 0x0d, 0x0c, 0x0b, 0x0a, 0x18, 0x01, 0x22, 0x0a, 0x08, 0x01, 0x12, 0x06
            .byte 0x68, 0xc3, 0xa9, 0x6c, 0x6c, 0x6f
            .byte 0x35, 0x07, 0x00, 0x00, 0x00, 0x50, 0x01
// a FromRadio text packet: id 9, packet {from 0x11, to everyone, decoded {port 1, "yo"}}
Lv_rx_text: .byte 0x08, 0x09, 0x12, 0x19, 0x0d, 0x11, 0, 0, 0, 0x15, 0xff, 0xff, 0xff, 0xff
            .byte 0x22, 0x06, 0x08, 0x01, 0x12, 0x02, 0x79, 0x6f, 0x35, 1, 2, 3, 4, 0x48, 0x03
// node_info {num 42, user {long "Anna", short "AN"}, last_heard}
Lv_rx_node: .byte 0x22, 0x13, 0x08, 0x2a, 0x12, 0x0a, 0x12, 0x04, 0x41, 0x6e, 0x6e, 0x61, 0x1a, 0x02, 0x41, 0x4e
            .byte 0x2d, 1, 2, 3, 4
Lv_rx_done: .byte 0x38, 0x45
// allowlist cases: length, allowed?, message
Lv_allow:
    .byte 2, 1,  0x18, 0x05                               // want_config
    .byte 2, 1,  0x3a, 0x00                               // heartbeat
    .byte 3, 0,  0x3a, 0x01, 0x00                         //   not empty
    .byte 4, 0,  0x18, 0x05, 0x18, 0x06                   // two fields
    .byte 2, 0,  0x20, 0x01                               // disconnect: not ours to send
    .byte 13, 0, 0x0a, 0x0b, 0x15, 1,0,0,0, 0x22, 0x04, 0x08, 0x06, 0x12, 0x00   // ADMIN_APP: never
    .byte 13, 1, 0x0a, 0x0b, 0x15, 1,0,0,0, 0x22, 0x04, 0x08, 0x01, 0x12, 0x00   // text
    .byte 11, 0, 0x0a, 0x09, 0x15, 1,0,0,0, 0x22, 0x02, 0x12, 0x00               //   no port
    .byte 15, 0, 0x0a, 0x0d, 0x15, 1,0,0,0, 0x22, 0x06, 0x08, 0x01, 0x12, 0x00, 0x18, 0x01   // + want_response
    .byte 15, 0, 0x0a, 0x0d, 0x15, 1,0,0,0, 0x2a, 0x00, 0x22, 0x04, 0x08, 0x01, 0x12, 0x00   // + encrypted
    .byte 16, 0, 0x0a, 0x0e, 0x15, 1,0,0,0, 0x15, 2,0,0,0, 0x22, 0x02, 0x08, 0x01            // to twice
    .byte 15, 0, 0x0a, 0x0d, 0x15, 1,0,0,0, 0x18, 0x08, 0x22, 0x04, 0x08, 0x01, 0x12, 0x00   // channel 8
    .byte 15, 1, 0x0a, 0x0d, 0x15, 1,0,0,0, 0x18, 0x07, 0x22, 0x04, 0x08, 0x01, 0x12, 0x00   // channel 7
    .byte 15, 0, 0x0a, 0x0d, 0x15, 1,0,0,0, 0x48, 0x07, 0x22, 0x04, 0x08, 0x01, 0x12, 0x00   // + hop_limit
    .byte 5, 0,  0x0a, 0x05, 0x15, 1, 0                   // cut short
    .byte 249, 1, 0x0a, 0xf6, 0x01, 0x15, 0x01, 0x00, 0x00, 0x00, 0x22, 0xee, 0x01, 0x08, 0x01, 0x12, 0xe9, 0x01   // a payload of 233 bytes
    .rept 233
    .byte 0x78
    .endr
    .byte 250, 0, 0x0a, 0xf7, 0x01, 0x15, 0x01, 0x00, 0x00, 0x00, 0x22, 0xef, 0x01, 0x08, 0x01, 0x12, 0xea, 0x01   // a payload of 234 bytes: one too many
    .rept 234
    .byte 0x78
    .endr
    .byte 0
// malformed: length, message
Lv_bad:
    .byte 2,  0x12, 0x05                                  // bytes past the end
    .byte 1,  0x08                                        // a varint with no bytes
    .byte 12, 0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01   // 11-byte varint
    .byte 2,  0x0b, 0x00                                  // wire type 3 (groups)
    .byte 2,  0x00, 0x00                                  // field 0
    .byte 4,  0x12, 0x02, 0x0d, 0x01                      // a fixed32 cut short, in a packet
    .byte 3,  0x22, 0x01, 0x12                            // node info: bytes past its end
    .byte 0

.section __TEXT,__cstring,cstring_literals
Ln_237: .asciz "237 meshtastic: messages built byte for byte; only start-up, heartbeat and plain text allowed"
Ln_238: .asciz "238 meshtastic: radio messages read; bad lengths, varints and wire types refused"
