# bcwire.py — bitchat's wire format (BinaryProtocol.swift), for test vectors
import random
def encode(version=1, type=2, ttl=7, ts=0x0000019a12345678, sender=b'\x11'*8, recipient=None,
           payload=b'', signature=None, route=None, rsr=False, compressed_orig=None):
    flags = 0
    if recipient is not None: flags |= 1
    if signature is not None: flags |= 2
    if compressed_orig is not None: flags |= 4
    if route and version >= 2: flags |= 8
    if rsr: flags |= 0x10
    lf = 4 if version == 2 else 2
    plen = len(payload) + (lf if compressed_orig is not None else 0)
    d = bytes([version, type, ttl]) + ts.to_bytes(8, 'big') + bytes([flags]) + plen.to_bytes(lf, 'big')
    d += sender
    if recipient is not None: d += recipient
    if route and version >= 2: d += bytes([len(route)]) + b''.join(route)
    if compressed_orig is not None: d += compressed_orig.to_bytes(lf, 'big')
    d += payload
    if signature is not None: d += signature
    return d
def pad(d):
    for size in (256, 512, 1024, 2048):
        if len(d) <= size:
            n = size - len(d)
            return d + bytes([n]) * n if 0 < n <= 255 else d
    return d
def frame_len_ref(b):
    # what bc_frame_len should say: total length, 0 = need more, -1 = not bitchat
    if not b: return 0
    v = b[0]
    if v not in (1, 2): return -1
    h = 16 if v == 2 else 14
    if len(b) < h: return 0
    plen = int.from_bytes(b[12:12 + (4 if v == 2 else 2)], 'big')
    if plen > 0x100000: return -1
    fl = b[11]
    t = h + 8 + (8 if fl & 1 else 0)
    if v == 2 and fl & 8:
        if len(b) <= t: return 0
        t += 1 + 8 * b[t]
    return t + plen + (64 if fl & 2 else 0)
def fragments(frame, chunk, fid, otype, sender, recipient=None, version=1, ts=0x0000019a12345678, ttl=7):
    chunks = [frame[i:i + chunk] for i in range(0, len(frame), chunk)]
    out = []
    for i, c in enumerate(chunks):
        pl = fid + i.to_bytes(2, 'big') + len(chunks).to_bytes(2, 'big') + bytes([otype]) + c
        out.append((pl, encode(version=version, type=0x20, ttl=ttl, ts=ts, sender=sender, recipient=recipient, payload=pl)))
    return out

# ---- Phase 3: what BinaryProtocol.decode, toBinaryDataForSigning, RelayController and the
# dedup id do (bitchat 04995f6), as plain Python, for bc_packet.s's vectors and checks
import hashlib, zlib
FRAMED = 1048576 + 18 + 2 * 65535 + 16 + 8 + 8 + 64     # FileTransferLimits.maxFramedFileBytes
def type_cap(t):                                         # PacketPayloadLimits.maxPayloadBytes
    if t in (0x22, 0x11): return FRAMED
    if t in (0x02, 0x25): return 128 * 1024
    if t in (0x04, 0x28): return 64 * 1024
    if t == 0x21: return 8 * 1024
    if t == 0x20: return 1280
    if t in (0x01, 0x2c, 0x03, 0x23, 0x24, 0x29, 0x10, 0x26, 0x27): return 4096
    return 128 * 1024
def raw_deflate(b, level=6):
    c = zlib.compressobj(level, zlib.DEFLATED, -15)
    return c.compress(b) + c.flush()
def inflate_upto(c, n):
    # the stream must end, within n bytes (stricter than Apple's decoder, which stops at n)
    d = zlib.decompressobj(-15)
    try: out = d.decompress(c, n + 1)
    except zlib.error: return None
    return out if d.eof and len(out) <= n else None
def unpad(b):
    if not b: return b
    L = b[-1]
    if L == 0 or L > len(b) or any(x != L for x in b[-L:]): return b
    return b[:-L]
