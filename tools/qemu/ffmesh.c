// ffmesh.c — runs src/ff_mesh.s (Fivefold's glue) under qemu with stand-ins for the app:
// rooms, people, the defaults, the mesh's send. The other player is ff_play.s itself, on its
// own game, so every packet really crosses. run.sh ffmesh.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define F(name) __asm__("_" #name)
#define FG_SIZE 960
#define FF_EPOCH 1767225600L

// ---- what ff_mesh.s calls -------------------------------------------------------------
unsigned char g_rooms[25 * 64] F(g_rooms);
unsigned char g_nodes[32 * 64] F(g_nodes);
long g_node_count F(g_node_count) = 0;
unsigned long g_node_id F(g_node_id) = 0xAAAA;
char g_nick[32] F(g_nick) = "Mac";
long g_remote_active F(g_remote_active) = 0;
extern unsigned char g_ffs[FG_SIZE] F(g_ffs);
extern unsigned char g_ffg[FG_SIZE] F(g_ffg);
static long now = FF_EPOCH + 5 * 86400 + 100, nrooms = 1, invites, pops;
static char lines[64][1200]; static int nlines;
static unsigned char sent[16][128]; static long sentlen[16]; static int nsent;
static char main_msg[600], pref[200];

long t_time(long *p) F(time);
long t_time(long *p) { (void)p; return now; }
unsigned t_arc4random(void) F(arc4random);
unsigned t_arc4random(void) { return 0x1234; }
void t_arc4random_buf(void *b, long n) F(arc4random_buf);
void t_arc4random_buf(void *b, long n) { for (long i = 0; i < n; i++) ((unsigned char *)b)[i] = (unsigned char)(i * 37 + 11); }
long t_strlen(const char *s) F(strlen);
long t_strlen(const char *s) { return strlen(s); }
int t_strcasecmp(const char *a, const char *b) F(strcasecmp);
int t_strcasecmp(const char *a, const char *b) { return strcasecmp(a, b); }
int t_strncasecmp(const char *a, const char *b, long n) F(strncasecmp);
int t_strncasecmp(const char *a, const char *b, long n) { return strncasecmp(a, b, n); }
long t_strlcpy(char *d, const char *s, long n) F(strlcpy);
long t_strlcpy(char *d, const char *s, long n) { long l = strlen(s); if (n) { long c = l < n - 1 ? l : n - 1; memcpy(d, s, c); d[c] = 0; } return l; }
long t_strlcat(char *d, const char *s, long n) F(strlcat);
long t_strlcat(char *d, const char *s, long n) { long l = strlen(d); return l + t_strlcpy(d + l, s, n > l ? n - l : 0); }
void t_utf8_fix(char *s) F(utf8_fix);
void t_utf8_fix(char *s) { (void)s; }
void t_pref_get(const char *k, char *b, long n) F(pref_get);
void t_pref_get(const char *k, char *b, long n) { (void)k; t_strlcpy(b, pref, n); }
void t_pref_set(const char *k, const char *v) F(pref_set);
void t_pref_set(const char *k, const char *v) { (void)k; t_strlcpy(pref, v, sizeof pref); }
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
long t_mesh_send_game(long room, const void *d, long n) F(mesh_send_game);
long t_mesh_send_game(long room, const void *d, long n) { (void)room; if (nsent < 16 && n <= 128) { memcpy(sent[nsent], d, n); sentlen[nsent++] = n; } return 1; }
long t_mesh_send_msg(long room, const char *t, long f) F(mesh_send_msg);
long t_mesh_send_msg(long room, const char *t, long f) { (void)f; if (room == 0) t_strlcpy(main_msg, t, sizeof main_msg); return 1; }
long t_mesh_send_invite(long node, long room) F(mesh_send_invite);
long t_mesh_send_invite(long node, long room) { (void)node; (void)room; invites++; return 1; }
unsigned long t_new_id(void) F(new_id);
unsigned long t_new_id(void) { return 0x4242; }
long t_room_add(unsigned long id, const char *name, long keep) F(room_add);
long t_room_add(unsigned long id, const char *name, long keep) { (void)keep; *(unsigned long *)(g_rooms + 64 * nrooms) = id; strncpy((char *)g_rooms + 64 * nrooms + 24, name, 31); return nrooms++; }
void t_room_own(long i) F(room_own);
void t_room_own(long i) { (void)i; }
void t_ui_select_room(long i) F(ui_select_room);
void t_ui_select_room(long i) { (void)i; }
void t_ff_ui_show(void) F(ff_ui_show);
void t_ff_ui_show(void) {}
void t_ff_ui_pop(void) F(ff_ui_pop);
void t_ff_ui_pop(void) { pops++; }
long t_report(const char *name, int pass) F(t_report);
long t_report(const char *name, int pass) { printf("%s  %s\n", pass ? "PASS" : "FAIL", name); return !pass; }

