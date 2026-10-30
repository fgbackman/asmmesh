# asmmesh

A Bluetooth LE mesh messenger for Apple Silicon Macs, written in ARM64 assembly. The Cocoa window and CoreBluetooth are driven entirely through the Objective-C runtime; there is no Swift or Objective-C source.

Each Mac is both a Bluetooth peripheral (it advertises an asmmesh service with a writable "inbox" and a readable "identity") and a central (it scans for that service, connects to every Mac it finds, and writes packets into their inboxes). Packets flood outward: every Mac handles a new packet, then passes a copy with one fewer hop left to all its neighbours; duplicates are dropped by packet id. The last 32 messages and invites a Mac has sent or relayed are handed to any Mac that links up later.

Version 0.3 adds:

- **Your own name.** Click the "You: ..." button (or Mesh › Change Name) and pick from your Mac's name, your full name, your first name, or type one. It is remembered.
- **People on the mesh.** Every Mac announces itself every 15 seconds, so the sidebar lists everyone reachable, nearby or several hops away.
- **Rooms.** Main is open to everyone and doubles as the mesh feed (who joined, links coming and going). Click + to make an invite-only room. Rooms are remembered between launches.
- **Listed rooms.** A room's owner can list it (Mac: Mesh › List This Room for Everyone; iPhone: the room's ⋯ menu › List for Everyone Nearby). Its name then shows up for everyone nearby who isn't in it (Mac: Mesh › Ask to Join a Room…; iPhone: *Rooms you can ask to join* in Rooms). Asking sends the owner a Let In / Not Now prompt; Let In sends the usual invite with the room's key, and it's taken without a second question. Only the owner can list a room (listings are signed), and unlisted rooms stay invisible.
- **Invites.** Select a person and click Invite to Chat. From a room, it invites them into that room; from Main, it starts a room for the two of you. They get a Join / Not now prompt. Room messages still hop through every Mac, but only members' windows show them.
- **Mesh Scanner.** A radar of every node (green = in Bluetooth range, placed by signal strength; amber = reached through other Macs, placed by hops) plus a table of name, signal, hops, last seen and messages relayed.

Version 0.4 adds the **Home room**: talk to your devices by typing or pressing **🎤 Talk** (Mesh › Talk, Cmd-T). Plain phrases: "kitchen lights off", "dim living room to 30%", "desk lamp blue", "all lights warm", "lock the front door", or a Shortcut's full name like "good night". "help" lists more; "devices" lists everything asmmesh knows.

- **Philips Hue Bridge** — found automatically on your network. Press the round button on the bridge, then say "pair hue". Lights, rooms and zones: on/off, brightness, colours, warm/white/cool.
- **Hue bulbs without a bridge** — spotted over Bluetooth and driven directly (experimental; macOS asks to pair each bulb, and the bulb must be in pairing mode).
- **SmartThings** — say "connect smartthings" and paste a personal access token (kept in your Keychain). Switches, dimmers, colour lights and locks.
- **Apple Home / Matter** — through your Shortcuts: say a shortcut's full name and it runs. Shortcuts only ever run on their full name, never on a partial match.
- **Other people's devices** — "@Anna hallway on" goes over the mesh; Anna's Mac asks her to Allow, Allow for 10 Minutes, or Deny.
- **Safety** — unlocking always asks you on screen first, and is never accepted from the mesh. Home is local to each Mac: nothing from the mesh can post into it.
- **Mesh Scanner** now also shows every other Bluetooth device nearby (blue dots), with name and signal.

Version 0.5 adds many more devices and a much more detailed scanner.

