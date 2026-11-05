# asmmesh: App Store checklist

Status on Nov 4, 2026: **not ready**. This list says what stands between asmmesh and the
App Store (iPhone and iPad) and the Mac App Store. Each item says what's done already. It
follows Apple's App Review Guidelines as we know them; check each point against Apple's
current pages when you get to it, because they change.

## Reminders saved for when the App Store work starts

- **SPIN remote:** gestures 20-24 (touch-scroll, double-tap, sleep/wake) and the old LED
  service go beyond SPIN's published spec (they came from SPIN's Android app). Decide whether
  to keep them or limit the store build to the documented gestures 0-19. Show `CREDITS.md`
  (SPIN's MIT notice) in the app's About. Review notes: the app works without a SPIN; offer
  a video.
- **Web pages over the mesh:** hide them on iPhone for the first submission (unfiltered web
  access means a 17+ rating).
- **Fivefold:** never say "Wordle" anywhere in the store listing (name, subtitle, keywords,
  description, screenshots): the NYT owns the name, and Apple pulled Wordle copies under 4.1
  in 2022. Call it "a five-letter word game"; its own name and amber/blue colours stay.
- **bitchat:** say "works with bitchat" only (no logo, no hint of endorsement); review notes
  explain the wall (nothing from bitchat runs as a command or reaches rooms, devices, keys)
  and that block/report/filter cover bitchat chats; recheck bitchat's licence and credit it in
  `CREDITS.md`; test against the current bitchat release just before submitting, and run
  `make bitchat-check` (it also runs weekly and notifies on a change).
- **Mac:** ship outside the store first (Developer ID + notarization); the sandbox list is in
  section 5.

- ✅ done
- ⬜ to do
- ⚠️ a decision, or a risk that review may reject it

## 0. Before anything: does it work?

| Item                                                                                                   | State |
|--------------------------------------------------------------------------------------------------------|-------|
| Ninefold played on two Macs and two iPhones, one several hops away (3 rounds)                          | ⬜    |
| Chess over asmmesh (Mac and iPhone) and over a bitchat private chat with a real bitchat phone          | ⬜    |
| bitchat private chats (Noise) tried with a real bitchat phone                                          | ⬜    |
| Room "delete for everyone" reaching a device that was away                                             | ⬜    |
| Bluetooth: Connect, Pair in Settings (iPhone); batteries of speakers and headphones (Mac)              | ⬜    |
| Every service in Settings switched on and off once, on each platform                                   | ⬜    |
| A week of daily use on the Mac with no crash (`~/Library/Logs/asmmesh-guard.log` stays empty)         | ⬜    |
| Mac and iPhone self-tests pass (`make selftest`; `tools/qemu/run.sh`)                                  | ✅    |

Review tests on real devices, often only one, with no other asmmesh nearby. A mesh app
must still make sense alone: see 4.

## 1. Accounts and money

| Item                                                                                                                 | State |
|----------------------------------------------------------------------------------------------------------------------|-------|
| Apple Developer Program membership, paid yearly (US $99). The free Apple ID used now can't publish, and its apps stop opening after 7 days | ⬜ |
| App Store Connect: an app record for iPhone/iPad and one for the Mac (or one universal purchase)                     | ⬜    |
| Bundle IDs: `com.fbackman.asmmesh.ios` (iPhone) and the Mac's, registered on the developer account                    | ⬜    |
| The legal name to show as seller (yours or a company), and a support URL                                             | ⬜    |
| Agreements, tax and banking in App Store Connect (only needed if it isn't free)                                      | ⬜    |

## 2. Signing and building for release

| Item                                                                                                     | State |
|----------------------------------------------------------------------------------------------------------|-------|
| iPhone: an archive build (Release) signed for distribution, uploaded with Xcode or `xcrun altool`          | ⬜    |
| iPhone: TestFlight with the internal testers first (CC's iPhone, iphoney (2), oatmeal)                   | ⬜    |
| Mac: built in Xcode (or the Makefile extended) for an archive with a Mac App Store distribution profile  | ⬜    |
| Mac: hardened runtime on                                                                                 | ⬜    |
| Mac outside the store (optional, sooner): Developer ID signing and notarization (`xcrun notarytool`)     | ⬜    |
| Version and build numbers raised for every upload (`CFBundleShortVersionString`, `CFBundleVersion`)      | ⬜    |

## 3. Permissions, privacy and the files Apple asks for

| Item                                                                                                                                                                          | State |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------|
| Usage texts: Bluetooth, local network (+ Bonjour services), microphone, speech recognition, location (both); camera and Nearby Interaction (iPhone)                            | ✅ written, ⬜ reread so each says exactly why |
| `PrivacyInfo.xcprivacy` (the privacy manifest) in both apps: the "required reason" APIs used (UserDefaults; check file timestamps and system boot time too) and the data collected | ⬜ |
| Privacy policy at a public URL: what's stored on the device (Keychain keys, room keys, history, rules), what goes over the mesh, what goes to which services (Hue, SmartThings, Home Assistant, LIFX, Govee, ntfy, Pushover, weather) | ⬜ |
| App Store "privacy nutrition label": most likely "Data Not Collected" by the developer, but answer it for location, audio and identifiers honestly                          | ⬜    |
| Export compliance: asmmesh uses encryption beyond HTTPS (P-256, X25519, Ed25519, ChaCha20-Poly1305, AES). Set `ITSAppUsesNonExemptEncryption` and answer App Store Connect's questions; this usually means a yearly self-classification report to the US Bureau of Industry and Security, and some countries (France) ask for a declaration | ⬜ ⚠️ |
| Credits in the app (About): `CREDITS.md` — SPIN remote's MIT notice, and ENABLE (public domain), SCOWL, wordfreq, WordNet, LDNOOBW (CC BY 4.0), Wiktionary (CC BY-SA 4.0) from `tools/ninefold/SOURCES.md` | ✅ written, ⬜ shown in the app |

## 4. App Review: what's likely to be looked at

| Guideline                         | asmmesh                                                                                                                                        | State  |
|-----------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|--------|
| 1.2 User-generated content        | Chat apps must have: a way to report a message or person, a way to block someone, a filter for objectionable content, and a published contact. Block, report (an email to the report address) and a filter are in (safety.s, cf_core.s); still to do: set the report address to one you watch, answer reports within 24 hours, publish a contact. Ejecting someone for everyone: the developer blocklist (docs/blocklist.md), once you make its key | ✅ built, ⬜ the address, the contact, the blocklist's key and URL |
| 1.2 / 5.1.1 Anonymous chat        | Chat with people nearby without accounts gets extra attention: blocking and reporting must be easy to find                                     | ⬜ ⚠️ |
| 2.1 App completeness              | No placeholders, no "not tried yet", no crashes; a reviewer alone must find something that works (Home, sensors, Hue, the scanner)            | ⬜     |
| 2.3 Accurate metadata             | The description must not promise what iOS stops (pairing speakers, their batteries, relaying with the screen off)                             | ⬜     |
| 2.5.4 Background modes            | `bluetooth-central` and `bluetooth-peripheral` are declared; the review notes must say why (the mesh relays messages)                          | ⬜     |
| 2.5.1 Public APIs only            | Mac: `IOBluetoothDevice batteryPercentSingle/Left/Right` are not documented (AirPods' batteries) and may count as private API; `system_profiler` is a public tool | ⬜ ⚠️ |
| 4.2 Minimum functionality         | Fine: a lot works without other people                                                                                                         | ✅     |
| 5.1.2 Data use                    | Nothing is sent to the developer; say so                                                                                                       | ✅     |
| SPIN remote                       | Follows SPIN's published, MIT-licensed developer spec (`CREDITS.md`); gestures 20-24 go beyond it. Review notes: the app works fully without a SPIN; offer a video | ✅ ⬜ the notes |
| 5.2 Intellectual property         | Names of other products (Hue, SmartThings, bitchat, AirPods) only to say what it works with; no logos. Ninefold is our own game and puzzles   | ✅ ⬜ reread the texts |
| 4.7 / 2.5.2 Code that downloads code | none                                                                                                                                         | ✅     |
| Interop with bitchat              | asmmesh talks to another app's open protocol; keep it walled off as now, and say so in the review notes                                        | ⚠️    |

Review notes should explain how to try the mesh with one device (Home, the scanner,
Ninefold alone in its lobby, chess needs two) and offer a video of two devices.

## 5. The Mac App Store needs the App Sandbox

The Mac app isn't sandboxed today. The store requires it, and several features have to
change or go:

| Feature                                        | In the sandbox                                                                    | State  |
|------------------------------------------------|-----------------------------------------------------------------------------------|--------|
| Bluetooth, mesh, Bonjour, Hue, cloud services  | entitlements: `device.bluetooth`, `network.client`                                 | ⬜     |
| Files on Wi-Fi (port 8788), webhook (port 8787), the web gateway | `network.server`; review will ask why a chat app runs servers | ⬜ ⚠️  |
| Files' folder chooser                          | `files.user-selected.read-write` and security-scoped bookmarks                    | ⬜     |
| Microphone (Talk), speech, location            | `device.audio-input`, `personal-information.location`                             | ⬜     |
| FM radio (microphone and speaker as a modem)   | allowed with audio entitlements; explain it                                       | ⬜ ⚠️  |
| `system_profiler` for batteries                | a child process inherits the sandbox; test that it still answers                  | ⬜ ⚠️  |
| Shortcuts, running other apps, AppleScript      | needs temporary exceptions that review rarely accepts; may have to go             | ⬜ ⚠️  |
| `~/Library/Logs/asmmesh-guard.log`             | moves into the app's container                                                    | ⬜     |
| Pinning to the Dock, `/Applications` install   | not the app's job in the store (`install.sh` stays for builds outside it)        | ⬜     |

Outside the store (Developer ID and notarization) none of this is needed, and the app can
ship as it is.

## 6. The store pages

| Item                                                                                       | State |
|--------------------------------------------------------------------------------------------|-------|
| Name, subtitle, keywords, description (what works on iPhone and what only on the Mac)       | ⬜    |
| Category: Social Networking or Utilities (iPhone); Utilities (Mac)                          | ⬜    |
| Age rating: chat with strangers nearby, so likely 12+ or 17+ (unrestricted web gateway)    | ⬜ ⚠️ |
| Screenshots: iPhone 6.9" and iPad 13" (required sizes as of now), Mac 1280×800 or larger   | ⬜    |
| App icon 1024×1024 without transparency (in the asset catalogue already for the iPhone)    | ⬜ check |
| Support URL and marketing URL; contact for review                                          | ⬜    |

## 7. Suggested order

1. Make it work: section 0, with the devices you have.
2. Join the Developer Program; ship to your phones by TestFlight instead of the 7-day free
   signing.
3. Add report, block and a filter to chat (1.2): the biggest blocker.
4. Privacy manifest, privacy policy, export compliance, credits.
5. iPhone to App Review.
6. Mac: Developer ID and notarization first (no sandbox needed); the Mac App Store after
   the sandbox work in section 5, if it's still wanted.
