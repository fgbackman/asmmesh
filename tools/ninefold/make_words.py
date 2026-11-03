# make_words.py: builds Ninefold's word lists. Accuracy decides what is a word; taste is a
# separate, visible layer on top (the family filter), so no moral call can cost a real word.
# Run it again to rebuild; the output must not change unless a source does (versions pinned).
#
#   answers.txt   the words a round counts, reveals and says you missed
#   extra.txt     real words that are rarer: they score, but are never shown as missed
#   family.txt    words the family filter hides (a game setting, on by default): only words
#                 on the lists below exactly as written there, never guessed variants
#   REPORT.txt    every word left out of answers and extra, and why (not in git: ~3 MB)
#
# ACCURACY. A word (4 to 9 letters a-z, lower case) is an ANSWER if all of these hold:
#   1. ENABLE2K (public domain): a valid word, so no names or abbreviations
#   2. SCOWL 2020.12.07, sizes 10-50 (English, American, British): an ordinary dictionary
#      word, not an archaic, technical or dialect one
#   3. wordfreq 3.1.1: Zipf frequency >= 2.5 in English text (about once in 3 million
#      words), so people actually use it
#   4. not a contraction typed without its apostrophe: SHES, CANT, WONT. That is when
#      SCOWL's contraction lists have the apostrophe form and it is at least 10 times as
#      common (Zipf +1) as the bare word; WELL (we'll) and SHELL (she'll) stay.
# It is EXTRA if 1, 2 and 4 hold and its frequency is between 2.0 and 2.5.
#
# TASTE. family.txt is every word in answers or extra that is, exactly as written, in
#   - LDNOOBW's English list (slurs and obscenities; CC BY 4.0), or
#   - family-extra.txt (ours: inflections LDNOOBW doesn't list and crude words, each one
#     written out in full).
# Those words stay real words: with the filter off they count like any other.
#
# Usage: python3 make_words.py <enable1.txt> <scowl-2020.12.07/final> <ldnoobw en> <out dir>
#   (wordfreq importable: pip install wordfreq==3.1.1)
import os, sys
from wordfreq import zipf_frequency

ANSWER_ZIPF = 2.5
EXTRA_ZIPF = 2.0
SCOWL_SIZES = (10, 20, 35, 40, 50)
SCOWL_KINDS = ('english-words', 'american-words', 'british-words')

def plain(w):
    return w.isascii() and w.isalpha() and w.islower() and 4 <= len(w) <= 9

def main(enable_path, scowl_dir, ldnoobw_path, out_dir):
    here = os.path.dirname(os.path.abspath(__file__))
    enable = {w.strip() for w in open(enable_path) if plain(w.strip())}
    scowl, apostrophes = read_scowl(scowl_dir)
    contraction = {}                              # bare word -> its apostrophe form
    for a in apostrophes:
        bare = a.replace("'", '')
        if plain(bare) and zipf_frequency(a, 'en') >= zipf_frequency(bare, 'en') + 1:
            contraction[bare] = a

    answers, extra, report = [], [], []
    for w in sorted(enable | scowl):
        z = zipf_frequency(w, 'en')
        why = []
        if w not in enable: why.append('not in ENABLE')
        if w not in scowl: why.append('not in SCOWL 10-50')
        if w in contraction: why.append('a contraction (%s)' % contraction[w])
        if not why and z >= ANSWER_ZIPF:
            answers.append(w)
        elif not why and z >= EXTRA_ZIPF:
            extra.append(w)
        else:
            if z < EXTRA_ZIPF: why.append('rare (zipf %.2f)' % z)
            report.append('%s\t%s' % (w, '; '.join(why)))

    listed = words_in(ldnoobw_path) | words_in(os.path.join(here, 'family-extra.txt'))
    family = sorted(w for w in set(answers) | set(extra) if w in listed)

    os.makedirs(out_dir, exist_ok=True)
    for name, rows in (('answers.txt', answers), ('extra.txt', extra),
                       ('family.txt', family), ('REPORT.txt', report)):
        with open(os.path.join(out_dir, name), 'w') as f:
            f.write('\n'.join(rows) + '\n')
    print('answers %d, extra %d, hidden by the family filter %d, left out %d'
          % (len(answers), len(extra), len(family), len(report)))

def read_scowl(scowl_dir):
    words, apostrophes = set(), set()
    for kind in SCOWL_KINDS:
        for size in SCOWL_SIZES:
            p = os.path.join(scowl_dir, '%s.%d' % (kind, size))
            if not os.path.exists(p):
                continue
            for line in open(p, encoding='latin-1'):
                w = line.strip()
                if plain(w):
                    words.add(w)
                elif "'" in w and w.replace("'", '').isalpha() and w.islower():
                    apostrophes.add(w)
    for size in SCOWL_SIZES:                      # contractions have files of their own
        p = os.path.join(scowl_dir, 'english-contractions.%d' % size)
        if os.path.exists(p):
            apostrophes |= {w.strip() for w in open(p, encoding='latin-1') if "'" in w}
    return words, apostrophes

def words_in(path):
    # one word per line; '#' starts a comment
    return {l.split('#')[0].strip() for l in open(path) if l.split('#')[0].strip()}

if __name__ == '__main__':
    main(*sys.argv[1:5])