- **TVs and media** — "TV volume 20", "louder", "mute the TV", "channel 7", "channel up", "HDMI 2", "open Netflix" (YouTube, Prime Video, Disney+, Apple TV, Spotify, Plex, Hulu), "pause", "play", "press home", "go back".
- **Around the house** — thermostats ("set the thermostat to 70", "heat to 68", "cool to 74", "thermostat auto"), fans ("fan high"), blinds ("close the blinds", "blinds 50%"), garage doors, valves, robot vacuums ("start the vacuum", "vacuum go home"), and questions ("what's the temperature", "is the front door locked", "status").
- **SmartThings** — every capability above, plus scenes (by full name) and live status.
- **Home Assistant** — "connect home assistant" (address + long-lived token). Brings in lights, switches, fans, covers and garage doors, locks, climate, media players and TVs, vacuums, valves, temperature sensors, scenes and scripts.
- **LIFX** and **Govee** — cloud keys ("connect lifx", "connect govee").
- **On your Wi-Fi, no account** — WLED, Elgato Key Light / Light Strip, Shelly (Gen2+ relays, dimmers, covers), Nanoleaf ("pair nanoleaf"), Roku (keys, apps, channels, inputs on Roku TVs) and WiZ bulbs are found and controlled directly.
- **Safety** — opening a garage door is treated like unlocking: always asked on screen, never from the mesh.
- **Mesh Scanner** — one table of everything around: Macs on the mesh; Bluetooth LE devices with maker, Apple device type, services, transmit power and whether they accept connections; classic Bluetooth devices paired with this Mac; and network devices from Bonjour (HomeKit, Matter, Google Cast, AirPlay, Sonos, printers, ESPHome, ...) and UPnP (routers, TVs, NAS). Pick a row for all its details. **Connect & Pair** reads a Bluetooth device's manufacturer, model, firmware and battery (macOS asks first if the device needs pairing) or connects a paired headset/keyboard. **Set Up** pairs a Hue Bridge or Nanoleaf, connects Home Assistant, opens the Home app for an unpaired HomeKit accessory or a Matter device in pairing mode, or opens a device's web page. **Bluetooth Settings...** is there for pairing new classic devices.
- **"list devices"** — everything connected, service by service, then room by room with each device's state ("Living Room: TV (on) · Lamp (on, 40%)"), then your Shortcuts and scenes. "list lights", "list tvs", "list locks", "list thermostats" narrow it. Works from any room. Rooms come from SmartThings (tick *Locations* on the token), Hue rooms and Home Assistant areas.
- **Where things are** — the scanner's radar is in metres (rings at 1, 3, 10 and 30 m), placing Bluetooth devices and Macs in range by distance estimated from their smoothed signal and advertised transmit power; the table's *Where* column says "≈3 m · in this room", and devices asmmesh controls are listed with the room they're in.

After each rebuild, macOS asks again for Bluetooth and for the saved SmartThings token (the ad-hoc signature changes every build): allow both, choosing Always Allow for the Keychain.

Version 0.6 adds automation, "where is it", and privacy. Say "help more" in Home for the list.

