// bc_packet.s — bitchat's packets (docs/bitchat_roadmap.md, Phase 3): reading one, the
// bytes its signature covers, building and signing our own, the duplicate filter and the
// relay rule. Pure functions on caller-owned memory, like bc_link.s, so they run under qemu.
//
// Ported from bitchat 04995f6: BinaryProtocol.swift (decode), BitchatPacket's
// toBinaryDataForSigning, PacketPayloadLimits, CompressionUtil.shouldCompress, MessagePadding,
// RelayController and BLEReceivedPacketContext's message id.
//
//   header   version(1) type(1) ttl(1) time ms(8) flags(1) payload length(2, or 4 in v2)
//   then     sender(8), recipient(8) if flag 1, route if v2 and flag 8 (count, count x 8),
//            [original size (2/4) if flag 4] payload, signature(64) if flag 2, padding
//
// Two things to know:
// - A signature covers the packet as bitchat would encode it again: TTL 0, no signature, no
//   RSR flag, an empty route left out, padded to 256/512/1024/2048. Compression is part of
//   that, so the bytes checked are rebuilt from the wire: what the sender compressed is what
//   it signed.
// - bitchat compresses (Apple's raw DEFLATE) a payload of 100+ bytes with under 90% of its
//   bytes different, and does so again when it checks a signature. We can't promise the
//   same compressed bytes, so _bc_build won't sign such a payload (-2): split or reword it.
//
// Decompression goes through _bc_inflate (bc_zlib.s: libz on the Mac and iPhone; the qemu
// harness brings its own), never past the size the packet declares or the caller's buffer.
// The DEFLATE stream must end, and make exactly that size. That's stricter than bitchat
// (Apple's decoder stops at the declared size), but every real sender's stream ends there.

.include "macros.inc"
.include "bc_defs.inc"

// the test packets' sizes (tools/qemu/bcvectors.py)
.set PK1_N, 256
.set PK2_N, 125
.set PK3_N, 38
.set PK3B_N, 38
.set PK3C_N, 27
.set PK4_N, 256

.text
.p2align 2

// long _bc_decode(const uint8 *p, long n, uint8 *dp, uint8 *buf, long cap) -> 0, or -1 refused.
//   Fills dp (DP_*). A compressed payload is unpacked into buf (at most cap bytes); any
//   other payload is left where it is in p. Like bitchat: the frame as it is first, then
//   without its padding; bytes after the packet are ignored.
.globl _bc_decode
_bc_decode:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    bl   Ldec_core
    cbz  x0, Ldc_ok
    cbz  x20, Ldc_bad                     // padding: n bytes of value n at the end
    sub  x9, x20, #1
    ldrb w10, [x19, x9]
    cbz  w10, Ldc_bad
    cmp  x10, x20
    b.hi Ldc_bad
    sub  x24, x20, x10
    mov  x9, x24
1:  cmp  x9, x20
    b.hs 2f
    ldrb w11, [x19, x9]
    cmp  w11, w10
    b.ne Ldc_bad
    add  x9, x9, #1
    b    1b
2:  mov  x0, x19
    mov  x1, x24
    mov  x2, x21
    mov  x3, x22
    mov  x4, x23
    bl   Ldec_core
    LEAVE 0
Ldc_ok:
    mov  x0, #0
    LEAVE 0
Ldc_bad:
    mov  x0, #-1
    LEAVE 0

