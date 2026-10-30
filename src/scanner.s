// scanner.s — the Mesh Scanner window and the app's heartbeat timer.
//
//   left:  AMRadarView, an NSView subclass whose drawRect: is written here.
//          Rings and a rotating sweep; every node on the mesh is a dot.
//          Green dots are in direct Bluetooth range, placed by signal
//          strength (closer to the centre = stronger). Amber dots are reached
//          through other Macs, placed further out the more hops away they are.
//          Grey = not heard from for a minute. Angle comes from the node id,
//          so each Mac keeps its own bearing.
//   right: a table of everything around: Macs on the mesh, Bluetooth LE
//          devices (maker, type, services, pairing state), classic Bluetooth
//          devices paired with this Mac, and devices on the network (Bonjour
//          and UPnP), each with what it says about itself.
//   below: details of the selected row, and Connect & Pair / Set Up /
//          Bluetooth Settings... / Look Again.
//
// The timer ticks 10 times a second: it redraws the radar while the scanner is
// open; once a second it reads RSSI from linked Macs and refreshes the lists;
// every 15 seconds it sends a HELLO so everyone knows we are still here.

.include "macros.inc"

// ---------------------------------------------------------------------------
.data
.p2align 3
.globl _g_scan_table
_g_scan_table:    .quad 0
_g_scan_window:   .quad 0
_g_radar:         .quad 0
_g_scan_details:  .quad 0
.zerofill __DATA,__bss,_g_scan_note,320,4
.globl _g_tick
_g_tick:          .quad 0

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lc_zero:     .double 0.0
Lc_half:     .double 0.5
Lc_one:      .double 1.0
Lc_2:        .double 2.0
Lc_5:        .double 5.0
Lc_3:        .double 3.0
Lc_6:        .double 6.0
Lc_8:        .double 8.0
Lc_9:        .double 9.0
Lc_35:       .double 35.0
Lc_60:       .double 60.0
Lc_018:      .double 0.18
Lc_052:      .double 0.52
Lc_045:      .double 0.45
Lc_072:      .double 0.72
Lc_008:      .double 0.08
Lc_094:      .double 0.94
Lc_tick:     .double 0.1
Lc_deg2rad:  .double 0.017453292519943295
Lc_ang:      .double 0.00009587379924285257     // 2*pi / 65536
Lc_q:        .double 0.25
Lring_frac:  .double 0.2018498, 0.4036996, 0.6982901, 1.0
// colours: r, g, b, a
Lk_bg:       .double 0.02, 0.08, 0.06, 1.0
Lk_ring:     .double 0.20, 0.90, 0.50, 0.30
Lk_wedge:    .double 0.20, 1.00, 0.50, 0.16
Lk_edge:     .double 0.30, 1.00, 0.60, 0.85
Lk_near:     .double 0.35, 1.00, 0.55, 1.0
Lk_far:      .double 1.00, 0.75, 0.25, 1.0
Lk_away:     .double 0.60, 0.60, 0.60, 0.6
Lk_you:      .double 0.85, 1.00, 0.90, 1.0
Lk_ble:      .double 0.40, 0.70, 1.00, 0.85
// scanner window
Lf_swin:     .double 0.0, 0.0, 1080.0, 640.0
Lf_radar:    .double 20.0, 210.0, 410.0, 410.0
Lf_legend:   .double 20.0, 186.0, 420.0, 18.0
Lf_stable:   .double 450.0, 186.0, 614.0, 440.0
Lf_details:  .double 20.0, 52.0, 1044.0, 124.0
Lf_b_pair:   .double 16.0, 12.0, 160.0, 30.0
Lf_b_setup:  .double 180.0, 12.0, 110.0, 30.0
Lf_b_bt:     .double 294.0, 12.0, 190.0, 30.0
Lf_b_again:  .double 488.0, 12.0, 120.0, 30.0
Lc_w_name:   .double 170.0
Lc_w_kind:   .double 150.0
Lc_w_sig:    .double 70.0
Lc_w_seen:   .double 110.0
Lc_w_det:    .double 300.0
Lc_12:       .double 12.0
Lc_11:       .double 11.0

// ---------------------------------------------------------------------------
.text
.p2align 2

// ---------------------------------------------------------------------------
// void _make_radar_class(void) — NSView subclass AMRadarView with drawRect:
// ---------------------------------------------------------------------------
.globl _make_radar_class
_make_radar_class:
    ENTER 0
    CLS  Ls_NSView
    ADRL x1, Ls_radar_name
    mov  x2, #0
    bl   _objc_allocateClassPair
    mov  x19, x0
    ADRL x0, Ls_drawRect
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    ADRL x2, _radar_draw
    ADRL x3, Ls_ty_draw
    bl   _class_addMethod
    mov  x0, x19
    bl   _objc_registerClassPair
    LEAVE 0

