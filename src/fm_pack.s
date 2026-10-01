// asmfm — proto.S : message compression, frame building, reassembly
//
// Radio frame payload layouts (inside an HDLC frame with CRC-16):
//   'B' id part nparts data...   broadcast chunk (repeated carousel)
//   'R' id text...               client -> station request
//   'W' id                       station: request received, fetching
//   'P' id part nparts data...   station -> client page chunk
//   'A' id part                  client -> station acknowledgement
// A message is [u32 original length][zlib data], cut into 200-byte chunks.
.include "fm_defs.inc"
    .text


// fm_pack(x0 = src, x1 = len, x2 = dst, x3 = cap) -> x0 = packed length (0 = error)
    .globl _fm_pack
    .p2align 2
_fm_pack:
    FENTER 16
    mov x19, x0
    mov x20, x1
    mov x21, x2
    str w20, [x21]
    sub x3, x3, #4
    str x3, [sp, #LOC]
    add x0, x21, #4
    add x1, sp, #LOC
    mov x2, x19
    mov x3, x20
    mov w4, #9
    bl _compress2
    cbnz w0, 9f
    ldr x0, [sp, #LOC]
    add x0, x0, #4
    FLEAVE 16
9:  mov x0, #0
    FLEAVE 16

// fm_unpack(x0 = src, x1 = len, x2 = dst, x3 = cap) -> x0 = length, or -1
    .globl _fm_unpack
    .p2align 2
_fm_unpack:
    FENTER 16
    mov x19, x0
    mov x20, x1
    mov x21, x2
    cmp x20, #5
    b.lt 9f
    ldr w4, [x19]
    sub x3, x3, #1
    cmp x4, x3
    b.hi 9f
    str x4, [sp, #LOC]
    mov x0, x21
    add x1, sp, #LOC
    add x2, x19, #4
    sub x3, x20, #4
    bl _uncompress
    cbnz w0, 9f
    ldr x0, [sp, #LOC]
    strb wzr, [x21, x0]
    FLEAVE 16
9:  mov x0, #-1
    FLEAVE 16

// fm_send(x0 = payload, w1 = length): modulate and queue for transmission
    .globl _fm_send
    .p2align 2
_fm_send:
    FENTER
    LA x2, _fm_modbuf
    bl _fm_mod
    mov x1, x0
    LA x0, _fm_modbuf
    bl _fm_tx_push
    FLEAVE

    BSS _fm_modbuf, (MODBUF*2)