// long Ldec_core(p, n, dp, buf, cap) -> 0 or -1: BinaryProtocol.decodeCore
Ldec_core:
    ENTER 32                              // [96] buf [104] cap [112] type's cap [120] original size
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    str  x3, [sp, #96]
    str  x4, [sp, #104]
    cmp  x20, #22                         // the smallest: a v1 header and the sender
    b.lo Ldk_bad
    ldrb w9, [x19]
    mov  x22, #14                         // x22: where we are; the header first
    cmp  w9, #1
    b.eq 1f
    cmp  w9, #2
    b.ne Ldk_bad
    mov  x22, #16
1:  str  x9, [x21, #DP_VER]
    add  x10, x22, #8
    cmp  x20, x10
    b.lo Ldk_bad
    ldrb w10, [x19, #1]
    str  x10, [x21, #DP_TYPE]
    ldrb w10, [x19, #2]
    str  x10, [x21, #DP_TTL]
    ldr  x10, [x19, #3]                   // big-endian time
    rev  x10, x10
    str  x10, [x21, #DP_TS]
    ldrb w24, [x19, #11]                  // x24: flags
    str  x24, [x21, #DP_FLAGS]
    cmp  w9, #2
    b.ne 2f
    ldr  w23, [x19, #12]                  // x23: payload length
    rev  w23, w23
    b    3f
2:  ldrh w23, [x19, #12]
    rev16 w23, w23
3:  mov  x10, #(BC_FRAMED & 0xffff)
    movk x10, #(BC_FRAMED >> 16), lsl #16
    cmp  x23, x10
    b.hi Ldk_bad
    add  x10, x19, x22                    // sender
    str  x10, [x21, #DP_SENDER]
    add  x22, x22, #8
    str  xzr, [x21, #DP_RCPT]
    tbz  w24, #0, 4f
    add  x10, x22, #8                     // recipient
    cmp  x10, x20
    b.hi Ldk_bad
    add  x11, x19, x22
    str  x11, [x21, #DP_RCPT]
    mov  x22, x10
4:  str  xzr, [x21, #DP_HOPS]
    str  xzr, [x21, #DP_ROUTE]
    ldr  x9, [x21, #DP_VER]
    cmp  x9, #2                           // a route only counts in v2
    b.ne 5f
    tbz  w24, #3, 5f
    cmp  x22, x20
    b.hs Ldk_bad
    ldrb w10, [x19, x22]
    add  x22, x22, #1
    str  x10, [x21, #DP_HOPS]
    add  x11, x19, x22
    str  x11, [x21, #DP_ROUTE]
    add  x22, x22, x10, lsl #3
    cmp  x22, x20
    b.hi Ldk_bad
5:  ldr  x0, [x21, #DP_TYPE]
    bl   Ltype_cap
    str  x0, [sp, #112]
    tbz  w24, #2, Ldk_plain
    // compressed: the original size, then DEFLATE
    ldr  x9, [x21, #DP_VER]
    mov  x10, #2                          // size field: 2 bytes, 4 in v2
    cmp  x9, #2
    mov  x11, #4
    csel x10, x11, x10, eq
    cmp  x23, x10
    b.lo Ldk_bad
    add  x11, x22, x10
    cmp  x11, x20
    b.hi Ldk_bad
    cmp  x10, #4
    b.ne 6f
    ldr  w12, [x19, x22]
    rev  w12, w12
    b    7f
6:  ldrh w12, [x19, x22]
    rev16 w12, w12
7:  mov  x22, x11
    ldr  x13, [sp, #112]
    cmp  x12, x13
    b.hi Ldk_bad
    ldr  x13, [sp, #104]                  // and what our buffer holds
    cmp  x12, x13
    b.hi Ldk_bad
    cbz  x12, Ldk_bad
    sub  x14, x23, x10                    // compressed bytes
    cbz  x14, Ldk_bad
    add  x15, x22, x14
    cmp  x15, x20
    b.hi Ldk_bad
    mov  x16, #BC_RATIO
    mul  x16, x14, x16
    cmp  x12, x16
    b.hi Ldk_bad
    str  x12, [sp, #120]
    mov  x23, x14
    ldr  x0, [sp, #96]
    mov  x1, x12
    add  x2, x19, x22
    mov  x3, x14
    bl   _bc_inflate
    ldr  x12, [sp, #120]
    cmp  x0, x12
    b.ne Ldk_bad
    ldr  x9, [sp, #96]
    str  x9, [x21, #DP_PAY]
    str  x12, [x21, #DP_PLEN]
    add  x22, x22, x23
    b    Ldk_sig
Ldk_plain:
    ldr  x13, [sp, #112]
    cmp  x23, x13
    b.hi Ldk_bad
    add  x10, x22, x23
    cmp  x10, x20
    b.hi Ldk_bad
    add  x11, x19, x22
    str  x11, [x21, #DP_PAY]
    str  x23, [x21, #DP_PLEN]
    mov  x22, x10
Ldk_sig:
    str  x22, [x21, #DP_SIGAT]
    str  xzr, [x21, #DP_SIG]
    tbz  w24, #1, 8f
    add  x10, x22, #64
    cmp  x10, x20
    b.hi Ldk_bad
    add  x11, x19, x22
    str  x11, [x21, #DP_SIG]
8:  str  x19, [x21, #DP_WIRE]
    mov  x0, #0
    LEAVE 32
Ldk_bad:
    mov  x0, #-1
    LEAVE 32

// long Ltype_cap(long type) -> the most payload bitchat takes for it (PacketPayloadLimits)
Ltype_cap:
    cmp  x0, #0x22                        // files, private
    b.eq 1f
    cmp  x0, #0x11
    b.eq 1f
    cmp  x0, #0x02                        // messages
    b.eq 2f
    cmp  x0, #0x25
    b.eq 2f
    cmp  x0, #0x04                        // courier, Nostr
    b.eq 3f
    cmp  x0, #0x28
    b.eq 3f
    mov  x1, #8192                        // sync requests
    cmp  x0, #0x21
    b.eq 9f
    mov  x1, #1280                        // fragments
    cmp  x0, #0x20
    b.eq 9f
    mov  x1, #4096                        // control packets
    cmp  x0, #0x01
    b.eq 9f
    cmp  x0, #0x2c
    b.eq 9f
    cmp  x0, #0x03
    b.eq 9f
    cmp  x0, #0x10
    b.eq 9f
    sub  x9, x0, #0x23                    // 0x23, 0x24, 0x26, 0x27, 0x29
    cmp  x9, #6
    b.hi 2f
    cmp  x9, #2                           // 0x25 is a message
    b.ne 9f
2:  mov  x1, #0x20000                     // messages, and types we don't know
    b    9f
3:  mov  x1, #0x10000
    b    9f
1:  mov  x1, #(BC_FRAMED & 0xffff)
    movk x1, #(BC_FRAMED >> 16), lsl #16
9:  mov  x0, x1
    ret

// void Lcopy(dst, src, n) — bytes, forwards (leaf: x9, x10 only)
Lcopy:
    mov  x9, #0
1:  cmp  x9, x2
    b.hs 2f
    ldrb w10, [x1, x9]
    strb w10, [x0, x9]
    add  x9, x9, #1
    b    1b
2:  ret

// long Lpad(uint8 *p, long n, long cap) -> the length padded as bitchat pads (MessagePadding:
//   up to the first of 256/512/1024/2048 with 16 bytes to spare, when that's at most 255
//   bytes), or -1 if that doesn't fit in cap (leaf)
Lpad:
    add  x9, x1, #16
    mov  x10, #256
1:  cmp  x9, x10
    b.ls 2f
    lsl  x10, x10, #1
    cmp  x10, #2048
    b.ls 1b
    mov  x0, x1                           // too big for any block: as it is
    ret
2:  sub  x11, x10, x1                     // padding bytes, each holding their count
    cmp  x11, #255
    b.hi 4f
    cmp  x10, x2
    b.hi 5f
3:  cmp  x1, x10
    b.hs 4f
    strb w11, [x0, x1]
    add  x1, x1, #1
    b    3b
4:  mov  x0, x1
    ret
5:  mov  x0, #-1
    ret

// long _bc_sign_data(const uint8 *dp, uint8 *out, long cap) -> the length of what the
//   packet's signature covers (toBinaryDataForSigning), -1 if it doesn't fit in cap
.globl _bc_sign_data
_bc_sign_data:
    ENTER 16                              // [96] where we are in the frame
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ldr  x22, [x19, #DP_WIRE]
    ldr  x23, [x19, #DP_SIGAT]
    cmp  x23, x21                         // never longer than the frame, before padding
    b.hi Lsd_bad
    ldr  x9, [x19, #DP_VER]
    mov  x10, #14
    cmp  x9, #2
    mov  x11, #16
    csel x10, x11, x10, eq
    add  x10, x10, #8                     // header and sender
    ldr  x11, [x19, #DP_RCPT]
    mov  x24, #0                          // x24: flags it was signed with
    cbz  x11, 1f
    add  x10, x10, #8
    mov  x24, #1
1:  str  x10, [sp, #96]
    mov  x0, x20
    mov  x1, x22
    mov  x2, x10
    bl   Lcopy
    strb wzr, [x20, #2]                   // TTL 0
    ldr  x9, [x19, #DP_FLAGS]
    and  x9, x9, #4                       // compressed stays
    orr  x24, x24, x9
    ldr  x10, [sp, #96]                   // x10: in the frame; x11: in out
    mov  x11, x10
    ldr  x9, [x19, #DP_VER]
    cmp  x9, #2
    b.ne 2f
    ldr  x9, [x19, #DP_FLAGS]
    tbz  w9, #3, 2f
    ldrb w12, [x22, x10]                  // a route: kept unless it's empty
    lsl  x13, x12, #3
    add  x13, x13, #1
    cbz  x12, 3f
    orr  x24, x24, #8
    str  x13, [sp, #104]
    add  x0, x20, x11
    add  x1, x22, x10
    mov  x2, x13
    bl   Lcopy
    ldr  x13, [sp, #104]
    ldr  x10, [sp, #96]
    add  x11, x10, x13
3:  add  x10, x10, x13
2:  str  x11, [sp, #104]
    add  x0, x20, x11                     // the rest: original size, payload
    add  x1, x22, x10
    sub  x2, x23, x10
    bl   Lcopy
    ldr  x11, [sp, #104]
    ldr  x10, [sp, #96]
    ldr  x9, [x19, #DP_VER]               // (frame position again, past any route)
    cmp  x9, #2
    b.ne 4f
    ldr  x9, [x19, #DP_FLAGS]
    tbz  w9, #3, 4f
    ldrb w12, [x22, x10]
    lsl  x13, x12, #3
    add  x10, x10, x13
    add  x10, x10, #1
4:  sub  x2, x23, x10
    add  x1, x11, x2
    strb w24, [x20, #11]
    mov  x0, x20
    mov  x2, x21
    bl   Lpad
    LEAVE 16
Lsd_bad:
    mov  x0, #-1
    LEAVE 16

// long _bc_verify(const uint8 *dp, const uint8 pub[32], uint8 *scratch, long cap) -> 1 if
//   the packet carries a signature and it's good for pub, else 0. scratch: 2048 is plenty
//   for anything up to 2032 bytes.
.globl _bc_verify
_bc_verify:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ldr  x9, [x19, #DP_SIG]
    cbz  x9, 1f
    mov  x1, x21
    mov  x2, x3
    bl   _bc_sign_data
    tbnz x0, #63, 1f
    mov  x2, x0
    mov  x0, x20
    mov  x1, x21
    ldr  x3, [x19, #DP_SIG]
    bl   _bc_ed25519_verify
    LEAVE 0
1:  mov  x0, #0
    LEAVE 0

// long _bc_would_compress(const uint8 *p, long n) -> 1 if bitchat would compress this
//   payload: 100 bytes or more, and fewer different byte values than 90% of min(n, 256)
.globl _bc_would_compress
_bc_would_compress:
    cmp  x1, #100
    b.lo 3f
    sub  sp, sp, #32                      // which byte values we've seen
    stp  xzr, xzr, [sp]
    stp  xzr, xzr, [sp, #16]
    mov  x9, #0
    mov  x10, #0                          // how many different
1:  cmp  x9, x1
    b.hs 2f
    ldrb w11, [x0, x9]
    lsr  x12, x11, #6
    ldr  x13, [sp, x12, lsl #3]
    lsr  x14, x13, x11                    // (shifts by the low 6 bits)
    add  x9, x9, #1
    tbnz x14, #0, 1b
    mov  x14, #1
    lsl  x14, x14, x11
    orr  x13, x13, x14
    str  x13, [sp, x12, lsl #3]
    add  x10, x10, #1
    b    1b
2:  add  sp, sp, #32
    mov  x11, #256
    cmp  x1, x11
    csel x11, x1, x11, lo
    mov  x12, #10
    mul  x10, x10, x12
    mov  x12, #9
    mul  x11, x11, x12
    cmp  x10, x11
    cset x0, lo
    ret
3:  mov  x0, #0
    ret

// long Lenc(dp, out, cap, ttl, sig or 0) -> length, padded, or -1: BinaryProtocol.encode
//   without compression or a route
Lenc:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    ldr  x9, [x19, #DP_VER]
    mov  x24, #14                         // x24: where we are
    cmp  x9, #1
    b.eq 1f
    cmp  x9, #2
    b.ne Len_bad
    mov  x24, #16
1:  ldr  x10, [x19, #DP_PLEN]
    cmp  x9, #1
    b.ne 2f
    mov  x11, #0xffff
    cmp  x10, x11
    b.hi Len_bad
2:  add  x11, x24, #8                     // the whole length must fit
    ldr  x12, [x19, #DP_RCPT]
    cbz  x12, 3f
    add  x11, x11, #8
3:  add  x11, x11, x10
    cbz  x23, 4f
    add  x11, x11, #64
4:  cmp  x11, x21
    b.hi Len_bad
    strb w9, [x20]
    ldr  x10, [x19, #DP_TYPE]
    strb w10, [x20, #1]
    strb w22, [x20, #2]
    ldr  x10, [x19, #DP_TS]
    rev  x10, x10
    str  x10, [x20, #3]
    cmp  x12, #0                          // flags: recipient 1, signature 2
    cset x10, ne
    cmp  x23, #0
    cset x11, ne
    orr  x10, x10, x11, lsl #1
    strb w10, [x20, #11]
    ldr  x10, [x19, #DP_PLEN]
    cmp  x9, #2
    b.ne 5f
    rev  w11, w10
    str  w11, [x20, #12]
    b    6f
5:  rev16 w11, w10
    strh w11, [x20, #12]
6:  add  x0, x20, x24
    ldr  x1, [x19, #DP_SENDER]
    mov  x2, #8
    bl   Lcopy
    add  x24, x24, #8
    ldr  x1, [x19, #DP_RCPT]
    cbz  x1, 7f
    add  x0, x20, x24
    mov  x2, #8
    bl   Lcopy
    add  x24, x24, #8
7:  add  x0, x20, x24
    ldr  x1, [x19, #DP_PAY]
    ldr  x2, [x19, #DP_PLEN]
    bl   Lcopy
    ldr  x2, [x19, #DP_PLEN]
    add  x24, x24, x2
    cbz  x23, 8f
    add  x0, x20, x24
    mov  x1, x23
    mov  x2, #64
    bl   Lcopy
    add  x24, x24, #64
8:  mov  x0, x20
    mov  x1, x24
    mov  x2, x21
    bl   Lpad
    LEAVE 0
Len_bad:
    mov  x0, #-1
    LEAVE 0

// long _bc_build(const uint8 *dp, const uint8 *seed or 0, uint8 *out, long cap) -> the
//   packet's length (padded), -1 if it doesn't fit, -2 if bitchat would compress the payload
//   (a signature over it couldn't be checked). Uses DP_VER, TYPE, TTL, TS, SENDER, RCPT,
//   PAY, PLEN. With a seed it's signed (Ed25519) the way bitchat checks.
.globl _bc_build
_bc_build:
    ENTER 64                              // [96] the signature
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, #0
    cbz  x20, 1f
    ldr  x0, [x19, #DP_PAY]
    ldr  x1, [x19, #DP_PLEN]
    bl   _bc_would_compress
    cbnz x0, 2f
    mov  x0, x19                          // what gets signed: TTL 0, no signature, padded
    mov  x1, x21
    mov  x2, x22
    mov  x3, #0
    mov  x4, #0
    bl   Lenc
    tbnz x0, #63, 3f
    mov  x2, x0
    mov  x0, x20
    mov  x1, x21
    add  x3, sp, #96
    bl   _bc_ed25519_sign
    add  x23, sp, #96
1:  mov  x0, x19
    mov  x1, x21
    mov  x2, x22
    ldr  x3, [x19, #DP_TTL]
    mov  x4, x23
    bl   Lenc
    LEAVE 64
2:  mov  x0, #-2
    LEAVE 64
3:  mov  x0, #-1
    LEAVE 64

// long _bc_seen(uint8 *dd, long now_ms, const uint8 *dp) -> 1 if this packet came by in the
//   last 5 minutes, else 0 (and it's remembered). bitchat's id: sender, time, type and the
//   first 4 bytes of SHA-256 of the payload. Fragments aren't meant to go through this.
.globl _bc_seen
_bc_seen:
    ENTER 32                              // [96] SHA-256
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ldr  x0, [x21, #DP_PAY]
    ldr  x1, [x21, #DP_PLEN]
    add  x2, sp, #96
    bl   _bc_sha256
    ldr  x9, [x21, #DP_SENDER]
    ldr  x22, [x9]                        // x22 sender, x23 time, x24 type << 32 | digest
    ldr  x23, [x21, #DP_TS]
    ldr  w24, [sp, #96]
    ldr  x9, [x21, #DP_TYPE]
    orr  x24, x24, x9, lsl #32
    add  x10, x19, #DD_ENT
    mov  x11, #0
    mov  x12, #(DD_AGE & 0xffff)
    movk x12, #(DD_AGE >> 16), lsl #16
1:  cmp  x11, #DD_N
    b.hs 3f
    ldr  x13, [x10, #24]
    cbz  x13, 2f
    sub  x13, x13, #1
    sub  x13, x20, x13                    // its age (a clock going back: very old)
    cmp  x13, x12
    b.hs 2f
    ldp  x13, x14, [x10]
    ldr  x15, [x10, #16]
    cmp  x13, x22
    ccmp x14, x23, #0, eq
    ccmp x15, x24, #0, eq
    b.eq 4f
2:  add  x10, x10, #32
    add  x11, x11, #1
    b    1b
3:  ldr  x9, [x19, #DD_POS]               // new: into the next slot, the oldest
    add  x10, x19, #DD_ENT
    add  x10, x10, x9, lsl #5
    stp  x22, x23, [x10]
    add  x13, x20, #1
    stp  x24, x13, [x10, #16]
    add  x9, x9, #1
    cmp  x9, #DD_N
    csel x9, xzr, x9, hs
    str  x9, [x19, #DD_POS]
    mov  x0, #0
    LEAVE 32
4:  mov  x0, #1
    LEAVE 32

// long _bc_relay(const uint8 *dp, long sent_by_us, long to_us, long links) -> the TTL to
//   pass it on with (0: don't), and in x1, x2 the delay to wait first, in ms (a random
//   point between them). bitchat's RelayController, leaf. Urgent board posts aren't told
//   apart from others (we don't read board posts).
.globl _bc_relay
_bc_relay:
    ldr  x9, [x0, #DP_TYPE]
    ldr  x10, [x0, #DP_TTL]
    ldr  x11, [x0, #DP_RCPT]
    mov  x12, #7                          // at most 7
    cmp  x10, x12
    csel x10, x10, x12, lo
    cmp  x9, #0x21                        // sync requests stay on the link
    b.eq Lrl_no
    cmp  x10, #1
    b.ls Lrl_no
    cbnz x1, Lrl_no
    cbnz x2, Lrl_no
    cmp  x9, #0x10                        // handshakes
    b.ne 1f
    sub  x0, x10, #1
    mov  x1, #10
    mov  x2, #35
    ret
1:  cbz  x11, 2f                          // directed: fragments, private, courier, ping, pong, Nostr
    cmp  x9, #0x20
    b.eq 11f
    cmp  x9, #0x11
    b.eq 11f
    cmp  x9, #0x04
    b.eq 11f
    cmp  x9, #0x26
    b.eq 11f
    cmp  x9, #0x27
    b.eq 11f
    cmp  x9, #0x28
    b.ne 2f
11: sub  x0, x10, #1
    mov  x1, #20
    mov  x2, #60
    ret
2:  cmp  x9, #0x20                        // fragments and voice: 5 with 6+ links
    b.eq 21f
    cmp  x9, #0x29
    b.ne 3f
21: mov  x12, #7
    mov  x13, #5
    cmp  x3, #6
    csel x12, x13, x12, hs
    cmp  x10, x12
    csel x10, x10, x12, lo
    cmp  x10, #1
    b.ls Lrl_no
    sub  x0, x10, #1
    mov  x1, #8
    mov  x2, #25
    ret
3:  cmp  x3, #6                           // everything else
    b.lo 31f
    mov  x12, #5                          //   6+ links: 2 to 5
    b    32f
31: cmp  x3, #2                           //   0-2 links: as it came
    b.ls 33f
    mov  x12, #6                          //   3-5: 2 to 6, announces 7
    cmp  x9, #0x01
    b.ne 32f
    mov  x12, #7
32: cmp  x10, x12
    csel x10, x10, x12, lo
    mov  x12, #2
    cmp  x10, x12
    csel x10, x10, x12, hs
33: sub  x0, x10, #1
    mov  x1, #10                          // wait longer the more links there are
    mov  x2, #40
    cmp  x3, #2
    b.ls 34f
    mov  x1, #60
    mov  x2, #150
    cmp  x3, #5
    b.ls 34f
    mov  x1, #80
    mov  x2, #180
    cmp  x3, #9
    b.ls 34f
    mov  x1, #100
    mov  x2, #220
34: ret
Lrl_no:
    mov  x0, #0
    mov  x1, #0
    mov  x2, #0
    ret

// ---------------------------------------------------------------------------
// self-tests 155-164, called from test.s

.macro BP_AND
    cset x9, eq
    and  x20, x20, x9
.endm

.macro BP_REPORT name
    mov  w1, w20
    ADRL x0, \name
    bl   _t_report
    add  x19, x19, x0
.endm

// x0 = _bc_decode(vector, n, dp x21, buf x22, 8192)
.macro DECODE vec, n
    ADRL x0, \vec
    mov  x1, #\n
    mov  x2, x21
    mov  x3, x22
    mov  x4, #8192
    bl   _bc_decode
.endm

// flags eq when dp field \f holds \v (x9, x10 free)
.macro FIELD f, v
    ldr  x9, [x21, #\f]
    mov  x10, #\v
    cmp  x9, x10
.endm

// long _bc_packet_selftest(void) -> number of failures
.globl _bc_packet_selftest
_bc_packet_selftest:
    ENTER 16                              // [96] x25 [104] x26
    stp  x25, x26, [sp, #96]
    mov  x19, #0
    mov  x0, #1                           // a decoded packet, a payload buffer, an output, a filter
    mov  x1, #DP_SIZE
    bl   _calloc
    mov  x21, x0
    mov  x0, #1
    mov  x1, #8192
    bl   _calloc
    mov  x22, x0
    mov  x0, #1
    mov  x1, #4096
    bl   _calloc
    mov  x23, x0
    mov  x0, #1
    mov  x1, #(DD_SIZE & 0xffff)
    bl   _calloc
    mov  x24, x0

    // 155. a public message: every field, the padding ignored
    DECODE Lv_pk1, PK1_N
    cmp  x0, #0
    cset x20, eq
    FIELD DP_VER, 1
    BP_AND
    FIELD DP_TYPE, 2
    BP_AND
    FIELD DP_TTL, 7
    BP_AND
    ldr  x9, [x21, #DP_TS]
    ADRL x10, Lv_ts
    ldr  x10, [x10]
    cmp  x9, x10
    BP_AND
    FIELD DP_RCPT, 0
    BP_AND
    FIELD DP_SIG, 0
    BP_AND
    FIELD DP_PLEN, 13
    BP_AND
    ldr  x0, [x21, #DP_PAY]
    ADRL x1, Lv_hello
    mov  x2, #13
    bl   _bc_memeq
    cmp  x0, #1
    BP_AND
    ldr  x0, [x21, #DP_SENDER]
    ADRL x1, Lv_pk1
    add  x1, x1, #14
    mov  x2, #8
    bl   _bc_memeq
    cmp  x0, #1
    BP_AND
    BP_REPORT Ln_bp155

    // 156. v2, to someone, a route of two, signed: where everything is
    DECODE Lv_pk2, PK2_N
    cmp  x0, #0
    cset x20, eq
    FIELD DP_VER, 2
    BP_AND
    FIELD DP_TYPE, 0x11
    BP_AND
    FIELD DP_HOPS, 2
    BP_AND
    FIELD DP_PLEN, 12
    BP_AND
    ADRL x25, Lv_pk2
    ldr  x9, [x21, #DP_RCPT]
    sub  x9, x9, x25
    cmp  x9, #24
    BP_AND
    ldr  x9, [x21, #DP_ROUTE]
    sub  x9, x9, x25
    cmp  x9, #33
    BP_AND
    ldr  x9, [x21, #DP_PAY]
    sub  x9, x9, x25
    cmp  x9, #49
    BP_AND
    ldr  x9, [x21, #DP_SIG]
    sub  x9, x9, x25
    cmp  x9, #61
    BP_AND
    BP_REPORT Ln_bp156

    // 157. compressed: unpacked; the wrong size and an impossible ratio are refused
    DECODE Lv_pk3, PK3_N
    cmp  x0, #0
    cset x20, eq
    FIELD DP_PLEN, 320
    BP_AND
    ldr  x9, [x21, #DP_PAY]
    cmp  x9, x22
    BP_AND
    mov  x25, #0                          // "bitchat " forty times
1:  cmp  x25, #320
    b.hs 2f
    add  x0, x22, x25
    ADRL x1, Lv_word
    mov  x2, #8
    bl   _bc_memeq
    add  x25, x25, #8
    cmp  x0, #1
    b.eq 1b
    mov  x20, #0
2:  DECODE Lv_pk3b, PK3B_N
    cmn  x0, #1
    BP_AND
    DECODE Lv_pk3c, PK3C_N
    cmn  x0, #1
    BP_AND
    ADRL x0, Lv_pk3                       // nor if it doesn't fit our buffer
    mov  x1, #PK3_N
    mov  x2, x21
    mov  x3, x22
    mov  x4, #319
    bl   _bc_decode
    cmn  x0, #1
    BP_AND
    BP_REPORT Ln_bp157

    // 158. refused: every cut-short copy, version 3, a fragment over 1280, too long for anything
    mov  x20, #1
    mov  x25, #0
3:  cmp  x25, #PK2_N
    b.hs 4f
    ADRL x0, Lv_pk2
    mov  x1, x25
    mov  x2, x21
    mov  x3, x22
    mov  x4, #8192
    bl   _bc_decode
    add  x25, x25, #1
    cmn  x0, #1
    b.eq 3b
    mov  x20, #0
4:  mov  x0, x23
    ADRL x1, Lv_pk1
    mov  x2, #PK1_N
    bl   Lcopy
    mov  w9, #3
    strb w9, [x23]
    mov  x0, x23
    mov  x1, #PK1_N
    mov  x2, x21
    mov  x3, x22
    mov  x4, #8192
    bl   _bc_decode
    cmn  x0, #1
    BP_AND
    mov  w9, #1                           // v1, a fragment saying 1281 bytes, all there
    strb w9, [x23]
    mov  w9, #0x20
    strb w9, [x23, #1]
    mov  w9, #0x05
    strb w9, [x23, #12]
    mov  w9, #0x01
    strb w9, [x23, #13]
    mov  x0, x23
    mov  x1, #1400
    mov  x2, x21
    mov  x3, x22
    mov  x4, #8192
    bl   _bc_decode
    cmn  x0, #1
    BP_AND
    mov  x0, x23                          // v2 saying 2 MB
    ADRL x1, Lv_pk2
    mov  x2, #PK2_N
    bl   Lcopy
    mov  w9, #0x20
    strb w9, [x23, #13]
    mov  x0, x23
    mov  x1, #PK2_N
    mov  x2, x21
    mov  x3, x22
    mov  x4, #8192
    bl   _bc_decode
    cmn  x0, #1
    BP_AND
    BP_REPORT Ln_bp158

    // 159. a signature checks out, with the TTL and RSR flag changed in between;
    //      not with a byte of the payload changed, or for another key
    mov  x0, x23
    ADRL x1, Lv_pk2
    mov  x2, #PK2_N
    bl   Lcopy
    mov  w9, #2                           // relays lowered the TTL and set RSR
    strb w9, [x23, #2]
    ldrb w9, [x23, #11]
    orr  w9, w9, #0x10
    strb w9, [x23, #11]
    mov  x0, x23
    mov  x1, #PK2_N
    mov  x2, x21
    mov  x3, x22
    mov  x4, #8192
    bl   _bc_decode
    cmp  x0, #0
    cset x20, eq
    mov  x0, x21
    ADRL x1, Lv_pub
    mov  x2, x22
    mov  x3, #4096
    bl   _bc_verify
    cmp  x0, #1
    BP_AND
    mov  x0, x21
    ADRL x1, Lv_pk1                       // someone else's key
    mov  x2, x22
    mov  x3, #4096
    bl   _bc_verify
    cmp  x0, #0
    BP_AND
    ldrb w9, [x23, #50]
    eor  w9, w9, #1
    strb w9, [x23, #50]
    mov  x0, x21
    ADRL x1, Lv_pub
    mov  x2, x22
    mov  x3, #4096
    bl   _bc_verify
    cmp  x0, #0
    BP_AND
    BP_REPORT Ln_bp159

    // 160. one we build and sign is byte for byte what bitchat makes, and checks out
    mov  x0, x21
    mov  x1, #DP_SIZE
    bl   Lzero
    mov  x9, #1
    str  x9, [x21, #DP_VER]
    mov  x9, #2
    str  x9, [x21, #DP_TYPE]
    mov  x9, #7
    str  x9, [x21, #DP_TTL]
    ADRL x9, Lv_ts
    ldr  x9, [x9]
    str  x9, [x21, #DP_TS]
    ADRL x9, Lv_pk1                       // the same sender
    add  x9, x9, #14
    str  x9, [x21, #DP_SENDER]
    ADRL x9, Lv_hi
    str  x9, [x21, #DP_PAY]
    mov  x9, #15
    str  x9, [x21, #DP_PLEN]
    mov  x0, x21
    ADRL x1, Lv_seed
    mov  x2, x23
    mov  x3, #4096
    bl   _bc_build
    cmp  x0, #PK4_N
    cset x20, eq
    mov  x0, x23
    ADRL x1, Lv_pk4
    mov  x2, #PK4_N
    bl   _bc_memeq
    cmp  x0, #1
    BP_AND
    mov  x0, x23
    mov  x1, #PK4_N
    mov  x2, x21
    mov  x3, x22
    mov  x4, #8192
    bl   _bc_decode
    cmp  x0, #0
    BP_AND
    mov  x0, x21
    ADRL x1, Lv_pub
    mov  x2, x22
    mov  x3, #4096
    bl   _bc_verify
    cmp  x0, #1
    BP_AND
    BP_REPORT Ln_bp160

    // 161. what bitchat would compress: not signed; short or varied payloads are fine
    mov  x0, x22                          // 120 x 'a'
    mov  x1, #120
    mov  w2, #0x61
    bl   Lfill
    mov  x0, x22
    mov  x1, #120
    bl   _bc_would_compress
    cmp  x0, #1
    cset x20, eq
    mov  x0, x22
    mov  x1, #99
    bl   _bc_would_compress
    cmp  x0, #0
    BP_AND
    mov  x25, #0                          // 0, 1, ... 119: all different
5:  strb w25, [x22, x25]
    add  x25, x25, #1
    cmp  x25, #120
    b.lo 5b
    mov  x0, x22
    mov  x1, #120
    bl   _bc_would_compress
    cmp  x0, #0
    BP_AND
    mov  x0, x22                          // 120 x 'a', signed: refused
    mov  x1, #120
    mov  w2, #0x61
    bl   Lfill
    str  x22, [x21, #DP_PAY]
    mov  x9, #120
    str  x9, [x21, #DP_PLEN]
    mov  x0, x21
    ADRL x1, Lv_seed
    mov  x2, x23
    mov  x3, #4096
    bl   _bc_build
    cmn  x0, #2
    BP_AND
    mov  x0, x21                          //   unsigned it goes as it is
    mov  x1, #0
    mov  x2, x23
    mov  x3, #4096
    bl   _bc_build
    cmp  x0, #256
    BP_AND
    BP_REPORT Ln_bp161

    // 162. the duplicate filter: seen once, then a duplicate; another payload at the
    //      same time is new; 5 minutes later it's new again
    DECODE Lv_pk1, PK1_N
    mov  x0, x24
    mov  x1, #1000
    mov  x2, x21
    bl   _bc_seen
    cmp  x0, #0
    cset x20, eq
    mov  x0, x24
    mov  x1, #2000
    mov  x2, x21
    bl   _bc_seen
    cmp  x0, #1
    BP_AND
    ADRL x9, Lv_hi
    str  x9, [x21, #DP_PAY]
    mov  x0, x24
    mov  x1, #3000
    mov  x2, x21
    bl   _bc_seen
    cmp  x0, #0
    BP_AND
    DECODE Lv_pk1, PK1_N
    mov  x0, x24
    mov  x1, #(301000 & 0xffff)
    movk x1, #(301000 >> 16), lsl #16
    mov  x2, x21
    bl   _bc_seen
    cmp  x0, #0
    BP_AND
    BP_REPORT Ln_bp162

    // 163. it keeps the last 1000: the first of 1001 is forgotten, the last isn't
    mov  x0, x24
    mov  x1, #(DD_SIZE & 0xffff)
    bl   Lzero
    mov  x20, #1
    mov  x25, #0
6:  cmp  x25, #1001
    b.hs 7f
    DECODE Lv_pk1, PK1_N
    str  x25, [x21, #DP_TS]
    mov  x0, x24
    mov  x1, #5000
    mov  x2, x21
    bl   _bc_seen
    add  x25, x25, #1
    cbz  x0, 6b
    mov  x20, #0
7:  str  xzr, [x21, #DP_TS]
    mov  x0, x24
    mov  x1, #5000
    mov  x2, x21
    bl   _bc_seen
    cmp  x0, #0
    BP_AND
    mov  x9, #1000
    str  x9, [x21, #DP_TS]
    mov  x0, x24
    mov  x1, #5000
    mov  x2, x21
    bl   _bc_seen
    cmp  x0, #1
    BP_AND
    BP_REPORT Ln_bp163

    // 164. the relay rule, case by case (Lv_relay: type, TTL, to someone, sent by us,
    //      to us, links, then the TTL, shortest and longest wait expected)
    mov  x20, #1
    ADRL x25, Lv_relay
8:  ldrb w9, [x25]
    cbz  w9, 9f
    str  x9, [x21, #DP_TYPE]
    ldrb w9, [x25, #1]
    str  x9, [x21, #DP_TTL]
    ldrb w9, [x25, #2]
    str  x9, [x21, #DP_RCPT]              // only zero or not is looked at
    mov  x0, x21
    ldrb w1, [x25, #3]
    ldrb w2, [x25, #4]
    ldrb w3, [x25, #5]
    bl   _bc_relay
    ldrb w9, [x25, #6]
    ldrb w10, [x25, #7]
    ldrb w11, [x25, #8]
    cmp  x0, x9
    ccmp x1, x10, #0, eq
    ccmp x2, x11, #0, eq
    BP_AND
    add  x25, x25, #9
    b    8b
9:  BP_REPORT Ln_bp164

    ldp  x25, x26, [sp, #96]
    mov  x0, x19
    LEAVE 16

// void Lzero(p, n), Lfill(p, n, byte) (leaf)
Lzero:
    mov  w2, #0
Lfill:
    mov  x9, #0
1:  cmp  x9, x1
    b.hs 2f
    strb w2, [x0, x9]
    add  x9, x9, #1
    b    1b
2:  ret

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lv_ts:      .quad 0x0000019a2f3c4d5e
Lv_hello:   .ascii "hello bitchat"
Lv_hi:      .ascii "hi from asmmesh"
Lv_word:    .ascii "bitchat "

// type, TTL, to someone, sent by us, to us, links -> TTL, wait from, to
Lv_relay:
    .byte 0x21, 7, 0, 0, 0, 1,   0, 0, 0        // sync requests: never
    .byte 0x02, 1, 0, 0, 0, 1,   0, 0, 0        // TTL 1: no further
    .byte 0x02, 7, 0, 1, 0, 1,   0, 0, 0        // our own
    .byte 0x11, 7, 1, 0, 1, 1,   0, 0, 0        // for us
    .byte 0x10, 9, 0, 0, 0, 8,   6, 10, 35      // handshake: TTL 7 at most, then one less
    .byte 0x11, 3, 1, 0, 0, 8,   2, 20, 60      // private, to someone else
    .byte 0x20, 7, 0, 0, 0, 7,   4, 8, 25       // a fragment with 6+ links: 5 at most
    .byte 0x20, 7, 0, 0, 0, 2,   6, 8, 25
    .byte 0x20, 7, 1, 0, 0, 7,   6, 20, 60      // a fragment to someone: deterministic
    .byte 0x02, 7, 0, 0, 0, 1,   6, 10, 40      // public, few links: as it came
    .byte 0x02, 7, 0, 0, 0, 4,   5, 60, 150     // 3-5 links: 6 at most
    .byte 0x01, 7, 0, 0, 0, 4,   6, 60, 150     // announces: 7
    .byte 0x02, 7, 0, 0, 0, 8,   4, 80, 180     // 6+ links: 5
    .byte 0x02, 2, 0, 0, 0, 12,  1, 100, 220    // but never under 2
    .byte 0x02, 3, 0, 0, 0, 4,   2, 60, 150
    .byte 0

Ln_bp155:   .asciz "155 bitchat packet: a public message is read, padding and all"
Ln_bp156:   .asciz "156 bitchat packet: v2 with recipient, route and signature is read"
Ln_bp157:   .asciz "157 bitchat packet: compressed is unpacked; a wrong size or ratio is refused"
Ln_bp158:   .asciz "158 bitchat packet: cut short, version 3, too big are refused"
Ln_bp159:   .asciz "159 bitchat packet: a signature checks out after relaying, not if changed"
Ln_bp160:   .asciz "160 bitchat packet: one we sign is byte for byte bitchat's"
Ln_bp161:   .asciz "161 bitchat packet: a payload bitchat would compress isn't signed"
Ln_bp162:   .asciz "162 bitchat packet: a duplicate is caught, for 5 minutes"
Ln_bp163:   .asciz "163 bitchat packet: the duplicate filter keeps the last 1000"
Ln_bp164:   .asciz "164 bitchat packet: when and how far to relay, as bitchat does"

// made by tools/qemu/bcvectors.py
// 155: v1 public message "hello bitchat", padded (256 bytes)
Lv_pk1:
    .byte 0x01, 0x02, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x2f, 0x3c, 0x4d, 0x5e, 0x00, 0x00, 0x0d, 0x11, 0x12
    .byte 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x62, 0x69, 0x74, 0x63
    .byte 0x68, 0x61, 0x74, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
    .byte 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd, 0xdd
// 156: v2, recipient, route of 2, payload "sealed bytes", signed with Lv_seed (125 bytes)
Lv_pk2:
    .byte 0x02, 0x11, 0x05, 0x00, 0x00, 0x01, 0x9a, 0x2f, 0x3c, 0x4d, 0x5e, 0x0b, 0x00, 0x00, 0x00, 0x0c
    .byte 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8
    .byte 0x02, 0xc1, 0xc1, 0xc1, 0xc1, 0xc1, 0xc1, 0xc1, 0xc1, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2, 0xc2
    .byte 0xc2, 0x73, 0x65, 0x61, 0x6c, 0x65, 0x64, 0x20, 0x62, 0x79, 0x74, 0x65, 0x73, 0x27, 0x82, 0xd3
    .byte 0x97, 0x8b, 0x13, 0x3a, 0x30, 0x93, 0xd1, 0xa2, 0x41, 0x3f, 0xd3, 0x17, 0x9d, 0xfd, 0x10, 0x09
    .byte 0x94, 0x4a, 0x83, 0x68, 0x73, 0xc4, 0x17, 0x9f, 0x4f, 0xd4, 0xa6, 0x2b, 0x7c, 0x7c, 0x61, 0x32
    .byte 0xb6, 0x2c, 0xf6, 0x75, 0x27, 0x1e, 0xf1, 0x06, 0x96, 0xd6, 0x51, 0x2a, 0x08, 0xd7, 0xc5, 0x86
    .byte 0x60, 0xe6, 0x70, 0x55, 0xda, 0x7b, 0x19, 0x26, 0xcb, 0x2f, 0x58, 0x48, 0x0f
// 157: v1, "bitchat " x 40 compressed (raw DEFLATE) (38 bytes)
Lv_pk3:
    .byte 0x01, 0x02, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x2f, 0x3c, 0x4d, 0x5e, 0x04, 0x00, 0x10, 0x11, 0x12
    .byte 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x01, 0x40, 0x4b, 0xca, 0x2c, 0x49, 0xce, 0x48, 0x2c, 0x51
    .byte 0x48, 0x1a, 0xa5, 0xc9, 0xa2, 0x01
// 157: the same, saying 321 bytes (38 bytes)
Lv_pk3b:
    .byte 0x01, 0x02, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x2f, 0x3c, 0x4d, 0x5e, 0x04, 0x00, 0x10, 0x11, 0x12
    .byte 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x01, 0x41, 0x4b, 0xca, 0x2c, 0x49, 0xce, 0x48, 0x2c, 0x51
    .byte 0x48, 0x1a, 0xa5, 0xc9, 0xa2, 0x01
// 157: 4000 bytes from 3: impossible (27 bytes)
Lv_pk3c:
    .byte 0x01, 0x02, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x2f, 0x3c, 0x4d, 0x5e, 0x04, 0x00, 0x05, 0x11, 0x12
    .byte 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x0f, 0xa0, 0xed, 0xc1, 0x31
// 160: what _bc_build makes for "hi from asmmesh", signed with Lv_seed (256 bytes)
Lv_pk4:
    .byte 0x01, 0x02, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x2f, 0x3c, 0x4d, 0x5e, 0x02, 0x00, 0x0f, 0x11, 0x12
    .byte 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x68, 0x69, 0x20, 0x66, 0x72, 0x6f, 0x6d, 0x20, 0x61, 0x73
    .byte 0x6d, 0x6d, 0x65, 0x73, 0x68, 0xd5, 0x51, 0xb7, 0xe3, 0x74, 0xe3, 0xc0, 0x72, 0x92, 0x3e, 0xa5
    .byte 0x13, 0x11, 0xb7, 0xcc, 0x04, 0x92, 0xb6, 0x59, 0xde, 0xd6, 0x9c, 0xa0, 0xe8, 0x3f, 0x35, 0xa5
    .byte 0xa4, 0xc4, 0x2e, 0x14, 0x91, 0x82, 0x85, 0xdf, 0xb0, 0x9e, 0x02, 0x33, 0x8a, 0xf7, 0xec, 0xd1
    .byte 0x9c, 0xa8, 0xb0, 0x15, 0xe7, 0x92, 0x1c, 0xe0, 0x37, 0x32, 0x1b, 0x0b, 0xbf, 0x3c, 0xe6, 0x0a
    .byte 0xee, 0xd8, 0x5a, 0xef, 0x05, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
    .byte 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b, 0x9b
// an Ed25519 seed (32 bytes)
Lv_seed:
    .byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
    .byte 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f
// its public key (32 bytes)
Lv_pub:
    .byte 0x03, 0xa1, 0x07, 0xbf, 0xf3, 0xce, 0x10, 0xbe, 0x1d, 0x70, 0xdd, 0x18, 0xe7, 0x4b, 0xc0, 0x99
    .byte 0x67, 0xe4, 0xd6, 0x30, 0x9b, 0xa5, 0x0d, 0x5f, 0x1d, 0xdc, 0x86, 0x64, 0x12, 0x55, 0x31, 0xb8
