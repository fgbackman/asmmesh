// spinui.s — the SPIN window: set the remote up the way its own app does.
//
//   Profiles along the top: one per colour (up to 9). Double-tap the SPIN to move
//   to the next profile that's in use, and the ring turns that profile's colour.
//   Each profile has a name, a switch, the devices it drives, and a map: for each
//   of the SPIN's 19 gestures, what it does ("Default" is the built-in action).
//   "Run a command…" runs anything you could type in Home ("good night",
//   "TV input HDMI 2"). Every gesture lights its row up as it arrives; in test
//   mode that's all that happens, so you can try the remote safely.
//
// Saved in the defaults as "spin_maps" (one 992-byte record per profile); the
// devices stay in spin.s's groups ("spin_g_<colour>").

.include "macros.inc"

.set NPROF,     9
.set NSLOT,     19
.set PR_SIZE,   992          // [0] in use  [1] name[31]  [32 + slot*48] action, text[47]
.set PR_SLOTS,  32
.set SL_SIZE,   48
.set NACT,      18
.set ACT_CMD,   17           // "Run a command…"
.set MAPS_SIZE, (NPROF * PR_SIZE)

// window geometry (origin bottom left)
.set UW,        900
.set UH,        740

.data
.p2align 3
.globl _g_spin_test
_g_spin_test:   .quad 0      // test mode: gestures light up, nothing runs
_g_sui_win:     .quad 0
_g_sui_prof:    .quad 0      // the profile being edited
_g_sui_name:    .quad 0
_g_sui_enable:  .quad 0
_g_sui_devs:    .quad 0
_g_sui_addpop:  .quad 0
_g_sui_lock:    .quad 0
_g_sui_testsw:  .quad 0
_g_sui_status:  .quad 0
.globl _g_spin_maps
.zerofill __DATA,__bss,_g_spin_maps,8928,4
.zerofill __DATA,__bss,_g_sui_tabs,80,4
.zerofill __DATA,__bss,_g_sui_rows,160,4
.zerofill __DATA,__bss,_g_sui_pops,160,4
.zerofill __DATA,__bss,_g_sui_texts,160,4
.zerofill __DATA,__bss,_g_sui_buf,512,4

.section __DATA,__const
.p2align 3
// gesture code (0..24) -> row (255: not mapped)
Lcode_slot:
    .byte 0, 1, 0, 1, 0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 6, 11, 12, 13, 14, 15, 16, 17, 18, 255, 255
.p2align 3
// what "Default" means for each row
Lslot_default:
    .byte 2, 3, 4, 5, 15, 14, 6, 1, 1, 1, 1, 1, 1, 1, 1, 16, 2, 3, 14
.p2align 3
Lslot_names:
    .quad Lg_cw, Lg_ccw, Lg_up, Lg_down, Lg_left, Lg_right, Lg_press, Lg_pn, Lg_ps
    .quad Lg_pe, Lg_pw, Lg_ln, Lg_ls, Lg_le, Lg_lw, Lg_lc, Lg_scw, Lg_sccw, Lg_dtap
Lact_names:
    .quad La_default, La_nothing, La_brighter, La_dimmer, La_on, La_off, La_toggle
    .quad La_louder, La_quieter, La_mute, La_play, La_pause, La_chup, La_chdown
    .quad La_next, La_prev, La_sos, La_cmd
// action -> _spin_gdo kind (-1: something else)
Lact_kind:
    .quad -1, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, -1, -1, -1, -1

.section __TEXT,__const
.p2align 3
Lc0:        .double 0.0
Lc1:        .double 1.0
Lc_dim:     .double 0.4
Lc_W:       .double 900.0
Lc_H:       .double 740.0
Lc_r16:     .double 16.0
Lc_r8:      .double 8.0
Lc_r14:     .double 14.0
Lc_s26:     .double 26.0
Lc_s13:     .double 13.0
Lc_s12:     .double 12.0
Lc_s11:     .double 11.0
Lc_bw:      .double 2.0
Lf_title:   .double 24.0, 686.0, 420.0, 34.0
Lf_status:  .double 24.0, 662.0, 852.0, 18.0
Lf_left:    .double 24.0, 24.0, 300.0, 560.0
Lf_right:   .double 340.0, 24.0, 536.0, 560.0
// inside the left card
Lf_lname:   .double 16.0, 520.0, 268.0, 16.0
Lf_name:    .double 16.0, 490.0, 268.0, 26.0
Lf_luse:    .double 16.0, 456.0, 200.0, 18.0
Lf_use:     .double 236.0, 452.0, 48.0, 24.0
Lf_ldev:    .double 16.0, 420.0, 268.0, 16.0
Lf_devs:    .double 16.0, 390.0, 268.0, 26.0
Lf_add:     .double 16.0, 356.0, 268.0, 26.0
Lf_help:    .double 16.0, 150.0, 268.0, 190.0
Lf_lon:     .double 16.0, 96.0, 200.0, 18.0
Lf_on:      .double 236.0, 92.0, 48.0, 24.0
Lf_ltest:   .double 16.0, 56.0, 200.0, 18.0
Lf_test:    .double 236.0, 52.0, 48.0, 24.0

.text
.p2align 2

// ---------------------------------------------------------------------------
// Profiles and their maps
// ---------------------------------------------------------------------------

// uint8 *_sui_rec(long i) — profile i's record (leaf)
.globl _sui_rec
_sui_rec:
    ADRL x8, _g_spin_maps
    mov  x9, #PR_SIZE
    madd x0, x0, x9, x8
    ret

// long _sui_enabled(long i) -> 1 if the profile is in use (switched on, or has devices)
.globl _sui_enabled
_sui_enabled:
    ADRL x8, _g_spin_maps
    mov  x9, #PR_SIZE
    madd x8, x0, x9, x8
    ldrb w9, [x8]
    cbnz w9, Lse_yes
    ADRL x8, _g_spin_groups
    lsl  x9, x0, #8
    ldrb w9, [x8, x9]
    cbnz w9, Lse_yes
    mov  x0, #0
    ret
