// dbl_core.s — the developer blocklist, pure (no globals, no system calls): a list of
// banned ids signed with the developer's Ed25519 key (tools/blocklist/blocklist.py). Only a
// list whose signature checks out with the public key built into the app is taken, and only
// if it is newer than the one held (safety.s). Self-test 218.
//   "ASMBL1" 0 0 | version u32 | count u32 | ids u64[count], ascending | signature[64]
.include "macros.inc"

.set DBL_MAX,       4096
.set DBL_CHUNK,     128          // shared over the mesh in pieces of 128 bytes,
.set DBL_GOSSIP,    8192         //   lists up to 8 KB (1,014 ids); bigger ones: updates, the web
.set DA_VER,        0            // a list being put together (_dbl_piece_in)
.set DA_TOTAL,      8
.set DA_HAVE,       16           // a bit for each piece we have
.set DA_FROM,       24           // who it's coming from: one sender at a time
.set DA_AT,         32           // when their last piece came
.set DA_BUF,        40
.set DA_SIZE,       (40 + 8192)

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

// long _dbl_piece(const uint8 *list, long len, long i, uint8 *out) -> the bytes of piece i
//   (128 a piece, the last one shorter) copied to out, or 0 past the end (leaf)
.globl _dbl_piece
_dbl_piece:
    lsl  x9, x2, #7
    cmp  x9, x1
    b.hs 8f
    sub  x10, x1, x9
    mov  x11, #DBL_CHUNK
    cmp  x10, x11
    csel x10, x11, x10, hi
    add  x12, x0, x9
    mov  x13, #0
1:  cmp  x13, x10
    b.hs 2f
    ldrb w14, [x12, x13]
    strb w14, [x3, x13]
    add  x13, x13, #1
    b    1b
2:  mov  x0, x10
    ret
8:  mov  x0, #0
    ret

