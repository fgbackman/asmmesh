// bc_link.s — bitchat's Bluetooth link layer, the parts that only move bytes
// (docs/bitchat_roadmap.md, Phase 2). Pure functions on caller-owned buffers: no
// Objective-C, no globals, so they run under qemu too. bc_ble.s does the radio.
//
// How bitchat uses the link: every ATT write or notification carries one whole
// bitchat packet. A write longer than the MTU arrives in pieces with offsets
// (a long write), and is collected per link until the packet is all there.
// A packet bigger than the link allows is sent as fragment packets (type 0x20)
// whose payload is
//     fragment id (8) | index (2, big-endian) | total (2) | original type (1) | chunk
// and the chunks, joined in index order, are the original packet's bytes.
//
// Everything from a stranger has a cap: 512 bytes per write, FA_N fragment sets
// of at most FA_FRAGS pieces and FA_BYTES bytes, each forgotten after 30 s.

.include "macros.inc"
.include "bc_defs.inc"

.text
.p2align 2

// long _bc_frame_len(const uint8 *p, long n) -> the whole packet's length (header,
//   sender, recipient, route, payload, signature; padding not counted), 0 if more
//   bytes are needed to tell, -1 if this can't be a bitchat packet
.globl _bc_frame_len
_bc_frame_len:
    cbz  x1, Lfl_more
    ldrb w2, [x0]
    cmp  w2, #1
    b.eq Lfl_v1
    cmp  w2, #2
    b.ne Lfl_bad
    mov  x3, #16                          // v2: 4-byte payload length
    cmp  x1, x3
    b.lo Lfl_more
    ldr  w4, [x0, #12]
    rev  w4, w4
    b    Lfl_have
Lfl_v1:
    mov  x3, #14                          // v1: 2-byte payload length
    cmp  x1, x3
    b.lo Lfl_more
    ldrb w4, [x0, #12]
    ldrb w5, [x0, #13]
    orr  x4, x5, x4, lsl #8
Lfl_have:
    mov  x6, #BC_FRAME_CAP
    cmp  x4, x6
    b.hi Lfl_bad
    ldrb w5, [x0, #11]                    // flags
    add  x7, x3, #8                       // sender id
    tst  w5, #1
    b.eq 1f
    add  x7, x7, #8                       // recipient id
1:  cmp  w2, #2                           // a route only counts in v2
    b.ne 2f
    tst  w5, #8
    b.eq 2f
    cmp  x1, x7
    b.ls Lfl_more
    ldrb w8, [x0, x7]
    add  x7, x7, #1
    add  x7, x7, x8, lsl #3
2:  add  x7, x7, x4
    tst  w5, #2
    b.eq 3f
    add  x7, x7, #64                      // signature
3:  mov  x0, x7
    ret
Lfl_more:
    mov  x0, #0
    ret
Lfl_bad:
    mov  x0, #-1
    ret

// long _bc_inbox_put(ib, long offset, const uint8 *p, long n) -> the packet's length
//   when it is complete (it is at ib + IB_DATA, padding and all), 0 while waiting
//   for more, -1 if the write was dropped (too big, or not a bitchat packet).
//   A piece at offset 0 starts a new write. A later piece with nothing waiting (the rest
//   of a write whose packet is already complete, or one whose start was lost or dropped)
//   is ignored: the old bytes must never be read as a packet again. A later piece must
//   start where the last one ended; one that leaves a gap drops the write.
.globl _bc_inbox_put
_bc_inbox_put:
    ENTER 0
    mov  x19, x0
    cbnz x1, 1f
    str  xzr, [x19, #IB_LEN]
1:  cmp  x1, #BC_WRITE_MAX
    b.hi Lib_drop
    cmp  x3, #BC_WRITE_MAX
    b.hi Lib_drop
    add  x9, x1, x3
    cmp  x9, #BC_WRITE_MAX
    b.hi Lib_drop
    cbz  x1, 4f                           // a later piece with nothing waiting: ignored
    ldr  x10, [x19, #IB_LEN]
    cbz  x10, Lib_wait
    cmp  x1, x10                          // and it must follow on, with no gap: bytes left
    b.ne Lib_drop                         //   from an earlier write never join a packet
4:  add  x10, x19, #IB_DATA
    add  x10, x10, x1
    mov  x11, #0
2:  cmp  x11, x3
    b.hs 3f
    ldrb w12, [x2, x11]
    strb w12, [x10, x11]
    add  x11, x11, #1
    b    2b
3:  ldr  x12, [x19, #IB_LEN]
    cmp  x9, x12
    csel x12, x9, x12, hi
    str  x12, [x19, #IB_LEN]
    mov  x20, x12
    add  x0, x19, #IB_DATA
    mov  x1, x20
    bl   _bc_frame_len
    tbnz x0, #63, Lib_drop
    cbz  x0, Lib_wait
    cmp  x0, #BC_WRITE_MAX                // more than one write can hold
    b.hi Lib_drop
    cmp  x0, x20
    b.hi Lib_wait
    str  xzr, [x19, #IB_LEN]              // complete: the next write starts afresh
    mov  x0, x20
    LEAVE 0
Lib_wait:
    mov  x0, #0
    LEAVE 0
Lib_drop:
    str  xzr, [x19, #IB_LEN]
    mov  x0, #-1
    LEAVE 0

// long _bc_frag_put(fa, long now_ms, const uint8 *sender[8], const uint8 *payload,
//   long n, uint8 *out[FA_BYTES], long link) -> the original packet's length when this
//   fragment completes it (its bytes are in out), 0 while waiting (or a repeat), -1 refused.
//   A set belongs to the link its first piece came on: pieces from other links don't join
//   it, and one link has at most FA_PER_LINK sets (a new one evicts its own oldest), so a
//   stranger's link can't push out or poison other phones' sets.
.globl _bc_frag_put
_bc_frag_put:
    ENTER 64                              // [96] id [104] index [112] total [120] type [128] chunk length
    str  x25, [sp, #144]                  //   [136] link + 1 [144] x25
    add  x6, x6, #1
    str  x6, [sp, #136]
    mov  x19, x0
    mov  x20, x1
    ldr  x21, [x2]                        // sender (8 bytes, compared as one word)
    mov  x22, x3
    mov  x23, x4
    mov  x24, x5
    cmp  x23, #BC_FRAG_HDR
    b.ls Lfp_bad                          // no chunk
    ldr  x9, [x22]
    str  x9, [sp, #96]
    ldrb w9, [x22, #8]
    ldrb w10, [x22, #9]
    orr  x9, x10, x9, lsl #8
    str  x9, [sp, #104]
    ldrb w10, [x22, #10]
    ldrb w11, [x22, #11]
    orr  x10, x11, x10, lsl #8
    str  x10, [sp, #112]
    ldrb w11, [x22, #12]
    str  x11, [sp, #120]
    sub  x12, x23, #BC_FRAG_HDR
    str  x12, [sp, #128]
    cbz  x10, Lfp_bad
    cmp  x10, #FA_FRAGS
    b.hi Lfp_bad
    cmp  x9, x10
    b.hs Lfp_bad
    // forget sets older than FA_TIMEOUT
    mov  x9, #0
    mov  x13, #FS_SIZE
    mov  x14, #FA_TIMEOUT
1:  madd x10, x9, x13, x19
    ldr  x11, [x10, #FS_USED]
    cbz  x11, 2f
    ldr  x11, [x10, #FS_START]
    sub  x11, x20, x11
    cmp  x11, x14
    b.ls 2f
    str  xzr, [x10, #FS_USED]
2:  add  x9, x9, #1
    cmp  x9, #FA_N
    b.lo 1b
    // this sender's set with this id, on this link?
    ldr  x15, [sp, #96]
    ldr  x17, [sp, #136]
    mov  x9, #0
3:  madd x25, x9, x13, x19
    ldr  x11, [x25, #FS_USED]
    cmp  x11, x17
    b.ne 4f
    ldr  x11, [x25, #FS_SENDER]
    cmp  x11, x21
    b.ne 4f
    ldr  x11, [x25, #FS_ID]
    cmp  x11, x15
    b.eq Lfp_slot
4:  add  x9, x9, #1
    cmp  x9, #FA_N
    b.lo 3b
    // a new set: if this link has FA_PER_LINK already, its own oldest; else a free slot,
    // or the oldest of all
    mov  x9, #0
    mov  x12, #0                          // this link's sets
    mov  x25, #0
    mov  x16, #-1                         // its oldest start
50: madd x10, x9, x13, x19
    ldr  x11, [x10, #FS_USED]
    cmp  x11, x17
    b.ne 51f
    add  x12, x12, #1
    ldr  x11, [x10, #FS_START]
    cmp  x11, x16
    b.hs 51f
    mov  x16, x11
    mov  x25, x10
51: add  x9, x9, #1
    cmp  x9, #FA_N
    b.lo 50b
    cmp  x12, #FA_PER_LINK
    b.hs 8f
    mov  x9, #0
    mov  x25, #0
    mov  x16, #-1                         // oldest start seen
5:  madd x10, x9, x13, x19
    ldr  x11, [x10, #FS_USED]
    cbz  x11, 6f
    ldr  x11, [x10, #FS_START]
    cmp  x11, x16
    b.hs 7f
    mov  x16, x11
    mov  x25, x10
    b    7f
6:  mov  x25, x10
    b    8f
7:  add  x9, x9, #1
    cmp  x9, #FA_N
    b.lo 5b
8:  ldr  x9, [sp, #136]
    str  x9, [x25, #FS_USED]
    str  x21, [x25, #FS_SENDER]
    str  x15, [x25, #FS_ID]
    ldr  x9, [sp, #112]
    str  x9, [x25, #FS_TOTAL]
    ldr  x9, [sp, #120]
    str  x9, [x25, #FS_TYPE]
    str  x20, [x25, #FS_START]
    str  xzr, [x25, #FS_GOT]
    str  xzr, [x25, #FS_BYTES]
    str  xzr, [x25, #FS_MAP]
Lfp_slot:
    ldr  x9, [x25, #FS_TOTAL]             // every piece must agree on the set
    ldr  x10, [sp, #112]
    cmp  x9, x10
    b.ne Lfp_bad
    ldr  x9, [x25, #FS_TYPE]
    ldr  x10, [sp, #120]
    cmp  x9, x10
    b.ne Lfp_bad
    ldr  x9, [x25, #FS_MAP]
    ldr  x10, [sp, #104]
    lsr  x11, x9, x10
    tbnz x11, #0, Lfp_wait                // a repeat
    ldr  x12, [x25, #FS_BYTES]
    ldr  x13, [sp, #128]
    add  x14, x12, x13
    cmp  x14, #FA_BYTES
    b.hi Lfp_toobig
    add  x15, x25, #FS_DATA               // copy the chunk in
    add  x15, x15, x12
    add  x16, x22, #BC_FRAG_HDR
    mov  x17, #0
9:  cmp  x17, x13
    b.hs 10f
    ldrb w11, [x16, x17]
    strb w11, [x15, x17]
    add  x17, x17, #1
    b    9b
10: add  x15, x25, #FS_TAB                // where it went
    add  x15, x15, x10, lsl #2
    strh w12, [x15]
    strh w13, [x15, #2]
    str  x14, [x25, #FS_BYTES]
    mov  x11, #1
    lsl  x11, x11, x10
    orr  x9, x9, x11
    str  x9, [x25, #FS_MAP]
    ldr  x9, [x25, #FS_GOT]
    add  x9, x9, #1
    str  x9, [x25, #FS_GOT]
    ldr  x10, [x25, #FS_TOTAL]
    cmp  x9, x10
    b.lo Lfp_wait
    // complete: join the chunks in order
    mov  x9, #0                           // index
    mov  x12, #0                          // bytes out
11: add  x15, x25, #FS_TAB
    add  x15, x15, x9, lsl #2
    ldrh w13, [x15]
    ldrh w14, [x15, #2]
    add  x16, x25, #FS_DATA
    add  x16, x16, x13
    mov  x17, #0
12: cmp  x17, x14
    b.hs 13f
    ldrb w11, [x16, x17]
    strb w11, [x24, x12]
    add  x12, x12, #1
    add  x17, x17, #1
    b    12b
13: add  x9, x9, #1
    cmp  x9, x10
    b.lo 11b
    str  xzr, [x25, #FS_USED]
    mov  x0, x12
    b    Lfp_ret
Lfp_toobig:
    str  xzr, [x25, #FS_USED]             // the whole set goes
Lfp_bad:
    mov  x0, #-1
    b    Lfp_ret
Lfp_wait:
    mov  x0, #0
Lfp_ret:
    ldr  x25, [sp, #144]
    LEAVE 64

// long _bc_frag_chunk(long link_limit) -> how many packet bytes go in each fragment
//   on a link that takes link_limit bytes per write (bitchat: limit - 42, at least 64)
.globl _bc_frag_chunk
_bc_frag_chunk:
    sub  x0, x0, #BC_FRAG_OVER
    mov  x1, #BC_FRAG_MIN
    cmp  x0, x1
    csel x0, x0, x1, gt
    ret

// long _bc_frag_payload(uint8 *out, const uint8 *id[8], long index, long total,
//   long type, const uint8 *chunk, long n) -> length of the fragment payload (13 + n)
.globl _bc_frag_payload
_bc_frag_payload:
    ldr  x9, [x1]
    str  x9, [x0]
    lsr  x9, x2, #8
    strb w9, [x0, #8]
    strb w2, [x0, #9]
    lsr  x9, x3, #8
    strb w9, [x0, #10]
    strb w3, [x0, #11]
    strb w4, [x0, #12]
    add  x10, x0, #BC_FRAG_HDR
    mov  x9, #0
1:  cmp  x9, x6
    b.hs 2f
    ldrb w11, [x5, x9]
    strb w11, [x10, x9]
    add  x9, x9, #1
    b    1b
2:  add  x0, x6, #BC_FRAG_HDR
    ret

// long _bc_q_push(q, const uint8 *p, long n) -> 1 queued, 0 full (counted in Q_DROPS),
//   -1 too big for one write
.globl _bc_q_push
_bc_q_push:
    cmp  x2, #BC_WRITE_MAX
    b.hi Lqp_big
    ldr  x9, [x0, #Q_COUNT]
    cmp  x9, #Q_N
    b.hs Lqp_full
    ldr  x10, [x0, #Q_HEAD]
    add  x10, x10, x9
    and  x10, x10, #(Q_N - 1)
    mov  x11, #Q_ESIZE
    madd x11, x10, x11, x0
    add  x11, x11, #Q_ENT
    str  x2, [x11]
    add  x11, x11, #8
    mov  x12, #0
1:  cmp  x12, x2
    b.hs 2f
    ldrb w13, [x1, x12]
    strb w13, [x11, x12]
    add  x12, x12, #1
    b    1b
2:  add  x9, x9, #1
    str  x9, [x0, #Q_COUNT]
    mov  x0, #1
    ret
Lqp_full:
    ldr  x9, [x0, #Q_DROPS]
    add  x9, x9, #1
    str  x9, [x0, #Q_DROPS]
    mov  x0, #0
    ret
Lqp_big:
    mov  x0, #-1
    ret

// (x0 bytes, x1 length) _bc_q_front(q) — the oldest frame, or (0, 0) when empty
.globl _bc_q_front
_bc_q_front:
    ldr  x9, [x0, #Q_COUNT]
    cbz  x9, 1f
    ldr  x10, [x0, #Q_HEAD]
    mov  x11, #Q_ESIZE
    madd x11, x10, x11, x0
    add  x11, x11, #Q_ENT
    ldr  x1, [x11]
    add  x0, x11, #8
    ret
1:  mov  x0, #0
    mov  x1, #0
    ret

// void _bc_q_pop(q) — drop the oldest frame (it was sent)
.globl _bc_q_pop
_bc_q_pop:
    ldr  x9, [x0, #Q_COUNT]
    cbz  x9, 1f
    sub  x9, x9, #1
    str  x9, [x0, #Q_COUNT]
    ldr  x10, [x0, #Q_HEAD]
    add  x10, x10, #1
    and  x10, x10, #(Q_N - 1)
    str  x10, [x0, #Q_HEAD]
1:  ret

// void _bc_q_clear(q) — empty it (the drop count stays)
.globl _bc_q_clear
_bc_q_clear:
    str  xzr, [x0, #Q_HEAD]
    str  xzr, [x0, #Q_COUNT]
    ret

// (x0 offset, x1 length) _bc_frame_payload(const uint8 *p, long n) — where a complete,
//   uncompressed packet's payload is; x0 = -1 if it isn't complete or is compressed
//   (inflating is the packet decoder's job, Phase 3)
.globl _bc_frame_payload
_bc_frame_payload:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _bc_frame_len
    cmp  x0, #1
    b.lt Lfy_no
    cmp  x0, x20
    b.hi Lfy_no
    ldrb w9, [x19, #11]                   // flags
    tst  w9, #4
    b.ne Lfy_no
    ldrb w10, [x19]
    mov  x11, #14
    cmp  w10, #2
    b.ne 1f
    mov  x11, #16
1:  cmp  w10, #2                          // the payload length again
    b.eq 2f
    ldrb w12, [x19, #12]
    ldrb w13, [x19, #13]
    orr  x1, x13, x12, lsl #8
    b    3f
2:  ldr  w1, [x19, #12]
    rev  w1, w1
3:  add  x11, x11, #8                     // sender
    tst  w9, #1
    b.eq 4f
    add  x11, x11, #8                     // recipient
4:  cmp  w10, #2
    b.ne 5f
    tst  w9, #8
    b.eq 5f
    ldrb w12, [x19, x11]                  // route
    add  x11, x11, #1
    add  x11, x11, x12, lsl #3
5:  mov  x0, x11
    LEAVE 0
Lfy_no:
    mov  x0, #-1
    mov  x1, #0
    LEAVE 0

// ---------------------------------------------------------------------------
// self-tests 145-154, called from test.s

// report flags "eq" (pass) under \name, folded into x20 first
.macro BL_AND
    cset x9, eq
    and  x20, x20, x9
.endm

.macro BL_REPORT name
    mov  w1, w20
    ADRL x0, \name
    bl   _t_report
    add  x19, x19, x0
.endm

// x0 = _bc_frag_put(fa, now, Lv_fsender, payload, n, out)
.macro FRAG now, pl, n, link=0
    mov  x0, x22
    mov  x1, #\now
    ADRL x2, Lv_fsender
    \pl
    mov  x4, #\n
    mov  x5, x23
    mov  x6, #\link
    bl   _bc_frag_put
.endm

// long _bc_link_selftest(void) -> number of failures
.globl _bc_link_selftest
_bc_link_selftest:
    ENTER 16                              // [96] x25 [104] x26
    stp  x25, x26, [sp, #96]
    mov  x19, #0
    mov  x0, #1                           // inbox, fragment table, output, queue
    mov  x1, #IB_SIZE
    bl   _calloc
    mov  x21, x0
    mov  x0, #1
    mov  x1, #(FA_SIZE & 0xffff)
    movk x1, #(FA_SIZE >> 16), lsl #16
    bl   _calloc
    mov  x22, x0
    mov  x0, #1
    mov  x1, #(FA_BYTES * 2)
    bl   _calloc
    mov  x23, x0
    mov  x0, #1
    mov  x1, #Q_SIZE
    bl   _calloc
    mov  x24, x0
    // 145. a packet's length from its header; too short to tell; not bitchat
    ADRL x0, Lv_p1
    mov  x1, #154
    bl   _bc_frame_len
    cmp  x0, #154
    cset x20, eq
    ADRL x0, Lv_p1
    mov  x1, #10
    bl   _bc_frame_len
    cmp  x0, #0
    BL_AND
    mov  x0, x23
    ADRL x1, Lv_p1
    mov  x2, #154
    bl   _memcpy
    mov  w9, #3
    strb w9, [x23]
    mov  x0, x23
    mov  x1, #154
    bl   _bc_frame_len
    cmn  x0, #1
    BL_AND
    BL_REPORT Ln_bl145
    // 146. v2 with a route: the route counts, the padding doesn't
    ADRL x0, Lv_p2
    mov  x1, #256
    bl   _bc_frame_len
    cmp  x0, #124
    cset x20, eq
    ADRL x0, Lv_p2
    mov  x1, #24
    bl   _bc_frame_len
    cmp  x0, #0
    BL_AND
    BL_REPORT Ln_bl146
    // 147. a long write in two pieces is put back together
    mov  x0, x21
    mov  x1, #0
    ADRL x2, Lv_p1
    mov  x3, #100
    bl   _bc_inbox_put
    cmp  x0, #0
    cset x20, eq
    mov  x0, x21
    mov  x1, #100
    ADRL x2, Lv_p1
    add  x2, x2, #100
    mov  x3, #54
    bl   _bc_inbox_put
    cmp  x0, #154
    BL_AND
    add  x0, x21, #IB_DATA
    ADRL x1, Lv_p1
    mov  x2, #154
    bl   _bc_memeq
    cmp  x0, #1
    BL_AND
    BL_REPORT Ln_bl147
    // 148. a new write starts over; a write past 512 bytes is dropped
    mov  x0, x21
    mov  x1, #0
    ADRL x2, Lv_p1
    mov  x3, #50
    bl   _bc_inbox_put
    cmp  x0, #0
    cset x20, eq
    mov  x0, x21
    mov  x1, #0
    ADRL x2, Lv_p1
    mov  x3, #154
    bl   _bc_inbox_put
    cmp  x0, #154
    BL_AND
    mov  x0, x21
    mov  x1, #400
    ADRL x2, Lv_p1
    mov  x3, #200
    bl   _bc_inbox_put
    cmn  x0, #1
    BL_AND
    BL_REPORT Ln_bl148
    // 149. three fragments, out of order and one twice, give back the packet
    FRAG 1000, "ADRL x3, Lv_f2", 62
    cmp  x0, #0
    cset x20, eq
    FRAG 1001, "ADRL x3, Lv_f0", 133
    cmp  x0, #0
    BL_AND
    FRAG 1002, "ADRL x3, Lv_f0", 133
    cmp  x0, #0
    BL_AND
    FRAG 1003, "ADRL x3, Lv_f1", 133
    cmp  x0, #289
    BL_AND
    mov  x0, x23
    ADRL x1, Lv_p3
    mov  x2, #289
    bl   _bc_memeq
    cmp  x0, #1
    BL_AND
    BL_REPORT Ln_bl149
    // 150. refused: index past the total, total 0, total over 64, a total that changes
    add  x25, x23, #FA_BYTES              // a scratch copy of fragment 0
    mov  x0, x25
    ADRL x1, Lv_f0
    mov  x2, #133
    bl   _memcpy
    mov  w9, #3
    strb w9, [x25, #9]
    FRAG 2000, "mov x3, x25", 133
    cmn  x0, #1
    cset x20, eq
    strb wzr, [x25, #9]
    strb wzr, [x25, #11]
    FRAG 2001, "mov x3, x25", 133
    cmn  x0, #1
    BL_AND
    mov  w9, #65
    strb w9, [x25, #11]
    FRAG 2002, "mov x3, x25", 133
    cmn  x0, #1
    BL_AND
    FRAG 2003, "ADRL x3, Lv_f0", 133
    cmp  x0, #0
    BL_AND
    mov  x0, x25
    ADRL x1, Lv_f1
    mov  x2, #133
    bl   _memcpy
    mov  w9, #4
    strb w9, [x25, #11]
    FRAG 2004, "mov x3, x25", 133
    cmn  x0, #1
    BL_AND
    BL_REPORT Ln_bl150
    // 151. a set left unfinished for 30 s is forgotten; a fresh one still works
    mov  x0, x22
    mov  x1, #(FA_SIZE & 0xffff)
    movk x1, #(FA_SIZE >> 16), lsl #16
    bl   _bc_wipe
    FRAG 1000, "ADRL x3, Lv_f0", 133
    cmp  x0, #0
    cset x20, eq
    FRAG 2000, "ADRL x3, Lv_f1", 133
    cmp  x0, #0
    BL_AND
    FRAG 40000, "ADRL x3, Lv_f2", 62
    cmp  x0, #0
    BL_AND
    FRAG 40001, "ADRL x3, Lv_f0", 133
    cmp  x0, #0
    BL_AND
    FRAG 40002, "ADRL x3, Lv_f1", 133
    cmp  x0, #289
    BL_AND
    BL_REPORT Ln_bl151
    // 152. making fragments: bitchat's chunk size and payload layout
    mov  x0, #185
    bl   _bc_frag_chunk
    cmp  x0, #143
    cset x20, eq
    mov  x0, #80
    bl   _bc_frag_chunk
    cmp  x0, #64
    BL_AND
    mov  x0, x23
    ADRL x1, Lv_fid
    mov  x2, #1
    mov  x3, #3
    mov  x4, #2
    ADRL x5, Lv_p3
    add  x5, x5, #120
    mov  x6, #120
    bl   _bc_frag_payload
    cmp  x0, #133
    BL_AND
    mov  x0, x23
    ADRL x1, Lv_f1
    mov  x2, #133
    bl   _bc_memeq
    cmp  x0, #1
    BL_AND
    BL_REPORT Ln_bl152
    // 153. the send queue: 8 fit, the 9th is counted as dropped, oldest first out
    mov  x20, #1
    mov  x25, #0
1:  mov  x0, x24
    ADRL x1, Lv_p1
    mov  x2, #154
    tst  x25, #1
    b.eq 2f
    ADRL x1, Lv_p2
    mov  x2, #256
2:  bl   _bc_q_push
    cmp  x0, #1
    BL_AND
    add  x25, x25, #1
    cmp  x25, #8
    b.lo 1b
    mov  x0, x24
    ADRL x1, Lv_p1
    mov  x2, #154
    bl   _bc_q_push
    cmp  x0, #0
    BL_AND
    ldr  x9, [x24, #Q_DROPS]
    cmp  x9, #1
    BL_AND
    mov  x0, x24
    bl   _bc_q_front
    cmp  x1, #154
    BL_AND
    mov  x0, x24
    bl   _bc_q_pop
    mov  x0, x24
    bl   _bc_q_front
    cmp  x1, #256
    BL_AND
    mov  x0, x24
    ADRL x1, Lv_p1
    mov  x2, #513
    bl   _bc_q_push
    cmn  x0, #1
    BL_AND
    BL_REPORT Ln_bl153
    // 154. a fragment's payload is found past recipient and route; compressed waits
    ADRL x0, Lv_p4
    mov  x1, #76
    bl   _bc_frame_payload
    cmp  x0, #57
    ccmp x1, #19, #0, eq
    cset x20, eq
    ADRL x0, Lv_p5
    mov  x1, #32
    bl   _bc_frame_payload
    cmn  x0, #1
    BL_AND
    ADRL x0, Lv_p4
    mov  x1, #75
    bl   _bc_frame_payload
    cmn  x0, #1
    BL_AND
    BL_REPORT Ln_bl154
    // 177. after a packet completes, the rest of the write (its padding) is ignored,
    //      not read as the same packet again
    mov  x0, x21
    mov  x1, #0
    ADRL x2, Lv_p1
    mov  x3, #100
    bl   _bc_inbox_put
    cmp  x0, #0
    cset x20, eq
    mov  x0, x21
    mov  x1, #100
    ADRL x2, Lv_p1
    add  x2, x2, #100
    mov  x3, #54
    bl   _bc_inbox_put
    cmp  x0, #154
    BL_AND
    mov  x0, x21
    mov  x1, #154
    ADRL x2, Lv_p1
    mov  x3, #20
    bl   _bc_inbox_put
    cmp  x0, #0
    BL_AND
    mov  x0, x21                          // nor a piece whose write never started
    mov  x1, #50
    ADRL x2, Lv_p1
    mov  x3, #20
    bl   _bc_inbox_put
    cmp  x0, #0
    BL_AND
    mov  x0, x21                          // a piece that leaves a gap drops the write
    mov  x1, #0
    ADRL x2, Lv_p1
    mov  x3, #100
    bl   _bc_inbox_put
    cmp  x0, #0
    BL_AND
    mov  x0, x21
    mov  x1, #120
    ADRL x2, Lv_p1
    add  x2, x2, #120
    mov  x3, #34
    bl   _bc_inbox_put
    cmn  x0, #1
    BL_AND
    BL_REPORT Ln_bl177
    // 178. one link can't push out another's fragment sets, or slip pieces into them
    mov  x0, x22
    mov  x1, #(FA_SIZE & 0xffff)
    movk x1, #(FA_SIZE >> 16), lsl #16
    bl   _bc_wipe
    FRAG 5000, "ADRL x3, Lv_f0", 133, 2   // link 2 starts the real set
    cmp  x0, #0
    cset x20, eq
    add  x25, x23, #FA_BYTES              // link 1: three sets of its own (copies, new ids)
    mov  x26, #1
9:  mov  x0, x25
    ADRL x1, Lv_f0
    mov  x2, #133
    bl   _memcpy
    strb w26, [x25]                       //   (the id's first byte)
    mov  w9, #0x5a
    strb w9, [x25, #1]
    FRAG 5001, "mov x3, x25", 133, 1
    cmp  x0, #0
    BL_AND
    add  x26, x26, #1
    cmp  x26, #4
    b.ls 9b
    FRAG 5002, "ADRL x3, Lv_f1", 133, 1   // link 1 with the real set's next piece: not joined
    cmp  x0, #0
    BL_AND
    FRAG 5003, "ADRL x3, Lv_f2", 62, 2    // link 2: the rest, and the real packet comes out
    cmp  x0, #0
    BL_AND
    FRAG 5004, "ADRL x3, Lv_f1", 133, 2
    cmp  x0, #289
    BL_AND
    BL_REPORT Ln_bl178
    mov  x0, x21
    bl   _free
    mov  x0, x22
    bl   _free
    mov  x0, x23
    bl   _free
    mov  x0, x24
    bl   _free
    mov  x0, x19
    ldp  x25, x26, [sp, #96]
    LEAVE 16

.section __TEXT,__const
Ln_bl145:   .asciz "145 bitchat link: a packet's length from its header"
Ln_bl146:   .asciz "146 bitchat link: a route counts, padding doesn't"
Ln_bl147:   .asciz "147 bitchat link: a long write in two pieces is put back together"
Ln_bl148:   .asciz "148 bitchat link: a new write starts over; past 512 bytes is dropped"
Ln_bl149:   .asciz "149 bitchat link: fragments out of order and repeated give back the packet"
Ln_bl150:   .asciz "150 bitchat link: impossible fragments are refused"
Ln_bl151:   .asciz "151 bitchat link: a fragment set left for 30 s is forgotten"
Ln_bl152:   .asciz "152 bitchat link: fragments are made the way bitchat makes them"
Ln_bl153:   .asciz "153 bitchat link: the send queue keeps 8, oldest first"
Ln_bl177:   .asciz "177 bitchat link: the rest of a write after its packet is ignored; gaps drop it"
Ln_bl178:   .asciz "178 bitchat link: fragment sets stay with their link, at most 2 each"
Ln_bl154:   .asciz "154 bitchat link: a fragment's payload is found; a compressed one waits"
// a v1 packet with recipient and signature (154 bytes)
Lv_p1:
    .byte 0x01, 0x11, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x12, 0x34, 0x56, 0x78, 0x03, 0x00, 0x3c, 0x52, 0xf2
    .byte 0x26, 0x65, 0xa6, 0x0c, 0x12, 0xd2, 0x89, 0x18, 0x5d, 0x95, 0x0e, 0xe8, 0x81, 0x36, 0x09, 0x16
    .byte 0x6f, 0x6b, 0x11, 0x3d, 0x17, 0x8d, 0x6c, 0x0f, 0xd3, 0x90, 0x1f, 0xf2, 0x39, 0xa1, 0xa0, 0x95
    .byte 0xf2, 0x0f, 0x93, 0x95, 0x65, 0x0c, 0xf9, 0x38, 0x0b, 0x8e, 0xdb, 0x22, 0x4a, 0x6b, 0x24, 0x8a
    .byte 0x1e, 0x92, 0x4e, 0x8f, 0xd0, 0xae, 0x2e, 0x1a, 0x94, 0x92, 0xa3, 0x30, 0x5f, 0x18, 0x8c, 0xb6
    .byte 0x10, 0x90, 0x0f, 0x9e, 0x34, 0x7f, 0xae, 0x88, 0x6d, 0xc6, 0x50, 0x77, 0x95, 0xec, 0x74, 0x5c
    .byte 0x4c, 0x3f, 0xcb, 0x2e, 0xb2, 0xc7, 0x3e, 0x14, 0x93, 0x4c, 0x86, 0x7e, 0xe0, 0x57, 0xba, 0x72
    .byte 0x49, 0x9b, 0xfa, 0x12, 0x1e, 0x83, 0x6b, 0x2a, 0xc1, 0x57, 0x26, 0xee, 0x7d, 0x6b, 0x0a, 0xf6
    .byte 0xab, 0x13, 0xc3, 0x8e, 0x92, 0xca, 0xe0, 0xd1, 0x50, 0x57, 0xb1, 0x59, 0x98, 0x7f, 0x94, 0xcc
    .byte 0x74, 0x11, 0xd7, 0x17, 0xf1, 0x45, 0x79, 0xb2, 0xaa, 0x10
// a v2 packet with a 2-hop route, padded to 256 (124 bytes before padding)
Lv_p2:
    .byte 0x02, 0x02, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x12, 0x34, 0x56, 0x78, 0x0a, 0x00, 0x00, 0x00, 0x13
    .byte 0x0f, 0xbb, 0xb3, 0x4f, 0xa5, 0x93, 0xfe, 0xae, 0x02, 0xd2, 0x72, 0x48, 0xb7, 0x62, 0xe3, 0xab
    .byte 0x58, 0x05, 0xf0, 0x76, 0x5a, 0x2b, 0x9c, 0x1d, 0x7e, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x66
    .byte 0x72, 0x6f, 0x6d, 0x20, 0x74, 0x68, 0x65, 0x20, 0x6d, 0x65, 0x73, 0x68, 0x0f, 0x37, 0xc4, 0x49
    .byte 0x21, 0xbd, 0x3f, 0x65, 0x64, 0xea, 0xdf, 0x7f, 0x14, 0x2a, 0x72, 0x66, 0x8c, 0x47, 0xe2, 0x23
    .byte 0xd1, 0x6e, 0xdd, 0x8c, 0x47, 0xb4, 0x6a, 0xfc, 0x5b, 0xae, 0xe2, 0x61, 0xf5, 0x3b, 0x26, 0x15
    .byte 0x2d, 0x26, 0x3b, 0xa8, 0x3b, 0x03, 0x7c, 0xd4, 0x96, 0x2e, 0x43, 0x48, 0x01, 0x25, 0x6b, 0x88
    .byte 0x5e, 0x9c, 0x90, 0x51, 0xf3, 0x20, 0xb0, 0xdb, 0x83, 0xf3, 0x9e, 0xa7, 0x84, 0x84, 0x84, 0x84
    .byte 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84
    .byte 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84
    .byte 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84
    .byte 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84
    .byte 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84
    .byte 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84
    .byte 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84
    .byte 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84, 0x84
// a 289-byte packet, sent as three fragments of 120
Lv_p3:
    .byte 0x01, 0x02, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x12, 0x34, 0x56, 0x78, 0x02, 0x00, 0xcb, 0x42, 0x42
    .byte 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09
    .byte 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19
    .byte 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29
    .byte 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39
    .byte 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49
    .byte 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59
    .byte 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69
    .byte 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79
    .byte 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89
    .byte 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99
    .byte 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9
    .byte 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9
    .byte 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf, 0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0x65, 0x6e
    .byte 0x64, 0xad, 0xbd, 0x0d, 0x74, 0xe6, 0xde, 0xc7, 0xf3, 0xdf, 0xae, 0xcc, 0x8f, 0x64, 0x65, 0x66
    .byte 0x64, 0x1a, 0x7b, 0xa2, 0x66, 0x0f, 0x30, 0x11, 0xfc, 0x35, 0x70, 0x29, 0x1c, 0x57, 0x99, 0x0d
    .byte 0x1a, 0x00, 0x91, 0x26, 0x89, 0x19, 0xf2, 0x5d, 0x9d, 0x06, 0x12, 0xdf, 0x35, 0x9d, 0x60, 0x26
    .byte 0xa2, 0x40, 0xf4, 0x58, 0x9a, 0x5d, 0x79, 0x1f, 0x1d, 0xd9, 0x7c, 0xfe, 0xfa, 0x77, 0x7a, 0x7b
    .byte 0x4f
Lv_f0:
    .byte 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0x00, 0x00, 0x00, 0x03, 0x02, 0x01, 0x02, 0x07
    .byte 0x00, 0x00, 0x01, 0x9a, 0x12, 0x34, 0x56, 0x78, 0x02, 0x00, 0xcb, 0x42, 0x42, 0x42, 0x42, 0x42
    .byte 0x42, 0x42, 0x42, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c
    .byte 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c
    .byte 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c
    .byte 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c
    .byte 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c
    .byte 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c
    .byte 0x5d, 0x5e, 0x5f, 0x60, 0x61
Lv_f1:
    .byte 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0x00, 0x01, 0x00, 0x03, 0x02, 0x62, 0x63, 0x64
    .byte 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74
    .byte 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x80, 0x81, 0x82, 0x83, 0x84
    .byte 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94
    .byte 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4
    .byte 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4
    .byte 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf, 0xc0, 0xc1, 0xc2, 0xc3, 0xc4
    .byte 0xc5, 0xc6, 0xc7, 0x65, 0x6e, 0x64, 0xad, 0xbd, 0x0d, 0x74, 0xe6, 0xde, 0xc7, 0xf3, 0xdf, 0xae
    .byte 0xcc, 0x8f, 0x64, 0x65, 0x66
Lv_f2:
    .byte 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0x00, 0x02, 0x00, 0x03, 0x02, 0x64, 0x1a, 0x7b
    .byte 0xa2, 0x66, 0x0f, 0x30, 0x11, 0xfc, 0x35, 0x70, 0x29, 0x1c, 0x57, 0x99, 0x0d, 0x1a, 0x00, 0x91
    .byte 0x26, 0x89, 0x19, 0xf2, 0x5d, 0x9d, 0x06, 0x12, 0xdf, 0x35, 0x9d, 0x60, 0x26, 0xa2, 0x40, 0xf4
    .byte 0x58, 0x9a, 0x5d, 0x79, 0x1f, 0x1d, 0xd9, 0x7c, 0xfe, 0xfa, 0x77, 0x7a, 0x7b, 0x4f
Lv_fid:
    .byte 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7
Lv_fsender:
    .byte 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42
// a v2 fragment packet with recipient and 3-hop route: payload at 57, 19 bytes (total 76)
Lv_p4:
    .byte 0x02, 0x20, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x12, 0x34, 0x56, 0x78, 0x09, 0x00, 0x00, 0x00, 0x13
    .byte 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24, 0x24
    .byte 0x03, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02
    .byte 0x02, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x03, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06
    .byte 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x63, 0x68, 0x75, 0x6e, 0x6b, 0x21
// a compressed v1 packet (32 bytes)
Lv_p5:
    .byte 0x01, 0x02, 0x07, 0x00, 0x00, 0x01, 0x9a, 0x12, 0x34, 0x56, 0x78, 0x04, 0x00, 0x0a, 0x42, 0x42
    .byte 0x42, 0x42, 0x42, 0x42, 0x42, 0x42, 0x01, 0x2c, 0x78, 0x78, 0x78, 0x78, 0x78, 0x78, 0x78, 0x78
