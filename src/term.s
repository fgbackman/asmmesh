// term.s — the Mac's input field as a terminal: a monospaced line with a ❯ prompt, ↑ and ↓
// to bring back what was typed, and in Home a list of commands that match what's being
// typed (Tab completes, ↑ ↓ choose, Esc hides), like Claude Code's. The bytes-only parts are
// term_core.s.
//
// What's typed is remembered while asmmesh runs. Across launches only if "history on" (the
// default), and never lines typed in private rooms or the bitchat room, nor ones that look
// like they carry a secret (a token, key, topic, password or passphrase). "history off"
// forgets what was saved, "history clear" everything.

.include "macros.inc"

.set SG_MAX,    6               // suggestions shown at once
.set WORDS_MAX, 256
.set PACK_MAX,  28000

.data
.p2align 3
_g_term_hist:   .quad 0         // term_core.s history
_g_term_on:     .quad 1         // keep across launches
_g_term_sg:     .quad 0         // the suggestions label
_g_term_n:      .quad 0         // suggestions showing (0: hidden)
_g_term_sel:    .quad 0         // the one chosen
_g_term_nw:     .quad 0         // words known
_g_sel_up:      .quad 0
_g_sel_down:    .quad 0
_g_sel_tab:     .quad 0
_g_sel_esc:     .quad 0
.zerofill __DATA,__bss,_g_term_words,(WORDS_MAX * 16 + 16),4
.zerofill __DATA,__bss,_g_term_out,(SG_MAX * 16),4
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

.text
.p2align 2

// void _term_setup(id field, id box, id content) — main.s, once the field is in its card
.globl _term_setup
_term_setup:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    bl   _th_size                         // the history
    mov  x1, x0
    mov  x0, #1
    bl   _calloc
    ADRL x8, _g_term_hist
    str  x0, [x8]
    bl   _th_reset
    ADRL x0, Ls_sel_up                    // the keys we take over
    bl   _sel_registerName
    ADRL x8, _g_sel_up
    str  x0, [x8]
    ADRL x0, Ls_sel_down
    bl   _sel_registerName
    ADRL x8, _g_sel_down
    str  x0, [x8]
    ADRL x0, Ls_sel_tab
    bl   _sel_registerName
    ADRL x8, _g_sel_tab
    str  x0, [x8]
    ADRL x0, Ls_sel_esc
    bl   _sel_registerName
    ADRL x8, _g_sel_esc
    str  x0, [x8]
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
    // a monospaced field, with a prompt
    CLS  Ls_NSFont
    mov  x22, x0
    SELX1 Ls_monoFont
    mov  x0, x22
    LDD  d0, Lc_13
    fmov d1, xzr
    bl   _objc_msgSend
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setFont
    SELX1 Ls_setFrame                     // room on the left for the prompt
    mov  x0, x19
    ADRL x8, Lf_tfield
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    ADRL x0, Ls_prompt
    mov  x1, #0
    mov  x2, #1
    mov  x3, x20
    ADRL x8, Lf_prompt
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_13
    bl   _mk_label
    mov  x0, x19                          // the field tells us about keys and typing
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    MSG1 Ls_setDelegate
    // the suggestions: a dark card of lines just above the field, hidden for now
    ADRL x0, Ls_empty
    mov  x1, #34                          // WidthSizable | MaxYMargin, like the field's card
    mov  x2, #0
    mov  x3, x21
    ADRL x8, Lf_sg
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_12
    bl   _mk_label
    mov  x22, x0
    ADRL x8, _g_term_sg
    str  x22, [x8]
    CLS  Ls_NSFont
    mov  x23, x0
    SELX1 Ls_monoFont
    mov  x0, x23
    LDD  d0, Lc_12
    fmov d1, xzr
    bl   _objc_msgSend
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setFont
    mov  x0, x22
    mov  x2, #0                           // NSLineBreakByWordWrapping: one line each
    MSG1 Ls_setLineBreakMode
    mov  x0, x22
    mov  x2, #1
    MSG1 Ls_setDrawsBackground
    mov  x0, #0x2c2e
    movk x0, #0x2c, lsl #16
    bl   _rgb
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setBackgroundColor
    mov  x0, x22
    mov  x2, #1
    MSG1 Ls_setHidden
    // what was saved last time, if keeping it
    ADRL x0, Ls_k_on
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
9:  LEAVE 16

// long Lterm_text(void) -> the field's text (UTF-8), never 0
Lterm_text:
    ENTER 0
    ADRL x8, _g_field
    ldr  x0, [x8]
    cbz  x0, 1f
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbnz x0, 2f
1:  ADRL x0, Ls_empty
2:  LEAVE 0

// void Lterm_set(const char *text) — the field shows text, the cursor at its end
Lterm_set:
    ENTER 0
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_field
    ldr  x19, [x8]
    cbz  x19, 1f
    mov  x0, x19
    MSG1 Ls_setStringValue
    mov  x0, x19
    MSG0 Ls_currentEditor
    cbz  x0, 1f
    mov  x2, #0
    MSG1 Ls_moveToEnd
