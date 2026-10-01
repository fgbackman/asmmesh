// udp.s — two finds that don't use Bonjour:
//
//   SSDP (UPnP)  M-SEARCH to 239.255.255.250:1900. Rokus answer "roku:ecp" and
//                are controlled with their External Control Protocol on port
//                8060 (POST /keypress/<key>, /launch/<app>). Everything else
//                that answers (smart TVs, speakers, routers, NAS...) is listed
//                in the Mesh Scanner with the name and model from its
//                description XML.
//   WiZ          {"method":"getPilot"} broadcast to UDP 38899; bulbs answer and
//                take {"method":"setPilot",...} the same way.
//
// Both sockets are non-blocking and read from the 10 Hz UI timer.

.include "macros.inc"

.set SSDP_MAX,   48
.set U_SHIFT,    8
.set U_IP,       0        // 16
.set U_FLAGS,    16       // 1 Roku, 2 described
.set U_DEV,      24
.set U_NAME,     32       // 64
.set U_INFO,     96       // 96
.set U_LOC,      192      // 64

.set AF_INET,    2
.set SOCK_DGRAM, 2
.set F_SETFL,    4
.set O_NONBLOCK, 4
.set SOL_SOCKET, 0xffff
.set SO_BROADCAST, 0x20

.data
.p2align 3
_g_ssdp_fd:     .quad -1
_g_wiz_fd:      .quad -1
.globl _g_ssdp_count
_g_ssdp_count:  .quad 0
.globl _g_ssdp
.zerofill __DATA,__bss,_g_ssdp,12288,4
.zerofill __DATA,__bss,_g_udp_buf,2048,4
.zerofill __DATA,__bss,_g_udp_from,16,4
.zerofill __DATA,__bss,_g_udp_ip,16,4
.zerofill __DATA,__bss,_g_udp_url,256,4
.zerofill __DATA,__bss,_g_udp_tag,32,4
.zerofill __DATA,__bss,_g_udp_msg,256,4
.zerofill __DATA,__bss,_g_udp_name,64,4
.zerofill __DATA,__bss,_g_udp_room,32,4
.zerofill __DATA,__bss,_g_soap,800,4
.zerofill __DATA,__bss,_g_soap_action,128,4
.zerofill __DATA,__bss,_g_kasa_buf,608,4
_g_udp_len:     .quad 0

.section __TEXT,__const
.p2align 3
// sockaddr_in: len, family, port (big-endian), address (big-endian)
Lsa_ssdp:   .byte 16, AF_INET, 0x07, 0x6c, 239, 255, 255, 250
            .quad 0
Lsa_bcast:  .byte 16, AF_INET, 0x96, 0x73, 255, 255, 255, 255
            .quad 0
Lsa_kasa:   .byte 16, AF_INET, 0x27, 0x0F, 255, 255, 255, 255
            .quad 0

.section __DATA,__const
.p2align 3
// Roku keys by action (0 = not a Roku thing)
Lroku_keys:
    .quad 0, Lk_PowerOn, Lk_PowerOff, 0, 0, 0, 0, 0   // NONE ON OFF LEVEL COLOR CT LOCK UNLOCK
    .quad 0, 0, 0, 0, 0, 0, 0, 0                      // RUN LIST HELP PAIR REFRESH BRIGHTER DIMMER CONNECT
    .quad 0, Lk_VolumeUp, Lk_VolumeDown               // VOLUME VOLUP VOLDOWN
    .quad Lk_VolumeMute, Lk_VolumeMute                // MUTE UNMUTE (a toggle on Roku)
    .quad 0, Lk_ChannelUp, Lk_ChannelDown             // CHANNEL CHUP CHDOWN
    .quad 0                                           // INPUT
    .quad Lk_Play, Lk_Play, Lk_Back, Lk_Fwd, Lk_Rev   // PLAY PAUSE STOP FFWD REWIND
    .quad 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0             // APP OPEN CLOSE HEATSET COOLSET TEMPSET TMODE FANSPEED VACSTART VACHOME STATUS
    .quad 0                                           // KEY
Lroku_named:
    .quad Lk_Home, Lk_Back, Lk_Select

.text
.p2align 2

