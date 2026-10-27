# diff.py — random cases through the assembly (via the qemu harness), checked
# against Python's `cryptography` and hashlib. Usage: diff.py harness N
import hashlib, hmac, os, random, subprocess, sys
from cryptography.hazmat.primitives.asymmetric import ed25519, x25519
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes, poly1305, serialization

harness, n = sys.argv[1], int(sys.argv[2])
rnd = random.Random(1)
def rb(k): return bytes(rnd.getrandbits(8) for _ in range(k))
def h(b): return b.hex() if b else '-'
def rlen(): return rnd.choice([0, 1, 15, 16, 17, 55, 56, 63, 64, 65, 111, 112, 127, 128, 129, 200, 1000, rnd.randrange(3000)])
raw = lambda k: k.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)

cases = []  # (command line, expected output, label)
for i in range(n):
    m = rb(rlen())
    cases.append(('sha256 ' + h(m), hashlib.sha256(m).hexdigest(), 'sha256'))
    cases.append(('sha512 ' + h(m), hashlib.sha512(m).hexdigest(), 'sha512'))
    step = rnd.choice([1, 3, 63, 64, 65, 127, 128, 129, 200])
    cases.append(('sha256s %s %02x' % (h(m), step), hashlib.sha256(m).hexdigest(), 'sha256 pieces'))
    cases.append(('sha512s %s %02x' % (h(m), step), hashlib.sha512(m).hexdigest(), 'sha512 pieces'))
    key = rb(rnd.choice([0, 1, 32, 64, 65, 131]))
    cases.append(('hmac %s %s' % (h(key), h(m)), hmac.new(key, m, hashlib.sha256).hexdigest(), 'hmac'))
    salt, ikm, info = rb(rnd.choice([0, 13, 32, 80])), rb(rnd.choice([1, 22, 32, 80])), rb(rnd.choice([0, 10, 80]))
    L = rnd.choice([1, 31, 32, 33, 42, 64, 82, 255, 8160])
    exp = HKDF(hashes.SHA256(), L, salt if salt else None, info).derive(ikm).hex()
    cases.append(('hkdf %s %s %s %02x%02x' % (h(salt), h(ikm), h(info), L & 255, L >> 8), exp, 'hkdf'))
    k, nonce, ctr = rb(32), rb(12), rnd.choice([0, 1, 7, 0xfffffffe, rnd.getrandbits(31)])
    blocks = (len(m) + 63) // 64
    if ctr + blocks <= 2**32:
        enc = Cipher(algorithms.ChaCha20(k, ctr.to_bytes(4, 'little') + nonce), None).encryptor().update(m)
        cases.append(('chacha %s %s %s %s' % (k.hex(), nonce.hex(), ctr.to_bytes(4, 'little').hex(), h(m)), h(enc), 'chacha20'))
        cases.append(('chachainplace %s %s %s %s' % (k.hex(), nonce.hex(), ctr.to_bytes(4, 'little').hex(), h(m)), h(enc), 'chacha20 in place'))
    pk = rb(32)
    cases.append(('poly %s %s' % (pk.hex(), h(m)), poly1305.Poly1305.generate_tag(pk, m).hex(), 'poly1305'))
    ad = rb(rnd.choice([0, 1, 12, 16, 17, 100]))
    ct = ChaCha20Poly1305(k).encrypt(nonce, m, ad if ad else None)
    cases.append(('seal %s %s %s %s' % (k.hex(), nonce.hex(), h(ad), h(m)), ct.hex(), 'aead seal'))
    cases.append(('open %s %s %s %s' % (k.hex(), nonce.hex(), h(ad), ct.hex()), h(m), 'aead open'))
    bad = bytearray(ct); bad[rnd.randrange(len(bad))] ^= 1 << rnd.randrange(8)
    cases.append(('open %s %s %s %s' % (k.hex(), nonce.hex(), h(ad), bytes(bad).hex()), 'FAIL', 'aead open (changed)'))
    a, b = x25519.X25519PrivateKey.from_private_bytes(rb(32)), x25519.X25519PrivateKey.from_private_bytes(rb(32))
    ab = a.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    cases.append(('x25519b ' + ab.hex(), raw(a.public_key()).hex() + ' 0', 'x25519 public'))
    cases.append(('x25519 %s %s' % (ab.hex(), raw(b.public_key()).hex()), a.exchange(b.public_key()).hex() + ' 0', 'x25519 shared'))
    seed = rb(32)
    sk = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
    pub = raw(sk.public_key())
    sig = sk.sign(m)
    cases.append(('edpub ' + seed.hex(), pub.hex(), 'ed25519 public'))
    cases.append(('edsign %s %s' % (seed.hex(), h(m)), sig.hex(), 'ed25519 sign'))
    cases.append(('edverify %s %s %s' % (pub.hex(), h(m), sig.hex()), '1', 'ed25519 verify'))
    bad = bytearray(sig); bad[rnd.randrange(64)] ^= 1 << rnd.randrange(8)
    cases.append(('edverify %s %s %s' % (pub.hex(), h(m), bytes(bad).hex()), '0', 'ed25519 verify (changed sig)'))
    if m:
        bm = bytearray(m); bm[rnd.randrange(len(bm))] ^= 1
        cases.append(('edverify %s %s %s' % (pub.hex(), h(bytes(bm)), sig.hex()), '0', 'ed25519 verify (changed msg)'))

