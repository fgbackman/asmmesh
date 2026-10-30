// ident.s — who is who on the mesh (protocol v3).
//
// Every Mac has its own P-256 identity key, made on first run and kept in the
// Keychain ("asmmesh.keys", together with the private rooms' keys). Its mesh id
// is the first 8 bytes of SHA-256(public key), so nobody can use someone else's
// id without their private key.
//
// Every packet ends with a 68-byte trailer: the time it was made (u32 seconds)
// and an ECDSA P-256 signature (raw r||s, 64 bytes) over the whole packet with
// its hop counter zeroed (relays change that byte). HELLOs also carry the
// sender's public key just before the trailer, so everyone learns it; other
// packets are checked against the key learned from the sender's HELLO. A
// packet from someone whose HELLO hasn't arrived yet waits here (pending) and
// is shown once the HELLO proves who sent it. Packets older than 6 hours or
// from more than 10 minutes in the future are refused (replays).
//
// Pairwise secrets (invites, device commands) come from ECDH between our key
// and theirs, run through the X9.63 KDF with SHA-256 -> 64 bytes: 32 for
// AES-256-CTR and 32 for HMAC-SHA256 (crypto.s does the sealing).
//
// Private rooms each have a random 64-byte key (AES + HMAC), handed over inside
// the invite, sealed with the pairwise secret of the two people.

.include "macros.inc"

.set KEYS_N,    64
.set KE_SIZE,   96          // +0 id, +8 in use, +16 public key[65], +88 SecKeyRef
.set KE_PUB,    16
.set KE_REF,    88
.set KE_SEEN,   84          // u32: when a signature of theirs last checked out
.set PEND_N,    8
.set PE_SHIFT,  8           // 256-byte slots: +0 length, +8 packet
.set PRIVLEN,   97
.set RK_SIZE,   72          // room key rows: +0 set, +8 key[64] (AES + HMAC)
.set MAX_AGE,   21600       // 6 hours
.set MAX_AHEAD, 600         // 10 minutes of clock difference

.data
.p2align 3
.globl _g_id_ready
_g_id_ready:    .quad 0
.globl _g_id_priv
_g_id_priv:     .quad 0
_g_id_pubref:   .quad 0
_g_keys_pos:    .quad 0
_g_pend_pos:    .quad 0
_g_skew_t:      .quad 0                // when we last said a clock was off
.globl _g_id_check
_g_id_check:    .quad 1                // tests switch off "id = hash of key" for canned ids
.globl _g_rx_replay
_g_rx_replay:   .quad 0                // 1 while a pending packet is being re-read
.globl _g_time_override
_g_time_override: .quad 0              // tests: sign as if at this time
_g_id_kcst:     .quad 0                // what the Keychain said when the identity was read
.globl _g_my_pub
.zerofill __DATA,__bss,_g_my_pub,72,4
.zerofill __DATA,__bss,_g_keys,6144,4
.zerofill __DATA,__bss,_g_pend,2048,4
.zerofill __DATA,__bss,_g_sigbuf,256,4
.zerofill __DATA,__bss,_g_hash,32,4
.zerofill __DATA,__bss,_g_kcblob,2400,4
.globl _g_room_keys
.zerofill __DATA,__bss,_g_room_keys,(ROOM_MAX * RK_SIZE),4

.text
.p2align 2

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

// id _cfdata(const void *bytes, size_t n) — autoreleased NSData
_cfdata:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    CLS  Ls_NSData
    mov  x2, x19
    mov  x3, x20
    MSG2 Ls_dataWithBytes
    LEAVE 0

// id _ec_attrs(long which) — 0 public key, 1 private key, 2 for making a new pair
_ec_attrs:
    ENTER 0
    mov  x19, x0
    CLS  Ls_NSMutableDictionary
    MSG0 Ls_dictionary
    mov  x20, x0
    LDGOT x8, _kSecAttrKeyTypeECSECPrimeRandom
    ldr  x2, [x8]
    LDGOT x8, _kSecAttrKeyType
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
    cmp  x19, #2
    b.eq Lea_size
    LDGOT x8, _kSecAttrKeyClassPrivate
    ldr  x2, [x8]
    LDGOT x9, _kSecAttrKeyClassPublic
    ldr  x9, [x9]
    cmp  x19, #0
    csel x2, x9, x2, eq
    LDGOT x8, _kSecAttrKeyClass
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
Lea_size:
    CLS  Ls_NSNumber
    mov  x2, #256
    MSG1 Ls_numberWithInt
    mov  x2, x0
    LDGOT x8, _kSecAttrKeySizeInBits
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
    mov  x0, x20
    LEAVE 0

