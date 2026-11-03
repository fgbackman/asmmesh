// bc_noise.s — bitchat's private chats: Noise_XX_25519_ChaChaPoly_SHA256 exactly as bitchat
// does it (bitchat/Noise/NoiseProtocol.swift, NoiseSession.swift, commit 04995f6), and its
// private-message payload. Pure functions on caller-owned memory (a session is NZ_SIZE
// bytes, bc_defs.inc), so they run under qemu too; bc_ble.s does the radio, the clock and
// the randomness.
//
//   handshake   empty prologue, empty payloads:  -> e (32)   <- e, ee, s, es (96)
//               -> s, se (64). Their static key must not be a low-order point.
//   transport   ChaCha20-Poly1305, no associated data. Each message starts with its nonce,
//               4 bytes big-endian (bitchat's "extracted nonce"); the 12-byte nonce is 4 zero
//               bytes and the counter little-endian. Nonces up to 0xFFFFFFFE are sent; one
//               already seen, or 1024 or more behind the highest, is refused.
//   payload     type byte, then for 0x01 (private message) TLVs: 0x00 message id, 0x01 the
//               text, a byte of length each. 0x02 read receipt and 0x03 delivered carry the
//               message id.
//
// Checked against tools/qemu/bcnoise.py, itself checked byte for byte against the
// noiseprotocol package (self-tests 192-195).

.include "macros.inc"
.include "bc_defs.inc"

.set NV_PM_N, 56
.set NV_C0_N, 76
.set NV_C1_N, 57
.set NV_R0_N, 22          // the vectors' sizes (at the end of the file)

.text
.p2align 2

// void Lnz_cpy(dst, src, n) (leaf: x9, x10)
Lnz_cpy:
    mov  x9, #0
1:  cmp  x9, x2
    b.hs 2f
    ldrb w10, [x1, x9]
    strb w10, [x0, x9]
    add  x9, x9, #1
    b    1b
2:  ret

// void Lnz_mixhash(s, p, n) — h = SHA-256(h || p), n at most 96
Lnz_mixhash:
    ENTER 128                             // [96] h || p
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x0, sp, #96
    add  x1, x19, #NZ_H
    mov  x2, #32
    bl   Lnz_cpy
    add  x0, sp, #128
    mov  x1, x20
    mov  x2, x21
    bl   Lnz_cpy
    add  x0, sp, #96
    add  x1, x21, #32
    add  x2, x19, #NZ_H
    bl   _bc_sha256
    LEAVE 128

