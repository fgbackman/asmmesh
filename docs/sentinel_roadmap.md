# Sentinel roadmap

**Sentinel** is asmmesh's watchtower: one eye on everything asmmesh can see, from the code it's built from to the radio around it. It looks for weaknesses before attackers find them, spots attacks while they happen, shuts out whoever is behind them, and tells you plainly what it saw.

## What it can and can't do

| Level | What Sentinel can do | Limits |
|---|---|---|
| **Code** (before it ships) | Fuzz every decoder, run every self-test, compare the crypto against known-good libraries | Finds bugs in asmmesh, not in macOS or iOS |
| **App** (while running) | See every packet, signature, crash, flood and odd peer | — |
| **Radio** | Watch Bluetooth LE and FM for spoofing, floods and strangers who stay close | Only what this device's radio hears |
| **Network** | Check asmmesh's own open ports and connections | No packet sniffing; that needs root |
| **Device** (Mac) | Read-only checks: OS updates, SIP, Gatekeeper, FileVault, firewall, asmmesh's own code signature | Checks settings; it can't change them for you |
| **Kernel** | Mac only, much later: an Endpoint Security system extension | Needs a special entitlement from Apple and a separate signed helper. The iPhone sandbox allows none of this |

So "from the kernel up" is realistic on the Mac, step by step. On the iPhone, Sentinel stops at the app and its radio.

## Ground rules

1. **Defence only. Never hack back.** Attacking someone's device is illegal almost everywhere. It can also hit the wrong person, because Bluetooth names and addresses are easy to fake. Sentinel blocks, ignores, slows down and reports. It never sends anything meant to harm the other side.
2. **"Talking to hackers" means one short, signed notice.** When Sentinel blocks a peer, it can send one notice: "You're blocked by this device until <time>." After that it goes silent. It doesn't argue, negotiate or reply again, because every reply gives an attacker information and something new to attack.
3. **Sentinel is behind its own wall.** It reads from the rest of asmmesh but can't command anything: no devices, rules, rooms or keys. A bug in Sentinel must not give an attacker more power than they had. It follows the same rules as the bitchat wall (`docs/bitchat_roadmap.md`).
4. **You stay in charge.** Automatic blocks are temporary (minutes to hours) and listed with the reason. You can unblock with one click. Permanent blocks and anything shared with other devices need your OK.
5. **Private by default.** Sentinel's log stays on the device. Nothing is sent anywhere unless you choose to share it with your own devices or people you trust.

## Phases

### S0 — one place for every warning sign
asmmesh already notices a lot, but each part keeps it to itself. Sentinel starts by collecting it all into one event log (`src/sentinel.s`, a ring buffer):
- packets that crashed a decoder and were caught (`guard.s`, now in `asmmesh-guard.log`)
- flood limits hit (`limits.s`: unverified, relay, new-key buckets)
- bad signatures, replays older than 6 hours, packets that fail to decrypt
- two people with the same name, keys that change for a known name
- tracker alerts (`find.s`)
- bitchat wall hits: commands arriving from bitchat, oversized or broken bitchat packets

Each event records the time, kind, source (fingerprint or radio address), level and a short note. Self-tests check that each existing warning reaches the log.

### S1 — the Eye (Sentinel window)
- A radar like the Mesh Scanner's, with the threats on it: who, how close, and how bad.
- A threat score per peer, built from its events and fading over time. Crossing a threshold triggers an automatic temporary block.
- A **block list**: blocked peers are dropped at the radio's door, before any decoding. Each entry shows the reason, the evidence, the expiry and an Unblock button.
- The one-time signed "you're blocked" notice (ground rule 2).
- Plain-language alerts: "Someone nearby sent 400 broken packets in a minute and is blocked for 1 hour."
- Commands in Home: "sentinel", "sentinel log", "block <name>", "unblock <name>".

### S2 — bug hunting before release
- **Fuzzing:** run coverage-guided fuzzing (AFL++ in qemu mode, using the `tools/qemu/` setup from bitchat Phase 1) on every decoder that reads bytes from strangers: asmmesh packets, invites, FM frames, sensor adverts, and later the bitchat codec.
- Every crash found becomes a permanent fuzz template in `test.s`, as the guard log already asks.
- **Crypto cross-checks:** `tools/qemu/run.sh diff`, extended as new code arrives.
- **One command before every install:** self-tests, fuzzing for a set time, crypto cross-check, and a pass/fail summary. `Install asmmesh.command` refuses to install on a fail.

### S3 — radio watch
- **Bluetooth spoofing:** the same name with a different key, a known key from an unexpected place, many identities from one radio, or address changes that don't match normal privacy rotation.
- **Floods and jamming:** sudden storms of connections or broken packets. Sentinel slows down, then blocks.
- **Strangers who stay close:** the tracker alert, widened to any unknown device that follows you for a long time.
- **FM:** frames with good CRCs but bad signatures, which could mean someone is transmitting on purpose.

### S4 — this Mac's health (read-only)
- Checks: macOS up to date (`softwareupdate --list`), SIP on (`csrutil status`), Gatekeeper on (`spctl --status`), FileVault on (`fdesetup status`), the firewall's state, and asmmesh's own signature still valid (`codesign --verify` on itself).
- asmmesh's own exposure: which of its ports are open (the webhook on 8787, Files on Wi-Fi on 8788) and to whom, saved tokens still in the Keychain, and services switched on but unused.
- Results appear as a checklist with how to fix each item. Sentinel never changes system settings itself.

### S5 — sharing warnings with your own devices
- Your Mac and iPhone can share Sentinel alerts and blocks over the mesh, signed with your own key.
- Accepted only from your own devices, or from people you've marked as trusted, and only as **advice**: "Your Mac blocked this peer. Block here too?" Otherwise, an attacker could get innocent people blocked with fake reports.
- Never shared with bitchat or strangers.

### S6 — the kernel level (Mac only, optional, much later)
- An **Endpoint Security system extension** can see process launches, file opens and network connections at the kernel's level. It's the real "from the kernel up".
- It needs: an Apple Developer account, an entitlement Apple must approve, a separate signed helper app, and the user's approval in System Settings.
- It would run as its own process, reporting to Sentinel through a narrow, one-way channel. That way a bug in asmmesh can't reach kernel-level power, and the other way round.
- Decide after S0–S5 are in use. For most people, S4's checks plus macOS's own XProtect cover this level.

## Risks
- **False alarms** wear people out. Start with conservative thresholds, show the evidence, and keep automatic blocks short.
- **Abuse of blocking:** an attacker who can fake a trusted peer's identity could get that peer blocked. Blocks key on cryptographic fingerprints, not names or radio addresses, wherever there is one.
- **Sentinel as a target:** it reads everything, so its own parsers are fuzzed first (S2), and it holds no power to act outside its block list.
- **Battery:** S3's radio watching uses data asmmesh already receives, so it needs no extra scanning.
