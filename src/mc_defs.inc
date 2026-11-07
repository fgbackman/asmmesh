// mc_defs.inc — MeshCore companion radio (mc_core.s, mc_ble.s)
.set MC_FRAME_MAX,  172      // the most we ever write to a radio (it takes 176)
.set MC_TEXT_MAX,   133      // a message's text, bytes (MeshCore's limit)
.set MC_DATA_MAX,   165      // channel data payload (MAX_GROUP_DATA_LENGTH)
.set MC_DATA_TYPE,  0xFFFF   // DATA_TYPE_DEV until asmmesh has a registered number

// frames the radio sends (byte 0)
.set MCR_OK,        0x00
.set MCR_ERR,       0x01
.set MCR_CSTART,    0x02     // contacts: start (count)
.set MCR_CONTACT,   0x03
.set MCR_CEND,      0x04
.set MCR_SELF,      0x05     // reply to APP_START
.set MCR_SENT,      0x06
.set MCR_DM,        0x07     // a direct message (old format)
.set MCR_CHAN,      0x08     // a channel message (old format)
.set MCR_NOMORE,    0x0A
.set MCR_DEVINFO,   0x0D
.set MCR_DM3,       0x10
.set MCR_CHAN3,     0x11
.set MCR_CHINFO,    0x12
.set MCR_DATA,      0x1B     // channel data
.set MCR_ADVERT,    0x80     // someone known advertised (key)
.set MCR_ACK,       0x82
.set MCR_WAITING,   0x83     // messages waiting: sync them
.set MCR_NEWADV,    0x8A     // someone new advertised (a contact record)

// _mc_parse's answer: which fields are there (MF_HAS bits), and them
.set MF_HAS,        0
.set MF_VAL,        8        // bit 0: OK's value, error code, contact count, firmware, route
.set MF_VAL2,       16       // bit 1: contact type, frequency's sf, max channels, tag, data type
.set MF_CHAN,       24       // bit 2
.set MF_PATH,       32       // bit 3
.set MF_TT,         40       // bit 4: text type
.set MF_TS,         48       // bit 5
.set MF_SNR,        56       // bit 6: signed, x4
.set MF_KEY,        64       // bit 7: a pointer into the frame, MF_KLEN bytes (32, or a 6-byte prefix)
.set MF_KLEN,       72
.set MF_NAME,       80       // bit 8: pointer, MF_NLEN bytes (not NUL-terminated)
.set MF_NLEN,       88
.set MF_TEXT,       96       // bit 9: pointer, MF_TLEN bytes (not cleaned: see _mc_show_text)
.set MF_TLEN,       104
.set MF_SECRET,     112      // bit 10: pointer, 16 bytes
.set MF_SIZE,       120