// ---------------------------------------------------------------------------
// void _start_timer(void) — 10 Hz heartbeat aimed at the controller's tick:
// ---------------------------------------------------------------------------
.globl _start_timer
_start_timer:
    ENTER 0
    ADRL x0, Ls_tick
    bl   _sel_registerName
    mov  x20, x0
    CLS  Ls_NSTimer
    mov  x19, x0
    SELX1 Ls_scheduledTimer
    mov  x0, x19
    LDD  d0, Lc_tick
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x3, x20
    mov  x4, #0
    mov  x5, #1
    bl   _objc_msgSend
    LEAVE 0

// - (void)tick:(NSTimer *)t
.globl _ui_tick
_ui_tick:
    ENTER 0
    ADRL x8, _g_tick
    ldr  x19, [x8]
    add  x19, x19, #1
    str  x19, [x8]
    ADRL x8, _g_scan_window
    ldr  x0, [x8]
    cbz  x0, Ltk_second
    MSG0 Ls_isVisible
    tst  w0, #0xff
    b.eq Ltk_second
    ADRL x8, _g_radar
    ldr  x0, [x8]
    mov  x2, #1
    MSG1 Ls_setNeedsDisplay
Ltk_second:
    bl   _voice_tick
    bl   _udp_poll
    mov  x9, #10
    udiv x20, x19, x9
    msub x10, x20, x9, x19
    cbnz x10, Ltk_hello
    bl   _ble_read_rssi_all
    bl   _ui_lists_changed
    bl   _alerts_tick                 // weather alerts, a waiting SOS
    mov  x0, x20
    bl   _sens_tick                   // the hourly low-battery check
    mov  x0, x20                      // seconds since launch
    bl   _hue_tick
    mov  x0, x20
    bl   _udp_tick
    bl   _near_tick
    bl   _scanner_update_details
    mov  x0, x20
    bl   _rules_tick                  // schedules, rules, sharing what we hear
    bl   _bc_tick                     // bitchat: announce, forget people gone quiet
Ltk_hello:
    mov  x9, #150
    udiv x10, x19, x9
    msub x10, x10, x9, x19
    cmp  x10, #20                     // first HELLO 2 s after launch, then every 15 s
    b.ne Ltk_done
    bl   _mesh_send_hello
Ltk_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// - (void)showScanner:(id)sender
// ---------------------------------------------------------------------------
.globl _scanner_show
_scanner_show:
    ENTER 0
    ADRL x8, _g_scan_window
    ldr  x0, [x8]
    cbnz x0, Lss_show
    bl   _build_scanner
Lss_show:
    bl   _bt_refresh
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    ADRL x8, _g_scan_window
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    bl   _ui_lists_changed
    LEAVE 0