// void Lnz_mixkey(s, ikm[32]) — ck, k = HKDF(ck, ikm); a new key starts at nonce 0
Lnz_mixkey:
    ENTER 64                              // [96] the two outputs
    mov  x19, x0
    mov  x20, x1
    add  x0, x19, #NZ_CK                  // HKDF with ck as the salt and no info is
    mov  x1, #32                          //   Noise's HKDF (RFC 5869, L = 64)
    mov  x2, x20
    mov  x3, #32
    mov  x4, x20
    mov  x5, #0
    add  x6, sp, #96
    mov  x7, #64
    bl   _bc_hkdf256
    add  x0, x19, #NZ_CK
    add  x1, sp, #96
    mov  x2, #32
    bl   Lnz_cpy
    add  x0, x19, #NZ_K
    add  x1, sp, #128
    mov  x2, #32
    bl   Lnz_cpy
    mov  x9, #1
    str  x9, [x19, #NZ_HAVEK]
    str  xzr, [x19, #NZ_N]
    add  x0, sp, #96
    mov  x1, #64
    bl   _bc_wipe
    LEAVE 64

// long Lnz_enc(s, pt, n, out) -> bytes written: encryptAndHash (n + 16 once keyed)
Lnz_enc:
    ENTER 16                              // [96] the 12-byte nonce
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldr  x9, [x19, #NZ_HAVEK]
    cbz  x9, 2f
    stp  xzr, xzr, [sp, #96]
    ldr  x9, [x19, #NZ_N]
    str  x9, [sp, #100]
    add  x0, x19, #NZ_K
    add  x1, sp, #96
    add  x2, x19, #NZ_H
    mov  x3, #32
    mov  x4, x20
    mov  x5, x21
    mov  x6, x22
    bl   _bc_aead_seal
    ldr  x9, [x19, #NZ_N]
    add  x9, x9, #1
    str  x9, [x19, #NZ_N]
    add  x21, x21, #16
    mov  x0, x19
    mov  x1, x22
    mov  x2, x21
    bl   Lnz_mixhash
    mov  x0, x21
    LEAVE 16
2:  mov  x0, x22                          // no key yet: as it is
    mov  x1, x20
    mov  x2, x21
    bl   Lnz_cpy
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lnz_mixhash
    mov  x0, x21
    LEAVE 16

// long Lnz_dec(s, ct, n, out) -> plaintext length, or -1: decryptAndHash
Lnz_dec:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldr  x9, [x19, #NZ_HAVEK]
    cbz  x9, 2f
    cmp  x21, #16
    b.lo 8f
    stp  xzr, xzr, [sp, #96]
    ldr  x9, [x19, #NZ_N]
    str  x9, [sp, #100]
    add  x0, x19, #NZ_K
    add  x1, sp, #96
    add  x2, x19, #NZ_H
    mov  x3, #32
    mov  x4, x20
    mov  x5, x21
    mov  x6, x22
    bl   _bc_aead_open
    tbnz x0, #63, 8f
    mov  x23, x0
    ldr  x9, [x19, #NZ_N]
    add  x9, x9, #1
    str  x9, [x19, #NZ_N]
    mov  x0, x19                          // the hash takes the ciphertext
    mov  x1, x20
    mov  x2, x21
    bl   Lnz_mixhash
    mov  x0, x23
    LEAVE 16
2:  mov  x0, x22
    mov  x1, x20
    mov  x2, x21
    bl   Lnz_cpy
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   Lnz_mixhash
    mov  x0, x21
    LEAVE 16
8:  mov  x0, #-1
    LEAVE 16

// long Lnz_dh(s, secret[32], pub[32]) -> 0, or -1 (a low-order result): mixKey(DH(...))
Lnz_dh:
    ENTER 32                              // [96] the shared secret
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    add  x0, sp, #96
    mov  x1, x20
    mov  x2, x21
    bl   _bc_x25519
    mov  x22, x0
    tbnz x22, #63, 1f
    mov  x0, x19
    add  x1, sp, #96
    bl   Lnz_mixkey
1:  add  x0, sp, #96
    mov  x1, #32
    bl   _bc_wipe
    mov  x0, x22
    LEAVE 32

// long _nz_key_ok(const uint8 *k) -> 1 unless it is one of the points bitchat refuses
//   (validatePublicKey: zero, low-order points, all ones and two more)
.globl _nz_key_ok
_nz_key_ok:
    ENTER 0
    mov  x19, x0
    ADRL x20, Lnz_bad
    mov  x21, #0
1:  cmp  x21, #8
    b.hs 3f
    mov  x0, x19
    add  x1, x20, x21, lsl #5
    mov  x2, #32
    bl   _bc_memeq
    add  x21, x21, #1
    cbz  x0, 1b
    mov  x0, #0
    LEAVE 0
3:  mov  x0, #1
    LEAVE 0

// void _nz_start(s, peer id, long role, long now) — a new handshake (0 initiator,
//   1 responder); a transport the session has stays as it is until this one completes
.globl _nz_start
_nz_start:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    add  x0, x19, #NZ_CK                  // the last handshake's secrets: gone
    mov  x1, #(NZ_RS - NZ_CK)
    bl   _bc_wipe
    str  x20, [x19, #NZ_PEER]
    mov  x9, #1
    str  x9, [x19, #NZ_ACTIVE]
    str  x21, [x19, #NZ_ROLE]
    str  xzr, [x19, #NZ_STEP]
    str  xzr, [x19, #NZ_HAVEK]
    str  xzr, [x19, #NZ_N]
    str  x22, [x19, #NZ_HSAT]
    add  x0, x19, #NZ_CK                  // the name is 32 bytes: h and ck start as it
    ADRL x1, Lnz_name
    mov  x2, #32
    bl   Lnz_cpy
    add  x0, x19, #NZ_H
    ADRL x1, Lnz_name
    mov  x2, #32
    bl   Lnz_cpy
    mov  x0, x19                          // the prologue: empty
    mov  x1, x19
    mov  x2, #0
    bl   Lnz_mixhash
    LEAVE 0

// void Lnz_finish(s) — Split(): the transport keys, the handshake's secrets wiped
Lnz_finish:
    ENTER 64                              // [96] k1, k2
    mov  x19, x0
    add  x0, x19, #NZ_CK
    mov  x1, #32
    mov  x2, x19                          // no input key material
    mov  x3, #0
    mov  x4, x19
    mov  x5, #0
    add  x6, sp, #96
    mov  x7, #64
    bl   _bc_hkdf256
    ldr  x9, [x19, #NZ_ROLE]
    add  x20, sp, #96                     // initiator: sends with k1, receives with k2
    add  x21, sp, #128
    cbz  x9, 1f
    add  x20, sp, #128
    add  x21, sp, #96
1:  add  x0, x19, #NZ_TSEND
    mov  x1, x20
    mov  x2, #32
    bl   Lnz_cpy
    add  x0, x19, #NZ_TRECV
    mov  x1, x21
    mov  x2, #32
    bl   Lnz_cpy
    add  x0, x19, #NZ_RS
    add  x1, x19, #NZ_HRS
    mov  x2, #32
    bl   Lnz_cpy
    str  xzr, [x19, #NZ_SENDN]
    str  xzr, [x19, #NZ_HI]
    add  x0, x19, #NZ_WIN
    mov  x1, #128
    bl   _bc_wipe
    mov  x9, #1
    str  x9, [x19, #NZ_EST]
    str  xzr, [x19, #NZ_ACTIVE]
    ldr  x9, [x19, #NZ_HSAT]
    str  x9, [x19, #NZ_ESTAT]
    add  x0, x19, #NZ_CK
    mov  x1, #(NZ_RS - NZ_CK)
    bl   _bc_wipe
    add  x0, sp, #96
    mov  x1, #64
    bl   _bc_wipe
    LEAVE 64

// long _nz_write(s, our secret[32], our public[32], ephemeral secret[32] or 0, out) ->
//   the message's length (32, 96, 64), or -1 if it isn't our turn. The third message
//   completes the handshake (NZ_EST).
.globl _nz_write
_nz_write:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    ldr  x9, [x19, #NZ_ACTIVE]
    cbz  x9, Lnw_no
    ldr  x24, [x19, #NZ_STEP]
    ldr  x10, [x19, #NZ_ROLE]
    cmp  x24, #1                          // steps 0 and 2 are the initiator's, 1 the responder's
    cset x11, eq
    cmp  x10, x11
    b.ne Lnw_no
    cmp  x24, #2
    b.eq Lnw_3
    b.hi Lnw_no
    cbz  x22, Lnw_no                      // -> e  /  <- e: a new ephemeral key
    add  x0, x19, #NZ_E
    mov  x1, x22
    mov  x2, #32
    bl   Lnz_cpy
    add  x0, x19, #NZ_EPUB
    add  x1, x19, #NZ_E
    bl   _bc_x25519_base
    mov  x0, x23
    add  x1, x19, #NZ_EPUB
    mov  x2, #32
    bl   Lnz_cpy
    mov  x0, x19
    add  x1, x19, #NZ_EPUB
    mov  x2, #32
    bl   Lnz_mixhash
    cbnz x24, Lnw_2
    mov  x0, x19                          // message 1: the empty payload, unkeyed
    mov  x1, x23
    mov  x2, #0
    add  x3, x23, #32
    bl   Lnz_enc
    mov  x0, #NZ_MSG1
    b    Lnw_done
Lnw_2:                                    // <- e, ee, s, es
    mov  x0, x19
    add  x1, x19, #NZ_E
    add  x2, x19, #NZ_RE
    bl   Lnz_dh
    tbnz x0, #63, Lnw_no
    mov  x0, x19
    mov  x1, x21
    mov  x2, #32
    add  x3, x23, #32
    bl   Lnz_enc
    mov  x0, x19                          // es, on the responder's side: s with re
    mov  x1, x20
    add  x2, x19, #NZ_RE
    bl   Lnz_dh
    tbnz x0, #63, Lnw_no
    mov  x0, x19
    mov  x1, x23
    mov  x2, #0
    add  x3, x23, #80
    bl   Lnz_enc
    mov  x0, #NZ_MSG2
    b    Lnw_done
Lnw_3:                                    // -> s, se
    mov  x0, x19
    mov  x1, x21
    mov  x2, #32
    mov  x3, x23
    bl   Lnz_enc
    mov  x0, x19                          // se, on the initiator's side: s with re
    mov  x1, x20
    add  x2, x19, #NZ_RE
    bl   Lnz_dh
    tbnz x0, #63, Lnw_no
    mov  x0, x19
    mov  x1, x23
    mov  x2, #0
    add  x3, x23, #48
    bl   Lnz_enc
    mov  x0, #NZ_MSG3
Lnw_done:
    mov  x22, x0
    add  x24, x24, #1
    str  x24, [x19, #NZ_STEP]
    cmp  x24, #3
    b.ne 1f
    mov  x0, x19
    bl   Lnz_finish
1:  mov  x0, x22
    LEAVE 16
Lnw_no:
    mov  x0, #-1
    LEAVE 16

// long _nz_read(s, our secret[32], msg, len) -> 0 read (our turn next), 1 read and the
//   handshake is complete (NZ_EST, their key in NZ_RS), -1 refused: not the message
//   expected, a bad key, or a tag that doesn't check out (the caller drops the handshake)
.globl _nz_read
_nz_read:
    ENTER 16                              // [96] an empty payload's (nothing) goes here
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldr  x9, [x19, #NZ_ACTIVE]
    cbz  x9, Lnr_no
    ldr  x24, [x19, #NZ_STEP]
    ldr  x10, [x19, #NZ_ROLE]
    cmp  x24, #1                          // steps 0 and 2 are read by the responder
    cset x11, ne
    cmp  x10, x11
    b.ne Lnr_no
    cmp  x24, #2
    b.hi Lnr_no
    b.eq Lnr_3
    cmp  x24, #1
    b.eq Lnr_2
    cmp  x22, #NZ_MSG1                    // -> e
    b.ne Lnr_no
    mov  x0, x21
    bl   _nz_key_ok
    cbz  x0, Lnr_no
    add  x0, x19, #NZ_RE
    mov  x1, x21
    mov  x2, #32
    bl   Lnz_cpy
    mov  x0, x19
    mov  x1, x21
    mov  x2, #32
    bl   Lnz_mixhash
    mov  x0, x19
    add  x1, x21, #32
    mov  x2, #0
    add  x3, sp, #96
    bl   Lnz_dec
    b    Lnr_ok
Lnr_2:                                    // <- e, ee, s, es
    cmp  x22, #NZ_MSG2
    b.ne Lnr_no
    mov  x0, x21
    bl   _nz_key_ok
    cbz  x0, Lnr_no
    add  x0, x19, #NZ_RE
    mov  x1, x21
    mov  x2, #32
    bl   Lnz_cpy
    mov  x0, x19
    mov  x1, x21
    mov  x2, #32
    bl   Lnz_mixhash
    mov  x0, x19
    add  x1, x19, #NZ_E
    add  x2, x19, #NZ_RE
    bl   Lnz_dh
    tbnz x0, #63, Lnr_no
    mov  x0, x19
    add  x1, x21, #32
    mov  x2, #48
    add  x3, x19, #NZ_HRS
    bl   Lnz_dec
    cmp  x0, #32
    b.ne Lnr_no
    add  x0, x19, #NZ_HRS
    bl   _nz_key_ok
    cbz  x0, Lnr_no
    mov  x0, x19                          // es, on the initiator's side: e with rs
    add  x1, x19, #NZ_E
    add  x2, x19, #NZ_HRS
    bl   Lnz_dh
    tbnz x0, #63, Lnr_no
    mov  x0, x19
    add  x1, x21, #80
    mov  x2, #16
    add  x3, sp, #96
    bl   Lnz_dec
    cbnz x0, Lnr_no
    b    Lnr_ok
Lnr_3:                                    // -> s, se
    cmp  x22, #NZ_MSG3
    b.ne Lnr_no
    mov  x0, x19
    mov  x1, x21
    mov  x2, #48
    add  x3, x19, #NZ_HRS
    bl   Lnz_dec
    cmp  x0, #32
    b.ne Lnr_no
    add  x0, x19, #NZ_HRS
    bl   _nz_key_ok
    cbz  x0, Lnr_no
    mov  x0, x19                          // se, on the responder's side: e with rs
    add  x1, x19, #NZ_E
    add  x2, x19, #NZ_HRS
    bl   Lnz_dh
    tbnz x0, #63, Lnr_no
    mov  x0, x19
    add  x1, x21, #48
    mov  x2, #16
    add  x3, sp, #96
    bl   Lnz_dec
    cbnz x0, Lnr_no
Lnr_ok:
    add  x24, x24, #1
    str  x24, [x19, #NZ_STEP]
    cmp  x24, #3
    b.ne 1f
    mov  x0, x19
    bl   Lnz_finish
    mov  x0, #1
    LEAVE 16
1:  mov  x0, #0
    LEAVE 16
Lnr_no:
    mov  x0, #-1
    LEAVE 16

// void _nz_drop(s) — the handshake abandoned (its secrets wiped); a transport stays
.globl _nz_drop
_nz_drop:
    ENTER 0
    mov  x19, x0
    add  x0, x19, #NZ_CK
    mov  x1, #(NZ_RS - NZ_CK)
    bl   _bc_wipe
    str  xzr, [x19, #NZ_ACTIVE]
    str  xzr, [x19, #NZ_STEP]
    str  xzr, [x19, #NZ_HAVEK]
    LEAVE 0

// long _nz_seal(s, pt, n, out) -> n + 20 (nonce, ciphertext, tag), or -1 (no transport,
//   or out of nonces)
.globl _nz_seal
_nz_seal:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldr  x9, [x19, #NZ_EST]
    cbz  x9, 8f
    ldr  x23, [x19, #NZ_SENDN]
    mov  x10, #0xfffffffe
    cmp  x23, x10
    b.hi 8f
    rev  w9, w23                          // the nonce, 4 bytes big-endian, in front
    str  w9, [x22]
    stp  xzr, xzr, [sp, #96]
    str  x23, [sp, #100]
    add  x0, x19, #NZ_TSEND
    add  x1, sp, #96
    mov  x2, x22                          // no associated data
    mov  x3, #0
    mov  x4, x20
    mov  x5, x21
    add  x6, x22, #4
    bl   _bc_aead_seal
    add  x23, x23, #1
    str  x23, [x19, #NZ_SENDN]
    add  x0, x21, #NZ_OVER
    LEAVE 16
8:  mov  x0, #-1
    LEAVE 16

// long _nz_open(s, in, n, out) -> the plaintext's length, or -1: no transport, too short,
//   a nonce already seen or 1024 or more behind the highest, or a tag that's wrong. Only a
//   message that checks out moves the replay window.
.globl _nz_open
_nz_open:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ldr  x9, [x19, #NZ_EST]
    cbz  x9, 8f
    cmp  x21, #NZ_OVER
    b.lo 8f
    ldr  w23, [x20]
    rev  w23, w23                         // the nonce (32 bits, so x23 is it zero-extended)
    ldr  x24, [x19, #NZ_HI]
    cmp  x24, #NZ_WINDOW                  // too old?
    b.lo 1f
    sub  x9, x24, #NZ_WINDOW
    cmp  x23, x9
    b.ls 8f
1:  cmp  x23, x24                         // not newer: must not have been seen
    b.hi 2f
    and  x9, x23, #(NZ_WINDOW - 1)
    lsr  x10, x9, #3
    add  x11, x19, #NZ_WIN
    ldrb w12, [x11, x10]
    and  x9, x9, #7
    lsr  w12, w12, w9
    tbnz w12, #0, 8f
2:  stp  xzr, xzr, [sp, #96]
    str  x23, [sp, #100]
    add  x0, x19, #NZ_TRECV
    add  x1, sp, #96
    mov  x2, x20
    mov  x3, #0
    add  x4, x20, #4
    sub  x5, x21, #4
    mov  x6, x22
    bl   _bc_aead_open
    tbnz x0, #63, 8f
    mov  x21, x0                          // its length
    cmp  x23, x24                         // newer: the window moves up to it
    b.ls 5f
    sub  x9, x23, x24
    cmp  x9, #NZ_WINDOW
    b.lo 3f
    add  x0, x19, #NZ_WIN                 //   a jump of 1024 or more: all forgotten
    mov  x1, #128
    bl   _bc_wipe
    b    4f
3:  add  x10, x24, #1                     //   the nonces passed over: not seen
    add  x11, x19, #NZ_WIN
31: cmp  x10, x23
    b.hi 4f
    and  x12, x10, #(NZ_WINDOW - 1)
    lsr  x13, x12, #3
    ldrb w14, [x11, x13]
    and  x12, x12, #7
    mov  w15, #1
    lsl  w15, w15, w12
    bic  w14, w14, w15
    strb w14, [x11, x13]
    add  x10, x10, #1
    b    31b
4:  str  x23, [x19, #NZ_HI]
5:  and  x12, x23, #(NZ_WINDOW - 1)       // this one: seen
    lsr  x13, x12, #3
    add  x11, x19, #NZ_WIN
    ldrb w14, [x11, x13]
    and  x12, x12, #7
    mov  w15, #1
    lsl  w15, w15, w12
    orr  w14, w14, w15
    strb w14, [x11, x13]
    mov  x0, x21
    LEAVE 16
8:  mov  x0, #-1
    LEAVE 16

// long _nz_pm_make(id, idlen, text, tlen, out) -> the payload's length (type 0x01 and its
//   two TLVs), or -1 if either is over 255 bytes
.globl _nz_pm_make
_nz_pm_make:
    ENTER 0
    cmp  x1, #255
    b.hi 8f
    cmp  x3, #255
    b.hi 8f
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    mov  w9, #1
    strb w9, [x23]
    strb wzr, [x23, #1]                   // 0x00: the message id
    strb w20, [x23, #2]
    add  x0, x23, #3
    mov  x1, x19
    mov  x2, x20
    bl   Lnz_cpy
    add  x24, x20, #3
    mov  w9, #1                           // 0x01: the text
    strb w9, [x23, x24]
    add  x24, x24, #1
    strb w22, [x23, x24]
    add  x24, x24, #1
    add  x0, x23, x24
    mov  x1, x21
    mov  x2, x22
    bl   Lnz_cpy
    add  x0, x24, x22
    LEAVE 0
8:  mov  x0, #-1
    LEAVE 0

// long _nz_pm_read(p, n, long out[4]) -> 0 and out = id, id length, text, text length;
//   -1 if it isn't a private message, a TLV runs past the end or isn't 0x00 / 0x01, or
//   either is missing (as bitchat's PrivateMessagePacket.decode) (leaf)
.globl _nz_pm_read
_nz_pm_read:
    cbz  x1, 8f
    ldrb w9, [x0]
    cmp  w9, #1
    b.ne 8f
    stp  xzr, xzr, [x2]
    stp  xzr, xzr, [x2, #16]
    mov  x10, #1                          // where
    mov  x13, #0                          // bit 0 id seen, bit 1 text seen
1:  add  x11, x10, #2
    cmp  x11, x1
    b.hi 5f
    ldrb w11, [x0, x10]                   // type
    add  x12, x10, #1
    ldrb w12, [x0, x12]                   // length
    add  x10, x10, #2
    add  x14, x10, x12
    cmp  x14, x1
    b.hi 8f
    add  x15, x0, x10
    cmp  w11, #0
    b.ne 2f
    stp  x15, x12, [x2]
    orr  x13, x13, #1
    b    3f
2:  cmp  w11, #1
    b.ne 8f
    stp  x15, x12, [x2, #16]
    orr  x13, x13, #2
3:  mov  x10, x14
    b    1b
5:  cmp  x13, #3
    b.ne 8f
    mov  x0, #0
    ret
8:  mov  x0, #-1
    ret

// ---------------------------------------------------------------------------
// self-tests 192-195, called from test.s

.macro NZ_EQ a, b, n                      // x20 &= (n bytes at a == at b); a, b registers
    mov  x0, \a
    mov  x1, \b
    mov  x2, #\n
    bl   _bc_memeq
    and  x20, x20, x0
.endm

.macro NZ_IS reg, val                     // x20 &= (reg == val)
    cmp  \reg, #\val
    cset x9, eq
    and  x20, x20, x9
.endm

.macro NZ_ISM reg, val                    // x20 &= (reg == -val)
    cmn  \reg, #\val
    cset x9, eq
    and  x20, x20, x9
.endm

.globl _bc_noise_selftest
_bc_noise_selftest:
    ENTER 16                              // [96] the count, [104] x25
    str  x25, [sp, #104]
    str  xzr, [sp, #96]
    ADRL x23, Lnz_tA                      // two sessions, A the initiator, B the responder
    ADRL x24, Lnz_tB
    ADRL x25, Lnz_tbuf

    // 192. the handshake: both sides make bitchat's three messages byte for byte
    mov  x20, #1
    mov  x0, x23
    mov  x1, #(2 * NZ_SIZE)
    bl   _bc_wipe
    mov  x0, x23
    mov  x1, #0x1111
    mov  x2, #0
    mov  x3, #5
    bl   _nz_start
    mov  x0, x24
    mov  x1, #0x2222
    mov  x2, #1
    mov  x3, #5
    bl   _nz_start
    mov  x0, x23
    ADRL x1, Lnv_si
    ADRL x2, Lnv_spi
    ADRL x3, Lnv_ei
    mov  x4, x25
    bl   _nz_write
    NZ_IS x0, 32
    ADRL x21, Lnv_m1
    NZ_EQ x25, x21, 32
    mov  x0, x24                          // the responder can't speak first
    ADRL x1, Lnv_sr
    ADRL x2, Lnv_spr
    ADRL x3, Lnv_er
    add  x4, x25, #256
    bl   _nz_write
    NZ_ISM x0, 1
    mov  x0, x24
    ADRL x1, Lnv_sr
    mov  x2, x25
    mov  x3, #32
    bl   _nz_read
    NZ_IS x0, 0
    mov  x0, x24
    ADRL x1, Lnv_sr
    ADRL x2, Lnv_spr
    ADRL x3, Lnv_er
    mov  x4, x25
    bl   _nz_write
    NZ_IS x0, 96
    ADRL x21, Lnv_m2
    NZ_EQ x25, x21, 96
    mov  x0, x23
    ADRL x1, Lnv_si
    mov  x2, x25
    mov  x3, #96
    bl   _nz_read
    NZ_IS x0, 0
    mov  x0, x23
    ADRL x1, Lnv_si
    ADRL x2, Lnv_spi
    mov  x3, #0
    mov  x4, x25
    bl   _nz_write
    NZ_IS x0, 64
    ADRL x21, Lnv_m3
    NZ_EQ x25, x21, 64
    ldr  x9, [x23, #NZ_EST]
    NZ_IS x9, 1
    mov  x0, x24
    ADRL x1, Lnv_sr
    mov  x2, x25
    mov  x3, #64
    bl   _nz_read
    NZ_IS x0, 1
    ldr  x9, [x24, #NZ_EST]
    NZ_IS x9, 1
    ldr  x9, [x24, #NZ_ACTIVE]
    NZ_IS x9, 0
    add  x0, x23, #NZ_RS                  // each knows the other's static key
    ADRL x21, Lnv_spr
    NZ_EQ x0, x21, 32
    add  x0, x24, #NZ_RS
    ADRL x21, Lnv_spi
    NZ_EQ x0, x21, 32
    add  x0, x23, #NZ_E                   // and the handshake's secrets are gone
    ADRL x21, Lnz_zero
    NZ_EQ x0, x21, 32
    mov  w1, w20
    ADRL x0, Ln_nz192
    bl   _t_report
    ldr  x9, [sp, #96]
    add  x9, x9, x0
    str  x9, [sp, #96]

    // 193. transport: bitchat's bytes both ways; replays, old nonces and changed bytes refused
    mov  x20, #1
    mov  x0, x23
    ADRL x1, Lnv_pm
    mov  x2, #NV_PM_N
    mov  x3, x25
    bl   _nz_seal
    NZ_IS x0, NV_C0_N
    ADRL x21, Lnv_c0
    NZ_EQ x25, x21, NV_C0_N
    mov  x0, x24
    mov  x1, x25
    mov  x2, #NV_C0_N
    add  x3, x25, #256
    bl   _nz_open
    NZ_IS x0, NV_PM_N
    add  x0, x25, #256
    ADRL x21, Lnv_pm
    NZ_EQ x0, x21, NV_PM_N
    mov  x0, x24                          // the same again: a replay
    mov  x1, x25
    mov  x2, #NV_C0_N
    add  x3, x25, #256
    bl   _nz_open
    NZ_ISM x0, 1
    mov  x0, x23
    ADRL x1, Lnv_c1p
    mov  x2, #(NV_C1_N - 20)
    mov  x3, x25
    bl   _nz_seal
    ADRL x21, Lnv_c1
    NZ_EQ x25, x21, NV_C1_N
    ldrb w9, [x25, #10]                   // one bit changed: refused, and nothing moved
    eor  w9, w9, #1
    strb w9, [x25, #10]
    mov  x0, x24
    mov  x1, x25
    mov  x2, #NV_C1_N
    add  x3, x25, #256
    bl   _nz_open
    NZ_ISM x0, 1
    mov  x0, x24
    ADRL x1, Lnv_c1
    mov  x2, #NV_C1_N
    add  x3, x25, #256
    bl   _nz_open
    NZ_IS x0, (NV_C1_N - 20)
    mov  x0, x24                          // the other way
    ADRL x1, Lnv_r0p
    mov  x2, #2
    mov  x3, x25
    bl   _nz_seal
    ADRL x21, Lnv_r0
    NZ_EQ x25, x21, NV_R0_N
    mov  x0, x23
    mov  x1, x25
    mov  x2, #NV_R0_N
    add  x3, x25, #256
    bl   _nz_open
    NZ_IS x0, 2
    // the window: 10, then 7 (late, fine), 7 again (no), 2000, then 900 (too old) and 977
    mov  x21, #10
    bl   Lnz_t_send_at
    NZ_IS x0, 4
    mov  x21, #7
    bl   Lnz_t_send_at
    NZ_IS x0, 4
    mov  x21, #7
    bl   Lnz_t_send_at
    NZ_ISM x0, 1
    mov  x21, #2000
    bl   Lnz_t_send_at
    NZ_IS x0, 4
    mov  x21, #900
    bl   Lnz_t_send_at
    NZ_ISM x0, 1
    mov  x21, #977
    bl   Lnz_t_send_at
    NZ_IS x0, 4
    mov  x21, #976
    bl   Lnz_t_send_at
    NZ_ISM x0, 1
    mov  x0, x24                          // too short to be one
    mov  x1, x25
    mov  x2, #19
    add  x3, x25, #256
    bl   _nz_open
    NZ_ISM x0, 1
    mov  w1, w20
    ADRL x0, Ln_nz193
    bl   _t_report
    ldr  x9, [sp, #96]
    add  x9, x9, x0
    str  x9, [sp, #96]

    // 194. bad handshakes: a low-order key, a wrong length, a changed byte, out of turn;
    //      a transport keeps working while a new handshake is under way
    mov  x20, #1
    mov  x0, x24                          // B, already talking to A, starts over as responder
    mov  x1, #0x2222
    mov  x2, #1
    mov  x3, #9
    bl   _nz_start
    mov  x0, x24
    ADRL x1, Lnv_sr
    ADRL x2, Lnz_zero                     // all zero: refused
    mov  x3, #32
    bl   _nz_read
    NZ_ISM x0, 1
    mov  x0, x24
    ADRL x1, Lnv_sr
    ADRL x2, Lnz_bad                      // a low-order point: refused
    add  x2, x2, #128
    mov  x3, #32
    bl   _nz_read
    NZ_ISM x0, 1
    mov  x0, x24
    ADRL x1, Lnv_sr
    ADRL x2, Lnv_m1
    mov  x3, #33                          // one byte too many
    bl   _nz_read
    NZ_ISM x0, 1
    mov  x0, x24                          // the old transport still works meanwhile
    ADRL x1, Lnv_r0p
    mov  x2, #2
    mov  x3, x25
    bl   _nz_seal
    NZ_IS x0, NV_R0_N
    mov  x0, x23
    mov  x1, x25
    mov  x2, #NV_R0_N
    add  x3, x25, #256
    bl   _nz_open
    NZ_IS x0, 2
    mov  x0, x23                          // A starts over too, and B's reply is changed
    mov  x1, #0x1111
    mov  x2, #0
    mov  x3, #9
    bl   _nz_start
    mov  x0, x23
    ADRL x1, Lnv_si
    ADRL x2, Lnv_spi
    ADRL x3, Lnv_ei
    mov  x4, x25
    bl   _nz_write
    NZ_IS x0, 32
    add  x0, x25, #128
    ADRL x1, Lnv_m2
    mov  x2, #96
    bl   Lnz_cpy
    ldrb w9, [x25, #(128 + 50)]           // inside their encrypted static key
    eor  w9, w9, #0x80
    strb w9, [x25, #(128 + 50)]
    mov  x0, x23
    ADRL x1, Lnv_si
    add  x2, x25, #128
    mov  x3, #96
    bl   _nz_read
    NZ_ISM x0, 1
    mov  x0, x23                          // dropped: nothing more is written or read
    bl   _nz_drop
    mov  x0, x23
    ADRL x1, Lnv_si
    ADRL x2, Lnv_spi
    mov  x3, #0
    mov  x4, x25
    bl   _nz_write
    NZ_ISM x0, 1
    ldr  x9, [x23, #NZ_EST]               // and A's transport is still there
    NZ_IS x9, 1
    mov  x22, #0                          // the keys bitchat refuses, and one it takes
    ADRL x21, Lnz_bad
1:  cmp  x22, #8
    b.hs 2f
    add  x0, x21, x22, lsl #5
    bl   _nz_key_ok
    NZ_IS x0, 0
    add  x22, x22, #1
    b    1b
2:  ADRL x0, Lnv_spi
    bl   _nz_key_ok
    NZ_IS x0, 1
    mov  w1, w20
    ADRL x0, Ln_nz194
    bl   _t_report
    ldr  x9, [sp, #96]
    add  x9, x9, x0
    str  x9, [sp, #96]

    // 195. the private-message payload, both ways; broken ones refused
    mov  x20, #1
    ADRL x0, Lnv_id
    mov  x1, #36
    ADRL x2, Lnv_text
    mov  x3, #15
    mov  x4, x25
    bl   _nz_pm_make
    NZ_IS x0, NV_PM_N
    ADRL x21, Lnv_pm
    NZ_EQ x25, x21, NV_PM_N
    ADRL x0, Lnv_pm
    mov  x1, #NV_PM_N
    add  x2, x25, #256
    bl   _nz_pm_read
    NZ_IS x0, 0
    ldr  x9, [x25, #(256 + 8)]
    NZ_IS x9, 36
    ldr  x9, [x25, #(256 + 24)]
    NZ_IS x9, 15
    ldr  x0, [x25, #(256 + 16)]
    ADRL x21, Lnv_text
    NZ_EQ x0, x21, 15
    ADRL x0, Lnv_pm                       // cut short
    mov  x1, #(NV_PM_N - 1)
    add  x2, x25, #256
    bl   _nz_pm_read
    NZ_ISM x0, 1
    mov  x0, x25                          // an unknown TLV type
    ADRL x1, Lnv_pm
    mov  x2, #NV_PM_N
    bl   Lnz_cpy
    mov  w9, #7
    strb w9, [x25, #1]
    mov  x0, x25
    mov  x1, #NV_PM_N
    add  x2, x25, #256
    bl   _nz_pm_read
    NZ_ISM x0, 1
    mov  w9, #2                           // not a private message
    strb w9, [x25]
    mov  x0, x25
    mov  x1, #NV_PM_N
    add  x2, x25, #256
    bl   _nz_pm_read
    NZ_ISM x0, 1
    mov  x0, x25                          // no text
    ADRL x1, Lnv_pm
    mov  x2, #39
    bl   Lnz_cpy
    mov  x0, x25
    mov  x1, #39
    add  x2, x25, #256
    bl   _nz_pm_read
    NZ_ISM x0, 1
    mov  w1, w20
    ADRL x0, Ln_nz195
    bl   _t_report
    ldr  x9, [sp, #96]
    add  x0, x9, x0
    ldr  x25, [sp, #104]
    LEAVE 16

// long Lnz_t_send_at(x21 nonce) -> what B's open of A's 4-byte message at that nonce says
//   (sessions in x23, x24, buffer in x25)
Lnz_t_send_at:
    ENTER 0
    str  x21, [x23, #NZ_SENDN]
    mov  x0, x23
    ADRL x1, Lnv_r0p
    mov  x2, #4
    mov  x3, x25
    bl   _nz_seal
    mov  x0, x24
    mov  x1, x25
    mov  x2, #24
    add  x3, x25, #256
    bl   _nz_open
    LEAVE 0

// ---------------------------------------------------------------------------
.data
.p2align 4
Lnz_tA:     .space NZ_SIZE                // the self-tests' sessions (A right before B:
Lnz_tB:     .space NZ_SIZE                //   192 wipes both at once) and a buffer
Lnz_tbuf:   .space 512

.section __TEXT,__const
.p2align 4
Lnz_name:   .ascii "Noise_XX_25519_ChaChaPoly_SHA256"
// bitchat's validatePublicKey refuses these outright
Lnz_bad:
    .fill 32, 1, 0
    .byte 0x01
    .fill 31, 1, 0
    .fill 31, 1, 0
    .byte 0x01
    .byte 0xe0, 0xeb, 0x7a, 0x7c, 0x3b, 0x41, 0xb8, 0xae, 0x16, 0x56, 0xe3, 0xfa, 0xf1, 0x9f, 0xc4, 0x6a
    .byte 0xda, 0x09, 0x8d, 0xeb, 0x9c, 0x32, 0xb1, 0xfd, 0x86, 0x62, 0x05, 0x16, 0x5f, 0x49, 0xb8, 0x00
    .byte 0x5f, 0x9c, 0x95, 0xbc, 0xa3, 0x50, 0x8c, 0x24, 0xb1, 0xd0, 0xb1, 0x55, 0x9c, 0x83, 0xef, 0x5b
    .byte 0x04, 0x44, 0x5c, 0xc4, 0x58, 0x1c, 0x8e, 0x86, 0xd8, 0x22, 0x4e, 0xdd, 0xd0, 0x9f, 0x11, 0x57
    .fill 32, 1, 0xff
    .byte 0xda
    .fill 31, 1, 0xff
    .byte 0xdb
    .fill 31, 1, 0xff
Lnz_zero:   .fill 32, 1, 0
Lnv_id:     .ascii "6F1C4A2E-0B7D-4E8A-9C3F-2D5E7A1B9C04"
Lnv_text:   .ascii "hi from asmmesh"
Lnv_c1p:    .byte 0x03
            .ascii "6F1C4A2E-0B7D-4E8A-9C3F-2D5E7A1B9C04"
Lnv_r0p:    .byte 0x02
            .ascii "X"
            .byte 0, 0
// vectors from tools/qemu/bcvectors.py noise (bcnoise.py, checked against noiseprotocol)
.p2align 4
// initiator static secret (32 bytes)
Lnv_si:
    .byte 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10
    .byte 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20
// responder static secret (32 bytes)
Lnv_sr:
    .byte 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30
    .byte 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40
// initiator ephemeral secret (32 bytes)
Lnv_ei:
    .byte 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x50
    .byte 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60
// responder ephemeral secret (32 bytes)
Lnv_er:
    .byte 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70
    .byte 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x80
// initiator static public (32 bytes)
Lnv_spi:
    .byte 0x07, 0xa3, 0x7c, 0xbc, 0x14, 0x20, 0x93, 0xc8, 0xb7, 0x55, 0xdc, 0x1b, 0x10, 0xe8, 0x6c, 0xb4
    .byte 0x26, 0x37, 0x4a, 0xd1, 0x6a, 0xa8, 0x53, 0xed, 0x0b, 0xdf, 0xc0, 0xb2, 0xb8, 0x6d, 0x1c, 0x7c
// responder static public (32 bytes)
Lnv_spr:
    .byte 0x58, 0x69, 0xaf, 0xf4, 0x50, 0x54, 0x97, 0x32, 0xcb, 0xaa, 0xed, 0x5e, 0x5d, 0xf9, 0xb3, 0x0a
    .byte 0x6d, 0xa3, 0x1c, 0xb0, 0xe5, 0x74, 0x2b, 0xad, 0x5a, 0xd4, 0xa1, 0xa7, 0x68, 0xf1, 0xa6, 0x7b
// XX message 1: -> e (32 bytes)
Lnv_m1:
    .byte 0x64, 0xb1, 0x01, 0xb1, 0xd0, 0xbe, 0x5a, 0x87, 0x04, 0xbd, 0x07, 0x8f, 0x98, 0x95, 0x00, 0x1f
    .byte 0xc0, 0x3e, 0x8e, 0x9f, 0x95, 0x22, 0xf1, 0x88, 0xdd, 0x12, 0x8d, 0x98, 0x46, 0xd4, 0x84, 0x66
// XX message 2: <- e, ee, s, es (96 bytes)
Lnv_m2:
    .byte 0x24, 0x4f, 0xe3, 0xb9, 0x63, 0xe8, 0x99, 0xdd, 0x29, 0x5b, 0xaf, 0xfc, 0xe2, 0x48, 0xd3, 0x53
    .byte 0x0f, 0x3a, 0x9a, 0x74, 0x79, 0xba, 0x06, 0x30, 0x02, 0x68, 0x0e, 0xbf, 0xe7, 0xad, 0xad, 0x49
    .byte 0x31, 0xf7, 0x3f, 0x6f, 0xb0, 0x65, 0x67, 0x69, 0x04, 0x9b, 0xb4, 0x55, 0x6e, 0xf4, 0x63, 0xbb
    .byte 0x2a, 0x49, 0x33, 0xa1, 0x37, 0xd9, 0xd2, 0x94, 0x2b, 0xd4, 0x19, 0x6d, 0xed, 0x36, 0x4d, 0xa1
    .byte 0x28, 0x4d, 0x27, 0x04, 0xf8, 0x28, 0xe5, 0x04, 0x99, 0x79, 0xbb, 0x7a, 0x56, 0xc4, 0xa8, 0xba
    .byte 0x48, 0xdb, 0xc2, 0x67, 0x65, 0xa7, 0x4e, 0xfd, 0xbe, 0xb3, 0x80, 0x97, 0xae, 0x8f, 0x10, 0x50
// XX message 3: -> s, se (64 bytes)
Lnv_m3:
    .byte 0x2f, 0xcd, 0x2f, 0xdb, 0x56, 0x61, 0x9e, 0xc4, 0x76, 0xf1, 0xf3, 0x93, 0x31, 0x71, 0x2b, 0x0d
    .byte 0x32, 0x60, 0x2c, 0xba, 0x3c, 0xe8, 0xde, 0x88, 0x16, 0xc0, 0x4c, 0xb6, 0x49, 0xfb, 0xa7, 0xf2
    .byte 0xc4, 0x6f, 0x4a, 0x80, 0x25, 0xd1, 0xe7, 0x24, 0x57, 0x8b, 0x4f, 0x80, 0x92, 0x91, 0xbb, 0x13
    .byte 0xb4, 0xd7, 0xf3, 0x4f, 0x84, 0x26, 0x7e, 0x06, 0xdf, 0x2f, 0x72, 0x44, 0xcc, 0xad, 0x2e, 0x39
// the handshake hash (32 bytes)
Lnv_hh:
    .byte 0x28, 0x4e, 0x70, 0x27, 0x79, 0x17, 0x6c, 0x76, 0x59, 0xb8, 0xe7, 0x82, 0x1c, 0x7a, 0x24, 0xd6
    .byte 0x30, 0x09, 0xde, 0x75, 0x64, 0x71, 0x86, 0x7a, 0x8f, 0x6e, 0x8a, 0xa8, 0x3c, 0xe6, 0x3f, 0xb5
// a private message: id, "hi from asmmesh" (56 bytes)
Lnv_pm:
    .byte 0x01, 0x00, 0x24, 0x36, 0x46, 0x31, 0x43, 0x34, 0x41, 0x32, 0x45, 0x2d, 0x30, 0x42, 0x37, 0x44
    .byte 0x2d, 0x34, 0x45, 0x38, 0x41, 0x2d, 0x39, 0x43, 0x33, 0x46, 0x2d, 0x32, 0x44, 0x35, 0x45, 0x37
    .byte 0x41, 0x31, 0x42, 0x39, 0x43, 0x30, 0x34, 0x01, 0x0f, 0x68, 0x69, 0x20, 0x66, 0x72, 0x6f, 0x6d
    .byte 0x20, 0x61, 0x73, 0x6d, 0x6d, 0x65, 0x73, 0x68
// it, sealed by the initiator (nonce 0) (76 bytes)
Lnv_c0:
    .byte 0x00, 0x00, 0x00, 0x00, 0x60, 0x41, 0x88, 0x88, 0xba, 0xa7, 0xc8, 0x90, 0x70, 0x55, 0x51, 0x46
    .byte 0xfd, 0x0f, 0x44, 0x3f, 0x54, 0x16, 0xcb, 0xd5, 0x9d, 0x6a, 0xd4, 0x6d, 0x3d, 0xbc, 0x08, 0x9e
    .byte 0xe0, 0x56, 0x2e, 0x6b, 0xdb, 0xd5, 0x06, 0x84, 0x9c, 0x82, 0x12, 0xa7, 0xff, 0xe0, 0x4c, 0x24
    .byte 0xc5, 0xd0, 0xc0, 0xc4, 0xb0, 0xfb, 0xa3, 0x2c, 0xec, 0xab, 0x86, 0x34, 0xaf, 0xcd, 0x63, 0x75
    .byte 0x08, 0x3d, 0x93, 0x3e, 0x80, 0x4c, 0xbc, 0xc6, 0x7e, 0x2b, 0x0d, 0x1a
// a delivered ack, sealed by the initiator (nonce 1) (57 bytes)
Lnv_c1:
    .byte 0x00, 0x00, 0x00, 0x01, 0x0a, 0xe9, 0x24, 0x81, 0x6b, 0x23, 0x88, 0x58, 0xb0, 0xd8, 0x05, 0x57
    .byte 0xaf, 0x54, 0x01, 0x8f, 0xdd, 0x71, 0x62, 0x55, 0xb3, 0x96, 0x35, 0x63, 0xa7, 0x6b, 0xaf, 0xf0
    .byte 0x47, 0x9f, 0x14, 0x7b, 0xa5, 0x8f, 0xcb, 0x3f, 0x07, 0x22, 0x10, 0x99, 0xff, 0xaf, 0x35, 0x74
    .byte 0x69, 0x42, 0x3e, 0x42, 0xe8, 0xae, 0x80, 0x24, 0xd9
// a read receipt "X", sealed by the responder (nonce 0) (22 bytes)
Lnv_r0:
    .byte 0x00, 0x00, 0x00, 0x00, 0x9a, 0xfe, 0x3f, 0xba, 0x5d, 0xcd, 0xa0, 0x97, 0x54, 0x47, 0xf9, 0xd6
    .byte 0x40, 0x8a, 0xf9, 0x9b, 0x96, 0xc1


.section __TEXT,__cstring,cstring_literals
Ln_nz192:   .asciz "192 bitchat noise: the XX handshake, bitchat's three messages byte for byte"
Ln_nz193:   .asciz "193 bitchat noise: transport both ways; replays, old nonces, changed bytes refused"
Ln_nz194:   .asciz "194 bitchat noise: bad keys, lengths and bytes refused; a transport outlives a new handshake"
Ln_nz195:   .asciz "195 bitchat noise: the private-message payload, and broken ones refused"
