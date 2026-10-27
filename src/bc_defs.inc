// bc_defs.inc — sizes and layouts shared by the bitchat files (bc_link.s, bc_ble.s)

.set BC_WRITE_MAX,  512         // one ATT write or notification: at most 512 bytes
.set BC_FRAME_CAP,  0x100000    // the most a frame header may announce (1 MiB, as bitchat)

// inbound write buffer (one per link): a write can arrive in pieces with offsets
.set IB_LEN,        0
.set IB_DATA,       8
.set IB_SIZE,       528

// send queue (one per link): frames waiting for the radio
.set Q_N,           8
.set Q_HEAD,        0
.set Q_COUNT,       8
.set Q_DROPS,       16
.set Q_ENT,         24          // Q_N entries: length (8), then BC_WRITE_MAX bytes
.set Q_ESIZE,       528
.set Q_SIZE,        (Q_ENT + Q_N * Q_ESIZE)

// fragment reassembly: FA_N slots
.set FA_N,          8
.set FA_FRAGS,      64          // most fragments in one set
.set FA_BYTES,      8192        // most bytes in one set (text; files are out of scope)
.set FA_TIMEOUT,    30000       // ms
.set FS_USED,       0
.set FS_SENDER,     8
.set FS_ID,         16
.set FS_TOTAL,      24
.set FS_GOT,        32
.set FS_TYPE,       40
.set FS_START,      48
.set FS_BYTES,      56
.set FS_MAP,        64          // bit i: fragment i is here
.set FS_TAB,        72          // FA_FRAGS x (offset u16, length u16)
.set FS_DATA,       328
.set FS_SIZE,       (FS_DATA + FA_BYTES)
.set FA_SIZE,       (FA_N * FS_SIZE)

.set BC_FRAG_HDR,   13          // fragment id 8, index 2, total 2, original type 1
.set BC_FRAG_OVER,  42          // bitchat's fragment frame overhead (13 + 8 + 8 + 13)
.set BC_FRAG_MIN,   64          // smallest chunk bitchat uses
