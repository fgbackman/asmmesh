// fm.s — the mesh over FM radio.
//
// Every packet asmmesh sends or relays leaves through _ble_broadcast; when the
// FM radio service is on, a copy also goes into a small transmit queue here and
// out of the headphone jack as audio tones (AFSK, HDLC framing with CRC-16 —
// fm_dsp.s). An FM transmitter plugged into that jack puts it on the air.
//
// Receiving works three ways:
//   * an RTL-SDR stick, tuned by rtl_fm to the "Listen on" frequency
//   * any sound input — the Mac's microphone next to an FM radio, or a radio's
//     headphone-out cabled into a line-in / USB audio adapter
// Decoded frames are handed to _mesh_receive on the main thread, exactly like a
// Bluetooth write, so signatures, encryption, rooms and relaying all apply.
//
// Channel plans:
//   shared    every Mac sends and listens on one frequency; before talking we
//             wait until nobody else is (listen-before-talk), and a relay is
//             dropped if another Mac already carried the same packet on FM
//   separate  send on one frequency, listen on another (two Macs, full duplex)
//
// Airtime is precious (about 1 s per packet at 2400 baud), so relayed HELLOs and
// "what I hear" packets stay on Bluetooth, and our own HELLO goes on FM every
// fourth time (once a minute).

.include "macros.inc"

.set FMQ_N,      32                  // queued transmissions
.set FMQ_SHIFT,  9                   // 512-byte slots
.set Q_DUE,      0
.set Q_LEN,      8
.set Q_HEARD,    16
.set Q_ID,       24
.set Q_RELAY,    32
.set Q_PKT,      40
.set HEARD_N,    128                 // packet ids heard on FM: id, count
.set DEV_N,      16                  // sound inputs offered in the window
.set FMW_W,      560
.set FMW_H,      560

// ---------------------------------------------------------------------------
.data
.p2align 3
.globl _g_fm_running
_g_fm_running:  .quad 0
_g_fm_rxkind:   .quad 0              // 0 none, 1 RTL-SDR, 2 sound input
.globl _g_fm_shared
_g_fm_shared:   .quad 1
.globl _g_fm_baud
_g_fm_baud:     .quad 2400
.globl _g_fm_repeat
_g_fm_repeat:   .quad 1              // send every frame twice ("fm repeat off" stops it)
_g_fm_aqin:     .quad 0
_g_fm_tid:      .quad 0
_g_fm_tick_on:  .quad 0
_g_fm_busy_ms:  .quad 0
_g_fm_lastflags: .quad 0
_g_fm_txlast:   .quad 0
.globl _g_fm_sent
_g_fm_sent:     .quad 0
_g_fm_held:     .quad 0
_g_fm_hello_t:  .quad 0              // when our hello last went out on FM
_g_fm_want_hello: .quad 0            // send our hello on the next tick
_g_fm_pend_t:   .quad 0              // last "waiting for its hello" note
_g_fm_hnote_t:  .quad 0              // last "heard … over FM" note
.globl _g_fm_heardpk
_g_fm_heardpk:  .quad 0
_g_fm_hello_n:  .quad 0
_g_fm_rxing:    .quad 0              // 1 while an FM packet is inside _mesh_receive
.globl _g_fm_test
_g_fm_test:     .quad 0              // selftest: frames are collected, not delivered
.globl _g_fm_test_n
_g_fm_test_n:   .quad 0
_g_fm_heard_pos: .quad 0
_g_fm_ndev:     .quad 0
_g_fm_ticks:    .quad 0
.globl _fm_envp
_fm_envp:       .quad 0
// window
_g_fm_win:      .quad 0
_g_fm_popup:    .quad 0
_g_fm_rxf:      .quad 0
_g_fm_txf:      .quad 0
_g_fm_samecb:   .quad 0
_g_fm_speed:    .quad 0
_g_fm_state:    .quad 0
_g_fm_stats:    .quad 0
_g_fm_levtxt:   .quad 0
_g_fm_level:    .quad 0
_g_fm_switch:   .quad 0
.zerofill __DATA,__bss,_g_fmq,(FMQ_N * 512),4
.zerofill __DATA,__bss,_g_fm_heard,(HEARD_N * 16),4
.zerofill __DATA,__bss,_g_fm_devname,(DEV_N * 8),4
.zerofill __DATA,__bss,_g_fm_devuid,(DEV_N * 8),4
.zerofill __DATA,__bss,_g_fm_rxfreq,16,4
.zerofill __DATA,__bss,_g_fm_txfreq,16,4
.zerofill __DATA,__bss,_g_fm_src,160,4
.zerofill __DATA,__bss,_g_fm_tpkt,256,4
.globl _g_fm_testbuf
.zerofill __DATA,__bss,_g_fm_testbuf,256,4
.zerofill __DATA,__bss,_g_fm_line,256,4
.zerofill __DATA,__bss,_g_fm_fecbuf,640,4

.section __TEXT,__const
.p2align 3
Lasbd_in:                            // 48 kHz, mono, 16-bit signed
    .double 48000.0
    .long 0x6C70636D, 12, 2, 1, 2, 1, 16, 0
Lc_fs2:     .double 1073741824.0     // 32768^2
Lc_ten:     .double 10.0
Lc_sixty:   .double 60.0
Lc_hund:    .double 100.0
Lc_zero:    .double 0.0
Lc_one:     .double 1.0
Lc_W:       .double 560.0
Lc_H:       .double 560.0
Lc_r16:     .double 16.0
Lc_s26:     .double 26.0
Lc_s13:     .double 13.0
Lc_s12:     .double 12.0
Lc_s15:     .double 15.0
// frames: x, y, w, h
Lf_title:   .double 24.0, 500.0, 400.0, 34.0
Lf_sub:     .double 24.0, 478.0, 520.0, 18.0
Lf_c1:      .double 16.0, 356.0, 528.0, 108.0     // on/off + send card
Lf_c2:      .double 16.0, 196.0, 528.0, 148.0     // receive card
Lf_c3:      .double 16.0, 66.0, 528.0, 118.0      // status card
Lf_on:      .double 36.0, 424.0, 300.0, 22.0
Lf_sw:      .double 480.0, 422.0, 44.0, 24.0
Lf_txl:     .double 36.0, 390.0, 120.0, 20.0
Lf_txf:     .double 160.0, 388.0, 80.0, 24.0
Lf_txn:     .double 250.0, 391.0, 280.0, 18.0
Lf_rxh:     .double 36.0, 312.0, 200.0, 20.0
Lf_srcl:    .double 36.0, 282.0, 120.0, 20.0
Lf_src:     .double 160.0, 278.0, 364.0, 26.0
Lf_rxl:     .double 36.0, 246.0, 120.0, 20.0
Lf_rxf:     .double 160.0, 244.0, 80.0, 24.0
Lf_spl:     .double 260.0, 246.0, 60.0, 20.0
Lf_sp:      .double 320.0, 242.0, 120.0, 26.0
Lf_same:    .double 36.0, 208.0, 480.0, 22.0
Lf_sth:     .double 36.0, 154.0, 200.0, 20.0
Lf_lev:     .double 36.0, 128.0, 300.0, 16.0
Lf_levt:    .double 346.0, 126.0, 180.0, 20.0
Lf_state:   .double 36.0, 100.0, 490.0, 20.0
Lf_stats:   .double 36.0, 76.0, 490.0, 20.0
Lf_apply:   .double 324.0, 18.0, 220.0, 34.0
Lf_test:    .double 16.0, 18.0, 180.0, 34.0
.section __DATA,__const
.p2align 3
Lspeeds:    .quad Ls_b1200, Ls_b2400, Ls_b4800

.text
.p2align 2

// ===========================================================================
// Settings (saved with the other preferences)
// ===========================================================================

// void _fm_load(void) — frequencies, channel plan, speed and source
.globl _fm_load
_fm_load:
    ENTER 32
    ADRL x0, Lk_rx
    ADRL x1, _g_fm_rxfreq
    mov  x2, #16
    bl   _pref_get
    ADRL x0, Lk_tx
    ADRL x1, _g_fm_txfreq
    mov  x2, #16
    bl   _pref_get
    ADRL x0, Lk_src
    ADRL x1, _g_fm_src
    mov  x2, #160
    bl   _pref_get
    ADRL x19, _g_fm_rxfreq           // defaults: 88.1 both ways
    ldrb w9, [x19]
    cbnz w9, 1f
    mov  x0, x19
    ADRL x1, Ls_def_freq
    mov  x2, #16
    bl   _strlcpy
1:  ADRL x19, _g_fm_txfreq
    ldrb w9, [x19]
    cbnz w9, 2f
    mov  x0, x19
    ADRL x1, Ls_def_freq
    mov  x2, #16
    bl   _strlcpy
