// macros.inc — shared assembler macros for asmmesh (ARM64, macOS / Mach-O)
//
// Frame layout used by every non-leaf function (ENTER/LEAVE):
//
//   sp + 0   .. 31   : outgoing variadic-argument slots (snprintf, printf)
//   sp + 32  .. 47   : saved x29, x30          (x29 points here)
//   sp + 48  .. 95   : saved x19 .. x24
//   sp + 96  ..      : locals (\locals bytes, multiple of 16)
//
// Apple arm64 ABI reminders:
//   * variadic arguments are ALWAYS passed on the stack, 8 bytes each, at [sp], [sp+8], ...
//   * NSRect / NSSize are homogeneous double aggregates: passed in d0..d3 / d0..d1
//   * x16/x17 are scratch (clobbered by stubs); never keep values in them across a bl

.macro ENTER locals
    sub  sp, sp, #(96 + \locals)
    stp  x29, x30, [sp, #32]
    add  x29, sp, #32
    stp  x19, x20, [sp, #48]
    stp  x21, x22, [sp, #64]
    stp  x23, x24, [sp, #80]
.endm

.macro LEAVE locals
    ldp  x19, x20, [sp, #48]
    ldp  x21, x22, [sp, #64]
    ldp  x23, x24, [sp, #80]
    ldp  x29, x30, [sp, #32]
    add  sp, sp, #(96 + \locals)
    ret
.endm

// address of a symbol defined in this program
.macro ADRL reg, sym
    adrp \reg, \sym@PAGE
    add  \reg, \reg, \sym@PAGEOFF
.endm

// address of an external (dylib/framework) data symbol, via the GOT
.macro LDGOT reg, sym
    adrp \reg, \sym@GOTPAGE
    ldr  \reg, [\reg, \sym@GOTPAGEOFF]
.endm

// load a double constant into a d register
.macro LDD dreg, sym
    adrp x16, \sym@PAGE
    ldr  \dreg, [x16, \sym@PAGEOFF]
.endm

// x0 = objc_getClass(name)
.macro CLS namesym
    ADRL x0, \namesym
    bl   _objc_getClass
.endm

// [rcv sel]                 rcv in x0
.macro MSG0 selsym
    ADRL x1, \selsym
    bl   _msg0
.endm

// [rcv sel:a]               rcv in x0, a in x2
.macro MSG1 selsym
    ADRL x1, \selsym
    bl   _msg1
.endm

// [rcv sel:a b:b]           rcv in x0, args in x2, x3
.macro MSG2 selsym
    ADRL x1, \selsym
    bl   _msg2
.endm

// [rcv sel:a b:b c:c]       rcv in x0, args in x2..x4
.macro MSG3 selsym
    ADRL x1, \selsym
    bl   _msg3
.endm

// [rcv sel:a b:b c:c d:d]   rcv in x0, args in x2..x5
.macro MSG4 selsym
    ADRL x1, \selsym
    bl   _msg4
.endm

// ---------------------------------------------------------------------------
// Protocol v2 and table layouts, shared by every file
// ---------------------------------------------------------------------------
.set PKT_MAX,       240      // largest packet we build or accept
.set HDR,           12       // 'M', version, ttl, type, id[8]
.set PROTO_VER,     3
.set NICK_MAX,      23       // bytes of UTF-8
.set ROOMNAME_MAX,  31
.set TTL0,          7
.set T_MSG,         1
.set T_HELLO,       2
.set T_INVITE,      3
.set T_ROOMDEL,     10       // the room's owner deleted it (+12 room, +20 owner, +28 nlen, +29 nick)
.set T_ROOMAD,      12       // a listed room: +12 room +20 owner +28 nlen +29 nick, name (listed.s)
.set T_JOINREQ,     13       // let me in: +12 room +20 asker +28 nlen +29 nick, owner id (listed.s)
.set T_SEEK,        14       // finding someone: +12 target +20 sender +28 nlen +29 nick, sealed (seek.s)
.set T_HP,          11       // headphones: +12 target (0 any) +20 sender +28 nlen +29 nick, op, hash[16]
.set RL_UNVERIFIED,  1        // limits.s buckets that aren't a sender: packets nobody can check yet
.set RL_RELAY,      2        //   and everything this Mac passes on
.set RL_NEWKEY,     3        //   and new identities' keys taken in
.set RX_BAD,        0
.set RX_NEW,        1
.set RX_DUP,        2

// MSG     +12 room[8] +20 sender[8] +28 flags +29 nlen +30 nick  then text
// HELLO   +12 node[8] +20 relayed(u32) +24 nlen +25 nick
// INVITE  +12 room[8] +20 from[8] +28 target[8] +36 nlen +37 nick  then rlen, room name
.set MSGF_NOTICE,   1        // flags bit: "· Fred joined the room" style line

// node table: 64-byte entries
.set NODE_MAX,      32
.set NODE_SHIFT,    6
.set N_ID,          0
.set N_SEEN,        8        // time_t of last packet from it
.set N_HOPS,        16
.set N_RSSI,        24       // dBm for direct neighbours, 0 = unknown
.set N_RELAYED,     32
.set N_NICK,        40       // 24 bytes, NUL-terminated

// room table: 64-byte entries; room 0 is Main (id 0)
.set ROOM_MAX,      16
.set ROOM_SHIFT,    6
.set R_ID,          0
.set R_UNREAD,      8
.set R_STORE,       16       // NSTextStorage * (retained) holding the transcript
.set R_NAME,        24       // 32 bytes, NUL-terminated
.set R_OWNER,       56       // node id of whoever made the room (0: not known)

// remote commands over the mesh (0.4)
// CMD / CMDRES  +12 target[8] +20 from[8] +28 nlen +29 nick, then UTF-8 text
.set T_CMD,         4
.set T_CMDRES,      5
.set T_SEEN,        6        // which Bluetooth devices a Mac hears, for "where is my ..."
.set MSGF_ENC,      2        // MSG flags bit: text is encrypted with the mesh passphrase
.set MSGF_RKEY,     4        // MSG flags bit: text is encrypted with the room's own key
.set TRAILER,       68       // v3: every packet ends with time(4) + signature(64)
.set PUBLEN,        65       // an uncompressed P-256 public key
.set HOME_ID,       1        // the local-only Home room; never sent on the mesh
.set WEB_ID,        2        // the local Web room: pages fetched by a gateway Mac
.set NEWS_ID,       3        // the local News room: headlines from gateway Macs
.set LOCAL_ROOMS,   4        // ids 1..3 are local rooms, never sent on the mesh
.set T_NEWS,        7        // +12 zero[8] +20 sender[8] +28 nlen +29 nick, mode, headline
.set T_WEBREQ,      8        // +12 gateway[8] (0 any) +20 sender[8] +28 nlen +29 nick, then web.s body
.set T_WEBPART,     9        // +12 requester[8] +20 gateway[8] +28 nlen (0), then web.s body

// device registry (0.5): 256-byte entries
.set DEV_MAX,       256
.set DEV_SHIFT,     8
.set D_KIND,        0
.set D_CAPS,        8
.set D_ON,          16       // 1 on, 0 off, -1 unknown
.set D_LEVEL,       24       // 0..100, -1 unknown
.set D_OBJ,         32       // retained object (a CBPeripheral for Bluetooth bulbs)
.set D_PORT,        40       // TCP port for network devices
.set D_ID,          48       // 64 bytes: the backend's id (string)
.set D_ID_MAX,      64
.set D_NAME,        112      // 64 bytes, display name
.set D_NAME_MAX,    64
.set D_AUX,         176      // 48 bytes: backend scratch (Govee sku, BLE characteristics...)
.set D_AUX_MAX,     48
.set D_ROOM,        224      // 32 bytes: the room it's in ("#id" while not yet known)
.set D_ROOM_MAX,    32
.set K_HUE_LIGHT,   1
.set K_HUE_GROUP,   2
.set K_ST,          3
.set K_SHORTCUT,    4
.set K_HUE_BLE,     5
.set K_ST_SCENE,    6
.set K_WLED,        7
.set K_ELGATO,      8
.set K_SHELLY,      9
.set K_NANOLEAF,    10
.set K_LIFX,        11
.set K_GOVEE,       12
.set K_HA,          13
.set K_ROKU,        14
.set K_WIZ,         15
.set K_SONOS,       16
.set K_KASA,        17
.set K_BLES,        18       // a Bluetooth sensor heard on the air (sensors.s)
.set K_LAST,        18
.set D_OPEN,        (D_AUX + 8)   // SmartThings / Home Assistant: 1 open, 0 closed, -1 unknown
.set D_LOCKED,      (D_AUX + 16)  //   1 locked, 0 unlocked, -1 unknown
.set D_SIDX,        (D_AUX + 0)   // Bluetooth sensor: its index in the sensor table
.set D_MOTION,      (D_AUX + 24)  //   1 motion, 0 clear, -1 unknown
.set D_WET,         (D_AUX + 32)  //   1 water, 0 dry, -1 unknown
.set CAP_ON,        0x1
.set CAP_LEVEL,     0x2
.set CAP_COLOR,     0x4
.set CAP_LOCK,      0x8
.set CAP_RUN,       0x10
.set CAP_CT,        0x20
.set CAP_LINKED,    0x100    // Bluetooth bulb: connected and characteristics found
.set CAP_VOLUME,    0x200
.set CAP_MUTE,      0x400
.set CAP_CHANNEL,   0x800
.set CAP_INPUT,     0x1000
.set CAP_MEDIA,     0x2000
.set CAP_APPS,      0x4000
.set CAP_SHADE,     0x8000
.set CAP_THERMO,    0x10000
.set CAP_FAN,       0x20000
.set CAP_GARAGE,    0x40000
.set CAP_VALVE,     0x80000
.set CAP_VACUUM,    0x100000
.set CAP_STATUS,    0x200000 // has readable state worth reporting
.set CAP_KEYS,      0x400000 // remote-control keys (Roku)
.set CAP_TV,        0x800000
.set CAP_TEMP,      0x1000000 // reports a temperature
.set CAP_POWER,     0x2000000 // reports power or energy use

// parsed command actions
.set A_NONE,        0
.set A_ON,          1
.set A_OFF,         2
.set A_LEVEL,       3
.set A_COLOR,       4
.set A_CT,          5
.set A_LOCK,        6
.set A_UNLOCK,      7
.set A_RUN,         8
.set A_LIST,        9
.set A_HELP,        10
.set A_PAIR,        11
.set A_REFRESH,     12
.set A_BRIGHTER,    13
.set A_DIMMER,      14
.set A_CONNECT,     15       // value: 1 SmartThings 2 Home Assistant 3 LIFX 4 Govee 5 Nanoleaf
.set A_VOLUME,      16
.set A_VOLUP,       17
.set A_VOLDOWN,     18
.set A_MUTE,        19
.set A_UNMUTE,      20
.set A_CHANNEL,     21
.set A_CHUP,        22
.set A_CHDOWN,      23
.set A_INPUT,       24       // value: 0 TV tuner, 1..4 HDMI n
.set A_PLAY,        25
.set A_PAUSE,       26
.set A_STOP,        27
.set A_FFWD,        28
.set A_REWIND,      29
.set A_APP,         30       // value: index into the app table
.set A_OPEN,        31
.set A_CLOSE,       32
.set A_HEATSET,     33
.set A_COOLSET,     34
.set A_TEMPSET,     35
.set A_TMODE,       36       // value: 0 off 1 heat 2 cool 3 auto
.set A_FANSPEED,    37       // value: 1 low 2 medium 3 high
.set A_VACSTART,    38
.set A_VACHOME,     39
.set A_STATUS,      40
.set A_KEY,         41       // value: 0 home 1 back 2 select
.set A_LAST,        41

// MOVI reg, imm32 : any 32-bit constant (capability masks above 16 bits)
.macro MOVI reg, val
    movz \reg, #((\val) & 0xffff)
    movk \reg, #(((\val) >> 16) & 0xffff), lsl #16
.endm

.set APP_COUNT,     8        // Netflix YouTube Prime Disney+ AppleTV Spotify Plex Hulu

// register a selector by name into x1 (clobbers x0)
.macro SELX1 selsym
    ADRL x0, \selsym
    bl   _sel_registerName
    mov  x1, x0
.endm

// nearby Bluetooth devices (not on the mesh): 256-byte entries (near.s)
.set NEAR_MAX,      48
.set NEAR_SHIFT,    9
.set NR_P,          0        // CBPeripheral (retained)
.set NR_RSSI,       8
.set NR_SEEN,       16
.set NR_NAME,       24       // 40 bytes
.set NR_FLAGS,      64
.set NR_TX,         72       // advertised transmit power, dBm
.set NR_CO,         80       // company id from manufacturer data, -1 none
.set NR_MAKER,      88       // const char * or 0
.set NR_SUB,        96       // const char * (Apple advertisement type) or 0
.set NR_PEND,       104      // reads outstanding while inspecting
.set NR_SVCS,       112      // 64 bytes: services, as text
.set NR_T0,         176      // when inspecting started
.set NR_INFO,       184      // 64 bytes: what was read over GATT
.set NR_INFO_MAX,   64
.set NR_AVG,        248      // smoothed signal, dBm x 16
.set NR_FIRST,      256      // when it was first heard (this time around)
.set NR_ALERTED,    264      // tracker alert already given
.set NR_TRUSTED,    272      // a tracker you said is yours
.set NF_CONN,       1        // connectable
.set NF_TX,         2
.set NF_LINKED,     4        // connected by us to inspect it
.set NF_READ,       8        // inspected
.set NF_HK_OPEN,    16       // HomeKit accessory not yet paired
.set NF_MATTER,     32       // Matter device in commissioning mode
.set NF_INSPECT,    64       // Connect & Pair asked for
.set NF_TRACKER,    128      // an item tracker: AirTag / Find My, SmartTag, Tile

// ---------------------------------------------------------------------------
// Services (services.s): every integration has its own switch; all start off
// ---------------------------------------------------------------------------
.set NSVC,          24
.set SVC_HUE,       0
.set SVC_ST,        1        // SmartThings (Lutron and friends ride on it)
.set SVC_HOME,      2        // Apple Home via Shortcuts
.set SVC_WIFI,      3        // WLED, Elgato, Shelly, Nanoleaf, WiZ, Kasa
.set SVC_TV,        4        // Roku, Sonos
.set SVC_LIFX,      5
.set SVC_GOVEE,     6
.set SVC_HA,        7
.set SVC_SPIN,      8
.set SVC_WEATHER,   9
.set SVC_MESH,      10       // commands other people send over the mesh
.set SVC_RULES,     11       // automations
.set SVC_FIND,      12       // find my things / trackers
.set SVC_WEB,       13       // "http get"
.set SVC_VOICE,     14       // the Talk button
.set SVC_FM,        15       // the mesh over an FM transmitter and radio (fm.s)
.set SVC_GATE,      16       // web pages and headlines for Macs without internet (web.s)
.set SVC_LOC,       17       // CoreLocation: SOS says where you are (alerts.s)
.set SVC_NTFY,      18       // pushes through ntfy.sh
.set SVC_PUSHOVER,  19       // pushes through Pushover (SOS as an emergency alert)
.set SVC_NWS,       20       // National Weather Service alerts
.set SVC_HOOK,      21       // incoming webhook on port 8787
.set SVC_FILES,     22       // the files page for your phone, port 8788 (files.s)
.set SVC_SENSORS,   23       // Bluetooth sensors and the battery board (sensors.s)

// one reading from a sensor's advertisement (sens_decode.s); values in hundredths
.set RD_HAVE,       0        // H_* bits: which numbers came
.set RD_TEMP,       8        // degrees C x 100
.set RD_HUM,        16       // % x 100
.set RD_BATT,       24       // %
.set RD_LUX,        32       // lux x 100
.set RD_MOIST,      40       // soil moisture % x 100
.set RD_PRESS,      48       // hPa x 100
.set RD_CO2,        56       // ppm
.set RD_BIN,        64       // BTHome binary sensors: bit (object id - 0x0F) = on
.set RD_BINHAVE,    72       //   and which of them came
.set RD_PID,        80       // BTHome packet id, -1 none
.set RD_NBTN,       88       // button events in this packet
.set RD_BTN,        96       // 4 bytes: event per button (1 press, 2 double, 3 triple, 4 long)
.set RD_KIND,       104      // SK_*
.set RD_SIZE,       112
.set H_TEMP,        1
.set H_HUM,         2
.set H_BATT,        4
.set H_LUX,         8
.set H_MOIST,       16
.set H_PRESS,       32
.set H_CO2,         64
.set SK_BTHOME,     1
.set SK_GOVEE,      2
.set SK_SWITCHBOT,  3
.set SK_XIAOMI,     4
