// net.s — HTTP over NSURLSession (delegate callbacks on the main queue, so no
// blocks are needed), small JSON accessors over NSJSONSerialization results,
// and the Keychain for secrets.
//
//   _http(method, url, body_or_0, authorization_or_0, tag)
//     starts a request; its taskDescription is the tag. When it finishes,
//     _net_done hands (tag, parsed JSON, HTTP status, error, raw NSData) to the
//     backend the tag's first letter names: 'h' Hue, 's' SmartThings,
//     'l' local network (WLED, Elgato, Shelly, Nanoleaf), 'c' cloud (LIFX,
//     Govee, Home Assistant), 'u' SSDP finds (Roku).
//   _http2(... , header_name, header_value) adds one more header (Govee-API-Key).

.include "macros.inc"

.data
.p2align 3
_g_session:   .quad 0
_g_bufs:      .quad 0

.section __TEXT,__const
.p2align 3
Lc_timeout:   .double 12.0

.data
.p2align 2
.globl _g_kc_status
_g_kc_status:   .long 0

.text
.p2align 2

// id _net_session(void)
_net_session:
    ENTER 0
    ADRL x8, _g_session
    ldr  x0, [x8]
    cbnz x0, Lns_done
    CLS  Ls_NSURLSessionConfiguration
    MSG0 Ls_ephemeral
    mov  x19, x0
    SELX1 Ls_setTimeoutForRequest
    mov  x0, x19
    LDD  d0, Lc_timeout
    bl   _objc_msgSend
    CLS  Ls_NSOperationQueue
    MSG0 Ls_mainQueue
    mov  x20, x0
    CLS  Ls_NSURLSession
    mov  x2, x19
    ADRL x8, _g_ctl
    ldr  x3, [x8]
    mov  x4, x20
    MSG3 Ls_sessionWith
    MSG0 Ls_retain
    ADRL x8, _g_session
    str  x0, [x8]
    mov  x19, x0
    CLS  Ls_NSMutableDictionary
    MSG0 Ls_new
    ADRL x8, _g_bufs
    str  x0, [x8]
    mov  x0, x19
Lns_done:
    LEAVE 0

// void _http(const char *method, const char *url, const char *body, const char *auth, const char *tag)
.globl _http
_http:
    mov  x5, #0
    mov  x6, #0
    // fall through
