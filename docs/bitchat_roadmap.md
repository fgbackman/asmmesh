# bitchat roadmap

Two tracks:

- **Track A:** talk to each other on bitchat today, with nothing to build.
- **Track B:** teach asmmesh (Mac and iPhone) to join bitchat's mesh, so asmmesh users and bitchat users can see and message each other.

Protocol details below come from bitchat's public repo (`permissionlesstech/bitchat`, commit `04995f6`, Oct 25 2026, released into the public domain under the Unlicense) and its `WHITEPAPER.md` v2.0. bitchat changes often, so re-check each detail against the current source before building that phase.

---

## Track A — use bitchat now

1. Both install **bitchat** (App Store for iPhone and Mac; Android has its own app).
2. Open it with Bluetooth on. There's no account, phone number or internet needed.
3. Within about 10–30 m you'll see each other under nearby people. Further away, messages hop through other bitchat users (up to 7 hops).
4. **Public chat** is seen by everyone nearby. **Private chat** (tap the person) is end-to-end encrypted with Noise.
5. **Favourite each other.** Favourites get store-and-forward mail: a message waits on trusted devices and is delivered when you're back in range.
6. Check you're really talking to each other: compare fingerprints in person once. Nicknames can be copied, keys can't.

Things to know: announcements (nickname and public keys) go out unencrypted, so anyone nearby can see you're there. Public messages stay sync-able for about 6 hours.

---

## Track B — asmmesh speaks bitchat

### Shape of the work

asmmesh and bitchat share almost no wire format, so this is a **second protocol stack beside asmmesh's own**. It should not be a change to asmmesh's packets.

- asmmesh stays exactly as it is (its own service UUID, P-256 signatures, protocol v3), and is walled off from bitchat (see below).
- A new **bitchat service** (its own Settings switch, off by default like every other service) advertises bitchat's GATT service, speaks bitchat's packets, and shows bitchat people and chat in asmmesh's UI.
- The mesh core (`ble.s`, `mesh.s`, `crypto.s`, …) is shared by the Mac and iPhone builds (`ios/make_project.py` lists the core `.s` files). New assembly files therefore serve both, and the iPhone only needs SwiftUI changes.

### The wall: integrated, but walled off

bitchat shows up inside asmmesh (People, Scanner, its own rooms), but nothing from bitchat can reach asmmesh's own mesh, keys, rooms or devices. Everything bitchat sends is treated as untrusted text from strangers.

**1. One narrow door.** All bitchat code lives in `src/bc_*.s`. The only way in is the bitchat Bluetooth characteristic. The only way out to the rest of asmmesh is a small set of UI events: *peer seen/gone* (ID, nickname, fingerprint), *message* (room, sender, text), and *delivery ack*. bitchat code never calls `mesh.s`, `ble.s`'s broadcast, FM, the web gateway, Home, rules or invites. asmmesh code never hands bitchat anything except text the user typed into a bitchat room.

**2. Separate packets.** bitchat packets are never relayed on asmmesh's mesh (Bluetooth or FM), never go into asmmesh's last-32 history, and are never parsed by asmmesh's packet decoder. asmmesh packets never go out on the bitchat characteristic. Each side has its own queues, dedup set and buffers.

**3. Separate keys.** bitchat's Curve25519 and Ed25519 keys are new, random, and stored in their own Keychain items. They are never derived from, signed by, or linked to the asmmesh P-256 identity, so nobody can connect your asmmesh identity to your bitchat one. The mesh passphrase and room keys are never used on the bitchat side.

**4. No authority.** Nothing that arrives over bitchat can:
- control devices, run Shortcuts or scenes, or trigger the `@name` remote commands
- set off rules ("when Anna arrives…"), reminders, alerts or SOS
- create, join or invite to asmmesh rooms, or move a message into one
- send files, fetch web pages, or open links automatically

bitchat rooms are display-only: incoming text is never parsed as a command, even if it says "kitchen lights off". Typing a command into a bitchat room sends it as chat text, never as a command.