Lse_yes:
    mov  x0, #1
    ret

// id _sui_defaults(void)
_sui_defaults:
    ENTER 0
    CLS  Ls_NSUserDefaults
    MSG0 Ls_standardUserDefaults
    LEAVE 0

// void _sui_load(void) — the saved maps
.globl _sui_load
_sui_load:
    ENTER 0
    ADRL x8, _g_no_persist
    ldr  x9, [x8]
    cbnz x9, Lsl_done
    bl   _sui_defaults
    mov  x19, x0
    ADRL x0, Ls_key_maps
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_dataForKey
    cbz  x0, Lsl_done
    mov  x20, x0
    MSG0 Ls_length
    mov  x9, #MAPS_SIZE
    cmp  x0, x9
    b.ne Lsl_done
    mov  x0, x20
    MSG0 Ls_bytes
    mov  x1, x0
    ADRL x0, _g_spin_maps
    mov  x2, #MAPS_SIZE
    bl   _memcpy
    mov  x19, #0                      // never trust a stored name's terminator
Lsl_term:
    cmp  x19, #NPROF
    b.hs Lsl_done
    mov  x0, x19
    bl   _sui_rec
    strb wzr, [x0, #31]
    mov  x20, #0
Lsl_slot:
    cmp  x20, #NSLOT
    b.hs Lsl_next
    mov  x9, #SL_SIZE
    madd x10, x20, x9, x0
    strb wzr, [x10, #(PR_SLOTS + SL_SIZE - 1)]
    ldrb w11, [x10, #PR_SLOTS]
    cmp  w11, #NACT
    b.lo Lsl_ok
    strb wzr, [x10, #PR_SLOTS]
Lsl_ok:
    add  x20, x20, #1
    b    Lsl_slot
Lsl_next:
    add  x19, x19, #1
    b    Lsl_term
Lsl_done:
    LEAVE 0

// void _sui_save(void)
_sui_save:
    ENTER 0
    ADRL x8, _g_no_persist
    ldr  x9, [x8]
    cbnz x9, Lss_done
    CLS  Ls_NSData
    ADRL x2, _g_spin_maps
    mov  x3, #MAPS_SIZE
    MSG2 Ls_dataWithBytes
    mov  x20, x0
    bl   _sui_defaults
    mov  x19, x0
    ADRL x0, Ls_key_maps
    bl   _nsstr
    mov  x3, x0
    mov  x2, x20
    mov  x0, x19
    MSG2 Ls_setObjectForKey
Lss_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// Gestures
// ---------------------------------------------------------------------------

// long _sui_slot(long code) -> row, or -1 (leaf)
_sui_slot:
    cmp  x0, #25
    b.hs Lsl2_none
    ADRL x8, Lcode_slot
    ldrb w0, [x8, x0]
    cmp  w0, #255
    b.eq Lsl2_none
    ret
Lsl2_none:
    mov  x0, #-1
    ret

// long _sui_seen(long code) -> 1 if test mode swallowed it. Lights its row up.
.globl _sui_seen
_sui_seen:
    ENTER 0
    bl   _sui_slot
    mov  x19, x0
    tbnz x19, #63, Lsn_test
    ADRL x8, _g_sui_win
    ldr  x9, [x8]
    cbz  x9, Lsn_test
    mov  x0, x19
    bl   _sui_flash
    ADRL x8, Lslot_names              // "Last gesture: spin clockwise"
    ldr  x1, [x8, x19, lsl #3]
    ADRL x0, Lf_last
    bl   _sui_status_set
Lsn_test:
    ADRL x8, _g_spin_test
    ldr  x0, [x8]
    LEAVE 0

// void _sui_gesture(long code) — what the current profile says this gesture does
.globl _sui_gesture
_sui_gesture:
    ENTER 0
    bl   _sui_slot
    tbnz x0, #63, Lsg_done
    mov  x19, x0
    ADRL x8, _g_spin_gcur
    ldr  x9, [x8]
    tbz  x9, #63, Lsg_have
    mov  x0, #1                       // none picked yet: the first one in use
    bl   _spin_gnext
Lsg_have:
    ADRL x8, _g_spin_gcur
    ldr  x20, [x8]
    tbnz x20, #63, Lsg_done
    mov  x0, x20
    bl   _sui_rec
    mov  x9, #SL_SIZE
    madd x21, x19, x9, x0
    add  x21, x21, #PR_SLOTS          // this row: action, then text
    ldrb w22, [x21]
    cbnz w22, Lsg_run
    ADRL x8, Lslot_default
    ldrb w22, [x8, x19]
Lsg_run:
    mov  x0, x22
    add  x1, x21, #1
    bl   _sui_exec
Lsg_done:
    LEAVE 0

// void _sui_exec(long action, const char *text) — do it
_sui_exec:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    cmp  x19, #NACT
    b.hs Lsx_done
    cmp  x19, #14
    b.eq Lsx_next
    cmp  x19, #15
    b.eq Lsx_prev
    cmp  x19, #16
    b.eq Lsx_sos
    cmp  x19, #ACT_CMD
    b.eq Lsx_cmd
    ADRL x8, Lact_kind
    ldr  x21, [x8, x19, lsl #3]
    tbnz x21, #63, Lsx_done           // Nothing
    cmp  x19, #2                      // steps (spins, scrolls) are paced
    b.eq Lsx_paced
    cmp  x19, #3
    b.eq Lsx_paced
    cmp  x19, #7
    b.eq Lsx_paced
    cmp  x19, #8
    b.ne Lsx_do
Lsx_paced:
    bl   _spin_throttle
    cbz  x0, Lsx_done
Lsx_do:
    mov  x0, x21
    bl   _spin_gdo
    b    Lsx_done
Lsx_next:
    mov  x0, #1
    bl   _spin_gnext
    bl   _sui_refresh
    b    Lsx_done
Lsx_prev:
    mov  x0, #-1
    bl   _spin_gnext
    bl   _sui_refresh
    b    Lsx_done
Lsx_sos:
    bl   _spin_sos
    b    Lsx_done
Lsx_cmd:
    ldrb w9, [x20]
    cbz  w9, Lsx_done
    mov  x0, x20
    bl   _run_text
Lsx_done:
    LEAVE 0

// void _sui_flash(long slot) — light its row up for a moment
_sui_flash:
    ENTER 0
    ADRL x8, _g_sui_rows
    ldr  x19, [x8, x0, lsl #3]
    cbz  x19, Lsf_done
    mov  x0, x19
    mov  x1, #0x84FF                  // blue, like the app's accent
    movk x1, #0x0A, lsl #16
    LDD  d0, Lc_r8
    bl   _card
    mov  x0, #0
    mov  x1, #0x6500                  // 0.6 s
    movk x1, #0x23C3, lsl #16
    bl   _dispatch_time
    LDGOT x1, __dispatch_main_q
    mov  x2, x19
    ADRL x3, _sui_unflash
    bl   _dispatch_after_f
Lsf_done:
    LEAVE 0

// void _sui_unflash(id row)
_sui_unflash:
    ENTER 0
    mov  x1, #0x2C2E
    movk x1, #0x2C, lsl #16
    LDD  d0, Lc_r8
    bl   _card
    LEAVE 0

// ---------------------------------------------------------------------------
// The window
// ---------------------------------------------------------------------------

// void _sui_target(id control, const char *selname, long tag)
_sui_target:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x19
    MSG1 Ls_setTarget
    mov  x0, x20
    bl   _sel_registerName
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setAction
    mov  x0, x19
    mov  x2, x21
    MSG1 Ls_setTag
    LEAVE 0

// id _sui_make(const char *class, id parent, frame d0-d3) — [[class alloc] initWithFrame:], added
_sui_make:
    ENTER 32
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    mov  x19, x1
    bl   _objc_getClass
    MSG0 Ls_alloc
    mov  x20, x0
    SELX1 Ls_initWithFrame
    mov  x0, x20
    ldp  d0, d1, [sp, #96]
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    mov  x20, x0
    mov  x0, x19
    mov  x2, x20
    MSG1 Ls_addSubview
    mov  x0, x20
    LEAVE 32

// id _sui_field(id parent, frame d0-d3, const char *placeholder, const char *sel, long tag)
_sui_field:
    ENTER 16
    mov  x21, x1
    mov  x22, x2
    mov  x23, x3
    mov  x1, x0
    ADRL x0, Ls_NSTextField
    bl   _sui_make
    mov  x19, x0
    mov  x2, #1                       // rounded
    MSG1 Ls_setBezelStyle
    mov  x0, x21
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setPlaceholderString
    LDD  d0, Lc_s12
    mov  w0, #0
    bl   _font
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setFont
    mov  x0, x19
    MSG0 Ls_cell
    mov  x2, #1                       // also when you click away, not only Return
    MSG1 Ls_setSendsActionOnEndEditing
    mov  x0, x19
    mov  x1, x22
    mov  x2, x23
    bl   _sui_target
    mov  x0, x19
    LEAVE 16

// id _sui_popup(id parent, frame d0-d3, const char *sel, long tag) — filled with the actions
_sui_popup:
    ENTER 32
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    mov  x19, x0
    mov  x21, x1
    mov  x22, x2
    CLS  Ls_NSPopUpButton
    MSG0 Ls_alloc
    mov  x20, x0
    SELX1 Ls_initWithFramePulls
    mov  x0, x20
    ldp  d0, d1, [sp, #96]
    ldp  d2, d3, [sp, #112]
    mov  x2, #0
    bl   _objc_msgSend
    mov  x20, x0
    mov  x0, x19
    mov  x2, x20
    MSG1 Ls_addSubview
    mov  x0, x20
    mov  x1, x21
    mov  x2, x22
    bl   _sui_target
    mov  x0, x20
    LEAVE 32

// id _sui_switch(id parent, frame d0-d3, const char *sel)
_sui_switch:
    ENTER 0
    mov  x21, x1
    mov  x1, x0
    ADRL x0, Ls_NSSwitch
    bl   _sui_make
    mov  x19, x0
    mov  x1, x21
    mov  x2, #0
    bl   _sui_target
    mov  x0, x19
    LEAVE 0

// void _sui_status_set(const char *fmt, const char *arg)
_sui_status_set:
    ENTER 0
    mov  x9, x1
    str  x9, [sp]
    mov  x2, x0
    ADRL x0, _g_sui_buf
    mov  x1, #300
    bl   _snprintf
    ADRL x8, _g_sui_status
    ldr  x19, [x8]
    cbz  x19, Lst_done
    ADRL x0, _g_sui_buf
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setStringValue
Lst_done:
    LEAVE 0

// - (void)showSpin:(id)sender
.globl _sui_show
_sui_show:
    ENTER 0
    ADRL x8, _g_window                // selftest: no windows
    ldr  x9, [x8]
    cbz  x9, Lsw_done
    ADRL x8, _g_sui_win
    ldr  x0, [x8]
    cbnz x0, Lsw_front
    bl   _sui_build
Lsw_front:
    bl   _sui_refresh
    ADRL x8, _g_sui_win
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
Lsw_done:
    LEAVE 0

// void _sui_build(void)
_sui_build:
    ENTER 32
    CLS  Ls_NSWindow
    MSG0 Ls_alloc
    mov  x20, x0
    SELX1 Ls_initWithContentRect
    mov  x0, x20
    LDD  d0, Lc0
    LDD  d1, Lc0
    LDD  d2, Lc_W
    LDD  d3, Lc_H
    mov  x2, #32775                   // titled|closable|miniaturizable|fullSizeContentView
    mov  x3, #2
    mov  x4, #0
    bl   _objc_msgSend
    mov  x20, x0
    ADRL x8, _g_sui_win
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
    mov  x21, x0                      // content

    ADRL x0, Ls_win_title
    mov  x1, #0
    mov  x2, #1
    mov  x3, x21
    ADRL x8, Lf_title
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s26
    bl   _mk_label
    ADRL x0, Ls_empty
    mov  x1, #0
    mov  x2, #0
    mov  x3, x21
    ADRL x8, Lf_status
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s13
    bl   _mk_label
    bl   _dim_label
    ADRL x8, _g_sui_status
    str  x0, [x8]

    // ---- profile tabs ----
    mov  x19, #0
Lsb_tab:
    cmp  x19, #NPROF
    b.hs Lsb_cards
    mov  x9, #96
    mul  x9, x19, x9
    add  x9, x9, #24
    ucvtf d0, x9
    mov  x9, #604
    ucvtf d1, x9
    mov  x9, #88
    ucvtf d2, x9
    mov  x9, #40
    ucvtf d3, x9
    ADRL x0, Ls_empty
    ADRL x1, Ls_m_tab
    mov  x2, #0
    mov  x3, x21
    bl   _mk_button
    mov  x22, x0
    ADRL x8, _g_sui_tabs
    str  x22, [x8, x19, lsl #3]
    mov  x0, x22
    mov  x2, x19
    MSG1 Ls_setTag
    mov  x0, x22
    mov  x2, #1
    MSG1 Ls_setWantsLayer
    add  x19, x19, #1
    b    Lsb_tab

Lsb_cards:
    // ---- left card: this profile ----
    mov  x0, x21
    ADRL x8, Lf_left
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _plain_view
    mov  x22, x0
    mov  x1, #0x2C2E
    movk x1, #0x2C, lsl #16
    LDD  d0, Lc_r16
    bl   _card

    ADRL x0, Ls_l_name
    ADRL x1, Lf_lname
    mov  x2, x22
    bl   _sui_caption
    mov  x0, x22
    ADRL x8, Lf_name
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    ADRL x1, Ls_ph_name
    ADRL x2, Ls_m_name
    mov  x3, #0
    bl   _sui_field
    ADRL x8, _g_sui_name
    str  x0, [x8]

    ADRL x0, Ls_l_use
    ADRL x1, Lf_luse
    mov  x2, x22
    bl   _sui_line
    mov  x0, x22
    ADRL x8, Lf_use
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    ADRL x1, Ls_m_enable
    bl   _sui_switch
    ADRL x8, _g_sui_enable
    str  x0, [x8]

    ADRL x0, Ls_l_devs
    ADRL x1, Lf_ldev
    mov  x2, x22
    bl   _sui_caption
    mov  x0, x22
    ADRL x8, Lf_devs
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    ADRL x1, Ls_ph_devs
    ADRL x2, Ls_m_devs
    mov  x3, #0
    bl   _sui_field
    ADRL x8, _g_sui_devs
    str  x0, [x8]
    mov  x0, x22
    ADRL x8, Lf_add
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    ADRL x1, Ls_m_add
    mov  x2, #0
    bl   _sui_popup
    ADRL x8, _g_sui_addpop
    str  x0, [x8]

    CLS  Ls_NSTextField               // how it works, in a few lines
    mov  x19, x0
    ADRL x0, Ls_help
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_wrappingLabelWithString
    mov  x19, x0
    SELX1 Ls_setFrame
    mov  x0, x19
    ADRL x8, Lf_help
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    LDD  d0, Lc_s12
    mov  w0, #0
    bl   _font
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setFont
    mov  x0, x19
    bl   _dim_label
    mov  x0, x22
    mov  x2, x19
    MSG1 Ls_addSubview

    ADRL x0, Ls_l_on
    ADRL x1, Lf_lon
    mov  x2, x22
    bl   _sui_line
    mov  x0, x22
    ADRL x8, Lf_on
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    ADRL x1, Ls_m_lock
    bl   _sui_switch
    ADRL x8, _g_sui_lock
    str  x0, [x8]
    ADRL x0, Ls_l_test
    ADRL x1, Lf_ltest
    mov  x2, x22
    bl   _sui_line
    mov  x0, x22
    ADRL x8, Lf_test
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    ADRL x1, Ls_m_test
    bl   _sui_switch
    ADRL x8, _g_sui_testsw
    str  x0, [x8]

    // ---- right card: one row per gesture ----
    mov  x0, x21
    ADRL x8, Lf_right
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _plain_view
    mov  x22, x0
    mov  x1, #0x2C2E
    movk x1, #0x2C, lsl #16
    LDD  d0, Lc_r16
    bl   _card
    mov  x19, #0
Lsb_row:
    cmp  x19, #NSLOT
    b.hs Lsb_done
    mov  x0, x19
    mov  x1, x22
    bl   _sui_row
    add  x19, x19, #1
    b    Lsb_row
Lsb_done:
    LEAVE 32

// void _sui_caption(const char *text, const double *frame, id parent) — small bold grey
_sui_caption:
    ENTER 0
    mov  x3, x2
    ldp  d0, d1, [x1]
    ldp  d2, d3, [x1, #16]
    mov  x1, #0
    mov  x2, #1
    LDD  d4, Lc_s11
    bl   _mk_label
    bl   _dim_label
    LEAVE 0

// void _sui_line(const char *text, const double *frame, id parent) — a 13-point label
_sui_line:
    ENTER 0
    mov  x3, x2
    ldp  d0, d1, [x1]
    ldp  d2, d3, [x1, #16]
    mov  x1, #0
    mov  x2, #0
    LDD  d4, Lc_s13
    bl   _mk_label
    LEAVE 0

// void _sui_row(long slot, id card) — name, what it does, and a command for "Run a command…"
_sui_row:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    mov  x9, #28
    mul  x9, x19, x9
    mov  x10, #518
    sub  x9, x10, x9
    ucvtf d0, x9                      // this row's y
    str  d0, [sp, #96]
    ldr  d1, [sp, #96]                // the row's background (it lights up)
    mov  x9, #8
    ucvtf d0, x9
    mov  x9, #520
    ucvtf d2, x9
    mov  x9, #28
    ucvtf d3, x9
    mov  x0, x20
    bl   _plain_view
    ADRL x8, _g_sui_rows
    str  x0, [x8, x19, lsl #3]
    mov  x1, #0x2C2E
    movk x1, #0x2C, lsl #16
    LDD  d0, Lc_r8
    bl   _card

    ADRL x8, Lslot_names
    ldr  x0, [x8, x19, lsl #3]
    mov  x1, #0
    mov  x2, #0
    mov  x3, x20
    mov  x9, #16
    ucvtf d0, x9
    ldr  d1, [sp, #96]
    mov  x9, #5
    ucvtf d4, x9
    fadd d1, d1, d4
    mov  x9, #160
    ucvtf d2, x9
    mov  x9, #18
    ucvtf d3, x9
    LDD  d4, Lc_s13
    bl   _mk_label

    mov  x9, #180
    ucvtf d0, x9
    ldr  d1, [sp, #96]
    mov  x9, #2
    ucvtf d4, x9
    fadd d1, d1, d4
    mov  x9, #170
    ucvtf d2, x9
    mov  x9, #24
    ucvtf d3, x9
    mov  x0, x20
    ADRL x1, Ls_m_action
    mov  x2, x19
    bl   _sui_popup
    mov  x21, x0
    ADRL x8, _g_sui_pops
    str  x21, [x8, x19, lsl #3]
    mov  x22, #0
Lsr_item:
    cmp  x22, #NACT
    b.hs Lsr_text
    ADRL x8, Lact_names
    ldr  x0, [x8, x22, lsl #3]
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_addItemWithTitle
    add  x22, x22, #1
    b    Lsr_item
Lsr_text:
    mov  x9, #356
    ucvtf d0, x9
    ldr  d1, [sp, #96]
    mov  x9, #3
    ucvtf d4, x9
    fadd d1, d1, d4
    mov  x9, #164
    ucvtf d2, x9
    mov  x9, #22
    ucvtf d3, x9
    mov  x0, x20
    ADRL x1, Ls_ph_cmd
    ADRL x2, Ls_m_text
    mov  x3, x19
    bl   _sui_field
    ADRL x8, _g_sui_texts
    str  x0, [x8, x19, lsl #3]
    LEAVE 32

// void _sui_refresh(void) — show the edited profile, the tabs and the switches
.globl _sui_refresh
_sui_refresh:
    ENTER 64                          // [96] tab title
    ADRL x8, _g_sui_win
    ldr  x9, [x8]
    cbz  x9, Lsr2_done
    ADRL x8, _g_sui_prof
    ldr  x19, [x8]

    // tabs: name (or colour), the colour, a ring round the one being edited
    mov  x20, #0
Lsr2_tab:
    cmp  x20, #NPROF
    b.hs Lsr2_prof
    ADRL x8, _g_sui_tabs
    ldr  x21, [x8, x20, lsl #3]
    mov  x0, x20
    bl   _sui_title
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setTitle
    mov  x0, x20
    bl   _spin_colour
    mov  x22, x1
    and  x22, x22, #0xFFFFFF
    mov  x2, #0                       // light colours get black text
    cmp  x20, #3
    b.lo Lsr2_pill
    cmp  x20, #5
    b.ls Lsr2_dark
    cmp  x20, #8
    b.ne Lsr2_pill
Lsr2_dark:
    mov  x2, #1
Lsr2_pill:
    mov  x0, x21
    mov  x1, x22
    bl   _pill
    SELX1 Ls_setAlphaValue            // profiles not in use are faded
    mov  x22, x1
    mov  x0, x20
    bl   _sui_enabled
    LDD  d0, Lc1
    cbnz x0, Lsr2_alpha
    LDD  d0, Lc_dim
Lsr2_alpha:
    mov  x0, x21
    mov  x1, x22
    bl   _objc_msgSend
    mov  x0, x21
    MSG0 Ls_layer
    mov  x22, x0
    cbz  x22, Lsr2_next
    SELX1 Ls_setBorderWidth
    mov  x0, x22
    LDD  d0, Lc0
    cmp  x20, x19
    b.ne Lsr2_bw
    LDD  d0, Lc_bw
Lsr2_bw:
    bl   _objc_msgSend
    CLS  Ls_NSColor
    MSG0 Ls_whiteColor
    MSG0 Ls_CGColor
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setBorderColor
    SELX1 Ls_setCornerRadius
    mov  x0, x22
    LDD  d0, Lc_r14
    bl   _objc_msgSend
Lsr2_next:
    add  x20, x20, #1
    b    Lsr2_tab

Lsr2_prof:
    mov  x0, x19
    bl   _sui_rec
    mov  x20, x0
    add  x0, x20, #1                  // name
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_sui_name
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    mov  x0, x19                      // in use?
    bl   _sui_enabled
    mov  x2, x0
    ADRL x8, _g_sui_enable
    ldr  x0, [x8]
    MSG1 Ls_setState
    ADRL x8, _g_spin_groups           // devices
    add  x0, x8, x19, lsl #8
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_sui_devs
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    mov  x21, #0                      // the gesture map
Lsr2_slot:
    cmp  x21, #NSLOT
    b.hs Lsr2_devpop
    mov  x9, #SL_SIZE
    madd x22, x21, x9, x20
    add  x22, x22, #PR_SLOTS
    ldrb w2, [x22]
    ADRL x8, _g_sui_pops
    ldr  x0, [x8, x21, lsl #3]
    MSG1 Ls_selectItemAtIndex
    add  x0, x22, #1
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_sui_texts
    ldr  x0, [x8, x21, lsl #3]
    MSG1 Ls_setStringValue
    add  x21, x21, #1
    b    Lsr2_slot

Lsr2_devpop:                          // "Add a device…" and every device you can use
    ADRL x8, _g_sui_addpop
    ldr  x21, [x8]
    mov  x0, x21
    MSG0 Ls_removeAllItems
    ADRL x0, Ls_add_dev
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_addItemWithTitle
    bl   _home_dev_count
    mov  x22, x0
    mov  x23, #0
Lsr2_dev:
    cmp  x23, x22
    b.hs Lsr2_switches
    mov  x0, x23
    bl   _home_dev_nth
    tbnz x0, #63, Lsr2_dnext
    ADRL x8, _g_devs
    add  x0, x8, x0, lsl #DEV_SHIFT
    add  x0, x0, #D_NAME
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_addItemWithTitle
Lsr2_dnext:
    add  x23, x23, #1
    b    Lsr2_dev

Lsr2_switches:
    ADRL x8, _g_spin_lock             // "Remote on" is the lock, the other way round
    ldr  x9, [x8]
    cmp  x9, #0
    cset x2, eq
    ADRL x8, _g_sui_lock
    ldr  x0, [x8]
    MSG1 Ls_setState
    ADRL x8, _g_spin_test
    ldr  x2, [x8]
    ADRL x8, _g_sui_testsw
    ldr  x0, [x8]
    MSG1 Ls_setState
    bl   _sui_status_now
Lsr2_done:
    LEAVE 64

// const char *_sui_title(long i) -> its name, or its colour (capitalised) in _g_sui_buf+400
_sui_title:
    ENTER 0
    mov  x19, x0
    bl   _sui_rec
    ldrb w9, [x0, #1]
    cbz  w9, Lti_colour
    add  x0, x0, #1
    LEAVE 0
Lti_colour:
    mov  x0, x19
    bl   _spin_colour
    mov  x1, x0
    ADRL x0, _g_sui_buf
    add  x0, x0, #400
    mov  x2, #32
    bl   _strlcpy
    ADRL x0, _g_sui_buf
    add  x0, x0, #400
    ldrb w9, [x0]
    sub  w9, w9, #0x20
    strb w9, [x0]
    LEAVE 0

// void _sui_status_now(void) — linked? which profile? locked? test mode?
_sui_status_now:
    ENTER 0
    ADRL x8, _g_spin_test
    ldr  x9, [x8]
    cbz  x9, Lsn2_lock
    ADRL x0, Lf_s_test
    ADRL x1, Ls_empty
    bl   _sui_status_set
    LEAVE 0
Lsn2_lock:
    ADRL x8, _g_spin_lock
    ldr  x9, [x8]
    cbz  x9, Lsn2_link
    ADRL x0, Lf_s_locked
    ADRL x1, Ls_empty
    bl   _sui_status_set
    LEAVE 0
Lsn2_link:
    ADRL x8, _g_spin_ready
    ldr  x9, [x8]
    ADRL x19, Lf_s_linked
    ADRL x8, Lf_s_unlinked
    cmp  x9, #0
    csel x19, x8, x19, eq
    ADRL x8, _g_spin_gcur
    ldr  x0, [x8]
    ADRL x1, Ls_none
    tbnz x0, #63, Lsn2_say
    bl   _sui_title
    mov  x1, x0
Lsn2_say:
    mov  x0, x19
    bl   _sui_status_set
    LEAVE 0

// ---------------------------------------------------------------------------
// What the controls do
// ---------------------------------------------------------------------------

// - spinTab: — edit that profile (and drive it, if it is in use)
.globl _sui_tab
_sui_tab:
    ENTER 0
    mov  x0, x2
    MSG0 Ls_tag
    cmp  x0, #NPROF
    b.hs Lstb_done
    ADRL x8, _g_sui_prof
    str  x0, [x8]
    mov  x19, x0
    bl   _sui_enabled
    cbz  x0, Lstb_show
    mov  x0, x19
    bl   _spin_gselect
Lstb_show:
    bl   _sui_refresh
Lstb_done:
    LEAVE 0

// - spinName:
.globl _sui_name
_sui_name:
    ENTER 0
    mov  x0, x2
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, Lsnm_done
    mov  x19, x0
    ADRL x8, _g_sui_prof
    ldr  x0, [x8]
    bl   _sui_rec
    add  x0, x0, #1
    mov  x1, x19
    mov  x2, #31
    bl   _text_copy_trim
    bl   _sui_save
    bl   _sui_refresh
Lsnm_done:
    LEAVE 0

// - spinEnable:
.globl _sui_enable
_sui_enable:
    ENTER 0
    mov  x0, x2
    MSG0 Ls_state
    cmp  x0, #0
    cset x20, ne
    ADRL x8, _g_sui_prof
    ldr  x19, [x8]
    mov  x0, x19
    bl   _sui_rec
    strb w20, [x0]
    cbnz x20, Lsen_on
    ADRL x8, _g_spin_groups           // off: its devices go too
    add  x0, x8, x19, lsl #8
    ldrb w9, [x0]
    cbz  w9, Lsen_off
    mov  x0, x19
    bl   _spin_colour
    str  x0, [sp]
    ADRL x0, _g_sui_buf
    mov  x1, #300
    ADRL x2, Lf_clear
    bl   _snprintf
    mov  x0, #0
    ADRL x1, _g_sui_buf
    ADRL x2, _g_sui_buf
    bl   _h_spin_group
Lsen_off:
    ADRL x8, _g_spin_gcur             // it was the one driving: move on
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne Lsen_save
    mov  x9, #-1
    str  x9, [x8]
    mov  x0, #1
    bl   _spin_gnext
    b    Lsen_save
Lsen_on:
    mov  x0, x19
    bl   _spin_gselect
Lsen_save:
    bl   _sui_save
    bl   _sui_refresh
    LEAVE 0

// - spinDevices: — "Kitchen lamp, Desk lamp" (checked and saved by spin.s)
.globl _sui_devs
_sui_devs:
    ENTER 0
    mov  x0, x2
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, Lsd_done
    bl   _sui_apply_devs
Lsd_done:
    LEAVE 0

// void _sui_apply_devs(const char *names)
_sui_apply_devs:
    ENTER 0
    mov  x20, x0
    ADRL x8, _g_sui_prof
    ldr  x19, [x8]
    mov  x0, x19
    bl   _spin_colour
    str  x0, [sp]
    str  x20, [sp, #8]
    ADRL x0, _g_sui_buf
    mov  x1, #300
    ADRL x2, Lf_group
    ldrb w9, [x20]
    cbnz w9, Lsad_fmt
    ADRL x2, Lf_clear
Lsad_fmt:
    bl   _snprintf
    mov  x0, #0
    ADRL x1, _g_sui_buf
    ADRL x2, _g_sui_buf
    bl   _h_spin_group
    ADRL x8, _g_spin_groups           // devices now: the profile is in use
    add  x0, x8, x19, lsl #8
    ldrb w9, [x0]
    cmp  w9, #0
    cset x20, ne
    mov  x0, x19
    bl   _sui_rec
    ldrb w9, [x0]
    orr  w9, w9, w20
    strb w9, [x0]
    bl   _sui_save
    bl   _sui_refresh
    LEAVE 0

// - spinAddDevice: — the pop-up adds a device to the list
.globl _sui_add
_sui_add:
    ENTER 0
    mov  x19, x2
    mov  x0, x19
    MSG0 Ls_indexOfSelectedItem
    cmp  x0, #1
    b.lt Lsa_done
    mov  x0, x19
    MSG0 Ls_titleOfSelectedItem
    MSG0 Ls_UTF8String
    cbz  x0, Lsa_done
    mov  x20, x0
    ADRL x8, _g_sui_prof
    ldr  x9, [x8]
    ADRL x8, _g_spin_groups
    add  x1, x8, x9, lsl #8
    ADRL x0, _g_sui_buf
    add  x0, x0, #320
    mov  x2, #190
    bl   _strlcpy
    ADRL x0, _g_sui_buf
    add  x0, x0, #320
    ldrb w9, [x0]
    cbz  w9, Lsa_name
    ADRL x1, Ls_comma
    mov  x2, #190
    bl   _strlcat
Lsa_name:
    ADRL x0, _g_sui_buf
    add  x0, x0, #320
    mov  x1, x20
    mov  x2, #190
    bl   _strlcat
    ADRL x0, _g_sui_buf
    add  x0, x0, #320
    bl   _sui_apply_devs
Lsa_done:
    LEAVE 0

// - spinAction: — a gesture's pop-up
.globl _sui_action
_sui_action:
    ENTER 0
    mov  x19, x2
    mov  x0, x19
    MSG0 Ls_tag
    cmp  x0, #NSLOT
    b.hs Lsac_done
    mov  x20, x0
    mov  x0, x19
    MSG0 Ls_indexOfSelectedItem
    cmp  x0, #NACT
    b.hs Lsac_done
    mov  x21, x0
    ADRL x8, _g_sui_prof
    ldr  x0, [x8]
    bl   _sui_rec
    mov  x9, #SL_SIZE
    madd x0, x20, x9, x0
    strb w21, [x0, #PR_SLOTS]
    bl   _sui_save
Lsac_done:
    LEAVE 0

// - spinText: — the command for "Run a command…" (typing one picks that action)
.globl _sui_text
_sui_text:
    ENTER 0
    mov  x19, x2
    mov  x0, x19
    MSG0 Ls_tag
    cmp  x0, #NSLOT
    b.hs Lstx_done
    mov  x20, x0
    mov  x0, x19
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, Lstx_done
    mov  x21, x0
    ADRL x8, _g_sui_prof
    ldr  x0, [x8]
    bl   _sui_rec
    mov  x9, #SL_SIZE
    madd x22, x20, x9, x0
    add  x22, x22, #PR_SLOTS
    add  x0, x22, #1
    mov  x1, x21
    mov  x2, #(SL_SIZE - 1)
    bl   _text_copy_trim
    cbz  x0, Lstx_save
    mov  w9, #ACT_CMD
    strb w9, [x22]
Lstx_save:
    bl   _sui_save
    bl   _sui_refresh
Lstx_done:
    LEAVE 0

// - spinLock: — "Remote on"
.globl _sui_lock
_sui_lock:
    ENTER 0
    mov  x0, x2
    MSG0 Ls_state
    cmp  x0, #0
    cset x0, eq                       // off = locked
    mov  x1, #0
    mov  x2, #0
    bl   _h_spin_lock_arg
    bl   _sui_status_now
    LEAVE 0

// - spinTest: — test mode
.globl _sui_test
_sui_test:
    ENTER 0
    mov  x0, x2
    MSG0 Ls_state
    cmp  x0, #0
    cset x9, ne
    ADRL x8, _g_spin_test
    str  x9, [x8]
    bl   _sui_status_now
    LEAVE 0

// void _h_spin_lock_arg(long locked) — the lock, as "spin off" / "spin on" set it
_h_spin_lock_arg:
    ENTER 0
    bl   _h_spin_lock
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_win_title:   .asciz "SPIN remote"
Ls_empty:       .asciz ""
Ls_none:        .asciz "none"
Ls_comma:       .asciz ", "
Ls_key_maps:    .asciz "spin_maps"
Lf_group:       .asciz "%s %s"
Lf_clear:       .asciz "%s clear"
Lf_last:        .asciz "Last gesture: %s"
Lf_s_linked:    .asciz "\360\237\237\242 SPIN linked  \302\267  driving: %s  \302\267  double-tap the remote to switch profile"
Lf_s_unlinked:  .asciz "\342\232\252\357\270\217 SPIN not linked \342\200\224 press the top of the remote to wake it  \302\267  driving: %s"
Lf_s_locked:    .asciz "\360\237\224\222 The remote is locked \342\200\224 switch \342\200\234Remote on\342\200\235 to use it (long-press SOS still works)%s"
Lf_s_test:      .asciz "\360\237\247\252 Test mode: every gesture lights its row up, and nothing happens%s"
Ls_l_name:      .asciz "PROFILE NAME"
Ls_ph_name:     .asciz "Living room"
Ls_l_use:       .asciz "Use this profile"
Ls_l_devs:      .asciz "DEVICES IT CONTROLS"
Ls_ph_devs:     .asciz "Kitchen lamp, Desk lamp"
Ls_add_dev:     .asciz "Add a device\342\200\246"
Ls_ph_cmd:      .asciz "a command, e.g. good night"
Ls_l_on:        .asciz "Remote on"
Ls_l_test:      .asciz "Test mode"
Ls_help:        .asciz "Double-tap the SPIN to move to the next profile in use \342\200\224 the ring turns its colour.\n\nOn the right, choose what each gesture does. \342\200\234Default\342\200\235 is the built-in action. \342\200\234Run a command\342\200\246\342\200\235 runs anything you could type in Home, like \342\200\234good night\342\200\235 or \342\200\234TV input HDMI 2\342\200\235.\n\nTest mode lets you try the remote: rows light up and nothing happens."
Ls_m_tab:       .asciz "spinTab:"
Ls_m_name:      .asciz "spinName:"
Ls_m_enable:    .asciz "spinEnable:"
Ls_m_devs:      .asciz "spinDevices:"
Ls_m_add:       .asciz "spinAddDevice:"
Ls_m_action:    .asciz "spinAction:"
Ls_m_text:      .asciz "spinText:"
Ls_m_lock:      .asciz "spinLock:"
Ls_m_test:      .asciz "spinTest:"

Lg_cw:      .asciz "Spin clockwise"
Lg_ccw:     .asciz "Spin counter-clockwise"
Lg_up:      .asciz "Swipe up"
Lg_down:    .asciz "Swipe down"
Lg_left:    .asciz "Swipe left"
Lg_right:   .asciz "Swipe right"
Lg_press:   .asciz "Press the top"
Lg_pn:      .asciz "Press north"
Lg_ps:      .asciz "Press south"
Lg_pe:      .asciz "Press east"
Lg_pw:      .asciz "Press west"
Lg_ln:      .asciz "Long-press north"
Lg_ls:      .asciz "Long-press south"
Lg_le:      .asciz "Long-press east"
Lg_lw:      .asciz "Long-press west"
Lg_lc:      .asciz "Long-press the top"
Lg_scw:     .asciz "Touch-scroll clockwise"
Lg_sccw:    .asciz "Touch-scroll back"
Lg_dtap:    .asciz "Double-tap"

La_default: .asciz "Default"
La_nothing: .asciz "Nothing"
La_brighter: .asciz "Brighter / louder"
La_dimmer:  .asciz "Dimmer / quieter"
La_on:      .asciz "Turn on"
La_off:     .asciz "Turn off"
La_toggle:  .asciz "On / off"
La_louder:  .asciz "Louder"
La_quieter: .asciz "Quieter"
La_mute:    .asciz "Mute"
La_play:    .asciz "Play"
La_pause:   .asciz "Pause"
La_chup:    .asciz "Channel up"
La_chdown:  .asciz "Channel down"
La_next:    .asciz "Next profile"
La_prev:    .asciz "Previous profile"
La_sos:     .asciz "SOS"
La_cmd:     .asciz "Run a command\342\200\246"

Ls_NSUserDefaults:      .asciz "NSUserDefaults"
Ls_standardUserDefaults: .asciz "standardUserDefaults"
Ls_dataForKey:          .asciz "dataForKey:"
Ls_setObjectForKey:     .asciz "setObject:forKey:"
Ls_NSData:              .asciz "NSData"
Ls_dataWithBytes:       .asciz "dataWithBytes:length:"
Ls_length:              .asciz "length"
Ls_bytes:               .asciz "bytes"
Ls_NSWindow:            .asciz "NSWindow"
Ls_NSTextField:         .asciz "NSTextField"
Ls_NSPopUpButton:       .asciz "NSPopUpButton"
Ls_NSSwitch:            .asciz "NSSwitch"
Ls_NSColor:             .asciz "NSColor"
Ls_NSApplication:       .asciz "NSApplication"
Ls_alloc:               .asciz "alloc"
Ls_initWithFrame:       .asciz "initWithFrame:"
Ls_initWithFramePulls:  .asciz "initWithFrame:pullsDown:"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_addSubview:          .asciz "addSubview:"
Ls_setTitle:            .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_setTitlebarAppearsTransparent: .asciz "setTitlebarAppearsTransparent:"
Ls_setTitleVisibility:  .asciz "setTitleVisibility:"
Ls_setBackgroundColor:  .asciz "setBackgroundColor:"
Ls_center:              .asciz "center"
Ls_contentView:         .asciz "contentView"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_sharedApplication:   .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_setTarget:           .asciz "setTarget:"
Ls_setAction:           .asciz "setAction:"
Ls_setTag:              .asciz "setTag:"
Ls_tag:                 .asciz "tag"
Ls_state:               .asciz "state"
Ls_setState:            .asciz "setState:"
Ls_setBezelStyle:       .asciz "setBezelStyle:"
Ls_setPlaceholderString: .asciz "setPlaceholderString:"
Ls_setFont:             .asciz "setFont:"
Ls_cell:                .asciz "cell"
Ls_setSendsActionOnEndEditing: .asciz "setSendsActionOnEndEditing:"
Ls_setStringValue:      .asciz "setStringValue:"
Ls_stringValue:         .asciz "stringValue"
Ls_UTF8String:          .asciz "UTF8String"
Ls_wrappingLabelWithString: .asciz "wrappingLabelWithString:"
Ls_setFrame:            .asciz "setFrame:"
Ls_setWantsLayer:       .asciz "setWantsLayer:"
Ls_layer:               .asciz "layer"
Ls_setBorderWidth:      .asciz "setBorderWidth:"
Ls_setBorderColor:      .asciz "setBorderColor:"
Ls_setCornerRadius:     .asciz "setCornerRadius:"
Ls_whiteColor:          .asciz "whiteColor"
Ls_CGColor:             .asciz "CGColor"
Ls_setAlphaValue:       .asciz "setAlphaValue:"
Ls_addItemWithTitle:    .asciz "addItemWithTitle:"
Ls_removeAllItems:      .asciz "removeAllItems"
Ls_selectItemAtIndex:   .asciz "selectItemAtIndex:"
Ls_indexOfSelectedItem: .asciz "indexOfSelectedItem"
Ls_titleOfSelectedItem: .asciz "titleOfSelectedItem"
