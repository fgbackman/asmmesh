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
  - **More than one bridge** (up to four): each is found and paired the same way ("pair hue" asks every bridge not paired yet). "hue bridges" lists them, numbered; "forget hue bridge 2" removes one with its lights. A bridge seen at a new address is recognised by its bridge id, not added twice.
  - **The old round v1 bridge** works too: it has no Bonjour and lost Philips' cloud in 2020, so asmmesh finds it by SSDP on the Wi-Fi. If it isn't found (or on iPhone, where SSDP needs an entitlement), type its address: "hue bridge 192.168.1.20".
  - **Add a bulb by its serial** — the 6 letters and digits printed on the bulb or its label, as in the Hue app's "Add by serial number": "add hue light 1A2B3C" (up to 10, spaces between). Useful for a bulb paired to another bridge or reset. "add hue lights" searches for any new light. About a minute later asmmesh says what the bridge found and adds it to the lists. With several bridges, add the number: "add hue light 1A2B3C on 2". On the Mac: Mesh › Add Hue Lights…; on iPhone: Settings › Philips Hue (bridges, Pair, add by address, add by serial, search).
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
- **Mesh Scanner** — one table of everything around: Macs on the mesh; Bluetooth LE devices with maker, Apple device type, services, transmit power and whether they accept connections; classic Bluetooth devices paired with this Mac; and network devices from Bonjour (HomeKit, Matter, Google Cast, AirPlay, Sonos, printers, ESPHome, ...) and UPnP (routers, TVs, NAS). A **Via** column says how each is reached (Bluetooth, Bluetooth (paired), Wi-Fi, Internet), and **All / Bluetooth / Wi-Fi & internet** under the list shows just one kind; on iPhone, Nearby groups them the same way with the same picker. Pick a row for all its details. **Connect & Pair** reads a Bluetooth device's manufacturer, model, firmware and battery (macOS asks first if the device needs pairing) or connects a paired headset/keyboard. **Set Up** pairs a Hue Bridge or Nanoleaf, connects Home Assistant, opens the Home app for an unpaired HomeKit accessory or a Matter device in pairing mode, or opens a device's web page. **Bluetooth Settings...** is there for pairing new classic devices.
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
- **SPIN remote** — the Bluetooth rotary puck (Spin Remote SDC1) drives asmmesh as a physical controller. Wake it and it links on its own (macOS may ask to pair it once). Spin for brighter/dimmer (or louder/quieter with “spin controls the tv”), touch-scroll or swipe left/right to change rooms, swipe up/down for all lights on/off, press the centre to mute or turn the room off, double-tap to switch between lights and TV, and long-press the centre for 🆘 SOS. **Colour groups:** “spin group green kitchen lamp, desk lamp”, “spin group red porch, hallway” — then double-tap the SPIN (or swipe left/right) to step through the groups; the ring turns that group's colour, and spin (brighter/dimmer, or volume for a TV), press the top (on/off) and swipe up/down (on/off) act on just those devices. “spin groups” lists them, “spin group green clear” empties one. “spin color blue” picks the ring colour when you have no groups. “spin off” locks the remote (only SOS works), “spin on” unlocks. These commands work from any room. “spin” (or Mesh › SPIN Remote…) opens the **SPIN window**, set up like the remote's own app: profiles along the top, one per colour; each with a name, a switch and the devices it controls; and a row per gesture (19 of them) with what it does — Default, brighter/dimmer, on/off, louder/quieter, mute, play/pause, channel, next/previous profile, SOS, or “Run a command…” (anything you could type in Home). Rows light up as each gesture arrives; Test mode lets you try the remote without anything happening. It follows SPIN remote B.V.'s published, MIT-licensed developer spec (docs/spin_protocol.md, CREDITS.md).
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

## bitchat (Settings › bitchat, off by default)

