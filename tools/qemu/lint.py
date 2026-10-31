# lint.py — checks for mistakes the assembler doesn't catch, in src/*.s:
#   - a function whose LEAVE doesn't match its ENTER (the stack would come back wrong)
#   - bc_ble.s's LINK macro given x17, its scratch register, or the same register twice
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
print('%d found' % bad)
sys.exit(1 if bad else 0)
