// ble.s — CoreBluetooth plumbing for asmmesh.
//
// Every Mac plays both Bluetooth LE roles at once:
//
//   peripheral  advertises the asmmesh service, which has one writable
//               characteristic: the "inbox". Whatever a neighbour writes there
//               is handed to _mesh_receive.
//   central     scans for that service, connects to every Mac it finds,
//               discovers its inbox, and writes packets into it.
//
// So a message from A to B travels A(central) -> B(peripheral inbox). When a
// link drops, the peer is forgotten and the scan is restarted, so the other
// Mac is rediscovered as soon as it is back in range.
//
// Peer table: PEER_MAX entries of 32 bytes
//   +0   CBPeripheral *      retained
//   +8   CBCharacteristic *  retained; the peer's inbox, 0 until discovered
//   +16  state               ST_FREE / ST_CONNECTING / ST_DISCOVERING / ST_READY
//
// Both managers are created with queue:nil, so every callback runs on the
// main thread and nothing here needs a lock.

.include "macros.inc"

.set PEER_MAX,        16
.set ST_FREE,         0
.set ST_CONNECTING,   1
.set ST_DISCOVERING,  2
.set ST_READY,        3
.set RXBUF_SIZE,      512
.set CB_POWERED_ON,   5

// ---------------------------------------------------------------------------
.data
.p2align 3
.globl _g_cm
_g_cm:          .quad 0
.globl _g_pm
_g_pm:          .quad 0
_g_svc_uuid:    .quad 0
_g_chr_uuid:    .quad 0
_g_id_uuid:     .quad 0
.zerofill __DATA,__bss,_g_peers,512,4
.zerofill __DATA,__bss,_g_rxbuf,512,4

// ---------------------------------------------------------------------------
.text
.p2align 2

// ---------------------------------------------------------------------------
// void _ble_start(void) — UUIDs, then the central and peripheral managers.
// Their state callbacks do the rest once Bluetooth reports powered-on.
// ---------------------------------------------------------------------------
.globl _ble_start
_ble_start:
    ENTER 0
    CLS  Ls_CBUUID
    mov  x19, x0
    ADRL x0, Ls_svc_uuid_str
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    ADRL x8, _g_svc_uuid
    str  x0, [x8]
    ADRL x0, Ls_chr_uuid_str
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    ADRL x8, _g_chr_uuid
    str  x0, [x8]
    ADRL x0, Ls_id_uuid_str
    bl   _nsstr
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_UUIDWithString
    MSG0 Ls_retain
    ADRL x8, _g_id_uuid
    str  x0, [x8]
    bl   _hueble_init

    ADRL x8, _g_ctl
    ldr  x20, [x8]
    CLS  Ls_CBCentralManager
    MSG0 Ls_alloc
    mov  x2, x20
    mov  x3, #0                       // queue: nil -> main queue
    MSG2 Ls_initWithDelegate
    ADRL x8, _g_cm
    str  x0, [x8]
    CLS  Ls_CBPeripheralManager
    MSG0 Ls_alloc
    mov  x2, x20
    mov  x3, #0
    MSG2 Ls_initWithDelegate
    ADRL x8, _g_pm
    str  x0, [x8]
    LEAVE 0

// id _array1(id obj) — [NSArray arrayWithObject:obj]
_array1:
    ENTER 0
    mov  x19, x0
    CLS  Ls_NSArray
    mov  x2, x19
    MSG1 Ls_arrayWithObject
    LEAVE 0

