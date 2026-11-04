# blocklist.py: the developer blocklist, on your Mac. A list of banned asmmesh / bitchat ids,
# signed with a key only you hold; every asmmesh checks the signature with the public half
# built into the app (src/dbl_key.inc) and blocks those ids, as if each person had blocked
# them. Needs: pip install cryptography.
#
#   python3 blocklist.py keygen                 once: makes your key (kept in ~/.asmmesh-blocklist,
#                                               never in the repository) and writes src/dbl_key.inc
#   python3 blocklist.py url https://you.example/asmmesh/blocklist.bin
#                                               where devices fetch it daily (in src/dbl_key.inc)
#   python3 blocklist.py add 0123456789abcdef "why"   an id from a report ("id ..." in it)
#   python3 blocklist.py remove 0123456789abcdef
#   python3 blocklist.py list
#   python3 blocklist.py sign                   a new version: blocklist.bin to upload to the URL,
#                                               and src/dbl_list.bin, shipped in the next build
#   python3 blocklist.py show <file>            check a list and print it
#
# The file: "ASMBL1" 0 0, version u32 LE, count u32 LE, ids u64 LE (ascending), then an
# Ed25519 signature (64) of everything before it. Devices take a list only if its signature
# is good and its version is newer than theirs: an old list can't be sent again to unban.
import os, struct, sys

HOME = os.path.expanduser('~/.asmmesh-blocklist')
KEY = os.path.join(HOME, 'key')                 # the 32-byte Ed25519 private seed
BANNED = os.path.join(HOME, 'banned.txt')       # one id per line, then why
VERSION = os.path.join(HOME, 'version')
REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
KEY_INC = os.path.join(REPO, 'src', 'dbl_key.inc')
SHIPPED = os.path.join(REPO, 'src', 'dbl_list.bin')
MAGIC = b'ASMBL1\0\0'
MAX = 4096

def pack(version, ids, seed):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    ids = sorted(set(ids))
    body = MAGIC + struct.pack('<II', version, len(ids)) + b''.join(struct.pack('<Q', i) for i in ids)
    return body + Ed25519PrivateKey.from_private_bytes(seed).sign(body)

def unpack(data, pub):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    if len(data) < 80 or data[:8] != MAGIC:
        raise ValueError('not a blocklist')
    version, n = struct.unpack_from('<II', data, 8)
    if n > MAX or len(data) != 16 + 8 * n + 64:
        raise ValueError('wrong length')
    Ed25519PublicKey.from_public_bytes(pub).verify(data[-64:], data[:-64])
    ids = [struct.unpack_from('<Q', data, 16 + 8 * k)[0] for k in range(n)]
    if ids != sorted(set(ids)):
        raise ValueError('ids not in order')
    return version, ids

def write_inc(pub, url):
    with open(KEY_INC, 'w') as f:
        f.write('// dbl_key.inc — made by tools/blocklist/blocklist.py: the developer blocklist\'s public key\n')
        f.write('// (all zeros: no key yet, no list is taken) and where devices fetch the list ("": nowhere)\n')
        f.write('Ldbl_pub:\n    .byte %s\n' % ', '.join('0x%02x' % b for b in pub))
        f.write('Ldbl_url_text:\n    .asciz "%s"\n' % url)

def read_inc():
    pub, url = bytes(32), ''
    if os.path.exists(KEY_INC):
        t = open(KEY_INC).read()
        i = t.index('.byte') + 5
        pub = bytes(int(x, 16) for x in t[i:t.index('\n', i)].split(','))
        url = t[t.index('.asciz "') + 8:].split('"')[0]
    return pub, url

def ids_from_file():
    out = {}
    if os.path.exists(BANNED):
        for line in open(BANNED):
            f = line.split(None, 1)
            if f and not f[0].startswith('#'):
                out[int(f[0], 16)] = f[1].strip() if len(f) > 1 else ''
    return out

def save_ids(ids):
    with open(BANNED, 'w') as f:
        for i, why in sorted(ids.items()):
            f.write('%016x %s\n' % (i, why))

def main(argv):
    cmd = argv[1] if len(argv) > 1 else ''
    os.makedirs(HOME, mode=0o700, exist_ok=True)
    if cmd == 'keygen':
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives import serialization as s
        if os.path.exists(KEY):
            sys.exit('a key exists already: %s (delete it only if you mean to replace it: lists signed '
                     'with it stop working in every copy of asmmesh)' % KEY)
        k = Ed25519PrivateKey.generate()
        seed = k.private_bytes(s.Encoding.Raw, s.PrivateFormat.Raw, s.NoEncryption())
        fd = os.open(KEY, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.write(fd, seed)
        os.close(fd)
        pub = k.public_key().public_bytes(s.Encoding.Raw, s.PublicFormat.Raw)
        write_inc(pub, read_inc()[1])
        print('key made: %s (back it up somewhere safe; never put it in the repository)' % KEY)
        print('public key written to src/dbl_key.inc: commit that, and build')
    elif cmd == 'url':
        write_inc(read_inc()[0], argv[2])
        print('devices will fetch %s daily (after the next build)' % argv[2])
    elif cmd in ('add', 'remove'):
        ids = ids_from_file()
        i = int(argv[2].replace('-', ''), 16)
        if cmd == 'add':
            ids[i] = ' '.join(argv[3:])
        else:
            ids.pop(i, None)
        save_ids(ids)
        print('%d ids in %s: sign to publish' % (len(ids), BANNED))
    elif cmd == 'list':
        for i, why in sorted(ids_from_file().items()):
            print('%016x  %s' % (i, why))
    elif cmd == 'sign':
        seed = open(KEY, 'rb').read()
        version = int(open(VERSION).read()) + 1 if os.path.exists(VERSION) else 1
        data = pack(version, ids_from_file().keys(), seed)
        out = os.path.join(HOME, 'blocklist.bin')
        open(out, 'wb').write(data)
        open(SHIPPED, 'wb').write(data)
        open(VERSION, 'w').write(str(version))
        print('version %d, %d ids, %d bytes' % (version, (len(data) - 80) // 8, len(data)))
        print('upload %s to the URL (devices take it within a day)' % out)
        print('and commit src/dbl_list.bin (the next build carries it)')
    elif cmd == 'show':
        v, ids = unpack(open(argv[2], 'rb').read(), read_inc()[0])
        print('version %d, signature good, %d ids' % (v, len(ids)))
        for i in ids:
            print('%016x' % i)
    else:
        print(__doc__ if __doc__ else open(__file__).read().split('import')[0])

if __name__ == '__main__':
    main(sys.argv)
