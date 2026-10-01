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
