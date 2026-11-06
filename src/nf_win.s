// nf_win.s — Ninefold's own window on the Mac: the status, nine big tiles (click one to type
// its letter), a box for words, Start / Shuffle / Clear, and below them your words, the
// players and, after a round, the results. nf_mesh.s brings it up (_nf_ui_pop: a game made
// or joined, every round) and keeps it current (_nf_ui_show, every second, via ui.s).
.include "macros.inc"
.set NFS_DONE_W, 5                        // nf_defs.inc's NFS_DONE (scored)

.data
.p2align 3
_g_nfw:         .quad 0                   // the window
_g_nfw_status:  .quad 0
_g_nfw_field:   .quad 0
_g_nfw_start:   .quad 0
_g_nfw_info:    .quad 0                   // an NSTextView
_g_nfw_tiles:   .space 72                 // 9 buttons
.zerofill __DATA,__bss,_g_nfw_shown,16,4  // the letters on the tiles now
.zerofill __DATA,__bss,_g_nfw_text,4096,4 // what the info view shows now
.zerofill __DATA,__bss,_g_nfw_buf,4096,4

.section __TEXT,__const
.p2align 3
Lw_zero:    .double 0.0
Lw_W:       .double 440.0
Lw_H:       .double 600.0
Lw_tile:    .double 34.0
Lw_s13:     .double 13.0
Lw_s15:     .double 15.0
Lf_status:  .double 20.0, 560.0, 400.0, 20.0
Lf_field:   .double 58.0, 216.0, 250.0, 32.0
Lf_enter:   .double 316.0, 216.0, 66.0, 32.0
Lf_bstart:  .double 58.0, 172.0, 104.0, 32.0
Lf_bshuf:   .double 168.0, 172.0, 104.0, 32.0
Lf_bclear:  .double 278.0, 172.0, 104.0, 32.0
Lf_info:    .double 20.0, 16.0, 400.0, 144.0
Lw_tx:      .double 58.0, 168.0, 278.0     // the tiles' columns
Lw_ty:      .double 452.0, 358.0, 264.0    //   and rows, top first
Lw_tsz:     .double 104.0, 84.0

.text
.p2align 2

// void _nf_ui_pop(void) — show the game's window, in front
.globl _nf_ui_pop
_nf_ui_pop:
    ENTER 0
    ADRL x8, _g_window                    // selftest: no window at all
    ldr  x8, [x8]
    cbz  x8, 9f
    ADRL x8, _g_nfw
    ldr  x0, [x8]
    cbnz x0, 1f
    bl   Lnw_build
1:  ADRL x8, _g_nfw_shown                 // draw everything afresh
    strb wzr, [x8]
    ADRL x8, _g_nfw_text
    strb wzr, [x8]
    ADRL x8, _g_nfw
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    ADRL x8, _g_nfw
    ldr  x0, [x8]
    MSG0 Ls_orderFrontRegardless          // even while another app is in front
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    ADRL x8, _g_nfw
    ldr  x0, [x8]
    ADRL x8, _g_nfw_field
    ldr  x2, [x8]
    MSG1 Ls_makeFirstResponder
    bl   _nfw_update
9:  LEAVE 0

// void _nfw_update(void) — the window shows the game as it is now (ui.s's _nf_ui_show)
.globl _nfw_update
_nfw_update:
    ENTER 32                              // [96] tiles (16)
    ADRL x8, _g_nfw
    ldr  x19, [x8]
    cbz  x19, 9f
    bl   _am_nf_state
    mov  x20, x0
    cbnz x20, 1f
    mov  x0, x19                          // no game any more: put it away
    mov  x2, #0
    MSG1 Ls_orderOut
    b    9f
1:  ADRL x0, _g_nfw_buf                   // the status line
    mov  x1, #300
    bl   _am_nf_status
    ADRL x0, _g_nfw_buf
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_nfw_status
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    add  x0, sp, #96                      // the tiles, when they change
    bl   _am_nf_tiles
    mov  x21, #0
