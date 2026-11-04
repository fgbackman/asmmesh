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