_build_scanner:
    ENTER 0
    CLS  Ls_NSWindow
    MSG0 Ls_alloc
    mov  x19, x0
    SELX1 Ls_initWithContentRect
    mov  x0, x19
    ADRL x8, Lf_swin
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    mov  x2, #15
    mov  x3, #2
    mov  x4, #0
    bl   _objc_msgSend
    mov  x19, x0
    ADRL x8, _g_scan_window
    str  x19, [x8]
    ADRL x0, Ls_scan_title
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setTitle
    mov  x0, x19
    mov  x2, #0
    MSG1 Ls_setReleasedWhenClosed
    mov  x0, x19
    MSG0 Ls_center
    mov  x0, x19
    MSG0 Ls_contentView
    mov  x20, x0                      // content

    CLS  Ls_radar_name
    MSG0 Ls_alloc
    mov  x21, x0
    SELX1 Ls_initWithFrame
    mov  x0, x21
    ADRL x8, Lf_radar
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x21, x0
    ADRL x8, _g_radar
    str  x21, [x8]
    mov  x0, x21
    mov  x2, #8                       // MinYMargin: stays at the top
    MSG1 Ls_setAutoresizingMask
    mov  x0, x20
    mov  x2, x21
    MSG1 Ls_addSubview

    ADRL x0, Ls_legend
    mov  x1, #32
    mov  x2, #0
    mov  x3, x20
    ADRL x8, Lf_legend
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_11
    bl   _mk_label
    mov  x19, x0
    mov  x2, #8
    MSG1 Ls_setAutoresizingMask
    mov  x0, x19
    bl   _dim_label

    mov  x0, #18                      // WidthSizable | HeightSizable
    mov  x1, #1                       // with column headers
    mov  x2, x20
    ADRL x8, Lf_stable
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_table
    mov  x21, x0
    ADRL x8, _g_scan_table
    str  x21, [x8]
    mov  x0, x21
    ADRL x1, Ls_c_name
    ADRL x2, Ls_h_name
    LDD  d0, Lc_w_name
    bl   _add_col
    mov  x0, x21
    ADRL x1, Ls_c_kind
    ADRL x2, Ls_h_kind
    LDD  d0, Lc_w_kind
    bl   _add_col
    mov  x0, x21
    ADRL x1, Ls_c_sig
    ADRL x2, Ls_h_sig
    LDD  d0, Lc_w_sig
    bl   _add_col
    mov  x0, x21
    ADRL x1, Ls_c_seen
    ADRL x2, Ls_h_seen
    LDD  d0, Lc_w_seen
    bl   _add_col
    mov  x0, x21
    ADRL x1, Ls_c_det
    ADRL x2, Ls_h_det
    LDD  d0, Lc_w_det
    bl   _add_col

    ADRL x0, Ls_pick                  // details of the selected row
    mov  x1, #2                       // WidthSizable
    mov  x2, #0
    mov  x3, x20
    ADRL x8, Lf_details
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_12
    bl   _mk_label
    mov  x21, x0
    ADRL x8, _g_scan_details
    str  x21, [x8]
    mov  x2, #0                       // word wrap
    MSG1 Ls_setLineBreakMode
    mov  x0, x21
    mov  x2, #8
    MSG1 Ls_setMaximumNumberOfLines
    mov  x0, x21
    mov  x2, #1
    MSG1 Ls_setSelectable

    ADRL x0, Ls_b_pair
    ADRL x1, Ls_m_scanPair
    mov  x2, #0
    mov  x3, x20
    ADRL x8, Lf_b_pair
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    ADRL x0, Ls_b_setup
    ADRL x1, Ls_m_scanSetUp
    mov  x2, #0
    mov  x3, x20
    ADRL x8, Lf_b_setup
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    ADRL x0, Ls_b_bt
    ADRL x1, Ls_m_scanBT
    mov  x2, #0
    mov  x3, x20
    ADRL x8, Lf_b_bt
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    ADRL x0, Ls_b_again
    ADRL x1, Ls_m_again
    mov  x2, #0
    mov  x3, x20
    ADRL x8, Lf_b_again
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    LEAVE 0

// ---------------------------------------------------------------------------
// Rows: Macs on the mesh, then Bluetooth LE, network (Bonjour), network
// (UPnP), then classic Bluetooth devices paired with this Mac.
// ---------------------------------------------------------------------------

// long _scan_selected(void) -> the selected row, or -1
_scan_selected:
    ENTER 0
    ADRL x8, _g_scan_table
    ldr  x0, [x8]
    cbz  x0, Lssel_none
    MSG0 Ls_selectedRow
    LEAVE 0
Lssel_none:
    mov  x0, #-1
    LEAVE 0

// void _scanner_update_details(void)
.globl _scanner_update_details
_scanner_update_details:
    ENTER 0
    ADRL x8, _g_scan_details
    ldr  x19, [x8]
    cbz  x19, Lsud_done
    bl   _scan_selected
    tbnz x0, #63, Lsud_pick
    bl   _scan_details_text
    b    Lsud_note
Lsud_pick:
    ADRL x8, _g_scan_text
    strb wzr, [x8]
    ADRL x0, Ls_pick
    bl   _cat
Lsud_note:
    ADRL x8, _g_scan_note
    ldrb w9, [x8]
    cbz  w9, Lsud_set
    ADRL x0, Ls_nlnl
    bl   _cat
    ADRL x0, _g_scan_note
    bl   _cat
Lsud_set:
    ADRL x0, _g_scan_text
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setStringValue
Lsud_done:
    LEAVE 0

// void _scanner_selected(void) — a new row: forget the last note
.globl _scanner_selected
_scanner_selected:
    ENTER 0
    ADRL x8, _g_scan_note
    strb wzr, [x8]
    bl   _scanner_update_details
    LEAVE 0

