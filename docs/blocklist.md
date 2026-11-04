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
- `url` is where devices fetch the list once a day when they have internet (HTTPS). Any
  static web host works (GitHub Pages, a bucket). Leave it out and lists only arrive with app
  updates.
- Commit `src/dbl_key.inc` and build: from then on the app takes your lists.

## For each report

A report email gives the person's id: "About: Anna (key 7KQ2-M9XD-4TRW, id 0123456789abcdef)".

    python3 blocklist.py add 0123456789abcdef "Nov 4: threats in Main, report from Bea"
    python3 blocklist.py sign

- `sign` makes the next version: upload `~/.asmmesh-blocklist/blocklist.bin` to the URL
  (devices take it within a day), and commit `src/dbl_list.bin` (the next build carries it,
  for devices that are never online).
- `remove <id>` and `sign` again to lift a ban; `list` shows the list with your notes (kept in
  `~/.asmmesh-blocklist/banned.txt`, never published: only the ids are); `show <file>` checks
  a list file.

## How devices treat it

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
