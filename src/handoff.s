// handoff.s — move your headphones between your Macs with one command.
//
//   headphones here  /  airpods here      the other Macs let go of them, this one connects
//   send my headphones to Mac             this Mac lets go, that Mac connects
//
// Which headphones: the paired Bluetooth audio device on this Mac (AirPods, Beats,
// anything that calls itself headphones or buds), the connected one first.
//
// Over the mesh goes a T_HP packet with what to do and a fingerprint of the
// headphones' Bluetooth address (SHA-256 of it, 16 bytes) — not the address itself.
// A Mac acts only if it is paired with headphones that match that fingerprint, which
// only a Mac paired with the same headphones can know; the worst a stranger could
// do is nothing. At most one request every 3 seconds is acted on.
//
// IOBluetooth is used off the main thread (its first call waits on the main thread).

.include "macros.inc"

.set HP_HERE,     1           // ops in a request (the packet carries RELEASE or GRAB)
.set HP_SEND,     2
.set HP_RELEASE,  10
.set HP_GRAB,     11
// messages from the workers to the main thread
.set HM_NONE,     1
.set HM_ALREADY,  2
.set HM_ASKING,   3
.set HM_OK,       4
.set HM_FAIL,     5
.set HM_SENT,     6
.set HM_LET_GO,   7
.set HM_GOT,      8
.set HM_GOT_FAIL, 9
// a request / message: 256 bytes
.set HC_OP,       0
.set HC_TARGET,   8           // node id (0: every Mac)
.set HC_CODE,     16          // message code, or an IOReturn
.set HC_ERR,      24
.set HC_NAME,     32          // 64: the headphones
.set HC_HASH,     96          // 16
.set HC_NICK,     112         // 32: the other Mac
.set HC_SIZE,     256

.data
.p2align 3
_g_hp_last:     .quad 0
.zerofill __DATA,__bss,_g_hp_pkt,256,4

.text
.p2align 2

// ===========================================================================
// Commands
// ===========================================================================

// "headphones here"
.globl _h_hp_here
_h_hp_here:
    ENTER 0
    mov  x0, #HP_HERE
    mov  x1, #0
    ADRL x2, Ls_empty
    bl   _hp_start
    LEAVE 0

