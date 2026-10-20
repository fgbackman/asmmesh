// files_mac.s — the Mac's side of Files on Wi-Fi: choosing folders (an open panel),
// AirDrop (NSSharingService) and the QR code window. iPhone has its own in ios_ui.s
// (the app's folder in the Files app, the share sheet, a SwiftUI sheet).

.include "macros.inc"

.set NROOT_MAX,  8          // as in files.s
.set ROOT_LEN,   1024

.section __TEXT,__cstring,cstring_literals
.globl _fs_default_dir
_fs_default_dir: .asciz "%s/asmmesh Files"      // shared until you choose folders

.text
.p2align 2

// "share folders" / Mesh › Share Folders on Wi-Fi… — pick up to eight folders
.globl _h_files_choose
_h_files_choose:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lhc2_done
    mov  x0, #SVC_FILES
    bl   _svc_gate
    cbz  x0, Lhc2_done
    CLS  Ls_NSOpenPanel
    MSG0 Ls_openPanel
    cbz  x0, Lhc2_done
    mov  x19, x0
    mov  x0, x19
    mov  x2, #0
    MSG1 Ls_setCanChooseFiles
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setCanChooseDirectories
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setAllowsMultipleSelection
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setCanCreateDirectories
    ADRL x0, Ls_share_prompt
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setPrompt
    ADRL x0, Ls_share_msg
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setMessage
    bl   _fs_activate
    mov  x0, x19
    MSG0 Ls_runModal
    cmp  x0, #1                       // NSModalResponseOK
    b.ne Lhc2_done
    mov  x0, x19
    MSG0 Ls_URLs
    mov  x20, x0
    MSG0 Ls_count
    mov  x21, x0
    cbz  x21, Lhc2_done
    cmp  x21, #NROOT_MAX
    mov  x9, #NROOT_MAX
    csel x21, x9, x21, hi
    mov  x22, #0
Lhc2_loop:
    cmp  x22, x21
    b.hs Lhc2_save
    mov  x0, x20
    mov  x2, x22
    MSG1 Ls_objectAtIndex
    MSG0 Ls_path
    MSG0 Ls_UTF8String
    mov  x1, x0
    ADRL x8, _g_fs_roots
    add  x0, x8, x22, lsl #10
    mov  x2, #ROOT_LEN
    bl   _strlcpy
    add  x22, x22, #1
    b    Lhc2_loop
Lhc2_save:
    ADRL x8, _g_fs_nroots
    str  x21, [x8]
    bl   _fs_save_roots
    bl   _h_files
Lhc2_done:
    LEAVE 0

// "airdrop" / Mesh › AirDrop a File… — pick files, then AirDrop shows who's near
.globl _h_airdrop
_h_airdrop:
    ENTER 0
    bl   _al_remote
    cbnz x0, Lad_done
    CLS  Ls_NSOpenPanel
    MSG0 Ls_openPanel
    cbz  x0, Lad_done
    mov  x19, x0
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setCanChooseFiles
    mov  x0, x19
    mov  x2, #0
    MSG1 Ls_setCanChooseDirectories
    mov  x0, x19
    mov  x2, #1
    MSG1 Ls_setAllowsMultipleSelection
    ADRL x0, Ls_ad_prompt
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setPrompt
    bl   _fs_activate
    mov  x0, x19
    MSG0 Ls_runModal
    cmp  x0, #1
    b.ne Lad_done
    mov  x0, x19
    MSG0 Ls_URLs
    mov  x20, x0
    LDGOT x8, _NSSharingServiceNameSendViaAirDrop
    ldr  x2, [x8]
    CLS  Ls_NSSharingService
    MSG1 Ls_sharingServiceNamed
    cbz  x0, Lad_none
    mov  x21, x0
    mov  x0, x21
    mov  x2, x20
    MSG1 Ls_canPerformWithItems
    tst  w0, #0xff
    b.eq Lad_none
    mov  x0, x21
    mov  x2, x20
    MSG1 Ls_performWithItems
    ADRL x0, Ls_ad_open
    bl   _home_say0
    LEAVE 0
Lad_none:
    ADRL x0, Ls_ad_none
    bl   _home_say0
Lad_done:
    LEAVE 0

// bring asmmesh to the front (so a panel or window isn't hidden behind others)
_fs_activate:
    ENTER 0
    CLS  Ls_NSApplication
    MSG0 Ls_sharedApplication
    mov  x2, #1
    MSG1 Ls_activateIgnoringOtherApps
    LEAVE 0