2:  add  x9, sp, #96
    ldrb w10, [x9, x21]
    ADRL x11, _g_nfw_shown
    ldrb w12, [x11, x21]
    cmp  w10, w12
    b.eq 3f
    strb w10, [x11, x21]
    ADRL x8, _g_nfw_tiles
    ldr  x0, [x8, x21, lsl #3]
    mov  w1, w10
    cmp  x21, #4
    cset x2, eq
    bl   Lnw_title
3:  add  x21, x21, #1
    cmp  x21, #9
    b.lo 2b
    bl   _am_nf_host                      // Start: the host in the lobby; anyone after a round
    cmp  x20, #NFS_DONE_W
    cset x9, eq
    cmp  x20, #1
    cset x10, eq
    and  x10, x10, x0
    orr  x9, x9, x10
    eor  x2, x9, #1
    ADRL x8, _g_nfw_start
    ldr  x0, [x8]
    MSG1 Ls_setHidden
    bl   Lnw_info
9:  LEAVE 32

// Lnw_info — the text under the buttons: the results after a round; else the last answer,
//   your words and the players (x20: the state)
Lnw_info:
    ENTER 32
    ADRL x19, _g_nfw_buf
    strb wzr, [x19]
    cmp  x20, #NFS_DONE_W
    b.ne Lni_play
    mov  x21, #0                          // the results, a line each
1:  mov  x0, x21
    ADRL x1, _g_nfw_buf
    add  x1, x1, #2048
    mov  x2, #2000
    bl   _am_nf_result
    cbz  x0, Lni_set
    ADRL x0, _g_nfw_buf
    ADRL x1, _g_nfw_buf
    add  x1, x1, #2048
    mov  x2, #2040
    bl   _strlcat
    ADRL x0, _g_nfw_buf
    ADRL x1, Ls_nl2
    mov  x2, #2040
    bl   _strlcat
    add  x21, x21, #1
    b    1b
Lni_play:
    cmp  x20, #1                          // the lobby
    b.ne 2f
    bl   _am_nf_host
    ADRL x1, Ls_w_lobby_guest
    ADRL x9, Ls_w_lobby_host
    cmp  x0, #0
    csel x1, x9, x1, ne
    ADRL x0, _g_nfw_buf
    mov  x2, #2040
    bl   _strlcpy
    b    Lni_set
2:  bl   _am_nf_last                      // "✓ TOOLING +4"
    mov  x1, x0
    ldrb w9, [x1]
    cbz  w9, 3f
    ADRL x0, _g_nfw_buf
    mov  x2, #2040
    bl   _strlcpy
    ADRL x0, _g_nfw_buf
    ADRL x1, Ls_nl2
    mov  x2, #2040
    bl   _strlcat
3:  ADRL x0, _g_nfw_buf
    ADRL x1, Ls_w_yours
    mov  x2, #2040
    bl   _strlcat
    ADRL x0, _g_nfw_buf
    add  x0, x0, #2048
    mov  x1, #2000
    bl   _am_nf_mine
    ADRL x1, _g_nfw_buf
    add  x1, x1, #2048
    ADRL x9, Ls_w_none
    cmp  x0, #0
    csel x1, x9, x1, eq
    ADRL x0, _g_nfw_buf
    mov  x2, #2040
    bl   _strlcat
    ADRL x0, _g_nfw_buf
    ADRL x1, Ls_nl2
    mov  x2, #2040
    bl   _strlcat
    ADRL x0, _g_nfw_buf                   // the players: "name 5 words · 12 points"
    add  x0, x0, #2048
    mov  x1, #2000
    bl   _am_nf_players
    ADRL x9, _g_nfw_buf
    add  x9, x9, #2048
4:  ldrb w10, [x9]                        // tabs to "  "
    cbz  w10, 5f
    cmp  w10, #9
    b.ne 41f
    mov  w10, #' '
    strb w10, [x9]
41: add  x9, x9, #1
    b    4b
5:  ADRL x0, _g_nfw_buf
    ADRL x1, Ls_w_players
    mov  x2, #2040
    bl   _strlcat
    ADRL x0, _g_nfw_buf
    ADRL x1, _g_nfw_buf
    add  x1, x1, #2048
    mov  x2, #2040
    bl   _strlcat
Lni_set:
    ADRL x0, _g_nfw_buf                   // only when it changed (keeps the scroll still)
    ADRL x1, _g_nfw_text
    bl   _strcmp
    cbz  w0, 9f
    ADRL x0, _g_nfw_text
    ADRL x1, _g_nfw_buf
    mov  x2, #4096
    bl   _strlcpy
    ADRL x0, _g_nfw_buf
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_nfw_info
    ldr  x0, [x8]
    MSG1 Ls_setString
9:  LEAVE 32

// Lnw_title(x0 button, w1 letter, x2 1 for the centre) — a tile's big letter
Lnw_title:
    ENTER 16
    mov  x19, x0
    strb w1, [sp, #96]
    strb wzr, [sp, #97]
    mov  x20, x2
    LDD  d0, Lw_tile
    mov  w0, #1
    bl   _font
    mov  x21, x0
    CLS  Ls_NSColor
    MSG0 Ls_whiteColor
    mov  x22, x0
    cbz  x20, 1f
    CLS  Ls_NSColor
    MSG0 Ls_blackColor
    mov  x22, x0
1:  mov  x0, x21
    mov  x1, x22
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

// Lnw_build — the window, once
Lnw_build:
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
    mov  x2, #7                           // titled, closable, miniaturizable
    mov  x3, #2
    mov  x4, #0
    bl   _objc_msgSend
    mov  x20, x0
    ADRL x8, _g_nfw
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
    ADRL x0, Ls_empty                     // the status line
    mov  x1, #0
    mov  x2, #1
    mov  x3, x21
    ADRL x8, Lf_status
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lw_s13
    bl   _mk_label
    ADRL x8, _g_nfw_status
    str  x0, [x8]
    mov  x22, #0                          // nine tiles
1:  mov  x9, #3
    udiv x10, x22, x9                     // row
    msub x11, x10, x9, x22                // column
    ADRL x8, Lw_tx
    ldr  d0, [x8, x11, lsl #3]
    ADRL x8, Lw_ty
    ldr  d1, [x8, x10, lsl #3]
    ADRL x8, Lw_tsz
    ldp  d2, d3, [x8]
    ADRL x0, Ls_empty
    ADRL x1, Ls_m_tile
    mov  x2, #0
    mov  x3, x21
    bl   _mk_button
    mov  x23, x0
    ADRL x8, _g_nfw_tiles
    str  x23, [x8, x22, lsl #3]
    mov  x2, x22
    MSG1 Ls_setTag
    mov  x0, x23
    mov  x1, #0x3A3C                      // dark tiles, the centre amber
    movk x1, #0x3A, lsl #16
    mov  x2, #0
    cmp  x22, #4
    b.ne 2f
    mov  x1, #0xB82E
    movk x1, #0xF5, lsl #16
    mov  x2, #1
2:  bl   _pill
    add  x22, x22, #1
    cmp  x22, #9
    b.lo 1b
    CLS  Ls_NSTextField                   // the box for words: Enter sends one
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithFrame
    mov  x0, x22
    ADRL x8, Lf_field
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x22, x0
    ADRL x8, _g_nfw_field
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
    ADRL x0, Ls_m_word
    bl   _sel_registerName
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setAction
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_addSubview
    ADRL x0, Ls_w_enter
    ADRL x1, Ls_m_word
    ADRL x8, Lf_enter
    bl   Lnw_button
    ADRL x0, Ls_w_start
    ADRL x1, Ls_m_start
    ADRL x8, Lf_bstart
    bl   Lnw_button
    ADRL x8, _g_nfw_start
    str  x0, [x8]
    mov  x1, #0xB82E
    movk x1, #0xF5, lsl #16
    mov  x2, #1
    bl   _pill
    ADRL x0, Ls_w_shuffle
    ADRL x1, Ls_m_shuffle
    ADRL x8, Lf_bshuf
    bl   Lnw_button
    ADRL x0, Ls_w_clear
    ADRL x1, Ls_m_clear
    ADRL x8, Lf_bclear
    bl   Lnw_button
    mov  x0, x21                          // your words, the players, the results
    mov  x1, #0
    ADRL x8, Lf_info
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_textview
    ADRL x8, _g_nfw_info
    str  x0, [x8]
    LEAVE 32

// Lnw_button(x0 title, x1 selector name, x8 frame) -> the button, in the window (x21)
Lnw_button:
    ENTER 0
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    mov  x2, #0
    mov  x3, x21
    bl   _mk_button
    LEAVE 0

// ---------------------------------------------------------------------------
// Its buttons (the controller's methods: main.s's table)

// - nfTile:(id)sender — a tile's letter onto the end of the word being typed
.globl _nfw_tile
_nfw_tile:
    ENTER 48                              // [96] the tiles  [112] the word (32)
    mov  x0, x2
    MSG0 Ls_tag
    mov  x19, x0
    cmp  x19, #8
    b.hi 9f
    bl   _am_nf_state
    cmp  x0, #3                           // playing
    b.ne 9f
    add  x0, sp, #96
    bl   _am_nf_tiles
    add  x9, sp, #96
    ldrb w20, [x9, x19]
    orr  w20, w20, #0x20
    ADRL x8, _g_nfw_field
    ldr  x0, [x8]
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    mov  x1, x0
    add  x0, sp, #112
    mov  x2, #24
    bl   _strlcpy
    cmp  x0, #20
    b.hs 9f
    add  x9, sp, #112
    strb w20, [x9, x0]
    add  x0, x0, #1
    strb wzr, [x9, x0]
    add  x0, sp, #112
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_nfw_field
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
9:  LEAVE 48

// - nfWord:(id)sender — Enter: the word typed, as if typed in the game room
.globl _nfw_word
_nfw_word:
    ENTER 80                              // [96] the word (64)
    ADRL x8, _g_nfw_field
    ldr  x0, [x8]
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, 9f
    mov  x1, x0
    add  x0, sp, #96
    mov  x2, #64
    bl   _strlcpy
    ldrb w9, [sp, #96]
    cbz  w9, 9f
    ADRL x0, Ls_empty
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_nfw_field
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    bl   _am_nf_room
    tbnz x0, #63, 9f
    add  x1, sp, #96
    bl   _nf_typed
    bl   _nfw_update
9:  LEAVE 80

// - nfStart:(id)sender
.globl _nfw_start
_nfw_start:
    ENTER 0
    bl   _am_nf_room
    tbnz x0, #63, 9f
    ADRL x1, Ls_w_startcmd
    bl   _nf_typed
    bl   _nfw_update
9:  LEAVE 0

// - nfShuffle:(id)sender
.globl _nfw_shuffle
_nfw_shuffle:
    ENTER 0
    bl   _nf_shuffle
    bl   _nfw_update
    LEAVE 0

// - nfClear:(id)sender
.globl _nfw_clear
_nfw_clear:
    ENTER 0
    ADRL x0, Ls_empty
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_nfw_field
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_empty:           .asciz ""
Ls_nl2:             .asciz "\n\n"
Ls_w_title:         .asciz "Ninefold"
Ls_w_ph:            .asciz "Type a word, press Enter"
Ls_w_enter:         .asciz "Enter"
Ls_w_start:         .asciz "Start"
Ls_w_startcmd:      .asciz "start"
Ls_w_shuffle:       .asciz "Shuffle"
Ls_w_clear:         .asciz "Clear"
Ls_w_yours:         .asciz "Your words: "
Ls_w_none:          .asciz "none yet"
Ls_w_players:       .asciz "Players (words this round, points):\n"
Ls_w_lobby_host:    .asciz "Waiting for the people you invited to join. Press Start when they have (more people: Invite\342\200\246 in the game room)."
Ls_w_lobby_guest:   .asciz "You\342\200\231re in. Waiting for the host to start the game."
Ls_m_tile:          .asciz "nfTile:"
Ls_m_word:          .asciz "nfWord:"
Ls_m_start:         .asciz "nfStart:"
Ls_m_shuffle:       .asciz "nfShuffle:"
Ls_m_clear:         .asciz "nfClear:"
Ls_NSApplication:   .asciz "NSApplication"
Ls_NSWindow:        .asciz "NSWindow"
Ls_NSTextField:     .asciz "NSTextField"
Ls_NSColor:         .asciz "NSColor"
Ls_NSAttributedString: .asciz "NSAttributedString"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_orderFrontRegardless: .asciz "orderFrontRegardless"
Ls_orderOut:        .asciz "orderOut:"
Ls_makeFirstResponder: .asciz "makeFirstResponder:"
Ls_setStringValue:  .asciz "setStringValue:"
Ls_stringValue:     .asciz "stringValue"
Ls_UTF8String:      .asciz "UTF8String"
Ls_setHidden:       .asciz "setHidden:"
Ls_setString:       .asciz "setString:"
Ls_whiteColor:      .asciz "whiteColor"
Ls_blackColor:      .asciz "blackColor"
Ls_alloc:           .asciz "alloc"
Ls_initWithStringAttributes: .asciz "initWithString:attributes:"
Ls_setAttributedTitle: .asciz "setAttributedTitle:"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_initWithFrame:   .asciz "initWithFrame:"
Ls_setTitle:        .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_setBackgroundColor: .asciz "setBackgroundColor:"
Ls_center:          .asciz "center"
Ls_contentView:     .asciz "contentView"
Ls_setTag:          .asciz "setTag:"
Ls_tag:             .asciz "tag"
Ls_setPlaceholderString: .asciz "setPlaceholderString:"
Ls_setFont:         .asciz "setFont:"
Ls_setTarget:       .asciz "setTarget:"
Ls_setAction:       .asciz "setAction:"
Ls_addSubview:      .asciz "addSubview:"
