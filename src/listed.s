// listed.s — rooms anyone nearby can ask to join. The person who made a room can list it;
// while it is listed, every HELLO is followed by a ROOMAD with its name, signed, so only its
// owner can list it. Someone who isn't in the room sees it ("Rooms you can ask to join" on
// iPhone, Mesh › Ask to Join a Room… on the Mac) and sends a JOINREQ to the owner, who is
// asked Let In / Not Now; Let In sends the usual invite, sealed for them with the room's key.
// An invite into a room we asked for, from its owner, is taken without asking again.
//
//   ROOMAD   +12 room id  +20 owner id  +28 n  +29 owner's nick, then name length and name
//   JOINREQ  +12 room id  +20 asker id  +28 n  +29 asker's nick, then the owner's id (8)

.include "macros.inc"

.set AD_MAX,        16
.set AD_SHIFT,      7        // 128-byte entries
.set AD_ID,         0
.set AD_OWNER,      8
.set AD_SEEN,       16
.set AD_ASKED,      24       // when we asked to be let in (0: not asked)
.set AD_NICK,       32       // the owner's name, 32 bytes
.set AD_NAME,       64       // the room's name, 32 bytes
.set AD_FRESH,      120      // seconds a listing is offered without being heard again
.set ASK_FOR,       900      // an invite this soon after asking is taken without a question

.data
.p2align 3
.globl _g_listed_n
_g_listed_n:     .quad 0     // rooms this Mac lists (ids in _g_listed)
.globl _g_ad_count
_g_ad_count:     .quad 0     // listings heard (entries used in _g_ads)
.globl _g_joinreqs_for_me
_g_joinreqs_for_me: .quad 0  // asks to join one of our rooms (self-tests count them)
_g_jr_who:       .quad 0     // the last ask passed on: the same again within 30 s is a resend
_g_jr_room:      .quad 0
_g_jr_time:      .quad 0
.zerofill __DATA,__bss,_g_listed,128,4
.zerofill __DATA,__bss,_g_ads,2048,4

.text
.p2align 2

// ---------------------------------------------------------------------------
// Our rooms: which are listed
// ---------------------------------------------------------------------------

// long _listed_find(uint64 room id) -> index in _g_listed or -1
_listed_find:
    ADRL x8, _g_listed_n
    ldr  x10, [x8]
    ADRL x8, _g_listed
    mov  x9, #0
