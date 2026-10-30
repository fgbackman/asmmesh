// harness.c — drives src/bc_crypto.s, bc_link.s and bc_packet.s under qemu-aarch64 (see run.sh).
//   harness selftest      runs _bc_selftest, as `asmmesh --selftest` does
//   harness < commands    one command per line, hex arguments ("-" = empty), prints hex
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define F(name) __asm__("_" #name)
extern void bc_sha256(const void *, long, void *) F(bc_sha256);
extern void bc_sha512(const void *, long, void *) F(bc_sha512);
extern void bc_sha256_init(void *) F(bc_sha256_init);
extern void bc_sha256_update(void *, const void *, long) F(bc_sha256_update);
extern void bc_sha256_final(void *, void *) F(bc_sha256_final);
extern void bc_sha512_init(void *) F(bc_sha512_init);
extern void bc_sha512_update(void *, const void *, long) F(bc_sha512_update);
extern void bc_sha512_final(void *, void *) F(bc_sha512_final);
extern void bc_hmac256(const void *, long, const void *, long, void *) F(bc_hmac256);
extern long bc_hkdf256(const void *, long, const void *, long, const void *, long, void *, long) F(bc_hkdf256);
extern void bc_chacha20(const void *, const void *, unsigned, const void *, void *, long) F(bc_chacha20);
extern void bc_poly1305(const void *, const void *, long, void *) F(bc_poly1305);
extern void bc_aead_seal(const void *, const void *, const void *, long, const void *, long, void *) F(bc_aead_seal);
extern long bc_aead_open(const void *, const void *, const void *, long, const void *, long, void *) F(bc_aead_open);
extern long bc_x25519(void *, const void *, const void *) F(bc_x25519);
extern long bc_x25519_base(void *, const void *) F(bc_x25519_base);
extern void bc_ed25519_pub(const void *, void *) F(bc_ed25519_pub);
extern void bc_ed25519_sign(const void *, const void *, long, void *) F(bc_ed25519_sign);
extern long bc_ed25519_verify(const void *, const void *, long, const void *) F(bc_ed25519_verify);
extern long bc_selftest(void) F(bc_selftest) __attribute__((weak));
extern long bc_link_selftest(void) F(bc_link_selftest) __attribute__((weak));
extern long bc_frame_len(const void *, long) F(bc_frame_len);
extern long bc_inbox_put(void *, long, const void *, long) F(bc_inbox_put);
extern long bc_frag_put(void *, long, const void *, const void *, long, void *) F(bc_frag_put);
extern long bc_packet_selftest(void) F(bc_packet_selftest) __attribute__((weak));
extern long bc_peer_selftest(void) F(bc_peer_selftest) __attribute__((weak));
extern long bc_decode(const void *, long, void *, void *, long) F(bc_decode);
extern long bc_sign_data(const void *, void *, long) F(bc_sign_data);
extern long bc_verify(const void *, const void *, void *, long) F(bc_verify);
extern long bc_would_compress(const void *, long) F(bc_would_compress);
extern long bc_build(const void *, const void *, void *, long) F(bc_build);
extern long bc_seen(void *, long, const void *) F(bc_seen);
extern long bc_utf8_ok(const void *, long) F(bc_utf8_ok);
extern long bc_ann_make(const void *, long, const void *, const void *, void *) F(bc_ann_make);
extern long bc_ann_read(const void *, long, void *) F(bc_ann_read);
extern long bc_peer_leave(void *, long, const void *, void *, long) F(bc_peer_leave);
extern long bc_peer_expire(void *, long) F(bc_peer_expire);
extern long bc_msg_read(void *, long, const void *, const void *, void *, long) F(bc_msg_read);
extern long bc_msg_split(const void *, long, long) F(bc_msg_split);
extern long bc_relay_ok(void *, long) F(bc_relay_ok);
extern void bc_text_clean(void *, const void *, long) F(bc_text_clean);

// _bc_peer_heard answers in x0 and x1
static void bc_heard2(void *tab, long now, const void *own, const void *dp, void *scr, long cap, long r[2]) {
    register long x0 __asm__("x0") = (long)tab, x1 __asm__("x1") = now, x2 __asm__("x2") = (long)own,
        x3 __asm__("x3") = (long)dp, x4 __asm__("x4") = (long)scr, x5 __asm__("x5") = cap;
    __asm__ volatile("bl _bc_peer_heard" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3), "+r"(x4), "+r"(x5) :
                     : "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17",
                       "x18", "x30", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v16", "v17", "v18",
                       "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30",
                       "v31", "cc", "memory");
    r[0] = x0; r[1] = x1;
}
static long be(const unsigned char *p, int n) { long v = 0; for (int i = 0; i < n; i++) v = v << 8 | p[i]; return v; }

