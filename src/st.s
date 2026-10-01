// st.s — SmartThings and Apple Home.
//
// SmartThings: its official REST API (api.smartthings.com) with a personal
// access token you paste once ("connect smartthings" or Mesh > Connect
// SmartThings). The token lives in your login Keychain, never in a file.
// Every capability asmmesh knows is mapped: lights (switch, level, colour,
// colour temperature), locks, TVs (power, volume, mute, channel, input, media
// keys, apps), blinds, thermostats, fans, garage doors, valves, robot
// vacuums, and sensors for "status". Scenes run by their full name.
//
// Apple Home: macOS has no public HomeKit API for apps like this one, but the
// Shortcuts app can drive every Home accessory and scene (Matter included).
// asmmesh lists your shortcuts with /usr/bin/shortcuts and runs one when you
// say its name.

.include "macros.inc"

.set SC_MAX, 24

// D_AUX flags for SmartThings devices
.set F_SHADE_LEVEL, 2
.set F_HEAT_SP,     4
.set F_COOL_SP,     8
.set F_GARAGE_DC,   16
.set F_TMODE,       32
.set F_STD_INPUT,   64

.data
.p2align 3
_g_sc_count:   .quad 0
_g_st_scenes:  .quad -1               // scenes found last time (-1 = never asked)
.zerofill __DATA,__bss,_g_st_token,256,4
.zerofill __DATA,__bss,_g_st_auth,300,4
.zerofill __DATA,__bss,_g_st_url,256,4
.zerofill __DATA,__bss,_g_st_body,512,4
.zerofill __DATA,__bss,_g_st_args,160,4
.zerofill __DATA,__bss,_g_st_word,40,4
.zerofill __DATA,__bss,_g_st_line,480,4
.zerofill __DATA,__bss,_g_st_val,64,4

.section __TEXT,__const
.p2align 3
Lf_field:     .double 0.0, 0.0, 320.0, 24.0

.section __DATA,__const
.p2align 3
// SmartThings capability -> CAP_ bits, D_AUX flags
Lst_caps:
    .quad Lc_switch,        CAP_ON, 0
    .quad Lc_level,         CAP_LEVEL, 0
    .quad Lc_color,         CAP_COLOR, 0
    .quad Lc_ct,            CAP_CT, 0
    .quad Lc_lock,          (CAP_LOCK | CAP_STATUS), 0
    .quad Lc_volume,        CAP_VOLUME, 0
    .quad Lc_mute,          CAP_MUTE, 0
    .quad Lc_channel,       CAP_CHANNEL, 0
    .quad Lc_input,         CAP_INPUT, F_STD_INPUT
    .quad Lc_svd_input,     CAP_INPUT, 0
    .quad Lc_playback,      CAP_MEDIA, 0
    .quad Lc_launchapp,     CAP_APPS, 0
    .quad Lc_shade,         (CAP_SHADE | CAP_STATUS), 0
    .quad Lc_shadelevel,    CAP_SHADE, F_SHADE_LEVEL
    .quad Lc_heatsp,        (CAP_THERMO | CAP_STATUS), F_HEAT_SP
    .quad Lc_coolsp,        (CAP_THERMO | CAP_STATUS), F_COOL_SP
    .quad Lc_tmode,         CAP_THERMO, F_TMODE
    .quad Lc_temp,          (CAP_TEMP | CAP_STATUS), 0
    .quad Lc_humidity,      CAP_STATUS, 0
    .quad Lc_fanspeed,      CAP_FAN, 0
    .quad Lc_door,          (CAP_GARAGE | CAP_STATUS), 0
    .quad Lc_garage,        (CAP_GARAGE | CAP_STATUS), F_GARAGE_DC
    .quad Lc_valve,         (CAP_VALVE | CAP_STATUS), 0
    .quad Lc_robot,         CAP_VACUUM, 0
    .quad Lc_contact,       CAP_STATUS, 0
    .quad Lc_motion,        CAP_STATUS, 0
    .quad Lc_battery,       CAP_STATUS, 0
    .quad Lc_power,         (CAP_POWER | CAP_STATUS), 0
    .quad Lc_energy,        (CAP_POWER | CAP_STATUS), 0
    .quad Lc_water,         CAP_STATUS, 0
    .quad Lc_smoke,         CAP_STATUS, 0
    .quad 0, 0, 0

// per action: capability, command, argument format, argument kind
//   kind 0: none   1: the number   2: a string made by the override code
Lst_acts:
    .quad 0, 0, 0, 0                                    // NONE
    .quad Lc_switch, Lm_on, Ls_empty, 0                 // ON
    .quad Lc_switch, Lm_off, Ls_empty, 0                // OFF
    .quad Lc_level, Lm_setLevel, Lg_num, 1              // LEVEL
    .quad Lc_color, Lm_setColor, Lg_color, 1            // COLOR
    .quad Lc_ct, Lm_setCT, Lg_num, 1                    // CT
    .quad Lc_lock, Lm_lock, Ls_empty, 0                 // LOCK
    .quad Lc_lock, Lm_unlock, Ls_empty, 0               // UNLOCK
    .quad 0, 0, 0, 0                                    // RUN
    .quad 0, 0, 0, 0                                    // LIST
    .quad 0, 0, 0, 0                                    // HELP
    .quad 0, 0, 0, 0                                    // PAIR
    .quad 0, 0, 0, 0                                    // REFRESH
    .quad 0, 0, 0, 0                                    // BRIGHTER (made a level)
    .quad 0, 0, 0, 0                                    // DIMMER
    .quad 0, 0, 0, 0                                    // CONNECT
    .quad Lc_volume, Lm_setVolume, Lg_num, 1            // VOLUME
    .quad Lc_volume, Lm_volumeUp, Ls_empty, 0           // VOLUP
    .quad Lc_volume, Lm_volumeDown, Ls_empty, 0         // VOLDOWN
    .quad Lc_mute, Lm_mute, Ls_empty, 0                 // MUTE
    .quad Lc_mute, Lm_unmute, Ls_empty, 0               // UNMUTE
    .quad Lc_channel, Lm_setChannel, Lg_str, 2          // CHANNEL
    .quad Lc_channel, Lm_channelUp, Ls_empty, 0         // CHUP
    .quad Lc_channel, Lm_channelDown, Ls_empty, 0       // CHDOWN
    .quad Lc_input, Lm_setInput, Lg_str, 2              // INPUT
    .quad Lc_playback, Lm_play, Ls_empty, 0             // PLAY
    .quad Lc_playback, Lm_pause, Ls_empty, 0            // PAUSE
    .quad Lc_playback, Lm_stop, Ls_empty, 0             // STOP
    .quad Lc_playback, Lm_ffwd, Ls_empty, 0             // FFWD
    .quad Lc_playback, Lm_rewind, Ls_empty, 0           // REWIND
    .quad Lc_launchapp, Lm_launchApp, Lg_str, 2         // APP
    .quad Lc_shade, Lm_open, Ls_empty, 0                // OPEN
    .quad Lc_shade, Lm_close, Ls_empty, 0               // CLOSE
    .quad Lc_heatsp, Lm_setHeat, Lg_num, 1              // HEATSET
    .quad Lc_coolsp, Lm_setCool, Lg_num, 1              // COOLSET
    .quad Lc_heatsp, Lm_setHeat, Lg_num, 1              // TEMPSET
    .quad Lc_tmode, Lm_setMode, Lg_str, 2               // TMODE
    .quad Lc_fanspeed, Lm_setFanSpeed, Lg_num, 1        // FANSPEED
    .quad Lc_robot, Lm_setRobot, Lg_cleaning, 0         // VACSTART
    .quad Lc_robot, Lm_setRobot, Lg_homing, 0           // VACHOME
    .quad 0, 0, 0, 0                                    // STATUS
    .quad 0, 0, 0, 0                                    // KEY

