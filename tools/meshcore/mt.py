#!/usr/bin/env python3
"""mt.py — the Python copy of src/mt_core.s: what asmmesh sends a Meshtastic radio over Bluetooth
(ToRadio protobufs, built here), the allowlist every one passes, and what the radio sends back
(FromRadio, read here). Protobuf by hand, the few fields used, from Meshtastic's published field
numbers (meshtastic/protobufs 85f3f43, mesh.proto, channel.proto, portnums.proto). No Meshtastic
code is used (theirs is GPL-3); this is written from the format. mtdiff.py checks the assembly
against it:  python3 tools/meshcore/mt.py vectors
"""
import struct, sys

FRAME_MAX = 512                 # MAX_TO_FROM_RADIO_SIZE
TEXT_MAX = 200                  # bytes of text we send (a Data payload holds 233)
BROADCAST = 0xFFFFFFFF
PORT_TEXT = 1                   # TEXT_MESSAGE_APP (ADMIN_APP is 6: never)

# --- protobuf, by hand ---------------------------------------------------------------------

def varint(v):
    v &= (1 << 64) - 1
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)

def key(field, wt): return varint(field << 3 | wt)
def f_varint(field, v): return key(field, 0) + varint(v)
def f_fixed32(field, v): return key(field, 5) + struct.pack('<I', v & 0xFFFFFFFF)
def f_bytes(field, b): return key(field, 2) + varint(len(b)) + b

def read_varint(b, i, end):
    """-> (value, next) or None (runs off the end, or longer than 10 bytes)"""
    v, s = 0, 0
    for k in range(10):
        if i >= end: return None
        c = b[i]; i += 1
        v |= (c & 0x7F) << s
        s += 7
        if not c & 0x80: return v & ((1 << 64) - 1), i
    return None

def fields(b, i=0, end=None):
    """-> list of (field, wire type, value or (start, length)) or None if malformed"""
    end = len(b) if end is None else end
    out = []
    while i < end:
        r = read_varint(b, i, end)
        if not r: return None
        k, i = r
        f, wt = k >> 3, k & 7
        if f == 0: return None
        if wt == 0:
            r = read_varint(b, i, end)
            if not r: return None
            v, i = r
        elif wt == 1:
            if i + 8 > end: return None
            v = struct.unpack_from('<Q', b, i)[0]; i += 8
        elif wt == 2:
            r = read_varint(b, i, end)
            if not r: return None
            n, i = r
            if n > end - i: return None
            v = (i, n); i += n
        elif wt == 5:
            if i + 4 > end: return None
            v = struct.unpack_from('<I', b, i)[0]; i += 4
        else:
            return None
        out.append((f, wt, v))
    return out

def cut_utf8(b, n):
    if len(b) <= n: return b
    while n > 0 and (b[n] & 0xC0) == 0x80: n -= 1
    return b[:n]

# --- what we send ----------------------------------------------------------------------------

def want_config(nonce):  return f_varint(3, nonce & 0xFFFFFFFF)
def heartbeat():         return f_bytes(7, b'')

def send_text(to, chan, pid, text, ack):
    data = f_varint(1, PORT_TEXT) + f_bytes(2, cut_utf8(text, TEXT_MAX))
    pkt = f_fixed32(2, to) + (f_varint(3, chan) if chan else b'') + f_bytes(4, data) + f_fixed32(6, pid) \
        + (f_varint(10, 1) if ack else b'')
    return f_bytes(1, pkt)

# --- the allowlist ---------------------------------------------------------------------------

def allowed(f):
    """1 if asmmesh may write this ToRadio: start-up, a heartbeat, or a plain text packet
    (to someone or everyone, on channel 0-7). Never admin, config, raw or encrypted payloads,
    XModem, MQTT, or a field we don't send."""
    if not 1 <= len(f) <= FRAME_MAX: return 0
    top = fields(f)
    if top is None or len(top) != 1: return 0
    fn, wt, v = top[0]
    if fn == 3 and wt == 0: return 1                               # want_config_id
    if fn == 7 and wt == 2: return int(v[1] == 0)                  # heartbeat, empty
    if fn != 1 or wt != 2: return 0
    p = fields(f, v[0], v[0] + v[1])                               # the MeshPacket
    if p is None: return 0
    seen, data = set(), None
    for pf, pw, pv in p:
        if pf in seen: return 0
        seen.add(pf)
        if pf == 2 and pw == 5: continue                           # to
        if pf == 3 and pw == 0 and pv <= 7: continue               # channel
        if pf == 6 and pw == 5: continue                           # id
        if pf == 10 and pw == 0 and pv <= 1: continue              # want_ack
        if pf == 4 and pw == 2: data = pv; continue                # decoded
        return 0
    if data is None: return 0
    d = fields(f, data[0], data[0] + data[1])
    if d is None: return 0
    port, seen = None, set()
    for df, dw, dv in d:
        if df in seen: return 0
        seen.add(df)
        if df == 1 and dw == 0: port = dv; continue
        if df == 2 and dw == 2 and dv[1] <= 233: continue
        return 0
    return int(port == PORT_TEXT)

