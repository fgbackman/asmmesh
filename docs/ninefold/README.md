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
in the centre, 42 words in the ENABLE list.

## Rules

- A word is 4 to 9 letters, uses the centre letter, and uses each tile at most once.
- Words come from one fixed list built into the app (ENABLE, public domain). The same list on
  every device means everyone agrees on what counts.
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
  1. A 9-letter word with no other 9-letter anagram in the list.
  2. A centre letter that leaves between 25 and 80 words.
  3. The order of the other eight tiles.
- The generator is pure code with self-tests (like `term_core.s` and `bc_noise.s`): the same
  seed must give the same puzzle on every build.
- The list is about 173,000 words, roughly 1.7 MB as text. It can be packed much smaller
  (a trie, or only the words of 4 to 9 letters, about 110,000). Bundled in the app, never
  downloaded.

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
| `START`  | host         | seed, round, round length, start time (10 s ahead), the players' ids                     |
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
2. **Word list** packed into the app (Mac and iPhone), with its licence note.
3. **Mesh**: the game flag on room messages, the five packets, the reveal check, invitations
   through the existing invite flow.
4. **Mac UI**: the game room view (grid panel and transcript), and Home commands.
5. **iPhone UI**: the invitation sheet, the game screen and the results screen, as in the
   mockups.
6. Two Macs and two iPhones, one of them several hops away: a full game of 3 rounds.
