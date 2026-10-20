// scan_core.s — what the scanner lists and does, shared by the Mac's Mesh Scanner
// window (scanner.s) and the iPhone and iPad's Nearby screen: one list of everything
// around (people on the mesh, Bluetooth LE devices, Bonjour and UPnP devices on the
// network, paired Bluetooth devices, devices asmmesh controls), each row's cells and
// details, and Connect & Pair / Set Up.

.include "macros.inc"

.data
.p2align 3
.globl _g_scan_text
.zerofill __DATA,__bss,_g_scan_text,1024,4
.globl _g_scan_tmp
.zerofill __DATA,__bss,_g_scan_tmp,160,4

.text
.p2align 2


// long _scan_rows(void)
.globl _scan_rows
_scan_rows:
    ENTER 0
    ADRL x8, _g_node_count
    ldr  x19, [x8]
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    add  x19, x19, x9
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    add  x19, x19, x9
    ADRL x8, _g_ssdp_count
    ldr  x9, [x8]
    add  x19, x19, x9
    bl   _bt_count
    add  x19, x19, x0
    bl   _home_dev_count
    add  x0, x19, x0
    LEAVE 0

// (long type, long index) _scan_row(long row) — type 0 mesh 1 BLE 2 Bonjour 3 UPnP 4 paired
//   5 a device asmmesh controls (index into the registry), -1 none
.globl _scan_row
_scan_row:
    ENTER 0
    mov  x19, x0
    tbnz x19, #63, Lsr_none
    mov  x20, #0
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.lo Lsr_hit
    sub  x19, x19, x9
    mov  x20, #1
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.lo Lsr_hit
    sub  x19, x19, x9
    mov  x20, #2
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.lo Lsr_hit
    sub  x19, x19, x9
    mov  x20, #3
    ADRL x8, _g_ssdp_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.lo Lsr_hit
    sub  x19, x19, x9
    mov  x20, #4
    bl   _bt_count
    cmp  x19, x0
    b.lo Lsr_hit
    sub  x19, x19, x0
    mov  x20, #5                      // devices asmmesh controls
    mov  x0, x19
    bl   _home_dev_nth
    tbnz x0, #63, Lsr_none
    mov  x19, x0
    b    Lsr_hit
Lsr_none:
    mov  x0, #-1
    mov  x1, #0
    LEAVE 0
Lsr_hit:
    mov  x0, x20
    mov  x1, x19
    LEAVE 0

// const char *_ago(long when, char *buf) — "now", "12s ago", "3m ago"
.globl _ago
_ago:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, #0
    bl   _time
    sub  x3, x0, x19
    ADRL x0, Ls_now
    cmp  x3, #2
    b.lt Lago_ret
    ADRL x2, Ls_f_secs
    cmp  x3, #120
    b.lt Lago_fmt
    mov  x10, #60
    udiv x3, x3, x10
    ADRL x2, Ls_f_mins
Lago_fmt:
    mov  x0, x20
    mov  x1, #64
    bl   _sfmt
    mov  x0, x20
Lago_ret:
    LEAVE 0

// const char *_dbm(long rssi, char *buf) — "-60 dBm" or a dash
.globl _dbm
_dbm:
    ENTER 0
    mov  x3, x0
    ADRL x0, Ls_dash
    cbz  x3, Ldbm_ret
    mov  x19, x1
    mov  x0, x1
    mov  x1, #32
    ADRL x2, Ls_f_dbm
    bl   _sfmt
    mov  x0, x19
Ldbm_ret:
    LEAVE 0

// const char *_scan_cell(char column, long row, char *buf) — one cell of the scanner's
//   list: 'n' name, 'k' kind, 's' signal, 'l' last heard (Mac table and iPhone list)
.globl _scan_cell
_scan_cell:
    ENTER 16
    mov  x19, x2
    mov  x20, x1
    and  w21, w0, #0xff
    strb wzr, [x19]
    mov  x0, x20
    bl   _scan_row
    mov  x22, x0
    mov  x23, x1
    cmp  x22, #0
    b.eq Lsv_node
    cmp  x22, #1
    b.eq Lsv_near
    cmp  x22, #2
    b.eq Lsv_lan
    cmp  x22, #3
    b.eq Lsv_ssdp
    cmp  x22, #4
    b.eq Lsv_bt
    cmp  x22, #5
    b.eq Lsv_home
    mov  x0, x19
    LEAVE 16

