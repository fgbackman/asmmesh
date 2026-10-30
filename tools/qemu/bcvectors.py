# bcvectors.py — prints the test packets that bc_packet.s's self-tests (155-164) carry,
# as assembly. Run it again, and paste over the vectors in bc_packet.s, if bcwire.py changes.
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bcwire as w
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

TS = 0x0000019a2f3c4d5e
A, B = bytes(range(0x11, 0x19)), bytes(range(0xa1, 0xa9))
SEED = bytes(range(32))
PUB = ed25519.Ed25519PrivateKey.from_private_bytes(SEED).public_key().public_bytes(
    serialization.Encoding.Raw, serialization.PublicFormat.Raw)

def out(name, b, note):
    print('// %s (%d bytes)' % (note, len(b)))
    print('%s:' % name)
    for i in range(0, len(b), 16):
        print('    .byte ' + ', '.join('0x%02x' % x for x in b[i:i + 16]))

# 155: a public message, padded to 256
v1 = w.build(1, 0x02, 7, TS, A, None, b'hello bitchat')
assert w.decode(v1)['payload'] == b'hello bitchat'
# 156, 158, 159: v2, to someone, a two-hop route, signed; not padded
hops = [bytes([0xc1] * 8), bytes([0xc2] * 8)]
unsigned = w.encode(version=2, type=0x11, ttl=5, ts=TS, sender=A, recipient=B, payload=b'sealed bytes', route=hops)
sig = ed25519.Ed25519PrivateKey.from_private_bytes(SEED).sign(w.signing_bytes(w.decode(unsigned)))
v2 = w.encode(version=2, type=0x11, ttl=5, ts=TS, sender=A, recipient=B, payload=b'sealed bytes', route=hops, signature=sig)
d = w.decode(v2)
assert d['sig'] == sig and len(d['route']) == 2
for k in range(len(v2)): assert w.decode(v2[:k]) is None, k
# 157: compressed, and the same with the wrong size, and an impossible ratio
text = b'bitchat ' * 40
z = w.raw_deflate(text)
v3 = w.encode(version=1, type=0x02, ttl=7, ts=TS, sender=A, payload=z, compressed_orig=len(text))
assert w.decode(v3)['payload'] == text
v3b = w.encode(version=1, type=0x02, ttl=7, ts=TS, sender=A, payload=z, compressed_orig=len(text) + 1)
assert w.decode(v3b) is None
v3c = w.encode(version=1, type=0x02, ttl=7, ts=TS, sender=A, payload=w.raw_deflate(b'x' * 4000)[:3], compressed_orig=4000)
assert w.decode(v3c) is None
# 160: one we build and sign, byte for byte
v4 = w.build(1, 0x02, 7, TS, A, None, b'hi from asmmesh', SEED)
assert w.decode(v4)['sig']

out('Lv_pk1', v1, '155: v1 public message "hello bitchat", padded')
out('Lv_pk2', v2, '156: v2, recipient, route of 2, payload "sealed bytes", signed with Lv_seed')
out('Lv_pk3', v3, '157: v1, "bitchat " x 40 compressed (raw DEFLATE)')
out('Lv_pk3b', v3b, '157: the same, saying 321 bytes')
out('Lv_pk3c', v3c, '157: 4000 bytes from 3: impossible')
out('Lv_pk4', v4, '160: what _bc_build makes for "hi from asmmesh", signed with Lv_seed')
out('Lv_seed', SEED, 'an Ed25519 seed')
out('Lv_pub', PUB, 'its public key')
print('.set PK1_N, %d\n.set PK2_N, %d\n.set PK3_N, %d\n.set PK3B_N, %d\n.set PK3C_N, %d\n.set PK4_N, %d'
      % (len(v1), len(v2), len(v3), len(v3b), len(v3c), len(v4)))
print('// TS %#x, sender %s, recipient %s, text %d bytes, compressed %d' % (TS, A.hex(), B.hex(), len(text), len(z)))