def decode_core(b, bufcap=8192):
    if len(b) < 22 or b[0] not in (1, 2): return None
    v = b[0]; hs = 16 if v == 2 else 14; lf = hs - 12
    if len(b) < hs + 8: return None
    t, ttl, ts, fl = b[1], b[2], int.from_bytes(b[3:11], 'big'), b[11]
    plen = int.from_bytes(b[12:hs], 'big')
    if plen > FRAMED: return None
    o = hs; sender = b[o:o + 8]; o += 8
    rcpt = None
    if fl & 1:
        if len(b) < o + 8: return None
        rcpt = b[o:o + 8]; o += 8
    route = []
    if v == 2 and fl & 8:
        if len(b) < o + 1: return None
        k = b[o]; o += 1
        if len(b) < o + 8 * k: return None
        route = [b[o + 8 * i:o + 8 * i + 8] for i in range(k)]; o += 8 * k
    cap = type_cap(t)
    if fl & 4:
        if plen < lf or len(b) < o + lf: return None
        orig = int.from_bytes(b[o:o + lf], 'big'); o += lf
        if orig > cap or orig > bufcap: return None      # bufcap: asmmesh's own limit
        cs = plen - lf
        if cs <= 0 or len(b) < o + cs or orig > cs * 1032: return None
        pay = inflate_upto(b[o:o + cs], orig)
        if pay is None or orig == 0 or len(pay) != orig: return None
        o += cs
    else:
        if plen > cap or len(b) < o + plen: return None
        pay = b[o:o + plen]; o += plen
    sig = None
    if fl & 2:
        if len(b) < o + 64: return None
        sig = b[o:o + 64]
    return dict(v=v, type=t, ttl=ttl, ts=ts, flags=fl, sender=sender, rcpt=rcpt, route=route,
                payload=pay, sig=sig, wire=b, sigat=o)
def decode(b, bufcap=8192):
    d = decode_core(b, bufcap)
    if d: return d
    u = unpad(b)
    return decode_core(u, bufcap) if len(u) != len(b) else None
def block_pad(d):                                        # MessagePadding.optimalBlockSize + pad
    for size in (256, 512, 1024, 2048):
        if len(d) + 16 <= size:
            n = size - len(d)
            return d + bytes([n]) * n if 0 < n <= 255 else d
    return d
def signing_bytes(d):
    # toBinaryDataForSigning: TTL 0, no signature, no RSR, padded; an empty route drops out
    w = d['wire']; v = d['v']; hs = 16 if v == 2 else 14
    o = hs + 8 + (8 if d['rcpt'] else 0)
    out = bytearray(w[:o]); out[2] = 0
    f = (1 if d['rcpt'] else 0) | (d['flags'] & 4)
    if v == 2 and d['flags'] & 8:
        k = w[o]
        if k: f |= 8; out += w[o:o + 1 + 8 * k]
        o += 1 + 8 * k
    out += w[o:d['sigat']]; out[11] = f
    return block_pad(bytes(out))
def would_compress(p):                                   # CompressionUtil.shouldCompress
    return len(p) >= 100 and len(set(p)) * 10 < 9 * min(len(p), 256)
def build(v, t, ttl, ts, sender, rcpt, payload, seed=None, pad=True):
    from cryptography.hazmat.primitives.asymmetric import ed25519
    if seed is not None and would_compress(payload): return None
    sig = None
    if seed is not None:
        unsigned = encode(version=v, type=t, ttl=0, ts=ts, sender=sender, recipient=rcpt, payload=payload)
        sig = ed25519.Ed25519PrivateKey.from_private_bytes(seed).sign(block_pad(unsigned))
    d = encode(version=v, type=t, ttl=ttl, ts=ts, sender=sender, recipient=rcpt, payload=payload, signature=sig)
    return block_pad(d) if pad else d
