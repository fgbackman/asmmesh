// quick.inc — what quick.s takes from src/macros.inc, for the qemu run (run.sh quick)
.set DEV_MAX,       256
.set DEV_SHIFT,     8
.set D_KIND,        0
.set D_CAPS,        8
.set D_ON,          16
.set D_LEVEL,       24
.set D_OBJ,         32
.set D_PORT,        40
.set D_ID,          48
.set D_ID_MAX,      64
.set D_NAME,        112
.set D_NAME_MAX,    64
.set D_AUX,         176
.set D_AUX_MAX,     48
.set D_ROOM,        224
.set D_ROOM_MAX,    32
.set K_HUE_BLE,     5
.set K_BLES,        18
.set K_LAST,        18
.set CAP_LINKED,    0x100
.macro CLS namesym
    ADRL x0, \namesym
    bl   _objc_getClass
.endm
.macro MSG0 selsym
    ADRL x1, \selsym
    bl   _msg0
.endm
.macro MSG1 selsym
    ADRL x1, \selsym
    bl   _msg1
.endm
.macro MSG2 selsym
    ADRL x1, \selsym
    bl   _msg2
.endm
