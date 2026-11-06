// quick.s — shortcuts you make, and the devices your services found, kept between launches.
//
// Shortcuts: a name for one or more Home commands, saved like the rooms are.
//   shortcut movie: dim living room to 20%; tv on      make (or change) one
//   movie                                              run it: each command, in order
//   shortcuts                                          list them
//   delete shortcut movie                              remove one
// Commands are split at ";" or " then ". Each runs as if typed in Home (safety rules
// included: an unlock still asks). A shortcut can't run another shortcut. Saved in the
// defaults as "quickShortcuts" ("name\tcommands\n" each). The Mac lists them in a
// Shortcuts menu, the iPhone on Nearby.
//
// Devices: every 30 s, if the services found something new or renamed it, the device
// table is saved ("savedDevices"), and at launch it's read back before the services
// start, so lights, scenes and devices are listed (and can be told) straight away; each
// service updates its own as it answers. Bluetooth bulbs and sensors aren't kept (they
// need the radio). A device's on/off and level start unknown. "forget devices" clears
// the saved list.
// Hooks: _qk_ui_changed (main.s on the Mac: the menu; ios_ui.s: the iPhone).
.include "macros.inc"

.set QK_N,       24
.set QK_NAME,    32                 // name, NUL-terminated
.set QK_CMDS,    224                // commands, NUL-terminated
.set QK_SIZE,    (QK_NAME + QK_CMDS)
.set QK_SAVE,    (QK_N * (QK_SIZE + 2) + 16)
.set QK_PARTS,   12                 // commands in one shortcut, at most
.set DV_EVERY,   30                 // seconds between looks at the device table

.data
.p2align 3
.globl _g_qk_count
_g_qk_count:    .quad 0
_g_qk_depth:    .quad 0             // 1 while a shortcut runs: its commands aren't shortcuts
_g_dv_secs:     .quad 0
_g_dv_saved:    .quad 0             // bytes in _g_dv_last (what's in the defaults now)
.zerofill __DATA,__bss,_g_qk,(QK_N * QK_SIZE),4
.zerofill __DATA,__bss,_g_qk_buf,QK_SAVE,4
.zerofill __DATA,__bss,_g_qk_run,QK_CMDS,4
.zerofill __DATA,__bss,_g_qk_line,512,4
.zerofill __DATA,__bss,_g_dv_now,65536,4
.zerofill __DATA,__bss,_g_dv_last,65536,4

.text
.p2align 2

// ---------------------------------------------------------------------------
// Shortcuts

// void _qk_load(void) — at launch
.globl _qk_load
_qk_load:
    ENTER 0
    ADRL x8, _g_qk_count
    str  xzr, [x8]
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, 9f
    ADRL x0, Ls_k_qk
    ADRL x1, _g_qk_buf
    mov  x2, #QK_SAVE
    bl   _pref_get
    ADRL x19, _g_qk_buf
1:  ldrb w9, [x19]                    // "name\tcommands\n"
    cbz  w9, 9f
    mov  x20, x19                     // the name
2:  ldrb w9, [x19]
    cbz  w9, 9f
    cmp  w9, #9
    b.eq 3f
    add  x19, x19, #1
    b    2b
3:  strb wzr, [x19]
    add  x19, x19, #1
    mov  x21, x19                     // the commands
4:  ldrb w9, [x19]
    cbz  w9, 5f
    cmp  w9, #10
    b.eq 41f
    add  x19, x19, #1
    b    4b
41: strb wzr, [x19]
    add  x19, x19, #1
5:  mov  x0, x20
    mov  x1, x21
    mov  x2, #0                       // (not saved again while reading)
    bl   Lqk_put
    b    1b
9:  bl   _qk_ui_changed               // the menus (Mac) and Nearby (iPhone) were made before
    LEAVE 0

// long _qk_save(const char *name, const char *commands) -> 0 saved; -1 no room for more,
//   -2 the name won't do (empty, too long, or has : or ;), -3 no commands
.globl _qk_save
_qk_save:
    ENTER 0
    mov  x2, #1
    bl   Lqk_put
    LEAVE 0

