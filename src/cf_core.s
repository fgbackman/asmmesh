// cf_core.s — the chat filter, pure (no globals, no system calls): words people receive in
// chat that Wiktionary labels vulgar, offensive or a slur (cf_words.inc, made from the
// family list by tools/ninefold/make_chat_filter.py) show with all but their first letter
// as stars ("f***"). A whole word only, with -s or -es: "Scunthorpe", "assess" and
// "Dickens" are untouched, and so are the few that are also names when capitalised (Dick,
// Mongol, Coon). Self-test 217.
.include "macros.inc"

.text
.p2align 2

// long _cf_filter(char *text) -> how many words were starred (in place, same length)
.globl _cf_filter
_cf_filter:
    ENTER 48                              // [96] the word in small letters (16)  [112] flags
    mov  x19, x0
    mov  x20, #0                          // where we are
    mov  x21, #0                          // starred
Lcf_next:
    ldrb w9, [x19, x20]
    cbz  w9, Lcf_done
    bl   Lcf_letter
    cbnz x0, 1f
    add  x20, x20, #1
    b    Lcf_next
1:  mov  x22, x20                         // a word: x22..x23
2:  add  x20, x20, #1
    ldrb w9, [x19, x20]
    bl   Lcf_letter
    cbnz x0, 2b
    mov  x23, x20
    sub  x24, x23, x22                    // its length
    cmp  x24, #3
    b.lo Lcf_next
    cmp  x24, #15
    b.hi Lcf_next
    ldrb w9, [x19, x22]                   // in small letters; Capitalised?
    sub  w10, w9, #'A'
    cmp  w10, #25
    cset x12, ls                          //   x12: the first letter is a capital
    mov  x9, #0
    mov  x13, #0                          //   x13: a capital after the first
3:  cmp  x9, x24
    b.hs 4f
    add  x10, x22, x9
    ldrb w10, [x19, x10]
    sub  w11, w10, #'A'
    cmp  w11, #25
    b.hi 31f
    cmp  x9, #0
    csinc x13, x13, x13, eq
    orr  w10, w10, #0x20
