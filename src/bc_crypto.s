// bc_crypto.s — the cryptography bitchat speaks, for the walled-off bitchat service
// (docs/bitchat_roadmap.md, Phase 1). Pure functions: no Objective-C, no frameworks,
// no globals, so the same code runs on the Mac, on the iPhone and under qemu.
// Nothing here touches asmmesh's own keys (ident.s, crypto.s).
//
//   SHA-256, SHA-512            FIPS 180-4            (incremental and one-shot)
//   HMAC-SHA256, HKDF-SHA256    RFC 2104 / RFC 5869
//   ChaCha20, Poly1305, AEAD    RFC 8439              (96-bit nonce, 32-bit counter)
//   X25519                      RFC 7748
//   Ed25519                     RFC 8032              (sign, verify; S < L enforced)
//
// Secrets never pick a branch or a memory address: the ladder, the scalar
// multiplication and the scalar reduction use masks and csel. Verification works
// on public data only.
//
// Field elements mod p = 2^255 - 19 are four 64-bit limbs, little-endian, kept
// below 2^256 between operations and made canonical only by Lfe_freeze.
// Points are extended coordinates (X, Y, Z, T), 128 bytes.

.include "macros.inc"

.set HC_COUNT, 0                          // hash context: bytes hashed so far
.set HC_NBUF, 8                           //   bytes waiting in the buffer
.set HC_BUF, 16                           //   up to one block (128)
.set HC_STATE, 144                        //   8 words (32 or 64 bytes)
.set HC_SIZE, 208
.set HM_K, 208                            // HMAC context: hash context, then the padded key
.set HM_SIZE, 272

// x0 = r, x1 = a, x2 = b as base + offset pairs, then bl fn
.macro F3 fn, rb, ro, ab, ao, bb, bo
    add  x0, \rb, #\ro
    add  x1, \ab, #\ao
    add  x2, \bb, #\bo
    bl   \fn
.endm

// c2:c1:c0 += a * b
.macro MAC a, b, c0, c1, c2
    mul   x16, \a, \b
    umulh x17, \a, \b
    adds  \c0, \c0, x16
    adcs  \c1, \c1, x17
    adc   \c2, \c2, xzr
.endm

