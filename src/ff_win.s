// ff_win.s — Fivefold's window on the Mac: six rows of five tiles (amber the right letter in
// the right place, blue in the word somewhere else, dark not in it), a keyboard that shows
// what's known of each letter, a box to type in, Share, Race… and Duel…. ff_mesh.s brings it
// up (_ff_ui_pop) and asks for a redraw (_ff_ui_show). Typing in a race's or duel's room
// works as well.
.include "macros.inc"
.include "ff_defs.inc"

.set FW_TILE,   56

.data
.p2align 3
_g_ffw:         .quad 0                   // the window
_g_ffw_status:  .quad 0                   // an NSTextView: the status, a race's others
_g_ffw_field:   .quad 0
_g_ffw_style:   .quad 0                   // the tiles' letters: big, bold, white
_g_ffw_msg:     .quad 0                   // a line to show once (why a guess didn't count)
_g_ffw_tile:    .space 240                // 30 buttons
_g_ffw_key:     .space 208                // 26 buttons, a-z
.zerofill __DATA,__bss,_g_ffw_shown,64,4  // what each tile shows now (letter, colour)
.zerofill __DATA,__bss,_g_ffw_kshown,32,4
.zerofill __DATA,__bss,_g_ffw_buf,2048,4
.zerofill __DATA,__bss,_g_ffw_text,2048,4
.zerofill __DATA,__bss,_g_ffw_typed,32,4

.section __TEXT,__const
.p2align 3
Lw_zero:    .double 0.0
Lw_W:       .double 440.0
Lw_H:       .double 680.0
Lw_letter:  .double 28.0
Lw_s13:     .double 13.0
Lw_s15:     .double 15.0
Lw_tile:    .double 56.0
Lw_step:    .double 62.0
Lw_tx0:     .double 65.0
Lw_ty0:     .double 520.0
Lw_kw:      .double 36.0
Lw_kh:      .double 38.0
Lw_kx0:     .double 42.0
Lf_status:  .double 20.0, 590.0, 400.0, 76.0
Lf_field:   .double 20.0, 16.0, 140.0, 28.0
Lf_share:   .double 166.0, 16.0, 76.0, 28.0
Lf_race:    .double 248.0, 16.0, 82.0, 28.0
Lf_duel:    .double 336.0, 16.0, 84.0, 28.0
Lf_enter:   .double 42.0, 72.0, 64.0, 38.0
Lf_del:     .double 334.0, 72.0, 64.0, 38.0
Lw_krow_y:  .double 160.0, 116.0, 72.0
.p2align 2
Lw_colours: .word 0x3A3A3C, 0x3B82F6, 0xF5B82E, 0x5A5A5E   // dark, blue, amber, sent
            .word 0x262628, 0x48484C                       //   empty, being typed
Lw_kcol:    .word 0x2C2C2E, 0x3B82F6, 0xF5B82E, 0x6E6E73   // keys: by what's known
Lw_rows:    .byte 0, 10, 19, 26                            // the keyboard's rows
Lw_kx:      .byte 0, 0, 1, 2                               //   how far in (half keys)

.text
.p2align 2

// void _ff_ui_pop(void) — the game, in front
.globl _ff_ui_pop
_ff_ui_pop:
    ENTER 0
    ADRL x8, _g_window                    // selftest: no window at all
    ldr  x8, [x8]
    cbz  x8, 9f
    ADRL x8, _g_ffw
    ldr  x0, [x8]
    cbnz x0, 1f
    bl   Lfw_build
1:  bl   Lfw_forget
    ADRL x8, _g_ffw
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    ADRL x8, _g_ffw
    ldr  x0, [x8]
    MSG0 Ls_orderFrontRegardless
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    ADRL x8, _g_ffw                       // typing goes to the box
    ldr  x0, [x8]
    ADRL x8, _g_ffw_field
    ldr  x2, [x8]
    MSG1 Ls_makeFirstResponder
    bl   _ff_ui_show
9:  LEAVE 0

