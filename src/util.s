// util.s — Objective-C messaging shortcuts, NSString helpers, formatted chat lines
//
// asmmesh: a Bluetooth mesh messenger with a Cocoa window, ARM64 assembly, Apple Silicon.

.include "macros.inc"

.text
.p2align 2

// ---------------------------------------------------------------------------
// id _msg0(id rcv, const char *selname)
// id _msg1(id rcv, const char *selname, a)
// id _msg2(id rcv, const char *selname, a, b)
// id _msg3(id rcv, const char *selname, a, b, c)
// id _msg4(id rcv, const char *selname, a, b, c, d)
//   Register the selector by name and send it. Integer/pointer arguments only
//   (float and struct arguments are sent by hand with SELX1 + _objc_msgSend).
// ---------------------------------------------------------------------------
.globl _msg0
_msg0:
    ENTER 0
    mov  x19, x0
    mov  x0, x1
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    bl   _objc_msgSend
    LEAVE 0

.globl _msg1
_msg1:
    ENTER 0
    mov  x19, x0
    mov  x20, x2
    mov  x0, x1
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    mov  x2, x20
    bl   _objc_msgSend
    LEAVE 0

.globl _msg2
_msg2:
    ENTER 0
    mov  x19, x0
    mov  x20, x2
    mov  x21, x3
    mov  x0, x1
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    mov  x2, x20
    mov  x3, x21
    bl   _objc_msgSend
    LEAVE 0

.globl _msg3
_msg3:
    ENTER 0
    mov  x19, x0
    mov  x20, x2
    mov  x21, x3
    mov  x22, x4
    mov  x0, x1
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    mov  x2, x20
    mov  x3, x21
    mov  x4, x22
    bl   _objc_msgSend
    LEAVE 0

.globl _msg4
_msg4:
    ENTER 0
    mov  x19, x0
    mov  x20, x2
    mov  x21, x3
    mov  x22, x4
    mov  x23, x5
    mov  x0, x1
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    mov  x2, x20
    mov  x3, x21
    mov  x4, x22
    mov  x5, x23
    bl   _objc_msgSend
    LEAVE 0

// ---------------------------------------------------------------------------
// id _nsstr(const char *utf8)
//   Autoreleased NSString. Never returns nil: if the bytes are not valid UTF-8
//   it falls back to a Latin-1 interpretation.
// ---------------------------------------------------------------------------
.globl _nsstr
_nsstr:
    ENTER 0
    mov  x19, x0
    CLS  Ls_NSString
    mov  x2, x19
    MSG1 Ls_stringWithUTF8String
    cbnz x0, Lnsstr_done
    mov  x0, x19
    bl   _strlen
    mov  x1, x0
    mov  x0, x19
    bl   _nsstr_latin1
Lnsstr_done:
    LEAVE 0

// ---------------------------------------------------------------------------
// id _nsstr_latin1(const void *bytes, size_t len)
//   Autoreleased NSString decoded as ISO-8859-1 (every byte sequence is valid).
// ---------------------------------------------------------------------------
.globl _nsstr_latin1
_nsstr_latin1:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    CLS  Ls_NSString
    MSG0 Ls_alloc
    mov  x2, x19
    mov  x3, x20
    mov  x4, #5                     // NSISOLatin1StringEncoding
    MSG3 Ls_initWithBytes
    MSG0 Ls_autorelease
    LEAVE 0

// ---------------------------------------------------------------------------
// const char *_err_cstr(NSError *err)
//   UTF-8 description of an NSError, or "unknown error".
// ---------------------------------------------------------------------------
.globl _err_cstr
_err_cstr:
    ENTER 0
    cbz  x0, Lerr_none
    MSG0 Ls_localizedDescription
    cbz  x0, Lerr_none
    MSG0 Ls_UTF8String
    cbz  x0, Lerr_none
    LEAVE 0
Lerr_none:
    ADRL x0, Ls_unknown
    LEAVE 0

// ---------------------------------------------------------------------------
// void _chat_fmt(const char *fmt, long a, long b, long c)
//   snprintf with up to three %s / %ld arguments, then _chat_line.
// ---------------------------------------------------------------------------
.globl _chat_fmt
_chat_fmt:
    ENTER 1024
    mov  x9, x0
    str  x1, [sp]
    str  x2, [sp, #8]
    str  x3, [sp, #16]
    add  x0, sp, #96
    mov  x1, #1024
    mov  x2, x9
    bl   _snprintf
    add  x0, sp, #96
    bl   _chat_line
    LEAVE 1024

// ---------------------------------------------------------------------------
// size_t _text_copy_trim(char *dst, const char *src, size_t max)
//   Copy with leading/trailing spaces trimmed, capped at max bytes on a UTF-8
//   boundary, control characters neutralised. dst needs max+1 bytes. -> length
// ---------------------------------------------------------------------------
.globl _text_copy_trim
_text_copy_trim:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
Ltc_skip:
    ldrb w9, [x20]
    cmp  w9, #' '
    b.ne Ltc_len
    add  x20, x20, #1
    b    Ltc_skip
Ltc_len:
    mov  x0, x20
    bl   _strlen
    mov  x22, x0
    cmp  x22, x21
    b.ls Ltc_trim
    mov  x22, x21
Ltc_back:
    cbz  x22, Ltc_trim
    ldrb w9, [x20, x22]
    and  w9, w9, #0xC0
    cmp  w9, #0x80
    b.ne Ltc_trim
    sub  x22, x22, #1
    b    Ltc_back
Ltc_trim:
    cbz  x22, Ltc_copy
    sub  x9, x22, #1
    ldrb w10, [x20, x9]
    cmp  w10, #' '
    b.ne Ltc_copy
    mov  x22, x9
    b    Ltc_trim
Ltc_copy:
    mov  x0, x19
    mov  x1, x20
    mov  x2, x22
    bl   _memmove
    strb wzr, [x19, x22]
    mov  x0, x19
    bl   _sanitize
    mov  x0, x22
    LEAVE 0

// void _utf8_fix(char *s) — drop a multi-byte character cut off at the end
.globl _utf8_fix
_utf8_fix:
    ENTER 0
    mov  x19, x0
    bl   _strlen
    cbz  x0, Luf_done
    mov  x20, x0                      // length
    sub  x9, x20, #1
Luf_lead:
    cbz  x9, Luf_check
    ldrb w10, [x19, x9]
    and  w10, w10, #0xC0
    cmp  w10, #0x80
    b.ne Luf_check
    sub  x9, x9, #1
    b    Luf_lead
Luf_check:
    ldrb w10, [x19, x9]
    mov  x11, #1
    cmp  w10, #0xC0
    b.lo Luf_have
    mov  x11, #2
    cmp  w10, #0xE0
    b.lo Luf_have
    mov  x11, #3
    cmp  w10, #0xF0
    b.lo Luf_have
    mov  x11, #4
Luf_have:
    add  x11, x9, x11
    cmp  x11, x20
    b.ls Luf_done
    strb wzr, [x19, x9]
Luf_done:
    LEAVE 0

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
Ls_NSString:              .asciz "NSString"
Ls_stringWithUTF8String:  .asciz "stringWithUTF8String:"
Ls_alloc:                 .asciz "alloc"
Ls_initWithBytes:         .asciz "initWithBytes:length:encoding:"
Ls_autorelease:           .asciz "autorelease"
Ls_localizedDescription:  .asciz "localizedDescription"
Ls_UTF8String:            .asciz "UTF8String"
Ls_unknown:               .asciz "unknown error"