// Lqk_put(x0 name, x1 commands, x2 1: save the list after) -> as _qk_save
Lqk_put:
    ENTER 64                          // [96] the name, cleaned (40)
    mov  x19, x0
    mov  x20, x1
    mov  x24, x2
    add  x0, sp, #96                  // the name: trimmed, single spaces
    mov  x1, x19
    mov  x2, #40
    mov  x3, #0
    bl   _norm
    cbz  x0, Lqp_badname
    cmp  x0, #(QK_NAME - 1)
    b.hs Lqp_badname
    add  x9, sp, #96
1:  ldrb w10, [x9], #1
    cbz  w10, 2f
    cmp  w10, #':'
    b.eq Lqp_badname
    cmp  w10, #';'
    b.eq Lqp_badname
    b    1b
2:  ldrb w9, [x20]                    // commands: after spaces, something
    cmp  w9, #' '
    b.ne 3f
    add  x20, x20, #1
    b    2b
3:  cbz  w9, Lqp_empty
    add  x0, sp, #96
    bl   Lqk_find
    mov  x21, x0
    tbz  x21, #63, 4f
    ADRL x8, _g_qk_count              // a new one
    ldr  x21, [x8]
    cmp  x21, #QK_N
    b.hs Lqp_full
    add  x9, x21, #1
    str  x9, [x8]
4:  ADRL x8, _g_qk
    mov  x9, #QK_SIZE
    madd x22, x21, x9, x8
    mov  x0, x22
    add  x1, sp, #96
    mov  x2, #QK_NAME
    bl   _strlcpy
    add  x0, x22, #QK_NAME
    mov  x1, x20
    mov  x2, #QK_CMDS
    bl   _strlcpy
    add  x9, x22, #QK_NAME            // no tabs or new lines (the saved form uses them)
5:  ldrb w10, [x9]
    cbz  w10, 6f
    cmp  w10, #9
    b.eq 51f
    cmp  w10, #10
    b.eq 51f
    cmp  w10, #13
    b.ne 52f
51: mov  w10, #' '
    strb w10, [x9]
52: add  x9, x9, #1
    b    5b
6:  cbz  x24, 7f
    bl   Lqk_write
7:  mov  x0, #0
    LEAVE 64
Lqp_badname:
    mov  x0, #-2
    LEAVE 64
Lqp_empty:
    mov  x0, #-3
    LEAVE 64
Lqp_full:
    mov  x0, #-1
    LEAVE 64

// long Lqk_find(x0 name) -> its index, or -1 (any case)
Lqk_find:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
1:  ADRL x8, _g_qk_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 2f
    ADRL x8, _g_qk
    mov  x9, #QK_SIZE
    madd x0, x20, x9, x8
    mov  x1, x19
    bl   _strcasecmp
    cbz  w0, 3f
    add  x20, x20, #1
    b    1b
2:  mov  x0, #-1
    LEAVE 0
3:  mov  x0, x20
    LEAVE 0

// long _qk_delete(long i) — remove shortcut i, save, tell the screens -> 1 if it was there
.globl _qk_delete
_qk_delete:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_qk_count
    ldr  x20, [x8]
    cmp  x19, x20
    b.hs 8f
    sub  x20, x20, #1
    str  x20, [x8]
    ADRL x8, _g_qk                    // the ones after it move up
    mov  x9, #QK_SIZE
    madd x0, x19, x9, x8
    add  x1, x0, #QK_SIZE
    sub  x10, x20, x19
    mul  x2, x10, x9
    bl   _memmove
    bl   Lqk_write
    mov  x0, #1
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// Lqk_write — the list into the defaults, and the screens told
Lqk_write:
    ENTER 0
    ADRL x19, _g_qk_buf
    strb wzr, [x19]
    mov  x20, #0
1:  ADRL x8, _g_qk_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs 2f
    ADRL x8, _g_qk
    mov  x9, #QK_SIZE
    madd x21, x20, x9, x8
    mov  x0, x19
    mov  x1, x21
    mov  x2, #QK_SAVE
    bl   _strlcat
    mov  x0, x19
    ADRL x1, Ls_tab
    mov  x2, #QK_SAVE
    bl   _strlcat
    mov  x0, x19
    add  x1, x21, #QK_NAME
    mov  x2, #QK_SAVE
    bl   _strlcat
    mov  x0, x19
    ADRL x1, Ls_nl
    mov  x2, #QK_SAVE
    bl   _strlcat
    add  x20, x20, #1
    b    1b
