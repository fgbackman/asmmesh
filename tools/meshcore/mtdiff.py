#!/usr/bin/env python3
"""mtdiff.py — random protobufs through src/mt_core.s (via the qemu harness) and mt.py, which
must agree: FromRadio messages read (well-formed, cut short, lengths that lie, varints too long,
unknown fields and wire types) and ToRadio messages through the allowlist (ours, tampered, and
hostile: admin ports, extra or repeated fields). Usage: mtdiff.py harness N"""
import os, random, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mt
from mt import f_varint, f_fixed32, f_bytes, key, varint

harness, n = sys.argv[1], int(sys.argv[2])
rnd = random.Random(11)
def rb(k): return bytes(rnd.getrandbits(8) for _ in range(k))
def h(b): return b.hex() if b else '-'
def text(): return rnd.choice([b'hi', 'héllo'.encode(), b'', rb(rnd.randrange(60)), b'Anna: hey \xe2\x80\xae', b'x' * rnd.randrange(228, 240)])
def junk_field():
    f = rnd.randrange(1, 40)
    return rnd.choice([f_varint(f, rnd.getrandbits(rnd.choice([1, 7, 32, 64]))), f_fixed32(f, rnd.getrandbits(32)),
                       f_bytes(f, rb(rnd.randrange(8))), key(f, 1) + rb(8)])
def shuffle(parts):
    parts = list(parts) + [junk_field() for _ in range(rnd.randrange(3))]
    rnd.shuffle(parts)
    return b''.join(parts)

def data(): return shuffle([f_varint(1, rnd.choice([1, 1, 1, 3, 6, 67])), f_bytes(2, text())])
def packet():
    p = [f_fixed32(1, rnd.getrandbits(32)), f_fixed32(2, rnd.choice([0xFFFFFFFF, rnd.getrandbits(32)])),
         f_fixed32(6, rnd.getrandbits(32))]
    if rnd.random() < .5: p.append(f_varint(3, rnd.randrange(9)))
    p.append(f_bytes(4, data()) if rnd.random() < .85 else f_bytes(5, rb(20)))
    return shuffle(p)
def user(): return shuffle([f_bytes(1, b'!%08x' % rnd.getrandbits(32)), f_bytes(2, text()), f_bytes(3, rb(rnd.randrange(5)))])
def node(): return shuffle([f_varint(1, rnd.getrandbits(32)), f_bytes(2, user()), f_fixed32(5, rnd.getrandbits(32))])
def channel(): return shuffle([f_varint(1, rnd.randrange(8)), f_bytes(2, shuffle([f_bytes(3, text()), f_bytes(2, rb(16))])), f_varint(3, rnd.randrange(3))])

def fromradio():
    k = rnd.choice(['packet', 'my', 'node', 'done', 'chan', 'other', 'junk', 'empty'])
    if k == 'packet': b = f_bytes(2, packet())
    elif k == 'my': b = f_bytes(3, shuffle([f_varint(1, rnd.getrandbits(32))]))
    elif k == 'node': b = f_bytes(4, node())
    elif k == 'done': b = f_varint(7, rnd.getrandbits(32))
    elif k == 'chan': b = f_bytes(10, channel())
    elif k == 'other': b = f_bytes(rnd.choice([5, 9, 11, 13]), rb(rnd.randrange(30)))
    elif k == 'junk': b = rb(rnd.randrange(1, 40))
    else: b = b''
    if rnd.random() < .5: b = f_varint(1, rnd.getrandbits(32)) + b
    r = rnd.random()
    if r < .15 and b: b = b[:rnd.randrange(len(b))]                       # cut short
    elif r < .22 and b: i = rnd.randrange(len(b)); b = b[:i] + bytes([rnd.randrange(256)]) + b[i + 1:]
    elif r < .25: b = b + b'\xff' * 11                                    # a varint too long
    return b

def toradio():
    k = rnd.choice(['cfg', 'hb', 'text', 'dm', 'admin', 'hostile', 'junk'])
    if k == 'cfg': b = mt.want_config(rnd.getrandbits(32))
    elif k == 'hb': b = mt.heartbeat() if rnd.random() < .8 else f_bytes(7, rb(2))
    elif k == 'text': b = mt.send_text(0xFFFFFFFF, rnd.randrange(9), rnd.getrandbits(32), text(), rnd.randrange(2))
    elif k == 'dm': b = mt.send_text(rnd.getrandbits(32), 0, 1, text(), 1)
    elif k == 'admin': b = f_bytes(1, f_fixed32(2, 1) + f_bytes(4, f_varint(1, 6) + f_bytes(2, rb(10))))
    elif k == 'hostile':
        pk = [f_fixed32(2, 1), f_bytes(4, data())]
        pk += rnd.sample([f_fixed32(2, 2), f_varint(9, 3), f_varint(10, 2), f_bytes(16, rb(32)), f_varint(17, 1),
                          f_varint(3, 9), f_fixed32(1, 5)], rnd.randrange(0, 2))
        rnd.shuffle(pk)
        b = f_bytes(1, b''.join(pk))
    else: b = rb(rnd.randrange(1, 30))
    if rnd.random() < .2: b = b + mt.heartbeat()
    if rnd.random() < .1 and b: b = b[:rnd.randrange(1, len(b) + 1)]
    return b

cases = []
for _ in range(n):
    f = fromradio()
    cases.append(('mtparse ' + h(f), mt.show(*mt.parse(f)), 'parse'))
    t = toradio()
    cases.append(('mtallow ' + h(t), str(mt.allowed(t)), 'allowlist'))

out = subprocess.run(['qemu-aarch64', harness], input='\n'.join(c[0] for c in cases) + '\n',
                     capture_output=True, text=True).stdout.split('\n')
if len(out) < len(cases):
    print('the harness answered %d of %d (did it crash?)' % (len(out), len(cases)))
    sys.exit(1)
bad = 0
for (cmd, exp, label), got in zip(cases, out):
    if got != exp:
        bad += 1
        if bad <= 8: print('DIFF %s\n  in   %s\n  asm  %s\n  py   %s' % (label, cmd[:200], got, exp))
allowed = sum(1 for (c, e, l) in cases if l == 'allowlist' and e == '1')
print('%d cases (%d allowed), %d differ' % (len(cases), allowed, bad))
sys.exit(1 if bad else 0)
