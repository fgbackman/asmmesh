# check_samples.py: checks samples-*.md without the generator's code. For each puzzle:
#   - every word listed: 4-9 letters a-z, has the centre letter, uses no tile more often
#     than the nine-letter word has it, and is in the list it claims to come from
#   - nothing missing: every word of the lists that fits is listed
#   - the nine-letter word has no other 9-letter anagram among the answers
# Usage: python3 check_samples.py ../../docs/ninefold/samples-200.md
import re, sys

here = sys.path[0]
answers = set(open(here + '/words/answers.txt').read().split())
extra = set(open(here + '/words/extra.txt').read().split())

def counts(w):
    c = [0] * 26
    for ch in w:
        c[ord(ch) - 97] += 1
    return c

def fits(w, tiles):
    cw = counts(w)
    return all(cw[i] <= tiles[i] for i in range(26))

text = open(sys.argv[1]).read()
heads = list(re.finditer(r'^## (\d+)\. ([A-Z]{9}) \(centre ([A-Z])\): (\d+) answers\n(.*)\nAlso accepted \((\d+)\): (.*)$', text, re.M))
problems, n_words = [], 0
for m in heads:
    num, nine, centre = m.group(1), m.group(2).lower(), m.group(3).lower()
    listed = [w.lower() for w in m.group(5).split(', ')]
    listed_x = [] if m.group(7) == '-' else [w.lower() for w in m.group(7).split(', ')]
    tiles = counts(nine)
    if centre not in nine:
        problems.append('%s: centre %s not in %s' % (num, centre, nine))
    if int(m.group(4)) != len(listed) or int(m.group(6)) != len(listed_x):
        problems.append('%s: counts in the heading are wrong' % num)
    for w, src, name in [(w, answers, 'answers') for w in listed] + [(w, extra, 'extra') for w in listed_x]:
        n_words += 1
        if not re.fullmatch(r'[a-z]{4,9}', w): problems.append('%s: %s: not 4-9 letters a-z' % (num, w))
        if centre not in w: problems.append('%s: %s: no centre letter' % (num, w))
        if not fits(w, tiles): problems.append('%s: %s: uses a tile too often' % (num, w))
        if w not in src: problems.append('%s: %s: not in %s.txt' % (num, w, name))
    want = {w for w in answers if 4 <= len(w) <= 9 and centre in w and fits(w, tiles)}
    want_x = {w for w in extra if 4 <= len(w) <= 9 and centre in w and fits(w, tiles)}
    for w in sorted(want - set(listed)): problems.append('%s: missing answer %s' % (num, w))
    for w in sorted(want_x - set(listed_x)): problems.append('%s: missing extra %s' % (num, w))
    anagrams = [w for w in answers if len(w) == 9 and sorted(w) == sorted(nine)]
    if anagrams != [nine]: problems.append('%s: nine-letter anagrams: %s' % (num, anagrams))
print('%d puzzles, %d words checked, %d problems' % (len(heads), n_words, len(problems)))
for p in problems: print('  ' + p)
sys.exit(1 if problems else 0)