# edge cases random inputs rarely reach
P = 2**255 - 19
def x25519_ref(k, u):
    k = bytearray(k); k[0] &= 248; k[31] &= 127; k[31] |= 64
    k = int.from_bytes(k, 'little'); u = (int.from_bytes(u, 'little') & (2**255 - 1)) % P
    x1, x2, z2, x3, z3, swap = u, 1, 0, u, 1, 0
    for t in range(254, -1, -1):
        kt = (k >> t) & 1; swap ^= kt
        if swap: x2, x3, z2, z3 = x3, x2, z3, z2
        swap = kt
        A = x2 + z2; AA = A * A; B = x2 - z2; BB = B * B; E = AA - BB
        C = x3 + z3; D = x3 - z3; DA = D * A; CB = C * B
        x3 = (DA + CB) ** 2 % P; z3 = x1 * (DA - CB) ** 2 % P
        x2 = AA * BB % P; z2 = E * (AA + 121665 * E) % P
    if swap: x2, x3, z2, z3 = x3, x2, z3, z2
    r = x2 * pow(z2, P - 2, P) % P
    return r.to_bytes(32, 'little').hex() + (' -1' if r == 0 else ' 0')
for uval in [0, 1, P - 1, P, P + 1, 2**255 - 1, 2**255, 2**256 - 1, 325606250916557431795983626356110631294008115727848805560023387167927233504,
             39382357235489614581723060781553021112529911719440698176882885853963445705823]:
    k = rb(32); u = uval.to_bytes(32, 'little')
    cases.append(('x25519 %s %s' % (k.hex(), u.hex()), x25519_ref(k, u), 'x25519 edge u'))
r2 = (2).to_bytes(16, 'little'); r1 = (1).to_bytes(16, 'little'); z = bytes(16); ff = b'\xff' * 16
for key, msg in [(r2 + z, ff), (r2 + ff, (2).to_bytes(16, 'little')), (r1 + z, ff + b'\xf0' + b'\xff' * 15 + b'\x11' + bytes(15)),
                 (r1 + z, ff + b'\xfb' + b'\xfe' * 15 + b'\x01' * 16), (r2 + z, b'\xfd' + b'\xff' * 15), (ff + ff, ff * 9 + b'\xff'),
                 (rb(32), ff * 33)]:
    cases.append(('poly %s %s' % (key.hex(), msg.hex()), poly1305.Poly1305.generate_tag(key, msg).hex(), 'poly1305 edge'))
L = 2**252 + 27742317777372353535851937790883648493
for i in range(4):
    seed = rb(32); sk = ed25519.Ed25519PrivateKey.from_private_bytes(seed); pub = raw(sk.public_key()); m = rb(20)
    sig = sk.sign(m); S = int.from_bytes(sig[32:], 'little')
    cases.append(('edverify %s %s %s' % (pub.hex(), m.hex(), (sig[:32] + (S + L).to_bytes(32, 'little')).hex()), '0', 'ed25519 S+L refused'))
    y = int.from_bytes(pub, 'little') & (2**255 - 1)
    if y < 19:
        pass
    bigy = ((P + 1).to_bytes(32, 'little'))
    cases.append(('edverify %s %s %s' % (bigy.hex(), m.hex(), sig.hex()), '0', 'ed25519 y >= p refused'))
    # a y with no x on the curve
    while True:
        yy = rnd.randrange(P); u = (yy * yy - 1) % P
        d = (-121665 * pow(121666, P - 2, P)) % P
        v = (d * yy * yy + 1) % P
        x2 = u * pow(v, P - 2, P) % P
        if pow(x2, (P - 1) // 2, P) == P - 1: break
    cases.append(('edverify %s %s %s' % (yy.to_bytes(32, 'little').hex(), m.hex(), sig.hex()), '0', 'ed25519 not a point'))
cases.append(('edverify %s %s %s' % ('01' + '00' * 31, '-', '00' * 64), '0', 'ed25519 identity key, zero sig'))

inp = '\n'.join(c[0] for c in cases) + '\n'
res = subprocess.run(['qemu-aarch64', harness], input=inp, capture_output=True, text=True).stdout.split('\n')
fails = {}
count = {}
for (cmd, exp, label), got in zip(cases, res):
    count[label] = count.get(label, 0) + 1
    if got.strip() != exp:
        fails.setdefault(label, []).append((cmd[:120], exp[:80], got[:80]))
if len(res) - 1 < len(cases):
    print('harness stopped after %d of %d cases' % (len(res) - 1, len(cases)))
for label in count:
    print('%-30s %5d cases  %s' % (label, count[label], 'FAIL %d' % len(fails[label]) if label in fails else 'ok'))
for label, f in fails.items():
    for c, e, g in f[:2]:
        print('  %s\n    want %s\n    got  %s' % (c, e, g))
sys.exit(1 if fails or len(res) - 1 < len(cases) else 0)
