// guard.s — what comes in over the air can't take asmmesh down.
//
// Everything a stranger can send arrives through a few doors: a write into our
// Bluetooth inbox, an advert from any device nearby, a value from a peripheral,
// a frame off the FM radio. Each of those runs under _guard_call: if the code
// handling it faults (a bad pointer, a read past the end — the bugs hand-written
// assembly can have), the fault is caught, that one packet or advert is dropped,
// Main says so once, and the details go to ~/Library/Logs/asmmesh-guard.log so
// the bug can be found and the packet added to the self-tests. asmmesh keeps
// running.
//
// How: sigsetjmp before the handler runs; SIGSEGV/SIGBUS/SIGILL handlers that,
// only while a guarded call is running on the main thread, siglongjmp back to
// it. A fault anywhere else is left alone: the old handler is put back and the
// fault happens again, so it crashes with a normal crash report.
//
// After a caught fault the app may be in a half-finished state (a table half
// updated), so after three in one run Main suggests quitting and reopening.

.include "macros.inc"

.set SIGILL,      4
.set SIGBUS,      10
.set SIGSEGV,     11
.set SA_SIGINFO,  0x40
.set MC_PC,       272          // arm64 mcontext: es (16) + x0-x28, fp, lr, sp, then pc

.data
.p2align 3
_g_gd_on:       .quad 0         // 1 while a guarded call runs
_g_gd_set:      .quad 0         // handlers installed
.globl _g_gd_faults
_g_gd_faults:   .quad 0
.globl _g_gd_nolog
_g_gd_nolog:    .quad 0         // the self-tests: count, but write and say nothing
_g_gd_sig:      .quad 0
_g_gd_addr:     .quad 0
_g_gd_pc:       .quad 0
_g_gd_fn:       .quad 0         // what was running
_g_gd_data:     .quad 0         // the packet, if it was one
_g_gd_len:      .quad 0
.zerofill __DATA,__bss,_g_gd_jb,256,4
.zerofill __DATA,__bss,_g_gd_old,48,4      // the previous sigactions: ILL, BUS, SEGV
.zerofill __DATA,__bss,_g_gd_path,512,4

.text
.p2align 2

