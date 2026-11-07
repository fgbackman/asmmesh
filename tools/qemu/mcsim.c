// mcsim.c — runs src/mc_ble.s (the MeshCore radio link and its chat) under qemu against a
// simulated radio: _g_mc_test keeps what's written to the radio, and the tests feed it the
// radio's frames. Stand-ins for the app: rooms, the switch, blocking, the filter. run.sh mcsim.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define F(name) __asm__("_" #name)
#define MQ 192

// ---- what mc_ble.s calls -------------------------------------------------------------
extern long g_mc_test F(g_mc_test), g_mc_sim_n F(g_mc_sim_n), g_mc_refused F(g_mc_refused),
            g_mc_state F(g_mc_state), g_mc_cn F(g_mc_cn);
extern unsigned char g_mc_sim[32 * MQ] F(g_mc_sim);
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
long t_room_find(unsigned long id) { return id == 13 && room_ok ? 5 : -1; }
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

// ---- mc_ble.s, mc_core.s -----------------------------------------------------------------
void mc_start(void) F(mc_start);
void mc_stop(void) F(mc_stop);
void mc_begin(void) F(mc_begin);
long mc_frame_in(const unsigned char *f, long n) F(mc_frame_in);
long mc_send(const unsigned char *f, long n) F(mc_send);
void mc_say(const char *t) F(mc_say);
void mc_tick(void) F(mc_tick);
long mc_allowed(const unsigned char *f, long n, long slot) F(mc_allowed);
long am_mc_contact_id(long i) F(am_mc_contact_id);
const char *am_mc_contact_name(long i) F(am_mc_contact_name);

