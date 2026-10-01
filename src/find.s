// find.s — where things are.
//
//   this Mac is in the office     then "lights on" here means the office lights,
//                                 and other Macs learn which room this one is in
//   where am i
//   where are my headphones       what this Mac hears, what other Macs on the mesh
//                                 hear (they share it every 30 s), home devices
//                                 with that name, and paired Bluetooth devices
//   trackers · trust trackers     AirTags, SmartTags and Tiles nearby; a warning when
//                                 one that isn't yours stays with you 10+ minutes
//
// SEEN   +12 sender[8] +20 flags (1: sealed) +21 nlen +22 nick, then
//        room length, room, count, then per device: rssi (int8), name length, name
// Sent with 2 hops to live: the next room over, not the whole mesh.

.include "macros.inc"

.set SG_MAX,     64
.set SG_SHIFT,   7
.set SG_NODE,    0
.set SG_TIME,    8
.set SG_RSSI,    16
.set SG_NICK,    24
.set SG_ROOM,    48
.set SG_NAME,    80
.set SG_NAME_MAX, 40
.set SEEN_TTL,   2
.set SEEN_MAXN,  12

.data
.p2align 3
.globl _g_my_room
.zerofill __DATA,__bss,_g_my_room,32,4
.zerofill __DATA,__bss,_g_sight,8192,4
.zerofill __DATA,__bss,_g_q,64,4
.zerofill __DATA,__bss,_g_kind,64,4
.zerofill __DATA,__bss,_g_dist,64,4
.zerofill __DATA,__bss,_g_rs,48,4
.zerofill __DATA,__bss,_g_rs2,48,4
.zerofill __DATA,__bss,_g_best,64,4
.zerofill __DATA,__bss,_g_fline,480,4
.zerofill __DATA,__bss,_g_seen_pkt,256,4
.zerofill __DATA,__bss,_g_seen_plain,256,4
.zerofill __DATA,__bss,_g_troom,32,4
.zerofill __DATA,__bss,_g_tname,48,4
.zerofill __DATA,__bss,_g_lroom,32,4

.text
.p2align 2

// void _find_init(void)
.globl _find_init
_find_init:
    ENTER 0
    ADRL x0, Ls_pref_room
    ADRL x1, _g_my_room
    mov  x2, #32
    bl   _pref_get
    bl   _bt_refresh                  // the paired list, for "where are my headphones"
    LEAVE 0

// "this Mac is in the office"
.globl _h_room_set
_h_room_set:
    ENTER 0
    mov  x19, x1
    mov  x20, x2
    mov  x0, x19
    bl   _skip_article
    sub  x9, x0, x19
    add  x20, x20, x9                 // same place in the original
    ldrb w9, [x20]
    cbz  w9, Lrm2_ask
    ADRL x0, _g_my_room
    mov  x1, x20
    mov  x2, #32
    bl   _strlcpy
    ADRL x0, _g_my_room
    bl   _utf8_fix
    ADRL x8, _g_my_room
    ldrb w9, [x8]
    sub  w10, w9, #'a'
    cmp  w10, #25
    b.hi Lrm2_save
    sub  w9, w9, #32
    strb w9, [x8]
Lrm2_save:
    ADRL x0, Ls_pref_room
    ADRL x1, _g_my_room
    bl   _pref_set
    ADRL x0, Lf_room_set
    ADRL x1, _g_my_room
    ADRL x2, _g_my_room
    bl   _home_say
    LEAVE 0
Lrm2_ask:
    ADRL x0, Ls_room_ask
    bl   _home_say0
    LEAVE 0

.globl _h_where_am_i
_h_where_am_i:
    ENTER 0
    ADRL x1, _g_my_room
    ldrb w9, [x1]
    cbz  w9, Lwa2_unknown
    ADRL x0, Lf_room_is
    bl   _home_say
    LEAVE 0
Lwa2_unknown:
    ADRL x0, Ls_room_unknown
    bl   _home_say0
    LEAVE 0

// void _room_suffix(const char *room, char *out48) — " (Kitchen)" or ""
_room_suffix:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    strb wzr, [x20]
    ldrb w9, [x19]
    cbz  w9, Lrsf_done
    mov  x0, x20
    mov  x1, #48
    ADRL x2, Lf_paren
    mov  x3, x19
    bl   _sfmt
Lrsf_done:
    LEAVE 0

// char *_dm_short(long dm, char *buf) — "≈3 m", "≈0.6 m"
_dm_short:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    tbnz x19, #63, Ldm_unknown
    cmp  x19, #10
    b.hs Ldm_whole
    mov  x0, x20
    mov  x1, #32
    ADRL x2, Lf_dm_dec
    mov  x3, x19
    bl   _sfmt
    mov  x0, x20
    LEAVE 0
Ldm_whole:
    add  x3, x19, #5
    mov  x9, #10
    udiv x3, x3, x9
    mov  x0, x20
    mov  x1, #32
    ADRL x2, Lf_dm
    bl   _sfmt
    mov  x0, x20
    LEAVE 0
