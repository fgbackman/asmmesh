# Fivefold

A five-letter word in six tries. After each guess every letter is coloured: **amber** (right
letter, right place), **blue** (in the word, somewhere else) or **dark** (not in it). A
repeated letter is only coloured as often as the word has it.

## Three ways to play

| Mode         | Home                              | The word                                  | What others see            |
|--------------|-----------------------------------|-------------------------------------------|----------------------------|
| Today        | `fivefold`                        | the day's: the same for everyone (UTC)     | your squares, if you share |
| Race         | `fivefold race with Anna, Sam`    | from a seed the host sends                 | your colours as you go     |
| Duel         | `fivefold duel with Anna`         | each picks the other's, sealed             | colours, then both words   |

`fivefold share` sends the squares of the last finished board to Main (rows by spaces, never
the word): "Fivefold 309 4/6 🟦⬛⬛🟧⬛ …".

## Files

| File               | What                                                                          |
|--------------------|-------------------------------------------------------------------------------|
| `src/ff_core.s`    | rules, pure: word lists, colours, the day's word, a race's word, the seal     |
| `src/ff_play.s`    | a game, pure: the three modes, packets in and out, honesty checks, text       |
| `src/ff_mesh.s`    | the glue: Home words, rooms, invitations, resending, saved board, accessors   |
| `src/ff_win.s`     | the Mac window: tiles, keyboard, box, Share, Race…, Duel…                      |
| `ios/asmmesh/FivefoldView.swift` | the iPhone screen and the Rooms sheet                         |
| `src/ff_words.bin` | 2,016 hidden words, then 3,005 accepted guesses (`tools/ninefold/ff.py pack`) |

## Packets

Room messages flagged `MSGF_GAME`, sealed with the room's key. Byte 0 `F`, byte 1 the kind,
bytes 2-5 the game's number.

| Kind       | Bytes | Carries                                     | Sent                                     |
|------------|-------|---------------------------------------------|------------------------------------------|
| 1 RACE     | 14    | the seed (u64)                              | by the host every 10 s, for late joiners |
| 2 ROW      | 13    | row number, five colours, solved            | once per guess                            |
| 3 DUEL     | 22    | our word sealed (16)                        | every 10 s until they guess               |
| 4 GUESS    | 12    | guess number, the word                      | every 10 s until answered                 |
| 5 FEED     | 12    | guess number, five colours                  | as the answer to a GUESS                  |
| 6 REVEAL   | 27    | our word, the salt (16)                     | every 10 s once both boards are finished  |

## Why a duel can't be cheated

The seal is the first 16 bytes of SHA-256(salt ‖ player id ‖ word). Your word is fixed when
you send it and the other side can't read it. Your device answers their guesses, so during the
game they must trust your colours; at the end your reveal must match the seal, and their
device re-scores every guess against the revealed word. A wrong answer or a different word
marks the game dishonest on their side. The player id in the seal stops a word sealed by one
player being replayed as another's. Packets from anyone but the other player are ignored.

## Today's word

`(unix time − 1767225600) / 86400` (days since 1 January 2026, UTC) picks a hidden word.
The board is saved in the defaults (`fivefoldToday`: "day:guess,guess"), so closing and
reopening the app gives the same board, and a new day gives a new one.

## Tests

- `tools/qemu/run.sh` self-tests 220-223: colours (repeated letters), word lists, the day's
  word, the seal against `tools/ninefold/ff.py`; solo, race and duel games, a lying answer and
  a swapped word caught.
- `tools/qemu/run.sh ffmesh` 224-226: the glue with stand-ins for the app: today's board kept
  across a restart and shared without the word, a race from Home and joined from a packet,
  and a whole duel against a second game, reveals crossing and checking out on both sides.