// void _scan_say(const char *fmt, a, b) — a line in Home and under the scanner
.globl _scan_say
_scan_say:
    ENTER 0
    mov  x4, x2
    mov  x3, x1
    mov  x2, x0
    ADRL x0, _g_scan_note
    mov  x1, #320
    bl   _sfmt
    ADRL x0, _g_scan_note
    bl   _home_say0
    bl   _scanner_update_details
    LEAVE 0

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

// - scanConnectPair: / - scanSetUp: — on the selected row (scan_core.s)
.globl _scan_pair
_scan_pair:
    ENTER 0
    bl   _scan_selected
    bl   _scan_pair_row
    LEAVE 0

.globl _scan_setup
_scan_setup:
    ENTER 0
    bl   _scan_selected
    bl   _scan_setup_row
    LEAVE 0

// id _scan_value(NSTableColumn *col, long row, char *buf) — a cell, for the table
.globl _scan_value
_scan_value:
    ENTER 16
    mov  x19, x1
    mov  x20, x2
    MSG0 Ls_identifier
    MSG0 Ls_UTF8String
    ldrb w0, [x0]
    mov  x1, x19
    mov  x2, x20
    bl   _scan_cell
    LEAVE 16

// - refreshDevices:
.globl _scan_refresh
_scan_refresh:
    ENTER 0
    ADRL x0, _g_scan_note
    ADRL x1, Ls_looking
    mov  x2, #320
    bl   _strlcpy
    bl   _scanner_update_details
    bl   _bt_refresh
    bl   _home_refresh
    bl   _ui_lists_changed
    LEAVE 0

// ===========================================================================
// Radar drawing. Doubles live on the stack between calls (d8-d15 untouched).
// ===========================================================================