// ---- ff_mesh.s, ff_play.s, ff_core.s ---------------------------------------------------
typedef struct { long a, b; } two;        // x0, x1
void h_fivefold(long a, const char *lc, const char *orig) F(h_fivefold);
void ffm_rx(unsigned long room, unsigned long sender, const char *nick, const void *d, long n) F(ffm_rx);
void ffm_tick(void) F(ffm_tick);
long ffm_typed(long room, const char *text) F(ffm_typed);
long am_ff_try(const char *t) F(am_ff_try);
void am_ff_solo(void) F(am_ff_solo);
long am_ff_mode(void) F(am_ff_mode);
long am_ff_cell(long r, long c) F(am_ff_cell);
long am_ff_key(long l) F(am_ff_key);
long am_ff_others(char *b, long n) F(am_ff_others);
long am_ff_room(void) F(am_ff_room);
const char *ff_hidden(long i) F(ff_hidden);
long ff_pick(unsigned long seed) F(ff_pick);
void ffp_begin(void *g, long mode, long word, unsigned long room, unsigned gid, unsigned long me, unsigned long other) F(ffp_begin);
two ffp_guess(void *g, const char *t, long n, void *out) F(ffp_guess);
long ffp_choose(void *g, const char *t, long n, const void *salt, void *out) F(ffp_choose);
two ffp_pkt_in(void *g, unsigned long sender, const char *nick, long nlen, const void *p, long n, void *out) F(ffp_pkt_in);
long ffp_pkt_reveal(const void *g, void *out) F(ffp_pkt_reveal);