31: add  x11, sp, #96
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    3b
4:  add  x11, sp, #96
    strb wzr, [x11, x24]
    stp  x12, x13, [sp, #112]             // (Lcf_match uses x9-x12)
    add  x0, sp, #96
    mov  x1, x24
    bl   Lcf_match
    cbz  x0, Lcf_next
    ldp  x12, x13, [sp, #112]
    cbz  x12, 5f                          // "Dick", "Mongol": a name, as written
    cbnz x13, 5f
    add  x0, sp, #96
    ADRL x1, Lcf_names
    bl   Lcf_in
    cbnz x0, Lcf_next
5:  add  x9, x22, #1                      // star it, but its first letter
6:  cmp  x9, x23
    b.hs 7f
    mov  w10, #'*'
    strb w10, [x19, x9]
    add  x9, x9, #1
    b    6b
7:  add  x21, x21, #1
    b    Lcf_next
Lcf_done:
    mov  x0, x21
    LEAVE 48

// Lcf_letter(w9 byte) -> x0 1 for A-Z a-z (leaf)
Lcf_letter:
    orr  w10, w9, #0x20
    sub  w10, w10, #'a'
    cmp  w10, #25
    cset x0, ls
    ret

// Lcf_match(x0 word, x1 length) -> 1 if it is on the list, or is one with -s or -es
Lcf_match:
    ENTER 16                              // [96] (the last byte saved)
    mov  x19, x0
    mov  x20, x1
    ADRL x1, Lcf_words
    bl   Lcf_in
    cbnz x0, 9f
    sub  x9, x20, #1                      // without an s
    ldrb w10, [x19, x9]
    cmp  w10, #'s'
    b.ne 8f
    strb wzr, [x19, x9]
    mov  x0, x19
    ADRL x1, Lcf_words
    bl   Lcf_in
    mov  x21, x0
    sub  x9, x20, #1
    mov  w10, #'s'
    strb w10, [x19, x9]
    mov  x0, x21
    cbnz x0, 9f
    sub  x9, x20, #2                      // without es
    ldrb w10, [x19, x9]
    cmp  w10, #'e'
    b.ne 8f
    strb wzr, [x19, x9]
    mov  x0, x19
    ADRL x1, Lcf_words
    bl   Lcf_in
    mov  x21, x0
    sub  x9, x20, #2
    mov  w10, #'e'
    strb w10, [x19, x9]
    mov  x0, x21
    b    9f
8:  mov  x0, #0
9:  LEAVE 16

// Lcf_in(x0 word, x1 a list of strings ending with an empty one) -> 1 if there (leaf)
Lcf_in:
1:  ldrb w9, [x1]
    cbz  w9, 8f
    mov  x10, #0
2:  ldrb w11, [x0, x10]
    ldrb w12, [x1, x10]
    cmp  w11, w12
    b.ne 3f
    add  x10, x10, #1
    cbnz w11, 2b
    mov  x0, #1
    ret
3:  ldrb w12, [x1], #1                    // the next one
    cbnz w12, 3b
    b    1b
8:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
// self-test 217, called from test.s

.globl _cf_core_selftest
_cf_core_selftest:
    ENTER 160                             // [96] a line being filtered (64)
    mov  x19, #0
    mov  x20, #1
    ADRL x21, Lcf_tests
1:  ldr  x1, [x21]                        // pairs: in, out; then how many starred
    cbz  x1, 3f
    add  x0, sp, #96
    mov  x2, #64
    bl   Lcf_copy
    add  x0, sp, #96
    bl   _cf_filter
    ldr  x9, [x21, #16]
    cmp  x0, x9
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #96
    ldr  x1, [x21, #8]
    bl   Lcf_same
    and  x20, x20, x0
    add  x21, x21, #24
    b    1b
3:  mov  w1, w20
    ADRL x0, Ln_cf217
    bl   _t_report
    add  x19, x19, x0
    mov  x0, x19
    LEAVE 160

// Lcf_copy(x0 dst, x1 src, x2 max) (leaf)
Lcf_copy:
    sub  x2, x2, #1
1:  cbz  x2, 2f
    ldrb w9, [x1], #1
    strb w9, [x0], #1
    cbz  w9, 3f
    sub  x2, x2, #1
    b    1b
2:  strb wzr, [x0]
3:  ret

// Lcf_same(a, b) -> 1 if equal (leaf)
Lcf_same:
    ldrb w9, [x0], #1
    ldrb w10, [x1], #1
    cmp  w9, w10
    b.ne 1f
    cbnz w9, Lcf_same
    mov  x0, #1
    ret
1:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lcf_tests:
    .quad Lct_i1, Lct_o1, 1
    .quad Lct_i2, Lct_o2, 1
    .quad Lct_i3, Lct_i3, 0
    .quad Lct_i4, Lct_o4, 2
    .quad Lct_i5, Lct_i5, 0
    .quad Lct_i6, Lct_i6, 0
    .quad Lct_i7, Lct_o7, 1
    .quad Lct_i8, Lct_o8, 1
    .quad 0, 0, 0

.section __TEXT,__cstring,cstring_literals
.include "cf_words.inc"
Lcf_names:
    .asciz "dick"
    .asciz "mongol"
    .asciz "coon"
    .byte 0
Lct_i1:         .asciz "what the fuck is this"
Lct_o1:         .asciz "what the f*** is this"
Lct_i2:         .asciz "Shit happens"
Lct_o2:         .asciz "S*** happens"
Lct_i3:         .asciz "Dick Smith and the Mongol Empire"
Lct_i4:         .asciz "dicks and BITCHES, ok?"
Lct_o4:         .asciz "d**** and B******, ok?"
Lct_i5:         .asciz "Scunthorpe will assess the classic Dickens"
Lct_i6:         .asciz "crappie fishing in Essex"
Lct_i7:         .asciz "you mongol."
Lct_o7:         .asciz "you m*****."
Lct_i8:         .asciz "sh: shit!"
Lct_o8:         .asciz "sh: s***!"
Ln_cf217:       .asciz "217 chat filter: slurs and vulgar words starred; names, Scunthorpe, assess left alone"
