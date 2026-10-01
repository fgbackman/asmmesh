// cloud.s — services reached with a key you paste once (kept in the Keychain):
//
//   LIFX            api.lifx.com/v1                       "connect lifx"
//   Govee           openapi.api.govee.com/router/api/v1   "connect govee"
//   Home Assistant  <your server>/api (long-lived token)   "connect home assistant"
//
// Home Assistant brings in whatever it already controls: lights, switches,
// fans, blinds and garage doors, locks, thermostats, TVs and speakers,
// vacuums, valves, temperature sensors, scenes and scripts.

.include "macros.inc"

.data
.p2align 3
.globl _g_ha_url
.zerofill __DATA,__bss,_g_ha_url,160,4
.zerofill __DATA,__bss,_g_ha_token,320,4
.zerofill __DATA,__bss,_g_ha_auth,340,4
.zerofill __DATA,__bss,_g_lifx_token,160,4
.zerofill __DATA,__bss,_g_lifx_auth,180,4
.zerofill __DATA,__bss,_g_govee_key,128,4
.zerofill __DATA,__bss,_g_cl_url,400,4
.zerofill __DATA,__bss,_g_cl_body,512,4
.zerofill __DATA,__bss,_g_cl_tag,32,4
.zerofill __DATA,__bss,_g_cl_tmp,160,4
.zerofill __DATA,__bss,_g_cl_val,64,4
.zerofill __DATA,__bss,_g_cl_line,480,4
.zerofill __DATA,__bss,_g_cl_dom,32,4

.section __TEXT,__const
.p2align 3
Lf_field:     .double 0.0, 0.0, 340.0, 24.0

.section __DATA,__const
.p2align 3
// Home Assistant domains: domain, capabilities
Lha_domains:
    .quad Ld_light,      CAP_ON
    .quad Ld_switch,     CAP_ON
    .quad Ld_input_bool, CAP_ON
    .quad Ld_fan,        (CAP_ON | CAP_FAN | CAP_LEVEL)
    .quad Ld_cover,      (CAP_SHADE | CAP_STATUS)
    .quad Ld_lock,       (CAP_LOCK | CAP_STATUS)
    .quad Ld_climate,    (CAP_THERMO | CAP_TEMP | CAP_STATUS)
    .quad Ld_media,      (CAP_ON | CAP_VOLUME | CAP_MUTE | CAP_MEDIA | CAP_STATUS)
    .quad Ld_vacuum,     (CAP_VACUUM | CAP_STATUS)
    .quad Ld_scene,      CAP_RUN
    .quad Ld_script,     CAP_RUN
    .quad Ld_valve,      (CAP_VALVE | CAP_STATUS)
    .quad Ld_humidifier, CAP_ON
    .quad Ld_sensor,     0            // temperature and humidity only (below)
    .quad 0, 0

// per action: service, extra JSON format, argument kind
//   kind 0 none  1 the number  2 a string made in the code  3 a fraction (0.NN)
Lha_acts:
    .quad 0, 0, 0                                 // NONE
    .quad Lsv_turn_on, Ls_empty, 0                // ON
    .quad Lsv_turn_off, Ls_empty, 0               // OFF
    .quad Lsv_turn_on, Lx_bri_pct, 1              // LEVEL (light; others below)
    .quad Lsv_turn_on, Lx_hs, 1                   // COLOR
    .quad Lsv_turn_on, Lx_kelvin, 1               // CT
    .quad Lsv_lock, Ls_empty, 0                   // LOCK
    .quad Lsv_unlock, Ls_empty, 0                 // UNLOCK
    .quad Lsv_turn_on, Ls_empty, 0                // RUN
    .quad 0, 0, 0                                 // LIST
    .quad 0, 0, 0                                 // HELP
    .quad 0, 0, 0                                 // PAIR
    .quad 0, 0, 0                                 // REFRESH
    .quad Lsv_turn_on, Lx_step_up, 0              // BRIGHTER
    .quad Lsv_turn_on, Lx_step_down, 0            // DIMMER
    .quad 0, 0, 0                                 // CONNECT
    .quad Lsv_volume_set, Lx_volume, 3            // VOLUME
    .quad Lsv_volume_up, Ls_empty, 0              // VOLUP
    .quad Lsv_volume_down, Ls_empty, 0            // VOLDOWN
    .quad Lsv_volume_mute, Lx_muted, 0            // MUTE
    .quad Lsv_volume_mute, Lx_unmuted, 0          // UNMUTE
    .quad 0, 0, 0                                 // CHANNEL
    .quad Lsv_next, Ls_empty, 0                   // CHUP
    .quad Lsv_previous, Ls_empty, 0               // CHDOWN
    .quad Lsv_select_source, Lx_source, 2         // INPUT
    .quad Lsv_play, Ls_empty, 0                   // PLAY
    .quad Lsv_pause, Ls_empty, 0                  // PAUSE
    .quad Lsv_stop, Ls_empty, 0                   // STOP
    .quad Lsv_next, Ls_empty, 0                   // FFWD
    .quad Lsv_previous, Ls_empty, 0               // REWIND
    .quad Lsv_select_source, Lx_source, 2         // APP
    .quad Lsv_open_cover, Ls_empty, 0             // OPEN
    .quad Lsv_close_cover, Ls_empty, 0            // CLOSE
    .quad Lsv_set_temp, Lx_heat, 1                // HEATSET
    .quad Lsv_set_temp, Lx_cool, 1                // COOLSET
    .quad Lsv_set_temp, Lx_temp, 1                // TEMPSET
    .quad Lsv_set_hvac, Lx_hvac, 2                // TMODE
    .quad Lsv_set_pct, Lx_pct, 1                  // FANSPEED
    .quad Lsv_start, Ls_empty, 0                  // VACSTART
    .quad Lsv_return, Ls_empty, 0                 // VACHOME
    .quad 0, 0, 0                                 // STATUS
    .quad 0, 0, 0                                 // KEY

// status: attribute, text before, text after, kind (0 as is, 1 0..255 -> %, 2 0..1 -> %)
Lha_report:
    .quad Lj_current_temp, Ls_now, Ls_deg, 0
    .quad Lj_temperature, Ls_set_to, Ls_deg, 0
    .quad Lj_hvac_action, Ls_empty, Ls_empty, 0
    .quad Lj_brightness, Ls_empty, Ls_pct, 1
    .quad Lj_position, Ls_empty, Ls_pct_open, 0
    .quad Lj_volume_level, Ls_volume_sp, Ls_pct, 2
    .quad Lj_source, Ls_empty, Ls_empty, 0
    .quad Lj_media_title, Ls_playing, Ls_empty, 0
    .quad Lj_battery_level, Ls_empty, Ls_pct_bat, 0
    .quad Lj_humidity, Ls_empty, Ls_pct_hum, 0
    .quad Lj_percentage, Ls_fan_sp, Ls_pct, 0
    .quad 0, 0, 0, 0

.text
.p2align 2

// ===========================================================================
// Setup
// ===========================================================================

