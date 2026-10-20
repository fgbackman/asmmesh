// parse.s — the Home room's plain-English commands: parsing, choosing the
// devices meant, and running the command on each through its backend.
//
// Order of recognition (first match wins), so that e.g. "open Netflix" is an
// app and not a door, and "cool to 72" is a thermostat and not a colour:
//   help · connect/pair a service · refresh · devices · status
//   lock/unlock · TV apps · volume/mute · channel · input · thermostat · fan
//   vacuum · playback · remote keys · level (30%) · open/close · colours
//   warm/white/cool · brighter/dimmer · off · on · run
//
// Targets: a device's full name in the command wins over its first word;
// failing names, a type word ("TV", "blinds", "thermostat") or the only device
// able to do the action is used. Devices that can't do the action are skipped.

.include "macros.inc"

// ---------------------------------------------------------------------------
.data
.p2align 3
.globl _g_cmd_word
_g_cmd_word:      .quad 0            // word for the report ("blue", "HDMI 2", "Netflix")
.globl _g_ambiguous
_g_ambiguous:     .quad 0
.globl _g_all_word
_g_all_word:      .quad 0
.zerofill __DATA,__bss,_g_wordbuf,32,4

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
// colour words: name, hue in degrees
Lcolors:
    .quad Lw_red, 0
    .quad Lw_orange, 30
    .quad Lw_yellow, 55
    .quad Lw_green, 120
    .quad Lw_teal, 175
    .quad Lw_cyan, 185
    .quad Lw_blue, 235
    .quad Lw_violet, 265
    .quad Lw_purple, 280
    .quad Lw_magenta, 300
    .quad Lw_pink, 325
    .quad 0, 0

// first words that say nothing about which device is meant
Lstop:
    .quad Lw_the, Lw_hue, Lw_light, Lw_lights, Lw_lamp, Lw_smart, Lw_my, Lw_all, Lw_tv, 0

// type words: word, capability mask, plural (1 = means "all of them")
Ltypes:
    .quad Lw_tv, CAP_TV, 0
    .quad Lw_television, CAP_TV, 0
    .quad Lw_tvs, CAP_TV, 1
    .quad Lw_blinds, CAP_SHADE, 1
    .quad Lw_blind, CAP_SHADE, 0
    .quad Lw_shades, CAP_SHADE, 1
    .quad Lw_shade, CAP_SHADE, 0
    .quad Lw_curtains, CAP_SHADE, 1
    .quad Lw_curtain, CAP_SHADE, 0
    .quad Lw_garage, CAP_GARAGE, 0
    .quad Lw_thermostat, CAP_THERMO, 0
    .quad Lw_heating, CAP_THERMO, 0
    .quad Lw_ac, CAP_THERMO, 0
    .quad Lw_vacuum, CAP_VACUUM, 0
    .quad Lw_robot, CAP_VACUUM, 0
    .quad Lw_roomba, CAP_VACUUM, 0
    .quad Lw_fan, CAP_FAN, 0
    .quad Lw_fans, CAP_FAN, 1
    .quad Lw_roku, CAP_KEYS, 0
    .quad Lw_lock, CAP_LOCK, 0
    .quad Lw_locks, CAP_LOCK, 1
    .quad Lw_valve, CAP_VALVE, 0
    .quad Lw_temperature, CAP_TEMP, 1
    .quad Lw_sprinkler, CAP_VALVE, 0
    .quad Lw_power, CAP_POWER, 1
    .quad Lw_energy, CAP_POWER, 1
    .quad Lw_watts, CAP_POWER, 1
    .quad 0, 0, 0

// what each action needs a device to be able to do (0 = checked in _exec_one)
Lmask:
    .quad 0, 0, 0, 0, 0, 0                                  // NONE ON OFF LEVEL COLOR CT
    .quad CAP_LOCK, CAP_LOCK                                // LOCK UNLOCK
    .quad 0, 0, 0, 0, 0, 0, 0, 0                            // RUN LIST HELP PAIR REFRESH BRIGHTER DIMMER CONNECT
    .quad CAP_VOLUME, CAP_VOLUME, CAP_VOLUME                // VOLUME VOLUP VOLDOWN
    .quad (CAP_MUTE | CAP_VOLUME), (CAP_MUTE | CAP_VOLUME)  // MUTE UNMUTE
    .quad CAP_CHANNEL, CAP_CHANNEL, CAP_CHANNEL             // CHANNEL CHUP CHDOWN
    .quad CAP_INPUT                                         // INPUT
    .quad CAP_MEDIA, CAP_MEDIA, CAP_MEDIA, CAP_MEDIA, CAP_MEDIA // PLAY PAUSE STOP FFWD REWIND
    .quad CAP_APPS                                          // APP
    .quad (CAP_SHADE | CAP_GARAGE | CAP_VALVE), (CAP_SHADE | CAP_GARAGE | CAP_VALVE) // OPEN CLOSE
    .quad CAP_THERMO, CAP_THERMO, CAP_THERMO, CAP_THERMO    // HEATSET COOLSET TEMPSET TMODE
    .quad CAP_FAN                                           // FANSPEED
    .quad CAP_VACUUM, CAP_VACUUM                            // VACSTART VACHOME
    .quad 0                                                 // STATUS
    .quad CAP_KEYS                                          // KEY

// report after a command: format, and what the value means (0 none, 1 number, 2 word)
Lreport:
    .quad Ls_r_what, 0          // NONE (unused)
    .quad Ls_r_on, 0
    .quad Ls_r_off, 0
    .quad Ls_r_level, 1
    .quad Ls_r_word, 2          // COLOR
    .quad Ls_r_word, 2          // CT
    .quad Ls_r_lock, 0
    .quad Ls_r_unlock, 0
    .quad Ls_r_run, 0
    .quad 0, 0, 0, 0, 0, 0, 0, 0 // LIST HELP PAIR REFRESH
    .quad Ls_r_brighter, 0
    .quad Ls_r_dimmer, 0
    .quad 0, 0                  // CONNECT
    .quad Ls_r_volume, 1
    .quad Ls_r_volup, 0
    .quad Ls_r_voldown, 0
    .quad Ls_r_mute, 0
    .quad Ls_r_unmute, 0
    .quad Ls_r_channel, 1
    .quad Ls_r_chup, 0
    .quad Ls_r_chdown, 0
    .quad Ls_r_word, 2          // INPUT
    .quad Ls_r_play, 0
    .quad Ls_r_pause, 0
    .quad Ls_r_stop, 0
    .quad Ls_r_ffwd, 0
    .quad Ls_r_rewind, 0
    .quad Ls_r_app, 2
    .quad Ls_r_open, 0
    .quad Ls_r_close, 0
    .quad Ls_r_heat, 1
    .quad Ls_r_cool, 1
    .quad Ls_r_temp, 1
    .quad Ls_r_word, 2          // TMODE
    .quad Ls_r_fan, 2
    .quad Ls_r_vacstart, 0
    .quad Ls_r_vachome, 0
    .quad 0, 0                  // STATUS
    .quad Ls_r_word, 2          // KEY

// TV apps: display name, word, second word, Samsung Tizen id, Roku id
.globl _g_apps
_g_apps:
    .quad La_netflix, Lw_netflix, 0, Lt_netflix, Lr_netflix
    .quad La_youtube, Lw_youtube, 0, Lt_youtube, Lr_youtube
    .quad La_prime, Lw_prime, Lw_amazon, Lt_prime, Lr_prime
    .quad La_disney, Lw_disney, 0, Lt_disney, Lr_disney
    .quad La_appletv, Lw_appletv, 0, Lt_appletv, Lr_appletv
    .quad La_spotify, Lw_spotify, 0, Lt_spotify, Lr_spotify
    .quad La_plex, Lw_plex, 0, Lt_plex, Lr_plex
    .quad La_hulu, Lw_hulu, 0, Lt_hulu, Lr_hulu

Lmodes:     .quad Lw_off, Lw_heat, Lw_cool, Lw_auto
Lspeeds:    .quad 0, Lw_low, Lw_medium, Lw_high
Lkeys:      .quad Lk_home, Lk_back, Lk_ok

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

// SETV value : _g_cmd_value = value (clobbers x8, x9)
.macro SETV val
    mov  x9, #\val
    ADRL x8, _g_cmd_value
    str  x9, [x8]
.endm

// SETW word : _g_cmd_word = word
.macro SETW word
    ADRL x9, \word
    ADRL x8, _g_cmd_word
    str  x9, [x8]
.endm

// ===========================================================================
// Numbers
// ===========================================================================

// long _num_at(const char *p) -> digits at p (up to 4), or -1
_num_at:
    mov  x9, #0
    mov  x10, #0                      // digits read
Lna_loop:
    ldrb w11, [x0, x10]
    sub  w11, w11, #'0'
    cmp  w11, #9
    b.hi Lna_end
    mov  x12, #10
    mul  x9, x9, x12
    add  x9, x9, x11
    add  x10, x10, #1
    cmp  x10, #4
    b.lo Lna_loop
Lna_end:
    mov  x0, #-1
    cbz  x10, Lna_ret
    mov  x0, x9
Lna_ret:
    ret