// long _guard_call(fn, a0, a1, a2, a3, a4, a5) -> fn(a0..a5), or -1 if it faulted
//   (main thread only; elsewhere fn is simply called)
.globl _guard_call
_guard_call:
    ENTER 32                          // [96] a4  [104] a5
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    stp  x5, x6, [sp, #96]
    ADRL x8, _g_gd_on                 // already guarded (nested): just call
    ldr  x9, [x8]
    cbnz x9, Lgc_plain
    bl   _pthread_main_np
    cbz  w0, Lgc_plain
    bl   _guard_install
    ADRL x8, _g_gd_fn
    str  x19, [x8]
    ADRL x0, _g_gd_jb
    mov  w1, #1
    bl   _sigsetjmp
    cbnz w0, Lgc_fault
    ADRL x8, _g_gd_on
    mov  x9, #1
    str  x9, [x8]
    mov  x0, x20
    mov  x1, x21
    mov  x2, x22
    mov  x3, x23
    ldp  x4, x5, [sp, #96]
    blr  x19
    ADRL x8, _g_gd_on
    str  xzr, [x8]
    LEAVE 32
Lgc_plain:
    mov  x0, x20
    mov  x1, x21
    mov  x2, x22
    mov  x3, x23
    ldp  x4, x5, [sp, #96]
    blr  x19
    LEAVE 32
Lgc_fault:
    ADRL x8, _g_gd_on
    str  xzr, [x8]
    bl   _guard_report
    mov  x0, #-1
    LEAVE 32

// Objective-C delegate methods with the guard around them: same arguments
// (self, _cmd, ...), so they go straight into the method tables
.macro GUARDED name, real
.globl \name
\name:
    mov  x6, x5
    mov  x5, x4
    mov  x4, x3
    mov  x3, x2
    mov  x2, x1
    mov  x1, x0
    ADRL x0, \real
    b    _guard_call
.endm

    GUARDED _g_ble_cm_discover, _ble_cm_discover   // an advert from any device
    GUARDED _g_ble_p_value, _ble_p_value           // a value from a peripheral
    GUARDED _g_ble_pm_writes, _ble_pm_writes       // a write into our inbox

// long _guard_rx(const uint8 *pkt, size_t len) — _mesh_receive under the guard,
//   remembering the packet so a fault can be written down with it
.globl _guard_rx
_guard_rx:
    ENTER 0
    ADRL x8, _g_gd_data
    str  x0, [x8]
    ADRL x8, _g_gd_len
    str  x1, [x8]
    mov  x2, x1
    mov  x1, x0
    ADRL x0, _mesh_receive
    bl   _guard_call
    ADRL x8, _g_gd_data
    str  xzr, [x8]
    LEAVE 0

// void _guard_install(void) — once
_guard_install:
    ENTER 16                          // [96] struct sigaction (handler, mask, flags)
    ADRL x8, _g_gd_set
    ldr  x9, [x8]
    cbnz x9, Lgi_done
    mov  x9, #1
    str  x9, [x8]
    ADRL x9, _guard_handler
    str  x9, [sp, #96]
    str  wzr, [sp, #104]
    mov  w9, #SA_SIGINFO
    str  w9, [sp, #108]
    mov  x0, #SIGILL
    add  x1, sp, #96
    ADRL x2, _g_gd_old
    bl   _sigaction
    mov  x0, #SIGBUS
    add  x1, sp, #96
    ADRL x2, _g_gd_old
    add  x2, x2, #16
    bl   _sigaction
    mov  x0, #SIGSEGV
    add  x1, sp, #96
    ADRL x2, _g_gd_old
    add  x2, x2, #32
    bl   _sigaction
Lgi_done:
    LEAVE 16

// void _guard_handler(int sig, siginfo_t *info, ucontext_t *uc)
_guard_handler:
    ADRL x8, _g_gd_on
    ldr  x9, [x8]
    cbz  x9, Lgh_not_ours
    str  xzr, [x8]
    ADRL x8, _g_gd_sig
    str  x0, [x8]
    ldr  x9, [x1, #24]                // si_addr
    ADRL x8, _g_gd_addr
    str  x9, [x8]
    ldr  x9, [x2, #48]                // uc_mcontext
    cbz  x9, 1f
    ldr  x9, [x9, #MC_PC]
1:  ADRL x8, _g_gd_pc
    str  x9, [x8]
    ADRL x0, _g_gd_jb
    mov  w1, #1
    b    _siglongjmp
Lgh_not_ours:                         // not inside a guarded call: put the old
    stp  x29, x30, [sp, #-16]!        //   handler back and return; the fault
    mov  x29, sp                      //   happens again and crashes as usual
    ADRL x2, _g_gd_old
    cmp  w0, #SIGBUS
    b.ne 2f
    add  x2, x2, #16
2:  cmp  w0, #SIGSEGV
    b.ne 3f
    add  x2, x2, #32
3:  mov  x1, x2
    mov  x2, #0
    bl   _sigaction
    ldp  x29, x30, [sp], #16
    ret

// void _guard_report(void) — after a caught fault: tell Main (once, and again at three),
//   and write the details down
_guard_report:
    ENTER 64                          // [96] image info (Dl_info: 32 bytes)
    ADRL x8, _g_gd_faults
    ldr  x19, [x8]
    add  x19, x19, #1
    str  x19, [x8]
    ADRL x8, _g_gd_nolog
    ldr  x9, [x8]
    cbnz x9, Lgr_done

    // the log file: ~/Library/Logs/asmmesh-guard.log (iPhone: the app's Caches)
    ADRL x0, Ls_home
    bl   _getenv
    cbz  x0, Lgr_say
    mov  x20, x0
    ADRL x0, _g_gd_path
    mov  x1, #512
    ADRL x2, Lf_logpath
    str  x20, [sp]
    bl   _snprintf
    ADRL x0, _g_gd_path
    ADRL x1, Ls_append
    bl   _fopen
    cbnz x0, 1f
    ADRL x0, _g_gd_path
    mov  x1, #512
    ADRL x2, Lf_cachepath
    str  x20, [sp]
    bl   _snprintf
    ADRL x0, _g_gd_path
    ADRL x1, Ls_append
    bl   _fopen
    cbz  x0, Lgr_say
1:  mov  x20, x0                      // FILE *
    mov  x0, #0
    bl   _time
    str  x0, [sp]
    ADRL x8, _g_gd_sig
    ldr  x9, [x8]
    str  x9, [sp, #8]
    ADRL x8, _g_gd_addr
    ldr  x9, [x8]
    str  x9, [sp, #16]
    ADRL x8, _g_gd_pc
    ldr  x9, [x8]
    str  x9, [sp, #24]
    mov  x0, x20
    ADRL x1, Lf_head
    bl   _fprintf
    ADRL x8, _g_gd_pc                 // where: which function, as an offset in the app
    ldr  x0, [x8]
    add  x1, sp, #96
    bl   _dladdr
    cbz  w0, 2f
    ldr  x9, [sp, #112]               // dli_sname
    cbz  x9, 2f
    str  x9, [sp]
    ADRL x8, _g_gd_pc
    ldr  x10, [x8]
    ldr  x11, [sp, #120]              // dli_saddr
    sub  x10, x10, x11
    str  x10, [sp, #8]
    mov  x0, x20
    ADRL x1, Lf_where
    bl   _fprintf
2:  ADRL x8, _g_gd_data               // the packet, in hex
    ldr  x21, [x8]
    cbz  x21, 4f
    ADRL x8, _g_gd_len
    ldr  x22, [x8]
    cmp  x22, #256
    mov  x9, #256
    csel x22, x9, x22, hi
    mov  x0, x20
    ADRL x1, Lf_pkt
    str  x22, [sp]
    bl   _fprintf
    mov  x23, #0
3:  cmp  x23, x22
    b.hs 31f
    ldrb w9, [x21, x23]
    str  x9, [sp]
    mov  x0, x20
    ADRL x1, Lf_byte
    bl   _fprintf
    add  x23, x23, #1
    b    3b
31: mov  x0, x20
    ADRL x1, Ls_nl
    bl   _fprintf
4:  mov  x0, x20
    bl   _fclose

Lgr_say:
    cmp  x19, #1
    b.eq 5f
    cmp  x19, #3
    b.ne Lgr_done
    ADRL x0, Ls_third
    bl   _chat_line
    b    Lgr_done
5:  ADRL x0, Ls_first
    bl   _chat_line
Lgr_done:
    LEAVE 64

.section __TEXT,__cstring,cstring_literals
Ls_home:        .asciz "HOME"
Ls_append:      .asciz "a"
Ls_nl:          .asciz "\n"
Lf_logpath:     .asciz "%s/Library/Logs/asmmesh-guard.log"
Lf_cachepath:   .asciz "%s/Library/Caches/asmmesh-guard.log"
Lf_head:        .asciz "\n[%ld] caught signal %ld at address 0x%lx, pc 0x%lx\n"
Lf_where:       .asciz "  in %s + %ld\n"
Lf_pkt:         .asciz "  the packet (%ld bytes): "
Lf_byte:        .asciz "%02lx"
Ls_first:       .asciz "\302\267 \360\237\233\241 Something that arrived over the air tripped a bug in asmmesh. It was dropped instead of crashing the app; the details are in Library/Logs/asmmesh-guard.log."
Ls_third:       .asciz "\302\267 \360\237\233\241 That's the third caught fault this session. asmmesh is still running, but quitting and reopening it would be safest."