# --- what the radio sends --------------------------------------------------------------------

def parse(f):
    """FromRadio -> (kind, fields) or (-1, {}). kind: the field number of what it holds
    (2 packet, 3 my_info, 4 node_info, 7 config_complete_id, 8 rebooted, 10 channel, ...), 0 if
    nothing (an empty read)"""
    if len(f) > FRAME_MAX: return -1, {}
    top = fields(f)
    if top is None: return -1, {}
    kind, d = 0, {}
    for fn, wt, v in top:
        if fn == 1: continue                                       # FromRadio.id
        kind = fn
        d = {}
        if fn == 2 and wt == 2:
            p = fields(f, v[0], v[0] + v[1])
            if p is None: return -1, {}
            for pf, pw, pv in p:
                if pf == 1 and pw == 5: d['from'] = pv
                elif pf == 2 and pw == 5: d['to'] = pv
                elif pf == 3 and pw == 0: d['chan'] = pv
                elif pf == 6 and pw == 5: d['pid'] = pv
                elif pf == 5 and pw == 2: d['enc'] = 1
                elif pf == 4 and pw == 2:
                    dd = fields(f, pv[0], pv[0] + pv[1])
                    if dd is None: return -1, {}
                    for df, dw, dv in dd:
                        if df == 1 and dw == 0: d['port'] = dv
                        elif df == 2 and dw == 2: d['text'] = f[dv[0]:dv[0] + dv[1]]
        elif fn == 3 and wt == 2:
            p = fields(f, v[0], v[0] + v[1])
            if p is None: return -1, {}
            for pf, pw, pv in p:
                if pf == 1 and pw == 0: d['num'] = pv
        elif fn == 4 and wt == 2:
            p = fields(f, v[0], v[0] + v[1])
            if p is None: return -1, {}
            for pf, pw, pv in p:
                if pf == 1 and pw == 0: d['num'] = pv
                elif pf == 5 and pw == 5: d['seen'] = pv
                elif pf == 2 and pw == 2:
                    u = fields(f, pv[0], pv[0] + pv[1])
                    if u is None: return -1, {}
                    for uf, uw, uv in u:
                        if uw != 2: continue
                        s = f[uv[0]:uv[0] + uv[1]]
                        if uf == 1: d['uid'] = s
                        elif uf == 2: d['long'] = s
                        elif uf == 3: d['short'] = s
        elif fn == 7 and wt == 0:
            d['num'] = v
        elif fn == 10 and wt == 2:
            p = fields(f, v[0], v[0] + v[1])
            if p is None: return -1, {}
            for pf, pw, pv in p:
                if pf == 1 and pw == 0: d['num'] = pv
                elif pf == 3 and pw == 0: d['role'] = pv
                elif pf == 2 and pw == 2:
                    s = fields(f, pv[0], pv[0] + pv[1])
                    if s is None: return -1, {}
                    for sf, sw, sv in s:
                        if sf == 3 and sw == 2: d['long'] = f[sv[0]:sv[0] + sv[1]]
    return kind, d

FIELDS = ('from', 'to', 'chan', 'port', 'pid', 'num', 'text', 'long', 'short', 'uid', 'seen', 'role', 'enc')

def show(kind, d):
    if kind < 0: return 'bad'
    out = ['%02x' % kind]
    for k in FIELDS:
        if k in d:
            v = d[k]
            out.append('%s=%s' % (k, (v.hex() or '-') if isinstance(v, bytes) else str(v)))
    return ' '.join(out)

def vectors():
    def line(label, b): print('%-10s %s' % (label, b.hex()))
    line('config', want_config(0x12345678))
    line('heart', heartbeat())
    line('text', send_text(BROADCAST, 0, 0xA1B2C3D4, b'hi all', 0))
    line('dm', send_text(0x0A0B0C0D, 1, 7, 'héllo'.encode(), 1))

if __name__ == '__main__':
    if sys.argv[1:] == ['vectors']: vectors()