// long _udp_socket(int broadcast) -> fd or -1
_udp_socket:
    ENTER 16
    mov  x19, x0
    mov  w0, #AF_INET
    mov  w1, #SOCK_DGRAM
    mov  w2, #0
    bl   _socket
    sxtw x20, w0
    tbnz x20, #63, Lus_done
    mov  x0, x20
    mov  w1, #F_SETFL
    mov  x9, #O_NONBLOCK
    str  x9, [sp]
    bl   _fcntl
    cbz  x19, Lus_done
    mov  w9, #1
    str  w9, [sp, #96]
    mov  x0, x20
    mov  w1, #SOL_SOCKET
    mov  w2, #SO_BROADCAST
    add  x3, sp, #96
    mov  w4, #4
    bl   _setsockopt
Lus_done:
    mov  x0, x20
    LEAVE 16

// void _udp_init(void)
.globl _udp_init
_udp_init:
    ENTER 0
    mov  x0, #0
    bl   _udp_socket
    ADRL x8, _g_ssdp_fd
    str  x0, [x8]
    mov  x0, #1
    bl   _udp_socket
    ADRL x8, _g_wiz_fd
    str  x0, [x8]
    bl   _udp_discover
    LEAVE 0

// void _udp_send(long fd, const char *text, const void *sockaddr)
_udp_send:
    ENTER 0
    tbnz x0, #63, Lusd_done
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x0, x20
    bl   _strlen
    mov  x2, x0
    mov  x0, x19
    mov  x1, x20
    mov  w3, #0
    mov  x4, x21
    mov  w5, #16
    bl   _sendto
Lusd_done:
    LEAVE 0

// void _udp_discover(void) — ask again
.globl _udp_discover
_udp_discover:
    ENTER 0
    ADRL x8, _g_ssdp_fd
    ldr  x0, [x8]
    ADRL x1, Ls_msearch_roku
    ADRL x2, Lsa_ssdp
    bl   _udp_send
    ADRL x8, _g_ssdp_fd
    ldr  x0, [x8]
    ADRL x1, Ls_msearch_all
    ADRL x2, Lsa_ssdp
    bl   _udp_send
    ADRL x8, _g_wiz_fd
    ldr  x0, [x8]
    ADRL x1, Ls_wiz_get
    ADRL x2, Lsa_bcast
    bl   _udp_send
    ADRL x0, Ls_kasa_info             // TP-Link Kasa plugs, switches and bulbs
    ADRL x1, Lsa_kasa
    bl   _kasa_send
    LEAVE 0

// void _udp_tick(long seconds) — a second round in case the first was missed
.globl _udp_tick
_udp_tick:
    cmp  x0, #4
    b.eq _udp_discover
    cmp  x0, #60
    b.eq _udp_discover
    ret

// void _udp_poll(void) — read whatever has arrived on both sockets
.globl _udp_poll
_udp_poll:
    ENTER 16
    mov  x21, #0
Lup_loop:
    cmp  x21, #24
    b.hs Lup_done
    add  x21, x21, #1
    ADRL x8, _g_ssdp_fd
    ldr  x0, [x8]
    bl   _udp_recv
    cmp  x0, #0
    b.le Lup_wiz
    bl   _ssdp_answer
    b    Lup_loop
Lup_wiz:
    ADRL x8, _g_wiz_fd
    ldr  x0, [x8]
    bl   _udp_recv
    cmp  x0, #0
    b.le Lup_done
    ADRL x8, _g_udp_from              // TP-Link Kasa answers from port 9999
    ldrh w9, [x8, #2]
    mov  w10, #0x0F27                 // 9999 big-endian, read little-endian
    cmp  w9, w10
    b.eq Lup_kasa
    bl   _wiz_answer
    b    Lup_loop
Lup_kasa:
    bl   _kasa_answer
    b    Lup_loop
Lup_done:
    LEAVE 16

// long _udp_recv(long fd) -> bytes into _g_udp_buf (NUL-terminated), sender in _g_udp_ip
_udp_recv:
    ENTER 16
    tbnz x0, #63, Lur_none
    mov  x19, x0
    mov  w9, #16
    str  w9, [sp, #96]
    mov  x0, x19
    ADRL x1, _g_udp_buf
    mov  x2, #2047
    mov  w3, #0
    ADRL x4, _g_udp_from
    add  x5, sp, #96
    bl   _recvfrom
    sxtw x20, w0
    cmp  x20, #0
    b.le Lur_none
    ADRL x8, _g_udp_buf
    strb wzr, [x8, x20]
    ADRL x8, _g_udp_len
    str  x20, [x8]
    ADRL x8, _g_udp_from              // "a.b.c.d"
    ldrb w3, [x8, #4]
    ldrb w4, [x8, #5]
    ldrb w5, [x8, #6]
    ldrb w6, [x8, #7]
    ADRL x0, _g_udp_ip
    mov  x1, #16
    ADRL x2, Lf_ip
    bl   _sfmt
    mov  x0, x20
    LEAVE 16
Lur_none:
    mov  x0, #0
    LEAVE 16

// const char *_hdr(const char *text, const char *name, char *out, size_t max)
//   the value of an HTTP-style header (name without colon, any case), or 0
_hdr:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x0, x20
    bl   _strlen
    mov  x23, x0
Lhd_line:
    mov  x0, x19
    mov  x1, x20
    mov  x2, x23
    bl   _strncasecmp
    cbnz w0, Lhd_next
    ldrb w9, [x19, x23]
    cmp  w9, #':'
    b.ne Lhd_next
    add  x19, x19, x23
    add  x19, x19, #1
Lhd_sp:
    ldrb w9, [x19]
    cmp  w9, #' '
    b.ne Lhd_copy
    add  x19, x19, #1
    b    Lhd_sp
Lhd_copy:
    mov  x10, #0
    sub  x11, x22, #1
Lhd_c:
    cmp  x10, x11
    b.hs Lhd_end
    ldrb w9, [x19, x10]
    cbz  w9, Lhd_end
    cmp  w9, #13
    b.eq Lhd_end
    cmp  w9, #10
    b.eq Lhd_end
    strb w9, [x21, x10]
    add  x10, x10, #1
    b    Lhd_c
Lhd_end:
    strb wzr, [x21, x10]
    mov  x0, x21
    LEAVE 0
Lhd_next:
    mov  x0, x19
    mov  w1, #10
    bl   _strchr
    cbz  x0, Lhd_none
    add  x19, x0, #1
    ldrb w9, [x19]
    cbnz w9, Lhd_line
Lhd_none:
    mov  x0, #0
    LEAVE 0

// long _ssdp_find(const char *ip) -> index or -1
_ssdp_find:
    ENTER 0
    mov  x19, x0
    mov  x20, #0
Lsf_loop:
    ADRL x8, _g_ssdp_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lsf_none
    ADRL x8, _g_ssdp
    add  x0, x8, x20, lsl #U_SHIFT
    mov  x1, x19
    bl   _strcmp
    cbz  w0, Lsf_found
    add  x20, x20, #1
    b    Lsf_loop
Lsf_found:
    mov  x0, x20
    LEAVE 0
Lsf_none:
    mov  x0, #-1
    LEAVE 0

// void _ssdp_answer(void) — one M-SEARCH reply in _g_udp_buf from _g_udp_ip
_ssdp_answer:
    ENTER 32
    ADRL x0, _g_udp_ip
    bl   _ssdp_find
    mov  x20, x0
    tbz  x20, #63, Lsa_have
    ADRL x8, _g_ssdp_count
    ldr  x20, [x8]
    cmp  x20, #SSDP_MAX
    b.hs Lsa_done
    add  x9, x20, #1
    str  x9, [x8]
    ADRL x8, _g_ssdp
    add  x19, x8, x20, lsl #U_SHIFT
    mov  x0, x19
    mov  x1, #(1 << U_SHIFT)
    bl   _bzero
    mov  x9, #-1
    str  x9, [x19, #U_DEV]
    mov  x0, x19
    ADRL x1, _g_udp_ip
    mov  x2, #16
    bl   _strlcpy
    ADRL x0, _g_udp_buf               // until the description arrives: the SERVER line
    ADRL x1, Ls_h_server
    add  x2, x19, #U_INFO
    mov  x3, #96
    bl   _hdr
    ADRL x0, _g_udp_buf
    ADRL x1, Ls_h_location
    add  x2, x19, #U_LOC
    mov  x3, #64
    bl   _hdr
Lsa_have:
    ADRL x8, _g_ssdp
    add  x19, x8, x20, lsl #U_SHIFT
    ADRL x0, _g_udp_buf               // a Roku?
    ADRL x1, Ls_h_st
    ADRL x2, _g_udp_msg
    mov  x3, #64
    bl   _hdr
    cbz  x0, Lsa_describe
    ADRL x1, Ls_roku_ecp
    bl   _strcmp
    cbnz w0, Lsa_describe
    ldr  x9, [x19, #U_FLAGS]
    tbnz x9, #0, Lsa_done
    orr  x9, x9, #1
    str  x9, [x19, #U_FLAGS]
    mov  x0, #'r'                     // ask it who it is
    mov  x1, x20
    bl   _udp_tagf
    mov  x4, x0
    ADRL x0, _g_udp_url
    mov  x1, #256
    ADRL x2, Lf_roku_info
    mov  x3, x19
    str  x4, [sp, #96]
    bl   _sfmt
    ADRL x0, Ls_GET
    ADRL x1, _g_udp_url
    mov  x2, #0
    mov  x3, #0
    ldr  x4, [sp, #96]
    bl   _http
    LEAVE 32
Lsa_describe:
    ldr  x9, [x19, #U_FLAGS]
    tbnz x9, #1, Lsa_done
    add  x9, x19, #U_LOC
    ldrb w9, [x9]
    cbz  w9, Lsa_done
    ldr  x9, [x19, #U_FLAGS]
    orr  x9, x9, #2
    str  x9, [x19, #U_FLAGS]
    mov  x0, #'d'
    mov  x1, x20
    bl   _udp_tagf
    mov  x4, x0
    ADRL x0, Ls_GET
    add  x1, x19, #U_LOC
    mov  x2, #0
    mov  x3, #0
    bl   _http
Lsa_done:
    LEAVE 32

// const char *_udp_tagf(char letter, long n) -> "u<letter><n>"
_udp_tagf:
    ENTER 0
    mov  x4, x1
    mov  x3, x0
    ADRL x0, _g_udp_tag
    mov  x1, #32
    ADRL x2, Lf_tag
    bl   _sfmt
    ADRL x0, _g_udp_tag
    LEAVE 0

// long _xml_get(const char *xml, const char *tag, char *out, size_t max) -> 1 if found
//   the text of the first <tag>...</tag>
_xml_get:
    ENTER 48                          // [96] "<tag>"
    mov  x19, x0
    mov  x21, x2
    mov  x22, x3
    strb wzr, [x21]
    cbz  x19, Lxg_no
    mov  x3, x1
    add  x0, sp, #96
    mov  x1, #48
    ADRL x2, Lf_open_tag
    bl   _sfmt
    mov  x0, x19
    add  x1, sp, #96
    bl   _strstr
    cbz  x0, Lxg_no
    mov  x20, x0
    add  x0, sp, #96
    bl   _strlen
    add  x20, x20, x0
    mov  x10, #0
    sub  x11, x22, #1
Lxg_c:
    cmp  x10, x11
    b.hs Lxg_end
    ldrb w9, [x20, x10]
    cbz  w9, Lxg_end
    cmp  w9, #'<'
    b.eq Lxg_end
    strb w9, [x21, x10]
    add  x10, x10, #1
    b    Lxg_c
Lxg_end:
    strb wzr, [x21, x10]
    mov  x0, x21
    bl   _utf8_fix
    mov  x0, #1
    LEAVE 48
Lxg_no:
    mov  x0, #0
    LEAVE 48

// void _udp_response(const char *tag, id json, long status, NSError *err, NSData *raw)
.globl _udp_response
_udp_response:
    ENTER 32
    mov  x19, x0
    mov  x22, x4
    ldrb w9, [x19, #1]
    cmp  w9, #'c'                     // a command to a Roku or Sonos
    b.eq Lurs_cmd
    cbnz x3, Lurs_done
    cmp  x2, #300
    b.hs Lurs_done
    cbz  x22, Lurs_done
    bl   _tag_num
    mov  x20, x0
    ADRL x8, _g_ssdp_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lurs_done
    ADRL x8, _g_ssdp
    add  x21, x8, x20, lsl #U_SHIFT
    // the body as text
    mov  x0, x22
    MSG0 Ls_length
    mov  x23, x0
    add  x0, x23, #1
    bl   _malloc
    cbz  x0, Lurs_done
    mov  x24, x0
    mov  x0, x22
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x24
    mov  x2, x23
    bl   _memcpy
    strb wzr, [x24, x23]
    ldrb w9, [x19, #1]
    cmp  w9, #'r'
    b.eq Lurs_roku
    // a UPnP description: friendlyName, manufacturer modelName
    mov  x0, x24
    ADRL x1, Ls_x_friendly
    add  x2, x21, #U_NAME
    mov  x3, #64
    bl   _xml_get
    mov  x0, x24
    ADRL x1, Ls_x_manufacturer
    ADRL x2, _g_udp_msg
    mov  x3, #48
    bl   _xml_get
    cbz  x0, Lurs_free
    add  x0, x21, #U_INFO
    ADRL x1, _g_udp_msg
    mov  x2, #96
    bl   _strlcpy
    mov  x0, x24
    ADRL x1, Ls_x_model
    ADRL x2, _g_udp_msg
    mov  x3, #48
    bl   _xml_get
    cbz  x0, Lurs_free
    add  x0, x21, #U_INFO
    ADRL x1, Ls_space
    mov  x2, #96
    bl   _strlcat
    add  x0, x21, #U_INFO
    ADRL x1, _g_udp_msg
    mov  x2, #96
    bl   _strlcat
    mov  x0, x24                      // a Sonos speaker: control it too
    ADRL x1, Ls_sonos_inc
    bl   _strstr
    cbz  x0, Lurs_free
    mov  x0, x24
    ADRL x1, Ls_x_room
    ADRL x2, _g_udp_room
    mov  x3, #32
    bl   _xml_get
    cbz  x0, Lurs_free
    ADRL x0, _g_udp_name
    mov  x1, #64
    ADRL x2, Lf_sonos_name
    ADRL x3, _g_udp_room
    bl   _sfmt
    ADRL x0, _g_udp_url
    mov  x1, #256
    ADRL x2, Lf_sonos_id
    mov  x3, x21                      // U_IP is at +0
    bl   _sfmt
    mov  x0, #K_SONOS
    ADRL x1, _g_udp_url
    ADRL x2, _g_udp_name
    MOVI x3, (CAP_ON | CAP_VOLUME | CAP_MUTE | CAP_MEDIA | CAP_STATUS)
    bl   _dev_add
    tbnz x0, #63, Lurs_free
    str  x0, [x21, #U_DEV]
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    add  x0, x8, #D_ROOM
    ADRL x1, _g_udp_room
    mov  x2, #D_ROOM_MAX
    bl   _strlcpy
    ldr  x9, [x21, #U_FLAGS]
    tbnz x9, #3, Lurs_sonos_quiet
    orr  x9, x9, #8
    str  x9, [x21, #U_FLAGS]
    ADRL x1, _g_udp_name
    mov  x2, x1
    ADRL x0, Ls_sonos_found
    bl   _home_say
Lurs_sonos_quiet:
    bl   _ui_lists_changed
    b    Lurs_free

Lurs_roku:                            // /query/device-info
    mov  x0, x24
    ADRL x1, Ls_x_user_name
    add  x2, x21, #U_NAME
    mov  x3, #64
    bl   _xml_get
    add  x9, x21, #U_NAME
    ldrb w9, [x9]
    cbnz w9, Lurs_rk_model
    mov  x0, x24
    ADRL x1, Ls_x_friendly_dev
    add  x2, x21, #U_NAME
    mov  x3, #64
    bl   _xml_get
    add  x9, x21, #U_NAME
    ldrb w9, [x9]
    cbnz w9, Lurs_rk_model
    add  x0, x21, #U_NAME
    ADRL x1, Ls_roku
    mov  x2, #64
    bl   _strlcpy
Lurs_rk_model:
    mov  x0, x24
    ADRL x1, Ls_x_model_name
    add  x2, x21, #U_INFO
    mov  x3, #96
    bl   _xml_get
    MOVI x23, (CAP_KEYS | CAP_APPS | CAP_MEDIA | CAP_VOLUME | CAP_MUTE)
    mov  x0, x24                      // a Roku TV also has power, channels and inputs
    ADRL x1, Ls_x_is_tv
    ADRL x2, _g_udp_msg
    mov  x3, #16
    bl   _xml_get
    ADRL x0, _g_udp_msg
    ADRL x1, Ls_true
    bl   _strcmp
    cbnz w0, Lurs_rk_add
    MOVI x9, (CAP_TV | CAP_ON | CAP_CHANNEL | CAP_INPUT)
    orr  x23, x23, x9
Lurs_rk_add:
    ADRL x0, _g_udp_url               // id: "ip:8060"
    mov  x1, #256
    ADRL x2, Lf_roku_id
    mov  x3, x21
    bl   _sfmt
    mov  x0, #K_ROKU
    ADRL x1, _g_udp_url
    add  x2, x21, #U_NAME
    mov  x3, x23
    bl   _dev_add
    tbnz x0, #63, Lurs_free
    str  x0, [x21, #U_DEV]
    ldr  x9, [x21, #U_FLAGS]
    tbnz x9, #2, Lurs_rk_quiet
    orr  x9, x9, #4
    str  x9, [x21, #U_FLAGS]
    add  x1, x21, #U_NAME
    mov  x2, x1
    ADRL x0, Ls_roku_found
    bl   _home_say
Lurs_rk_quiet:
    bl   _ui_lists_changed
Lurs_free:
    mov  x0, x24
    bl   _free
Lurs_done:
    LEAVE 32

Lurs_cmd:                             // only failures are worth a line
    mov  x20, x2
    mov  x21, x3
    bl   _tag_num
    ADRL x8, _g_dev_count
    ldr  x9, [x8]
    cmp  x0, x9
    b.hs Lurs_cmd_done
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    add  x23, x8, #D_NAME
    cbnz x21, Lurs_cmd_net
    cmp  x20, #300
    b.lo Lurs_cmd_done
    mov  x1, x23
    mov  x2, x20
    ADRL x0, Ls_cmd_http
    bl   _home_say
    b    Lurs_cmd_done
Lurs_cmd_net:
    mov  x0, x21
    bl   _err_cstr
    mov  x2, x0
    mov  x1, x23
    ADRL x0, Ls_cmd_net
    bl   _home_say
Lurs_cmd_done:
    LEAVE 32

// long _roku_set(long idx, long action, long value)
.globl _roku_set
_roku_set:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    cmp  x20, #A_APP
    b.eq Lrk_app
    cmp  x20, #A_KEY
    b.eq Lrk_named
    cmp  x20, #A_INPUT
    b.eq Lrk_input
    cmp  x20, #A_CHANNEL
    b.eq Lrk_channel
    cmp  x20, #A_LAST
    b.hi Lrk_cant
    ADRL x8, Lroku_keys
    ldr  x3, [x8, x20, lsl #3]
    cbz  x3, Lrk_cant
    ADRL x2, Lf_roku_key
    b    Lrk_send
Lrk_named:
    cmp  x21, #2
    b.hi Lrk_cant
    ADRL x8, Lroku_named
    ldr  x3, [x8, x21, lsl #3]
    ADRL x2, Lf_roku_key
    b    Lrk_send
Lrk_app:
    mov  x0, x21
    mov  x1, #4                       // Roku channel id
    bl   _app_field
    mov  x3, x0
    ADRL x2, Lf_roku_launch
    b    Lrk_send
Lrk_input:
    ADRL x3, Lk_InputTuner
    cbz  x21, Lrk_input_key
    cmp  x21, #4
    b.hi Lrk_cant
    ADRL x0, _g_udp_name
    mov  x1, #64
    ADRL x2, Lf_hdmi_key
    mov  x3, x21
    bl   _sfmt
    ADRL x3, _g_udp_name
Lrk_input_key:
    ADRL x2, Lf_roku_key
    b    Lrk_send
Lrk_channel:                          // Roku TV: the tuner app with a channel
    mov  x3, x21
    ADRL x2, Lf_roku_channel
Lrk_send:
    mov  x4, x3
    add  x3, x22, #D_ID
    ADRL x0, _g_udp_url
    mov  x1, #256
    bl   _sfmt
    mov  x0, #'c'
    mov  x1, x19
    bl   _udp_tagf
    mov  x4, x0
    ADRL x0, Ls_POST
    ADRL x1, _g_udp_url
    mov  x2, #0
    mov  x3, #0
    bl   _http
    cmp  x20, #A_ON
    b.eq Lrk_on
    cmp  x20, #A_OFF
    b.ne Lrk_sent
    mov  x0, x19
    mov  x1, #0
    mov  x2, #-1
    bl   _dev_state
    b    Lrk_sent
Lrk_on:
    mov  x0, x19
    mov  x1, #1
    mov  x2, #-1
    bl   _dev_state
Lrk_sent:
    mov  x0, #1
    LEAVE 16
Lrk_cant:
    mov  x0, #0
    LEAVE 16

// ===========================================================================
// WiZ
// ===========================================================================

// void _wiz_answer(void) — {"method":"getPilot","result":{"mac":"...","state":true,"dimming":80}}
_wiz_answer:
    ENTER 32
    ADRL x0, _g_udp_buf
    bl   _strlen
    mov  x1, x0
    ADRL x0, _g_udp_buf
    bl   _json_parse
    mov  x19, x0
    ADRL x1, Lj_method
    bl   _jget
    bl   _jstr
    cbz  x0, Lwa_done
    ADRL x1, Lj_getPilot
    bl   _strcmp
    cbnz w0, Lwa_done
    mov  x0, x19
    ADRL x1, Lj_result
    bl   _jget
    mov  x20, x0
    cbz  x20, Lwa_done
    ADRL x1, Lj_mac
    bl   _jget
    bl   _jstr
    cbz  x0, Lwa_name_plain
    mov  x21, x0
    bl   _strlen
    cmp  x0, #4
    b.lo Lwa_name_plain
    add  x3, x21, x0
    sub  x3, x3, #4
    ADRL x0, _g_udp_name
    mov  x1, #64
    ADRL x2, Lf_wiz_name
    bl   _sfmt
    b    Lwa_add
Lwa_name_plain:
    ADRL x0, _g_udp_name
    ADRL x1, Ls_wiz
    mov  x2, #64
    bl   _strlcpy
Lwa_add:
    mov  x0, #K_WIZ
    ADRL x1, _g_udp_ip
    ADRL x2, _g_udp_name
    mov  x3, #(CAP_ON | CAP_LEVEL | CAP_COLOR | CAP_CT)
    bl   _dev_find_wiz
    mov  x21, x0
    tbnz x21, #63, Lwa_done
    mov  x0, x20
    ADRL x1, Lj_state
    bl   _jget
    bl   _jint
    mov  x22, x0
    mov  x0, x20
    ADRL x1, Lj_dimming
    bl   _jget
    mov  x2, #-1
    cbz  x0, Lwa_state
    bl   _jint
    mov  x2, x0
Lwa_state:
    mov  x0, x21
    mov  x1, x22
    bl   _dev_state
Lwa_done:
    LEAVE 32

// long _dev_find_wiz(kind, ip, name, caps) — add a new bulb (announced once); keep an old one's name
_dev_find_wiz:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    bl   _dev_find
    tbz  x0, #63, Ldw_done
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    mov  x3, x22
    bl   _dev_add
    tbnz x0, #63, Ldw_done
    mov  x23, x0
    mov  x1, x21
    ADRL x0, Ls_wiz_found
    bl   _home_say
    bl   _ui_lists_changed
    mov  x0, x23
Ldw_done:
    LEAVE 0

// long _wiz_set(long idx, long action, long value)
.globl _wiz_set
_wiz_set:
    ENTER 48                          // [96] sockaddr
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ADRL x2, Lw_on
    cmp  x20, #A_ON
    b.eq Lwz_fixed
    ADRL x2, Lw_off
    cmp  x20, #A_OFF
    b.eq Lwz_fixed
    cmp  x20, #A_LEVEL
    b.eq Lwz_level
    cmp  x20, #A_BRIGHTER
    b.eq Lwz_level
    cmp  x20, #A_DIMMER
    b.eq Lwz_level
    cmp  x20, #A_CT
    b.eq Lwz_ct
    cmp  x20, #A_COLOR
    b.ne Lwz_cant
    mov  x0, x21
    bl   _hue_to_rgb
    lsr  x3, x0, #16
    ubfx x4, x0, #8, #8
    and  x5, x0, #0xff
    ADRL x2, Lw_rgb
    b    Lwz_fmt
Lwz_ct:                               // WiZ: 2200..6500 K
    mov  x3, x21
    mov  x9, #2200
    cmp  x3, x9
    csel x3, x9, x3, lo
    mov  x9, #6500
    cmp  x3, x9
    csel x3, x9, x3, hi
    ADRL x2, Lw_temp
    b    Lwz_fmt
Lwz_level:
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _rel_level
    mov  x21, x0
    mov  x20, #A_LEVEL
    cmp  x0, #10                      // WiZ dims 10..100
    mov  x9, #10
    csel x3, x9, x0, lo
    ADRL x2, Lw_dim
Lwz_fmt:
    ADRL x0, _g_udp_msg
    mov  x1, #256
    bl   _sfmt
    b    Lwz_send
Lwz_fixed:
    ADRL x0, _g_udp_msg
    mov  x1, x2
    mov  x2, #256
    bl   _strlcpy
Lwz_send:
    add  x0, x22, #D_ID               // the bulb's address
    bl   _inet_addr
    str  xzr, [sp, #96]
    str  xzr, [sp, #104]
    mov  w9, #16
    strb w9, [sp, #96]
    mov  w9, #AF_INET
    strb w9, [sp, #97]
    mov  w9, #0x96                    // 38899 big-endian
    strb w9, [sp, #98]
    mov  w9, #0x73
    strb w9, [sp, #99]
    str  w0, [sp, #100]
    ADRL x8, _g_wiz_fd
    ldr  x0, [x8]
    ADRL x1, _g_udp_msg
    add  x2, sp, #96
    bl   _udp_send
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 48
Lwz_cant:
    mov  x0, #0
    LEAVE 48


// ===========================================================================
// For the scanner
// ===========================================================================

// char *_ssdp_cell(long i, char column, char *buf)
.globl _ssdp_cell
_ssdp_cell:
    ENTER 0
    mov  x20, x2
    ADRL x8, _g_ssdp
    add  x19, x8, x0, lsl #U_SHIFT
    strb wzr, [x20]
    cmp  w1, #'n'
    b.eq Lsc_name
    cmp  w1, #'k'
    b.eq Lsc_kind
    cmp  w1, #'s'
    b.eq Lsc_sig
    cmp  w1, #'l'
    b.eq Lsc_where
    add  x1, x19, #U_INFO
    b    Lsc_copy
Lsc_name:
    add  x1, x19, #U_NAME
    ldrb w9, [x1]
    cbnz w9, Lsc_copy
Lsc_where:
    add  x1, x19, #U_IP
    b    Lsc_copy
Lsc_kind:
    ldr  x9, [x19, #U_FLAGS]
    ADRL x1, Ls_k_upnp
    tbz  x9, #0, Lsc_copy
    ADRL x1, Ls_roku
    b    Lsc_copy
Lsc_sig:
    ADRL x1, Ls_wifi
Lsc_copy:
    mov  x0, x20
    mov  x2, #120
    bl   _strlcpy
    mov  x0, x20
    LEAVE 0

// char *_ssdp_details(long i, char *buf, size_t max)
.globl _ssdp_details
_ssdp_details:
    ENTER 0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_ssdp
    add  x19, x8, x0, lsl #U_SHIFT
    add  x3, x19, #U_NAME
    ldrb w9, [x3]
    cbnz w9, Lsd_named
    add  x3, x19, #U_IP
Lsd_named:
    add  x4, x19, #U_INFO
    add  x5, x19, #U_IP
    ldr  x9, [x19, #U_FLAGS]
    ADRL x6, Ls_hint_upnp
    tbz  x9, #0, Lsd_fmt
    ADRL x6, Ls_hint_roku
Lsd_fmt:
    mov  x0, x20
    mov  x1, x21
    ADRL x2, Lf_ssdp_details
    bl   _sfmt
    mov  x0, x20
    LEAVE 0

// void _ssdp_open_web(long i) — its address in the browser (routers, NAS, printers...)
.globl _ssdp_open_web
_ssdp_open_web:
    ENTER 0
    ADRL x8, _g_ssdp
    add  x19, x8, x0, lsl #U_SHIFT
    ldr  x9, [x19, #U_FLAGS]
    tbnz x9, #0, Losw_roku
    ADRL x0, _g_udp_url
    mov  x1, #256
    ADRL x2, Lf_web_ip
    add  x3, x19, #U_IP
    bl   _sfmt
    ADRL x0, _g_udp_url
    bl   _open_url
    LEAVE 0
Losw_roku:
    add  x1, x19, #U_NAME
    ADRL x0, Ls_roku_ready
    bl   _scan_say
    LEAVE 0


// ===========================================================================
// Sonos: UPnP SOAP on port 1400
// ===========================================================================

// long _sonos_set(long idx, long action, long value)
.globl _sonos_set
_sonos_set:
    ENTER 48                          // [96] action [104] service [112] extra fmt [120] extra value
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ADRL x9, Ls_avt
    str  x9, [sp, #104]
    ADRL x9, Ls_empty
    str  x9, [sp, #112]
    str  xzr, [sp, #120]
    ADRL x9, Lso_play
    cmp  x20, #A_ON
    b.eq Lso_speed
    cmp  x20, #A_PLAY
    b.eq Lso_speed
    ADRL x9, Lso_pause
    cmp  x20, #A_OFF
    b.eq Lso_go
    cmp  x20, #A_PAUSE
    b.eq Lso_go
    ADRL x9, Lso_stop
    cmp  x20, #A_STOP
    b.eq Lso_go
    ADRL x9, Lso_next
    cmp  x20, #A_FFWD
    b.eq Lso_go
    ADRL x9, Lso_prev
    cmp  x20, #A_REWIND
    b.eq Lso_go
    ADRL x10, Ls_rc                   // the rest is RenderingControl
    str  x10, [sp, #104]
    ADRL x9, Lso_setvol
    ADRL x10, Lx_vol
    cmp  x20, #A_VOLUME
    b.eq Lso_arg
    ADRL x9, Lso_relvol
    ADRL x10, Lx_rel
    mov  x21, #5
    cmp  x20, #A_VOLUP
    b.eq Lso_arg
    mov  x21, #-5
    cmp  x20, #A_VOLDOWN
    b.eq Lso_arg
    ADRL x9, Lso_mute
    ADRL x10, Lx_mute
    mov  x21, #1
    cmp  x20, #A_MUTE
    b.eq Lso_arg
    mov  x21, #0
    cmp  x20, #A_UNMUTE
    b.eq Lso_arg
    mov  x0, #0
    LEAVE 48
Lso_speed:
    ADRL x10, Lx_speed
    str  x10, [sp, #112]
    b    Lso_go
Lso_arg:
    str  x10, [sp, #112]
    str  x21, [sp, #120]
Lso_go:
    str  x9, [sp, #96]
    ADRL x0, _g_udp_msg               // the argument elements
    mov  x1, #256
    ldr  x2, [sp, #112]
    ldr  x3, [sp, #120]
    bl   _sfmt
    ADRL x0, _g_soap                  // the envelope
    mov  x1, #800
    ADRL x2, Lf_soap
    ldr  x3, [sp, #96]
    ldr  x4, [sp, #104]
    ADRL x5, _g_udp_msg
    ldr  x6, [sp, #96]
    bl   _sfmt
    ADRL x0, _g_soap_action           // "urn:schemas-upnp-org:service:AVTransport:1#Play"
    mov  x1, #128
    ADRL x2, Lf_soap_action
    ldr  x3, [sp, #104]
    ldr  x4, [sp, #96]
    bl   _sfmt
    ADRL x0, _g_udp_url
    mov  x1, #256
    ADRL x2, Lf_sonos_ctl
    add  x3, x22, #D_ID
    ldr  x4, [sp, #104]
    bl   _sfmt
    mov  x0, #'c'
    mov  x1, x19
    bl   _udp_tagf
    mov  x4, x0
    ADRL x0, Ls_POST
    ADRL x1, _g_udp_url
    ADRL x2, _g_soap
    mov  x3, #0
    ADRL x5, Ls_soapaction
    ADRL x6, _g_soap_action
    bl   _http2
    cmp  x20, #A_ON                   // playing counts as on
    b.eq Lso_on
    cmp  x20, #A_PLAY
    b.eq Lso_on
    cmp  x20, #A_OFF
    b.eq Lso_off
    cmp  x20, #A_PAUSE
    b.eq Lso_off
    cmp  x20, #A_STOP
    b.ne Lso_sent
Lso_off:
    mov  x0, x19
    mov  x1, #0
    mov  x2, #-1
    bl   _dev_state
    b    Lso_sent
Lso_on:
    mov  x0, x19
    mov  x1, #1
    mov  x2, #-1
    bl   _dev_state
Lso_sent:
    mov  x0, #1
    LEAVE 48

// ===========================================================================
// TP-Link Kasa: JSON over UDP 9999, "encrypted" with a rolling XOR (key 171)
// ===========================================================================

// void _kasa_cipher(uint8 *buf, size_t n, int decrypt)
.globl _kasa_cipher
_kasa_cipher:
    mov  w9, #171
Lkc_loop:
    cbz  x1, Lkc_done
    ldrb w10, [x0]
    eor  w11, w10, w9
    strb w11, [x0], #1
    cmp  w2, #0
    csel w9, w10, w11, ne             // the key is always the encrypted byte
    sub  x1, x1, #1
    b    Lkc_loop
Lkc_done:
    ret

// void _kasa_send(const char *json, const void *sockaddr)
_kasa_send:
    ENTER 16
    mov  x20, x1
    mov  x1, x0
    ADRL x0, _g_kasa_buf
    mov  x2, #600
    bl   _strlcpy
    mov  x21, x0                      // length
    cmp  x21, #599
    b.hi Lks_done
    ADRL x0, _g_kasa_buf
    mov  x1, x21
    mov  w2, #0
    bl   _kasa_cipher
    ADRL x8, _g_wiz_fd
    ldr  x0, [x8]
    tbnz x0, #63, Lks_done
    ADRL x1, _g_kasa_buf
    mov  x2, x21
    mov  w3, #0
    mov  x4, x20
    mov  w5, #16
    bl   _sendto
Lks_done:
    LEAVE 16

// void _kasa_answer(void) — a reply in _g_udp_buf (encrypted), from _g_udp_ip
_kasa_answer:
    ENTER 32
    ADRL x0, _g_udp_buf
    bl   _strlen                      // the cipher can produce 0 bytes: use the received length
    ADRL x8, _g_udp_len
    ldr  x19, [x8]
    ADRL x0, _g_udp_buf
    mov  x1, x19
    mov  w2, #1
    bl   _kasa_cipher
    ADRL x0, _g_udp_buf
    mov  x1, x19
    bl   _json_parse
    ADRL x1, Lk_system
    bl   _jget
    ADRL x1, Lk_sysinfo
    bl   _jget
    mov  x20, x0
    cbz  x20, Lka_done                // a reply to a command: nothing to do
    ADRL x1, Lk_alias
    bl   _jget
    bl   _jstr
    mov  x21, x0
    cbz  x21, Lka_done
    mov  x22, #1                      // kind: 1 plug, 2 dimmer, 3 bulb
    mov  x23, #CAP_ON
    mov  x0, x20
    ADRL x1, Lk_light_state
    bl   _jget
    cbnz x0, Lka_bulb
    mov  x0, x20
    ADRL x1, Lk_brightness
    bl   _jget
    cbz  x0, Lka_add
    mov  x22, #2
    mov  x23, #(CAP_ON | CAP_LEVEL)
    b    Lka_add
Lka_bulb:
    mov  x22, #3
    mov  x23, #(CAP_ON | CAP_LEVEL)
    mov  x0, x20
    ADRL x1, Lk_is_color
    bl   _jget
    bl   _jint
    cbz  x0, Lka_ct
    orr  x23, x23, #CAP_COLOR
Lka_ct:
    mov  x0, x20
    ADRL x1, Lk_is_ct
    bl   _jget
    bl   _jint
    cbz  x0, Lka_add
    orr  x23, x23, #CAP_CT
Lka_add:
    mov  x0, #K_KASA
    ADRL x1, _g_udp_ip
    bl   _dev_find
    mov  x24, x0
    mov  x0, #K_KASA
    ADRL x1, _g_udp_ip
    mov  x2, x21
    mov  x3, x23
    bl   _dev_add
    tbnz x0, #63, Lka_done
    ADRL x8, _g_devs
    add  x8, x8, x0, lsl #DEV_SHIFT
    str  x22, [x8, #D_AUX]
    mov  x21, x0
    mov  x0, x20                      // on or off now
    ADRL x1, Lk_relay
    bl   _jget
    cbz  x0, Lka_bulb_state
    bl   _jint
    mov  x1, x0
    mov  x0, x21
    mov  x2, #-1
    bl   _dev_state
    b    Lka_new
Lka_bulb_state:
    mov  x0, x20
    ADRL x1, Lk_light_state
    bl   _jget
    ADRL x1, Lk_on_off
    bl   _jget
    cbz  x0, Lka_new
    bl   _jint
    mov  x1, x0
    mov  x0, x21
    mov  x2, #-1
    bl   _dev_state
Lka_new:
    tbz  x24, #63, Lka_done           // known already: no announcement
    ADRL x8, _g_devs
    add  x8, x8, x21, lsl #DEV_SHIFT
    add  x1, x8, #D_NAME
    ADRL x0, Ls_kasa_found
    bl   _home_say
    bl   _ui_lists_changed
Lka_done:
    LEAVE 32

// long _kasa_set(long idx, long action, long value)
.globl _kasa_set
_kasa_set:
    ENTER 48                          // [96] sockaddr
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    ADRL x8, _g_devs
    add  x22, x8, x19, lsl #DEV_SHIFT
    ldr  x23, [x22, #D_AUX]           // 1 plug 2 dimmer 3 bulb
    cmp  x20, #A_BRIGHTER
    b.eq Lkx_rel
    cmp  x20, #A_DIMMER
    b.ne Lkx_pick
Lkx_rel:
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _rel_level
    mov  x21, x0
    mov  x20, #A_LEVEL
Lkx_pick:
    cmp  x23, #3
    b.eq Lkx_bulb
    mov  x3, #1                       // plugs and dimmers: the relay, then the dimmer
    ADRL x2, Lk_relay_fmt
    cmp  x20, #A_ON
    b.eq Lkx_fmt
    mov  x3, #0
    cmp  x20, #A_OFF
    b.eq Lkx_fmt
    cmp  x23, #2
    b.ne Lkx_cant
    cmp  x20, #A_LEVEL
    b.ne Lkx_cant
    mov  x3, x21
    ADRL x2, Lk_dim_fmt
    b    Lkx_fmt
Lkx_bulb:
    mov  x3, #1
    ADRL x2, Lk_bulb_onoff
    cmp  x20, #A_ON
    b.eq Lkx_fmt
    mov  x3, #0
    cmp  x20, #A_OFF
    b.eq Lkx_fmt
    mov  x3, x21
    ADRL x2, Lk_bulb_bri
    cmp  x20, #A_LEVEL
    b.eq Lkx_fmt
    ADRL x2, Lk_bulb_hue
    cmp  x20, #A_COLOR
    b.eq Lkx_fmt
    ADRL x2, Lk_bulb_ct
    cmp  x20, #A_CT
    b.ne Lkx_cant
    mov  x9, #2500                    // Kasa: 2500..9000 K
    cmp  x3, x9
    csel x3, x9, x3, lo
    mov  x9, #9000
    cmp  x3, x9
    csel x3, x9, x3, hi
Lkx_fmt:
    ADRL x0, _g_udp_msg
    mov  x1, #256
    bl   _sfmt
    add  x0, x22, #D_ID
    bl   _inet_addr
    str  xzr, [sp, #96]
    str  xzr, [sp, #104]
    mov  w9, #16
    strb w9, [sp, #96]
    mov  w9, #AF_INET
    strb w9, [sp, #97]
    mov  w9, #0x27                    // 9999 big-endian
    strb w9, [sp, #98]
    mov  w9, #0x0F
    strb w9, [sp, #99]
    str  w0, [sp, #100]
    ADRL x0, _g_udp_msg
    add  x1, sp, #96
    bl   _kasa_send
    mov  x0, x19
    mov  x1, x20
    mov  x2, x21
    bl   _believe
    mov  x0, #1
    LEAVE 48
Lkx_cant:
    mov  x0, #0
    LEAVE 48

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_length:        .asciz "length"
Ls_bytes:         .asciz "bytes"
Ls_GET:           .asciz "GET"
Ls_POST:          .asciz "POST"
Ls_msearch_roku:  .asciz "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: roku:ecp\r\n\r\n"
Ls_msearch_all:   .asciz "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: upnp:rootdevice\r\n\r\n"
Ls_wiz_get:       .asciz "{\"method\":\"getPilot\",\"params\":{}}"
Lf_ip:            .asciz "%d.%d.%d.%d"
Lf_tag:           .asciz "u%c%ld"
Lf_open_tag:      .asciz "<%s>"
Ls_h_server:      .asciz "server"
Ls_h_location:    .asciz "location"
Ls_h_st:          .asciz "st"
Ls_roku_ecp:      .asciz "roku:ecp"
Ls_x_friendly:    .asciz "friendlyName"
Ls_x_manufacturer: .asciz "manufacturer"
Ls_x_model:       .asciz "modelName"
Ls_x_user_name:   .asciz "user-device-name"
Ls_x_friendly_dev: .asciz "friendly-device-name"
Ls_x_model_name:  .asciz "friendly-model-name"
Ls_x_is_tv:       .asciz "is-tv"
Ls_true:          .asciz "true"
Ls_space:         .asciz " "
Ls_roku:          .asciz "Roku"
Lf_roku_info:     .asciz "http://%s:8060/query/device-info"
Lf_roku_id:       .asciz "%s:8060"
Lf_roku_key:      .asciz "http://%s/keypress/%s"
Lf_roku_launch:   .asciz "http://%s/launch/%s"
Lf_roku_channel:  .asciz "http://%s/launch/tvinput.dtv?ch=%ld"
Lf_hdmi_key:      .asciz "InputHDMI%ld"
Lk_PowerOn:       .asciz "PowerOn"
Lk_PowerOff:      .asciz "PowerOff"
Lk_VolumeUp:      .asciz "VolumeUp"
Lk_VolumeDown:    .asciz "VolumeDown"
Lk_VolumeMute:    .asciz "VolumeMute"
Lk_ChannelUp:     .asciz "ChannelUp"
Lk_ChannelDown:   .asciz "ChannelDown"
Lk_InputTuner:    .asciz "InputTuner"
Lk_Play:          .asciz "Play"
Lk_Back:          .asciz "Back"
Lk_Fwd:           .asciz "Fwd"
Lk_Rev:           .asciz "Rev"
Lk_Home:          .asciz "Home"
Lk_Select:        .asciz "Select"
Ls_roku_found:    .asciz "\302\267 Found Roku \342\200\234%s\342\200\235. Try \342\200\234%s open Netflix\342\200\235, \342\200\234pause\342\200\235 or \342\200\234press home\342\200\235."
Lj_method:        .asciz "method"
Lj_getPilot:      .asciz "getPilot"
Lj_result:        .asciz "result"
Lj_mac:           .asciz "mac"
Lj_state:         .asciz "state"
Lj_dimming:       .asciz "dimming"
Lf_wiz_name:      .asciz "WiZ light %s"
Ls_wiz:           .asciz "WiZ light"
Ls_wiz_found:     .asciz "\302\267 Found %s on your Wi-Fi."
Lw_on:            .asciz "{\"id\":1,\"method\":\"setPilot\",\"params\":{\"state\":true}}"
Lw_off:           .asciz "{\"id\":1,\"method\":\"setPilot\",\"params\":{\"state\":false}}"
Lw_dim:           .asciz "{\"id\":1,\"method\":\"setPilot\",\"params\":{\"state\":true,\"dimming\":%ld}}"
Lw_temp:          .asciz "{\"id\":1,\"method\":\"setPilot\",\"params\":{\"state\":true,\"temp\":%ld}}"
Lw_rgb:           .asciz "{\"id\":1,\"method\":\"setPilot\",\"params\":{\"state\":true,\"r\":%ld,\"g\":%ld,\"b\":%ld}}"
Ls_k_upnp:        .asciz "Network (UPnP)"
Ls_wifi:          .asciz "Wi-Fi"
Lf_web_ip:        .asciz "http://%s/"
Lf_ssdp_details:  .asciz "%s \342\200\224 %s at %s\n%s"
Ls_hint_upnp:     .asciz "Set Up opens its web page, if it has one."
Ls_hint_roku:     .asciz "asmmesh controls it directly: \342\200\234Roku open YouTube\342\200\235, \342\200\234pause\342\200\235, \342\200\234press home\342\200\235."
Ls_roku_ready:    .asciz "\302\267 %s is already under asmmesh's control \342\200\224 nothing to pair. Try \342\200\234Roku press home\342\200\235."
Ls_cmd_http:      .asciz "\302\267 %s refused that (HTTP %ld)."
Ls_cmd_net:       .asciz "\302\267 %s didn't answer: %s"
Ls_empty:         .asciz ""
Ls_sonos_inc:     .asciz "Sonos"
Ls_x_room:        .asciz "roomName"
Lf_sonos_name:    .asciz "%s Sonos"
Lf_sonos_id:      .asciz "%s:1400"
Ls_sonos_found:   .asciz "\302\267 Found \342\200\234%s\342\200\235. Try \342\200\234%s volume 20\342\200\235, \342\200\234pause\342\200\235 or \342\200\234next\342\200\235."
Ls_avt:           .asciz "AVTransport"
Ls_rc:            .asciz "RenderingControl"
Lso_play:         .asciz "Play"
Lso_pause:        .asciz "Pause"
Lso_stop:         .asciz "Stop"
Lso_next:         .asciz "Next"
Lso_prev:         .asciz "Previous"
Lso_setvol:       .asciz "SetVolume"
Lso_relvol:       .asciz "SetRelativeVolume"
Lso_mute:         .asciz "SetMute"
Lx_speed:         .asciz "<Speed>1</Speed>"
Lx_vol:           .asciz "<Channel>Master</Channel><DesiredVolume>%ld</DesiredVolume>"
Lx_rel:           .asciz "<Channel>Master</Channel><Adjustment>%ld</Adjustment>"
Lx_mute:          .asciz "<Channel>Master</Channel><DesiredMute>%ld</DesiredMute>"
Lf_soap:          .asciz "<?xml version=\"1.0\" encoding=\"utf-8\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\"><s:Body><u:%s xmlns:u=\"urn:schemas-upnp-org:service:%s:1\"><InstanceID>0</InstanceID>%s</u:%s></s:Body></s:Envelope>"
Lf_soap_action:   .asciz "\"urn:schemas-upnp-org:service:%s:1#%s\""
Lf_sonos_ctl:     .asciz "http://%s/MediaRenderer/%s/Control"
Ls_soapaction:    .asciz "SOAPACTION"
Ls_kasa_info:     .asciz "{\"system\":{\"get_sysinfo\":{}}}"
Lk_system:        .asciz "system"
Lk_sysinfo:       .asciz "get_sysinfo"
Lk_alias:         .asciz "alias"
Lk_light_state:   .asciz "light_state"
Lk_brightness:    .asciz "brightness"
Lk_is_color:      .asciz "is_color"
Lk_is_ct:         .asciz "is_variable_color_temp"
Lk_relay:         .asciz "relay_state"
Lk_on_off:        .asciz "on_off"
Lk_relay_fmt:     .asciz "{\"system\":{\"set_relay_state\":{\"state\":%ld}}}"
Lk_dim_fmt:       .asciz "{\"system\":{\"set_relay_state\":{\"state\":1}},\"smartlife.iot.dimmer\":{\"set_brightness\":{\"brightness\":%ld}}}"
Lk_bulb_onoff:    .asciz "{\"smartlife.iot.smartbulb.lightingservice\":{\"transition_light_state\":{\"on_off\":%ld}}}"
Lk_bulb_bri:      .asciz "{\"smartlife.iot.smartbulb.lightingservice\":{\"transition_light_state\":{\"on_off\":1,\"brightness\":%ld}}}"
Lk_bulb_hue:      .asciz "{\"smartlife.iot.smartbulb.lightingservice\":{\"transition_light_state\":{\"on_off\":1,\"hue\":%ld,\"saturation\":100,\"color_temp\":0}}}"
Lk_bulb_ct:       .asciz "{\"smartlife.iot.smartbulb.lightingservice\":{\"transition_light_state\":{\"on_off\":1,\"color_temp\":%ld}}}"
Ls_kasa_found:    .asciz "\302\267 Found TP-Link Kasa \342\200\234%s\342\200\235 on your Wi-Fi."
