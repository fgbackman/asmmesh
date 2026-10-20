// near.s — every Bluetooth LE device we hear that isn't on the mesh.
//
// From each advertisement: its name, signal, whether it accepts connections,
// its transmit power, who made it (the company id in the manufacturer data;
// for Apple, what kind of advertisement), and the services it lists by name.
// HomeKit accessories that aren't paired yet, and Matter devices open for
// commissioning, are marked so the scanner can offer to set them up.
//
// Connect & Pair (scanner): connects, reads Device Information (0x180A:
// manufacturer 2A29, model 2A24, firmware 2A26) and Battery (0x180F: 2A19).
// If the device only allows paired readers, macOS shows its own pairing
// dialog at that moment; after that it stays paired to this Mac.

.include "macros.inc"

.data
.p2align 3
.globl _g_near_count
_g_near_count:  .quad 0
.globl _g_near
.zerofill __DATA,__bss,_g_near,24576,4
.zerofill __DATA,__bss,_g_nr_tmp,96,4

.section __DATA,__const
.p2align 3
// company ids (Bluetooth SIG assigned numbers)
Lcompanies:
    .quad 0x004C, Lm_apple
    .quad 0x0006, Lm_microsoft
    .quad 0x0075, Lm_samsung
    .quad 0x00E0, Lm_google
    .quad 0x0087, Lm_garmin
    .quad 0x009E, Lm_bose
    .quad 0x012D, Lm_sony
    .quad 0x00C4, Lm_lg
    .quad 0x027D, Lm_huawei
    .quad 0x038F, Lm_xiaomi
    .quad 0x0171, Lm_amazon
    .quad 0x0224, Lm_fitbit
    .quad 0x006B, Lm_polar
    .quad 0x0059, Lm_nordic
    .quad 0x000F, Lm_broadcom
    .quad 0x0002, Lm_intel
    .quad 0x000A, Lm_qualcomm
    .quad 0x02E5, Lm_espressif
    .quad -1, 0

// Apple manufacturer-data types
Lapple_types:
    .quad 0, 0, Lat_ibeacon, 0, 0, Lat_airdrop, Lat_homekit, Lat_airpods
    .quad 0, Lat_airplay, 0, Lat_watch, Lat_handoff, Lat_hotspot, Lat_hotspot, Lat_action
    .quad Lat_nearby, 0, Lat_findmy, 0, 0, 0, 0
.set APPLE_TYPES, 23

// 16-bit service UUIDs worth naming
Lservices:
    .quad Lu_180D, Lsn_heart
    .quad Lu_180F, Lsn_battery
    .quad Lu_180A, Lsn_devinfo
    .quad Lu_1812, Lsn_hid
    .quad Lu_FE0F, Lsn_hue
    .quad Lu_FFF6, Lsn_matter
    .quad Lu_FD6F, Lsn_exposure
    .quad Lu_FEAA, Lsn_eddystone
    .quad Lu_FE2C, Lsn_fastpair
    .quad Lu_FE9F, Lsn_google
    .quad Lu_181A, Lsn_env
    .quad Lu_1816, Lsn_cycling
    .quad Lu_1818, Lsn_power
    .quad Lu_1826, Lsn_fitness
    .quad Lu_181D, Lsn_scale
    .quad Lu_1810, Lsn_bp
    .quad Lu_1809, Lsn_thermo
    .quad Lu_FD5A, Lsn_smarttag
    .quad Lu_FEED, Lsn_tile
    .quad Lu_FE07, Lsn_sonos
    .quad Lu_FE03, Lsn_alexa
    .quad 0, 0

.section __TEXT,__const
.p2align 3
Lc_log31:     .double 1.4913616938342726      // log10(31)
Lc_fmin:      .double 0.08
Lc_fmax:      .double 0.96

.text
.p2align 2

// entry for index
.macro NEARE reg, idx
    ADRL \reg, _g_near
    add  \reg, \reg, \idx, lsl #NEAR_SHIFT
.endm

// long _near_find(CBPeripheral *p) -> index or -1
.globl _near_find
_near_find:
    ADRL x8, _g_near_count
    ldr  x10, [x8]
    ADRL x8, _g_near
    mov  x9, #0
