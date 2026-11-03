# bcnoise.py — a Python copy of bitchat's Noise (bitchat/Noise/NoiseProtocol.swift,
# NoiseSession.swift, bitchat commit 04995f6): Noise_XX_25519_ChaChaPoly_SHA256, empty
# prologue, empty handshake payloads; transport ciphers put the nonce in front as 4 bytes,
# big-endian, and keep a 1024-message replay window. The reference src/bc_noise.s is
# checked against (tools/qemu/bcvectors.py noise, tools/qemu/diff.py).
import hashlib, hmac
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives import serialization

NAME = b'Noise_XX_25519_ChaChaPoly_SHA256'   # exactly 32 bytes: used as h as it is
RAW = dict(encoding=serialization.Encoding.Raw, format=serialization.PublicFormat.Raw)

# bitchat's validatePublicKey: refused outright (then CryptoKit's own checks)
LOW_ORDER = [bytes(32), bytes([1]) + bytes(31), bytes(31) + bytes([1]),
             bytes.fromhex('e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800'),
             bytes.fromhex('5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157'),
             b'\xff' * 32, b'\xda' + b'\xff' * 31, b'\xdb' + b'\xff' * 31]

def pub(priv32):
    return X25519PrivateKey.from_private_bytes(priv32).public_key().public_bytes(**RAW)

def dh(priv32, pub32):
    return X25519PrivateKey.from_private_bytes(priv32).exchange(X25519PublicKey.from_public_bytes(pub32))

def valid_key(k):
    return len(k) == 32 and k not in LOW_ORDER

def hkdf(ck, ikm, n):
    t = hmac.new(ck, ikm, hashlib.sha256).digest()
    out, prev = [], b''
    for i in range(1, n + 1):
        prev = hmac.new(t, prev + bytes([i]), hashlib.sha256).digest()
        out.append(prev)
    return out

def nonce12(n):
    return bytes(4) + n.to_bytes(8, 'little')

class Handshake:
    def __init__(self, initiator, s_priv):
        self.initiator, self.s, self.spub = initiator, s_priv, pub(s_priv)
        self.h = NAME
        self.ck = NAME
        self.k, self.n = None, 0
        self.mix_hash(b'')                       # the (empty) prologue
        self.step, self.e, self.epub, self.re, self.rs = 0, None, None, None, None

    def mix_hash(self, d):
        self.h = hashlib.sha256(self.h + d).digest()

    def mix_key(self, ikm):
        self.ck, self.k = hkdf(self.ck, ikm, 2)
        self.n = 0

    def enc_hash(self, pt):
        if self.k is None:
            self.mix_hash(pt)
            return pt
        ct = ChaCha20Poly1305(self.k).encrypt(nonce12(self.n), pt, self.h)
        self.n += 1
        self.mix_hash(ct)
        return ct

    def dec_hash(self, ct):
        if self.k is None:
            self.mix_hash(ct)
            return ct
        pt = ChaCha20Poly1305(self.k).decrypt(nonce12(self.n), ct, self.h)   # raises if wrong
        self.n += 1
        self.mix_hash(ct)
        return pt

    # XX:  -> e   <- e, ee, s, es   -> s, se
    def write(self, e_priv=None):
        out = b''
        if self.step == 0:                      # -> e  (initiator)
            self.e, self.epub = e_priv, pub(e_priv)
            out += self.epub; self.mix_hash(self.epub)
        elif self.step == 1:                    # <- e, ee, s, es  (responder)
            self.e, self.epub = e_priv, pub(e_priv)
            out += self.epub; self.mix_hash(self.epub)
            self.mix_key(dh(self.e, self.re))
            out += self.enc_hash(self.spub)
            self.mix_key(dh(self.s, self.re))   # es, responder side: s with re
        else:                                   # -> s, se  (initiator)
            out += self.enc_hash(self.spub)
            self.mix_key(dh(self.s, self.re))   # se, initiator side: s with re
        out += self.enc_hash(b'')               # the empty payload: its tag, once keyed
        self.step += 1
        return out

    def read(self, m):
        if self.step == 0:
            if len(m) != 32 or not valid_key(m): raise ValueError('msg1')
            self.re = m; self.mix_hash(m)
            self.dec_hash(b'')
        elif self.step == 1:
            if len(m) != 96 or not valid_key(m[:32]): raise ValueError('msg2')
            self.re = m[:32]; self.mix_hash(self.re)
            self.mix_key(dh(self.e, self.re))
            rs = self.dec_hash(m[32:80])
            if not valid_key(rs): raise ValueError('rs')
            self.rs = rs
            self.mix_key(dh(self.e, self.rs))   # es, initiator side: e with rs
            self.dec_hash(m[80:])
        else:
            if len(m) != 64: raise ValueError('msg3')
            rs = self.dec_hash(m[:48])
            if not valid_key(rs): raise ValueError('rs')
            self.rs = rs
            self.mix_key(dh(self.e, self.rs))   # se, responder side: e with rs
            self.dec_hash(m[48:])
        self.step += 1

    def split(self):
        k1, k2 = hkdf(self.ck, b'', 2)
        return (Transport(k1), Transport(k2)) if self.initiator else (Transport(k2), Transport(k1))

class Transport:
    WINDOW = 1024
    def __init__(self, k):
        self.k, self.n, self.hi, self.seen = k, 0, 0, set()

    def seal(self, pt):
        if self.n > 0xFFFFFFFE: raise ValueError('nonce')
        ct = ChaCha20Poly1305(self.k).encrypt(nonce12(self.n), pt, b'')
        out = self.n.to_bytes(4, 'big') + ct
        self.n += 1
        return out

    def ok_nonce(self, n):
        if self.hi >= self.WINDOW and n <= self.hi - self.WINDOW: return False
        if n > self.hi: return True
        return n not in self.seen

    def open(self, data):
        if len(data) < 20: raise ValueError('short')
        n = int.from_bytes(data[:4], 'big')
        if not self.ok_nonce(n): raise ValueError('replay')
        pt = ChaCha20Poly1305(self.k).decrypt(nonce12(n), data[4:], b'')
        if n > self.hi: self.hi = n
        self.seen = {x for x in self.seen if x > self.hi - self.WINDOW} | {n}
        return pt

# bitchat's inner payloads (Packets.swift PrivateMessagePacket, BLENoisePayloadFactory)
def private_message(message_id, text):
    mid, t = message_id.encode(), text.encode()
    assert len(mid) <= 255 and len(t) <= 255
    return bytes([0x01, 0x00, len(mid)]) + mid + bytes([0x01, len(t)]) + t

def read_private_message(p):
    if not p or p[0] != 0x01: return None
    mid = text = None
    i, d = 0, p[1:]
    while i + 2 <= len(d):
        t, n = d[i], d[i + 1]
        if t not in (0, 1) or i + 2 + n > len(d): return None
        v = d[i + 2:i + 2 + n]
        if t == 0: mid = v
        else: text = v
        i += 2 + n
    if mid is None or text is None: return None
    return mid, text

def handshake(si, sr, ei, er):
    a, b = Handshake(True, si), Handshake(False, sr)
    m1 = a.write(ei); b.read(m1)
    m2 = b.write(er); a.read(m2)
    m3 = a.write(); b.read(m3)
    assert a.h == b.h and a.rs == pub(sr) and b.rs == pub(si)
    return (m1, m2, m3), a.split(), b.split(), a.h
