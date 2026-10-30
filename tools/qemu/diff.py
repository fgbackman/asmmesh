# diff.py — random cases through the assembly (via the qemu harness), checked
# against Python's `cryptography` and hashlib. Usage: diff.py harness N
import hashlib, hmac, os, random, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bcwire
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

# the link layer (bc_link.s) against bcwire.py, bitchat's format written in Python
def rpacket():
    v = rnd.choice([1, 2])
    route = [rb(8) for _ in range(rnd.randrange(4))] if v == 2 and rnd.random() < .5 else None
    return bcwire.encode(version=v, type=rnd.choice([1, 2, 0x11, 0x20]), sender=rb(8),
                         recipient=rb(8) if rnd.random() < .5 else None, payload=rb(rnd.randrange(400)),
                         signature=rb(64) if rnd.random() < .6 else None, route=route, rsr=rnd.random() < .1)
for i in range(n):
    p = rpacket()
    for cut in [len(p), rnd.randrange(len(p) + 1), rnd.randrange(20)]:
        q = p[:cut]
        cases.append(('framelen ' + h(q), str(bcwire.frame_len_ref(q)), 'frame length'))
    q = bytearray(p); q[rnd.randrange(min(len(q), 30))] = rnd.getrandbits(8); q = bytes(q)
    cases.append(('framelen ' + h(q), str(bcwire.frame_len_ref(q)), 'frame length (changed byte)'))
    q = rb(rnd.randrange(40))
    cases.append(('framelen ' + h(q), str(bcwire.frame_len_ref(q)), 'frame length (noise)'))
    # a long write in random pieces
    if rnd.random() < .5: p = bcwire.pad(p)
    want = bcwire.frame_len_ref(p)
    cuts = sorted(set([0] + [rnd.randrange(1, len(p)) for _ in range(rnd.randrange(4))])) + [len(p)]
    done = False
    for a, b in zip(cuts, cuts[1:]):
        so_far = p[:b]
        fl = bcwire.frame_len_ref(so_far)
        if b > 512: exp = '-1'            # too far in: always dropped
        elif done: exp = '0'              # the rest of a finished (or dropped) write: ignored
        elif fl > 512 or fl < 0: exp = '-1'
        elif fl == 0 or fl > b: exp = '0'
        else: exp = '%d %s' % (b, so_far.hex())
        cases.append(('inbox %04x %s' % (a, h(p[a:b])), exp, 'long write'))
        if exp != '0': done = True
cases.append(('fragreset', 'ok', 'fragments'))
now = 1000
for i in range(n):
    # two senders' sets at once, shuffled, some pieces twice
    sets = []
    for k in range(2):
        p = rpacket(); chunk = rnd.choice([64, 100, 143, 200, 469])
        sender = rb(8); fid = rb(8)
        fr = bcwire.fragments(p, chunk, fid, p[1], sender)
        if len(fr) > 64 or len(p) > 8192: continue
        sets.append((p, sender, [pl for pl, _ in fr]))
    pieces = [(si, j) for si, s3 in enumerate(sets) for j in range(len(s3[2]))]
    pieces += [rnd.choice(pieces) for _ in range(rnd.randrange(3))] if pieces else []
    rnd.shuffle(pieces)
    seen = [set() for _ in sets]
    for si, j in pieces:
        p, sender, pls = sets[si]
        now += rnd.randrange(50)
        if j in seen[si]: exp = '0'
        else:
            seen[si].add(j)
            exp = ('%d %s' % (len(p), p.hex())) if len(seen[si]) == len(pls) else '0'
        cases.append(('frag %08x %s %s' % (now, sender.hex(), pls[j].hex()), exp, 'fragments'))
        if exp != '0': seen[si] = set()   # done: a later repeat starts a new set

