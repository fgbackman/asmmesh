// files.s — your phone and your Macs' folders, over home Wi-Fi; and AirDrop.
//
//   Files on Wi-Fi   a small web page on this Mac (port 8788) that a phone's browser opens:
//                    browse the folders you chose, tap a file to open or download it,
//                    and upload photos and files into any of them. Nothing can be
//                    deleted or overwritten from the phone (a name that is taken gets
//                    " (2)"). The address has a long secret in it; "files new" changes it.
//                    Hidden files (".ssh", …) and the Library folder never show.
//   "files"          the address, as a QR code to scan (and pushed to your phone)
//   "share folders"  choose which folders (Mesh › Share Folders on Wi-Fi…)
//   "airdrop"        pick files and AirDrop them (Mesh › AirDrop a File…)
//
// Each connection is served on a background thread with blocking reads and writes
// (30-second timeouts), so a big upload never holds up the window.

.include "macros.inc"

.set FS_PORT,    8788
.set NROOT_MAX,  8
.set ROOT_LEN,   1024
.set HDR_MAX,    16384
.set BUF_CAP,    65536
.set W_CAP,      8192

// one connection's state (calloc'd, freed when the connection closes)
.set CT_FD,      0
.set CT_HLEN,    8
.set CT_HEND,    16
.set CT_ROOT,    24
.set CT_CLEN,    32
.set CT_FFD,     40
.set CT_BLEN,    72
.set CT_NUP,     80
.set CT_WLEN,    88
.set CT_BL,      96
.set CT_LEFT,    104
.set CT_DL,      112
.set CT_L2,      120                  // the request's headers, from their first "\r\n"
.set CT_BOUND,   128                  // "\r\n--" + boundary (96)
.set CT_PATH,    224                  // the folder or file asked for, relative (1024)
.set CT_FULL,    1248                 // (1104)
.set CT_REAL,    2352                 // its real path (1104)
.set CT_RROOT,   3456                 // the shared folder's real path (1104)
.set CT_NAME,    4560                 // an upload's file name (272)
.set CT_TMP,     4832                 // (1104)
.set CT_W,       5936                 // what we are about to send (8192)
.set CT_HDR,     14128                // the request (16392)
.set CT_BUF,     30528                // file data (65536 + 512)
.set CT_SIZE,    96576

// address of a field of the connection in x19
.macro CTA reg, off
    mov  \reg, #\off
    add  \reg, x19, \reg
.endm

.data
.p2align 3
_g_fs_fd:       .quad -1
_g_fs_src:      .quad 0
.globl _g_fs_nroots
_g_fs_nroots:   .quad 0
_g_fs_qrwin:    .quad 0
_g_fs_qriv:     .quad 0
_g_fs_qrlbl:    .quad 0
.globl _g_fs_tok
.zerofill __DATA,__bss,_g_fs_tok,40,4
.globl _g_fs_roots
.zerofill __DATA,__bss,_g_fs_roots,8192,4
.globl _g_fs_home
.zerofill __DATA,__bss,_g_fs_home,1104,4
.zerofill __DATA,__bss,_g_fs_url,200,4
.zerofill __DATA,__bss,_g_fs_ip,48,4
.zerofill __DATA,__bss,_g_fs_line,1200,4
.zerofill __DATA,__bss,_g_fs_pref,8400,4
.zerofill __DATA,__bss,_g_fs_tresp,16384,4

.section __TEXT,__const
.p2align 3
Lc_1k:      .double 1024.0
Lc_1m:      .double 1048576.0
Lc_1g:      .double 1073741824.0
Lc_0:       .double 0.0
Lc_qw:      .double 320.0
Lc_qh:      .double 400.0
Lf_qr_iv:   .double 30.0, 110.0, 260.0, 260.0
Lf_qr_url:  .double 16.0, 72.0, 288.0, 20.0
Lf_qr_how:  .double 16.0, 30.0, 288.0, 34.0
Lc_s12:     .double 12.0
Lc_250:     .double 250.0

.text
.p2align 2

// ===========================================================================
// Writing the answer (buffered)
// ===========================================================================

// long _fs_sendall(int fd, const void *buf, size_t n) -> 0 sent, -1 not
_fs_sendall:
    ENTER 0
    mov  w19, w0
    mov  x20, x1
    mov  x21, x2
Lsa2_loop:
    cbz  x21, Lsa2_ok
    mov  w0, w19
    mov  x1, x20
    mov  x2, x21
    bl   _write
    cmp  x0, #0
    b.le Lsa2_fail
    add  x20, x20, x0
    sub  x21, x21, x0
    b    Lsa2_loop
Lsa2_ok:
    mov  x0, #0
    LEAVE 0
Lsa2_fail:
    mov  x0, #-1
    LEAVE 0

