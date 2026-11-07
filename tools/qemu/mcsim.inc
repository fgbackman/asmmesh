// mcsim.inc — what mc_ble.s takes from src/macros.inc, for the qemu run (run.sh mcsim)
.set MESHCORE_ID,   13
.set SVC_MESHCORE,  25
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