static unsigned char *sim(int i) { return g_mc_sim + MQ * i + 8; }
static long simlen(int i) { return *(long *)(g_mc_sim + MQ * i); }
static int has(const char *w) { for (int i = 0; i < nlines; i++) if (strstr(lines[i], w)) return 1; return 0; }
static void in(const unsigned char *f, long n) { mc_frame_in(f, n); }
static void inx(const char *hex) { unsigned char f[256]; long n = strlen(hex) / 2; for (long i = 0; i < n; i++) sscanf(hex + 2 * i, "%2hhx", &f[i]); in(f, n); }
static void contact(const char *name, unsigned char k0) {
    unsigned char f[148] = { 0x03 }; for (int i = 1; i <= 32; i++) f[i] = k0 + i;
    f[33] = 1; strcpy((char *)f + 100, name); f[132] = 1; in(f, 148);
}
static void chan(const char *text) { unsigned char f[200] = { 0x11, 0xf8, 0, 0, 0, 1, 0, 1, 2, 3, 4 }; long n = strlen(text); memcpy(f + 11, text, n); in(f, 11 + n); }
static void dm(unsigned char k0, int tt, const char *text) {
    unsigned char f[200] = { 0x10, 0, 0, 0 }; for (int i = 0; i < 6; i++) f[4 + i] = k0 + 1 + i;
    f[10] = 0; f[11] = tt; long o = tt == 2 ? 20 : 16; long n = strlen(text); memcpy(f + o, text, n); in(f, o + n);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    long bad = 0, ok;
    g_mc_test = 1;

    // 234. starting: the room comes with the switch; APP_START first, and each next command
    //      only once the radio answered the last; its name shown; its contacts kept
    ok = 1;
    mc_start();
    ok &= room_ok && has("looking for a radio");
    mc_begin();
    ok &= g_mc_sim_n == 1 && sim(0)[0] == 0x01 && !memcmp(sim(0) + 8, "asmmesh", 7);
    unsigned char self[71] = { 0x05 }; memcpy(self + 58, "Base camp\n\xe2\x80\xae", 13);
    in(self, 71);
    ok &= g_mc_state == 3 && has("Base camp") && !has("\n\xe2\x80\xae") && g_mc_sim_n == 2 && sim(1)[0] == 0x16;
    inx("0d09022801000000");                          // device info: firmware 9, 1 channel
    ok &= g_mc_sim_n == 3 && sim(2)[0] == 0x04;
    inx("0202000000");                                // contacts: 2
    ok &= g_mc_sim_n == 4 && sim(3)[0] == 0x0a;       // then messages
    contact("Anna", 0x10); contact("Bob", 0x40); contact("Anna", 0x10);
    inx("0400000000");
    ok &= g_mc_cn == 2 && !strcmp(am_mc_contact_name(1), "Bob");
    bad += t_report("234 meshcore radio (simulated): started in order, one command at a time, contacts kept", ok);

    // 235. messages: Public channel lines as "Name: text", cleaned and filtered; direct ones
    //      as "Name → you"; a CLI reply never shown as chat; a blocked contact hidden; the
    //      next message asked for until there are no more; nothing ever reaches Home
    ok = 1;
    inx("0a");                                        // no more (the first sync)
    long n0 = g_mc_sim_n;
    inx("83");                                        // messages waiting
    ok &= g_mc_sim_n == n0 + 1 && sim(n0)[0] == 0x0a;
    chan("Bob: hi \xe2\x80\xae" "evil\nline, darn");
    ok &= has("Bob: hi    evil line, d***") && g_mc_sim_n == n0 + 2;
    dm(0x10, 0, "lunch?");
    ok &= has("Anna \xe2\x86\x92 you: lunch?");
    dm(0x10, 2, "signed hi");
    ok &= has("Anna \xe2\x86\x92 you: signed hi");
    dm(0x10, 1, "reboot ok");                         // a CLI reply: not chat
    ok &= !has("reboot ok");
    dm(0x99, 0, "who am I");                          // not a contact
    ok &= has("someone \xe2\x86\x92 you: who am I");
    blocked_id = am_mc_contact_id(1);                 // Bob blocked
    chan("Bob: still here");
    ok &= !has("still here");
    blocked_id = 0;
    inx("0a");
    ok &= home_cmds == 0;
    bad += t_report("235 meshcore messages: cleaned, filtered, direct ones marked, CLI and blocked not shown", ok);

    // 236. sending, and the wall: Public and @Name messages built right; nothing off the list
    //      ever written; garbage from a radio harmless
    ok = 1;
    long s0 = g_mc_sim_n;
    mc_say("hello all");
    ok &= g_mc_sim_n == s0 + 1 && sim(s0)[0] == 0x03 && sim(s0)[1] == 0 && sim(s0)[2] == 0
          && simlen(s0) == 16 && !memcmp(sim(s0) + 7, "hello all", 9) && has("me: hello all");
    inx("06010000000000000000");                      // sent
    mc_say("@anna see you at 6");
    ok &= g_mc_sim_n == s0 + 2 && sim(s0 + 1)[0] == 0x02 && sim(s0 + 1)[1] == 0 && sim(s0 + 1)[7] == 0x11
          && !memcmp(sim(s0 + 1) + 13, "see you at 6", 12) && has("me \xe2\x86\x92 Anna: see you at 6");
    inx("06010000000000000000");
    mc_say("@nobody hi");
    ok &= g_mc_sim_n == s0 + 2 && has("Nobody by that name");
    unsigned char reboot[7] = { 0x13, 'r', 'e', 'b', 'o', 'o', 't' };
    ok &= mc_send(reboot, 7) == 0 && g_mc_refused == 1;
    srand(5);
    for (int i = 0; i < 3000; i++) {                  // garbage from the radio
        unsigned char f[256]; long n = 1 + rand() % 255;
        for (long j = 0; j < n; j++) f[j] = rand();
        if (i % 3 == 0) f[0] = (unsigned char[]){ 0x03, 0x05, 0x07, 0x08, 0x10, 0x11, 0x12, 0x1b, 0x83, 0x8a }[rand() % 10];
        in(f, n);
        if (i % 50 == 0) { now += 5; mc_tick(); }
    }
    for (int i = 0; i < g_mc_sim_n; i++) ok &= mc_allowed(sim(i), simlen(i), 0) == 1;
    ok &= g_mc_refused == 1 && home_cmds == 0 && g_mc_cn <= 64;
    mc_stop();
    ok &= !room_ok && g_mc_state == 0 && g_mc_cn == 0;
    bad += t_report("236 meshcore wall: Public and @Name sent right; only allowed frames written; garbage harmless", ok);

    for (int i = 0; i < nlines && i < 14; i++) printf("  room %s\n", lines[i]);
    printf("%ld failed\n", bad);
    return bad != 0;
}