1:  LEAVE 0

// void _term_hide(void) — no suggestions showing (ui.s, on a change of room too)
.globl _term_hide
_term_hide:
    ENTER 0
    ADRL x8, _g_term_n
    str  xzr, [x8]
    ADRL x8, _g_term_sg
    ldr  x0, [x8]
    cbz  x0, 1f
    mov  x2, #1
    MSG1 Ls_setHidden
1:  LEAVE 0

// void Lterm_suggest(void) — Home's commands that match what's typed, if in Home
Lterm_suggest:
    ENTER 0
    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    ADRL x8, _g_rooms
    add  x8, x8, x9, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    cmp  x9, #HOME_ID
    b.ne 8f
    bl   Lterm_text
    ldrb w9, [x0]
    cbz  w9, 8f
    mov  x1, x0
    ADRL x0, _g_term_words
    ADRL x2, _g_term_out
    mov  x3, #SG_MAX
    bl   _sg_match
    cbz  x0, 8f
    ADRL x8, _g_term_n
    str  x0, [x8]
    ADRL x8, _g_term_sel
    str  xzr, [x8]
    bl   Lterm_render
    LEAVE 0
8:  bl   _term_hide
    LEAVE 0

// void Lterm_render(void) — the suggestions, the chosen one marked, and how to use them
Lterm_render:
    ENTER 0
    ADRL x19, _g_term_buf
    strb wzr, [x19]
    mov  x20, #0
    ADRL x8, _g_term_n
    ldr  x21, [x8]
1:  cmp  x20, x21
    b.hs 2f
    ADRL x8, _g_term_sel
    ldr  x9, [x8]
    ADRL x1, Ls_mark
    ADRL x10, Ls_nomark
    cmp  x9, x20
    csel x1, x1, x10, eq
    mov  x0, x19
    mov  x2, #PACK_MAX
    bl   _strlcat
    ADRL x8, _g_term_out
    add  x9, x8, x20, lsl #4
    ldr  x1, [x9]
    mov  x0, x19
    mov  x2, #PACK_MAX
    bl   _strlcat
    mov  x0, x19
    ADRL x1, Ls_nl
    mov  x2, #PACK_MAX
    bl   _strlcat
    add  x20, x20, #1
    b    1b