// _bc_relay answers in x0, x1 and x2, which C can't take as one return value
static void bc_relay3(const void *dp, long a, long b, long c, long r[3]) {
    register long x0 __asm__("x0") = (long)dp, x1 __asm__("x1") = a, x2 __asm__("x2") = b, x3 __asm__("x3") = c;
    __asm__ volatile("bl _bc_relay" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3) :
                     : "x9", "x10", "x11", "x12", "x13", "x30", "cc", "memory");
    r[0] = x0; r[1] = x1; r[2] = x2;
}

// a decoded packet, as bc_defs.inc lays it out
typedef struct {
    long ver, type, ttl, ts, flags;
    const unsigned char *sender, *rcpt;
    long hops;
    const unsigned char *route, *pay;
    long plen;
    const unsigned char *sig, *wire;
    long sigat;
} Dp;

// what test.s provides inside the app
long t_report(const char *name, int pass) F(t_report);
long t_report(const char *name, int pass) {
    printf("%s  %s\n", pass ? "PASS" : "FAIL", name);
    return pass ? 0 : 1;
}

static unsigned char A[8][70000];
static long N[8];
static unsigned char out[70000];

static void hex(const unsigned char *p, long n) {
    for (long i = 0; i < n; i++) printf("%02x", p[i]);
    if (n == 0) printf("-");
}

static long unhex(const char *s, unsigned char *p) {
    if (!strcmp(s, "-")) return 0;
    long n = strlen(s) / 2;
    for (long i = 0; i < n; i++) sscanf(s + 2 * i, "%2hhx", &p[i]);
    return n;
}

