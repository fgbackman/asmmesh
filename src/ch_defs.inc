// ch_defs.inc — chess layouts, shared by ch_core.s (pure rules) and the files that use it
// A position: a 0x88 board (square = rank * 16 + file; a1 0, h1 7, a8 0x70, h8 0x77).
// Pieces: 0 empty; white 1 pawn 2 knight 3 bishop 4 rook 5 queen 6 king; black the same | 8.
.set CP_BOARD,      0        // [128]
.set CP_SIDE,       128      // 0 white to move, 8 black
.set CP_CASTLE,     129      // 1 white O-O, 2 white O-O-O, 4 black O-O, 8 black O-O-O
.set CP_EP,         130      // the square a pawn may capture en passant, 0xFF none
.set CP_HALF,       131      // moves since a capture or pawn move (fifty-move rule)
.set CP_FULL,       132      // u16: the move number
.set CP_WKING,      134
.set CP_BKING,      135
.set CP_SIZE,       136

// A move, 32 bits: from | to << 8 | promotion piece type << 16 | flags << 24
.set CMF_CAPTURE,   1
.set CMF_EP,        2
.set CMF_CASTLE,    4
.set CMF_DOUBLE,    8
.set CH_MAXMOVES,   256

// _ch_status
.set CHS_PLAY,      0
.set CHS_CHECK,     1
.set CHS_MATE,      2
.set CHS_STALE,     3
.set CHS_FIFTY,     4
.set CHS_MATERIAL,  5        // neither side can mate

// _ch_parse
.set CHP_ILLEGAL,   -1       // reads as a move, but it isn't legal here
.set CHP_AMBIGUOUS, -2       // more than one legal move fits
.set CHP_UNREADABLE, -3      // not a move at all
