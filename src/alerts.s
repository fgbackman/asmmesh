// alerts.s — help that reaches you, with or without the internet.
//
//   SOS                  "sos" (or the SPIN's long-press): straight away to everyone on
//                        the mesh and to your phone; then, with Location on, a second
//                        message saying where you are ("Fred is at 12 Main St, …")
//   Location             CoreLocation for SOS and "where am i"; the address comes from
//                        OpenStreetMap (Nominatim)
//   ntfy                 push to your phone through ntfy.sh — asmmesh makes a long
//                        random topic for you ("ntfy" shows it); SOS goes out urgent
//   Pushover             the same through Pushover ("pushover token …", "pushover user …");
//                        SOS is an emergency alert that repeats until you acknowledge it
//   Weather alerts       the National Weather Service's active alerts for where you are,
//                        every 10 minutes: shown here, pushed, and passed to the mesh
//   Webhook              a tiny web address on this Mac, so Shortcuts on your iPhone,
//                        IFTTT or Zapier can post into a room: POST text to
//                        http://<this Mac>:8787/<secret>/say[/<room>], /notify or /sos
//
// Each is its own switch in Settings, off until you turn it on.

.include "macros.inc"

.set HOOK_PORT,  8787
.set NWS_EVERY,  600
.set NWS_SEEN,   32
.set REQ_MAX,    4095

.data
.p2align 3
_g_al_clm:      .quad 0              // CLLocationManager
_g_al_fix_t:    .quad 0              // when we last knew where we are
_g_al_sos:      .quad 0              // 1: an SOS is waiting for our location
_g_al_sos_t:    .quad 0
_g_al_want:     .quad 0              // 1: "where am i" is waiting
_g_nws_next:    .quad 0              // next weather-alert check (time)
_g_nws_pos:     .quad 0
_g_nws_loud:    .quad 0              // the user asked: say "no alerts" too
_g_hook_fd:     .quad -1
_g_hook_src:    .quad 0
.zerofill __DATA,__bss,_g_al_lat,24,4
.zerofill __DATA,__bss,_g_al_lon,24,4
.zerofill __DATA,__bss,_g_al_addr,160,4
.zerofill __DATA,__bss,_g_al_url,512,4
.zerofill __DATA,__bss,_g_al_body,1100,4
.zerofill __DATA,__bss,_g_al_e1,420,4
.zerofill __DATA,__bss,_g_al_line,560,4
.zerofill __DATA,__bss,_g_al_host,80,4
.zerofill __DATA,__bss,_g_nws_seen,256,4
.zerofill __DATA,__bss,_g_po_token,48,4
.zerofill __DATA,__bss,_g_po_user,48,4
.zerofill __DATA,__bss,_g_po_blob,112,4
.zerofill __DATA,__bss,_g_hook_tok,40,4
.zerofill __DATA,__bss,_g_hook_req,4100,4

.section __TEXT,__const
.p2align 3
Lc_100:     .double 100.0

.text
.p2align 2

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

// size_t _json_esc(char *dst, const char *src, size_t max) — a JSON string's inside
.globl _json_esc
_json_esc:
    sub  x2, x2, #3                   // room for an escape pair and the NUL
    mov  x9, #0
Lje_loop:
    cmp  x9, x2
    b.hs Lje_end
    ldrb w10, [x1], #1
    cbz  w10, Lje_end
    cmp  w10, #'"'
    b.eq Lje_esc
    cmp  w10, #'\\'
    b.eq Lje_esc
    cmp  w10, #0x20
    b.hs Lje_put
    mov  w10, #' '                    // control characters: a space
    b    Lje_put
Lje_esc:
    mov  w11, #'\\'
    strb w11, [x0, x9]
    add  x9, x9, #1
Lje_put:
    strb w10, [x0, x9]
    add  x9, x9, #1
    b    Lje_loop
Lje_end:
    strb wzr, [x0, x9]
    mov  x0, x9
    ret

// void _al_random_hex(char *dst, long nbytes) — 2n random hex digits
.globl _al_random_hex
_al_random_hex:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    add  x0, sp, #96
    mov  x1, x20
    bl   _arc4random_buf
    add  x0, sp, #96
    mov  x1, x20
    mov  x2, x19
    bl   _hex_enc
    LEAVE 32

// long _al_remote(void) -> 1 (and says so) when this is a command from another Mac:
//   secrets (topic, webhook address, keys) and SOS are for this Mac's own user
.globl _al_remote
_al_remote:
    ENTER 0
    ADRL x8, _g_remote_active
    ldr  x0, [x8]
    cbz  x0, Lrm_done
    ADRL x0, Ls_local_only
    bl   _home_say0
    mov  x0, #1
Lrm_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// Pushing to your phone
// ---------------------------------------------------------------------------

// void _push_all(const char *text, long urgent) — every push service that is on
.globl _push_all
_push_all:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, #SVC_NTFY
    bl   _svc_on
    cbz  x0, Lpa_po
    mov  x0, x19
    mov  x1, x20
    bl   _ntfy_json
Lpa_po:
    mov  x0, #SVC_PUSHOVER
    bl   _svc_on
    cbz  x0, Lpa_done
    mov  x0, x19
    mov  x1, x20
    bl   _po_send
Lpa_done:
    LEAVE 0

