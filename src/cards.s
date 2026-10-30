// cards.s — the Rooms and People lists drawn as cards, like the iPhone app: a
// round coloured icon, a bold name, a dim second line (a room's last line, a
// person's key and how far away they are) and an amber unread badge. The open
// room and the chosen person get an amber outline.
//
// The two tables get their own small delegate class (AMeshCards), so the
// scanner's table keeps the controller's plain text rows. Also the round icon
// buttons (Talk, Send) under the transcript.

.include "macros.inc"
.include "bc_defs.inc"

.section __DATA,__data
.p2align 3
.globl _g_cards
_g_cards:    .quad 0

.section __TEXT,__const
.p2align 3
Lc_0:        .double 0.0
Lc_2:        .double 2.0
Lc_3:        .double 3.0
Lc_4:        .double 4.0
Lc_rowh:     .double 58.0
Lc_cardh:    .double 52.0
Lc_r16:      .double 16.0
Lc_r17:      .double 17.0
Lc_r18:      .double 18.0
Lc_r8:       .double 8.0
Lc_tx:       .double 52.0         // the text starts here
Lc_tright:   .double 66.0         // text width = row width - this
Lc_tbadge:   .double 38.0         //   ... and this much less beside a badge
Lc_ty:       .double 27.0
Lc_th:       .double 18.0
Lc_sy:       .double 9.0
Lc_sh:       .double 16.0
Lc_bx:       .double 44.0         // badge x = row width - this
Lc_by:       .double 18.0
Lc_bw:       .double 28.0
Lc_bh:       .double 16.0
Lc_s14:      .double 14.0
Lc_s115:     .double 11.5
Lc_s11:      .double 11.0
Lc_gsize:    .double 15.0         // SF Symbol point size and weight (semibold)
Lc_gweight:  .double 0.3
Lf_icon:     .double 9.0, 9.0, 34.0, 34.0
Lf_glyph:    .double 7.0, 7.0, 20.0, 20.0

// room kinds: symbol, colour, second line when the room is empty
.section __DATA,__const
.p2align 3
Lk_main:     .quad Ls_y_globe, 0x0A84FF, Ls_k_main
Lk_home:     .quad Ls_y_house, 0xFF9E0A, Ls_k_home
Lk_web:      .quad Ls_y_safari, 0x99999E, Ls_k_web
Lk_news:     .quad Ls_y_news, 0xFFD60A, Ls_k_news
Lk_private:  .quad Ls_y_lock, 0xBF59F2, Ls_k_private

Lcd_methods:
    .quad Ls_m_rows,   _ds_rows,       Ls_ty_rows
    .quad Ls_m_view,   _cd_view,       Ls_ty_view
    .quad Ls_m_height, _cd_height,     Ls_ty_height
    .quad Ls_m_sel,    _cd_selchange,  Ls_ty_v1
    .quad 0

.text
.p2align 2

// ---------------------------------------------------------------------------
// void _cards_init(void) — builds AMeshCards and keeps one in _g_cards
// ---------------------------------------------------------------------------
.globl _cards_init
_cards_init:
    ENTER 0
    CLS  Ls_NSObject
    ADRL x1, Ls_cls
    mov  x2, #0
    bl   _objc_allocateClassPair
    mov  x19, x0
    cbz  x19, Lci_done
    ADRL x20, Lcd_methods