// Lfw_forget — draw every tile and key afresh next time (leaf)
Lfw_forget:
    ADRL x8, _g_ffw_shown
    mov  x9, #0
    mov  w10, #0xFF
1:  strb w10, [x8, x9]
    add  x9, x9, #1
    cmp  x9, #64
    b.lo 1b
    ADRL x8, _g_ffw_kshown
    mov  x9, #0
2:  strb w10, [x8, x9]
    add  x9, x9, #1
    cmp  x9, #32
    b.lo 2b
    ADRL x8, _g_ffw_text
    strb wzr, [x8]
    ret

// void _ff_ui_show(void) — the window shows the game as it is now
.globl _ff_ui_show
_ff_ui_show:
    ENTER 32
    ADRL x8, _g_ffw
    ldr  x19, [x8]
    cbz  x19, 9f
    bl   _am_ff_mode
    cbnz x0, 1f
    mov  x0, x19                          // no game: put it away
    mov  x2, #0
    MSG1 Ls_orderOut
    b    9f
1:  bl   Lfw_typed                        // what's in the box, for the row being typed
    bl   _am_ff_state                     //   (only while guessing)
    cmp  x0, #FFS_PLAY
    b.eq 11f
    ADRL x8, _g_ffw_typed
    strb wzr, [x8]
11: mov  x20, #0                          // the tiles
    mov  x24, #-1                         // the first empty row: where typing shows
2:  mov  x9, #5
    udiv x21, x20, x9                     // row
    msub x22, x21, x9, x20                // column
    mov  x0, x21
    mov  x1, x22
    bl   _am_ff_cell
    mov  x23, x0
    cbnz x23, 4f
    tbz  x24, #63, 3f
    mov  x24, x21
3:  cmp  x21, x24                         // the row being typed: the box's letters
    b.ne 31f
    ADRL x8, _g_ffw_typed
    ldrb w9, [x8, x22]
    cbz  w9, 31f
    lsl  w9, w9, #8
    add  w23, w9, #5
    b    4f