// long _ask_text(title, info, placeholder, prefill, secure, out, max) -> length, 0 if cancelled
.globl _ask_text
_ask_text:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x5
    str  x6, [sp, #96]
    ADRL x0, Ls_NSTextField
    cbz  x4, Lat_cls
    ADRL x0, Ls_NSSecureTextField
Lat_cls:
    str  x4, [sp, #104]
    bl   _objc_getClass
    MSG0 Ls_alloc
    mov  x24, x0
    SELX1 Ls_initWithFrame
    mov  x0, x24
    ADRL x8, Lf_field
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x24, x0
    mov  x0, x21
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_setPlaceholderString
    cbz  x22, Lat_run
    ldrb w9, [x22]
    cbz  w9, Lat_run
    mov  x0, x22
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_setStringValue
Lat_run:
    mov  x0, x19
    mov  x1, x20
    ADRL x2, Ls_connect
    mov  x3, x24
    ADRL x4, Ls_cancel
    bl   _alert_run
    mov  x19, #0
    cbz  x0, Lat_release
    mov  x0, x24
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, Lat_release
    mov  x1, x0
    ldr  x9, [sp, #104]
    ldr  x2, [sp, #96]
    sub  x2, x2, #1
    mov  x0, x23
    cbz  x9, Lat_plain
    bl   _token_clean
    mov  x19, x0
    b    Lat_release
Lat_plain:
    bl   _text_copy_trim
    mov  x19, x0
Lat_release:
    mov  x0, x24
    MSG0 Ls_release
    mov  x0, x19
    LEAVE 16

// void _cloud_make_auth(void)
_cloud_make_auth:
    ENTER 0
    ADRL x0, _g_lifx_auth
    mov  x1, #180
    ADRL x2, Lf_bearer
    ADRL x3, _g_lifx_token
    bl   _sfmt
    ADRL x0, _g_ha_auth
    mov  x1, #340
    ADRL x2, Lf_bearer
    ADRL x3, _g_ha_token
    bl   _sfmt
    LEAVE 0

// void _cloud_kc_read(void) — saved keys (any thread: the Keychain may ask first)
.globl _cloud_kc_read
_cloud_kc_read:
    ENTER 0
    ADRL x0, Ls_kc_lifx
    ADRL x1, _g_lifx_token
    mov  x2, #160
    bl   _kc_get
    ADRL x0, Ls_kc_govee
    ADRL x1, _g_govee_key
    mov  x2, #128
    bl   _kc_get
    ADRL x0, Ls_kc_ha
    ADRL x1, _g_ha_token
    mov  x2, #320
    bl   _kc_get
    ADRL x0, Ls_pref_ha
    ADRL x1, _g_ha_url
    mov  x2, #160
    bl   _pref_get
    LEAVE 0

// void _cloud_init(void) — main thread, after _cloud_kc_read
.globl _cloud_init
_cloud_init:
    ENTER 0
    ADRL x8, _g_ha_token              // no token: the address alone isn't a connection
    ldrb w9, [x8]
    cbnz w9, Lci_auth
    ADRL x8, _g_ha_url
    strb wzr, [x8]
Lci_auth:
    bl   _cloud_make_auth
    bl   _cloud_load
    LEAVE 0

// void _cloud_load(void) — ask each connected service for its devices
.globl _cloud_load
_cloud_load:
    ENTER 0
    bl   _lifx_load
    bl   _govee_load
    bl   _ha_load
    LEAVE 0

_lifx_load:
    ENTER 0
    ADRL x8, _g_lifx_token
    ldrb w9, [x8]
    cbz  w9, Lll_done
    ADRL x0, Ls_GET
    ADRL x1, Ls_lifx_all
    mov  x2, #0
    ADRL x3, _g_lifx_auth
    ADRL x4, Ls_tag_lifx
    bl   _http
Lll_done:
    LEAVE 0

_govee_load:
    ENTER 0
    ADRL x8, _g_govee_key
    ldrb w9, [x8]
    cbz  w9, Lgl_done
    ADRL x0, Ls_GET
    ADRL x1, Ls_govee_devices
    mov  x2, #0
    mov  x3, #0
    ADRL x4, Ls_tag_govee
    ADRL x5, Ls_govee_header
    ADRL x6, _g_govee_key
    bl   _http2
Lgl_done:
    LEAVE 0

_ha_load:
    ENTER 0
    ADRL x8, _g_ha_url
    ldrb w9, [x8]
    cbz  w9, Lhl_done
    ADRL x0, _g_cl_url
    mov  x1, #400
    ADRL x2, Lf_ha_states
    ADRL x3, _g_ha_url
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_cl_url
    mov  x2, #0
    ADRL x3, _g_ha_auth
    ADRL x4, Ls_tag_ha
    bl   _http
Lhl_done:
    LEAVE 0

.globl _lifx_connect_dialog
_lifx_connect_dialog:
    ENTER 0
    ADRL x0, Ls_lifx_title
    ADRL x1, Ls_lifx_info
    ADRL x2, Ls_lifx_ph
    mov  x3, #0
    mov  x4, #1
    ADRL x5, _g_lifx_token
    mov  x6, #160
    bl   _ask_text
    cbz  x0, Llc_none
    ADRL x0, Ls_kc_lifx
    ADRL x1, _g_lifx_token
    bl   _kc_set
    bl   _cloud_make_auth
    ADRL x0, Ls_checking
    ADRL x1, Ls_n_lifx
    bl   _home_say
    bl   _lifx_load
    LEAVE 0
Llc_none:
    ADRL x0, Ls_cancelled
    bl   _home_say0
    LEAVE 0

.globl _govee_connect_dialog
_govee_connect_dialog:
    ENTER 0
    ADRL x0, Ls_govee_title
    ADRL x1, Ls_govee_info
    ADRL x2, Ls_govee_ph
    mov  x3, #0
    mov  x4, #1
    ADRL x5, _g_govee_key
    mov  x6, #128
    bl   _ask_text
    cbz  x0, Lgc_none
    ADRL x0, Ls_kc_govee
    ADRL x1, _g_govee_key
    bl   _kc_set
    ADRL x0, Ls_checking
    ADRL x1, Ls_n_govee
    bl   _home_say
    bl   _govee_load
    LEAVE 0
Lgc_none:
    ADRL x0, Ls_cancelled
    bl   _home_say0
    LEAVE 0

.globl _ha_connect_dialog
_ha_connect_dialog:
    ENTER 16
    // the address: what we had, what Bonjour found, or the usual one
    ADRL x3, _g_ha_url
    ldrb w9, [x3]
    cbnz w9, Lhc_ask
    ADRL x3, _g_ha_found
    ldrb w9, [x3]
    cbnz w9, Lhc_ask
    ADRL x3, Ls_ha_default
Lhc_ask:
    ADRL x0, _g_cl_tmp
    mov  x1, x3
    mov  x2, #160
    bl   _strlcpy
    ADRL x0, Ls_ha_title
    ADRL x1, Ls_ha_info1
    ADRL x2, Ls_ha_default
    ADRL x3, _g_cl_tmp
    mov  x4, #0
    ADRL x5, _g_cl_url
    mov  x6, #160
    bl   _ask_text
    cbz  x0, Lhc_none
    // "homeassistant.local:8123/" -> "http://homeassistant.local:8123"
    ADRL x0, _g_cl_url
    ADRL x1, Ls_scheme
    bl   _strstr
    ADRL x3, _g_cl_url
    ADRL x2, Lf_s
    cbnz x0, Lhc_fmt
    ADRL x2, Lf_http_s
Lhc_fmt:
    ADRL x0, _g_ha_url
    mov  x1, #160
    bl   _sfmt
    ADRL x0, _g_ha_url
    bl   _strlen
    cbz  x0, Lhc_none
    sub  x9, x0, #1
    ADRL x10, _g_ha_url
    ldrb w11, [x10, x9]
    cmp  w11, #'/'
    b.ne Lhc_token
    strb wzr, [x10, x9]
Lhc_token:
    ADRL x0, Ls_ha_title
    ADRL x1, Ls_ha_info2
    ADRL x2, Ls_ha_ph
    mov  x3, #0
    mov  x4, #1
    ADRL x5, _g_ha_token
    mov  x6, #320
    bl   _ask_text
    cbz  x0, Lhc_none
    ADRL x0, Ls_kc_ha
    ADRL x1, _g_ha_token
    bl   _kc_set
    ADRL x0, Ls_pref_ha
    ADRL x1, _g_ha_url
    bl   _pref_set
    bl   _cloud_make_auth
    ADRL x0, Ls_checking
    ADRL x1, Ls_n_ha
    bl   _home_say
    bl   _ha_load
    LEAVE 16
Lhc_none:
    ADRL x8, _g_ha_token              // keep an earlier connection working
    ldrb w9, [x8]
    cbnz w9, Lhc_keep
    ADRL x8, _g_ha_url
    strb wzr, [x8]
Lhc_keep:
    ADRL x0, Ls_cancelled
    bl   _home_say0
    LEAVE 16

// ===========================================================================
// Responses
// ===========================================================================

// const char *_cl_tag(char letter, long n) -> "c<letter><n>"
_cl_tag:
    ENTER 0
    mov  x4, x1
    mov  x3, x0
    ADRL x0, _g_cl_tag
    mov  x1, #32
    ADRL x2, Lf_tag
    bl   _sfmt
    ADRL x0, _g_cl_tag
    LEAVE 0

// void _cloud_response(const char *tag, id json, long status, NSError *err, NSData *raw)
.globl _cloud_response
_cloud_response:
    ENTER 32                          // [96] service name
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldrb w23, [x19, #1]
    cmp  w23, #'c'
    b.eq Lcr_cmd
    cmp  w23, #'s'
    b.eq Lcr_status
    cmp  w23, #'t'
    b.eq Lcr_areas
    cmp  w23, #'q'
    b.eq Lcr_quiet
    ADRL x24, Ls_n_lifx
    cmp  w23, #'x'
    b.eq Lcr_list
    ADRL x24, Ls_n_govee
    cmp  w23, #'g'
    b.eq Lcr_list
    ADRL x24, Ls_n_ha
Lcr_list:
    cbnz x22, Lcr_neterr
    cmp  x21, #401
    b.eq Lcr_auth
    cmp  x21, #403
    b.eq Lcr_auth
    cmp  x21, #300
    b.hs Lcr_http
    cmp  w23, #'x'
    b.eq Lcr_lifx
    cmp  w23, #'g'
    b.eq Lcr_govee
    b    Lcr_ha
Lcr_neterr:
    mov  x0, x22
    bl   _err_cstr
    mov  x2, x0
    mov  x1, x24
    ADRL x0, Ls_unreach
    bl   _home_say
    LEAVE 32
Lcr_auth:
    mov  x1, x24
    mov  x2, x24
    ADRL x0, Ls_badkey
    bl   _home_say
    LEAVE 32
Lcr_http:
    mov  x1, x24
    mov  x2, x21
    ADRL x0, Ls_refused
    bl   _home_say
Lcr_done:
    LEAVE 32

Lcr_cmd:                              // a command: only failures are worth a line
    mov  x0, x19
    bl   _tag_num
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs Lcr_done
    ADRL x8, _g_devs
    add  x24, x8, x0, lsl #DEV_SHIFT
    cbnz x22, Lcr_cmd_net
    cmp  x21, #300
    b.hs Lcr_cmd_http
    ldr  x9, [x24, #D_KIND]           // Govee answers 200 with its own code
    cmp  x9, #K_GOVEE
    b.ne Lcr_done
    mov  x0, x20
    ADRL x1, Lj_code
    bl   _jget
    cbz  x0, Lcr_done
    bl   _jint
    cmp  x0, #200
    b.eq Lcr_done
    mov  x21, x0
Lcr_cmd_http:
    mov  x0, x20                      // any message the service sent
    ADRL x1, Lj_message
    bl   _jget
    bl   _jstr
    cbnz x0, Lcr_cmd_msg
    mov  x0, x20
    ADRL x1, Lj_msg
    bl   _jget
    bl   _jstr
    cbnz x0, Lcr_cmd_msg
    mov  x0, x20
    ADRL x1, Lj_error
    bl   _jget
    bl   _jstr
    cbnz x0, Lcr_cmd_msg
    ADRL x0, Ls_empty
Lcr_cmd_msg:
    mov  x3, x0
    add  x1, x24, #D_NAME
    mov  x2, x21
    ADRL x0, Ls_cmd_http
    bl   _home_say
    LEAVE 32
Lcr_cmd_net:
    mov  x0, x22
    bl   _err_cstr
    mov  x2, x0
    add  x1, x24, #D_NAME
    ADRL x0, Ls_cmd_net
    bl   _home_say
    LEAVE 32

// ---- LIFX: [{"id","label","power","brightness","product":{"capabilities":{...}}}]
Lcr_lifx:
    mov  x0, x20
    bl   _jcount
    mov  x21, x0
    mov  x22, #0                      // i
    mov  x23, #0                      // taken
Lcx_loop:
    cmp  x22, x21
    b.hs Lcx_sum
    mov  x0, x20
    mov  x1, x22
    bl   _jat
    mov  x24, x0
    ADRL x1, Lj_id
    bl   _jget
    bl   _jstr
    cbz  x0, Lcx_next
    str  x0, [sp, #96]
    mov  x0, x24
    ADRL x1, Lj_label
    bl   _jget
    bl   _jstr
    cbz  x0, Lcx_next
    str  x0, [sp, #104]
    mov  x0, x24
    ADRL x1, Lj_product
    bl   _jget
    ADRL x1, Lj_capabilities
    bl   _jget
    str  x0, [sp, #112]
    mov  x9, #(CAP_ON | CAP_LEVEL)
    str  x9, [sp, #120]
    ADRL x1, Lj_has_color
    bl   _jget
    bl   _jint
    cbz  x0, Lcx_ct
    ldr  x9, [sp, #120]
    orr  x9, x9, #CAP_COLOR
    str  x9, [sp, #120]
Lcx_ct:
    ldr  x0, [sp, #112]
    ADRL x1, Lj_has_ct
    bl   _jget
    bl   _jint
    cbz  x0, Lcx_add
    ldr  x9, [sp, #120]
    orr  x9, x9, #CAP_CT
    str  x9, [sp, #120]
Lcx_add:
    mov  x0, #K_LIFX
    ldr  x1, [sp, #96]
    ldr  x2, [sp, #104]
    ldr  x3, [sp, #120]
    bl   _dev_add
    tbnz x0, #63, Lcx_next
    str  x0, [sp, #96]
    add  x23, x23, #1
    mov  x0, x24
    ADRL x1, Lj_brightness
    bl   _jget
    bl   _jpct
    str  x0, [sp, #104]
    mov  x0, x24
    ADRL x1, Lj_power
    bl   _jget
    bl   _jstr
    mov  x1, #0
    cbz  x0, Lcx_state
    ADRL x1, Lj_on
    bl   _strcmp
    cmp  w0, #0
    cset x1, eq
Lcx_state:
    ldr  x0, [sp, #96]
    ldr  x2, [sp, #104]
    bl   _dev_state
Lcx_next:
    add  x22, x22, #1
    b    Lcx_loop
Lcx_sum:
    mov  x1, x23
    ADRL x0, Ls_lifx_ready
    bl   _home_say
    bl   _ui_lists_changed
    LEAVE 32

// ---- Govee: {"code":200,"data":[{"sku","device","deviceName","capabilities":[{"instance"}]}]}
Lcr_govee:
    mov  x0, x20
    ADRL x1, Lj_data
    bl   _jget
    mov  x20, x0
    bl   _jcount
    mov  x21, x0
    mov  x22, #0
    mov  x23, #0
Lcg_loop:
    cmp  x22, x21
    b.hs Lcg_sum
    mov  x0, x20
    mov  x1, x22
    bl   _jat
    mov  x24, x0
    ADRL x1, Lj_capabilities
    bl   _jget
    str  x0, [sp, #112]
    str  xzr, [sp, #120]
    ADRL x1, Lj_instance
    ADRL x2, Lg_power
    bl   _jfind
    cbz  x0, Lcg_bri
    mov  x9, #CAP_ON
    str  x9, [sp, #120]
Lcg_bri:
    ldr  x0, [sp, #112]
    ADRL x1, Lj_instance
    ADRL x2, Lg_brightness
    bl   _jfind
    cbz  x0, Lcg_rgb
    ldr  x9, [sp, #120]
    orr  x9, x9, #CAP_LEVEL
    str  x9, [sp, #120]
Lcg_rgb:
    ldr  x0, [sp, #112]
    ADRL x1, Lj_instance
    ADRL x2, Lg_rgb
    bl   _jfind
    cbz  x0, Lcg_ct
    ldr  x9, [sp, #120]
    orr  x9, x9, #CAP_COLOR
    str  x9, [sp, #120]
Lcg_ct:
    ldr  x0, [sp, #112]
    ADRL x1, Lj_instance
    ADRL x2, Lg_ct
    bl   _jfind
    cbz  x0, Lcg_have
    ldr  x9, [sp, #120]
    orr  x9, x9, #CAP_CT
    str  x9, [sp, #120]
Lcg_have:
    ldr  x9, [sp, #120]
    cbz  x9, Lcg_next
    mov  x0, x24
    ADRL x1, Lj_device
    bl   _jget
    bl   _jstr
    cbz  x0, Lcg_next
    str  x0, [sp, #96]
    mov  x0, x24
    ADRL x1, Lj_deviceName
    bl   _jget
    bl   _jstr
    cbz  x0, Lcg_next
    mov  x2, x0
    mov  x0, #K_GOVEE
    ldr  x1, [sp, #96]
    ldr  x3, [sp, #120]
    bl   _dev_add
    tbnz x0, #63, Lcg_next
    add  x23, x23, #1
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    str  x8, [sp, #104]
    mov  x0, x24
    ADRL x1, Lj_sku
    bl   _jget
    bl   _jstr
    cbz  x0, Lcg_next
    mov  x1, x0
    ldr  x8, [sp, #104]
    add  x0, x8, #D_AUX
    mov  x2, #D_AUX_MAX
    bl   _strlcpy
Lcg_next:
    add  x22, x22, #1
    b    Lcg_loop
Lcg_sum:
    mov  x1, x23
    ADRL x0, Ls_govee_ready
    bl   _home_say
    bl   _ui_lists_changed
    LEAVE 32

// ---- Home Assistant: [{"entity_id","state","attributes":{...}}]
Lcr_ha:
    mov  x0, x20
    bl   _jcount
    mov  x21, x0
    mov  x22, #0
    mov  x23, #0
Lca_loop:
    cmp  x22, x21
    b.hs Lca_sum
    mov  x0, x20
    mov  x1, x22
    bl   _jat
    bl   _ha_take
    add  x23, x23, x0
    add  x22, x22, #1
    b    Lca_loop
Lca_sum:
    mov  x1, x23
    ADRL x0, Ls_ha_ready
    bl   _home_say
    bl   _ui_lists_changed
    ADRL x0, _g_cl_url                // and which area (room) each one is in
    mov  x1, #400
    ADRL x2, Lf_ha_template
    ADRL x3, _g_ha_url
    bl   _sfmt
    ADRL x0, Ls_POST
    ADRL x1, _g_cl_url
    ADRL x2, Ls_ha_areas_body
    ADRL x3, _g_ha_auth
    ADRL x4, Ls_tag_areas
    bl   _http
    LEAVE 32

// ---- a rule is watching it: remember its state quietly
Lcr_quiet:
    cbnz x22, Lcr_done
    cmp  x21, #300
    b.hs Lcr_done
    mov  x0, x19
    bl   _tag_num
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs Lcr_done
    mov  x23, x0
    mov  x0, x20
    bl   _ha_state_to_dev
    LEAVE 32

// ---- Home Assistant areas: "light.kitchen=Kitchen;switch.fan=None;..."
Lcr_areas:
    cbnz x22, Lcr_done
    cmp  x21, #300
    b.hs Lcr_done
    cbz  x4, Lcr_done
    mov  x24, x4                      // raw text
    mov  x0, x24
    MSG0 Ls_length
    mov  x23, x0
    add  x0, x23, #1
    bl   _malloc
    cbz  x0, Lcr_done
    mov  x20, x0
    mov  x0, x24
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x20
    mov  x2, x23
    bl   _memcpy
    strb wzr, [x20, x23]
    mov  x21, x20                     // cursor
Lar_item:
    ldrb w9, [x21]
    cbz  w9, Lar_free
    mov  x22, x21                     // entity
Lar_eq:
    ldrb w9, [x21]
    cbz  w9, Lar_free
    cmp  w9, #';'
    b.eq Lar_skip
    cmp  w9, #'='
    b.eq Lar_area
    add  x21, x21, #1
    b    Lar_eq
Lar_skip:
    add  x21, x21, #1
    b    Lar_item
Lar_area:
    strb wzr, [x21]
    add  x21, x21, #1
    mov  x24, x21                     // area
Lar_end:
    ldrb w9, [x21]
    cbz  w9, Lar_set
    cmp  w9, #';'
    b.eq Lar_cut
    add  x21, x21, #1
    b    Lar_end
Lar_cut:
    strb wzr, [x21]
    add  x21, x21, #1
Lar_set:
    ldrb w9, [x22]                    // entity ids may have picked up spaces
    cmp  w9, #' '
    b.ne Lar_trim_done
    add  x22, x22, #1
    b    Lar_set
Lar_trim_done:
    mov  x0, x24
    ADRL x1, Ls_None
    bl   _strcmp
    cbz  w0, Lar_item
    ldrb w9, [x24]
    cbz  w9, Lar_item
    mov  x0, #K_HA
    mov  x1, x22
    bl   _dev_find
    tbnz x0, #63, Lar_item
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    add  x0, x8, #D_ROOM
    mov  x1, x24
    mov  x2, #D_ROOM_MAX
    bl   _strlcpy
    b    Lar_item
Lar_free:
    mov  x0, x20
    bl   _free
    bl   _ui_lists_changed
    LEAVE 32

// ---- Home Assistant status of one entity
Lcr_status:
    mov  x0, x19
    bl   _tag_num
    mov  x23, x0
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x23, x9
    b.hs Lcr_done
    ADRL x8, _g_devs
    add  x24, x8, x23, lsl #DEV_SHIFT
    cbnz x22, Lcr_cmd_net
    cmp  x21, #300
    b.hs Lcr_cmd_http
    mov  x0, x20
    bl   _ha_state_to_dev
    mov  x0, x20                      // "on", "locked", "21.5", "heat"...
    ADRL x1, Lj_state
    bl   _jget
    ADRL x1, _g_cl_line
    mov  x2, #400
    bl   _jdesc
    mov  x0, x20
    ADRL x1, Lj_attributes
    bl   _jget
    mov  x22, x0
    ADRL x1, Lj_unit
    bl   _jget
    bl   _jstr
    cbz  x0, Lcs_attrs
    mov  x1, x0
    ADRL x0, _g_cl_line
    mov  x2, #480
    bl   _strlcat
Lcs_attrs:
    ADRL x21, Lha_report
Lcs_loop:
    ldr  x1, [x21]
    cbz  x1, Lcs_say
    mov  x0, x22
    bl   _jget
    cbz  x0, Lcs_next
    ldr  x9, [x21, #24]
    cbz  x9, Lcs_text
    cmp  x9, #2
    b.eq Lcs_frac
    bl   _jint                        // 0..255
    mov  x9, #100
    mul  x3, x0, x9
    mov  x9, #255
    udiv x3, x3, x9
    b    Lcs_num
Lcs_frac:
    bl   _jpct
    mov  x3, x0
Lcs_num:
    ADRL x0, _g_cl_val
    mov  x1, #64
    ADRL x2, Lf_ld
    bl   _sfmt
    b    Lcs_piece
Lcs_text:
    ADRL x1, _g_cl_val
    mov  x2, #64
    bl   _jdesc
    ldrb w9, [x0]
    cbz  w9, Lcs_next
Lcs_piece:
    ADRL x0, _g_cl_line
    ADRL x1, Ls_comma
    mov  x2, #480
    bl   _strlcat
    ADRL x0, _g_cl_line
    ldr  x1, [x21, #8]
    mov  x2, #480
    bl   _strlcat
    ADRL x0, _g_cl_line
    ADRL x1, _g_cl_val
    mov  x2, #480
    bl   _strlcat
    ADRL x0, _g_cl_line
    ldr  x1, [x21, #16]
    mov  x2, #480
    bl   _strlcat
Lcs_next:
    add  x21, x21, #32
    b    Lcs_loop
Lcs_say:
    add  x1, x24, #D_NAME
    ADRL x2, _g_cl_line
    ADRL x0, Ls_status_line
    bl   _home_say
    LEAVE 32

// void _ha_state_to_dev(NSDictionary *state) — on/off and brightness into the registry (x23 = index)
_ha_state_to_dev:
    ENTER 16
    mov  x19, x0
    ADRL x1, Lj_state
    bl   _jget
    bl   _jstr
    mov  x1, #-1
    cbz  x0, Lhsd_level
    mov  x20, x0
    bl   _ha_open_lock                // open/closed, locked/unlocked
    ADRL x1, Lj_on
    bl   _strcmp
    mov  x1, #1
    cbz  w0, Lhsd_level
    mov  x0, x20
    ADRL x1, Lj_off
    bl   _strcmp
    mov  x1, #0
    cbz  w0, Lhsd_level
    mov  x1, #-1
Lhsd_level:
    str  x1, [sp, #96]
    mov  x0, x19
    ADRL x1, Lj_attributes
    bl   _jget
    ADRL x1, Lj_brightness
    bl   _jget
    mov  x2, #-1
    cbz  x0, Lhsd_set
    bl   _jint
    mov  x9, #100
    mul  x2, x0, x9
    mov  x9, #255
    udiv x2, x2, x9
Lhsd_set:
    mov  x0, x23
    ldr  x1, [sp, #96]
    bl   _dev_state
    LEAVE 16

// void _ha_open_lock(const char *state) — into D_OPEN / D_LOCKED of device x23 (caller's)
_ha_open_lock:
    stp  x29, x30, [sp, #-32]!
    mov  x29, sp
    stp  x19, x20, [sp, #16]
    mov  x19, x0
    ADRL x8, _g_devs
    add  x20, x8, x23, lsl #DEV_SHIFT
    mov  x0, x19
    ADRL x1, Lj_open
    bl   _strcmp
    mov  x9, #1
    cbz  w0, Lhol_open
    mov  x0, x19
    ADRL x1, Lj_opening
    bl   _strcmp
    mov  x9, #1
    cbz  w0, Lhol_open
    mov  x0, x19
    ADRL x1, Lj_closed
    bl   _strcmp
    mov  x9, #0
    cbz  w0, Lhol_open
    mov  x0, x19
    ADRL x1, Lj_closing
    bl   _strcmp
    mov  x9, #0
    cbnz w0, Lhol_lock
Lhol_open:
    str  x9, [x20, #D_OPEN]
Lhol_lock:
    mov  x0, x19
    ADRL x1, Lj_locked
    bl   _strcmp
    mov  x9, #1
    cbz  w0, Lhol_lock_set
    mov  x0, x19
    ADRL x1, Lj_unlocked
    bl   _strcmp
    mov  x9, #0
    cbnz w0, Lhol_done
Lhol_lock_set:
    str  x9, [x20, #D_LOCKED]
Lhol_done:
    ldp  x19, x20, [sp, #16]
    ldp  x29, x30, [sp], #32
    ret

// void _ha_poll(long idx) — quietly ask for its state (for rules)
.globl _ha_poll
_ha_poll:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_ha_url
    ldrb w9, [x8]
    cbz  w9, Lhp_done
    ADRL x8, _g_devs
    add  x20, x8, x19, lsl #DEV_SHIFT
    ADRL x0, _g_cl_url
    mov  x1, #400
    ADRL x2, Lf_ha_state
    ADRL x3, _g_ha_url
    add  x4, x20, #D_ID
    bl   _sfmt
    mov  x0, #'q'
    mov  x1, x19
    bl   _cl_tag
    mov  x4, x0
    ADRL x0, Ls_GET
    ADRL x1, _g_cl_url
    mov  x2, #0
    ADRL x3, _g_ha_auth
    bl   _http
Lhp_done:
    LEAVE 0

// long _ha_take(NSDictionary *state) -> 1 if registered
_ha_take:
    ENTER 32                          // [96] entity  [104] name  [112] attrs  [120] caps
    mov  x19, x0
    ADRL x1, Lj_entity_id
    bl   _jget
    bl   _jstr
    cbz  x0, Lht_no
    str  x0, [sp, #96]
    // domain = the part before '.'
    mov  x1, x0
    ADRL x0, _g_cl_dom
    mov  x2, #32
    bl   _strlcpy
    ADRL x0, _g_cl_dom
    mov  w1, #'.'
    bl   _strchr
    cbz  x0, Lht_no
    strb wzr, [x0]
    mov  x0, x19
    ADRL x1, Lj_attributes
    bl   _jget
    str  x0, [sp, #112]
    ADRL x1, Lj_friendly
    bl   _jget
    bl   _jstr
    cbnz x0, Lht_named
    ldr  x0, [sp, #96]
Lht_named:
    str  x0, [sp, #104]
    ADRL x20, Lha_domains
Lht_dom:
    ldr  x1, [x20]
    cbz  x1, Lht_no
    ADRL x0, _g_cl_dom
    bl   _strcmp
    cbz  w0, Lht_known
    add  x20, x20, #16
    b    Lht_dom
Lht_known:
    ldr  x21, [x20, #8]               // caps
    ldr  x22, [sp, #112]              // attributes
    mov  x24, #0                      // aux flags
    ldr  x9, [x20]
    ADRL x10, Ld_light
    cmp  x9, x10
    b.eq Lht_light
    ADRL x10, Ld_cover
    cmp  x9, x10
    b.eq Lht_cover
    ADRL x10, Ld_climate
    cmp  x9, x10
    b.eq Lht_climate
    ADRL x10, Ld_media
    cmp  x9, x10
    b.eq Lht_media
    ADRL x10, Ld_sensor
    cmp  x9, x10
    b.eq Lht_sensor
    b    Lht_add
Lht_light:                            // supported_color_modes
    mov  x0, x22
    ADRL x1, Lj_color_modes
    bl   _jget
    mov  x23, x0
    ADRL x20, Lcolor_modes
Lht_cm:
    ldr  x1, [x20], #8
    cbz  x1, Lht_ct
    mov  x0, x23
    bl   _jhas
    cbz  x0, Lht_cm
    orr  x21, x21, #(CAP_COLOR | CAP_LEVEL)
Lht_ct:
    mov  x0, x23
    ADRL x1, Lj_color_temp
    bl   _jhas
    cbz  x0, Lht_bri
    orr  x21, x21, #CAP_CT
    orr  x21, x21, #CAP_LEVEL
Lht_bri:
    mov  x0, x23
    ADRL x1, Lj_brightness
    bl   _jhas
    cbz  x0, Lht_white
    orr  x21, x21, #CAP_LEVEL
Lht_white:
    mov  x0, x23
    ADRL x1, Lj_white
    bl   _jhas
    cbz  x0, Lht_add
    orr  x21, x21, #CAP_LEVEL
    b    Lht_add
Lht_cover:                            // a garage door or gate is treated with care
    mov  x0, x22
    ADRL x1, Lj_device_class
    bl   _jget
    bl   _jstr
    cbz  x0, Lht_add
    mov  x23, x0
    ADRL x1, Lj_garage
    bl   _strcmp
    cbz  w0, Lht_garage
    mov  x0, x23
    ADRL x1, Lj_gate
    bl   _strcmp
    cbnz w0, Lht_add
Lht_garage:
    MOVI x21, (CAP_GARAGE | CAP_STATUS)
    b    Lht_add
Lht_climate:                          // "auto" is heat_cool on most thermostats
    mov  x0, x22
    ADRL x1, Lj_hvac_modes
    bl   _jget
    ADRL x1, Lj_heat_cool
    bl   _jhas
    mov  x24, x0
    b    Lht_add
Lht_media:
    mov  x0, x22
    ADRL x1, Lj_device_class
    bl   _jget
    bl   _jstr
    cbz  x0, Lht_add
    ADRL x1, Lj_tv
    bl   _strcmp
    cbnz w0, Lht_add
    MOVI x9, (CAP_TV | CAP_INPUT | CAP_APPS | CAP_CHANNEL)
    orr  x21, x21, x9
    b    Lht_add
Lht_sensor:
    mov  x0, x22
    ADRL x1, Lj_device_class
    bl   _jget
    bl   _jstr
    cbz  x0, Lht_no
    mov  x23, x0
    ADRL x1, Lj_temperature
    bl   _strcmp
    MOVI x21, (CAP_TEMP | CAP_STATUS)
    cbz  w0, Lht_add
    mov  x0, x23
    ADRL x1, Lj_humidity
    bl   _strcmp
    MOVI x21, CAP_STATUS
    cbz  w0, Lht_add
    mov  x0, x23                      // power and energy meters: "power use"
    ADRL x1, Lj_power
    bl   _strcmp
    cbz  w0, Lht_power
    mov  x0, x23
    ADRL x1, Lj_energy
    bl   _strcmp
    cbnz w0, Lht_no
Lht_power:
    MOVI x21, (CAP_POWER | CAP_STATUS)
Lht_add:
    mov  x0, #K_HA
    ldr  x1, [sp, #96]
    ldr  x2, [sp, #104]
    mov  x3, x21
    bl   _dev_add
    tbnz x0, #63, Lht_no
    mov  x23, x0
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    str  x24, [x8, #D_AUX]
    mov  x9, #-1
    str  x9, [x8, #D_OPEN]
    str  x9, [x8, #D_LOCKED]
    mov  x0, x19
    bl   _ha_state_to_dev
    mov  x0, #1
    LEAVE 32
Lht_no:
    mov  x0, #0
    LEAVE 32

// ===========================================================================
// Control
// ===========================================================================

// long _lifx_set(long idx, long action, long value)
.globl _lifx_set
_lifx_set:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_lifx_token
    ldrb w9, [x8]
    cbz  w9, Lxs_noconn
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ADRL x23, Lf_lifx_state
    ADRL x24, Ls_PUT
    ADRL x2, Lx_lifx_on
    cmp  x20, #A_ON
    b.eq Lxs_fixed
    ADRL x2, Lx_lifx_off
    cmp  x20, #A_OFF
    b.eq Lxs_fixed
    ADRL x23, Lf_lifx_delta
    ADRL x24, Ls_POST
    ADRL x2, Lx_lifx_up
    cmp  x20, #A_BRIGHTER
    b.eq Lxs_fixed
    ADRL x2, Lx_lifx_down
    cmp  x20, #A_DIMMER
    b.eq Lxs_fixed
    ADRL x23, Lf_lifx_state
    ADRL x24, Ls_PUT
    mov  x3, x21
    ADRL x2, Lx_lifx_hue
    cmp  x20, #A_COLOR
    b.eq Lxs_fmt
    ADRL x2, Lx_lifx_kelvin
    cmp  x20, #A_CT
    b.eq Lxs_fmt
    cmp  x20, #A_LEVEL
    b.ne Lxs_cant
    mov  x9, #100
    udiv x3, x21, x9
    msub x4, x3, x9, x21
    ADRL x2, Lx_lifx_bri
Lxs_fmt:
    ADRL x0, _g_cl_body
    mov  x1, #512
    bl   _sfmt
    b    Lxs_send
Lxs_fixed:
    ADRL x0, _g_cl_body
    mov  x1, x2
    mov  x2, #512
    bl   _strlcpy
Lxs_send:
    ADRL x0, _g_cl_url
    mov  x1, #400
    mov  x2, x23
    add  x3, x22, #D_ID
    bl   _sfmt
    mov  x0, #'c'
    mov  x1, x19
    bl   _cl_tag
    mov  x4, x0
    mov  x0, x24
    ADRL x1, _g_cl_url
    ADRL x2, _g_cl_body
    ADRL x3, _g_lifx_auth
    bl   _http
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 16
Lxs_cant:
    mov  x0, #0
    LEAVE 16
Lxs_noconn:
    ADRL x0, Ls_need
    ADRL x1, Ls_n_lifx
    ADRL x2, Ls_w_lifx
    bl   _home_say
    mov  x0, #2
    LEAVE 16

// long _govee_set(long idx, long action, long value)
.globl _govee_set
_govee_set:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_govee_key
    ldrb w9, [x8]
    cbz  w9, Lgs_noconn
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    cmp  x20, #A_ON
    b.eq Lgs_on
    cmp  x20, #A_OFF
    b.eq Lgs_off
    cmp  x20, #A_COLOR
    b.eq Lgs_rgb
    cmp  x20, #A_CT
    b.eq Lgs_ct
    cmp  x20, #A_LEVEL
    b.eq Lgs_level
    cmp  x20, #A_BRIGHTER
    b.eq Lgs_level
    cmp  x20, #A_DIMMER
    b.ne Lgs_cant
Lgs_level:
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _rel_level
    mov  x21, x0
    mov  x20, #A_LEVEL
    mov  x7, x0
    ADRL x5, Lg_range
    ADRL x6, Lg_brightness
    b    Lgs_body
Lgs_on:
    mov  x7, #1
    b    Lgs_power
Lgs_off:
    mov  x7, #0
Lgs_power:
    ADRL x5, Lg_on_off
    ADRL x6, Lg_power
    b    Lgs_body
Lgs_rgb:
    mov  x0, x21
    bl   _hue_to_rgb
    mov  x7, x0
    ADRL x5, Lg_color_setting
    ADRL x6, Lg_rgb
    b    Lgs_body
Lgs_ct:
    mov  x7, x21                      // Govee: 2000..9000 K
    mov  x9, #2000
    cmp  x7, x9
    csel x7, x9, x7, lo
    mov  x9, #9000
    cmp  x7, x9
    csel x7, x9, x7, hi
    ADRL x5, Lg_color_setting
    ADRL x6, Lg_ct
Lgs_body:
    ADRL x0, _g_cl_body
    mov  x1, #512
    ADRL x2, Lf_govee_body
    add  x3, x22, #D_AUX              // sku
    add  x4, x22, #D_ID               // device
    bl   _sfmt
    mov  x0, #'c'
    mov  x1, x19
    bl   _cl_tag
    mov  x4, x0
    ADRL x0, Ls_POST
    ADRL x1, Ls_govee_control
    ADRL x2, _g_cl_body
    mov  x3, #0
    ADRL x5, Ls_govee_header
    ADRL x6, _g_govee_key
    bl   _http2
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 16
Lgs_cant:
    mov  x0, #0
    LEAVE 16
Lgs_noconn:
    ADRL x0, Ls_need
    ADRL x1, Ls_n_govee
    ADRL x2, Ls_w_govee
    bl   _home_say
    mov  x0, #2
    LEAVE 16

// long _ha_set(long idx, long action, long value)
.globl _ha_set
_ha_set:
    ENTER 32                          // [96] extra fmt  [104] kind  [112] string arg  [120] service
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_ha_url
    ldrb w9, [x8]
    cbz  w9, Lhs_noconn
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    add  x1, x22, #D_ID               // domain
    ADRL x0, _g_cl_dom
    mov  x2, #32
    bl   _strlcpy
    ADRL x0, _g_cl_dom
    mov  w1, #'.'
    bl   _strchr
    cbz  x0, Lhs_cant
    strb wzr, [x0]
    cmp  x20, #A_LAST
    b.hi Lhs_cant
    mov  x9, #24
    ADRL x8, Lha_acts
    madd x8, x20, x9, x8
    ldr  x23, [x8]                    // service
    cbz  x23, Lhs_cant
    ldp  x9, x10, [x8, #8]
    stp  x9, x10, [sp, #96]
    str  xzr, [sp, #112]
    ldr  x24, [x22, #D_CAPS]

    cmp  x20, #A_LEVEL
    b.eq Lho_level
    cmp  x20, #A_OPEN
    b.eq Lho_open
    cmp  x20, #A_CLOSE
    b.eq Lho_close
    cmp  x20, #A_INPUT
    b.eq Lho_input
    cmp  x20, #A_APP
    b.eq Lho_app
    cmp  x20, #A_TMODE
    b.eq Lho_tmode
    cmp  x20, #A_FANSPEED
    b.eq Lho_fan
    b    Lhs_build
Lho_level:
    tst  x24, #CAP_SHADE
    b.eq Lho_level_fan
    ADRL x23, Lsv_set_pos
    ADRL x9, Lx_position
    str  x9, [sp, #96]
    b    Lhs_build
Lho_level_fan:
    tst  x24, #CAP_FAN
    b.eq Lhs_build
    ADRL x23, Lsv_set_pct
    ADRL x9, Lx_pct
    str  x9, [sp, #96]
    b    Lhs_build
Lho_open:
    tst  x24, #CAP_VALVE
    b.eq Lhs_build
    ADRL x23, Lsv_open_valve
    b    Lhs_build
Lho_close:
    tst  x24, #CAP_VALVE
    b.eq Lhs_build
    ADRL x23, Lsv_close_valve
    b    Lhs_build
Lho_input:
    ADRL x9, Ls_tv
    cbz  x21, Lho_input_set
    ADRL x0, _g_cl_val
    mov  x1, #64
    ADRL x2, Lf_hdmi
    mov  x3, x21
    bl   _sfmt
    ADRL x9, _g_cl_val
Lho_input_set:
    str  x9, [sp, #112]
    b    Lhs_build
Lho_app:
    mov  x0, x21
    mov  x1, #0                       // display name, e.g. "Netflix"
    bl   _app_field
    str  x0, [sp, #112]
    b    Lhs_build
Lho_tmode:
    ADRL x8, _g_cmd_word
    ldr  x9, [x8]
    cbz  x9, Lhs_cant
    cmp  x21, #3                      // auto
    b.ne Lho_tmode_set
    ADRL x9, Lj_auto
    ldr  x10, [x22, #D_AUX]
    cbz  x10, Lho_tmode_set
    ADRL x9, Lj_heat_cool
Lho_tmode_set:
    str  x9, [sp, #112]
    b    Lhs_build
Lho_fan:                              // 1 2 3 -> 33 67 100 %
    mov  x9, #33
    mul  x21, x21, x9
    cmp  x21, #99
    mov  x9, #100
    csel x21, x9, x21, hs

Lhs_build:
    ldp  x2, x9, [sp, #96]
    mov  x3, x21
    cmp  x9, #2
    b.ne Lhs_frac
    ldr  x3, [sp, #112]
    b    Lhs_extra
Lhs_frac:
    cmp  x9, #3
    b.ne Lhs_extra
    mov  x10, #100
    udiv x3, x21, x10
    msub x4, x3, x10, x21
Lhs_extra:
    ADRL x0, _g_cl_val
    mov  x1, #64
    bl   _sfmt
    ADRL x0, _g_cl_body
    mov  x1, #512
    ADRL x2, Lf_ha_body
    add  x3, x22, #D_ID
    ADRL x4, _g_cl_val
    bl   _sfmt
    ADRL x0, _g_cl_url
    mov  x1, #400
    ADRL x2, Lf_ha_service
    ADRL x3, _g_ha_url
    ADRL x4, _g_cl_dom
    mov  x5, x23
    bl   _sfmt
    mov  x0, #'c'
    mov  x1, x19
    bl   _cl_tag
    mov  x4, x0
    ADRL x0, Ls_POST
    ADRL x1, _g_cl_url
    ADRL x2, _g_cl_body
    ADRL x3, _g_ha_auth
    bl   _http
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 32
Lhs_cant:
    mov  x0, #0
    LEAVE 32
Lhs_noconn:
    ADRL x0, Ls_need
    ADRL x1, Ls_n_ha
    ADRL x2, Ls_w_ha
    bl   _home_say
    mov  x0, #2
    LEAVE 32

// void _ha_status(long idx) — GET /api/states/<entity>
.globl _ha_status
_ha_status:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_ha_url
    ldrb w9, [x8]
    cbz  w9, Lhst_none
    ADRL x8, _g_devs
    add  x20, x8, x19, lsl #DEV_SHIFT
    ADRL x0, _g_cl_url
    mov  x1, #400
    ADRL x2, Lf_ha_state
    ADRL x3, _g_ha_url
    add  x4, x20, #D_ID
    bl   _sfmt
    mov  x0, #'s'
    mov  x1, x19
    bl   _cl_tag
    mov  x4, x0
    ADRL x0, Ls_GET
    ADRL x1, _g_cl_url
    mov  x2, #0
    ADRL x3, _g_ha_auth
    bl   _http
    LEAVE 0
Lhst_none:
    mov  x0, x19
    bl   _dev_say_state
    LEAVE 0

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lcolor_modes:
    .quad Lj_hs, Lj_xy, Lj_rgb, Lj_rgbw, Lj_rgbww, 0

.section __TEXT,__cstring,cstring_literals
Ls_NSTextField:       .asciz "NSTextField"
Ls_NSSecureTextField: .asciz "NSSecureTextField"
Ls_alloc:             .asciz "alloc"
Ls_release:           .asciz "release"
Ls_initWithFrame:     .asciz "initWithFrame:"
Ls_setPlaceholderString: .asciz "setPlaceholderString:"
Ls_setStringValue:    .asciz "setStringValue:"
Ls_stringValue:       .asciz "stringValue"
Ls_UTF8String:        .asciz "UTF8String"
Ls_connect:           .asciz "Connect"
Ls_cancel:            .asciz "Cancel"
Ls_GET:               .asciz "GET"
Ls_PUT:               .asciz "PUT"
Ls_POST:              .asciz "POST"
Lf_bearer:            .asciz "Bearer %s"
Lf_tag:               .asciz "c%c%ld"
Lf_ld:                .asciz "%ld"
Lf_s:                 .asciz "%s"
Lf_http_s:            .asciz "http://%s"
Lf_hdmi:              .asciz "HDMI %ld"
Ls_scheme:            .asciz "://"
Ls_tv:                .asciz "TV"
Ls_empty:             .asciz ""
Ls_comma:             .asciz ", "

Ls_kc_lifx:           .asciz "asmmesh.lifx"
Ls_kc_govee:          .asciz "asmmesh.govee"
Ls_kc_ha:             .asciz "asmmesh.homeassistant"
Ls_pref_ha:           .asciz "ha_url"
Ls_tag_lifx:          .asciz "cx"
Ls_tag_govee:         .asciz "cg"
Ls_tag_ha:            .asciz "ca"
Ls_lifx_all:          .asciz "https://api.lifx.com/v1/lights/all"
Lf_lifx_state:        .asciz "https://api.lifx.com/v1/lights/id:%s/state"
Lf_lifx_delta:        .asciz "https://api.lifx.com/v1/lights/id:%s/state/delta"
Ls_govee_devices:     .asciz "https://openapi.api.govee.com/router/api/v1/user/devices"
Ls_govee_control:     .asciz "https://openapi.api.govee.com/router/api/v1/device/control"
Ls_govee_header:      .asciz "Govee-API-Key"
Lf_ha_states:         .asciz "%s/api/states"
Lf_ha_template:       .asciz "%s/api/template"
Ls_ha_areas_body:     .asciz "{\"template\":\"{% for s in states %}{{ s.entity_id }}={{ area_name(s.entity_id) }};{% endfor %}\"}"
Ls_tag_areas:         .asciz "ct"
Ls_None:              .asciz "None"
Ls_length:            .asciz "length"
Ls_bytes:             .asciz "bytes"
Lf_ha_state:          .asciz "%s/api/states/%s"
Lf_ha_service:        .asciz "%s/api/services/%s/%s"
Lf_ha_body:           .asciz "{\"entity_id\":\"%s\"%s}"
Ls_ha_default:        .asciz "http://homeassistant.local:8123"

Lx_lifx_on:           .asciz "{\"power\":\"on\"}"
Lx_lifx_off:          .asciz "{\"power\":\"off\"}"
Lx_lifx_up:           .asciz "{\"power\":\"on\",\"brightness\":0.2}"
Lx_lifx_down:         .asciz "{\"brightness\":-0.2}"
Lx_lifx_bri:          .asciz "{\"power\":\"on\",\"brightness\":%ld.%02ld}"
Lx_lifx_hue:          .asciz "{\"power\":\"on\",\"color\":\"hue:%ld saturation:1.0\"}"
Lx_lifx_kelvin:       .asciz "{\"power\":\"on\",\"color\":\"kelvin:%ld saturation:0\"}"
Lf_govee_body:        .asciz "{\"requestId\":\"asmmesh\",\"payload\":{\"sku\":\"%s\",\"device\":\"%s\",\"capability\":{\"type\":\"devices.capabilities.%s\",\"instance\":\"%s\",\"value\":%ld}}}"
Lg_on_off:            .asciz "on_off"
Lg_range:             .asciz "range"
Lg_color_setting:     .asciz "color_setting"
Lg_power:             .asciz "powerSwitch"
Lg_brightness:        .asciz "brightness"
Lg_rgb:               .asciz "colorRgb"
Lg_ct:                .asciz "colorTemperatureK"

Lx_bri_pct:           .asciz ",\"brightness_pct\":%ld"
Lx_hs:                .asciz ",\"hs_color\":[%ld,100]"
Lx_kelvin:            .asciz ",\"color_temp_kelvin\":%ld"
Lx_step_up:           .asciz ",\"brightness_step_pct\":20"
Lx_step_down:         .asciz ",\"brightness_step_pct\":-20"
Lx_volume:            .asciz ",\"volume_level\":%ld.%02ld"
Lx_muted:             .asciz ",\"is_volume_muted\":true"
Lx_unmuted:           .asciz ",\"is_volume_muted\":false"
Lx_source:            .asciz ",\"source\":\"%s\""
Lx_heat:              .asciz ",\"temperature\":%ld,\"hvac_mode\":\"heat\""
Lx_cool:              .asciz ",\"temperature\":%ld,\"hvac_mode\":\"cool\""
Lx_temp:              .asciz ",\"temperature\":%ld"
Lx_hvac:              .asciz ",\"hvac_mode\":\"%s\""
Lx_pct:               .asciz ",\"percentage\":%ld"
Lx_position:          .asciz ",\"position\":%ld"
Lsv_turn_on:          .asciz "turn_on"
Lsv_turn_off:         .asciz "turn_off"
Lsv_lock:             .asciz "lock"
Lsv_unlock:           .asciz "unlock"
Lsv_volume_set:       .asciz "volume_set"
Lsv_volume_up:        .asciz "volume_up"
Lsv_volume_down:      .asciz "volume_down"
Lsv_volume_mute:      .asciz "volume_mute"
Lsv_next:             .asciz "media_next_track"
Lsv_previous:         .asciz "media_previous_track"
Lsv_select_source:    .asciz "select_source"
Lsv_play:             .asciz "media_play"
Lsv_pause:            .asciz "media_pause"
Lsv_stop:             .asciz "media_stop"
Lsv_open_cover:       .asciz "open_cover"
Lsv_close_cover:      .asciz "close_cover"
Lsv_open_valve:       .asciz "open_valve"
Lsv_close_valve:      .asciz "close_valve"
Lsv_set_pos:          .asciz "set_cover_position"
Lsv_set_temp:         .asciz "set_temperature"
Lsv_set_hvac:         .asciz "set_hvac_mode"
Lsv_set_pct:          .asciz "set_percentage"
Lsv_start:            .asciz "start"
Lsv_return:           .asciz "return_to_base"

Ld_light:             .asciz "light"
Ld_switch:            .asciz "switch"
Ld_input_bool:        .asciz "input_boolean"
Ld_fan:               .asciz "fan"
Ld_cover:             .asciz "cover"
Ld_lock:              .asciz "lock"
Ld_climate:           .asciz "climate"
Ld_media:             .asciz "media_player"
Ld_vacuum:            .asciz "vacuum"
Ld_scene:             .asciz "scene"
Ld_script:            .asciz "script"
Ld_valve:             .asciz "valve"
Ld_humidifier:        .asciz "humidifier"
Ld_sensor:            .asciz "sensor"

Lj_id:                .asciz "id"
Lj_label:             .asciz "label"
Lj_power:             .asciz "power"
Lj_brightness:        .asciz "brightness"
Lj_product:           .asciz "product"
Lj_capabilities:      .asciz "capabilities"
Lj_has_color:         .asciz "has_color"
Lj_has_ct:            .asciz "has_variable_color_temp"
Lj_on:                .asciz "on"
Lj_off:               .asciz "off"
Lj_data:              .asciz "data"
Lj_instance:          .asciz "instance"
Lj_device:            .asciz "device"
Lj_deviceName:        .asciz "deviceName"
Lj_sku:               .asciz "sku"
Lj_code:              .asciz "code"
Lj_message:           .asciz "message"
Lj_msg:               .asciz "msg"
Lj_error:             .asciz "error"
Lj_entity_id:         .asciz "entity_id"
Lj_state:             .asciz "state"
Lj_attributes:        .asciz "attributes"
Lj_friendly:          .asciz "friendly_name"
Lj_unit:              .asciz "unit_of_measurement"
Lj_color_modes:       .asciz "supported_color_modes"
Lj_hs:                .asciz "hs"
Lj_xy:                .asciz "xy"
Lj_rgb:               .asciz "rgb"
Lj_rgbw:              .asciz "rgbw"
Lj_rgbww:             .asciz "rgbww"
Lj_color_temp:        .asciz "color_temp"
Lj_white:             .asciz "white"
Lj_device_class:      .asciz "device_class"
Lj_garage:            .asciz "garage"
Lj_gate:              .asciz "gate"
Lj_hvac_modes:        .asciz "hvac_modes"
Lj_heat_cool:         .asciz "heat_cool"
Lj_open:              .asciz "open"
Lj_opening:           .asciz "opening"
Lj_closed:            .asciz "closed"
Lj_closing:           .asciz "closing"
Lj_locked:            .asciz "locked"
Lj_unlocked:          .asciz "unlocked"
Lj_auto:              .asciz "auto"
Lj_tv:                .asciz "tv"
Lj_temperature:       .asciz "temperature"
Lj_humidity:          .asciz "humidity"
Lj_energy:            .asciz "energy"
Lj_current_temp:      .asciz "current_temperature"
Lj_hvac_action:       .asciz "hvac_action"
Lj_position:          .asciz "current_position"
Lj_volume_level:      .asciz "volume_level"
Lj_source:            .asciz "source"
Lj_media_title:       .asciz "media_title"
Lj_battery_level:     .asciz "battery_level"
Lj_percentage:        .asciz "percentage"
Ls_now:               .asciz "now "
Ls_set_to:            .asciz "set to "
Ls_deg:               .asciz "\302\260"
Ls_pct:               .asciz "%"
Ls_pct_open:          .asciz "% open"
Ls_pct_bat:           .asciz "% battery"
Ls_pct_hum:           .asciz "% humidity"
Ls_volume_sp:         .asciz "volume "
Ls_playing:           .asciz "playing "
Ls_fan_sp:            .asciz "fan "
Ls_status_line:       .asciz "\302\267 %s: %s"

Ls_n_lifx:            .asciz "LIFX"
Ls_n_govee:           .asciz "Govee"
Ls_n_ha:              .asciz "Home Assistant"
Ls_w_lifx:            .asciz "lifx"
Ls_w_govee:           .asciz "govee"
Ls_w_ha:              .asciz "home assistant"
Ls_lifx_title:        .asciz "Connect LIFX"
Ls_lifx_info:         .asciz "1. Go to cloud.lifx.com and sign in.\n2. Click your email address \342\200\272 Personal access tokens \342\200\272 Generate New Token.\n3. Paste the token here with Cmd-V.\n\nIt's kept in your Keychain."
Ls_lifx_ph:           .asciz "LIFX personal access token"
Ls_govee_title:       .asciz "Connect Govee"
Ls_govee_info:        .asciz "1. In the Govee Home app: Profile \342\200\272 Settings \342\200\272 Apply for API Key.\n2. Govee emails you the key within a few minutes.\n3. Paste it here with Cmd-V.\n\nIt's kept in your Keychain."
Ls_govee_ph:          .asciz "Govee API key"
Ls_ha_title:          .asciz "Connect Home Assistant"
Ls_ha_info1:          .asciz "Your Home Assistant's address, as you'd type it in a browser (e.g. http://homeassistant.local:8123)."
Ls_ha_info2:          .asciz "In Home Assistant: click your name (bottom left) \342\200\272 Security \342\200\272 Long-lived access tokens \342\200\272 Create token. Name it asmmesh and paste it here with Cmd-V.\n\nIt's kept in your Keychain."
Ls_ha_ph:             .asciz "Long-lived access token"
Ls_checking:          .asciz "\302\267 Checking %s\342\200\246"
Ls_cancelled:         .asciz "\302\267 Nothing was changed."
Ls_need:              .asciz "\302\267 %s isn't connected yet. Say \342\200\234connect %s\342\200\235."
Ls_unreach:           .asciz "\302\267 Can't reach %s: %s"
Ls_badkey:            .asciz "\302\267 %s didn't accept the key. Say \342\200\234connect %s\342\200\235 to enter a new one."
Ls_refused:           .asciz "\302\267 %s answered HTTP %ld."
Ls_cmd_http:          .asciz "\302\267 %s refused that (HTTP %ld). %s"
Ls_cmd_net:           .asciz "\302\267 %s didn't answer: %s"
Ls_lifx_ready:        .asciz "\302\267 LIFX connected: %ld lights. Try \342\200\234all lights blue\342\200\235."
Ls_govee_ready:       .asciz "\302\267 Govee connected: %ld devices."
Ls_ha_ready:          .asciz "\302\267 Home Assistant connected: %ld things you can control or ask about. Say \342\200\234devices\342\200\235 to see them."