// void _fs_qr_show(const char *text) — a small window with the text as a QR code
.globl _fs_qr_show
_fs_qr_show:
    ENTER 80                          // [96] transform (48)  [144] size
    mov  x19, x0
    CLS  Ls_CIFilter
    mov  x20, x0
    ADRL x0, Ls_qrgen
    bl   _nsstr
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_filterWithName
    cbz  x0, Lqr_done
    mov  x20, x0
    mov  x0, x19
    bl   _nsstr
    mov  x2, #4                       // UTF-8
    MSG1 Ls_dataUsingEncoding
    mov  x21, x0
    ADRL x0, Ls_inputMessage
    bl   _nsstr
    mov  x3, x0
    mov  x0, x20
    mov  x2, x21
    MSG2 Ls_setValueForKey
    ADRL x0, Ls_M
    bl   _nsstr
    mov  x21, x0
    ADRL x0, Ls_inputCorrection
    bl   _nsstr
    mov  x3, x0
    mov  x0, x20
    mov  x2, x21
    MSG2 Ls_setValueForKey
    mov  x0, x20
    MSG0 Ls_outputImage
    cbz  x0, Lqr_done
    mov  x21, x0
    mov  x0, x21                      // scale it up to about 250 points, whole pixels
    MSG0 Ls_extent
    LDD  d1, Lc_250
    fdiv d0, d1, d2
    frintm d0, d0
    fmov d1, #1.0
    fmax d0, d0, d1
    LDD  d1, Lc_0
    stp  d0, d1, [sp, #96]            // a, b
    stp  d1, d0, [sp, #112]           // c, d
    stp  d1, d1, [sp, #128]           // tx, ty
    mov  x0, x21
    add  x2, sp, #96                  // (a 48-byte struct goes by address)
    MSG1 Ls_imageByApplyingTransform
    mov  x21, x0
    CLS  Ls_NSCIImageRep
    mov  x2, x21
    MSG1 Ls_imageRepWithCIImage
    cbz  x0, Lqr_done
    mov  x21, x0
    MSG0 Ls_size
    stp  d0, d1, [sp, #144]
    CLS  Ls_NSImage
    MSG0 Ls_alloc
    mov  x22, x0
    SELX1 Ls_initWithSize
    mov  x0, x22
    ldp  d0, d1, [sp, #144]
    bl   _objc_msgSend
    mov  x22, x0
    mov  x2, x21
    MSG1 Ls_addRepresentation

    ADRL x8, _g_fs_qrwin
    ldr  x0, [x8]
    cbnz x0, Lqr_have
    CLS  Ls_NSWindow
    MSG0 Ls_alloc
    mov  x23, x0
    SELX1 Ls_initWithContentRect
    mov  x0, x23
    LDD  d0, Lc_0
    LDD  d1, Lc_0
    LDD  d2, Lc_qw
    LDD  d3, Lc_qh
    mov  x2, #3                       // titled | closable
    mov  x3, #2
    mov  x4, #0
    bl   _objc_msgSend
    mov  x23, x0
    ADRL x8, _g_fs_qrwin
    str  x23, [x8]
    ADRL x0, Ls_qr_title
    bl   _nsstr
    mov  x2, x0
    mov  x0, x23
    MSG1 Ls_setTitle
    mov  x0, x23
    mov  x2, #0
    MSG1 Ls_setReleasedWhenClosed
    mov  x0, x23
    MSG0 Ls_center
    mov  x0, x23
    MSG0 Ls_contentView
    mov  x24, x0
    CLS  Ls_NSImageView
    MSG0 Ls_new
    mov  x20, x0
    ADRL x8, _g_fs_qriv
    str  x20, [x8]
    SELX1 Ls_setFrame
    mov  x0, x20
    ADRL x8, Lf_qr_iv
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    mov  x0, x24
    mov  x2, x20
    MSG1 Ls_addSubview
    ADRL x0, Ls_empty                 // the address, small, selectable
    mov  x1, #0
    mov  x2, #0
    mov  x3, x24
    ADRL x8, Lf_qr_url
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s12
    bl   _mk_label
    ADRL x8, _g_fs_qrlbl
    str  x0, [x8]
    mov  x2, #1
    MSG1 Ls_setSelectable
    ADRL x0, Ls_qr_how
    mov  x1, #0
    mov  x2, #0
    mov  x3, x24
    ADRL x8, Lf_qr_how
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    LDD  d4, Lc_s12
    bl   _mk_label
    bl   _dim_label
Lqr_have:
    ADRL x8, _g_fs_qriv
    ldr  x0, [x8]
    mov  x2, x22
    MSG1 Ls_setImage
    mov  x0, x19
    bl   _nsstr
    mov  x2, x0
    ADRL x8, _g_fs_qrlbl
    ldr  x0, [x8]
    MSG1 Ls_setStringValue
    ADRL x8, _g_fs_qrwin
    ldr  x0, [x8]
    mov  x2, #0
    MSG1 Ls_makeKeyAndOrderFront
    bl   _fs_activate
Lqr_done:
    LEAVE 80


.section __TEXT,__const
.p2align 3
Lc_0:       .double 0.0
Lc_qw:      .double 320.0
Lc_qh:      .double 400.0
Lf_qr_iv:   .double 30.0, 110.0, 260.0, 260.0
Lf_qr_url:  .double 16.0, 72.0, 288.0, 20.0
Lf_qr_how:  .double 16.0, 30.0, 288.0, 34.0
Lc_s12:     .double 12.0
Lc_250:     .double 250.0

.section __TEXT,__cstring,cstring_literals
Ls_empty:       .asciz ""
Ls_share_prompt: .asciz "Share"
Ls_share_msg: .asciz "Choose up to eight folders your phone may open and add files to. Hidden files and Library always stay hidden."
Ls_ad_prompt: .asciz "AirDrop"
Ls_ad_open:   .asciz "\302\267 AirDrop is open \342\200\224 pick your phone (it needs to be unlocked and near)."
Ls_ad_none:   .asciz "\302\267 AirDrop isn\342\200\231t available right now. Check that Wi-Fi and Bluetooth are on, and AirDrop is allowed in Control Centre."
Ls_qr_title:  .asciz "Files on Wi-Fi"
Ls_qr_how:    .asciz "Scan with the iPhone camera, then open it in Safari. Your phone must be on the same Wi-Fi."
Ls_qrgen:     .asciz "CIQRCodeGenerator"
Ls_inputMessage: .asciz "inputMessage"
Ls_inputCorrection: .asciz "inputCorrectionLevel"
Ls_M:         .asciz "M"
Ls_NSOpenPanel:       .asciz "NSOpenPanel"
Ls_NSSharingService:  .asciz "NSSharingService"
Ls_NSApplication:     .asciz "NSApplication"
Ls_NSWindow:          .asciz "NSWindow"
Ls_NSImageView:       .asciz "NSImageView"
Ls_NSImage:           .asciz "NSImage"
Ls_NSCIImageRep:      .asciz "NSCIImageRep"
Ls_CIFilter:          .asciz "CIFilter"
Ls_openPanel:         .asciz "openPanel"
Ls_setCanChooseFiles: .asciz "setCanChooseFiles:"
Ls_setCanChooseDirectories: .asciz "setCanChooseDirectories:"
Ls_setAllowsMultipleSelection: .asciz "setAllowsMultipleSelection:"
Ls_setCanCreateDirectories: .asciz "setCanCreateDirectories:"
Ls_setPrompt:         .asciz "setPrompt:"
Ls_setMessage:        .asciz "setMessage:"
Ls_runModal:          .asciz "runModal"
Ls_URLs:              .asciz "URLs"
Ls_count:             .asciz "count"
Ls_objectAtIndex:     .asciz "objectAtIndex:"
Ls_path:              .asciz "path"
Ls_UTF8String:        .asciz "UTF8String"
Ls_sharingServiceNamed: .asciz "sharingServiceNamed:"
Ls_canPerformWithItems: .asciz "canPerformWithItems:"
Ls_performWithItems:  .asciz "performWithItems:"
Ls_sharedApplication: .asciz "sharedApplication"
Ls_activateIgnoringOtherApps: .asciz "activateIgnoringOtherApps:"
Ls_filterWithName:    .asciz "filterWithName:"
Ls_dataUsingEncoding: .asciz "dataUsingEncoding:"
Ls_setValueForKey:    .asciz "setValue:forKey:"
Ls_outputImage:       .asciz "outputImage"
Ls_extent:            .asciz "extent"
Ls_imageByApplyingTransform: .asciz "imageByApplyingTransform:"
Ls_imageRepWithCIImage: .asciz "imageRepWithCIImage:"
Ls_size:              .asciz "size"
Ls_alloc:             .asciz "alloc"
Ls_new:               .asciz "new"
Ls_initWithSize:      .asciz "initWithSize:"
Ls_addRepresentation: .asciz "addRepresentation:"
Ls_initWithContentRect: .asciz "initWithContentRect:styleMask:backing:defer:"
Ls_setTitle:          .asciz "setTitle:"
Ls_setReleasedWhenClosed: .asciz "setReleasedWhenClosed:"
Ls_center:            .asciz "center"
Ls_contentView:       .asciz "contentView"
Ls_setFrame:          .asciz "setFrame:"
Ls_addSubview:        .asciz "addSubview:"
Ls_setSelectable:     .asciz "setSelectable:"
Ls_setImage:          .asciz "setImage:"
Ls_setStringValue:    .asciz "setStringValue:"
Ls_makeKeyAndOrderFront: .asciz "makeKeyAndOrderFront:"
