// term_hist.s — what's typed, remembered, and Home's commands suggested as you type: the
// parts the Mac (term.s) and the iPhone (ios_ui.s's am_hist_* and am_sg_*) share. No views
// here; term_core.s does the bytes.
//
// What's typed is remembered while asmmesh runs. Across launches only if "history on" (the
// default), and never lines typed in private rooms or the bitchat room, nor ones that look
// like they carry a secret (a token, key, topic, password or passphrase). "history off"
// forgets what was saved, "history clear" everything.

.include "macros.inc"

.set SG_MAX,    6               // suggestions at once
.set WORDS_MAX, 256
.set PACK_MAX,  28000

.data
.p2align 3
.globl _g_term_hist, _g_term_out, _g_term_buf
_g_term_hist:   .quad 0         // term_core.s history (0 until _term_init)
_g_term_on:     .quad 1         // keep across launches
_g_term_nw:     .quad 0         // words known
.zerofill __DATA,__bss,_g_term_words,(WORDS_MAX * 16 + 16),4
.zerofill __DATA,__bss,_g_term_out,(SG_MAX * 16 + 16),4
.zerofill __DATA,__bss,_g_term_buf,PACK_MAX,4

.section __DATA,__const
.p2align 3
// Home words that aren't in rules.s's table (home.s and others read them)
Lterm_extra:
    .quad Lw_help, 0
    .quad Lw_devices, 0
    .quad Lw_pairhue, 0
    .quad Lw_goodnight, 0
    .quad Lw_hist, 0
    .quad Lw_hist_on, 0
    .quad Lw_hist_off, 0
    .quad Lw_hist_clear, 0
    .quad 0, 0
Lterm_secrets:
    .quad Ls_s_token, Ls_s_key, Ls_s_topic, Ls_s_pass, 0

.text
.p2align 2

// void _term_init(void) — once, at launch: the history, the words, what was saved
.globl _term_init
_term_init:
    ENTER 0
    ADRL x8, _g_term_hist
    ldr  x9, [x8]
    cbnz x9, 9f
    bl   _th_size
    mov  x1, x0
    mov  x0, #1
    bl   _calloc
    cbz  x0, 9f
    ADRL x8, _g_term_hist
    str  x0, [x8]
    bl   _th_reset
    ADRL x0, _g_term_words                // the words to suggest: rules.s's, then ours
    mov  x1, #WORDS_MAX
    bl   _rules_words
    mov  x22, x0
    ADRL x9, Lterm_extra
    ADRL x10, _g_term_words
1:  ldp  x11, x12, [x9], #16
    cbz  x11, 2f
    cmp  x22, #WORDS_MAX
    b.hs 2f
    add  x13, x10, x22, lsl #4
    stp  x11, x12, [x13]
    add  x22, x22, #1
    b    1b
2:  add  x13, x10, x22, lsl #4
    stp  xzr, xzr, [x13]
    ADRL x8, _g_term_nw
    str  x22, [x8]
    ADRL x0, Ls_k_on                      // what was saved last time, if keeping it
    ADRL x1, _g_term_buf
    mov  x2, #8
    bl   _pref_get
    ADRL x8, _g_term_buf
    ldrb w9, [x8]
    cmp  w9, #'0'
    cset x9, ne
    ADRL x8, _g_term_on
    str  x9, [x8]
    cbz  x9, 9f
    ADRL x0, Ls_k_lines
    ADRL x1, _g_term_buf
    mov  x2, #PACK_MAX
    bl   _pref_get
    ADRL x8, _g_term_hist
    ldr  x0, [x8]
    ADRL x1, _g_term_buf
    bl   _th_unpack
9:  LEAVE 0

// long _term_match(const char *text) -> how many of Home's commands match what's typed
//   (into _g_term_out: word, kind pairs), 0 unless Home is showing and something's typed
.globl _term_match
_term_match:
    ENTER 0
    mov  x19, x0
    cbz  x19, 8f
    ldrb w9, [x19]
    cbz  w9, 8f
    ADRL x8, _g_term_hist                 // not set up yet
    ldr  x9, [x8]
    cbz  x9, 8f
    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    ADRL x8, _g_rooms
    add  x8, x8, x9, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    cmp  x9, #HOME_ID
    b.ne 8f
    ADRL x0, _g_term_words
    mov  x1, x19
    ADRL x2, _g_term_out
    mov  x3, #SG_MAX
    bl   _sg_match
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// long Lterm_secret(const char *text) -> 1 if it looks like it carries a secret
Lterm_secret:
    ENTER 0
    mov  x19, x0
    ADRL x20, Lterm_secrets
1:  ldr  x1, [x20], #8
    cbz  x1, 2f
    mov  x0, x19
    bl   _strcasestr
    cbz  x0, 1b
    mov  x0, #1
    LEAVE 0
