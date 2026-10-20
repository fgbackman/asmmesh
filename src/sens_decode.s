// sens_decode.s — reading what Bluetooth sensors broadcast. No connection, no pairing:
// these devices put their readings in every advertisement, and these functions turn
// those bytes into numbers. Pure functions (no Objective-C), so they can be tested
// on their own.
//
//   BTHome v2        service data 0xFCD2 — Shelly BLU buttons, door/window, motion,
//                    H&T; pvvx thermometer firmware; many DIY sensors
//   Xiaomi / pvvx    service data 0x181A — LYWSD03MMC and friends on ATC/pvvx firmware
//   SwitchBot        service data 0xFD3D / 0x0D00 (+ manufacturer 0x0969) — Meter,
//                    Meter Plus, Outdoor Meter, Meter Pro
//   Govee            manufacturer 0xEC88 / 0x0001 / 0x8801 — H5072/5075, H5074,
//                    H5051/5052/5071, H5100-5105/5174/5177, H5179
//   AirPods / Beats  Apple manufacturer data type 0x07 — battery levels (for "batteries")
//
// Every reading is stored in whole hundredths: 2245 = 22.45 °C, 4510 = 45.10 %.

.include "macros.inc"

.section __TEXT,__const
Lbt_size:
.include "sens_bthome.inc"

.text
.p2align 2

// void _rd_clear(rd *r) — nothing known yet
.globl _rd_clear
_rd_clear:
    mov  x9, #0
