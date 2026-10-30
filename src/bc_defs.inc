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

// an announce's contents (bc_peer.s _bc_ann_read): pointers into the payload
.set AN_NICK,       0
.set AN_NLEN,       8
.set AN_XPUB,       16          // Noise static key (X25519), 32 bytes
.set AN_EDPUB,      24          // signing key (Ed25519), 32 bytes
.set AN_SIZE,       32

// bitchat people we've heard announce (bc_peer.s): BT_N slots of 256 bytes
.set BT_N,          32
.set BT_SHIFT,      8
.set BT_ID,         0           // peer id: first 8 bytes of SHA-256 of the Noise key
.set BT_HEARD,      8           // ms since 1970 of the last good announce; 0: a free slot
.set BT_FIRST,      16
.set BT_HOPS,       24          // 7 - the TTL it reached us with
.set BT_XPUB,       32
.set BT_EDPUB,      64          // pinned: a later announce with another key is refused
.set BT_NLEN,       96
.set BT_NICK,       104         // up to BT_NICK_MAX bytes of UTF-8, then 0
.set BT_NICK_MAX,   47
.set BT_TS,         152         // the time on their last announce taken (a leave must be later)
.set BT_FRESH,      30000       // a full table never gives up someone heard this recently
.set BT_SIZE,       (BT_N << BT_SHIFT)
.set BT_KEEP,       60000       // forgotten a minute after the last announce (as bitchat)
.set BT_STALE,      900000      // announces older than 15 minutes are ignored (as bitchat)
.set BT_NICK_SEND,  26          // our name in announces: the signed packet stays within 182
                                // bytes (one write on most phone links), and under 100 bytes
                                // of payload, which bitchat never compresses

// public messages (bc_peer.s, Milestone 2)
.set BT_MSG_MAX,    96          // bytes per message we send: one write, never compressed
.set BT_MSG_STALE,  21600000    // older than 6 hours: not shown (as bitchat)
.set BT_RELAY_PS,   20          // packets relayed for bitchat per second, at most
.set BT_VERIFY_PS,  30          // signatures checked for bitchat per second, at most
.set RL_SEC,        0           // the relay limit: which second, and how many in it
.set RL_N,          8
.set RL_SIZE,       16
