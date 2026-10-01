// asmfm — audio.S : transmit ring buffer and audio sinks
//   * macOS: AudioQueue output (default device, e.g. headphone jack -> FM transmitter)
//   * any OS: raw 16-bit 48 kHz PCM to a file / FIFO / stdout, paced in real time
.include "fm_defs.inc"
    .text

// fm_tx_push(x0 = int16 samples, x1 = count) — blocks while the ring is full
    .globl _fm_tx_push
    .p2align 2
_fm_tx_push:
    FENTER
    mov x19, x0
    mov x20, x1
    LA x21, tx_head
    LA x22, _fm_txring
1:  ldr x0, [x21]               // head (we own it)
    add x2, x21, #8
    ldar x1, [x2]               // tail
    sub x3, x0, x1
    mov x4, #TXCAP
    sub x4, x4, #1
    sub x4, x4, x3              // free
    cmp x4, x20
    b.hs 2f
    mov x0, #5000
    bl _fm_sleep_us
    b 1b
2:  ldr x23, [x21]
    and x24, x23, #(TXCAP-1)    // pos
    mov x25, #TXCAP
    sub x25, x25, x24           // room to end
    cmp x25, x20
    csel x25, x20, x25, hi      // first = min(n, room)
    add x0, x22, x24, lsl #1
    mov x1, x19
    lsl x2, x25, #1
    bl _memcpy
    subs x2, x20, x25
    b.eq 3f
    mov x0, x22
    add x1, x19, x25, lsl #1
    lsl x2, x2, #1
    bl _memcpy
3:  add x23, x23, x20
    stlr x23, [x21]
    FLEAVE

// fm_tx_pull(x0 = dest, x1 = count) -> x0 = real samples; rest zero-filled
    .globl _fm_tx_pull
    .p2align 2
_fm_tx_pull:
    FENTER
    mov x19, x0
    mov x20, x1
    LA x21, tx_head
    LA x22, _fm_txring
    LA x2, tx_flush             // drop queued audio when asked
    ldar w3, [x2]
    cbz w3, 0f
    str wzr, [x2]
    ldar x0, [x21]
    add x3, x21, #8
    stlr x0, [x3]
0:  ldar x0, [x21]              // head
    ldr x23, [x21, #8]          // tail (we own it)
    sub x1, x0, x23
    cmp x1, x20
    csel x26, x1, x20, lo       // m = min(avail, n)
    mov x27, x26
    and x24, x23, #(TXCAP-1)
    mov x25, #TXCAP
    sub x25, x25, x24
    cmp x25, x26
    csel x25, x26, x25, hi      // first
    cbz x26, 4f
    mov x0, x19
    add x1, x22, x24, lsl #1
    lsl x2, x25, #1
    bl _memcpy
    subs x2, x26, x25
    b.eq 4f
    add x0, x19, x25, lsl #1
    mov x1, x22
    lsl x2, x2, #1
    bl _memcpy
4:  subs x2, x20, x26
    b.eq 5f
    add x0, x19, x26, lsl #1
    mov x1, #0
    lsl x2, x2, #1
    bl _memset
5:  add x23, x23, x26
    add x0, x21, #8
    stlr x23, [x0]
    mov x0, x27
    FLEAVE

// fm_tx_pending() -> x0 samples queued but not yet played
    .globl _fm_tx_pending
    .p2align 2
_fm_tx_pending:
    LA x2, tx_head
    ldar x0, [x2]
    add x2, x2, #8
    ldar x1, [x2]
    sub x0, x0, x1
    ret

// fm_tx_flush(): throw away audio that has not been played yet
    .globl _fm_tx_flush
    .p2align 2
_fm_tx_flush:
    LA x0, tx_flush
    mov w1, #1
    stlr w1, [x0]
    ret

// fm_tx_start() -> w0 = 0 ok, 1 no sound output. Starts the output once per run.
    .globl _fm_tx_start
    .p2align 2
_fm_tx_start:
    FENTER 16
    LA x2, tx_started
    ldr w3, [x2]
    cbz w3, 0f
    mov w0, #0
    FLEAVE 16
0:  bl aq_start
    cbnz w0, 1f
    LA x2, tx_started
    mov w3, #1
    str w3, [x2]
    mov w0, #0
1:  FLEAVE 16

// ---------------- macOS AudioQueue output ----------------
    .p2align 2
aq_start:
    FENTER 16
    LA x0, asbd
    LA x1, aq_cb
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov w5, #0
    LA x6, aq_ref
    bl _AudioQueueNewOutput
    cbnz w0, 8f
    mov w19, #3
1:  LA x0, aq_ref
    ldr x0, [x0]
    mov w1, #4096
    add x2, sp, #LOC
    bl _AudioQueueAllocateBuffer
    cbnz w0, 8f
    mov x0, #0
    LA x1, aq_ref
    ldr x1, [x1]
    ldr x2, [sp, #LOC]
    bl aq_cb
    subs w19, w19, #1
    b.ne 1b
    LA x0, aq_ref
    ldr x0, [x0]
    mov x1, #0
    bl _AudioQueueStart
    cbnz w0, 8f
    mov w0, #0
    FLEAVE 16
8:  mov w0, #1
    FLEAVE 16

// callback(user, queue, buffer): fill 1024 stereo frames
    .p2align 2
aq_cb:
    FENTER
    mov x19, x1
    mov x20, x2
    LA x21, aq_scratch
    mov x0, x21
    mov x1, #1024
    bl _fm_tx_pull
    ldr x0, [x20, #8]           // mAudioData
    mov x1, #1024
1:  ldrh w2, [x21], #2
    strh w2, [x0], #2
    strh w2, [x0], #2
    subs x1, x1, #1
    b.ne 1b
    mov w1, #4096
    str w1, [x20, #16]          // mAudioDataByteSize
    mov x0, x19
    mov x1, x20
    mov w2, #0
    mov x3, #0
    bl _AudioQueueEnqueueBuffer
    FLEAVE

    .data
    .p2align 3
asbd:
    .double 48000.0
    .word 0x6C70636D            // 'lpcm'
    .word 12                    // signed int | packed
    .word 4, 1, 4, 2, 16, 0     // bytes/packet, frames/packet, bytes/frame, channels, bits, reserved
aq_ref: .quad 0
    BSS aq_scratch, 2048

    .section __TEXT,__const
    .data
    .p2align 3
tx_head: .quad 0
tx_tail: .quad 0
tx_started: .word 0
tx_flush: .word 0

    BSS _fm_txring, (TXCAP*2)
