// ui.s — what the window does: per-room transcripts, the Rooms and People
// lists, sending, New Room, Invite to Chat, the Join / Not now prompt, the
// name picker, and the status line. All of it runs on the main thread.

.include "macros.inc"

.section __TEXT,__const
.p2align 3
Lf_acc:      .double 0.0, 0.0, 280.0, 24.0

.text
.p2align 2

// ---------------------------------------------------------------------------
// void _room_line(long room, const char *utf8, int sys)
//   "HH:MM:SS  text" appended to the room's transcript (and to stderr).
//   A line for a room you are not looking at bumps its unread count.
// ---------------------------------------------------------------------------
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
    ADRL x2, Ls_timefmt
    add  x3, sp, #112
    bl   _strftime
    add  x0, sp, #208
    mov  x1, #1024
    ADRL x2, Ls_linefmt
    add  x8, sp, #176
    str  x8, [sp]
    str  x20, [sp, #8]
    bl   _snprintf
    add  x0, sp, #208
    bl   _strlen
    mov  x2, x0
    mov  w0, #2
    add  x1, sp, #208
    bl   _write

    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lrl_done
    ADRL x8, _g_rooms
    add  x22, x8, x19, lsl #ROOM_SHIFT
    ldr  x23, [x22, #R_STORE]
    cbz  x23, Lrl_done
    add  x0, sp, #208
    bl   _nsstr
    mov  x24, x0
    CLS  Ls_NSAttributedString
    MSG0 Ls_alloc
    mov  x20, x0
    ADRL x8, _g_attr_msg
    ADRL x9, _g_attr_sys
    cmp  x21, #0
    csel x8, x9, x8, ne
    ldr  x3, [x8]
    mov  x2, x24
    mov  x0, x20
    MSG2 Ls_initWithStringAttrs
    mov  x24, x0
    mov  x0, x23
    mov  x2, x24
    MSG1 Ls_appendAttributedString
    mov  x0, x24
    MSG0 Ls_release

    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne Lrl_unread
    ADRL x8, _g_chatview
    ldr  x0, [x8]
    cbz  x0, Lrl_done
    mov  x2, #0
    MSG1 Ls_scrollToEndOfDocument
    b    Lrl_done
Lrl_unread:
    ldr  x9, [x22, #R_UNREAD]
    add  x9, x9, #1
    str  x9, [x22, #R_UNREAD]
    bl   _ui_rooms_changed
Lrl_done:
    LEAVE 1136

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

// ---------------------------------------------------------------------------
// void _ui_select_room(long room) — show its transcript, header and prompt
// ---------------------------------------------------------------------------
.globl _ui_select_room
_ui_select_room:
    ENTER 256
    mov  x19, x0
    ADRL x8, _g_cur_room
    str  x19, [x8]
    ADRL x8, _g_rooms
    add  x20, x8, x19, lsl #ROOM_SHIFT
    str  xzr, [x20, #R_UNREAD]
    ADRL x8, _g_chatview
    ldr  x21, [x8]
    cbz  x21, Lsr_labels
    mov  x0, x21
    MSG0 Ls_layoutManager
    ldr  x2, [x20, #R_STORE]
    MSG1 Ls_replaceTextStorage
    mov  x0, x21
    mov  x2, #0
    MSG1 Ls_scrollToEndOfDocument
Lsr_labels:
    ADRL x8, _g_header
    ldr  x21, [x8]
    cbz  x21, Lsr_table
    add  x9, x20, #R_NAME
    str  x9, [sp]
    add  x0, sp, #96
    mov  x1, #160
    ADRL x2, Ls_hdr_room
    ADRL x8, Ls_hdr_main
    cmp  x19, #0
    csel x2, x8, x2, eq
    ldr  x9, [x20, #R_ID]
    ADRL x8, Ls_hdr_home
    cmp  x9, #HOME_ID
    csel x2, x8, x2, eq
    ADRL x8, Ls_hdr_web
    cmp  x9, #WEB_ID
    csel x2, x8, x2, eq
    ADRL x8, Ls_hdr_news
    cmp  x9, #NEWS_ID
    csel x2, x8, x2, eq
    bl   _snprintf
    add  x0, sp, #96
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setStringValue
    add  x9, x20, #R_NAME
    str  x9, [sp]
    add  x0, sp, #96
    mov  x1, #160
    ADRL x2, Ls_ph_fmt
    ldr  x9, [x20, #R_ID]
    ADRL x8, Ls_ph_home
    cmp  x9, #HOME_ID
    csel x2, x8, x2, eq
    ADRL x8, Ls_ph_web
    cmp  x9, #WEB_ID
    csel x2, x8, x2, eq
    ADRL x8, Ls_ph_news
    cmp  x9, #NEWS_ID
    csel x2, x8, x2, eq
    bl   _snprintf
    add  x0, sp, #96
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_field
    ldr  x0, [x8]
    cbz  x0, Lsr_table
    MSG1 Ls_setPlaceholderString
Lsr_table:
    ADRL x8, _g_rooms_table
    ldr  x21, [x8]
    cbz  x21, Lsr_done
    CLS  Ls_NSIndexSet
    mov  x2, x19
    MSG1 Ls_indexSetWithIndex
    mov  x2, x0
    mov  x0, x21
    mov  x3, #0
    MSG2 Ls_selectRowIndexes
    bl   _ui_rooms_changed
Lsr_done:
    LEAVE 256

// void _ui_rooms_changed(void)
.globl _ui_rooms_changed
_ui_rooms_changed:
    ENTER 0
    ADRL x8, _g_rooms_table
    ldr  x0, [x8]
    cbz  x0, Lrc_done
    MSG0 Ls_reloadData
Lrc_done:
    LEAVE 0

// void _ui_lists_changed(void) — People, the scanner table and the status line
.globl _ui_lists_changed
_ui_lists_changed:
    ENTER 0
    ADRL x8, _g_people_table
    ldr  x0, [x8]
    cbz  x0, Llc_scan
    MSG0 Ls_reloadData
Llc_scan:
    ADRL x8, _g_scan_table
    ldr  x0, [x8]
    cbz  x0, Llc_status
    MSG0 Ls_reloadData
Llc_status:
    bl   _ui_update_status
    bl   _sui_devs_changed            // the SPIN window's device list
    LEAVE 0

// ---------------------------------------------------------------------------
// Status line, menu-bar count, name button
// ---------------------------------------------------------------------------
.globl _ui_update_status
_ui_update_status:
    ENTER 256
    bl   _ble_ready_count
    mov  x20, x0
    str  x0, [sp]
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    str  x9, [sp, #8]
    ADRL x8, _g_relayed
    ldr  x9, [x8]
    str  x9, [sp, #16]
    add  x0, sp, #96
    mov  x1, #160
    ADRL x2, Ls_status_fmt
    bl   _snprintf
    add  x0, sp, #96
    bl   _nsstr
    mov  x21, x0
    ADRL x8, _g_status
    ldr  x0, [x8]
    cbz  x0, Lus_menu
    mov  x2, x21
    MSG1 Ls_setStringValue
Lus_menu:
    mov  x0, x21
    bl   _sinfo_set
    ADRL x8, _g_sitem
    ldr  x0, [x8]
    cbz  x0, Lus_done
    MSG0 Ls_button
    mov  x19, x0
    add  x0, sp, #96
    strb wzr, [x0]
    cbz  x20, Lus_title
    str  x20, [sp]
    mov  x1, #32
    ADRL x2, Ls_count_fmt
    bl   _snprintf
Lus_title:
    add  x0, sp, #96
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setTitle
Lus_done:
    LEAVE 256

// void _ui_set_status(const char *utf8)
.globl _ui_set_status
_ui_set_status:
    ENTER 0
    bl   _nsstr
    mov  x20, x0
    ADRL x8, _g_status
    ldr  x0, [x8]
    cbz  x0, Lss_menu
    mov  x2, x20
    MSG1 Ls_setStringValue
Lss_menu:
    mov  x0, x20
    bl   _sinfo_set
    LEAVE 0

// void _sinfo_set(NSString *s) — first line of the menu-bar menu
_sinfo_set:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_sinfo
    ldr  x0, [x8]
    cbz  x0, Lsi_done
    mov  x2, x19
    MSG1 Ls_setTitle
Lsi_done:
    LEAVE 0

// void _ui_update_name(void) — "You: Fred" on the button top right
.globl _ui_update_name
_ui_update_name:
    ENTER 128
    ADRL x8, _g_namebtn
    ldr  x19, [x8]
    cbz  x19, Lun_done
    ADRL x9, _g_nick
    str  x9, [sp]
    add  x0, sp, #96
    mov  x1, #64
    ADRL x2, Ls_you_fmt
    bl   _snprintf
    add  x0, sp, #96
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setTitle
Lun_done:
    LEAVE 128

// const char *_node_name(void *entry) — its nickname, or "(unknown)"
.globl _node_name
_node_name:
    add  x0, x0, #N_NICK
    ldrb w9, [x0]
    cbnz w9, Lnn_done
    ADRL x0, Ls_unknown
Lnn_done:
    ret

// ---------------------------------------------------------------------------
// Table data source / delegate (Rooms, People, and the scanner's table)
// ---------------------------------------------------------------------------

// - (NSInteger)numberOfRowsInTableView:(NSTableView *)t
.globl _ds_rows
_ds_rows:
    ADRL x8, _g_rooms_table
    ldr  x9, [x8]
    cmp  x2, x9
    b.eq Ldr_rooms
    ADRL x8, _g_people_table
    ldr  x9, [x8]
    cmp  x2, x9
    b.eq Ldr_nodes
    ADRL x8, _g_scan_table
    ldr  x9, [x8]
    cmp  x2, x9
    b.eq Ldr_scan
    mov  x0, #0
    ret
Ldr_scan:
    b    _scan_rows
Ldr_rooms:
    ADRL x8, _g_room_count
    ldr  x0, [x8]
    ret
Ldr_nodes:
    ADRL x8, _g_node_count
    ldr  x0, [x8]
    ret

// - (id)tableView:t objectValueForTableColumn:col row:(NSInteger)row
.globl _ds_value
_ds_value:
    ENTER 256
    mov  x19, x2
    mov  x20, x3
    mov  x21, x4
    add  x0, sp, #96
    strb wzr, [x0]
    ADRL x8, _g_rooms_table
    ldr  x9, [x8]
    cmp  x19, x9
    b.eq Ldv_room
    ADRL x8, _g_people_table
    ldr  x9, [x8]
    cmp  x19, x9
    b.eq Ldv_person
    ADRL x8, _g_scan_table
    ldr  x9, [x8]
    cmp  x19, x9
    b.ne Ldv_make
    mov  x0, x20
    mov  x1, x21
    add  x2, sp, #96
    bl   _scan_value
    b    Ldv_make_x0

Ldv_room:
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Ldv_make
    ADRL x8, _g_rooms
    add  x22, x8, x21, lsl #ROOM_SHIFT
    add  x9, x22, #R_NAME
    str  x9, [sp]
    ldr  x9, [x22, #R_UNREAD]
    str  x9, [sp, #8]
    ADRL x2, Ls_room_row
    ADRL x8, Ls_room_row_unread
    cmp  x9, #0
    csel x2, x8, x2, ne
    b    Ldv_print

Ldv_person:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Ldv_make
    ADRL x8, _g_nodes
    add  x22, x8, x21, lsl #NODE_SHIFT
    mov  x0, x22
    bl   _node_name
    str  x0, [sp]
    ldr  x0, [x22, #N_ID]             // their key's fingerprint
    add  x1, sp, #288
    bl   _fp
    str  x0, [sp, #8]
    mov  x0, #0
    bl   _time
    ldr  x9, [x22, #N_SEEN]
    sub  x9, x0, x9
    ADRL x2, Ls_pp_away
    cmp  x9, #60
    b.gt Ldv_print
    ldr  x9, [x22, #N_HOPS]
    str  x9, [sp, #16]
    ADRL x2, Ls_pp_near
    cmp  x9, #1
    b.le Ldv_print
    ADRL x2, Ls_pp_hops
Ldv_print:
    add  x0, sp, #96
    mov  x1, #160
    bl   _snprintf
Ldv_make:
    add  x0, sp, #96
Ldv_make_x0:
    bl   _nsstr
    LEAVE 256

// - (void)tableViewSelectionDidChange:(NSNotification *)n — switching rooms
.globl _ds_selchange
_ds_selchange:
    ENTER 0
    mov  x0, x2
    MSG0 Ls_object
    ADRL x8, _g_scan_table
    ldr  x9, [x8]
    cmp  x0, x9
    b.eq Lds_scan
    ADRL x8, _g_rooms_table
    ldr  x9, [x8]
    cmp  x0, x9
    b.ne Lds_done
    MSG0 Ls_selectedRow
    tbnz x0, #63, Lds_done
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs Lds_done
    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    cmp  x0, x9
    b.eq Lds_done
    bl   _ui_select_room
Lds_done:
    LEAVE 0
Lds_scan:
    bl   _scanner_selected
    LEAVE 0

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

// - (void)sendMessage:(id)sender — Return in the field, or Send
.globl _ui_send
_ui_send:
    ENTER 0
    ADRL x8, _g_field
    ldr  x19, [x8]
    cbz  x19, Lsend_done
    mov  x0, x19
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, Lsend_done
    ldrb w8, [x0]
    cbz  w8, Lsend_done
    bl   _mesh_send_text
    ADRL x0, Ls_empty
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setStringValue
Lsend_done:
    LEAVE 0

// - (void)showMain:(id)sender
.globl _ui_show
_ui_show:
    ENTER 0
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    ADRL x8, _g_window
    ldr  x0, [x8]
    cbz  x0, Lshow_done
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
Lshow_done:
    LEAVE 0

// - (BOOL)applicationShouldHandleReopen:hasVisibleWindows:
.globl _app_reopen
_app_reopen:
    ENTER 0
    bl   _ui_show
    mov  w0, #1
    LEAVE 0

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

// - (void)inviteSelected:(id)sender — invite the selected person into this room
//   (from Main, a new room "Fred & Anna" is made for the two of you)
.globl _ui_invite
_ui_invite:
    ENTER 64                          // [96] room name
    ADRL x8, _g_people_table
    ldr  x0, [x8]
    cbz  x0, Liv_pick
    MSG0 Ls_selectedRow
    mov  x19, x0
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
    ADRL x1, Ls_pick_info
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

// ---------------------------------------------------------------------------
// Invites addressed to us: prompt after the current Bluetooth callback returns
// ---------------------------------------------------------------------------

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
    tbnz x20, #63, Lic_free
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
Lic_free:
    mov  x0, x19
    bl   _free
    LEAVE 256

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
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
