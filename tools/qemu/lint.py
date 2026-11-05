# lint.py — checks for mistakes the assembler doesn't catch, in src/*.s:
#   - a function whose LEAVE doesn't match its ENTER (the stack would come back wrong)
#   - bc_ble.s's LINK macro given x17, its scratch register, or the same register twice
#   - a list of strings (an .asciz with no label of its own) in __cstring: the Mac's linker
#     treats each string there on its own (merges, moves, drops the empty end), breaking
#     the list, though Linux keeps it (so qemu passes); such lists belong in __TEXT,__const
# Usage: python3 tools/qemu/lint.py   (exit 1 if anything is found)
import glob, os, re, sys

src = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'src')
bad = 0
for f in sorted(glob.glob(os.path.join(src, '*.s'))):
    enter = None
    for n, line in enumerate(open(f, errors='replace'), 1):
        label = re.match(r'^([_A-Za-z]\w*):', line)
        # a function starts at a global or an Lxxx_ label that's not a branch target inside one
        if label and (label.group(1).startswith('_') or re.match(r'^L[a-z]+[A-Z_]', label.group(1)) is None
                      and not re.match(r'^L[a-z]{1,3}_', label.group(1))):
            enter = None
        e = re.match(r'\s+ENTER\s+(\d+)', line)
        if e:
            enter = int(e.group(1))
        lv = re.search(r'\bLEAVE\s+(\d+)', line)
        if lv and enter is not None and int(lv.group(1)) != enter:
            print('%s:%d: ENTER %d but LEAVE %s' % (os.path.basename(f), n, enter, lv.group(1)))
            bad += 1
        m = re.match(r'\s+LINK\s+(x\d+),\s*(x\d+)', line)
        if m and (m.group(1) == m.group(2) or 'x17' in m.groups()):
            print('%s:%d: LINK %s, %s: x17 is its scratch, and the two must differ'
                  % (os.path.basename(f), n, m.group(1), m.group(2)))
            bad += 1

def cstring_lists(path, shown, in_cstring=False):
    """unlabelled .asciz lines in __cstring (following .include into .inc files)"""
    found = 0
    labelled = False
    for n, line in enumerate(open(path, errors='replace'), 1):
        code = line.split('//')[0].strip()
        if code.startswith('.section') or code in ('.text', '.data'):
            in_cstring = 'cstring' in code
            continue
        inc = re.match(r'\.include\s+"([\w.]+)"', code)
        if inc and in_cstring:
            found += cstring_lists(os.path.join(src, inc.group(1)), shown, True)
            continue
        if re.match(r'^[\w.]+:\s*$', code):
            labelled = True
            continue
        if in_cstring and code.startswith('.asciz') and not labelled:
            print('%s:%d: a string with no label in __cstring (a list? put it in __TEXT,__const)'
                  % (os.path.basename(path), n))
            found += 1
        if code:
            labelled = False
    return found

for f in sorted(glob.glob(os.path.join(src, '*.s'))):
    bad += cstring_lists(f, set())
print('%d found' % bad)
sys.exit(1 if bad else 0)
