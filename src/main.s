// main.s — asmmesh entry point, the main window, menus, menu-bar item, and the
// runtime-built controller class. Everything goes through the Objective-C
// runtime from ARM64 assembly.
//
// Main window (820x640, origin bottom-left):
//
//   +-----------------+----------------------------------------------+
//   | ROOMS        [+]| # Main — everyone on the mesh   [You: Fred ] |
//   | # Main          | 2 linked nearby · 3 on the mesh · 5 relayed   |
//   | # lab  (2)      |                                              |
//   | PEOPLE ON MESH  |  transcript of the selected room             |
//   | Anna · nearby   |                                              |
//   | Ben  · 2 hops   |                                              |
//   | [Invite to chat]|                                              |
//   | [Mesh Scanner ] | [ Message #Main                     ] [Send] |
//   +-----------------+----------------------------------------------+
//
// `asmmesh --selftest` skips all of this and runs test.s (exit 0 = passed).

.include "macros.inc"

// ---------------------------------------------------------------------------
.data
.p2align 3
.globl _g_window
_g_window:        .quad 0
.globl _g_content
_g_content:       .quad 0
.globl _g_chatview
_g_chatview:      .quad 0
.globl _g_field
_g_field:         .quad 0
.globl _g_status
_g_status:        .quad 0
.globl _g_header
_g_header:        .quad 0
.globl _g_namebtn
_g_namebtn:       .quad 0
.globl _g_rooms_table
_g_rooms_table:   .quad 0
.globl _g_people_table
_g_people_table:  .quad 0
.globl _g_ctl
_g_ctl:           .quad 0
.globl _g_font
_g_font:          .quad 0
.globl _g_sitem
_g_sitem:         .quad 0
.globl _g_sinfo
_g_sinfo:         .quad 0
.globl _g_attr_msg
_g_attr_msg:      .quad 0
.globl _g_attr_sys
_g_attr_sys:      .quad 0
.globl _g_attr_radar
_g_attr_radar:    .quad 0

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lc_zero:     .double 0.0
Lc_W:        .double 820.0
Lc_H:        .double 640.0
Lc_Hshow:    .double 740.0
Lc_minW:     .double 640.0
Lc_minH:     .double 420.0
Lc_big:      .double 10000000.0
Lc_10:       .double 10.0
Lc_11:       .double 11.0
Lc_12:       .double 12.0
Lc_13:       .double 13.0
Lc_15:       .double 15.0
Lc_17:       .double 17.0
Lc_14:       .double 14.0
Lc_card:     .double 16.0
Lc_varlen:   .double -1.0
Lc_rc_r:     .double 0.70
Lc_rc_g:     .double 1.0
Lc_rc_b:     .double 0.80
// frames: x, y, w, h
Lf_roomslbl: .double 16.0, 610.0, 150.0, 16.0
Lf_addroom:  .double 206.0, 604.0, 36.0, 28.0
Lf_rooms:    .double 6.0, 306.0, 240.0, 294.0
Lf_peoplelbl: .double 16.0, 284.0, 196.0, 16.0
Lf_people:   .double 6.0, 128.0, 240.0, 152.0
Lf_invite:   .double 8.0, 88.0, 236.0, 32.0
Lf_scanner:  .double 8.0, 50.0, 236.0, 32.0
Lf_services: .double 8.0, 12.0, 236.0, 32.0
Lf_header:   .double 266.0, 606.0, 360.0, 22.0
Lf_namebtn:  .double 632.0, 602.0, 176.0, 30.0
Lf_status:   .double 266.0, 586.0, 542.0, 16.0
Lf_chat:     .double 256.0, 58.0, 556.0, 520.0
Lf_fieldbox: .double 262.0, 12.0, 456.0, 36.0
Lf_field:    .double 14.0, 9.0, 428.0, 19.0
Lf_talk:     .double 726.0, 12.0, 36.0, 36.0
Lf_send:     .double 770.0, 12.0, 36.0, 36.0

// Controller methods: selector name, IMP, type encoding. Zero-terminated.
.section __DATA,__const
.p2align 3
Lmethods:
    .quad Ls_m_reopen,      _app_reopen,        Ls_ty_reopen
    .quad Ls_m_showMain,    _ui_show,           Ls_ty_v1
    .quad Ls_m_send,        _ui_send,           Ls_ty_v1
    .quad Ls_m_newRoom,     _ui_new_room,       Ls_ty_v1
    .quad Ls_m_invite,      _ui_invite,         Ls_ty_v1
    .quad Ls_m_leave,       _ui_leave_room,     Ls_ty_v1
    .quad Ls_m_delroom,     _ui_delete_room,    Ls_ty_v1
    .quad Ls_m_listroom,    _ui_list_room,      Ls_ty_v1
    .quad Ls_m_joinroom,    _ui_join_room,      Ls_ty_v1
    .quad Ls_m_changeName,  _ui_change_name,    Ls_ty_v1
    .quad Ls_m_showScanner, _scanner_show,      Ls_ty_v1
    .quad Ls_m_showSettings, _svc_show,         Ls_ty_v1
    .quad Ls_m_svcToggled,  _svc_toggled,       Ls_ty_v1
    .quad Ls_m_showSpin,    _sui_show,          Ls_ty_v1
    .quad Ls_m_spinTab,     _sui_tab,           Ls_ty_v1
    .quad Ls_m_spinName,    _sui_name,          Ls_ty_v1
    .quad Ls_m_spinEnable,  _sui_enable,        Ls_ty_v1
    .quad Ls_m_spinDevices, _sui_devs,          Ls_ty_v1
    .quad Ls_m_spinAdd,     _sui_add,           Ls_ty_v1
    .quad Ls_m_spinAction,  _sui_action,        Ls_ty_v1
    .quad Ls_m_spinText,    _sui_text,          Ls_ty_v1
    .quad Ls_m_spinLock,    _sui_lock,          Ls_ty_v1
    .quad Ls_m_spinTest,    _sui_test,          Ls_ty_v1
    .quad Ls_m_tick,        _ui_tick,           Ls_ty_v1
    .quad Ls_m_rows,        _ds_rows,           Ls_ty_rows
    .quad Ls_m_value,       _ds_value,          Ls_ty_value
    .quad Ls_m_selChanged,  _ds_selchange,      Ls_ty_v1
    .quad Ls_m_cmState,     _ble_cm_state,      Ls_ty_v1
    .quad Ls_m_cmDiscover,  _g_ble_cm_discover,   Ls_ty_v4
    .quad Ls_m_cmConnect,   _ble_cm_connect,    Ls_ty_v2
    .quad Ls_m_cmFail,      _ble_cm_lost,       Ls_ty_v3
    .quad Ls_m_cmDisconn,   _ble_cm_lost,       Ls_ty_v3
    .quad Ls_m_pServices,   _ble_p_services,    Ls_ty_v2
    .quad Ls_m_pChars,      _ble_p_chars,       Ls_ty_v3
    .quad Ls_m_pValue,      _g_ble_p_value,       Ls_ty_v3
    .quad Ls_m_pRSSI,       _ble_p_rssi,        Ls_ty_v3
    .quad Ls_m_pModify,     _ble_p_modify,      Ls_ty_v2
    .quad Ls_m_pmState,     _ble_pm_state,      Ls_ty_v1
    .quad Ls_m_pmAdded,     _ble_pm_added,      Ls_ty_v3
    .quad Ls_m_pmAdv,       _ble_pm_adv,        Ls_ty_v2
    .quad Ls_m_pmRead,      _ble_pm_read,       Ls_ty_v2
    .quad Ls_m_pmWrites,    _g_ble_pm_writes,     Ls_ty_v2
    .quad Ls_m_talk,        _voice_toggle,      Ls_ty_v1
    .quad Ls_m_connectST,   _st_connect_dialog, Ls_ty_v1
    .quad Ls_m_pairHue,     _hue_pair,          Ls_ty_v1
    .quad Ls_m_meshPass,    _crypto_dialog,     Ls_ty_v1
    .quad Ls_m_fmShow,      _fm_show,           Ls_ty_v1
    .quad Ls_m_fmApply,     _fm_apply,          Ls_ty_v1
    .quad Ls_m_fmTest,      _fm_test_hello,     Ls_ty_v1
    .quad Ls_m_connectHA,   _ha_connect_dialog, Ls_ty_v1
    .quad Ls_m_connectLIFX, _lifx_connect_dialog, Ls_ty_v1
    .quad Ls_m_connectGovee, _govee_connect_dialog, Ls_ty_v1
    .quad Ls_m_pairNano,    _nano_pair,         Ls_ty_v1
    .quad Ls_m_refreshHome, _scan_refresh,      Ls_ty_v1
    .quad Ls_m_scanPair,    _scan_pair,         Ls_ty_v1
    .quad Ls_m_scanSetUp,   _scan_setup,        Ls_ty_v1
    .quad Ls_m_scanBT,      _bt_settings,       Ls_ty_v1
    .quad Ls_m_netData,     _net_data,          Ls_ty_v3
    .quad Ls_m_netDone,     _net_done,          Ls_ty_v3
    .quad Ls_m_bonjourFound, _lan_found,        Ls_ty_found
    .quad Ls_m_resolved,    _lan_resolved,      Ls_ty_v1
    .quad Ls_m_speechHyp,   _voice_hyp,         Ls_ty_v2
    .quad Ls_m_speechFinal, _voice_final,       Ls_ty_v2
    .quad Ls_m_speechDone,  _voice_done,        Ls_ty_vB
    .quad Ls_m_locUpdate,   _al_cl_update,      Ls_ty_v2
    .quad Ls_m_locFail,     _al_cl_fail,        Ls_ty_v2
    .quad Ls_m_filesShow,   _h_files,           Ls_ty_v1
    .quad Ls_m_filesChoose, _h_files_choose,    Ls_ty_v1
    .quad Ls_m_airdrop,     _h_airdrop,         Ls_ty_v1
    .quad 0, 0, 0