**5. No impersonation.** bitchat people always carry a **bitchat** badge and their bitchat fingerprint, everywhere they appear. They are never merged with an asmmesh person who has the same name. If a bitchat nickname matches someone in your asmmesh People list, show a warning, as asmmesh already does for two people with the same name.

**6. Can't drown asmmesh.** bitchat gets fixed memory and rate limits: caps on peers, reassembly buffers (bitchat's own: 128 assemblies, 30 s, 1 MiB), dedup entries, and packets per second per link. asmmesh traffic has priority for Bluetooth writes. When a limit is hit, bitchat traffic is dropped and asmmesh carries on.

**7. Hardened parser.** The bitchat decoder is the main attack surface: it's assembly reading bytes from strangers. Every length is checked before it's used, zlib output is capped before inflating, and unknown types and TLVs are dropped. It's fuzzed under qemu with random and corrupted packets before it ships.

**8. Off really means off.** With the switch off, the bitchat service isn't advertised, nothing is scanned, the bitchat keys aren't loaded from the Keychain, and bitchat rooms are hidden. A **Forget bitchat** button deletes the bitchat keys, peers and history.

**9. Tests for the wall.** Self-tests check that the wall holds, for example:
- a bitchat message containing a Home command changes nothing
- a bitchat packet fed to asmmesh's decoder is rejected, and the other way round
- a bitchat nickname that matches an asmmesh person gets the badge and the warning
- a flood of bitchat packets doesn't delay asmmesh messages
- with the switch off, nothing is advertised and the Keychain isn't touched

A stronger option for later on the Mac: run the bitchat stack in a separate helper process that talks to asmmesh only through those UI events, so a bug in it can't touch asmmesh's memory. iOS doesn't allow this, so the in-process wall above is the baseline on both.

### What bitchat speaks (summary)

