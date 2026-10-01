// lan.s — devices on your Wi-Fi, found with Bonjour (mDNS).
//
// Controlled directly over their local HTTP APIs, no account needed:
//   WLED          _wled._tcp          POST /json/state
//   Elgato        _elg._tcp           PUT  /elgato/lights            (Key Light, Light Strip)
//   Shelly Gen2+  _shelly._tcp        GET  /rpc/Switch.Set, Light.Set, Cover.*
//   Nanoleaf      _nanoleafapi._tcp   PUT  /api/v1/<token>/state     ("pair nanoleaf" gets the token)
//   Hue Bridge    _hue._tcp           handed to hue.s
//   Home Assistant _home-assistant._tcp  its address is offered in "connect home assistant"
// Listed in the Mesh Scanner with what they say about themselves (and whether
// they're open for pairing): HomeKit, Matter, Chromecast / Google TV, AirPlay,
// Sonos, Spotify Connect, printers, ESPHome, Sonoff, Apple devices, Fire TV,
// Xiaomi.

.include "macros.inc"

.set LAN_MAX,   64
.set LAN_SHIFT, 8
.set L_SVC,     0
.set L_TYPE,    8
.set L_PORT,    16
.set L_DEV,     24
.set L_STATE,   32        // 0 found, 1 resolved
.set L_SAID,    40        // announced already
.set L_HOST,    48        // 64
.set L_NAME,    112       // 64
.set L_INFO,    176       // 80

// handlers
.set H_INFO,    0
.set H_HUE,     1
.set H_WLED,    2
.set H_ELGATO,  3
.set H_SHELLY,  4
.set H_NANO,    5
.set H_HA,      6
.set H_HAP,     7
.set H_MATTERC, 8
.set H_CAST,    9

.data
.p2align 3
.globl _g_lan_count
_g_lan_count:   .quad 0
.globl _g_lan
.zerofill __DATA,__bss,_g_lan,16384,4
.zerofill __DATA,__bss,_g_lan_browsers,256,4
.zerofill __DATA,__bss,_g_lan_url,320,4
.zerofill __DATA,__bss,_g_lan_body,320,4
.zerofill __DATA,__bss,_g_lan_tag,32,4
.zerofill __DATA,__bss,_g_lan_tmp,128,4
.zerofill __DATA,__bss,_g_lan_tmp2,128,4
.globl _g_ha_found
.zerofill __DATA,__bss,_g_ha_found,128,4

.section __TEXT,__const
.p2align 3
Lc_resolve:   .double 5.0

.section __DATA,__const
.p2align 3
// service type, what it is, handler
.globl _g_lan_types
_g_lan_types:
Ltypes:
    .quad Lt_hue,      Lk_hue,      H_HUE
    .quad Lt_wled,     Lk_wled,     H_WLED
    .quad Lt_elg,      Lk_elg,      H_ELGATO
    .quad Lt_shelly,   Lk_shelly,   H_SHELLY
    .quad Lt_nano,     Lk_nano,     H_NANO
    .quad Lt_ha,       Lk_ha,       H_HA
    .quad Lt_hap,      Lk_hap,      H_HAP
    .quad Lt_matterc,  Lk_matterc,  H_MATTERC
    .quad Lt_matter,   Lk_matter,   H_INFO
    .quad Lt_cast,     Lk_cast,     H_CAST
    .quad Lt_airplay,  Lk_airplay,  H_INFO
    .quad Lt_sonos,    Lk_sonos,    H_INFO
    .quad Lt_spotify,  Lk_spotify,  H_INFO
    .quad Lt_ipp,      Lk_ipp,      H_INFO
    .quad Lt_esphome,  Lk_esphome,  H_INFO
    .quad Lt_ewelink,  Lk_ewelink,  H_INFO
    .quad Lt_companion, Lk_companion, H_INFO
    .quad Lt_firetv,   Lk_firetv,   H_INFO
    .quad Lt_atv,      Lk_atv,      H_INFO
    .quad Lt_miio,     Lk_miio,     H_INFO
    .quad 0, 0, 0

// HomeKit accessory categories ("ci"), 0..36
Lhap_cat:
    .quad Lci_other, Lci_other, Lci_bridge, Lci_fan, Lci_garage, Lci_bulb, Lci_lock
    .quad Lci_outlet, Lci_switch, Lci_thermo, Lci_sensor, Lci_security, Lci_door
    .quad Lci_window, Lci_blinds, Lci_button, Lci_other, Lci_camera, Lci_camera
    .quad Lci_purifier, Lci_heater, Lci_ac, Lci_humidifier, Lci_other, Lci_other
    .quad Lci_other, Lci_speaker, Lci_other, Lci_sprinkler, Lci_faucet, Lci_other
    .quad Lci_tv, Lci_remote, Lci_router, Lci_other, Lci_tv, Lci_tv

.text
.p2align 2

// entry pointer for index x0 -> x0
.macro LANE reg, idx
    ADRL \reg, _g_lan
    add  \reg, \reg, \idx, lsl #LAN_SHIFT
.endm

// const char *_lan_tag(char letter, long n) -> "l<letter><n>"
_lan_tag:
    ENTER 0
    mov  x4, x1
    mov  x3, x0
    ADRL x0, _g_lan_tag
    mov  x1, #32
    ADRL x2, Lf_tag
    bl   _sfmt
    ADRL x0, _g_lan_tag
    LEAVE 0

// void _lan_init(void) — one browser per service type
.globl _lan_init
_lan_init:
    ENTER 0
    ADRL x19, Ltypes
    mov  x20, #0
