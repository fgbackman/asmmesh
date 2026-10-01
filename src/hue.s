// hue.s — Philips Hue.
//
// Bridge: found on the local network with Bonjour (_hue._tcp, via lan.s), or through
// Philips' discovery service if Bonjour finds nothing within a few seconds.
// Pairing: press the round button on the bridge, then "pair hue" — the bridge
// hands back a username, kept in NSUserDefaults with the bridge's address.
// Lights and rooms/zones come from the bridge's local v1 REST API; commands are
// PUTs of small JSON bodies.
//
// Bluetooth bulbs (no bridge): they advertise the 0xFE0F service. Control uses
// Signify's light service 932C32BD-0000-47A2-835A-A8D455B859DD: power
// (…-0002, one byte) and brightness (…-0003, one byte 1..254). macOS asks to
// pair the first time; the bulb must be in pairing mode (just powered on, or
// "make discoverable" in the Hue app). Experimental.

.include "macros.inc"

.data
.p2align 3
_g_hue_browser:   .quad 0
_g_hue_service:   .quad 0
_g_hue_cloud_asked: .quad 0
_g_hb_adv:        .quad 0            // CBUUID FE0F
_g_hb_svc:        .quad 0
_g_hb_pow:        .quad 0
_g_hb_bri:        .quad 0
.zerofill __DATA,__bss,_g_hue_host,128,4
.zerofill __DATA,__bss,_g_hue_user,64,4
.zerofill __DATA,__bss,_g_hue_url,320,4
.zerofill __DATA,__bss,_g_hue_body,160,4

.section __TEXT,__const
.p2align 3
Lc_resolve:   .double 5.0

.text
.p2align 2

// id _defaults(void)
_hdefaults:
    ENTER 0
    CLS  Ls_NSUserDefaults
    MSG0 Ls_standardUserDefaults
    LEAVE 0

// void _pref_get(const char *key, char *buf, size_t max)
.globl _pref_get
_pref_get:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    strb wzr, [x20]
    bl   _hdefaults
    mov  x22, x0
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_stringForKey
    cbz  x0, Lpg_done
    MSG0 Ls_UTF8String
    cbz  x0, Lpg_done
    mov  x1, x0
    mov  x0, x20
    mov  x2, x21
    bl   _strlcpy
Lpg_done:
    LEAVE 0

// void _pref_set(const char *key, const char *value)
.globl _pref_set
_pref_set:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _hdefaults
    mov  x21, x0
    mov  x0, x20
    bl   _nsstr
    mov  x22, x0
    mov  x0, x19
    bl   _nsstr
    mov  x3, x0
    mov  x2, x22
    mov  x0, x21
    MSG2 Ls_setObjectForKey
    LEAVE 0

// ---------------------------------------------------------------------------
// void _hue_init(void)
// ---------------------------------------------------------------------------
.globl _hue_init
_hue_init:
    ENTER 0
    ADRL x0, Ls_key_host
    ADRL x1, _g_hue_host
    mov  x2, #128
    bl   _pref_get
    ADRL x0, Ls_key_user
    ADRL x1, _g_hue_user
    mov  x2, #64
    bl   _pref_get
    bl   _hue_load                   // lan.s browses for _hue._tcp and calls _hue_resolved
    LEAVE 0

// void _hue_tick(long seconds) — Philips' discovery service if Bonjour found nothing
.globl _hue_tick
_hue_tick:
    ENTER 0
    cmp  x0, #8
    b.ne Lht_done
    ADRL x8, _g_hue_host
    ldrb w9, [x8]
    cbnz w9, Lht_done
    ADRL x8, _g_hue_cloud_asked
    ldr  x9, [x8]
    cbnz x9, Lht_done
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, Ls_GET
    ADRL x1, Ls_cloud_url
    mov  x2, #0
    mov  x3, #0
    ADRL x4, Ls_tag_disc
    bl   _http
Lht_done:
    LEAVE 0

// - netServiceBrowser:didFindService:moreComing:
.globl _hue_found
_hue_found:
    ENTER 0
    mov  x19, x3
    ADRL x8, _g_hue_service
    ldr  x9, [x8]
    cbnz x9, Lhf_done                 // one bridge is enough
    mov  x0, x19
    MSG0 Ls_retain
    ADRL x8, _g_hue_service
    str  x0, [x8]
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    MSG1 Ls_setDelegate
    SELX1 Ls_resolveWithTimeout
    ADRL x8, _g_hue_service
    ldr  x0, [x8]
    LDD  d0, Lc_resolve
    bl   _objc_msgSend
Lhf_done:
    LEAVE 0

// - netServiceDidResolveAddress:
.globl _hue_resolved
_hue_resolved:
    ENTER 144                         // [96] host name
    mov  x0, x2
    MSG0 Ls_hostName
    cbz  x0, Lhr_done
    MSG0 Ls_UTF8String
    cbz  x0, Lhr_done
    mov  x1, x0
    add  x0, sp, #96
    mov  x2, #128
    bl   _strlcpy
    add  x0, sp, #96                  // drop the trailing dot of "Philips-hue.local."
    bl   _strlen
    cbz  x0, Lhr_done
    sub  x9, x0, #1
    add  x10, sp, #96
    ldrb w11, [x10, x9]
    cmp  w11, #'.'
    b.ne Lhr_have
    strb wzr, [x10, x9]