// void _fs_flush(ctx)
_fs_flush:
    ENTER 0
    mov  x19, x0
    ldr  x2, [x19, #CT_WLEN]
    cbz  x2, Lfl_done
    ldr  x0, [x19, #CT_FD]
    CTA  x1, CT_W
    bl   _fs_sendall
    str  xzr, [x19, #CT_WLEN]
Lfl_done:
    LEAVE 0

// void _fs_wn(ctx, const void *s, size_t n)
_fs_wn:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
Lwn_loop:
    cbz  x21, Lwn_done
    ldr  x9, [x19, #CT_WLEN]
    mov  x10, #W_CAP
    subs x10, x10, x9
    b.hi Lwn_copy
    mov  x0, x19
    bl   _fs_flush
    b    Lwn_loop
Lwn_copy:
    cmp  x10, x21
    csel x22, x10, x21, lo
    CTA  x0, CT_W
    add  x0, x0, x9
    mov  x1, x20
    mov  x2, x22
    bl   _memcpy
    ldr  x9, [x19, #CT_WLEN]
    add  x9, x9, x22
    str  x9, [x19, #CT_WLEN]
    add  x20, x20, x22
    sub  x21, x21, x22
    b    Lwn_loop
Lwn_done:
    LEAVE 0

// void _fs_w(ctx, const char *s)
_fs_w:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x20
    bl   _strlen
    mov  x2, x0
    mov  x0, x19
    mov  x1, x20
    bl   _fs_wn
    LEAVE 0

// void _fs_wc(ctx, char c)
_fs_wc:
    ENTER 16
    strb w1, [sp, #96]
    add  x1, sp, #96
    mov  x2, #1
    bl   _fs_wn
    LEAVE 16

// void _fs_wesc(ctx, const char *s) — as HTML text
_fs_wesc:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
Lwe_loop:
    ldrb w9, [x20], #1
    cbz  w9, Lwe_done
    ADRL x1, Ls_e_amp
    cmp  w9, #'&'
    b.eq Lwe_str
    ADRL x1, Ls_e_lt
    cmp  w9, #'<'
    b.eq Lwe_str
    ADRL x1, Ls_e_gt
    cmp  w9, #'>'
    b.eq Lwe_str
    ADRL x1, Ls_e_quot
    cmp  w9, #'"'
    b.eq Lwe_str
    ADRL x1, Ls_e_apos
    cmp  w9, #'\''
    b.eq Lwe_str
    mov  x0, x19
    mov  w1, w9
    bl   _fs_wc
    b    Lwe_loop
Lwe_str:
    mov  x0, x19
    bl   _fs_w
    b    Lwe_loop
Lwe_done:
    LEAVE 0

// void _fs_wurl(ctx, const char *s) — a path in an address: %XX except letters,
//   digits, - _ . ~ and /
_fs_wurl:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
Lwu_loop:
    ldrb w9, [x20], #1
    cbz  w9, Lwu_done
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.ls Lwu_raw
    orr  w10, w9, #0x20
    sub  w10, w10, #'a'
    cmp  w10, #25
    b.ls Lwu_raw
    cmp  w9, #'-'
    b.eq Lwu_raw
    cmp  w9, #'_'
    b.eq Lwu_raw
    cmp  w9, #'.'
    b.eq Lwu_raw
    cmp  w9, #'~'
    b.eq Lwu_raw
    cmp  w9, #'/'
    b.eq Lwu_raw
    mov  w10, #'%'
    strb w10, [sp, #96]
    ADRL x11, Ls_hexup
    lsr  w12, w9, #4
    ldrb w12, [x11, x12]
    strb w12, [sp, #97]
    and  w12, w9, #15
    ldrb w12, [x11, x12]
    strb w12, [sp, #98]
    mov  x0, x19
    add  x1, sp, #96
    mov  x2, #3
    bl   _fs_wn
    b    Lwu_loop
Lwu_raw:
    mov  x0, x19
    mov  w1, w9
    bl   _fs_wc
    b    Lwu_loop
Lwu_done:
    LEAVE 16

// void _fs_wnum(ctx, long n)
_fs_wnum:
    ENTER 32
    mov  x19, x0
    str  x1, [sp]
    add  x0, sp, #96
    mov  x1, #32
    ADRL x2, Lf_ld
    bl   _snprintf
    mov  x0, x19
    add  x1, sp, #96
    bl   _fs_w
    LEAVE 32

// void _fs_wsize(ctx, long bytes) — "812 B", "44 KB", "3.2 MB", "1.25 GB"
_fs_wsize:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    cmp  x20, #1024
    b.hs Lws_kb
    str  x20, [sp]
    ADRL x2, Lf_b
    b    Lws_fmt
Lws_kb:
    ucvtf d0, x20
    mov  x9, #0x100000
    cmp  x20, x9
    b.hs Lws_mb
    LDD  d1, Lc_1k
    fdiv d0, d0, d1
    str  d0, [sp]
    ADRL x2, Lf_kb
    b    Lws_fmt
Lws_mb:
    mov  x9, #0x40000000
    cmp  x20, x9
    b.hs Lws_gb
    LDD  d1, Lc_1m
    fdiv d0, d0, d1
    str  d0, [sp]
    ADRL x2, Lf_mb
    b    Lws_fmt
Lws_gb:
    LDD  d1, Lc_1g
    fdiv d0, d0, d1
    str  d0, [sp]
    ADRL x2, Lf_gb
Lws_fmt:
    add  x0, sp, #96
    mov  x1, #32
    bl   _snprintf
    mov  x0, x19
    add  x1, sp, #96
    bl   _fs_w
    LEAVE 32

// void _fs_whref(ctx, char kind, const char *name or 0, long slash)
//   "/<secret>/<kind>/<folder>/<path>[/<name>][/]"
_fs_whref:
    ENTER 16
    mov  x19, x0
    mov  w20, w1
    mov  x21, x2
    mov  x22, x3
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
    mov  x0, x19
    ADRL x1, _g_fs_tok
    bl   _fs_w
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
    mov  x0, x19
    mov  w1, w20
    bl   _fs_wc
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
    mov  x0, x19
    ldr  x1, [x19, #CT_ROOT]
    bl   _fs_wnum
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
    CTA  x23, CT_PATH
    ldrb w9, [x23]
    cbz  w9, Lwh_name
    mov  x0, x19
    mov  x1, x23
    bl   _fs_wurl
    cbz  x21, Lwh_slash
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
Lwh_name:
    cbz  x21, Lwh_slash
    mov  x0, x19
    mov  x1, x21
    bl   _fs_wurl
Lwh_slash:
    cbz  x22, Lwh_done
    ldrb w9, [x23]                    // the shared folder itself already ends in "/"
    orr  x9, x9, x21
    cbz  x9, Lwh_done
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
Lwh_done:
    LEAVE 16

// void _fs_reply(ctx, const char *whole_response)
_fs_reply:
    ENTER 0
    mov  x19, x0
    bl   _fs_w
    mov  x0, x19
    bl   _fs_flush
    LEAVE 0

// ===========================================================================
// Paths
// ===========================================================================

// long _fs_decode(const char *src, char *dst, size_t max) -> 1, or 0 if not allowed
//   %XX decoding; no NUL, control characters or backslashes
.globl _fs_decode
_fs_decode:
    mov  x9, #0
    sub  x2, x2, #1
Ldc_loop:
    ldrb w10, [x0], #1
    cbz  w10, Ldc_end
    cmp  w10, #'%'
    b.ne Ldc_chk
    mov  w13, #0
    mov  x14, #2
Ldc_hex:
    ldrb w11, [x0], #1
    sub  w12, w11, #'0'
    cmp  w12, #9
    b.ls Ldc_dig
    orr  w12, w11, #0x20
    sub  w12, w12, #'a'
    cmp  w12, #5
    b.hi Ldc_bad
    add  w12, w12, #10
Ldc_dig:
    lsl  w13, w13, #4
    orr  w13, w13, w12
    subs x14, x14, #1
    b.ne Ldc_hex
    mov  w10, w13
Ldc_chk:
    cmp  w10, #0x20
    b.lo Ldc_bad
    cmp  w10, #0x7F
    b.eq Ldc_bad
    cmp  w10, #'\\'
    b.eq Ldc_bad
    cmp  x9, x2
    b.hs Ldc_bad
    strb w10, [x1, x9]
    add  x9, x9, #1
    b    Ldc_loop
Ldc_end:
    strb wzr, [x1, x9]
    mov  x0, #1
    ret
Ldc_bad:
    strb wzr, [x1]
    mov  x0, #0
    ret

// long _fs_check_path(char *p) -> 1 fine (tidied in place: no leading, doubled or
//   trailing "/"), 0 if any part starts with "." (".", "..", hidden files)
.globl _fs_check_path
_fs_check_path:
    mov  x9, #0                       // read
    mov  x10, #0                      // write
Lcp_skip:
    ldrb w11, [x0, x9]
    cmp  w11, #'/'
    b.ne Lcp_part
    add  x9, x9, #1
    b    Lcp_skip
Lcp_part:
    cbz  w11, Lcp_end
    cmp  w11, #'.'
    b.eq Lcp_bad
Lcp_copy:
    ldrb w11, [x0, x9]
    cbz  w11, Lcp_end
    cmp  w11, #'/'
    b.eq Lcp_sep
    strb w11, [x0, x10]
    add  x9, x9, #1
    add  x10, x10, #1
    b    Lcp_copy
Lcp_sep:
    add  x9, x9, #1
    ldrb w11, [x0, x9]
    cmp  w11, #'/'
    b.eq Lcp_sep
    cbz  w11, Lcp_end
    mov  w12, #'/'
    strb w12, [x0, x10]
    add  x10, x10, #1
    b    Lcp_part
Lcp_end:
    strb wzr, [x0, x10]
    mov  x0, #1
    ret
Lcp_bad:
    mov  x0, #0
    ret

// long _fs_real(const char *path, char *out) -> 1 with its real path in out, 0 if missing
_fs_real:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    mov  w1, #4                       // O_RDONLY | O_NONBLOCK (a pipe mustn't hang us)
    bl   _open
    tbnz w0, #31, Lrl_no
    mov  w21, w0
    mov  w0, w21
    mov  w1, #50                      // F_GETPATH (variadic: on the stack)
    str  x20, [sp]
    bl   _fcntl
    mov  w22, w0
    mov  w0, w21
    bl   _close
    cmp  w22, #0
    cset x0, eq
    LEAVE 0
Lrl_no:
    mov  x0, #0
    LEAVE 0

// void _fs_clean_name(char *name) — just the file name: no folders, no control
//   characters or ":", never hidden, at most 200 bytes
.globl _fs_clean_name
_fs_clean_name:
    ENTER 0
    mov  x19, x0
    mov  x20, x0                      // start after the last / or \ .
    mov  x9, x0
Lcn_find:
    ldrb w10, [x9], #1
    cbz  w10, Lcn_copy0
    cmp  w10, #'/'
    b.eq Lcn_cut
    cmp  w10, #'\\'
    b.ne Lcn_find
Lcn_cut:
    mov  x20, x9
    b    Lcn_find
Lcn_copy0:
    mov  x21, #0
Lcn_copy:
    ldrb w10, [x20, x21]
    cbz  w10, Lcn_end
    cmp  w10, #0x20
    b.lo Lcn_sub
    cmp  w10, #':'
    b.eq Lcn_sub
    cmp  w10, #0x7F
    b.ne Lcn_put
Lcn_sub:
    mov  w10, #'_'
Lcn_put:
    strb w10, [x19, x21]
    add  x21, x21, #1
    cmp  x21, #200
    b.lo Lcn_copy
Lcn_end:
    cmp  x21, #200                    // cut on a character boundary
    b.lo Lcn_term
Lcn_back:
    ldrb w10, [x19, x21]
    and  w10, w10, #0xC0
    cmp  w10, #0x80
    b.ne Lcn_term
    sub  x21, x21, #1
    b    Lcn_back
Lcn_term:
    strb wzr, [x19, x21]
    ldrb w10, [x19]
    cmp  w10, #'.'
    b.ne Lcn_done
    add  x0, x19, #1                  // ".profile" -> "_.profile"
    mov  x1, x19
    add  x2, x21, #1
    bl   _memmove
    mov  w10, #'_'
    strb w10, [x19]
Lcn_done:
    LEAVE 0

// const char *_fs_rootname(long i) — "Home", or the folder's own name
_fs_rootname:
    ENTER 0
    ADRL x8, _g_fs_roots
    add  x19, x8, x0, lsl #10
    mov  x0, x19
    ADRL x1, _g_fs_home
    bl   _strcmp
    cbz  w0, Lrn_home
    mov  x0, x19
    mov  w1, #'/'
    bl   _strrchr
    cbz  x0, Lrn_whole
    ldrb w9, [x0, #1]
    cbz  w9, Lrn_whole
    add  x0, x0, #1
    LEAVE 0
Lrn_whole:
    mov  x0, x19
    LEAVE 0
Lrn_home:
    ADRL x0, Ls_home
    LEAVE 0

// const char *_fs_type(const char *path) — the Content-Type to send it with
_fs_type:
    ENTER 0
    mov  w1, #'.'
    bl   _strrchr
    cbz  x0, Lty_default
    add  x19, x0, #1
    mov  w1, #'/'
    bl   _strchr
    cbnz x0, Lty_default
    ADRL x20, Ltypes
Lty_loop:
    ldr  x1, [x20]
    cbz  x1, Lty_default
    mov  x0, x19
    bl   _strcasecmp
    cbz  w0, Lty_hit
    add  x20, x20, #16
    b    Lty_loop
Lty_hit:
    ldr  x0, [x20, #8]
    LEAVE 0
Lty_default:
    ADRL x0, Lt_bin
    LEAVE 0

// ===========================================================================
// One connection (a background thread)
// ===========================================================================

// void _fs_conn(ctx) — read the request, answer it, close, free
.globl _fs_conn
_fs_conn:
    ENTER 176                         // [96] struct stat (144)  [240] timeval
    mov  x19, x0
    ldr  x20, [x19, #CT_FD]
    mov  w9, #1                       // a browser that goes away mustn't kill the app
    str  w9, [sp, #240]
    mov  w0, w20
    mov  w1, #0xffff
    mov  w2, #0x1022                  // SO_NOSIGPIPE
    add  x3, sp, #240
    mov  w4, #4
    bl   _setsockopt
    mov  w0, w20
    mov  w1, #4                       // F_SETFL 0: blocking
    str  xzr, [sp]
    bl   _fcntl
    mov  x9, #30
    str  x9, [sp, #240]
    str  xzr, [sp, #248]
    mov  w0, w20
    mov  w1, #0xffff
    mov  w2, #0x1006                  // SO_RCVTIMEO
    add  x3, sp, #240
    mov  w4, #16
    bl   _setsockopt
    mov  w0, w20
    mov  w1, #0xffff
    mov  w2, #0x1005                  // SO_SNDTIMEO
    add  x3, sp, #240
    mov  w4, #16
    bl   _setsockopt

    mov  x21, #0                      // the request's head
Lcn2_read:
    mov  x9, #(HDR_MAX - 1)
    sub  x2, x9, x21
    cbz  x2, Lcn2_big
    CTA  x1, CT_HDR
    add  x1, x1, x21
    mov  w0, w20
    bl   _read
    cmp  x0, #0
    b.le Lcn2_close
    add  x21, x21, x0
    CTA  x8, CT_HDR
    strb wzr, [x8, x21]
    mov  x0, x8
    ADRL x1, Ls_crlf2
    bl   _strstr
    cbz  x0, Lcn2_read
    CTA  x8, CT_HDR
    sub  x9, x0, x8
    add  x9, x9, #4
    str  x9, [x19, #CT_HEND]
    str  x21, [x19, #CT_HLEN]
    CTA  x0, CT_HDR                   // the headers start at the first "\r\n"
    ADRL x1, Ls_crlf
    bl   _strstr
    str  x0, [x19, #CT_L2]
    ldr  x9, [x19, #CT_HEND]
    sub  x9, x9, #2
    CTA  x8, CT_HDR
    strb wzr, [x8, x9]

    CTA  x22, CT_HDR                  // GET or POST
    mov  x23, #1
    mov  x0, x22
    ADRL x1, Ls_GET_sp
    mov  x2, #4
    bl   _strncmp
    cbz  w0, Lcn2_target
    mov  x23, #2
    mov  x0, x22
    ADRL x1, Ls_POST_sp
    mov  x2, #5
    bl   _strncmp
    cbnz w0, Lcn2_method
Lcn2_target:
    mov  x0, x22
    mov  w1, #' '
    bl   _strchr
    cbz  x0, Lcn2_bad
    add  x24, x0, #1
    mov  x0, x24
    mov  w1, #' '
    bl   _strchr
    cbz  x0, Lcn2_bad
    strb wzr, [x0]
    ldrb w9, [x24]                    // "/<secret>…"
    cmp  w9, #'/'
    b.ne Lcn2_bad
    ADRL x8, _g_fs_tok
    ldrb w9, [x8]
    cbz  w9, Lcn2_denied
    add  x0, x24, #1
    ADRL x1, _g_fs_tok
    mov  x2, #32
    bl   _strncmp
    cbnz w0, Lcn2_denied
    ldrb w9, [x24, #33]
    cbz  w9, Lcn2_roots
    cmp  w9, #'?'
    b.eq Lcn2_roots
    cmp  w9, #'/'
    b.ne Lcn2_denied
    add  x24, x24, #34
    ldrb w9, [x24]
    cbz  w9, Lcn2_roots
    cmp  w9, #'?'
    b.eq Lcn2_roots
    mov  w22, w9                      // d (look), g (download), u (upload)
    ldrb w10, [x24, #1]
    cmp  w10, #'/'
    b.ne Lcn2_notfound
    add  x24, x24, #2
    mov  x21, #0                      // which shared folder
    mov  x10, #0
Lcn2_idx:
    ldrb w9, [x24]
    sub  w11, w9, #'0'
    cmp  w11, #9
    b.hi Lcn2_idx_end
    mov  x12, #10
    madd x21, x21, x12, x11
    add  x24, x24, #1
    add  x10, x10, #1
    cmp  x10, #3
    b.hi Lcn2_notfound
    b    Lcn2_idx
Lcn2_idx_end:
    cbz  x10, Lcn2_notfound
    cmp  w9, #'/'
    b.eq Lcn2_idx_sl
    cbz  w9, Lcn2_idx_q
    cmp  w9, #'?'
    b.eq Lcn2_idx_q
    b    Lcn2_notfound
Lcn2_idx_sl:
    add  x24, x24, #1
Lcn2_idx_q:
    ADRL x8, _g_fs_nroots
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lcn2_notfound
    str  x21, [x19, #CT_ROOT]
    cmp  w22, #'g'
    cset x9, eq
    str  x9, [x19, #CT_DL]
    mov  x0, x24                      // no "?…"
    mov  w1, #'?'
    bl   _strchr
    cbz  x0, Lcn2_decode
    strb wzr, [x0]
Lcn2_decode:
    mov  x0, x24
    CTA  x1, CT_PATH
    mov  x2, #1024
    bl   _fs_decode
    cbz  x0, Lcn2_bad
    CTA  x0, CT_PATH
    bl   _fs_check_path
    cbz  x0, Lcn2_bad
    ADRL x8, _g_fs_roots              // the shared folder, and what was asked for, for real
    add  x24, x8, x21, lsl #10
    mov  x0, x24
    CTA  x1, CT_RROOT
    bl   _fs_real
    cbz  x0, Lcn2_notfound
    str  x24, [sp]
    CTA  x9, CT_PATH
    str  x9, [sp, #8]
    CTA  x0, CT_FULL
    mov  x1, #1104
    ADRL x2, Lf_join
    bl   _snprintf
    CTA  x0, CT_FULL
    CTA  x1, CT_REAL
    bl   _fs_real
    cbz  x0, Lcn2_notfound
    CTA  x0, CT_RROOT                 // still inside the shared folder?
    bl   _strlen
    mov  x21, x0
    CTA  x0, CT_REAL
    CTA  x1, CT_RROOT
    mov  x2, x21
    bl   _strncmp
    cbnz w0, Lcn2_notfound
    CTA  x8, CT_REAL
    ldrb w9, [x8, x21]
    cbz  w9, Lcn2_lib
    cmp  w9, #'/'
    b.ne Lcn2_notfound
Lcn2_lib:
    CTA  x0, CT_RROOT                 // the home folder's Library never shows
    ADRL x1, _g_fs_home
    bl   _strcmp
    cbnz w0, Lcn2_stat
    CTA  x0, CT_PATH
    ADRL x1, Ls_Library
    mov  x2, #7
    bl   _strncasecmp
    cbnz w0, Lcn2_stat
    CTA  x8, CT_PATH
    ldrb w9, [x8, #7]
    cbz  w9, Lcn2_notfound
    cmp  w9, #'/'
    b.eq Lcn2_notfound
Lcn2_stat:
    CTA  x0, CT_REAL
    add  x1, sp, #96
    bl   _stat
    cbnz w0, Lcn2_notfound
    ldrh w9, [sp, #100]               // st_mode
    and  w9, w9, #0xF000
    cmp  x23, #2
    b.eq Lcn2_post
    cmp  w22, #'u'
    b.eq Lcn2_method
    cmp  w9, #0x4000
    b.eq Lcn2_dir
    cmp  w9, #0x8000
    b.ne Lcn2_notfound
    mov  x0, x19
    bl   _fs_send_file
    b    Lcn2_close
Lcn2_dir:
    mov  x0, x19
    bl   _fs_page_dir
    b    Lcn2_close
Lcn2_post:
    cmp  w22, #'u'
    b.ne Lcn2_method
    cmp  w9, #0x4000
    b.ne Lcn2_notfound
    mov  x0, x19
    bl   _fs_upload
    b    Lcn2_close
Lcn2_roots:
    cmp  x23, #1
    b.ne Lcn2_method
    mov  x0, x19
    bl   _fs_page_roots
    b    Lcn2_close
Lcn2_big:
    mov  x0, x19
    ADRL x1, Ls_r431
    bl   _fs_reply
    b    Lcn2_close
Lcn2_method:
    mov  x0, x19
    ADRL x1, Ls_r405
    bl   _fs_reply
    b    Lcn2_close
Lcn2_denied:
    mov  x0, x19
    ADRL x1, Ls_r403
    bl   _fs_reply
    b    Lcn2_close
Lcn2_notfound:
    mov  x0, x19
    ADRL x1, Ls_r404
    bl   _fs_reply
    b    Lcn2_close
Lcn2_bad:
    mov  x0, x19
    ADRL x1, Ls_r400
    bl   _fs_reply
Lcn2_close:
    mov  x0, x19
    bl   _fs_flush
    mov  w0, w20
    bl   _close
    mov  x0, x19
    bl   _free
    LEAVE 176

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------

// the shared folders
_fs_page_roots:
    ENTER 0
    mov  x19, x0
    mov  x0, x19
    ADRL x1, Ls_h200
    bl   _fs_w
    mov  x0, x19
    ADRL x1, Ls_head
    bl   _fs_w
    mov  x0, x19
    ADRL x1, Ls_roots_top
    bl   _fs_w
    mov  x20, #0
Lpr_loop:
    ADRL x8, _g_fs_nroots
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lpr_end
    str  x20, [x19, #CT_ROOT]
    CTA  x8, CT_PATH
    strb wzr, [x8]
    mov  x0, x19
    ADRL x1, Ls_li_dir
    bl   _fs_w
    mov  x0, x19
    mov  w1, #'d'
    mov  x2, #0
    mov  x3, #1
    bl   _fs_whref
    mov  x0, x19
    ADRL x1, Ls_a_mid
    bl   _fs_w
    mov  x0, x20
    bl   _fs_rootname
    mov  x1, x0
    mov  x0, x19
    bl   _fs_wesc
    mov  x0, x19
    ADRL x1, Ls_a_end
    bl   _fs_w
    add  x20, x20, #1
    b    Lpr_loop
Lpr_end:
    mov  x0, x19
    ADRL x1, Ls_roots_end
    bl   _fs_w
    LEAVE 0

// a folder: its folders, then its files, then the upload form
_fs_page_dir:
    ENTER 176                         // [96] stat  [240] list  [248] count  [256] shown
    mov  x19, x0
    mov  x0, x19
    ADRL x1, Ls_h200
    bl   _fs_w
    mov  x0, x19
    ADRL x1, Ls_head
    bl   _fs_w
    mov  x0, x19                      // back: the folder above, or the list of folders
    ADRL x1, Ls_up_a
    bl   _fs_w
    CTA  x20, CT_PATH
    ldrb w9, [x20]
    cbnz w9, Lpd_parent
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
    mov  x0, x19
    ADRL x1, _g_fs_tok
    bl   _fs_w
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
    b    Lpd_title
Lpd_parent:
    mov  x0, x20
    mov  w1, #'/'
    bl   _strrchr
    mov  x21, x0
    mov  x22, x20
    cbz  x21, Lpd_cut
    mov  x22, x21
Lpd_cut:
    ldrb w23, [x22]                   // cut the path at its last "/" for a moment
    strb wzr, [x22]
    mov  x0, x19
    mov  w1, #'d'
    mov  x2, #0
    mov  x3, #1
    bl   _fs_whref
    strb w23, [x22]
Lpd_title:
    mov  x0, x19
    ADRL x1, Ls_up_b
    bl   _fs_w
    ldr  x0, [x19, #CT_ROOT]
    bl   _fs_rootname
    mov  x1, x0
    mov  x0, x19
    bl   _fs_wesc
    ldrb w9, [x20]
    cbz  w9, Lpd_h1
    mov  x0, x19
    ADRL x1, Ls_slash_sp
    bl   _fs_w
    mov  x0, x19
    mov  x1, x20
    bl   _fs_wesc
Lpd_h1:
    mov  x0, x19
    ADRL x1, Ls_h1_end
    bl   _fs_w
    str  xzr, [sp, #256]
    str  xzr, [sp, #240]
    CTA  x0, CT_REAL
    add  x1, sp, #240
    mov  x2, #0
    LDGOT x3, _alphasort
    bl   _scandir
    sxtw x9, w0
    str  x9, [sp, #248]
    tbnz x9, #63, Lpd_form
    mov  x24, #0                      // pass 0: folders, pass 1: files
Lpd_pass:
    mov  x21, #0
Lpd_entry:
    ldr  x9, [sp, #248]
    cmp  x21, x9
    b.hs Lpd_pass_end
    ldr  x8, [sp, #240]
    ldr  x8, [x8, x21, lsl #3]
    add  x22, x8, #21                 // d_name
    ldrb w9, [x22]
    cmp  w9, #'.'
    b.eq Lpd_next
    ldrb w9, [x20]                    // the home folder's Library stays hidden
    cbnz w9, Lpd_stat
    CTA  x0, CT_RROOT
    ADRL x1, _g_fs_home
    bl   _strcmp
    cbnz w0, Lpd_stat
    mov  x0, x22
    ADRL x1, Ls_Library
    bl   _strcasecmp
    cbz  w0, Lpd_next
Lpd_stat:
    CTA  x9, CT_REAL
    str  x9, [sp]
    str  x22, [sp, #8]
    CTA  x0, CT_TMP
    mov  x1, #1104
    ADRL x2, Lf_join
    bl   _snprintf
    CTA  x0, CT_TMP
    add  x1, sp, #96
    bl   _stat
    cbnz w0, Lpd_next
    ldrh w9, [sp, #100]
    and  w9, w9, #0xF000
    cbnz x24, Lpd_file
    cmp  w9, #0x4000
    b.ne Lpd_next
    mov  x0, x19
    ADRL x1, Ls_li_dir
    bl   _fs_w
    mov  x0, x19
    mov  w1, #'d'
    mov  x2, x22
    mov  x3, #1
    bl   _fs_whref
    mov  x0, x19
    ADRL x1, Ls_a_mid
    bl   _fs_w
    mov  x0, x19
    mov  x1, x22
    bl   _fs_wesc
    mov  x0, x19
    ADRL x1, Ls_a_end
    bl   _fs_w
    b    Lpd_shown
Lpd_file:
    cmp  w9, #0x8000
    b.ne Lpd_next
    mov  x0, x19
    ADRL x1, Ls_li_file
    bl   _fs_w
    mov  x0, x19
    mov  w1, #'d'
    mov  x2, x22
    mov  x3, #0
    bl   _fs_whref
    mov  x0, x19
    ADRL x1, Ls_a_mid
    bl   _fs_w
    mov  x0, x19
    mov  x1, x22
    bl   _fs_wesc
    mov  x0, x19
    ADRL x1, Ls_a_size
    bl   _fs_w
    mov  x0, x19
    ldr  x1, [sp, #192]               // st_size
    bl   _fs_wsize
    mov  x0, x19
    ADRL x1, Ls_a_dl
    bl   _fs_w
    mov  x0, x19
    mov  w1, #'g'
    mov  x2, x22
    mov  x3, #0
    bl   _fs_whref
    mov  x0, x19
    ADRL x1, Ls_a_dl_end
    bl   _fs_w
Lpd_shown:
    ldr  x9, [sp, #256]
    add  x9, x9, #1
    str  x9, [sp, #256]
Lpd_next:
    add  x21, x21, #1
    b    Lpd_entry
Lpd_pass_end:
    add  x24, x24, #1
    cmp  x24, #2
    b.lo Lpd_pass
    mov  x21, #0                      // done with the list
Lpd_free:
    ldr  x9, [sp, #248]
    cmp  x21, x9
    b.hs Lpd_free_list
    ldr  x8, [sp, #240]
    ldr  x0, [x8, x21, lsl #3]
    bl   _free
    add  x21, x21, #1
    b    Lpd_free
Lpd_free_list:
    ldr  x0, [sp, #240]
    bl   _free
Lpd_form:
    ldr  x9, [sp, #256]
    cbnz x9, Lpd_form2
    mov  x0, x19
    ADRL x1, Ls_empty_dir
    bl   _fs_w
Lpd_form2:
    mov  x0, x19
    ADRL x1, Ls_form_a
    bl   _fs_w
    mov  x0, x19
    mov  w1, #'u'
    mov  x2, #0
    mov  x3, #1
    bl   _fs_whref
    mov  x0, x19
    ADRL x1, Ls_form_b
    bl   _fs_w
    LEAVE 176

// a file: all of it, or the part a video player asks for ("Range: bytes=a-b")
_fs_send_file:
    ENTER 176                         // [96] stat  [240] end pointer  [248] ranged
    mov  x19, x0
    CTA  x0, CT_REAL
    mov  w1, #4                       // O_RDONLY | O_NONBLOCK
    bl   _open
    tbnz w0, #31, Lsf_404
    mov  w20, w0
    mov  w0, w20
    add  x1, sp, #96
    bl   _fstat
    ldr  x21, [sp, #192]              // size
    mov  x22, #0                      // first byte
    sub  x23, x21, #1                 // last byte
    str  xzr, [sp, #248]
    ldr  x0, [x19, #CT_L2]
    ADRL x1, Ls_range
    bl   _strcasestr
    cbz  x0, Lsf_head
    add  x24, x0, #15                 // after "\r\nRange: bytes="
    ldrb w9, [x24]
    cmp  w9, #'-'
    b.ne Lsf_from
    add  x0, x24, #1                  // "-500": the last 500 bytes
    mov  x1, #0
    mov  w2, #10
    bl   _strtoll
    subs x22, x21, x0
    csel x22, xzr, x22, lt
    b    Lsf_ranged
Lsf_from:
    mov  x0, x24
    add  x1, sp, #240
    mov  w2, #10
    bl   _strtoll
    mov  x22, x0
    ldr  x24, [sp, #240]
    ldrb w9, [x24]
    cmp  w9, #'-'
    b.ne Lsf_416
    ldrb w9, [x24, #1]
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi Lsf_ranged
    add  x0, x24, #1
    mov  x1, #0
    mov  w2, #10
    bl   _strtoll
    cmp  x0, x23
    csel x23, x0, x23, lt
Lsf_ranged:
    tbnz x22, #63, Lsf_416
    cmp  x22, x21
    b.hs Lsf_416
    cmp  x22, x23
    b.gt Lsf_416
    mov  x9, #1
    str  x9, [sp, #248]
Lsf_head:
    ldr  x9, [sp, #248]
    ADRL x1, Ls_s200
    ADRL x10, Ls_s206
    cmp  x9, #0
    csel x1, x10, x1, ne
    mov  x0, x19
    bl   _fs_w
    mov  x0, x19
    ADRL x1, Ls_ctype
    bl   _fs_w
    CTA  x0, CT_REAL
    bl   _fs_type
    mov  x1, x0
    mov  x0, x19
    bl   _fs_w
    mov  x0, x19
    ADRL x1, Ls_clen_h
    bl   _fs_w
    sub  x1, x23, x22
    add  x1, x1, #1
    mov  x0, x19
    bl   _fs_wnum
    ldr  x9, [sp, #248]
    cbz  x9, Lsf_rest
    mov  x0, x19
    ADRL x1, Ls_crange
    bl   _fs_w
    mov  x0, x19
    mov  x1, x22
    bl   _fs_wnum
    mov  x0, x19
    mov  w1, #'-'
    bl   _fs_wc
    mov  x0, x19
    mov  x1, x23
    bl   _fs_wnum
    mov  x0, x19
    mov  w1, #'/'
    bl   _fs_wc
    mov  x0, x19
    mov  x1, x21
    bl   _fs_wnum
Lsf_rest:
    mov  x0, x19
    ADRL x1, Ls_file_hdrs
    bl   _fs_w
    ldr  x9, [x19, #CT_DL]
    cbz  x9, Lsf_end_h
    mov  x0, x19
    ADRL x1, Ls_attach
    bl   _fs_w
Lsf_end_h:
    mov  x0, x19
    ADRL x1, Ls_close_h
    bl   _fs_w
    mov  x0, x19
    bl   _fs_flush
    mov  w0, w20
    mov  x1, x22
    mov  w2, #0                       // SEEK_SET
    bl   _lseek
    sub  x21, x23, x22                // bytes to go
    add  x21, x21, #1
Lsf_loop:
    cmp  x21, #0
    b.le Lsf_done
    mov  x2, #BUF_CAP
    cmp  x21, x2
    csel x2, x21, x2, lo
    CTA  x1, CT_BUF
    mov  w0, w20
    bl   _read
    cmp  x0, #0
    b.le Lsf_done
    mov  x22, x0
    mov  x2, x0
    ldr  x0, [x19, #CT_FD]
    CTA  x1, CT_BUF
    bl   _fs_sendall
    cbnz x0, Lsf_done
    sub  x21, x21, x22
    b    Lsf_loop
Lsf_done:
    mov  w0, w20
    bl   _close
    LEAVE 176
Lsf_416:
    mov  w0, w20
    bl   _close
    mov  x0, x19
    ADRL x1, Ls_r416
    bl   _fs_reply
    LEAVE 176
Lsf_404:
    mov  x0, x19
    ADRL x1, Ls_r404
    bl   _fs_reply
    LEAVE 176

// ---------------------------------------------------------------------------
// Uploads (multipart/form-data, read as it arrives: any size)
// ---------------------------------------------------------------------------

// long _fs_fill(ctx) -> bytes added to the buffer (0: no more)
_fs_fill:
    ENTER 0
    mov  x19, x0
    ldr  x9, [x19, #CT_BL]
    mov  x10, #BUF_CAP
    sub  x2, x10, x9
    ldr  x11, [x19, #CT_LEFT]
    cmp  x11, x2
    csel x2, x11, x2, lo
    cbz  x2, Lfi_none
    CTA  x1, CT_BUF
    add  x1, x1, x9
    ldr  x0, [x19, #CT_FD]
    bl   _read
    cmp  x0, #0
    b.le Lfi_none
    ldr  x9, [x19, #CT_BL]
    add  x9, x9, x0
    str  x9, [x19, #CT_BL]
    ldr  x9, [x19, #CT_LEFT]
    sub  x9, x9, x0
    str  x9, [x19, #CT_LEFT]
    LEAVE 0
Lfi_none:
    mov  x0, #0
    LEAVE 0

// void _fs_eat(ctx, size_t n) — drop n bytes from the front of the buffer
_fs_eat:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ldr  x21, [x19, #CT_BL]
    sub  x21, x21, x20
    CTA  x0, CT_BUF
    add  x1, x0, x20
    mov  x2, x21
    bl   _memmove
    str  x21, [x19, #CT_BL]
    LEAVE 0

// long _fs_open_new(ctx) -> a new file for CT_NAME in the folder (never replacing one:
//   "photo (2).jpg"), its path in CT_FULL; -1 if none can be made
_fs_open_new:
    ENTER 32
    mov  x19, x0
    mov  x20, #1
    CTA  x0, CT_NAME
    mov  w1, #'.'
    bl   _strrchr
    CTA  x9, CT_NAME
    sub  x21, x0, x9                  // where the extension starts (<= 0: none)
    cbnz x0, Lon_try
    mov  x21, #0
Lon_try:
    CTA  x9, CT_REAL
    str  x9, [sp]
    CTA  x9, CT_NAME
    str  x9, [sp, #8]
    ADRL x2, Lf_join
    cmp  x20, #1
    b.eq Lon_fmt
    str  x20, [sp, #16]
    ADRL x2, Lf_join_n
    cmp  x21, #0
    b.le Lon_fmt
    CTA  x9, CT_NAME                  // "name (2).ext": split at the dot for a moment
    strb wzr, [x9, x21]
    add  x10, x9, x21
    add  x10, x10, #1
    str  x10, [sp, #24]
    ADRL x2, Lf_join_ne
Lon_fmt:
    CTA  x0, CT_FULL
    mov  x1, #1104
    bl   _snprintf
    cmp  x21, #0
    b.le Lon_open
    CTA  x9, CT_NAME
    mov  w10, #'.'
    strb w10, [x9, x21]
Lon_open:
    CTA  x0, CT_FULL
    mov  w1, #0xA01                   // O_WRONLY | O_CREAT | O_EXCL
    mov  x9, #0644
    str  x9, [sp]
    bl   _open
    tbz  w0, #31, Lon_ok
    add  x20, x20, #1
    cmp  x20, #99
    b.ls Lon_try
    mov  x0, #-1
    LEAVE 32
Lon_ok:
    sxtw x0, w0
    LEAVE 32

// void _fs_upload(ctx)
_fs_upload:
    ENTER 32
    mov  x19, x0
    mov  x9, #-1
    str  x9, [x19, #CT_FFD]
    str  xzr, [x19, #CT_NUP]
    ldr  x0, [x19, #CT_L2]            // boundary=…
    ADRL x1, Ls_h_ctype
    bl   _strcasestr
    cbz  x0, Lup_bad
    mov  x20, x0
    add  x0, x20, #2
    ADRL x1, Ls_crlf
    bl   _strstr
    mov  x21, x0                      // end of that line (0: last)
    mov  x0, x20
    ADRL x1, Ls_boundary
    bl   _strcasestr
    cbz  x0, Lup_bad
    cbz  x21, Lup_bnd
    cmp  x0, x21
    b.hs Lup_bad
Lup_bnd:
    add  x20, x0, #9
    ldrb w9, [x20]
    cmp  w9, #'"'
    b.ne Lup_bcopy0
    add  x20, x20, #1
Lup_bcopy0:
    CTA  x8, CT_BOUND
    mov  w9, #0x0A0D                  // "\r\n--"
    movk w9, #0x2D2D, lsl #16
    str  w9, [x8]
    mov  x10, #4
Lup_bcopy:
    ldrb w9, [x20], #1
    cbz  w9, Lup_bend
    cmp  w9, #'"'
    b.eq Lup_bend
    cmp  w9, #';'
    b.eq Lup_bend
    cmp  w9, #' '
    b.eq Lup_bend
    cmp  w9, #'\r'
    b.eq Lup_bend
    cmp  x10, #74
    b.hs Lup_bad
    strb w9, [x8, x10]
    add  x10, x10, #1
    b    Lup_bcopy
Lup_bend:
    cmp  x10, #4
    b.ls Lup_bad
    strb wzr, [x8, x10]
    str  x10, [x19, #CT_BLEN]
    ldr  x0, [x19, #CT_L2]            // how much is coming
    ADRL x1, Ls_h_clen
    bl   _strcasestr
    cbz  x0, Lup_411
    add  x0, x0, #17
    bl   _atol
    cmp  x0, #0
    b.le Lup_bad
    str  x0, [x19, #CT_CLEN]
    ldr  x9, [x19, #CT_HLEN]          // what already came with the headers
    ldr  x10, [x19, #CT_HEND]
    sub  x2, x9, x10
    cmp  x2, x0
    csel x2, x0, x2, hi
    str  x2, [x19, #CT_BL]
    sub  x9, x0, x2
    str  x9, [x19, #CT_LEFT]
    CTA  x0, CT_BUF
    CTA  x1, CT_HDR
    add  x1, x1, x10
    bl   _memcpy

Lup_pre:                              // the first "--boundary"
    CTA  x0, CT_BUF
    ldr  x1, [x19, #CT_BL]
    CTA  x2, CT_BOUND
    add  x2, x2, #2
    ldr  x3, [x19, #CT_BLEN]
    sub  x3, x3, #2
    bl   _memmem
    cbz  x0, Lup_pre_more
    CTA  x9, CT_BUF
    sub  x1, x0, x9
    ldr  x9, [x19, #CT_BLEN]
    add  x1, x1, x9
    sub  x1, x1, #2
    mov  x0, x19
    bl   _fs_eat
    b    Lup_after
Lup_pre_more:
    ldr  x9, [x19, #CT_BL]
    ldr  x10, [x19, #CT_BLEN]
    cmp  x9, x10
    b.ls Lup_pre_fill
    sub  x1, x9, x10
    mov  x0, x19
    bl   _fs_eat
Lup_pre_fill:
    mov  x0, x19
    bl   _fs_fill
    cbz  x0, Lup_bad
    b    Lup_pre

Lup_after:                            // "--" the end, or "\r\n" another part
    ldr  x9, [x19, #CT_BL]
    cmp  x9, #2
    b.hs Lup_after2
    mov  x0, x19
    bl   _fs_fill
    cbz  x0, Lup_bad
    b    Lup_after
Lup_after2:
    CTA  x8, CT_BUF
    ldrh w9, [x8]
    mov  w10, #0x2D2D                 // "--"
    cmp  w9, w10
    b.eq Lup_done
    mov  w10, #0x0A0D                 // "\r\n"
    cmp  w9, w10
    b.ne Lup_bad
    mov  x0, x19
    mov  x1, #2
    bl   _fs_eat

Lup_hdrs:                             // the part's headers, up to a blank line
    CTA  x0, CT_BUF
    ldr  x1, [x19, #CT_BL]
    ADRL x2, Ls_crlf2
    mov  x3, #4
    bl   _memmem
    cbnz x0, Lup_hdrs_ok
    ldr  x9, [x19, #CT_BL]
    mov  x10, #BUF_CAP
    cmp  x9, x10
    b.hs Lup_bad
    mov  x0, x19
    bl   _fs_fill
    cbz  x0, Lup_bad
    b    Lup_hdrs
Lup_hdrs_ok:
    mov  x20, x0
    strb wzr, [x20]
    CTA  x8, CT_NAME
    strb wzr, [x8]
    CTA  x0, CT_BUF
    ADRL x1, Ls_filename
    bl   _strcasestr
    cbz  x0, Lup_hdrs_eat
    add  x9, x0, #10
    CTA  x8, CT_NAME
    mov  x10, #0
Lup_name:
    ldrb w11, [x9, x10]
    cbz  w11, Lup_name_end
    cmp  w11, #'"'
    b.eq Lup_name_end
    cmp  x10, #255
    b.hs Lup_name_end
    strb w11, [x8, x10]
    add  x10, x10, #1
    b    Lup_name
Lup_name_end:
    strb wzr, [x8, x10]
Lup_hdrs_eat:
    CTA  x9, CT_BUF
    sub  x1, x20, x9
    add  x1, x1, #4
    mov  x0, x19
    bl   _fs_eat
    CTA  x0, CT_NAME
    bl   _fs_clean_name
    CTA  x8, CT_NAME
    ldrb w9, [x8]
    cbz  w9, Lup_data                 // not a file (or none chosen): skip its data
    mov  x0, x19
    bl   _fs_open_new
    str  x0, [x19, #CT_FFD]
    tbnz x0, #63, Lup_bad

Lup_data:                             // the file, up to "\r\n--boundary"
    CTA  x0, CT_BUF
    ldr  x1, [x19, #CT_BL]
    CTA  x2, CT_BOUND
    ldr  x3, [x19, #CT_BLEN]
    bl   _memmem
    cbz  x0, Lup_data_more
    CTA  x9, CT_BUF
    sub  x20, x0, x9
    mov  x0, x19
    mov  x1, x20
    bl   _fs_put
    cbnz x0, Lup_bad
    ldr  x0, [x19, #CT_FFD]
    tbnz x0, #63, Lup_data_eat
    bl   _close
    mov  x9, #-1
    str  x9, [x19, #CT_FFD]
    ldr  x9, [x19, #CT_NUP]
    add  x9, x9, #1
    str  x9, [x19, #CT_NUP]
Lup_data_eat:
    ldr  x9, [x19, #CT_BLEN]
    add  x1, x20, x9
    mov  x0, x19
    bl   _fs_eat
    b    Lup_after
Lup_data_more:
    ldr  x9, [x19, #CT_BL]            // keep enough to spot a boundary split across reads
    ldr  x10, [x19, #CT_BLEN]
    sub  x10, x10, #1
    cmp  x9, x10
    b.ls Lup_data_fill
    sub  x20, x9, x10
    mov  x0, x19
    mov  x1, x20
    bl   _fs_put
    cbnz x0, Lup_bad
    mov  x0, x19
    mov  x1, x20
    bl   _fs_eat
Lup_data_fill:
    mov  x0, x19
    bl   _fs_fill
    cbz  x0, Lup_bad
    b    Lup_data

Lup_done:
    ldr  x9, [x19, #CT_NUP]
    cbz  x9, Lup_redirect
    mov  x0, x19
    bl   _fs_note_up
Lup_redirect:                         // back to the folder, showing the new files
    mov  x0, x19
    ADRL x1, Ls_r303a
    bl   _fs_w
    mov  x0, x19
    mov  w1, #'d'
    mov  x2, #0
    mov  x3, #1
    bl   _fs_whref
    mov  x0, x19
    ADRL x1, Ls_r303b
    bl   _fs_w
    mov  x0, x19
    bl   _fs_flush
    LEAVE 32
Lup_411:
    mov  x0, x19
    ADRL x1, Ls_r411
    bl   _fs_reply
    LEAVE 32
Lup_bad:                              // a half-written file isn't kept
    ldr  x0, [x19, #CT_FFD]
    tbnz x0, #63, Lup_bad2
    bl   _close
    CTA  x0, CT_FULL
    bl   _unlink
    mov  x9, #-1
    str  x9, [x19, #CT_FFD]
Lup_bad2:
    ldr  x9, [x19, #CT_NUP]
    cbz  x9, Lup_bad3
    mov  x0, x19
    bl   _fs_note_up
Lup_bad3:
    mov  x0, x19
    ADRL x1, Ls_r400
    bl   _fs_reply
    LEAVE 32

// long _fs_put(ctx, size_t n) — the first n buffered bytes into the file being
//   uploaded (if any) -> 0 ok, -1 couldn't write (disk full…)
_fs_put:
    ENTER 0
    mov  x19, x0
    mov  x2, x1
    ldr  x0, [x19, #CT_FFD]
    tbnz x0, #63, Lpu_ok
    cbz  x2, Lpu_ok
    CTA  x1, CT_BUF
    bl   _fs_sendall
    LEAVE 0
Lpu_ok:
    mov  x0, #0
    LEAVE 0

// void _fs_note_up(ctx) — tell the Home room (on the main thread)
_fs_note_up:
    ENTER 32
    mov  x19, x0
    ldr  x20, [x19, #CT_NUP]
    ldr  x0, [x19, #CT_ROOT]
    bl   _fs_rootname
    str  x20, [sp]
    ADRL x9, Ls_s
    ADRL x10, Ls_empty
    cmp  x20, #1
    csel x9, x10, x9, eq
    str  x9, [sp, #8]
    str  x0, [sp, #16]
    CTA  x0, CT_TMP
    mov  x1, #300
    ADRL x2, Lf_note_up
    bl   _snprintf
    CTA  x0, CT_TMP
    bl   _strdup
    cbz  x0, Lnu_done
    mov  x1, x0
    LDGOT x0, __dispatch_main_q
    ADRL x2, _fs_note_main
    bl   _dispatch_async_f
Lnu_done:
    LEAVE 32

_fs_note_main:
    ENTER 0
    mov  x19, x0
    bl   _home_say0
    mov  x0, x19
    bl   _free
    LEAVE 0

// ===========================================================================
// The Mac side: switch on/off, commands, the QR window, AirDrop
// ===========================================================================

// Files on Wi-Fi switched on: a secret, the folders, then listen
.globl _files_start
_files_start:
    ENTER 32                          // [96] sockaddr_in  [112] one
    ADRL x0, Ls_pref_tok
    ADRL x1, _g_fs_tok
    mov  x2, #40
    bl   _pref_get
    ADRL x8, _g_fs_tok
    ldrb w9, [x8]
    cbnz w9, Lfs_roots
    ADRL x0, _g_fs_tok
    mov  x1, #16
    bl   _al_random_hex
    ADRL x0, Ls_pref_tok
    ADRL x1, _g_fs_tok
    bl   _pref_set
Lfs_roots:
    ADRL x0, Ls_HOME
    bl   _getenv
    cbz  x0, Lfs_noh
    ADRL x1, _g_fs_home
    bl   _fs_real
Lfs_noh:
    bl   _fs_load_roots
    ADRL x8, _g_fs_fd
    ldr  x9, [x8]
    tbz  x9, #63, Lfs_show
    mov  w0, #2                       // AF_INET, SOCK_STREAM
    mov  w1, #1
    mov  w2, #0
    bl   _socket
    tbnz w0, #31, Lfs_fail
    mov  w19, w0
    mov  w9, #1
    str  w9, [sp, #112]
    mov  w0, w19
    mov  w1, #0xffff
    mov  w2, #4                       // SO_REUSEADDR
    add  x3, sp, #112
    mov  w4, #4
    bl   _setsockopt
    stp  xzr, xzr, [sp, #96]
    mov  w9, #0x0210
    strh w9, [sp, #96]
    mov  w9, #FS_PORT
    rev16 w9, w9
    strh w9, [sp, #98]
    mov  w0, w19
    add  x1, sp, #96
    mov  w2, #16
    bl   _bind
    cbnz w0, Lfs_close
    mov  w0, w19
    mov  w1, #16
    bl   _listen
    cbnz w0, Lfs_close
    mov  w0, w19
    mov  w1, #4                       // F_SETFL O_NONBLOCK (on the stack)
    mov  x9, #4
    str  x9, [sp]
    bl   _fcntl
    ADRL x8, _g_fs_fd
    sxtw x9, w19
    str  x9, [x8]
    LDGOT x0, __dispatch_source_type_read
    sxtw x1, w19
    mov  x2, #0
    LDGOT x3, __dispatch_main_q
    bl   _dispatch_source_create
    cbz  x0, Lfs_show
    mov  x20, x0
    ADRL x8, _g_fs_src
    str  x20, [x8]
    mov  x0, x20
    ADRL x1, _fs_accept
    bl   _dispatch_source_set_event_handler_f
    mov  x0, x20
    bl   _dispatch_resume
Lfs_show:
    ADRL x8, _g_svc_boot              // at launch: quietly
    ldr  x9, [x8]
    cbnz x9, Lfs_done
    bl   _h_files
Lfs_done:
    LEAVE 32
Lfs_close:
    mov  w0, w19
    bl   _close
Lfs_fail:
    ADRL x0, Ls_fs_fail
    bl   _home_say0
    LEAVE 32

// Files on Wi-Fi switched off: stop listening
.globl _files_stop
_files_stop:
    ENTER 0
    ADRL x8, _g_fs_src
    ldr  x0, [x8]
    cbz  x0, Lfst_fd
    str  xzr, [x8]
    bl   _dispatch_source_cancel
Lfst_fd:
    ADRL x8, _g_fs_fd
    ldr  x0, [x8]
    tbnz x0, #63, Lfst_win
    mov  x9, #-1
    str  x9, [x8]
    bl   _close
Lfst_win:
    ADRL x8, _g_fs_qrwin
    ldr  x0, [x8]
    cbz  x0, Lfst_done
    MSG0 Ls_orderOut
Lfst_done:
    LEAVE 0

// someone is knocking: hand the connection to a background thread
_fs_accept:
    ENTER 0
    ADRL x8, _g_fs_fd
    ldr  x0, [x8]
    tbnz x0, #63, Lfa_done
    mov  x1, #0
    mov  x2, #0
    bl   _accept
    tbnz w0, #31, Lfa_done
    mov  w19, w0
    mov  x0, #1
    MOVI x1, CT_SIZE
    bl   _calloc
    cbz  x0, Lfa_close
    mov  x20, x0
    sxtw x9, w19
    str  x9, [x20, #CT_FD]
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, x20
    ADRL x2, _fs_conn
    bl   _dispatch_async_f
    LEAVE 0
Lfa_close:
    mov  w0, w19
    bl   _close
Lfa_done:
    LEAVE 0

// the shared folders from the settings ("a\nb\n…"); the first time, a new folder
//   "asmmesh Files" in your home folder
_fs_load_roots:
    ENTER 0
    ADRL x8, _g_fs_nroots
    str  xzr, [x8]
    ADRL x0, Ls_pref_dirs
    ADRL x1, _g_fs_pref
    mov  x2, #8400
    bl   _pref_get
    ADRL x19, _g_fs_pref
Llr_line:
    ldrb w9, [x19]
    cbz  w9, Llr_end
    mov  x0, x19
    mov  w1, #'\n'
    bl   _strchr
    mov  x20, x0
    cbz  x20, Llr_add
    strb wzr, [x20]
Llr_add:
    ldrb w9, [x19]
    cbz  w9, Llr_next
    ADRL x8, _g_fs_nroots
    ldr  x21, [x8]
    cmp  x21, #NROOT_MAX
    b.hs Llr_end
    ADRL x8, _g_fs_roots
    add  x0, x8, x21, lsl #10
    mov  x1, x19
    mov  x2, #ROOT_LEN
    bl   _strlcpy
    ADRL x8, _g_fs_nroots
    add  x21, x21, #1
    str  x21, [x8]
Llr_next:
    cbz  x20, Llr_end
    add  x19, x20, #1
    b    Llr_line
Llr_end:
    ADRL x8, _g_fs_nroots
    ldr  x9, [x8]
    cbnz x9, Llr_done
    ADRL x0, Ls_HOME                  // nothing chosen yet: ~/asmmesh Files
    bl   _getenv
    cbz  x0, Llr_done
    str  x0, [sp]
    ADRL x0, _g_fs_roots
    mov  x1, #ROOT_LEN
    ADRL x2, Lf_default_dir
    bl   _snprintf
    ADRL x0, _g_fs_roots
    mov  w1, #0755
    bl   _mkdir
    ADRL x8, _g_fs_nroots
    mov  x9, #1
    str  x9, [x8]
    bl   _fs_save_roots
Llr_done:
    LEAVE 0

// save the shared folders
_fs_save_roots:
    ENTER 0
    ADRL x0, _g_fs_pref
    strb wzr, [x0]
    mov  x19, #0
Lsr_loop:
    ADRL x8, _g_fs_nroots
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lsr_save
    cbz  x19, Lsr_add
    ADRL x0, _g_fs_pref
    ADRL x1, Ls_nl
    mov  x2, #8400
    bl   _strlcat
Lsr_add:
    ADRL x8, _g_fs_roots
    add  x1, x8, x19, lsl #10
    ADRL x0, _g_fs_pref
    mov  x2, #8400
    bl   _strlcat
    add  x19, x19, #1
    b    Lsr_loop
Lsr_save:
    ADRL x0, Ls_pref_dirs
    ADRL x1, _g_fs_pref
    bl   _pref_set
    LEAVE 0

// void _fs_make_url(void) — "http://192.168.1.20:8788/<secret>/" in _g_fs_url
_fs_make_url:
    ENTER 16                          // [96] ifaddrs list
    ADRL x8, _g_fs_ip
    strb wzr, [x8]
    add  x0, sp, #96
    bl   _getifaddrs
    cbnz w0, Lmu_host
    ldr  x19, [sp, #96]
Lmu_loop:
    cbz  x19, Lmu_free
    ldr  w9, [x19, #16]               // flags: up, not loopback
    tst  w9, #1
    b.eq Lmu_next
    tst  w9, #8
    b.ne Lmu_next
    ldr  x20, [x19, #24]              // address
    cbz  x20, Lmu_next
    ldrb w9, [x20, #1]
    cmp  w9, #2                       // AF_INET
    b.ne Lmu_next
    ldr  x0, [x19, #8]                // prefer en0, en1…
    ldrb w9, [x0]
    cmp  w9, #'e'
    b.ne Lmu_other
    ldrb w9, [x0, #1]
    cmp  w9, #'n'
    b.ne Lmu_other
    mov  w0, #2
    add  x1, x20, #4
    ADRL x2, _g_fs_ip
    mov  w3, #48
    bl   _inet_ntop
    b    Lmu_free
Lmu_other:
    ADRL x8, _g_fs_ip
    ldrb w9, [x8]
    cbnz w9, Lmu_next
    mov  w0, #2
    add  x1, x20, #4
    ADRL x2, _g_fs_ip
    mov  w3, #48
    bl   _inet_ntop
Lmu_next:
    ldr  x19, [x19]
    b    Lmu_loop
Lmu_free:
    ldr  x0, [sp, #96]
    bl   _freeifaddrs
Lmu_host:
    ADRL x8, _g_fs_ip
    ldrb w9, [x8]
    cbnz w9, Lmu_fmt
    ADRL x0, _g_fs_ip                 // no address: this Mac's .local name
    mov  x1, #40
    bl   _gethostname
    ADRL x8, _g_fs_ip
    strb wzr, [x8, #39]
    ADRL x0, _g_fs_ip
    mov  w1, #'.'
    bl   _strchr
    cbnz x0, Lmu_fmt
    ADRL x0, _g_fs_ip
    ADRL x1, Ls_dot_local
    mov  x2, #48
    bl   _strlcat
Lmu_fmt:
    ADRL x9, _g_fs_ip
    str  x9, [sp]
    ADRL x9, _g_fs_tok
    str  x9, [sp, #8]
    ADRL x0, _g_fs_url
    mov  x1, #200
    ADRL x2, Lf_url
    bl   _snprintf
    LEAVE 16

// "files" — the address, the folders, the QR code (and the link to your phone)
.globl _h_files
_h_files:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lhf_done
    mov  x0, #SVC_FILES
    bl   _svc_gate
    cbz  x0, Lhf_done
    bl   _fs_make_url
    ADRL x1, _g_fs_url
    ADRL x0, Lf_files_on
    bl   _home_say
    mov  x19, #0
Lhf_roots:
    ADRL x8, _g_fs_nroots
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lhf_how
    ADRL x8, _g_fs_roots
    add  x1, x8, x19, lsl #10
    ADRL x0, Lf_files_root
    bl   _home_say
    add  x19, x19, #1
    b    Lhf_roots
Lhf_how:
    ADRL x0, Ls_files_how
    bl   _home_say0
    mov  x0, #SVC_NTFY                // and the link on your phone, to tap
    bl   _svc_on
    mov  x19, x0
    mov  x0, #SVC_PUSHOVER
    bl   _svc_on
    orr  x19, x19, x0
    cbz  x19, Lhf_qr
    ADRL x0, _g_fs_url
    mov  x1, #0
    bl   _push_all
    ADRL x0, Ls_files_pushed
    bl   _home_say0
Lhf_qr:
    ADRL x0, _g_fs_url
    bl   _fs_qr_show
Lhf_done:
    LEAVE 0

// "files new" — a new secret; the old address stops working
.globl _h_files_new
_h_files_new:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lhn3_done
    mov  x0, #SVC_FILES
    bl   _svc_gate
    cbz  x0, Lhn3_done
    ADRL x0, _g_fs_tok
    mov  x1, #16
    bl   _al_random_hex
    ADRL x0, Ls_pref_tok
    ADRL x1, _g_fs_tok
    bl   _pref_set
    ADRL x0, Ls_files_newtok
    bl   _home_say0
    bl   _h_files
Lhn3_done:
    LEAVE 0

// "share folders" / Mesh › Share Folders on Wi-Fi… — pick up to eight folders
.globl _h_files_choose
_h_files_choose:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lhc2_done
    mov  x0, #SVC_FILES
    bl   _svc_gate
    cbz  x0, Lhc2_done
    CLS  Ls_NSOpenPanel
    MSG0 Ls_openPanel
    cbz  x0, Lhc2_done
    mov  x19, x0
    mov  x0, x19
    mov  x2, #0
    MSG1 Ls_setCanChooseFiles
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setCanChooseDirectories
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setAllowsMultipleSelection
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setCanCreateDirectories
    ADRL x0, Ls_share_prompt
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setPrompt
    ADRL x0, Ls_share_msg
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setMessage
    bl   _fs_activate
    mov  x0, x19
    MSG0 Ls_runModal
    cmp  x0, #1                       // NSModalResponseOK
    b.ne Lhc2_done
    mov  x0, x19
    MSG0 Ls_URLs
    mov  x20, x0
    MSG0 Ls_count
    mov  x21, x0
    cbz  x21, Lhc2_done
    cmp  x21, #NROOT_MAX
    mov  x9, #NROOT_MAX
    csel x21, x9, x21, hi
    mov  x22, #0
Lhc2_loop:
    cmp  x22, x21
    b.hs Lhc2_save
    mov  x0, x20
    mov  x2, x22
    MSG1 Ls_objectAtIndex
    MSG0 Ls_path
    MSG0 Ls_UTF8String
    mov  x1, x0
    ADRL x8, _g_fs_roots
    add  x0, x8, x22, lsl #10
    mov  x2, #ROOT_LEN
    bl   _strlcpy
    add  x22, x22, #1
    b    Lhc2_loop
Lhc2_save:
    ADRL x8, _g_fs_nroots
    str  x21, [x8]
    bl   _fs_save_roots
    bl   _h_files
Lhc2_done:
    LEAVE 0

// "airdrop" / Mesh › AirDrop a File… — pick files, then AirDrop shows who's near
.globl _h_airdrop
_h_airdrop:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lad_done
    CLS  Ls_NSOpenPanel
    MSG0 Ls_openPanel
    cbz  x0, Lad_done
    mov  x19, x0
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setCanChooseFiles
    mov  x0, x19
    mov  x2, #0
    MSG1 Ls_setCanChooseDirectories
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setAllowsMultipleSelection
    ADRL x0, Ls_ad_prompt
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setPrompt
    bl   _fs_activate
    mov  x0, x19
    MSG0 Ls_runModal
    cmp  x0, #1
    b.ne Lad_done
    mov  x0, x19
    MSG0 Ls_URLs
    mov  x20, x0
    LDGOT x8, _NSSharingServiceNameSendViaAirDrop
    ldr  x2, [x8]
    CLS  Ls_NSSharingService
    MSG1 Ls_sharingServiceNamed
    cbz  x0, Lad_none
    mov  x21, x0
    mov  x0, x21
    mov  x2, x20
    MSG1 Ls_canPerformWithItems
    tst  w0, #0xff
    b.eq Lad_none
    mov  x0, x21
    mov  x2, x20
    MSG1 Ls_performWithItems
    ADRL x0, Ls_ad_open
    bl   _home_say0
    LEAVE 0
Lad_none:
    ADRL x0, Ls_ad_none
    bl   _home_say0
Lad_done:
    LEAVE 0

// bring asmmesh to the front (so a panel or window isn't hidden behind others)
_fs_activate:
    ENTER 0
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    LEAVE 0

// void _fs_qr_show(const char *text) — a small window with the text as a QR code
_fs_qr_show:
    ENTER 80                          // [96] transform (48)  [144] size
    mov  x19, x0
    CLS  Ls_CIFilter
    mov  x20, x0
    ADRL x0, Ls_qrgen
    bl   _nsstr
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_filterWithName
    cbz  x0, Lqr_done
    mov  x20, x0
    mov  x0, x19
    bl   _nsstr
    mov  x2, #4                       // UTF-8
    MSG1 Ls_dataUsingEncoding
    mov  x21, x0
    ADRL x0, Ls_inputMessage
    bl   _nsstr
    mov  x3, x0
    mov  x0, x20
    mov  x2, x21
    MSG2 Ls_setValueForKey
    ADRL x0, Ls_M
    bl   _nsstr
    mov  x21, x0
    ADRL x0, Ls_inputCorrection
    bl   _nsstr
    mov  x3, x0
    mov  x0, x20
    mov  x2, x21
    MSG2 Ls_setValueForKey
    mov  x0, x20
    MSG0 Ls_outputImage
    cbz  x0, Lqr_done
    mov  x21, x0
    mov  x0, x21                      // scale it up to about 250 points, whole pixels
    MSG0 Ls_extent
    LDD  d1, Lc_250
    fdiv d0, d1, d2
    frintm d0, d0
    fmov d1, #1.0
    fmax d0, d0, d1
    LDD  d1, Lc_0
    stp  d0, d1, [sp, #96]            // a, b
    stp  d1, d0, [sp, #112]           // c, d
    stp  d1, d1, [sp, #128]           // tx, ty
    mov  x0, x21
    add  x2, sp, #96                  // (a 48-byte struct goes by address)
    MSG1 Ls_imageByApplyingTransform
    mov  x21, x0
    CLS  Ls_NSCIImageRep
    mov  x2, x21
    MSG1 Ls_imageRepWithCIImage
    cbz  x0, Lqr_done
    mov  x21, x0
    MSG0 Ls_size
    stp  d0, d1, [sp, #144]
    CLS  Ls_NSImage
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithSize
    mov  x0, x22
    ldp  d0, d1, [sp, #144]
    bl   _objc_msgSend
    mov  x22, x0
    mov  x2, x21
    MSG1 Ls_addRepresentation

    ADRL x8, _g_fs_qrwin
    ldr  x0, [x8]
    cbnz x0, Lqr_have
    CLS  Ls_NSWindow
    MSG0 Ls_alloc
    mov  x23, x0
    SELX1 Ls_initWithContentRect
    mov  x0, x23
    LDD  d0, Lc_0
    LDD  d1, Lc_0
    LDD  d2, Lc_qw
    LDD  d3, Lc_qh
    mov  x2, #3                       // titled | closable
    mov  x3, #2
    mov  x4, #0
    bl   _objc_msgSend
    mov  x23, x0
    ADRL x8, _g_fs_qrwin
    str  x23, [x8]
    ADRL x0, Ls_qr_title
    bl   _nsstr
    mov  x2, x0
    mov  x0, x23
    MSG1 Ls_setTitle
    mov  x0, x23
    mov  x2, #0
    MSG1 Ls_setReleasedWhenClosed
    mov  x0, x23
    MSG0 Ls_center
    mov  x0, x23
    MSG0 Ls_contentView
    mov  x24, x0
    CLS  Ls_NSImageView
    MSG0 Ls_new
    mov  x20, x0
    ADRL x8, _g_fs_qriv
    str  x20, [x8]
    SELX1 Ls_setFrame
    mov  x0, x20
    ADRL x8, Lf_qr_iv
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x0, x24
    mov  x2, x20
    MSG1 Ls_addSubview
    ADRL x0, Ls_empty                 // the address, small, selectable
    mov  x1, #0
    mov  x2, #0
    mov  x3, x24
    ADRL x8, Lf_qr_url
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s12
    bl   _mk_label
    ADRL x8, _g_fs_qrlbl
    str  x0, [x8]
    mov  x2, #1
    MSG1 Ls_setSelectable
    ADRL x0, Ls_qr_how
    mov  x1, #0
    mov  x2, #0
    mov  x3, x24
    ADRL x8, Lf_qr_how
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s12
    bl   _mk_label
    bl   _dim_label
Lqr_have:
    ADRL x8, _g_fs_qriv
    ldr  x0, [x8]
    mov  x2, x22
    MSG1 Ls_setImage
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_fs_qrlbl
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    ADRL x8, _g_fs_qrwin
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    bl   _fs_activate
Lqr_done:
    LEAVE 80

// ===========================================================================
// Self-tests
// ===========================================================================

// long _t_fs(const char *request) -> the answer's status; the answer in _g_fs_tresp
_t_fs:
    ENTER 32                          // [96] the two ends  [104] big
    mov  x19, x0
    mov  w0, #1
    mov  w1, #1
    mov  w2, #0
    add  x3, sp, #96
    bl   _socketpair
    cbnz w0, Ltf_fail
    mov  w9, #0x40000                 // room for the whole answer (nobody reads it yet)
    str  w9, [sp, #104]
    mov  x20, #0
Ltf_buf:
    ldr  w0, [sp, #96]
    cmp  x20, #0
    b.eq Ltf_buf2
    ldr  w0, [sp, #100]
Ltf_buf2:
    mov  w1, #0xffff
    mov  w2, #0x1001                  // SO_SNDBUF
    add  x3, sp, #104
    mov  w4, #4
    bl   _setsockopt
    ldr  w0, [sp, #96]
    cmp  x20, #0
    b.eq Ltf_buf3
    ldr  w0, [sp, #100]
Ltf_buf3:
    mov  w1, #0xffff
    mov  w2, #0x1002                  // SO_RCVBUF
    add  x3, sp, #104
    mov  w4, #4
    bl   _setsockopt
    add  x20, x20, #1
    cmp  x20, #2
    b.lo Ltf_buf
    mov  x0, x19
    bl   _strlen
    mov  x2, x0
    ldr  w0, [sp, #96]
    mov  x1, x19
    bl   _fs_sendall
    mov  x0, #1
    MOVI x1, CT_SIZE
    bl   _calloc
    cbz  x0, Ltf_fail
    ldrsw x9, [sp, #100]
    str  x9, [x0, #CT_FD]
    bl   _fs_conn                     // answers, closes its end, frees
    mov  x20, #0
Ltf_read:
    mov  x9, #16383
    sub  x2, x9, x20
    cbz  x2, Ltf_end
    ADRL x1, _g_fs_tresp
    add  x1, x1, x20
    ldr  w0, [sp, #96]
    bl   _read
    cmp  x0, #0
    b.le Ltf_end
    add  x20, x20, x0
    b    Ltf_read
Ltf_end:
    ADRL x8, _g_fs_tresp
    strb wzr, [x8, x20]
    ldr  w0, [sp, #96]
    bl   _close
    cmp  x20, #12
    b.lt Ltf_fail
    ADRL x0, _g_fs_tresp
    add  x0, x0, #9
    bl   _atol
    LEAVE 32
Ltf_fail:
    mov  x0, #0
    LEAVE 32

// long _t_file_is(const char *dir, const char *name, const char *want) -> 1 if so
_t_file_is:
    ENTER 64
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    str  x19, [sp]
    str  x20, [sp, #8]
    ADRL x0, _g_fs_line
    mov  x1, #1100
    ADRL x2, Lf_join
    bl   _snprintf
    ADRL x0, _g_fs_line
    mov  w1, #0
    bl   _open
    tbnz w0, #31, Ltfi_no
    mov  w22, w0
    mov  w0, w22
    add  x1, sp, #96
    mov  x2, #63
    bl   _read
    mov  x23, x0
    mov  w0, w22
    bl   _close
    tbnz x23, #63, Ltfi_no
    add  x8, sp, #96
    strb wzr, [x8, x23]
    add  x0, sp, #96
    mov  x1, x21
    bl   _strcmp
    cmp  w0, #0
    cset x0, eq
    LEAVE 64
Ltfi_no:
    mov  x0, #0
    LEAVE 64

// void _t_fs_rm(const char *dir, const char *name)
_t_fs_rm:
    ENTER 0
    str  x0, [sp]
    str  x1, [sp, #8]
    ADRL x0, _g_fs_line
    mov  x1, #1100
    ADRL x2, Lf_join
    bl   _snprintf
    ADRL x0, _g_fs_line
    bl   _unlink
    LEAVE 0

.macro TCHECK name
    cset w1, eq
    ADRL x0, \name
    bl   _t_report
    add  x19, x19, x0
.endm

// long _files_selftest(void) -> failures
.globl _files_selftest
_files_selftest:
    ENTER 64                          // [96] a scratch path (40)
    mov  x19, #0
    // 85. addresses: %-decoding, and nothing outside the shared folder
    ADRL x0, Lt_p_ok
    ADRL x1, _g_fs_line
    mov  x2, #1024
    bl   _fs_decode
    mov  x20, x0
    ADRL x0, _g_fs_line
    bl   _fs_check_path
    and  x20, x20, x0
    ADRL x0, _g_fs_line
    ADRL x1, Lt_p_ok_out
    bl   _strcmp
    cmp  w0, #0
    ccmp x20, #1, #0, eq
    TCHECK Ln_fs_path
    mov  x20, #0                      // each of these must be refused
    ADRL x21, Lt_p_bad
Ltst_bad:
    ldr  x0, [x21], #8
    cbz  x0, Ltst_bad_end
    ADRL x1, _g_fs_line
    mov  x2, #1024
    bl   _fs_decode
    cbz  x0, Ltst_bad
    ADRL x0, _g_fs_line
    bl   _fs_check_path
    add  x20, x20, x0
    b    Ltst_bad
Ltst_bad_end:
    cmp  x20, #0
    TCHECK Ln_fs_trav
    // 87. an upload's name is only a name
    ADRL x0, _g_fs_line
    ADRL x1, Lt_n_in
    mov  x2, #200
    bl   _strlcpy
    ADRL x0, _g_fs_line
    bl   _fs_clean_name
    ADRL x0, _g_fs_line
    ADRL x1, Lt_n_out
    bl   _strcmp
    cmp  w0, #0
    TCHECK Ln_fs_name
    // 88-93. the whole page, over a socket, in a scratch folder
    add  x0, sp, #96
    ADRL x1, Lt_tmpl
    mov  x2, #40
    bl   _strlcpy
    add  x0, sp, #96
    bl   _mkdtemp
    cbz  x0, Ltst_end
    ADRL x8, _g_fs_roots
    mov  x0, x8
    add  x1, sp, #96
    mov  x2, #ROOT_LEN
    bl   _strlcpy
    ADRL x8, _g_fs_nroots
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, _g_fs_tok
    ADRL x1, Lt_fs_tok
    mov  x2, #40
    bl   _strlcpy
    ADRL x8, _g_fs_home
    strb wzr, [x8]
    ADRL x0, Lt_fs_up1                // two files in one upload
    bl   _t_fs
    mov  x20, x0
    add  x0, sp, #96
    ADRL x1, Lt_hello
    ADRL x2, Lt_hi
    bl   _t_file_is
    mov  x21, x0
    add  x0, sp, #96
    ADRL x1, Lt_b
    ADRL x2, Lt_second
    bl   _t_file_is
    and  x21, x21, x0
    cmp  x20, #303
    ccmp x21, #1, #0, eq
    TCHECK Ln_fs_up
    ADRL x0, Lt_fs_up2                // the same name again: kept as "hello (2).txt"
    bl   _t_fs
    mov  x20, x0
    add  x0, sp, #96
    ADRL x1, Lt_hello2
    ADRL x2, Lt_again
    bl   _t_file_is
    mov  x21, x0
    add  x0, sp, #96
    ADRL x1, Lt_hello
    ADRL x2, Lt_hi
    bl   _t_file_is
    and  x21, x21, x0
    cmp  x20, #303
    ccmp x21, #1, #0, eq
    TCHECK Ln_fs_keep
    ADRL x0, Lt_fs_list               // the folder lists them
    bl   _t_fs
    mov  x20, x0
    ADRL x0, _g_fs_tresp
    ADRL x1, Lt_hello2_url
    bl   _strstr
    cmp  x0, #0
    cset x21, ne
    cmp  x20, #200
    ccmp x21, #1, #0, eq
    TCHECK Ln_fs_list
    ADRL x0, Lt_fs_get                // a file comes back whole…
    bl   _t_fs
    mov  x20, x0
    ADRL x0, _g_fs_tresp
    ADRL x1, Lt_crlf2_hi
    bl   _strstr
    cmp  x0, #0
    cset x21, ne
    cmp  x20, #200
    ccmp x21, #1, #0, eq
    TCHECK Ln_fs_get
    ADRL x0, Lt_fs_range              // …or in part, for video players
    bl   _t_fs
    mov  x20, x0
    ADRL x0, _g_fs_tresp
    ADRL x1, Lt_crlf2_the
    bl   _strstr
    cmp  x0, #0
    cset x21, ne
    cmp  x20, #206
    ccmp x21, #1, #0, eq
    TCHECK Ln_fs_range
    ADRL x0, Lt_fs_wrong              // the wrong secret, a way out, a hidden file
    bl   _t_fs
    mov  x20, x0
    ADRL x0, Lt_fs_out
    bl   _t_fs
    mov  x21, x0
    ADRL x0, Lt_fs_hidden
    bl   _t_fs
    mov  x22, x0
    mov  x9, #403
    cmp  x20, x9
    mov  x9, #400
    ccmp x21, x9, #0, eq
    ccmp x22, x9, #0, eq
    TCHECK Ln_fs_refuse
    add  x0, sp, #96                  // tidy up
    ADRL x1, Lt_hello
    bl   _t_fs_rm
    add  x0, sp, #96
    ADRL x1, Lt_hello2
    bl   _t_fs_rm
    add  x0, sp, #96
    ADRL x1, Lt_b
    bl   _t_fs_rm
    add  x0, sp, #96
    bl   _rmdir
Ltst_end:
    ADRL x8, _g_fs_nroots
    str  xzr, [x8]
    ADRL x8, _g_fs_tok
    strb wzr, [x8]
    mov  x0, x19
    LEAVE 64

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Ltypes:
    .quad Lx_jpg,  Lt_jpeg
    .quad Lx_jpeg, Lt_jpeg
    .quad Lx_png,  Lt_png
    .quad Lx_gif,  Lt_gif
    .quad Lx_heic, Lt_heic
    .quad Lx_webp, Lt_webp
    .quad Lx_pdf,  Lt_pdf
    .quad Lx_mp4,  Lt_mp4
    .quad Lx_mov,  Lt_mov
    .quad Lx_m4v,  Lt_m4v
    .quad Lx_mp3,  Lt_mp3
    .quad Lx_m4a,  Lt_m4a
    .quad Lx_wav,  Lt_wav
    .quad Lx_txt,  Lt_text
    .quad Lx_md,   Lt_text
    .quad Lx_csv,  Lt_text
    .quad Lx_json, Lt_text
    .quad Lx_log,  Lt_text
    .quad Lx_s,    Lt_text
    .quad Lx_html, Lt_text
    .quad Lx_svg,  Lt_text
    .quad 0, 0
Lt_p_bad:
    .quad Lt_pb1, Lt_pb2, Lt_pb3, Lt_pb4, Lt_pb5, Lt_pb6, 0

.section __TEXT,__cstring,cstring_literals
Lx_jpg:   .asciz "jpg"
Lx_jpeg:  .asciz "jpeg"
Lx_png:   .asciz "png"
Lx_gif:   .asciz "gif"
Lx_heic:  .asciz "heic"
Lx_webp:  .asciz "webp"
Lx_pdf:   .asciz "pdf"
Lx_mp4:   .asciz "mp4"
Lx_mov:   .asciz "mov"
Lx_m4v:   .asciz "m4v"
Lx_mp3:   .asciz "mp3"
Lx_m4a:   .asciz "m4a"
Lx_wav:   .asciz "wav"
Lx_txt:   .asciz "txt"
Lx_md:    .asciz "md"
Lx_csv:   .asciz "csv"
Lx_json:  .asciz "json"
Lx_log:   .asciz "log"
Lx_s:     .asciz "s"
Lx_html:  .asciz "html"
Lx_svg:   .asciz "svg"
Lt_jpeg:  .asciz "image/jpeg"
Lt_png:   .asciz "image/png"
Lt_gif:   .asciz "image/gif"
Lt_heic:  .asciz "image/heic"
Lt_webp:  .asciz "image/webp"
Lt_pdf:   .asciz "application/pdf"
Lt_mp4:   .asciz "video/mp4"
Lt_mov:   .asciz "video/quicktime"
Lt_m4v:   .asciz "video/x-m4v"
Lt_mp3:   .asciz "audio/mpeg"
Lt_m4a:   .asciz "audio/mp4"
Lt_wav:   .asciz "audio/wav"
Lt_text:  .asciz "text/plain; charset=utf-8"
Lt_bin:   .asciz "application/octet-stream"

Ls_hexup:       .asciz "0123456789ABCDEF"
Ls_e_amp:       .asciz "&amp;"
Ls_e_lt:        .asciz "&lt;"
Ls_e_gt:        .asciz "&gt;"
Ls_e_quot:      .asciz "&quot;"
Ls_e_apos:      .asciz "&#39;"
Lf_ld:          .asciz "%ld"
Lf_b:           .asciz "%ld B"
Lf_kb:          .asciz "%.0f KB"
Lf_mb:          .asciz "%.1f MB"
Lf_gb:          .asciz "%.2f GB"
Lf_join:        .asciz "%s/%s"
Lf_join_n:      .asciz "%s/%s (%ld)"
Lf_join_ne:     .asciz "%s/%s (%ld).%s"
Ls_crlf:        .asciz "\r\n"
Ls_crlf2:       .asciz "\r\n\r\n"
Ls_GET_sp:      .asciz "GET "
Ls_POST_sp:     .asciz "POST "
Ls_Library:     .asciz "Library"
Ls_home:        .asciz "Home"
Ls_s:           .asciz "s"
Ls_empty:       .asciz ""
Ls_nl:          .asciz "\n"
Ls_slash_sp:    .asciz " / "
Ls_range:       .asciz "\r\nRange: bytes="
Ls_h_ctype:     .asciz "\r\nContent-Type:"
Ls_h_clen:      .asciz "\r\nContent-Length:"
Ls_boundary:    .asciz "boundary="
Ls_filename:    .asciz "filename=\""
Ls_HOME:        .asciz "HOME"
Ls_dot_local:   .asciz ".local"
Ls_pref_tok:    .asciz "files_token"
Ls_pref_dirs:   .asciz "files_dirs"
Lf_default_dir: .asciz "%s/asmmesh Files"
Lf_url:         .asciz "http://%s:8788/%s/"

Ls_r400:  .asciz "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n"
Ls_r403:  .asciz "HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nContent-Length: 10\r\nConnection: close\r\n\r\nforbidden\n"
Ls_r404:  .asciz "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 10\r\nConnection: close\r\n\r\nnot found\n"
Ls_r405:  .asciz "HTTP/1.1 405 Method Not Allowed\r\nContent-Type: text/plain\r\nContent-Length: 12\r\nConnection: close\r\n\r\nnot allowed\n"
Ls_r411:  .asciz "HTTP/1.1 411 Length Required\r\nContent-Type: text/plain\r\nContent-Length: 16\r\nConnection: close\r\n\r\nlength required\n"
Ls_r416:  .asciz "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
Ls_r431:  .asciz "HTTP/1.1 431 Request Header Fields Too Large\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
Ls_r303a: .asciz "HTTP/1.1 303 See Other\r\nLocation: "
Ls_r303b: .asciz "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
Ls_s200:  .asciz "HTTP/1.1 200 OK\r\n"
Ls_s206:  .asciz "HTTP/1.1 206 Partial Content\r\n"
Ls_ctype: .asciz "Content-Type: "
Ls_clen_h: .asciz "\r\nContent-Length: "
Ls_crange: .asciz "\r\nContent-Range: bytes "
Ls_file_hdrs: .asciz "\r\nAccept-Ranges: bytes\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: sandbox\r\nCache-Control: no-store\r\n"
Ls_attach: .asciz "Content-Disposition: attachment\r\n"
Ls_close_h: .asciz "Connection: close\r\n\r\n"
Ls_h200:  .asciz "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'\r\nConnection: close\r\n\r\n"
Ls_head:  .asciz "<!doctype html><html><head><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\"><title>asmmesh files</title><style>body{font:16px -apple-system,sans-serif;background:#1c1c1e;color:#f2f2f7;margin:0;padding:16px}a{color:#64d2ff;text-decoration:none}h1{font-size:22px;margin:6px 0 12px;word-break:break-word}ul{list-style:none;padding:0;margin:0}li{display:flex;align-items:center;gap:10px;background:#2c2c2e;border-radius:12px;padding:12px 14px;margin:6px 0}li a.n{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}li span{color:#8e8e93;font-size:13px;white-space:nowrap}form{background:#2c2c2e;border-radius:12px;padding:14px;margin-top:16px}input{margin-top:8px;color:#f2f2f7}button{display:block;background:#0a84ff;color:#fff;border:0;border-radius:8px;padding:10px 18px;font-size:16px;margin-top:12px}.up{display:inline-block;margin-bottom:4px}</style></head><body>"
Ls_roots_top: .asciz "<h1>asmmesh files</h1><ul>"
Ls_roots_end: .asciz "</ul></body></html>"
Ls_li_dir:    .asciz "<li>\360\237\223\201<a class=n href=\""
Ls_li_file:   .asciz "<li>\360\237\223\204<a class=n href=\""
Ls_a_mid:     .asciz "\">"
Ls_a_end:     .asciz "</a></li>"
Ls_a_size:    .asciz "</a><span>"
Ls_a_dl:      .asciz "</span><a href=\""
Ls_a_dl_end:  .asciz "\">\342\244\223</a></li>"
Ls_up_a:      .asciz "<a class=up href=\""
Ls_up_b:      .asciz "\">\342\200\271 Back</a><h1>"
Ls_h1_end:    .asciz "</h1><ul>"
Ls_empty_dir: .asciz "<li><span>Nothing here yet.</span></li>"
Ls_form_a:    .asciz "</ul><form method=post enctype=multipart/form-data action=\""
Ls_form_b:    .asciz "\"><div>Add photos or files to this folder</div><input type=file name=f multiple><button>Upload</button></form></body></html>"

Lf_note_up:   .asciz "\302\267 \360\237\223\201 %ld file%s added to %s from the files page."
Ls_fs_fail:   .asciz "\302\267 \342\232\240\357\270\217 Files on Wi-Fi couldn\342\200\231t listen on port 8788 \342\200\224 is something else using it?"
Lf_files_on:  .asciz "\302\267 \360\237\223\201 Files on Wi-Fi: open %s in Safari on your phone (same Wi-Fi) \342\200\224 or scan the QR code. Sharing:"
Lf_files_root: .asciz "\302\267      %s"
Ls_files_how: .asciz "\302\267 Your phone can open, download and add files there, but never delete or replace any. Hidden files and Library stay hidden. \342\200\234share folders\342\200\235 picks others; \342\200\234files new\342\200\235 changes the secret in the address."
Ls_files_pushed: .asciz "\302\267 \360\237\223\262 Sent the link to your phone too \342\200\224 tap it there."
Ls_files_newtok: .asciz "\302\267 \360\237\224\220 New files address \342\200\224 the old one no longer works."
Ls_share_prompt: .asciz "Share"
Ls_share_msg: .asciz "Choose up to eight folders your phone may open and add files to. Hidden files and Library always stay hidden."
Ls_ad_prompt: .asciz "AirDrop"
Ls_ad_open:   .asciz "\302\267 AirDrop is open \342\200\224 pick your phone (it needs to be unlocked and near)."
Ls_ad_none:   .asciz "\302\267 AirDrop isn\342\200\231t available right now. Check that Wi-Fi and Bluetooth are on, and AirDrop is allowed in Control Centre."
Ls_qr_title:  .asciz "Files on Wi-Fi"
Ls_qr_how:    .asciz "Scan with the iPhone camera, then open it in Safari. Your phone must be on the same Wi-Fi."
Ls_qrgen:     .asciz "CIQRCodeGenerator"
Ls_inputMessage: .asciz "inputMessage"
Ls_inputCorrection: .asciz "inputCorrectionLevel"
Ls_M:         .asciz "M"

Ls_NSOpenPanel:       .asciz "NSOpenPanel"
Ls_NSSharingService:  .asciz "NSSharingService"
Ls_NSApplication:     .asciz "NSApplication"
Ls_NSWindow:          .asciz "NSWindow"
Ls_NSImageView:       .asciz "NSImageView"
Ls_NSImage:           .asciz "NSImage"
Ls_NSCIImageRep:      .asciz "NSCIImageRep"
Ls_CIFilter:          .asciz "CIFilter"
Ls_openPanel:         .asciz "openPanel"
Ls_setCanChooseFiles: .asciz "setCanChooseFiles:"
Ls_setCanChooseDirectories: .asciz "setCanChooseDirectories:"
Ls_setAllowsMultipleSelection: .asciz "setAllowsMultipleSelection:"
Ls_setCanCreateDirectories: .asciz "setCanCreateDirectories:"
Ls_setPrompt:         .asciz "setPrompt:"
Ls_setMessage:        .asciz "setMessage:"
Ls_runModal:          .asciz "runModal"
Ls_URLs:              .asciz "URLs"
Ls_count:             .asciz "count"
Ls_objectAtIndex:     .asciz "objectAtIndex:"
Ls_path:              .asciz "path"
Ls_UTF8String:        .asciz "UTF8String"
Ls_sharingServiceNamed: .asciz "sharingServiceNamed:"
Ls_canPerformWithItems: .asciz "canPerformWithItems:"
Ls_performWithItems:  .asciz "performWithItems:"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_filterWithName:    .asciz "filterWithName:"
Ls_dataUsingEncoding: .asciz "dataUsingEncoding:"
Ls_setValueForKey:    .asciz "setValue:forKey:"
Ls_outputImage:       .asciz "outputImage"
Ls_extent:            .asciz "extent"
Ls_imageByApplyingTransform: .asciz "imageByApplyingTransform:"
Ls_imageRepWithCIImage: .asciz "imageRepWithCIImage:"
Ls_size:              .asciz "size"
Ls_alloc:             .asciz "alloc"
Ls_new:               .asciz "new"
Ls_initWithSize:      .asciz "initWithSize:"
Ls_addRepresentation: .asciz "addRepresentation:"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_setTitle:          .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_center:            .asciz "center"
Ls_contentView:       .asciz "contentView"
Ls_setFrame:          .asciz "setFrame:"
Ls_addSubview:        .asciz "addSubview:"
Ls_setSelectable:     .asciz "setSelectable:"
Ls_setImage:          .asciz "setImage:"
Ls_setStringValue:    .asciz "setStringValue:"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_orderOut:          .asciz "orderOut:"

Lt_p_ok:      .asciz "/Photos%20from%20May//trip%2Fday%201/"
Lt_p_ok_out:  .asciz "Photos from May/trip/day 1"
Lt_pb1:       .asciz "../etc"
Lt_pb2:       .asciz "a/../../b"
Lt_pb3:       .asciz "a/%2E%2E/b"
Lt_pb4:       .asciz ".ssh/id_rsa"
Lt_pb5:       .asciz "a%00b"
Lt_pb6:       .asciz "a%5C..%5Cb"
Lt_n_in:      .asciz "../../.evil:name.sh"
Lt_n_out:     .asciz "_.evil_name.sh"
Lt_tmpl:      .asciz "/private/tmp/asmmesh-fs-XXXXXX"
Lt_fs_tok:    .asciz "0123456789abcdef0123456789abcdef"
Lt_hello:     .asciz "hello.txt"
Lt_hello2:    .asciz "hello (2).txt"
Lt_hello2_url: .asciz "hello%20%282%29.txt"
Lt_b:         .asciz "b.txt"
Lt_hi:        .asciz "hi there"
Lt_second:    .asciz "second"
Lt_again:     .asciz "again"
Lt_crlf2_hi:  .asciz "\r\n\r\nhi there"
Lt_crlf2_the: .asciz "\r\n\r\nthe"
Lt_fs_up1:    .asciz "POST /0123456789abcdef0123456789abcdef/u/0/ HTTP/1.1\r\nHost: x\r\nContent-Type: multipart/form-data; boundary=XyZ\r\nContent-Length: 224\r\n\r\n--XyZ\r\nContent-Disposition: form-data; name=\"f\"; filename=\"hello.txt\"\r\nContent-Type: text/plain\r\n\r\nhi there\r\n--XyZ\r\nContent-Disposition: form-data; name=\"f\"; filename=\"../b.txt\"\r\nContent-Type: text/plain\r\n\r\nsecond\r\n--XyZ--\r\n"
Lt_fs_up2:    .asciz "POST /0123456789abcdef0123456789abcdef/u/0/ HTTP/1.1\r\nContent-Type: multipart/form-data; boundary=\"XyZ\"\r\nContent-Length: 89\r\n\r\n--XyZ\r\nContent-Disposition: form-data; name=\"f\"; filename=\"hello.txt\"\r\n\r\nagain\r\n--XyZ--\r\n"
Lt_fs_list:   .asciz "GET /0123456789abcdef0123456789abcdef/d/0/ HTTP/1.1\r\nHost: x\r\n\r\n"
Lt_fs_get:    .asciz "GET /0123456789abcdef0123456789abcdef/d/0/hello.txt HTTP/1.1\r\nHost: x\r\n\r\n"
Lt_fs_range:  .asciz "GET /0123456789abcdef0123456789abcdef/d/0/hello.txt HTTP/1.1\r\nRange: bytes=3-5\r\n\r\n"
Lt_fs_wrong:  .asciz "GET /0123456789abcdef0123456789abcdee/d/0/ HTTP/1.1\r\n\r\n"
Lt_fs_out:    .asciz "GET /0123456789abcdef0123456789abcdef/d/0/..%2F..%2Fetc HTTP/1.1\r\n\r\n"
Lt_fs_hidden: .asciz "GET /0123456789abcdef0123456789abcdef/d/0/.ssh/ HTTP/1.1\r\n\r\n"
Ln_fs_path:   .asciz "85 files: an address becomes a tidy folder path"
Ln_fs_trav:   .asciz "86 files: .., hidden files, NUL and backslashes are refused"
Ln_fs_name:   .asciz "87 files: an upload's name is only a name, never hidden"
Ln_fs_up:     .asciz "88 files: two files in one upload both arrive"
Ln_fs_keep:   .asciz "89 files: an upload never replaces a file (hello (2).txt)"
Ln_fs_list:   .asciz "90 files: a folder page lists its files"
Ln_fs_get:    .asciz "91 files: a file comes back whole"
Ln_fs_range:  .asciz "92 files: part of a file, for video players (206)"
Ln_fs_refuse: .asciz "93 files: wrong secret 403, a way out or hidden 400"
