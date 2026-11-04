# nfdiff.py — checks src/nf_core.s against tools/ninefold/nf.py: puzzles from random seeds
# (word, centre, tiles, every word), typed words (real ones, near misses, junk), commitments
# and the lists' fingerprint. Usage: python3 nfdiff.py <harness> [N]   (run.sh nfdiff N)
import os, random, subprocess, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'ninefold'))
import nf

harness, n = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 200
table, raw = nf.read_bin()
rng = random.Random(9)
cmds, want = [], []
cmds.append('nfhash'); want.append(nf.lists_hash(raw).hex())
for _ in range(n):
    seed = rng.getrandbits(64) if _ else 0x0123456789abcdef
    p = nf.puzzle(table, seed)
    cmds.append('nfpuz %016x' % seed)
    want.append('%s %s %s %d %d %d: %s' % (p['word'], p['centre'], p['tiles'], len(p['words']), p['answers'],
                                         p['tries'], ' '.join(str(i) for i in p['words'])))
    tries = [table[i][0] for i in rng.sample(p['words'], min(4, len(p['words'])))]
    tries += [p['word'].upper(), p['tiles'], p['centre'] * 4, 'abc', 'x' * 10, p['centre'] + 'q1z']
    tries += [''.join(rng.choice(p['tiles']) for _ in range(rng.randint(4, 9))) for _ in range(4)]
    for t in tries:
        k, f = nf.find(p, table, t)
        cmds.append('nffind %016x %s' % (seed, t.encode().hex()))
        want.append('%d %d' % (k, f))
for _ in range(n):
    salt, player, rnd, idx = rng.randbytes(16), rng.getrandbits(64), rng.randrange(256), rng.randrange(256)
    cmds.append('nfcommit %s %016x %02x %02x' % (salt.hex(), player, rnd, idx))
    want.append(nf.commit(salt, player, rnd, idx).hex())
got = subprocess.run(['qemu-aarch64', harness], input='\n'.join(cmds) + '\n', capture_output=True, text=True).stdout.splitlines()
bad = 0
for c, w, g in zip(cmds, want, got + [''] * len(cmds)):
    if w != g:
        bad += 1
        if bad <= 5:
            print('MISMATCH %s\n  want %s\n  got  %s' % (c, w[:300], g[:300]))
print('%d cases, %d mismatches' % (len(cmds), bad))
sys.exit(1 if bad else 0)
