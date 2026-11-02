// hue_core.s — the bytes-only parts of Hue (hue.s does the network): reading the serial
// codes printed on bulbs, checking a bridge address someone typed, and telling a Hue
// bridge's SSDP answer from other devices'. No libc, so they run under qemu too.
//
// A Hue serial is the 6 letters and digits (hex) printed on the bulb or its label, the same
// code the Hue app's "Add by serial number" takes. The bridge (v1 round or v2 square, API
// v1) searches for up to 10 at once: POST /api/<user>/lights {"deviceid":["1A2B3C",...]}.

.include "macros.inc"

.set HS_MAX, 10

.text
.p2align 2

// long Lhc_lower(long c) -> ASCII lower case (leaf: w12)
Lhc_lower:
    sub  w12, w0, #'A'
    cmp  w12, #25
    b.hi 1f
    add  w0, w0, #32
1:  ret

// long Lhc_word_is(const char *w, long n, const char *lc) -> 1 if the n bytes at w are the
//   word lc, ignoring case (leaf: x9-x12)
Lhc_word_is:
    mov  x9, #0
1:  cmp  x9, x1
    b.hs 3f
    ldrb w10, [x2, x9]
    cbz  w10, 4f
    ldrb w11, [x0, x9]
    sub  w12, w11, #'A'
    cmp  w12, #25
    b.hi 2f
    add  w11, w11, #32
2:  cmp  w10, w11
    b.ne 4f
    add  x9, x9, #1
    b    1b
3:  ldrb w10, [x2, x9]
    cbnz w10, 4f
    mov  x0, #1
    ret
4:  mov  x0, #0
    ret

// long _hue_serials(const char *text, char *out, long cap) -> how many serials (0-10) with
//   out the bridge's search body ({} for 0: search for any new light), -1 a word that isn't
//   a serial (out ""), -2 more than 10, -3 cap too small. Words like "light", "bulb",
//   "serial", "code", "and" are skipped; separators are spaces, commas and semicolons.
.globl _hue_serials
_hue_serials:
    ENTER 32                              // [96] count
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    cmp  x21, #(16 + HS_MAX * 9 + 4)      // room for all ten
    b.lo Lhs_small
    strb wzr, [x20]
    mov  x23, #0                          // count
    mov  x22, #0                          // out length
    ADRL x1, Lhs_head
1:  ldrb w9, [x1], #1                     // {"deviceid":[
    cbz  w9, Lhs_word
    strb w9, [x20, x22]
    add  x22, x22, #1
    b    1b
Lhs_word:                                 // skip separators
    ldrb w9, [x19]
    cbz  w9, Lhs_end
    cmp  w9, #' '
    b.eq 2f
    cmp  w9, #','
    b.eq 2f
    cmp  w9, #';'
    b.eq 2f
    cmp  w9, #'\t'
    b.eq 2f
    cmp  w9, #'#'
    b.eq 2f
    b    3f
2:  add  x19, x19, #1
    b    Lhs_word
3:  mov  x24, #0                          // the word's length
4:  ldrb w9, [x19, x24]
    cbz  w9, 5f
    cmp  w9, #' '
    b.eq 5f
    cmp  w9, #','
    b.eq 5f
    cmp  w9, #';'
    b.eq 5f
    cmp  w9, #'\t'
    b.eq 5f
    add  x24, x24, #1
    cmp  x24, #64
    b.hs Lhs_bad
    b    4b
5:  ADRL x15, Lhs_skip                    // a filler word? (x15: Lhc_word_is keeps it)
6:  ldr  x2, [x15], #8
    cbz  x2, 7f
    mov  x0, x19
    mov  x1, x24
    bl   Lhc_word_is
    cbz  x0, 6b
    add  x19, x19, x24
    b    Lhs_word
7:  cmp  x24, #6                          // a serial: 6 hex digits
    b.ne Lhs_bad
    mov  x9, #0
8:  cmp  x9, #6
    b.hs 9f
    ldrb w0, [x19, x9]
    bl   Lhc_lower
    sub  w10, w0, #'0'
    cmp  w10, #9
    b.ls 81f
    sub  w10, w0, #'a'
    cmp  w10, #5
    b.hi Lhs_bad
81: add  x9, x9, #1
    b    8b
9:  cmp  x23, #HS_MAX
    b.hs Lhs_many
    cbz  x23, 10f
    mov  w9, #','
    strb w9, [x20, x22]
    add  x22, x22, #1
10: mov  w9, #'"'
    strb w9, [x20, x22]
    add  x22, x22, #1
    mov  x9, #0
11: ldrb w10, [x19, x9]                   // upper case, as the Hue app shows them
    sub  w11, w10, #'a'
    cmp  w11, #25
    b.hi 12f
    sub  w10, w10, #32
12: strb w10, [x20, x22]
    add  x22, x22, #1
    add  x9, x9, #1
    cmp  x9, #6
    b.lo 11b
    mov  w9, #'"'
    strb w9, [x20, x22]
    add  x22, x22, #1
    add  x23, x23, #1
    add  x19, x19, #6
    b    Lhs_word