asmmesh can also talk to phones running [bitchat](https://github.com/permissionlesstech/bitchat), Jack Dorsey's Bluetooth mesh chat, walled off from asmmesh's own mesh: bitchat people and their chat show up here, but nothing from bitchat reaches your rooms, devices, rules or keys, and nothing of asmmesh goes to bitchat.

- **Switch it on** in Settings, or `enable bitchat` in Home. This Mac gets bitchat keys of its own (Keychain item `asmmesh.bitchat`), never linked to its asmmesh identity, and a separate name: "anon" and four digits until you set one with `bitchat name …`.
- **People** lists bitchat people in orange after asmmesh's, with a fingerprint, and "nearby" when a phone is linked straight to this Mac. They can't be invited, found or sent commands. A name that looks like an asmmesh person's gets a warning.
- **The bitchat room** (there while bitchat is on) shows bitchat's public chat as "Name (1a2b): text", the start of each sender's fingerprint after the name. What you type there goes to bitchat as signed public messages, in pieces of up to 96 bytes; it's only ever chat, never a command.
- **In Home:** `bitchat` (status), `bitchat people`, `bitchat name …`, `bitchat forget` (deletes this Mac's bitchat keys and everything heard), `bitchat advertise on/off` (let phones find this Mac too). None of these work from the mesh.
- With two or more phones linked, this Mac passes bitchat packets on for them, as a bitchat phone would.

- **Private chats** (new, not yet tried with a phone): `bitchat chat Anna` or `bitchat chat 1a2b` (the start of their fingerprint), or **Message** next to them in People on iPhone, opens a room of its own, 🔒 and their name. It's end-to-end encrypted with Noise exactly as bitchat does it (`Noise_XX_25519_ChaChaPoly_SHA256`): only that person can read it, and only after their phone proves the key their fingerprint stands for. A message waits until a session is set up, is sent again until their phone says it arrived, and "✓ delivered" shows when it did; up to 88 bytes per message, longer text goes in pieces. Up to 8 chats; they're local rooms, never saved or sent on asmmesh's mesh, and go when bitchat is switched off.

How it works, how it was tested and what's next: `docs/bitchat_roadmap.md` and `docs/bitchat_handoff.md`.

## Ninefold: a word game across the mesh, by invitation

Nine letters in a 3×3 grid; make words of 4 to 9 letters that use the centre letter, each tile once. One word uses all nine. Everyone plays the same puzzle at the same time, and nobody sees anyone else's words until the round ends.

- **Start a game** with the ▦ button next to + above Rooms, **Mesh › Play Ninefold…** (⌘9), or in Home: `ninefold with Anna, Sam` (names as People shows them, commas between). Add `3 rounds` (1-5), `2 minutes` (1-9) or `family off` as you like; the defaults are 3 rounds of 4 minutes with the family filter on. On iPhone: the ▦ button on the Rooms list.
- That makes an invite-only room, "Ninefold" and your name, invites them, and the game comes up in its own window (iPhone: full screen); the invitation pops up in front of everything, and joining brings the game up for them too. When they've joined, press **Start** (or type `start` in the room). Each round starts 10 seconds later on everyone's own clock; the next one follows 15 seconds after the results.
- **During a round**, any single word you type in the game room is a guess, never sent as chat: ✓ and its points, or why not. Only its length and a sealed commitment go out. `shuffle` moves the tiles, `words` lists yours. The game window (Mac) and screen (iPhone) show the tiles (click or tap them to type), the clock, your words and the others' counts, and come to the front for every round; clicking the game room brings the window back.
- **At the end** everyone's words are revealed and checked against what they claimed during the round, on every device, so all agree on the score: 1 point for 4 letters, one more per extra letter, 10 for the nine-letter word, +1 for finding it first (within 2 s), +2 if nobody else did. Then the answers nobody found.
- The puzzles come from built-in word lists (`tools/ninefold`), the same on every device; a different build won't play with yours. How it works: `docs/ninefold/README.md`.

## Chess, across the mesh or with a bitchat person

- **With someone on asmmesh:** the chess button next to ▦ above Rooms, **Mesh › Play Chess…** (⌘8), or in Home `chess with Anna` (add `black` to play black). That makes an invite-only room, "Chess" and your name, and invites them; the invitation pops up and says it's chess. On iPhone: the chessboard button on Rooms.
- **With someone on bitchat:** in your private bitchat chat with them, type `chess` (or `chess black`). bitchat has no chess of its own, so moves go as text: they see "♟ 12. Nf3 · your move" and reply by typing a move (`e5`, `Nf6`, `O-O`, or `resign`, `draw`). Another asmmesh on the other end reads those lines too, so two asmmesh users can play over bitchat.
- **The board** pops up in its own window (Mac) or full screen (iPhone) when a game starts and with every move: click or tap a piece of yours, its moves light up, click one to play it. Or type moves in the game's room or chat: `e4`, `Nf3`, `exd5`, `O-O`, `e7e8q`, `e2e4`; `resign`, `draw` (offer, or accept theirs), `board`, `moves`. Only a line that is a single word counts as a move; anything else is chat.
- **Secure and walled off:** every move, whoever sends it, is checked against the rules on both devices (illegal, out-of-turn and other people's moves are refused; catching up after a lost move only ever fills in the other player's moves). Game packets are sealed with the room's key. Over bitchat only text crosses the wall: the game never touches asmmesh's rooms, devices, rules or keys, and nothing from bitchat runs as a command. The rules engine is pure code, checked by perft (the count of every position a few moves deep, from standard test positions, against the published numbers: 4,865,609 at depth 5 from the start).
- The game ends by checkmate, resignation, an agreed draw, stalemate, the fifty-move rule, threefold repetition, or when neither side can mate. One game at a time.

## Fivefold: a five-letter word in six tries

- **Today's word:** the amber Fivefold button left of chess above Rooms, **Mesh › Play Fivefold…** (⌘5), or `fivefold` in Home. On iPhone: the grid button on Rooms. The same word for everyone that day; type a guess and press Enter (or the on-screen keys). **Amber** is the right letter in the right place, **blue** is in the word somewhere else, **dark** isn't in it; the keyboard shows what you know of each letter. Your board is kept, so reopening the app doesn't give a fresh start. `fivefold share` (or Share) puts your squares in Main, never the word.
- **A race:** `fivefold race with Anna, Sam` (or Race… in the window). An invite-only room, "Fivefold" and your name; everyone gets the same word (from a seed the host sends), and each sees the others' colours as they go, never their letters.
- **A duel:** `fivefold duel with Anna` (or Duel…). Each of you types a five-letter word for the other; it's sealed (SHA-256 with a salt and your id) and can't be changed. Their device answers your guesses with colours and yours answers theirs; at the end both words are revealed and every answer is checked, so a lying answer is caught. Fewer guesses wins.
- In a race's or duel's room, a single five-letter word is a guess; anything else is chat. Packets are sealed with the room's key. The words: 2,016 that can be the answer, 3,005 that count as guesses, from the same lists as Ninefold. How it works: `docs/fivefold/README.md`.

## Block, report, and the chat filter

- **Block** someone: Mesh › Block Person (with them picked in People) on the Mac, their ⋯ in People on iPhone, or `block Anna` in Home; in a private bitchat chat, type `block`. Their messages, invitations, game moves and asks to join aren't shown or taken any more (their packets are still passed on for others: that's the mesh). `unblock Anna`, `unblock all`, `blocked` lists them. Kept between launches.
- **Report** someone: Mesh › Report Person…, ⋯ › Report… on iPhone, `report Anna`, or `report` in a private bitchat chat. Your mail app opens a report (their name, key fingerprint and what they sent here lately) addressed to the report address, and they're blocked. Set the address with `report address you@example.com` or Settings › Privacy on iPhone.
- **The developer blocklist:** ids you ban for everyone, signed with your key, shipped in the app and passed from device to device over the mesh (fetching from a web address is optional, off unless `blocklist fetch on`): `docs/blocklist.md`, `tools/blocklist/blocklist.py`. Reports carry the person's id for it. `blocklist` shows what a device has.
- **The chat filter** (on unless `filter off`; Settings › Privacy on iPhone): vulgar words and slurs in what others send show as `f***`. Only words Wiktionary itself labels vulgar, offensive or a slur (the same 37 as Ninefold's family filter), whole words with -s or -es: Scunthorpe, assess and Dickens are untouched, and so are Dick and Mongol written as names.

## Your shortcuts, and devices remembered

- **A shortcut** gives a few Home commands one name: `shortcut movie: dim living room to 20%; tv on` (split them with `;` or "then"). Say `movie` in Home to run them in order, or click **⚡ Shortcuts** in the Mac's sidebar (above Scanner and Services) or the **Shortcuts** menu (New Shortcut… makes one in either), or tap it under **Your shortcuts** on the iPhone's Nearby tab (+ makes one; hold one to delete it). `shortcuts` lists them, `delete shortcut movie` removes one. Up to 24, kept between launches like your rooms. Each command runs as if you typed it, so an unlock still asks; a shortcut can't run another one, and shortcuts are only made on the device itself, never from the mesh.
- **Devices remembered:** the lights, scenes and devices your services find are saved (every 30 s, when the list changes) and listed straight away at the next launch, before the hubs answer; each service updates its own as it comes in. Their on/off and level show as unknown until then. Bluetooth bulbs and sensors aren't kept (they need the radio). `forget devices` clears the saved list.

## Typing: history and suggestions

On the Mac the input line works like a terminal's: monospaced, with a ❯ prompt.

- **↑ and ↓** bring back what you typed, up to the last 100 lines; past the newest, ↓ gives back what you were in the middle of typing.
- **In Home**, commands that match what you're typing appear above the line, those that start with it first. **Tab** fills in the chosen one, ↑ ↓ choose, **Esc** hides them; Enter sends what's typed.
- **Remembered between launches** with `history on` (the default); `history off` keeps it only until asmmesh quits and deletes what was saved; `history clear` forgets everything; `history` says which. Lines typed in private rooms or the bitchat room, and anything with a token, key, topic, password, Pushover setting or web address in it, are never saved.
- **On iPhone** the 🕘 button by the input lists what you typed (newest first, tap to fill it in); in Home, matching commands show as chips above it (tap to fill in). A hardware keyboard's ↑ ↓ and Tab work as on the Mac. The `history` commands are the same.

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
    src/hue.s      Hue Bridge (Bonjour, SSDP for v1, pairing, lights/rooms, adding by serial) and Hue Bluetooth bulbs
    src/nf_core.s  Ninefold's rules, pure: the word table (nf_words.bin), seed to puzzle, words typed, points, commitments
    src/nf_play.s  a Ninefold game, pure: rounds, claims, reveals checked against claims, scores
    src/nf_text.s  Ninefold's words on screen, pure: status line, grid, answers to words typed, results
    src/nf_mesh.s  Ninefold on the mesh: packets, the clock, Home's "ninefold", what the iPhone's game screen reads
    src/ch_core.s  chess's rules, pure: legal moves, check and mate, SAN read and written, perft
    src/ch_play.s  a chess game, pure: turns, packets, catching up, how it ends, the board and moves as text
    src/ch_mesh.s  chess on the mesh and over bitchat text; Home's "chess", what the boards read
    src/ch_win.s   the Mac's chess window (src/nf_win.s: Ninefold's)
    src/ff_core.s  Fivefold's rules, pure: the words (ff_words.bin), colours, today's word, a race's word, sealing
    src/ff_play.s  a Fivefold game, pure: today's word, a race, a duel; packets, checks, the squares and status
    src/ff_mesh.s  Fivefold on the mesh: Home's "fivefold", packets sent until taken, what the screens read
    src/ff_win.s   the Mac's Fivefold window
    src/quick.s    your shortcuts (saved Home commands) and the devices kept between launches
    src/cf_core.s  the chat filter, pure (its words: cf_words.inc, made by tools/ninefold/make_chat_filter.py)
    src/safety.s   block, report, the filter's setting, the developer blocklist's loading and fetching, Home's words
    src/dbl_core.s the developer blocklist, pure: a signed list checked, an id looked up
    src/hue_core.s Hue's bytes-only parts: serials typed, bridge addresses, telling a bridge's SSDP answer
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
    src/bc_crypto.s bitchat's cryptography: SHA-256/512, HMAC, HKDF, ChaCha20-Poly1305, X25519, Ed25519
    src/bc_link.s  bitchat's link layer, bytes only: packet lengths, long writes, fragments, send queues
    src/bc_packet.s bitchat packets: reading, what a signature covers, signing ours, duplicates, relaying
    src/bc_zlib.s  bitchat's compressed payloads, through libz
    src/bc_peer.s  bitchat people and chat: announces, leaves, messages, pinned keys, cleaning names and text
    src/bc_noise.s bitchat's private chats: Noise XX, the transport and its replay window, the message payload
    src/bc_ble.s   the Bluetooth link to bitchat phones (switch "bitchat", off by default), walled off; keys,
                   announcing, the bitchat room, private chats (sessions, outbox, rooms), "bitchat …" in Home
    src/bc_defs.inc sizes and layouts shared by the bitchat files
    src/term_core.s the input line's history and command matching (bytes only)
    src/term_hist.s the history's keeping rules, Home's word list, the history commands (Mac and iPhone)
    src/term.s     the input line as a terminal: prompt, up/down history, suggestions in Home (Mac)
    src/test.s     `asmmesh --selftest`
    src/util.s     objc_msgSend shortcuts, NSString helpers, chat formatting
    src/macros.inc frame and messaging macros
    tools/bitchat/ watch.py: has bitchat changed its protocol since the commit asmmesh follows?
                   (`make bitchat-check`; baseline.json names that commit and the files)
    tools/qemu/    runs the bitchat and typing self-tests under qemu on Linux (run.sh), checks them against
                   Python's cryptography and a Python copy of bitchat's rules (run.sh diff), and lints (lint.py)

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
