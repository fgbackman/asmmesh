// rules.s — schedules and "when …" rules, and the Home words that aren't device
// commands (weather, where is my …, notify, say, …).
//
//   at 7 pm turn off the tv            once, the next time it is 7 pm
//   in 20 minutes turn off the tv      once
//   every weekday at 7 am kitchen on   (every day, weekends, on Mondays, tomorrow …)
//   turn on the porch light at sunset  (the time can come last, too)
//   remind me in 10 minutes to check the oven
//   when Anna arrives turn on the hall light      her Mac on the mesh, or a Bluetooth
//   when Anna leaves …                            gadget that says that name
//   when the front door opens turn on the hall light
//   notify me when the garage opens
//   rules · cancel rule 2 · cancel all rules
//
// Rules run while asmmesh is open. Repeating rules are saved as the sentence you
// typed and understood again at the next launch; one-off ones are not kept.

.include "macros.inc"

.set RULE_MAX,    24
.set RULE_SHIFT,  9
.set RU_TYPE,     0
.set RU_DAYS,     8
.set RU_MIN,      16
.set RU_WHEN,     24          // R_AT: when; R_PRES/R_DEV: its event entry
.set RU_FIELD,    32
.set RU_WANT,     40
.set RU_PREV,     48
.set RU_LAST,     56          // day it last fired (year*1000 + day of year)
.set RU_ONCE,     64
.set RU_PEND,     72
.set RU_SUBJ,     80
.set RU_SUBJ_MAX, 64
.set RU_CMD,      144
.set RU_CMD_MAX,  160
.set RU_SENT,     304
.set RU_SENT_MAX, 208
.set R_AT,        1
.set R_CLOCK,     2
.set R_PRES,      3
.set R_DEV,       4
.set R_THR,       5           // a sensor reading crosses a number: RU_FIELD what (1 temperature,
                              //   2 humidity, 4 moisture, 5 light), RU_DAYS 1 above / 0 below,
                              //   RU_MIN the number (hundredths; degrees C)
.set R_BTN,       6           // a Bluetooth button: RU_DAYS which (0 any), RU_WANT the press
.set T_SUNRISE,   2000
.set T_SUNSET,    2001
.set TM_MIN,      4
.set TM_HOUR,     8
.set TM_YEAR,     20
.set TM_WDAY,     24
.set TM_YDAY,     28
.set EV_SIZE,     48
.set DAY_TOMORROW, 0x100
.set DAY_TODAY,   0x200

.macro RULEA reg, idx
    ADRL \reg, _g_rules
    add  \reg, \reg, \idx, lsl #RULE_SHIFT
.endm

.data
.p2align 3
.globl _g_rule_count
_g_rule_count:  .quad 0
_g_last_min:    .quad -1
_g_last_day:    .quad 0
_g_busy:        .quad 0
.globl _g_now
_g_now:         .quad 0
_g_cur_min:     .quad 0
_g_today:       .quad 0
_g_wday:        .quad 0
_g_tp_end:      .quad 0
.globl _g_rules
.zerofill __DATA,__bss,_g_rules,12288,4
.zerofill __DATA,__bss,_g_x_lc,256,4
.zerofill __DATA,__bss,_g_x_orig,256,4
.zerofill __DATA,__bss,_g_subj,64,4
.globl _g_cmdtmp
.zerofill __DATA,__bss,_g_cmdtmp,160,4
.zerofill __DATA,__bss,_g_cmdtmp2,160,4
.zerofill __DATA,__bss,_g_fire_cmd,160,4
.zerofill __DATA,__bss,_g_run,256,4
.zerofill __DATA,__bss,_g_rsave,6400,4
.zerofill __DATA,__bss,_g_wtxt,96,4
.zerofill __DATA,__bss,_g_clk,48,4
.zerofill __DATA,__bss,_g_clk2,32,4
.zerofill __DATA,__bss,_g_route,256,4

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
// pattern, 0 whole sentence / 1 first words / 2 whole sentence and fine to route
// from a chat room / 3 first words and fine to route, handler(arg, rest, rest in the original case), arg
Lsimple:
    .quad Lw_rules,          0, _h_rules_list, 0
    .quad Lw_list_rules,     0, _h_rules_list, 0
    .quad Lw_show_rules,     0, _h_rules_list, 0
    .quad Lw_my_rules,       0, _h_rules_list, 0
    .quad Lw_cancel_all,     0, _h_rules_clear, 0
    .quad Lw_clear_rules,    0, _h_rules_clear, 0
    .quad Lw_clear_all,      0, _h_rules_clear, 0
    .quad Lw_delete_all,     0, _h_rules_clear, 0
    .quad Lw_remove_all,     0, _h_rules_clear, 0
    .quad Lw_where_am_i,     0, _h_where, 0
    .quad Lw_sos,            2, _h_sos, 0
    .quad Lw_send_sos,       2, _h_sos, 0
    .quad Lw_location,       2, _h_where, 0
    .quad Lw_my_address,     2, _h_where, 0
    .quad Lw_where_this_mac, 2, _h_where, 0
    .quad Lw_alerts,         2, _h_alerts, 0
    .quad Lw_weather_alerts, 2, _h_alerts, 0
    .quad Lw_any_alerts,     2, _h_alerts, 0
    .quad Lw_ntfy,           2, _h_ntfy_info, 0
    .quad Lw_ntfy_test,      2, _h_push_test, 0
    .quad Lw_push_test,      2, _h_push_test, 0
    .quad Lw_test_push,      2, _h_push_test, 0
    .quad Lw_pushover,       2, _h_pushover, 0
    .quad Lw_pushover_test,  2, _h_push_test, 0
    .quad Lw_pushover_token, 3, _h_po_key, 0
    .quad Lw_pushover_user,  3, _h_po_key, 1
    .quad Lw_webhook,        2, _h_webhook, 0
    .quad Lw_webhook_new,    2, _h_webhook_new, 0
    .quad Lw_files,          2, _h_files, 0
    .quad Lw_files_page,     2, _h_files, 0
    .quad Lw_file_page,      2, _h_files, 0
    .quad Lw_files_new,      2, _h_files_new, 0
    .quad Lw_share_folders,  2, _h_files_choose, 0
    .quad Lw_files_choose,   2, _h_files_choose, 0
    .quad Lw_airdrop,        2, _h_airdrop, 0
    .quad Lw_airdrop_file,   2, _h_airdrop, 0
    .quad Lw_fm_rep_on,      2, _h_fm_repeat, 1
    .quad Lw_fm_rep_off,     2, _h_fm_repeat, 0
    .quad Lw_spin,           2, _h_spin, 0
    .quad Lw_spin_debug,     2, _h_spin_debug, 0
    .quad Lw_spin_status,    2, _h_spin, 0
    .quad Lw_connect_spin,   2, _h_spin_connect, 0
    .quad Lw_pair_spin,      2, _h_spin_connect, 0
    .quad Lw_spin_color,     3, _h_spin_color, 0
    .quad Lw_spin_colour,    3, _h_spin_color, 0
    .quad Lw_spin_controls,  3, _h_spin_target, 0
    .quad Lw_spin_drives,    3, _h_spin_target, 0
    .quad Lw_services,       2, _h_services, 0
    .quad Lw_bitchat,        2, _h_bitchat, 0
    .quad Lw_bitchat_status, 2, _h_bitchat, 0
    .quad Lw_bc_adv_on,      2, _h_bitchat_adv, 1
    .quad Lw_bc_adv_off,     2, _h_bitchat_adv, 0
    .quad Lw_bc_people,      2, _h_bitchat_people, 0
    .quad Lw_bc_forget,      0, _h_bitchat_forget, 0
    .quad Lw_bc_ann_on,      0, _h_bitchat_quiet, 0
    .quad Lw_bc_ann_off,     0, _h_bitchat_quiet, 1
    .quad Lw_settings,       2, _h_services, 0
    .quad Lw_service_list,   2, _h_services, 0
    .quad Lw_enable,         1, _h_svc_switch, 1
    .quad Lw_disable,        1, _h_svc_switch, 0
    .quad Lw_spin_groups,    2, _h_spin_groups, 0
    .quad Lw_spin_colors,    2, _h_spin_groups, 0
    .quad Lw_spin_group,     3, _h_spin_group, 0
    .quad Lw_spin_off,       2, _h_spin_lock, 1
    .quad Lw_spin_lock,      2, _h_spin_lock, 1
    .quad Lw_lock_spin,      2, _h_spin_lock, 1
    .quad Lw_spin_on,        2, _h_spin_lock, 0
    .quad Lw_spin_unlock,    2, _h_spin_lock, 0
    .quad Lw_unlock_spin,    2, _h_spin_lock, 0
    .quad Lw_trackers,       2, _h_trackers, 0
    .quad Lw_sensors,        2, _h_sensors, 0
    .quad Lw_list_sensors,   2, _h_sensors, 0
    .quad Lw_my_sensors,     2, _h_sensors, 0
    .quad Lw_bt_sensors,     2, _h_sensors, 0
    .quad Lw_batteries,      2, _h_batteries, 0
    .quad Lw_battery,        2, _h_batteries, 0
    .quad Lw_battery_levels, 2, _h_batteries, 0
    .quad Lw_low_batteries,  2, _h_batteries, 0
    .quad Lw_check_batteries, 2, _h_batteries, 0
    .quad Lw_hp_here,        2, _h_hp_here, 0
    .quad Lw_air_here,       2, _h_hp_here, 0
    .quad Lw_hp_here2,       2, _h_hp_here, 0
    .quad Lw_air_here2,      2, _h_hp_here, 0
    .quad Lw_hp_take,        2, _h_hp_here, 0
    .quad Lw_air_take,       2, _h_hp_here, 0
    .quad Lw_hp_switch,      2, _h_hp_here, 0
    .quad Lw_air_switch,     2, _h_hp_here, 0
    .quad Lw_list_trackers,  2, _h_trackers, 0
    .quad Lw_any_trackers,   2, _h_trackers, 0
    .quad Lw_trackers_near,  2, _h_trackers, 0
    .quad Lw_trust,          0, _h_trust, 0
    .quad Lw_trust1,         0, _h_trust, 0
    .quad Lw_trust2,         0, _h_trust, 0
    .quad Lw_trust3,         0, _h_trust, 0
    .quad Lw_weather,        2, _h_weather, 1
    .quad Lw_weather_today,  2, _h_weather, 1
    .quad Lw_weather_now,    2, _h_weather, 1
    .quad Lw_forecast,       2, _h_weather, 1
    .quad Lw_whats_weather,  2, _h_weather, 1
    .quad Lw_hows_weather,   2, _h_weather, 1
    .quad Lw_weather_tom,    2, _h_weather, 2
    .quad Lw_forecast_tom,   2, _h_weather, 2
    .quad Lw_tom_weather,    2, _h_weather, 2
    .quad Lw_tom_weather2,   2, _h_weather, 2
    .quad Lw_air_quality,    2, _h_weather, 3
    .quad Lw_aqi,            2, _h_weather, 3
    .quad Lw_hows_air,       2, _h_weather, 3
    .quad Lw_sunset,         2, _h_weather, 4
    .quad Lw_sunrise,        2, _h_weather, 4
    .quad Lw_when_sunset,    2, _h_weather, 4
    .quad Lw_when_sunrise,   2, _h_weather, 4
    .quad Lw_whens_sunset,   2, _h_weather, 4
    .quad Lw_whens_sunset2,  2, _h_weather, 4
    .quad Lw_will_rain,      2, _h_weather, 5
    .quad Lw_will_rain_today, 2, _h_weather, 5
    .quad Lw_will_rain_tom,  2, _h_weather, 5
    .quad Lw_going_to_rain,  2, _h_weather, 5
    .quad Lw_use_c,          0, _h_units, 1
    .quad Lw_celsius,        0, _h_units, 1
    .quad Lw_use_f,          0, _h_units, 0
    .quad Lw_fahrenheit,     0, _h_units, 0
    .quad Lw_energy,         0, _h_energy, 0
    .quad Lw_energy_use,     0, _h_energy, 0
    .quad Lw_energy_usage,   0, _h_energy, 0
    .quad Lw_power_use,      0, _h_energy, 0
    .quad Lw_power_usage,    0, _h_energy, 0
    .quad Lw_how_much_power, 0, _h_energy, 0
    .quad Lw_how_much_energy, 0, _h_energy, 0
    .quad Lw_watts,          0, _h_energy, 0
    .quad Lw_help_more,      0, _h_help_more, 0
    .quad Lw_more_help,      0, _h_help_more, 0
    .quad Lw_what_else,      0, _h_help_more, 0
    .quad Lw_help_rules,     0, _h_help_more, 0
    .quad Lw_cancel_rule,    1, _h_rule_cancel, 0
    .quad Lw_delete_rule,    1, _h_rule_cancel, 0
    .quad Lw_remove_rule,    1, _h_rule_cancel, 0
    .quad Lw_stop_rule,      1, _h_rule_cancel, 0
    .quad Lw_this_mac_in,    1, _h_room_set, 0
    .quad Lw_this_comp_in,   1, _h_room_set, 0
    .quad Lw_im_in,          1, _h_room_set, 0
    .quad Lw_im_in2,         1, _h_room_set, 0
    .quad Lw_i_am_in,        1, _h_room_set, 0
    .quad Lw_where_is_my,    1, _h_find, 0
    .quad Lw_where_are_my,   1, _h_find, 0
    .quad Lw_wheres_my,      1, _h_find, 0
    .quad Lw_wheres_my2,     1, _h_find, 0
    .quad Lw_find_my,        1, _h_find, 0
    .quad Lw_where_is,       1, _h_find, 0
    .quad Lw_where_are,      1, _h_find, 0
    .quad Lw_wheres,         1, _h_find, 0
    .quad Lw_wheres2,        1, _h_find, 0
    .quad Lw_locate,         1, _h_find, 0
    .quad Lw_notify_topic,   1, _h_ntfy_topic, 0
    .quad Lw_ntfy_topic,     1, _h_ntfy_topic, 0
    .quad Lw_notif_topic,    1, _h_ntfy_topic, 0
    .quad Lw_notify,         1, _h_notify, 0
    .quad Lw_push,           1, _h_notify, 0
    .quad Lw_ntfy,           1, _h_notify, 0
    .quad Lw_ifttt_key,      1, _h_ifttt_key, 0
    .quad Lw_trigger,        1, _h_trigger, 0
    .quad Lw_ifttt,          1, _h_trigger, 0
    .quad Lw_say,            1, _h_say, 0
    .quad Lw_speak,          1, _h_say, 0
    .quad Lw_my_city,        1, _h_city, 0
    .quad Lw_i_live_in,      1, _h_city, 0
    .quad Lw_set_city_to,    1, _h_city, 0
    .quad Lw_set_city,       1, _h_city, 0
    .quad Lw_my_location,    1, _h_city, 0
    .quad Lw_set_loc_to,     1, _h_city, 0
    .quad Lw_set_loc,        1, _h_city, 0
    .quad Lw_http_get,       1, _h_http_get, 0
    .quad Lw_name_sensor,    3, _h_sens_name, 0
    .quad Lw_send_hp,        3, _h_hp_send, 0
    .quad Lw_send_hp2,       3, _h_hp_send, 0
    .quad Lw_send_air,       3, _h_hp_send, 0
    .quad Lw_send_air2,      3, _h_hp_send, 0
    .quad 0, 0, 0, 0

