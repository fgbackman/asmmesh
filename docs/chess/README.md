# Chess for asmmesh

Status: **built, not yet tried on devices.** The rules and the game are pure code tested under
qemu (self-tests 205-213; `tools/qemu/run.sh chperft` for deep perft), and the glue runs under
qemu with stand-ins for the app (`run.sh chmesh`, tests 214-216). The Mac and iPhone parts
assemble; the Swift wasn't compiled here.

## Two ways to play

| With                | How it starts                                      | How moves travel                              |
|---------------------|----------------------------------------------------|-----------------------------------------------|
| someone on asmmesh  | `chess with Anna` (Home), the chess button, ⌘8      | game packets in an invite-only room           |
| someone on bitchat  | `chess` in your private bitchat chat with them      | text in that chat: "♟ 12. Nf3 · your move"    |

bitchat itself has no chess, so a bitchat person plays by typing moves. asmmesh reads them
(`e5`, `Nf6`, `exd5`, `O-O`, `e7e8q`, `resign`, `draw`) and checks each one. Only a message
that is one word counts (or asmmesh's own "♟ …" lines, so two asmmesh users can play over
bitchat too); anything else stays chat.

## Rules (`src/ch_core.s`)

- A 0x88 board; every legal move, including castling (not out of, through or into check),
  en passant and promotion to any piece.
- Check, checkmate, stalemate, the fifty-move rule, bare kings (or one minor piece).
- Moves read as typed in standard notation or as squares, and written in standard notation
  with the file or rank added only when needed, `+` and `#`.
- Perft against the published counts, the standard test of a move generator:

  | Position              | Depth | Positions | Where                  |
  |-----------------------|-------|-----------|------------------------|
  | start                 | 3     | 8,902     | self-test 205          |
  | start                 | 5     | 4,865,609 | `run.sh chperft`       |
  | Kiwipete              | 3     | 97,862    | `run.sh chperft`       |
  | position 3            | 5     | 674,624   | `run.sh chperft`       |
  | position 4            | 4     | 422,333   | `run.sh chperft`       |
  | position 5            | 3     | 62,379    | `run.sh chperft`       |
  | position 6            | 3     | 89,890    | `run.sh chperft`       |

## The game (`src/ch_play.s`)

| Packet   | Carries                                         | Taken when                                          |
|----------|-------------------------------------------------|-----------------------------------------------------|
| `NEW`    | game id, who's white, who's black               | we're one of them and the sender is the other       |
| `MOVE`   | its number, the move, the position's hash after | from the other player, their turn, legal, the next  |
| `RESIGN` | game id                                         | from the other player                               |
| `DRAW`   | game id, move number                            | an offer, or yes to ours                            |
| `ASK`    | how many moves we have                          | answered with `HIST`                                |
| `HIST`   | up to 24 moves from a point                     | only the other player's moves: ours we always have  |

- The maker of a game sends `NEW` every 10 s until the other player has moved, so they get it
  after joining the room. Each side sends its last move again every 10 s until answered.
- Over: checkmate, resignation, agreed draw, stalemate, fifty moves, threefold repetition,
  bare kings, or 400 moves.

## Security

- Only the other player of this game is heard; every move is checked against the rules on
  each device, so neither can make an illegal move, move out of turn, or move for the other.
- Packets are room messages sealed with the room's key and signed by their sender.
- Over bitchat, only text crosses the wall: the game is kept in that private chat (bitchat's
  own end-to-end encryption) and never touches asmmesh's rooms, devices, rules or keys.
