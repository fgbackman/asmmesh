// ch_win.s — the chess board's window on the Mac: 64 squares seen from our side (click a
// piece of ours, its moves light up, click one to play it), the status, the moves so far,
// Resign and Offer Draw. ch_mesh.s brings it up (_ch_ui_pop: a game set up, every move)
// and asks for a redraw (_ch_ui_show). Typing moves in the game's room works as well.
.include "macros.inc"

.set CW_SQ,     56                        // a square's size

.data
.p2align 3
_g_chw:         .quad 0                   // the window
_g_chw_status:  .quad 0
_g_chw_moves:   .quad 0                   // an NSTextView
_g_chw_sel:     .quad -1                  // the square picked, or -1
_g_chw_btn:     .space 512                // 64 buttons, by place on screen (0 top left)
.zerofill __DATA,__bss,_g_chw_shown,128,4 // what each shows now: piece, colour
.zerofill __DATA,__bss,_g_chw_targets,32,4
_g_chw_ntargets: .quad 0
.zerofill __DATA,__bss,_g_chw_buf,2048,4
.zerofill __DATA,__bss,_g_chw_text,2048,4

.section __TEXT,__const
.p2align 3
Lw_zero:    .double 0.0
Lw_W:       .double 520.0
Lw_H:       .double 640.0
Lw_glyph:   .double 34.0
Lw_s13:     .double 13.0
Lw_sq:      .double 56.0
Lw_x0:      .double 36.0
Lw_y0:      .double 128.0
Lf_status:  .double 36.0, 600.0, 448.0, 20.0
Lf_resign:  .double 36.0, 84.0, 120.0, 30.0
Lf_draw:    .double 164.0, 84.0, 120.0, 30.0
Lf_moves:   .double 36.0, 14.0, 448.0, 62.0
.p2align 2
Lw_colours: .word 0xEEEED2, 0x769656      // light, dark squares
            .word 0xF6F669, 0xBACA44      //   picked, a move it can make
            .word 0xCDD26A, 0xAAA23A      //   the last move (light, dark)

.text
.p2align 2

// void _ch_ui_pop(void) — the board, in front
.globl _ch_ui_pop
_ch_ui_pop:
    ENTER 0
    ADRL x8, _g_window                    // selftest: no window at all
    ldr  x8, [x8]
    cbz  x8, 9f
    ADRL x8, _g_chw
    ldr  x0, [x8]
    cbnz x0, 1f
    bl   Lcw_build
1:  ADRL x8, _g_chw_shown                 // draw everything afresh
    mov  x9, #0
2:  mov  w10, #0xFF
    strb w10, [x8, x9]
    add  x9, x9, #1
    cmp  x9, #128
    b.lo 2b
    ADRL x8, _g_chw_text
    strb wzr, [x8]
    ADRL x8, _g_chw
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    ADRL x8, _g_chw
    ldr  x0, [x8]
    MSG0 Ls_orderFrontRegardless
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    bl   _ch_ui_show
9:  LEAVE 0

// void _ch_ui_show(void) — the window shows the game as it is now
.globl _ch_ui_show
_ch_ui_show:
    ENTER 16
    ADRL x8, _g_chw
    ldr  x19, [x8]
    cbz  x19, 9f
    bl   _am_ch_state
    cbnz x0, 1f
    mov  x0, x19                          // no game: put it away
    mov  x2, #0
    MSG1 Ls_orderOut
    b    9f
1:  ADRL x0, _g_chw_buf                   // the status: "Anna · Your move (you're white)"
    mov  x1, #600
    bl   _am_ch_status
    ADRL x0, _g_chw_buf
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_chw_status
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    bl   _am_ch_last
    mov  x22, x0                          // the last move's squares
    mov  x20, #0                          // each square on screen