Ldm_unknown:
    mov  x0, x20
    ADRL x1, Ls_q
    mov  x2, #32
    bl   _strlcpy
    mov  x0, x20
    LEAVE 0

// long _pres_age(const char *name) -> seconds since someone/something by that name was
//   heard (a Mac on the mesh, a Bluetooth name here, or one another Mac hears), or -1
.globl _pres_age
_pres_age:
    ENTER 16
    mov  x19, x0
    mov  x0, #0
    bl   _time
    mov  x20, x0
    mov  x21, #-1
    ldrb w9, [x19]
    cbz  w9, Lpa_done
    mov  x22, #0
Lpa_near:
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs Lpa_nodes0
    ADRL x8, _g_near
    add  x23, x8, x22, lsl #NEAR_SHIFT
    add  x0, x23, #NR_NAME
    ldrb w9, [x0]
    cbz  w9, Lpa_near_next
    mov  x1, x19
    bl   _strcasestr
    cbz  x0, Lpa_near_next
    ldr  x9, [x23, #NR_SEEN]
    sub  x9, x20, x9
    tbnz x21, #63, Lpa_near_take
    cmp  x9, x21
    b.ge Lpa_near_next
Lpa_near_take:
    mov  x21, x9
Lpa_near_next:
    add  x22, x22, #1
    b    Lpa_near
Lpa_nodes0:
    mov  x22, #0
Lpa_nodes:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs Lpa_sight0
    ADRL x8, _g_nodes
    add  x23, x8, x22, lsl #NODE_SHIFT
    add  x0, x23, #N_NICK
    ldrb w9, [x0]
    cbz  w9, Lpa_nodes_next
    mov  x1, x19
    bl   _strcasestr
    cbz  x0, Lpa_nodes_next
    ldr  x9, [x23, #N_SEEN]
    sub  x9, x20, x9
    tbnz x21, #63, Lpa_nodes_take
    cmp  x9, x21
    b.ge Lpa_nodes_next
Lpa_nodes_take:
    mov  x21, x9
Lpa_nodes_next:
    add  x22, x22, #1
    b    Lpa_nodes
Lpa_sight0:
    mov  x22, #0
Lpa_sight:
    cmp  x22, #SG_MAX
    b.hs Lpa_done
    ADRL x8, _g_sight
    add  x23, x8, x22, lsl #SG_SHIFT
    ldr  x9, [x23, #SG_TIME]
    cbz  x9, Lpa_sight_next
    add  x0, x23, #SG_NAME
    mov  x1, x19
    bl   _strcasestr
    cbz  x0, Lpa_sight_next
    ldr  x9, [x23, #SG_TIME]
    sub  x9, x20, x9
    tbnz x21, #63, Lpa_sight_take
    cmp  x9, x21
    b.ge Lpa_sight_next
Lpa_sight_take:
    mov  x21, x9
Lpa_sight_next:
    add  x22, x22, #1
    b    Lpa_sight
Lpa_done:
    mov  x0, x21
    LEAVE 16

// ---------------------------------------------------------------------------
// "where are my headphones"
// ---------------------------------------------------------------------------
.globl _h_find
_h_find:
    ENTER 80      // [96] found  [104] closest dm  [112] this Mac hears it  [120] now
    mov  x19, x1  // [128] tried the singular  [136] lines  [144] other Macs  [152] home lines
    mov  x0, #SVC_FIND
    bl   _svc_gate
    cbnz x0, Lfd_on
    LEAVE 80
Lfd_on:
    mov  x0, x19
    bl   _skip_article
    mov  x19, x0
    ldrb w9, [x19]
    cbz  w9, Lfd_usage
    ADRL x0, _g_q
    mov  x1, x19
    mov  x2, #64
    bl   _strlcpy
    str  xzr, [sp, #128]
Lfd_again:
    str  xzr, [sp, #96]
    str  xzr, [sp, #112]
    str  xzr, [sp, #136]
    str  xzr, [sp, #144]
    str  xzr, [sp, #152]
    MOVI x9, 0x7fffffff
    str  x9, [sp, #104]
    ADRL x8, _g_best
    strb wzr, [x8]
    mov  x0, #0
    bl   _time
    str  x0, [sp, #120]
    ADRL x0, _g_my_room
    ADRL x1, _g_rs
    bl   _room_suffix

    // ---- what this Mac hears
    mov  x20, #0
Lfd_near:
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lfd_remote
    ADRL x8, _g_near
    add  x21, x8, x20, lsl #NEAR_SHIFT
    ldr  x9, [x21, #NR_SEEN]
    ldr  x10, [sp, #120]
    sub  x22, x10, x9
    cmp  x22, #300
    b.gt Lfd_near_next
    mov  x0, x20
    ADRL x1, _g_kind
    mov  x2, #64
    bl   _near_kind
    add  x23, x21, #NR_NAME
    ldrb w9, [x23]
    cbz  w9, Lfd_near_kind
    mov  x0, x23
    ADRL x1, _g_q
    bl   _strcasestr
    cbnz x0, Lfd_near_hit
Lfd_near_kind:
    ADRL x0, _g_kind
    ADRL x1, _g_q
    bl   _strcasestr
    cbz  x0, Lfd_near_next
    ldrb w9, [x23]
    cbnz w9, Lfd_near_hit
    ADRL x23, _g_kind
Lfd_near_hit:
    ldr  x9, [sp, #96]
    add  x9, x9, #1
    str  x9, [sp, #96]
    mov  x9, #1
    str  x9, [sp, #112]
    ldr  x9, [sp, #136]
    cmp  x9, #5
    b.hs Lfd_near_next
    add  x9, x9, #1
    str  x9, [sp, #136]
    mov  x0, x20
    bl   _near_dm
    mov  x24, x0
    ADRL x1, _g_dist
    bl   _dist_text
    ADRL x0, Lf_find_near
    mov  x1, x23
    ADRL x2, _g_dist
    ADRL x3, _g_rs
    mov  x4, x22
    bl   _home_say4
    tbnz x24, #63, Lfd_near_next
    ldr  x9, [sp, #104]
    cmp  x24, x9
    b.ge Lfd_near_next
    str  x24, [sp, #104]
    ADRL x0, _g_best
    mov  x1, #64
    ADRL x2, Lf_this_mac
    ADRL x3, _g_rs
    bl   _sfmt
Lfd_near_next:
    add  x20, x20, #1
    b    Lfd_near

    // ---- what other Macs hear
Lfd_remote:
    mov  x20, #0
Lfd_rm:
    cmp  x20, #SG_MAX
    b.hs Lfd_summary
    ADRL x8, _g_sight
    add  x21, x8, x20, lsl #SG_SHIFT
    ldr  x9, [x21, #SG_TIME]
    cbz  x9, Lfd_rm_next
    ldr  x10, [sp, #120]
    sub  x22, x10, x9
    cmp  x22, #300
    b.gt Lfd_rm_next
    add  x0, x21, #SG_NAME
    ADRL x1, _g_q
    bl   _strcasestr
    cbz  x0, Lfd_rm_next
    ldr  x9, [sp, #96]
    add  x9, x9, #1
    str  x9, [sp, #96]
    ldr  x9, [sp, #144]
    add  x9, x9, #1
    str  x9, [sp, #144]
    cmp  x9, #6
    b.hi Lfd_rm_next
    ldr  x0, [x21, #SG_RSSI]
    mov  x1, #0x7fff
    bl   _dist_dm
    mov  x24, x0
    ADRL x1, _g_dist
    bl   _dm_short
    add  x0, x21, #SG_ROOM
    ADRL x1, _g_rs2
    bl   _room_suffix
    ADRL x0, _g_fline
    mov  x1, #480
    ADRL x2, Lf_find_remote
    add  x3, x21, #SG_NICK
    ADRL x4, _g_rs2
    add  x5, x21, #SG_NAME
    ADRL x6, _g_dist
    mov  x7, x22
    bl   _sfmt
    ADRL x0, _g_fline
    bl   _home_say0
    tbnz x24, #63, Lfd_rm_next
    ldr  x9, [sp, #104]
    cmp  x24, x9
    b.ge Lfd_rm_next
    str  x24, [sp, #104]
    ADRL x0, _g_best
    mov  x1, #64
    ADRL x2, Lf_two
    add  x3, x21, #SG_NICK
    ADRL x4, _g_rs2
    bl   _sfmt
Lfd_rm_next:
    add  x20, x20, #1
    b    Lfd_rm
Lfd_summary:
    ldr  x9, [sp, #112]
    ldr  x10, [sp, #144]
    add  x9, x9, x10
    cmp  x9, #2
    b.lo Lfd_home
    ADRL x1, _g_best
    ldrb w9, [x1]
    cbz  w9, Lfd_home
    ADRL x0, Lf_closest
    bl   _home_say

    // ---- home devices by that name
Lfd_home:
    mov  x20, #0
Lfd_hm:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lfd_bt
    ADRL x8, _g_devs
    add  x21, x8, x20, lsl #DEV_SHIFT
    add  x0, x21, #D_NAME
    ADRL x1, _g_q
    bl   _strcasestr
    cbz  x0, Lfd_hm_next
    ldr  x9, [sp, #96]
    add  x9, x9, #1
    str  x9, [sp, #96]
    ldr  x9, [sp, #152]
    add  x9, x9, #1
    str  x9, [sp, #152]
    cmp  x9, #6
    b.hi Lfd_hm_next
    mov  x0, x20
    bl   _room_of
    mov  x22, x0
    ADRL x23, Ls_empty
    ldrb w9, [x22]
    cbz  w9, Lfd_hm_kind
    ADRL x0, _g_rs2
    mov  x1, #48
    ADRL x2, Lf_in_room
    mov  x3, x22
    bl   _sfmt
    ADRL x23, _g_rs2
Lfd_hm_kind:
    mov  x0, x20
    bl   _kind_name
    mov  x22, x0
    mov  x0, x20
    bl   _dev_brief
    mov  x1, x0
    ADRL x0, Lf_find_dev
    mov  x2, x22
    mov  x3, x23
    bl   _home_say
Lfd_hm_next:
    add  x20, x20, #1
    b    Lfd_hm

    // ---- paired with this Mac
Lfd_bt:
    bl   _bt_count
    mov  x22, x0
    mov  x20, #0
Lfd_bt_loop:
    cmp  x20, x22
    b.hs Lfd_end
    mov  x0, x20
    ADRL x1, _g_tname
    mov  x2, #48
    bl   _bt_name
    ADRL x0, _g_tname
    ADRL x1, _g_q
    bl   _strcasestr
    cbz  x0, Lfd_bt_next
    ldr  x9, [sp, #96]
    add  x9, x9, #1
    str  x9, [sp, #96]
    mov  x0, x20
    bl   _bt_connected
    ADRL x2, Ls_bt_conn
    ADRL x9, Ls_bt_notconn
    cmp  x0, #0
    csel x2, x9, x2, eq
    ADRL x0, Lf_find_bt
    ADRL x1, _g_tname
    bl   _home_say
Lfd_bt_next:
    add  x20, x20, #1
    b    Lfd_bt_loop
Lfd_end:
    ldr  x9, [sp, #96]
    cbnz x9, Lfd_done
    ldr  x9, [sp, #128]
    cbnz x9, Lfd_none
    ADRL x0, _g_q                     // "keys" -> "key"
    bl   _strlen
    cmp  x0, #3
    b.lo Lfd_none
    ADRL x8, _g_q
    sub  x9, x0, #1
    ldrb w10, [x8, x9]
    cmp  w10, #'s'
    b.ne Lfd_none
    strb wzr, [x8, x9]
    mov  x9, #1
    str  x9, [sp, #128]
    b    Lfd_again
Lfd_none:
    ADRL x0, Lf_find_none
    mov  x1, x19
    bl   _home_say
Lfd_done:
    LEAVE 80
Lfd_usage:
    ADRL x0, Ls_find_usage
    bl   _home_say0
    LEAVE 80

// ---------------------------------------------------------------------------
// Sharing what this Mac hears
// ---------------------------------------------------------------------------

// void _seen_send(void) — every 30 s: the named devices heard in the last minute
.globl _seen_send
_seen_send:
    ENTER 32                          // [96] count  [104] entry  [112] name length
    mov  x0, #0
    bl   _time
    mov  x23, x0
    ADRL x0, _g_seen_pkt
    mov  w1, #T_SEEN
    bl   _pkt_begin
    ADRL x19, _g_seen_pkt
    mov  w9, #SEEN_TTL
    strb w9, [x19, #2]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x19, #12]
    strb wzr, [x19, #20]
    add  x0, x19, #21
    bl   _put_nick
    mov  x20, x0                      // body
    mov  x21, x0                      // where we write
    ADRL x0, _g_my_room
    bl   _strlen
    mov  x9, #31
    cmp  x0, x9
    csel x22, x9, x0, hi
    strb w22, [x21], #1
    mov  x0, x21
    ADRL x1, _g_my_room
    mov  x2, x22
    bl   _memcpy
    add  x21, x21, x22
    mov  x24, x21                     // the count goes here
    strb wzr, [x21], #1
    str  xzr, [sp, #96]
    mov  x22, #0
Lss_loop:
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs Lss_built
    ldr  x9, [sp, #96]
    cmp  x9, #SEEN_MAXN
    b.hs Lss_built
    ADRL x8, _g_near
    add  x10, x8, x22, lsl #NEAR_SHIFT
    ldrb w9, [x10, #NR_NAME]
    cbz  w9, Lss_next
    ldr  x9, [x10, #NR_SEEN]
    sub  x9, x23, x9
    cmp  x9, #60
    b.gt Lss_next
    ldr  x9, [x10, #NR_AVG]
    cbz  x9, Lss_next
    str  x10, [sp, #104]
    add  x0, x10, #NR_NAME
    bl   _strlen
    mov  x9, #24
    cmp  x0, x9
    csel x0, x9, x0, hi
    str  x0, [sp, #112]
    add  x9, x21, x0
    add  x9, x9, #2
    sub  x9, x9, x19
    cmp  x9, #(PKT_MAX - 8 - TRAILER) // room for the tag and the signature
    b.hi Lss_built
    ldr  x10, [sp, #104]
    ldr  x9, [x10, #NR_AVG]
    asr  x9, x9, #4
    strb w9, [x21]
    ldr  x9, [sp, #112]
    strb w9, [x21, #1]
    add  x0, x21, #2
    add  x1, x10, #NR_NAME
    ldr  x2, [sp, #112]
    bl   _memcpy
    ldr  x9, [sp, #112]
    add  x21, x21, x9
    add  x21, x21, #2
    ldr  x9, [sp, #96]
    add  x9, x9, #1
    str  x9, [sp, #96]
Lss_next:
    add  x22, x22, #1
    b    Lss_loop
Lss_built:
    ldr  x9, [sp, #96]
    cbz  x9, Lss_done
    strb w9, [x24]
    sub  x22, x21, x20                // body length
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, Lss_send
    mov  w9, #1
    strb w9, [x19, #20]
    mov  x0, x20
    mov  x1, x22
    add  x2, x19, #4
    bl   _crypto_seal
    mov  x22, x0
Lss_send:
    add  x1, x20, x22
    sub  x1, x1, x19
    mov  x0, x19
    bl   _pkt_finish                  // time and signature
    cbz  x0, Lss_done
    mov  x1, x0
    mov  x0, x19
    bl   _ble_broadcast
Lss_done:
    LEAVE 32

// void _seen_in(const uint8 *pkt, size_t len) — another Mac's SEEN (already validated
//   up to the nick; _g_nickbuf holds the sender's name)
.globl _seen_in
_seen_in:
    ENTER 32                          // [96] next  [104] length
    mov  x19, x0
    mov  x20, x1
    ldrb w9, [x19, #21]
    add  x21, x19, #22
    add  x21, x21, x9
    sub  x22, x20, #22
    sub  x22, x22, x9
    ldrb w9, [x19, #20]
    ADRL x8, _g_crypto_on
    ldr  x10, [x8]
    tbz  w9, #0, Lsi_plain
    cbz  x10, Lsi_done                // sealed and we have no passphrase
    mov  x0, x21
    mov  x1, x22
    add  x2, x19, #4
    ADRL x3, _g_seen_plain
    bl   _crypto_open
    tbnz x0, #63, Lsi_done
    mov  x22, x0
    ADRL x21, _g_seen_plain
    b    Lsi_parse
Lsi_plain:
    cbnz x10, Lsi_done                // with a passphrase, only sealed ones count
Lsi_parse:
    add  x22, x21, x22                // end
    cmp  x21, x22
    b.hs Lsi_done
    ldrb w9, [x21], #1                // room
    cmp  w9, #31
    b.hi Lsi_done
    add  x10, x21, x9
    cmp  x10, x22
    b.hi Lsi_done
    str  x10, [sp, #96]
    str  x9, [sp, #104]
    ADRL x0, _g_troom
    mov  x1, x21
    mov  x2, x9
    bl   _memcpy
    ADRL x8, _g_troom
    ldr  x9, [sp, #104]
    strb wzr, [x8, x9]
    ADRL x0, _g_troom
    bl   _utf8_fix
    ADRL x0, _g_troom
    bl   _sanitize
    ldr  x21, [sp, #96]
    cmp  x21, x22
    b.hs Lsi_done
    ldrb w23, [x21], #1               // how many
    cmp  w23, #16
    b.hi Lsi_done
Lsi_ent:
    cbz  x23, Lsi_done
    add  x9, x21, #2
    cmp  x9, x22
    b.hi Lsi_done
    ldrsb x24, [x21]
    ldrb w9, [x21, #1]
    cmp  w9, #32
    b.hi Lsi_done
    add  x21, x21, #2
    add  x10, x21, x9
    cmp  x10, x22
    b.hi Lsi_done
    str  x10, [sp, #96]
    str  x9, [sp, #104]
    ADRL x0, _g_tname
    mov  x1, x21
    mov  x2, x9
    bl   _memcpy
    ADRL x8, _g_tname
    ldr  x9, [sp, #104]
    strb wzr, [x8, x9]
    ADRL x0, _g_tname
    bl   _utf8_fix
    ADRL x0, _g_tname
    bl   _sanitize
    cmp  x24, #0
    b.ge Lsi_skip                     // not a signal strength
    ADRL x8, _g_tname
    ldrb w9, [x8]
    cbz  w9, Lsi_skip
    ldr  x0, [x19, #12]
    mov  x1, x24
    bl   _sight_put
Lsi_skip:
    ldr  x21, [sp, #96]
    sub  x23, x23, #1
    b    Lsi_ent
Lsi_done:
    LEAVE 32

// void _sight_put(uint64 node, long rssi) — _g_tname heard by that node (_g_nickbuf,
//   in _g_troom): replace its old entry, else an empty one, else the oldest
_sight_put:
    ENTER 16                          // [96] empty slot
    mov  x19, x0
    mov  x20, x1
    mov  x9, #-1
    str  x9, [sp, #96]
    mov  x21, #-1                     // same node and name
    mov  x22, #0                      // oldest
    mov  x23, #-1                     // its time (unsigned max)
    mov  x24, #0
Lsp_loop:
    cmp  x24, #SG_MAX
    b.hs Lsp_pick
    ADRL x8, _g_sight
    add  x10, x8, x24, lsl #SG_SHIFT
    ldr  x9, [x10, #SG_TIME]
    cbnz x9, Lsp_used
    ldr  x11, [sp, #96]
    tbz  x11, #63, Lsp_next
    str  x24, [sp, #96]
    b    Lsp_next
Lsp_used:
    cmp  x9, x23
    b.hs Lsp_same
    mov  x23, x9
    mov  x22, x24
Lsp_same:
    ldr  x11, [x10, #SG_NODE]
    cmp  x11, x19
    b.ne Lsp_next
    add  x0, x10, #SG_NAME
    ADRL x1, _g_tname
    bl   _strcmp
    cbnz w0, Lsp_next
    mov  x21, x24
    b    Lsp_pick
Lsp_next:
    add  x24, x24, #1
    b    Lsp_loop
Lsp_pick:
    tbz  x21, #63, Lsp_write
    ldr  x21, [sp, #96]
    tbz  x21, #63, Lsp_write
    mov  x21, x22
Lsp_write:
    ADRL x8, _g_sight
    add  x22, x8, x21, lsl #SG_SHIFT
    str  x19, [x22, #SG_NODE]
    mov  x0, #0
    bl   _time
    str  x0, [x22, #SG_TIME]
    str  x20, [x22, #SG_RSSI]
    add  x0, x22, #SG_NICK
    ADRL x1, _g_nickbuf
    mov  x2, #24
    bl   _strlcpy
    add  x0, x22, #SG_ROOM
    ADRL x1, _g_troom
    mov  x2, #32
    bl   _strlcpy
    add  x0, x22, #SG_NAME
    ADRL x1, _g_tname
    mov  x2, #SG_NAME_MAX
    bl   _strlcpy
    LEAVE 16

// ---------------------------------------------------------------------------
// Item trackers
// ---------------------------------------------------------------------------

// void _tracker_check(void) — every 10 s
.globl _tracker_check
_tracker_check:
    ENTER 0
    mov  x0, #0
    bl   _time
    mov  x21, x0
    mov  x19, #0
Ltc_loop:
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Ltc_done
    ADRL x8, _g_near
    add  x20, x8, x19, lsl #NEAR_SHIFT
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_TRACKER
    b.eq Ltc_next
    ldr  x9, [x20, #NR_TRUSTED]
    cbnz x9, Ltc_next
    ldr  x9, [x20, #NR_ALERTED]
    cbnz x9, Ltc_next
    ldr  x9, [x20, #NR_SEEN]
    sub  x9, x21, x9
    cmp  x9, #30
    b.gt Ltc_next
    ldr  x9, [x20, #NR_FIRST]
    cbz  x9, Ltc_next
    sub  x22, x21, x9
    cmp  x22, #600
    b.lt Ltc_next
    mov  x0, x19
    bl   _near_dm
    tbnz x0, #63, Ltc_next
    cmp  x0, #50                      // within about 5 m
    b.gt Ltc_next
    mov  x23, x0
    mov  x9, #1
    str  x9, [x20, #NR_ALERTED]
    mov  x0, x19
    ADRL x1, _g_kind
    mov  x2, #64
    bl   _near_kind
    mov  x0, x23
    ADRL x1, _g_dist
    bl   _dist_text
    mov  x9, #60
    udiv x2, x22, x9
    ADRL x0, Lf_tracker_alert
    ADRL x1, _g_kind
    ADRL x3, _g_dist
    bl   _home_say
    ADRL x0, Ls_tracker_main
    bl   _chat_line
    ADRL x0, Ls_tracker_push
    bl   _notify_quiet
    b    Ltc_done
Ltc_next:
    add  x19, x19, #1
    b    Ltc_loop
Ltc_done:
    LEAVE 0

// "trackers"
.globl _h_trackers
_h_trackers:
    ENTER 16                          // [96] shown
    mov  x0, #SVC_FIND
    bl   _svc_gate
    cbnz x0, Lht2_on
    LEAVE 16
Lht2_on:
    str  xzr, [sp, #96]
    mov  x0, #0
    bl   _time
    mov  x21, x0
    mov  x19, #0
Lht2_loop:
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lht2_end
    ADRL x8, _g_near
    add  x20, x8, x19, lsl #NEAR_SHIFT
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_TRACKER
    b.eq Lht2_next
    ldr  x9, [x20, #NR_SEEN]
    sub  x9, x21, x9
    cmp  x9, #120
    b.gt Lht2_next
    mov  x0, x19
    ADRL x1, _g_kind
    mov  x2, #64
    bl   _near_kind
    mov  x0, x19
    bl   _near_dm
    ADRL x1, _g_dist
    bl   _dist_text
    ldr  x9, [x20, #NR_FIRST]
    sub  x3, x21, x9
    mov  x9, #60
    udiv x3, x3, x9
    ADRL x4, Ls_empty
    ldr  x9, [x20, #NR_TRUSTED]
    cbz  x9, Lht2_say
    ADRL x4, Ls_yours
Lht2_say:
    ADRL x0, Lf_tracker_line
    ADRL x1, _g_kind
    ADRL x2, _g_dist
    bl   _home_say4
    ldr  x9, [sp, #96]
    add  x9, x9, #1
    str  x9, [sp, #96]
Lht2_next:
    add  x19, x19, #1
    b    Lht2_loop
Lht2_end:
    ldr  x9, [sp, #96]
    cbnz x9, Lht2_foot
    ADRL x0, Ls_no_trackers
    bl   _home_say0
Lht2_foot:
    ADRL x0, Ls_tracker_foot
    bl   _home_say0
    LEAVE 16

// "trust trackers" — the ones heard now are yours
.globl _h_trust
_h_trust:
    ENTER 0
    mov  x0, #0
    bl   _time
    mov  x21, x0
    mov  x22, #0
    mov  x19, #0
Ltr2_loop:
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Ltr2_end
    ADRL x8, _g_near
    add  x20, x8, x19, lsl #NEAR_SHIFT
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_TRACKER
    b.eq Ltr2_next
    ldr  x9, [x20, #NR_SEEN]
    sub  x9, x21, x9
    cmp  x9, #120
    b.gt Ltr2_next
    mov  x9, #1
    str  x9, [x20, #NR_TRUSTED]
    str  x9, [x20, #NR_ALERTED]
    add  x22, x22, #1
Ltr2_next:
    add  x19, x19, #1
    b    Ltr2_loop
Ltr2_end:
    ADRL x0, Lf_trusted
    mov  x1, x22
    bl   _home_say
    LEAVE 0

// void _near_prune(void) — every minute: forget devices unheard for 15 minutes, so the
//   table has room for new ones (Apple devices change their address every 15 min or so)
.globl _near_prune
_near_prune:
    ENTER 0
    mov  x0, #0
    bl   _time
    mov  x21, x0
    mov  x19, #0
Lnp_loop:
    ADRL x8, _g_near_count
    ldr  x22, [x8]
    cmp  x19, x22
    b.hs Lnp_done
    ADRL x8, _g_near
    add  x20, x8, x19, lsl #NEAR_SHIFT
    ldr  x9, [x20, #NR_FLAGS]
    mov  x10, #(NF_LINKED | NF_INSPECT)
    tst  x9, x10
    b.ne Lnp_next
    ldr  x9, [x20, #NR_SEEN]
    sub  x9, x21, x9
    cmp  x9, #900
    b.lt Lnp_next
    ldr  x0, [x20, #NR_P]
    cbz  x0, Lnp_move
    MSG0 Ls_release
Lnp_move:
    sub  x22, x22, #1
    ADRL x8, _g_near_count
    str  x22, [x8]
    cmp  x19, x22
    b.eq Lnp_done
    ADRL x8, _g_near
    add  x1, x8, x22, lsl #NEAR_SHIFT
    mov  x0, x20
    mov  x2, #(1 << NEAR_SHIFT)
    bl   _memcpy
    b    Lnp_loop                     // look at the one moved here
Lnp_next:
    add  x19, x19, #1
    b    Lnp_loop
Lnp_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// "lights on": which lights
// ---------------------------------------------------------------------------

// void _lights_room_filter(void) — after "every light" was chosen: if the command
//   names a room ("kitchen lights"), just that room's; otherwise, unless it said "all",
//   the lights in this Mac's room, if there are any
.globl _lights_room_filter
_lights_room_filter:
    ENTER 80                          // [96..159] keep flags  [160] kept
    ADRL x8, _g_cmd_n
    ldr  x19, [x8]
    cbz  x19, Llr_done
    cmp  x19, #64
    b.hi Llr_done
    str  xzr, [sp, #160]
    mov  x20, #0
Llr_named:
    cmp  x20, x19
    b.hs Llr_named_end
    add  x9, sp, #96
    strb wzr, [x9, x20]
    ADRL x8, _g_cmd_targets
    ldrb w0, [x8, x20]
    bl   _room_of
    ldrb w9, [x0]
    cbz  w9, Llr_named_next
    mov  x1, x0
    ADRL x0, _g_lroom
    mov  x2, #32
    bl   _lower_copy
    ADRL x0, _g_cmdbuf
    ADRL x1, _g_lroom
    bl   _has_word
    cbz  w0, Llr_named_next
    add  x9, sp, #96
    mov  w10, #1
    strb w10, [x9, x20]
    ldr  x9, [sp, #160]
    add  x9, x9, #1
    str  x9, [sp, #160]
Llr_named_next:
    add  x20, x20, #1
    b    Llr_named
Llr_named_end:
    ldr  x9, [sp, #160]
    cbnz x9, Llr_compact
    ADRL x8, _g_all_word
    ldr  x9, [x8]
    cbnz x9, Llr_done
    ADRL x8, _g_my_room
    ldrb w9, [x8]
    cbz  w9, Llr_done
    mov  x20, #0
Llr_mine:
    cmp  x20, x19
    b.hs Llr_mine_end
    add  x9, sp, #96
    strb wzr, [x9, x20]
    ADRL x8, _g_cmd_targets
    ldrb w0, [x8, x20]
    bl   _room_of
    ADRL x1, _g_my_room
    bl   _strcasecmp
    cbnz w0, Llr_mine_next
    add  x9, sp, #96
    mov  w10, #1
    strb w10, [x9, x20]
    ldr  x9, [sp, #160]
    add  x9, x9, #1
    str  x9, [sp, #160]
Llr_mine_next:
    add  x20, x20, #1
    b    Llr_mine
Llr_mine_end:
    ldr  x9, [sp, #160]
    cbz  x9, Llr_done
Llr_compact:
    ADRL x8, _g_cmd_targets
    add  x10, sp, #96
    mov  x11, #0                      // read
    mov  x12, #0                      // write
Llr_c_loop:
    cmp  x11, x19
    b.hs Llr_c_end
    ldrb w13, [x10, x11]
    cbz  w13, Llr_c_next
    ldrb w14, [x8, x11]
    strb w14, [x8, x12]
    add  x12, x12, #1
Llr_c_next:
    add  x11, x11, #1
    b    Llr_c_loop
Llr_c_end:
    ADRL x8, _g_cmd_n
    str  x12, [x8]
Llr_done:
    LEAVE 80

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_empty:        .asciz ""
Ls_q:            .asciz "?"
Ls_release:      .asciz "release"
Ls_pref_room:    .asciz "my_room"
Lf_paren:        .asciz " (%s)"
Lf_in_room:      .asciz " in the %s"
Lf_two:          .asciz "%s%s"
Lf_this_mac:     .asciz "this Mac%s"
Lf_dm_dec:       .asciz "\342\211\2100.%ld m"
Lf_dm:           .asciz "\342\211\210%ld m"
Lf_room_set:     .asciz "\302\267 \360\237\223\215 This Mac is in the %s. \342\200\234lights on\342\200\235 typed here now means the %s lights (\342\200\234all lights on\342\200\235 still means the whole home), and when you ask where something is, other Macs hear which room this one is in."
Ls_room_ask:     .asciz "\302\267 Which room? e.g. \342\200\234this Mac is in the office\342\200\235."
Lf_room_is:      .asciz "\302\267 \360\237\223\215 This Mac is in the %s. Say \342\200\234this Mac is in \342\200\246\342\200\235 to change it."
Ls_room_unknown: .asciz "\302\267 I don't know which room this Mac is in yet. Tell me: \342\200\234this Mac is in the office\342\200\235."
Ls_find_usage:   .asciz "\302\267 Where is what? e.g. \342\200\234where are my headphones\342\200\235."
Lf_find_near:    .asciz "\302\267 \360\237\223\215 %s: %s from this Mac%s \302\267 heard %ld s ago."
Lf_find_remote:  .asciz "\302\267 \360\237\223\241 %s%s hears %s %s away \302\267 %ld s ago."
Lf_closest:      .asciz "\302\267 Closest: %s."
Lf_find_dev:     .asciz "\302\267 \360\237\217\240 %s \342\200\224 %s%s."
Lf_find_bt:      .asciz "\302\267 \360\237\216\247 %s: paired with this Mac, %s."
Ls_bt_conn:      .asciz "connected right now"
Ls_bt_notconn:   .asciz "not connected"
Lf_find_none:    .asciz "\302\267 I can't hear anything called \342\200\234%s\342\200\235 right now. iPhones, Apple Watches and AirTags don't say their names over Bluetooth \342\200\224 use Find My for those. Headphones, speakers and gadgets that do say it show up here, and so does what other Macs running asmmesh hear."
Lf_tracker_alert: .asciz "\302\267 \342\232\240\357\270\217 An item tracker (%s) has been near this Mac for %ld minutes, %s. If it isn't yours or someone's you're with, check your bag, coat and car \342\200\224 on an iPhone, Find My \342\200\272 Items \342\200\272 Identify Found Item helps. Say \342\200\234trust trackers\342\200\235 if it's yours."
Ls_tracker_main: .asciz "\302\267 \342\232\240\357\270\217 Tracker alert \342\200\224 see the Home room."
Ls_tracker_push: .asciz "An item tracker that isn't marked as yours has been near your Mac for 10+ minutes."
Lf_tracker_line: .asciz "\302\267 \360\237\217\267 %s \342\200\224 %s \302\267 around for %ld min%s"
Ls_yours:        .asciz " \302\267 yours"
Ls_no_trackers:  .asciz "\302\267 No item trackers (AirTag, SmartTag, Tile) heard right now."
Ls_tracker_foot: .asciz "\302\267 A tracker that isn't yours and stays near this Mac for 10+ minutes gets a warning here (and on your phone if ntfy or Pushover is on). Say \342\200\234trust trackers\342\200\235 for the ones you own."
Lf_trusted:      .asciz "\302\267 Marked %ld tracker(s) heard right now as yours."
