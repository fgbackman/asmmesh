// asmfm — html.S : HTML -> plain text with numbered links, RSS headlines,
// URL resolution and encoding. All output goes through a small text writer
// that collapses whitespace.
.include "fm_defs.inc"
    .text

.set W_OUT, 0
.set W_CAP, 8
.set W_LEN, 16
.set W_PEND, 24
.set W_LS, 28
.set W_NLC, 32
.set MAXLINKS, 200
.set LINKSZ, 512

// ---------------- text writer ----------------
    .globl _fm_w_init
    .p2align 2
_fm_w_init:                 // x0 = dst, x1 = cap
    LA x2, wstate
    str x0, [x2, #W_OUT]
    str x1, [x2, #W_CAP]
    str xzr, [x2, #W_LEN]
    str wzr, [x2, #W_PEND]
    mov w3, #1
    str w3, [x2, #W_LS]
    mov w3, #2
    str w3, [x2, #W_NLC]
    strb wzr, [x0]
    ret

    .globl _fm_w_len
    .p2align 2
_fm_w_len:
    LA x2, wstate
    ldr x0, [x2, #W_LEN]
    ret

// w_room() -> w0 = 1 if at least 16 bytes left
    .p2align 2
w_room:
    LA x2, wstate
    ldr x0, [x2, #W_LEN]
    ldr x1, [x2, #W_CAP]
    add x0, x0, #16
    cmp x0, x1
    cset w0, lo
    ret

    .p2align 2
w_put:                          // w0 = byte
    LA x1, wstate
    ldr x2, [x1, #W_LEN]
    ldr x3, [x1, #W_CAP]
    sub x3, x3, #1
    cmp x2, x3
    b.hs 1f
    ldr x4, [x1, #W_OUT]
    strb w0, [x4, x2]
    add x2, x2, #1
    str x2, [x1, #W_LEN]
    strb wzr, [x4, x2]
1:  ret

    .globl _fm_w_char
    .p2align 2
_fm_w_char:                 // w0 = byte (whitespace collapses)
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    mov w19, w0
    LA x1, wstate
    cmp w0, #' '
    b.eq 5f
    sub w2, w0, #9
    cmp w2, #4
    b.ls 5f
    cbz w0, 9f
    ldr w2, [x1, #W_PEND]
    cbz w2, 1f
    str wzr, [x1, #W_PEND]
    mov w0, #' '
    bl w_put
1:  mov w0, w19
    bl w_put
    LA x1, wstate
    str wzr, [x1, #W_LS]
    str wzr, [x1, #W_NLC]
    b 9f
5:  ldr w2, [x1, #W_LS]
    cbnz w2, 9f
    mov w2, #1
    str w2, [x1, #W_PEND]
9:  ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

    .globl _fm_w_nl
    .p2align 2
_fm_w_nl:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    LA x1, wstate
    str wzr, [x1, #W_PEND]
    ldr w2, [x1, #W_NLC]
    cmp w2, #2
    b.ge 9f
    add w2, w2, #1
    str w2, [x1, #W_NLC]
    mov w2, #1
    str w2, [x1, #W_LS]
    mov w0, #'\n'
    bl w_put
9:  ldp x29, x30, [sp], #16
    ret

    .globl _fm_w_str
    .p2align 2
_fm_w_str:                  // x0 = cstr
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    mov x19, x0
1:  ldrb w0, [x19], #1
    cbz w0, 2f
    cmp w0, #'\n'
    b.ne 3f
    bl _fm_w_nl
    b 1b
3:  bl _fm_w_char
    b 1b
2:  ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

    .globl _fm_w_num
    .p2align 2
_fm_w_num:                  // x0 = number
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    add x1, sp, #16
    bl _fm_utoa
    add x0, sp, #16
    bl _fm_w_str
    ldp x29, x30, [sp], #48
    ret

// ---------------- helpers ----------------
// ifind(x0 = p, x1 = end, x2 = needle cstr) -> x0 = match or end (ignore case)
    .p2align 2
ifind:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x0, x2
    bl _strlen
    sub x22, x20, x0            // last start
1:  cmp x19, x22
    b.hi 8f
    mov x0, x19
    mov x1, x21
    bl _fm_istarts
    cbnz w0, 9f
    add x19, x19, #1
    b 1b
8:  mov x19, x20
9:  mov x0, x19
    ldp x19, x20, [sp, #16]
    ldp x21, x22, [sp, #32]
    ldp x29, x30, [sp], #48
    ret

// isalnum(w0) -> w0
    .p2align 2
is_alnum:
    sub w1, w0, #'0'
    cmp w1, #9
    b.ls 1f
    orr w1, w0, #0x20
    sub w1, w1, #'a'
    cmp w1, #25
    b.ls 1f
    mov w0, #0
    ret
1:  mov w0, #1
    ret

// emit_utf8(w0 = code point) through the writer
    .p2align 2
emit_utf8:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    mov w19, w0
    cmp w19, #160
    b.ne 0f
    mov w19, #' '
0:  cmp w19, #0x80
    b.hs 1f
    mov w0, w19
    bl _fm_w_char
    b 9f
1:  cmp w19, #0x800
    b.hs 2f
    lsr w0, w19, #6
    orr w0, w0, #0xC0
    bl _fm_w_char
    b 7f
2:  mov w1, #0x10000
    cmp w19, w1
    b.hs 3f
    lsr w0, w19, #12
    orr w0, w0, #0xE0
    bl _fm_w_char
    b 6f
3:  mov w1, #0x110000
    cmp w19, w1
    b.hs 8f
    lsr w0, w19, #18
    orr w0, w0, #0xF0
    bl _fm_w_char
    lsr w0, w19, #12
    and w0, w0, #0x3F
    orr w0, w0, #0x80
    bl _fm_w_char
6:  lsr w0, w19, #6
    and w0, w0, #0x3F
    orr w0, w0, #0x80
    bl _fm_w_char
7:  and w0, w19, #0x3F
    orr w0, w0, #0x80
    bl _fm_w_char
    b 9f
8:  mov w0, #'?'
    bl _fm_w_char
9:  ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

// entity(x0 = pointer at '&', x1 = end) -> x0 = pointer after the entity; emits text
    .p2align 2
entity:
    FENTER 32
    mov x19, x0
    mov x20, x1
    add x21, x19, #1            // name start
    mov x22, x21
1:  cmp x22, x20
    b.hs 8f
    sub x0, x22, x21
    cmp x0, #10
    b.gt 8f
    ldrb w0, [x22]
    cmp w0, #59              // ';'
    b.eq 2f
    cmp w0, #'#'
    b.eq 11f
    bl is_alnum
    cbz w0, 8f
11: add x22, x22, #1
    b 1b
2:  sub x23, x22, x21           // name length
    cbz x23, 8f
    ldrb w0, [x21]
    cmp w0, #'#'
    b.ne 5f
    // numeric
    mov w24, #0
    add x25, x21, #1
    mov w26, #10
    ldrb w0, [x25]
    orr w0, w0, #0x20
    cmp w0, #'x'
    b.ne 3f
    mov w26, #16
    add x25, x25, #1
3:  cmp x25, x22
    b.hs 4f
    ldrb w0, [x25], #1
    sub w1, w0, #'0'
    cmp w1, #9
    b.ls 31f
    cmp w26, #16
    b.ne 8f
    orr w1, w0, #0x20
    sub w1, w1, #'a'
    cmp w1, #5
    b.hi 8f
    add w1, w1, #10
31: mul w24, w24, w26
    add w24, w24, w1
    mov w2, #0x110000
    cmp w24, w2
    b.hi 8f
    b 3b
4:  mov w0, w24
    cbz w0, 8f
    bl emit_utf8
    add x0, x22, #1
    FLEAVE 32
5:  // named: copy name to local buffer and look it up
    cmp x23, #15
    b.gt 8f
    add x0, sp, #LOC
    mov x1, x21
    mov x2, x23
    bl _memcpy
    add x0, sp, #LOC
    strb wzr, [x0, x23]
    LA x24, ent_table
6:  ldrb w0, [x24]
    cbz w0, 8f
    add x0, sp, #LOC
    mov x1, x24
    bl _fm_streq
    mov w25, w0
    mov x0, x24
    bl _strlen
    add x24, x24, x0
    add x24, x24, #1            // -> replacement
    cbnz w25, 7f
    mov x0, x24
    bl _strlen
    add x24, x24, x0
    add x24, x24, #1
    b 6b
7:  mov x0, x24
    bl _fm_w_str
    add x0, x22, #1
    FLEAVE 32
8:  mov w0, #'&'
    bl _fm_w_char
    add x0, x19, #1
    FLEAVE 32

// get_attr(x0 = start, x1 = end, x2 = name) -> x0 = value ptr, x1 = length (0 if none)
    .p2align 2
get_attr:
    FENTER
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x0
    mov x0, x2
    bl _strlen
    mov x23, x0
1:  add x0, x22, x23
    cmp x0, x20
    b.hs 8f
    cmp x22, x19
    b.eq 2f
    ldurb w0, [x22, #-1]
    cmp w0, #' '
    b.eq 2f
    sub w0, w0, #9
    cmp w0, #4
    b.ls 2f
    b 7f
2:  mov x0, x22
    mov x1, x21
    bl _fm_istarts
    cbz w0, 7f
    add x24, x22, x23
3:  cmp x24, x20
    b.hs 7f
    ldrb w0, [x24]
    cmp w0, #' '
    b.ne 4f
    add x24, x24, #1
    b 3b
4:  cmp w0, #'='
    b.ne 7f
    add x24, x24, #1
41: cmp x24, x20
    b.hs 8f
    ldrb w0, [x24]
    cmp w0, #' '
    b.ne 42f
    add x24, x24, #1
    b 41b
42: cmp w0, #'"'
    b.eq 5f
    cmp w0, #'\''
    b.eq 5f
    mov x25, x24                // unquoted
43: cmp x25, x20
    b.hs 44f
    ldrb w1, [x25]
    cmp w1, #' '
    b.eq 44f
    cmp w1, #'>'
    b.eq 44f
    add x25, x25, #1
    b 43b
44: mov x0, x24
    sub x1, x25, x24
    FLEAVE
5:  mov w26, w0
    add x24, x24, #1
    mov x25, x24
51: cmp x25, x20
    b.hs 44b
    ldrb w1, [x25]
    cmp w1, w26
    b.eq 44b
    add x25, x25, #1
    b 51b
7:  add x22, x22, #1
    b 1b
8:  mov x0, #0
    mov x1, #0
    FLEAVE

// ---------------- URL helpers ----------------
// fm_urlencode(x0 = src cstr, x1 = dst, x2 = cap) -> x0 = length
    .globl _fm_urlencode
    .p2align 2
_fm_urlencode:
    LA x9, hexdig
    mov x3, #0
    sub x2, x2, #4
1:  ldrb w4, [x0], #1
    cbz w4, 9f
    cmp x3, x2
    b.hs 9f
    cmp w4, #' '
    b.ne 2f
    mov w4, #'+'
    b 3f
2:  sub w5, w4, #'0'
    cmp w5, #9
    b.ls 3f
    orr w5, w4, #0x20
    sub w5, w5, #'a'
    cmp w5, #25
    b.ls 3f
    cmp w4, #'-'
    b.eq 3f
    cmp w4, #'_'
    b.eq 3f
    cmp w4, #'.'
    b.eq 3f
    cmp w4, #'~'
    b.eq 3f
    mov w5, #'%'
    strb w5, [x1, x3]
    add x3, x3, #1
    lsr w5, w4, #4
    ldrb w5, [x9, w5, uxtw]
    strb w5, [x1, x3]
    add x3, x3, #1
    and w5, w4, #15
    ldrb w5, [x9, w5, uxtw]
    strb w5, [x1, x3]
    add x3, x3, #1
    b 1b
3:  strb w4, [x1, x3]
    add x3, x3, #1
    b 1b
9:  strb wzr, [x1, x3]
    mov x0, x3
    ret

// hexval(w0) -> w0 0..15 or -1
    .p2align 2
hexval:
    sub w1, w0, #'0'
    cmp w1, #9
    b.ls 1f
    orr w1, w0, #0x20
    sub w1, w1, #'a'
    cmp w1, #5
    b.hi 2f
    add w0, w1, #10
    ret
1:  mov w0, w1
    ret
2:  mov w0, #-1
    ret

// origin_len(x0 = url) -> x0 = length of "scheme://host[:port]"
    .p2align 2
origin_len:
    mov x1, #0
1:  ldrb w2, [x0, x1]
    cbz w2, 9f
    cmp w2, #':'
    b.ne 2f
    ldrb w3, [x0, x1]
    add x4, x1, #1
    ldrb w3, [x0, x4]
    cmp w3, #'/'
    b.ne 2f
    add x4, x4, #1
    ldrb w3, [x0, x4]
    cmp w3, #'/'
    b.ne 2f
    add x1, x4, #1
3:  ldrb w2, [x0, x1]
    cbz w2, 9f
    cmp w2, #'/'
    b.eq 9f
    cmp w2, #'?'
    b.eq 9f
    cmp w2, #'#'
    b.eq 9f
    add x1, x1, #1
    b 3b
2:  add x1, x1, #1
    b 1b
9:  mov x0, x1
    ret

// fm_resolve(x0 = base, x1 = href, x2 = href length, x3 = dst[512]) -> w0 = length (0 = skip)
    .globl _fm_resolve
    .p2align 2
_fm_resolve:
    FENTER 16
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    strb wzr, [x22]
    // trim leading spaces
1:  cbz x21, 90f
    ldrb w0, [x20]
    cmp w0, #' '
    b.hi 2f
    add x20, x20, #1
    sub x21, x21, #1
    b 1b
2:  cmp w0, #'#'
    b.eq 90f
    cmp x21, #400
    b.hi 90f
    // copy href to tmp decoding &amp;
    LA x23, rtmp
    mov x24, #0                 // src idx
    mov x25, #0                 // dst idx
3:  cmp x24, x21
    b.hs 4f
    ldrb w0, [x20, x24]
    cmp w0, #' '
    b.ls 31f
    strb w0, [x23, x25]
    add x25, x25, #1
    cmp w0, #'&'
    b.ne 31f
    add x0, x20, x24
    LA x1, s_amp
    bl _fm_istarts
    cbz w0, 31f
    add x24, x24, #4
31: add x24, x24, #1
    b 3b
4:  strb wzr, [x23, x25]
    cbz x25, 90f
    // rejected schemes
    LA x26, bad_schemes
5:  ldrb w0, [x26]
    cbz w0, 6f
    mov x0, x23
    mov x1, x26
    bl _fm_istarts
    cbnz w0, 90f
    mov x0, x26
    bl _strlen
    add x26, x26, x0
    add x26, x26, #1
    b 5b
6:  mov x0, x23
    LA x1, s_http
    bl _fm_istarts
    cbnz w0, 60f
    mov x0, x23
    LA x1, s_https
    bl _fm_istarts
    cbnz w0, 60f
    ldrb w0, [x23]
    ldrb w1, [x23, #1]
    cmp w0, #'/'
    b.ne 7f
    cmp w1, #'/'
    b.ne 65f
    // //host/path : scheme of base
    mov x0, x22
    LA x1, s_https_colon
    mov x2, #LINKSZ
    bl _fm_strlcpy
    mov x0, x19
    LA x1, s_http
    bl _fm_istarts
    cbz w0, 61f
    mov x0, x22
    LA x1, s_http_colon
    mov x2, #LINKSZ
    bl _fm_strlcpy
61: mov x0, x22
    mov x1, x23
    mov x2, #LINKSZ
    bl _fm_strlcat
    b 80f
65: // /path : origin + path
    mov x0, x19
    bl origin_len
    add x2, x0, #1
    mov x0, x22
    mov x1, x19
    cmp x2, #LINKSZ
    b.hi 90f
    bl _fm_strlcpy
    b 61b
7:  // relative: base up to last '/' (before any ? or #)
    mov x0, x19
    bl origin_len
    mov x24, x0                 // origin length
    mov x1, x24
    mov x25, x24                // position after last '/', default origin
    mov w26, #0                 // saw path slash
71: ldrb w2, [x19, x1]
    cbz w2, 72f
    cmp w2, #'?'
    b.eq 72f
    cmp w2, #'#'
    b.eq 72f
    cmp w2, #'/'
    b.ne 73f
    add x25, x1, #1
    mov w26, #1
73: add x1, x1, #1
    b 71b
72: ldrb w0, [x23]
    cmp w0, #'?'
    b.ne 74f
    mov x25, x1                 // ?query replaces query only
    mov w26, #1
74: add x2, x25, #1
    cmp x2, #LINKSZ
    b.hi 90f
    mov x0, x22
    mov x1, x19
    bl _fm_strlcpy
    cbnz w26, 61b
    mov x0, x22
    LA x1, s_slash
    mov x2, #LINKSZ
    bl _fm_strlcat
    b 61b
60: mov x0, x22
    mov x1, x23
    mov x2, #LINKSZ
    bl _fm_strlcpy
80: // DuckDuckGo redirect links: take the uddg= target
    mov x0, x22
    LA x1, s_uddg
    bl _strstr
    cbz x0, 89f
    add x20, x0, #5
    LA x23, rtmp
    mov x25, #0
81: ldrb w0, [x20], #1
    cbz w0, 88f
    cmp w0, #'&'
    b.eq 88f
    cmp w0, #'%'
    b.ne 82f
    ldrb w0, [x20]
    bl hexval
    tbnz w0, #31, 83f
    mov w24, w0
    ldrb w0, [x20, #1]
    bl hexval
    tbnz w0, #31, 83f
    orr w0, w0, w24, lsl #4
    add x20, x20, #2
    b 82f
83: mov w0, #'%'
82: strb w0, [x23, x25]
    add x25, x25, #1
    cmp x25, #500
    b.lo 81b
88: strb wzr, [x23, x25]
    mov x0, x22
    mov x1, x23
    mov x2, #LINKSZ
    bl _fm_strlcpy
89: mov x0, x22
    bl _strlen
    FLEAVE 16
90: mov w0, #0
    FLEAVE 16

// add_link(x0 = base, x1 = href, x2 = len) -> w0 = link number (0 if skipped)
    .p2align 2
add_link:
    FENTER
    mov x19, x0
    mov x20, x1
    mov x21, x2
    LA x22, _fm_nlinks
    ldr w23, [x22]
    cmp w23, #MAXLINKS
    b.ge 9f
    LA x3, _fm_links
    mov w4, #LINKSZ
    umaddl x3, w23, w4, x3
    bl _fm_resolve
    cbz w0, 9f
    add w23, w23, #1
    str w23, [x22]
    mov w0, w23
    FLEAVE
9:  mov w0, #0
    FLEAVE

// ---------------- HTML to text ----------------
// fm_html2text(x0 = src, x1 = length, x2 = dst, x3 = cap, x4 = base url) -> x0 = text length
    .globl _fm_html2text
    .p2align 2
_fm_html2text:
    FENTER 64
    mov x19, x0
    add x20, x0, x1
    mov x21, x4
    mov x0, x2
    mov x1, x3
    bl _fm_w_init
    LA x0, _fm_nlinks
    str wzr, [x0]
    mov w22, #0                 // pending link number
10: cmp x19, x20
    b.hs 99f
    bl w_room
    cbz w0, 99f
    ldrb w0, [x19]
    cmp w0, #'<'
    b.eq 20f
    cmp w0, #'&'
    b.eq 15f
    bl _fm_w_char
    add x19, x19, #1
    b 10b
15: mov x0, x19
    mov x1, x20
    bl entity
    mov x19, x0
    b 10b
20: // ---- tag ----
    add x24, x19, #1
    mov x0, x24
    LA x1, s_comment
    bl _fm_istarts
    cbz w0, 21f
    add x0, x24, #3
    mov x1, x20
    LA x2, s_comment_end
    bl ifind
    add x19, x0, #3
    b 10b
21: ldrb w0, [x24]
    cmp w0, #'!'
    b.eq 22f
    cmp w0, #'?'
    b.eq 22f
    mov w23, #0
    cmp w0, #'/'
    b.ne 23f
    mov w23, #1
    add x24, x24, #1
23: // read tag name into LOC (lower case, max 15)
    mov x25, #0
24: cmp x24, x20
    b.hs 25f
    ldrb w0, [x24]
    bl is_alnum
    cbz w0, 25f
    ldrb w0, [x24]
    bl _fm_lower
    cmp x25, #15
    b.hs 241f
    add x1, sp, #LOC
    strb w0, [x1, x25]
    add x25, x25, #1
241: add x24, x24, #1
    b 24b
25: add x1, sp, #LOC
    strb wzr, [x1, x25]
    cbnz x25, 26f
    mov w0, #'<'                // not a tag: literal '<'
    bl _fm_w_char
    add x19, x19, #1
    b 10b
22: // <!doctype ...> or <?xml ...?>: skip to '>'
    mov x25, x24
    b 27f
26: mov x25, x24                // attributes start
27: // find closing '>' honoring quotes
    mov x26, x25
271: cmp x26, x20
    b.hs 28f
    ldrb w0, [x26]
    cmp w0, #'>'
    b.eq 28f
    cmp w0, #'"'
    b.eq 272f
    cmp w0, #'\''
    b.ne 273f
272: mov w1, w0
    add x26, x26, #1
274: cmp x26, x20
    b.hs 28f
    ldrb w0, [x26]
    cmp w0, w1
    b.eq 273f
    add x26, x26, #1
    b 274b
273: add x26, x26, #1
    b 271b
28: add x19, x26, #1           // continue after '>'
    ldrb w0, [x24]
    cmp w0, #'!'
    b.eq 10b
    cmp w0, #'?'
    b.eq 10b
    // ---- dispatch on tag name ----
    cbnz w23, 30f
    add x0, sp, #LOC
    LA x1, skip_tags
    bl in_list
    cbz w0, 30f
    // skip everything up to </name
    add x0, sp, #(LOC+16)
    LA x1, s_lt_slash
    mov x2, #24
    bl _fm_strlcpy
    add x0, sp, #(LOC+16)
    add x1, sp, #LOC
    mov x2, #24
    bl _fm_strlcat
    mov x0, x19
    mov x1, x20
    add x2, sp, #(LOC+16)
    bl ifind
    mov x1, x0
2811: cmp x1, x20
    b.hs 2812f
    ldrb w2, [x1], #1
    cmp w2, #'>'
    b.ne 2811b
2812: mov x19, x1
    b 10b
30: add x0, sp, #LOC
    LA x1, s_a
    bl _fm_streq
    cbz w0, 35f
    cbnz w23, 32f
    // <a href=...>
    mov x0, x25
    mov x1, x26
    LA x2, s_href
    bl get_attr
    cbz x1, 10b
    mov x2, x1
    mov x1, x0
    mov x0, x21
    bl add_link
    cbz w0, 10b
    mov w22, w0
    b 10b
32: cbz w22, 10b                // </a>: print [n]
    mov w0, #'['
    bl _fm_w_char
    mov w0, w22
    bl _fm_w_num
    mov w0, #']'
    bl _fm_w_char
    mov w22, #0
    b 10b
35: add x0, sp, #LOC
    LA x1, s_br
    bl _fm_streq
    cbz w0, 36f
    bl _fm_w_nl
    b 10b
36: add x0, sp, #LOC
    LA x1, s_li
    bl _fm_streq
    cbz w0, 37f
    bl _fm_w_nl
    cbnz w23, 10b
    mov w0, #'*'
    bl _fm_w_char
    mov w0, #' '
    bl _fm_w_char
    b 10b
37: add x0, sp, #LOC
    LA x1, space_tags
    bl in_list
    cbz w0, 38f
    mov w0, #' '
    bl _fm_w_char
    b 10b
38: add x0, sp, #LOC
    LA x1, block_tags
    bl in_list
    cbz w0, 10b
    bl _fm_w_nl
    b 10b
99: bl _fm_w_len
    FLEAVE 64

// in_list(x0 = name, x1 = list of cstrs ending with "") -> w0
    .p2align 2
in_list:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x20, x1
1:  ldrb w0, [x20]
    cbz w0, 8f
    mov x0, x19
    mov x1, x20
    bl _fm_streq
    cbnz w0, 9f
    mov x0, x20
    bl _strlen
    add x20, x20, x0
    add x20, x20, #1
    b 1b
8:  mov w0, #0
9:  ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

// ---------------- RSS headlines ----------------
// fm_rss_titles(x0 = src, x1 = length, x2 = dst, x3 = cap) -> x0 = text length
    .globl _fm_rss_titles
    .p2align 2
_fm_rss_titles:
    FENTER
    mov x19, x0
    add x20, x0, x1
    mov x0, x2
    mov x1, x3
    bl _fm_w_init
1:  bl w_room
    cbz w0, 9f
    mov x0, x19
    mov x1, x20
    LA x2, s_title
    bl ifind
    cmp x0, x20
    b.hs 9f
    add x0, x0, #6
    mov x1, x0
2:  cmp x1, x20
    b.hs 9f
    ldrb w2, [x1], #1
    cmp w2, #'>'
    b.ne 2b
    mov x21, x1                 // text start
    mov x0, x1
    mov x1, x20
    LA x2, s_title_end
    bl ifind
    mov x22, x0                 // text end
    add x19, x0, #1
    mov x0, x21
    LA x1, s_cdata
    bl _fm_istarts
    cbz w0, 3f
    add x21, x21, #9
    sub x0, x22, #3
    cmp x0, x21
    b.lo 3f
    mov x22, x0
3:  LA x0, s_dash
    bl _fm_w_str
4:  cmp x21, x22
    b.hs 6f
    ldrb w0, [x21]
    cmp w0, #'&'
    b.ne 5f
    mov x0, x21
    mov x1, x22
    bl entity
    mov x21, x0
    b 4b
5:  bl _fm_w_char
    add x21, x21, #1
    b 4b
6:  bl _fm_w_nl
    b 1b
9:  bl _fm_w_len
    FLEAVE

    .section __TEXT,__const
hexdig: .ascii "0123456789ABCDEF"
s_amp:  .asciz "&amp;"
s_http: .asciz "http://"
s_https: .asciz "https://"
s_http_colon: .asciz "http:"
s_https_colon: .asciz "https:"
s_slash: .asciz "/"
s_uddg: .asciz "uddg="
s_comment: .asciz "!--"
s_comment_end: .asciz "-->"
s_lt_slash: .asciz "</"
s_a:    .asciz "a"
s_href: .asciz "href"
s_br:   .asciz "br"
s_li:   .asciz "li"
s_title: .asciz "<title"
s_title_end: .asciz "</title"
s_cdata: .asciz "<![CDATA["
s_dash: .asciz "- "
bad_schemes:
    .asciz "javascript:"
    .asciz "mailto:"
    .asciz "tel:"
    .asciz "data:"
    .asciz ""
skip_tags:
    .asciz "script"
    .asciz "style"
    .asciz "noscript"
    .asciz "svg"
    .asciz "template"
    .asciz "iframe"
    .asciz "select"
    .asciz ""
space_tags:
    .asciz "td"
    .asciz "th"
    .asciz "img"
    .asciz ""
block_tags:
    .asciz "p"
    .asciz "div"
    .asciz "h1"
    .asciz "h2"
    .asciz "h3"
    .asciz "h4"
    .asciz "h5"
    .asciz "h6"
    .asciz "tr"
    .asciz "table"
    .asciz "ul"
    .asciz "ol"
    .asciz "dl"
    .asciz "dt"
    .asciz "dd"
    .asciz "section"
    .asciz "article"
    .asciz "header"
    .asciz "footer"
    .asciz "nav"
    .asciz "main"
    .asciz "aside"
    .asciz "blockquote"
    .asciz "pre"
    .asciz "hr"
    .asciz "title"
    .asciz "form"
    .asciz "figure"
    .asciz "figcaption"
    .asciz "address"
    .asciz "option"
    .asciz "body"
    .asciz ""
ent_table:
    .asciz "amp"
    .asciz "&"
    .asciz "lt"
    .asciz "<"
    .asciz "gt"
    .asciz ">"
    .asciz "quot"
    .asciz "\""
    .asciz "apos"
    .asciz "'"
    .asciz "nbsp"
    .asciz " "
    .asciz "mdash"
    .asciz "\342\200\224"
    .asciz "ndash"
    .asciz "\342\200\223"
    .asciz "hellip"
    .asciz "\342\200\246"
    .asciz "rsquo"
    .asciz "\342\200\231"
    .asciz "lsquo"
    .asciz "\342\200\230"
    .asciz "rdquo"
    .asciz "\342\200\235"
    .asciz "ldquo"
    .asciz "\342\200\234"
    .asciz "laquo"
    .asciz "\302\253"
    .asciz "raquo"
    .asciz "\302\273"
    .asciz "middot"
    .asciz "\302\267"
    .asciz "bull"
    .asciz "\342\200\242"
    .asciz "copy"
    .asciz "\302\251"
    .asciz "reg"
    .asciz "\302\256"
    .asciz "trade"
    .asciz "\342\204\242"
    .asciz "euro"
    .asciz "\342\202\254"
    .asciz "pound"
    .asciz "\302\243"
    .asciz "deg"
    .asciz "\302\260"
    .asciz "times"
    .asciz "\303\227"
    .asciz ""

    .data
    .p2align 3
wstate: .space 48
    .globl _fm_nlinks
_fm_nlinks: .word 0

    BSS rtmp, 1024
    BSS _fm_links, (MAXLINKS*LINKSZ)
