# benchmark.py: measures Ninefold's word lists against puzzles whose answers people chose.
# For each puzzle (nine letters, a centre letter, the editors' words), our lists are run on
# the same tiles, and the two are compared word for word:
#   accepted       of the editors' words, how many we accept (as answers or also accepted)
#   answers listed of our answers, how many the editors listed too
# Puzzles whose own words don't fit their tiles or centre (scraping errors) are left out,
# and so are 3-letter words and the nine-letter word itself.
# The puzzle file isn't in this repository: it is someone else's work. Point at your copy.
#
# Usage: python3 benchmark.py <puzzles.csv>   (columns: letters, center, solutions)
#        add --words to print the words on each side of the difference
import csv, sys
from collections import Counter

here = sys.path[0]
answers = set(open(here + '/words/answers.txt').read().split())
extra = set(open(here + '/words/extra.txt').read().split())
family = set(open(here + '/words/family.txt').read().split())

def fits(w, tiles):
    c, t = Counter(w), Counter(tiles)
    return all(c[k] <= t[k] for k in c)

rows = list(csv.DictReader(open(sys.argv[1])))
clean = [r for r in rows if all(fits(w, r['letters']) and r['center'] in w for w in r['solutions'].split())]
accepted = missed = listed = unlisted = 0
miss, ours = Counter(), Counter()
for r in clean:
    t, c = r['letters'], r['center']
    theirs = {w for w in r['solutions'].split() if 4 <= len(w) < 9}
    oa = {w for w in answers if len(w) < 9 and c in w and fits(w, t) and w not in family}
    ox = {w for w in extra if len(w) < 9 and c in w and fits(w, t) and w not in family}
    accepted += len(theirs & (oa | ox))
    missed += len(theirs - (oa | ox))
    listed += len(oa & theirs)
    unlisted += len(oa - theirs)
    miss.update(theirs - (oa | ox))
    ours.update(oa - theirs)
print('%d of %d puzzles usable (the rest have words that don\'t fit their own tiles)' % (len(clean), len(rows)))
print('their words accepted:      %d of %d (%.1f%%)' % (accepted, accepted + missed, 100 * accepted / (accepted + missed)))
print('our answers they list too: %d of %d (%.1f%%)' % (listed, listed + unlisted, 100 * listed / (listed + unlisted)))
try:                                       # why each missed word is out (make_words.py's REPORT)
    why = dict(l.rstrip('\n').split('\t', 1) for l in open(here + '/words/REPORT.txt') if '\t' in l)
    kinds = Counter()
    for w, n in miss.items():
        r = why.get(w, 'not in ENABLE or SCOWL')
        k = ('a plural or -s form (our rule)' if 'plural' in r else 'a contraction (our rule)' if 'contraction' in r
             else 'a name' if 'a name' in r else 'family filter' if w in family else
             'not in ENABLE or SCOWL 10-60' if 'not in' in r else 'rare' if 'rare' in r else r)
        kinds[k] += n
    for k, n in kinds.most_common():
        print('  missed because %-32s %5d' % (k + ':', n))
    ruled = kinds['a plural or -s form (our rule)'] + kinds['a contraction (our rule)'] + kinds['family filter']
    print('their words accepted, leaving out what our rules exclude on purpose: %.1f%%'
          % (100 * accepted / (accepted + missed - ruled)))
except FileNotFoundError:
    pass
if '--words' in sys.argv:
    print('their words we don\'t accept: ' + ' '.join(w for w, n in miss.most_common()))
    print('our answers they never list: ' + ' '.join(w for w, n in ours.most_common()))