2:  ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, 3f
    ADRL x0, Ls_k_qk
    mov  x1, x19
    bl   _pref_set
3:  bl   _qk_ui_changed
    LEAVE 0

// long _qk_try(const char *text) -> 1 if it was a shortcut's name, and it ran (Home:
//   before anything else, so your name for something wins)
.globl _qk_try
_qk_try:
    ENTER 64                          // [96] the text, cleaned (40)
    mov  x19, x0
    ADRL x8, _g_qk_depth
    ldr  x9, [x8]
    cbnz x9, 8f
    ADRL x8, _g_qk_count
    ldr  x9, [x8]
    cbz  x9, 8f
    mov  x0, x19
    bl   _strlen
    cmp  x0, #(QK_NAME + 8)
    b.hs 8f
    add  x0, sp, #96
    mov  x1, x19
    mov  x2, #40
    mov  x3, #0
    bl   _norm
    add  x0, sp, #96
    bl   Lqk_find
    tbnz x0, #63, 8f
    bl   _am_qk_run
    mov  x0, #1
    LEAVE 64
8:  mov  x0, #0
    LEAVE 64

// void am_qk_run(long i) — shortcut i: each of its commands, in Home, in order
.globl _am_qk_run
_am_qk_run:
    ENTER 16
    mov  x19, x0
    ADRL x8, _g_qk_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs 9f
    ADRL x8, _g_qk_depth
    ldr  x9, [x8]
    cbnz x9, 9f
    mov  x9, #1
    str  x9, [x8]
    ADRL x8, _g_qk
    mov  x9, #QK_SIZE
    madd x20, x19, x9, x8
    ADRL x0, Ls_running               // "▶ movie"
    mov  x1, x20
    bl   _home_say
    ADRL x0, _g_qk_run                // a copy: running may change the list
    add  x1, x20, #QK_NAME
    mov  x2, #QK_CMDS
    bl   _strlcpy
    ADRL x21, _g_qk_run
    mov  x23, #0                      // commands run
1:  ldrb w9, [x21]                    // the next command: up to ; or " then "
    cbz  w9, 8f
    mov  x22, x21
2:  ldrb w9, [x22]
    cbz  w9, 4f
    cmp  w9, #';'
    b.eq 3f
    mov  x0, x22
    ADRL x1, Ls_then
    mov  x2, #6
    bl   _strncasecmp
    cbz  w0, 31f
    add  x22, x22, #1
    b    2b
3:  strb wzr, [x22]                   // ";"
    add  x24, x22, #1
    b    5f
31: strb wzr, [x22]                   // " then "
    add  x24, x22, #6
    b    5f
4:  mov  x24, x22                     // the last one
5:  ldrb w9, [x21]                    // spaces before it
    cmp  w9, #' '
    b.ne 6f
    add  x21, x21, #1
    b    5b
6:  cbz  w9, 7f
    cmp  x23, #QK_PARTS
    b.hs 8f
    add  x23, x23, #1
    mov  x0, x21
    mov  w1, #0
    bl   _home_command
7:  mov  x21, x24
    b    1b
8:  ADRL x8, _g_qk_depth
    str  xzr, [x8]
9:  LEAVE 16

// _h_quick(arg, rest_lc, rest_orig) — Home: 1 shortcut NAME: COMMANDS, 2 shortcuts,
//   3 delete shortcut NAME, 4 forget devices, 5 shortcut (how)
.globl _h_quick
_h_quick:
    ENTER 64                          // [96] the name (48)
    mov  x19, x0
    mov  x20, x2
    ADRL x8, _g_remote_active         // made on the device itself, not from the mesh
    ldr  x9, [x8]
    cbz  x9, 1f
    cmp  x19, #2
    b.ne Lhq_remote