// what a rule (or "at 7 pm …") may do besides device commands: pattern, runner(text)
Lrun_pats:
    .quad Lw_notify,  _notify_quiet
    .quad Lw_push,    _notify_quiet
    .quad Lw_ntfy,    _notify_quiet
    .quad Lw_say,     _say_text
    .quad Lw_speak,   _say_text
    .quad Lw_trigger, _trigger_event
    .quad Lw_ifttt,   _trigger_event
    .quad Lw_remind,  _remind
    .quad 0, 0

Lwhen_pats:
    .quad Lw_notify_when, 1
    .quad Lw_tell_when,   1
    .quad Lw_alert_when,  1
    .quad Lw_letmek_when, 1
    .quad Lw_ping_when,   1
    .quad Lw_text_when,   1
    .quad Lw_whenever,    0
    .quad Lw_when,        0
    .quad Lw_if,          0
    .quad 0, 0

Lnotify_me:
    .quad Lw_notify_me, Lw_tell_me, Lw_let_me_know, Lw_alert_me, Lw_notify, Lw_ping_me
    .quad Lw_text_me, Lw_send_notif, 0

// " arrives", rule type, field, value that fires it, past tense, present tense
Levents:
    .quad Le_comes_home,  R_PRES, 0, 1, Lp_arrived, Lq_arrives
    .quad Le_gets_home,   R_PRES, 0, 1, Lp_arrived, Lq_arrives
    .quad Le_arrives_home, R_PRES, 0, 1, Lp_arrived, Lq_arrives
    .quad Le_arrives,     R_PRES, 0, 1, Lp_arrived, Lq_arrives
    .quad Le_arrive,      R_PRES, 0, 1, Lp_arrived, Lq_arrives
    .quad Le_gets_here,   R_PRES, 0, 1, Lp_arrived, Lq_arrives
    .quad Le_comes_back,  R_PRES, 0, 1, Lp_arrived, Lq_arrives
    .quad Le_is_home,     R_PRES, 0, 1, Lp_arrived, Lq_arrives
    .quad Le_leaves_home, R_PRES, 0, 0, Lp_left, Lq_leaves
    .quad Le_leaves,      R_PRES, 0, 0, Lp_left, Lq_leaves
    .quad Le_leave,       R_PRES, 0, 0, Lp_left, Lq_leaves
    .quad Le_goes_out,    R_PRES, 0, 0, Lp_left, Lq_leaves
    .quad Le_is_away,     R_PRES, 0, 0, Lp_left, Lq_leaves
    .quad Le_turns_on,    R_DEV, D_ON, 1, Lp_turned_on, Lq_turns_on
    .quad Le_is_turned_on, R_DEV, D_ON, 1, Lp_turned_on, Lq_turns_on
    .quad Le_goes_on,     R_DEV, D_ON, 1, Lp_turned_on, Lq_turns_on
    .quad Le_switches_on, R_DEV, D_ON, 1, Lp_turned_on, Lq_turns_on
    .quad Le_turns_off,   R_DEV, D_ON, 0, Lp_turned_off, Lq_turns_off
    .quad Le_is_turned_off, R_DEV, D_ON, 0, Lp_turned_off, Lq_turns_off
    .quad Le_goes_off,    R_DEV, D_ON, 0, Lp_turned_off, Lq_turns_off
    .quad Le_switches_off, R_DEV, D_ON, 0, Lp_turned_off, Lq_turns_off
    .quad Le_opens,       R_DEV, D_OPEN, 1, Lp_opened, Lq_opens
    .quad Le_is_opened,   R_DEV, D_OPEN, 1, Lp_opened, Lq_opens
    .quad Le_is_open,     R_DEV, D_OPEN, 1, Lp_opened, Lq_opens
    .quad Le_open,        R_DEV, D_OPEN, 1, Lp_opened, Lq_opens
    .quad Le_closes,      R_DEV, D_OPEN, 0, Lp_closed, Lq_closes
    .quad Le_is_closed,   R_DEV, D_OPEN, 0, Lp_closed, Lq_closes
    .quad Le_shuts,       R_DEV, D_OPEN, 0, Lp_closed, Lq_closes
    .quad Le_close,       R_DEV, D_OPEN, 0, Lp_closed, Lq_closes
    .quad Le_unlocks,     R_DEV, D_LOCKED, 0, Lp_unlocked, Lq_unlocks
    .quad Le_is_unlocked, R_DEV, D_LOCKED, 0, Lp_unlocked, Lq_unlocks
    .quad Le_locks,       R_DEV, D_LOCKED, 1, Lp_locked, Lq_locks
    .quad Le_is_locked,   R_DEV, D_LOCKED, 1, Lp_locked, Lq_locks
    .quad Le_detects_motion, R_DEV, D_MOTION, 1, Lp_motion, Lq_motion
    .quad Le_sees_motion, R_DEV, D_MOTION, 1, Lp_motion, Lq_motion
    .quad Le_senses_motion, R_DEV, D_MOTION, 1, Lp_motion, Lq_motion
    .quad Le_stops_motion, R_DEV, D_MOTION, 0, Lp_still, Lq_still
    .quad Le_is_clear,    R_DEV, D_MOTION, 0, Lp_still, Lq_still
    .quad Le_detects_water, R_DEV, D_WET, 1, Lp_wet, Lq_wet
    .quad Le_detects_leak, R_DEV, D_WET, 1, Lp_wet, Lq_wet
    .quad Le_gets_wet,    R_DEV, D_WET, 1, Lp_wet, Lq_wet
    .quad Le_is_wet,      R_DEV, D_WET, 1, Lp_wet, Lq_wet
    .quad Le_is_dry,      R_DEV, D_WET, 0, Lp_dry, Lq_dry
    .quad Le_gets_above,  R_THR, 1, 1, Lp_above, Lq_above
    .quad Le_goes_above,  R_THR, 1, 1, Lp_above, Lq_above
    .quad Le_rises_above, R_THR, 1, 1, Lp_above, Lq_above
    .quad Le_climbs_above, R_THR, 1, 1, Lp_above, Lq_above
    .quad Le_is_above,    R_THR, 1, 1, Lp_above, Lq_above
    .quad Le_gets_over,   R_THR, 1, 1, Lp_above, Lq_above
    .quad Le_goes_over,   R_THR, 1, 1, Lp_above, Lq_above
    .quad Le_is_over,     R_THR, 1, 1, Lp_above, Lq_above
    .quad Le_drops_below, R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_falls_below, R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_goes_below,  R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_gets_below,  R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_dips_below,  R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_is_below,    R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_drops_under, R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_falls_under, R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_goes_under,  R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_gets_under,  R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_is_under,    R_THR, 0, 1, Lp_below, Lq_below
    .quad Le_is_pressed,  R_BTN, 0, 1, Lp_pressed, Lq_pressed
    .quad Le_gets_pressed, R_BTN, 0, 1, Lp_pressed, Lq_pressed
    .quad Le_is_clicked,  R_BTN, 0, 1, Lp_pressed, Lq_pressed
    .quad Le_is_double,   R_BTN, 0, 2, Lp_double, Lq_double
    .quad Le_is_double2,  R_BTN, 0, 2, Lp_double, Lq_double
    .quad Le_is_double3,  R_BTN, 0, 2, Lp_double, Lq_double
    .quad Le_is_triple,   R_BTN, 0, 3, Lp_triple, Lq_triple
    .quad Le_is_triple2,  R_BTN, 0, 3, Lp_triple, Lq_triple
    .quad Le_is_long,     R_BTN, 0, 4, Lp_long, Lq_long
    .quad Le_is_long2,    R_BTN, 0, 4, Lp_long, Lq_long
    .quad Le_is_held,     R_BTN, 0, 4, Lp_long, Lq_long
    .quad Le_is_held_down, R_BTN, 0, 4, Lp_long, Lq_long
    .quad Le_pressed_held, R_BTN, 0, 4, Lp_long, Lq_long
    .quad 0, 0, 0, 0, 0, 0

// day phrases (longest first where one ends another), mask of days (bit 0 Sunday)
Ldays:
    .quad Ld_every_day, 0x7f
    .quad Ld_everyday, 0x7f
    .quad Ld_daily, 0x7f
    .quad Ld_each_day, 0x7f
    .quad Ld_every_morning, 0x7f
    .quad Ld_every_evening, 0x7f
    .quad Ld_every_night, 0x7f
    .quad Ld_every_weekday, 0x3e
    .quad Ld_on_weekdays, 0x3e
    .quad Ld_weekdays, 0x3e
    .quad Ld_every_weekend, 0x41
    .quad Ld_on_weekends, 0x41
    .quad Ld_weekends, 0x41
    .quad Ld_every_sun, 0x01
    .quad Ld_on_suns, 0x01
    .quad Ld_suns, 0x01
    .quad Ld_every_mon, 0x02
    .quad Ld_on_mons, 0x02
    .quad Ld_mons, 0x02
    .quad Ld_every_tue, 0x04
    .quad Ld_on_tues, 0x04
    .quad Ld_tues, 0x04
    .quad Ld_every_wed, 0x08
    .quad Ld_on_weds, 0x08
    .quad Ld_weds, 0x08
    .quad Ld_every_thu, 0x10
    .quad Ld_on_thus, 0x10
    .quad Ld_thus, 0x10
    .quad Ld_every_fri, 0x20
    .quad Ld_on_fris, 0x20
    .quad Ld_fris, 0x20
    .quad Ld_every_sat, 0x40
    .quad Ld_on_sats, 0x40
    .quad Ld_sats, 0x40
    .quad Ld_tomorrow, DAY_TOMORROW
    .quad Ld_today, DAY_TODAY
    .quad Ld_tonight, DAY_TODAY
    .quad 0, 0

Ldaynames:
    .quad Ln_sun, Ln_mon, Ln_tue, Ln_wed, Ln_thu, Ln_fri, Ln_sat

Ltimewords:
    .quad Lt_noon, 720
    .quad Lt_midnight, 0
    .quad Lt_sunrise, T_SUNRISE
    .quad Lt_dawn, T_SUNRISE
    .quad Lt_sunset, T_SUNSET
    .quad Lt_dusk, T_SUNSET
    .quad 0, 0

Lunits:
    .quad Lu_minutes, 60
    .quad Lu_minute, 60
    .quad Lu_mins, 60
    .quad Lu_min, 60
    .quad Lu_hours, 3600
    .quad Lu_hour, 3600
    .quad Lu_hrs, 3600
    .quad Lu_hr, 3600
    .quad Lu_seconds, 1
    .quad Lu_second, 1
    .quad Lu_secs, 1
    .quad Lu_sec, 1
    .quad 0, 0

Larticles:
    .quad Lw_the, Lw_my, Lw_a, Lw_an, Lw_our, Lw_your, 0

// ===========================================================================
.text
.p2align 2

// long _norm(char *dst, const char *src, size_t max, long lower) -> length
//   trimmed, single spaces, curly quotes made plain, no trailing . ! ?
.globl _norm
_norm:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    sub  x21, x2, #1
    mov  x23, x3
    mov  x22, #0
Lno_lead:
    ldrb w9, [x20]
    cmp  w9, #' '
    b.ne Lno_loop
    add  x20, x20, #1
    b    Lno_lead
