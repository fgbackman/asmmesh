// appear.s — light and dark mode on the Mac.
//
// The app follows the system's appearance (System Settings › Appearance), or the one you
// pick: "appearance light", "appearance dark", "appearance auto" in Home (saved as
// defaults "appearance"). Colours that change with it are dynamic NSColors: _rgb2(dark,
// light) makes one (an NSColor whose provider block picks the dark or the light colour
// each time it's drawn), and _rgb turns the app's dark greys into one of those by itself
// (Lpal below), so the windows, cards and fields go light with the system. The accent
// colours (amber, blue, green...) are the same in both. The game boards and the scanner
// stay dark (_appear_dark on their window): they're drawn for it.
// Blocks: hand-laid global blocks (as voice.s), one per colour pair, with the pair's slot
// after the descriptor; the provider reads it there. 24 pairs at most.
.include "macros.inc"

.set BLOCK_GLOBAL_SIG, 0x50000000     // BLOCK_IS_GLOBAL | BLOCK_HAS_SIGNATURE
.set DYN_N,     24
.set DY_DARK,   0                     // a slot: the two colours (0xRRGGBB), the NSColors
.set DY_LIGHT,  8
.set DY_DC,     16
.set DY_LC,     24
.set DY_COLOR,  32                    // the dynamic NSColor (retained)
.set DY_SIZE,   40

.data
.p2align 3
_g_dyn_n:       .quad 0
.zerofill __DATA,__bss,_g_dyn,(DYN_N * DY_SIZE),4
.zerofill __DATA,__bss,_g_appear_buf,32,4

// the provider blocks: struct { isa; int flags; int reserved; invoke; descriptor; slot }
.macro DYNBLOCK i
    .quad __NSConcreteGlobalBlock
    .long BLOCK_GLOBAL_SIG
    .long 0
    .quad Ldyn_provide
    .quad Ldyn_desc
    .quad \i
.endm
.p2align 3
Ldyn_blocks:
.irp i, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23
    DYNBLOCK \i
.endr
Ldyn_desc:
    .quad 0, 40, Lsig_provide         // reserved, size, signature

.section __TEXT,__const
.p2align 3
// the app's dark greys and what they are in light mode
Lpal:
    .quad 0x1A1A1C, 0xF2F2F7          // the main window
    .quad 0x1C1C1E, 0xECECF0          // Settings, SPIN, FM windows
    .quad 0x222426, 0xFFFFFF          // cards
    .quad 0x2C2C2E, 0xFFFFFF          // cards and fields in Settings, the input box
    .quad 0x3A3A3C, 0xD1D1D6          // grey pills
    .quad 0, 0
Lc_255:     .double 255.0
Lc_one:     .double 1.0

.text
.p2align 2

// id _rgb_dyn(long 0xRRGGBB) -> the dynamic colour if it's one of the app's dark greys,
//   else 0 (services.s's _rgb then makes a plain one)
.globl _rgb_dyn
_rgb_dyn:
    ADRL x9, Lpal
1:  ldp  x10, x11, [x9], #16
    cbz  x10, 8f
    cmp  x10, x0
    b.ne 1b
    mov  x1, x11
    b    _rgb2
8:  mov  x0, #0
    ret

// long _rgb_is_dyn(long 0xRRGGBB) -> 1 if it's one of the greys that go light (leaf)
.globl _rgb_is_dyn
_rgb_is_dyn:
    ADRL x9, Lpal
1:  ldp  x10, x11, [x9], #16
    cbz  x10, 8f
    cmp  x10, x0
    b.ne 1b
    mov  x0, #1
    ret
8:  mov  x0, #0
    ret

// id _rgb2(long dark, long light) — a colour that's `dark` in dark mode, `light` in light
//   mode (made once per pair, kept)
.globl _rgb2
_rgb2:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x21, _g_dyn
    mov  x22, #0