2:  mov  x0, #0
    LEAVE 0

// void _term_record(const char *text) — a line sent in the current room: remembered, and
//   saved if it may be (not from a private or the bitchat room, nothing that looks secret)
.globl _term_record
_term_record:
    ENTER 0
    mov  x19, x0
    cbz  x19, 9f
    ADRL x8, _g_term_hist
    ldr  x20, [x8]
    cbz  x20, 9f
    ADRL x8, _g_cur_room                  // Main, Home, Web, News: may be kept
    ldr  x9, [x8]
    ADRL x8, _g_rooms
    add  x8, x8, x9, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    cmp  x9, #NEWS_ID
    cset x21, ls
    cbz  x21, 1f
    mov  x0, x19
    bl   Lterm_secret
    cmp  x0, #0
    cset x21, eq
1:  mov  x0, x20
    mov  x1, x19
    mov  x2, x21
    bl   _th_add
    bl   Lterm_save
9:  LEAVE 0

// void Lterm_save(void) — the lines that may be kept, into the defaults, if keeping
Lterm_save:
    ENTER 0
    ADRL x8, _g_term_on
    ldr  x9, [x8]
    cbz  x9, 9f
    ADRL x8, _g_term_hist
    ldr  x0, [x8]
    cbz  x0, 9f
    ADRL x1, _g_term_buf
    mov  x2, #PACK_MAX
    bl   _th_pack
    ADRL x0, Ls_k_lines
    ADRL x1, _g_term_buf
    bl   _pref_set
9:  LEAVE 0

// "history" (3) / "history on" (1) / "history off" (0) / "history clear" (2) — Home
.globl _h_term_history
_h_term_history:
    ENTER 0
    mov  x19, x0
    cmp  x19, #3
    b.eq 5f
    cmp  x19, #2
    b.eq 3f
    ADRL x8, _g_term_on                   // on / off
    str  x19, [x8]
    ADRL x0, Ls_k_on
    ADRL x1, Ls_one
    ADRL x9, Ls_zero
    cmp  x19, #0
    csel x1, x9, x1, eq
    bl   _pref_set
    cbnz x19, 1f
    ADRL x0, Ls_k_lines                   // off: nothing stays saved
    ADRL x1, Ls_empty
    bl   _pref_set
    ADRL x0, Ls_hist_off
    bl   _home_say0
    LEAVE 0
1:  bl   Lterm_save
    ADRL x0, Ls_hist_on
    bl   _home_say0
    LEAVE 0
3:  ADRL x8, _g_term_hist                 // clear: here and saved
    ldr  x0, [x8]
    cbz  x0, 4f
    bl   _th_size
    mov  x1, x0
    ADRL x8, _g_term_hist
    ldr  x0, [x8]
    bl   _bzero
    ADRL x8, _g_term_hist
    ldr  x0, [x8]
    bl   _th_reset
4:  ADRL x0, Ls_k_lines
    ADRL x1, Ls_empty
    bl   _pref_set
    ADRL x0, Ls_hist_cleared
    bl   _home_say0
    LEAVE 0
5:  ADRL x8, _g_term_on                   // just "history": how it is
    ldr  x9, [x8]
    ADRL x0, Ls_hist_is_off
    ADRL x10, Ls_hist_is_on
    cmp  x9, #0
    csel x0, x10, x0, ne
    bl   _home_say0
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_empty:       .asciz ""
Ls_one:         .asciz "1"
Ls_zero:        .asciz "0"
Ls_k_on:        .asciz "termHistory"
Ls_k_lines:     .asciz "termHistoryLines"
Ls_s_token:     .asciz "token"
Ls_s_key:       .asciz "key"
Ls_s_topic:     .asciz "topic"
Ls_s_pass:      .asciz "pass"
Lw_help:        .asciz "help"
Lw_devices:     .asciz "devices"
Lw_pairhue:     .asciz "pair hue"
Lw_goodnight:   .asciz "good night"
Lw_hist:        .asciz "history"
Lw_hist_on:     .asciz "history on"
Lw_hist_off:    .asciz "history off"
Lw_hist_clear:  .asciz "history clear"
Ls_hist_on:     .asciz "\302\267 History is on: what you type is remembered between launches (not private or bitchat rooms, nor anything with a token, key, topic or password). Up and down bring it back."
Ls_hist_off:    .asciz "\302\267 History is off: what you type is only remembered until asmmesh quits, and what was saved is gone."
Ls_hist_cleared: .asciz "\302\267 History cleared."
Ls_hist_is_on:  .asciz "\302\267 History is on (\342\200\234history off\342\200\235 to stop, \342\200\234history clear\342\200\235 to forget). Up and down bring back what you typed."
Ls_hist_is_off: .asciz "\302\267 History is off: remembered until asmmesh quits (\342\200\234history on\342\200\235 to keep it)."
