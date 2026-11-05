// quick.c — runs src/quick.s (your shortcuts, and the devices kept between launches) under
// qemu with stand-ins for the app: Home, the defaults (NSUserDefaults and NSData, by
// selector name), the device table. run.sh quick.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>

#define F(name) __asm__("_" #name)
#define DEV 256

// ---- what quick.s calls ----------------------------------------------------------------
unsigned char g_devs[256 * DEV] F(g_devs);
long g_dev_count F(g_dev_count) = 0;
long g_no_persist F(g_no_persist) = 0;
long g_remote_active F(g_remote_active) = 0;
extern long g_qk_count F(g_qk_count);
static char pref[8192], said[64][300], ran[64][300];
static int nsaid, nran, uichanged, saves, removes;
static unsigned char *stored; static long storedlen = -1;   // "savedDevices"

long qk_try(const char *t) F(qk_try);
long t_norm(char *d, const char *s, long max, long lower) F(norm);
long t_norm(char *d, const char *s, long max, long lower) {
    long n = 0; int sp = 0;
    while (*s == ' ') s++;
    for (; *s && n < max - 1; s++) {
        if (*s == ' ') { sp = 1; continue; }
        if (sp && n) d[n++] = ' ';
        sp = 0;
        d[n++] = lower ? tolower((unsigned char)*s) : *s;
    }
    while (n && strchr(".!?", d[n - 1])) n--;
    d[n] = 0; return n;
}
void t_home_command(const char *t, long voice) F(home_command);
void t_home_command(const char *t, long voice) {     // as Home: a shortcut's name first
    (void)voice;
    if (nran < 64) strncpy(ran[nran++], t, 299);
    qk_try(t);
}
void t_home_say(const char *fmt, const char *a) F(home_say);
void t_home_say(const char *fmt, const char *a) { if (nsaid < 64) snprintf(said[nsaid++], 300, fmt, a); }
void t_home_say0(const char *s) F(home_say0);
void t_home_say0(const char *s) { if (nsaid < 64) strncpy(said[nsaid++], s, 299); }
void t_pref_get(const char *k, char *b, long n) F(pref_get);
void t_pref_get(const char *k, char *b, long n) { (void)k; strncpy(b, pref, n - 1); b[n - 1] = 0; }
void t_pref_set(const char *k, const char *v) F(pref_set);
void t_pref_set(const char *k, const char *v) { (void)k; strncpy(pref, v, sizeof pref - 1); }
void t_qk_ui_changed(void) F(qk_ui_changed);
void t_qk_ui_changed(void) { uichanged++; }
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
long t_strlcat(char *d, const char *s, long n) F(strlcat);
long t_strlcat(char *d, const char *s, long n) { long l = strlen(d); return l + t_strlcpy(d + l, s, n > l ? n - l : 0); }
void *t_memcpy(void *d, const void *s, long n) F(memcpy);
void *t_memcpy(void *d, const void *s, long n) { return memcpy(d, s, n); }
void *t_memmove(void *d, const void *s, long n) F(memmove);
void *t_memmove(void *d, const void *s, long n) { return memmove(d, s, n); }
int t_memcmp(const void *a, const void *b, long n) F(memcmp);
int t_memcmp(const void *a, const void *b, long n) { return memcmp(a, b, n); }
// the defaults and NSData, by selector
typedef struct { unsigned char *p; long n; } blob;
static char defaults_obj, nsdata_cls;
void *t_defaults(void) F(defaults);
void *t_defaults(void) { return &defaults_obj; }
void *t_nsstr(const char *s) F(nsstr);
void *t_nsstr(const char *s) { return (void *)s; }
void *t_getclass(const char *n) F(objc_getClass);
void *t_getclass(const char *n) { return strcmp(n, "NSData") ? NULL : &nsdata_cls; }
long t_msg0(void *r, const char *sel) F(msg0);
long t_msg0(void *r, const char *sel) { blob *b = r; return !strcmp(sel, "length") ? b->n : !strcmp(sel, "bytes") ? (long)b->p : 0; }
long t_msg1(void *r, const char *sel, const char *key) F(msg1);
long t_msg1(void *r, const char *sel, const char *key) {
    static blob out;
    (void)r; (void)key;
    if (!strcmp(sel, "dataForKey:")) { if (storedlen < 0) return 0; out.p = stored; out.n = storedlen; return (long)&out; }
    if (!strcmp(sel, "removeObjectForKey:")) { removes++; storedlen = -1; }
    return 0;
}
long t_msg2(void *r, const char *sel, long a, long b) F(msg2);
long t_msg2(void *r, const char *sel, long a, long b) {
    if (r == &nsdata_cls && !strcmp(sel, "dataWithBytes:length:")) {
        blob *x = malloc(sizeof *x); x->n = b; x->p = malloc(b ? b : 1); memcpy(x->p, (void *)a, b); return (long)x;
    }
    if (r == &defaults_obj && !strcmp(sel, "setObject:forKey:")) {
        blob *x = (blob *)a; free(stored); stored = malloc(x->n ? x->n : 1); memcpy(stored, x->p, x->n); storedlen = x->n; saves++;
    }
    return 0;
}
long t_report(const char *name, int pass) { printf("%s  %s\n", pass ? "PASS" : "FAIL", name); return !pass; }

