// mtsim.c — runs src/mt_ble.s (the Meshtastic radio link and its chat) under qemu against a
// simulated radio: _g_mt_test keeps what's written to the radio and counts reads, and the tests
// feed it the radio's messages. Stand-ins for the app as in mcsim.c. run.sh mtsim.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define F(name) __asm__("_" #name)
#define MQ 192

// ---- what mc_ble.s calls -------------------------------------------------------------
extern long g_mt_test F(g_mt_test), g_mt_sim_n F(g_mt_sim_n), g_mt_refused F(g_mt_refused),
            g_mt_state F(g_mt_state), g_mt_nn F(g_mt_nn), g_mt_nonce F(g_mt_nonce), g_mt_reads F(g_mt_reads);
extern unsigned char g_mt_sim[32 * 528] F(g_mt_sim);
void *CBAdvertisementDataServiceUUIDsKey F(CBAdvertisementDataServiceUUIDsKey);
unsigned t_arc4(void) F(arc4random);
unsigned t_arc4(void) { static unsigned x = 0x9E3779B9; x = x * 1103515245 + 12345; return x; }
long t_strlcpy(char *d, const char *s, long n) F(strlcpy);
long t_strlcpy(char *d, const char *s, long n) { long l = strlen(s); if (n) { long c = l < n - 1 ? l : n - 1; memcpy(d, s, c); d[c] = 0; } return l; }
void *g_cm F(g_cm), *g_ctl F(g_ctl);
long g_cur_room F(g_cur_room) = 0;
static long now = 1800000000, room_ok = 1, svc = 1, home_cmds, blocked_id;
static char lines[64][800]; static int nlines;          // lines in the MeshCore room
static char mainl[16][400]; static int nmain;