def relay(t, ttl, has_rcpt, self_sent, to_self, degree):  # RelayController.decide -> (ttl, lo, hi)
    cap = min(ttl, 7)
    if t == 0x21 or cap <= 1 or self_sent or to_self: return (0, 0, 0)
    if t == 0x10 or (has_rcpt and t in (0x20, 0x11, 0x04, 0x26, 0x27, 0x28)):
        return (cap - 1, 10, 35) if t == 0x10 else (cap - 1, 20, 60)
    if t in (0x20, 0x29):
        lim = min(cap, 5 if degree >= 6 else 7)
        return (lim - 1, 8, 25) if lim > 1 else (0, 0, 0)
    if degree >= 6: lim = max(2, min(cap, 5))
    elif degree <= 2: lim = cap
    else: lim = max(2, min(cap, 7 if t == 0x01 else 6))
    lo, hi = (10, 40) if degree <= 2 else (60, 150) if degree <= 5 else (80, 180) if degree <= 9 else (100, 220)
    return (lim - 1, lo, hi)
def dedup_key(d):                                        # BLEReceivedPacketContext.messageID
    return (d['sender'], d['ts'], d['type'], hashlib.sha256(d['payload']).digest()[:4])

# ---- Milestone 1: announces (AnnouncementPacket in Packets.swift) and who's around
# (BLEAnnouncePreflightPolicy, BLEAnnounceTrustPolicy, handleLeave), for bc_peer.s
STALE_MS, KEEP_MS, PEERS, NICK_MAX, FRESH_MS = 900000, 60000, 32, 47, 30000
def utf8_ok(b):
    try: b.decode('utf-8'); return True
    except UnicodeDecodeError: return False
def utf8_cut(b, mx):
    m = min(len(b), mx)
    while 0 < m < len(b) and b[m] & 0xc0 == 0x80: m -= 1
    return m
def ann_make(nick, xpub, edpub):
    n = nick[:utf8_cut(nick, 26)]        # the packet fits one 182-byte write; never compressed
    return bytes([1, len(n)]) + n + bytes([2, 32]) + xpub + bytes([3, 32]) + edpub
def ann_read(p):
    o, nick, x, e = 0, None, None, None
    while o + 2 <= len(p):
        t, L = p[o], p[o + 1]; o += 2
        if o + L > len(p): return None
        v = p[o:o + L]; o += L
        if t == 1: nick = v if utf8_ok(v) else None
        elif t == 2: x = v
        elif t == 3: e = v
    if nick is None or x is None or e is None or len(x) != 32 or len(e) != 32: return None
    return nick, x, e
def peer_id(xpub): return hashlib.sha256(xpub).digest()[:8]
def ed_ok(pub, sig, msg):
    from cryptography.hazmat.primitives.asymmetric import ed25519
    try: ed25519.Ed25519PublicKey.from_public_bytes(pub).verify(sig, msg); return True
    except Exception: return False
FUTURE_MS, PIN_N, PIN_NEW, PIN_PERIOD = 300000, 128, 6, 60000
SMALL_ORDER = [bytes.fromhex(h) for h in (
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0100000000000000000000000000000000000000000000000000000000000000',
    '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05',
    'c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a',
    'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f')]
def ed_small(pub):
    # an Ed25519 key of small order (or its non-canonical twin): anyone could sign as it
    k = pub[:31] + bytes([pub[31] & 0x7f])
    return any(k == x for x in SMALL_ORDER)
class Rate:
    def __init__(self, mx, period): self.mx, self.period, self.sec, self.n = mx, period, -1, 0
    def ok(self, now):
        s = now // self.period
        if s != self.sec: self.sec, self.n = s, 0
        if self.n >= self.mx: return 0
        self.n += 1; return 1
class Pins:
    # every signing key seen, for good (kept in the Keychain): id -> floor (the time on the
    # latest announce or leave taken), heard (our clock), signing key; the least lately heard
    # goes when it's full; at most 6 new ones a minute
    def __init__(self): self.t = [None] * PIN_N; self.rate = Rate(PIN_NEW, PIN_PERIOD)
    def find(self, i):
        for p in self.t:
            if p and p['id'] == i: return p
        return None
    def note(self, i, e, ts, now):
        p = self.find(i)
        if p is None:
            free = [j for j, q in enumerate(self.t) if q is None]
            j = free[0] if free else min(range(PIN_N), key=lambda j: (self.t[j]['heard'], j))
            p = self.t[j] = dict(id=i, floor=0, e=e)
        p['floor'] = max(p['floor'], ts); p['heard'] = now