// id _array2(id a, id b) — [NSArray arrayWithObjects:(id[]){a,b} count:2]
_array2:
    ENTER 16
    stp  x0, x1, [sp, #96]
    CLS  Ls_NSArray
    add  x2, sp, #96
    mov  x3, #2
    MSG2 Ls_arrayWithObjectsCount
    LEAVE 16

// void _ble_scan(void) — (re)start scanning for the asmmesh service.
// Restarting clears CoreBluetooth's duplicate filter, so a Mac we lost is
// reported again as soon as it is advertising in range.
_ble_scan:
    ENTER 0
    ADRL x8, _g_cm
    ldr  x19, [x8]
    cbz  x19, Lscan_done
    mov  x0, x19
    MSG0 Ls_state
    cmp  x0, #CB_POWERED_ON
    b.ne Lscan_done
    mov  x0, x19
    MSG0 Ls_stopScan
    CLS  Ls_NSNumber                  // every advertiser, every time: fresh signal strengths
    mov  x2, #1
    MSG1 Ls_numberWithBool
    mov  x20, x0
    LDGOT x8, _CBCentralManagerScanOptionAllowDuplicatesKey
    ldr  x21, [x8]
    CLS  Ls_NSDictionary
    mov  x2, x20
    mov  x3, x21
    MSG2 Ls_dictionaryWithObject
    mov  x3, x0
    mov  x0, x19
    mov  x2, #0                       // no service filter: we sort them out ourselves
    MSG2 Ls_scanForPeripherals
Lscan_done:
    LEAVE 0

// void _ble_cancel(id peripheral) — drop the link; didDisconnect cleans up
.globl _ble_cancel
_ble_cancel:
    ENTER 0
    mov  x19, x0
    ADRL x8, _g_cm
    ldr  x0, [x8]
    mov  x2, x19
    MSG1 Ls_cancelPeripheralConnection
    LEAVE 0

// ---------------------------------------------------------------------------
// Peer table helpers
// ---------------------------------------------------------------------------

// long _peer_find(id peripheral) -> index, or -1
_peer_find:
    ADRL x8, _g_peers
    mov  x9, #0
Lpf_loop:
    cmp  x9, #PEER_MAX
    b.hs Lpf_none
    ldr  x10, [x8, #16]
    cbz  x10, Lpf_next
    ldr  x10, [x8]
    cmp  x10, x0
    b.eq Lpf_found
Lpf_next:
    add  x8, x8, #32
    add  x9, x9, #1
    b    Lpf_loop
Lpf_none:
    mov  x0, #-1
    ret
Lpf_found:
    mov  x0, x9
    ret

// long _peer_alloc(id peripheral) -> index (state CONNECTING), or -1 if full
_peer_alloc:
    ENTER 0
    mov  x19, x0
    ADRL x20, _g_peers
    mov  x21, #0
Lpa_loop:
    cmp  x21, #PEER_MAX
    b.hs Lpa_full
    ldr  x9, [x20, #16]
    cbz  x9, Lpa_take
    add  x20, x20, #32
    add  x21, x21, #1
    b    Lpa_loop
Lpa_take:
    mov  x0, x19
    MSG0 Ls_retain
    str  x0, [x20]
    str  xzr, [x20, #8]
    mov  x9, #ST_CONNECTING
    str  x9, [x20, #16]
    mov  x0, x21
    LEAVE 0
Lpa_full:
    mov  x0, #-1
    LEAVE 0

// void _peer_remove(long index) — release and clear the entry
_peer_remove:
    ENTER 0
    ADRL x8, _g_peers
    add  x19, x8, x0, lsl #5
    ldr  x0, [x19, #8]
    cbz  x0, Lpr_1
    MSG0 Ls_release
Lpr_1:
    ldr  x0, [x19]
    cbz  x0, Lpr_2
    MSG0 Ls_release
Lpr_2:
    stp  xzr, xzr, [x19]
    stp  xzr, xzr, [x19, #16]
    LEAVE 0

// void _peers_reset(void) — forget every peer (Bluetooth went off or reset)
_peers_reset:
    ENTER 0
    ADRL x19, _g_peers
    mov  x20, #0
Lrs_loop:
    cmp  x20, #PEER_MAX
    b.hs Lrs_done
    ldr  x9, [x19, #16]
    cbz  x9, Lrs_next
    mov  x0, x20
    bl   _peer_remove
Lrs_next:
    add  x19, x19, #32
    add  x20, x20, #1
    b    Lrs_loop
Lrs_done:
    LEAVE 0

// long _ble_ready_count(void) — peers whose inbox we can write to
.globl _ble_ready_count
_ble_ready_count:
    ADRL x8, _g_peers
    mov  x9, #0
    mov  x0, #0
Lrc_loop:
    cmp  x9, #PEER_MAX
    b.hs Lrc_done
    ldr  x10, [x8, #16]
    cmp  x10, #ST_READY
    cinc x0, x0, eq
    add  x8, x8, #32
    add  x9, x9, #1
    b    Lrc_loop
Lrc_done:
    ret

// ---------------------------------------------------------------------------
// long _ble_write_peer(long index, const void *bytes, size_t len) -> 1 if queued
//   Write-with-response, so CoreBluetooth splits anything over the link MTU
//   into a long (prepared) write and the other side reassembles it.
// ---------------------------------------------------------------------------
.globl _ble_write_peer
_ble_write_peer:
    ENTER 0
    ADRL x8, _g_peers
    add  x19, x8, x0, lsl #5
    ldr  x9, [x19, #16]
    cmp  x9, #ST_READY
    b.ne Lwp_no
    mov  x20, x1
    mov  x21, x2
    CLS  Ls_NSData
    mov  x2, x20
    mov  x3, x21
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    ldr  x0, [x19]
    ldr  x3, [x19, #8]
    mov  x4, #0                       // CBCharacteristicWriteWithResponse
    MSG3 Ls_writeValue
    mov  x0, #1
    LEAVE 0
Lwp_no:
    mov  x0, #0
    LEAVE 0

// long _ble_broadcast(const void *bytes, size_t len) -> number of peers written
.globl _ble_broadcast
_ble_broadcast:
    ENTER 0
    mov  x19, x0
    mov  x20, x1
    mov  x21, #0
    mov  x22, #0
Lbc_loop:
    cmp  x21, #PEER_MAX
    b.hs Lbc_done
    mov  x0, x21
    mov  x1, x19
    mov  x2, x20
    bl   _ble_write_peer
    add  x22, x22, x0
    add  x21, x21, #1
    b    Lbc_loop
Lbc_done:
    mov  x0, x19                      // and over FM, when the radio is on (fm.s)
    mov  x1, x20
    bl   _fm_tx_packet
    add  x0, x22, x0
    LEAVE 0

// Every other Bluetooth LE device we hear lives in near.s (_nearby_seen).

// ===========================================================================
// Central role — CBCentralManagerDelegate / CBPeripheralDelegate methods
// ===========================================================================

// - (void)centralManagerDidUpdateState:(CBCentralManager *)cm
.globl _ble_cm_state
_ble_cm_state:
    ENTER 0
    mov  x19, x2
    mov  x0, x19
    MSG0 Ls_state
    mov  x20, x0
    bl   _peers_reset
    cmp  x20, #CB_POWERED_ON
    b.ne Lcs_off
    bl   _ble_scan
    ADRL x0, Ls_msg_scanning
    bl   _chat_line
    bl   _ui_update_status
    LEAVE 0
Lcs_off:
    cmp  x20, #3                      // unauthorized
    b.eq Lcs_unauth
    cmp  x20, #2                      // unsupported
    b.eq Lcs_unsup
    cmp  x20, #4                      // powered off
    b.eq Lcs_poweroff
    LEAVE 0                           // unknown / resetting: wait for the next update
Lcs_unauth:
    ADRL x19, Ls_msg_unauth
    b    Lcs_show
Lcs_unsup:
    ADRL x19, Ls_msg_unsup
    b    Lcs_show
Lcs_poweroff:
    ADRL x19, Ls_msg_off
Lcs_show:
    mov  x0, x19
    bl   _chat_line
    mov  x0, x19
    bl   _ui_set_status
    LEAVE 0

// - (void)centralManager:cm didDiscoverPeripheral:p advertisementData:ad RSSI:rssi
.globl _ble_cm_discover
_ble_cm_discover:
    ENTER 0
    mov  x19, x2                      // central
    mov  x20, x3                      // peripheral
    mov  x21, x4                      // advertisement data
    mov  x22, x5                      // RSSI
    LDGOT x8, _CBAdvertisementDataServiceUUIDsKey
    ldr  x2, [x8]
    mov  x0, x21
    MSG1 Ls_objectForKey
    mov  x23, x0                      // advertised services (may be nil)
    cbz  x23, Lcd_other
    ADRL x8, _g_svc_uuid
    ldr  x2, [x8]
    MSG1 Ls_containsObject
    tst  w0, #0xff
    b.ne Lcd_mesh
Lcd_other:
    LDGOT x8, _CBAdvertisementDataLocalNameKey
    ldr  x2, [x8]
    mov  x0, x21
    MSG1 Ls_objectForKey
    cbnz x0, Lcd_named
    mov  x0, x20
    MSG0 Ls_name
Lcd_named:
    mov  x24, #0
    cbz  x0, Lcd_rssi
    MSG0 Ls_UTF8String
    mov  x24, x0
Lcd_rssi:
    mov  x0, x22
    MSG0 Ls_integerValue
    mov  x2, x0
    mov  x0, x20
    mov  x1, x24
    mov  x3, x21
    bl   _nearby_seen
    mov  x0, x22                      // a sensor saying its readings? (sensors.s)
    MSG0 Ls_integerValue
    mov  x2, x0
    mov  x0, x20
    mov  x1, x24
    mov  x3, x21
    bl   _sens_seen
    mov  x0, x20                      // a SPIN remote? claim and connect it
    mov  x1, x24
    mov  x2, x21
    bl   _spin_seen
    cbnz x0, Lcd_done
    cbz  x23, Lcd_done
    bl   _hueble_adv
    mov  x2, x0
    mov  x0, x23
    MSG1 Ls_containsObject
    tst  w0, #0xff
    b.eq Lcd_done
    mov  x0, x20
    mov  x1, x24
    bl   _hueble_seen
    b    Lcd_done
Lcd_mesh:
    mov  x0, x20
    bl   _peer_find
    tbz  x0, #63, Lcd_done            // already tracking it
    mov  x0, x20
    bl   _peer_alloc
    tbnz x0, #63, Lcd_done            // table full
    mov  x0, x19
    mov  x2, x20
    mov  x3, #0
    MSG2 Ls_connectPeripheral
    ADRL x0, Ls_msg_found
    bl   _chat_line
Lcd_done:
    LEAVE 0

// - (void)centralManager:cm didConnectPeripheral:p
.globl _ble_cm_connect
_ble_cm_connect:
    ENTER 0
    mov  x19, x0                      // self
    mov  x20, x3                      // peripheral
    mov  x0, x20
    bl   _peer_find
    tbnz x0, #63, Lcc_unknown
    ADRL x8, _g_peers
    add  x21, x8, x0, lsl #5
    mov  x9, #ST_DISCOVERING
    str  x9, [x21, #16]
    mov  x0, x20
    mov  x2, x19
    MSG1 Ls_setDelegate
    ADRL x8, _g_svc_uuid
    ldr  x0, [x8]
    bl   _array1
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_discoverServices
    LEAVE 0
Lcc_unknown:
    mov  x0, x20                      // our SPIN remote?
    bl   _spin_connected
    cbnz x0, Lcc_done
    mov  x0, x20                      // Connect & Pair from the scanner?
    bl   _near_connected
    cbnz x0, Lcc_done
    mov  x0, x20
    bl   _dev_find_obj
    tbnz x0, #63, Lcc_cancel
    mov  x0, x20
    bl   _hueble_connected
    LEAVE 0
Lcc_cancel:
    mov  x0, x20
    bl   _ble_cancel
Lcc_done:
    LEAVE 0

// - (void)centralManager:cm didFailToConnectPeripheral:p error:e
// - (void)centralManager:cm didDisconnectPeripheral:p error:e
.globl _ble_cm_lost
_ble_cm_lost:
    ENTER 0
    mov  x21, x3
    mov  x0, x3
    bl   _peer_find
    tbnz x0, #63, Lcl_other
    ADRL x8, _g_peers
    add  x9, x8, x0, lsl #5
    ldr  x19, [x9, #16]               // state before we drop it
    ldr  x20, [x9, #24]               // its node id, if we learned it
    bl   _peer_remove                 // x0 is still the index
    cbz  x20, Lcl_state
    mov  x0, x20
    mov  x1, #0                       // no longer a direct neighbour: no signal
    bl   _node_set_rssi
    bl   _ui_lists_changed
Lcl_state:
    cmp  x19, #ST_READY
    b.ne Lcl_rescan
    bl   _ble_ready_count
    mov  x1, x0
    ADRL x0, Ls_fmt_lost
    bl   _chat_fmt
    bl   _ui_update_status
Lcl_rescan:
    bl   _ble_scan
    LEAVE 0
Lcl_other:
    mov  x0, x21
    bl   _spin_lost
    mov  x0, x21
    bl   _near_lost
    mov  x0, x21
    bl   _hueble_lost
    b    Lcl_rescan

// - (void)peripheral:p didDiscoverServices:error
.globl _ble_p_services
_ble_p_services:
    ENTER 0
    mov  x19, x2
    mov  x21, x3
    mov  x0, x19
    bl   _peer_find
    tbz  x0, #63, Lsv_mesh
    mov  x0, x19                      // our SPIN remote?
    mov  x1, x21
    bl   _spin_services
    cbnz x0, Lsv_done
    mov  x0, x19                      // being inspected from the scanner?
    mov  x1, x21
    bl   _near_services
    cbnz x0, Lsv_done
    mov  x0, x19                      // not a mesh peer: a Hue bulb?
    bl   _dev_find_obj
    tbnz x0, #63, Lsv_drop
    cbnz x21, Lsv_drop
    mov  x0, x19
    bl   _hueble_services
    LEAVE 0
Lsv_mesh:
    cbnz x21, Lsv_drop
    mov  x0, x19
    MSG0 Ls_services
    MSG0 Ls_firstObject
    cbz  x0, Lsv_drop
    mov  x20, x0                      // our service (we asked for only its UUID)
    ADRL x8, _g_chr_uuid
    ldr  x0, [x8]
    ADRL x8, _g_id_uuid
    ldr  x1, [x8]
    bl   _array2
    mov  x2, x0
    mov  x0, x19
    mov  x3, x20
    MSG2 Ls_discoverCharacteristics
    LEAVE 0
Lsv_drop:
    mov  x0, x19
    bl   _ble_cancel
Lsv_done:
    LEAVE 0

// - (void)peripheral:p didDiscoverCharacteristicsForService:s error:e
.globl _ble_p_chars
_ble_p_chars:
    ENTER 0
    mov  x19, x2                      // peripheral
    mov  x20, x3                      // service
    mov  x21, x4
    mov  x0, x19                      // our SPIN remote?
    mov  x1, x20
    mov  x2, x21
    bl   _spin_chars
    cbnz x0, Lch_ret
    mov  x0, x19                      // being inspected from the scanner?
    mov  x1, x20
    mov  x2, x21
    bl   _near_chars
    cbnz x0, Lch_ret
    cbnz x21, Lch_drop
    mov  x0, x19
    bl   _peer_find
    tbnz x0, #63, Lch_hue
    mov  x22, x0                      // peer index
    mov  x0, x20
    MSG0 Ls_characteristics
    mov  x23, x0                      // NSArray of characteristics
    MSG0 Ls_count
    mov  x24, x0
    mov  x21, #0                      // inbox found?
Lch_loop:
    cbz  x24, Lch_done
    sub  x24, x24, #1
    mov  x0, x23
    mov  x2, x24
    MSG1 Ls_objectAtIndex
    mov  x20, x0                      // characteristic
    MSG0 Ls_UUID
    ADRL x8, _g_chr_uuid
    ldr  x2, [x8]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.ne Lch_inbox
    mov  x0, x20
    MSG0 Ls_UUID
    ADRL x8, _g_id_uuid
    ldr  x2, [x8]
    MSG1 Ls_isEqual
    tst  w0, #0xff
    b.eq Lch_loop
    mov  x0, x19                      // identity: ask who this is
    mov  x2, x20
    MSG1 Ls_readValueForCharacteristic
    b    Lch_loop
Lch_inbox:
    ADRL x8, _g_peers
    add  x9, x8, x22, lsl #5
    ldr  x0, [x9, #8]
    cbz  x0, Lch_store
    MSG0 Ls_release
Lch_store:
    mov  x0, x20
    MSG0 Ls_retain
    ADRL x8, _g_peers
    add  x9, x8, x22, lsl #5
    str  x0, [x9, #8]
    mov  x21, #1
    b    Lch_loop
Lch_done:
    cbz  x21, Lch_drop                // no inbox: not an asmmesh we can talk to
    ADRL x8, _g_peers
    add  x9, x8, x22, lsl #5
    mov  x10, #ST_READY
    str  x10, [x9, #16]
    bl   _ble_ready_count
    mov  x1, x0
    ADRL x0, Ls_fmt_linked
    bl   _chat_fmt
    bl   _ui_update_status
    mov  x0, x22
    bl   _mesh_flush_to               // hand over everything we are carrying
    bl   _mesh_send_hello             // and introduce ourselves
    LEAVE 0
Lch_hue:
    mov  x0, x19
    mov  x1, x20
    bl   _hueble_chars
    LEAVE 0
Lch_drop:
    mov  x0, x19
    bl   _ble_cancel
Lch_ret:
    LEAVE 0

// - (void)peripheral:p didUpdateValueForCharacteristic:c error:e
//   The identity characteristic: 8 bytes, the neighbour's node id.
.globl _ble_p_value
_ble_p_value:
    ENTER 16
    mov  x19, x2
    mov  x20, x3
    mov  x21, x4
    mov  x0, x19                      // our SPIN remote?
    mov  x1, x20
    mov  x2, x21
    bl   _spin_value
    cbnz x0, Lpv_done
    mov  x0, x19                      // being inspected from the scanner?
    mov  x1, x20
    mov  x2, x21
    bl   _near_value
    cbnz x0, Lpv_done
    mov  x3, x20
    mov  x4, x21
    cbnz x4, Lpv_done
    mov  x0, x3
    MSG0 Ls_value
    cbz  x0, Lpv_done
    mov  x20, x0
    MSG0 Ls_length
    cmp  x0, #8
    b.lo Lpv_done
    mov  x0, x20
    MSG0 Ls_bytes
    ldr  x20, [x0]                    // node id (may be unaligned; fine on arm64)
    cbz  x20, Lpv_done
    mov  x0, x19
    bl   _peer_find
    tbnz x0, #63, Lpv_done
    ADRL x8, _g_peers
    add  x9, x8, x0, lsl #5
    str  x20, [x9, #24]
    mov  x0, x20
    mov  x1, #0
    mov  x2, #1                       // a direct neighbour
    bl   _node_touch
    bl   _ui_lists_changed
Lpv_done:
    LEAVE 16

// - (void)peripheral:p didReadRSSI:(NSNumber *)rssi error:e
.globl _ble_p_rssi
_ble_p_rssi:
    ENTER 0
    mov  x19, x2
    cbnz x4, Lrr_done
    mov  x0, x3
    MSG0 Ls_integerValue
    mov  x20, x0
    cmp  x20, #0
    b.ge Lrr_done                     // 127 / 0 mean "unavailable"
    mov  x0, x19
    bl   _peer_find
    tbnz x0, #63, Lrr_done
    ADRL x8, _g_peers
    add  x9, x8, x0, lsl #5
    ldr  x0, [x9, #24]
    cbz  x0, Lrr_done
    mov  x1, x20
    bl   _node_set_rssi
Lrr_done:
    LEAVE 0

// void _ble_read_rssi_all(void) — ask every linked neighbour for its signal
.globl _ble_read_rssi_all
_ble_read_rssi_all:
    ENTER 0
    ADRL x19, _g_peers
    mov  x20, #0
Lra_loop:
    cmp  x20, #PEER_MAX
    b.hs Lra_done
    ldr  x9, [x19, #16]
    cmp  x9, #ST_READY
    b.ne Lra_next
    ldr  x0, [x19]
    MSG0 Ls_readRSSI
Lra_next:
    add  x19, x19, #32
    add  x20, x20, #1
    b    Lra_loop
Lra_done:
    LEAVE 0

// - (void)peripheral:p didModifyServices:invalidated
//   The other Mac restarted or unpublished its service: drop the link and let
//   the rescan find it again when it is back.
.globl _ble_p_modify
_ble_p_modify:
    ENTER 0
    mov  x0, x2
    bl   _ble_cancel
    LEAVE 0

// ===========================================================================
// Peripheral role — CBPeripheralManagerDelegate methods
// ===========================================================================

// - (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)pm
//   Powered on: publish the service with its writable inbox characteristic.
.globl _ble_pm_state
_ble_pm_state:
    ENTER 0
    mov  x19, x2
    mov  x0, x19
    MSG0 Ls_state
    cmp  x0, #CB_POWERED_ON
    b.ne Lpm_done
    mov  x0, x19
    MSG0 Ls_removeAllServices
    CLS  Ls_CBMutableCharacteristic
    MSG0 Ls_alloc
    ADRL x8, _g_chr_uuid
    ldr  x2, [x8]
    mov  x3, #8                       // CBCharacteristicPropertyWrite
    mov  x4, #0                       // value: nil (dynamic)
    mov  x5, #2                       // CBAttributePermissionsWriteable
    MSG4 Ls_initCharacteristic
    mov  x20, x0                      // inbox
    CLS  Ls_CBMutableCharacteristic
    MSG0 Ls_alloc
    ADRL x8, _g_id_uuid
    ldr  x2, [x8]
    mov  x3, #2                       // CBCharacteristicPropertyRead
    mov  x4, #0                       // value: nil (answered per request)
    mov  x5, #1                       // CBAttributePermissionsReadable
    MSG4 Ls_initCharacteristic
    mov  x22, x0                      // identity
    CLS  Ls_CBMutableService
    MSG0 Ls_alloc
    ADRL x8, _g_svc_uuid
    ldr  x2, [x8]
    mov  x3, #1                       // primary: YES
    MSG2 Ls_initWithTypePrimary
    mov  x21, x0
    mov  x0, x20
    mov  x1, x22
    bl   _array2
    mov  x2, x0
    mov  x0, x21
    MSG1 Ls_setCharacteristics
    mov  x0, x19
    mov  x2, x21
    MSG1 Ls_addService
    mov  x0, x20
    MSG0 Ls_release
    mov  x0, x22
    MSG0 Ls_release
    mov  x0, x21
    MSG0 Ls_release
Lpm_done:
    LEAVE 0

// - (void)peripheralManager:pm didReceiveReadRequest:(CBATTRequest *)req
//   Someone read our identity characteristic: answer with our node id.
.globl _ble_pm_read
_ble_pm_read:
    ENTER 0
    mov  x19, x2
    mov  x20, x3
    mov  x0, x20
    MSG0 Ls_offset
    cbnz x0, Lrd_offset
    CLS  Ls_NSData
    ADRL x2, _g_node_id
    mov  x3, #8
    MSG2 Ls_dataWithBytes
    mov  x2, x0
    mov  x0, x20
    MSG1 Ls_setValue
    mov  x3, #0                       // CBATTErrorSuccess
    b    Lrd_respond
Lrd_offset:
    mov  x3, #7                       // CBATTErrorInvalidOffset
Lrd_respond:
    mov  x0, x19
    mov  x2, x20
    MSG2 Ls_respondToRequest
    LEAVE 0

// - (void)peripheralManager:pm didAddService:s error:e — start advertising it
.globl _ble_pm_added
_ble_pm_added:
    ENTER 0
    mov  x19, x2
    cbz  x4, Lad_ok
    mov  x0, x4
    bl   _err_cstr
    mov  x1, x0
    ADRL x0, Ls_fmt_adderr
    bl   _chat_fmt
    LEAVE 0
Lad_ok:
    ADRL x8, _g_svc_uuid
    ldr  x0, [x8]
    bl   _array1
    mov  x20, x0
    LDGOT x8, _CBAdvertisementDataServiceUUIDsKey
    ldr  x21, [x8]
    CLS  Ls_NSDictionary
    mov  x2, x20
    mov  x3, x21
    MSG2 Ls_dictionaryWithObject
    mov  x2, x0
    mov  x0, x19
    MSG1 Ls_startAdvertising
    LEAVE 0

// - (void)peripheralManagerDidStartAdvertising:pm error:e
.globl _ble_pm_adv
_ble_pm_adv:
    ENTER 0
    cbz  x3, Lav_ok
    mov  x0, x3
    bl   _err_cstr
    mov  x1, x0
    ADRL x0, Ls_fmt_adverr
    bl   _chat_fmt
    LEAVE 0
Lav_ok:
    ADRL x0, Ls_msg_adv
    bl   _chat_line
    LEAVE 0

// - (void)peripheralManager:pm didReceiveWriteRequests:(NSArray<CBATTRequest*> *)reqs
//   One ATT write, possibly a long write split into pieces with offsets.
//   Reassemble into _g_rxbuf, acknowledge once, then hand the packet on.
.globl _ble_pm_writes
_ble_pm_writes:
    ENTER 32
    // locals: [96] NSData *value   [104] offset   [112] length
    mov  x19, x2                      // peripheral manager
    mov  x20, x3                      // requests
    mov  x0, x20
    MSG0 Ls_count
    mov  x21, x0
    cbz  x21, Lpw_done
    mov  x22, #0                      // i
    mov  x23, #0                      // assembled length
Lpw_loop:
    cmp  x22, x21
    b.hs Lpw_respond
    mov  x0, x20
    mov  x2, x22
    MSG1 Ls_objectAtIndex
    mov  x24, x0
    MSG0 Ls_offset
    str  x0, [sp, #104]
    mov  x0, x24
    MSG0 Ls_value
    str  x0, [sp, #96]
    MSG0 Ls_length
    str  x0, [sp, #112]
    ldr  x9, [sp, #104]
    ldr  x10, [sp, #112]
    cmp  x9, #RXBUF_SIZE
    b.hs Lpw_next
    cmp  x10, #RXBUF_SIZE
    b.hs Lpw_next
    add  x11, x9, x10
    cmp  x11, #RXBUF_SIZE
    b.hi Lpw_next                     // would overflow: drop the piece
    cmp  x11, x23
    csel x23, x11, x23, hi
    cbz  x10, Lpw_next
    ldr  x0, [sp, #96]
    MSG0 Ls_bytes
    mov  x1, x0
    ADRL x0, _g_rxbuf
    ldr  x9, [sp, #104]
    add  x0, x0, x9
    ldr  x2, [sp, #112]
    bl   _memcpy
Lpw_next:
    add  x22, x22, #1
    b    Lpw_loop
Lpw_respond:
    mov  x0, x20
    MSG0 Ls_firstObject
    mov  x2, x0
    mov  x0, x19
    mov  x3, #0                       // CBATTErrorSuccess
    MSG2 Ls_respondToRequest
    cbz  x23, Lpw_done
    ADRL x0, _g_rxbuf
    mov  x1, x23
    bl   _mesh_receive
Lpw_done:
    LEAVE 32

// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
// The asmmesh service and its inbox characteristic. Random v4 UUIDs; every
// copy of asmmesh must use the same pair to find each other.
Ls_svc_uuid_str:       .asciz "6E3A1C52-4B8F-4E1D-9A7C-2F5B8D0E4A11"
Ls_chr_uuid_str:       .asciz "6E3A1C53-4B8F-4E1D-9A7C-2F5B8D0E4A11"
Ls_id_uuid_str:        .asciz "6E3A1C54-4B8F-4E1D-9A7C-2F5B8D0E4A11"
Ls_arrayWithObjectsCount: .asciz "arrayWithObjects:count:"
Ls_UUID:               .asciz "UUID"
Ls_isEqual:            .asciz "isEqual:"
Ls_readValueForCharacteristic: .asciz "readValueForCharacteristic:"
Ls_integerValue:       .asciz "integerValue"
Ls_readRSSI:           .asciz "readRSSI"
Ls_setValue:           .asciz "setValue:"
Ls_NSNumber:           .asciz "NSNumber"
Ls_numberWithBool:     .asciz "numberWithBool:"
Ls_objectForKey:       .asciz "objectForKey:"
Ls_containsObject:     .asciz "containsObject:"
Ls_name:               .asciz "name"
Ls_UTF8String:         .asciz "UTF8String"

Ls_CBUUID:             .asciz "CBUUID"
Ls_CBCentralManager:   .asciz "CBCentralManager"
Ls_CBPeripheralManager: .asciz "CBPeripheralManager"
Ls_CBMutableCharacteristic: .asciz "CBMutableCharacteristic"
Ls_CBMutableService:   .asciz "CBMutableService"
Ls_NSArray:            .asciz "NSArray"
Ls_NSData:             .asciz "NSData"
Ls_NSDictionary:       .asciz "NSDictionary"

Ls_UUIDWithString:     .asciz "UUIDWithString:"
Ls_alloc:              .asciz "alloc"
Ls_retain:             .asciz "retain"
Ls_release:            .asciz "release"
Ls_initWithDelegate:   .asciz "initWithDelegate:queue:"
Ls_arrayWithObject:    .asciz "arrayWithObject:"
Ls_state:              .asciz "state"
Ls_stopScan:           .asciz "stopScan"
Ls_scanForPeripherals: .asciz "scanForPeripheralsWithServices:options:"
Ls_cancelPeripheralConnection: .asciz "cancelPeripheralConnection:"
Ls_connectPeripheral:  .asciz "connectPeripheral:options:"
Ls_setDelegate:        .asciz "setDelegate:"
Ls_discoverServices:   .asciz "discoverServices:"
Ls_services:           .asciz "services"
Ls_firstObject:        .asciz "firstObject"
Ls_discoverCharacteristics: .asciz "discoverCharacteristics:forService:"
Ls_characteristics:    .asciz "characteristics"
Ls_dataWithBytes:      .asciz "dataWithBytes:length:"
Ls_writeValue:         .asciz "writeValue:forCharacteristic:type:"
Ls_removeAllServices:  .asciz "removeAllServices"
Ls_initCharacteristic: .asciz "initWithType:properties:value:permissions:"
Ls_initWithTypePrimary: .asciz "initWithType:primary:"
Ls_setCharacteristics: .asciz "setCharacteristics:"
Ls_addService:         .asciz "addService:"
Ls_dictionaryWithObject: .asciz "dictionaryWithObject:forKey:"
Ls_startAdvertising:   .asciz "startAdvertising:"
Ls_count:              .asciz "count"
Ls_objectAtIndex:      .asciz "objectAtIndex:"
Ls_offset:             .asciz "offset"
Ls_value:              .asciz "value"
Ls_length:             .asciz "length"
Ls_bytes:              .asciz "bytes"
Ls_respondToRequest:   .asciz "respondToRequest:withResult:"

Ls_msg_scanning:       .asciz "\302\267 Bluetooth is on \342\200\224 looking for other Macs running asmmesh"
Ls_msg_adv:            .asciz "\302\267 advertising \342\200\224 nearby Macs running asmmesh can find this one"
Ls_msg_found:          .asciz "\302\267 found a Mac running asmmesh \342\200\224 connecting\342\200\246"
Ls_msg_unauth:         .asciz "\302\267 asmmesh isn't allowed to use Bluetooth. Allow it in System Settings \342\200\272 Privacy & Security \342\200\272 Bluetooth, then reopen."
Ls_msg_unsup:          .asciz "\302\267 this Mac doesn't support Bluetooth LE peripheral mode."
Ls_msg_off:            .asciz "\302\267 Bluetooth is off. Turn it on in Control Center to join the mesh."
Ls_fmt_linked:         .asciz "\302\267 linked with a nearby Mac \342\200\224 %ld in range"
Ls_fmt_lost:           .asciz "\302\267 a Mac went out of range \342\200\224 %ld still linked"
Ls_fmt_adderr:         .asciz "\302\267 couldn't publish the mesh service: %s"
Ls_fmt_adverr:         .asciz "\302\267 couldn't start advertising: %s"
