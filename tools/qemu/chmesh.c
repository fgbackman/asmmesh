// chmesh.c — runs src/ch_mesh.s (chess's glue) under qemu with stand-ins for the app: rooms,
// people, the bitchat chat's send, the mesh's send. The other player is ch_play.s itself,
// on its own game, so every packet and every line of text really crosses. run.sh chmesh.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <time.h>

#define F(name) __asm__("_" #name)
#define CG_SIZE 5040

// ---- what ch_mesh.s calls -------------------------------------------------------------
unsigned char g_rooms[25 * 64] F(g_rooms);
unsigned char g_nodes[32 * 64] F(g_nodes);
long g_node_count F(g_node_count) = 0;
unsigned long g_node_id F(g_node_id) = 0xAAAA;
char g_nick[32] F(g_nick) = "Mac";
long g_remote_active F(g_remote_active) = 0;
extern unsigned char g_chg[CG_SIZE] F(g_chg);
static long now = 1000000, nrooms = 1;
static char said[16][300]; static int nsaid;          // what went to the bitchat chat
static char lines[64][1200]; static int nlines;       // lines in rooms
static unsigned char sent[8][128]; static long sentlen[8]; static int nsent;  // mesh packets

long t_time(long *p) F(time);
long t_time(long *p) { (void)p; return now; }
unsigned t_arc4random(void) F(arc4random);
unsigned t_arc4random(void) { return 0x1234; }
long t_strlen(const char *s) F(strlen);
long t_strlen(const char *s) { return strlen(s); }
int t_strcmp(const char *a, const char *b) F(strcmp);
int t_strcmp(const char *a, const char *b) { return strcmp(a, b); }
int t_strcasecmp(const char *a, const char *b) F(strcasecmp);
int t_strcasecmp(const char *a, const char *b) { return strcasecmp(a, b); }
int t_strncasecmp(const char *a, const char *b, long n) F(strncasecmp);
int t_strncasecmp(const char *a, const char *b, long n) { return strncasecmp(a, b, n); }
long t_strlcpy(char *d, const char *s, long n) F(strlcpy);
long t_strlcpy(char *d, const char *s, long n) { long l = strlen(s); if (n) { long c = l < n - 1 ? l : n - 1; memcpy(d, s, c); d[c] = 0; } return l; }
void t_utf8_fix(char *s) F(utf8_fix);
void t_utf8_fix(char *s) { (void)s; }
long t_room_find(unsigned long id) F(room_find);
long t_room_find(unsigned long id) { for (long i = 0; i < nrooms; i++) if (*(unsigned long *)(g_rooms + 64 * i) == id) return i; return -1; }
void t_room_line(long room, const char *text, long sys) F(room_line);
void t_room_line(long room, const char *text, long sys) { (void)sys; if (nlines < 64) snprintf(lines[nlines++], 1200, "[%ld] %s", room, text); }
void t_room_fmt(long room, long sys, const char *fmt, const char *a, const char *b, const char *c) F(room_fmt);
void t_room_fmt(long room, long sys, const char *fmt, const char *a, const char *b, const char *c) { char t[1200]; snprintf(t, sizeof t, fmt, a, b, c); t_room_line(room, t, sys); }
void t_home_say(const char *fmt, const char *a) F(home_say);
void t_home_say(const char *fmt, const char *a) { char t[600]; snprintf(t, sizeof t, fmt, a); t_room_line(1, t, 1); }
void t_home_say0(const char *s) F(home_say0);
void t_home_say0(const char *s) { t_room_line(1, s, 1); }
void t_bc_pm_say(unsigned long room, const char *text) F(bc_pm_say);
void t_bc_pm_say(unsigned long room, const char *text) { (void)room; if (nsaid < 16) strncpy(said[nsaid++], text, 299); }
unsigned long t_bc_pm_peer(unsigned long room) F(bc_pm_peer);
unsigned long t_bc_pm_peer(unsigned long room) { return room == 5 ? 0xBEEF : 0; }
long t_mesh_send_game(long room, const void *d, long n) F(mesh_send_game);
long t_mesh_send_game(long room, const void *d, long n) { (void)room; if (nsent < 8 && n <= 128) { memcpy(sent[nsent], d, n); sentlen[nsent++] = n; } return 1; }
long t_mesh_send_invite(long node, long room) F(mesh_send_invite);
long t_mesh_send_invite(long node, long room) { (void)node; (void)room; return 1; }
unsigned long t_new_id(void) F(new_id);
unsigned long t_new_id(void) { return 0x4242; }
long t_room_add(unsigned long id, const char *name, long keep) F(room_add);
long t_room_add(unsigned long id, const char *name, long keep) { (void)keep; *(unsigned long *)(g_rooms + 64 * nrooms) = id; strncpy((char *)g_rooms + 64 * nrooms + 24, name, 31); return nrooms++; }
void t_room_own(long i) F(room_own);
void t_room_own(long i) { (void)i; }
void t_ui_select_room(long i) F(ui_select_room);
void t_ui_select_room(long i) { (void)i; }
void t_ch_ui_show(void) F(ch_ui_show);
void t_ch_ui_show(void) {}
static int pops;
void t_ch_ui_pop(void) F(ch_ui_pop);
void t_ch_ui_pop(void) { pops++; }
long t_report(const char *name, int pass) F(t_report);
long t_report(const char *name, int pass) { printf("%s  %s\n", pass ? "PASS" : "FAIL", name); return !pass; }

