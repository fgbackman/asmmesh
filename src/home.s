// home.s — the Home room: a device registry shared by every backend (Hue Bridge,
// Hue Bluetooth bulbs, SmartThings, Apple Home via Shortcuts), a small
// plain-English command parser, and remote commands over the mesh.
//
// Commands look like:  "kitchen lights off", "dim living room to 30%",
// "bedroom blue", "all lights warm", "lock the front door", "good night",
// "devices", "pair hue", "@Anna hallway on".
//
// Safety: unlocking always asks on screen first, and is never accepted from
// the mesh, even though remote commands are signed by their sender (protocol v3)
// and usually sealed for this Mac alone. Any other remote command asks the owner
// of this Mac to Allow / Allow for 10 minutes / Deny.

.include "macros.inc"

.set REPLY_MAX,  400
.set ALLOW_N,    16

// ---------------------------------------------------------------------------
.data
.p2align 3
.globl _g_dev_count
_g_dev_count:     .quad 0
.globl _g_home_idx
_g_home_idx:      .quad 1
.globl _g_cmd_action
_g_cmd_action:    .quad 0
.globl _g_cmd_value
_g_cmd_value:     .quad 0
.globl _g_cmd_n
_g_cmd_n:         .quad 0
.globl _g_remote_active
_g_remote_active: .quad 0
_g_reply_len:     .quad 0
.globl _g_cmds_for_me
_g_cmds_for_me:   .quad 0

.globl _g_devs
.zerofill __DATA,__bss,_g_devs,65536,4
.globl _g_cmd_targets
.zerofill __DATA,__bss,_g_cmd_targets,64,4
.globl _g_cmdbuf
.zerofill __DATA,__bss,_g_cmdbuf,256,4
.globl _g_lname
.zerofill __DATA,__bss,_g_lname,80,4
.zerofill __DATA,__bss,_g_reply,512,4
.zerofill __DATA,__bss,_g_allow,256,4
.zerofill __DATA,__bss,_g_list_line,480,4
.zerofill __DATA,__bss,_g_brief,128,4

// ---------------------------------------------------------------------------
.text
.p2align 2

// IFWORD word, label : branch if the lowercased command (x19) contains the word
.macro IFWORD word, target
    mov  x0, x19
    ADRL x1, \word
    bl   _has_word
    cbnz w0, \target
.endm

// ===========================================================================
// Registry
// ===========================================================================

// long _dev_find(long kind, const char *id) -> index or -1
.globl _dev_find
_dev_find:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
    ADRL x8, _g_dev_count
    ldr  x22, [x8]
