// harness.c — drives src/bc_crypto.s under qemu-aarch64 (see run.sh).
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
        long f = bc_selftest();
        printf("%ld failed\n", f);
        return f != 0;
    }
    static char line[300000];
    unsigned char ctx[208];
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
        else printf("?");
        printf("\n");
        fflush(stdout);
    }
    return 0;
}
