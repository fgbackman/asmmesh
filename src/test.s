// test.s — `asmmesh --selftest`: exercises the mesh logic (protocol v2, nodes,
// rooms, invites, names) without Bluetooth or a window. Prints PASS/FAIL per
// check; returns the number of failures (0 = everything passed).

.include "macros.inc"

.set STORE_N, 32
.set SLOT_SHIFT, 8

// EXPECT_EQ imm, name : x0 == imm ?
.macro EXPECT_EQ val, name
    cmp  x0, #\val
    cset w1, eq
    ADRL x0, \name
    bl   _t_report
    add  x19, x19, x0
.endm

// EXPECT_TRUE name : flags from the previous compare, "eq" = pass
.macro EXPECT_TRUE name
    cset w1, eq
    ADRL x0, \name
    bl   _t_report
    add  x19, x19, x0
.endm

// RX label : feed a canned packet to _mesh_receive, made into a signed v3 packet
//   from the test peer first (see _t_rx)
.macro RX pkt
    ADRL x0, \pkt
    mov  x1, #(\pkt\()_end - \pkt)
    bl   _t_rx
.endm

// PARSE text : x0 = action
.macro PARSE text
    ADRL x0, \text
    bl   _cmd_parse
.endm

// ONE_TARGET reg : flags "eq" when exactly one target, and it is reg (keeps x0)
.macro ONE_TARGET reg
    ADRL x8, _g_cmd_n
    ldr  x9, [x8]
    ADRL x8, _g_cmd_targets
    ldrb w10, [x8]
    cmp  x9, #1
    ccmp x10, \reg, #0, eq
.endm

// TARGET_IS global : flags "eq" when exactly one target, the device in that global (keeps x0)
.macro TARGET_IS g
    ADRL x8, \g
    ldr  x11, [x8]
    ADRL x8, _g_cmd_n
    ldr  x9, [x8]
    ADRL x8, _g_cmd_targets
    ldrb w10, [x8]
    cmp  x9, #1
    ccmp x10, x11, #0, eq
.endm

// x0 = store position
.macro STOREPOS
    ADRL x8, _g_store_pos
    ldr  x0, [x8]
.endm

.data
.p2align 3
_g_tpeer:       .quad 0                   // a second identity: "the other Mac"
_g_t_flip:      .quad 0                   // 1: damage the packet after signing it
.zerofill __DATA,__bss,_g_tbuf,128,4
.zerofill __DATA,__bss,_g_tbuf2,128,4
.zerofill __DATA,__bss,_g_tpeer_pub,72,4
.zerofill __DATA,__bss,_g_trx,256,4
.zerofill __DATA,__bss,_g_tkey,64,4
.zerofill __DATA,__bss,_g_tkey2,64,4

.text
.p2align 2