Lst_open_caps:
    .quad Lc_contact, La_contact
    .quad Lc_door, La_door
    .quad Lc_garage, La_door
    .quad Lc_shade, La_shade
    .quad Lc_valve, La_valve
    .quad 0, 0

// status report: capability, attribute, text before, text after
Lst_report:
    .quad Lc_switch, La_switch, Ls_empty, Ls_empty
    .quad Lc_level, La_level, Ls_empty, Ls_pct
    .quad Lc_lock, La_lock, Ls_empty, Ls_empty
    .quad Lc_temp, La_temperature, Ls_empty, Ls_deg
    .quad Lc_humidity, La_humidity, Ls_empty, Ls_pct_hum
    .quad Lc_heatsp, La_heatsp, Ls_heat_to, Ls_deg
    .quad Lc_coolsp, La_coolsp, Ls_cool_to, Ls_deg
    .quad Lc_tmode, La_tmode, Ls_mode_sp, Ls_empty
    .quad Lc_contact, La_contact, Ls_empty, Ls_empty
    .quad Lc_motion, La_motion, Ls_motion_sp, Ls_empty
    .quad Lc_battery, La_battery, Ls_empty, Ls_pct_bat
    .quad Lc_volume, La_volume, Ls_volume_sp, Ls_empty
    .quad Lc_mute, La_mute, Ls_empty, Ls_empty
    .quad Lc_channel, La_channel, Ls_channel_sp, Ls_empty
    .quad Lc_input, La_input, Ls_input_sp, Ls_empty
    .quad Lc_shade, La_shade, Ls_empty, Ls_empty
    .quad Lc_shadelevel, La_shadelevel, Ls_empty, Ls_pct_open
    .quad Lc_door, La_door, Ls_door_sp, Ls_empty
    .quad Lc_garage, La_door, Ls_door_sp, Ls_empty
    .quad Lc_valve, La_valve, Ls_valve_sp, Ls_empty
    .quad Lc_fanspeed, La_fanspeed, Ls_fan_sp, Ls_empty
    .quad Lc_power, La_power, Ls_empty, Ls_empty
    .quad Lc_energy, La_energy, Ls_empty, Ls_empty
    .quad Lc_water, La_water, Ls_water_sp, Ls_empty
    .quad Lc_smoke, La_smoke, Ls_smoke_sp, Ls_empty
    .quad Lc_robot, La_robot, Ls_empty, Ls_empty
    .quad 0, 0, 0, 0

.text
.p2align 2

// ===========================================================================
// SmartThings
// ===========================================================================

// void _st_make_auth(void) — "Bearer <token>"
_st_make_auth:
    ENTER 0
    ADRL x0, _g_st_auth
    mov  x1, #300
    ADRL x2, Lf_bearer
    ADRL x3, _g_st_token
    bl   _sfmt
    LEAVE 0

// void _st_kc_read(void) — the saved token (any thread: the Keychain may ask first)
.globl _st_kc_read
_st_kc_read:
    ENTER 0
    ADRL x0, Ls_kc_service
    ADRL x1, _g_st_token
    mov  x2, #256
    bl   _kc_get
    LEAVE 0

// void _st_init(void) — main thread, after _st_kc_read
.globl _st_init
_st_init:
    ENTER 0
    ADRL x8, _g_st_token
    ldrb w9, [x8]
    cbz  w9, Lsi_done
    bl   _st_make_auth
    bl   _st_load
Lsi_done:
    LEAVE 0

// void _st_load(void) — devices, then scenes when the devices arrive
.globl _st_load
_st_load:
    ENTER 0
    ADRL x8, _g_st_token
    ldrb w9, [x8]
    cbz  w9, Lsl_done
    ADRL x0, Ls_GET
    ADRL x1, Ls_devices_url
    mov  x2, #0
    ADRL x3, _g_st_auth
    ADRL x4, Ls_tag_load
    bl   _http
Lsl_done:
    LEAVE 0

// void _st_connect_dialog(void) — paste a personal access token
.globl _st_connect_dialog
_st_connect_dialog:
    ENTER 0
    CLS  Ls_NSSecureTextField
    MSG0 Ls_alloc
    mov  x19, x0
    SELX1 Ls_initWithFrame
    mov  x0, x19
    ADRL x8, Lf_field
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x19, x0
    ADRL x0, Ls_token_ph
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setPlaceholderString
    ADRL x0, Ls_conn_msg
    ADRL x1, Ls_conn_info
    ADRL x2, Ls_connect
    mov  x3, x19
    ADRL x4, Ls_cancel
    bl   _alert_run
    cbz  x0, Lsc_release
    mov  x0, x19
    MSG0 Ls_stringValue
    MSG0 Ls_UTF8String
    cbz  x0, Lsc_empty
    mov  x1, x0
    ADRL x0, _g_st_token
    mov  x2, #250
    bl   _token_clean
    cbz  x0, Lsc_empty
    ADRL x0, Ls_kc_service
    ADRL x1, _g_st_token
    bl   _kc_set
    bl   _st_make_auth
    ADRL x0, Ls_checking
    bl   _home_say0
    bl   _st_load
Lsc_release:
    mov  x0, x19
    MSG0 Ls_release
    LEAVE 0
Lsc_empty:
    ADRL x0, Ls_no_token
    bl   _home_say0
    b    Lsc_release

// size_t _token_clean(char *dst, const char *src, size_t max)
//   Keeps only the characters a token is made of (letters, digits, - _ .),
//   so a stray space, newline or "Bearer " pasted along with it can't break it.
.globl _token_clean
_token_clean:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
Ltc_space:
    ldrb w9, [x20]
    cmp  w9, #' '
    b.eq Ltc_skip
    cmp  w9, #9
    b.eq Ltc_skip
    cmp  w9, #10
    b.eq Ltc_skip
    cmp  w9, #13
    b.ne Ltc_bearer
Ltc_skip:
    add  x20, x20, #1
    b    Ltc_space
Ltc_bearer:
    mov  x0, x20
    ADRL x1, Ls_bearer_sp
    mov  x2, #7
    bl   _strncasecmp
    cbnz w0, Ltc_copy
    add  x20, x20, #7
Ltc_copy:
    mov  x22, #0                      // written
Ltc_loop:
    cmp  x22, x21
    b.hs Ltc_end
    ldrb w9, [x20], #1
    cbz  w9, Ltc_end
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.ls Ltc_keep
    orr  w10, w9, #0x20               // letters, either case
    sub  w10, w10, #'a'
    cmp  w10, #25
    b.ls Ltc_keep
    cmp  w9, #'-'
    b.eq Ltc_keep
    cmp  w9, #'_'
    b.eq Ltc_keep
    cmp  w9, #'.'
    b.ne Ltc_loop                     // anything else is dropped
Ltc_keep:
    strb w9, [x19, x22]
    add  x22, x22, #1
    b    Ltc_loop
Ltc_end:
    strb wzr, [x19, x22]
    mov  x0, x22
    LEAVE 0