class Peers:
    def __init__(self): self.t = [None] * PEERS        # dict(id, heard, first, hops, x, e, nick)
    def find(self, i):
        for k, p in enumerate(self.t):
            if p and p['id'] == i: return k
        return -1
    def heard(self, now, own, d, pins=None):
        # -> (slot, new) or (code, 0): -1 not an announce, -2 id not from its key, -3 us,
        #    -4 stale, from the future, or not later than one taken before, -5 signature or
        #    a weak key, -6 a different signing key than before, -9 table full of people
        #    heard in the last 30 s, -10 too many new people this minute
        if d['type'] != 1: return (-1, 0)
        a = ann_read(d['payload'])
        if a is None: return (-1, 0)
        nick, x, e = a
        if peer_id(x) != d['sender']: return (-2, 0)
        if d['sender'] == own: return (-3, 0)
        if now >= STALE_MS and d['ts'] < now - STALE_MS: return (-4, 0)
        if d['ts'] > now + FUTURE_MS: return (-4, 0)
        if ed_small(e): return (-5, 0)
        k = self.find(d['sender'])
        if k >= 0 and self.t[k]['e'] != e: return (-6, 0)
        pin = pins.find(d['sender']) if pins else None
        if pin and pin['e'] != e: return (-6, 0)
        if pin and d['ts'] <= pin['floor']: return (-4, 0)
        if k >= 0 and d['ts'] < self.t[k]['ts']: return (-4, 0)
        if d['sig'] is None or not ed_ok(e, d['sig'], signing_bytes(d)): return (-5, 0)
        if pins and pin is None and not pins.rate.ok(now): return (-10, 0)
        new = 0
        if k < 0:
            new = 1
            free = [j for j, p in enumerate(self.t) if p is None]
            k = free[0] if free else min(range(PEERS), key=lambda j: (self.t[j]['heard'], j))
            if not free and now - self.t[k]['heard'] < FRESH_MS: return (-9, 0)
            self.t[k] = dict(id=d['sender'], first=now, mts=0)
        p = self.t[k]
        p.update(ts=d['ts'], heard=now, hops=7 - min(d['ttl'], 7), x=x, e=e, nick=text_clean(nick[:utf8_cut(nick, NICK_MAX)]))
        if pins: pins.note(d['sender'], e, d['ts'], now)
        return (k, new)
    def leave(self, now, d, pins=None):
        # only a fresh leave, later than their last announce, signed with their key
        if d['type'] != 3: return -1
        k = self.find(d['sender'])
        if k < 0: return -1
        if now >= STALE_MS and d['ts'] < now - STALE_MS: return -1
        if d['ts'] < self.t[k]['ts']: return -1
        if d['sig'] is None or not ed_ok(self.t[k]['e'], d['sig'], signing_bytes(d)): return -1
        if pins: pins.note(d['sender'], self.t[k]['e'], d['ts'], now)
        self.t[k] = None
        return k
    def expire(self, now):
        gone = 0
        for k, p in enumerate(self.t):
            if p and now >= p['heard'] and now - p['heard'] >= KEEP_MS: self.t[k] = None; gone += 1
        return gone
    def dump(self, k):
        p = self.t[k]
        if p is None: return '-'
        return '%s %x %x %d %s %s %s %x' % (p['id'].hex(), p['heard'], p['first'], p['hops'], p['x'].hex(), p['e'].hex(), p['nick'].hex() or '-', p['ts'])
