# asmmesh roadmap

Written Oct 28, 2026, from the top-of-file notes in every source file, the iPhone stubs, a search of the comments for known limits, and a passing `make selftest` (0 failures). The code has almost no TODO comments, so this list comes from stubs, limits and gaps between the code and the docs.

## Features that need work

1. **iPhone parity.** These are stubbed out in `ios/asm/ios_ui.s`:
   - FM radio: `_fm_start`, `_fm_stop` and `_fm_tx_packet` do nothing.
   - The device's own battery level: the IOKit calls return 0.
   - The SPIN settings window and other Mac-only views.
   - iOS only scans for Bluetooth while the app is open, so a locked iPhone stops relaying.
2. **Fixed table sizes.** Larger meshes will hit these:
   - 16 linked Bluetooth peers (`PEER_MAX`, `src/ble.s`)
   - 32 people on the mesh (`NODE_MAX`, `src/macros.inc`)
   - 16 rooms (`ROOM_MAX`, `src/macros.inc`)
   - 32 stored messages for people who come back later (`STORE_N`, `src/mesh.s`)
   - 64 known keys (`KEYS_N`, `src/ident.s`)
3. **Settings is full.** The service-switch grid holds 24 (3 x 8) and `NSVC` is 24, so a new integration needs a new layout first.
4. **Bluetooth Hue bulbs** (without a bridge) are still experimental (`src/hue.s`).
5. **Web gateway.** A Mac only takes a page from the first gateway it hears, so if that gateway drops mid-page there's no switch to another (`src/web.s`).
6. **Test coverage.**
   - "Find someone on the mesh" (`src/seek.s`) has only a few self-test mentions, and the Swift side (`ios/asmmesh/FindView.swift`) has none.
   - Voice, the cloud integrations and the Bluetooth link itself can't be self-tested.
7. **Rules and schedules only run while asmmesh is open.** One-off schedules are lost when you quit.
8. **Signing.** Every rebuild makes macOS ask again for Bluetooth and the Keychain, until an Apple Development certificate is set up.

## Docs and cleanup

- `_to_delete/` on the Mac mini holds two leftover archives (the folder is in `.gitignore`, so it isn't in the repository).

## bitchat (Jack Dorsey's Bluetooth mesh app)

Not integrated: nothing in the code mentions bitchat, Noise or Nostr. The two apps can't talk to each other. asmmesh uses its own Bluetooth service and its own signed packet format (protocol v3). As far as we know, bitchat advertises a different Bluetooth service with its own packet format, encrypts private chats with the Noise protocol, and uses Nostr when there's no Bluetooth link.

Linking them would mean a bridge that also speaks bitchat's protocol, probably starting with its public chat only. Check bitchat's current code before planning this, since these details may be out of date.
