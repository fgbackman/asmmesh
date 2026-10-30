// inflate.c — raw DEFLATE (RFC 1951) for the qemu harness. It stands in for libz's inflate,
// which src/bc_zlib.s calls on the Mac and iPhone (libz isn't built for Linux on ARM64 here).
// Same contract: the stream must end properly within dcap bytes; returns how many bytes it
// made, or -1 if it's broken, runs out first, or wants more than dcap.
#include <string.h>

typedef struct { const unsigned char *in; long n, pos; unsigned bits, nb; } St;
typedef struct { short count[16], sym[320]; } Huff;

static int bits(St *s, int need, int *ok) {
    unsigned v = s->bits;
    while (s->nb < (unsigned)need) {
        if (s->pos >= s->n) { *ok = 0; return 0; }
        v |= (unsigned)s->in[s->pos++] << s->nb;
        s->nb += 8;
    }
    s->bits = v >> need;
    s->nb -= need;
    return (int)(v & ((1u << need) - 1));
}

// canonical Huffman code from code lengths. 0 if libz would refuse it: over-subscribed, or
// incomplete (allowed only for a single 1-bit code, and never for the code-length code)
static int build(Huff *h, const short *len, int n, int lengths_code) {
    short offs[16];
    memset(h->count, 0, sizeof h->count);
    for (int i = 0; i < n; i++) h->count[len[i]]++;
    if (h->count[0] == n) return !lengths_code;
    int left = 1, max = 0;
    for (int l = 1; l < 16; l++) {
        left <<= 1; left -= h->count[l];
        if (left < 0) return 0;
        if (h->count[l]) max = l;
    }
    offs[1] = 0;
    for (int l = 1; l < 15; l++) offs[l + 1] = offs[l] + h->count[l];
    for (int i = 0; i < n; i++) if (len[i]) h->sym[offs[len[i]]++] = i;
    return !(left > 0 && (lengths_code || max != 1));
}

static int decode(St *s, const Huff *h, int *ok) {
    int code = 0, first = 0, index = 0;
    for (int l = 1; l < 16; l++) {
        code |= bits(s, 1, ok);
        if (!*ok) return -1;
        int c = h->count[l];
        if (code - c < first) return h->sym[index + (code - first)];
        index += c; first += c; first <<= 1; code <<= 1;
    }
    *ok = 0;
    return -1;
}

static const short lbase[29] = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
static const short lext[29] = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
static const short dbase[30] = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
static const short dext[30] = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};

// 1: block done, -1: broken, or more than cap
static int codes(St *s, unsigned char *d, long cap, long *o, const Huff *lc, const Huff *dc) {
    int ok = 1;
    for (;;) {
        int sym = decode(s, lc, &ok);
        if (!ok || sym < 0) return -1;
        if (sym < 256) { if (*o >= cap) return -1; d[(*o)++] = sym; continue; }
        if (sym == 256) return 1;
        sym -= 257;
        if (sym >= 29) return -1;
        int len = lbase[sym] + bits(s, lext[sym], &ok);
        int ds = decode(s, dc, &ok);
        if (!ok || ds < 0 || ds >= 30) return -1;
        long dist = dbase[ds] + bits(s, dext[ds], &ok);
        if (!ok || dist > *o) return -1;
        while (len--) { if (*o >= cap) return -1; d[*o] = d[*o - dist]; (*o)++; }
    }
}

long bc_inflate(unsigned char *dst, long dcap, const unsigned char *src, long slen) __asm__("_bc_inflate");
long bc_inflate(unsigned char *dst, long dcap, const unsigned char *src, long slen) {
    St s = { src, slen, 0, 0, 0 };
    long o = 0;
    int last, ok = 1;
    do {
        last = bits(&s, 1, &ok);
        int type = bits(&s, 2, &ok);
        if (!ok) return -1;
        int r;
        if (type == 0) {
            s.bits = 0; s.nb = 0;
            if (s.pos + 4 > s.n) return -1;
            unsigned len = s.in[s.pos] | s.in[s.pos + 1] << 8, nlen = s.in[s.pos + 2] | s.in[s.pos + 3] << 8;
            s.pos += 4;
            if (len != (~nlen & 0xffff)) return -1;
            r = 1;
            while (len--) {
                if (o >= dcap) return -1;
                if (s.pos >= s.n) return -1;
                dst[o++] = s.in[s.pos++];
            }
        } else if (type == 1) {
            static Huff lc, dc;
            static int made;
            if (!made) {
                short l[320];
                int i = 0;
                for (; i < 144; i++) l[i] = 8;
                for (; i < 256; i++) l[i] = 9;
                for (; i < 280; i++) l[i] = 7;
                for (; i < 288; i++) l[i] = 8;
                build(&lc, l, 288, 0);
                for (i = 0; i < 30; i++) l[i] = 5;
                build(&dc, l, 30, 0);
                made = 1;
            }
            r = codes(&s, dst, dcap, &o, &lc, &dc);
        } else if (type == 2) {
            static const short order[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};
            short l[320] = {0};
            Huff lc, dc, cc;
            int nlen = bits(&s, 5, &ok) + 257, ndist = bits(&s, 5, &ok) + 1, ncode = bits(&s, 4, &ok) + 4;
            if (!ok || nlen > 286 || ndist > 30) return -1;
            for (int i = 0; i < ncode; i++) l[order[i]] = bits(&s, 3, &ok);
            if (!ok || !build(&cc, l, 19, 1)) return -1;
            int i = 0;
            while (i < nlen + ndist) {
                int sym = decode(&s, &cc, &ok);
                if (!ok || sym < 0) return -1;
                if (sym < 16) { l[i++] = sym; continue; }
                int prev = 0, rep;
                if (sym == 16) { if (i == 0) return -1; prev = l[i - 1]; rep = 3 + bits(&s, 2, &ok); }
                else if (sym == 17) rep = 3 + bits(&s, 3, &ok);
                else rep = 11 + bits(&s, 7, &ok);
                if (!ok || i + rep > nlen + ndist) return -1;
                while (rep--) l[i++] = prev;
            }
            if (l[256] == 0) return -1;
            if (!build(&lc, l, nlen, 0) || !build(&dc, l + nlen, ndist, 0)) return -1;
            r = codes(&s, dst, dcap, &o, &lc, &dc);
        } else return -1;
        if (r < 0) return -1;
    } while (!last);
    return o;
}