// void _ntfy_json(const char *text, long urgent) — ntfy.sh, as JSON (priority, tags)
_ntfy_json:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_ntfy_topic
    ldrb w9, [x8]
    cbz  w9, Lnj_done
    ADRL x0, _g_al_e1
    mov  x1, x19
    mov  x2, #400
    bl   _json_esc
    ADRL x9, _g_ntfy_topic
    str  x9, [sp]
    ADRL x9, _g_al_e1
    str  x9, [sp, #8]
    mov  x9, #3
    mov  x10, #5
    cmp  x20, #0
    csel x9, x10, x9, ne
    str  x9, [sp, #16]
    ADRL x9, Ls_tag_bell
    ADRL x10, Ls_tag_sos
    csel x9, x10, x9, ne
    str  x9, [sp, #24]
    ADRL x0, _g_al_body
    mov  x1, #1100
    ADRL x2, Lf_ntfy_json
    bl   _snprintf
    ADRL x0, Ls_POST
    ADRL x1, Ls_ntfy_url
    ADRL x2, _g_al_body
    mov  x3, #0
    ADRL x4, Ls_tag_an
    bl   _http
Lnj_done:
    LEAVE 0

// void _po_send(const char *text, long urgent) — Pushover (urgent: until acknowledged)
_po_send:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_po_token
    ldrb w9, [x8]
    cbz  w9, Lps_done
    ADRL x8, _g_po_user
    ldrb w9, [x8]
    cbz  w9, Lps_done
    ADRL x0, _g_al_e1
    mov  x1, x19
    mov  x2, #400
    bl   _json_esc
    ADRL x9, _g_po_token
    str  x9, [sp]
    ADRL x9, _g_po_user
    str  x9, [sp, #8]
    ADRL x9, _g_al_e1
    str  x9, [sp, #16]
    ADRL x2, Lf_po_json
    ADRL x9, Lf_po_json_sos
    cmp  x20, #0
    csel x2, x9, x2, ne
    ADRL x0, _g_al_body
    mov  x1, #1100
    bl   _snprintf
    ADRL x0, Ls_POST
    ADRL x1, Ls_po_url
    ADRL x2, _g_al_body
    mov  x3, #0
    ADRL x4, Ls_tag_ap
    bl   _http
Lps_done:
    LEAVE 32

// ntfy switched on: make sure there is a topic — long and random, since anyone who
//   knows a topic's name can read it
.globl _al_ntfy_start
_al_ntfy_start:
    ENTER 0
    ADRL x8, _g_ntfy_topic
    ldrb w9, [x8]
    cbnz w9, Lns_show
    ADRL x0, _g_ntfy_topic
    ADRL x1, Ls_topic_pre
    mov  x2, #72
    bl   _strlcpy
    ADRL x0, _g_ntfy_topic
    add  x0, x0, #8                   // after "asmmesh-"
    mov  x1, #10
    bl   _al_random_hex
    ADRL x0, Ls_pref_topic
    ADRL x1, _g_ntfy_topic
    bl   _pref_set
Lns_show:
    ADRL x8, _g_svc_boot              // at launch: quietly
    ldr  x9, [x8]
    cbnz x9, Lns_done
    bl   _h_ntfy_info
Lns_done:
    LEAVE 0

// "ntfy" — the topic and how to subscribe
.globl _h_ntfy_info
_h_ntfy_info:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lni_done
    mov  x0, #SVC_NTFY
    bl   _svc_gate
    cbz  x0, Lni_done
    ADRL x1, _g_ntfy_topic
    ADRL x0, Lf_ntfy_info
    bl   _home_say
Lni_done:
    LEAVE 0

// "ntfy test" / "pushover test"
.globl _h_push_test
_h_push_test:
    ENTER 0
    ADRL x0, Ls_push_test
    mov  x1, #0
    bl   _push_any
    LEAVE 0

// void _push_any(text, urgent) — push, or say why nothing can ("push …", "notify …")
.globl _push_any
_push_any:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, #SVC_NTFY
    bl   _svc_on
    mov  x21, x0
    mov  x0, #SVC_PUSHOVER
    bl   _svc_on
    orr  x21, x21, x0
    cbz  x21, Lpy_none
    mov  x0, x19
    mov  x1, x20
    bl   _push_all
    mov  x1, x19
    ADRL x0, Lf_pushed
    bl   _home_say
    LEAVE 0
Lpy_none:
    ADRL x0, Ls_push_none
    bl   _home_say0
    LEAVE 0

// Pushover switched on: its keys from the Keychain (in the background), then say
//   what's set up (on the main thread)
.globl _al_po_read
_al_po_read:
    ENTER 0
    ADRL x0, Ls_kc_po
    ADRL x1, _g_po_blob
    mov  x2, #112
    bl   _kc_get
    LEAVE 0

.globl _al_po_start
_al_po_start:                         // x0: 1 = quietly (at launch)
    ENTER 0
    mov  x19, x0
    bl   _po_split
    cbnz x19, Laps_done
    bl   _h_pushover
Laps_done:
    LEAVE 0

// void _po_split(void) — "token user" -> the two fields
_po_split:
    ENTER 0
    ADRL x19, _g_po_blob
    ADRL x0, _g_po_token
    strb wzr, [x0]
    ADRL x0, _g_po_user
    strb wzr, [x0]
    mov  x0, x19
    mov  w1, #' '
    bl   _strchr
    cbz  x0, Lpo_done
    strb wzr, [x0]
    add  x20, x0, #1
    ADRL x0, _g_po_token
    mov  x1, x19
    mov  x2, #48
    bl   _strlcpy
    ADRL x0, _g_po_user
    mov  x1, x20
    mov  x2, #48
    bl   _strlcpy
    sub  x0, x20, #1                  // put the blob back as it was
    mov  w9, #' '
    strb w9, [x0]
Lpo_done:
    LEAVE 0

// void _po_save(void) — both fields into the Keychain
_po_save:
    ENTER 0
    ADRL x9, _g_po_token
    str  x9, [sp]
    ADRL x9, _g_po_user
    str  x9, [sp, #8]
    ADRL x0, _g_po_blob
    mov  x1, #112
    ADRL x2, Lf_two
    bl   _snprintf
    ADRL x0, Ls_kc_po
    ADRL x1, _g_po_blob
    bl   _kc_set
    LEAVE 0

// "pushover" — what's set up
.globl _h_pushover
_h_pushover:
    ENTER 0
    mov  x0, #SVC_PUSHOVER
    bl   _svc_gate
    cbz  x0, Lhpo_done
    ADRL x8, _g_po_token
    ldrb w9, [x8]
    ADRL x8, _g_po_user
    ldrb w10, [x8]
    and  w9, w9, w10
    ADRL x0, Ls_po_ready
    cbnz w9, Lhpo_say
    ADRL x0, Ls_po_need
Lhpo_say:
    bl   _home_say0
Lhpo_done:
    LEAVE 0

// "pushover token <app token>" (arg 0) / "pushover user <user key>" (arg 1)
.globl _h_po_key
_h_po_key:
    ENTER 0
    mov  x19, x0
    mov  x20, x2
    bl   _al_remote
    cbnz x0, Lpk2_done
    ldrb w9, [x20]
    cbz  w9, Lpk2_bad
    ADRL x0, _g_po_token
    ADRL x9, _g_po_user
    cmp  x19, #0
    csel x0, x9, x0, ne
    mov  x1, x20
    mov  x2, #48
    bl   _token_clean
    cmp  x0, #20
    b.lo Lpk2_bad
    bl   _po_save
    bl   _h_pushover
    LEAVE 0
Lpk2_bad:
    ADRL x0, Ls_po_bad
    bl   _home_say0
Lpk2_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// Where we are
// ---------------------------------------------------------------------------

// Location switched on: ask macOS once, and get a first fix
.globl _al_loc_start
_al_loc_start:
    ENTER 0
    ADRL x8, _g_al_clm
    ldr  x0, [x8]
    cbnz x0, Lls_have
    CLS  Ls_CLLocationManager
    MSG0 Ls_new
    cbz  x0, Lls_done
    mov  x19, x0
    ADRL x8, _g_al_clm
    str  x19, [x8]
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x19
    MSG1 Ls_setDelegate
    SELX1 Ls_setDesiredAccuracy
    mov  x0, x19
    LDD  d0, Lc_100
    bl   _objc_msgSend
    mov  x0, x19
    MSG0 Ls_requestWhenInUse
Lls_have:
    ADRL x8, _g_al_clm
    ldr  x0, [x8]
    MSG0 Ls_requestLocation
Lls_done:
    LEAVE 0

// - locationManager:didUpdateLocations:
.globl _al_cl_update
_al_cl_update:
    ENTER 32
    mov  x0, x3
    MSG0 Ls_lastObject
    cbz  x0, Lcu_done
    mov  x19, x0
    SELX1 Ls_coordinate
    mov  x0, x19
    bl   _objc_msgSend                // {latitude, longitude} in d0, d1
    str  d1, [sp, #104]
    str  d0, [sp]
    ADRL x0, _g_al_lat
    mov  x1, #24
    ADRL x2, Lf_deg
    bl   _snprintf
    ldr  d1, [sp, #104]
    str  d1, [sp]
    ADRL x0, _g_al_lon
    mov  x1, #24
    ADRL x2, Lf_deg
    bl   _snprintf
    mov  x0, #0
    bl   _time
    ADRL x8, _g_al_fix_t
    str  x0, [x8]
    ADRL x8, _g_al_sos                // an SOS was waiting for this
    ldr  x9, [x8]
    cbz  x9, Lcu_want
    str  xzr, [x8]
    bl   _al_sos_where
Lcu_want:
    ADRL x8, _g_al_want
    ldr  x9, [x8]
    cbz  x9, Lcu_done
    str  xzr, [x8]
    mov  x0, #1
    bl   _al_geocode_why
Lcu_done:
    LEAVE 32

// - locationManager:didFailWithError:
.globl _al_cl_fail
_al_cl_fail:
    ENTER 0
    ADRL x8, _g_al_sos
    ldr  x9, [x8]
    ADRL x10, _g_al_want
    ldr  x11, [x10]
    orr  x9, x9, x11
    cbz  x9, Lcf_done
    str  xzr, [x8]
    str  xzr, [x10]
    ADRL x0, Ls_loc_fail
    bl   _home_say0
Lcf_done:
    LEAVE 0

// "where am i", "location", "my address"
.globl _h_where
_h_where:
    ENTER 0
    mov  x0, #SVC_LOC
    bl   _svc_on
    cbnz x0, Lhw2_on
    bl   _h_where_am_i                // Location off: which room this Mac is in
    LEAVE 0
Lhw2_on:
    bl   _al_fresh
    cbz  x0, Lhw2_ask
    mov  x0, #1
    bl   _al_geocode_why
    LEAVE 0
Lhw2_ask:
    ADRL x8, _g_al_want
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, Ls_locating
    bl   _home_say0
    bl   _al_loc_start
Lhw2_done:
    LEAVE 0

// long _al_fresh(void) -> 1 if we knew where we are within the last 2 minutes
_al_fresh:
    ENTER 0
    ADRL x8, _g_al_fix_t
    ldr  x19, [x8]
    cbz  x19, Laf_no
    mov  x0, #0
    bl   _time
    sub  x0, x0, x19
    cmp  x0, #120
    cset x0, le
    LEAVE 0
Laf_no:
    mov  x0, #0
    LEAVE 0

// void _al_geocode_why(long why) — geocode with the right tag
_al_geocode_why:
    ENTER 0
    mov  x19, x0
    ADRL x3, _g_al_lat
    ADRL x4, _g_al_lon
    ADRL x0, _g_al_url
    mov  x1, #512
    ADRL x2, Lf_nominatim
    bl   _sfmt
    ADRL x4, Ls_tag_ag0
    ADRL x9, Ls_tag_ag1
    cmp  x19, #0
    csel x4, x9, x4, ne
    ADRL x0, Ls_GET
    ADRL x1, _g_al_url
    mov  x2, #0
    mov  x3, #0
    ADRL x5, Ls_ua
    ADRL x6, Ls_ua_val
    bl   _http2
    LEAVE 0

// ---------------------------------------------------------------------------
// SOS
// ---------------------------------------------------------------------------

// void _alerts_sos(void) — tell everyone now; say where as soon as we know
.globl _alerts_sos
_alerts_sos:
    ENTER 0
    ADRL x9, _g_nick
    str  x9, [sp]
    ADRL x0, _g_al_line
    mov  x1, #300
    ADRL x2, Lf_sos_now
    bl   _snprintf
    mov  x0, #0                       // Main: everyone on the mesh
    ADRL x1, _g_al_line
    mov  w2, #0
    bl   _mesh_send_msg
    ADRL x0, _g_al_line
    bl   _chat_line
    ADRL x0, Ls_sos_home
    bl   _home_say0
    ADRL x0, _g_al_line               // your phone, loudly
    mov  x1, #1
    bl   _push_all
    mov  x0, #SVC_LOC
    bl   _svc_on
    cbz  x0, Las_noloc
    mov  x0, #0
    bl   _time
    ADRL x8, _g_al_sos_t
    str  x0, [x8]
    bl   _al_fresh
    cbz  x0, Las_wait
    bl   _al_sos_where
    LEAVE 0
Las_wait:
    ADRL x8, _g_al_sos
    mov  x9, #1
    str  x9, [x8]
    bl   _al_loc_start
    LEAVE 0
Las_noloc:
    ADRL x0, Ls_sos_noloc
    bl   _home_say0
    LEAVE 0

// void _al_sos_where(void) — we know where: the address, then the second message
_al_sos_where:
    ENTER 0
    ADRL x8, _g_al_addr
    strb wzr, [x8]
    mov  x0, #0
    bl   _al_geocode_why              // the answer calls _al_sos_located
    LEAVE 0

// void _al_sos_located(void) — "🆘 Fred is at 12 Main St, Healdsburg · maps.apple.com/?ll=…"
_al_sos_located:
    ENTER 0
    ADRL x9, _g_nick
    str  x9, [sp]
    ADRL x9, _g_al_addr
    ldrb w10, [x9]
    cbnz w10, Lsl_addr
    ADRL x9, Ls_here
Lsl_addr:
    str  x9, [sp, #8]
    ADRL x9, _g_al_lat
    str  x9, [sp, #16]
    ADRL x9, _g_al_lon
    str  x9, [sp, #24]
    ADRL x0, _g_al_line
    mov  x1, #300
    ADRL x2, Lf_sos_where
    bl   _snprintf
    mov  x0, #0
    ADRL x1, _g_al_line
    mov  w2, #0
    bl   _mesh_send_msg
    ADRL x0, _g_al_line
    bl   _chat_line
    ADRL x0, _g_al_line
    mov  x1, #1
    bl   _push_all
    LEAVE 0

// "sos" / "send sos"
.globl _h_sos
_h_sos:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lhs2_done
    bl   _alerts_sos
Lhs2_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// Weather alerts (National Weather Service, US)
// ---------------------------------------------------------------------------

// void _nws_poll(long loud)
.globl _nws_poll
_nws_poll:
    ENTER 64                          // [96] lat  [120] lon
    mov  x19, x0
    ADRL x8, _g_nws_loud
    str  x19, [x8]
    ADRL x8, _g_al_lat                // where: our last fix, else the weather's place
    ldrb w9, [x8]
    cbz  w9, Lnp_pref
    add  x0, sp, #96
    ADRL x1, _g_al_lat
    mov  x2, #24
    bl   _strlcpy
    add  x0, sp, #120
    ADRL x1, _g_al_lon
    mov  x2, #24
    bl   _strlcpy
    b    Lnp_have
Lnp_pref:
    ADRL x0, Ls_pref_lat
    add  x1, sp, #96
    mov  x2, #24
    bl   _pref_get
    ADRL x0, Ls_pref_lon
    add  x1, sp, #120
    mov  x2, #24
    bl   _pref_get
    ldrb w9, [sp, #96]
    cbz  w9, Lnp_nowhere
Lnp_have:
    add  x0, sp, #96                  // four decimals, as the NWS wants
    bl   _atof
    str  d0, [sp, #144]
    add  x0, sp, #120
    bl   _atof
    str  d0, [sp, #8]
    ldr  d0, [sp, #144]
    str  d0, [sp]
    ADRL x0, _g_al_url
    mov  x1, #512
    ADRL x2, Lf_nws_url
    bl   _snprintf
    ADRL x0, Ls_GET
    ADRL x1, _g_al_url
    mov  x2, #0
    mov  x3, #0
    ADRL x4, Ls_tag_aw
    ADRL x5, Ls_ua
    ADRL x6, Ls_ua_val
    bl   _http2
    LEAVE 64
Lnp_nowhere:
    cbz  x19, Lnp_done
    ADRL x0, Ls_nws_nowhere
    bl   _home_say0
Lnp_done:
    LEAVE 64

// "alerts" / "weather alerts"
.globl _h_alerts
_h_alerts:
    ENTER 0
    mov  x0, #SVC_NWS
    bl   _svc_gate
    cbz  x0, Lha_done
    mov  x0, #1
    bl   _nws_poll
Lha_done:
    LEAVE 0

// long _nws_new(const char *id) -> 1 the first time we see this alert
_nws_new:
    ENTER 0
    mov  x19, x0
    mov  x20, #5381                   // djb2
Lnn_hash:
    ldrb w9, [x19], #1
    cbz  w9, Lnn_look
    add  x20, x20, x20, lsl #5
    add  x20, x20, x9
    b    Lnn_hash
Lnn_look:
    orr  x20, x20, #1
    ADRL x8, _g_nws_seen
    mov  x9, #0
Lnn_loop:
    cmp  x9, #NWS_SEEN
    b.hs Lnn_add
    ldr  x10, [x8, x9, lsl #3]
    cmp  x10, x20
    b.eq Lnn_old
    add  x9, x9, #1
    b    Lnn_loop
Lnn_add:
    ADRL x10, _g_nws_pos
    ldr  x11, [x10]
    add  x12, x11, #1
    str  x12, [x10]
    and  x11, x11, #(NWS_SEEN - 1)
    str  x20, [x8, x11, lsl #3]
    mov  x0, #1
    LEAVE 0
Lnn_old:
    mov  x0, #0
    LEAVE 0

// ---------------------------------------------------------------------------
// Answers from the web ('a' tags)
// ---------------------------------------------------------------------------

// void _alerts_response(tag, json, status, error, data)
.globl _alerts_response
_alerts_response:
    ENTER 64
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ldrb w9, [x19, #1]
    cmp  w9, #'w'
    b.eq Lar_nws
    cmp  w9, #'g'
    b.eq Lar_geo
    cmp  w21, #200                    // ntfy, Pushover: only speak up on trouble
    b.eq Lar_done
    ADRL x1, Ls_ntfy
    cmp  w9, #'p'
    b.ne Lar_fail
    ADRL x1, Ls_pushover
Lar_fail:
    mov  x2, x21
    ADRL x0, Lf_push_fail
    bl   _home_say
    b    Lar_done

Lar_geo:                              // Nominatim: road, number, town
    ldrb w22, [x19, #2]               // '0' SOS, '1' where am i
    ADRL x8, _g_al_addr
    strb wzr, [x8]
    cmp  w21, #200
    b.ne Lar_geo_done
    mov  x0, x20
    ADRL x1, Lj_address
    bl   _jget
    mov  x23, x0
    cbz  x23, Lar_geo_disp
    mov  x0, x23
    ADRL x1, Lj_road
    bl   _jget
    bl   _jstr
    cbz  x0, Lar_geo_disp
    mov  x24, x0
    mov  x0, x23
    ADRL x1, Lj_house
    bl   _jget
    bl   _jstr
    ADRL x9, Ls_empty
    cmp  x0, #0
    csel x0, x9, x0, eq
    str  x0, [sp]
    str  x24, [sp, #8]
    ADRL x1, Lj_city
    mov  x0, x23
    bl   _jget
    bl   _jstr
    cbnz x0, Lar_town
    mov  x0, x23
    ADRL x1, Lj_town
    bl   _jget
    bl   _jstr
    cbnz x0, Lar_town
    mov  x0, x23
    ADRL x1, Lj_village
    bl   _jget
    bl   _jstr
    cbnz x0, Lar_town
    ADRL x0, Ls_empty
Lar_town:
    str  x0, [sp, #16]
    ADRL x0, _g_al_addr
    mov  x1, #160
    ADRL x2, Lf_addr
    bl   _snprintf
    ADRL x0, _g_al_addr               // "  Main St, …" when there's no number
    ldrb w9, [x0]
    cmp  w9, #' '
    b.ne Lar_geo_done
    add  x1, x0, #1
    mov  x2, #160
    bl   _memmove
    b    Lar_geo_done
Lar_geo_disp:
    mov  x0, x20
    ADRL x1, Lj_display
    bl   _jget
    bl   _jstr
    cbz  x0, Lar_geo_done
    mov  x1, x0
    ADRL x0, _g_al_addr
    mov  x2, #100
    bl   _strlcpy
Lar_geo_done:
    cmp  w22, #'0'
    b.ne Lar_where
    bl   _al_sos_located
    b    Lar_done
Lar_where:
    ADRL x9, _g_al_addr
    ldrb w10, [x9]
    cbnz w10, Lar_where2
    ADRL x9, Ls_unknown_addr
Lar_where2:
    str  x9, [sp]
    ADRL x9, _g_al_lat
    str  x9, [sp, #8]
    ADRL x9, _g_al_lon
    str  x9, [sp, #16]
    ADRL x0, _g_al_line
    mov  x1, #400
    ADRL x2, Lf_where
    bl   _snprintf
    ADRL x0, _g_al_line
    bl   _home_say0
    b    Lar_done

Lar_nws:                              // {"features":[{"properties":{id,event,headline,severity}}]}
    cmp  w21, #200
    b.eq Lar_nws_ok
    ADRL x8, _g_nws_loud
    ldr  x9, [x8]
    cbz  x9, Lar_done
    mov  x1, x21
    ADRL x0, Lf_nws_fail
    bl   _home_say
    b    Lar_done
Lar_nws_ok:
    mov  x0, x20
    ADRL x1, Lj_features
    bl   _jget
    mov  x23, x0
    bl   _jcount
    mov  x24, x0
    cmp  x24, #10
    mov  x9, #10
    csel x24, x9, x24, hi
    str  xzr, [sp, #96]               // shown
    mov  x22, #0
Lar_nws_loop:
    cmp  x22, x24
    b.hs Lar_nws_end
    mov  x0, x23
    mov  x1, x22
    bl   _jat
    ADRL x1, Lj_properties
    bl   _jget
    str  x0, [sp, #104]
    ADRL x1, Lj_id
    bl   _jget
    bl   _jstr
    cbz  x0, Lar_nws_next
    bl   _nws_new
    str  x0, [sp, #112]               // 1: new
    ADRL x8, _g_nws_loud
    ldr  x9, [x8]
    orr  x9, x9, x0
    cbz  x9, Lar_nws_next             // old and nobody asked: stay quiet
    ldr  x0, [sp, #104]
    ADRL x1, Lj_event
    bl   _jget
    bl   _jstr
    ADRL x9, Ls_alert
    cmp  x0, #0
    csel x0, x9, x0, eq
    str  x0, [sp]
    ldr  x0, [sp, #104]
    ADRL x1, Lj_headline
    bl   _jget
    bl   _jstr
    ADRL x9, Ls_empty
    cmp  x0, #0
    csel x0, x9, x0, eq
    str  x0, [sp, #8]
    ADRL x0, _g_al_line
    mov  x1, #300
    ADRL x2, Lf_nws_line
    bl   _snprintf
    ADRL x0, _g_al_line
    bl   _chat_line
    ldr  x9, [sp, #96]
    add  x9, x9, #1
    str  x9, [sp, #96]
    ldr  x9, [sp, #112]
    cbz  x9, Lar_nws_next             // only new ones go further
    mov  x0, #0                       // Macs without internet hear it too
    ADRL x1, _g_al_line
    mov  w2, #0
    bl   _mesh_send_msg
    ldr  x0, [sp, #104]               // your phone: loudly if it is severe
    ADRL x1, Lj_severity
    bl   _jget
    bl   _jstr
    mov  x1, #0
    cbz  x0, Lar_nws_push
    ldrb w9, [x0]
    cmp  w9, #'E'                     // Extreme
    b.eq Lar_nws_loud
    cmp  w9, #'S'                     // Severe
    b.ne Lar_nws_push
Lar_nws_loud:
    mov  x1, #1
Lar_nws_push:
    ADRL x0, _g_al_line
    bl   _push_all
Lar_nws_next:
    add  x22, x22, #1
    b    Lar_nws_loop
Lar_nws_end:
    ADRL x8, _g_nws_loud
    ldr  x9, [x8]
    cbz  x9, Lar_done
    str  xzr, [x8]
    ldr  x9, [sp, #96]
    cbnz x9, Lar_done
    ADRL x0, Ls_nws_none
    bl   _home_say0
Lar_done:
    LEAVE 64

// Weather alerts switched on: check now
.globl _al_nws_start
_al_nws_start:
    ENTER 0
    mov  x0, #0
    bl   _time
    mov  x9, #NWS_EVERY
    add  x0, x0, x9
    ADRL x8, _g_nws_next
    str  x0, [x8]
    ADRL x8, _g_svc_boot              // switched on now: say "no alerts" too
    ldr  x9, [x8]
    cmp  x9, #0
    cset x0, eq
    bl   _nws_poll
    LEAVE 0

// void _alerts_tick(void) — every second: weather alerts every 10 minutes; an SOS
//   that has waited 30 seconds for a location goes without one
.globl _alerts_tick
_alerts_tick:
    ENTER 0
    mov  x0, #0
    bl   _time
    mov  x19, x0
    ADRL x8, _g_al_sos
    ldr  x9, [x8]
    cbz  x9, Lat_nws
    ADRL x10, _g_al_sos_t
    ldr  x10, [x10]
    sub  x10, x19, x10
    cmp  x10, #30
    b.lt Lat_nws
    str  xzr, [x8]
    ADRL x0, Ls_loc_fail
    bl   _home_say0
Lat_nws:
    mov  x0, #SVC_NWS
    bl   _svc_on
    cbz  x0, Lat_done
    ADRL x8, _g_nws_next
    ldr  x9, [x8]
    cmp  x19, x9
    b.lt Lat_done
    mov  x9, #NWS_EVERY
    add  x9, x19, x9
    str  x9, [x8]
    mov  x0, #0
    bl   _nws_poll
Lat_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// Webhook: http://<this Mac>:8787/<secret>/say[/<room>] | /notify | /sos
// ---------------------------------------------------------------------------

// Webhook switched on: a secret (made once), then listen
.globl _hook_start
_hook_start:
    ENTER 32                          // [96] sockaddr_in
    ADRL x0, Ls_pref_hook
    ADRL x1, _g_hook_tok
    mov  x2, #40
    bl   _pref_get
    ADRL x8, _g_hook_tok
    ldrb w9, [x8]
    cbnz w9, Lhk_listen
    ADRL x0, _g_hook_tok
    mov  x1, #16
    bl   _al_random_hex
    ADRL x0, Ls_pref_hook
    ADRL x1, _g_hook_tok
    bl   _pref_set
Lhk_listen:
    ADRL x8, _g_hook_fd
    ldr  x9, [x8]
    tbz  x9, #63, Lhk_show            // already listening
    mov  w0, #2                       // AF_INET
    mov  w1, #1                       // SOCK_STREAM
    mov  w2, #0
    bl   _socket
    tbnz w0, #31, Lhk_fail
    mov  w19, w0
    mov  w9, #1
    str  w9, [sp, #112]
    mov  w0, w19
    mov  w1, #0xffff                  // SOL_SOCKET
    mov  w2, #4                       // SO_REUSEADDR
    add  x3, sp, #112
    mov  w4, #4
    bl   _setsockopt
    stp  xzr, xzr, [sp, #96]
    mov  w9, #0x0210                  // sin_len 16, sin_family AF_INET
    strh w9, [sp, #96]
    mov  w9, #HOOK_PORT
    rev16 w9, w9
    strh w9, [sp, #98]
    mov  w0, w19
    add  x1, sp, #96
    mov  w2, #16
    bl   _bind
    cbnz w0, Lhk_close
    mov  w0, w19
    mov  w1, #8
    bl   _listen
    cbnz w0, Lhk_close
    mov  w0, w19
    mov  w1, #4                       // F_SETFL
    mov  x9, #4                       // O_NONBLOCK (variadic: on the stack)
    str  x9, [sp]
    bl   _fcntl
    ADRL x8, _g_hook_fd
    sxtw x9, w19
    str  x9, [x8]
    LDGOT x0, __dispatch_source_type_read
    sxtw x1, w19
    mov  x2, #0
    LDGOT x3, __dispatch_main_q
    bl   _dispatch_source_create
    cbz  x0, Lhk_show
    mov  x20, x0
    ADRL x8, _g_hook_src
    str  x20, [x8]
    mov  x0, x20
    ADRL x1, _hook_accept
    bl   _dispatch_source_set_event_handler_f
    mov  x0, x20
    bl   _dispatch_resume
Lhk_show:
    ADRL x8, _g_svc_boot              // at launch: quietly
    ldr  x9, [x8]
    cbnz x9, Lhk_quiet
    bl   _h_webhook
Lhk_quiet:
    LEAVE 32
Lhk_close:
    mov  w0, w19
    bl   _close
Lhk_fail:
    ADRL x0, Ls_hook_fail
    bl   _home_say0
    LEAVE 32

// Webhook switched off: stop listening
.globl _hook_stop
_hook_stop:
    ENTER 0
    ADRL x8, _g_hook_src
    ldr  x0, [x8]
    cbz  x0, Lhs_fd
    str  xzr, [x8]
    bl   _dispatch_source_cancel
Lhs_fd:
    ADRL x8, _g_hook_fd
    ldr  x0, [x8]
    tbnz x0, #63, Lhs_done
    mov  x9, #-1
    str  x9, [x8]
    bl   _close
Lhs_done:
    LEAVE 0

// "webhook" — the address to use
.globl _h_webhook
_h_webhook:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lhw_done
    mov  x0, #SVC_HOOK
    bl   _svc_gate
    cbz  x0, Lhw_done
    ADRL x0, _g_al_host
    mov  x1, #72
    bl   _gethostname
    ADRL x8, _g_al_host
    strb wzr, [x8, #71]
    ADRL x0, _g_al_host               // "CCs-Mac-mini" -> "CCs-Mac-mini.local"
    mov  w1, #'.'
    bl   _strchr
    cbnz x0, Lhw_named
    ADRL x0, _g_al_host
    ADRL x1, Ls_dot_local
    mov  x2, #72
    bl   _strlcat
Lhw_named:
    ADRL x1, _g_al_host
    ADRL x2, _g_hook_tok
    ADRL x3, _g_al_host
    ADRL x0, Lf_hook_info
    bl   _home_say
    ADRL x1, _g_al_host
    ADRL x2, _g_hook_tok
    ADRL x0, Lf_hook_example
    bl   _home_say
Lhw_done:
    LEAVE 0

// "webhook new" — a new secret (the old address stops working)
.globl _h_webhook_new
_h_webhook_new:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lhn2_done
    mov  x0, #SVC_HOOK
    bl   _svc_gate
    cbz  x0, Lhn2_done
    ADRL x0, _g_hook_tok
    mov  x1, #16
    bl   _al_random_hex
    ADRL x0, Ls_pref_hook
    ADRL x1, _g_hook_tok
    bl   _pref_set
    bl   _h_webhook
Lhn2_done:
    LEAVE 0

// void _hook_reply(int fd, const char *text)
_hook_reply:
    ENTER 0
    mov  w19, w0
    mov  x20, x1
    mov  x0, x20
    bl   _strlen
    mov  x2, x0
    mov  w0, w19
    mov  x1, x20
    bl   _write
    LEAVE 0

// void _hook_accept(void *ctx) — someone is knocking: take the connection and answer it
_hook_accept:
    ENTER 0
    ADRL x8, _g_hook_fd
    ldr  x0, [x8]
    tbnz x0, #63, Lhac_done
    mov  x1, #0
    mov  x2, #0
    bl   _accept
    tbnz w0, #31, Lhac_done
    bl   _hook_serve
Lhac_done:
    LEAVE 0

// void _hook_serve(int fd) — one request, answered and closed
_hook_serve:
    ENTER 64                          // [96] timeval  [120] reads so far
    mov  w19, w0
    mov  w0, w19                      // this one blocks, but only briefly (below)
    mov  w1, #4                       // F_SETFL 0 (variadic: on the stack)
    str  xzr, [sp]
    bl   _fcntl
    mov  w9, #1                       // a client that hangs up early mustn't kill the app
    str  w9, [sp, #112]
    mov  w0, w19
    mov  w1, #0xffff
    mov  w2, #0x1022                  // SO_NOSIGPIPE
    add  x3, sp, #112
    mov  w4, #4
    bl   _setsockopt
    mov  x9, #1
    str  x9, [sp, #96]
    str  xzr, [sp, #104]
    str  xzr, [sp, #120]              // reads so far
    mov  w0, w19
    mov  w1, #0xffff
    mov  w2, #0x1006                  // SO_RCVTIMEO
    add  x3, sp, #96
    mov  w4, #16
    bl   _setsockopt
    mov  x20, #0                      // bytes read
    mov  x21, #0                      // body start (0: not yet)
    mov  x22, #0                      // content length
Lha2_read:
    ldr  x9, [sp, #120]
    cmp  x9, #4
    b.hs Lha2_parse
    add  x9, x9, #1
    str  x9, [sp, #120]
    mov  x9, #REQ_MAX
    sub  x2, x9, x20
    cbz  x2, Lha2_parse
    ADRL x1, _g_hook_req
    add  x1, x1, x20
    mov  w0, w19
    bl   _read
    cmp  x0, #0
    b.le Lha2_parse
    add  x20, x20, x0
    ADRL x8, _g_hook_req
    strb wzr, [x8, x20]
    cbnz x21, Lha2_enough
    ADRL x0, _g_hook_req
    ADRL x1, Ls_crlf2
    bl   _strstr
    cbz  x0, Lha2_read
    ADRL x8, _g_hook_req
    sub  x21, x0, x8
    add  x21, x21, #4
    ADRL x0, _g_hook_req
    ADRL x1, Ls_clen
    bl   _strcasestr
    cbz  x0, Lha2_parse
    add  x0, x0, #15
    bl   _atol
    mov  x22, x0
    cmp  x22, #1024
    mov  x9, #1024
    csel x22, x9, x22, hi
Lha2_enough:
    add  x9, x21, x22
    cmp  x20, x9
    b.lo Lha2_read
Lha2_parse:
    ADRL x23, _g_hook_req
    strb wzr, [x23, x20]
    cbz  x21, Lha2_bad
    add  x9, x21, x22                 // the body, as text
    cmp  x9, x20
    csel x9, x20, x9, hi
    strb wzr, [x23, x9]
    mov  x0, x23                      // "POST /<secret>/<what>[/<room>] HTTP/1.1"
    mov  w1, #' '
    bl   _strchr
    cbz  x0, Lha2_bad
    add  x24, x0, #1
    mov  x0, x24
    mov  w1, #' '
    bl   _strchr
    cbz  x0, Lha2_bad
    strb wzr, [x0]
    ldrb w9, [x24]
    cmp  w9, #'/'
    b.ne Lha2_bad
    add  x0, x24, #1
    ADRL x1, _g_hook_tok
    mov  x2, #32
    bl   _strncmp
    cbnz w0, Lha2_denied
    ldrb w9, [x24, #33]
    cmp  w9, #'/'
    b.ne Lha2_denied
    add  x24, x24, #34                // what, then maybe /room
    add  x0, x23, x21                 // the text: trimmed, one line, not too long
    bl   _hook_text
    mov  x0, x24
    ADRL x1, Ls_w_say
    mov  x2, #3
    bl   _strncmp
    cbz  w0, Lha2_say
    mov  x0, x24
    ADRL x1, Ls_w_notify
    bl   _strcmp
    cbz  w0, Lha2_notify
    mov  x0, x24
    ADRL x1, Ls_w_sos
    bl   _strcmp
    cbz  w0, Lha2_sos
    b    Lha2_bad
Lha2_say:
    ADRL x8, _g_al_line
    ldrb w9, [x8]
    cbz  w9, Lha2_empty
    ldrb w9, [x24, #3]                // "/say/<room>": which room
    mov  x0, #0
    cbz  w9, Lha2_room
    cmp  w9, #'/'
    b.ne Lha2_bad
    add  x0, x24, #4
    bl   _hook_room
    tbnz x0, #63, Lha2_noroom
Lha2_room:
    mov  x22, x0
    ADRL x1, _g_al_line
    mov  w2, #0
    bl   _mesh_send_msg
    mov  x0, x22
    mov  x1, #0
    ADRL x2, Lf_hook_said
    ADRL x3, _g_txt
    bl   _room_fmt
    b    Lha2_ok
Lha2_notify:
    ADRL x8, _g_al_line
    ldrb w9, [x8]
    cbz  w9, Lha2_empty
    ADRL x1, _g_al_line
    ADRL x0, Lf_hook_note
    bl   _chat_fmt
    ADRL x0, _g_al_line
    mov  x1, #0
    bl   _push_all
    b    Lha2_ok
Lha2_sos:
    bl   _alerts_sos
Lha2_ok:
    mov  w0, w19
    ADRL x1, Ls_http_ok
    bl   _hook_reply
    b    Lha2_close
Lha2_empty:
    mov  w0, w19
    ADRL x1, Ls_http_empty
    bl   _hook_reply
    b    Lha2_close
Lha2_noroom:
    mov  w0, w19
    ADRL x1, Ls_http_noroom
    bl   _hook_reply
    b    Lha2_close
Lha2_denied:
    mov  w0, w19
    ADRL x1, Ls_http_denied
    bl   _hook_reply
    b    Lha2_close
Lha2_bad:
    mov  w0, w19
    ADRL x1, Ls_http_bad
    bl   _hook_reply
Lha2_close:
    mov  w0, w19
    bl   _close
Lha2_done:
    LEAVE 64

// void _hook_text(const char *body) — trimmed, one line, at most 200 bytes, into _g_al_line
_hook_text:
    ENTER 0
    mov  x1, x0
    ADRL x0, _g_al_line
    mov  x2, #200
    bl   _text_copy_trim
    ADRL x0, _g_al_line
    bl   _utf8_fix
    ADRL x0, _g_al_line
    bl   _sanitize
    LEAVE 0

// long _hook_room(const char *name) -> index of a mesh room with that name, or -1
_hook_room:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
Lhr_loop:
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lhr_none
    ADRL x8, _g_rooms
    add  x21, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, [x21, #R_ID]
    sub  x10, x9, #1                  // never a local room
    cmp  x10, #(LOCAL_ROOMS - 2)
    b.ls Lhr_next
    add  x0, x21, #R_NAME
    mov  x1, x19
    bl   _strcasecmp
    cbz  w0, Lhr_hit
Lhr_next:
    add  x20, x20, #1
    b    Lhr_loop
Lhr_hit:
    mov  x0, x20
    LEAVE 0
Lhr_none:
    mov  x0, #-1
    LEAVE 0

// ---------------------------------------------------------------------------
// Self-tests (asmmesh --selftest)
// ---------------------------------------------------------------------------

// long _t_hook(const char *request) -> the reply's status code, served over a socketpair
_t_hook:
    ENTER 32                          // [96] the two ends
    mov  x19, x0
    mov  w0, #1                       // AF_UNIX
    mov  w1, #1                       // SOCK_STREAM
    mov  w2, #0
    add  x3, sp, #96
    bl   _socketpair
    cbnz w0, Lth_fail
    mov  x0, x19
    bl   _strlen
    mov  x2, x0
    ldr  w0, [sp, #96]
    mov  x1, x19
    bl   _write
    ldr  w0, [sp, #100]
    bl   _hook_serve                  // answers and closes its end
    ldr  w0, [sp, #96]
    ADRL x1, _g_al_body
    mov  x2, #200
    bl   _read
    mov  x20, x0
    ldr  w0, [sp, #96]
    bl   _close
    cmp  x20, #12
    b.lt Lth_fail
    ADRL x0, _g_al_body               // "HTTP/1.1 200 …"
    add  x0, x0, #9
    bl   _atol
    LEAVE 32
Lth_fail:
    mov  x0, #0
    LEAVE 32

// long _alerts_selftest(void) -> failures
.globl _alerts_selftest
_alerts_selftest:
    ENTER 16
    mov  x19, #0
    // 78. text for ntfy / Pushover JSON: quotes and backslashes escaped, no control characters
    ADRL x0, _g_al_e1
    ADRL x1, Lt_json_in
    mov  x2, #400
    bl   _json_esc
    mov  x20, x0
    ADRL x0, _g_al_e1
    ADRL x1, Lt_json_out
    bl   _strcmp
    cmp  w0, #0
    ccmp x20, #16, #0, eq
    cset w1, eq
    ADRL x0, Ln_json
    bl   _t_report
    add  x19, x19, x0
    // 79. a weather alert is news once
    ADRL x0, Lt_nws_id
    bl   _nws_new
    mov  x20, x0
    ADRL x0, Lt_nws_id
    bl   _nws_new
    cmp  x20, #1
    ccmp x0, #0, #0, eq
    cset w1, eq
    ADRL x0, Ln_nws
    bl   _t_report
    add  x19, x19, x0
    // 80-83. the webhook: the secret, what it may do, empty text
    ADRL x0, _g_hook_tok
    ADRL x1, Lt_hook_tok
    mov  x2, #40
    bl   _strlcpy
    ADRL x0, Lt_req_wrong
    bl   _t_hook
    cmp  x0, #403
    cset w1, eq
    ADRL x0, Ln_hook_403
    bl   _t_report
    add  x19, x19, x0
    ADRL x0, Lt_req_what
    bl   _t_hook
    cmp  x0, #400
    cset w1, eq
    ADRL x0, Ln_hook_400
    bl   _t_report
    add  x19, x19, x0
    ADRL x0, Lt_req_empty
    bl   _t_hook
    cmp  x0, #400
    cset w1, eq
    ADRL x0, Ln_hook_empty
    bl   _t_report
    add  x19, x19, x0
    ADRL x0, Lt_req_room
    bl   _t_hook
    cmp  x0, #404
    cset w1, eq
    ADRL x0, Ln_hook_room
    bl   _t_report
    add  x19, x19, x0
    ADRL x0, Lt_req_ok
    bl   _t_hook
    cmp  x0, #200
    cset w1, eq
    ADRL x0, Ln_hook_ok
    bl   _t_report
    add  x19, x19, x0
    ADRL x0, _g_hook_tok
    strb wzr, [x0]
    mov  x0, x19
    LEAVE 16

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lt_json_in:     .asciz "say \"hi\"\\ ok\n"
Lt_json_out:    .asciz "say \\\"hi\\\"\\\\ ok "
Lt_nws_id:      .asciz "urn:oid:2.49.0.1.840.0.test"
Lt_hook_tok:    .asciz "0123456789abcdef0123456789abcdef"
Lt_req_wrong:   .asciz "POST /0123456789abcdef0123456789abcdee/say HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\nhi"
Lt_req_what:    .asciz "POST /0123456789abcdef0123456789abcdef/unlock HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\nhi"
Lt_req_empty:   .asciz "POST /0123456789abcdef0123456789abcdef/say HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
Lt_req_room:    .asciz "POST /0123456789abcdef0123456789abcdef/say/Nowhere HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\nhi"
Lt_req_ok:      .asciz "POST /0123456789abcdef0123456789abcdef/notify HTTP/1.1\r\nHost: x\r\nContent-Length: 11\r\n\r\ntest notice"
Ln_json:        .asciz "78 pushes: quotes, backslashes and newlines are safe in the JSON"
Ln_nws:         .asciz "79 weather alerts: each one is new only once"
Ln_hook_403:    .asciz "80 webhook: the wrong secret is refused (403)"
Ln_hook_400:    .asciz "81 webhook: only say / notify / sos (400)"
Ln_hook_empty:  .asciz "82 webhook: no text, nothing sent (400)"
Ln_hook_room:   .asciz "83 webhook: an unknown room is 404"
Ln_hook_ok:     .asciz "84 webhook: notify with the right secret (200)"
Ls_local_only:  .asciz "\302\267 That one only works on the Mac itself, not from another Mac on the mesh."
Ls_POST:        .asciz "POST"
Ls_GET:         .asciz "GET"
Ls_empty:       .asciz ""
Ls_ntfy_url:    .asciz "https://ntfy.sh"
Ls_po_url:      .asciz "https://api.pushover.net/1/messages.json"
Ls_tag_an:      .asciz "an"
Ls_tag_ap:      .asciz "ap"
Ls_tag_aw:      .asciz "aw"
Ls_tag_ag0:     .asciz "ag0"
Ls_tag_ag1:     .asciz "ag1"
Ls_tag_bell:    .asciz "bell"
Ls_tag_sos:     .asciz "rotating_light"
Ls_ua:          .asciz "User-Agent"
Ls_ua_val:      .asciz "asmmesh/0.8 (Bluetooth mesh messenger for the Mac)"
Lf_ntfy_json:   .asciz "{\"topic\":\"%s\",\"title\":\"asmmesh\",\"message\":\"%s\",\"priority\":%ld,\"tags\":[\"%s\"]}"
Lf_po_json:     .asciz "{\"token\":\"%s\",\"user\":\"%s\",\"title\":\"asmmesh\",\"message\":\"%s\"}"
Lf_po_json_sos: .asciz "{\"token\":\"%s\",\"user\":\"%s\",\"title\":\"asmmesh SOS\",\"message\":\"%s\",\"priority\":2,\"retry\":60,\"expire\":1800,\"sound\":\"siren\"}"
Lf_two:         .asciz "%s %s"
Ls_topic_pre:   .asciz "asmmesh-"
Ls_pref_topic:  .asciz "ntfy_topic"
Ls_pref_lat:    .asciz "loc_lat"
Ls_pref_lon:    .asciz "loc_lon"
Ls_pref_hook:   .asciz "hook_token"
Ls_kc_po:       .asciz "asmmesh.pushover"
Ls_ntfy:        .asciz "ntfy"
Ls_pushover:    .asciz "Pushover"
Lf_push_fail:   .asciz "\302\267 \342\232\240\357\270\217 %s didn\342\200\231t take the push (HTTP %ld)."
Lf_ntfy_info:   .asciz "\302\267 \360\237\223\262 ntfy is on. On your phone, install the ntfy app and subscribe to the topic %s \342\200\224 keep that name private: anyone who knows it can read your alerts. \342\200\234ntfy test\342\200\235 sends one."
Ls_push_test:   .asciz "Test from asmmesh \342\200\224 pushes reach this phone."
Ls_push_usage:  .asciz "\302\267 Say \342\200\234push\342\200\235 and the message, e.g. \342\200\234push dinner is ready\342\200\235."
Ls_push_none:   .asciz "\302\267 Nothing to push with: switch on ntfy or Pushover in Settings (\342\214\230,)."
Lf_pushed:      .asciz "\302\267 \360\237\223\262 Pushed: %s"
Ls_po_ready:    .asciz "\302\267 \360\237\223\262 Pushover is ready. An SOS arrives as an emergency alert that repeats until you acknowledge it. \342\200\234pushover test\342\200\235 sends one."
Ls_po_need:     .asciz "\302\267 \360\237\223\262 Pushover needs two keys from pushover.net: \342\200\234pushover user <your user key>\342\200\235 and \342\200\234pushover token <an application token>\342\200\235 (make an application there called asmmesh). They\342\200\231re kept in the Keychain."
Ls_po_bad:      .asciz "\302\267 That doesn\342\200\231t look like a Pushover key (they\342\200\231re 30 letters and digits)."
Ls_CLLocationManager: .asciz "CLLocationManager"
Ls_new:         .asciz "new"
Ls_setDelegate: .asciz "setDelegate:"
Ls_setDesiredAccuracy: .asciz "setDesiredAccuracy:"
Ls_requestWhenInUse: .asciz "requestWhenInUseAuthorization"
Ls_requestLocation: .asciz "requestLocation"
Ls_lastObject:  .asciz "lastObject"
Ls_coordinate:  .asciz "coordinate"
Lf_deg:         .asciz "%.5f"
Lf_nominatim:   .asciz "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&lat=%s&lon=%s"
Ls_loc_fail:    .asciz "\302\267 \360\237\223\215 Couldn\342\200\231t get this Mac\342\200\231s location. Check System Settings \342\200\272 Privacy & Security \342\200\272 Location Services: it has to be on, and on for asmmesh."
Ls_locating:    .asciz "\302\267 \360\237\223\215 Finding where this Mac is\342\200\246"
Lf_where:       .asciz "\302\267 \360\237\223\215 This Mac is at %s (%s, %s)."
Ls_unknown_addr: .asciz "an address OpenStreetMap doesn\342\200\231t know"
Lf_addr:        .asciz "%s %s, %s"
Ls_here:        .asciz "this spot"
Lf_sos_now:     .asciz "\360\237\206\230 SOS from %s \342\200\224 please check on them."
Lf_sos_where:   .asciz "\360\237\206\230 %s is at %s \302\267 maps.apple.com/?ll=%s,%s"
Ls_sos_home:    .asciz "\302\267 \360\237\206\230 SOS sent to everyone on the mesh, and to your phone if a push service is on."
Ls_sos_noloc:   .asciz "\302\267 Switch on Location in Settings (\342\214\230,) and an SOS also says where you are."
Lf_nws_url:     .asciz "https://api.weather.gov/alerts/active?point=%.4f,%.4f"
Ls_nws_nowhere: .asciz "\302\267 Weather alerts need to know where you are: switch on Location, or say \342\200\234my city is \342\200\246\342\200\235."
Lf_nws_fail:    .asciz "\302\267 The National Weather Service didn\342\200\231t answer (HTTP %ld). It only covers the US."
Ls_nws_none:    .asciz "\302\267 \342\234\205 No weather alerts for where you are right now."
Lf_nws_line:    .asciz "\342\232\240\357\270\217 %s \342\200\224 %s"
Ls_alert:       .asciz "Weather alert"
Lj_features:    .asciz "features"
Lj_properties:  .asciz "properties"
Lj_id:          .asciz "id"
Lj_event:       .asciz "event"
Lj_headline:    .asciz "headline"
Lj_severity:    .asciz "severity"
Lj_address:     .asciz "address"
Lj_road:        .asciz "road"
Lj_house:       .asciz "house_number"
Lj_city:        .asciz "city"
Lj_town:        .asciz "town"
Lj_village:     .asciz "village"
Lj_display:     .asciz "display_name"
Ls_dot_local:   .asciz ".local"
Lf_hook_info:   .asciz "\302\267 \360\237\224\227 Webhook: POST text to http://%s:8787/%s/say (or /say/<room>, /notify, /sos). Keep the address secret; \342\200\234webhook new\342\200\235 changes it. Only Macs and phones on your network can reach %s."
Lf_hook_example: .asciz "\302\267 Example: curl -d 'dinner is ready' http://%s:8787/%s/say"
Ls_hook_fail:   .asciz "\302\267 \342\232\240\357\270\217 The webhook couldn\342\200\231t listen on port 8787 \342\200\224 is something else using it?"
Lf_hook_said:   .asciz "me (webhook): %s"
Lf_hook_note:   .asciz "\302\267 \360\237\224\224 %s"
Ls_crlf2:       .asciz "\r\n\r\n"
Ls_clen:        .asciz "Content-Length:"
Ls_w_say:       .asciz "say"
Ls_w_notify:    .asciz "notify"
Ls_w_sos:       .asciz "sos"
Ls_http_ok:     .asciz "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\nConnection: close\r\n\r\nok\n"
Ls_http_empty:  .asciz "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 18\r\nConnection: close\r\n\r\nsend some text in\n"
Ls_http_noroom: .asciz "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: close\r\n\r\nno such room\n"
Ls_http_denied: .asciz "HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\nContent-Length: 10\r\nConnection: close\r\n\r\nforbidden\n"
Ls_http_bad:    .asciz "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 12\r\nConnection: close\r\n\r\nbad request\n"
