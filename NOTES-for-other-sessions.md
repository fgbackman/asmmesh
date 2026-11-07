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

## bitchat Milestone 2 (Oct 30, branch claude/bitchat-roadmap): public chat
- Room id 4 is the local bitchat room (BITCHAT_ID); LOCAL_ROOMS is 5 (ids 1-4 local). It exists
  only while bitchat is on (bc_ble.s adds and removes it), so find it with _room_find, never by
  index. ROOM_MAX is 17. mesh.s routes text typed there to `_bc_say` (bc_ble.s) only.
- `_kc_get` (net.s) now also returns the Keychain status in x1; prefer it to _g_kc_status, which
  every thread shares. Self-tests 176 (bc_peer.s) and 177 (bc_link.s).
- bc_peer.s: `_bc_msg_read`, `_bc_msg_split`, `_bc_relay_ok`; self-tests 173-175.
- bc_ble.s: duplicate filter, messages into the room, relaying between bitchat links.

## bitchat security hardening (Oct 31, branch claude/bitchat-roadmap)
- Self-tests 176-183 (bc_peer.s, bc_link.s). bc_peer.s: pins (PN_*), _bc_name_same/_bc_name_skel,
  _bc_ed_small, _bc_rate_ok(rl, now, max, period). _bc_peer_heard takes pins in x6,
  _bc_peer_leave in x5; _bc_seen takes a "remember" flag in x3; _bc_frag_put takes the link in x6.