| Piece | bitchat |
|---|---|
| BLE service UUID | `F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C` (a `…4B5A` variant also appears in the source; find out what it's for) |
| Characteristic | `A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D` — notify, write, write-without-response, read |
| Identity | Curve25519 static key (Noise) + Ed25519 signing key |
| Peer ID | first 8 bytes of SHA-256 of the Noise static public key |
| Packet header v1 | version(1) type(1) TTL(1) timestamp ms(8, big-endian) flags(1) payload length(2) = 14 bytes |
| Packet header v2 | same, but payload length is 4 bytes = 16 bytes; may carry a source route |
| Then | sender ID(8), recipient ID(8, if flag 0x01), payload, Ed25519 signature(64, if flag 0x02) |
| Flags | 0x01 recipient · 0x02 signature · 0x04 zlib-compressed · 0x08 route · 0x10 RSR |
| Signing | Ed25519 over the packet with TTL excluded, so relays can decrement it (`toBinaryDataForSigning`) |
| Compression | zlib for payloads > 256 bytes, original size stored |
| Padding | PKCS#7-style to 256/512/1024/2048, only on Noise packets |
| Relay | TTL 7 at origin; dedup on sender+timestamp+type+payload digest (1000 entries, 5 min) |
| Private sessions | `Noise_XX_25519_ChaChaPoly_SHA256` |

Message types used here: `0x01` announce, `0x02` public message (UTF-8 text), `0x03` leave, `0x10` Noise handshake, `0x11` Noise encrypted, `0x20` fragment, `0x21` sync request. Others (`0x04` courier, `0x22` file, `0x23` board, `0x24` prekeys, `0x25` group, `0x26/27` ping/pong, `0x28` Nostr, `0x29` voice, `0x2C` rotating presence) are out of scope at first.

Announce payload is TLV: `0x01` nickname, `0x02` Noise public key, `0x03` Ed25519 public key, `0x04` up to 10 neighbour IDs, `0x05` capabilities, `0x06` bridge geohash. Unknown TLVs are skipped.

### Phases

**Phase 0 — groundwork**
- Pick the new service number and file names, and add them to `NOTES-for-other-sessions.md` so parallel sessions don't collide. *(Done: service 24, `src/bc_*.s`, a Settings card; the Mac window is now 5 x 5.)*
- Pin one bitchat release to test against, and install it on a spare iPhone or Mac.

**Phase 1 — crypto in assembly** (`src/bc_crypto.s`) — **done**
- Hand-written, with nothing from CommonCrypto, so the same file runs on the Mac, the iPhone and under qemu: SHA-256 and SHA-512, HMAC-SHA256, HKDF-SHA256 (RFC 5869), ChaCha20-Poly1305 (RFC 8439), X25519 (RFC 7748), and Ed25519 sign/verify (RFC 8032, refusing S ≥ L and keys that aren't on the curve).
- Constant-time: secrets never choose a branch or a memory address.
- Self-tests 127–144 use the published RFC and FIPS vectors, and run with `make selftest`.
- `tools/qemu/run.sh` runs them on Linux. `tools/qemu/run.sh diff 300` checks every function against Python's `cryptography` with random inputs and edge cases (Poly1305's reduction limits, X25519 inputs at or above p, low-order points).
- Keychain storage for the two bitchat keys moved to Milestone 1, where the keys are first needed and the off switch has to keep them unloaded.

**Phase 2 — Bluetooth link** (`src/bc_link.s`, `src/bc_ble.s`) — **works on a Mac (tried Oct 30, 2026)**
- The **bitchat** switch is service 24, off by default. It's a new card in Settings (the Mac window is now five columns by five rows, which is full). "enable all" leaves it off, and it can't be switched from the mesh.
- bitchat gets its own CBCentralManager, CBPeripheralManager and delegate class, so its callbacks never pass through asmmesh's controller. Each of its three entry points for outside bytes runs under the guard.
- Central: scans for bitchat's service only, connects (up to 8 links), subscribes to notifications, and writes without response when the radio has room.
- Peripheral: publishes the same service and characteristic, takes writes (long writes in pieces too), and notifies subscribers.
- Advertising bitchat's service waits for **"bitchat advertise on"**: two peripheral managers advertising at once has to be tried first, so asmmesh's own advert keeps working. Without it the Mac still links by connecting to the phones.
- Pure link layer, tested under qemu: packet length from the header, long writes per link (512-byte cap), fragment reassembly (8 sets, 64 pieces, 8 KiB, 30 s), bitchat's fragment layout and chunk size, and send queues.
- Incoming packets are only counted for now. **"bitchat"** in Home shows links and what was heard: hellos, public, private, fragments, refused.
- Self-tests 145–154. `tools/qemu/run.sh diff` also checks the link layer against `tools/qemu/bcwire.py`, a Python copy of bitchat's wire format.

*Checklist for the first Mac test:*
1. `make selftest`: 127–154 all PASS.
2. Settings: the bitchat row is there, off. Type "enable bitchat".
3. With bitchat open on a phone nearby, "bitchat" shows 1 linked and hellos counting up.
4. Another Mac running asmmesh still links as before (`ble.s` is unchanged).
5. "bitchat advertise on": the phone links to this Mac too ("found this Mac"), and step 4 still works. If asmmesh's own linking breaks, turn it off and note it here.
6. "disable bitchat": links drop, and "bitchat" says it's off.

*Results of the first Mac test (Oct 30, 2026, the App Store bitchat on an iPhone):*
- Steps 1–3 passed. With bitchat open on the iPhone, "bitchat" showed 1 linked (this Mac found it), and 11 packets heard: 6 hellos, 5 "other", none refused.
- Step 5 passed. After "bitchat advertise on", "found this Mac" went to 1, and asmmesh's own links stayed up while both services were advertised.
- Step 6 passed: "disable bitchat" drops the links and "bitchat" says it's off.
- Still to do: the bitchat build on iPhone (installed, not tried yet).
- The 5 "other" packets turned out to be sync requests (`0x21`), found in Phase 3.

**Phase 3 — packet codec** (`src/bc_packet.s`, `src/bc_zlib.s`) — **done: tested under qemu and on a Mac (Oct 30)**
- Ported from bitchat `04995f6` (still its latest commit on Oct 30): `BinaryProtocol.decode`, `toBinaryDataForSigning`, `PacketPayloadLimits`, `CompressionUtil.shouldCompress`, `MessagePadding`, `RelayController` and the receive pipeline's message id.
- `_bc_decode`: v1 and v2 headers, recipient, source route, signature, padding (tried as it is, then unpadded, as bitchat does), and bitchat's payload cap per type. Compressed payloads are raw DEFLATE (Apple's `COMPRESSION_ZLIB`), unpacked by libz (`bc_zlib.s`) into the caller's buffer, never past the declared size and with bitchat's 1032:1 ratio limit. The stream must end properly; that's stricter than Apple's decoder, but real senders' streams always do.
- `_bc_sign_data` / `_bc_verify`: what a signature covers is the packet re-encoded with TTL 0, no signature, no RSR flag, an empty route left out, and padded. It's rebuilt from the wire bytes, so compressed packets check out too. Relays lowering the TTL or setting RSR don't break it.
- `_bc_build`: our own packets (v1, like bitchat's ordinary traffic), signed with Ed25519. **A payload bitchat would compress can't be signed (-2):** bitchat compresses any payload of 100+ bytes with under 90% different byte values, and does it again when it checks a signature, so our signature would only match if our DEFLATE output were byte-identical to Apple's. Milestone 2 has to keep public messages under that rule (short, or split).
- `_bc_seen`: bitchat's duplicate filter (sender, time, type and 4 bytes of SHA-256 of the payload; 1000 entries, 5 minutes). `_bc_relay`: its TTL clamp and relay delay by type and number of links. Not used yet: relaying is Milestone 2, and not sending a packet back over the link it came in on belongs there (bc_ble.s).
- `bc_ble.s` now reads every packet it gets: a broken one counts as refused, and **"bitchat"** lists the types it doesn't name ("other kinds: 3 × sync request (0x21)"), which answers what the 5 "other" packets were.
- Self-tests 155–164 (`_bc_packet_selftest`): vectors from `tools/qemu/bcvectors.py`, including a packet we sign that matches the Python model byte for byte.
- `tools/qemu/run.sh diff` cross-checks decode, signing bytes, verify, build, the compression rule, relay and the duplicate filter against `tools/qemu/bcwire.py`, a Python copy of the Swift above (1000 random cases each, plus corrupted and cut-short packets): all agree. Under qemu, `tools/qemu/inflate.c` stands in for libz.
- Checked against a Python model, not against bitchat itself: the Mac test below is the real check.

*Checklist for the Mac:*
1. `make selftest`: 127–164 all PASS (157 is the one that uses libz).
2. With bitchat open on a phone: "bitchat" shows packets heard and **0 refused**, and an "other kinds" line if any arrive. Note which kinds here.
3. Send a public message from the phone: "public messages" goes up.

*Results on the Mac (Oct 30, 2026):* self-tests 127–164 pass (so libz unpacks bitchat's compression), every packet from the iPhone's bitchat was read with **0 refused**, and the 5 "other" packets from Phase 2 are **sync requests (`0x21`)**: bitchat asking its neighbours what they have, which never travels further than one link. Answering them is optional (Milestone 2).

**Milestone 1 — "I can see bitchat people"** (`src/bc_peer.s`, `src/bc_ble.s`) — **works on a Mac (Oct 30): each sees the other; iPhone build not tried yet**
- **Keys:** an X25519 (Noise) key and an Ed25519 signing key, 64 random bytes from `SecRandomCopyBytes`, in one Keychain item of their own (`asmmesh.bitchat`), never derived from or linked to the asmmesh identity. Read off the main thread when the switch goes on, wiped from memory when it goes off. New ones are made only when the Keychain says there are none; if it refuses, this Mac stays quiet on bitchat and says why. Our peer id is the first 8 bytes of SHA-256 of the X25519 key, as bitchat's.
- **Announcing:** our asmmesh name (cut to 26 bytes) and both keys, signed, as bitchat's `AnnouncementPacket`. Sent a tick after a link comes up, then every 15–19 s while there's a link (bitchat's sparse-mesh pace), without padding so the packet (at most 182 bytes) fits one write. No neighbour list or capabilities (both optional). A signed leave goes out when the switch goes off (best effort: the links drop right after).
- **Reading announces** (bitchat's preflight and trust rules): the sender id must come from the announced Noise key, not ours, under 15 minutes old, and signed by the announced signing key. That signing key is then pinned: another key for the same id is refused. A leave counts only when signed with the pinned key. People are forgotten a minute after their last announce (bitchat keeps verified peers 60 s); the table holds 32.
- **Showing them:** People (Mac and iPhone) lists bitchat people after asmmesh's, in orange, with their name, a **bitchat** label and their fingerprint (the peer id, the start of bitchat's own fingerprint), and nearby or how many hops. Nothing to click: they can't be invited, found or sent commands. If a bitchat name matches an asmmesh person's, the line starts with a warning that it's not the same person. "bitchat" also says who this Mac is on bitchat and how many announces were taken and refused; "bitchat people" lists everyone; "bitchat forget" deletes the keys and the people (this Mac only; with the switch on, new keys follow).
- Not done: the Mesh Scanner doesn't show bitchat devices (People does instead).
- For testing: "bitchat announce off" makes this Mac listen without announcing; "bitchat announce on" undoes it.
- Self-tests 165–172 (`_bc_peer_selftest`); `tools/qemu/run.sh diff` cross-checks announces, UTF-8 and the people table (coming, refused, leaving, forgotten) against `bcwire.py`.

*Checklist for the Mac and iPhone:*
1. `make selftest`: 127–172 all PASS.
2. With bitchat open on a phone and bitchat switched on here: "bitchat" says who this Mac is on bitchat (its name and fingerprint) and that announces are being sent.
3. Within a few seconds Home says the phone's bitchat name "is around", and it's in People in orange with a fingerprint. "bitchat people" lists it, and "announces refused" stays at 0.
4. On the phone, bitchat lists this Mac under nearby people with its asmmesh name. (That's bitchat checking our signature: the real test of Phase 3's signing.)
5. Close bitchat on the phone: within about a minute it leaves People here.
6. "disable bitchat": the phone's bitchat drops this Mac; People here has no bitchat people.
7. On an iPhone with the bitchat build of asmmesh: the People tab shows an "On bitchat" section.

*Results on the Mac (Oct 30, 2026, the App Store bitchat on an iPhone):*
- **Both directions work.** The Mac took the phone's announces (7 taken, 0 refused) and listed it, and **bitchat on the phone lists the Mac ("CC")**, so bitchat accepts our signed announce: Phase 3's signing is right.
- The phone then sent 2 sealed packets, most likely starting a Noise session with the Mac (it only does that with verified peers). Answering them is Milestone 3.
- The sync requests (`0x21`) keep coming (8 in a minute); answering them is optional (Milestone 2).
- What went wrong first: two copies of asmmesh were running at once, and the phone stopped sending to the Mac until its Bluetooth was switched off and on (Settings › Bluetooth). With one copy and a fresh phone link everything worked, announcing on or off. If a phone goes quiet again on a link that stays up, note what came before it here.
- Still to try: steps 5–7 (the phone leaving, switching off, the iPhone build).

**Milestone 2 — public chat both ways** (`src/bc_peer.s`, `src/bc_ble.s`, the bitchat room) — **written and tested under qemu (Oct 30); to be tried on a Mac**
- **The bitchat room** (local room id 4, after Home, Web and News; `LOCAL_ROOMS` is now 5, so there's room for 11 private rooms instead of 12). Mac and iPhone, orange, "Public chat with bitchat phones".
- **Messages in:** a public message (`0x02`: plain UTF-8, signed) shows as "Anna: text" only if it's from someone whose announce we took, signed with their pinned key, under 6 hours old, and real UTF-8; the rest is dropped (bitchat's rules, `BLEPublicMessageHandler`). At most 600 bytes are shown, control characters as spaces. If the name matches an asmmesh person's, the line starts with a warning. It's only shown: nothing in it is ever run as a command.
- **Messages out:** what you type in the bitchat room goes to bitchat as signed public messages, never as a command (it doesn't pass through the Home or chat-command paths). Long text goes in pieces of at most 96 bytes, cut at a space: each fits one write and stays under the 100 bytes bitchat would compress (a compressed payload couldn't carry our signature). With bitchat off, no keys yet or no phone linked, the room says so and nothing is sent.
- **Duplicates:** every packet but fragments goes through bitchat's duplicate filter (sender, time, type, payload digest; 1000, 5 minutes) before it's acted on or passed on.
- **Relaying for other bitchat users:** with two or more bitchat links, packets are passed on as bitchat's `RelayController` says (TTL rules by type and number of links), never back over the link they came in on, at most 20 a second, only to bitchat links. Not relayed: fragments (bitchat doesn't de-duplicate them, so they're left to the phones) and anything bigger than one write. Relaying goes out at once, without bitchat's random delay.
- Not done: answering sync requests (`0x21`) with recent history.
- Self-tests 173–175; `tools/qemu/run.sh diff` cross-checks message reading, splitting and the relay limit.

*Checklist for the Mac:*
1. `make selftest`: 127–175 all PASS.
2. With bitchat on and the phone linked: Rooms has a **bitchat** room (orange).
3. Send a public message from bitchat on the phone: it shows in the bitchat room as "<phone's name>: text".
4. Type in the bitchat room on the Mac: the phone's bitchat public chat shows it from "CC". Try a long message (over 96 bytes): it arrives in pieces.
5. Type "kitchen lights off" in the bitchat room: it goes to bitchat as text, and nothing happens to any light. A phone sending the same changes nothing either.
6. "bitchat" in Home: the "bitchat room" line counts messages shown and sent.

**Milestone 3 — private chat** (`src/bc_noise.s`)
- Noise XX handshake over `0x10`, sessions keyed by peer ID, rekeying, and replay protection.
- Read bitchat's `NoiseEncryptionService.swift` for the inner payload types (private message, delivery ack, read receipt) and copy them exactly.
- Each private chat opens as its own room, like asmmesh invites do now. Mark which conversations are Noise-encrypted.
- Outbox: retry until a delivery ack arrives (bitchat: 100 per peer, 24 h, 8 tries).

**Later / maybe**
- Favourites and courier mail (`0x04`), source routing, files (`0x22`), group messages (`0x25`), voice (`0x29`).
- Peer ID rotation (`0x2C`). It's still a draft in bitchat, so wait until it ships.
- **No automatic bridge.** Messages never cross between asmmesh rooms and bitchat on their own. If one is ever added, it's per message: the user picks a message and chooses to share it, and it arrives labelled as coming from the other network.

### Risks and open questions
- **Moving target.** bitchat's protocol is active (v2 headers, routing and rotation are all recent). Write the codec to be tolerant (skip unknown TLVs and types), and re-test against each new bitchat release.
- **Assembly crypto** is the hardest and riskiest part. RFC vectors plus cross-checks against real bitchat packets are a must.
- **Privacy.** Joining bitchat means advertising its service and sending your nickname and keys in the clear, as bitchat itself does. The switch must be off by default, with that explained next to it.
- **Battery and radio time** go up with two services advertising and scanning.
- Header version: bitchat sends v1 for ordinary packets and v2 for files and source-routed packets (`BLEService.swift`), and reads both. asmmesh sends v1.
