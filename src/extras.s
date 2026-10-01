// extras.s — notifications to your phone, IFTTT, speech, weather words, energy.
//
//   notify topic <name>     ntfy.sh topic (free; the ntfy app on your phone subscribes)
//   notify <message>        push it now; rules can "notify …" too
//   ifttt key <key>         Webhooks key from ifttt.com/maker_webhooks (kept in Keychain)
//   trigger <event>         POST https://maker.ifttt.com/trigger/<event>/with/key/<key>
//   say <text>              speak it on this Mac
//   remind …                (rules.s) shows it, speaks it, and pushes it

.include "macros.inc"

.data
.p2align 3
.globl _g_ntfy_topic
.zerofill __DATA,__bss,_g_ntfy_topic,72,4
.zerofill __DATA,__bss,_g_ifttt_key,96,4
.zerofill __DATA,__bss,_g_ifttt_event,64,4
.zerofill __DATA,__bss,_g_xurl,512,4
.zerofill __DATA,__bss,_g_xtmp,320,4

.text
.p2align 2

// void _extras_init(void)
.globl _extras_init
_extras_init:
    ENTER 0
    ADRL x0, Ls_pref_topic
    ADRL x1, _g_ntfy_topic
    mov  x2, #72
    bl   _pref_get
    LEAVE 0

// void _extras_kc_read(void) — background, with the other Keychain reads
.globl _extras_kc_read
_extras_kc_read:
    ENTER 0
    ADRL x0, Ls_kc_ifttt
    ADRL x1, _g_ifttt_key
    mov  x2, #96
    bl   _kc_get
    LEAVE 0

// size_t _token_copy(char *dst, const char *src, size_t max, long spaces_to_underscore)
//   letters, digits, - and _ only
_token_copy:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    sub  x21, x2, #1
    mov  x22, #0
Ltk2_loop:
    cmp  x22, x21
    b.hs Ltk2_end
    ldrb w9, [x20], #1
    cbz  w9, Ltk2_end
    cmp  w9, #' '
    b.ne Ltk2_chk
    cbz  x3, Ltk2_loop
    mov  w9, #'_'
    b    Ltk2_put
Ltk2_chk:
    cmp  w9, #'-'
    b.eq Ltk2_put
    cmp  w9, #'_'
    b.eq Ltk2_put
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.ls Ltk2_put
    orr  w10, w9, #0x20
    sub  w10, w10, #'a'
    cmp  w10, #25
    b.hi Ltk2_loop
Ltk2_put:
    strb w9, [x19, x22]
    add  x22, x22, #1
    b    Ltk2_loop
Ltk2_end:
    strb wzr, [x19, x22]
    mov  x0, x22
    LEAVE 0

// ---------------------------------------------------------------------------
// ntfy
// ---------------------------------------------------------------------------

// void _notify_quiet(const char *text) — for rules, trackers and the SPIN: every push
//   service that is switched on (ntfy, Pushover — alerts.s), silently
.globl _notify_quiet
_notify_quiet:
    ENTER 0
    mov  x1, #0
    bl   _push_all
    LEAVE 0

// "notify <message>"
.globl _h_notify
_h_notify:
    ENTER 0
    ldrb w9, [x2]
    cbz  w9, Lhn_usage
    mov  x0, x2
    mov  x1, #0
    bl   _push_any
    LEAVE 0
Lhn_usage:
    ADRL x0, Ls_ntfy_usage
    bl   _home_say0
    LEAVE 0

// "notify topic <name>" / "notify topic off"
.globl _h_ntfy_topic
_h_ntfy_topic:
    ENTER 0
    mov  x19, x2
    mov  x0, x1
    ADRL x1, Ls_off
    bl   _strcmp
    cbz  w0, Lnt3_off
    ADRL x0, _g_ntfy_topic
    mov  x1, x19
    mov  x2, #65
    mov  x3, #0
    bl   _token_copy
    cmp  x0, #1
    b.lo Lnt3_usage
    ADRL x0, Ls_pref_topic
    ADRL x1, _g_ntfy_topic
    bl   _pref_set
    ADRL x0, Lf_ntfy_set
    ADRL x1, _g_ntfy_topic
    ADRL x2, _g_ntfy_topic
    bl   _home_say
    LEAVE 0
