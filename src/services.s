// services.s — every integration asmmesh can use has its own switch, and every
// switch starts OFF. Nothing talks to a hub, a cloud, the network or a remote
// until you turn it on — in Settings (⌘, or the Services button), or by typing
// "enable hue" / "disable smartthings" / "services".
//
// A switched-off service is never started, its devices drop out of every list
// and command, and its commands say how to turn it back on. Turning one on
// starts it right away (no restart). Saved as defaults "svc_<key>" = "1".
//
// The Settings window is styled like the Productive habit app: a near-black
// window, rounded dark cards, a coloured round icon per row, bold rounded type.

.include "macros.inc"

.set SV_SIZE,   48                    // key, title, subtitle, SF Symbol, colour, kinds
.set ST_LAN,    40                    // "started" bits shared by several switches
.set ST_CLOUD,  41                    //   (above every service's own bit)

// window geometry
.set SW_W,      964
.set SW_H,      720                   // three columns, eight rows of cards
.set SW_TOP,    (SW_H - 118 - 64)     // y of the first row of cards

.data
.p2align 3
.globl _g_svc_on
_g_svc_on:      .quad 0               // bit i: service i is on
_g_svc_started: .quad 0               // bit i: service i was started this run
_g_svc_win:     .quad 0
.globl _g_svc_boot
_g_svc_boot:    .quad 0               // 1 while starting at launch: services start quietly
.globl _g_kind_on
.zerofill __DATA,__bss,_g_kind_on,32,4    // byte per device kind: 1 if its service is on
.zerofill __DATA,__bss,_g_svc_sw,256,4    // the NSSwitch for each service
.zerofill __DATA,__bss,_g_svc_line,512,4

.section __DATA,__const
.p2align 3
Lsvc:
    .quad Lk_hue,   Lt_hue,   Ld_hue,   Lsy_hue,   0xFF9F0A, 0x26
    .quad Lk_st,    Lt_st,    Ld_st,    Lsy_st,    0x0A84FF, 0x48
    .quad Lk_home,  Lt_home,  Ld_home,  Lsy_home,  0xFF6B3D, 0x10
    .quad Lk_wifi,  Lt_wifi,  Ld_wifi,  Lsy_wifi,  0x30D158, 0x28780
    .quad Lk_tv,    Lt_tv,    Ld_tv,    Lsy_tv,    0xBF5AF2, 0x14000
    .quad Lk_lifx,  Lt_lifx,  Ld_lifx,  Lsy_lifx,  0xFF375F, 0x800
    .quad Lk_govee, Lt_govee, Ld_govee, Lsy_govee, 0x64D2FF, 0x1000
    .quad Lk_ha,    Lt_ha,    Ld_ha,    Lsy_ha,    0x5E5CE6, 0x2000
    .quad Lk_spin,  Lt_spin,  Ld_spin,  Lsy_spin,  0xFF453A, 0
    .quad Lk_wx,    Lt_wx,    Ld_wx,    Lsy_wx,    0xFFD60A, 0
    .quad Lk_mesh,  Lt_mesh,  Ld_mesh,  Lsy_mesh,  0x32ADE6, 0
    .quad Lk_rules, Lt_rules, Ld_rules, Lsy_rules, 0xDA8FFF, 0
    .quad Lk_find,  Lt_find,  Ld_find,  Lsy_find,  0x34C759, 0
    .quad Lk_web,   Lt_web,   Ld_web,   Lsy_web,   0x98989D, 0
    .quad Lk_voice, Lt_voice, Ld_voice, Lsy_voice, 0xFF2D55, 0
    .quad Lk_fm,    Lt_fm,    Ld_fm,    Lsy_fm,    0xFFB340, 0
    .quad Lk_gate,  Lt_gate,  Ld_gate,  Lsy_gate,  0x0A84FF, 0
    .quad Lk_loc,   Lt_loc,   Ld_loc,   Lsy_loc,   0x0A84FF, 0
    .quad Lk_ntfy,  Lt_ntfy,  Ld_ntfy,  Lsy_ntfy,  0x30D158, 0
    .quad Lk_po,    Lt_po,    Ld_po,    Lsy_po,    0x249DF1, 0
    .quad Lk_nws,   Lt_nws,   Ld_nws,   Lsy_nws,   0xFF9F0A, 0
    .quad Lk_hook,  Lt_hook,  Ld_hook,  Lsy_hook,  0xBF5AF2, 0
    .quad Lk_files, Lt_files, Ld_files, Lsy_files, 0x64D2FF, 0

