#!/usr/bin/env python3
"""linkcheck.py — assemble every file of the Mac app (Makefile) and the iPhone core
(ios/make_project.py) as Apple arm64 objects, and list any symbol used but defined nowhere
that isn't the system's (libc, Apple frameworks) or, on the iPhone, the Swift side's (_ios_*).
A label used from another file but not .globl shows up here. Run on Linux with clang and llvm-nm:
    python3 tools/linkcheck.py      (exit 1 if anything is missing)"""
import os, re, subprocess, sys, tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SYSTEM = re.compile(r'^_(NS|objc_|kCF|kSec|CB|k[A-Z]|_|dispatch_|Sec|CF|CC|IO|Audio|pthread_|posix_spawn|UI|AV)')
LIBC = set('''accept access alphasort arc4random arc4random_buf arc4random_uniform atof atoi atol bind bzero
calloc class_addMethod class_addProtocol clock_gettime close compress2 cos dladdr dup dup2 exit fclose fcntl
fopen fprintf fread free freeaddrinfo freeifaddrs fstat getaddrinfo getenv gethostname getifaddrs inet_addr
inet_ntop inflate inflateEnd inflateInit2_ kill listen localtime_r log10 lseek malloc memcmp memcpy memmem
memmove memset mkdir mkdtemp nanosleep open pclose pipe popen pow printf read recvfrom rmdir scandir
sel_registerName sendto setenv setsockopt sigaction siglongjmp sigsetjmp sin snprintf socket socketpair stat
strcasecmp strcasestr strchr strcmp strcpy strdup strftime strlcat strlcpy strlen strncasecmp strncmp strnlen
strrchr strstr strtoll time uncompress unlink usleep waitpid write'''.split())

def check(name, files, target, swift_ok):
    d = tempfile.mkdtemp()
    objs = []
    for f in files:
        o = os.path.join(d, os.path.basename(f) + '.o')
        r = subprocess.run(['clang', '--target=' + target, '-I', os.path.join(ROOT, 'src'), '-c', f, '-o', o],
                           capture_output=True, text=True)
        if r.returncode:
            print('%s: %s does not assemble:\n%s' % (name, f, r.stderr[:600]))
            return 1
        objs.append(o)
    nm = lambda *a: subprocess.run(['llvm-nm', *a, *objs], capture_output=True, text=True).stdout.split('\n')
    defined = {l.split()[-1] for l in nm('-g', '--defined-only') if len(l.split()) == 3}
    used = {l.split()[-1] for l in nm('-u') if l.strip() and not l.endswith(':')}
    missing = sorted(s for s in used - defined
                     if not SYSTEM.match(s) and s[1:] not in LIBC and not (swift_ok and s.startswith('_ios_')))
    for s in missing:
        users = [os.path.basename(o)[:-2] for o in objs
                 if s in subprocess.run(['llvm-nm', '-u', o], capture_output=True, text=True).stdout.split()]
        print('%s: %s is used (%s) but defined nowhere, or not .globl' % (name, s, ', '.join(users)))
    print('%s: %d files, %s' % (name, len(files), 'all symbols found' if not missing else '%d missing' % len(missing)))
    return 1 if missing else 0

mk = open(os.path.join(ROOT, 'Makefile')).read()
mac = [os.path.join(ROOT, 'src', f) for f in re.findall(r'\$\(SRCDIR\)/([a-z_0-9]+\.s)', mk)]
mp = open(os.path.join(ROOT, 'ios', 'make_project.py')).read()
core = re.search(r'CORE\s*=\s*"""(.*?)"""', mp, re.S).group(1).split()
ios = [os.path.join(ROOT, 'src', f + '.s') for f in core] + [os.path.join(ROOT, 'ios', 'asm', 'ios_ui.s')]
bad = check('Mac', mac, 'arm64-apple-macos12', False) + check('iPhone', ios, 'arm64-apple-ios16', True)
sys.exit(1 if bad else 0)
