# nf.py: the Python copy of src/nf_core.s (Ninefold's rules), to check the assembly against.
#   python3 nf.py pack                 writes src/nf_words.bin from words/*.txt
#   python3 nf.py puzzle <seed hex>    the puzzle that seed makes (as the app makes it)
#   python3 nf.py stats [N]            N random seeds: words per puzzle, tries needed
# The word table (nf_words.bin): a 16-byte header "NINEFOLD", count (u32 LE), 4 zero bytes;
# then one 10-byte record per word, in alphabetical order: the letters (a-z), zero-padded to
# 9, and a flags byte: 1 answer, 2 also accepted, 4 hidden by the family filter.
import hashlib, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, '..', '..', 'src', 'nf_words.bin')
F_ANSWER, F_EXTRA, F_FAMILY = 1, 2, 4
MIN_ANSWERS, MAX_ANSWERS = 15, 60
TRIES = 4096
MAX_WORDS = 250                        # a word's index in a puzzle is one byte
MASK = (1 << 64) - 1

def load_lists():
    rd = lambda n: open(os.path.join(HERE, 'words', n)).read().split()
    ans, ext, fam = set(rd('answers.txt')), set(rd('extra.txt')), set(rd('family.txt'))
    words = sorted(ans | ext)
    return [(w, (F_ANSWER if w in ans else F_EXTRA) | (F_FAMILY if w in fam else 0)) for w in words]

def pack(table):
    out = bytearray(b'NINEFOLD' + struct.pack('<II', len(table), 0))
    for w, f in table:
        out += w.encode().ljust(9, b'\0') + bytes([f])
    return bytes(out)

def read_bin(path=BIN):
    b = open(path, 'rb').read()
    n = struct.unpack_from('<I', b, 8)[0]
    return [(b[16 + 10*i:16 + 10*i + 9].rstrip(b'\0').decode(), b[16 + 10*i + 9]) for i in range(n)], b

def lists_hash(raw):
    return hashlib.sha256(raw).digest()[:8]

def splitmix(state):
    # returns (new state, value): splitmix64
    state = (state + 0x9E3779B97F4A7C15) & MASK
    z = state
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK
    return state, z ^ (z >> 31)

def fits(w, counts):
    c = list(counts)
    for ch in w:
        k = ord(ch) - 97
        if c[k] == 0:
            return False
        c[k] -= 1
    return True

def counts_of(w):
    c = [0] * 26
    for ch in w:
        c[ord(ch) - 97] += 1
    return c

def is_answer(f):
    return f & F_ANSWER and not f & F_FAMILY

def puzzle(table, seed):
    # -> dict(word, centre, tiles (9 letters, centre at 4), words [table indexes], answers, tries)
    nines = [i for i, (w, f) in enumerate(table) if len(w) == 9 and is_answer(f)]
    state = seed & MASK
    for tries in range(1, TRIES + 1):
        state, r = splitmix(state)
        w = table[nines[r % len(nines)]][0]
        key = sorted(w)
        if any(sorted(table[j][0]) == key for j in nines if table[j][0] != w):
            continue                       # another nine-letter answer has the same letters
        cnt = counts_of(w)
        per = [0] * 26                     # answers each centre letter would leave
        for v, f in table:
            if is_answer(f) and fits(v, cnt):
                seen = 0
                for ch in v:
                    k = ord(ch) - 97
                    if not seen >> k & 1:
                        per[k] += 1
                        seen |= 1 << k
        cands = [k for k in range(26) if cnt[k] and MIN_ANSWERS <= per[k] <= MAX_ANSWERS]
        if not cands:
            continue
        state, r = splitmix(state)
        c = cands[r % len(cands)]
        found = [i for i, (v, f) in enumerate(table) if chr(97 + c) in v and fits(v, cnt)]
        if len(found) > MAX_WORDS:
            continue
        rest = list(w)
        rest.remove(chr(97 + c))
        for i in range(7, 0, -1):          # Fisher-Yates
            state, r = splitmix(state)
            j = r % (i + 1)
            rest[i], rest[j] = rest[j], rest[i]
        tiles = rest[:4] + [chr(97 + c)] + rest[4:]
        return dict(word=w, centre=chr(97 + c), tiles=''.join(tiles), words=found,
                    answers=sum(1 for i in found if is_answer(table[i][1])), tries=tries)
    return None

def points(n):
    return 10 if n == 9 else n - 3

def commit(salt, player, rnd, idx):
    # what CLAIM carries: SHA-256(salt[16] | player id[8] LE | round | word index)[:16].
    # The player's id is in it so nobody can copy someone else's claims and, after seeing
    # their salt at the reveal, pass them off as their own.
    return hashlib.sha256(salt + struct.pack('<QBB', player, rnd, idx)).digest()[:16]

def find(p, table, text):
    # what a typed word is: (index in the puzzle, flags) or (-2 length, -3 no centre letter,
    # -4 not these tiles, -1 not a word we accept, None)
    t = text.lower()
    if not 4 <= len(t) <= 9: return -2, 0
    if not all('a' <= ch <= 'z' for ch in t): return -4, 0
    if p['centre'] not in t: return -3, 0
    if not fits(t, counts_of(p['tiles'])): return -4, 0
    for k, i in enumerate(p['words']):
        if table[i][0] == t: return k, table[i][1]
    return -1, 0

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'pack':
        raw = pack(load_lists())
        open(BIN, 'wb').write(raw)
        print('%d words, %d bytes, lists hash %s' % ((len(raw) - 16) // 10, len(raw), lists_hash(raw).hex()))
    elif cmd == 'puzzle':
        t, raw = read_bin()
        p = puzzle(t, int(sys.argv[2], 16))
        print(p['word'], p['centre'], p['tiles'], len(p['words']), p['answers'], p['tries'])
        print(' '.join(t[i][0] for i in p['words']))
    elif cmd == 'stats':
        import random
        t, raw = read_bin()
        rng = random.Random(1)
        mx = mt = 0
        for _ in range(int(sys.argv[2]) if len(sys.argv) > 2 else 50):
            p = puzzle(t, rng.getrandbits(64))
            mx, mt = max(mx, len(p['words'])), max(mt, p['tries'])
        print('most words in a puzzle %d, most tries %d' % (mx, mt))