# ---- Phase 3: packets, against bcwire.py's copy of bitchat's rules
def fmt(d):
    if d is None: return '-1'
    return '%d %d %d %x %d %s %s %d %s %s %s %d' % (d['v'], d['type'], d['ttl'], d['ts'], d['flags'], h(d['sender']),
        h(d['rcpt']), len(d['route']), h(b''.join(d['route'])), h(d['payload']), h(d['sig']), d['sigat'])
def rtext(k):
    words = [b'hi', b'bitchat', b'mesh', b'the', b'radio', b'asmmesh', b' ', b'\xf0\x9f\x93\xa1']
    out = b''
    while len(out) < k: out += rnd.choice(words)
    return out[:k]
def rpkt():
    v = rnd.choice([1, 1, 2])
    t = rnd.choice([0x01, 0x02, 0x03, 0x10, 0x11, 0x20, 0x21, 0x22, 0x26, 0x29, 0x2c, 0x05, 0x99])
    pay = rtext(rnd.choice([0, 1, 13, 99, 100, 300, 1000, 1500])) if rnd.random() < .7 else rb(rnd.choice([0, 5, 64, 200]))
    kw = dict(version=v, type=t, ttl=rnd.randrange(10), ts=rnd.getrandbits(48), sender=rb(8))
    if rnd.random() < .4: kw['recipient'] = rb(8)
    if v == 2 and rnd.random() < .5: kw['route'] = [rb(8) for _ in range(rnd.randrange(4))]
    if rnd.random() < .3: kw['rsr'] = True
    seed = rb(32) if rnd.random() < .5 else None
    if pay and rnd.random() < .4:
        z = bcwire.raw_deflate(pay, rnd.choice([1, 6, 9]))
        kw['payload'], kw['compressed_orig'] = z, len(pay)
    else:
        kw['payload'] = pay
    if seed:
        unsigned = bcwire.encode(**kw)
        d = bcwire.decode(unsigned)
        if d: kw['signature'] = ed25519.Ed25519PrivateKey.from_private_bytes(seed).sign(bcwire.signing_bytes(d))
    elif rnd.random() < .2: kw['signature'] = rb(64)
    p = bcwire.encode(**kw)
    if v == 2 and not kw.get('route') and rnd.random() < .3:
        # the route flag with no hops: bitchat reads it, and leaves it out of what's signed
        o = 16 + 8 + (8 if 'recipient' in kw else 0)
        p = bytearray(p[:o] + b'\x00' + p[o:]); p[11] |= 8; p = bytes(p)
    return (bcwire.pad(p) if rnd.random() < .5 else p), seed, kw.get('ttl')
def py_verify(d, pub):
    if d is None: return '-1'
    if d['sig'] is None: return '0'
    try:
        ed25519.Ed25519PublicKey.from_public_bytes(pub).verify(d['sig'], bcwire.signing_bytes(d)); return '1'
    except Exception: return '0'
