// mc_core.s — a MeshCore companion radio's frames, pure (no globals, no system calls): what
// asmmesh may send a radio (built here, and nothing else ever let through: _mc_allowed),
// what a radio sends back (read here, every length checked), text as it may be shown, and
// asmmesh's private LoRa channel key from the mesh passphrase. mc_ble.s moves the frames.
// tools/meshcore/mc.py is the Python copy (from MeshCore's docs/companion_protocol.md and
// examples/companion_radio/MyMesh.cpp, meshcore-dev/MeshCore 81dbae5, MIT); mcdiff.py checks
// the two agree on random frames. Self-tests 230-233.
.include "macros.inc"
.include "mc_defs.inc"

.text
.p2align 2

// ---------------------------------------------------------------------------
// What we send (each -> the frame's length)

// long _mc_app_start(uint8 *out) — APP_START: who we are ("asmmesh") (leaf)
.globl _mc_app_start
_mc_app_start:
    mov  w9, #1
    strb w9, [x0]
    stur xzr, [x0, #1]                    // 7 reserved bytes (and one more, overwritten)
    ADRL x10, Lmc_app
    ldr  x11, [x10]                       // "asmmesh\0"
    stur x11, [x0, #8]
    mov  x0, #15
    ret

// long _mc_device_query(uint8 *out) — DEVICE_QUERY, protocol 3 (leaf)
.globl _mc_device_query
_mc_device_query:
    mov  w9, #0x16
    strb w9, [x0]
    mov  w9, #3
    strb w9, [x0, #1]
    mov  x0, #2
    ret

// long _mc_get_contacts(uint8 *out, uint32 since) — GET_CONTACTS (only those changed since) (leaf)
.globl _mc_get_contacts
_mc_get_contacts:
    mov  w9, #4
    strb w9, [x0]
    cbz  w1, 1f
    stur w1, [x0, #1]
    mov  x0, #5
    ret
1:  mov  x0, #1
    ret

// long _mc_sync_next(uint8 *out) — SYNC_NEXT_MESSAGE (leaf)
.globl _mc_sync_next
_mc_sync_next:
    mov  w9, #0x0A
    strb w9, [x0]
    mov  x0, #1
    ret

// long _mc_get_channel(uint8 *out, long i) — GET_CHANNEL (leaf)
.globl _mc_get_channel
_mc_get_channel:
    mov  w9, #0x1F
    strb w9, [x0]
    strb w1, [x0, #1]
    mov  x0, #2
    ret

// long _mc_set_channel(uint8 *out, long i, const char *name, const uint8 secret[16]) -> 50
//   SET_CHANNEL: the name (31 bytes at most, zeros after), the key (leaf)
.globl _mc_set_channel
_mc_set_channel:
    mov  w9, #0x20
    strb w9, [x0]
    strb w1, [x0, #1]
    mov  x9, #0
1:  cmp  x9, #31
    b.hs 2f
    ldrb w10, [x2, x9]
    cbz  w10, 2f
    add  x11, x0, #2
    strb w10, [x11, x9]
    add  x9, x9, #1
    b    1b
2:  cmp  x9, #32
    b.hs 3f
    add  x11, x0, #2
    strb wzr, [x11, x9]
    add  x9, x9, #1
    b    2b
3:  ldp  x10, x11, [x3]
    stur x10, [x0, #34]
    stur x11, [x0, #42]
    mov  x0, #50
    ret

// long _mc_send_chan_txt(uint8 *out, long i, uint32 ts, const char *text, long len)
//   SEND_CHANNEL_TXT_MSG, plain text, cut to 133 bytes between characters
.globl _mc_send_chan_txt
_mc_send_chan_txt:
    ENTER 0
    mov  x19, x0
    mov  w9, #3
    strb w9, [x19]
    strb wzr, [x19, #1]
    strb w1, [x19, #2]
    stur w2, [x19, #3]
    mov  x0, x3
    mov  x1, x4
    mov  x2, #MC_TEXT_MAX
    mov  x20, x3
    bl   _mc_cut_utf8
    mov  x21, x0
    add  x0, x19, #7
    mov  x1, x20
    mov  x2, x21
    bl   Lmc_copy
    add  x0, x21, #7
    LEAVE 0

// long _mc_send_txt(uint8 *out, const uint8 prefix[6], uint32 ts, const char *text, long len)
//   SEND_TXT_MSG: plain (never a CLI command), the first try, to the contact with that key
.globl _mc_send_txt
_mc_send_txt:
    ENTER 0
    mov  x19, x0
    mov  w9, #2
    strb w9, [x19]
    strb wzr, [x19, #1]                   // TXT_TYPE_PLAIN
    strb wzr, [x19, #2]                   // attempt
    stur w2, [x19, #3]
    ldr  w9, [x1]
    stur w9, [x19, #7]
    ldrh w9, [x1, #4]
    sturh w9, [x19, #11]
    mov  x0, x3
    mov  x1, x4
    mov  x2, #MC_TEXT_MAX
    mov  x20, x3
    bl   _mc_cut_utf8
    mov  x21, x0
    add  x0, x19, #13
    mov  x1, x20
    mov  x2, x21
    bl   Lmc_copy
    add  x0, x21, #13
    LEAVE 0

// long _mc_send_chan_data(uint8 *out, long i, const uint8 *payload, long len)
//   SEND_CHANNEL_DATA: flooded, asmmesh's data type, 165 bytes at most
.globl _mc_send_chan_data
_mc_send_chan_data:
    ENTER 0
    mov  x19, x0
    mov  w9, #0x3E
    strb w9, [x19]
    strb w1, [x19, #1]
    mov  w9, #0xFF
    strb w9, [x19, #2]
    mov  w9, #MC_DATA_TYPE
    sturh w9, [x19, #3]
    mov  x9, #MC_DATA_MAX
    cmp  x3, x9
    csel x20, x3, x9, ls
    add  x0, x19, #5
    mov  x1, x2
    mov  x2, x20
    bl   Lmc_copy
    add  x0, x20, #5
    LEAVE 0

// long _mc_cut_utf8(const uint8 *b, long n, long max) -> n, or less: at most max bytes, not
//   inside a character (leaf)
.globl _mc_cut_utf8
_mc_cut_utf8:
    cmp  x1, x2
    b.ls 9f
    mov  x1, x2
1:  cbz  x1, 9f
    ldrb w9, [x0, x1]
    and  w9, w9, #0xC0
    cmp  w9, #0x80
    b.ne 9f
    sub  x1, x1, #1
    b    1b
9:  mov  x0, x1
    ret

// Lmc_copy(x0 dst, x1 src, x2 n) (leaf)
Lmc_copy:
    cbz  x2, 9f
1:  ldrb w9, [x1], #1
    strb w9, [x0], #1
    subs x2, x2, #1
    b.ne 1b
9:  ret

// ---------------------------------------------------------------------------
// The allowlist

// long _mc_allowed(const uint8 *f, long len, long slot) -> 1 if asmmesh may write this frame to
//   a radio, else 0. Everything mc_ble.s writes passes here first. Never: radio settings, power,
//   reboot, factory reset, keys, contacts changed, CLI commands, raw packets — only starting
//   up, reading, our messages, and our own channel (slot, never Public's slot 0) (leaf)
.globl _mc_allowed
_mc_allowed:
    cmp  x1, #1
    b.lo 8f
    cmp  x1, #MC_FRAME_MAX
    b.hi 8f
    ldrb w9, [x0]
    cmp  w9, #1                           // APP_START
    b.eq 7f
    cmp  w9, #0x0A                        // SYNC_NEXT_MESSAGE
    b.ne 1f
    cmp  x1, #1
    b    6f
1:  cmp  w9, #0x16                        // DEVICE_QUERY
    b.ne 2f
    cmp  x1, #2
    b    6f
2:  cmp  w9, #4                           // GET_CONTACTS
    b.ne 3f
    cmp  x1, #1
    ccmp x1, #5, #4, ne
    b    6f
3:  cmp  w9, #0x1F                        // GET_CHANNEL
    b.ne 4f
    cmp  x1, #2
    b    6f
4:  cmp  w9, #3                           // SEND_CHANNEL_TXT_MSG: plain text
    b.ne 5f
    cmp  x1, #8
    b.lo 8f
    ldrb w10, [x0, #1]
    cmp  w10, #0
    b    6f
5:  cmp  w9, #2                           // SEND_TXT_MSG: plain, never a CLI command
    b.ne 51f
    cmp  x1, #14
    b.lo 8f
    ldrb w10, [x0, #1]
    cmp  w10, #0
    b    6f
51: cmp  w9, #0x20                        // SET_CHANNEL: 50 bytes, our slot, not 0, a real key
    b.ne 52f
    cmp  x1, #50
    b.ne 8f
    cbz  x2, 8f
    ldrb w10, [x0, #1]
    cmp  x10, x2
    b.ne 8f
    ldur x10, [x0, #34]
    ldur x11, [x0, #42]
    orr  x10, x10, x11
    cmp  x10, #0
    b.eq 8f
    b    7f
52: cmp  w9, #0x3E                        // SEND_CHANNEL_DATA: flooded, our type, fits
    b.ne 8f
    cmp  x1, #6
    b.lo 8f
    ldrb w10, [x0, #2]
    cmp  w10, #0xFF
    b.ne 8f
    ldurh w10, [x0, #3]
    mov  w11, #MC_DATA_TYPE
    cmp  w10, w11
    b.ne 8f
    sub  x10, x1, #5
    cmp  x10, #MC_DATA_MAX
    b.hi 8f
    b    7f
6:  b.ne 8f
7:  mov  x0, #1
    ret
8:  mov  x0, #0
    ret

// ---------------------------------------------------------------------------
// What the radio sends

// long _mc_parse(const uint8 *f, long len, uint8 mf[MF_SIZE]) -> the frame's kind (byte 0) with
//   its fields in mf (MF_HAS says which), or -1 if it's too short or a length inside it doesn't
//   fit. A kind not read here comes back with no fields (the caller ignores it) (leaf)
.globl _mc_parse
_mc_parse:
    mov  x7, x30                          // (it calls Lmp_name, so the return is kept in x7)
    mov  x15, x0                          // f
    mov  x9, #0                           // clear mf
1:  str  xzr, [x2, x9]
    add  x9, x9, #8
    cmp  x9, #MF_SIZE
    b.lo 1b
    cmp  x1, #1
    b.lo Lmp_bad
    cmp  x1, #255
    b.hi Lmp_bad
    ldrb w14, [x15]                       // the kind
    mov  x13, #0                          // MF_HAS
    cmp  w14, #MCR_OK
    b.eq Lmp_val32
    cmp  w14, #MCR_CEND
    b.eq Lmp_val32
    cmp  w14, #MCR_ACK
    b.eq Lmp_val32
    cmp  w14, #MCR_ERR
    b.eq Lmp_err
    cmp  w14, #MCR_CSTART
    b.eq Lmp_cstart
    cmp  w14, #MCR_CONTACT
    b.eq Lmp_contact
    cmp  w14, #MCR_NEWADV
    b.eq Lmp_contact
    cmp  w14, #MCR_SELF
    b.eq Lmp_self
    cmp  w14, #MCR_SENT
    b.eq Lmp_sent
    cmp  w14, #MCR_DM
    b.eq Lmp_dm
    cmp  w14, #MCR_DM3
    b.eq Lmp_dm3
    cmp  w14, #MCR_CHAN
    b.eq Lmp_chan
    cmp  w14, #MCR_CHAN3
    b.eq Lmp_chan3
    cmp  w14, #MCR_DEVINFO
    b.eq Lmp_dev
    cmp  w14, #MCR_CHINFO
    b.eq Lmp_chinfo
    cmp  w14, #MCR_DATA
    b.eq Lmp_data
    cmp  w14, #MCR_ADVERT
    b.eq Lmp_advert
    b    Lmp_ok                           // a kind we don't read: no fields
Lmp_val32:                                // OK, END_OF_CONTACTS, ACK: a value if there is one
    orr  x13, x13, #1
    cmp  x1, #5
    b.lo Lmp_ok
    ldur w9, [x15, #1]
    str  x9, [x2, #MF_VAL]
    b    Lmp_ok
Lmp_err:
    orr  x13, x13, #1
    cmp  x1, #2
    b.lo Lmp_ok
    ldrb w9, [x15, #1]
    str  x9, [x2, #MF_VAL]
    b    Lmp_ok
Lmp_cstart:
    cmp  x1, #5
    b.lo Lmp_bad
    orr  x13, x13, #1
    ldur w9, [x15, #1]
    str  x9, [x2, #MF_VAL]
    b    Lmp_ok
Lmp_contact:                              // pub key 32, type, flags, path len, path 64, name 32, ts
    cmp  x1, #148
    b.lo Lmp_bad
    add  x9, x15, #1
    str  x9, [x2, #MF_KEY]
    mov  x9, #32
    str  x9, [x2, #MF_KLEN]
    ldrb w9, [x15, #33]
    str  x9, [x2, #MF_VAL2]
    ldrb w9, [x15, #35]
    str  x9, [x2, #MF_PATH]
    add  x0, x15, #100
    mov  x10, #32
    bl   Lmp_name
    ldur w9, [x15, #132]
    str  x9, [x2, #MF_TS]
    mov  x9, #0x1AA                       // val2 path ts key name: bits 1 3 5 7 8
    orr  x13, x13, x9
    b    Lmp_ok
Lmp_self:                                 // ... key at 4, frequency at 48, sf at 56, name at 58
    cmp  x1, #58
    b.lo Lmp_bad
    add  x9, x15, #4
    str  x9, [x2, #MF_KEY]
    mov  x9, #32
    str  x9, [x2, #MF_KLEN]
    ldur w9, [x15, #48]
    str  x9, [x2, #MF_VAL]
    ldrb w9, [x15, #56]
    str  x9, [x2, #MF_VAL2]
    add  x0, x15, #58
    sub  x10, x1, #58
    cmp  x10, #32
    mov  x9, #32
    csel x10, x9, x10, hi
    bl   Lmp_name
    mov  x9, #0x183                       // val val2 key name
    orr  x13, x13, x9
    b    Lmp_ok
Lmp_sent:
    cmp  x1, #10
    b.lo Lmp_bad
    ldrb w9, [x15, #1]
    str  x9, [x2, #MF_VAL]
    ldur w9, [x15, #2]
    str  x9, [x2, #MF_VAL2]
    orr  x13, x13, #3
    b    Lmp_ok
Lmp_dm:                                   // prefix 6, path, text type, ts, [sig 4], text
    cmp  x1, #13
    b.lo Lmp_bad
    add  x9, x15, #1
    mov  x10, #7
    mov  x11, #13
    b    Lmp_dmrest
Lmp_dm3:                                  // snr, 2 reserved, then as above
    cmp  x1, #16
    b.lo Lmp_bad
    ldrsb x9, [x15, #1]
    str  x9, [x2, #MF_SNR]
    orr  x13, x13, #0x40
    add  x9, x15, #4
    mov  x10, #10
    mov  x11, #16
Lmp_dmrest:
    str  x9, [x2, #MF_KEY]
    mov  x9, #6
    str  x9, [x2, #MF_KLEN]
    ldrb w9, [x15, x10]                   // path
    str  x9, [x2, #MF_PATH]
    add  x10, x10, #1
    ldrb w12, [x15, x10]                  // text type
    str  x12, [x2, #MF_TT]
    add  x10, x10, #1
    ldr  w9, [x15, x10]
    str  x9, [x2, #MF_TS]
    cmp  w12, #2                          // signed: 4 bytes of signature first
    b.ne 1f
    add  x11, x11, #4
1:  cmp  x11, x1
    b.hi Lmp_bad
    mov  x9, #0x2B8                       // path tt ts key text: bits 3 4 5 7 9
    orr  x13, x13, x9
    b    Lmp_text
Lmp_chan:                                 // chan, path, text type, ts, text
    cmp  x1, #8
    b.lo Lmp_bad
    mov  x10, #1
    mov  x11, #8
    b    Lmp_chanrest
Lmp_chan3:
    cmp  x1, #11
    b.lo Lmp_bad
    ldrsb x9, [x15, #1]
    str  x9, [x2, #MF_SNR]
    orr  x13, x13, #0x40
    mov  x10, #4
    mov  x11, #11
Lmp_chanrest:
    ldrb w9, [x15, x10]
    str  x9, [x2, #MF_CHAN]
    add  x10, x10, #1
    ldrb w9, [x15, x10]
    str  x9, [x2, #MF_PATH]
    add  x10, x10, #1
    ldrb w9, [x15, x10]
    str  x9, [x2, #MF_TT]
    add  x10, x10, #1
    ldr  w9, [x15, x10]
    str  x9, [x2, #MF_TS]
    mov  x9, #0x23C                       // chan path tt ts text: bits 2 3 4 5 9
    orr  x13, x13, x9
Lmp_text:                                 // the text: from x11 to the end
    add  x9, x15, x11
    str  x9, [x2, #MF_TEXT]
    sub  x9, x1, x11
    str  x9, [x2, #MF_TLEN]
    b    Lmp_ok
Lmp_dev:
    cmp  x1, #2
    b.lo Lmp_bad
    orr  x13, x13, #1
    ldrb w9, [x15, #1]
    str  x9, [x2, #MF_VAL]
    cmp  w9, #3
    b.lo Lmp_ok
    cmp  x1, #4
    b.lo Lmp_ok
    ldrb w9, [x15, #3]                    // max channels
    str  x9, [x2, #MF_VAL2]
    orr  x13, x13, #2
    b    Lmp_ok
Lmp_chinfo:                               // index, name 32, secret 16
    cmp  x1, #50
    b.lo Lmp_bad
    ldrb w9, [x15, #1]
    str  x9, [x2, #MF_CHAN]
    add  x0, x15, #2
    mov  x10, #32
    bl   Lmp_name
    add  x9, x15, #34
    str  x9, [x2, #MF_SECRET]
    mov  x9, #0x504                       // chan name secret: bits 2 8 10
    orr  x13, x13, x9
    b    Lmp_ok
Lmp_data:                                 // snr, 2, chan, path, type 2, length, payload
    cmp  x1, #9
    b.lo Lmp_bad
    ldrb w9, [x15, #8]
    add  x11, x9, #9
    cmp  x11, x1
    b.hi Lmp_bad
    str  x9, [x2, #MF_TLEN]
    add  x9, x15, #9
    str  x9, [x2, #MF_TEXT]
    ldrsb x9, [x15, #1]
    str  x9, [x2, #MF_SNR]
    ldrb w9, [x15, #4]
    str  x9, [x2, #MF_CHAN]
    ldrb w9, [x15, #5]
    str  x9, [x2, #MF_PATH]
    ldurh w9, [x15, #6]
    str  x9, [x2, #MF_VAL2]
    mov  x9, #0x24E                       // val2 chan path snr text: bits 1 2 3 6 9
    orr  x13, x13, x9
    b    Lmp_ok
Lmp_advert:
    cmp  x1, #33
    b.lo Lmp_bad
    add  x9, x15, #1
    str  x9, [x2, #MF_KEY]
    mov  x9, #32
    str  x9, [x2, #MF_KLEN]
    orr  x13, x13, #0x80
Lmp_ok:
    str  x13, [x2, #MF_HAS]
    mov  x0, x14
    ret  x7
Lmp_bad:
    str  xzr, [x2, #MF_HAS]
    mov  x0, #-1
    ret  x7

// Lmp_name (inside _mc_parse: x0 the name's field, x10 its size, x2 mf) — the name, up to its
//   first 0 (uses x9, x12)
Lmp_name:
    str  x0, [x2, #MF_NAME]
    mov  x9, #0
1:  cmp  x9, x10
    b.hs 2f
    ldrb w12, [x0, x9]
    cbz  w12, 2f
    add  x9, x9, #1
    b    1b
2:  str  x9, [x2, #MF_NLEN]
    ret

// ---------------------------------------------------------------------------
// Text as it may be shown

// long _mc_show_text(const uint8 *src, long n, char *dst, long cap) -> bytes in dst: at most
//   cap - 1, not cut inside a character, invalid UTF-8 made '?', and then what _bc_text_clean
//   blanks made spaces (no fake lines, no turned-round text), NUL-terminated
.globl _mc_show_text
_mc_show_text:
    ENTER 0
    mov  x19, x2
    cbz  x3, 8f
    mov  x20, x0
    sub  x2, x3, #1
    bl   _mc_cut_utf8                     // (x0 src, x1 n, x2 cap - 1)
    mov  x21, x0
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lmc_copy
    strb wzr, [x19, x21]
    mov  x0, x19
    mov  x1, x21
    bl   _mc_utf8_fix
    mov  x0, x19
    mov  x1, x19
    mov  x2, x21
    bl   _bc_text_clean
    mov  x0, x21
    LEAVE 0
8:  mov  x0, #0
    LEAVE 0

// void _mc_utf8_fix(uint8 *b, long n) — each byte that doesn't begin a whole, shortest,
//   valid character (no surrogates, nothing past U+10FFFF) becomes '?' (leaf)
.globl _mc_utf8_fix
_mc_utf8_fix:
    mov  x9, #0
Luf_next:
    cmp  x9, x1
    b.hs Luf_done
    ldrb w10, [x0, x9]
    cmp  w10, #0x80
    b.lo Luf_one
    mov  w11, #0x80                       // lo, hi for the second byte; x12 continuation bytes
    mov  w13, #0xBF
    cmp  w10, #0xC2
    b.lo Luf_bad
    cmp  w10, #0xDF
    b.hi 1f
    mov  x12, #1
    b    Luf_check
1:  cmp  w10, #0xE0
    b.ne 2f
    mov  w11, #0xA0
    mov  x12, #2
    b    Luf_check
2:  cmp  w10, #0xED
    b.ne 3f
    mov  w13, #0x9F
    mov  x12, #2
    b    Luf_check
3:  cmp  w10, #0xEF
    b.hi 4f
    mov  x12, #2
    b    Luf_check
4:  cmp  w10, #0xF0
    b.ne 5f
    mov  w11, #0x90
    mov  x12, #3
    b    Luf_check
5:  cmp  w10, #0xF4
    b.hi Luf_bad
    b.ne 6f
    mov  w13, #0x8F
6:  mov  x12, #3
Luf_check:                                // need b[i+1] in lo..hi, the rest 80..BF, all in n
    add  x14, x9, x12
    cmp  x14, x1
    b.hs Luf_bad
    add  x14, x9, #1
    ldrb w15, [x0, x14]
    cmp  w15, w11
    b.lo Luf_bad
    cmp  w15, w13
    b.hi Luf_bad
    mov  x14, #2
7:  cmp  x14, x12
    b.hi 8f
    add  x15, x9, x14
    ldrb w15, [x0, x15]
    and  w15, w15, #0xC0
    cmp  w15, #0x80
    b.ne Luf_bad
    add  x14, x14, #1
    b    7b
8:  add  x9, x9, x12
Luf_one:
    add  x9, x9, #1
    b    Luf_next
Luf_bad:
    mov  w10, #'?'
    strb w10, [x0, x9]
    add  x9, x9, #1
    b    Luf_next
Luf_done:
    ret

// long _mc_sender(const uint8 *text, long n) -> a channel message's sender: the length of
//   "Name" in "Name: text" (1-32), or 0 (leaf)
.globl _mc_sender
_mc_sender:
    mov  x9, #1
1:  cmp  x9, #32
    b.hi 8f
    add  x10, x9, #1
    cmp  x10, x1
    b.hs 8f
    ldrb w11, [x0, x9]
    cmp  w11, #':'
    b.ne 2f
    ldrb w11, [x0, x10]
    cmp  w11, #' '
    b.ne 2f
    mov  x0, x9
    ret
2:  add  x9, x9, #1
    b    1b
8:  mov  x0, #0
    ret

// void _mc_chan_secret(const uint8 *passphrase, long n, uint8 out[16]) — asmmesh's private LoRa
//   channel's key: HKDF-SHA256(salt "asmmesh meshcore channel v1", the passphrase, "secret").
//   No passphrase: from "asmmesh", a key every asmmesh shares (packets are signed and room
//   contents sealed either way)
.globl _mc_chan_secret
_mc_chan_secret:
    ENTER 0
    mov  x19, x2
    cbnz x1, 1f
    ADRL x0, Lmc_app
    mov  x1, #7
1:  mov  x2, x0                           // _bc_hkdf256(salt, slen, ikm, ilen, info, ilen, out, L)
    mov  x3, x1
    ADRL x0, Lmc_salt
    mov  x1, #27
    ADRL x4, Lmc_info
    mov  x5, #6
    mov  x6, x19
    mov  x7, #16
    bl   _bc_hkdf256
    LEAVE 0

// ---------------------------------------------------------------------------
// self-tests 230-233, called from test.s (vectors from tools/meshcore/mc.py vectors)

.globl _mc_core_selftest
_mc_core_selftest:
    ENTER 512                             // [96] frame (256)  [352] mf (120)  [480] key (16)
    mov  x19, #0                          // failures
    // 230. what we send, byte for byte
    mov  x20, #1
    add  x0, sp, #96
    bl   _mc_app_start
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_app
    mov  x2, #15
    bl   Lmt_is
    add  x0, sp, #96
    bl   _mc_device_query
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_query
    mov  x2, #2
    bl   Lmt_is
    add  x0, sp, #96
    mov  w1, #0
    bl   _mc_get_contacts
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_contacts
    mov  x2, #1
    bl   Lmt_is
    add  x0, sp, #96
    mov  w1, #0x0304
    movk w1, #0x0102, lsl #16
    bl   _mc_get_contacts
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_contacts_t
    mov  x2, #5
    bl   Lmt_is
    add  x0, sp, #96
    bl   _mc_sync_next
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_sync
    mov  x2, #1
    bl   Lmt_is
    add  x0, sp, #96
    mov  x1, #3
    bl   _mc_get_channel
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_getchan
    mov  x2, #2
    bl   Lmt_is
    add  x0, sp, #96
    mov  x1, #3
    ADRL x2, Lmc_app
    ADRL x3, Lv_key16
    bl   _mc_set_channel
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_setchan
    mov  x2, #50
    bl   Lmt_is
    add  x0, sp, #96
    mov  x1, #0
    mov  w2, #0x1000
    movk w2, #0x5f5e, lsl #16
    ADRL x3, Lv_hello
    mov  x4, #13
    bl   _mc_send_chan_txt
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_chantxt
    mov  x2, #20
    bl   Lmt_is
    add  x0, sp, #96
    ADRL x1, Lv_prefix
    mov  w2, #0x1000
    movk w2, #0x5f5e, lsl #16
    ADRL x3, Lv_hianna
    mov  x4, #7
    bl   _mc_send_txt
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_dm
    mov  x2, #20
    bl   Lmt_is
    add  x0, sp, #96
    mov  x1, #3
    ADRL x2, Lv_abcd
    mov  x3, #2
    bl   _mc_send_chan_data
    add  x0, sp, #96                      // (x0 was the length)
    ADRL x1, Lv_data
    mov  x2, #7
    bl   Lmt_is
    add  x0, sp, #96                      // 80 é (160 bytes) cut to 66 é: 133 would split one
    mov  x1, #0
    mov  w2, #1
    ADRL x3, Lv_eacute
    mov  x4, #160
    bl   _mc_send_chan_txt
    cmp  x0, #139
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_230
    bl   _t_report
    add  x19, x19, x0
    // 231. what the radio sends: each kind read, and every short or overlong one refused
    mov  x20, #1
    ADRL x21, Lv_frames
2:  ldrb w22, [x21]                       // tests: length, expected kind (+1; 0 = bad), frame
    cbz  w22, 3f
    ldrb w23, [x21, #1]                   // (0xff: refused, as -1 & 0xff)
    add  x0, x21, #2
    mov  x1, x22
    add  x2, sp, #352
    bl   _mc_parse
    and  x0, x0, #0xff
    cmp  x0, x23
    cset x9, eq
    and  x20, x20, x9
    add  x21, x21, #2
    add  x21, x21, x22
    b    2b
3:  ADRL x0, Lv_chan3                     // a channel message: its fields
    mov  x1, #19
    add  x2, sp, #352
    bl   _mc_parse
    cmp  x0, #0x11
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MF_CHAN)]
    cmp  x9, #2
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MF_SNR)]
    cmn  x9, #8                           // -8: -2 dB
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MF_TLEN)]
    cmp  x9, #8
    cset x9, eq
    and  x20, x20, x9
    ldr  x0, [sp, #(352 + MF_TEXT)]
    mov  x1, #8
    bl   _mc_sender
    cmp  x0, #3                           // "Bob: hi" -> "Bob"
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lv_dmsig                     // a signed direct message: text after the signature
    mov  x1, #22
    add  x2, sp, #352
    bl   _mc_parse
    cmp  x0, #0x10
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MF_TLEN)]
    cmp  x9, #2
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #(352 + MF_TEXT)]
    ldrh w9, [x9]
    mov  w10, #0x6968                     // "hi"
    cmp  w9, w10
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_231
    bl   _t_report
    add  x19, x19, x0
    // 232. the allowlist: only what's on it, with its rules
    mov  x20, #1
    mov  x21, #0                          // every first byte: a one-byte frame, and a long one
4:  cmp  x21, #256
    b.hs 6f
    add  x9, sp, #96
    mov  x10, #0
5:  strb wzr, [x9, x10]
    add  x10, x10, #1
    cmp  x10, #50
    b.lo 5b
    strb w21, [x9]
    add  x0, sp, #96
    mov  x1, #1
    mov  x2, #3
    bl   _mc_allowed
    mov  x22, x0
    cmp  x21, #1                          // alone, only these: APP_START, SYNC, GET_CONTACTS
    ccmp x21, #0x0A, #4, ne
    ccmp x21, #4, #4, ne
    cset x9, eq
    cmp  x22, x9
    cset x9, eq
    and  x20, x20, x9
    add  x21, x21, #1
    b    4b
6:  ADRL x22, Lv_allow                    // cases: length, slot, expected, frame
7:  ldrb w23, [x22]
    cbz  w23, 8f
    add  x0, x22, #3
    mov  x1, x23
    ldrb w2, [x22, #1]
    bl   _mc_allowed
    ldrb w9, [x22, #2]
    cmp  x0, x9
    cset x9, eq
    and  x20, x20, x9
    add  x22, x22, #3
    add  x22, x22, x23
    b    7b
8:  mov  w1, w20
    ADRL x0, Ln_232
    bl   _t_report
    add  x19, x19, x0
    // 233. text as shown, and the channel's key
    mov  x20, #1
    ADRL x0, Lv_dirty                     // "a" RLO "b" LF "c" C0-80 "d" E2-82 (cut)
    mov  x1, #13
    add  x2, sp, #96
    mov  x3, #64
    bl   _mc_show_text
    cmp  x0, #13
    cset x9, eq
    and  x20, x20, x9
    add  x0, sp, #96
    ADRL x1, Lv_clean
    mov  x2, #14
    bl   Lmt_is
    ADRL x0, Lv_eacute                    // cut to cap - 1 = 4: two é, not one and a half
    mov  x1, #160
    add  x2, sp, #96
    mov  x3, #6
    bl   _mc_show_text
    cmp  x0, #4
    cset x9, eq
    and  x20, x20, x9
    ADRL x0, Lv_pass
    mov  x1, #13
    add  x2, sp, #480
    bl   _mc_chan_secret
    add  x0, sp, #480
    ADRL x1, Lv_secret
    mov  x2, #16
    bl   Lmt_is
    ADRL x0, Lv_pass
    mov  x1, #0
    add  x2, sp, #480
    bl   _mc_chan_secret
    add  x0, sp, #480
    ADRL x1, Lv_secret0
    mov  x2, #16
    bl   Lmt_is
    mov  w1, w20
    ADRL x0, Ln_233
    bl   _t_report
    add  x19, x19, x0
    mov  x0, x19
    LEAVE 512

// Lmt_is(x0 a, x1 b, x2 n) — x20 &= (n bytes the same) (leaf)
Lmt_is:
    cbz  x2, 2f
1:  ldrb w9, [x0], #1
    ldrb w10, [x1], #1
    cmp  w9, w10
    b.ne 3f
    subs x2, x2, #1
    b.ne 1b
2:  ret
3:  mov  x20, #0
    ret

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 3
Lmc_app:        .ascii "asmmesh\0"        // 8 bytes: APP_START reads them as one
Lmc_salt:       .ascii "asmmesh meshcore channel v1"
Lmc_info:       .ascii "secret"
Lv_app:         .byte 0x01,0,0,0,0,0,0,0, 0x61,0x73,0x6d,0x6d,0x65,0x73,0x68
Lv_query:       .byte 0x16, 0x03
Lv_contacts:    .byte 0x04
Lv_contacts_t:  .byte 0x04, 0x04, 0x03, 0x02, 0x01
Lv_sync:        .byte 0x0a
Lv_getchan:     .byte 0x1f, 0x03
Lv_key16:       .byte 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
Lv_setchan:     .byte 0x20, 0x03, 0x61,0x73,0x6d,0x6d,0x65,0x73,0x68
                .space 25
                .byte 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
Lv_hello:       .byte 0x68,0xc3,0xa9,0x6c,0x6c,0x6f,0x20,0x77,0xc3,0xb6,0x72,0x6c,0x64   // héllo wörld
Lv_chantxt:     .byte 0x03,0x00,0x00, 0x00,0x10,0x5e,0x5f
                .byte 0x68,0xc3,0xa9,0x6c,0x6c,0x6f,0x20,0x77,0xc3,0xb6,0x72,0x6c,0x64
Lv_prefix:      .byte 0xa1,0xb2,0xc3,0xd4,0xe5,0xf6
Lv_hianna:      .ascii "hi Anna"
Lv_dm:          .byte 0x02,0x00,0x00, 0x00,0x10,0x5e,0x5f, 0xa1,0xb2,0xc3,0xd4,0xe5,0xf6
                .ascii "hi Anna"
Lv_abcd:        .byte 0xab, 0xcd
Lv_data:        .byte 0x3e,0x03,0xff,0xff,0xff,0xab,0xcd
Lv_eacute:      .rept 80
                .byte 0xc3, 0xa9
                .endr
Lv_pass:        .ascii "correct horse"
Lv_secret:      .byte 0x80,0x59,0x6e,0x41,0x4d,0x06,0x98,0x3b,0xc9,0x69,0x62,0xad,0x3e,0x7d,0x79,0x2a
Lv_secret0:     .byte 0x2d,0xd6,0x51,0xd9,0xce,0x17,0xa0,0x27,0x8d,0x0d,0xd6,0xe6,0xfc,0x0c,0x9f,0xb9
// a channel message, v3: snr -8, chan 2, path 1, plain, ts, "Bob: hi!"
Lv_chan3:       .byte 0x11, 0xf8, 0, 0, 2, 1, 0, 0x10,0x5e,0x5f,0x00
                .ascii "Bob: hi!"
// a signed direct message, v3: prefix, path, type 2, ts, signature 4, "hi"
Lv_dmsig:       .byte 0x10, 0, 0, 0, 1,2,3,4,5,6, 0, 2, 0,0,0,0, 9,9,9,9
                .ascii "hi"
Lv_dirty:       .byte 0x61, 0xe2,0x80,0xae, 0x62, 0x0a, 0x63, 0xc0,0x80, 0x64, 0xe2,0x82, 0x21
Lv_clean:       .byte 0x61, 0x20,0x20,0x20, 0x62, 0x20, 0x63, 0x3f,0x3f, 0x64, 0x3f,0x3f, 0x21, 0
// parse cases: length, kind expected (-1 bad), the frame
Lv_frames:
    .byte 1, 0x0a,  0x0a                          // no more messages
    .byte 1, 0x83,  0x83                          // messages waiting
    .byte 5, 0x00,  0x00, 1, 0, 0, 0              // OK with a value
    .byte 1, 0x00,  0x00                          // OK without
    .byte 2, 0x01,  0x01, 6                       // error 6
    .byte 4, 0xff,  0x02, 1, 2, 3                 // contacts start, short
    .byte 7, 0xff,  0x08, 0, 0, 0, 0, 0, 0        // channel message, short
    .byte 10, 0xff, 0x11, 0, 0, 0, 0, 0, 0, 0, 0, 0   // v3 channel message, short
    .byte 12, 0xff, 0x07, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   // direct, short
    .byte 15, 0xff, 0x07, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0   // signed, no room for it
    .byte 9, 0xff,  0x1b, 0, 0, 0, 0, 0, 0xff, 0xff, 5   // data: says 5 bytes, has 0
    .byte 9, 0x1b,  0x1b, 0, 0, 0, 0, 0, 0xff, 0xff, 0   // data: empty
    .byte 32, 0xff, 0x80                          // advert, short
    .space 31
    .byte 57, 0xff, 0x05                          // self info, short
    .space 56
    .byte 147, 0xff, 0x03                         // contact, short
    .space 146
    .byte 2, 0x42,  0x42, 0                       // a kind not read: no fields
    .byte 0
// allowlist cases: length, slot, allowed?, frame
Lv_allow:
    .byte 2, 3, 1,  0x16, 0x03                    // DEVICE_QUERY
    .byte 3, 3, 0,  0x16, 0x03, 0                 //   too long
    .byte 5, 3, 1,  0x04, 1, 2, 3, 4              // GET_CONTACTS since
    .byte 2, 3, 0,  0x04, 1                       //   odd length
    .byte 2, 3, 1,  0x1f, 1                       // GET_CHANNEL
    .byte 8, 3, 1,  0x03, 0, 0, 1, 2, 3, 4, 0x68  // channel text, plain
    .byte 8, 3, 0,  0x03, 1, 0, 1, 2, 3, 4, 0x68  //   not plain
    .byte 7, 3, 0,  0x03, 0, 0, 1, 2, 3, 4        //   no text
    .byte 14, 3, 1, 0x02, 0, 0, 1,2,3,4, 1,2,3,4,5,6, 0x68   // direct, plain
    .byte 14, 3, 0, 0x02, 1, 0, 1,2,3,4, 1,2,3,4,5,6, 0x68   //   a CLI command: never
    .byte 14, 3, 0, 0x02, 3, 0, 1,2,3,4, 1,2,3,4,5,6, 0x68   //   CLI command (explicit)
    .byte 50, 3, 1, 0x20, 3                       // SET_CHANNEL our slot
    .space 32
    .byte 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
    .byte 50, 3, 0, 0x20, 0                       //   Public's slot 0: never
    .space 32
    .byte 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
    .byte 50, 3, 0, 0x20, 4                       //   another slot
    .space 32
    .byte 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
    .byte 50, 3, 0, 0x20, 3                       //   a zero key
    .space 48
    .byte 50, 0, 0, 0x20, 0                       //   no slot of ours yet
    .space 32
    .byte 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16
    .byte 7, 3, 1,  0x3e, 3, 0xff, 0xff, 0xff, 1, 2   // channel data, ours
    .byte 7, 3, 0,  0x3e, 3, 0x00, 0xff, 0xff, 1, 2   //   not flooded (a path)
    .byte 7, 3, 0,  0x3e, 3, 0xff, 0x01, 0x00, 1, 2   //   someone else's type
    .byte 11, 3, 0, 0x0b, 0x10, 0x27, 0, 0, 0x40, 0x0d, 0x03, 0, 7, 5   // SET_RADIO_PARAMS
    .byte 7, 3, 0,  0x13, 0x72, 0x65, 0x62, 0x6f, 0x6f, 0x74             // REBOOT "reboot"
    .byte 1, 3, 0,  0x17                          // EXPORT_PRIVATE_KEY
    .byte 1, 3, 0,  0x33                          // FACTORY_RESET
    .byte 0

.section __TEXT,__cstring,cstring_literals
Ln_230: .asciz "230 meshcore: commands built byte for byte; text cut between characters"
Ln_231: .asciz "231 meshcore: radio frames read; short ones and lengths that don't fit refused"
Ln_232: .asciz "232 meshcore: only allowed commands reach a radio (no settings, reboot, keys, CLI)"
Ln_233: .asciz "233 meshcore: text cleaned for showing; the channel key from the passphrase"
