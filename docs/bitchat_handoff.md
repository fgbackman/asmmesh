# bitchat in asmmesh: handoff (Oct 31, 2026)

Where the bitchat work stands, how it's built and tested, what's been seen working on real
hardware, and what comes next. `docs/bitchat_roadmap.md` is the plan and the per-phase
detail; `NOTES-for-other-sessions.md` lists the numbers taken. This file ties them together
for whoever picks the work up next.

## 1. Status in one screen

| Step | What | State |
|---|---|---|
| Track A | Use the bitchat app as it is | Nothing to build |
| Phase 1 | Crypto in assembly (`bc_crypto.s`) | Done; tests 127–144 pass on the Mac |
| Phase 2 | Bluetooth link (`bc_link.s`, `bc_ble.s`) | **Works on a Mac**: linked both ways with the App Store bitchat on an iPhone |
| Phase 3 | Packet codec (`bc_packet.s`, `bc_zlib.s`) | **Works on a Mac**: every bitchat packet read, 0 refused |
| Milestone 1 | Seeing bitchat people (`bc_peer.s`) | **Works on a Mac**: each lists the other ("CC" shows up on the phone) |
| Milestone 2 | Public chat both ways, relaying | Written, self-tests pass; **not yet tried on a Mac** |
| Hardening 1 and 2 | Two deep reviews' fixes | Written, self-tests pass; **not yet tried on a Mac** |
| Guard-fault fix | `LINK` macro clobbered its own register | Fixed (`4154d9e`); **waiting for the Mac to confirm** |
| Milestone 3 | Private chat (Noise) | Not started |

The last thing seen on the Mac (build of `29f15b4`): the guard caught a steady stream of faults
at `bc_frame_in + 792`, address `0x2618`. That was the `LINK` macro bug (section 9), fixed in
`4154d9e`. The very next step is to run that build and confirm no new guard faults (section 6).

## 2. Where the code is

- **Branch:** `claude/bitchat-roadmap` on `github.com/fgbackman/asmmesh`, 17 commits on top of
  `61cd2ee` ("Find someone on the mesh…").
- **`main`** has moved on by two commits since then (`be7464f` added `ROADMAP.md`, `94a6653`
  fixed docs). Nothing on the branch is merged yet.
- **Merging into main:** a test merge conflicts only in `README.md`, the last line of the packet
  format section: keep main's v3 table and the branch's "Web (2), News (3) and bitchat (4), like
  Home (1), are local rooms". After merging, `ROADMAP.md` on main still says "nothing in the code
  mentions bitchat"; that section needs rewriting, pointing at `docs/bitchat_roadmap.md`.
- **Don't merge before** Milestone 2 and the hardening have been tried on the Mac
  (section 6): `main` is what's installed on the Mac mini.

### On the Mac mini

| Path | What |
|---|---|
| `~/Developer/asmmesh` | `main`, the installed copy (`/Applications/asmmesh.app`, build 16) |
| `~/Developer/asmmesh-bitchat` | worktree on `claude/bitchat-roadmap`: the test build, run from its own folder |
| `~/Developer/asmmesh-p3` | worktree at `945bab0` (Phase 3), used once to compare; remove with `git worktree remove ../asmmesh-p3` |

**Only one copy of asmmesh may run at a time.** Two copies fight over Bluetooth, and early in the
Milestone 1 test that alone made it look as if nothing worked. `pgrep -lx asmmesh` must show one.

## 3. What it is: the wall