long t_time(long *p) F(time);
long t_time(long *p) { (void)p; return now; }
long t_strlen(const char *s) F(strlen);
long t_strlen(const char *s) { return strlen(s); }
int t_strcmp(const char *a, const char *b) F(strcmp);
int t_strcmp(const char *a, const char *b) { return strcmp(a, b); }
int t_strncmp(const char *a, const char *b, long n) F(strncmp);
int t_strncmp(const char *a, const char *b, long n) { return strncmp(a, b, n); }
int t_strncasecmp(const char *a, const char *b, long n) F(strncasecmp);
int t_strncasecmp(const char *a, const char *b, long n) { return strncasecmp(a, b, n); }
void *t_memcpy(void *d, const void *s, long n) F(memcpy);
void *t_memcpy(void *d, const void *s, long n) { return memcpy(d, s, n); }
int t_memcmp(const void *a, const void *b, long n) F(memcmp);
int t_memcmp(const void *a, const void *b, long n) { return memcmp(a, b, n); }
long t_svc_on(long i) F(svc_on);
long t_svc_on(long i) { (void)i; return svc; }
long t_room_find(unsigned long id) F(room_find);
long t_room_find(unsigned long id) { return id == 14 && room_ok ? 5 : -1; }
long t_room_add(unsigned long id, const char *n, long k) F(room_add);
long t_room_add(unsigned long id, const char *n, long k) { (void)id; (void)n; (void)k; room_ok = 1; return 5; }
void t_room_drop(long i) F(room_drop);
void t_room_drop(long i) { (void)i; room_ok = 0; }
void t_room_line(long room, const char *t, long sys) F(room_line);
void t_room_line(long room, const char *t, long sys) {
    (void)sys;
    if (room == 5 && nlines < 64) strncpy(lines[nlines++], t, 799);
    else if (room == 0 && nmain < 16) strncpy(mainl[nmain++], t, 399);
}
void t_chat_line(const char *t) F(chat_line);
void t_chat_line(const char *t) { t_room_line(0, t, 1); }
void t_nop(void) F(ui_rooms_changed);
void t_nop(void) {}
void t_nop2(void) F(ui_lists_changed);
void t_nop2(void) {}
void t_nop3(void) F(ui_update_status);
void t_nop3(void) {}
void t_sel(long i) F(ui_select_room);
void t_sel(long i) { (void)i; }
void t_scan(void) F(ble_scan);
void t_scan(void) {}
void t_cancel(void *p) F(ble_cancel);
void t_cancel(void *p) { (void)p; }
void *t_array1(void *o) F(array1);
void *t_array1(void *o) { return o; }
void *t_nsstr(const char *s) F(nsstr);
void *t_nsstr(const char *s) { return (void *)s; }
void *t_cls(const char *n) F(objc_getClass);
void *t_cls(const char *n) { (void)n; return (void *)1; }
long t_msg0(void *r, const char *s) F(msg0);
long t_msg0(void *r, const char *s) { (void)s; return (long)r; }
long t_msg1(void *r, const char *s, long a) F(msg1);
long t_msg1(void *r, const char *s, long a) { (void)s; (void)a; return (long)r; }
long t_msg2(void *r, const char *s, long a, long b) F(msg2);
long t_msg2(void *r, const char *s, long a, long b) { (void)s; (void)a; (void)b; return (long)r; }
long t_msg3(void *r, const char *s, long a, long b, long c) F(msg3);
long t_msg3(void *r, const char *s, long a, long b, long c) { (void)s; (void)a; (void)b; (void)c; return (long)r; }
long t_blk(unsigned long id) F(blk_has);
long t_blk(unsigned long id) { return blocked_id && id == (unsigned long)blocked_id; }
void t_clean(char *t) F(chat_clean);
void t_clean(char *t) { char *p = strstr(t, "darn"); if (p) memcpy(p + 1, "***", 3); }
void t_rec(unsigned long w, unsigned long r, const char *t) F(rec_note);
void t_rec(unsigned long w, unsigned long r, const char *t) { (void)w; (void)r; (void)t; }
void t_home(const char *t, long v) F(home_command);
void t_home(const char *t, long v) { (void)t; (void)v; home_cmds++; }   // must never happen
typedef long (*fn6)(long, long, long, long, long, long);
long t_guard(fn6 f, long a, long b, long c, long d, long e, long g) F(guard_call);
long t_guard(fn6 f, long a, long b, long c, long d, long e, long g) { return f(a, b, c, d, e, g); }
long t_report(const char *name, int pass) F(t_report);
long t_report(const char *name, int pass) { printf("%s  %s\n", pass ? "PASS" : "FAIL", name); return !pass; }

// ---- mt_ble.s, mt_core.s ---------------------------------------------------------------
void mt_start(void) F(mt_start);
void mt_stop(void) F(mt_stop);
void mt_begin(void) F(mt_begin);
long mt_frame_in(const unsigned char *f, long n) F(mt_frame_in);
long mt_write(const unsigned char *f, long n) F(mt_write);
void mt_say(const char *t) F(mt_say);
void mt_tick(void) F(mt_tick);
long mt_allowed(const unsigned char *f, long n) F(mt_allowed);
long am_mt_node_id(long i) F(am_mt_node_id);
const char *am_mt_node_name(long i) F(am_mt_node_name);