1:  cmp  x19, #2
    b.eq Lhq_list
    cmp  x19, #3
    b.eq Lhq_delete
    cmp  x19, #4
    b.eq Lhq_forget
    cmp  x19, #5
    b.eq Lhq_how
    mov  x21, x20                     // "NAME: COMMANDS"
2:  ldrb w9, [x21]
    cbz  w9, Lhq_how
    cmp  w9, #':'
    b.eq 3f
    add  x21, x21, #1
    b    2b
3:  sub  x2, x21, x20                 // the name
    cmp  x2, #47
    b.hs Lhq_badname
    add  x0, sp, #96
    mov  x1, x20
    bl   _memcpy
    sub  x9, x21, x20
    add  x10, sp, #96
    strb wzr, [x10, x9]
    add  x0, sp, #96
    add  x1, x21, #1
    bl   _qk_save
    cbz  x0, Lhq_saved
    cmp  x0, #-1
    b.eq Lhq_full
    cmp  x0, #-3
    b.eq Lhq_how
Lhq_badname:
    ADRL x0, Ls_badname
    bl   _home_say0
    b    Lhq_done
Lhq_full:
    ADRL x0, Ls_full
    bl   _home_say0
    b    Lhq_done
Lhq_saved:
    ADRL x0, Ls_saved
    add  x1, sp, #96
    bl   _home_say
    b    Lhq_done
Lhq_list:
    ADRL x8, _g_qk_count
    ldr  x9, [x8]
    cbz  x9, Lhq_how
    ADRL x0, Ls_list_head
    bl   _home_say0
    mov  x21, #0
