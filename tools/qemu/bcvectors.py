# bcvectors.py — prints, as assembly, the test packets of bc_packet.s's self-tests (155-164);
# with `peer` those of bc_peer.s (165-172), with `msg` its public-message ones (173-175).
# Run it again, and paste over the vectors in the .s file, if bcwire.py changes.
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

def packet_vectors():
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

# ---- bc_peer.s (self-tests 165-172): `bcvectors.py peer`
def peer_vectors():
    X1, E1, E2 = bytes([7] * 32), bytes([8] * 32), bytes([9] * 32)
    nick = "Anna's phone \xe2\x98\x95".encode('latin-1').decode('utf-8').encode('utf-8')
    a1 = w.announce_packet(X1, E1, nick, TS, ttl=6)
    from cryptography.hazmat.primitives.asymmetric import x25519
    xpub = x25519.X25519PrivateKey.from_private_bytes(X1).public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    epub = ed25519.Ed25519PrivateKey.from_private_bytes(E1).public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    bad_sender = w.announce_packet(X1, E1, nick, TS, sender=bytes(8))
    unsigned = w.announce_packet(X1, E1, nick, TS, sign_with=False)
    other_sig = w.announce_packet(X1, E1, nick, TS, sign_with=E2)
    pinned = w.announce_packet(X1, E2, nick, TS)            # same Noise key, another signing key
    pid = w.peer_id(xpub)
    leave = w.build(1, 3, 7, TS + 5, pid, None, b'', E1)
    leave_forged = w.build(1, 3, 7, TS + 5, pid, None, b'', E2)
    ours = w.ann_make(b'asmmesh on the Mac mini, kitchen', SEED_X_PUB, PUB)
    T = w.Peers(); d = w.decode(a1)
    assert T.heard(TS + 1000, bytes(8), d) == (0, 1)
    assert T.heard(TS + 1000, bytes(8), w.decode(bad_sender))[0] == -2
    assert T.heard(TS + 1000, pid, d)[0] == -3
    assert T.heard(TS + w.STALE_MS + 1, bytes(8), d)[0] == -4
    assert T.heard(TS + 1000, bytes(8), w.decode(unsigned))[0] == -5
    assert T.heard(TS + 1000, bytes(8), w.decode(other_sig))[0] == -5
    assert T.heard(TS + 1000, bytes(8), w.decode(pinned))[0] == -6
    assert T.leave(w.decode(leave_forged)) == -1 and T.leave(w.decode(leave)) == 0
    out('Lp_ann1', a1, '167: an announce from "Anna\'s phone ☕", TTL 6')
    out('Lp_bad_sender', bad_sender, '168: the same, from a sender id that isn\'t its key\'s')
    out('Lp_unsigned', unsigned, '168: the same, not signed')
    out('Lp_other_sig', other_sig, '168: the same, signed with another key')
    out('Lp_pinned', pinned, '169: the same Noise key, announcing another signing key')
    out('Lp_leave', leave, '170: Anna leaving, signed')
    out('Lp_leave_forged', leave_forged, '170: a leave for Anna signed with another key')
    out('Lp_ours', ours, '165: our announce payload (name cut to 26 bytes)')
    out('Lp_xpub', xpub, 'Anna\'s Noise key')
    out('Lp_epub', epub, 'Anna\'s signing key')
    out('Lp_id', pid, 'Anna\'s peer id')
    out('Lp_nick', nick, 'Anna\'s name')
    out('Lp_mypub', SEED_X_PUB, 'a stand-in Noise key for us')
    out('Lp_myed', PUB, 'and signing key')
    print('.set PA1_N, %d\n.set PBS_N, %d\n.set PUN_N, %d\n.set POS_N, %d\n.set PPN_N, %d\n.set PLV_N, %d\n.set PLF_N, %d\n.set POURS_N, %d\n.set PNICK_N, %d'
          % (len(a1), len(bad_sender), len(unsigned), len(other_sig), len(pinned), len(leave), len(leave_forged), len(ours), len(nick)))
SEED_X_PUB = bytes(range(0x40, 0x60))

# ---- bc_peer.s public messages (self-tests 173-175): `bcvectors.py msg`
def msg_vectors():
    X1, E1, E2 = bytes([7] * 32), bytes([8] * 32), bytes([9] * 32)
    from cryptography.hazmat.primitives.asymmetric import x25519
    xpub = x25519.X25519PrivateKey.from_private_bytes(X1).public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    pid = w.peer_id(xpub)
    text = 'hi from bitchat \u2615'.encode('utf-8')
    now = TS + 3000
    m_ok = w.build(1, 2, 7, TS + 2000, pid, None, text, E1)
    m_forged = w.build(1, 2, 7, TS + 2000, pid, None, text, E2)
    m_stale = w.build(1, 2, 7, now - w.MSG_STALE_MS - 1, pid, None, text, E1)
    m_utf8 = w.build(1, 2, 7, TS + 2000, pid, None, b'\xc0\xaf', E1)
    m_to = w.build(1, 2, 7, TS + 2000, pid, bytes(range(8)), text, E1)
    m_bcast = w.build(1, 2, 7, TS + 2000, pid, b'\xff' * 8, text, E1)
    T = w.Peers(); T.heard(TS + 1000, bytes(8), w.decode(w.announce_packet(X1, E1,         "Anna's phone \u2615".encode('utf-8'), TS, ttl=6)))
    for pkt, want in ((m_ok, 0), (m_forged, -5), (m_stale, -4), (m_utf8, -7), (m_to, -1), (m_bcast, 0)):
        assert w.msg_read(T, now, bytes(8), w.decode(pkt)) == want, want
    assert w.msg_read(T, now, pid, w.decode(m_ok)) == -3
    assert w.msg_read(w.Peers(), now, bytes(8), w.decode(m_ok)) == -8
    out('Lm_ok', m_ok, '173: Anna says "hi from bitchat \u2615", signed')
    out('Lm_forged', m_forged, '173: the same, signed with another key')
    out('Lm_stale', m_stale, '173: the same, over 6 hours old')
    out('Lm_utf8', m_utf8, '173: not UTF-8')
    out('Lm_to', m_to, '173: addressed to someone')
    out('Lm_bcast', m_bcast, '173: addressed to everyone (ff x 8)')
    out('Lm_text', text, 'what Anna said')
    print('.set MOK_N, %d\n.set MFG_N, %d\n.set MST_N, %d\n.set MU8_N, %d\n.set MTO_N, %d\n.set MBC_N, %d\n.set MTX_N, %d'
          % (len(m_ok), len(m_forged), len(m_stale), len(m_utf8), len(m_to), len(m_bcast), len(text)))

if __name__ == '__main__':
    {'peer': peer_vectors, 'msg': msg_vectors}.get(sys.argv[1] if sys.argv[1:] else '', packet_vectors)()
