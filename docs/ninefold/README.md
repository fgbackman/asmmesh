# Ninefold — a word game for asmmesh, played by invitation across the mesh

Status: **built, not yet tried on devices.** The rules, the puzzles and the screens' text
are pure code tested under qemu (self-tests 196-204, and `tools/qemu/run.sh nfdiff` against
the Python copy); the mesh, Mac and iPhone parts assemble, but haven't run on a Mac or
iPhone yet, and the Swift wasn't compiled here. The mockups are `mockups.html` (open with
`#invite`, `#play`, `#mac` or `#results`) and the PNGs next to it.

Nine letters in a 3×3 grid. Every word must use the centre letter, and one word uses all
nine. Ninefold is asmmesh's own game in that long-standing newspaper format. It is **not** a
copy of any one paper's puzzle: asmmesh makes its own puzzles on the device, from an open
word list, and nothing is scraped or republished.

| Screen        | File          | What it shows                                                        |
|---------------|---------------|----------------------------------------------------------------------|
| Invitation    | `invite.png`  | An iPhone gets asked to play: who, how far away, how private          |
| Playing       | `play.png`    | The grid, your words, the others' progress (counts only), the clock  |
| On the Mac    | `mac.png`     | The same game as a room in asmmesh's window, next to its chat         |
| Results       | `results.png` | The nine-letter word, the ranking, every word revealed and checked   |

The puzzle in the mockups is real, made the way the game will make them: "moonlight" with G
in the centre, 19 answers and 7 rarer words also accepted.

## Rules

- A word is 4 to 9 letters, uses the centre letter, and uses each tile at most once.
- Words come from two fixed lists built into the app, the same on every device, so everyone
  agrees on what counts. No single source decides (see "Which words count" below):
  - **answers**: the words a round counts, reveals and says you missed;
  - **also accepted**: real but rarer words. They score, but nobody is shown them as missed.
- A round lasts 4 minutes (the host can choose 2, 4 or 8). A game is 1 to 5 rounds.
- Points:

  | Word                         | Points             |
  |------------------------------|--------------------|
  | 4 letters                    | 1                  |
  | each letter after the fourth | +1 (7 letters: 4)  |
  | the nine-letter word         | 10                 |
  | found it first               | +1                 |
  | nobody else found it         | +2 (at the reveal) |

- During a round, you see how many words each player has, never which ones. Your own score
  shows; the others' scores show as "?" until the reveal.

## Puzzles: made on the device, the same everywhere

- The host picks a random 64-bit **seed**. The puzzle comes from the seed alone, so only the
  seed travels, and every Mac and iPhone builds the same grid.
