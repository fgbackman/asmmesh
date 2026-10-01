// asmfm — io.S : child processes (rtl_fm, curl), receive stream, web fetch
.include "fm_defs.inc"
    .text

.set FETCHCAP, (2*1024*1024)

// fm_spawn(x0 = program, x1 = argv, x2 = envp, x3 = stderr path or 0,
//          x4 = where to put the pid, or 0 for fm_last_pid)
//   -> w0 = read end of child's stdout (or -1)
// Safe to call from two threads at once: everything it builds is on its stack.
    .globl _fm_spawn
    .p2align 2
_fm_spawn:
    FENTER 32
    mov x19, x0
    mov x20, x1
    mov x21, x2
    mov x22, x3
    mov x25, x4
    cbnz x25, 0f
    LA x25, _fm_last_pid
0:  cbnz x22, 1f
    LA x22, str_devnull
1:  add x0, sp, #LOC
    bl _pipe
    cbnz w0, 9f
    add x23, sp, #(LOC + 8)          // posix_spawn_file_actions_t (one pointer on macOS)
    mov x0, x23
    bl _posix_spawn_file_actions_init
    mov x0, x23
    ldr w1, [sp, #LOC+4]
    mov w2, #1
    bl _posix_spawn_file_actions_adddup2
    mov x0, x23
    ldr w1, [sp, #LOC]
    bl _posix_spawn_file_actions_addclose
    mov x0, x23
    ldr w1, [sp, #LOC+4]
    bl _posix_spawn_file_actions_addclose
    mov x0, x23
    mov w1, #0
    LA x2, str_devnull
    mov w3, #O_RDONLY
    mov w4, #0
    bl _posix_spawn_file_actions_addopen
    mov x0, x23
    mov w1, #2
    mov x2, x22
    mov w3, #O_WR_CREAT_TRUNC
    mov w4, #420
    bl _posix_spawn_file_actions_addopen
    // the child gets stdin, stdout and stderr and nothing else: without this,
    // a child started on another thread could inherit this pipe and keep it open
    add x0, sp, #(LOC + 24)
    bl _posix_spawnattr_init
    add x0, sp, #(LOC + 24)
    mov w1, #0x4000                  // POSIX_SPAWN_CLOEXEC_DEFAULT
    bl _posix_spawnattr_setflags
    add x0, sp, #(LOC + 16)          // pid
    mov x1, x19
    mov x2, x23
    add x3, sp, #(LOC + 24)
    mov x4, x20
    mov x5, x21
    bl _posix_spawnp
    mov w24, w0
    add x0, sp, #(LOC + 24)
    bl _posix_spawnattr_destroy
    mov x0, x23
    bl _posix_spawn_file_actions_destroy
    ldr w0, [sp, #LOC+4]
    bl _close
    cbz w24, 2f
    ldr w0, [sp, #LOC]
    bl _close
9:  mov w0, #-1
    FLEAVE 32
2:  ldr w1, [sp, #(LOC + 16)]
    str w1, [x25]
    ldr w0, [sp, #LOC]
    FLEAVE 32

// fm_rx_open(x0 = raw path or 0, x1 = frequency string, x2 = envp) -> w0 = fd
    .globl _fm_rx_open
    .p2align 2
_fm_rx_open:
    FENTER
    mov x19, x0
    mov x20, x1
    mov x21, x2
    cbz x19, 5f
    ldrb w0, [x19]
    cmp w0, #'-'
    b.ne 1f
    ldrb w0, [x19, #1]
    cbnz w0, 1f
    mov w0, #0
    FLEAVE
1:  mov x0, x19                 // O_RDWR first so FIFOs open without blocking
    mov w1, #O_RDWR
    bl _open
    cmp w0, #0
    b.ge 2f
    mov x0, x19
    mov w1, #O_RDONLY
    bl _open
    cmp w0, #0
    b.ge 2f
    mov w0, #-1
2:  LA x1, _fm_rx_fd
    str w0, [x1]
    FLEAVE
5:  // validate frequency: digits and at most one '.', 2..7 chars
    cbz x20, 8f
    mov x0, x20
    bl _strlen
    cmp x0, #2
    b.lt 8f
    cmp x0, #7
    b.gt 8f
    mov x1, #0
    mov w3, #0
6:  cmp x1, x0
    b.ge 7f
    ldrb w2, [x20, x1]
    add x1, x1, #1
    cmp w2, #'.'
    b.ne 61f
    add w3, w3, #1
    b 6b
61: sub w2, w2, #'0'
    cmp w2, #9
    b.hi 8f
    b 6b
7:  cmp w3, #1
    b.gt 8f
    LA x0, freqbuf
    mov x1, x20
    mov x2, #16
    bl _fm_strlcpy
    LA x0, freqbuf
    LA x1, str_M
    mov x2, #16
    bl _fm_strlcat
    LA x0, str_rtlfm
    LA x1, rtl_argv
    mov x2, x21
    LA x3, str_rtllog
    LA x4, _fm_rx_pid               // remember rtl_fm so it can be stopped
    bl _fm_spawn
    cmp w0, #0
    b.lt 81f
    b 2b
81: mov w0, #2                    // rtl_fm is not installed
    LA x1, _g_fm_rx_err
    str w0, [x1]
    mov w0, #-1
    b 2b
8:  mov w0, #1                     // not a frequency
    LA x1, _g_fm_rx_err
    str w0, [x1]
    mov w0, #-1
    b 2b

// fm_rx_service(w0 = fd) -> x0 = samples demodulated this call, 0 on end of stream
    .globl _fm_rx_service
    .p2align 2
_fm_rx_service:
    FENTER
    mov w19, w0
    LA x20, rx_carry
    LA x21, _fm_rxbuf
    ldr w22, [x20]
    add x1, x21, x22
    mov x2, #8192
    sub x2, x2, x22
    mov w0, w19
    bl _read
    cmp x0, #0
    b.gt 1f
    mov x0, #0
    FLEAVE
1:  add x23, x0, x22            // total bytes
    lsr x24, x23, #1            // samples
    and x25, x23, #1
    // signal level: mean square of this block
    mov x0, #0
    mov x1, #0
3:  cmp x1, x24
    b.hs 4f
    ldrsh x2, [x21, x1, lsl #1]
    madd x0, x2, x2, x0
    add x1, x1, #1
    b 3b
4:  cbz x24, 5f
    udiv x0, x0, x24
    LA x1, _fm_level_ms
    str x0, [x1]
5:  mov x0, x21
    mov w1, w24
    bl _fm_demod
    LA x0, _fm_rx_samples
    ldr x1, [x0]
    add x1, x1, x24
    str x1, [x0]
    str w25, [x20]
    cbz x25, 2f
    sub x2, x23, #1
    ldrb w3, [x21, x2]
    strb w3, [x21]
2:  mov x0, x24
    cmp x0, #0
    csinc x0, x0, xzr, ne       // report at least 1 while the stream is alive
    FLEAVE

// fm_rx_close(): stop rtl_fm and close the receive stream
    .globl _fm_rx_close
    .p2align 2
_fm_rx_close:
    FENTER 16
    LA x19, _fm_rx_pid
    ldr w0, [x19]
    cbz w0, 1f
    mov w1, #15
    bl _kill
    ldr w0, [x19]
    add x1, sp, #LOC
    mov w2, #0
    bl _waitpid
    str wzr, [x19]
1:  LA x19, _fm_rx_fd
    ldr w0, [x19]
    cmp w0, #0
    b.le 2f
    bl _close
2:  mov w0, #-1
    str w0, [x19]
    FLEAVE 16

// fm_rx_reset(): forget partial samples and restart the receive clock
    .globl _fm_rx_reset
    .p2align 2
_fm_rx_reset:
    LA x0, rx_carry
    str wzr, [x0]
    LA x0, _fm_rx_samples
    str xzr, [x0]
    LA x0, _fm_level_ms
    str xzr, [x0]
    ret

// fm_fetch_start(x0 = url, x1 = envp) -> w0 = fd of curl output (or -1)
    .globl _fm_fetch_start
    .p2align 2
_fm_fetch_start:
    FENTER
    LA x2, curl_argv
    str x0, [x2, #(8*14)]       // url slot (after --url)
    mov x2, x1
    LA x0, str_curl
    LA x1, curl_argv
    mov x3, #0
    LA x4, _fm_fetch_len
    str xzr, [x4]
    mov x4, #0
    bl _fm_spawn
    FLEAVE

// fm_fetch_read(w0 = fd) -> w0 = 1 more to come, 0 finished (fd closed, child reaped)
    .globl _fm_fetch_read
    .p2align 2
_fm_fetch_read:
    FENTER 16
    mov w19, w0
    LA x20, _fm_fetch_len
    ldr x21, [x20]
    mov x2, #FETCHCAP
    sub x2, x2, x21
    sub x2, x2, #1
    mov w22, #0
    cbz x2, 3f
    LA x1, _fm_fetchbuf
    add x1, x1, x21
    b 4f
3:  LA x1, drain_buf            // full: drain into scratch
    mov x2, #4096
    mov w22, #1
4:  mov w0, w19
    bl _read
    cmp x0, #0
    b.le 5f
    cbnz w22, 6f
    add x21, x21, x0
6:  LA x1, _fm_fetchbuf
    strb wzr, [x1, x21]
    str x21, [x20]
    mov w0, #1
    FLEAVE 16
5:  mov w0, w19
    bl _close
    LA x0, _fm_last_pid
    ldr w0, [x0]
    add x1, sp, #LOC
    mov w2, #0
    bl _waitpid
    LA x1, _fm_fetchbuf
    strb wzr, [x1, x21]
    mov w0, #0
    FLEAVE 16

// fm_fetch_blocking(x0 = url, x1 = envp) -> x0 = bytes in fm_fetchbuf
    .globl _fm_fetch_blocking
    .p2align 2
_fm_fetch_blocking:
    FENTER
    bl _fm_fetch_start
    cmp w0, #0
    b.lt 9f
    mov w19, w0
1:  mov w0, w19
    bl _fm_fetch_read
    cbnz w0, 1b
    LA x0, _fm_fetch_len
    ldr x0, [x0]
    FLEAVE
9:  mov x0, #0
    FLEAVE

    .section __TEXT,__const
str_devnull: .asciz "/dev/null"
str_M:       .asciz "M"
str_rtlfm:   .asciz "rtl_fm"
str_rtllog:  .asciz "/tmp/asmfm-rtl_fm.log"
str_curl:    .asciz "curl"
a_f:    .asciz "-f"
a_M:    .asciz "-M"
a_wbfm: .asciz "wbfm"
a_r:    .asciz "-r"
a_48k:  .asciz "48000"
a_dash: .asciz "-"
c_s:    .asciz "-sL"
c_comp: .asciz "--compressed"
c_mt:   .asciz "--max-time"
c_30:   .asciz "30"
c_A:    .asciz "-A"
c_ua:   .asciz "Mozilla/5.0 (Macintosh; Apple Silicon) asmfm/1.0"
c_w:    .asciz "-w"
c_wfmt: .asciz "\n\001%{url_effective}"
c_proto: .asciz "--proto"
c_predir: .asciz "--proto-redir"
c_http: .asciz "=http,https"
c_url:  .asciz "--url"
msg_rawin:   .asciz "asmfm: cannot open --rx-raw input\n"
msg_nortl:   .asciz "asmfm: could not start rtl_fm. Install it with: brew install librtlsdr\n"
msg_badfreq: .asciz "asmfm: give the frequency in MHz, for example 88.3\n"

    .data
    .p2align 3
rtl_argv:
    .quad str_rtlfm, a_f, freqbuf, a_M, a_wbfm, a_r, a_48k, a_dash, 0
curl_argv:
    .quad str_curl, c_s, c_comp, c_mt, c_30, c_A, c_ua, c_w, c_wfmt
    .quad c_proto, c_http, c_predir, c_http, c_url, 0, 0
freqbuf: .space 16
rx_carry: .word 0
    .p2align 3
    .globl _fm_rx_samples
_fm_rx_samples: .quad 0
    .globl _fm_fetch_len
_fm_fetch_len: .quad 0
    .globl _fm_last_pid
_fm_last_pid: .word 0, 0
    .globl _fm_rx_pid
_fm_rx_pid: .word 0
    .globl _fm_rx_fd
_fm_rx_fd: .word -1
    .globl _g_fm_rx_err
_g_fm_rx_err: .word 0
    .p2align 3
    .globl _fm_level_ms
_fm_level_ms: .quad 0

    BSS _fm_rxbuf, 8192
    BSS _fm_fetchbuf, FETCHCAP
    BSS drain_buf, 4096
