// web.s — web pages and headlines over the mesh (Bluetooth and FM alike).
//
// A Mac with internet can switch on "Internet for the mesh" (SVC_GATE). It then:
//   * answers web requests: fetches the page (curl), turns it into plain text
//     with numbered links (fm_html.s), compresses it (zlib) and sends it back
//     as a run of small signed T_WEBPART packets
//   * posts headlines: every 15 minutes it reads an RSS feed and sends each new
//     headline once as a T_NEWS packet
//
// Everyone else has two local rooms:
//   Web   type an address or search words; a number follows a link; "back";
//         "links". The page arrives in pieces; missing pieces are asked for
//         again (with a bitmap) until the page is whole.
//   News  headlines from any gateway, each shown once.
//
// Packets (after the usual 12-byte header; sender at +20 as always):
//   T_WEBREQ   +12 gateway (0 = any)  +20 requester  +28 nlen  +29 nick, then
//              reqid u32, flags (1 sealed, 2 resend), then
//                a request:  seq u8, total u8, offset u16, a piece of the words
//                            (a long address travels in up to 8 packets)
//                a resend:   nparts u16 + a bitmap of the pieces still missing
//   T_WEBPART  +12 requester  +20 gateway  +28 0  +29 reqid u32  +33 part u16
//              +35 nparts u16  +37 flags (1 sealed)  +38 up to 120 bytes
//   T_NEWS     +12 0  +20 gateway  +28 nlen  +29 nick, then flags, the headline
// With a mesh passphrase the words, pieces and headlines are sealed with it.
//
// Several gateways may hear one request. Each waits a moment at random and
// stays quiet if another gateway's pieces for that request are already about;
// the asking Mac only takes pieces from the first gateway it hears.
//
// Safety on the gateway: an address from the mesh is fetched only if it is
// http(s) on the usual ports, names a public host (no localhost, .local, private
// or link-local addresses; the name is looked up here and curl is pinned to the
// checked address) and every redirect passes the same checks. curl never sees
// the address as an option (--url) and speaks http(s) only.

.include "macros.inc"

.set W_DATA,     120                 // bytes of page per piece
.set W_MAXN,     400                 // pieces per page at most
.set W_PACKCAP,  (W_DATA * W_MAXN)
.set W_TEXTCAP,  12000
.set W_OUTCAP,   64000
.set GSLOTS,     4                   // pages a gateway keeps for resends
.set GS_SHIFT,   7
.set G_REQ,      0
.set G_ID,       8
.set G_LEN,      16
.set G_N,        24
.set G_NEXT,     32
.set G_DATA,     40
.set G_USED,     48
.set G_MAP,      64                  // 64 bytes: pieces still to send
.set PSLOTS,     8                   // requests a gateway is collecting / about to answer
.set PS_SHIFT,   10
.set P_REQ,      0
.set P_ID,       8
.set P_DUE,      16                  // collecting: give up then; waiting: start then
.set P_LIVE,     24                  // 0 free, 1 collecting, 2 waiting, 3 fetching, 4 fetching but cancelled
.set P_GOT,      32                  // bitmap of request pieces here
.set P_TOT,      40
.set P_END,      48                  // length of the words (known once the last piece is in)
.set P_TARGET,   56                  // asked this Mac by name
.set P_TEXT,     64                  // WORDS_CAP bytes
.set J_KIND,     0                   // job for the fetch queue: 0 page, 1 headlines
.set J_REQ,      8
.set J_ID,       16
.set J_PACK,     24
.set J_PLEN,     32
.set J_LOCAL,    40
.set J_URL,      64                  // 512 bytes
.set J_SIZE,     576
.set LINKS_N,    150
.set LINK_SZ,    512
.set LINK_SHIFT, 9
.set WORDS_CAP,  512                 // longest request (an address from a link)
.set RQ_HDR,     9                   // reqid, flags, seq, total, offset
.set RQ_MAXN,    8                   // pieces per request at most
.set HIST_N,     8
.set NEWSQ_N,    40
.set NEWSQ_SZ,   160
.set NHASH_N,    256

.data
.p2align 3
_g_wr_state:    .quad 0              // 0 idle, 1 asked, 2 pieces arriving
_g_wr_id:       .quad 0
_g_wr_gw:       .quad 0
_g_wr_n:        .quad 0
_g_wr_got:      .quad 0
_g_wr_lastlen:  .quad 0
_g_wr_t0:       .quad 0
_g_wr_tlast:    .quad 0
_g_wr_tries:    .quad 0
_g_wr_nlinks:   .quad 0
_g_wr_nhist:    .quad 0
_g_wr_local:    .quad 0              // this Mac is fetching it itself (it is a gateway)
_g_web_tick_on: .quad 0
_g_web_queue:   .quad 0              // serial dispatch queue: one fetch at a time
_g_news_qn:     .quad 0
_g_news_next:   .quad 0
_g_news_due:    .quad 0              // next headline fetch (ms)
_g_news_hpos:   .quad 0
_g_news_busy:   .quad 0
_g_news_tnext:  .quad 0              // next headline may go out (ms)
_g_wport:       .quad 0              // fetch queue: port of the address being checked
.zerofill __DATA,__bss,_g_wr_have,64,4
.zerofill __DATA,__bss,_g_wr_data,W_PACKCAP,4
.zerofill __DATA,__bss,_g_wr_text,WORDS_CAP,4
.zerofill __DATA,__bss,_g_wr_links,(LINKS_N * LINK_SZ),4
.zerofill __DATA,__bss,_g_wr_hist,(HIST_N * LINK_SZ),4
.zerofill __DATA,__bss,_g_web_out,W_OUTCAP,4
.zerofill __DATA,__bss,_g_gslots,(GSLOTS * 128),4
.zerofill __DATA,__bss,_g_pslots,(PSLOTS << PS_SHIFT),4
.zerofill __DATA,__bss,_g_wpkt,256,4
.zerofill __DATA,__bss,_g_wline,1024,4
.zerofill __DATA,__bss,_g_news_q,(NEWSQ_N * NEWSQ_SZ),4
.zerofill __DATA,__bss,_g_news_hash,(NHASH_N * 8),4
.zerofill __DATA,__bss,_g_news_feed,256,4
.zerofill __DATA,__bss,_g_wtext,16384,4       // the fetch queue's text buffer
.zerofill __DATA,__bss,_g_wurl,512,4
.zerofill __DATA,__bss,_g_whost,256,4         // fetch queue: the host being checked
.zerofill __DATA,__bss,_g_wresolve,384,4      // fetch queue: "host:port:address" for curl
.zerofill __DATA,__bss,_g_wquad,32,4          // fetch queue: "a.b.c.d"
.zerofill __DATA,__bss,_g_wargv,256,4         // fetch queue: curl's arguments
.zerofill __DATA,__bss,_g_wpiece,256,4        // a request piece, opened

.text
.p2align 2

// ===========================================================================
// Small helpers
// ===========================================================================

// long _web_room(uint64 id) -> room index (or -1)
_web_room:
    b    _room_find

// void _web_say(uint64 room_id, const char *text) — a system line in Web or News
_web_say:
    ENTER 0
    mov  x19, x1
    bl   _room_find
    tbnz x0, #63, 1f
    mov  x1, x19
    mov  w2, #1
    bl   _room_line
1:  LEAVE 0

