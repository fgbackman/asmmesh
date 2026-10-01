// mesh.s — the mesh: identity, packets, duplicate filter, store-and-forward,
// the table of nodes we have heard from, and the table of rooms we belong to.
//
// Packet header (every type, protocol v3):
//   +0 'M'   +1 version 3   +2 ttl (hops left)   +3 type   +4 id[8] (random, never 0)
//
//   MSG     +12 room[8] +20 sender[8] +28 flags +29 nlen +30 nick, then the text
//           (sealed with the room's key in private rooms, with the mesh passphrase
//           in Main when one is set)
//   HELLO   +12 node[8] +20 relayed(u32) +24 nlen +25 nick, then the public key[65]
//   INVITE  +12 room[8] +20 from[8] +28 target[8] +36 nlen +37 nick, then sealed
//           for the target alone: rlen, room name, the room's key[64]
//   CMD     +12 target[8] +20 sender[8] +28 nlen +29 nick, then a mode byte
//           (0 plain, 1 mesh passphrase, 2 sealed for the target alone) and text
//
// Every packet ends with the ident.s trailer: time[4] + signature[64]. A node's id
// is the hash of its public key, so every packet proves who sent it.
//
// Room 0 is Main (id 0): everyone sees it. Every other room is invite-only: its
// messages still hop through every Mac, but only members' windows show them.
// HELLOs go out every 15 s and flood like everything else, so each Mac learns
// every node on the mesh and how many hops away it is. HELLOs are not kept in
// the store; messages and invites are, so late joiners still receive them.
//
// With a mesh passphrase (crypto.s), room messages, remote commands and SEEN
// packets are sealed: AES-256-CTR plus an HMAC-SHA256 tag. HELLOs stay readable.
//
//   SEEN    +12 sender[8] +20 flags +21 nlen +22 nick, then what it hears (find.s)

.include "macros.inc"

.set SEEN_N,     1024
.set STORE_N,    32
.set SLOT_SHIFT, 8           // 256-byte slots: [0] length, [8] packet
.set ROOMSAVE,   40          // persisted room record: id[8] + name[32]

// ---------------------------------------------------------------------------
.data
.p2align 3
.globl _g_node_id
_g_node_id:       .quad 0
.globl _g_nick_len
_g_nick_len:      .quad 0
.globl _g_relayed
_g_relayed:       .quad 0
_g_seen_pos:      .quad 0
.globl _g_store_pos
_g_store_pos:     .quad 0
.globl _g_node_count
_g_node_count:    .quad 0
.globl _g_room_count
_g_room_count:    .quad 0
.globl _g_cur_room
_g_cur_room:      .quad 0
.globl _g_no_persist
_g_no_persist:    .quad 0
.globl _g_invites_for_me
_g_invites_for_me: .quad 0
_g_warned_ver:    .quad 0
_g_warned_clash:  .quad 0

.globl _g_nick
.zerofill __DATA,__bss,_g_nick,32,4
.globl _g_hostnick
.zerofill __DATA,__bss,_g_hostnick,32,4
.zerofill __DATA,__bss,_g_seen,8192,4
.globl _g_rx_pended
.zerofill __DATA,__bss,_g_inv_owner,8,3
.zerofill __DATA,__bss,_g_ownsave,256,4
.zerofill __DATA,__bss,_g_rx_pended,8,3
.globl _g_store
.zerofill __DATA,__bss,_g_store,8192,4
.zerofill __DATA,__bss,_g_pkt,256,4
.zerofill __DATA,__bss,_g_fwd,256,4
.globl _g_txt
.zerofill __DATA,__bss,_g_txt,256,4
.globl _g_nickbuf
.zerofill __DATA,__bss,_g_nickbuf,32,4
.zerofill __DATA,__bss,_g_roombuf,32,4
.globl _g_nodes
.zerofill __DATA,__bss,_g_nodes,2048,4
.globl _g_rooms
.zerofill __DATA,__bss,_g_rooms,1024,4
.zerofill __DATA,__bss,_g_roomsave,640,4
.zerofill __DATA,__bss,_g_pairkey,64,4
.zerofill __DATA,__bss,_g_invbuf,256,4
.zerofill __DATA,__bss,_g_fpbuf,48,4
.globl _g_last_refused
_g_last_refused:  .quad 0

// ---------------------------------------------------------------------------
.text
.p2align 2