// long _st_set(long idx, long action, long value) -> 1 sent, 0 can't, 2 said why not
.globl _st_set
_st_set:
    ENTER 32                          // [96] arg format  [104] arg kind  [112] string arg
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_st_token
    ldrb w9, [x8]
    cbz  w9, Lss_noconn
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ldr  x9, [x22, #D_KIND]
    cmp  x9, #K_ST_SCENE
    b.eq Lss_scene

    cmp  x20, #A_BRIGHTER             // relative changes become a level
    b.eq Lss_rel
    cmp  x20, #A_DIMMER
    b.ne Lss_lookup
Lss_rel:
    ldr  x9, [x22, #D_LEVEL]
    tbz  x9, #63, Lss_rel_known
    mov  x9, #50
Lss_rel_known:
    cmp  x20, #A_BRIGHTER
    b.ne Lss_rel_down
    add  x9, x9, #25
    cmp  x9, #100
    mov  x10, #100
    csel x9, x10, x9, hi
    b    Lss_rel_set
Lss_rel_down:
    subs x9, x9, #25
    b.gt Lss_rel_set
    mov  x9, #1
Lss_rel_set:
    mov  x21, x9
    mov  x20, #A_LEVEL

Lss_lookup:
    cmp  x20, #A_LAST
    b.hi Lss_cant
    ADRL x8, Lst_acts
    add  x8, x8, x20, lsl #5
    ldp  x23, x24, [x8]               // capability, command
    cbz  x23, Lss_cant
    ldp  x9, x10, [x8, #16]
    stp  x9, x10, [sp, #96]
    str  xzr, [sp, #112]
    ldr  x11, [x22, #D_CAPS]
    ldr  x12, [x22, #D_AUX]           // flags

    // overrides
    cmp  x20, #A_LEVEL
    b.eq Lso_level
    cmp  x20, #A_COLOR
    b.eq Lso_color
    cmp  x20, #A_CHANNEL
    b.eq Lso_channel
    cmp  x20, #A_INPUT
    b.eq Lso_input
    cmp  x20, #A_APP
    b.eq Lso_app
    cmp  x20, #A_OPEN
    b.eq Lso_openclose
    cmp  x20, #A_CLOSE
    b.eq Lso_openclose
    cmp  x20, #A_TEMPSET
    b.eq Lso_tempset
    cmp  x20, #A_TMODE
    b.eq Lso_tmode
    cmp  x20, #A_MUTE
    b.eq Lso_mute
    cmp  x20, #A_UNMUTE
    b.eq Lso_mute
    b    Lss_build
Lso_level:
    tst  x11, #CAP_LEVEL
    b.ne Lss_build
    tst  x12, #F_SHADE_LEVEL          // "blinds 40%"
    b.eq Lso_level_shade
    ADRL x23, Lc_shadelevel
    ADRL x24, Lm_setShadeLevel
    b    Lss_build
Lso_level_shade:                      // no level: 0% closes, anything else opens
    tst  x11, #CAP_SHADE
    b.eq Lss_cant
    ADRL x23, Lc_shade
    ADRL x24, Lm_open
    ADRL x9, Lm_close
    cmp  x21, #0
    csel x24, x9, x24, eq
    ADRL x9, Ls_empty
    str  x9, [sp, #96]
    str  xzr, [sp, #104]
    b    Lss_build
Lso_color:                            // SmartThings hue is 0..100
    mov  x10, #100
    mul  x21, x21, x10
    mov  x10, #360
    udiv x21, x21, x10
    b    Lss_build
Lso_channel:
    ADRL x0, _g_st_word
    mov  x1, #40
    ADRL x2, Lf_ld
    mov  x3, x21
    bl   _sfmt
    ADRL x9, _g_st_word
    str  x9, [sp, #112]
    b    Lss_build
Lso_input:
    tst  x12, #F_STD_INPUT
    b.ne Lso_input_word
    ADRL x23, Lc_svd_input
Lso_input_word:
    ADRL x9, Ls_digitalTv
    cbz  x21, Lso_input_set
    ADRL x0, _g_st_word
    mov  x1, #40
    ADRL x2, Lf_hdmi
    mov  x3, x21
    bl   _sfmt
    ADRL x9, _g_st_word
Lso_input_set:
    str  x9, [sp, #112]
    b    Lss_build
Lso_app:
    mov  x0, x21
    mov  x1, #3                       // Tizen id
    bl   _app_field
    str  x0, [sp, #112]
    b    Lss_build
Lso_openclose:
    ADRL x24, Lm_open
    ADRL x9, Lm_close
    cmp  x20, #A_CLOSE
    csel x24, x9, x24, eq
    tst  x11, #CAP_GARAGE
    b.eq Lso_oc_valve
    ADRL x23, Lc_door
    tst  x12, #F_GARAGE_DC
    b.eq Lss_build
    ADRL x23, Lc_garage
    b    Lss_build
Lso_oc_valve:
    tst  x11, #CAP_VALVE
    b.eq Lss_build                    // blinds: windowShade from the table
    ADRL x23, Lc_valve
    b    Lss_build
Lso_tempset:
    tst  x12, #F_HEAT_SP
    b.ne Lss_build
    ADRL x23, Lc_coolsp
    ADRL x24, Lm_setCool
    b    Lss_build
Lso_tmode:
    ADRL x8, _g_cmd_word              // "off" "heat" "cool" "auto"
    ldr  x9, [x8]
    cbz  x9, Lss_cant
    str  x9, [sp, #112]
    b    Lss_build
Lso_mute:
    tst  x11, #CAP_MUTE
    b.eq Lss_cant

Lss_build:
    ldp  x2, x9, [sp, #96]            // argument text
    mov  x3, x21
    cmp  x9, #2
    b.ne Lss_args
    ldr  x3, [sp, #112]
Lss_args:
    ADRL x0, _g_st_args
    mov  x1, #160
    bl   _sfmt
    ADRL x0, _g_st_body
    mov  x1, #512
    ADRL x2, Lf_st_cmd
    mov  x3, x23
    mov  x4, x24
    ADRL x5, _g_st_args
    bl   _sfmt
    ADRL x0, _g_st_url
    mov  x1, #256
    ADRL x2, Lf_command_url
    add  x3, x22, #D_ID
    bl   _sfmt
    ADRL x0, Ls_POST
    ADRL x1, _g_st_url
    ADRL x2, _g_st_body
    ADRL x3, _g_st_auth
    ADRL x4, Ls_tag_cmd
    bl   _http
    // what we now believe
    cmp  x20, #A_ON
    b.eq Lss_on
    cmp  x20, #A_OFF
    b.eq Lss_off
    cmp  x20, #A_LEVEL
    b.ne Lss_sent
    ldr  x11, [x22, #D_CAPS]
    tst  x11, #CAP_LEVEL
    b.eq Lss_sent
    mov  x0, x19
    mov  x1, #1
    mov  x2, x21
    bl   _dev_state
    b    Lss_sent
Lss_on:
    mov  x0, x19
    mov  x1, #1
    ldr  x2, [x22, #D_LEVEL]
    bl   _dev_state
    b    Lss_sent
Lss_off:
    mov  x0, x19
    mov  x1, #0
    ldr  x2, [x22, #D_LEVEL]
    bl   _dev_state
Lss_sent:
    mov  x0, #1
    LEAVE 32
Lss_scene:
    ADRL x0, _g_st_url
    mov  x1, #256
    ADRL x2, Lf_scene_url
    add  x3, x22, #D_ID
    bl   _sfmt
    ADRL x0, Ls_POST
    ADRL x1, _g_st_url
    mov  x2, #0
    ADRL x3, _g_st_auth
    ADRL x4, Ls_tag_scene
    bl   _http
    mov  x0, #1
    LEAVE 32
Lss_cant:
    mov  x0, #0
    LEAVE 32
Lss_noconn:
    ADRL x0, Ls_need_token
    bl   _home_say0
    mov  x0, #2
    LEAVE 32

// void _st_status(long idx) — ask SmartThings for everything the device reports
.globl _st_status
_st_status:
    ENTER 32                          // [96] tag
    mov  x19, x0
    ADRL x8, _g_st_token
    ldrb w9, [x8]
    cbz  w9, Lsst_noconn
    ADRL x8, _g_devs
    add  x20, x8, x19, lsl #DEV_SHIFT
    ADRL x0, _g_st_url
    mov  x1, #256
    ADRL x2, Lf_status_url
    add  x3, x20, #D_ID
    bl   _sfmt
    add  x0, sp, #96
    mov  x1, #32
    ADRL x2, Lf_tag_status
    mov  x3, x19
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_st_url
    mov  x2, #0
    ADRL x3, _g_st_auth
    add  x4, sp, #96
    bl   _http
    LEAVE 32
Lsst_noconn:
    ADRL x0, Ls_need_token
    bl   _home_say0
    LEAVE 32

// void _st_response(const char *tag, id json, long status, NSError *err, NSData *raw)
.globl _st_response
_st_response:
    ENTER 32                          // [96] items  [104] n  [112] i  [120] taken
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    cbnz x3, Lsr_neterr
    ldrb w22, [x19, #1]
    cmp  x21, #401
    b.eq Lsr_auth
    cmp  x21, #403
    b.eq Lsr_scope
    cmp  x21, #300
    b.hs Lsr_http
    cmp  w22, #'l'
    b.eq Lsr_list
    cmp  w22, #'n'
    b.eq Lsr_scenes
    cmp  w22, #'s'
    b.eq Lsr_status
    cmp  w22, #'q'
    b.eq Lsr_quiet
    cmp  w22, #'o'
    b.eq Lsr_locations
    cmp  w22, #'r'
    b.eq Lsr_rooms
    LEAVE 32                          // a command that went through
Lsr_http:
    mov  x0, x20                      // {"error":{"message":"..."}} if SmartThings sent one
    ADRL x1, Ls_j_error
    bl   _jget
    ADRL x1, Ls_j_message
    bl   _jget
    bl   _jstr
    mov  x2, x0
    cbnz x2, Lsr_http_say
    ADRL x2, Ls_empty
Lsr_http_say:
    mov  x1, x21
    ADRL x0, Ls_st_refused
    bl   _home_say
    LEAVE 32
Lsr_scope:
    cmp  w22, #'n'                    // scenes and rooms need their own tick-boxes; quietly skip
    b.eq Lsr_done
    cmp  w22, #'o'
    b.eq Lsr_done
    cmp  w22, #'r'
    b.eq Lsr_done
    ADRL x0, Ls_st_scope
    bl   _home_say0
    LEAVE 32
Lsr_neterr:
    mov  x0, x3
    bl   _err_cstr
    mov  x1, x0
    ADRL x0, Ls_st_unreach
    bl   _home_say
    LEAVE 32
Lsr_auth:
    cmp  w22, #'n'
    b.eq Lsr_done
    cmp  w22, #'o'
    b.eq Lsr_done
    cmp  w22, #'r'
    b.eq Lsr_done
    ADRL x0, Ls_st_badtoken
    bl   _home_say0
    LEAVE 32

Lsr_list:
    mov  x0, x20
    ADRL x1, Ls_j_items
    bl   _jget
    str  x0, [sp, #96]
    bl   _jcount
    str  x0, [sp, #104]
    str  xzr, [sp, #112]
    str  xzr, [sp, #120]
Lsr_loop:
    ldr  x9, [sp, #112]
    ldr  x10, [sp, #104]
    cmp  x9, x10
    b.hs Lsr_summary
    ldr  x0, [sp, #96]
    mov  x1, x9
    bl   _jat
    bl   _st_take
    ldr  x9, [sp, #120]
    add  x9, x9, x0
    str  x9, [sp, #120]
    ldr  x9, [sp, #112]
    add  x9, x9, #1
    str  x9, [sp, #112]
    b    Lsr_loop
Lsr_summary:
    ldr  x1, [sp, #120]
    ldr  x2, [sp, #104]
    ADRL x0, Ls_st_ready
    cbnz x1, Lsr_say
    ADRL x0, Ls_st_none
    mov  x1, x2
    cbnz x2, Lsr_say
    ADRL x0, Ls_st_empty
Lsr_say:
    bl   _home_say
    bl   _ui_lists_changed
    ADRL x0, Ls_GET                   // now the scenes
    ADRL x1, Ls_scenes_url
    mov  x2, #0
    ADRL x3, _g_st_auth
    ADRL x4, Ls_tag_scenes
    bl   _http
    ADRL x0, Ls_GET                   // and the rooms: locations first
    ADRL x1, Ls_locations_url
    mov  x2, #0
    ADRL x3, _g_st_auth
    ADRL x4, Ls_tag_locations
    bl   _http
Lsr_done:
    LEAVE 32

Lsr_scenes:
    mov  x0, x20
    ADRL x1, Ls_j_items
    bl   _jget
    mov  x22, x0
    bl   _jcount
    mov  x23, x0
    mov  x24, #0                      // i
    str  xzr, [sp, #120]
Lsn_loop:
    cmp  x24, x23
    b.hs Lsn_summary
    mov  x0, x22
    mov  x1, x24
    bl   _jat
    mov  x21, x0
    ADRL x1, Ls_j_sceneId
    bl   _jget
    bl   _jstr
    str  x0, [sp, #96]
    cbz  x0, Lsn_next
    mov  x0, x21
    ADRL x1, Ls_j_sceneName
    bl   _jget
    bl   _jstr
    cbz  x0, Lsn_next
    mov  x2, x0
    mov  x0, #K_ST_SCENE
    ldr  x1, [sp, #96]
    mov  x3, #CAP_RUN
    bl   _dev_add
    tbnz x0, #63, Lsn_next
    ldr  x9, [sp, #120]
    add  x9, x9, #1
    str  x9, [sp, #120]
Lsn_next:
    add  x24, x24, #1
    b    Lsn_loop
Lsn_summary:
    ldr  x1, [sp, #120]
    ADRL x8, _g_st_scenes
    ldr  x9, [x8]
    str  x1, [x8]
    cbz  x1, Lsr_done
    cmp  x9, x1                       // only when the number changes
    b.eq Lsr_done
    ADRL x0, Ls_st_scenes
    bl   _home_say
    bl   _ui_lists_changed
    LEAVE 32

Lsr_status:
    mov  x0, x19
    bl   _tag_num
    mov  x24, x0                      // device index
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x24, x9
    b.hs Lsr_done
    ADRL x8, _g_devs
    add  x23, x8, x24, lsl #DEV_SHIFT
    mov  x0, x20
    ADRL x1, Ls_j_components
    bl   _jget
    ADRL x1, Ls_j_main
    bl   _jget
    mov  x22, x0                      // components.main
    mov  x1, x24
    bl   _st_apply
    ADRL x8, _g_st_line
    strb wzr, [x8]
    ADRL x21, Lst_report
Lsrs_loop:
    ldr  x1, [x21]
    cbz  x1, Lsrs_say
    mov  x0, x22
    bl   _jget
    ldr  x1, [x21, #8]
    bl   _jget
    str  x0, [sp, #104]               // {"value":..., "unit":...}
    ADRL x1, Ls_j_value
    bl   _jget
    cbz  x0, Lsrs_next
    ADRL x1, _g_st_val
    mov  x2, #64
    bl   _jdesc
    ldrb w9, [x0]
    cbz  w9, Lsrs_next
    ldr  x9, [x21]                    // remember on/off and level
    ADRL x10, Lc_switch
    cmp  x9, x10
    b.ne Lsrs_lvl
    ADRL x0, _g_st_val
    ADRL x1, Lm_on
    bl   _strcmp
    cmp  w0, #0
    cset x9, eq
    str  x9, [x23, #D_ON]
Lsrs_lvl:
    ldr  x9, [x21]
    ADRL x10, Lc_level
    cmp  x9, x10
    b.ne Lsrs_append
    ADRL x0, _g_st_val
    bl   _atol
    str  x0, [x23, #D_LEVEL]
Lsrs_append:
    ADRL x0, _g_st_line
    ldrb w9, [x0]
    cbz  w9, Lsrs_piece
    ADRL x1, Ls_comma
    mov  x2, #480
    bl   _strlcat
Lsrs_piece:
    ADRL x0, _g_st_line
    ldr  x1, [x21, #16]
    mov  x2, #480
    bl   _strlcat
    ADRL x0, _g_st_line
    ADRL x1, _g_st_val
    mov  x2, #480
    bl   _strlcat
    ADRL x0, _g_st_line
    ldr  x1, [x21, #24]
    mov  x2, #480
    bl   _strlcat
    ldr  x0, [sp, #104]               // a short unit like F, C, W
    ADRL x1, Ls_j_unit
    bl   _jget
    bl   _jstr
    cbz  x0, Lsrs_next
    str  x0, [sp, #112]
    bl   _strlen
    sub  x9, x0, #1
    cmp  x9, #2
    b.hs Lsrs_next
    ldr  x0, [sp, #112]
    ldrb w9, [x0]
    cmp  w9, #'%'
    b.eq Lsrs_next
    mov  x1, x0
    ADRL x0, _g_st_line
    mov  x2, #480
    bl   _strlcat
Lsrs_next:
    add  x21, x21, #32
    b    Lsrs_loop
Lsrs_say:
    add  x1, x23, #D_NAME
    ADRL x2, _g_st_line
    ldrb w9, [x2]
    ADRL x0, Ls_st_status
    cbnz w9, Lsrs_out
    ADRL x0, Ls_st_nostatus
Lsrs_out:
    bl   _home_say
    LEAVE 32

Lsr_quiet:                            // a rule is watching it: just remember the state
    mov  x0, x19
    bl   _tag_num
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs Lsr_done
    mov  x21, x0
    mov  x0, x20
    ADRL x1, Ls_j_components
    bl   _jget
    ADRL x1, Ls_j_main
    bl   _jget
    mov  x1, x21
    bl   _st_apply
    LEAVE 32

Lsr_locations:                        // {"items":[{"locationId":..}]}: ask each for its rooms
    mov  x0, x20
    ADRL x1, Ls_j_items
    bl   _jget
    mov  x21, x0
    bl   _jcount
    mov  x23, x0
    mov  x24, #0
Lsl_loop:
    cmp  x24, x23
    b.hs Lsr_done
    mov  x0, x21
    mov  x1, x24
    bl   _jat
    ADRL x1, Ls_j_locationId
    bl   _jget
    bl   _jstr
    add  x24, x24, #1
    cbz  x0, Lsl_loop
    mov  x3, x0
    ADRL x0, _g_st_url
    mov  x1, #256
    ADRL x2, Lf_rooms_url
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_st_url
    mov  x2, #0
    ADRL x3, _g_st_auth
    ADRL x4, Ls_tag_rooms
    bl   _http
    b    Lsl_loop

Lsr_rooms:                            // {"items":[{"roomId":..,"name":..}]}: name the devices' rooms
    mov  x0, x20
    ADRL x1, Ls_j_items
    bl   _jget
    mov  x21, x0
    bl   _jcount
    mov  x23, x0
    mov  x24, #0
Lsm_loop:
    cmp  x24, x23
    b.hs Lsm_done
    mov  x0, x21
    mov  x1, x24
    bl   _jat
    add  x24, x24, #1
    mov  x22, x0
    ADRL x1, Ls_j_roomId
    bl   _jget
    bl   _jstr
    cbz  x0, Lsm_loop
    str  x0, [sp, #96]
    mov  x0, x22
    ADRL x1, Ls_j_name
    bl   _jget
    bl   _jstr
    cbz  x0, Lsm_loop
    str  x0, [sp, #104]
    mov  x19, #0                      // every SmartThings device in that room
Lsm_dev:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lsm_loop
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    add  x19, x19, #1
    ldr  x9, [x22, #D_KIND]
    cmp  x9, #K_ST
    b.ne Lsm_dev
    ldrb w9, [x22, #D_ROOM]
    cmp  w9, #'#'
    b.ne Lsm_dev
    add  x0, x22, #(D_ROOM + 1)
    ldr  x1, [sp, #96]
    mov  x2, #(D_ROOM_MAX - 2)
    bl   _strncmp
    cbnz w0, Lsm_dev
    add  x0, x22, #D_ROOM
    ldr  x1, [sp, #104]
    mov  x2, #D_ROOM_MAX
    bl   _strlcpy
    b    Lsm_dev
Lsm_done:
    bl   _ui_lists_changed
    LEAVE 32

// void _st_apply(NSDictionary *main, long idx) — on/off, level, open/closed, locked
_st_apply:
    ENTER 16
    mov  x19, x0
    ADRL x8, _g_devs
    add  x20, x8, x1, lsl #DEV_SHIFT
    mov  x0, x19
    ADRL x1, Lc_switch
    ADRL x2, La_switch
    bl   _st_attr
    cbz  x0, Lsa_level
    ADRL x1, Lm_on
    bl   _strcmp
    cmp  w0, #0
    cset x9, eq
    str  x9, [x20, #D_ON]
Lsa_level:
    mov  x0, x19
    ADRL x1, Lc_level
    ADRL x2, La_level
    bl   _st_attr
    cbz  x0, Lsa_open
    bl   _atol
    str  x0, [x20, #D_LEVEL]
Lsa_open:
    ADRL x21, Lst_open_caps           // contact, door, shade, valve
Lsa_open_loop:
    ldp  x1, x2, [x21], #16
    cbz  x1, Lsa_lock
    mov  x0, x19
    bl   _st_attr
    cbz  x0, Lsa_open_loop
    mov  x22, x0
    ADRL x1, Ls_w_open
    bl   _strstr                      // "open", "opening", "partially open"
    cmp  x0, #0
    cset x9, ne
    mov  x0, x22
    str  x9, [sp, #96]
    ADRL x1, Ls_w_unknown
    bl   _strcmp
    cbz  w0, Lsa_lock
    ldr  x9, [sp, #96]
    str  x9, [x20, #D_OPEN]
Lsa_lock:
    mov  x0, x19
    ADRL x1, Lc_lock
    ADRL x2, La_lock
    bl   _st_attr
    cbz  x0, Lsa_done
    mov  x22, x0
    ADRL x1, Ls_w_locked
    bl   _strcmp
    mov  x9, #1
    cbz  w0, Lsa_lock_set
    mov  x0, x22
    ADRL x1, Ls_w_unlocked
    bl   _strcmp
    mov  x9, #0
    cbnz w0, Lsa_done
Lsa_lock_set:
    str  x9, [x20, #D_LOCKED]
Lsa_done:
    LEAVE 16

// const char *_st_attr(NSDictionary *main, const char *cap, const char *attr) -> value text or 0
_st_attr:
    ENTER 0
    mov  x19, x2
    bl   _jget
    mov  x1, x19
    bl   _jget
    ADRL x1, Ls_j_value
    bl   _jget
    cbz  x0, Lsat_none
    ADRL x1, _g_st_val
    mov  x2, #64
    bl   _jdesc
    ldrb w9, [x0]
    cbz  w9, Lsat_none
    LEAVE 0
Lsat_none:
    mov  x0, #0
    LEAVE 0

// void _st_poll(long idx) — quietly ask for its state (for rules)
.globl _st_poll
_st_poll:
    ENTER 32
    mov  x19, x0
    ADRL x8, _g_st_token
    ldrb w9, [x8]
    cbz  w9, Lsp_done
    ADRL x8, _g_devs
    add  x20, x8, x19, lsl #DEV_SHIFT
    ADRL x0, _g_st_url
    mov  x1, #256
    ADRL x2, Lf_status_url
    add  x3, x20, #D_ID
    bl   _sfmt
    add  x0, sp, #96
    mov  x1, #32
    ADRL x2, Lf_tag_quiet
    mov  x3, x19
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_st_url
    mov  x2, #0
    ADRL x3, _g_st_auth
    add  x4, sp, #96
    bl   _http
Lsp_done:
    LEAVE 32

// long _st_take(NSDictionary *device) -> 1 if registered
_st_take:
    ENTER 16
    mov  x19, x0
    ADRL x1, Ls_j_deviceId
    bl   _jget
    bl   _jstr
    mov  x20, x0
    cbz  x20, Lstk_no
    mov  x0, x19
    ADRL x1, Ls_j_label
    bl   _jget
    bl   _jstr
    mov  x21, x0
    cbz  x21, Lstk_name
    ldrb w9, [x21]
    cbnz w9, Lstk_caps
Lstk_name:
    mov  x0, x19
    ADRL x1, Ls_j_name
    bl   _jget
    bl   _jstr
    mov  x21, x0
    cbz  x21, Lstk_no
Lstk_caps:
    mov  x0, x19
    ADRL x1, Ls_j_components
    bl   _jget
    mov  x1, #0
    bl   _jat
    mov  x22, x0                      // the main component
    ADRL x1, Ls_j_capabilities
    bl   _jget
    bl   _st_caps                     // x0 caps, x1 flags
    cbz  x0, Lstk_no
    mov  x23, x0
    mov  x24, x1
    mov  x0, x22                      // a television?
    ADRL x1, Ls_j_categories
    bl   _jget
    ADRL x1, Ls_j_name
    ADRL x2, Ls_television
    bl   _jfind
    cbz  x0, Lstk_add
    MOVI x9, CAP_TV
    orr  x23, x23, x9
Lstk_add:
    mov  x0, #K_ST
    mov  x1, x20
    mov  x2, x21
    mov  x3, x23
    bl   _dev_add
    tbnz x0, #63, Lstk_no
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    str  x24, [x8, #D_AUX]
    ldr  x9, [x8, #D_OPEN]            // open/locked: unknown until a status arrives
    cbnz x9, Lstk_known
    mov  x9, #-1
    str  x9, [x8, #D_OPEN]
    str  x9, [x8, #D_LOCKED]
Lstk_known:
    add  x20, x8, #D_ROOM             // "#<roomId>" until the room's name is known
    ldrb w9, [x20]
    cbz  w9, Lstk_room
    cmp  w9, #'#'
    b.ne Lstk_took                    // already named from an earlier load
Lstk_room:
    mov  x0, x19
    ADRL x1, Ls_j_roomId
    bl   _jget
    bl   _jstr
    cbz  x0, Lstk_took
    mov  x3, x0
    mov  x0, x20
    mov  x1, #D_ROOM_MAX
    ADRL x2, Lf_hash
    bl   _sfmt
Lstk_took:
    mov  x0, #1
    LEAVE 16
Lstk_no:
    mov  x0, #0
    LEAVE 16

// (long caps, long flags) _st_caps(NSArray *capabilities) from [{"id":"switch"}, ...]
_st_caps:
    ENTER 16
    mov  x19, x0
    bl   _jcount
    mov  x20, x0
    mov  x21, #0                      // i
    mov  x22, #0                      // caps
    mov  x23, #0                      // flags
Lstc_loop:
    cmp  x21, x20
    b.hs Lstc_done
    mov  x0, x19
    mov  x1, x21
    bl   _jat
    ADRL x1, Ls_j_id
    bl   _jget
    bl   _jstr
    cbz  x0, Lstc_next
    str  x0, [sp, #96]
    ADRL x24, Lst_caps
Lstc_find:
    ldr  x1, [x24]
    cbz  x1, Lstc_next
    ldr  x0, [sp, #96]
    bl   _strcmp
    cbnz w0, Lstc_other
    ldp  x9, x10, [x24, #8]
    orr  x22, x22, x9
    orr  x23, x23, x10
    b    Lstc_next
Lstc_other:
    add  x24, x24, #24
    b    Lstc_find
Lstc_next:
    add  x21, x21, #1
    b    Lstc_loop
Lstc_done:
    mov  x0, x22
    mov  x1, x23
    LEAVE 16

// ===========================================================================
// Apple Home via Shortcuts
// ===========================================================================

// void _sc_load(void) — list shortcuts on a background queue
.globl _sc_load
_sc_load:
    ENTER 0
    ADRL x0, Ls_shortcuts_bin
    mov  w1, #1                       // X_OK
    bl   _access
    cbnz w0, Lscl_done
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, #0
    ADRL x2, _sc_worker
    bl   _dispatch_async_f
Lscl_done:
    LEAVE 0

// void _sc_worker(void *unused) — `shortcuts list`, then hand the text to the main thread
_sc_worker:
    ENTER 16
    CLS  Ls_NSTask
    MSG0 Ls_new
    mov  x19, x0
    ADRL x0, Ls_shortcuts_bin
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setLaunchPath
    ADRL x0, Ls_list
    bl   _nsstr
    mov  x20, x0
    CLS  Ls_NSArray
    mov  x2, x20
    MSG1 Ls_arrayWithObject
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setArguments
    CLS  Ls_NSPipe
    MSG0 Ls_pipe
    mov  x20, x0
    mov  x0, x19
    mov  x2, x20
    MSG1 Ls_setStandardOutput
    CLS  Ls_NSFileHandle
    MSG0 Ls_nullDevice
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setStandardError
    mov  x0, x19
    MSG0 Ls_launch
    mov  x0, x20
    MSG0 Ls_fileHandleForReading
    MSG0 Ls_readToEnd
    mov  x21, x0
    mov  x0, x19
    MSG0 Ls_waitUntilExit
    mov  x0, x21
    MSG0 Ls_length
    mov  x22, x0
    add  x0, x22, #1
    bl   _malloc
    cbz  x0, Lscw_release
    mov  x23, x0
    mov  x0, x21
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x23
    mov  x2, x22
    bl   _memcpy
    strb wzr, [x23, x22]
    LDGOT x0, __dispatch_main_q
    mov  x1, x23
    ADRL x2, _sc_loaded
    bl   _dispatch_async_f
Lscw_release:
    mov  x0, x19
    MSG0 Ls_release
    LEAVE 16

// void _sc_loaded(char *text) — one shortcut per line
_sc_loaded:
    ENTER 0
    mov  x19, x0
    mov  x20, x0                      // line start
    mov  x21, #0                      // added
Lsd_loop:
    ldrb w9, [x20]
    cbz  w9, Lsd_summary
    mov  x22, x20
Lsd_eol:
    ldrb w9, [x22]
    cbz  w9, Lsd_line
    cmp  w9, #10
    b.eq Lsd_line
    add  x22, x22, #1
    b    Lsd_eol
Lsd_line:
    ldrb w23, [x22]                   // remember what ended the line
    strb wzr, [x22]
    sub  x9, x22, x20
    cbz  x9, Lsd_advance
    cmp  x21, #SC_MAX
    b.hs Lsd_advance
    mov  x0, #K_SHORTCUT
    mov  x1, x20
    mov  x2, x20
    mov  x3, #CAP_RUN
    bl   _dev_add
    tbnz x0, #63, Lsd_advance
    add  x21, x21, #1
Lsd_advance:
    cbz  w23, Lsd_summary
    add  x20, x22, #1
    b    Lsd_loop
Lsd_summary:
    cbz  x21, Lsd_free
    ADRL x8, _g_sc_count
    ldr  x9, [x8]
    str  x21, [x8]
    cbnz x9, Lsd_free                 // only announce the first time
    mov  x1, x21
    ADRL x0, Ls_sc_ready
    bl   _home_say
Lsd_free:
    mov  x0, x19
    bl   _free
    LEAVE 0

// void _sc_run(long idx) — `shortcuts run "<name>"`, not waited for
.globl _sc_run
_sc_run:
    ENTER 16
    ADRL x8, _g_devs
    add  x19, x8, x0, lsl #DEV_SHIFT
    ADRL x0, Ls_run
    bl   _nsstr
    str  x0, [sp, #96]
    add  x0, x19, #D_NAME
    bl   _nsstr
    str  x0, [sp, #104]
    CLS  Ls_NSArray
    add  x2, sp, #96
    mov  x3, #2
    MSG2 Ls_arrayWithObjectsCount
    mov  x20, x0
    ADRL x0, Ls_shortcuts_bin
    bl   _nsstr
    mov  x21, x0
    CLS  Ls_NSTask
    mov  x2, x21
    mov  x3, x20
    MSG2 Ls_launchedTask
    LEAVE 16


// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_NSSecureTextField: .asciz "NSSecureTextField"
Ls_NSTask:            .asciz "NSTask"
Ls_NSPipe:            .asciz "NSPipe"
Ls_NSFileHandle:      .asciz "NSFileHandle"
Ls_NSArray:           .asciz "NSArray"
Ls_alloc:             .asciz "alloc"
Ls_new:               .asciz "new"
Ls_release:           .asciz "release"
Ls_initWithFrame:     .asciz "initWithFrame:"
Ls_setPlaceholderString: .asciz "setPlaceholderString:"
Ls_stringValue:       .asciz "stringValue"
Ls_UTF8String:        .asciz "UTF8String"
Ls_setLaunchPath:     .asciz "setLaunchPath:"
Ls_setArguments:      .asciz "setArguments:"
Ls_arrayWithObject:   .asciz "arrayWithObject:"
Ls_arrayWithObjectsCount: .asciz "arrayWithObjects:count:"
Ls_pipe:              .asciz "pipe"
Ls_setStandardOutput: .asciz "setStandardOutput:"
Ls_setStandardError:  .asciz "setStandardError:"
Ls_nullDevice:        .asciz "fileHandleWithNullDevice"
Ls_launch:            .asciz "launch"
Ls_fileHandleForReading: .asciz "fileHandleForReading"
Ls_readToEnd:         .asciz "readDataToEndOfFile"
Ls_waitUntilExit:     .asciz "waitUntilExit"
Ls_length:            .asciz "length"
Ls_bytes:             .asciz "bytes"
Ls_launchedTask:      .asciz "launchedTaskWithLaunchPath:arguments:"

Ls_kc_service:   .asciz "asmmesh.smartthings"
Lf_bearer:       .asciz "Bearer %s"
Ls_GET:          .asciz "GET"
Ls_POST:         .asciz "POST"
Ls_tag_load:     .asciz "sl"
Ls_tag_cmd:      .asciz "sc"
Ls_tag_scenes:   .asciz "sn"
Ls_tag_scene:    .asciz "sx"
Ls_tag_locations: .asciz "so"
Ls_tag_rooms:    .asciz "sr"
Ls_locations_url: .asciz "https://api.smartthings.com/v1/locations"
Lf_rooms_url:    .asciz "https://api.smartthings.com/v1/locations/%s/rooms"
Lf_hash:         .asciz "#%s"
Ls_j_roomId:     .asciz "roomId"
Ls_j_locationId: .asciz "locationId"
Lf_tag_status:   .asciz "ss%ld"
Lf_tag_quiet:    .asciz "sq%ld"
Ls_w_open:       .asciz "open"
Ls_w_unknown:    .asciz "unknown"
Ls_w_locked:     .asciz "locked"
Ls_w_unlocked:   .asciz "unlocked"
Ls_devices_url:  .asciz "https://api.smartthings.com/v1/devices"
Ls_scenes_url:   .asciz "https://api.smartthings.com/v1/scenes"
Lf_command_url:  .asciz "https://api.smartthings.com/v1/devices/%s/commands"
Lf_status_url:   .asciz "https://api.smartthings.com/v1/devices/%s/status"
Lf_scene_url:    .asciz "https://api.smartthings.com/v1/scenes/%s/execute"
Lf_st_cmd:       .asciz "{\"commands\":[{\"component\":\"main\",\"capability\":\"%s\",\"command\":\"%s\"%s}]}"
Lg_num:          .asciz ",\"arguments\":[%ld]"
Lg_str:          .asciz ",\"arguments\":[\"%s\"]"
Lg_color:        .asciz ",\"arguments\":[{\"hue\":%ld,\"saturation\":100}]"
Lg_cleaning:     .asciz ",\"arguments\":[\"cleaning\"]"
Lg_homing:       .asciz ",\"arguments\":[\"homing\"]"
Lf_ld:           .asciz "%ld"
Lf_hdmi:         .asciz "HDMI%ld"
Ls_digitalTv:    .asciz "digitalTv"
Ls_television:   .asciz "Television"

Lc_switch:       .asciz "switch"
Lc_level:        .asciz "switchLevel"
Lc_color:        .asciz "colorControl"
Lc_ct:           .asciz "colorTemperature"
Lc_lock:         .asciz "lock"
Lc_volume:       .asciz "audioVolume"
Lc_mute:         .asciz "audioMute"
Lc_channel:      .asciz "tvChannel"
Lc_input:        .asciz "mediaInputSource"
Lc_svd_input:    .asciz "samsungvd.mediaInputSource"
Lc_playback:     .asciz "mediaPlayback"
Lc_launchapp:    .asciz "custom.launchapp"
Lc_shade:        .asciz "windowShade"
Lc_shadelevel:   .asciz "windowShadeLevel"
Lc_heatsp:       .asciz "thermostatHeatingSetpoint"
Lc_coolsp:       .asciz "thermostatCoolingSetpoint"
Lc_tmode:        .asciz "thermostatMode"
Lc_temp:         .asciz "temperatureMeasurement"
Lc_humidity:     .asciz "relativeHumidityMeasurement"
Lc_fanspeed:     .asciz "fanSpeed"
Lc_door:         .asciz "doorControl"
Lc_garage:       .asciz "garageDoorControl"
Lc_valve:        .asciz "valve"
Lc_robot:        .asciz "robotCleanerMovement"
Lc_contact:      .asciz "contactSensor"
Lc_motion:       .asciz "motionSensor"
Lc_battery:      .asciz "battery"
Lc_power:        .asciz "powerMeter"
Lc_energy:       .asciz "energyMeter"
Lc_water:        .asciz "waterSensor"
Lc_smoke:        .asciz "smokeDetector"

Lm_on:           .asciz "on"
Lm_off:          .asciz "off"
Lm_setLevel:     .asciz "setLevel"
Lm_setColor:     .asciz "setColor"
Lm_setCT:        .asciz "setColorTemperature"
Lm_lock:         .asciz "lock"
Lm_unlock:       .asciz "unlock"
Lm_setVolume:    .asciz "setVolume"
Lm_volumeUp:     .asciz "volumeUp"
Lm_volumeDown:   .asciz "volumeDown"
Lm_mute:         .asciz "mute"
Lm_unmute:       .asciz "unmute"
Lm_setChannel:   .asciz "setTvChannel"
Lm_channelUp:    .asciz "channelUp"
Lm_channelDown:  .asciz "channelDown"
Lm_setInput:     .asciz "setInputSource"
Lm_play:         .asciz "play"
Lm_pause:        .asciz "pause"
Lm_stop:         .asciz "stop"
Lm_ffwd:         .asciz "fastForward"
Lm_rewind:       .asciz "rewind"
Lm_launchApp:    .asciz "launchApp"
Lm_open:         .asciz "open"
Lm_close:        .asciz "close"
Lm_setShadeLevel: .asciz "setShadeLevel"
Lm_setHeat:      .asciz "setHeatingSetpoint"
Lm_setCool:      .asciz "setCoolingSetpoint"
Lm_setMode:      .asciz "setThermostatMode"
Lm_setFanSpeed:  .asciz "setFanSpeed"
Lm_setRobot:     .asciz "setRobotCleanerMovement"

La_switch:       .asciz "switch"
La_level:        .asciz "level"
La_lock:         .asciz "lock"
La_temperature:  .asciz "temperature"
La_humidity:     .asciz "humidity"
La_heatsp:       .asciz "heatingSetpoint"
La_coolsp:       .asciz "coolingSetpoint"
La_tmode:        .asciz "thermostatMode"
La_contact:      .asciz "contact"
La_motion:       .asciz "motion"
La_battery:      .asciz "battery"
La_volume:       .asciz "volume"
La_mute:         .asciz "mute"
La_channel:      .asciz "tvChannel"
La_input:        .asciz "inputSource"
La_shade:        .asciz "windowShade"
La_shadelevel:   .asciz "shadeLevel"
La_door:         .asciz "door"
La_valve:        .asciz "valve"
La_fanspeed:     .asciz "fanSpeed"
La_power:        .asciz "power"
La_energy:       .asciz "energy"
La_water:        .asciz "water"
La_smoke:        .asciz "smoke"
La_robot:        .asciz "robotCleanerMovement"
Ls_pct:          .asciz "%"
Ls_deg:          .asciz "\302\260"
Ls_pct_hum:      .asciz "% humidity"
Ls_pct_bat:      .asciz "% battery"
Ls_pct_open:     .asciz "% open"
Ls_heat_to:      .asciz "heat to "
Ls_cool_to:      .asciz "cool to "
Ls_mode_sp:      .asciz "mode "
Ls_motion_sp:    .asciz "motion "
Ls_volume_sp:    .asciz "volume "
Ls_channel_sp:   .asciz "channel "
Ls_input_sp:     .asciz "input "
Ls_door_sp:      .asciz "door "
Ls_valve_sp:     .asciz "valve "
Ls_fan_sp:       .asciz "fan speed "
Ls_water_sp:     .asciz "water "
Ls_smoke_sp:     .asciz "smoke "
Ls_comma:        .asciz ", "

Ls_j_items:      .asciz "items"
Ls_j_deviceId:   .asciz "deviceId"
Ls_j_label:      .asciz "label"
Ls_j_name:       .asciz "name"
Ls_j_components: .asciz "components"
Ls_j_capabilities: .asciz "capabilities"
Ls_j_categories: .asciz "categories"
Ls_j_id:         .asciz "id"
Ls_j_main:       .asciz "main"
Ls_j_value:      .asciz "value"
Ls_j_unit:       .asciz "unit"
Ls_j_sceneId:    .asciz "sceneId"
Ls_j_sceneName:  .asciz "sceneName"
Ls_token_ph:     .asciz "SmartThings personal access token"
Ls_conn_msg:     .asciz "Connect SmartThings"
Ls_conn_info:    .asciz "1. Go to account.smartthings.com/tokens and sign in with your Samsung account.\n2. Generate new token; under Devices tick List all devices, See all devices and Control all devices (also tick Locations: See all locations so asmmesh knows which room each device is in, and Scenes: List and Control all scenes if you want scenes).\n3. Copy the long code it shows and paste it here with Cmd-V.\n\nIt's kept in your Keychain. SmartThings makes these tokens expire after 24 hours; asmmesh will tell you when to paste a new one."
Ls_connect:      .asciz "Connect"
Ls_cancel:       .asciz "Cancel"
Ls_checking:     .asciz "\302\267 Checking your SmartThings token\342\200\246"
Ls_need_token:   .asciz "\302\267 SmartThings isn't connected yet. Say \342\200\234connect smartthings\342\200\235 to paste a token."
Ls_st_ready:     .asciz "\302\267 SmartThings connected: %ld of your %ld devices can be controlled or read. Say \342\200\234devices\342\200\235 to see them."
Ls_st_none:      .asciz "\302\267 SmartThings connected and sees %ld devices, but none has anything asmmesh knows how to control."
Ls_st_empty:     .asciz "\302\267 SmartThings connected, but this account has no devices. Make sure the token was made while signed in to the same Samsung account as your SmartThings app."
Ls_st_scenes:    .asciz "\302\267 SmartThings scenes: %ld \342\200\224 say a scene's full name to run it."
Ls_st_status:    .asciz "\302\267 %s: %s"
Ls_st_nostatus:  .asciz "\302\267 %s: SmartThings has no status for it."
Ls_st_refused:   .asciz "\302\267 SmartThings answered HTTP %ld. %s"
Ls_st_scope:     .asciz "\302\267 SmartThings accepted the token but it isn't allowed to see your devices. Make a new token at account.smartthings.com/tokens and tick all three Devices boxes: List all devices, See all devices, Control all devices."
Ls_no_token:     .asciz "\302\267 No token was entered. Copy it from account.smartthings.com/tokens (the long code shown once after you generate it), then choose Mesh \342\200\272 Connect SmartThings and paste it with Cmd-V."
Ls_bearer_sp:    .asciz "bearer "
Ls_j_error:      .asciz "error"
Ls_j_message:    .asciz "message"
Ls_empty:        .asciz ""
Ls_st_unreach:   .asciz "\302\267 Can't reach SmartThings: %s"
Ls_st_badtoken:  .asciz "\302\267 SmartThings rejected the token (HTTP 401). Either it was copied incompletely, or it expired: SmartThings personal tokens now only last 24 hours. Generate a new one at account.smartthings.com/tokens and choose Mesh \342\200\272 Connect SmartThings to paste it."
Ls_shortcuts_bin: .asciz "/usr/bin/shortcuts"
Ls_list:         .asciz "list"
Ls_run:          .asciz "run"
Ls_sc_ready:     .asciz "\302\267 Shortcuts: %ld ready \342\200\224 say a shortcut's name (like \342\200\234good night\342\200\235) to run it. That's how Apple Home and Matter devices are reached."