2:  ADRL x0, Lk_shared
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #96]
    cmp  w9, #'0'
    cset x9, ne                      // shared unless saved as "0"
    ADRL x8, _g_fm_shared
    str  x9, [x8]
    ADRL x0, Lk_baud
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    add  x0, sp, #96
    bl   _atoi
    mov  x9, #2400
    cmp  x0, #1200
    b.eq 3f
    mov  x10, #4800
    cmp  x0, x10
    b.eq 3f
    mov  x0, x9
3:  ADRL x8, _g_fm_baud
    str  x0, [x8]
    ADRL x0, Lk_repeat               // twice unless saved as "0"
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #96]
    cmp  w9, #'0'
    cset x9, ne
    ADRL x8, _g_fm_repeat
    str  x9, [x8]
    LEAVE 32

// ===========================================================================
// Start and stop
// ===========================================================================

// void _fm_start(void) — main thread; called when the service is switched on
.globl _fm_start
_fm_start:
    ENTER 32
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbnz x9, Lfs_done
    bl   _fm_load
    // rtl_fm and curl live in Homebrew; apps opened from Finder get a short PATH
    ADRL x0, Ls_PATH
    ADRL x1, Ls_pathval
    mov  w2, #1
    bl   _setenv
    bl   __NSGetEnviron
    ldr  x0, [x0]
    ADRL x8, _fm_envp
    str  x0, [x8]
    ADRL x8, _g_fm_baud
    ldr  x0, [x8]
    bl   _fm_modem_init
    bl   _fm_counters_reset
    bl   _fm_counts_zero
    bl   _fm_rx_reset
    ADRL x8, _g_fm_flags
    ldr  w9, [x8]
    ADRL x8, _g_fm_lastflags
    str  x9, [x8]
    bl   _fm_tx_start                // sound out (headphone jack)
    cbz  w0, Lfs_out_ok
    ADRL x0, Ls_no_out
    bl   _chat_line
Lfs_out_ok:
    ADRL x8, _g_fm_running
    mov  x9, #1
    str  x9, [x8]
    // ---- receive side ----
    ADRL x19, _g_fm_src
    ldrb w9, [x19]
    cbz  w9, Lfs_rtl
    mov  x0, x19
    ADRL x1, Ls_rtl_key
    bl   _strcmp
    cbz  w0, Lfs_rtl
    mov  x0, x19                     // a sound input, by its UID
    bl   _fm_ain_start
    cbz  x0, Lfs_ain_ok
    ADRL x0, Ls_no_in
    bl   _chat_line
    b    Lfs_said
Lfs_ain_ok:
    ADRL x8, _g_fm_rxkind
    mov  x9, #2
    str  x9, [x8]
    b    Lfs_said
Lfs_rtl:
    ADRL x8, _g_fm_rx_err
    str  wzr, [x8]
    mov  x0, #0
    ADRL x1, _g_fm_rxfreq
    ADRL x8, _fm_envp
    ldr  x2, [x8]
    bl   _fm_rx_open
    tbnz w0, #31, Lfs_rtl_fail
    sxtw x2, w0                      // reader thread gets the fd
    mov  x3, x2
    ADRL x0, _g_fm_tid
    mov  x1, #0
    ADRL x2, _fm_reader
    bl   _pthread_create
    ADRL x8, _g_fm_rxkind
    mov  x9, #1
    str  x9, [x8]
    b    Lfs_said
Lfs_rtl_fail:
    ADRL x0, Ls_no_rtl
    ADRL x8, _g_fm_rx_err
    ldr  w9, [x8]
    cmp  w9, #1
    ADRL x8, Ls_bad_freq
    csel x0, x8, x0, eq
    bl   _chat_line
Lfs_said:
    bl   _fm_state_line
    ADRL x0, _g_fm_line
    bl   _chat_line
    ADRL x8, _g_fm_tick_on
    ldr  x9, [x8]
    cbnz x9, Lfs_done
    mov  x9, #1
    str  x9, [x8]
    bl   _fm_arm_tick
Lfs_done:
    LEAVE 32

// void _fm_stop(void) — main thread; the service was switched off
.globl _fm_stop
_fm_stop:
    ENTER 0
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbz  x9, Lft_done
    str  xzr, [x8]
    ADRL x8, _g_fm_rxkind
    ldr  x19, [x8]
    str  xzr, [x8]
    cmp  x19, #1
    b.ne Lft_ain
    bl   _fm_rx_close                // ends rtl_fm, so the reader sees end-of-stream
    ADRL x8, _g_fm_tid
    ldr  x0, [x8]
    mov  x1, #0
    bl   _pthread_join
    b    Lft_q
Lft_ain:
    cmp  x19, #2
    b.ne Lft_q
    ADRL x8, _g_fm_aqin
    ldr  x0, [x8]
    cbz  x0, Lft_q
    mov  w1, #1
    bl   _AudioQueueStop
    ADRL x8, _g_fm_aqin
    ldr  x0, [x8]
    mov  w1, #1
    bl   _AudioQueueDispose
    ADRL x8, _g_fm_aqin
    str  xzr, [x8]
Lft_q:
    bl   _fm_tx_flush
    ADRL x0, _g_fmq                  // forget anything still waiting
    mov  x1, #0
    mov  x2, #(FMQ_N * 512)
    bl   _memset
    ADRL x0, Ls_fm_off
    bl   _chat_line
Lft_done:
    LEAVE 0

// void _fm_restart(void) — after the settings changed
.globl _fm_restart
_fm_restart:
    ENTER 0
    ADRL x8, _g_fm_running
    ldr  x19, [x8]
    cbz  x19, 1f
    bl   _fm_stop
    bl   _fm_start
1:  LEAVE 0

// RTL-SDR reader thread: x0 = fd of rtl_fm's audio
_fm_reader:
    ENTER 0
    mov  x19, x0
1:  ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbz  x9, 2f
    mov  w0, w19
    bl   _fm_rx_service              // read, measure level, demodulate
    cbnz x0, 1b
2:  mov  x0, #0
    LEAVE 0

// ===========================================================================
// Sound input (microphone, line-in, USB audio) through an AudioQueue
// ===========================================================================

