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

.set HB_MAX,  4
.set HB_HOST, 0                       // 64: its address
.set HB_USER, 64                      // 64: the username it gave us
.set HB_ID,   128                     // 24: its bridgeid
.set HB_NAME, 152                     // 32: its name
.set HB_NEW,  184                     // 1: just found, its /api/config not answered yet
.set HB_SIZE, 192

// the current bridge's entry, address, username (x16 and x17 scratch)
.macro HUE_HOST reg
    ADRL \reg, _g_hue_br
    ADRL x16, _g_hue_cur
    ldr  x16, [x16]
    mov  x17, #HB_SIZE
    madd \reg, x16, x17, \reg
.endm
.macro HUE_USER reg
    HUE_HOST \reg
    add  \reg, \reg, #HB_USER
.endm

.data
.p2align 3
_g_hue_cloud_asked: .quad 0
_g_hb_adv:        .quad 0            // CBUUID FE0F
_g_hb_svc:        .quad 0
_g_hb_pow:        .quad 0
_g_hb_bri:        .quad 0
.zerofill __DATA,__bss,_g_hue_br,(HB_MAX * HB_SIZE),4   // the bridges
_g_hue_cur:       .quad 0            // the bridge being talked to
_g_hue_pairing:   .quad 0            // pairing answers still to come
_g_hue_pair_seen: .quad 0            // bit 0 one paired, bit 1 "press the button"
_g_hue_add_br:    .quad 0            // the bridge searching for new lights
_g_hue_full_said: .quad 0
.zerofill __DATA,__bss,_g_hue_url,320,4
.zerofill __DATA,__bss,_g_hue_body,160,4
.zerofill __DATA,__bss,_g_hue_search,160,4   // the last "add hue" search body
_g_hue_tries:     .quad 0            // checks left for the lights a search found

.section __TEXT,__const
.p2align 3
Lc_resolve:   .double 5.0
// request tags, one per bridge: Lhue_tag picks family + 4 * bridge
Lt_hp:  .ascii "hp0\0hp1\0hp2\0hp3\0"
Lt_hl:  .ascii "hl0\0hl1\0hl2\0hl3\0"
Lt_hg:  .ascii "hg0\0hg1\0hg2\0hg3\0"
Lt_hs:  .ascii "hs0\0hs1\0hs2\0hs3\0"
Lt_ha:  .ascii "ha0\0ha1\0ha2\0ha3\0"
Lt_hn:  .ascii "hn0\0hn1\0hn2\0hn3\0"
Lt_hc:  .ascii "hc0\0hc1\0hc2\0hc3\0"

.section __DATA,__const
.p2align 3
Lhue_fields:                          // key base, (offset << 8) | (size / 4)
    .quad Ls_key_host, (HB_HOST << 8) | 16
    .quad Ls_key_user, (HB_USER << 8) | 16
    .quad Ls_key_id,   (HB_ID << 8) | 6
    .quad Ls_key_name, (HB_NAME << 8) | 8
    .quad 0, 0

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
// Bridges: up to HB_MAX, each with its address, the username it gave us, its bridgeid
// (so a bridge seen at a new address is known again) and its name. The first is kept in
// the defaults as hueHost / hueUser / hueId / hueName (as before there could be more),
// the others as hueHost2 ... hueName4. _g_hue_cur is the one being talked to: every
// request's tag ends in its number ("hl1"), so the answer is read as that bridge's.
// ---------------------------------------------------------------------------

// char *Lhue_tag(const char *family) -> its tag for the current bridge (leaf)
Lhue_tag:
    ADRL x9, _g_hue_cur
    ldr  x9, [x9]
    add  x0, x0, x9, lsl #2
    ret

// char *Lhue_ent(long b) -> bridge b's entry (leaf)
Lhue_ent:
    ADRL x9, _g_hue_br
    mov  x10, #HB_SIZE
    madd x0, x0, x10, x9
    ret

// void Lhue_key(const char *base, long b, char *out /*24*/) — "hueHost", "hueHost2"...
Lhue_key:
    ENTER 0
    mov  x19, x1
    mov  x20, x2
    mov  x1, x0
    mov  x0, x20
    mov  x2, #20
    bl   _strlcpy
    cbz  x19, 1f
    add  w9, w19, #'1'
    strb w9, [x20, x0]
    add  x0, x0, #1
    strb wzr, [x20, x0]
1:  LEAVE 0

// void Lhue_prefs(long b, long save) — bridge b's four fields from or into the defaults
Lhue_prefs:
    ENTER 32                          // [96] key (24)
    mov  x19, x0
    mov  x20, x1
    bl   Lhue_ent
    mov  x21, x0
    ADRL x22, Lhue_fields
1:  ldp  x0, x23, [x22], #16          // key base, (offset << 8 | size)
    cbz  x0, 9f
    mov  x1, x19
    add  x2, sp, #96
    bl   Lhue_key
    and  x9, x23, #0xff
    lsr  x10, x23, #8
    add  x1, x21, x10
    add  x0, sp, #96
    cbz  x20, 2f
    bl   _pref_set
    b    1b
2:  lsl  x2, x9, #2                   // sizes are kept / 4 (64 fits a byte that way)
    bl   _pref_get
    b    1b
9:  LEAVE 32

