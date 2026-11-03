# Ninefold — a word game for asmmesh, played by invitation across the mesh

Status: **prototype (images only)**. Nothing in the app yet. The mockups are `mockups.html`
(open with `#invite`, `#play`, `#mac` or `#results`) and the PNGs next to it.

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
in the centre, 21 answers and 4 rarer words also accepted.

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
- From the seed:
  1. A 9-letter answer with no other 9-letter anagram among the answers.
  2. A centre letter that leaves between 15 and 60 answers.
  3. The order of the other eight tiles.
- The generator is pure code with self-tests (like `term_core.s` and `bc_noise.s`): the same
  seed must give the same puzzle on every build.
- Puzzles are made from the answers only. A centre letter must leave 15 to 60 answers.

## Which words count

A plain Scrabble list (ENABLE) is full of words nobody uses (TIGLON, LOGION, THOLING), and
a game that counts them can't be trusted. Now three independent sources must agree
(`tools/ninefold/make_words.py`, sources and licences in `tools/ninefold/SOURCES.md`):

| Test                      | Source                                   | Rules out                                  |
|---------------------------|------------------------------------------|--------------------------------------------|
| a valid word              | ENABLE2K (public domain)                 | names, abbreviations, misspellings         |
| an ordinary word          | SCOWL sizes 10-50 (a spell checker's list) | archaic, technical and dialect words     |
| a word people use         | wordfreq: Zipf 2.5 or more               | rare words (2.0 to 2.5: "also accepted")   |

- Result: about 24,800 answers and 6,800 "also accepted" words, of 4 to 9 letters.
- The mockups' puzzle has 21 answers and 4 "also accepted" words. Its full list is MOONLIGHT,
  LOOMING, LOOTING, TOOLING, HOMING, GLINT, GLOOM, IGLOO, LIGHT, LINGO, MIGHT, NIGHT, THING,
  THONG, GILT, GOON, LOGO, LONG, NIGH, TING, TONG, plus HOOTING, INGOT, MOLTING, HOLING.
- Every word left out is in `REPORT.txt` with its reason, so anyone can check a decision.
  Rebuilding gives the same lists unless a source changes (versions pinned).
- A game's `START` carries a hash of the lists: devices with different lists won't play
  together, so a mismatch can't decide a word.
- Still to do: `blocked.txt` (slurs and the like) is empty and must be filled from a
  reviewed list before the game ships.

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
| `START`  | host         | seed, round, round length, start time (10 s ahead), the players' ids, the word lists' hash |
| `READY`  | each player  | "I have built the puzzle"; the round starts when all are ready, or after 30 s            |
| `CLAIM`  | finder       | word length, a 16-byte commitment, the time found                                        |
| `REVEAL` | each player  | after the round: their words (one byte each: an index into the puzzle's word list), their salt |
| `END`    | host         | round over (everyone also stops on their own clock)                                      |

### Words stay hidden until the end: commit, then reveal

A puzzle has only a few dozen words, so a plain hash would be easy to undo by trying them
all. Each player therefore makes a secret random **salt** for each round:

- When you find a word, `CLAIM` carries `SHA-256(salt ‖ round ‖ word index)`, first 16
  bytes. Others learn the length and that you found something, nothing more.
- At the end, `REVEAL` gives your word indexes and the salt. Every device recomputes each
  commitment. A word whose commitment wasn't sent during the round, or doesn't match, scores
  nothing. So you can't add words after seeing everyone else's.
- **First finder**: the earliest signed time on a matching claim. Clocks differ, so claims
  within 2 s of each other share the bonus.

### Limits

- 4 claims a second per player, 12 players a game.
- Names and chat are cleaned like everywhere else in asmmesh.
- A game room is local to its players: not listed, and gone when the game ends (its
  transcript can be kept).

## In the app

- **Mac**:
  - Home: `ninefold with Anna Sam` starts a game and invites them.
  - Inside the game room: the grid sits next to the room's chat. You type a word in the
    input line and press Enter; Tab shuffles and Esc clears, as the terminal-style line
    already does.
  - Each word gets a line in the transcript ("you: TOOLING ✓ (first, +1)").
- **iPhone**:
  - The invitation comes as a sheet with **Join game** and **Not now**.
  - The game screen is the grid with letter tiles, the players' counts, the clock and your
    words.
  - A hardware keyboard works too.
- **Not over bitchat.** bitchat stays walled off.

## Plan

1. **Generator** (pure, qemu self-tests): seed to puzzle, word check, scoring, commitments.
   Cross-checked against a Python copy, as the bitchat code was.
2. **Word lists** (`tools/ninefold`) packed into the app (Mac and iPhone), with the credits
   from `SOURCES.md`, and `blocked.txt` filled.
3. **Mesh**: the game flag on room messages, the five packets, the reveal check, invitations
   through the existing invite flow.
4. **Mac UI**: the game room view (grid panel and transcript), and Home commands.
5. **iPhone UI**: the invitation sheet, the game screen and the results screen, as in the
   mockups.
6. Two Macs and two iPhones, one of them several hops away: a full game of 3 rounds.