bitchat (permissionlesstech/bitchat, Jack Dorsey's Bluetooth mesh chat) uses its own service,
packet format and keys. asmmesh speaks it as a **second stack beside its own**, behind a wall:
bitchat shows up in asmmesh (People, its own room), but nothing from bitchat reaches asmmesh's
mesh, rooms, keys, devices or rules, and asmmesh's identity is never linked to its bitchat one.

How the wall is kept, concretely:
- **Code:** everything bitchat lives in `src/bc_*.s`, with its own `CBCentralManager`,
  `CBPeripheralManager` and delegate class (`AMeshBitchat`). bitchat callbacks never pass through
  `ble.s` or the AMeshController method tables.
- **Packets:** bitchat packets are never relayed on asmmesh's mesh (Bluetooth or FM), and
  asmmesh packets never go out on bitchat links.
- **Keys:** bitchat has its own X25519 and Ed25519 keys (Keychain item `asmmesh.bitchat`),
  random, never derived from or linked to the asmmesh P-256 identity. Its announces carry a
  separate name ("anonNNNN" by default, `bitchat name …` to change it), never the asmmesh name.
- **No authority:** text from bitchat is only ever shown. Text typed in the bitchat room goes
  only to `_bc_say` (bc_ble.s), never through Home's command parser or `_chat_route`. Nothing
  from bitchat can run a command, trigger a rule, invite, join, send files or fetch pages.
- **Not over the mesh:** "bitchat", "bitchat people", "bitchat name", "bitchat forget", the
  advertise and announce switches all refuse remote asmmesh commands (`_g_remote_active`), and
  lines bitchat writes to Home from its own callbacks go straight to Home (`Lbc_note`), never into
  a remote command's reply.
- **Off means off:** the switch (service 24) is off by default; "enable all" leaves it off,
  "disable all" switches it off. Off: nothing advertised or scanned, keys and people wiped from
  memory, the bitchat room removed.

## 4. Files

| File | What | Runs under qemu |
|---|---|---|
| `src/bc_crypto.s` | SHA-256/512, HMAC, HKDF, ChaCha20-Poly1305, X25519, Ed25519, hand-written, constant-time | yes |
| `src/bc_link.s` | link layer, bytes only: packet length, long writes, fragments (per-link sets), send queues | yes |
| `src/bc_packet.s` | decode, signing bytes, verify, build/sign, duplicate filter, relay rule | yes |
| `src/bc_zlib.s` | `_bc_inflate`: raw DEFLATE through libz (qemu uses `tools/qemu/inflate.c`) | no |
| `src/bc_peer.s` | announces, people table, leaves, public messages, pins, text cleaning, look-alike names, weak keys, rate limits | yes |
| `src/bc_ble.s` | CoreBluetooth, Keychain, announcing, reading, relaying, the bitchat room, Home words, People rows | no |
| `src/bc_defs.inc` | every bitchat layout and limit (DP_, DD_, AN_, BT_, PN_, RL_, FA_, IB_, Q_) | — |
| `tools/qemu/run.sh` | builds the pure files for Linux/ARM64, runs the self-tests (or `diff N`) | — |
| `tools/qemu/bcwire.py` | a Python copy of bitchat's rules (from its Swift), the reference everything is checked against | — |
| `tools/qemu/diff.py` | random and corrupted cases through the assembly vs `bcwire.py` | — |
| `tools/qemu/bcvectors.py` | makes the self-tests' packets (`… peer`, `… msg`, `… pin` for the other files) | — |
| `tools/qemu/lint.py` | ENTER/LEAVE sizes and `LINK` registers (run.sh runs it first) | — |

Touched outside `bc_*`: `mesh.s` (bitchat room typing → `_bc_say`, `_room_drop`), `ui.s`
(People rows, room header), `cards.s` (bitchat people and room cards), `rules.s` (Home words),
`services.s` (switch 24, Settings 5×5, disable all), `net.s` (`_kc_del`, `_kc_get` returns its
status in x1), `ident.s` (`_id_ready` uses its own read's status), `listed.s`/`mesh.s`/`ident.s`
(room arrays sized from `ROOM_MAX`), `scanner.s`/`ios_ui.s` (`_bc_tick` once a second),
`test.s`, the iPhone's `Mesh.swift`, `PeopleView.swift` and bridging header.

### A packet's way in (bc_ble.s)

1. A write or notification → `_bc_rx` → `_bc_inbox_put` (long writes, gap-free) → `_bc_frame_in`.
2. `Lbc_read` → `_bc_decode` (refused → counted). Counted by type.
3. Fragments → `_bc_frag_put` (sets tied to their link) → the joined packet goes back to step 2.
4. Announce / leave / message: looked up in the duplicate filter (not recorded yet), 15 signature
   checks a second per link, then `Lbc_heard` / `Lbc_left` / `Lbc_message`. Only if taken: recorded
   in the filter and passed on. Other kinds: recorded, passed on.
5. `Lbc_forward`: bitchat's TTL rule, ≥2 distinct phones, never back to the link or phone it came
   from, 20 a second.

## 5. Interfaces and numbers

- **Home words:** `bitchat` (status), `bitchat people`, `bitchat name …`, `bitchat forget`,
  `bitchat advertise on/off`, `bitchat announce on/off` (testing), `enable/disable bitchat`.
- **Settings:** service 24 (`SVC_BITCHAT`), `NSVC` 25; the Mac window is 5 columns × 5 rows (full).
- **Rooms:** `BITCHAT_ID` 4, `LOCAL_ROOMS` 5, `ROOM_MAX` 17. The bitchat room exists only while
  bitchat is on: find it with `_room_find`, never by index.
- **People:** rows past `_g_node_count` are bitchat people. Any new code that takes a People row
  as an index into `_g_nodes` must check it against `_g_node_count` first.
- **Keychain:** `asmmesh.bitchat` (our two keys, hex), `asmmesh.bitchat.pins` (signing keys
  seen). All Keychain work for them runs on one serial queue, off the main thread.
- **Defaults:** `bitchatName`.
- **Self-tests:** 127–144 crypto, 145–154 and 177–178 link, 155–164 packets, 165–176 and
  179–183 people, chat and hardening. 57 in all; `make selftest` runs them with the rest.
- **asmmesh packet types:** none added; bitchat packets never touch asmmesh's mesh.

## 6. How to test

**Here (Linux, no Mac):**

```bash
tools/qemu/run.sh            # lint, then every pure self-test
tools/qemu/run.sh diff 300   # 300 random cases per check against bcwire.py
```

Install once: `apt-get install gcc-aarch64-linux-gnu qemu-user`, `pip install cryptography`.
For the Mac-only files, `clang -target arm64-apple-macos12 -c src/X.s -I src` (and
`-target arm64-apple-ios15`) catches assembly errors, and `llvm-nm` on the objects finds missing
symbols; nothing here can run CoreBluetooth, the Keychain or the UI.

**On the Mac (the next step):**

```bash
cd ~/Developer/asmmesh-bitchat && git pull && make selftest && make && (pkill -x asmmesh || true) && sleep 3 && open asmmesh.app && sleep 3 && pgrep -lx asmmesh
```

`make selftest` only builds the command-line test binary; `make` builds `asmmesh.app`. Use both,
or the app opened is the previous build.

Then, with bitchat open on the iPhone (screen on, in front):
1. `enable bitchat`; after a minute no new 🛡 lines (`tail -n 5 ~/Library/Logs/asmmesh-guard.log`:
   the newest time doesn't move).
2. `bitchat`: this Mac's bitchat name and fingerprint, announces sent, 0 refused.
   `bitchat name CC` keeps the old name.
3. `bitchat people`: the phone, **nearby**. The phone lists the Mac.
4. The bitchat room appears; a public message from the phone shows as "Name (1a2b): text";
   one typed on the Mac shows on the phone (over 96 bytes: in pieces).
5. `kitchen lights off` typed in the bitchat room arrives on the phone as text; no light changes.
6. `disable bitchat`: the room goes, the phone drops the Mac.
7. iPhone build (`ios/Install on iPhone.command` from the bitchat worktree): People has an
   "On bitchat" section. The Swift has never been compiled.

If the phone goes quiet on a link that stays up: check for a second asmmesh copy, then switch
the phone's Bluetooth off and on in Settings › Bluetooth.

## 7. Security: what's covered, what's left

Covered (details and tests in the roadmap's two hardening sections): signatures as bitchat checks
them; pinned signing keys, kept for good; replays (time floors, 5-minute future limit, message
floor); weak Ed25519 keys; forged copies can't block real ones; per-link limits on checks, links
and fragment sets; text cleaned of control, line-break, direction and invisible characters;
look-alike names flagged; fingerprints on every bitchat line; the wall over the mesh; a separate
name; Keychain races; the asmmesh identity can't be replaced by another read's status. The second
review found no memory-safety holes in the parser, link layer, reassembly or DEFLATE wrapper.

Left on purpose, or not fixable without more protocol:
- **Fragments are unauthenticated** in bitchat itself: a stranger on the same link can still spoil
  a set. Sets are now per link, so other links aren't affected.
- **TTL isn't signed**, so hop counts aren't shown; "nearby" means a link of ours is tied to them.
- **First contact is trust-on-first-use:** a stranger who announces someone's Noise key with their
  own signing key *before we've ever seen the real one* gets pinned. Noise authentication
  (Milestone 3) is what really binds the two keys.
- **Not relayed:** fragments and anything bigger than one write; no random relay delay.
- **Sync requests** (`0x21`, about 8 a minute from a phone) aren't answered: late joiners don't
  get history from us.
- **Assembly crypto:** RFC vectors and random cross-checks pass, and the second review checked the
  field arithmetic, but "constant-time" has not been measured by a tool.
- **Signature checks run on the main thread** at about twice the needed cost (two constant-time
  scalar multiplies where verification could use a variable-time double multiply).

## 8. Roadmap from here

**Now**
1. Confirm the `LINK` fix on the Mac (section 6, step 1), then run the whole Milestone 2
   checklist and record the results in `docs/bitchat_roadmap.md`.
2. Try the iPhone build (step 7). Compile errors in `Mesh.swift` / `PeopleView.swift` are possible.
3. Remove `~/Developer/asmmesh-p3`.

**Before merging into main**
4. Bring `README.md` up to date: the files list still calls `bc_crypto.s` "not used yet" and lacks
   `bc_packet.s`, `bc_peer.s`, `bc_zlib.s` and `tools/qemu`'s new files; add a short bitchat section
   (switch, room, Home words, the wall).
5. Merge `main` into the branch (one README conflict), rewrite main's `ROADMAP.md` bitchat
   section, run `make selftest` and the checklist again, then merge.

**Milestone 3: private chat** (`src/bc_noise.s`, new)
- `Noise_XX_25519_ChaChaPoly_SHA256` handshake over `0x10`, sessions per peer, rekeying, replay
  windows; the primitives are all in `bc_crypto.s` already.
- Copy the inner payload types (private message, delivery ack, read receipt) exactly from
  bitchat's `NoiseEncryptionService.swift`; re-check against bitchat's current source first.
- A completed handshake on a link authenticates that peer: bind the Noise static key to the
  pinned signing key there (closes the first-contact gap in section 7).
- Each private chat its own room; an outbox retrying until a delivery ack (bitchat: 100 per peer,
  24 h, 8 tries).
- The phone already starts handshakes with the Mac ("2 private (sealed)" in the status): the
  first test case is answering that.

**Later / maybe**
- Answer sync requests (`0x21`, GCS filters) so late arrivals get recent messages.
- Relay fragments, with bitchat's delay; send our own long packets as fragments instead of
  keeping messages to 96 bytes.
- Favourites and courier mail (`0x04`), files (`0x22`), groups (`0x25`), voice (`0x29`);
  peer-ID rotation (`0x2C`) once bitchat ships it.
- Mesh Scanner rows for bitchat devices.
- Cleanups: one shared byte-copy helper (there are four), drop dead link-layer code, a faster
  variable-time Ed25519 verify, a per-row-kind accessor for People.

## 9. Gotchas learned the hard way

- **`make selftest` doesn't rebuild the app**: run `make` too (section 6).
- **Two asmmesh copies** break bitchat in confusing ways. `pgrep -lx asmmesh`.
- **A stuck phone:** after a lot of testing, an iPhone's bitchat can stop sending on a link that
  stays up. Settings › Bluetooth off and on fixes it.
- **`LINK reg, idx`** (bc_ble.s) uses `x17` as scratch: never pass x17, never the same register
  twice. It used `x9`, and `LINK x9, x21` read address 0x2618 on every relayed packet.
  `tools/qemu/lint.py` checks this.
- **ENTER n** puts locals at `[sp, #96]` onward; `[sp]` to `[sp, #31]` is where variadic
  arguments go (Apple ARM64 passes them on the stack: `str x9, [sp]` before `bl _snprintf`).
  LEAVE must use the same n: lint.py checks.
- **Callee-saved:** ENTER saves x19–x24 only. A function using x25/x26 saves them itself.
- **Offsets over 4095** (`L_VL` and friends in the link table) can't be an `add` immediate:
  `mov x9, #L_VL; add x0, x0, x9`. `ldr`/`str` offsets are fine.
- **Leaf functions** may use x9–x17 freely; anything that calls `bl` loses x0–x18.
- **Shell heredocs:** an unquoted `<<EOF` expands `$out` and friends inside Python patches; quote
  it (`<<'EOF'`).
- **bitchat's compression:** a payload of 100+ bytes with under 90% distinct byte values gets
  compressed by bitchat when it checks a signature, so we never sign one (`_bc_build` returns -2).
  Our messages go in pieces of 96 bytes.
- **Signing bytes** are rebuilt from the wire (TTL 0, no signature, no RSR, padded), so compressed
  packets verify without recompressing.
- **The protocol moves:** everything here follows bitchat commit `04995f6` (Oct 25, 2026). Check
  its current `BinaryProtocol.swift`, `Packets.swift`, `BLEService.swift` and
  `NoiseEncryptionService.swift` before Milestone 3.
