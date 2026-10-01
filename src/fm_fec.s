// fm_fec.s — making FM stronger: Reed–Solomon error correction for every frame.
//
// A frame on the air (after the usual run of 0x7E flags, NRZI tones as before):
//
//   tag      8 bytes, a fixed 64-bit pattern; found even with up to 6 bits wrong
//   header   the payload length L, three times (each bit decided by majority)
//   body     the payload + its CRC-16 (M = L + 2 bytes), as one or two Reed–Solomon
//            RS(n, n-32) blocks over GF(256) (two once M > 223), their bytes
//            interleaved so a crackle damages both blocks a little rather than one a lot
//
// Each block repairs up to 16 damaged bytes; the CRC then confirms the payload.
// No bit stuffing in a frame, so a wrong bit can't shift everything after it.
// The FM window counts frames that arrived clean, repaired, or lost.
//
// The sender may send every frame twice (fm.s); the second copy, if it arrives
// too, is recognised and not passed on again.

.include "macros.inc"

.set NROOTS,     32
.set FX_MAXLEN,  240                  // largest payload (a mesh packet)
.set TAG_ERRS,   6                    // bits of the tag that may be wrong
.set DUP_BITS,   8000                 // a copy within this many bits is the same frame

// receiver state (_fx)
.set FX_SR,      0                    // last 64 bits heard, while hunting for the tag
.set FX_ST,      8                    // 0 hunting, 1 header, 2 body
.set FX_NBIT,    12
.set FX_BYTE,    16
.set FX_POS,     20
.set FX_NEED,    24
.set FX_LEN,     28
.set FX_DONE,    32                   // a frame just ended (the HDLC side ignores it)
.set FX_BITS,    40                   // bits heard, ever
.set FX_LCRC,    48                   // the last frame passed on: CRC, length, when
.set FX_LLEN,    52
.set FX_LBIT,    56
.set FX_BUF,     64                   // the frame's bytes (header, then body)
.set FX_SIZE,    704

.section __TEXT,__const
.p2align 3
Lfx_tagreg:  .quad 0x7cf4ca51fbedb2ed  // the tag, as the 64 bits arrive
Lfx_tag:     .byte 0x3E, 0x2F, 0x53, 0x8A, 0xDF, 0xB7, 0x4D, 0xB7
.p2align 4
.include "fm_fec_tables.inc"

.data
.p2align 3
.globl _fx
_fx:            .space FX_SIZE
.globl _fx_ok
_fx_ok:         .quad 0               // frames that arrived clean
.globl _fx_fixed
_fx_fixed:      .quad 0               // … that needed repairs
.globl _fx_fail
_fx_fail:       .quad 0               // … that couldn't be repaired
.globl _fx_dup
_fx_dup:        .quad 0               // second copies, not passed on
.globl _fx_last
_fx_last:       .quad -2              // the last frame: -2 none yet, -1 lost, else bytes fixed
.zerofill __DATA,__bss,_rs_S,32,4
.zerofill __DATA,__bss,_rs_Lam,48,4
.zerofill __DATA,__bss,_rs_B,48,4
.zerofill __DATA,__bss,_rs_T,48,4
.zerofill __DATA,__bss,_rs_Om,32,4
.zerofill __DATA,__bss,_rs_pos,32,4
.zerofill __DATA,__bss,_fx_tb,256,4    // sending: payload + CRC
.zerofill __DATA,__bss,_fx_p0,32,4
.zerofill __DATA,__bss,_fx_p1,32,4
.zerofill __DATA,__bss,_fx_c0,256,4    // receiving: the two blocks
.zerofill __DATA,__bss,_fx_c1,256,4
.globl _fx_rd
.zerofill __DATA,__bss,_fx_rd,256,4    // receiving: payload + CRC

.text
.p2align 2

// ---------------------------------------------------------------------------
// GF(256) arithmetic (x^8 + x^4 + x^3 + x^2 + 1). These touch only x0, x9-x11.
// ---------------------------------------------------------------------------

