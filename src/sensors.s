// sensors.s — Bluetooth sensors you don't pair with: thermometers, door and window
// sensors, motion sensors, buttons. They broadcast their readings to anyone
// listening; sens_decode.s reads the bytes, this file keeps track of them.
//
//   sensors                         what's heard nearby, numbered
//   name sensor 2 bedroom           give one a name: it becomes a Home device, so
//                                   "bedroom temperature" and rules can use it
//   when bedroom gets above 78 turn on the fan       (rules.s)
//   when the front door opens turn on the hall light
//   when the doorbell is pressed say someone's at the door
//   batteries                       every battery this Mac can see (below)
//
// A named sensor's number is kept as defaults "sensor_<its CoreBluetooth id>" =
// the name. Nothing is sent anywhere: it only listens. Readings can be faked by
// anyone nearby with a radio, which is why unlocking and opening the garage still
// ask on screen, whatever triggered them.

.include "macros.inc"

.set SN_MAX,     32
.set SN_SHIFT,   8
.set SN_P,       0          // CBPeripheral (retained)
.set SN_KIND,    8          // SK_*
.set SN_SEEN,    16         // last heard
.set SN_R,       24         // an rd block (RD_SIZE): what we know
.set SN_DEV,     136        // its Home device, -1 while it has no name
.set SN_RSSI,    144
.set SN_FLAGS,   152
.set SN_PTIME,   160        // when the last BTHome packet id came
.set SN_LPID,    168        // that packet id
.set SN_UUID,    176        // 40: CoreBluetooth's id for it on this Mac
.set SN_ANAME,   216        // 40: the name it advertises
.set SN_BTIME,   (SN_R + RD_NBTN)   // when buttons last came (sensors without packet ids)
.set SNF_ENC,    1          // BTHome with encryption on: can't read it
.set SNF_SAID,   2          // "a button was pressed" said once for an unnamed one

.macro SNE reg, idx
    ADRL \reg, _g_sns
    add  \reg, \reg, \idx, lsl #SN_SHIFT
.endm

.data
.p2align 3
.globl _g_sn_count
_g_sn_count:    .quad 0
_g_sn_uu:       .quad 0, 0, 0, 0      // CBUUIDs: FCD2 (BTHome), 181A, FD3D, 0D00
_g_air_seen:    .quad 0               // AirPods heard by their broadcast: when
_g_air_rssi:    .quad 0
_g_bat_days:    .quad 0
.zerofill __DATA,__bss,_g_air,48,4    // model, left, right, case, charging, status
.zerofill __DATA,__bss,_g_air_tmp,48,4
.zerofill __DATA,__bss,_g_bat_low,256,4   // 16 x {name hash, day}: low-battery pushes sent
.globl _g_sns
.zerofill __DATA,__bss,_g_sns,8192,4
.zerofill __DATA,__bss,_g_sn_rd,128,4
.zerofill __DATA,__bss,_g_sn_key,96,4
.zerofill __DATA,__bss,_g_sn_val,64,4
.zerofill __DATA,__bss,_g_sn_sum,256,4
.zerofill __DATA,__bss,_g_sn_line,512,4
.zerofill __DATA,__bss,_g_sn_t,48,4
.zerofill __DATA,__bss,_g_sn_age,48,4

.section __TEXT,__const
// the binary sensors that make a Home device "open", "motion", "wet" (object id - 0x0F)
Lb_open:    .byte (0x1A - 0x0F), (0x2D - 0x0F), (0x11 - 0x0F), (0x1B - 0x0F), 0xFF
Lb_motion:  .byte (0x21 - 0x0F), (0x23 - 0x0F), (0x25 - 0x0F), (0x22 - 0x0F), 0xFF
Lb_wet:     .byte (0x20 - 0x0F), 0xFF
Lb_smoke:   .byte (0x29 - 0x0F), 0xFF
.section __DATA,__const
.p2align 3
Lkinds_sn:  .quad Ls_sk_0, Ls_sk_bthome, Ls_sk_govee, Ls_sk_switchbot, Ls_sk_xiaomi
Luu_str:    .quad Ls_u_fcd2, Ls_u_181a, Ls_u_fd3d, Ls_u_0d00

.text
.p2align 2

// ===========================================================================
// Hearing them
// ===========================================================================