2:  mov  x0, x20
    bl   Lcw_square
    mov  x21, x0
    bl   _am_ch_piece
    mov  x23, x0
    mov  x0, x21                          // its colour: 0/1 light/dark, 2 picked, 3 a target,
    bl   Lcw_colour                       //   4/5 the last move
    mov  x24, x0
    ADRL x8, _g_chw_shown
    add  x9, x8, x20, lsl #1
    ldrb w10, [x9]
    ldrb w11, [x9, #1]
    cmp  w10, w23
    ccmp w11, w24, #0, eq
    b.eq 3f
    strb w23, [x9]
    strb w24, [x9, #1]
    ADRL x8, _g_chw_btn
    ldr  x0, [x8, x20, lsl #3]
    mov  x1, x23
    mov  x2, x24
    bl   Lcw_draw
3:  add  x20, x20, #1
    cmp  x20, #64
    b.lo 2b
    ADRL x0, _g_chw_buf                   // the moves, when they change
    mov  x1, #2000
    bl   _am_ch_moves
    ADRL x0, _g_chw_buf
    ADRL x1, _g_chw_text
    bl   _strcmp
    cbz  w0, 9f
    ADRL x0, _g_chw_text
    ADRL x1, _g_chw_buf
    mov  x2, #2048
    bl   _strlcpy
    ADRL x0, _g_chw_buf
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_chw_moves
    ldr  x0, [x8]
    MSG1 Ls_setString
    ADRL x8, _g_chw_moves
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_scrollToEndOfDocument
9:  LEAVE 16

// Lcw_square(x0 place 0-63, top left first) -> the square there, as we see the board
Lcw_square:
    ENTER 0
    mov  x19, x0
    bl   _am_ch_me
    lsr  x9, x19, #3                      // row on screen
    and  x10, x19, #7                     // column
    mov  x11, #7
    sub  x12, x11, x9                     // white: rank 8 on top, a on the left
    mov  x13, x10
    cbz  x0, 1f
    mov  x12, x9                          // black: rank 1 on top, h on the left
    sub  x13, x11, x10
1:  add  x0, x13, x12, lsl #4
    LEAVE 0

// Lcw_colour(x0 square, x22 the last move) -> its colour's index (leaf-ish)
Lcw_colour:
    ENTER 0
    mov  x19, x0
    lsr  x9, x19, #4
    and  x10, x19, #7
    add  x9, x9, x10
    and  x20, x9, #1
    eor  x20, x20, #1                     // a1 is dark
    ADRL x8, _g_chw_sel
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne 1f
    mov  x0, #2
    LEAVE 0
1:  ADRL x8, _g_chw_ntargets
    ldr  x9, [x8]
    ADRL x8, _g_chw_targets
    mov  x10, #0
2:  cmp  x10, x9
    b.hs 3f
    ldrb w11, [x8, x10]
    add  x10, x10, #1
    cmp  x11, x19
    b.ne 2b
    mov  x0, #3
    LEAVE 0
3:  tbnz x22, #63, 4f
    and  x9, x22, #0xFF
    cmp  x9, x19
    b.eq 31f
    ubfx x9, x22, #8, #8
    cmp  x9, x19
    b.ne 4f
31: add  x0, x20, #4
    LEAVE 0
4:  mov  x0, x20
    LEAVE 0

// Lcw_draw(x0 button, x1 piece, x2 colour index) — a square: its colour and its piece
Lcw_draw:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    ADRL x8, Lw_colours
    ldr  w0, [x8, x2, lsl #2]
    bl   _rgb
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setBezelColor
    ADRL x8, Lw_glyphs                    // the piece's symbol (4 bytes each)
    and  x9, x20, #15
    ldr  w9, [x8, x9, lsl #2]
    str  w9, [sp, #96]
    strb wzr, [sp, #100]
    LDD  d0, Lw_glyph
    mov  w0, #0
    bl   _font
    mov  x21, x0
    CLS  Ls_NSColor
    MSG0 Ls_blackColor
    mov  x1, x0
    mov  x0, x21
    bl   _dict2
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

// Lcw_build — the window, once
Lcw_build:
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
    ADRL x8, _g_chw
    str  x20, [x8]
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
    ADRL x0, Ls_empty
    mov  x1, #0
    mov  x2, #1
    mov  x3, x21
    ADRL x8, Lf_status
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lw_s13
    bl   _mk_label
    ADRL x8, _g_chw_status
    str  x0, [x8]
    mov  x22, #0                          // the squares, top left first
1:  lsr  x9, x22, #3
    and  x10, x22, #7
    scvtf d0, x10
    LDD  d4, Lw_sq
    fmul d0, d0, d4
    LDD  d5, Lw_x0
    fadd d0, d0, d5
    mov  x11, #7
    sub  x9, x11, x9
    scvtf d1, x9
    fmul d1, d1, d4
    LDD  d5, Lw_y0
    fadd d1, d1, d5
    fmov d2, d4
    fmov d3, d4
    ADRL x0, Ls_empty
    ADRL x1, Ls_m_square
    mov  x2, #0
    mov  x3, x21
    bl   _mk_button
    mov  x23, x0
    ADRL x8, _g_chw_btn
    str  x23, [x8, x22, lsl #3]
    mov  x2, x22
    MSG1 Ls_setTag
    add  x22, x22, #1
    cmp  x22, #64
    b.lo 1b
    ADRL x0, Ls_w_resign
    ADRL x1, Ls_m_resign
    ADRL x8, Lf_resign
    bl   Lcw_button
    ADRL x0, Ls_w_draw
    ADRL x1, Ls_m_draw
    ADRL x8, Lf_draw
    bl   Lcw_button
    mov  x0, x21
    mov  x1, #0
    ADRL x8, Lf_moves
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_textview
    ADRL x8, _g_chw_moves
    str  x0, [x8]
    LEAVE 32

// Lcw_button(x0 title, x1 selector name, x8 frame) — in the window (x21)
Lcw_button:
    ENTER 0
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    mov  x2, #0
    mov  x3, x21
    bl   _mk_button
    LEAVE 0

// ---------------------------------------------------------------------------
// The controller's methods (main.s's table)

// - chSquare:(id)sender — a square clicked: pick a piece of ours, or move the one picked
.globl _chw_square
_chw_square:
    ENTER 16
    mov  x0, x2
    MSG0 Ls_tag
    cmp  x0, #63
    b.hi 9f
    bl   Lcw_square
    mov  x19, x0                          // the square
    ADRL x8, _g_chw_sel
    ldr  x20, [x8]
    tbnz x20, #63, Lsq_pick
    ADRL x8, _g_chw_ntargets              // one of the picked piece's moves?
    ldr  x9, [x8]
    ADRL x8, _g_chw_targets
    mov  x10, #0
1:  cmp  x10, x9
    b.hs Lsq_pick
    ldrb w11, [x8, x10]
    add  x10, x10, #1
    cmp  x11, x19
    b.ne 1b
    bl   Lsq_clear
    mov  x0, x20
    mov  x1, x19
    bl   _am_ch_move
    b    8f
Lsq_pick:
    bl   Lsq_clear
    mov  x0, x19
    ADRL x1, _g_chw_targets
    bl   _am_ch_targets
    cbz  x0, 8f                           // not ours, or nowhere to go
    ADRL x8, _g_chw_ntargets
    str  x0, [x8]
    ADRL x8, _g_chw_sel
    str  x19, [x8]
8:  bl   _ch_ui_show
9:  LEAVE 16

// Lsq_clear — nothing picked
Lsq_clear:
    ADRL x8, _g_chw_sel
    mov  x9, #-1
    str  x9, [x8]
    ADRL x8, _g_chw_ntargets
    str  xzr, [x8]
    ret

// - chResign:(id)sender, - chDraw:(id)sender
.globl _chw_resign
_chw_resign:
    ENTER 0
    ADRL x0, Ls_w_resigncmd
    bl   _am_ch_say
    LEAVE 0
.globl _chw_draw
_chw_draw:
    ENTER 0
    ADRL x0, Ls_w_drawcmd
    bl   _am_ch_say
    LEAVE 0

// - playChess:(id)sender — Mesh › Play Chess…: who (a name as People shows it)
.globl _ch_dialog
_ch_dialog:
    ENTER 160                             // [96] the name (64)
    strb wzr, [sp, #96]
    ADRL x8, _g_node_count                // the first one on the mesh, filled in
    ldr  x9, [x8]
    cbz  x9, 1f
    add  x0, sp, #96
    ADRL x8, _g_nodes
    add  x1, x8, #N_NICK
    mov  x2, #64
    bl   _strlcpy
1:  ADRL x0, Ls_dlg_title
    ADRL x1, Ls_dlg_info
    ADRL x2, Ls_dlg_ph
    add  x3, sp, #96
    mov  x4, #0
    add  x5, sp, #96
    mov  x6, #64
    bl   _ask_text
    cbz  x0, 9f
    mov  x0, #0
    add  x1, sp, #96
    add  x2, sp, #96
    bl   _h_chess
9:  LEAVE 160

// ---------------------------------------------------------------------------
.section __TEXT,__const
Lw_glyphs:
    .byte 0x20, 0, 0, 0                   // empty
    .byte 0xE2, 0x99, 0x99, 0             // ♙ ♘ ♗ ♖ ♕ ♔
    .byte 0xE2, 0x99, 0x98, 0
    .byte 0xE2, 0x99, 0x97, 0
    .byte 0xE2, 0x99, 0x96, 0
    .byte 0xE2, 0x99, 0x95, 0
    .byte 0xE2, 0x99, 0x94, 0
    .byte 0x20, 0, 0, 0
    .byte 0x20, 0, 0, 0
    .byte 0xE2, 0x99, 0x9F, 0             // ♟ ♞ ♝ ♜ ♛ ♚
    .byte 0xE2, 0x99, 0x9E, 0
    .byte 0xE2, 0x99, 0x9D, 0
    .byte 0xE2, 0x99, 0x9C, 0
    .byte 0xE2, 0x99, 0x9B, 0
    .byte 0xE2, 0x99, 0x9A, 0
    .byte 0x20, 0, 0, 0

.section __TEXT,__cstring,cstring_literals
Ls_empty:           .asciz ""
Ls_w_title:         .asciz "Chess"
Ls_w_resign:        .asciz "Resign"
Ls_w_draw:          .asciz "Offer Draw"
Ls_w_resigncmd:     .asciz "resign"
Ls_w_drawcmd:       .asciz "draw"
Ls_m_square:        .asciz "chSquare:"
Ls_m_resign:        .asciz "chResign:"
Ls_m_draw:          .asciz "chDraw:"
Ls_dlg_title:       .asciz "Play Chess"
Ls_dlg_info:        .asciz "Who to play: a name as People shows it (add \342\200\234black\342\200\235 to play black). Every move is checked on both devices. With a bitchat person, type chess in your private chat with them instead."
Ls_dlg_ph:          .asciz "Anna"
Ls_NSApplication:   .asciz "NSApplication"
Ls_NSWindow:        .asciz "NSWindow"
Ls_NSColor:         .asciz "NSColor"
Ls_NSAttributedString: .asciz "NSAttributedString"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_orderFrontRegardless: .asciz "orderFrontRegardless"
Ls_orderOut:        .asciz "orderOut:"
Ls_setStringValue:  .asciz "setStringValue:"
Ls_setString:       .asciz "setString:"
Ls_scrollToEndOfDocument: .asciz "scrollToEndOfDocument:"
Ls_setBezelColor:   .asciz "setBezelColor:"
Ls_blackColor:      .asciz "blackColor"
Ls_alloc:           .asciz "alloc"
Ls_initWithStringAttributes: .asciz "initWithString:attributes:"
Ls_setAttributedTitle: .asciz "setAttributedTitle:"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_setTitle:        .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_setBackgroundColor: .asciz "setBackgroundColor:"
Ls_center:          .asciz "center"
Ls_contentView:     .asciz "contentView"
Ls_setTag:          .asciz "setTag:"
Ls_tag:             .asciz "tag"