// uint64 _new_id(void) — random, never zero
.globl _new_id
_new_id:
    ENTER 16
    add  x0, sp, #96
    mov  x1, #8
    bl   _arc4random_buf
    ldr  x0, [sp, #96]
    orr  x0, x0, #1
    LEAVE 16

// id _defaults(void)
_defaults:
    ENTER 0
    CLS  Ls_NSUserDefaults
    MSG0 Ls_standardUserDefaults
    LEAVE 0

// ---------------------------------------------------------------------------
// void _mesh_init(void)
//   Host name -> _g_hostnick. Node id and nickname come from NSUserDefaults
//   (created on first run); with _g_no_persist set (selftest) they are fresh.
// ---------------------------------------------------------------------------
.globl _mesh_init
_mesh_init:
    ENTER 0
    ADRL x0, _g_hostnick
    mov  x1, #31
    bl   _gethostname
    ADRL x8, _g_hostnick
    strb wzr, [x8, #31]
    mov  x9, #0
Lmi_loop:
    ldrb w10, [x8, x9]
    cbz  w10, Lmi_end
    cmp  w10, #'.'
    b.eq Lmi_end
    cmp  x9, #NICK_MAX
    b.hs Lmi_end
    add  x9, x9, #1
    b    Lmi_loop
Lmi_end:
    strb wzr, [x8, x9]
    cbnz x9, Lmi_host_ok
    ADRL x0, _g_hostnick
    ADRL x1, Ls_anon
    bl   _strcpy
Lmi_host_ok:
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, Lmi_fresh

    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_key_node
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_integerForKey
    cbnz x0, Lmi_have_id
    bl   _new_id
    mov  x20, x0
    ADRL x0, Ls_key_node
    bl   _nsstr
    mov  x3, x0
    mov  x0, x19
    mov  x2, x20
    MSG2 Ls_setIntegerForKey
    mov  x0, x20
Lmi_have_id:
    ADRL x8, _g_node_id
    str  x0, [x8]
    ADRL x0, Ls_key_nick
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_stringForKey
    cbz  x0, Lmi_hostnick
    MSG0 Ls_UTF8String
    cbz  x0, Lmi_hostnick
    bl   _nick_store
    cbnz x0, Lmi_done
Lmi_hostnick:
    ADRL x0, _g_hostnick
    bl   _nick_store
Lmi_done:
    LEAVE 0
Lmi_fresh:
    bl   _new_id
    ADRL x8, _g_node_id
    str  x0, [x8]
    ADRL x0, _g_hostnick
    bl   _nick_store
    LEAVE 0

// ---------------------------------------------------------------------------
// size_t _nick_store(const char *s) — trim, cap at NICK_MAX on a UTF-8
// boundary, neutralise control characters, store in _g_nick. 0 if empty.
// ---------------------------------------------------------------------------
_nick_store:
    ENTER 0
    mov  x19, x0
Lns_skip:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.ne Lns_len
    add  x19, x19, #1
    b    Lns_skip
Lns_len:
    mov  x0, x19
    bl   _strlen
    mov  x20, x0
    cmp  x20, #NICK_MAX
    b.ls Lns_trim
    mov  x20, #NICK_MAX
Lns_back:
    cbz  x20, Lns_trim
    ldrb w9, [x19, x20]
    and  w9, w9, #0xC0
    cmp  w9, #0x80
    b.ne Lns_trim
    sub  x20, x20, #1
    b    Lns_back
Lns_trim:
    cbz  x20, Lns_empty
    sub  x9, x20, #1
    ldrb w10, [x19, x9]
    cmp  w10, #' '
    b.ne Lns_copy
    mov  x20, x9
    b    Lns_trim
Lns_copy:
    ADRL x0, _g_nick
    mov  x1, x19
    mov  x2, x20
    bl   _memmove
    ADRL x8, _g_nick
    strb wzr, [x8, x20]
    ADRL x0, _g_nick
    bl   _sanitize
    ADRL x8, _g_nick_len
    str  x20, [x8]
    mov  x0, x20
    LEAVE 0
Lns_empty:
    mov  x0, #0
    LEAVE 0

// size_t _mesh_set_nick(const char *s) — change our name and remember it
.globl _mesh_set_nick
_mesh_set_nick:
    ENTER 0
    bl   _nick_store
    mov  x19, x0
    cbz  x19, Lsn_done
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, Lsn_done
    bl   _defaults
    mov  x20, x0
    ADRL x0, _g_nick
    bl   _nsstr
    mov  x21, x0
    ADRL x0, Ls_key_nick
    bl   _nsstr
    mov  x3, x0
    mov  x2, x21
    mov  x0, x20
    MSG2 Ls_setObjectForKey
Lsn_done:
    mov  x0, x19
    LEAVE 0

// ---------------------------------------------------------------------------
// Duplicate filter and store
// ---------------------------------------------------------------------------

// int _seen_check_add(uint64 id) -> 1 if already seen, else records it, 0
.globl _seen_check_add
_seen_check_add:
    ADRL x8, _g_seen
    mov  x9, #0
Lsc_loop:
    cmp  x9, #SEEN_N
    b.hs Lsc_new
    ldr  x10, [x8, x9, lsl #3]
    cmp  x10, x0
    b.eq Lsc_dup
    add  x9, x9, #1
    b    Lsc_loop
Lsc_new:
    ADRL x11, _g_seen_pos
    ldr  x12, [x11]
    and  x13, x12, #(SEEN_N - 1)
    str  x0, [x8, x13, lsl #3]
    add  x12, x12, #1
    str  x12, [x11]
    mov  w0, #0
    ret
Lsc_dup:
    mov  w0, #1
    ret

// void _store_put(const void *pkt, size_t len)
_store_put:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_store_pos
    ldr  x9, [x8]
    add  x10, x9, #1
    str  x10, [x8]
    and  x9, x9, #(STORE_N - 1)
    ADRL x21, _g_store
    add  x21, x21, x9, lsl #SLOT_SHIFT
    str  x20, [x21]
    add  x0, x21, #8
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    LEAVE 0

// void _mesh_flush_to(long peer) — hand a newly linked Mac everything we carry
.globl _mesh_flush_to
_mesh_flush_to:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_store_pos
    ldr  x20, [x8]
    mov  x21, #0
Lmf_loop:
    cmp  x21, #STORE_N
    b.hs Lmf_done
    add  x9, x20, x21
    and  x9, x9, #(STORE_N - 1)
    ADRL x22, _g_store
    add  x22, x22, x9, lsl #SLOT_SHIFT
    ldr  x2, [x22]
    cbz  x2, Lmf_next
    mov  x0, x19
    add  x1, x22, #8
    bl   _ble_write_peer
Lmf_next:
    add  x21, x21, #1
    b    Lmf_loop
Lmf_done:
    LEAVE 0

// void _sanitize(char *s) — control characters become spaces
.globl _sanitize
_sanitize:
    ldrb w9, [x0]
    cbz  w9, Lsz_done
    cmp  w9, #0x20
    b.hs Lsz_next
    mov  w9, #' '
    strb w9, [x0]
Lsz_next:
    add  x0, x0, #1
    b    _sanitize
Lsz_done:
    ret

// ---------------------------------------------------------------------------
// Building packets
// ---------------------------------------------------------------------------

// void *_pkt_begin(void *buf, int type) — header with a fresh id (marked seen)
.globl _pkt_begin
_pkt_begin:
    ENTER 0
    mov  x19, x0
    mov  w20, w1
    mov  w9, #'M'
    strb w9, [x19]
    mov  w9, #PROTO_VER
    strb w9, [x19, #1]
    mov  w9, #TTL0
    strb w9, [x19, #2]
    strb w20, [x19, #3]
    bl   _new_id
    str  x0, [x19, #4]
    bl   _seen_check_add
    mov  x0, x19
    LEAVE 0

// void *_put_nick(void *dst) — [len][our nick]; returns the byte after it
.globl _put_nick
_put_nick:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_nick_len
    ldr  x20, [x8]
    strb w20, [x19]
    add  x0, x19, #1
    ADRL x1, _g_nick
    mov  x2, x20
    bl   _memcpy
    add  x0, x19, #1
    add  x0, x0, x20
    LEAVE 0

// long _mesh_send_msg(long room, const char *text, int flags) -> peers written
//   The text actually sent (trimmed to fit) is left in _g_txt for the caller.
.globl _mesh_send_msg
_mesh_send_msg:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  w21, w2
    ADRL x8, _g_id_ready              // nothing goes out unsigned
    ldr  x9, [x8]
    cbnz x9, Lsm_go
    ADRL x0, Ls_no_id
    bl   _chat_line
    mov  x0, #0
    LEAVE 0
Lsm_go:
    ADRL x0, _g_pkt
    mov  w1, #T_MSG
    bl   _pkt_begin
    ADRL x22, _g_pkt
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    str  x9, [x22, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x22, #20]
    strb w21, [x22, #28]
    add  x0, x22, #29
    bl   _put_nick
    mov  x23, x0                      // text goes here
    sub  x9, x23, x22
    mov  x10, #(PKT_MAX - TRAILER)
    sub  x24, x10, x9                 // room left for text
    cbnz x19, Lsm_tagroom             // a private room: always sealed
    ADRL x8, _g_crypto_on             // encrypted: leave room for the tag
    ldr  x9, [x8]
    cbz  x9, Lsm_room
Lsm_tagroom:
    sub  x24, x24, #8
Lsm_room:
    mov  x0, x20
    bl   _strlen
    cmp  x0, x24
    csel x24, x0, x24, lo
Lsm_back:                             // never cut a UTF-8 character in half
    cbz  x24, Lsm_fit
    ldrb w9, [x20, x24]
    and  w9, w9, #0xC0
    cmp  w9, #0x80
    b.ne Lsm_fit
    sub  x24, x24, #1
    b    Lsm_back
Lsm_fit:
    mov  x0, x23
    mov  x1, x20
    mov  x2, x24
    bl   _memcpy
    ADRL x0, _g_txt
    mov  x1, x20
    mov  x2, x24
    bl   _memmove
    ADRL x8, _g_txt
    strb wzr, [x8, x24]
    cbnz x19, Lsm_rkey
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, Lsm_plain
    mov  x0, x23                      // seal it: id, room and sender are bound in
    mov  x1, x24
    add  x2, x22, #4
    bl   _crypto_seal
    mov  x24, x0
    ldrb w9, [x22, #28]
    orr  w9, w9, #MSGF_ENC
    strb w9, [x22, #28]
    b    Lsm_plain
Lsm_rkey:                             // a private room: only its members hold this key
    mov  x0, x19
    bl   _room_key
    cbnz x0, Lsm_rk_have
    mov  x0, x19
    bl   _room_key_new
    mov  x0, x19
    bl   _room_key
Lsm_rk_have:
    mov  x1, x23
    mov  x2, x24
    add  x3, x22, #4
    bl   _seal_key
    mov  x24, x0
    ldrb w9, [x22, #28]
    orr  w9, w9, #MSGF_RKEY
    strb w9, [x22, #28]
Lsm_plain:
    add  x23, x23, x24
    sub  x23, x23, x22                // packet length
    mov  x0, x22                      // time and signature
    mov  x1, x23
    bl   _pkt_finish
    cbz  x0, Lsm_fail
    mov  x23, x0
    mov  x0, x22
    mov  x1, x23
    bl   _store_put
    mov  x0, x22
    mov  x1, x23
    bl   _ble_broadcast
    LEAVE 0
Lsm_fail:
    mov  x0, #0
    LEAVE 0

// void _mesh_send_text(const char *text) — typed message into the current room
.globl _mesh_send_text
_mesh_send_text:
    ENTER 0
    mov  x20, x0
    ADRL x8, _g_cur_room
    ldr  x19, [x8]
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    cmp  x9, #WEB_ID
    b.eq Lst_web
    cmp  x9, #NEWS_ID
    b.eq Lst_news
    cmp  x9, #HOME_ID
    b.ne Lst_mesh
    mov  x0, x20                      // Home: a device command, stays on this Mac
    mov  w1, #0
    bl   _home_command
    LEAVE 0
Lst_web:
    mov  x0, x20                      // Web: an address or search, for a gateway Mac
    bl   _web_command
    LEAVE 0
Lst_news:
    mov  x0, x20
    bl   _news_command
    LEAVE 0
Lst_mesh:
    mov  x0, x20                      // a device command typed here? run it in Home
    bl   _chat_route
    cbz  x0, Lst_chat
    LEAVE 0
Lst_chat:
    mov  x0, x19
    mov  x1, x20
    mov  w2, #0
    bl   _mesh_send_msg
    mov  x3, x0
    ADRL x8, _g_id_ready              // not sent at all (no key yet): already said why
    ldr  x9, [x8]
    cbnz x9, Lst_said
    LEAVE 0
Lst_said:
    mov  x0, x19
    mov  x1, #0
    ADRL x2, Ls_fmt_me_sent
    ADRL x8, Ls_fmt_me_held
    cmp  x3, #0
    csel x2, x8, x2, eq
    mov  x4, x3
    ADRL x3, _g_txt
    bl   _room_fmt
    bl   _ui_update_status
    LEAVE 0

// long _mesh_send_hello(void)
.globl _mesh_send_hello
_mesh_send_hello:
    ENTER 0
    ADRL x0, _g_pkt
    mov  w1, #T_HELLO
    bl   _pkt_begin
    ADRL x19, _g_pkt
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x19, #12]
    ADRL x8, _g_relayed
    ldr  x9, [x8]
    str  w9, [x19, #20]
    add  x0, x19, #24
    bl   _put_nick
    mov  x20, x0
    ADRL x8, _g_id_ready              // no key yet: stay quiet until there is one
    ldr  x9, [x8]
    cbz  x9, Lsh_none
    mov  x0, x20                      // our public key, so everyone can check us
    ADRL x1, _g_my_pub
    mov  x2, #PUBLEN
    bl   _memcpy
    add  x20, x20, #PUBLEN
    mov  x0, x19
    sub  x1, x20, x19
    bl   _pkt_finish
    cbz  x0, Lsh_none
    mov  x1, x0
    mov  x0, x19
    bl   _ble_broadcast
    LEAVE 0
Lsh_none:
    mov  x0, #0
    LEAVE 0

// long _mesh_send_invite(long node, long room) -> peers written
.globl _mesh_send_invite
_mesh_send_invite:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_nodes                 // the secret only they and we can compute
    add  x8, x8, x19, lsl #NODE_SHIFT
    ldr  x0, [x8, #N_ID]
    ADRL x1, _g_pairkey
    bl   _pair_key
    cbz  x0, Lsi2_nokey
    ADRL x0, _g_pkt
    mov  w1, #T_INVITE
    bl   _pkt_begin
    ADRL x21, _g_pkt
    ADRL x8, _g_rooms
    add  x23, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, [x23, #R_ID]
    str  x9, [x21, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x21, #20]
    ADRL x8, _g_nodes
    add  x8, x8, x19, lsl #NODE_SHIFT
    ldr  x9, [x8, #N_ID]
    str  x9, [x21, #28]
    add  x0, x21, #36
    bl   _put_nick
    mov  x22, x0                      // the sealed part starts here
    add  x23, x23, #R_NAME
    mov  x0, x23
    bl   _strlen
    mov  x24, x0
    strb w24, [x22]
    add  x0, x22, #1
    mov  x1, x23
    mov  x2, x24
    bl   _memcpy
    mov  x0, x20                      // the room's key rides along
    bl   _room_key
    cbnz x0, Lsi2_key
    mov  x0, x20
    bl   _room_key_new
    mov  x0, x20
    bl   _room_key
Lsi2_key:
    mov  x1, x0
    add  x0, x22, #1
    add  x0, x0, x24
    mov  x2, #64
    bl   _memcpy
    ADRL x8, _g_rooms                 // who made the room (an older room, not known:
    add  x8, x8, x20, lsl #ROOM_SHIFT //   whoever invites from it becomes its owner)
    ldr  x9, [x8, #R_OWNER]
    cbnz x9, 1f
    ADRL x10, _g_node_id
    ldr  x9, [x10]
    str  x9, [x8, #R_OWNER]
    stp  x9, x9, [sp, #-16]!
    bl   _rooms_save
    ldp  x9, x10, [sp], #16
1:  add  x10, x22, x24
    str  x9, [x10, #65]
    ADRL x0, _g_pairkey
    mov  x1, x22
    add  x2, x24, #73
    add  x3, x21, #4
    bl   _seal_key
    add  x22, x22, x0
    sub  x22, x22, x21                // packet length
    mov  x0, x21
    mov  x1, x22
    bl   _pkt_finish
    cbz  x0, Lsi2_nokey
    mov  x22, x0
    mov  x0, x21
    mov  x1, x22
    bl   _store_put
    mov  x0, x21
    mov  x1, x22
    bl   _ble_broadcast
    LEAVE 0
Lsi2_nokey:                           // we haven't had their hello yet
    mov  x0, #-1
    LEAVE 0

// long _mesh_send_roomdel(long room) -> peers written, -1 not sent (no identity yet)
.globl _mesh_send_roomdel
_mesh_send_roomdel:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_id_ready
    ldr  x9, [x8]
    cbz  x9, Lsd_fail
    ADRL x0, _g_pkt
    mov  w1, #T_ROOMDEL
    bl   _pkt_begin
    ADRL x21, _g_pkt
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    str  x9, [x21, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x21, #20]
    add  x0, x21, #28
    bl   _put_nick
    sub  x1, x0, x21
    mov  x0, x21
    bl   _pkt_finish
    cbz  x0, Lsd_fail
    mov  x22, x0
    mov  x0, x21                      // kept, so a Mac that's away gets it later too
    mov  x1, x22
    bl   _store_put
    mov  x0, x21
    mov  x1, x22
    bl   _ble_broadcast
    LEAVE 0
Lsd_fail:
    mov  x0, #-1
    LEAVE 0

// long _mesh_send_cmd(int type, uint64 target, const char *text) -> peers written
.globl _mesh_send_cmd
_mesh_send_cmd:
    ENTER 0
    mov  w19, w0
    mov  x20, x1
    mov  x21, x2
    ADRL x0, _g_pkt
    mov  w1, w19
    bl   _pkt_begin
    ADRL x22, _g_pkt
    str  x20, [x22, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x22, #20]
    add  x0, x22, #28
    bl   _put_nick
    mov  x23, x0
    ADRL x8, _g_id_ready
    ldr  x9, [x8]
    cbz  x9, Lsc_fail
    mov  x0, x20                      // mode: 2 sealed for them alone, 1 mesh passphrase, 0 plain
    ADRL x1, _g_pairkey
    bl   _pair_key
    mov  w9, #2
    cbnz x0, Lsc_mode
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
Lsc_mode:
    strb w9, [x23]
    add  x23, x23, #1
    sub  x9, x23, x22
    mov  x10, #(PKT_MAX - TRAILER)
    sub  x24, x10, x9
    ldrb w9, [x23, #-1]
    cbz  w9, Lsc_len
    sub  x24, x24, #8
Lsc_len:
    mov  x0, x21
    bl   _strlen
    cmp  x0, x24
    csel x24, x0, x24, lo
Lsc_back:
    cbz  x24, Lsc_fit
    ldrb w9, [x21, x24]
    and  w9, w9, #0xC0
    cmp  w9, #0x80
    b.ne Lsc_fit
    sub  x24, x24, #1
    b    Lsc_back
Lsc_fit:
    mov  x0, x23
    mov  x1, x21
    mov  x2, x24
    bl   _memcpy
    ldrb w9, [x23, #-1]
    cbz  w9, Lsc_plain
    cmp  w9, #2
    b.eq Lsc_pair
    mov  x0, x23
    mov  x1, x24
    add  x2, x22, #4
    bl   _crypto_seal
    mov  x24, x0
    b    Lsc_plain
Lsc_pair:
    ADRL x0, _g_pairkey
    mov  x1, x23
    mov  x2, x24
    add  x3, x22, #4
    bl   _seal_key
    mov  x24, x0
Lsc_plain:
    add  x1, x23, x24
    sub  x1, x1, x22
    mov  x0, x22
    bl   _pkt_finish
    cbz  x0, Lsc_fail
    mov  x1, x0
    mov  x0, x22
    bl   _ble_broadcast
    LEAVE 0
Lsc_fail:
    mov  x0, #0
    LEAVE 0

// ---------------------------------------------------------------------------
// int _mesh_receive(const void *pkt, size_t len) -> RX_BAD / RX_NEW / RX_DUP
// ---------------------------------------------------------------------------
.globl _mesh_receive
_mesh_receive:
    ENTER 32
    // locals: [96] hops  [104] nick length  [112] type  [120] whole length
    mov  x19, x0
    mov  x20, x1
    str  x20, [sp, #120]
    cmp  x20, #(HDR + 13 + TRAILER)   // smallest valid packet is an empty-nick HELLO
    b.lo Lrx_bad
    cmp  x20, #PKT_MAX
    b.hi Lrx_bad
    ldrb w8, [x19]
    cmp  w8, #'M'
    b.ne Lrx_bad
    ldrb w8, [x19, #1]
    cmp  w8, #PROTO_VER
    b.ne Lrx_oldver
    ldrb w21, [x19, #2]               // ttl
    cbz  w21, Lrx_bad
    cmp  w21, #TTL0
    b.hi Lrx_bad
    ldrb w22, [x19, #3]               // type
    str  x22, [sp, #112]
    ldr  x8, [x19, #4]
    cbz  x8, Lrx_bad
    mov  x9, #(TTL0 + 1)
    sub  x9, x9, x21
    str  x9, [sp, #96]                // hops travelled
    sub  x20, x20, #TRAILER           // from here on: the body, without time and signature

    // ---- validate the body before trusting any length in it ----
    cmp  w22, #T_MSG
    b.eq Lrx_vmsg
    cmp  w22, #T_HELLO
    b.eq Lrx_vhello
    cmp  w22, #T_INVITE
    b.eq Lrx_vinvite
    cmp  w22, #T_CMD
    b.eq Lrx_vcmd
    cmp  w22, #T_CMDRES
    b.eq Lrx_vcmd
    cmp  w22, #T_SEEN
    b.eq Lrx_vseen
    cmp  w22, #T_NEWS                 // news and web pages: same layout checks as CMD
    b.eq Lrx_vcmd
    cmp  w22, #T_WEBREQ
    b.eq Lrx_vcmd
    cmp  w22, #T_WEBPART
    b.eq Lrx_vcmd
    cmp  w22, #T_ROOMDEL
    b.eq Lrx_vcmd
    b    Lrx_bad
Lrx_vseen:
    cmp  x20, #22
    b.lo Lrx_bad
    ldrb w23, [x19, #21]
    cmp  x23, #NICK_MAX
    b.hi Lrx_bad
    add  x8, x23, #22
    cmp  x8, x20
    b.hi Lrx_bad
    b    Lrx_dedupe
Lrx_vcmd:
    cmp  x20, #29
    b.lo Lrx_bad
    ldrb w23, [x19, #28]
    cmp  x23, #NICK_MAX
    b.hi Lrx_bad
    add  x8, x23, #29
    cmp  x8, x20
    b.hi Lrx_bad
    b    Lrx_dedupe
Lrx_vmsg:
    cmp  x20, #30
    b.lo Lrx_bad
    ldrb w23, [x19, #29]
    cmp  x23, #NICK_MAX
    b.hi Lrx_bad
    add  x8, x23, #30
    cmp  x8, x20
    b.hi Lrx_bad
    b    Lrx_dedupe
Lrx_vhello:
    ldrb w23, [x19, #24]
    cmp  x23, #NICK_MAX
    b.hi Lrx_bad
    add  x8, x23, #(25 + PUBLEN)      // name, then exactly the public key
    cmp  x8, x20
    b.ne Lrx_bad
    b    Lrx_dedupe
Lrx_vinvite:
    cmp  x20, #38
    b.lo Lrx_bad
    ldrb w23, [x19, #36]
    cmp  x23, #NICK_MAX
    b.hi Lrx_bad
    add  x8, x23, #(37 + 2 + 64 + 8)  // nick, then at least a sealed 1-letter name and key
    cmp  x8, x20
    b.hi Lrx_bad
Lrx_dedupe:
    str  x23, [sp, #104]
    ADRL x8, _g_rx_replay             // re-reading a held packet: already counted
    ldr  x9, [x8]
    cbnz x9, Lrx_auth
    ldr  x0, [x19, #4]
    bl   _seen_check_add
    cbnz w0, Lrx_dup

    // ---- who sent it? the signature must match their key ----
Lrx_auth:
    ldr  x22, [sp, #112]
    cmp  w22, #T_HELLO
    b.eq Lrx_auth_hello
    mov  x0, x19
    bl   _pkt_sender
    mov  x2, x0
    mov  x0, x19
    ldr  x1, [sp, #120]
    bl   _sender_check
    cmp  x0, #1
    b.eq Lrx_ok
    cmp  x0, #3
    b.ne Lrx_forged
    ADRL x8, _g_rx_replay             // their hello hasn't come yet: hold it, pass it on
    ldr  x9, [x8]
    cbnz x9, Lrx_forged
    mov  x0, x19
    ldr  x1, [sp, #120]
    bl   _pending_put
    ADRL x8, _g_rx_pended             // (FM tells you why nothing showed yet)
    mov  x9, #1
    str  x9, [x8]
    b    Lrx_relay
Lrx_auth_hello:
    mov  x0, x19
    ldr  x1, [sp, #120]
    ldr  x2, [x19, #12]
    bl   _hello_check
    cmp  x0, #1
    b.ne Lrx_forged
Lrx_ok:

    ldr  x22, [sp, #112]
    cmp  w22, #T_MSG
    b.eq Lrx_msg
    cmp  w22, #T_HELLO
    b.eq Lrx_hello
    cmp  w22, #T_INVITE
    b.eq Lrx_invite
    cmp  w22, #T_SEEN
    b.eq Lrx_seen
    cmp  w22, #T_ROOMDEL
    b.eq Lrx_roomdel
    cmp  w22, #T_NEWS
    b.hs Lrx_web

    // ---- CMD / CMDRES: a device command for someone, or its answer ----
    ldr  x9, [x19, #12]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne Lrx_relay                    // not ours: pass it on
    add  x0, x19, #29
    ldr  x1, [sp, #104]
    bl   _copy_nick
    ldr  x0, [x19, #20]
    ADRL x1, _g_nickbuf
    ldr  x2, [sp, #96]
    bl   _node_touch_announce
    ldr  x9, [sp, #104]
    add  x23, x9, #29
    sub  x24, x20, x23
    cbz  x24, Lrx_bad2
    ldrb w9, [x19, x23]               // mode byte
    add  x23, x23, #1
    sub  x24, x24, #1
    cbz  w9, Lrx_cmd_plain
    cmp  w9, #2
    b.eq Lrx_cmd_pair
    cmp  w9, #1                       // sealed with the mesh passphrase
    b.ne Lrx_bad2
    add  x0, x19, x23
    mov  x1, x24
    add  x2, x19, #4
    ADRL x3, _g_txt
    bl   _crypto_open
    tbz  x0, #63, Lrx_cmd_open
    b    Lrx_cmd_locked
Lrx_cmd_pair:                         // sealed for us alone
    ldr  x0, [x19, #20]
    ADRL x1, _g_pairkey
    bl   _pair_key
    cbz  x0, Lrx_cmd_locked
    ADRL x0, _g_pairkey
    add  x1, x19, x23
    mov  x2, x24
    add  x3, x19, #4
    ADRL x4, _g_txt
    bl   _open_key
    tbz  x0, #63, Lrx_cmd_open
Lrx_cmd_locked:
    ADRL x1, _g_nickbuf               // not for our passphrase: drop it, say so
    ADRL x0, Ls_fmt_cmd_locked
    bl   _chat_fmt
    b    Lrx_new
Lrx_cmd_plain:
    ADRL x8, _g_crypto_on             // with a passphrase set, plain commands are refused
    ldr  x9, [x8]
    cbz  x9, Lrx_cmd_copy
    ldr  x22, [sp, #112]
    cmp  w22, #T_CMD
    b.ne Lrx_cmd_copy
    ADRL x1, _g_nickbuf
    ADRL x0, Ls_fmt_cmd_plain
    bl   _chat_fmt
    b    Lrx_new
Lrx_cmd_copy:
    cmp  x24, #240
    b.hs Lrx_bad2
    ADRL x0, _g_txt
    add  x1, x19, x23
    mov  x2, x24
    bl   _memcpy
    ADRL x8, _g_txt
    strb wzr, [x8, x24]
Lrx_cmd_open:
    ADRL x0, _g_txt
    bl   _sanitize
    ldr  x22, [sp, #112]
    cmp  w22, #T_CMD
    b.ne Lrx_cmdres
    ldr  x0, [x19, #20]
    ADRL x1, _g_nickbuf
    ADRL x2, _g_txt
    bl   _cmd_incoming
    b    Lrx_new
Lrx_cmdres:
    ADRL x0, _g_nickbuf
    ADRL x1, _g_txt
    bl   _cmd_result_in
    b    Lrx_new

    // ---- MSG ----
Lrx_msg:
    add  x0, x19, #30
    ldr  x1, [sp, #104]
    bl   _copy_nick                   // -> _g_nickbuf
    ldr  x0, [x19, #20]
    ADRL x1, _g_nickbuf
    ldr  x2, [sp, #96]
    bl   _node_touch_announce
    ldr  x9, [sp, #104]
    add  x23, x9, #30                 // text offset
    sub  x24, x20, x23
    ldrb w9, [x19, #28]
    tbnz w9, #2, Lrx_msg_rkey         // MSGF_RKEY: the room's own key
    tbz  w9, #1, Lrx_msg_plain        // MSGF_ENC
    add  x0, x19, x23
    mov  x1, x24
    add  x2, x19, #4
    ADRL x3, _g_txt
    bl   _crypto_open
    tbz  x0, #63, Lrx_msg_text
    ADRL x1, Ls_locked_other          // -1: another passphrase; -2: we have none
    cmn  x0, #1
    b.eq Lrx_msg_locked
    ADRL x1, Ls_locked_none
Lrx_msg_locked:
    ADRL x0, _g_txt
    mov  x2, #240
    bl   _strlcpy
    b    Lrx_msg_text
Lrx_msg_rkey:
    ldr  x0, [x19, #12]
    bl   _room_find
    tbnz x0, #63, Lrx_relay           // not a room we are in: just pass it on
    bl   _room_key
    cbz  x0, Lrx_relay
    add  x1, x19, x23
    mov  x2, x24
    add  x3, x19, #4
    ADRL x4, _g_txt
    bl   _open_key
    tbz  x0, #63, Lrx_msg_text
    ADRL x0, _g_txt
    ADRL x1, Ls_locked_room
    mov  x2, #240
    bl   _strlcpy
    b    Lrx_msg_text
Lrx_msg_plain:                        // unencrypted: only fine in Main with no passphrase
    ldr  x9, [x19, #12]
    cbnz x9, Lrx_msg_refuse
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbnz x9, Lrx_msg_refuse
    cmp  x24, #240
    b.hs Lrx_bad2
    ADRL x0, _g_txt
    add  x1, x19, x23
    mov  x2, x24
    bl   _memcpy
    ADRL x8, _g_txt
    strb wzr, [x8, x24]
Lrx_msg_text:
    ADRL x0, _g_txt
    bl   _sanitize
    ldr  x0, [x19, #12]
    sub  x9, x0, #1                   // nobody else's words land in a local room
    cmp  x9, #(LOCAL_ROOMS - 2)       //   (Home, Web, News)
    b.ls Lrx_relay
    bl   _room_find
    tbnz x0, #63, Lrx_relay           // not a room we are in: just pass it on
    ldrb w9, [x19, #28]
    tbnz w9, #0, Lrx_notice
    mov  x1, #0
    ADRL x2, Ls_fmt_rx
    ADRL x3, _g_nickbuf
    ADRL x4, _g_txt
    ldr  x5, [sp, #96]
    bl   _room_fmt
    b    Lrx_relay
Lrx_notice:
    mov  x1, #1
    ADRL x2, Ls_fmt_notice
    ADRL x3, _g_nickbuf
    ADRL x4, _g_txt
    bl   _room_fmt
    b    Lrx_relay

Lrx_msg_refuse:                       // say so once per sender, then stay quiet
    ldr  x0, [x19, #12]
    bl   _room_find
    tbnz x0, #63, Lrx_relay
    ldr  x9, [x19, #20]
    ADRL x8, _g_last_refused
    ldr  x10, [x8]
    cmp  x9, x10
    b.eq Lrx_relay
    str  x9, [x8]
    ADRL x1, _g_nickbuf
    ADRL x0, Ls_fmt_plain_refused
    bl   _chat_fmt
    b    Lrx_relay

    // ---- HELLO ----
Lrx_hello:
    ldr  x9, [x19, #12]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.eq Lrx_relay                    // our own, echoed back under a new path
    add  x0, x19, #25
    ldr  x1, [sp, #104]
    bl   _copy_nick
    ldr  x0, [x19, #12]
    ADRL x1, _g_nickbuf
    ldr  x2, [sp, #96]
    bl   _node_touch_announce
    tbnz x0, #63, Lrx_relay
    ADRL x8, _g_nodes
    add  x8, x8, x0, lsl #NODE_SHIFT
    ldr  w9, [x19, #20]
    str  x9, [x8, #N_RELAYED]
    ldr  x0, [x19, #12]
    bl   _name_clash
    bl   _ui_lists_changed
    ldr  x0, [x19, #12]               // anything it sent before we knew its key
    bl   _pending_replay
    b    Lrx_relay

    // ---- INVITE ----
Lrx_invite:
    ldr  x9, [x19, #28]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne Lrx_relay                    // someone else's invite: pass it on
    ldr  x0, [x19, #12]
    sub  x9, x0, #1                   // an invite into a local room: ignore it
    cmp  x9, #(LOCAL_ROOMS - 2)
    b.ls Lrx_new
    add  x0, x19, #37
    ldr  x1, [sp, #104]
    bl   _copy_nick
    ldr  x0, [x19, #20]
    ADRL x1, _g_nickbuf
    ldr  x2, [sp, #96]
    bl   _node_touch_announce
    ldr  x0, [x19, #20]               // sealed for us: open it with our shared secret
    ADRL x1, _g_pairkey
    bl   _pair_key
    cbz  x0, Lrx_new
    ldr  x9, [sp, #104]
    add  x23, x9, #37
    ADRL x0, _g_pairkey
    add  x1, x19, x23
    sub  x2, x20, x23
    add  x3, x19, #4
    ADRL x4, _g_invbuf
    bl   _open_key
    tbnz x0, #63, Lrx_new
    ADRL x22, _g_invbuf
    ldrb w24, [x22]                   // room name length
    cbz  w24, Lrx_new
    cmp  w24, #ROOMNAME_MAX
    b.hi Lrx_new
    ADRL x8, _g_inv_owner             // [len][name][key64] or, newer, [..][owner id]
    str  xzr, [x8]
    add  x9, x24, #65
    cmp  x0, x9
    b.eq Linv_sized
    add  x9, x24, #73
    cmp  x0, x9
    b.ne Lrx_new
    add  x9, x22, x24
    ldr  x9, [x9, #65]
    ADRL x8, _g_inv_owner
    str  x9, [x8]
Linv_sized:
    ADRL x0, _g_roombuf
    add  x1, x22, #1
    mov  x2, x24
    bl   _memcpy
    ADRL x8, _g_roombuf
    strb wzr, [x8, x24]
    ADRL x0, _g_roombuf
    bl   _sanitize
    ldr  x0, [x19, #12]               // already in that room: only a new key is news
    bl   _room_find                   //   (the sender lost its old one, e.g. a reinstall);
    tbnz x0, #63, Linv_queue          //   then you're asked whether to use it
    bl   _room_key
    cbz  x0, Linv_queue
    add  x1, x22, #1
    add  x1, x1, x24
    mov  x2, #64
    bl   _memcmp
    cbz  w0, Lrx_new                  // the key we have: nothing new
Linv_queue:
    ADRL x8, _g_invites_for_me
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    ldr  x0, [x19, #12]
    ADRL x1, _g_roombuf
    ADRL x2, _g_nickbuf
    add  x3, x22, #1                  // the room's key
    add  x3, x3, x24
    ADRL x8, _g_inv_owner
    ldr  x4, [x8]
    bl   _invite_queue
    b    Lrx_new                      // addressed to us: nobody else needs it

    // ---- ROOMDEL: the room's owner deleted it; only its owner's (signed) word counts ----
Lrx_roomdel:
    ldr  x0, [x19, #12]
    bl   _room_find
    tbnz x0, #63, Lrx_relay           // not one of ours: pass it on
    cbz  x0, Lrx_relay                // never Main
    mov  x22, x0
    ADRL x8, _g_rooms
    add  x23, x8, x22, lsl #ROOM_SHIFT
    ldr  x9, [x23, #R_ID]
    sub  x10, x9, #1                  // nor a local room
    cmp  x10, #(LOCAL_ROOMS - 2)
    b.ls Lrx_relay
    ldr  x9, [x23, #R_OWNER]
    cbz  x9, Lrx_relay
    ldr  x10, [x19, #20]
    cmp  x9, x10
    b.ne Lrx_relay
    add  x0, x19, #29
    ldr  x1, [sp, #104]
    bl   _copy_nick
    mov  x0, x22
    bl   _room_deleted
    b    Lrx_relay

    // ---- SEEN: what another Mac hears (for "where is my …"); passed on, not kept ----
Lrx_seen:
    add  x0, x19, #22
    ldr  x1, [sp, #104]
    bl   _copy_nick
    ldr  x0, [x19, #12]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x0, x8
    b.eq Lrx_new                      // our own, come back round
    ADRL x1, _g_nickbuf
    ldr  x2, [sp, #96]
    bl   _node_touch_announce
    mov  x0, x19
    mov  x1, x20
    bl   _seen_in
    b    Lrx_relay

    // ---- news and web pages (web.s), then pass them on like everything else ----
Lrx_web:
    mov  x0, x19
    mov  x1, x20                      // body length, without the trailer
    ldr  x2, [sp, #96]                // hops travelled
    bl   _web_rx
    cbnz x0, Lrx_new                  // meant for this Mac alone: not passed on
    b    Lrx_relay

    // ---- relay onwards with one hop fewer ----
Lrx_relay:
    ADRL x8, _g_rx_replay             // passed on when it first arrived
    ldr  x9, [x8]
    cbnz x9, Lrx_new
    ldr  x20, [sp, #120]              // the whole packet, trailer and all
    cmp  w21, #1
    b.ls Lrx_new
    ADRL x0, _g_fwd
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    ADRL x8, _g_fwd
    sub  w21, w21, #1
    strb w21, [x8, #2]
    ldr  x22, [sp, #112]
    cmp  w22, #T_HELLO
    b.eq Lrx_send                     // presence is not worth carrying for later
    cmp  w22, #T_CMD
    b.hs Lrx_send                     // nor are commands: stale ones must not replay
    ADRL x0, _g_fwd
    mov  x1, x20
    bl   _store_put
Lrx_send:
    ADRL x0, _g_fwd
    mov  x1, x20
    bl   _ble_broadcast
    cbz  x0, Lrx_new
    ADRL x8, _g_relayed
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    bl   _ui_update_status
Lrx_new:
    mov  x0, #RX_NEW
    LEAVE 32
Lrx_dup:
    mov  x0, #RX_DUP
    LEAVE 32
Lrx_bad2:                             // signed, but not something we understand
    b    Lrx_new
Lrx_forged:                           // a bad signature, or an old packet replayed
    mov  x0, #RX_BAD
    LEAVE 32
Lrx_oldver:                           // say so once; after that, stay quiet
    ADRL x8, _g_warned_ver
    ldr  x9, [x8]
    cbnz x9, Lrx_bad
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, Ls_msg_oldver
    bl   _chat_line
Lrx_bad:
    mov  x0, #RX_BAD
    LEAVE 32

// void _name_clash(uint64 id) — someone else already goes by this node's name? say so,
//   with both fingerprints, so people can check which one is real
_name_clash:
    ENTER 0
    mov  x19, x0
    bl   _node_find
    tbnz x0, #63, Lnc_done
    ADRL x8, _g_nodes
    add  x20, x8, x0, lsl #NODE_SHIFT
    ldrb w9, [x20, #N_NICK]
    cbz  w9, Lnc_done
    mov  x21, #0
Lnc_loop:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lnc_done
    ADRL x8, _g_nodes
    add  x22, x8, x21, lsl #NODE_SHIFT
    ldr  x9, [x22, #N_ID]
    cmp  x9, x19
    b.eq Lnc_next
    add  x0, x22, #N_NICK
    add  x1, x20, #N_NICK
    bl   _strcasecmp
    cbnz w0, Lnc_next
    ADRL x8, _g_warned_clash          // once per pair of ids
    ldr  x10, [x8]
    ldr  x9, [x22, #N_ID]
    eor  x9, x9, x19
    cmp  x9, x10
    b.eq Lnc_done
    str  x9, [x8]
    ldr  x0, [x22, #N_ID]
    ADRL x1, _g_fpbuf
    bl   _fp
    mov  x0, x19
    ADRL x1, _g_fpbuf
    add  x1, x1, #16
    bl   _fp
    add  x1, x20, #N_NICK
    ADRL x2, _g_fpbuf
    ADRL x3, _g_fpbuf
    add  x3, x3, #16
    str  x2, [sp, #8]
    str  x3, [sp, #16]
    str  x1, [sp]
    ADRL x0, _g_txt
    mov  x1, #240
    ADRL x2, Ls_fmt_clash
    bl   _snprintf
    ADRL x0, _g_txt
    bl   _chat_line
    b    Lnc_done
Lnc_next:
    add  x21, x21, #1
    b    Lnc_loop
Lnc_done:
    LEAVE 0

// void _copy_nick(const char *src, size_t n) -> NUL-terminated, sanitised _g_nickbuf
_copy_nick:
    ENTER 0
    mov  x19, x1
    mov  x1, x0
    ADRL x0, _g_nickbuf
    mov  x2, x19
    bl   _memcpy
    ADRL x8, _g_nickbuf
    strb wzr, [x8, x19]
    ADRL x0, _g_nickbuf
    bl   _sanitize
    LEAVE 0

// ---------------------------------------------------------------------------
// Node table
// ---------------------------------------------------------------------------

// long _node_find(uint64 id) -> index or -1
.globl _node_find
_node_find:
    ADRL x8, _g_node_count
    ldr  x10, [x8]
    ADRL x8, _g_nodes
    mov  x9, #0
Lnf_loop:
    cmp  x9, x10
    b.hs Lnf_none
    ldr  x11, [x8, #N_ID]
    cmp  x11, x0
    b.eq Lnf_found
    add  x8, x8, #64
    add  x9, x9, #1
    b    Lnf_loop
Lnf_none:
    mov  x0, #-1
    ret
Lnf_found:
    mov  x0, x9
    ret

// long _node_touch(uint64 id, const char *nick /*may be 0*/, long hops)
//   -> x0 index (or -1 if the table is full), x1 = 1 if it was new
.globl _node_touch
_node_touch:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, #0
    bl   _node_find
    tbz  x0, #63, Lnt_have
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x9, #NODE_MAX
    b.hs Lnt_full
    mov  x0, x9
    add  x9, x9, #1
    str  x9, [x8]
    mov  x22, #1
    ADRL x8, _g_nodes
    add  x8, x8, x0, lsl #NODE_SHIFT
    str  x19, [x8, #N_ID]
    str  xzr, [x8, #N_RSSI]
    str  xzr, [x8, #N_RELAYED]
    strb wzr, [x8, #N_NICK]
Lnt_have:
    mov  x23, x0
    ADRL x8, _g_nodes
    add  x24, x8, x23, lsl #NODE_SHIFT
    mov  x0, #0
    bl   _time
    str  x0, [x24, #N_SEEN]
    cbz  x21, Lnt_nick
    str  x21, [x24, #N_HOPS]
Lnt_nick:
    cbz  x20, Lnt_ret
    ldrb w9, [x20]
    cbz  w9, Lnt_ret
    add  x0, x24, #N_NICK
    mov  x1, x20
    mov  x2, #24
    bl   _strlcpy
Lnt_ret:
    mov  x0, x23
    mov  x1, x22
    LEAVE 16
Lnt_full:
    mov  x0, #-1
    mov  x1, #0
    LEAVE 16

// long _node_touch_announce(id, nick, hops) — _node_touch, and tell Main when
// someone new appears on the mesh
_node_touch_announce:
    ENTER 0
    mov  x21, x2
    bl   _node_touch
    mov  x19, x0
    cbz  x1, Lna_done
    tbnz x19, #63, Lna_done
    ADRL x8, _g_nodes
    add  x8, x8, x19, lsl #NODE_SHIFT
    add  x3, x8, #N_NICK
    mov  x0, #0
    mov  x1, #1
    ADRL x2, Ls_fmt_joined_far
    ADRL x8, Ls_fmt_joined_near
    cmp  x21, #1
    csel x2, x8, x2, ls
    mov  x4, x21
    bl   _room_fmt
    bl   _ui_lists_changed
Lna_done:
    mov  x0, x19
    LEAVE 0

// void _node_set_rssi(uint64 id, long rssi) — from a direct link's readRSSI
.globl _node_set_rssi
_node_set_rssi:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _node_find
    tbz  x0, #63, Lnr_have
    cbz  x20, Lnr_done                // clearing an unknown node: nothing to do
    mov  x0, x19
    mov  x1, #0
    mov  x2, #1
    bl   _node_touch
    tbnz x0, #63, Lnr_done
Lnr_have:
    ADRL x8, _g_nodes
    add  x8, x8, x0, lsl #NODE_SHIFT
    str  x20, [x8, #N_RSSI]
    cbz  x20, Lnr_done
    mov  x9, #1
    str  x9, [x8, #N_HOPS]
Lnr_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// Room table
// ---------------------------------------------------------------------------

// long _room_find(uint64 id) -> index or -1
.globl _room_find
_room_find:
    ADRL x8, _g_room_count
    ldr  x10, [x8]
    ADRL x8, _g_rooms
    mov  x9, #0
Lrf_loop:
    cmp  x9, x10
    b.hs Lrf_none
    ldr  x11, [x8, #R_ID]
    cmp  x11, x0
    b.eq Lrf_found
    add  x8, x8, #64
    add  x9, x9, #1
    b    Lrf_loop
Lrf_none:
    mov  x0, #-1
    ret
Lrf_found:
    mov  x0, x9
    ret

// long _room_add(uint64 id, const char *name, int save) -> index or -1 (full)
.globl _room_add
_room_add:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    bl   _room_find
    tbz  x0, #63, Lra_done
    ADRL x8, _g_room_count
    ldr  x22, [x8]
    cmp  x22, #ROOM_MAX
    b.hs Lra_full
    add  x9, x22, #1
    str  x9, [x8]
    ADRL x8, _g_rooms
    add  x23, x8, x22, lsl #ROOM_SHIFT
    str  x19, [x23, #R_ID]
    str  xzr, [x23, #R_UNREAD]
    str  xzr, [x23, #R_OWNER]
    add  x0, x23, #R_NAME
    mov  x1, x20
    mov  x2, #32
    bl   _strlcpy
    add  x0, x23, #R_NAME
    bl   _sanitize
    CLS  Ls_NSTextStorage
    MSG0 Ls_new
    str  x0, [x23, #R_STORE]
    mov  x0, x22                      // every room gets its own key
    bl   _room_key_new
    cbz  x21, Lra_ret
    bl   _rooms_save
    bl   _keys_save
Lra_ret:
    mov  x0, x22
Lra_done:
    LEAVE 0
Lra_full:
    mov  x0, #-1
    LEAVE 0

// void _room_remove(long idx) — forget a room (never Main)
.globl _room_remove
_room_remove:
    ENTER 0
    mov  x19, x0
    cbz  x19, Lrm_done
    ADRL x8, _g_room_count
    ldr  x20, [x8]
    cmp  x19, x20
    b.hs Lrm_done
    ADRL x8, _g_rooms
    add  x21, x8, x19, lsl #ROOM_SHIFT
    ldr  x0, [x21, #R_STORE]
    cbz  x0, Lrm_move
    MSG0 Ls_release
Lrm_move:
    mov  x0, x19
    mov  x1, x20
    bl   _room_keys_remove
    sub  x9, x20, x19
    sub  x9, x9, #1
    lsl  x2, x9, #ROOM_SHIFT
    mov  x0, x21
    add  x1, x21, #64
    bl   _memmove
    sub  x20, x20, #1
    ADRL x8, _g_room_count
    str  x20, [x8]
    ADRL x8, _g_rooms
    add  x0, x8, x20, lsl #ROOM_SHIFT
    mov  x1, #64
    bl   _bzero
    bl   _rooms_save
    bl   _keys_save
Lrm_done:
    LEAVE 0

// void _rooms_init(void) — Main, plus the rooms remembered from last time
.globl _rooms_init
_rooms_init:
    ENTER 48                          // [96] one record copied out of the NSData
    ADRL x8, _g_room_count
    str  xzr, [x8]
    mov  x0, #0
    ADRL x1, Ls_main
    mov  x2, #0
    bl   _room_add
    mov  x0, #HOME_ID                 // local only: device commands, never on the mesh
    ADRL x1, Ls_home
    mov  x2, #0
    bl   _room_add
    mov  x0, #WEB_ID                  // local: web pages fetched by a gateway Mac (web.s)
    ADRL x1, Ls_webroom
    mov  x2, #0
    bl   _room_add
    mov  x0, #NEWS_ID                 // local: headlines from gateway Macs
    ADRL x1, Ls_newsroom
    mov  x2, #0
    bl   _room_add
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, Lri_done
    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_key_rooms
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_dataForKey
    cbz  x0, Lri_done
    mov  x19, x0
    MSG0 Ls_length
    mov  x20, x0
    mov  x0, x19
    MSG0 Ls_bytes
    mov  x21, x0
    mov  x22, #0
Lri_loop:
    add  x9, x22, #ROOMSAVE
    cmp  x9, x20
    b.hi Lri_done
    add  x0, sp, #96
    add  x1, x21, x22
    mov  x2, #ROOMSAVE
    bl   _memcpy
    strb wzr, [sp, #(96 + 8 + 31)]    // never trust a stored string's terminator
    ldr  x0, [sp, #96]
    cbz  x0, Lri_next
    add  x1, sp, #104
    mov  x2, #0
    bl   _room_add
Lri_next:
    add  x22, x22, #ROOMSAVE
    b    Lri_loop
Lri_owners:                           // who made each room
    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_key_owners
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_dataForKey
    cbz  x0, Lri_end
    mov  x19, x0
    MSG0 Ls_length
    mov  x20, x0
    mov  x0, x19
    MSG0 Ls_bytes
    mov  x21, x0
    mov  x22, #0
Lri_o_loop:
    add  x9, x22, #16
    cmp  x9, x20
    b.hi Lri_end
    add  x9, x21, x22
    ldp  x0, x23, [x9]
    bl   _room_find
    tbnz x0, #63, Lri_o_next
    ADRL x8, _g_rooms
    add  x8, x8, x0, lsl #ROOM_SHIFT
    str  x23, [x8, #R_OWNER]
Lri_o_next:
    add  x22, x22, #16
    b    Lri_o_loop
Lri_done:
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbz  x8, Lri_owners
Lri_end:
    LEAVE 48

// void _rooms_save(void) — id + name of every room except Main
.globl _rooms_save
_rooms_save:
    ENTER 0
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, Lrs_done
    ADRL x8, _g_room_count
    ldr  x19, [x8]
    mov  x20, #1
    ADRL x21, _g_roomsave
Lrs_loop:
    cmp  x20, x19
    b.hs Lrs_write
    ADRL x8, _g_rooms
    add  x8, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    sub  x10, x9, #1                  // local rooms are made at launch, not saved
    cmp  x10, #(LOCAL_ROOMS - 2)
    b.hi Lrs_keep
    add  x20, x20, #1
    b    Lrs_loop
Lrs_keep:
    str  x9, [x21]
    add  x0, x21, #8
    add  x1, x8, #R_NAME
    mov  x2, #32
    bl   _memcpy
    add  x21, x21, #ROOMSAVE
    add  x20, x20, #1
    b    Lrs_loop
Lrs_write:
    ADRL x8, _g_roomsave
    sub  x21, x21, x8                 // bytes used
    CLS  Ls_NSData
    ADRL x2, _g_roomsave
    mov  x3, x21
    MSG2 Ls_dataWithBytes
    mov  x21, x0
    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_key_rooms
    bl   _nsstr
    mov  x3, x0
    mov  x2, x21
    mov  x0, x19
    MSG2 Ls_setObjectForKey
    ADRL x21, _g_ownsave              // and who made each room
    mov  x20, #1
Lro_loop:
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lro_write
    ADRL x8, _g_rooms
    add  x8, x8, x20, lsl #ROOM_SHIFT
    ldr  x10, [x8, #R_OWNER]
    cbz  x10, Lro_next
    ldr  x9, [x8, #R_ID]
    stp  x9, x10, [x21], #16
Lro_next:
    add  x20, x20, #1
    b    Lro_loop
Lro_write:
    ADRL x8, _g_ownsave
    sub  x21, x21, x8
    CLS  Ls_NSData
    ADRL x2, _g_ownsave
    mov  x3, x21
    MSG2 Ls_dataWithBytes
    mov  x21, x0
    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_key_owners
    bl   _nsstr
    mov  x3, x0
    mov  x2, x21
    mov  x0, x19
    MSG2 Ls_setObjectForKey
Lrs_done:
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_anon:              .asciz "anon"
Ls_main:              .asciz "Main"
Ls_home:              .asciz "Home"
Ls_webroom:           .asciz "Web"
Ls_newsroom:          .asciz "News"
Ls_key_node:          .asciz "nodeId"
Ls_key_nick:          .asciz "nick"
Ls_key_rooms:         .asciz "rooms"
Ls_key_owners:        .asciz "roomOwners"
Ls_NSUserDefaults:    .asciz "NSUserDefaults"
Ls_NSTextStorage:     .asciz "NSTextStorage"
Ls_NSData:            .asciz "NSData"
Ls_standardUserDefaults: .asciz "standardUserDefaults"
Ls_integerForKey:     .asciz "integerForKey:"
Ls_setIntegerForKey:  .asciz "setInteger:forKey:"
Ls_stringForKey:      .asciz "stringForKey:"
Ls_setObjectForKey:   .asciz "setObject:forKey:"
Ls_dataForKey:        .asciz "dataForKey:"
Ls_dataWithBytes:     .asciz "dataWithBytes:length:"
Ls_UTF8String:        .asciz "UTF8String"
Ls_length:            .asciz "length"
Ls_bytes:             .asciz "bytes"
Ls_new:               .asciz "new"
Ls_release:           .asciz "release"
Ls_fmt_me_sent:       .asciz "me: %s   \302\267 sent to %ld nearby"
Ls_fmt_me_held:       .asciz "me: %s   \302\267 nobody in range yet \342\200\224 holding it for the next Mac that appears"
Ls_fmt_rx:            .asciz "%s: %s   \302\267 hop %ld"
Ls_fmt_notice:        .asciz "\302\267 %s %s"
Ls_fmt_joined_near:   .asciz "\302\267 %s joined the mesh \342\200\224 in Bluetooth range"
Ls_fmt_joined_far:    .asciz "\302\267 %s joined the mesh \342\200\224 %ld hops away"
Ls_locked_none:        .asciz "\360\237\224\222 (encrypted \342\200\224 set the same mesh passphrase to read it)"
Ls_locked_other:       .asciz "\360\237\224\222 (encrypted with a different mesh passphrase)"
Ls_fmt_cmd_locked:     .asciz "\302\267 %s sent a device command sealed with a different mesh passphrase; it was ignored."
Ls_fmt_cmd_plain:      .asciz "\302\267 %s sent a device command without the mesh passphrase; it was refused."
Ls_no_id:             .asciz "\302\267 \360\237\224\221 Your identity key isn\342\200\231t unlocked yet, so nothing was sent. If macOS is asking about the Keychain, allow it, then try again."
Ls_locked_room:       .asciz "\360\237\224\222 (sealed with a room key you don\342\200\231t have \342\200\224 ask to be invited again)"
Ls_fmt_plain_refused: .asciz "\302\267 \360\237\224\222 Ignored an unencrypted message from %s: with a mesh passphrase set, only sealed messages are shown."
Ls_fmt_clash:         .asciz "\302\267 \342\232\240\357\270\217 Two people on the mesh are called \342\200\234%s\342\200\235 (%s and %s). Their keys differ, so check with them which one is really them."
Ls_msg_oldver:        .asciz "\302\267 a nearby Mac is running a different version of asmmesh \342\200\224 update asmmesh on it so you can talk."