Lnt3_off:
    ADRL x8, _g_ntfy_topic
    strb wzr, [x8]
    ADRL x0, Ls_pref_topic
    ADRL x1, _g_ntfy_topic
    bl   _pref_set
    ADRL x0, Ls_ntfy_off
    bl   _home_say0
    LEAVE 0
Lnt3_usage:
    ADRL x0, Ls_ntfy_need
    bl   _home_say0
    LEAVE 0

// ---------------------------------------------------------------------------
// IFTTT webhooks
// ---------------------------------------------------------------------------

// "ifttt key <key>"
.globl _h_ifttt_key
_h_ifttt_key:
    ENTER 0
    ADRL x0, _g_xtmp
    mov  x1, x2
    mov  x2, #96
    mov  x3, #0
    bl   _token_copy
    cmp  x0, #10
    b.lo Lik_bad
    ADRL x0, _g_ifttt_key
    ADRL x1, _g_xtmp
    mov  x2, #96
    bl   _strlcpy
    ADRL x0, Ls_kc_ifttt
    ADRL x1, _g_ifttt_key
    bl   _kc_set
    ADRL x0, Ls_ifttt_saved
    bl   _home_say0
    LEAVE 0
Lik_bad:
    ADRL x0, Ls_ifttt_need
    bl   _home_say0
    LEAVE 0

// void _trigger_event(const char *name)
.globl _trigger_event
_trigger_event:
    ENTER 0
    mov  x1, x0
    ADRL x0, _g_ifttt_event
    mov  x2, #60
    mov  x3, #1
    bl   _token_copy
    cbz  x0, Lte_usage
    ADRL x8, _g_ifttt_key
    ldrb w9, [x8]
    cbz  w9, Lte_nokey
    ADRL x0, _g_xurl
    mov  x1, #512
    ADRL x2, Lf_ifttt_url
    ADRL x3, _g_ifttt_event
    ADRL x4, _g_ifttt_key
    bl   _sfmt
    ADRL x0, Ls_POST
    ADRL x1, _g_xurl
    ADRL x2, Ls_json_empty
    mov  x3, #0
    ADRL x4, Ls_tag_i
    bl   _http
    LEAVE 0
Lte_usage:
    ADRL x0, Ls_trigger_usage
    bl   _home_say0
    LEAVE 0
Lte_nokey:
    ADRL x0, Ls_ifttt_need
    bl   _home_say0
    LEAVE 0

// "trigger <event>"
.globl _h_trigger
_h_trigger:
    ENTER 0
    mov  x0, x1
    bl   _trigger_event
    LEAVE 0

// ---------------------------------------------------------------------------
// Speech
// ---------------------------------------------------------------------------

// void _say_text(const char *text) — /usr/bin/say, never with options
.globl _say_text
_say_text:
    ENTER 0
    mov  x19, x0
Lsy_lead:
    ldrb w9, [x19]
    cmp  w9, #'-'
    b.eq Lsy_skip
    cmp  w9, #' '
    b.ne Lsy_go
Lsy_skip:
    add  x19, x19, #1
    b    Lsy_lead
Lsy_go:
    ldrb w9, [x19]
    cbz  w9, Lsy_done
    ADRL x0, _g_xtmp
    mov  x1, x19
    mov  x2, #300
    bl   _strlcpy
    ADRL x0, _g_xtmp
    bl   _utf8_fix
    ADRL x0, _g_xtmp
    bl   _nsstr
    cbz  x0, Lsy_done
    mov  x19, x0
    CLS  Ls_NSArray
    mov  x2, x19
    MSG1 Ls_arrayWithObject
    mov  x20, x0
    ADRL x0, Ls_say_path
    bl   _nsstr
    mov  x21, x0
    CLS  Ls_NSTask
    mov  x2, x21
    mov  x3, x20
    MSG2 Ls_launchedTask
Lsy_done:
    LEAVE 0

// "say <text>"
.globl _h_say
_h_say:
    ENTER 0
    mov  x19, x2
    ldrb w9, [x19]
    cbz  w9, Lhs2_usage
    ADRL x0, Lf_said
    mov  x1, x19
    bl   _home_say
    mov  x0, x19
    bl   _say_text
    LEAVE 0
Lhs2_usage:
    ADRL x0, Ls_say_usage
    bl   _home_say0
    LEAVE 0