for i in range(n):
    p, seed, _ = rpkt()
    d = bcwire.decode(p)
    cases.append(('decode ' + h(p), fmt(d), 'packet decode'))
    if d: cases.append(('signdata ' + h(p), h(bcwire.signing_bytes(d)) if len(bcwire.signing_bytes(d)) <= 4096 else '-1', 'packet signing bytes'))
    if seed:
        pub = raw(ed25519.Ed25519PrivateKey.from_private_bytes(seed).public_key())
        q = bytearray(p); q[2] = rnd.randrange(8); q[11] |= 0x10 if rnd.random() < .5 else 0; q = bytes(q)
        cases.append(('verify %s %s' % (pub.hex(), h(q)), py_verify(bcwire.decode(q), pub), 'packet verify (relayed)'))
        q = bytearray(p); q[rnd.randrange(len(q))] ^= 1 << rnd.randrange(8); q = bytes(q)
        cases.append(('verify %s %s' % (pub.hex(), h(q)), py_verify(bcwire.decode(q), pub), 'packet verify (changed)'))
    for _ in range(3):
        q = bytearray(p)
        for _ in range(rnd.randrange(1, 4)): q[rnd.randrange(len(q))] = rnd.getrandbits(8)
        q = bytes(q)
        cases.append(('decode ' + h(q), fmt(bcwire.decode(q)), 'packet decode (changed bytes)'))
    q = p[:rnd.randrange(len(p) + 1)]
    cases.append(('decode ' + h(q), fmt(bcwire.decode(q)), 'packet decode (cut short)'))
    q = rb(rnd.randrange(80))
    cases.append(('decode ' + h(q), fmt(bcwire.decode(q)), 'packet decode (noise)'))
    # building
    v, t, ttl, ts = rnd.choice([1, 2]), rnd.choice([0x01, 0x02, 0x11]), rnd.randrange(8), rnd.getrandbits(48)
    sender, rcpt = rb(8), (rb(8) if rnd.random() < .4 else None)
    pay = rtext(rnd.choice([0, 13, 99, 100, 150, 400])) if rnd.random() < .6 else rb(rnd.choice([0, 13, 120, 300]))
    seed = rb(32) if rnd.random() < .7 else None
    want = bcwire.build(v, t, ttl, ts, sender, rcpt, pay, seed)
    want = '-2' if want is None else ('-1' if len(want) > 4096 else want.hex())
    hdr = bytes([v, t, ttl]) + ts.to_bytes(8, 'big')
    cases.append(('build %s %s %s %s %s' % (hdr.hex(), sender.hex(), h(rcpt), h(pay), h(seed)), want, 'packet build'))
    cases.append(('wouldc ' + h(pay), '1' if bcwire.would_compress(pay) else '0', 'would compress'))
    # relaying
    for _ in range(5):
        t = rnd.choice([0x01, 0x02, 0x03, 0x04, 0x10, 0x11, 0x20, 0x21, 0x22, 0x23, 0x26, 0x27, 0x28, 0x29, 0x2c, 0x77])
        a = [t, rnd.randrange(12), rnd.random() < .4, rnd.random() < .1, rnd.random() < .1, rnd.randrange(14)]
        r = bcwire.relay(t, a[1], a[2], a[3], a[4], a[5])
        cases.append(('relay ' + bytes(int(x) for x in a).hex(), '%d %d %d' % r, 'relay rule'))
# the duplicate filter: a stream of packets, some again, time moving on
cases.append(('dedupreset', 'ok', 'duplicate filter'))
pool, seen_at, ring, now = [], {}, [], 1000
for i in range(n * 6):
    if pool and rnd.random() < .4: p = rnd.choice(pool)
    else:
        p, _, _ = rpkt()
        if bcwire.decode(p) is None: continue
        pool.append(p)
    now += rnd.choice([1, 10, 1000, 20000])
    d = bcwire.decode(p); k = bcwire.dedup_key(d)
    live = [e for e in ring if e[0] == k and now - e[1] < 300000]
    if live: exp = '1'
    else:
        exp = '0'; ring.append((k, now))
        if len(ring) > 1000: ring.pop(0)
    cases.append(('seen %08x %s' % (now, h(p)), exp, 'duplicate filter'))

# ---- Milestone 1: announces and the table of bitchat people, against bcwire.Peers
def rutf8(k):
    s = ''.join(rnd.choice(['a', 'Z', ' ', '\'', '\u00e9', '\u2615', '\U0001F4E1', '\u4e2d']) for _ in range(k))
    return s.encode('utf-8')
for i in range(n):
    b = rutf8(rnd.randrange(12)) if rnd.random() < .6 else rb(rnd.randrange(8))
    cases.append(('utf8 ' + h(b), '1' if bcwire.utf8_ok(b) else '0', 'utf-8 check'))
    nick, x, e = rutf8(rnd.randrange(40)), rb(32), rb(32)
    a = bcwire.ann_make(nick, x, e)
    cases.append(('annmake %s %s %s' % (h(nick), x.hex(), e.hex()), a.hex(), 'announce make'))
    q = bytearray(a)
    if rnd.random() < .5:
        for _ in range(rnd.randrange(1, 3)): q[rnd.randrange(len(q))] = rnd.getrandbits(8)
    if rnd.random() < .3: q += bytes([rnd.choice([4, 5, 6, 9, 1]), 2, 1, 2])
    if rnd.random() < .2: q = q[:rnd.randrange(len(q) + 1)]
    r = bcwire.ann_read(bytes(q))
    cases.append(('annread ' + h(bytes(q)), '-1' if r is None else '%s %s %s' % (h(r[0]), r[1].hex(), r[2].hex()), 'announce read'))
