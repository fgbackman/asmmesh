// ios_ui.s — asmmesh on iPhone: the same assembly core as the Mac app, with this
// file in place of the Mac's window code (main.s, ui.s, scanner.s). SwiftUI draws
// the screens; it calls the am_* functions below, and the core calls back into
// Swift through the ios_* hooks (room lines, list changes, the status line).
//
// Dialogs: the core shows its prompts with NSAlert and NSTextField, as on the Mac.
// iOS has neither, so the Swift side registers small classes under those names
// that present a UIAlertController and wait for the answer (Bridge.swift). That
// keeps every prompt in the core — Join / Not now, Allow for 10 minutes, connect
// SmartThings, confirm unlocking — working unchanged.
//
// Built only for iOS (the Xcode project in ios/); the Mac build never sees it.

.include "macros.inc"

.data
.p2align 3
.globl _g_ctl
_g_ctl:         .quad 0               // the delegate object (CoreBluetooth, URLs, Bonjour...)
.globl _g_window
_g_window:      .quad 0               // 1 once the app is up (the core only tests it)
.globl _g_field
_g_field:       .quad 0               // Swift's text field stand-in (voice writes into it)
.globl _g_tick
_g_tick:        .quad 0               // tenths of a second since launch
_g_ios_sel:     .quad -1              // the person picked for Invite
// what the web code reads from the Mac's FM radio: never running here
.globl _fm_envp
_fm_envp:       .quad 0
.globl _g_fm_running
_g_fm_running:  .quad 0
.globl _g_fm_baud
_g_fm_baud:     .quad 2400
.zerofill __DATA,__bss,_g_ios_buf,512,4

.section __TEXT,__const
.p2align 3
Lf_acc:      .double 0.0, 0.0, 280.0, 24.0

// Controller methods: what CoreBluetooth, NSURLSession, Bonjour, Speech and
// CoreLocation call. Selector name, IMP, type encoding. Zero-terminated.
.section __DATA,__const
.p2align 3
Lmethods:
    .quad Li_m_cmState,     _ble_cm_state,      Li_ty_v1
    .quad Li_m_cmDiscover,  _g_ble_cm_discover,   Li_ty_v4
    .quad Li_m_cmConnect,   _ble_cm_connect,    Li_ty_v2
    .quad Li_m_cmFail,      _ble_cm_lost,       Li_ty_v3
    .quad Li_m_cmDisconn,   _ble_cm_lost,       Li_ty_v3
    .quad Li_m_pServices,   _ble_p_services,    Li_ty_v2
    .quad Li_m_pChars,      _ble_p_chars,       Li_ty_v3
    .quad Li_m_pValue,      _g_ble_p_value,       Li_ty_v3
    .quad Li_m_pRSSI,       _ble_p_rssi,        Li_ty_v3
    .quad Li_m_pModify,     _ble_p_modify,      Li_ty_v2
    .quad Li_m_pmState,     _ble_pm_state,      Li_ty_v1
    .quad Li_m_pmAdded,     _ble_pm_added,      Li_ty_v3
    .quad Li_m_pmAdv,       _ble_pm_adv,        Li_ty_v2
    .quad Li_m_pmRead,      _ble_pm_read,       Li_ty_v2
    .quad Li_m_pmWrites,    _g_ble_pm_writes,     Li_ty_v2
    .quad Li_m_netData,     _net_data,          Li_ty_v3
    .quad Li_m_netDone,     _net_done,          Li_ty_v3
    .quad Li_m_bonjourFound, _lan_found,        Li_ty_found
    .quad Li_m_resolved,    _lan_resolved,      Li_ty_v1
    .quad Li_m_speechHyp,   _voice_hyp,         Li_ty_v2
    .quad Li_m_speechFinal, _voice_final,       Li_ty_v2
    .quad Li_m_speechDone,  _voice_done,        Li_ty_vB
    .quad Li_m_locUpdate,   _al_cl_update,      Li_ty_v2
    .quad Li_m_locFail,     _al_cl_fail,        Li_ty_v2
    .quad 0, 0, 0

Lprotos:
    .quad Li_p_cm, Li_p_p, Li_p_pm, Li_p_url, Li_p_nsb, Li_p_ns, Li_p_speech, Li_p_loc
    .quad 0

.text
.p2align 2

// ===========================================================================
// Starting up, and the heartbeat
// ===========================================================================

// void am_start(void) — called once by Swift, after its hooks are ready
.globl _am_start
_am_start:
    ENTER 0
    bl   _mesh_init
    bl   _rooms_init
    bl   _make_controller
    ADRL x8, _g_ctl
    str  x0, [x8]
    ADRL x8, _g_window                // from now on prompts may be shown
    mov  x9, #1
    str  x9, [x8]
    mov  x0, #0
    bl   _ui_select_room
    bl   _app_build
    mov  x2, x0
    ADRL x0, Li_fmt_welcome
    ADRL x1, _g_nick
    bl   _chat_fmt
    bl   _ble_start
    LDGOT x0, __dispatch_main_q       // Home starts after the first screen is up
    mov  x1, #0
    ADRL x2, _home_init
    bl   _dispatch_async_f
    LEAVE 0

// void am_tick(void) — every tenth of a second (a Swift timer)
.globl _am_tick
_am_tick:
    ENTER 0
    ADRL x8, _g_tick
    ldr  x19, [x8]
    add  x19, x19, #1
    str  x19, [x8]
    bl   _voice_tick
    bl   _udp_poll
    mov  x9, #10
    udiv x20, x19, x9
    msub x10, x20, x9, x19
    cbnz x10, Lat_hello
    bl   _ble_read_rssi_all
    bl   _ui_lists_changed
    bl   _alerts_tick
    mov  x0, x20
    bl   _sens_tick
    mov  x0, x20
    bl   _hue_tick
    mov  x0, x20
    bl   _udp_tick
    bl   _near_tick
    mov  x0, x20
    bl   _rules_tick
Lat_hello:
    mov  x9, #150                     // first HELLO 2 s after launch, then every 15 s
    udiv x10, x19, x9
    msub x10, x10, x9, x19
    cmp  x10, #20
    b.ne Lat_done
    bl   _mesh_send_hello
Lat_done:
    LEAVE 0

// id _make_controller(void) — builds, registers and instantiates AMeshController
_make_controller:
    ENTER 0
    CLS  Li_NSObject
    ADRL x1, Li_ctl_name
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
    MSG0 Li_new
    LEAVE 0

// const char *_app_build(void) — this app's build number (CFBundleVersion), or "?"
.globl _app_build
_app_build:
    ENTER 0
    CLS  Li_NSBundle
    MSG0 Li_mainBundle
    cbz  x0, 1f
    mov  x19, x0
    ADRL x0, Li_CFBundleVersion
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Li_objectForInfoKey
    cbz  x0, 1f
    MSG0 Li_UTF8String
    cbnz x0, 2f
1:  ADRL x0, Li_qmark
2:  LEAVE 0

// ===========================================================================
// What the core calls: transcripts, lists, status (hooks into Swift)
// ===========================================================================