1:  ADRL x8, _g_dyn_n                 // made already?
    ldr  x9, [x8]
    cmp  x22, x9
    b.hs 2f
    mov  x9, #DY_SIZE
    madd x23, x22, x9, x21
    ldp  x10, x11, [x23, #DY_DARK]
    cmp  x10, x19
    ccmp x11, x20, #0, eq
    b.eq 7f
    add  x22, x22, #1
    b    1b
2:  cmp  x22, #DYN_N                  // no room: the dark one, as before
    b.hs 6f
    mov  x9, #DY_SIZE
    madd x23, x22, x9, x21
    stp  x19, x20, [x23, #DY_DARK]
    mov  x0, x19
    bl   Lrgb_plain
    MSG0 Ls_retain
    str  x0, [x23, #DY_DC]
    mov  x0, x20
    bl   Lrgb_plain
    MSG0 Ls_retain
    str  x0, [x23, #DY_LC]
    CLS  Ls_NSColor                   // [NSColor colorWithName:nil dynamicProvider:block]
    mov  x2, #0
    ADRL x3, Ldyn_blocks
    mov  x9, #40                      // (each block is 40 bytes)
    madd x3, x22, x9, x3
    MSG2 Ls_colorWithName
    cbz  x0, 6f                       // (before macOS 10.15: the dark one)
    MSG0 Ls_retain
    str  x0, [x23, #DY_COLOR]
    ADRL x8, _g_dyn_n
    add  x9, x22, #1
    str  x9, [x8]
7:  ldr  x0, [x23, #DY_COLOR]
    LEAVE 0
6:  mov  x0, x19
    bl   Lrgb_plain
    LEAVE 0

// NSColor *Ldyn_provide(block, NSAppearance *appearance) — the provider: dark or light
Ldyn_provide:
    ENTER 0
    ldr  x19, [x0, #32]               // its slot
    mov  x0, x1
    bl   _appear_is_dark
    ADRL x8, _g_dyn
    mov  x9, #DY_SIZE
    madd x8, x19, x9, x8
    ldr  x9, [x8, #DY_LC]
    ldr  x10, [x8, #DY_DC]
    cmp  x0, #0
    csel x0, x10, x9, ne
    LEAVE 0

// long _appear_is_dark(NSAppearance *a) -> 1 for a dark appearance (any kind: its name says)
.globl _appear_is_dark
_appear_is_dark:
    ENTER 0
    cbz  x0, 8f
    MSG0 Ls_name
    cbz  x0, 8f
    MSG0 Ls_UTF8String
    cbz  x0, 8f
    ADRL x1, Ls_Dark
    bl   _strstr
    cmp  x0, #0
    cset x0, ne
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// id Lrgb_plain(long 0xRRGGBB) — an sRGB colour, as services.s's _rgb always made
Lrgb_plain:
    ENTER 16
    mov  x19, x0
    SELX1 Ls_colorWithSRGB
    mov  x20, x1
    CLS  Ls_NSColor
    mov  x1, x20
    ubfx x9, x19, #16, #8
    ucvtf d0, x9
    ubfx x9, x19, #8, #8
    ucvtf d1, x9
    and  x9, x19, #0xff
    ucvtf d2, x9
    LDD  d4, Lc_255
    fdiv d0, d0, d4
    fdiv d1, d1, d4
    fdiv d2, d2, d4
    LDD  d3, Lc_one
    bl   _objc_msgSend
    LEAVE 16

// ---------------------------------------------------------------------------
// Which appearance

// void _appear_apply(void) — at launch (main.s) and when it's changed: the saved choice,
//   or the system's; then what's being drawn now follows it
.globl _appear_apply
_appear_apply:
    ENTER 0
    ADRL x0, Ls_k_appear
    ADRL x1, _g_appear_buf
    mov  x2, #32
    bl   _pref_get
    mov  x19, #0                      // nil: the system's
    ADRL x0, _g_appear_buf
    ADRL x1, Ls_light
    bl   _strcmp
    cbnz w0, 1f
    LDGOT x8, _NSAppearanceNameAqua
    ldr  x19, [x8]
    b    2f
1:  ADRL x0, _g_appear_buf
    ADRL x1, Ls_dark
    bl   _strcmp
    cbnz w0, 2f
    LDGOT x8, _NSAppearanceNameDarkAqua
    ldr  x19, [x8]
2:  cbz  x19, 3f
    CLS  Ls_NSAppearance
    mov  x2, x19
    MSG1 Ls_appearanceNamed
    mov  x19, x0
3:  CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x20, x0
    mov  x2, x19
    MSG1 Ls_setAppearance
    mov  x0, x20                      // colours turned into layers' CGColors now use it too
    MSG0 Ls_effectiveAppearance
    mov  x2, x0
    CLS  Ls_NSAppearance
    MSG1 Ls_setCurrentAppearance
    LEAVE 0

// void _appear_dark(id window) — this window stays dark (a game board, the scanner)
.globl _appear_dark
_appear_dark:
    ENTER 0
    mov  x19, x0
    cbz  x19, 9f
    CLS  Ls_NSAppearance
    LDGOT x8, _NSAppearanceNameDarkAqua
    ldr  x2, [x8]
    MSG1 Ls_appearanceNamed
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setAppearance
9:  LEAVE 0

// _h_appear(arg, rest_lc, rest_orig) — Home: 1 light, 2 dark, 3 auto (the system's), 4 which
.globl _h_appear
_h_appear:
    ENTER 0
    mov  x19, x0
    cmp  x19, #4
    b.eq 5f
    ADRL x1, Ls_light
    cmp  x19, #1
    b.eq 1f
    ADRL x1, Ls_dark
    cmp  x19, #2
    b.eq 1f
    ADRL x1, Ls_empty
1:  ADRL x0, Ls_k_appear
    bl   _pref_set
    bl   _appear_apply
5:  ADRL x0, Ls_k_appear
    ADRL x1, _g_appear_buf
    mov  x2, #32
    bl   _pref_get
    ADRL x0, Ls_said_auto
    ADRL x8, _g_appear_buf
    ldrb w9, [x8]
    cbz  w9, 6f
    ADRL x0, Ls_said
6:  ADRL x1, _g_appear_buf
    bl   _home_say
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lsig_provide:   .asciz "@16@?0@8"
Ls_Dark:        .asciz "Dark"
Ls_k_appear:    .asciz "appearance"
Ls_light:       .asciz "light"
Ls_dark:        .asciz "dark"
Ls_empty:       .asciz ""
Ls_said:        .asciz "\302\267 Appearance: %s (appearance auto follows the system again)."
Ls_said_auto:   .asciz "\302\267 Appearance: the system\342\200\231s (System Settings \342\200\272 Appearance)%s. appearance light or appearance dark picks one for asmmesh."
Ls_NSColor:     .asciz "NSColor"
Ls_NSAppearance: .asciz "NSAppearance"
Ls_NSApplication: .asciz "NSApplication"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_colorWithName: .asciz "colorWithName:dynamicProvider:"
Ls_colorWithSRGB: .asciz "colorWithSRGBRed:green:blue:alpha:"
Ls_appearanceNamed: .asciz "appearanceNamed:"
Ls_setAppearance: .asciz "setAppearance:"
Ls_effectiveAppearance: .asciz "effectiveAppearance"
Ls_setCurrentAppearance: .asciz "setCurrentAppearance:"
Ls_retain:      .asciz "retain"
Ls_name:        .asciz "name"
Ls_UTF8String:  .asciz "UTF8String"
