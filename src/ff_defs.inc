// ff_defs.inc — Fivefold's game (ff_play.s) and packets
.set FFM_SOLO,      1        // modes: the day's word, alone
.set FFM_RACE,      2        //   everyone the same word, the others' colours shown
.set FFM_DUEL,      3        //   each picks the other's word; answers checked at the end
.set FFS_NONE,      0
.set FFS_CHOOSE,    1        // a duel: picking our word for them
.set FFS_PLAY,      2
.set FFS_DONE,      3        // our board is finished (guessed, or six tries)
.set FF_ROWS,       6

.set FG_MODE,       0
.set FG_STATE,      8
.set FG_ROOM,       16
.set FG_GID,        24
.set FG_ME,         32
.set FG_OPP,        40       // a duel's other player
.set FG_HOST,       48
.set FG_WORD,       56       // [8] the word we guess (a duel's: only once revealed)
.set FG_DAY,        64       // the day (solo), or the hidden word's number (race)
.set FG_N,          72       // our guesses
.set FG_GUESS,      80       // [30] six rows of five letters
.set FG_COL,        112      // [30] their colours (0 1 2)
.set FG_SOLVED,     144      // 1 guessed, 2 six tries used
.set FG_MINE,       152      // [8] a duel: our word for them
.set FG_SALT,       160      // [16] a duel: what our word is sealed with
.set FG_THEIRC,     176      // [16] a duel: their word, sealed (0s until it comes)
.set FG_PEND,       192      // a duel: a guess sent, its colours not back yet
.set FG_TN,         200      // a duel: their guesses we answered
.set FG_TGUESS,     208      // [30] their guesses
.set FG_TCOL,       240      // [30] our answers
.set FG_TDONE,      272      // a duel: they're finished: 1 guessed, 2 six tries
.set FG_CHECK,      280      // a duel: their word revealed: 1 every answer was honest, -1 not
.set FG_TWORD,      288      // [8] their word, revealed
.set FG_NPL,        296      // race: players heard
.set FG_START,      304
.set FG_AUX,        312      // the glue's
.set FG_PL,         320      // race players: FF_PLAYERS of PF_SIZE
.set FF_PLAYERS,    8
.set PF_ID,         0
.set PF_NICK,       8        // 24
.set PF_N,          32
.set PF_SOLVED,     40
.set PF_COL,        48       // [32] their colours, row by row
.set PF_SIZE,       80
.set FG_SIZE,       960

// packets: room messages flagged MSGF_GAME, byte 0 'F', 1 kind, +2 game u32
.set FK_RACE,       1        // +6 seed u64 (14)
.set FK_ROW,        2        // +6 row number 1-6, +7 colours[5], +12 solved (13)
.set FK_DUEL,       3        // +6 our word sealed [16] (22)
.set FK_GUESS,      4        // +6 guess number, +7 the word [5] (12)
.set FK_FEED,       5        // +6 guess number, +7 colours [5] (12)
.set FK_REVEAL,     6        // +6 the word [5], +11 salt [16] (27)

// _ffp_guess's answers
.set FFG_NOT5,      -1       // not five letters
.set FFG_NOTWORD,   -2
.set FFG_OVER,      -3       // no guessing now
.set FFG_WAIT,      -4       // a duel: the last guess's colours haven't come back
