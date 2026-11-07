// mt_defs.inc — a Meshtastic radio (mt_core.s, mt_ble.s)
.set MT_FRAME_MAX,  512      // MAX_TO_FROM_RADIO_SIZE
.set MT_TEXT_MAX,   200      // bytes of text we send (a Data payload holds 233)
.set MT_PAYLOAD_MAX, 233
.set MT_PORT_TEXT,  1        // TEXT_MESSAGE_APP (ADMIN_APP 6: never)

// FromRadio: which it holds (_mt_parse's answer)
.set MTK_PACKET,    2
.set MTK_MYINFO,    3
.set MTK_NODE,      4
.set MTK_DONE,      7        // config_complete_id
.set MTK_REBOOTED,  8
.set MTK_CHANNEL,   10

// _mt_parse's fields (MT_HAS bit i: FIELDS[i] in mt.py)
.set MT_HAS,        0
.set MT_FROM,       8        // bit 0
.set MT_TO,         16       // bit 1
.set MT_CHAN,       24       // bit 2
.set MT_PORT,       32       // bit 3
.set MT_PID,        40       // bit 4
.set MT_NUM,        48       // bit 5: my node number, a node's, the complete id, a channel's index
.set MT_TEXT,       56       // bit 6: pointer, MT_TLEN bytes (the payload)
.set MT_TLEN,       64
.set MT_LONG,       72       // bit 7: a node's long name, or a channel's name
.set MT_LLEN,       80
.set MT_SHORT,      88       // bit 8
.set MT_SLEN,       96
.set MT_UID,        104      // bit 9: "!1a2b3c4d"
.set MT_ULEN,       112
.set MT_SEEN,       120      // bit 10: last heard (unix time)
.set MT_ROLE,       128      // bit 11: a channel's role (1 primary)
.set MT_ENC,        136      // bit 12: 1 if the payload is still encrypted (not for us)
.set MT_SIZE,       144