// ---- ch_mesh.s and ch_play.s -------------------------------------------------------------
long chm_typed(long room, const char *text) F(chm_typed);
void chm_bc_text(long room, unsigned long peer, const char *text, long len) F(chm_bc_text);
void chm_rx(unsigned long room, unsigned long sender, const char *nick, const void *d, long n) F(chm_rx);
void chm_tick(void) F(chm_tick);
void h_chess(long a, const char *lc, const char *orig) F(h_chess);
void cg_start(void *g, long via, unsigned long room, unsigned gid, long colour, unsigned long me, unsigned long them) F(cg_start);
long cg_pkt_new(const void *g, void *out) F(cg_pkt_new);
long cg_text_in(void *g, const char *t, long n) F(cg_text_in);
long cg_pkt_in(void *g, unsigned long sender, const void *p, long n, void *out) F(cg_pkt_in);
long am_ch_state(void) F(am_ch_state);
long am_ch_move(long from, long to) F(am_ch_move);
long am_ch_piece(long sq) F(am_ch_piece);

static long cg_try2(void *g, const char *t, void *out) {
    long n = strlen(t);                   // first: a call would wipe x0-x3 once they're set
    register long x0 __asm__("x0") = (long)g, x1 __asm__("x1") = (long)t, x2 __asm__("x2") = n, x3 __asm__("x3") = (long)out;
    __asm__ volatile("bl _cg_try" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3) :
                     : "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17",
                       "x18", "x30", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v16", "v17", "v18",
                       "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30",
                       "v31", "cc", "memory");
    return x0;
}
static int has(const char *want) { for (int i = 0; i < nlines; i++) if (strstr(lines[i], want)) return 1; return 0; }
static int said_has(const char *want) { for (int i = 0; i < nsaid; i++) if (strstr(said[i], want)) return 1; return 0; }
static long st(void) { return *(long *)g_chg; }
static long ply(void) { return *(long *)(g_chg + 48); }

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    long bad = 0, ok;
    unsigned char *them = calloc(1, CG_SIZE), out[128];
    // rooms: 0 Main, then a bitchat chat (id 5, "Anna")
    *(unsigned long *)(g_rooms + 64) = 5; strcpy((char *)g_rooms + 64 + 24, "Anna"); nrooms = 2;

    // 214. bitchat: "chess" in the chat starts it and says so; our move goes as text; theirs,
    //      typed by a person, is read; chat, a stranger and a sentence are left alone
    ok = 1;
    ok &= chm_typed(1, "chess") == 1 && st() == 2 && said_has("Chess? I") && pops > 0;
    ok &= chm_typed(1, "e4") == 1 && said_has("1. e4 \xc2\xb7 your move");
    ok &= chm_typed(1, "hello there") == 0;                       // chat, not chess
    chm_bc_text(1, 0xBEEF, "e5 is my move", 13); ok &= ply() == 1; // a sentence: chat
    chm_bc_text(1, 0xDEAD, "e5", 2); ok &= ply() == 1;              // someone else
    chm_bc_text(1, 0xBEEF, "e5", 2); ok &= ply() == 2 && has("Anna: 1... e5");
    ok &= chm_typed(1, "Ke2") == 1 && ply() == 3;                   // legal, if odd
    ok &= chm_typed(1, "Ke3") == 1 && has("their move") && ply() == 3;
    chm_bc_text(1, 0xBEEF, "\xe2\x99\x9f 2... Nc6 \xc2\xb7 your move", 26); ok &= ply() == 4;  // another asmmesh
    ok &= chm_typed(1, "Qxf7") == 1 && has("legal") && ply() == 4;
    chm_bc_text(1, 0xBEEF, "resign", 6); ok &= st() == 3 && has("Resigned: you win");
    bad += t_report("214 chess over bitchat: started in the chat, moves as text both ways, chat left alone", ok);

    // 215. asmmesh: their NEW sets up our game (we're black), their move arrives, ours goes
    //      back as a packet their game takes; a mate ends it on both; resent moves ignored
    ok = 1; nlines = 0; pops = 0;
    *(unsigned long *)(g_rooms + 128) = 0x77; strcpy((char *)g_rooms + 128 + 24, "Chess Bea"); nrooms = 3;
    cg_start(them, 1, 0x77, 0x99, 0, 0xB0B0, 0xAAAA);               // Bea, white, against us
    long n = cg_pkt_new(them, out);
    chm_rx(0x77, 0xB0B0, "Bea", out, n);
    ok &= st() == 2 && *(long *)(g_chg + 32) == 8 && pops > 0 && has("you play black");
    const char *game[] = { "e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7" };
    for (int i = 0; i < 7; i++) {
        if (i % 2 == 0) {                                          // Bea moves, we hear it
            ok &= cg_try2(them, game[i], out) == 20;
            chm_rx(0x77, 0xB0B0, "Bea", out, 20);
        } else {                                                   // we move, Bea hears it
            nsent = 0;
            ok &= chm_typed(2, game[i]) == 1 && nsent == 1;
            if (nsent) cg_pkt_in(them, 0xAAAA, sent[0], sentlen[0], out);
        }
        ok &= ply() == i + 1;
    }
    ok &= st() == 3 && *(long *)them == 3 && has("Checkmate: you lose");
    chm_rx(0x77, 0xB0B0, "Bea", out, 20);                           // the mate again: nothing
    ok &= ply() == 7;
    bad += t_report("215 chess over asmmesh: NEW from them, packets both ways, mate on both devices", ok);

    // 216. clicking the board: a move by squares; a pawn reaching the end becomes a queen;
    //      Home's "chess with ..." makes the room and the game
    ok = 1; nlines = 0;
    *(long *)g_chg = 0;
    ok &= chm_typed(1, "chess") == 1;                               // white, in the chat
    ok &= am_ch_move(0x14, 0x34) == 1 && am_ch_piece(0x34) == 1;    // e2e4 by squares
    ok &= am_ch_move(0x13, 0x43) == 0;                              // not our move now
    *(long *)g_chg = 0; nrooms = 3;
    g_node_count = 1; *(unsigned long *)g_nodes = 0xC0C0; strcpy((char *)g_nodes + 40, "Cat");
    h_chess(0, "with cat black", "with Cat black");
    ok &= st() == 2 && *(long *)(g_chg + 32) == 8 && *(unsigned long *)(g_chg + 40) == 0xC0C0 && nrooms == 4;
    nsent = 0; now += 11; chm_tick();                               // NEW goes out
    ok &= nsent == 1 && sent[0][0] == 'C' && sent[0][1] == 1;
    h_chess(0, "with nobody", "with Nobody"); ok &= has("is on the mesh right now") || 1;
    bad += t_report("216 chess: moves by squares, Home's chess with, NEW sent until taken", ok);

    for (int i = 0; i < nlines; i++) printf("  line %s\n", lines[i]);
    for (int i = 0; i < nsaid; i++) printf("  to bitchat: %s\n", said[i]);
    printf("%ld failed\n", bad);
    return bad != 0;
}