Lli_loop:
    ldr  x9, [x19]
    cbz  x9, Lli_done
    CLS  Ls_NSNetServiceBrowser
    MSG0 Ls_new
    mov  x21, x0
    ADRL x8, _g_lan_browsers
    str  x21, [x8, x20, lsl #3]
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x21
    MSG1 Ls_setDelegate
    ldr  x0, [x19]
    bl   _nsstr
    mov  x22, x0
    ADRL x0, Ls_local
    bl   _nsstr
    mov  x3, x0
    mov  x2, x22
    mov  x0, x21
    MSG2 Ls_searchForServices
    add  x19, x19, #24
    add  x20, x20, #1
    cmp  x20, #32
    b.lo Lli_loop
Lli_done:
    LEAVE 0

// - netServiceBrowser:didFindService:moreComing:
.globl _lan_found
_lan_found:
    ENTER 16
    mov  x19, x3
    mov  x0, x19
    MSG0 Ls_type
    MSG0 Ls_UTF8String
    cbz  x0, Llf_done
    mov  x21, x0
    ADRL x22, Ltypes                  // which type is it?
    mov  x20, #0
Llf_type:
    ldr  x1, [x22]
    cbz  x1, Llf_done
    mov  x0, x21
    bl   _strcmp
    cbz  w0, Llf_known
    add  x22, x22, #24
    add  x20, x20, #1
    b    Llf_type
Llf_known:
    mov  x0, x19
    MSG0 Ls_name
    MSG0 Ls_UTF8String
    cbz  x0, Llf_done
    mov  x21, x0
    mov  x23, #0                      // already listed?
Llf_dup:
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x23, x9
    b.hs Llf_new
    LANE x24, x23
    ldr  x9, [x24, #L_TYPE]
    cmp  x9, x20
    b.ne Llf_dup_next
    add  x0, x24, #L_NAME
    mov  x1, x21
    bl   _strcmp
    cbz  w0, Llf_done
Llf_dup_next:
    add  x23, x23, #1
    b    Llf_dup
Llf_new:
    cmp  x9, #LAN_MAX
    b.hs Llf_done
    add  x10, x9, #1
    str  x10, [x8]
    LANE x24, x9
    mov  x0, x24
    mov  x1, #(1 << LAN_SHIFT)
    bl   _bzero
    str  x20, [x24, #L_TYPE]
    mov  x9, #-1
    str  x9, [x24, #L_DEV]
    add  x0, x24, #L_NAME
    mov  x1, x21
    mov  x2, #64
    bl   _strlcpy
    add  x0, x24, #L_NAME
    bl   _utf8_fix
    mov  x0, x19
    MSG0 Ls_retain
    str  x0, [x24, #L_SVC]
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    MSG1 Ls_setDelegate
    SELX1 Ls_resolveWithTimeout
    ldr  x0, [x24, #L_SVC]
    LDD  d0, Lc_resolve
    bl   _objc_msgSend
Llf_done:
    LEAVE 16

// - netServiceDidResolveAddress:
.globl _lan_resolved
_lan_resolved:
    ENTER 32                          // [96] self [104] cmd [112] service
    stp  x0, x1, [sp, #96]
    str  x2, [sp, #112]
    mov  x19, x2
    mov  x21, #0
Llr_find:
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Llr_done
    LANE x22, x21
    ldr  x9, [x22, #L_SVC]
    cmp  x9, x19
    b.eq Llr_have
    add  x21, x21, #1
    b    Llr_find
Llr_have:
    mov  x0, x19
    MSG0 Ls_hostName
    cbz  x0, Llr_done
    MSG0 Ls_UTF8String
    cbz  x0, Llr_done
    mov  x1, x0
    add  x0, x22, #L_HOST
    mov  x2, #64
    bl   _strlcpy
    add  x0, x22, #L_HOST             // "wled-desk.local." -> "wled-desk.local"
    bl   _strlen
    cbz  x0, Llr_port
    sub  x9, x0, #1
    add  x10, x22, #L_HOST
    ldrb w11, [x10, x9]
    cmp  w11, #'.'
    b.ne Llr_port
    strb wzr, [x10, x9]
Llr_port:
    mov  x0, x19
    MSG0 Ls_port
    sxtw x0, w0
    str  x0, [x22, #L_PORT]
    mov  x9, #1
    str  x9, [x22, #L_STATE]
    ldr  x9, [x22, #L_TYPE]
    ADRL x10, Ltypes
    mov  x11, #24
    madd x10, x9, x11, x10
    ldr  x9, [x10, #16]               // handler
    cmp  x9, #H_HUE
    b.eq Llr_hue
    mov  x0, x21
    bl   _lan_take
Llr_done:
    LEAVE 32
Llr_hue:
    ldp  x0, x1, [sp, #96]
    ldr  x2, [sp, #112]
    bl   _hue_resolved
    ADRL x0, Ls_hue_info
    add  x1, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy_swap
    LEAVE 32

// strlcpy with (src, dst, max) — keeps call sites short
_strlcpy_swap:
    mov  x9, x0
    mov  x0, x1
    mov  x1, x9
    b    _strlcpy

// id _lan_txt(long i) -> the TXT record as a dictionary of NSData, or nil
_lan_txt:
    ENTER 0
    LANE x19, x0
    ldr  x0, [x19, #L_SVC]
    MSG0 Ls_TXTRecordData
    cbz  x0, Llt_done
    mov  x20, x0
    CLS  Ls_NSNetService
    mov  x2, x20
    MSG1 Ls_dictFromTXT
Llt_done:
    LEAVE 0

// char *_txt_get(id dict, const char *key, char *buf, size_t max) -> buf, or 0 if absent
_txt_get:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    cbz  x19, Ltg_none
    mov  x0, x20
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_objectForKey
    cbz  x0, Ltg_none
    mov  x23, x0
    MSG0 Ls_length
    cbz  x0, Ltg_none
    sub  x9, x22, #1
    cmp  x0, x9
    csel x24, x0, x9, lo
    mov  x0, x23
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x21
    mov  x2, x24
    bl   _memcpy
    strb wzr, [x21, x24]
    mov  x0, x21
    bl   _utf8_fix
    mov  x0, x21
    LEAVE 0
Ltg_none:
    mov  x0, #0
    LEAVE 0

// void _lan_take(long i) — act on a resolved service
_lan_take:
    ENTER 32                          // [96] txt
    mov  x21, x0
    LANE x22, x21
    mov  x0, x21
    bl   _lan_txt
    str  x0, [sp, #96]
    ldr  x9, [x22, #L_TYPE]
    ADRL x10, Ltypes
    mov  x11, #24
    madd x10, x9, x11, x10
    ldr  x9, [x10, #16]
    add  x23, x22, #L_HOST            // host
    ldr  x24, [x22, #L_PORT]
    // "host:port" for the device id
    ADRL x0, _g_lan_tmp2
    mov  x1, #128
    ADRL x2, Lf_hostport
    mov  x3, x23
    mov  x4, x24
    str  x9, [sp, #104]
    bl   _sfmt
    ldr  x9, [sp, #104]
    cmp  x9, #H_WLED
    b.eq Ltk_wled
    cmp  x9, #H_ELGATO
    b.eq Ltk_elgato
    cmp  x9, #H_SHELLY
    b.eq Ltk_shelly
    cmp  x9, #H_NANO
    b.eq Ltk_nano
    cmp  x9, #H_HA
    b.eq Ltk_ha
    cmp  x9, #H_HAP
    b.eq Ltk_hap
    cmp  x9, #H_MATTERC
    b.eq Ltk_matterc
    cmp  x9, #H_CAST
    b.eq Ltk_cast
    // anything else: its model, if it says
    ldr  x0, [sp, #96]
    bl   _lan_model
    LEAVE 32

Ltk_wled:
    mov  x0, #K_WLED
    ADRL x1, _g_lan_tmp2
    add  x2, x22, #L_NAME
    mov  x3, #(CAP_ON | CAP_LEVEL | CAP_COLOR | CAP_CT)
    bl   _lan_dev
    tbnz x0, #63, Ltk_done
    mov  x1, x0
    mov  x0, #'w'
    bl   _lan_tag
    mov  x4, x0
    ADRL x0, _g_lan_url
    mov  x1, #320
    ADRL x2, Lf_wled_state
    ADRL x3, _g_lan_tmp2
    str  x4, [sp, #104]
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_lan_url
    mov  x2, #0
    mov  x3, #0
    ldr  x4, [sp, #104]
    bl   _http
    ADRL x0, Ls_wled_info
    add  x1, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy_swap
Ltk_done:
    LEAVE 32

Ltk_elgato:                           // name and model first
    mov  x0, #'e'
    mov  x1, x21
    bl   _lan_tag
    str  x0, [sp, #104]
    ADRL x0, _g_lan_url
    mov  x1, #320
    ADRL x2, Lf_elg_info
    ADRL x3, _g_lan_tmp2
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_lan_url
    mov  x2, #0
    mov  x3, #0
    ldr  x4, [sp, #104]
    bl   _http
    LEAVE 32

Ltk_shelly:                           // its own name first, then what it has
    mov  x0, #'z'
    mov  x1, x21
    bl   _lan_tag
    str  x0, [sp, #104]
    ADRL x0, _g_lan_url
    mov  x1, #320
    ADRL x2, Lf_shelly_info
    ADRL x3, _g_lan_tmp2
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_lan_url
    mov  x2, #0
    mov  x3, #0
    ldr  x4, [sp, #104]
    bl   _http
    LEAVE 32

Ltk_nano:
    mov  x0, #K_NANOLEAF
    ADRL x1, _g_lan_tmp2
    add  x2, x22, #L_NAME
    mov  x3, #(CAP_ON | CAP_LEVEL | CAP_COLOR | CAP_CT)
    bl   _lan_dev
    tbnz x0, #63, Ltk_done
    ADRL x8, _g_devs
    add  x24, x8, x0, lsl #DEV_SHIFT
    mov  x0, x21                      // its token, if paired before
    bl   _nano_kc
    add  x1, x24, #D_AUX
    mov  x2, #D_AUX_MAX
    bl   _kc_get
    add  x9, x24, #D_AUX
    ldrb w9, [x9]
    ADRL x0, Ls_nano_paired
    cbnz w9, Ltk_nano_info
    ADRL x0, Ls_nano_unpaired
    ldr  x9, [x22, #L_SAID]
    cbnz x9, Ltk_nano_info
    mov  x9, #1
    str  x9, [x22, #L_SAID]
    add  x1, x22, #L_NAME
    ADRL x0, Ls_nano_found
    bl   _home_say
    ADRL x0, Ls_nano_unpaired
Ltk_nano_info:
    add  x1, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy_swap
    LEAVE 32

Ltk_ha:
    ADRL x0, _g_ha_found
    mov  x1, #128
    ADRL x2, Lf_ha_url
    ADRL x3, _g_lan_tmp2
    bl   _sfmt
    ADRL x0, Ls_ha_info
    add  x1, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy_swap
    ADRL x8, _g_ha_url                // connected already: nothing to say
    ldrb w9, [x8]
    cbnz w9, Ltk_done
    ldr  x9, [x22, #L_SAID]
    cbnz x9, Ltk_done
    mov  x9, #1
    str  x9, [x22, #L_SAID]
    ADRL x1, _g_ha_found
    ADRL x0, Ls_ha_found
    bl   _home_say
    LEAVE 32

Ltk_hap:                              // HomeKit: category, model, and whether it's paired
    ldr  x0, [sp, #96]
    ADRL x1, Ls_k_ci
    ADRL x2, _g_lan_tmp
    mov  x3, #16
    bl   _txt_get
    mov  x9, #0
    cbz  x0, Ltk_hap_cat
    bl   _atol
    mov  x9, x0
    cmp  x9, #36
    csel x9, xzr, x9, hi
Ltk_hap_cat:
    ADRL x8, Lhap_cat
    ldr  x0, [x8, x9, lsl #3]
    add  x1, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy_swap
    ldr  x0, [sp, #96]
    ADRL x1, Ls_k_md
    ADRL x2, _g_lan_tmp
    mov  x3, #48
    bl   _txt_get
    cbz  x0, Ltk_hap_sf
    add  x0, x22, #L_INFO
    ADRL x1, Ls_dot
    mov  x2, #80
    bl   _strlcat
    add  x0, x22, #L_INFO
    ADRL x1, _g_lan_tmp
    mov  x2, #80
    bl   _strlcat
Ltk_hap_sf:
    ldr  x0, [sp, #96]                // sf=1: not paired, ready to add
    ADRL x1, Ls_k_sf
    ADRL x2, _g_lan_tmp
    mov  x3, #8
    bl   _txt_get
    ADRL x1, Ls_hap_paired
    cbz  x0, Ltk_hap_say
    ldrb w9, [x0]
    cmp  w9, #'1'
    b.ne Ltk_hap_say
    ADRL x1, Ls_hap_ready
Ltk_hap_say:
    add  x0, x22, #L_INFO
    mov  x2, #80
    bl   _strlcat
    LEAVE 32

Ltk_matterc:                          // Matter in commissioning mode
    ldr  x0, [sp, #96]
    ADRL x1, Ls_k_DN
    ADRL x2, _g_lan_tmp
    mov  x3, #64
    bl   _txt_get
    cbz  x0, Ltk_mc_info
    mov  x1, x0
    add  x0, x22, #L_NAME
    mov  x2, #64
    bl   _strlcpy
Ltk_mc_info:
    ADRL x0, Ls_matter_open
    add  x1, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy_swap
    LEAVE 32

Ltk_cast:                             // friendly name and model
    ldr  x0, [sp, #96]
    ADRL x1, Ls_k_fn
    ADRL x2, _g_lan_tmp
    mov  x3, #64
    bl   _txt_get
    cbz  x0, Ltk_cast_md
    mov  x1, x0
    add  x0, x22, #L_NAME
    mov  x2, #64
    bl   _strlcpy
Ltk_cast_md:
    ldr  x0, [sp, #96]
    ADRL x1, Ls_k_md
    ADRL x2, _g_lan_tmp
    mov  x3, #64
    bl   _txt_get
    cbz  x0, Ltk_done
    mov  x1, x0
    add  x0, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy
    LEAVE 32

// void _lan_model(id txt) — L_INFO from md / model / ty / product (entry in x22)
_lan_model:
    ENTER 0
    mov  x19, x0
    ADRL x20, Lmodel_keys
Llm_loop:
    ldr  x1, [x20], #8
    cbz  x1, Llm_done
    mov  x0, x19
    ADRL x2, _g_lan_tmp
    mov  x3, #80
    bl   _txt_get
    cbz  x0, Llm_loop
    mov  x1, x0
    add  x0, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy
Llm_done:
    LEAVE 0

// long _lan_dev(kind, id, name, caps) — register; remember which device it is (entry x22)
_lan_dev:
    ENTER 0
    bl   _dev_add
    tbnz x0, #63, Lld_done
    str  x0, [x22, #L_DEV]
    mov  x19, x0
    bl   _ui_lists_changed
    mov  x0, x19
Lld_done:
    LEAVE 0

// const char *_nano_kc(long lan_index) -> "asmmesh.nanoleaf.<name>"
_nano_kc:
    ENTER 0
    LANE x9, x0
    add  x3, x9, #L_NAME
    ADRL x0, _g_lan_tmp
    mov  x1, #128
    ADRL x2, Lf_nano_kc
    bl   _sfmt
    ADRL x0, _g_lan_tmp
    LEAVE 0

// void _lan_refresh(void) — look again at everything already resolved
.globl _lan_refresh
_lan_refresh:
    ENTER 0
    mov  x19, #0
Llx_loop:
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Llx_done
    LANE x20, x19
    ldr  x9, [x20, #L_STATE]
    cbz  x9, Llx_next
    ldr  x9, [x20, #L_TYPE]
    cbz  x9, Llx_next                 // the Hue Bridge refreshes itself
    mov  x0, x19
    bl   _lan_take
Llx_next:
    add  x19, x19, #1
    b    Llx_loop
Llx_done:
    LEAVE 0

// ===========================================================================
// Responses
// ===========================================================================

// void _lan_response(const char *tag, id json, long status, NSError *err, NSData *raw)
.globl _lan_response
_lan_response:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    bl   _tag_num
    mov  x23, x0
    ldrb w24, [x19, #1]
    cmp  w24, #'c'
    b.eq Lrs_cmd
    cmp  w24, #'n'
    b.eq Lrs_nano
    cbnz x22, Lrs_done                // lookups that fail stay quiet
    cmp  x21, #300
    b.hs Lrs_done
    cmp  w24, #'w'
    b.eq Lrs_wled
    cmp  w24, #'e'
    b.eq Lrs_elgato
    cmp  w24, #'z'
    b.eq Lrs_shelly_info
    cmp  w24, #'y'
    b.eq Lrs_shelly_status
Lrs_done:
    LEAVE 32

Lrs_cmd:                              // a command: only failures are worth a line
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x23, x9
    b.hs Lrs_done
    ADRL x8, _g_devs
    add  x24, x8, x23, lsl #DEV_SHIFT
    cbnz x22, Lrs_cmd_net
    cmp  x21, #300
    b.lo Lrs_done
    add  x1, x24, #D_NAME
    ldr  x9, [x24, #D_KIND]
    cmp  x9, #K_NANOLEAF
    b.ne Lrs_cmd_http
    cmp  x21, #401
    b.ne Lrs_cmd_http
    strb wzr, [x24, #D_AUX]           // token no longer good
    ADRL x0, Ls_nano_401
    bl   _home_say
    LEAVE 32
Lrs_cmd_http:
    mov  x2, x21
    ADRL x0, Ls_cmd_http
    bl   _home_say
    LEAVE 32
Lrs_cmd_net:
    mov  x0, x22
    bl   _err_cstr
    mov  x2, x0
    add  x1, x24, #D_NAME
    ADRL x0, Ls_cmd_net
    bl   _home_say
    LEAVE 32

Lrs_wled:                             // {"on":true,"bri":128,...}
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x23, x9
    b.hs Lrs_done
    mov  x0, x20
    ADRL x1, Ls_j_on
    bl   _jget
    bl   _jint
    mov  x24, x0
    mov  x0, x20
    ADRL x1, Ls_j_bri
    bl   _jget
    bl   _jint
    mov  x9, #100
    mul  x0, x0, x9
    mov  x9, #255
    udiv x2, x0, x9
    mov  x1, x24
    mov  x0, x23
    bl   _dev_state
    LEAVE 32

Lrs_elgato:                           // accessory-info: displayName, productName
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x23, x9
    b.hs Lrs_done
    LANE x22, x23
    mov  x0, x20
    ADRL x1, Ls_j_productName
    bl   _jget
    bl   _jstr
    str  x0, [sp, #96]
    cbz  x0, Lre_name
    mov  x1, x0
    add  x0, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy
Lre_name:
    mov  x0, x20
    ADRL x1, Ls_j_displayName
    bl   _jget
    bl   _jstr
    cbz  x0, Lre_add
    ldrb w9, [x0]
    cbz  w9, Lre_add
    mov  x1, x0
    add  x0, x22, #L_NAME
    mov  x2, #64
    bl   _strlcpy
Lre_add:
    mov  x24, #(CAP_ON | CAP_LEVEL | CAP_CT)
    ldr  x0, [sp, #96]                // a Light Strip also does colour
    cbz  x0, Lre_reg
    ADRL x1, Ls_strip
    bl   _strstr
    cbz  x0, Lre_reg
    orr  x24, x24, #CAP_COLOR
Lre_reg:
    ADRL x0, _g_lan_tmp2
    mov  x1, #128
    ADRL x2, Lf_hostport
    add  x3, x22, #L_HOST
    ldr  x4, [x22, #L_PORT]
    bl   _sfmt
    mov  x0, #K_ELGATO
    ADRL x1, _g_lan_tmp2
    add  x2, x22, #L_NAME
    mov  x3, x24
    bl   _lan_dev
    LEAVE 32

Lrs_shelly_info:                      // Shelly.GetDeviceInfo: "name" (yours), "app" (model)
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x23, x9
    b.hs Lrs_done
    LANE x22, x23
    mov  x0, x20
    ADRL x1, Ls_j_app
    bl   _jget
    bl   _jstr
    cbz  x0, Lrsi_name
    mov  x1, x0
    add  x0, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy
Lrsi_name:
    mov  x0, x20
    ADRL x1, Ls_j_name
    bl   _jget
    bl   _jstr
    cbz  x0, Lrsi_status
    ldrb w9, [x0]
    cbz  w9, Lrsi_status
    mov  x1, x0
    add  x0, x22, #L_NAME
    mov  x2, #64
    bl   _strlcpy
Lrsi_status:
    mov  x0, #'y'
    mov  x1, x23
    bl   _lan_tag
    str  x0, [sp, #104]
    ADRL x0, _g_lan_tmp2
    mov  x1, #128
    ADRL x2, Lf_hostport
    add  x3, x22, #L_HOST
    ldr  x4, [x22, #L_PORT]
    bl   _sfmt
    ADRL x0, _g_lan_url
    mov  x1, #320
    ADRL x2, Lf_shelly_status
    ADRL x3, _g_lan_tmp2
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_lan_url
    mov  x2, #0
    mov  x3, #0
    ldr  x4, [sp, #104]
    bl   _http
    LEAVE 32

Lrs_shelly_status:                    // which component: switch:0, light:0, cover:0
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x23, x9
    b.hs Lrs_done
    LANE x22, x23
    mov  x0, x20
    ADRL x1, Ls_j_switch0
    bl   _jget
    mov  x24, #1
    mov  x3, #CAP_ON
    cbnz x0, Lrss_reg
    mov  x0, x20
    ADRL x1, Ls_j_light0
    bl   _jget
    mov  x24, #2
    mov  x3, #(CAP_ON | CAP_LEVEL)
    cbnz x0, Lrss_reg
    mov  x0, x20
    ADRL x1, Ls_j_cover0
    bl   _jget
    cbz  x0, Lrs_done                 // a sensor or something else: listed only
    mov  x24, #3
    MOVI x3, (CAP_SHADE | CAP_STATUS)
Lrss_reg:
    str  x3, [sp, #96]
    ADRL x0, _g_lan_tmp2
    mov  x1, #128
    ADRL x2, Lf_hostport
    add  x3, x22, #L_HOST
    ldr  x4, [x22, #L_PORT]
    bl   _sfmt
    mov  x0, #K_SHELLY
    ADRL x1, _g_lan_tmp2
    add  x2, x22, #L_NAME
    ldr  x3, [sp, #96]
    bl   _lan_dev
    tbnz x0, #63, Lrs_done
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    str  x24, [x8, #D_AUX]
    LEAVE 32

Lrs_nano:                             // {"auth_token":"..."} or 403 when not in pairing mode
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x23, x9
    b.hs Lrs_done
    cbz  x22, Lrn_answered
    mov  x0, x22
    bl   _err_cstr
    mov  x2, x0
    LANE x9, x23
    add  x1, x9, #L_NAME
    ADRL x0, Ls_cmd_net
    bl   _home_say
    LEAVE 32
Lrn_answered:
    LANE x22, x23
    add  x1, x22, #L_NAME
    cmp  x21, #403
    b.eq Lrn_notready
    cmp  x21, #200
    b.ne Lrn_fail
    mov  x0, x20
    ADRL x1, Ls_j_auth_token
    bl   _jget
    bl   _jstr
    cbz  x0, Lrn_fail0
    mov  x24, x0
    mov  x0, x23
    bl   _nano_kc
    mov  x1, x24
    bl   _kc_set
    ldr  x9, [x22, #L_DEV]
    tbnz x9, #63, Lrn_said
    ADRL x8, _g_devs
    add  x8, x8, x9, lsl #DEV_SHIFT
    add  x0, x8, #D_AUX
    mov  x1, x24
    mov  x2, #D_AUX_MAX
    bl   _strlcpy
Lrn_said:
    ADRL x0, Ls_nano_paired
    add  x1, x22, #L_INFO
    mov  x2, #80
    bl   _strlcpy_swap
    add  x1, x22, #L_NAME
    mov  x2, x1
    ADRL x0, Ls_nano_ok
    bl   _home_say
    LEAVE 32
Lrn_notready:
    ADRL x0, Ls_nano_403
    bl   _home_say
    LEAVE 32
Lrn_fail0:
    add  x1, x22, #L_NAME
Lrn_fail:
    mov  x2, x21
    ADRL x0, Ls_cmd_http
    bl   _home_say
    LEAVE 32

// ===========================================================================
// Control
// ===========================================================================

// void _lan_send(method, fmt, hostport, arg, body, dev_index) — http://... with tag "lc<idx>"
_lan_send:
    ENTER 32
    mov  x19, x0
    mov  x20, x4
    str  x5, [sp, #96]
    mov  x4, x3
    mov  x3, x2
    mov  x2, x1
    ADRL x0, _g_lan_url
    mov  x1, #320
    bl   _sfmt
    mov  x0, #'c'
    ldr  x1, [sp, #96]
    bl   _lan_tag
    mov  x4, x0
    mov  x0, x19
    ADRL x1, _g_lan_url
    mov  x2, x20
    mov  x3, #0
    bl   _http
    LEAVE 32

// long _rel_level(long idx, long action, long value) -> the level to set (for brighter/dimmer)
.globl _rel_level
_rel_level:
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    cmp  x1, #A_LEVEL
    b.ne Lrl_rel
    mov  x0, x2
    ret
Lrl_rel:
    ldr  x9, [x8, #D_LEVEL]
    tbz  x9, #63, Lrl_known
    mov  x9, #50
Lrl_known:
    cmp  x1, #A_BRIGHTER
    b.ne Lrl_down
    add  x9, x9, #20
    cmp  x9, #100
    mov  x10, #100
    csel x0, x10, x9, hi
    ret
Lrl_down:
    subs x9, x9, #20
    mov  x10, #1
    csel x0, x9, x10, gt
    ret

// long _mired(long kelvin, long lo, long hi) -> 1,000,000 / kelvin clamped
.globl _mired
_mired:
    mov  x9, #16960
    movk x9, #15, lsl #16
    cmp  x0, #0
    csinc x0, x0, xzr, ne
    udiv x9, x9, x0
    cmp  x9, x1
    csel x9, x1, x9, lo
    cmp  x9, x2
    csel x0, x2, x9, hi
    ret

// long _wled_set(long idx, long action, long value)
.globl _wled_set
_wled_set:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ADRL x2, Lw_on
    cmp  x20, #A_ON
    b.eq Lws_fixed
    ADRL x2, Lw_off
    cmp  x20, #A_OFF
    b.eq Lws_fixed
    ADRL x2, Lw_up
    cmp  x20, #A_BRIGHTER
    b.eq Lws_fixed
    ADRL x2, Lw_down
    cmp  x20, #A_DIMMER
    b.eq Lws_fixed
    cmp  x20, #A_LEVEL
    b.eq Lws_level
    cmp  x20, #A_COLOR
    b.eq Lws_color
    cmp  x20, #A_CT
    b.ne Lws_cant
    mov  x0, x21
    bl   _kelvin_to_rgb
    b    Lws_rgb
Lws_color:
    mov  x0, x21
    bl   _hue_to_rgb
Lws_rgb:
    lsr  x3, x0, #16
    ubfx x4, x0, #8, #8
    and  x5, x0, #0xff
    ADRL x0, _g_lan_body
    mov  x1, #320
    ADRL x2, Lw_rgb
    bl   _sfmt
    b    Lws_send
Lws_level:
    mov  x9, #255
    mul  x3, x21, x9
    mov  x9, #100
    udiv x3, x3, x9
    ADRL x0, _g_lan_body
    mov  x1, #320
    ADRL x2, Lw_bri
    bl   _sfmt
    b    Lws_send
Lws_fixed:
    ADRL x0, _g_lan_body
    mov  x1, x2
    mov  x2, #320
    bl   _strlcpy
Lws_send:
    ADRL x0, Ls_POST
    ADRL x1, Lf_wled_state
    add  x2, x22, #D_ID
    mov  x3, #0
    ADRL x4, _g_lan_body
    mov  x5, x19
    bl   _lan_send
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 16
Lws_cant:
    mov  x0, #0
    LEAVE 16

// void _believe(long idx, long action, long value) — record the likely new state
.globl _believe
_believe:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ldr  x1, [x22, #D_ON]
    ldr  x2, [x22, #D_LEVEL]
    cmp  x20, #A_OFF
    b.ne Lbv_on
    mov  x1, #0
    b    Lbv_set
Lbv_on:
    cmp  x20, #A_ON
    b.eq Lbv_on1
    cmp  x20, #A_COLOR
    b.eq Lbv_on1
    cmp  x20, #A_CT
    b.eq Lbv_on1
    cmp  x20, #A_LEVEL
    b.eq Lbv_level
    cmp  x20, #A_BRIGHTER
    b.eq Lbv_rel
    cmp  x20, #A_DIMMER
    b.ne Lbv_done
Lbv_rel:
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _rel_level
    mov  x2, x0
    mov  x1, #1
    b    Lbv_set
Lbv_level:
    mov  x2, x21
Lbv_on1:
    mov  x1, #1
Lbv_set:
    mov  x0, x19
    bl   _dev_state
Lbv_done:
    LEAVE 0

// long _elgato_set(long idx, long action, long value)
.globl _elgato_set
_elgato_set:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ADRL x2, Le_on
    cmp  x20, #A_ON
    b.eq Les_fixed
    ADRL x2, Le_off
    cmp  x20, #A_OFF
    b.eq Les_fixed
    cmp  x20, #A_LEVEL
    b.eq Les_level
    cmp  x20, #A_BRIGHTER
    b.eq Les_level
    cmp  x20, #A_DIMMER
    b.eq Les_level
    cmp  x20, #A_CT
    b.eq Les_ct
    cmp  x20, #A_COLOR
    b.ne Les_cant
    mov  x3, x21
    ADRL x2, Le_hue
    b    Les_fmt
Les_ct:                               // Elgato: 143..344 mired
    mov  x0, x21
    mov  x1, #143
    mov  x2, #344
    bl   _mired
    mov  x3, x0
    ADRL x2, Le_temp
    b    Les_fmt
Les_level:
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _rel_level
    mov  x21, x0
    mov  x20, #A_LEVEL
    mov  x3, x0
    ADRL x2, Le_bri
Les_fmt:
    ADRL x0, _g_lan_body
    mov  x1, #320
    bl   _sfmt
    b    Les_send
Les_fixed:
    ADRL x0, _g_lan_body
    mov  x1, x2
    mov  x2, #320
    bl   _strlcpy
Les_send:
    ADRL x0, Ls_PUT
    ADRL x1, Lf_elg_lights
    add  x2, x22, #D_ID
    mov  x3, #0
    ADRL x4, _g_lan_body
    mov  x5, x19
    bl   _lan_send
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 16
Les_cant:
    mov  x0, #0
    LEAVE 16

// long _shelly_set(long idx, long action, long value)
.globl _shelly_set
_shelly_set:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ldr  x9, [x22, #D_AUX]
    cmp  x9, #3
    b.eq Lys_cover
    cmp  x9, #2
    b.eq Lys_light
    // a relay
    ADRL x1, Ly_sw_on
    cmp  x20, #A_ON
    b.eq Lys_path
    ADRL x1, Ly_sw_off
    cmp  x20, #A_OFF
    b.eq Lys_path
    b    Lys_cant
Lys_light:
    ADRL x1, Ly_li_on
    cmp  x20, #A_ON
    b.eq Lys_path
    ADRL x1, Ly_li_off
    cmp  x20, #A_OFF
    b.eq Lys_path
    cmp  x20, #A_LEVEL
    b.eq Lys_li_level
    cmp  x20, #A_BRIGHTER
    b.eq Lys_li_level
    cmp  x20, #A_DIMMER
    b.ne Lys_cant
Lys_li_level:
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _rel_level
    mov  x21, x0
    mov  x20, #A_LEVEL
    mov  x3, x0
    ADRL x1, Ly_li_bri
    b    Lys_arg
Lys_cover:
    ADRL x1, Ly_co_open
    cmp  x20, #A_OPEN
    b.eq Lys_path
    ADRL x1, Ly_co_close
    cmp  x20, #A_CLOSE
    b.eq Lys_path
    cmp  x20, #A_LEVEL
    b.ne Lys_cant
    mov  x3, x21
    ADRL x1, Ly_co_pos
    b    Lys_arg
Lys_path:
    mov  x3, #0
Lys_arg:
    ADRL x0, Ls_GET
    add  x2, x22, #D_ID
    mov  x4, #0
    mov  x5, x19
    bl   _lan_send
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 16
Lys_cant:
    mov  x0, #0
    LEAVE 16

// long _nano_set(long idx, long action, long value)
.globl _nano_set
_nano_set:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    add  x9, x22, #D_AUX
    ldrb w9, [x9]
    cbz  w9, Lns_unpaired
    ADRL x2, Ln_on
    cmp  x20, #A_ON
    b.eq Lns_fixed
    ADRL x2, Ln_off
    cmp  x20, #A_OFF
    b.eq Lns_fixed
    ADRL x2, Ln_up
    cmp  x20, #A_BRIGHTER
    b.eq Lns_fixed
    ADRL x2, Ln_down
    cmp  x20, #A_DIMMER
    b.eq Lns_fixed
    mov  x3, x21
    ADRL x2, Ln_bri
    cmp  x20, #A_LEVEL
    b.eq Lns_fmt
    ADRL x2, Ln_hue
    cmp  x20, #A_COLOR
    b.eq Lns_fmt
    cmp  x20, #A_CT
    b.ne Lns_cant
    mov  x9, #1200                    // Nanoleaf: 1200..6500 K
    cmp  x3, x9
    csel x3, x9, x3, lo
    mov  x9, #6500
    cmp  x3, x9
    csel x3, x9, x3, hi
    ADRL x2, Ln_ct
Lns_fmt:
    ADRL x0, _g_lan_body
    mov  x1, #320
    bl   _sfmt
    b    Lns_send
Lns_fixed:
    ADRL x0, _g_lan_body
    mov  x1, x2
    mov  x2, #320
    bl   _strlcpy
Lns_send:
    ADRL x0, Ls_PUT
    ADRL x1, Lf_nano_state
    add  x2, x22, #D_ID
    add  x3, x22, #D_AUX
    ADRL x4, _g_lan_body
    mov  x5, x19
    bl   _lan_send
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 32
Lns_cant:
    mov  x0, #0
    LEAVE 32
Lns_unpaired:
    add  x1, x22, #D_NAME
    ADRL x0, Ls_nano_need
    bl   _home_say
    mov  x0, #2
    LEAVE 32

// void _nano_pair(void) — ask every Nanoleaf for a token (it must be in pairing mode)
.globl _nano_pair
_nano_pair:
    ENTER 16
    mov  x19, #0
    mov  x20, #0                      // asked
Lnp_loop:
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lnp_done
    LANE x21, x19
    ldr  x9, [x21, #L_TYPE]
    cmp  x9, #4                       // _nanoleafapi._tcp
    b.ne Lnp_next
    ldr  x9, [x21, #L_STATE]
    cbz  x9, Lnp_next
    mov  x0, #'n'
    mov  x1, x19
    bl   _lan_tag
    str  x0, [sp, #96]
    ADRL x0, _g_lan_tmp2
    mov  x1, #128
    ADRL x2, Lf_hostport
    add  x3, x21, #L_HOST
    ldr  x4, [x21, #L_PORT]
    bl   _sfmt
    ADRL x0, _g_lan_url
    mov  x1, #320
    ADRL x2, Lf_nano_new
    ADRL x3, _g_lan_tmp2
    bl   _sfmt
    ADRL x0, Ls_POST
    ADRL x1, _g_lan_url
    mov  x2, #0
    mov  x3, #0
    ldr  x4, [sp, #96]
    bl   _http
    add  x20, x20, #1
Lnp_next:
    add  x19, x19, #1
    b    Lnp_loop
Lnp_done:
    ADRL x0, Ls_nano_asking
    cbnz x20, Lnp_say
    ADRL x0, Ls_nano_none
Lnp_say:
    bl   _home_say0
    LEAVE 16

// long _lan_set_up(long i) — the scanner's Set Up button for a network entry.
//   -> 1 if something was started
.globl _lan_set_up
_lan_set_up:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_lan_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lsu_no
    LANE x20, x19
    ldr  x9, [x20, #L_TYPE]
    ADRL x10, Ltypes
    mov  x11, #24
    madd x10, x9, x11, x10
    ldr  x9, [x10, #16]
    cmp  x9, #H_HUE
    b.eq Lsu_hue
    cmp  x9, #H_NANO
    b.eq Lsu_nano
    cmp  x9, #H_HA
    b.eq Lsu_ha
    cmp  x9, #H_HAP
    b.eq Lsu_home
    cmp  x9, #H_MATTERC
    b.eq Lsu_home
    ldr  x9, [x20, #L_TYPE]
    cmp  x9, #8                       // _matter._tcp
    b.eq Lsu_home
Lsu_no:
    mov  x0, #0
    LEAVE 0
Lsu_hue:
    bl   _hue_pair
    mov  x0, #1
    LEAVE 0
Lsu_nano:
    bl   _nano_pair
    mov  x0, #1
    LEAVE 0
Lsu_ha:
    bl   _ha_connect_dialog
    mov  x0, #1
    LEAVE 0
Lsu_home:                             // HomeKit and Matter pair in the Home app
    bl   _open_home_app
    mov  x0, #1
    LEAVE 0

// void _open_home_app(void)
.globl _open_home_app
_open_home_app:
    ENTER 0
    CLS  Ls_NSWorkspace
    MSG0 Ls_sharedWorkspace
    mov  x19, x0
    ADRL x0, Ls_home_app
    bl   _nsstr
    mov  x20, x0
    CLS  Ls_NSURL
    mov  x2, x20
    MSG1 Ls_fileURLWithPath
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_openURL
    ADRL x0, Ls_home_hint
    bl   _scan_say
    LEAVE 0

// void _open_url(const char *url) — in the default browser (or whichever app owns it)
.globl _open_url
_open_url:
    ENTER 0
    bl   _nsstr
    mov  x20, x0
    CLS  Ls_NSURL
    mov  x2, x20
    MSG1 Ls_URLWithString
    cbz  x0, Lou_done
    mov  x19, x0
    CLS  Ls_NSWorkspace
    MSG0 Ls_sharedWorkspace
    mov  x2, x19
    MSG1 Ls_openURL
Lou_done:
    LEAVE 0

// void _lan_open_web(long i) — its web page, for things that have one
.globl _lan_open_web
_lan_open_web:
    ENTER 0
    LANE x19, x0
    ADRL x0, _g_lan_url
    mov  x1, #320
    ADRL x2, Lf_web
    add  x3, x19, #L_HOST
    ldr  x4, [x19, #L_PORT]
    bl   _sfmt
    ADRL x0, _g_lan_url
    bl   _open_url
    LEAVE 0

// char *_lan_cell(long i, char column, char *buf) — n name, k kind, s signal, l where, d details
.globl _lan_cell
_lan_cell:
    ENTER 0
    mov  x20, x2
    LANE x19, x0
    strb wzr, [x20]
    cmp  w1, #'n'
    b.eq Llc_name
    cmp  w1, #'k'
    b.eq Llc_kind
    cmp  w1, #'s'
    b.eq Llc_sig
    cmp  w1, #'l'
    b.eq Llc_where
    add  x1, x19, #L_INFO
    b    Llc_copy
Llc_name:
    add  x1, x19, #L_NAME
    b    Llc_copy
Llc_kind:
    ldr  x9, [x19, #L_TYPE]
    ADRL x10, Ltypes
    mov  x11, #24
    madd x10, x9, x11, x10
    ldr  x1, [x10, #8]
    b    Llc_copy
Llc_sig:
    ADRL x1, Ls_wifi
    b    Llc_copy
Llc_where:
    add  x1, x19, #L_HOST
Llc_copy:
    mov  x0, x20
    mov  x2, #120
    bl   _strlcpy
    mov  x0, x20
    LEAVE 0

// char *_lan_details(long i, char *buf, size_t max)
.globl _lan_details
_lan_details:
    ENTER 16
    mov  x20, x1
    mov  x21, x2
    mov  x22, x0
    LANE x19, x0
    ldr  x9, [x19, #L_TYPE]
    ADRL x10, Ltypes
    mov  x11, #24
    madd x10, x9, x11, x10
    ldr  x4, [x10, #8]                // kind
    ldr  x9, [x10, #16]
    str  x9, [sp, #96]
    add  x3, x19, #L_NAME
    add  x5, x19, #L_HOST
    ldr  x6, [x19, #L_PORT]
    add  x7, x19, #L_INFO
    mov  x0, x20
    mov  x1, x21
    ADRL x2, Lf_lan_details
    bl   _sfmt
    ldr  x9, [sp, #96]                // what Set Up does here
    cmp  x9, #H_HUE
    b.eq Lldt_hue
    cmp  x9, #H_HAP
    b.eq Lldt_hap
    ADRL x1, Ls_hint_nano
    cmp  x9, #H_NANO
    b.eq Lldt_hint
    ADRL x1, Ls_hint_ha
    cmp  x9, #H_HA
    b.eq Lldt_hint
    ADRL x1, Ls_hint_home
    cmp  x9, #H_HAP
    b.eq Lldt_hint
    cmp  x9, #H_MATTERC
    b.eq Lldt_hint
    ADRL x1, Ls_hint_web
    cmp  x9, #H_WLED
    b.eq Lldt_hint
    cmp  x9, #H_SHELLY
    b.eq Lldt_hint
    ldr  x9, [x19, #L_TYPE]
    cmp  x9, #14                      // ESPHome
    b.eq Lldt_hint
    cmp  x9, #13                      // printer
    b.eq Lldt_hint
    ADRL x1, Ls_hint_ctl
    cmp  x9, #2
    b.eq Lldt_hint
    b    Lldt_done
    b    Lldt_done
Lldt_hue:
    bl   _hue_paired
    ADRL x1, Ls_hint_hue
    cbz  x0, Lldt_hint
    ADRL x1, Ls_hint_hue_ok
    b    Lldt_hint
Lldt_hap:                             // only an unpaired accessory can be added
    add  x0, x19, #L_INFO
    ADRL x1, Ls_not_paired
    bl   _strstr
    ADRL x1, Ls_hint_home
    cbnz x0, Lldt_hint
    ADRL x1, Ls_hint_hap_ok
Lldt_hint:
    mov  x0, x20
    mov  x2, x21
    bl   _strlcat
Lldt_done:
    mov  x0, x20
    LEAVE 16

// long _lan_has_web(long i) -> 1 for WLED, Shelly, ESPHome, printers
.globl _lan_has_web
_lan_has_web:
    LANE x9, x0
    ldr  x9, [x9, #L_TYPE]
    mov  x0, #1
    cmp  x9, #1
    b.eq Lhw_ret
    cmp  x9, #3
    b.eq Lhw_ret
    cmp  x9, #13
    b.eq Lhw_ret
    cmp  x9, #14
    b.eq Lhw_ret
    mov  x0, #0
Lhw_ret:
    ret

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_NSNetServiceBrowser: .asciz "NSNetServiceBrowser"
Ls_NSNetService:      .asciz "NSNetService"
Ls_NSWorkspace:       .asciz "NSWorkspace"
Ls_NSURL:             .asciz "NSURL"
Ls_new:               .asciz "new"
Ls_retain:            .asciz "retain"
Ls_setDelegate:       .asciz "setDelegate:"
Ls_searchForServices: .asciz "searchForServicesOfType:inDomain:"
Ls_resolveWithTimeout: .asciz "resolveWithTimeout:"
Ls_type:              .asciz "type"
Ls_name:              .asciz "name"
Ls_hostName:          .asciz "hostName"
Ls_port:              .asciz "port"
Ls_TXTRecordData:     .asciz "TXTRecordData"
Ls_dictFromTXT:       .asciz "dictionaryFromTXTRecordData:"
Ls_objectForKey:      .asciz "objectForKey:"
Ls_length:            .asciz "length"
Ls_bytes:             .asciz "bytes"
Ls_UTF8String:        .asciz "UTF8String"
Ls_sharedWorkspace:   .asciz "sharedWorkspace"
Ls_fileURLWithPath:   .asciz "fileURLWithPath:"
Ls_openURL:           .asciz "openURL:"
Ls_local:             .asciz "local."
Ls_GET:               .asciz "GET"
Ls_PUT:               .asciz "PUT"
Ls_POST:              .asciz "POST"
Lf_tag:               .asciz "l%c%ld"
Lf_hostport:          .asciz "%s:%ld"
Ls_dot:               .asciz " \302\267 "
Ls_home_app:          .asciz "/System/Applications/Home.app"
Lf_web:               .asciz "http://%s:%ld/"
Ls_wifi:              .asciz "Wi-Fi"
Ls_URLWithString:     .asciz "URLWithString:"
Lf_lan_details:       .asciz "%s \342\200\224 %s at %s port %ld\n%s\n"
Ls_hint_hue:          .asciz "Set Up: press the round button on the bridge first, then Set Up pairs it."
Ls_hint_nano:         .asciz "Set Up: hold the Nanoleaf's power button 5\342\200\2237 seconds until it flashes, then Set Up."
Ls_hint_ha:           .asciz "Set Up connects Home Assistant with a long-lived token."
Ls_hint_hue_ok:       .asciz "Paired: asmmesh controls its lights and rooms (say \342\200\234devices\342\200\235)."
Ls_hint_hap_ok:       .asciz "Already paired with a home. To control it from asmmesh, make a Shortcut for it in the Shortcuts app and say its name."
Ls_not_paired:        .asciz "not paired"
Ls_hint_home:         .asciz "Set Up opens the Home app to add it (scan its setup code)."
Ls_hint_web:          .asciz "Set Up opens its own web page."
Ls_hint_ctl:          .asciz "asmmesh controls it directly: try \342\200\234desk light 50%\342\200\235."
Ls_home_hint:         .asciz "\302\267 Opened the Home app: choose + \342\200\272 Add Accessory and scan the code on the device (or its box). Once it's in Home, make a Shortcut for it and asmmesh can run it by name."

Lt_hue:       .asciz "_hue._tcp."
Lt_wled:      .asciz "_wled._tcp."
Lt_elg:       .asciz "_elg._tcp."
Lt_shelly:    .asciz "_shelly._tcp."
Lt_nano:      .asciz "_nanoleafapi._tcp."
Lt_ha:        .asciz "_home-assistant._tcp."
Lt_hap:       .asciz "_hap._tcp."
Lt_matterc:   .asciz "_matterc._udp."
Lt_matter:    .asciz "_matter._tcp."
Lt_cast:      .asciz "_googlecast._tcp."
Lt_airplay:   .asciz "_airplay._tcp."
Lt_sonos:     .asciz "_sonos._tcp."
Lt_spotify:   .asciz "_spotify-connect._tcp."
Lt_ipp:       .asciz "_ipp._tcp."
Lt_esphome:   .asciz "_esphomelib._tcp."
Lt_ewelink:   .asciz "_ewelink._tcp."
Lt_companion: .asciz "_companion-link._tcp."
Lt_firetv:    .asciz "_amzn-wplay._tcp."
Lt_atv:       .asciz "_androidtvremote2._tcp."
Lt_miio:      .asciz "_miio._udp."
Lk_hue:       .asciz "Hue Bridge"
Lk_wled:      .asciz "WLED"
Lk_elg:       .asciz "Elgato"
Lk_shelly:    .asciz "Shelly"
Lk_nano:      .asciz "Nanoleaf"
Lk_ha:        .asciz "Home Assistant"
Lk_hap:       .asciz "HomeKit"
Lk_matterc:   .asciz "Matter (pairing)"
Lk_matter:    .asciz "Matter"
Lk_cast:      .asciz "Google Cast"
Lk_airplay:   .asciz "AirPlay"
Lk_sonos:     .asciz "Sonos"
Lk_spotify:   .asciz "Spotify Connect"
Lk_ipp:       .asciz "Printer"
Lk_esphome:   .asciz "ESPHome"
Lk_ewelink:   .asciz "Sonoff"
Lk_companion: .asciz "Apple device"
Lk_firetv:    .asciz "Fire TV"
Lk_atv:       .asciz "Google TV"
Lk_miio:      .asciz "Xiaomi"

Lci_other:      .asciz "accessory"
Lci_bridge:     .asciz "bridge"
Lci_fan:        .asciz "fan"
Lci_garage:     .asciz "garage door"
Lci_bulb:       .asciz "light"
Lci_lock:       .asciz "lock"
Lci_outlet:     .asciz "outlet"
Lci_switch:     .asciz "switch"
Lci_thermo:     .asciz "thermostat"
Lci_sensor:     .asciz "sensor"
Lci_security:   .asciz "security system"
Lci_door:       .asciz "door"
Lci_window:     .asciz "window"
Lci_blinds:     .asciz "blinds"
Lci_button:     .asciz "button"
Lci_camera:     .asciz "camera"
Lci_purifier:   .asciz "air purifier"
Lci_heater:     .asciz "heater"
Lci_ac:         .asciz "air conditioner"
Lci_humidifier: .asciz "humidifier"
Lci_speaker:    .asciz "speaker"
Lci_sprinkler:  .asciz "sprinkler"
Lci_faucet:     .asciz "faucet"
Lci_tv:         .asciz "TV"
Lci_remote:     .asciz "remote"
Lci_router:     .asciz "router"
Ls_k_ci:        .asciz "ci"
Ls_k_md:        .asciz "md"
Ls_k_sf:        .asciz "sf"
Ls_k_DN:        .asciz "DN"
Ls_k_fn:        .asciz "fn"
Ls_k_model:     .asciz "model"
Ls_k_ty:        .asciz "ty"
Ls_k_product:   .asciz "product"
Ls_hap_ready:   .asciz " \302\267 not paired: ready to add in Home"
Ls_hap_paired:  .asciz " \302\267 paired"
Ls_matter_open: .asciz "pairing window open: add it in Home or your hub"
Ls_hue_info:    .asciz "say \342\200\234pair hue\342\200\235 after pressing its button"
Ls_wled_info:   .asciz "controlled by asmmesh"
Ls_ha_info:     .asciz "say \342\200\234connect home assistant\342\200\235"
Ls_nano_paired: .asciz "paired \302\267 controlled by asmmesh"
Ls_nano_unpaired: .asciz "not paired: hold power 5\342\200\2237 s, then Set Up"

Lf_wled_state:  .asciz "http://%s/json/state"
Lf_elg_info:    .asciz "http://%s/elgato/accessory-info"
Lf_elg_lights:  .asciz "http://%s/elgato/lights"
Lf_shelly_info: .asciz "http://%s/rpc/Shelly.GetDeviceInfo"
Lf_shelly_status: .asciz "http://%s/rpc/Shelly.GetStatus"
Lf_nano_new:    .asciz "http://%s/api/v1/new"
Lf_nano_state:  .asciz "http://%s/api/v1/%s/state"
Lf_nano_kc:     .asciz "asmmesh.nanoleaf.%s"
Lf_ha_url:      .asciz "http://%s"
Ly_sw_on:       .asciz "http://%s/rpc/Switch.Set?id=0&on=true"
Ly_sw_off:      .asciz "http://%s/rpc/Switch.Set?id=0&on=false"
Ly_li_on:       .asciz "http://%s/rpc/Light.Set?id=0&on=true"
Ly_li_off:      .asciz "http://%s/rpc/Light.Set?id=0&on=false"
Ly_li_bri:      .asciz "http://%s/rpc/Light.Set?id=0&on=true&brightness=%ld"
Ly_co_open:     .asciz "http://%s/rpc/Cover.Open?id=0"
Ly_co_close:    .asciz "http://%s/rpc/Cover.Close?id=0"
Ly_co_pos:      .asciz "http://%s/rpc/Cover.GoToPosition?id=0&pos=%ld"
Lw_on:          .asciz "{\"on\":true}"
Lw_off:         .asciz "{\"on\":false}"
Lw_up:          .asciz "{\"on\":true,\"bri\":\"~40\"}"
Lw_down:        .asciz "{\"bri\":\"~-40\"}"
Lw_bri:         .asciz "{\"on\":true,\"bri\":%ld}"
Lw_rgb:         .asciz "{\"on\":true,\"seg\":[{\"col\":[[%ld,%ld,%ld]]}]}"
Le_on:          .asciz "{\"numberOfLights\":1,\"lights\":[{\"on\":1}]}"
Le_off:         .asciz "{\"numberOfLights\":1,\"lights\":[{\"on\":0}]}"
Le_bri:         .asciz "{\"numberOfLights\":1,\"lights\":[{\"on\":1,\"brightness\":%ld}]}"
Le_temp:        .asciz "{\"numberOfLights\":1,\"lights\":[{\"on\":1,\"temperature\":%ld}]}"
Le_hue:         .asciz "{\"numberOfLights\":1,\"lights\":[{\"on\":1,\"hue\":%ld,\"saturation\":100}]}"
Ln_on:          .asciz "{\"on\":{\"value\":true}}"
Ln_off:         .asciz "{\"on\":{\"value\":false}}"
Ln_up:          .asciz "{\"on\":{\"value\":true},\"brightness\":{\"increment\":20}}"
Ln_down:        .asciz "{\"brightness\":{\"increment\":-20}}"
Ln_bri:         .asciz "{\"on\":{\"value\":true},\"brightness\":{\"value\":%ld}}"
Ln_hue:         .asciz "{\"on\":{\"value\":true},\"hue\":{\"value\":%ld},\"sat\":{\"value\":100}}"
Ln_ct:          .asciz "{\"on\":{\"value\":true},\"ct\":{\"value\":%ld}}"

Ls_j_on:        .asciz "on"
Ls_j_bri:       .asciz "bri"
Ls_j_productName: .asciz "productName"
Ls_j_displayName: .asciz "displayName"
Ls_j_app:       .asciz "app"
Ls_j_name:      .asciz "name"
Ls_j_switch0:   .asciz "switch:0"
Ls_j_light0:    .asciz "light:0"
Ls_j_cover0:    .asciz "cover:0"
Ls_j_auth_token: .asciz "auth_token"
Ls_strip:       .asciz "Strip"

Ls_ha_found:    .asciz "\302\267 Found Home Assistant at %s. Say \342\200\234connect home assistant\342\200\235 to use everything in it."
Ls_nano_found:  .asciz "\302\267 Found Nanoleaf \342\200\234%s\342\200\235. To connect it, hold its power button for 5\342\200\2237 seconds until the lights flash, then say \342\200\234pair nanoleaf\342\200\235."
Ls_nano_need:   .asciz "\302\267 %s isn't paired yet: hold its power button for 5\342\200\2237 seconds until the lights flash, then say \342\200\234pair nanoleaf\342\200\235."
Ls_nano_asking: .asciz "\302\267 Asking your Nanoleaf for access\342\200\246"
Ls_nano_none:   .asciz "\302\267 No Nanoleaf has shown up on this network yet."
Ls_nano_ok:     .asciz "\302\267 Nanoleaf \342\200\234%s\342\200\235 paired. Try \342\200\234%s blue\342\200\235."
Ls_nano_403:    .asciz "\302\267 Nanoleaf \342\200\234%s\342\200\235 isn't in pairing mode. Hold its power button for 5\342\200\2237 seconds until the lights flash, then say \342\200\234pair nanoleaf\342\200\235 within 30 seconds."
Ls_nano_401:    .asciz "\302\267 %s no longer accepts asmmesh's token. Hold its power button for 5\342\200\2237 seconds, then say \342\200\234pair nanoleaf\342\200\235."
Ls_cmd_http:    .asciz "\302\267 %s refused that (HTTP %ld)."
Ls_cmd_net:     .asciz "\302\267 %s didn't answer: %s"

.section __DATA,__const
.p2align 3
Lmodel_keys:
    .quad Ls_k_md, Ls_k_model, Ls_k_ty, Ls_k_product, 0
