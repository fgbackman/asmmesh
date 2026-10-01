// asmfm — dsp.S
// AFSK modem: HDLC framing (flags, bit stuffing, NRZI, CRC-16/X.25),
// continuous-phase tone synthesis, and a non-coherent correlator
// demodulator with a digital PLL for bit timing. Integer DSP only.
.include "fm_defs.inc"

    .text

// ---------------------------------------------------------------
// fm_modem_init(w0 = baud)   mark tone = baud, space tone = 2*baud
// ---------------------------------------------------------------
    .globl _fm_modem_init
    .p2align 2
_fm_modem_init:
    FENTER
    mov w19, w0
    LA x20, _fm_mdm
    // clear whole state block
    mov x0, x20
    mov x1, #0
    mov x2, #M_SIZE
    bl _memset
    str w19, [x20, #M_BAUD]
    mov w1, #FS
    udiv w2, w1, w19
    str w2, [x20, #M_SPB]
    // step = (f << 32) / FS
    mov x3, #FS
    uxtw x4, w19
    lsl x5, x4, #32
    udiv x5, x5, x3
    str w5, [x20, #M_STEPM]
    str w5, [x20, #M_PLLSTEP]
    lsl x5, x4, #33
    udiv x5, x5, x3
    str w5, [x20, #M_STEPS]
    // preamble flags ~ 0.16 s
    mov w1, #50
    udiv w2, w19, w1
    cmp w2, #16
    mov w3, #16
    csel w2, w3, w2, lt
    str w2, [x20, #M_NPRE]
    bl build_sintab
    FLEAVE

// sine table: 1024 x int16, amplitude 16384 (Q14), via rotation recurrence
    .p2align 2
build_sintab:
    LA x0, _fm_sintab
    LA x1, rot_consts
    ldr d2, [x1]          // cos(2pi/1024)
    ldr d3, [x1, #8]      // sin(2pi/1024)
    ldr d4, [x1, #16]     // 16384.0
    fmov d0, #1.0         // x = cos
    movi d1, #0           // y = sin
    mov w2, #0
1:  fmul d5, d1, d4
    fcvtns w3, d5
    strh w3, [x0, w2, uxtw #1]
    fmul d6, d0, d2       // x*c
    fmsub d6, d1, d3, d6  // - y*s
    fmul d7, d0, d3       // x*s
    fmadd d7, d1, d2, d7  // + y*c
    fmov d0, d6
    fmov d1, d7
    add w2, w2, #1
    cmp w2, #1024
    b.lt 1b
    ret

// ---------------------------------------------------------------
// fm_crc16(x0 = ptr, w1 = len) -> w0   CRC-16/X.25
// uses only x0..x5
// ---------------------------------------------------------------
    .globl _fm_crc16
    .p2align 2
_fm_crc16:
    mov w2, #0xFFFF
    mov w5, #0x8408
    cbz w1, 3f
1:  ldrb w3, [x0], #1
    eor w2, w2, w3
    mov w4, #8
2:  tst w2, #1
    lsr w2, w2, #1
    eor w3, w2, w5
    csel w2, w3, w2, ne
    subs w4, w4, #1
    b.ne 2b
    subs w1, w1, #1
    b.ne 1b
3:  mov w3, #0xFFFF
    eor w0, w2, w3
    ret

// ---------------------------------------------------------------
// fm_mod(x0 = payload, w1 = len, x2 = out int16*) -> x0 = nsamples
// ---------------------------------------------------------------
    .globl _fm_mod
    .p2align 2
// Every frame now carries Reed-Solomon error correction (fm_fec.s): preamble flags,
// then tag + header + blocks as plain bytes (no bit stuffing), then flags; sent a
// second time when "repeat" is on (_g_fm_repeat).
_fm_mod:
    FENTER 16
    mov x21, x0            // payload
    mov w22, w1            // len
    mov x23, x2            // out start
    mov x20, x2            // out cursor
    mov x0, x21
    uxtw x1, w22
    LA x2, _fx_air
    bl _fx_build
    str x0, [sp, #LOC]     // bytes per copy
    LA x19, _fm_mdm
    LA x26, _fm_sintab
    LA x8, _g_fm_repeat
    ldr x25, [x8]
    cmp x25, #0
    cset x25, ne
    add x25, x25, #1       // copies
    // preamble flags
    ldr w24, [x19, #M_NPRE]
1:  mov w0, #0x7E
    bl mod_rawbyte
    subs w24, w24, #1
    b.ne 1b
2:  LA x21, _fx_air        // one copy: tag, header, blocks
    ldr x22, [sp, #LOC]
    mov w24, #0
3:  cmp w24, w22
    b.ge 4f
    ldrb w0, [x21, w24, uxtw]
    bl mod_rawbyte
    add w24, w24, #1
    b 3b
4:  mov w24, #4            // flags after it (and before a second copy)
5:  mov w0, #0x7E
    bl mod_rawbyte
    subs w24, w24, #1
    b.ne 5b
    subs x25, x25, #1
    b.ne 2b
    sub x0, x20, x23
    asr x0, x0, #1
    FLEAVE 16

// byte without stuffing (flags). w0 = byte. clobbers x0-x15, keeps w24
    .p2align 2
mod_rawbyte:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x27, x28, [sp, #16]
    mov w27, w0
    mov w28, #0
1:  lsr w0, w27, w28
    and w0, w0, #1
    bl mod_bit
    add w28, w28, #1
    cmp w28, #8
    b.lt 1b
    ldp x27, x28, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// byte with HDLC bit stuffing, ones counter in w25
    .p2align 2
mod_stuffbyte:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x27, x28, [sp, #16]
    mov w27, w0
    mov w28, #0
1:  lsr w0, w27, w28
    and w0, w0, #1
    cbz w0, 2f
    bl mod_bit
    add w25, w25, #1
    cmp w25, #5
    b.ne 3f
    mov w0, #0
    bl mod_bit
    mov w25, #0
    b 3f
2:  bl mod_bit
    mov w25, #0
3:  add w28, w28, #1
    cmp w28, #8
    b.lt 1b
    ldp x27, x28, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// one bit: NRZI (0 = change tone), spb samples of continuous-phase tone
// uses x19 = mdm, x20 = out cursor, x26 = sintab; clobbers x9-x15
    .p2align 2
mod_bit:
    ldr w9, [x19, #M_TXTONE]
    cbnz w0, 1f
    eor w9, w9, #1
    str w9, [x19, #M_TXTONE]
1:  ldr w10, [x19, #M_STEPM]
    ldr w11, [x19, #M_STEPS]
    cmp w9, #0
    csel w10, w10, w11, eq
    ldr w12, [x19, #M_TXPH]
    ldr w13, [x19, #M_SPB]
2:  add w12, w12, w10
    lsr w14, w12, #22
    ldrsh w15, [x26, w14, uxtw #1]
    strh w15, [x20], #2
    subs w13, w13, #1
    b.ne 2b
    str w12, [x19, #M_TXPH]
    ret

// ---------------------------------------------------------------
// fm_demod(x0 = int16 samples, w1 = count)
// complete frames are pushed to the rx queue
// ---------------------------------------------------------------
    .globl _fm_demod
    .p2align 2
_fm_demod:
    FENTER
    mov x20, x0
    mov w21, w1
    LA x19, _fm_mdm
    LA x26, _fm_sintab
    ldr w22, [x19, #M_RXPM]
    ldr w23, [x19, #M_RXPS]
    ldr w24, [x19, #M_STEPM]
    ldr w25, [x19, #M_STEPS]
    ldr w27, [x19, #M_RPOS]
    ldr w28, [x19, #M_SPB]
    ldr x9,  [x19, #M_IM]
    ldr x10, [x19, #M_QM]
    ldr x11, [x19, #M_IS]
    ldr x12, [x19, #M_QS]
    cbz w21, 9f
1:  ldrsh w0, [x20], #2
    // ---- mark mixer ----
    add w22, w22, w24
    lsr w1, w22, #22
    ldrsh w2, [x26, w1, uxtw #1]      // sin
    add w3, w1, #256
    and w3, w3, #1023
    ldrsh w3, [x26, w3, uxtw #1]      // cos
    mul w4, w0, w3
    asr w4, w4, #14
    mul w5, w0, w2
    asr w5, w5, #14
    add x6, x19, #M_RIM
    ldrsw x7, [x6, x27, lsl #2]
    str w4, [x6, x27, lsl #2]
    sub x9, x9, x7
    add x9, x9, w4, sxtw
    add x6, x19, #M_RQM
    ldrsw x7, [x6, x27, lsl #2]
    str w5, [x6, x27, lsl #2]
    sub x10, x10, x7
    add x10, x10, w5, sxtw
    // ---- space mixer ----
    add w23, w23, w25
    lsr w1, w23, #22
    ldrsh w2, [x26, w1, uxtw #1]
    add w3, w1, #256
    and w3, w3, #1023
    ldrsh w3, [x26, w3, uxtw #1]
    mul w4, w0, w3
    asr w4, w4, #14
    mul w5, w0, w2
    asr w5, w5, #14
    add x6, x19, #M_RIS
    ldrsw x7, [x6, x27, lsl #2]
    str w4, [x6, x27, lsl #2]
    sub x11, x11, x7
    add x11, x11, w4, sxtw
    add x6, x19, #M_RQS
    ldrsw x7, [x6, x27, lsl #2]
    str w5, [x6, x27, lsl #2]
    sub x12, x12, x7
    add x12, x12, w5, sxtw
    // ring position
    add w27, w27, #1
    cmp w27, w28
    csel w27, wzr, w27, eq
    // ---- energies, decision ----
    mul x4, x9, x9
    madd x4, x10, x10, x4
    mul x5, x11, x11
    madd x5, x12, x12, x5
    cmp x4, x5
    cset w6, gt                         // 1 = mark tone
    // ---- DPLL ----
    ldr w7, [x19, #M_PREV]
    ldr w8, [x19, #M_PLL]
    cmp w6, w7
    b.eq 2f
    mov w13, #0x80000000
    sub w14, w8, w13
    asr w14, w14, #3            // nudge 1/8 of the way: steadier in static (tested
    sub w8, w8, w14             //   in noise and with sound clocks 1000 ppm apart)
2:  str w6, [x19, #M_PREV]
    ldr w13, [x19, #M_PLLSTEP]
    adds w8, w8, w13
    str w8, [x19, #M_PLL]
    b.cc 3f
    // bit clock tick: save sums, process bit
    stp x9, x10, [x19, #M_IM]
    stp x11, x12, [x19, #M_IS]
    mov w0, w6
    bl rx_bit
    ldp x9, x10, [x19, #M_IM]
    ldp x11, x12, [x19, #M_IS]
3:  subs w21, w21, #1
    b.ne 1b
9:  str w22, [x19, #M_RXPM]
    str w23, [x19, #M_RXPS]
    str w27, [x19, #M_RPOS]
    stp x9, x10, [x19, #M_IM]
    stp x11, x12, [x19, #M_IS]
    FLEAVE

// rx_bit(w0 = tone) — NRZI decode, HDLC deframe, CRC check, enqueue
// x19 = mdm. clobbers caller-saved registers.
    .p2align 2
rx_bit:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr w12, [x19, #M_SINCE]    // bits since the last flag
    add w12, w12, #1
    cmp w12, #1000
    mov w13, #1000
    csel w12, w13, w12, hi
    str w12, [x19, #M_SINCE]
    ldr w1, [x19, #M_LAST]
    str w0, [x19, #M_LAST]
    cmp w0, w1
    cset w2, eq                 // NRZI: same tone = 1
    stp x2, x3, [sp, #-16]!     // every bit also goes to the error-corrected framer
    mov w0, w2
    bl _fx_bit
    ldp x2, x3, [sp], #16
    ldr w3, [x19, #M_SR]
    lsl w3, w3, #1
    orr w3, w3, w2
    and w3, w3, #0xFF
    str w3, [x19, #M_SR]
    cmp w3, #0x7E
    b.ne 5f
    // Channel activity, for listen-before-talk: only flags that follow a flag
    // (a preamble or a frame's end). Radio hiss makes lone 0x7E patterns all the
    // time; two in a row, exactly a byte apart, are rare in noise.
    ldr w12, [x19, #M_SINCE]
    str wzr, [x19, #M_SINCE]
    cmp w12, #8
    b.ne 0f
    bl rx_activity
0:
    // inside (or just after) an error-corrected frame: its bytes aren't HDLC
    LA x10, _fx
    ldr w11, [x10, #8]          // FX_ST
    cbnz w11, 4f
    ldr w11, [x10, #32]         // FX_DONE
    str wzr, [x10, #32]
    cbnz w11, 4f
    // ---- flag: close frame ----
    ldr w4, [x19, #M_BLEN]
    cmp w4, #3
    b.lt 4f
    ldr w5, [x19, #M_INF]
    cbz w5, 4f
    add x0, x19, #M_FBUF
    sub w1, w4, #2
    bl _fm_crc16
    ldr w4, [x19, #M_BLEN]
    add x6, x19, #M_FBUF
    sub w7, w4, #2
    ldrb w8, [x6, w7, uxtw]
    add w7, w7, #1
    ldrb w9, [x6, w7, uxtw]
    orr w8, w8, w9, lsl #8
    cmp w0, w8
    b.eq 41f
    cmp w4, #6                  // count damaged frames (ignore flag noise)
    b.lt 4f
    LA x10, _fm_frames_bad
    ldr w11, [x10]
    add w11, w11, #1
    str w11, [x10]
    b 4f
41: LA x10, _fm_frames_ok
    ldr w11, [x10]
    add w11, w11, #1
    str w11, [x10]
    // hand the payload (blen-2 bytes) to the FM transport
    add x0, x19, #M_FBUF
    sub w1, w4, #2
    bl _fm_frame_in
4:  str wzr, [x19, #M_BLEN]
    str wzr, [x19, #M_NBIT]
    str wzr, [x19, #M_BYTE]
    str wzr, [x19, #M_ONES]
    mov w5, #1
    str w5, [x19, #M_INF]
    b 9f
5:  // ---- data bit ----
    ldr w4, [x19, #M_ONES]
    cbz w2, 1f
    add w4, w4, #1
    str w4, [x19, #M_ONES]
    cmp w4, #7
    b.lt 2f
    str wzr, [x19, #M_INF]      // abort
    str wzr, [x19, #M_BLEN]
    b 9f
1:  cmp w4, #5
    str wzr, [x19, #M_ONES]
    b.eq 9f                     // stuffed zero: drop
2:  ldr w5, [x19, #M_INF]
    cbz w5, 9f
    ldr w6, [x19, #M_NBIT]
    ldr w7, [x19, #M_BYTE]
    lsl w8, w2, w6
    orr w7, w7, w8
    add w6, w6, #1
    cmp w6, #8
    b.lt 3f
    ldr w4, [x19, #M_BLEN]
    add x8, x19, #M_FBUF
    strb w7, [x8, w4, uxtw]
    add w4, w4, #1
    str w4, [x19, #M_BLEN]
    mov w6, #0
    mov w7, #0
    // a frame that starts like a mesh packet ('M', version) is someone talking
    cmp w4, #2
    b.lo 31f
    ldrh w9, [x8]
    mov w10, #(FM_MAGIC0 | (FM_MAGIC1 << 8))
    cmp w9, w10
    b.ne 31f
    bl rx_activity              // (touches only x10, x11)
31:
    cmp w4, #(MAXFRAME+2)
    b.le 3f
    str wzr, [x19, #M_INF]
    str wzr, [x19, #M_BLEN]
3:  str w6, [x19, #M_NBIT]
    str w7, [x19, #M_BYTE]
9:  ldp x29, x30, [sp], #16
    ret

// someone is on the air: bump the counter the transport watches (x10, x11)
    .p2align 2
rx_activity:
    LA x10, _g_fm_flags
    ldr w11, [x10]
    add w11, w11, #1
    str w11, [x10]
    ret

// fm_counters_reset(): zero the good/damaged frame counters
    .globl _fm_counters_reset
    .p2align 2
_fm_counters_reset:
    LA x0, _fm_frames_ok
    str xzr, [x0]
    ret

    .section __TEXT,__const
    .p2align 3
rot_consts:
    .double 0.99998117528260111
    .double 0.0061358846491544753
    .double 16384.0

    .data
    .p2align 3
    .globl _g_fm_flags
_g_fm_flags: .word 0, 0
    .globl _fm_frames_ok
    .globl _fm_frames_bad
_fm_frames_ok:  .word 0
_fm_frames_bad: .word 0

    BSS _fm_mdm, M_SIZE
    BSS _fm_sintab, 2048
    BSS _fx_air, 512