// w0 = w0 * w1
_gfm:
    cbz  w0, 1f
    cbz  w1, 2f
    ADRL x9, _gf_log
    ldrb w10, [x9, w0, uxtw]
    ldrb w11, [x9, w1, uxtw]
    add  w10, w10, w11
    ADRL x9, _gf_exp
    ldrb w0, [x9, w10, uxtw]
    ret
2:  mov  w0, #0
1:  ret

// w0 = w0 / w1 (w1 != 0)
_gfd:
    cbz  w0, 1f
    ADRL x9, _gf_log
    ldrb w10, [x9, w0, uxtw]
    ldrb w11, [x9, w1, uxtw]
    sub  w10, w10, w11
    add  w10, w10, #255
    ADRL x9, _gf_exp
    ldrb w0, [x9, w10, uxtw]
1:  ret

// w0 = alpha^(-w0), for 0 <= w0 < 255
_gfinv_pow:
    mov  w10, #255
    sub  w0, w10, w0
    ADRL x9, _gf_exp
    ldrb w0, [x9, w0, uxtw]
    ret

// ---------------------------------------------------------------------------
// Reed–Solomon
// ---------------------------------------------------------------------------

// void _rs_encode(const uint8 *data, long k, uint8 *parity32)
.globl _rs_encode
_rs_encode:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    stp  xzr, xzr, [x21]
    stp  xzr, xzr, [x21, #16]
    mov  x22, #0                      // i
Lre_byte:
    cmp  x22, x20
    b.hs Lre_done
    ldrb w23, [x19, x22]
    ldrb w9, [x21]
    eor  w23, w23, w9                 // feedback
    mov  x9, #0                       // shift the remainder up a byte
Lre_shift:
    add  x10, x9, #1
    ldrb w11, [x21, x10]
    strb w11, [x21, x9]
    mov  x9, x10
    cmp  x9, #31
    b.lo Lre_shift
    strb wzr, [x21, #31]
    cbz  w23, Lre_next
    mov  x24, #0                      // rem[j] ^= f * g[31-j]
Lre_mix:
    mov  x9, #31
    sub  x9, x9, x24
    ADRL x10, _rs_g
    ldrb w1, [x10, x9]
    mov  w0, w23
    bl   _gfm
    ldrb w9, [x21, x24]
    eor  w9, w9, w0
    strb w9, [x21, x24]
    add  x24, x24, #1
    cmp  x24, #32
    b.lo Lre_mix
Lre_next:
    add  x22, x22, #1
    b    Lre_byte
Lre_done:
    LEAVE 0

// long _rs_decode(uint8 *block, long n) -> bytes repaired (0 = it was clean), or -1
//   block = data then 32 parity bytes, 33 <= n <= 255; repaired in place
.globl _rs_decode
_rs_decode:
    ENTER 32                          // [96] k  [104] coef  [112] count  [120] d
    mov  x19, x0
    mov  x20, x1
    cmp  x20, #33
    b.lo Lrd_fail
    cmp  x20, #255
    b.hi Lrd_fail
    // syndromes S[i] = r(alpha^i)
    mov  x21, #0
    mov  x24, #0                      // any non-zero?
Lrd_syn:
    ADRL x9, _gf_exp
    ldrb w22, [x9, x21]               // alpha^i
    mov  w0, #0
    mov  x23, #0
Lrd_syn_j:
    mov  w1, w22
    bl   _gfm
    ldrb w9, [x19, x23]
    eor  w0, w0, w9
    add  x23, x23, #1
    cmp  x23, x20
    b.lo Lrd_syn_j
    ADRL x9, _rs_S
    strb w0, [x9, x21]
    orr  w24, w24, w0
    add  x21, x21, #1
    cmp  x21, #NROOTS
    b.lo Lrd_syn
    cbnz w24, Lrd_bm
    mov  x0, #0
    LEAVE 32

Lrd_bm:                               // Berlekamp–Massey: the error locator Lambda
    ADRL x0, _rs_Lam
    mov  w1, #0
    mov  x2, #48
    bl   _memset
    ADRL x0, _rs_B
    mov  w1, #0
    mov  x2, #48
    bl   _memset
    mov  w9, #1
    ADRL x10, _rs_Lam
    strb w9, [x10]
    ADRL x10, _rs_B
    strb w9, [x10]
    mov  x22, #0                      // L
    mov  x23, #1                      // m
    mov  x24, #1                      // b
    mov  x21, #0                      // k
Lrd_k:
    ADRL x9, _rs_S                    // d = S[k] + sum Lam[i] S[k-i]
    ldrb w9, [x9, x21]
    str  x9, [sp, #120]
    mov  x9, #1
    str  x9, [sp, #112]
Lrd_d:
    ldr  x9, [sp, #112]
    cmp  x9, x22
    b.hi Lrd_d_end
    ADRL x10, _rs_Lam
    ldrb w0, [x10, x9]
    sub  x11, x21, x9
    ADRL x10, _rs_S
    ldrb w1, [x10, x11]
    bl   _gfm
    ldr  x9, [sp, #120]
    eor  x9, x9, x0
    str  x9, [sp, #120]
    ldr  x9, [sp, #112]
    add  x9, x9, #1
    str  x9, [sp, #112]
    b    Lrd_d
Lrd_d_end:
    ldr  x9, [sp, #120]
    cbnz x9, Lrd_upd
    add  x23, x23, #1
    b    Lrd_k_next
Lrd_upd:
    mov  w0, w9                       // coef = d / b
    mov  w1, w24
    bl   _gfd
    str  x0, [sp, #104]
    ADRL x0, _rs_T                    // T = Lam
    ADRL x1, _rs_Lam
    mov  x2, #48
    bl   _memcpy
    mov  x9, #0                       // Lam[i+m] ^= coef * B[i], i = 0 .. 32-m
    str  x9, [sp, #112]
Lrd_upd_i:
    ldr  x9, [sp, #112]
    mov  x10, #32
    sub  x10, x10, x23
    cmp  x9, x10
    b.gt Lrd_upd_end
    ADRL x10, _rs_B
    ldrb w1, [x10, x9]
    ldr  x0, [sp, #104]
    bl   _gfm
    ldr  x9, [sp, #112]
    add  x10, x9, x23
    ADRL x11, _rs_Lam
    ldrb w12, [x11, x10]
    eor  w12, w12, w0
    strb w12, [x11, x10]
    add  x9, x9, #1
    str  x9, [sp, #112]
    b    Lrd_upd_i
Lrd_upd_end:
    lsl  x9, x22, #1                  // 2L <= k: the locator grows
    cmp  x9, x21
    b.hi Lrd_upd_m
    add  x22, x21, #1
    sub  x22, x22, x9, lsr #1
    ADRL x0, _rs_B
    ADRL x1, _rs_T
    mov  x2, #48
    bl   _memcpy
    ldr  x24, [sp, #120]
    mov  x23, #1
    b    Lrd_k_next
Lrd_upd_m:
    add  x23, x23, #1
Lrd_k_next:
    add  x21, x21, #1
    cmp  x21, #NROOTS
    b.lo Lrd_k
    cmp  x22, #16                     // more than 16 errors: beyond repair
    b.hi Lrd_fail

    // Chien search: positions p (powers) where Lam(alpha^-p) = 0
    mov  x21, #0                      // p
    str  xzr, [sp, #112]              // roots found
Lrd_ch:
    cmp  x21, x20
    b.hs Lrd_ch_end
    mov  w0, w21
    bl   _gfinv_pow
    mov  w23, w0                      // alpha^-p
    mov  w0, #0
    mov  x24, x22                     // i = L .. 0
Lrd_ch_i:
    mov  w1, w23
    bl   _gfm
    ADRL x9, _rs_Lam
    ldrb w9, [x9, x24]
    eor  w0, w0, w9
    cbz  x24, Lrd_ch_v
    sub  x24, x24, #1
    b    Lrd_ch_i
Lrd_ch_v:
    cbnz w0, Lrd_ch_next
    ldr  x9, [sp, #112]
    cmp  x9, #32
    b.hs Lrd_fail
    ADRL x10, _rs_pos
    strb w21, [x10, x9]
    add  x9, x9, #1
    str  x9, [sp, #112]
Lrd_ch_next:
    add  x21, x21, #1
    b    Lrd_ch
Lrd_ch_end:
    ldr  x9, [sp, #112]
    cmp  x9, x22
    b.ne Lrd_fail

    // Omega = S * Lam mod x^32
    mov  x21, #0                      // i
Lrd_om:
    mov  x23, #0                      // j
    str  xzr, [sp, #120]
Lrd_om_j:
    cmp  x23, x21
    b.hi Lrd_om_set
    sub  x9, x21, x23
    ADRL x10, _rs_S
    ldrb w0, [x10, x9]
    ADRL x10, _rs_Lam
    ldrb w1, [x10, x23]
    bl   _gfm
    ldr  x9, [sp, #120]
    eor  x9, x9, x0
    str  x9, [sp, #120]
    add  x23, x23, #1
    b    Lrd_om_j
Lrd_om_set:
    ldr  x9, [sp, #120]
    ADRL x10, _rs_Om
    strb w9, [x10, x21]
    add  x21, x21, #1
    cmp  x21, #NROOTS
    b.lo Lrd_om

    // Forney: each error's value, fixed in place
    mov  x21, #0                      // which root
Lrd_fx:
    cmp  x21, x22
    b.hs Lrd_ok
    ADRL x9, _rs_pos
    ldrb w9, [x9, x21]
    str  x9, [sp, #96]                // p
    mov  w0, w9
    bl   _gfinv_pow
    mov  w23, w0                      // xinv
    mov  w0, #0                       // num = Omega(xinv), Horner from x^31
    mov  x24, #31
Lrd_num:
    mov  w1, w23
    bl   _gfm
    ADRL x9, _rs_Om
    ldrb w9, [x9, x24]
    eor  w0, w0, w9
    cbz  x24, Lrd_num_end
    sub  x24, x24, #1
    b    Lrd_num
Lrd_num_end:
    str  x0, [sp, #104]
    mov  w0, w23                      // xinv^2
    mov  w1, w23
    bl   _gfm
    str  x0, [sp, #112]
    mov  x24, #1                      // den = sum over odd i of Lam[i] xinv^(i-1)
    mov  x9, #1
    str  x9, [sp, #120]               // xinv^(i-1)
    mov  w23, #0                      // den
Lrd_den:
    cmp  x24, x22
    b.hi Lrd_den_end
    ADRL x9, _rs_Lam
    ldrb w0, [x9, x24]
    ldr  x1, [sp, #120]
    bl   _gfm
    eor  w23, w23, w0
    ldr  x0, [sp, #120]
    ldr  x1, [sp, #112]
    bl   _gfm
    str  x0, [sp, #120]
    add  x24, x24, #2
    b    Lrd_den
Lrd_den_end:
    cbz  w23, Lrd_fail
    ldr  x0, [sp, #104]               // e = alpha^p * num / den
    mov  w1, w23
    bl   _gfd
    mov  w23, w0
    ldr  x9, [sp, #96]
    ADRL x10, _gf_exp
    ldrb w1, [x10, x9]
    mov  w0, w23
    bl   _gfm
    ldr  x9, [sp, #96]                // byte n-1-p
    sub  x10, x20, #1
    sub  x10, x10, x9
    ldrb w11, [x19, x10]
    eor  w11, w11, w0
    strb w11, [x19, x10]
    add  x21, x21, #1
    b    Lrd_fx
Lrd_ok:
    mov  x0, x22
    LEAVE 32
Lrd_fail:
    mov  x0, #-1
    LEAVE 32

// ---------------------------------------------------------------------------
// Frames
// ---------------------------------------------------------------------------

// w0 = CRC-16/X.25 of (x0, x1) — the same check the HDLC frames use
_fx_crc:
    mov  w2, #0xFFFF
    mov  w5, #0x8408
    cbz  x1, 3f
1:  ldrb w3, [x0], #1
    eor  w2, w2, w3
    mov  w4, #8
2:  tst  w2, #1
    lsr  w2, w2, #1
    eor  w3, w2, w5
    csel w2, w3, w2, ne
    subs w4, w4, #1
    b.ne 2b
    subs x1, x1, #1
    b.ne 1b
3:  mov  w3, #0xFFFF
    eor  w0, w2, w3
    ret

// the shape of a frame with an L-byte payload:
//   x0 = M (payload + CRC), x1 = blocks, x2 = k0, x3 = k1, x4 = n0, x5 = n1
_fx_layout:
    add  x0, x0, #2
    mov  x1, #1
    cmp  x0, #223
    b.ls 1f
    mov  x1, #2
1:  add  x2, x0, x1
    sub  x2, x2, #1
    udiv x2, x2, x1                   // k0 = ceil(M / blocks)
    sub  x3, x0, x2
    add  x4, x2, #NROOTS
    mov  x5, #0
    cmp  x1, #2
    b.ne 2f
    add  x5, x3, #NROOTS
2:  ret

// long _fx_build(const uint8 *payload, long L, uint8 *out) -> bytes to send
//   tag, header, interleaved blocks (1 <= L <= 240)
.globl _fx_build
_fx_build:
    ENTER 48                          // [96] k0 [104] k1 [112] n0 [120] n1 [128] blocks
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x0, _fx_tb                   // payload + CRC
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    mov  x0, x19
    mov  x1, x20
    bl   _fx_crc
    ADRL x9, _fx_tb
    add  x9, x9, x20
    strb w0, [x9]
    lsr  w0, w0, #8
    strb w0, [x9, #1]
    mov  x0, x20
    bl   _fx_layout
    stp  x2, x3, [sp, #96]
    stp  x4, x5, [sp, #112]
    str  x1, [sp, #128]
    ADRL x0, _fx_tb                   // the blocks' check bytes
    ldr  x1, [sp, #96]
    ADRL x2, _fx_p0
    bl   _rs_encode
    ldr  x9, [sp, #128]
    cmp  x9, #2
    b.ne Lfb_out
    ADRL x0, _fx_tb
    ldr  x9, [sp, #96]
    add  x0, x0, x9
    ldr  x1, [sp, #104]
    ADRL x2, _fx_p1
    bl   _rs_encode
Lfb_out:
    ADRL x9, Lfx_tag                  // tag
    ldr  x9, [x9]
    str  x9, [x21]
    strb w20, [x21, #8]               // header: the length, three times
    strb w20, [x21, #9]
    strb w20, [x21, #10]
    mov  x22, #11                     // out position
    mov  x23, #0                      // i
    ADRL x24, _fx_tb
Lfb_i:
    ldr  x9, [sp, #112]               // block 0, byte i
    cmp  x23, x9
    b.hs Lfb_done
    ldr  x10, [sp, #96]
    cmp  x23, x10
    b.hs 1f
    ldrb w11, [x24, x23]
    b    2f
1:  sub  x11, x23, x10
    ADRL x12, _fx_p0
    ldrb w11, [x12, x11]
2:  strb w11, [x21, x22]
    add  x22, x22, #1
    ldr  x9, [sp, #120]               // block 1, byte i
    cmp  x23, x9
    b.hs 4f
    ldr  x10, [sp, #104]
    cmp  x23, x10
    b.hs 3f
    ldr  x12, [sp, #96]
    add  x12, x12, x23
    ldrb w11, [x24, x12]
    b    5f
3:  sub  x11, x23, x10
    ADRL x12, _fx_p1
    ldrb w11, [x12, x11]
5:  strb w11, [x21, x22]
    add  x22, x22, #1
4:  add  x23, x23, #1
    b    Lfb_i
Lfb_done:
    mov  x0, x22
    LEAVE 48

// void _fx_reset(void) — forget a half-heard frame
.globl _fx_reset
_fx_reset:
    ADRL x9, _fx
    str  xzr, [x9, #FX_SR]
    str  wzr, [x9, #FX_ST]
    ret

// void _fx_bit(int bit) — every bit the demodulator decides (after NRZI)
.globl _fx_bit
_fx_bit:
    ENTER 0
    ADRL x19, _fx
    and  x20, x0, #1
    ldr  x9, [x19, #FX_BITS]
    add  x9, x9, #1
    str  x9, [x19, #FX_BITS]
    ldr  w9, [x19, #FX_ST]
    cbnz w9, Lxb_collect
    ldr  x9, [x19, #FX_SR]            // hunting: does the last 64 bits look like the tag?
    lsl  x9, x9, #1
    orr  x9, x9, x20
    str  x9, [x19, #FX_SR]
    ADRL x10, Lfx_tagreg
    ldr  x10, [x10]
    eor  x9, x9, x10
    fmov d0, x9
    cnt  v0.8b, v0.8b
    addv b0, v0.8b
    fmov w9, s0
    cmp  w9, #TAG_ERRS
    b.hi Lxb_done
    mov  w9, #1
    str  w9, [x19, #FX_ST]
    str  wzr, [x19, #FX_NBIT]
    str  wzr, [x19, #FX_BYTE]
    str  wzr, [x19, #FX_POS]
    mov  w9, #3
    str  w9, [x19, #FX_NEED]
    ADRL x9, _g_fm_flags              // someone is on the air
    ldr  w10, [x9]
    add  w10, w10, #1
    str  w10, [x9]
    b    Lxb_done
Lxb_collect:
    ldr  w10, [x19, #FX_NBIT]
    ldr  w11, [x19, #FX_BYTE]
    lsl  w12, w20, w10
    orr  w11, w11, w12
    add  w10, w10, #1
    cmp  w10, #8
    b.hs Lxb_byte
    str  w10, [x19, #FX_NBIT]
    str  w11, [x19, #FX_BYTE]
    b    Lxb_done
Lxb_byte:
    str  wzr, [x19, #FX_NBIT]
    str  wzr, [x19, #FX_BYTE]
    ldr  w12, [x19, #FX_POS]
    add  x13, x19, #FX_BUF
    strb w11, [x13, w12, uxtw]
    add  w12, w12, #1
    str  w12, [x19, #FX_POS]
    ADRL x9, _g_fm_flags              // still on the air (for listen-before-talk)
    ldr  w10, [x9]
    add  w10, w10, #1
    str  w10, [x9]
    ldr  w13, [x19, #FX_NEED]
    cmp  w12, w13
    b.lo Lxb_done
    ldr  w9, [x19, #FX_ST]
    cmp  w9, #1
    b.ne Lxb_body
    ldrb w9, [x19, #FX_BUF]           // the header: each bit by majority
    ldrb w10, [x19, #(FX_BUF + 1)]
    ldrb w11, [x19, #(FX_BUF + 2)]
    and  w12, w9, w10
    and  w13, w9, w11
    orr  w12, w12, w13
    and  w13, w10, w11
    orr  w12, w12, w13
    cbz  w12, Lxb_abort
    cmp  w12, #FX_MAXLEN
    b.hi Lxb_abort
    str  w12, [x19, #FX_LEN]
    mov  x0, x12
    bl   _fx_layout
    add  x9, x4, x5
    str  w9, [x19, #FX_NEED]
    str  wzr, [x19, #FX_POS]
    mov  w9, #2
    str  w9, [x19, #FX_ST]
    b    Lxb_done
Lxb_body:
    bl   _fx_finish
Lxb_abort:
    str  wzr, [x19, #FX_ST]
    str  xzr, [x19, #FX_SR]
    mov  w9, #1
    str  w9, [x19, #FX_DONE]
Lxb_done:
    LEAVE 0

// a whole body has arrived: split the blocks, repair them, check, pass it on
_fx_finish:
    ENTER 64                          // [96] k0 [104] k1 [112] n0 [120] n1 [128] blocks [136] fixed
    ADRL x19, _fx
    ldr  w20, [x19, #FX_LEN]
    mov  x0, x20
    bl   _fx_layout
    stp  x2, x3, [sp, #96]
    stp  x4, x5, [sp, #112]
    str  x1, [sp, #128]
    add  x21, x19, #FX_BUF            // deinterleave
    mov  x22, #0                      // i
    mov  x23, #0                      // read position
Lff_i:
    ldr  x9, [sp, #112]
    cmp  x22, x9
    b.hs Lff_split
    ldrb w10, [x21, x23]
    add  x23, x23, #1
    ADRL x11, _fx_c0
    strb w10, [x11, x22]
    ldr  x9, [sp, #120]
    cmp  x22, x9
    b.hs 1f
    ldrb w10, [x21, x23]
    add  x23, x23, #1
    ADRL x11, _fx_c1
    strb w10, [x11, x22]
1:  add  x22, x22, #1
    b    Lff_i
Lff_split:
    ADRL x0, _fx_c0
    ldr  x1, [sp, #112]
    bl   _rs_decode
    tbnz x0, #63, Lff_bad
    str  x0, [sp, #136]
    ldr  x9, [sp, #128]
    cmp  x9, #2
    b.ne Lff_join
    ADRL x0, _fx_c1
    ldr  x1, [sp, #120]
    bl   _rs_decode
    tbnz x0, #63, Lff_bad
    ldr  x9, [sp, #136]
    add  x9, x9, x0
    str  x9, [sp, #136]
Lff_join:
    ADRL x0, _fx_rd                   // payload + CRC back together
    ADRL x1, _fx_c0
    ldr  x2, [sp, #96]
    bl   _memcpy
    ldr  x9, [sp, #128]
    cmp  x9, #2
    b.ne Lff_crc
    ADRL x0, _fx_rd
    ldr  x9, [sp, #96]
    add  x0, x0, x9
    ADRL x1, _fx_c1
    ldr  x2, [sp, #104]
    bl   _memcpy
Lff_crc:
    ADRL x0, _fx_rd
    mov  x1, x20
    bl   _fx_crc
    mov  w22, w0
    ADRL x9, _fx_rd
    add  x9, x9, x20
    ldrb w10, [x9]
    ldrb w11, [x9, #1]
    orr  w10, w10, w11, lsl #8
    cmp  w22, w10
    b.ne Lff_bad
    ldr  w9, [x19, #FX_LCRC]          // the second copy of the frame we just had?
    cmp  w9, w22
    b.ne Lff_new
    ldr  w9, [x19, #FX_LLEN]
    cmp  w9, w20
    b.ne Lff_new
    ldr  x9, [x19, #FX_BITS]
    ldr  x10, [x19, #FX_LBIT]
    sub  x9, x9, x10
    MOVI x10, DUP_BITS
    cmp  x9, x10
    b.hs Lff_new
    ADRL x9, _fx_dup
    ldr  x10, [x9]
    add  x10, x10, #1
    str  x10, [x9]
    LEAVE 64
Lff_new:
    str  w22, [x19, #FX_LCRC]
    str  w20, [x19, #FX_LLEN]
    ldr  x9, [x19, #FX_BITS]
    str  x9, [x19, #FX_LBIT]
    ldr  x9, [sp, #136]
    ADRL x10, _fx_last
    str  x9, [x10]
    ADRL x10, _fx_ok
    cbz  x9, 1f
    ADRL x10, _fx_fixed
1:  ldr  x11, [x10]
    add  x11, x11, #1
    str  x11, [x10]
    ADRL x0, _fx_rd
    mov  w1, w20
    bl   _fm_frame_in
    LEAVE 64
Lff_bad:                              // lost — unless it was a copy of the one we just had
    ldr  w9, [x19, #FX_LLEN]
    cbz  w9, Lff_bad_count
    ldr  x9, [x19, #FX_BITS]
    ldr  x10, [x19, #FX_LBIT]
    sub  x9, x9, x10
    MOVI x10, DUP_BITS
    cmp  x9, x10
    b.lo Lff_bad_done
Lff_bad_count:
    ADRL x10, _fx_last
    mov  x9, #-1
    str  x9, [x10]
    ADRL x10, _fx_fail
    ldr  x11, [x10]
    add  x11, x11, #1
    str  x11, [x10]
Lff_bad_done:
    LEAVE 64