static unsigned char *sim(int i) { return g_mt_sim + 528 * i + 8; }
static long simlen(int i) { return *(long *)(g_mt_sim + 528 * i); }
static int has(const char *w) { for (int i = 0; i < nlines; i++) if (strstr(lines[i], w)) return 1; return 0; }
static int memhas(const unsigned char *a, long n, const void *w, long k) { for (long i = 0; i + k <= n; i++) if (!memcmp(a + i, w, k)) return 1; return 0; }
// protobuf, by hand (as mt.py)
typedef struct { unsigned char b[600]; long n; } pb;
static void v(pb *p, unsigned long x) { do { unsigned char c = x & 0x7f; x >>= 7; p->b[p->n++] = c | (x ? 0x80 : 0); } while (x); }
static void fv(pb *p, int f, unsigned long x) { v(p, f << 3); v(p, x); }
static void f32(pb *p, int f, unsigned x) { v(p, f << 3 | 5); memcpy(p->b + p->n, &x, 4); p->n += 4; }
static void fb(pb *p, int f, const void *d, long k) { v(p, f << 3 | 2); v(p, k); memcpy(p->b + p->n, d, k); p->n += k; }
static void fs(pb *p, int f, const char *s) { fb(p, f, s, strlen(s)); }
static void sub(pb *p, int f, pb *q) { fb(p, f, q->b, q->n); }
static void in(pb *p) { mt_frame_in(p->b, p->n); }
static void node(unsigned num, const char *lng, const char *sht) {
    pb u = {0}, n = {0}, r = {0};
    if (lng) fs(&u, 2, lng);
    if (sht) fs(&u, 3, sht);
    fv(&n, 1, num); sub(&n, 2, &u); f32(&n, 5, 1800000000);
    sub(&r, 4, &n); in(&r);
}
static void text(unsigned from, unsigned to, int chan, int port, const char *t, int enc) {
    pb d = {0}, k = {0}, r = {0};
    fv(&d, 1, port); fs(&d, 2, t);
    f32(&k, 1, from); f32(&k, 2, to); if (chan) fv(&k, 3, chan);
    if (enc) fb(&k, 5, "xxxxxxxx", 8); else sub(&k, 4, &d);
    f32(&k, 6, 77);
    fv(&r, 1, 5); sub(&r, 2, &k); in(&r);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    long bad = 0, ok;
    g_mt_test = 1;
    pb r;

    // 239. starting: the room comes with the switch; want_config with a number of ours, then
    //      reads; our own node, nodes by name (long, short, or number); ready only on our number
    ok = 1;
    mt_start();
    ok &= room_ok && has("looking for a Meshtastic radio");
    mt_begin();
    ok &= g_mt_sim_n == 1 && sim(0)[0] == 0x18 && g_mt_reads == 1 && mt_allowed(sim(0), simlen(0));
    r = (pb){0}; { pb m = {0}; fv(&m, 1, 0x100); sub(&r, 3, &m); } in(&r);
    node(0x2A, "Anna \xe2\x80\xae" "x", "AN"); node(0x2B, NULL, "BB"); node(0x2C, NULL, NULL); node(0x100, "Me", "ME");
    node(0x2A, "Anna", "AN");
    r = (pb){0}; { pb c = {0}, s = {0}; fs(&s, 3, "LongFast"); fv(&c, 1, 0); sub(&c, 2, &s); fv(&c, 3, 1); sub(&r, 10, &c); } in(&r);
    r = (pb){0}; fv(&r, 7, g_mt_nonce + 1); in(&r);       // someone else's number: not ready
    ok &= g_mt_state == 2;
    r = (pb){0}; fv(&r, 7, g_mt_nonce); in(&r);
    ok &= g_mt_state == 3 && g_mt_nn == 3 && has("3 nodes") && !strcmp(am_mt_node_name(0), "Anna")
          && !strcmp(am_mt_node_name(1), "BB") && !strcmp(am_mt_node_name(2), "!0000002c");
    bad += t_report("239 meshtastic radio (simulated): want_config, reads, nodes named, ready on our number only", ok);

    // 240. messages: text to everyone (another channel says which), to us, cleaned and filtered;
    //      not shown: to others, from ourselves, other ports (admin), encrypted, blocked nodes
    ok = 1;
    text(0x2A, 0xFFFFFFFF, 0, 1, "hi \xe2\x80\xae" "evil\nline, darn", 0);
    ok &= has("Anna: hi    evil line, d***");
    text(0x2A, 0xFFFFFFFF, 2, 1, "on two", 0);
    ok &= has("Anna (channel 2): on two");
    text(0x2B, 0x100, 0, 1, "just you", 0);
    ok &= has("BB \xe2\x86\x92 you: just you");
    text(0x2B, 0x555, 0, 1, "not for us", 0);
    text(0x100, 0xFFFFFFFF, 0, 1, "my own echo", 0);
    text(0x2A, 0xFFFFFFFF, 0, 6, "admin payload", 0);
    text(0x2A, 0xFFFFFFFF, 0, 1, "sealed", 1);
    ok &= !has("not for us") && !has("my own echo") && !has("admin payload") && !has("sealed");
    blocked_id = am_mt_node_id(0);
    text(0x2A, 0xFFFFFFFF, 0, 1, "blocked words", 0);
    ok &= !has("blocked words");
    blocked_id = 0;
    text(0x99, 0xFFFFFFFF, 0, 1, "stranger", 0);
    ok &= has("!00000099: stranger") && home_cmds == 0;
    bad += t_report("240 meshtastic messages: shown cleaned and filtered; others, echoes, admin, sealed, blocked not", ok);

    // 241. sending, and the wall: to everyone and @Name built right and allowed; nothing off the
    //      list ever written; garbage harmless; the heartbeat; off is off
    ok = 1;
    long s0 = g_mt_sim_n;
    mt_say("hello mesh");
    ok &= g_mt_sim_n == s0 + 1 && mt_allowed(sim(s0), simlen(s0)) && memhas(sim(s0), simlen(s0), "\x15\xff\xff\xff\xff", 5)
          && memhas(sim(s0), simlen(s0), "hello mesh", 10) && sim(s0)[simlen(s0) - 2] != 0x50 && has("me: hello mesh");
    mt_say("@anna see you at 6");
    ok &= g_mt_sim_n == s0 + 2 && memhas(sim(s0 + 1), simlen(s0 + 1), "\x15\x2a\x00\x00\x00", 5)
          && !memcmp(sim(s0 + 1) + simlen(s0 + 1) - 2, "\x50\x01", 2) && has("me \xe2\x86\x92 Anna: see you at 6");
    mt_say("@nobody hi");
    ok &= g_mt_sim_n == s0 + 2 && has("Nobody by that name");
    unsigned char admin[] = { 0x0a, 0x0b, 0x15, 1, 0, 0, 0, 0x22, 0x04, 0x08, 0x06, 0x12, 0x00 };
    ok &= mt_write(admin, sizeof admin) == 0 && g_mt_refused == 1;
    srand(9);
    for (int i = 0; i < 3000; i++) {
        unsigned char f[600]; long n = rand() % 520;
        for (long j = 0; j < n; j++) f[j] = rand();
        if (i % 3 == 0 && n > 4) { f[0] = 0x12; f[1] = n - 2 < 127 ? n - 2 : 127; f[2] = 0x22; }
        if (i % 7 == 0) text(rand(), rand() % 2 ? 0xFFFFFFFF : 0x100, rand() % 9, rand() % 8, "x", rand() % 2);
        mt_frame_in(f, n);
        if (i % 40 == 0) { now += 10; mt_tick(); }
    }
    for (int i = 0; i < g_mt_sim_n; i++) ok &= mt_allowed(sim(i), simlen(i)) == 1;
    ok &= g_mt_refused == 1 && home_cmds == 0 && g_mt_nn <= 128;
    long beats = 0; for (int i = 0; i < g_mt_sim_n; i++) beats += simlen(i) == 2 && sim(i)[0] == 0x3a;
    ok &= beats >= 1;
    mt_stop();
    ok &= !room_ok && g_mt_state == 0 && g_mt_nn == 0;
    bad += t_report("241 meshtastic wall: everyone and @Name sent right; only allowed messages written; garbage harmless", ok);

    for (int i = 0; i < nlines && i < 12; i++) printf("  room %s\n", lines[i]);
    printf("%ld failed\n", bad);
    return bad != 0;
}
