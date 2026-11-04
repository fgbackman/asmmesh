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

// A game (ch_play.s): one at a time on a device
.set CGS_NONE,      0
.set CGS_PLAY,      2
.set CGS_OVER,      3
.set CGV_MESH,      1        // in an invite-only asmmesh room
.set CGV_BITCHAT,   2        // in a bitchat private chat: moves as text
.set CGR_WHITE,     1        // results
.set CGR_BLACK,     2
.set CGR_DRAW,      3
.set CGE_MATE,      1        // how it ended
.set CGE_RESIGN,    2
.set CGE_STALE,     3
.set CGE_FIFTY,     4
.set CGE_MATERIAL,  5
.set CGE_REPEAT,    6
.set CGE_AGREED,    7
.set CGE_LONG,      8        // 400 moves
.set CG_STATE,      0
.set CG_VIA,        8
.set CG_ROOM,       16
.set CG_GID,        24
.set CG_ME,         32       // our colour: 0 white, 8 black
.set CG_OPP,        40       // the other player's id (asmmesh node, or bitchat peer)
.set CG_PLY,        48       // moves played (half-moves)
.set CG_RESULT,     56
.set CG_REASON,     64
.set CG_DRAW,       72       // 1 we offered a draw, 2 they did
.set CG_AUX,        80       // the glue's: when we last sent again
.set CG_ME_ID,      88
.set CG_POS,        96       // the position now (CP_SIZE)
.set CG_HIST,       232      // u64[CG_MAXPLY + 1]: each position's hash, for repetitions
.set CG_MOVES,      3440     // u32[CG_MAXPLY]: the moves
.set CG_MAXPLY,     400
.set CG_SIZE,       5040

// game packets: room messages flagged MSGF_GAME, byte 0 'C', 1 kind
.set CK_NEW,        1        // +2 game u32 +6 white id u64 +14 black id u64 (22)
.set CK_MOVE,       2        // +2 game +6 ply u16 (after it) +8 move u32 +12 hash after u64 (20)
.set CK_RESIGN,     3        // +2 game (6)
.set CK_ASK,        4        // +2 game +6 how many moves we have u16 (8): send the rest
.set CK_HIST,       5        // +2 game +6 first u16 +8 n +9 moves u32[n <= 24]
.set CK_DRAW,       6        // +2 game +6 ply u16 (8): an offer, or yes to theirs
.set CK_HIST_MAX,   24

// _cg_try
.set CGT_NOTPLAYING, -11
.set CGT_NOTYOURS,  -10
