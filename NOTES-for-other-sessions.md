# Note from the FM + web session (Sept 30, 07:05–07:19 UTC)

Another Claude session (FM radio / web over the mesh) edited this folder while you were working.
Please read this before your next change or install.

## What I changed
New files:
- `src/fm.s` — FM transport: TX queue, listen-before-talk, sound inputs, and the FM Radio window
- `src/fm_dsp.s`, `src/fm_audio.s`, `src/fm_io.s`, `src/fm_pack.s`, `src/fm_util.s`, `src/fm_html.s`, `src/fm_defs.inc` — the AFSK modem and helpers, ported from asmfm
- `src/web.s` — Web and News rooms, plus the "Internet for the mesh" gateway

Edited:
- `Makefile` — new sources, AudioToolbox/CoreAudio/CoreFoundation/-lz, fm_defs.inc dependency
- `Info.plist` — microphone text mentions FM listening; version 0.7
- `README.md` — 0.7 section, files list, packet formats
- `src/macros.inc` — SVC_FM=15, SVC_GATE=16, NSVC=17, WEB_ID=2, NEWS_ID=3, LOCAL_ROOMS=4, T_NEWS=7, T_WEBREQ=8, T_WEBPART=9
- `src/ble.s` — _ble_broadcast also calls _fm_tx_packet
- `src/mesh.s` — types 7–9 go to _web_rx; ids 1–3 are local rooms
- `src/services.s` — FM radio and gateway rows; the gateway can restart after being switched off
- `src/main.s` — Web and News rooms, Mesh › FM Radio…, welcome line says 0.7
- `src/ui.s`, `src/ident.s`
- `src/test.s` — calls _fm_selftest and _web_selftest