// "send my headphones to <Mac>"
.globl _h_hp_send
_h_hp_send:
    ENTER 0
    mov  x19, x2                      // the name as typed
    mov  x0, x1
    bl   _hp_node
    tbnz x0, #63, Lhs_who
    ADRL x8, _g_nodes
    add  x20, x8, x0, lsl #NODE_SHIFT
    mov  x0, #HP_SEND
    ldr  x1, [x20, #N_ID]
    add  x2, x20, #N_NICK
    bl   _hp_start
    LEAVE 0
Lhs_who:
    ADRL x0, Lf_hp_who
    mov  x1, x19
    bl   _home_say
    LEAVE 0

// long _hp_node(const char *name) -> the Mac on the mesh with that name (or the only
//   other one, for "the other mac" / "my laptop"), -1
_hp_node:
    ENTER 0
    mov  x19, x0
    mov  x20, #-1                     // match
    mov  x21, #0
    mov  x23, #0                      // how many others
    mov  x24, #-1                     // the last other one
Lhn_loop:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lhn_done
    ADRL x8, _g_nodes
    add  x22, x8, x21, lsl #NODE_SHIFT
    ldr  x9, [x22, #N_ID]
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.eq Lhn_next
    ldrb w9, [x22, #N_NICK]
    cbz  w9, Lhn_next
    add  x23, x23, #1
    mov  x24, x21
    add  x0, x22, #N_NICK
    mov  x1, x19
    bl   _strcasecmp
    cbnz w0, Lhn_part
    mov  x20, x21
    b    Lhn_done
Lhn_part:
    tbz  x20, #63, Lhn_next
    add  x0, x22, #N_NICK
    mov  x1, x19
    bl   _strcasestr
    cbz  x0, Lhn_next
    mov  x20, x21
Lhn_next:
    add  x21, x21, #1
    b    Lhn_loop
Lhn_done:
    tbz  x20, #63, Lhn_ret
    cmp  x23, #1                      // nobody by that name, but only one other Mac
    b.ne Lhn_ret
    mov  x20, x24
Lhn_ret:
    mov  x0, x20
    LEAVE 0

// void _hp_start(long op, uint64 target, const char *target_nick)
_hp_start:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, #1
    mov  x1, #HC_SIZE
    bl   _calloc
    cbz  x0, Lst_done
    mov  x22, x0
    str  x19, [x22, #HC_OP]
    str  x20, [x22, #HC_TARGET]
    add  x0, x22, #HC_NICK
    mov  x1, x21
    mov  x2, #32
    bl   _strlcpy
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, x22
    ADRL x2, _hp_worker
    bl   _dispatch_async_f
Lst_done:
    LEAVE 0

// ===========================================================================
// Background: IOBluetooth
// ===========================================================================

// void _hp_hash(IOBluetoothDevice *d, uint8 out[16])
_hp_hash:
    ENTER 128
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    MSG0 Ls_addressString
    cbz  x0, Lhh_zero
    MSG0 Ls_UTF8String
    cbz  x0, Lhh_zero
    mov  x21, x0
    add  x0, sp, #96                  // "asmmesh-hp:" + the address, lowercase
    ADRL x1, Ls_hp_salt
    mov  x2, #64
    bl   _strlcpy
    add  x0, sp, #96
    mov  x1, x21
    mov  x2, #64
    bl   _strlcat
    add  x9, sp, #96
Lhh_lc:
    ldrb w10, [x9]
    cbz  w10, Lhh_sha
    sub  w11, w10, #'A'
    cmp  w11, #25
    b.hi Lhh_lc_next
    add  w10, w10, #32
    strb w10, [x9]
Lhh_lc_next:
    cmp  w10, #':'                    // 00:11:.. and 00-11-.. are the same address
    b.ne Lhh_lc_adv
    mov  w10, #'-'
    strb w10, [x9]
Lhh_lc_adv:
    add  x9, x9, #1
    b    Lhh_lc
Lhh_sha:
    add  x0, sp, #96
    bl   _strlen
    mov  x1, x0
    add  x0, sp, #96
    add  x2, sp, #160                 // 32 bytes of digest
    bl   _CC_SHA256
    mov  x0, x20
    add  x1, sp, #160
    mov  x2, #16
    bl   _memcpy
    LEAVE 128
Lhh_zero:
    stp  xzr, xzr, [x20]
    LEAVE 128

// id _hp_pick(NSArray *paired, long want_connected) -> the headphones, or 0
_hp_pick:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0                      // best
    mov  x22, #1                      // its score (must beat 1)
    mov  x0, x19
    MSG0 Ls_count
    str  x0, [sp, #96]
    mov  x23, #0
Lpk_loop:
    ldr  x9, [sp, #96]
    cmp  x23, x9
    b.hs Lpk_done
    mov  x0, x19
    mov  x2, x23
    MSG1 Ls_objectAtIndex
    mov  x24, x0
    bl   _hp_score
    mov  x9, x0
    cbz  x9, Lpk_next
    str  x9, [sp, #104]
    mov  x0, x24
    MSG0 Ls_isConnected
    ldr  x9, [sp, #104]
    tst  w0, #0xff
    b.eq Lpk_cmp
    add  x9, x9, x20                  // connected counts when we want to let go
Lpk_cmp:
    cmp  x9, x22
    b.le Lpk_next
    mov  x22, x9
    mov  x21, x24
Lpk_next:
    add  x23, x23, #1
    b    Lpk_loop
Lpk_done:
    mov  x0, x21
    LEAVE 16

// long _hp_score(IOBluetoothDevice *d) -> 0 not headphones; 2..4 the likelier
_hp_score:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
    MSG0 Ls_deviceClassMajor
    and  x0, x0, #0xffffffff
    cmp  x0, #4                       // audio / video
    b.ne Lsc_name
    mov  x20, #2
Lsc_name:
    mov  x0, x19
    MSG0 Ls_nameOrAddress
    cbz  x0, Lsc_done
    MSG0 Ls_UTF8String
    cbz  x0, Lsc_done
    mov  x21, x0
    ADRL x22, Lhp_words
Lsc_w:
    ldr  x1, [x22], #8
    cbz  x1, Lsc_done
    mov  x0, x21
    bl   _strcasestr
    cbz  x0, Lsc_w
    add  x20, x20, #2
Lsc_done:
    mov  x0, x20
    LEAVE 0

// void _hp_post(ctx, long code, long err) — a copy of the request, with a message,
//   to the main thread
_hp_post:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, #HC_SIZE
    bl   _malloc
    cbz  x0, Lpo_done
    mov  x22, x0
    mov  x1, x19
    mov  x2, #HC_SIZE
    bl   _memcpy
    str  x20, [x22, #HC_CODE]
    str  x21, [x22, #HC_ERR]
    mov  x1, x22
    LDGOT x0, __dispatch_main_q
    ADRL x2, _hp_main
    bl   _dispatch_async_f
Lpo_done:
    LEAVE 0

// void _hp_worker(ctx) — HP_HERE / HP_SEND
_hp_worker:
    ENTER 0
    mov  x19, x0
    ADRL x0, Ls_IOBluetoothDevice
    bl   _objc_getClass
    cbz  x0, Lwk_none
    MSG0 Ls_pairedDevices
    cbz  x0, Lwk_none
    mov  x1, #0
    ldr  x9, [x19, #HC_OP]
    cmp  x9, #HP_SEND
    b.ne Lwk_pick
    mov  x1, #2
Lwk_pick:
    bl   _hp_pick
    cbz  x0, Lwk_none
    mov  x20, x0
    MSG0 Ls_nameOrAddress
    MSG0 Ls_UTF8String
    mov  x1, x0
    add  x0, x19, #HC_NAME
    mov  x2, #64
    bl   _strlcpy
    mov  x0, x20
    add  x1, x19, #HC_HASH
    bl   _hp_hash
    mov  x0, x20
    MSG0 Ls_isConnected
    and  x21, x0, #0xff
    ldr  x9, [x19, #HC_OP]
    cmp  x9, #HP_SEND
    b.eq Lwk_send
    cbz  x21, Lwk_ask
    mov  x0, x19
    mov  x1, #HM_ALREADY
    mov  x2, #0
    bl   _hp_post
    b    Lwk_free
Lwk_ask:                              // the others let go; then connect here
    mov  x0, x19
    mov  x1, #HM_ASKING
    mov  x2, #0
    bl   _hp_post
    MOVI x0, 2000000
    bl   _usleep
    mov  x0, x20
    MSG0 Ls_openConnection
    and  x21, x0, #0xffffffff
    cbz  x21, Lwk_ok
    MOVI x0, 3000000                  // still busy elsewhere? once more
    bl   _usleep
    mov  x0, x20
    MSG0 Ls_openConnection
    and  x21, x0, #0xffffffff
    cbz  x21, Lwk_ok
    mov  x0, x19
    mov  x1, #HM_FAIL
    mov  x2, x21
    bl   _hp_post
    b    Lwk_free
Lwk_ok:
    mov  x0, x19
    mov  x1, #HM_OK
    mov  x2, #0
    bl   _hp_post
    b    Lwk_free
Lwk_send:                             // let go here, then ask the other Mac
    cbz  x21, Lwk_sent
    mov  x0, x20
    MSG0 Ls_closeConnection
    MOVI x0, 500000
    bl   _usleep
Lwk_sent:
    mov  x0, x19
    mov  x1, #HM_SENT
    mov  x2, #0
    bl   _hp_post
    b    Lwk_free
Lwk_none:
    mov  x0, x19
    mov  x1, #HM_NONE
    mov  x2, #0
    bl   _hp_post
Lwk_free:
    mov  x0, x19
    bl   _free
    LEAVE 0

// void _hp_rx_worker(ctx) — another Mac asked: find our headphones by fingerprint
_hp_rx_worker:
    ENTER 32
    mov  x19, x0
    ADRL x0, Ls_IOBluetoothDevice
    bl   _objc_getClass
    cbz  x0, Lrw_free
    MSG0 Ls_pairedDevices
    cbz  x0, Lrw_free
    mov  x20, x0
    MSG0 Ls_count
    mov  x21, x0
    mov  x22, #0
Lrw_loop:
    cmp  x22, x21
    b.hs Lrw_free                     // not paired with those: nothing to do
    mov  x0, x20
    mov  x2, x22
    MSG1 Ls_objectAtIndex
    mov  x23, x0
    add  x1, sp, #96
    bl   _hp_hash
    add  x0, sp, #96
    add  x1, x19, #HC_HASH
    mov  x2, #16
    bl   _memcmp
    cbz  w0, Lrw_found
    add  x22, x22, #1
    b    Lrw_loop
Lrw_found:
    mov  x0, x23
    MSG0 Ls_nameOrAddress
    MSG0 Ls_UTF8String
    mov  x1, x0
    add  x0, x19, #HC_NAME
    mov  x2, #64
    bl   _strlcpy
    mov  x0, x23
    MSG0 Ls_isConnected
    and  x24, x0, #0xff
    ldr  x9, [x19, #HC_OP]
    cmp  x9, #HP_GRAB
    b.eq Lrw_grab
    cbz  x24, Lrw_free                // release: only if we have them
    mov  x0, x23
    MSG0 Ls_closeConnection
    mov  x0, x19
    mov  x1, #HM_LET_GO
    mov  x2, #0
    bl   _hp_post
    b    Lrw_free
Lrw_grab:
    cbnz x24, Lrw_free                // already here
    MOVI x0, 1500000                  // give the sender a moment to let go
    bl   _usleep
    mov  x0, x23
    MSG0 Ls_openConnection
    and  x21, x0, #0xffffffff
    mov  x0, x19
    mov  x1, #HM_GOT
    mov  x2, #0
    cbz  x21, Lrw_post
    mov  x1, #HM_GOT_FAIL
    mov  x2, x21
Lrw_post:
    bl   _hp_post
Lrw_free:
    mov  x0, x19
    bl   _free
    LEAVE 32

// ===========================================================================
// Main thread: the mesh and the Home room
// ===========================================================================

// void _hp_main(msg)
_hp_main:
    ENTER 0
    mov  x19, x0
    ldr  x9, [x19, #HC_CODE]
    add  x20, x19, #HC_NAME
    cmp  x9, #HM_NONE
    b.eq Lhm_none
    cmp  x9, #HM_ALREADY
    b.eq Lhm_already
    cmp  x9, #HM_ASKING
    b.eq Lhm_asking
    cmp  x9, #HM_OK
    b.eq Lhm_ok
    cmp  x9, #HM_FAIL
    b.eq Lhm_fail
    cmp  x9, #HM_SENT
    b.eq Lhm_sent
    cmp  x9, #HM_LET_GO
    b.eq Lhm_let_go
    cmp  x9, #HM_GOT
    b.eq Lhm_got
    cmp  x9, #HM_GOT_FAIL
    b.eq Lhm_got_fail
    b    Lhm_free
Lhm_none:
    ADRL x0, Ls_hm_none
    bl   _home_say0
    b    Lhm_free
Lhm_already:
    ADRL x0, Lf_hm_already
    mov  x1, x20
    bl   _home_say
    b    Lhm_free
Lhm_asking:
    mov  x0, #HP_RELEASE
    mov  x1, #0
    add  x2, x19, #HC_HASH
    bl   _hp_send_pkt
    ADRL x0, Lf_hm_asking
    mov  x1, x20
    bl   _home_say
    b    Lhm_free
Lhm_ok:
    ADRL x0, Lf_hm_ok
    mov  x1, x20
    bl   _home_say
    b    Lhm_free
Lhm_fail:
    ADRL x0, Lf_hm_fail
    mov  x1, x20
    ldr  x2, [x19, #HC_ERR]
    bl   _home_say
    b    Lhm_free
Lhm_sent:
    mov  x0, #HP_GRAB
    ldr  x1, [x19, #HC_TARGET]
    add  x2, x19, #HC_HASH
    bl   _hp_send_pkt
    ADRL x0, Lf_hm_sent
    mov  x1, x20
    add  x2, x19, #HC_NICK
    bl   _home_say
    b    Lhm_free
Lhm_let_go:
    ADRL x0, Lf_hm_let_go
    mov  x1, x20
    add  x2, x19, #HC_NICK
    bl   _home_say
    b    Lhm_free
Lhm_got:
    ADRL x0, Lf_hm_got
    mov  x1, x20
    add  x2, x19, #HC_NICK
    bl   _home_say
    b    Lhm_free
Lhm_got_fail:
    ADRL x0, Lf_hm_got_fail
    add  x1, x19, #HC_NICK
    mov  x2, x20
    ldr  x3, [x19, #HC_ERR]
    bl   _home_say
Lhm_free:
    bl   _ui_lists_changed
    mov  x0, x19
    bl   _free
    LEAVE 0

// long _hp_send_pkt(long op, uint64 target, const uint8 hash[16]) -> peers written
.globl _hp_send_pkt
_hp_send_pkt:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x0, _g_hp_pkt
    mov  w1, #T_HP
    bl   _pkt_begin
    ADRL x22, _g_hp_pkt
    str  x20, [x22, #12]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x22, #20]
    add  x0, x22, #28
    bl   _put_nick
    strb w19, [x0]
    add  x23, x0, #1
    mov  x0, x23
    mov  x1, x21
    mov  x2, #16
    bl   _memcpy
    add  x23, x23, #16
    sub  x1, x23, x22
    mov  x0, x22
    bl   _pkt_finish
    cbz  x0, Lsp_fail
    mov  x1, x0
    mov  x0, x22
    bl   _ble_broadcast
    LEAVE 0
Lsp_fail:
    mov  x0, #0
    LEAVE 0

// long _hp_rx(const uint8 *pkt, size_t body_len, long nick_len) — a T_HP arrived (the
//   sender's name is in _g_nickbuf). -> 1 if it was for this Mac alone (not passed on)
.globl _hp_rx
_hp_rx:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x22, x21, #(29 + 17)         // nick, op, fingerprint
    cmp  x20, x22
    b.lo Lhr_relay
    ldr  x9, [x19, #20]               // our own, come back round
    ADRL x8, _g_node_id
    ldr  x8, [x8]
    cmp  x9, x8
    b.eq Lhr_mine
    ldr  x23, [x19, #12]
    cbz  x23, Lhr_go
    cmp  x23, x8
    b.ne Lhr_relay                    // for another Mac
Lhr_go:
    add  x24, x19, x21
    add  x24, x24, #29                // op, then the fingerprint
    ldrb w9, [x24]
    cmp  w9, #HP_RELEASE
    b.eq Lhr_ok_op
    cmp  w9, #HP_GRAB
    b.ne Lhr_done
Lhr_ok_op:
    mov  x0, #0
    bl   _time
    ADRL x8, _g_hp_last
    ldr  x9, [x8]
    sub  x10, x0, x9
    cmp  x10, #3
    b.lt Lhr_done
    str  x0, [x8]
    mov  x0, #1
    mov  x1, #HC_SIZE
    bl   _calloc
    cbz  x0, Lhr_done
    mov  x22, x0
    ldrb w9, [x24]
    str  x9, [x22, #HC_OP]
    add  x0, x22, #HC_HASH
    add  x1, x24, #1
    mov  x2, #16
    bl   _memcpy
    add  x0, x22, #HC_NICK
    ADRL x1, _g_nickbuf
    mov  x2, #32
    bl   _strlcpy
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, x22
    ADRL x2, _hp_rx_worker
    bl   _dispatch_async_f
Lhr_done:
    cbz  x23, Lhr_relay               // to every Mac: pass it on too
Lhr_mine:
    mov  x0, #1
    LEAVE 0
Lhr_relay:
    mov  x0, #0
    LEAVE 0

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lhp_words:
    .quad Ls_w_airpods, Ls_w_beats, Ls_w_headphone, Ls_w_buds, Ls_w_earbud, 0

.section __TEXT,__cstring,cstring_literals
Ls_empty:            .asciz ""
Ls_IOBluetoothDevice: .asciz "IOBluetoothDevice"
Ls_pairedDevices:    .asciz "pairedDevices"
Ls_count:            .asciz "count"
Ls_objectAtIndex:    .asciz "objectAtIndex:"
Ls_isConnected:      .asciz "isConnected"
Ls_nameOrAddress:    .asciz "nameOrAddress"
Ls_addressString:    .asciz "addressString"
Ls_UTF8String:       .asciz "UTF8String"
Ls_deviceClassMajor: .asciz "deviceClassMajor"
Ls_openConnection:   .asciz "openConnection"
Ls_closeConnection:  .asciz "closeConnection"
Ls_hp_salt:          .asciz "asmmesh-hp:"
Ls_w_airpods:        .asciz "airpods"
Ls_w_beats:          .asciz "beats"
Ls_w_headphone:      .asciz "headphone"
Ls_w_buds:           .asciz "buds"
Ls_w_earbud:         .asciz "earbud"
Lf_hp_who:           .asciz "\302\267 \360\237\216\247 I don't see a Mac called \342\200\234%s\342\200\235 on the mesh right now \342\200\224 use a name from People on the mesh."
Ls_hm_none:          .asciz "\302\267 \360\237\216\247 I can't find paired headphones on this Mac. Pair them once in Bluetooth Settings (AirPods paired to your iPhone usually show up on your Macs by themselves)."
Lf_hm_already:       .asciz "\302\267 \360\237\216\247 %s is already connected to this Mac."
Lf_hm_asking:        .asciz "\302\267 \360\237\216\247 Asking your other Macs to let go of %s, then connecting it here\342\200\246"
Lf_hm_ok:            .asciz "\302\267 \360\237\216\247 %s is connected here."
Lf_hm_fail:          .asciz "\302\267 \360\237\216\247 %s didn't connect (error 0x%lx). Is it in its case with the lid closed, or still busy with a phone? Try again in a moment."
Lf_hm_sent:          .asciz "\302\267 \360\237\216\247 Let go of %s and asked %s to connect it."
Lf_hm_let_go:        .asciz "\302\267 \360\237\216\247 Let go of %s \342\200\224 %s asked for it."
Lf_hm_got:           .asciz "\302\267 \360\237\216\247 %s is connected here \342\200\224 sent over from %s."
Lf_hm_got_fail:      .asciz "\302\267 \360\237\216\247 %s sent %s over, but it didn't connect (error 0x%lx)."
