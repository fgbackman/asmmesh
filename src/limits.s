// limits.s — how much the mesh will take from one sender, and how much this Mac
// passes on. Token buckets: each sender has `cap` tokens, gets `rate` back per
// second, and every packet costs some. A sender over budget has its packets
// dropped and not relayed, so one buggy or hostile Mac can't flood everyone's
// Bluetooth and battery.
//
//   per sender (signed)      cap 480, 48/s: a message costs 4 (120 at once, then
//                            12 a second); a web page piece costs 1 (a 400-piece
//                            page fits)
//   unverified (no key yet)  one shared bucket, cap 64, 8/s: packets from someone
//                            whose HELLO hasn't arrived can't be checked, so they
//                            are cheap to fake
//   relaying                 one bucket for everything this Mac passes on,
//                            cap 600, 60/s
//
// Buckets are kept for the 64 most recent senders; a new one takes the slot used
// longest ago, starting full.

.include "macros.inc"

.set RL_N,       64
.set RL_SHIFT,   5            // 32-byte rows: +0 id, +8 tokens, +16 last refill (s), +24 warned
.set RL_TOK,     8
.set RL_LAST,    16
.set RL_WARNED,  24

.data
.p2align 3
.globl _g_rate_off
_g_rate_off:     .quad 0      // the self-tests switch limits off while they flood
.zerofill __DATA,__bss,_g_rl,2048,4

.text
.p2align 2

// long _rate_take(uint64 id, long cost, long cap, long rate) -> 1 within budget, 0 over
//   x1 of the result: 1 the first time this sender went over since it was last fine
.globl _rate_take
_rate_take:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ADRL x8, _g_rate_off
    ldr  x9, [x8]
    cbnz x9, Lrt_ok_quiet
    mov  x0, #0
    bl   _time
    mov  x23, x0                      // now
    ADRL x8, _g_rl                    // find the sender, else the stalest row
    mov  x9, #0
    mov  x10, #0                      // stalest index
    mov  x11, #-1                     // its last time (as unsigned: the biggest)
Lrt_find:
    cmp  x9, #RL_N
    b.hs Lrt_new
    add  x12, x8, x9, lsl #RL_SHIFT
    ldr  x13, [x12]
    cmp  x13, x19
    b.eq Lrt_have
    ldr  x13, [x12, #RL_LAST]
    cmp  x13, x11
    b.hs 1f
    mov  x11, x13
    mov  x10, x9
1:  add  x9, x9, #1
    b    Lrt_find
Lrt_new:
    add  x24, x8, x10, lsl #RL_SHIFT
    str  x19, [x24]
    str  x21, [x24, #RL_TOK]          // a new sender starts full
    str  x23, [x24, #RL_LAST]
    str  xzr, [x24, #RL_WARNED]
    b    Lrt_take
Lrt_have:
    mov  x24, x12
    ldr  x9, [x24, #RL_LAST]          // refill for the seconds since
    subs x9, x23, x9
    b.le Lrt_take                     // same second (or the clock went back)
    str  x23, [x24, #RL_LAST]
    cmp  x9, #3600                    // an hour away: simply full again
    b.hs 2f
    mul  x9, x9, x22
    ldr  x10, [x24, #RL_TOK]
    add  x10, x10, x9
    cmp  x10, x21
    csel x10, x21, x10, hi
    str  x10, [x24, #RL_TOK]
    b    Lrt_take
2:  str  x21, [x24, #RL_TOK]
Lrt_take:
    ldr  x10, [x24, #RL_TOK]
    cmp  x10, x20
    b.lt Lrt_over
    sub  x10, x10, x20
    str  x10, [x24, #RL_TOK]
    str  xzr, [x24, #RL_WARNED]
Lrt_ok_quiet:
    mov  x0, #1
    mov  x1, #0
    LEAVE 16
Lrt_over:
    ldr  x1, [x24, #RL_WARNED]
    mov  x9, #1
    str  x9, [x24, #RL_WARNED]
    eor  x1, x1, #1                   // 1 only on the first refusal in a row
    mov  x0, #0
    LEAVE 16

// void _rate_reset(void) — every bucket forgotten (the self-tests)
.globl _rate_reset
_rate_reset:
    ENTER 0
    ADRL x0, _g_rl
    mov  x1, #(RL_N << RL_SHIFT)
    bl   _bzero
    LEAVE 0