Lsv_home:
    cmp  w21, #'n'
    b.eq Lsvh_name
    cmp  w21, #'k'
    b.eq Lsvh_kind
    cmp  w21, #'s'
    b.eq Lsvh_state
    cmp  w21, #'l'
    b.eq Lsvh_room
    mov  x0, x23
    mov  x1, x19
    mov  x2, #120
    bl   _caps_text
    LEAVE 16
Lsvh_name:
    ADRL x8, _g_devs
    add  x0, x8, x23, lsl #DEV_SHIFT
    add  x0, x0, #D_NAME
    LEAVE 16
Lsvh_kind:
    mov  x0, x23
    bl   _kind_name
    LEAVE 16
Lsvh_state:
    mov  x0, x23
    mov  x1, x19
    bl   _state_text
    LEAVE 16
Lsvh_room:
    mov  x0, x23
    bl   _room_of
    ldrb w9, [x0]
    cbnz w9, Lsvh_ret
    ADRL x0, Ls_dash
Lsvh_ret:
    LEAVE 16

Lsv_node:
    ADRL x8, _g_nodes
    add  x24, x8, x23, lsl #NODE_SHIFT
    cmp  w21, #'n'
    b.eq Lsvm_name
    cmp  w21, #'k'
    b.eq Lsvm_kind
    cmp  w21, #'s'
    b.eq Lsvm_sig
    cmp  w21, #'l'
    b.eq Lsvm_seen
    ldr  x4, [x24, #N_RELAYED]        // details
    ldr  x3, [x24, #N_HOPS]
    ADRL x2, Ls_f_hops_n
    cmp  x3, #1
    b.hi Lsvm_det
    mov  x3, x4
    ADRL x2, Ls_f_hops
Lsvm_det:
    mov  x0, x19
    mov  x1, #120
    bl   _sfmt
    mov  x0, x19
    LEAVE 16
Lsvm_name:
    mov  x0, x24
    bl   _node_name
    LEAVE 16
Lsvm_kind:
    ADRL x0, Ls_k_mesh
    LEAVE 16
Lsvm_sig:
    ldr  x0, [x24, #N_RSSI]
    mov  x1, x19
    bl   _dbm
    LEAVE 16
Lsvm_seen:                            // in range: how far; else how many hops
    ldr  x0, [x24, #N_RSSI]
    cbz  x0, Lsvm_hops
    mov  x1, #0x7fff
    bl   _dist_dm
    tbnz x0, #63, Lsvm_hops
    mov  x1, x19
    bl   _dist_text
    LEAVE 16
Lsvm_hops:
    ldr  x3, [x24, #N_HOPS]
    mov  x0, x19
    mov  x1, #64
    ADRL x2, Ls_f_hops_away
    bl   _sfmt
    mov  x0, x19
    LEAVE 16

Lsv_near:
    ADRL x8, _g_near
    add  x24, x8, x23, lsl #NEAR_SHIFT
    cmp  w21, #'n'
    b.eq Lsvn_name
    cmp  w21, #'k'
    b.eq Lsvn_kind
    cmp  w21, #'s'
    b.eq Lsvn_sig
    cmp  w21, #'l'
    b.eq Lsvn_seen
    ldr  x9, [x24, #NR_FLAGS]         // details: the most useful thing it says
    ADRL x0, Ls_d_hk
    tst  x9, #NF_HK_OPEN
    b.ne Lsvn_ret
    ADRL x0, Ls_d_matter
    tst  x9, #NF_MATTER
    b.ne Lsvn_ret
    add  x0, x24, #NR_INFO
    ldrb w10, [x0]
    cbnz w10, Lsvn_ret
    add  x0, x24, #NR_SVCS
    ldrb w10, [x0]
    cbnz w10, Lsvn_ret
    ADRL x0, Ls_d_conn
    tst  x9, #NF_CONN
    b.ne Lsvn_ret
    ADRL x0, Ls_d_bcast
Lsvn_ret:
    LEAVE 16
Lsvn_name:                            // its name, or its brand
    mov  x0, x23
    mov  x1, x19
    mov  x2, #120
    bl   _near_label
    cbnz x0, Lsvn_ret
    ADRL x0, Ls_unnamed
    LEAVE 16
Lsvn_kind:
    mov  x0, x23
    mov  x1, x19
    mov  x2, #120
    bl   _near_kind
    LEAVE 16
Lsvn_sig:
    ldr  x0, [x24, #NR_RSSI]
    mov  x1, x19
    bl   _dbm
    LEAVE 16
Lsvn_seen:                            // about how far away
    mov  x0, x23
    bl   _near_dm
    mov  x1, x19
    bl   _dist_text
    LEAVE 16

Lsv_lan:
    mov  x0, x23
    mov  w1, w21
    mov  x2, x19
    bl   _lan_cell
    LEAVE 16
Lsv_ssdp:
    mov  x0, x23
    mov  w1, w21
    mov  x2, x19
    bl   _ssdp_cell
    LEAVE 16

Lsv_bt:
    cmp  w21, #'n'
    b.eq Lsvb_name
    cmp  w21, #'k'
    b.eq Lsvb_kind
    cmp  w21, #'s'
    b.eq Lsvb_sig
    cmp  w21, #'l'
    b.eq Lsvb_where
    mov  x0, x23
    mov  x1, x19
    mov  x2, #120
    bl   _bt_details
    LEAVE 16
Lsvb_name:
    mov  x0, x23
    mov  x1, x19
    mov  x2, #120
    bl   _bt_name
    LEAVE 16
Lsvb_kind:
    mov  x0, x23
    bl   _bt_kind
    LEAVE 16
Lsvb_sig:
    mov  x0, x23
    bl   _bt_connected
    mov  x9, x0
    ADRL x0, Ls_dash
    cbz  x9, Lsvb_ret
    ADRL x0, Ls_connected
Lsvb_ret:
    LEAVE 16
Lsvb_where:
    ADRL x0, Ls_paired
    LEAVE 16

// ---------------------------------------------------------------------------
// Details pane
// ---------------------------------------------------------------------------

// void _cat(const char *s) — append to _g_scan_text
.globl _cat
_cat:
    mov  x1, x0
    ADRL x0, _g_scan_text
    mov  x2, #1024
    b    _strlcat

// void _scan_details_text(long row) — into _g_scan_text
.globl _scan_details_text
_scan_details_text:
    ENTER 64                          // [96] small buffers
    ADRL x8, _g_scan_text
    strb wzr, [x8]
    bl   _scan_row
    mov  x22, x0
    mov  x23, x1
    cmp  x22, #0
    b.eq Lsd_node
    cmp  x22, #1
    b.eq Lsd_near
    cmp  x22, #2
    b.eq Lsd_lan
    cmp  x22, #3
    b.eq Lsd_ssdp
    cmp  x22, #4
    b.eq Lsd_bt
    cmp  x22, #5
    b.eq Lsd_home
    ADRL x0, Ls_pick
    bl   _cat
    LEAVE 64

Lsd_node:
    ADRL x8, _g_nodes
    add  x24, x8, x23, lsl #NODE_SHIFT
    ldr  x0, [x24, #N_RSSI]
    add  x1, sp, #96
    bl   _dbm
    mov  x21, x0
    ldr  x4, [x24, #N_RELAYED]
    ldr  x3, [x24, #N_HOPS]
    ADRL x2, Ls_f_hops_n
    cmp  x3, #1
    b.hi Lsd_node_h
    mov  x3, x4
    ADRL x2, Ls_f_hops
Lsd_node_h:
    ADRL x0, _g_scan_tmp
    mov  x1, #160
    bl   _sfmt
    mov  x0, x24
    bl   _node_name
    mov  x3, x0
    mov  x4, x21
    ADRL x5, _g_scan_tmp
    ADRL x0, _g_scan_text
    mov  x1, #1024
    ADRL x2, Lf_d_node
    bl   _sfmt
    LEAVE 64

Lsd_near:
    ADRL x8, _g_near
    add  x24, x8, x23, lsl #NEAR_SHIFT
    mov  x0, x23                      // "Name — kind"
    ADRL x1, _g_scan_tmp
    mov  x2, #160
    bl   _near_label
    cbnz x0, Lsdn_name
    ADRL x0, Ls_unnamed
Lsdn_name:
    bl   _cat
    ADRL x0, Ls_dash_sp
    bl   _cat
    mov  x0, x23
    ADRL x1, _g_scan_tmp
    mov  x2, #160
    bl   _near_kind
    bl   _cat
    ADRL x0, Ls_where_sp              // "\nWhere: ≈3 m · in this room (from signal strength; heard 2s ago)"
    bl   _cat
    mov  x0, x23
    bl   _near_dm
    add  x1, sp, #96
    bl   _dist_text
    bl   _cat
    ADRL x0, Ls_where_note
    bl   _cat
    ldr  x0, [x24, #NR_SEEN]
    add  x1, sp, #96
    bl   _ago
    bl   _cat
    ADRL x0, Ls_close_paren
    bl   _cat
    ADRL x0, Ls_signal_sp             // "\nSignal -60 dBm · transmit power 4 dBm · accepts connections"
    bl   _cat
    ldr  x0, [x24, #NR_RSSI]
    add  x1, sp, #96
    bl   _dbm
    bl   _cat
    ldr  x9, [x24, #NR_FLAGS]
    tst  x9, #NF_TX
    b.eq Lsdn_conn
    ADRL x0, Ls_tx_sp
    bl   _cat
    add  x0, sp, #96
    mov  x1, #32
    ADRL x2, Ls_f_num
    ldr  x3, [x24, #NR_TX]
    bl   _sfmt
    add  x0, sp, #96
    bl   _cat
    ADRL x0, Ls_dbm
    bl   _cat
Lsdn_conn:
    ldr  x9, [x24, #NR_FLAGS]
    ADRL x0, Ls_conn_yes
    tst  x9, #NF_CONN
    b.ne Lsdn_conn_say
    ADRL x0, Ls_conn_no
Lsdn_conn_say:
    bl   _cat
    ADRL x0, Ls_services_sp
    bl   _cat
    add  x0, x24, #NR_SVCS
    ldrb w9, [x0]
    cbnz w9, Lsdn_svcs
    ADRL x0, Ls_none
Lsdn_svcs:
    bl   _cat
    add  x0, x24, #NR_INFO            // what Connect & Pair read
    ldrb w9, [x0]
    cbz  w9, Lsdn_hint
    ADRL x0, Ls_nl
    bl   _cat
    ADRL x0, _g_scan_tmp
    mov  x1, #160
    ADRL x2, Ls_x_read
    add  x3, x24, #NR_INFO
    bl   _sfmt
    ADRL x0, _g_scan_tmp
    bl   _cat
Lsdn_hint:
    ADRL x0, Ls_nl
    bl   _cat
    ldr  x9, [x24, #NR_FLAGS]
    ADRL x0, Ls_x_hk
    tst  x9, #NF_HK_OPEN
    b.ne Lsdn_hint_say
    ADRL x0, Ls_x_matter
    tst  x9, #NF_MATTER
    b.ne Lsdn_hint_say
    ADRL x0, Ls_x_conn
    tst  x9, #NF_CONN
    b.ne Lsdn_hint_say
    ADRL x0, Ls_x_bcast
Lsdn_hint_say:
    bl   _cat
    LEAVE 64

Lsd_lan:
    mov  x0, x23
    ADRL x1, _g_scan_text
    mov  x2, #1024
    bl   _lan_details
    LEAVE 64
Lsd_ssdp:
    mov  x0, x23
    ADRL x1, _g_scan_text
    mov  x2, #1024
    bl   _ssdp_details
    LEAVE 64
Lsd_bt:
    mov  x0, x23
    ADRL x1, _g_scan_tmp
    mov  x2, #80
    bl   _bt_name
    mov  x0, x23
    bl   _bt_kind
    mov  x21, x0
    mov  x0, x23
    add  x1, sp, #96
    mov  x2, #64
    bl   _bt_details
    mov  x5, x0
    ADRL x3, _g_scan_tmp
    mov  x4, x21
    ADRL x0, _g_scan_text
    mov  x1, #1024
    ADRL x2, Lf_d_bt
    bl   _sfmt
    LEAVE 64

Lsd_home:                             // "Name — SmartThings in Living Room / State: on / Can: ..."
    ADRL x8, _g_devs
    add  x24, x8, x23, lsl #DEV_SHIFT
    add  x0, x24, #D_NAME
    bl   _cat
    ADRL x0, Ls_dash_sp
    bl   _cat
    mov  x0, x23
    bl   _kind_name
    bl   _cat
    mov  x0, x23
    bl   _room_of
    mov  x21, x0
    ldrb w9, [x21]
    cbz  w9, Lsdh_state
    ADRL x0, Ls_in_sp
    bl   _cat
    mov  x0, x21
    bl   _cat
Lsdh_state:
    ADRL x0, Ls_state_sp
    bl   _cat
    mov  x0, x23
    add  x1, sp, #96
    bl   _state_text
    bl   _cat
    ADRL x0, Ls_can_sp
    bl   _cat
    mov  x0, x23
    ADRL x1, _g_scan_tmp
    mov  x2, #160
    bl   _caps_text
    bl   _cat
    ADRL x0, Ls_home_hint2
    bl   _cat
    LEAVE 64
// void _scan_pair_row(long row) — Connect & Pair
.globl _scan_pair_row
_scan_pair_row:
    ENTER 0
    tbnz x0, #63, Lsp_norow
    bl   _scan_row
    mov  x19, x1
    cmp  x0, #0
    b.eq Lsp_mesh
    cmp  x0, #1
    b.eq Lsp_near
    cmp  x0, #2
    b.eq Lsp_lan
    cmp  x0, #3
    b.eq Lsp_ssdp
    cmp  x0, #4
    b.eq Lsp_bt
    cmp  x0, #5
    b.eq Lsp_home
Lsp_norow:
    ADRL x0, Ls_no_row
    bl   _scan_say
    LEAVE 0
Lsp_mesh:
    ADRL x0, Ls_mesh_already
    bl   _scan_say
    LEAVE 0
Lsp_near:
    mov  x0, x19
    bl   _near_inspect
    LEAVE 0
Lsp_lan:
    mov  x0, x19
    bl   _scan_lan
    LEAVE 0
Lsp_ssdp:
    mov  x0, x19
    bl   _ssdp_open_web
    LEAVE 0
Lsp_bt:
    mov  x0, x19
    bl   _bt_connect
    LEAVE 0
Lsp_home:                             // already connected: say how to use it
    ADRL x8, _g_devs
    add  x1, x19, #0
    add  x1, x8, x1, lsl #DEV_SHIFT
    add  x1, x1, #D_NAME
    mov  x2, x1
    ADRL x0, Ls_home_ready
    bl   _scan_say
    LEAVE 0

// void _scan_setup_row(long row) — Set Up
.globl _scan_setup_row
_scan_setup_row:
    ENTER 0
    tbnz x0, #63, Lsp_norow
    bl   _scan_row
    mov  x19, x1
    cmp  x0, #0
    b.eq Lsp_mesh
    cmp  x0, #1
    b.eq Lsu_near
    cmp  x0, #2
    b.eq Lsp_lan
    cmp  x0, #3
    b.eq Lsp_ssdp
    cmp  x0, #5
    b.eq Lsp_home
    cmp  x0, #4
    b.ne Lsp_norow
    bl   _bt_settings
    LEAVE 0
Lsu_near:
    ADRL x8, _g_near
    add  x9, x8, x19, lsl #NEAR_SHIFT
    ldr  x9, [x9, #NR_FLAGS]
    mov  x10, #(NF_HK_OPEN | NF_MATTER)
    tst  x9, x10
    b.eq Lsu_near_none
    bl   _open_home_app
    LEAVE 0
Lsu_near_none:
    ADRL x0, Ls_near_setup_none
    bl   _scan_say
    LEAVE 0

// void _scan_lan(long i) — pair / connect it, or open its web page
_scan_lan:
    ENTER 16
    mov  x19, x0
    bl   _lan_set_up
    cbnz x0, Lsl_done
    mov  x0, x19
    bl   _lan_has_web
    cbz  x0, Lsl_nothing
    mov  x0, x19
    bl   _lan_open_web
    LEAVE 16
Lsl_nothing:
    mov  x0, x19
    mov  w1, #'n'
    add  x2, sp, #96
    ADRL x2, _g_scan_tmp
    bl   _lan_cell
    mov  x1, x0
    ADRL x0, Ls_lan_nothing
    bl   _scan_say
Lsl_done:
    LEAVE 16


.section __TEXT,__cstring,cstring_literals
Ls_f_num:             .asciz "%ld"
Ls_f_dbm:             .asciz "%ld dBm"
Ls_f_secs:            .asciz "%lds ago"
Ls_f_mins:            .asciz "%ldm ago"
Ls_dash:              .asciz "\342\200\224"
Ls_now:               .asciz "now"
Ls_unnamed:           .asciz "(unnamed)"
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
