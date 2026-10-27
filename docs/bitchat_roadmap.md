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

- asmmesh stays exactly as it is (its own service UUID, P-256 signatures, protocol v3).
- A new **bitchat service** (its own Settings switch, off by default like every other service) advertises bitchat's GATT service, speaks bitchat's packets, and shows bitchat people and chat in asmmesh's UI.
- The mesh core (`ble.s`, `mesh.s`, `crypto.s`, …) is shared by the Mac and iPhone builds (`ios/make_project.py` lists the core `.s` files). New assembly files therefore serve both, and the iPhone only needs SwiftUI changes.

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
- Pick the new service number and file names, and add them to `NOTES-for-other-sessions.md` so parallel sessions don't collide. The Settings grid (3 × 8) is full, so it needs another row or page.
- Pin one bitchat release to test against, and install it on a spare iPhone or Mac.

**Phase 1 — crypto in assembly** (`src/bc_crypto.s`)
- CommonCrypto already gives SHA-256, SHA-512 and HMAC, and `-lz` is already linked for zlib.
- Hand-write: **X25519** (RFC 7748), **Ed25519** sign/verify (RFC 8032, uses SHA-512), **ChaCha20-Poly1305** (RFC 8439), and **HKDF-SHA256** on top of HMAC.
- Keep it constant-time: no secret-dependent branches or table lookups.
- Self-tests with the RFC test vectors, run under qemu like `sens_decode.s`.
- Store the two private keys in the Keychain next to the existing identity, following `ident.s` (only regenerate on "not found").

**Phase 2 — Bluetooth link** (`src/bc_ble.s`)
- Advertise bitchat's service as well as asmmesh's, and scan for both.
- Central role: connect, subscribe to notify, write packets. Peripheral role: accept writes, and send to subscribers by notify.
- Handle MTU, chunking and reassembly, plus fragment packets (`0x20`, ~469-byte pieces).
- iOS: check background advertising with two services; iOS moves background service UUIDs into an overflow area.

**Phase 3 — packet codec** (`src/bc_packet.s`)
- Encode and decode v1 and v2 headers, flags, zlib, padding, and signatures.
- Copy bitchat's own test packets from `bitchatTests` as self-tests, so the codec is byte-for-byte identical.
- Dedup set and relay rules (TTL clamp, never relay back to the link a packet came in on).

**Milestone 1 — "I can see bitchat people"**
- Send a signed announce (nickname from asmmesh's name, both public keys, capabilities) every few seconds when alone, backing off to 15–30 s.
- Verify incoming announces and list bitchat peers in People with a "bitchat" tag and their fingerprint. Handle leave (`0x03`).
- Show bitchat devices in the Mesh Scanner.

**Milestone 2 — public chat both ways**
- New **bitchat** room. Incoming `0x02` messages appear there with the sender's nickname. Messages typed there go out signed.
- Keep it separate from Main: bitchat messages are verified with bitchat's Ed25519 keys, not asmmesh's P-256 identities, so they shouldn't look like asmmesh traffic.
- Relay bitchat packets for other bitchat users like any bitchat node does.
- Optional: answer sync requests (`0x21`, GCS filters) so late arrivals get recent history.

**Milestone 3 — private chat** (`src/bc_noise.s`)
- Noise XX handshake over `0x10`, sessions keyed by peer ID, rekeying, and replay protection.
- Read bitchat's `NoiseEncryptionService.swift` for the inner payload types (private message, delivery ack, read receipt) and copy them exactly.
- Each private chat opens as its own room, like asmmesh invites do now. Mark which conversations are Noise-encrypted.
- Outbox: retry until a delivery ack arrives (bitchat: 100 per peer, 24 h, 8 tries).

**Later / maybe**
- Favourites and courier mail (`0x04`), source routing, files (`0x22`), group messages (`0x25`), voice (`0x29`).
- Peer ID rotation (`0x2C`). It's still a draft in bitchat, so wait until it ships.
- A **bridge** that carries messages between asmmesh rooms and bitchat. Only add it with clear labels and the user's consent, because the two trust models differ.

### Risks and open questions
- **Moving target.** bitchat's protocol is active (v2 headers, routing and rotation are all recent). Write the codec to be tolerant (skip unknown TLVs and types), and re-test against each new bitchat release.
- **Assembly crypto** is the hardest and riskiest part. RFC vectors plus cross-checks against real bitchat packets are a must.
- **Privacy.** Joining bitchat means advertising its service and sending your nickname and keys in the clear, as bitchat itself does. The switch must be off by default, with that explained next to it.
- **Battery and radio time** go up with two services advertising and scanning.
- Which header version current bitchat clients send by default, and whether v1-only clients are still accepted. Check before Phase 3.