Lhr_have:
    add  x0, sp, #96
    bl   _hue_set_host
Lhr_done:
    LEAVE 144

// void _hue_set_host(const char *host) — remember a bridge; pair or load
_hue_set_host:
    ENTER 0
    mov  x19, x0
    ADRL x0, _g_hue_host
    mov  x1, x19
    bl   _strcmp
    cbz  w0, Lhs_same
    ADRL x8, _g_hue_host
    ldrb w20, [x8]                    // did we already know a bridge?
    ADRL x0, _g_hue_host
    mov  x1, x19
    mov  x2, #128
    bl   _strlcpy
    ADRL x0, Ls_key_host
    ADRL x1, _g_hue_host
    bl   _pref_set
    cbnz w20, Lhs_quiet               // same bridge, new address: nothing to announce
    ADRL x1, _g_hue_host
    ADRL x0, Ls_found_bridge
    bl   _home_say
    ADRL x8, _g_hue_user
    ldrb w9, [x8]
    cbz  w9, Lhs_hint
    bl   _hue_load
    LEAVE 0
Lhs_quiet:
    ADRL x8, _g_hue_user
    ldrb w9, [x8]
    cbz  w9, Lhs_done
    bl   _hue_load
    LEAVE 0
Lhs_same:
    ADRL x8, _g_hue_user
    ldrb w9, [x8]
    cbnz w9, Lhs_done
Lhs_hint:
    ADRL x0, Ls_pair_hint
    bl   _home_say0
Lhs_done:
    LEAVE 0

// long _hue_paired(void) -> 1 once the bridge has given us a username
.globl _hue_paired
_hue_paired:
    ADRL x8, _g_hue_user
    ldrb w0, [x8]
    cmp  w0, #0
    cset x0, ne
    ret

// void _hue_status(void) — one line on where Hue setup stands
.globl _hue_status
_hue_status:
    ENTER 0
    ADRL x8, _g_hue_host
    ldrb w9, [x8]
    ADRL x0, Ls_hue_none
    cbz  w9, Lhst_say
    ADRL x8, _g_hue_user
    ldrb w9, [x8]
    ADRL x0, Ls_pair_hint
    cbz  w9, Lhst_say
    ADRL x0, Ls_hue_ok
Lhst_say:
    bl   _home_say0
    LEAVE 0

// void _hue_pair(void) — "pair hue"
.globl _hue_pair
_hue_pair:
    ENTER 0
    ADRL x8, _g_hue_host
    ldrb w9, [x8]
    cbz  w9, Lhp_nobridge
    ADRL x2, _g_hue_host
    str  x2, [sp]
    ADRL x0, _g_hue_url
    mov  x1, #320
    ADRL x2, Lf_pair
    bl   _snprintf
    ADRL x0, Ls_POST
    ADRL x1, _g_hue_url
    ADRL x2, Ls_pair_body
    mov  x3, #0
    ADRL x4, Ls_tag_pair
    bl   _http
    ADRL x0, Ls_pairing
    bl   _home_say0
    LEAVE 0
Lhp_nobridge:
    ADRL x0, Ls_hue_none
    bl   _home_say0
    LEAVE 0

// void _hue_load(void) — lights and rooms from the bridge
.globl _hue_load
_hue_load:
    ENTER 0
    ADRL x8, _g_hue_host
    ldrb w9, [x8]
    cbz  w9, Lhl_done
    ADRL x8, _g_hue_user
    ldrb w9, [x8]
    cbz  w9, Lhl_done
    ADRL x0, Lf_lights                // rooms are asked for once the lights are in,
    ADRL x1, Ls_tag_lights            // so each light can be put in its room
    bl   Lhl_get
Lhl_done:
    LEAVE 0
