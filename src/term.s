// term.s — the Mac's input field as a terminal: a monospaced line with a ❯ prompt, ↑ and ↓
// to bring back what was typed, and in Home a list of commands that match what's being
// typed (Tab completes, ↑ ↓ choose, Esc hides), like Claude Code's. What's shared with the
// iPhone is term_hist.s; the bytes-only parts are term_core.s.
//
// What's typed is remembered while asmmesh runs. Across launches only if "history on" (the
// default), and never lines typed in private rooms or the bitchat room, nor ones that look
// like they carry a secret (a token, key, topic, password or passphrase). "history off"
// forgets what was saved, "history clear" everything.

.include "macros.inc"

.set SG_MAX,    6               // suggestions shown at once
.set PACK_MAX,  28000

.data
.p2align 3
_g_term_sg:     .quad 0         // the suggestions label
_g_term_n:      .quad 0         // suggestions showing (0: hidden)
_g_term_sel:    .quad 0         // the one chosen
_g_sel_up:      .quad 0
_g_sel_down:    .quad 0
_g_sel_tab:     .quad 0
_g_sel_esc:     .quad 0

.text
.p2align 2

// void _term_setup(id field, id box, id content) — main.s, once the field is in its card
.globl _term_setup
_term_setup:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    bl   _term_init                       // the history and the words (term_hist.s)
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
    LEAVE 16

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
    bl   Lterm_text
    bl   _term_match
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

// void _term_sent(const char *text) — ui.s, as a line is sent: suggestions away, the
//   line remembered (term_hist.s)
.globl _term_sent
_term_sent:
    ENTER 0
    mov  x19, x0
    bl   _term_hide
    mov  x0, x19
    bl   _term_record
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lc_13:      .double 13.0
Lc_12:      .double 12.0
Lf_tfield:  .double 30.0, 9.0, 412.0, 19.0       // in the field's card, after the prompt
Lf_prompt:  .double 12.0, 9.0, 16.0, 19.0
Lf_sg:      .double 262.0, 52.0, 456.0, 0.0      // just above the field's card (y 12-48)

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
Ls_keys:        .asciz "Tab completes \302\267 \342\206\221\342\206\223 choose \302\267 Esc hides"
