# ff.py: Fivefold's words and rules in Python, to make src/ff_words.bin and check
# src/ff_core.s against.
#   python3 ff.py pack <enable1.txt>     writes src/ff_words.bin
#   python3 ff.py score <guess> <word>   the colours: 2 right place, 1 in the word elsewhere, 0 not
# Words: the five-letter answers and also-accepted words of words/answers.txt and extra.txt
# (so no plurals, no contractions, nothing the accuracy rules leave out), the family filter's
# words left out. Hidden words: the answers only, and not a word that is another one with
# -ed or -ing added (ACTED, ADDED, TIRED); those still count as guesses.
# ff_words.bin: "FIVEFOLD", hidden count u32, all count u32; the hidden words (5 bytes
# each) in a fixed shuffled order (the daily word is day mod count); then every word,
# sorted (5 bytes each), for checking guesses.
import os, random, struct, sys, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, '..', '..', 'src', 'ff_words.bin')

def lists(enable_path):
    rd = lambda n: open(os.path.join(HERE, 'words', n)).read().split()
    family = set(rd('family.txt'))
    ans = [w for w in rd('answers.txt') if len(w) == 5 and w not in family]
    ext = [w for w in rd('extra.txt') if len(w) == 5 and w not in family]
    enable = set(open(enable_path).read().split())
    def inflected(w):
        if w.endswith('ed'):
            return w[:-2] in enable or w[:-1] in enable or (len(w) > 3 and w[-3] == w[-4] and w[:-3] in enable)
        if w.endswith('ing'):
            return w[:-3] in enable or w[:-3] + 'e' in enable
        return False
    hidden = [w for w in ans if not inflected(w)]
    random.Random(20261105).shuffle(hidden)        # fixed: the same order in every build
    return hidden, sorted(set(ans) | set(ext))

def pack(hidden, allw):
    out = bytearray(b'FIVEFOLD' + struct.pack('<II', len(hidden), len(allw)))
    for w in hidden: out += w.encode()
    for w in allw: out += w.encode()
    return bytes(out)

def read():
    b = open(BIN, 'rb').read()
    nh, na = struct.unpack_from('<II', b, 8)
    hidden = [b[16 + 5*i:21 + 5*i].decode() for i in range(nh)]
    o = 16 + 5 * nh
    allw = [b[o + 5*i:o + 5 + 5*i].decode() for i in range(na)]
    return hidden, allw

def score(guess, word):
    # right place first, then the rest from what's left of each letter
    out, left = [0] * 5, {}
    for g, w in zip(guess, word):
        if g != w:
            left[w] = left.get(w, 0) + 1
    for i, (g, w) in enumerate(zip(guess, word)):
        if g == w:
            out[i] = 2
        elif left.get(g, 0) > 0:
            out[i] = 1
            left[g] -= 1
    return out

def commit(salt, player, word):
    # a duel's sealed word: SHA-256(salt[16] | player id LE | word)[:16]
    return hashlib.sha256(salt + struct.pack('<Q', player) + word.encode()).digest()[:16]

if __name__ == '__main__':
    if sys.argv[1] == 'pack':
        h, a = lists(sys.argv[2])
        open(BIN, 'wb').write(pack(h, a))
        print('%d hidden words, %d guesses accepted, %d bytes' % (len(h), len(a), 16 + 5 * (len(h) + len(a))))
        print('first days:', ' '.join(h[:8]))
    elif sys.argv[1] == 'score':
        print(''.join(map(str, score(sys.argv[2], sys.argv[3]))))
