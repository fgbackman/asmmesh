#!/usr/bin/env python3
"""mcdiff.py — random cases through src/mc_core.s (via the qemu harness) and tools/meshcore/mc.py,
which must agree: radio frames read (well-formed, cut short, lengths that lie, garbage), the
allowlist, text cleaned for showing, the channel key. Usage: mcdiff.py harness N"""
import os, random, struct, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mc

harness, n = sys.argv[1], int(sys.argv[2])
rnd = random.Random(7)
def rb(k): return bytes(rnd.getrandbits(8) for _ in range(k))
def h(b): return b.hex() if b else '-'

def text():
    pool = [b'hi', 'héllo wörld'.encode(), '😀 ok'.encode(), b'Bob: hey', b'\n\t\x7f', '‮x'.encode(),
            b'\xc0\x80', b'\xe2\x82', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', rb(rnd.randrange(0, 40))]
    return b''.join(rnd.choice(pool) for _ in range(rnd.randrange(0, 6)))

def frame():
    k = rnd.choice([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x0A, 0x0D, 0x10, 0x11,
                    0x12, 0x1B, 0x80, 0x82, 0x83, 0x8A, rnd.randrange(256)])
    t = text()
    if k in (0x03, 0x8A): body = rb(32) + bytes([rnd.randrange(4), 0, 3]) + rb(64) + (b'Anna' + bytes(28) if rnd.random() < .7 else rb(32)) + rb(16)
    elif k == 0x05: body = rb(3) + rb(32) + rb(12) + struct.pack('<I', 915000) + rb(4) + bytes([10, 5]) + t[:32]
    elif k == 0x07: tt = rnd.choice([0, 2]); body = rb(6) + bytes([1, tt]) + rb(4) + (rb(4) if tt == 2 else b'') + t
    elif k == 0x10: tt = rnd.choice([0, 2]); body = rb(3) + rb(6) + bytes([1, tt]) + rb(4) + (rb(4) if tt == 2 else b'') + t
    elif k == 0x08: body = bytes([rnd.randrange(8), 1, 0]) + rb(4) + t
    elif k == 0x11: body = rb(3) + bytes([rnd.randrange(8), 1, 0]) + rb(4) + t
    elif k == 0x12: body = bytes([3]) + b'asmmesh' + bytes(25) + rb(16)
    elif k == 0x1B: p = t[:100]; body = rb(3) + bytes([3, 2]) + b'\xff\xff' + bytes([len(p) if rnd.random() < .8 else rnd.randrange(256)]) + p
    elif k == 0x0D: body = bytes([rnd.choice([1, 2, 3, 9])]) + rb(rnd.randrange(0, 80))
    else: body = rb(rnd.randrange(0, 12))
    f = bytes([k]) + body
    r = rnd.random()
    if r < .2: f = f[:rnd.randrange(1, len(f) + 1)]          # cut short
    elif r < .25: f = f + rb(rnd.randrange(1, 20))            # longer
    return f[:255] or b'\x83'

cases = []
for _ in range(n):
    f = frame()
    k, d = mc.parse(f)
    cases.append(('mcparse ' + h(f), mc.show(k, d), 'parse'))
    a = rnd.choice([mc.app_start(), mc.sync_next(), mc.device_query(), mc.get_contacts(rnd.getrandbits(32)),
                    mc.get_channel(rnd.randrange(9)), mc.set_channel(rnd.randrange(5), b'asmmesh', rb(16) if rnd.random() < .8 else bytes(16)),
                    mc.send_chan_txt(rnd.randrange(3), rnd.getrandbits(32), text()), mc.send_txt(rb(6), 1, text()),
                    mc.send_chan_data(3, rb(rnd.randrange(170)))])
    if rnd.random() < .5:                                      # tampered
        a = bytearray(a); a[rnd.randrange(len(a))] = rnd.randrange(256); a = bytes(a[:rnd.randrange(1, len(a) + 1)] if rnd.random() < .3 else a)
    if rnd.random() < .1: a = rb(rnd.randrange(1, 200))
    slot = rnd.randrange(5)
    cases.append(('mcallow %s %02x' % (h(a), slot), str(mc.allowed(a, slot)), 'allowlist'))
    t, cap = text(), rnd.choice([1, 2, 5, 16, 64, 200])
    cases.append(('mctext %s %02x' % (h(t), cap), h(mc.show_text(t, cap)), 'text'))
    p = rb(rnd.choice([0, 1, 13, 40]))
    cases.append(('mcsecret ' + h(p), mc.chan_secret(p).hex(), 'secret'))

out = subprocess.run(['qemu-aarch64', harness], input='\n'.join(c[0] for c in cases) + '\n',
                     capture_output=True, text=True).stdout.split('\n')
bad = 0
if len(out) < len(cases):
    print('the harness answered %d of %d (did it crash?)' % (len(out), len(cases)))
    sys.exit(1)
for (cmd, exp, label), got in zip(cases, out):
    if got != exp:
        bad += 1
        if bad <= 8: print('DIFF %s\n  in   %s\n  asm  %s\n  py   %s' % (label, cmd[:160], got, exp))
print('%d cases, %d differ' % (len(cases), bad))
sys.exit(1 if bad else 0)