// long Lhue_find(const char *host) -> the bridge at that address, or -1
Lhue_find:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
1:  cmp  x20, #HB_MAX
    b.hs 8f
    mov  x0, x20
    bl   Lhue_ent
    ldrb w9, [x0, #HB_HOST]
    cbz  w9, 2f
    mov  x1, x19
    bl   _strcasecmp
    cbz  w0, 7f
2:  add  x20, x20, #1
    b    1b
7:  mov  x0, x20
    LEAVE 0
8:  mov  x0, #-1
    LEAVE 0

// long Lhue_count(long paired) -> how many bridges are known (paired: and paired)
Lhue_count:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
    mov  x21, #0
1:  cmp  x20, #HB_MAX
    b.hs 9f
    mov  x0, x20
    bl   Lhue_ent
    add  x20, x20, #1
    ldrb w9, [x0, #HB_HOST]
    cbz  w9, 1b
    ldrb w9, [x0, #HB_USER]
    cbz  x19, 2f
    cbz  w9, 1b
2:  add  x21, x21, #1
    b    1b
9:  mov  x0, x21
    LEAVE 0

// char *Lhue_label(long b) -> its name if it has said one, else its address (leaf-ish)
Lhue_label:
    ENTER 0
    bl   Lhue_ent
    add  x9, x0, #HB_NAME
    ldrb w10, [x9]
    cbz  w10, 1f
    mov  x0, x9
1:  LEAVE 0

// void Lhue_get(const char *fmt, const char *family) — GET http://host/api/user/... from
//   the current bridge
Lhue_get:
    ENTER 0
    mov  x19, x0
    mov  x0, x1
    bl   Lhue_tag
    mov  x20, x0
    HUE_HOST x9
    HUE_USER x10
    stp  x9, x10, [sp]
    ADRL x0, _g_hue_url
    mov  x1, #320
    mov  x2, x19
    bl   _snprintf
    ADRL x0, Ls_GET
    ADRL x1, _g_hue_url
    mov  x2, #0
    mov  x3, #0
    mov  x4, x20
    bl   _http
    LEAVE 0

// void Lhue_config(void) — GET http://host/api/config of the current bridge: no username
//   needed; it says the bridge's id and name
Lhue_config:
    ENTER 0
    HUE_HOST x9
    str  x9, [sp]
    ADRL x0, _g_hue_url
    mov  x1, #320
    ADRL x2, Lf_config
    bl   _snprintf
    ADRL x0, Lt_hc
    bl   Lhue_tag
    mov  x4, x0
    ADRL x0, Ls_GET
    ADRL x1, _g_hue_url
    mov  x2, #0
    mov  x3, #0
    bl   _http
    LEAVE 0

// ---------------------------------------------------------------------------
// void _hue_init(void)
// ---------------------------------------------------------------------------
.globl _hue_init
_hue_init:
    ENTER 0
    mov  x19, #0
1:  cmp  x19, #HB_MAX
    b.hs 3f
    mov  x0, x19
    mov  x1, #0
    bl   Lhue_prefs
    mov  x0, x19
    bl   Lhue_ent
    ldrb w9, [x0, #HB_HOST]
    cbz  w9, 2f
    ldrb w9, [x0, #HB_ID]             // saved before ids were kept: ask it
    cbnz w9, 2f
    ADRL x8, _g_hue_cur
    str  x19, [x8]
    bl   Lhue_config
2:  add  x19, x19, #1
    b    1b
3:  bl   _hue_load                    // lan.s browses for _hue._tcp and calls _hue_resolved
    LEAVE 0

// void _hue_tick(long seconds) — 8 s after launch: Philips' discovery service and SSDP,
//   for bridges Bonjour didn't find (a round v1 bridge only answers SSDP)
.globl _hue_tick
_hue_tick:
    ENTER 0
    cmp  x0, #8
    b.ne Lht_done
    mov  x0, #SVC_HUE                 // Hue switched off: don't ask Philips where a bridge is
    bl   _svc_on
    cbz  x0, Lht_done
    ADRL x8, _g_hue_cloud_asked
    ldr  x9, [x8]
    cbnz x9, Lht_done
    mov  x9, #1
    str  x9, [x8]
    bl   _udp_init                    // SSDP; udp.s calls _hue_ssdp with each answer
    ADRL x0, Ls_GET
    ADRL x1, Ls_cloud_url
    mov  x2, #0
    mov  x3, #0
    ADRL x4, Ls_tag_disc
    bl   _http
Lht_done:
    LEAVE 0

// - netServiceDidResolveAddress: (lan.s, for each _hue._tcp service)
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
    mov  x2, #64
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
    bl   _hue_addr_ok
    cbz  x0, Lhr_done
    add  x0, sp, #96
    bl   _hue_set_host
Lhr_done:
    LEAVE 144

// void _hue_set_host(const char *host) — a bridge found (Bonjour, SSDP, Philips' service)
//   or typed: a new address takes a free slot, and its /api/config says whether it is a
//   bridge we know at a new address (Lhx_config) before anything is said
_hue_set_host:
    ENTER 0
    mov  x19, x0
    bl   Lhue_find
    tbz  x0, #63, 9f                  // known: nothing new
    mov  x20, #0
1:  cmp  x20, #HB_MAX
    b.hs 8f
    mov  x0, x20
    bl   Lhue_ent
    ldrb w9, [x0, #HB_HOST]
    cbz  w9, 2f
    add  x20, x20, #1
    b    1b
2:  mov  x21, x0
    mov  x1, #HB_SIZE
    bl   _bzero
    mov  x0, x21
    mov  x1, x19
    mov  x2, #64
    bl   _strlcpy
    mov  x9, #1
    str  x9, [x21, #HB_NEW]
    ADRL x8, _g_hue_cur
    str  x20, [x8]
    bl   Lhue_config
    LEAVE 0
8:  ADRL x8, _g_hue_full_said         // all four slots in use: once
    ldr  x9, [x8]
    cbnz x9, 9f
    mov  x9, #1
    str  x9, [x8]
    ADRL x0, Ls_hue_full
    mov  x1, x19
    bl   _home_say
9:  LEAVE 0

// Lhx_config: {"name":"Philips hue","bridgeid":"001788FFFE123456",...} for the current
//   bridge (x20 the dictionary). Called from _hue_response.
Lhue_config_take:
    ENTER 32                          // [96] was new
    mov  x19, x0
    ADRL x8, _g_hue_cur
    ldr  x20, [x8]
    mov  x0, x20
    bl   Lhue_ent
    mov  x21, x0
    ldr  x9, [x21, #HB_NEW]
    str  x9, [sp, #96]
    str  xzr, [x21, #HB_NEW]
    mov  x0, x19
    ADRL x1, Ls_j_bridgeid
    bl   _jget
    bl   _jstr
    mov  x22, x0
    cbz  x22, 5f
    mov  x23, #0                      // the same bridge in another slot?
1:  cmp  x23, #HB_MAX
    b.hs 4f
    cmp  x23, x20
    b.eq 3f
    mov  x0, x23
    bl   Lhue_ent
    mov  x24, x0
    ldrb w9, [x24, #HB_ID]
    cbz  w9, 3f
    add  x0, x24, #HB_ID
    mov  x1, x22
    bl   _strcasecmp
    cbnz w0, 3f
    ldr  x9, [sp, #96]                // yes: found at a new address
    cbz  x9, 2f
    mov  x0, x24                      //   the old slot takes the new address
    add  x1, x21, #HB_HOST
    mov  x2, #64
    bl   _strlcpy
    mov  x0, x21
    mov  x1, #HB_SIZE
    bl   _bzero
    mov  x0, x23
    mov  x1, #1
    bl   Lhue_prefs
    ADRL x8, _g_hue_cur
    str  x23, [x8]
    ldrb w9, [x24, #HB_USER]
    cbz  w9, 9f
    bl   Lhue_load_cur
    LEAVE 32
2:  ldrb w9, [x21, #HB_USER]          // one bridge in two slots (a saved one checked late):
    cbnz w9, 21f                      //   keep the paired one
    mov  x0, x21
    mov  x1, #HB_SIZE
    bl   _bzero
    mov  x0, x20
    mov  x1, #1
    bl   Lhue_prefs
    bl   _ui_lists_changed
    LEAVE 32
21: ldrb w9, [x24, #HB_USER]
    cbnz w9, 3f
    mov  x0, x24
    mov  x1, #HB_SIZE
    bl   _bzero
    mov  x0, x23
    mov  x1, #1
    bl   Lhue_prefs
    bl   _ui_lists_changed
3:  add  x23, x23, #1
    b    1b
4:  add  x0, x21, #HB_ID
    mov  x1, x22
    mov  x2, #24
    bl   _strlcpy
5:  mov  x0, x19
    ADRL x1, Ls_j_name
    bl   _jget
    bl   _jstr
    cbz  x0, 6f
    mov  x1, x0
    add  x0, x21, #HB_NAME
    mov  x2, #32
    bl   _strlcpy
    add  x0, x21, #HB_NAME
    bl   _utf8_fix
    add  x0, x21, #HB_NAME
    bl   _sanitize
6:  mov  x0, x20
    mov  x1, #1
    bl   Lhue_prefs
    ldr  x9, [sp, #96]
    cbz  x9, 9f
    add  w1, w20, #1                  // new: say so, and how to pair it
    add  x2, x21, #HB_NAME
    ldrb w9, [x2]
    ADRL x10, Ls_hue_unnamed
    cmp  w9, #0
    csel x2, x10, x2, eq
    add  x3, x21, #HB_HOST
    ADRL x0, Ls_found_bridge
    bl   _home_say
    ldrb w9, [x21, #HB_USER]
    cbnz w9, 9f
    ADRL x0, Ls_pair_hint
    bl   _home_say0
    bl   _ui_lists_changed
9:  LEAVE 32

// long _hue_paired(void) -> 1 once a bridge has given us a username
.globl _hue_paired
_hue_paired:
    ENTER 0
    mov  x0, #1
    bl   Lhue_count
    cmp  x0, #0
    cset x0, ne
    LEAVE 0

// void _hue_status(void) — one line on where Hue setup stands
.globl _hue_status
_hue_status:
    ENTER 0
    mov  x0, #0
    bl   Lhue_count
    mov  x19, x0
    mov  x0, #1
    bl   Lhue_count
    mov  x20, x0
    ADRL x0, Ls_hue_none
    cbz  x19, 1f
    ADRL x0, Ls_pair_hint
    cmp  x20, x19
    b.lo 1f
    ADRL x0, Ls_hue_ok
1:  bl   _home_say0
    LEAVE 0

// void _hue_pair(void) — "pair hue": every known bridge not paired yet is asked; the one
//   whose button was pressed answers with a username
.globl _hue_pair
_hue_pair:
    ENTER 0
    mov  x0, #0
    bl   Lhue_count
    cbz  x0, Lhp_nobridge
    ADRL x8, _g_hue_pairing
    str  xzr, [x8]
    ADRL x8, _g_hue_pair_seen
    str  xzr, [x8]
    mov  x19, #0
    mov  x20, #0                      // asked
1:  cmp  x19, #HB_MAX
    b.hs 3f
    mov  x0, x19
    bl   Lhue_ent
    add  x19, x19, #1
    ldrb w9, [x0, #HB_HOST]
    cbz  w9, 1b
    ldrb w9, [x0, #HB_USER]
    cbnz w9, 1b
    sub  x9, x19, #1
    ADRL x8, _g_hue_cur
    str  x9, [x8]
    add  x9, x0, #HB_HOST
    str  x9, [sp]
    ADRL x0, _g_hue_url
    mov  x1, #320
    ADRL x2, Lf_pair
    bl   _snprintf
    ADRL x0, Lt_hp
    bl   Lhue_tag
    mov  x4, x0
    ADRL x0, Ls_POST
    ADRL x1, _g_hue_url
    ADRL x2, Ls_pair_body
    mov  x3, #0
    bl   _http
    add  x20, x20, #1
    b    1b
3:  cbz  x20, Lhp_all
    ADRL x8, _g_hue_pairing
    str  x20, [x8]
    ADRL x0, Ls_pairing
    bl   _home_say0
    LEAVE 0
Lhp_all:
    ADRL x0, Ls_hue_all_paired
    bl   _home_say0
    LEAVE 0
Lhp_nobridge:
    ADRL x0, Ls_hue_none
    bl   _home_say0
    LEAVE 0

// void Lhue_pair_done(long seen) — one pairing answer in (seen: 1 paired, 2 "press the
//   button", 0 other); after the last, if none paired, say to press the button
Lhue_pair_done:
    ENTER 0
    ADRL x8, _g_hue_pair_seen
    ldr  x9, [x8]
    orr  x9, x9, x0
    str  x9, [x8]
    ADRL x8, _g_hue_pairing
    ldr  x10, [x8]
    cbz  x10, 9f
    sub  x10, x10, #1
    str  x10, [x8]
    cbnz x10, 9f
    tbnz x9, #0, 9f
    tbz  x9, #1, 9f
    ADRL x0, Ls_press_button
    bl   _home_say0
9:  LEAVE 0

// void _hue_ssdp(const char *answer, const char *ip) — udp.s, every SSDP answer: a Hue
//   bridge's (the round v1's too) is added if Hue is on
.globl _hue_ssdp
_hue_ssdp:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, #SVC_HUE
    bl   _svc_on
    cbz  x0, 9f
    mov  x0, x19
    bl   _ssdp_is_hue
    cbz  x0, 9f
    mov  x0, x20
    bl   _hue_addr_ok
    cbz  x0, 9f
    mov  x0, x20
    bl   _hue_set_host
9:  LEAVE 0

// "hue bridges" / "hue bridge" — Home: each bridge, numbered, and whether it's paired
.globl _h_hue_bridges
_h_hue_bridges:
    ENTER 0
    mov  x0, #SVC_HUE
    bl   _svc_gate
    cbz  x0, 9f
    mov  x19, #0
    mov  x20, #0                      // listed
1:  cmp  x19, #HB_MAX
    b.hs 5f
    mov  x0, x19
    bl   Lhue_ent
    mov  x21, x0
    add  x19, x19, #1
    ldrb w9, [x21, #HB_HOST]
    cbz  w9, 1b
    add  x20, x20, #1
    mov  x1, x19
    add  x2, x21, #HB_NAME
    ldrb w9, [x2]
    ADRL x10, Ls_hue_unnamed
    cmp  w9, #0
    csel x2, x10, x2, eq
    add  x3, x21, #HB_HOST
    ADRL x0, Lf_br_paired
    ADRL x9, Lf_br_unpaired
    ldrb w10, [x21, #HB_USER]
    cmp  w10, #0
    csel x0, x9, x0, eq
    bl   _home_say
    b    1b
5:  cbnz x20, 6f
    ADRL x0, Ls_hue_none
    bl   _home_say0
    LEAVE 0
6:  ADRL x0, Ls_hue_br_how
    bl   _home_say0
9:  LEAVE 0

// "hue bridge 192.168.1.20" — Home: a bridge by its address (a v1 bridge that wasn't
//   found, one on another subnet, another bridge); "hue bridge" alone lists them
.globl _h_hue_bridge
_h_hue_bridge:
    ENTER 0
    mov  x19, x2
    cbz  x19, 5f
1:  ldrb w9, [x19]
    cmp  w9, #' '
    b.ne 2f
    add  x19, x19, #1
    b    1b
2:  cbz  w9, 5f
    mov  x0, #SVC_HUE
    bl   _svc_gate
    cbz  x0, 9f
    mov  x0, x19
    bl   _hue_addr_ok
    cbz  x0, 4f
    mov  x0, x19
    bl   Lhue_find
    tbz  x0, #63, 3f
    ADRL x0, Ls_hue_checking
    mov  x1, x19
    bl   _home_say
    mov  x0, x19
    bl   _hue_set_host
    LEAVE 0
3:  add  x1, x0, #1
    ADRL x0, Ls_hue_known
    bl   _home_say
    LEAVE 0
4:  ADRL x0, Ls_hue_bad_addr
    bl   _home_say0
    LEAVE 0
5:  bl   _h_hue_bridges
9:  LEAVE 0

// "forget hue bridge 2" — Home: the bridge, its username and its lights and rooms go
.globl _h_hue_forget
_h_hue_forget:
    ENTER 16                          // [96] (_hue_split's id)
    mov  x19, x1
    mov  x0, #SVC_HUE
    bl   _svc_gate
    cbz  x0, 9f
    cbz  x19, 8f
1:  ldrb w9, [x19]                    // the number, after any spaces or "#"
    cmp  w9, #' '
    b.eq 2f
    cmp  w9, #'#'
    b.ne 3f
2:  add  x19, x19, #1
    b    1b
3:  sub  w20, w9, #'1'
    cmp  w20, #(HB_MAX - 1)
    b.hi 8f
    ldrb w9, [x19, #1]
    cbnz w9, 8f
    mov  x0, x20
    bl   Lhue_ent
    mov  x21, x0
    ldrb w9, [x21, #HB_HOST]
    cbz  w9, 8f
    mov  x22, #0                      // its lights and rooms: out of every list
    ADRL x8, _g_dev_count
    ldr  x23, [x8]
4:  cmp  x22, x23
    b.hs 6f
    ADRL x8, _g_devs
    add  x24, x8, x22, lsl #DEV_SHIFT
    add  x22, x22, #1
    ldr  x9, [x24, #D_KIND]
    cmp  x9, #K_HUE_LIGHT
    b.eq 5f
    cmp  x9, #K_HUE_GROUP
    b.ne 4b
5:  add  x0, x24, #D_ID
    add  x1, sp, #96
    bl   _hue_split
    cmp  x0, x20
    b.ne 4b
    str  xzr, [x24, #D_KIND]          // kind 0: no service, never listed or touched
    strb wzr, [x24, #D_ID]
    strb wzr, [x24, #D_NAME]
    b    4b
6:  mov  x0, x21
    mov  x1, #HB_SIZE
    bl   _bzero
    mov  x0, x20
    mov  x1, #1
    bl   Lhue_prefs
    add  x1, x20, #1
    ADRL x0, Ls_hue_forgot
    bl   _home_say
    bl   _ui_lists_changed
    LEAVE 16
8:  ADRL x0, Ls_hue_forget_how
    bl   _home_say0
9:  LEAVE 16

// "add hue light 1A2B3C" / "add hue lights" / "search hue lights" (… "on 2" for the second
//   bridge) — Home: the bridge searches for the bulbs whose serials (printed on them) are
//   given, or for any new light; a minute later we ask what it found (_hue_new_check)
.globl _h_hue_add
_h_hue_add:
    ENTER 16                          // [96] bridge number typed (0: none)
    mov  x19, x1
    mov  x0, #SVC_HUE
    bl   _svc_gate
    cbz  x0, 9f
    mov  x0, #0
    bl   Lhue_count
    cbz  x0, Lha_nobridge
    mov  x0, #1
    bl   Lhue_count
    cbz  x0, Lha_unpaired
    mov  x22, x0                      // paired bridges
    ADRL x0, Ls_empty_h
    cmp  x19, #0
    csel x19, x0, x19, eq
    mov  x0, x19
    ADRL x1, _g_hue_search
    mov  x2, #160
    add  x3, sp, #96
    bl   _hue_serials
    mov  x20, x0
    cmp  x20, #-2
    b.eq Lha_many
    tbnz x20, #63, Lha_bad
    ldr  x21, [sp, #96]               // which bridge: the one typed, else the first paired
    cbz  x21, 2f
    sub  x21, x21, #1
    mov  x0, x21
    bl   Lhue_ent
    ldrb w9, [x0, #HB_USER]
    cbnz w9, 3f
    add  x1, x21, #1
    ADRL x0, Ls_hue_no_such
    bl   _home_say
    LEAVE 16
2:  mov  x0, x21
    bl   Lhue_ent
    ldrb w9, [x0, #HB_USER]
    cbnz w9, 3f
    add  x21, x21, #1
    cmp  x21, #HB_MAX
    b.lo 2b
    b    Lha_unpaired
3:  ADRL x8, _g_hue_cur
    str  x21, [x8]
    ADRL x8, _g_hue_add_br
    str  x21, [x8]
    HUE_HOST x9
    HUE_USER x10
    stp  x9, x10, [sp]
    ADRL x0, _g_hue_url
    mov  x1, #320
    ADRL x2, Lf_lights
    bl   _snprintf
    ADRL x0, Lt_ha
    bl   Lhue_tag
    mov  x4, x0
    ADRL x0, Ls_POST
    ADRL x1, _g_hue_url
    ADRL x2, _g_hue_search
    mov  x3, #0
    bl   _http
    mov  x0, x21
    bl   Lhue_label
    mov  x2, x0
    ADRL x0, Ls_hue_searching_any
    mov  x1, x2
    cbz  x20, 4f
    ADRL x0, Ls_hue_searching
    mov  x1, x20
4:  bl   _home_say
    cmp  x22, #1                      // more than one bridge: how to pick another
    b.ls 5f
    ADRL x0, Ls_hue_add_other
    bl   _home_say0
5:  mov  x9, #3                       // up to three checks, the first in 50 s
    ADRL x8, _g_hue_tries
    str  x9, [x8]
    mov  x0, #50
    bl   Lhue_check_in
    LEAVE 16
Lha_nobridge:
    ADRL x0, Ls_hue_none
    bl   _home_say0
    LEAVE 16
Lha_unpaired:
    ADRL x0, Ls_pair_hint
    bl   _home_say0
    LEAVE 16
Lha_many:
    ADRL x0, Ls_hue_many
    bl   _home_say0
    LEAVE 16
Lha_bad:
    ADRL x0, Ls_hue_bad_serial
    bl   _home_say0
9:  LEAVE 16

// void _hue_add_dialog(id sender) — Mesh › Add Hue Lights…: the serials (or nothing, to
//   search for any new light), then as "add hue light …"
.globl _hue_add_dialog
_hue_add_dialog:
    ENTER 160                         // [96] what was typed (128)
    mov  x0, #1
    bl   Lhue_count
    ADRL x1, Ls_add_info
    cmp  x0, #1
    b.ls 1f
    ADRL x1, Ls_add_info_many
1:  ADRL x0, Ls_add_title
    ADRL x2, Ls_add_ph
    mov  x3, #0
    mov  x4, #0
    add  x5, sp, #96
    mov  x6, #128
    bl   _ask_text
    cbz  x0, 9f                       // cancelled
    mov  x0, #0
    add  x1, sp, #96
    add  x2, sp, #96
    bl   _h_hue_add
9:  LEAVE 160

// void Lhue_check_in(long seconds) — _hue_new_check, that many seconds from now
Lhue_check_in:
    ENTER 0
    MOVI x9, 1000000000
    mul  x1, x0, x9
    mov  x0, #0                       // DISPATCH_TIME_NOW
    bl   _dispatch_time
    LDGOT x1, __dispatch_main_q
    mov  x2, #0
    ADRL x3, _hue_new_check
    bl   _dispatch_after_f
    LEAVE 0

// void _hue_new_check(void *unused) — main queue: what has the search found?
_hue_new_check:
    ENTER 0
    ADRL x8, _g_hue_tries
    ldr  x9, [x8]
    cbz  x9, 9f
    sub  x9, x9, #1
    str  x9, [x8]
    mov  x0, #SVC_HUE                 // switched off meanwhile
    bl   _svc_on
    cbz  x0, 9f
    ADRL x8, _g_hue_add_br
    ldr  x9, [x8]
    ADRL x8, _g_hue_cur
    str  x9, [x8]
    HUE_USER x9
    ldrb w9, [x9]
    cbz  w9, 9f
    ADRL x0, Lf_lights_new
    ADRL x1, Lt_hn
    bl   Lhue_get
9:  LEAVE 0

// void Lhue_new_take(NSDictionary *d) — {"lastscan":"active"|"<time>", "7":{"name":..}}
Lhue_new_take:
    ENTER 160                         // [96] names (160)
    mov  x19, x0
    ADRL x1, Ls_j_lastscan
    bl   _jget
    bl   _jstr
    cbz  x0, 1f
    ADRL x1, Ls_j_active
    bl   _strcmp
    cbnz w0, 1f
    ADRL x8, _g_hue_tries             // still searching: look again in 20 s
    ldr  x9, [x8]
    cbz  x9, 1f
    mov  x0, #20
    bl   Lhue_check_in
    LEAVE 160
1:  ADRL x8, _g_hue_tries
    str  xzr, [x8]
    strb wzr, [sp, #96]
    mov  x0, x19
    bl   _jkeys
    mov  x20, x0
    bl   _jcount
    mov  x21, x0
    mov  x22, #0                      // i
    mov  x23, #0                      // found
2:  cmp  x22, x21
    b.hs 5f
    mov  x0, x20
    mov  x1, x22
    bl   _jat
    mov  x24, x0
    MSG0 Ls_UTF8String
    cbz  x0, 4f
    ADRL x1, Ls_j_lastscan
    bl   _strcmp
    cbz  w0, 4f
    mov  x0, x19
    mov  x2, x24
    MSG1 Ls_objectForKey
    ADRL x1, Ls_j_name
    bl   _jget
    bl   _jstr
    cbz  x0, 4f
    mov  x24, x0
    cbz  x23, 3f
    add  x0, sp, #96
    ADRL x1, Ls_comma_sp
    mov  x2, #160
    bl   _strlcat
3:  add  x0, sp, #96
    mov  x1, x24
    mov  x2, #160
    bl   _strlcat
    add  x23, x23, #1
4:  add  x22, x22, #1
    b    2b
5:  cbz  x23, 6f
    ADRL x0, Ls_hue_new_found
    add  x1, sp, #96
    bl   _home_say
    bl   Lhue_load_cur                // into the lists, and their rooms
    LEAVE 160
6:  ADRL x0, Ls_hue_new_none
    bl   _home_say0
    LEAVE 160

// iPhone (Settings › Hue): bridge b's address ("" if none), name or address, paired
.globl _am_hue_host, _am_hue_name, _am_hue_paired
_am_hue_host:
    cmp  x0, #HB_MAX
    b.hs 1f
    b    Lhue_ent
1:  ADRL x0, Ls_empty_h
    ret
_am_hue_name:
    cmp  x0, #HB_MAX
    b.hs 1f
    ENTER 0
    mov  x19, x0
    bl   Lhue_ent
    ldrb w9, [x0, #HB_HOST]
    cbz  w9, 2f
    mov  x0, x19
    bl   Lhue_label
    LEAVE 0
2:  ADRL x0, Ls_empty_h
    LEAVE 0
1:  ADRL x0, Ls_empty_h
    ret
_am_hue_paired:
    cmp  x0, #HB_MAX
    b.hs 1f
    mov  x15, x30                     // (Lhue_ent: x9, x10 only)
    bl   Lhue_ent
    mov  x30, x15
    ldrb w0, [x0, #HB_USER]
    cmp  w0, #0
    cset x0, ne
    ret
1:  mov  x0, #0
    ret

// void _hue_load(void) — lights and rooms from every paired bridge
.globl _hue_load
_hue_load:
    ENTER 0
    mov  x19, #0
1:  cmp  x19, #HB_MAX
    b.hs 9f
    ADRL x8, _g_hue_cur
    str  x19, [x8]
    add  x19, x19, #1
    bl   Lhue_load_cur
    b    1b
9:  LEAVE 0

// void Lhue_load_cur(void) — the current bridge's lights (its rooms once they're in, so
//   each light can be put in its room), if it's known and paired
Lhue_load_cur:
    ENTER 0
    HUE_HOST x8
    ldrb w9, [x8]
    cbz  w9, 9f
    HUE_USER x8
    ldrb w9, [x8]
    cbz  w9, 9f
    ADRL x0, Lf_lights
    ADRL x1, Lt_hl
    bl   Lhue_get
9:  LEAVE 0

// void _hue_set(long idx, long action, long value)
.globl _hue_set
_hue_set:
    ENTER 32                          // [120] the bridge's own id of it
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    add  x0, x22, #D_ID               // which bridge it's on
    add  x1, sp, #120
    bl   _hue_split
    ADRL x8, _g_hue_cur
    str  x0, [x8]
    HUE_USER x8
    ldrb w9, [x8]
    cbz  w9, Lhz_unpaired
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
    HUE_HOST x9
    str  x9, [sp]
    HUE_USER x9
    str  x9, [sp, #8]
    ldr  x9, [sp, #120]
    str  x9, [sp, #16]
    ldr  x10, [x22, #D_KIND]
    ADRL x2, Lf_light_state
    ADRL x8, Lf_group_action
    cmp  x10, #K_HUE_GROUP
    csel x2, x8, x2, eq
    ADRL x0, _g_hue_url
    mov  x1, #320
    bl   _snprintf
    ADRL x0, Lt_hs
    bl   Lhue_tag
    mov  x4, x0
    ADRL x0, Ls_PUT
    ADRL x1, _g_hue_url
    ADRL x2, _g_hue_body
    mov  x3, #0
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
    ldrb w9, [x19, #2]                // which bridge: the tag's last character
    sub  w9, w9, #'0'
    cmp  w9, #(HB_MAX - 1)
    b.hi 1f
    ADRL x8, _g_hue_cur
    str  x9, [x8]
1:  ldrb w9, [x19, #1]
    cmp  w9, #'d'
    b.eq Lhx_disc
    cbnz x22, Lhx_neterr
    cmp  w9, #'c'
    b.eq Lhx_config
    cmp  w9, #'p'
    b.eq Lhx_pair
    cmp  w9, #'l'
    b.eq Lhx_lists
    cmp  w9, #'g'
    b.eq Lhx_lists
    cmp  w9, #'n'
    b.eq Lhx_new
    b    Lhx_set

Lhx_new:                              // what a search found (an array: an error)
    mov  x0, x20
    bl   _jcount
    cbnz x0, Lhx_set
    mov  x0, x20
    bl   Lhue_new_take
    LEAVE 64

Lhx_neterr:
    cmp  w9, #'c'                     // a bridge checked at launch: quietly, it may be off
    b.ne 1f
    HUE_HOST x23
    ldr  x9, [x23, #HB_NEW]
    cbz  x9, Lhx_done
1:  cmp  w9, #'p'
    b.ne 2f
    mov  x0, #0
    bl   Lhue_pair_done
2:  mov  x0, x22
    bl   _err_cstr
    mov  x2, x0
    HUE_HOST x1
    ADRL x0, Ls_hue_unreach
    bl   _home_say
    ldrb w9, [x19, #1]                // a new address that doesn't answer: not kept
    cmp  w9, #'c'
    b.ne Lhx_done
    HUE_HOST x0
    mov  x1, #HB_SIZE
    bl   _bzero
    LEAVE 64

Lhx_config:
    mov  x0, x20
    bl   Lhue_config_take
    LEAVE 64

Lhx_disc:                             // [{"id":..,"internalipaddress":"192.168.1.20"}, ...]
    cbnz x22, Lhx_done
    mov  x0, x20
    bl   _jcount
    mov  x23, x0
    mov  x24, #0
1:  cmp  x24, x23
    b.hs Lhx_done
    mov  x0, x20
    mov  x1, x24
    bl   _jat
    add  x24, x24, #1
    ADRL x1, Ls_j_ip
    bl   _jget
    bl   _jstr
    cbz  x0, 1b
    mov  x21, x0
    bl   _hue_addr_ok
    cbz  x0, 1b
    mov  x0, x21
    bl   _hue_set_host                // known ones are left alone
    b    1b

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
    HUE_USER x0
    mov  x2, #64
    bl   _strlcpy
    ADRL x8, _g_hue_cur
    ldr  x0, [x8]
    mov  x1, #1
    bl   Lhue_prefs
    ADRL x8, _g_hue_cur
    ldr  x0, [x8]
    bl   Lhue_label
    mov  x1, x0
    ADRL x0, Ls_paired
    bl   _home_say
    mov  x0, #1
    bl   Lhue_pair_done
    bl   Lhue_load_cur
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
    b.ne 1f
    mov  x0, #2                       // "press the button": said once all have answered
    bl   Lhue_pair_done
    LEAVE 64
1:  mov  x0, #0
    bl   Lhue_pair_done
    b    Lhx_err_desc

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
    HUE_USER x8                       // unauthorised: forget the username
    strb wzr, [x8]
    ADRL x8, _g_hue_cur
    ldr  x0, [x8]
    mov  x1, #1
    bl   Lhue_prefs
    ADRL x8, _g_hue_cur
    ldr  x0, [x8]
    bl   Lhue_label
    mov  x1, x0
    ADRL x0, Ls_repair
    bl   _home_say
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
    ADRL x1, Lt_hg
    bl   Lhue_get
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
    ENTER 96                          // [96] keys  [104] n  [112] i  [120] taken  [128] id (64)
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
    ADRL x8, _g_hue_cur               // as the device list knows it ("2:3" on bridge 2)
    ldr  x0, [x8]
    mov  x1, x22
    add  x2, sp, #128
    bl   _hue_devid
    add  x22, sp, #128
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
    LEAVE 96

// void _hue_room_mark(NSDictionary *group, const char *room) — its "lights" are in room
_hue_room_mark:
    ENTER 64                          // [96] a light's id in the device list
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
    ADRL x8, _g_hue_cur
    ldr  x0, [x8]
    add  x2, sp, #96
    bl   _hue_devid
    add  x1, sp, #96
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
    LEAVE 64

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
Ls_key_id: .asciz "hueId"
Ls_key_name: .asciz "hueName"
Lf_config: .asciz "http://%s/api/config"
Ls_j_bridgeid: .asciz "bridgeid"
Ls_hue_full: .asciz "\302\267 Found another Hue Bridge (%s), but four is the most asmmesh keeps. \342\200\234forget hue bridge 2\342\200\235 makes room."
Ls_hue_unnamed: .asciz "Hue Bridge"
Lf_br_paired: .asciz "\302\267 %ld. \342\200\234%s\342\200\235 at %s: connected."
Lf_br_unpaired: .asciz "\302\267 %ld. \342\200\234%s\342\200\235 at %s: not paired: press its button, then \342\200\234pair hue\342\200\235."
Ls_hue_br_how: .asciz "\302\267 \342\200\234add hue light 1A2B3C on 2\342\200\235 adds a bulb to bridge 2; \342\200\234forget hue bridge 2\342\200\235 removes one; \342\200\234hue bridge 192.168.1.20\342\200\235 adds one by its address."
Ls_hue_checking: .asciz "\302\267 Asking %s if it\342\200\231s a Hue Bridge\342\200\246"
Ls_hue_known: .asciz "\302\267 That\342\200\231s Hue Bridge %ld already (\342\200\234hue bridges\342\200\235 lists them)."
Ls_hue_forgot: .asciz "\302\267 Forgot Hue Bridge %ld, and its lights and rooms. If it\342\200\231s still on the network it will be found again, unpaired."
Ls_hue_forget_how: .asciz "\302\267 Which one? Say \342\200\234hue bridges\342\200\235 for their numbers, then e.g. \342\200\234forget hue bridge 2\342\200\235."
Ls_hue_no_such: .asciz "\302\267 There\342\200\231s no paired Hue Bridge %ld. Say \342\200\234hue bridges\342\200\235 to see them."
Ls_hue_add_other: .asciz "\302\267 (For another bridge, add its number: \342\200\234add hue light 1A2B3C on 2\342\200\235.)"
Ls_hue_all_paired: .asciz "\302\267 Every Hue Bridge found is already paired. Another one is found by itself, or say \342\200\234hue bridge\342\200\235 and its address."
Ls_add_title: .asciz "Add Hue Lights"
Ls_add_info: .asciz "Type the serial printed on the bulb or its label (6 letters and digits, up to 10 with spaces between), or \342\200\234any\342\200\235 to search for any new light. The bulb should be on and near the bridge."
Ls_add_info_many: .asciz "Type the serial printed on the bulb or its label (6 letters and digits, up to 10 with spaces between), or \342\200\234any\342\200\235 to search for any new light. More than one bridge: add its number, e.g. \342\200\2341A2B3C on 2\342\200\235 (Home: \342\200\234hue bridges\342\200\235)."
Ls_add_ph: .asciz "1A2B3C"
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
Lf_lights_new:   .asciz "http://%s/api/%s/lights/new"
Ls_tag_add:      .asciz "ha"
Ls_tag_new:      .asciz "hn"
Ls_j_lastscan:   .asciz "lastscan"
Ls_j_active:     .asciz "active"
Ls_empty_h:      .asciz ""
Ls_comma_sp:     .asciz ", "
Ls_hue_searching: .asciz "\302\267 The Hue Bridge is looking for %ld light(s) by serial (on \342\200\234%s\342\200\235). Keep them powered on and near the bridge or another Hue light; I\342\200\231ll say what it finds in about a minute."
Ls_hue_searching_any: .asciz "\302\267 The Hue Bridge \342\200\234%s\342\200\235 is looking for new lights (switch them on). I\342\200\231ll say what it finds in about a minute. A light already paired elsewhere needs its serial: \342\200\234add hue light 1A2B3C\342\200\235."
Ls_hue_new_found: .asciz "\302\267 New on the Hue Bridge: %s."
Ls_hue_new_none: .asciz "\302\267 The Hue Bridge found no new lights. Check the serial (6 letters and digits on the bulb or its label), that the light is on, and that it\342\200\231s near the bridge; switch it off and on 5 times to reset it, then try again."
Ls_hue_bad_serial: .asciz "\302\267 A Hue serial is the 6 letters and digits printed on the bulb or its label, e.g. \342\200\234add hue light 1A2B3C\342\200\235 (several: separate with spaces)."
Ls_hue_many:     .asciz "\302\267 The Hue Bridge looks for at most 10 serials at a time."
Ls_hue_bad_addr: .asciz "\302\267 That doesn\342\200\231t look like an address. Use the bridge\342\200\231s IP, e.g. \342\200\234hue bridge 192.168.1.20\342\200\235 (your router lists it)."
Ls_hue_at:       .asciz "\302\267 Hue Bridge at %s."
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
Ls_found_bridge: .asciz "\302\267 Found Hue Bridge %ld, \342\200\234%s\342\200\235 (%s)."
Ls_pair_hint: .asciz "\302\267 To connect a Hue Bridge: press the round button on top of it, then say or type \342\200\234pair hue\342\200\235 within 30 seconds."
Ls_press_button: .asciz "\302\267 The Hue Bridge wants its button pressed first. Press the round button on top of it, then say \342\200\234pair hue\342\200\235 again."
Ls_pairing: .asciz "\302\267 Asking the Hue Bridge(s) not paired yet\342\200\246"
Ls_paired: .asciz "\302\267 Paired with the Hue Bridge \342\200\234%s\342\200\235. Loading its lights and rooms\342\200\246"
Ls_repair: .asciz "\302\267 The Hue Bridge \342\200\234%s\342\200\235 no longer knows this device. Press its button and say \342\200\234pair hue\342\200\235."
Ls_hue_none:     .asciz "\302\267 No Hue Bridge found on this network yet. Make sure this Mac is on the same Wi-Fi as the bridge, then say \342\200\234refresh\342\200\235."
Ls_hue_ok: .asciz "\302\267 Hue connected (\342\200\234hue bridges\342\200\235 lists them)."
Ls_hue_unreach:  .asciz "\302\267 Can't reach the Hue Bridge at %s: %s"
Ls_hue_said:     .asciz "\302\267 Hue says: %s"
Ls_hue_lights_ready: .asciz "\302\267 Hue: %ld lights ready."
Ls_hue_rooms_ready:  .asciz "\302\267 Hue: %ld rooms and zones ready."
