// mtsim.inc — what mt_ble.s takes from src/macros.inc, for the qemu run (run.sh mtsim)
.set MESHTASTIC_ID, 14
.set SVC_MESHTASTIC, 26
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
.macro MSG3 selsym
    ADRL x1, \selsym
    bl   _msg3
.endm
.macro LDGOT reg, sym
    ADRL \reg, \sym
.endm