1:  cmp  x9, x10
    b.hs 2f
    ldr  x11, [x8, x9, lsl #3]
    cmp  x11, x0
    b.eq 3f
    add  x9, x9, #1
    b    1b
2:  mov  x0, #-1
    ret
3:  mov  x0, x9
    ret

// long _room_owned(long idx) -> 1 if this Mac made the room (never Main or a local room)
.globl _room_owned
_room_owned:
    cbz  x0, 9f
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs 9f
    ADRL x8, _g_rooms
    add  x8, x8, x0, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    sub  x9, x9, #1
    cmp  x9, #(LOCAL_ROOMS - 2)
    b.ls 9f
    ldr  x9, [x8, #R_OWNER]
    ADRL x10, _g_node_id
    ldr  x10, [x10]
    cmp  x9, x10
    cset x0, eq
    ret
9:  mov  x0, #0
    ret

// long _room_listed(long idx) -> 1 if it is listed
.globl _room_listed
_room_listed:
    ENTER 0
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs 9f
    ADRL x8, _g_rooms
    add  x8, x8, x0, lsl #ROOM_SHIFT
    ldr  x0, [x8, #R_ID]
    bl   _listed_find
    cmp  x0, #0
    cset x0, ge
    LEAVE 0
9:  mov  x0, #0
    LEAVE 0

// long _room_set_listed(long idx, long on) -> 1 done, 0 not ours (or no room for it)
.globl _room_set_listed
_room_set_listed:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _room_owned
    cbz  x0, Lsl_no
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x21, [x8, #R_ID]
    mov  x0, x21
    bl   _listed_find
    mov  x22, x0
    cbz  x20, Lsl_off
    tbz  x22, #63, Lsl_save           // listed already
    ADRL x8, _g_listed_n
    ldr  x9, [x8]
    cmp  x9, #ROOM_MAX
    b.hs Lsl_no
    ADRL x10, _g_listed
    str  x21, [x10, x9, lsl #3]
    add  x9, x9, #1
    str  x9, [x8]
    b    Lsl_save
Lsl_off:
    tbnz x22, #63, Lsl_save
    ADRL x8, _g_listed_n              // the last one takes its place
    ldr  x9, [x8]
    sub  x9, x9, #1
    str  x9, [x8]
    ADRL x10, _g_listed
    ldr  x11, [x10, x9, lsl #3]
    str  x11, [x10, x22, lsl #3]
Lsl_save:
    bl   _listed_save
    cbz  x20, 1f
    bl   _rooms_advertise             // out now, not at the next hello
1:  mov  x0, #1
    LEAVE 0
Lsl_no:
    mov  x0, #0
    LEAVE 0

// void _listed_save(void)
_listed_save:
    ENTER 0
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, 1f
    CLS  Ls_NSData
    ADRL x2, _g_listed
    ADRL x8, _g_listed_n
    ldr  x3, [x8]
    lsl  x3, x3, #3
    MSG2 Ls_dataWithBytes
    mov  x19, x0
    bl   _defaults
    mov  x20, x0
    ADRL x0, Ls_key_listed
    bl   _nsstr
    mov  x3, x0
    mov  x2, x19
    mov  x0, x20
    MSG2 Ls_setObjectForKey
1:  LEAVE 0

// void _listed_init(void) — the rooms listed last time (after _rooms_init)
.globl _listed_init
_listed_init:
    ENTER 0
    ADRL x8, _g_listed_n
    str  xzr, [x8]
    ADRL x8, _g_ad_count
    str  xzr, [x8]
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, 9f
    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_key_listed
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_dataForKey
    cbz  x0, 9f
    mov  x19, x0
    MSG0 Ls_length
    lsr  x20, x0, #3
    cmp  x20, #ROOM_MAX
    mov  x9, #ROOM_MAX
    csel x20, x9, x20, hi
    mov  x0, x19
    MSG0 Ls_bytes
    mov  x1, x0
    ADRL x0, _g_listed
    lsl  x2, x20, #3
    bl   _memcpy
    ADRL x8, _g_listed_n
    str  x20, [x8]
9:  LEAVE 0

// void _rooms_advertise(void) — a ROOMAD for each room we list (after every HELLO)
.globl _rooms_advertise
_rooms_advertise:
    ENTER 0
    ADRL x8, _g_id_ready              // nothing goes out unsigned
    ldr  x9, [x8]
    cbz  x9, Lra_done
    mov  x19, #0
Lra_loop:
    ADRL x8, _g_listed_n
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lra_done
    ADRL x8, _g_listed
    ldr  x0, [x8, x19, lsl #3]
    add  x19, x19, #1
    bl   _room_find
    tbnz x0, #63, Lra_loop            // left or deleted since
    mov  x20, x0
    bl   _room_owned
    cbz  x0, Lra_loop
    ADRL x0, _g_pkt
    mov  w1, #T_ROOMAD
    bl   _pkt_begin
    ADRL x21, _g_pkt
    ADRL x8, _g_rooms
    add  x22, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, [x22, #R_ID]
    str  x9, [x21, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x21, #20]
    add  x0, x21, #28
    bl   _put_nick
    mov  x23, x0
    add  x0, x22, #R_NAME
    bl   _strlen
    mov  x24, x0
    strb w24, [x23]
    add  x0, x23, #1
    add  x1, x22, #R_NAME
    mov  x2, x24
    bl   _memcpy
    add  x1, x23, #1
    add  x1, x1, x24
    sub  x1, x1, x21                  // packet length
    mov  x0, x21
    bl   _pkt_finish
    cbz  x0, Lra_loop
    mov  x1, x0
    mov  x0, x21
    bl   _ble_broadcast
    b    Lra_loop
Lra_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// Other people's listed rooms
// ---------------------------------------------------------------------------

// void *_ad_find(uint64 room id) -> entry or 0
_ad_find:
    ADRL x8, _g_ad_count
    ldr  x10, [x8]
    ADRL x8, _g_ads
    mov  x9, #0
1:  cmp  x9, x10
    b.hs 2f
    ldr  x11, [x8, #AD_ID]
    cmp  x11, x0
    b.eq 3f
    add  x8, x8, #(1 << AD_SHIFT)
    add  x9, x9, #1
    b    1b
2:  mov  x0, #0
    ret
3:  mov  x0, x8
    ret

// void *_ad_slot(void) — a free entry, or the one heard from least lately
_ad_slot:
    ADRL x8, _g_ad_count
    ldr  x9, [x8]
    ADRL x10, _g_ads
    cmp  x9, #AD_MAX
    b.hs 1f
    add  x11, x9, #1
    str  x11, [x8]
    add  x0, x10, x9, lsl #AD_SHIFT
    ret
1:  mov  x0, x10
    ldr  x12, [x0, #AD_SEEN]
    mov  x11, #1
2:  cmp  x11, #AD_MAX
    b.hs 4f
    add  x13, x10, x11, lsl #AD_SHIFT
    ldr  x14, [x13, #AD_SEEN]
    cmp  x14, x12
    b.hs 3f
    mov  x0, x13
    mov  x12, x14
3:  add  x11, x11, #1
    b    2b
4:  ret

// void _roomad_rx(const uint8 *pkt, size_t body_len, long nick_len) — a ROOMAD arrived
//   (signed by its sender; nick already in _g_nickbuf). Passed on by the caller either way.
.globl _roomad_rx
_roomad_rx:
    ENTER 48                          // [96] the room's name
    mov  x19, x0
    add  x9, x2, #29                  // the name's length byte
    cmp  x9, x1
    b.hs Lar_done
    ldrb w20, [x19, x9]
    cbz  w20, Lar_done
    cmp  w20, #ROOMNAME_MAX
    b.hi Lar_done
    add  x10, x9, #1
    add  x10, x10, x20
    cmp  x10, x1
    b.hi Lar_done
    add  x1, x19, x9
    add  x1, x1, #1
    add  x0, sp, #96
    mov  x2, x20
    bl   _memcpy
    add  x8, sp, #96
    strb wzr, [x8, x20]
    add  x0, sp, #96
    bl   _sanitize
    ldr  x9, [x19, #20]               // our own, come back round
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.eq Lar_done
    ldr  x0, [x19, #12]
    cbz  x0, Lar_done                 // Main and the local rooms aren't listed
    sub  x9, x0, #1
    cmp  x9, #(LOCAL_ROOMS - 2)
    b.ls Lar_done
    bl   _ad_find
    mov  x21, x0
    mov  x22, #0                      // changed: the list needs redrawing
    mov  x23, #0                      // new: say so in Main
    cbnz x21, Lar_have
    bl   _ad_slot
    mov  x21, x0
    mov  x1, #(1 << AD_SHIFT)
    bl   _bzero
    ldr  x9, [x19, #12]
    str  x9, [x21, #AD_ID]
    ldr  x9, [x19, #20]
    str  x9, [x21, #AD_OWNER]
    mov  x22, #1
    mov  x23, #1
    b    Lar_fill
Lar_have:                             // only its first lister's word counts: someone else
    ldr  x9, [x21, #AD_OWNER]         //   reusing the id is ignored
    ldr  x10, [x19, #20]
    cmp  x9, x10
    b.ne Lar_done
    mov  x0, #0                       // gone quiet and back: offered again
    bl   _time
    ldr  x9, [x21, #AD_SEEN]
    sub  x9, x0, x9
    cmp  x9, #AD_FRESH
    cset x22, hi
    add  x0, x21, #AD_NAME            // renamed
    add  x1, sp, #96
    bl   _strcmp
    cmp  w0, #0
    csinc x22, x22, xzr, eq
Lar_fill:
    mov  x0, #0
    bl   _time
    str  x0, [x21, #AD_SEEN]
    add  x0, x21, #AD_NICK
    ADRL x1, _g_nickbuf
    mov  x2, #32
    bl   _strlcpy
    add  x0, x21, #AD_NAME
    add  x1, sp, #96
    mov  x2, #32
    bl   _strlcpy
    ldr  x0, [x19, #12]               // a room we're in already: nothing to offer
    bl   _room_find
    tbz  x0, #63, Lar_done
    cbz  x23, Lar_redraw
    ADRL x0, Lf_listed
    ADRL x1, _g_nickbuf
    add  x2, sp, #96
    bl   _chat_fmt
Lar_redraw:
    cbz  x22, Lar_done
    ADRL x8, _g_window
    ldr  x8, [x8]
    cbz  x8, Lar_done
    bl   _ui_rooms_changed
Lar_done:
    LEAVE 48

// void *_ad_nth(long k) -> the k-th listing on offer (heard lately, not a room we're in), or 0
.globl _ad_nth
_ad_nth:
    ENTER 0
    mov  x19, x0
    mov  x0, #0
    bl   _time
    mov  x20, x0
    mov  x21, #0
Lan_loop:
    ADRL x8, _g_ad_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lan_none
    ADRL x8, _g_ads
    add  x22, x8, x21, lsl #AD_SHIFT
    add  x21, x21, #1
    ldr  x9, [x22, #AD_SEEN]
    sub  x9, x20, x9
    cmp  x9, #AD_FRESH
    b.hi Lan_loop
    ldr  x0, [x22, #AD_ID]
    cbz  x0, Lan_loop
    bl   _room_find
    tbz  x0, #63, Lan_loop
    cbz  x19, Lan_hit
    sub  x19, x19, #1
    b    Lan_loop
Lan_hit:
    mov  x0, x22
    LEAVE 0
Lan_none:
    mov  x0, #0
    LEAVE 0

// long _ad_count(void) — listings on offer
.globl _ad_count
_ad_count:
    ENTER 0
    mov  x19, #0
1:  mov  x0, x19
    bl   _ad_nth
    cbz  x0, 2f
    add  x19, x19, #1
    b    1b
2:  mov  x0, x19
    LEAVE 0

// const char *_ad_field(void *entry, long f) — 0 room name, 1 owner's name
.globl _ad_field
_ad_field:
    cbz  x0, 1f
    cmp  x1, #1
    add  x9, x0, #AD_NAME
    add  x10, x0, #AD_NICK
    csel x0, x10, x9, eq
    ret
1:  ADRL x0, Ls_empty_l
    ret

// long _ad_asked(void *entry) -> 1 if we asked to be let in lately
.globl _ad_asked
_ad_asked:
    ENTER 0
    cbz  x0, 9f
    ldr  x19, [x0, #AD_ASKED]
    cbz  x19, 9f
    mov  x0, #0
    bl   _time
    sub  x9, x0, x19
    cmp  x9, #ASK_FOR
    cset x0, ls
    LEAVE 0
9:  mov  x0, #0
    LEAVE 0

// long _join_ask(void *entry) -> peers written, -1 not sent (no identity yet)
.globl _join_ask
_join_ask:
    ENTER 0
    mov  x19, x0
    cbz  x19, Lja_fail
    ADRL x8, _g_id_ready
    ldr  x9, [x8]
    cbz  x9, Lja_fail
    ADRL x0, _g_pkt
    mov  w1, #T_JOINREQ
    bl   _pkt_begin
    ADRL x21, _g_pkt
    ldr  x9, [x19, #AD_ID]
    str  x9, [x21, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x21, #20]
    add  x0, x21, #28
    bl   _put_nick
    ldr  x9, [x19, #AD_OWNER]         // whose answer it needs
    str  x9, [x0]
    add  x1, x0, #8
    sub  x1, x1, x21
    mov  x0, x21
    bl   _pkt_finish
    cbz  x0, Lja_fail
    mov  x22, x0
    mov  x0, x21                      // kept, so an owner who's away gets it later too
    mov  x1, x22
    bl   _store_put
    mov  x0, x21
    mov  x1, x22
    bl   _ble_broadcast
    mov  x22, x0
    mov  x0, #0
    bl   _time
    str  x0, [x19, #AD_ASKED]
    ADRL x0, Lf_asked
    add  x1, x19, #AD_NICK
    add  x2, x19, #AD_NAME
    bl   _chat_fmt
    ADRL x8, _g_window
    ldr  x8, [x8]
    cbz  x8, 1f
    bl   _ui_rooms_changed
1:  mov  x0, x22
    LEAVE 0
Lja_fail:
    mov  x0, #-1
    LEAVE 0

// long _join_asked(uint64 room id, uint64 from) -> 1 if we asked its owner, `from`, lately:
//   their invite is the answer, so it is taken without asking again
.globl _join_asked
_join_asked:
    ENTER 0
    mov  x19, x1
    cbz  x19, 9f
    bl   _ad_find
    cbz  x0, 9f
    ldr  x9, [x0, #AD_OWNER]
    cmp  x9, x19
    b.ne 9f
    bl   _ad_asked
    LEAVE 0
9:  mov  x0, #0
    LEAVE 0

// long _joinreq_rx(const uint8 *pkt, size_t body_len, long nick_len) -> 1 if it was for us
//   (or malformed): not passed on. Nick already in _g_nickbuf.
.globl _joinreq_rx
_joinreq_rx:
    ENTER 0
    mov  x19, x0
    add  x9, x2, #29                  // the owner's id
    add  x10, x9, #8
    cmp  x10, x1
    b.hi Ljr_mine
    ldr  x9, [x19, x9]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.ne Ljr_pass                     // someone else's room: pass it on
    ldr  x0, [x19, #12]
    bl   _room_find
    tbnz x0, #63, Ljr_mine            // deleted since
    mov  x20, x0
    bl   _room_owned
    cbz  x0, Ljr_mine
    mov  x0, x20
    bl   _room_listed
    cbz  x0, Ljr_mine                 // not listed any more: they need an invite
    ldr  x21, [x19, #20]              // who
    ldr  x22, [x19, #12]              // which room
    mov  x0, #0
    bl   _time
    mov  x23, x0
    ADRL x8, _g_jr_who                // the same ask again within 30 s: once is enough
    ldr  x9, [x8]
    cmp  x9, x21
    b.ne 1f
    ADRL x8, _g_jr_room
    ldr  x9, [x8]
    cmp  x9, x22
    b.ne 1f
    ADRL x8, _g_jr_time
    ldr  x9, [x8]
    sub  x9, x23, x9
    cmp  x9, #30
    b.lo Ljr_mine
1:  ADRL x8, _g_jr_who
    str  x21, [x8]
    ADRL x8, _g_jr_room
    str  x22, [x8]
    ADRL x8, _g_jr_time
    str  x23, [x8]
    ADRL x8, _g_joinreqs_for_me
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    mov  x0, x22
    mov  x1, x21
    ADRL x2, _g_nickbuf
    bl   _joinreq_in                  // the platform asks: Let In / Not Now
Ljr_mine:
    mov  x0, #1
    LEAVE 0
Ljr_pass:
    mov  x0, #0
    LEAVE 0

// long _joinreq_let_in(uint64 room id, uint64 who) -> 0 invited, -1 no key from them yet,
//   -2 the room is gone
.globl _joinreq_let_in
_joinreq_let_in:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _room_find
    tbnz x0, #63, Lli_gone
    mov  x21, x0
    mov  x0, x20
    bl   _node_find
    tbnz x0, #63, Lli_nokey
    mov  x22, x0
    mov  x1, x21
    bl   _mesh_send_invite
    tbnz x0, #63, Lli_nokey
    ADRL x8, _g_nodes
    add  x0, x8, x22, lsl #NODE_SHIFT
    bl   _node_name
    mov  x3, x0
    mov  x0, x21
    mov  x1, #1
    ADRL x2, Lf_letting_in
    bl   _room_fmt
    mov  x0, #0
    LEAVE 0
Lli_nokey:
    mov  x0, #-1
    LEAVE 0
Lli_gone:
    mov  x0, #-2
    LEAVE 0

.section __TEXT,__cstring,cstring_literals
Lf_listed:      .asciz "\302\267 \360\237\232\252 %s listed the room \342\200\234%s\342\200\235: you can ask to join it."
Lf_asked:       .asciz "\302\267 \360\237\232\252 Asked %s to let you into \342\200\234%s\342\200\235. You\342\200\231ll join as soon as they say yes."
Lf_letting_in:  .asciz "\302\267 \360\237\232\252 Let %s in: they join as soon as their device hears the invite."
Ls_key_listed:  .asciz "listedRooms"
Ls_empty_l:     .asciz ""
Ls_NSData:      .asciz "NSData"
Ls_dataWithBytes: .asciz "dataWithBytes:length:"
Ls_setObjectForKey: .asciz "setObject:forKey:"
Ls_dataForKey:  .asciz "dataForKey:"
Ls_length:      .asciz "length"
Ls_bytes:       .asciz "bytes"
