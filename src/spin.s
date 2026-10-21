// spin.s — the SPIN remote (Spin Remote SDC1), a Bluetooth LE rotary/gesture puck,
// as an input device for asmmesh. Spin it, tap it, swipe its top; each gesture drives
// your lights, TV, rooms — and a long press is a panic button.
//
// Protocol reverse-engineered from the SPIN remote Android app (see docs/spin_protocol.md).
//   interaction service  5E5A10D3-6EC7-17AF-D743-3CF1679C1CC7
//     action char        182BEC1F-51A4-458E-4B48-C431EA701A3B   notify, 1 byte = gesture
//   LED service          BDF1ED51-6FF4-9DB7-F646-007627DD7DF3
//     colour char        4A60B963-AD6A-53A0-DE4D-DBD27386F8F1   write 3 bytes R,G,B
// No proprietary handshake: we just subscribe to notifications. macOS may ask to pair
// the remote the first time; that's normal.
//
// gesture bytes (from the app's enum):
//   0/1 spin CW/CCW (right side up)   2/3 on its side   4/5 upside down
//   6-9 swipe up/down/left/right      10-14 press N/S/E/W/center
//   15-19 long-press N/S/E/W/center   20/21 touch-scroll CW/CCW
//   22 double-tap the shell           23/24 sleep/wake

.include "macros.inc"

.set SP_CW1,   0
.set SP_CCW1,  1
.set SP_CW2,   2
.set SP_CCW2,  3
.set SP_CW3,   4
.set SP_CCW3,  5
.set SP_UP,    6
.set SP_DOWN,  7
.set SP_LEFT,  8
.set SP_RIGHT, 9
.set SP_PN,    10
.set SP_PS,    11
.set SP_PE,    12
.set SP_PW,    13
.set SP_PC,    14
.set SP_LPN,   15
.set SP_LPC,   19
.set SP_SCW,   20
.set SP_SCCW,  21
.set SP_DTAP,  22

.data
.p2align 3
.globl _g_spin_p
_g_spin_p:      .quad 0               // the connected SPIN (retained), or 0
_g_spin_act:    .quad 0               // its action characteristic (retained)
_g_spin_led:    .quad 0               // its LED characteristic (retained), or 0
_g_spin_cmd:    .quad 0               // its command characteristic (retained), or 0
	.globl _g_spin_ready
_g_spin_ready:  .quad 0
_g_spin_target: .quad 0               // 0 lights, 1 TV
_g_spin_debug:  .quad 0               // print every gesture to Home
_g_spin_u_svc:  .quad 0               // CBUUIDs, built once
_g_spin_u_act:  .quad 0
_g_spin_u_lsvc: .quad 0
_g_spin_u_led:  .quad 0
_g_spin_u_cmd:  .quad 0
	.globl _g_spin_gcur
_g_spin_gcur:   .quad -1              // the group the SPIN drives now (colour index), -1 none
	.globl _g_spin_lock
_g_spin_lock:   .quad 0               // 1: "spin off" — gestures are shown, nothing is sent
_g_spin_gstate: .quad 0               // bit i: we last turned group i on (for the toggle)
_g_spin_last:   .quad 0               // CFAbsoluteTime of the last spin step we acted on
.zerofill __DATA,__bss,_g_spin_rgb,8,4
.zerofill __DATA,__bss,_g_spin_line,256,4
.globl _g_spin_groups
.zerofill __DATA,__bss,_g_spin_groups,2304,4   // 9 groups x 256: "Kitchen lamp, Porch"
.set NGROUP, 9                        // red … cyan: the first 9 colours

.text
.p2align 2

// id _spin_uuid(const char *s) — a retained CBUUID
_spin_uuid:
    ENTER 0
    bl   _nsstr
    mov  x19, x0
    CLS  Ls_CBUUID
    mov  x2, x19
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    LEAVE 0

// void _spin_init(void) — build the CBUUIDs and read the saved target
.globl _spin_init
_spin_init:
    ENTER 16
    ADRL x8, _g_spin_u_svc
    ldr  x9, [x8]
    cbnz x9, Lsi_pref
    ADRL x0, Ls_u_svc
    bl   _spin_uuid
    ADRL x8, _g_spin_u_svc
    str  x0, [x8]
    ADRL x0, Ls_u_act
    bl   _spin_uuid
    ADRL x8, _g_spin_u_act
    str  x0, [x8]
    ADRL x0, Ls_u_lsvc
    bl   _spin_uuid
    ADRL x8, _g_spin_u_lsvc
    str  x0, [x8]
    ADRL x0, Ls_u_led
    bl   _spin_uuid
    ADRL x8, _g_spin_u_led
    str  x0, [x8]
    ADRL x0, Ls_u_cmd
    bl   _spin_uuid
    ADRL x8, _g_spin_u_cmd
    str  x0, [x8]
Lsi_pref:
    ADRL x0, Ls_pref_target
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #96]
    cmp  w9, #'t'
    cset x9, eq
    ADRL x8, _g_spin_target
    str  x9, [x8]
    bl   _spin_groups_load
    LEAVE 16

// long _spin_is(const char *nameUTF8 /*or 0*/, id advDict) -> 1 if this looks like a SPIN
.globl _spin_is
_spin_is:
    ENTER 0
    mov  x19, x1
    cbz  x0, Lis_adv
    ADRL x1, Ls_name_spin
    bl   _strcasestr
    cbnz x0, Lis_yes
Lis_adv:
    cbz  x19, Lis_no
    LDGOT x8, _CBAdvertisementDataServiceUUIDsKey
    ldr  x2, [x8]
    mov  x0, x19
    MSG1 Ls_objectForKey
    cbz  x0, Lis_no
    ADRL x8, _g_spin_u_svc
    ldr  x2, [x8]
    cbz  x2, Lis_no
    MSG1 Ls_containsObject
    tst  w0, #0xff
    b.ne Lis_yes
Lis_no:
    mov  x0, #0
    LEAVE 0
Lis_yes:
    mov  x0, #1
    LEAVE 0

// long _spin_seen(id peripheral, const char *nameUTF8, id advDict) -> 1 if it's a SPIN
//   (and, if we have none yet, we start connecting to it). Called from the scan.
.globl _spin_seen
_spin_seen:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, x20
    mov  x1, x21
    bl   _spin_is
    cbz  x0, Lss_no
    mov  x0, #SVC_SPIN                // SPIN switched off: don't link to it
    bl   _svc_on
    cbz  x0, Lss_no
    ADRL x8, _g_spin_p                // already have one? then just claim the advert
    ldr  x9, [x8]
    cbnz x9, Lss_yes
    mov  x0, x19
    MSG0 Ls_retain
    ADRL x8, _g_spin_p
    str  x0, [x8]
    ADRL x8, _g_cm
    ldr  x0, [x8]
    mov  x2, x19
    mov  x3, #0
    MSG2 Ls_connectPeripheral
    ADRL x0, Ls_msg_found
    bl   _chat_line
Lss_yes:
    mov  x0, #1
    LEAVE 0
Lss_no:
    mov  x0, #0
    LEAVE 0