Lno_loop:
    cmp  x22, x21
    b.hs Lno_end
    ldrb w9, [x20], #1
    cbz  w9, Lno_end
    cmp  w9, #0xE2
    b.ne Lno_ascii
    ldrb w10, [x20]
    cmp  w10, #0x80
    b.ne Lno_store
    ldrb w10, [x20, #1]
    cmp  w10, #0x98
    b.eq Lno_apos
    cmp  w10, #0x99
    b.eq Lno_apos
    cmp  w10, #0x9C
    b.eq Lno_dquote
    cmp  w10, #0x9D
    b.eq Lno_dquote
    b    Lno_store
Lno_apos:
    add  x20, x20, #2
    mov  w9, #'\''
    b    Lno_store
Lno_dquote:
    add  x20, x20, #2
    b    Lno_loop
Lno_ascii:
    cmp  w9, #'\t'
    b.eq Lno_space
    cmp  w9, #'\n'
    b.eq Lno_space
    cmp  w9, #'"'
    b.eq Lno_loop
    cbz  x23, Lno_sp
    sub  w10, w9, #'A'
    cmp  w10, #25
    b.hi Lno_sp
    orr  w9, w9, #0x20
    b    Lno_store
Lno_space:
    mov  w9, #' '
Lno_sp:
    cmp  w9, #' '
    b.ne Lno_store
    cbz  x22, Lno_loop
    sub  x10, x22, #1
    ldrb w10, [x19, x10]
    cmp  w10, #' '
    b.eq Lno_loop
Lno_store:
    strb w9, [x19, x22]
    add  x22, x22, #1
    b    Lno_loop
Lno_end:
    cbz  x22, Lno_done
    sub  x10, x22, #1
    ldrb w9, [x19, x10]
    cmp  w9, #' '
    b.eq Lno_trim
    cmp  w9, #'.'
    b.eq Lno_trim
    cmp  w9, #'!'
    b.eq Lno_trim
    cmp  w9, #'?'
    b.eq Lno_trim
    b    Lno_done
Lno_trim:
    mov  x22, x10
    b    Lno_end
Lno_done:
    strb wzr, [x19, x22]
    mov  x0, x22
    LEAVE 0

// char *_after(const char *s, const char *prefix) -> just past the prefix (a whole
//   word or words) and any spaces or commas after it; 0 if s doesn't start with it
.globl _after
_after:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x20
    bl   _strlen
    mov  x21, x0
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _strncmp
    cbnz w0, Laf_no
    add  x19, x19, x21
    ldrb w9, [x19]
    cbz  w9, Laf_yes
    cmp  w9, #' '
    b.eq Laf_skip
    cmp  w9, #','
    b.ne Laf_no
Laf_skip:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.eq Laf_next
    cmp  w9, #','
    b.ne Laf_yes
Laf_next:
    add  x19, x19, #1
    b    Laf_skip
Laf_yes:
    mov  x0, x19
    LEAVE 0
Laf_no:
    mov  x0, #0
    LEAVE 0

// char *_skip_article(const char *s) — past "the", "my", "a", "our" …
.globl _skip_article
_skip_article:
    ENTER 0
    mov  x19, x0
Lsa_again:
    ADRL x20, Larticles
Lsa_loop:
    ldr  x1, [x20], #8
    cbz  x1, Lsa_done
    mov  x0, x19
    bl   _after
    cbz  x0, Lsa_loop
    ldrb w9, [x0]
    cbz  w9, Lsa_done                 // "the" and nothing else: keep it
    mov  x19, x0
    b    Lsa_again
Lsa_done:
    mov  x0, x19
    LEAVE 0

// ---------------------------------------------------------------------------
// The Home room's other words
// ---------------------------------------------------------------------------

// long _simple_cmd(const char *lc, const char *orig, long prefix_pass, long dry) -> 1 if it is one
_simple_cmd:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    str  x3, [sp, #96]
    ADRL x22, Lsimple
Lsm_loop:
    ldr  x1, [x22]
    cbz  x1, Lsm_no
    ldr  x9, [x22, #8]
    and  x9, x9, #1
    cmp  x9, x21
    b.ne Lsm_next
    cbnz x21, Lsm_prefix
    mov  x0, x19
    bl   _strcmp
    cbnz w0, Lsm_next
    mov  x0, x19
    bl   _strlen
    add  x23, x19, x0
    b    Lsm_hit
Lsm_prefix:
    mov  x0, x19
    bl   _after
    cbz  x0, Lsm_next
    mov  x23, x0
Lsm_hit:
    ldr  x9, [sp, #96]
    cbnz x9, Lsm_yes
    sub  x9, x23, x19
    add  x2, x20, x9
    mov  x1, x23
    ldr  x0, [x22, #24]
    ldr  x9, [x22, #16]
    blr  x9
Lsm_yes:
    mov  x0, #1
    LEAVE 16
Lsm_next:
    add  x22, x22, #32
    b    Lsm_loop
Lsm_no:
    mov  x0, #0
    LEAVE 16

// long _extra_command(const char *text) -> 1 if handled here (called before the
//   device parser by _home_command)
.globl _extra_command
_extra_command:
    ENTER 0
    mov  x19, x0
    ADRL x0, _g_x_lc
    mov  x1, x19
    mov  x2, #256
    mov  x3, #1
    bl   _norm
    cbz  x0, Lxc_no
    ADRL x0, _g_x_orig
    mov  x1, x19
    mov  x2, #256
    mov  x3, #0
    bl   _norm
    ADRL x0, _g_x_lc
    ADRL x1, _g_x_orig
    mov  x2, #0
    mov  x3, #0
    bl   _simple_cmd
    cbnz x0, Lxc_yes
    ADRL x0, _g_x_lc
    mov  x1, #0
    bl   _rule_try
    cbnz x0, Lxc_yes
    ADRL x0, _g_x_lc
    ADRL x1, _g_x_orig
    mov  x2, #1
    mov  x3, #0
    bl   _simple_cmd
    cbnz x0, Lxc_yes
Lxc_no:
    mov  x0, #0
    LEAVE 0
Lxc_yes:
    bl   _ui_lists_changed
    mov  x0, #1
    LEAVE 0

// long _extra_routable(const char *text) -> 1 for the few phrases that are plainly
//   for Home even when typed in a chat room ("weather", "sunset", "trackers")
.globl _extra_routable
_extra_routable:
    ENTER 0
    mov  x1, x0
    ADRL x0, _g_route
    mov  x2, #256
    mov  x3, #1
    bl   _norm
    ADRL x19, Lsimple
Ler_loop:
    ldr  x1, [x19]
    cbz  x1, Ler_no
    ldr  x9, [x19, #8]
    cmp  x9, #3
    b.eq Ler_prefix
    cmp  x9, #2
    b.ne Ler_next
    ADRL x0, _g_route
    bl   _strcmp
    cbz  w0, Ler_yes
    b    Ler_next
Ler_prefix:
    ADRL x0, _g_route                 // "spin color blue" typed in Main
    bl   _after
    cbnz x0, Ler_yes
Ler_next:
    add  x19, x19, #32
    b    Ler_loop
Ler_no:
    mov  x0, #0
    LEAVE 0
Ler_yes:
    mov  x0, #1
    LEAVE 0

// void _run_text(const char *cmd) — what a rule does when it fires
.globl _run_text
_run_text:
    ENTER 0
    mov  x1, x0
    ADRL x0, _g_run
    mov  x2, #256
    mov  x3, #1
    bl   _norm
    ADRL x20, Lrun_pats
Lrx2_loop:
    ldr  x1, [x20]
    cbz  x1, Lrx2_simple
    ADRL x0, _g_run
    bl   _after
    cbnz x0, Lrx2_hit
    add  x20, x20, #16
    b    Lrx2_loop
Lrx2_hit:
    ldr  x9, [x20, #8]
    blr  x9
    LEAVE 0
Lrx2_simple:
    ADRL x0, _g_run
    mov  x1, x0
    mov  x2, #0
    mov  x3, #0
    bl   _simple_cmd
    cbnz x0, Lrx2_done
    ADRL x0, _g_run
    mov  x1, x0
    mov  x2, #1
    mov  x3, #0
    bl   _simple_cmd
    cbnz x0, Lrx2_done
    ADRL x0, _g_run
    bl   _cmd_parse
    bl   _cmd_exec
Lrx2_done:
    bl   _ui_lists_changed
    LEAVE 0

// long _cmd_ok(const char *cmd) -> 1 something we can do, 0 not understood, 2 which one?
_cmd_ok:
    ENTER 0
    mov  x19, x0
    ADRL x20, Lrun_pats
Lok_pats:
    ldr  x1, [x20]
    cbz  x1, Lok_simple
    mov  x0, x19
    bl   _after
    cbnz x0, Lok_yes
    add  x20, x20, #16
    b    Lok_pats
Lok_simple:
    mov  x0, x19
    mov  x1, x19
    mov  x2, #0
    mov  x3, #1
    bl   _simple_cmd
    cbnz x0, Lok_yes
    mov  x0, x19
    mov  x1, x19
    mov  x2, #1
    mov  x3, #1
    bl   _simple_cmd
    cbnz x0, Lok_yes
    mov  x0, x19
    bl   _cmd_parse
    mov  x20, x0
    cmp  x20, #A_ON
    b.lo Lok_no
    cmp  x20, #A_LAST
    b.hi Lok_no
    cmp  x20, #A_LIST
    b.lo Lok_action
    cmp  x20, #A_REFRESH
    b.ls Lok_no
    cmp  x20, #A_CONNECT
    b.eq Lok_no
Lok_action:
    ADRL x8, _g_ambiguous
    ldr  x9, [x8]
    cbnz x9, Lok_which
    ADRL x8, _g_cmd_n
    ldr  x9, [x8]
    cbnz x9, Lok_yes
    cmp  x20, #A_STATUS
    b.eq Lok_yes
Lok_no:
    mov  x0, #0
    LEAVE 0
Lok_which:
    mov  x0, #2
    LEAVE 0
Lok_yes:
    mov  x0, #1
    LEAVE 0

// long _cmd_ok_say(const char *cmd) -> 1 fine; else says why not and returns 0
_cmd_ok_say:
    ENTER 0
    mov  x19, x0
    bl   _cmd_ok
    cmp  x0, #1
    b.eq Lcs2_yes
    cmp  x0, #2
    b.eq Lcs2_which
    ADRL x0, Lf_rule_unknown
    mov  x1, x19
    bl   _home_say
    mov  x0, #0
    LEAVE 0
Lcs2_which:
    ADRL x0, Ls_rule_which
    bl   _home_say0
    mov  x0, #0
    LEAVE 0
Lcs2_yes:
    mov  x0, #1
    LEAVE 0

// long _cmd_extract(const char *start, const char *end, long remind) -> length of
//   the command in _g_cmdtmp ("then" dropped; a reminder becomes "remind …")
_cmd_extract:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
Lce2_lead:
    cmp  x19, x20
    b.hs Lce2_trail
    ldrb w9, [x19]
    cmp  w9, #' '
    b.eq Lce2_lead_next
    cmp  w9, #','
    b.ne Lce2_trail
Lce2_lead_next:
    add  x19, x19, #1
    b    Lce2_lead
Lce2_trail:
    cmp  x20, x19
    b.ls Lce2_copy
    ldurb w9, [x20, #-1]
    cmp  w9, #' '
    b.eq Lce2_trail_next
    cmp  w9, #','
    b.ne Lce2_copy
Lce2_trail_next:
    sub  x20, x20, #1
    b    Lce2_trail
Lce2_copy:
    sub  x22, x20, x19
    cmp  x22, #150
    mov  x9, #150
    csel x22, x9, x22, hi
    ADRL x0, _g_cmdtmp2
    mov  x1, x19
    mov  x2, x22
    bl   _memcpy
    ADRL x8, _g_cmdtmp2
    strb wzr, [x8, x22]
    ADRL x19, _g_cmdtmp2
    mov  x0, x19
    ADRL x1, Lw_then
    bl   _after
    cbz  x0, Lce2_remind
    mov  x19, x0
Lce2_remind:
    cbz  x21, Lce2_plain
    mov  x0, x19
    ADRL x1, Lw_to
    bl   _after
    cbz  x0, Lce2_rtext
    mov  x19, x0
Lce2_rtext:
    ldrb w9, [x19]
    cbz  w9, Lce2_empty
    ADRL x0, _g_cmdtmp
    mov  x1, #RU_CMD_MAX
    ADRL x2, Lf_remind
    mov  x3, x19
    bl   _sfmt
    b    Lce2_len
Lce2_plain:
    ADRL x0, _g_cmdtmp
    mov  x1, x19
    mov  x2, #RU_CMD_MAX
    bl   _strlcpy
Lce2_len:
    ADRL x0, _g_cmdtmp
    bl   _strlen
    LEAVE 0
Lce2_empty:
    ADRL x8, _g_cmdtmp
    strb wzr, [x8]
    mov  x0, #0
    LEAVE 0

// long _is_notify_me(const char *s) -> 1 for "notify me", "tell me", "let me know" …
_is_notify_me:
    ENTER 0
    mov  x19, x0
    ADRL x20, Lnotify_me
Lnm_loop:
    ldr  x1, [x20], #8
    cbz  x1, Lnm_no
    mov  x0, x19
    bl   _strcmp
    cbnz w0, Lnm_loop
    mov  x0, #1
    LEAVE 0
Lnm_no:
    mov  x0, #0
    LEAVE 0

// ---------------------------------------------------------------------------
// Time words
// ---------------------------------------------------------------------------

// long _parse_time(const char *p, long strict) -> minutes after midnight, T_SUNRISE,
//   T_SUNSET, or -1. strict: a bare "7" doesn't count (needs am/pm or 7:00).
//   _g_tp_end: just after it (and any spaces or commas)
.globl _parse_time
_parse_time:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x21, Ltimewords
Lpt_w:
    ldr  x1, [x21]
    cbz  x1, Lpt_digits
    mov  x0, x19
    bl   _after
    cbnz x0, Lpt_word
    add  x21, x21, #16
    b    Lpt_w
Lpt_word:
    ADRL x8, _g_tp_end
    str  x0, [x8]
    ldr  x0, [x21, #8]
    LEAVE 0
Lpt_digits:
    mov  x21, #0
    mov  x22, #0
Lpt_h:
    ldrb w9, [x19]
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi Lpt_h_end
    cmp  x22, #2
    b.hs Lpt_bad
    mov  x10, #10
    madd x21, x21, x10, x9
    add  x19, x19, #1
    add  x22, x22, #1
    b    Lpt_h
Lpt_h_end:
    cbz  x22, Lpt_bad
    mov  x23, #0
    mov  x24, #0
    ldrb w9, [x19]
    cmp  w9, #':'
    b.ne Lpt_ampm
    ldrb w9, [x19, #1]
    sub  w9, w9, #'0'
    cmp  w9, #5
    b.hi Lpt_bad
    ldrb w10, [x19, #2]
    sub  w10, w10, #'0'
    cmp  w10, #9
    b.hi Lpt_bad
    mov  w11, #10
    madd w23, w9, w11, w10
    add  x19, x19, #3
    mov  x24, #1
Lpt_ampm:
    mov  x10, x19
    ldrb w9, [x10]
    cmp  w9, #' '
    b.ne Lpt_ap_letter
    add  x10, x10, #1
Lpt_ap_letter:
    ldrb w9, [x10]
    cmp  w9, #'a'
    b.eq Lpt_ap
    cmp  w9, #'p'
    b.ne Lpt_24
Lpt_ap:
    add  x11, x10, #1
    ldrb w12, [x11]
    cmp  w12, #'.'
    b.ne Lpt_ap_m
    add  x11, x11, #1
Lpt_ap_m:
    ldrb w12, [x11]
    cmp  w12, #'m'
    b.ne Lpt_24
    add  x11, x11, #1
    ldrb w12, [x11]
    cmp  w12, #'.'
    b.ne Lpt_ap_end
    add  x11, x11, #1
Lpt_ap_end:
    ldrb w12, [x11]
    cbz  w12, Lpt_ap_ok
    cmp  w12, #' '
    b.eq Lpt_ap_ok
    cmp  w12, #','
    b.ne Lpt_24                       // "7 apples": not a time of day
Lpt_ap_ok:
    mov  x19, x11
    cmp  x21, #1
    b.lo Lpt_bad
    cmp  x21, #12
    b.hi Lpt_bad
    b.ne Lpt_ap_pm
    mov  x21, #0                      // 12 am is midnight, 12 pm noon
Lpt_ap_pm:
    cmp  w9, #'p'
    b.ne Lpt_ap_set
    add  x21, x21, #12
Lpt_ap_set:
    mov  x24, #1
    b    Lpt_check
Lpt_24:
    cmp  x21, #23
    b.hi Lpt_bad
    cbz  x20, Lpt_check
    cbz  x24, Lpt_bad
Lpt_check:
    ldrb w9, [x19]
    cbz  w9, Lpt_ok
    cmp  w9, #' '
    b.eq Lpt_ok
    cmp  w9, #','
    b.ne Lpt_bad
Lpt_ok:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.eq Lpt_ok_next
    cmp  w9, #','
    b.ne Lpt_ok_done
Lpt_ok_next:
    add  x19, x19, #1
    b    Lpt_ok
Lpt_ok_done:
    ADRL x8, _g_tp_end
    str  x19, [x8]
    mov  x9, #60
    madd x0, x21, x9, x23
    LEAVE 0
Lpt_bad:
    mov  x0, #-1
    LEAVE 0

// long _in_amount(const char *p) -> seconds in "10 minutes", "2 hours", "an hour", or 0
.globl _in_amount
_in_amount:
    ENTER 0
    mov  x19, x0
    ADRL x1, Lw_half_hour
    bl   _after
    mov  x20, #1800
    cbnz x0, Lia_word
    mov  x0, x19
    ADRL x1, Lw_an_hour
    bl   _after
    mov  x20, #3600
    cbnz x0, Lia_word
    mov  x0, x19
    ADRL x1, Lw_a_minute
    bl   _after
    mov  x20, #60
    cbnz x0, Lia_word
    mov  x20, #0
    mov  x21, #0
Lia_d:
    ldrb w9, [x19]
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi Lia_de
    mov  x10, #10
    madd x20, x20, x10, x9
    add  x19, x19, #1
    add  x21, x21, #1
    cmp  x21, #5
    b.hi Lia_bad
    b    Lia_d
Lia_de:
    cbz  x21, Lia_bad
    cbz  x20, Lia_bad
    ldrb w9, [x19]
    cmp  w9, #' '
    b.ne Lia_units
    add  x19, x19, #1
Lia_units:
    ADRL x22, Lunits
Lia_u:
    ldr  x1, [x22]
    cbz  x1, Lia_bad
    mov  x0, x19
    bl   _after
    cbnz x0, Lia_uhit
    add  x22, x22, #16
    b    Lia_u
Lia_uhit:
    ldr  x9, [x22, #8]
    mul  x20, x20, x9
    MOVI x9, 604800                   // a week at most
    cmp  x20, x9
    b.hi Lia_bad
Lia_word:
    ADRL x8, _g_tp_end
    str  x0, [x8]
    mov  x0, x20
    LEAVE 0
Lia_bad:
    mov  x0, #0
    LEAVE 0

// char *_last_of(const char *s, const char *pat) -> the last place pat occurs, or 0
_last_of:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
Llo_loop:
    mov  x0, x19
    mov  x1, x20
    bl   _strstr
    cbz  x0, Llo_done
    mov  x21, x0
    add  x19, x0, #1
    b    Llo_loop
Llo_done:
    mov  x0, x21
    LEAVE 0

// void _now_tm(void) — _g_now, _g_cur_min, _g_today, _g_wday
_now_tm:
    ENTER 64
    add  x0, sp, #96
    bl   _time
    ADRL x8, _g_now
    str  x0, [x8]
    add  x0, sp, #96
    add  x1, sp, #104
    bl   _localtime_r
    ldr  w9, [sp, #(104 + TM_HOUR)]
    ldr  w10, [sp, #(104 + TM_MIN)]
    mov  w11, #60
    madd w9, w9, w11, w10
    ADRL x8, _g_cur_min
    str  x9, [x8]
    ldr  w9, [sp, #(104 + TM_YEAR)]
    ldr  w10, [sp, #(104 + TM_YDAY)]
    mov  w11, #1000
    madd w9, w9, w11, w10
    ADRL x8, _g_today
    str  x9, [x8]
    ldr  w9, [sp, #(104 + TM_WDAY)]
    ADRL x8, _g_wday
    str  x9, [x8]
    LEAVE 64

// long _min_of(time_t t) -> minutes after midnight, local time
_min_of:
    ENTER 64
    str  x0, [sp, #96]
    add  x0, sp, #96
    add  x1, sp, #104
    bl   _localtime_r
    ldr  w9, [sp, #(104 + TM_HOUR)]
    ldr  w10, [sp, #(104 + TM_MIN)]
    mov  w11, #60
    madd w0, w9, w11, w10
    LEAVE 64

// long _resolve_min(long m) -> m, or today's sunrise/sunset (-1 not known yet)
_resolve_min:
    cmp  x0, #T_SUNRISE
    b.eq Lrm_rise
    cmp  x0, #T_SUNSET
    b.eq Lrm_set
    ret
Lrm_rise:
    ADRL x8, _g_sunrise_min
    ldr  x0, [x8]
    ret
Lrm_set:
    ADRL x8, _g_sunset_min
    ldr  x0, [x8]
    ret

// char *_when_text(long i) — "every day at 7:00 am", "today at sunset (6:52 pm)" -> _g_wtxt
_when_text:
    ENTER 0
    RULEA x19, x0
    bl   _now_tm
    ldr  x20, [x19, #RU_DAYS]
    ldr  x9, [x19, #RU_ONCE]
    cbz  x9, Lwt_days
    ADRL x21, Ls_today
    ADRL x8, _g_today
    ldr  x10, [x8]
    ldr  x11, [x19, #RU_LAST]
    cmp  x10, x11
    b.eq Lwt_tom
    ADRL x8, _g_wday
    ldr  x10, [x8]
    lsr  x11, x20, x10
    tbnz x11, #0, Lwt_time
Lwt_tom:
    ADRL x21, Ls_tomorrow
    b    Lwt_time
Lwt_days:
    ADRL x21, Ls_every_day
    cmp  x20, #0x7f
    b.eq Lwt_time
    ADRL x21, Ls_on_weekdays
    cmp  x20, #0x3e
    b.eq Lwt_time
    ADRL x21, Ls_on_weekends
    cmp  x20, #0x41
    b.eq Lwt_time
    ADRL x21, Ls_some_days
    sub  x9, x20, #1
    tst  x9, x20
    b.ne Lwt_time
    rbit x9, x20
    clz  x9, x9
    cmp  x9, #6
    b.hi Lwt_time
    ADRL x8, Ldaynames
    ldr  x21, [x8, x9, lsl #3]
Lwt_time:
    ldr  x0, [x19, #RU_MIN]
    cmp  x0, #T_SUNRISE
    b.eq Lwt_sun
    cmp  x0, #T_SUNSET
    b.eq Lwt_sun
    ADRL x1, _g_clk
    bl   _clock12
    ADRL x4, _g_clk
    b    Lwt_fmt
Lwt_sun:
    mov  x22, x0
    bl   _resolve_min
    ADRL x23, Lt_sunrise
    ADRL x9, Lt_sunset
    cmp  x22, #T_SUNSET
    csel x23, x9, x23, eq
    tbnz x0, #63, Lwt_sun_plain
    ADRL x1, _g_clk2
    bl   _clock12
    ADRL x0, _g_clk
    mov  x1, #48
    ADRL x2, Lf_sun_at
    mov  x3, x23
    ADRL x4, _g_clk2
    bl   _sfmt
    ADRL x4, _g_clk
    b    Lwt_fmt
Lwt_sun_plain:
    mov  x4, x23
Lwt_fmt:
    mov  x3, x21
    ADRL x0, _g_wtxt
    mov  x1, #96
    ADRL x2, Lf_when
    bl   _sfmt
    ADRL x0, _g_wtxt
    LEAVE 0

// ---------------------------------------------------------------------------
// The rule table
// ---------------------------------------------------------------------------

// long _rule_new(void) -> index of a cleared rule, or -1 when full
_rule_new:
    ENTER 0
    ADRL x8, _g_rule_count
    ldr  x19, [x8]
    cmp  x19, #RULE_MAX
    b.hs Lrn_full
    add  x9, x19, #1
    str  x9, [x8]
    RULEA x0, x19
    mov  x1, #(1 << RULE_SHIFT)
    bl   _bzero
    mov  x0, x19
    LEAVE 0
Lrn_full:
    mov  x0, #-1
    LEAVE 0

// void _rule_del(long i)
_rule_del:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_rule_count
    ldr  x20, [x8]
    cmp  x19, x20
    b.hs Lrd_done
    sub  x21, x20, #1
    str  x21, [x8]
    sub  x2, x21, x19
    lsl  x2, x2, #RULE_SHIFT
    cbz  x2, Lrd_done
    RULEA x0, x19
    add  x1, x0, #(1 << RULE_SHIFT)
    bl   _memmove
Lrd_done:
    LEAVE 0

// void _rules_save(void) — the repeating rules, one sentence per line
_rules_save:
    ENTER 0
    ADRL x8, _g_rsave
    strb wzr, [x8]
    mov  x19, #0
Lsv_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lsv_done
    RULEA x20, x19
    ldr  x9, [x20, #RU_ONCE]
    cbnz x9, Lsv_next
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_AT
    b.eq Lsv_next
    ADRL x0, _g_rsave
    add  x1, x20, #RU_SENT
    mov  x2, #6400
    bl   _strlcat
    ADRL x0, _g_rsave
    ADRL x1, Ls_nl
    mov  x2, #6400
    bl   _strlcat
Lsv_next:
    add  x19, x19, #1
    b    Lsv_loop
Lsv_done:
    ADRL x0, Ls_pref_rules
    ADRL x1, _g_rsave
    bl   _pref_set
    LEAVE 0

// void _rules_init(void) — saved rules, this Mac's room, notification settings
.globl _rules_init
_rules_init:
    ENTER 0
    bl   _find_init
    bl   _extras_init
    ADRL x0, Ls_pref_rules
    ADRL x1, _g_rsave
    mov  x2, #6400
    bl   _pref_get
    ADRL x19, _g_rsave
Lri_loop:
    ldrb w9, [x19]
    cbz  w9, Lri_done
    mov  x0, x19
    mov  w1, #'\n'
    bl   _strchr
    mov  x20, x0
    cbz  x20, Lri_one
    strb wzr, [x20]
Lri_one:
    ldrb w9, [x19]
    cbz  w9, Lri_next
    mov  x0, x19
    mov  x1, #1
    bl   _rule_try
Lri_next:
    cbz  x20, Lri_done
    add  x19, x20, #1
    b    Lri_loop
Lri_done:
    LEAVE 0

// long _rule_try(const char *lc, long quiet) -> 1 if it was a rule (made, or explained)
.globl _rule_try
_rule_try:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x21, Lwhen_pats
Lrt2_loop:
    ldr  x1, [x21]
    cbz  x1, Lrt2_sched
    mov  x0, x19
    bl   _after
    cbnz x0, Lrt2_when
    add  x21, x21, #16
    b    Lrt2_loop
Lrt2_when:
    ldr  x1, [x21, #8]
    mov  x2, x19
    mov  x3, x20
    bl   _rule_when
    mov  x0, #1
    LEAVE 0
Lrt2_sched:
    mov  x0, x19
    mov  x1, x20
    bl   _rule_sched
    LEAVE 0

// long _rule_when(const char *p, long notify, const char *sentence, long quiet) -> 1
_rule_when:
    ENTER 48                          // [96] event at  [104] its entry  [112] its length
    mov  x19, x0                      // [120] custom command  [136] scratch
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    str  xzr, [sp, #96]
    str  xzr, [sp, #112]
    ADRL x23, Levents
Lrw_ev:
    ldr  x1, [x23]
    cbz  x1, Lrw_ev_done
    mov  x0, x19
    bl   _strstr
    cbz  x0, Lrw_ev_next
    mov  x24, x0
    ldr  x0, [x23]
    bl   _strlen
    ldrb w9, [x24, x0]
    cbz  w9, Lrw_ev_ok
    cmp  w9, #' '
    b.eq Lrw_ev_ok
    cmp  w9, #','
    b.ne Lrw_ev_next
Lrw_ev_ok:
    ldr  x9, [sp, #96]
    cbz  x9, Lrw_ev_take
    cmp  x24, x9
    b.lo Lrw_ev_take
    b.hi Lrw_ev_next
    ldr  x10, [sp, #112]
    cmp  x0, x10
    b.ls Lrw_ev_next
Lrw_ev_take:
    str  x24, [sp, #96]
    str  x23, [sp, #104]
    str  x0, [sp, #112]
Lrw_ev_next:
    add  x23, x23, #EV_SIZE
    b    Lrw_ev
Lrw_ev_done:
    ldr  x23, [sp, #96]
    cbz  x23, Lrw_help
    mov  x0, x19
    bl   _skip_article
    mov  x24, x0
    cmp  x24, x23
    b.hs Lrw_help
    sub  x2, x23, x24
    mov  x9, #(RU_SUBJ_MAX - 1)
    cmp  x2, x9
    csel x2, x9, x2, hi
    str  x2, [sp, #136]
    ADRL x0, _g_subj
    mov  x1, x24
    bl   _memcpy
    ADRL x8, _g_subj
    ldr  x9, [sp, #136]
Lrw_trim:
    strb wzr, [x8, x9]
    cbz  x9, Lrw_help
    sub  x10, x9, #1
    ldrb w11, [x8, x10]
    cmp  w11, #' '
    b.ne Lrw_rest
    mov  x9, x10
    b    Lrw_trim
Lrw_rest:
    ldr  x9, [sp, #112]
    add  x19, x23, x9                 // after the event words
    str  xzr, [sp, #128]
    ldr  x10, [sp, #104]
    ldr  x10, [x10, #8]
    cmp  x10, #R_BTN
    b.eq Lrw_btn
    cmp  x10, #R_THR
    b.ne Lrw_rest2
    ADRL x0, _g_subj                  // "the bedroom humidity" -> bedroom, humidity
    bl   _sens_subj_q
    str  x0, [sp, #128]
    mov  x1, x0
    mov  x0, x19
    bl   _sens_parse_thr              // "78 turn on the fan" -> 78 (as degrees C)
    cbz  x0, Lrw_thr_help
    mov  x19, x0
    str  x1, [sp, #136]
    b    Lrw_rest2
Lrw_btn:
    ADRL x0, _g_subj                  // "button 2 on the remote" -> remote, 2
    bl   _sens_subj_btn
    str  x0, [sp, #128]
Lrw_rest2:
    mov  x0, x19
    bl   _strlen
    add  x1, x19, x0
    mov  x0, x19
    mov  x2, #0
    bl   _cmd_extract
    str  xzr, [sp, #120]
    cbnz x20, Lrw_type                // "notify me when …": always a notification
    cbz  x0, Lrw_type                 // nothing said: a notification too
    ADRL x0, _g_cmdtmp
    bl   _is_notify_me
    cbnz x0, Lrw_type
    mov  x9, #1
    str  x9, [sp, #120]
Lrw_type:
    ldr  x23, [sp, #104]
    ldr  x9, [x23, #8]
    cmp  x9, #R_THR
    b.eq Lrw_sens
    cmp  x9, #R_BTN
    b.eq Lrw_sens
    cmp  x9, #R_DEV
    b.ne Lrw_valid
    cbnz x22, Lrw_valid
    ADRL x0, _g_subj
    bl   _sens_dev_by_name
    tbnz x0, #63, Lrw_nodev
    ADRL x8, _g_devs
    add  x24, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x23, #16]
    cmp  x9, #D_ON
    b.eq Lrw_devname
    ldr  x10, [x24, #D_KIND]
    cmp  x10, #K_BLES
    b.eq Lrw_devname
    cmp  x9, #D_MOTION                // motion and water: Bluetooth sensors only
    b.eq Lrw_nostate
    cmp  x9, #D_WET
    b.eq Lrw_nostate
    cmp  x10, #K_ST
    b.eq Lrw_devname
    cmp  x10, #K_HA
    b.eq Lrw_devname
Lrw_nostate:
    ADRL x0, Lf_rule_nostate
    add  x1, x24, #D_NAME
    bl   _home_say
    b    Lrw_handled
Lrw_devname:
    ADRL x0, _g_subj
    add  x1, x24, #D_NAME
    mov  x2, #RU_SUBJ_MAX
    bl   _strlcpy
    b    Lrw_valid
Lrw_sens:                             // a reading or a button: a named Bluetooth sensor
    cbnz x22, Lrw_valid
    ADRL x0, _g_subj
    bl   _sens_dev_by_name
    tbnz x0, #63, Lrw_nosens
    ADRL x8, _g_devs
    add  x24, x8, x0, lsl #DEV_SHIFT
    ldr  x10, [x24, #D_KIND]
    cmp  x10, #K_BLES
    b.ne Lrw_nosens
    b    Lrw_devname
Lrw_nosens:
    ADRL x0, Lf_rule_nosens
    ADRL x1, _g_subj
    bl   _home_say
    b    Lrw_handled
Lrw_thr_help:
    cbnz x22, Lrw_handled
    ADRL x0, Ls_rule_thr_help
    bl   _home_say0
    b    Lrw_handled
Lrw_valid:
    ldr  x9, [sp, #120]
    cbz  x9, Lrw_notify_cmd
    cbnz x22, Lrw_make
    ADRL x0, _g_cmdtmp
    bl   _cmd_ok_say
    cbz  x0, Lrw_handled
    b    Lrw_make
Lrw_notify_cmd:
    ldr  x9, [x23, #8]
    cmp  x9, #R_THR
    b.ne Lrw_notify_ev
    ldr  x0, [sp, #128]               // "notify Bedroom is above 78.0°F"
    ldr  x1, [x23, #16]
    ldr  x2, [sp, #136]
    ADRL x3, _g_wtxt
    bl   _sens_thr_text
    ADRL x0, _g_cmdtmp
    mov  x1, #RU_CMD_MAX
    ADRL x2, Lf_notify_thr
    ADRL x3, _g_subj
    ADRL x4, _g_wtxt
    bl   _sfmt
    b    Lrw_notify_cap
Lrw_notify_ev:
    ADRL x0, _g_cmdtmp
    mov  x1, #RU_CMD_MAX
    ADRL x2, Lf_notify_ev
    ADRL x3, _g_subj
    ldr  x4, [x23, #32]
    bl   _sfmt
Lrw_notify_cap:
    ADRL x8, _g_cmdtmp                // "notify Anna arrived"
    ldrb w9, [x8, #7]
    sub  w10, w9, #'a'
    cmp  w10, #25
    b.hi Lrw_make
    sub  w9, w9, #32
    strb w9, [x8, #7]
Lrw_make:
    bl   _rule_new
    tbnz x0, #63, Lrw_full
    mov  x24, x0
    RULEA x19, x24
    ldr  x9, [x23, #8]
    str  x9, [x19, #RU_TYPE]
    ldr  x9, [x23, #16]
    str  x9, [x19, #RU_FIELD]
    ldr  x9, [x23, #24]
    str  x9, [x19, #RU_WANT]
    str  x23, [x19, #RU_WHEN]
    mov  x9, #-1
    str  x9, [x19, #RU_PREV]
    ldr  x9, [x23, #8]
    cmp  x9, #R_BTN
    b.eq Lrw_make_btn
    cmp  x9, #R_THR
    b.ne Lrw_make_subj
    ldr  x9, [x23, #16]               // above / below
    str  x9, [x19, #RU_DAYS]
    ldr  x9, [sp, #128]               // temperature / humidity / ...
    str  x9, [x19, #RU_FIELD]
    ldr  x9, [sp, #136]
    str  x9, [x19, #RU_MIN]
    b    Lrw_make_subj
Lrw_make_btn:
    ldr  x9, [sp, #128]               // which button (0 any)
    str  x9, [x19, #RU_DAYS]
Lrw_make_subj:
    add  x0, x19, #RU_SUBJ
    ADRL x1, _g_subj
    mov  x2, #RU_SUBJ_MAX
    bl   _strlcpy
    add  x0, x19, #RU_CMD
    ADRL x1, _g_cmdtmp
    mov  x2, #RU_CMD_MAX
    bl   _strlcpy
    add  x0, x19, #RU_SENT
    mov  x1, x21
    mov  x2, #RU_SENT_MAX
    bl   _strlcpy
    cbnz x22, Lrw_handled
    bl   _rules_save
    mov  x0, x24
    bl   _rule_announce
Lrw_handled:
    mov  x0, #1
    LEAVE 48
Lrw_help:
    cbnz x22, Lrw_handled
    ADRL x0, Ls_when_help
    bl   _home_say0
    b    Lrw_handled
Lrw_nodev:
    ADRL x0, Lf_rule_nodev
    ADRL x1, _g_subj
    bl   _home_say
    b    Lrw_handled
Lrw_full:
    cbnz x22, Lrw_handled
    ADRL x0, Ls_rules_full
    bl   _home_say0
    b    Lrw_handled

// long _rule_sched(const char *lc, long quiet) -> 1 if it was a schedule (made, or explained)
_rule_sched:
    ENTER 80      // [96] days  [104] minute  [112] once  [120] command start  [128] its end
    mov  x19, x0  // [136] absolute time (R_AT)  [144] reminder  [152] the whole sentence
    mov  x20, x1
    str  x19, [sp, #152]
    str  xzr, [sp, #144]
    str  xzr, [sp, #128]
    str  xzr, [sp, #136]
    str  xzr, [sp, #112]
    mov  x0, x19
    ADRL x1, Lw_remind_me
    bl   _after
    cbz  x0, Lrs_in
    mov  x19, x0
    mov  x9, #1
    str  x9, [sp, #144]
Lrs_in:                               // "in 10 minutes …"
    mov  x0, x19
    ADRL x1, Lw_in
    bl   _after
    cbz  x0, Lrs_days
    bl   _in_amount
    cbz  x0, Lrs_days
    mov  x21, x0
    mov  x0, #0
    bl   _time
    add  x0, x0, x21
    str  x0, [sp, #136]
    ADRL x8, _g_tp_end
    ldr  x9, [x8]
    str  x9, [sp, #120]
    b    Lrs_have
Lrs_days:                             // "every weekday at 7 …", "tomorrow at 9 …"
    ADRL x21, Ldays
Lrs_days_loop:
    ldr  x1, [x21]
    cbz  x1, Lrs_at
    mov  x0, x19
    bl   _after
    cbz  x0, Lrs_days_next
    ADRL x1, Lw_at
    bl   _after
    cbz  x0, Lrs_days_next
    str  x0, [sp, #160]
    mov  x1, #0
    bl   _parse_time
    tbnz x0, #63, Lrs_days_next
    str  x0, [sp, #104]
    ldr  x9, [x21, #8]
    str  x9, [sp, #96]
    ADRL x8, _g_tp_end
    ldr  x9, [x8]
    str  x9, [sp, #120]
    b    Lrs_clock
Lrs_days_next:
    add  x21, x21, #16
    b    Lrs_days_loop
Lrs_at:                               // "at 7 pm …"
    mov  x0, x19
    ADRL x1, Lw_at
    bl   _after
    cbz  x0, Lrs_suffix_in
    str  x0, [sp, #160]
    mov  x1, #0
    bl   _parse_time
    tbnz x0, #63, Lrs_suffix_in
    str  x0, [sp, #104]
    mov  x9, #DAY_TODAY
    str  x9, [sp, #96]
    ADRL x8, _g_tp_end
    ldr  x9, [x8]
    str  x9, [sp, #120]
    b    Lrs_clock
Lrs_suffix_in:                        // "… in 10 minutes"
    mov  x0, x19
    ADRL x1, Ls_sp_in_sp
    bl   _last_of
    cbz  x0, Lrs_suffix_at
    mov  x21, x0
    add  x0, x21, #4
    bl   _in_amount
    cbz  x0, Lrs_suffix_at
    mov  x22, x0
    ADRL x8, _g_tp_end
    ldr  x9, [x8]
    ldrb w9, [x9]
    cbnz w9, Lrs_suffix_at
    mov  x0, #0
    bl   _time
    add  x0, x0, x22
    str  x0, [sp, #136]
    str  x19, [sp, #120]
    str  x21, [sp, #128]
    b    Lrs_have
Lrs_suffix_at:                        // "… at 11 pm", "… every day at 7"
    mov  x0, x19
    ADRL x1, Ls_sp_at_sp
    bl   _last_of
    cbz  x0, Lrs_none
    mov  x21, x0
    add  x0, x21, #4
    str  x0, [sp, #160]
    mov  x1, #0
    bl   _parse_time
    tbnz x0, #63, Lrs_none
    str  x0, [sp, #104]
    ADRL x8, _g_tp_end
    ldr  x9, [x8]
    ldrb w9, [x9]
    cbnz w9, Lrs_none
    str  x19, [sp, #120]
    str  x21, [sp, #128]
    ADRL x22, Ldays
Lrs_sd_loop:
    ldr  x23, [x22]
    cbz  x23, Lrs_sd_none
    mov  x0, x23
    bl   _strlen
    mov  x24, x0
    sub  x9, x21, x19                 // length before " at "
    cmp  x9, x24
    b.lo Lrs_sd_next
    sub  x0, x21, x24                 // where the day phrase would start
    b.eq Lrs_sd_cmp                   // right at the start
    ldurb w10, [x0, #-1]
    cmp  w10, #' '
    b.ne Lrs_sd_next
Lrs_sd_cmp:
    mov  x1, x23
    mov  x2, x24
    bl   _strncmp
    cbnz w0, Lrs_sd_next
    ldr  x9, [x22, #8]
    str  x9, [sp, #96]
    sub  x9, x21, x24
    cmp  x9, x19
    b.eq Lrs_sd_end
    sub  x9, x9, #1
Lrs_sd_end:
    str  x9, [sp, #128]
    b    Lrs_clock
Lrs_sd_next:
    add  x22, x22, #16
    b    Lrs_sd_loop
Lrs_sd_none:
    add  x0, x21, #4
    mov  x1, #1
    bl   _parse_time
    tbz  x0, #63, Lrs_sd_once
    ldr  x9, [sp, #104]               // a bare "at 7": morning or evening?
    cmp  x9, #720
    b.hi Lrs_none
    mov  x10, #60
    udiv x1, x9, x10
    cbz  x1, Lrs_none
    cbnz x20, Lrs_handled
    mov  x2, x1
    mov  x3, x1
    ADRL x0, Lf_ampm
    bl   _home_say
    b    Lrs_handled
Lrs_sd_once:
    mov  x9, #DAY_TODAY
    str  x9, [sp, #96]
    b    Lrs_clock
Lrs_none:
    ldr  x9, [sp, #144]
    cbz  x9, Lrs_no
    cbnz x20, Lrs_handled
    ADRL x0, Ls_remind_help
    bl   _home_say0
    b    Lrs_handled
Lrs_no:
    mov  x0, #0
    LEAVE 80

Lrs_clock:
    ldr  x0, [sp, #160]               // "at 7" with no am/pm: ask
    mov  x1, #1
    bl   _parse_time
    tbz  x0, #63, Lrs_clock_ok
    ldr  x9, [sp, #104]
    cmp  x9, #720
    b.hi Lrs_clock_ok
    mov  x10, #60
    udiv x1, x9, x10
    cbz  x1, Lrs_clock_ok
    cbnz x20, Lrs_handled
    mov  x2, x1
    mov  x3, x1
    ADRL x0, Lf_ampm
    bl   _home_say
    b    Lrs_handled
Lrs_clock_ok:
    bl   _now_tm
    ldr  x9, [sp, #96]
    mov  x10, #0
    cmp  x9, #DAY_TOMORROW
    b.ne Lrs_ck_today
    ADRL x8, _g_wday
    ldr  x11, [x8]
    add  x11, x11, #1
    cmp  x11, #7
    csel x11, xzr, x11, eq
    mov  x9, #1
    lsl  x9, x9, x11
    mov  x10, #1
    b    Lrs_ck_set
Lrs_ck_today:
    cmp  x9, #DAY_TODAY
    b.ne Lrs_ck_set
    mov  x9, #0x7f
    mov  x10, #1
Lrs_ck_set:
    str  x9, [sp, #96]
    str  x10, [sp, #112]
    str  xzr, [sp, #136]

Lrs_have:
    ldr  x21, [sp, #120]
    ldr  x22, [sp, #128]
    cbnz x22, Lrs_have_end
    mov  x0, x21
    bl   _strlen
    add  x22, x21, x0
Lrs_have_end:
    mov  x0, x21
    mov  x1, x22
    ldr  x2, [sp, #144]
    bl   _cmd_extract
    cbnz x0, Lrs_check
    cbnz x20, Lrs_handled
    ADRL x0, Ls_what_then
    bl   _home_say0
    b    Lrs_handled
Lrs_check:
    cbnz x20, Lrs_make
    ADRL x0, _g_cmdtmp
    bl   _cmd_ok_say
    cbz  x0, Lrs_handled
Lrs_make:
    bl   _rule_new
    tbnz x0, #63, Lrs_full
    mov  x23, x0
    RULEA x24, x23
    ldr  x9, [sp, #136]
    cbz  x9, Lrs_mk_clock
    mov  x10, #R_AT
    str  x10, [x24, #RU_TYPE]
    str  x9, [x24, #RU_WHEN]
    mov  x10, #1
    str  x10, [x24, #RU_ONCE]
    b    Lrs_mk_common
Lrs_mk_clock:
    mov  x10, #R_CLOCK
    str  x10, [x24, #RU_TYPE]
    ldr  x9, [sp, #96]
    str  x9, [x24, #RU_DAYS]
    ldr  x9, [sp, #104]
    str  x9, [x24, #RU_MIN]
    ldr  x9, [sp, #112]
    str  x9, [x24, #RU_ONCE]
    bl   _now_tm
    ldr  x0, [x24, #RU_MIN]
    bl   _resolve_min
    tbnz x0, #63, Lrs_mk_common
    ADRL x8, _g_cur_min
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs Lrs_mk_common                // later today (or right now)
    ADRL x8, _g_today                 // already past: from tomorrow on
    ldr  x9, [x8]
    str  x9, [x24, #RU_LAST]
Lrs_mk_common:
    mov  x9, #-1
    str  x9, [x24, #RU_PREV]
    add  x0, x24, #RU_CMD
    ADRL x1, _g_cmdtmp
    mov  x2, #RU_CMD_MAX
    bl   _strlcpy
    add  x0, x24, #RU_SENT
    ldr  x1, [sp, #152]
    mov  x2, #RU_SENT_MAX
    bl   _strlcpy
    cbnz x20, Lrs_handled
    bl   _rules_save
    mov  x0, x23
    bl   _rule_announce
Lrs_handled:
    mov  x0, #1
    LEAVE 80
Lrs_full:
    cbnz x20, Lrs_handled
    ADRL x0, Ls_rules_full
    bl   _home_say0
    b    Lrs_handled

// void _rule_announce(long i) — "Rule 3: every weekday at 7:00 am → kitchen on."
_rule_announce:
    ENTER 0
    mov  x19, x0
    RULEA x20, x19
    add  x21, x19, #1
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_AT
    b.eq Lra_at
    cmp  x9, #R_CLOCK
    b.eq Lra_clock
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_THR
    b.eq Lra_thr
    cmp  x9, #R_BTN
    b.eq Lra_btn
    ldr  x9, [x20, #RU_WHEN]
    ldr  x3, [x9, #40]
    ADRL x0, Lf_ann_when
    mov  x1, x21
    add  x2, x20, #RU_SUBJ
    add  x4, x20, #RU_CMD
    bl   _home_say4
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_PRES
    b.eq Lra_pres
    add  x0, x20, #RU_SUBJ            // a Bluetooth sensor: no polling, it tells us
    bl   _sens_dev_by_name
    tbnz x0, #63, Lra_poll
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x8, #D_KIND]
    cmp  x9, #K_BLES
    b.eq Lra_sens
Lra_poll:
    ADRL x0, Ls_ann_dev
    bl   _home_say0
    b    Lra_first
Lra_sens:
    ADRL x0, Ls_ann_sens
    bl   _home_say0
    b    Lra_first
Lra_thr:
    ldr  x0, [x20, #RU_FIELD]
    ldr  x1, [x20, #RU_DAYS]
    ldr  x2, [x20, #RU_MIN]
    ADRL x3, _g_wtxt
    bl   _sens_thr_text
    ADRL x0, Lf_ann_thr
    mov  x1, x21
    add  x2, x20, #RU_SUBJ
    ADRL x3, _g_wtxt
    add  x4, x20, #RU_CMD
    bl   _home_say4
    ADRL x0, Ls_ann_sens
    bl   _home_say0
    b    Lra_first
Lra_btn:
    ldr  x9, [x20, #RU_WHEN]
    ldr  x3, [x9, #40]
    ldr  x9, [x20, #RU_DAYS]
    cbnz x9, Lra_btn_n
    ADRL x0, Lf_ann_when
    mov  x1, x21
    add  x2, x20, #RU_SUBJ
    add  x4, x20, #RU_CMD
    bl   _home_say4
    b    Lra_first
Lra_btn_n:
    mov  x22, x3                      // the tense
    ADRL x0, _g_wtxt                  // "Remote button 2"
    mov  x1, #96
    ADRL x2, Lf_btn_subj
    add  x3, x20, #RU_SUBJ
    mov  x4, x9
    bl   _sfmt
    ADRL x0, Lf_ann_when
    mov  x1, x21
    ADRL x2, _g_wtxt
    mov  x3, x22
    add  x4, x20, #RU_CMD
    bl   _home_say4
    b    Lra_first
Lra_pres:
    add  x0, x20, #RU_SUBJ
    bl   _pres_age
    ADRL x9, Lf_ann_here
    ADRL x10, Lf_ann_away
    tbnz x0, #63, Lra_away
    cmp  x0, #90
    b.gt Lra_away
    mov  x0, x9
    b    Lra_pres_say
Lra_away:
    mov  x0, x10
Lra_pres_say:
    add  x1, x20, #RU_SUBJ
    bl   _home_say
    b    Lra_first
Lra_at:
    ldr  x0, [x20, #RU_WHEN]
    bl   _min_of
    ADRL x1, _g_clk
    bl   _clock12
    ADRL x0, Lf_ann_at
    mov  x1, x21
    ADRL x2, _g_clk
    add  x3, x20, #RU_CMD
    bl   _home_say
    b    Lra_first
Lra_clock:
    mov  x0, x19
    bl   _when_text
    ADRL x0, Lf_ann_clock
    mov  x1, x21
    ADRL x2, _g_wtxt
    add  x3, x20, #RU_CMD
    bl   _home_say
    ldr  x0, [x20, #RU_MIN]
    cmp  x0, #T_SUNRISE
    b.lo Lra_first
    bl   _resolve_min
    tbz  x0, #63, Lra_first
    ADRL x0, Ls_ann_sun
    bl   _home_say0
Lra_first:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x9, #1
    b.ne Lra_done
    ADRL x0, Ls_ann_first
    bl   _home_say0
Lra_done:
    LEAVE 0

// long _dev_by_name(const char *name) -> the device called that (or containing it), -1
.globl _dev_by_name
_dev_by_name:
    ENTER 0
    mov  x19, x0
    ldrb w9, [x19]
    cbz  w9, Ldn_none
    mov  x20, #0
Ldn_exact:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Ldn_part
    ADRL x8, _g_devs
    add  x0, x8, x20, lsl #DEV_SHIFT
    add  x0, x0, #D_NAME
    mov  x1, x19
    bl   _strcasecmp
    cbz  w0, Ldn_found
    add  x20, x20, #1
    b    Ldn_exact
Ldn_part:
    mov  x20, #0
Ldn_part_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Ldn_none
    ADRL x8, _g_devs
    add  x0, x8, x20, lsl #DEV_SHIFT
    add  x0, x0, #D_NAME
    mov  x1, x19
    bl   _strcasestr
    cbnz x0, Ldn_found
    add  x20, x20, #1
    b    Ldn_part_loop
Ldn_found:
    mov  x0, x20
    LEAVE 0
Ldn_none:
    mov  x0, #-1
    LEAVE 0

// ---------------------------------------------------------------------------
// "rules", "cancel rule 2", "cancel all rules"
// ---------------------------------------------------------------------------

.globl _h_rules_list
_h_rules_list:
    ENTER 0
    ADRL x8, _g_rule_count
    ldr  x19, [x8]
    cbnz x19, Lhl2_some
    ADRL x0, Ls_no_rules
    bl   _home_say0
    LEAVE 0
Lhl2_some:
    ADRL x0, Lf_rules_head
    mov  x1, x19
    bl   _home_say
    mov  x20, #0
Lhl2_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lhl2_foot
    RULEA x21, x20
    ADRL x3, Ls_empty
    ADRL x4, Ls_empty
    ldr  x9, [x21, #RU_TYPE]
    cmp  x9, #R_AT
    b.eq Lhl2_at
    cmp  x9, #R_CLOCK
    b.ne Lhl2_say
    mov  x0, x20
    bl   _when_text
    ADRL x3, Ls_next_sep
    ADRL x4, _g_wtxt
    b    Lhl2_say
Lhl2_at:
    ldr  x0, [x21, #RU_WHEN]
    bl   _min_of
    ADRL x1, _g_clk2
    bl   _clock12
    ADRL x0, _g_wtxt
    mov  x1, #96
    ADRL x2, Lf_at_clock
    ADRL x3, _g_clk2
    bl   _sfmt
    ADRL x3, Ls_next_sep
    ADRL x4, _g_wtxt
Lhl2_say:
    ADRL x0, Lf_rule_line
    add  x1, x20, #1
    add  x2, x21, #RU_SENT
    bl   _home_say4
    add  x20, x20, #1
    b    Lhl2_loop
Lhl2_foot:
    ADRL x0, Ls_rules_foot
    bl   _home_say0
    LEAVE 0

.globl _h_rules_clear
_h_rules_clear:
    ENTER 0
    ADRL x8, _g_rule_count
    str  xzr, [x8]
    bl   _rules_save
    ADRL x0, Ls_rules_cleared
    bl   _home_say0
    LEAVE 0

// "cancel rule 2"
.globl _h_rule_cancel
_h_rule_cancel:
    ENTER 0
    ldrb w9, [x1]
    cmp  w9, #'#'
    b.ne Lrc_num
    add  x1, x1, #1
Lrc_num:
    mov  x0, x1
    bl   _atol
    mov  x19, x0
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, #1
    b.lt Lrc_none
    cmp  x19, x9
    b.gt Lrc_none
    sub  x20, x19, #1
    RULEA x21, x20
    ADRL x0, Lf_rule_cancelled
    mov  x1, x19
    add  x2, x21, #RU_SENT
    bl   _home_say
    mov  x0, x20
    bl   _rule_del
    bl   _rules_save
    LEAVE 0
Lrc_none:
    ADRL x0, Lf_no_rule
    mov  x1, x19
    bl   _home_say
    LEAVE 0

// ---------------------------------------------------------------------------
// Every second
// ---------------------------------------------------------------------------

// void _rules_tick(long seconds_since_launch)
.globl _rules_tick
_rules_tick:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_busy
    ldr  x9, [x8]
    cbnz x9, Lrk_done
    mov  x0, #SVC_RULES               // which switches are on (Settings)
    bl   _svc_on
    mov  x20, x0
    mov  x0, #SVC_FIND
    bl   _svc_on
    mov  x21, x0
    mov  x0, #SVC_WEATHER
    bl   _svc_on
    mov  x22, x0
    bl   _now_tm
    ADRL x8, _g_today                 // a new day: today's sunrise and sunset
    ldr  x9, [x8]
    ADRL x10, _g_last_day
    ldr  x11, [x10]
    cmp  x9, x11
    b.eq Lrk_weather
    str  x9, [x10]
    cbz  x11, Lrk_weather
    cbz  x22, Lrk_weather
    mov  x0, #0
    bl   _weather_ask
Lrk_weather:
    cbz  x19, Lrk_minute
    mov  x9, #10800                   // and every three hours
    udiv x10, x19, x9
    msub x10, x10, x9, x19
    cbnz x10, Lrk_minute
    cbz  x22, Lrk_minute
    mov  x0, #0
    bl   _weather_ask
Lrk_minute:
    ADRL x8, _g_cur_min
    ldr  x9, [x8]
    ADRL x10, _g_last_min
    ldr  x11, [x10]
    cmp  x9, x11
    b.eq Lrk_at
    str  x9, [x10]
    cbz  x20, Lrk_at
    bl   _rules_clock_eval
Lrk_at:
    cbz  x20, Lrk_at_done
    bl   _rules_at_eval
Lrk_at_done:
    mov  x9, #10
    udiv x10, x19, x9
    msub x10, x10, x9, x19
    cmp  x10, #3
    b.ne Lrk_20
    cbz  x20, Lrk_10_find
    bl   _rules_pres_eval
    bl   _rules_dev_eval
Lrk_10_find:
    cbz  x21, Lrk_20
    bl   _tracker_check
Lrk_20:
    mov  x9, #20
    udiv x10, x19, x9
    msub x10, x10, x9, x19
    cmp  x10, #7
    b.ne Lrk_30
    cbz  x20, Lrk_30
    bl   _rules_poll
Lrk_30:
    mov  x9, #30
    udiv x10, x19, x9
    msub x10, x10, x9, x19
    cmp  x10, #12
    b.ne Lrk_60
    cbz  x21, Lrk_60
    bl   _seen_send
Lrk_60:
    mov  x9, #60
    udiv x10, x19, x9
    msub x10, x10, x9, x19
    cmp  x10, #30
    b.ne Lrk_fire
    bl   _near_prune
Lrk_fire:
    cbz  x20, Lrk_done
    bl   _rules_fire_one
Lrk_done:
    LEAVE 0

_rules_clock_eval:
    ENTER 0
    mov  x19, #0
Lce3_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lce3_done
    RULEA x20, x19
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_CLOCK
    b.ne Lce3_next
    ldr  x9, [x20, #RU_LAST]
    ADRL x8, _g_today
    ldr  x10, [x8]
    cmp  x9, x10
    b.eq Lce3_next
    ADRL x8, _g_wday
    ldr  x10, [x8]
    ldr  x11, [x20, #RU_DAYS]
    lsr  x11, x11, x10
    tbz  x11, #0, Lce3_next
    ldr  x0, [x20, #RU_MIN]
    bl   _resolve_min
    tbnz x0, #63, Lce3_next
    ADRL x8, _g_cur_min
    ldr  x9, [x8]
    cmp  x9, x0
    b.lt Lce3_next
    add  x10, x0, #3                  // a minute or two late (asleep, busy) still counts
    cmp  x9, x10
    b.ge Lce3_next
    ADRL x8, _g_today
    ldr  x10, [x8]
    str  x10, [x20, #RU_LAST]
    mov  x9, #1
    str  x9, [x20, #RU_PEND]
Lce3_next:
    add  x19, x19, #1
    b    Lce3_loop
Lce3_done:
    LEAVE 0

_rules_at_eval:
    ENTER 0
    mov  x19, #0
Lae_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lae_done
    RULEA x20, x19
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_AT
    b.ne Lae_next
    ldr  x9, [x20, #RU_WHEN]
    ADRL x8, _g_now
    ldr  x10, [x8]
    cmp  x10, x9
    b.lt Lae_next
    mov  x9, #1
    str  x9, [x20, #RU_PEND]
    mov  x9, #-1
    lsr  x9, x9, #1
    str  x9, [x20, #RU_WHEN]
Lae_next:
    add  x19, x19, #1
    b    Lae_loop
Lae_done:
    LEAVE 0

// void _rule_transition(rule, long state) — fires when it becomes the wanted state
_rule_transition:
    ldr  x9, [x0, #RU_PREV]
    str  x1, [x0, #RU_PREV]
    tbnz x9, #63, Ltr_done
    cmp  x9, x1
    b.eq Ltr_done
    ldr  x10, [x0, #RU_WANT]
    cmp  x10, x1
    b.ne Ltr_done
    mov  x10, #1
    str  x10, [x0, #RU_PEND]
Ltr_done:
    ret

// here: heard in the last 90 s; gone: not for 5 minutes (phones and Macs go quiet)
_rules_pres_eval:
    ENTER 0
    mov  x19, #0
Lpe_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lpe_done
    RULEA x20, x19
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_PRES
    b.ne Lpe_next
    add  x0, x20, #RU_SUBJ
    bl   _pres_age
    tbnz x0, #63, Lpe_gone
    cmp  x0, #90
    b.le Lpe_here
    cmp  x0, #300
    b.gt Lpe_gone
    b    Lpe_next
Lpe_here:
    mov  x1, #1
    b    Lpe_apply
Lpe_gone:
    mov  x1, #0
Lpe_apply:
    mov  x0, x20
    bl   _rule_transition
Lpe_next:
    add  x19, x19, #1
    b    Lpe_loop
Lpe_done:
    LEAVE 0

// void _rules_sens_eval(void) — a Bluetooth sensor said something new (sensors.s)
.globl _rules_sens_eval
_rules_sens_eval:
    ENTER 0
    ADRL x8, _g_busy
    ldr  x9, [x8]
    cbnz x9, Lrse_done
    bl   _rules_dev_eval
Lrse_done:
    LEAVE 0

// long _rules_button(long dev, long button, long press) -> how many rules it set off
.globl _rules_button
_rules_button:
    ENTER 16
    mov  x21, x0
    mov  x22, x1
    mov  x23, x2
    mov  x24, #0
    mov  x19, #0
Lrb_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lrb_done
    RULEA x20, x19
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_BTN
    b.ne Lrb_next
    ldr  x9, [x20, #RU_WANT]
    cmp  x9, x23
    b.ne Lrb_next
    ldr  x9, [x20, #RU_DAYS]
    cbz  x9, Lrb_dev
    cmp  x9, x22
    b.ne Lrb_next
Lrb_dev:
    add  x0, x20, #RU_SUBJ
    bl   _sens_dev_by_name
    cmp  x0, x21
    b.ne Lrb_next
    mov  x9, #1
    str  x9, [x20, #RU_PEND]
    add  x24, x24, #1
Lrb_next:
    add  x19, x19, #1
    b    Lrb_loop
Lrb_done:
    mov  x0, x24
    LEAVE 16

_rules_dev_eval:
    ENTER 0
    mov  x19, #0
Lde_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lde_done
    RULEA x20, x19
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_THR
    b.eq Lde_thr
    cmp  x9, #R_DEV
    b.ne Lde_next
    add  x0, x20, #RU_SUBJ
    bl   _sens_dev_by_name
    tbnz x0, #63, Lde_next
    ADRL x8, _g_devs
    add  x21, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x20, #RU_FIELD]
    cmp  x9, #D_ON
    b.eq Lde_read
    ldr  x10, [x21, #D_KIND]
    cmp  x10, #K_BLES
    b.eq Lde_read
    cmp  x10, #K_ST
    b.eq Lde_read
    cmp  x10, #K_HA
    b.ne Lde_next
Lde_read:
    ldr  x1, [x21, x9]
    tbnz x1, #63, Lde_next
    cmp  x1, #1
    b.hi Lde_next
    mov  x0, x20
    bl   _rule_transition
    b    Lde_next
Lde_thr:                              // above / below, with half a unit of slack once crossed
    add  x0, x20, #RU_SUBJ
    bl   _sens_dev_by_name
    tbnz x0, #63, Lde_next
    ldr  x1, [x20, #RU_FIELD]
    bl   _sens_value
    cbz  x1, Lde_next
    ldr  x10, [x20, #RU_MIN]
    ldr  x11, [x20, #RU_PREV]
    mov  x12, #50
    ldr  x9, [x20, #RU_DAYS]
    cbz  x9, Lde_below
    cmp  x11, #1                      // above: v > limit (once above, until v <= limit - 0.5)
    b.ne Lde_a_cmp
    sub  x10, x10, x12
Lde_a_cmp:
    cmp  x0, x10
    cset x1, gt
    b    Lde_thr_go
Lde_below:
    cmp  x11, #1
    b.ne Lde_b_cmp
    add  x10, x10, x12
Lde_b_cmp:
    cmp  x0, x10
    cset x1, lt
Lde_thr_go:
    mov  x0, x20
    bl   _rule_transition
Lde_next:
    add  x19, x19, #1
    b    Lde_loop
Lde_done:
    LEAVE 0

// every 20 s: ask SmartThings / Home Assistant how the watched devices are
_rules_poll:
    ENTER 0
    mov  x19, #0
Lpl2_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lpl2_done
    RULEA x20, x19
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_DEV
    b.ne Lpl2_next
    add  x0, x20, #RU_SUBJ
    bl   _dev_by_name
    tbnz x0, #63, Lpl2_next
    mov  x21, x0
    ADRL x8, _g_devs
    add  x9, x8, x21, lsl #DEV_SHIFT
    ldr  x10, [x9, #D_KIND]
    cmp  x10, #K_ST
    b.eq Lpl2_st
    cmp  x10, #K_HA
    b.ne Lpl2_next
    mov  x0, x21
    bl   _ha_poll
    b    Lpl2_next
Lpl2_st:
    mov  x0, x21
    bl   _st_poll
Lpl2_next:
    add  x19, x19, #1
    b    Lpl2_loop
Lpl2_done:
    LEAVE 0

// one due rule per second; the rest wait their turn
_rules_fire_one:
    ENTER 0
    ADRL x8, _g_busy
    mov  x9, #1
    str  x9, [x8]
    mov  x19, #0
Lf1_loop:
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lf1_done
    RULEA x20, x19
    ldr  x9, [x20, #RU_PEND]
    cbz  x9, Lf1_next
    str  xzr, [x20, #RU_PEND]
    ADRL x0, _g_fire_cmd
    add  x1, x20, #RU_CMD
    mov  x2, #RU_CMD_MAX
    bl   _strlcpy
    ADRL x0, Lf_firing
    add  x1, x19, #1
    add  x2, x20, #RU_SENT
    bl   _home_say
    ldr  x9, [x20, #RU_TYPE]
    cmp  x9, #R_AT
    b.eq Lf1_del
    ldr  x9, [x20, #RU_ONCE]
    cbz  x9, Lf1_run
Lf1_del:
    mov  x0, x19
    bl   _rule_del
Lf1_run:
    ADRL x0, _g_fire_cmd
    bl   _run_text
    b    Lf1_done
Lf1_next:
    add  x19, x19, #1
    b    Lf1_loop
Lf1_done:
    ADRL x8, _g_busy
    str  xzr, [x8]
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_empty:        .asciz ""
Ls_nl:           .asciz "\n"
Ls_pref_rules:   .asciz "rules"
Ls_sp_in_sp:     .asciz " in "
Ls_sp_at_sp:     .asciz " at "
Lf_remind:       .asciz "remind %s"
Lf_notify_ev:    .asciz "notify %s %s"
Lf_when:         .asciz "%s at %s"
Lf_sun_at:       .asciz "%s (%s today)"
Lf_at_clock:     .asciz "at %s"
Ls_next_sep:     .asciz " \342\200\224 next: "
Ls_today:        .asciz "today"
Ls_tomorrow:     .asciz "tomorrow"
Ls_every_day:    .asciz "every day"
Ls_on_weekdays:  .asciz "weekdays"
Ls_on_weekends:  .asciz "weekends"
Ls_some_days:    .asciz "some days"
Ln_sun:          .asciz "Sundays"
Ln_mon:          .asciz "Mondays"
Ln_tue:          .asciz "Tuesdays"
Ln_wed:          .asciz "Wednesdays"
Ln_thu:          .asciz "Thursdays"
Ln_fri:          .asciz "Fridays"
Ln_sat:          .asciz "Saturdays"

Lf_rule_unknown: .asciz "\302\267 I don't know how to \342\200\234%s\342\200\235, so I didn't make that rule. Say \342\200\234help\342\200\235 for what I can do."
Ls_rule_which:   .asciz "\302\267 More than one device matches \342\200\224 use its whole name (\342\200\234list devices\342\200\235 shows them), and I'll make the rule."
Lf_rule_nodev:   .asciz "\302\267 I can't find a device called \342\200\234%s\342\200\235. Say \342\200\234list devices\342\200\235 to see their names."
Lf_rule_nostate: .asciz "\302\267 I can only tell when %s opens, closes, locks or unlocks if it comes from SmartThings, Home Assistant or a Bluetooth sensor (motion and water: Bluetooth sensors)."
Ls_when_help:    .asciz "\302\267 I can follow: when <someone> arrives / leaves; when <device> turns on / off, opens / closes, locks / unlocks; and for Bluetooth sensors: detects motion, detects water, gets above / drops below <number>, is pressed / double-pressed / long-pressed \342\200\224 e.g. \342\200\234when Anna arrives turn on the hall light\342\200\235, \342\200\234when bedroom gets above 78 turn on the fan\342\200\235."
Ls_rules_full:   .asciz "\302\267 That's 24 rules already \342\200\224 cancel one first (\342\200\234rules\342\200\235 lists them)."
Ls_what_then:    .asciz "\302\267 And what should happen then? e.g. \342\200\234at 7 pm turn on the porch light\342\200\235."
Ls_remind_help:  .asciz "\302\267 When? e.g. \342\200\234remind me in 20 minutes to check the oven\342\200\235 or \342\200\234remind me at 5 pm to call Anna\342\200\235."
Lf_ampm:         .asciz "\302\267 %ld in the morning or the evening? Say \342\200\234at %ld am\342\200\235 or \342\200\234at %ld pm\342\200\235."
Lf_ann_when:     .asciz "\302\267 \360\237\224\224 Rule %ld: when %s %s \342\206\222 %s."
Ls_ann_dev:      .asciz "\302\267 I'll check it every 20 seconds while asmmesh is open."
Lf_ann_here:     .asciz "\302\267 %s is in range right now; I'll notice when that changes."
Lf_ann_away:     .asciz "\302\267 %s isn't in range right now. I look for their Mac on the mesh, and for Bluetooth gadgets that say that name (iPhones don't, sadly)."
Lf_ann_at:       .asciz "\302\267 \342\217\260 Rule %ld: at %s \342\206\222 %s."
Lf_ann_clock:    .asciz "\302\267 \342\217\260 Rule %ld: %s \342\206\222 %s."
Ls_ann_sun:      .asciz "\302\267 I don't know today's sunrise and sunset yet \342\200\224 say \342\200\234my city is \342\200\246\342\200\235 so I can look them up."
Ls_ann_first:    .asciz "\302\267 Rules run while asmmesh is open on this Mac. \342\200\234rules\342\200\235 lists them; \342\200\234cancel rule 1\342\200\235 removes one."
Ls_no_rules:     .asciz "\302\267 No rules yet. Try \342\200\234every weekday at 7 am turn on the kitchen lights\342\200\235, \342\200\234at sunset turn on the porch light\342\200\235, \342\200\234in 20 minutes turn off the TV\342\200\235, \342\200\234when Anna arrives turn on the hall light\342\200\235 or \342\200\234notify me when the front door opens\342\200\235."
Lf_rules_head:   .asciz "\302\267 \342\217\260 Rules (%ld) \342\200\224 they run while asmmesh is open on this Mac:"
Lf_rule_line:    .asciz "\302\267 %ld. %s%s%s"
Ls_rules_foot:   .asciz "\302\267 \342\200\234cancel rule 2\342\200\235 removes one; \342\200\234cancel all rules\342\200\235 removes them all."
Ls_rules_cleared: .asciz "\302\267 All rules cancelled."
Lf_rule_cancelled: .asciz "\302\267 Cancelled rule %ld (%s)."
Lf_no_rule:      .asciz "\302\267 There's no rule %ld \342\200\224 \342\200\234rules\342\200\235 lists them."
Lf_firing:       .asciz "\302\267 \342\226\266 Rule %ld: %s"

Lw_rules:        .asciz "rules"
Lw_list_rules:   .asciz "list rules"
Lw_show_rules:   .asciz "show rules"
Lw_my_rules:     .asciz "my rules"
Lw_cancel_all:   .asciz "cancel all rules"
Lw_clear_rules:  .asciz "clear rules"
Lw_clear_all:    .asciz "clear all rules"
Lw_delete_all:   .asciz "delete all rules"
Lw_remove_all:   .asciz "remove all rules"
Lw_cancel_rule:  .asciz "cancel rule"
Lw_delete_rule:  .asciz "delete rule"
Lw_remove_rule:  .asciz "remove rule"
Lw_stop_rule:    .asciz "stop rule"
Lw_where_am_i:   .asciz "where am i"
Lw_sos:          .asciz "sos"
Lw_send_sos:     .asciz "send sos"
Lw_location:     .asciz "location"
Lw_my_address:   .asciz "my address"
Lw_where_this_mac: .asciz "where is this mac"
Lw_alerts:       .asciz "alerts"
Lw_weather_alerts: .asciz "weather alerts"
Lw_any_alerts:   .asciz "any weather alerts"
Lw_ntfy_test:    .asciz "ntfy test"
Lw_push_test:    .asciz "push test"
Lw_test_push:    .asciz "test push"
Lw_pushover:     .asciz "pushover"
Lw_pushover_test: .asciz "pushover test"
Lw_pushover_token: .asciz "pushover token"
Lw_pushover_user: .asciz "pushover user"
Lw_webhook:      .asciz "webhook"
Lw_webhook_new:  .asciz "webhook new"
Lw_files:        .asciz "files"
Lw_files_page:   .asciz "files page"
Lw_file_page:    .asciz "file page"
Lw_files_new:    .asciz "files new"
Lw_share_folders: .asciz "share folders"
Lw_files_choose: .asciz "files choose"
Lw_airdrop:      .asciz "airdrop"
Lw_airdrop_file: .asciz "airdrop a file"
Lw_fm_rep_on:    .asciz "fm repeat on"
Lw_fm_rep_off:   .asciz "fm repeat off"
Lw_spin:         .asciz "spin"
Lw_spin_debug:   .asciz "spin debug"
Lw_spin_color:   .asciz "spin color"
Lw_spin_colour:  .asciz "spin colour"
Lw_spin_status:  .asciz "spin remote"
Lw_connect_spin: .asciz "connect spin"
Lw_pair_spin:    .asciz "pair spin"
Lw_spin_controls: .asciz "spin controls"
Lw_spin_drives:  .asciz "spin drives"
Lw_spin_groups:  .asciz "spin groups"
Lw_services:     .asciz "services"
Lw_bitchat:      .asciz "bitchat"
Lw_bitchat_status: .asciz "bitchat status"
Lw_bc_adv_on:    .asciz "bitchat advertise on"
Lw_bc_adv_off:   .asciz "bitchat advertise off"
Lw_bc_people:    .asciz "bitchat people"
Lw_bc_forget:    .asciz "bitchat forget"
Lw_bc_ann_on:    .asciz "bitchat announce on"
Lw_bc_ann_off:   .asciz "bitchat announce off"
Lw_settings:     .asciz "settings"
Lw_service_list: .asciz "list services"
Lw_enable:       .asciz "enable"
Lw_disable:      .asciz "disable"
Lw_spin_colors:  .asciz "spin colors"
Lw_spin_group:   .asciz "spin group"
Lw_spin_off:     .asciz "spin off"
Lw_spin_lock:    .asciz "spin lock"
Lw_lock_spin:    .asciz "lock spin"
Lw_spin_on:      .asciz "spin on"
Lw_spin_unlock:  .asciz "spin unlock"
Lw_unlock_spin:  .asciz "unlock spin"
Lw_this_mac_in:  .asciz "this mac is in"
Lw_this_comp_in: .asciz "this computer is in"
Lw_im_in:        .asciz "i'm in"
Lw_im_in2:       .asciz "im in"
Lw_i_am_in:      .asciz "i am in"
Lw_where_is_my:  .asciz "where is my"
Lw_where_are_my: .asciz "where are my"
Lw_wheres_my:    .asciz "where's my"
Lw_wheres_my2:   .asciz "wheres my"
Lw_find_my:      .asciz "find my"
Lw_where_is:     .asciz "where is"
Lw_where_are:    .asciz "where are"
Lw_wheres:       .asciz "where's"
Lw_wheres2:      .asciz "wheres"
Lw_locate:       .asciz "locate"
Lw_trackers:     .asciz "trackers"
Lw_list_trackers: .asciz "list trackers"
Lw_any_trackers: .asciz "any trackers"
Lw_trackers_near: .asciz "trackers nearby"
Lw_trust:        .asciz "trust trackers"
Lw_trust1:       .asciz "trust tracker"
Lw_trust2:       .asciz "these trackers are mine"
Lw_trust3:       .asciz "this tracker is mine"
Lw_weather:      .asciz "weather"
Lw_weather_today: .asciz "weather today"
Lw_weather_now:  .asciz "weather now"
Lw_forecast:     .asciz "forecast"
Lw_whats_weather: .asciz "what's the weather"
Lw_hows_weather: .asciz "how's the weather"
Lw_weather_tom:  .asciz "weather tomorrow"
Lw_forecast_tom: .asciz "forecast tomorrow"
Lw_tom_weather:  .asciz "tomorrow's weather"
Lw_tom_weather2: .asciz "tomorrows weather"
Lw_air_quality:  .asciz "air quality"
Lw_aqi:          .asciz "aqi"
Lw_hows_air:     .asciz "how's the air"
Lw_sunset:       .asciz "sunset"
Lw_sunrise:      .asciz "sunrise"
Lw_when_sunset:  .asciz "when is sunset"
Lw_when_sunrise: .asciz "when is sunrise"
Lw_whens_sunset: .asciz "when's sunset"
Lw_whens_sunset2: .asciz "when's sunrise"
Lw_will_rain:    .asciz "will it rain"
Lw_will_rain_today: .asciz "will it rain today"
Lw_will_rain_tom: .asciz "will it rain tomorrow"
Lw_going_to_rain: .asciz "is it going to rain"
Lw_use_c:        .asciz "use celsius"
Lw_celsius:      .asciz "celsius"
Lw_use_f:        .asciz "use fahrenheit"
Lw_fahrenheit:   .asciz "fahrenheit"
Lw_energy:       .asciz "energy"
Lw_energy_use:   .asciz "energy use"
Lw_energy_usage: .asciz "energy usage"
Lw_power_use:    .asciz "power use"
Lw_power_usage:  .asciz "power usage"
Lw_how_much_power: .asciz "how much power"
Lw_how_much_energy: .asciz "how much energy"
Lw_watts:        .asciz "watts"
Lw_help_more:    .asciz "help more"
Lw_more_help:    .asciz "more help"
Lw_what_else:    .asciz "what else can you do"
Lw_help_rules:   .asciz "help rules"
Lw_notify_topic: .asciz "notify topic"
Lw_ntfy_topic:   .asciz "ntfy topic"
Lw_notif_topic:  .asciz "notification topic"
Lw_notify:       .asciz "notify"
Lw_push:         .asciz "push"
Lw_ntfy:         .asciz "ntfy"
Lw_ifttt_key:    .asciz "ifttt key"
Lw_trigger:      .asciz "trigger"
Lw_ifttt:        .asciz "ifttt"
Lw_say:          .asciz "say"
Lw_speak:        .asciz "speak"
Lw_remind:       .asciz "remind"
Lw_my_city:      .asciz "my city is"
Lw_i_live_in:    .asciz "i live in"
Lw_set_city_to:  .asciz "set city to"
Lw_set_city:     .asciz "set city"
Lw_my_location:  .asciz "my location is"
Lw_set_loc_to:   .asciz "set location to"
Lw_set_loc:      .asciz "set location"
Lw_http_get:     .asciz "http get"
Lw_notify_when:  .asciz "notify me when"
Lw_tell_when:    .asciz "tell me when"
Lw_alert_when:   .asciz "alert me when"
Lw_letmek_when:  .asciz "let me know when"
Lw_ping_when:    .asciz "ping me when"
Lw_text_when:    .asciz "text me when"
Lw_whenever:     .asciz "whenever"
Lw_when:         .asciz "when"
Lw_if:           .asciz "if"
Lw_notify_me:    .asciz "notify me"
Lw_tell_me:      .asciz "tell me"
Lw_let_me_know:  .asciz "let me know"
Lw_alert_me:     .asciz "alert me"
Lw_ping_me:      .asciz "ping me"
Lw_text_me:      .asciz "text me"
Lw_send_notif:   .asciz "send me a notification"
Lw_remind_me:    .asciz "remind me"
Lw_in:           .asciz "in"
Lw_at:           .asciz "at"
Lw_then:         .asciz "then"
Lw_to:           .asciz "to"
Lw_half_hour:    .asciz "half an hour"
Lw_an_hour:      .asciz "an hour"
Lw_a_minute:     .asciz "a minute"
Lw_the:          .asciz "the"
Lw_my:           .asciz "my"
Lw_a:            .asciz "a"
Lw_an:           .asciz "an"
Lw_our:          .asciz "our"
Lw_your:         .asciz "your"
Lt_noon:         .asciz "noon"
Lt_midnight:     .asciz "midnight"
Lt_sunrise:      .asciz "sunrise"
Lt_dawn:         .asciz "dawn"
Lt_sunset:       .asciz "sunset"
Lt_dusk:         .asciz "dusk"
Lu_minutes:      .asciz "minutes"
Lu_minute:       .asciz "minute"
Lu_mins:         .asciz "mins"
Lu_min:          .asciz "min"
Lu_hours:        .asciz "hours"
Lu_hour:         .asciz "hour"
Lu_hrs:          .asciz "hrs"
Lu_hr:           .asciz "hr"
Lu_seconds:      .asciz "seconds"
Lu_second:       .asciz "second"
Lu_secs:         .asciz "secs"
Lu_sec:          .asciz "sec"
Ld_every_day:    .asciz "every day"
Ld_everyday:     .asciz "everyday"
Ld_daily:        .asciz "daily"
Ld_each_day:     .asciz "each day"
Ld_every_morning: .asciz "every morning"
Ld_every_evening: .asciz "every evening"
Ld_every_night:  .asciz "every night"
Ld_every_weekday: .asciz "every weekday"
Ld_on_weekdays:  .asciz "on weekdays"
Ld_weekdays:     .asciz "weekdays"
Ld_every_weekend: .asciz "every weekend"
Ld_on_weekends:  .asciz "on weekends"
Ld_weekends:     .asciz "weekends"
Ld_every_sun:    .asciz "every sunday"
Ld_on_suns:      .asciz "on sundays"
Ld_suns:         .asciz "sundays"
Ld_every_mon:    .asciz "every monday"
Ld_on_mons:      .asciz "on mondays"
Ld_mons:         .asciz "mondays"
Ld_every_tue:    .asciz "every tuesday"
Ld_on_tues:      .asciz "on tuesdays"
Ld_tues:         .asciz "tuesdays"
Ld_every_wed:    .asciz "every wednesday"
Ld_on_weds:      .asciz "on wednesdays"
Ld_weds:         .asciz "wednesdays"
Ld_every_thu:    .asciz "every thursday"
Ld_on_thus:      .asciz "on thursdays"
Ld_thus:         .asciz "thursdays"
Ld_every_fri:    .asciz "every friday"
Ld_on_fris:      .asciz "on fridays"
Ld_fris:         .asciz "fridays"
Ld_every_sat:    .asciz "every saturday"
Ld_on_sats:      .asciz "on saturdays"
Ld_sats:         .asciz "saturdays"
Ld_tomorrow:     .asciz "tomorrow"
Ld_today:        .asciz "today"
Ld_tonight:      .asciz "tonight"
Le_comes_home:   .asciz " comes home"
Le_gets_home:    .asciz " gets home"
Le_arrives_home: .asciz " arrives home"
Le_arrives:      .asciz " arrives"
Le_arrive:       .asciz " arrive"
Le_gets_here:    .asciz " gets here"
Le_comes_back:   .asciz " comes back"
Le_is_home:      .asciz " is home"
Le_leaves_home:  .asciz " leaves home"
Le_leaves:       .asciz " leaves"
Le_leave:        .asciz " leave"
Le_goes_out:     .asciz " goes out"
Le_is_away:      .asciz " is away"
Le_turns_on:     .asciz " turns on"
Le_is_turned_on: .asciz " is turned on"
Le_goes_on:      .asciz " goes on"
Le_switches_on:  .asciz " switches on"
Le_turns_off:    .asciz " turns off"
Le_is_turned_off: .asciz " is turned off"
Le_goes_off:     .asciz " goes off"
Le_switches_off: .asciz " switches off"
Le_opens:        .asciz " opens"
Le_is_opened:    .asciz " is opened"
Le_is_open:      .asciz " is open"
Le_open:         .asciz " open"
Le_closes:       .asciz " closes"
Le_is_closed:    .asciz " is closed"
Le_shuts:        .asciz " shuts"
Le_close:        .asciz " close"
Le_unlocks:      .asciz " unlocks"
Le_is_unlocked:  .asciz " is unlocked"
Le_locks:        .asciz " locks"
Le_is_locked:    .asciz " is locked"
Le_detects_motion: .asciz " detects motion"
Le_sees_motion:  .asciz " sees motion"
Le_senses_motion: .asciz " senses motion"
Le_stops_motion: .asciz " stops detecting motion"
Le_is_clear:     .asciz " is clear"
Le_detects_water: .asciz " detects water"
Le_detects_leak: .asciz " detects a leak"
Le_gets_wet:     .asciz " gets wet"
Le_is_wet:       .asciz " is wet"
Le_is_dry:       .asciz " is dry"
Le_gets_above:   .asciz " gets above"
Le_goes_above:   .asciz " goes above"
Le_rises_above:  .asciz " rises above"
Le_climbs_above: .asciz " climbs above"
Le_is_above:     .asciz " is above"
Le_gets_over:    .asciz " gets over"
Le_goes_over:    .asciz " goes over"
Le_is_over:      .asciz " is over"
Le_drops_below:  .asciz " drops below"
Le_falls_below:  .asciz " falls below"
Le_goes_below:   .asciz " goes below"
Le_gets_below:   .asciz " gets below"
Le_dips_below:   .asciz " dips below"
Le_is_below:     .asciz " is below"
Le_drops_under:  .asciz " drops under"
Le_falls_under:  .asciz " falls under"
Le_goes_under:   .asciz " goes under"
Le_gets_under:   .asciz " gets under"
Le_is_under:     .asciz " is under"
Le_is_pressed:   .asciz " is pressed"
Le_gets_pressed: .asciz " gets pressed"
Le_is_clicked:   .asciz " is clicked"
Le_is_double:    .asciz " is double pressed"
Le_is_double2:   .asciz " is double-pressed"
Le_is_double3:   .asciz " is double clicked"
Le_is_triple:    .asciz " is triple pressed"
Le_is_triple2:   .asciz " is triple-pressed"
Le_is_long:      .asciz " is long pressed"
Le_is_long2:     .asciz " is long-pressed"
Le_is_held:      .asciz " is held"
Le_is_held_down: .asciz " is held down"
Le_pressed_held: .asciz " is pressed and held"
Lp_motion:       .asciz "detected motion"
Lp_still:        .asciz "stopped seeing motion"
Lp_wet:          .asciz "detected water"
Lp_dry:          .asciz "is dry again"
Lp_above:        .asciz "went above the limit"
Lp_below:        .asciz "went below the limit"
Lp_pressed:      .asciz "was pressed"
Lp_double:       .asciz "was double-pressed"
Lp_triple:       .asciz "was triple-pressed"
Lp_long:         .asciz "was long-pressed"
Lq_motion:       .asciz "detects motion"
Lq_still:        .asciz "stops detecting motion"
Lq_wet:          .asciz "detects water"
Lq_dry:          .asciz "is dry"
Lq_above:        .asciz "goes above"
Lq_below:        .asciz "goes below"
Lq_pressed:      .asciz "is pressed"
Lq_double:       .asciz "is double-pressed"
Lq_triple:       .asciz "is triple-pressed"
Lq_long:         .asciz "is long-pressed"
Lf_notify_thr:   .asciz "notify %s is %s"
Lf_ann_thr:      .asciz "\302\267 \360\237\224\224 Rule %ld: when %s goes %s \342\206\222 %s."
Lf_btn_subj:     .asciz "%s button %ld"
Ls_ann_sens:     .asciz "\302\267 It's a Bluetooth sensor, so the rule runs the moment it broadcasts \342\200\224 while asmmesh is open and the sensor is in range."
Lf_rule_nosens:  .asciz "\302\267 I don't know a Bluetooth sensor called \342\200\234%s\342\200\235. Say \342\200\234sensors\342\200\235 to see what's nearby, then \342\200\234name sensor 2 bedroom\342\200\235."
Ls_rule_thr_help: .asciz "\302\267 Tell me the number, e.g. \342\200\234when bedroom gets above 78 turn on the fan\342\200\235 or \342\200\234when the bathroom humidity goes above 70% turn on the fan\342\200\235."
Lw_name_sensor:  .asciz "name sensor"
Lw_sensors:      .asciz "sensors"
Lw_list_sensors: .asciz "list sensors"
Lw_my_sensors:   .asciz "my sensors"
Lw_bt_sensors:   .asciz "bluetooth sensors"
Lw_batteries:    .asciz "batteries"
Lw_battery:      .asciz "battery"
Lw_battery_levels: .asciz "battery levels"
Lw_low_batteries: .asciz "low batteries"
Lw_check_batteries: .asciz "check batteries"
Lw_hp_here:      .asciz "headphones here"
Lw_air_here:     .asciz "airpods here"
Lw_hp_here2:     .asciz "move my headphones here"
Lw_air_here2:    .asciz "move my airpods here"
Lw_hp_take:      .asciz "connect my headphones"
Lw_air_take:     .asciz "connect my airpods"
Lw_hp_switch:    .asciz "switch my headphones here"
Lw_air_switch:   .asciz "switch my airpods here"
Lw_send_hp:      .asciz "send my headphones to"
Lw_send_hp2:     .asciz "send headphones to"
Lw_send_air:     .asciz "send my airpods to"
Lw_send_air2:    .asciz "send airpods to"
Lp_arrived:      .asciz "arrived"
Lp_left:         .asciz "left"
Lp_turned_on:    .asciz "turned on"
Lp_turned_off:   .asciz "turned off"
Lp_opened:       .asciz "opened"
Lp_closed:       .asciz "closed"
Lp_unlocked:     .asciz "was unlocked"
Lp_locked:       .asciz "was locked"
Lq_arrives:      .asciz "arrives"
Lq_leaves:       .asciz "leaves"
Lq_turns_on:     .asciz "turns on"
Lq_turns_off:    .asciz "turns off"
Lq_opens:        .asciz "opens"
Lq_closes:       .asciz "closes"
Lq_unlocks:      .asciz "is unlocked"
Lq_locks:        .asciz "is locked"
