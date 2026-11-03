// netscan_core.s — the bytes-only parts of the network scan (netscan.s does the sockets):
// which addresses to try on this subnet, an address as text, the maker a MAC address
// belongs to, which ports are tried and what the open ones suggest a device is. No libc,
// so they run under qemu too (tools/qemu/run.sh).
//
// Addresses here are 32-bit numbers in host order: 192.168.1.20 is 0xC0A80114.

.include "macros.inc"

.set NS_NPORTS, 13

.macro NSK reg, val                   // a 32-bit constant (MOVI reads as SIMD to GNU as)
    movz \reg, #((\val) & 0xffff)
    movk \reg, #(((\val) >> 16) & 0xffff), lsl #16
.endm

.text
.p2align 2

// long _ns_range(long ip, long mask, long *first) -> how many addresses to try, from
//   *first: every host on the subnet, but no more than a /24's (the /24 around us on a
//   bigger one), and none on a /31 or /32 (leaf)
.globl _ns_range
_ns_range:
    mov  w9, w1
    mov  w10, #0xffffff00
    cmp  w9, w10                      // a bigger subnet than a /24 (fewer mask bits):
    csel w9, w10, w9, lo              //   just our /24
    mvn  w11, w9                      // host bits
    and  w12, w0, w9                  // the network
    add  w12, w12, #1
    str  x12, [x2]
    cmp  w11, #2                      // /31, /32: no hosts to try
    b.lo 1f
    sub  w0, w11, #1                  // 2^n - 2
    ret
1:  mov  x0, #0
    ret

// char *_ns_ip_text(long ip, char *out /*16*/) -> out, "192.168.1.20" (leaf)
.globl _ns_ip_text
_ns_ip_text:
    mov  x9, x1
    mov  x10, #24
1:  lsr  w11, w0, w10
    and  w11, w11, #0xff
    mov  w12, #100                    // up to three digits, no leading zeros
    udiv w13, w11, w12
    cbz  w13, 2f
    add  w14, w13, #'0'
    strb w14, [x9], #1
2:  msub w11, w13, w12, w11
    mov  w12, #10
    udiv w14, w11, w12
    orr  w15, w13, w14
    cbz  w15, 3f
    add  w15, w14, #'0'
    strb w15, [x9], #1
3:  msub w11, w14, w12, w11
    add  w11, w11, #'0'
    strb w11, [x9], #1
    cbz  x10, 4f
    mov  w11, #'.'
    strb w11, [x9], #1
    sub  x10, x10, #8
    b    1b
4:  strb wzr, [x9]
    mov  x0, x1
    ret