// void _remind(const char *text) — a reminder coming due: show it, say it, push it
.globl _remind
_remind:
    ENTER 0
    mov  x19, x0
    ADRL x0, Lf_reminder
    mov  x1, x19
    bl   _home_say
    ADRL x0, Lf_reminder_main
    mov  x1, x19
    mov  x2, #0
    mov  x3, #0
    bl   _chat_fmt
    ADRL x0, _g_xtmp
    mov  x1, #300
    ADRL x2, Lf_reminder_say
    mov  x3, x19
    bl   _sfmt
    ADRL x0, _g_xtmp
    bl   _say_text
    mov  x0, x19
    bl   _notify_quiet
    LEAVE 0

// ---------------------------------------------------------------------------
// Weather words (weather.s does the work)
// ---------------------------------------------------------------------------

.globl _h_weather
_h_weather:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, #SVC_WEATHER
    bl   _svc_gate
    cbz  x0, Lhwx_off
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _weather_ask
Lhwx_off:
    LEAVE 0

.globl _h_units
_h_units:
    ENTER 0
    bl   _weather_units
    LEAVE 0

.globl _h_city
_h_city:
    ENTER 0
    ldrb w9, [x2]
    cbz  w9, Lhc2_usage
    mov  x0, x2
    bl   _weather_city
    LEAVE 0
Lhc2_usage:
    ADRL x0, Ls_city_usage
    bl   _home_say0
    LEAVE 0

// ---------------------------------------------------------------------------
// "energy": every power / energy meter's reading
// ---------------------------------------------------------------------------
.globl _h_energy
_h_energy:
    ENTER 0
    mov  x19, #0
    mov  x20, #0
