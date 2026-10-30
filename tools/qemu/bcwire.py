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
class Peers:
    def __init__(self): self.t = [None] * PEERS        # dict(id, heard, first, hops, x, e, nick)
    def find(self, i):
        for k, p in enumerate(self.t):
            if p and p['id'] == i: return k
        return -1
    def heard(self, now, own, d):
        # -> (slot, new) or (code, 0): -1 not an announce, -2 id not from its key, -3 us,
        #    -4 stale, -5 signature, -6 a different signing key than before, -9 table full
        #    of people heard in the last 30 s
        if d['type'] != 1: return (-1, 0)
        a = ann_read(d['payload'])
        if a is None: return (-1, 0)
        nick, x, e = a
        if peer_id(x) != d['sender']: return (-2, 0)
        if d['sender'] == own: return (-3, 0)
        if now >= STALE_MS and d['ts'] < now - STALE_MS: return (-4, 0)
        k = self.find(d['sender'])
        if k >= 0 and self.t[k]['e'] != e: return (-6, 0)
        if d['sig'] is None or not ed_ok(e, d['sig'], signing_bytes(d)): return (-5, 0)
        new = 0
        if k < 0:
            new = 1
            free = [j for j, p in enumerate(self.t) if p is None]
            k = free[0] if free else min(range(PEERS), key=lambda j: (self.t[j]['heard'], j))
            if not free and now - self.t[k]['heard'] < FRESH_MS: return (-9, 0)
            self.t[k] = dict(id=d['sender'], first=now)
        p = self.t[k]
        p.update(ts=d['ts'], heard=now, hops=7 - min(d['ttl'], 7), x=x, e=e, nick=text_clean(nick[:utf8_cut(nick, NICK_MAX)]))
        return (k, new)
    def leave(self, now, d):
        # only a fresh leave, later than their last announce, signed with their key
        if d['type'] != 3: return -1
        k = self.find(d['sender'])
        if k < 0: return -1
        if now >= STALE_MS and d['ts'] < now - STALE_MS: return -1
        if d['ts'] < self.t[k]['ts']: return -1
        if d['sig'] is None or not ed_ok(self.t[k]['e'], d['sig'], signing_bytes(d)): return -1
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
MSG_STALE_MS, MSG_MAX, RELAY_PER_S = 6 * 3600 * 1000, 96, 20
def msg_read(T, now, own, d):
    # -> the sender's slot, or -1 not a public message, -3 ours, -4 older than 6 hours,
    #    -5 not signed by them, -7 not UTF-8 / too long, -8 nobody we know
    if d['type'] != 2: return -1
    r = d['rcpt']
    if r is not None and r != b'\xff' * 8: return -1
    if d['sender'] == own: return -3
    if now >= MSG_STALE_MS and d['ts'] < now - MSG_STALE_MS: return -4
    if len(d['payload']) > 65535 or not utf8_ok(d['payload']): return -7
    k = T.find(d['sender'])
    if k < 0: return -8
    if d['sig'] is None or not ed_ok(T.t[k]['e'], d['sig'], signing_bytes(d)): return -5
    return k
def msg_split(b, mx=MSG_MAX):
    # how much of b goes in the first message: all of it if it fits, else up to the last
    # space within mx bytes, else as much as fits between characters
    if len(b) <= mx: return len(b)
    m = utf8_cut(b, mx)
    s = b.rfind(b' ', 0, m)
    return s if s > 0 else (m if m > 0 else mx)
class RelayLimit:
    def __init__(self): self.sec, self.n = -1, 0
    def ok(self, now):
        s = now // 1000
        if s != self.sec: self.sec, self.n = s, 0
        if self.n >= RELAY_PER_S: return 0
        self.n += 1; return 1

# ---- hardening: what a bitchat name or message may not do on our screen
def text_clean(b):
    # control characters (C0, DEL, U+0085), line and paragraph separators (U+2028/9), and
    # direction marks, overrides and isolates (U+200E/F, U+202A-E, U+2066-9) become spaces,
    # byte for byte, so the length stays the same
    out, i = bytearray(b), 0
    while i < len(b):
        c = b[i]
        if c < 0x20 or c == 0x7f: out[i] = 0x20; i += 1; continue
        if c == 0xc2 and i + 1 < len(b) and b[i + 1] == 0x85: out[i:i + 2] = b'  '; i += 2; continue
        if c == 0xe2 and i + 2 < len(b) and ((b[i + 1] == 0x80 and (0xa8 <= b[i + 2] <= 0xae or b[i + 2] in (0x8e, 0x8f)))
                                             or (b[i + 1] == 0x81 and 0xa6 <= b[i + 2] <= 0xa9)):
            out[i:i + 3] = b'   '; i += 3; continue
        i += 1
    return bytes(out)
