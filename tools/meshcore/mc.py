#!/usr/bin/env python3
"""mc.py — the Python copy of src/mc_core.s: MeshCore companion-radio frames built and read,
the allowlist of what asmmesh may ever ask a radio, text cleaning, and the private channel's key.

Written from MeshCore's own docs/companion_protocol.md and examples/companion_radio/MyMesh.cpp
(meshcore-dev/MeshCore 81dbae5, MIT). Used by mcdiff.py to check the assembly on random cases,
and to make the self-tests' vectors:  python3 tools/meshcore/mc.py vectors
"""
import hashlib, hmac, struct, sys

FRAME_MAX = 172                 # the most we ever write (the radio takes 176)
TEXT_MAX = 133                  # MeshCore's limit for a message's text, in bytes here
DATA_MAX = 165                  # channel data payload (MAX_GROUP_DATA_LENGTH)
DATA_TYPE = 0xFFFF              # DATA_TYPE_DEV until asmmesh has a registered number
APP_NAME = b'asmmesh'

# --- what we send ---------------------------------------------------------------------------

def app_start():                 return bytes([1]) + bytes(7) + APP_NAME
def device_query():              return bytes([0x16, 3])
def get_contacts(since=0):       return bytes([4]) + (struct.pack('<I', since) if since else b'')
def sync_next():                 return bytes([0x0A])
def get_channel(i):              return bytes([0x1F, i & 255])

def set_channel(i, name, secret):
    n = name[:31]
    return bytes([0x20, i & 255]) + n + bytes(32 - len(n)) + secret[:16]

def cut_utf8(b, n):
    """b cut to at most n bytes, not inside a character"""
    if len(b) <= n: return b
    while n > 0 and (b[n] & 0xC0) == 0x80: n -= 1
    return b[:n]

def send_chan_txt(i, ts, text):
    return bytes([3, 0, i & 255]) + struct.pack('<I', ts & 0xFFFFFFFF) + cut_utf8(text, TEXT_MAX)

def send_txt(prefix6, ts, text):
    return bytes([2, 0, 0]) + struct.pack('<I', ts & 0xFFFFFFFF) + prefix6[:6] + cut_utf8(text, TEXT_MAX)

def send_chan_data(i, payload):
    return bytes([0x3E, i & 255, 0xFF]) + struct.pack('<H', DATA_TYPE) + payload[:DATA_MAX]

# --- the allowlist: the only frames asmmesh may ever write to a radio -----------------------

def allowed(f, slot):
    n = len(f)
    if n < 1 or n > FRAME_MAX: return 0
    c = f[0]
    if c == 1: return 1                                   # APP_START
    if c == 0x0A: return int(n == 1)                      # SYNC_NEXT_MESSAGE
    if c == 0x16: return int(n == 2)                      # DEVICE_QUERY
    if c == 4: return int(n in (1, 5))                    # GET_CONTACTS
    if c == 0x1F: return int(n == 2)                      # GET_CHANNEL
    if c == 3: return int(n >= 8 and f[1] == 0)           # SEND_CHANNEL_TXT_MSG, plain text
    if c == 2: return int(n >= 14 and f[1] == 0)          # SEND_TXT_MSG, plain (never a CLI command)
    if c == 0x20:                                         # SET_CHANNEL: our slot only, never Public's,
        return int(n == 50 and slot != 0 and f[1] == slot and any(f[34:50]))   # never a zero key
    if c == 0x3E:                                         # SEND_CHANNEL_DATA: flood, our type, fits
        return int(n >= 6 and f[2] == 0xFF and f[3:5] == struct.pack('<H', DATA_TYPE) and n - 5 <= DATA_MAX)
    return 0

# --- what the radio sends: one notification is one frame -----------------------------------

def u32(f, i): return struct.unpack_from('<I', f, i)[0]
def s8(b): return b - 256 if b >= 128 else b
def zlen(f, i, n):
    """bytes before the first 0 in f[i:i+n]"""
    s = f[i:i + n]
    k = s.find(b'\0')
    return len(s) if k < 0 else k