Len_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Len_counted
    ADRL x8, _g_devs
    add  x8, x8, x19, lsl #DEV_SHIFT
    ldr  x9, [x8, #D_CAPS]
    tst  x9, #CAP_POWER
    b.eq Len_next
    add  x20, x20, #1
Len_next:
    add  x19, x19, #1
    b    Len_loop
Len_counted:
    cbz  x20, Len_none
    ADRL x0, Ls_status_energy
    bl   _run_text
    LEAVE 0
Len_none:
    ADRL x0, Ls_energy_none
    bl   _home_say0
    LEAVE 0

// "http get <url>" — for checking a web service by hand: status and the start of the answer
.globl _h_http_get
_h_http_get:
    ENTER 0
    mov  x19, x2
    mov  x0, #SVC_WEB
    bl   _svc_gate
    cbz  x0, Lhg_done
    mov  x2, x19
    ldrb w9, [x2]
    cbz  w9, Lhg_done
    mov  x1, x2
    ADRL x0, Ls_GET
    mov  x2, #0
    mov  x3, #0
    ADRL x4, Ls_tag_g
    bl   _http
Lhg_done:
    LEAVE 0

// "help more"
.globl _h_help_more
_h_help_more:
    ENTER 0
    ADRL x19, Lhelp_more
Lhm_loop:
    ldr  x0, [x19], #8
    cbz  x0, Lhm_done
    bl   _home_say0
    b    Lhm_loop
Lhm_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// void _extra_response(const char *tag, id json, long status, NSError *err, NSData *raw)
// ---------------------------------------------------------------------------
.globl _extra_response
_extra_response:
    ENTER 0
    mov  x19, x0
    mov  x20, x2
    ldrb w9, [x19, #1]
    cmp  w9, #'n'
    b.eq Lxr_ntfy
    cmp  w9, #'i'
    b.eq Lxr_ifttt
    cmp  w9, #'g'
    b.eq Lxr_get
    LEAVE 0
Lxr_get:
    ADRL x8, _g_xtmp
    strb wzr, [x8]
    cbz  x4, Lxr_get_say
    mov  x21, x4
    mov  x0, x21
    MSG0 Ls_length
    mov  x9, #300
    cmp  x0, x9
    csel x22, x9, x0, hi
    mov  x0, x21
    MSG0 Ls_bytes
    mov  x1, x0
    ADRL x0, _g_xtmp
    mov  x2, x22
    bl   _memcpy
    ADRL x8, _g_xtmp
    strb wzr, [x8, x22]
Lxr_get_clean:
    cbz  x22, Lxr_get_say
    sub  x22, x22, #1
    ldrb w10, [x8, x22]
    cmp  w10, #' '
    b.lo Lxr_get_sp
    cmp  w10, #0x7e
    b.ls Lxr_get_clean
Lxr_get_sp:
    mov  w10, #' '
    strb w10, [x8, x22]
    b    Lxr_get_clean
Lxr_get_say:
    ADRL x0, Lf_http_got
    mov  x1, x20
    ADRL x2, _g_xtmp
    bl   _home_say
    LEAVE 0
Lxr_ntfy:
    cmp  x20, #200
    b.ne Lxr_ntfy_err
    ldrb w9, [x19, #2]
    cmp  w9, #'1'
    b.ne Lxr_done
    ADRL x0, Lf_ntfy_ok
    ADRL x1, _g_ntfy_topic
    bl   _home_say
    LEAVE 0
Lxr_ntfy_err:
    ADRL x0, Lf_ntfy_err
    mov  x1, x20
    bl   _home_say
    LEAVE 0
Lxr_ifttt:
    cmp  x20, #200
    b.ne Lxr_ifttt_err
    ADRL x0, Lf_ifttt_ok
    ADRL x1, _g_ifttt_event
    bl   _home_say
    LEAVE 0
Lxr_ifttt_err:
    cmp  x20, #401
    b.eq Lxr_ifttt_key
    cmp  x20, #403
    b.eq Lxr_ifttt_key
    ADRL x0, Lf_ifttt_err
    mov  x1, x20
    bl   _home_say
    LEAVE 0
Lxr_ifttt_key:
    ADRL x0, Ls_ifttt_badkey
    bl   _home_say0
Lxr_done:
    LEAVE 0

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lhelp_more:
    .quad Ls_hm1, Ls_hm2, Ls_hm3, Ls_hm4, Ls_hm5, Ls_hm6, Ls_hm8, Ls_hm7, 0

.section __TEXT,__cstring,cstring_literals
Ls_pref_topic:   .asciz "ntfy_topic"
Ls_kc_ifttt:     .asciz "asmmesh.ifttt"
Ls_off:          .asciz "off"
Ls_POST:         .asciz "POST"
Ls_Title:        .asciz "Title"
Ls_asmmesh:      .asciz "asmmesh"
Ls_tag_n1:       .asciz "xn1"
Ls_tag_n0:       .asciz "xn0"
Ls_tag_i:        .asciz "xi"
Ls_tag_g:        .asciz "xg"
Ls_GET:          .asciz "GET"
Ls_length:       .asciz "length"
Ls_bytes:        .asciz "bytes"
Lf_http_got:     .asciz "\302\267 HTTP %ld: %s"
Ls_json_empty:   .asciz "{}"
Lf_ntfy_url:     .asciz "https://ntfy.sh/%s"
Lf_ifttt_url:    .asciz "https://maker.ifttt.com/trigger/%s/with/key/%s"
Ls_NSArray:      .asciz "NSArray"
Ls_NSTask:       .asciz "NSTask"
Ls_arrayWithObject: .asciz "arrayWithObject:"
Ls_launchedTask: .asciz "launchedTaskWithLaunchPath:arguments:"
Ls_say_path:     .asciz "/usr/bin/say"
Ls_status_energy: .asciz "status energy"
Ls_ntfy_need:    .asciz "\302\267 To get notifications on your phone: install the free ntfy app, subscribe to a topic name only you know, and tell me \342\200\234notify topic <that name>\342\200\235."
Ls_ntfy_usage:   .asciz "\302\267 Notify what? e.g. \342\200\234notify dinner is ready\342\200\235 (after \342\200\234notify topic <name>\342\200\235)."
Lf_ntfy_set:     .asciz "\302\267 \360\237\223\262 Notifications go to ntfy topic \342\200\234%s\342\200\235. On your phone, install the free ntfy app and subscribe to \342\200\234%s\342\200\235. Anyone who knows the name can read them, so make it hard to guess. Try \342\200\234notify hello\342\200\235."
Ls_ntfy_off:     .asciz "\302\267 Phone notifications are off."
Lf_ntfy_ok:      .asciz "\302\267 \360\237\223\262 Sent to ntfy topic \342\200\234%s\342\200\235."
Lf_ntfy_err:     .asciz "\302\267 ntfy.sh didn't take the notification (status %ld)."
Ls_ifttt_need:   .asciz "\302\267 IFTTT needs your Webhooks key: open ifttt.com/maker_webhooks \342\200\272 Documentation, copy the key, and tell me \342\200\234ifttt key <key>\342\200\235. It's kept in your Keychain."
Ls_ifttt_saved:  .asciz "\302\267 \342\232\241 IFTTT key saved in your Keychain. Now \342\200\234trigger <event name>\342\200\235 runs an applet whose If This is Webhooks with that event name \342\200\224 rules can do it too."
Ls_trigger_usage: .asciz "\302\267 Trigger which IFTTT event? e.g. \342\200\234trigger movie_night\342\200\235."
Lf_ifttt_ok:     .asciz "\302\267 \342\232\241 IFTTT: triggered \342\200\234%s\342\200\235."
Lf_ifttt_err:    .asciz "\302\267 IFTTT answered with status %ld."
Ls_ifttt_badkey: .asciz "\302\267 IFTTT didn't accept the key \342\200\224 copy it again from ifttt.com/maker_webhooks \342\200\272 Documentation and say \342\200\234ifttt key <key>\342\200\235."
Lf_said:         .asciz "\302\267 \360\237\227\243 \342\200\234%s\342\200\235"
Ls_say_usage:    .asciz "\302\267 Say what? e.g. \342\200\234say dinner is ready\342\200\235."
Lf_reminder:     .asciz "\302\267 \360\237\224\224 Reminder: %s"
Lf_reminder_main: .asciz "\302\267 \360\237\224\224 Reminder: %s"
Lf_reminder_say: .asciz "Reminder: %s"
Ls_city_usage:   .asciz "\302\267 Which city? e.g. \342\200\234my city is Portland, Oregon\342\200\235."
Ls_energy_none:  .asciz "\302\267 No power or energy meters yet. Smart plugs and meters that report watts show up here from SmartThings or Home Assistant."
Ls_hm1:          .asciz "\302\267 Weather: \342\200\234weather\342\200\235, \342\200\234weather tomorrow\342\200\235, \342\200\234will it rain\342\200\235, \342\200\234sunset\342\200\235, \342\200\234air quality\342\200\235; \342\200\234my city is Portland\342\200\235, \342\200\234use celsius\342\200\235."
Ls_hm2:          .asciz "\302\267 Schedules: \342\200\234at 7 pm turn off the TV\342\200\235, \342\200\234in 20 minutes lights off\342\200\235, \342\200\234every weekday at 7 am kitchen on\342\200\235, \342\200\234turn on the porch light at sunset\342\200\235, \342\200\234remind me in 10 minutes to check the oven\342\200\235."
Ls_hm3:          .asciz "\302\267 Rules: \342\200\234when Anna arrives turn on the hall light\342\200\235, \342\200\234when Anna leaves lights off\342\200\235, \342\200\234when the TV turns on dim the living room\342\200\235, \342\200\234notify me when the front door opens\342\200\235. \342\200\234rules\342\200\235 lists them, \342\200\234cancel rule 2\342\200\235."
Ls_hm4:          .asciz "\302\267 Where: \342\200\234this Mac is in the office\342\200\235 (then \342\200\234lights on\342\200\235 means the office), \342\200\234where am i\342\200\235, \342\200\234where are my headphones\342\200\235 (this Mac, other Macs on the mesh, home devices, paired Bluetooth)."
Ls_hm5:          .asciz "\302\267 Trackers: \342\200\234trackers\342\200\235 lists AirTags, SmartTags and Tiles nearby; one that isn't yours and stays 10+ minutes gets a warning. \342\200\234trust trackers\342\200\235 marks yours."
Ls_hm6:          .asciz "\302\267 Out loud and to your phone: \342\200\234say hello\342\200\235, \342\200\234push dinner\342\200\231s ready\342\200\235 (switch on ntfy or Pushover), \342\200\234ifttt key <key>\342\200\235 then \342\200\234trigger movie_night\342\200\235. \342\200\234energy\342\200\235 reads power meters."
Ls_hm8:          .asciz "\302\267 Help: \342\200\234sos\342\200\235 (or long-press the SPIN) tells the mesh and your phone, and where you are with Location on. \342\200\234alerts\342\200\235 checks weather warnings, \342\200\234webhook\342\200\235 shows the address Shortcuts or IFTTT can post to. \342\200\234files\342\200\235 shows a page your phone can browse and upload to; \342\200\234airdrop\342\200\235 sends a file."
Ls_hm7:          .asciz "\302\267 Privacy: Mesh \342\206\222 Mesh Passphrase\342\200\246 encrypts room messages, remote commands and what Macs hear, between Macs that share it."
