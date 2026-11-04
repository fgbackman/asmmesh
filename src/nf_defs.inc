// nf_defs.inc — Ninefold's layouts, shared by nf_core.s (pure) and nf_game.s
// The word table (nf_words.bin, made by tools/ninefold/nf.py pack): "NINEFOLD", count u32,
// 4 zero bytes, then 10-byte records in alphabetical order: letters a-z zero-padded to 9, flags.
.set NF_HDR,        16
.set NF_REC,        10
.set NFF_ANSWER,    1        // flags: an answer (counted, revealed, "missed")
.set NFF_EXTRA,     2        //   also accepted: scores, never shown as missed
.set NFF_FAMILY,    4        //   hidden while the family filter is on
.set NF_MINANS,     15       // a centre letter must leave 15..60 answers
.set NF_MAXANS,     60
.set NF_MAXW,       250      // words in a puzzle: an index is one byte
.set NF_TRIES,      4096

// a puzzle (_nf_puzzle)
.set NP_TILES,      0        // 9 letters, the centre at 4
.set NP_CENTRE,     9        // the centre letter
.set NP_WORD,       10       // the nine-letter word, NUL-terminated (10 bytes)
.set NP_N,          24       // words in the puzzle
.set NP_ANS,        32       //   of which answers (family words not counted)
.set NP_TRIES,      40       // seeds tried (for the tests)
.set NP_IDX,        48       // u16[NF_MAXW + 6]: table index of each word, alphabetical
.set NP_SIZE,       560

// _nf_find's answers
.set NF_NOTWORD,    -1
.set NF_LENGTH,     -2
.set NF_NOCENTRE,   -3
.set NF_TILES,      -4
.set NF_DUP,        -5       // found already
.set NF_CLOSED,     -6       // no round being played
.set NF_HIDDEN,     -7       // a family-filter word, and the filter is on
.set NF_FULL,       -8       // too many claims this round

// game packets: room messages with MSGF_GAME, sealed with the room's key. Byte 0 'N', 1 kind:
.set NK_START,      1        // +2 game u32 +6 round +7 rounds +8 secs u16 +10 seed u64 +18 start u32
                             //   +22 lists hash[8] +30 family (31 bytes)
.set NK_CLAIM,      3        // +2 game +6 round +7 length +8 time u32 +12 commitment[16] (28)
.set NK_REVEAL,     4        // +2 game +6 round +7 part +8 parts +9 salt[16] +25 n +26 indexes[n]
.set NK_START_LEN,  31
.set NK_CLAIM_LEN,  28
.set NK_REV_HDR,    26
.set NK_REV_MAX,    80       // indexes in one REVEAL
.set NF_GRACE,      5        // claims still taken this long after the round, for slow hops
.set NF_REVEAL_WAIT, 12      // seconds after the round before it is scored
.set NF_FIRST_WINDOW, 2      // claims within 2 s of the first share "first"

// a game (nf_play.s)
.set NFS_NONE,      0
.set NFS_LOBBY,     1        // room made, invitations out, not started
.set NFS_WAIT,      2        // a round is set, its start time not reached
.set NFS_PLAY,      3
.set NFS_REVEAL,    4        // the round is over: reveals coming in
.set NFS_DONE,      5        // the round is scored
.set G_STATE,       0
.set G_ROOM,        8
.set G_GID,         16
.set G_HOST,        24
.set G_ME,          32
.set G_ROUND,       40
.set G_ROUNDS,      48
.set G_SECS,        56
.set G_SEED,        64
.set G_START,       72
.set G_FAMILY,      80
.set G_NPL,         88
.set G_NCL,         96
.set G_MYN,         104      // words I found this round
.set G_AUX,         112      // the glue's (nf_mesh.s): last START sent
.set G_HASH,        120
.set G_SALT,        128      // [16] my salt this round
.set G_PUZ,         144      // the puzzle (NP_SIZE)
.set G_MINE,        704      // u8[256]: I found word i
.set G_FIND,        960      // u16[256]: players (bits) whose claim of word i checked out
.set G_FIRST,       1472     // u16[256]: of those, who was first
.set G_PL,          1984     // NF_PLAYERS players
.set NF_PLAYERS,    12
.set PL_ID,         0
.set PL_NICK,       8        // 24, NUL-terminated
.set PL_CLAIMS,     32       // this round
.set PL_SCORE,      40       // the game so far
.set PL_RSCORE,     48       // this round
.set PL_WORDS,      56       // this round, checked
.set PL_REVEALED,   64
.set PL_SALT,       72       // [16]
.set PL_SIZE,       104
.set G_CL,          3232     // claims this round
.set NF_CLMAX,      768
.set NF_PLCL,       100      // claims one player may make in a round
.set CL_SLOT,       0
.set CL_LEN,        1
.set CL_USED,       2        // its word was revealed and checks out
.set CL_IDX,        3
.set CL_TIME,       4
.set CL_COMMIT,     8
.set CL_SIZE,       24
.set G_SIZE,        21664