.globl _selftest
_selftest:
    ENTER 80                              // [96] scratch packet (64 bytes)  [160] an index
    mov  x19, #0                          // failures
    ADRL x8, _g_kind_on                   // tests use every kind of device: all switched on
    mov  x9, #0x0101010101010101
    stp  x9, x9, [x8]
    stp  x9, x9, [x8, #16]
    ADRL x8, _g_svc_on
    mov  x9, #0x7fff
    str  x9, [x8]
    bl   _id_generate                      // our identity for the tests
    bl   _key_generate                     // and the other Mac's
    ADRL x8, _g_tpeer
    str  x0, [x8]
    ADRL x1, _g_tpeer_pub
    bl   _key_pub
    ADRL x8, _g_id_check                  // the canned packets use made-up ids
    str  xzr, [x8]
    ldr  x0, Lid_alice                    // alice signs with the other Mac's key
    ADRL x1, _g_tpeer_pub
    bl   _key_put

    // 1. a well-formed Main message is accepted
    STOREPOS
    mov  x20, x0
    RX   Lp_msg
    EXPECT_EQ 1, Ln_valid

    // 2. its relay copy was stored once, with ttl 7 -> 6
    STOREPOS
    sub  x9, x0, x20
    and  x10, x20, #(STORE_N - 1)
    ADRL x11, _g_store
    add  x11, x11, x10, lsl #SLOT_SHIFT
    ldrb w12, [x11, #(8 + 2)]
    cmp  x9, #1
    ccmp w12, #6, #0, eq
    EXPECT_TRUE Ln_relaycopy

    // 3. the sender became a node on the mesh, one hop away
    ldr  x0, Lid_alice
    bl   _node_find
    tbnz x0, #63, 1f
    ADRL x8, _g_nodes
    add  x8, x8, x0, lsl #NODE_SHIFT
    ldr  x22, [x8, #N_HOPS]
    add  x0, x8, #N_NICK
    ADRL x1, Ls_alice
    bl   _strcmp
    cmp  w0, #0
    ccmp x22, #1, #0, eq
    b    2f
1:  cmp  x0, #0                           // not found: force a failure
2:  EXPECT_TRUE Ln_node

    // 4. the same packet again is a duplicate
    RX   Lp_msg
    EXPECT_EQ 2, Ln_dup

    // 5. ttl 1: shown, but not stored for relaying
    STOREPOS
    mov  x20, x0
    RX   Lp_ttl1
    mov  x21, x0
    STOREPOS
    cmp  x21, #1
    ccmp x0, x20, #0, eq
    EXPECT_TRUE Ln_ttl1

    // 6-11. malformed packets are rejected
    RX   Lp_badmagic
    EXPECT_EQ 0, Ln_badmagic
    RX   Lp_v1
    EXPECT_EQ 0, Ln_v1
    RX   Lp_bignick
    EXPECT_EQ 0, Ln_bignick
    RX   Lp_short
    EXPECT_EQ 0, Ln_short
    RX   Lp_bigttl
    EXPECT_EQ 0, Ln_bigttl
    RX   Lp_badtype
    EXPECT_EQ 0, Ln_badtype

    // 12. control characters in text are neutralised
    RX   Lp_ctrl
    ADRL x0, _g_txt
    ADRL x1, Ls_ctrl_expect
    bl   _strcmp
    cmp  w0, #0
    EXPECT_TRUE Ln_ctrl

    // 13. a HELLO adds the node with its name, hop count and relay count,
    //     and is passed on but not stored
    STOREPOS
    mov  x20, x0
    RX   Lp_hello
    mov  x21, x0
    STOREPOS
    mov  x22, x0
    ldr  x0, Lid_bob
    bl   _node_find
    tbnz x0, #63, 3f
    ADRL x8, _g_nodes
    add  x23, x8, x0, lsl #NODE_SHIFT
    add  x0, x23, #N_NICK
    ADRL x1, Ls_bob
    bl   _strcmp
    ldr  x9, [x23, #N_HOPS]
    ldr  x10, [x23, #N_RELAYED]
    cmp  w0, #0
    ccmp x9, #2, #0, eq
    ccmp x10, #3, #0, eq
    ccmp x21, #1, #0, eq
    ccmp x22, x20, #0, eq
    b    4f
3:  cmp  x0, #0
4:  EXPECT_TRUE Ln_hello

    // 14. an invite for someone else is relayed and kept, but not for us
    ADRL x8, _g_invites_for_me
    ldr  x20, [x8]
    RX   Lp_inv_other
    mov  x21, x0
    ADRL x8, _g_invites_for_me
    ldr  x9, [x8]
    cmp  x21, #1
    ccmp x9, x20, #0, eq
    EXPECT_TRUE Ln_inv_other

    // 15. an invite addressed to us (sealed for us alone) is noticed, and we are
    //     not auto-joined
    bl   _t_invite_me
    mov  x21, x0
    ADRL x8, _g_invites_for_me
    ldr  x22, [x8]
    sub  x22, x22, x20                    // (callee-saved: _room_find uses x9)
    ldr  x0, Lid_lab
    bl   _room_find
    add  x10, x0, #1                      // -1 (not a member) -> 0
    cmp  x21, #1
    ccmp x22, #1, #0, eq
    ccmp x10, #0, #0, eq
    EXPECT_TRUE Ln_inv_me

    // 16. messages for a room we are not in are relayed but not shown
    RX   Lp_room_msg
    EXPECT_EQ 1, Ln_room_hidden

    // 17. once we are in the room, its messages count as unread while we
    //     look at Main
    ldr  x0, Lid_lab
    ADRL x1, Ls_lab
    mov  x2, #0
    bl   _room_add
    mov  x20, x0
    ADRL x0, Lp_room_msg2
    mov  x1, #(Lp_room_msg2_end - Lp_room_msg2)
    mov  x2, x20
    bl   _t_rx_room
    ADRL x8, _g_rooms
    add  x8, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_UNREAD]
    cmp  x20, #4                          // after Main, Home, Web and News
    ccmp x9, #1, #0, eq
    EXPECT_TRUE Ln_unread

    // 17b. an invite into a room we're already in, with a new key, asks again
    //      (the sender lost its old key); the key we already have doesn't
    ADRL x8, _g_invites_for_me
    ldr  x22, [x8]
    bl   _t_invite_me
    ADRL x8, _g_invites_for_me
    ldr  x23, [x8]
    sub  x23, x23, x22
    ldr  x0, Lid_lab
    bl   _room_find
    mov  x24, x0
    ADRL x0, _g_tkey2
    mov  w1, #0x42
    mov  x2, #64
    bl   _memset
    mov  x0, x24
    ADRL x1, _g_tkey2
    bl   _room_key_set
    ADRL x8, _g_invites_for_me
    ldr  x22, [x8]
    bl   _t_invite_me
    ADRL x8, _g_invites_for_me
    ldr  x9, [x8]
    sub  x9, x9, x22
    cmp  x23, #1
    ccmp x9, #0, #0, eq
    EXPECT_TRUE Ln_inv_rekey

    // 18. an over-long message is trimmed to fit, on a UTF-8 boundary
    STOREPOS
    mov  x20, x0
    ADRL x0, Ltxt_long
    bl   _mesh_send_text
    and  x10, x20, #(STORE_N - 1)
    ADRL x11, _g_store
    add  x21, x11, x10, lsl #SLOT_SHIFT   // slot of the sent packet
    ldr  x22, [x21]                       // packet length
    ADRL x8, _g_nick_len
    ldr  x9, [x8]
    add  x9, x9, #30                      // text offset in a MSG
    sub  x10, x22, x9                     // text bytes
    add  x11, x21, #8
    ldrb w12, [x11, x9]                   // first text byte
    and  x13, x10, #1                     // every "é" is 2 bytes -> must be even
    mov  w14, #0xC3
    cmp  x22, #PKT_MAX
    ccmp x13, #0, #0, ls
    ccmp w12, w14, #0, eq
    EXPECT_TRUE Ln_trim

    // 19. our own message coming back to us is a duplicate
    add  x0, x21, #8
    mov  x1, x22
    bl   _mesh_receive
    EXPECT_EQ 2, Ln_echo

    // 20. names are trimmed and capped at 23 bytes without splitting a character
    ADRL x0, Ls_name_spaces
    bl   _mesh_set_nick
    mov  x20, x0
    ADRL x0, _g_nick
    ADRL x1, Ls_fred
    bl   _strcmp
    cmp  w0, #0
    ccmp x20, #4, #0, eq
    EXPECT_TRUE Ln_name_trim
    ADRL x0, Ltxt_long                    // 300 bytes of "é"
    bl   _mesh_set_nick
    cmp  x0, #22
    EXPECT_TRUE Ln_name_cap

    // 21. a room name cut mid-character is repaired
    add  x0, sp, #96
    ADRL x1, Ls_cut
    bl   _strcpy
    add  x0, sp, #96
    bl   _utf8_fix
    add  x0, sp, #96
    ADRL x1, Ls_ab
    bl   _strcmp
    cmp  w0, #0
    EXPECT_TRUE Ln_utf8fix

    // ---- 0.4: Home devices, the command parser, remote commands ----
    bl   _test_devices                   // x20..x24 and [sp,#160] = device indices

    // 22. "turn off the kitchen lights" -> off, the Kitchen room only
    PARSE Lc_kitchen_off
    ONE_TARGET x20
    ccmp x0, #A_OFF, #0, eq
    EXPECT_TRUE Ln_p_off

    // 23. "dim living room to 30%" -> 30 %
    PARSE Lc_dim_30
    ONE_TARGET x24
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    ccmp x9, #30, #0, eq
    ADRL x8, _g_cmd_action
    ldr  x9, [x8]
    ccmp x9, #A_LEVEL, #0, eq
    EXPECT_TRUE Ln_p_level

    // 24. "desk lamp blue" -> colour 235 degrees
    PARSE Lc_desk_blue
    ONE_TARGET x22
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    mov  x10, #235
    ccmp x9, x10, #0, eq
    ADRL x8, _g_cmd_action
    ldr  x9, [x8]
    ccmp x9, #A_COLOR, #0, eq
    EXPECT_TRUE Ln_p_colour

    // 25. "all lights warm" -> every light (not rooms, locks or shortcuts), 2700 K
    PARSE Lc_all_warm
    ADRL x8, _g_cmd_n
    ldr  x9, [x8]
    ADRL x8, _g_cmd_value
    ldr  x10, [x8]
    mov  x11, #2700
    cmp  x9, #2
    ccmp x10, x11, #0, eq
    ccmp x0, #A_CT, #0, eq
    EXPECT_TRUE Ln_p_all

    // 26. "lock the front door" -> the lock
    PARSE Lc_lock_door
    ONE_TARGET x23
    ccmp x0, #A_LOCK, #0, eq
    EXPECT_TRUE Ln_p_lock

    // 27. "good night" -> no verb, but it names a shortcut
    PARSE Lc_good_night
    ldr  x11, [sp, #160]
    ONE_TARGET x11
    ccmp x0, #A_NONE, #0, eq
    EXPECT_TRUE Ln_p_shortcut

    // 28. "Living Room 40 percent" -> case doesn't matter
    PARSE Lc_lr_40
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    cmp  x9, #40
    ccmp x0, #A_LEVEL, #0, eq
    EXPECT_TRUE Ln_p_case

    // 29. "turn on lamp 2" -> a number in a name is not a brightness
    PARSE Lc_lamp2
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    add  x9, x9, #1                       // -1 -> 0
    cmp  x0, #A_ON
    ccmp x9, #0, #0, eq
    EXPECT_TRUE Ln_p_number

    // 30. whole words only: "on" is not in "front"
    ADRL x0, Lc_front
    ADRL x1, Lc_on
    bl   _has_word
    mov  x20, x0
    ADRL x0, Lc_whats_on
    ADRL x1, Lc_on
    bl   _has_word
    cmp  x20, #0
    ccmp x0, #1, #0, eq
    EXPECT_TRUE Ln_p_words

    // 31. a remote command addressed to us is noticed, not stored or relayed
    ADRL x8, _g_cmds_for_me
    ldr  x20, [x8]
    STOREPOS
    mov  x21, x0
    add  x0, sp, #96
    ADRL x1, Lp_cmd
    mov  x2, #(Lp_cmd_end - Lp_cmd)
    bl   _memcpy
    bl   _new_id
    str  x0, [sp, #(96 + 4)]              // fresh packet id
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [sp, #(96 + 12)]
    add  x0, sp, #96
    mov  x1, #(Lp_cmd_end - Lp_cmd)
    bl   _t_rx
    mov  x22, x0
    ADRL x8, _g_cmds_for_me
    ldr  x9, [x8]
    sub  x9, x9, x20
    STOREPOS
    cmp  x22, #1
    ccmp x9, #1, #0, eq
    ccmp x0, x21, #0, eq
    EXPECT_TRUE Ln_cmd_me

    // 32. someone else's remote command is passed on but never stored
    STOREPOS
    mov  x20, x0
    RX   Lp_cmd
    mov  x21, x0
    STOREPOS
    cmp  x21, #1
    ccmp x0, x20, #0, eq
    EXPECT_TRUE Ln_cmd_other

    // 33. nothing from the mesh lands in the Home room
    ADRL x8, _g_rooms
    ldr  x20, [x8, #(64 + R_UNREAD)]      // Home is room 1
    RX   Lp_home_msg
    ADRL x8, _g_rooms
    ldr  x9, [x8, #(64 + R_UNREAD)]
    cmp  x0, #1
    ccmp x9, x20, #0, eq
    EXPECT_TRUE Ln_home_private

    // 34. a pasted token is cleaned: spaces, newline and "Bearer " removed
    add  x0, sp, #96
    ADRL x1, Lt_messy
    mov  x2, #60
    bl   _token_clean
    mov  x20, x0
    add  x0, sp, #96
    ADRL x1, Lt_clean
    bl   _strcmp
    mov  x9, #36
    cmp  w0, #0
    ccmp x20, x9, #0, eq
    EXPECT_TRUE Ln_token

    // 35. an empty or whitespace-only paste gives no token
    add  x0, sp, #96
    ADRL x1, Lt_blank
    mov  x2, #60
    bl   _token_clean
    cmp  x0, #0
    EXPECT_TRUE Ln_token_empty

    // ---- 0.5: TVs, thermostats, blinds, garage, fans, vacuums; helpers ----
    bl   _test_devices2

    // 36. "tv volume 20" -> the TV, volume 20
    PARSE Lc5_tvvol
    TARGET_IS _t_tv
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    ccmp x9, #20, #0, eq
    ccmp x0, #A_VOLUME, #0, eq
    EXPECT_TRUE Ln5_tvvol

    // 37. "open netflix on the tv" -> an app, not a door; Netflix is app 0
    PARSE Lc5_netflix
    TARGET_IS _t_tv
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    ccmp x9, #0, #0, eq
    mov  x10, #A_APP
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_app

    // 38. "switch to hdmi 2" -> input 2, on the only device with inputs
    PARSE Lc5_hdmi
    TARGET_IS _t_tv
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    ccmp x9, #2, #0, eq
    mov  x10, #A_INPUT
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_hdmi

    // 39. "set the thermostat to 70" -> 70 degrees, the thermostat
    PARSE Lc5_thermo
    TARGET_IS _t_thermo
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    mov  x10, #70
    ccmp x9, x10, #0, eq
    mov  x10, #A_TEMPSET
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_thermo

    // 40. "close the blinds" -> the blinds, not the garage
    PARSE Lc5_blinds
    TARGET_IS _t_blinds
    mov  x10, #A_CLOSE
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_blinds

    // 41. "open the garage" -> the garage door
    PARSE Lc5_garage
    TARGET_IS _t_garage
    mov  x10, #A_OPEN
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_garage

    // 42. "channel 7" -> channel 7 on the TV
    PARSE Lc5_channel
    TARGET_IS _t_tv
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    ccmp x9, #7, #0, eq
    mov  x10, #A_CHANNEL
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_channel

    // 43. "mute" -> the only thing with a volume
    PARSE Lc5_mute
    TARGET_IS _t_tv
    mov  x10, #A_MUTE
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_mute

    // 44. "fan high" -> speed 3
    PARSE Lc5_fan
    TARGET_IS _t_fan
    ADRL x8, _g_cmd_value
    ldr  x9, [x8]
    ccmp x9, #3, #0, eq
    mov  x10, #A_FANSPEED
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_fan

    // 45. "vacuum go home" -> back to the dock
    PARSE Lc5_vac
    TARGET_IS _t_vac
    mov  x10, #A_VACHOME
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_vac

    // 46. "what's the temperature" -> a status question that includes the thermostat
    PARSE Lc5_temp
    mov  x10, #A_STATUS
    cmp  x0, x10
    ADRL x8, _g_cmd_n
    ldr  x9, [x8]
    ccmp x9, #0, #4, eq               // at least one target
    cset w1, ne
    cmp  w1, #1
    EXPECT_TRUE Ln5_status

    // 47. colours for RGB devices: 240 degrees is pure blue, 0 is red
    mov  x0, #240
    bl   _hue_to_rgb
    mov  x20, x0
    mov  x0, #0
    bl   _hue_to_rgb
    mov  x9, #0xFF0000
    cmp  x20, #0xFF
    ccmp x0, x9, #0, eq
    EXPECT_TRUE Ln5_rgb

    // 48. kelvin -> mired, clamped to what an Elgato light takes
    mov  x0, #2700
    mov  x1, #143
    mov  x2, #344
    bl   _mired
    mov  x20, x0
    mov  x0, #6500
    mov  x1, #143
    mov  x2, #344
    bl   _mired
    mov  x9, #344
    mov  x10, #153
    cmp  x20, x9
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln5_mired

    // 49. Bluetooth services get names
    ADRL x0, Lc5_uuid
    bl   _svc_name
    ADRL x1, Lc5_heart
    bl   _strcmp
    cmp  w0, #0
    EXPECT_TRUE Ln5_svc

    // 50. JSON lists: Home Assistant colour modes
    ADRL x0, Lc5_json
    bl   _strlen
    mov  x1, x0
    ADRL x0, Lc5_json
    bl   _json_parse
    mov  x20, x0
    ADRL x1, Lc5_ct
    bl   _jhas
    mov  x21, x0
    mov  x0, x20
    ADRL x1, Lc5_rgb
    bl   _jhas
    cmp  x21, #1
    ccmp x0, #0, #0, eq
    EXPECT_TRUE Ln5_json

    // 51. response tags carry a device number
    ADRL x0, Lc5_tag
    bl   _tag_num
    cmp  x0, #42
    EXPECT_TRUE Ln5_tag

    // 52. SmartThings-style capability masks above 16 bits survive the registry
    ADRL x8, _t_tv
    ldr  x9, [x8]
    ADRL x8, _g_devs
    add  x8, x8, x9, lsl #DEV_SHIFT
    ldr  x9, [x8, #D_CAPS]
    MOVI x10, CAP_TV
    and  x9, x9, x10
    cmp  x9, x10
    EXPECT_TRUE Ln5_caps

    // 53. typed in a chat room: device commands are recognised, chat is not
    ADRL x0, Lc6_tv
    bl   _chat_is_command
    mov  x20, x0
    ADRL x0, Lc6_kitchen
    bl   _chat_is_command
    mov  x21, x0
    ADRL x0, Lc6_onway
    bl   _chat_is_command
    mov  x22, x0
    ADRL x0, Lc6_lockup
    bl   _chat_is_command
    mov  x23, x0
    ADRL x0, Lc6_long
    bl   _chat_is_command
    cmp  x20, #1
    ccmp x21, #1, #0, eq
    ccmp x22, #0, #0, eq
    ccmp x23, #0, #0, eq
    ccmp x0, #0, #0, eq
    EXPECT_TRUE Ln6_route

    // 54. a scene with the same name as a device: "tv off" means the TV
    mov  x0, #K_ST_SCENE
    ADRL x1, Ld6_scene_id
    ADRL x2, Ld6_scene_name
    mov  x3, #CAP_RUN
    bl   _dev_add
    PARSE Lc6_tvoff
    TARGET_IS _t_tv
    mov  x10, #A_OFF
    ccmp x0, x10, #0, eq
    EXPECT_TRUE Ln6_scene

    // 55. "list lights" / "list tvs" filter the device list; "list devices" works from a chat room
    PARSE Lc7_lights
    mov  x20, x0
    bl   _list_filter
    mov  x21, x0
    PARSE Lc7_tvs
    mov  x22, x0
    bl   _list_filter
    mov  x23, x0
    ADRL x0, Lc7_devices
    bl   _chat_is_command
    MOVI x9, CAP_TV
    cmp  x20, #A_LIST
    ccmp x22, #A_LIST, #0, eq
    ccmn x21, #1, #0, eq
    ccmp x23, x9, #0, eq
    ccmp x0, #1, #0, eq
    EXPECT_TRUE Ln7_list

    // 56. distance from signal: -59 dBm is about 1 m, -84 dBm about 10 m
    mov  x0, #-59
    mov  x1, #0x7fff
    bl   _dist_dm
    mov  x20, x0
    mov  x0, #-84
    mov  x1, #0x7fff
    bl   _dist_dm
    mov  x9, #100
    cmp  x20, #10
    ccmp x0, x9, #0, eq
    EXPECT_TRUE Ln7_dist

    // 57. mesh passphrase: sealed text opens with the same passphrase, and a changed
    //     byte (or a changed packet id) is refused
    ADRL x0, Lt_pass
    bl   _crypto_set
    ADRL x0, _g_tbuf
    ADRL x1, Lt_plain
    mov  x2, #64
    bl   _strlcpy
    ADRL x0, _g_tbuf
    mov  x1, #10
    ADRL x2, Lt_aad
    bl   _crypto_seal
    mov  x20, x0                          // 18
    ADRL x0, _g_tbuf
    mov  x1, x20
    ADRL x2, Lt_aad
    ADRL x3, _g_tbuf2
    bl   _crypto_open
    mov  x21, x0
    ADRL x0, _g_tbuf2
    ADRL x1, Lt_plain
    bl   _strcmp
    mov  x22, x0
    ADRL x8, _g_tbuf                      // flip one bit of the ciphertext
    ldrb w9, [x8, #3]
    eor  w9, w9, #1
    strb w9, [x8, #3]
    ADRL x0, _g_tbuf
    mov  x1, x20
    ADRL x2, Lt_aad
    ADRL x3, _g_tbuf2
    bl   _crypto_open
    mov  x23, x0
    ADRL x0, Ls_t_empty                   // passphrase off again
    bl   _crypto_set
    cmp  x20, #18
    ccmp x21, #10, #0, eq
    ccmp x22, #0, #0, eq
    ccmn x23, #1, #0, eq
    EXPECT_TRUE Ln8_crypto

    // 58. without a passphrase, sealed text is reported as such (-2)
    ADRL x0, _g_tbuf
    mov  x1, x20
    ADRL x2, Lt_aad
    ADRL x3, _g_tbuf2
    bl   _crypto_open
    cmn  x0, #2
    EXPECT_TRUE Ln8_nokey

    // 59. TP-Link Kasa: the autokey cipher round-trips
    ADRL x0, _g_tbuf
    ADRL x1, Lt_kasa
    mov  x2, #64
    bl   _strlcpy
    ADRL x0, _g_tbuf
    mov  x1, #20
    mov  w2, #0
    bl   _kasa_cipher
    ADRL x8, _g_tbuf
    ldrb w20, [x8]                        // '{' ^ 171 = 0xd0
    ADRL x0, _g_tbuf
    mov  x1, #20
    mov  w2, #1
    bl   _kasa_cipher
    ADRL x0, _g_tbuf
    ADRL x1, Lt_kasa
    bl   _strcmp
    mov  w9, #0xd0
    cmp  w0, #0
    ccmp w20, w9, #0, eq
    EXPECT_TRUE Ln8_kasa

    // 60. times of day: "7:30 pm", "12 am", "noon", "sunset"; a bare "7" only when not strict
    ADRL x0, Lt_730pm
    mov  x1, #1
    bl   _parse_time
    mov  x20, x0
    ADRL x0, Lt_12am
    mov  x1, #1
    bl   _parse_time
    mov  x21, x0
    ADRL x0, Lt_seven
    mov  x1, #1
    bl   _parse_time
    mov  x22, x0
    ADRL x0, Lt_seven
    mov  x1, #0
    bl   _parse_time
    mov  x23, x0
    ADRL x0, Lt_sunset
    mov  x1, #1
    bl   _parse_time
    mov  x24, x0
    ADRL x0, Lt_noon
    mov  x1, #1
    bl   _parse_time
    mov  x9, #1170
    cmp  x20, x9
    ccmp x21, #0, #0, eq
    ccmn x22, #1, #0, eq
    mov  x9, #420
    ccmp x23, x9, #0, eq
    mov  x9, #2001
    ccmp x24, x9, #0, eq
    mov  x9, #720
    ccmp x0, x9, #0, eq
    EXPECT_TRUE Ln8_times

    // 61. amounts of time: "20 minutes", "2 hrs", "an hour"
    ADRL x0, Lt_20min
    bl   _in_amount
    mov  x20, x0
    ADRL x0, Lt_2hrs
    bl   _in_amount
    mov  x21, x0
    ADRL x0, Lt_anhour
    bl   _in_amount
    mov  x9, #1200
    cmp  x20, x9
    mov  x9, #7200
    ccmp x21, x9, #0, eq
    mov  x9, #3600
    ccmp x0, x9, #0, eq
    EXPECT_TRUE Ln8_amounts

    // 62. "every weekday at 7:15 am turn on the kitchen" -> a repeating rule
    ADRL x8, _g_rule_count
    str  xzr, [x8]
    ADRL x0, Lt_rule1
    mov  x1, #1
    bl   _rule_try
    mov  x20, x0
    ADRL x8, _g_rules
    ldr  x21, [x8, #0]                    // type
    ldr  x22, [x8, #8]                    // days
    ldr  x23, [x8, #16]                   // minute
    ldr  x24, [x8, #64]                   // once
    add  x0, x8, #144
    ADRL x1, Lt_rule1_cmd
    bl   _strcmp
    cmp  x20, #1
    ccmp x21, #2, #0, eq
    mov  x9, #0x3e
    ccmp x22, x9, #0, eq
    mov  x9, #435
    ccmp x23, x9, #0, eq
    ccmp x24, #0, #0, eq
    ccmp w0, #0, #0, eq
    EXPECT_TRUE Ln8_rule1

    // 63. "turn off the lights at 11 pm" -> once, 23:00, the command before "at"
    ADRL x0, Lt_rule2
    mov  x1, #1
    bl   _rule_try
    ADRL x8, _g_rules
    add  x8, x8, #512
    ldr  x21, [x8, #0]
    ldr  x22, [x8, #16]
    ldr  x23, [x8, #64]
    add  x0, x8, #144
    ADRL x1, Lt_rule2_cmd
    bl   _strcmp
    ADRL x8, _g_rule_count
    ldr  x9, [x8]
    cmp  x9, #2
    ccmp x21, #2, #0, eq
    mov  x9, #1380
    ccmp x22, x9, #0, eq
    ccmp x23, #1, #0, eq
    ccmp w0, #0, #0, eq
    EXPECT_TRUE Ln8_rule2

    // 64. "remind me in 10 minutes to check the oven" -> in 600 s, "remind check the oven"
    ADRL x0, Lt_rule3
    mov  x1, #1
    bl   _rule_try
    mov  x0, #0
    bl   _time
    mov  x20, x0
    ADRL x8, _g_rules
    add  x8, x8, #1024
    ldr  x21, [x8, #0]
    ldr  x22, [x8, #24]
    add  x0, x8, #144
    ADRL x1, Lt_rule3_cmd
    bl   _strcmp
    sub  x22, x22, x20                    // 600 s from now, give or take a second
    sub  x22, x22, #598
    cmp  x22, #3
    cset x9, ls
    cmp  x21, #1
    ccmp x9, #1, #0, eq
    ccmp w0, #0, #0, eq
    EXPECT_TRUE Ln8_rule3

    // 65. "when Anna arrives turn on the hall light" / "notify me when the front door opens"
    ADRL x0, Lt_rule4
    mov  x1, #1
    bl   _rule_try
    ADRL x0, Lt_rule5
    mov  x1, #1
    bl   _rule_try
    ADRL x8, _g_rules
    add  x20, x8, #1536
    add  x21, x8, #2048
    add  x0, x20, #80
    ADRL x1, Lt_anna
    bl   _strcmp
    mov  x22, x0
    add  x0, x21, #144
    ADRL x1, Lt_rule5_cmd
    bl   _strcmp
    mov  x23, x0
    ldr  x9, [x20, #0]
    ldr  x10, [x20, #40]
    ldr  x11, [x21, #0]
    ldr  x12, [x21, #32]
    cmp  x9, #3
    ccmp x10, #1, #0, eq
    ccmp x22, #0, #0, eq
    ccmp x11, #4, #0, eq
    mov  x9, #D_OPEN
    ccmp x12, x9, #0, eq
    ccmp x23, #0, #0, eq
    EXPECT_TRUE Ln8_rule4
    ADRL x8, _g_rule_count
    str  xzr, [x8]

    // 66. "11:00" style clock text and ISO times from the forecast
    ADRL x0, Lt_iso
    bl   _hhmm
    mov  x20, x0
    mov  x0, #1170
    ADRL x1, _g_tbuf
    bl   _clock12
    ADRL x1, Lt_clock
    bl   _strcmp
    mov  x9, #419
    cmp  x20, x9
    ccmp w0, #0, #0, eq
    EXPECT_TRUE Ln8_clock

    // 67. the SPIN remote is recognised by name; other devices are not
    ADRL x0, Lt_spinname
    mov  x1, #0
    bl   _spin_is
    mov  x20, x0
    ADRL x0, Lt_notspin
    mov  x1, #0
    bl   _spin_is
    cmp  x20, #1
    ccmp x0, #0, #0, eq
    EXPECT_TRUE Ln8_spin

    // 68. SPIN commands typed in a chat room are run in Home, chat is not
    ADRL x0, Lt_spincol
    bl   _extra_routable
    mov  x20, x0
    ADRL x0, Lt_spindbg
    bl   _extra_routable
    and  x20, x20, x0
    ADRL x0, Lt_spinchat
    bl   _extra_routable
    cmp  x20, #1
    ccmp x0, #0, #0, eq
    EXPECT_TRUE Ln8_spinroute

    // 69. colour-group lists split into trimmed names
    ADRL x0, Lt_glist
    ADRL x1, _g_tbuf
    bl   _spin_next_item
    mov  x20, x0
    ADRL x0, _g_tbuf
    ADRL x1, Lt_g1
    bl   _strcmp
    mov  x21, x0
    mov  x0, x20
    ADRL x1, _g_tbuf
    bl   _spin_next_item
    mov  x20, x0
    ADRL x0, _g_tbuf
    ADRL x1, Lt_g2
    bl   _strcmp
    orr  x21, x21, x0
    mov  x0, x20
    ADRL x1, _g_tbuf
    bl   _spin_next_item
    cmp  x0, #0
    ccmp w21, #0, #0, eq
    EXPECT_TRUE Ln8_glist

    // ---- v3 security ----
    // 70. a signed packet changed on the way is refused
    ADRL x8, _g_t_flip
    mov  x9, #1
    str  x9, [x8]
    RX   Lp_forged
    ADRL x8, _g_t_flip
    str  xzr, [x8]
    EXPECT_EQ 0, Ln9_forged

    // 71. an old packet replayed hours later is refused
    mov  x0, #0
    bl   _time
    mov  x9, #30000
    sub  x0, x0, x9
    ADRL x8, _g_time_override
    str  x0, [x8]
    RX   Lp_stale
    ADRL x8, _g_time_override
    str  xzr, [x8]
    EXPECT_EQ 0, Ln9_stale

    // 72. a message from someone whose key we don't know yet waits, and is shown
    //     once their hello proves who they are
    RX   Lp_carol_msg
    mov  x20, x0
    ldr  x0, Lid_carol
    bl   _node_find
    mov  x21, x0
    RX   Lp_carol_hello
    ADRL x0, _g_txt
    ADRL x1, Ls_held
    bl   _strcmp
    cmp  x20, #1
    ccmn x21, #1, #0, eq                  // not a node before the hello
    ccmp w0, #0, #0, eq                   // shown after it
    EXPECT_TRUE Ln9_pending

    // 73. with a mesh passphrase set, an unencrypted message is ignored
    ADRL x0, Lt_pass
    bl   _crypto_set
    RX   Lp_plain_main
    ADRL x0, Ls_t_empty
    bl   _crypto_set
    ADRL x8, _g_last_refused
    ldr  x9, [x8]
    ldr  x10, Lid_alice
    cmp  x9, x10
    EXPECT_TRUE Ln9_plain

    // 74. both sides of a pair compute the same secret (ECDH)
    ldr  x0, Lid_alice
    ADRL x1, _g_tkey
    bl   _pair_key
    mov  x20, x0
    ADRL x8, _g_tpeer
    ldr  x0, [x8]
    ADRL x8, _g_node_id
    ldr  x1, [x8]
    ADRL x2, _g_tkey2
    bl   _pair_key_with
    mov  x21, x0
    ADRL x0, _g_tkey
    ADRL x1, _g_tkey2
    mov  x2, #64
    bl   _memcmp
    cmp  x20, #1
    ccmp x21, #1, #0, eq
    ccmp w0, #0, #0, eq
    EXPECT_TRUE Ln9_ecdh

    // 75. nobody can use an id that isn't the hash of their own key
    ADRL x8, _g_id_check
    mov  x9, #1
    str  x9, [x8]
    RX   Lp_fake_hello
    ADRL x8, _g_id_check
    str  xzr, [x8]
    EXPECT_EQ 0, Ln9_fakeid

    // 77. a SPIN profile switched on in the window counts as in use, and then
    //     the gesture maps decide what the remote does
    bl   _spin_ghave
    mov  x20, x0
    mov  x0, #2
    bl   _sui_rec
    mov  w9, #1
    strb w9, [x0]
    bl   _spin_ghave
    mov  x21, x0
    mov  x0, #2
    bl   _sui_rec
    strb wzr, [x0]
    cmp  x20, #0
    ccmp x21, #1, #0, eq
    EXPECT_TRUE Ln9_profile

    // 76. our own id is the hash of our key
    ADRL x0, _g_my_pub
    bl   _id_of
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    cmp  x0, x9
    EXPECT_TRUE Ln9_ownid

    // 78. a room deleted by whoever made it disappears; anyone else's word is ignored
    ldr  x0, Lid_lab
    bl   _room_find
    mov  x20, x0
    tbnz x20, #63, 1f
    ADRL x8, _g_rooms                     // "lab" was made by bob…
    add  x8, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, Lid_bob
    str  x9, [x8, #R_OWNER]
    bl   _t_roomdel                       // …so alice can't delete it
    ldr  x0, Lid_lab
    bl   _room_find
    mov  x21, x0
    tbnz x21, #63, 1f
    ADRL x8, _g_rooms                     // made by alice: now she can
    add  x8, x8, x21, lsl #ROOM_SHIFT
    ldr  x9, Lid_alice
    str  x9, [x8, #R_OWNER]
    bl   _t_roomdel
    ldr  x0, Lid_lab
    bl   _room_find
    cmn  x0, #1
    b    2f
1:  mov  x9, #0                           // (lab missing: fail)
    cmp  x9, #1
2:  EXPECT_TRUE Ln_roomdel

    // FM radio and the web over the mesh (fm.s, web.s)
    bl   _fm_selftest
    add  x19, x19, x0
    bl   _web_selftest
    add  x19, x19, x0
    bl   _alerts_selftest             // pushes, weather alerts, the webhook (alerts.s)
    add  x19, x19, x0
    bl   _files_selftest              // the files page (files.s)
    add  x19, x19, x0

    // summary
    str  x19, [sp]
    ADRL x0, Ls_summary
    bl   _printf
    mov  x0, x19
    LEAVE 80

// void _test_devices(void) — a small pretend home; indices in the caller's
// x20 Kitchen, x21 Kitchen ceiling, x22 Desk lamp, x23 Front Door,
// x24 Living room, and [caller sp + 160] Good Night
_test_devices:
    stp  x29, x30, [sp, #-16]!
    mov  x0, #K_HUE_GROUP
    ADRL x1, Ld_id1
    ADRL x2, Ld_kitchen
    mov  x3, #(CAP_ON | CAP_LEVEL | CAP_COLOR | CAP_CT)
    bl   _dev_add
    mov  x20, x0
    mov  x0, #K_HUE_LIGHT
    ADRL x1, Ld_id2
    ADRL x2, Ld_ceiling
    mov  x3, #(CAP_ON | CAP_LEVEL)
    bl   _dev_add
    mov  x21, x0
    mov  x0, #K_HUE_LIGHT
    ADRL x1, Ld_id3
    ADRL x2, Ld_desk
    mov  x3, #(CAP_ON | CAP_LEVEL | CAP_COLOR)
    bl   _dev_add
    mov  x22, x0
    mov  x0, #K_ST
    ADRL x1, Ld_id4
    ADRL x2, Ld_door
    mov  x3, #CAP_LOCK
    bl   _dev_add
    mov  x23, x0
    mov  x0, #K_HUE_GROUP
    ADRL x1, Ld_id5
    ADRL x2, Ld_living
    mov  x3, #(CAP_ON | CAP_LEVEL | CAP_CT)
    bl   _dev_add
    mov  x24, x0
    mov  x0, #K_SHORTCUT
    ADRL x1, Ld_night
    ADRL x2, Ld_night
    mov  x3, #CAP_RUN
    bl   _dev_add
    str  x0, [sp, #(16 + 160)]
    ldp  x29, x30, [sp], #16
    ret

// void _test_devices2(void) — a TV, a thermostat, blinds, a garage door, a fan, a vacuum
_test_devices2:
    stp  x29, x30, [sp, #-16]!
    mov  x0, #K_ST
    ADRL x1, Ld5_id1
    ADRL x2, Ld5_tv
    MOVI x3, (CAP_ON | CAP_VOLUME | CAP_MUTE | CAP_CHANNEL | CAP_INPUT | CAP_MEDIA | CAP_APPS | CAP_TV)
    bl   _dev_add
    ADRL x8, _t_tv
    str  x0, [x8]
    mov  x0, #K_HA
    ADRL x1, Ld5_id2
    ADRL x2, Ld5_thermo
    MOVI x3, (CAP_THERMO | CAP_TEMP | CAP_STATUS)
    bl   _dev_add
    ADRL x8, _t_thermo
    str  x0, [x8]
    mov  x0, #K_HA
    ADRL x1, Ld5_id3
    ADRL x2, Ld5_blinds
    MOVI x3, (CAP_SHADE | CAP_STATUS)
    bl   _dev_add
    ADRL x8, _t_blinds
    str  x0, [x8]
    mov  x0, #K_HA
    ADRL x1, Ld5_id4
    ADRL x2, Ld5_garage
    MOVI x3, (CAP_GARAGE | CAP_STATUS)
    bl   _dev_add
    ADRL x8, _t_garage
    str  x0, [x8]
    mov  x0, #K_HA
    ADRL x1, Ld5_id5
    ADRL x2, Ld5_fan
    MOVI x3, (CAP_ON | CAP_FAN | CAP_LEVEL)
    bl   _dev_add
    ADRL x8, _t_fan
    str  x0, [x8]
    mov  x0, #K_HA
    ADRL x1, Ld5_id6
    ADRL x2, Ld5_vac
    MOVI x3, (CAP_VACUUM | CAP_STATUS)
    bl   _dev_add
    ADRL x8, _t_vac
    str  x0, [x8]
    ldp  x29, x30, [sp], #16
    ret

// long _t_report(const char *name, int pass) -> 0 if pass, 1 if fail
// long _t_rx(const uint8 *pkt, size_t len) — a canned v2-style packet, made into a
//   v3 one signed by the test peer (a HELLO also gets the peer's key), then received
_t_rx:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x21, _g_trx
    mov  x0, x21
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    ldrb w9, [x21, #1]
    cmp  w9, #2
    b.ne Ltr_recv                         // other versions: exactly as they are
    mov  w9, #PROTO_VER
    strb w9, [x21, #1]
    ldrb w9, [x21, #3]
    cmp  w9, #T_HELLO
    b.ne Ltr_sign
    add  x0, x21, x20
    ADRL x1, _g_tpeer_pub
    mov  x2, #PUBLEN
    bl   _memcpy
    add  x20, x20, #PUBLEN
Ltr_sign:
    ADRL x8, _g_tpeer
    ldr  x0, [x8]
    mov  x1, x21
    mov  x2, x20
    bl   _pkt_finish_with
    cbz  x0, Ltr_recv
    mov  x20, x0
    ADRL x8, _g_t_flip
    ldr  x9, [x8]
    cbz  x9, Ltr_recv
    ldrb w9, [x21, #31]
    eor  w9, w9, #1
    strb w9, [x21, #31]
Ltr_recv:
    mov  x0, x21
    mov  x1, x20
    bl   _mesh_receive
    LEAVE 0

// long _t_rx_room(const uint8 *pkt, size_t len, long room_idx) — a room message sealed
//   with that room's key, signed by the test peer, received
_t_rx_room:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x22, x2
    ADRL x21, _g_trx
    mov  x0, x21
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    mov  w9, #PROTO_VER
    strb w9, [x21, #1]
    ldrb w9, [x21, #29]
    add  x23, x9, #30                     // text offset
    mov  x0, x22
    bl   _room_key
    mov  x1, x21
    add  x1, x1, x23
    sub  x2, x20, x23
    add  x3, x21, #4
    bl   _seal_key
    add  x20, x23, x0
    ldrb w9, [x21, #28]
    orr  w9, w9, #MSGF_RKEY
    strb w9, [x21, #28]
    ADRL x8, _g_tpeer
    ldr  x0, [x8]
    mov  x1, x21
    mov  x2, x20
    bl   _pkt_finish_with
    mov  x1, x0
    mov  x0, x21
    bl   _mesh_receive
    LEAVE 0

// long _t_roomdel(void) — alice says: room "lab" is deleted
_t_roomdel:
    ENTER 0
    ADRL x19, _g_tbuf
    mov  w9, #'M'
    strb w9, [x19]
    mov  w9, #2                           // (version 2: _t_rx signs it as alice)
    strb w9, [x19, #1]
    mov  w9, #7
    strb w9, [x19, #2]
    mov  w9, #T_ROOMDEL
    strb w9, [x19, #3]
    bl   _new_id
    str  x0, [x19, #4]
    ldr  x9, Lid_lab
    str  x9, [x19, #12]
    ldr  x9, Lid_alice
    str  x9, [x19, #20]
    mov  w9, #5
    strb w9, [x19, #28]
    add  x0, x19, #29
    ADRL x1, Ls_t_alice
    mov  x2, #5
    bl   _memcpy
    mov  x0, x19
    mov  x1, #34
    bl   _t_rx
    LEAVE 0

// long _t_invite_me(void) — alice invites us into "lab"; sealed with the secret only
//   her key and ours can compute
_t_invite_me:
    ENTER 0
    ADRL x21, _g_trx
    mov  x0, x21
    ADRL x1, Lp_inv_other
    mov  x2, #42                          // header and nick
    bl   _memcpy
    mov  w9, #PROTO_VER
    strb w9, [x21, #1]
    bl   _new_id
    str  x0, [x21, #4]
    ADRL x8, _g_node_id
    ldr  x9, [x8]
    str  x9, [x21, #28]                   // target: us
    mov  w9, #3
    strb w9, [x21, #42]
    add  x0, x21, #43
    ADRL x1, Ls_lab
    mov  x2, #3
    bl   _memcpy
    add  x0, x21, #46
    mov  w1, #0x42
    mov  x2, #64
    bl   _memset
    ADRL x8, _g_tpeer
    ldr  x0, [x8]
    ADRL x8, _g_node_id
    ldr  x1, [x8]
    ADRL x2, _g_tkey
    bl   _pair_key_with
    ADRL x0, _g_tkey
    add  x1, x21, #42
    mov  x2, #68
    add  x3, x21, #4
    bl   _seal_key
    add  x2, x0, #42
    ADRL x8, _g_tpeer
    ldr  x0, [x8]
    mov  x1, x21
    bl   _pkt_finish_with
    mov  x1, x0
    mov  x0, x21
    bl   _mesh_receive
    LEAVE 0

.globl _t_report
_t_report:
    ENTER 0
    mov  w20, w1
    str  x0, [sp]
    ADRL x0, Ls_pass
    ADRL x8, Ls_fail
    cmp  w20, #0
    csel x0, x0, x8, ne
    bl   _printf
    cmp  w20, #0
    cset x0, eq
    LEAVE 0

.data
.p2align 3
_t_tv:      .quad 0
_t_thermo:  .quad 0
_t_blinds:  .quad 0
_t_garage:  .quad 0
_t_fan:     .quad 0
_t_vac:     .quad 0
.text
.p2align 3
Lid_alice:  .quad 0x0A11CE0000000001
Lid_bob:    .quad 0x0B0B000000000001
Lid_lab:    .quad 0x1AB0000000000001
Lid_carol:  .quad 0x0CA2010000000001

// ---------------------------------------------------------------------------
.section __TEXT,__const
// MSG: 'M' 2 ttl 1 | id | room | sender | flags | nlen | nick | text
Lp_msg:
    .byte 'M', 2, 7, 1
    .quad 0x1122334455667788
    .quad 0
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .ascii "hello mesh"
Lp_msg_end:

Lp_ttl1:
    .byte 'M', 2, 1, 1
    .quad 0x2233445566778899
    .quad 0
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .ascii "last hop"
Lp_ttl1_end:

Lp_badmagic:
    .byte 'X', 2, 7, 1
    .quad 0x33445566778899AA
    .quad 0, 0
    .byte 0, 0
    .ascii "nope"
Lp_badmagic_end:

Lp_v1:                                    // a version-1 packet from asmmesh 0.2
    .byte 'M', 1, 7, 5
    .quad 0x3344556677889900
    .ascii "alice"
    .ascii "hello from the past"
Lp_v1_end:

Lp_bignick:
    .byte 'M', 2, 7, 1
    .quad 0x445566778899AABB
    .quad 0, 0
    .byte 0, 30
    .ascii "abcdefghijklmnopqrstuvwxyz0123456789"
Lp_bignick_end:

Lp_short:
    .byte 'M', 2, 7, 1, 1, 2, 3
Lp_short_end:

Lp_bigttl:
    .byte 'M', 2, 200, 1
    .quad 0x5566778899AABBCC
    .quad 0
    .quad 0x0A11CE0000000001
    .byte 0, 3
    .ascii "eve"
    .ascii "flood"
Lp_bigttl_end:

Lp_badtype:
    .byte 'M', 2, 7, 200                  // no such type (9 is now a web page part)
    .quad 0x5566778899AABBDD
    .quad 0, 0
    .byte 0, 3
    .ascii "eve"
    .ascii "what is this"
Lp_badtype_end:

Lp_ctrl:
    .byte 'M', 2, 3, 1
    .quad 0x66778899AABBCCDD
    .quad 0
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .byte 'a', 10, 'b', 27, 'c'
Lp_ctrl_end:

// HELLO: 'M' 2 ttl 2 | id | node | relayed(u32) | nlen | nick     (ttl 6 = 2 hops)
Lp_hello:
    .byte 'M', 2, 6, 2
    .quad 0x778899AABBCCDDEE
    .quad 0x0B0B000000000001
    .long 3
    .byte 3
    .ascii "bob"
Lp_hello_end:

// INVITE: 'M' 2 ttl 3 | id | room | from | target | nlen | nick | rlen | name
Lp_inv_other:
    .byte 'M', 2, 7, 3
    .quad 0x8899AABBCCDDEEFF
    .quad 0x1AB0000000000001
    .quad 0x0A11CE0000000001
    .quad 0x0777000000000001              // somebody else
    .byte 5
    .ascii "alice"
    .fill 80, 1, 0x5A                     // sealed for them: we can't read it
Lp_inv_other_end:

Lp_room_msg:
    .byte 'M', 2, 7, 1
    .quad 0x99AABBCCDDEEFF01
    .quad 0x1AB0000000000001
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .ascii "secret plans"
Lp_room_msg_end:

// CMD: 'M' 2 ttl 4 | id | target | from | nlen | nick | text
Lp_cmd:
    .byte 'M', 2, 7, 4
    .quad 0xABCDEF0123456701
    .quad 0x0777000000000001              // target (the test patches in our id)
    .quad 0x0A11CE0000000001
    .byte 5
    .ascii "alice"
    .byte 0                               // mode: plain
    .ascii "kitchen off"
Lp_cmd_end:

Lp_home_msg:
    .byte 'M', 2, 7, 1
    .quad 0xABCDEF0123456702
    .quad 1                               // HOME_ID
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .ascii "pretending to be your Home room"
Lp_home_msg_end:

Lp_forged:
    .byte 'M', 2, 7, 1
    .quad 0x4F4F4F4F00000001
    .quad 0
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .ascii "changed on the way"
Lp_forged_end:

Lp_stale:
    .byte 'M', 2, 7, 1
    .quad 0x4F4F4F4F00000002
    .quad 0
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .ascii "yesterday's news"
Lp_stale_end:

Lp_carol_msg:
    .byte 'M', 2, 7, 1
    .quad 0x4F4F4F4F00000003
    .quad 0
    .quad 0x0CA2010000000001
    .byte 0, 5
    .ascii "carol"
    .ascii "held till hello"
Lp_carol_msg_end:

Lp_carol_hello:
    .byte 'M', 2, 7, 2
    .quad 0x4F4F4F4F00000004
    .quad 0x0CA2010000000001
    .long 0
    .byte 5
    .ascii "carol"
Lp_carol_hello_end:

Lp_plain_main:
    .byte 'M', 2, 7, 1
    .quad 0x4F4F4F4F00000005
    .quad 0
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .ascii "not sealed"
Lp_plain_main_end:

Lp_fake_hello:
    .byte 'M', 2, 7, 2
    .quad 0x4F4F4F4F00000006
    .quad 0x0B0B000000000002              // not the hash of the key it carries
    .long 0
    .byte 3
    .ascii "bob"
Lp_fake_hello_end:

Lp_room_msg2:
    .byte 'M', 2, 7, 1
    .quad 0x99AABBCCDDEEFF02
    .quad 0x1AB0000000000001
    .quad 0x0A11CE0000000001
    .byte 0, 5
    .ascii "alice"
    .ascii "welcome to the lab"
Lp_room_msg2_end:

.section __TEXT,__cstring,cstring_literals
Ltxt_long:
    .rept 150
    .byte 0xC3, 0xA9                      // "é"
    .endr
    .byte 0
Ls_ctrl_expect:  .asciz "a b c"
Ls_alice:        .asciz "alice"
Ls_bob:          .asciz "bob"
Ls_lab:          .asciz "lab"
Ls_fred:         .asciz "Fred"
Ls_name_spaces:  .asciz "   Fred  "
Ls_cut:          .asciz "ab\303"
Ls_ab:           .asciz "ab"
Ls_pass:         .asciz "PASS  %s\n"
Ls_fail:         .asciz "FAIL  %s\n"
Ls_summary:      .asciz "\n%ld failure(s)\n"
Ln_valid:        .asciz "well-formed Main message is accepted"
Ln_relaycopy:    .asciz "relay copy stored once with ttl 7 -> 6"
Ln_node:         .asciz "sender appears as a node, 1 hop away"
Ln_dup:          .asciz "same packet twice is dropped as a duplicate"
Ln_ttl1:         .asciz "ttl 1 is shown but not relayed"
Ln_badmagic:     .asciz "wrong magic byte is rejected"
Ln_v1:           .asciz "old version-1 packet is rejected"
Ln_bignick:      .asciz "oversized nickname length is rejected"
Ln_short:        .asciz "truncated packet is rejected"
Ln_bigttl:       .asciz "ttl above the maximum is rejected"
Ln_badtype:      .asciz "unknown packet type is rejected"
Ln_ctrl:         .asciz "control characters become spaces"
Ln_hello:        .asciz "HELLO adds name, hops and relay count; relayed but not stored"
Ln_inv_other:    .asciz "invite for someone else is passed on, not shown to us"
Ln_inv_rekey:    .asciz "17b an invite with a new key for a room we are in asks again; the same key does not"
Ln_roomdel:      .asciz "78 a room deleted by whoever made it goes; anyone else's delete is ignored"
Ls_t_alice:      .asciz "alice"
Ln_inv_me:       .asciz "invite for us is noticed and waits for Join"
Ln_room_hidden:  .asciz "message in a room we're not in is relayed quietly"
Ln_unread:       .asciz "message in our other room counts as unread"
Ln_trim:         .asciz "long message trimmed to fit on a UTF-8 boundary"
Ln_echo:         .asciz "our own message echoed back is a duplicate"
Ln_name_trim:    .asciz "name is trimmed of spaces"
Ln_name_cap:     .asciz "name capped at 23 bytes on a character boundary"
Ln_utf8fix:      .asciz "cut-off character at the end is removed"
Ln_p_off:        .asciz "\"turn off the kitchen lights\" -> Kitchen off"
Ln_p_level:      .asciz "\"dim living room to 30%\" -> Living room 30%"
Ln_p_colour:     .asciz "\"desk lamp blue\" -> Desk lamp blue"
Ln_p_all:        .asciz "\"all lights warm\" -> every light, 2700 K"
Ln_p_lock:       .asciz "\"lock the front door\" -> the lock"
Ln_p_shortcut:   .asciz "\"good night\" -> the Good Night shortcut"
Ln_p_case:       .asciz "\"Living Room 40 percent\" -> 40%, any case"
Ln_p_number:     .asciz "\"turn on lamp 2\" -> on, not 2% brightness"
Ln_p_words:      .asciz "whole words only (\"on\" is not in \"front\")"
Ln8_spin:        .asciz "SPIN remote recognised by name, other devices are not"
Lt_spinname:     .asciz "SPIN remote"
Lt_notspin:      .asciz "Kitchen lamp"
Ln9_forged:       .asciz "a signed packet changed on the way is refused"
Ln9_stale:        .asciz "an old packet replayed hours later is refused"
Ln9_pending:      .asciz "a message waits for its sender's hello, then shows"
Ln9_plain:        .asciz "with a mesh passphrase, unencrypted messages are ignored"
Ln9_ecdh:         .asciz "both sides of a pair compute the same secret"
Ln9_fakeid:       .asciz "nobody can use an id that isn't the hash of their key"
Ln9_profile:      .asciz "a SPIN profile switched on counts as in use"
Ln9_ownid:        .asciz "our id is the hash of our own key"
Ls_held:          .asciz "held till hello"
Ln8_glist:       .asciz "SPIN colour group lists split into trimmed device names"
Lt_glist:        .asciz "  Kitchen lamp ,Desk lamp , "
Lt_g1:           .asciz "Kitchen lamp"
Lt_g2:           .asciz "Desk lamp"
Ln8_spinroute:   .asciz "spin commands typed in Main go to Home, chat about spinning does not"
Lt_spincol:      .asciz "Spin colour blue"
Lt_spindbg:      .asciz "spin debug"
Lt_spinchat:     .asciz "spin class was great"
Ln8_crypto:      .asciz "mesh passphrase: sealed text opens, a flipped bit is refused"
Ln8_nokey:       .asciz "without a passphrase, sealed text is reported as locked"
Ln8_kasa:        .asciz "TP-Link Kasa cipher round-trips"
Ln8_times:       .asciz "times of day: 7:30 pm, 12 am, noon, sunset; bare 7 only when not strict"
Ln8_amounts:     .asciz "amounts of time: 20 minutes, 2 hrs, an hour"
Ln8_rule1:       .asciz "\"every weekday at 7:15 am turn on the kitchen\" is a weekday rule"
Ln8_rule2:       .asciz "\"turn off the lights at 11 pm\" is a one-off at 23:00"
Ln8_rule3:       .asciz "\"remind me in 10 minutes to check the oven\""
Ln8_rule4:       .asciz "\"when anna arrives ...\" and \"notify me when the front door opens\""
Ln8_clock:       .asciz "clock text 7:30 pm, forecast time 06:59"
Lt_pass:         .asciz "correct horse battery"
Lt_plain:        .asciz "hello mesh"
Lt_aad:          .asciz "0123456789abcdefghijklmn"
Ls_t_empty:      .asciz ""
Lt_kasa:         .asciz "{\"system\":{\"x\":1}}ab"
Lt_730pm:        .asciz "7:30 pm"
Lt_12am:         .asciz "12 am"
Lt_seven:        .asciz "7"
Lt_sunset:       .asciz "sunset"
Lt_noon:         .asciz "noon"
Lt_20min:        .asciz "20 minutes"
Lt_2hrs:         .asciz "2 hrs"
Lt_anhour:       .asciz "an hour"
Lt_rule1:        .asciz "every weekday at 7:15 am turn on the kitchen"
Lt_rule1_cmd:    .asciz "turn on the kitchen"
Lt_rule2:        .asciz "turn off the lights at 11 pm"
Lt_rule2_cmd:    .asciz "turn off the lights"
Lt_rule3:        .asciz "remind me in 10 minutes to check the oven"
Lt_rule3_cmd:    .asciz "remind check the oven"
Lt_rule4:        .asciz "when anna arrives turn on the hall light"
Lt_rule5:        .asciz "notify me when the front door opens"
Lt_rule5_cmd:    .asciz "notify Front door opened"
Lt_anna:         .asciz "anna"
Lt_iso:          .asciz "2026-09-29T06:59"
Lt_clock:        .asciz "7:30 pm"
Ln_cmd_me:       .asciz "remote command for us is noticed, not stored"
Ln_cmd_other:    .asciz "someone else's remote command is relayed, not stored"
Ln_home_private: .asciz "mesh messages never land in the Home room"
Ln_token:        .asciz "pasted SmartThings token is cleaned up"
Ln_token_empty:  .asciz "blank paste gives no token"
Lt_messy:        .asciz "  Bearer 1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d \n"
Lt_clean:        .asciz "1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d"
Lt_blank:        .asciz "  \n\t "
Lc_kitchen_off:  .asciz "turn off the kitchen lights"
Lc_dim_30:       .asciz "dim living room to 30%"
Lc_desk_blue:    .asciz "desk lamp blue"
Lc_all_warm:     .asciz "all lights warm"
Lc_lock_door:    .asciz "lock the front door"
Lc_good_night:   .asciz "good night"
Lc_lr_40:        .asciz "Living Room 40 percent"
Lc_lamp2:        .asciz "turn on lamp 2"
Lc_front:        .asciz "front door"
Lc_whats_on:     .asciz "what's on"
Lc_on:           .asciz "on"
Ld_id1:          .asciz "1"
Ld_id2:          .asciz "2"
Ld_id3:          .asciz "3"
Ld_id4:          .asciz "st-door"
Ld_id5:          .asciz "5"
Ld_kitchen:      .asciz "Kitchen"
Ld_ceiling:      .asciz "Kitchen ceiling"
Ld_desk:         .asciz "Desk lamp"
Ld_door:         .asciz "Front Door"
Ld_living:       .asciz "Living room"
Ld_night:        .asciz "Good Night"
Ln5_tvvol:       .asciz "\"tv volume 20\" -> the TV, volume 20"
Ln5_app:         .asciz "\"open netflix on the tv\" is an app, not a door"
Ln5_hdmi:        .asciz "\"switch to hdmi 2\" -> input 2"
Ln5_thermo:      .asciz "\"set the thermostat to 70\" -> 70 degrees"
Ln5_blinds:      .asciz "\"close the blinds\" -> the blinds, not the garage"
Ln5_garage:      .asciz "\"open the garage\" -> the garage door"
Ln5_channel:     .asciz "\"channel 7\" -> channel 7"
Ln5_mute:        .asciz "\"mute\" -> the only thing with a volume"
Ln5_fan:         .asciz "\"fan high\" -> speed 3"
Ln5_vac:         .asciz "\"vacuum go home\" -> back to the dock"
Ln5_status:      .asciz "\"what's the temperature\" -> a status question"
Ln5_rgb:         .asciz "hue 240 is blue, 0 is red"
Ln5_mired:       .asciz "kelvin to mired, clamped"
Ln5_svc:         .asciz "Bluetooth 180D is heart rate"
Ln5_json:        .asciz "JSON lists: colour modes"
Ln5_tag:         .asciz "response tags carry a device number"
Ln5_caps:        .asciz "capability bits above 16 survive the registry"
Lc5_tvvol:       .asciz "tv volume 20"
Lc5_netflix:     .asciz "open netflix on the tv"
Lc5_hdmi:        .asciz "switch to hdmi 2"
Lc5_thermo:      .asciz "set the thermostat to 70"
Lc5_blinds:      .asciz "close the blinds"
Lc5_garage:      .asciz "open the garage"
Lc5_channel:     .asciz "channel 7"
Lc5_mute:        .asciz "mute"
Lc5_fan:         .asciz "fan high"
Lc5_vac:         .asciz "vacuum go home"
Lc5_temp:        .asciz "what's the temperature"
Lc5_uuid:        .asciz "180D"
Lc5_heart:       .asciz "heart rate"
Lc5_json:        .asciz "[\"hs\",\"color_temp\"]"
Lc5_ct:          .asciz "color_temp"
Lc5_rgb:         .asciz "rgb"
Lc5_tag:         .asciz "ss42"
Ld5_id1:         .asciz "t5-tv"
Ld5_id2:         .asciz "climate.hall"
Ld5_id3:         .asciz "cover.study_blinds"
Ld5_id4:         .asciz "cover.garage"
Ld5_id5:         .asciz "fan.ceiling"
Ld5_id6:         .asciz "vacuum.robbie"
Ld5_tv:          .asciz "Samsung TV"
Ld5_thermo:      .asciz "Hall Thermostat"
Ld5_blinds:      .asciz "Study Blinds"
Ld5_garage:      .asciz "Garage Door"
Ld5_fan:         .asciz "Ceiling Fan"
Ld5_vac:         .asciz "Robbie"
Ln6_route:       .asciz "device commands typed in a chat room go to Home; chat stays chat"
Lc6_tv:          .asciz "tv volume 10"
Lc6_kitchen:     .asciz "turn off the kitchen lights"
Lc6_onway:       .asciz "on my way"
Lc6_lockup:      .asciz "I'll lock up tonight"
Lc6_long:        .asciz "could you turn the lights off when you leave the office later"
Ln6_scene:       .asciz "\"tv off\" turns off the TV, not a scene called \"TV\""
Lc6_tvoff:       .asciz "tv off"
Ld6_scene_id:    .asciz "scene-tv"
Ld6_scene_name:  .asciz "Samsung TV"
Ln7_list:        .asciz "\"list lights\" and \"list tvs\" filter the device list; \"list devices\" works anywhere"
Ln7_dist:        .asciz "signal to distance: -59 dBm = 1 m, -84 dBm = 10 m"
Lc7_lights:      .asciz "list lights"
Lc7_tvs:         .asciz "list tvs"
Lc7_devices:     .asciz "list devices"