Lhs_end:
    cbz  x23, Lhs_any
    mov  w9, #']'
    strb w9, [x20, x22]
    add  x22, x22, #1
    mov  w9, #'}'
    strb w9, [x20, x22]
    add  x22, x22, #1
    strb wzr, [x20, x22]
    mov  x0, x23
    LEAVE 32
Lhs_any:
    mov  w9, #'{'
    strb w9, [x20]
    mov  w9, #'}'
    strb w9, [x20, #1]
    strb wzr, [x20, #2]
    mov  x0, #0
    LEAVE 32
Lhs_bad:
    strb wzr, [x20]
    mov  x0, #-1
    LEAVE 32
Lhs_many:
    strb wzr, [x20]
    mov  x0, #-2
    LEAVE 32
Lhs_small:
    mov  x0, #-3
    LEAVE 32

// long _hue_addr_ok(const char *s) -> 1 if it can be a bridge's address in a URL: 1-63 of
//   letters, digits, '.', '-' (an IPv4 address or a name like Philips-hue.local), not
//   starting with '.' or '-' (leaf)
.globl _hue_addr_ok
_hue_addr_ok:
    ldrb w9, [x0]
    cmp  w9, #'.'
    b.eq 9f
    cmp  w9, #'-'
    b.eq 9f
    mov  x10, #0
1:  ldrb w9, [x0, x10]
    cbz  w9, 5f
    cmp  x10, #63
    b.hs 9f
    sub  w11, w9, #'0'
    cmp  w11, #9
    b.ls 2f
    orr  w11, w9, #0x20
    sub  w11, w11, #'a'
    cmp  w11, #25
    b.ls 2f
    cmp  w9, #'.'
    b.eq 2f
    cmp  w9, #'-'
    b.ne 9f
2:  add  x10, x10, #1
    b    1b
5:  cbz  x10, 9f
    mov  x0, #1
    ret
9:  mov  x0, #0
    ret

// long _ssdp_is_hue(const char *answer) -> 1 if an SSDP answer is a Hue bridge's: its
//   SERVER line says "IpBridge" (every bridge, the round v1 too, which has no Bonjour) or a
//   "hue-bridgeid:" line (leaf)
.globl _ssdp_is_hue
_ssdp_is_hue:
    mov  x15, x30                         // (Lhc_has keeps x14 and x15)
    ADRL x1, Lhs_ipbridge
    mov  x14, x0
    bl   Lhc_has
    cbnz x0, 1f
    mov  x0, x14
    ADRL x1, Lhs_bridgeid
    bl   Lhc_has
1:  mov  x30, x15
    ret

// long Lhc_has(const char *s, const char *lc) -> 1 if s has lc in it, ignoring case
//   (leaf: x9-x13; x14 and x15 kept)
Lhc_has:
    mov  x9, #0
1:  mov  x10, #0
2:  ldrb w12, [x1, x10]
    cbz  w12, 8f
    add  x13, x9, x10
    ldrb w11, [x0, x13]
    cbz  w11, 9f
    sub  w13, w11, #'A'
    cmp  w13, #25
    b.hi 3f
    add  w11, w11, #32
3:  cmp  w11, w12
    b.ne 4f
    add  x10, x10, #1
    b    2b
4:  add  x9, x9, #1
    b    1b
8:  mov  x0, #1
    ret
9:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
// self-tests 188-190, called from test.s

.macro HC_STR lbl                         // x20 &= (string at x22 == \lbl)
    mov  x0, x22
    ADRL x1, \lbl
    bl   Lhc_same
    and  x20, x20, x0
.endm

// long Lhc_same(a, b) -> 1 if equal (leaf)
Lhc_same:
    mov  x9, #0
1:  ldrb w10, [x0, x9]
    ldrb w11, [x1, x9]
    cmp  w10, w11
    b.ne 2f
    add  x9, x9, #1
    cbnz w10, 1b
    mov  x0, #1
    ret
2:  mov  x0, #0
    ret

.globl _hue_core_selftest
_hue_core_selftest:
    ENTER 256                             // [96] out (256)
    mov  x19, #0
    add  x22, sp, #96

    // 188. serials: fillers skipped, case fixed, commas; none: any new light; bad words
    mov  x20, #1
    ADRL x0, Lht_in1
    mov  x1, x22
    mov  x2, #256
    bl   _hue_serials
    cmp  x0, #2
    cset x9, eq
    and  x20, x20, x9
    HC_STR Lht_out1
    ADRL x0, Lht_in2
    mov  x1, x22
    mov  x2, #256
    bl   _hue_serials
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    HC_STR Lht_out2
    ADRL x0, Lht_in3                      // 7 characters
    mov  x1, x22
    mov  x2, #256
    bl   _hue_serials
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lht_in4                      // a quote: never into the JSON
    mov  x1, x22
    mov  x2, #256
    bl   _hue_serials
    cmp  x0, #-1
    cset x9, eq
    and  x20, x20, x9
    HC_STR Lht_empty
    mov  w1, w20
    ADRL x0, Ln_hc188
    bl   _t_report
    add  x19, x19, x0

    // 189. at most ten; a small buffer refused
    mov  x20, #1
    ADRL x0, Lht_in10
    mov  x1, x22
    mov  x2, #256
    bl   _hue_serials
    cmp  x0, #10
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lht_in11
    mov  x1, x22
    mov  x2, #256
    bl   _hue_serials
    cmp  x0, #-2
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lht_in1
    mov  x1, x22
    mov  x2, #40
    bl   _hue_serials
    cmp  x0, #-3
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_hc189
    bl   _t_report
    add  x19, x19, x0

    // 190. bridge addresses; a Hue bridge's SSDP answer (v1 and v2), and a TV's
    mov  x20, #1
    ADRL x0, Lht_a1
    bl   _hue_addr_ok
    and  x20, x20, x0
    ADRL x0, Lht_a2
    bl   _hue_addr_ok
    and  x20, x20, x0
    ADRL x24, Lht_bad_addrs
1:  ldr  x0, [x24], #8
    cbz  x0, 2f
    bl   _hue_addr_ok
    eor  x0, x0, #1
    and  x20, x20, x0
    b    1b
2:  ADRL x0, Lht_ssdp_v1
    bl   _ssdp_is_hue
    and  x20, x20, x0
    ADRL x0, Lht_ssdp_v2
    bl   _ssdp_is_hue
    and  x20, x20, x0
    ADRL x0, Lht_ssdp_tv
    bl   _ssdp_is_hue
    eor  x0, x0, #1
    and  x20, x20, x0
    mov  w1, w20
    ADRL x0, Ln_hc190
    bl   _t_report
    add  x19, x19, x0

    mov  x0, x19
    LEAVE 256

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lhs_skip:
    .quad Lhs_w1, Lhs_w2, Lhs_w3, Lhs_w4, Lhs_w5, Lhs_w6, Lhs_w7, Lhs_w8, Lhs_w9, Lhs_w10
    .quad Lhs_w11, Lhs_w12, Lhs_w13, Lhs_w14, Lhs_w15, 0
Lht_bad_addrs:
    .quad Lht_b1, Lht_b2, Lht_b3, Lht_b4, Lht_b5, 0

.section __TEXT,__cstring,cstring_literals
Lhs_head:       .asciz "{\"deviceid\":["
Lhs_ipbridge:   .asciz "ipbridge"
Lhs_bridgeid:   .asciz "hue-bridgeid:"
Lhs_w1:         .asciz "light"
Lhs_w2:         .asciz "lights"
Lhs_w3:         .asciz "bulb"
Lhs_w4:         .asciz "bulbs"
Lhs_w5:         .asciz "lamp"
Lhs_w6:         .asciz "serial"
Lhs_w7:         .asciz "serials"
Lhs_w8:         .asciz "number"
Lhs_w9:         .asciz "code"
Lhs_w10:        .asciz "codes"
Lhs_w11:        .asciz "and"
Lhs_w12:        .asciz "by"
Lhs_w13:        .asciz "with"
Lhs_w14:        .asciz "the"
Lhs_w15:        .asciz "no"
Lht_in1:        .asciz "light by serial 1a2b3c, and #FFEE00"
Lht_out1:       .asciz "{\"deviceid\":[\"1A2B3C\",\"FFEE00\"]}"
Lht_in2:        .asciz " lights "
Lht_out2:       .asciz "{}"
Lht_in3:        .asciz "1a2b3c4"
Lht_in4:        .asciz "1a2b\"c"
Lht_empty:      .asciz ""
Lht_in10:       .asciz "000001 000002 000003 000004 000005 000006 000007 000008 000009 00000a"
Lht_in11:       .asciz "000001 000002 000003 000004 000005 000006 000007 000008 000009 00000a 00000b"
Lht_a1:         .asciz "192.168.1.20"
Lht_a2:         .asciz "Philips-hue.local"
Lht_b1:         .asciz ""
Lht_b2:         .asciz "192.168.1.20/api"
Lht_b3:         .asciz "evil.com@192.168.1.2"
Lht_b4:         .asciz "-x"
Lht_b5:         .asciz "a b"
Lht_ssdp_v1:    .asciz "HTTP/1.1 200 OK\r\nSERVER: FreeRTOS/6.0.5, UPnP/1.0, IpBridge/1.16.0\r\nST: upnp:rootdevice\r\n\r\n"
Lht_ssdp_v2:    .asciz "HTTP/1.1 200 OK\r\nSERVER: Hue/1.0 UPnP/1.0 IpBridge/1.60.0\r\nhue-bridgeid: 001788FFFE123456\r\n\r\n"
Lht_ssdp_tv:    .asciz "HTTP/1.1 200 OK\r\nSERVER: Roku/9.4.0 UPnP/1.0 Roku/9.4.0\r\nST: roku:ecp\r\n\r\n"
Ln_hc188:       .asciz "188 hue: serials read from what's typed, fillers skipped, bad words refused"
Ln_hc189:       .asciz "189 hue: at most ten serials; a small buffer refused"
Ln_hc190:       .asciz "190 hue: bridge addresses checked; a Hue bridge's SSDP answer, v1 and v2"
