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

// a decoded packet (bc_packet.s): numbers, and pointers into the frame or the caller's buffer
.set DP_VER,        0
.set DP_TYPE,       8
.set DP_TTL,        16
.set DP_TS,         24          // ms since 1970
.set DP_FLAGS,      32          // as on the wire
.set DP_SENDER,     40          // -> 8 bytes
.set DP_RCPT,       48          // -> 8 bytes, or 0
.set DP_HOPS,       56          // source route: how many hops
.set DP_ROUTE,      64          // -> hops x 8 bytes, or 0
.set DP_PAY,        72          // -> the payload (decompressed into the caller's buffer)
.set DP_PLEN,       80
.set DP_SIG,        88          // -> 64 bytes, or 0
.set DP_WIRE,       96          // -> the frame it came from
.set DP_SIGAT,      104         // where the signature starts in it (the end of what's signed)
.set DP_SIZE,       112

.set BC_FRAMED,     1179760     // bitchat's FileTransferLimits.maxFramedFileBytes
.set BC_RATIO,      1032        // most a byte of DEFLATE can stand for (PacketPayloadLimits)

// the duplicate filter: bitchat's id is sender, time, type and 4 bytes of SHA-256(payload),
// kept 5 minutes, 1000 of them
.set DD_N,          1000
.set DD_AGE,        300000      // ms
.set DD_POS,        0
.set DD_ENT,        8           // DD_N x 32: sender, time, type << 32 | digest, when seen + 1
.set DD_SIZE,       (DD_ENT + DD_N * 32)