4:  ADRL x8, _g_qk_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs Lhq_done
    ADRL x8, _g_qk
    mov  x9, #QK_SIZE
    madd x22, x21, x9, x8
    str  x22, [sp]                    // "· movie: dim living room to 20%; tv on"
    add  x9, x22, #QK_NAME
    str  x9, [sp, #8]
    ADRL x0, _g_qk_line
    mov  x1, #512
    ADRL x2, Ls_list_fmt
    bl   _snprintf
    ADRL x0, _g_qk_line
    bl   _home_say0
    add  x21, x21, #1
    b    4b
Lhq_delete:
    add  x0, sp, #96
    mov  x1, x20
    mov  x2, #48
    mov  x3, #0
    bl   _norm
    add  x0, sp, #96
    bl   Lqk_find
    tbnz x0, #63, 5f
    bl   _qk_delete
    ADRL x0, Ls_deleted
    add  x1, sp, #96
    bl   _home_say
    b    Lhq_done
5:  ADRL x0, Ls_no_such
    add  x1, sp, #96
    bl   _home_say
    b    Lhq_done
Lhq_forget:
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, 6f
    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_k_dev
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_removeObjectForKey
6:  ADRL x8, _g_dv_saved              // what's found from now on is saved again
    str  xzr, [x8]
    ADRL x8, _g_dv_secs
    str  xzr, [x8]
    ADRL x0, Ls_forgot
    bl   _home_say0
    b    Lhq_done
Lhq_how:
    ADRL x0, Ls_how
    bl   _home_say0
    b    Lhq_done
Lhq_remote:
    ADRL x0, Ls_remote
    bl   _home_say0
Lhq_done:
    LEAVE 64

// long am_qk_save(name, commands), am_qk_delete(long i) — the iPhone's (as _qk_save, _qk_delete)
.globl _am_qk_save
_am_qk_save:
    b    _qk_save
.globl _am_qk_delete
_am_qk_delete:
    b    _qk_delete

// For the screens: long am_qk_count(void), const char *am_qk_name(long i),
//   const char *am_qk_cmds(long i)
.globl _am_qk_count
_am_qk_count:
    ADRL x8, _g_qk_count
    ldr  x0, [x8]
    ret
.globl _am_qk_name
_am_qk_name:
    ADRL x8, _g_qk
    mov  x9, #QK_SIZE
    madd x0, x0, x9, x8
    ret
.globl _am_qk_cmds
_am_qk_cmds:
    ADRL x8, _g_qk
    mov  x9, #QK_SIZE
    madd x0, x0, x9, x8
    add  x0, x0, #QK_NAME
    ret

// ---------------------------------------------------------------------------
// The devices the services found

// void _dv_load(void) — at launch, before the services start: the devices saved last time
.globl _dv_load
_dv_load:
    ENTER 0
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, 9f
    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_k_dev
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_dataForKey
    cbz  x0, 9f
    mov  x19, x0
    MSG0 Ls_length
    mov  x20, x0
    mov  x0, x19
    MSG0 Ls_bytes
    cbz  x0, 9f
    mov  x21, x0
    mov  x22, #0                      // offset
1:  add  x9, x22, #(1 << DEV_SHIFT)
    cmp  x9, x20
    b.hi 8f
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x9, #DEV_MAX
    b.hs 8f
    add  x23, x21, x22                // one saved device
    add  x22, x22, #(1 << DEV_SHIFT)
    ldr  x10, [x23, #D_KIND]
    mov  x0, x10
    bl   Ldv_keep
    cbz  x0, 1b
    ldrb w9, [x23, #D_ID]             // an id to know it by again
    cbz  w9, 1b
    ldr  x0, [x23, #D_KIND]           // there already?
    add  x1, x23, #D_ID
    bl   _dev_find_n
    tbz  x0, #63, 1b
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    add  x10, x9, #1
    str  x10, [x8]
    ADRL x8, _g_devs
    add  x24, x8, x9, lsl #DEV_SHIFT
    mov  x0, x24
    mov  x1, x23
    mov  x2, #(1 << DEV_SHIFT)
    bl   _memcpy
    str  xzr, [x24, #D_OBJ]           // nothing that was a pointer
    mov  x9, #-1                      // its state: unknown until its service says
    str  x9, [x24, #D_ON]
    str  x9, [x24, #D_LEVEL]
    ldr  x9, [x24, #D_CAPS]
    and  x9, x9, #~CAP_LINKED
    str  x9, [x24, #D_CAPS]
    strb wzr, [x24, #(D_ID + D_ID_MAX - 1)]       // never trust a stored terminator
    strb wzr, [x24, #(D_NAME + D_NAME_MAX - 1)]
    strb wzr, [x24, #(D_ROOM + D_ROOM_MAX - 1)]
    b    1b
8:  bl   Ldv_pack                     // what was read is what's saved
    mov  x19, x0
    ADRL x8, _g_dv_saved
    str  x19, [x8]
    ADRL x0, _g_dv_last
    ADRL x1, _g_dv_now
    mov  x2, x19
    bl   _memcpy
9:  LEAVE 0

// long _dev_find_n(long kind, const char *id) -> its index, or -1
_dev_find_n:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
1:  ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x21, x9
    b.hs 2f
    ADRL x8, _g_devs
    add  x22, x8, x21, lsl #DEV_SHIFT
    ldr  x9, [x22, #D_KIND]
    cmp  x9, x19
    b.ne 11f
    add  x0, x22, #D_ID
    mov  x1, x20
    bl   _strcmp
    cbz  w0, 3f
11: add  x21, x21, #1
    b    1b
2:  mov  x0, #-1
    LEAVE 0
3:  mov  x0, x21
    LEAVE 0

// long Ldv_keep(x0 kind) -> 1 if a device of that kind is kept between launches (leaf)
Ldv_keep:
    cmp  x0, #1
    b.lt 8f
    cmp  x0, #K_LAST
    b.gt 8f
    cmp  x0, #K_HUE_BLE               // these need the radio to be found again
    b.eq 8f
    cmp  x0, #K_BLES
    b.eq 8f
    mov  x0, #1
    ret
8:  mov  x0, #0
    ret

// long Ldv_pack -> bytes: the devices worth keeping, into _g_dv_now (no pointers, state unknown)
Ldv_pack:
    ENTER 0
    mov  x19, #0                      // device
    mov  x20, #0                      // bytes out
    ADRL x21, _g_dv_now
1:  ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs 8f
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    add  x19, x19, #1
    ldr  x0, [x22, #D_KIND]
    bl   Ldv_keep
    cbz  x0, 1b
    add  x23, x21, x20
    add  x20, x20, #(1 << DEV_SHIFT)
    mov  x0, x23
    mov  x1, x22
    mov  x2, #(1 << DEV_SHIFT)
    bl   _memcpy
    str  xzr, [x23, #D_OBJ]           // (so a changing state or pointer isn't a change)
    mov  x9, #-1
    str  x9, [x23, #D_ON]
    str  x9, [x23, #D_LEVEL]
    ldr  x9, [x23, #D_CAPS]
    and  x9, x9, #~CAP_LINKED
    str  x9, [x23, #D_CAPS]
    b    1b
8:  mov  x0, x20
    LEAVE 0

// void _dv_tick(void) — every second (scanner.s, ios_ui.s): every 30 s, save the devices if
//   the list changed
.globl _dv_tick
_dv_tick:
    ENTER 0
    ADRL x8, _g_dv_secs
    ldr  x9, [x8]
    add  x9, x9, #1
    str  x9, [x8]
    cmp  x9, #DV_EVERY
    b.lo 9f
    str  xzr, [x8]
    ADRL x8, _g_no_persist
    ldr  x8, [x8]
    cbnz x8, 9f
    bl   Ldv_pack
    mov  x19, x0
    cbz  x19, 9f                      // nothing found (yet): keep what's saved
    ADRL x8, _g_dv_saved
    ldr  x9, [x8]
    cmp  x9, x19
    b.ne 1f
    ADRL x0, _g_dv_now
    ADRL x1, _g_dv_last
    mov  x2, x19
    bl   _memcmp
    cbz  w0, 9f
1:  ADRL x8, _g_dv_saved
    str  x19, [x8]
    ADRL x0, _g_dv_last
    ADRL x1, _g_dv_now
    mov  x2, x19
    bl   _memcpy
    CLS  Ls_NSData
    ADRL x2, _g_dv_last
    mov  x3, x19
    MSG2 Ls_dataWithBytes
    mov  x20, x0
    bl   _defaults
    mov  x19, x0
    ADRL x0, Ls_k_dev
    bl   _nsstr
    mov  x3, x0
    mov  x2, x20
    mov  x0, x19
    MSG2 Ls_setObjectForKey
9:  LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_k_qk:        .asciz "quickShortcuts"
Ls_k_dev:       .asciz "savedDevices"
Ls_tab:         .asciz "\t"
Ls_nl:          .asciz "\n"
Ls_then:        .asciz " then "
Ls_running:     .asciz "\342\226\266 %s"
Ls_saved:       .asciz "\302\267 Shortcut \342\200\234%s\342\200\235 saved. Say its name to run it; shortcuts lists them."
Ls_deleted:     .asciz "\302\267 Shortcut \342\200\234%s\342\200\235 deleted."
Ls_no_such:     .asciz "\302\267 No shortcut called \342\200\234%s\342\200\235 (shortcuts lists them)."
Ls_badname:     .asciz "\302\267 A shortcut\342\200\231s name: up to 30 letters, without : or ;."
Ls_full:        .asciz "\302\267 That\342\200\231s 24 shortcuts already: delete shortcut NAME makes room."
Ls_list_head:   .asciz "\302\267 Your shortcuts (say the name to run one):"
Ls_list_fmt:    .asciz "   %s: %s"
Ls_how:         .asciz "\302\267 Make a shortcut: shortcut movie: dim living room to 20%; tv on (commands split by ; or then). Then say movie to run it. shortcuts lists them, delete shortcut movie removes one."
Ls_remote:      .asciz "\302\267 Shortcuts are made on the device itself, not from the mesh."
Ls_forgot:      .asciz "\302\267 The saved devices are forgotten. What the services find from now on is saved again; the rest goes at the next launch."
Ls_NSData:      .asciz "NSData"
Ls_dataWithBytes: .asciz "dataWithBytes:length:"
Ls_dataForKey:  .asciz "dataForKey:"
Ls_setObjectForKey: .asciz "setObject:forKey:"
Ls_removeObjectForKey: .asciz "removeObjectForKey:"
Ls_length:      .asciz "length"
Ls_bytes:       .asciz "bytes"