## Your test.s fix
You fixed "unknown packet type" (type 200) and "other room counts as unread" (#4) the same way I would have,
so I kept your version. Room indexes: Main 0, Home 1, Web 2, News 3, so new rooms start at 4.

## State now
- Self-tests all pass, and the app is installed and running. FM Radio window checked.
- Double-clicking "Install asmmesh.command" started it twice both times, and the two runs clashed over
  $TMPDIR/asmmesh-build. One run installed fine. Please don't start an install while another is running.
- Packet types 7, 8 and 9 are taken, and local room ids are 1–3. Please use other numbers.

## 0.8, builds 9-13 (rewritten after the move: the original notes for these builds were lost)
New files: `src/alerts.s` (ntfy, Pushover, location, SOS, weather alerts, webhook on port 8787),
`src/files.s` (Files on Wi-Fi on port 8788, folder chooser, AirDrop, QR code),
`src/fm_fec.s` + generated `src/fm_fec_tables.inc` (Reed-Solomon error correction for FM).
Numbers now taken - please pick others:
- Packet types: T_HELLO 2, T_INVITE 3, 7-9 (web/news), T_ROOMDEL 10.
- Services: SVC_LOC 17, SVC_NTFY 18, SVC_PUSHOVER 19, SVC_NWS 20, SVC_HOOK 21, SVC_FILES 22, NSVC 23.
  ST_LAN / ST_CLOUD moved to bits 40/41 so they don't collide with service bits.
- Room struct: R_OWNER at 56 (creator's id); saved in defaults key "roomOwners".
- Self-tests 78-93 (alerts, files, room delete) and 17b (re-key invite).
Behaviour changes:
- FM frames: 8-byte sync tag, length x3, RS(n, n-32) blocks, CRC-16; sent twice unless "fm repeat off".
  The old HDLC path still receives. DPLL gain is 1/8. MODBUF is 480000.
- Invites carry the room owner; an invite to a room you already have with a different key asks
  "Use the New Key". Only the owner can delete a room for everyone (Mesh > Delete Room...).
- ident.s: the identity is only regenerated when Keychain says "not found" (-25300), never on a refusal.
- The welcome line shows the build number from Info.plist (CFBundleVersion).

## Build 14 (Bluetooth sensors, batteries, headphones)
New files: `src/sens_decode.s` (pure decoders, tested against bthome-ble / govee-ble / pySwitchbot
references under qemu), `src/sens_bthome.inc` (generated), `src/sensors.s`, `src/handoff.s`.
Numbers now taken:
- Device kind K_BLES 18 (K_LAST 18). D_SIDX = D_AUX+0, D_MOTION = D_AUX+24, D_WET = D_AUX+32.
- SVC_SENSORS 23, NSVC 24 — the Settings grid (3 x 8) is now full.
- Packet type T_HP 11 (headphones; +12 target, +20 sender, +28 nlen, nick, op, fingerprint[16]).
- Rule types R_THR 5 (RU_FIELD quantity, RU_DAYS above/below, RU_MIN limit in hundredths of °C)
  and R_BTN 6 (RU_DAYS button, RU_WANT press). Self-tests 94-105.
- Frameworks: IOKit (battery levels). sensors.s is called from ble.s for every non-mesh advert.

## Moved to ~/Developer/asmmesh, now in git (after build 13)
- The project lives in `~/Developer/asmmesh` (outside iCloud). `~/Desktop/asmmesh old` is the
  pre-git copy - don't edit it any more.
- Branch `main` = what is installed on the Mac mini. "Install asmmesh.command" commits automatically
  after a passing install ("build N installed"). The first commit is tagged `build-13`.
- Another session: please work in your own worktree on a branch, not in the main folder:
  `cd ~/Developer/asmmesh && git worktree add ../asmmesh-<topic> -b <topic>`,
  and merge into main only when its self-tests pass.
- Signing: once an "Apple Development" certificate exists (Xcode > Settings > Accounts), the Makefile
  uses it automatically and install.log says "signed: Apple Development: ...".

## iPhone app (ios/, after build 14)
- `ios/asm/ios_ui.s` replaces main.s, ui.s and scanner.s on iOS. It keeps the same globals and entry
  points (`_room_line`, `_ui_select_room`, `_ui_*_changed`, `_ui_set_status`, `_alert_run`...), so the
  core files build unchanged for both. New core helpers: `_svc_field` (services.s), `_sens_info` (sensors.s).
- Swift registers ObjC classes named NSAlert, NSTextField, NSSecureTextField and NSComboBox
  (Bridge.swift). The core's dialogs therefore work as they are: `runModal` shows a UIAlertController and
  spins the run loop until answered, then returns 1000 + the button index.
- Swift is called back through `ios_room_line`, `ios_select_room`, `ios_refresh`, `ios_status` (@_cdecl).
- The project file is generated: `python3 ios/make_project.py` (lists every core .s file). Please keep
  the list in step when you add a source file used on both.
- iOS stubs: web/news rooms, files, AirDrop, FM, IOKit battery calls (return 0).

## Builds 15-16 (Oct 20): iPhone-style Mac look, hardening, iPhone/iPad parity
- New files: cards.s (Mac card lists), limits.s (flood limits), guard.s (guarded radio input),
  scan_core.s (scanner logic, shared), files_mac.s (Mac-only Files on Wi-Fi parts).
  Shared with iOS now: limits, guard, web, fm_html, fm_pack, fm_util, fm_io, files, scan_core.
- Numbers taken: RL_UNVERIFIED 1, RL_RELAY 2, RL_NEWKEY 3 (limits.s bucket ids); key table
  KEYS_N 64 with KE_SEEN at +84; self-tests 106-118.
- Platform hooks each side must provide: _room_append (ui.s / ios_ui.s), _fs_default_dir,
  _fs_qr_show, _h_files_choose, _h_airdrop, _scan_say.
- Radio entry points in the method tables are the _g_ble_* guarded versions (guard.s); keep it so.
- A packet that crashes the guard lands in ~/Library/Logs/asmmesh-guard.log as hex: add it
  to the fuzz templates in test.s.

## bitchat Phase 1 (Oct 27, branch claude/bitchat-roadmap): cryptography only
- Plan: docs/bitchat_roadmap.md. bitchat stays walled off from asmmesh (see "The wall" there).
- New file: `src/bc_crypto.s` — SHA-256/512, HMAC/HKDF-SHA256, ChaCha20-Poly1305, X25519, Ed25519.
  Pure functions, no globals, nothing called yet. In the Makefile and ios/make_project.py.
- All bitchat code goes in `src/bc_*.s`; please don't put bitchat code anywhere else.
- Self-tests 127-144 (`_bc_selftest`, called from test.s after _sens_selftest).
- `tools/qemu/run.sh` runs those tests on Linux under qemu; `tools/qemu/run.sh diff 300` checks
  every function against Python's `cryptography` with random and edge-case inputs.
  It turns the file into ELF with sed, so keep bc_*.s to ENTER/LEAVE/ADRL and `.section __TEXT,__const`.

## bitchat Phase 2 (Oct 27, branch claude/bitchat-roadmap): the Bluetooth link
- New files: `src/bc_link.s` (pure: frame length, long writes, fragment reassembly, send queue),
  `src/bc_ble.s` (CoreBluetooth), `src/bc_defs.inc`. In the Makefile (and its include list) and
  ios/make_project.py.
- Numbers taken: SVC_BITCHAT 24, NSVC 25. The Mac Settings window is now five columns by five rows (1440 x 498), full at 25.
  "enable all" skips bitchat; it can't be switched from the mesh (_g_remote_active).
- Home words: "bitchat", "bitchat status", "bitchat advertise on/off" (rules.s table).
- bitchat has its own CBCentralManager, CBPeripheralManager and delegate class (AMeshBitchat):
  please keep bitchat callbacks out of ble.s and the AMeshController method tables.
- Self-tests 145-154 (`_bc_link_selftest`, after _bc_selftest in test.s).
- Not tried on a Mac yet: see the Phase 2 checklist in docs/bitchat_roadmap.md.

## bitchat Phase 3 (Oct 30, branch claude/bitchat-roadmap): reading and writing packets
- New files: `src/bc_packet.s` (pure: decode, signing bytes, verify, build, duplicate filter,
  relay rule) and `src/bc_zlib.s` (_bc_inflate through libz). In the Makefile and ios/make_project.py.
  Decoded-packet layout DP_* and the filter's DD_* are in bc_defs.inc.
- Self-tests 155-164 (`_bc_packet_selftest`, after _bc_link_selftest in test.s).
- tools/qemu: bcvectors.py makes the test packets; inflate.c stands in for libz under qemu;
  `tools/qemu/run.sh diff` checks everything against bcwire.py.
- bc_ble.s reads each packet with _bc_decode and counts it by type (_g_bc_types); "bitchat" lists
  the kinds it doesn't name.

## bitchat Milestone 1 (Oct 30, branch claude/bitchat-roadmap): bitchat people
- New file: `src/bc_peer.s` (pure: announces, the people table, leaves, UTF-8). In the Makefile
  and ios/make_project.py. Layouts AN_*, BT_* in bc_defs.inc. Self-tests 165-172.
- bc_ble.s: our bitchat keys (Keychain item "asmmesh.bitchat", separate from asmmesh's identity),
  announces, people. `_bc_tick` runs once a second from scanner.s and ios_ui.s.
- net.s: new `_kc_del(service)`. rules.s: "bitchat people", "bitchat forget".
- People: rows past _g_node_count are bitchat people (`_people_rows` in ui.s, `Lcv_bitchat` in
  cards.s; iPhone: `am_bc_*` and Mesh.bitchatPeople). Code that takes a People row as an index
  into _g_nodes must check it against _g_node_count first (Invite already does).