- From the seed (splitmix64; `src/nf_core.s`, Python copy `tools/ninefold/nf.py`):
  1. A 9-letter answer with no other 9-letter anagram among the answers.
  2. A centre letter that leaves between 15 and 60 answers (family-filter words never
     count here, so the setting can't change the puzzle). A puzzle with more than 250 words
     in all is skipped, so a word's index fits in one byte.
  3. The order of the other eight tiles.
- The generator is pure code with self-tests (like `term_core.s` and `bc_noise.s`): the same
  seed must give the same puzzle on every build.
- Puzzles are made from the answers only. A centre letter must leave 15 to 60 answers.

## Which words count

Accuracy decides what is a word; taste is a separate, visible layer (the family filter).
The rules are in `tools/ninefold/make_words.py`, the sources and licences in
`tools/ninefold/SOURCES.md`.

| Test                        | Source                                      | Rules out                                      |
|-----------------------------|---------------------------------------------|------------------------------------------------|
| a valid word                | ENABLE2K (public domain)                    | names, abbreviations, misspellings             |
| an ordinary word            | SCOWL sizes 10-60 (spell-checker lists)     | archaic, technical, dialect words (TOLA, AIRT) |
| not a plural or -s form     | WordNet 3.0's grammar                       | OATS, CARS, YEARS, PARENTS, RUNS; PANTS too    |
| not a contraction           | SCOWL's contraction lists, wordfreq         | SHES, CANT, WONT                               |
| an answer: common, British  | wordfreq Zipf 2.75 or more; SCOWL British   | rarer words and COLOR: those are "also accepted" |
| an answer: not a name       | SCOWL's name lists                          | ANNA, LOGAN as answers (ORCA, BRIE still count) |

- **No plurals**, and no verb -s forms (they're spelled the same). Words that only look
  plural stay: NEWS, SERIES, LENS, BONUS, ALWAYS, ALAS, PHYSICS, POLITICS, OURS.
  Edge cases left for review: PECS, UNDIES, AFTERS (plural-only nouns, like PANTS, which
  goes), TIGHTS and ARREARS.
- Result: 16,272 answers and 9,543 "also accepted" words, of 4 to 9 letters.
- **Family filter** (a game setting, on by default, the same on every device): judged by
  a dictionary's own labels. Candidates come from LDNOOBW's list and `family-extra.txt`;
  each one's Wiktionary page is read (`fetch_wiktionary.py`, `judge_family.py`), and it is
  hidden only if Wiktionary labels its first meaning, or half or more of its meanings,
  vulgar, offensive, derogatory or a slur. 37 words are hidden (the slurs, CUNT, FUCK,
  SHIT, PISS, WHORE, CRAP, TURD...); 61 candidates show (BUTT, ESCORT, SNATCH, SKEET, SCAT,
  FINGERING, the anatomy words). Every decision and its count is in
  `words/family-judged.tsv`. With the filter off, all of them count.
  Not hidden, because Wiktionary doesn't label them vulgar: serious words (RAPE, INCEST)
  and plain sexual vocabulary (PORN, ORGASM). If a family game should leave those out too,
  that's a second, stricter setting: a taste decision, to be made as one.
- **Measured against people's choices**: `benchmark.py` runs the lists on 595 puzzles whose
  answers were chosen by hand. 97.0% of our answers are words those editors listed; of
  their words, we accept 85.7% once plurals and contractions (excluded by rule) are set
  aside. Most of the rest are rarer words below our cut-offs (THROE, EWER, TIRO).
- **200 sample puzzles** with every word: `samples-200.md`, checked by
  `tools/ninefold/check_samples.py` (separate code): 7,957 words, 0 problems. It catches
  planted mistakes (a word without the centre letter, a tile used twice, a missing word).
- The mockups' puzzle has 19 answers and 7 also accepted (one of those hidden by the filter).
- A game's `START` carries a hash of the lists: devices with different lists won't play
  together, so a mismatch can't decide a word.

## Across the mesh, by invitation only

A game is an **invite-only room**, made and joined exactly like asmmesh's private rooms
today. That gives three things already built and tested:

- **Only those invited can play.** The room has its own key, handed to each invitee sealed
  for them alone (`T_INVITE`). Anyone else on the mesh relays the packets but can't read them.
- **Every packet is signed** by its sender (the ident trailer), so nobody can claim words or
  scores in someone else's name.
- **Multi-hop and store-and-forward.** Players can be several hops apart (Sam, 3 hops away,
  in `mac.png`), and a packet waits in the store when a phone briefly drops out.

Game packets are room messages with a game flag. They inherit the room's sealing, signing,
relaying and duplicate filter, and stay within the 240-byte packet limit:

| Packet   | Sent by      | Carries                                                                                  |
|----------|--------------|------------------------------------------------------------------------------------------|
| `START`  | host         | game id, round, rounds, round length, seed, start time (10 s ahead), the word lists' hash, family filter (31 bytes) |
| `CLAIM`  | finder       | word length, the time found, a 16-byte commitment (28 bytes)                             |
| `REVEAL` | each player  | after the round: their salt and their words (one byte each: an index into the puzzle's word list), 80 a packet |

- There is no READY or END: everyone starts and stops on their own clock, from the start
  time in `START`. The host sends `START` again every 15 seconds while a round is waiting or
  on, so a slow hop or a late joiner catches up (a late joiner starts where the round has
  got to). Only a game's host can start its later rounds.
- Claims are taken until 5 seconds after the round; their times are kept within the round.
  Reveals are scored 12 seconds after it. The host's next round starts 15 seconds after that.

### Words stay hidden until the end: commit, then reveal

A puzzle has only a few dozen words, so a plain hash would be easy to undo by trying them
all. Each player therefore makes a secret random **salt** for each round:

- When you find a word, `CLAIM` carries `SHA-256(salt ‖ your id ‖ round ‖ word index)`,
  first 16 bytes. Your id is in it so nobody can copy your claims and, after seeing your salt
  at the reveal, pass them off as theirs (self-test 203 tries exactly that). Others learn the length and that you found something, nothing more.
- At the end, `REVEAL` gives your word indexes and the salt. Every device recomputes each
  commitment. A word whose commitment wasn't sent during the round, or doesn't match, scores
  nothing. So you can't add words after seeing everyone else's.
- **First finder**: the earliest signed time on a matching claim. Clocks differ, so claims
  within 2 s of the earliest share the bonus. Only signed claims and reveals count, so every
  device works out the same scores (self-test 203 checks two devices agree).

### Limits

- 100 claims a player a round, 768 in all, 12 players a game.
- Names and chat are cleaned like everywhere else in asmmesh.
- A game room is local to its players: not listed, and gone when the game ends (its
  transcript can be kept).

## In the app

- **Mac**:
  - **Mesh › Play Ninefold…** (⌘9) asks who to invite. Or in Home: `ninefold with Anna, Sam` (options `3 rounds`, `2 minutes`, `family off`) makes the
    game room and invites them; `ninefold` alone makes it empty (invite from the room).
  - Inside the game room: `start` (the host), then type words and press Enter. `shuffle`
    shows the tiles in a new order, `words` lists yours. The room's header shows the clock
    and everyone's word counts; the grid, each answer and the results are transcript lines.
  - A typed line that is one word of letters, during a round, is always a guess and never
    chat; anything else is chat as usual.
- **iPhone**:
  - The invitation says it's a game: **Join Game** or **Not now**.
  - The ▦ button on the Rooms list starts a game (people, rounds, minutes, family filter).
  - The game room shows the board above the chat: the status, tiles to tap, Shuffle,
    Delete, Clear, your words, the others' counts; after a round, the results and
    **Next Round Now** (host) or **Play Again** (after the last round). A card on the Rooms
    list leads back to the game.
- **Not over bitchat.** bitchat stays walled off.
- One game at a time on a device.

## What was done, and what's left

1. Generator and rules (pure, qemu self-tests 196-204), cross-checked against `nf.py`. Done.
2. Word lists packed into the app (`src/nf_words.bin`, 25,815 words). Done; the credits from
   `tools/ninefold/SOURCES.md` still need adding to the app's About text.
3. Mesh: the game flag on room messages, the packets, the reveal check, invitations through
   the existing invite flow. Done.
4. Mac UI: header and transcript, Home command. Done.
5. iPhone UI: invitation wording, game board, start sheet, results. Done, not compiled here.
6. Two Macs and two iPhones, one of them several hops away: a full game of 3 rounds. To do.
