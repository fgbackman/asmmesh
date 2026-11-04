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
extern long bc_frag_put(void *, long, const void *, const void *, long, void *, long) F(bc_frag_put);
extern long bc_packet_selftest(void) F(bc_packet_selftest) __attribute__((weak));
extern long bc_peer_selftest(void) F(bc_peer_selftest) __attribute__((weak));
extern long term_selftest(void) F(term_selftest) __attribute__((weak));
extern long hue_core_selftest(void) F(hue_core_selftest) __attribute__((weak));
extern long bc_noise_selftest(void) F(bc_noise_selftest) __attribute__((weak));
extern long nf_core_selftest(void) F(nf_core_selftest) __attribute__((weak));
extern long nf_play_selftest(void) F(nf_play_selftest) __attribute__((weak));
extern long ch_core_selftest(void) F(ch_core_selftest) __attribute__((weak));
extern long ch_fen_in(void *, const char *) F(ch_fen_in);
extern unsigned long ch_perft(const void *, long) F(ch_perft);

/* chperft: deeper perft than the self-tests, each against its published count */
static int ch_perft_all(void) {
    static const struct { const char *fen; int depth; unsigned long want; } t[] = {
        { "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 4, 197281 },
        { "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 5, 4865609 },
        { "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 3, 97862 },
        { "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 4, 43238 },
        { "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 5, 674624 },
        { "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 4, 422333 },
        { "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 3, 62379 },
        { "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 3, 89890 },
    };
    unsigned char pos[136];
    int bad = 0;
    for (unsigned i = 0; i < sizeof t / sizeof t[0]; i++) {
        ch_fen_in(pos, t[i].fen);
        unsigned long n = ch_perft(pos, t[i].depth);
        printf("%s  perft %d = %lu (want %lu)  %s\n", n == t[i].want ? "PASS" : "FAIL", t[i].depth, n, t[i].want, t[i].fen);
        bad += n != t[i].want;
    }
    printf("%d failed\n", bad);
    return bad != 0;
}
extern long nf_puzzle(unsigned long, void *) F(nf_puzzle);
extern long nf_find(const void *, const void *, long) F(nf_find);
extern void nf_commit(const void *, unsigned long, long, long, void *) F(nf_commit);
extern void nf_hash(void *) F(nf_hash);
extern long nfp_pkt_start(void *, long, long, long, long, unsigned long, long, long) F(nfp_pkt_start);
extern long nfp_start_in(void *, long, long, const void *, long) F(nfp_start_in);
extern long nfp_player(void *, long, const char *, long) F(nfp_player);
extern long nfp_claim_in(void *, long, const char *, long, const void *, long, long) F(nfp_claim_in);
extern long nfp_pkt_reveal(void *, long, void *) F(nfp_pkt_reveal);
extern long nfp_reveal_in(void *, long, const void *, long) F(nfp_reveal_in);
extern long nfp_tick(void *, long) F(nfp_tick);
extern long nft_status(const void *, long, char *, long) F(nft_status);
extern long nft_board(const void *, const char *, long, char *, long) F(nft_board);
extern long nft_try(const void *, long, long, const char *, long, char *, long) F(nft_try);
extern long nft_result(const void *, long, char *, long) F(nft_result);
extern long nft_mine(const void *, char *, long) F(nft_mine);
extern long nft_players(const void *, char *, long) F(nft_players);
extern const char *nf_word(const void *, long) F(nf_word);

/* _nfp_try answers in x0 and x1 */
static long nfp_try2(void *g, const char *t, long n, long now, void *out, long *pts) {
    register long x0 __asm__("x0") = (long)g, x1 __asm__("x1") = (long)t, x2 __asm__("x2") = n,
        x3 __asm__("x3") = now, x4 __asm__("x4") = (long)out;
    __asm__ volatile("bl _nfp_try" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3), "+r"(x4) :
                     : "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17",
                       "x18", "x30", "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v16", "v17", "v18",
                       "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26", "v27", "v28", "v29", "v30",
                       "v31", "cc", "memory");
    *pts = x1;
    return x0;
}

/* nfdemo: Ann (host) and Bea play one round of two; prints every line the screens show */
static void nf_demo(void) {
    enum { GS = 21664, T = 1000000 };
    unsigned char *a = calloc(1, GS), *b = calloc(1, GS), st[32], cl[32], rv[120];
    char buf[1200], view[10];
    long pts, n, r;
    nfp_pkt_start(st, 0x1234, 1, 2, 120, 0x0123456789abcdefUL, T + 10, 0);
    nfp_start_in(a, 0xA1, 0xA1, st, 31);
    nfp_start_in(b, 0xB2, 0xA1, st, 31);
    nfp_player(a, 0xB2, "Bea", 3);
    nfp_player(b, 0xA1, "Ann", 3);
    nft_status(a, T, buf, sizeof buf); printf("status (Ann, waiting): %s\n", buf);
    memcpy(view, a + 144, 9); view[9] = 0;
    for (r = 0; r < 3; r++) { nft_board(a, view, r, buf, sizeof buf); printf("board: |%s|\n", buf); }
    nfp_tick(a, T + 10); nfp_tick(b, T + 10);
    const char *tries[] = { (char *)a + 154, "zzzz", "abc", "coolness", "loco", "LOCO", "colonics" };
    for (int i = 0; i < 7; i++) {
        long k = nfp_try2(a, tries[i], strlen(tries[i]) > 9 && i == 0 ? 9 : strlen(tries[i]), T + 20 + i, cl, &pts);
        nft_try(a, k, pts, tries[i], strlen(tries[i]), buf, sizeof buf); printf("try %-10s -> %s\n", tries[i], buf);
        if (k >= 0) nfp_claim_in(b, 0xA1, "Ann", 3, cl, 28, T + 21 + i);
    }
    const char *bt[] = { "coil", "loco", "silo" };
    for (int i = 0; i < 3; i++) {
        long k = nfp_try2(b, bt[i], 4, T + 22 + i, cl, &pts);
        if (k >= 0) nfp_claim_in(a, 0xB2, "Bea", 3, cl, 28, T + 23 + i);
    }
    nft_status(a, T + 75, buf, sizeof buf); printf("status (Ann, playing): %s\n", buf);
    nft_mine(a, buf, sizeof buf); printf("Ann's words: %s\n", buf);
    nfp_tick(a, T + 130); nfp_tick(b, T + 130);
    nft_status(a, T + 131, buf, sizeof buf); printf("status (Ann, over): %s\n", buf);
    n = nfp_pkt_reveal(a, 0, rv); nfp_reveal_in(a, 0xA1, rv, n); nfp_reveal_in(b, 0xA1, rv, n);
    n = nfp_pkt_reveal(b, 0, rv); nfp_reveal_in(a, 0xB2, rv, n); nfp_reveal_in(b, 0xB2, rv, n);
    nfp_tick(a, T + 142); nfp_tick(b, T + 142);
    nft_status(a, T + 142, buf, sizeof buf); printf("status (Ann, scored): %s\n", buf);
    for (long k = 0; nft_result(a, k, buf, sizeof buf); k++) printf("result %ld (Ann): %s\n", k, buf);
    for (long k = 0; nft_result(b, k, buf, sizeof buf); k++) printf("result %ld (Bea): %s\n", k, buf);
    nft_players(b, buf, sizeof buf); printf("players (Bea):\n%s", buf);
    free(a); free(b);
}
extern long bc_decode(const void *, long, void *, void *, long) F(bc_decode);
extern long bc_sign_data(const void *, void *, long) F(bc_sign_data);
extern long bc_verify(const void *, const void *, void *, long) F(bc_verify);
extern long bc_would_compress(const void *, long) F(bc_would_compress);
extern long bc_build(const void *, const void *, void *, long) F(bc_build);
extern long bc_seen(void *, long, const void *, long) F(bc_seen);
extern long bc_utf8_ok(const void *, long) F(bc_utf8_ok);
extern long bc_ann_make(const void *, long, const void *, const void *, void *) F(bc_ann_make);
extern long bc_ann_read(const void *, long, void *) F(bc_ann_read);
extern long bc_peer_leave(void *, long, const void *, void *, long, void *) F(bc_peer_leave);
extern long bc_name_skel(void *, const void *, long) F(bc_name_skel);
extern long bc_ed_small(const void *) F(bc_ed_small);
extern long bc_peer_expire(void *, long) F(bc_peer_expire);
extern long bc_msg_read(void *, long, const void *, const void *, void *, long) F(bc_msg_read);
extern long bc_msg_split(const void *, long, long) F(bc_msg_split);
extern long bc_relay_ok(void *, long) F(bc_relay_ok);
extern void bc_text_clean(void *, const void *, long) F(bc_text_clean);

// _bc_peer_heard answers in x0 and x1
static void bc_heard2(void *tab, long now, const void *own, const void *dp, void *scr, long cap, void *pins, long r[2]) {
    register long x0 __asm__("x0") = (long)tab, x1 __asm__("x1") = now, x2 __asm__("x2") = (long)own,
        x3 __asm__("x3") = (long)dp, x4 __asm__("x4") = (long)scr, x5 __asm__("x5") = cap, x6 __asm__("x6") = (long)pins;
    __asm__ volatile("bl _bc_peer_heard" : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3), "+r"(x4), "+r"(x5), "+r"(x6) :
                     : "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17",
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
    setvbuf(stdout, NULL, _IONBF, 0);   /* a crash shows right after the last test that ran */
    if (argc > 1 && !strcmp(argv[1], "selftest")) {
        long f = bc_selftest() + bc_link_selftest() + bc_packet_selftest() + bc_peer_selftest() + term_selftest() + hue_core_selftest() + bc_noise_selftest() + nf_core_selftest() + nf_play_selftest() + ch_core_selftest();
        printf("%ld failed\n", f);
        return f != 0;
    }
    if (argc > 1 && !strcmp(argv[1], "nfdemo")) { nf_demo(); return 0; }
    if (argc > 1 && !strcmp(argv[1], "chperft")) return ch_perft_all();
    static char line[300000];
    unsigned char ctx[208];
    static unsigned char ib[528], fa[8 * 8520], fout[16384], pay[8192], dd[8 + 1000 * 32], bt[32 * 256], pn[32 + 128 * 56];
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
            long r = bc_frag_put(fa, now, A[1], A[2], N[2], fout, N[3] ? A[3][0] : 0);
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
            else printf("%ld", bc_seen(dd, now, &dp, 1));
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
        else if (!strcmp(cmd, "peerreset")) { memset(bt, 0, sizeof bt); memset(pn, 0, sizeof pn); printf("ok"); }
        else if (!strcmp(cmd, "skel")) { long r = bc_name_skel(out, A[0], N[0]); hex(out, r); }
        else if (!strcmp(cmd, "small")) printf("%ld", bc_ed_small(A[0]));
        else if (!strcmp(cmd, "heard")) {
            // heard <now as 8 bytes> <our id> <frame>: slot and new, or the reason; then that slot
            long r[2];
            if (bc_decode(A[2], N[2], &dp, pay, sizeof pay)) { printf("bad"); goto done; }
            bc_heard2(bt, be(A[0], 8), A[1], &dp, out, 4096, pn, r);
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
            else printf("%ld", bc_peer_leave(bt, be(A[0], 8), &dp, out, 4096, pn));
        }
        else if (!strcmp(cmd, "msgread")) {
            // msgread <now as 8 bytes> <our id> <frame>
            if (bc_decode(A[2], N[2], &dp, pay, sizeof pay)) printf("bad");
            else printf("%ld", bc_msg_read(bt, be(A[0], 8), A[1], &dp, out, 4096));
        }
        else if (!strcmp(cmd, "clean")) { bc_text_clean(out, A[0], N[0]); hex(out, N[0]); }
        else if (!strcmp(cmd, "split")) printf("%ld", bc_msg_split(A[0], N[0], A[1][0]));
        else if (!strcmp(cmd, "relayok")) { static unsigned char rl[16]; printf("%ld", bc_relay_ok(rl, be(A[0], 8))); }
        else if (!strcmp(cmd, "nfpuz")) {            /* seed -> word centre tiles n answers tries: indexes */
            static unsigned char p[560];
            if (nf_puzzle(be(A[0], 8), p)) { printf("none"); goto done; }
            printf("%.9s %c %.9s %ld %ld %ld:", p + 10, p[9], p, *(long *)(p + 24), *(long *)(p + 32), *(long *)(p + 40));
            for (long i = 0; i < *(long *)(p + 24); i++) printf(" %d", ((unsigned short *)(p + 48))[i]);
        }
        else if (!strcmp(cmd, "nffind")) {           /* seed text -> index flags (the puzzle from nfpuz) */
            static unsigned char p[560];
            nf_puzzle(be(A[0], 8), p);
            register long x0 __asm__("x0") = (long)p, x1 __asm__("x1") = (long)A[1], x2 __asm__("x2") = N[1];
            __asm__ volatile("bl _nf_find" : "+r"(x0), "+r"(x1), "+r"(x2) :
                             : "x3", "x9", "x10", "x11", "x12", "x13", "x14", "x30", "cc", "memory");
            printf("%ld %ld", x0, x1);
        }
        else if (!strcmp(cmd, "nfcommit")) { nf_commit(A[0], be(A[1], 8), A[2][0], A[3][0], out); hex(out, 16); }
        else if (!strcmp(cmd, "nfhash")) { nf_hash(out); hex(out, 8); }
        else if (!strcmp(cmd, "expire")) printf("%ld", bc_peer_expire(bt, be(A[0], 8)));
        else printf("?");
        done:
        printf("\n");
        fflush(stdout);
    }
    return 0;
}