Lrc_loop:
    str  xzr, [x0, x9]
    add  x9, x9, #8
    cmp  x9, #RD_SIZE
    b.lo Lrc_loop
    mov  x9, #-1
    str  x9, [x0, #RD_PID]
    ret

// ---------------------------------------------------------------------------
// long _sn_bthome(const uint8 *d, long n, rd *r) -> 1 read, 0 not BTHome v2, -1 encrypted
// ---------------------------------------------------------------------------
.globl _sn_bthome
_sn_bthome:
    cmp  x1, #1
    b.lt Lbh_no
    ldrb w9, [x0]                     // device information
    lsr  w10, w9, #5
    cmp  w10, #2                      // version 2 only
    b.ne Lbh_no
    tbnz w9, #0, Lbh_enc              // encrypted: needs a key we don't have
    mov  x3, #1
    ADRL x11, Lbt_size
Lbh_loop:
    cmp  x3, x1
    b.hs Lbh_yes
    ldrb w4, [x0, x3]                 // object id
    ldrb w5, [x11, x4]                // its size
    cbz  w5, Lbh_yes                  // an id we don't know: keep what came before it
    add  x6, x3, #1                   // its data
    cmp  w5, #0xFE
    b.eq Lbh_var
    cmp  w5, #0xFD
    b.eq Lbh_cmd
    add  x7, x6, x5
    cmp  x7, x1
    b.hi Lbh_yes                      // cut short
    mov  x8, #0                       // little-endian value
    mov  x12, x5
Lbh_rd:
    cbz  x12, Lbh_have
    sub  x12, x12, #1
    add  x13, x6, x12
    ldrb w13, [x0, x13]
    orr  x8, x13, x8, lsl #8
    b    Lbh_rd
Lbh_have:
    mov  x3, x7
    cmp  w4, #0x00
    b.eq Lbh_pid
    cmp  w4, #0x01
    b.eq Lbh_batt
    cmp  w4, #0x02
    b.eq Lbh_t001
    cmp  w4, #0x03
    b.eq Lbh_hum
    cmp  w4, #0x04
    b.eq Lbh_press
    cmp  w4, #0x05
    b.eq Lbh_lux
    cmp  w4, #0x12
    b.eq Lbh_co2
    cmp  w4, #0x14
    b.eq Lbh_moist
    cmp  w4, #0x2E
    b.eq Lbh_hum1
    cmp  w4, #0x2F
    b.eq Lbh_moist1
    cmp  w4, #0x3A
    b.eq Lbh_button
    cmp  w4, #0x45
    b.eq Lbh_t01
    cmp  w4, #0x57
    b.eq Lbh_t1
    cmp  w4, #0x58
    b.eq Lbh_t035
    sub  w9, w4, #0x0F                // binary sensors 0x0F..0x2D
    cmp  w9, #(0x2D - 0x0F)
    b.ls Lbh_bin
    b    Lbh_loop
Lbh_pid:
    str  x8, [x2, #RD_PID]
    b    Lbh_loop
Lbh_batt:
    str  x8, [x2, #RD_BATT]
    mov  x9, #H_BATT
    b    Lbh_flag
Lbh_t001:                             // sint16 x 0.01
    sxth x8, w8
    b    Lbh_temp
Lbh_t01:                              // sint16 x 0.1
    sxth x8, w8
    mov  x9, #10
    mul  x8, x8, x9
    b    Lbh_temp
Lbh_t1:                               // sint8 x 1
    sxtb x8, w8
    mov  x9, #100
    mul  x8, x8, x9
    b    Lbh_temp
Lbh_t035:                             // sint8 x 0.35
    sxtb x8, w8
    mov  x9, #35
    mul  x8, x8, x9
Lbh_temp:
    str  x8, [x2, #RD_TEMP]
    mov  x9, #H_TEMP
    b    Lbh_flag
Lbh_hum1:
    mov  x9, #100
    mul  x8, x8, x9
Lbh_hum:
    str  x8, [x2, #RD_HUM]
    mov  x9, #H_HUM
    b    Lbh_flag
Lbh_moist1:
    mov  x9, #100
    mul  x8, x8, x9
Lbh_moist:
    str  x8, [x2, #RD_MOIST]
    mov  x9, #H_MOIST
    b    Lbh_flag
Lbh_press:
    str  x8, [x2, #RD_PRESS]
    mov  x9, #H_PRESS
    b    Lbh_flag
Lbh_lux:
    str  x8, [x2, #RD_LUX]
    mov  x9, #H_LUX
    b    Lbh_flag
Lbh_co2:
    str  x8, [x2, #RD_CO2]
    mov  x9, #H_CO2
Lbh_flag:
    ldr  x10, [x2, #RD_HAVE]
    orr  x10, x10, x9
    str  x10, [x2, #RD_HAVE]
    b    Lbh_loop
Lbh_bin:                              // bit (id - 0x0F): seen, and its state
    mov  x10, #1
    lsl  x10, x10, x9
    ldr  x12, [x2, #RD_BINHAVE]
    orr  x12, x12, x10
    str  x12, [x2, #RD_BINHAVE]
    ldr  x12, [x2, #RD_BIN]
    bic  x12, x12, x10
    cmp  x8, #0
    csel x10, xzr, x10, eq
    orr  x12, x12, x10
    str  x12, [x2, #RD_BIN]
    b    Lbh_loop
Lbh_button:                           // each 0x3A is the next button (1, 2, 3, 4)
    ldr  x9, [x2, #RD_NBTN]
    cmp  x9, #4
    b.hs Lbh_loop
    add  x10, x2, #RD_BTN
    strb w8, [x10, x9]
    add  x9, x9, #1
    str  x9, [x2, #RD_NBTN]
    b    Lbh_loop
Lbh_var:                              // text / raw: [length] then data
    cmp  x6, x1
    b.hs Lbh_yes
    ldrb w5, [x0, x6]
    add  x6, x6, #1
    b    Lbh_skip
Lbh_cmd:                              // command: [args length] opcode args
    cmp  x6, x1
    b.hs Lbh_yes
    ldrb w5, [x0, x6]
    and  w5, w5, #31
    add  w5, w5, #1
    add  x6, x6, #1
Lbh_skip:
    add  x7, x6, x5
    cmp  x7, x1
    b.hi Lbh_yes
    mov  x3, x7
    b    Lbh_loop
Lbh_yes:
    mov  x9, #SK_BTHOME
    str  x9, [x2, #RD_KIND]
    mov  x0, #1
    ret
Lbh_enc:
    mov  x0, #-1
    ret
Lbh_no:
    mov  x0, #0
    ret

// ---------------------------------------------------------------------------
// long _sn_xiaomi(const uint8 *d, long n, rd *r) — service data 0x181A
//   13 bytes, atc1441: mac[6] temp s16 BE x0.1, humidity %, battery %, mV BE, count
//   15 bytes, pvvx:    mac[6] temp s16 LE x0.01, humidity u16 LE x0.01, mV, battery %, ...
// ---------------------------------------------------------------------------
.globl _sn_xiaomi
_sn_xiaomi:
    cmp  x1, #13
    b.eq Lxi_atc
    cmp  x1, #15
    b.eq Lxi_pvvx
    mov  x0, #0
    ret
Lxi_atc:
    ldrb w9, [x0, #6]
    ldrb w10, [x0, #7]
    orr  w9, w10, w9, lsl #8
    sxth x9, w9
    mov  x10, #10
    mul  x9, x9, x10
    str  x9, [x2, #RD_TEMP]
    ldrb w9, [x0, #8]
    mov  x10, #100
    mul  x9, x9, x10
    str  x9, [x2, #RD_HUM]
    ldrb w9, [x0, #9]
    str  x9, [x2, #RD_BATT]
    b    Lxi_done
Lxi_pvvx:
    ldrh w9, [x0, #6]
    sxth x9, w9
    str  x9, [x2, #RD_TEMP]
    ldrh w9, [x0, #8]
    str  x9, [x2, #RD_HUM]
    ldrb w9, [x0, #12]
    str  x9, [x2, #RD_BATT]
Lxi_done:
    ldr  x9, [x2, #RD_HAVE]
    orr  x9, x9, #(H_TEMP | H_HUM | H_BATT)
    str  x9, [x2, #RD_HAVE]
    mov  x9, #SK_XIAOMI
    str  x9, [x2, #RD_KIND]
    mov  x0, #1
    ret

// ---------------------------------------------------------------------------
// long _sn_switchbot(const uint8 *sd, long sdn, const uint8 *mfr, long mfrn, rd *r)
//   sd: service data 0xFD3D / 0x0D00; mfr: manufacturer data with its company id, or 0
// ---------------------------------------------------------------------------
.globl _sn_switchbot
_sn_switchbot:
    cmp  x1, #3
    b.lt Lsb_no
    ldrb w9, [x0]
    and  w9, w9, #0x7f                // the model letter
    cmp  w9, #'T'
    b.eq Lsb_meter
    cmp  w9, #'t'
    b.eq Lsb_meter
    cmp  w9, #'i'
    b.eq Lsb_meter
    cmp  w9, #'I'
    b.eq Lsb_meter
    cmp  w9, #'w'
    b.eq Lsb_meter
    cmp  w9, #'W'
    b.eq Lsb_meter
    cmp  w9, #'4'
    b.eq Lsb_meter
    cmp  w9, #0x14
    b.eq Lsb_meter
Lsb_no:
    mov  x0, #0
    ret
Lsb_meter:
    ldrb w9, [x0, #2]
    and  w9, w9, #0x7f
    str  x9, [x4, #RD_BATT]
    ldr  x10, [x4, #RD_HAVE]
    orr  x10, x10, #H_BATT
    str  x10, [x4, #RD_HAVE]
    mov  x11, #0                      // where temperature and humidity are
    cbz  x2, Lsb_sd
    cmp  x3, #13
    b.lt Lsb_sd
    ldrh w9, [x2]
    mov  w10, #0x0969
    cmp  w9, w10
    b.ne Lsb_sd
    add  x11, x2, #10                 // newer firmware: in the manufacturer data
    b    Lsb_th
Lsb_sd:
    cmp  x1, #6
    b.lt Lsb_done
    add  x11, x0, #3
Lsb_th:
    ldrb w9, [x11, #1]
    and  w10, w9, #0x7f
    mov  w12, #10
    mul  w10, w10, w12
    ldrb w12, [x11]
    and  w12, w12, #0x0f
    add  w10, w10, w12                // tenths of a degree
    ldrb w12, [x11, #2]
    and  w12, w12, #0x7f              // humidity %
    orr  w13, w10, w12
    cbz  w13, Lsb_done                // all zero: not measured yet
    sxtw x10, w10
    tst  w9, #0x80                    // bit 7 set: above zero
    b.ne Lsb_pos
    neg  x10, x10
Lsb_pos:
    mov  x13, #10
    mul  x10, x10, x13
    str  x10, [x4, #RD_TEMP]
    mov  x13, #100
    mul  x12, x12, x13
    str  x12, [x4, #RD_HUM]
    ldr  x10, [x4, #RD_HAVE]
    orr  x10, x10, #(H_TEMP | H_HUM)
    str  x10, [x4, #RD_HAVE]
Lsb_done:
    mov  x9, #SK_SWITCHBOT
    str  x9, [x4, #RD_KIND]
    mov  x0, #1
    ret

// ---------------------------------------------------------------------------
// long _sn_govee(const uint8 *mfr, long n, const char *name /*or 0*/, rd *r)
//   mfr includes its 2-byte company id
// ---------------------------------------------------------------------------
.globl _sn_govee
_sn_govee:
    cmp  x1, #8
    b.lt Lgv_no
    ldrh w9, [x0]
    sub  x1, x1, #2                   // payload length
    add  x0, x0, #2                   // payload
    cmp  x1, #25                      // macOS sometimes glues Govee's iBeacon
    b.le Lgv_kind                     // ("INTELLI_ROCKS…", 25 bytes) onto the end
    mov  x10, #0
Lgv_ir:
    add  x11, x10, #7
    cmp  x11, x1
    b.hi Lgv_kind
    ldrb w11, [x0, x10]
    cmp  w11, #'I'
    b.ne Lgv_ir_next
    add  x12, x0, x10
    ldrb w11, [x12, #1]
    cmp  w11, #'N'
    b.ne Lgv_ir_next
    ldrb w11, [x12, #2]
    cmp  w11, #'T'
    b.ne Lgv_ir_next
    ldrb w11, [x12, #3]
    cmp  w11, #'E'
    b.ne Lgv_ir_next
    ldrb w11, [x12, #4]
    cmp  w11, #'L'
    b.ne Lgv_ir_next
    sub  x1, x1, #25
    b    Lgv_kind
Lgv_ir_next:
    add  x10, x10, #1
    b    Lgv_ir
Lgv_kind:
    mov  w10, #0xEC88
    cmp  w9, w10
    b.eq Lgv_ec88
    cmp  w9, #1
    b.eq Lgv_0001
    mov  w10, #0x8801
    cmp  w9, w10
    b.eq Lgv_8801
Lgv_no:
    mov  x0, #0
    ret
Lgv_ec88:
    cmp  x1, #6                       // H5072 / H5075: packed at 1, battery at 4
    b.eq Lgv_pack1
    cmp  x1, #7                       // H5074: s16 / u16 / battery at 1
    b.eq Lgv_le1
    cmp  x1, #9                       // H5051 / H5052 / H5071: the same at 1
    b.eq Lgv_le1
    b    Lgv_no
Lgv_0001:                             // company 1 is shared: only with a Govee name
    cmp  x1, #6
    b.eq Lgv_0001_name
    cmp  x1, #8
    b.ne Lgv_no
Lgv_0001_name:
    cbz  x2, Lgv_no
    ldrb w9, [x2]
    ldrb w10, [x2, #1]
    cmp  w9, #'G'
    b.ne Lgv_h5
    cmp  w10, #'V'
    b.eq Lgv_pack2
    cmp  w10, #'o'
    b.eq Lgv_pack2
    b    Lgv_no
Lgv_h5:
    cmp  w9, #'H'
    b.ne Lgv_no
    cmp  w10, #'5'
    b.ne Lgv_no
Lgv_pack2:                            // H5100-H5105 / H5174 / H5177: packed at 2, battery at 5
    add  x0, x0, #1
Lgv_pack1:
    ldrb w9, [x0, #1]
    ldrb w10, [x0, #2]
    ldrb w11, [x0, #3]
    lsl  w9, w9, #16
    orr  w9, w9, w10, lsl #8
    orr  w9, w9, w11
    ldrb w12, [x0, #4]                // battery, bit 7 = error
    and  w13, w12, #0x7f
    str  x13, [x3, #RD_BATT]
    ldr  x10, [x3, #RD_HAVE]
    orr  x10, x10, #H_BATT
    str  x10, [x3, #RD_HAVE]
    tbnz w12, #7, Lgv_yes
    and  w10, w9, #0x7fffff
    mov  w11, #1000
    udiv w14, w10, w11                // tenths of a degree
    msub w15, w14, w11, w10           // tenths of a percent
    mov  w11, #10
    mul  w14, w14, w11
    mul  w15, w15, w11
    sxtw x14, w14
    tst  w9, #0x800000
    b.eq Lgv_pk_pos
    neg  x14, x14
Lgv_pk_pos:
    mov  x9, x14
    mov  x10, x15
    b    Lgv_store
Lgv_le1:
    ldrh w9, [x0, #1]
    sxth x9, w9
    ldrh w10, [x0, #3]
    ldrb w11, [x0, #5]
    str  x11, [x3, #RD_BATT]
    b    Lgv_store_b
Lgv_8801:                             // H5179: at 4
    cmp  x1, #9
    b.ne Lgv_no
    ldrh w9, [x0, #4]
    sxth x9, w9
    ldrh w10, [x0, #6]
    ldrb w11, [x0, #8]
    str  x11, [x3, #RD_BATT]
Lgv_store_b:
    ldr  x11, [x3, #RD_HAVE]
    orr  x11, x11, #H_BATT
    str  x11, [x3, #RD_HAVE]
Lgv_store:                            // x9 temperature, x10 humidity (hundredths)
    mov  x11, #-4000                  // outside -40..100 °C: a bad reading
    cmp  x9, x11
    b.lt Lgv_yes
    mov  x11, #10000
    cmp  x9, x11
    b.gt Lgv_yes
    str  x9, [x3, #RD_TEMP]
    str  x10, [x3, #RD_HUM]
    ldr  x11, [x3, #RD_HAVE]
    orr  x11, x11, #(H_TEMP | H_HUM)
    str  x11, [x3, #RD_HAVE]
Lgv_yes:
    mov  x9, #SK_GOVEE
    str  x9, [x3, #RD_KIND]
    mov  x0, #1
    ret

// ---------------------------------------------------------------------------
// long _sn_airpods(const uint8 *mfr, long n, long out[6]) — Apple proximity pairing
//   out: model, left %, right %, case % (-1 not known), charging bits, status
// ---------------------------------------------------------------------------
.globl _sn_airpods
_sn_airpods:
    cmp  x1, #10
    b.lt Lap_no
    ldrh w9, [x0]
    cmp  w9, #0x4C
    b.ne Lap_no
    ldrb w9, [x0, #2]
    cmp  w9, #7
    b.ne Lap_no
    ldrb w9, [x0, #4]
    cmp  w9, #1
    b.ne Lap_no
    ldrh w9, [x0, #5]
    str  x9, [x2]
    ldrb w9, [x0, #8]                 // right << 4 | left, tens of percent
    and  w10, w9, #15
    mov  x11, #-1
    cmp  w10, #15
    b.eq Lap_l
    mov  w11, #100
    cmp  w10, #10
    b.hi Lap_l
    mov  w12, #10
    mul  w11, w10, w12
Lap_l:
    str  x11, [x2, #8]
    lsr  w10, w9, #4
    mov  x11, #-1
    cmp  w10, #15
    b.eq Lap_r
    mov  w11, #100
    cmp  w10, #10
    b.hi Lap_r
    mov  w12, #10
    mul  w11, w10, w12
Lap_r:
    str  x11, [x2, #16]
    ldrb w9, [x0, #9]                 // charging << 4 | case
    and  w10, w9, #15
    mov  x11, #-1
    cmp  w10, #15
    b.eq Lap_c
    mov  w11, #100
    cmp  w10, #10
    b.hi Lap_c
    mov  w12, #10
    mul  w11, w10, w12
Lap_c:
    str  x11, [x2, #24]
    lsr  w10, w9, #4
    str  x10, [x2, #32]
    ldrb w9, [x0, #7]
    str  x9, [x2, #40]
    mov  x0, #1
    ret
Lap_no:
    mov  x0, #0
    ret