Lci_loop:
    ldr  x0, [x20]
    cbz  x0, Lci_protos
    bl   _sel_registerName
    mov  x1, x0
    mov  x0, x19
    ldr  x2, [x20, #8]
    ldr  x3, [x20, #16]
    bl   _class_addMethod
    add  x20, x20, #24
    b    Lci_loop
Lci_protos:
    ADRL x0, Ls_p_tds
    bl   _objc_getProtocol
    cbz  x0, 1f
    mov  x1, x0
    mov  x0, x19
    bl   _class_addProtocol
1:  ADRL x0, Ls_p_tdl
    bl   _objc_getProtocol
    cbz  x0, 2f
    mov  x1, x0
    mov  x0, x19
    bl   _class_addProtocol
2:  mov  x0, x19
    bl   _objc_registerClassPair
    mov  x0, x19
    MSG0 Ls_new
    ADRL x8, _g_cards
    str  x0, [x8]
Lci_done:
    LEAVE 0

// void _cards_attach(id table) — card rows for this table
.globl _cards_attach
_cards_attach:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_cards
    ldr  x20, [x8]
    cbz  x20, Lca_done
    mov  x0, x19
    mov  x2, x20
    MSG1 Ls_setDataSource
    mov  x0, x19
    mov  x2, x20
    MSG1 Ls_setDelegate
    mov  x0, x19
    mov  x2, #1                       // full width: the cards bring their own margins
    MSG1 Ls_setStyle
    mov  x0, x19
    mov  x2, #-1                      // no blue highlight: the amber outline shows it
    MSG1 Ls_setSelectionHighlightStyle
    SELX1 Ls_setRowHeight
    mov  x0, x19
    LDD  d0, Lc_rowh
    bl   _objc_msgSend
    SELX1 Ls_setIntercellSpacing
    mov  x0, x19
    LDD  d0, Lc_0
    LDD  d1, Lc_0
    bl   _objc_msgSend
    mov  x0, x19                      // one column, as wide as the list
    mov  x2, #1                       // NSTableViewUniformColumnAutoresizingStyle
    MSG1 Ls_setColumnAutoresizingStyle
    mov  x0, x19
    MSG0 Ls_sizeLastColumnToFit
    mov  x0, x19                      // no scroll bar beside the cards (trackpad still scrolls)
    MSG0 Ls_enclosingScrollView
    cbz  x0, Lca_done
    mov  x2, #0
    MSG1 Ls_setHasVerticalScroller
Lca_done:
    LEAVE 0

// - (CGFloat)tableView:t heightOfRow:(NSInteger)row
_cd_height:
    LDD  d0, Lc_rowh
    ret

// - (void)tableViewSelectionDidChange:n — as the controller, then redraw the
//   People outline (Rooms is redrawn by _ui_select_room)
_cd_selchange:
    ENTER 0
    mov  x19, x2
    bl   _ds_selchange
    mov  x0, x19
    MSG0 Ls_object
    ADRL x8, _g_people_table
    ldr  x9, [x8]
    cmp  x0, x9
    b.ne Lcs_done
    MSG0 Ls_reloadData
Lcs_done:
    LEAVE 0

// - (NSView *)tableView:t viewForTableColumn:col row:(NSInteger)row
_cd_view:
    ENTER 160
    // locals: [96] row width   [112] fingerprint[16]   [160] second line[96]
    mov  x19, x2
    mov  x20, x4
    mov  x0, x3
    MSG0 Ls_width
    str  d0, [sp, #96]
    ADRL x8, _g_rooms_table
    ldr  x9, [x8]
    cmp  x19, x9
    b.eq Lcv_room
    ADRL x8, _g_people_table
    ldr  x9, [x8]
    cmp  x19, x9
    b.eq Lcv_person
Lcv_nil:
    mov  x0, #0
    LEAVE 160

Lcv_room:
    ADRL x8, _g_room_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lcv_ad
    ADRL x8, _g_rooms
    add  x21, x8, x20, lsl #ROOM_SHIFT
    ldr  x9, [x21, #R_ID]
    ADRL x22, Lk_private
    ADRL x8, Lk_home
    cmp  x9, #HOME_ID
    csel x22, x8, x22, eq
    ADRL x8, Lk_web
    cmp  x9, #WEB_ID
    csel x22, x8, x22, eq
    ADRL x8, Lk_news
    cmp  x9, #NEWS_ID
    csel x22, x8, x22, eq
    ADRL x8, Lk_main
    cmp  x20, #0
    csel x22, x8, x22, eq
    ldr  x0, [x21, #R_STORE]
    bl   _cd_last
    mov  x23, x0
    cbnz x23, 1f
    ldr  x0, [x22, #16]
    bl   _nsstr
    mov  x23, x0
1:  ADRL x8, _g_cur_room
    ldr  x9, [x8]
    cmp  x9, x20
    cset x5, eq
    ldr  x0, [x22]
    ldr  x1, [x22, #8]
    add  x2, x21, #R_NAME
    mov  x3, x23
    ldr  x4, [x21, #R_UNREAD]
    ldr  d0, [sp, #96]
    bl   _cd_card
    LEAVE 160

Lcv_ad:                               // someone else's listed room (listed.s): click to ask
    sub  x0, x20, x9
    bl   _ad_nth
    cbz  x0, Lcv_nil
    mov  x21, x0
    mov  x1, #1
    bl   _ad_field
    str  x0, [sp]
    mov  x0, x21
    bl   _ad_asked
    mov  x22, x0
    mov  x0, x21
    bl   _ad_away
    ADRL x2, Ls_ad_ask
    ADRL x8, Ls_ad_away
    cmp  x0, #0
    csel x2, x8, x2, ne
    ADRL x8, Ls_ad_asked
    cmp  x22, #0
    csel x2, x8, x2, ne
    add  x0, sp, #160
    mov  x1, #96
    bl   _snprintf
    add  x0, sp, #160
    bl   _nsstr
    mov  x23, x0
    mov  x0, x21
    mov  x1, #0
    bl   _ad_field
    mov  x2, x0
    ADRL x0, Ls_y_door
    mov  x1, #0xD158                  // green: open to ask
    movk x1, #0x30, lsl #16
    mov  x3, x23
    mov  x4, #0
    mov  x5, #0
    ldr  d0, [sp, #96]
    bl   _cd_card
    LEAVE 160

Lcv_person:
    ADRL x8, _g_node_count
    ldr  x9, [x8]
    cmp  x20, x9
    b.hs Lcv_bitchat
    ADRL x8, _g_nodes
    add  x21, x8, x20, lsl #NODE_SHIFT
    ldr  x0, [x21, #N_ID]
    add  x1, sp, #112
    bl   _fp
    str  x0, [sp]
    mov  x0, #0
    bl   _time
    ldr  x9, [x21, #N_SEEN]
    sub  x9, x0, x9
    mov  x22, #0x999E                 // grey: not heard from lately
    movk x22, #0x99, lsl #16
    ADRL x2, Ls_pp_away
    cmp  x9, #60
    b.gt Lcv_pfmt
    ldr  x9, [x21, #N_HOPS]
    str  x9, [sp, #8]
    mov  x22, #0x9E0A                 // amber: reached through other Macs
    movk x22, #0xFF, lsl #16
    ADRL x2, Ls_pp_hops
    cmp  x9, #1
    b.gt Lcv_pfmt
    mov  x22, #0xD158                 // green: in Bluetooth range
    movk x22, #0x30, lsl #16
    ldr  x9, [x21, #N_RSSI]
    str  x9, [sp, #8]
    ADRL x2, Ls_pp_near
    cbnz x9, Lcv_pfmt
    ADRL x2, Ls_pp_near0
Lcv_pfmt:
    add  x0, sp, #160
    mov  x1, #96
    bl   _snprintf
    add  x0, sp, #160
    bl   _nsstr
    mov  x23, x0
    mov  x0, x19
    MSG0 Ls_selectedRow
    cmp  x0, x20
    cset x24, eq
    mov  x0, x21
    bl   _node_name
    mov  x2, x0
    ADRL x0, Ls_y_person
    mov  x1, x22
    mov  x3, x23
    mov  x4, #0
    mov  x5, x24
    ldr  d0, [sp, #96]
    bl   _cd_card
    LEAVE 160

Lcv_bitchat:                          // someone on bitchat (bc_ble.s): orange, walled off,
    sub  x0, x20, x9                  //   nothing to click
    bl   _bc_person
    cbz  x0, Lcv_nil
    mov  x21, x0
    add  x1, sp, #160
    mov  x2, #96
    bl   _bc_person_line
    add  x0, sp, #160
    bl   _nsstr
    mov  x23, x0
    add  x2, x21, #BT_NICK
    ADRL x0, Ls_y_bitchat
    mov  x1, #0x9500                  // bitchat's switch colour
    movk x1, #0xFF, lsl #16
    mov  x3, x23
    mov  x4, #0
    mov  x5, #0
    ldr  d0, [sp, #96]
    bl   _cd_card
    LEAVE 160

// ---------------------------------------------------------------------------
// id _cd_card(const char *symbol, long 0xRRGGBB, const char *title,
//             NSString *second, long badge, int selected, double width /*d0*/)
// ---------------------------------------------------------------------------
_cd_card:
    ENTER 96
    // locals: [96] width [104] symbol [112] colour [120] title [128] second
    //         [136] badge [144] selected [160] badge text[32]
    str  d0, [sp, #96]
    stp  x0, x1, [sp, #104]
    stp  x2, x3, [sp, #120]
    stp  x4, x5, [sp, #136]
    CLS  Ls_NSView
    MSG0 Ls_alloc
    mov  x19, x0
    SELX1 Ls_initWithFrame
    mov  x0, x19
    LDD  d0, Lc_0
    LDD  d1, Lc_0
    ldr  d2, [sp, #96]
    LDD  d3, Lc_rowh
    bl   _objc_msgSend
    MSG0 Ls_autorelease
    mov  x19, x0                      // the row

    mov  x0, x19                      // the card, 4 pt apart
    LDD  d0, Lc_2
    LDD  d1, Lc_3
    ldr  d2, [sp, #96]
    LDD  d4, Lc_4
    fsub d2, d2, d4
    LDD  d3, Lc_cardh
    bl   _plain_view
    mov  x20, x0
    mov  x2, #2                       // WidthSizable
    MSG1 Ls_setAutoresizingMask
    mov  x0, x20
    mov  x1, #0x2426
    movk x1, #0x22, lsl #16
    LDD  d0, Lc_r16
    bl   _card
    ldr  x9, [sp, #144]
    cbz  x9, Lcc_icon
    mov  x0, x20
    MSG0 Ls_layer
    mov  x21, x0
    cbz  x21, Lcc_icon
    SELX1 Ls_setBorderWidth
    mov  x0, x21
    LDD  d0, Lc_2
    bl   _objc_msgSend
    mov  x0, #0x9E0A
    movk x0, #0xFF, lsl #16
    bl   _rgb
    MSG0 Ls_CGColor
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setBorderColor

Lcc_icon:
    mov  x0, x20                      // coloured round icon
    ADRL x8, Lf_icon
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _plain_view
    mov  x21, x0
    ldr  x1, [sp, #112]
    LDD  d0, Lc_r17
    bl   _card
    ldr  x0, [sp, #104]
    bl   _cd_symbol
    cbz  x0, Lcc_text
    mov  x22, x0
    CLS  Ls_NSImageView
    mov  x2, x22
    MSG1 Ls_imageViewWithImage
    mov  x22, x0
    SELX1 Ls_setFrame
    mov  x0, x22
    ADRL x8, Lf_glyph
    ldp  d0, d1, [x8]
    ldp  d2, d3, [x8, #16]
    bl   _objc_msgSend
    CLS  Ls_NSColor
    MSG0 Ls_whiteColor
    mov  x2, x0
    mov  x0, x22
    MSG1 Ls_setContentTintColor
    mov  x0, x21
    mov  x2, x22
    MSG1 Ls_addSubview

Lcc_text:
    ldr  x0, [sp, #120]               // the name, bold
    mov  x1, #2
    mov  x2, #1
    mov  x3, x20
    LDD  d0, Lc_tx
    LDD  d1, Lc_ty
    bl   Lcc_textw
    LDD  d3, Lc_th
    LDD  d4, Lc_s14
    bl   _mk_label
    ADRL x0, Ls_empty                 // the second line, dim
    mov  x1, #2
    mov  x2, #0
    mov  x3, x20
    LDD  d0, Lc_tx
    LDD  d1, Lc_sy
    bl   Lcc_textw
    LDD  d3, Lc_sh
    LDD  d4, Lc_s115
    bl   _mk_label
    bl   _dim_label
    ldr  x2, [sp, #128]
    cbz  x2, Lcc_badge
    MSG1 Ls_setStringValue

Lcc_badge:
    ldr  x9, [sp, #136]
    cmp  x9, #0
    b.le Lcc_done
    str  x9, [sp]
    add  x0, sp, #160
    mov  x1, #32
    ADRL x2, Ls_badge_fmt
    bl   _snprintf
    add  x0, sp, #160
    mov  x1, #1                       // MinXMargin: stays on the right
    mov  x2, #1
    mov  x3, x20
    ldr  d0, [sp, #96]
    LDD  d4, Lc_bx
    fsub d0, d0, d4
    LDD  d1, Lc_by
    LDD  d2, Lc_bw
    LDD  d3, Lc_bh
    LDD  d4, Lc_s11
    bl   _mk_label
    mov  x21, x0
    mov  x2, #1                       // NSTextAlignmentCenter (arm64 values)
    MSG1 Ls_setAlignment
    CLS  Ls_NSColor
    MSG0 Ls_blackColor
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setTextColor
    mov  x0, x21
    mov  x1, #0x9E0A
    movk x1, #0xFF, lsl #16
    LDD  d0, Lc_r8
    bl   _card
Lcc_done:
    mov  x0, x19
    LEAVE 96

// d2 = the text's width for this card ([sp, #96] row width, [sp, #136] badge);
//   called from _cd_card, so it reads _cd_card's frame through x29
Lcc_textw:
    ldr  d2, [x29, #64]               // x29 = sp + 32 in _cd_card: [sp, #96]
    LDD  d4, Lc_tright
    fsub d2, d2, d4
    ldr  x9, [x29, #104]              // [sp, #136]
    cmp  x9, #0
    b.le 1f
    LDD  d4, Lc_tbadge
    fsub d2, d2, d4
1:  ret

// id _cd_symbol(const char *name) — an SF Symbol at the cards' size, or nil
.globl _cd_symbol
_cd_symbol:
    ENTER 0
    bl   _symbol_image
    mov  x19, x0
    cbz  x19, Lsy_done
    CLS  Ls_NSImageSymbolConfiguration
    mov  x20, x0
    cbz  x20, Lsy_done
    SELX1 Ls_cfgPointWeight
    mov  x0, x20
    LDD  d0, Lc_gsize
    LDD  d1, Lc_gweight
    bl   _objc_msgSend
    cbz  x0, Lsy_done
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_withConfig
    cbz  x0, Lsy_done
    mov  x19, x0
Lsy_done:
    mov  x0, x19
    LEAVE 0

// NSString *_cd_last(NSTextStorage *store) — the transcript's last line without
//   its time, or nil when there is none
_cd_last:
    ENTER 0
    cbz  x0, Lcl_nil
    MSG0 Ls_string
    mov  x19, x0
    cbz  x19, Lcl_nil
    CLS  Ls_NSCharacterSet
    MSG0 Ls_wsnl
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_trim
    mov  x19, x0
    MSG0 Ls_length
    cbz  x0, Lcl_nil
    ADRL x0, Ls_nl
    bl   _nsstr
    mov  x20, x0
    SELX1 Ls_rangeOpts
    mov  x0, x19
    mov  x2, x20
    mov  x3, #4                       // NSBackwardsSearch
    bl   _objc_msgSend
    mov  x9, #-1
    lsr  x9, x9, #1                   // NSNotFound
    cmp  x0, x9
    b.eq Lcl_time
    add  x2, x0, #1
    mov  x0, x19
    MSG1 Ls_substrFrom
    mov  x19, x0
Lcl_time:
    ADRL x0, Ls_2sp                   // "HH:MM:SS  text"
    bl   _nsstr
    mov  x20, x0
    SELX1 Ls_rangeOf
    mov  x0, x19
    mov  x2, x20
    bl   _objc_msgSend
    cmp  x0, #12
    b.hs Lcl_out
    add  x2, x0, #2
    mov  x0, x19
    MSG1 Ls_substrFrom
    mov  x19, x0
Lcl_out:
    mov  x0, x19
    LEAVE 0
Lcl_nil:
    mov  x0, #0
    LEAVE 0

// ---------------------------------------------------------------------------
// id _cd_round(const char *symbol, const char *selname, mask, id parent,
//              long 0xRRGGBB, int dark_glyph, frame d0-d3)
//   a round icon button (36 x 36), like the iPhone's mic and send buttons
// ---------------------------------------------------------------------------
.globl _cd_round
_cd_round:
    ENTER 32
    stp  d0, d1, [sp, #96]
    stp  d2, d3, [sp, #112]
    mov  x19, x0
    mov  x20, x1
    mov  x21, x2
    mov  x22, x3
    mov  x23, x4
    mov  x24, x5
    mov  x0, x20
    bl   _sel_registerName
    mov  x20, x0
    mov  x0, x19
    bl   _cd_symbol
    mov  x19, x0
    CLS  Ls_NSButton
    mov  x2, x19
    ADRL x8, _g_ctl
    ldr  x3, [x8]
    mov  x4, x20
    MSG3 Ls_buttonWithImage
    mov  x19, x0
    SELX1 Ls_setFrame
    mov  x0, x19
    ldp  d0, d1, [sp, #96]
    ldp  d2, d3, [sp, #112]
    bl   _objc_msgSend
    mov  x0, x19
    mov  x2, #0
    MSG1 Ls_setBordered
    mov  x0, x19
    mov  x2, x21
    MSG1 Ls_setAutoresizingMask
    mov  x0, x19
    mov  x1, x23
    LDD  d0, Lc_r18
    bl   _card
    CLS  Ls_NSColor
    MSG0 Ls_whiteColor
    cbz  x24, 1f
    CLS  Ls_NSColor
    MSG0 Ls_blackColor
1:  mov  x2, x0
    mov  x0, x19
    MSG1 Ls_setContentTintColor
    mov  x0, x22
    mov  x2, x19
    MSG1 Ls_addSubview
    mov  x0, x19
    LEAVE 32

.section __TEXT,__cstring,cstring_literals
Ls_cls:              .asciz "AMeshCards"
Ls_NSObject:         .asciz "NSObject"
Ls_NSView:           .asciz "NSView"
Ls_NSImageView:      .asciz "NSImageView"
Ls_NSColor:          .asciz "NSColor"
Ls_NSButton:         .asciz "NSButton"
Ls_NSCharacterSet:   .asciz "NSCharacterSet"
Ls_NSImageSymbolConfiguration: .asciz "NSImageSymbolConfiguration"
Ls_p_tds:            .asciz "NSTableViewDataSource"
Ls_p_tdl:            .asciz "NSTableViewDelegate"
Ls_m_rows:           .asciz "numberOfRowsInTableView:"
Ls_m_view:           .asciz "tableView:viewForTableColumn:row:"
Ls_m_height:         .asciz "tableView:heightOfRow:"
Ls_m_sel:            .asciz "tableViewSelectionDidChange:"
Ls_ty_rows:          .asciz "q@:@"
Ls_ty_view:          .asciz "@@:@@q"
Ls_ty_height:        .asciz "d@:@q"
Ls_ty_v1:            .asciz "v@:@"
Ls_new:              .asciz "new"
Ls_alloc:            .asciz "alloc"
Ls_autorelease:      .asciz "autorelease"
Ls_initWithFrame:    .asciz "initWithFrame:"
Ls_setFrame:         .asciz "setFrame:"
Ls_setDataSource:    .asciz "setDataSource:"
Ls_setDelegate:      .asciz "setDelegate:"
Ls_setStyle:         .asciz "setStyle:"
Ls_setSelectionHighlightStyle: .asciz "setSelectionHighlightStyle:"
Ls_setRowHeight:     .asciz "setRowHeight:"
Ls_setIntercellSpacing: .asciz "setIntercellSpacing:"
Ls_object:           .asciz "object"
Ls_reloadData:       .asciz "reloadData"
Ls_selectedRow:      .asciz "selectedRow"
Ls_width:            .asciz "width"
Ls_layer:            .asciz "layer"
Ls_setBorderWidth:   .asciz "setBorderWidth:"
Ls_setBorderColor:   .asciz "setBorderColor:"
Ls_CGColor:          .asciz "CGColor"
Ls_setAutoresizingMask: .asciz "setAutoresizingMask:"
Ls_imageViewWithImage: .asciz "imageViewWithImage:"
Ls_whiteColor:       .asciz "whiteColor"
Ls_blackColor:       .asciz "blackColor"
Ls_setContentTintColor: .asciz "setContentTintColor:"
Ls_addSubview:       .asciz "addSubview:"
Ls_setStringValue:   .asciz "setStringValue:"
Ls_setAlignment:     .asciz "setAlignment:"
Ls_setTextColor:     .asciz "setTextColor:"
Ls_cfgPointWeight:   .asciz "configurationWithPointSize:weight:"
Ls_withConfig:       .asciz "imageWithSymbolConfiguration:"
Ls_string:           .asciz "string"
Ls_wsnl:             .asciz "whitespaceAndNewlineCharacterSet"
Ls_trim:             .asciz "stringByTrimmingCharactersInSet:"
Ls_length:           .asciz "length"
Ls_rangeOpts:        .asciz "rangeOfString:options:"
Ls_rangeOf:          .asciz "rangeOfString:"
Ls_substrFrom:       .asciz "substringFromIndex:"
Ls_buttonWithImage:  .asciz "buttonWithImage:target:action:"
Ls_setBordered:      .asciz "setBordered:"
Ls_enclosingScrollView: .asciz "enclosingScrollView"
Ls_setColumnAutoresizingStyle: .asciz "setColumnAutoresizingStyle:"
Ls_sizeLastColumnToFit: .asciz "sizeLastColumnToFit"
Ls_setHasVerticalScroller: .asciz "setHasVerticalScroller:"
Ls_nl:               .asciz "\n"
Ls_2sp:              .asciz "  "
Ls_empty:            .asciz ""
Ls_badge_fmt:        .asciz "%ld"
Ls_pp_near:          .asciz "key %s  \302\267  nearby  \302\267  %ld dBm"
Ls_pp_near0:         .asciz "key %s  \302\267  nearby"
Ls_pp_hops:          .asciz "key %s  \302\267  %ld hops"
Ls_pp_away:          .asciz "key %s  \302\267  away"
Ls_y_globe:          .asciz "globe"
Ls_y_house:          .asciz "house.fill"
Ls_y_safari:         .asciz "safari.fill"
Ls_y_news:           .asciz "newspaper.fill"
Ls_y_lock:           .asciz "lock.fill"
Ls_y_door:           .asciz "door.left.hand.open"
Ls_ad_ask:           .asciz "%s\342\200\231s room \302\267 click to ask to join"
Ls_ad_away:          .asciz "%s\342\200\231s room \302\267 away now \302\267 click to ask to join"
Ls_ad_asked:         .asciz "Asked %s \302\267 you join when they say yes"
Ls_y_person:         .asciz "person.fill"
Ls_y_bitchat:        .asciz "antenna.radiowaves.left.and.right"
Ls_k_main:           .asciz "Everyone on the mesh"
Ls_k_home:           .asciz "Lights, locks and scenes"
Ls_k_web:            .asciz "Pages through a Mac with internet"
Ls_k_news:           .asciz "Headlines from Macs with internet"
Ls_k_private:        .asciz "Invite-only"