.section __TEXT,__const
.p2align 3
Lc0:        .double 0.0
Lc1:        .double 1.0
Lc255:      .double 255.0
Lc_W:       .double 964.0
Lc_H:       .double 720.0
Lc_cw:      .double 300.0
Lc_ch:      .double 64.0
Lc_r16:     .double 16.0
Lc_r18:     .double 18.0
Lc_s26:     .double 26.0
Lc_s14:     .double 14.0
Lc_s13:     .double 13.0
Lc_s11:     .double 11.0
// frames inside the window / a card: x, y, w, h
Lf_title:   .double 24.0, 646.0, 420.0, 34.0
Lf_sub:     .double 24.0, 622.0, 900.0, 18.0
Lf_icon:    .double 14.0, 14.0, 36.0, 36.0
Lf_glyph:   .double 8.0, 8.0, 20.0, 20.0
Lf_name:    .double 62.0, 33.0, 170.0, 18.0
Lf_what:    .double 62.0, 14.0, 172.0, 16.0
Lf_switch:  .double 240.0, 20.0, 44.0, 24.0

.text
.p2align 2

// long _svc_on(long i) -> 1 if service i is switched on (leaf: x8, x9 only)
.globl _svc_on
_svc_on:
    ADRL x8, _g_svc_on
    ldr  x9, [x8]
    lsr  x9, x9, x0
    and  x0, x9, #1
    ret

