// asmfm — util.S : printing, numbers, time, small string helpers
.include "fm_defs.inc"
    .text

// fm_utoa(x0 = value, x1 = dest) -> x0 = length (no terminator written... it is)
    .globl _fm_utoa
    .p2align 2
_fm_utoa:
    sub sp, sp, #32
    mov x2, sp
    mov x3, #0
    mov x5, #10
1:  udiv x4, x0, x5
    msub x6, x4, x5, x0
    add w6, w6, #'0'
    strb w6, [x2, x3]
    add x3, x3, #1
    mov x0, x4
    cbnz x0, 1b
    mov x0, x3
2:  sub x3, x3, #1
    ldrb w6, [x2, x3]
    strb w6, [x1], #1
    cbnz x3, 2b
    strb wzr, [x1]
    add sp, sp, #32
    ret

// fm_now_ms() -> x0 monotonic milliseconds
    .globl _fm_now_ms
    .p2align 2
_fm_now_ms:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mov w0, #CLOCK_MONO
    add x1, sp, #16
    bl _clock_gettime
    ldr x0, [sp, #16]
    ldr x1, [sp, #24]
    mov x2, #1000
    mul x0, x0, x2
    mov x2, #16960
    movk x2, #15, lsl #16          // 1_000_000
    udiv x1, x1, x2
    add x0, x0, x1
    ldp x29, x30, [sp], #32
    ret

// fm_now_us() -> x0 monotonic microseconds
    .globl _fm_now_us
    .p2align 2
_fm_now_us:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mov w0, #CLOCK_MONO
    add x1, sp, #16
    bl _clock_gettime
    ldr x0, [sp, #16]
    ldr x1, [sp, #24]
    mov x2, #16960
    movk x2, #15, lsl #16          // 1_000_000
    mul x0, x0, x2
    mov x2, #1000
    udiv x1, x1, x2
    add x0, x0, x1
    ldp x29, x30, [sp], #32
    ret

// fm_sleep_us(x0 = microseconds)
    .globl _fm_sleep_us
    .p2align 2
_fm_sleep_us:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    mov x2, #16960
    movk x2, #15, lsl #16
    udiv x3, x0, x2
    msub x4, x3, x2, x0
    mov x5, #1000
    mul x4, x4, x5
    stp x3, x4, [sp, #16]
    add x0, sp, #16
    mov x1, #0
    bl _nanosleep
    ldp x29, x30, [sp], #32
    ret

// fm_rand() -> w0 (xorshift32)
    .globl _fm_rand
    .p2align 2
_fm_rand:
    LA x1, rng_state
    ldr w0, [x1]
    eor w0, w0, w0, lsl #13
    eor w0, w0, w0, lsr #17
    eor w0, w0, w0, lsl #5
    str w0, [x1]
    ret

// fm_seed(w0)
    .globl _fm_seed
    .p2align 2
_fm_seed:
    cmp w0, #0
    mov w1, #0x2545
    csel w0, w1, w0, eq
    LA x1, rng_state
    str w0, [x1]
    ret

// fm_lower(w0) -> ascii lower-case
    .globl _fm_lower
    .p2align 2
_fm_lower:
    sub w1, w0, #'A'
    cmp w1, #25
    b.hi 1f
    add w0, w0, #32
1:  ret

// fm_istarts(x0 = s, x1 = prefix) -> w0 = 1 if s starts with prefix (ignore case)
    .globl _fm_istarts
    .p2align 2
_fm_istarts:
1:  ldrb w3, [x1], #1
    cbz w3, 3f
    ldrb w2, [x0], #1
    sub w4, w2, #'A'
    cmp w4, #25
    b.hi 2f
    add w2, w2, #32
2:  sub w4, w3, #'A'
    cmp w4, #25
    b.hi 4f
    add w3, w3, #32
4:  cmp w2, w3
    b.eq 1b
    mov w0, #0
    ret
3:  mov w0, #1
    ret

// fm_streq(x0, x1) -> w0 = 1 if equal
    .globl _fm_streq
    .p2align 2
_fm_streq:
1:  ldrb w2, [x0], #1
    ldrb w3, [x1], #1
    cmp w2, w3
    b.ne 2f
    cbnz w2, 1b
    mov w0, #1
    ret
2:  mov w0, #0
    ret

// fm_strlcpy(x0 = dst, x1 = src, x2 = cap) -> x0 = copied length
    .globl _fm_strlcpy
    .p2align 2
_fm_strlcpy:
    mov x3, #0
    cbz x2, 2f
    sub x2, x2, #1
1:  cmp x3, x2
    b.ge 2f
    ldrb w4, [x1, x3]
    cbz w4, 2f
    strb w4, [x0, x3]
    add x3, x3, #1
    b 1b
2:  strb wzr, [x0, x3]
    mov x0, x3
    ret

// fm_strlcat(x0 = dst, x1 = src, x2 = cap) -> x0 = total length
    .globl _fm_strlcat
    .p2align 2
_fm_strlcat:
    mov x3, #0
1:  ldrb w4, [x0, x3]
    cbz w4, 2f
    add x3, x3, #1
    b 1b
2:  add x2, x2, #0
    sub x5, x2, #1
3:  cmp x3, x5
    b.ge 4f
    ldrb w4, [x1], #1
    cbz w4, 4f
    strb w4, [x0, x3]
    add x3, x3, #1
    b 3b
4:  strb wzr, [x0, x3]
    mov x0, x3
    ret

    .data
    .p2align 2
rng_state: .word 0x12345678