Lprotos:
    .quad Ls_p_app, Ls_p_cm, Ls_p_p, Ls_p_pm, Ls_p_tds, Ls_p_tdl
    .quad Ls_p_url, Ls_p_nsb, Ls_p_ns, Ls_p_speech
    .quad 0

// ---------------------------------------------------------------------------
.text
.p2align 2

// void _main_later(void (*fn)(void *), void *ctx) — run fn(ctx) on the main thread, after the
//   current callback. Code that may ask something goes through here (the iPhone's version
//   waits for the run loop instead: ios_ui.s).
.globl _main_later
_main_later:
    mov  x2, x0
    LDGOT x0, __dispatch_main_q
    b    _dispatch_async_f

// const char *_app_build(void) — this app's build number (CFBundleVersion), or "?"
.globl _app_build
_app_build:
    ENTER 0
    CLS  Ls_NSBundle
    MSG0 Ls_mainBundle
    cbz  x0, 1f
    mov  x19, x0
    ADRL x0, Ls_CFBundleVersion
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_objectForInfoKey
    cbz  x0, 1f
    MSG0 Ls_UTF8String_b
    cbnz x0, 2f
1:  ADRL x0, Ls_qmark
2:  LEAVE 0

// int main(int argc, char **argv)
.globl _main
_main:
    ENTER 0
    mov  w19, w0
    mov  x20, x1
    bl   _objc_autoreleasePoolPush
    cmp  w19, #2
    b.lt Lmain_gui
    ldr  x0, [x20, #8]
    ADRL x1, Ls_selftest_flag
    bl   _strcmp
    cbnz w0, Lmain_gui
    ADRL x8, _g_no_persist            // tests never touch your saved name or rooms
    mov  x9, #1
    str  x9, [x8]
    bl   _mesh_init
    bl   _rooms_init
    bl   _selftest
    bl   _exit                        // flushes stdout
Lmain_gui:
    bl   _mesh_init
    bl   _rooms_init
    bl   _build_ui
    mov  x0, #0
    bl   _ui_select_room
    bl   _app_build                   // "asmmesh 0.8 (build 11)", from the app's Info.plist
    mov  x2, x0
    ADRL x0, Ls_fmt_welcome
    ADRL x1, _g_nick
    bl   _chat_fmt
    bl   _ble_start
    bl   _start_timer
    LDGOT x0, __dispatch_main_q       // Home starts once the window is up: reading the
    mov  x1, #0                       // Keychain can wait on a macOS permission prompt,
    ADRL x2, _home_init               // and the window shouldn't wait with it
    bl   _dispatch_async_f
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    MSG0 Ls_run
    mov  w0, #0
    LEAVE 0

// ---------------------------------------------------------------------------
// void _build_ui(void)
// ---------------------------------------------------------------------------
_build_ui:
    ENTER 0
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x19, x0                      // x19 = NSApp
    mov  x2, #0                       // NSApplicationActivationPolicyRegular
    MSG1 Ls_setActivationPolicy
    CLS  Ls_NSAppearance              // dark, like the Productive app
    LDGOT x8, _NSAppearanceNameDarkAqua
    ldr  x2, [x8]
    MSG1 Ls_appearanceNamed
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setAppearance

    bl   _make_controller
    mov  x22, x0
    ADRL x8, _g_ctl
    str  x22, [x8]
    mov  x0, x19
    mov  x2, x22
    MSG1 Ls_setDelegate
    bl   _make_radar_class
    bl   _make_attrs
    bl   _cards_init

    // ---- window ----
    CLS  Ls_NSWindow
    MSG0 Ls_alloc
    mov  x20, x0
    SELX1 Ls_initWithContentRect
    mov  x0, x20
    LDD  d0, Lc_zero
    LDD  d1, Lc_zero
    LDD  d2, Lc_W
    LDD  d3, Lc_H
    mov  x2, #15                      // titled|closable|miniaturizable|resizable
    mov  x3, #2                       // NSBackingStoreBuffered
    mov  x4, #0
    bl   _objc_msgSend
    mov  x20, x0
    ADRL x8, _g_window
    str  x20, [x8]
    ADRL x0, Ls_title
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
    mov  x0, #0x1A1C                  // near-black window
    movk x0, #0x1A, lsl #16
    bl   _rgb
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_setBackgroundColor
    SELX1 Ls_setContentMinSize
    mov  x0, x20
    LDD  d0, Lc_minW
    LDD  d1, Lc_minH
    bl   _objc_msgSend
    mov  x0, x20
    MSG0 Ls_center
    mov  x0, x20
    MSG0 Ls_contentView
    mov  x21, x0                      // x21 = content view
    ADRL x8, _g_content
    str  x21, [x8]

    // ---- sidebar: room and people cards straight on the window, as on iPhone ----
    ADRL x0, Ls_rooms_lbl
    mov  x1, #8                       // MinYMargin: stays at the top
    mov  x2, #1
    mov  x3, x21
    ADRL x8, Lf_roomslbl
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_11
    bl   _mk_label
    bl   _dim_label

    ADRL x0, Ls_plus
    ADRL x1, Ls_m_newRoom
    mov  x2, #8
    mov  x3, x21
    ADRL x8, Lf_addroom
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    mov  x1, #0xB82E                  // amber
    movk x1, #0xF5, lsl #16
    mov  x2, #1
    bl   _pill

    mov  x0, #8
    mov  x1, #0                       // no header
    mov  x2, x21
    ADRL x8, Lf_rooms
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_table
    ADRL x8, _g_rooms_table
    str  x0, [x8]
    ADRL x1, Ls_col_main
    mov  x2, #0
    LDD  d0, Lc_colw
    bl   _add_col
    ADRL x8, _g_rooms_table
    ldr  x0, [x8]
    bl   _cards_attach

    ADRL x0, Ls_people_lbl
    mov  x1, #8
    mov  x2, #1
    mov  x3, x21
    ADRL x8, Lf_peoplelbl
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_11
    bl   _mk_label
    bl   _dim_label

    mov  x0, #16                      // HeightSizable
    mov  x1, #0
    mov  x2, x21
    ADRL x8, Lf_people
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_table
    ADRL x8, _g_people_table
    str  x0, [x8]
    ADRL x1, Ls_col_main
    mov  x2, #0
    LDD  d0, Lc_colw
    bl   _add_col
    ADRL x8, _g_people_table
    ldr  x0, [x8]
    bl   _cards_attach

    ADRL x0, Ls_invite_title
    ADRL x1, Ls_m_invite
    mov  x2, #32                      // MaxYMargin: stays at the bottom
    mov  x3, x21
    ADRL x8, Lf_invite
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button

    ADRL x0, Ls_scanner_title
    ADRL x1, Ls_m_showScanner
    mov  x2, #32
    mov  x3, x21
    ADRL x8, Lf_scanner
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button

    ADRL x0, Ls_services_title
    ADRL x1, Ls_m_showSettings
    mov  x2, #32
    mov  x3, x21
    ADRL x8, Lf_services
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    mov  x1, #0x0A84                  // blue, like the app's add button
    movk x1, #0xFF, lsl #16
    mov  x2, #0
    bl   _pill

    // ---- right: header, name button, status ----
    ADRL x0, Ls_empty
    mov  x1, #10                      // WidthSizable | MinYMargin
    mov  x2, #1
    mov  x3, x21
    ADRL x8, Lf_header
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_17
    bl   _mk_label
    ADRL x8, _g_header
    str  x0, [x8]

    ADRL x0, Ls_empty
    ADRL x1, Ls_m_changeName
    mov  x2, #9                       // MinXMargin | MinYMargin
    mov  x3, x21
    ADRL x8, Lf_namebtn
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_button
    ADRL x8, _g_namebtn
    str  x0, [x8]
    bl   _ui_update_name

    ADRL x0, Ls_status0
    mov  x1, #10
    mov  x2, #0
    mov  x3, x21
    ADRL x8, Lf_status
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_11
    bl   _mk_label
    ADRL x8, _g_status
    str  x0, [x8]
    bl   _dim_label

    // ---- transcript ----
    mov  x0, x21
    mov  x1, #18                      // WidthSizable | HeightSizable
    ADRL x8, Lf_chat
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _mk_textview
    ADRL x8, _g_chatview
    str  x0, [x8]
    mov  x1, #0x1A1C                  // flat on the window, like the iPhone's chat
    movk x1, #0x1A, lsl #16
    bl   _card_scroll

    // ---- input: a rounded card holding a plain field, round mic and send ----
    mov  x0, x21
    ADRL x8, Lf_fieldbox
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _plain_view
    mov  x24, x0
    mov  x2, #34                      // WidthSizable | MaxYMargin
    MSG1 Ls_setAutoresizingMask
    mov  x0, x24
    mov  x1, #0x2426
    movk x1, #0x22, lsl #16
    LDD  d0, Lc_r18
    bl   _card

    CLS  Ls_NSTextField
    MSG0 Ls_alloc
    mov  x23, x0
    SELX1 Ls_initWithFrame
    mov  x0, x23
    ADRL x8, Lf_field
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x23, x0
    ADRL x8, _g_field
    str  x23, [x8]
    mov  x0, x23
    mov  x2, x22
    MSG1 Ls_setTarget
    ADRL x0, Ls_m_send
    bl   _sel_registerName
    mov  x2, x0
    mov  x0, x23
    MSG1 Ls_setAction
    mov  x0, x23
    mov  x2, #2                       // WidthSizable
    MSG1 Ls_setAutoresizingMask
    mov  x0, x23
    mov  x2, #0
    MSG1 Ls_setBezeled
    mov  x0, x23
    mov  x2, #0
    MSG1 Ls_setBordered
    mov  x0, x23
    mov  x2, #0
    MSG1 Ls_setDrawsBackground
    mov  x0, x23
    mov  x2, #1                       // NSFocusRingTypeNone: the card is the field
    MSG1 Ls_setFocusRingType
    LDD  d0, Lc_14
    mov  w0, #0
    bl   _font
    mov  x2, x0
    mov  x0, x23
    MSG1 Ls_setFont
    mov  x0, x24
    mov  x2, x23
    MSG1 Ls_addSubview

    ADRL x0, Ls_y_send
    ADRL x1, Ls_m_send
    mov  x2, #33                      // MinXMargin | MaxYMargin
    mov  x3, x21
    mov  x4, #0x9E0A                  // amber, black arrow
    movk x4, #0xFF, lsl #16
    mov  x5, #1
    ADRL x8, Lf_send
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _cd_round
    ADRL x1, Ls_send_title
    bl   _tooltip

    ADRL x0, Ls_y_mic
    ADRL x1, Ls_m_talk
    mov  x2, #33
    mov  x3, x21
    mov  x4, #0x2E2F                  // dark grey, white mic
    movk x4, #0x33, lsl #16
    mov  x5, #0
    ADRL x8, Lf_talk
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _cd_round
    ADRL x8, _g_talkbtn
    str  x0, [x8]
    ADRL x1, Ls_talk_tip
    bl   _tooltip

    // ---- menus, menu-bar item ----
    mov  x0, x19
    bl   _build_menus
    bl   _build_status_item

    // ---- show: taller than the 640 it was laid out at, so People has room ----
    SELX1 Ls_setContentSize
    ADRL x8, _g_window
    ldr  x0, [x8]
    LDD  d0, Lc_W
    LDD  d1, Lc_Hshow
    bl   _objc_msgSend
    ADRL x8, _g_window
    ldr  x0, [x8]
    MSG0 Ls_center
    ADRL x8, _g_window
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    ADRL x8, _g_window
    ldr  x0, [x8]
    ADRL x8, _g_field
    ldr  x2, [x8]
    MSG1 Ls_makeFirstResponder
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    LEAVE 0

// ---------------------------------------------------------------------------
// id _make_controller(void) — builds, registers and instantiates AMeshController
// ---------------------------------------------------------------------------
_make_controller:
    ENTER 0
    CLS  Ls_NSObject
    ADRL x1, Ls_ctl_name
    mov  x2, #0
    bl   _objc_allocateClassPair
    mov  x19, x0
    ADRL x20, Lmethods
Lmc_loop:
    ldr  x0, [x20]
    cbz  x0, Lmc_protos
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    ldr  x2, [x20, #8]
    ldr  x3, [x20, #16]
    bl   _class_addMethod
    add  x20, x20, #24
    b    Lmc_loop
Lmc_protos:
    ADRL x20, Lprotos
Lmc_ploop:
    ldr  x0, [x20]
    cbz  x0, Lmc_register
    bl   _objc_getProtocol
    cbz  x0, Lmc_pnext
    mov  x1, x0
    mov  x0, x19
    bl   _class_addProtocol
Lmc_pnext:
    add  x20, x20, #8
    b    Lmc_ploop
Lmc_register:
    mov  x0, x19
    bl   _objc_registerClassPair
    mov  x0, x19
    MSG0 Ls_new
    LEAVE 0

// ---------------------------------------------------------------------------
// Text attributes shared by the transcript and the radar labels
// ---------------------------------------------------------------------------
_make_attrs:
    ENTER 0
    LDD  d0, Lc_13
    mov  w0, #0
    bl   _font
    MSG0 Ls_retain
    ADRL x8, _g_font
    str  x0, [x8]
    mov  x19, x0
    CLS  Ls_NSColor
    MSG0 Ls_labelColor
    mov  x1, x0
    mov  x0, x19
    bl   _dict2
    ADRL x8, _g_attr_msg
    str  x0, [x8]

    LDD  d0, Lc_12
    mov  w0, #0
    bl   _font
    mov  x19, x0
    CLS  Ls_NSColor
    MSG0 Ls_secondaryLabelColor
    mov  x1, x0
    mov  x0, x19
    bl   _dict2
    ADRL x8, _g_attr_sys
    str  x0, [x8]

    LDD  d0, Lc_10
    mov  w0, #1
    bl   _font
    mov  x19, x0
    CLS  Ls_NSColor
    mov  x20, x0
    SELX1 Ls_colorWithSRGB
    mov  x0, x20
    LDD  d0, Lc_rc_r
    LDD  d1, Lc_rc_g
    LDD  d2, Lc_rc_b
    LDD  d3, Lc_rc_g
    bl   _objc_msgSend
    mov  x1, x0
    mov  x0, x19
    bl   _dict2
    ADRL x8, _g_attr_radar
    str  x0, [x8]
    LEAVE 0

// id _font(double size /*d0*/, int bold /*w0*/)
.globl _font
_font:
    ENTER 16
    str  d0, [sp, #96]
    mov  w19, w0
    CLS  Ls_NSFont
    mov  x20, x0
    ADRL x0, Ls_systemFontOfSize
    ADRL x8, Ls_boldSystemFontOfSize
    cmp  w19, #0
    csel x0, x8, x0, ne
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x20
    ldr  d0, [sp, #96]
    bl   _objc_msgSend
    mov  x21, x0                      // the plain system font; now its rounded design
    cbz  x21, Lfo_done
    MSG0 Ls_fontDescriptor
    cbz  x0, Lfo_plain
    LDGOT x8, _NSFontDescriptorSystemDesignRounded
    ldr  x2, [x8]
    MSG1 Ls_fontDescriptorWithDesign
    cbz  x0, Lfo_plain
    mov  x22, x0
    CLS  Ls_NSFont
    mov  x20, x0
    SELX1 Ls_fontWithDescriptorSize
    mov  x0, x20
    mov  x2, x22
    ldr  d0, [sp, #96]
    bl   _objc_msgSend
    cbnz x0, Lfo_done
Lfo_plain:
    mov  x0, x21
Lfo_done:
    LEAVE 16

// id _dict2(id font, id color) — retained {font, foreground colour} attributes
_dict2:
    ENTER 32
    stp  x0, x1, [sp, #96]
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
    LEAVE 32

// ---------------------------------------------------------------------------
// View helpers. Frames arrive in d0-d3; `parent` is the view to add to.
// ---------------------------------------------------------------------------

// id _mk_label(const char *text, mask, int bold, id parent, frame d0-d3, size d4)
.globl _mk_label
_mk_label:
    ENTER 48
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    str  d4, [sp, #128]
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x23, x3
    mov  x0, x19
    bl   _nsstr
    mov  x22, x0
    CLS  Ls_NSTextField
    mov  x2, x22
    MSG1 Ls_labelWithString
    mov  x22, x0
    SELX1 Ls_setFrame
    mov  x0, x22
    ldp  d0, d1, [sp, #96]
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    ldr  d0, [sp, #128]
    mov  w0, w21
    bl   _font
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setFont
    mov  x0, x22
    mov  x2, #4                       // NSLineBreakByTruncatingTail
    MSG1 Ls_setLineBreakMode
    mov  x0, x22
    mov  x2, x20
    MSG1 Ls_setAutoresizingMask
    mov  x0, x23
    mov  x2, x22
    MSG1 Ls_addSubview
    mov  x0, x22
    LEAVE 48

// void _dim_label(id label) — secondary text colour
.globl _dim_label
_dim_label:
    ENTER 0
    mov  x19, x0
    CLS  Ls_NSColor
    MSG0 Ls_secondaryLabelColor
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setTextColor
    mov  x0, x19
    LEAVE 0

// id _mk_button(const char *title, const char *selname, mask, id parent, frame d0-d3)
.globl _mk_button
_mk_button:
    ENTER 32
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x23, x3
    mov  x0, x20
    bl   _sel_registerName
    mov  x20, x0
    mov  x0, x19
    bl   _nsstr
    mov  x19, x0
    CLS  Ls_NSButton
    mov  x2, x19
    ADRL x8, _g_ctl
    ldr  x3, [x8]
    mov  x4, x20
    MSG3 Ls_buttonWithTitle
    mov  x22, x0
    SELX1 Ls_setFrame
    mov  x0, x22
    ldp  d0, d1, [sp, #96]
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    mov  x0, x22
    mov  x2, x21
    MSG1 Ls_setAutoresizingMask
    mov  x0, x23
    mov  x2, x22
    MSG1 Ls_addSubview
    mov  x0, x22                      // a dark grey pill
    mov  x1, #0x3A3C
    movk x1, #0x3A, lsl #16
    mov  x2, #0
    bl   _pill
    mov  x0, x22
    LEAVE 32

// id _pill(id button, long 0xRRGGBB, int dark_text) -> button: coloured, bold
//   rounded title (black on light colours)
.globl _pill
_pill:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, x20
    bl   _rgb
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setBezelColor
    mov  x0, x19
    MSG0 Ls_sel_title
    cbz  x0, Lpl_done
    mov  x22, x0
    LDD  d0, Lc_13
    mov  w0, #1
    bl   _font
    mov  x23, x0
    CLS  Ls_NSColor
    MSG0 Ls_whiteColor
    mov  x24, x0
    cbz  x21, Lpl_attrs
    CLS  Ls_NSColor
    MSG0 Ls_blackColor
    mov  x24, x0
Lpl_attrs:
    mov  x0, x23
    mov  x1, x24
    bl   _dict2
    mov  x23, x0
    CLS  Ls_NSAttributedString
    MSG0 Ls_alloc
    mov  x2, x22
    mov  x3, x23
    MSG2 Ls_initWithStringAttributes
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setAttributedTitle
Lpl_done:
    mov  x0, x19
    LEAVE 32

// void _card_scroll(id docview, long 0xRRGGBB) — its scroll view becomes a rounded card
.globl _card_scroll
_card_scroll:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    MSG0 Ls_enclosingScrollView
    mov  x21, x0
    cbz  x21, Lcs_done
    mov  x2, #0                       // NSNoBorder
    MSG1 Ls_setBorderType
    mov  x0, x20
    bl   _rgb
    mov  x22, x0
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_setBackgroundColor
    mov  x0, x19
    mov  x2, x22
    MSG1 Ls_setBackgroundColor
    mov  x0, x21
    mov  x1, x20
    LDD  d0, Lc_card
    bl   _card
Lcs_done:
    LEAVE 16

// id _mk_scroll(unsigned mask /*x0*/, NSRect frame /*d0-d3*/)
.globl _mk_scroll
_mk_scroll:
    ENTER 32
    mov  x19, x0
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    CLS  Ls_NSScrollView
    MSG0 Ls_alloc
    mov  x20, x0
    SELX1 Ls_initWithFrame
    mov  x0, x20
    ldp  d0, d1, [sp, #96]
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    mov  x20, x0
    mov  x2, #1
    MSG1 Ls_setHasVerticalScroller
    mov  x0, x20
    mov  x2, x19
    MSG1 Ls_setAutoresizingMask
    mov  x0, x20
    LEAVE 32

// id _mk_table(mask, int header, id parent, frame d0-d3) — table in a scroll view
.globl _mk_table
_mk_table:
    ENTER 32
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    mov  x19, x0
    mov  x20, x1
    mov  x23, x2
    mov  x0, x19
    bl   _mk_scroll
    mov  x21, x0
    mov  x2, #0                       // no border: it sits on a card
    MSG1 Ls_setBorderType
    mov  x0, x21
    mov  x2, #0
    MSG1 Ls_setDrawsBackground
    CLS  Ls_NSTableView
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithFrame
    mov  x0, x22
    LDD  d0, Lc_zero
    LDD  d1, Lc_zero
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    mov  x22, x0
    cbnz x20, Lmt_header
    mov  x0, x22
    mov  x2, #0
    MSG1 Ls_setHeaderView
Lmt_header:
    CLS  Ls_NSColor
    MSG0 Ls_clearColor
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setBackgroundColor
    mov  x0, x22
    mov  x2, #2                       // NSTableViewStyleInset: rounded selection
    MSG1 Ls_setStyle
    ADRL x8, _g_ctl
    ldr  x19, [x8]
    mov  x0, x22
    mov  x2, x19
    MSG1 Ls_setDataSource
    mov  x0, x22
    mov  x2, x19
    MSG1 Ls_setDelegate
    SELX1 Ls_setRowHeight
    mov  x0, x22
    LDD  d0, Lc_20r
    bl   _objc_msgSend
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_setDocumentView
    mov  x0, x23
    mov  x2, x21
    MSG1 Ls_addSubview
    mov  x0, x22
    LEAVE 32

// id _add_col(id table, const char *ident, const char *title /*0: none*/, double width /*d0*/)
.globl _add_col
_add_col:
    ENTER 16
    str  d0, [sp, #96]
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, x20
    bl   _nsstr
    mov  x22, x0
    CLS  Ls_NSTableColumn
    MSG0 Ls_alloc
    mov  x2, x22
    MSG1 Ls_initWithIdentifier
    mov  x22, x0
    SELX1 Ls_setWidth
    mov  x0, x22
    ldr  d0, [sp, #96]
    bl   _objc_msgSend
    mov  x0, x22
    mov  x2, #0
    MSG1 Ls_setEditable
    mov  x0, x22
    mov  x2, #1                       // NSTableColumnAutoresizingMask
    MSG1 Ls_setResizingMask
    cbz  x21, Lac_add
    mov  x0, x21
    bl   _nsstr
    mov  x23, x0
    mov  x0, x22
    MSG0 Ls_headerCell
    mov  x2, x23
    MSG1 Ls_setStringValue
Lac_add:
    mov  x0, x19
    mov  x2, x22
    MSG1 Ls_addTableColumn
    mov  x0, x22
    LEAVE 16

// id _mk_textview(id parent, unsigned mask, NSRect frame /*d0-d3*/)
_mk_textview:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    mov  x0, x20
    bl   _mk_scroll
    mov  x21, x0
    CLS  Ls_NSTextView
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithFrame
    mov  x0, x22
    LDD  d0, Lc_zero
    LDD  d1, Lc_zero
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    mov  x22, x0
    mov  x0, x22
    mov  x2, #0
    MSG1 Ls_setEditable
    SELX1 Ls_setTextContainerInset
    mov  x0, x22
    LDD  d0, Lc_10
    LDD  d1, Lc_10
    bl   _objc_msgSend
    SELX1 Ls_setMinSize
    mov  x0, x22
    LDD  d0, Lc_zero
    LDD  d1, Lc_zero
    bl   _objc_msgSend
    SELX1 Ls_setMaxSize
    mov  x0, x22
    LDD  d0, Lc_big
    LDD  d1, Lc_big
    bl   _objc_msgSend
    mov  x0, x22
    mov  x2, #1
    MSG1 Ls_setVerticallyResizable
    mov  x0, x22
    mov  x2, #0
    MSG1 Ls_setHorizontallyResizable
    mov  x0, x22
    mov  x2, #2
    MSG1 Ls_setAutoresizingMask
    mov  x0, x22
    MSG0 Ls_textContainer
    mov  x23, x0
    SELX1 Ls_setContainerSize
    mov  x0, x23
    ldr  d0, [sp, #112]
    LDD  d1, Lc_big
    bl   _objc_msgSend
    mov  x0, x23
    mov  x2, #1
    MSG1 Ls_setWidthTracksTextView
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_setDocumentView
    mov  x0, x19
    mov  x2, x21
    MSG1 Ls_addSubview
    mov  x0, x22
    LEAVE 32

// ---------------------------------------------------------------------------
// Menus
// ---------------------------------------------------------------------------
_build_menus:
    ENTER 0
    mov  x19, x0
    CLS  Ls_NSMenu
    MSG0 Ls_new
    mov  x20, x0                      // menu bar

    mov  x0, x20
    ADRL x1, Ls_title
    bl   _add_submenu
    mov  x21, x0
    mov  x0, x21
    ADRL x1, Ls_name_item
    ADRL x2, Ls_m_changeName
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_settings_item
    ADRL x2, Ls_m_showSettings
    ADRL x3, Ls_key_comma
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_quit_title
    ADRL x2, Ls_terminate
    ADRL x3, Ls_key_q
    bl   _add_item

    mov  x0, x20
    ADRL x1, Ls_edit
    bl   _add_submenu
    mov  x21, x0
    mov  x0, x21
    ADRL x1, Ls_cut_title
    ADRL x2, Ls_cut
    ADRL x3, Ls_key_x
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_copy_title
    ADRL x2, Ls_copy
    ADRL x3, Ls_key_c
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_paste_title
    ADRL x2, Ls_paste
    ADRL x3, Ls_key_v
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_selall_title
    ADRL x2, Ls_selectAll
    ADRL x3, Ls_key_a
    bl   _add_item

    mov  x0, x20
    ADRL x1, Ls_mesh_menu
    bl   _add_submenu
    mov  x21, x0
    mov  x0, x21
    ADRL x1, Ls_newroom_item
    ADRL x2, Ls_m_newRoom
    ADRL x3, Ls_key_n
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_invite_title
    ADRL x2, Ls_m_invite
    ADRL x3, Ls_key_i
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_leave_item
    ADRL x2, Ls_m_leave
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_delroom_item
    ADRL x2, Ls_m_delroom
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_listroom_item
    ADRL x2, Ls_m_listroom
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_joinroom_item
    ADRL x2, Ls_m_joinroom
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_talk_item
    ADRL x2, Ls_m_talk
    ADRL x3, Ls_key_t
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_pairhue_item
    ADRL x2, Ls_m_pairHue
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_connectst_item
    ADRL x2, Ls_m_connectST
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_connectha_item
    ADRL x2, Ls_m_connectHA
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_connectlifx_item
    ADRL x2, Ls_m_connectLIFX
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_connectgovee_item
    ADRL x2, Ls_m_connectGovee
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_pairnano_item
    ADRL x2, Ls_m_pairNano
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_refresh_item
    ADRL x2, Ls_m_refreshHome
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_scanner_title
    ADRL x2, Ls_m_showScanner
    ADRL x3, Ls_key_k
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_spin_item
    ADRL x2, Ls_m_showSpin
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_meshpass_item
    ADRL x2, Ls_m_meshPass
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_fm_item
    ADRL x2, Ls_m_fmShow
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_files_item
    ADRL x2, Ls_m_filesShow
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_share_item
    ADRL x2, Ls_m_filesChoose
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x21
    ADRL x1, Ls_airdrop_item
    ADRL x2, Ls_m_airdrop
    ADRL x3, Ls_empty
    bl   _add_item

    mov  x0, x19
    mov  x2, x20
    MSG1 Ls_setMainMenu
    LEAVE 0

// id _add_submenu(id menubar, const char *title)
_add_submenu:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    CLS  Ls_NSMenuItem
    MSG0 Ls_new
    mov  x21, x0
    mov  x0, x19
    mov  x2, x21
    MSG1 Ls_addItem
    mov  x0, x20
    bl   _nsstr
    mov  x22, x0
    CLS  Ls_NSMenu
    MSG0 Ls_alloc
    mov  x2, x22
    MSG1 Ls_initWithTitle1
    mov  x23, x0
    mov  x0, x21
    mov  x2, x23
    MSG1 Ls_setSubmenu
    mov  x0, x23
    LEAVE 0

// id _add_item(id menu, const char *title, const char *selname, const char *key)
//   Our own actions are aimed at the controller; the rest go up the responder chain.
_add_item:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x0, x21
    bl   _sel_registerName
    mov  x21, x0
    mov  x0, x20
    bl   _nsstr
    mov  x20, x0
    mov  x0, x22
    bl   _nsstr
    mov  x22, x0
    CLS  Ls_NSMenuItem
    MSG0 Ls_alloc
    mov  x2, x20
    mov  x3, x21
    mov  x4, x22
    MSG3 Ls_initWithTitle3
    mov  x23, x0
    ADRL x8, _g_ctl
    ldr  x0, [x8]
    mov  x2, x21
    MSG1 Ls_respondsToSelector
    tst  w0, #0xff
    b.eq Lai_add
    mov  x0, x23
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    MSG1 Ls_setTarget
Lai_add:
    mov  x0, x19
    mov  x2, x23
    MSG1 Ls_addItem
    mov  x0, x23
    LEAVE 0

// ---------------------------------------------------------------------------
// Menu-bar item: icon + linked count; menu with status, Show, Scanner, Quit
// ---------------------------------------------------------------------------
_build_status_item:
    ENTER 0
    CLS  Ls_NSStatusBar
    MSG0 Ls_systemStatusBar
    mov  x19, x0
    SELX1 Ls_statusItemWithLength
    mov  x0, x19
    LDD  d0, Lc_varlen
    bl   _objc_msgSend
    MSG0 Ls_retain
    mov  x20, x0
    ADRL x8, _g_sitem
    str  x20, [x8]
    MSG0 Ls_button
    mov  x21, x0

    ADRL x0, Ls_sym_mesh
    bl   _symbol_image
    cbnz x0, Lsi_img
    ADRL x0, Ls_sym_fallback
    bl   _symbol_image
    cbz  x0, Lsi_noimg
Lsi_img:
    mov  x22, x0
    mov  x2, #1
    MSG1 Ls_setTemplate
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_setImage
    mov  x0, x21
    mov  x2, #2                       // NSImageLeft
    MSG1 Ls_setImagePosition
    b    Lsi_menu
Lsi_noimg:
    ADRL x0, Ls_title
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setTitle
Lsi_menu:
    CLS  Ls_NSMenu
    MSG0 Ls_new
    mov  x22, x0

    ADRL x0, Ls_status0
    bl   _nsstr
    mov  x23, x0
    ADRL x0, Ls_empty
    bl   _nsstr
    mov  x24, x0
    CLS  Ls_NSMenuItem
    MSG0 Ls_alloc
    mov  x2, x23
    mov  x3, #0
    mov  x4, x24
    MSG3 Ls_initWithTitle3
    mov  x23, x0
    mov  x0, x22
    mov  x2, x23
    MSG1 Ls_addItem
    ADRL x8, _g_sinfo
    str  x23, [x8]

    CLS  Ls_NSMenuItem
    MSG0 Ls_separatorItem
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_addItem

    mov  x0, x22
    ADRL x1, Ls_show_title
    ADRL x2, Ls_m_showMain
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x22
    ADRL x1, Ls_scanner_title
    ADRL x2, Ls_m_showScanner
    ADRL x3, Ls_empty
    bl   _add_item
    mov  x0, x22
    ADRL x1, Ls_quit_title
    ADRL x2, Ls_terminate
    ADRL x3, Ls_empty
    bl   _add_item

    mov  x0, x20
    mov  x2, x22
    MSG1 Ls_setMenu
    LEAVE 0

// id _symbol_image(const char *name) -> NSImage for an SF Symbol, or nil
.globl _symbol_image
_symbol_image:
    ENTER 0
    bl   _nsstr
    mov  x19, x0
    CLS  Ls_NSImage
    mov  x2, x19
    mov  x3, #0
    MSG2 Ls_imageWithSymbol
    LEAVE 0

// void _tooltip(id view, const char *utf8)
_tooltip:
    ENTER 0
    mov  x19, x0
    mov  x0, x1
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setToolTip
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lc_r18:      .double 18.0
Lc_20r:      .double 26.0
Lc_colw:     .double 236.0

.section __TEXT,__cstring,cstring_literals
Ls_selftest_flag:      .asciz "--selftest"
Ls_NSApplication:      .asciz "NSApplication"
Ls_NSObject:           .asciz "NSObject"
Ls_NSWindow:           .asciz "NSWindow"
Ls_NSScrollView:       .asciz "NSScrollView"
Ls_NSTextView:         .asciz "NSTextView"
Ls_NSTextField:        .asciz "NSTextField"
Ls_NSTableView:        .asciz "NSTableView"
Ls_NSTableColumn:      .asciz "NSTableColumn"
Ls_NSButton:           .asciz "NSButton"
Ls_NSFont:             .asciz "NSFont"
Ls_NSColor:            .asciz "NSColor"
Ls_NSDictionary:       .asciz "NSDictionary"
Ls_NSMenu:             .asciz "NSMenu"
Ls_NSMenuItem:         .asciz "NSMenuItem"
Ls_NSStatusBar:        .asciz "NSStatusBar"
Ls_NSImage:            .asciz "NSImage"
Ls_ctl_name:           .asciz "AMeshController"

Ls_sharedApplication:  .asciz "sharedApplication"
Ls_run:                .asciz "run"
Ls_setActivationPolicy: .asciz "setActivationPolicy:"
Ls_setDelegate:        .asciz "setDelegate:"
Ls_new:                .asciz "new"
Ls_alloc:              .asciz "alloc"
Ls_retain:             .asciz "retain"
Ls_systemFontOfSize:   .asciz "systemFontOfSize:"
Ls_boldSystemFontOfSize: .asciz "boldSystemFontOfSize:"
Ls_labelColor:         .asciz "labelColor"
Ls_secondaryLabelColor: .asciz "secondaryLabelColor"
Ls_colorWithSRGB:      .asciz "colorWithSRGBRed:green:blue:alpha:"
Ls_dictWithObjectsForKeys: .asciz "dictionaryWithObjects:forKeys:count:"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_setTitle:           .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_setContentMinSize:  .asciz "setContentMinSize:"
Ls_center:             .asciz "center"
Ls_contentView:        .asciz "contentView"
Ls_labelWithString:    .asciz "labelWithString:"
Ls_setFrame:           .asciz "setFrame:"
Ls_setFont:            .asciz "setFont:"
Ls_setLineBreakMode:   .asciz "setLineBreakMode:"
Ls_setTextColor:       .asciz "setTextColor:"
Ls_setAutoresizingMask: .asciz "setAutoresizingMask:"
Ls_addSubview:         .asciz "addSubview:"
Ls_initWithFrame:      .asciz "initWithFrame:"
Ls_setTarget:          .asciz "setTarget:"
Ls_setAction:          .asciz "setAction:"
Ls_buttonWithTitle:    .asciz "buttonWithTitle:target:action:"
Ls_setBorderType:      .asciz "setBorderType:"
Ls_setHeaderView:      .asciz "setHeaderView:"
Ls_setDataSource:      .asciz "setDataSource:"
Ls_setRowHeight:       .asciz "setRowHeight:"
Ls_initWithIdentifier: .asciz "initWithIdentifier:"
Ls_setWidth:           .asciz "setWidth:"
Ls_setEditable:        .asciz "setEditable:"
Ls_setResizingMask:    .asciz "setResizingMask:"
Ls_headerCell:         .asciz "headerCell"
Ls_setStringValue:     .asciz "setStringValue:"
Ls_addTableColumn:     .asciz "addTableColumn:"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_makeFirstResponder: .asciz "makeFirstResponder:"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_addItem:            .asciz "addItem:"
Ls_setSubmenu:         .asciz "setSubmenu:"
Ls_setMainMenu:        .asciz "setMainMenu:"
Ls_initWithTitle1:     .asciz "initWithTitle:"
Ls_initWithTitle3:     .asciz "initWithTitle:action:keyEquivalent:"
Ls_respondsToSelector: .asciz "respondsToSelector:"
Ls_setHasVerticalScroller: .asciz "setHasVerticalScroller:"
Ls_setTextContainerInset: .asciz "setTextContainerInset:"
Ls_setMinSize:         .asciz "setMinSize:"
Ls_setMaxSize:         .asciz "setMaxSize:"
Ls_setVerticallyResizable: .asciz "setVerticallyResizable:"
Ls_setHorizontallyResizable: .asciz "setHorizontallyResizable:"
Ls_textContainer:      .asciz "textContainer"
Ls_setContainerSize:   .asciz "setContainerSize:"
Ls_setWidthTracksTextView: .asciz "setWidthTracksTextView:"
Ls_setDocumentView:    .asciz "setDocumentView:"
Ls_systemStatusBar:    .asciz "systemStatusBar"
Ls_statusItemWithLength: .asciz "statusItemWithLength:"
Ls_button:             .asciz "button"
Ls_setTemplate:        .asciz "setTemplate:"
Ls_setImage:           .asciz "setImage:"
Ls_setImagePosition:   .asciz "setImagePosition:"
Ls_separatorItem:      .asciz "separatorItem"
Ls_setMenu:            .asciz "setMenu:"
Ls_imageWithSymbol:    .asciz "imageWithSystemSymbolName:accessibilityDescription:"
Ls_sym_mesh:           .asciz "point.3.connected.trianglepath.dotted"
Ls_sym_fallback:       .asciz "antenna.radiowaves.left.and.right"

// controller selectors and type encodings
Ls_m_reopen:           .asciz "applicationShouldHandleReopen:hasVisibleWindows:"
Ls_m_showMain:         .asciz "showMain:"
Ls_m_send:             .asciz "sendMessage:"
Ls_m_newRoom:          .asciz "newRoom:"
Ls_m_invite:           .asciz "inviteSelected:"
Ls_m_leave:            .asciz "leaveRoom:"
Ls_m_delroom:          .asciz "deleteRoom:"
Ls_delroom_item:       .asciz "Delete Room\342\200\246"
Ls_m_listroom:         .asciz "listRoom:"
Ls_m_joinroom:         .asciz "joinRoom:"
Ls_listroom_item:      .asciz "List This Room for Everyone (on/off)"
Ls_joinroom_item:      .asciz "Ask to Join a Room\342\200\246"
Ls_m_changeName:       .asciz "changeName:"
Ls_m_showScanner:      .asciz "showScanner:"
Ls_m_showSettings:     .asciz "showSettings:"
Ls_m_svcToggled:       .asciz "serviceToggled:"
Ls_m_showSpin:         .asciz "showSpin:"
Ls_m_spinTab:          .asciz "spinTab:"
Ls_m_spinName:         .asciz "spinName:"
Ls_m_spinEnable:       .asciz "spinEnable:"
Ls_m_spinDevices:      .asciz "spinDevices:"
Ls_m_spinAdd:          .asciz "spinAddDevice:"
Ls_m_spinAction:       .asciz "spinAction:"
Ls_m_spinText:         .asciz "spinText:"
Ls_m_spinLock:         .asciz "spinLock:"
Ls_m_spinTest:         .asciz "spinTest:"
Ls_spin_item:          .asciz "SPIN Remote\342\200\246"
Ls_settings_item:      .asciz "Settings\342\200\246"
Ls_services_title:     .asciz "Services"
Ls_key_comma:          .asciz ","
Ls_NSAppearance:       .asciz "NSAppearance"
Ls_appearanceNamed:    .asciz "appearanceNamed:"
Ls_setAppearance:      .asciz "setAppearance:"
Ls_setTitlebarAppearsTransparent: .asciz "setTitlebarAppearsTransparent:"
Ls_setBackgroundColor: .asciz "setBackgroundColor:"
Ls_setBezelStyle:      .asciz "setBezelStyle:"
Ls_setBezelColor:      .asciz "setBezelColor:"
Ls_sel_title:          .asciz "title"
Ls_whiteColor:         .asciz "whiteColor"
Ls_blackColor:         .asciz "blackColor"
Ls_clearColor:         .asciz "clearColor"
Ls_NSAttributedString: .asciz "NSAttributedString"
Ls_initWithStringAttributes: .asciz "initWithString:attributes:"
Ls_setAttributedTitle: .asciz "setAttributedTitle:"
Ls_enclosingScrollView: .asciz "enclosingScrollView"
Ls_setDrawsBackground: .asciz "setDrawsBackground:"
Ls_setStyle:           .asciz "setStyle:"
Ls_fontDescriptor:     .asciz "fontDescriptor"
Ls_fontDescriptorWithDesign: .asciz "fontDescriptorWithDesign:"
Ls_fontWithDescriptorSize: .asciz "fontWithDescriptor:size:"
Ls_m_tick:             .asciz "tick:"
Ls_m_rows:             .asciz "numberOfRowsInTableView:"
Ls_m_value:            .asciz "tableView:objectValueForTableColumn:row:"
Ls_m_selChanged:       .asciz "tableViewSelectionDidChange:"
Ls_m_cmState:          .asciz "centralManagerDidUpdateState:"
Ls_m_cmDiscover:       .asciz "centralManager:didDiscoverPeripheral:advertisementData:RSSI:"
Ls_m_cmConnect:        .asciz "centralManager:didConnectPeripheral:"
Ls_m_cmFail:           .asciz "centralManager:didFailToConnectPeripheral:error:"
Ls_m_cmDisconn:        .asciz "centralManager:didDisconnectPeripheral:error:"
Ls_m_pServices:        .asciz "peripheral:didDiscoverServices:"
Ls_m_pChars:           .asciz "peripheral:didDiscoverCharacteristicsForService:error:"
Ls_m_pValue:           .asciz "peripheral:didUpdateValueForCharacteristic:error:"
Ls_m_pRSSI:            .asciz "peripheral:didReadRSSI:error:"
Ls_m_pModify:          .asciz "peripheral:didModifyServices:"
Ls_m_pmState:          .asciz "peripheralManagerDidUpdateState:"
Ls_m_pmAdded:          .asciz "peripheralManager:didAddService:error:"
Ls_m_pmAdv:            .asciz "peripheralManagerDidStartAdvertising:error:"
Ls_m_pmRead:           .asciz "peripheralManager:didReceiveReadRequest:"
Ls_m_pmWrites:         .asciz "peripheralManager:didReceiveWriteRequests:"
Ls_ty_reopen:          .asciz "B@:@B"
Ls_ty_rows:            .asciz "q@:@"
Ls_ty_value:           .asciz "@@:@@q"
Ls_ty_v1:              .asciz "v@:@"
Ls_ty_v2:              .asciz "v@:@@"
Ls_ty_v3:              .asciz "v@:@@@"
Ls_ty_v4:              .asciz "v@:@@@@"
Ls_p_app:              .asciz "NSApplicationDelegate"
Ls_p_cm:               .asciz "CBCentralManagerDelegate"
Ls_p_p:                .asciz "CBPeripheralDelegate"
Ls_p_pm:               .asciz "CBPeripheralManagerDelegate"
Ls_p_tds:              .asciz "NSTableViewDataSource"
Ls_p_tdl:              .asciz "NSTableViewDelegate"
Ls_p_url:              .asciz "NSURLSessionDataDelegate"
Ls_p_nsb:              .asciz "NSNetServiceBrowserDelegate"
Ls_p_ns:               .asciz "NSNetServiceDelegate"
Ls_p_speech:           .asciz "SFSpeechRecognitionTaskDelegate"
Ls_m_talk:             .asciz "talk:"
Ls_m_connectST:        .asciz "connectSmartThings:"
Ls_m_pairHue:          .asciz "pairHue:"
Ls_m_meshPass:         .asciz "meshPassphrase:"
Ls_m_fmShow:           .asciz "fmShow:"
Ls_m_fmApply:          .asciz "fmApply:"
Ls_m_fmTest:           .asciz "fmTest:"
Ls_fm_item:            .asciz "FM Radio\342\200\246"
Ls_meshpass_item:      .asciz "Mesh Passphrase\342\200\246"
Ls_m_connectHA:        .asciz "connectHomeAssistant:"
Ls_m_connectLIFX:      .asciz "connectLIFX:"
Ls_m_connectGovee:     .asciz "connectGovee:"
Ls_m_pairNano:         .asciz "pairNanoleaf:"
Ls_m_refreshHome:      .asciz "refreshDevices:"
Ls_m_scanPair:         .asciz "scanConnectPair:"
Ls_m_scanSetUp:        .asciz "scanSetUp:"
Ls_m_scanBT:           .asciz "scanBluetoothSettings:"
Ls_connectha_item:     .asciz "Connect Home Assistant\342\200\246"
Ls_connectlifx_item:   .asciz "Connect LIFX\342\200\246"
Ls_connectgovee_item:  .asciz "Connect Govee\342\200\246"
Ls_pairnano_item:      .asciz "Pair Nanoleaf"
Ls_refresh_item:       .asciz "Look for Devices Again"
Ls_m_netData:          .asciz "URLSession:dataTask:didReceiveData:"
Ls_m_netDone:          .asciz "URLSession:task:didCompleteWithError:"
Ls_m_bonjourFound:     .asciz "netServiceBrowser:didFindService:moreComing:"
Ls_m_resolved:         .asciz "netServiceDidResolveAddress:"
Ls_m_speechHyp:        .asciz "speechRecognitionTask:didHypothesizeTranscription:"
Ls_m_speechFinal:      .asciz "speechRecognitionTask:didFinishRecognition:"
Ls_m_locUpdate:        .asciz "locationManager:didUpdateLocations:"
Ls_m_locFail:          .asciz "locationManager:didFailWithError:"
Ls_m_filesShow:        .asciz "filesShow:"
Ls_m_filesChoose:      .asciz "filesChoose:"
Ls_m_airdrop:          .asciz "airdropFile:"
Ls_files_item:         .asciz "Files on Wi-Fi\342\200\246"
Ls_share_item:         .asciz "Share Folders on Wi-Fi\342\200\246"
Ls_airdrop_item:       .asciz "AirDrop a File\342\200\246"
Ls_m_speechDone:       .asciz "speechRecognitionTask:didFinishSuccessfully:"
Ls_ty_found:           .asciz "v@:@@B"
Ls_ty_vB:              .asciz "v@:@B"
Ls_talk_title:         .asciz "\360\237\216\244 Talk"
Ls_talk_item:          .asciz "Talk"
Ls_pairhue_item:       .asciz "Pair Hue Bridge"
Ls_connectst_item:     .asciz "Connect SmartThings\342\200\246"
Ls_key_t:              .asciz "t"

// menus
Ls_edit:               .asciz "Edit"
Ls_mesh_menu:          .asciz "Mesh"
Ls_name_item:          .asciz "Change Name\342\200\246"
Ls_newroom_item:       .asciz "New Room\342\200\246"
Ls_leave_item:         .asciz "Leave Room"
Ls_quit_title:         .asciz "Quit asmmesh"
Ls_show_title:         .asciz "Show asmmesh"
Ls_terminate:          .asciz "terminate:"
Ls_cut_title:          .asciz "Cut"
Ls_cut:                .asciz "cut:"
Ls_copy_title:         .asciz "Copy"
Ls_copy:               .asciz "copy:"
Ls_paste_title:        .asciz "Paste"
Ls_paste:              .asciz "paste:"
Ls_selall_title:       .asciz "Select All"
Ls_selectAll:          .asciz "selectAll:"
Ls_key_q:              .asciz "q"
Ls_key_x:              .asciz "x"
Ls_key_c:              .asciz "c"
Ls_key_v:              .asciz "v"
Ls_key_a:              .asciz "a"
Ls_key_n:              .asciz "n"
Ls_key_i:              .asciz "i"
Ls_key_k:              .asciz "k"

// text
Ls_title:              .asciz "asmmesh"
Ls_rooms_lbl:          .asciz "ROOMS"
Ls_people_lbl:         .asciz "PEOPLE ON THE MESH"
Ls_plus:               .asciz "+"
Ls_invite_title:       .asciz "Invite to Chat"
Ls_scanner_title:      .asciz "Mesh Scanner"
Ls_send_title:         .asciz "Send"
Ls_talk_tip:           .asciz "Talk (\342\214\230T)"
Ls_y_send:             .asciz "arrow.up"
Ls_y_mic:              .asciz "mic.fill"
Ls_setToolTip:         .asciz "setToolTip:"
Ls_setContentSize:     .asciz "setContentSize:"
Ls_setBezeled:         .asciz "setBezeled:"
Ls_setBordered:        .asciz "setBordered:"
Ls_setFocusRingType:   .asciz "setFocusRingType:"
Ls_col_main:           .asciz "main"
Ls_status0:            .asciz "Starting Bluetooth\342\200\246"
Ls_NSBundle:           .asciz "NSBundle"
Ls_mainBundle:         .asciz "mainBundle"
Ls_CFBundleVersion:    .asciz "CFBundleVersion"
Ls_objectForInfoKey:   .asciz "objectForInfoDictionaryKey:"
Ls_UTF8String_b:       .asciz "UTF8String"
Ls_qmark:              .asciz "?"
Ls_fmt_welcome:        .asciz "\302\267 asmmesh 0.8 (build %2$s) \342\200\224 you are \342\200\234%1$s\342\200\235. Main is open to everyone on the mesh; make a room with + and invite people from the list."

Ls_empty:              .asciz ""