// const char *_svc_title(long i)
.globl _svc_title
_svc_title:
    ADRL x8, Lsvc
    mov  x9, #SV_SIZE
    madd x8, x0, x9, x8
    ldr  x0, [x8, #8]
    ret

// long _svc_gate(long i) -> 1 if on; otherwise says in Home how to turn it on
.globl _svc_gate
_svc_gate:
    ENTER 0
    mov  x19, x0
    bl   _svc_on
    cbnz x0, Lsg_yes
    mov  x0, x19
    bl   _svc_title
    mov  x1, x0
    ADRL x0, Lf_svc_off
    bl   _home_say
    mov  x0, #0
    LEAVE 0
Lsg_yes:
    mov  x0, #1
    LEAVE 0

// char *_svc_key(long i, char *buf /*32*/) -> "svc_hue"
_svc_key:
    ENTER 0
    mov  x19, x1
    ADRL x8, Lsvc
    mov  x9, #SV_SIZE
    madd x8, x0, x9, x8
    ldr  x9, [x8]
    str  x9, [sp]
    mov  x0, x19
    mov  x1, #32
    ADRL x2, Lf_key
    bl   _snprintf
    mov  x0, x19
    LEAVE 0

// void _svc_load(void) — read every switch (missing = off)
.globl _svc_load
_svc_load:
    ENTER 48                          // [96] key  [128] value
    mov  x19, #0
    mov  x20, #0
Lsl_loop:
    cmp  x19, #NSVC
    b.hs Lsl_done
    mov  x0, x19
    add  x1, sp, #96
    bl   _svc_key
    add  x0, sp, #96
    add  x1, sp, #128
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #128]
    cmp  w9, #'1'
    b.ne Lsl_next
    mov  x9, #1
    lsl  x9, x9, x19
    orr  x20, x20, x9
Lsl_next:
    add  x19, x19, #1
    b    Lsl_loop
Lsl_done:
    ADRL x8, _g_svc_on
    str  x20, [x8]
    bl   _svc_kinds
    LEAVE 48

// void _svc_kinds(void) — rebuild the per-device-kind table from the switches
_svc_kinds:
    ENTER 0
    ADRL x19, _g_kind_on
    stp  xzr, xzr, [x19]
    stp  xzr, xzr, [x19, #16]
    ADRL x8, _g_svc_on
    ldr  x20, [x8]
    ADRL x21, Lsvc
    mov  x22, #0
Lsk_loop:
    cmp  x22, #NSVC
    b.hs Lsk_done
    lsr  x9, x20, x22
    tbz  x9, #0, Lsk_next
    ldr  x10, [x21, #40]
    mov  x11, #0
Lsk_bit:
    cmp  x11, #32
    b.hs Lsk_next
    lsr  x12, x10, x11
    tbz  x12, #0, Lsk_bit_next
    mov  w13, #1
    strb w13, [x19, x11]
Lsk_bit_next:
    add  x11, x11, #1
    b    Lsk_bit
Lsk_next:
    add  x21, x21, #SV_SIZE
    add  x22, x22, #1
    b    Lsk_loop
Lsk_done:
    LEAVE 0

// void _svc_start_all(void) — at launch: start whatever is switched on
.globl _svc_start_all
_svc_start_all:
    ENTER 0
    ADRL x8, _g_svc_boot
    mov  x9, #1
    str  x9, [x8]
    mov  x19, #0
Lsa_loop:
    cmp  x19, #NSVC
    b.hs Lsa_done
    mov  x0, x19
    bl   _svc_on
    cbz  x0, Lsa_next
    mov  x0, x19
    bl   _svc_start
Lsa_next:
    add  x19, x19, #1
    b    Lsa_loop
Lsa_done:
    ADRL x8, _g_svc_boot
    str  xzr, [x8]
    bl   _svc_summary
    LEAVE 0

// void _svc_start(long i) — bring a service up (once per run)
.globl _svc_start
_svc_start:
    ENTER 0
    mov  x19, x0
    ADRL x20, _g_svc_started
    ldr  x9, [x20]
    lsr  x10, x9, x19
    tbnz x10, #0, Lss_done
    mov  x10, #1
    lsl  x10, x10, x19
    orr  x9, x9, x10
    str  x9, [x20]
    cmp  x19, #SVC_HUE
    b.eq Lss_hue
    cmp  x19, #SVC_ST
    b.eq Lss_st
    cmp  x19, #SVC_HOME
    b.eq Lss_home
    cmp  x19, #SVC_WIFI
    b.eq Lss_lan
    cmp  x19, #SVC_TV
    b.eq Lss_lan
    cmp  x19, #SVC_LIFX
    b.eq Lss_cloud
    cmp  x19, #SVC_GOVEE
    b.eq Lss_cloud
    cmp  x19, #SVC_HA
    b.eq Lss_cloud
    cmp  x19, #SVC_WEATHER
    b.eq Lss_weather
    cmp  x19, #SVC_FM
    b.eq Lss_fm
    cmp  x19, #SVC_GATE
    b.eq Lss_gate
    cmp  x19, #SVC_LOC
    b.eq Lss_loc
    cmp  x19, #SVC_NTFY
    b.eq Lss_ntfy
    cmp  x19, #SVC_PUSHOVER
    b.eq Lss_po
    cmp  x19, #SVC_NWS
    b.eq Lss_nws
    cmp  x19, #SVC_HOOK
    b.eq Lss_hook
    cmp  x19, #SVC_FILES
    b.eq Lss_files
    b    Lss_done
Lss_files:
    bl   _files_start
    b    Lss_done
Lss_loc:
    bl   _al_loc_start
    b    Lss_done
Lss_ntfy:
    bl   _al_ntfy_start
    b    Lss_done
Lss_po:                               // its keys come from the Keychain: off the main thread
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    ADRL x8, _g_svc_boot              // at launch: quietly
    ldr  x1, [x8]
    ADRL x2, _svc_po_worker
    bl   _dispatch_async_f
    b    Lss_done
Lss_nws:
    bl   _al_nws_start
    b    Lss_done
Lss_hook:
    bl   _hook_start
    b    Lss_done
Lss_fm:
    bl   _fm_start
    b    Lss_done
Lss_gate:
    bl   _web_gate_start
    b    Lss_done
Lss_hue:
    bl   _hue_init
    b    Lss_done
Lss_home:
    bl   _sc_load
    b    Lss_done
Lss_weather:
    bl   _weather_init
    b    Lss_done
Lss_lan:
    ldr  x9, [x20]
    tbnz x9, #ST_LAN, Lss_done
    orr  x9, x9, #(1 << ST_LAN)
    str  x9, [x20]
    bl   _lan_init
    bl   _udp_init
    b    Lss_done
Lss_st:                               // its token comes from the Keychain: off the main thread
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, #0
    ADRL x2, _svc_st_worker
    bl   _dispatch_async_f
    b    Lss_done
Lss_cloud:
    ldr  x9, [x20]
    tbnz x9, #ST_CLOUD, Lss_done
    orr  x9, x9, #(1 << ST_CLOUD)
    str  x9, [x20]
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, #0
    ADRL x2, _svc_cloud_worker
    bl   _dispatch_async_f
Lss_done:
    LEAVE 0

_svc_st_worker:
    ENTER 0
    bl   _st_kc_read
    LDGOT x0, __dispatch_main_q
    mov  x1, #0
    ADRL x2, _svc_st_ready
    bl   _dispatch_async_f
    LEAVE 0

_svc_st_ready:
    ENTER 0
    bl   _st_init
    bl   _ui_lists_changed
    LEAVE 0

_svc_po_worker:                       // ctx: 1 = quietly
    ENTER 0
    mov  x19, x0
    bl   _al_po_read
    LDGOT x0, __dispatch_main_q
    mov  x1, x19
    ADRL x2, _svc_po_ready
    bl   _dispatch_async_f
    LEAVE 0

_svc_po_ready:
    ENTER 0
    bl   _al_po_start                 // x0: quietly
    LEAVE 0

_svc_cloud_worker:
    ENTER 0
    bl   _cloud_kc_read
    LDGOT x0, __dispatch_main_q
    mov  x1, #0
    ADRL x2, _svc_cloud_ready
    bl   _dispatch_async_f
    LEAVE 0

_svc_cloud_ready:
    ENTER 0
    bl   _cloud_init
    bl   _ui_lists_changed
    LEAVE 0

// void _svc_set(long i, long on) — flip a switch: saved, applied, said in Home
.globl _svc_set
_svc_set:
    ENTER 48
    mov  x19, x0
    cmp  x1, #0
    cset x20, ne
    ADRL x8, _g_svc_on
    ldr  x9, [x8]
    mov  x10, #1
    lsl  x10, x10, x19
    orr  x11, x9, x10
    bic  x12, x9, x10
    cmp  x20, #0
    csel x9, x12, x11, eq
    str  x9, [x8]
    mov  x0, x19
    add  x1, sp, #96
    bl   _svc_key
    ADRL x1, Ls_one
    ADRL x9, Ls_zero
    cmp  x20, #0
    csel x1, x9, x1, eq
    add  x0, sp, #96
    bl   _pref_set
    bl   _svc_kinds
    ADRL x8, _g_svc_sw                // keep the window's switch in step
    ldr  x0, [x8, x19, lsl #3]
    cbz  x0, Lsv_say
    mov  x2, x20
    MSG1 Ls_setState
Lsv_say:
    mov  x0, x19
    bl   _svc_title
    mov  x1, x0
    ADRL x0, Lf_now_on
    ADRL x9, Lf_now_off
    cmp  x20, #0
    csel x0, x9, x0, eq
    bl   _home_say
    cbnz x20, Lsv_start
    cmp  x19, #SVC_GATE               // gateway off: it may start again later
    b.ne Lsv_notgate
    ADRL x8, _g_svc_started
    ldr  x9, [x8]
    bic  x9, x9, #(1 << SVC_GATE)
    str  x9, [x8]
    b    Lsv_done
Lsv_notgate:
    cmp  x19, #SVC_LOC                // alerts: each may start again later
    b.lo Lsv_notalerts
    cmp  x19, #SVC_FILES
    b.hi Lsv_notalerts
    ADRL x8, _g_svc_started
    ldr  x9, [x8]
    mov  x10, #1
    lsl  x10, x10, x19
    bic  x9, x9, x10
    str  x9, [x8]
    cmp  x19, #SVC_FILES
    b.ne Lsv_nofiles
    bl   _files_stop
    b    Lsv_done
Lsv_nofiles:
    cmp  x19, #SVC_HOOK
    b.ne Lsv_done
    bl   _hook_stop
    b    Lsv_done
Lsv_notalerts:
    cmp  x19, #SVC_FM                 // FM off: stop the radio; it may start again later
    b.ne Lsv_done
    bl   _fm_stop
    ADRL x8, _g_svc_started
    ldr  x9, [x8]
    bic  x9, x9, #(1 << SVC_FM)
    str  x9, [x8]
    b    Lsv_done
Lsv_start:
    mov  x0, x19
    bl   _svc_start
Lsv_done:
    bl   _ui_lists_changed
    LEAVE 48

// - (void)serviceToggled:(NSSwitch *)sender
.globl _svc_toggled
_svc_toggled:
    ENTER 0
    mov  x19, x2
    mov  x0, x19
    MSG0 Ls_tag
    mov  x20, x0
    mov  x0, x19
    MSG0 Ls_state
    mov  x21, x0
    cmp  x20, #NSVC
    b.hs Lst_done
    mov  x0, x20
    mov  x1, x21
    bl   _svc_set
Lst_done:
    LEAVE 0

// void _svc_summary(void) — "Services on: … — everything else is off"
.globl _svc_summary
_svc_summary:
    ENTER 0
    ADRL x19, _g_svc_line
    strb wzr, [x19]
    mov  x20, #0
    mov  x21, #0                      // how many are on
Lsu_loop:
    cmp  x20, #NSVC
    b.hs Lsu_say
    mov  x0, x20
    bl   _svc_on
    cbz  x0, Lsu_next
    cbz  x21, Lsu_first
    mov  x0, x19
    ADRL x1, Ls_comma
    mov  x2, #512
    bl   _strlcat
Lsu_first:
    mov  x0, x20
    bl   _svc_title
    mov  x1, x0
    mov  x0, x19
    mov  x2, #512
    bl   _strlcat
    add  x21, x21, #1
Lsu_next:
    add  x20, x20, #1
    b    Lsu_loop
Lsu_say:
    cbnz x21, Lsu_some
    ADRL x0, Ls_all_off
    bl   _home_say0
    LEAVE 0
Lsu_some:
    mov  x1, x19
    ADRL x0, Lf_some_on
    bl   _home_say
    LEAVE 0

// "services" / "settings" — say what's on and open the window
.globl _h_services
_h_services:
    ENTER 0
    bl   _svc_summary
    bl   _svc_show
    LEAVE 0

// "enable hue" (arg 1) / "disable smartthings" (arg 0) / "enable everything"
.globl _h_svc_switch
_h_svc_switch:
    ENTER 0
    mov  x19, x0                      // on?
    mov  x20, x1                      // which
    ldrb w9, [x20]
    cbz  w9, Lhw_usage
    mov  x0, x20
    ADRL x1, Ls_w_all
    bl   _strcasecmp
    cbz  w0, Lhw_all
    mov  x0, x20
    ADRL x1, Ls_w_everything
    bl   _strcasecmp
    cbz  w0, Lhw_all
    mov  x21, #0
Lhw_find:
    cmp  x21, #NSVC
    b.hs Lhw_usage
    ADRL x8, Lsvc
    mov  x9, #SV_SIZE
    madd x22, x21, x9, x8
    mov  x0, x20                      // its key: "hue", "smartthings"…
    ldr  x1, [x22]
    bl   _strcasecmp
    cbz  w0, Lhw_hit
    ldr  x0, [x22, #8]                // or a piece of its name: "home assistant", "lutron"
    mov  x1, x20
    bl   _strcasestr
    cbnz x0, Lhw_hit
    ldr  x0, [x22, #16]
    mov  x1, x20
    bl   _strcasestr
    cbnz x0, Lhw_hit
    add  x21, x21, #1
    b    Lhw_find
Lhw_hit:
    mov  x0, x21
    mov  x1, x19
    bl   _svc_set
    LEAVE 0
Lhw_all:
    mov  x21, #0
Lhw_all_loop:
    cmp  x21, #NSVC
    b.hs Lhw_done
    mov  x0, x21
    mov  x1, x19
    bl   _svc_set
    add  x21, x21, #1
    b    Lhw_all_loop
Lhw_usage:
    ADRL x0, Ls_sw_usage
    bl   _home_say0
Lhw_done:
    LEAVE 0

// ===========================================================================
// Look: colours, layers, the Settings window
// ===========================================================================

// id _rgb(long 0xRRGGBB) — an sRGB NSColor
.globl _rgb
_rgb:
    ENTER 16
    mov  x19, x0
    SELX1 Ls_colorWithSRGB
    mov  x20, x1
    CLS  Ls_NSColor
    mov  x1, x20
    ubfx x9, x19, #16, #8
    ucvtf d0, x9
    ubfx x9, x19, #8, #8
    ucvtf d1, x9
    and  x9, x19, #0xff
    ucvtf d2, x9
    LDD  d4, Lc255
    fdiv d0, d0, d4
    fdiv d1, d1, d4
    fdiv d2, d2, d4
    LDD  d3, Lc1
    bl   _objc_msgSend
    LEAVE 16

// void _card(id view, long 0xRRGGBB, double radius /*d0*/) — rounded colour fill
.globl _card
_card:
    ENTER 32
    str  d0, [sp, #96]
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setWantsLayer
    mov  x0, x20
    bl   _rgb
    MSG0 Ls_CGColor
    mov  x21, x0
    mov  x0, x19
    MSG0 Ls_layer
    mov  x22, x0
    cbz  x22, Lcd_done
    mov  x2, x21
    MSG1 Ls_setBackgroundColor
    SELX1 Ls_setCornerRadius
    mov  x0, x22
    ldr  d0, [sp, #96]
    bl   _objc_msgSend
    mov  x0, x22
    mov  x2, #1
    MSG1 Ls_setMasksToBounds
Lcd_done:
    LEAVE 32

// id _plain_view(id parent, frame d0-d3) — an empty NSView added to parent
.globl _plain_view
_plain_view:
    ENTER 32
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    mov  x19, x0
    CLS  Ls_NSView
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

// - (void)showSettings:(id)sender — the Services window
.globl _svc_show
_svc_show:
    ENTER 0
    ADRL x8, _g_svc_win
    ldr  x0, [x8]
    cbnz x0, Lsw_front
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
    ADRL x8, _g_svc_win
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
    mov  x2, #1                       // NSWindowTitleHidden
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

    ADRL x0, Ls_win_title             // big bold title, like the app's "Today"
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

    mov  x19, #0
Lsw_cards:
    cmp  x19, #NSVC
    b.hs Lsw_front_w
    mov  x0, x19
    mov  x1, x21
    bl   _svc_card
    add  x19, x19, #1
    b    Lsw_cards
Lsw_front_w:
    ADRL x8, _g_svc_win
    ldr  x0, [x8]
Lsw_front:
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    LEAVE 0

// void _svc_card(long i, id parent) — one rounded row: icon, name, what, switch
_svc_card:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    ADRL x8, Lsvc
    mov  x9, #SV_SIZE
    madd x21, x19, x9, x8
    // three columns; row r = i / 3 from the top
    mov  x11, #3
    udiv x10, x19, x11
    msub x9, x10, x11, x19
    mov  x11, #316
    mul  x9, x9, x11
    add  x9, x9, #16
    ucvtf d0, x9
    mov  x11, #74
    mul  x10, x10, x11
    mov  x11, #SW_TOP
    sub  x10, x11, x10
    ucvtf d1, x10
    LDD  d2, Lc_cw
    LDD  d3, Lc_ch
    mov  x0, x20
    bl   _plain_view
    mov  x22, x0                      // the card
    mov  x1, #0x2C2E
    movk x1, #0x2C, lsl #16
    LDD  d0, Lc_r16
    bl   _card

    mov  x0, x22                      // coloured round icon
    ADRL x8, Lf_icon
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _plain_view
    mov  x23, x0
    ldr  x1, [x21, #32]
    LDD  d0, Lc_r18
    bl   _card
    ldr  x0, [x21, #24]
    bl   _symbol_image
    cbz  x0, Lsc_text
    mov  x24, x0
    CLS  Ls_NSImageView
    mov  x2, x24
    MSG1 Ls_imageViewWithImage
    mov  x24, x0
    SELX1 Ls_setFrame
    mov  x0, x24
    ADRL x8, Lf_glyph
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    CLS  Ls_NSColor
    MSG0 Ls_whiteColor
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_setContentTintColor
    mov  x0, x23
    mov  x2, x24
    MSG1 Ls_addSubview

Lsc_text:
    ldr  x0, [x21, #8]
    mov  x1, #0
    mov  x2, #1
    mov  x3, x22
    ADRL x8, Lf_name
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s14
    bl   _mk_label
    ldr  x0, [x21, #16]
    mov  x1, #0
    mov  x2, #0
    mov  x3, x22
    ADRL x8, Lf_what
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s11
    bl   _mk_label
    bl   _dim_label

    CLS  Ls_NSSwitch
    MSG0 Ls_alloc
    mov  x24, x0
    SELX1 Ls_initWithFrame
    mov  x0, x24
    ADRL x8, Lf_switch
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x24, x0
    cbz  x24, Lsc_done
    ADRL x8, _g_svc_sw
    str  x24, [x8, x19, lsl #3]
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x24
    MSG1 Ls_setTarget
    ADRL x0, Ls_m_toggled
    bl   _sel_registerName
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_setAction
    mov  x0, x24
    mov  x2, x19
    MSG1 Ls_setTag
    mov  x0, x19
    bl   _svc_on
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_setState
    mov  x0, x22
    mov  x2, x24
    MSG1 Ls_addSubview
Lsc_done:
    LEAVE 16

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lk_hue:     .asciz "hue"
Lk_st:      .asciz "smartthings"
Lk_home:    .asciz "home"
Lk_wifi:    .asciz "wifi"
Lk_tv:      .asciz "tv"
Lk_lifx:    .asciz "lifx"
Lk_govee:   .asciz "govee"
Lk_ha:      .asciz "homeassistant"
Lk_spin:    .asciz "spin"
Lk_wx:      .asciz "weather"
Lk_mesh:    .asciz "mesh"
Lk_rules:   .asciz "rules"
Lk_find:    .asciz "find"
Lk_web:     .asciz "web"
Lk_voice:   .asciz "voice"
Lk_fm:      .asciz "fm"
Lk_gate:    .asciz "gateway"
Lk_loc:     .asciz "location"
Lk_ntfy:    .asciz "ntfy"
Lk_po:      .asciz "pushover"
Lk_nws:     .asciz "alerts"
Lk_hook:    .asciz "webhook"
Lk_files:   .asciz "files"
Lt_hue:     .asciz "Philips Hue"
Lt_st:      .asciz "SmartThings"
Lt_home:    .asciz "Apple Home"
Lt_wifi:    .asciz "Wi-Fi lights & plugs"
Lt_tv:      .asciz "TVs & speakers"
Lt_lifx:    .asciz "LIFX"
Lt_govee:   .asciz "Govee"
Lt_ha:      .asciz "Home Assistant"
Lt_spin:    .asciz "SPIN remote"
Lt_wx:      .asciz "Weather & sunset"
Lt_mesh:    .asciz "Mesh commands"
Lt_rules:   .asciz "Automations"
Lt_find:    .asciz "Find my things"
Lt_web:     .asciz "Web requests"
Lt_voice:   .asciz "Voice"
Lt_fm:      .asciz "FM radio"
Lt_gate:    .asciz "Internet for the mesh"
Lt_loc:     .asciz "Location"
Lt_ntfy:    .asciz "ntfy"
Lt_po:      .asciz "Pushover"
Lt_nws:     .asciz "Weather alerts"
Lt_hook:    .asciz "Webhook"
Lt_files:   .asciz "Files on Wi-Fi"
Ld_hue:     .asciz "Bridge and Bluetooth bulbs"
Ld_st:      .asciz "Lutron, Samsung and more"
Ld_home:    .asciz "Scenes and devices via Shortcuts"
Ld_wifi:    .asciz "WLED, Elgato, Shelly, Nanoleaf, WiZ, Kasa"
Ld_tv:      .asciz "Roku and Sonos on your network"
Ld_lifx:    .asciz "LIFX cloud lights"
Ld_govee:   .asciz "Govee cloud lights"
Ld_ha:      .asciz "Your Home Assistant server"
Ld_spin:    .asciz "The rotary Bluetooth remote"
Ld_wx:      .asciz "Forecasts, sunrise and sunset"
Ld_mesh:    .asciz "Let people on the mesh ask this Mac"
Ld_rules:   .asciz "Your rules and timers"
Ld_find:    .asciz "Trackers and nearby things"
Ld_web:     .asciz "\342\200\234http get\342\200\235 from Home"
Ld_voice:   .asciz "The Talk button"
Ld_fm:      .asciz "The mesh over an FM transmitter"
Ld_gate:    .asciz "Pages and headlines for others"
Ld_loc:     .asciz "Where you are, for SOS and alerts"
Ld_ntfy:    .asciz "Pushes to your phone (ntfy.sh)"
Ld_po:      .asciz "Pushes and loud SOS alerts"
Ld_nws:     .asciz "US National Weather Service"
Ld_hook:    .asciz "Shortcuts and IFTTT post in"
Ld_files:   .asciz "Your phone browses and uploads"
Lsy_hue:    .asciz "lightbulb.fill"
Lsy_st:     .asciz "square.grid.2x2.fill"
Lsy_home:   .asciz "house.fill"
Lsy_wifi:   .asciz "wifi"
Lsy_tv:     .asciz "tv.fill"
Lsy_lifx:   .asciz "sparkles"
Lsy_govee:  .asciz "rays"
Lsy_ha:     .asciz "server.rack"
Lsy_spin:   .asciz "dial.max.fill"
Lsy_wx:     .asciz "cloud.sun.fill"
Lsy_mesh:   .asciz "antenna.radiowaves.left.and.right"
Lsy_rules:  .asciz "clock.arrow.circlepath"
Lsy_find:   .asciz "magnifyingglass"
Lsy_web:    .asciz "globe"
Lsy_voice:  .asciz "mic.fill"
Lsy_fm:     .asciz "dot.radiowaves.left.and.right"
Lsy_gate:   .asciz "globe.americas.fill"
Lsy_loc:    .asciz "location.fill"
Lsy_ntfy:   .asciz "bell.fill"
Lsy_po:     .asciz "paperplane.fill"
Lsy_nws:    .asciz "exclamationmark.triangle.fill"
Lsy_hook:   .asciz "link"
Lsy_files:  .asciz "folder.fill"

Lf_key:        .asciz "svc_%s"
Ls_one:        .asciz "1"
Ls_zero:       .asciz "0"
Ls_comma:      .asciz ", "
Ls_w_all:      .asciz "all"
Ls_w_everything: .asciz "everything"
Lf_svc_off:    .asciz "\302\267 \342\217\270 %s is switched off. Turn it on in Settings (\342\214\230,) or say \342\200\234enable\342\200\235 and its name."
Lf_now_on:     .asciz "\302\267 \342\234\205 %s is on."
Lf_now_off:    .asciz "\302\267 \342\217\270 %s is off \342\200\224 asmmesh won\342\200\231t use it until you turn it back on."
Ls_all_off:    .asciz "\302\267 \342\217\270 Every service is switched off. Open Settings (\342\214\230,) or the Services button to turn on the ones you use."
Lf_some_on:    .asciz "\302\267 Services on: %s. Everything else is off (Settings: \342\214\230,)."
Ls_sw_usage:   .asciz "\302\267 Say \342\200\234enable\342\200\235 or \342\200\234disable\342\200\235 and a service: hue, smartthings, home, wifi, tv, lifx, govee, homeassistant, spin, weather, mesh, rules, find, web, voice, fm, gateway, location, ntfy, pushover, alerts, webhook, files \342\200\224 or \342\200\234all\342\200\235."
Ls_win_title:  .asciz "Services"
Ls_win_sub:    .asciz "Everything starts off. Switch on only what you use \342\200\224 each one is independent."
Ls_m_toggled:  .asciz "serviceToggled:"

Ls_NSColor:            .asciz "NSColor"
Ls_NSView:             .asciz "NSView"
Ls_NSWindow:           .asciz "NSWindow"
Ls_NSImageView:        .asciz "NSImageView"
Ls_NSSwitch:           .asciz "NSSwitch"
Ls_NSApplication:      .asciz "NSApplication"
Ls_colorWithSRGB:      .asciz "colorWithSRGBRed:green:blue:alpha:"
Ls_setWantsLayer:      .asciz "setWantsLayer:"
Ls_CGColor:            .asciz "CGColor"
Ls_layer:              .asciz "layer"
Ls_setBackgroundColor: .asciz "setBackgroundColor:"
Ls_setCornerRadius:    .asciz "setCornerRadius:"
Ls_setMasksToBounds:   .asciz "setMasksToBounds:"
Ls_alloc:              .asciz "alloc"
Ls_initWithFrame:      .asciz "initWithFrame:"
Ls_addSubview:         .asciz "addSubview:"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_setTitle:           .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_setTitlebarAppearsTransparent: .asciz "setTitlebarAppearsTransparent:"
Ls_setTitleVisibility: .asciz "setTitleVisibility:"
Ls_center:             .asciz "center"
Ls_contentView:        .asciz "contentView"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_sharedApplication:  .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_imageViewWithImage: .asciz "imageViewWithImage:"
Ls_setFrame:           .asciz "setFrame:"
Ls_whiteColor:         .asciz "whiteColor"
Ls_setContentTintColor: .asciz "setContentTintColor:"
Ls_setTarget:          .asciz "setTarget:"
Ls_setAction:          .asciz "setAction:"
Ls_setTag:             .asciz "setTag:"
Ls_tag:                .asciz "tag"
Ls_state:              .asciz "state"
Ls_setState:           .asciz "setState:"
