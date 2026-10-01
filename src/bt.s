// bt.s — classic Bluetooth devices already paired with this Mac (headphones,
// keyboards, mice, phones, speakers), from IOBluetooth. The scanner lists
// them; Connect & Pair asks one to connect now. New classic devices are paired
// in Bluetooth Settings, which the scanner opens for you.

.include "macros.inc"

.data
.p2align 3
_g_paired:      .quad 0

.section __DATA,__const
.p2align 3
// major device classes 0..9
Lclasses:
    .quad Lc_misc, Lc_computer, Lc_phone, Lc_network, Lc_audio, Lc_peripheral
    .quad Lc_imaging, Lc_wearable, Lc_toy, Lc_health

.text
.p2align 2

// void _bt_refresh(void) — asks IOBluetooth off the main thread: its first call
// sets up a helper that waits on the main thread, so asking from there hangs
.globl _bt_refresh
_bt_refresh:
    ENTER 0
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, #0
    ADRL x2, _bt_fetch
    bl   _dispatch_async_f
    LEAVE 0

// void _bt_fetch(void *unused) — background: the paired list, handed to the main thread
_bt_fetch:
    ENTER 0
    ADRL x0, Ls_IOBluetoothDevice
    bl   _objc_getClass
    cbz  x0, Lbf_done
    MSG0 Ls_pairedDevices
    cbz  x0, Lbf_done
    MSG0 Ls_retain
    mov  x1, x0
    LDGOT x0, __dispatch_main_q
    ADRL x2, _bt_fetched
    bl   _dispatch_async_f
Lbf_done:
    LEAVE 0

// void _bt_fetched(NSArray *paired /* retained */) — main thread
_bt_fetched:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_paired
    ldr  x0, [x8]
    str  x19, [x8]
    cbz  x0, Lbfd_list
    MSG0 Ls_release
Lbfd_list:
    bl   _ui_lists_changed
    LEAVE 0

// long _bt_count(void)
.globl _bt_count
_bt_count:
    ENTER 0
    ADRL x8, _g_paired
    ldr  x0, [x8]
    cbz  x0, Lbc_zero
    MSG0 Ls_count
    LEAVE 0
Lbc_zero:
    mov  x0, #0
    LEAVE 0

// id _bt_dev(long i) -> IOBluetoothDevice or nil
_bt_dev:
    ENTER 0
    mov  x19, x0
    bl   _bt_count
    cmp  x19, x0
    b.hs Lbd_nil
    ADRL x8, _g_paired
    ldr  x0, [x8]
    mov  x2, x19
    MSG1 Ls_objectAtIndex
    LEAVE 0
Lbd_nil:
    mov  x0, #0
    LEAVE 0

// char *_bt_name(long i, char *buf, size_t max)
.globl _bt_name
_bt_name:
    ENTER 0
    mov  x20, x1
    mov  x21, x2
    strb wzr, [x20]
    bl   _bt_dev
    cbz  x0, Lbn_done
    MSG0 Ls_nameOrAddress
    cbz  x0, Lbn_done
    MSG0 Ls_UTF8String
    cbz  x0, Lbn_done
    mov  x1, x0
    mov  x0, x20
    mov  x2, x21
    bl   _strlcpy
Lbn_done:
    mov  x0, x20
    LEAVE 0