// [base .. base+63] = [x1] * [x2], 256 x 256 -> 512 bits (column by column).
// Uses x3-x13, x16, x17.
.macro MUL256 base
    ldp  x3, x4, [x1]
    ldp  x5, x6, [x1, #16]
    ldp  x7, x8, [x2]
    ldp  x9, x10, [x2, #16]
    mul   x11, x3, x7
    umulh x12, x3, x7
    mov   x13, #0
    str   x11, [\base]
    mov   x11, #0
    MAC  x3, x8, x12, x13, x11
    MAC  x4, x7, x12, x13, x11
    str  x12, [\base, #8]
    mov  x12, #0
    MAC  x3, x9, x13, x11, x12
    MAC  x4, x8, x13, x11, x12
    MAC  x5, x7, x13, x11, x12
    str  x13, [\base, #16]
    mov  x13, #0
    MAC  x3, x10, x11, x12, x13
    MAC  x4, x9, x11, x12, x13
    MAC  x5, x8, x11, x12, x13
    MAC  x6, x7, x11, x12, x13
    str  x11, [\base, #24]
    mov  x11, #0
    MAC  x4, x10, x12, x13, x11
    MAC  x5, x9, x12, x13, x11
    MAC  x6, x8, x12, x13, x11
    str  x12, [\base, #32]
    mov  x12, #0
    MAC  x5, x10, x13, x11, x12
    MAC  x6, x9, x13, x11, x12
    str  x13, [\base, #40]
    mov  x13, #0
    MAC  x6, x10, x11, x12, x13
    str  x11, [\base, #48]
    str  x12, [\base, #56]
.endm

// ChaCha20 quarter round on four w registers
.macro QR a, b, c, d
    add  \a, \a, \b
    eor  \d, \d, \a
    ror  \d, \d, #16
    add  \c, \c, \d
    eor  \b, \b, \c
    ror  \b, \b, #20
    add  \a, \a, \b
    eor  \d, \d, \a
    ror  \d, \d, #24
    add  \c, \c, \d
    eor  \b, \b, \c
    ror  \b, \b, #25
.endm

.section __TEXT,__const
.p2align 3
Lk256:
    .word 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    .word 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    .word 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    .word 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    .word 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    .word 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    .word 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    .word 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    .word 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    .word 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    .word 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    .word 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    .word 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    .word 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    .word 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    .word 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
Liv256:
    .word 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    .word 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
Lk512:
    .quad 0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc
    .quad 0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118
    .quad 0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2
    .quad 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694
    .quad 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65
    .quad 0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5
    .quad 0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4
    .quad 0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70
    .quad 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df
    .quad 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b
    .quad 0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30
    .quad 0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8
    .quad 0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8
    .quad 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3
    .quad 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec
    .quad 0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b
    .quad 0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178
    .quad 0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b
    .quad 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c
    .quad 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817
Liv512:
    .quad 0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1
    .quad 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
Lchacha_c:
    .word 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574    // "expand 32-byte k"
Lpoly_clamp:
    .quad 0x0ffffffc0fffffff, 0x0ffffffc0ffffffc
Lfe_zero:
    .quad 0, 0, 0, 0
Lfe_one:
    .quad 1, 0, 0, 0
Lfe_a24:
    .quad 121665, 0, 0, 0
Lfe_d:
    .quad 0x75eb4dca135978a3, 0x00700a4d4141d8ab, 0x8cc740797779e898, 0x52036cee2b6ffe73
Lfe_2d:
    .quad 0xebd69b9426b2f159, 0x00e0149a8283b156, 0x198e80f2eef3d130, 0x2406d9dc56dffce7
Lfe_sqrtm1:
    .quad 0xc4ee1b274a0ea0b0, 0x2f431806ad2fe478, 0x2b4d00993dfbd7a7, 0x2b8324804fc1df0b
Lsc_L:
    .quad 0x5812631a5cf5d3ed, 0x14def9dea2f79cd6, 0x0000000000000000, 0x1000000000000000
Lexp_inv:                                 // p - 2
    .quad 0xffffffffffffffeb, 0xffffffffffffffff, 0xffffffffffffffff, 0x7fffffffffffffff
Lexp_2523:                                // (p - 5) / 8
    .quad 0xfffffffffffffffd, 0xffffffffffffffff, 0xffffffffffffffff, 0x0fffffffffffffff
Lge_base:                                 // B: X, Y, Z = 1, T = XY
    .quad 0xc9562d608f25d51a, 0x692cc7609525a7b2, 0xc0a4e231fdd6dc5c, 0x216936d3cd6e53fe
    .quad 0x6666666666666658, 0x6666666666666666, 0x6666666666666666, 0x6666666666666666
    .quad 1, 0, 0, 0
    .quad 0x6dde8ab3a5b7dda3, 0x20f09f80775152f5, 0x66ea4e8e64abe37d, 0x67875f0fd78b7665

.text
.p2align 2

// ---------------------------------------------------------------------------
// small helpers

// Lmemcpy(x0 dst, x1 src, x2 n) — uses x9, x10
Lmemcpy:
    mov  x9, #0
1:  cmp  x9, x2
    b.hs 2f
    ldrb w10, [x1, x9]
    strb w10, [x0, x9]
    add  x9, x9, #1
    b    1b
2:  ret

// _bc_wipe(x0 p, x1 n) — zero n bytes (for keys and other secrets)
.globl _bc_wipe
_bc_wipe:
Lmemzero:
    mov  x9, #0
1:  cmp  x9, x1
    b.hs 2f
    strb wzr, [x0, x9]
    add  x9, x9, #1
    b    1b
2:  ret

// long _bc_memeq(x0 a, x1 b, x2 n) -> 1 equal, 0 not; time depends only on n
.globl _bc_memeq
_bc_memeq:
    mov  x9, #0
    mov  w11, #0
1:  cmp  x9, x2
    b.hs 2f
    ldrb w10, [x0, x9]
    ldrb w12, [x1, x9]
    eor  w10, w10, w12
    orr  w11, w11, w10
    add  x9, x9, #1
    b    1b
2:  cmp  w11, #0
    cset x0, eq
    ret

// Lcmov(x0 dst, x1 src, x2 n (multiple of 8), x3 bit): dst = bit ? src : dst
Lcmov:
    neg  x3, x3
    mov  x9, #0
1:  cmp  x9, x2
    b.hs 2f
    ldr  x10, [x0, x9]
    ldr  x11, [x1, x9]
    eor  x11, x11, x10
    and  x11, x11, x3
    eor  x10, x10, x11
    str  x10, [x0, x9]
    add  x9, x9, #8
    b    1b
2:  ret

// ---------------------------------------------------------------------------
// SHA-256 and SHA-512

// Lsha256_block(x0 state[8] (native words), x1 64-byte block) — leaf
Lsha256_block:
    sub  sp, sp, #256                     // W[0..63]
    ldp  w2, w3, [x0]
    ldp  w4, w5, [x0, #8]
    ldp  w6, w7, [x0, #16]
    ldp  w8, w9, [x0, #24]
    ADRL x16, Lk256
    mov  x17, #0
Ls2_loop:
    cmp  x17, #16
    b.hs Ls2_sched
    ldr  w10, [x1, x17, lsl #2]
    rev  w10, w10
    b    Ls2_have
Ls2_sched:
    sub  x11, x17, #2
    ldr  w11, [sp, x11, lsl #2]
    ror  w10, w11, #17
    eor  w10, w10, w11, ror #19
    eor  w10, w10, w11, lsr #10
    sub  x11, x17, #7
    ldr  w11, [sp, x11, lsl #2]
    add  w10, w10, w11
    sub  x11, x17, #15
    ldr  w11, [sp, x11, lsl #2]
    ror  w12, w11, #7
    eor  w12, w12, w11, ror #18
    eor  w12, w12, w11, lsr #3
    add  w10, w10, w12
    sub  x11, x17, #16
    ldr  w11, [sp, x11, lsl #2]
    add  w10, w10, w11
Ls2_have:
    str  w10, [sp, x17, lsl #2]
    add  w10, w10, w9                     // T1 = W + h + K + S1(e) + Ch(e,f,g)
    ldr  w11, [x16, x17, lsl #2]
    add  w10, w10, w11
    ror  w11, w6, #6
    eor  w11, w11, w6, ror #11
    eor  w11, w11, w6, ror #25
    add  w10, w10, w11
    and  w11, w6, w7
    bic  w12, w8, w6
    orr  w11, w11, w12
    add  w10, w10, w11
    ror  w11, w2, #2                      // T2 = S0(a) + Maj(a,b,c)
    eor  w11, w11, w2, ror #13
    eor  w11, w11, w2, ror #22
    orr  w12, w2, w3
    and  w12, w12, w4
    and  w13, w2, w3
    orr  w12, w12, w13
    add  w11, w11, w12
    mov  w9, w8
    mov  w8, w7
    mov  w7, w6
    add  w6, w5, w10
    mov  w5, w4
    mov  w4, w3
    mov  w3, w2
    add  w2, w10, w11
    add  x17, x17, #1
    cmp  x17, #64
    b.lo Ls2_loop
    ldp  w10, w11, [x0]
    add  w2, w2, w10
    add  w3, w3, w11
    stp  w2, w3, [x0]
    ldp  w10, w11, [x0, #8]
    add  w4, w4, w10
    add  w5, w5, w11
    stp  w4, w5, [x0, #8]
    ldp  w10, w11, [x0, #16]
    add  w6, w6, w10
    add  w7, w7, w11
    stp  w6, w7, [x0, #16]
    ldp  w10, w11, [x0, #24]
    add  w8, w8, w10
    add  w9, w9, w11
    stp  w8, w9, [x0, #24]
    add  sp, sp, #256
    ret

// Lsha512_block(x0 state[8], x1 128-byte block) — leaf
Lsha512_block:
    sub  sp, sp, #640                     // W[0..79]
    ldp  x2, x3, [x0]
    ldp  x4, x5, [x0, #16]
    ldp  x6, x7, [x0, #32]
    ldp  x8, x9, [x0, #48]
    ADRL x16, Lk512
    mov  x17, #0
Ls5_loop:
    cmp  x17, #16
    b.hs Ls5_sched
    ldr  x10, [x1, x17, lsl #3]
    rev  x10, x10
    b    Ls5_have
Ls5_sched:
    sub  x11, x17, #2
    ldr  x11, [sp, x11, lsl #3]
    ror  x10, x11, #19
    eor  x10, x10, x11, ror #61
    eor  x10, x10, x11, lsr #6
    sub  x11, x17, #7
    ldr  x11, [sp, x11, lsl #3]
    add  x10, x10, x11
    sub  x11, x17, #15
    ldr  x11, [sp, x11, lsl #3]
    ror  x12, x11, #1
    eor  x12, x12, x11, ror #8
    eor  x12, x12, x11, lsr #7
    add  x10, x10, x12
    sub  x11, x17, #16
    ldr  x11, [sp, x11, lsl #3]
    add  x10, x10, x11
Ls5_have:
    str  x10, [sp, x17, lsl #3]
    add  x10, x10, x9
    ldr  x11, [x16, x17, lsl #3]
    add  x10, x10, x11
    ror  x11, x6, #14
    eor  x11, x11, x6, ror #18
    eor  x11, x11, x6, ror #41
    add  x10, x10, x11
    and  x11, x6, x7
    bic  x12, x8, x6
    orr  x11, x11, x12
    add  x10, x10, x11
    ror  x11, x2, #28
    eor  x11, x11, x2, ror #34
    eor  x11, x11, x2, ror #39
    orr  x12, x2, x3
    and  x12, x12, x4
    and  x13, x2, x3
    orr  x12, x12, x13
    add  x11, x11, x12
    mov  x9, x8
    mov  x8, x7
    mov  x7, x6
    add  x6, x5, x10
    mov  x5, x4
    mov  x4, x3
    mov  x3, x2
    add  x2, x10, x11
    add  x17, x17, #1
    cmp  x17, #80
    b.lo Ls5_loop
    ldp  x10, x11, [x0]
    add  x2, x2, x10
    add  x3, x3, x11
    stp  x2, x3, [x0]
    ldp  x10, x11, [x0, #16]
    add  x4, x4, x10
    add  x5, x5, x11
    stp  x4, x5, [x0, #16]
    ldp  x10, x11, [x0, #32]
    add  x6, x6, x10
    add  x7, x7, x11
    stp  x6, x7, [x0, #32]
    ldp  x10, x11, [x0, #48]
    add  x8, x8, x10
    add  x9, x9, x11
    stp  x8, x9, [x0, #48]
    add  sp, sp, #640
    ret

// Lhash_update(x0 ctx, x1 p, x2 n, x3 block size, x4 block function)
Lhash_update:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    ldr  x9, [x19, #HC_COUNT]
    add  x9, x9, x21
    str  x9, [x19, #HC_COUNT]
    ldr  x24, [x19, #HC_NBUF]
    cbz  x24, Lhu_full
    sub  x2, x22, x24                     // fill the buffer first
    cmp  x2, x21
    csel x2, x2, x21, ls
    add  x0, x19, #HC_BUF
    add  x0, x0, x24
    mov  x1, x20
    add  x20, x20, x2
    sub  x21, x21, x2
    add  x24, x24, x2
    bl   Lmemcpy
    cmp  x24, x22
    b.ne Lhu_keep
    add  x0, x19, #HC_STATE
    add  x1, x19, #HC_BUF
    blr  x23
    mov  x24, #0
Lhu_full:
    cmp  x21, x22
    b.lo Lhu_rest
    add  x0, x19, #HC_STATE
    mov  x1, x20
    blr  x23
    add  x20, x20, x22
    sub  x21, x21, x22
    b    Lhu_full
Lhu_rest:
    add  x0, x19, #HC_BUF
    mov  x1, x20
    mov  x2, x21
    bl   Lmemcpy
    mov  x24, x21
Lhu_keep:
    str  x24, [x19, #HC_NBUF]
    LEAVE 0

// Lhash_final(x0 ctx, x1 out, x2 block size, x3 block function, x4 length bytes, x5 word size)
Lhash_final:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    mov  x24, x5
    ldr  x9, [x19, #HC_NBUF]
    add  x10, x19, #HC_BUF
    mov  w11, #0x80
    strb w11, [x10, x9]
    add  x9, x9, #1
    sub  x12, x21, x23
    cmp  x9, x12
    b.ls Lhf_pad
1:  cmp  x9, x21                          // no room for the length: one more block
    b.hs 2f
    strb wzr, [x10, x9]
    add  x9, x9, #1
    b    1b
2:  add  x0, x19, #HC_STATE
    mov  x1, x10
    blr  x22
    mov  x9, #0
    add  x10, x19, #HC_BUF
Lhf_pad:
    sub  x12, x21, #8
1:  cmp  x9, x12
    b.hs 2f
    strb wzr, [x10, x9]
    add  x9, x9, #1
    b    1b
2:  ldr  x11, [x19, #HC_COUNT]
    lsl  x11, x11, #3
    rev  x11, x11
    str  x11, [x10, x12]
    add  x0, x19, #HC_STATE
    mov  x1, x10
    blr  x22
    add  x9, x19, #HC_STATE
    mov  x10, #0
1:  cmp  x24, #4
    b.ne 2f
    ldr  w11, [x9, x10, lsl #2]
    rev  w11, w11
    str  w11, [x20, x10, lsl #2]
    b    3f
2:  ldr  x11, [x9, x10, lsl #3]
    rev  x11, x11
    str  x11, [x20, x10, lsl #3]
3:  add  x10, x10, #1
    cmp  x10, #8
    b.lo 1b
    LEAVE 0

// void _bc_sha256_init(ctx)   ctx is HC_SIZE (208) bytes
.globl _bc_sha256_init
_bc_sha256_init:
    stp  xzr, xzr, [x0, #HC_COUNT]
    ADRL x9, Liv256
    ldp  x10, x11, [x9]
    stp  x10, x11, [x0, #HC_STATE]
    ldp  x10, x11, [x9, #16]
    stp  x10, x11, [x0, #(HC_STATE + 16)]
    ret

// void _bc_sha256_update(ctx, p, n)
.globl _bc_sha256_update
_bc_sha256_update:
    mov  x3, #64
    adr  x4, Lsha256_block
    b    Lhash_update

// void _bc_sha256_final(ctx, out[32])
.globl _bc_sha256_final
_bc_sha256_final:
    mov  x2, #64
    adr  x3, Lsha256_block
    mov  x4, #8
    mov  x5, #4
    b    Lhash_final

// void _bc_sha256(p, n, out[32])
.globl _bc_sha256
_bc_sha256:
    ENTER HC_SIZE
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x0, sp, #96
    bl   _bc_sha256_init
    add  x0, sp, #96
    mov  x1, x19
    mov  x2, x20
    bl   _bc_sha256_update
    add  x0, sp, #96
    mov  x1, x21
    bl   _bc_sha256_final
    LEAVE HC_SIZE

// void _bc_sha512_init(ctx)
.globl _bc_sha512_init
_bc_sha512_init:
    stp  xzr, xzr, [x0, #HC_COUNT]
    ADRL x9, Liv512
    mov  x12, #0
1:  ldr  x10, [x9, x12]
    add  x11, x0, #HC_STATE
    str  x10, [x11, x12]
    add  x12, x12, #8
    cmp  x12, #64
    b.lo 1b
    ret

// void _bc_sha512_update(ctx, p, n)
.globl _bc_sha512_update
_bc_sha512_update:
    mov  x3, #128
    adr  x4, Lsha512_block
    b    Lhash_update

// void _bc_sha512_final(ctx, out[64])
.globl _bc_sha512_final
_bc_sha512_final:
    mov  x2, #128
    adr  x3, Lsha512_block
    mov  x4, #16
    mov  x5, #8
    b    Lhash_final

// void _bc_sha512(p, n, out[64])
.globl _bc_sha512
_bc_sha512:
    ENTER HC_SIZE
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x0, sp, #96
    bl   _bc_sha512_init
    add  x0, sp, #96
    mov  x1, x19
    mov  x2, x20
    bl   _bc_sha512_update
    add  x0, sp, #96
    mov  x1, x21
    bl   _bc_sha512_final
    LEAVE HC_SIZE

// ---------------------------------------------------------------------------
// HMAC-SHA256 and HKDF-SHA256

// void _bc_hmac256_init(h, key, klen)   h is HM_SIZE (272) bytes
.globl _bc_hmac256_init
_bc_hmac256_init:
    ENTER 64                              // [96] padded key ^ 0x36
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x0, x19, #HM_K
    mov  x1, #64
    bl   Lmemzero
    cmp  x21, #64
    b.hi 1f
    add  x0, x19, #HM_K
    mov  x1, x20
    mov  x2, x21
    bl   Lmemcpy
    b    2f
1:  mov  x0, x20                          // a long key is hashed first
    mov  x1, x21
    add  x2, x19, #HM_K
    bl   _bc_sha256
2:  mov  x9, #0
3:  add  x10, x19, #HM_K
    ldrb w10, [x10, x9]
    mov  w12, #0x36
    eor  w10, w10, w12
    add  x11, sp, #96
    strb w10, [x11, x9]
    add  x9, x9, #1
    cmp  x9, #64
    b.lo 3b
    mov  x0, x19
    bl   _bc_sha256_init
    mov  x0, x19
    add  x1, sp, #96
    mov  x2, #64
    bl   _bc_sha256_update
    add  x0, sp, #96
    mov  x1, #64
    bl   Lmemzero
    LEAVE 64

// void _bc_hmac256_update(h, p, n)
.globl _bc_hmac256_update
_bc_hmac256_update:
    b    _bc_sha256_update

// void _bc_hmac256_final(h, out[32]) — also wipes the key held in h
.globl _bc_hmac256_final
_bc_hmac256_final:
    ENTER 96                              // [96] inner hash  [128] padded key ^ 0x5c
    mov  x19, x0
    mov  x20, x1
    add  x1, sp, #96
    bl   _bc_sha256_final
    mov  x9, #0
1:  add  x10, x19, #HM_K
    ldrb w10, [x10, x9]
    mov  w12, #0x5c
    eor  w10, w10, w12
    add  x11, sp, #128
    strb w10, [x11, x9]
    add  x9, x9, #1
    cmp  x9, #64
    b.lo 1b
    mov  x0, x19
    bl   _bc_sha256_init
    mov  x0, x19
    add  x1, sp, #128
    mov  x2, #64
    bl   _bc_sha256_update
    mov  x0, x19
    add  x1, sp, #96
    mov  x2, #32
    bl   _bc_sha256_update
    mov  x0, x19
    mov  x1, x20
    bl   _bc_sha256_final
    add  x0, sp, #96
    mov  x1, #96
    bl   Lmemzero
    add  x0, x19, #HM_K
    mov  x1, #64
    bl   Lmemzero
    LEAVE 96

// void _bc_hmac256(key, klen, msg, mlen, out[32])
.globl _bc_hmac256
_bc_hmac256:
    ENTER HM_SIZE
    mov  x19, x2
    mov  x20, x3
    mov  x21, x4
    mov  x2, x1
    mov  x1, x0
    add  x0, sp, #96
    bl   _bc_hmac256_init
    add  x0, sp, #96
    mov  x1, x19
    mov  x2, x20
    bl   _bc_hmac256_update
    add  x0, sp, #96
    mov  x1, x21
    bl   _bc_hmac256_final
    LEAVE HM_SIZE

// long _bc_hkdf256(salt, slen, ikm, ilen, info, infolen, out, L) -> 0, or -1 if L > 255*32.
// An empty salt means 32 zero bytes, as RFC 5869 says (HMAC pads either to the same key).
.globl _bc_hkdf256
_bc_hkdf256:
    ENTER 352                             // [96] HMAC  [368] PRK  [400] T  [432] counter byte
    mov  x9, #8160
    cmp  x7, x9
    b.hi Lhk_bad
    mov  x19, x4                          // info
    mov  x20, x5                          // info length
    mov  x21, x6                          // out
    mov  x22, x7                          // bytes still to make
    mov  x23, #0                          // length of T (0 for T(0))
    mov  x24, #0                          // block counter
    add  x4, sp, #368
    bl   _bc_hmac256                      // PRK = HMAC(salt, ikm)
Lhk_loop:
    cbz  x22, Lhk_done
    add  x24, x24, #1
    add  x0, sp, #96
    add  x1, sp, #368
    mov  x2, #32
    bl   _bc_hmac256_init
    add  x0, sp, #96
    add  x1, sp, #400
    mov  x2, x23
    bl   _bc_hmac256_update
    add  x0, sp, #96
    mov  x1, x19
    mov  x2, x20
    bl   _bc_hmac256_update
    strb w24, [sp, #432]
    add  x0, sp, #96
    add  x1, sp, #432
    mov  x2, #1
    bl   _bc_hmac256_update
    add  x0, sp, #96
    add  x1, sp, #400
    bl   _bc_hmac256_final
    mov  x23, #32
    mov  x2, #32
    cmp  x22, #32
    csel x2, x22, x2, lo
    mov  x0, x21
    add  x1, sp, #400
    add  x21, x21, x2
    sub  x22, x22, x2
    bl   Lmemcpy
    b    Lhk_loop
Lhk_done:
    add  x0, sp, #96
    mov  x1, #352
    bl   Lmemzero
    mov  x0, #0
    LEAVE 352
Lhk_bad:
    mov  x0, #-1
    LEAVE 352

// ---------------------------------------------------------------------------
// ChaCha20 (RFC 8439 §2.4)

// void _bc_chacha20(key[32], nonce[12], counter (w2), in, out, n) — out = in ^ keystream;
// in and out may be the same buffer
.globl _bc_chacha20
_bc_chacha20:
    ENTER 144                             // [96] state  [160] keystream block  [224] saved x25
    str  x25, [sp, #224]
    mov  x23, x3
    mov  x24, x4
    mov  x25, x5
    ADRL x9, Lchacha_c
    ldp  x10, x11, [x9]
    stp  x10, x11, [sp, #96]
    ldp  x10, x11, [x0]
    stp  x10, x11, [sp, #112]
    ldp  x10, x11, [x0, #16]
    stp  x10, x11, [sp, #128]
    str  w2, [sp, #144]
    ldr  w10, [x1]
    str  w10, [sp, #148]
    ldr  x10, [x1, #4]
    str  x10, [sp, #152]
Lcc_block:
    cbz  x25, Lcc_done
    ldp  w3, w4, [sp, #96]
    ldp  w5, w6, [sp, #104]
    ldp  w7, w8, [sp, #112]
    ldp  w9, w10, [sp, #120]
    ldp  w11, w12, [sp, #128]
    ldp  w13, w14, [sp, #136]
    ldp  w15, w16, [sp, #144]
    ldp  w17, w19, [sp, #152]
    mov  w20, #10
Lcc_round:
    QR   w3, w7, w11, w15
    QR   w4, w8, w12, w16
    QR   w5, w9, w13, w17
    QR   w6, w10, w14, w19
    QR   w3, w8, w13, w19
    QR   w4, w9, w14, w15
    QR   w5, w10, w11, w16
    QR   w6, w7, w12, w17
    subs w20, w20, #1
    b.ne Lcc_round
    ldp  w0, w1, [sp, #96]
    add  w3, w3, w0
    add  w4, w4, w1
    stp  w3, w4, [sp, #160]
    ldp  w0, w1, [sp, #104]
    add  w5, w5, w0
    add  w6, w6, w1
    stp  w5, w6, [sp, #168]
    ldp  w0, w1, [sp, #112]
    add  w7, w7, w0
    add  w8, w8, w1
    stp  w7, w8, [sp, #176]
    ldp  w0, w1, [sp, #120]
    add  w9, w9, w0
    add  w10, w10, w1
    stp  w9, w10, [sp, #184]
    ldp  w0, w1, [sp, #128]
    add  w11, w11, w0
    add  w12, w12, w1
    stp  w11, w12, [sp, #192]
    ldp  w0, w1, [sp, #136]
    add  w13, w13, w0
    add  w14, w14, w1
    stp  w13, w14, [sp, #200]
    ldp  w0, w1, [sp, #144]
    add  w15, w15, w0
    add  w16, w16, w1
    stp  w15, w16, [sp, #208]
    ldp  w0, w1, [sp, #152]
    add  w17, w17, w0
    add  w19, w19, w1
    stp  w17, w19, [sp, #216]
    ldr  w0, [sp, #144]                   // next block
    add  w0, w0, #1
    str  w0, [sp, #144]
    mov  x0, #64
    cmp  x25, #64
    csel x0, x25, x0, lo
    mov  x9, #0
    add  x10, sp, #160
1:  ldrb w1, [x23, x9]
    ldrb w2, [x10, x9]
    eor  w1, w1, w2
    strb w1, [x24, x9]
    add  x9, x9, #1
    cmp  x9, x0
    b.lo 1b
    add  x23, x23, x0
    add  x24, x24, x0
    sub  x25, x25, x0
    b    Lcc_block
Lcc_done:
    add  x0, sp, #96
    mov  x1, #128
    bl   Lmemzero
    ldr  x25, [sp, #224]
    LEAVE 144

// ---------------------------------------------------------------------------
// Poly1305 (RFC 8439 §2.5), 64-bit limbs. State (64 bytes):
//   h0 h1 h2 at 0/8/16, r0 r1 at 24/32, s1 = r1 + r1/4 at 40, s (the pad) at 48/56

// Lpoly_init(x0 st, x1 key[32]) — leaf
Lpoly_init:
    ldp  x2, x3, [x1]
    ADRL x9, Lpoly_clamp
    ldp  x4, x5, [x9]
    and  x2, x2, x4
    and  x3, x3, x5
    stp  xzr, xzr, [x0]
    str  xzr, [x0, #16]
    stp  x2, x3, [x0, #24]
    add  x6, x3, x3, lsr #2
    str  x6, [x0, #40]
    ldp  x2, x3, [x1, #16]
    stp  x2, x3, [x0, #48]
    ret

// Lpoly_blocks(x0 st, x1 p, x2 number of 16-byte blocks, x3 high bit (1, or 0 for a short last block))
Lpoly_blocks:
    ldp  x4, x5, [x0]
    ldr  x6, [x0, #16]
    ldp  x7, x8, [x0, #24]
    ldr  x9, [x0, #40]
1:  cbz  x2, 2f
    ldp  x10, x11, [x1], #16
    adds x4, x4, x10                      // h += m
    adcs x5, x5, x11
    adc  x6, x6, x3
    mul   x10, x4, x7                     // d0 = h0 r0 + h1 s1
    umulh x11, x4, x7
    mul   x12, x5, x9
    umulh x13, x5, x9
    adds  x10, x10, x12
    adc   x11, x11, x13
    mul   x12, x4, x8                     // d1 = h0 r1 + h1 r0 + h2 s1
    umulh x13, x4, x8
    mul   x14, x5, x7
    umulh x15, x5, x7
    adds  x12, x12, x14
    adc   x13, x13, x15
    mul   x14, x6, x9
    adds  x12, x12, x14
    adc   x13, x13, xzr
    mul   x6, x6, x7                      // d2 = h2 r0
    adds  x12, x12, x11
    adc   x13, x13, xzr
    mov   x4, x10
    mov   x5, x12
    add   x6, x6, x13
    and   x14, x6, #0xfffffffffffffffc    // fold 2^130 = 5 back in
    add   x14, x14, x6, lsr #2
    and   x6, x6, #3
    adds  x4, x4, x14
    adcs  x5, x5, xzr
    adc   x6, x6, xzr
    sub   x2, x2, #1
    b     1b
2:  stp  x4, x5, [x0]
    str  x6, [x0, #16]
    ret

// Lpoly_final(x0 st, x1 tag[16]) — leaf
Lpoly_final:
    ldp  x4, x5, [x0]
    ldr  x6, [x0, #16]
    adds x7, x4, #5                       // h - p = h + 5 - 2^130
    adcs x8, x5, xzr
    adc  x9, x6, xzr
    lsr  x9, x9, #2
    cmp  x9, #0
    csel x4, x7, x4, ne
    csel x5, x8, x5, ne
    ldp  x10, x11, [x0, #48]
    adds x4, x4, x10
    adc  x5, x5, x11
    stp  x4, x5, [x1]
    ret

// Lpoly_padded(x0 st, x1 p, x2 n) — n bytes, the last block zero-padded to 16 (the AEAD layout)
Lpoly_padded:
    ENTER 16                              // [96] last block
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    lsr  x2, x21, #4
    mov  x3, #1
    bl   Lpoly_blocks
    ands x22, x21, #15
    b.eq 1f
    stp  xzr, xzr, [sp, #96]
    add  x0, sp, #96
    and  x9, x21, #~15
    add  x1, x20, x9
    mov  x2, x22
    bl   Lmemcpy
    mov  x0, x19
    add  x1, sp, #96
    mov  x2, #1
    mov  x3, #1
    bl   Lpoly_blocks
1:  LEAVE 16

// void _bc_poly1305(key[32], msg, n, tag[16])
.globl _bc_poly1305
_bc_poly1305:
    ENTER 80                              // [96] state  [160] last block
    mov  x19, x1
    mov  x20, x2
    mov  x21, x3
    mov  x1, x0
    add  x0, sp, #96
    bl   Lpoly_init
    add  x0, sp, #96
    mov  x1, x19
    lsr  x2, x20, #4
    mov  x3, #1
    bl   Lpoly_blocks
    ands x22, x20, #15
    b.eq 1f
    stp  xzr, xzr, [sp, #160]
    add  x0, sp, #160
    and  x9, x20, #~15
    add  x1, x19, x9
    mov  x2, x22
    bl   Lmemcpy
    add  x9, sp, #160
    mov  w10, #1
    strb w10, [x9, x22]
    add  x0, sp, #96
    add  x1, sp, #160
    mov  x2, #1
    mov  x3, #0
    bl   Lpoly_blocks
1:  add  x0, sp, #96
    mov  x1, x21
    bl   Lpoly_final
    add  x0, sp, #96
    mov  x1, #80
    bl   Lmemzero
    LEAVE 80

// ---------------------------------------------------------------------------
// ChaCha20-Poly1305 AEAD (RFC 8439 §2.8)

// Laead_tag(x0 key, x1 nonce, x2 ad, x3 adlen, x4 ct, x5 n, x6 tag[16]) — the Poly1305 tag
Laead_tag:
    ENTER 160                             // [96] state  [160] one-time key  [224] lengths  [240] tag out
    mov  x19, x2
    mov  x20, x3
    mov  x21, x4
    mov  x22, x5
    str  x6, [sp, #240]
    mov  x23, x0
    mov  x24, x1
    add  x0, sp, #160
    mov  x1, #64
    bl   Lmemzero
    mov  x0, x23
    mov  x1, x24
    mov  w2, #0
    add  x3, sp, #160
    add  x4, sp, #160
    mov  x5, #64
    bl   _bc_chacha20                     // block 0 makes the one-time key
    add  x0, sp, #96
    add  x1, sp, #160
    bl   Lpoly_init
    add  x0, sp, #96
    mov  x1, x19
    mov  x2, x20
    bl   Lpoly_padded
    add  x0, sp, #96
    mov  x1, x21
    mov  x2, x22
    bl   Lpoly_padded
    stp  x20, x22, [sp, #224]
    add  x0, sp, #96
    add  x1, sp, #224
    mov  x2, #1
    mov  x3, #1
    bl   Lpoly_blocks
    add  x0, sp, #96
    ldr  x1, [sp, #240]
    bl   Lpoly_final
    add  x0, sp, #96
    mov  x1, #128
    bl   Lmemzero
    LEAVE 160

// void _bc_aead_seal(key[32], nonce[12], ad, adlen, pt, n, out) — out gets n + 16 bytes:
// the ciphertext, then the tag
.globl _bc_aead_seal
_bc_aead_seal:
    ENTER 16                              // [96] out
    str  x6, [sp, #96]
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x5
    mov  x3, x4
    mov  x4, x6
    mov  w2, #1
    bl   _bc_chacha20                     // (key, nonce, 1, pt, out, n)
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, x22
    ldr  x4, [sp, #96]
    mov  x5, x23
    add  x6, x4, x23
    bl   Laead_tag
    LEAVE 16

// long _bc_aead_open(key[32], nonce[12], ad, adlen, ct, clen, out) -> plaintext length
// (clen - 16), or -1 if the tag is wrong. Nothing is written to out unless the tag is right.
.globl _bc_aead_open
_bc_aead_open:
    ENTER 32                              // [96] computed tag  [112] out
    str  x6, [sp, #112]
    subs x23, x5, #16
    b.lo Lao_bad
    mov  x19, x0
    mov  x20, x1
    mov  x21, x4
    mov  x5, x23
    add  x6, sp, #96
    bl   Laead_tag
    add  x0, sp, #96
    add  x1, x21, x23
    mov  x2, #16
    bl   _bc_memeq
    cbz  x0, Lao_bad
    mov  x0, x19
    mov  x1, x20
    mov  w2, #1
    mov  x3, x21
    ldr  x4, [sp, #112]
    mov  x5, x23
    bl   _bc_chacha20
    mov  x0, x23
    LEAVE 32
Lao_bad:
    mov  x0, #-1
    LEAVE 32

// ---------------------------------------------------------------------------
// Arithmetic mod p = 2^255 - 19 (all leaf unless noted; r may equal a or b)

// Lfe_add(x0 r, x1 a, x2 b)
Lfe_add:
    ldp  x3, x4, [x1]
    ldp  x5, x6, [x1, #16]
    ldp  x7, x8, [x2]
    ldp  x9, x10, [x2, #16]
    adds x3, x3, x7
    adcs x4, x4, x8
    adcs x5, x5, x9
    adcs x6, x6, x10
    mov  x11, #38                         // 2^256 = 38 (mod p)
    csel x12, x11, xzr, cs
    adds x3, x3, x12
    adcs x4, x4, xzr
    adcs x5, x5, xzr
    adcs x6, x6, xzr
    csel x12, x11, xzr, cs
    add  x3, x3, x12
    stp  x3, x4, [x0]
    stp  x5, x6, [x0, #16]
    ret

// Lfe_sub(x0 r, x1 a, x2 b)
Lfe_sub:
    ldp  x3, x4, [x1]
    ldp  x5, x6, [x1, #16]
    ldp  x7, x8, [x2]
    ldp  x9, x10, [x2, #16]
    subs x3, x3, x7
    sbcs x4, x4, x8
    sbcs x5, x5, x9
    sbcs x6, x6, x10
    mov  x11, #38
    csel x12, xzr, x11, cs
    subs x3, x3, x12
    sbcs x4, x4, xzr
    sbcs x5, x5, xzr
    sbcs x6, x6, xzr
    csel x12, xzr, x11, cs
    sub  x3, x3, x12
    stp  x3, x4, [x0]
    stp  x5, x6, [x0, #16]
    ret

// Lfe_mul(x0 r, x1 a, x2 b)
Lfe_mul:
    sub  sp, sp, #64
    MUL256 sp
    ldp  x3, x4, [sp]
    ldp  x5, x6, [sp, #16]
    ldp  x7, x8, [sp, #32]
    ldp  x9, x10, [sp, #48]
    add  sp, sp, #64
    mov   x11, #38                        // low half + 38 * high half
    mul   x12, x7, x11
    umulh x13, x7, x11
    mul   x14, x8, x11
    umulh x15, x8, x11
    adds  x3, x3, x12
    adcs  x4, x4, x14
    mul   x12, x9, x11
    umulh x16, x9, x11
    adcs  x5, x5, x12
    mul   x12, x10, x11
    umulh x17, x10, x11
    adcs  x6, x6, x12
    adc   x17, x17, xzr
    adds  x4, x4, x13
    adcs  x5, x5, x15
    adcs  x6, x6, x16
    adc   x17, x17, xzr
    mul   x17, x17, x11                   // and the few bits above 2^256
    adds  x3, x3, x17
    adcs  x4, x4, xzr
    adcs  x5, x5, xzr
    adcs  x6, x6, xzr
    csel  x12, x11, xzr, cs
    add   x3, x3, x12
    stp  x3, x4, [x0]
    stp  x5, x6, [x0, #16]
    ret

// Lmul256(x0 out[64], x1 a, x2 b) — plain 512-bit product
Lmul256:
    MUL256 x0
    ret

// Lfe_freeze(x0 r, x1 a) — the canonical value, 0 <= r < p
Lfe_freeze:
    ldp  x3, x4, [x1]
    ldp  x5, x6, [x1, #16]
    lsr  x7, x6, #63
    and  x6, x6, #0x7fffffffffffffff
    mov  x8, #19
    mul  x7, x7, x8
    adds x3, x3, x7
    adcs x4, x4, xzr
    adcs x5, x5, xzr
    adc  x6, x6, xzr
    adds x9, x3, #19                      // a >= p  <=>  a + 19 reaches 2^255
    adcs x10, x4, xzr
    adcs x11, x5, xzr
    adc  x12, x6, xzr
    tst  x12, #0x8000000000000000
    and  x12, x12, #0x7fffffffffffffff
    csel x3, x9, x3, ne
    csel x4, x10, x4, ne
    csel x5, x11, x5, ne
    csel x6, x12, x6, ne
    stp  x3, x4, [x0]
    stp  x5, x6, [x0, #16]
    ret

// Lfe_cswap(x0 a, x1 b, x2 bit) — swap a and b when bit = 1
Lfe_cswap:
    neg  x2, x2
    mov  x9, #2
1:  ldp  x3, x4, [x0]
    ldp  x5, x6, [x1]
    eor  x7, x3, x5
    and  x7, x7, x2
    eor  x8, x4, x6
    and  x8, x8, x2
    eor  x3, x3, x7
    eor  x5, x5, x7
    eor  x4, x4, x8
    eor  x6, x6, x8
    stp  x3, x4, [x0], #16
    stp  x5, x6, [x1], #16
    subs x9, x9, #1
    b.ne 1b
    ret

// Lfe_pow(x0 r, x1 a, x2 e) — r = a^e, e a public 255-bit exponent (p - 2 or (p - 5)/8)
Lfe_pow:
    ENTER 64                              // [96] result  [128] a
    mov  x19, x0
    mov  x20, x2
    add  x0, sp, #128
    mov  x2, #32
    bl   Lmemcpy
    mov  x9, #1
    stp  x9, xzr, [sp, #96]
    stp  xzr, xzr, [sp, #112]
    mov  x21, #254
1:  F3   Lfe_mul, sp, 96, sp, 96, sp, 96
    lsr  x9, x21, #3
    ldrb w10, [x20, x9]
    and  x11, x21, #7
    lsr  w10, w10, w11
    tbz  w10, #0, 2f
    F3   Lfe_mul, sp, 96, sp, 96, sp, 128
2:  subs x21, x21, #1
    b.ge 1b
    mov  x0, x19
    add  x1, sp, #96
    mov  x2, #32
    bl   Lmemcpy
    LEAVE 64

// Lfe_inv(x0 r, x1 a) — r = 1/a (0 for a = 0)
Lfe_inv:
    ADRL x2, Lexp_inv
    b    Lfe_pow

// Lfe_iszero(x0 a) -> x0 = 1 if a = 0 (mod p); a must be canonical
Lfe_iszero:
    ldp  x1, x2, [x0]
    ldp  x3, x4, [x0, #16]
    orr  x1, x1, x2
    orr  x3, x3, x4
    orr  x1, x1, x3
    cmp  x1, #0
    cset x0, eq
    ret

// ---------------------------------------------------------------------------
// X25519 (RFC 7748 §5)

// long _bc_x25519(out[32], scalar[32], u[32]) -> 0, or -1 if the result is all zero
// (a low-order point: the caller should refuse it)
.globl _bc_x25519
_bc_x25519:
    ENTER 512
    // [96] k  [128] x1  [160] x2  [192] z2  [224] x3  [256] z3
    // [288] A  [320] AA  [352] B  [384] BB  [416] E  [448] C  [480] D  [512] DA  [544] CB
    mov  x19, x0
    mov  x20, x2
    add  x0, sp, #96
    mov  x2, #32
    bl   Lmemcpy
    ldrb w9, [sp, #96]                    // clamp
    and  w9, w9, #248
    strb w9, [sp, #96]
    ldrb w9, [sp, #127]
    and  w9, w9, #127
    orr  w9, w9, #64
    strb w9, [sp, #127]
    add  x0, sp, #128
    mov  x1, x20
    mov  x2, #32
    bl   Lmemcpy
    ldr  x9, [sp, #152]                   // the top bit of u is ignored
    and  x9, x9, #0x7fffffffffffffff
    str  x9, [sp, #152]
    mov  x9, #1
    stp  x9, xzr, [sp, #160]              // x2 = 1
    stp  xzr, xzr, [sp, #176]
    stp  xzr, xzr, [sp, #192]             // z2 = 0
    stp  xzr, xzr, [sp, #208]
    ldp  x10, x11, [sp, #128]             // x3 = u
    stp  x10, x11, [sp, #224]
    ldp  x10, x11, [sp, #144]
    stp  x10, x11, [sp, #240]
    stp  x9, xzr, [sp, #256]              // z3 = 1
    stp  xzr, xzr, [sp, #272]
    mov  x21, #0                          // swap
    mov  x22, #254
Lx_loop:
    lsr  x9, x22, #3
    add  x10, sp, #96
    ldrb w10, [x10, x9]
    and  x11, x22, #7
    lsr  w10, w10, w11
    and  x23, x10, #1
    eor  x21, x21, x23
    add  x0, sp, #160
    add  x1, sp, #224
    mov  x2, x21
    bl   Lfe_cswap
    add  x0, sp, #192
    add  x1, sp, #256
    mov  x2, x21
    bl   Lfe_cswap
    mov  x21, x23
    F3   Lfe_add, sp, 288, sp, 160, sp, 192     // A = x2 + z2
    F3   Lfe_mul, sp, 320, sp, 288, sp, 288     // AA = A^2
    F3   Lfe_sub, sp, 352, sp, 160, sp, 192     // B = x2 - z2
    F3   Lfe_mul, sp, 384, sp, 352, sp, 352     // BB = B^2
    F3   Lfe_sub, sp, 416, sp, 320, sp, 384     // E = AA - BB
    F3   Lfe_add, sp, 448, sp, 224, sp, 256     // C = x3 + z3
    F3   Lfe_sub, sp, 480, sp, 224, sp, 256     // D = x3 - z3
    F3   Lfe_mul, sp, 512, sp, 480, sp, 288     // DA = D * A
    F3   Lfe_mul, sp, 544, sp, 448, sp, 352     // CB = C * B
    F3   Lfe_add, sp, 224, sp, 512, sp, 544     // x3 = (DA + CB)^2
    F3   Lfe_mul, sp, 224, sp, 224, sp, 224
    F3   Lfe_sub, sp, 256, sp, 512, sp, 544     // z3 = x1 * (DA - CB)^2
    F3   Lfe_mul, sp, 256, sp, 256, sp, 256
    F3   Lfe_mul, sp, 256, sp, 128, sp, 256
    F3   Lfe_mul, sp, 160, sp, 320, sp, 384     // x2 = AA * BB
    add  x0, sp, #192                           // z2 = E * (AA + a24 * E)
    add  x1, sp, #416
    ADRL x2, Lfe_a24
    bl   Lfe_mul
    F3   Lfe_add, sp, 192, sp, 320, sp, 192
    F3   Lfe_mul, sp, 192, sp, 416, sp, 192
    subs x22, x22, #1
    b.ge Lx_loop
    add  x0, sp, #160
    add  x1, sp, #224
    mov  x2, x21
    bl   Lfe_cswap
    add  x0, sp, #192
    add  x1, sp, #256
    mov  x2, x21
    bl   Lfe_cswap
    add  x0, sp, #192
    add  x1, sp, #192
    bl   Lfe_inv
    F3   Lfe_mul, sp, 160, sp, 160, sp, 192
    mov  x0, x19
    add  x1, sp, #160
    bl   Lfe_freeze
    mov  x0, x19
    bl   Lfe_iszero
    neg  x20, x0                          // 0, or -1 for an all-zero result
    add  x0, sp, #96
    mov  x1, #480
    bl   Lmemzero
    mov  x0, x20
    LEAVE 512

// long _bc_x25519_base(out[32], scalar[32]) — the public key for a private key
.globl _bc_x25519_base
_bc_x25519_base:
    ENTER 32                              // [96] u = 9
    mov  x9, #9
    stp  x9, xzr, [sp, #96]
    stp  xzr, xzr, [sp, #112]
    add  x2, sp, #96
    bl   _bc_x25519
    LEAVE 32

// ---------------------------------------------------------------------------
// Edwards25519 points: X 0, Y 32, Z 64, T 96

// Lge_add(x0 r, x1 p, x2 q) — complete addition (also doubles); r may be p or q
Lge_add:
    ENTER 288                             // [96] A [128] B [160] C [192] D [224] E [256] F [288] G [320] H [352] t
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    F3   Lfe_sub, sp, 352, x20, 32, x20, 0      // A = (Y1 - X1)(Y2 - X2)
    F3   Lfe_sub, sp, 96, x21, 32, x21, 0
    F3   Lfe_mul, sp, 96, sp, 352, sp, 96
    F3   Lfe_add, sp, 352, x20, 32, x20, 0      // B = (Y1 + X1)(Y2 + X2)
    F3   Lfe_add, sp, 128, x21, 32, x21, 0
    F3   Lfe_mul, sp, 128, sp, 352, sp, 128
    F3   Lfe_mul, sp, 160, x20, 96, x21, 96     // C = T1 2d T2
    add  x0, sp, #160
    add  x1, sp, #160
    ADRL x2, Lfe_2d
    bl   Lfe_mul
    F3   Lfe_mul, sp, 192, x20, 64, x21, 64     // D = 2 Z1 Z2
    F3   Lfe_add, sp, 192, sp, 192, sp, 192
    F3   Lfe_sub, sp, 224, sp, 128, sp, 96      // E = B - A
    F3   Lfe_sub, sp, 256, sp, 192, sp, 160     // F = D - C
    F3   Lfe_add, sp, 288, sp, 192, sp, 160     // G = D + C
    F3   Lfe_add, sp, 320, sp, 128, sp, 96      // H = B + A
    F3   Lfe_mul, x19, 0, sp, 224, sp, 256      // X3 = E F
    F3   Lfe_mul, x19, 32, sp, 288, sp, 320     // Y3 = G H
    F3   Lfe_mul, x19, 96, sp, 224, sp, 320     // T3 = E H
    F3   Lfe_mul, x19, 64, sp, 256, sp, 288     // Z3 = F G
    LEAVE 288

// Lge_scalarmult(x0 r, x1 p, x2 s[32]) — r = s p, same steps for every s; r may be p
Lge_scalarmult:
    ENTER 384                             // [96] Q  [224] Q + P  [352] P
    mov  x19, x0
    mov  x20, x2
    add  x0, sp, #352
    mov  x2, #128
    bl   Lmemcpy
    add  x0, sp, #96
    mov  x1, #128
    bl   Lmemzero
    mov  x9, #1
    str  x9, [sp, #128]                   // Q = (0, 1, 1, 0)
    str  x9, [sp, #160]
    mov  x21, #255
1:  F3   Lge_add, sp, 96, sp, 96, sp, 96
    F3   Lge_add, sp, 224, sp, 96, sp, 352
    lsr  x9, x21, #3
    ldrb w10, [x20, x9]
    and  x11, x21, #7
    lsr  w10, w10, w11
    and  x3, x10, #1
    add  x0, sp, #96
    add  x1, sp, #224
    mov  x2, #128
    bl   Lcmov
    subs x21, x21, #1
    b.ge 1b
    mov  x0, x19
    add  x1, sp, #96
    mov  x2, #128
    bl   Lmemcpy
    add  x0, sp, #96
    mov  x1, #256
    bl   Lmemzero
    LEAVE 384

// Lge_encode(x0 out[32], x1 p) — y, with the low bit of x on top
Lge_encode:
    ENTER 96                              // [96] 1/Z  [128] x  [160] y
    mov  x19, x0
    mov  x20, x1
    add  x0, sp, #96
    add  x1, x20, #64
    bl   Lfe_inv
    F3   Lfe_mul, sp, 128, x20, 0, sp, 96
    F3   Lfe_mul, sp, 160, x20, 32, sp, 96
    add  x0, sp, #128
    add  x1, sp, #128
    bl   Lfe_freeze
    mov  x0, x19
    add  x1, sp, #160
    bl   Lfe_freeze
    ldrb w9, [sp, #128]
    and  w9, w9, #1
    ldrb w10, [x19, #31]
    orr  w10, w10, w9, lsl #7
    strb w10, [x19, #31]
    LEAVE 96

// Lge_decode(x0 p, x1 in[32]) -> x0 = 0, or -1 if it isn't a point (RFC 8032 §5.1.3).
// Public data only.
Lge_decode:
    ENTER 256
    // [96] y  [128] u  [160] v  [192] v^3  [224] t  [256] x  [288] check  [320] check 2
    mov  x19, x0
    mov  x20, x1
    add  x0, sp, #96
    mov  x2, #32
    bl   Lmemcpy
    ldrb w21, [sp, #127]
    lsr  w21, w21, #7                     // the sign of x
    ldr  x9, [sp, #120]
    and  x9, x9, #0x7fffffffffffffff
    str  x9, [sp, #120]
    add  x0, sp, #288                     // y must be below p
    add  x1, sp, #96
    bl   Lfe_freeze
    add  x0, sp, #288
    add  x1, sp, #96
    mov  x2, #32
    bl   _bc_memeq
    cbz  x0, Lgd_bad
    F3   Lfe_mul, sp, 128, sp, 96, sp, 96       // u = y^2 - 1, v = d y^2 + 1
    add  x0, sp, #160
    add  x1, sp, #128
    ADRL x2, Lfe_d
    bl   Lfe_mul
    add  x0, sp, #160
    add  x1, sp, #160
    ADRL x2, Lfe_one
    bl   Lfe_add
    add  x0, sp, #128
    add  x1, sp, #128
    ADRL x2, Lfe_one
    bl   Lfe_sub
    F3   Lfe_mul, sp, 192, sp, 160, sp, 160     // v^3
    F3   Lfe_mul, sp, 192, sp, 192, sp, 160
    F3   Lfe_mul, sp, 224, sp, 192, sp, 192     // u v^7
    F3   Lfe_mul, sp, 224, sp, 224, sp, 160
    F3   Lfe_mul, sp, 224, sp, 224, sp, 128
    add  x0, sp, #224                           // (u v^7)^((p-5)/8)
    add  x1, sp, #224
    ADRL x2, Lexp_2523
    bl   Lfe_pow
    F3   Lfe_mul, sp, 256, sp, 224, sp, 192     // x = u v^3 (u v^7)^((p-5)/8)
    F3   Lfe_mul, sp, 256, sp, 256, sp, 128
    F3   Lfe_mul, sp, 288, sp, 256, sp, 256     // v x^2 = u ?
    F3   Lfe_mul, sp, 288, sp, 288, sp, 160
    add  x0, sp, #288
    add  x1, sp, #288
    bl   Lfe_freeze
    add  x0, sp, #320
    add  x1, sp, #128
    bl   Lfe_freeze
    add  x0, sp, #288
    add  x1, sp, #320
    mov  x2, #32
    bl   _bc_memeq
    cbnz x0, Lgd_root
    add  x0, sp, #320                     // v x^2 = -u ? then x = x sqrt(-1)
    ADRL x1, Lfe_zero
    add  x2, sp, #128
    bl   Lfe_sub
    add  x0, sp, #320
    add  x1, sp, #320
    bl   Lfe_freeze
    add  x0, sp, #288
    add  x1, sp, #320
    mov  x2, #32
    bl   _bc_memeq
    cbz  x0, Lgd_bad
    add  x0, sp, #256
    add  x1, sp, #256
    ADRL x2, Lfe_sqrtm1
    bl   Lfe_mul
Lgd_root:
    add  x0, sp, #256
    add  x1, sp, #256
    bl   Lfe_freeze
    add  x0, sp, #256
    bl   Lfe_iszero
    and  x0, x0, x21
    cbnz x0, Lgd_bad                      // x = 0 with the sign bit set
    ldrb w9, [sp, #256]
    and  w9, w9, #1
    cmp  w9, w21
    b.eq 1f
    add  x0, sp, #256
    ADRL x1, Lfe_zero
    add  x2, sp, #256
    bl   Lfe_sub
    add  x0, sp, #256
    add  x1, sp, #256
    bl   Lfe_freeze
1:  mov  x0, x19
    add  x1, sp, #256
    mov  x2, #32
    bl   Lmemcpy
    add  x0, x19, #32
    add  x1, sp, #96
    mov  x2, #32
    bl   Lmemcpy
    mov  x9, #1
    stp  x9, xzr, [x19, #64]
    stp  xzr, xzr, [x19, #80]
    F3   Lfe_mul, x19, 96, sp, 256, sp, 96
    mov  x0, #0
    LEAVE 256
Lgd_bad:
    mov  x0, #-1
    LEAVE 256

// ---------------------------------------------------------------------------
// Scalars mod L = 2^252 + 27742317777372353535851937790883648493

// Lsc_reduce(x0 out[32], x1 in[64]) — one bit at a time, the same steps for every input
Lsc_reduce:
    ADRL x16, Lsc_L
    ldp  x12, x13, [x16]
    ldp  x14, x15, [x16, #16]
    mov  x2, #0
    mov  x3, #0
    mov  x4, #0
    mov  x5, #0
    mov  x6, #511
1:  lsr  x7, x6, #3
    ldrb w7, [x1, x7]
    and  x8, x6, #7
    lsr  w7, w7, w8
    and  x7, x7, #1
    extr x5, x5, x4, #63                  // r = 2r + bit
    extr x4, x4, x3, #63
    extr x3, x3, x2, #63
    orr  x2, x7, x2, lsl #1
    subs x8, x2, x12                      // if r >= L: r -= L
    sbcs x9, x3, x13
    sbcs x10, x4, x14
    sbcs x11, x5, x15
    csel x2, x8, x2, cs
    csel x3, x9, x3, cs
    csel x4, x10, x4, cs
    csel x5, x11, x5, cs
    subs x6, x6, #1
    b.ge 1b
    stp  x2, x3, [x0]
    stp  x4, x5, [x0, #16]
    ret

// Lsc_muladd(x0 out[32], x1 a, x2 b, x3 c) — out = (a b + c) mod L
Lsc_muladd:
    ENTER 64                              // [96] 512-bit sum
    mov  x19, x0
    mov  x20, x3
    add  x0, sp, #96
    bl   Lmul256
    ldp  x3, x4, [sp, #96]
    ldp  x5, x6, [sp, #112]
    ldp  x7, x8, [x20]
    ldp  x9, x10, [x20, #16]
    adds x3, x3, x7
    adcs x4, x4, x8
    adcs x5, x5, x9
    adcs x6, x6, x10
    stp  x3, x4, [sp, #96]
    stp  x5, x6, [sp, #112]
    ldp  x3, x4, [sp, #128]
    ldp  x5, x6, [sp, #144]
    adcs x3, x3, xzr
    adcs x4, x4, xzr
    adcs x5, x5, xzr
    adc  x6, x6, xzr
    stp  x3, x4, [sp, #128]
    stp  x5, x6, [sp, #144]
    mov  x0, x19
    add  x1, sp, #96
    bl   Lsc_reduce
    add  x0, sp, #96
    mov  x1, #64
    bl   Lmemzero
    LEAVE 64

// ---------------------------------------------------------------------------
// Ed25519 (RFC 8032 §5.1)

// Led_secret(x0 seed[32], x1 h[64]) — h = SHA-512(seed), first half clamped into the scalar a
Led_secret:
    ENTER 0
    mov  x19, x1
    mov  x2, x1
    mov  x1, #32
    bl   _bc_sha512
    ldrb w9, [x19]
    and  w9, w9, #248
    strb w9, [x19]
    ldrb w9, [x19, #31]
    and  w9, w9, #127
    orr  w9, w9, #64
    strb w9, [x19, #31]
    LEAVE 0

// void _bc_ed25519_pub(seed[32], pub[32]) — the public key for a 32-byte private seed
.globl _bc_ed25519_pub
_bc_ed25519_pub:
    ENTER 192                             // [96] h  [160] a B
    mov  x20, x1
    add  x1, sp, #96
    bl   Led_secret
    add  x0, sp, #160
    ADRL x1, Lge_base
    add  x2, sp, #96
    bl   Lge_scalarmult
    mov  x0, x20
    add  x1, sp, #160
    bl   Lge_encode
    add  x0, sp, #96
    mov  x1, #64
    bl   Lmemzero
    LEAVE 192

// void _bc_ed25519_sign(seed[32], msg, n, sig[64])
.globl _bc_ed25519_sign
_bc_ed25519_sign:
    ENTER 560
    // [96] h (a, prefix)  [160] A  [192] 64-byte hash  [256] r  [288] k  [320] point  [448] hash context
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    add  x1, sp, #96
    bl   Led_secret
    add  x0, sp, #320                     // A = a B
    ADRL x1, Lge_base
    add  x2, sp, #96
    bl   Lge_scalarmult
    add  x0, sp, #160
    add  x1, sp, #320
    bl   Lge_encode
    add  x0, sp, #448                     // r = SHA-512(prefix || M) mod L
    bl   _bc_sha512_init
    add  x0, sp, #448
    add  x1, sp, #128
    mov  x2, #32
    bl   _bc_sha512_update
    add  x0, sp, #448
    mov  x1, x20
    mov  x2, x21
    bl   _bc_sha512_update
    add  x0, sp, #448
    add  x1, sp, #192
    bl   _bc_sha512_final
    add  x0, sp, #256
    add  x1, sp, #192
    bl   Lsc_reduce
    add  x0, sp, #320                     // R = r B
    ADRL x1, Lge_base
    add  x2, sp, #256
    bl   Lge_scalarmult
    mov  x0, x22
    add  x1, sp, #320
    bl   Lge_encode
    add  x0, sp, #448                     // k = SHA-512(R || A || M) mod L
    bl   _bc_sha512_init
    add  x0, sp, #448
    mov  x1, x22
    mov  x2, #32
    bl   _bc_sha512_update
    add  x0, sp, #448
    add  x1, sp, #160
    mov  x2, #32
    bl   _bc_sha512_update
    add  x0, sp, #448
    mov  x1, x20
    mov  x2, x21
    bl   _bc_sha512_update
    add  x0, sp, #448
    add  x1, sp, #192
    bl   _bc_sha512_final
    add  x0, sp, #288
    add  x1, sp, #192
    bl   Lsc_reduce
    add  x0, x22, #32                     // S = (r + k a) mod L
    add  x1, sp, #288
    add  x2, sp, #96
    add  x3, sp, #256
    bl   Lsc_muladd
    add  x0, sp, #96
    mov  x1, #560
    bl   Lmemzero
    LEAVE 560

// long _bc_ed25519_verify(pub[32], msg, n, sig[64]) -> 1 good, 0 bad
.globl _bc_ed25519_verify
_bc_ed25519_verify:
    ENTER 592
    // [96] -A, then k(-A)  [224] S B  [352] 64-byte hash  [416] k  [448] encoding  [480] hash context
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldp  x3, x4, [x22, #32]               // S must be below L
    ldp  x5, x6, [x22, #48]
    ADRL x9, Lsc_L
    ldp  x10, x11, [x9]
    ldp  x12, x13, [x9, #16]
    subs xzr, x3, x10
    sbcs xzr, x4, x11
    sbcs xzr, x5, x12
    sbcs xzr, x6, x13
    b.hs Lev_bad
    add  x0, sp, #96
    mov  x1, x19
    bl   Lge_decode
    cbnz x0, Lev_bad
    add  x0, sp, #96                      // negate A: -X, -T
    ADRL x1, Lfe_zero
    add  x2, sp, #96
    bl   Lfe_sub
    add  x0, sp, #192
    ADRL x1, Lfe_zero
    add  x2, sp, #192
    bl   Lfe_sub
    add  x0, sp, #480                     // k = SHA-512(R || A || M) mod L
    bl   _bc_sha512_init
    add  x0, sp, #480
    mov  x1, x22
    mov  x2, #32
    bl   _bc_sha512_update
    add  x0, sp, #480
    mov  x1, x19
    mov  x2, #32
    bl   _bc_sha512_update
    add  x0, sp, #480
    mov  x1, x20
    mov  x2, x21
    bl   _bc_sha512_update
    add  x0, sp, #480
    add  x1, sp, #352
    bl   _bc_sha512_final
    add  x0, sp, #416
    add  x1, sp, #352
    bl   Lsc_reduce
    add  x0, sp, #224                     // S B - k A = R ?
    ADRL x1, Lge_base
    add  x2, x22, #32
    bl   Lge_scalarmult
    add  x0, sp, #96
    add  x1, sp, #96
    add  x2, sp, #416
    bl   Lge_scalarmult
    F3   Lge_add, sp, 224, sp, 224, sp, 96
    add  x0, sp, #448
    add  x1, sp, #224
    bl   Lge_encode
    add  x0, sp, #448
    mov  x1, x22
    mov  x2, #32
    bl   _bc_memeq
    LEAVE 592
Lev_bad:
    mov  x0, #0
    LEAVE 592

// ---------------------------------------------------------------------------
// self-tests 127-144 (published test vectors), called from test.s

// x0 = 1 when the n bytes at [sp + off] are the bytes at \expect
.macro BC_SAME off, expect, n
    add  x0, sp, #\off
    ADRL x1, \expect
    mov  x2, #\n
    bl   _bc_memeq
.endm

// report x20 (1 = pass) under \name
.macro BC_REPORT name
    mov  w1, w20
    ADRL x0, \name
    bl   _t_report
    add  x19, x19, x0
.endm

// long _bc_selftest(void) -> number of failures
.globl _bc_selftest
_bc_selftest:
    ENTER 512                             // [96] output  [352] second output
    mov  x19, #0
    // 127. SHA-256
    ADRL x0, Lv_abc
    mov  x1, #3
    add  x2, sp, #96
    bl   _bc_sha256
    BC_SAME 96, Lv_sha256_abc, 32
    mov  x20, x0
    ADRL x0, Lv_448
    mov  x1, #56
    add  x2, sp, #96
    bl   _bc_sha256
    BC_SAME 96, Lv_sha256_448, 32
    and  x20, x20, x0
    BC_REPORT Ln_bc127
    // 128. SHA-512
    ADRL x0, Lv_abc
    mov  x1, #3
    add  x2, sp, #96
    bl   _bc_sha512
    BC_SAME 96, Lv_sha512_abc, 64
    mov  x20, x0
    ADRL x0, Lv_896
    mov  x1, #112
    add  x2, sp, #96
    bl   _bc_sha512
    BC_SAME 96, Lv_sha512_896, 64
    and  x20, x20, x0
    BC_REPORT Ln_bc128
    // 129. HMAC-SHA256, a short key and a key longer than a block
    ADRL x0, Lv_jefe
    mov  x1, #4
    ADRL x2, Lv_jefe_msg
    mov  x3, #28
    add  x4, sp, #96
    bl   _bc_hmac256
    BC_SAME 96, Lv_hmac2, 32
    mov  x20, x0
    ADRL x0, Lv_aa131
    mov  x1, #131
    ADRL x2, Lv_hm6_msg
    mov  x3, #54
    add  x4, sp, #96
    bl   _bc_hmac256
    BC_SAME 96, Lv_hmac6, 32
    and  x20, x20, x0
    BC_REPORT Ln_bc129
    // 130. HKDF-SHA256, with and without salt and info
    ADRL x0, Lv_hk_salt
    mov  x1, #13
    ADRL x2, Lv_hk_ikm
    mov  x3, #22
    ADRL x4, Lv_hk_info
    mov  x5, #10
    add  x6, sp, #96
    mov  x7, #42
    bl   _bc_hkdf256
    cmp  x0, #0
    cset x20, eq
    BC_SAME 96, Lv_hk_okm1, 42
    and  x20, x20, x0
    mov  x0, #0
    mov  x1, #0
    ADRL x2, Lv_hk_ikm
    mov  x3, #22
    mov  x4, #0
    mov  x5, #0
    add  x6, sp, #96
    mov  x7, #42
    bl   _bc_hkdf256
    BC_SAME 96, Lv_hk_okm3, 42
    and  x20, x20, x0
    BC_REPORT Ln_bc130
    // 131. ChaCha20
    ADRL x0, Lv_cc_key
    ADRL x1, Lv_cc_nonce
    mov  w2, #1
    ADRL x3, Lv_sun
    add  x4, sp, #96
    mov  x5, #114
    bl   _bc_chacha20
    BC_SAME 96, Lv_cc_ct, 114
    mov  x20, x0
    BC_REPORT Ln_bc131
    // 132. Poly1305
    ADRL x0, Lv_poly_key
    ADRL x1, Lv_poly_msg
    mov  x2, #34
    add  x3, sp, #96
    bl   _bc_poly1305
    BC_SAME 96, Lv_poly_tag, 16
    mov  x20, x0
    BC_REPORT Ln_bc132
    // 133. ChaCha20-Poly1305 sealing
    ADRL x0, Lv_ae_key
    ADRL x1, Lv_ae_nonce
    ADRL x2, Lv_ae_ad
    mov  x3, #12
    ADRL x4, Lv_sun
    mov  x5, #114
    add  x6, sp, #96
    bl   _bc_aead_seal
    BC_SAME 96, Lv_ae_ct, 130
    mov  x20, x0
    BC_REPORT Ln_bc133
    // 134. ... and opening gives the plaintext back
    ADRL x0, Lv_ae_key
    ADRL x1, Lv_ae_nonce
    ADRL x2, Lv_ae_ad
    mov  x3, #12
    ADRL x4, Lv_ae_ct
    mov  x5, #130
    add  x6, sp, #352
    bl   _bc_aead_open
    cmp  x0, #114
    cset x20, eq
    BC_SAME 352, Lv_sun, 114
    and  x20, x20, x0
    BC_REPORT Ln_bc134
    // 135. one changed bit in the tag, or in the ciphertext, is refused
    ldrb w9, [sp, #225]                   // the sealed copy from 133: last tag byte
    eor  w9, w9, #1
    strb w9, [sp, #225]
    ADRL x0, Lv_ae_key
    ADRL x1, Lv_ae_nonce
    ADRL x2, Lv_ae_ad
    mov  x3, #12
    add  x4, sp, #96
    mov  x5, #130
    add  x6, sp, #352
    bl   _bc_aead_open
    cmn  x0, #1
    cset x20, eq
    ldrb w9, [sp, #225]
    eor  w9, w9, #1
    strb w9, [sp, #225]
    ldrb w9, [sp, #100]
    eor  w9, w9, #0x80
    strb w9, [sp, #100]
    ADRL x0, Lv_ae_key
    ADRL x1, Lv_ae_nonce
    ADRL x2, Lv_ae_ad
    mov  x3, #12
    add  x4, sp, #96
    mov  x5, #130
    add  x6, sp, #352
    bl   _bc_aead_open
    cmn  x0, #1
    cset x9, eq
    and  x20, x20, x9
    BC_REPORT Ln_bc135
    // 136. X25519
    add  x0, sp, #96
    ADRL x1, Lv_x_s1
    ADRL x2, Lv_x_u1
    bl   _bc_x25519
    BC_SAME 96, Lv_x_r1, 32
    mov  x20, x0
    add  x0, sp, #96
    ADRL x1, Lv_x_s2
    ADRL x2, Lv_x_u2
    bl   _bc_x25519
    BC_SAME 96, Lv_x_r2, 32
    and  x20, x20, x0
    BC_REPORT Ln_bc136
    // 137. X25519 key agreement: both sides get the same secret
    add  x0, sp, #96
    ADRL x1, Lv_x_apriv
    bl   _bc_x25519_base
    BC_SAME 96, Lv_x_apub, 32
    mov  x20, x0
    add  x0, sp, #96
    ADRL x1, Lv_x_bpriv
    bl   _bc_x25519_base
    BC_SAME 96, Lv_x_bpub, 32
    and  x20, x20, x0
    add  x0, sp, #96
    ADRL x1, Lv_x_apriv
    ADRL x2, Lv_x_bpub
    bl   _bc_x25519
    BC_SAME 96, Lv_x_shared, 32
    and  x20, x20, x0
    add  x0, sp, #96
    ADRL x1, Lv_x_bpriv
    ADRL x2, Lv_x_apub
    bl   _bc_x25519
    BC_SAME 96, Lv_x_shared, 32
    and  x20, x20, x0
    BC_REPORT Ln_bc137
    // 138. X25519 refuses a low-order point (the all-zero secret)
    stp  xzr, xzr, [sp, #352]
    stp  xzr, xzr, [sp, #368]
    add  x0, sp, #96
    ADRL x1, Lv_x_apriv
    add  x2, sp, #352
    bl   _bc_x25519
    cmn  x0, #1
    cset x20, eq
    BC_REPORT Ln_bc138
    // 139. Ed25519 public keys
    ADRL x0, Lv_ed_seed1
    add  x1, sp, #96
    bl   _bc_ed25519_pub
    BC_SAME 96, Lv_ed_pub1, 32
    mov  x20, x0
    ADRL x0, Lv_ed_seed2
    add  x1, sp, #96
    bl   _bc_ed25519_pub
    BC_SAME 96, Lv_ed_pub2, 32
    and  x20, x20, x0
    ADRL x0, Lv_ed_seed3
    add  x1, sp, #96
    bl   _bc_ed25519_pub
    BC_SAME 96, Lv_ed_pub3, 32
    and  x20, x20, x0
    BC_REPORT Ln_bc139
    // 140. Ed25519 signatures (0, 1 and 2-byte messages)
    ADRL x0, Lv_ed_seed1
    mov  x1, #0
    mov  x2, #0
    add  x3, sp, #96
    bl   _bc_ed25519_sign
    BC_SAME 96, Lv_ed_sig1, 64
    mov  x20, x0
    ADRL x0, Lv_ed_seed2
    ADRL x1, Lv_ed_msg2
    mov  x2, #1
    add  x3, sp, #96
    bl   _bc_ed25519_sign
    BC_SAME 96, Lv_ed_sig2, 64
    and  x20, x20, x0
    ADRL x0, Lv_ed_seed3
    ADRL x1, Lv_ed_msg3
    mov  x2, #2
    add  x3, sp, #96
    bl   _bc_ed25519_sign
    BC_SAME 96, Lv_ed_sig3, 64
    and  x20, x20, x0
    BC_REPORT Ln_bc140
    // 141. ... and they verify
    ADRL x0, Lv_ed_pub1
    mov  x1, #0
    mov  x2, #0
    ADRL x3, Lv_ed_sig1
    bl   _bc_ed25519_verify
    mov  x20, x0
    ADRL x0, Lv_ed_pub2
    ADRL x1, Lv_ed_msg2
    mov  x2, #1
    ADRL x3, Lv_ed_sig2
    bl   _bc_ed25519_verify
    and  x20, x20, x0
    ADRL x0, Lv_ed_pub3
    ADRL x1, Lv_ed_msg3
    mov  x2, #2
    ADRL x3, Lv_ed_sig3
    bl   _bc_ed25519_verify
    and  x20, x20, x0
    BC_REPORT Ln_bc141
    // 142. a signature for another message, or from another key, is refused
    ADRL x0, Lv_ed_pub3
    ADRL x1, Lv_ed_msg2
    mov  x2, #1
    ADRL x3, Lv_ed_sig3
    bl   _bc_ed25519_verify
    mov  x20, x0
    ADRL x0, Lv_ed_pub2
    ADRL x1, Lv_ed_msg3
    mov  x2, #2
    ADRL x3, Lv_ed_sig3
    bl   _bc_ed25519_verify
    orr  x20, x20, x0
    eor  x20, x20, #1
    BC_REPORT Ln_bc142
    // 143. S + L in place of S is refused (no second signature for free)
    ADRL x0, Lv_ed_pub1
    mov  x1, #0
    mov  x2, #0
    ADRL x3, Lv_ed_sig1_sl
    bl   _bc_ed25519_verify
    eor  x20, x0, #1
    BC_REPORT Ln_bc143
    // 144. a public key that isn't a point on the curve is refused
    ADRL x0, Lv_ed_nopoint
    mov  x1, #0
    mov  x2, #0
    ADRL x3, Lv_ed_sig1
    bl   _bc_ed25519_verify
    eor  x20, x0, #1
    BC_REPORT Ln_bc144
    mov  x0, x19
    LEAVE 512

.section __TEXT,__const
Ln_bc127:   .asciz "127 bitchat crypto: SHA-256 gives the FIPS 180 answers"
Ln_bc128:   .asciz "128 bitchat crypto: SHA-512 gives the FIPS 180 answers"
Ln_bc129:   .asciz "129 bitchat crypto: HMAC-SHA256, short key and long key (RFC 4231)"
Ln_bc130:   .asciz "130 bitchat crypto: HKDF-SHA256, with and without salt (RFC 5869)"
Ln_bc131:   .asciz "131 bitchat crypto: ChaCha20 (RFC 8439)"
Ln_bc132:   .asciz "132 bitchat crypto: Poly1305 (RFC 8439)"
Ln_bc133:   .asciz "133 bitchat crypto: ChaCha20-Poly1305 seals (RFC 8439)"
Ln_bc134:   .asciz "134 bitchat crypto: ... and opens to the same plaintext"
Ln_bc135:   .asciz "135 bitchat crypto: a changed tag or ciphertext bit is refused"
Ln_bc136:   .asciz "136 bitchat crypto: X25519 (RFC 7748)"
Ln_bc137:   .asciz "137 bitchat crypto: X25519 keys and shared secret, both sides (RFC 7748)"
Ln_bc138:   .asciz "138 bitchat crypto: X25519 refuses a low-order point"
Ln_bc139:   .asciz "139 bitchat crypto: Ed25519 public keys (RFC 8032)"
Ln_bc140:   .asciz "140 bitchat crypto: Ed25519 signatures (RFC 8032)"
Ln_bc141:   .asciz "141 bitchat crypto: ... and they verify"
Ln_bc142:   .asciz "142 bitchat crypto: a signature for another message or key is refused"
Ln_bc143:   .asciz "143 bitchat crypto: S + L in place of S is refused"
Ln_bc144:   .asciz "144 bitchat crypto: a public key that isn't on the curve is refused"
// FIPS 180-4 examples
Lv_abc:
    .byte 0x61, 0x62, 0x63
Lv_448:
    .byte 0x61, 0x62, 0x63, 0x64, 0x62, 0x63, 0x64, 0x65, 0x63, 0x64, 0x65, 0x66, 0x64, 0x65, 0x66, 0x67
    .byte 0x65, 0x66, 0x67, 0x68, 0x66, 0x67, 0x68, 0x69, 0x67, 0x68, 0x69, 0x6a, 0x68, 0x69, 0x6a, 0x6b
    .byte 0x69, 0x6a, 0x6b, 0x6c, 0x6a, 0x6b, 0x6c, 0x6d, 0x6b, 0x6c, 0x6d, 0x6e, 0x6c, 0x6d, 0x6e, 0x6f
    .byte 0x6d, 0x6e, 0x6f, 0x70, 0x6e, 0x6f, 0x70, 0x71
Lv_896:
    .byte 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69
    .byte 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b
    .byte 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d
    .byte 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f
    .byte 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71
    .byte 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73
    .byte 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75
Lv_sha256_abc:
    .byte 0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea, 0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23
    .byte 0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c, 0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
Lv_sha256_448:
    .byte 0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8, 0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39
    .byte 0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67, 0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1
Lv_sha512_abc:
    .byte 0xdd, 0xaf, 0x35, 0xa1, 0x93, 0x61, 0x7a, 0xba, 0xcc, 0x41, 0x73, 0x49, 0xae, 0x20, 0x41, 0x31
    .byte 0x12, 0xe6, 0xfa, 0x4e, 0x89, 0xa9, 0x7e, 0xa2, 0x0a, 0x9e, 0xee, 0xe6, 0x4b, 0x55, 0xd3, 0x9a
    .byte 0x21, 0x92, 0x99, 0x2a, 0x27, 0x4f, 0xc1, 0xa8, 0x36, 0xba, 0x3c, 0x23, 0xa3, 0xfe, 0xeb, 0xbd
    .byte 0x45, 0x4d, 0x44, 0x23, 0x64, 0x3c, 0xe8, 0x0e, 0x2a, 0x9a, 0xc9, 0x4f, 0xa5, 0x4c, 0xa4, 0x9f
Lv_sha512_896:
    .byte 0x8e, 0x95, 0x9b, 0x75, 0xda, 0xe3, 0x13, 0xda, 0x8c, 0xf4, 0xf7, 0x28, 0x14, 0xfc, 0x14, 0x3f
    .byte 0x8f, 0x77, 0x79, 0xc6, 0xeb, 0x9f, 0x7f, 0xa1, 0x72, 0x99, 0xae, 0xad, 0xb6, 0x88, 0x90, 0x18
    .byte 0x50, 0x1d, 0x28, 0x9e, 0x49, 0x00, 0xf7, 0xe4, 0x33, 0x1b, 0x99, 0xde, 0xc4, 0xb5, 0x43, 0x3a
    .byte 0xc7, 0xd3, 0x29, 0xee, 0xb6, 0xdd, 0x26, 0x54, 0x5e, 0x96, 0xe5, 0x5b, 0x87, 0x4b, 0xe9, 0x09
// RFC 4231 tests 2 and 6
Lv_jefe:
    .byte 0x4a, 0x65, 0x66, 0x65
Lv_jefe_msg:
    .byte 0x77, 0x68, 0x61, 0x74, 0x20, 0x64, 0x6f, 0x20, 0x79, 0x61, 0x20, 0x77, 0x61, 0x6e, 0x74, 0x20
    .byte 0x66, 0x6f, 0x72, 0x20, 0x6e, 0x6f, 0x74, 0x68, 0x69, 0x6e, 0x67, 0x3f
Lv_aa131:
    .byte 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
    .byte 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
    .byte 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
    .byte 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
    .byte 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
    .byte 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
    .byte 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
    .byte 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa
    .byte 0xaa, 0xaa, 0xaa
Lv_hm6_msg:
    .byte 0x54, 0x65, 0x73, 0x74, 0x20, 0x55, 0x73, 0x69, 0x6e, 0x67, 0x20, 0x4c, 0x61, 0x72, 0x67, 0x65
    .byte 0x72, 0x20, 0x54, 0x68, 0x61, 0x6e, 0x20, 0x42, 0x6c, 0x6f, 0x63, 0x6b, 0x2d, 0x53, 0x69, 0x7a
    .byte 0x65, 0x20, 0x4b, 0x65, 0x79, 0x20, 0x2d, 0x20, 0x48, 0x61, 0x73, 0x68, 0x20, 0x4b, 0x65, 0x79
    .byte 0x20, 0x46, 0x69, 0x72, 0x73, 0x74
Lv_hmac2:
    .byte 0x5b, 0xdc, 0xc1, 0x46, 0xbf, 0x60, 0x75, 0x4e, 0x6a, 0x04, 0x24, 0x26, 0x08, 0x95, 0x75, 0xc7
    .byte 0x5a, 0x00, 0x3f, 0x08, 0x9d, 0x27, 0x39, 0x83, 0x9d, 0xec, 0x58, 0xb9, 0x64, 0xec, 0x38, 0x43
Lv_hmac6:
    .byte 0x60, 0xe4, 0x31, 0x59, 0x1e, 0xe0, 0xb6, 0x7f, 0x0d, 0x8a, 0x26, 0xaa, 0xcb, 0xf5, 0xb7, 0x7f
    .byte 0x8e, 0x0b, 0xc6, 0x21, 0x37, 0x28, 0xc5, 0x14, 0x05, 0x46, 0x04, 0x0f, 0x0e, 0xe3, 0x7f, 0x54
// RFC 5869 tests 1 and 3
Lv_hk_ikm:
    .byte 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b
    .byte 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b
Lv_hk_salt:
    .byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c
Lv_hk_info:
    .byte 0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9
Lv_hk_okm1:
    .byte 0x3c, 0xb2, 0x5f, 0x25, 0xfa, 0xac, 0xd5, 0x7a, 0x90, 0x43, 0x4f, 0x64, 0xd0, 0x36, 0x2f, 0x2a
    .byte 0x2d, 0x2d, 0x0a, 0x90, 0xcf, 0x1a, 0x5a, 0x4c, 0x5d, 0xb0, 0x2d, 0x56, 0xec, 0xc4, 0xc5, 0xbf
    .byte 0x34, 0x00, 0x72, 0x08, 0xd5, 0xb8, 0x87, 0x18, 0x58, 0x65
Lv_hk_okm3:
    .byte 0x8d, 0xa4, 0xe7, 0x75, 0xa5, 0x63, 0xc1, 0x8f, 0x71, 0x5f, 0x80, 0x2a, 0x06, 0x3c, 0x5a, 0x31
    .byte 0xb8, 0xa1, 0x1f, 0x5c, 0x5e, 0xe1, 0x87, 0x9e, 0xc3, 0x45, 0x4e, 0x5f, 0x3c, 0x73, 0x8d, 0x2d
    .byte 0x9d, 0x20, 0x13, 0x95, 0xfa, 0xa4, 0xb6, 0x1a, 0x96, 0xc8
// RFC 8439 2.4.2, 2.5.2, 2.8.2
Lv_sun:
    .byte 0x4c, 0x61, 0x64, 0x69, 0x65, 0x73, 0x20, 0x61, 0x6e, 0x64, 0x20, 0x47, 0x65, 0x6e, 0x74, 0x6c
    .byte 0x65, 0x6d, 0x65, 0x6e, 0x20, 0x6f, 0x66, 0x20, 0x74, 0x68, 0x65, 0x20, 0x63, 0x6c, 0x61, 0x73
    .byte 0x73, 0x20, 0x6f, 0x66, 0x20, 0x27, 0x39, 0x39, 0x3a, 0x20, 0x49, 0x66, 0x20, 0x49, 0x20, 0x63
    .byte 0x6f, 0x75, 0x6c, 0x64, 0x20, 0x6f, 0x66, 0x66, 0x65, 0x72, 0x20, 0x79, 0x6f, 0x75, 0x20, 0x6f
    .byte 0x6e, 0x6c, 0x79, 0x20, 0x6f, 0x6e, 0x65, 0x20, 0x74, 0x69, 0x70, 0x20, 0x66, 0x6f, 0x72, 0x20
    .byte 0x74, 0x68, 0x65, 0x20, 0x66, 0x75, 0x74, 0x75, 0x72, 0x65, 0x2c, 0x20, 0x73, 0x75, 0x6e, 0x73
    .byte 0x63, 0x72, 0x65, 0x65, 0x6e, 0x20, 0x77, 0x6f, 0x75, 0x6c, 0x64, 0x20, 0x62, 0x65, 0x20, 0x69
    .byte 0x74, 0x2e
Lv_cc_key:
    .byte 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
    .byte 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f
Lv_cc_nonce:
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4a, 0x00, 0x00, 0x00, 0x00
Lv_cc_ct:
    .byte 0x6e, 0x2e, 0x35, 0x9a, 0x25, 0x68, 0xf9, 0x80, 0x41, 0xba, 0x07, 0x28, 0xdd, 0x0d, 0x69, 0x81
    .byte 0xe9, 0x7e, 0x7a, 0xec, 0x1d, 0x43, 0x60, 0xc2, 0x0a, 0x27, 0xaf, 0xcc, 0xfd, 0x9f, 0xae, 0x0b
    .byte 0xf9, 0x1b, 0x65, 0xc5, 0x52, 0x47, 0x33, 0xab, 0x8f, 0x59, 0x3d, 0xab, 0xcd, 0x62, 0xb3, 0x57
    .byte 0x16, 0x39, 0xd6, 0x24, 0xe6, 0x51, 0x52, 0xab, 0x8f, 0x53, 0x0c, 0x35, 0x9f, 0x08, 0x61, 0xd8
    .byte 0x07, 0xca, 0x0d, 0xbf, 0x50, 0x0d, 0x6a, 0x61, 0x56, 0xa3, 0x8e, 0x08, 0x8a, 0x22, 0xb6, 0x5e
    .byte 0x52, 0xbc, 0x51, 0x4d, 0x16, 0xcc, 0xf8, 0x06, 0x81, 0x8c, 0xe9, 0x1a, 0xb7, 0x79, 0x37, 0x36
    .byte 0x5a, 0xf9, 0x0b, 0xbf, 0x74, 0xa3, 0x5b, 0xe6, 0xb4, 0x0b, 0x8e, 0xed, 0xf2, 0x78, 0x5e, 0x42
    .byte 0x87, 0x4d
Lv_poly_key:
    .byte 0x85, 0xd6, 0xbe, 0x78, 0x57, 0x55, 0x6d, 0x33, 0x7f, 0x44, 0x52, 0xfe, 0x42, 0xd5, 0x06, 0xa8
    .byte 0x01, 0x03, 0x80, 0x8a, 0xfb, 0x0d, 0xb2, 0xfd, 0x4a, 0xbf, 0xf6, 0xaf, 0x41, 0x49, 0xf5, 0x1b
Lv_poly_msg:
    .byte 0x43, 0x72, 0x79, 0x70, 0x74, 0x6f, 0x67, 0x72, 0x61, 0x70, 0x68, 0x69, 0x63, 0x20, 0x46, 0x6f
    .byte 0x72, 0x75, 0x6d, 0x20, 0x52, 0x65, 0x73, 0x65, 0x61, 0x72, 0x63, 0x68, 0x20, 0x47, 0x72, 0x6f
    .byte 0x75, 0x70
Lv_poly_tag:
    .byte 0xa8, 0x06, 0x1d, 0xc1, 0x30, 0x51, 0x36, 0xc6, 0xc2, 0x2b, 0x8b, 0xaf, 0x0c, 0x01, 0x27, 0xa9
Lv_ae_key:
    .byte 0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f
    .byte 0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f
Lv_ae_nonce:
    .byte 0x07, 0x00, 0x00, 0x00, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47
Lv_ae_ad:
    .byte 0x50, 0x51, 0x52, 0x53, 0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7
Lv_ae_ct:
    .byte 0xd3, 0x1a, 0x8d, 0x34, 0x64, 0x8e, 0x60, 0xdb, 0x7b, 0x86, 0xaf, 0xbc, 0x53, 0xef, 0x7e, 0xc2
    .byte 0xa4, 0xad, 0xed, 0x51, 0x29, 0x6e, 0x08, 0xfe, 0xa9, 0xe2, 0xb5, 0xa7, 0x36, 0xee, 0x62, 0xd6
    .byte 0x3d, 0xbe, 0xa4, 0x5e, 0x8c, 0xa9, 0x67, 0x12, 0x82, 0xfa, 0xfb, 0x69, 0xda, 0x92, 0x72, 0x8b
    .byte 0x1a, 0x71, 0xde, 0x0a, 0x9e, 0x06, 0x0b, 0x29, 0x05, 0xd6, 0xa5, 0xb6, 0x7e, 0xcd, 0x3b, 0x36
    .byte 0x92, 0xdd, 0xbd, 0x7f, 0x2d, 0x77, 0x8b, 0x8c, 0x98, 0x03, 0xae, 0xe3, 0x28, 0x09, 0x1b, 0x58
    .byte 0xfa, 0xb3, 0x24, 0xe4, 0xfa, 0xd6, 0x75, 0x94, 0x55, 0x85, 0x80, 0x8b, 0x48, 0x31, 0xd7, 0xbc
    .byte 0x3f, 0xf4, 0xde, 0xf0, 0x8e, 0x4b, 0x7a, 0x9d, 0xe5, 0x76, 0xd2, 0x65, 0x86, 0xce, 0xc6, 0x4b
    .byte 0x61, 0x16, 0x1a, 0xe1, 0x0b, 0x59, 0x4f, 0x09, 0xe2, 0x6a, 0x7e, 0x90, 0x2e, 0xcb, 0xd0, 0x60
    .byte 0x06, 0x91
// RFC 7748 5.2 and 6.1
Lv_x_s1:
    .byte 0xa5, 0x46, 0xe3, 0x6b, 0xf0, 0x52, 0x7c, 0x9d, 0x3b, 0x16, 0x15, 0x4b, 0x82, 0x46, 0x5e, 0xdd
    .byte 0x62, 0x14, 0x4c, 0x0a, 0xc1, 0xfc, 0x5a, 0x18, 0x50, 0x6a, 0x22, 0x44, 0xba, 0x44, 0x9a, 0xc4
Lv_x_u1:
    .byte 0xe6, 0xdb, 0x68, 0x67, 0x58, 0x30, 0x30, 0xdb, 0x35, 0x94, 0xc1, 0xa4, 0x24, 0xb1, 0x5f, 0x7c
    .byte 0x72, 0x66, 0x24, 0xec, 0x26, 0xb3, 0x35, 0x3b, 0x10, 0xa9, 0x03, 0xa6, 0xd0, 0xab, 0x1c, 0x4c
Lv_x_r1:
    .byte 0xc3, 0xda, 0x55, 0x37, 0x9d, 0xe9, 0xc6, 0x90, 0x8e, 0x94, 0xea, 0x4d, 0xf2, 0x8d, 0x08, 0x4f
    .byte 0x32, 0xec, 0xcf, 0x03, 0x49, 0x1c, 0x71, 0xf7, 0x54, 0xb4, 0x07, 0x55, 0x77, 0xa2, 0x85, 0x52
Lv_x_s2:
    .byte 0x4b, 0x66, 0xe9, 0xd4, 0xd1, 0xb4, 0x67, 0x3c, 0x5a, 0xd2, 0x26, 0x91, 0x95, 0x7d, 0x6a, 0xf5
    .byte 0xc1, 0x1b, 0x64, 0x21, 0xe0, 0xea, 0x01, 0xd4, 0x2c, 0xa4, 0x16, 0x9e, 0x79, 0x18, 0xba, 0x0d
Lv_x_u2:
    .byte 0xe5, 0x21, 0x0f, 0x12, 0x78, 0x68, 0x11, 0xd3, 0xf4, 0xb7, 0x95, 0x9d, 0x05, 0x38, 0xae, 0x2c
    .byte 0x31, 0xdb, 0xe7, 0x10, 0x6f, 0xc0, 0x3c, 0x3e, 0xfc, 0x4c, 0xd5, 0x49, 0xc7, 0x15, 0xa4, 0x93
Lv_x_r2:
    .byte 0x95, 0xcb, 0xde, 0x94, 0x76, 0xe8, 0x90, 0x7d, 0x7a, 0xad, 0xe4, 0x5c, 0xb4, 0xb8, 0x73, 0xf8
    .byte 0x8b, 0x59, 0x5a, 0x68, 0x79, 0x9f, 0xa1, 0x52, 0xe6, 0xf8, 0xf7, 0x64, 0x7a, 0xac, 0x79, 0x57
Lv_x_apriv:
    .byte 0x77, 0x07, 0x6d, 0x0a, 0x73, 0x18, 0xa5, 0x7d, 0x3c, 0x16, 0xc1, 0x72, 0x51, 0xb2, 0x66, 0x45
    .byte 0xdf, 0x4c, 0x2f, 0x87, 0xeb, 0xc0, 0x99, 0x2a, 0xb1, 0x77, 0xfb, 0xa5, 0x1d, 0xb9, 0x2c, 0x2a
Lv_x_apub:
    .byte 0x85, 0x20, 0xf0, 0x09, 0x89, 0x30, 0xa7, 0x54, 0x74, 0x8b, 0x7d, 0xdc, 0xb4, 0x3e, 0xf7, 0x5a
    .byte 0x0d, 0xbf, 0x3a, 0x0d, 0x26, 0x38, 0x1a, 0xf4, 0xeb, 0xa4, 0xa9, 0x8e, 0xaa, 0x9b, 0x4e, 0x6a
Lv_x_bpriv:
    .byte 0x5d, 0xab, 0x08, 0x7e, 0x62, 0x4a, 0x8a, 0x4b, 0x79, 0xe1, 0x7f, 0x8b, 0x83, 0x80, 0x0e, 0xe6
    .byte 0x6f, 0x3b, 0xb1, 0x29, 0x26, 0x18, 0xb6, 0xfd, 0x1c, 0x2f, 0x8b, 0x27, 0xff, 0x88, 0xe0, 0xeb
Lv_x_bpub:
    .byte 0xde, 0x9e, 0xdb, 0x7d, 0x7b, 0x7d, 0xc1, 0xb4, 0xd3, 0x5b, 0x61, 0xc2, 0xec, 0xe4, 0x35, 0x37
    .byte 0x3f, 0x83, 0x43, 0xc8, 0x5b, 0x78, 0x67, 0x4d, 0xad, 0xfc, 0x7e, 0x14, 0x6f, 0x88, 0x2b, 0x4f
Lv_x_shared:
    .byte 0x4a, 0x5d, 0x9d, 0x5b, 0xa4, 0xce, 0x2d, 0xe1, 0x72, 0x8e, 0x3b, 0xf4, 0x80, 0x35, 0x0f, 0x25
    .byte 0xe0, 0x7e, 0x21, 0xc9, 0x47, 0xd1, 0x9e, 0x33, 0x76, 0xf0, 0x9b, 0x3c, 0x1e, 0x16, 0x17, 0x42
// RFC 8032 7.1 tests 1-3
Lv_ed_seed1:
    .byte 0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60, 0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4
    .byte 0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19, 0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60
Lv_ed_pub1:
    .byte 0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a
    .byte 0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25, 0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a
Lv_ed_sig1:
    .byte 0xe5, 0x56, 0x43, 0x00, 0xc3, 0x60, 0xac, 0x72, 0x90, 0x86, 0xe2, 0xcc, 0x80, 0x6e, 0x82, 0x8a
    .byte 0x84, 0x87, 0x7f, 0x1e, 0xb8, 0xe5, 0xd9, 0x74, 0xd8, 0x73, 0xe0, 0x65, 0x22, 0x49, 0x01, 0x55
    .byte 0x5f, 0xb8, 0x82, 0x15, 0x90, 0xa3, 0x3b, 0xac, 0xc6, 0x1e, 0x39, 0x70, 0x1c, 0xf9, 0xb4, 0x6b
    .byte 0xd2, 0x5b, 0xf5, 0xf0, 0x59, 0x5b, 0xbe, 0x24, 0x65, 0x51, 0x41, 0x43, 0x8e, 0x7a, 0x10, 0x0b
// test 1 with S + L in place of S
Lv_ed_sig1_sl:
    .byte 0xe5, 0x56, 0x43, 0x00, 0xc3, 0x60, 0xac, 0x72, 0x90, 0x86, 0xe2, 0xcc, 0x80, 0x6e, 0x82, 0x8a
    .byte 0x84, 0x87, 0x7f, 0x1e, 0xb8, 0xe5, 0xd9, 0x74, 0xd8, 0x73, 0xe0, 0x65, 0x22, 0x49, 0x01, 0x55
    .byte 0x4c, 0x8c, 0x78, 0x72, 0xaa, 0x06, 0x4e, 0x04, 0x9d, 0xbb, 0x30, 0x13, 0xfb, 0xf2, 0x93, 0x80
    .byte 0xd2, 0x5b, 0xf5, 0xf0, 0x59, 0x5b, 0xbe, 0x24, 0x65, 0x51, 0x41, 0x43, 0x8e, 0x7a, 0x10, 0x1b
Lv_ed_seed2:
    .byte 0x4c, 0xcd, 0x08, 0x9b, 0x28, 0xff, 0x96, 0xda, 0x9d, 0xb6, 0xc3, 0x46, 0xec, 0x11, 0x4e, 0x0f
    .byte 0x5b, 0x8a, 0x31, 0x9f, 0x35, 0xab, 0xa6, 0x24, 0xda, 0x8c, 0xf6, 0xed, 0x4f, 0xb8, 0xa6, 0xfb
Lv_ed_pub2:
    .byte 0x3d, 0x40, 0x17, 0xc3, 0xe8, 0x43, 0x89, 0x5a, 0x92, 0xb7, 0x0a, 0xa7, 0x4d, 0x1b, 0x7e, 0xbc
    .byte 0x9c, 0x98, 0x2c, 0xcf, 0x2e, 0xc4, 0x96, 0x8c, 0xc0, 0xcd, 0x55, 0xf1, 0x2a, 0xf4, 0x66, 0x0c
Lv_ed_sig2:
    .byte 0x92, 0xa0, 0x09, 0xa9, 0xf0, 0xd4, 0xca, 0xb8, 0x72, 0x0e, 0x82, 0x0b, 0x5f, 0x64, 0x25, 0x40
    .byte 0xa2, 0xb2, 0x7b, 0x54, 0x16, 0x50, 0x3f, 0x8f, 0xb3, 0x76, 0x22, 0x23, 0xeb, 0xdb, 0x69, 0xda
    .byte 0x08, 0x5a, 0xc1, 0xe4, 0x3e, 0x15, 0x99, 0x6e, 0x45, 0x8f, 0x36, 0x13, 0xd0, 0xf1, 0x1d, 0x8c
    .byte 0x38, 0x7b, 0x2e, 0xae, 0xb4, 0x30, 0x2a, 0xee, 0xb0, 0x0d, 0x29, 0x16, 0x12, 0xbb, 0x0c, 0x00
Lv_ed_msg2:
    .byte 0x72
Lv_ed_seed3:
    .byte 0xc5, 0xaa, 0x8d, 0xf4, 0x3f, 0x9f, 0x83, 0x7b, 0xed, 0xb7, 0x44, 0x2f, 0x31, 0xdc, 0xb7, 0xb1
    .byte 0x66, 0xd3, 0x85, 0x35, 0x07, 0x6f, 0x09, 0x4b, 0x85, 0xce, 0x3a, 0x2e, 0x0b, 0x44, 0x58, 0xf7
Lv_ed_pub3:
    .byte 0xfc, 0x51, 0xcd, 0x8e, 0x62, 0x18, 0xa1, 0xa3, 0x8d, 0xa4, 0x7e, 0xd0, 0x02, 0x30, 0xf0, 0x58
    .byte 0x08, 0x16, 0xed, 0x13, 0xba, 0x33, 0x03, 0xac, 0x5d, 0xeb, 0x91, 0x15, 0x48, 0x90, 0x80, 0x25
Lv_ed_sig3:
    .byte 0x62, 0x91, 0xd6, 0x57, 0xde, 0xec, 0x24, 0x02, 0x48, 0x27, 0xe6, 0x9c, 0x3a, 0xbe, 0x01, 0xa3
    .byte 0x0c, 0xe5, 0x48, 0xa2, 0x84, 0x74, 0x3a, 0x44, 0x5e, 0x36, 0x80, 0xd7, 0xdb, 0x5a, 0xc3, 0xac
    .byte 0x18, 0xff, 0x9b, 0x53, 0x8d, 0x16, 0xf2, 0x90, 0xae, 0x67, 0xf7, 0x60, 0x98, 0x4d, 0xc6, 0x59
    .byte 0x4a, 0x7c, 0x15, 0xe9, 0x71, 0x6e, 0xd2, 0x8d, 0xc0, 0x27, 0xbe, 0xce, 0xea, 0x1e, 0xc4, 0x0a
Lv_ed_msg3:
    .byte 0xaf, 0x82
// y = 2: no x on the curve
Lv_ed_nopoint:
    .byte 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    .byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