// ---- quick.s ---------------------------------------------------------------------------
void h_quick(long a, const char *lc, const char *orig) F(h_quick);
void qk_load(void) F(qk_load);
long qk_save(const char *n, const char *c) F(qk_save);
const char *am_qk_name(long i) F(am_qk_name);
const char *am_qk_cmds(long i) F(am_qk_cmds);
long am_qk_delete(long i) F(am_qk_delete);
void dv_load(void) F(dv_load);
void dv_tick(void) F(dv_tick);

static int saidhas(const char *w) { for (int i = 0; i < nsaid; i++) if (strstr(said[i], w)) return 1; return 0; }
static unsigned char *dev(int i) { return g_devs + DEV * i; }
static long q(unsigned char *d, int off) { return *(long *)(d + off); }
static void mkdev(int i, long kind, const char *id, const char *name) {
    memset(dev(i), 0, DEV); *(long *)dev(i) = kind; *(long *)(dev(i) + 16) = 1; *(long *)(dev(i) + 24) = 80;
    *(long *)(dev(i) + 32) = 0x1234; *(long *)(dev(i) + 8) = 0x100 | 3;
    strcpy((char *)dev(i) + 48, id); strcpy((char *)dev(i) + 112, name); strcpy((char *)dev(i) + 224, "Office");
}
static void tick30(void) { for (int i = 0; i < 30; i++) dv_tick(); }

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    long bad = 0, ok;
    char line[400];

    // 227. shortcuts: made from Home, run by name (any case) as each command in order, split by
    //      ; and "then"; not by a longer sentence; one can't run another; bad names, a full
    //      list; saved and read back the same; deleted
    ok = 1;
    h_quick(1, "", "Movie Night: dim living room to 20%;  tv on then kitchen lamp off");
    ok &= g_qk_count == 1 && !strcmp(am_qk_name(0), "Movie Night") && saidhas("saved") && uichanged == 1;
    ok &= qk_try("movie night") == 1 && nran == 3 && !strcmp(ran[0], "dim living room to 20%")
        && !strcmp(ran[1], "tv on") && !strcmp(ran[2], "kitchen lamp off");
    ok &= qk_try("movie night please") == 0 && qk_try("movie") == 0;
    h_quick(1, "", "both: movie night; lights off");
    nran = 0;
    ok &= qk_try("BOTH") == 1 && nran == 2 && !strcmp(ran[0], "movie night");   // not expanded
    ok &= qk_save("a;b", "x") == -2 && qk_save("", "x") == -2 && qk_save("ok", "   ") == -3;
    ok &= qk_save("this name is far far too long for it", "x") == -2;
    h_quick(1, "", "movie night: tv on");                                  // changed, not added
    ok &= g_qk_count == 2 && !strcmp(am_qk_cmds(0), "tv on");
    for (int i = 0; i < 22; i++) { snprintf(line, sizeof line, "s%d", i); ok &= qk_save(line, "lights on") == 0; }
    ok &= qk_save("one more", "x") == -1 && g_qk_count == 24;
    g_qk_count = 0; qk_load();                                             // a restart
    ok &= g_qk_count == 24 && !strcmp(am_qk_name(1), "both") && !strcmp(am_qk_cmds(1), "movie night; lights off");
    h_quick(3, "", "Both");
    ok &= g_qk_count == 23 && !strcmp(am_qk_name(1), "s0") && saidhas("deleted") && strstr(pref, "both\t") == NULL;
    g_remote_active = 1; nsaid = 0; h_quick(1, "", "x: unlock the door");
    ok &= saidhas("on the device itself") && g_qk_count == 23; g_remote_active = 0;
    bad += t_report("227 shortcuts: made, run by name as each command, saved and read back, deleted", ok);

    // 228. devices: saved every 30 s when the list changes (not when a light's state does),
    //      without Bluetooth bulbs, sensors or pointers; read back at launch with the state
    //      unknown, never twice, and a broken entry skipped
    ok = 1;
    mkdev(0, 7, "10.0.0.5", "Desk strip"); mkdev(1, 5, "AA:BB", "BLE bulb"); mkdev(2, 13, "light.porch", "Porch");
    g_dev_count = 3;
    tick30();
    ok &= saves == 1 && storedlen == 2 * DEV && *(long *)stored == 7 && *(long *)(stored + 32) == 0
        && *(long *)(stored + 16) == -1 && (*(long *)(stored + 8) & 0x100) == 0;
    tick30(); ok &= saves == 1;                                            // nothing new
    *(long *)(dev(0) + 16) = 0; tick30(); ok &= saves == 1;                // a light went off
    strcpy((char *)dev(2) + 112, "Porch light"); tick30(); ok &= saves == 2;   // renamed
    memset(g_devs, 0, sizeof g_devs); g_dev_count = 0;                     // a restart
    dv_load();
    ok &= g_dev_count == 2 && !strcmp((char *)dev(0) + 48, "10.0.0.5") && !strcmp((char *)dev(1) + 112, "Porch light")
        && q(dev(0), 16) == -1 && q(dev(0), 32) == 0 && !strcmp((char *)dev(1) + 224, "Office");
    dv_load(); ok &= g_dev_count == 2;                                     // not twice
    unsigned char *junk = calloc(3, DEV);                                  // broken entries
    *(long *)junk = 99; strcpy((char *)junk + 48, "x");
    *(long *)(junk + DEV) = 7;                                             // no id
    *(long *)(junk + 2 * DEV) = 7; memset(junk + 2 * DEV + 48, 'A', 200);  // no terminators
    free(stored); stored = junk; storedlen = 3 * DEV;
    memset(g_devs, 0, sizeof g_devs); g_dev_count = 0;
    dv_load();
    ok &= g_dev_count == 1 && strlen((char *)dev(0) + 48) == 63 && strlen((char *)dev(0) + 112) == 63;
    bad += t_report("228 devices: saved when the list changes, read back at launch, broken entries refused", ok);

    // 229. forget devices: the saved list goes; what's found later is saved again
    ok = 1; nsaid = 0;
    h_quick(4, "", "");
    ok &= removes == 1 && storedlen == -1 && saidhas("forgotten");
    tick30(); ok &= storedlen == DEV;
    bad += t_report("229 forget devices: cleared, then saved again from what's found", ok);

    for (int i = 0; i < nsaid; i++) printf("  said %s\n", said[i]);
    printf("%ld failed\n", bad);
    return bad != 0;
}