// long _num_after(const char *s, const char *word) -> number after the word
//   (skipping spaces and a "to" / "at"), or -1
.globl _num_after
_num_after:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x20
    bl   _strlen
    mov  x21, x0
    mov  x22, x19
Lnf_loop:
    mov  x0, x22
    mov  x1, x20
    bl   _strstr
    cbz  x0, Lnf_none
    mov  x23, x0
    cmp  x23, x19
    b.eq Lnf_after
    ldurb w0, [x23, #-1]
    bl   _isword
    cbnz w0, Lnf_next
Lnf_after:
    add  x24, x23, x21
    ldrb w0, [x24]
    sub  w9, w0, #'0'                 // "hdmi2": digits right after are fine
    cmp  w9, #9
    b.ls Lnf_digits
    bl   _isword
    cbnz w0, Lnf_next
Lnf_skip:
    ldrb w9, [x24]
    cmp  w9, #' '
    b.ne Lnf_word
    add  x24, x24, #1
    b    Lnf_skip
Lnf_word:
    ldrh w9, [x24]                    // "to " / "at "
    ldrb w11, [x24, #2]
    cmp  w11, #' '
    b.ne Lnf_digits
    mov  w10, #0x6f74                 // "to"
    cmp  w9, w10
    b.eq Lnf_skip2
    mov  w10, #0x7461                 // "at"
    cmp  w9, w10
    b.ne Lnf_digits
Lnf_skip2:
    add  x24, x24, #3
    b    Lnf_skip
Lnf_digits:
    mov  x0, x24
    bl   _num_at
    tbz  x0, #63, Lnf_ret
Lnf_next:
    add  x22, x23, #1
    b    Lnf_loop
Lnf_none:
    mov  x0, #-1
Lnf_ret:
    LEAVE 0

// long _find_number(const char *s) -> the first standalone number, or -1
.globl _find_number
_find_number:
    ENTER 0
    mov  x19, x0
    mov  x20, x0
Lfn_loop:
    ldrb w9, [x20]
    cbz  w9, Lfn_none
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.hi Lfn_next
    cmp  x20, x19
    b.eq Lfn_take
    ldurb w0, [x20, #-1]
    bl   _isword
    cbnz w0, Lfn_next
Lfn_take:
    mov  x0, x20
    bl   _num_at
    LEAVE 0
Lfn_next:
    add  x20, x20, #1
    b    Lfn_loop
Lfn_none:
    mov  x0, #-1
    LEAVE 0

// long _therm_num(void) — the temperature in a thermostat command
_therm_num:
    ENTER 0
    ADRL x19, _g_cmdbuf
    ADRL x20, Lthermwords
Ltn_loop:
    ldr  x1, [x20]
    cbz  x1, Ltn_any
    mov  x0, x19
    bl   _num_after
    tbz  x0, #63, Ltn_done
    add  x20, x20, #8
    b    Ltn_loop
Ltn_any:
    mov  x0, x19
    bl   _find_number
Ltn_done:
    LEAVE 0

// ===========================================================================
// Parsing
// ===========================================================================

// long _cmd_parse(const char *text) -> action; fills _g_cmd_* and the targets
.globl _cmd_parse
_cmd_parse:
    ENTER 16
    mov  x1, x0
    ADRL x0, _g_cmdbuf
    mov  x2, #255
    bl   _lower_copy
    ADRL x19, _g_cmdbuf
    ADRL x8, _g_cmd_n
    str  xzr, [x8]
    SETV -1
    ADRL x8, _g_cmd_word
    str  xzr, [x8]
    ADRL x8, _g_ambiguous
    str  xzr, [x8]
    ADRL x8, _g_all_word
    str  xzr, [x8]
    mov  x0, x19
    ADRL x1, Lw_all
    bl   _has_word
    mov  x20, x0
    mov  x0, x19
    ADRL x1, Lw_every
    bl   _has_word
    orr  x20, x20, x0
    mov  x0, x19
    ADRL x1, Lw_everything
    bl   _has_word
    orr  x20, x20, x0
    ADRL x8, _g_all_word
    str  x20, [x8]

    IFWORD Lw_help, Lp_help
    IFWORD Lw_connect, Lp_connect
    IFWORD Lw_token, Lp_connect
    IFWORD Lw_setup, Lp_connect
    IFWORD Lw_link, Lp_connect
    IFWORD Lw_pair, Lp_pair
    IFWORD Lw_refresh, Lp_refresh
    IFWORD Lw_rescan, Lp_refresh
    IFWORD Lw_devices, Lp_list
    IFWORD Lw_list, Lp_list

    // thermostat settings come before "status"/"temperature"
    bl   _therm_num
    mov  x21, x0                      // a number, if any
    tbnz x21, #63, Lp_nonum
    IFWORD Lw_heat, Lp_heatset
    IFWORD Lw_heating, Lp_heatset
    IFWORD Lw_cool, Lp_coolset
    IFWORD Lw_cooling, Lp_coolset
    IFWORD Lw_thermostat, Lp_tempset
    IFWORD Lw_temperature, Lp_tempset
    IFWORD Lw_degrees, Lp_tempset
Lp_nonum:
    IFWORD Lw_status, Lp_status
    IFWORD Lw_what, Lp_status
    IFWORD Lw_what2, Lp_status
    IFWORD Lw_whats, Lp_status
    IFWORD Lw_check, Lp_status
    IFWORD Lw_is, Lp_status
    IFWORD Lw_are, Lp_status
    IFWORD Lw_temperature, Lp_status
    IFWORD Lw_battery, Lp_status
    IFWORD Lw_how, Lp_status

    IFWORD Lw_unlock, Lp_unlock
    IFWORD Lw_lock, Lp_lock

    ADRL x20, _g_apps                 // TV apps
    mov  x22, #0
Lp_app_loop:
    cmp  x22, #APP_COUNT
    b.hs Lp_volume
    ldr  x1, [x20, #8]
    mov  x0, x19
    bl   _has_word
    cbnz w0, Lp_app
    ldr  x1, [x20, #16]
    cbz  x1, Lp_app_next
    mov  x0, x19
    bl   _has_word
    cbnz w0, Lp_app
Lp_app_next:
    add  x20, x20, #40
    add  x22, x22, #1
    b    Lp_app_loop

Lp_volume:
    IFWORD Lw_unmute, Lp_unmute
    IFWORD Lw_mute, Lp_mute
    IFWORD Lw_volume, Lp_vol
    IFWORD Lw_louder, Lp_volup
    IFWORD Lw_quieter, Lp_voldown
    IFWORD Lw_softer, Lp_voldown
    IFWORD Lw_channel, Lp_chan
    mov  x0, x19                      // "hdmi 2", "hdmi2"
    ADRL x1, Lw_hdmi
    bl   _strstr
    cbnz x0, Lp_hdmi
    IFWORD Lw_input, Lp_input
    IFWORD Lw_source, Lp_input
    IFWORD Lw_thermostat, Lp_tmode
    IFWORD Lw_ac, Lp_tmode
    IFWORD Lw_hvac, Lp_tmode
    IFWORD Lw_fan, Lp_fan
Lp_vacuum:
    IFWORD Lw_vacuum, Lp_vac
    IFWORD Lw_vacuuming, Lp_vac
    IFWORD Lw_roomba, Lp_vac
    IFWORD Lw_robot, Lp_vac
    IFWORD Lw_cleaning, Lp_vac
    IFWORD Lw_clean, Lp_vac
    IFWORD Lw_pause, Lp_pause
    IFWORD Lw_resume, Lp_play
    IFWORD Lw_play, Lp_play
    IFWORD Lw_stop, Lp_stop
    IFWORD Lw_rewind, Lp_rewind
    IFWORD Lw_forward, Lp_ffwd
    IFWORD Lw_homescreen, Lp_key_home
    IFWORD Lw_presshome, Lp_key_home
    IFWORD Lw_goback, Lp_key_back
    IFWORD Lw_pressback, Lp_key_back
    IFWORD Lw_pressok, Lp_key_ok
    IFWORD Lw_select, Lp_key_ok
    mov  x0, x19
    bl   _find_level
    tbz  x0, #63, Lp_level
    IFWORD Lw_open, Lp_open
    IFWORD Lw_raise, Lp_open
    IFWORD Lw_close, Lp_close
    IFWORD Lw_shut, Lp_close
    ADRL x20, Lcolors
Lp_col_loop:
    ldr  x1, [x20]
    cbz  x1, Lp_temps
    mov  x0, x19
    bl   _has_word
    cbnz w0, Lp_colour
    add  x20, x20, #16
    b    Lp_col_loop
Lp_temps:
    IFWORD Lw_white, Lp_white
    IFWORD Lw_warm, Lp_warm
    IFWORD Lw_cool, Lp_cool
    IFWORD Lw_cold, Lp_cool
    IFWORD Lw_daylight, Lp_cool
    IFWORD Lw_brighter, Lp_brighter
    IFWORD Lw_brighten, Lp_brighter
    IFWORD Lw_up, Lp_brighter
    IFWORD Lw_dimmer, Lp_dimmer
    IFWORD Lw_dim, Lp_dimmer
    IFWORD Lw_down, Lp_dimmer
    IFWORD Lw_lower, Lp_close
    IFWORD Lw_off, Lp_off
    IFWORD Lw_on, Lp_on
    IFWORD Lw_run, Lp_run
    IFWORD Lw_start, Lp_run
    IFWORD Lw_activate, Lp_run
    mov  x21, #A_NONE
    b    Lp_targets

// ---- no devices involved ----
Lp_help:
    mov  x21, #A_HELP
    b    Lp_done
Lp_list:
    mov  x21, #A_LIST
    b    Lp_done
Lp_refresh:
    mov  x21, #A_REFRESH
    b    Lp_done
Lp_pair:
    IFWORD Lw_nanoleaf, Lp_c_nano
    IFWORD Lw_smartthings, Lp_c_st
    IFWORD Lw_assistant, Lp_c_ha
    IFWORD Lw_homeassistant, Lp_c_ha
    IFWORD Lw_lifx, Lp_c_lifx
    IFWORD Lw_govee, Lp_c_govee
    mov  x21, #A_PAIR
    b    Lp_done
Lp_connect:
    IFWORD Lw_smartthings, Lp_c_st
    IFWORD Lw_assistant, Lp_c_ha
    IFWORD Lw_homeassistant, Lp_c_ha
    IFWORD Lw_lifx, Lp_c_lifx
    IFWORD Lw_govee, Lp_c_govee
    IFWORD Lw_nanoleaf, Lp_c_nano
    IFWORD Lw_hue, Lp_pair
    SETV 0
    b    Lp_conn
Lp_c_st:
    SETV 1
    b    Lp_conn
Lp_c_ha:
    SETV 2
    b    Lp_conn
Lp_c_lifx:
    SETV 3
    b    Lp_conn
Lp_c_govee:
    SETV 4
    b    Lp_conn
Lp_c_nano:
    SETV 5
Lp_conn:
    mov  x21, #A_CONNECT
    b    Lp_done

// ---- settings with a number ----
Lp_heatset:
    mov  x22, #A_HEATSET
    b    Lp_setnum
Lp_coolset:
    mov  x22, #A_COOLSET
    b    Lp_setnum
Lp_tempset:
    mov  x22, #A_TEMPSET
Lp_setnum:
    ADRL x8, _g_cmd_value
    str  x21, [x8]
    mov  x21, x22
    b    Lp_targets

Lp_status:
    mov  x21, #A_STATUS
    b    Lp_targets
Lp_unlock:
    mov  x21, #A_UNLOCK
    b    Lp_targets
Lp_lock:
    mov  x21, #A_LOCK
    b    Lp_targets
Lp_app:
    ADRL x8, _g_cmd_value
    str  x22, [x8]
    ldr  x9, [x20]
    ADRL x8, _g_cmd_word
    str  x9, [x8]
    mov  x21, #A_APP
    b    Lp_targets

Lp_unmute:
    mov  x21, #A_UNMUTE
    b    Lp_targets
Lp_mute:
    mov  x21, #A_MUTE
    b    Lp_targets
Lp_vol:
    mov  x0, x19
    ADRL x1, Lw_volume
    bl   _num_after
    tbnz x0, #63, Lp_vol_dir
    cmp  x0, #100
    mov  x9, #100
    csel x0, x9, x0, hi
    ADRL x8, _g_cmd_value
    str  x0, [x8]
    mov  x21, #A_VOLUME
    b    Lp_targets
Lp_vol_dir:
    IFWORD Lw_up, Lp_volup
    IFWORD Lw_louder, Lp_volup
    IFWORD Lw_raise, Lp_volup
    IFWORD Lw_down, Lp_voldown
    IFWORD Lw_lower, Lp_voldown
    IFWORD Lw_quieter, Lp_voldown
    mov  x21, #A_NONE
    b    Lp_targets
Lp_volup:
    mov  x21, #A_VOLUP
    b    Lp_targets
Lp_voldown:
    mov  x21, #A_VOLDOWN
    b    Lp_targets

Lp_chan:
    mov  x0, x19
    ADRL x1, Lw_channel
    bl   _num_after
    tbnz x0, #63, Lp_chan_dir
    ADRL x8, _g_cmd_value
    str  x0, [x8]
    mov  x21, #A_CHANNEL
    b    Lp_targets
Lp_chan_dir:
    IFWORD Lw_up, Lp_chup
    IFWORD Lw_next, Lp_chup
    IFWORD Lw_down, Lp_chdown
    IFWORD Lw_previous, Lp_chdown
    IFWORD Lw_prev, Lp_chdown
    mov  x21, #A_NONE
    b    Lp_targets
Lp_chup:
    mov  x21, #A_CHUP
    b    Lp_targets
Lp_chdown:
    mov  x21, #A_CHDOWN
    b    Lp_targets

Lp_hdmi:
    mov  x0, x19
    ADRL x1, Lw_hdmi
    bl   _num_after
    cmp  x0, #1
    b.lt Lp_hdmi1
    cmp  x0, #4
    b.ls Lp_input_n
Lp_hdmi1:
    mov  x0, #1
    b    Lp_input_n
Lp_input:
    IFWORD Lw_tv, Lp_input_tv
    IFWORD Lw_antenna, Lp_input_tv
    IFWORD Lw_live, Lp_input_tv
    mov  x0, x19
    bl   _find_number
    cmp  x0, #1
    b.lt Lp_hdmi1
    cmp  x0, #4
    b.hi Lp_hdmi1
Lp_input_n:
    ADRL x8, _g_cmd_value
    str  x0, [x8]
    str  x0, [sp]
    ADRL x0, _g_wordbuf
    mov  x1, #32
    ADRL x2, Lf_hdmi
    bl   _snprintf
    ADRL x9, _g_wordbuf
    ADRL x8, _g_cmd_word
    str  x9, [x8]
    mov  x21, #A_INPUT
    b    Lp_targets
Lp_input_tv:
    SETV 0
    SETW Ls_tv_input
    mov  x21, #A_INPUT
    b    Lp_targets

Lp_tmode:
    mov  x22, #0
    IFWORD Lw_off, Lp_tmode_set
    mov  x22, #1
    IFWORD Lw_heat, Lp_tmode_set
    mov  x22, #2
    IFWORD Lw_cool, Lp_tmode_set
    mov  x22, #3
    IFWORD Lw_auto, Lp_tmode_set
    b    Lp_fan                       // "turn on the AC" etc: continue below
Lp_tmode_set:
    ADRL x8, _g_cmd_value
    str  x22, [x8]
    ADRL x9, Lmodes
    ldr  x9, [x9, x22, lsl #3]
    ADRL x8, _g_cmd_word
    str  x9, [x8]
    mov  x21, #A_TMODE
    b    Lp_targets

Lp_fan:
    mov  x22, #3
    IFWORD Lw_high, Lp_fan_set
    IFWORD Lw_max, Lp_fan_set
    mov  x22, #2
    IFWORD Lw_medium, Lp_fan_set
    mov  x22, #1
    IFWORD Lw_low, Lp_fan_set
    b    Lp_vacuum
Lp_fan_set:
    ADRL x8, _g_cmd_value
    str  x22, [x8]
    ADRL x9, Lspeeds
    ldr  x9, [x9, x22, lsl #3]
    ADRL x8, _g_cmd_word
    str  x9, [x8]
    mov  x21, #A_FANSPEED
    b    Lp_targets

Lp_vac:
    IFWORD Lw_dock, Lp_vachome
    IFWORD Lw_home, Lp_vachome
    IFWORD Lw_return, Lp_vachome
    IFWORD Lw_base, Lp_vachome
    IFWORD Lw_stop, Lp_vachome
    mov  x21, #A_VACSTART
    b    Lp_targets
Lp_vachome:
    mov  x21, #A_VACHOME
    b    Lp_targets

Lp_pause:
    mov  x21, #A_PAUSE
    b    Lp_targets
Lp_play:
    mov  x21, #A_PLAY
    b    Lp_targets
Lp_stop:
    mov  x21, #A_STOP
    b    Lp_targets
Lp_rewind:
    mov  x21, #A_REWIND
    b    Lp_targets
Lp_ffwd:
    mov  x21, #A_FFWD
    b    Lp_targets
Lp_key_home:
    mov  x22, #0
    b    Lp_key
Lp_key_back:
    mov  x22, #1
    b    Lp_key
Lp_key_ok:
    mov  x22, #2
Lp_key:
    ADRL x8, _g_cmd_value
    str  x22, [x8]
    ADRL x9, Lkeys
    ldr  x9, [x9, x22, lsl #3]
    ADRL x8, _g_cmd_word
    str  x9, [x8]
    mov  x21, #A_KEY
    b    Lp_targets

Lp_level:
    ADRL x8, _g_cmd_value
    str  x0, [x8]
    mov  x21, #A_LEVEL
    b    Lp_targets
Lp_open:
    mov  x21, #A_OPEN
    b    Lp_targets
Lp_close:
    mov  x21, #A_CLOSE
    b    Lp_targets
Lp_colour:
    ldr  x9, [x20, #8]
    ADRL x8, _g_cmd_value
    str  x9, [x8]
    ldr  x9, [x20]
    ADRL x8, _g_cmd_word
    str  x9, [x8]
    mov  x21, #A_COLOR
    b    Lp_targets
Lp_white:
    mov  x9, #4000
    ADRL x10, Lw_white
    b    Lp_ct
Lp_warm:
    mov  x9, #2700
    ADRL x10, Lw_warm
    b    Lp_ct
Lp_cool:
    mov  x9, #5500
    ADRL x10, Lw_cool
Lp_ct:                                // value: colour temperature in kelvin
    ADRL x8, _g_cmd_value
    str  x9, [x8]
    ADRL x8, _g_cmd_word
    str  x10, [x8]
    mov  x21, #A_CT
    b    Lp_targets
Lp_brighter:
    mov  x21, #A_BRIGHTER
    b    Lp_targets
Lp_dimmer:
    mov  x21, #A_DIMMER
    b    Lp_targets
Lp_off:
    mov  x21, #A_OFF
    b    Lp_targets
Lp_on:
    mov  x21, #A_ON
    b    Lp_targets
Lp_run:
    mov  x21, #A_RUN
Lp_targets:
    mov  x0, x21
    bl   _cmd_targets
Lp_done:
    ADRL x8, _g_cmd_action
    str  x21, [x8]
    mov  x0, x21
    LEAVE 16

// long _chat_route(const char *text) — typed in a chat room, but plainly a device
// command ("tv volume 10", "kitchen lights off")? Then run it in Home, show Home,
// and return 1 so it is not sent to the mesh as a chat message.
.globl _chat_route
_chat_route:
    ENTER 256                         // [96] copy of the text
    mov  x1, x0
    add  x0, sp, #96
    mov  x2, #250
    bl   _strlcpy
    add  x0, sp, #96
    bl   _chat_is_command
    cbnz x0, Lcr_route_yes
    add  x0, sp, #96
    bl   _extra_routable              // "weather", "sunset", "trackers"
    cbz  x0, Lcr_route_no
Lcr_route_yes:
    ADRL x8, _g_home_idx
    ldr  x0, [x8]
    bl   _ui_select_room
    add  x0, sp, #96
    mov  w1, #0
    bl   _home_command
    mov  x0, #1
Lcr_route_no:
    LEAVE 256

// long _chat_is_command(const char *text) -> 1 if it is plainly a device command
.globl _chat_is_command
_chat_is_command:
    ENTER 0
    mov  x19, x0
    ldrb w9, [x19]
    cmp  w9, #'@'                     // "@Anna ..." is for someone else
    b.eq Lcr_no
    mov  x0, x19
    bl   _cmd_parse
    mov  x20, x0                      // action
    cmp  x20, #A_ON
    b.lo Lcr_no
    cmp  x20, #A_LAST
    b.hi Lcr_no
    cmp  x20, #A_RUN
    b.eq Lcr_no
    cmp  x20, #A_STATUS
    b.eq Lcr_no
    cmp  x20, #A_LIST                 // "list devices" typed in a chat room
    b.ne Lcr_not_list
    ADRL x0, _g_cmdbuf
    ADRL x1, Lw_devices
    bl   _has_word
    cbnz w0, Lcr_yes
    b    Lcr_no
Lcr_not_list:
    cmp  x20, #A_LIST
    b.lo Lcr_words
    cmp  x20, #A_REFRESH
    b.ls Lcr_no                       // list, help, pair, refresh, connect: fine as chat
    cmp  x20, #A_CONNECT
    b.eq Lcr_no
Lcr_words:
    ADRL x0, _g_cmdbuf                // short, like a command (at most 6 words)
    mov  x9, #1
Lcr_count:
    ldrb w10, [x0], #1
    cbz  w10, Lcr_counted
    cmp  w10, #' '
    cinc x9, x9, eq
    b    Lcr_count
Lcr_counted:
    cmp  x9, #6
    b.hi Lcr_no
    bl   _named_device                // a device's name in it?
    cbnz x0, Lcr_yes
    cmp  x20, #A_LOCK                 // "I'll lock up" stays chat
    b.eq Lcr_no
    cmp  x20, #A_UNLOCK
    b.eq Lcr_no
    ADRL x21, Ltypes                  // a type word: TV, blinds, thermostat...
Lcr_type:
    ldr  x1, [x21]
    cbz  x1, Lcr_lights
    ADRL x0, _g_cmdbuf
    bl   _has_word
    cbnz w0, Lcr_yes
    add  x21, x21, #24
    b    Lcr_type
Lcr_lights:                           // "lights off", "all lights warm"
    ADRL x0, _g_cmdbuf
    ADRL x1, Lw_lights
    bl   _has_word
    cbnz w0, Lcr_yes
    ADRL x0, _g_cmdbuf
    ADRL x1, Lw_light
    bl   _has_word
    cbnz w0, Lcr_yes
Lcr_no:
    mov  x0, #0
    LEAVE 0
Lcr_yes:
    mov  x0, #1
    LEAVE 0

// long _named_device(void) -> 1 if some device's full name is in _g_cmdbuf
_named_device:
    ENTER 0
    mov  x19, #0
Lnd_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lnd_no
    ADRL x8, _g_devs
    add  x20, x8, x19, lsl #DEV_SHIFT
    add  x19, x19, #1
    ldr  x9, [x20, #D_KIND]
    cmp  x9, #K_SHORTCUT              // shortcuts and scenes stay by name in Home
    b.eq Lnd_loop
    cmp  x9, #K_ST_SCENE
    b.eq Lnd_loop
    ADRL x0, _g_lname
    add  x1, x20, #D_NAME
    mov  x2, #(D_NAME_MAX - 1)
    bl   _lower_copy
    ADRL x0, _g_lname
    bl   _strlen
    cmp  x0, #3
    b.lo Lnd_loop
    ADRL x0, _g_cmdbuf
    ADRL x1, _g_lname
    bl   _has_word
    cbz  w0, Lnd_loop
    mov  x0, #1
    LEAVE 0
Lnd_no:
    mov  x0, #0
    LEAVE 0

// long _list_filter(void) -> what "list ..." asks for: 0 everything, -1 lights,
//   else the capability of a type word ("list tvs", "list locks", "list thermostats")
.globl _list_filter
_list_filter:
    ENTER 0
    ADRL x0, _g_cmdbuf
    ADRL x1, Lw_lights
    bl   _has_word
    cbnz w0, Llf_lights
    ADRL x0, _g_cmdbuf
    ADRL x1, Lw_light
    bl   _has_word
    cbnz w0, Llf_lights
    ADRL x0, _g_cmdbuf
    ADRL x1, Lw_lamps
    bl   _has_word
    cbnz w0, Llf_lights
    ADRL x19, Ltypes
    mov  x20, #0
Llf_type:
    ldr  x1, [x19]
    cbz  x1, Llf_done
    ADRL x0, _g_cmdbuf
    bl   _has_word
    cbz  w0, Llf_next
    ldr  x9, [x19, #8]
    orr  x20, x20, x9
Llf_next:
    add  x19, x19, #24
    b    Llf_type
Llf_done:
    mov  x0, x20
    LEAVE 0
Llf_lights:
    mov  x0, #-1
    LEAVE 0

// long _action_mask(long action)
.globl _action_mask
_action_mask:
    cmp  x0, #A_LAST
    b.hi Lam_zero
    ADRL x8, Lmask
    ldr  x0, [x8, x0, lsl #3]
    ret
Lam_zero:
    mov  x0, #0
    ret

// int _is_stopword(const char *w)
_is_stopword:
    ENTER 0
    mov  x19, x0
    ADRL x20, Lstop
Lsw_loop:
    ldr  x1, [x20]
    cbz  x1, Lsw_no
    mov  x0, x19
    bl   _strcmp
    cbz  w0, Lsw_yes
    add  x20, x20, #8
    b    Lsw_loop
Lsw_no:
    mov  x0, #0
    LEAVE 0
Lsw_yes:
    mov  x0, #1
    LEAVE 0

// ===========================================================================
// Which devices?
// ===========================================================================

// void _cmd_targets(long action)
.globl _cmd_targets
_cmd_targets:
    ENTER 32
    // locals: [96] best score  [104] action mask  [112] action
    str  x0, [sp, #112]
    bl   _action_mask
    str  x0, [sp, #104]
    str  xzr, [sp, #96]
    mov  x20, #0
Lct_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lct_after
    ADRL x8, _g_devs
    add  x21, x8, x20, lsl #DEV_SHIFT
    ldr  x9, [x21, #D_CAPS]
    ldr  x10, [sp, #104]
    cbz  x10, Lct_score
    tst  x9, x10                      // can't do this action: not a candidate
    b.eq Lct_next
Lct_score:
    ldr  x10, [sp, #112]              // shortcuts and scenes only for "run X" or just "X":
    cmp  x10, #A_NONE                 //  "TV off" means the TV, not a scene called "TV"
    b.eq Lct_named
    cmp  x10, #A_RUN
    b.eq Lct_named
    ldr  x9, [x21, #D_KIND]
    cmp  x9, #K_SHORTCUT
    b.eq Lct_next
    cmp  x9, #K_ST_SCENE
    b.eq Lct_next
    ldr  x9, [x21, #D_CAPS]
    tst  x9, #CAP_RUN
    b.eq Lct_named
    tst  x9, #CAP_ON
    b.eq Lct_next
Lct_named:
    ADRL x0, _g_lname
    add  x1, x21, #D_NAME
    mov  x2, #(D_NAME_MAX - 1)
    bl   _lower_copy
    ADRL x0, _g_lname
    bl   _strlen
    mov  x22, x0
    mov  x23, #0
    cmp  x22, #2
    b.lo Lct_word
    ADRL x0, _g_cmdbuf
    ADRL x1, _g_lname
    bl   _has_word
    cbz  w0, Lct_word
    lsl  x23, x22, #1
    add  x23, x23, #10
    b    Lct_keep
Lct_word:                             // first word of the name (never for runnables:
    ldr  x9, [x21, #D_KIND]           //  running one by accident is worse than asking)
    cmp  x9, #K_SHORTCUT
    b.eq Lct_next
    cmp  x9, #K_ST_SCENE
    b.eq Lct_next
    ADRL x8, _g_lname
    mov  x9, #0
Lct_fw:
    ldrb w10, [x8, x9]
    cbz  w10, Lct_fw_end
    cmp  w10, #' '
    b.eq Lct_fw_end
    add  x9, x9, #1
    b    Lct_fw
Lct_fw_end:
    strb wzr, [x8, x9]
    cmp  x9, #3
    b.lo Lct_next
    mov  x23, x9
    ADRL x0, _g_lname
    bl   _is_stopword
    cbnz w0, Lct_next
    ADRL x0, _g_cmdbuf
    ADRL x1, _g_lname
    bl   _has_word
    cbz  w0, Lct_next
Lct_keep:
    ldr  x9, [sp, #96]
    cmp  x23, x9
    b.lo Lct_next
    b.eq Lct_add
    str  x23, [sp, #96]               // a better match: start over
    ADRL x8, _g_cmd_n
    str  xzr, [x8]
Lct_add:
    mov  x0, x20
    bl   _target_add
Lct_next:
    add  x20, x20, #1
    b    Lct_loop

Lct_after:
    ADRL x8, _g_cmd_n
    ldr  x9, [x8]
    cbnz x9, Lct_done
    ADRL x19, _g_cmdbuf
    // a type word: "TV", "blinds", "thermostat"...
    ADRL x22, Ltypes
Lct_type:
    ldr  x1, [x22]
    cbz  x1, Lct_mask
    mov  x0, x19
    bl   _has_word
    cbnz w0, Lct_type_hit
    add  x22, x22, #24
    b    Lct_type
Lct_type_hit:
    ldr  x0, [x22, #8]
    ldr  x1, [sp, #104]
    bl   _targets_with
    ldr  x9, [x22, #16]               // plural word: all of them
    cbnz x9, Lct_done
    b    Lct_one
Lct_mask:
    ldr  x0, [sp, #104]               // the only device that can do it
    cbz  x0, Lct_lights
    mov  x1, #0
    bl   _targets_with
    b    Lct_one
Lct_lights:
    ldr  x9, [sp, #112]
    cmp  x9, #A_ON
    b.lo Lct_done
    cmp  x9, #A_CT
    b.ls Lct_lights_go
    cmp  x9, #A_BRIGHTER
    b.lo Lct_done
    cmp  x9, #A_DIMMER
    b.hi Lct_done
Lct_lights_go:
    ADRL x8, _g_all_word
    ldr  x9, [x8]
    cbnz x9, Lct_lights_all
    IFWORD Lw_lights, Lct_lights_all
    IFWORD Lw_light, Lct_lights_all
    b    Lct_done
Lct_lights_all:
    bl   _targets_lights
    bl   _lights_room_filter          // "kitchen lights", or this Mac's room
    b    Lct_done
Lct_one:                              // several: fine for "all" or status; else ask
    ADRL x8, _g_cmd_n
    ldr  x9, [x8]
    cmp  x9, #1
    b.ls Lct_done
    ADRL x10, _g_all_word
    ldr  x10, [x10]
    cbnz x10, Lct_done
    ldr  x10, [sp, #112]
    cmp  x10, #A_STATUS
    b.eq Lct_done
    str  xzr, [x8]
    ADRL x8, _g_ambiguous
    mov  x9, #1
    str  x9, [x8]
Lct_done:
    LEAVE 32

// void _target_add(long idx)
_target_add:
    ADRL x8, _g_devs                  // its service is switched off: never a target
    add  x8, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x8, #D_KIND]
    ADRL x10, _g_kind_on
    ldrb w10, [x10, x9]
    cbz  w10, Lta_done
    ADRL x8, _g_cmd_n
    ldr  x9, [x8]
    cmp  x9, #64
    b.hs Lta_done
    ADRL x10, _g_cmd_targets
    strb w0, [x10, x9]
    add  x9, x9, #1
    str  x9, [x8]
Lta_done:
    ret

// void _targets_with(long any_of, long also_one_of /*0: no extra condition*/)
.globl _targets_with
_targets_with:
    ENTER 0
    mov  x19, x0
    mov  x22, x1
    mov  x20, #0
    ADRL x8, _g_cmd_n
    str  xzr, [x8]
Ltw_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Ltw_done
    ADRL x8, _g_devs
    add  x21, x8, x20, lsl #DEV_SHIFT
    ldr  x9, [x21, #D_CAPS]
    tst  x9, x19
    b.eq Ltw_next
    cbz  x22, Ltw_add
    tst  x9, x22
    b.eq Ltw_next
Ltw_add:
    mov  x0, x20
    bl   _target_add
Ltw_next:
    add  x20, x20, #1
    b    Ltw_loop
Ltw_done:
    LEAVE 0

// void _targets_lights(void) — every light: switchable and dimmable or colour,
// not a Hue room (its lights are listed on their own), lock, TV or shortcut
_targets_lights:
    ENTER 0
    mov  x20, #0
    ADRL x8, _g_cmd_n
    str  xzr, [x8]
Ltl_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Ltl_done
    ADRL x8, _g_devs
    add  x21, x8, x20, lsl #DEV_SHIFT
    ldr  x9, [x21, #D_CAPS]
    ldr  x10, [x21, #D_KIND]
    tst  x9, #CAP_ON
    b.eq Ltl_next
    mov  x11, #(CAP_LEVEL | CAP_COLOR | CAP_CT)
    tst  x9, x11
    b.eq Ltl_next
    mov  x11, #CAP_LOCK
    movk x11, #((CAP_TV | CAP_FAN) >> 16), lsl #16
    tst  x9, x11
    b.ne Ltl_next
    cmp  x10, #K_HUE_GROUP
    b.eq Ltl_next
    mov  x0, x20
    bl   _target_add
Ltl_next:
    add  x20, x20, #1
    b    Ltl_loop
Ltl_done:
    LEAVE 0

// ===========================================================================
// Running a parsed command
// ===========================================================================

// void _cmd_exec(void)
.globl _cmd_exec
_cmd_exec:
    ENTER 0
    ADRL x8, _g_cmd_action
    ldr  x19, [x8]
    cmp  x19, #A_HELP
    b.eq Lce_help
    cmp  x19, #A_LIST
    b.eq Lce_list
    cmp  x19, #A_PAIR
    b.eq Lce_pair
    cmp  x19, #A_REFRESH
    b.eq Lce_refresh
    cmp  x19, #A_CONNECT
    b.eq Lce_connect
    ADRL x8, _g_cmd_n
    ldr  x20, [x8]
    cbnz x20, Lce_each
    cmp  x19, #A_STATUS
    b.eq Lce_list
    ADRL x8, _g_ambiguous
    ldr  x9, [x8]
    ADRL x0, Ls_which
    cbnz x9, Lce_say
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    ADRL x0, Ls_no_devices
    cbz  x9, Lce_say
    ADRL x0, Ls_no_match
    cmp  x19, #A_NONE
    b.ne Lce_say
    ADRL x0, Ls_no_idea
Lce_say:
    bl   _home_say0
    LEAVE 0
Lce_each:
    mov  x21, #0
Lce_loop:
    cmp  x21, x20
    b.hs Lce_done
    ADRL x8, _g_cmd_targets
    ldrb w0, [x8, x21]
    bl   _exec_one
    add  x21, x21, #1
    b    Lce_loop
Lce_done:
    LEAVE 0
Lce_help:
    bl   _home_help
    LEAVE 0
Lce_list:
    bl   _list_filter
    bl   _home_list
    LEAVE 0
Lce_pair:
    bl   _hue_pair
    LEAVE 0
Lce_refresh:
    bl   _home_refresh
    LEAVE 0
Lce_connect:
    ADRL x8, _g_remote_active
    ldr  x8, [x8]
    cbnz x8, Lce_done
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    cmp  x9, #1
    b.eq Lce_c_st
    cmp  x9, #2
    b.eq Lce_c_ha
    cmp  x9, #3
    b.eq Lce_c_lifx
    cmp  x9, #4
    b.eq Lce_c_govee
    cmp  x9, #5
    b.eq Lce_c_nano
    ADRL x0, Ls_connect_what
    bl   _home_say0
    LEAVE 0
Lce_c_st:
    bl   _st_connect_dialog
    LEAVE 0
Lce_c_ha:
    bl   _ha_connect_dialog
    LEAVE 0
Lce_c_lifx:
    bl   _lifx_connect_dialog
    LEAVE 0
Lce_c_govee:
    bl   _govee_connect_dialog
    LEAVE 0
Lce_c_nano:
    bl   _nano_pair
    LEAVE 0

// void _exec_one(long idx) — one device, the current action
.globl _exec_one
_exec_one:
    ENTER 16
    // [96] value
    mov  x19, x0
    ADRL x8, _g_devs
    add  x20, x8, x19, lsl #DEV_SHIFT
    ldr  x21, [x20, #D_CAPS]
    ldr  x22, [x20, #D_KIND]
    add  x23, x20, #D_NAME
    ADRL x8, _g_cmd_action
    ldr  x24, [x8]
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    str  x9, [sp, #96]

    cmp  x24, #A_STATUS
    b.eq Leo_status
    // things that only run: shortcuts and scenes
    cmp  x22, #K_SHORTCUT
    b.eq Leo_runnable
    cmp  x22, #K_ST_SCENE
    b.eq Leo_runnable
    tst  x21, #CAP_RUN
    b.eq Leo_not_runnable
    tst  x21, #CAP_ON
    b.eq Leo_runnable                 // Home Assistant scenes and scripts
Leo_not_runnable:
    cmp  x24, #A_NONE
    b.eq Leo_what

    // translate on/off for things without a switch
    cmp  x24, #A_ON
    b.eq Leo_onoff
    cmp  x24, #A_OFF
    b.ne Leo_mask
Leo_onoff:
    tst  x21, #CAP_ON
    b.ne Leo_mask
    tst  x21, #CAP_THERMO
    b.eq Leo_onoff_vac
    mov  x9, #3                       // on: auto; off: off
    cmp  x24, #A_OFF
    csel x9, xzr, x9, eq
    str  x9, [sp, #96]
    ADRL x10, Lmodes
    ldr  x10, [x10, x9, lsl #3]
    ADRL x8, _g_cmd_word
    str  x10, [x8]
    mov  x24, #A_TMODE
    b    Leo_mask
Leo_onoff_vac:
    tst  x21, #CAP_VACUUM
    b.eq Leo_cant
    cmp  x24, #A_ON
    mov  x9, #A_VACSTART
    mov  x10, #A_VACHOME
    csel x24, x9, x10, eq
Leo_mask:
    mov  x0, x24
    bl   _action_mask
    cbz  x0, Leo_light
    tst  x21, x0
    b.eq Leo_cant
    b    Leo_special
Leo_light:
    cmp  x24, #A_ON
    b.eq Leo_go
    cmp  x24, #A_OFF
    b.eq Leo_go
    cmp  x24, #A_RUN
    b.eq Leo_run_other
    cmp  x24, #A_COLOR
    b.eq Leo_need_color
    cmp  x24, #A_CT
    b.eq Leo_need_ct
    cmp  x24, #A_LEVEL
    b.eq Leo_level
    tst  x21, #CAP_LEVEL              // brighter / dimmer
    b.eq Leo_cant
    b    Leo_go
Leo_level:
    tst  x21, #CAP_LEVEL
    b.ne Leo_level_ok
    tst  x21, #CAP_SHADE              // "blinds 50%" = position
    b.ne Leo_go
    tst  x21, #CAP_VOLUME             // a TV at "30%" = volume
    b.eq Leo_cant
    mov  x24, #A_VOLUME
    b    Leo_go
Leo_level_ok:
    ldr  x9, [sp, #96]
    cbnz x9, Leo_go
    mov  x24, #A_OFF                  // "0%" means off
    b    Leo_go
Leo_need_color:
    tst  x21, #CAP_COLOR
    b.eq Leo_cant
    b    Leo_go
Leo_need_ct:
    mov  x9, #(CAP_CT | CAP_COLOR)
    tst  x21, x9
    b.eq Leo_cant
    b    Leo_go
Leo_run_other:                        // "start the fan" / "start the vacuum"
    tst  x21, #CAP_VACUUM
    b.eq Leo_run_on
    mov  x24, #A_VACSTART
    b    Leo_go
Leo_run_on:
    tst  x21, #CAP_ON
    b.eq Leo_cant
    mov  x24, #A_ON
    b    Leo_go

Leo_special:                          // actions that need care
    cmp  x24, #A_UNLOCK
    b.eq Leo_unlock
    cmp  x24, #A_OPEN
    b.ne Leo_go
    tst  x21, #CAP_GARAGE
    b.eq Leo_go
    ADRL x8, _g_remote_active         // opening a garage: never from the mesh
    ldr  x8, [x8]
    cbnz x8, Leo_no_remote
    ADRL x0, Ls_garage_q
    ADRL x1, Ls_garage_info
    ADRL x2, Ls_garage_btn
    bl   _confirm
    cbz  x0, Leo_cancelled
    b    Leo_go
Leo_unlock:
    ADRL x8, _g_remote_active
    ldr  x8, [x8]
    cbnz x8, Leo_no_remote
    ADRL x0, Ls_unlock_q
    ADRL x1, Ls_unlock_info
    ADRL x2, Ls_unlock_btn
    bl   _confirm
    cbz  x0, Leo_cancelled
    b    Leo_go

Leo_runnable:
    cmp  x24, #A_NONE
    b.eq Leo_run_go
    cmp  x24, #A_RUN
    b.eq Leo_run_go
    cmp  x24, #A_ON
    b.ne Leo_cant
Leo_run_go:
    mov  x24, #A_RUN
Leo_go:
    mov  x0, x19
    mov  x1, x24
    ldr  x2, [sp, #96]
    bl   _backend_set
    cbz  x0, Leo_cant
    cmp  x0, #2                       // 2: the backend already said why not
    b.eq Leo_done
    // report
    cmp  x24, #A_RUN
    b.eq Leo_rep_run
    ADRL x8, Lreport
    add  x8, x8, x24, lsl #4
    ldr  x0, [x8]
    cbz  x0, Leo_done
    ldr  x9, [x8, #8]
    mov  x1, x23
    ldr  x2, [sp, #96]
    cmp  x9, #2
    b.ne Leo_rep_say
    ADRL x10, _g_cmd_word
    ldr  x2, [x10]
    cbnz x2, Leo_rep_say
    ADRL x2, Ls_empty
Leo_rep_say:
    bl   _home_say
Leo_done:
    LEAVE 16
Leo_rep_run:
    mov  x1, x23
    ADRL x0, Ls_r_run
    bl   _home_say
    LEAVE 16

Leo_status:
    mov  x0, x19
    bl   _backend_status
    LEAVE 16
Leo_what:
    mov  x1, x23
    ADRL x0, Ls_what_do
    bl   _home_say
    LEAVE 16
Leo_cant:
    mov  x1, x23
    ADRL x0, Ls_cant
    bl   _home_say
    LEAVE 16
Leo_no_remote:
    mov  x1, x23
    ADRL x0, Ls_no_remote
    bl   _home_say
    LEAVE 16
Leo_cancelled:
    mov  x1, x23
    ADRL x0, Ls_cancelled
    bl   _home_say
    LEAVE 16

// long _confirm(const char *fmt_with_name, const char *info, const char *button)
//   The device's name comes from the caller's x23. -> 1 to go ahead
_confirm:
    ENTER 144
    mov  x20, x1
    mov  x21, x2
    mov  x2, x0
    str  x23, [sp]
    add  x0, sp, #96
    mov  x1, #128
    bl   _snprintf
    add  x0, sp, #96
    mov  x1, x20
    mov  x2, x21
    mov  x3, #0
    ADRL x4, Ls_cancel
    bl   _alert_run
    LEAVE 144

// long _backend_set(long idx, long action, long value) -> 1 if sent
_backend_set:
    ENTER 0
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x8, #D_KIND]
    ADRL x10, _g_kind_on              // switched off in Settings: don't touch it
    ldrb w10, [x10, x9]
    cbz  w10, Lbs_svc_off
    cmp  x9, #K_HUE_LIGHT
    b.eq Lbs_hue
    cmp  x9, #K_HUE_GROUP
    b.eq Lbs_hue
    cmp  x9, #K_ST
    b.eq Lbs_st
    cmp  x9, #K_ST_SCENE
    b.eq Lbs_st
    cmp  x9, #K_SHORTCUT
    b.eq Lbs_sc
    cmp  x9, #K_HUE_BLE
    b.eq Lbs_ble
    cmp  x9, #K_WLED
    b.eq Lbs_wled
    cmp  x9, #K_ELGATO
    b.eq Lbs_elgato
    cmp  x9, #K_SHELLY
    b.eq Lbs_shelly
    cmp  x9, #K_NANOLEAF
    b.eq Lbs_nano
    cmp  x9, #K_LIFX
    b.eq Lbs_lifx
    cmp  x9, #K_GOVEE
    b.eq Lbs_govee
    cmp  x9, #K_HA
    b.eq Lbs_ha
    cmp  x9, #K_ROKU
    b.eq Lbs_roku
    cmp  x9, #K_WIZ
    b.eq Lbs_wiz
    cmp  x9, #K_SONOS
    b.eq Lbs_sonos
    cmp  x9, #K_KASA
    b.eq Lbs_kasa
    mov  x0, #0
    LEAVE 0
Lbs_svc_off:
    ADRL x0, Ls_svc_dev_off
    bl   _home_say0
    mov  x0, #2
    LEAVE 0
Lbs_sonos:
    bl   _sonos_set
    LEAVE 0
Lbs_kasa:
    bl   _kasa_set
    LEAVE 0
Lbs_hue:
    bl   _hue_set
    LEAVE 0
Lbs_st:
    bl   _st_set
    LEAVE 0
Lbs_sc:
    bl   _sc_run
    mov  x0, #1
    LEAVE 0
Lbs_ble:
    bl   _hueble_set
    LEAVE 0
Lbs_wled:
    bl   _wled_set
    LEAVE 0
Lbs_elgato:
    bl   _elgato_set
    LEAVE 0
Lbs_shelly:
    bl   _shelly_set
    LEAVE 0
Lbs_nano:
    bl   _nano_set
    LEAVE 0
Lbs_lifx:
    bl   _lifx_set
    LEAVE 0
Lbs_govee:
    bl   _govee_set
    LEAVE 0
Lbs_ha:
    bl   _ha_set
    LEAVE 0
Lbs_roku:
    bl   _roku_set
    LEAVE 0
Lbs_wiz:
    bl   _wiz_set
    LEAVE 0

// void _backend_status(long idx) — ask a live backend, or say what we know
_backend_status:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_devs
    add  x20, x8, x19, lsl #DEV_SHIFT
    ldr  x9, [x20, #D_KIND]
    cmp  x9, #K_ST
    b.eq Lbt_st
    cmp  x9, #K_HA
    b.eq Lbt_ha
    cmp  x9, #K_BLES
    b.eq Lbt_bles
    mov  x0, x19
    bl   _dev_say_state
    LEAVE 0
Lbt_st:
    mov  x0, x19
    bl   _st_status
    LEAVE 0
Lbt_ha:
    mov  x0, x19
    bl   _ha_status
    LEAVE 0
Lbt_bles:
    mov  x0, x19
    bl   _sens_status
    LEAVE 0

// void _dev_say_state(long idx) — "Kitchen: on, 40%"
.globl _dev_say_state
_dev_say_state:
    ENTER 0
    ADRL x8, _g_devs
    add  x20, x8, x0, lsl #DEV_SHIFT
    add  x1, x20, #D_NAME
    ldr  x9, [x20, #D_ON]
    ldr  x3, [x20, #D_LEVEL]
    tbnz x9, #63, Lss_unknown
    ADRL x2, Ls_s_off
    cbz  x9, Lss_onoff
    ADRL x2, Ls_s_on
    tbnz x3, #63, Lss_onoff
    ADRL x0, Ls_s_on_level
    bl   _home_say
    LEAVE 0
Lss_onoff:
    ADRL x0, Ls_s_plain
    bl   _home_say
    LEAVE 0
Lss_unknown:
    ADRL x0, Ls_s_unknown
    bl   _home_say
    LEAVE 0

// ===========================================================================
// Colours for backends that want RGB
// ===========================================================================

// long _hue_to_rgb(long degrees) -> 0xRRGGBB (full saturation and brightness)
.globl _hue_to_rgb
_hue_to_rgb:
    mov  x9, #360
    udiv x10, x0, x9
    msub x0, x10, x9, x0              // 0..359
    mov  x9, #60
    udiv x10, x0, x9                  // sector 0..5
    msub x11, x10, x9, x0             // position in the sector 0..59
    mov  x12, #255
    mul  x13, x11, x12
    udiv x13, x13, x9                 // t = rising
    sub  x14, x12, x13                // q = falling
    cmp  x10, #0
    b.eq Lhr_0
    cmp  x10, #1
    b.eq Lhr_1
    cmp  x10, #2
    b.eq Lhr_2
    cmp  x10, #3
    b.eq Lhr_3
    cmp  x10, #4
    b.eq Lhr_4
    mov  x15, #255                    // 5: (255, 0, q)
    mov  x16, #0
    mov  x17, x14
    b    Lhr_pack
Lhr_0:
    mov  x15, #255
    mov  x16, x13
    mov  x17, #0
    b    Lhr_pack
Lhr_1:
    mov  x15, x14
    mov  x16, #255
    mov  x17, #0
    b    Lhr_pack
Lhr_2:
    mov  x15, #0
    mov  x16, #255
    mov  x17, x13
    b    Lhr_pack
Lhr_3:
    mov  x15, #0
    mov  x16, x14
    mov  x17, #255
    b    Lhr_pack
Lhr_4:
    mov  x15, x13
    mov  x16, #0
    mov  x17, #255
Lhr_pack:
    lsl  x0, x15, #16
    orr  x0, x0, x16, lsl #8
    orr  x0, x0, x17
    ret

// long _kelvin_to_rgb(long kelvin) -> 0xRRGGBB, a close-enough white
.globl _kelvin_to_rgb
_kelvin_to_rgb:
    mov  x9, #3000
    cmp  x0, x9
    b.hi Lkr_neutral
    mov  x0, #0xA957
    movk x0, #0xFF, lsl #16
    ret
Lkr_neutral:
    mov  x9, #4500
    cmp  x0, x9
    b.hi Lkr_cool
    mov  x0, #0xD1A3
    movk x0, #0xFF, lsl #16
    ret
Lkr_cool:
    mov  x0, #0xECE0
    movk x0, #0xFF, lsl #16
    ret

// const char *_app_field(long app, long field /*0 name 3 tizen 4 roku*/)
.globl _app_field
_app_field:
    mov  x9, #40
    mul  x9, x0, x9
    ADRL x8, _g_apps
    add  x8, x8, x9
    ldr  x0, [x8, x1, lsl #3]
    ret

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lthermwords:
    .quad Lw_to_sp, Lw_at_sp, Lw_heat, Lw_cool, Lw_thermostat, Lw_temperature, 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_svc_dev_off: .asciz "\302\267 \342\217\270 That device\342\200\231s service is switched off. Turn it on in Settings (\342\214\230,)."
Lw_help:        .asciz "help"
Lw_devices:     .asciz "devices"
Lw_list:        .asciz "list"
Lw_status:      .asciz "status"
Lw_what:        .asciz "what's"
Lw_what2:       .asciz "what\342\200\231s"
Lw_whats:       .asciz "whats"
Lw_check:       .asciz "check"
Lw_is:          .asciz "is"
Lw_are:         .asciz "are"
Lw_battery:     .asciz "battery"
Lw_pair:        .asciz "pair"
Lw_refresh:     .asciz "refresh"
Lw_rescan:      .asciz "rescan"
Lw_connect:     .asciz "connect"
Lw_token:       .asciz "token"
Lw_setup:       .asciz "setup"
Lw_link:        .asciz "link"
Lw_smartthings: .asciz "smartthings"
Lw_assistant:   .asciz "home assistant"
Lw_homeassistant: .asciz "homeassistant"
Lw_lifx:        .asciz "lifx"
Lw_govee:       .asciz "govee"
Lw_nanoleaf:    .asciz "nanoleaf"
Lw_hue:         .asciz "hue"
Lw_unlock:      .asciz "unlock"
Lw_lock:        .asciz "lock"
Lw_locks:       .asciz "locks"
Lw_unmute:      .asciz "unmute"
Lw_mute:        .asciz "mute"
Lw_volume:      .asciz "volume"
Lw_louder:      .asciz "louder"
Lw_quieter:     .asciz "quieter"
Lw_softer:      .asciz "softer"
Lw_channel:     .asciz "channel"
Lw_next:        .asciz "next"
Lw_previous:    .asciz "previous"
Lw_prev:        .asciz "prev"
Lw_hdmi:        .asciz "hdmi"
Lw_input:       .asciz "input"
Lw_source:      .asciz "source"
Lw_antenna:     .asciz "antenna"
Lw_live:        .asciz "live"
Lw_thermostat:  .asciz "thermostat"
Lw_temperature: .asciz "temperature"
Lw_degrees:     .asciz "degrees"
Lw_heat:        .asciz "heat"
Lw_heating:     .asciz "heating"
Lw_cool:        .asciz "cool"
Lw_cooling:     .asciz "cooling"
Lw_auto:        .asciz "auto"
Lw_ac:          .asciz "ac"
Lw_hvac:        .asciz "hvac"
Lw_fan:         .asciz "fan"
Lw_fans:        .asciz "fans"
Lw_high:        .asciz "high"
Lw_max:         .asciz "max"
Lw_medium:      .asciz "medium"
Lw_low:         .asciz "low"
Lw_vacuum:      .asciz "vacuum"
Lw_vacuuming:   .asciz "vacuuming"
Lw_roomba:      .asciz "roomba"
Lw_robot:       .asciz "robot"
Lw_clean:       .asciz "clean"
Lw_cleaning:    .asciz "cleaning"
Lw_dock:        .asciz "dock"
Lw_home:        .asciz "home"
Lw_return:      .asciz "return"
Lw_base:        .asciz "base"
Lw_pause:       .asciz "pause"
Lw_resume:      .asciz "resume"
Lw_play:        .asciz "play"
Lw_stop:        .asciz "stop"
Lw_rewind:      .asciz "rewind"
Lw_forward:     .asciz "forward"
Lw_homescreen:  .asciz "home screen"
Lw_presshome:   .asciz "press home"
Lw_goback:      .asciz "go back"
Lw_pressback:   .asciz "press back"
Lw_pressok:     .asciz "press ok"
Lw_select:      .asciz "select"
Lw_open:        .asciz "open"
Lw_raise:       .asciz "raise"
Lw_close:       .asciz "close"
Lw_shut:        .asciz "shut"
Lw_lower:       .asciz "lower"
Lw_white:       .asciz "white"
Lw_warm:        .asciz "warm"
Lw_cold:        .asciz "cold"
Lw_daylight:    .asciz "daylight"
Lw_brighter:    .asciz "brighter"
Lw_brighten:    .asciz "brighten"
Lw_up:          .asciz "up"
Lw_dimmer:      .asciz "dimmer"
Lw_dim:         .asciz "dim"
Lw_down:        .asciz "down"
Lw_off:         .asciz "off"
Lw_on:          .asciz "on"
Lw_run:         .asciz "run"
Lw_start:       .asciz "start"
Lw_activate:    .asciz "activate"
Lw_all:         .asciz "all"
Lw_every:       .asciz "every"
Lw_everything:  .asciz "everything"
Lw_lights:      .asciz "lights"
Lw_light:       .asciz "light"
Lw_lamp:        .asciz "lamp"
Lw_lamps:       .asciz "lamps"
Lw_the:         .asciz "the"
Lw_smart:       .asciz "smart"
Lw_my:          .asciz "my"
Lw_tv:          .asciz "tv"
Lw_tvs:         .asciz "tvs"
Lw_television:  .asciz "television"
Lw_blinds:      .asciz "blinds"
Lw_blind:       .asciz "blind"
Lw_shades:      .asciz "shades"
Lw_shade:       .asciz "shade"
Lw_curtains:    .asciz "curtains"
Lw_curtain:     .asciz "curtain"
Lw_garage:      .asciz "garage"
Lw_valve:       .asciz "valve"
Lw_sprinkler:   .asciz "sprinkler"
Lw_roku:        .asciz "roku"
Lw_power:       .asciz "power"
Lw_energy:      .asciz "energy"
Lw_watts:       .asciz "watts"
Lw_how:         .asciz "how"
Lw_to_sp:       .asciz "to"
Lw_at_sp:       .asciz "at"
Lw_red:         .asciz "red"
Lw_orange:      .asciz "orange"
Lw_yellow:      .asciz "yellow"
Lw_green:       .asciz "green"
Lw_teal:        .asciz "teal"
Lw_cyan:        .asciz "cyan"
Lw_blue:        .asciz "blue"
Lw_violet:      .asciz "violet"
Lw_purple:      .asciz "purple"
Lw_magenta:     .asciz "magenta"
Lw_pink:        .asciz "pink"
Lw_netflix:     .asciz "netflix"
Lw_youtube:     .asciz "youtube"
Lw_prime:       .asciz "prime video"
Lw_amazon:      .asciz "amazon"
Lw_disney:      .asciz "disney"
Lw_appletv:     .asciz "apple tv"
Lw_spotify:     .asciz "spotify"
Lw_plex:        .asciz "plex"
Lw_hulu:        .asciz "hulu"
La_netflix:     .asciz "Netflix"
La_youtube:     .asciz "YouTube"
La_prime:       .asciz "Prime Video"
La_disney:      .asciz "Disney+"
La_appletv:     .asciz "Apple TV"
La_spotify:     .asciz "Spotify"
La_plex:        .asciz "Plex"
La_hulu:        .asciz "Hulu"
Lt_netflix:     .asciz "3201907018807"
Lt_youtube:     .asciz "111299001912"
Lt_prime:       .asciz "3201910019365"
Lt_disney:      .asciz "3201901017640"
Lt_appletv:     .asciz "3201807016597"
Lt_spotify:     .asciz "3201606009684"
Lt_plex:        .asciz "3201512006963"
Lt_hulu:        .asciz "3201601007625"
Lr_netflix:     .asciz "12"
Lr_youtube:     .asciz "837"
Lr_prime:       .asciz "13"
Lr_disney:      .asciz "291097"
Lr_appletv:     .asciz "551012"
Lr_spotify:     .asciz "22297"
Lr_plex:        .asciz "13535"
Lr_hulu:        .asciz "2285"
Lk_home:        .asciz "Home"
Lk_back:        .asciz "Back"
Lk_ok:          .asciz "OK"
Lf_hdmi:        .asciz "HDMI %ld"
Ls_tv_input:    .asciz "TV"

Ls_empty:            .asciz ""
Ls_cancel:           .asciz "Cancel"
Ls_no_devices:       .asciz "\302\267 No devices yet. Say \342\200\234help\342\200\235 to see how to connect Hue, SmartThings, Home Assistant, LIFX, Govee and the rest."
Ls_no_match:         .asciz "\302\267 I couldn't tell which device you meant. Say \342\200\234devices\342\200\235 to hear the names I know."
Ls_no_idea:          .asciz "\302\267 I didn't catch a device or what to do. Try \342\200\234kitchen lights off\342\200\235 or \342\200\234TV volume 20\342\200\235, or say \342\200\234help\342\200\235."
Ls_which:            .asciz "\302\267 More than one device could do that \342\200\224 say its name, or \342\200\234all\342\200\235. Say \342\200\234devices\342\200\235 to hear them."
Ls_connect_what:     .asciz "\302\267 Connect what? Say \342\200\234connect smartthings\342\200\235, \342\200\234connect home assistant\342\200\235, \342\200\234connect lifx\342\200\235, \342\200\234connect govee\342\200\235, \342\200\234pair nanoleaf\342\200\235 or \342\200\234pair hue\342\200\235."
Ls_what_do:          .asciz "\302\267 What should %s do?"
Ls_cant:             .asciz "\302\267 %s can't do that."
Ls_no_remote:        .asciz "\302\267 %s: that only works from this Mac, never over the mesh."
Ls_cancelled:        .asciz "\302\267 %s: cancelled."
Ls_unlock_q:         .asciz "Unlock %s?"
Ls_unlock_info:      .asciz "asmmesh will unlock it right away."
Ls_unlock_btn:       .asciz "Unlock"
Ls_garage_q:         .asciz "Open %s?"
Ls_garage_info:      .asciz "asmmesh will open it right away. Make sure the way is clear."
Ls_garage_btn:       .asciz "Open"
Ls_s_on:             .asciz "on"
Ls_s_off:            .asciz "off"
Ls_s_plain:          .asciz "\302\267 %s: %s"
Ls_s_on_level:       .asciz "\302\267 %s: %s, %ld%%"
Ls_s_unknown:        .asciz "\302\267 %s: no state known yet"
Ls_r_what:           .asciz "\302\267 %s"
Ls_r_on:             .asciz "\302\267 %s \342\206\222 on"
Ls_r_off:            .asciz "\302\267 %s \342\206\222 off"
Ls_r_level:          .asciz "\302\267 %s \342\206\222 %ld%%"
Ls_r_word:           .asciz "\302\267 %s \342\206\222 %s"
Ls_r_lock:           .asciz "\302\267 %s \342\206\222 locking"
Ls_r_unlock:         .asciz "\302\267 %s \342\206\222 unlocking"
Ls_r_run:            .asciz "\302\267 Running \342\200\234%s\342\200\235"
Ls_r_brighter:       .asciz "\302\267 %s \342\206\222 brighter"
Ls_r_dimmer:         .asciz "\302\267 %s \342\206\222 dimmer"
Ls_r_volume:         .asciz "\302\267 %s \342\206\222 volume %ld"
Ls_r_volup:          .asciz "\302\267 %s \342\206\222 volume up"
Ls_r_voldown:        .asciz "\302\267 %s \342\206\222 volume down"
Ls_r_mute:           .asciz "\302\267 %s \342\206\222 muted"
Ls_r_unmute:         .asciz "\302\267 %s \342\206\222 unmuted"
Ls_r_channel:        .asciz "\302\267 %s \342\206\222 channel %ld"
Ls_r_chup:           .asciz "\302\267 %s \342\206\222 channel up"
Ls_r_chdown:         .asciz "\302\267 %s \342\206\222 channel down"
Ls_r_play:           .asciz "\302\267 %s \342\206\222 play"
Ls_r_pause:          .asciz "\302\267 %s \342\206\222 pause"
Ls_r_stop:           .asciz "\302\267 %s \342\206\222 stop"
Ls_r_ffwd:           .asciz "\302\267 %s \342\206\222 fast forward"
Ls_r_rewind:         .asciz "\302\267 %s \342\206\222 rewind"
Ls_r_app:            .asciz "\302\267 %s \342\206\222 opening %s"
Ls_r_open:           .asciz "\302\267 %s \342\206\222 opening"
Ls_r_close:          .asciz "\302\267 %s \342\206\222 closing"
Ls_r_heat:           .asciz "\302\267 %s \342\206\222 heat to %ld\302\260"
Ls_r_cool:           .asciz "\302\267 %s \342\206\222 cool to %ld\302\260"
Ls_r_temp:           .asciz "\302\267 %s \342\206\222 %ld\302\260"
Ls_r_fan:            .asciz "\302\267 %s \342\206\222 fan %s"
Ls_r_vacstart:       .asciz "\302\267 %s \342\206\222 cleaning"
Ls_r_vachome:        .asciz "\302\267 %s \342\206\222 back to the dock"