# people coming and going: a few identities announcing, sometimes forged, leaving, time passing
T, PN = bcwire.Peers(), bcwire.Pins()
cases.append(('peerreset', 'ok', 'bitchat people'))
own = rb(8)
ids = [(rb(32), rb(32), rutf8(rnd.randrange(1, 50))) for _ in range(40)]
now = 1_760_000_000_000
for i in range(n * 4):
    now += rnd.choice([10, 500, 5000, 30000, 70000])
    xs, es, nick = rnd.choice(ids)
    roll = rnd.random()
    ts = now - rnd.choice([0, 0, 0, 1000, 899000, 901000])
    if roll < .6:
        kw = {}
        if rnd.random() < .1: kw['sign_with'] = rb(32)                 # someone else's key
        if rnd.random() < .05: kw['sign_with'] = False
        if rnd.random() < .05: kw['sender'] = rb(8)
        if rnd.random() < .05: es2 = rb(32); p = bcwire.announce_packet(xs, es2, nick, ts, ttl=rnd.randrange(9))
        else: p = bcwire.announce_packet(xs, es, nick, ts, ttl=rnd.randrange(9), **kw)
        d = bcwire.decode(p)
        k, new = T.heard(now, own, d, PN)
        exp = '%d %d' % (k, new) + ((' ' + T.dump(k)) if k >= 0 else '')
        cases.append(('heard %s %s %s' % (now.to_bytes(8, 'big').hex(), own.hex(), h(p)), exp, 'bitchat people'))
    elif roll < .75:
        from cryptography.hazmat.primitives.asymmetric import x25519
        xpub = raw(x25519.X25519PrivateKey.from_private_bytes(xs).public_key())
        p = bcwire.build(1, 3, 7, ts, bcwire.peer_id(xpub), None, b'', es if rnd.random() < .7 else rb(32))
        cases.append(('leave %s %s' % (now.to_bytes(8, 'big').hex(), h(p)), str(T.leave(now, bcwire.decode(p), PN)), 'bitchat people'))
    else:
        cases.append(('expire ' + now.to_bytes(8, 'big').hex(), str(T.expire(now)), 'bitchat people'))

# ---- Milestone 2: public messages, splitting, the relay limit
for i in range(n * 2):
    now += rnd.choice([10, 1000, 60000])
    xs, es, nick = rnd.choice(ids)
    from cryptography.hazmat.primitives.asymmetric import x25519
    pid = bcwire.peer_id(raw(x25519.X25519PrivateKey.from_private_bytes(xs).public_key()))
    if rnd.random() < .3:                                         # make sure some are known
        p = bcwire.announce_packet(xs, es, nick, now, ttl=7)
        k, new = T.heard(now, own, bcwire.decode(p), PN)
        exp = '%d %d' % (k, new) + ((' ' + T.dump(k)) if k >= 0 else '')
        cases.append(('heard %s %s %s' % (now.to_bytes(8, 'big').hex(), own.hex(), h(p)), exp, 'bitchat people'))
    text = rutf8(rnd.randrange(80)) if rnd.random() < .85 else rb(rnd.randrange(6))
    ts = now - rnd.choice([0, 0, 500, 21599000, 21601000])
    rc = rnd.choice([None, None, None, b'\xff' * 8, rb(8)])
    snd = pid if rnd.random() < .9 else (own if rnd.random() < .5 else rb(8))
    key = es if rnd.random() < .85 else rb(32)
    p = bcwire.build(rnd.choice([1, 1, 2]), rnd.choice([2, 2, 2, 1]), rnd.randrange(8), ts, snd, rc, text, key)
    if p is None: continue
    cases.append(('msgread %s %s %s' % (now.to_bytes(8, 'big').hex(), own.hex(), h(p)),
                  str(bcwire.msg_read(T, now, own, bcwire.decode(p))), 'public message read'))
    b = rutf8(rnd.randrange(150)).replace(b' ', b' ' if rnd.random() < .7 else b'_')
    mx = rnd.choice([96, 96, 20, 7])
    cases.append(('split %s %02x' % (h(b), mx), str(bcwire.msg_split(b, mx)), 'message split'))