// void _sens_seen(CBPeripheral *p, const char *name /*or 0*/, long rssi, NSDictionary *adv)
//   every advertisement that isn't the mesh (main thread)
.globl _sens_seen
_sens_seen:
    ENTER 48                          // [96] mfr bytes [104] mfr length [112] result
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    cbz  x22, Lss_done
    mov  x0, #SVC_SENSORS
    bl   _svc_on
    cbz  x0, Lss_done
    bl   _sn_uuids
    ADRL x0, _g_sn_rd
    bl   _rd_clear
    str  xzr, [sp, #96]
    str  xzr, [sp, #104]
    LDGOT x8, _CBAdvertisementDataManufacturerDataKey
    ldr  x2, [x8]
    mov  x0, x22
    MSG1 Ls_objectForKey
    cbz  x0, Lss_sd
    bl   _sn_nsdata
    str  x0, [sp, #96]
    str  x1, [sp, #104]
Lss_sd:
    LDGOT x8, _CBAdvertisementDataServiceDataKey
    ldr  x2, [x8]
    mov  x0, x22
    MSG1 Ls_objectForKey
    mov  x23, x0
    cbz  x23, Lss_mfr
    ADRL x8, _g_sn_uu                 // BTHome
    ldr  x2, [x8]
    mov  x0, x23
    MSG1 Ls_objectForKey
    cbz  x0, Lss_181a
    bl   _sn_nsdata
    ADRL x2, _g_sn_rd
    bl   _sn_bthome
    cbnz x0, Lss_got
Lss_181a:
    ADRL x8, _g_sn_uu
    ldr  x2, [x8, #8]
    mov  x0, x23
    MSG1 Ls_objectForKey
    cbz  x0, Lss_sb
    bl   _sn_nsdata
    ADRL x2, _g_sn_rd
    bl   _sn_xiaomi
    cbnz x0, Lss_got
Lss_sb:
    ADRL x8, _g_sn_uu
    ldr  x2, [x8, #16]
    mov  x0, x23
    MSG1 Ls_objectForKey
    cbnz x0, Lss_sb_have
    ADRL x8, _g_sn_uu
    ldr  x2, [x8, #24]
    mov  x0, x23
    MSG1 Ls_objectForKey
    cbz  x0, Lss_mfr
Lss_sb_have:
    bl   _sn_nsdata
    ldr  x2, [sp, #96]
    ldr  x3, [sp, #104]
    ADRL x4, _g_sn_rd
    bl   _sn_switchbot
    cbnz x0, Lss_got
Lss_mfr:
    ldr  x0, [sp, #96]
    cbz  x0, Lss_done
    ldr  x1, [sp, #104]
    mov  x2, x20
    ADRL x3, _g_sn_rd
    bl   _sn_govee
    cbnz x0, Lss_got
    ldr  x0, [sp, #96]                // AirPods telling their batteries
    ldr  x1, [sp, #104]
    ADRL x2, _g_air_tmp
    bl   _sn_airpods
    cbz  x0, Lss_done
    mov  x0, x21
    bl   _air_seen
    b    Lss_done
Lss_got:
    str  x0, [sp, #112]
    mov  x0, x19
    mov  x1, x20
    bl   _sn_find_add
    tbnz x0, #63, Lss_done
    mov  x1, x21
    ldr  x2, [sp, #112]
    bl   _sn_apply
Lss_done:
    LEAVE 48

// (bytes, length) of an NSData: x0 bytes, x1 length
_sn_nsdata:
    ENTER 0
    mov  x19, x0
    MSG0 Ls_length
    mov  x20, x0
    mov  x0, x19
    MSG0 Ls_bytes
    mov  x1, x20
    LEAVE 0

// the four service-data UUIDs, made once
_sn_uuids:
    ENTER 0
    ADRL x8, _g_sn_uu
    ldr  x9, [x8]
    cbnz x9, Lsu_done
    mov  x19, #0
Lsu_loop:
    cmp  x19, #4
    b.hs Lsu_done
    ADRL x8, Luu_str
    ldr  x0, [x8, x19, lsl #3]
    bl   _nsstr
    mov  x20, x0
    CLS  Ls_CBUUID
    mov  x2, x20
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    ADRL x8, _g_sn_uu
    str  x0, [x8, x19, lsl #3]
    add  x19, x19, #1
    b    Lsu_loop
Lsu_done:
    LEAVE 0

// long _sn_find_add(CBPeripheral *p, const char *name) -> its index, or -1 (table full)
_sn_find_add:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
Lfa_loop:
    ADRL x8, _g_sn_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lfa_new
    SNE  x22, x21
    ldr  x9, [x22, #SN_P]
    cmp  x9, x19
    b.eq Lfa_found
    add  x21, x21, #1
    b    Lfa_loop
Lfa_found:
    ldrb w9, [x22, #SN_ANAME]         // a name came later (scan response)
    cbnz w9, Lfa_ret
    cbz  x20, Lfa_ret
    add  x0, x22, #SN_ANAME
    mov  x1, x20
    bl   _sn_setname
Lfa_ret:
    mov  x0, x21
    LEAVE 0
Lfa_new:
    cmp  x21, #SN_MAX
    b.hs Lfa_full
    SNE  x22, x21
    mov  x0, x22
    mov  x1, #(1 << SN_SHIFT)
    bl   _bzero
    mov  x9, #-1
    str  x9, [x22, #SN_DEV]
    str  x9, [x22, #(SN_R + RD_PID)]
    str  x9, [x22, #SN_LPID]
    mov  x0, x19
    MSG0 Ls_retain
    str  x0, [x22, #SN_P]
    MSG0 Ls_identifier
    cbz  x0, Lfa_noid
    MSG0 Ls_UUIDString
    cbz  x0, Lfa_noid
    MSG0 Ls_UTF8String
    cbz  x0, Lfa_noid
    mov  x1, x0
    add  x0, x22, #SN_UUID
    mov  x2, #40
    bl   _strlcpy
Lfa_noid:
    cbz  x20, Lfa_count
    add  x0, x22, #SN_ANAME
    mov  x1, x20
    bl   _sn_setname
Lfa_count:
    ADRL x8, _g_sn_count
    add  x9, x21, #1
    str  x9, [x8]
    mov  x0, x21                      // named before? then it's a Home device again
    bl   _sn_key
    ADRL x1, _g_sn_val
    mov  x2, #32
    bl   _pref_get
    ADRL x8, _g_sn_val
    ldrb w9, [x8]
    cbz  w9, Lfa_ret
    mov  x0, x21
    ADRL x1, _g_sn_val
    bl   _sn_register
    b    Lfa_ret
Lfa_full:
    mov  x0, #-1
    LEAVE 0

// void _sn_setname(char *dst /*40*/, const char *name)
_sn_setname:
    ENTER 0
    mov  x19, x0
    mov  x2, #40
    bl   _strlcpy
    mov  x0, x19
    bl   _utf8_fix
    mov  x0, x19
    bl   _sanitize
    LEAVE 0

// char *_sn_key(long idx) -> "sensor_<uuid>" in _g_sn_key
_sn_key:
    ENTER 0
    SNE  x19, x0
    ADRL x0, _g_sn_key
    mov  x1, #96
    ADRL x2, Lf_sn_key
    add  x3, x19, #SN_UUID
    bl   _sfmt
    ADRL x0, _g_sn_key
    LEAVE 0

// void _sn_register(long idx, const char *name) — make it (or rename it as) a Home device
_sn_register:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    SNE  x21, x19
    mov  x0, #K_BLES
    add  x1, x21, #SN_UUID
    mov  x2, x20
    mov  x3, #CAP_STATUS
    bl   _dev_add
    tbnz x0, #63, Lrg_done
    str  x0, [x21, #SN_DEV]
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    str  x19, [x8, #D_SIDX]
    mov  x9, #-1
    str  x9, [x8, #D_LOCKED]
    mov  x0, x19
    bl   _sn_sync_dev
    bl   _ui_lists_changed
Lrg_done:
    LEAVE 0

// long _sn_bin(entry, const uint8 *bits /*0xFF-terminated*/) -> 1 / 0, or -1 never said
_sn_bin:
    ldr  x9, [x0, #(SN_R + RD_BINHAVE)]
    ldr  x10, [x0, #(SN_R + RD_BIN)]
Lbi_loop:
    ldrb w11, [x1], #1
    cmp  w11, #0xFF
    b.eq Lbi_none
    lsr  x12, x9, x11
    tbz  x12, #0, Lbi_loop
    lsr  x12, x10, x11
    and  x0, x12, #1
    ret
Lbi_none:
    mov  x0, #-1
    ret

// void _sn_sync_dev(long idx) — copy what we know into its Home device
_sn_sync_dev:
    ENTER 0
    SNE  x19, x0
    ldr  x9, [x19, #SN_DEV]
    tbnz x9, #63, Lsy_done
    ADRL x8, _g_devs
    add  x20, x8, x9, lsl #DEV_SHIFT
    mov  x0, x19
    ADRL x1, Lb_open
    bl   _sn_bin
    str  x0, [x20, #D_OPEN]
    mov  x0, x19
    ADRL x1, Lb_motion
    bl   _sn_bin
    str  x0, [x20, #D_MOTION]
    mov  x0, x19
    ADRL x1, Lb_wet
    bl   _sn_bin
    str  x0, [x20, #D_WET]
    ldr  x9, [x20, #D_CAPS]
    ldr  x10, [x19, #(SN_R + RD_HAVE)]
    tst  x10, #H_TEMP
    b.eq Lsy_done
    MOVI x10, CAP_TEMP
    orr  x9, x9, x10
    str  x9, [x20, #D_CAPS]
Lsy_done:
    LEAVE 0

// void _sn_apply(long idx, long rssi, long result /*1 read, -1 encrypted*/)
_sn_apply:
    ENTER 16
    mov  x19, x0
    SNE  x20, x19
    str  x1, [x20, #SN_RSSI]
    mov  x21, x2
    mov  x0, #0
    bl   _time
    mov  x22, x0
    str  x22, [x20, #SN_SEEN]
    ADRL x23, _g_sn_rd
    ldr  x9, [x23, #RD_KIND]
    cbz  x9, Lap2_kind
    str  x9, [x20, #SN_KIND]
Lap2_kind:
    tbz  x21, #63, Lap2_read
    mov  x9, #SK_BTHOME
    str  x9, [x20, #SN_KIND]
    ldr  x9, [x20, #SN_FLAGS]
    orr  x9, x9, #SNF_ENC
    str  x9, [x20, #SN_FLAGS]
    LEAVE 16
Lap2_read:
    ldr  x9, [x23, #RD_PID]           // the same BTHome packet again (they repeat): skip
    tbnz x9, #63, Lap2_merge
    ldr  x10, [x20, #SN_LPID]
    cmp  x9, x10
    b.ne Lap2_newpid
    ldr  x10, [x20, #SN_PTIME]
    sub  x10, x22, x10
    cmp  x10, #4
    b.le Lap2_done
Lap2_newpid:
    str  x9, [x20, #SN_LPID]
    str  x22, [x20, #SN_PTIME]
Lap2_merge:
    ldr  x9, [x23, #RD_HAVE]          // numbers: whichever came
    mov  x10, #0
Lap2_num:
    cmp  x10, #7
    b.hs Lap2_bin
    lsr  x11, x9, x10
    tbz  x11, #0, Lap2_num_next
    add  x12, x10, #1                 // RD_TEMP + 8k
    lsl  x12, x12, #3
    ldr  x13, [x23, x12]
    add  x12, x12, #SN_R
    str  x13, [x20, x12]
Lap2_num_next:
    add  x10, x10, #1
    b    Lap2_num
Lap2_bin:
    ldr  x10, [x20, #(SN_R + RD_HAVE)]
    orr  x10, x10, x9
    str  x10, [x20, #(SN_R + RD_HAVE)]
    ldr  x9, [x23, #RD_BINHAVE]
    ldr  x10, [x20, #(SN_R + RD_BIN)]
    bic  x10, x10, x9
    ldr  x11, [x23, #RD_BIN]
    and  x11, x11, x9
    orr  x10, x10, x11
    str  x10, [x20, #(SN_R + RD_BIN)]
    ldr  x10, [x20, #(SN_R + RD_BINHAVE)]
    orr  x10, x10, x9
    str  x10, [x20, #(SN_R + RD_BINHAVE)]
    ldr  x9, [x20, #SN_DEV]
    tbnz x9, #63, Lap2_buttons
    mov  x0, x19
    bl   _sn_sync_dev
    mov  x0, #SVC_RULES
    bl   _svc_on
    cbz  x0, Lap2_buttons
    bl   _rules_sens_eval
Lap2_buttons:
    ldr  x24, [x23, #RD_NBTN]
    cbz  x24, Lap2_done
    ldr  x9, [x23, #RD_PID]           // no packet id: the same press repeats for a
    tbz  x9, #63, Lap2_btn_go         //   second or so, so take one per 2 seconds
    ldr  x10, [x20, #SN_BTIME]
    sub  x10, x22, x10
    cmp  x10, #2
    b.lt Lap2_done
    str  x22, [x20, #SN_BTIME]
Lap2_btn_go:
    mov  x21, #0
Lap2_btn:
    cmp  x21, x24
    b.hs Lap2_done
    add  x9, x23, #RD_BTN
    ldrb w9, [x9, x21]
    cbz  w9, Lap2_btn_next
    str  x9, [sp, #96]
    mov  x0, x19
    add  x1, x21, #1
    mov  x2, x9
    bl   _sn_button
Lap2_btn_next:
    add  x21, x21, #1
    b    Lap2_btn
Lap2_done:
    LEAVE 16

// void _sn_button(long idx, long button, long event) — a press: run its rules, or say it
_sn_button:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    SNE  x22, x19
    cmp  x21, #0x80                   // "hold" counts as a long press
    mov  x9, #4
    csel x21, x9, x21, eq
    ldr  x23, [x22, #SN_DEV]
    tbnz x23, #63, Lbn_unnamed
    mov  x0, #SVC_RULES
    bl   _svc_on
    cbz  x0, Lbn_say
    mov  x0, x23
    mov  x1, x20
    mov  x2, x21
    bl   _rules_button
    cbnz x0, Lbn_done
Lbn_say:
    mov  x0, x21
    bl   _sn_event_word
    mov  x3, x0
    ADRL x8, _g_devs
    add  x1, x8, x23, lsl #DEV_SHIFT
    add  x1, x1, #D_NAME
    mov  x2, x20
    ADRL x0, Lf_sn_press
    bl   _home_say
    b    Lbn_done
Lbn_unnamed:
    ldr  x9, [x22, #SN_FLAGS]
    tbnz x9, #1, Lbn_done             // said once already this run
    orr  x9, x9, #SNF_SAID
    str  x9, [x22, #SN_FLAGS]
    mov  x0, x19
    bl   _sn_label
    mov  x1, x0
    add  x2, x19, #1
    ADRL x0, Lf_sn_press_new
    bl   _home_say
Lbn_done:
    LEAVE 16

// const char *_sn_event_word(long event)
_sn_event_word:
    ADRL x1, Ls_ev_press
    cmp  x0, #2
    b.ne 1f
    ADRL x1, Ls_ev_double
1:  cmp  x0, #3
    b.ne 2f
    ADRL x1, Ls_ev_triple
2:  cmp  x0, #4
    b.lo 3f
    ADRL x1, Ls_ev_long
3:  mov  x0, x1
    ret

// ===========================================================================
// For the rest of the app
// ===========================================================================

// long _sens_value(long dev, long q /*1 temperature, 2 humidity, 3 battery, 4 moisture,
//   5 light*/) -> x0 value (hundredths; battery in %), x1 1 if known
.globl _sens_value
_sens_value:
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x8, #D_KIND]
    cmp  x9, #K_BLES
    b.ne Lsv_none
    ldr  x9, [x8, #D_SIDX]
    ADRL x10, _g_sn_count
    ldr  x10, [x10]
    cmp  x9, x10
    b.hs Lsv_none
    ADRL x10, _g_sns
    add  x10, x10, x9, lsl #SN_SHIFT
    ldr  x11, [x10, #(SN_R + RD_HAVE)]
    cmp  x1, #1
    b.eq Lsv_temp
    cmp  x1, #2
    b.eq Lsv_hum
    cmp  x1, #3
    b.eq Lsv_batt
    cmp  x1, #4
    b.eq Lsv_moist
    cmp  x1, #5
    b.eq Lsv_lux
    b    Lsv_none
Lsv_temp:
    tbz  x11, #0, Lsv_none
    ldr  x0, [x10, #(SN_R + RD_TEMP)]
    b    Lsv_yes
Lsv_hum:
    tbz  x11, #1, Lsv_none
    ldr  x0, [x10, #(SN_R + RD_HUM)]
    b    Lsv_yes
Lsv_batt:
    tbz  x11, #2, Lsv_none
    ldr  x0, [x10, #(SN_R + RD_BATT)]
    b    Lsv_yes
Lsv_lux:
    tbz  x11, #3, Lsv_none
    ldr  x0, [x10, #(SN_R + RD_LUX)]
    b    Lsv_yes
Lsv_moist:
    tbz  x11, #4, Lsv_none
    ldr  x0, [x10, #(SN_R + RD_MOIST)]
Lsv_yes:
    mov  x1, #1
    ret
Lsv_none:
    mov  x0, #0
    mov  x1, #0
    ret

// long _sens_dev_by_name(const char *name) -> a named sensor called that (or
//   containing it), else any device called that, else -1
.globl _sens_dev_by_name
_sens_dev_by_name:
    ENTER 0
    mov  x19, x0
    mov  x21, #0                      // pass 0 exact, pass 1 containing
Lsd_pass:
    mov  x20, #0
Lsd_loop:
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lsd_next_pass
    ADRL x8, _g_devs
    add  x22, x8, x20, lsl #DEV_SHIFT
    ldr  x9, [x22, #D_KIND]
    cmp  x9, #K_BLES
    b.ne Lsd_next
    add  x0, x22, #D_NAME
    mov  x1, x19
    cbnz x21, Lsd_contains
    bl   _strcasecmp
    cbz  w0, Lsd_found
    b    Lsd_next
Lsd_contains:
    bl   _strcasestr
    cbnz x0, Lsd_found
Lsd_next:
    add  x20, x20, #1
    b    Lsd_loop
Lsd_next_pass:
    add  x21, x21, #1
    cmp  x21, #2
    b.lo Lsd_pass
    mov  x0, x19
    bl   _dev_by_name
    LEAVE 0
Lsd_found:
    mov  x0, x20
    LEAVE 0

// long _sens_subj_q(char *subject) -> 1 temperature (default), 2 humidity,
//   4 soil moisture, 5 light; takes those words out of the subject
.globl _sens_subj_q
_sens_subj_q:
    ENTER 0
    mov  x19, x0
    mov  x20, #1
    ADRL x1, Ls_w_humidity
    bl   _sn_cut_word
    cbz  x0, Lsq_moist
    mov  x20, #2
Lsq_moist:
    mov  x0, x19
    ADRL x1, Ls_w_moisture
    bl   _sn_cut_word
    cbz  x0, Lsq_light
    mov  x20, #4
Lsq_light:
    mov  x0, x19
    ADRL x1, Ls_w_light
    bl   _sn_cut_word
    cbz  x0, Lsq_temp
    mov  x20, #5
Lsq_temp:
    mov  x0, x19
    ADRL x1, Ls_w_temperature
    bl   _sn_cut_word
    mov  x0, x19
    ADRL x1, Ls_w_temp
    bl   _sn_cut_word
    mov  x0, x19                      // "the … in the bedroom" -> "bedroom"
    bl   _sn_tidy_subj
    mov  x0, x20
    LEAVE 0

// long _sens_subj_btn(char *subject) -> button number (0 any); takes "button N" out
.globl _sens_subj_btn
_sens_subj_btn:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
    ADRL x1, Ls_w_button_sp
    bl   _strstr
    cbz  x0, Lsb2_tidy
    mov  x21, x0
    ldrb w9, [x21, #7]                // "button N"
    sub  w9, w9, #'1'
    cmp  w9, #3
    b.hi Lsb2_word
    add  x20, x9, #1
    add  x0, x21, #8                  // cut "button N"
    mov  x1, x21
    bl   _sn_shift_left
    b    Lsb2_tidy
Lsb2_word:
Lsb2_tidy:
    mov  x0, x19
    ADRL x1, Ls_w_button
    bl   _sn_cut_word
    mov  x0, x19
    bl   _sn_tidy_subj
    mov  x0, x20
    LEAVE 0

// void _sn_shift_left(char *from, char *to) — move the rest of the string down
_sn_shift_left:
    ldrb w9, [x0], #1
    strb w9, [x1], #1
    cbnz w9, _sn_shift_left
    ret

// long _sn_cut_word(char *s, const char *word) -> 1 if the whole word was there and
//   is now gone
_sn_cut_word:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x20
    bl   _strlen
    mov  x21, x0
    mov  x22, x19
Lcw_find:
    mov  x0, x22
    mov  x1, x20
    bl   _strstr
    cbz  x0, Lcw_no
    mov  x23, x0
    cmp  x23, x19                     // a whole word: a space or the edge on both sides
    b.eq Lcw_left_ok
    ldurb w9, [x23, #-1]
    cmp  w9, #' '
    b.ne Lcw_again
Lcw_left_ok:
    ldrb w9, [x23, x21]
    cbz  w9, Lcw_cut
    cmp  w9, #' '
    b.eq Lcw_cut
    cmp  w9, #'s'                     // "buttons"
    b.ne Lcw_again
Lcw_again:
    add  x22, x23, #1
    b    Lcw_find
Lcw_cut:
    add  x0, x23, x21
    mov  x1, x23
    bl   _sn_shift_left
    mov  x0, #1
    LEAVE 0
Lcw_no:
    mov  x0, #0
    LEAVE 0

// void _sn_tidy_subj(char *s) — drop leading "the", "in the", "on the", "of the",
//   "in", "on", "of" and spaces; trailing spaces
_sn_tidy_subj:
    ENTER 0
    mov  x19, x0
Lts_again:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.ne Lts_words
    add  x0, x19, #1
    mov  x1, x19
    bl   _sn_shift_left
    b    Lts_again
Lts_words:
    ADRL x20, Lts_prefixes
Lts_p:
    ldr  x1, [x20], #8
    cbz  x1, Lts_tail
    mov  x21, x1
    mov  x0, x1
    bl   _strlen
    mov  x22, x0
    mov  x0, x19
    mov  x1, x21
    mov  x2, x22
    bl   _strncmp
    cbnz w0, Lts_p
    add  x0, x19, x22
    mov  x1, x19
    bl   _sn_shift_left
    b    Lts_again
Lts_tail:
    mov  x0, x19
    bl   _strlen
Lts_t:
    cbz  x0, Lts_done
    sub  x9, x0, #1
    ldrb w10, [x19, x9]
    cmp  w10, #' '
    b.ne Lts_done
    strb wzr, [x19, x9]
    mov  x0, x9
    b    Lts_t
Lts_done:
    LEAVE 0

// long _sens_parse_thr(const char *p, long q) -> x0 the text after the number and its
//   unit (0 if no number), x1 the threshold in hundredths (degrees C for temperature)
.globl _sens_parse_thr
_sens_parse_thr:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
Lpt_sp:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.ne Lpt_num
    add  x19, x19, #1
    b    Lpt_sp
Lpt_num:
    mov  x21, #0                      // negative?
    cmp  w9, #'-'
    b.ne Lpt_dig
    mov  x21, #1
    add  x19, x19, #1
Lpt_dig:
    ldrb w9, [x19]
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi Lpt_none
    mov  x22, #0                      // in hundredths
Lpt_int:
    ldrb w9, [x19]
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi Lpt_frac
    mov  x10, #10
    mul  x22, x22, x10
    add  x22, x22, x9
    add  x19, x19, #1
    b    Lpt_int
Lpt_frac:
    mov  x10, #100
    mul  x22, x22, x10
    ldrb w9, [x19]
    cmp  w9, #'.'
    b.ne Lpt_unit
    add  x19, x19, #1
    ldrb w9, [x19]
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi Lpt_unit
    mov  x10, #10
    madd x22, x9, x10, x22
    add  x19, x19, #1
Lpt_skipd:
    ldrb w9, [x19]
    sub  w9, w9, #'0'
    cmp  w9, #9
    b.hi Lpt_unit
    add  x19, x19, #1
    b    Lpt_skipd
Lpt_unit:
    cbz  x21, Lpt_units
    neg  x22, x22
Lpt_units:                            // degrees, °, °f, °c, f, c, %, percent
    mov  x23, #0                      // said Celsius / Fahrenheit: 1 C, 2 F
Lpt_u:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.eq Lpt_u_next
    cmp  w9, #'%'
    b.eq Lpt_u_next
    cmp  w9, #','
    b.eq Lpt_u_next
    cmp  w9, #0xC2                    // °
    b.ne Lpt_u_words
    ldrb w9, [x19, #1]
    cmp  w9, #0xB0
    b.ne Lpt_end
    add  x19, x19, #1
    b    Lpt_u_next
Lpt_u_words:
    ADRL x24, Lpt_unit_words
Lpt_uw:
    ldp  x1, x9, [x24], #16
    cbz  x1, Lpt_end
    str  x9, [sp, #96]
    mov  x0, x19
    bl   _sn_word_at
    cbz  x0, Lpt_uw
    ldr  x9, [sp, #96]
    cbz  x9, Lpt_uw_skip
    mov  x23, x9
Lpt_uw_skip:
    sub  x19, x0, #1
Lpt_u_next:
    add  x19, x19, #1
    b    Lpt_u
Lpt_end:
    cmp  x20, #1                      // temperature: Fahrenheit unless Celsius
    b.ne Lpt_ret
    cmp  x23, #1
    b.eq Lpt_ret
    cmp  x23, #2
    b.eq Lpt_f
    bl   _celsius
    cbnz x0, Lpt_ret
Lpt_f:                                // (F - 32) * 5 / 9, in hundredths
    mov  x9, #3200
    sub  x22, x22, x9
    mov  x9, #5
    mul  x22, x22, x9
    mov  x9, #9
    sdiv x22, x22, x9
Lpt_ret:
    mov  x0, x19
    mov  x1, x22
    LEAVE 16
Lpt_none:
    mov  x0, #0
    mov  x1, #0
    LEAVE 16

// const char *_sn_word_at(const char *p, const char *word) -> after the word if p
//   starts with it as a whole word, else 0
_sn_word_at:
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
    cbnz w0, Lwa_no
    ldrb w9, [x19, x21]
    cbz  w9, Lwa_yes
    cmp  w9, #' '
    b.eq Lwa_yes
    cmp  w9, #','
    b.ne Lwa_no
Lwa_yes:
    add  x0, x19, x21
    LEAVE 0
Lwa_no:
    mov  x0, #0
    LEAVE 0

// char *_sens_thr_text(long q, long above, long thr, char *buf /*48*/) -> "above 78°F"
.globl _sens_thr_text
_sens_thr_text:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ADRL x23, Ls_w_above
    cbnz x20, Ltt_val
    ADRL x23, Ls_w_below
Ltt_val:
    cmp  x19, #1
    b.ne Ltt_pct
    mov  x0, x21
    ADRL x1, _g_sn_t
    bl   _sn_fmt_temp
    mov  x0, x22
    mov  x1, #48
    ADRL x2, Lf_two
    mov  x3, x23
    ADRL x4, _g_sn_t
    bl   _sfmt
    b    Ltt_done
Ltt_pct:
    mov  x0, x22
    mov  x1, #48
    ADRL x2, Lf_thr_pct
    mov  x3, x23
    mov  x9, #100
    sdiv x4, x21, x9
    cmp  x19, #5
    b.ne Ltt_fmt
    ADRL x2, Lf_thr_lux
Ltt_fmt:
    bl   _sfmt
Ltt_done:
    mov  x0, x22
    LEAVE 16

// ===========================================================================
// Words
// ===========================================================================

// char *_sn_fmt_temp(long hundredths_c, char *buf /*48*/) -> "72.4°F" (or °C)
_sn_fmt_temp:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _celsius
    mov  x21, x0
    cbnz x21, Lft_c
    mov  x9, #9                       // tenths of a degree F, rounded
    mul  x19, x19, x9
    mov  x9, #16000
    add  x19, x19, x9
    mov  x9, #50
    cmp  x19, #0
    mov  x10, #25
    mov  x11, #-25
    csel x10, x10, x11, ge
    add  x19, x19, x10
    sdiv x19, x19, x9
    b    Lft_fmt
Lft_c:
    mov  x9, #10                      // tenths of a degree C, rounded
    cmp  x19, #0
    mov  x10, #5
    mov  x11, #-5
    csel x10, x10, x11, ge
    add  x19, x19, x10
    sdiv x19, x19, x9
Lft_fmt:
    ADRL x3, Ls_empty
    cmp  x19, #0
    b.ge Lft_pos
    ADRL x3, Ls_minus
    neg  x19, x19
Lft_pos:
    mov  x9, #10
    udiv x4, x19, x9
    msub x5, x4, x9, x19
    ADRL x6, Ls_deg_f
    cbz  x21, Lft_out
    ADRL x6, Ls_deg_c
Lft_out:
    mov  x0, x20
    mov  x1, #48
    ADRL x2, Lf_temp
    bl   _sfmt
    mov  x0, x20
    LEAVE 0

// const char *_sn_label(long idx) — its name, what it calls itself, or what it is
_sn_label:
    ENTER 0
    SNE  x19, x0
    ldr  x9, [x19, #SN_DEV]
    tbnz x9, #63, Llb_adv
    ADRL x8, _g_devs
    add  x0, x8, x9, lsl #DEV_SHIFT
    add  x0, x0, #D_NAME
    LEAVE 0
Llb_adv:
    add  x0, x19, #SN_ANAME
    ldrb w9, [x0]
    cbnz w9, Llb_ret
    ldr  x9, [x19, #SN_KIND]
    cmp  x9, #4
    csel x9, xzr, x9, hi
    ADRL x8, Lkinds_sn
    ldr  x0, [x8, x9, lsl #3]
Llb_ret:
    LEAVE 0

// void _sn_cat(const char *piece) — append to _g_sn_sum with " · " between pieces
_sn_cat:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_sn_sum
    ldrb w9, [x8]
    cbz  w9, Lsc_add
    ADRL x0, _g_sn_sum
    ADRL x1, Ls_dot
    mov  x2, #256
    bl   _strlcat
Lsc_add:
    ADRL x0, _g_sn_sum
    mov  x1, x19
    mov  x2, #256
    bl   _strlcat
    LEAVE 0

// char *_sn_summary(long idx) -> "72.4°F · 45% humidity · battery 80%" in _g_sn_sum
_sn_summary:
    ENTER 32
    SNE  x19, x0
    ADRL x8, _g_sn_sum
    strb wzr, [x8]
    ldr  x9, [x19, #SN_FLAGS]
    tbz  x9, #0, Lsm_nums
    ldr  x9, [x19, #(SN_R + RD_HAVE)]
    cbnz x9, Lsm_nums
    ADRL x0, Ls_sm_enc
    bl   _sn_cat
    b    Lsm_done
Lsm_nums:
    ldr  x20, [x19, #(SN_R + RD_HAVE)]
    tbz  x20, #0, Lsm_hum
    ldr  x0, [x19, #(SN_R + RD_TEMP)]
    ADRL x1, _g_sn_t
    bl   _sn_fmt_temp
    bl   _sn_cat
Lsm_hum:
    tbz  x20, #1, Lsm_moist
    ldr  x3, [x19, #(SN_R + RD_HUM)]
    ADRL x2, Lf_sm_hum
    bl   _sn_cat_pct
Lsm_moist:
    tbz  x20, #4, Lsm_lux
    ldr  x3, [x19, #(SN_R + RD_MOIST)]
    ADRL x2, Lf_sm_moist
    bl   _sn_cat_pct
Lsm_lux:
    tbz  x20, #3, Lsm_press
    ldr  x3, [x19, #(SN_R + RD_LUX)]
    ADRL x2, Lf_sm_lux
    bl   _sn_cat_pct
Lsm_press:
    tbz  x20, #5, Lsm_co2
    ldr  x3, [x19, #(SN_R + RD_PRESS)]
    ADRL x2, Lf_sm_press
    bl   _sn_cat_pct
Lsm_co2:
    tbz  x20, #6, Lsm_bins
    ldr  x3, [x19, #(SN_R + RD_CO2)]
    mov  x9, #100
    mul  x3, x3, x9
    ADRL x2, Lf_sm_co2
    bl   _sn_cat_pct
Lsm_bins:
    mov  x0, x19
    ADRL x1, Lb_open
    bl   _sn_bin
    tbnz x0, #63, Lsm_motion
    ADRL x8, Ls_sm_closed
    ADRL x9, Ls_sm_open
    cmp  x0, #0
    csel x0, x8, x9, eq
    bl   _sn_cat
Lsm_motion:
    mov  x0, x19
    ADRL x1, Lb_motion
    bl   _sn_bin
    tbnz x0, #63, Lsm_wet
    ADRL x8, Ls_sm_still
    ADRL x9, Ls_sm_motion
    cmp  x0, #0
    csel x0, x8, x9, eq
    bl   _sn_cat
Lsm_wet:
    mov  x0, x19
    ADRL x1, Lb_wet
    bl   _sn_bin
    tbnz x0, #63, Lsm_smoke
    ADRL x8, Ls_sm_dry
    ADRL x9, Ls_sm_wet
    cmp  x0, #0
    csel x0, x8, x9, eq
    bl   _sn_cat
Lsm_smoke:
    mov  x0, x19
    ADRL x1, Lb_smoke
    bl   _sn_bin
    tbnz x0, #63, Lsm_button
    ADRL x8, Ls_sm_nosmoke
    ADRL x9, Ls_sm_smoke
    cmp  x0, #0
    csel x0, x8, x9, eq
    bl   _sn_cat
Lsm_button:
    ADRL x8, _g_sn_sum                // nothing but presses: a button
    ldrb w9, [x8]
    cbnz w9, Lsm_batt
    ADRL x0, Ls_sm_button
    bl   _sn_cat
Lsm_batt:
    tbz  x20, #2, Lsm_done
    ldr  x3, [x19, #(SN_R + RD_BATT)]
    mov  x9, #100
    mul  x3, x3, x9
    ADRL x2, Lf_sm_batt
    bl   _sn_cat_pct
Lsm_done:
    ADRL x0, _g_sn_sum
    LEAVE 32

// _sn_cat_pct: x2 format with one %ld, x3 value in hundredths (rounded to whole)
_sn_cat_pct:
    ENTER 0
    mov  x19, x2
    add  x3, x3, #50
    mov  x9, #100
    sdiv x3, x3, x9
    ADRL x0, _g_sn_t
    mov  x1, #48
    mov  x2, x19
    bl   _sfmt
    ADRL x0, _g_sn_t
    bl   _sn_cat
    LEAVE 0

// char *_sn_age(long idx) -> "just now", "3 min ago", "2 h ago" in _g_sn_age
_sn_age:
    ENTER 0
    SNE  x19, x0
    mov  x0, #0
    bl   _time
    ldr  x9, [x19, #SN_SEEN]
    sub  x3, x0, x9
    ADRL x2, Ls_just_now
    cmp  x3, #60
    b.lt Lag_fmt
    mov  x9, #60
    sdiv x3, x3, x9
    ADRL x2, Lf_min_ago
    cmp  x3, #120
    b.lt Lag_fmt
    sdiv x3, x3, x9
    ADRL x2, Lf_h_ago
Lag_fmt:
    ADRL x0, _g_sn_age
    mov  x1, #48
    bl   _sfmt
    ADRL x0, _g_sn_age
    LEAVE 0

// long _sens_info(long i, long k) — for the iPhone app's list: 0 label, 1 reading,
//   2 age (strings; reading and age are in shared buffers, copy before the next call),
//   3 kind (string), 4 named (0/1), 5 signal dBm
.globl _sens_info
_sens_info:
    ENTER 0
    mov  x19, x0
    SNE  x20, x19
    cmp  x1, #0
    b.ne 1f
    mov  x0, x19
    bl   _sn_label
    LEAVE 0
1:  cmp  x1, #1
    b.ne 2f
    mov  x0, x19
    bl   _sn_summary
    LEAVE 0
2:  cmp  x1, #2
    b.ne 3f
    mov  x0, x19
    bl   _sn_age
    LEAVE 0
3:  cmp  x1, #3
    b.ne 4f
    ldr  x9, [x20, #SN_KIND]
    cmp  x9, #4
    csel x9, xzr, x9, hi
    ADRL x8, Lkinds_sn
    ldr  x0, [x8, x9, lsl #3]
    LEAVE 0
4:  cmp  x1, #4
    b.ne 5f
    ldr  x9, [x20, #SN_DEV]
    mvn  x9, x9
    lsr  x0, x9, #63                  // 1 when SN_DEV >= 0
    LEAVE 0
5:  ldr  x0, [x20, #SN_RSSI]
    LEAVE 0

// ===========================================================================
// Commands
// ===========================================================================

// "sensors"
.globl _h_sensors
_h_sensors:
    ENTER 0
    mov  x0, #SVC_SENSORS
    bl   _svc_gate
    cbz  x0, Lhs_done
    ADRL x8, _g_sn_count
    ldr  x20, [x8]
    cbnz x20, Lhs_some
    ADRL x0, Ls_sn_none
    bl   _home_say0
    b    Lhs_done
Lhs_some:
    ADRL x0, Lf_sn_head
    mov  x1, x20
    bl   _home_say
    mov  x19, #0
Lhs_loop:
    cmp  x19, x20
    b.hs Lhs_foot
    mov  x0, x19
    bl   _sn_summary
    mov  x0, x19
    bl   _sn_age
    mov  x0, x19
    bl   _sn_label
    mov  x21, x0
    SNE  x22, x19
    ldr  x9, [x22, #SN_KIND]
    cmp  x9, #4
    csel x9, xzr, x9, hi
    ADRL x8, Lkinds_sn
    ldr  x23, [x8, x9, lsl #3]
    ldr  x9, [x22, #SN_DEV]
    ADRL x2, Lf_sn_named
    tbz  x9, #63, Lhs_fmt
    ADRL x2, Lf_sn_unnamed
Lhs_fmt:
    ADRL x0, _g_sn_line
    mov  x1, #512
    add  x3, x19, #1
    mov  x4, x21
    mov  x5, x23
    ADRL x6, _g_sn_sum
    ADRL x7, _g_sn_age
    bl   _sfmt6
    ADRL x0, _g_sn_line
    bl   _home_say0
    add  x19, x19, #1
    b    Lhs_loop
Lhs_foot:
    ADRL x0, Ls_sn_foot
    bl   _home_say0
Lhs_done:
    LEAVE 0

// long _sfmt6(dst, max, fmt, a, b, c, d, e) — snprintf with five arguments (x3..x7)
_sfmt6:
    sub  sp, sp, #64
    stp  x29, x30, [sp, #48]
    add  x29, sp, #48
    stp  x3, x4, [sp]
    stp  x5, x6, [sp, #16]
    str  x7, [sp, #32]
    bl   _snprintf
    ldp  x29, x30, [sp, #48]
    add  sp, sp, #64
    ret

// "name sensor 2 bedroom" (also "name sensor 2 as bedroom")
.globl _h_sens_name
_h_sens_name:
    ENTER 16
    mov  x19, x1                      // lowercase rest
    mov  x20, x2                      // as typed
    mov  x0, #SVC_SENSORS
    bl   _svc_gate
    cbz  x0, Lhn2_done
    mov  x0, x19
    bl   _atol
    mov  x21, x0
    ADRL x8, _g_sn_count
    ldr  x9, [x8]
    cmp  x21, #1
    b.lt Lhn2_which
    cmp  x21, x9
    b.gt Lhn2_which
    mov  x22, #0                      // past the number and spaces
Lhn2_skipnum:
    ldrb w9, [x19, x22]
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.hi Lhn2_skipsp
    add  x22, x22, #1
    b    Lhn2_skipnum
Lhn2_skipsp:
    ldrb w9, [x19, x22]
    cmp  w9, #' '
    b.ne Lhn2_as
    add  x22, x22, #1
    b    Lhn2_skipsp
Lhn2_as:
    add  x0, x19, x22
    ADRL x1, Ls_w_as
    bl   _sn_word_at
    cbz  x0, Lhn2_to
    sub  x22, x0, x19
    b    Lhn2_skipsp
Lhn2_to:
    add  x0, x19, x22
    ADRL x1, Ls_w_to
    bl   _sn_word_at
    cbz  x0, Lhn2_name
    sub  x22, x0, x19
    b    Lhn2_skipsp
Lhn2_name:
    ADRL x0, _g_sn_val
    add  x1, x20, x22
    mov  x2, #32
    bl   _strlcpy
    ADRL x0, _g_sn_val
    bl   _sn_tidy_name
    ADRL x8, _g_sn_val
    ldrb w9, [x8]
    cbz  w9, Lhn2_which
    sub  x23, x21, #1
    mov  x0, x23
    bl   _sn_key
    ADRL x1, _g_sn_val
    bl   _pref_set
    mov  x0, x23
    ADRL x1, _g_sn_val
    bl   _sn_register
    ADRL x0, Lf_sn_named_ok
    mov  x1, x21
    ADRL x2, _g_sn_val
    ADRL x3, _g_sn_val
    bl   _home_say
    b    Lhn2_done
Lhn2_which:
    ADRL x0, Ls_sn_name_help
    bl   _home_say0
Lhn2_done:
    LEAVE 16

// void _sn_tidy_name(char *s) — no trailing spaces or full stop, no quotes
_sn_tidy_name:
    ENTER 0
    mov  x19, x0
    bl   _strlen
Ltn_loop:
    cbz  x0, Ltn_done
    sub  x9, x0, #1
    ldrb w10, [x19, x9]
    cmp  w10, #' '
    b.eq Ltn_cut
    cmp  w10, #'.'
    b.eq Ltn_cut
    cmp  w10, #'"'
    b.eq Ltn_cut
    b    Ltn_done
Ltn_cut:
    strb wzr, [x19, x9]
    mov  x0, x9
    b    Ltn_loop
Ltn_done:
    ldrb w9, [x19]
    cmp  w9, #'"'
    b.ne Ltn_ret
    add  x0, x19, #1
    mov  x1, x19
    bl   _sn_shift_left
Ltn_ret:
    LEAVE 0

// void _sens_status(long dev) — "Bedroom: 72.4°F · 45% humidity · battery 80% (just now)"
.globl _sens_status
_sens_status:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_devs
    add  x20, x8, x19, lsl #DEV_SHIFT
    ldr  x21, [x20, #D_SIDX]
    ADRL x8, _g_sn_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lst_none
    mov  x0, x21
    bl   _sn_summary
    mov  x0, x21
    bl   _sn_age
    ADRL x0, Lf_sn_status
    add  x1, x20, #D_NAME
    ADRL x2, _g_sn_sum
    ADRL x3, _g_sn_age
    bl   _home_say
    LEAVE 0
Lst_none:
    ADRL x0, Lf_sn_quiet
    add  x1, x20, #D_NAME
    bl   _home_say
    LEAVE 0

// ===========================================================================
// Batteries
// ===========================================================================

// void _air_seen(long rssi) — AirPods (or Beats) said their batteries: keep the
//   strongest recent one (yours are usually the closest)
_air_seen:
    ENTER 0
    mov  x19, x0
    mov  x0, #0
    bl   _time
    mov  x20, x0
    ADRL x8, _g_air_seen
    ldr  x9, [x8]
    sub  x10, x20, x9
    cmp  x10, #30                     // a quieter one only replaces it after 30 s
    b.gt Lai_take
    ADRL x8, _g_air_rssi
    ldr  x9, [x8]
    cmp  x19, x9
    b.lt Lai_done
Lai_take:
    ADRL x8, _g_air_seen
    str  x20, [x8]
    ADRL x8, _g_air_rssi
    str  x19, [x8]
    ADRL x0, _g_air
    ADRL x1, _g_air_tmp
    mov  x2, #48
    bl   _memcpy
Lai_done:
    LEAVE 0

// const char *_air_model(long model)
_air_model:
    ADRL x9, Lair_models
Lam_loop:
    ldp  x10, x11, [x9], #16
    cbz  x10, Lam_none
    cmp  x10, x0
    b.ne Lam_loop
    mov  x0, x11
    ret
Lam_none:
    ADRL x0, Ls_air_unknown
    ret

// "batteries": the background part reads IOKit / IOBluetooth, then _bat_show
.globl _h_batteries
_h_batteries:
    ENTER 0
    mov  x0, #SVC_SENSORS
    bl   _svc_gate
    cbz  x0, Lhb_done
    ADRL x0, Ls_bat_looking
    bl   _home_say0
    mov  x0, #0
    bl   _bat_start
Lhb_done:
    LEAVE 0

// void _bat_start(long quiet)
_bat_start:
    ENTER 0
    mov  x19, x0
    mov  x0, #4096
    bl   _malloc
    cbz  x0, Lbs_done
    mov  x20, x0
    str  x19, [x20]                   // [0] quiet  [8] lines
    strb wzr, [x20, #8]
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, x20
    ADRL x2, _bat_worker
    bl   _dispatch_async_f
Lbs_done:
    LEAVE 0

// void _bat_line(ctx, const char *name, long pct, long charging) — "name\tpct\tcharging\n"
_bat_line:
    ENTER 128
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    cbz  x20, Lbl_done
    ldrb w9, [x20]
    cbz  w9, Lbl_done
    tbnz x21, #63, Lbl_done
    cmp  x21, #100
    b.hi Lbl_done
    add  x0, x19, #8                  // already listed under that name?
    mov  x1, x20
    bl   _strstr
    cbnz x0, Lbl_done
    add  x0, sp, #96
    mov  x1, #128
    ADRL x2, Lf_bat_rec
    mov  x3, x20
    mov  x4, x21
    mov  x5, x22
    bl   _sfmt
    add  x0, x19, #8
    add  x1, sp, #96
    mov  x2, #4088
    bl   _strlcat
Lbl_done:
    LEAVE 128

// void _bat_worker(ctx) — background
_bat_worker:
    ENTER 48
    mov  x19, x0
    // ---- this Mac (a laptop) ----
    bl   _IOPSCopyPowerSourcesInfo
    mov  x20, x0
    cbz  x20, Lbw_hid
    bl   _IOPSCopyPowerSourcesList
    mov  x21, x0
    cbz  x21, Lbw_info_rel
    mov  x0, x21
    MSG0 Ls_count
    mov  x22, x0
    mov  x23, #0
Lbw_ps:
    cmp  x23, x22
    b.hs Lbw_ps_done
    mov  x0, x21
    mov  x2, x23
    MSG1 Ls_objectAtIndex
    mov  x1, x0
    mov  x0, x20
    bl   _IOPSGetPowerSourceDescription
    cbz  x0, Lbw_ps_next
    mov  x24, x0
    ADRL x0, Ls_ps_type
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_objectForKey
    cbz  x0, Lbw_ps_next
    str  x0, [sp, #96]
    ADRL x0, Ls_ps_internal
    bl   _nsstr
    mov  x2, x0
    ldr  x0, [sp, #96]
    MSG1 Ls_isEqualToString
    tst  w0, #0xff
    b.eq Lbw_ps_next
    ADRL x0, Ls_ps_cur
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_objectForKey
    cbz  x0, Lbw_ps_next
    MSG0 Ls_integerValue
    str  x0, [sp, #104]
    ADRL x0, Ls_ps_max
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_objectForKey
    mov  x9, #100
    cbz  x0, Lbw_ps_max
    MSG0 Ls_integerValue
    mov  x9, x0
Lbw_ps_max:
    cmp  x9, #1
    b.lt Lbw_ps_next
    ldr  x10, [sp, #104]
    mov  x11, #100
    mul  x10, x10, x11
    udiv x10, x10, x9
    str  x10, [sp, #104]
    ADRL x0, Ls_ps_charging
    bl   _nsstr
    mov  x2, x0
    mov  x0, x24
    MSG1 Ls_objectForKey
    mov  x3, #0
    cbz  x0, Lbw_ps_line
    MSG0 Ls_boolValue
    and  x3, x0, #0xff
Lbw_ps_line:
    mov  x0, x19
    ADRL x1, Ls_this_mac
    ldr  x2, [sp, #104]
    bl   _bat_line
Lbw_ps_next:
    add  x23, x23, #1
    b    Lbw_ps
Lbw_ps_done:
    mov  x0, x21
    bl   _CFRelease
Lbw_info_rel:
    mov  x0, x20
    bl   _CFRelease
Lbw_hid:
    // ---- Magic Keyboard / Mouse / Trackpad and other Apple accessories ----
    ADRL x0, Ls_hid_class
    bl   _IOServiceMatching
    cbz  x0, Lbw_bt
    mov  x1, x0
    mov  x0, #0                       // kIOMainPortDefault
    add  x2, sp, #112
    str  wzr, [sp, #112]
    bl   _IOServiceGetMatchingServices
    cbnz w0, Lbw_bt
    ldr  w20, [sp, #112]
Lbw_hid_loop:
    mov  w0, w20
    bl   _IOIteratorNext
    cbz  w0, Lbw_hid_done
    mov  w21, w0
    mov  w0, w21
    ADRL x1, Ls_hid_batt
    bl   _sn_ioprop
    mov  x22, #-1
    cbz  x0, Lbw_hid_rel
    mov  x23, x0
    MSG0 Ls_integerValue
    mov  x22, x0
    mov  x0, x23
    bl   _CFRelease
    mov  w0, w21
    ADRL x1, Ls_hid_product
    bl   _sn_ioprop
    cbz  x0, Lbw_hid_rel
    mov  x23, x0
    MSG0 Ls_UTF8String
    mov  x1, x0
    mov  x0, x19
    mov  x2, x22
    mov  x3, #0
    bl   _bat_line
    mov  x0, x23
    bl   _CFRelease
Lbw_hid_rel:
    mov  w0, w21
    bl   _IOObjectRelease
    b    Lbw_hid_loop
Lbw_hid_done:
    mov  w0, w20
    bl   _IOObjectRelease
Lbw_bt:
    // ---- connected Bluetooth audio (AirPods, Beats): what macOS knows ----
    ADRL x0, Ls_IOBluetoothDevice
    bl   _objc_getClass
    cbz  x0, Lbw_send
    MSG0 Ls_pairedDevices
    cbz  x0, Lbw_send
    mov  x20, x0
    MSG0 Ls_count
    mov  x21, x0
    mov  x22, #0
Lbw_bt_loop:
    cmp  x22, x21
    b.hs Lbw_send
    mov  x0, x20
    mov  x2, x22
    MSG1 Ls_objectAtIndex
    mov  x23, x0
    MSG0 Ls_isConnected
    tst  w0, #0xff
    b.eq Lbw_bt_next
    mov  x0, x23
    MSG0 Ls_nameOrAddress
    cbz  x0, Lbw_bt_next
    MSG0 Ls_UTF8String
    str  x0, [sp, #96]
    mov  x0, x23
    ADRL x1, Ls_bp_single
    bl   _sn_bt_pct
    tbnz x0, #63, Lbw_bt_pair
    mov  x2, x0
    mov  x0, x19
    ldr  x1, [sp, #96]
    mov  x3, #0
    bl   _bat_line
    b    Lbw_bt_next
Lbw_bt_pair:                          // earbuds: the lower of the two, and the case
    mov  x0, x23
    ADRL x1, Ls_bp_left
    bl   _sn_bt_pct
    mov  x24, x0
    mov  x0, x23
    ADRL x1, Ls_bp_right
    bl   _sn_bt_pct
    tbnz x24, #63, Lbw_bt_r
    tbnz x0, #63, Lbw_bt_l
    cmp  x0, x24
    csel x24, x0, x24, lt
    b    Lbw_bt_l
Lbw_bt_r:
    mov  x24, x0
Lbw_bt_l:
    tbnz x24, #63, Lbw_bt_next
    mov  x0, x19
    ldr  x1, [sp, #96]
    mov  x2, x24
    mov  x3, #0
    bl   _bat_line
Lbw_bt_next:
    add  x22, x22, #1
    b    Lbw_bt_loop
Lbw_send:
    mov  x1, x19
    LDGOT x0, __dispatch_main_q
    ADRL x2, _bat_show
    bl   _dispatch_async_f
    LEAVE 48

// id _sn_ioprop(io_object_t o, const char *key) -> the property (retained) or 0
_sn_ioprop:
    ENTER 0
    mov  w19, w0
    mov  x0, x1
    bl   _nsstr
    mov  x1, x0
    mov  w0, w19
    mov  x2, #0
    mov  w3, #0
    bl   _IORegistryEntryCreateCFProperty
    LEAVE 0

// long _sn_bt_pct(IOBluetoothDevice *d, const char *selector) -> 1..100, or -1
_sn_bt_pct:
    ENTER 0
    mov  x19, x0
    mov  x0, x1
    bl   _sel_registerName
    mov  x20, x0
    mov  x0, x19
    SELX1 Ls_respondsToSelector
    mov  x2, x20
    mov  x0, x19
    bl   _objc_msgSend
    tst  w0, #0xff
    b.eq Lbp_none
    mov  x0, x19
    mov  x1, x20
    bl   _objc_msgSend
    and  x0, x0, #0xff
    cbz  x0, Lbp_none
    cmp  x0, #100
    b.hi Lbp_none
    LEAVE 0
Lbp_none:
    mov  x0, #-1
    LEAVE 0

// void _bat_show(ctx) — main thread: the list in Home (or, quietly, pushes for low ones)
_bat_show:
    ENTER 32
    mov  x19, x0
    ldr  x20, [x19]                   // quiet?
    // the sensors and AirPods we heard, added on this side
    mov  x21, #0
Lbs2_sn:
    ADRL x8, _g_sn_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lbs2_air
    SNE  x22, x21
    ldr  x9, [x22, #(SN_R + RD_HAVE)]
    tbz  x9, #2, Lbs2_sn_next
    ldr  x9, [x22, #SN_DEV]           // only yours (named)
    tbnz x9, #63, Lbs2_sn_next
    mov  x0, x21
    bl   _sn_label
    mov  x1, x0
    mov  x0, x19
    ldr  x2, [x22, #(SN_R + RD_BATT)]
    mov  x3, #0
    bl   _bat_line
Lbs2_sn_next:
    add  x21, x21, #1
    b    Lbs2_sn
Lbs2_air:
    mov  x0, #0
    bl   _time
    ADRL x8, _g_air_seen
    ldr  x9, [x8]
    cbz  x9, Lbs2_out
    sub  x9, x0, x9
    cmp  x9, #120
    b.gt Lbs2_out
    ADRL x8, _g_air_rssi
    ldr  x9, [x8]
    cmn  x9, #75                      // close by only
    b.lt Lbs2_out
    ADRL x22, _g_air
    ldr  x0, [x22]
    bl   _air_model
    str  x0, [sp, #96]
    ldr  x9, [x22, #8]
    ldr  x10, [x22, #16]
    tbnz x9, #63, Lbs2_air_r
    tbnz x10, #63, Lbs2_air_l
    cmp  x10, x9
    csel x9, x10, x9, lt
    b    Lbs2_air_l
Lbs2_air_r:
    mov  x9, x10
Lbs2_air_l:
    tbnz x9, #63, Lbs2_air_case
    mov  x0, x19
    ldr  x1, [sp, #96]
    mov  x2, x9
    ldr  x3, [x22, #32]
    and  x3, x3, #3
    bl   _bat_line
Lbs2_air_case:
    ldr  x9, [x22, #24]
    tbnz x9, #63, Lbs2_out
    ADRL x0, _g_sn_val
    mov  x1, #64
    ADRL x2, Lf_air_case
    ldr  x3, [sp, #96]
    bl   _sfmt
    mov  x0, x19
    ADRL x1, _g_sn_val
    ldr  x2, [x22, #24]
    ldr  x3, [x22, #32]
    and  x3, x3, #4
    bl   _bat_line
Lbs2_out:
    cbnz x20, Lbs2_quiet
    add  x0, x19, #8
    ldrb w9, [x0]
    cbnz w9, Lbs2_list
    ADRL x0, Ls_bat_none
    bl   _home_say0
    b    Lbs2_free
Lbs2_list:
    ADRL x0, Ls_bat_head
    bl   _home_say0
    add  x21, x19, #8                 // name \t pct \t charging \n
Lbs2_line:
    ldrb w9, [x21]
    cbz  w9, Lbs2_free
    mov  x0, x21
    bl   _bat_parse                   // x0 name, x1 pct, x2 charging, x3 next
    mov  x21, x3
    mov  x22, x0
    mov  x23, x1
    mov  x24, x2
    ADRL x2, Lf_bat_line
    cmp  x23, #15
    b.hi Lbs2_fmt
    ADRL x2, Lf_bat_low
Lbs2_fmt:
    ADRL x5, Ls_empty
    cbz  x24, Lbs2_say
    ADRL x5, Ls_charging
Lbs2_say:
    ADRL x0, _g_sn_line
    mov  x1, #512
    mov  x3, x22
    mov  x4, x23
    bl   _sfmt
    ADRL x0, _g_sn_line
    bl   _home_say0
    b    Lbs2_line
Lbs2_quiet:                           // hourly: push the low ones, once a day each
    add  x21, x19, #8
Lbs2_q:
    ldrb w9, [x21]
    cbz  w9, Lbs2_free
    mov  x0, x21
    bl   _bat_parse
    mov  x21, x3
    cmp  x1, #15
    b.hi Lbs2_q
    cbnz x2, Lbs2_q                   // charging: fine
    mov  x22, x0
    mov  x23, x1
    mov  x0, x22
    bl   _bat_once_today
    cbz  x0, Lbs2_q
    ADRL x0, _g_sn_line
    mov  x1, #512
    ADRL x2, Lf_bat_push
    mov  x3, x22
    mov  x4, x23
    bl   _sfmt
    ADRL x0, _g_sn_line
    mov  x1, #0
    bl   _push_all
    b    Lbs2_q
Lbs2_free:
    mov  x0, x19
    bl   _free
    LEAVE 32

// _bat_parse(char *line) -> x0 name (NUL-terminated in place), x1 pct, x2 charging,
//   x3 the next line
_bat_parse:
    ENTER 0
    mov  x19, x0
    mov  x20, x0
Lbp2_tab1:
    ldrb w9, [x20]
    cbz  w9, Lbp2_end
    cmp  w9, #9
    b.eq Lbp2_t1
    add  x20, x20, #1
    b    Lbp2_tab1
Lbp2_t1:
    strb wzr, [x20]
    add  x20, x20, #1
    mov  x0, x20
    bl   _atol
    mov  x21, x0
Lbp2_tab2:
    ldrb w9, [x20]
    cbz  w9, Lbp2_end
    cmp  w9, #9
    b.eq Lbp2_t2
    add  x20, x20, #1
    b    Lbp2_tab2
Lbp2_t2:
    add  x20, x20, #1
    mov  x0, x20
    bl   _atol
    mov  x22, x0
Lbp2_nl:
    ldrb w9, [x20]
    cbz  w9, Lbp2_ret
    add  x20, x20, #1
    cmp  w9, #'\n'
    b.ne Lbp2_nl
Lbp2_ret:
    mov  x0, x19
    mov  x1, x21
    mov  x2, x22
    mov  x3, x20
    LEAVE 0
Lbp2_end:
    mov  x0, x19
    mov  x1, #100
    mov  x2, #0
    mov  x3, x20
    LEAVE 0

// long _bat_once_today(const char *name) -> 1 the first time today (and remembers it)
_bat_once_today:
    ENTER 0
    mov  x19, x0
    mov  x20, #5381                   // djb2
Lot_h:
    ldrb w9, [x19], #1
    cbz  w9, Lot_day
    add  x20, x9, x20, lsl #5
    add  x20, x20, x20, lsr #59
    b    Lot_h
Lot_day:
    mov  x0, #0
    bl   _time
    MOVI x9, 86400
    udiv x21, x0, x9
    ADRL x22, _g_bat_low
    mov  x23, #0
Lot_find:
    cmp  x23, #16
    b.hs Lot_new
    lsl  x9, x23, #4
    ldr  x10, [x22, x9]
    cmp  x10, x20
    b.ne Lot_next
    add  x9, x9, #8
    ldr  x10, [x22, x9]
    cmp  x10, x21
    b.eq Lot_no
    str  x21, [x22, x9]
    b    Lot_yes
Lot_next:
    add  x23, x23, #1
    b    Lot_find
Lot_new:
    ADRL x8, _g_bat_days              // round robin
    ldr  x23, [x8]
    add  x9, x23, #1
    and  x9, x9, #15
    str  x9, [x8]
    lsl  x9, x23, #4
    str  x20, [x22, x9]
    add  x9, x9, #8
    str  x21, [x22, x9]
Lot_yes:
    mov  x0, #1
    LEAVE 0
Lot_no:
    mov  x0, #0
    LEAVE 0

// void _sens_tick(long seconds) — every 10 s from the scanner: hourly battery check
.globl _sens_tick
_sens_tick:
    ENTER 0
    mov  x19, x0
    mov  x9, #3600
    udiv x10, x19, x9
    msub x10, x10, x9, x19
    cmp  x10, #600                    // ten minutes in, then every hour
    b.ne Ltk_done
    mov  x0, #SVC_SENSORS
    bl   _svc_on
    cbz  x0, Ltk_done
    mov  x0, #SVC_NTFY                // only worth it if a push can go out
    bl   _svc_on
    mov  x20, x0
    mov  x0, #SVC_PUSHOVER
    bl   _svc_on
    orr  x0, x0, x20
    cbz  x0, Ltk_done
    mov  x0, #1
    bl   _bat_start
Ltk_done:
    LEAVE 0

// ===========================================================================
// Self-tests (asmmesh --selftest)
// ===========================================================================

// TREP name : flags "eq" = pass
.macro TREP name
    cset w1, eq
    ADRL x0, \name
    bl   _t_report
    add  x19, x19, x0
.endm

.globl _sens_selftest
_sens_selftest:
    ENTER 48                          // [96] devices before  [104] a device
    mov  x19, #0
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    str  x9, [sp, #96]
    // 94. BTHome: 25.00 °C, 50.55 %
    ADRL x0, _g_sn_rd
    bl   _rd_clear
    ADRL x0, Lt_bth1
    mov  x1, #7
    ADRL x2, _g_sn_rd
    bl   _sn_bthome
    ADRL x8, _g_sn_rd
    ldr  x9, [x8, #RD_TEMP]
    ldr  x10, [x8, #RD_HUM]
    ldr  x11, [x8, #RD_HAVE]
    cmp  x0, #1
    mov  x12, #2500
    ccmp x9, x12, #0, eq
    mov  x12, #5055
    ccmp x10, x12, #0, eq
    ccmp x11, #3, #0, eq
    TREP Ln_bth1
    // 95. BTHome buttons: packet 5, button 1 press, button 2 double press
    ADRL x0, _g_sn_rd
    bl   _rd_clear
    ADRL x0, Lt_bth2
    mov  x1, #7
    ADRL x2, _g_sn_rd
    bl   _sn_bthome
    ADRL x8, _g_sn_rd
    ldr  x9, [x8, #RD_NBTN]
    ldrb w10, [x8, #RD_BTN]
    ldrb w11, [x8, #(RD_BTN + 1)]
    ldr  x12, [x8, #RD_PID]
    cmp  x0, #1
    ccmp x9, #2, #0, eq
    ccmp x10, #1, #0, eq
    ccmp x11, #2, #0, eq
    ccmp x12, #5, #0, eq
    TREP Ln_bth2
    // 96. BTHome with encryption on: recognised, not read
    ADRL x0, _g_sn_rd
    bl   _rd_clear
    ADRL x0, Lt_bth3
    mov  x1, #5
    ADRL x2, _g_sn_rd
    bl   _sn_bthome
    cmn  x0, #1
    TREP Ln_bth3
    // 97. Govee H5075 (with the iBeacon macOS glues on): 21.3 °C, 44.2 %, battery 100
    ADRL x0, _g_sn_rd
    bl   _rd_clear
    ADRL x0, Lt_gv1
    mov  x1, #(Lt_gv1_end - Lt_gv1)
    ADRL x2, Lt_gv1_name
    ADRL x3, _g_sn_rd
    bl   _sn_govee
    ADRL x8, _g_sn_rd
    ldr  x9, [x8, #RD_TEMP]
    ldr  x10, [x8, #RD_HUM]
    ldr  x11, [x8, #RD_BATT]
    cmp  x0, #1
    mov  x12, #2130
    ccmp x9, x12, #0, eq
    mov  x12, #4420
    ccmp x10, x12, #0, eq
    mov  x12, #100
    ccmp x11, x12, #0, eq
    TREP Ln_gv1
    // 98. SwitchBot Meter: 22.5 °C, 50 %, battery 100
    ADRL x0, _g_sn_rd
    bl   _rd_clear
    ADRL x0, Lt_sb1
    mov  x1, #6
    mov  x2, #0
    mov  x3, #0
    ADRL x4, _g_sn_rd
    bl   _sn_switchbot
    ADRL x8, _g_sn_rd
    ldr  x9, [x8, #RD_TEMP]
    ldr  x10, [x8, #RD_HUM]
    ldr  x11, [x8, #RD_BATT]
    cmp  x0, #1
    mov  x12, #2250
    ccmp x9, x12, #0, eq
    mov  x12, #5000
    ccmp x10, x12, #0, eq
    mov  x12, #100
    ccmp x11, x12, #0, eq
    TREP Ln_sb1
    // 99. Xiaomi on ATC firmware: 22.5 °C, 55 %, battery 90
    ADRL x0, _g_sn_rd
    bl   _rd_clear
    ADRL x0, Lt_atc1
    mov  x1, #13
    ADRL x2, _g_sn_rd
    bl   _sn_xiaomi
    ADRL x8, _g_sn_rd
    ldr  x9, [x8, #RD_TEMP]
    ldr  x10, [x8, #RD_HUM]
    ldr  x11, [x8, #RD_BATT]
    cmp  x0, #1
    mov  x12, #2250
    ccmp x9, x12, #0, eq
    mov  x12, #5500
    ccmp x10, x12, #0, eq
    mov  x12, #90
    ccmp x11, x12, #0, eq
    TREP Ln_atc1
    // 100. rule subjects: "the bedroom humidity" -> bedroom, humidity;
    //      "temperature in the living room" -> living room, temperature
    ADRL x0, _g_sn_line
    ADRL x1, Lt_sq1
    mov  x2, #64
    bl   _strlcpy
    ADRL x0, _g_sn_line
    bl   _sens_subj_q
    mov  x20, x0
    ADRL x0, _g_sn_line
    ADRL x1, Lt_bedroom
    bl   _strcmp
    mov  x21, x0
    ADRL x0, _g_sn_line
    ADRL x1, Lt_sq2
    mov  x2, #64
    bl   _strlcpy
    ADRL x0, _g_sn_line
    bl   _sens_subj_q
    mov  x22, x0
    ADRL x0, _g_sn_line
    ADRL x1, Lt_living
    bl   _strcmp
    cmp  x20, #2
    ccmp w21, #0, #0, eq
    ccmp x22, #1, #0, eq
    ccmp w0, #0, #0, eq
    TREP Ln_subj
    // 101. "button 2 on the remote" -> remote, button 2
    ADRL x0, _g_sn_line
    ADRL x1, Lt_sb2
    mov  x2, #64
    bl   _strlcpy
    ADRL x0, _g_sn_line
    bl   _sens_subj_btn
    mov  x20, x0
    ADRL x0, _g_sn_line
    ADRL x1, Lt_remote
    bl   _strcmp
    cmp  x20, #2
    ccmp w0, #0, #0, eq
    TREP Ln_subjb
    // 102. thresholds: "78°f turn on the fan" -> 25.55 °C; "70% turn …" -> 70.00
    ADRL x0, Lt_thr1
    mov  x1, #1
    bl   _sens_parse_thr
    mov  x20, x0
    mov  x21, x1
    ADRL x1, Lt_fan
    bl   _strcmp
    mov  x22, x0
    ADRL x0, Lt_thr2
    mov  x1, #2
    bl   _sens_parse_thr
    mov  x23, x1
    mov  x9, #2555
    cmp  x21, x9
    ccmp w22, #0, #0, eq
    mov  x9, #7000
    ccmp x23, x9, #0, eq
    TREP Ln_thr
    // a named sensor "Bedroom" at 20 °C, a button "Doorbell", for the rules
    ADRL x8, _g_sn_count
    mov  x9, #1
    str  x9, [x8]
    ADRL x20, _g_sns
    mov  x9, #H_TEMP
    str  x9, [x20, #(SN_R + RD_HAVE)]
    mov  x9, #2000
    str  x9, [x20, #(SN_R + RD_TEMP)]
    mov  x0, #K_BLES
    ADRL x1, Lt_uuid1
    ADRL x2, Lt_Bedroom
    mov  x3, #CAP_STATUS
    bl   _dev_add
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    str  xzr, [x8, #D_SIDX]
    mov  x0, #K_BLES
    ADRL x1, Lt_uuid2
    ADRL x2, Lt_Doorbell
    mov  x3, #CAP_STATUS
    bl   _dev_add
    str  x0, [sp, #104]
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    mov  x9, #5                       // no such sensor: never a reading
    str  x9, [x8, #D_SIDX]
    ADRL x8, _g_rule_count
    str  xzr, [x8]
    // 103. "when bedroom gets above 78 f turn on the kitchen": made, and fires on the way up
    ADRL x0, Lt_rthr
    mov  x1, #1
    bl   _rule_try
    ADRL x21, _g_rules
    ldr  x22, [x21, #0]               // type
    ldr  x23, [x21, #16]              // the number
    bl   _rules_sens_eval             // 20 °C: below, noted
    ldr  x24, [x21, #72]              // not pending
    mov  x9, #2600
    str  x9, [x20, #(SN_R + RD_TEMP)]
    bl   _rules_sens_eval             // 26 °C: above now
    ldr  x9, [x21, #72]
    cmp  x22, #5
    mov  x10, #2555
    ccmp x23, x10, #0, eq
    ccmp x24, #0, #0, eq
    ccmp x9, #1, #0, eq
    TREP Ln_rthr
    // 104. "when doorbell button 2 is double pressed say hello": that press fires it, others don't
    ADRL x8, _g_rule_count
    str  xzr, [x8]
    ADRL x0, Lt_rbtn
    mov  x1, #1
    bl   _rule_try
    ADRL x21, _g_rules
    ldr  x22, [x21, #0]
    ldr  x23, [x21, #8]               // which button
    ldr  x0, [sp, #104]
    mov  x1, #1
    mov  x2, #2
    bl   _rules_button
    mov  x24, x0
    ldr  x0, [sp, #104]
    mov  x1, #2
    mov  x2, #2
    bl   _rules_button
    cmp  x22, #6
    ccmp x23, #2, #0, eq
    ccmp x24, #0, #0, eq
    ccmp x0, #1, #0, eq
    TREP Ln_rbtn
    // 105. "when hallway detects motion turn on the hall light": a motion rule
    ADRL x8, _g_rule_count
    str  xzr, [x8]
    ADRL x0, Lt_rmot
    mov  x1, #1
    bl   _rule_try
    ADRL x21, _g_rules
    ldr  x22, [x21, #0]
    ldr  x23, [x21, #32]
    ldr  x24, [x21, #40]
    cmp  x22, #4
    mov  x9, #D_MOTION
    ccmp x23, x9, #0, eq
    ccmp x24, #1, #0, eq
    TREP Ln_rmot
    // tidy up
    ADRL x8, _g_rule_count
    str  xzr, [x8]
    ADRL x8, _g_sn_count
    str  xzr, [x8]
    ADRL x8, _g_dev_count
    ldr  x9, [sp, #96]
    str  x9, [x8]
    mov  x0, x19
    LEAVE 48

.section __TEXT,__const
Lt_bth1:   .byte 0x40, 0x02, 0xC4, 0x09, 0x03, 0xBF, 0x13
Lt_bth2:   .byte 0x44, 0x00, 0x05, 0x3A, 0x01, 0x3A, 0x02
Lt_bth3:   .byte 0x41, 0x11, 0x22, 0x33, 0x44
Lt_gv1:    .byte 0x88, 0xEC, 0x00, 0x03, 0x41, 0xC2, 0x64, 0x00, 0x4C, 0x00, 0x02, 0x15
           .ascii "INTELLI_ROCKS_HW"
           .byte 0x50, 0x75, 0xF2, 0xFF, 0x0C
Lt_gv1_end:
Lt_sb1:    .byte 0x54, 0x00, 0x64, 0x05, 0x96, 0x32
Lt_atc1:   .byte 0xA4, 0xC1, 0x38, 0x11, 0x22, 0x33, 0x00, 0xE1, 0x37, 0x5A, 0x0B, 0xB8, 0x01

.section __TEXT,__cstring,cstring_literals
Lt_gv1_name: .asciz "GVH5075_2762"
Lt_sq1:      .asciz "the bedroom humidity"
Lt_sq2:      .asciz "temperature in the living room"
Lt_sb2:      .asciz "button 2 on the remote"
Lt_bedroom:  .asciz "bedroom"
Lt_living:   .asciz "living room"
Lt_remote:   .asciz "remote"
Lt_thr1:     .asciz "78\302\260f turn on the fan"
Lt_thr2:     .asciz "70% turn on the fan"
Lt_fan:      .asciz "turn on the fan"
Lt_uuid1:    .asciz "TEST-SENSOR-1"
Lt_uuid2:    .asciz "TEST-SENSOR-2"
Lt_Bedroom:  .asciz "Bedroom"
Lt_Doorbell: .asciz "Doorbell"
Lt_rthr:     .asciz "when bedroom gets above 78 f turn on the kitchen"
Lt_rbtn:     .asciz "when doorbell button 2 is double pressed say hello"
Lt_rmot:     .asciz "when hallway detects motion turn on the hall light"
Ln_bth1:     .asciz "94 sensors: BTHome temperature and humidity are read"
Ln_bth2:     .asciz "95 sensors: BTHome button presses, one per button, with the packet id"
Ln_bth3:     .asciz "96 sensors: an encrypted BTHome sensor is recognised but not read"
Ln_gv1:      .asciz "97 sensors: Govee H5075, even with the iBeacon macOS glues on"
Ln_sb1:      .asciz "98 sensors: SwitchBot Meter"
Ln_atc1:     .asciz "99 sensors: Xiaomi thermometer on ATC firmware"
Ln_subj:     .asciz "100 rules: \342\200\234the bedroom humidity\342\200\235 / \342\200\234temperature in the living room\342\200\235"
Ln_subjb:    .asciz "101 rules: \342\200\234button 2 on the remote\342\200\235"
Ln_thr:      .asciz "102 rules: 78\302\260F and 70% read as limits"
Ln_rthr:     .asciz "103 rules: \342\200\234when bedroom gets above 78\342\200\235 fires on the way up, not before"
Ln_rbtn:     .asciz "104 rules: a button rule fires for its button and press only"
Ln_rmot:     .asciz "105 rules: \342\200\234when hallway detects motion\342\200\235"

// ---------------------------------------------------------------------------
.section __DATA,__const
.p2align 3
Lts_prefixes:
    .quad Ls_p_in_the, Ls_p_on_the, Ls_p_of_the, Ls_p_the, Ls_p_in, Ls_p_on, Ls_p_of
    .quad Ls_p_my, Ls_p_it, 0
Lpt_unit_words:                       // word, 1 Celsius / 2 Fahrenheit / 0 neither
    .quad Ls_u_degrees, 0
    .quad Ls_u_degree, 0
    .quad Ls_u_deg, 0
    .quad Ls_u_percent, 0
    .quad Ls_u_lux, 0
    .quad Ls_u_celsius, 1
    .quad Ls_u_fahrenheit, 2
    .quad Ls_u_f, 2
    .quad Ls_u_c, 1
    .quad 0, 0
Lair_models:
    .quad 0x2002, Ls_air_1
    .quad 0x200F, Ls_air_2
    .quad 0x2013, Ls_air_3
    .quad 0x2019, Ls_air_4
    .quad 0x201B, Ls_air_4
    .quad 0x200E, Ls_air_pro
    .quad 0x2014, Ls_air_pro2
    .quad 0x2024, Ls_air_pro2
    .quad 0x200A, Ls_air_max
    .quad 0x201F, Ls_air_max
    .quad 0x200B, Ls_air_pbpro
    .quad 0x2010, Ls_air_flex
    .quad 0x2011, Ls_air_studio
    .quad 0x2012, Ls_air_fit
    .quad 0x2016, Ls_air_studio
    .quad 0, 0

.section __TEXT,__cstring,cstring_literals
Ls_objectForKey:   .asciz "objectForKey:"
Ls_length:         .asciz "length"
Ls_bytes:          .asciz "bytes"
Ls_retain:         .asciz "retain"
Ls_identifier:     .asciz "identifier"
Ls_UUIDString:     .asciz "UUIDString"
Ls_UTF8String:     .asciz "UTF8String"
Ls_CBUUID:         .asciz "CBUUID"
Ls_UUIDWithString: .asciz "UUIDWithString:"
Ls_count:          .asciz "count"
Ls_objectAtIndex:  .asciz "objectAtIndex:"
Ls_isEqualToString: .asciz "isEqualToString:"
Ls_integerValue:   .asciz "integerValue"
Ls_boolValue:      .asciz "boolValue"
Ls_IOBluetoothDevice: .asciz "IOBluetoothDevice"
Ls_pairedDevices:  .asciz "pairedDevices"
Ls_isConnected:    .asciz "isConnected"
Ls_nameOrAddress:  .asciz "nameOrAddress"
Ls_respondsToSelector: .asciz "respondsToSelector:"
Ls_bp_single:      .asciz "batteryPercentSingle"
Ls_bp_left:        .asciz "batteryPercentLeft"
Ls_bp_right:       .asciz "batteryPercentRight"
Ls_u_fcd2:         .asciz "FCD2"
Ls_u_181a:         .asciz "181A"
Ls_u_fd3d:         .asciz "FD3D"
Ls_u_0d00:         .asciz "0D00"
Ls_ps_type:        .asciz "Type"
Ls_ps_internal:    .asciz "InternalBattery"
Ls_ps_cur:         .asciz "Current Capacity"
Ls_ps_max:         .asciz "Max Capacity"
Ls_ps_charging:    .asciz "Is Charging"
Ls_hid_class:      .asciz "AppleDeviceManagementHIDEventService"
Ls_hid_batt:       .asciz "BatteryPercent"
Ls_hid_product:    .asciz "Product"
Lf_sn_key:         .asciz "sensor_%s"
Ls_empty:          .asciz ""
Ls_minus:          .asciz "-"
Ls_dot:            .asciz " \302\267 "
Ls_deg_f:          .asciz "\302\260F"
Ls_deg_c:          .asciz "\302\260C"
Lf_temp:           .asciz "%s%ld.%ld%s"
Lf_two:            .asciz "%s %s"
Lf_thr_pct:        .asciz "%s %ld%%"
Lf_thr_lux:        .asciz "%s %ld lux"
Ls_w_above:        .asciz "above"
Ls_w_below:        .asciz "below"
Ls_w_humidity:     .asciz "humidity"
Ls_w_moisture:     .asciz "moisture"
Ls_w_light:        .asciz "light level"
Ls_w_temperature:  .asciz "temperature"
Ls_w_temp:         .asciz "temp"
Ls_w_button_sp:    .asciz "button "
Ls_w_button:       .asciz "button"
Ls_w_as:           .asciz "as"
Ls_w_to:           .asciz "to"
Ls_p_in_the:       .asciz "in the "
Ls_p_on_the:       .asciz "on the "
Ls_p_of_the:       .asciz "of the "
Ls_p_the:          .asciz "the "
Ls_p_in:           .asciz "in "
Ls_p_on:           .asciz "on "
Ls_p_of:           .asciz "of "
Ls_p_my:           .asciz "my "
Ls_p_it:           .asciz "it "
Ls_u_degrees:      .asciz "degrees"
Ls_u_degree:       .asciz "degree"
Ls_u_deg:          .asciz "deg"
Ls_u_percent:      .asciz "percent"
Ls_u_lux:          .asciz "lux"
Ls_u_celsius:      .asciz "celsius"
Ls_u_fahrenheit:   .asciz "fahrenheit"
Ls_u_f:            .asciz "f"
Ls_u_c:            .asciz "c"
Ls_sk_0:           .asciz "Bluetooth sensor"
Ls_sk_bthome:      .asciz "BTHome sensor"
Ls_sk_govee:       .asciz "Govee thermometer"
Ls_sk_switchbot:   .asciz "SwitchBot meter"
Ls_sk_xiaomi:      .asciz "Xiaomi thermometer"
Lf_sm_hum:         .asciz "%ld%% humidity"
Lf_sm_moist:       .asciz "soil %ld%%"
Lf_sm_lux:         .asciz "%ld lux"
Lf_sm_press:       .asciz "%ld hPa"
Lf_sm_co2:         .asciz "%ld ppm CO\342\202\202"
Lf_sm_batt:        .asciz "battery %ld%%"
Ls_sm_open:        .asciz "open"
Ls_sm_closed:      .asciz "closed"
Ls_sm_motion:      .asciz "motion"
Ls_sm_still:       .asciz "no motion"
Ls_sm_wet:         .asciz "\342\232\240\357\270\217 water"
Ls_sm_dry:         .asciz "dry"
Ls_sm_smoke:       .asciz "\342\232\240\357\270\217 SMOKE"
Ls_sm_nosmoke:     .asciz "no smoke"
Ls_sm_button:      .asciz "a button"
Ls_sm_enc:         .asciz "encrypted \342\200\224 turn encryption off in its app so asmmesh can read it"
Ls_just_now:       .asciz "just now"
Lf_min_ago:        .asciz "%ld min ago"
Lf_h_ago:          .asciz "%ld h ago"
Ls_ev_press:       .asciz "pressed"
Ls_ev_double:      .asciz "double-pressed"
Ls_ev_triple:      .asciz "triple-pressed"
Ls_ev_long:        .asciz "long-pressed"
Lf_sn_press:       .asciz "\302\267 \360\237\224\230 %s: button %ld %s \342\200\224 no rule for that yet (\342\200\234when \342\200\246 is pressed \342\200\246\342\200\235)."
Lf_sn_press_new:   .asciz "\302\267 \360\237\224\230 A Bluetooth button was pressed: %s. Give it a name with \342\200\234name sensor %ld doorbell\342\200\235 and it can run rules."
Lf_sn_head:        .asciz "\302\267 Bluetooth sensors heard (%ld):"
Lf_sn_named:       .asciz "\302\267 %ld. %s (%s): %s \302\267 %s"
Lf_sn_unnamed:     .asciz "\302\267 %ld. %s \342\200\224 not named (%s): %s \302\267 %s"
Ls_sn_foot:        .asciz "\302\267 Name one to use it: \342\200\234name sensor 1 bedroom\342\200\235. Then \342\200\234bedroom temperature\342\200\235, \342\200\234when bedroom gets above 78 turn on the fan\342\200\235, \342\200\234when the front door opens turn on the hall light\342\200\235 or \342\200\234when doorbell is pressed say someone's here\342\200\235."
Ls_sn_none:        .asciz "\302\267 No Bluetooth sensors heard yet. asmmesh reads Govee, SwitchBot and Xiaomi (ATC/pvvx firmware) thermometers, and BTHome devices such as Shelly BLU buttons, door/window and motion sensors \342\200\224 no pairing, they just need to be within range."
Lf_sn_named_ok:    .asciz "\302\267 Sensor %ld is now \342\200\234%s\342\200\235. Use that name in Home and in rules \342\200\224 e.g. \342\200\234%s temperature\342\200\235."
Ls_sn_name_help:   .asciz "\302\267 Say \342\200\234sensors\342\200\235 for the list, then \342\200\234name sensor 2 bedroom\342\200\235."
Lf_sn_status:      .asciz "\302\267 %s: %s (%s)"
Lf_sn_quiet:       .asciz "\302\267 %s hasn't been heard since asmmesh started \342\200\224 is it within Bluetooth range?"
Lf_bat_rec:        .asciz "%s\t%ld\t%ld\n"
Ls_this_mac:       .asciz "This Mac"
Ls_bat_looking:    .asciz "\302\267 \360\237\224\213 Checking batteries\342\200\246"
Ls_bat_head:       .asciz "\302\267 \360\237\224\213 Batteries:"
Lf_bat_line:       .asciz "\302\267    %s: %ld%%%s"
Lf_bat_low:        .asciz "\302\267    \342\232\240\357\270\217 %s: %ld%% \342\200\224 low%s"
Ls_charging:       .asciz ", charging"
Ls_bat_none:       .asciz "\302\267 I can't see any batteries right now. Magic keyboards and mice show up while they're connected, AirPods while connected or with the case open nearby, and Bluetooth sensors once you've named them."
Lf_bat_push:       .asciz "Low battery: %s at %ld%%"
Lf_air_case:       .asciz "%s case"
Ls_air_unknown:    .asciz "AirPods or Beats"
Ls_air_1:          .asciz "AirPods"
Ls_air_2:          .asciz "AirPods (2nd gen)"
Ls_air_3:          .asciz "AirPods (3rd gen)"
Ls_air_4:          .asciz "AirPods 4"
Ls_air_pro:        .asciz "AirPods Pro"
Ls_air_pro2:       .asciz "AirPods Pro 2"
Ls_air_max:        .asciz "AirPods Max"
Ls_air_pbpro:      .asciz "Powerbeats Pro"
Ls_air_flex:       .asciz "Beats Flex"
Ls_air_studio:     .asciz "Beats Studio Buds"
Ls_air_fit:        .asciz "Beats Fit Pro"