// void _set_color(r, g, b, a in d0-d3)
_set_color:
    ENTER 32
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    CLS  Ls_NSColor
    mov  x19, x0
    SELX1 Ls_colorWithSRGB
    mov  x0, x19
    ldp  d0, d1, [sp, #96]
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    MSG0 Ls_set
    LEAVE 32

// void _set_color_k(const double *rgba)
_set_color_k:
    ldp  d0, d1, [x0]
    ldp  d2, d3, [x0, #16]
    b    _set_color

// id _oval_path(cx d0, cy d1, r d2) -> NSBezierPath circle
_oval_path:
    ENTER 32
    fsub d4, d0, d2
    fsub d5, d1, d2
    fadd d6, d2, d2
    stp  d4, d5, [sp, #96]
    str  d6, [sp, #112]
    CLS  Ls_NSBezierPath
    mov  x19, x0
    SELX1 Ls_ovalInRect
    mov  x0, x19
    ldp  d0, d1, [sp, #96]
    ldr  d2, [sp, #112]
    fmov d3, d2
    bl   _objc_msgSend
    LEAVE 32

_fill_oval:
    ENTER 0
    bl   _oval_path
    MSG0 Ls_fill
    LEAVE 0

_stroke_oval:
    ENTER 0
    bl   _oval_path
    MSG0 Ls_stroke
    LEAVE 0

// void _line(x1 d0, y1 d1, x2 d2, y2 d3)
_line:
    ENTER 32
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    CLS  Ls_NSBezierPath
    mov  x19, x0
    SELX1 Ls_strokeLine
    mov  x0, x19
    ldp  d0, d1, [sp, #96]
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    LEAVE 32

// void _draw_label(const char *utf8, x d0, y d1)
_draw_label:
    ENTER 16
    stp  d0, d1, [sp, #96]
    bl   _nsstr
    mov  x19, x0
    SELX1 Ls_drawAtPoint
    mov  x0, x19
    ldp  d0, d1, [sp, #96]
    ADRL x8, _g_attr_radar
    ldr  x2, [x8]
    bl   _objc_msgSend
    LEAVE 16

// - (void)drawRect:(NSRect)dirty      (self x0; the rect in d0-d3 is ignored)
_radar_draw:
    ENTER 128
    // locals: [96] cx  [104] cy  [112] R  [120] now  [128] r  [136] theta
    //         [144] x  [152] y   [160] sweep deg  [168] sweep rad  [176] tmp
    mov  x19, x0
    SELX1 Ls_bounds
    mov  x0, x19
    bl   _objc_msgSend                // bounds -> d0..d3
    LDD  d4, Lc_half
    fmul d5, d2, d4
    fadd d5, d0, d5
    str  d5, [sp, #96]
    fmul d6, d3, d4
    fadd d6, d1, d6
    str  d6, [sp, #104]
    fcmp d2, d3
    fcsel d7, d2, d3, lt
    fmul d7, d7, d4
    LDD  d4, Lc_8
    fsub d7, d7, d4
    str  d7, [sp, #112]

    // background disc
    ADRL x0, Lk_bg
    bl   _set_color_k
    ldr  d0, [sp, #96]
    ldr  d1, [sp, #104]
    ldr  d2, [sp, #112]
    bl   _fill_oval

    // four range rings and a crosshair
    ADRL x0, Lk_ring
    bl   _set_color_k
    mov  x20, #0                      // rings at 1, 3, 10 and 30 metres (log scale)
Lrd_ring:
    cmp  x20, #4
    b.hs Lrd_cross
    ADRL x8, Lring_frac
    ldr  d2, [x8, x20, lsl #3]
    ldr  d3, [sp, #112]
    fmul d2, d2, d3
    str  d2, [sp, #176]
    ldr  d0, [sp, #96]
    ldr  d1, [sp, #104]
    bl   _stroke_oval
    ADRL x8, Lring_label              // "3 m" just inside the top of its ring
    ldr  x0, [x8, x20, lsl #3]
    ldr  d0, [sp, #96]
    LDD  d1, Lc_3
    fadd d0, d0, d1
    ldr  d1, [sp, #104]
    ldr  d2, [sp, #176]
    fadd d1, d1, d2
    LDD  d2, Lc_12
    fsub d1, d1, d2
    bl   _draw_label
    add  x20, x20, #1
    b    Lrd_ring
Lrd_cross:
    ldr  d4, [sp, #96]
    ldr  d5, [sp, #112]
    fsub d0, d4, d5
    fadd d2, d4, d5
    ldr  d1, [sp, #104]
    fmov d3, d1
    bl   _line
    ldr  d4, [sp, #104]
    ldr  d5, [sp, #112]
    fsub d1, d4, d5
    fadd d3, d4, d5
    ldr  d0, [sp, #96]
    fmov d2, d0
    bl   _line

    // sweep: 60 degrees a second at 10 ticks a second
    ADRL x8, _g_tick
    ldr  x9, [x8]
    mov  x10, #6
    mul  x9, x9, x10
    mov  x10, #360
    udiv x11, x9, x10
    msub x9, x11, x10, x9
    scvtf d0, x9
    str  d0, [sp, #160]
    LDD  d1, Lc_deg2rad
    fmul d0, d0, d1
    str  d0, [sp, #168]
    ADRL x0, Lk_wedge
    bl   _set_color_k
    CLS  Ls_NSBezierPath
    MSG0 Ls_bezierPath
    mov  x20, x0
    SELX1 Ls_moveToPoint
    mov  x0, x20
    ldr  d0, [sp, #96]
    ldr  d1, [sp, #104]
    bl   _objc_msgSend
    SELX1 Ls_appendArc
    mov  x0, x20
    ldr  d0, [sp, #96]
    ldr  d1, [sp, #104]
    ldr  d2, [sp, #112]
    ldr  d4, [sp, #160]
    LDD  d5, Lc_35
    fsub d3, d4, d5
    bl   _objc_msgSend
    mov  x0, x20
    MSG0 Ls_closePath
    mov  x0, x20
    MSG0 Ls_fill
    ADRL x0, Lk_edge
    bl   _set_color_k
    ldr  d0, [sp, #168]
    bl   _cos
    ldr  d1, [sp, #112]
    fmul d0, d0, d1
    ldr  d1, [sp, #96]
    fadd d0, d0, d1
    str  d0, [sp, #176]
    ldr  d0, [sp, #168]
    bl   _sin
    ldr  d1, [sp, #112]
    fmul d0, d0, d1
    ldr  d1, [sp, #104]
    fadd d3, d0, d1
    ldr  d2, [sp, #176]
    ldr  d0, [sp, #96]
    ldr  d1, [sp, #104]
    bl   _line

    // nodes
    mov  x0, #0
    bl   _time
    str  x0, [sp, #120]
    ADRL x8, _g_node_count
    ldr  x21, [x8]
    mov  x20, #0
Lrd_node:
    cmp  x20, x21
    b.hs Lrd_you
    ADRL x8, _g_nodes
    add  x22, x8, x20, lsl #NODE_SHIFT
    ldr  x9, [sp, #120]
    ldr  x10, [x22, #N_SEEN]
    sub  x23, x9, x10                 // age in seconds
    cmp  x23, #300
    b.gt Lrd_next

    // distance from the centre, as a fraction of R
    ldr  x0, [x22, #N_RSSI]           // in range: by estimated distance
    cbz  x0, Lrd_norssi
    mov  x1, #0x7fff
    bl   _dist_dm
    tbnz x0, #63, Lrd_norssi
    bl   _dist_frac
    b    Lrd_frac
Lrd_norssi:
    ldr  x9, [x22, #N_HOPS]
    cmp  x9, #1
    b.hi Lrd_far
    LDD  d0, Lc_045
    b    Lrd_frac
Lrd_far:
    sub  x9, x9, #2
    scvtf d0, x9
    LDD  d1, Lc_008
    fmul d0, d0, d1
    LDD  d1, Lc_072
    fadd d0, d0, d1
    LDD  d1, Lc_094
    fmin d0, d0, d1
Lrd_frac:
    ldr  d1, [sp, #112]
    fmul d0, d0, d1
    str  d0, [sp, #128]
    ldr  x9, [x22, #N_ID]
    lsr  x9, x9, #16
    and  x9, x9, #0xffff
    scvtf d0, x9
    LDD  d1, Lc_ang
    fmul d0, d0, d1
    str  d0, [sp, #136]
    bl   _cos
    ldr  d1, [sp, #128]
    fmul d0, d0, d1
    ldr  d1, [sp, #96]
    fadd d0, d0, d1
    str  d0, [sp, #144]
    ldr  d0, [sp, #136]
    bl   _sin
    ldr  d1, [sp, #128]
    fmul d0, d0, d1
    ldr  d1, [sp, #104]
    fadd d0, d0, d1
    str  d0, [sp, #152]

    ADRL x0, Lk_away
    cmp  x23, #60
    b.gt Lrd_colour
    ldr  x9, [x22, #N_HOPS]
    ADRL x0, Lk_near
    cmp  x9, #1
    b.le Lrd_colour
    ADRL x0, Lk_far
Lrd_colour:
    bl   _set_color_k
    ldr  d0, [sp, #144]
    ldr  d1, [sp, #152]
    LDD  d2, Lc_5
    bl   _fill_oval
    mov  x0, x22
    bl   _node_name
    ldr  d0, [sp, #144]
    LDD  d1, Lc_8
    fadd d0, d0, d1
    ldr  d1, [sp, #152]
    LDD  d2, Lc_6
    fsub d1, d1, d2
    bl   _draw_label
Lrd_next:
    add  x20, x20, #1
    b    Lrd_node

Lrd_you:
    ADRL x8, _g_near_count
    ldr  x21, [x8]
    mov  x20, #0
Lrd_near:
    cmp  x20, x21
    b.hs Lrd_me
    ADRL x8, _g_near
    add  x22, x8, x20, lsl #NEAR_SHIFT
    ldr  x9, [sp, #120]
    ldr  x10, [x22, #16]
    sub  x9, x9, x10
    cmp  x9, #60
    b.gt Lrd_near_next
    ldr  x9, [x22, #8]
    cbz  x9, Lrd_near_next
    mov  x0, x20                      // by estimated distance
    bl   _near_dm
    tbnz x0, #63, Lrd_near_next
    bl   _dist_frac
    ldr  d1, [sp, #112]
    fmul d0, d0, d1
    str  d0, [sp, #128]
    ldr  x9, [x22]                    // bearing from the object's address bits
    lsr  x9, x9, #4
    and  x9, x9, #0xffff
    scvtf d0, x9
    LDD  d1, Lc_ang
    fmul d0, d0, d1
    str  d0, [sp, #136]
    bl   _cos
    ldr  d1, [sp, #128]
    fmul d0, d0, d1
    ldr  d1, [sp, #96]
    fadd d0, d0, d1
    str  d0, [sp, #144]
    ldr  d0, [sp, #136]
    bl   _sin
    ldr  d1, [sp, #128]
    fmul d0, d0, d1
    ldr  d1, [sp, #104]
    fadd d0, d0, d1
    str  d0, [sp, #152]
    ADRL x0, Lk_ble
    bl   _set_color_k
    ldr  d0, [sp, #144]
    ldr  d1, [sp, #152]
    LDD  d2, Lc_3
    bl   _fill_oval
    ldrb w9, [x22, #24]
    cbz  w9, Lrd_near_next
    add  x0, x22, #24
    ldr  d0, [sp, #144]
    LDD  d1, Lc_6
    fadd d0, d0, d1
    ldr  d1, [sp, #152]
    LDD  d2, Lc_6
    fsub d1, d1, d2
    bl   _draw_label
Lrd_near_next:
    add  x20, x20, #1
    b    Lrd_near
Lrd_me:
    ADRL x0, Lk_you
    bl   _set_color_k
    ldr  d0, [sp, #96]
    ldr  d1, [sp, #104]
    LDD  d2, Lc_6
    bl   _fill_oval
    ADRL x0, Ls_you
    ldr  d0, [sp, #96]
    LDD  d1, Lc_9
    fadd d0, d0, d1
    ldr  d1, [sp, #104]
    LDD  d2, Lc_6
    fsub d1, d1, d2
    bl   _draw_label
    LEAVE 128

.section __DATA,__const
.p2align 3
Lring_label: .quad Ls_r1, Ls_r3, Ls_r10, Ls_r30

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_r1:                .asciz "1 m"
Ls_r3:                .asciz "3 m"
Ls_r10:               .asciz "10 m"
Ls_r30:               .asciz "30 m"
Ls_NSView:            .asciz "NSView"
Ls_NSWindow:          .asciz "NSWindow"
Ls_NSTimer:           .asciz "NSTimer"
Ls_NSColor:           .asciz "NSColor"
Ls_NSBezierPath:      .asciz "NSBezierPath"
Ls_NSApplication:     .asciz "NSApplication"
Ls_radar_name:        .asciz "AMRadarView"
Ls_drawRect:          .asciz "drawRect:"
Ls_ty_draw:           .asciz "v@:{CGRect={CGPoint=dd}{CGSize=dd}}"
Ls_tick:              .asciz "tick:"
Ls_scheduledTimer:    .asciz "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"
Ls_isVisible:         .asciz "isVisible"
Ls_setNeedsDisplay:   .asciz "setNeedsDisplay:"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_alloc:             .asciz "alloc"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_initWithFrame:     .asciz "initWithFrame:"
Ls_setTitle:          .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_center:            .asciz "center"
Ls_contentView:       .asciz "contentView"
Ls_setAutoresizingMask: .asciz "setAutoresizingMask:"
Ls_addSubview:        .asciz "addSubview:"
Ls_identifier:        .asciz "identifier"
Ls_UTF8String:        .asciz "UTF8String"
Ls_colorWithSRGB:     .asciz "colorWithSRGBRed:green:blue:alpha:"
Ls_set:               .asciz "set"
Ls_ovalInRect:        .asciz "bezierPathWithOvalInRect:"
Ls_fill:              .asciz "fill"
Ls_stroke:            .asciz "stroke"
Ls_strokeLine:        .asciz "strokeLineFromPoint:toPoint:"
Ls_drawAtPoint:       .asciz "drawAtPoint:withAttributes:"
Ls_bounds:            .asciz "bounds"
Ls_bezierPath:        .asciz "bezierPath"
Ls_moveToPoint:       .asciz "moveToPoint:"
Ls_appendArc:         .asciz "appendBezierPathWithArcWithCenter:radius:startAngle:endAngle:"
Ls_closePath:         .asciz "closePath"

Ls_scan_title:        .asciz "Mesh Scanner"
Ls_legend:            .asciz "rings: 1, 3, 10, 30 m (from signal)  \302\267  green: Macs in range  \302\267  amber: via other Macs  \302\267  blue: Bluetooth"
Ls_you:               .asciz "you"
Ls_c_name:            .asciz "name"
Ls_c_sig:             .asciz "sig"
Ls_c_hops:            .asciz "hops"
Ls_c_seen:            .asciz "last"
Ls_c_kind:            .asciz "kind"
Ls_c_det:             .asciz "details"
Ls_h_name:            .asciz "Name"
Ls_h_sig:             .asciz "Signal"
Ls_h_hops:            .asciz "Hops"
Ls_h_seen:            .asciz "Where"
Ls_h_kind:            .asciz "Kind"
Ls_h_det:             .asciz "Details"
Ls_f_num:             .asciz "%ld"
Ls_f_dbm:             .asciz "%ld dBm"
Ls_f_secs:            .asciz "%lds ago"
Ls_f_mins:            .asciz "%ldm ago"
Ls_dash:              .asciz "\342\200\224"
Ls_now:               .asciz "now"
Ls_unnamed:           .asciz "(unnamed)"
Ls_ble:               .asciz "BLE"
Ls_setLineBreakMode:  .asciz "setLineBreakMode:"
Ls_setMaximumNumberOfLines: .asciz "setMaximumNumberOfLines:"
Ls_setSelectable:     .asciz "setSelectable:"
Ls_setStringValue:    .asciz "setStringValue:"
Ls_selectedRow:       .asciz "selectedRow"
Ls_m_scanPair:        .asciz "scanConnectPair:"
Ls_m_scanSetUp:       .asciz "scanSetUp:"
Ls_m_scanBT:          .asciz "scanBluetoothSettings:"
Ls_m_again:           .asciz "refreshDevices:"
Ls_b_pair:            .asciz "Connect & Pair"
Ls_b_setup:           .asciz "Set Up"
Ls_b_bt:              .asciz "Bluetooth Settings\342\200\246"
Ls_b_again:           .asciz "Look Again"
Ls_pick:              .asciz "Pick a row to see everything it says about itself. Connect & Pair reads a Bluetooth device's maker, model, firmware and battery (macOS asks first if it needs pairing) or connects a paired headset or keyboard; Set Up pairs a Hue Bridge or Nanoleaf, connects Home Assistant, opens the Home app for HomeKit and Matter devices, or opens a device's web page."
Ls_k_mesh:            .asciz "Mac (asmmesh)"
Ls_home_ready:        .asciz "\302\267 %s is already connected \342\200\224 in Home, try \342\200\234%s status\342\200\235."
Ls_f_hops_away:       .asciz "%ld hops away"
Ls_where_sp:          .asciz "\nWhere: "
Ls_where_note:        .asciz " (estimated from signal strength, so walls and bodies make it read farther; heard "
Ls_close_paren:       .asciz ")"
Ls_in_sp:             .asciz " in "
Ls_state_sp:          .asciz "\nState: "
Ls_can_sp:            .asciz "\nCan: "
Ls_home_hint2:        .asciz "\nSay its name with what to do in Home, e.g. \342\200\234off\342\200\235, \342\200\23450%\342\200\235 or \342\200\234status\342\200\235. \342\200\234list devices\342\200\235 shows everything room by room."
Ls_f_hops:            .asciz "in range \302\267 relayed %ld"
Ls_f_hops_n:          .asciz "%ld hops \302\267 relayed %ld"
Ls_d_hk:              .asciz "HomeKit, not paired: Set Up adds it in Home"
Ls_d_matter:          .asciz "Matter, open for pairing: Set Up"
Ls_d_conn:            .asciz "connectable: Connect & Pair reads its details"
Ls_d_bcast:           .asciz "broadcast only"
Lf_d_node:            .asciz "%s \342\200\224 a Mac running asmmesh\nSignal: %s \302\267 %s\nIt's already linked: messages and remote commands reach it over the mesh."
Lf_d_bt:              .asciz "%s \342\200\224 %s\n%s\nConnect & Pair asks it to connect now. To pair something new, put it in pairing mode and open Bluetooth Settings."
Ls_dash_sp:           .asciz " \342\200\224 "
Ls_signal_sp:         .asciz "\nSignal "
Ls_services_sp:       .asciz "\nServices: "
Ls_nl:                .asciz "\n"
Ls_nlnl:              .asciz "\n\n"
Ls_connected:         .asciz "connected"
Ls_paired:            .asciz "paired"
Ls_tx_sp:             .asciz " \302\267 transmit power "
Ls_dbm:               .asciz " dBm"
Ls_conn_yes:          .asciz " \302\267 accepts connections"
Ls_conn_no:           .asciz " \302\267 broadcast only"
Ls_none:              .asciz "none listed"
Ls_x_hk:              .asciz "This HomeKit accessory isn't paired yet. Set Up opens the Home app: + \342\200\272 Add Accessory, then scan its code."
Ls_x_matter:          .asciz "This Matter device is open for pairing. Set Up opens the Home app to add it (or use your SmartThings / Home Assistant app)."
Ls_x_read:            .asciz "Read over Bluetooth: %s"
Ls_x_conn:            .asciz "Connect & Pair reads its maker, model, firmware and battery. If it needs pairing, macOS asks you first."
Ls_x_bcast:           .asciz "It only broadcasts. Headsets, keyboards and speakers pair in Bluetooth Settings while in pairing mode."
Ls_no_row:            .asciz "\302\267 Pick a row in the scanner first."
Ls_mesh_already:      .asciz "\302\267 That's a Mac on the mesh \342\200\224 it's already linked."
Ls_near_setup_none:   .asciz "\302\267 Nothing to set up there. Use Connect & Pair to read its details, or Bluetooth Settings to pair a headset or keyboard."
Ls_lan_nothing:       .asciz "\302\267 %s doesn't need setting up."
Ls_looking:           .asciz "\302\267 Looking again for Bluetooth, network and home devices\342\200\246"