// long _spin_connected(id peripheral) -> 1 if it's our SPIN
.globl _spin_connected
_spin_connected:
    ENTER 16
    mov  x19, x0
    ADRL x8, _g_spin_p
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne Lsc_no
    ADRL x8, _g_ctl
    ldr  x2, [x8]
    mov  x0, x19
    MSG1 Ls_setDelegate
    ADRL x8, _g_spin_u_svc            // discover both services: [svc, lsvc]
    ldr  x9, [x8]
    str  x9, [sp, #96]
    ADRL x8, _g_spin_u_lsvc
    ldr  x9, [x8]
    str  x9, [sp, #104]
    CLS  Ls_NSArray
    add  x2, sp, #96
    mov  x3, #2
    MSG2 Ls_arrayWithObjects
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_discoverServices
    mov  x0, #1
    LEAVE 16
Lsc_no:
    mov  x0, #0
    LEAVE 16

// long _spin_services(id peripheral, id err) -> 1 if handled
.globl _spin_services
_spin_services:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_spin_p
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne Lsv2_no
    cbnz x20, Lsv2_yes                // error: give up quietly
    mov  x0, x19
    MSG0 Ls_services
    mov  x21, x0
    cbz  x21, Lsv2_yes
    MSG0 Ls_count
    mov  x22, x0
    mov  x23, #0
Lsv2_loop:
    cmp  x23, x22
    b.hs Lsv2_yes
    mov  x0, x21
    mov  x2, x23
    MSG1 Ls_objectAtIndex
    mov  x24, x0                      // service
    mov  x2, #0                       // all characteristics (nil)
    mov  x3, x24                      // for this service
    mov  x0, x19                      // ask the peripheral
    MSG2 Ls_discoverCharacteristics2
    add  x23, x23, #1
    b    Lsv2_loop
Lsv2_yes:
    mov  x0, #1
    LEAVE 0
Lsv2_no:
    mov  x0, #0
    LEAVE 0

// long _spin_chars(id peripheral, id service, id err) -> 1 if handled
.globl _spin_chars
_spin_chars:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_spin_p
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne Lch2_no
    cbnz x21, Lch2_yes
    mov  x0, x20
    MSG0 Ls_characteristics
    mov  x22, x0
    cbz  x22, Lch2_yes
    MSG0 Ls_count
    mov  x23, x0
    mov  x24, #0
Lch2_loop:
    cmp  x24, x23
    b.hs Lch2_yes
    mov  x0, x22
    mov  x2, x24
    MSG1 Ls_objectAtIndex
    mov  x20, x0                      // characteristic (x19-x24 only: they are saved)
    MSG0 Ls_UUID
    mov  x21, x0
    ADRL x8, _g_spin_u_act
    ldr  x2, [x8]
    mov  x0, x21
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.ne Lch2_act
    ADRL x8, _g_spin_u_led
    ldr  x2, [x8]
    mov  x0, x21
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.ne Lch2_ledc
    ADRL x8, _g_spin_u_cmd
    ldr  x2, [x8]
    mov  x0, x21
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.ne Lch2_cmdc
    b    Lch2_next
Lch2_cmdc:                            // the command channel: ask for every gesture
    mov  x0, x20
    MSG0 Ls_retain
    ADRL x8, _g_spin_cmd
    str  x0, [x8]
    ADRL x0, Lcmd_force
    mov  x1, #2
    bl   _spin_cmd_write
    bl   _spin_apply_color
    b    Lch2_next
Lch2_act:
    mov  x0, x20
    MSG0 Ls_retain
    ADRL x8, _g_spin_act
    str  x0, [x8]
    mov  x0, x19                      // subscribe to notifications
    mov  x2, #1
    mov  x3, x20
    MSG2 Ls_setNotifyValue
    mov  x9, #1
    ADRL x8, _g_spin_ready
    str  x9, [x8]
    ADRL x0, Ls_msg_linked
    bl   _chat_line
    ADRL x8, _g_spin_lock
    ldr  x9, [x8]
    cbz  x9, Lch2_unlocked
    ADRL x0, Ls_lock_on
    bl   _chat_line
Lch2_unlocked:
    bl   _ui_update_status
    b    Lch2_next
Lch2_ledc:
    mov  x0, x20
    MSG0 Ls_retain
    ADRL x8, _g_spin_led
    str  x0, [x8]
    bl   _spin_apply_color             // the colour you chose, if any
Lch2_next:
    add  x24, x24, #1
    b    Lch2_loop
Lch2_yes:                             // leave the ring alone: its colour is your SPIN profile
    mov  x0, #1
    LEAVE 0
Lch2_no:
    mov  x0, #0
    LEAVE 0

// long _spin_value(id peripheral, id chr, id err) -> 1 if it was our action char
.globl _spin_value
_spin_value:
    ENTER 16
    mov  x19, x1                      // characteristic
    mov  x20, x2                      // error
    ADRL x8, _g_spin_act
    ldr  x9, [x8]
    cbz  x9, Lval_no
    mov  x0, x19
    MSG0 Ls_UUID
    ADRL x8, _g_spin_u_act
    ldr  x2, [x8]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.eq Lval_no
    cbnz x20, Lval_yes
    mov  x0, x19
    MSG0 Ls_value
    cbz  x0, Lval_yes
    mov  x19, x0
    MSG0 Ls_length
    cbz  x0, Lval_yes
    mov  x0, x19
    MSG0 Ls_bytes
    ldrb w1, [x0]                     // the gesture's action may ask something: run it once
    ADRL x0, _spin_act                //   this Bluetooth callback is over
    bl   _main_later
Lval_yes:
    mov  x0, #1
    LEAVE 16
Lval_no:
    mov  x0, #0
    LEAVE 16

// void _spin_lost(id peripheral) — the SPIN went away
.globl _spin_lost
_spin_lost:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_spin_p
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne Lsl_done
    ldr  x0, [x8]
    cbz  x0, Lsl_clr
    MSG0 Ls_release
Lsl_clr:
    ADRL x8, _g_spin_p
    str  xzr, [x8]
    ADRL x8, _g_spin_act
    ldr  x0, [x8]
    cbz  x0, Lsl_led
    MSG0 Ls_release
    ADRL x8, _g_spin_act
    str  xzr, [x8]
Lsl_led:
    ADRL x8, _g_spin_led
    ldr  x0, [x8]
    cbz  x0, Lsl_flag
    MSG0 Ls_release
    ADRL x8, _g_spin_led
    str  xzr, [x8]
Lsl_flag:
    ADRL x8, _g_spin_cmd
    ldr  x0, [x8]
    cbz  x0, Lsl_flag2
    MSG0 Ls_release
    ADRL x8, _g_spin_cmd
    str  xzr, [x8]
Lsl_flag2:
    ADRL x8, _g_spin_ready
    ldr  x9, [x8]
    str  xzr, [x8]
    cbz  x9, Lsl_done
    ADRL x0, Ls_msg_lost
    bl   _chat_line
    bl   _ui_update_status
Lsl_done:
    LEAVE 0

// void _spin_cmd_write(const uint8 *bytes, long len) — to the command characteristic
_spin_cmd_write:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_spin_cmd
    ldr  x21, [x8]
    cbz  x21, Lcw_done
    CLS  Ls_NSData
    mov  x2, x19
    mov  x3, x20
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    ADRL x8, _g_spin_p
    ldr  x0, [x8]
    mov  x3, x21
    mov  x4, #0                       // with response
    MSG3 Ls_writeValue
Lcw_done:
    LEAVE 0

// void _spin_led(long r, long g, long b) — colour the ring (0..255 each)
.globl _spin_led
_spin_led:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_spin_cmd
    ldr  x9, [x8]
    cbz  x9, Lled_old
    ADRL x8, _g_spin_rgb              // newer firmware: SET_LED_COLOR 09 R G B
    mov  w9, #9
    strb w9, [x8]
    strb w19, [x8, #1]
    strb w20, [x8, #2]
    strb w21, [x8, #3]
    ADRL x0, _g_spin_rgb
    mov  x1, #4
    bl   _spin_cmd_write
    LEAVE 0
Lled_old:
    ADRL x8, _g_spin_led              // older firmware: R G B to the LED characteristic
    ldr  x22, [x8]
    cbz  x22, Lled_done
    ADRL x8, _g_spin_rgb
    strb w19, [x8]
    strb w20, [x8, #1]
    strb w21, [x8, #2]
    CLS  Ls_NSData
    ADRL x2, _g_spin_rgb
    mov  x3, #3
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    ADRL x8, _g_spin_p
    ldr  x0, [x8]
    mov  x3, x22
    mov  x4, #0
    MSG3 Ls_writeValue
Lled_done:
    LEAVE 0

// void _spin_do(const char *cmd) — run a device command and show it in Home
_spin_do:
    ENTER 0
    bl   _run_text
    LEAVE 0

// void _spin_flash_g(void) — a brief brighter-green tick
_spin_flash_g:                        // no-op: keep the ring on your profile colour
    ret

// void _spin_room(long dir) — dir +1 next room, -1 previous
_spin_room:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_room_count
    ldr  x20, [x8]
    cmp  x20, #1
    b.ls Lrm3_done
    ADRL x8, _g_cur_room
    ldr  x9, [x8]
    add  x9, x9, x19
    cmp  x9, x20
    b.lo Lrm3_lo
    mov  x9, #0
    b    Lrm3_sel
Lrm3_lo:
    tbz  x9, #63, Lrm3_sel
    sub  x9, x20, #1
Lrm3_sel:
    mov  x0, x9
    bl   _ui_select_room
Lrm3_done:
    LEAVE 0

// void _spin_sos(void) — the long-press panic button
.globl _spin_sos
_spin_sos:
    ENTER 0
    mov  x0, #255                     // ring red
    mov  x1, #0
    mov  x2, #0
    bl   _spin_led
    bl   _alerts_sos                  // the mesh, your phone, and where you are (alerts.s)
    bl   _ui_update_status
    LEAVE 0

// void _spin_act(long code) — a gesture happened
.globl _spin_act
_spin_act:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_spin_target
    ldr  x20, [x8]                    // 0 lights, 1 tv
    ADRL x8, _g_spin_debug
    ldr  x9, [x8]
    cbz  x9, Lact_go
    mov  x0, x19                      // debug: show the raw gesture
    ADRL x8, Lspin_names
    mov  x10, #25
    cmp  x19, x10
    csel x9, x10, x19, hs
    tbz  x19, #63, Lact_dbg_idx
    mov  x9, x10
Lact_dbg_idx:
    ldr  x2, [x8, x9, lsl #3]
    mov  x1, x2
    mov  x2, x19
    ADRL x0, Ls_dbg_fmt
    bl   _home_say
Lact_go:
    mov  x0, x19                      // the SPIN window lights the row up; in test mode
    bl   _sui_seen                    //   that's all that happens
    cbnz x0, Lact_done
    mov  x0, #SVC_SPIN                // switched off while linked: ignore it
    bl   _svc_on
    cbz  x0, Lact_done
    ADRL x8, _g_spin_lock             // "spin off": only the panic button still works
    ldr  x9, [x8]
    cbz  x9, Lact_unlocked
    cmp  x19, #SP_LPC
    b.eq Lact_sos
    b    Lact_done
Lact_unlocked:
    bl   _spin_ghave                  // profiles set up? then their gesture maps rule
    cbz  x0, Lact_legacy
    mov  x0, x19
    bl   _sui_gesture
    b    Lact_done
    cmp  x19, #SP_DTAP                // double-tap / swipe: next or previous group
    b.eq Lg_next
    cmp  x19, #SP_RIGHT
    b.eq Lg_next
    cmp  x19, #SP_LEFT
    b.eq Lg_prev
    cmp  x19, #SP_LPC
    b.eq Lact_sos
    ADRL x8, _g_spin_gcur
    ldr  x9, [x8]
    tbz  x9, #63, Lg_have
    mov  x0, #1                       // none picked yet: the first one
    bl   _spin_gnext
Lg_have:
    cmp  x19, #SP_UP
    b.eq Lg_on
    cmp  x19, #SP_DOWN
    b.eq Lg_off
    cmp  x19, #SP_PC
    b.eq Lg_toggle
    cmp  x19, #SP_SCW
    b.eq Lg_up
    cmp  x19, #SP_SCCW
    b.eq Lg_down
    cmp  x19, #SP_CCW3
    b.hi Lact_done
    tst  x19, #1                      // even = clockwise
    b.ne Lg_down
Lg_up:
    bl   _spin_throttle
    cbz  x0, Lact_done
    mov  x0, #0
    bl   _spin_gdo
    b    Lact_done
Lg_down:
    bl   _spin_throttle
    cbz  x0, Lact_done
    mov  x0, #1
    bl   _spin_gdo
    b    Lact_done
Lg_on:
    mov  x0, #2
    bl   _spin_gdo
    b    Lact_done
Lg_off:
    mov  x0, #3
    bl   _spin_gdo
    b    Lact_done
Lg_toggle:
    mov  x0, #4
    bl   _spin_gdo
    b    Lact_done
Lg_next:
    mov  x0, #1
    bl   _spin_gnext
    b    Lact_done
Lg_prev:
    mov  x0, #-1
    bl   _spin_gnext
    b    Lact_done
Lact_legacy:
    cmp  x19, #SP_DTAP                // double-tap: switch what the spin drives
    b.eq Lact_switch
    cmp  x19, #SP_LPC                // long-press centre: SOS
    b.eq Lact_sos
    cmp  x19, #SP_SCW                // touch-scroll / swipe sideways: change room
    b.eq Lact_next
    cmp  x19, #SP_RIGHT
    b.eq Lact_next
    cmp  x19, #SP_SCCW
    b.eq Lact_prev
    cmp  x19, #SP_LEFT
    b.eq Lact_prev
    cmp  x19, #SP_UP                 // swipe up/down: lights on/off (whole home)
    b.eq Lact_allon
    cmp  x19, #SP_DOWN
    b.eq Lact_alloff
    cmp  x19, #SP_PC                 // press centre: mute TV, or toggle this room off
    b.eq Lact_center

    // spins: any clockwise is "up", any counter-clockwise is "down"
    cmp  x19, #SP_CW3
    b.hi Lact_done                   // 6+ handled above; >5 that reach here: ignore
    and  x9, x19, #1                 // even = CW (up), odd = CCW (down)
    cbnz x9, Lact_down
Lact_up:
    ADRL x21, Ls_c_brighter
    cbz  x20, Lact_up_go
    ADRL x21, Ls_c_louder
Lact_up_go:
    bl   _spin_flash_g
    mov  x0, x21
    bl   _spin_do
    b    Lact_done
Lact_down:
    ADRL x21, Ls_c_dimmer
    cbz  x20, Lact_down_go
    ADRL x21, Ls_c_quieter
Lact_down_go:
    bl   _spin_flash_g
    mov  x0, x21
    bl   _spin_do
    b    Lact_done
Lact_next:
    bl   _spin_flash_b
    mov  x0, #1
    bl   _spin_room
    b    Lact_done
Lact_prev:
    bl   _spin_flash_b
    mov  x0, #-1
    bl   _spin_room
    b    Lact_done
Lact_allon:
    bl   _spin_flash_b
    ADRL x0, Ls_c_allon
    bl   _spin_do
    b    Lact_done
Lact_alloff:
    bl   _spin_flash_b
    ADRL x0, Ls_c_alloff
    bl   _spin_do
    b    Lact_done
Lact_center:
    bl   _spin_flash_b
    ADRL x0, Ls_c_lightsoff
    cbz  x20, Lact_center_go
    ADRL x0, Ls_c_mute
Lact_center_go:
    bl   _spin_do
    b    Lact_done
Lact_switch:
    eor  x20, x20, #1
    ADRL x8, _g_spin_target
    str  x20, [x8]
    ADRL x0, Ls_t_tv
    ADRL x1, Ls_t_lights
    ADRL x9, Ls_f_val
    cmp  x20, #0
    csel x0, x1, x0, eq
    ADRL x8, Ls_pref_target
    mov  x1, x0
    mov  x0, x8
    bl   _pref_set
    ADRL x0, Ls_t_tv
    ADRL x8, Ls_t_lights
    cmp  x20, #0
    csel x0, x8, x0, eq
    mov  x1, x0
    ADRL x0, Ls_f_switch
    bl   _home_say
    b    Lact_done
Lact_sos:
    bl   _spin_sos
Lact_done:
    LEAVE 0

// void _spin_flash_b(void) — a brief blue tick
_spin_flash_b:                        // no-op: keep the ring on your profile colour
    ret

// const char *_spin_colour(long i) -> x0 its name, x1 0x00RRGGBB (leaf)
.globl _spin_colour
_spin_colour:
    ADRL x8, Lspin_colors
    add  x8, x8, x0, lsl #4
    ldr  x1, [x8, #8]
    ldr  x0, [x8]
    ret

// long _spin_color_find(const char *name) -> index into Lspin_colors, or -1
_spin_color_find:
    ENTER 0
    mov  x19, x0
    ADRL x20, Lspin_colors
    mov  x21, #0
Lcf_loop:
    ldr  x1, [x20]
    cbz  x1, Lcf_none
    mov  x0, x19
    bl   _strcmp
    cbz  w0, Lcf_hit
    add  x20, x20, #16
    add  x21, x21, #1
    b    Lcf_loop
Lcf_hit:
    mov  x0, x21
    LEAVE 0
Lcf_none:
    mov  x0, #-1
    LEAVE 0

// void _spin_color_idx(long i) — paint the ring with colour i
_spin_color_idx:
    ENTER 0
    ADRL x8, Lspin_colors
    add  x8, x8, x0, lsl #4
    ldr  w9, [x8, #8]                  // packed 0x00RRGGBB
    tbnz w9, #24, Lci_normal
    lsr  w0, w9, #16
    and  w0, w0, #0xff
    lsr  w1, w9, #8
    and  w1, w1, #0xff
    and  w2, w9, #0xff
    bl   _spin_led
    LEAVE 0
Lci_normal:                           // CANCEL_LED_OVERRIDE: the remote's own colours
    ADRL x0, Lcmd_normal
    mov  x1, #1
    bl   _spin_cmd_write
    LEAVE 0

// void _spin_apply_color(void) — the saved colour, when the ring is reachable
.globl _spin_apply_color
_spin_apply_color:
    ENTER 32
    ADRL x8, _g_spin_gcur             // driving a group: the ring shows its colour
    ldr  x0, [x8]
    tbnz x0, #63, Lac_pref
    bl   _spin_color_idx
    LEAVE 32
Lac_pref:
    ADRL x0, Ls_pref_color
    add  x1, sp, #96
    mov  x2, #24
    bl   _pref_get
    ldrb w9, [sp, #96]
    cbz  w9, Lac_done
    add  x0, sp, #96
    bl   _spin_color_find
    tbnz x0, #63, Lac_done
    bl   _spin_color_idx
Lac_done:
    LEAVE 32

// "spin color red" — choose the ring colour (saved; applied whenever it links)
.globl _h_spin_color
_h_spin_color:
    ENTER 0
    mov  x19, x1
    ldrb w9, [x19]
    cbz  w9, Lsc3_list
    mov  x0, x19
    bl   _spin_color_find
    tbnz x0, #63, Lsc3_list
    mov  x20, x0
    ADRL x0, Ls_pref_color
    mov  x1, x19
    bl   _pref_set
    ADRL x8, _g_spin_ready
    ldr  x9, [x8]
    cbz  x9, Lsc3_later
    mov  x0, x20
    bl   _spin_color_idx
    ADRL x0, Ls_col_set
    mov  x1, x19
    bl   _home_say
    LEAVE 0
Lsc3_later:
    ADRL x0, Ls_col_later
    mov  x1, x19
    bl   _home_say
    LEAVE 0
Lsc3_list:
    ADRL x0, Ls_col_list
    bl   _home_say0
    LEAVE 0

// ---------------------------------------------------------------------------
// Home-room words
// ---------------------------------------------------------------------------

// "spin" — status and the gesture map
.globl _h_spin
_h_spin:
    ENTER 0
    bl   _sui_show                    // the SPIN window, like the remote's own app
    ADRL x8, _g_spin_ready
    ldr  x9, [x8]
    cbnz x9, Lhs3_on
    ADRL x8, _g_spin_p
    ldr  x9, [x8]
    cbz  x9, Lhs3_off
    ADRL x0, Ls_st_connecting
    bl   _home_say0
    b    Lhs3_map
Lhs3_off:
    bl   _spin_bt_say
    cbz  x0, Lhs3_map
    ADRL x0, Ls_st_off
    bl   _home_say0
    b    Lhs3_map
Lhs3_on:
    ADRL x8, _g_spin_target
    ldr  x9, [x8]
    ADRL x0, Ls_st_lights
    ADRL x8, Ls_st_tv
    cmp  x9, #0
    csel x0, x8, x0, ne
    bl   _home_say0
Lhs3_map:
    ADRL x8, _g_spin_lock
    ldr  x9, [x8]
    cbz  x9, Lhs3_nolock
    ADRL x0, Ls_lock_on
    bl   _home_say0
Lhs3_nolock:
    bl   _spin_ghave
    cbz  x0, Lhs3_old
    ADRL x0, Ls_gmap1
    bl   _home_say0
    ADRL x0, Ls_gmap2
    bl   _home_say0
    bl   _h_spin_groups
    LEAVE 0
Lhs3_old:
    ADRL x0, Ls_map1
    bl   _home_say0
    ADRL x0, Ls_map2
    bl   _home_say0
    ADRL x0, Ls_map3
    bl   _home_say0
    ADRL x0, Ls_g_usage
    bl   _home_say0
    LEAVE 0

// "spin debug" — show every gesture as it arrives
.globl _h_spin_debug
_h_spin_debug:
    ENTER 0
    ADRL x8, _g_spin_debug
    ldr  x9, [x8]
    eor  x9, x9, #1
    str  x9, [x8]
    ADRL x0, Ls_dbg_on
    ADRL x8, Ls_dbg_off
    cmp  x9, #0
    csel x0, x8, x0, eq
    bl   _home_say0
    LEAVE 0

// "connect spin" / "pair spin"
.globl _h_spin_connect
_h_spin_connect:
    ENTER 0
    bl   _spin_bt_say
    cbz  x0, Lhsc_done
    ADRL x8, _g_spin_ready
    ldr  x9, [x8]
    cbz  x9, Lhsc_scan
    ADRL x0, Ls_already
    bl   _home_say0
    LEAVE 0
Lhsc_scan:
    ADRL x0, Ls_scanning
    bl   _home_say0
Lhsc_done:
    LEAVE 0

// long _spin_bt_say(void) -> 1 if Bluetooth is on and allowed; otherwise says why
//   in Home (a rebuilt, ad-hoc signed asmmesh has to be allowed Bluetooth again)
_spin_bt_say:
    ENTER 0
    ADRL x8, _g_cm
    ldr  x0, [x8]
    cbz  x0, Lbs_wait
    MSG0 Ls_state
    cmp  x0, #5                       // powered on
    b.eq Lbs_ok
    cmp  x0, #4
    b.eq Lbs_off
    cmp  x0, #3
    b.eq Lbs_denied
Lbs_wait:
    ADRL x0, Ls_bt_wait               // unknown / resetting: usually the prompt is waiting
    b    Lbs_say
Lbs_off:
    ADRL x0, Ls_bt_off
    b    Lbs_say
Lbs_denied:
    ADRL x0, Ls_bt_denied
Lbs_say:
    bl   _home_say0
    mov  x0, #0
    LEAVE 0
Lbs_ok:
    mov  x0, #1
    LEAVE 0

// "spin controls the tv" / "spin controls the lights"
.globl _h_spin_target
_h_spin_target:
    ENTER 0
    mov  x19, x1
    mov  x0, x19
    ADRL x1, Ls_w_tv
    bl   _strcasestr
    cbz  x0, Lhst_lights
    mov  x20, #1
    b    Lhst_set
Lhst_lights:
    mov  x20, #0
Lhst_set:
    ADRL x8, _g_spin_target
    str  x20, [x8]
    ADRL x0, Ls_t_tv
    ADRL x8, Ls_t_lights
    cmp  x20, #0
    csel x1, x8, x0, eq
    ADRL x0, Ls_pref_target
    bl   _pref_set
    ADRL x0, Ls_t_tv
    ADRL x8, Ls_t_lights
    cmp  x20, #0
    csel x1, x8, x0, eq
    ADRL x0, Ls_f_switch
    bl   _home_say
    LEAVE 0

// ---------------------------------------------------------------------------

// ===========================================================================
// Colour groups: "spin group green kitchen lamp, desk lamp". Double-tap the SPIN
// (or swipe left/right) to step through the groups; the ring turns that group's
// colour and spins, swipes and presses act on just those devices.
// ===========================================================================

// char *_spin_gkey(long i, char *buf /*32*/) -> "spin_g_green"
_spin_gkey:
    ENTER 0
    mov  x19, x1
    ADRL x8, Lspin_colors
    lsl  x9, x0, #4
    ldr  x9, [x8, x9]
    str  x9, [sp]
    mov  x0, x19
    mov  x1, #32
    ADRL x2, Ls_gkey_fmt
    bl   _snprintf
    mov  x0, x19
    LEAVE 0

// void _spin_groups_load(void) — the saved groups, the current one, the lock
_spin_groups_load:
    ENTER 32
    mov  x19, #0
Lgl_loop:
    cmp  x19, #NGROUP
    b.hs Lgl_cur
    mov  x0, x19
    add  x1, sp, #96
    bl   _spin_gkey
    add  x0, sp, #96
    ADRL x8, _g_spin_groups
    add  x1, x8, x19, lsl #8
    mov  x2, #256
    bl   _pref_get
    add  x19, x19, #1
    b    Lgl_loop
Lgl_cur:
    ADRL x0, Ls_pref_group
    add  x1, sp, #96
    mov  x2, #32
    bl   _pref_get
    mov  x20, #-1
    ldrb w9, [sp, #96]
    cbz  w9, Lgl_set
    add  x0, sp, #96
    bl   _spin_color_find
    tbnz x0, #63, Lgl_set
    cmp  x0, #NGROUP
    b.hs Lgl_set
    ADRL x8, _g_spin_groups
    lsl  x9, x0, #8
    ldrb w9, [x8, x9]
    cbz  w9, Lgl_set
    mov  x20, x0
Lgl_set:
    ADRL x8, _g_spin_gcur
    str  x20, [x8]
    ADRL x0, Ls_pref_lock
    add  x1, sp, #96
    mov  x2, #8
    bl   _pref_get
    ldrb w9, [sp, #96]                // locked unless you've said "spin on"
    cmp  w9, #'0'
    cset x9, ne
    ADRL x8, _g_spin_lock
    str  x9, [x8]
    bl   _sui_load                    // each profile's name and gesture map
    LEAVE 32

// long _spin_ghave(void) -> 1 if any group has devices
.globl _spin_ghave
_spin_ghave:
    ENTER 0
    mov  x20, #0
Lgh_loop:
    cmp  x20, #NGROUP
    b.hs Lgh_no
    mov  x0, x20
    bl   _sui_enabled
    add  x20, x20, #1
    cbz  x0, Lgh_loop
    mov  x0, #1
    LEAVE 0
Lgh_no:
    mov  x0, #0
    LEAVE 0

// long _spin_throttle(void) -> 1 if a quarter second has passed since the last
//   spin step we acted on (a spin sends a burst; each step is a network request)
.globl _spin_throttle
_spin_throttle:
    ENTER 0
    bl   _CFAbsoluteTimeGetCurrent
    ADRL x8, _g_spin_last
    ldr  d1, [x8]
    fsub d2, d0, d1
    ADRL x9, Ld_spin_gap
    ldr  d3, [x9]
    fcmp d2, d3
    b.lt Lth_no
    str  d0, [x8]
    mov  x0, #1
    LEAVE 0
Lth_no:
    mov  x0, #0
    LEAVE 0

// char *_spin_next_item(const char *p, char *out /*64*/) -> just past the next
//   comma-separated name (copied trimmed into out), or 0 when none are left
.globl _spin_next_item
_spin_next_item:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
Lni_skip:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.eq Lni_adv
    cmp  w9, #','
    b.ne Lni_start
Lni_adv:
    add  x19, x19, #1
    b    Lni_skip
Lni_start:
    cbz  w9, Lni_none
    mov  x21, #0
Lni_copy:
    ldrb w9, [x19]
    cbz  w9, Lni_trim
    cmp  w9, #','
    b.eq Lni_trim
    add  x19, x19, #1
    cmp  x21, #62
    b.hs Lni_copy
    strb w9, [x20, x21]
    add  x21, x21, #1
    b    Lni_copy
Lni_trim:
    cbz  x21, Lni_end
    sub  x9, x21, #1
    ldrb w10, [x20, x9]
    cmp  w10, #' '
    b.ne Lni_end
    mov  x21, x9
    b    Lni_trim
Lni_end:
    strb wzr, [x20, x21]
    mov  x0, x19
    LEAVE 0
Lni_none:
    strb wzr, [x20]
    mov  x0, #0
    LEAVE 0

// void _spin_and_commas(char *s) — "a and b" -> "a,b" (in place)
_spin_and_commas:
    ENTER 0
    mov  x19, x0                      // read
    mov  x20, x0                      // write
Lanc_loop:
    ldrb w9, [x19]
    cbz  w9, Lanc_end
    mov  x0, x19
    ADRL x1, Ls_and_sp
    mov  x2, #5
    bl   _strncasecmp
    cbnz w0, Lanc_copy
    mov  w9, #','
    strb w9, [x20], #1
    add  x19, x19, #5
    b    Lanc_loop
Lanc_copy:
    ldrb w9, [x19], #1
    strb w9, [x20], #1
    b    Lanc_loop
Lanc_end:
    strb wzr, [x20]
    LEAVE 0

// void _spin_gstore(long i, const char *names) — keep and save a group
_spin_gstore:
    ENTER 32
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_spin_groups
    add  x0, x8, x19, lsl #8
    mov  x1, x20
    mov  x2, #256
    bl   _strlcpy
    mov  x0, x19
    add  x1, sp, #96
    bl   _spin_gkey
    add  x0, sp, #96
    mov  x1, x20
    bl   _pref_set
    LEAVE 32

// void _spin_gselect(long i) — drive group i: ring colour, saved, said in Home
.globl _spin_gselect
_spin_gselect:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_spin_gcur
    str  x19, [x8]
    ADRL x8, Lspin_colors
    lsl  x9, x19, #4
    ldr  x20, [x8, x9]
    ADRL x0, Ls_pref_group
    mov  x1, x20
    bl   _pref_set
    mov  x0, x19
    bl   _spin_color_idx
    ADRL x8, Lspin_dots
    ldr  x1, [x8, x19, lsl #3]
    mov  x2, x20
    ADRL x8, _g_spin_groups
    add  x3, x8, x19, lsl #8
    ADRL x0, Lf_g_sel
    bl   _home_say
    LEAVE 0

// long _spin_gnext(long dir) -> 1 if it moved to the next (+1) / previous (-1) group
.globl _spin_gnext
_spin_gnext:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_spin_gcur
    ldr  x20, [x8]
    mov  x21, #0
Lgn_loop:
    cmp  x21, #NGROUP
    b.hs Lgn_none
    add  x21, x21, #1
    add  x20, x20, x19
    cmp  x20, #NGROUP
    b.lt Lgn_lo
    mov  x20, #0
Lgn_lo:
    tbz  x20, #63, Lgn_chk
    mov  x20, #(NGROUP - 1)
Lgn_chk:
    mov  x0, x20
    bl   _sui_enabled
    cbz  x0, Lgn_loop
    mov  x0, x20
    bl   _spin_gselect
    mov  x0, #1
    LEAVE 0
Lgn_none:
    mov  x0, #0
    LEAVE 0

// void _spin_gdo(long what) — 0 brighter/louder, 1 dimmer/quieter, 2 on, 3 off,
//   4 toggle — on every device of the current group
.globl _spin_gdo
_spin_gdo:
    ENTER 336                         // [96] names, [352] one name
    mov  x19, x0
    ADRL x8, _g_spin_gcur
    ldr  x20, [x8]
    tbnz x20, #63, Lgd_done
    ADRL x8, _g_spin_groups
    add  x1, x8, x20, lsl #8
    ldrb w9, [x1]
    cbz  w9, Lgd_done
    add  x0, sp, #96
    mov  x2, #256
    bl   _strlcpy
    cmp  x19, #4
    b.ne Lgd_remember
    // toggle: anything on -> all off; anything known off -> all on; else our last
    add  x21, sp, #96
    mov  x22, #0                      // 1: something is on
    mov  x23, #0                      // 1: we know some state
Lgt_item:
    mov  x0, x21
    add  x1, sp, #352
    bl   _spin_next_item
    cbz  x0, Lgt_decide
    mov  x21, x0
    add  x0, sp, #352
    bl   _dev_by_name
    tbnz x0, #63, Lgt_item
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    ldr  x9, [x8, #D_ON]
    tbnz x9, #63, Lgt_item
    mov  x23, #1
    cmp  x9, #1
    b.ne Lgt_item
    mov  x22, #1
Lgt_decide:
    mov  x19, #3                      // off
    cbnz x22, Lgd_remember
    mov  x19, #2                      // on
    cbnz x23, Lgd_remember
    ADRL x8, _g_spin_gstate
    ldr  x9, [x8]
    lsr  x9, x9, x20
    tbz  x9, #0, Lgd_remember
    mov  x19, #3
Lgd_remember:
    cmp  x19, #2
    b.lo Lgd_run
    ADRL x8, _g_spin_gstate
    ldr  x9, [x8]
    mov  x10, #1
    lsl  x10, x10, x20
    orr  x11, x9, x10
    bic  x12, x9, x10
    cmp  x19, #2
    csel x9, x11, x12, eq
    str  x9, [x8]
Lgd_run:
    add  x21, sp, #96
Lgd_item:
    mov  x0, x21
    add  x1, sp, #352
    bl   _spin_next_item
    cbz  x0, Lgd_done
    mov  x21, x0
    add  x0, sp, #352
    bl   _dev_by_name
    tbnz x0, #63, Lgd_item
    mov  x22, x0
    ADRL x8, _g_devs
    add  x23, x8, x22, lsl #DEV_SHIFT
    ldr  x24, [x23, #D_CAPS]
    cmp  x19, #2
    b.eq Lgd_on
    cmp  x19, #3
    b.eq Lgd_off
    cmp  x19, #5
    b.hs Lgd_media
    tst  x24, #CAP_LEVEL              // a light: 10% steps
    b.ne Lgd_level
    tst  x24, #CAP_VOLUME             // a TV or speaker: volume
    b.eq Lgd_item
    mov  x9, #A_VOLUP
    mov  x10, #A_VOLDOWN
    cmp  x19, #0
    csel x9, x9, x10, eq
    mov  x10, #0
    b    Lgd_exec
Lgd_level:
    ldr  x10, [x23, #D_LEVEL]
    tbz  x10, #63, Lgd_known
    mov  x10, #50
Lgd_known:
    ldr  x11, [x23, #D_ON]            // off: brighter starts from dark,
    cbnz x11, Lgd_step                //   dimmer leaves it off
    cbnz x19, Lgd_item
    mov  x10, #0
Lgd_step:
    cbnz x19, Lgd_down
    add  x10, x10, #10
    cmp  x10, #100
    mov  x11, #100
    csel x10, x11, x10, hi
    b    Lgd_lset
Lgd_down:
    subs x10, x10, #10
    b.gt Lgd_lset
    mov  x10, #1
Lgd_lset:
    mov  x9, #A_LEVEL
    b    Lgd_exec
Lgd_on:
    mov  x9, #A_ON
    mov  x10, #0
    b    Lgd_exec
Lgd_off:
    mov  x9, #A_OFF
    mov  x10, #0
Lgd_media:                            // 5.. louder, quieter, mute, play, pause, channel up/down:
    ADRL x8, Lgd_kinds                //   only the devices that can
    sub  x9, x19, #5
    cmp  x9, #7
    b.hs Lgd_item
    add  x8, x8, x9, lsl #4
    ldp  x10, x9, [x8]
    tst  x24, x10
    b.eq Lgd_item
    mov  x10, #0
Lgd_exec:
    ADRL x8, _g_cmd_action
    str  x9, [x8]
    ADRL x8, _g_cmd_value
    str  x10, [x8]
    ADRL x8, _g_cmd_word
    str  xzr, [x8]
    mov  x0, x22
    bl   _exec_one
    b    Lgd_item
Lgd_done:
    LEAVE 336

// "spin group green kitchen lamp, desk lamp" / "spin group green clear"
.globl _h_spin_group
_h_spin_group:
    ENTER 784                         // [96] names, [352] one, [448] kept, [704] unknown
    mov  x19, x1
    mov  x20, x2
    mov  x9, #0                       // the colour word
Lhg_w:
    ldrb w10, [x19, x9]
    cbz  w10, Lhg_wend
    cmp  w10, #' '
    b.eq Lhg_wend
    cmp  x9, #30
    b.hs Lhg_wend
    add  x11, sp, #352
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    Lhg_w
Lhg_wend:
    add  x11, sp, #352
    strb wzr, [x11, x9]
    mov  x21, x9
    cbz  x9, Lhg_usage
    add  x0, sp, #352
    bl   _spin_color_find
    tbnz x0, #63, Lhg_usage
    cmp  x0, #NGROUP
    b.hs Lhg_usage
    mov  x22, x0
    add  x1, x20, x21                 // the names, as typed
Lhg_sp:
    ldrb w9, [x1]
    cmp  w9, #' '
    b.ne Lhg_sp_done
    add  x1, x1, #1
    b    Lhg_sp
Lhg_sp_done:
    add  x0, sp, #96
    mov  x2, #256
    bl   _strlcpy
    ldrb w9, [sp, #96]
    cbz  w9, Lhg_show
    add  x0, sp, #96
    ADRL x1, Ls_w_clear
    bl   _strcasecmp
    cbz  w0, Lhg_clear
    add  x0, sp, #96
    ADRL x1, Ls_w_none
    bl   _strcasecmp
    cbz  w0, Lhg_clear
    add  x0, sp, #96
    ADRL x1, Ls_w_nothing
    bl   _strcasecmp
    cbz  w0, Lhg_clear
    add  x0, sp, #96
    bl   _spin_and_commas
    strb wzr, [sp, #448]
    strb wzr, [sp, #704]
    add  x23, sp, #96
    mov  x24, #0                      // devices kept
Lhg_item:
    mov  x0, x23
    add  x1, sp, #352
    bl   _spin_next_item
    cbz  x0, Lhg_built
    mov  x23, x0
    add  x0, sp, #352
    bl   _dev_by_name
    tbnz x0, #63, Lhg_miss
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    add  x21, x8, #D_NAME
    cbz  x24, Lhg_first
    add  x0, sp, #448
    ADRL x1, Ls_comma_sp
    mov  x2, #256
    bl   _strlcat
Lhg_first:
    add  x0, sp, #448
    mov  x1, x21
    mov  x2, #256
    bl   _strlcat
    add  x24, x24, #1
    b    Lhg_item
Lhg_miss:
    ldrb w9, [sp, #704]
    cbz  w9, Lhg_miss1
    add  x0, sp, #704
    ADRL x1, Ls_comma_sp
    mov  x2, #72
    bl   _strlcat
Lhg_miss1:
    add  x0, sp, #704
    add  x1, sp, #352
    mov  x2, #72
    bl   _strlcat
    b    Lhg_item
Lhg_built:
    ldrb w9, [sp, #704]
    cbz  w9, Lhg_nomiss
    add  x1, sp, #704
    ADRL x0, Lf_g_miss
    bl   _home_say
Lhg_nomiss:
    cbz  x24, Lhg_done                // nothing usable: the group stays as it was
    mov  x0, x22
    add  x1, sp, #448
    bl   _spin_gstore
    mov  x0, x22
    bl   _spin_gselect
    ADRL x0, Ls_g_tip
    bl   _home_say0
    b    Lhg_done
Lhg_show:                             // "spin group green": what's in it
    ADRL x8, _g_spin_groups
    add  x9, x8, x22, lsl #8
    ldrb w10, [x9]
    cbz  w10, Lhg_empty
    mov  x0, x22
    bl   _spin_gselect
    b    Lhg_done
Lhg_clear:
    mov  x0, x22
    ADRL x1, Ls_nothing
    bl   _spin_gstore
    ADRL x8, _g_spin_gcur
    ldr  x9, [x8]
    cmp  x9, x22
    b.ne Lhg_empty
    mov  x9, #-1
    str  x9, [x8]
    ADRL x0, Ls_pref_group
    ADRL x1, Ls_nothing
    bl   _pref_set
    mov  x0, #1                       // move on to another group, if any
    bl   _spin_gnext
Lhg_empty:
    ADRL x8, Lspin_colors
    lsl  x9, x22, #4
    ldr  x1, [x8, x9]
    ADRL x0, Lf_g_cleared
    bl   _home_say
    b    Lhg_done
Lhg_usage:
    ADRL x0, Ls_g_usage
    bl   _home_say0
    ADRL x0, Ls_g_usage2
    bl   _home_say0
Lhg_done:
    LEAVE 784

// "spin groups" — every group and what's in it
.globl _h_spin_groups
_h_spin_groups:
    ENTER 0
    mov  x19, #0
    mov  x20, #0
Lhgs_loop:
    cmp  x19, #NGROUP
    b.hs Lhgs_end
    ADRL x8, _g_spin_groups
    add  x21, x8, x19, lsl #8
    ldrb w9, [x21]
    cbz  w9, Lhgs_next
    add  x20, x20, #1
    ADRL x8, Lspin_dots
    ldr  x1, [x8, x19, lsl #3]
    ADRL x8, Lspin_colors
    lsl  x9, x19, #4
    ldr  x2, [x8, x9]
    mov  x3, x21
    ADRL x0, Lf_g_line
    ADRL x8, _g_spin_gcur
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne Lhgs_say
    ADRL x0, Lf_g_line_cur
Lhgs_say:
    bl   _home_say
Lhgs_next:
    add  x19, x19, #1
    b    Lhgs_loop
Lhgs_end:
    cbnz x20, Lhgs_done
    ADRL x0, Ls_g_none
    bl   _home_say0
    ADRL x0, Ls_g_usage2
    bl   _home_say0
Lhgs_done:
    LEAVE 0

// "spin off" (arg 1) / "spin on" (arg 0) — a lock, so handling it changes nothing
.globl _h_spin_lock
_h_spin_lock:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_spin_lock
    str  x19, [x8]
    ADRL x1, Ls_zero
    ADRL x9, Ls_one
    cmp  x19, #0
    csel x1, x9, x1, ne
    ADRL x0, Ls_pref_lock
    bl   _pref_set
    ADRL x0, Ls_lock_on
    ADRL x9, Ls_lock_off
    cmp  x19, #0
    csel x0, x9, x0, eq
    bl   _home_say0
    LEAVE 0

.section __DATA,__const
.p2align 3
Lcmd_force:  .byte 8, 1               // FORCE_ACTION_NOTIFICATION on
Lcmd_normal: .byte 7                  // CANCEL_LED_OVERRIDE
.p2align 3
Lspin_colors:                          // name, 0x00RRGGBB (bit 24: back to the profile colour)
    .quad Lc_red,    0xFF0000
    .quad Lc_green,  0x00FF00
    .quad Lc_blue,   0x0000FF
    .quad Lc_white,  0xFFFFFF
    .quad Lc_orange, 0xFF7800
    .quad Lc_yellow, 0xFFDC00
    .quad Lc_purple, 0x9600FF
    .quad Lc_pink,   0xFF3CA0
    .quad Lc_cyan,   0x00DCFF
    .quad Lc_off,    0x000000
    .quad Lc_normal, 0x1000000
    .quad Lc_auto,   0x1000000
    .quad 0, 0

Lspin_dots:
    .quad Ld0,Ld1,Ld2,Ld3,Ld4,Ld5,Ld6,Ld7,Ld8
Ld_spin_gap: .double 0.25

Lgd_kinds:                             // capability needed, action
    .quad CAP_VOLUME, A_VOLUP
    .quad CAP_VOLUME, A_VOLDOWN
    .quad (CAP_MUTE | CAP_VOLUME), A_MUTE
    .quad CAP_MEDIA, A_PLAY
    .quad CAP_MEDIA, A_PAUSE
    .quad CAP_CHANNEL, A_CHUP
    .quad CAP_CHANNEL, A_CHDOWN

Lspin_names:
    .quad Lg0,Lg1,Lg2,Lg3,Lg4,Lg5,Lg6,Lg7,Lg8,Lg9,Lg10,Lg11,Lg12
    .quad Lg13,Lg14,Lg15,Lg16,Lg17,Lg18,Lg19,Lg20,Lg21,Lg22,Lg23,Lg24
    .quad Lgu

.section __TEXT,__cstring,cstring_literals
Ls_gkey_fmt: .asciz "spin_g_%s"
Ls_pref_group: .asciz "spin_group"
Ls_pref_lock: .asciz "spin_lock"
Ls_and_sp: .asciz " and "
Ls_comma_sp: .asciz ", "
Ls_nothing: .asciz ""
Ls_zero: .asciz "0"
Ls_one: .asciz "1"
Ls_w_clear: .asciz "clear"
Ls_w_none: .asciz "none"
Ls_w_nothing: .asciz "nothing"
Lf_g_sel: .asciz "\302\267 %s The SPIN now drives the %s group: %s"
Lf_g_miss: .asciz "\302\267 \342\232\240\357\270\217 I couldn\342\200\231t find: %s. Say \342\200\234list devices\342\200\235 to see the exact names."
Lf_g_cleared: .asciz "\302\267 The %s group is empty."
Lf_g_line: .asciz "\302\267 %s %s: %s"
Lf_g_line_cur: .asciz "\302\267 %s %s: %s  \342\227\200 now"
Ls_g_tip: .asciz "\302\267 Double-tap the SPIN (or swipe left/right) to switch groups \342\200\224 the ring shows which one. Spin: brighter/dimmer. Press the top: on/off. Swipe up/down: on/off."
Ls_g_usage: .asciz "\302\267 Make a colour group: \342\200\234spin group green kitchen lamp, desk lamp\342\200\235. Colours: red, green, blue, white, orange, yellow, purple, pink, cyan."
Ls_g_usage2: .asciz "\302\267 \342\200\234spin groups\342\200\235 lists them, \342\200\234spin group green clear\342\200\235 empties one, \342\200\234list devices\342\200\235 shows the names to use."
Ls_g_none: .asciz "\302\267 No colour groups yet."
Ls_gmap1: .asciz "\302\267 Double-tap or swipe left/right: next group (the ring turns its colour). Spin: brighter / dimmer (TVs: louder / quieter)."
Ls_gmap2: .asciz "\302\267 Press the top: that group on / off. Swipe up / down: on / off. Long-press: \360\237\206\230 SOS. \342\200\234spin off\342\200\235 locks the remote."
Ls_lock_on: .asciz "\302\267 \360\237\224\222 SPIN locked \342\200\224 gestures do nothing (only the long-press SOS still works). Say \342\200\234spin on\342\200\235 to use it again."
Ls_lock_off: .asciz "\302\267 \360\237\224\223 SPIN on \342\200\224 gestures control your devices again."
Ld0: .asciz "\360\237\224\264"
Ld1: .asciz "\360\237\237\242"
Ld2: .asciz "\360\237\224\265"
Ld3: .asciz "\342\232\252\357\270\217"
Ld4: .asciz "\360\237\237\240"
Ld5: .asciz "\360\237\237\241"
Ld6: .asciz "\360\237\237\243"
Ld7: .asciz "\360\237\251\267"
Ld8: .asciz "\360\237\251\265"
Lc_red:    .asciz "red"
Lc_green:  .asciz "green"
Lc_blue:   .asciz "blue"
Lc_white:  .asciz "white"
Lc_orange: .asciz "orange"
Lc_yellow: .asciz "yellow"
Lc_purple: .asciz "purple"
Lc_pink:   .asciz "pink"
Lc_cyan:   .asciz "cyan"
Lc_off:    .asciz "off"
Lc_normal: .asciz "normal"
Lc_auto:   .asciz "auto"
Ls_pref_color: .asciz "spin_color"
Ls_col_set:    .asciz "\302\267 \360\237\224\230 SPIN ring set to %s."
Ls_col_later:  .asciz "\302\267 \360\237\224\230 Saved %s \342\200\224 it goes on the ring as soon as the SPIN links to this Mac."
Ls_col_list:   .asciz "\302\267 Colours: red, green, blue, white, orange, yellow, purple, pink, cyan, off, or normal (the remote\342\200\231s own colours) \342\200\224 e.g. \342\200\234spin color blue\342\200\235."
Lg0:  .asciz "spin clockwise"
Lg1:  .asciz "spin counter-clockwise"
Lg2:  .asciz "spin clockwise (on its side)"
Lg3:  .asciz "spin counter-clockwise (on its side)"
Lg4:  .asciz "spin clockwise (upside down)"
Lg5:  .asciz "spin counter-clockwise (upside down)"
Lg6:  .asciz "swipe up"
Lg7:  .asciz "swipe down"
Lg8:  .asciz "swipe left"
Lg9:  .asciz "swipe right"
Lg10: .asciz "press north"
Lg11: .asciz "press south"
Lg12: .asciz "press east"
Lg13: .asciz "press west"
Lg14: .asciz "press centre"
Lg15: .asciz "long-press north"
Lg16: .asciz "long-press south"
Lg17: .asciz "long-press east"
Lg18: .asciz "long-press west"
Lg19: .asciz "long-press centre"
Lg20: .asciz "touch-scroll clockwise"
Lg21: .asciz "touch-scroll counter-clockwise"
Lg22: .asciz "double-tap"
Lg23: .asciz "going to sleep"
Lg24: .asciz "waking up"
Lgu:  .asciz "unknown"
Ls_u_svc:    .asciz "5E5A10D3-6EC7-17AF-D743-3CF1679C1CC7"
Ls_u_act:    .asciz "182BEC1F-51A4-458E-4B48-C431EA701A3B"
Ls_u_lsvc:   .asciz "BDF1ED51-6FF4-9DB7-F646-007627DD7DF3"
Ls_u_led:    .asciz "4A60B963-AD6A-53A0-DE4D-DBD27386F8F1"
Ls_u_cmd:    .asciz "92E92B18-FA20-D486-5E43-099387C61A71"
Ls_name_spin: .asciz "spin"
Ls_pref_target: .asciz "spin_target"
Ls_t_tv:     .asciz "the TV"
Ls_t_lights: .asciz "the lights"
Ls_f_val:    .asciz "%s"
Ls_w_tv:     .asciz "tv"

Ls_c_louder:    .asciz "louder"
Ls_c_quieter:   .asciz "quieter"
Ls_c_brighter:  .asciz "all lights brighter"
Ls_c_dimmer:    .asciz "all lights dimmer"
Ls_c_allon:     .asciz "all lights on"
Ls_c_alloff:    .asciz "all lights off"
Ls_c_lightsoff: .asciz "lights off"
Ls_c_mute:      .asciz "mute"

Ls_msg_found:  .asciz "\302\267 \360\237\224\230 Found a SPIN remote \342\200\224 connecting\342\200\246 (macOS may ask to pair it; that's fine)."
Ls_msg_linked: .asciz "\302\267 \360\237\224\230 SPIN remote connected. Type \342\200\234spin\342\200\235 for its map, \342\200\234spin debug\342\200\235 to see each gesture arrive."
Ls_msg_lost:   .asciz "\302\267 \360\237\224\230 SPIN remote disconnected."
Ls_f_switch:   .asciz "\302\267 \360\237\224\230 The SPIN now controls %s. Double-tap it (or say \342\200\234spin controls the tv/lights\342\200\235) to switch."
Ls_bt_wait:    .asciz "\302\267 \342\232\240\357\270\217 asmmesh isn't allowed to use Bluetooth yet. Click Allow on the Bluetooth prompt, or turn asmmesh on in System Settings \342\206\222 Privacy & Security \342\206\222 Bluetooth."
Ls_bt_denied:  .asciz "\302\267 \342\232\240\357\270\217 Bluetooth is blocked for asmmesh. Turn it on in System Settings \342\206\222 Privacy & Security \342\206\222 Bluetooth (switch it off and on again after a rebuild)."
Ls_bt_off:     .asciz "\302\267 \342\232\240\357\270\217 Bluetooth is turned off on this Mac. Turn it on in Control Centre, then say \342\200\234connect spin\342\200\235."
Ls_already:    .asciz "\302\267 The SPIN remote is already connected."
Ls_scanning:   .asciz "\302\267 Looking for a SPIN remote\342\200\246 wake it (press its top) so it advertises, then it links on its own."
Ls_st_off:     .asciz "\302\267 \360\237\224\230 No SPIN remote connected. Say \342\200\234connect spin\342\200\235 and wake the remote."
Ls_st_connecting: .asciz "\302\267 \360\237\224\230 Connecting to a SPIN remote\342\200\246"
Ls_st_lights:  .asciz "\302\267 \360\237\224\230 SPIN remote connected \342\200\224 spinning controls the lights."
Ls_st_tv:      .asciz "\302\267 \360\237\224\230 SPIN remote connected \342\200\224 spinning controls the TV."
Ls_map1:       .asciz "\302\267 Spin: brighter / dimmer (or louder / quieter for the TV). Touch-scroll or swipe left/right: change room."
Ls_map2:       .asciz "\302\267 Swipe up / down: all lights on / off. Press the centre: mute the TV, or lights off. Double-tap: switch between lights and TV."
Ls_dbg_fmt:    .asciz "\302\267 \360\237\224\230 gesture: %s (code %ld)"
Ls_dbg_on:     .asciz "\302\267 \360\237\224\230 SPIN debug on \342\200\224 every gesture the remote sends will show here. Quit the SPIN app first, then spin, press and swipe it. If nothing shows, the remote isn't talking to asmmesh (the SPIN app or another device still has it)."
Ls_dbg_off:    .asciz "\302\267 \360\237\224\230 SPIN debug off."
Ls_map3:       .asciz "\302\267 Long-press the centre: \360\237\206\230 SOS (message to the mesh + a push to your phone). Your SPIN profile colours are left as you set them."

.section __TEXT,__cstring,cstring_literals
Ls_NSArray:            .asciz "NSArray"
Ls_arrayWithObjects:   .asciz "arrayWithObjects:count:"
Ls_CBUUID:             .asciz "CBUUID"
Ls_UUIDWithString:     .asciz "UUIDWithString:"
Ls_NSData:             .asciz "NSData"
Ls_dataWithBytes:      .asciz "dataWithBytes:length:"
Ls_retain:             .asciz "retain"
Ls_state:              .asciz "state"
Ls_release:            .asciz "release"
Ls_setDelegate:        .asciz "setDelegate:"
Ls_connectPeripheral:  .asciz "connectPeripheral:options:"
Ls_discoverServices:   .asciz "discoverServices:"
Ls_discoverCharacteristics2: .asciz "discoverCharacteristics:forService:"
Ls_services:           .asciz "services"
Ls_characteristics:    .asciz "characteristics"
Ls_count:              .asciz "count"
Ls_objectAtIndex:      .asciz "objectAtIndex:"
Ls_UUID:               .asciz "UUID"
Ls_isEqual:            .asciz "isEqual:"
Ls_setNotifyValue:     .asciz "setNotifyValue:forCharacteristic:"
Ls_writeValue:         .asciz "writeValue:forCharacteristic:type:"
Ls_value:              .asciz "value"
Ls_length:             .asciz "length"
Ls_bytes:              .asciz "bytes"
Ls_objectForKey:       .asciz "objectForKey:"
Ls_containsObject:     .asciz "containsObject:"