// const char *_oui_vendor(const uint8 *mac) -> its maker if we know the first three bytes,
//   "private address" for a randomised one (Wi-Fi privacy on phones), 0 if unknown (leaf)
.globl _oui_vendor
_oui_vendor:
    ldrb w9, [x0]
    ldrb w10, [x0, #1]
    ldrb w11, [x0, #2]
    orr  w12, w9, w10
    orr  w12, w12, w11
    cbz  w12, 8f                      // 00:00:00: nothing known
    tbnz w9, #1, 7f                   // locally administered: randomised
    lsl  w9, w9, #16
    orr  w9, w9, w10, lsl #8
    orr  w9, w9, w11
    ADRL x12, Loui
1:  ldp  w13, w14, [x12], #8          // prefix, string offset
    cbz  w13, 8f
    cmp  w13, w9
    b.ne 1b
    ADRL x0, Loui_names
    add  x0, x0, x14
    ret
7:  ADRL x0, Ls_private
    ret
8:  mov  x0, #0
    ret

// long _ns_port(long i) -> the i-th port tried (0 past the last) (leaf)
.globl _ns_port
_ns_port:
    cmp  x0, #NS_NPORTS
    b.hs 1f
    ADRL x9, Lns_ports
    ldrh w0, [x9, x0, lsl #1]
    ret
1:  mov  x0, #0
    ret

// long _ns_nports(void) (leaf)
.globl _ns_nports
_ns_nports:
    mov  x0, #NS_NPORTS
    ret

// char *_ns_ports_text(long open, char *out, long cap) -> out: "80 web, 22 SSH" for the
//   bits set in open (bit i: _ns_port(i)), "none answered" if none (leaf)
.globl _ns_ports_text
_ns_ports_text:
    mov  x9, #0                       // bit
    mov  x10, #0                      // length
    sub  x2, x2, #1
1:  cmp  x9, #NS_NPORTS
    b.hs 6f
    lsr  x11, x0, x9
    tbz  x11, #0, 5f
    cbz  x10, 2f                      // ", " between
    cmp  x10, x2
    b.hs 6f
    mov  w12, #','
    strb w12, [x1, x10]
    add  x10, x10, #1
    cmp  x10, x2
    b.hs 6f
    mov  w12, #' '
    strb w12, [x1, x10]
    add  x10, x10, #1
2:  ADRL x12, Lns_port_names
    ldr  x13, [x12, x9, lsl #3]
    ADRL x12, Lns_pn
    add  x12, x12, x13
3:  ldrb w13, [x12], #1
    cbz  w13, 5f
    cmp  x10, x2
    b.hs 6f
    strb w13, [x1, x10]
    add  x10, x10, #1
    b    3b
5:  add  x9, x9, #1
    b    1b
6:  cbnz x10, 7f
    ADRL x12, Ls_none_open
8:  ldrb w13, [x12], #1
    cbz  w13, 7f
    cmp  x10, x2
    b.hs 7f
    strb w13, [x1, x10]
    add  x10, x10, #1
    b    8b
7:  strb wzr, [x1, x10]
    mov  x0, x1
    ret

// const char *_ns_kind(long open, const uint8 *mac /*or 0*/) -> a guess at what it is,
//   from its open ports first (they say what it does), then its maker (leaf)
.globl _ns_kind
_ns_kind:
    mov  x15, x30
    ADRL x9, Lns_kinds
1:  ldp  x10, x11, [x9], #16          // bits that say it, the words
    cbz  x10, 2f
    tst  x0, x10
    b.eq 1b
    mov  x0, x11
    mov  x30, x15
    ret
2:  cbz  x1, 3f
    mov  x0, x1
    bl   _oui_vendor
    cbnz x0, 4f
3:  ADRL x0, Ls_k_device
4:  mov  x30, x15
    ret

// ---------------------------------------------------------------------------
// self-tests 192-194, called from test.s

.macro NS_IS lbl                          // x20 &= (string at x0 == \lbl)
    ADRL x1, \lbl
    bl   Lns_same
    and  x20, x20, x0
.endm

Lns_same:
    mov  x9, #0
1:  ldrb w10, [x0, x9]
    ldrb w11, [x1, x9]
    cmp  w10, w11
    b.ne 2f
    add  x9, x9, #1
    cbnz w10, 1b
    mov  x0, #1
    ret
2:  mov  x0, #0
    ret

.globl _netscan_selftest
_netscan_selftest:
    ENTER 128                             // [96] first  [104] text (64)
    mov  x19, #0

    // 192. ranges: a /24, a /16 (just our /24), a /28, a /31; addresses as text
    mov  x20, #1
    NSK  x0, 0xC0A80114                   // 192.168.1.20/24
    NSK  x1, 0xFFFFFF00
    add  x2, sp, #96
    bl   _ns_range
    cmp  x0, #254
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #96]
    NSK  x10, 0xC0A80101
    cmp  x9, x10
    cset x9, eq
    and  x20, x20, x9
    NSK  x0, 0x0A0005C8                   // 10.0.5.200/16: 10.0.5.1 .. 10.0.5.254
    NSK  x1, 0xFFFF0000
    add  x2, sp, #96
    bl   _ns_range
    cmp  x0, #254
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #96]
    NSK  x10, 0x0A000501
    cmp  x9, x10
    cset x9, eq
    and  x20, x20, x9
    NSK  x0, 0xC0A80122                   // a /28: 14 hosts from .17
    NSK  x1, 0xFFFFFFF0
    add  x2, sp, #96
    bl   _ns_range
    cmp  x0, #14
    cset x9, eq
    and  x20, x20, x9
    ldr  x9, [sp, #96]
    NSK  x10, 0xC0A80121
    cmp  x9, x10
    cset x9, eq
    and  x20, x20, x9
    NSK  x0, 0xC0A80122                   // a /31: none
    NSK  x1, 0xFFFFFFFE
    add  x2, sp, #96
    bl   _ns_range
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    NSK  x0, 0xC0A80114
    add  x1, sp, #104
    bl   _ns_ip_text
    NS_IS Lnt_ip1
    NSK  x0, 0x0A000009
    add  x1, sp, #104
    bl   _ns_ip_text
    NS_IS Lnt_ip2
    mov  w1, w20
    ADRL x0, Ln_ns192
    bl   _t_report
    add  x19, x19, x0

    // 193. makers: Apple, Raspberry Pi, a randomised address, an unknown one
    mov  x20, #1
    ADRL x0, Lnt_mac_apple
    bl   _oui_vendor
    cbz  x0, 1f
    NS_IS Lnt_apple
    b    2f
1:  mov  x20, #0
2:  ADRL x0, Lnt_mac_pi
    bl   _oui_vendor
    cbz  x0, 3f
    NS_IS Lnt_pi
    b    4f
3:  mov  x20, #0
4:  ADRL x0, Lnt_mac_rand
    bl   _oui_vendor
    cbz  x0, 5f
    NS_IS Ls_private
    b    6f
5:  mov  x20, #0
6:  ADRL x0, Lnt_mac_unknown
    bl   _oui_vendor
    cmp  x0, #0
    cset x9, eq
    and  x20, x20, x9
    mov  w1, w20
    ADRL x0, Ln_ns193
    bl   _t_report
    add  x19, x19, x0

    // 194. open ports as text (and cut to fit); what they suggest; nothing open
    mov  x20, #1
    mov  x0, #0b101                       // 80, 22
    add  x1, sp, #104
    mov  x2, #64
    bl   _ns_ports_text
    NS_IS Lnt_ports
    mov  x0, #0b101
    add  x1, sp, #104
    mov  x2, #6                           // "80 web" doesn't fit with its 0: cut
    bl   _ns_ports_text
    NS_IS Lnt_cut
    mov  x0, #0
    add  x1, sp, #104
    mov  x2, #64
    bl   _ns_ports_text
    NS_IS Ls_none_open
    mov  x0, #(1 << 5)                    // 62078
    mov  x1, #0
    bl   _ns_kind
    NS_IS Ls_k_iphone
    mov  x0, #(1 << 8)                    // 9100
    ADRL x1, Lnt_mac_apple
    bl   _ns_kind
    NS_IS Ls_k_printer
    mov  x0, #0                           // nothing open: its maker
    ADRL x1, Lnt_mac_pi
    bl   _ns_kind
    NS_IS Lnt_pi
    mov  x0, #0
    ADRL x1, Lnt_mac_unknown
    bl   _ns_kind
    NS_IS Ls_k_device
    mov  w1, w20
    ADRL x0, Ln_ns194
    bl   _t_report
    add  x19, x19, x0

    mov  x0, x19
    LEAVE 128

// ---------------------------------------------------------------------------
.section __TEXT,__const
.p2align 2
// the ports tried, in bit order (_ns_ports_text and _ns_kind read the bits the same way)
Lns_ports:
    .hword 80, 443, 22, 445, 548, 62078, 8080, 554, 9100, 631, 1883, 8443, 7000
.p2align 2
// maker prefixes (the first three bytes of a MAC address), and where its name is
Loui:
    .word 0x0017F2, Lo_apple - Loui_names
    .word 0x3C22FB, Lo_apple - Loui_names
    .word 0xA4B197, Lo_apple - Loui_names
    .word 0xF0B479, Lo_apple - Loui_names
    .word 0x8C8590, Lo_apple - Loui_names
    .word 0xACBC32, Lo_apple - Loui_names
    .word 0x14C213, Lo_apple - Loui_names
    .word 0xD0817A, Lo_apple - Loui_names
    .word 0xF01898, Lo_apple - Loui_names
    .word 0x88665A, Lo_apple - Loui_names
    .word 0xB827EB, Lo_pi - Loui_names
    .word 0xDCA632, Lo_pi - Loui_names
    .word 0xE45F01, Lo_pi - Loui_names
    .word 0x2CCF67, Lo_pi - Loui_names
    .word 0xD83ADD, Lo_pi - Loui_names
    .word 0x001788, Lo_hue - Loui_names
    .word 0xECB5FA, Lo_hue - Loui_names
    .word 0x000E58, Lo_sonos - Loui_names
    .word 0x5CAAFD, Lo_sonos - Loui_names
    .word 0x949F3E, Lo_sonos - Loui_names
    .word 0x48A6B8, Lo_sonos - Loui_names
    .word 0xB0A737, Lo_roku - Loui_names
    .word 0xD83134, Lo_roku - Loui_names
    .word 0xDC3A5E, Lo_roku - Loui_names
    .word 0x240AC4, Lo_esp - Loui_names
    .word 0x30AEA4, Lo_esp - Loui_names
    .word 0x3C71BF, Lo_esp - Loui_names
    .word 0x84CCA8, Lo_esp - Loui_names
    .word 0xA4CF12, Lo_esp - Loui_names
    .word 0xC45BBE, Lo_esp - Loui_names
    .word 0xECFABC, Lo_esp - Loui_names
    .word 0x7CDFA1, Lo_esp - Loui_names
    .word 0x34EA34, Lo_esp - Loui_names
    .word 0x50C7BF, Lo_tplink - Loui_names
    .word 0xB0BE76, Lo_tplink - Loui_names
    .word 0x1C61B4, Lo_tplink - Loui_names
    .word 0x98DAC4, Lo_tplink - Loui_names
    .word 0x001132, Lo_synology - Loui_names
    .word 0x0418D6, Lo_ubnt - Loui_names
    .word 0x245A4C, Lo_ubnt - Loui_names
    .word 0x784558, Lo_ubnt - Loui_names
    .word 0xF4F5D8, Lo_google - Loui_names
    .word 0x54609A, Lo_google - Loui_names
    .word 0x6C5697, Lo_amazon - Loui_names
    .word 0xFCA667, Lo_amazon - Loui_names
    .word 0x44650D, Lo_amazon - Loui_names
    .word 0x00045A, Lo_linksys - Loui_names
    .word 0x00146C, Lo_netgear - Loui_names
    .word 0xA040A0, Lo_netgear - Loui_names
    .word 0x001E06, Lo_wibrain - Loui_names
    .word 0x8CAAB5, Lo_esp - Loui_names
    .word 0x00155D, Lo_hyperv - Loui_names
    .word 0x000C29, Lo_vmware - Loui_names
    .word 0x005056, Lo_vmware - Loui_names
    .word 0x080027, Lo_vbox - Loui_names
    .word 0x0024E4, Lo_withings - Loui_names
    .word 0x18B430, Lo_nest - Loui_names
    .word 0x64166D, Lo_nest - Loui_names
    .word 0x7C2EBD, Lo_google - Loui_names
    .word 0x001A11, Lo_google - Loui_names
    .word 0x9CB6D0, Lo_rivet - Loui_names
    .word 0x00E04C, Lo_realtek - Loui_names
    .word 0x0050F2, Lo_microsoft - Loui_names
    .word 0x28C68E, Lo_netgear - Loui_names
    .word 0x00090F, Lo_fortinet - Loui_names
    .word 0x001F33, Lo_netgear - Loui_names
    .word 0xD8EB46, Lo_google - Loui_names
    .word 0, 0
.p2align 3

.section __TEXT,__const
Lnt_mac_apple:  .byte 0x3C, 0x22, 0xFB, 0x01, 0x02, 0x03
Lnt_mac_pi:     .byte 0xB8, 0x27, 0xEB, 0x11, 0x22, 0x33
Lnt_mac_rand:   .byte 0x5A, 0x11, 0x22, 0x33, 0x44, 0x55
Lnt_mac_unknown: .byte 0x00, 0x99, 0x98, 0x01, 0x02, 0x03

.section __DATA,__const
.p2align 3
Lns_port_names:                           // offsets into Lns_pn, in bit order
    .quad Lp_80 - Lns_pn, Lp_443 - Lns_pn, Lp_22 - Lns_pn, Lp_445 - Lns_pn, Lp_548 - Lns_pn
    .quad Lp_62078 - Lns_pn, Lp_8080 - Lns_pn, Lp_554 - Lns_pn, Lp_9100 - Lns_pn
    .quad Lp_631 - Lns_pn, Lp_1883 - Lns_pn, Lp_8443 - Lns_pn, Lp_7000 - Lns_pn
// what open ports say, the first match wins (bits as in Lns_ports)
Lns_kinds:
    .quad (1 << 5), Ls_k_iphone           // 62078: an iPhone or iPad (lockdown)
    .quad (1 << 8) | (1 << 9), Ls_k_printer
    .quad (1 << 7), Ls_k_camera           // RTSP
    .quad (1 << 10), Ls_k_hub             // MQTT
    .quad (1 << 12), Ls_k_airplay         // AirPlay
    .quad (1 << 4), Ls_k_afp              // AFP: a Mac or a NAS
    .quad (1 << 3), Ls_k_smb              // file sharing
    .quad (1 << 2), Ls_k_ssh
    .quad (1 << 0) | (1 << 1) | (1 << 6) | (1 << 11), Ls_k_web
    .quad 0, 0

.section __TEXT,__const      // names found by offset: not a literal section, which
                              //   the linker may merge and reorder
Lns_pn:
Lp_80:          .asciz "80 web"
Lp_443:         .asciz "443 web (https)"
Lp_22:          .asciz "22 SSH"
Lp_445:         .asciz "445 file sharing"
Lp_548:         .asciz "548 AFP"
Lp_62078:       .asciz "62078 iPhone sync"
Lp_8080:        .asciz "8080 web"
Lp_554:         .asciz "554 video (RTSP)"
Lp_9100:        .asciz "9100 printing"
Lp_631:         .asciz "631 printing (IPP)"
Lp_1883:        .asciz "1883 MQTT"
Lp_8443:        .asciz "8443 web (https)"
Lp_7000:        .asciz "7000 AirPlay"
Loui_names:
Lo_apple:       .asciz "Apple"
Lo_pi:          .asciz "Raspberry Pi"
Lo_hue:         .asciz "Philips Hue"
Lo_sonos:       .asciz "Sonos"
Lo_roku:        .asciz "Roku"
Lo_esp:         .asciz "Espressif (smart plug, bulb or sensor)"
Lo_tplink:      .asciz "TP-Link"
Lo_synology:    .asciz "Synology"
Lo_ubnt:        .asciz "Ubiquiti"
Lo_google:      .asciz "Google"
Lo_amazon:      .asciz "Amazon"
Lo_linksys:     .asciz "Linksys"
Lo_netgear:     .asciz "Netgear"
Lo_wibrain:     .asciz "WIBRAIN"
Lo_hyperv:      .asciz "Hyper-V virtual machine"
Lo_vmware:      .asciz "VMware virtual machine"
Lo_vbox:        .asciz "VirtualBox virtual machine"
Lo_withings:    .asciz "Withings"
Lo_nest:        .asciz "Google Nest"
Lo_rivet:       .asciz "Rivet Networks"
Lo_realtek:     .asciz "Realtek"
Lo_microsoft:   .asciz "Microsoft"
Lo_fortinet:    .asciz "Fortinet"
.section __TEXT,__cstring,cstring_literals
Ls_private:     .asciz "private address"
Ls_none_open:   .asciz "none answered"
Ls_k_device:    .asciz "Network device"
Ls_k_iphone:    .asciz "iPhone or iPad"
Ls_k_printer:   .asciz "Printer"
Ls_k_camera:    .asciz "Camera or video"
Ls_k_hub:       .asciz "Smart-home hub (MQTT)"
Ls_k_airplay:   .asciz "AirPlay (Apple TV, Mac, speaker)"
Ls_k_afp:       .asciz "Mac or NAS"
Ls_k_smb:       .asciz "Computer or NAS"
Ls_k_ssh:       .asciz "Computer (SSH)"
Ls_k_web:       .asciz "Device with a web page"
Lnt_ip1:        .asciz "192.168.1.20"
Lnt_ip2:        .asciz "10.0.0.9"
Lnt_apple:      .asciz "Apple"
Lnt_pi:         .asciz "Raspberry Pi"
Lnt_ports:      .asciz "80 web, 22 SSH"
Lnt_cut:        .asciz "80 we"
Ln_ns192:       .asciz "192 network scan: which addresses to try, and addresses as text"
Ln_ns193:       .asciz "193 network scan: makers from MAC addresses, randomised ones said so"
Ln_ns194:       .asciz "194 network scan: open ports as text, and what they suggest"