// void _http2(method, url, body, auth, tag, header_name, header_value)
.globl _http2
_http2:
    ENTER 16
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    stp  x5, x6, [sp, #96]
    bl   _net_session
    mov  x24, x0
    mov  x0, x20
    bl   _nsstr
    mov  x20, x0
    CLS  Ls_NSURL
    mov  x2, x20
    MSG1 Ls_URLWithString
    cbz  x0, Lh_bad
    mov  x20, x0
    CLS  Ls_NSMutableURLRequest
    mov  x2, x20
    MSG1 Ls_requestWithURL
    mov  x20, x0
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_setHTTPMethod
    cbz  x21, Lh_auth
    mov  x0, x21
    bl   _nsstr
    mov  x2, #4                       // NSUTF8StringEncoding
    MSG1 Ls_dataUsingEncoding
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_setHTTPBody
    ADRL x0, Ls_json_type
    ADRL x1, Ls_content_type
    mov  x2, x20
    bl   _set_header
Lh_auth:
    cbz  x22, Lh_extra
    mov  x0, x22
    ADRL x1, Ls_authorization
    mov  x2, x20
    bl   _set_header
Lh_extra:
    ldp  x1, x0, [sp, #96]
    cbz  x1, Lh_task
    cbz  x0, Lh_task
    mov  x2, x20
    bl   _set_header
    ldr  x9, [sp, #96]                // a SOAPACTION (Sonos): the body is XML, not JSON
    ldrb w10, [x9]
    cmp  w10, #'S'
    b.ne Lh_task
    ldrb w10, [x9, #1]
    cmp  w10, #'O'
    b.ne Lh_task
    ADRL x0, Ls_xml_type
    ADRL x1, Ls_content_type
    mov  x2, x20
    bl   _set_header
Lh_task:
    mov  x0, x24
    mov  x2, x20
    MSG1 Ls_dataTaskWithRequest
    mov  x21, x0
    mov  x0, x23
    bl   _nsstr
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setTaskDescription
    mov  x0, x21
    MSG0 Ls_resume
Lh_done:
    LEAVE 16
Lh_bad:                               // a URL NSURL won't take: say so instead of silence
    ADRL x0, Ls_bad_url
    bl   _home_say0
    LEAVE 16

// long _sfmt(char *dst, size_t max, const char *fmt, a, b, c, d, e) — snprintf
// with up to five register arguments
.globl _sfmt
_sfmt:
    sub  sp, sp, #64
    stp  x29, x30, [sp, #48]
    add  x29, sp, #48
    stp  x3, x4, [sp]
    stp  x5, x6, [sp, #16]
    str  x7, [sp, #32]
    bl   _snprintf
    ldp  x29, x30, [sp, #48]
    add  sp, sp, #64
    ret

// void _set_header(const char *value, const char *field, NSMutableURLRequest *req)
_set_header:
    ENTER 0
    mov  x19, x1
    mov  x22, x2
    bl   _nsstr
    mov  x21, x0
    mov  x0, x19
    bl   _nsstr
    mov  x3, x0
    mov  x2, x21
    mov  x0, x22
    MSG2 Ls_setValueForHeader
    LEAVE 0

// id _task_key(NSURLSessionTask *t) -> NSNumber of its identifier
_task_key:
    ENTER 0
    MSG0 Ls_taskIdentifier
    mov  x19, x0
    CLS  Ls_NSNumber
    mov  x2, x19
    MSG1 Ls_numberWithUnsignedInteger
    LEAVE 0

// - URLSession:dataTask:didReceiveData:
.globl _net_data
_net_data:
    ENTER 0
    mov  x19, x3
    mov  x20, x4
    mov  x0, x19
    bl   _task_key
    mov  x21, x0
    ADRL x8, _g_bufs
    ldr  x22, [x8]
    mov  x0, x22
    mov  x2, x21
    MSG1 Ls_objectForKey
    cbnz x0, Lnd_append
    CLS  Ls_NSMutableData
    MSG0 Ls_data
    mov  x23, x0
    mov  x0, x22
    mov  x2, x23
    mov  x3, x21
    MSG2 Ls_setObjectForKey
    mov  x0, x23
Lnd_append:
    mov  x2, x20
    MSG1 Ls_appendData
    LEAVE 0

// - URLSession:task:didCompleteWithError:
.globl _net_done
_net_done:
    ENTER 64                          // [96] tag
    mov  x19, x3
    mov  x20, x4
    mov  x0, x19
    bl   _task_key
    mov  x21, x0
    ADRL x8, _g_bufs
    ldr  x0, [x8]
    mov  x2, x21
    MSG1 Ls_objectForKey
    MSG0 Ls_retain
    mov  x22, x0                      // body (may be nil)
    ADRL x8, _g_bufs
    ldr  x0, [x8]
    mov  x2, x21
    MSG1 Ls_removeObjectForKey
    strb wzr, [sp, #96]
    mov  x0, x19
    MSG0 Ls_taskDescription
    cbz  x0, Lnd2_status
    MSG0 Ls_UTF8String
    cbz  x0, Lnd2_status
    mov  x1, x0
    add  x0, sp, #96
    mov  x2, #32
    bl   _strlcpy
Lnd2_status:
    mov  x23, #-1
    cbnz x20, Lnd2_json
    mov  x0, x19
    MSG0 Ls_response
    mov  x23, #0
    cbz  x0, Lnd2_json
    MSG0 Ls_statusCode
    mov  x23, x0
Lnd2_json:
    mov  x24, #0
    cbz  x22, Lnd2_dispatch
    CLS  Ls_NSJSONSerialization
    mov  x2, x22
    mov  x3, #0
    mov  x4, #0
    MSG3 Ls_JSONObjectWithData
    mov  x24, x0
Lnd2_dispatch:
    add  x0, sp, #96
    mov  x1, x24
    mov  x2, x23
    mov  x3, x20
    mov  x4, x22
    ldrb w9, [sp, #96]
    cmp  w9, #'h'
    b.eq Lnd2_hue
    cmp  w9, #'s'
    b.eq Lnd2_st
    cmp  w9, #'l'
    b.eq Lnd2_lan
    cmp  w9, #'c'
    b.eq Lnd2_cloud
    cmp  w9, #'w'
    b.eq Lnd2_weather
    cmp  w9, #'x'
    b.eq Lnd2_extra
    cmp  w9, #'a'
    b.eq Lnd2_alerts
    cmp  w9, #'u'
    b.ne Lnd2_release
    bl   _udp_response
    b    Lnd2_release
Lnd2_weather:
    bl   _weather_response
    b    Lnd2_release
Lnd2_extra:
    bl   _extra_response
    b    Lnd2_release
Lnd2_alerts:
    bl   _alerts_response
    b    Lnd2_release
Lnd2_st:
    bl   _st_response
    b    Lnd2_release
Lnd2_lan:
    bl   _lan_response
    b    Lnd2_release
Lnd2_cloud:
    bl   _cloud_response
    b    Lnd2_release
Lnd2_hue:
    bl   _hue_response
Lnd2_release:
    mov  x0, x22
    MSG0 Ls_release
    LEAVE 64

// ---------------------------------------------------------------------------
// JSON accessors (all nil-safe; wrong types read as nil / 0)
// ---------------------------------------------------------------------------

// int _is_kind(id obj, const char *classname)
_is_kind:
    ENTER 0
    mov  x19, x0
    cbz  x19, Lik_no
    mov  x0, x1
    bl   _objc_getClass
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_isKindOfClass
    and  x0, x0, #0xff
    LEAVE 0
Lik_no:
    mov  x0, #0
    LEAVE 0

// id _jget(id dict, const char *key)
.globl _jget
_jget:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    ADRL x1, Ls_NSDictionary
    bl   _is_kind
    cbz  x0, Ljg_nil
    mov  x0, x20
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_objectForKey
    LEAVE 0
Ljg_nil:
    mov  x0, #0
    LEAVE 0

// const char *_jstr(id obj) -> UTF-8 or 0
.globl _jstr
_jstr:
    ENTER 0
    mov  x19, x0
    ADRL x1, Ls_NSString
    bl   _is_kind
    cbz  x0, Ljs_nil
    mov  x0, x19
    MSG0 Ls_UTF8String
    LEAVE 0
Ljs_nil:
    mov  x0, #0
    LEAVE 0

// long _jint(id obj) — numbers and numeric strings; 0 otherwise
.globl _jint
_jint:
    ENTER 0
    mov  x19, x0
    ADRL x1, Ls_NSNumber
    bl   _is_kind
    cbnz x0, Lji_go
    mov  x0, x19
    ADRL x1, Ls_NSString
    bl   _is_kind
    cbz  x0, Lji_zero
Lji_go:
    mov  x0, x19
    MSG0 Ls_integerValue
    LEAVE 0
Lji_zero:
    mov  x0, #0
    LEAVE 0

// long _jcount(id obj) -> element count if it is an array, else 0
.globl _jcount
_jcount:
    ENTER 0
    mov  x19, x0
    ADRL x1, Ls_NSArray
    bl   _is_kind
    cbz  x0, Ljc_zero
    mov  x0, x19
    MSG0 Ls_count
    LEAVE 0
Ljc_zero:
    mov  x0, #0
    LEAVE 0

// id _jat(id array, long i)
.globl _jat
_jat:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _jcount
    cmp  x20, x0
    b.hs Lja_nil
    mov  x0, x19
    mov  x2, x20
    MSG1 Ls_objectAtIndex
    LEAVE 0
Lja_nil:
    mov  x0, #0
    LEAVE 0

// id _jkeys(id dict) -> its keys (NSArray) or nil
.globl _jkeys
_jkeys:
    ENTER 0
    mov  x19, x0
    ADRL x1, Ls_NSDictionary
    bl   _is_kind
    cbz  x0, Ljk_nil
    mov  x0, x19
    MSG0 Ls_allKeys
    LEAVE 0
Ljk_nil:
    mov  x0, #0
    LEAVE 0

// id _json_parse(const void *bytes, size_t len) -> parsed object or nil
.globl _json_parse
_json_parse:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    CLS  Ls_NSData
    mov  x2, x19
    mov  x3, x20
    MSG2 Ls_dataWithBytes
    mov  x21, x0
    CLS  Ls_NSJSONSerialization
    mov  x2, x21
    mov  x3, #0
    mov  x4, #0
    MSG3 Ls_JSONObjectWithData
    LEAVE 0

// char *_jdesc(id obj, char *buf, size_t max) — a number or string as text ("" if nil)
.globl _jdesc
_jdesc:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    strb wzr, [x20]
    cbz  x19, Ljd_done
    mov  x0, x19
    ADRL x1, Ls_NSDictionary
    bl   _is_kind
    cbnz x0, Ljd_done
    mov  x0, x19
    ADRL x1, Ls_NSArray
    bl   _is_kind
    cbnz x0, Ljd_done
    mov  x0, x19
    MSG0 Ls_description
    MSG0 Ls_UTF8String
    cbz  x0, Ljd_done
    mov  x1, x0
    mov  x0, x20
    mov  x2, x21
    bl   _strlcpy
Ljd_done:
    mov  x0, x20
    LEAVE 0

// long _jpct(id number_0_to_1) -> 0..100
.globl _jpct
_jpct:
    ENTER 0
    mov  x19, x0
    ADRL x1, Ls_NSNumber
    bl   _is_kind
    cbz  x0, Ljp_zero
    SELX1 Ls_doubleValue
    mov  x0, x19
    bl   _objc_msgSend
    mov  x9, #100
    scvtf d1, x9
    fmul d0, d0, d1
    fcvtns x0, d0
    LEAVE 0
Ljp_zero:
    mov  x0, #0
    LEAVE 0

// long _jround(id number) -> nearest whole number (0 if not a number)
.globl _jround
_jround:
    ENTER 0
    mov  x19, x0
    ADRL x1, Ls_NSNumber
    bl   _is_kind
    cbz  x0, Ljr_zero
    SELX1 Ls_doubleValue
    mov  x0, x19
    bl   _objc_msgSend
    fcvtas x0, d0
    LEAVE 0
Ljr_zero:
    mov  x0, #0
    LEAVE 0

// long _jhas(NSArray *strings, const char *s) -> 1 if s is one of them
.globl _jhas
_jhas:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    bl   _jcount
    mov  x21, x0
    mov  x22, #0
Ljh_loop:
    cmp  x22, x21
    b.hs Ljh_no
    mov  x0, x19
    mov  x1, x22
    bl   _jat
    bl   _jstr
    add  x22, x22, #1
    cbz  x0, Ljh_loop
    mov  x1, x20
    bl   _strcmp
    cbnz w0, Ljh_loop
    mov  x0, #1
    LEAVE 0
Ljh_no:
    mov  x0, #0
    LEAVE 0

// long _jfind(NSArray *dicts, const char *key, const char *value) -> 1 if some
// element has d[key] == value
.globl _jfind
_jfind:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x23, x2
    bl   _jcount
    mov  x21, x0
    mov  x22, #0
Ljf_loop:
    cmp  x22, x21
    b.hs Ljf_no
    mov  x0, x19
    mov  x1, x22
    bl   _jat
    mov  x1, x20
    bl   _jget
    bl   _jstr
    add  x22, x22, #1
    cbz  x0, Ljf_loop
    mov  x1, x23
    bl   _strcmp
    cbnz w0, Ljf_loop
    mov  x0, #1
    LEAVE 0
Ljf_no:
    mov  x0, #0
    LEAVE 0

// long _tag_num(const char *tag) -> the number after the two tag letters
.globl _tag_num
_tag_num:
    add  x0, x0, #2
    b    _atol

// ---------------------------------------------------------------------------
// Keychain: one generic password per service, account "asmmesh"
// ---------------------------------------------------------------------------

// NSMutableDictionary *_kc_query(const char *service)
_kc_query:
    ENTER 0
    mov  x19, x0
    CLS  Ls_NSMutableDictionary
    MSG0 Ls_dictionary
    mov  x20, x0
    LDGOT x8, _kSecClassGenericPassword
    ldr  x2, [x8]
    LDGOT x8, _kSecClass
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    LDGOT x8, _kSecAttrService
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
    ADRL x0, Ls_account
    bl   _nsstr
    mov  x2, x0
    LDGOT x8, _kSecAttrAccount
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
    mov  x0, x20
    LEAVE 0

// size_t _kc_get(const char *service, char *buf, size_t max) -> length (0 = none)
.globl _kc_get
_kc_get:
    ENTER 16
    mov  x21, x1
    mov  x22, x2
    strb wzr, [x21]
    bl   _kc_query
    mov  x20, x0
    LDGOT x8, _kCFBooleanTrue
    ldr  x2, [x8]
    LDGOT x8, _kSecReturnData
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
    LDGOT x8, _kSecMatchLimitOne
    ldr  x2, [x8]
    LDGOT x8, _kSecMatchLimit
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
    str  xzr, [sp, #96]
    mov  x0, x20
    add  x1, sp, #96
    bl   _SecItemCopyMatching
    ADRL x8, _g_kc_status             // why a read came back empty (-25300: there's none)
    str  w0, [x8]
    cbnz w0, Lkg_none
    ldr  x23, [sp, #96]
    cbz  x23, Lkg_none
    mov  x0, x23
    MSG0 Ls_length
    mov  x24, x0
    sub  x9, x22, #1
    cmp  x24, x9
    csel x24, x24, x9, lo
    mov  x0, x23
    MSG0 Ls_bytes
    mov  x1, x0
    mov  x0, x21
    mov  x2, x24
    bl   _memcpy
    strb wzr, [x21, x24]
    mov  x0, x23
    bl   _CFRelease
    mov  x0, x24
    LEAVE 16
Lkg_none:
    mov  x0, #0
    LEAVE 16

// void _kc_set(const char *service, const char *secret) — replaces any old one
.globl _kc_set
_kc_set:
    ENTER 0
    mov  x21, x1
    bl   _kc_query
    mov  x20, x0
    bl   _SecItemDelete
    mov  x0, x21
    bl   _nsstr
    mov  x2, #4
    MSG1 Ls_dataUsingEncoding
    mov  x2, x0
    LDGOT x8, _kSecValueData
    ldr  x3, [x8]
    mov  x0, x20
    MSG2 Ls_setObjectForKey
    mov  x0, x20
    mov  x1, #0
    bl   _SecItemAdd
    LEAVE 0

// void _kc_del(const char *service) — removes it, if there is one
.globl _kc_del
_kc_del:
    ENTER 0
    bl   _kc_query
    bl   _SecItemDelete
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_NSURLSessionConfiguration: .asciz "NSURLSessionConfiguration"
Ls_NSOperationQueue:  .asciz "NSOperationQueue"
Ls_NSURLSession:      .asciz "NSURLSession"
Ls_NSMutableDictionary: .asciz "NSMutableDictionary"
Ls_NSURL:             .asciz "NSURL"
Ls_NSMutableURLRequest: .asciz "NSMutableURLRequest"
Ls_NSNumber:          .asciz "NSNumber"
Ls_NSMutableData:     .asciz "NSMutableData"
Ls_NSJSONSerialization: .asciz "NSJSONSerialization"
Ls_NSDictionary:      .asciz "NSDictionary"
Ls_NSString:          .asciz "NSString"
Ls_NSArray:           .asciz "NSArray"
Ls_ephemeral:         .asciz "ephemeralSessionConfiguration"
Ls_setTimeoutForRequest: .asciz "setTimeoutIntervalForRequest:"
Ls_mainQueue:         .asciz "mainQueue"
Ls_sessionWith:       .asciz "sessionWithConfiguration:delegate:delegateQueue:"
Ls_retain:            .asciz "retain"
Ls_release:           .asciz "release"
Ls_new:               .asciz "new"
Ls_URLWithString:     .asciz "URLWithString:"
Ls_requestWithURL:    .asciz "requestWithURL:"
Ls_setHTTPMethod:     .asciz "setHTTPMethod:"
Ls_dataUsingEncoding: .asciz "dataUsingEncoding:"
Ls_setHTTPBody:       .asciz "setHTTPBody:"
Ls_setValueForHeader: .asciz "setValue:forHTTPHeaderField:"
Ls_dataTaskWithRequest: .asciz "dataTaskWithRequest:"
Ls_setTaskDescription: .asciz "setTaskDescription:"
Ls_taskDescription:   .asciz "taskDescription"
Ls_resume:            .asciz "resume"
Ls_taskIdentifier:    .asciz "taskIdentifier"
Ls_numberWithUnsignedInteger: .asciz "numberWithUnsignedInteger:"
Ls_objectForKey:      .asciz "objectForKey:"
Ls_setObjectForKey:   .asciz "setObject:forKey:"
Ls_removeObjectForKey: .asciz "removeObjectForKey:"
Ls_data:              .asciz "data"
Ls_appendData:        .asciz "appendData:"
Ls_response:          .asciz "response"
Ls_statusCode:        .asciz "statusCode"
Ls_UTF8String:        .asciz "UTF8String"
Ls_JSONObjectWithData: .asciz "JSONObjectWithData:options:error:"
Ls_isKindOfClass:     .asciz "isKindOfClass:"
Ls_integerValue:      .asciz "integerValue"
Ls_count:             .asciz "count"
Ls_objectAtIndex:     .asciz "objectAtIndex:"
Ls_allKeys:           .asciz "allKeys"
Ls_dictionary:        .asciz "dictionary"
Ls_length:            .asciz "length"
Ls_bytes:             .asciz "bytes"
Ls_account:           .asciz "asmmesh"
Ls_json_type:         .asciz "application/json"
Ls_content_type:      .asciz "Content-Type"
Ls_authorization:     .asciz "Authorization"
Ls_NSData:            .asciz "NSData"
Ls_xml_type:          .asciz "text/xml; charset=\"utf-8\""
Ls_dataWithBytes:     .asciz "dataWithBytes:length:"
Ls_description:       .asciz "description"
Ls_doubleValue:       .asciz "doubleValue"
Ls_bad_url:           .asciz "\302\267 That address doesn't look like a web address asmmesh can use."