Lhl_get:                              // (fmt x0, tag x1) GET http://host/api/user/...
    stp  x29, x30, [sp, #-32]!
    str  x1, [sp, #16]
    mov  x2, x0
    ADRL x9, _g_hue_host
    ADRL x10, _g_hue_user
    sub  sp, sp, #16
    stp  x9, x10, [sp]
    ADRL x0, _g_hue_url
    mov  x1, #320
    bl   _snprintf
    add  sp, sp, #16
    ADRL x0, Ls_GET
    ADRL x1, _g_hue_url
    mov  x2, #0
    mov  x3, #0
    ldr  x4, [sp, #16]
    bl   _http
    ldp  x29, x30, [sp], #32
    ret

// void _hue_set(long idx, long action, long value)
.globl _hue_set
_hue_set:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_hue_user
    ldrb w9, [x8]
    cbz  w9, Lhz_unpaired
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    // body
    ADRL x2, Lb_on
    cmp  x20, #A_ON
    b.eq Lhz_body0
    ADRL x2, Lb_off
    cmp  x20, #A_OFF
    b.eq Lhz_body0
    ADRL x2, Lb_up
    cmp  x20, #A_BRIGHTER
    b.eq Lhz_body0
    ADRL x2, Lb_down
    cmp  x20, #A_DIMMER
    b.eq Lhz_body0
    cmp  x20, #A_LEVEL
    b.eq Lhz_level
    cmp  x20, #A_COLOR
    b.eq Lhz_colour
    // colour temperature: mired = 1,000,000 / kelvin, 153..500
    mov  x9, #16960
    movk x9, #15, lsl #16             // 1,000,000
    udiv x9, x9, x21
    cmp  x9, #153
    mov  x10, #153
    csel x9, x10, x9, lo
    cmp  x9, #500
    mov  x10, #500
    csel x9, x10, x9, hi
    ADRL x2, Lb_ct
    b    Lhz_body1
Lhz_level:
    mov  x9, #254
    mul  x9, x21, x9
    mov  x10, #100
    udiv x9, x9, x10
    cmp  x9, #1
    csinc x9, x9, xzr, hs             // at least 1
    ADRL x2, Lb_bri
    b    Lhz_body1
Lhz_colour:
    mov  x9, #65535
    mul  x9, x21, x9
    mov  x10, #360
    udiv x9, x9, x10
    ADRL x2, Lb_hue
Lhz_body1:
    str  x9, [sp]
    ADRL x0, _g_hue_body
    mov  x1, #160
    bl   _snprintf
    b    Lhz_url
Lhz_body0:
    ADRL x0, _g_hue_body
    mov  x1, x2
    mov  x2, #160
    bl   _strlcpy
Lhz_url:
    ADRL x9, _g_hue_host
    str  x9, [sp]
    ADRL x9, _g_hue_user
    str  x9, [sp, #8]
    add  x9, x22, #D_ID
    str  x9, [sp, #16]
    ldr  x10, [x22, #D_KIND]
    ADRL x2, Lf_light_state
    ADRL x8, Lf_group_action
    cmp  x10, #K_HUE_GROUP
    csel x2, x8, x2, eq
    ADRL x0, _g_hue_url
    mov  x1, #320
    bl   _snprintf
    ADRL x0, Ls_PUT
    ADRL x1, _g_hue_url
    ADRL x2, _g_hue_body
    mov  x3, #0
    ADRL x4, Ls_tag_set
    bl   _http
    // what we now believe
    mov  x1, #1
    cmp  x20, #A_OFF
    csel x1, xzr, x1, eq
    mov  x2, #-1
    cmp  x20, #A_LEVEL
    csel x2, x21, x2, eq
    cmp  x20, #A_DIMMER
    b.ne Lhz_state
    ldr  x1, [x22, #D_ON]             // dimming leaves on/off as it was
Lhz_state:
    mov  x0, x19
    bl   _dev_state
    mov  x0, #1
    LEAVE 32
Lhz_unpaired:
    ADRL x0, Ls_pair_hint
    bl   _home_say0
    mov  x0, #2
    LEAVE 32

// ---------------------------------------------------------------------------
// void _hue_response(const char *tag, id json, long status, NSError *err)
// ---------------------------------------------------------------------------
.globl _hue_response
_hue_response:
    ENTER 64
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldrb w9, [x19, #1]
    cmp  w9, #'d'
    b.eq Lhx_disc
    cbnz x22, Lhx_neterr
    cmp  w9, #'p'
    b.eq Lhx_pair
    cmp  w9, #'l'
    b.eq Lhx_lists
    cmp  w9, #'g'
    b.eq Lhx_lists
    b    Lhx_set

Lhx_neterr:
    mov  x0, x22
    bl   _err_cstr
    mov  x2, x0
    ADRL x1, _g_hue_host
    ADRL x0, Ls_hue_unreach
    bl   _home_say
    LEAVE 64

Lhx_disc:                             // [{"id":..,"internalipaddress":"192.168.1.20"}]
    cbnz x22, Lhx_done
    mov  x0, x20
    mov  x1, #0
    bl   _jat
    ADRL x1, Ls_j_ip
    bl   _jget
    bl   _jstr
    cbz  x0, Lhx_done
    ADRL x8, _g_hue_host
    ldrb w9, [x8]
    cbnz w9, Lhx_done                 // Bonjour got there first
    bl   _hue_set_host
    LEAVE 64

Lhx_pair:                             // [{"success":{"username":".."}}] or [{"error":{..}}]
    mov  x0, x20
    mov  x1, #0
    bl   _jat
    mov  x23, x0
    ADRL x1, Ls_j_success
    bl   _jget
    ADRL x1, Ls_j_username
    bl   _jget
    bl   _jstr
    cbz  x0, Lhx_pair_err
    mov  x1, x0
    ADRL x0, _g_hue_user
    mov  x2, #64
    bl   _strlcpy
    ADRL x0, Ls_key_user
    ADRL x1, _g_hue_user
    bl   _pref_set
    ADRL x0, Ls_paired
    bl   _home_say0
    bl   _hue_load
    LEAVE 64
Lhx_pair_err:
    mov  x0, x23
    ADRL x1, Ls_j_error
    bl   _jget
    mov  x23, x0
    ADRL x1, Ls_j_type
    bl   _jget
    bl   _jint
    cmp  x0, #101
    b.ne Lhx_err_desc
    ADRL x0, Ls_press_button
    bl   _home_say0
    LEAVE 64

Lhx_lists:
    // an array here means an error, e.g. the username is no longer valid
    mov  x0, x20
    bl   _jcount
    cbz  x0, Lhx_dict
    mov  x0, x20
    mov  x1, #0
    bl   _jat
    ADRL x1, Ls_j_error
    bl   _jget
    mov  x23, x0
    ADRL x1, Ls_j_type
    bl   _jget
    bl   _jint
    cmp  x0, #1
    b.ne Lhx_err_desc
    ADRL x8, _g_hue_user              // unauthorised: forget the username
    strb wzr, [x8]
    ADRL x0, Ls_key_user
    ADRL x1, _g_hue_user
    bl   _pref_set
    ADRL x0, Ls_repair
    bl   _home_say0
    LEAVE 64
Lhx_dict:
    ldrb w9, [x19, #1]
    cmp  w9, #'g'
    cset w1, eq
    mov  x0, x20
    bl   _hue_take
    mov  x21, x0
    ldrb w9, [x19, #1]
    cmp  w9, #'l'
    b.ne Lhx_counted
    ADRL x0, Lf_groups                // now the rooms
    ADRL x1, Ls_tag_groups
    bl   Lhl_get
Lhx_counted:
    mov  x0, x21
    cbz  x0, Lhx_done
    mov  x1, x0
    ldrb w9, [x19, #1]
    ADRL x0, Ls_hue_lights_ready
    ADRL x8, Ls_hue_rooms_ready
    cmp  w9, #'g'
    csel x0, x8, x0, eq
    bl   _home_say
    bl   _ui_lists_changed
    LEAVE 64

Lhx_err_desc:
    mov  x0, x23
    ADRL x1, Ls_j_description
    bl   _jget
    bl   _jstr
    cbz  x0, Lhx_done
    mov  x1, x0
    ADRL x0, Ls_hue_said
    bl   _home_say
    LEAVE 64

Lhx_set:                              // [{"success":..}, {"error":..}]
    mov  x0, x20
    bl   _jcount
    mov  x24, x0
    mov  x21, #0
Lhx_set_loop:
    cmp  x21, x24
    b.hs Lhx_done
    mov  x0, x20
    mov  x1, x21
    bl   _jat
    ADRL x1, Ls_j_error
    bl   _jget
    cbz  x0, Lhx_set_next
    mov  x23, x0
    b    Lhx_err_desc
Lhx_set_next:
    add  x21, x21, #1
    b    Lhx_set_loop
Lhx_done:
    LEAVE 64

// long _hue_take(NSDictionary *d, int groups) — register lights, or rooms/zones -> count
_hue_take:
    ENTER 32                          // [96] keys  [104] n  [112] i  [120] taken
    mov  x19, x0
    mov  w20, w1
    bl   _jkeys
    str  x0, [sp, #96]
    bl   _jcount
    str  x0, [sp, #104]
    str  xzr, [sp, #112]
    str  xzr, [sp, #120]
Ltk_loop:
    ldr  x9, [sp, #112]
    ldr  x10, [sp, #104]
    cmp  x9, x10
    b.hs Ltk_done
    ldr  x0, [sp, #96]
    mov  x1, x9
    bl   _jat
    mov  x21, x0                      // key
    MSG0 Ls_UTF8String
    mov  x22, x0                      // key as C string ("3")
    cbz  x22, Ltk_next
    mov  x0, x19
    mov  x2, x21
    MSG1 Ls_objectForKey
    mov  x23, x0                      // entry
    ADRL x1, Ls_j_name
    bl   _jget
    bl   _jstr
    mov  x24, x0                      // name
    cbz  x24, Ltk_next
    cbnz w20, Ltk_group
    mov  x0, x23
    ADRL x1, Ls_j_state
    bl   _jget
    mov  x23, x0                      // state
    bl   _hue_caps
    mov  x3, x0
    mov  x0, #K_HUE_LIGHT
    mov  x1, x22
    mov  x2, x24
    bl   _dev_add
    tbnz x0, #63, Ltk_next
    mov  x24, x0
    mov  x0, x23
    ADRL x1, Ls_j_on
    bl   _jget
    bl   _jint
    mov  x21, x0
    mov  x0, x23
    ADRL x1, Ls_j_bri
    bl   _jget
    bl   _jint
    mov  x9, #100
    mul  x2, x0, x9
    mov  x9, #254
    udiv x2, x2, x9
    mov  x1, x21
    mov  x0, x24
    bl   _dev_state
    b    Ltk_took
Ltk_group:
    mov  x0, x23
    ADRL x1, Ls_j_type
    bl   _jget
    bl   _jstr
    cbz  x0, Ltk_next
    mov  x21, x0
    ADRL x1, Ls_room
    bl   _strcmp
    cbz  w0, Ltk_group_ok
    mov  x0, x21
    ADRL x1, Ls_zone
    bl   _strcmp
    cbz  w0, Ltk_group_ok
    mov  x0, x21
    ADRL x1, Ls_lightgroup
    bl   _strcmp
    cbnz w0, Ltk_next
Ltk_group_ok:
    mov  x0, x21                      // a Room: its lights are in it
    ADRL x1, Ls_room
    bl   _strcmp
    cbnz w0, Ltk_group_add
    mov  x0, x23
    mov  x1, x24
    bl   _hue_room_mark
Ltk_group_add:
    mov  x0, x23
    ADRL x1, Ls_j_action
    bl   _jget
    bl   _hue_caps
    mov  x3, x0
    mov  x0, #K_HUE_GROUP
    mov  x1, x22
    mov  x2, x24
    bl   _dev_add
    tbnz x0, #63, Ltk_next
    ADRL x8, _g_devs                  // a room is in itself
    add  x8, x8, x0, lsl #DEV_SHIFT
    mov  x21, x0
    add  x0, x8, #D_ROOM
    mov  x1, x24
    mov  x2, #D_ROOM_MAX
    bl   _strlcpy
    mov  x0, x21
    mov  x24, x0
    mov  x0, x23
    ADRL x1, Ls_j_state
    bl   _jget
    ADRL x1, Ls_j_any_on
    bl   _jget
    bl   _jint
    mov  x1, x0
    mov  x2, #-1
    mov  x0, x24
    bl   _dev_state
Ltk_took:
    ldr  x9, [sp, #120]
    add  x9, x9, #1
    str  x9, [sp, #120]
Ltk_next:
    ldr  x9, [sp, #112]
    add  x9, x9, #1
    str  x9, [sp, #112]
    b    Ltk_loop
Ltk_done:
    ldr  x0, [sp, #120]
    LEAVE 32

// void _hue_room_mark(NSDictionary *group, const char *room) — its "lights" are in room
_hue_room_mark:
    ENTER 0
    mov  x21, x1
    ADRL x1, Ls_j_lights
    bl   _jget
    mov  x19, x0
    bl   _jcount
    mov  x20, x0
    mov  x22, #0
Lhm_loop:
    cmp  x22, x20
    b.hs Lhm_done
    mov  x0, x19
    mov  x1, x22
    bl   _jat
    bl   _jstr
    add  x22, x22, #1
    cbz  x0, Lhm_loop
    mov  x1, x0
    mov  x0, #K_HUE_LIGHT
    bl   _dev_find
    tbnz x0, #63, Lhm_loop
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    add  x0, x8, #D_ROOM
    mov  x1, x21
    mov  x2, #D_ROOM_MAX
    bl   _strlcpy
    b    Lhm_loop
Lhm_done:
    LEAVE 0

// long _hue_caps(NSDictionary *state_or_action) -> CAP_ bits
_hue_caps:
    ENTER 0
    mov  x19, x0
    mov  x20, #(CAP_ON | CAP_LEVEL)
    ADRL x1, Ls_j_hue
    bl   _jget
    cbz  x0, Lhc_ct
    orr  x20, x20, #CAP_COLOR
Lhc_ct:
    mov  x0, x19
    ADRL x1, Ls_j_ct
    bl   _jget
    cbz  x0, Lhc_done
    orr  x20, x20, #CAP_CT
Lhc_done:
    mov  x0, x20
    LEAVE 0

// ===========================================================================
// Hue Bluetooth bulbs (no bridge)
// ===========================================================================

// void _hueble_init(void) — the UUIDs
.globl _hueble_init
_hueble_init:
    ENTER 0
    CLS  Ls_CBUUID
    mov  x19, x0
    ADRL x0, Ls_hb_adv
    ADRL x20, _g_hb_adv
    bl   Lhb_uuid
    ADRL x0, Ls_hb_svc
    ADRL x20, _g_hb_svc
    bl   Lhb_uuid
    ADRL x0, Ls_hb_pow
    ADRL x20, _g_hb_pow
    bl   Lhb_uuid
    ADRL x0, Ls_hb_bri
    ADRL x20, _g_hb_bri
    bl   Lhb_uuid
    LEAVE 0
Lhb_uuid:                             // string x0 -> retained CBUUID stored at [x20]
    stp  x29, x30, [sp, #-16]!
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    str  x0, [x20]
    ldp  x29, x30, [sp], #16
    ret

// CBUUID *_hueble_adv(void)
.globl _hueble_adv
_hueble_adv:
    ADRL x8, _g_hb_adv
    ldr  x0, [x8]
    ret

// void _hueble_seen(CBPeripheral *p, const char *name) — a bulb is advertising
.globl _hueble_seen
_hueble_seen:
    ENTER 64                          // [96] id
    mov  x19, x0
    mov  x20, x1
    mov  x0, #SVC_HUE                 // Hue switched off: leave the bulb alone
    bl   _svc_on
    cbz  x0, Lhbs_done
    bl   _dev_find_obj
    tbz  x0, #63, Lhbs_done
    str  x19, [sp]
    add  x0, sp, #96
    mov  x1, #40
    ADRL x2, Lf_ble_id
    bl   _snprintf
    cbz  x20, Lhbs_default
    ldrb w9, [x20]
    cbnz w9, Lhbs_add
Lhbs_default:
    ADRL x20, Ls_hb_default
Lhbs_add:
    mov  x0, #K_HUE_BLE
    add  x1, sp, #96
    mov  x2, x20
    mov  x3, #(CAP_ON | CAP_LEVEL)
    bl   _dev_add
    tbnz x0, #63, Lhbs_done
    ADRL x8, _g_devs
    add  x21, x8, x0, lsl #DEV_SHIFT
    mov  x0, x19
    MSG0 Ls_retain
    str  x0, [x21, #D_OBJ]
    add  x1, x21, #D_NAME
    mov  x2, x1
    ADRL x0, Ls_hb_found
    bl   _home_say
    bl   _ui_lists_changed
Lhbs_done:
    LEAVE 64

// void _hueble_set(long idx, long action, long value) — remember it; connect if needed
.globl _hueble_set
_hueble_set:
    ENTER 0
    ADRL x8, _g_devs
    add  x19, x8, x0, lsl #DEV_SHIFT
    mov  x20, x0
    str  x1, [x19, #(D_AUX + 16)]      // pending action
    str  x2, [x19, #(D_AUX + 24)]      // pending value
    ldr  x9, [x19, #D_CAPS]
    tst  x9, #CAP_LINKED
    b.eq Lhbx_connect
    mov  x0, x20
    bl   _hueble_write
    mov  x0, #1
    LEAVE 0
Lhbx_connect:
    ADRL x8, _g_cm
    ldr  x0, [x8]
    ldr  x2, [x19, #D_OBJ]
    mov  x3, #0
    MSG2 Ls_connectPeripheral
    mov  x0, #1
    LEAVE 0

// void _hueble_connected(CBPeripheral *p)
.globl _hueble_connected
_hueble_connected:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    MSG1 Ls_setDelegate
    CLS  Ls_NSArray
    ADRL x8, _g_hb_svc
    ldr  x2, [x8]
    MSG1 Ls_arrayWithObject
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_discoverServices
    LEAVE 0

// void _hueble_services(CBPeripheral *p)
.globl _hueble_services
_hueble_services:
    ENTER 16
    mov  x19, x0
    MSG0 Ls_services
    MSG0 Ls_firstObject
    cbz  x0, Lhbv_done
    mov  x20, x0
    ADRL x8, _g_hb_pow
    ldr  x9, [x8]
    ADRL x8, _g_hb_bri
    ldr  x10, [x8]
    stp  x9, x10, [sp, #96]
    CLS  Ls_NSArray
    add  x2, sp, #96
    mov  x3, #2
    MSG2 Ls_arrayWithObjectsCount
    mov  x2, x0
    mov  x0, x19
    mov  x3, x20
    MSG2 Ls_discoverCharacteristics
Lhbv_done:
    LEAVE 16

// void _hueble_chars(CBPeripheral *p, CBService *s) — keep power and brightness
.globl _hueble_chars
_hueble_chars:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x19
    bl   _dev_find_obj
    tbnz x0, #63, Lhbc_done
    mov  x24, x0
    ADRL x8, _g_devs
    add  x21, x8, x24, lsl #DEV_SHIFT
    mov  x0, x20
    MSG0 Ls_characteristics
    mov  x22, x0
    MSG0 Ls_count
    mov  x23, x0
Lhbc_loop:
    cbz  x23, Lhbc_linked
    sub  x23, x23, #1
    mov  x0, x22
    mov  x2, x23
    MSG1 Ls_objectAtIndex
    mov  x20, x0
    MSG0 Ls_UUID
    ADRL x8, _g_hb_pow
    ldr  x2, [x8]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.eq Lhbc_bri
    str  x20, [x21, #D_AUX]
    b    Lhbc_loop
Lhbc_bri:
    mov  x0, x20
    MSG0 Ls_UUID
    ADRL x8, _g_hb_bri
    ldr  x2, [x8]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.eq Lhbc_loop
    str  x20, [x21, #(D_AUX + 8)]
    b    Lhbc_loop
Lhbc_linked:
    ldr  x9, [x21, #D_AUX]
    cbz  x9, Lhbc_done
    ldr  x9, [x21, #D_CAPS]
    orr  x9, x9, #CAP_LINKED
    str  x9, [x21, #D_CAPS]
    mov  x0, x24
    bl   _hueble_write
Lhbc_done:
    LEAVE 0

// void _hueble_lost(CBPeripheral *p)
.globl _hueble_lost
_hueble_lost:
    ENTER 0
    bl   _dev_find_obj
    tbnz x0, #63, Lhbl_done
    ADRL x8, _g_devs
    add  x9, x8, x0, lsl #DEV_SHIFT
    ldr  x10, [x9, #D_CAPS]
    bic  x10, x10, #CAP_LINKED
    str  x10, [x9, #D_CAPS]
    str  xzr, [x9, #D_AUX]
    str  xzr, [x9, #(D_AUX + 8)]
Lhbl_done:
    LEAVE 0

// void _hueble_write(long idx) — carry out the pending action over GATT
_hueble_write:
    ENTER 16
    mov  x24, x0
    ADRL x8, _g_devs
    add  x19, x8, x0, lsl #DEV_SHIFT
    ldr  x20, [x19, #(D_AUX + 16)]     // action
    ldr  x21, [x19, #(D_AUX + 24)]     // value
    str  xzr, [x19, #(D_AUX + 16)]
    cmp  x20, #A_OFF
    b.eq Lhw_off
    cmp  x20, #A_ON
    b.eq Lhw_on
    ldr  x22, [x19, #D_LEVEL]         // brighter / dimmer from what we know
    tbz  x22, #63, Lhw_known
    mov  x22, #50
Lhw_known:
    cmp  x20, #A_LEVEL
    csel x22, x21, x22, eq
    cmp  x20, #A_BRIGHTER
    b.ne Lhw_dim
    add  x22, x22, #25
Lhw_dim:
    cmp  x20, #A_DIMMER
    b.ne Lhw_clamp
    subs x22, x22, #25
    b.gt Lhw_clamp
    mov  x22, #1
Lhw_clamp:
    cmp  x22, #100
    mov  x9, #100
    csel x22, x9, x22, hi
    cmp  x22, #1
    mov  x9, #1
    csel x22, x9, x22, lt
    mov  x0, x19
    mov  w1, #1
    ldr  x2, [x19, #D_AUX]
    bl   Lhw_write
    mov  x9, #254
    mul  x9, x22, x9
    mov  x10, #100
    udiv x9, x9, x10
    mov  x0, x19
    mov  w1, w9
    ldr  x2, [x19, #(D_AUX + 8)]
    bl   Lhw_write
    mov  x0, x24
    mov  x1, #1
    mov  x2, x22
    bl   _dev_state
    LEAVE 16
Lhw_on:
    mov  x0, x19
    mov  w1, #1
    ldr  x2, [x19, #D_AUX]
    bl   Lhw_write
    mov  x0, x24
    mov  x1, #1
    ldr  x2, [x19, #D_LEVEL]
    bl   _dev_state
    LEAVE 16
Lhw_off:
    mov  x0, x19
    mov  w1, #0
    ldr  x2, [x19, #D_AUX]
    bl   Lhw_write
    mov  x0, x24
    mov  x1, #0
    ldr  x2, [x19, #D_LEVEL]
    bl   _dev_state
    LEAVE 16
Lhw_write:                            // (entry x0, byte w1, characteristic x2)
    stp  x29, x30, [sp, #-48]!        // [16] byte  [24] entry  [32] characteristic
    cbz  x2, Lhw_skip
    strb w1, [sp, #16]
    str  x0, [sp, #24]
    str  x2, [sp, #32]
    CLS  Ls_NSData
    add  x2, sp, #16
    mov  x3, #1
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    ldr  x9, [sp, #24]
    ldr  x0, [x9, #D_OBJ]
    ldr  x3, [sp, #32]
    mov  x4, #0                       // with response: lets macOS run the pairing
    MSG3 Ls_writeValue
Lhw_skip:
    ldp  x29, x30, [sp], #48
    ret

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_NSUserDefaults:     .asciz "NSUserDefaults"
Ls_NSNetServiceBrowser: .asciz "NSNetServiceBrowser"
Ls_NSArray:            .asciz "NSArray"
Ls_NSData:             .asciz "NSData"
Ls_CBUUID:             .asciz "CBUUID"
Ls_standardUserDefaults: .asciz "standardUserDefaults"
Ls_stringForKey:       .asciz "stringForKey:"
Ls_setObjectForKey:    .asciz "setObject:forKey:"
Ls_UTF8String:         .asciz "UTF8String"
Ls_new:                .asciz "new"
Ls_retain:             .asciz "retain"
Ls_setDelegate:        .asciz "setDelegate:"
Ls_searchForServices:  .asciz "searchForServicesOfType:inDomain:"
Ls_resolveWithTimeout: .asciz "resolveWithTimeout:"
Ls_hostName:           .asciz "hostName"
Ls_objectForKey:       .asciz "objectForKey:"
Ls_UUIDWithString:     .asciz "UUIDWithString:"
Ls_connectPeripheral:  .asciz "connectPeripheral:options:"
Ls_arrayWithObject:    .asciz "arrayWithObject:"
Ls_arrayWithObjectsCount: .asciz "arrayWithObjects:count:"
Ls_discoverServices:   .asciz "discoverServices:"
Ls_services:           .asciz "services"
Ls_firstObject:        .asciz "firstObject"
Ls_discoverCharacteristics: .asciz "discoverCharacteristics:forService:"
Ls_characteristics:    .asciz "characteristics"
Ls_count:              .asciz "count"
Ls_objectAtIndex:      .asciz "objectAtIndex:"
Ls_UUID:               .asciz "UUID"
Ls_isEqual:            .asciz "isEqual:"
Ls_dataWithBytes:      .asciz "dataWithBytes:length:"
Ls_writeValue:         .asciz "writeValue:forCharacteristic:type:"

Ls_key_host:     .asciz "hueHost"
Ls_key_user:     .asciz "hueUser"
Ls_hue_type:     .asciz "_hue._tcp."
Ls_local_domain: .asciz "local."
Ls_cloud_url:    .asciz "https://discovery.meethue.com/"
Ls_GET:          .asciz "GET"
Ls_PUT:          .asciz "PUT"
Ls_POST:         .asciz "POST"
Ls_tag_disc:     .asciz "hd"
Ls_tag_pair:     .asciz "hp"
Ls_tag_lights:   .asciz "hl"
Ls_tag_groups:   .asciz "hg"
Ls_tag_set:      .asciz "hs"
Lf_pair:         .asciz "http://%s/api"
Lf_lights:       .asciz "http://%s/api/%s/lights"
Lf_groups:       .asciz "http://%s/api/%s/groups"
Lf_light_state:  .asciz "http://%s/api/%s/lights/%s/state"
Lf_group_action: .asciz "http://%s/api/%s/groups/%s/action"
Lf_ble_id:       .asciz "ble-%llx"
Ls_pair_body:    .asciz "{\"devicetype\":\"asmmesh#mac\"}"
Lb_on:           .asciz "{\"on\":true}"
Lb_off:          .asciz "{\"on\":false}"
Lb_up:           .asciz "{\"on\":true,\"bri_inc\":64}"
Lb_down:         .asciz "{\"bri_inc\":-64}"
Lb_bri:          .asciz "{\"on\":true,\"bri\":%ld}"
Lb_hue:          .asciz "{\"on\":true,\"hue\":%ld,\"sat\":254}"
Lb_ct:           .asciz "{\"on\":true,\"ct\":%ld}"
Ls_j_ip:         .asciz "internalipaddress"
Ls_j_success:    .asciz "success"
Ls_j_username:   .asciz "username"
Ls_j_error:      .asciz "error"
Ls_j_type:       .asciz "type"
Ls_j_description: .asciz "description"
Ls_j_name:       .asciz "name"
Ls_j_state:      .asciz "state"
Ls_j_action:     .asciz "action"
Ls_j_on:         .asciz "on"
Ls_j_bri:        .asciz "bri"
Ls_j_any_on:     .asciz "any_on"
Ls_j_hue:        .asciz "hue"
Ls_j_ct:         .asciz "ct"
Ls_room:         .asciz "Room"
Ls_j_lights:     .asciz "lights"
Ls_zone:         .asciz "Zone"
Ls_lightgroup:   .asciz "LightGroup"
Ls_hb_adv:       .asciz "FE0F"
Ls_hb_svc:       .asciz "932C32BD-0000-47A2-835A-A8D455B859DD"
Ls_hb_pow:       .asciz "932C32BD-0002-47A2-835A-A8D455B859DD"
Ls_hb_bri:       .asciz "932C32BD-0003-47A2-835A-A8D455B859DD"
Ls_hb_default:   .asciz "Hue Bluetooth bulb"
Ls_hb_found:     .asciz "\302\267 Found a Hue Bluetooth bulb: %s. Say \342\200\234%s on\342\200\235 to try it \342\200\224 macOS may ask to pair it first."
Ls_found_bridge: .asciz "\302\267 Found your Hue Bridge (%s)."
Ls_pair_hint:    .asciz "\302\267 To connect Hue: press the round button on top of the Hue Bridge, then say or type \342\200\234pair hue\342\200\235 within 30 seconds."
Ls_press_button: .asciz "\302\267 The Hue Bridge wants its button pressed first. Press the round button on top of it, then say \342\200\234pair hue\342\200\235 again."
Ls_pairing:      .asciz "\302\267 Asking the Hue Bridge to pair\342\200\246"
Ls_paired:       .asciz "\302\267 Paired with your Hue Bridge. Loading lights and rooms\342\200\246"
Ls_repair:       .asciz "\302\267 The Hue Bridge no longer knows this Mac. Press its button and say \342\200\234pair hue\342\200\235."
Ls_hue_none:     .asciz "\302\267 No Hue Bridge found on this network yet. Make sure this Mac is on the same Wi-Fi as the bridge, then say \342\200\234refresh\342\200\235."
Ls_hue_ok:       .asciz "\302\267 Hue Bridge connected."
Ls_hue_unreach:  .asciz "\302\267 Can't reach the Hue Bridge at %s: %s"
Ls_hue_said:     .asciz "\302\267 Hue says: %s"
Ls_hue_lights_ready: .asciz "\302\267 Hue: %ld lights ready."
Ls_hue_rooms_ready:  .asciz "\302\267 Hue: %ld rooms and zones ready."