static int has(const char *want) { for (int i = 0; i < nlines; i++) if (strstr(lines[i], want)) return 1; return 0; }
static long q(const unsigned char *g, int off) { return *(long *)(g + off); }
static void word(char *out, long i) { memcpy(out, ff_hidden(i), 5); out[5] = 0; }

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    long bad = 0, ok;
    unsigned char *them = calloc(1, FG_SIZE), out[128], pkt[128];
    char w[8], w2[8], buf[1600];

    // 224. today's word: a word not in the list is refused; a guess counts and is kept in the
    //      defaults, so reopening the app gives the same board; solved, its squares go to Main
    //      (never the word); the next day is a new board
    ok = 1;
    h_fivefold(1, "", "");
    ok &= am_ff_mode() == 1 && q(g_ffs, 64) == 5 && pops == 1;
    ok &= am_ff_try("zzzzq") == -2 && am_ff_try("abc") == -1;
    word(w, 6);
    ok &= am_ff_try(w) == 0 && strncmp(pref, "5:", 2) == 0 && strstr(pref, w) != NULL;
    memset(g_ffs, 0, FG_SIZE);
    am_ff_solo();                                                    // reopened
    ok &= q(g_ffs, 72) == 1 && (am_ff_cell(0, 0) >> 8) == w[0] && am_ff_cell(1, 0) == 0;
    word(w, 5);
    ok &= am_ff_try(w) == 1 && q(g_ffs, 8) == 3 && am_ff_cell(1, 2) == (w[2] << 8 | 2);
    ok &= am_ff_key(w[0]) == 2 && am_ff_key('q') == 3 - 3 * !!strchr(w, 'q');
    h_fivefold(4, "", "");
    ok &= strstr(main_msg, "2/6") != NULL && strstr(main_msg, w) == NULL && !strchr(main_msg, '\n');
    now += 86400; am_ff_solo();
    ok &= q(g_ffs, 64) == 6 && q(g_ffs, 72) == 0;
    bad += t_report("224 fivefold today: refused words, kept across a restart, squares to Main, a new day", ok);

    // 225. a race: Home's "fivefold race with Anna" makes the room and invites; the host sends
    //      the seed until... ; Anna's rows show as colours only; ours go as colours; someone
    //      else's race packet starts the same word here
    ok = 1; nlines = 0; pops = 0; nsent = 0;
    g_node_count = 1; *(unsigned long *)g_nodes = 0xA1; strcpy((char *)g_nodes + 40, "Anna");
    h_fivefold(2, "with anna", "with Anna");
    ok &= nrooms == 2 && invites == 1 && am_ff_mode() == 2 && pops == 1 && am_ff_room() == 1;
    now += 11; ffm_tick();
    ok &= nsent == 1 && sent[0][0] == 'F' && sent[0][1] == 1 && sentlen[0] == 14;
    unsigned long seed = *(unsigned long *)(sent[0] + 6);
    unsigned gid = *(unsigned *)(sent[0] + 2);
    ffp_begin(them, 2, ff_pick(seed), 0x4242, gid, 0xA1, 0xAAAA);
    ok &= memcmp(them + 56, g_ffg + 56, 5) == 0;                     // the same word
    long wi = ff_pick(seed);
    word(w2, wi + 1);
    two r = ffp_guess(them, w2, 5, out);
    ok &= r.a == 0 && r.b == 13;
    ffm_rx(0x4242, 0xA1, "Anna", out, r.b);
    am_ff_others(buf, sizeof buf);
    ok &= strstr(buf, "Anna") != NULL && strstr(buf, w2) == NULL;
    nsent = 0;
    memcpy(w, g_ffg + 56, 5); w[5] = 0;
    ok &= ffm_typed(1, w) == 1 && nsent == 1 && sentlen[0] == 13 && q(g_ffg, 8) == 3;
    ok &= ffm_typed(1, "hello there") == 0;                          // chat
    memcpy(pkt, sent[0], 13);                                        // a fresh race, from Bea
    memset(g_ffg, 0, FG_SIZE);
    *(unsigned long *)(g_rooms + 128) = 0x77; strcpy((char *)g_rooms + 128 + 24, "Fivefold Bea"); nrooms = 3;
    unsigned char rp[14] = { 'F', 1, 9, 0, 0, 0 }; *(unsigned long *)(rp + 6) = 777;
    ffm_rx(0x77, 0xB0, "Bea", rp, 14);
    ok &= am_ff_mode() == 2 && q(g_ffg, 16) == 0x77 && q(g_ffg, 48) == 0xB0 && memcmp(g_ffg + 56, ff_hidden(ff_pick(777)), 5) == 0;
    bad += t_report("225 fivefold race: room and invite, the seed sent, colours only both ways, joined from a packet", ok);

    // 226. a duel: our word sealed and sent; theirs taken; our guess answered by them, theirs
    //      by us; both finished, the reveals cross and every answer checks out on both
    ok = 1; nlines = 0; nsent = 0;
    memset(g_ffg, 0, FG_SIZE); nrooms = 1;
    h_fivefold(3, "with anna", "with Anna");
    ok &= am_ff_mode() == 3 && q(g_ffg, 8) == 1 && q(g_ffg, 40) == 0xA1;
    word(w, 10); word(w2, 20);
    ok &= am_ff_try("zzzzq") == -2;                                  // not a word: still choosing
    ok &= am_ff_try(w) == 0 && nsent == 1 && sentlen[0] == 22 && has("sealed");
    ffp_begin(them, 3, -1, 0x4242, 0x1234, 0xA1, 0xAAAA);
    ffp_pkt_in(them, 0xAAAA, "Mac", 3, sent[0], 22, out);
    unsigned char salt[16] = { 5, 4, 3 };
    long n = ffp_choose(them, w2, 5, salt, pkt);
    ok &= n == 22;
    ffm_rx(0x4242, 0xA1, "Anna", pkt, n);
    nsent = 0;
    ok &= am_ff_try(w2) == 0 && nsent == 1 && sentlen[0] == 12;      // our guess, for them
    ok &= (am_ff_cell(0, 0) & 0xFF) == 3;                            // sent, no answer yet
    r = ffp_pkt_in(them, 0xAAAA, "Mac", 3, sent[0], 12, out);
    ok &= r.b == 12;
    ffm_rx(0x4242, 0xA1, "Anna", out, r.b);
    ok &= q(g_ffg, 8) == 3 && (am_ff_cell(0, 4) & 0xFF) == 2;
    word(buf, 30);
    r = ffp_guess(them, buf, 5, pkt);                                // they miss once
    ok &= r.b == 12;
    nsent = 0;
    ffm_rx(0x4242, 0xA1, "Anna", pkt, r.b);
    ok &= nsent == 1 && sentlen[0] == 12;                            // our answer
    ffp_pkt_in(them, 0xAAAA, "Mac", 3, sent[0], 12, out);
    r = ffp_guess(them, w, 5, pkt);                                  // then get it
    nsent = 0;
    ffm_rx(0x4242, 0xA1, "Anna", pkt, r.b);
    ffp_pkt_in(them, 0xAAAA, "Mac", 3, sent[0], 12, out);
    ok &= q(them, 8) == 3;
    nsent = 0; now += 11; ffm_tick();                                // our reveal goes
    int rv = -1; for (int i = 0; i < nsent; i++) if (sent[i][1] == 6) rv = i;
    ok &= rv >= 0;
    if (rv >= 0) ffp_pkt_in(them, 0xAAAA, "Mac", 3, sent[rv], sentlen[rv], out);
    n = ffp_pkt_reveal(them, pkt);
    ok &= n == 27;
    ffm_rx(0x4242, 0xA1, "Anna", pkt, n);
    ok &= q(g_ffg, 280) == 1 && q(them, 280) == 1 && has("you win");
    bad += t_report("226 fivefold duel: sealed words, answers both ways, reveals cross, all honest", ok);

    for (int i = 0; i < nlines; i++) printf("  line %s\n", lines[i]);
    printf("  Main: %s\n", main_msg);
    printf("%ld failed\n", bad);
    return bad != 0;
}