// void _web_append(uint64 room_id, const char *utf8) — any length, no time stamp
_web_append:
    ENTER 16
    mov  x20, x1
    bl   _room_find
    tbnz x0, #63, 9f
    mov  x19, x0
    ADRL x8, _g_rooms
    add  x21, x8, x19, lsl #ROOM_SHIFT
    ldr  x22, [x21, #R_STORE]
    cbz  x22, 9f
    mov  x0, x20
    bl   _nsstr
    mov  x23, x0
    CLS  Ls_NSAttributedString
    MSG0 Ls_alloc
    mov  x24, x0
    SELX1 Ls_initWithStringAttrs
    mov  x0, x24
    mov  x2, x23
    ADRL x8, _g_attr_msg
    ldr  x3, [x8]
    bl   _objc_msgSend
    mov  x24, x0
    mov  x0, x22
    mov  x2, x24
    MSG1 Ls_appendAttributedString
    mov  x0, x24
    MSG0 Ls_release
    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne 1f
    ADRL x8, _g_chatview
    ldr  x0, [x8]
    cbz  x0, 9f
    mov  x2, #0
    MSG1 Ls_scrollToEndOfDocument
    b    9f
1:  ldr  x9, [x21, #R_UNREAD]
    add  x9, x9, #1
    str  x9, [x21, #R_UNREAD]
    bl   _ui_rooms_changed
9:  LEAVE 16

// PATH for curl/rtl_fm, and the environment handed to them
_web_env:
    ENTER 0
    ADRL x8, _fm_envp
    ldr  x9, [x8]
    cbnz x9, 1f
    ADRL x0, Ls_PATH
    ADRL x1, Ls_pathval
    mov  w2, #1
    bl   _setenv
    bl   __NSGetEnviron
    ldr  x0, [x0]
    ADRL x8, _fm_envp
    str  x0, [x8]
1:  LEAVE 0

// long _web_pace(void) -> ms between pieces (FM airtime when the radio is on)
_web_pace:
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbz  x9, 1f
    ADRL x8, _g_fm_baud
    ldr  x9, [x8]
    mov  x10, #0x4C00                // 1,920,000 = one full packet in bit-ms
    movk x10, #0x1D, lsl #16
    udiv x0, x10, x9
    add  x0, x0, #450
    ret
1:  mov  x0, #60
    ret

// uint64 _web_hash(const char *s) — FNV-1a
_web_hash:
    mov  x9, #0x2325
    movk x9, #0x8422, lsl #16
    movk x9, #0x9ce4, lsl #32
    movk x9, #0xcbf2, lsl #48
    mov  x10, #0x01b3
    movk x10, #0x100, lsl #32
1:  ldrb w11, [x0], #1
    cbz  w11, 2f
    eor  x9, x9, x11
    mul  x9, x9, x10
    b    1b
2:  mov  x0, x9
    ret

// build the address a gateway fetches: x0 = words, x1 = out[512]
.globl _web_make_url
_web_make_url:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    mov  w1, #' '
    bl   _strchr
    cbnz x0, 2f                      // words with spaces: a search
    mov  x0, x19
    mov  w1, #'.'
    bl   _strchr
    cbz  x0, 2f                      // one word, no dot: a search
    mov  x0, x19
    ADRL x1, Ls_scheme
    bl   _strstr
    cbnz x0, 1f
    mov  x0, x20
    ADRL x1, Ls_https
    mov  x2, #512
    bl   _strlcpy
    mov  x0, x20
    mov  x1, x19
    mov  x2, #512
    bl   _strlcat
    LEAVE 0
1:  mov  x0, x20
    mov  x1, x19
    mov  x2, #512
    bl   _strlcpy
    LEAVE 0
2:  mov  x0, x20
    ADRL x1, Ls_search
    mov  x2, #512
    bl   _strlcpy
    mov  x21, x0
    mov  x0, x19
    add  x1, x20, x21
    mov  x2, #512
    sub  x2, x2, x21
    bl   _fm_urlencode
    LEAVE 0

// ===========================================================================
// The Web room (asking side)
// ===========================================================================

// void _web_command(const char *text) — typed in the Web room
.globl _web_command
_web_command:
    ENTER 16
    mov  x19, x0
1:  ldrb w9, [x19]                   // trim leading spaces
    cmp  w9, #' '
    b.ne 2f
    add  x19, x19, #1
    b    1b
2:  cbz  w9, 9f
    mov  x0, x19
    ADRL x1, Ls_back
    bl   _strcasecmp
    cbz  w0, Lwc_back
    mov  x0, x19
    ADRL x1, Ls_links
    bl   _strcasecmp
    cbz  w0, Lwc_links
    // a link number?
    mov  x20, #0
    mov  x21, #0
3:  ldrb w9, [x19, x21]
    cbz  w9, 4f
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi Lwc_words
    mov  x10, #10
    madd x20, x20, x10, x9
    add  x21, x21, #1
    cmp  x21, #4
    b.hi Lwc_words
    b    3b
4:  cbz  x21, Lwc_words
    ADRL x8, _g_wr_nlinks
    ldr  x9, [x8]
    cbz  x20, 5f
    cmp  x20, x9
    b.hi 5f
    sub  x20, x20, #1
    ADRL x8, _g_wr_links
    add  x0, x8, x20, lsl #LINK_SHIFT
    mov  w1, #1
    bl   _web_ask
    b    9f
5:  mov  x0, #WEB_ID
    ADRL x1, Ls_nolink
    bl   _web_say
    b    9f
Lwc_words:
    mov  x0, x19
    mov  w1, #1
    bl   _web_ask
    b    9f
Lwc_back:
    ADRL x8, _g_wr_nhist
    ldr  x9, [x8]
    cmp  x9, #2
    b.hs 6f
    mov  x0, #WEB_ID
    ADRL x1, Ls_noback
    bl   _web_say
    b    9f
6:  sub  x9, x9, #2                  // drop the current page; ask for the one before
    str  x9, [x8]
    ADRL x8, _g_wr_hist
    add  x1, x8, x9, lsl #LINK_SHIFT
    ADRL x0, _g_wurl
    mov  x2, #512
    bl   _strlcpy
    ADRL x0, _g_wurl
    mov  w1, #1
    bl   _web_ask
    b    9f
Lwc_links:
    bl   _web_list_links
9:  LEAVE 16

// void _web_ask(const char *words, int remember) — a new page request
_web_ask:
    ENTER 16
    mov  x19, x0
    mov  w20, w1
    ADRL x0, _g_wr_text
    mov  x1, x19
    mov  x2, #WORDS_CAP
    bl   _strlcpy
    cbz  w20, 1f                     // remember it for "back"
    ADRL x8, _g_wr_nhist
    ldr  x9, [x8]
    cmp  x9, #HIST_N
    b.lo 0f
    ADRL x0, _g_wr_hist              // full: slide everything down one
    add  x1, x0, #LINK_SZ
    mov  x2, #((HIST_N - 1) * LINK_SZ)
    bl   _memmove
    ADRL x8, _g_wr_nhist
    mov  x9, #(HIST_N - 1)
    str  x9, [x8]
0:  ADRL x8, _g_wr_hist
    add  x0, x8, x9, lsl #LINK_SHIFT
    mov  x1, x19
    mov  x2, #LINK_SZ
    bl   _strlcpy
    ADRL x8, _g_wr_nhist
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
1:  bl   _fm_rand                    // a fresh request
    cmp  w0, #0
    csinc w0, w0, wzr, ne
    ADRL x8, _g_wr_id
    str  x0, [x8]
    ADRL x8, _g_wr_gw
    str  xzr, [x8]
    ADRL x8, _g_wr_n
    str  xzr, [x8]
    ADRL x8, _g_wr_got
    str  xzr, [x8]
    ADRL x8, _g_wr_tries
    str  xzr, [x8]
    ADRL x0, _g_wr_have
    mov  x1, #0
    mov  x2, #64
    bl   _memset
    bl   _fm_now_ms
    ADRL x8, _g_wr_t0
    str  x0, [x8]
    ADRL x8, _g_wr_tlast
    str  x0, [x8]
    ADRL x8, _g_wr_state
    mov  x9, #1
    str  x9, [x8]
    ADRL x8, _g_wr_text
    str  x8, [sp]
    ADRL x0, _g_wline
    mov  x1, #1024
    ADRL x2, Lf_asking
    bl   _snprintf
    mov  x0, #WEB_ID
    ADRL x1, _g_wline
    bl   _web_say
    mov  x0, #SVC_GATE               // this Mac is a gateway itself: no radio needed
    bl   _svc_on
    cbz  x0, 2f
    ADRL x8, _g_node_id
    ldr  x0, [x8]
    ADRL x8, _g_wr_id
    ldr  x1, [x8]
    ADRL x2, _g_wr_text
    mov  w3, #1
    bl   _web_job_page
    ADRL x8, _g_wr_local
    mov  x9, #1
    str  x9, [x8]
    cbnz x0, 3f
    ADRL x8, _g_wr_state
    str  xzr, [x8]
    mov  x0, #WEB_ID
    ADRL x1, Ls_nomem
    bl   _web_say
    b    3f
2:  ADRL x8, _g_wr_local
    str  xzr, [x8]
    mov  w0, #0
    bl   _web_send_req
3:  bl   _web_tick_arm
    LEAVE 16

// void _web_send_req(int mode) — mode bit 0: ask for the missing pieces;
//   bit 1: quiet (a repeat; don't report "nobody to ask" again)
_web_send_req:
    ENTER 32
    mov  w21, w0
    tbnz w21, #0, Lsr_resend
    // how many bytes of the words fit in one packet
    ADRL x8, _g_nick_len
    ldr  x9, [x8]
    mov  x23, #(PKT_MAX - TRAILER - 29 - RQ_HDR)
    sub  x23, x23, x9
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, 1f
    sub  x23, x23, #8                // the seal's tag
1:  ADRL x0, _g_wr_text
    bl   _strlen
    mov  x24, x0
    cbz  x24, 9f
    add  x9, x24, x23
    sub  x9, x9, #1
    udiv x9, x9, x23                 // pieces
    cmp  x9, #RQ_MAXN
    b.ls 2f
    mov  x9, #RQ_MAXN                // (cannot happen with WORDS_CAP; kept as a bound)
    mul  x24, x9, x23
2:  str  x9, [sp, #96]               // total
    str  xzr, [sp, #104]             // seq
    str  xzr, [sp, #112]             // Macs reached
    str  xzr, [sp, #120]             // a packet could not be signed
3:  ldr  x9, [sp, #104]
    ldr  x10, [sp, #96]
    cmp  x9, x10
    b.hs 8f
    mov  w0, #0
    bl   Lreq_head
    mov  x20, x0                     // body
    ldr  x9, [sp, #104]
    strb w9, [x20, #5]               // seq
    ldr  x10, [sp, #96]
    strb w10, [x20, #6]              // total
    mul  x11, x9, x23                // offset
    strh w11, [x20, #7]
    sub  x22, x24, x11               // this piece's length
    cmp  x22, x23
    csel x22, x23, x22, hi
    add  x0, x20, #RQ_HDR
    ADRL x1, _g_wr_text
    add  x1, x1, x11
    mov  x2, x22
    bl   _memcpy
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, 4f
    add  x0, x20, #RQ_HDR
    mov  x1, x22
    ADRL x2, _g_wpkt
    add  x2, x2, #4
    bl   _crypto_seal
    mov  x22, x0
    ldrb w9, [x20, #4]
    orr  w9, w9, #1
    strb w9, [x20, #4]
4:  add  x1, x20, #RQ_HDR
    add  x1, x1, x22
    bl   Lreq_send
    ldr  x9, [sp, #104]
    add  x9, x9, #1
    str  x9, [sp, #104]
    b    3b

Lsr_resend:                          // how many pieces, and a bitmap of the ones still missing
    mov  w0, #1
    bl   Lreq_head
    mov  x20, x0
    ADRL x8, _g_wr_n
    ldr  x23, [x8]
    strh w23, [x20, #5]
    add  x22, x20, #7
    add  x24, x23, #7
    lsr  x24, x24, #3                // bitmap bytes
    mov  x9, #0
5:  cmp  x9, x24
    b.hs 6f
    ADRL x8, _g_wr_have
    ldrb w10, [x8, x9]
    mvn  w10, w10
    lsl  x11, x9, #3                 // only pieces that exist
    sub  x11, x23, x11
    cmp  x11, #8
    b.hs 51f
    mov  w12, #1
    lsl  w12, w12, w11
    sub  w12, w12, #1
    and  w10, w10, w12
51: strb w10, [x22, x9]
    add  x9, x9, #1
    b    5b
6:  add  x1, x22, x24
    str  xzr, [sp, #112]
    str  xzr, [sp, #120]
    bl   Lreq_send
8:  tbnz w21, #1, 9f                 // quiet
    ldr  x9, [sp, #120]
    cbz  x9, 81f
    mov  x0, #WEB_ID
    ADRL x1, Ls_nosign
    bl   _web_say
    b    9f
81: ldr  x9, [sp, #112]
    cbnz x9, 9f
    mov  x0, #WEB_ID                 // nobody to hand it to
    ADRL x1, Ls_nobody
    bl   _web_say
9:  LEAVE 32

// the header every T_WEBREQ starts with, in _g_wpkt. w0: 1 = a resend (to the
// gateway that answered, flag 2). -> x0 = body (reqid at +0, flags at +4)
Lreq_head:
    ENTER 0
    mov  w21, w0
    ADRL x0, _g_wpkt
    mov  w1, #T_WEBREQ
    bl   _pkt_begin
    ADRL x19, _g_wpkt
    ADRL x8, _g_wr_gw
    ldr  x9, [x8]
    cmp  w21, #0
    csel x9, xzr, x9, eq
    str  x9, [x19, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x19, #20]
    add  x0, x19, #28
    bl   _put_nick
    mov  x20, x0
    ADRL x8, _g_wr_id
    ldr  x9, [x8]
    str  w9, [x20]
    mov  w9, #0
    cbz  w21, 1f
    mov  w9, #2
1:  strb w9, [x20, #4]
    mov  x0, x20
    LEAVE 0

// sign and send _g_wpkt: x1 = end of body. Only called from _web_send_req, whose
// locals it updates: [sp,#112] most Macs reached, [sp,#120] set if unsigned.
Lreq_send:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    ADRL x0, _g_wpkt
    sub  x1, x1, x0
    bl   _pkt_finish
    cbnz x0, 1f
    mov  x9, #1                      // the caller's sp is our x29 + 16
    str  x9, [x29, #(16 + 120)]
    b    2f
1:  mov  x1, x0
    ADRL x0, _g_wpkt
    bl   _ble_broadcast
    ldr  x9, [x29, #(16 + 112)]
    cmp  x0, x9
    csel x9, x0, x9, hi
    str  x9, [x29, #(16 + 112)]
2:  ldp  x29, x30, [sp], #16
    ret

// a piece of the page we asked for (from the mesh or from ourselves)
// x0 gateway, x1 reqid, x2 part, x3 nparts, x4 data, x5 len
.globl _web_accept_part
_web_accept_part:
    ENTER 32
    mov  x19, x0
    mov  x20, x2
    mov  x21, x3
    mov  x22, x4
    mov  x23, x5
    ADRL x8, _g_wr_state
    ldr  x9, [x8]
    cbz  x9, 9f
    ADRL x8, _g_wr_id
    ldr  w9, [x8]
    cmp  w1, w9
    b.ne 9f
    cbz  x21, 9f
    cmp  x21, #W_MAXN
    b.hi 9f
    cmp  x20, x21
    b.hs 9f
    cmp  x23, #W_DATA
    b.hi 9f
    ADRL x8, _g_wr_gw                // only from the first gateway that answers
    ldr  x9, [x8]
    cbz  x9, 1f
    cmp  x9, x19
    b.ne 9f
    b    2f
1:  str  x19, [x8]
    ADRL x8, _g_wr_n
    str  x21, [x8]
    ADRL x8, _g_wr_state
    mov  x9, #2
    str  x9, [x8]
    ADRL x8, _g_wr_tries             // count resends afresh
    str  xzr, [x8]
2:  ADRL x8, _g_wr_n
    ldr  x9, [x8]
    cmp  x9, x21
    b.ne 9f
    lsr  x9, x20, #3                 // already have it?
    and  x10, x20, #7
    ADRL x8, _g_wr_have
    ldrb w11, [x8, x9]
    lsr  w12, w11, w10
    tbnz w12, #0, 9f
    sub  x13, x21, #1                // every piece but the last is full
    cmp  x20, x13
    b.eq 3f
    cmp  x23, #W_DATA
    b.ne 9f
    b    4f
3:  ADRL x8, _g_wr_lastlen
    str  x23, [x8]
4:  mov  w12, #1
    lsl  w12, w12, w10
    orr  w11, w11, w12
    ADRL x8, _g_wr_have
    strb w11, [x8, x9]
    ADRL x8, _g_wr_data
    mov  x9, #W_DATA
    madd x0, x20, x9, x8
    mov  x1, x22
    mov  x2, x23
    bl   _memcpy
    bl   _fm_now_ms
    ADRL x8, _g_wr_tlast
    str  x0, [x8]
    ADRL x8, _g_wr_got
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    cmp  x9, x21
    b.ne 5f
    bl   _web_complete
    b    9f
5:  // progress every 10 pieces
    mov  x10, #10
    udiv x11, x9, x10
    msub x11, x11, x10, x9
    cbnz x11, 9f
    str  x9, [sp]
    str  x21, [sp, #8]
    ADRL x0, _g_wline
    mov  x1, #1024
    ADRL x2, Lf_progress
    bl   _snprintf
    mov  x0, #WEB_ID
    ADRL x1, _g_wline
    bl   _web_say
9:  LEAVE 32

// every piece is here: unpack and show the page
_web_complete:
    ENTER 32
    ADRL x8, _g_wr_state
    str  xzr, [x8]
    ADRL x8, _g_wr_n
    ldr  x9, [x8]
    sub  x9, x9, #1
    mov  x10, #W_DATA
    mul  x9, x9, x10
    ADRL x8, _g_wr_lastlen
    ldr  x10, [x8]
    add  x1, x9, x10                 // packed length
    ADRL x0, _g_wr_data
    ADRL x2, _g_web_out
    MOVI x3, W_OUTCAP
    bl   _fm_unpack
    tbnz x0, #63, 8f
    mov  x19, x0
    ADRL x0, _g_web_out
    mov  x1, x19
    bl   _web_show_page
    LEAVE 32
8:  mov  x0, #WEB_ID
    ADRL x1, Ls_badpage
    bl   _web_say
    LEAVE 32

// show "text \x01 link\nlink\n…" in the Web room and keep the links
.globl _web_show_page
_web_show_page:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    strb wzr, [x19, x20]
    mov  x0, x19                     // split off the links
    mov  w1, #1
    bl   _strchr
    mov  x21, x0
    cbz  x21, 1f
    strb wzr, [x21]
    add  x21, x21, #1
1:  ADRL x8, _g_wr_gw                // who sent it
    ldr  x0, [x8]
    bl   _node_find
    ADRL x9, Ls_thismac
    tbnz x0, #63, 2f
    ADRL x8, _g_nodes
    add  x0, x8, x0, lsl #NODE_SHIFT
    bl   _node_name
    mov  x9, x0
2:  str  x9, [sp]
    ADRL x8, _g_wr_n
    ldr  x9, [x8]
    str  x9, [sp, #8]
    ADRL x0, _g_wline
    mov  x1, #1024
    ADRL x2, Lf_page_from
    bl   _snprintf
    mov  x0, #WEB_ID
    ADRL x1, _g_wline
    bl   _web_say
    mov  x0, #WEB_ID
    mov  x1, x19
    bl   _web_append
    mov  x0, #WEB_ID
    ADRL x1, Ls_nl2
    bl   _web_append
    // links, one per line, into the table
    ADRL x8, _g_wr_nlinks
    str  xzr, [x8]
    cbz  x21, 9f
3:  ldrb w9, [x21]
    cbz  w9, 9f
    mov  x0, x21
    mov  w1, #'\n'
    bl   _strchr
    mov  x22, x0
    cbz  x22, 4f
    strb wzr, [x22]
4:  ADRL x8, _g_wr_nlinks
    ldr  x9, [x8]
    cmp  x9, #LINKS_N
    b.hs 9f
    ADRL x10, _g_wr_links
    add  x0, x10, x9, lsl #LINK_SHIFT
    add  x9, x9, #1
    str  x9, [x8]
    mov  x1, x21
    mov  x2, #LINK_SZ
    bl   _strlcpy
    cbz  x22, 9f
    add  x21, x22, #1
    b    3b
9:  LEAVE 32

// "links": list them in the room
_web_list_links:
    ENTER 32
    ADRL x8, _g_wr_nlinks
    ldr  x19, [x8]
    cbnz x19, 1f
    mov  x0, #WEB_ID
    ADRL x1, Ls_nolinks
    bl   _web_say
    LEAVE 32
1:  mov  x20, #0
2:  cmp  x20, x19
    b.hs 3f
    add  x9, x20, #1
    str  x9, [sp]
    ADRL x8, _g_wr_links
    add  x9, x8, x20, lsl #LINK_SHIFT
    str  x9, [sp, #8]
    ADRL x0, _g_wline
    mov  x1, #1024
    ADRL x2, Lf_link
    bl   _snprintf
    mov  x0, #WEB_ID
    ADRL x1, _g_wline
    bl   _web_append
    add  x20, x20, #1
    b    2b
3:  LEAVE 32

// ===========================================================================
// Packets in (from _mesh_receive, after the signature checked out)
// ===========================================================================

// long _web_rx(const uint8 *pkt, size_t bodylen, long hops) -> 1 if the packet
//   was meant for this Mac alone (the mesh need not pass it on), else 0
.globl _web_rx
_web_rx:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    str  xzr, [sp, #96]              // result
    ldr  x9, [x19, #20]              // our own, come back round
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.eq Lwr_done
    ldrb w9, [x19, #3]
    cmp  w9, #T_WEBPART
    b.eq Lwr_part
    cmp  w9, #T_WEBREQ
    b.eq Lwr_req
    cmp  w9, #T_NEWS
    b.eq Lwr_news
    b    Lwr_done

Lwr_part:
    cmp  x20, #38
    b.lo Lwr_done
    ldr  w21, [x19, #29]             // reqid
    // a gateway about to answer this same request stays quiet
    ldr  x0, [x19, #12]
    mov  x1, x21
    ldr  x2, [x19, #20]
    bl   _gw_heard_other
    ldr  x9, [x19, #12]              // for us?
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne Lwr_done
    mov  x9, #1
    str  x9, [sp, #96]
    ldrh w22, [x19, #33]             // part
    ldrh w23, [x19, #35]             // nparts
    sub  x24, x20, #38               // data length
    ldrb w9, [x19, #37]
    tbz  w9, #0, 1f
    add  x0, x19, #38                // sealed with the mesh passphrase
    mov  x1, x24
    add  x2, x19, #4
    ADRL x3, _g_wpiece
    bl   _crypto_open
    tbnz x0, #63, Lwr_locked
    mov  x24, x0
    ADRL x4, _g_wpiece
    b    2f
1:  add  x4, x19, #38
2:  ldr  x0, [x19, #20]
    mov  x1, x21
    mov  x2, x22
    mov  x3, x23
    mov  x5, x24
    bl   _web_accept_part
    b    Lwr_done
Lwr_locked:
    ADRL x8, _g_wr_state             // say it once per request
    ldr  x9, [x8]
    cbz  x9, Lwr_done
    ADRL x8, _g_wr_id
    ldr  w9, [x8]
    cmp  w9, w21
    b.ne Lwr_done
    ADRL x8, _g_wr_state
    str  xzr, [x8]
    mov  x0, #WEB_ID
    ADRL x1, Ls_locked
    bl   _web_say
    b    Lwr_done

Lwr_req:
    ldr  x9, [x19, #12]              // for any gateway, or for us by name
    cbz  x9, 1f
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne Lwr_done
    mov  x9, #1
    str  x9, [sp, #96]
1:  mov  x0, #SVC_GATE               // only gateways answer
    bl   _svc_on
    cbz  x0, Lwr_done
    ldrb w9, [x19, #28]
    add  x21, x9, #29                // body start
    add  x9, x21, #5
    cmp  x9, x20
    b.hi Lwr_done
    add  x22, x19, x21
    ldr  w23, [x22]                  // reqid
    ldrb w24, [x22, #4]              // flags
    tbnz w24, #1, Lwr_resend
    add  x9, x21, #RQ_HDR
    cmp  x9, x20
    b.hs Lwr_done                    // no words
    sub  x1, x20, x9                 // this piece's bytes
    tbz  w24, #0, 2f
    add  x0, x22, #RQ_HDR            // sealed: open it
    add  x2, x19, #4
    ADRL x3, _g_wpiece
    bl   _crypto_open
    tbnz x0, #63, Lwr_done           // not our passphrase: can't read it, can't answer
    mov  x1, x0
    ADRL x4, _g_wpiece
    b    3f
2:  add  x4, x22, #RQ_HDR
3:  mov  x3, x4                      // data
    mov  x4, x1                      // len
    ldrb w5, [x22, #5]               // seq
    ldrb w6, [x22, #6]               // total
    ldrh w7, [x22, #7]               // offset
    ldr  x0, [x19, #20]              // requester
    mov  x1, x23
    ldr  x2, [x19, #12]              // asked us by name: answer at once
    bl   _gw_piece_add
    b    Lwr_done
Lwr_resend:
    add  x9, x21, #7
    cmp  x9, x20
    b.hi Lwr_done
    ldrh w9, [x22, #5]               // nparts
    ldr  x0, [x19, #20]
    mov  x1, x23
    add  x2, x22, #7                 // bitmap
    sub  x3, x20, x21
    sub  x3, x3, #7                  // bitmap bytes
    mov  x4, x9
    bl   _gw_resend
    b    Lwr_done

Lwr_news:
    ldrb w9, [x19, #28]
    add  x21, x9, #29
    add  x9, x21, #1
    cmp  x9, x20
    b.hs Lwr_done
    add  x22, x19, x21
    ldrb w24, [x22]
    sub  x1, x20, x21
    sub  x1, x1, #1
    tbz  w24, #0, 1f
    add  x0, x22, #1
    add  x2, x19, #4
    ADRL x3, _g_wline
    bl   _crypto_open
    tbnz x0, #63, Lwr_done
    ADRL x8, _g_wline
    strb wzr, [x8, x0]
    b    2f
1:  cmp  x1, #200
    mov  x9, #200
    csel x1, x9, x1, hi
    mov  x23, x1
    ADRL x0, _g_wline
    add  x1, x22, #1
    mov  x2, x23
    bl   _memcpy
    ADRL x8, _g_wline
    strb wzr, [x8, x23]
2:  add  x0, x19, #29                // the gateway's name
    ldrb w1, [x19, #28]
    ADRL x2, _g_wurl
    bl   Lnick_copy
    ADRL x0, _g_wline
    ADRL x1, _g_wurl
    bl   _news_show
Lwr_done:
    ldr  x0, [sp, #96]
    LEAVE 32

// local: copy a length-prefixed nick: x0 bytes, w1 len, x2 out (<= 24)
Lnick_copy:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x2
    and  x20, x1, #0xFF
    cmp  x20, #NICK_MAX
    mov  x9, #NICK_MAX
    csel x20, x9, x20, hi
    mov  x1, x0
    mov  x0, x19
    mov  x2, x20
    bl   _memcpy
    strb wzr, [x19, x20]
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// ===========================================================================
// Gateway side
// ===========================================================================

// void _web_gate_start(void) — the service was switched on
.globl _web_gate_start
_web_gate_start:
    ENTER 0
    bl   _web_env
    bl   _fm_now_ms
    MOVI x9, 15000                   // first headlines 15 s after starting
    add  x0, x0, x9
    ADRL x8, _g_news_due
    str  x0, [x8]
    ADRL x0, Ls_gate_on
    bl   _chat_line
    bl   _web_tick_arm
    LEAVE 0

// a piece of a request reached this gateway:
//   x0 requester, w1 reqid, x2 target (us, or 0 = any gateway), x3 data, x4 len,
//   x5 seq, x6 total, x7 offset
.globl _gw_piece_add
_gw_piece_add:
    ENTER 32
    mov  x19, x0
    mov  w20, w1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    stp  x5, x6, [sp, #96]
    str  x7, [sp, #112]
    cbz  x6, 9f                      // a sane piece?
    cmp  x6, #RQ_MAXN
    b.hi 9f
    cmp  x5, x6
    b.hs 9f
    add  x9, x7, x4
    cmp  x9, #(WORDS_CAP - 1)
    b.hi 9f
    // already sending this page: the request came again because nothing
    // arrived, so send every piece again
    ADRL x8, _g_gslots
    mov  x9, #0
1:  cmp  x9, #GSLOTS
    b.hs 3f
    add  x10, x8, x9, lsl #GS_SHIFT
    ldr  x11, [x10, #G_DATA]
    cbz  x11, 2f
    ldr  x11, [x10, #G_REQ]
    ldr  w12, [x10, #G_ID]
    cmp  x11, x19
    ccmp w12, w20, #0, eq
    b.ne 2f
    ldr  x11, [sp, #96]
    cbnz x11, 9f                     // once per repeat: on its first piece
    add  x0, x10, #G_MAP
    mov  w1, #0xFF
    mov  x2, #64
    bl   _memset
    bl   _web_tick_arm
    b    9f
2:  add  x9, x9, #1
    b    1b
3:  // collecting it already?
    ADRL x8, _g_pslots
    mov  x9, #0
4:  cmp  x9, #PSLOTS
    b.hs 5f
    add  x24, x8, x9, lsl #PS_SHIFT
    ldr  x10, [x24, #P_LIVE]
    cbz  x10, 41f
    ldr  x11, [x24, #P_REQ]
    ldr  w12, [x24, #P_ID]
    cmp  x11, x19
    ccmp w12, w20, #0, eq
    b.ne 41f
    cmp  x10, #1
    b.ne 9f                          // complete already: waiting or fetching
    b    7f
41: add  x9, x9, #1
    b    4b
5:  mov  x9, #0                      // a free slot
6:  cmp  x9, #PSLOTS
    b.hs 9f                          // all busy: the asking Mac will ask again
    add  x24, x8, x9, lsl #PS_SHIFT
    ldr  x10, [x24, #P_LIVE]
    cbz  x10, 61f
    add  x9, x9, #1
    b    6b
61: str  x19, [x24, #P_REQ]
    str  x20, [x24, #P_ID]
    str  xzr, [x24, #P_GOT]
    ldr  x10, [sp, #104]
    str  x10, [x24, #P_TOT]
    str  xzr, [x24, #P_END]
    str  x21, [x24, #P_TARGET]
    add  x0, x24, #P_TEXT
    mov  w1, #0
    mov  x2, #WORDS_CAP
    bl   _memset
    bl   _fm_now_ms                  // the rest must arrive within 30 s
    MOVI x9, 30000
    add  x0, x0, x9
    str  x0, [x24, #P_DUE]
    mov  x9, #1
    str  x9, [x24, #P_LIVE]
    bl   _web_tick_arm
7:  ldr  x9, [x24, #P_TOT]           // add the piece
    ldr  x10, [sp, #104]
    cmp  x9, x10
    b.ne 9f
    add  x0, x24, #P_TEXT
    ldr  x9, [sp, #112]
    add  x0, x0, x9
    mov  x1, x22
    mov  x2, x23
    bl   _memcpy
    ldr  x9, [sp, #96]               // seq
    mov  x10, #1
    lsl  x10, x10, x9
    ldr  x11, [x24, #P_GOT]
    orr  x11, x11, x10
    str  x11, [x24, #P_GOT]
    ldr  x10, [sp, #104]             // the last piece tells the length
    sub  x10, x10, #1
    cmp  x9, x10
    b.ne 8f
    ldr  x12, [sp, #112]
    add  x12, x12, x23
    str  x12, [x24, #P_END]
8:  ldr  x10, [x24, #P_TOT]          // all here?
    mov  x12, #1
    lsl  x12, x12, x10
    sub  x12, x12, #1
    cmp  x11, x12
    b.ne 9f
    ldr  x9, [x24, #P_END]
    add  x10, x24, #P_TEXT
    strb wzr, [x10, x9]
    mov  x9, #2
    str  x9, [x24, #P_LIVE]
    mov  x21, #0                     // asked by name: no wait
    ldr  x9, [x24, #P_TARGET]
    cbnz x9, 81f
    bl   _fm_rand                    // else up to 1.5 s, so one gateway usually goes first
    mov  w9, #1500
    udiv w10, w0, w9
    msub w21, w10, w9, w0
81: bl   _fm_now_ms
    add  x0, x0, x21
    str  x0, [x24, #P_DUE]
    bl   _web_tick_arm
9:  LEAVE 32

// another gateway's piece for (requester, reqid) went by: stand down
// x0 requester, x1 reqid, x2 that gateway
_gw_heard_other:
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x2, x8
    b.eq 3f
    ADRL x8, _g_pslots
    mov  x9, #0
1:  cmp  x9, #PSLOTS
    b.hs 3f
    add  x10, x8, x9, lsl #PS_SHIFT
    ldr  x13, [x10, #P_LIVE]
    cbz  x13, 2f
    ldr  x11, [x10, #P_REQ]
    ldr  w12, [x10, #P_ID]
    cmp  x11, x0
    ccmp w12, w1, #0, eq
    b.ne 2f
    mov  x11, #4                     // fetching: finish, but don't send
    cmp  x13, #3
    csel x11, x11, xzr, hs
    str  x11, [x10, #P_LIVE]
2:  add  x9, x9, #1
    b    1b
3:  ret

// void _gw_resend(uint64 requester, u32 reqid, const uint8 *bitmap, size_t bytes, long nparts)
_gw_resend:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ADRL x23, _g_gslots
    mov  x24, #0
1:  cmp  x24, #GSLOTS
    b.hs 9f
    add  x9, x23, x24, lsl #GS_SHIFT
    ldr  x10, [x9, #G_REQ]
    ldr  w11, [x9, #G_ID]
    cmp  x10, x19
    ccmp w11, w20, #0, eq
    b.eq 2f
    add  x24, x24, #1
    b    1b
2:  add  x23, x9, #G_MAP
    ldr  x10, [x9, #G_N]
    add  x10, x10, #7
    lsr  x10, x10, #3
    cmp  x22, x10
    csel x22, x10, x22, hi
    mov  x10, #0
3:  cmp  x10, x22
    b.hs 4f
    ldrb w11, [x21, x10]
    ldrb w12, [x23, x10]
    orr  w12, w12, w11
    strb w12, [x23, x10]
    add  x10, x10, #1
    b    3b
4:  bl   _web_tick_arm
9:  LEAVE 0

// start fetching a page: x0 requester, x1 reqid, x2 words, w3 local (this Mac asked)
//   -> 1 queued, 0 not (out of memory)
_web_job_page:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  w22, w3
    bl   _web_env
    mov  x0, #J_SIZE
    bl   _malloc
    cbz  x0, 9f
    mov  x23, x0
    str  xzr, [x23, #J_KIND]
    str  x19, [x23, #J_REQ]
    str  x20, [x23, #J_ID]
    str  xzr, [x23, #J_PACK]
    str  xzr, [x23, #J_PLEN]
    str  x22, [x23, #J_LOCAL]
    mov  x0, x21
    add  x1, x23, #J_URL
    bl   _web_make_url
    bl   _web_queue
    cbz  x0, 8f
    mov  x1, x23
    ADRL x2, _web_work
    bl   _dispatch_async_f
    mov  x0, #1
    LEAVE 0
8:  mov  x0, x23
    bl   _free
    mov  x0, #0
9:  LEAVE 0

// the serial fetch queue
_web_queue:
    ENTER 0
    ADRL x8, _g_web_queue
    ldr  x0, [x8]
    cbnz x0, 1f
    ADRL x0, Ls_qname
    mov  x1, #0
    bl   _dispatch_queue_create
    ADRL x8, _g_web_queue
    str  x0, [x8]
1:  LEAVE 0

// ---------------------------------------------------------------------------
// Fetching (on the serial fetch queue only: the buffers here are its own)
// ---------------------------------------------------------------------------

// long _web_ip_public(u32 ip, host order) -> 1 if it is an ordinary internet
//   address, 0 for loopback, private, link-local, shared, test and multicast ones
.globl _web_ip_public
_web_ip_public:
    lsr  w9, w0, #24                 // a
    ubfx w10, w0, #16, #8            // b
    cbz  w9, 8f                      // 0/8
    cmp  w9, #10
    b.eq 8f                          // 10/8
    cmp  w9, #127
    b.eq 8f                          // 127/8
    cmp  w9, #224
    b.hs 8f                          // multicast and reserved
    cmp  w9, #100                    // 100.64/10 (carrier-grade NAT)
    b.ne 1f
    and  w11, w10, #0xC0
    cmp  w11, #64
    b.eq 8f
1:  cmp  w9, #169                    // 169.254/16 link-local
    b.ne 2f
    cmp  w10, #254
    b.eq 8f
2:  cmp  w9, #172                    // 172.16/12
    b.ne 3f
    and  w11, w10, #0xF0
    cmp  w11, #16
    b.eq 8f
3:  cmp  w9, #192                    // 192.168/16 and 192.0/16 (IETF, TEST-NET-1)
    b.ne 4f
    cmp  w10, #168
    b.eq 8f
    cbz  w10, 8f
4:  cmp  w9, #198                    // 198.18/15 benchmarking
    b.ne 5f
    and  w11, w10, #0xFE
    cmp  w11, #18
    b.eq 8f
5:  mov  x0, #1
    ret
8:  mov  x0, #0
    ret

// local: x0 host, x1 host length, x2 suffix -> 1 if the host ends with it
Lends_with:
    stp  x29, x30, [sp, #-48]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    stp  x21, x22, [sp, #32]
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, x21
    bl   _strlen
    cmp  x0, x20
    b.hi 1f
    sub  x9, x20, x0
    add  x0, x19, x9
    mov  x1, x21
    bl   _strcmp
    cmp  w0, #0
    cset x0, eq
    b    2f
1:  mov  x0, #0
2:  ldp  x19, x20, [sp, #16]
    ldp  x21, x22, [sp, #32]
    ldp  x29, x30, [sp], #48
    ret

// long _web_url_check(const char *url) -> 1 if a Mac on the mesh may have the
//   gateway fetch it: http(s), port 80/443, a public-looking host name or
//   address. The host (lower case) goes to _g_whost, the port to _g_wport.
.globl _web_url_check
_web_url_check:
    ENTER 16
    mov  x19, x0
    mov  x0, x19
    ADRL x1, Ls_http
    mov  x2, #7
    bl   _strncasecmp
    cbnz w0, 1f
    mov  x9, #80
    add  x20, x19, #7
    b    2f
1:  mov  x0, x19
    ADRL x1, Ls_https
    mov  x2, #8
    bl   _strncasecmp
    cbnz w0, Luc_bad
    mov  x9, #443
    add  x20, x19, #8
2:  ADRL x8, _g_wport
    str  x9, [x8]
    ADRL x22, _g_whost
    mov  x21, #0                     // host length
3:  ldrb w9, [x20]
    cbz  w9, 5f
    cmp  w9, #'/'
    b.eq 5f
    cmp  w9, #'?'
    b.eq 5f
    cmp  w9, #'#'
    b.eq 5f
    cmp  w9, #':'
    b.eq 4f
    cmp  w9, #' '                    // controls, spaces and non-ASCII
    b.ls Luc_bad
    cmp  w9, #0x7f
    b.hs Luc_bad
    cmp  w9, #'@'                    // user@host
    b.eq Luc_bad
    cmp  w9, #'['                    // IPv6 literals
    b.eq Luc_bad
    cmp  w9, #']'
    b.eq Luc_bad
    cmp  w9, #'\\'
    b.eq Luc_bad
    cmp  w9, #'%'                    // escapes in the name
    b.eq Luc_bad
    sub  w10, w9, #'A'
    cmp  w10, #25
    b.hi 31f
    add  w9, w9, #32
31: strb w9, [x22, x21]
    add  x21, x21, #1
    cmp  x21, #253
    b.hs Luc_bad
    add  x20, x20, #1
    b    3b
4:  // a port: 80 or 443 only
    add  x20, x20, #1
    mov  x10, #0
    mov  x11, #0
41: ldrb w9, [x20]
    sub  w12, w9, #'0'
    cmp  w12, #9
    b.hi 42f
    mov  x13, #10
    madd x10, x10, x13, x12
    add  x11, x11, #1
    cmp  x11, #5
    b.hi Luc_bad
    add  x20, x20, #1
    b    41b
42: cbz  w9, 43f                     // the port must end the authority
    cmp  w9, #'/'
    b.eq 43f
    cmp  w9, #'?'
    b.eq 43f
    cmp  w9, #'#'
    b.ne Luc_bad
43: cmp  x10, #80
    b.eq 44f
    cmp  x10, #443
    b.ne Luc_bad
44: ADRL x8, _g_wport
    str  x10, [x8]
5:  strb wzr, [x22, x21]
    cbz  x21, Luc_bad
    sub  x9, x21, #1                 // "name." is refused
    ldrb w9, [x22, x9]
    cmp  w9, #'.'
    b.eq Luc_bad
    ldrb w9, [x22]
    cmp  w9, #'.'
    b.eq Luc_bad
    mov  x0, x22                     // a single word (localhost, intranet names)
    mov  w1, #'.'
    bl   _strchr
    cbz  x0, Luc_bad
    ADRL x23, Lbad_suffixes          // names that never leave the building
6:  ldr  x2, [x23], #8
    cbz  x2, 7f
    mov  x0, x22
    mov  x1, x21
    bl   Lends_with
    cbnz x0, Luc_bad
    b    6b
7:  ldrh w9, [x22]                   // hexadecimal address forms (0x7f.1)
    mov  w10, #0x7830                // "0x"
    cmp  w9, w10
    b.eq Luc_bad
    mov  x0, x22
    ADRL x1, Ls_dot0x
    bl   _strstr
    cbnz x0, Luc_bad
    // only digits and dots: it must be a plain a.b.c.d address, and a public one
    mov  x9, #0
8:  ldrb w10, [x22, x9]
    cbz  w10, 81f
    add  x9, x9, #1
    cmp  w10, #'.'
    b.eq 8b
    sub  w10, w10, #'0'
    cmp  w10, #9
    b.ls 8b
    b    Luc_ok                      // a name: looked up (and checked) later
81: mov  x0, x22
    bl   Lparse_quad
    tbnz x0, #63, Luc_bad
    bl   _web_ip_public
    cbz  x0, Luc_bad
Luc_ok:
    mov  x0, #1
    LEAVE 16
Luc_bad:
    mov  x0, #0
    LEAVE 16

// local: x0 "a.b.c.d" (digits and dots only) -> u32 address, or -1
Lparse_quad:
    mov  x9, #0                      // parts seen
    mov  x10, #0                     // address
    mov  x11, #0                     // this part
    mov  x12, #0                     // digits in this part
1:  ldrb w13, [x0], #1
    cmp  w13, #'.'
    b.eq 2f
    cbz  w13, 2f
    sub  w13, w13, #'0'
    mov  x14, #10
    madd x11, x11, x14, x13
    add  x12, x12, #1
    cmp  x12, #3
    b.hi 9f
    b    1b
2:  cbz  x12, 9f                     // empty part
    cmp  x11, #255
    b.hi 9f
    lsl  x10, x10, #8
    orr  x10, x10, x11
    add  x9, x9, #1
    mov  x11, #0
    mov  x12, #0
    cbnz w13, 1b                     // a '.' (unchanged): the next part
    cmp  x9, #4                      // the end: exactly four parts
    b.ne 9f
    mov  x0, x10
    ret
9:  mov  x0, #-1
    ret

// long _web_resolve(void) -> 1 and "host:port:address" in _g_wresolve when every
//   IPv4 address of _g_whost is public; 0 otherwise
_web_resolve:
    ENTER 64
    add  x0, sp, #104                // hints (48 bytes at sp+104)
    mov  w1, #0
    mov  x2, #48
    bl   _memset
    mov  w9, #2                      // AF_INET
    str  w9, [sp, #108]
    mov  w9, #1                      // SOCK_STREAM
    str  w9, [sp, #112]
    str  xzr, [sp, #96]              // result list
    ADRL x0, _g_whost
    mov  x1, #0
    add  x2, sp, #104
    add  x3, sp, #96
    bl   _getaddrinfo
    cbnz w0, 8f
    ldr  x19, [sp, #96]
    mov  x20, #0                     // first good address
    mov  x21, #0                     // a bad one seen
1:  cbz  x19, 3f
    ldr  w9, [x19, #4]               // ai_family
    cmp  w9, #2
    b.ne 2f
    ldr  x10, [x19, #32]             // ai_addr
    cbz  x10, 2f
    ldr  w0, [x10, #4]
    rev  w0, w0
    mov  w22, w0
    bl   _web_ip_public
    cbnz x0, 11f
    mov  x21, #1
    b    2f
11: cbnz x20, 2f
    mov  w20, w22
    orr  x20, x20, #(1 << 32)        // mark "found" (0.0.0.0 is never public anyway)
2:  ldr  x19, [x19, #40]             // ai_next
    b    1b
3:  ldr  x0, [sp, #96]
    bl   _freeaddrinfo
    cbnz x21, 8f
    cbz  x20, 8f
    ADRL x8, _g_whost                // "host:port:"
    str  x8, [sp]
    ADRL x8, _g_wport
    ldr  x8, [x8]
    str  x8, [sp, #8]
    ADRL x0, _g_wresolve
    mov  x1, #384
    ADRL x2, Lf_hostport
    bl   _snprintf
    lsr  w9, w20, #24                // "a.b.c.d"
    str  x9, [sp]
    ubfx w9, w20, #16, #8
    str  x9, [sp, #8]
    ubfx w9, w20, #8, #8
    str  x9, [sp, #16]
    and  w9, w20, #0xFF
    str  x9, [sp, #24]
    ADRL x0, _g_wquad
    mov  x1, #32
    ADRL x2, Lf_quad
    bl   _snprintf
    ADRL x0, _g_wresolve
    ADRL x1, _g_wquad
    mov  x2, #384
    bl   _strlcat
    mov  x0, #1
    LEAVE 64
8:  mov  x0, #0
    LEAVE 64

// long _web_fetch(job) -> bytes of the page in _fm_fetchbuf (0 = failed);
//   the job's address becomes the final one. A page for a Mac on the mesh
//   follows redirects itself, checking every hop.
_web_fetch:
    ENTER 16
    mov  x19, x0
    mov  x20, #0                     // hops
Lwf_hop:
    cmp  x20, #6
    b.hs Lwf_fail
    ADRL x21, _g_wargv
    mov  x22, #0
    ADRL x23, Largv_common
1:  ldr  x9, [x23], #8
    cbz  x9, 2f
    str  x9, [x21, x22, lsl #3]
    add  x22, x22, #1
    b    1b
2:  ldr  x9, [x19, #J_LOCAL]
    cbz  x9, 3f
    ADRL x23, Largv_local            // this Mac's own request: curl follows redirects
    b    4f
3:  add  x0, x19, #J_URL             // for the mesh: check the address, pin the lookup
    bl   _web_url_check
    cbz  x0, Lwf_fail
    bl   _web_resolve
    cbz  x0, Lwf_fail
    ADRL x23, Largv_mesh
4:  ldr  x9, [x23], #8
    cbz  x9, 5f
    str  x9, [x21, x22, lsl #3]
    add  x22, x22, #1
    b    4b
5:  ADRL x9, Lc_url                  // the address is never read as an option
    str  x9, [x21, x22, lsl #3]
    add  x22, x22, #1
    add  x9, x19, #J_URL
    str  x9, [x21, x22, lsl #3]
    add  x22, x22, #1
    str  xzr, [x21, x22, lsl #3]
    ADRL x8, _fm_fetch_len
    str  xzr, [x8]
    ADRL x0, Lc_curl
    mov  x1, x21
    ADRL x8, _fm_envp
    ldr  x2, [x8]
    mov  x3, #0
    mov  x4, #0
    bl   _fm_spawn
    cmp  w0, #0
    b.lt Lwf_fail
    mov  w24, w0
6:  mov  w0, w24
    bl   _fm_fetch_read
    cbnz w0, 6b
    ADRL x8, _fm_fetch_len
    ldr  x22, [x8]                   // curl adds "\n\x01<address>" at the end
    ADRL x21, _fm_fetchbuf
    mov  x9, x22
7:  cbz  x9, Lwf_done                // no marker: take it all
    sub  x9, x9, #1
    ldrb w10, [x21, x9]
    cmp  w10, #1
    b.ne 7b
    subs x22, x9, #1                 // the body ends before the "\n"
    csel x22, xzr, x22, lt
    add  x1, x21, x9
    add  x1, x1, #1                  // the address after the marker
    ldrb w10, [x1]
    cbz  w10, Lwf_done
    add  x0, x19, #J_URL
    mov  x2, #512
    bl   _strlcpy
    ldr  x9, [x19, #J_LOCAL]
    cbnz x9, Lwf_done                // local: that was the final address
    add  x20, x20, #1                // mesh: a redirect; check and follow it
    b    Lwf_hop
Lwf_done:
    mov  x0, x22
    LEAVE 16
Lwf_fail:
    mov  x0, #0
    LEAVE 16

// the fetch queue: x0 = job. Fetch, convert, pack; then back to the main thread.
_web_work:
    ENTER 16
    mov  x19, x0
    mov  x0, x19
    bl   _web_fetch
    mov  x22, x0                     // body length
    ADRL x21, _fm_fetchbuf
    ldr  x9, [x19, #J_KIND]
    cbnz x9, Lww_news
    // a page: "[address]\n\n" then the text
    ADRL x0, _g_wtext
    ADRL x1, Ls_lbr
    mov  x2, #16384
    bl   _strlcpy
    ADRL x0, _g_wtext
    add  x1, x19, #J_URL
    mov  x2, #16384
    bl   _strlcat
    ADRL x0, _g_wtext
    ADRL x1, Ls_rbr
    mov  x2, #16384
    bl   _strlcat
    mov  x23, x0
    ADRL x8, _fm_nlinks
    str  wzr, [x8]
    cbnz x22, 3f
    ADRL x0, _g_wtext                // nothing came back
    ADRL x1, Ls_fetchfail
    mov  x2, #16384
    bl   _strlcat
    mov  x23, x0
    b    4f
3:  mov  x0, x21
    mov  x1, x22
    ADRL x2, _g_wtext
    add  x2, x2, x23
    MOVI x3, W_TEXTCAP
    sub  x3, x3, x23
    add  x4, x19, #J_URL
    bl   _fm_html2text
    add  x23, x23, x0
4:  // then \x01 and the links, one per line
    ADRL x24, _g_wtext
    mov  w9, #1
    strb w9, [x24, x23]
    add  x23, x23, #1
    strb wzr, [x24, x23]
    mov  x20, #0
5:  ADRL x8, _fm_nlinks
    ldr  w9, [x8]
    cmp  x20, x9
    b.hs 6f
    cmp  x20, #LINKS_N
    b.hs 6f
    MOVI x9, (16384 - 600)
    cmp  x23, x9
    b.hs 6f
    ADRL x8, _fm_links
    mov  x9, #512
    madd x1, x20, x9, x8
    mov  x0, x24
    mov  x2, #16384
    bl   _strlcat
    ADRL x1, Ls_nl
    mov  x0, x24
    mov  x2, #16384
    bl   _strlcat
    mov  x23, x0
    add  x20, x20, #1
    b    5b
6:  MOVI x0, W_PACKCAP
    bl   _malloc
    str  x0, [x19, #J_PACK]
    cbz  x0, 7f
    mov  x2, x0
    ADRL x0, _g_wtext
    mov  x1, x23
    MOVI x3, W_PACKCAP
    bl   _fm_pack
    str  x0, [x19, #J_PLEN]
7:  LDGOT x0, __dispatch_main_q
    mov  x1, x19
    ADRL x2, _web_page_done
    bl   _dispatch_async_f
    LEAVE 16
Lww_news:                            // headlines, handed over in their own buffer
    str  xzr, [x19, #J_PLEN]
    cbz  x22, 8f
    mov  x0, x21
    mov  x1, x22
    ADRL x2, _g_wtext
    mov  x3, #16384
    bl   _fm_rss_titles
    mov  x20, x0
    add  x0, x20, #1
    bl   _malloc
    str  x0, [x19, #J_PACK]
    cbz  x0, 8f
    ADRL x1, _g_wtext
    mov  x2, x20
    bl   _memcpy
    ldr  x0, [x19, #J_PACK]
    strb wzr, [x0, x20]
    str  x20, [x19, #J_PLEN]
8:  LDGOT x0, __dispatch_main_q
    mov  x1, x19
    ADRL x2, _news_done
    bl   _dispatch_async_f
    LEAVE 16

// main thread: a page is packed. Local: show it. Else keep it and send the pieces.
_web_page_done:
    ENTER 16
    mov  x19, x0
    ldr  x20, [x19, #J_PACK]
    ldr  x21, [x19, #J_PLEN]
    ldr  x9, [x19, #J_LOCAL]
    cbnz x9, 1f
    // for the mesh: free the request's slot; stay quiet if another gateway answered
    ADRL x8, _g_pslots
    mov  x10, #0
0:  cmp  x10, #PSLOTS
    b.hs 1f
    add  x11, x8, x10, lsl #PS_SHIFT
    add  x10, x10, #1
    ldr  x12, [x11, #P_LIVE]
    cmp  x12, #3
    b.lo 0b
    ldr  x13, [x11, #P_REQ]
    ldr  x14, [x19, #J_REQ]
    cmp  x13, x14
    b.ne 0b
    ldr  w13, [x11, #P_ID]
    ldr  x14, [x19, #J_ID]
    cmp  w13, w14
    b.ne 0b
    str  xzr, [x11, #P_LIVE]
    cmp  x12, #4
    b.eq 8f                          // cancelled
1:  cbz  x20, Lpd_fail
    cbz  x21, Lpd_fail
    ldr  x9, [x19, #J_LOCAL]
    cbz  x9, 2f
    // asked on this Mac: straight into the Web room
    ADRL x8, _g_wr_id
    ldr  w9, [x8]
    ldr  x10, [x19, #J_ID]
    cmp  w9, w10
    b.ne 8f
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    ADRL x8, _g_wr_gw
    str  x9, [x8]
    add  x9, x21, #(W_DATA - 1)      // the pieces it would have taken on the mesh
    mov  x10, #W_DATA
    udiv x9, x9, x10
    ADRL x8, _g_wr_n
    str  x9, [x8]
    ADRL x8, _g_wr_state
    str  xzr, [x8]
    mov  x0, x20
    mov  x1, x21
    ADRL x2, _g_web_out
    MOVI x3, W_OUTCAP
    bl   _fm_unpack
    tbnz x0, #63, Lpd_bad
    mov  x1, x0
    ADRL x0, _g_web_out
    bl   _web_show_page
    b    8f
Lpd_bad:
    mov  x0, #WEB_ID
    ADRL x1, Ls_badpage
    bl   _web_say
    b    8f
Lpd_fail:                            // out of memory, or the page wouldn't pack
    ldr  x9, [x19, #J_LOCAL]
    cbz  x9, 8f                      // for the mesh: the asking Mac will ask again
    ADRL x8, _g_wr_id
    ldr  w9, [x8]
    ldr  x10, [x19, #J_ID]
    cmp  w9, w10
    b.ne 8f
    ADRL x8, _g_wr_state
    str  xzr, [x8]
    mov  x0, #WEB_ID
    ADRL x1, Ls_nomem
    bl   _web_say
    b    8f
2:  // the oldest cache slot (or an empty one)
    ADRL x22, _g_gslots
    mov  x23, #0
    mov  x24, #0                     // best
    mov  x10, #-1
3:  cmp  x23, #GSLOTS
    b.hs 4f
    add  x9, x22, x23, lsl #GS_SHIFT
    ldr  x11, [x9, #G_USED]
    cmp  x11, x10
    b.hs 31f
    mov  x10, x11
    mov  x24, x23
31: add  x23, x23, #1
    b    3b
4:  add  x22, x22, x24, lsl #GS_SHIFT
    ldr  x0, [x22, #G_DATA]
    cbz  x0, 5f
    bl   _free
5:  ldr  x9, [x19, #J_REQ]
    str  x9, [x22, #G_REQ]
    ldr  x9, [x19, #J_ID]
    str  x9, [x22, #G_ID]
    str  x20, [x22, #G_DATA]
    str  xzr, [x19, #J_PACK]
    str  x21, [x22, #G_LEN]
    add  x9, x21, #(W_DATA - 1)
    mov  x10, #W_DATA
    udiv x9, x9, x10
    cmp  x9, #W_MAXN
    mov  x10, #W_MAXN
    csel x9, x10, x9, hi
    str  x9, [x22, #G_N]
    bl   _fm_now_ms
    str  x0, [x22, #G_USED]
    str  x0, [x22, #G_NEXT]
    add  x0, x22, #G_MAP             // every piece to send
    mov  x1, #0xFF
    mov  x2, #64
    bl   _memset
    ldr  x8, [x22, #G_N]             // say so in our own feed
    str  x8, [sp]
    ADRL x0, _g_wline
    mov  x1, #1024
    ADRL x2, Lf_serving
    bl   _snprintf
    ADRL x0, _g_wline
    bl   _chat_line
    bl   _web_tick_arm
8:  ldr  x0, [x19, #J_PACK]
    cbz  x0, 9f
    bl   _free
9:  mov  x0, x19
    bl   _free
    LEAVE 16

// send one piece of a cache slot: x0 slot, x1 part
_gw_send_part:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    ADRL x0, _g_wpkt
    mov  w1, #T_WEBPART
    bl   _pkt_begin
    ADRL x21, _g_wpkt
    ldr  x9, [x19, #G_REQ]
    str  x9, [x21, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x21, #20]
    strb wzr, [x21, #28]
    ldr  x9, [x19, #G_ID]
    str  w9, [x21, #29]
    strh w20, [x21, #33]
    ldr  x9, [x19, #G_N]
    strh w9, [x21, #35]
    strb wzr, [x21, #37]
    mov  x9, #W_DATA                 // this piece's bytes
    mul  x10, x20, x9
    ldr  x11, [x19, #G_LEN]
    sub  x22, x11, x10
    cmp  x22, x9
    csel x22, x9, x22, hi
    add  x0, x21, #38
    ldr  x1, [x19, #G_DATA]
    add  x1, x1, x10
    mov  x2, x22
    bl   _memcpy
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, 1f
    add  x0, x21, #38
    mov  x1, x22
    add  x2, x21, #4
    bl   _crypto_seal
    mov  x22, x0
    mov  w9, #1
    strb w9, [x21, #37]
1:  add  x1, x22, #38
    mov  x0, x21
    bl   _pkt_finish
    cbz  x0, 9f
    mov  x1, x0
    mov  x0, x21
    bl   _ble_broadcast
9:  LEAVE 16

// ===========================================================================
// News
// ===========================================================================

// void _news_command(const char *text) — typed in the News room
.globl _news_command
_news_command:
    ENTER 0
    mov  x19, x0
    mov  x0, x19
    ADRL x1, Ls_refresh
    bl   _strcasecmp
    cbz  w0, 2f
    mov  x0, x19
    ADRL x1, Ls_feedsp
    mov  x2, #5
    bl   _strncasecmp
    cbz  w0, 3f
    mov  x0, #NEWS_ID
    ADRL x1, Ls_news_help
    bl   _web_say
    LEAVE 0
2:  mov  x0, #SVC_GATE
    bl   _svc_on
    cbnz x0, 21f
    mov  x0, #NEWS_ID
    ADRL x1, Ls_news_nogate
    bl   _web_say
    LEAVE 0
21: ADRL x8, _g_news_due
    str  xzr, [x8]                   // the tick fetches now
    bl   _web_tick_arm
    mov  x0, #NEWS_ID
    ADRL x1, Ls_news_fetching
    bl   _web_say
    LEAVE 0
3:  add  x1, x19, #5
    ADRL x0, Lk_feed
    bl   _pref_set
    mov  x0, #NEWS_ID
    ADRL x1, Ls_news_feedset
    bl   _web_say
    LEAVE 0

// start a headline fetch (main thread)
_news_fetch:
    ENTER 0
    ADRL x8, _g_news_busy
    ldr  x9, [x8]
    cbnz x9, 9f
    mov  x9, #1
    str  x9, [x8]
    bl   _web_env
    mov  x0, #J_SIZE
    bl   _malloc
    cbz  x0, 8f
    mov  x19, x0
    mov  x9, #1
    str  x9, [x19, #J_KIND]
    str  x9, [x19, #J_LOCAL]         // the feed is this Mac's own choice
    str  xzr, [x19, #J_PACK]
    str  xzr, [x19, #J_PLEN]
    ADRL x0, Lk_feed
    add  x1, x19, #J_URL
    mov  x2, #512
    bl   _pref_get
    ldrb w9, [x19, #J_URL]
    cbnz w9, 1f
    add  x0, x19, #J_URL
    ADRL x1, Ls_deffeed
    mov  x2, #512
    bl   _strlcpy
1:  bl   _web_queue
    cbz  x0, 7f
    mov  x1, x19
    ADRL x2, _web_work
    bl   _dispatch_async_f
    LEAVE 0
7:  mov  x0, x19
    bl   _free
8:  ADRL x8, _g_news_busy
    str  xzr, [x8]
9:  LEAVE 0

// main thread: the job's buffer holds the headlines, one per line ("- title")
_news_done:
    ENTER 16
    mov  x19, x0
    ADRL x8, _g_news_busy
    str  xzr, [x8]
    ldr  x21, [x19, #J_PACK]         // NUL-terminated by the fetch queue
    cbz  x21, 6f
    mov  x22, #0                     // new ones queued
    mov  x0, x21                     // the first title is the feed's own name
    mov  w1, #'\n'
    bl   _strchr
    cbz  x0, 5f
    add  x21, x0, #1
1:  ldrb w9, [x21]
    cbz  w9, 5f
    mov  x0, x21
    mov  w1, #'\n'
    bl   _strchr
    mov  x23, x0
    cbz  x23, 2f
    strb wzr, [x23]
2:  mov  x24, x21
    ldrb w9, [x24]                   // drop the "- " the RSS reader adds
    cmp  w9, #'-'
    b.ne 3f
    ldrb w9, [x24, #1]
    cmp  w9, #' '
    b.ne 3f
    add  x24, x24, #2
3:  ldrb w9, [x24]
    cbz  w9, 4f
    mov  x0, x24
    bl   _news_seen                  // sent (or shown) before?
    cbnz x0, 4f
    ADRL x8, _g_news_qn
    ldr  x9, [x8]
    cmp  x9, #NEWSQ_N
    b.hs 4f
    add  x10, x9, #1
    str  x10, [x8]
    ADRL x8, _g_news_q
    mov  x10, #NEWSQ_SZ
    madd x0, x9, x10, x8
    mov  x1, x24
    mov  x2, #NEWSQ_SZ
    bl   _strlcpy
    add  x22, x22, #1
4:  cbz  x23, 5f
    add  x21, x23, #1
    b    1b
5:  ldr  x0, [x19, #J_PACK]
    bl   _free
6:  mov  x0, x19
    bl   _free
    bl   _web_tick_arm
    LEAVE 16

// long _news_seen(const char *headline) -> 1 if already shown/sent; else remembers it
_news_seen:
    ENTER 0
    bl   _web_hash
    mov  x19, x0
    ADRL x8, _g_news_hash
    mov  x9, #0
1:  cmp  x9, #NHASH_N
    b.hs 2f
    ldr  x10, [x8, x9, lsl #3]
    cmp  x10, x19
    b.eq 3f
    add  x9, x9, #1
    b    1b
2:  ADRL x10, _g_news_hpos
    ldr  x11, [x10]
    add  x12, x11, #1
    str  x12, [x10]
    and  x11, x11, #(NHASH_N - 1)
    str  x19, [x8, x11, lsl #3]
    mov  x0, #0
    LEAVE 0
3:  mov  x0, #1
    LEAVE 0

// void _news_show(const char *headline, const char *from) — once, into News
.globl _news_show
_news_show:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    bl   _news_seen
    cbnz x0, 9f
    str  x19, [sp]
    str  x20, [sp, #8]
    ADRL x0, _g_wline
    mov  x1, #1024
    ADRL x2, Lf_headline
    bl   _snprintf
    mov  x0, #NEWS_ID
    ADRL x1, _g_wline
    mov  x2, #0
    bl   _web_room
    tbnz x0, #63, 9f
    ADRL x1, _g_wline
    mov  w2, #0
    bl   _room_line
9:  LEAVE 16

// send one queued headline as T_NEWS, and show it here too
_news_send_one:
    ENTER 16
    ADRL x8, _g_news_next
    ldr  x19, [x8]
    ADRL x8, _g_news_qn
    ldr  x9, [x8]
    cmp  x19, x9
    b.lo 1f
    ADRL x8, _g_news_qn              // all sent
    str  xzr, [x8]
    ADRL x8, _g_news_next
    str  xzr, [x8]
    LEAVE 16
1:  add  x9, x19, #1
    ADRL x8, _g_news_next
    str  x9, [x8]
    ADRL x8, _g_news_q
    mov  x9, #NEWSQ_SZ
    madd x20, x19, x9, x8            // the headline
    ADRL x0, _g_wpkt
    mov  w1, #T_NEWS
    bl   _pkt_begin
    ADRL x21, _g_wpkt
    str  xzr, [x21, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x21, #20]
    add  x0, x21, #28
    bl   _put_nick
    mov  x22, x0
    strb wzr, [x22]
    // as much of the headline as fits, cut on a character boundary
    sub  x24, x22, x21
    add  x24, x24, #1                // header, nick and flags
    mov  x9, #(PKT_MAX - TRAILER)
    sub  x24, x9, x24
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, 11f
    sub  x24, x24, #8                // the seal's tag
11: mov  x0, x20
    bl   _strlen
    mov  x23, x0
    cmp  x23, x24
    b.ls 13f
    mov  x23, x24
12: cbz  x23, 13f                    // don't split a UTF-8 character
    ldrb w9, [x20, x23]
    and  w9, w9, #0xC0
    cmp  w9, #0x80
    b.ne 13f
    sub  x23, x23, #1
    b    12b
13: add  x0, x22, #1
    mov  x1, x20
    mov  x2, x23
    bl   _memcpy
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, 2f
    add  x0, x22, #1
    mov  x1, x23
    add  x2, x21, #4
    bl   _crypto_seal
    mov  x23, x0
    mov  w9, #1
    strb w9, [x22]
2:  add  x9, x22, #1
    add  x9, x9, x23
    sub  x1, x9, x21
    mov  x0, x21
    bl   _pkt_finish
    cbz  x0, 3f
    mov  x1, x0
    mov  x0, x21
    bl   _ble_broadcast
3:  ADRL x9, _g_nick                 // shown here as well (it is already "seen")
    str  x20, [sp]
    str  x9, [sp, #8]
    ADRL x0, _g_wline
    mov  x1, #1024
    ADRL x2, Lf_headline
    bl   _snprintf
    mov  x0, #NEWS_ID
    bl   _web_room
    tbnz x0, #63, 4f
    ADRL x1, _g_wline
    mov  w2, #0
    bl   _room_line
4:  LEAVE 16

// ===========================================================================
// The tick: requests that stalled, pieces to send, headlines to post
// ===========================================================================

_web_tick_arm:
    ENTER 0
    ADRL x8, _g_web_tick_on
    ldr  x9, [x8]
    cbnz x9, 1f
    mov  x9, #1
    str  x9, [x8]
    bl   Lweb_arm
1:  LEAVE 0

Lweb_arm:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    mov  x0, #0
    MOVI x1, 250000000               // 250 ms
    bl   _dispatch_time
    LDGOT x1, __dispatch_main_q
    mov  x2, #0
    ADRL x3, _web_tick
    bl   _dispatch_after_f
    ldp  x29, x30, [sp], #16
    ret

_web_tick:
    ENTER 16
    mov  x24, #0                     // anything left to do?
    bl   _fm_now_ms
    mov  x19, x0
    // ---- asking side: waiting too long ----
    ADRL x8, _g_wr_state
    ldr  x9, [x8]
    cbz  x9, Lwt_gate
    mov  x24, #1
    MOVI x11, 15000                  // how long a quiet spell may last
    ADRL x8, _g_fm_running
    ldr  x12, [x8]
    cbz  x12, 0f
    MOVI x11, 25000                  //   (longer on the radio: pieces take ~2 s each)
0:  ADRL x8, _g_wr_tlast
    ldr  x10, [x8]
    sub  x10, x19, x10
    cmp  x10, x11
    b.lo Lwt_gate
    str  x19, [x8]
    ADRL x8, _g_wr_tries
    ldr  x12, [x8]
    add  x12, x12, #1
    str  x12, [x8]
    cmp  x9, #1
    b.ne 2f
    // nobody answered yet: ask again (the same request), twice at most;
    // a page this Mac fetches itself just gets the time
    ADRL x8, _g_wr_local
    ldr  x10, [x8]
    cbnz x10, 1f
    cmp  x12, #2
    b.hi 1f
    mov  w0, #2                      // quiet repeat
    bl   _web_send_req
    b    Lwt_gate
1:  cmp  x12, #3
    b.lo Lwt_gate
    ADRL x8, _g_wr_state
    str  xzr, [x8]
    mov  x0, #WEB_ID
    ADRL x1, Ls_noanswer
    bl   _web_say
    b    Lwt_gate
2:  // pieces stopped coming: ask for the missing ones, six times at most
    cmp  x12, #6
    b.ls 3f
    ADRL x8, _g_wr_state
    str  xzr, [x8]
    mov  x0, #WEB_ID
    ADRL x1, Ls_gaveup
    bl   _web_say
    b    Lwt_gate
3:  mov  w0, #3                      // missing pieces, quiet
    bl   _web_send_req
Lwt_gate:
    mov  x0, #SVC_GATE
    bl   _svc_on
    cbz  x0, Lwt_done
    mov  x24, #1
    // ---- requests due for an answer ----
    ADRL x20, _g_pslots
    mov  x21, #0
4:  cmp  x21, #PSLOTS
    b.hs 5f
    add  x22, x20, x21, lsl #PS_SHIFT
    ldr  x10, [x22, #P_LIVE]
    cmp  x10, #1                     // collecting or waiting, and due?
    b.lo 41f
    cmp  x10, #2
    b.hi 41f
    ldr  x9, [x22, #P_DUE]
    cmp  x9, x19
    b.hi 41f
    cmp  x10, #1
    b.ne 40f
    str  xzr, [x22, #P_LIVE]         // pieces of the request never came: forget it
    b    41f
40: ldr  x0, [x22, #P_REQ]           // each asker: 6 pages at once, then one per
    mov  x9, #0x6A7E
    eor  x0, x0, x9                  //   10 s (limits.s; its own bucket, not their
    mov  x1, #10                     //   packets'), so nobody can keep the gateway
    mov  x2, #60                     //   to themselves
    mov  x3, #1
    bl   _rate_take
    cbnz x0, 42f
    str  xzr, [x22, #P_LIVE]         // over: dropped (they'll hear nothing back)
    b    41f
42: mov  x9, #3                      // fetching (freed when the page is ready)
    str  x9, [x22, #P_LIVE]
    ldr  x0, [x22, #P_REQ]
    ldr  x1, [x22, #P_ID]
    add  x2, x22, #P_TEXT
    mov  w3, #0
    bl   _web_job_page
    cbnz x0, 41f
    str  xzr, [x22, #P_LIVE]         // couldn't start it
41: add  x21, x21, #1
    b    4b
5:  // ---- pieces to send ----
    bl   _web_pace
    mov  x23, x0
    ADRL x20, _g_gslots
    mov  x21, #0
6:  cmp  x21, #GSLOTS
    b.hs Lwt_news
    add  x22, x20, x21, lsl #GS_SHIFT
    ldr  x9, [x22, #G_DATA]
    cbz  x9, 69f
    ldr  x9, [x22, #G_NEXT]
    cmp  x9, x19
    b.hi 69f
    // up to 4 pieces per tick on Bluetooth, one on FM
    mov  x9, #4
    ADRL x8, _g_fm_running
    ldr  x10, [x8]
    cmp  x10, #0
    mov  x10, #1
    csel x9, x10, x9, ne
    str  x9, [sp, #96]
    mov  x10, #0                     // part index
61: ldr  x11, [x22, #G_N]
    cmp  x10, x11
    b.hs 68f
    lsr  x12, x10, #3
    and  x13, x10, #7
    add  x14, x22, #G_MAP
    ldrb w15, [x14, x12]
    lsr  w16, w15, w13
    tbz  w16, #0, 67f
    mov  w16, #1                     // clear it, then send it
    lsl  w16, w16, w13
    bic  w15, w15, w16
    strb w15, [x14, x12]
    str  x10, [sp, #104]
    mov  x0, x22
    mov  x1, x10
    bl   _gw_send_part
    ldr  x10, [sp, #104]
    ldr  x9, [sp, #96]
    subs x9, x9, #1
    str  x9, [sp, #96]
    b.eq 68f
67: add  x10, x10, #1
    b    61b
68: add  x9, x19, x23
    str  x9, [x22, #G_NEXT]
69: add  x21, x21, #1
    b    6b
Lwt_news:
    // ---- headlines: fetch every 15 minutes, post one at a time ----
    ADRL x8, _g_news_due
    ldr  x9, [x8]
    cmp  x9, x19
    b.hi 7f
    MOVI x10, 900000
    add  x9, x19, x10
    str  x9, [x8]
    bl   _news_fetch
7:  ADRL x8, _g_news_qn
    ldr  x9, [x8]
    cbz  x9, Lwt_done
    ADRL x8, _g_news_tnext           // one at a time, at the radio's pace
    ldr  x10, [x8]
    cmp  x10, x19
    b.hi Lwt_done
    bl   _web_pace
    add  x0, x0, x19
    ADRL x8, _g_news_tnext
    str  x0, [x8]
    bl   _news_send_one              // (clears the queue once all are out)
Lwt_done:
    cbz  x24, 9f
    bl   Lweb_arm
    LEAVE 16
9:  ADRL x8, _g_web_tick_on
    str  xzr, [x8]
    LEAVE 16

// ===========================================================================
// Self-test
// ===========================================================================

// long _web_selftest(void) -> failures
.globl _web_selftest
_web_selftest:
    ENTER 32
    mov  x19, #0
    // 1. addresses and searches
    ADRL x0, Lt_host
    ADRL x1, _g_wurl
    bl   _web_make_url
    ADRL x0, _g_wurl
    ADRL x1, Lt_host_url
    bl   _strcmp
    cmp  w0, #0
    cset w1, eq
    ADRL x0, Ln_url
    bl   _t_report
    add  x19, x19, x0
    ADRL x0, Lt_words
    ADRL x1, _g_wurl
    bl   _web_make_url
    ADRL x0, _g_wurl
    ADRL x1, Lt_words_url
    bl   _strcmp
    cmp  w0, #0
    cset w1, eq
    ADRL x0, Ln_search
    bl   _t_report
    add  x19, x19, x0

    // 2. what a gateway will fetch for the mesh
    mov  x20, #1                     // all as expected so far
    ADRL x21, Lt_urls
20: ldr  x0, [x21], #16
    cbz  x0, 22f
    bl   _web_url_check
    ldur x9, [x21, #-8]
    cmp  x0, x9
    b.eq 20b
    mov  x20, #0
    ldur x9, [x21, #-16]             // name the one that went wrong
    str  x9, [sp]
    ADRL x0, Lf_badcase
    bl   _printf
    b    20b
22: mov  w1, w20
    ADRL x0, Ln_safe
    bl   _t_report
    add  x19, x19, x0

    // 3. a long request in pieces, out of order, is put back together by the gateway
    ADRL x0, Lt_longurl
    bl   _strlen
    mov  x20, x0                     // its length (> 200: three pieces of 100)
    mov  x21, #2                     // deliver pieces 2, 0, 1
    bl   Lt_rqpiece
    mov  x21, #0
    bl   Lt_rqpiece
    mov  x21, #1
    bl   Lt_rqpiece
    mov  w1, #0
    ADRL x8, _g_pslots
    mov  x9, #0
30: cmp  x9, #PSLOTS
    b.hs 32f
    add  x10, x8, x9, lsl #PS_SHIFT
    add  x9, x9, #1
    ldr  x11, [x10, #P_REQ]
    MOVI x12, 0x1111
    cmp  x11, x12
    b.ne 30b
    ldr  x11, [x10, #P_LIVE]
    cmp  x11, #2                     // complete, waiting to be fetched
    b.ne 32f
    add  x0, x10, #P_TEXT
    ADRL x1, Lt_longurl
    bl   _strcmp
    cmp  w0, #0
    cset w1, eq
32: ADRL x0, Ln_request
    bl   _t_report
    add  x19, x19, x0
    ADRL x0, _g_pslots
    mov  w1, #0
    mov  x2, #(PSLOTS << PS_SHIFT)
    bl   _memset

    // 4. page pieces: any order; repeats, strangers and other requests ignored
    ADRL x0, Lt_page
    bl   _strlen
    mov  x20, x0                     // raw bytes stand in for a packed page (3 pieces)
    ADRL x8, _g_wr_state
    mov  x9, #1
    str  x9, [x8]
    ADRL x8, _g_wr_id
    mov  x9, #77
    str  x9, [x8]
    ADRL x8, _g_wr_gw
    str  xzr, [x8]
    ADRL x8, _g_wr_got
    str  xzr, [x8]
    ADRL x0, _g_wr_have
    mov  w1, #0
    mov  x2, #64
    bl   _memset
    MOVI x0, 0x6A7E0001              // the last piece first
    mov  x1, #77
    mov  x2, #2
    bl   Lt_pgpiece
    MOVI x0, 0x6A7E0001              // the same again
    mov  x1, #77
    mov  x2, #2
    bl   Lt_pgpiece
    MOVI x0, 0x6A7E0002              // another gateway
    mov  x1, #77
    mov  x2, #1
    bl   Lt_pgpiece
    MOVI x0, 0x6A7E0001              // another request
    mov  x1, #78
    mov  x2, #1
    bl   Lt_pgpiece
    MOVI x0, 0x6A7E0001              // the middle one
    mov  x1, #77
    mov  x2, #1
    bl   Lt_pgpiece
    mov  w1, #0
    ADRL x8, _g_wr_got               // two pieces, from the first gateway, still asking
    ldr  x9, [x8]
    cmp  x9, #2
    b.ne 42f
    ADRL x8, _g_wr_state
    ldr  x9, [x8]
    cmp  x9, #2
    b.ne 42f
    ADRL x0, _g_wr_data              // and the bytes in the right places
    add  x0, x0, #W_DATA
    ADRL x1, Lt_page
    add  x1, x1, #W_DATA
    sub  x2, x20, #W_DATA
    bl   _memcmp
    cmp  w0, #0
    cset w1, eq
42: ADRL x0, Ln_pieces
    bl   _t_report
    add  x19, x19, x0
    ADRL x8, _g_wr_state
    str  xzr, [x8]

    // 5. the packed page unpacks to the original
    ADRL x0, Lt_page
    mov  x1, x20
    ADRL x2, _g_web_out
    MOVI x3, W_OUTCAP
    bl   _fm_pack
    mov  x21, x0
    mov  w1, #0
    cbz  x21, 53f
    ADRL x0, _g_web_out
    mov  x1, x21
    ADRL x2, _g_wr_data
    MOVI x3, W_PACKCAP
    bl   _fm_unpack
    cmp  x0, x20
    mov  w1, #0
    b.ne 53f
    ADRL x0, _g_wr_data
    ADRL x1, Lt_page
    mov  x2, x20
    bl   _memcmp
    cmp  w0, #0
    cset w1, eq
53: ADRL x0, Ln_unpack
    bl   _t_report
    add  x19, x19, x0

    // 6. HTML to text with numbered links, resolved against the page's address
    ADRL x8, _fm_nlinks
    str  wzr, [x8]
    ADRL x0, Lt_html
    bl   _strlen
    mov  x1, x0
    ADRL x0, Lt_html
    ADRL x2, _g_wtext
    mov  x3, #4096
    ADRL x4, Lt_base
    bl   _fm_html2text
    ADRL x0, _g_wtext
    ADRL x1, Lt_html_text
    bl   _strcmp
    mov  w1, #0
    cbnz w0, 64f
    ADRL x0, _fm_links
    ADRL x1, Lt_html_link
    bl   _strcmp
    cmp  w0, #0
    cset w1, eq
64: ADRL x0, Ln_html
    bl   _t_report
    add  x19, x19, x0
    mov  x0, x19
    LEAVE 32

// test helper: request piece x21 (of 3, 100 bytes each) of Lt_longurl (x20 long)
Lt_rqpiece:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    mov  x9, #100
    mul  x7, x21, x9                 // offset
    sub  x4, x20, x7
    cmp  x4, x9
    csel x4, x9, x4, hi              // len
    ADRL x3, Lt_longurl
    add  x3, x3, x7
    MOVI x0, 0x1111                  // requester
    mov  w1, #5                      // reqid
    mov  x2, #1                      // asked by name: no random wait
    mov  x5, x21
    mov  x6, #3
    bl   _gw_piece_add
    ldp  x29, x30, [sp], #16
    ret

// test helper: page piece x2 of Lt_page (x20 long, 3 pieces) from gateway x0, reqid x1
Lt_pgpiece:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    mov  x9, #W_DATA
    mul  x10, x2, x9
    sub  x5, x20, x10
    cmp  x5, x9
    csel x5, x9, x5, hi
    ADRL x4, Lt_page
    add  x4, x4, x10
    mov  x3, #3
    bl   _web_accept_part
    ldp  x29, x30, [sp], #16
    ret

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_NSAttributedString:  .asciz "NSAttributedString"
Ls_alloc:               .asciz "alloc"
Ls_initWithStringAttrs: .asciz "initWithString:attributes:"
Ls_appendAttributedString: .asciz "appendAttributedString:"
Ls_release:             .asciz "release"
Ls_scrollToEndOfDocument: .asciz "scrollToEndOfDocument:"
Ls_PATH:        .asciz "PATH"
Ls_pathval:     .asciz "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
Ls_scheme:      .asciz "://"
Ls_https:       .asciz "https://"
Ls_search:      .asciz "https://lite.duckduckgo.com/lite/?q="
Ls_back:        .asciz "back"
Ls_links:       .asciz "links"
Ls_refresh:     .asciz "refresh"
Ls_feedsp:      .asciz "feed "
Lk_feed:        .asciz "news_feed"
Ls_deffeed:     .asciz "https://feeds.bbci.co.uk/news/world/rss.xml"
Ls_qname:       .asciz "asmmesh.web"
Ls_lbr:         .asciz "["
Ls_rbr:         .asciz "]\n\n"
Ls_nl:          .asciz "\n"
Ls_nl2:         .asciz "\n\n"
Ls_fetchfail:   .asciz "The gateway couldn't load this page."
Ls_thismac:     .asciz "this Mac"
Ls_nolink:      .asciz "There is no link with that number. Type links to see them."
Ls_noback:      .asciz "There is no earlier page."
Ls_nolinks:     .asciz "No links on this page."
Ls_nobody:      .asciz "Nobody on the mesh to ask yet \342\200\224 the request is waiting for a Mac to link up."
Ls_noanswer:    .asciz "No gateway answered. A Mac with internet needs Internet for the mesh switched on (Settings)."
Ls_gaveup:      .asciz "Some pieces never arrived; try again."
Ls_nomem:       .asciz "Not enough memory to fetch that page."
Ls_nosign:      .asciz "This Mac\342\200\231s identity isn\342\200\231t ready yet, so the request couldn\342\200\231t be signed. Try again in a moment."
Ls_badpage:     .asciz "The page arrived but couldn't be unpacked."
Ls_locked:      .asciz "The page is locked with a mesh passphrase this Mac doesn't have."
Ls_gate_on:     .asciz "Internet for the mesh is on: this Mac answers web requests and posts headlines."
Ls_news_help:   .asciz "Headlines from gateway Macs appear here. Type refresh to fetch now (on a gateway), or feed <address> to change the RSS feed."
Ls_news_nogate: .asciz "Only a gateway fetches headlines: switch on Internet for the mesh on a Mac with internet."
Ls_news_fetching: .asciz "Fetching headlines\342\200\246"
Ls_news_feedset: .asciz "Feed saved; type refresh to fetch it now."
Lf_asking:      .asciz "Asking the mesh for \342\200\234%s\342\200\235\342\200\246"
Lf_progress:    .asciz "%ld of %ld pieces\342\200\246"
Lf_page_from:   .asciz "Page from %s (%ld pieces):"
Lf_link:        .asciz "[%ld] %s\n"
Lf_serving:     .asciz "Web: sending a page to the mesh in %ld pieces."
Lf_headline:    .asciz "\342\200\242 %s  \302\267 via %s"
// tests
Lt_host:        .asciz "example.com"
Lt_host_url:    .asciz "https://example.com"
Lt_words:       .asciz "radio waves"
Lt_words_url:   .asciz "https://lite.duckduckgo.com/lite/?q=radio+waves"
Lt_page:        .asciz "[https://example.com/]\n\nFM mesh test page. This line repeats to make the page longer than a few pieces. FM mesh test page. This line repeats to make the page longer than a few pieces. FM mesh test page 0123456789 abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ.\001https://example.com/a\nhttps://example.com/b\n"
Lt_html:        .asciz "<p>Hello &amp; welcome</p><a href=\"/next\">Next</a>"
Lt_base:        .asciz "https://example.com/dir/page.html"
Lt_html_text:   .asciz "Hello & welcome\nNext[1]"
Lt_html_link:   .asciz "https://example.com/next"
Ln_url:         .asciz "web: an address gets https:// added"
Ln_search:      .asciz "web: words become a search"
Ln_pieces:      .asciz "web: a page cut into pieces is rebuilt, in any order"
Ln_unpack:      .asciz "web: a compressed page unpacks to the original"
Ln_html:        .asciz "web: HTML becomes text with numbered, resolved links"
Ln_safe:        .asciz "web: a gateway fetches only public http(s) addresses for the mesh"
Ln_request:     .asciz "web: a long address sent in pieces is put back together"
Lf_badcase:     .asciz "      (unexpected answer for %s)\n"
Lt_longurl:     .asciz "https://example.com/a/very/long/path/that/needs/more/than/one/packet/to/cross/the/mesh/because/links/on/real/pages/are/often/this/long/or/longer/than/this/one/which/has/two/hundred/and/some/characters/in/it/for/the/test?x=1"
Lu1:  .asciz "https://example.com/a?b=1"
Lu2:  .asciz "http://93.184.216.34/"
Lu3:  .asciz "https://Example.COM:443/x"
Lu4:  .asciz "file:///etc/passwd"
Lu5:  .asciz "http://127.0.0.1/"
Lu6:  .asciz "http://10.0.0.1/"
Lu7:  .asciz "http://192.168.1.1/"
Lu8:  .asciz "http://172.20.1.1/"
Lu9:  .asciz "http://169.254.169.254/latest"
Lu10: .asciz "http://localhost/"
Lu11: .asciz "http://printer.local/"
Lu12: .asciz "http://[::1]/"
Lu13: .asciz "http://user@example.com/"
Lu14: .asciz "http://example.com:22/"
Lu15: .asciz "http://2130706433/"
Lu16: .asciz "http://0x7f.1/"
Lu17: .asciz "http://127.1/"
Lu18: .asciz "ftp://example.com/"
Lu19: .asciz "-K/etc/x"
Lu20: .asciz "https://example.com./"
Lu21: .asciz "http://100.100.1.1/"
// fetching
Ls_http:        .asciz "http://"
Ls_dot0x:       .asciz ".0x"
Lf_hostport:    .asciz "%s:%ld:"
Lf_quad:        .asciz "%ld.%ld.%ld.%ld"
Lc_curl:        .asciz "curl"
Lc_s:           .asciz "-s"
Lc_comp:        .asciz "--compressed"
Lc_mt:          .asciz "--max-time"
Lc_20:          .asciz "20"
Lc_mfs:         .asciz "--max-filesize"
Lc_2m:          .asciz "2000000"
Lc_A:           .asciz "-A"
Lc_ua:          .asciz "Mozilla/5.0 (Macintosh; Apple Silicon) asmmesh"
Lc_proto:       .asciz "--proto"
Lc_protoredir:  .asciz "--proto-redir"
Lc_httponly:    .asciz "=http,https"
Lc_L:           .asciz "-L"
Lc_maxredirs:   .asciz "--max-redirs"
Lc_5:           .asciz "5"
Lc_w:           .asciz "-w"
Lc_weff:        .asciz "\n\001%{url_effective}"
Lc_wredir:      .asciz "\n\001%{redirect_url}"
Lc_resolve:     .asciz "--resolve"
Lc_url:         .asciz "--url"
Lsx_localhost:  .asciz ".localhost"
Lsx_local:      .asciz ".local"
Lsx_internal:   .asciz ".internal"
Lsx_lan:        .asciz ".lan"
Lsx_home:       .asciz ".home"
Lsx_arpa:       .asciz ".arpa"
Lsx_intranet:   .asciz ".intranet"
Lsx_corp:       .asciz ".corp"
Lsx_localdomain: .asciz ".localdomain"

.section __DATA,__const
.p2align 3
Largv_common:   .quad Lc_curl, Lc_s, Lc_comp, Lc_mt, Lc_20, Lc_mfs, Lc_2m, Lc_A, Lc_ua
                .quad Lc_proto, Lc_httponly, 0
Largv_local:    .quad Lc_L, Lc_maxredirs, Lc_5, Lc_protoredir, Lc_httponly, Lc_w, Lc_weff, 0
Largv_mesh:     .quad Lc_resolve, _g_wresolve, Lc_w, Lc_wredir, 0
Lbad_suffixes:  .quad Lsx_localhost, Lsx_local, Lsx_internal, Lsx_lan, Lsx_home, Lsx_arpa
                .quad Lsx_intranet, Lsx_corp, Lsx_localdomain, 0
Lt_urls:        .quad Lu1, 1, Lu2, 1, Lu3, 1, Lu4, 0, Lu5, 0, Lu6, 0, Lu7, 0, Lu8, 0
                .quad Lu9, 0, Lu10, 0, Lu11, 0, Lu12, 0, Lu13, 0, Lu14, 0, Lu15, 0
                .quad Lu16, 0, Lu17, 0, Lu18, 0, Lu19, 0, Lu20, 0, Lu21, 0, 0, 0
