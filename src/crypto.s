// crypto.s — the mesh passphrase. Macs that share one read each other's room
// messages and remote commands; nobody else can, and nobody can forge them.
//
//   key     PBKDF2-HMAC-SHA256(passphrase, "asmmesh mesh v1", 20000 rounds) -> 64 bytes:
//           32 for AES-256, 32 for HMAC-SHA256
//   seal    AES-256 in counter mode, counter block = packet id (8) || block number (8);
//           tag = first 8 bytes of HMAC-SHA256(id, room/target, sender, ciphertext)
//
// The packet id is random and never reused, so each message gets its own
// keystream. HELLOs (names on the mesh) stay readable so people still show up.

.include "macros.inc"

.set KCCPBKDF2,       2
.set KCCPRF_SHA256,   3
.set KCCHMAC_SHA256,  2
.set KCCAES,          0
.set KCCECB,          2
.set ROUNDS,          20000

.data
.p2align 3
.globl _g_crypto_on
_g_crypto_on:   .quad 0
_g_kcur:        .quad 0              // the 64-byte key the next seal/open uses
.zerofill __DATA,__bss,_g_key,64,4
.zerofill __DATA,__bss,_g_ctr_in,256,4
.zerofill __DATA,__bss,_g_ctr_out,256,4
.zerofill __DATA,__bss,_g_mac_in,288,4
.zerofill __DATA,__bss,_g_mac,32,4
.zerofill __DATA,__bss,_g_pnorm,128,4
.globl _g_mesh_pass
.zerofill __DATA,__bss,_g_mesh_pass,128,4

.text
.p2align 2

// void _crypto_set(const char *passphrase) — "" or "off" turns it off
.globl _crypto_set
_crypto_set:
    ENTER 32
    mov  x19, x0
    ADRL x8, _g_crypto_on
    str  xzr, [x8]
    ADRL x20, _g_pnorm                // letters and digits, lower case: the same
    mov  x21, #0                      // passphrase typed a little differently still works
Lcs_norm:
    cmp  x21, #120
    b.hs Lcs_normed
    ldrb w9, [x19], #1
    cbz  w9, Lcs_normed
    cmp  w9, #0x80                    // other alphabets: keep every byte
    b.hs Lcs_keep
    sub  w10, w9, #'0'
    cmp  w10, #9
    b.ls Lcs_keep
    orr  w9, w9, #0x20
    sub  w10, w9, #'a'
    cmp  w10, #25
    b.hi Lcs_norm
Lcs_keep:
    strb w9, [x20, x21]
    add  x21, x21, #1
    b    Lcs_norm
Lcs_normed:
    strb wzr, [x20, x21]
    cbz  x21, Lcs_done
    mov  x0, x20
    ADRL x1, Ls_off
    bl   _strcmp
    cbz  w0, Lcs_done
    mov  x19, x20
    mov  x20, x21
    ADRL x0, Ls_salt
    bl   _strlen
    mov  x4, x0                       // salt length
    mov  x0, #KCCPBKDF2
    mov  x1, x19
    mov  x2, x20
    ADRL x3, Ls_salt
    mov  x5, #KCCPRF_SHA256
    mov  x6, #(ROUNDS & 0xffff)
    movk x6, #(ROUNDS >> 16), lsl #16
    ADRL x7, _g_key
    mov  x9, #64                      // ninth argument on the stack
    str  x9, [sp]
    bl   _CCKeyDerivationPBKDF
    cbnz w0, Lcs_done
    ADRL x8, _g_crypto_on
    mov  x9, #1
    str  x9, [x8]
Lcs_done:
    LEAVE 32

// void _keystream(const uint8 *nonce8, size_t n) — n bytes of AES-CTR keystream into _g_ctr_out
_keystream:
    ENTER 32                          // [96] bytes moved
    mov  x19, x0
    add  x20, x1, #15
    lsr  x20, x20, #4                 // blocks
    cmp  x20, #16
    mov  x9, #16
    csel x20, x9, x20, hi
    ldr  x21, [x19]                   // the nonce
    ADRL x22, _g_ctr_in
    mov  x23, #0