// const char *_bt_kind(long i) -> "Bluetooth: headphones / speaker" etc.
.globl _bt_kind
_bt_kind:
    ENTER 0
    bl   _bt_dev
    ADRL x19, Lc_misc
    cbz  x0, Lbk_ret
    MSG0 Ls_deviceClassMajor
    and  x0, x0, #0xffffffff
    cmp  x0, #9
    b.hi Lbk_ret
    ADRL x8, Lclasses
    ldr  x19, [x8, x0, lsl #3]
Lbk_ret:
    mov  x0, x19
    LEAVE 0

// long _bt_connected(long i)
.globl _bt_connected
_bt_connected:
    ENTER 0
    bl   _bt_dev
    cbz  x0, Lbcn_ret
    MSG0 Ls_isConnected
    and  x0, x0, #0xff
Lbcn_ret:
    LEAVE 0

// char *_bt_details(long i, char *buf, size_t max) — "address 00-11-22-.. · connected"
.globl _bt_details
_bt_details:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    strb wzr, [x20]
    bl   _bt_dev
    cbz  x0, Lbde_done
    MSG0 Ls_addressString
    cbz  x0, Lbde_done
    MSG0 Ls_UTF8String
    mov  x22, x0
    mov  x0, x19
    bl   _bt_connected
    ADRL x4, Ls_not_connected
    cbz  x0, Lbde_fmt
    ADRL x4, Ls_connected
Lbde_fmt:
    mov  x0, x20
    mov  x1, x21
    ADRL x2, Lf_details
    mov  x3, x22
    bl   _sfmt
Lbde_done:
    mov  x0, x20
    LEAVE 0

// void _bt_connect(long i) — ask it to connect, off the main thread
.globl _bt_connect
_bt_connect:
    ENTER 0
    bl   _bt_dev
    cbz  x0, Lbco_done
    MSG0 Ls_retain
    mov  x19, x0
    MSG0 Ls_nameOrAddress
    MSG0 Ls_UTF8String
    mov  x1, x0
    ADRL x0, Ls_connecting
    bl   _scan_say
    mov  x0, #0
    mov  x1, #0
    bl   _dispatch_get_global_queue
    mov  x1, x19
    ADRL x2, _bt_worker
    bl   _dispatch_async_f
Lbco_done:
    LEAVE 0

// void _bt_worker(IOBluetoothDevice *dev) — background: open the connection
_bt_worker:
    ENTER 0
    mov  x19, x0
    MSG0 Ls_openConnection
    mov  x20, x0
    mov  x0, #16
    bl   _malloc
    cbz  x0, Lbw_done
    stp  x19, x20, [x0]
    mov  x1, x0
    LDGOT x0, __dispatch_main_q
    ADRL x2, _bt_done
    bl   _dispatch_async_f
Lbw_done:
    LEAVE 0

// void _bt_done(void *ctx /* {dev, IOReturn} */) — main thread
_bt_done:
    ENTER 0
    mov  x21, x0
    ldp  x19, x20, [x21]
    mov  x0, x19
    MSG0 Ls_nameOrAddress
    MSG0 Ls_UTF8String
    mov  x1, x0
    and  x2, x20, #0xffffffff
    ADRL x0, Ls_bt_ok
    cbz  x2, Lbdn_say
    ADRL x0, Ls_bt_fail
Lbdn_say:
    bl   _scan_say
    mov  x0, x19
    MSG0 Ls_release
    mov  x0, x21
    bl   _free
    bl   _ui_lists_changed
    LEAVE 0

// void _bt_settings(void) — System Settings > Bluetooth
.globl _bt_settings
_bt_settings:
    ENTER 0
    CLS  Ls_NSWorkspace
    MSG0 Ls_sharedWorkspace
    mov  x19, x0
    ADRL x0, Ls_bt_url
    bl   _nsstr
    mov  x20, x0
    CLS  Ls_NSURL
    mov  x2, x20
    MSG1 Ls_URLWithString
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_openURL
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_IOBluetoothDevice: .asciz "IOBluetoothDevice"
Ls_NSWorkspace:       .asciz "NSWorkspace"
Ls_NSURL:             .asciz "NSURL"
Ls_pairedDevices:     .asciz "pairedDevices"
Ls_retain:            .asciz "retain"
Ls_release:           .asciz "release"
Ls_count:             .asciz "count"
Ls_objectAtIndex:     .asciz "objectAtIndex:"
Ls_nameOrAddress:     .asciz "nameOrAddress"
Ls_UTF8String:        .asciz "UTF8String"
Ls_deviceClassMajor:  .asciz "deviceClassMajor"
Ls_isConnected:       .asciz "isConnected"
Ls_addressString:     .asciz "addressString"
Ls_openConnection:    .asciz "openConnection"
Ls_sharedWorkspace:   .asciz "sharedWorkspace"
Ls_URLWithString:     .asciz "URLWithString:"
Ls_openURL:           .asciz "openURL:"
Ls_bt_url:            .asciz "x-apple.systempreferences:com.apple.BluetoothSettings"
Lf_details:           .asciz "address %s \302\267 %s"
Ls_connected:         .asciz "connected"
Ls_not_connected:     .asciz "paired, not connected"
Ls_connecting:        .asciz "\302\267 Asking %s to connect\342\200\246"
Ls_bt_ok:             .asciz "\302\267 %s is connected."
Ls_bt_fail:           .asciz "\302\267 %s didn't connect (error 0x%lx). Make sure it's switched on and nearby, and not connected to another device."
Lc_misc:              .asciz "Bluetooth"
Lc_computer:          .asciz "Bluetooth computer"
Lc_phone:             .asciz "Bluetooth phone"
Lc_network:           .asciz "Bluetooth network"
Lc_audio:             .asciz "Bluetooth audio"
Lc_peripheral:        .asciz "Bluetooth keyboard/mouse"
Lc_imaging:           .asciz "Bluetooth printer/camera"
Lc_wearable:          .asciz "Bluetooth wearable"
Lc_toy:               .asciz "Bluetooth toy"
Lc_health:            .asciz "Bluetooth health"