int main(int argc, char **argv) {
    if (argc > 1 && !strcmp(argv[1], "selftest")) {
        long f = bc_selftest() + bc_link_selftest() + bc_packet_selftest() + bc_peer_selftest();
        printf("%ld failed\n", f);
        return f != 0;
    }
    static char line[300000];
    unsigned char ctx[208];
    static unsigned char ib[528], fa[8 * 8520], fout[16384], pay[8192], dd[8 + 1000 * 32], bt[32 * 256];
    Dp dp;
    while (fgets(line, sizeof line, stdin)) {
        char *cmd = strtok(line, " \n");
        if (!cmd) continue;
        int k = 0;
        char *t;
        while (k < 8 && (t = strtok(NULL, " \n"))) { N[k] = unhex(t, A[k]); k++; }
        if (!strcmp(cmd, "sha256")) { bc_sha256(A[0], N[0], out); hex(out, 32); }
        else if (!strcmp(cmd, "sha512")) { bc_sha512(A[0], N[0], out); hex(out, 64); }
        else if (!strcmp(cmd, "sha256s") || !strcmp(cmd, "sha512s")) {
            // incremental, in pieces of A[1][0] bytes
            int big = cmd[3] == '5';
            long step = A[1][0] ? A[1][0] : 1;
            if (big) bc_sha512_init(ctx); else bc_sha256_init(ctx);
            for (long i = 0; i < N[0]; i += step) {
                long m = N[0] - i < step ? N[0] - i : step;
                if (big) bc_sha512_update(ctx, A[0] + i, m); else bc_sha256_update(ctx, A[0] + i, m);
            }
            if (big) { bc_sha512_final(ctx, out); hex(out, 64); }
            else { bc_sha256_final(ctx, out); hex(out, 32); }
        }
        else if (!strcmp(cmd, "hmac")) { bc_hmac256(A[0], N[0], A[1], N[1], out); hex(out, 32); }
        else if (!strcmp(cmd, "hkdf")) {
            long L = A[3][0] | (A[3][1] << 8);
            long r = bc_hkdf256(A[0], N[0], A[1], N[1], A[2], N[2], out, L);
            if (r) printf("ERR"); else hex(out, L);
        }
        else if (!strcmp(cmd, "chacha")) {
            unsigned c = A[2][0] | A[2][1] << 8 | A[2][2] << 16 | (unsigned)A[2][3] << 24;
            bc_chacha20(A[0], A[1], c, A[3], out, N[3]); hex(out, N[3]);
        }
        else if (!strcmp(cmd, "chachainplace")) {
            unsigned c = A[2][0] | A[2][1] << 8 | A[2][2] << 16 | (unsigned)A[2][3] << 24;
            bc_chacha20(A[0], A[1], c, A[3], A[3], N[3]); hex(A[3], N[3]);
        }
        else if (!strcmp(cmd, "poly")) { bc_poly1305(A[0], A[1], N[1], out); hex(out, 16); }
        else if (!strcmp(cmd, "seal")) { bc_aead_seal(A[0], A[1], A[2], N[2], A[3], N[3], out); hex(out, N[3] + 16); }
        else if (!strcmp(cmd, "open")) {
            long r = bc_aead_open(A[0], A[1], A[2], N[2], A[3], N[3], out);
            if (r < 0) printf("FAIL"); else hex(out, r);
        }
        else if (!strcmp(cmd, "x25519")) { long r = bc_x25519(out, A[0], A[1]); hex(out, 32); printf(" %ld", r); }
        else if (!strcmp(cmd, "x25519b")) { long r = bc_x25519_base(out, A[0]); hex(out, 32); printf(" %ld", r); }
        else if (!strcmp(cmd, "edpub")) { bc_ed25519_pub(A[0], out); hex(out, 32); }
        else if (!strcmp(cmd, "edsign")) { bc_ed25519_sign(A[0], A[1], N[1], out); hex(out, 64); }
        else if (!strcmp(cmd, "edverify")) { printf("%ld", bc_ed25519_verify(A[0], A[1], N[1], A[2])); }
        else if (!strcmp(cmd, "framelen")) printf("%ld", bc_frame_len(A[0], N[0]));
        else if (!strcmp(cmd, "inbox")) {
            // inbox <offset as 2 bytes> <bytes>: prints the result, and the packet when complete
            long r = bc_inbox_put(ib, A[0][0] << 8 | A[0][1], A[1], N[1]);
            printf("%ld", r);
            if (r > 0) { printf(" "); hex(ib + 8, r); }
        }
        else if (!strcmp(cmd, "fragreset")) { memset(fa, 0, sizeof fa); printf("ok"); }
        else if (!strcmp(cmd, "frag")) {
            // frag <now as 4 bytes> <sender 8> <payload>
            long now = (long)A[0][0] << 24 | A[0][1] << 16 | A[0][2] << 8 | A[0][3];
            long r = bc_frag_put(fa, now, A[1], A[2], N[2], fout);
            printf("%ld", r);
            if (r > 0) { printf(" "); hex(fout, r); }
        }
        else if (!strcmp(cmd, "decode")) {
            // decode <frame>: the fields, or -1
            if (bc_decode(A[0], N[0], &dp, pay, sizeof pay)) printf("-1");
            else {
                printf("%ld %ld %ld %lx %ld ", dp.ver, dp.type, dp.ttl, dp.ts, dp.flags);
                hex(dp.sender, 8); printf(" ");
                hex(dp.rcpt, dp.rcpt ? 8 : 0); printf(" %ld ", dp.hops);
                hex(dp.route, dp.hops * 8); printf(" ");
                hex(dp.pay, dp.plen); printf(" ");
                hex(dp.sig, dp.sig ? 64 : 0); printf(" %ld", dp.sigat);
            }
        }
        else if (!strcmp(cmd, "signdata")) {
            long r = bc_decode(A[0], N[0], &dp, pay, sizeof pay);
            if (!r) r = bc_sign_data(&dp, out, 4096);
            if (r < 0) printf("-1"); else hex(out, r);
        }
        else if (!strcmp(cmd, "verify")) {
            // verify <pub> <frame>
            if (bc_decode(A[1], N[1], &dp, pay, sizeof pay)) printf("-1");
            else printf("%ld", bc_verify(&dp, A[0], out, 4096));
        }
        else if (!strcmp(cmd, "wouldc")) printf("%ld", bc_would_compress(A[0], N[0]));
        else if (!strcmp(cmd, "build")) {
            // build <version type ttl time(8)> <sender> <recipient or -> <payload> <seed or ->
            memset(&dp, 0, sizeof dp);
            dp.ver = A[0][0]; dp.type = A[0][1]; dp.ttl = A[0][2];
            for (int i = 0; i < 8; i++) dp.ts = dp.ts << 8 | A[0][3 + i];
            dp.sender = A[1]; dp.rcpt = N[2] ? A[2] : 0; dp.pay = A[3]; dp.plen = N[3];
            long r = bc_build(&dp, N[4] ? A[4] : 0, out, 4096);
            if (r < 0) printf("%ld", r); else hex(out, r);
        }
        else if (!strcmp(cmd, "relay")) {
            // relay <type ttl to-someone sent-by-us to-us links>
            memset(&dp, 0, sizeof dp);
            dp.type = A[0][0]; dp.ttl = A[0][1]; dp.rcpt = A[0][2] ? A[0] : 0;
            long r[3];
            bc_relay3(&dp, A[0][3], A[0][4], A[0][5], r);
            printf("%ld %ld %ld", r[0], r[1], r[2]);
        }
        else if (!strcmp(cmd, "dedupreset")) { memset(dd, 0, sizeof dd); printf("ok"); }
        else if (!strcmp(cmd, "seen")) {
            // seen <now as 4 bytes> <frame>
            long now = (long)A[0][0] << 24 | A[0][1] << 16 | A[0][2] << 8 | A[0][3];
            if (bc_decode(A[1], N[1], &dp, pay, sizeof pay)) printf("-1");
            else printf("%ld", bc_seen(dd, now, &dp));
        }
        else if (!strcmp(cmd, "utf8")) printf("%ld", bc_utf8_ok(A[0], N[0]));
        else if (!strcmp(cmd, "annmake")) {
            // annmake <name> <xpub> <edpub>
            long r = bc_ann_make(A[0], N[0], A[1], A[2], out); hex(out, r);
        }
        else if (!strcmp(cmd, "annread")) {
            // annread <payload>: name, Noise key, signing key, or -1
            const unsigned char *an[4];
            if (bc_ann_read(A[0], N[0], an)) printf("-1");
            else { hex(an[0], (long)an[1]); printf(" "); hex(an[2], 32); printf(" "); hex(an[3], 32); }
        }
        else if (!strcmp(cmd, "peerreset")) { memset(bt, 0, sizeof bt); printf("ok"); }
        else if (!strcmp(cmd, "heard")) {
            // heard <now as 8 bytes> <our id> <frame>: slot and new, or the reason; then that slot
            long r[2];
            if (bc_decode(A[2], N[2], &dp, pay, sizeof pay)) { printf("bad"); goto done; }
            bc_heard2(bt, be(A[0], 8), A[1], &dp, out, 4096, r);
            printf("%ld %ld", r[0], r[1]);
            if (r[0] >= 0) {
                unsigned char *e = bt + r[0] * 256;
                printf(" "); hex(e, 8);
                printf(" %lx %lx %ld ", *(long *)(e + 8), *(long *)(e + 16), *(long *)(e + 24));
                hex(e + 32, 32); printf(" "); hex(e + 64, 32); printf(" "); hex(e + 104, *(long *)(e + 96));
                printf(" %lx", *(long *)(e + 152));
            }
        }
        else if (!strcmp(cmd, "leave")) {
            // leave <now as 8 bytes> <frame>
            if (bc_decode(A[1], N[1], &dp, pay, sizeof pay)) printf("bad");
            else printf("%ld", bc_peer_leave(bt, be(A[0], 8), &dp, out, 4096));
        }
        else if (!strcmp(cmd, "msgread")) {
            // msgread <now as 8 bytes> <our id> <frame>
            if (bc_decode(A[2], N[2], &dp, pay, sizeof pay)) printf("bad");
            else printf("%ld", bc_msg_read(bt, be(A[0], 8), A[1], &dp, out, 4096));
        }
        else if (!strcmp(cmd, "clean")) { bc_text_clean(out, A[0], N[0]); hex(out, N[0]); }
        else if (!strcmp(cmd, "split")) printf("%ld", bc_msg_split(A[0], N[0], A[1][0]));
        else if (!strcmp(cmd, "relayok")) { static unsigned char rl[16]; printf("%ld", bc_relay_ok(rl, be(A[0], 8))); }
        else if (!strcmp(cmd, "expire")) printf("%ld", bc_peer_expire(bt, be(A[0], 8)));
        else printf("?");
        done:
        printf("\n");
        fflush(stdout);
    }
    return 0;
}