def announce_packet(xseed, edseed, nick, ts, ttl=7, sender=None, sign_with=None, version=1):
    from cryptography.hazmat.primitives.asymmetric import ed25519, x25519
    from cryptography.hazmat.primitives import serialization as S
    raw = lambda k: k.public_bytes(S.Encoding.Raw, S.PublicFormat.Raw)
    xpub = raw(x25519.X25519PrivateKey.from_private_bytes(xseed).public_key())
    epub = raw(ed25519.Ed25519PrivateKey.from_private_bytes(edseed).public_key())
    pay = ann_make(nick, xpub, epub)
    snd = sender if sender is not None else peer_id(xpub)
    if sign_with is False: return encode(version=version, type=1, ttl=ttl, ts=ts, sender=snd, payload=pay)
    p = build(version, 1, ttl, ts, snd, None, pay, sign_with or edseed)
    return p

# ---- Milestone 2: public messages (BLEPublicMessageHandler, BLEPublicMessagePolicy)
MSG_STALE_MS, MSG_MAX, RELAY_PER_S, MSG_REPLAY_MS = 6 * 3600 * 1000, 96, 20, 300000
def msg_read(T, now, own, d):
    # -> the sender's slot, or -1 not a public message, -3 ours, -4 older than 6 hours,
    #    -5 not signed by them, -7 not UTF-8 / too long, -8 nobody we know
    if d['type'] != 2: return -1
    r = d['rcpt']
    if r is not None and r != b'\xff' * 8: return -1
    if d['sender'] == own: return -3
    if now >= MSG_STALE_MS and d['ts'] < now - MSG_STALE_MS: return -4
    if d['ts'] > now + FUTURE_MS: return -4
    if len(d['payload']) > 65535 or not utf8_ok(d['payload']): return -7
    k = T.find(d['sender'])
    if k < 0: return -8
    if d['ts'] + MSG_REPLAY_MS < T.t[k]['mts']: return -4      # well behind their newest: a replay
    if d['sig'] is None or not ed_ok(T.t[k]['e'], d['sig'], signing_bytes(d)): return -5
    T.t[k]['mts'] = max(T.t[k]['mts'], d['ts'])
    return k
def msg_split(b, mx=MSG_MAX):
    # how much of b goes in the first message: all of it if it fits, else up to the last
    # space within mx bytes, else as much as fits between characters
    if len(b) <= mx: return len(b)
    m = utf8_cut(b, mx)
    s = b.rfind(b' ', 0, m)
    return s if s > 0 else (m if m > 0 else mx)
class RelayLimit(object):
    def __init__(self): self.r = Rate(RELAY_PER_S, 1000)
    def ok(self, now): return self.r.ok(now)

# ---- hardening: what a bitchat name or message may not do on our screen
def text_clean(b):
    # control characters (C0, DEL, C1 including U+0085), line and paragraph separators,
    # direction marks, embeddings, overrides and isolates, and invisible format characters
    # (U+00AD, U+061C, U+180E, U+200B-F, U+2028-E, U+2060-4, U+2066-F, U+FEFF, U+FFF9-B)
    # become spaces, byte for byte, so the length stays the same
    out, i = bytearray(b), 0
    while i < len(b):
        c = b[i]
        if c < 0x20 or c == 0x7f: out[i] = 0x20; i += 1; continue
        if i + 1 < len(b) and ((c == 0xc2 and (0x80 <= b[i + 1] <= 0x9f or b[i + 1] == 0xad))
                               or (c == 0xd8 and b[i + 1] == 0x9c)):
            out[i:i + 2] = b'  '; i += 2; continue
        if i + 2 < len(b) and _blank3(b[i], b[i + 1], b[i + 2]):
            out[i:i + 3] = b'   '; i += 3; continue
        i += 1
    return bytes(out)
BLANK3 = [(0xe2, 0x80, 0x8b, 0x8f), (0xe2, 0x80, 0xa8, 0xae), (0xe2, 0x81, 0xa0, 0xa4),
          (0xe2, 0x81, 0xa6, 0xaf), (0xef, 0xbb, 0xbf, 0xbf), (0xe1, 0xa0, 0x8e, 0x8e), (0xef, 0xbf, 0xb9, 0xbb)]