- New Keychain item "asmmesh.bitchat.pins"; defaults key "bitchatName"; Home word "bitchat name".
- ident.s: _id_ready reads _g_id_kcst (its own read's status), not the shared _g_kc_status.
- mesh.s: `_room_drop(idx)` removes a room without saving; `_room_remove` = drop + save.

## Handoff
For where the bitchat work stands and what comes next, start with `docs/bitchat_handoff.md`.

## The input field as a terminal (Oct 31, branch claude/bitchat-roadmap)
- New files: `src/term_core.s` (pure: history ring, saving, suggestion matching; runs under qemu)
  and `src/term.s` (Mac: monospaced field with a prompt, up/down history, suggestions in Home).
  In the Makefile. `src/term_hist.s` (Mac and iPhone): keeping rules, word list, `_h_term_history`,
  `_term_init`/`_term_record`/`_term_match`. iPhone: `am_hist_*`/`am_sg_*` in ios_ui.s, chips and a
  recent menu in RoomsView.swift.
- Service switches: `refresh` (`_home_refresh`), `_cloud_load`, `_hue_tick` and `_rules_poll` check
  them; a service switched off must not be contacted.
- Self-tests 184-187. Defaults keys "termHistory" ("0" = don't keep) and "termHistoryLines".
  Home words "history", "history on", "history off", "history clear".
- The controller is the field's delegate: `control:textView:doCommandBySelector:` (_term_cmd)
  and `controlTextDidChange:` (_term_changed) are in main.s's method table.
- rules.s `_rules_words` hands the Lsimple words to the suggestions: a word added there is
  suggested automatically.

## Hue: v1 bridge and adding by serial (Nov 2, branch claude/bitchat-roadmap)
- `src/hue_core.s` (pure, qemu self-tests 188-190): `_hue_serials` (typed text -> the bridge's
  `{"deviceid":[...]}` body, 6 hex chars each, max 10), `_hue_addr_ok`, `_ssdp_is_hue` ("IpBridge"
  in SERVER or a `hue-bridgeid:` line).
- hue.s: `_h_hue_add` ("add hue …", "search hue …", "find new hue …": POST /lights, then GET
  /lights/new after 50 s, again every 20 s while `lastscan` is "active", 3 checks at most),
  `_h_hue_bridge` ("hue bridge <ip>": a new address forgets the old username), `_hue_ssdp`
  (udp.s calls it for every SSDP answer). `_hue_tick` opens the SSDP sockets (`_udp_init` is
  now safe to call twice) when no bridge is known at 8 s.
- The API was already v1 over http://, which the v1 bridge speaks; only finding it was missing.

## Hue: several bridges (Nov 3)
- hue.s keeps up to 4 bridges in `_g_hue_br` (HB_HOST/USER/ID/NAME/NEW, 192 bytes each);
  `_g_hue_cur` is the one talked to; `HUE_HOST`/`HUE_USER` macros (x16/x17 scratch) give its
  fields. Every request tag ends in the bridge's digit ("hl1"); `_hue_response` sets
  `_g_hue_cur` from it. Defaults: hueHost/hueUser/hueId/hueName for bridge 1 (unchanged keys),
  hueHost2…hueName4 for the others.
- Device ids: bridge 1 keeps the plain light/group id ("3"); others are "2:3" (`_hue_devid`,
  `_hue_split` in hue_core.s, self-test 191).
- A new address gets a slot marked HB_NEW and `GET /api/config` (no username needed); its
  `bridgeid` merges it into a known slot (the bridge moved) or it's announced as new.
- Commands: "hue bridges", "hue bridge <ip>", "forget hue bridge N" (devices set to kind 0),
  "add hue light X on N". Mac menu: Mesh › Add Hue Lights… (`_hue_add_dialog`). iPhone:
  `HueView.swift`, `am_hue_host/name/paired`.

## bitchat private chats, Milestone 3 (Nov 3)
- `src/bc_noise.s` (pure, qemu self-tests 192-195): Noise XX as bitchat does it; `tools/qemu/bcnoise.py` is
  the Python copy (matches the `noiseprotocol` package); `bcvectors.py noise` makes the test vectors.
- `src/bc_ble.s` end: sessions (`_g_bc_nz`, 16), outbox (`_g_bc_ob`, 32), chat slots (8) -> rooms with ids
  `BCPM_FIRST` (5)..12. `LOCAL_ROOMS` is 13 now (ids 1..12 local) and `ROOM_MAX` 25: every "local room"
  check in mesh/ident/listed/ui covers the chats without other changes.
- mesh.s `_mesh_send_text`: typing in a chat room -> `_bc_pm_say`. `Lbc_read`: 0x10/0x11 for us ->
  `Lbc_noise_in` (not relayed). `Lbc_keys_wipe` -> `Lbc_pm_wipe`; `_bc_tick` -> `Lbc_pm_tick`.
- Home: `bitchat chat <name|hex>` (`_h_bitchat_chat`); iPhone `am_bc_hexid`, PeopleView "Message".

## Ninefold, the word game (Nov 4, branch claude/ninefold)
- New files: `src/nf_core.s`, `src/nf_play.s`, `src/nf_text.s` (all pure, qemu self-tests 196-204),
  `src/nf_mesh.s` (Mac and iPhone), `src/nf_defs.inc`, `src/nf_words.bin` (made by
  `tools/ninefold/nf.py pack` from `tools/ninefold/words/`), `ios/asmmesh/GameView.swift`.
  In the Makefile (nf_core.o depends on nf_words.bin) and ios/make_project.py.
- Numbers taken: MSGF_GAME 8 (room-message flag: the bytes are a game packet, always with
  MSGF_RKEY). Game packet kinds NK_START 1, NK_CLAIM 3, NK_REVEAL 4 (nf_defs.inc).
- mesh.s: `_mesh_send_game(room, data, len)`; `Lrx_game` -> `_nf_rx`; `_mesh_send_text` asks
  `_nf_typed` first. Home word "ninefold" (rules.s). `_nf_tick` runs from scanner.s and
  ios_ui.s next to `_bc_tick`. Platform hook `_nf_ui_show(status)`: ui.s (room header) and
  ios_ui.s (`ios_nf_changed` in Bridge.swift).
- `tools/qemu/run.sh nfdiff N` checks nf_core.s against nf.py; `run.sh nfdemo` prints a round.
- Not tried on a Mac or iPhone yet (built and tested under qemu and clang only; Swift not
  compiled here).

## Chess (Nov 4, branch claude/ninefold)
- New files: `src/ch_core.s`, `src/ch_play.s` (pure; qemu self-tests 205-213), `src/ch_mesh.s`
  (Mac and iPhone), `src/ch_win.s` (Mac), `src/ch_defs.inc`, `ios/asmmesh/ChessView.swift`.
- Game packets share MSGF_GAME with Ninefold: byte 0 'C' is chess (`_chm_rx`), 'N' Ninefold.
  Kinds CK_NEW 1, CK_MOVE 2, CK_RESIGN 3, CK_ASK 4, CK_HIST 5, CK_DRAW 6 (ch_defs.inc).
- bc_ble.s: `Lbc_pm_took` hands each private message's text to `_chm_bc_text` after showing it;
  `_bc_pm_peer(room id)`. mesh.s `_mesh_send_text` asks `_chm_typed` in game rooms and in
  bitchat chats. Home word "chess". `_chm_tick` next to `_nf_tick`. Hooks `_ch_ui_show`,
  `_ch_ui_pop` (ch_win.s on the Mac; ios_ui.s -> `ios_ch_changed` / `ios_ch_pop`).
- `tools/qemu/run.sh chperft` (deep perft), `run.sh chmesh` (ch_mesh.s with stand-ins for the
  app, tests 214-216: both transports).
- Not tried on a Mac or iPhone yet.

## Block, report, chat filter (Nov 4, branch claude/ninefold)
- New files: `src/cf_core.s` (pure, self-test 217; words in `src/cf_words.inc` from
  `tools/ninefold/make_chat_filter.py`), `src/safety.s` (Mac and iPhone).
- mesh.s: blocked senders' MSG (text and game), INVITE, JOINREQ, SEEK aren't shown or taken
  (still relayed); `_chat_clean` + `_rec_note` on every message shown. bc_ble.s: the same for
  bitchat public and private messages. Typing block / unblock / report in a private bitchat
  chat (`_sf_bc_typed`, before chess). Defaults keys "blocked", "chatFilter", "reportTo".
- Home words: block, unblock, blocked, report, report address, filter, filter on/off.
  Mac: Mesh › Block Person, Report Person…. iPhone: People ⋯ menu; Settings › Privacy.

## The developer blocklist (Nov 4, branch claude/ninefold)
- `src/dbl_core.s` (pure, self-test 218): `_dbl_verify` (Ed25519 with the key in
  `src/dbl_key.inc`; all zeros = off), `_dbl_has`. `src/dbl_list.bin` is the list shipped
  (may be empty). safety.s: `_blk_has` also checks it; `_dbl_tick` fetches the URL in
  dbl_key.inc daily (tag 'd' -> `_dbl_response`, net.s); newest good list kept in defaults
  "devBlocklist". Tool: `tools/blocklist/blocklist.py`; the private key lives in
  ~/.asmmesh-blocklist, never in the repository. Instructions: docs/blocklist.md.
- Mesh sharing: packet type T_DBL 15 (TTL 1, neighbours only; macros.inc has the layout).
  dbl_core.s `_dbl_piece`, `_dbl_piece_in` (self-test 219); safety.s `_dbl_rx` (mesh.s
  Lrx_dbl), announces and paced sending in `_dbl_tick`. The web fetch only when defaults
  "blocklistFetch" is "1" (Home: blocklist fetch on/off); `blocklist` shows the state.

## Fivefold, the five-letter word game (Nov 5, branch claude/ninefold)
- New files: `src/ff_core.s`, `src/ff_play.s` (pure; qemu self-tests 220-223), `src/ff_mesh.s`
  (Mac and iPhone), `src/ff_win.s` (Mac), `src/ff_defs.inc`, `src/ff_words.bin`
  (`tools/ninefold/ff.py pack`), `ios/asmmesh/FivefoldView.swift`. `docs/fivefold/README.md`.
- Game packets: byte 0 'F' (`_ffm_rx`, from mesh.s `Lrx_game`). Kinds FK_RACE 1 … FK_REVEAL 6.
  mesh.s `Lst_mesh` asks `_ffm_typed` after chess. `_ffm_tick` next to `_chm_tick`.
- Home words (rules.s): fivefold, fivefold today, fivefold share, fivefold race [with] A, B,
  fivefold duel [with] A. Rooms "Fivefold <nick>" get the game wording in invites (ui.s,
  ios_ui.s). Selecting the race/duel room brings the board up.
- Two game structs: `_g_ffs` (today's, saved in defaults "fivefoldToday" as "day:w,w"),
  `_g_ffg` (race or duel). The screens show `_g_ffg` while its room exists, else `_g_ffs`.
- Hooks `_ff_ui_show`, `_ff_ui_pop` (ff_win.s on the Mac; ios_ui.s -> `ios_ff_changed` /
  `ios_ff_pop`). Mac: Mesh › Play Fivefold… (⌘5), the amber button left of chess (x=86).
- `tools/qemu/run.sh ffmesh` (ff_mesh.s with stand-ins, tests 224-226: today, race, duel).
- Not tried on a Mac or iPhone yet.

## When the user starts on the App Store (they asked to be reminded)
- Bring up "Reminders saved for when the App Store work starts" at the top of
  `docs/app-store-checklist.md` first: SPIN gestures 20-24 beyond SPIN's spec, CREDITS.md in
  About, hiding web pages on iPhone, the Mac outside the store first.

## Shortcuts and saved devices (Nov 6, branch claude/ninefold)
- `src/quick.s` (Mac and iPhone). Shortcuts: defaults "quickShortcuts" ("name\tcommands\n"),
  24 at most; `_qk_try` runs first in `_home_command` (home.s), each part through
  `_home_command` again with a depth guard. Home words (rules.s): shortcut NAME: …, shortcuts,
  delete/remove shortcut, forget devices. Hook `_qk_ui_changed`: main.s rebuilds the
  Shortcuts menu (qkRun:/qkNew:/qkDelete:); ios_ui.s -> `ios_qk_changed` (Nearby tab).
- Devices: `_dv_load` in `_home_init` before the services start, `_dv_tick` once a second
  (saves every 30 s when the packed table differs) into defaults "savedDevices" (NSData of
  256-byte entries). K_HUE_BLE and K_BLES are never kept; D_OBJ zeroed, state -1, CAP_LINKED off.
- `tools/qemu/run.sh quick` (tests 227-229, stand-ins for Home and the defaults).
- Not tried on a Mac or iPhone yet.

## MeshCore and Meshtastic (LoRa) — chat built for both (Nov 7)
- `docs/meshcore/PLAN.md` (status table at its end). `src/mc_core.s` (pure, self-tests 230-233),
  `src/mc_ble.s` (hooks in ble.s next to spin's), `tools/meshcore/mc.py` + `mcdiff.py`
  (`run.sh mcdiff`), `tools/qemu/mcsim.c` (`run.sh mcsim`, 234-236).
- Numbers taken: SVC_MESHCORE 25, SVC_MESHTASTIC 26, NSVC 27 (Settings 5 x 6, room for 30),
  MESHCORE_ID 13, MESHTASTIC_ID 14, LOCAL_ROOMS 15. Next self-test number: 242.
- Meshtastic: `src/mt_core.s` (protobufs by hand, 237-238), `src/mt_ble.s`, `tools/meshcore/mt.py`
  + `mtdiff.py` (`run.sh mtdiff`), `tools/qemu/mtsim.c` (`run.sh mtsim`, 239-241).
- Not tried with a real radio yet.

## Before pushing assembly: `python3 tools/linkcheck.py` (Nov 7)
- Assembles every Mac (Makefile) and iPhone (make_project.py CORE + ios_ui.s) file and lists any
  symbol used but defined nowhere or not `.globl`. A filtered nm check missed `_array1` and
  `_ble_scan` (private to ble.s, used by mc_ble.s) and the Mac link failed; this would have caught it.