// void _room_line(long room, const char *utf8, int sys) — "HH:MM:SS  text" for that
//   room; a line in a room you aren't looking at bumps its unread count
.globl _room_line
_room_line:
    ENTER 1136
    // locals: [96] time_t   [112] struct tm (64)   [176] ts[32]   [208] buf[1024]
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x0, sp, #96
    bl   _time
    add  x0, sp, #96
    add  x1, sp, #112
    bl   _localtime_r
    add  x0, sp, #176
    mov  x1, #32
    ADRL x2, Li_timefmt
    add  x3, sp, #112
    bl   _strftime
    add  x0, sp, #208
    mov  x1, #1024
    ADRL x2, Li_linefmt
    add  x8, sp, #176
    str  x8, [sp]
    str  x20, [sp, #8]
    bl   _snprintf
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lrl_done
    ADRL x8, _g_rooms
    add  x22, x8, x19, lsl #ROOM_SHIFT
    ldr  x0, [x22, #R_ID]
    add  x1, sp, #208
    mov  x2, x21
    bl   _ios_room_line
    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    cmp  x9, x19
    b.eq Lrl_done
    ldr  x9, [x22, #R_UNREAD]
    add  x9, x9, #1
    str  x9, [x22, #R_UNREAD]
    bl   _ui_rooms_changed
Lrl_done:
    LEAVE 1136

// void _ui_select_room(long room)
.globl _ui_select_room
_ui_select_room:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x19, x9
    csel x19, xzr, x19, hs
    ADRL x8, _g_cur_room
    str  x19, [x8]
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    str  xzr, [x8, #R_UNREAD]
    mov  x0, x19
    bl   _ios_select_room
    LEAVE 0

// void _ui_rooms_changed(void)
.globl _ui_rooms_changed
_ui_rooms_changed:
    mov  x0, #1
    b    _ios_refresh

// void _ui_lists_changed(void) — people, nearby, status
.globl _ui_lists_changed
_ui_lists_changed:
    mov  x0, #2
    b    _ios_refresh

// void _ui_update_status(void)
.globl _ui_update_status
_ui_update_status:
    mov  x0, #2
    b    _ios_refresh

// void _ui_update_name(void)
.globl _ui_update_name
_ui_update_name:
    mov  x0, #3
    b    _ios_refresh

// void _ui_set_status(const char *utf8)
.globl _ui_set_status
_ui_set_status:
    b    _ios_status

// - (void)showMain:(id)sender — the app is already in front on iPhone
.globl _ui_show
_ui_show:
    ret

// void _scan_say(const char *fmt, a, b) — a line in Home (the Mac also shows it
//   under the scanner)
.globl _scan_say
_scan_say:
    ENTER 0
    mov  x4, x2
    mov  x3, x1
    mov  x2, x0
    ADRL x0, _g_ios_buf
    mov  x1, #320
    bl   _sfmt
    ADRL x0, _g_ios_buf
    bl   _home_say0
    LEAVE 0

// - (void)inviteSelected:(id)sender, with the person chosen in Swift (_g_ios_sel)
//   (from Main, a new room "Fred & Anna" is made for the two of you)
_ui_invite:
    ENTER 64                          // [96] room name
    ADRL x8, _g_ios_sel
    ldr  x19, [x8]
    tbnz x19, #63, Liv_pick
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Liv_pick
    ADRL x8, _g_cur_room
    ldr  x20, [x8]
    ADRL x8, _g_rooms
    add  x9, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, [x9, #R_ID]
    sub  x9, x9, #1                   // from a local room: invite as if from Main
    cmp  x9, #(LOCAL_ROOMS - 2)
    b.hi Liv_notHome
    mov  x20, #0
Liv_notHome:
    cbnz x20, Liv_send
    ADRL x8, _g_nodes
    add  x0, x8, x19, lsl #NODE_SHIFT
    bl   _node_name
    str  x0, [sp, #8]
    ADRL x9, _g_nick
    str  x9, [sp]
    add  x0, sp, #96
    mov  x1, #(ROOMNAME_MAX + 1)
    ADRL x2, Ls_pair_fmt
    bl   _snprintf
    add  x0, sp, #96
    bl   _utf8_fix
    bl   _new_id
    add  x1, sp, #96
    mov  x2, #1
    bl   _room_add
    mov  x20, x0
    tbnz x20, #63, Liv_full
    mov  x0, x20
    bl   _room_own
    mov  x0, x20
    bl   _ui_select_room
    bl   _ui_rooms_changed
Liv_send:
    mov  x0, x19
    mov  x1, x20
    bl   _mesh_send_invite
    mov  x21, x0
    tbnz x21, #63, Liv_nokey
    ADRL x8, _g_nodes
    add  x0, x8, x19, lsl #NODE_SHIFT
    bl   _node_name
    mov  x3, x0
    ADRL x2, Ls_fmt_invited
    ADRL x8, Ls_fmt_invited_held
    cmp  x21, #0
    csel x2, x8, x2, eq
    mov  x0, x20
    mov  x1, #1
    bl   _room_fmt
    LEAVE 64
Liv_nokey:                            // no hello from them yet: we can't seal it for them
    ADRL x8, _g_nodes
    add  x0, x8, x19, lsl #NODE_SHIFT
    bl   _node_name
    mov  x3, x0
    mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_fmt_invite_nokey
    bl   _room_fmt
    LEAVE 64
Liv_pick:
    ADRL x0, Ls_pick_msg
    ADRL x1, Li_pick_info
    ADRL x2, Ls_ok
    mov  x3, #0
    mov  x4, #0
    bl   _alert_run
    LEAVE 64
Liv_full:
    ADRL x0, Ls_full_msg
    ADRL x1, Ls_full_info
    ADRL x2, Ls_ok
    mov  x3, #0
    mov  x4, #0
    bl   _alert_run
    LEAVE 64

// ===========================================================================
// What Swift calls (am_*): plain C functions
// ===========================================================================

// rooms
.globl _am_room_count
_am_room_count:
    ADRL x8, _g_room_count
    ldr  x0, [x8]
    ret

// uint64 am_room_id(long i)
.globl _am_room_id
_am_room_id:
    ADRL x8, _g_rooms
    add  x8, x8, x0, lsl #ROOM_SHIFT
    ldr  x0, [x8, #R_ID]
    ret

// const char *am_room_name(long i)
.globl _am_room_name
_am_room_name:
    ADRL x8, _g_rooms
    add  x8, x8, x0, lsl #ROOM_SHIFT
    add  x0, x8, #R_NAME
    ret

// long am_room_unread(long i)
.globl _am_room_unread
_am_room_unread:
    ADRL x8, _g_rooms
    add  x8, x8, x0, lsl #ROOM_SHIFT
    ldr  x0, [x8, #R_UNREAD]
    ret

// long am_room_mine(long i) — 1 if this phone made the room
.globl _am_room_mine
_am_room_mine:
    ADRL x8, _g_rooms
    add  x8, x8, x0, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_OWNER]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    cset x0, eq
    ret

// long am_cur_room(void)
.globl _am_cur_room
_am_cur_room:
    ADRL x8, _g_cur_room
    ldr  x0, [x8]
    ret

// void am_select_room(long i)
.globl _am_select_room
_am_select_room:
    b    _ui_select_room

// void am_send(const char *text) — what you typed in the current room
.globl _am_send
_am_send:
    ENTER 0
    cbz  x0, Las_done
    ldrb w9, [x0]
    cbz  w9, Las_done
    bl   _mesh_send_text
    bl   _ui_rooms_changed
Las_done:
    LEAVE 0

// void am_home(const char *text) — a Home command from a button ("batteries",
//   "name sensor 2 bedroom"), whichever room is showing
.globl _am_home
_am_home:
    mov  w1, #0
    b    _home_command

// people on the mesh
.globl _am_node_count
_am_node_count:
    ADRL x8, _g_node_count
    ldr  x0, [x8]
    ret

// const char *am_node_nick(long i)
.globl _am_node_nick
_am_node_nick:
    ADRL x8, _g_nodes
    add  x0, x8, x0, lsl #NODE_SHIFT
    b    _node_name

// long am_node_info(long i, long k) — 0 hops, 1 signal dBm (0 unknown), 2 seconds
//   since last heard, 3 relayed for us
.globl _am_node_info
_am_node_info:
    ENTER 0
    ADRL x8, _g_nodes
    add  x19, x8, x0, lsl #NODE_SHIFT
    cmp  x1, #0
    b.ne 1f
    ldr  x0, [x19, #N_HOPS]
    LEAVE 0
1:  cmp  x1, #1
    b.ne 2f
    ldr  x0, [x19, #N_RSSI]
    LEAVE 0
2:  cmp  x1, #2
    b.ne 3f
    mov  x0, #0
    bl   _time
    ldr  x9, [x19, #N_SEEN]
    sub  x0, x0, x9
    LEAVE 0
3:  ldr  x0, [x19, #N_RELAYED]
    LEAVE 0

// char *am_node_fp(long i, char *buf /*12*/) — "A1B2-C3D4"; i = -1 for this phone
.globl _am_node_fp
_am_node_fp:
    tbnz x0, #63, 1f
    ADRL x8, _g_nodes
    add  x8, x8, x0, lsl #NODE_SHIFT
    ldr  x0, [x8, #N_ID]
    b    _fp
1:  ADRL x8, _g_node_id
    ldr  x0, [x8]
    b    _fp

// const char *am_nick(void)
.globl _am_nick
_am_nick:
    ADRL x0, _g_nick
    ret

// char *am_status(void) — "2 linked nearby · 3 on the mesh · 14 relayed"
.globl _am_status
_am_status:
    ENTER 0
    bl   _ble_ready_count
    mov  x3, x0
    ADRL x8, _g_node_count
    ldr  x4, [x8]
    ADRL x8, _g_relayed
    ldr  x5, [x8]
    ADRL x0, _g_ios_buf
    mov  x1, #160
    ADRL x2, Li_status_fmt
    bl   _sfmt
    ADRL x0, _g_ios_buf
    LEAVE 0

// The scanner's list (scan_core.s): everything around, as on the Mac
// long am_scan_count(void)
.globl _am_scan_count
_am_scan_count:
    b    _scan_rows

// const char *am_scan_cell(long row, long column) — 'n' name, 'k' kind, 's' signal,
//   'l' last heard
.globl _am_scan_cell
_am_scan_cell:
    ENTER 0
    mov  x9, x0
    mov  x0, x1
    mov  x1, x9
    ADRL x2, _g_ios_buf
    bl   _scan_cell                   // its answer: the buffer, or a name it points at
    LEAVE 0

// const char *am_scan_details(long row)
.globl _am_scan_details
_am_scan_details:
    ENTER 0
    bl   _scan_details_text
    ADRL x0, _g_scan_text
    LEAVE 0

.globl _am_scan_pair
_am_scan_pair:
    b    _scan_pair_row

.globl _am_scan_setup
_am_scan_setup:
    b    _scan_setup_row

// actions (each shows its own prompt through the NSAlert stand-in)
.globl _am_new_room
_am_new_room:
    b    _ui_new_room

// void am_invite(long node)
.globl _am_invite
_am_invite:
    ADRL x8, _g_ios_sel
    str  x0, [x8]
    b    _ui_invite

.globl _am_leave_room
_am_leave_room:
    b    _ui_leave_room

.globl _am_delete_room
_am_delete_room:
    b    _ui_delete_room

// long am_delete_room_ask(char *title, char *info) — Delete for Everyone without waiting on a
//   prompt (SwiftUI asks): 0 this Mac made the selected room, title/info hold the question, then
//   am_delete_room_confirmed(); 1 it can't be deleted, title/info say why. Both 256 bytes.
.globl _am_delete_room_ask
_am_delete_room_ask:
    ENTER 32                          // [96] the room's name
    mov  x22, x0
    mov  x23, x1
    ADRL x8, _g_cur_room
    ldr  x19, [x8]
    cbz  x19, Lda_builtin
    ADRL x8, _g_rooms
    add  x20, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x20, #R_ID]
    sub  x9, x9, #1
    cmp  x9, #(LOCAL_ROOMS - 2)
    b.ls Lda_builtin
    add  x1, x20, #R_NAME
    add  x0, sp, #96
    mov  x2, #32
    bl   _strlcpy
    ldr  x21, [x20, #R_OWNER]
    cbz  x21, Lda_unknown
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    cmp  x21, x9
    b.ne Lda_notyours
    add  x9, sp, #96                  // ours: are you sure?
    str  x9, [sp]
    mov  x0, x22
    mov  x1, #256
    ADRL x2, Ls_del_msg
    bl   _snprintf
    ADRL x1, Ls_del_info
    mov  x24, #0
    b    Lda_info
Lda_notyours:                         // someone else's: who can delete it
    mov  x0, x21
    bl   _node_find
    ADRL x21, Ls_its_maker
    tbnz x0, #63, 1f
    ADRL x8, _g_nodes
    add  x0, x8, x0, lsl #NODE_SHIFT
    bl   _node_name
    mov  x21, x0
1:  str  x21, [sp]
    add  x9, sp, #96
    str  x9, [sp, #8]
    mov  x0, x22
    mov  x1, #256
    ADRL x2, Ls_del_notyours
    bl   _snprintf
    ADRL x1, Ls_del_leave
    b    Lda_refuse
Lda_unknown:
    add  x9, sp, #96
    str  x9, [sp]
    mov  x0, x22
    mov  x1, #256
    ADRL x2, Ls_del_unknown
    bl   _snprintf
    ADRL x1, Ls_del_unknown_info
    b    Lda_refuse
Lda_builtin:
    mov  x0, x22
    ADRL x1, Ls_del_builtin
    mov  x2, #256
    bl   _strlcpy
    ADRL x1, Ls_del_builtin_info
Lda_refuse:
    mov  x24, #1
Lda_info:
    mov  x0, x23
    mov  x2, #256
    bl   _strlcpy
    mov  x0, x24
    LEAVE 32

// long am_delete_room_confirmed(char *title, char *info) — you said yes: tell the room and forget
//   it. 0 done; 1 not done, title/info say why (as am_delete_room_ask).
.globl _am_delete_room_confirmed
_am_delete_room_confirmed:
    ENTER 32                          // [96] the room's name
    mov  x22, x0
    mov  x23, x1
    bl   _am_delete_room_ask          // still ours?
    cbnz x0, Ldc_done
    ADRL x8, _g_cur_room
    ldr  x19, [x8]
    ADRL x8, _g_rooms
    add  x20, x8, x19, lsl #ROOM_SHIFT
    add  x1, x20, #R_NAME
    add  x0, sp, #96
    mov  x2, #32
    bl   _strlcpy
    mov  x0, x19
    bl   _mesh_send_roomdel
    tbnz x0, #63, Ldc_noid
    mov  x0, #0
    bl   _ui_select_room
    mov  x0, x19
    bl   _room_remove
    bl   _ui_rooms_changed
    mov  x0, #0
    mov  x1, #1
    ADRL x2, Lf_you_deleted
    add  x3, sp, #96
    bl   _room_fmt
    mov  x0, #0
    b    Ldc_done
Ldc_noid:
    mov  x0, x22
    ADRL x1, Ls_del_noid
    mov  x2, #256
    bl   _strlcpy
    mov  x0, x23
    ADRL x1, Ls_del_noid_info
    mov  x2, #256
    bl   _strlcpy
    mov  x0, #1
Ldc_done:
    LEAVE 32

.globl _am_change_name
_am_change_name:
    b    _ui_change_name

.globl _am_talk
_am_talk:
    b    _voice_toggle

.globl _am_connect_st
_am_connect_st:
    b    _st_connect_dialog

.globl _am_connect_ha
_am_connect_ha:
    b    _ha_connect_dialog

.globl _am_connect_lifx
_am_connect_lifx:
    b    _lifx_connect_dialog

.globl _am_connect_govee
_am_connect_govee:
    b    _govee_connect_dialog

.globl _am_pair_hue
_am_pair_hue:
    b    _hue_pair

.globl _am_pair_nano
_am_pair_nano:
    b    _nano_pair

.globl _am_airdrop
_am_airdrop:
    b    _ios_share_files

.globl _am_mesh_pass
_am_mesh_pass:
    b    _crypto_dialog

.globl _am_refresh_home
_am_refresh_home:
    b    _home_refresh

// services: the same switches as the Mac's Settings window
.globl _am_svc_count
_am_svc_count:
    mov  x0, #NSVC
    ret

// long am_svc_field(long i, long k) — 1 title, 2 subtitle, 3 SF Symbol (strings),
//   4 colour 0xRRGGBB
.globl _am_svc_field
_am_svc_field:
    b    _svc_field

.globl _am_svc_on
_am_svc_on:
    b    _svc_on

// void am_svc_set(long i, long on)
.globl _am_svc_set
_am_svc_set:
    b    _svc_set

// Bluetooth sensors (sensors.s)
.globl _am_sensor_count
_am_sensor_count:
    ADRL x8, _g_sn_count
    ldr  x0, [x8]
    ret

// am_sensor_info(long i, long k): 0 label, 1 reading, 2 age, 3 kind (strings),
//   4 named (0/1), 5 signal dBm
.globl _am_sensor_info
_am_sensor_info:
    b    _sens_info

// nearby Bluetooth devices (near.s), for the radar
.globl _am_near_count
_am_near_count:
    ADRL x8, _g_near_count
    ldr  x0, [x8]
    ret

// long am_near_info(long i, long k): 0 name, 1 maker, 2 what it is (strings, may be
//   empty), 3 signal dBm, 4 seconds since heard, 5 flags (NF_*)
.globl _am_near_info
_am_near_info:
    ENTER 0
    ADRL x8, _g_near
    add  x19, x8, x0, lsl #NEAR_SHIFT
    cmp  x1, #0
    b.ne 1f
    add  x0, x19, #NR_NAME
    LEAVE 0
1:  cmp  x1, #1
    b.ne 2f
    ldr  x0, [x19, #NR_MAKER]
    cbnz x0, 9f
    ADRL x0, Li_empty
9:  LEAVE 0
2:  cmp  x1, #2
    b.ne 3f
    ldr  x0, [x19, #NR_SUB]
    cbnz x0, 8f
    add  x0, x19, #NR_SVCS
8:  LEAVE 0
3:  cmp  x1, #3
    b.ne 4f
    ldr  x0, [x19, #NR_AVG]
    asr  x0, x0, #4
    LEAVE 0
4:  cmp  x1, #4
    b.ne 5f
    mov  x0, #0
    bl   _time
    ldr  x9, [x19, #NR_SEEN]
    sub  x0, x0, x9
    LEAVE 0
5:  ldr  x0, [x19, #NR_FLAGS]
    LEAVE 0

// ===========================================================================
// Mac-only parts, answered here so the core links unchanged
// ===========================================================================

// void _room_append(long room, const char *utf8) — a web page or headlines: one line,
//   no time stamp
.globl _room_append
_room_append:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_rooms
    add  x20, x8, x19, lsl #ROOM_SHIFT
    ldr  x0, [x20, #R_ID]
    mov  x2, #0
    bl   _ios_room_line
    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    cmp  x9, x19
    b.eq 1f
    ldr  x9, [x20, #R_UNREAD]
    add  x9, x9, #1
    str  x9, [x20, #R_UNREAD]
    bl   _ui_rooms_changed
1:  LEAVE 0

// FM radio is the Mac's (a transmitter on the headphone jack, an RTL-SDR stick):
// what the web and page-packing code look at, answered "off"
.globl _fm_demod
_fm_demod:
.globl _fm_mod
_fm_mod:
.globl _fm_tx_push
_fm_tx_push:
    mov  x0, #0
    ret

.globl _h_fm_repeat
_h_fm_repeat:
    ADRL x0, Li_mac_only
    b    _home_say0

// Files on Wi-Fi (files.s) on iPhone: the folder is asmmesh's own, which the Files
// app shows under On My iPhone › asmmesh; AirDrop is the share sheet; the QR code a sheet
.globl _h_files_choose
_h_files_choose:
    ADRL x0, Li_files_folder
    b    _home_say0

.globl _h_airdrop
_h_airdrop:
    b    _ios_share_files

// void _fs_qr_show(const char *text)
.globl _fs_qr_show
_fs_qr_show:
    b    _ios_show_qr

.globl _fm_start
_fm_start:
.globl _fm_stop
_fm_stop:
.globl _fm_tx_packet
_fm_tx_packet:
    ret

// Cocoa view helpers the Mac's Settings and SPIN windows use: no views on iPhone
.globl _mk_label
_mk_label:
.globl _dim_label
_dim_label:
.globl _symbol_image
_symbol_image:
.globl _font
_font:
.globl _mk_button
_mk_button:
.globl _pill
_pill:
.globl _t_report
_t_report:
    mov  x0, #0
    ret

// IOKit (battery levels on the Mac) is not open to iPhone apps
.globl _IOPSCopyPowerSourcesInfo
_IOPSCopyPowerSourcesInfo:
.globl _IOPSCopyPowerSourcesList
_IOPSCopyPowerSourcesList:
.globl _IOPSGetPowerSourceDescription
_IOPSGetPowerSourceDescription:
.globl _IOServiceMatching
_IOServiceMatching:
.globl _IORegistryEntryCreateCFProperty
_IORegistryEntryCreateCFProperty:
.globl _IOIteratorNext
_IOIteratorNext:
.globl _IOObjectRelease
_IOObjectRelease:
    mov  x0, #0
    ret
.globl _IOServiceGetMatchingServices
_IOServiceGetMatchingServices:
    mov  x0, #1                       // an error: nothing to list
    ret

// ===========================================================================
// From the Mac's ui.s, unchanged: prompts, rooms, names, invites
// ===========================================================================

// void _room_fmt(long room, int sys, const char *fmt, a, b, c)
.globl _room_fmt
_room_fmt:
    ENTER 1024
    mov  x19, x0
    mov  x20, x1
    str  x3, [sp]
    str  x4, [sp, #8]
    str  x5, [sp, #16]
    add  x0, sp, #96
    mov  x1, #1024
    bl   _snprintf                    // fmt is already in x2
    mov  x0, x19
    add  x1, sp, #96
    mov  x2, x20
    bl   _room_line
    LEAVE 1024

// void _chat_line(const char *utf8) — a system line in Main (the mesh feed)
.globl _chat_line
_chat_line:
    ENTER 0
    mov  x1, x0
    mov  x0, #0
    mov  x2, #1
    bl   _room_line
    LEAVE 0

// const char *_node_name(void *entry) — its nickname, or "(unknown)"
.globl _node_name
_node_name:
    add  x0, x0, #N_NICK
    ldrb w9, [x0]
    cbnz w9, Lnn_done
    ADRL x0, Ls_unknown
Lnn_done:
    ret

// long _alert_run(msg, info, ok, id accessory /*or 0*/, cancel /*or 0*/) -> 1 if OK
.globl _alert_run
_alert_run:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    CLS  Ls_NSAlert
    MSG0 Ls_new
    mov  x24, x0
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_setMessageText
    mov  x0, x20
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_setInformativeText
    mov  x0, x21
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_addButtonWithTitle
    cbz  x23, Lar_acc
    mov  x0, x23
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_addButtonWithTitle
Lar_acc:
    cbz  x22, Lar_run
    mov  x0, x24
    mov  x2, x22
    MSG1 Ls_setAccessoryView
    mov  x0, x24
    MSG0 Ls_window
    mov  x2, x22
    MSG1 Ls_setInitialFirstResponder
Lar_run:
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    mov  x0, x24
    MSG0 Ls_runModal
    mov  x19, x0
    mov  x0, x24
    MSG0 Ls_release
    cmp  x19, #1000                   // NSAlertFirstButtonReturn
    cset x0, eq
    LEAVE 0

// id _accessory(Class cls) — [[cls alloc] initWithFrame:{0,0,280,24}]
_accessory:
    ENTER 0
    MSG0 Ls_alloc
    mov  x19, x0
    SELX1 Ls_initWithFrame
    mov  x0, x19
    ADRL x8, Lf_acc
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    LEAVE 0

// - (void)newRoom:(id)sender
.globl _ui_new_room
_ui_new_room:
    ENTER 64                          // [96] room name
    CLS  Ls_NSTextField
    bl   _accessory
    mov  x19, x0
    ADRL x0, Ls_room_ph
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setPlaceholderString
    ADRL x0, Ls_newroom_msg
    ADRL x1, Ls_newroom_info
    ADRL x2, Ls_create
    mov  x3, x19
    ADRL x4, Ls_cancel
    bl   _alert_run
    cbz  x0, Lnr_release
    mov  x0, x19
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, Lnr_release
    mov  x1, x0
    add  x0, sp, #96
    mov  x2, #ROOMNAME_MAX
    bl   _text_copy_trim
    cbz  x0, Lnr_release
    bl   _new_id
    add  x1, sp, #96
    mov  x2, #1
    bl   _room_add
    mov  x20, x0
    tbnz x20, #63, Lnr_full
    mov  x0, x20                      // we made it: only we can delete it for everyone
    bl   _room_own
    mov  x0, x20
    bl   _ui_select_room
    mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_fmt_created
    add  x3, sp, #96
    bl   _room_fmt
    b    Lnr_release
Lnr_full:
    ADRL x0, Ls_full_msg
    ADRL x1, Ls_full_info
    ADRL x2, Ls_ok
    mov  x3, #0
    mov  x4, #0
    bl   _alert_run
Lnr_release:
    mov  x0, x19
    MSG0 Ls_release
    LEAVE 64

// - (void)changeName:(id)sender — pick from a list or type your own
.globl _ui_change_name
_ui_change_name:
    ENTER 64                          // [96] first name
    CLS  Ls_NSComboBox
    bl   _accessory
    mov  x19, x0
    mov  x0, x19
    ADRL x1, _g_nick
    bl   _combo_add
    ADRL x0, _g_hostnick
    ADRL x1, _g_nick
    bl   _strcmp
    cbz  w0, Lcn_full
    mov  x0, x19
    ADRL x1, _g_hostnick
    bl   _combo_add
Lcn_full:
    bl   _NSFullUserName
    cbz  x0, Lcn_show
    MSG0 Ls_UTF8String
    cbz  x0, Lcn_show
    mov  x20, x0
    ldrb w9, [x20]
    cbz  w9, Lcn_show
    mov  x0, x19
    mov  x1, x20
    bl   _combo_add
    mov  x9, #0                       // first word of the full name
Lcn_word:
    cmp  x9, #31
    b.hs Lcn_word_end
    ldrb w10, [x20, x9]
    cbz  w10, Lcn_show                // one word only: already offered
    cmp  w10, #' '
    b.eq Lcn_word_end
    add  x11, sp, #96
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    Lcn_word
Lcn_word_end:
    add  x11, sp, #96
    strb wzr, [x11, x9]
    cbz  x9, Lcn_show
    mov  x0, x19
    add  x1, sp, #96
    bl   _combo_add
Lcn_show:
    ADRL x0, _g_nick
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setStringValue
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setCompletes
    ADRL x0, Ls_name_msg
    ADRL x1, Ls_name_info
    ADRL x2, Ls_save
    mov  x3, x19
    ADRL x4, Ls_cancel
    bl   _alert_run
    cbz  x0, Lcn_release
    mov  x0, x19
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, Lcn_release
    bl   _mesh_set_nick
    cbz  x0, Lcn_release
    bl   _ui_update_name
    mov  x0, #0
    mov  x1, #1
    ADRL x2, Ls_fmt_renamed
    ADRL x3, _g_nick
    bl   _room_fmt
    bl   _mesh_send_hello
    bl   _ui_update_status
Lcn_release:
    mov  x0, x19
    MSG0 Ls_release
    LEAVE 64

// void _room_own(long idx) — this Mac made the room
.globl _room_own
_room_own:
    ENTER 0
    ADRL x8, _g_rooms
    add  x8, x8, x0, lsl #ROOM_SHIFT
    ADRL x9, _g_node_id
    ldr  x9, [x9]
    str  x9, [x8, #R_OWNER]
    bl   _rooms_save
    LEAVE 0

// void _room_deleted(long idx) — its owner deleted it (_g_nickbuf: their name)
.globl _room_deleted
_room_deleted:
    ENTER 48                          // [96] the room's name
    mov  x19, x0
    ADRL x8, _g_rooms
    add  x9, x8, x19, lsl #ROOM_SHIFT
    add  x1, x9, #R_NAME
    add  x0, sp, #96
    mov  x2, #32
    bl   _strlcpy
    ADRL x8, _g_window
    ldr  x8, [x8]
    cbz  x8, 1f
    ADRL x8, _g_cur_room              // looking at it (or one listed after it): go to Main
    ldr  x9, [x8]
    cmp  x9, x19
    b.lo 1f
    mov  x0, #0
    bl   _ui_select_room
1:  mov  x0, x19
    bl   _room_remove
    ADRL x8, _g_window
    ldr  x8, [x8]
    cbz  x8, 2f
    bl   _ui_rooms_changed
2:  ADRL x0, Lf_room_deleted
    ADRL x1, _g_nickbuf
    add  x2, sp, #96
    bl   _chat_fmt
    LEAVE 48

// - (void)deleteRoom:(id)sender — its owner deletes it for everyone; anyone else is told
//   who can, and that they can leave it
.globl _ui_delete_room
_ui_delete_room:
    ENTER 224                         // [96] name (32)  [128] message (160)
    ADRL x8, _g_cur_room
    ldr  x19, [x8]
    cbz  x19, Ldr_builtin
    ADRL x8, _g_rooms
    add  x20, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x20, #R_ID]
    sub  x9, x9, #1
    cmp  x9, #(LOCAL_ROOMS - 2)
    b.ls Ldr_builtin
    add  x1, x20, #R_NAME
    add  x0, sp, #96
    mov  x2, #32
    bl   _strlcpy
    ldr  x21, [x20, #R_OWNER]
    cbz  x21, Ldr_unknown
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    cmp  x21, x9
    b.ne Ldr_notyours
    add  x9, sp, #96                  // ours: are you sure?
    str  x9, [sp]
    add  x0, sp, #128
    mov  x1, #160
    ADRL x2, Ls_del_msg
    bl   _snprintf
    add  x0, sp, #128
    ADRL x1, Ls_del_info
    ADRL x2, Ls_del_yes
    mov  x3, #0
    ADRL x4, Ls_cancel
    bl   _alert_run
    cbz  x0, Ldr_done
    mov  x0, x19
    bl   _mesh_send_roomdel
    tbnz x0, #63, Ldr_noid
    mov  x0, #0
    bl   _ui_select_room
    mov  x0, x19
    bl   _room_remove
    bl   _ui_rooms_changed
    mov  x0, #0
    mov  x1, #1
    ADRL x2, Lf_you_deleted
    add  x3, sp, #96
    bl   _room_fmt
    b    Ldr_done
Ldr_notyours:                         // someone else's: who can delete it
    mov  x0, x21
    bl   _node_find
    ADRL x22, Ls_its_maker
    tbnz x0, #63, 1f
    ADRL x8, _g_nodes
    add  x0, x8, x0, lsl #NODE_SHIFT
    bl   _node_name
    mov  x22, x0
1:  str  x22, [sp]
    add  x9, sp, #96
    str  x9, [sp, #8]
    add  x0, sp, #128
    mov  x1, #160
    ADRL x2, Ls_del_notyours
    bl   _snprintf
    add  x0, sp, #128
    ADRL x1, Ls_del_leave
    b    Ldr_tell
Ldr_unknown:
    add  x9, sp, #96
    str  x9, [sp]
    add  x0, sp, #128
    mov  x1, #160
    ADRL x2, Ls_del_unknown
    bl   _snprintf
    add  x0, sp, #128
    ADRL x1, Ls_del_unknown_info
    b    Ldr_tell
Ldr_noid:
    ADRL x0, Ls_del_noid
    ADRL x1, Ls_del_noid_info
    b    Ldr_tell
Ldr_builtin:
    ADRL x0, Ls_del_builtin
    ADRL x1, Ls_del_builtin_info
Ldr_tell:
    ADRL x2, Ls_ok
    mov  x3, #0
    mov  x4, #0
    bl   _alert_run
Ldr_done:
    LEAVE 224

// - (void)leaveRoom:(id)sender — tell the room, then forget it
.globl _ui_leave_room
_ui_leave_room:
    ENTER 48                          // [96] the room's name
    ADRL x8, _g_cur_room
    ldr  x19, [x8]
    cbz  x19, Llv_main
    ADRL x8, _g_rooms
    add  x9, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x9, #R_ID]
    sub  x9, x9, #1                   // local rooms can't be left
    cmp  x9, #(LOCAL_ROOMS - 2)
    b.ls Llv_main
    ADRL x8, _g_rooms
    add  x9, x8, x19, lsl #ROOM_SHIFT
    add  x1, x9, #R_NAME
    add  x0, sp, #96
    mov  x2, #32
    bl   _strlcpy
    mov  x0, x19
    ADRL x1, Ls_left_txt
    mov  w2, #MSGF_NOTICE
    bl   _mesh_send_msg
    mov  x0, #0                       // look at Main before the transcript goes away
    bl   _ui_select_room
    mov  x0, x19
    bl   _room_remove
    bl   _ui_rooms_changed
    mov  x0, #0
    mov  x1, #1
    ADRL x2, Ls_fmt_you_left
    add  x3, sp, #96
    bl   _room_fmt
    LEAVE 48
Llv_main:
    ADRL x0, Ls_main_msg
    ADRL x1, Ls_main_info
    ADRL x2, Ls_ok
    mov  x3, #0
    mov  x4, #0
    bl   _alert_run
    LEAVE 48

// void _combo_add(id combo, const char *utf8)
_combo_add:
    ENTER 0
    mov  x19, x0
    mov  x0, x1
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_addItemWithObjectValue
    LEAVE 0

// void _invite_queue(uint64 room, const char *room_name, const char *from, const uint8 *key64)
.globl _invite_queue
_invite_queue:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x23, x3
    mov  x24, x4
    mov  x0, #144                     // +0 room id, +8 name[32], +40 from[24], +72 key[64],
    bl   _malloc                      //   +136 who made the room (0: not said)
    cbz  x0, Liq_done
    mov  x22, x0
    str  x19, [x22]
    str  x24, [x22, #136]
    add  x0, x22, #72
    mov  x1, x23
    mov  x2, #64
    bl   _memcpy
    add  x0, x22, #8
    mov  x1, x20
    mov  x2, #32
    bl   _strlcpy
    add  x0, x22, #40
    mov  x1, x21
    mov  x2, #24
    bl   _strlcpy
    ADRL x8, _g_window                // selftest: no window, no run loop
    ldr  x8, [x8]
    cbz  x8, Liq_free
    LDGOT x0, __dispatch_main_q
    mov  x1, x22
    ADRL x2, _invite_cb
    bl   _dispatch_async_f
Liq_done:
    LEAVE 0
Liq_free:
    mov  x0, x22
    bl   _free
    LEAVE 0

// void _invite_cb(void *ctx) — Join / Not now
_invite_cb:
    ENTER 256
    mov  x19, x0
    ldr  x0, [x19]
    bl   _room_find
    tbz  x0, #63, Lic_rekey           // already in it: this invite brings a new key
    bl   _ui_show
    add  x9, x19, #40
    str  x9, [sp]
    add  x9, x19, #8
    str  x9, [sp, #8]
    add  x0, sp, #96
    mov  x1, #160
    ADRL x2, Ls_inv_msg
    bl   _snprintf
    add  x0, sp, #96
    ADRL x1, Ls_inv_info
    ADRL x2, Ls_join
    mov  x3, #0
    ADRL x4, Ls_notnow
    bl   _alert_run
    cbz  x0, Lic_free
    ldr  x0, [x19]
    add  x1, x19, #8
    mov  x2, #1
    bl   _room_add
    mov  x20, x0
    tbnz x20, #63, Lic_full
    ldr  x9, [x19, #136]              // who made it, if the invite said
    ADRL x8, _g_rooms
    add  x8, x8, x20, lsl #ROOM_SHIFT
    str  x9, [x8, #R_OWNER]
    bl   _rooms_save
    mov  x0, x20                      // the room's key came sealed in the invite
    add  x1, x19, #72
    bl   _room_key_set
    bl   _keys_save
    mov  x0, x20
    bl   _ui_select_room
    mov  x0, x20
    ADRL x1, Ls_joined_txt
    mov  w2, #MSGF_NOTICE
    bl   _mesh_send_msg
    mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_fmt_you_joined
    add  x3, x19, #8
    bl   _room_fmt
    b    Lic_free
Lic_rekey:                            // "Fred sent a new key for 'X'": use it?
    mov  x20, x0
    bl   _room_key                    // (a second copy of an invite we took: same key)
    cbz  x0, Lic_rk_ask
    add  x1, x19, #72
    mov  x2, #64
    bl   _memcmp
    cbz  w0, Lic_free
Lic_rk_ask:
    bl   _ui_show
    add  x9, x19, #40
    str  x9, [sp]
    add  x9, x19, #8
    str  x9, [sp, #8]
    add  x0, sp, #96
    mov  x1, #160
    ADRL x2, Ls_rekey_msg
    bl   _snprintf
    add  x0, sp, #96
    ADRL x1, Ls_rekey_info
    ADRL x2, Ls_rekey_yes
    mov  x3, #0
    ADRL x4, Ls_notnow
    bl   _alert_run
    cbz  x0, Lic_free
    mov  x0, x20
    add  x1, x19, #72
    bl   _room_key_set
    bl   _keys_save
    ADRL x8, _g_rooms                 // and who made it, if we didn't know
    add  x8, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_OWNER]
    cbnz x9, 1f
    ldr  x9, [x19, #136]
    str  x9, [x8, #R_OWNER]
    bl   _rooms_save
1:  mov  x0, x20
    bl   _ui_select_room
    mov  x0, x20
    mov  x1, #1
    ADRL x2, Ls_fmt_rekeyed
    add  x3, x19, #40
    bl   _room_fmt
    b    Lic_free
Lic_full:                             // 16 rooms already: say why nothing happened
    ADRL x0, Ls_inv_full
    bl   _chat_line
Lic_free:
    mov  x0, x19
    bl   _free
    LEAVE 256

.section __TEXT,__cstring,cstring_literals
Ls_inv_full:          .asciz "\302\267 You\342\200\231re already in 16 rooms, the most asmmesh keeps. Leave one first, then ask for the invite again."
Ls_fmt_invite_nokey: .asciz "\302\267 \360\237\224\221 Can\342\200\231t invite %s yet: their Mac hasn\342\200\231t introduced its key. Wait a few seconds for them to show up, then try again."
Ls_NSAttributedString: .asciz "NSAttributedString"
Ls_NSIndexSet:        .asciz "NSIndexSet"
Ls_NSApplication:     .asciz "NSApplication"
Ls_NSAlert:           .asciz "NSAlert"
Ls_NSTextField:       .asciz "NSTextField"
Ls_NSComboBox:        .asciz "NSComboBox"
Ls_alloc:             .asciz "alloc"
Ls_new:               .asciz "new"
Ls_release:           .asciz "release"
Ls_initWithFrame:     .asciz "initWithFrame:"
Ls_initWithStringAttrs: .asciz "initWithString:attributes:"
Ls_appendAttributedString: .asciz "appendAttributedString:"
Ls_scrollToEndOfDocument: .asciz "scrollToEndOfDocument:"
Ls_layoutManager:     .asciz "layoutManager"
Ls_replaceTextStorage: .asciz "replaceTextStorage:"
Ls_setStringValue:    .asciz "setStringValue:"
Ls_setPlaceholderString: .asciz "setPlaceholderString:"
Ls_indexSetWithIndex: .asciz "indexSetWithIndex:"
Ls_selectRowIndexes:  .asciz "selectRowIndexes:byExtendingSelection:"
Ls_reloadData:        .asciz "reloadData"
Ls_button:            .asciz "button"
Ls_setTitle:          .asciz "setTitle:"
Ls_object:            .asciz "object"
Ls_selectedRow:       .asciz "selectedRow"
Ls_stringValue:       .asciz "stringValue"
Ls_UTF8String:        .asciz "UTF8String"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
Ls_setMessageText:    .asciz "setMessageText:"
Ls_setInformativeText: .asciz "setInformativeText:"
Ls_addButtonWithTitle: .asciz "addButtonWithTitle:"
Ls_setAccessoryView:  .asciz "setAccessoryView:"
Ls_window:            .asciz "window"
Ls_setInitialFirstResponder: .asciz "setInitialFirstResponder:"
Ls_runModal:          .asciz "runModal"
Ls_addItemWithObjectValue: .asciz "addItemWithObjectValue:"
Ls_setCompletes:      .asciz "setCompletes:"

Ls_timefmt:           .asciz "%H:%M:%S"
Ls_linefmt:           .asciz "%s  %s\n"
Ls_empty:             .asciz ""
Ls_unknown:           .asciz "(unknown)"
Ls_hdr_main:          .asciz "# %s \342\200\224 everyone on the mesh"
Ls_hdr_room:          .asciz "# %s \342\200\224 invite-only"
Ls_hdr_home:          .asciz "# %s \342\200\224 lights, locks and scenes on this Mac"
Ls_ph_home:           .asciz "Say or type a command, e.g. kitchen lights off%.0s"
Ls_hdr_web:           .asciz "# %s \342\200\224 web pages fetched by a Mac with internet"
Ls_hdr_news:          .asciz "# %s \342\200\224 headlines from Macs with internet"
Ls_ph_web:            .asciz "A web address or search words; a number follows a link%.0s"
Ls_ph_news:           .asciz "Headlines arrive here; type refresh or feed <address>%.0s"
Ls_ph_fmt:            .asciz "Message #%s"
Ls_status_fmt:        .asciz "%ld linked nearby  \302\267  %ld on the mesh  \302\267  %ld relayed"
Ls_count_fmt:         .asciz " %ld"
Ls_you_fmt:           .asciz "You: %s"
Ls_room_row:          .asciz "# %s"
Ls_room_row_unread:   .asciz "# %s   (%ld)"
Ls_pp_near:           .asciz "%s  \302\267 %s  \302\267 nearby"
Ls_pp_hops:           .asciz "%s  \302\267 %s  \302\267 %ld hops"
Ls_pp_away:           .asciz "%s  \302\267 %s  \302\267 away"
Ls_pair_fmt:          .asciz "%s & %s"

Ls_ok:                .asciz "OK"
Ls_cancel:            .asciz "Cancel"
Ls_create:            .asciz "Create"
Ls_save:              .asciz "Save"
Ls_join:              .asciz "Join"
Ls_notnow:            .asciz "Not now"
Ls_rekey_msg:         .asciz "%s sent a new key for \342\200\234%s\342\200\235."
Ls_rekey_info:        .asciz "Their old key was lost (for example after a reinstall), so their messages in that room couldn\342\200\231t be opened. Use the new key if this really is them \342\200\224 you can check their fingerprint under People on the Mesh."
Ls_rekey_yes:         .asciz "Use the New Key"
Ls_fmt_rekeyed:       .asciz "\302\267 \360\237\224\221 You have %s\342\200\231s new key for this room \342\200\224 their messages open again."
Ls_room_ph:           .asciz "Room name, e.g. Weekend plans"
Ls_newroom_msg:       .asciz "New invite-only room"
Ls_newroom_info:      .asciz "Only people you invite will see it. Messages still hop through every Mac on the mesh to reach them."
Ls_full_msg:          .asciz "That's the room limit"
Ls_full_info:         .asciz "asmmesh keeps up to 15 rooms besides Main."
Ls_pick_msg:          .asciz "Pick someone first"
Ls_pick_info:         .asciz "Click a name under People on the Mesh, then Invite to Chat. From Main this starts a new room for the two of you; from a room it invites them into that room."
Ls_name_msg:          .asciz "Your name on the mesh"
Ls_name_info:         .asciz "Pick one or type your own, up to 23 characters. Everyone sees it next to your messages and in their People list."
Ls_inv_msg:           .asciz "%s invites you to #%s"
Ls_inv_info:          .asciz "It's an invite-only room. Messages hop over Bluetooth through nearby Macs; only members see them."
Ls_joined_txt:        .asciz "joined the room"
Ls_left_txt:          .asciz "left the room"
Ls_fmt_you_left:      .asciz "\302\267 You left #%s."
Lf_room_deleted:      .asciz "\302\267 \360\237\227\221 %s deleted the room \342\200\234%s\342\200\235 \342\200\224 it\342\200\231s gone from this Mac too."
Lf_you_deleted:       .asciz "\302\267 \360\237\227\221 You deleted \342\200\234%s\342\200\235 for everyone in it."
Ls_del_msg:           .asciz "Delete \342\200\234%s\342\200\235 for everyone?"
Ls_del_info:          .asciz "It disappears from every Mac in it, with its messages. A Mac that\342\200\231s away gets the news when it comes back. This can\342\200\231t be undone."
Ls_del_yes:           .asciz "Delete Room"
Ls_del_notyours:      .asciz "Only %s can delete \342\200\234%s\342\200\235."
Ls_del_leave:         .asciz "Whoever made a room is the only one who can delete it for everyone. You can leave it instead: Mesh \342\200\272 Leave Room."
Ls_its_maker:         .asciz "the person who made it"
Ls_del_unknown:       .asciz "asmmesh doesn\342\200\231t know who made \342\200\234%s\342\200\235."
Ls_del_unknown_info:  .asciz "It\342\200\231s older than room owners. Invite someone to it again from this Mac \342\200\224 that makes you its owner \342\200\224 and then you can delete it. Or just leave it: Mesh \342\200\272 Leave Room."
Ls_del_noid:          .asciz "Can\342\200\231t delete it yet"
Ls_del_noid_info:     .asciz "Your identity key isn\342\200\231t unlocked, so the other Macs couldn\342\200\231t trust the request. Allow the Keychain prompt, then try again."
Ls_del_builtin:       .asciz "That room can\342\200\231t be deleted"
Ls_del_builtin_info:  .asciz "Main, Home, Web and News are built in. Select one of your own rooms first."
Ls_main_msg:          .asciz "Main and Home are built in"
Ls_main_info:         .asciz "Select one of your own rooms in the list first, then Leave Room."
Ls_fmt_created:       .asciz "\302\267 You created #%s. Pick someone under People and click Invite to Chat."
Ls_fmt_invited:       .asciz "\302\267 Invited %s \342\200\224 they'll get a Join / Not now prompt."
Ls_fmt_invited_held:  .asciz "\302\267 Invited %s \342\200\224 nobody in range right now, so the invite waits for the next Mac that appears."
Ls_fmt_renamed:       .asciz "\302\267 You're now \342\200\234%s\342\200\235."
Ls_fmt_you_joined:    .asciz "\302\267 You joined #%s \342\200\224 say hello."


// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Li_NSObject:           .asciz "NSObject"
Li_ctl_name:           .asciz "AMeshController"
Li_new:                .asciz "new"
Li_NSBundle:           .asciz "NSBundle"
Li_mainBundle:         .asciz "mainBundle"
Li_CFBundleVersion:    .asciz "CFBundleVersion"
Li_objectForInfoKey:   .asciz "objectForInfoDictionaryKey:"
Li_UTF8String:         .asciz "UTF8String"
Li_qmark:              .asciz "?"
Li_empty:              .asciz ""
Li_timefmt:            .asciz "%H:%M:%S"
Li_linefmt:            .asciz "%s  %s"
Li_status_fmt:         .asciz "%ld linked nearby  \302\267  %ld on the mesh  \302\267  %ld relayed"
Li_fmt_welcome:        .asciz "\302\267 asmmesh for iPhone (build %2$s) \342\200\224 you are \342\200\234%1$s\342\200\235. Main is open to everyone on the mesh; tap + for a room, and invite people from People."
Li_pick_info:          .asciz "Open People, tap someone, then Invite. From Main this starts a room for the two of you; from a room it invites them into that room."
Li_files_folder:       .asciz "\302\267 \360\237\223\202 On iPhone and iPad the shared folder is asmmesh\342\200\231s own: in the Files app, On My iPhone (or iPad) \342\200\272 asmmesh. Put files there; uploads from other phones land there too."
.globl _fs_default_dir
_fs_default_dir:       .asciz "%s/Documents"
Li_mac_only:           .asciz "\302\267 That one is Mac-only (files page, AirDrop, FM radio)."
Li_m_cmState:          .asciz "centralManagerDidUpdateState:"
Li_m_cmDiscover:       .asciz "centralManager:didDiscoverPeripheral:advertisementData:RSSI:"
Li_m_cmConnect:        .asciz "centralManager:didConnectPeripheral:"
Li_m_cmFail:           .asciz "centralManager:didFailToConnectPeripheral:error:"
Li_m_cmDisconn:        .asciz "centralManager:didDisconnectPeripheral:error:"
Li_m_pServices:        .asciz "peripheral:didDiscoverServices:"
Li_m_pChars:           .asciz "peripheral:didDiscoverCharacteristicsForService:error:"
Li_m_pValue:           .asciz "peripheral:didUpdateValueForCharacteristic:error:"
Li_m_pRSSI:            .asciz "peripheral:didReadRSSI:error:"
Li_m_pModify:          .asciz "peripheral:didModifyServices:"
Li_m_pmState:          .asciz "peripheralManagerDidUpdateState:"
Li_m_pmAdded:          .asciz "peripheralManager:didAddService:error:"
Li_m_pmAdv:            .asciz "peripheralManagerDidStartAdvertising:error:"
Li_m_pmRead:           .asciz "peripheralManager:didReceiveReadRequest:"
Li_m_pmWrites:         .asciz "peripheralManager:didReceiveWriteRequests:"
Li_m_netData:          .asciz "URLSession:dataTask:didReceiveData:"
Li_m_netDone:          .asciz "URLSession:task:didCompleteWithError:"
Li_m_bonjourFound:     .asciz "netServiceBrowser:didFindService:moreComing:"
Li_m_resolved:         .asciz "netServiceDidResolveAddress:"
Li_m_speechHyp:        .asciz "speechRecognitionTask:didHypothesizeTranscription:"
Li_m_speechFinal:      .asciz "speechRecognitionTask:didFinishRecognition:"
Li_m_speechDone:       .asciz "speechRecognitionTask:didFinishSuccessfully:"
Li_m_locUpdate:        .asciz "locationManager:didUpdateLocations:"
Li_m_locFail:          .asciz "locationManager:didFailWithError:"
Li_ty_v1:              .asciz "v@:@"
Li_ty_v2:              .asciz "v@:@@"
Li_ty_v3:              .asciz "v@:@@@"
Li_ty_v4:              .asciz "v@:@@@@"
Li_ty_found:           .asciz "v@:@@B"
Li_ty_vB:              .asciz "v@:@B"
Li_p_cm:               .asciz "CBCentralManagerDelegate"
Li_p_p:                .asciz "CBPeripheralDelegate"
Li_p_pm:               .asciz "CBPeripheralManagerDelegate"
Li_p_url:              .asciz "NSURLSessionDataDelegate"
Li_p_nsb:              .asciz "NSNetServiceBrowserDelegate"
Li_p_ns:               .asciz "NSNetServiceDelegate"
Li_p_speech:           .asciz "SFSpeechRecognitionTaskDelegate"
Li_p_loc:              .asciz "CLLocationManagerDelegate"