def parse(f):
    """-> (kind, fields) or (-1, {}) if malformed. kind is the frame's first byte."""
    n = len(f)
    if n < 1 or n > 255: return -1, {}
    c = f[0]
    d = {}
    def text_at(i):
        if i > n: return False
        d['text'] = f[i:]
        return True
    if c == 0x00:
        d['val'] = u32(f, 1) if n >= 5 else 0
    elif c == 0x01:
        d['val'] = f[1] if n >= 2 else 0
    elif c == 0x02:
        if n < 5: return -1, {}
        d['val'] = u32(f, 1)
    elif c in (0x03, 0x8A):
        if n < 148: return -1, {}
        d['key'] = f[1:33]; d['val2'] = f[33]; d['path'] = f[35]
        d['name'] = f[100:100 + zlen(f, 100, 32)]; d['ts'] = u32(f, 132)
    elif c == 0x04:
        d['val'] = u32(f, 1) if n >= 5 else 0
    elif c == 0x05:
        if n < 58: return -1, {}
        d['key'] = f[4:36]; d['val'] = u32(f, 48); d['val2'] = f[56]
        d['name'] = f[58:58 + zlen(f, 58, 32)]
    elif c == 0x06:
        if n < 10: return -1, {}
        d['val'] = f[1]; d['val2'] = u32(f, 2)
    elif c == 0x07:
        if n < 13: return -1, {}
        d['key'] = f[1:7]; d['path'] = f[7]; d['tt'] = f[8]; d['ts'] = u32(f, 9)
        if not text_at(17 if f[8] == 2 else 13): return -1, {}
    elif c == 0x10:
        if n < 16: return -1, {}
        d['snr'] = s8(f[1]); d['key'] = f[4:10]; d['path'] = f[10]; d['tt'] = f[11]; d['ts'] = u32(f, 12)
        if not text_at(20 if f[11] == 2 else 16): return -1, {}
    elif c == 0x08:
        if n < 8: return -1, {}
        d['chan'] = f[1]; d['path'] = f[2]; d['tt'] = f[3]; d['ts'] = u32(f, 4); text_at(8)
    elif c == 0x11:
        if n < 11: return -1, {}
        d['snr'] = s8(f[1]); d['chan'] = f[4]; d['path'] = f[5]; d['tt'] = f[6]; d['ts'] = u32(f, 7); text_at(11)
    elif c == 0x0D:
        if n < 2: return -1, {}
        d['val'] = f[1]
        if f[1] >= 3 and n >= 4: d['val2'] = f[3]
    elif c == 0x12:
        if n < 50: return -1, {}
        d['chan'] = f[1]; d['name'] = f[2:2 + zlen(f, 2, 32)]; d['secret'] = f[34:50]
    elif c == 0x1B:
        if n < 9: return -1, {}
        dl = f[8]
        if 9 + dl > n: return -1, {}
        d['snr'] = s8(f[1]); d['chan'] = f[4]; d['path'] = f[5]; d['val2'] = struct.unpack_from('<H', f, 6)[0]
        d['text'] = f[9:9 + dl]
    elif c == 0x80:
        if n < 33: return -1, {}
        d['key'] = f[1:33]
    elif c == 0x82:
        d['val'] = u32(f, 1) if n >= 5 else 0
    return c, d

FIELDS = ('val', 'val2', 'chan', 'path', 'tt', 'ts', 'snr', 'key', 'name', 'text', 'secret')

def show(kind, d):
    """the line the harness prints for a parse (mcdiff.py compares them)"""
    if kind < 0: return 'bad'
    out = ['%02x' % kind]
    for k in FIELDS:
        if k in d:
            v = d[k]
            out.append('%s=%s' % (k, (v.hex() or '-') if isinstance(v, bytes) else str(v)))
    return ' '.join(out)

# --- text as it may be shown ---------------------------------------------------------------

