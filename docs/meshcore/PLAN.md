# MeshCore in asmmesh: the plan

Goal: asmmesh talks to a MeshCore LoRa radio, a small device that sends messages miles
without Wi-Fi or phone signal. Two uses:

1. **Chat with MeshCore users**: their public channel and direct messages, behind a wall like
   bitchat's.
2. **asmmesh over LoRa**: our own signed packets carried between asmmesh users far apart, the
   way FM radio already carries them.

Everything is off until switched on. It is tested without a radio first, and the radio can only be
asked to do a short list of harmless things.

Status (Nov 7, 2026): plan only. Nothing is built yet.

## Facts checked in MeshCore's source

These were checked in `meshcore-dev/MeshCore` at commit `81dbae5` (Oct 15, 2026, MIT licence),
in `docs/companion_protocol.md`, `examples/companion_radio/MyMesh.cpp` and `src/MeshCore.h`.

| Fact                     | Value                                                                       |
|--------------------------|-----------------------------------------------------------------------------|
| Bluetooth service        | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` (Nordic UART)                        |
| Write (app → radio)      | `6E400002-…`; one write is one command, byte 0 its code                     |
| Notify (radio → app)     | `6E400003-…`; replies, and pushes such as `0x83` "messages waiting"          |
| Commands we'd use        | 1 APP_START, 2 SEND_TXT_MSG, 3 SEND_CHANNEL_TXT_MSG, 10 SYNC_NEXT_MESSAGE, 62 SEND_CHANNEL_DATA, plus contacts and channel reads |
| Channel data limit       | **165 bytes** of payload (not 184: that is the whole LoRa packet)           |
| Channel data format      | `3E chan pathlen [path] type(2, LE) payload`; type 0xFFFF = developer use    |
| Datagram identity        | none: "no built-in sender identity and no timestamp" (we sign our own)      |
| Pairing                  | the radio shows a Bluetooth PIN; macOS and iOS ask for it once              |
| Dangerous commands       | 11 SET_RADIO_PARAMS, 19 REBOOT, 23 EXPORT_PRIVATE_KEY, 24 IMPORT_PRIVATE_KEY, 51 FACTORY_RESET, and others |

asmmesh facts: packets are up to `PKT_MAX` 240 bytes, including a 68-byte `TRAILER` (time
and P-256 signature). Every send goes through `_ble_broadcast` (`src/ble.s`), which already
hands each packet to `_fm_tx_packet`. Every receive goes into `_mesh_receive` behind
`_guard_rx`. The Settings grid is 5 × 5, full at `NSVC` 25.

## Shape: the same as bitchat and FM

| File                   | What                                                                      | Runs where           |
|------------------------|---------------------------------------------------------------------------|----------------------|
| `src/mc_core.s`        | pure: frame encode and decode, the command allowlist, contacts and messages parsed, asmmesh packets split in two and joined, the airtime budget | Mac, iPhone, qemu    |
| `src/mc_ble.s`         | the radio over Bluetooth: connect, pair, write, notify, an outbox, reconnect; a simulated radio for tests | Mac, iPhone          |
| `src/mc_ui.s` + Swift  | the MeshCore room, LoRa people, the Settings switch                        | Mac (asm), iPhone (Swift) |
| `tools/meshcore/mc.py` | a Python copy of `mc_core`, from MeshCore's docs, for diff tests           | Linux                |
| `tools/qemu/mcsim.c`   | runs `mc_ble.s` against a fake radio (like `chmesh.c`, `ffmesh.c`)        | qemu                 |

Hooks, each one line:
- `_ble_broadcast` → `_mc_tx_packet`, next to `_fm_tx_packet`.
- `_mc_rx` → join the two pieces → `_guard_rx` → `_mesh_receive`, with the packet marked as
  having come over LoRa, so it is never sent back over LoRa.
- The tick → `_mc_tick`.
- Service `SVC_MESHCORE`, off by default; "enable all" leaves it off.

## The wall: what MeshCore users can and can't reach

Modelled on bitchat's wall (`bc_ble.s`, `Lst_bcpm`):

- MeshCore users' text appears only in the **MeshCore** room and in direct-message chats. It
  is never a Home command, never a rule trigger, and never relayed into asmmesh rooms.
- Nothing from asmmesh rooms goes to MeshCore unless you type it in the MeshCore room or a
  MeshCore direct chat.
- Names and text are cleaned as bitchat's are: no line breaks or direction tricks, and
  length limits. The chat filter, block and report apply.
- Messages are marked "via MeshCore". They carry no asmmesh signature, so they are never
  shown as a verified asmmesh person.
- asmmesh-over-LoRa packets are ordinary asmmesh packets, signed and checked exactly as on
  Bluetooth. A packet that fails its checks is dropped. LoRa adds no trust.

## The radio stays safe: the allowlist

One encoder builds every frame sent to the radio. It refuses any command not on this list:
APP_START, DEVICE_QUERY, GET_CONTACTS, SYNC_NEXT_MESSAGE, SEND_TXT_MSG,
SEND_CHANNEL_TXT_MSG, SEND_CHANNEL_DATA, GET_CHANNEL, and SET_CHANNEL for **our own
channel slot only**.

Never sent: radio settings, transmit power, reboot, factory reset, key export or import, or
firmware updates. The radio's frequency and region are set by you in MeshCore's own app. A
self-test checks that every other code is refused.

## Sandbox and tests

- **Simulated radio (`_g_mc_test`)**, like FM's `_g_fm_test`. Frames go to a buffer instead
  of Bluetooth, and replies are fed in from tests. `make selftest` covers the Bluetooth glue
  with no hardware.
- **Pure self-tests (qemu, numbered from 230)**:
  - frame encode and decode for each command, reply and push used;
  - unknown and short frames ignored;
  - the allowlist;
  - split and join: lost, duplicated, out-of-order and oversized pieces, and two packets
    interleaved;
  - the airtime budget;
  - names cleaned.
- **Diff tests**: random cases through `mc_core` and `tools/meshcore/mc.py`, which must agree
  (like `run.sh diff` for bitchat).
- **Fuzz**: random bytes as radio frames. Nothing crashes, and `_guard_call` catches a fault
  if one gets through.
- **`run.sh mcsim`**: a whole session against a fake radio — connect, APP_START, contacts,
  "messages waiting" → sync → a message shown in the MeshCore room, and a direct message out.
  Also asmmesh packets out in two pieces and back in through `_mesh_receive`, and a check that
  nothing from MeshCore reaches Home.
- **Mutation checks** on the allowlist and the wall: break each, and its test must fail.
- **Hardware checklist**: run on your Mac and iPhone, since this machine has no radio.

## asmmesh over LoRa: the details

- **Channel**: our own private MeshCore channel, "asmmesh", in a slot we set. Its 16-byte
  secret comes from the mesh passphrase (HKDF) when one is set. Otherwise it is a fixed public
  asmmesh value: packets are signed, and room contents are sealed with room keys either way.
- **Data type**: 0xFFFF (developer) to start. Ask MeshCore to register an asmmesh number
  before release.
- **Split in two**: each piece holds `'A' 'M'`, a version, a packet id (4 bytes), its index
  and the total, then up to 155 bytes. A packet of 240 bytes or less is at most two pieces.
  The join keeps 16 partial packets for 30 s, and an oldest-first eviction stops a flood from
  filling it.
- **Airtime**, from FM's rules:
  - our own HELLO about once a minute;
  - other people's HELLOs and `T_SEEN` never relayed over LoRa;
  - relays limited per sender (`limits.s`);
  - a duty-cycle budget per hour (EU 868 MHz: 1 to 10%), set low by default.
- **Loops**: a packet that came in over LoRa isn't sent back over LoRa. The existing duplicate
  filter covers the rest.

## Milestones

| #   | What                                                            | Done when                                                               |
|-----|-----------------------------------------------------------------|-------------------------------------------------------------------------|
| 0   | Settings room: the 5 × 5 grid is full                            | a sixth row or a scrolling grid; MeshCore's switch in it, off           |
| 1   | `mc_core.s` + `mc.py`: frames, allowlist, split and join, airtime | self-tests 230+ and diff tests pass under qemu; mutation checks fail as they should |
| 2   | `mc_ble.s` with the simulated radio                              | `run.sh mcsim` passes; Mac and iPhone assemble and link                 |
| 3   | Chat with MeshCore users                                         | MeshCore room, LoRa people, direct messages, wall tests pass            |
| 4   | asmmesh over LoRa                                                | two asmmesh devices exchange packets through the fake radio in mcsim     |
| 5   | Real radios                                                      | your Mac and iPhone with two companion radios: the hardware checklist passes |
| 6   | Docs, App Store notes                                            | README, this file, and the checklist's encryption and wall notes updated |

Milestones 1 to 4 are built and tested here. Milestone 5 needs you and the radios.

## Decisions for you

- **Radios**: two, such as a Heltec V3 (cheap, needs a case) or a SenseCAP T1000-E (cased,
  with GPS), flashed with Companion (Bluetooth) firmware.
- **Region**: the frequency is set in MeshCore's app, by your country. We never change it.
- **Channel secret**: derived from the mesh passphrase (recommended), or a fixed one.
- **Order**: chat with MeshCore users first (milestone 3, useful with one radio), or asmmesh
  over LoRa first (milestone 4, needs two).

## What runs where during the work

- **Here (Linux)**: all assembly is assembled for Mac and iPhone and checked for missing
  symbols. Pure code and the fake-radio glue run under qemu. Swift can't be compiled.
- **On your Mac**: `make selftest`, `make install`, the iPhone installer, and the radios.
- **Other sessions**: check `NOTES-for-other-sessions.md` before starting, and add a section
  there when work lands.