- **Schedules** — "at 7 pm turn off the TV", "in 20 minutes lights off", "every weekday at 7 am kitchen on", "turn on the porch light at sunset", "tomorrow at 9 am trigger coffee". A bare "at 7" asks whether you mean morning or evening.
- **Rules** — "when Anna arrives turn on the hall light" / "when Anna leaves …" (her Mac on the mesh, or a Bluetooth gadget that says that name — iPhones don't), "when the TV turns on dim the living room", "notify me when the front door opens" (SmartThings and Home Assistant doors and locks are checked every 20 s). "rules" lists them, "cancel rule 2". Repeating rules are kept between launches; everything runs only while asmmesh is open.
- **Reminders** — "remind me in 10 minutes to check the oven": shown, spoken, and pushed to your phone.
- **Weather** from Open-Meteo, no key: "weather", "weather tomorrow", "will it rain", "sunset", "air quality"; "my city is Portland" (until then, a guess from your internet address); "use celsius".
- **This Mac's room** — "this Mac is in the office": "lights on" typed here then means the office lights ("all lights on" still means everything), and "kitchen lights" picks lights by the room SmartThings/Hue/Home Assistant put them in.
- **Where is it** — "where are my headphones" answers from what this Mac hears (with distance), what other Macs on the mesh hear (they share it every 30 s, two hops at most), devices at home with that name, and Bluetooth devices paired with this Mac, and says which Mac is closest.
- **Tracker alerts** — AirTags / Find My items, Galaxy SmartTags and Tiles are recognised; one that isn't yours and stays within ~5 m for 10 minutes gets a warning. "trackers" lists them; "trust trackers" marks the ones heard now as yours.
- **Your phone and other services** — "notify topic <name>" then "notify …" (ntfy.sh, free app); "ifttt key <key>" then "trigger <event>" (IFTTT Webhooks, key in your Keychain); "say …" speaks on this Mac; "energy" reads power meters. Sonos speakers ("kitchen sonos pause", "sonos volume 30") and TP-Link Kasa plugs are found on your Wi-Fi.
- **Security (protocol v3)** — every Mac has its own P-256 identity key in the Keychain, and its mesh id is the hash of that key. Every packet is signed and time-stamped (replays older than 6 hours are refused), so names can't be faked; two people with the same name get a warning with both key fingerprints, and the People list shows each fingerprint. Private rooms have their own key, handed over inside the invite sealed for that one person, so only members can read them. Device commands are sealed for the one Mac they're for. With a mesh passphrase set, unencrypted messages are ignored. v3 can't talk to older versions.
- **Services, all off by default** — every integration has its own switch in Settings (⌘, or the Services button): Philips Hue, SmartThings (Lutron and friends), Apple Home, Wi-Fi lights & plugs, TVs & speakers, LIFX, Govee, Home Assistant, the SPIN remote, weather, mesh commands, automations, find my things, web requests and voice. A switched-off service is never started, never asks the Keychain, and its devices drop out of every list and command. Typed: “services”, “enable hue”, “disable smartthings”, “enable all”.
- **Look** — a dark skin after the Productive habit app: near-black window, rounded dark cards, amber and blue pills, SF Rounded type, and a Services window of coloured-icon rows with switches.
- **SPIN remote** — the Bluetooth rotary puck (Spin Remote SDC1) drives asmmesh as a physical controller. Wake it and it links on its own (macOS may ask to pair it once). Spin for brighter/dimmer (or louder/quieter with “spin controls the tv”), touch-scroll or swipe left/right to change rooms, swipe up/down for all lights on/off, press the centre to mute or turn the room off, double-tap to switch between lights and TV, and long-press the centre for 🆘 SOS. **Colour groups:** “spin group green kitchen lamp, desk lamp”, “spin group red porch, hallway” — then double-tap the SPIN (or swipe left/right) to step through the groups; the ring turns that group's colour, and spin (brighter/dimmer, or volume for a TV), press the top (on/off) and swipe up/down (on/off) act on just those devices. “spin groups” lists them, “spin group green clear” empties one. “spin color blue” picks the ring colour when you have no groups. “spin off” locks the remote (only SOS works), “spin on” unlocks. These commands work from any room. “spin” (or Mesh › SPIN Remote…) opens the **SPIN window**, set up like the remote's own app: profiles along the top, one per colour; each with a name, a switch and the devices it controls; and a row per gesture (19 of them) with what it does — Default, brighter/dimmer, on/off, louder/quieter, mute, play/pause, channel, next/previous profile, SOS, or “Run a command…” (anything you could type in Home). Rows light up as each gesture arrives; Test mode lets you try the remote without anything happening. Protocol reverse-engineered from the SPIN app (docs/spin_protocol.md).
- **Mesh passphrase** (Mesh › Mesh Passphrase…) — Macs that share one encrypt room messages, remote commands and what they hear (AES-256-CTR with an HMAC-SHA256 tag, key from PBKDF2); anyone else sees only that a locked message went by, and with a passphrase set, unencrypted remote commands are refused. Names in HELLOs stay readable so people still show up. It's a shared secret — tell it to people in person.

Version 0.7 carries the mesh over **FM radio**, and brings **web pages and headlines** to Macs with no internet.

- **FM radio** (Settings › FM radio, then Mesh › FM Radio…) — plug a small FM transmitter (a Retekess FT11 or similar) into the Mac's headphone jack. Every packet asmmesh sends or relays also goes out as audio tones (AFSK at 1200, 2400 or 4800 baud, HDLC frames with a CRC), so Macs miles apart can share one mesh. Packets are signed exactly as on Bluetooth; with a mesh passphrase their contents stay sealed on the air. Everything played on that Mac goes out on the air while FM is on, so keep other sounds off and the transmitter at its lowest power (unlicensed FM power limits differ by country).
- **Three ways to listen** — an **RTL-SDR stick** (`brew install librtlsdr`; asmmesh tunes it with rtl_fm), a **radio's headphone-out cabled into a line-in or USB sound adapter**, or simply the **microphone** next to an FM radio. Pick one under *Listen with*. The level meter shows what is being heard.
- **Two channel plans** — *shared*: everyone sends and listens on one frequency; a Mac waits while it hears someone else (it listens for real frames, so radio hiss doesn't hold it off) and skips a relay another Mac already put on the air. *Separate*: send on one frequency and listen on another, for two Macs talking both ways at once.
- **Airtime is saved** — others' HELLOs and "what I hear" packets stay on Bluetooth; your own HELLO goes on the air once a minute. *Send a test hello* checks the chain end to end.
- **Internet for the mesh** (Settings) — a Mac with internet becomes a **gateway**. It answers web requests from the mesh and posts headlines from an RSS feed every 15 minutes (default BBC World; type `feed <address>` in News to change it, `refresh` to fetch now).
- **The Web room** — type an address (`example.com`) or search words (`fm radio range`). A gateway fetches it, turns it into plain text with numbered links, compresses it and sends it back in small signed pieces; missing pieces are asked for again until the page is whole. Type a number to follow a link, `links` to list them, `back` for the previous page. A long address travels in several packets.
- **The News room** — headlines from any gateway, each shown once.
- **Gateway safety** — for requests from the mesh, a gateway only fetches http(s) addresses on the usual ports whose names resolve to public internet addresses: no localhost, `.local`, private, link-local or shared addresses, no user@host, and every redirect is checked the same way (curl is pinned to the checked address, is handed the address with `--url`, and speaks http(s) only). The gateway sees the addresses people ask for, just as any web proxy would; without a mesh passphrase, other Macs on the mesh can read them too.
- **Self-tests** now cover the modem round trip, the FM heard-counter, address checks, request and page reassembly (in any order), compression and HTML-to-text.

Offline messages were already there: every Mac keeps the last 32 messages and invites it carried and hands them to Macs that link up later, so someone out of range gets them when they come back (as long as some Mac that carried them is still around).

Without a passphrase, messages are plaintext: anyone running a modified copy could read any room. Version 0.3 speaks protocol v2 and ignores 0.2 packets, so update every Mac.

## 0.8 build 14: Bluetooth sensors, batteries, headphones

Switch on **Bluetooth Sensors** in Settings, then:

- **`sensors`** lists what broadcasts nearby: Govee, SwitchBot and Xiaomi (ATC/pvvx firmware) thermometers, and BTHome devices such as Shelly BLU buttons, door/window, motion and H&T sensors. No pairing; asmmesh only listens.
- **`name sensor 2 bedroom`** makes one a Home device: `bedroom temperature`, and rules like `when bedroom gets above 78 turn on the fan`, `when the bathroom humidity goes above 70% turn on the fan`, `when the front door opens turn on the hall light`, `when hallway detects motion …`, `when doorbell is pressed say someone's here` (also double-pressed, long-pressed, `button 2 on the remote`).
- **`batteries`** lists this Mac's battery, Magic keyboards/mice/trackpads, connected AirPods, AirPods nearby with the case open, and your named sensors. With ntfy or Pushover on, a low one (15% or less) is pushed once a day.
- **`headphones here`** asks your other Macs to let go of your AirPods and connects them here; **`send my headphones to Mac`** does the opposite. Only a fingerprint of the headphones' address goes over the mesh, and only a Mac paired with the same headphones acts on it.

Sensor readings can be faked by anyone with a radio nearby, so unlocking and opening a garage still ask on screen however they were triggered.

## asmmesh for iPhone (ios/)

The same assembly core (`src/*.s`) runs on iPhone. `ios/asm/ios_ui.s` takes the place of main.s, ui.s and scanner.s, and a thin SwiftUI front end (`ios/asmmesh/*.swift`) draws four tabs: **Rooms** (mesh chat, Home with the Talk mic), **People**, **Nearby** (radar, Bluetooth sensors, batteries, headphones) and **Settings** (Hue, SmartThings, Home Assistant, LIFX, Govee, the mesh passphrase and the service switches).

To install: plug in the iPhone or iPad, then run `cd ~/Developer/asmmesh/ios && bash "Install on iPhone.command"`. It signs with your free Apple ID, then installs and opens the app on every paired iPhone and iPad. The first time, turn on Settings > Privacy & Security > Developer Mode, and trust your certificate under Settings > General > VPN & Device Management. With a free Apple ID the app stops opening after 7 days; run the script again to renew it.

Not on iPhone (yet): the Web and News rooms, FM radio, the files page, AirDrop and the web gateway. iOS only scans for Bluetooth while the app is open, and Hue/Sonos discovery by SSDP needs an entitlement free accounts can't get (Bonjour discovery still works). After adding a source file, run `python3 ios/make_project.py`.

## Build and run

Needs the Xcode command line tools (`xcode-select --install`).

    make selftest   # mesh-logic tests, no Bluetooth needed
    make run        # builds asmmesh.app and opens it

To install it properly, double-click **Install asmmesh.command** (or run `make install`). It runs the self-tests, builds the app, copies it to /Applications, pins it to the Dock and launches it. asmmesh then lives in the menu bar too: the mesh icon shows how many Macs are linked, and its menu has the live status, Show asmmesh and Quit. Closing the window keeps it running so it can keep relaying for others; click the Dock icon or Show asmmesh to bring the window back.

The first launch asks for Bluetooth permission; allow it. If you said no by mistake, turn it back on in System Settings › Privacy & Security › Bluetooth.

## Trying the mesh

Copy this folder to a second Mac, run `make run` there too, and keep the two within Bluetooth range (a room is plenty). Within a few seconds each window says it linked with a nearby Mac. Type in either window and the message appears on the other, marked "hop 1". With a third Mac in the middle and the outer two out of range of each other, messages between the ends show "hop 2": they were relayed.

## Files

    src/main.s     entry point, window layout, menus, menu-bar item, the runtime-built controller class
    src/ui.s       room transcripts, Rooms/People lists, sending, New Room, invites, name picker
    src/scanner.s  Mesh Scanner window, the radar view's drawRect:, the heartbeat timer
    src/ble.s      CoreBluetooth: advertising, scanning, connecting, inbox, identity, signal strength
    src/mesh.s     identity, packets, duplicate filter, store-and-forward, relaying, nodes, rooms
    src/home.s     Home room: device registry, help, device list, remote commands
    src/parse.s    plain-English commands: actions, choosing devices, running them per backend
    src/net.s      HTTP (NSURLSession delegate), JSON accessors, Keychain
    src/hue.s      Hue Bridge (Bonjour, pairing, lights/rooms) and Hue Bluetooth bulbs
    src/st.s       SmartThings (all capabilities, scenes, status) and Apple Home via Shortcuts
    src/lan.s      Bonjour: WLED, Elgato, Shelly, Nanoleaf, Home Assistant discovery, scanner network rows
    src/cloud.s    LIFX, Govee and Home Assistant
    src/udp.s      SSDP/UPnP (Roku control, network listing) and WiZ bulbs
    src/near.s     nearby Bluetooth LE devices: advertisement decoding, Connect & Pair
    src/bt.s       classic Bluetooth devices paired with this Mac (IOBluetooth)
    src/rules.s    schedules and rules, the Home words that aren't device commands
    src/find.s     this Mac's room, "where is my …", sharing what Macs hear, tracker alerts
    src/extras.s   ntfy, IFTTT, speech, weather words, energy
    src/weather.s  Open-Meteo weather, sunrise/sunset, air quality, geocoding
    src/crypto.s   the mesh passphrase: key derivation, seal and open
    src/spin.s     the SPIN remote (rotary BLE puck) as an input device
    src/services.s the on/off switch for every integration, and the Settings window
    src/ident.s    identity keys, signatures, pairwise secrets and room keys (v3)
    src/spinui.s   the SPIN window: profiles and a gesture map, like the remote's app
    src/voice.s    push-to-talk speech recognition (hand-laid-out global blocks)
    src/fm.s       FM radio transport: transmit queue, listen-before-talk, sound inputs, the FM Radio window
    src/fm_dsp.s   AFSK modem: HDLC framing, bit stuffing, NRZI, CRC-16, correlator and DPLL demodulator
    src/fm_audio.s transmit ring buffer and AudioQueue output
    src/fm_io.s    child processes (rtl_fm, curl), receive stream
    src/fm_pack.s  zlib packing of pages
    src/fm_html.s  HTML to text with numbered links, RSS headlines, URL helpers
    src/fm_util.s  clocks, random numbers, small string helpers
    src/fm_defs.inc constants and frame macros for the FM files
    src/web.s      web pages and headlines over the mesh: Web and News rooms, the gateway
    src/sens_decode.s what Bluetooth sensors broadcast: BTHome v2, Govee, SwitchBot, Xiaomi ATC/pvvx, AirPods batteries
    src/sens_bthome.inc BTHome object sizes (generated from bthome-ble)
    src/sensors.s  Bluetooth sensors as Home devices, "sensors", "name sensor", "batteries", their self-tests
    src/handoff.s  "headphones here" / "send my headphones to …": AirPods between your Macs over the mesh
    src/cards.s    the Rooms and People lists drawn as cards (Mac), and the round icon buttons
    src/limits.s   flood limits: token buckets per sender, for unverified packets and for relaying
    src/guard.s    radio input runs guarded: a fault drops that packet, logged, and asmmesh keeps going
    src/listed.s   listed rooms: ROOMAD and JOINREQ, asking to join, letting people in
    src/scan_core.s the scanner's list, details and Connect & Pair / Set Up (Mac window and iPhone)
    src/files_mac.s Files on Wi-Fi's Mac side: folder chooser, AirDrop, the QR window
    src/bc_crypto.s bitchat's cryptography (not used yet): SHA-256/512, HMAC, HKDF, ChaCha20-Poly1305, X25519, Ed25519
    src/bc_link.s  bitchat's link layer, bytes only: packet lengths, long writes, fragments, send queues
    src/bc_ble.s   the Bluetooth link to bitchat phones (switch "bitchat", off by default), walled off; "bitchat" in Home
    src/bc_defs.inc sizes and layouts shared by the bitchat files
    src/test.s     `asmmesh --selftest`
    src/util.s     objc_msgSend shortcuts, NSString helpers, chat formatting
    src/macros.inc frame and messaging macros
    tools/qemu/    runs bc_crypto.s's self-tests under qemu on Linux, and checks it against Python's cryptography

## Packet format (v2)

    header  +0 'M'  +1 version 2  +2 hops left (starts at 7)  +3 type  +4 8-byte random packet id
    MSG     +12 room id  +20 sender id  +28 flags  +29 nick length n  +30 nick, then UTF-8 text
    HELLO   +12 node id  +20 messages relayed (u32)  +24 n  +25 nick
    INVITE  +12 room id  +20 from id  +28 target id  +36 n  +37 nick, then room-name length and name
    ROOMAD  +12 room id  +20 owner id  +28 n  +29 nick, then room-name length and name (type 12, after each HELLO)
    JOINREQ +12 room id  +20 asker id  +28 n  +29 nick, then the owner's id (type 13)
    CMD/RES +12 target id  +20 from id  +28 n  +29 nick, then UTF-8 command text or reply (types 4, 5)
    SEEN    +12 sender id  +20 flags  +21 n  +22 nick, then room, count, (rssi, name) per device (type 6, 2 hops)
    sealed  MSG flag 2 / CMD first byte 1 / SEEN flag 1: ciphertext then an 8-byte tag over id, ids and text
    NEWS    +12 zero  +20 gateway id  +28 n  +29 nick, then flags (1 sealed) and the headline (type 7)
    WEBREQ  +12 gateway id (0 = any)  +20 asker id  +28 n  +29 nick, then request id u32, flags (1 sealed,
            2 resend), then seq, total, offset u16 and a piece of the address — or, for a resend,
            the page's piece count u16 and a bitmap of the pieces still missing (type 8)
    WEBPART +12 asker id  +20 gateway id  +28 0  +29 request id u32  +33 piece u16  +35 pieces u16
            +37 flags (1 sealed)  +38 up to 120 bytes of the zlib-packed page (type 9)
    at most 240 bytes; Main is room id 0; Web (2), News (3) and bitchat (4), like Home (1), are local rooms