Ldf_loop:
    cmp  x21, x22
    b.hs Ldf_none
    ADRL x8, _g_devs
    add  x23, x8, x21, lsl #DEV_SHIFT
    ldr  x9, [x23, #D_KIND]
    cmp  x9, x19
    b.ne Ldf_next
    add  x0, x23, #D_ID
    mov  x1, x20
    bl   _strcmp
    cbz  w0, Ldf_found
Ldf_next:
    add  x21, x21, #1
    b    Ldf_loop
Ldf_found:
    mov  x0, x21
    LEAVE 0
Ldf_none:
    mov  x0, #-1
    LEAVE 0

// long _dev_find_obj(id obj) -> index of the device holding obj, or -1
.globl _dev_find_obj
_dev_find_obj:
    ADRL x8, _g_dev_count
    ldr  x10, [x8]
    ADRL x8, _g_devs
    mov  x9, #0
Ldo_loop:
    cmp  x9, x10
    b.hs Ldo_none
    ldr  x11, [x8, #D_OBJ]
    cmp  x11, x0
    b.eq Ldo_found
    add  x8, x8, #(1 << DEV_SHIFT)
    add  x9, x9, #1
    b    Ldo_loop
Ldo_none:
    mov  x0, #-1
    ret
Ldo_found:
    mov  x0, x9
    ret

// long _dev_add(long kind, const char *id, const char *name, long caps)
//   Adds or updates; state starts unknown. -> index, or -1 if the table is full
.globl _dev_add
_dev_add:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    bl   _dev_find
    tbz  x0, #63, Lda_have
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x9, #DEV_MAX
    b.hs Lda_full
    mov  x0, x9
    add  x9, x9, #1
    str  x9, [x8]
    ADRL x8, _g_devs
    add  x23, x8, x0, lsl #DEV_SHIFT
    mov  x24, x0
    mov  x0, x23
    mov  x1, #(1 << DEV_SHIFT)
    bl   _bzero
    str  x19, [x23, #D_KIND]
    mov  x9, #-1
    str  x9, [x23, #D_ON]
    str  x9, [x23, #D_LEVEL]
    add  x0, x23, #D_ID
    mov  x1, x20
    mov  x2, #D_ID_MAX
    bl   _strlcpy
    mov  x0, x24
Lda_have:
    mov  x24, x0
    ADRL x8, _g_devs
    add  x23, x8, x24, lsl #DEV_SHIFT
    ldr  x9, [x23, #D_CAPS]
    and  x9, x9, #CAP_LINKED          // keep the connection flag of a Bluetooth bulb
    orr  x9, x9, x22
    str  x9, [x23, #D_CAPS]
    add  x0, x23, #D_NAME
    mov  x1, x21
    mov  x2, #D_NAME_MAX
    bl   _strlcpy
    add  x0, x23, #D_NAME
    bl   _utf8_fix
    add  x0, x23, #D_NAME
    bl   _sanitize
    mov  x0, x24
    LEAVE 0
Lda_full:
    mov  x0, #-1
    LEAVE 0

// void _dev_state(long idx, long on, long level) — record what we know (-1 = unknown)
.globl _dev_state
_dev_state:
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    str  x1, [x8, #D_ON]
    str  x2, [x8, #D_LEVEL]
    ret

// ===========================================================================
// Text helpers
// ===========================================================================

// void _lower_copy(char *dst, const char *src, size_t max) — ASCII lowercase
.globl _lower_copy
_lower_copy:
    mov  x9, #0
Llc_loop:
    cmp  x9, x2
    b.hs Llc_end
    ldrb w10, [x1, x9]
    cbz  w10, Llc_end
    sub  w11, w10, #'A'
    cmp  w11, #25
    b.hi Llc_store
    add  w10, w10, #32
Llc_store:
    strb w10, [x0, x9]
    add  x9, x9, #1
    b    Llc_loop
Llc_end:
    strb wzr, [x0, x9]
    ret

.globl _isword
// int _isword(int c) — letters, digits, and any byte of a multi-byte character
_isword:
    cmp  w0, #0x80
    b.hs Liw_yes
    sub  w9, w0, #'0'
    cmp  w9, #9
    b.ls Liw_yes
    sub  w9, w0, #'a'
    cmp  w9, #25
    b.ls Liw_yes
    sub  w9, w0, #'A'
    cmp  w9, #25
    b.ls Liw_yes
    mov  w0, #0
    ret
Liw_yes:
    mov  w0, #1
    ret

// int _has_word(const char *hay, const char *word) — whole-word match
.globl _has_word
_has_word:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x20
    bl   _strlen
    mov  x21, x0
    cbz  x21, Lhw_no
    mov  x22, x19
Lhw_loop:
    mov  x0, x22
    mov  x1, x20
    bl   _strstr
    cbz  x0, Lhw_no
    mov  x23, x0
    cmp  x23, x19
    b.eq Lhw_after
    ldurb w0, [x23, #-1]
    bl   _isword
    cbnz w0, Lhw_next
Lhw_after:
    ldrb w0, [x23, x21]
    bl   _isword
    cbnz w0, Lhw_next
    mov  x0, #1
    LEAVE 0
Lhw_next:
    add  x22, x23, #1
    b    Lhw_loop
Lhw_no:
    mov  x0, #0
    LEAVE 0

// long _digits_before(const char *start, const char *p) -> number ending just before p, or -1
_digits_before:
    sub  x9, x1, #1
Ldb_space:
    cmp  x9, x0
    b.lo Ldb_none
    ldrb w10, [x9]
    cmp  w10, #' '
    b.ne Ldb_end
    sub  x9, x9, #1
    b    Ldb_space
Ldb_end:
    sub  w11, w10, #'0'
    cmp  w11, #9
    b.hi Ldb_none
    mov  x12, x9                      // last digit
Ldb_back:
    sub  x13, x9, #1
    cmp  x13, x0
    b.lo Ldb_parse
    ldrb w10, [x13]
    sub  w11, w10, #'0'
    cmp  w11, #9
    b.hi Ldb_parse
    mov  x9, x13
    b    Ldb_back
Ldb_parse:
    mov  x0, #0
Ldb_num:
    cmp  x9, x12
    b.hi Ldb_clamp
    ldrb w10, [x9]
    sub  w10, w10, #'0'
    mov  x11, #10
    mul  x0, x0, x11
    add  x0, x0, x10
    add  x9, x9, #1
    b    Ldb_num
Ldb_clamp:
    cmp  x0, #100
    b.ls Ldb_ret
    mov  x0, #100
Ldb_ret:
    ret
Ldb_none:
    mov  x0, #-1
    ret

.globl _digits_after
// long _digits_after(const char *p) -> number starting at p (after spaces), or -1
_digits_after:
    ldrb w10, [x0]
    cmp  w10, #' '
    b.ne Lda2_start
    add  x0, x0, #1
    b    _digits_after
Lda2_start:
    sub  w11, w10, #'0'
    cmp  w11, #9
    b.hi Lda2_none
    mov  x9, #0
Lda2_loop:
    ldrb w10, [x0]
    sub  w11, w10, #'0'
    cmp  w11, #9
    b.hi Lda2_done
    mov  x12, #10
    mul  x9, x9, x12
    add  x9, x9, x11
    add  x0, x0, #1
    b    Lda2_loop
Lda2_done:
    cmp  x9, #100
    b.ls Lda2_ret
    mov  x9, #100
Lda2_ret:
    mov  x0, x9
    ret
Lda2_none:
    mov  x0, #-1
    ret

// long _find_level(const char *s) -> 0..100 from "40%", "40 percent", "to 40", "at 40", "half"; or -1
.globl _find_level
_find_level:
    ENTER 0
    mov  x19, x0
    mov  w1, #'%'
    bl   _strchr
    cbz  x0, Lfl_percent
    mov  x1, x0
    mov  x0, x19
    bl   _digits_before
    tbz  x0, #63, Lfl_done
Lfl_percent:
    mov  x0, x19
    ADRL x1, Lw_percent_sp
    bl   _strstr
    cbz  x0, Lfl_to
    mov  x1, x0
    mov  x0, x19
    bl   _digits_before
    tbz  x0, #63, Lfl_done
Lfl_to:
    ADRL x20, Lw_to_sp
    bl   Lfl_after_word
    tbz  x0, #63, Lfl_done
    ADRL x20, Lw_at_sp
    bl   Lfl_after_word
    tbz  x0, #63, Lfl_done
    mov  x0, x19
    ADRL x1, Lw_half
    bl   _has_word
    cbz  w0, Lfl_none
    mov  x0, #50
    b    Lfl_done
Lfl_none:
    mov  x0, #-1
Lfl_done:
    LEAVE 0
// local helper: number after the word in x20 ("to ", "at "), searching x19; -1 if none
Lfl_after_word:
    stp  x29, x30, [sp, #-16]!
    mov  x21, x19
Lfa_loop:
    mov  x0, x21
    mov  x1, x20
    bl   _strstr
    cbz  x0, Lfa_none
    mov  x22, x0
    cmp  x22, x19
    b.eq Lfa_ok
    ldurb w0, [x22, #-1]
    bl   _isword
    cbnz w0, Lfa_next
Lfa_ok:
    add  x0, x22, #3
    bl   _digits_after
    tbz  x0, #63, Lfa_ret
Lfa_next:
    add  x21, x22, #1
    b    Lfa_loop
Lfa_none:
    mov  x0, #-1
Lfa_ret:
    ldp  x29, x30, [sp], #16
    ret

// ===========================================================================
// Home room output
// ===========================================================================

// void _home_say(const char *fmt, a, b, c) — a line in Home; when answering a
// remote command, also collected for the reply
.globl _home_say
_home_say:
    ENTER 512
    str  x1, [sp]
    str  x2, [sp, #8]
    str  x3, [sp, #16]
    mov  x2, x0
    add  x0, sp, #96
    mov  x1, #400
    bl   _snprintf
    ADRL x8, _g_home_idx
    ldr  x0, [x8]
    add  x1, sp, #96
    mov  x2, #1
    bl   _room_line
    ADRL x8, _g_remote_active
    ldr  x8, [x8]
    cbz  x8, Lhs_done
    add  x0, sp, #96                  // skip the leading "· "
    ldrb w9, [x0]
    cmp  w9, #0xC2
    b.ne Lhs_append
    add  x0, x0, #3
Lhs_append:
    bl   _reply_add
Lhs_done:
    LEAVE 512

// void _home_say0(const char *text)
.globl _home_say0
_home_say0:
    ENTER 0
    mov  x1, x0
    ADRL x0, Ls_pct_s
    bl   _home_say
    LEAVE 0

// void _reply_add(const char *line) — "a; b; c" up to REPLY_MAX bytes
_reply_add:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_reply_len
    ldr  x20, [x8]
    cbz  x20, Lra2_copy
    ADRL x0, _g_reply
    ADRL x1, Ls_semi
    mov  x2, #REPLY_MAX
    bl   _strlcat
Lra2_copy:
    ADRL x0, _g_reply
    mov  x1, x19
    mov  x2, #REPLY_MAX
    bl   _strlcat
    ADRL x8, _g_reply_len
    str  x0, [x8]
    LEAVE 0

// void _home_help(void)
.globl _home_help
_home_help:
    ENTER 0
    ADRL x19, Lhelp
Lhh_loop:
    ldr  x0, [x19], #8
    cbz  x0, Lhh_done
    bl   _home_say0
    b    Lhh_loop
Lhh_done:
    LEAVE 0

// void _home_list(long filter) — "list devices": what's connected, room by room.
//   filter 0 = everything, -1 = lights only, else devices having any of those CAP_ bits
.globl _home_list
_home_list:
    ENTER 64                          // [96] filter  [104] shown  [112] line length
    str  x0, [sp, #96]
    str  xzr, [sp, #104]
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cbnz x9, Lhl_go
    ADRL x0, Ls_no_devices
    bl   _home_say0
    bl   _hue_status
    LEAVE 64
Lhl_go:
    ldr  x9, [sp, #96]
    cbnz x9, Lhl_rooms
    bl   _list_summary                // "Connected: SmartThings 10 · Hue 5 · ..."
Lhl_rooms:
    mov  x20, #0                      // i
Lhl_room_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lhl_runnables
    mov  x0, x20
    ldr  x1, [sp, #96]
    bl   _list_wanted
    cbz  x0, Lhl_room_next
    mov  x0, x20                      // this room already listed?
    bl   _room_of
    mov  x21, x0
    mov  x22, #0
Lhl_seen:
    cmp  x22, x20
    b.hs Lhl_new_room
    mov  x0, x22
    ldr  x1, [sp, #96]
    bl   _list_wanted
    cbz  x0, Lhl_seen_next
    mov  x0, x22
    bl   _room_of
    mov  x1, x21
    bl   _strcmp
    cbz  w0, Lhl_room_next
Lhl_seen_next:
    add  x22, x22, #1
    b    Lhl_seen
Lhl_new_room:                         // "· Living Room: TV (on) · Lamp (off, 40%)"
    ADRL x0, _g_list_line
    mov  x1, #480
    ADRL x2, Lf_room_head
    mov  x3, x21
    ldrb w9, [x21]
    cbnz w9, Lhl_head
    ADRL x3, Ls_no_room
Lhl_head:
    bl   _sfmt
    mov  x23, #0                      // items on this line
    mov  x22, x20
Lhl_item:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs Lhl_flush
    mov  x0, x22
    ldr  x1, [sp, #96]
    bl   _list_wanted
    cbz  x0, Lhl_item_next
    mov  x0, x22
    bl   _room_of
    mov  x1, x21
    bl   _strcmp
    cbnz w0, Lhl_item_next
    ADRL x0, _g_list_line             // a long room goes on to a second line
    bl   _strlen
    cmp  x0, #330
    b.lo Lhl_append
    bl   _list_flush
    ADRL x0, _g_list_line
    ADRL x1, Ls_cont
    mov  x2, #480
    bl   _strlcpy
    mov  x23, #0
Lhl_append:
    cbz  x23, Lhl_first
    ADRL x0, _g_list_line
    ADRL x1, Ls_dot_sep
    mov  x2, #480
    bl   _strlcat
Lhl_first:
    mov  x0, x22
    bl   _dev_brief
    mov  x1, x0
    ADRL x0, _g_list_line
    mov  x2, #480
    bl   _strlcat
    add  x23, x23, #1
    ldr  x9, [sp, #104]
    add  x9, x9, #1
    str  x9, [sp, #104]
Lhl_item_next:
    add  x22, x22, #1
    b    Lhl_item
Lhl_flush:
    bl   _list_flush
Lhl_room_next:
    add  x20, x20, #1
    b    Lhl_room_loop
Lhl_runnables:
    ldr  x9, [sp, #96]
    cbnz x9, Lhl_end
    mov  x0, #K_SHORTCUT              // then shortcuts and scenes, one line each
    ADRL x1, Ls_h_shortcuts
    bl   _list_runnables
    mov  x0, #K_ST_SCENE
    ADRL x1, Ls_h_scenes
    bl   _list_runnables
    LEAVE 64
Lhl_end:
    ldr  x9, [sp, #104]
    cbnz x9, Lhl_done
    ADRL x0, Ls_none_such
    bl   _home_say0
Lhl_done:
    LEAVE 64

// void _list_flush(void) — say the line built so far
_list_flush:
    ENTER 0
    ADRL x0, _g_list_line
    bl   _home_say0
    LEAVE 0

// long _list_wanted(long idx, long filter) -> 1 if it belongs in the list
.globl _list_wanted
_list_wanted:
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x8, #D_KIND]
    ADRL x10, _g_kind_on              // its service switched off: not listed
    ldrb w10, [x10, x9]
    cbz  w10, Llw_no
    cmp  x9, #K_BLES                  // sensors have their own list ("sensors")
    b.eq Llw_no
    cmp  x9, #K_SHORTCUT              // runnables get their own lines
    b.eq Llw_no
    cmp  x9, #K_ST_SCENE
    b.eq Llw_no
    ldr  x10, [x8, #D_CAPS]
    tst  x10, #CAP_ON
    b.ne Llw_device
    tst  x10, #CAP_RUN                // Home Assistant scenes and scripts
    b.ne Llw_no
Llw_device:
    cbz  x1, Llw_yes
    cmn  x1, #1
    b.eq Llw_lights
    tst  x10, x1
    b.eq Llw_no
Llw_yes:
    mov  x0, #1
    ret
Llw_lights:                           // lights: switchable and dimmable/colour, not a TV or fan
    cmp  x9, #K_HUE_GROUP
    b.eq Llw_no
    tst  x10, #CAP_ON
    b.eq Llw_no
    mov  x11, #(CAP_LEVEL | CAP_COLOR | CAP_CT)
    tst  x10, x11
    b.eq Llw_no
    mov  x11, #CAP_LOCK
    movk x11, #((CAP_TV | CAP_FAN) >> 16), lsl #16
    tst  x10, x11
    b.ne Llw_no
    mov  x0, #1
    ret
Llw_no:
    mov  x0, #0
    ret

// const char *_room_of(long idx) -> its room's name, or "" if not known
.globl _room_of
_room_of:
    ADRL x8, _g_devs
    add  x0, x8, x0, lsl #DEV_SHIFT
    add  x0, x0, #D_ROOM
    ldrb w9, [x0]
    cmp  w9, #'#'
    b.ne Lro_ret
    ADRL x0, Ls_empty
Lro_ret:
    ret

// const char *_dev_brief(long idx) -> "TV (on)", "Desk lamp (on, 40%)", "Front Door"
.globl _dev_brief
_dev_brief:
    ENTER 0
    ADRL x8, _g_devs
    add  x19, x8, x0, lsl #DEV_SHIFT
    add  x3, x19, #D_NAME
    ldr  x9, [x19, #D_ON]
    ldr  x4, [x19, #D_LEVEL]
    ADRL x2, Lf_brief_plain
    tbnz x9, #63, Lbr_fmt
    ADRL x5, Ls_st_on_w
    cmp  x9, #0
    b.ne Lbr_on
    ADRL x5, Ls_st_off_w
    ADRL x2, Lf_brief_state
    mov  x4, x5
    b    Lbr_fmt
Lbr_on:
    ADRL x2, Lf_brief_state
    mov  x9, x4
    mov  x4, x5
    tbnz x9, #63, Lbr_fmt
    cmp  x9, #100
    b.hi Lbr_fmt
    mov  x5, x9
    ADRL x2, Lf_brief_level
Lbr_fmt:
    ADRL x0, _g_brief
    mov  x1, #120
    bl   _sfmt
    ADRL x0, _g_brief
    LEAVE 0

// void _list_summary(void) — one line: how many of each kind
_list_summary:
    ENTER 16
    ADRL x0, _g_list_line
    ADRL x1, Ls_connected_head
    mov  x2, #480
    bl   _strlcpy
    mov  x20, #1                      // kind
    mov  x23, #0                      // pieces
Lls_kind:
    cmp  x20, #K_LAST
    b.hi Lls_say
    cmp  x20, #K_HUE_GROUP            // Hue rooms count with Hue
    b.eq Lls_next
    mov  x21, #0                      // count
    mov  x22, #0
Lls_count:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs Lls_counted
    ADRL x8, _g_devs
    add  x8, x8, x22, lsl #DEV_SHIFT
    add  x22, x22, #1
    ldr  x9, [x8, #D_KIND]
    cmp  x9, x20
    b.eq Lls_one
    cmp  x20, #K_HUE_LIGHT
    b.ne Lls_count
    cmp  x9, #K_HUE_GROUP
    b.ne Lls_count
Lls_one:
    add  x21, x21, #1
    b    Lls_count
Lls_counted:
    cbz  x21, Lls_next
    cbz  x23, Lls_piece
    ADRL x0, _g_list_line
    ADRL x1, Ls_dot_sep
    mov  x2, #480
    bl   _strlcat
Lls_piece:
    ADRL x8, Lsumnames
    ldr  x3, [x8, x20, lsl #3]
    mov  x4, x21
    ADRL x0, _g_brief
    mov  x1, #120
    ADRL x2, Lf_sum_piece
    bl   _sfmt
    ADRL x0, _g_list_line
    ADRL x1, _g_brief
    mov  x2, #480
    bl   _strlcat
    add  x23, x23, #1
Lls_next:
    add  x20, x20, #1
    b    Lls_kind
Lls_say:
    bl   _list_flush
    LEAVE 16

// void _list_runnables(long kind, const char *heading) — "Shortcuts (24): a · b · c"
_list_runnables:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0                      // index
    mov  x23, #0                      // on this line
Llr2_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Llr2_end
    ADRL x8, _g_devs
    add  x22, x8, x21, lsl #DEV_SHIFT
    add  x21, x21, #1
    ldr  x9, [x22, #D_KIND]
    cmp  x9, x19
    b.ne Llr2_loop
    cbnz x23, Llr2_more
    ADRL x0, _g_list_line
    mov  x1, #480
    ADRL x2, Lf_room_head
    mov  x3, x20
    bl   _sfmt
    b    Llr2_add
Llr2_more:
    ADRL x0, _g_list_line
    bl   _strlen
    cmp  x0, #330
    b.lo Llr2_sep
    bl   _list_flush
    ADRL x0, _g_list_line
    ADRL x1, Ls_cont
    mov  x2, #480
    bl   _strlcpy
    b    Llr2_add
Llr2_sep:
    ADRL x0, _g_list_line
    ADRL x1, Ls_dot_sep
    mov  x2, #480
    bl   _strlcat
Llr2_add:
    ADRL x0, _g_list_line
    add  x1, x22, #D_NAME
    mov  x2, #480
    bl   _strlcat
    add  x23, x23, #1
    b    Llr2_loop
Llr2_end:
    cbz  x23, Llr2_done
    bl   _list_flush
Llr2_done:
    LEAVE 16

// ===========================================================================
// For the scanner: devices asmmesh controls, one row each
// ===========================================================================

// long _home_dev_count(void)
.globl _home_dev_count
_home_dev_count:
    ENTER 0
    mov  x19, #0
    mov  x20, #0
Lhc2_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lhc2_done
    mov  x0, x19
    mov  x1, #0
    bl   _list_wanted
    add  x20, x20, x0
    add  x19, x19, #1
    b    Lhc2_loop
Lhc2_done:
    mov  x0, x20
    LEAVE 0

// long _home_dev_nth(long n) -> registry index of the n-th listed device, or -1
.globl _home_dev_nth
_home_dev_nth:
    ENTER 0
    mov  x21, x0
    mov  x19, #0
Lhn_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lhn_none
    mov  x0, x19
    mov  x1, #0
    bl   _list_wanted
    cbz  x0, Lhn_next
    cbz  x21, Lhn_hit
    sub  x21, x21, #1
Lhn_next:
    add  x19, x19, #1
    b    Lhn_loop
Lhn_hit:
    mov  x0, x19
    LEAVE 0
Lhn_none:
    mov  x0, #-1
    LEAVE 0

// const char *_kind_name(long idx) -> "SmartThings", "Hue light", "TV"...
.globl _kind_name
_kind_name:
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    ldr  x10, [x8, #D_CAPS]
    tst  x10, #0x800000               // CAP_TV
    b.ne Lkn_tv
    ldr  x9, [x8, #D_KIND]
    cmp  x9, #K_LAST
    csel x9, xzr, x9, hi
    ADRL x8, Lkinds
    ldr  x0, [x8, x9, lsl #3]
    ret
Lkn_tv:
    ADRL x0, Ls_k_tv
    ret

// char *_state_text(long idx, char *buf) — "on", "off", "on · 40%", or a dash
.globl _state_text
_state_text:
    ENTER 0
    mov  x20, x1
    ADRL x8, _g_devs
    add  x19, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x19, #D_ON]
    ldr  x4, [x19, #D_LEVEL]
    ADRL x1, Ls_dash
    tbnz x9, #63, Lstx_copy
    ADRL x1, Ls_st_off_w
    cbz  x9, Lstx_copy
    ADRL x1, Ls_st_on_w
    tbnz x4, #63, Lstx_copy
    cmp  x4, #100
    b.hi Lstx_copy
    mov  x3, x4
    mov  x0, x20
    mov  x1, #32
    ADRL x2, Lf_on_level
    bl   _sfmt
    mov  x0, x20
    LEAVE 0
Lstx_copy:
    mov  x0, x20
    mov  x2, #32
    bl   _strlcpy
    mov  x0, x20
    LEAVE 0

// char *_caps_text(long idx, char *buf, size_t max) — "on/off · brightness · colour ..."
.globl _caps_text
_caps_text:
    ENTER 0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    ldr  x19, [x8, #D_CAPS]
    strb wzr, [x20]
    ADRL x22, Lcapnames
Lct2_loop:
    ldp  x9, x1, [x22], #16
    cbz  x1, Lct2_done
    tst  x19, x9
    b.eq Lct2_loop
    ldrb w10, [x20]
    cbz  w10, Lct2_add
    str  x1, [sp]                     // keep x1 while adding the separator
    mov  x0, x20
    ADRL x1, Ls_dot_sep
    mov  x2, x21
    bl   _strlcat
    ldr  x1, [sp]
Lct2_add:
    mov  x0, x20
    mov  x2, x21
    bl   _strlcat
    b    Lct2_loop
Lct2_done:
    mov  x0, x20
    LEAVE 0

// void _home_refresh(void) — ask every backend again
.globl _home_refresh
_home_refresh:
    ENTER 0
    ADRL x0, Ls_refreshing
    bl   _home_say0
    bl   _hue_load
    bl   _st_load
    bl   _sc_load
    bl   _cloud_load
    bl   _lan_refresh
    bl   _udp_discover
    LEAVE 0

// void _home_init(void) — greet, then start the backends
.globl _home_init
_home_init:
    ENTER 0
    mov  x0, #HOME_ID
    bl   _room_find
    tbnz x0, #63, Lhi_go
    ADRL x8, _g_home_idx
    str  x0, [x8]
Lhi_go:
    ADRL x0, Ls_intro
    bl   _home_say0
    bl   _rules_init
    bl   _spin_init
    bl   _svc_load                    // every integration has a switch; all start off
    bl   _svc_start_all               //   (services.s starts the ones you turned on)
    mov  x0, #0                       // saved tokens: read off the main thread, because
    mov  x1, #0                       // after an update macOS may ask before handing
    bl   _dispatch_get_global_queue   // them over, and the app mustn't freeze meanwhile
    mov  x1, #0
    ADRL x2, _kc_worker
    bl   _dispatch_async_f
    LEAVE 0

// void _kc_worker(void *unused) — background
_kc_worker:
    ENTER 0
    bl   _id_kc_read                  // our identity key and the private rooms' keys
    bl   _crypto_kc_read              // SmartThings and cloud tokens: read by services.s
    //                                   only when you switch those on
    bl   _extras_kc_read
    LDGOT x0, __dispatch_main_q
    mov  x1, #0
    ADRL x2, _kc_ready
    bl   _dispatch_async_f
    LEAVE 0

// void _kc_ready(void *unused) — main thread: connect whatever has a token
_kc_ready:
    ENTER 0
    bl   _crypto_init
    bl   _id_ready
    LEAVE 0

// void _home_command(const char *text, int voice) — the Home room's input
.globl _home_command
_home_command:
    ENTER 0
    mov  x19, x0
    ADRL x2, Ls_you_typed
    ADRL x8, Ls_you_said
    cmp  w1, #0
    csel x2, x8, x2, ne
    ADRL x8, _g_home_idx
    ldr  x0, [x8]
    mov  x1, #0
    mov  x3, x19
    bl   _room_fmt
    ldrb w9, [x19]
    cmp  w9, #'@'
    b.eq Lhc_remote
    mov  x0, x19                      // weather, rules, where is my …
    bl   _extra_command
    cbnz x0, Lhc_done
    mov  x0, x19
    bl   _cmd_parse
    bl   _cmd_exec
    bl   _ui_lists_changed
Lhc_done:
    LEAVE 0
Lhc_remote:
    mov  x0, x19
    bl   _cmd_remote
    LEAVE 0

// ===========================================================================
// Remote commands over the mesh
// ===========================================================================

// void _cmd_remote(const char *text) — "@Name command"
_cmd_remote:
    ENTER 16
    add  x19, x0, #1                  // after '@'
    mov  x20, #-1                     // best node
    mov  x21, #0                      // its nick length
    mov  x22, #0
Lcr_loop:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs Lcr_chosen
    ADRL x8, _g_nodes
    add  x23, x8, x22, lsl #NODE_SHIFT
    add  x0, x23, #N_NICK
    bl   _strlen
    mov  x24, x0
    cbz  x24, Lcr_next
    cmp  x24, x21
    b.ls Lcr_next
    mov  x0, x19
    add  x1, x23, #N_NICK
    mov  x2, x24
    bl   _strncasecmp
    cbnz w0, Lcr_next
    ldrb w9, [x19, x24]
    cbz  w9, Lcr_take
    cmp  w9, #' '
    b.ne Lcr_next
Lcr_take:
    mov  x20, x22
    mov  x21, x24
Lcr_next:
    add  x22, x22, #1
    b    Lcr_loop
Lcr_chosen:
    tbnz x20, #63, Lcr_nobody
    add  x19, x19, x21
Lcr_skip:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.ne Lcr_have
    add  x19, x19, #1
    b    Lcr_skip
Lcr_have:
    cbz  w9, Lcr_empty
    ADRL x8, _g_nodes
    add  x23, x8, x20, lsl #NODE_SHIFT
    mov  w0, #T_CMD
    ldr  x1, [x23, #N_ID]
    mov  x2, x19
    bl   _mesh_send_cmd
    mov  x9, x0
    add  x1, x23, #N_NICK
    mov  x2, x19
    ADRL x0, Ls_asked
    ADRL x8, Ls_asked_held
    cmp  x9, #0
    csel x0, x8, x0, eq
    bl   _home_say
    LEAVE 16
Lcr_nobody:
    ADRL x0, Ls_nobody
    bl   _home_say0
    LEAVE 16
Lcr_empty:
    ADRL x0, Ls_say_what
    bl   _home_say0
    LEAVE 16

// void _cmd_incoming(uint64 from, const char *nick, const char *text)
//   Called from the mesh receive path: ask on the main thread, later.
.globl _cmd_incoming
_cmd_incoming:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_cmds_for_me
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    mov  x0, #SVC_MESH                // "Mesh commands" switched off: say so, run nothing
    bl   _svc_on
    cbnz x0, Lci_allowed
    ADRL x8, _g_window
    ldr  x8, [x8]
    cbz  x8, Lci_done
    mov  x1, x20
    mov  x2, x21
    ADRL x0, Lf_mesh_off
    bl   _home_say
    b    Lci_done
Lci_allowed:
    ADRL x8, _g_window
    ldr  x8, [x8]
    cbz  x8, Lci_done                 // selftest: count it, nothing to ask
    mov  x0, #264                     // +0 from, +8 nick[24], +32 text[232]
    bl   _malloc
    cbz  x0, Lci_done
    mov  x22, x0
    str  x19, [x22]
    add  x0, x22, #8
    mov  x1, x20
    mov  x2, #24
    bl   _strlcpy
    add  x0, x22, #32
    mov  x1, x21
    mov  x2, #232
    bl   _strlcpy
    ADRL x0, _cmd_incoming_cb
    mov  x1, x22
    bl   _main_later
Lci_done:
    LEAVE 0

// void _cmd_incoming_cb(void *ctx) — Allow / Allow for 10 minutes / Deny, then run
_cmd_incoming_cb:
    ENTER 512
    mov  x19, x0
    ldr  x0, [x19]
    bl   _allow_check
    cbnz x0, Lcc_run
    bl   _ui_show
    add  x9, x19, #8
    str  x9, [sp]
    add  x0, sp, #96
    mov  x1, #160
    ADRL x2, Ls_remote_q
    bl   _snprintf
    add  x9, x19, #32
    str  x9, [sp]
    add  x0, sp, #256
    mov  x1, #256
    ADRL x2, Ls_remote_info
    bl   _snprintf
    add  x0, sp, #96
    add  x1, sp, #256
    bl   _alert3
    mov  x20, x0
    cmp  x20, #2
    b.eq Lcc_deny
    cmp  x20, #1
    b.ne Lcc_run
    ldr  x0, [x19]
    bl   _allow_add
Lcc_run:
    add  x1, x19, #8
    add  x2, x19, #32
    ADRL x0, Ls_remote_ran
    bl   _home_say
    ADRL x8, _g_reply
    strb wzr, [x8]
    ADRL x8, _g_reply_len
    str  xzr, [x8]
    ADRL x8, _g_remote_active
    mov  x9, #1
    str  x9, [x8]
    add  x0, x19, #32
    ldrb w9, [x0]
    cmp  w9, #'@'                     // no forwarding chains
    b.eq Lcc_after
    bl   _cmd_parse
    bl   _cmd_exec
Lcc_after:
    ADRL x8, _g_remote_active
    str  xzr, [x8]
    bl   _ui_lists_changed
    ADRL x8, _g_reply_len
    ldr  x9, [x8]
    ADRL x2, _g_reply
    cbnz x9, Lcc_send
    ADRL x2, Ls_done_word
    b    Lcc_send
Lcc_deny:
    add  x1, x19, #8
    ADRL x0, Ls_remote_denied
    bl   _home_say
    ADRL x2, Ls_declined
Lcc_send:
    mov  w0, #T_CMDRES
    ldr  x1, [x19]
    bl   _mesh_send_cmd
    mov  x0, x19
    bl   _free
    LEAVE 512

// void _cmd_result_in(const char *nick, const char *text) — a reply for us
.globl _cmd_result_in
_cmd_result_in:
    ENTER 0
    mov  x2, x1
    mov  x1, x0
    ADRL x0, Ls_replied
    bl   _home_say
    LEAVE 0

// long _alert3(const char *msg, const char *info) -> 0 Allow, 1 Allow 10 min, 2 Deny
_alert3:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    CLS  Ls_NSAlert
    MSG0 Ls_new
    mov  x21, x0
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setMessageText
    mov  x0, x20
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setInformativeText
    ADRL x0, Ls_allow
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_addButtonWithTitle
    ADRL x0, Ls_allow10
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_addButtonWithTitle
    ADRL x0, Ls_deny
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_addButtonWithTitle
    mov  x0, x21
    MSG0 Ls_runModal
    mov  x19, x0
    mov  x0, x21
    MSG0 Ls_release
    sub  x0, x19, #1000
    cmp  x0, #2
    b.ls Lal_done
    mov  x0, #2
Lal_done:
    LEAVE 0

// long _allow_check(uint64 id) -> 1 if allowed right now
_allow_check:
    ENTER 0
    mov  x19, x0
    mov  x0, #0
    bl   _time
    ADRL x8, _g_allow
    mov  x9, #0
Lac_loop:
    cmp  x9, #ALLOW_N
    b.hs Lac_no
    ldr  x10, [x8]
    cmp  x10, x19
    b.ne Lac_next
    ldr  x11, [x8, #8]
    cmp  x11, x0
    b.gt Lac_yes
Lac_next:
    add  x8, x8, #16
    add  x9, x9, #1
    b    Lac_loop
Lac_no:
    mov  x0, #0
    LEAVE 0
Lac_yes:
    mov  x0, #1
    LEAVE 0

// void _allow_add(uint64 id) — allowed for the next 10 minutes
_allow_add:
    ENTER 0
    mov  x19, x0
    mov  x0, #0
    bl   _time
    add  x20, x0, #600
    ADRL x8, _g_allow
    mov  x9, #0
    mov  x12, x8                      // fallback slot: the first one
Laa_loop:
    cmp  x9, #ALLOW_N
    b.hs Laa_put
    ldr  x10, [x8]
    cmp  x10, x19
    b.eq Laa_this
    ldr  x11, [x8, #8]
    cmp  x11, x0                      // expired: reuse
    b.gt Laa_next
    mov  x12, x8
Laa_next:
    add  x8, x8, #16
    add  x9, x9, #1
    b    Laa_loop
Laa_this:
    mov  x12, x8
Laa_put:
    str  x19, [x12]
    str  x20, [x12, #8]
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lf_mesh_off: .asciz "\302\267 \360\237\232\253 %s asked this Mac to \342\200\234%s\342\200\235 \342\200\224 mesh commands are switched off (Settings: \342\214\230,)."
Ls_NSAlert:          .asciz "NSAlert"
Ls_new:              .asciz "new"
Ls_release:          .asciz "release"
Ls_setMessageText:   .asciz "setMessageText:"
Ls_setInformativeText: .asciz "setInformativeText:"
Ls_addButtonWithTitle: .asciz "addButtonWithTitle:"
Ls_runModal:         .asciz "runModal"


Lw_half:        .asciz "half"
Lw_percent_sp:  .asciz " percent"
Lw_to_sp:       .asciz "to "
Lw_at_sp:       .asciz "at "
Ls_empty:            .asciz ""
Ls_pct_s:            .asciz "%s"
Ls_semi:             .asciz "; "
Ls_you_typed:        .asciz "you: %s"
Ls_you_said:         .asciz "\360\237\216\244 %s"
Ls_intro:            .asciz "\302\267 This is your Home room. It stays on this Mac. Say or type things like \342\200\234kitchen lights off\342\200\235, \342\200\234dim living room to 30%\342\200\235, \342\200\234bedroom blue\342\200\235, \342\200\234TV volume 20\342\200\235, \342\200\234open Netflix\342\200\235, \342\200\234thermostat to 70\342\200\235 or \342\200\234good night\342\200\235. Say \342\200\234help\342\200\235 for more."
Ls_help1:            .asciz "\302\267 Lights: \342\200\234kitchen on\342\200\235, \342\200\234all lights off\342\200\235, \342\200\234dim bedroom to 20%\342\200\235, \342\200\234desk lamp blue\342\200\235, \342\200\234all lights warm\342\200\235, \342\200\234living room brighter\342\200\235."
Ls_help2:            .asciz "\302\267 TV: \342\200\234TV off\342\200\235, \342\200\234TV volume 20\342\200\235, \342\200\234louder\342\200\235, \342\200\234mute the TV\342\200\235, \342\200\234channel 7\342\200\235, \342\200\234channel up\342\200\235, \342\200\234HDMI 2\342\200\235, \342\200\234open Netflix\342\200\235 (YouTube, Prime Video, Disney+, Apple TV, Spotify, Plex, Hulu), \342\200\234pause\342\200\235, \342\200\234play\342\200\235, \342\200\234press home\342\200\235, \342\200\234go back\342\200\235."
Ls_help3:            .asciz "\302\267 Home: \342\200\234set the thermostat to 70\342\200\235, \342\200\234heat to 68\342\200\235, \342\200\234cool to 74\342\200\235, \342\200\234thermostat auto\342\200\235, \342\200\234fan high\342\200\235, \342\200\234close the blinds\342\200\235, \342\200\234blinds 50%\342\200\235, \342\200\234start the vacuum\342\200\235, \342\200\234vacuum go home\342\200\235, \342\200\234close the garage\342\200\235, \342\200\234what's the temperature\342\200\235, \342\200\234is the front door locked\342\200\235."
Ls_help4:            .asciz "\302\267 Safety: unlocking and opening a garage always ask on this Mac first and never work over the mesh. Shortcuts and scenes run only when you say their whole name, e.g. \342\200\234good night\342\200\235."
Ls_help5:            .asciz "\302\267 Connect: \342\200\234pair hue\342\200\235 (press the bridge button first), \342\200\234connect smartthings\342\200\235, \342\200\234connect home assistant\342\200\235, \342\200\234connect lifx\342\200\235, \342\200\234connect govee\342\200\235, \342\200\234pair nanoleaf\342\200\235 (hold its power button 5 s first). WLED, Elgato, Shelly, Roku and WiZ on your Wi-Fi are found by themselves."
Ls_help6:            .asciz "\302\267 \342\200\234list devices\342\200\235 shows everything connected, room by room (also \342\200\234list lights\342\200\235, \342\200\234list tvs\342\200\235, \342\200\234list locks\342\200\235), \342\200\234status\342\200\235 or \342\200\234what's the kitchen\342\200\235 reports, \342\200\234refresh\342\200\235 looks again. Mesh \342\206\222 Mesh Scanner shows everything nearby, with Connect & Pair. Someone else's Mac: \342\200\234@Anna hallway on\342\200\235 \342\200\224 they're asked to allow it."
Ls_help7:            .asciz "\302\267 More: \342\200\234help more\342\200\235 \342\200\224 weather, schedules and rules (\342\200\234at sunset porch light on\342\200\235), \342\200\234where are my headphones\342\200\235, tracker alerts, notifications to your phone, IFTTT, \342\200\234say \342\200\246\342\200\235."
Ls_no_devices:       .asciz "\302\267 No devices yet. Say \342\200\234help\342\200\235 to see how to connect Hue, SmartThings, Home Assistant, LIFX, Govee and the rest."
Ls_k_unknown:        .asciz "device"
Ls_k_huelight:       .asciz "Hue light"
Ls_k_huegroup:       .asciz "Hue room"
Ls_k_st:             .asciz "SmartThings"
Ls_k_sc:             .asciz "Shortcut"
Ls_k_ble:            .asciz "Hue Bluetooth bulb"
Ls_k_stscene:        .asciz "SmartThings scene"
Ls_k_wled:           .asciz "WLED"
Ls_k_elgato:         .asciz "Elgato light"
Ls_k_shelly:         .asciz "Shelly"
Ls_k_nano:           .asciz "Nanoleaf"
Ls_k_lifx:           .asciz "LIFX"
Ls_k_govee:          .asciz "Govee"
Ls_k_ha:             .asciz "Home Assistant"
Ls_k_roku:           .asciz "Roku"
Ls_k_wiz:            .asciz "WiZ"
Ls_k_sonos:          .asciz "Sonos"
Ls_k_kasa:           .asciz "TP-Link Kasa"
Ls_k_bles:     .asciz "Bluetooth sensor"
Ls_k_tv:             .asciz "TV"
Ls_k_hue:            .asciz "Hue"
Ls_k_sc_n:           .asciz "Shortcuts"
Ls_k_stscene_n:      .asciz "SmartThings scenes"
Ls_list_line:        .asciz "\302\267 %s \342\200\224 %s%s"
Lf_room_head:        .asciz "\302\267 %s: "
Ls_no_room:          .asciz "Not in a room"
Ls_cont:             .asciz "   \342\200\246 "
Ls_dot_sep:          .asciz " \302\267 "
Lf_brief_plain:      .asciz "%s"
Lf_brief_state:      .asciz "%s (%s)"
Lf_brief_level:      .asciz "%s (%s, %ld%%)"
Ls_st_on_w:          .asciz "on"
Lf_on_level:         .asciz "on \302\267 %ld%%"
Ls_dash:             .asciz "\342\200\224"
Lc_on:   .asciz "on/off"
Lc_lvl:  .asciz "brightness"
Lc_col:  .asciz "colour"
Lc_ct:   .asciz "white tones"
Lc_lock: .asciz "lock"
Lc_vol:  .asciz "volume"
Lc_ch:   .asciz "channels"
Lc_in:   .asciz "inputs"
Lc_med:  .asciz "play/pause"
Lc_apps: .asciz "apps"
Lc_shd:  .asciz "open/close"
Lc_thm:  .asciz "temperature setting"
Lc_fan:  .asciz "fan speed"
Lc_gar:  .asciz "garage door"
Lc_vlv:  .asciz "valve"
Lc_vac:  .asciz "cleaning"
Lc_keys: .asciz "remote keys"
Lc_tmp:  .asciz "reads temperature"
Lc_st:   .asciz "status"
Ls_st_off_w:         .asciz "off"
Ls_connected_head:   .asciz "\302\267 Connected: "
Lf_sum_piece:        .asciz "%s %ld"
Ls_h_shortcuts:      .asciz "Shortcuts (say the whole name)"
Ls_h_scenes:         .asciz "Scenes (say the whole name)"
Ls_none_such:        .asciz "\302\267 None of those are connected."
Ls_st_on:            .asciz ", on"
Ls_st_off:           .asciz ", off"
Ls_refreshing:       .asciz "\302\267 Looking for devices again\342\200\246"
Ls_asked:            .asciz "\302\267 Asked %s: \342\200\234%s\342\200\235 \342\200\224 waiting for their OK."
Ls_asked_held:       .asciz "\302\267 Asked %s: \342\200\234%s\342\200\235 \342\200\224 nobody in range right now, so it may not arrive."
Ls_nobody:           .asciz "\302\267 Nobody on the mesh has that name. Use a name from People, like \342\200\234@Anna kitchen off\342\200\235."
Ls_say_what:         .asciz "\302\267 Add what they should do, like \342\200\234@Anna kitchen off\342\200\235."
Ls_remote_q:         .asciz "%s wants to use this Mac's devices"
Ls_remote_info:      .asciz "They asked: \342\200\234%s\342\200\235\n\nIt came over the mesh, signed by them \342\200\224 only allow people you trust. Unlocking doors and opening garages are never allowed this way."
Ls_allow:            .asciz "Allow"
Ls_allow10:          .asciz "Allow for 10 Minutes"
Ls_deny:             .asciz "Deny"
Ls_remote_ran:       .asciz "\302\267 %s asked: \342\200\234%s\342\200\235"
Ls_remote_denied:    .asciz "\302\267 Declined %s's request."
Ls_declined:         .asciz "declined"
Ls_done_word:        .asciz "done"
Ls_replied:          .asciz "\302\267 %s replied: %s"

.section __DATA,__const
.p2align 3
Lhelp:
    .quad Ls_help1, Ls_help2, Ls_help3, Ls_help4, Ls_help5, Ls_help6, Ls_help7, 0
Lkinds:
    .quad Ls_k_unknown, Ls_k_huelight, Ls_k_huegroup, Ls_k_st, Ls_k_sc, Ls_k_ble
    .quad Ls_k_stscene, Ls_k_wled, Ls_k_elgato, Ls_k_shelly, Ls_k_nano, Ls_k_lifx
    .quad Ls_k_govee, Ls_k_ha, Ls_k_roku, Ls_k_wiz, Ls_k_sonos, Ls_k_kasa, Ls_k_bles
Lsumnames:
    .quad Ls_k_unknown, Ls_k_hue, Ls_k_hue, Ls_k_st, Ls_k_sc_n, Ls_k_ble, Ls_k_stscene_n
    .quad Ls_k_wled, Ls_k_elgato, Ls_k_shelly, Ls_k_nano, Ls_k_lifx
    .quad Ls_k_govee, Ls_k_ha, Ls_k_roku, Ls_k_wiz, Ls_k_sonos, Ls_k_kasa, Ls_k_bles
Lcapnames:
    .quad CAP_ON, Lc_on
    .quad CAP_LEVEL, Lc_lvl
    .quad CAP_COLOR, Lc_col
    .quad CAP_CT, Lc_ct
    .quad CAP_LOCK, Lc_lock
    .quad CAP_VOLUME, Lc_vol
    .quad CAP_CHANNEL, Lc_ch
    .quad CAP_INPUT, Lc_in
    .quad CAP_MEDIA, Lc_med
    .quad CAP_APPS, Lc_apps
    .quad CAP_SHADE, Lc_shd
    .quad CAP_THERMO, Lc_thm
    .quad CAP_FAN, Lc_fan
    .quad CAP_GARAGE, Lc_gar
    .quad CAP_VALVE, Lc_vlv
    .quad CAP_VACUUM, Lc_vac
    .quad CAP_KEYS, Lc_keys
    .quad CAP_TEMP, Lc_tmp
    .quad CAP_STATUS, Lc_st
    .quad 0, 0