Lks_block:
    cmp  x23, x20
    b.hs Lks_encrypt
    lsl  x9, x23, #4
    add  x10, x22, x9
    str  x21, [x10]
    rev  x11, x23                     // block number, big-endian
    str  x11, [x10, #8]
    add  x23, x23, #1
    b    Lks_block
Lks_encrypt:
    mov  x0, #0                       // kCCEncrypt
    mov  x1, #KCCAES
    mov  x2, #KCCECB
    ADRL x3, _g_kcur
    ldr  x3, [x3]
    mov  x4, #32
    mov  x5, #0                       // no IV in ECB
    ADRL x6, _g_ctr_in
    lsl  x7, x20, #4
    ADRL x9, _g_ctr_out               // dataOut, dataOutAvailable, dataOutMoved on the stack
    str  x9, [sp]
    mov  x9, #256
    str  x9, [sp, #8]
    add  x9, sp, #96
    str  x9, [sp, #16]
    bl   _CCCrypt
    LEAVE 32

// void _mac(const uint8 *aad24, const uint8 *ct, size_t n) — HMAC into _g_mac
_mac:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    cmp  x21, #256
    mov  x9, #256
    csel x21, x9, x21, hi
    ADRL x0, _g_mac_in
    mov  x1, x19
    mov  x2, #24
    bl   _memcpy
    ADRL x0, _g_mac_in
    add  x0, x0, #24
    mov  x1, x20
    mov  x2, x21
    bl   _memcpy
    mov  x0, #KCCHMAC_SHA256
    ADRL x1, _g_kcur
    ldr  x1, [x1]
    add  x1, x1, #32
    mov  x2, #32
    ADRL x3, _g_mac_in
    add  x4, x21, #24
    ADRL x5, _g_mac
    bl   _CCHmac
    LEAVE 0

// size_t _crypto_seal(uint8 *text, size_t n, const uint8 *aad24) — encrypt in place and
//   append an 8-byte tag. The nonce is the packet id, the first 8 bytes of aad. -> n + 8
.globl _crypto_seal
_crypto_seal:
    ADRL x8, _g_key
    ADRL x9, _g_kcur
    str  x8, [x9]
    b    _seal_core

// size_t _seal_key(const uint8 *key64, uint8 *text, size_t n, const uint8 *aad24)
//   the same, with a room key or a pairwise key
.globl _seal_key
_seal_key:
    ADRL x9, _g_kcur
    str  x0, [x9]
    mov  x0, x1
    mov  x1, x2
    mov  x2, x3
    b    _seal_core

_seal_core:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, x21
    mov  x1, x20
    bl   _keystream
    ADRL x9, _g_ctr_out
    mov  x10, #0
Lse_xor:
    cmp  x10, x20
    b.hs Lse_mac
    ldrb w11, [x19, x10]
    ldrb w12, [x9, x10]
    eor  w11, w11, w12
    strb w11, [x19, x10]
    add  x10, x10, #1
    b    Lse_xor
Lse_mac:
    mov  x0, x21
    mov  x1, x19
    mov  x2, x20
    bl   _mac
    ADRL x9, _g_mac
    ldr  x10, [x9]
    str  x10, [x19, x20]              // unaligned is fine on arm64
    add  x0, x20, #8
    LEAVE 0

// long _crypto_open(const uint8 *in, size_t n, const uint8 *aad24, char *out)
//   -> plaintext length (NUL-terminated in out), -1 wrong passphrase or forged, -2 no passphrase
.globl _crypto_open
_crypto_open:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, Lop_nokey
    ADRL x8, _g_key
    ADRL x9, _g_kcur
    str  x8, [x9]
    b    Lop_core

// long _open_key(const uint8 *key64, const uint8 *in, size_t n, const uint8 *aad24, char *out)
//   -> plaintext length, or -1 if the key is wrong or the text was changed
.globl _open_key
_open_key:
    ENTER 0
    ADRL x9, _g_kcur
    str  x0, [x9]
    mov  x19, x1
    mov  x20, x2
    mov  x21, x3
    mov  x22, x4
Lop_core:
    cmp  x20, #8
    b.lo Lop_bad
    sub  x20, x20, #8                 // ciphertext length
    mov  x0, x21
    mov  x1, x19
    mov  x2, x20
    bl   _mac
    ADRL x9, _g_mac
    ldr  x10, [x9]
    ldr  x11, [x19, x20]
    cmp  x10, x11
    b.ne Lop_bad
    mov  x0, x21
    mov  x1, x20
    bl   _keystream
    ADRL x9, _g_ctr_out
    mov  x10, #0
Lop_xor:
    cmp  x10, x20
    b.hs Lop_done
    ldrb w11, [x19, x10]
    ldrb w12, [x9, x10]
    eor  w11, w11, w12
    strb w11, [x22, x10]
    add  x10, x10, #1
    b    Lop_xor
Lop_done:
    strb wzr, [x22, x20]
    mov  x0, x20
    LEAVE 0
Lop_bad:
    mov  x0, #-1
    LEAVE 0
Lop_nokey:
    mov  x0, #-2
    LEAVE 0

// void _crypto_kc_read(void) — background: the saved passphrase
.globl _crypto_kc_read
_crypto_kc_read:
    ENTER 0
    ADRL x0, Ls_kc_mesh
    ADRL x1, _g_mesh_pass
    mov  x2, #128
    bl   _kc_get
    LEAVE 0

// void _crypto_init(void) — main thread, after _crypto_kc_read
.globl _crypto_init
_crypto_init:
    ENTER 0
    ADRL x0, _g_mesh_pass
    bl   _crypto_set
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    cbz  x9, Lci_done
    ADRL x0, Ls_on_msg
    bl   _chat_line
    bl   _ui_update_status
Lci_done:
    LEAVE 0

// - meshPassphrase: — Mesh › Mesh Passphrase…
.globl _crypto_dialog
_crypto_dialog:
    ENTER 0
    ADRL x0, Ls_title
    ADRL x1, Ls_info
    ADRL x2, Ls_ph
    mov  x3, #0
    mov  x4, #1
    ADRL x5, _g_mesh_pass
    mov  x6, #120
    bl   _ask_text
    cbz  x0, Lcd_done
    ADRL x0, Ls_kc_mesh
    ADRL x1, _g_mesh_pass
    bl   _kc_set
    ADRL x0, _g_mesh_pass
    bl   _crypto_set
    ADRL x8, _g_crypto_on
    ldr  x9, [x8]
    ADRL x0, Ls_on_msg
    ADRL x8, Ls_off_msg
    cmp  x9, #0
    csel x0, x8, x0, eq
    bl   _chat_line
    bl   _ui_update_status
Lcd_done:
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_salt:     .asciz "asmmesh mesh v1"
Ls_off:      .asciz "off"
Ls_kc_mesh:  .asciz "asmmesh.meshpassphrase"
Ls_title:    .asciz "Mesh Passphrase"
Ls_info:     .asciz "Macs with the same passphrase can read each other's room messages and send each other device commands; nobody else can read or fake them. Tell it to people in person, not over the mesh.\n\nCapitals, spaces and punctuation don't matter. Type off to turn encryption off."
Ls_ph:       .asciz "passphrase"
Ls_on_msg:   .asciz "\302\267 \360\237\224\222 Encrypted: room messages and remote commands now need the mesh passphrase."
Ls_off_msg:  .asciz "\302\267 Encryption is off: messages on the mesh are readable by any asmmesh nearby."
