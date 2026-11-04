// dbl_core.s — the developer blocklist, pure (no globals, no system calls): a list of
// banned ids signed with the developer's Ed25519 key (tools/blocklist/blocklist.py). Only a
// list whose signature checks out with the public key built into the app is taken, and only
// if it is newer than the one held (safety.s). Self-test 218.
//   "ASMBL1" 0 0 | version u32 | count u32 | ids u64[count], ascending | signature[64]
.include "macros.inc"

.set DBL_MAX,       4096

.text
.p2align 2

// long _dbl_verify(const uint8 *data, long len, const uint8 pub[32]) -> x0 how many ids, x1
//   its version; or x0 -1: not a list, a bad length, ids out of order, or a bad signature.
//   A key of all zeros (none set up yet) takes nothing.
.globl _dbl_verify
_dbl_verify:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ldp  x9, x10, [x21]                   // no key yet
    ldp  x11, x12, [x21, #16]
    orr  x9, x9, x10
    orr  x11, x11, x12
    orr  x9, x9, x11
    cbz  x9, 8f
    cmp  x20, #80
    b.lo 8f
    ldr  x9, [x19]
    ADRL x10, Ldbl_magic
    ldr  x10, [x10]
    cmp  x9, x10
    b.ne 8f
    ldr  w22, [x19, #12]                  // count
    cmp  x22, #DBL_MAX
    b.hi 8f
    lsl  x9, x22, #3
    add  x9, x9, #80
    cmp  x20, x9
    b.ne 8f
    mov  x9, #1                           // ascending, no repeats
1:  cmp  x9, x22
    b.hs 2f
    add  x10, x19, #16
    sub  x11, x9, #1
    ldr  x12, [x10, x11, lsl #3]
    ldr  x13, [x10, x9, lsl #3]
    cmp  x13, x12
    b.ls 8f
    add  x9, x9, #1
    b    1b
2:  mov  x0, x21                          // the signature, over everything before it
    mov  x1, x19
    sub  x2, x20, #64
    add  x3, x19, x2
    bl   _bc_ed25519_verify
    cbz  x0, 8f
    mov  x0, x22
    ldr  w1, [x19, #8]
    LEAVE 0
8:  mov  x0, #-1
    mov  x1, #0
    LEAVE 0

// long _dbl_has(const uint8 *data, long count, uint64 id) -> 1 if the (verified) list has
//   it (leaf; binary search)
.globl _dbl_has
_dbl_has:
    cbz  x1, 8f
    add  x9, x0, #16
    mov  x10, #0                          // lo
    mov  x11, x1                          // hi (past)
1:  cmp  x10, x11
    b.hs 8f
    add  x12, x10, x11
    lsr  x12, x12, #1
    ldr  x13, [x9, x12, lsl #3]
    cmp  x13, x2
    b.eq 9f
    b.hi 2f
    add  x10, x12, #1
    b    1b
2:  mov  x11, x12
    b    1b
8:  mov  x0, #0
    ret
9:  mov  x0, #1
    ret

// ---------------------------------------------------------------------------
// self-test 218, called from test.s: a list signed with a test key (not the developer's)

.globl _dbl_core_selftest
_dbl_core_selftest:
    ENTER 128                             // [96] a copy, to spoil (104)
    mov  x19, #0
    mov  x20, #1
    ADRL x0, Ldt_list                     // good: 3 ids, version 7
    mov  x1, #104
    ADRL x2, Ldt_pub
    bl   _dbl_verify
    cmp  x0, #3
    cset x9, eq
    and  x20, x20, x9
    cmp  x1, #7
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Ldt_list
    mov  x1, #3
    mov  x2, #0xA1
    bl   _dbl_has
    and  x20, x20, x0
    ADRL x0, Ldt_list
    mov  x1, #3
    ADRL x9, Ldt_id
    ldr  x2, [x9]
    bl   _dbl_has
    and  x20, x20, x0
    ADRL x0, Ldt_list                     // not on it
    mov  x1, #3
    mov  x2, #0xA2
    bl   _dbl_has
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Ldt_list                     // cut short
    mov  x1, #103
    ADRL x2, Ldt_pub
    bl   _dbl_verify
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #96                      // one id changed: the signature fails
    ADRL x1, Ldt_list
    mov  x2, #104
    bl   _memcpy
    ldrb w9, [sp, #(96 + 16)]
    eor  w9, w9, #1
    strb w9, [sp, #(96 + 16)]
    add  x0, sp, #96
    mov  x1, #104
    ADRL x2, Ldt_pub
    bl   _dbl_verify
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Ldt_list                     // another key: refused
    mov  x1, #104
    ADRL x2, Ldt_list
    bl   _dbl_verify
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Ldt_list                     // no key set up (all zeros): refused
    mov  x1, #104
    ADRL x2, Ldt_zero
    bl   _dbl_verify
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_dbl218
    bl   _t_report
    add  x19, x19, x0
    mov  x0, x19
    LEAVE 128

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Ldbl_magic:     .ascii "ASMBL1"
                .byte 0, 0
Ldt_id:         .quad 0xFFFF000011112222
Ldt_zero:       .space 32
Ldt_pub:
    .byte 0x03, 0xa1, 0x07, 0xbf, 0xf3, 0xce, 0x10, 0xbe, 0x1d, 0x70, 0xdd, 0x18, 0xe7, 0x4b, 0xc0, 0x99
    .byte 0x67, 0xe4, 0xd6, 0x30, 0x9b, 0xa5, 0x0d, 0x5f, 0x1d, 0xdc, 0x86, 0x64, 0x12, 0x55, 0x31, 0xb8
.p2align 3
Ldt_list:
    .byte 0x41, 0x53, 0x4d, 0x42, 0x4c, 0x31, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00
    .byte 0xa1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11
    .byte 0x22, 0x22, 0x11, 0x11, 0x00, 0x00, 0xff, 0xff, 0x6c, 0x86, 0xd1, 0x19, 0x8e, 0xba, 0x81, 0x1a
    .byte 0x35, 0x98, 0x2d, 0x6e, 0x3d, 0xe6, 0xff, 0x95, 0x6e, 0x5d, 0xd5, 0xf8, 0x4a, 0x6f, 0xf8, 0xfa
    .byte 0x95, 0x2e, 0x35, 0x71, 0xc0, 0xa9, 0xbd, 0x50, 0xcf, 0xf0, 0x67, 0x2b, 0x01, 0x6f, 0xc0, 0xec
    .byte 0x34, 0x1e, 0xe7, 0x95, 0x89, 0x13, 0xd1, 0x87, 0x43, 0xd0, 0x8e, 0x68, 0x45, 0x87, 0xfb, 0x32
    .byte 0x65, 0x12, 0x7a, 0xf2, 0x3f, 0x87, 0x47, 0x09

.section __TEXT,__cstring,cstring_literals
Ln_dbl218:      .asciz "218 developer blocklist: a signed list taken; changed, cut, other or no key refused"