R = bcwire.RelayLimit(); t = 1_760_000_000_000
for i in range(n * 3):
    t += rnd.choice([0, 0, 10, 300, 1000])
    cases.append(('relayok ' + t.to_bytes(8, 'big').hex(), str(R.ok(t)), 'relay limit'))

# ---- hardening: cleaning names and messages
tricky = [b'\n', b'\r', b'\x7f', b'\x00', b'\xc2\x85', b'\xe2\x80\xa8', b'\xe2\x80\xae', b'\xe2\x81\xa6',
          b'\xe2\x80\x8f', b'\xe2\x80\xa7', b'\xe2\x80', b'\xc2', b'\xe2\x98\x95', b'ok', b' ']
for i in range(n * 2):
    b = b''.join(rnd.choice(tricky) for _ in range(rnd.randrange(12))) if rnd.random() < .8 else rb(rnd.randrange(20))
    cases.append(('clean ' + h(b), h(bcwire.text_clean(b)), 'text clean'))

# ---- second review: name skeletons, weak keys
looks = ['a', 'A', 'n', 'l', '1', 'I', '!', '|', '0', 'o', ' ', '\u0430', '\u0410', '\u043e', '\u0456', '\u0391',
         '\uff21', '\uff4c', '\u200b', '\u00ad', '\u00a0', '\ufeff', '\u061c', '\u2615', '\u00e9', '\u034f']
for i in range(n * 2):
    b = ''.join(rnd.choice(looks) for _ in range(rnd.randrange(10))).encode() if rnd.random() < .85 else rb(rnd.randrange(12))
    cases.append(('skel ' + h(b), h(bcwire.name_skel(b)), 'name skeleton'))
for e in bcwire.SMALL_ORDER:
    for sign in (0, 0x80):
        k = e[:31] + bytes([e[31] | sign])
        cases.append(('small ' + k.hex(), '1', 'weak key'))
for i in range(n):
    k = rb(32)
    cases.append(('small ' + k.hex(), '1' if bcwire.ed_small(k) else '0', 'weak key'))

inp = '\n'.join(c[0] for c in cases) + '\n'
res = subprocess.run(['qemu-aarch64', harness], input=inp, capture_output=True, text=True).stdout.split('\n')
fails = {}
count = {}
for (cmd, exp, label), got in zip(cases, res):
    count[label] = count.get(label, 0) + 1
    if got.strip() != exp:
        fails.setdefault(label, []).append((cmd[:120], exp[:80], got[:80]))
        if os.environ.get('BCDIFF_DUMP'):                # every failing command in full
            open(os.environ['BCDIFF_DUMP'], 'a').write(cmd + '\n')
if len(res) - 1 < len(cases):
    print('harness stopped after %d of %d cases' % (len(res) - 1, len(cases)))
for label in count:
    print('%-30s %5d cases  %s' % (label, count[label], 'FAIL %d' % len(fails[label]) if label in fails else 'ok'))
for label, f in fails.items():
    for c, e, g in f[:5]:
        print('  %s\n    want %s\n    got  %s' % (c, e, g))
sys.exit(1 if fails or len(res) - 1 < len(cases) else 0)