// long _fm_ain_start(const char *uid) -> 0 ok, else an error
_fm_ain_start:
    ENTER 32
    mov  x19, x0
    ADRL x0, Lasbd_in
    ADRL x1, _fm_ain_cb
    mov  x2, #0
    mov  x3, #0
    mov  x4, #0
    mov  w5, #0
    ADRL x6, _g_fm_aqin
    bl   _AudioQueueNewInput
    cbnz w0, Lai_fail
    ldrb w9, [x19]                   // a chosen device (else the Mac's current input)
    cbz  w9, Lai_bufs
    mov  x0, x19
    bl   _nsstr
    str  x0, [sp, #96]               // CFStringRef (toll-free bridged)
    ADRL x8, _g_fm_aqin
    ldr  x0, [x8]
    MOVI w1, 0x61716364              // kAudioQueueProperty_CurrentDevice 'aqcd'
    add  x2, sp, #96
    mov  w3, #8
    bl   _AudioQueueSetProperty
    // a device that has gone away: fall back to the current input
Lai_bufs:
    mov  x20, #3
Lai_buf:
    ADRL x8, _g_fm_aqin
    ldr  x0, [x8]
    mov  w1, #4096
    add  x2, sp, #104
    bl   _AudioQueueAllocateBuffer
    cbnz w0, Lai_fail
    ADRL x8, _g_fm_aqin
    ldr  x0, [x8]
    ldr  x1, [sp, #104]
    mov  w2, #0
    mov  x3, #0
    bl   _AudioQueueEnqueueBuffer
    subs x20, x20, #1
    b.ne Lai_buf
    ADRL x8, _g_fm_aqin
    ldr  x0, [x8]
    mov  x1, #0
    bl   _AudioQueueStart
    cbnz w0, Lai_fail
    mov  x0, #0
    LEAVE 32
Lai_fail:
    sxtw x19, w0
    ADRL x8, _g_fm_aqin
    ldr  x0, [x8]
    cbz  x0, 1f
    mov  w1, #1
    bl   _AudioQueueDispose
    ADRL x8, _g_fm_aqin
    str  xzr, [x8]
1:  mov  x0, x19
    cmp  x0, #0
    csinc x0, x0, xzr, ne
    LEAVE 32

// input callback (AudioQueue's own thread): (user, queue, buffer, time, n, descs)
_fm_ain_cb:
    ENTER 0
    mov  x19, x1
    mov  x20, x2
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbz  x9, 3f
    ldr  x21, [x20, #8]              // mAudioData
    ldr  w22, [x20, #16]             // mAudioDataByteSize
    lsr  x22, x22, #1                // samples
    cbz  x22, 3f
    mov  x0, #0                      // level: mean square
    mov  x1, #0
1:  cmp  x1, x22
    b.hs 2f
    ldrsh x2, [x21, x1, lsl #1]
    madd x0, x2, x2, x0
    add  x1, x1, #1
    b    1b
2:  udiv x0, x0, x22
    ADRL x8, _fm_level_ms
    str  x0, [x8]
    mov  x0, x21
    mov  w1, w22
    bl   _fm_demod
3:  mov  x0, x19
    mov  x1, x20
    mov  w2, #0
    mov  x3, #0
    bl   _AudioQueueEnqueueBuffer
    LEAVE 0

// ===========================================================================
// Receiving: frames from the demodulator
// ===========================================================================

// void _fm_frame_in(const uint8 *p, int len) — radio thread
.globl _fm_frame_in
_fm_frame_in:
    ENTER 0
    mov  x19, x0
    sxtw x20, w1
    ADRL x8, _g_fm_test
    ldr  x9, [x8]
    cbz  x9, 1f
    cmp  x20, #256                   // selftest: keep the last frame
    b.hi 2f
    ADRL x0, _g_fm_testbuf
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    ADRL x8, _g_fm_test_n
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    b    2f
1:  add  x0, x20, #8
    bl   _malloc
    cbz  x0, 2f
    mov  x21, x0
    str  x20, [x21]
    add  x0, x21, #8
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    LDGOT x0, __dispatch_main_q
    mov  x1, x21
    ADRL x2, _fm_rx_main
    bl   _dispatch_async_f
2:  LEAVE 0

// main thread: [len][bytes] from the radio
_fm_rx_main:
    ENTER 0
    mov  x19, x0
    ldr  x20, [x19]
    add  x21, x19, #8
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbz  x9, 9f
    cmp  x20, #HDR
    b.lo 9f
    cmp  x20, #PKT_MAX
    b.hi 9f
    ldrb w9, [x21]
    cmp  w9, #'M'
    b.ne 9f
    mov  x0, x21                     // our own sound coming back: not news
    bl   _pkt_sender
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    cmp  x0, x9
    b.eq 9f
    ADRL x8, _g_rx_pended
    str  xzr, [x8]
    ADRL x8, _g_fm_heardpk
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    ldr  x0, [x21, #4]
    bl   _fm_heard_add
    ADRL x8, _g_fm_rxing
    mov  x9, #1
    str  x9, [x8]
    mov  x0, x21
    mov  x1, x20
    bl   _mesh_receive
    ADRL x8, _g_fm_rxing
    str  xzr, [x8]
    mov  x0, x21
    mov  x1, x20
    bl   _fm_rx_note
9:  mov  x0, x19
    bl   _free
    LEAVE 0

// void _fm_rx_note(pkt, len) — a line in Main for what FM brought: a hello (so you know
//   the radio link works), or a message held until its sender's hello is heard
_fm_rx_note:
    ENTER 96                          // [96] nick (32)  [128] quality (48)
    mov  x19, x0
    mov  x20, x1
    add  x0, sp, #128
    bl   _fx_quality
    ldrb w9, [x19, #3]
    cmp  w9, #T_HELLO
    b.ne Lrn2_msg
    ldrb w9, [x19, #24]               // HELLO: +24 nlen, +25 nick
    cmp  w9, #NICK_MAX
    mov  w10, #NICK_MAX
    csel w21, w10, w9, hi
    add  x9, x21, #25
    cmp  x9, x20
    b.hi Lrn2_done
    add  x0, sp, #96
    add  x1, x19, #25
    mov  x2, x21
    bl   _memcpy
    add  x8, sp, #96
    strb wzr, [x8, x21]
    add  x0, sp, #96
    bl   _sanitize
    mov  x0, #0                       // at most once a minute
    bl   _time
    ADRL x8, _g_fm_hnote_t
    ldr  x9, [x8]
    sub  x9, x0, x9
    cmp  x9, #60
    b.lt Lrn2_done
    str  x0, [x8]
    ADRL x0, Lf_fm_heard_hello
    add  x1, sp, #96
    add  x2, sp, #128
    bl   _chat_fmt
    b    Lrn2_done
Lrn2_msg:
    ADRL x8, _g_rx_pended
    ldr  x9, [x8]
    cbz  x9, Lrn2_done
    mov  x0, #0                       // at most once a minute
    bl   _time
    ADRL x8, _g_fm_pend_t
    ldr  x9, [x8]
    sub  x9, x0, x9
    cmp  x9, #60
    b.lt Lrn2_done
    str  x0, [x8]
    ADRL x0, Lf_fm_pended
    add  x1, sp, #128
    bl   _chat_fmt
Lrn2_done:
    LEAVE 96

// void _fx_quality(char *out48) — "clean" or "5 bytes repaired" (the last frame)
_fx_quality:
    ENTER 0
    mov  x19, x0
    ADRL x8, _fx_last
    ldr  x9, [x8]
    cmp  x9, #0
    b.gt 1f
    mov  x0, x19
    ADRL x1, Ls_last_clean
    mov  x2, #48
    bl   _strlcpy
    LEAVE 0
1:  str  x9, [sp]
    mov  x0, x19
    mov  x1, #48
    ADRL x2, Lf_last_fixed
    bl   _snprintf
    LEAVE 0

// void _fm_counts_zero(void) — the window's counters start again with the radio
_fm_counts_zero:
    ADRL x8, _g_fm_heardpk
    str  xzr, [x8]
    ADRL x8, _g_fm_sent
    str  xzr, [x8]
    ADRL x8, _g_fm_held
    str  xzr, [x8]
    ADRL x8, _fx_ok
    str  xzr, [x8]
    ADRL x8, _fx_fixed
    str  xzr, [x8]
    ADRL x8, _fx_fail
    str  xzr, [x8]
    ADRL x8, _fx_dup
    str  xzr, [x8]
    ADRL x8, _fx_last
    mov  x9, #-2
    str  x9, [x8]
    ret

// heard table: how many times each packet id went by on FM
_fm_heard_find:                      // x0 = id -> x0 = entry or 0 (x8..x11)
    ADRL x8, _g_fm_heard
    mov  x9, #0
1:  cmp  x9, #HEARD_N
    b.hs 2f
    add  x10, x8, x9, lsl #4
    ldr  x11, [x10]
    cmp  x11, x0
    b.eq 3f
    add  x9, x9, #1
    b    1b
2:  mov  x0, #0
    ret
3:  mov  x0, x10
    ret

.globl _fm_heard_add
_fm_heard_add:
    ENTER 0
    mov  x19, x0
    bl   _fm_heard_find
    cbz  x0, 1f
    ldr  x9, [x0, #8]
    add  x9, x9, #1
    str  x9, [x0, #8]
    LEAVE 0
1:  ADRL x8, _g_fm_heard_pos
    ldr  x9, [x8]
    add  x10, x9, #1
    str  x10, [x8]
    and  x9, x9, #(HEARD_N - 1)
    ADRL x8, _g_fm_heard
    add  x8, x8, x9, lsl #4
    str  x19, [x8]
    mov  x9, #1
    str  x9, [x8, #8]
    LEAVE 0

// long _fm_heard_count(uint64 id)
.globl _fm_heard_count
_fm_heard_count:
    ENTER 0
    bl   _fm_heard_find
    cbz  x0, 1f
    ldr  x0, [x0, #8]
1:  LEAVE 0

// ===========================================================================
// Sending: the queue
// ===========================================================================

// long _fm_tx_packet(const uint8 *pkt, size_t len) -> 1 if it will go out on FM
//   Called for every packet _ble_broadcast sends (ours and relays).
.globl _fm_tx_packet
_fm_tx_packet:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbz  x9, Lfq_no
    cmp  x20, #PKT_MAX
    b.hi Lfq_no
    cmp  x20, #HDR
    b.lo Lfq_no
    ldrb w21, [x19, #3]              // type
    ldrb w22, [x19, #2]              // ttl
    cmp  w21, #T_SEEN                // "what I hear" stays on Bluetooth
    b.eq Lfq_no
    cmp  w21, #T_HELLO
    b.ne Lfq_own
    cmp  w22, #TTL0                  // others' hellos: not worth the airtime
    b.ne Lfq_no
    ADRL x8, _g_fm_hello_n           // ours: every fourth one (once a minute)
    ldr  x9, [x8]
    add  x10, x9, #1
    str  x10, [x8]
    tst  x9, #3
    b.ne Lfq_no
    mov  x0, #0
    bl   _time
    ADRL x8, _g_fm_hello_t
    str  x0, [x8]
    b    Lfq_go
Lfq_own:                             // our own message, and our hello hasn't been on
    cmp  w22, #TTL0                  //   FM for 2 minutes: send it too (next tick), so
    b.ne Lfq_go                      //   the other Macs can check our signature
    mov  x0, #0
    bl   _time
    ADRL x8, _g_fm_hello_t
    ldr  x9, [x8]
    sub  x9, x0, x9
    cmp  x9, #120
    b.lt Lfq_go
    ADRL x8, _g_fm_want_hello
    mov  x9, #1
    str  x9, [x8]
Lfq_go:
    ADRL x23, _g_fmq                 // a free slot
    mov  x24, #0
1:  cmp  x24, #FMQ_N
    b.hs Lfq_full
    add  x9, x23, x24, lsl #FMQ_SHIFT
    ldr  x10, [x9, #Q_LEN]
    cbz  x10, 2f
    add  x24, x24, #1
    b    1b
2:  add  x23, x23, x24, lsl #FMQ_SHIFT
    ldr  x0, [x19, #4]
    str  x0, [x23, #Q_ID]
    bl   _fm_heard_count
    str  x0, [x23, #Q_HEARD]
    cmp  w22, #TTL0
    cset x9, ne
    str  x9, [x23, #Q_RELAY]
    add  x0, x23, #Q_PKT
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    // a little random wait: relays longer, so the nearest Mac usually goes first
    bl   _fm_rand
    ADRL x8, _g_fm_shared
    ldr  x9, [x8]
    ldr  x10, [x23, #Q_RELAY]
    mov  w11, #400
    mov  w12, #50
    cbz  x10, 3f
    mov  w11, #1300
    mov  w12, #200
3:  cbnz x9, 4f
    mov  w11, #150                   // separate frequencies: no one to collide with
    mov  w12, #20
4:  udiv w13, w0, w11
    msub w13, w13, w11, w0
    add  w24, w13, w12
    bl   _fm_now_ms
    add  x0, x0, x24
    str  x0, [x23, #Q_DUE]
    str  x20, [x23, #Q_LEN]          // last: the slot is now live
    mov  x0, #1
    LEAVE 0
Lfq_full:
    ADRL x8, _g_fm_held
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
Lfq_no:
    mov  x0, #0
    LEAVE 0

_fm_arm_tick:
    ENTER 0
    mov  x0, #0                      // DISPATCH_TIME_NOW
    MOVI x1, 100000000               // 100 ms
    bl   _dispatch_time
    mov  x19, x0
    mov  x0, x19
    LDGOT x1, __dispatch_main_q
    mov  x2, #0
    ADRL x3, _fm_tick
    bl   _dispatch_after_f
    LEAVE 0

// main thread, ten times a second while the radio is on
_fm_tick:
    ENTER 16
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbnz x9, 1f
    ADRL x8, _g_fm_tick_on
    str  xzr, [x8]
    LEAVE 16
1:  ADRL x8, _g_fm_want_hello      // a message is waiting for our hello to go with it
    ldr  x9, [x8]
    cbz  x9, 0f
    str  xzr, [x8]
    ADRL x8, _g_fm_hello_n
    str  xzr, [x8]
    bl   _mesh_send_hello
0:  bl   _fm_now_ms
    mov  x19, x0                     // now
    // someone else transmitting? (HDLC flags are being heard)
    ADRL x8, _g_fm_flags
    ldr  w9, [x8]
    ADRL x8, _g_fm_lastflags
    ldr  x10, [x8]
    cmp  x9, x10
    b.eq 2f
    str  x9, [x8]
    ADRL x8, _g_fm_busy_ms
    str  x19, [x8]
2:  bl   _fm_tx_pending
    mov  x20, x0
    cbz  x20, 3f
    ADRL x8, _g_fm_txlast
    str  x19, [x8]
3:  cmp  x20, #2400                  // still sending: packets wait in the queue, not in
    b.hi 8f                          //   the sound ring (a full ring would stall this thread)
    mov  x21, #0                     // busy?
    ADRL x8, _g_fm_shared
    ldr  x9, [x8]
    cbz  x9, 4f
    cbnz x20, 4f                     // we are on the air ourselves: that's our own echo
    ADRL x8, _g_fm_txlast
    ldr  x9, [x8]
    sub  x9, x19, x9
    cmp  x9, #600
    b.lo 4f                          // our own tail still ringing in the receiver
    ADRL x8, _g_fm_busy_ms
    ldr  x9, [x8]
    sub  x9, x19, x9
    cmp  x9, #350
    cset x21, lo
4:  // one due packet per tick
    ADRL x22, _g_fmq
    mov  x23, #0
5:  cmp  x23, #FMQ_N
    b.hs 8f
    add  x24, x22, x23, lsl #FMQ_SHIFT
    ldr  x9, [x24, #Q_LEN]
    cbz  x9, 7f
    ldr  x9, [x24, #Q_DUE]
    cmp  x9, x19
    b.hi 7f
    ldr  x9, [x24, #Q_RELAY]         // a relay someone else already carried on FM
    cbz  x9, 6f
    ldr  x0, [x24, #Q_ID]
    bl   _fm_heard_count
    ldr  x9, [x24, #Q_HEARD]
    cmp  x0, x9
    b.ls 6f
    str  xzr, [x24, #Q_LEN]
    ADRL x8, _g_fm_held
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    b    7f
6:  cbz  x21, 61f                    // channel busy: wait a little longer
    bl   _fm_rand
    mov  w11, #700
    udiv w13, w0, w11
    msub w13, w13, w11, w0
    add  x13, x13, #200
    add  x13, x13, x19
    str  x13, [x24, #Q_DUE]
    b    7f
61: add  x0, x24, #Q_PKT
    ldr  x1, [x24, #Q_LEN]
    bl   _fm_send                    // tones into the transmit ring
    str  xzr, [x24, #Q_LEN]
    ADRL x8, _g_fm_sent
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    ADRL x8, _g_fm_txlast
    str  x19, [x8]
    b    8f
7:  add  x23, x23, #1
    b    5b
8:  // the window, twice a second
    ADRL x8, _g_fm_ticks
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    tst  x9, #3
    b.ne 9f
    bl   _fm_win_update
9:  bl   _fm_arm_tick
    LEAVE 16

// ===========================================================================
// Text for the window and the mesh feed
// ===========================================================================

// void _fm_state_line(void) -> _g_fm_line: what the radio is doing, in words
.globl _fm_state_line
_fm_state_line:
    ENTER 32
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbnz x9, 1f
    ADRL x0, _g_fm_line
    ADRL x1, Ls_state_off
    mov  x2, #256
    bl   _strlcpy
    LEAVE 32
1:  ADRL x8, _g_fm_txfreq
    str  x8, [sp]
    ADRL x8, _g_fm_rxfreq
    str  x8, [sp, #8]
    ADRL x8, _g_fm_baud
    ldr  x9, [x8]
    str  x9, [sp, #16]
    ADRL x10, Ls_plan_shared
    ADRL x8, _g_fm_shared
    ldr  x9, [x8]
    cbnz x9, 2f
    ADRL x10, Ls_plan_sep
2:  str  x10, [sp, #24]
    ADRL x2, Lf_state_none
    ADRL x8, _g_fm_rxkind
    ldr  x9, [x8]
    cmp  x9, #1
    b.ne 3f
    ADRL x2, Lf_state_rtl
3:  cmp  x9, #2
    b.ne 4f
    ADRL x2, Lf_state_in
4:  ADRL x0, _g_fm_line
    mov  x1, #256
    bl   _snprintf
    LEAVE 32

// ===========================================================================
// The FM Radio window
// ===========================================================================

// void _fm_devices(void) — list the Mac's sound inputs (name + UID)
_fm_devices:
    ENTER 80                         // [96] address  [112] size  [120] ids (8 x u32 used as buffer ptr)
    // release the previous list
    mov  x19, #0
    ADRL x8, _g_fm_ndev
    ldr  x20, [x8]
Lfd_rel:
    cmp  x19, x20
    b.hs Lfd_rel_done
    ADRL x8, _g_fm_devname
    ldr  x0, [x8, x19, lsl #3]
    bl   _CFRelease
    ADRL x8, _g_fm_devuid
    ldr  x0, [x8, x19, lsl #3]
    bl   _CFRelease
    add  x19, x19, #1
    b    Lfd_rel
Lfd_rel_done:
    ADRL x8, _g_fm_ndev
    str  xzr, [x8]
    MOVI w9, 0x64657623              // kAudioHardwarePropertyDevices 'dev#'
    MOVI w10, 0x676C6F62             // global scope 'glob'
    stp  w9, w10, [sp, #96]
    str  wzr, [sp, #104]
    mov  w0, #1                      // kAudioObjectSystemObject
    add  x1, sp, #96
    mov  w2, #0
    mov  x3, #0
    add  x4, sp, #112
    bl   _AudioObjectGetPropertyDataSize
    cbnz w0, Lfd_done
    ldr  w0, [sp, #112]
    cbz  w0, Lfd_done
    bl   _malloc
    cbz  x0, Lfd_done
    mov  x21, x0                     // device ids
    mov  w0, #1
    add  x1, sp, #96
    mov  w2, #0
    mov  x3, #0
    add  x4, sp, #112
    mov  x5, x21
    bl   _AudioObjectGetPropertyData
    cbnz w0, Lfd_free
    ldr  w22, [sp, #112]
    lsr  w22, w22, #2                // count
    mov  x23, #0
Lfd_loop:
    cmp  x23, x22
    b.hs Lfd_free
    ADRL x8, _g_fm_ndev
    ldr  x9, [x8]
    cmp  x9, #DEV_N
    b.hs Lfd_free
    ldr  w24, [x21, x23, lsl #2]     // device id
    MOVI w9, 0x73746D23              // kAudioDevicePropertyStreams 'stm#'
    MOVI w10, 0x696E7074             // input scope 'inpt'
    stp  w9, w10, [sp, #96]
    str  wzr, [sp, #104]
    str  wzr, [sp, #112]
    mov  w0, w24
    add  x1, sp, #96
    mov  w2, #0
    mov  x3, #0
    add  x4, sp, #112
    bl   _AudioObjectGetPropertyDataSize
    cbnz w0, Lfd_next
    ldr  w9, [sp, #112]
    cbz  w9, Lfd_next                // no input streams
    MOVI w9, 0x6C6E616D              // kAudioObjectPropertyName 'lnam'
    MOVI w10, 0x676C6F62
    stp  w9, w10, [sp, #96]
    mov  w9, #8
    str  w9, [sp, #112]
    str  xzr, [sp, #128]
    mov  w0, w24
    add  x1, sp, #96
    mov  w2, #0
    mov  x3, #0
    add  x4, sp, #112
    add  x5, sp, #128
    bl   _AudioObjectGetPropertyData
    cbnz w0, Lfd_next
    MOVI w9, 0x75696420              // kAudioDevicePropertyDeviceUID 'uid '
    MOVI w10, 0x676C6F62
    stp  w9, w10, [sp, #96]
    mov  w9, #8
    str  w9, [sp, #112]
    str  xzr, [sp, #136]
    mov  w0, w24
    add  x1, sp, #96
    mov  w2, #0
    mov  x3, #0
    add  x4, sp, #112
    add  x5, sp, #136
    bl   _AudioObjectGetPropertyData
    cbnz w0, Lfd_noname
    ldr  x9, [sp, #136]
    cbz  x9, Lfd_noname
    ADRL x8, _g_fm_ndev
    ldr  x10, [x8]
    ADRL x11, _g_fm_devname
    ldr  x12, [sp, #128]
    str  x12, [x11, x10, lsl #3]
    ADRL x11, _g_fm_devuid
    str  x9, [x11, x10, lsl #3]
    add  x10, x10, #1
    str  x10, [x8]
    b    Lfd_next
Lfd_noname:
    ldr  x0, [sp, #128]
    cbz  x0, Lfd_next
    bl   _CFRelease
Lfd_next:
    add  x23, x23, #1
    b    Lfd_loop
Lfd_free:
    mov  x0, x21
    bl   _free
Lfd_done:
    LEAVE 80

// - (void)fmShow:(id)sender — Mesh › FM Radio…
.globl _fm_show
_fm_show:
    ENTER 0
    bl   _fm_load
    ADRL x8, _g_fm_win
    ldr  x0, [x8]
    cbnz x0, Lfw_fill
    bl   _fm_build
Lfw_fill:
    bl   _fm_fill
    ADRL x8, _g_fm_win
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    bl   _fm_win_update              // once it is visible (it skips hidden windows)
    LEAVE 0

// build the window once (dark, cards, like the Settings window)
_fm_build:
    ENTER 32
    CLS  Ls_NSWindow
    MSG0 Ls_alloc
    mov  x20, x0
    SELX1 Ls_initWithContentRect
    mov  x0, x20
    LDD  d0, Lc_zero
    LDD  d1, Lc_zero
    LDD  d2, Lc_W
    LDD  d3, Lc_H
    mov  x2, #32775                  // titled|closable|miniaturizable|fullSizeContentView
    mov  x3, #2
    mov  x4, #0
    bl   _objc_msgSend
    mov  x20, x0
    ADRL x8, _g_fm_win
    str  x20, [x8]
    ADRL x0, Ls_win_title
    bl   _nsstr
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_setTitle
    mov  x0, x20
    mov  x2, #0
    MSG1 Ls_setReleasedWhenClosed
    mov  x0, x20
    mov  x2, #1
    MSG1 Ls_setTitlebarAppearsTransparent
    mov  x0, x20
    mov  x2, #1
    MSG1 Ls_setTitleVisibility
    mov  x0, #0x1C1E
    movk x0, #0x1C, lsl #16
    bl   _rgb
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_setBackgroundColor
    mov  x0, x20
    MSG0 Ls_center
    mov  x0, x20
    MSG0 Ls_contentView
    mov  x21, x0
    // title
    ADRL x0, Ls_win_title
    mov  x1, #0
    mov  x2, #1
    mov  x3, x21
    ADRL x8, Lf_title
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s26
    bl   _mk_label
    ADRL x0, Ls_win_sub
    mov  x1, #0
    mov  x2, #0
    mov  x3, x21
    ADRL x8, Lf_sub
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s13
    bl   _mk_label
    bl   _dim_label
    // three cards
    ADRL x22, Lf_c1
    mov  x23, #3
1:  mov  x0, x21
    ldp  d0, d1, [x22]
    ldp  d2, d3, [x22, #16]
    bl   _plain_view
    mov  x1, #0x2C2E
    movk x1, #0x2C, lsl #16
    LDD  d0, Lc_r16
    bl   _card
    add  x22, x22, #32
    subs x23, x23, #1
    b.ne 1b
    // ---- card 1: on/off and the transmitter ----
    ADRL x0, Ls_on_title
    ADRL x8, Lf_on
    LDD  d4, Lc_s15
    mov  x2, #1
    bl   Lfb_label
    CLS  Ls_NSSwitch
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithFrame
    mov  x0, x22
    ADRL x8, Lf_sw
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x22, x0
    ADRL x8, _g_fm_switch
    str  x22, [x8]
    mov  x2, #SVC_FM
    MSG1 Ls_setTag
    mov  x0, x22
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    MSG1 Ls_setTarget
    ADRL x0, Ls_m_svcToggled
    bl   _sel_registerName
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setAction
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_addSubview
    ADRL x0, Ls_tx_label
    ADRL x8, Lf_txl
    LDD  d4, Lc_s13
    mov  x2, #0
    bl   Lfb_label
    ADRL x8, Lf_txf
    bl   Lfb_field
    ADRL x8, _g_fm_txf
    str  x0, [x8]
    ADRL x0, Ls_tx_note
    ADRL x8, Lf_txn
    LDD  d4, Lc_s12
    mov  x2, #0
    bl   Lfb_label
    bl   _dim_label
    // ---- card 2: receiving ----
    ADRL x0, Ls_rx_title
    ADRL x8, Lf_rxh
    LDD  d4, Lc_s15
    mov  x2, #1
    bl   Lfb_label
    ADRL x0, Ls_src_label
    ADRL x8, Lf_srcl
    LDD  d4, Lc_s13
    mov  x2, #0
    bl   Lfb_label
    CLS  Ls_NSPopUpButton
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithFrame_pullsDown
    mov  x0, x22
    ADRL x8, Lf_src
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    mov  w2, #0
    bl   _objc_msgSend
    ADRL x8, _g_fm_popup
    str  x0, [x8]
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_addSubview
    ADRL x0, Ls_rx_label
    ADRL x8, Lf_rxl
    LDD  d4, Lc_s13
    mov  x2, #0
    bl   Lfb_label
    ADRL x8, Lf_rxf
    bl   Lfb_field
    ADRL x8, _g_fm_rxf
    str  x0, [x8]
    ADRL x0, Ls_sp_label
    ADRL x8, Lf_spl
    LDD  d4, Lc_s13
    mov  x2, #0
    bl   Lfb_label
    CLS  Ls_NSPopUpButton
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithFrame_pullsDown
    mov  x0, x22
    ADRL x8, Lf_sp
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    mov  w2, #0
    bl   _objc_msgSend
    mov  x22, x0
    ADRL x8, _g_fm_speed
    str  x22, [x8]
    ADRL x23, Lspeeds
    mov  x24, #3
2:  ldr  x0, [x23], #8
    bl   _nsstr
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_addItemWithTitle
    subs x24, x24, #1
    b.ne 2b
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_addSubview
    CLS  Ls_NSButton                 // checkbox: one shared frequency
    mov  x23, x0                     //   (the class first: calls clobber x2..x7)
    ADRL x0, Ls_same_title
    bl   _nsstr
    mov  x2, x0
    mov  x0, x23
    mov  x3, #0
    mov  x4, #0
    MSG3 Ls_checkboxWithTitle
    mov  x22, x0
    ADRL x8, _g_fm_samecb
    str  x22, [x8]
    SELX1 Ls_setFrame
    mov  x0, x22
    ADRL x8, Lf_same
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_addSubview
    // ---- card 3: what is happening ----
    ADRL x0, Ls_st_title
    ADRL x8, Lf_sth
    LDD  d4, Lc_s15
    mov  x2, #1
    bl   Lfb_label
    CLS  Ls_NSLevelIndicator
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithFrame
    mov  x0, x22
    ADRL x8, Lf_lev
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x22, x0
    ADRL x8, _g_fm_level
    str  x22, [x8]
    mov  x2, #1                      // continuous capacity
    MSG1 Ls_setLevelIndicatorStyle
    SELX1 Ls_setMaxValue
    mov  x0, x22
    LDD  d0, Lc_hund
    bl   _objc_msgSend
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_addSubview
    ADRL x0, Ls_empty
    ADRL x8, Lf_levt
    LDD  d4, Lc_s13
    mov  x2, #1
    bl   Lfb_label
    ADRL x8, _g_fm_levtxt
    str  x0, [x8]
    ADRL x0, Ls_empty
    ADRL x8, Lf_state
    LDD  d4, Lc_s13
    mov  x2, #0
    bl   Lfb_label
    ADRL x8, _g_fm_state
    str  x0, [x8]
    ADRL x0, Ls_empty
    ADRL x8, Lf_stats
    LDD  d4, Lc_s12
    mov  x2, #0
    bl   Lfb_label
    bl   _dim_label
    ADRL x8, _g_fm_stats
    str  x0, [x8]
    // ---- buttons ----
    ADRL x0, Ls_apply
    ADRL x1, Ls_m_fmApply
    mov  x2, #0
    mov  x3, x21
    ADRL x8, Lf_apply
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    mov  x1, #0xB340                 // amber pill, dark text
    movk x1, #0xFF, lsl #16
    mov  x2, #1
    bl   _pill
    ADRL x0, Ls_test
    ADRL x1, Ls_m_fmTest
    mov  x2, #0
    mov  x3, x21
    ADRL x8, Lf_test
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    LEAVE 32

// local: a label in the window. x0 text, x8 frame, x2 bold, d4 size; x21 = content
Lfb_label:
    stp  x29, x30, [sp, #-16]!
    mov  x29, sp
    mov  x1, #0
    mov  x3, x21
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_label
    ldp  x29, x30, [sp], #16
    ret

// local: an editable text field at frame x8 in x21 -> x0
Lfb_field:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    str  x19, [sp, #16]
    mov  x19, x8
    CLS  Ls_NSTextField
    MSG0 Ls_alloc
    mov  x9, x19
    mov  x19, x0
    str  x9, [sp, #24]
    SELX1 Ls_initWithFrame
    mov  x0, x19
    ldr  x9, [sp, #24]
    ldp  d0, d1, [x9]
    ldp  d2, d3, [x9, #16]
    bl   _objc_msgSend
Lfbf_made:
    mov  x19, x0
    mov  x2, #1                      // rounded bezel
    MSG1 Ls_setBezelStyle
    mov  x0, x21
    mov  x2, x19
    MSG1 Ls_addSubview
    mov  x0, x19
    ldr  x19, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// put the saved settings into the window
_fm_fill:
    ENTER 32
    ADRL x8, _g_fm_txf
    ldr  x0, [x8]
    ADRL x1, _g_fm_txfreq
    bl   Lff_set
    ADRL x8, _g_fm_rxf
    ldr  x0, [x8]
    ADRL x1, _g_fm_rxfreq
    bl   Lff_set
    ADRL x8, _g_fm_samecb
    ldr  x0, [x8]
    ADRL x8, _g_fm_shared
    ldr  x2, [x8]
    MSG1 Ls_setState
    ADRL x8, _g_fm_baud              // 1200 / 2400 / 4800 -> 0 / 1 / 2
    ldr  x9, [x8]
    mov  x2, #1
    cmp  x9, #1200
    csel x2, xzr, x2, eq
    mov  x10, #4800
    cmp  x9, x10
    mov  x10, #2
    csel x2, x10, x2, eq
    ADRL x8, _g_fm_speed
    ldr  x0, [x8]
    MSG1 Ls_selectItemAtIndex
    // sources: the RTL-SDR stick, then every sound input
    bl   _fm_devices
    ADRL x8, _g_fm_popup
    ldr  x19, [x8]
    mov  x0, x19
    MSG0 Ls_removeAllItems
    ADRL x0, Ls_src_rtl
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_addItemWithTitle
    mov  x20, #0
    mov  x21, #0                     // index to select
1:  ADRL x8, _g_fm_ndev
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 3f
    ADRL x8, _g_fm_devname
    ldr  x2, [x8, x20, lsl #3]
    mov  x0, x19
    MSG1 Ls_addItemWithTitle
    ADRL x8, _g_fm_devuid            // the saved choice?
    ldr  x0, [x8, x20, lsl #3]
    MSG0 Ls_UTF8String
    cbz  x0, 2f
    ADRL x1, _g_fm_src
    bl   _strcmp
    cbnz w0, 2f
    add  x21, x20, #1
2:  add  x20, x20, #1
    b    1b
3:  mov  x0, x19
    mov  x2, x21
    MSG1 Ls_selectItemAtIndex
    LEAVE 32

Lff_set:                             // x0 = field, x1 = C string
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    str  x19, [sp, #16]
    mov  x19, x0
    mov  x0, x1
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setStringValue
    ldr  x19, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// - (void)fmApply:(id)sender — save the window's settings and restart the radio
.globl _fm_apply
_fm_apply:
    ENTER 32
    ADRL x8, _g_fm_txf
    ldr  x0, [x8]
    ADRL x1, Lk_tx
    bl   Lfa_save_field
    ADRL x8, _g_fm_rxf
    ldr  x0, [x8]
    ADRL x1, Lk_rx
    bl   Lfa_save_field
    ADRL x8, _g_fm_samecb
    ldr  x0, [x8]
    MSG0 Ls_state
    ADRL x1, Ls_one
    ADRL x9, Ls_zero
    cmp  x0, #0
    csel x1, x9, x1, eq
    ADRL x0, Lk_shared
    bl   _pref_set
    ADRL x8, _g_fm_speed
    ldr  x0, [x8]
    MSG0 Ls_indexOfSelectedItem
    ADRL x1, Ls_b2400v
    cmp  x0, #0
    ADRL x9, Ls_b1200v
    csel x1, x9, x1, eq
    cmp  x0, #2
    ADRL x9, Ls_b4800v
    csel x1, x9, x1, eq
    ADRL x0, Lk_baud
    bl   _pref_set
    ADRL x8, _g_fm_popup
    ldr  x0, [x8]
    MSG0 Ls_indexOfSelectedItem
    ADRL x1, Ls_rtl_key
    cbz  x0, 2f
    sub  x9, x0, #1
    ADRL x8, _g_fm_ndev
    ldr  x10, [x8]
    cmp  x9, x10
    b.hs 2f
    ADRL x8, _g_fm_devuid
    ldr  x0, [x8, x9, lsl #3]
    MSG0 Ls_UTF8String
    mov  x1, x0
    cbnz x1, 2f
    ADRL x1, Ls_rtl_key
2:  ADRL x0, Lk_src
    bl   _pref_set
    bl   _fm_load
    bl   _fm_restart
    ADRL x0, Ls_saved
    bl   _chat_line
    bl   _fm_win_update
    LEAVE 32

Lfa_save_field:                      // x0 = field, x1 = key
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    str  x19, [sp, #16]
    mov  x19, x1
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, 1f
    mov  x1, x0
    mov  x0, x19
    bl   _pref_set
1:  ldr  x19, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// - (void)fmTest:(id)sender — put a hello on the air right now
.globl _fm_test_hello
_fm_test_hello:
    ENTER 0
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbnz x9, 1f
    ADRL x0, Ls_test_off
    bl   _chat_line
    LEAVE 0
1:  ADRL x8, _g_fm_hello_n           // the next hello goes on FM
    str  xzr, [x8]
    bl   _mesh_send_hello
    ADRL x0, Ls_test_sent
    bl   _chat_line
    LEAVE 0

// refresh the live parts of the window
_fm_win_update:
    ENTER 32
    ADRL x8, _g_fm_win
    ldr  x0, [x8]
    cbz  x0, 9f
    MSG0 Ls_isVisible
    cbz  x0, 9f
    // switch follows the service
    mov  x0, #SVC_FM
    bl   _svc_on
    mov  x2, x0
    ADRL x8, _g_fm_switch
    ldr  x0, [x8]
    MSG1 Ls_setState
    // state line
    bl   _fm_state_line
    ADRL x8, _g_fm_state
    ldr  x0, [x8]
    ADRL x1, _g_fm_line
    bl   Lff_set
    // counters, and how the last frame arrived (the signal meter)
    ADRL x8, _g_fm_heardpk
    ldr  x9, [x8]
    str  x9, [sp]
    ADRL x8, _fx_fixed
    ldr  x9, [x8]
    str  x9, [sp, #8]
    ADRL x8, _fx_fail                // (HDLC noise no longer counts as "lost")
    ldr  x9, [x8]
    str  x9, [sp, #16]
    ADRL x8, _g_fm_sent
    ldr  x9, [x8]
    str  x9, [sp, #24]
    ADRL x0, _g_fm_line
    mov  x1, #256
    ADRL x2, Lf_statfmt
    bl   _snprintf
    ADRL x8, _fx_last
    ldr  x9, [x8]
    ADRL x1, Ls_last_none
    cmn  x9, #2
    b.eq 1f
    ADRL x1, Ls_last_lost
    cmn  x9, #1
    b.eq 1f
    ADRL x1, Ls_last_clean
    cbz  x9, 1f
    str  x9, [sp]
    add  x0, sp, #96
    mov  x1, #32
    ADRL x2, Lf_last_fixed
    bl   _snprintf
    add  x1, sp, #96
1:  ADRL x0, _g_fm_line
    mov  x2, #256
    bl   _strlcat
    ADRL x8, _g_fm_stats
    ldr  x0, [x8]
    ADRL x1, _g_fm_line
    bl   Lff_set
    // level: 10*log10(mean square / full scale^2), -60..0 dB
    mov  x19, #-60
    ADRL x8, _g_fm_running
    ldr  x9, [x8]
    cbz  x9, 2f
    ADRL x8, _fm_level_ms
    ldr  x9, [x8]
    cbz  x9, 2f
    ucvtf d0, x9
    LDD  d1, Lc_fs2
    fdiv d0, d0, d1
    bl   _log10
    LDD  d1, Lc_ten
    fmul d0, d0, d1
    fcvtzs x19, d0
    mov  x9, #-60
    cmp  x19, x9
    csel x19, x9, x19, lt
    cmp  x19, #0
    csel x19, xzr, x19, gt
2:  SELX1 Ls_setDoubleValue
    add  x9, x19, #60
    scvtf d0, x9
    LDD  d1, Lc_hund
    fmul d0, d0, d1
    LDD  d1, Lc_sixty
    fdiv d0, d0, d1
    ADRL x8, _g_fm_level
    ldr  x0, [x8]
    bl   _objc_msgSend
    str  x19, [sp]
    ADRL x0, _g_fm_line
    mov  x1, #256
    ADRL x2, Lf_level
    ADRL x8, _g_fm_rxkind
    ldr  x9, [x8]
    cbnz x9, 3f
    ADRL x2, Lf_nolevel
3:  bl   _snprintf
    ADRL x8, _g_fm_levtxt
    ldr  x0, [x8]
    ADRL x1, _g_fm_line
    bl   Lff_set
9:  LEAVE 32

// ===========================================================================
// Self-test: the modem, end to end, on a real signed packet
// ===========================================================================

// "fm repeat on" (arg 1) / "fm repeat off" (arg 0)
.globl _h_fm_repeat
_h_fm_repeat:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_fm_repeat
    str  x19, [x8]
    ADRL x0, Lk_repeat
    ADRL x1, Ls_one_s
    ADRL x9, Ls_zero_s
    cmp  x19, #0
    csel x1, x9, x1, eq
    bl   _pref_set
    ADRL x0, Ls_rep_on
    ADRL x9, Ls_rep_off
    cmp  x19, #0
    csel x0, x9, x0, eq
    bl   _home_say0
    LEAVE 0

// void _t_fx_feed(const uint8 *bytes, long n) — selftest: bits straight to the framer
_t_fx_feed:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
1:  cmp  x21, x20
    b.hs 3f
    ldrb w22, [x19, x21]
    mov  x23, #0
2:  lsr  w0, w22, w23
    and  w0, w0, #1
    bl   _fx_bit
    add  x23, x23, #1
    cmp  x23, #8
    b.lo 2b
    add  x21, x21, #1
    b    1b
3:  LEAVE 0

// long _fm_selftest(void) -> failures
.globl _fm_selftest
_fm_selftest:
    ENTER 16
    mov  x19, #0
    mov  x0, #2400
    bl   _fm_modem_init
    ADRL x8, _g_fm_test
    mov  x9, #1
    str  x9, [x8]
    ADRL x8, _g_fm_test_n
    str  xzr, [x8]
    // a packet header and 188 bytes of body, as it would go on the air
    ADRL x0, _g_fm_tpkt
    mov  w1, #T_HELLO
    bl   _pkt_begin
    ADRL x20, _g_fm_tpkt
    mov  x9, #12
0:  strb w9, [x20, x9]               // a recognisable body
    add  x9, x9, #1
    cmp  x9, #200
    b.lo 0b
    // modulate 200 bytes of the packet buffer, then demodulate the audio
    mov  x0, x20
    mov  w1, #200
    ADRL x2, _fm_modbuf
    bl   _fm_mod
    mov  x21, x0                     // samples
    mov  x22, #0
1:  cmp  x22, x21                    // feed it in blocks, as the radio would
    b.hs 2f
    sub  x1, x21, x22
    mov  x9, #4096
    cmp  x1, x9
    csel x1, x9, x1, hi
    ADRL x0, _fm_modbuf
    add  x0, x0, x22, lsl #1
    add  x22, x22, x1
    bl   _fm_demod
    b    1b
2:  ADRL x8, _g_fm_test_n
    ldr  x9, [x8]
    cmp  x9, #1
    b.ne 3f
    ADRL x0, _g_fm_testbuf
    mov  x1, x20
    mov  x2, #200
    bl   _memcmp
    cmp  x0, #0
3:  cset w1, eq
    ADRL x0, Ln_fm_modem
    bl   _t_report
    add  x19, x19, x0
    // the heard-counter that lets a Mac skip a relay someone else already sent
    MOVI x0, 0x5EED0001
    bl   _fm_heard_add
    MOVI x0, 0x5EED0001
    bl   _fm_heard_add
    MOVI x0, 0x5EED0001
    bl   _fm_heard_count
    cmp  x0, #2
    cset w1, eq
    ADRL x0, Ln_fm_heard
    bl   _t_report
    add  x19, x19, x0
    // Reed–Solomon: 16 damaged bytes in a 232-byte block are all repaired
    ADRL x20, _g_fm_tpkt
    mov  x9, #0
0:  mov  w10, #37
    mul  w10, w9, w10
    add  w10, w10, #11
    strb w10, [x20, x9]
    add  x9, x9, #1
    cmp  x9, #200
    b.lo 0b
    ADRL x0, _g_fm_fecbuf
    mov  x1, x20
    mov  x2, #200
    bl   _memcpy
    ADRL x0, _g_fm_fecbuf
    mov  x1, #200
    ADRL x2, _g_fm_fecbuf
    add  x2, x2, #200
    bl   _rs_encode
    ADRL x8, _g_fm_fecbuf            // damage 16 bytes, data and check bytes alike
    mov  x9, #3
1:  ldrb w10, [x8, x9]
    mov  w11, #0x5A
    eor  w10, w10, w11
    strb w10, [x8, x9]
    add  x9, x9, #14
    cmp  x9, #(3 + 14 * 16)
    b.lo 1b
    ADRL x0, _g_fm_fecbuf
    mov  x1, #232
    bl   _rs_decode
    mov  x21, x0
    ADRL x0, _g_fm_fecbuf
    mov  x1, x20
    mov  x2, #200
    bl   _memcmp
    cmp  w0, #0
    ccmp x21, #16, #0, eq
    cset w1, eq
    ADRL x0, Ln_fm_rs
    bl   _t_report
    add  x19, x19, x0
    // a whole frame through crackle: wrong tag bits, one bad length copy, 12 bad bytes
    bl   _fx_reset
    ADRL x8, _g_fm_test_n
    str  xzr, [x8]
    mov  x0, x20
    mov  x1, #200
    ADRL x2, _g_fm_fecbuf
    bl   _fx_build
    mov  x21, x0                     // bytes
    ADRL x8, _g_fm_fecbuf
    ldrb w9, [x8, #1]                // three tag bits
    mov  w11, #0x15
    eor  w9, w9, w11
    strb w9, [x8, #1]
    mov  w9, #0xFF                   // one of the three length bytes
    strb w9, [x8, #9]
    mov  x9, #20                     // twelve body bytes, spread through the block
2:  ldrb w10, [x8, x9]
    mov  w11, #0xA5
    eor  w10, w10, w11
    strb w10, [x8, x9]
    add  x9, x9, #19
    cmp  x9, #(20 + 19 * 12)
    b.lo 2b
    ADRL x0, Ls_fx_flags
    mov  x1, #8
    bl   _t_fx_feed
    ADRL x0, _g_fm_fecbuf
    mov  x1, x21
    bl   _t_fx_feed
    ADRL x0, Ls_fx_flags
    mov  x1, #4
    bl   _t_fx_feed
    ADRL x8, _g_fm_test_n
    ldr  x22, [x8]
    ADRL x0, _g_fm_testbuf
    mov  x1, x20
    mov  x2, #200
    bl   _memcmp
    cmp  w0, #0
    ccmp x22, #1, #0, eq
    cset w1, eq
    ADRL x0, Ln_fm_fec
    bl   _t_report
    add  x19, x19, x0
    // the same frame again straight away (the repeat copy): not passed on twice
    ADRL x0, _g_fm_fecbuf
    mov  x1, x21
    bl   _t_fx_feed
    ADRL x0, Ls_fx_flags
    mov  x1, #4
    bl   _t_fx_feed
    ADRL x8, _g_fm_test_n
    ldr  x9, [x8]
    cmp  x9, #1
    cset w1, eq
    ADRL x0, Ln_fm_dup
    bl   _t_report
    add  x19, x19, x0
    ADRL x8, _g_fm_test
    str  xzr, [x8]
    mov  x0, x19
    LEAVE 16

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lk_rx:          .asciz "fm_listen"
Lk_tx:          .asciz "fm_send"
Lk_src:         .asciz "fm_source"
Lk_shared:      .asciz "fm_shared"
Lk_baud:        .asciz "fm_baud"
Ls_def_freq:    .asciz "88.1"
Ls_rtl_key:     .asciz "rtl"
Ls_one:         .asciz "1"
Ls_zero:        .asciz "0"
Ls_b1200v:      .asciz "1200"
Ls_b2400v:      .asciz "2400"
Ls_b4800v:      .asciz "4800"
Ls_PATH:        .asciz "PATH"
Ls_pathval:     .asciz "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
Ls_empty:       .asciz ""
Ls_no_out:      .asciz "FM: no sound output found for the transmitter."
Ls_no_in:       .asciz "FM: couldn't open that sound input. Check Microphone access in System Settings \342\200\272 Privacy & Security, or pick another input in FM Radio."
Ls_no_rtl:      .asciz "FM: rtl_fm isn't installed, so the RTL-SDR stick can't listen. In Terminal: brew install librtlsdr \342\200\224 or pick a sound input in Mesh \342\200\272 FM Radio."
Ls_bad_freq:    .asciz "FM: the Listen on frequency should be in MHz, like 88.1."
Ls_fm_off:      .asciz "FM radio off."
Ls_saved:       .asciz "FM settings saved."
Ls_test_off:    .asciz "FM: switch FM radio on first (Mesh \342\200\272 FM Radio)."
Ls_test_sent:   .asciz "FM: a hello is going out on the air now."
Ls_state_off:   .asciz "FM radio is off."
Lf_state_rtl:   .asciz "FM radio on \302\267 sending on %s MHz \302\267 listening on %s MHz with the RTL-SDR \302\267 %ld baud \302\267 %s"
Lf_state_in:    .asciz "FM radio on \302\267 sending on %s MHz \302\267 listening through the sound input (radio on %s MHz) \302\267 %ld baud \302\267 %s"
Lf_state_none:  .asciz "FM radio on \302\267 sending on %s MHz \302\267 not listening (would be %s MHz) \302\267 %ld baud \302\267 %s"
Ls_plan_shared: .asciz "shared channel"
Ls_plan_sep:    .asciz "separate channels"
Lf_statfmt:     .asciz "Heard %ld \302\267 %ld repaired \302\267 %ld lost \302\267 sent %ld \302\267 last: "
Ls_last_none:   .asciz "\342\200\224"
Ls_last_lost:   .asciz "lost"
Ls_last_clean:  .asciz "clean"
Lf_fm_heard_hello: .asciz "\302\267 \360\237\223\273 Heard %s over FM (%s) \342\200\224 the radio link works."
Lf_fm_pended:   .asciz "\302\267 \360\237\223\273 A message came in over FM (%s) from a Mac whose hello hasn\342\200\231t come through yet. It will show as soon as that Mac\342\200\231s hello is heard (it sends one with its next message)."
Lf_last_fixed:  .asciz "%ld bytes repaired"
Lk_repeat:      .asciz "fm_repeat"
Ls_rep_on:      .asciz "\302\267 \360\237\223\273 FM sends every message twice now \342\200\224 steadier through crackle and fading, about twice the airtime. \342\200\234fm repeat off\342\200\235 to send once."
Ls_rep_off:     .asciz "\302\267 \360\237\223\273 FM sends every message once now. \342\200\234fm repeat on\342\200\235 to send twice."
Lf_level:       .asciz "%ld dB"
Lf_nolevel:     .asciz "not listening"
Ls_src_rtl:     .asciz "RTL-SDR stick (tunes itself)"
Ls_win_title:   .asciz "FM Radio"
Ls_win_sub:     .asciz "Carry the mesh over FM. Without a licence keep it very low power (FCC Part 15)."
Ls_on_title:    .asciz "Send and receive over FM"
Ls_tx_label:    .asciz "Transmitter on"
Ls_tx_note:     .asciz "MHz \302\267 headphone jack \302\267 lowest power"
Ls_rx_title:    .asciz "Receiving"
Ls_src_label:   .asciz "Listen with"
Ls_rx_label:    .asciz "Listen on"
Ls_sp_label:    .asciz "Speed"
Ls_b1200:       .asciz "1200 baud"
Ls_b2400:       .asciz "2400 baud"
Ls_b4800:       .asciz "4800 baud"
Ls_same_title:  .asciz "Send and listen on the same frequency (shared channel, waits its turn)"
Ls_st_title:    .asciz "On the air"
Ls_apply:       .asciz "Save and restart the radio"
Ls_test:        .asciz "Send a test hello"
Ln_fm_modem:    .asciz "a signed packet goes through the FM modem and comes back intact"
Ln_fm_heard:    .asciz "FM remembers how often a packet was heard on the air"
Ln_fm_rs:       .asciz "FM: Reed-Solomon repairs 16 damaged bytes in a block"
Ln_fm_fec:      .asciz "FM: a frame with bad tag bits, a bad length copy and 12 bad bytes still arrives"
Ln_fm_dup:      .asciz "FM: the repeat copy of a frame is not passed on twice"
Ls_fx_flags:    .asciz "~~~~~~~~"
Ls_one_s:       .asciz "1"
Ls_zero_s:      .asciz "0"
Ls_m_svcToggled: .asciz "serviceToggled:"
Ls_m_fmApply:   .asciz "fmApply:"
Ls_m_fmTest:    .asciz "fmTest:"
// selectors
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_NSApplication: .asciz "NSApplication"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_NSWindow:    .asciz "NSWindow"
Ls_alloc:       .asciz "alloc"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_setTitle:    .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_setTitlebarAppearsTransparent: .asciz "setTitlebarAppearsTransparent:"
Ls_setTitleVisibility: .asciz "setTitleVisibility:"
Ls_setBackgroundColor: .asciz "setBackgroundColor:"
Ls_center:      .asciz "center"
Ls_contentView: .asciz "contentView"
Ls_NSSwitch:    .asciz "NSSwitch"
Ls_initWithFrame: .asciz "initWithFrame:"
Ls_setTag:      .asciz "setTag:"
Ls_setTarget:   .asciz "setTarget:"
Ls_setAction:   .asciz "setAction:"
Ls_addSubview:  .asciz "addSubview:"
Ls_setLineBreakMode: .asciz "setLineBreakMode:"
Ls_NSPopUpButton: .asciz "NSPopUpButton"
Ls_initWithFrame_pullsDown: .asciz "initWithFrame:pullsDown:"
Ls_addItemWithTitle: .asciz "addItemWithTitle:"
Ls_NSButton:    .asciz "NSButton"
Ls_checkboxWithTitle: .asciz "checkboxWithTitle:target:action:"
Ls_setFrame:    .asciz "setFrame:"
Ls_NSLevelIndicator: .asciz "NSLevelIndicator"
Ls_setLevelIndicatorStyle: .asciz "setLevelIndicatorStyle:"
Ls_setMaxValue: .asciz "setMaxValue:"
Ls_NSTextField: .asciz "NSTextField"
Ls_setBezelStyle: .asciz "setBezelStyle:"
Ls_setStringValue: .asciz "setStringValue:"
Ls_setState:    .asciz "setState:"
Ls_state:       .asciz "state"
Ls_selectItemAtIndex: .asciz "selectItemAtIndex:"
Ls_indexOfSelectedItem: .asciz "indexOfSelectedItem"
Ls_removeAllItems: .asciz "removeAllItems"
Ls_UTF8String:  .asciz "UTF8String"
Ls_stringValue: .asciz "stringValue"
Ls_isVisible:   .asciz "isVisible"
Ls_setDoubleValue: .asciz "setDoubleValue:"