def _blank3(a, b, c):
    return any(a == x and b == y and lo <= c <= hi for x, y, lo, hi in BLANK3)
# look-alikes: two-byte letters that pass for Latin ones, and fullwidth Latin
HOMO2 = {
    (0xd0, 0xb0): 'a', (0xd0, 0xb2): 'b', (0xd0, 0xb5): 'e', (0xd0, 0xba): 'k', (0xd0, 0xbc): 'm',
    (0xd0, 0xbd): 'h', (0xd0, 0xbe): 'o', (0xd1, 0x80): 'p', (0xd1, 0x81): 'c', (0xd1, 0x82): 't',
    (0xd1, 0x83): 'y', (0xd1, 0x85): 'x', (0xd1, 0x96): 'i', (0xd1, 0x98): 'j', (0xd1, 0x95): 's',
    (0xd0, 0x90): 'a', (0xd0, 0x92): 'b', (0xd0, 0x95): 'e', (0xd0, 0x9a): 'k', (0xd0, 0x9c): 'm',
    (0xd0, 0x9d): 'h', (0xd0, 0x9e): 'o', (0xd0, 0xa0): 'p', (0xd0, 0xa1): 'c', (0xd0, 0xa2): 't',
    (0xd0, 0xa3): 'y', (0xd0, 0xa5): 'x', (0xd0, 0x86): 'i', (0xd0, 0x88): 'j', (0xd0, 0x85): 's',
    (0xce, 0x91): 'a', (0xce, 0x92): 'b', (0xce, 0x95): 'e', (0xce, 0x96): 'z', (0xce, 0x97): 'h',
    (0xce, 0x99): 'i', (0xce, 0x9a): 'k', (0xce, 0x9c): 'm', (0xce, 0x9d): 'n', (0xce, 0x9f): 'o',
    (0xce, 0xa1): 'p', (0xce, 0xa4): 't', (0xce, 0xa5): 'y', (0xce, 0xa7): 'x', (0xce, 0xbf): 'o',
    (0xce, 0xbd): 'v', (0xcf, 0x81): 'p', (0xce, 0xb1): 'a', (0xce, 0xb9): 'i', (0xce, 0xba): 'k',
    (0xcf, 0x85): 'u'}
def name_skel(b):
    # what a name looks like: invisible and blank characters gone, look-alikes as the Latin
    # letter, case folded, and 0 as o, 1 l | ! as i
    out, i = bytearray(), 0
    while i < len(b):
        c = b[i]
        if c <= 0x20 or c == 0x7f: i += 1; continue
        if c < 0x80:
            ch = chr(c).lower()
            ch = {'0': 'o', '1': 'i', 'l': 'i', '|': 'i', '!': 'i'}.get(ch, ch)
            out += ch.encode(); i += 1; continue
        if i + 1 < len(b):
            if (c == 0xc2 and (0x80 <= b[i + 1] <= 0x9f or b[i + 1] in (0xa0, 0xad))) or (c == 0xd8 and b[i + 1] == 0x9c) \
               or (c == 0xcd and b[i + 1] == 0x8f):
                i += 2; continue
            m = HOMO2.get((c, b[i + 1]))
            if m:
                m = {'l': 'i'}.get(m, m); out += m.encode(); i += 2; continue
        if i + 2 < len(b):
            if _blank3(c, b[i + 1], b[i + 2]): i += 3; continue
            if c == 0xef and b[i + 1] == 0xbc and 0xa1 <= b[i + 2] <= 0xba:      # A-Z fullwidth
                out += chr(b[i + 2] - 0xa1 + 0x61).encode(); i += 3; continue
            if c == 0xef and b[i + 1] == 0xbd and 0x81 <= b[i + 2] <= 0x9a:      # a-z fullwidth
                out += chr(b[i + 2] - 0x81 + 0x61).replace('l', 'i').encode(); i += 3; continue
        out.append(c); i += 1
    return bytes(out)
def names_same(a, b): return name_skel(a) == name_skel(b)