// void _hex_enc(const uint8 *src, size_t n, char *dst) — 2n hex digits + NUL
.globl _hex_enc
_hex_enc:
    ADRL x9, Ls_hexdig
    mov  x10, #0
Lhe_loop:
    cmp  x10, x1
    b.hs Lhe_done
    ldrb w11, [x0, x10]
    lsr  w12, w11, #4
    and  w11, w11, #15
    ldrb w12, [x9, x12]
    ldrb w11, [x9, x11]
    strb w12, [x2], #1
    strb w11, [x2], #1
    add  x10, x10, #1
    b    Lhe_loop
Lhe_done:
    strb wzr, [x2]
    ret

// long _hex_dec(const char *src, size_t nbytes, uint8 *dst) -> 1 ok, 0 not hex
.globl _hex_dec
_hex_dec:
    mov  x10, #0
Lhd_loop:
    cmp  x10, x1
    b.hs Lhd_ok
    mov  x13, #0
    mov  x14, #2
Lhd_nib:
    ldrb w11, [x0], #1
    sub  w12, w11, #'0'
    cmp  w12, #9
    b.ls Lhd_have
    orr  w11, w11, #0x20
    sub  w12, w11, #'a'
    cmp  w12, #5
    b.hi Lhd_bad
    add  w12, w12, #10
Lhd_have:
    lsl  w13, w13, #4
    orr  w13, w13, w12
    subs x14, x14, #1
    b.ne Lhd_nib
    strb w13, [x2, x10]
    add  x10, x10, #1
    b    Lhd_loop
Lhd_ok:
    mov  x0, #1
    ret
Lhd_bad:
    mov  x0, #0
    ret

// char *_fp(uint64 id, char *buf /*15*/) -> "7KQ2-M9XD-4TRW": 60 of the id's 64 bits in
//   Crockford base32 (no I, L, O or U, so it reads aloud without mix-ups)
.globl _fp
_fp:
    ADRL x10, Ls_b32dig
    mov  x11, x1
    mov  x9, #55                      // the top 5 of the 60 bits first
    mov  x12, #0
Lfp_loop:
    lsr  x13, x0, x9
    and  x13, x13, #31
    ldrb w13, [x10, x13]
    strb w13, [x11], #1
    add  x12, x12, #1
    cmp  x12, #4
    ccmp x12, #8, #4, ne
    b.ne Lfp_next
    mov  w13, #'-'                    // groups of four
    strb w13, [x11], #1
Lfp_next:
    subs x9, x9, #5
    b.pl Lfp_loop
    strb wzr, [x11]
    mov  x0, x1
    ret

// ---------------------------------------------------------------------------
// Our identity
// ---------------------------------------------------------------------------

