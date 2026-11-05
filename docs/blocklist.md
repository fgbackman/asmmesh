# The developer blocklist

Status: **built, the key not made yet.** The list's checking is pure code tested under qemu
(self-test 218, and lists made by the tool are checked by the app's own code). Until you make
your key, no list is taken and nothing changes for anyone.

A list of banned ids that every copy of asmmesh blocks, as if each person had blocked them
(their messages, invitations, game moves and asks to join aren't shown or taken). It's how
you act on a report for everyone, not only on the reporter's device. It is signed with a key
only you have: a list anyone else makes, or an older one of yours, is refused.

## Once

    pip3 install cryptography
    cd ~/Developer/asmmesh/tools/blocklist
    python3 blocklist.py keygen
    python3 blocklist.py url https://your-site.example/asmmesh/blocklist.bin

- `keygen` makes your key in `~/.asmmesh-blocklist/key` (readable by you only) and writes
  its public half into `src/dbl_key.inc`. **Back the key up** (a password manager, an
  encrypted USB stick). Lose it and you can't publish lists again without a new build of the
  app with a new key; leak it and someone else can sign lists. Never put it in the repository.
- `url` (optional) is where devices may fetch the list once a day (HTTPS; any static web
  host). Fetching is **off on every device** until its owner types `blocklist fetch on`: a
  fetch shows the web host the device's internet address, so it's their choice. Without it,
  lists travel over the mesh and with app updates.
- Commit `src/dbl_key.inc` and build: from then on the app takes your lists.

## For each report

A report email gives the person's id: "About: Anna (key 7KQ2-M9XD-4TRW, id 0123456789abcdef)".

    python3 blocklist.py add 0123456789abcdef "Nov 4: threats in Main, report from Bea"
    python3 blocklist.py sign

- `sign` makes the next version. To get it out:
  - run asmmesh (with the new `src/dbl_list.bin` built in) on one of your devices: it passes
    the list to its neighbours over Bluetooth, they pass it to theirs, and so on;
  - commit `src/dbl_list.bin`: the next build carries it;
  - if you set a URL, upload `~/.asmmesh-blocklist/blocklist.bin` there too.
- `remove <id>` and `sign` again to lift a ban; `list` shows the list with your notes (kept in
  `~/.asmmesh-blocklist/banned.txt`, never published: only the ids are); `show <file>` checks
  a list file.

## How devices treat it

- **Over the mesh, like a ledger's blocks:** once a minute each device tells its direct
  neighbours which version it has (a tiny packet, not passed on further). A neighbour with a
  newer list sends it in 128-byte pieces, two a second for 40 s, which repeats until they have
  it. Pieces come from one neighbour at a time; once whole, the list is taken only if your
  signature checks out and it's newer. Then that device passes it on in turn, so a list
  spreads hop by hop to devices that are never online. Any device can pass a list on; only
  your key can make one. Lists up to 8 KB (1,014 ids) go over the mesh; bigger ones only by
  update or the web.
- `blocklist` (Home) says which version a device has, how many ids, where it came from (this
  app, the web, the mesh) and whether fetching is on; `blocklist fetch on` / `off`.

- A list is taken only if its signature checks out with the key built into the app and its
  version is newer than the one held: an old list can't be sent again to lift bans.
- The newest good list is kept (the shipped one, or the one fetched, whichever is newer).
- Up to 4,096 ids. They're the ids asmmesh people sign their messages with, and the peer ids
  of bitchat people.
- A banned person who makes a new identity (deletes the app's Keychain item and starts again)
  has a new id: ban that one too when it's reported.

## What it doesn't do

- It doesn't delete what was already shown on anyone's device, and it can't reach devices
  that are never online until they update the app.
- It doesn't tell anyone they were banned.