Lnf_loop:
    cmp  x9, x10
    b.hs Lnf_none
    ldr  x11, [x8, #NR_P]
    cmp  x11, x0
    b.eq Lnf_found
    add  x8, x8, #(1 << NEAR_SHIFT)
    add  x9, x9, #1
    b    Lnf_loop
Lnf_none:
    mov  x0, #-1
    ret
Lnf_found:
    mov  x0, x9
    ret

// void _nearby_seen(CBPeripheral *p, const char *name /*or 0*/, long rssi, NSDictionary *adv)
.globl _nearby_seen
_nearby_seen:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x24, x3
    bl   _near_find
    tbz  x0, #63, Lns_have
    ADRL x8, _g_near_count
    ldr  x22, [x8]
    cmp  x22, #NEAR_MAX
    b.hs Lns_done
    add  x9, x22, #1
    str  x9, [x8]
    NEARE x23, x22
    mov  x0, x23
    mov  x1, #(1 << NEAR_SHIFT)
    bl   _bzero
    mov  x9, #-1
    str  x9, [x23, #NR_CO]
    mov  x0, x19
    MSG0 Ls_retain
    str  x0, [x23, #NR_P]
    b    Lns_update
Lns_have:
    NEARE x23, x0
Lns_update:
    cmp  x21, #0                      // 127 means "no reading"
    b.ge Lns_time
    str  x21, [x23, #NR_RSSI]
    lsl  x10, x21, #4                 // smoothed x16: avg += (new - avg) / 4
    ldr  x9, [x23, #NR_AVG]
    cbz  x9, Lns_avg_set
    sub  x11, x10, x9
    asr  x11, x11, #2
    add  x10, x9, x11
Lns_avg_set:
    str  x10, [x23, #NR_AVG]
Lns_time:
    mov  x0, #0
    bl   _time
    ldr  x9, [x23, #NR_SEEN]          // back after two minutes away: a new visit
    sub  x10, x0, x9
    cmp  x10, #120
    b.lt Lns_same_visit
    str  x0, [x23, #NR_FIRST]
    str  xzr, [x23, #NR_ALERTED]
Lns_same_visit:
    str  x0, [x23, #NR_SEEN]
    cbz  x20, Lns_adv
    ldrb w9, [x20]
    cbz  w9, Lns_adv
    add  x0, x23, #NR_NAME
    mov  x1, x20
    mov  x2, #40
    bl   _strlcpy
    add  x0, x23, #NR_NAME
    bl   _utf8_fix
    add  x0, x23, #NR_NAME
    bl   _sanitize
Lns_adv:
    cbz  x24, Lns_done
    mov  x0, x23
    mov  x1, x24
    bl   _near_decode
Lns_done:
    LEAVE 0

// void _near_decode(entry, NSDictionary *adv)
_near_decode:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    ldr  x21, [x19, #NR_FLAGS]
    mov  x9, #(NF_LINKED | NF_READ | NF_INSPECT)
    and  x21, x21, x9
    // connectable
    LDGOT x8, _CBAdvertisementDataIsConnectable
    ldr  x2, [x8]
    mov  x0, x20
    MSG1 Ls_objectForKey
    cbz  x0, Lnd_tx
    MSG0 Ls_boolValue
    tst  w0, #0xff
    b.eq Lnd_tx
    orr  x21, x21, #NF_CONN
Lnd_tx:
    LDGOT x8, _CBAdvertisementDataTxPowerLevelKey
    ldr  x2, [x8]
    mov  x0, x20
    MSG1 Ls_objectForKey
    cbz  x0, Lnd_mfg
    MSG0 Ls_integerValue
    str  x0, [x19, #NR_TX]
    orr  x21, x21, #NF_TX
Lnd_mfg:
    LDGOT x8, _CBAdvertisementDataManufacturerDataKey
    ldr  x2, [x8]
    mov  x0, x20
    MSG1 Ls_objectForKey
    cbz  x0, Lnd_svcs
    mov  x22, x0
    MSG0 Ls_length
    mov  x23, x0
    cmp  x23, #2
    b.lo Lnd_svcs
    mov  x0, x22
    MSG0 Ls_bytes
    mov  x22, x0                      // bytes
    ldrh w9, [x22]                    // company id, little-endian
    str  x9, [x19, #NR_CO]
    ADRL x10, Lcompanies
    str  xzr, [x19, #NR_MAKER]
Lnd_co:
    ldr  x11, [x10]
    tbnz x11, #63, Lnd_apple
    cmp  x11, x9
    b.eq Lnd_co_hit
    add  x10, x10, #16
    b    Lnd_co
Lnd_co_hit:
    ldr  x11, [x10, #8]
    str  x11, [x19, #NR_MAKER]
Lnd_apple:
    str  xzr, [x19, #NR_SUB]
    cmp  x9, #0x4C
    b.ne Lnd_svcs
    cmp  x23, #3
    b.lo Lnd_svcs
    ldrb w9, [x22, #2]                // type
    cmp  x9, #APPLE_TYPES
    b.hs Lnd_svcs
    ADRL x10, Lapple_types
    ldr  x11, [x10, x9, lsl #3]
    str  x11, [x19, #NR_SUB]
    cmp  x9, #0x12                    // Find My: an AirTag or a lost Apple device
    b.ne Lnd_hk
    orr  x21, x21, #NF_TRACKER
    b    Lnd_svcs
Lnd_hk:
    cmp  x9, #6                       // HomeKit: status flags bit 0 = not paired
    b.ne Lnd_svcs
    cmp  x23, #5
    b.lo Lnd_svcs
    ldrb w9, [x22, #4]
    tbz  w9, #0, Lnd_svcs
    orr  x21, x21, #NF_HK_OPEN
Lnd_svcs:
    add  x9, x19, #NR_SVCS
    strb wzr, [x9]
    LDGOT x8, _CBAdvertisementDataServiceUUIDsKey
    ldr  x2, [x8]
    mov  x0, x20
    MSG1 Ls_objectForKey
    bl   _near_names                  // x0 array of CBUUID, x19 entry, x21 flags
    LDGOT x8, _CBAdvertisementDataServiceDataKey
    ldr  x2, [x8]
    mov  x0, x20
    MSG1 Ls_objectForKey
    cbz  x0, Lnd_done
    MSG0 Ls_allKeys
    bl   _near_names
Lnd_done:
    str  x21, [x19, #NR_FLAGS]
    LEAVE 16

// void _near_names(NSArray *uuids) — append service names to NR_SVCS of x19;
//   sets NF_MATTER in x21 for 0xFFF6. Uses the caller's x19 and x21.
_near_names:
    stp  x29, x30, [sp, #-64]!
    mov  x29, sp
    stp  x22, x23, [sp, #16]
    stp  x24, x25, [sp, #32]
    mov  x22, x0
    cbz  x22, Lnn_done
    mov  x0, x22
    MSG0 Ls_count
    mov  x23, x0
    mov  x24, #0
Lnn_loop:
    cmp  x24, x23
    b.hs Lnn_done
    mov  x0, x22
    mov  x2, x24
    MSG1 Ls_objectAtIndex
    MSG0 Ls_UUIDString
    MSG0 Ls_UTF8String
    add  x24, x24, #1
    cbz  x0, Lnn_loop
    mov  x25, x0
    ADRL x1, Lu_FFF6
    bl   _strcmp
    cbnz w0, Lnn_tag
    orr  x21, x21, #NF_MATTER
Lnn_tag:
    mov  x0, x25                      // SmartTag, Tile: item trackers
    ADRL x1, Lu_FD5A
    bl   _strcmp
    cbz  w0, Lnn_tracker
    mov  x0, x25
    ADRL x1, Lu_FEED
    bl   _strcmp
    cbz  w0, Lnn_tracker
    mov  x0, x25
    ADRL x1, Lu_FEEC
    bl   _strcmp
    cbnz w0, Lnn_name
Lnn_tracker:
    orr  x21, x21, #NF_TRACKER
Lnn_name:
    mov  x0, x25
    bl   _svc_name
    mov  x25, x0
    add  x0, x19, #NR_SVCS            // already listed?
    mov  x1, x25
    bl   _strstr
    cbnz x0, Lnn_loop
    add  x0, x19, #NR_SVCS
    ldrb w9, [x0]
    cbz  w9, Lnn_add
    ADRL x1, Ls_comma
    mov  x2, #64
    bl   _strlcat
Lnn_add:
    add  x0, x19, #NR_SVCS
    mov  x1, x25
    mov  x2, #64
    bl   _strlcat
    b    Lnn_loop
Lnn_done:
    ldp  x22, x23, [sp, #16]
    ldp  x24, x25, [sp, #32]
    ldp  x29, x30, [sp], #64
    ret

// const char *_svc_name(const char *uuid_string) -> a name for a known 16-bit UUID, else itself
.globl _svc_name
_svc_name:
    ENTER 0
    mov  x19, x0
    ADRL x20, Lservices
Lsvn_loop:
    ldr  x1, [x20]
    cbz  x1, Lsvn_self
    mov  x0, x19
    bl   _strcmp
    cbz  w0, Lsvn_hit
    add  x20, x20, #16
    b    Lsvn_loop
Lsvn_hit:
    ldr  x0, [x20, #8]
    LEAVE 0
Lsvn_self:
    mov  x0, x19
    LEAVE 0

// ===========================================================================
// Connect & Pair
// ===========================================================================

// void _near_inspect(long i)
.globl _near_inspect
_near_inspect:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lni_done
    NEARE x20, x19
    add  x21, x20, #NR_NAME
    ldrb w9, [x21]
    cbnz w9, Lni_named
    ADRL x21, Ls_this_device
Lni_named:
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_CONN
    b.eq Lni_not
    orr  x9, x9, #NF_INSPECT
    bic  x9, x9, #NF_READ
    str  x9, [x20, #NR_FLAGS]
    add  x9, x20, #NR_INFO
    strb wzr, [x9]
    str  xzr, [x20, #NR_PEND]
    mov  x0, #0
    bl   _time
    str  x0, [x20, #NR_T0]
    ADRL x8, _g_cm
    ldr  x0, [x8]
    ldr  x2, [x20, #NR_P]
    mov  x3, #0
    MSG2 Ls_connectPeripheral
    mov  x1, x21
    ADRL x0, Ls_connecting
    bl   _scan_say
Lni_done:
    LEAVE 0
Lni_not:
    mov  x1, x21
    ADRL x0, Ls_not_connectable
    bl   _scan_say
    LEAVE 0

// long _near_connected(CBPeripheral *p) -> 1 if it was ours to inspect
.globl _near_connected
_near_connected:
    ENTER 0
    mov  x19, x0
    bl   _near_find
    tbnz x0, #63, Lnc_no
    NEARE x20, x0
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_INSPECT
    b.eq Lnc_no
    orr  x9, x9, #NF_LINKED
    str  x9, [x20, #NR_FLAGS]
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x19
    MSG1 Ls_setDelegate
    mov  x0, x19
    mov  x2, #0                       // every service
    MSG1 Ls_discoverServices
    mov  x0, #1
    LEAVE 0
Lnc_no:
    mov  x0, #0
    LEAVE 0

// long _near_services(CBPeripheral *p, NSError *err) -> 1 if handled
.globl _near_services
_near_services:
    ENTER 16
    mov  x19, x0
    mov  x22, x1
    bl   _near_find
    tbnz x0, #63, Lnv_no
    mov  x23, x0
    NEARE x20, x0
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_INSPECT
    b.eq Lnv_no
    cbnz x22, Lnv_fail
    add  x9, x20, #NR_SVCS            // the full list, now that we're connected
    strb wzr, [x9]
    mov  x0, x19
    MSG0 Ls_services
    mov  x21, x0
    MSG0 Ls_count
    mov  x24, x0
    mov  x22, #0                      // asked for characteristics
    str  xzr, [sp, #96]
Lnv_loop:
    ldr  x9, [sp, #96]
    cmp  x9, x24
    b.hs Lnv_names
    mov  x0, x21
    mov  x2, x9
    MSG1 Ls_objectAtIndex
    mov  x23, x0
    MSG0 Ls_UUID
    MSG0 Ls_UUIDString
    MSG0 Ls_UTF8String
    cbz  x0, Lnv_next
    str  x0, [sp, #104]
    ADRL x1, Lu_180A
    bl   _strcmp
    cbz  w0, Lnv_ask
    ldr  x0, [sp, #104]
    ADRL x1, Lu_180F
    bl   _strcmp
    cbnz w0, Lnv_next
Lnv_ask:
    mov  x0, x19
    mov  x2, #0
    mov  x3, x23
    MSG2 Ls_discoverCharacteristics
    add  x22, x22, #1
Lnv_next:
    ldr  x9, [sp, #96]
    add  x9, x9, #1
    str  x9, [sp, #96]
    b    Lnv_loop
Lnv_names:
    mov  x0, x21                      // service names for the details pane
    bl   _uuids_of
    stp  x21, x22, [sp, #96]
    mov  x19, x20
    ldr  x21, [x20, #NR_FLAGS]
    bl   _near_names
    str  x21, [x20, #NR_FLAGS]
    ldp  x21, x22, [sp, #96]
    ldr  x19, [x20, #NR_P]
    str  x22, [x20, #NR_PEND]
    cbnz x22, Lnv_yes
    mov  x0, x20                      // nothing to read: done
    bl   _near_finish
Lnv_yes:
    mov  x0, #1
    LEAVE 16
Lnv_fail:
    mov  x0, x20
    bl   _near_finish
    mov  x0, #1
    LEAVE 16
Lnv_no:
    mov  x0, #0
    LEAVE 16

// NSArray *_uuids_of(NSArray *services_or_characteristics) -> their UUIDs
_uuids_of:
    ENTER 0
    mov  x19, x0
    ADRL x0, Ls_UUID_key
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_valueForKey
    LEAVE 0

// long _near_chars(CBPeripheral *p, CBService *s, NSError *err) -> 1 if handled
.globl _near_chars
_near_chars:
    ENTER 16
    mov  x19, x0
    mov  x21, x1
    mov  x22, x2
    bl   _near_find
    tbnz x0, #63, Lnh_no
    NEARE x20, x0
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_INSPECT
    b.eq Lnh_no
    ldr  x9, [x20, #NR_PEND]          // this service is answered
    sub  x9, x9, #1
    str  x9, [x20, #NR_PEND]
    cbnz x22, Lnh_check
    mov  x0, x21
    MSG0 Ls_characteristics
    mov  x21, x0
    MSG0 Ls_count
    mov  x24, x0
    mov  x23, #0
Lnh_loop:
    cmp  x23, x24
    b.hs Lnh_check
    mov  x0, x21
    mov  x2, x23
    MSG1 Ls_objectAtIndex
    str  x0, [sp, #96]
    MSG0 Ls_UUID
    MSG0 Ls_UUIDString
    MSG0 Ls_UTF8String
    add  x23, x23, #1
    cbz  x0, Lnh_loop
    bl   _chr_wanted
    cbz  x0, Lnh_loop
    mov  x0, x19
    ldr  x2, [sp, #96]
    MSG1 Ls_readValueForCharacteristic
    ldr  x9, [x20, #NR_PEND]
    add  x9, x9, #1
    str  x9, [x20, #NR_PEND]
    b    Lnh_loop
Lnh_check:
    ldr  x9, [x20, #NR_PEND]
    cmp  x9, #0
    b.gt Lnh_yes
    mov  x0, x20
    bl   _near_finish
Lnh_yes:
    mov  x0, #1
    LEAVE 16
Lnh_no:
    mov  x0, #0
    LEAVE 16

// long _chr_wanted(const char *uuid) -> 1 manufacturer 2 model 3 firmware 4 battery, 0 no
_chr_wanted:
    ENTER 0
    mov  x19, x0
    mov  x20, #1
    ADRL x1, Lu_2A29
    bl   _strcmp
    cbz  w0, Lcw_yes
    mov  x20, #2
    mov  x0, x19
    ADRL x1, Lu_2A24
    bl   _strcmp
    cbz  w0, Lcw_yes
    mov  x20, #3
    mov  x0, x19
    ADRL x1, Lu_2A26
    bl   _strcmp
    cbz  w0, Lcw_yes
    mov  x20, #4
    mov  x0, x19
    ADRL x1, Lu_2A19
    bl   _strcmp
    cbz  w0, Lcw_yes
    mov  x0, #0
    LEAVE 0
Lcw_yes:
    mov  x0, x20
    LEAVE 0

// long _near_value(CBPeripheral *p, CBCharacteristic *c, NSError *err) -> 1 if handled
.globl _near_value
_near_value:
    ENTER 16
    mov  x19, x0
    mov  x21, x1
    mov  x22, x2
    bl   _near_find
    tbnz x0, #63, Lnw_no
    NEARE x20, x0
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_INSPECT
    b.eq Lnw_no
    ldr  x9, [x20, #NR_PEND]
    sub  x9, x9, #1
    str  x9, [x20, #NR_PEND]
    cbnz x22, Lnw_locked
    mov  x0, x21
    MSG0 Ls_UUID
    MSG0 Ls_UUIDString
    MSG0 Ls_UTF8String
    cbz  x0, Lnw_check
    bl   _chr_wanted
    mov  x23, x0
    cbz  x23, Lnw_check
    mov  x0, x21
    MSG0 Ls_value
    cbz  x0, Lnw_check
    mov  x24, x0
    MSG0 Ls_length
    cbz  x0, Lnw_check
    mov  x22, x0
    mov  x0, x24
    MSG0 Ls_bytes
    mov  x24, x0
    cmp  x23, #4
    b.eq Lnw_battery
    cmp  x22, #40                     // text
    mov  x9, #40
    csel x22, x9, x22, hi
    ADRL x0, _g_nr_tmp
    mov  x1, x24
    mov  x2, x22
    bl   _memcpy
    ADRL x8, _g_nr_tmp
    strb wzr, [x8, x22]
    ADRL x0, _g_nr_tmp
    bl   _utf8_fix
    ADRL x0, _g_nr_tmp
    bl   _sanitize
    cmp  x23, #3
    b.ne Lnw_add
    ADRL x0, _g_nr_tmp                // "firmware 1.2.3"
    add  x0, x0, #48
    mov  x1, #48
    ADRL x2, Lf_fw
    ADRL x3, _g_nr_tmp
    bl   _sfmt
    ADRL x1, _g_nr_tmp
    add  x1, x1, #48
    ADRL x0, _g_nr_tmp
    mov  x2, #48
    bl   _strlcpy
    b    Lnw_add
Lnw_battery:
    ldrb w3, [x24]
    ADRL x0, _g_nr_tmp
    mov  x1, #48
    ADRL x2, Lf_battery
    bl   _sfmt
Lnw_add:
    add  x0, x20, #NR_INFO
    ldrb w9, [x0]
    cbz  w9, Lnw_piece
    ADRL x1, Ls_dot
    mov  x2, #NR_INFO_MAX
    bl   _strlcat
Lnw_piece:
    add  x0, x20, #NR_INFO
    ADRL x1, _g_nr_tmp
    mov  x2, #NR_INFO_MAX
    bl   _strlcat
    b    Lnw_check
Lnw_locked:                           // not allowed: it wants pairing (macOS asks), or refused
    add  x0, x20, #NR_INFO
    ADRL x1, Ls_locked
    bl   _strstr
    cbnz x0, Lnw_check
    add  x0, x20, #NR_INFO
    ldrb w9, [x0]
    cbz  w9, Lnw_lpiece
    ADRL x1, Ls_dot
    mov  x2, #NR_INFO_MAX
    bl   _strlcat
Lnw_lpiece:
    add  x0, x20, #NR_INFO
    ADRL x1, Ls_locked
    mov  x2, #NR_INFO_MAX
    bl   _strlcat
Lnw_check:
    ldr  x9, [x20, #NR_PEND]
    cmp  x9, #0
    b.gt Lnw_yes
    mov  x0, x20
    bl   _near_finish
Lnw_yes:
    mov  x0, #1
    LEAVE 16
Lnw_no:
    mov  x0, #0
    LEAVE 16

// void _near_finish(entry) — done inspecting: report, then let it go
_near_finish:
    ENTER 0
    mov  x19, x0
    ldr  x9, [x19, #NR_FLAGS]
    tst  x9, #NF_INSPECT
    b.eq Lnfi_done
    bic  x9, x9, #NF_INSPECT
    orr  x9, x9, #NF_READ
    str  x9, [x19, #NR_FLAGS]
    ldr  x0, [x19, #NR_P]
    bl   _ble_cancel
    add  x1, x19, #NR_NAME
    ldrb w9, [x1]
    cbnz w9, Lnfi_named
    ADRL x1, Ls_this_device
Lnfi_named:
    add  x2, x19, #NR_INFO
    ldrb w9, [x2]
    ADRL x0, Ls_inspected
    cbnz w9, Lnfi_say
    ADRL x0, Ls_inspected_none
Lnfi_say:
    bl   _scan_say
    bl   _ui_lists_changed
Lnfi_done:
    LEAVE 0

// void _near_lost(CBPeripheral *p)
.globl _near_lost
_near_lost:
    ENTER 0
    bl   _near_find
    tbnz x0, #63, Lnl_done
    NEARE x19, x0
    ldr  x9, [x19, #NR_FLAGS]
    bic  x9, x9, #NF_LINKED
    str  x9, [x19, #NR_FLAGS]
    tst  x9, #NF_INSPECT              // dropped before we were done
    b.eq Lnl_done
    mov  x0, x19
    bl   _near_finish
Lnl_done:
    LEAVE 0

// void _near_tick(void) — give up on an inspection after 20 seconds
.globl _near_tick
_near_tick:
    ENTER 0
    mov  x0, #0
    bl   _time
    mov  x21, x0
    mov  x19, #0
Lnt_loop:
    ADRL x8, _g_near_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lnt_done
    NEARE x20, x19
    ldr  x9, [x20, #NR_FLAGS]
    tst  x9, #NF_INSPECT
    b.eq Lnt_next
    ldr  x10, [x20, #NR_T0]
    sub  x10, x21, x10
    cmp  x10, #20
    b.lt Lnt_next
    add  x0, x20, #NR_INFO
    ldrb w9, [x0]
    cbnz w9, Lnt_finish
    ADRL x1, Ls_no_answer
    mov  x2, #NR_INFO_MAX
    bl   _strlcpy
Lnt_finish:
    mov  x0, x20
    bl   _near_finish
Lnt_next:
    add  x19, x19, #1
    b    Lnt_loop
Lnt_done:
    LEAVE 0

// char *_near_kind(long i, char *buf, size_t max) — "Apple · AirPods / Beats", "Samsung", "BLE"
.globl _near_kind
_near_kind:
    ENTER 0
    NEARE x19, x0
    mov  x20, x1
    mov  x21, x2
    ldr  x3, [x19, #NR_MAKER]
    ldr  x4, [x19, #NR_SUB]
    ldr  x9, [x19, #NR_FLAGS]
    tst  x9, #NF_MATTER
    b.ne Lnk_matter
    cbz  x3, Lnk_co
    cbz  x4, Lnk_maker
    mov  x0, x20
    mov  x1, x21
    ADRL x2, Lf_two
    bl   _sfmt
    b    Lnk_ret
Lnk_maker:
    mov  x0, x20
    mov  x1, x3
    mov  x2, x21
    bl   _strlcpy
    b    Lnk_ret
Lnk_co:
    ldr  x3, [x19, #NR_CO]
    tbnz x3, #63, Lnk_ble
    mov  x0, x20
    mov  x1, x21
    ADRL x2, Lf_company
    bl   _sfmt
    b    Lnk_ret
Lnk_matter:
    ADRL x1, Ls_k_matter
    b    Lnk_copy
Lnk_ble:
    ADRL x1, Ls_k_ble
Lnk_copy:
    mov  x0, x20
    mov  x2, x21
    bl   _strlcpy
Lnk_ret:
    mov  x0, x20
    LEAVE 0


// char *_near_label(long i, char *buf, size_t max) — its name or, when it doesn't say one
//   (iPhone and iPad rarely hear names from devices they haven't connected to), what its
//   advertisement says it is: "AirPods / Beats", "Samsung device", "Matter device"; 0 if nothing
.globl _near_label
_near_label:
    ENTER 0
    NEARE x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x0, x19, #NR_NAME
    ldrb w9, [x0]
    cbnz w9, Lnl_ret
    ldr  x9, [x19, #NR_FLAGS]
    ADRL x1, Ls_l_matter
    tst  x9, #NF_MATTER
    b.ne Lnl_copy
    ldr  x3, [x19, #NR_MAKER]
    cbz  x3, Lnl_none
    ldr  x4, [x19, #NR_SUB]           // Apple's own: the kind of thing it says it is
    ADRL x1, Lat_airpods
    cmp  x4, x1
    b.eq Lnl_copy
    ADRL x1, Ls_l_watch
    ADRL x8, Lat_watch
    cmp  x4, x8
    b.eq Lnl_copy
    ADRL x1, Ls_l_findmy
    ADRL x8, Lat_findmy
    cmp  x4, x8
    b.eq Lnl_copy
    ADRL x1, Lat_nearby
    cmp  x4, x1
    b.eq Lnl_copy
    mov  x0, x20                      // "Samsung device"
    mov  x1, x21
    ADRL x2, Lf_l_device
    bl   _sfmt
    mov  x0, x20
    LEAVE 0
Lnl_copy:
    mov  x0, x20
    mov  x2, x21
    bl   _strlcpy
    mov  x0, x20
    LEAVE 0
Lnl_none:
    mov  x0, #0
Lnl_ret:
    LEAVE 0


// ===========================================================================
// Where things are: distance from signal strength
// ===========================================================================

// long _dist_dm(long rssi, long tx /*0x7fff: unknown*/) -> about how far, in decimetres; -1 unknown
//   log-distance path loss: rssi = P1m - 10 n log10(d), n = 2.5 indoors,
//   P1m = advertised transmit power - 41 dB, or -59 dBm when not advertised
.globl _dist_dm
_dist_dm:
    ENTER 0
    cmp  x0, #0
    b.ge Ldd_unknown
    mov  x9, #-59
    mov  x10, #0x7fff
    cmp  x1, x10
    b.eq Ldd_have
    sub  x9, x1, #41
Ldd_have:
    sub  x9, x9, x0                   // P1m - rssi
    scvtf d1, x9
    mov  x10, #25
    scvtf d2, x10
    fdiv d1, d1, d2
    mov  x10, #10
    scvtf d0, x10
    bl   _pow                         // 10 ^ ((P1m - rssi) / 25) metres
    mov  x10, #10
    scvtf d1, x10
    fmul d0, d0, d1
    fcvtns x0, d0
    cmp  x0, #1
    mov  x9, #1
    csel x0, x9, x0, lt
    mov  x9, #10000
    cmp  x0, x9
    csel x0, x9, x0, gt
    LEAVE 0
Ldd_unknown:
    mov  x0, #-1
    LEAVE 0

// double _dist_frac(long dm) -> where on the radar: log scale, 1 m .. 30 m at the rim
.globl _dist_frac
_dist_frac:
    ENTER 0
    scvtf d0, x0
    mov  x9, #10
    scvtf d1, x9
    fdiv d0, d0, d1                   // metres
    fmov d1, #1.0
    fadd d0, d0, d1
    bl   _log10
    ADRL x8, Lc_log31
    ldr  d1, [x8]
    fdiv d0, d0, d1
    ADRL x8, Lc_fmin
    ldr  d1, [x8]
    fmax d0, d0, d1
    ADRL x8, Lc_fmax
    ldr  d1, [x8]
    fmin d0, d0, d1
    LEAVE 0

// long _near_dm(long i) -> distance of a nearby device, from its smoothed signal
.globl _near_dm
_near_dm:
    ENTER 0
    NEARE x19, x0
    ldr  x0, [x19, #NR_AVG]
    asr  x0, x0, #4
    mov  x1, #0x7fff
    ldr  x9, [x19, #NR_FLAGS]
    tst  x9, #NF_TX
    b.eq Lnd2_go
    ldr  x1, [x19, #NR_TX]
Lnd2_go:
    bl   _dist_dm
    LEAVE 0

// char *_dist_text(long dm, char *buf) — "≈3 m · in this room"
.globl _dist_text
_dist_text:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    tbnz x19, #63, Ldt_unknown
    cmp  x19, #10
    b.hs Ldt_metres
    mov  x3, #0                       // under a metre: "≈0.6 m"
    mov  x4, x19
    ADRL x5, Lz_here
    ADRL x2, Lf_dist_dec
    b    Ldt_fmt
Ldt_metres:
    add  x3, x19, #5
    mov  x9, #10
    udiv x3, x3, x9
    ADRL x5, Lz_here
    cmp  x19, #15
    b.ls Ldt_whole
    ADRL x5, Lz_room
    cmp  x19, #40
    b.ls Ldt_whole
    ADRL x5, Lz_next
    cmp  x19, #100
    b.ls Ldt_whole
    ADRL x5, Lz_far
Ldt_whole:
    mov  x4, x5
    ADRL x2, Lf_dist
Ldt_fmt:
    mov  x0, x20
    mov  x1, #64
    bl   _sfmt
    mov  x0, x20
    LEAVE 0
Ldt_unknown:
    ADRL x1, Ls_dist_unknown
    mov  x0, x20
    mov  x2, #64
    bl   _strlcpy
    mov  x0, x20
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_retain:            .asciz "retain"
Lf_dist_dec:          .asciz "\342\211\210%ld.%ld m \302\267 %s"
Lf_dist:              .asciz "\342\211\210%ld m \302\267 %s"
Lz_here:              .asciz "right by this Mac"
Lz_room:              .asciz "in this room"
Lz_next:              .asciz "next room / far side"
Lz_far:               .asciz "farther away"
Ls_dist_unknown:      .asciz "distance unknown"
Ls_objectForKey:      .asciz "objectForKey:"
Ls_boolValue:         .asciz "boolValue"
Ls_integerValue:      .asciz "integerValue"
Ls_length:            .asciz "length"
Ls_bytes:             .asciz "bytes"
Ls_count:             .asciz "count"
Ls_objectAtIndex:     .asciz "objectAtIndex:"
Ls_UUIDString:        .asciz "UUIDString"
Ls_UTF8String:        .asciz "UTF8String"
Ls_allKeys:           .asciz "allKeys"
Ls_connectPeripheral: .asciz "connectPeripheral:options:"
Ls_setDelegate:       .asciz "setDelegate:"
Ls_discoverServices:  .asciz "discoverServices:"
Ls_services:          .asciz "services"
Ls_UUID:              .asciz "UUID"
Ls_UUID_key:          .asciz "UUID"
Ls_valueForKey:       .asciz "valueForKey:"
Ls_discoverCharacteristics: .asciz "discoverCharacteristics:forService:"
Ls_characteristics:   .asciz "characteristics"
Ls_readValueForCharacteristic: .asciz "readValueForCharacteristic:"
Ls_value:             .asciz "value"
Ls_comma:             .asciz ", "
Ls_dot:               .asciz " \302\267 "
Lf_fw:                .asciz "firmware %s"
Lf_battery:           .asciz "battery %d%%"
Lf_two:               .asciz "%s \302\267 %s"
Lf_company:           .asciz "maker 0x%04lX"
Ls_k_ble:             .asciz "Bluetooth LE"
Ls_k_matter:          .asciz "Matter (pairing)"
Ls_l_matter:          .asciz "Matter device"
Ls_l_watch:           .asciz "Apple Watch"
Ls_l_findmy:          .asciz "AirTag or Find My item"
Lf_l_device:          .asciz "%s device"
Ls_this_device:       .asciz "this device"
Ls_locked:            .asciz "some details need pairing"
Ls_no_answer:         .asciz "didn't answer (out of range or busy)"
Ls_connecting:        .asciz "\302\267 Connecting to %s\342\200\246 If it needs pairing, macOS will ask you to allow it."
Ls_not_connectable:   .asciz "\302\267 %s only broadcasts; it doesn't accept connections. If it's a headset, keyboard or speaker, put it in pairing mode and use Bluetooth Settings."
Ls_inspected:         .asciz "\302\267 %s: %s"
Ls_inspected_none:    .asciz "\302\267 %s connected, but it doesn't share device details."

Lu_180D: .asciz "180D"
Lu_180F: .asciz "180F"
Lu_180A: .asciz "180A"
Lu_1812: .asciz "1812"
Lu_FE0F: .asciz "FE0F"
Lu_FFF6: .asciz "FFF6"
Lu_FD6F: .asciz "FD6F"
Lu_FEAA: .asciz "FEAA"
Lu_FE2C: .asciz "FE2C"
Lu_FE9F: .asciz "FE9F"
Lu_181A: .asciz "181A"
Lu_1816: .asciz "1816"
Lu_1818: .asciz "1818"
Lu_1826: .asciz "1826"
Lu_181D: .asciz "181D"
Lu_1810: .asciz "1810"
Lu_1809: .asciz "1809"
Lu_FD5A: .asciz "FD5A"
Lu_FEED: .asciz "FEED"
Lu_FEEC: .asciz "FEEC"
Lu_FE07: .asciz "FE07"
Lu_FE03: .asciz "FE03"
Lu_2A29: .asciz "2A29"
Lu_2A24: .asciz "2A24"
Lu_2A26: .asciz "2A26"
Lu_2A19: .asciz "2A19"
Lsn_heart:     .asciz "heart rate"
Lsn_battery:   .asciz "battery"
Lsn_devinfo:   .asciz "device info"
Lsn_hid:       .asciz "keyboard/mouse"
Lsn_hue:       .asciz "Philips Hue"
Lsn_matter:    .asciz "Matter setup"
Lsn_exposure:  .asciz "exposure notification"
Lsn_eddystone: .asciz "Eddystone beacon"
Lsn_fastpair:  .asciz "Google Fast Pair"
Lsn_google:    .asciz "Google"
Lsn_env:       .asciz "environment sensor"
Lsn_cycling:   .asciz "cycling speed"
Lsn_power:     .asciz "cycling power"
Lsn_fitness:   .asciz "fitness machine"
Lsn_scale:     .asciz "weight scale"
Lsn_bp:        .asciz "blood pressure"
Lsn_thermo:    .asciz "thermometer"
Lsn_smarttag:  .asciz "Samsung SmartTag"
Lsn_tile:      .asciz "Tile"
Lsn_sonos:     .asciz "Sonos"
Lsn_alexa:     .asciz "Alexa"
Lm_apple:      .asciz "Apple"
Lm_microsoft:  .asciz "Microsoft"
Lm_samsung:    .asciz "Samsung"
Lm_google:     .asciz "Google"
Lm_garmin:     .asciz "Garmin"
Lm_bose:       .asciz "Bose"
Lm_sony:       .asciz "Sony"
Lm_lg:         .asciz "LG"
Lm_huawei:     .asciz "Huawei"
Lm_xiaomi:     .asciz "Xiaomi"
Lm_amazon:     .asciz "Amazon"
Lm_fitbit:     .asciz "Fitbit"
Lm_polar:      .asciz "Polar"
Lm_nordic:     .asciz "Nordic chip"
Lm_broadcom:   .asciz "Broadcom chip"
Lm_intel:      .asciz "Intel"
Lm_qualcomm:   .asciz "Qualcomm chip"
Lm_espressif:  .asciz "Espressif (ESP32)"
Lat_ibeacon:   .asciz "iBeacon"
Lat_airdrop:   .asciz "AirDrop"
Lat_homekit:   .asciz "HomeKit"
Lat_airpods:   .asciz "AirPods / Beats"
Lat_airplay:   .asciz "AirPlay"
Lat_watch:     .asciz "Watch"
Lat_handoff:   .asciz "Handoff"
Lat_hotspot:   .asciz "Instant Hotspot"
Lat_action:    .asciz "Nearby action"
Lat_nearby:    .asciz "iPhone, iPad or Mac"
Lat_findmy:    .asciz "Find My (AirTag or lost device)"
