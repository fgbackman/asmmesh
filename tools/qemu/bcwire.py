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