def utf8_fix(b):
    """invalid UTF-8 (bad bytes, cut or overlong sequences, surrogates) becomes '?', byte for byte"""
    out = bytearray(b)
    i, n = 0, len(b)
    while i < n:
        c = b[i]
        if c < 0x80:
            i += 1
            continue
        if 0xC2 <= c <= 0xDF: k, lo, hi = 1, 0x80, 0xBF
        elif c == 0xE0: k, lo, hi = 2, 0xA0, 0xBF
        elif 0xE1 <= c <= 0xEC or 0xEE <= c <= 0xEF: k, lo, hi = 2, 0x80, 0xBF
        elif c == 0xED: k, lo, hi = 2, 0x80, 0x9F
        elif c == 0xF0: k, lo, hi = 3, 0x90, 0xBF
        elif 0xF1 <= c <= 0xF3: k, lo, hi = 3, 0x80, 0xBF
        elif c == 0xF4: k, lo, hi = 3, 0x80, 0x8F
        else: k = -1
        ok = k > 0 and i + k < n and lo <= b[i + 1] <= hi and \
            all(0x80 <= b[j] <= 0xBF for j in range(i + 2, i + k + 1))
        if ok:
            i += k + 1
        else:
            out[i] = 0x3F
            i += 1
    return bytes(out)

# _bc_text_clean's characters (bc_peer.s), as ranges of code points
BLANK = [(0x00, 0x1F), (0x7F, 0x9F), (0xAD, 0xAD), (0x61C, 0x61C), (0x180E, 0x180E), (0x200B, 0x200F),
         (0x2028, 0x202E), (0x2060, 0x2064), (0x2066, 0x206F), (0xFEFF, 0xFEFF), (0xFFF9, 0xFFFB)]

def text_clean(b):
    """as _bc_text_clean: each blanked character becomes spaces, byte for byte"""
    out = bytearray(b)
    s = b.decode('utf-8')
    i = 0
    for ch in s:
        e = ch.encode('utf-8')
        cp = ord(ch)
        if any(lo <= cp <= hi for lo, hi in BLANK):
            out[i:i + len(e)] = b' ' * len(e)
        i += len(e)
    return bytes(out)

def show_text(b, cap):
    """what's shown: at most cap-1 bytes, not cut inside a character, valid, cleaned"""
    return text_clean(utf8_fix(cut_utf8(b, cap - 1)))

def sender(text):
    """a channel message is "Name: text": the name's length, or 0 (within 32 bytes, not empty)"""
    k = text[:34].find(b': ')
    return k if 0 < k <= 32 else 0

# --- asmmesh's private LoRa channel key, from the mesh passphrase --------------------------

SALT = b'asmmesh meshcore channel v1'

def hkdf16(ikm, info):
    prk = hmac.new(SALT, ikm, hashlib.sha256).digest()
    return hmac.new(prk, info + b'\x01', hashlib.sha256).digest()[:16]

def chan_secret(passphrase):
    """with a passphrase: only its holders can read the channel; without: a fixed asmmesh key
    (packets are signed, room contents sealed, either way)"""
    return hkdf16(passphrase if passphrase else b'asmmesh', b'secret')

# --- self-test vectors ----------------------------------------------------------------------

def vectors():
    def line(label, b): print('%-14s %s' % (label, b.hex()))
    line('app_start', app_start())
    line('query', device_query())
    line('contacts', get_contacts())
    line('contacts_t', get_contacts(0x01020304))
    line('sync', sync_next())
    line('getchan', get_channel(3))
    line('setchan', set_channel(3, b'asmmesh', bytes(range(1, 17))))
    line('chantxt', send_chan_txt(0, 0x5f5e1000, 'héllo wörld'.encode()))
    line('dm', send_txt(bytes.fromhex('a1b2c3d4e5f6'), 0x5f5e1000, b'hi Anna'))
    line('data', send_chan_data(3, b'\xAB\xCD'))
    line('secret', chan_secret(b'correct horse'))
    line('secret0', chan_secret(b''))
    long = ('é' * 80).encode()
    line('chantxt_cut', send_chan_txt(0, 1, long))

if __name__ == '__main__':
    if sys.argv[1:] == ['vectors']: vectors()