31: mov  w23, #4                          // empty
4:  ADRL x8, _g_ffw_shown
    add  x9, x8, x20, lsl #1
    lsr  w10, w23, #8
    and  w11, w23, #0xFF
    ldrb w12, [x9]
    ldrb w13, [x9, #1]
    cmp  w12, w10
    ccmp w13, w11, #0, eq
    b.eq 5f
    strb w10, [x9]
    strb w11, [x9, #1]
    ADRL x8, _g_ffw_tile
    ldr  x0, [x8, x20, lsl #3]
    mov  x1, x10
    mov  x2, x11
    bl   Lfw_draw
5:  add  x20, x20, #1
    cmp  x20, #30
    b.lo 2b
    mov  x20, #0                          // the keys
6:  add  x0, x20, #'a'
    bl   _am_ff_key
    ADRL x8, _g_ffw_kshown
    ldrb w9, [x8, x20]
    cmp  w9, w0
    b.eq 7f
    strb w0, [x8, x20]
    mov  x21, x0
    ADRL x8, Lw_kcol
    ldr  w0, [x8, x21, lsl #2]
    bl   _rgb
    mov  x2, x0
    ADRL x8, _g_ffw_key
    ldr  x0, [x8, x20, lsl #3]
    MSG1 Ls_setBezelColor
7:  add  x20, x20, #1
    cmp  x20, #26
    b.lo 6b
    ADRL x19, _g_ffw_buf                  // the status, a line of why, a race's others
    strb wzr, [x19]
    ADRL x8, _g_ffw_msg
    ldr  x1, [x8]
    cbz  x1, 71f
    str  xzr, [x8]
    add  x1, x1, #3                       // (without its "· ")
    mov  x0, x19
    mov  x2, #2048
    bl   _strlcpy
    mov  x0, x19
    ADRL x1, Ls_nl
    mov  x2, #2048
    bl   _strlcat
71: mov  x0, x19
    bl   _strlen
    add  x0, x19, x0
    mov  x1, #600
    bl   _am_ff_status
    mov  x0, x19
    ADRL x1, Ls_nl
    mov  x2, #2048
    bl   _strlcat
    mov  x0, x19
    bl   _strlen
    add  x0, x19, x0
    mov  x1, #1200
    bl   _am_ff_others
    ADRL x0, _g_ffw_buf
    ADRL x1, _g_ffw_text
    bl   _strcmp
    cbz  w0, 9f
    ADRL x0, _g_ffw_text
    ADRL x1, _g_ffw_buf
    mov  x2, #2048
    bl   _strlcpy
    ADRL x0, _g_ffw_buf
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_ffw_status
    ldr  x0, [x8]
    MSG1 Ls_setString
9:  LEAVE 32

// Lfw_typed — the box's letters (a-z, five at most) into _g_ffw_typed
Lfw_typed:
    ENTER 0
    ADRL x19, _g_ffw_typed
    strb wzr, [x19]
    ADRL x8, _g_ffw_field
    ldr  x0, [x8]
    cbz  x0, 9f
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, 9f
    mov  x9, #0
1:  ldrb w10, [x0], #1
    cbz  w10, 8f
    orr  w10, w10, #0x20
    sub  w11, w10, #'a'
    cmp  w11, #25
    b.hi 1b
    strb w10, [x19, x9]
    add  x9, x9, #1
    cmp  x9, #5
    b.lo 1b
8:  strb wzr, [x19, x9]
9:  LEAVE 0

// Lfw_draw(x0 button, x1 letter (0 none), x2 colour index) — a tile
Lfw_draw:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    ADRL x8, Lw_colours
    ldr  w0, [x8, x2, lsl #2]
    bl   _rgb
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setBezelColor
    mov  w9, #' '
    cbz  w20, 1f
    sub  w9, w20, #0x20                   // in capitals
1:  strb w9, [sp, #96]
    strb wzr, [sp, #97]
    bl   Lfw_style
    mov  x21, x0
    add  x0, sp, #96
    bl   _nsstr
    mov  x22, x0
    CLS  Ls_NSAttributedString
    MSG0 Ls_alloc
    mov  x2, x22
    mov  x3, x21
    MSG2 Ls_initWithStringAttributes
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setAttributedTitle
    LEAVE 16

// id Lfw_style — the tiles' letters' attributes, made once
Lfw_style:
    ENTER 32                              // [96] objects (2)  [112] keys (2)
    ADRL x8, _g_ffw_style
    ldr  x0, [x8]
    cbnz x0, 9f
    LDD  d0, Lw_letter
    mov  w0, #1
    bl   _font
    str  x0, [sp, #96]
    CLS  Ls_NSColor
    MSG0 Ls_whiteColor
    str  x0, [sp, #104]
    LDGOT x8, _NSFontAttributeName
    ldr  x9, [x8]
    LDGOT x8, _NSForegroundColorAttributeName
    ldr  x10, [x8]
    stp  x9, x10, [sp, #112]
    CLS  Ls_NSDictionary
    add  x2, sp, #96
    add  x3, sp, #112
    mov  x4, #2
    MSG3 Ls_dictWithObjectsForKeys
    MSG0 Ls_retain
    ADRL x8, _g_ffw_style
    str  x0, [x8]
9:  LEAVE 32

// Lfw_build — the window, once
Lfw_build:
    ENTER 32
    CLS  Ls_NSWindow
    MSG0 Ls_alloc
    mov  x20, x0
    SELX1 Ls_initWithContentRect
    mov  x0, x20
    LDD  d0, Lw_zero
    LDD  d1, Lw_zero
    LDD  d2, Lw_W
    LDD  d3, Lw_H
    mov  x2, #7
    mov  x3, #2
    mov  x4, #0
    bl   _objc_msgSend
    mov  x20, x0
    ADRL x8, _g_ffw
    str  x20, [x8]
    mov  x0, x20                          // a board: dark in light mode too (appear.s)
    bl   _appear_dark
    ADRL x0, Ls_w_title
    bl   _nsstr
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_setTitle
    mov  x0, x20
    mov  x2, #0
    MSG1 Ls_setReleasedWhenClosed
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
    mov  x0, x21                          // the status
    mov  x1, #0
    ADRL x8, Lf_status
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_textview
    ADRL x8, _g_ffw_status
    str  x0, [x8]
    mov  x2, #0
    MSG1 Ls_setEditable
    mov  x22, #0                          // the tiles, top left first
1:  mov  x9, #5
    udiv x10, x22, x9
    msub x11, x10, x9, x22
    scvtf d0, x11
    LDD  d4, Lw_step
    fmul d0, d0, d4
    LDD  d5, Lw_tx0
    fadd d0, d0, d5
    scvtf d1, x10
    fmul d1, d1, d4
    LDD  d5, Lw_ty0
    fsub d1, d5, d1
    LDD  d2, Lw_tile
    fmov d3, d2
    ADRL x0, Ls_empty
    ADRL x1, Ls_m_ffTile
    mov  x2, #0
    mov  x3, x21
    bl   _mk_button
    ADRL x8, _g_ffw_tile
    str  x0, [x8, x22, lsl #3]
    add  x22, x22, #1
    cmp  x22, #30
    b.lo 1b
    mov  x22, #0                          // the keys: QWERTY, three rows
    mov  x23, #0                          //   the row
2:  ADRL x8, Lw_rows
    add  x9, x23, #1
    ldrb w9, [x8, x9]
    cmp  x22, x9
    b.lo 3f
    add  x23, x23, #1
    b    2b
3:  ldrb w9, [x8, x23]
    sub  x10, x22, x9                     // across
    scvtf d0, x10
    LDD  d4, Lw_kw
    fmul d0, d0, d4
    ADRL x8, Lw_kx
    ldrb w9, [x8, x23]
    scvtf d5, x9
    fmov d6, #0.5
    fmul d5, d5, d6
    fmul d5, d5, d4
    fadd d0, d0, d5
    LDD  d5, Lw_kx0
    fadd d0, d0, d5
    cmp  x23, #2                          // the last row: after Enter
    b.ne 4f
    fmov d5, #1.0
    fmul d5, d5, d4
    fadd d0, d0, d5
4:  ADRL x8, Lw_krow_y
    ldr  d1, [x8, x23, lsl #3]
    fmov d6, #4.0
    fsub d2, d4, d6
    LDD  d3, Lw_kh
    ADRL x8, Lw_qwerty                    // its letter, as its title
    ldrb w9, [x8, x22]
    sub  w10, w9, #0x20
    strb w10, [sp, #96]
    strb wzr, [sp, #97]
    str  x9, [sp, #104]
    add  x0, sp, #96
    ADRL x1, Ls_m_ffKey
    mov  x2, #0
    mov  x3, x21
    bl   _mk_button
    mov  x24, x0
    ldr  x2, [sp, #104]
    MSG1 Ls_setTag
    ldr  x9, [sp, #104]
    sub  x9, x9, #'a'
    ADRL x8, _g_ffw_key
    str  x24, [x8, x9, lsl #3]
    add  x22, x22, #1
    cmp  x22, #26
    b.lo 2b
    ADRL x0, Ls_w_enter                   // Enter, Delete
    ADRL x1, Ls_m_ffKey
    ADRL x8, Lf_enter
    bl   Lfw_button
    mov  x2, #1
    MSG1 Ls_setTag
    ADRL x0, Ls_w_del
    ADRL x1, Ls_m_ffKey
    ADRL x8, Lf_del
    bl   Lfw_button
    mov  x2, #2
    MSG1 Ls_setTag
    CLS  Ls_NSTextField                   // the box: Enter sends the guess
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithFrame
    mov  x0, x22
    ADRL x8, Lf_field
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x22, x0
    ADRL x8, _g_ffw_field
    str  x22, [x8]
    ADRL x0, Ls_w_ph
    bl   _nsstr
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setPlaceholderString
    LDD  d0, Lw_s15
    mov  w0, #1
    bl   _font
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setFont
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x22
    MSG1 Ls_setTarget
    ADRL x0, Ls_m_ffEnter
    bl   _sel_registerName
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setAction
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_addSubview
    ADRL x0, Ls_w_share
    ADRL x1, Ls_m_ffShare
    ADRL x8, Lf_share
    bl   Lfw_button
    ADRL x0, Ls_w_race
    ADRL x1, Ls_m_ffRace
    ADRL x8, Lf_race
    bl   Lfw_button
    ADRL x0, Ls_w_duel
    ADRL x1, Ls_m_ffDuel
    ADRL x8, Lf_duel
    bl   Lfw_button
    LEAVE 32

// Lfw_button(x0 title, x1 selector name, x8 frame) -> the button, in the window (x21)
Lfw_button:
    ENTER 0
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    mov  x2, #0
    mov  x3, x21
    bl   _mk_button
    LEAVE 0

// ---------------------------------------------------------------------------
// The controller's methods (main.s's table)

// - ffKey:(id)sender — a letter into the box; 1 Enter, 2 Delete
.globl _ffw_key
_ffw_key:
    ENTER 48                              // [96] the box's text (32)
    mov  x0, x2
    MSG0 Ls_tag
    mov  x19, x0
    cmp  x19, #1
    b.eq 8f
    bl   Lfw_typed
    add  x0, sp, #96
    ADRL x1, _g_ffw_typed
    mov  x2, #32
    bl   _strlcpy
    mov  x20, x0                          // its length
    cmp  x19, #2
    b.ne 1f
    cbz  x20, 9f
    sub  x20, x20, #1
    b    2f
1:  cmp  x20, #5
    b.hs 9f
    add  x9, sp, #96
    strb w19, [x9, x20]
    add  x20, x20, #1
2:  add  x9, sp, #96
    strb wzr, [x9, x20]
    add  x0, sp, #96
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_ffw_field
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    bl   _ff_ui_show
    b    9f
8:  bl   _ffw_enter
9:  LEAVE 48

// - ffEnter:(id)sender — the box's word, as a guess (a duel's first: our word for them)
.globl _ffw_enter
_ffw_enter:
    ENTER 48                              // [96] the word (32)
    ADRL x8, _g_ffw_field
    ldr  x0, [x8]
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, 9f
    mov  x1, x0
    add  x0, sp, #96
    mov  x2, #32
    bl   _strlcpy
    ldrb w9, [sp, #96]
    cbz  w9, 9f
    add  x0, sp, #96
    bl   _am_ff_try
    tbz  x0, #63, 1f
    bl   _am_ff_why                       // it didn't count: say why, keep the letters
    ADRL x8, _g_ffw_msg
    str  x0, [x8]
    bl   _NSBeep
    bl   _ff_ui_show
    b    9f
1:  ADRL x0, Ls_empty
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_ffw_field
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    bl   _ff_ui_show
9:  LEAVE 48

// - ffTile:(id)sender — nothing (tiles are buttons only to look like tiles)
.globl _ffw_tile
_ffw_tile:
    ret

// - ffShare:(id)sender — the squares, to Main
.globl _ffw_share
_ffw_share:
    ENTER 0
    mov  x0, #4
    ADRL x1, Ls_empty
    ADRL x2, Ls_empty
    bl   _h_fivefold
    LEAVE 0

// - ffRace:(id)sender, - ffDuel:(id)sender — who with
.globl _ffw_race
_ffw_race:
    mov  x0, #2
    b    Lfw_with
.globl _ffw_duel
_ffw_duel:
    mov  x0, #3
Lfw_with:
    ENTER 160                             // [96] the names (128)
    mov  x19, x0
    strb wzr, [sp, #96]
    ADRL x8, _g_node_count                // the first one on the mesh, filled in
    ldr  x9, [x8]
    cbz  x9, 1f
    add  x0, sp, #96
    ADRL x8, _g_nodes
    add  x1, x8, #N_NICK
    mov  x2, #64
    bl   _strlcpy
1:  ADRL x0, Ls_dlg_race
    ADRL x1, Ls_dlg_race_info
    cmp  x19, #3
    b.ne 2f
    ADRL x0, Ls_dlg_duel
    ADRL x1, Ls_dlg_duel_info
2:  ADRL x2, Ls_dlg_ph
    add  x3, sp, #96
    mov  x4, #0
    add  x5, sp, #96
    mov  x6, #128
    bl   _ask_text
    cbz  x0, 9f
    mov  x0, x19
    add  x1, sp, #96
    add  x2, sp, #96
    bl   _h_fivefold
9:  LEAVE 160

// - playFivefold:(id)sender — Mesh › Play Fivefold…, the sidebar's button: today's word
.globl _ff_dialog
_ff_dialog:
    ENTER 0
    bl   _am_ff_solo
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lw_qwerty:          .asciz "qwertyuiopasdfghjklzxcvbnm"
Ls_empty:           .asciz ""
Ls_nl:              .asciz "\n"
Ls_w_title:         .asciz "Fivefold"
Ls_w_enter:         .asciz "Enter"
Ls_w_del:           .asciz "\342\214\253"
Ls_w_ph:            .asciz "five letters"
Ls_w_share:         .asciz "Share"
Ls_w_race:          .asciz "Race\342\200\246"
Ls_w_duel:          .asciz "Duel\342\200\246"
Ls_m_ffTile:        .asciz "ffTile:"
Ls_m_ffKey:         .asciz "ffKey:"
Ls_m_ffEnter:       .asciz "ffEnter:"
Ls_m_ffShare:       .asciz "ffShare:"
Ls_m_ffRace:        .asciz "ffRace:"
Ls_m_ffDuel:        .asciz "ffDuel:"
Ls_dlg_race:        .asciz "Fivefold Race"
Ls_dlg_race_info:   .asciz "Who to race: names as People shows them, with commas. Everyone gets the same word; each of you sees the others\342\200\231 colours, never their letters."
Ls_dlg_duel:        .asciz "Fivefold Duel"
Ls_dlg_duel_info:   .asciz "Who to duel: a name as People shows it. Each of you picks a five-letter word for the other; both are sealed until the end, then every answer is checked."
Ls_dlg_ph:          .asciz "Anna"
Ls_NSApplication:   .asciz "NSApplication"
Ls_NSWindow:        .asciz "NSWindow"
Ls_NSColor:         .asciz "NSColor"
Ls_NSTextField:     .asciz "NSTextField"
Ls_NSAttributedString: .asciz "NSAttributedString"
Ls_NSDictionary:    .asciz "NSDictionary"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_makeFirstResponder: .asciz "makeFirstResponder:"
Ls_orderFrontRegardless: .asciz "orderFrontRegardless"
Ls_orderOut:        .asciz "orderOut:"
Ls_setStringValue:  .asciz "setStringValue:"
Ls_stringValue:     .asciz "stringValue"
Ls_UTF8String:      .asciz "UTF8String"
Ls_setString:       .asciz "setString:"
Ls_setEditable:     .asciz "setEditable:"
Ls_setBezelColor:   .asciz "setBezelColor:"
Ls_whiteColor:      .asciz "whiteColor"
Ls_dictWithObjectsForKeys: .asciz "dictionaryWithObjects:forKeys:count:"
Ls_retain:          .asciz "retain"
Ls_alloc:           .asciz "alloc"
Ls_initWithFrame:   .asciz "initWithFrame:"
Ls_initWithStringAttributes: .asciz "initWithString:attributes:"
Ls_setAttributedTitle: .asciz "setAttributedTitle:"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_setTitle:        .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_setBackgroundColor: .asciz "setBackgroundColor:"
Ls_setPlaceholderString: .asciz "setPlaceholderString:"
Ls_setFont:         .asciz "setFont:"
Ls_setTarget:       .asciz "setTarget:"
Ls_setAction:       .asciz "setAction:"
Ls_addSubview:      .asciz "addSubview:"
Ls_center:          .asciz "center"
Ls_contentView:     .asciz "contentView"
Ls_setTag:          .asciz "setTag:"
Ls_tag:             .asciz "tag"