// SecKeyRef _key_generate(void) -> a new private key (+1), or 0
.globl _key_generate
_key_generate:
    ENTER 16
    mov  x0, #2
    bl   _ec_attrs
    str  xzr, [sp, #96]
    add  x1, sp, #96
    bl   _SecKeyCreateRandomKey
    LEAVE 16

// long _key_pub(SecKeyRef priv, uint8 *out65) -> 1 if exported
.globl _key_pub
_key_pub:
    ENTER 0
    mov  x20, x1
    bl   _SecKeyCopyPublicKey
    cbz  x0, Lkp_no
    mov  x19, x0
    mov  x1, #0
    bl   _SecKeyCopyExternalRepresentation
    mov  x21, x0
    mov  x0, x19
    bl   _CFRelease
    cbz  x21, Lkp_no
    mov  x0, x21
    MSG0 Ls_length
    cmp  x0, #PUBLEN
    b.ne Lkp_rel
    mov  x0, x21
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x20
    mov  x2, #PUBLEN
    bl   _memcpy
    mov  x0, x21
    bl   _CFRelease
    mov  x0, #1
    LEAVE 0
Lkp_rel:
    mov  x0, x21
    bl   _CFRelease
Lkp_no:
    mov  x0, #0
    LEAVE 0

// uint64 _id_of(const uint8 *pub65) — the mesh id that key owns
.globl _id_of
_id_of:
    ENTER 0
    mov  w1, #PUBLEN
    ADRL x2, _g_hash
    bl   _CC_SHA256
    ADRL x8, _g_hash
    ldr  x0, [x8]
    orr  x0, x0, #1                   // never zero, like every id
    LEAVE 0

// long _id_adopt(SecKeyRef priv) — make it ours: public key, mesh id, ready
.globl _id_adopt
_id_adopt:
    ENTER 0
    mov  x19, x0
    ADRL x1, _g_my_pub
    bl   _key_pub
    cbz  x0, Lia_no
    ADRL x8, _g_id_priv
    ldr  x0, [x8]
    cbz  x0, Lia_set
    bl   _CFRelease
Lia_set:
    ADRL x8, _g_id_priv
    str  x19, [x8]
    ADRL x0, _g_my_pub
    bl   _id_of
    ADRL x8, _g_node_id
    str  x0, [x8]
    ADRL x1, _g_my_pub                // we know our own key, like anyone's
    bl   _key_put
    ADRL x8, _g_id_ready
    mov  x9, #1
    str  x9, [x8]
    mov  x0, #1
    LEAVE 0
Lia_no:
    mov  x0, #0
    LEAVE 0

// long _id_generate(void) — a brand-new identity (first run, and the self-tests)
.globl _id_generate
_id_generate:
    ENTER 0
    bl   _key_generate
    cbz  x0, Lig_no
    bl   _id_adopt
    LEAVE 0
Lig_no:
    mov  x0, #0
    LEAVE 0

// long _id_import(const uint8 *priv97) -> 1 if it is a usable key
_id_import:
    ENTER 16
    mov  x1, #PRIVLEN
    bl   _cfdata
    mov  x19, x0
    mov  x0, #1
    bl   _ec_attrs
    mov  x1, x0
    mov  x0, x19
    str  xzr, [sp, #96]
    add  x2, sp, #96
    bl   _SecKeyCreateWithData
    cbz  x0, Lii_no
    bl   _id_adopt
    LEAVE 16
Lii_no:
    mov  x0, #0
    LEAVE 16

// long _id_export(uint8 *out97) -> 1 if exported
_id_export:
    ENTER 0
    mov  x20, x0
    ADRL x8, _g_id_priv
    ldr  x0, [x8]
    cbz  x0, Lie_no
    mov  x1, #0
    bl   _SecKeyCopyExternalRepresentation
    cbz  x0, Lie_no
    mov  x21, x0
    MSG0 Ls_length
    cmp  x0, #PRIVLEN
    b.ne Lie_rel
    mov  x0, x21
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x20
    mov  x2, #PRIVLEN
    bl   _memcpy
    mov  x0, x21
    bl   _CFRelease
    mov  x0, #1
    LEAVE 0
Lie_rel:
    mov  x0, x21
    bl   _CFRelease
Lie_no:
    mov  x0, #0
    LEAVE 0

// void _id_kc_read(void) — background: our identity and room keys from the Keychain
.globl _id_kc_read
_id_kc_read:
    ENTER 0
    ADRL x0, Ls_kc_keys
    ADRL x1, _g_kcblob
    mov  x2, #2400
    bl   _kc_get
    ADRL x8, _g_id_kcst               // what the Keychain said to this read: _g_kc_status
    str  x1, [x8]                     //   is shared by every reader on every thread
    LEAVE 0

// void _id_ready(void) — main thread, after _id_kc_read: adopt or create our key,
//   put the room keys back, tell Main who we are, and say hello
.globl _id_ready
_id_ready:
    ENTER 128                         // [96] private key / one room record
    mov  x20, #1                      // always save: rooms may have new keys
    ADRL x19, _g_kcblob
    ldrb w9, [x19]
    cbnz w9, Lir_have
    ADRL x8, _g_id_kcst               // nothing came back: only make a new identity if the
    ldr  x9, [x8]                      //   Keychain truly has none — never because it said no
    mov  w10, #-25300                 //   (that would replace your identity for good)
    cmp  w9, w10
    b.eq Lir_new
    cbz  w9, Lir_new
    mov  x1, x9
    ADRL x0, Lf_id_locked
    bl   _chat_fmt
    LEAVE 128
Lir_have:
    mov  x0, x19
    mov  x1, #PRIVLEN
    add  x2, sp, #96
    bl   _hex_dec
    cbz  x0, Lir_new
    add  x0, sp, #96
    bl   _id_import
    cbnz x0, Lir_rooms
Lir_new:
    bl   _id_generate
    cbz  x0, Lir_fail
    mov  x20, #1
Lir_rooms:
    add  x21, x19, #(PRIVLEN * 2)
Lir_room:
    mov  x0, x21
    bl   _strlen
    cmp  x0, #144
    b.lo Lir_fill
    mov  x0, x21
    mov  x1, #72
    add  x2, sp, #96
    bl   _hex_dec
    add  x21, x21, #144
    cbz  x0, Lir_room
    ldr  x0, [sp, #96]
    bl   _room_find
    tbnz x0, #63, Lir_room
    add  x1, sp, #104
    bl   _room_key_set
    b    Lir_room
Lir_fill:
    bl   _room_keys_fill
    orr  x20, x20, x0
    cbz  x20, Lir_hello
    bl   _keys_save
Lir_hello:
    ADRL x8, _g_node_id
    ldr  x0, [x8]
    add  x1, sp, #96
    bl   _fp
    mov  x1, x0
    ADRL x0, Lf_id_msg
    bl   _chat_fmt
    bl   _mesh_send_hello
    bl   _ui_lists_changed
    LEAVE 128
Lir_fail:
    ADRL x0, Ls_id_fail
    bl   _chat_line
    LEAVE 128

// void _keys_save(void) — identity + every private room's key, into the Keychain
.globl _keys_save
_keys_save:
    ENTER 160                         // [96] one record (priv97 / id+key 40)
    ADRL x8, _g_no_persist
    ldr  x9, [x8]
    cbnz x9, Lks_done
    ADRL x8, _g_id_ready
    ldr  x9, [x8]
    cbz  x9, Lks_done
    add  x0, sp, #96
    bl   _id_export
    cbz  x0, Lks_done
    add  x0, sp, #96
    mov  x1, #PRIVLEN
    ADRL x2, _g_kcblob
    bl   _hex_enc
    ADRL x21, _g_kcblob
    add  x21, x21, #(PRIVLEN * 2)
    mov  x19, #1
Lks_room:
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lks_write
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    sub  x10, x9, #1                  // local rooms have no key
    cmp  x10, #(LOCAL_ROOMS - 2)
    b.ls Lks_next
    str  x9, [sp, #96]
    mov  x0, x19
    bl   _room_key
    cbz  x0, Lks_next
    mov  x1, x0
    add  x0, sp, #104
    mov  x2, #64
    bl   _memcpy
    add  x0, sp, #96
    mov  x1, #72
    mov  x2, x21
    bl   _hex_enc
    add  x21, x21, #144
Lks_next:
    add  x19, x19, #1
    b    Lks_room
Lks_write:
    ADRL x0, Ls_kc_keys
    ADRL x1, _g_kcblob
    bl   _kc_set
Lks_done:
    LEAVE 160

// ---------------------------------------------------------------------------
// Room keys (parallel to the room table)
// ---------------------------------------------------------------------------

// uint8 *_room_key(long idx) -> its key, or 0
.globl _room_key
_room_key:
    ADRL x8, _g_room_keys
    mov  x9, #RK_SIZE
    madd x8, x0, x9, x8
    ldr  x9, [x8]
    cbz  x9, Lrk_none
    add  x0, x8, #8
    ret
Lrk_none:
    mov  x0, #0
    ret

// void _room_key_set(long idx, const uint8 *key64)
.globl _room_key_set
_room_key_set:
    ADRL x8, _g_room_keys
    mov  x9, #RK_SIZE
    madd x8, x0, x9, x8
    mov  x9, #1
    str  x9, [x8]
    mov  x10, #0
Lrks_copy:
    ldr  x9, [x1, x10]
    add  x11, x8, #8
    str  x9, [x11, x10]
    add  x10, x10, #8
    cmp  x10, #64
    b.lo Lrks_copy
    ret

// void _room_key_new(long idx) — a fresh random key
.globl _room_key_new
_room_key_new:
    ENTER 0
    ADRL x8, _g_room_keys
    mov  x9, #RK_SIZE
    madd x19, x0, x9, x8
    mov  x9, #1
    str  x9, [x19]
    add  x0, x19, #8
    mov  x1, #64
    bl   _arc4random_buf
    LEAVE 0

// void _room_key_clear(long idx)
.globl _room_key_clear
_room_key_clear:
    ADRL x8, _g_room_keys
    mov  x9, #RK_SIZE
    madd x8, x0, x9, x8
    mov  x10, #0
Lrkc_loop:
    str  xzr, [x8, x10]
    add  x10, x10, #8
    cmp  x10, #RK_SIZE
    b.lo Lrkc_loop
    ret

// void _room_keys_remove(long idx, long count) — shift the rows after idx down
.globl _room_keys_remove
_room_keys_remove:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x8, _g_room_keys
    mov  x9, #RK_SIZE
    madd x0, x19, x9, x8
    add  x1, x0, #RK_SIZE
    sub  x10, x20, x19
    sub  x10, x10, #1
    mul  x2, x10, x9
    bl   _memmove
    sub  x0, x20, #1
    bl   _room_key_clear
    LEAVE 0

// long _room_keys_fill(void) -> 1 if a private room had no key and got one
_room_keys_fill:
    ENTER 0
    mov  x19, #1
    mov  x20, #0
Lrf2_loop:
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x19, x9
    b.hs Lrf2_done
    ADRL x8, _g_rooms
    add  x8, x8, x19, lsl #ROOM_SHIFT
    ldr  x9, [x8, #R_ID]
    sub  x10, x9, #1
    cmp  x10, #(LOCAL_ROOMS - 2)
    b.ls Lrf2_next
    mov  x0, x19
    bl   _room_key
    cbnz x0, Lrf2_next
    mov  x0, x19
    bl   _room_key_new
    mov  x20, #1
Lrf2_next:
    add  x19, x19, #1
    b    Lrf2_loop
Lrf2_done:
    mov  x0, x20
    LEAVE 0

// ---------------------------------------------------------------------------
// Other people's keys
// ---------------------------------------------------------------------------

// uint8 *_key_find(uint64 id) -> its entry, or 0
.globl _key_find
_key_find:
    ADRL x8, _g_keys
    mov  x9, #0
Lkf_loop:
    cmp  x9, #KEYS_N
    b.hs Lkf_none
    ldr  x10, [x8, #8]
    cbz  x10, Lkf_next
    ldr  x10, [x8]
    cmp  x10, x0
    b.eq Lkf_hit
Lkf_next:
    add  x8, x8, #KE_SIZE
    add  x9, x9, #1
    b    Lkf_loop
Lkf_hit:
    mov  x0, x8
    ret
Lkf_none:
    mov  x0, #0
    ret

// SecKeyRef _pub_ref(const uint8 *pub65) -> a public key object (+1), or 0
.globl _pub_ref
_pub_ref:
    ENTER 16
    mov  x1, #PUBLEN
    bl   _cfdata
    mov  x19, x0
    mov  x0, #0
    bl   _ec_attrs
    mov  x1, x0
    mov  x0, x19
    str  xzr, [sp, #96]
    add  x2, sp, #96
    bl   _SecKeyCreateWithData
    LEAVE 16

// uint8 *_key_put(uint64 id, const uint8 *pub65) -> its entry (0 if not a key)
.globl _key_put
_key_put:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x20
    bl   _pub_ref
    cbz  x0, Lkpt_no
    mov  x21, x0
    mov  x0, x19
    bl   _key_find
    cbnz x0, Lkpt_have
    mov  x0, #RL_NEWKEY               // new identities are taken at most one a second
    mov  x1, #1                       //   (16 at once), so a flood of made-up ones can't
    mov  x2, #16                      //   push out the people actually talking
    mov  x3, #1
    bl   _rate_take
    cbz  x0, Lkpt_refused
    ADRL x8, _g_keys                  // a free row, else the one quiet longest
    mov  x9, #0
    mov  x0, x8
    mov  w11, #-1
1:  cmp  x9, #KEYS_N
    b.hs Lkpt_have
    mov  x10, #KE_SIZE
    madd x12, x9, x10, x8
    ldr  x13, [x12, #8]
    cbz  x13, 2f
    ldr  w13, [x12, #KE_SEEN]
    cmp  w13, w11
    b.hs 3f
    mov  w11, w13
    mov  x0, x12
3:  add  x9, x9, #1
    b    1b
2:  mov  x0, x12
Lkpt_have:
    mov  x22, x0
    ldr  x0, [x22, #KE_REF]
    cbz  x0, Lkpt_fill
    bl   _CFRelease
Lkpt_fill:
    str  x19, [x22]
    mov  x9, #1
    str  x9, [x22, #8]
    add  x0, x22, #KE_PUB
    mov  x1, x20
    mov  x2, #PUBLEN
    bl   _memcpy
    str  x21, [x22, #KE_REF]
    mov  x0, #0
    bl   _time
    str  w0, [x22, #KE_SEEN]
    mov  x0, x22
    LEAVE 0
Lkpt_refused:
    mov  x0, x21
    bl   _CFRelease
Lkpt_no:
    mov  x0, #0
    LEAVE 0

// ---------------------------------------------------------------------------
// Signatures and the packet trailer
// ---------------------------------------------------------------------------

// void _pkt_hash(const uint8 *pkt, size_t n, uint8 *out32) — SHA-256 with the hop byte zeroed
_pkt_hash:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    cmp  x20, #256
    mov  x9, #256
    csel x20, x9, x20, hi
    ADRL x0, _g_sigbuf
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
    ADRL x0, _g_sigbuf
    strb wzr, [x0, #2]
    mov  x1, x20
    mov  x2, x21
    bl   _CC_SHA256
    LEAVE 0

// long _sign_digest(SecKeyRef priv, const uint8 *digest32, uint8 *out64) -> 1 ok
_sign_digest:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, x20
    mov  x1, #32
    bl   _cfdata
    mov  x2, x0
    LDGOT x8, _kSecKeyAlgorithmECDSASignatureRFC4754
    ldr  x1, [x8]
    mov  x0, x19
    mov  x3, #0
    bl   _SecKeyCreateSignature
    cbz  x0, Lsd_no
    mov  x22, x0
    MSG0 Ls_length
    cmp  x0, #64
    b.ne Lsd_rel
    mov  x0, x22
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x21
    mov  x2, #64
    bl   _memcpy
    mov  x0, x22
    bl   _CFRelease
    mov  x0, #1
    LEAVE 0
Lsd_rel:
    mov  x0, x22
    bl   _CFRelease
Lsd_no:
    mov  x0, #0
    LEAVE 0

// long _verify_digest(SecKeyRef pub, const uint8 *digest32, const uint8 *sig64) -> 1 ok
_verify_digest:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    cbz  x19, Lvd_no
    mov  x0, x20
    mov  x1, #32
    bl   _cfdata
    mov  x22, x0
    mov  x0, x21
    mov  x1, #64
    bl   _cfdata
    mov  x3, x0
    mov  x2, x22
    LDGOT x8, _kSecKeyAlgorithmECDSASignatureRFC4754
    ldr  x1, [x8]
    mov  x0, x19
    mov  x4, #0
    bl   _SecKeyVerifySignature
    and  x0, x0, #0xff
    LEAVE 0
Lvd_no:
    mov  x0, #0
    LEAVE 0

// size_t _pkt_finish_with(SecKeyRef priv, uint8 *pkt, size_t len) -> len + 68, or 0
.globl _pkt_finish_with
_pkt_finish_with:
    ENTER 0
    mov  x21, x0
    mov  x19, x1
    mov  x20, x2
    cbz  x21, Lpf_no
    add  x9, x20, #TRAILER
    cmp  x9, #PKT_MAX
    b.hi Lpf_no
    ADRL x8, _g_time_override
    ldr  x0, [x8]
    cbnz x0, Lpf_time
    mov  x0, #0
    bl   _time
Lpf_time:
    str  w0, [x19, x20]
    add  x20, x20, #4
    mov  x0, x19
    mov  x1, x20
    ADRL x2, _g_hash
    bl   _pkt_hash
    mov  x0, x21
    ADRL x1, _g_hash
    add  x2, x19, x20
    bl   _sign_digest
    cbz  x0, Lpf_no
    add  x0, x20, #64
    LEAVE 0
Lpf_no:
    mov  x0, #0
    LEAVE 0

// size_t _pkt_finish(uint8 *pkt, size_t len) — signed by us
.globl _pkt_finish
_pkt_finish:
    ENTER 0
    mov  x2, x1
    mov  x1, x0
    ADRL x8, _g_id_ready
    ldr  x9, [x8]
    cbz  x9, Lpfm_no
    ADRL x8, _g_id_priv
    ldr  x0, [x8]
    bl   _pkt_finish_with
    LEAVE 0
Lpfm_no:
    mov  x0, #0
    LEAVE 0

// long _pkt_check(const uint8 *pkt, size_t len, SecKeyRef pub) -> 1 genuine,
//   0 forged / damaged, 2 too old or from the future (a replay)
.globl _pkt_check
_pkt_check:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    cmp  x20, #TRAILER
    b.lo Lpc_bad
    sub  x20, x20, #64                // signed part: everything up to the signature
    sub  x9, x20, #4
    ldr  w22, [x19, x9]               // when it was made
    mov  x0, #0
    bl   _time
    mov  x9, #MAX_AHEAD
    add  x9, x0, x9
    cmp  x22, x9
    b.hi Lpc_stale
    mov  x9, #MAX_AGE
    sub  x9, x0, x9
    cmp  x22, x9
    b.lt Lpc_stale
    mov  x0, x19
    mov  x1, x20
    ADRL x2, _g_hash
    bl   _pkt_hash
    mov  x0, x21
    ADRL x1, _g_hash
    add  x2, x19, x20
    bl   _verify_digest
    LEAVE 16
Lpc_stale:                            // x0: now. From the future and genuinely signed?
    sub  x9, x22, x0                  //   then the clocks differ: say so (now and then)
    mov  x10, #MAX_AHEAD
    cmp  x9, x10
    b.le Lpc_stale_ret
    str  x9, [sp, #96]
    mov  x0, x19
    mov  x1, x20
    ADRL x2, _g_hash
    bl   _pkt_hash
    mov  x0, x21
    ADRL x1, _g_hash
    add  x2, x19, x20
    bl   _verify_digest
    cmp  x0, #1
    b.ne Lpc_stale_ret
    ldr  x0, [sp, #96]
    bl   _skew_note
Lpc_stale_ret:
    mov  x0, #2
    LEAVE 16
Lpc_bad:
    mov  x0, #0
    LEAVE 16

// void _skew_note(long seconds_ahead) — at most every 30 minutes: another Mac's clock
//   is ahead of this one's, so its messages are being turned away
_skew_note:
    ENTER 0
    mov  x19, x0
    mov  x0, #0
    bl   _time
    ADRL x8, _g_skew_t
    ldr  x9, [x8]
    sub  x10, x0, x9
    cmp  x10, #1800
    b.lt Lsn_done
    str  x0, [x8]
    add  x1, x19, #59
    mov  x9, #60
    udiv x1, x1, x9
    ADRL x0, Lf_skew
    bl   _chat_fmt
Lsn_done:
    LEAVE 0

// long _hello_check(const uint8 *pkt, size_t len, uint64 id) -> 1 genuine (and its key
//   is now known), 0 forged or not the owner of that id, 2 stale
.globl _hello_check
_hello_check:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    sub  x22, x20, #(TRAILER + PUBLEN)
    add  x22, x19, x22                // its public key
    ldrb w9, [x22]
    cmp  w9, #4                       // uncompressed point
    b.ne Lhc_bad
    ADRL x8, _g_id_check
    ldr  x9, [x8]
    cbz  x9, Lhc_key
    mov  x0, x22
    bl   _id_of
    cmp  x0, x21
    b.ne Lhc_bad
Lhc_key:
    mov  x0, x22
    bl   _pub_ref
    cbz  x0, Lhc_bad
    mov  x23, x0
    mov  x0, x19
    mov  x1, x20
    mov  x2, x23
    bl   _pkt_check
    mov  x24, x0
    mov  x0, x23
    bl   _CFRelease
    cmp  x24, #1
    b.ne Lhc_ret
    mov  x0, x21
    mov  x1, x22
    bl   _key_put
Lhc_ret:
    mov  x0, x24
    LEAVE 0
Lhc_bad:
    mov  x0, #0
    LEAVE 0

// long _sender_check(const uint8 *pkt, size_t len, uint64 id) -> 1 genuine,
//   0 forged, 2 stale, 3 we don't know that sender's key yet
.globl _sender_check
_sender_check:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x0, x2
    bl   _key_find
    cbz  x0, Lsk2_unknown
    mov  x21, x0
    ldr  x2, [x0, #KE_REF]
    mov  x0, x19
    mov  x1, x20
    bl   _pkt_check
    cmp  x0, #1
    b.ne 1f
    mov  x22, x0                      // genuine: they're still around
    mov  x0, #0
    bl   _time
    str  w0, [x21, #KE_SEEN]
    mov  x0, x22
1:  LEAVE 0
Lsk2_unknown:
    mov  x0, #3
    LEAVE 0

// ---------------------------------------------------------------------------
// Pairwise secrets
// ---------------------------------------------------------------------------

// long _pair_key_with(SecKeyRef priv, uint64 their_id, uint8 *out64) -> 1 ok, 0 no key known
.globl _pair_key_with
_pair_key_with:
    ENTER 16
    mov  x19, x0
    mov  x21, x2
    mov  x0, x1
    bl   _key_find
    cbz  x0, Lpk_no
    ldr  x20, [x0, #KE_REF]
    cbz  x20, Lpk_no
    cbz  x19, Lpk_no
    CLS  Ls_NSMutableDictionary
    MSG0 Ls_dictionary
    mov  x22, x0
    CLS  Ls_NSNumber
    mov  x2, #64
    MSG1 Ls_numberWithInt
    mov  x2, x0
    LDGOT x8, _kSecKeyKeyExchangeParameterRequestedSize
    ldr  x3, [x8]
    mov  x0, x22
    MSG2 Ls_setObjectForKey
    ADRL x0, Ls_pair_info
    bl   _strlen
    mov  x1, x0
    ADRL x0, Ls_pair_info
    bl   _cfdata
    mov  x2, x0
    LDGOT x8, _kSecKeyKeyExchangeParameterSharedInfo
    ldr  x3, [x8]
    mov  x0, x22
    MSG2 Ls_setObjectForKey
    LDGOT x8, _kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256
    ldr  x1, [x8]
    mov  x0, x19
    mov  x2, x20
    mov  x3, x22
    mov  x4, #0
    bl   _SecKeyCopyKeyExchangeResult
    cbz  x0, Lpk_no
    mov  x23, x0
    MSG0 Ls_length
    cmp  x0, #64
    b.ne Lpk_rel
    mov  x0, x23
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x21
    mov  x2, #64
    bl   _memcpy
    mov  x0, x23
    bl   _CFRelease
    mov  x0, #1
    LEAVE 16
Lpk_rel:
    mov  x0, x23
    bl   _CFRelease
Lpk_no:
    mov  x0, #0
    LEAVE 16

// long _pair_key(uint64 their_id, uint8 *out64) — with our identity
.globl _pair_key
_pair_key:
    ENTER 0
    mov  x2, x1
    mov  x1, x0
    ADRL x8, _g_id_priv
    ldr  x0, [x8]
    bl   _pair_key_with
    LEAVE 0

// ---------------------------------------------------------------------------
// Packets waiting for their sender's HELLO
// ---------------------------------------------------------------------------

// uint64 _pkt_sender(const uint8 *pkt) — who made it
.globl _pkt_sender
_pkt_sender:
    ldrb w9, [x0, #3]
    cmp  w9, #T_HELLO
    b.eq Lps_12
    cmp  w9, #T_SEEN
    b.eq Lps_12
    ldr  x0, [x0, #20]
    ret
Lps_12:
    ldr  x0, [x0, #12]
    ret

// void _pending_put(const uint8 *pkt, size_t len)
.globl _pending_put
_pending_put:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    cmp  x20, #PKT_MAX
    b.hi Lpp_done
    ADRL x8, _g_pend_pos
    ldr  x9, [x8]
    add  x10, x9, #1
    str  x10, [x8]
    and  x9, x9, #(PEND_N - 1)
    ADRL x21, _g_pend
    add  x21, x21, x9, lsl #PE_SHIFT
    str  x20, [x21]
    add  x0, x21, #8
    mov  x1, x19
    mov  x2, x20
    bl   _memcpy
Lpp_done:
    LEAVE 0

// void _pending_replay(uint64 id) — its key just arrived: read what it sent
.globl _pending_replay
_pending_replay:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
Lpr_loop:
    cmp  x20, #PEND_N
    b.hs Lpr_done
    ADRL x21, _g_pend
    add  x21, x21, x20, lsl #PE_SHIFT
    ldr  x22, [x21]
    cbz  x22, Lpr_next
    add  x0, x21, #8
    bl   _pkt_sender
    cmp  x0, x19
    b.ne Lpr_next
    str  xzr, [x21]
    ADRL x8, _g_rx_replay
    mov  x9, #1
    str  x9, [x8]
    add  x0, x21, #8
    mov  x1, x22
    bl   _mesh_receive
    ADRL x8, _g_rx_replay
    str  xzr, [x8]
Lpr_next:
    add  x20, x20, #1
    b    Lpr_loop
Lpr_done:
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Lf_skew:        .asciz "\302\267 \342\217\261 Another Mac\342\200\231s clock is about %ld minutes ahead of this one, so its messages are being turned away. Both Macs should set the time automatically (System Settings \342\200\272 General \342\200\272 Date & Time)."
Ls_hexdig:      .asciz "0123456789abcdef"
Ls_b32dig:      .asciz "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
Ls_kc_keys:     .asciz "asmmesh.keys"
Ls_pair_info:   .asciz "asmmesh v3 pair"
Ls_NSData:      .asciz "NSData"
Ls_NSNumber:    .asciz "NSNumber"
Ls_NSMutableDictionary: .asciz "NSMutableDictionary"
Ls_dictionary:  .asciz "dictionary"
Ls_setObjectForKey: .asciz "setObject:forKey:"
Ls_numberWithInt: .asciz "numberWithInt:"
Ls_dataWithBytes: .asciz "dataWithBytes:length:"
Ls_length:      .asciz "length"
Ls_bytes:       .asciz "bytes"
Lf_id_msg:      .asciz "\302\267 \360\237\224\221 Your identity key is ready \342\200\224 others see you as %s. Messages you send are signed, so nobody can fake them."
Lf_id_locked:   .asciz "\302\267 \342\232\240\357\270\217 macOS didn\342\200\231t let asmmesh read its identity key from the Keychain (status %ld), so you can\342\200\231t send yet \342\200\224 your identity is kept, not replaced. Quit and reopen asmmesh, and click Always Allow when macOS asks."
Ls_id_fail:     .asciz "\302\267 \342\232\240\357\270\217 Couldn\342\200\231t create or unlock your identity key, so you can\342\200\231t send yet. Quit and reopen asmmesh, and allow the Keychain prompt."