// long _dbl_piece_in(da *a, uint64 from, long version, long total, long offset,
//   const uint8 *data, long n, long now) -> 1 the whole list is in a->buf (check it with
//   _dbl_verify), 0 more to come, -1 refused: a bad size or place, or another sender's
//   pieces while one is coming (until 20 s without a piece from them)
.globl _dbl_piece_in
_dbl_piece_in:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    mov  x24, x5
    str  x6, [sp, #96]
    str  x7, [sp, #104]
    cmp  x22, #80                         // a list's size: 80 bytes to 8 KB
    b.lo 8f
    mov  x9, #DBL_GOSSIP
    cmp  x22, x9
    b.hi 8f
    tst  x23, #(DBL_CHUNK - 1)            // a piece's place and size
    b.ne 8f
    cmp  x23, x22
    b.hs 8f
    sub  x9, x22, x23
    mov  x10, #DBL_CHUNK
    cmp  x9, x10
    csel x9, x10, x9, hi
    ldr  x10, [sp, #96]
    cmp  x10, x9
    b.ne 8f
    ldr  x9, [x19, #DA_VER]               // the list we're putting together?
    cmp  x9, x21
    b.ne 1f
    ldr  x9, [x19, #DA_TOTAL]
    cmp  x9, x22
    b.ne 1f
    ldr  x9, [x19, #DA_FROM]
    cmp  x9, x20
    b.eq 3f
1:  ldr  x9, [x19, #DA_VER]               // another: only if nothing's coming now
    cbz  x9, 2f
    ldr  x9, [x19, #DA_FROM]
    cmp  x9, x20
    b.eq 2f
    ldr  x9, [sp, #104]
    ldr  x10, [x19, #DA_AT]
    sub  x9, x9, x10
    cmp  x9, #20
    b.lo 8f
2:  str  x21, [x19, #DA_VER]
    str  x22, [x19, #DA_TOTAL]
    str  x20, [x19, #DA_FROM]
    str  xzr, [x19, #DA_HAVE]
3:  add  x0, x19, #DA_BUF
    add  x0, x0, x23
    mov  x1, x24
    ldr  x2, [sp, #96]
    bl   _memcpy
    ldr  x9, [sp, #104]
    str  x9, [x19, #DA_AT]
    lsr  x10, x23, #7                     // this piece's bit
    mov  x11, #1
    lsl  x11, x11, x10
    ldr  x12, [x19, #DA_HAVE]
    orr  x12, x12, x11
    str  x12, [x19, #DA_HAVE]
    add  x13, x22, #(DBL_CHUNK - 1)       // all of them?
    lsr  x13, x13, #7
    mov  x14, #-1
    cmp  x13, #64
    b.eq 4f
    mov  x14, #1
    lsl  x14, x14, x13
    sub  x14, x14, #1
4:  cmp  x12, x14
    cset x0, eq
    LEAVE 16
8:  mov  x0, #-1
    LEAVE 16

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

    // 219. pieces over the mesh: the list in its pieces, last first, comes out whole and
    //      checks out; a stranger's piece meanwhile, a bad place and a bad size are refused
    mov  x20, #1
    mov  x0, #1
    mov  x1, #DA_SIZE
    bl   _calloc
    mov  x21, x0
    cbz  x21, 9f
    mov  x0, x21                          // the one piece of a 104-byte list, 100 bytes: refused
    mov  x1, #0xB0
    mov  x2, #7
    mov  x3, #104
    mov  x4, #0
    ADRL x5, Ldt_list
    mov  x6, #100
    mov  x7, #1000
    bl   _dbl_piece_in
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    mov  x0, x21                          // a place inside a piece: refused
    mov  x1, #0xB0
    mov  x2, #7
    mov  x3, #200
    mov  x4, #64
    ADRL x5, Ldt_list
    mov  x6, #64
    mov  x7, #1000
    bl   _dbl_piece_in
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    // a 200-byte "list": the real 104 bytes and padding, in two pieces, the last first
    add  x0, sp, #96
    mov  x9, #0
1:  strb wzr, [x0, x9]
    add  x9, x9, #1
    cmp  x9, #32
    b.lo 1b
    mov  x0, x21                          // piece 1 (72 bytes at 128), from 0xB0
    mov  x1, #0xB0
    mov  x2, #7
    mov  x3, #200
    mov  x4, #128
    ADRL x5, Ldt_list
    mov  x6, #72
    mov  x7, #1000
    bl   _dbl_piece_in
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    mov  x0, x21                          // a stranger's piece 0 while 0xB0's are coming
    mov  x1, #0xC3
    mov  x2, #7
    mov  x3, #200
    mov  x4, #0
    ADRL x5, Ldt_list
    mov  x6, #128
    mov  x7, #1005
    bl   _dbl_piece_in
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    mov  x0, x21                          // 0xB0's piece 0: whole
    mov  x1, #0xB0
    mov  x2, #7
    mov  x3, #200
    mov  x4, #0
    ADRL x5, Ldt_list
    mov  x6, #128
    mov  x7, #1006
    bl   _dbl_piece_in
    cmp  x0, #1
    cset x9, eq
    and  x20, x20, x9
    add  x0, x21, #DA_BUF                 // its first 104 bytes are the real list (the rest
    mov  x1, #104                         //   is what this test filled it with)
    ADRL x2, Ldt_pub
    bl   _dbl_verify
    cmp  x0, #3
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Ldt_list                     // _dbl_piece: 128 bytes, then the rest, then none
    mov  x1, #200
    mov  x2, #1
    add  x3, sp, #96
    bl   _dbl_piece
    cmp  x0, #72
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Ldt_list
    mov  x1, #200
    mov  x2, #2
    add  x3, sp, #96
    bl   _dbl_piece
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    mov  x0, x21
    bl   _free
    b    10f
9:  mov  x20, #0
10: mov  w1, w20
    ADRL x0, Ln_dbl219
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
Ln_dbl219:      .asciz "219 developer blocklist over the mesh: pieces put together; a stranger, bad places and sizes refused"
Ln_dbl218:      .asciz "218 developer blocklist: a signed list taken; changed, cut, other or no key refused"