2:  mov  x0, x19
    ADRL x1, Ls_keys
    mov  x2, #PACK_MAX
    bl   _strlcat
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_term_sg
    ldr  x22, [x8]
    cbz  x22, 9f
    mov  x0, x22
    MSG1 Ls_setStringValue
    SELX1 Ls_setFrame                     // as tall as its lines, just above the field
    mov  x0, x22
    ADRL x8, Lf_sg
    ldp  d0, d1, [x8]
    ldr  d2, [x8, #16]
    add  x9, x21, #1
    mov  x10, #16
    mul  x9, x9, x10
    add  x9, x9, #6
    ucvtf d3, x9
    bl   _objc_msgSend
    mov  x0, x22
    mov  x2, #0
    MSG1 Ls_setHidden
9:  LEAVE 0

// BOOL control:textView:doCommandBySelector: — ↑ ↓ Tab Esc in the field (the controller
//   is its delegate). YES: done here; NO: the field's own way.
.globl _term_cmd
_term_cmd:
    ENTER 0
    mov  x19, x4
    ADRL x8, _g_term_n
    ldr  x20, [x8]                        // suggestions showing
    ADRL x8, _g_sel_up
    ldr  x9, [x8]
    cmp  x19, x9
    b.eq Ltc_up
    ADRL x8, _g_sel_down
    ldr  x9, [x8]
    cmp  x19, x9
    b.eq Ltc_down
    ADRL x8, _g_sel_tab
    ldr  x9, [x8]
    cmp  x19, x9
    b.eq Ltc_tab
    ADRL x8, _g_sel_esc
    ldr  x9, [x8]
    cmp  x19, x9
    b.eq Ltc_esc
Ltc_no:
    mov  x0, #0
    LEAVE 0
Ltc_up:
    cbz  x20, 1f                          // choosing a suggestion
    ADRL x8, _g_term_sel
    ldr  x9, [x8]
    add  x9, x9, x20
    sub  x9, x9, #1
    udiv x10, x9, x20
    msub x9, x10, x20, x9
    str  x9, [x8]
    bl   Lterm_render
    b    Ltc_yes
1:  bl   Lterm_text                       // or back through the history
    mov  x1, x0
    ADRL x8, _g_term_hist
    ldr  x0, [x8]
    cbz  x0, Ltc_yes
    bl   _th_prev
    cbz  x0, Ltc_yes
    bl   Lterm_set
    b    Ltc_yes
Ltc_down:
    cbz  x20, 1f
    ADRL x8, _g_term_sel
    ldr  x9, [x8]
    add  x9, x9, #1
    udiv x10, x9, x20
    msub x9, x10, x20, x9
    str  x9, [x8]
    bl   Lterm_render
    b    Ltc_yes
1:  ADRL x8, _g_term_hist
    ldr  x0, [x8]
    cbz  x0, Ltc_yes
    bl   _th_next
    cbz  x0, Ltc_yes
    bl   Lterm_set
    b    Ltc_yes
Ltc_tab:
    cbz  x20, Ltc_no                      // nothing to complete: Tab as usual
    ADRL x8, _g_term_sel
    ldr  x9, [x8]
    ADRL x8, _g_term_out
    add  x8, x8, x9, lsl #4
    ldp  x1, x9, [x8]                     // the word, and its kind
    ADRL x19, _g_term_buf
    mov  x0, x19
    mov  x2, #PACK_MAX
    str  x9, [sp, #-16]!
    bl   _strlcpy
    ldr  x9, [sp], #16
    tbz  x9, #0, 2f                       // first words of more: a space for the rest
    mov  x0, x19
    ADRL x1, Ls_space
    mov  x2, #PACK_MAX
    bl   _strlcat
2:  mov  x0, x19
    bl   Lterm_set
    bl   Lterm_suggest
    b    Ltc_yes
Ltc_esc:
    cbz  x20, Ltc_no
    bl   _term_hide
Ltc_yes:
    mov  x0, #1
    LEAVE 0

// - (void)controlTextDidChange:(NSNotification *)n — typing: the suggestions follow
.globl _term_changed
_term_changed:
    ENTER 0
    bl   Lterm_suggest
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

// void _term_sent(const char *text) — ui.s, as a line is sent: remembered, and saved if
//   it may be (not from a private or the bitchat room, nothing that looks secret)
.globl _term_sent
_term_sent:
    ENTER 0
    mov  x19, x0
    bl   _term_hide
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

// "history" / "history on" (1) / "history off" (0) / "history clear" (2) — Home
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
.section __TEXT,__const
.p2align 3
Lc_13:      .double 13.0
Lc_12:      .double 12.0
Lf_tfield:  .double 30.0, 9.0, 412.0, 19.0       // in the field's card, after the prompt
Lf_prompt:  .double 12.0, 9.0, 16.0, 19.0
Lf_sg:      .double 262.0, 52.0, 456.0, 0.0      // just above the field's card (y 12-48)

.section __DATA,__const
.p2align 3
Lterm_secrets:
    .quad Ls_s_token, Ls_s_key, Ls_s_topic, Ls_s_pass, 0

.section __TEXT,__cstring,cstring_literals
Ls_sel_up:      .asciz "moveUp:"
Ls_sel_down:    .asciz "moveDown:"
Ls_sel_tab:     .asciz "insertTab:"
Ls_sel_esc:     .asciz "cancelOperation:"
Ls_NSFont:      .asciz "NSFont"
Ls_monoFont:    .asciz "monospacedSystemFontOfSize:weight:"
Ls_setFont:     .asciz "setFont:"
Ls_setFrame:    .asciz "setFrame:"
Ls_setDelegate: .asciz "setDelegate:"
Ls_setLineBreakMode: .asciz "setLineBreakMode:"
Ls_setDrawsBackground: .asciz "setDrawsBackground:"
Ls_setBackgroundColor: .asciz "setBackgroundColor:"
Ls_setHidden:   .asciz "setHidden:"
Ls_stringValue: .asciz "stringValue"
Ls_UTF8String:  .asciz "UTF8String"
Ls_setStringValue: .asciz "setStringValue:"
Ls_currentEditor: .asciz "currentEditor"
Ls_moveToEnd:   .asciz "moveToEndOfDocument:"
Ls_prompt:      .asciz "\342\235\257"
Ls_mark:        .asciz "\342\235\257 "
Ls_nomark:      .asciz "  "
Ls_nl:          .asciz "\n"
Ls_space:       .asciz " "
Ls_empty:       .asciz ""
Ls_one:         .asciz "1"
Ls_zero:        .asciz "0"
Ls_keys:        .asciz "Tab completes \302\267 \342\206\221\342\206\223 choose \302\267 Esc hides"
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
Ls_hist_on:     .asciz "\302\267 History is on: what you type is remembered between launches (not private or bitchat rooms, nor anything with a token, key, topic or password). \342\206\221 and \342\206\223 bring it back."
Ls_hist_off:    .asciz "\302\267 History is off: what you type is only remembered until asmmesh quits, and what was saved is gone."
Ls_hist_cleared: .asciz "\302\267 History cleared."
Ls_hist_is_on:  .asciz "\302\267 History is on (\342\200\234history off\342\200\235 to stop, \342\200\234history clear\342\200\235 to forget). \342\206\221 and \342\206\223 bring back what you typed."
Ls_hist_is_off: .asciz "\302\267 History is off: remembered until asmmesh quits (\342\200\234history on\342\200\235 to keep it)."
