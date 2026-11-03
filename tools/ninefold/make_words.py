# make_words.py: builds Ninefold's word lists from three independent sources, so that no
# single list decides what is a word. Run it again to rebuild; the output must not change
# unless a source does (its version is pinned below).
#
#   answers.txt   the words a round counts, reveals and says you missed
#   extra.txt     real words that are rarer: they score, but are never shown as missed
#   REPORT.txt    every word left out, and the reason, for anyone who wants to check
#
# A word (4 to 9 letters a-z, lower case) is an ANSWER if all three agree:
#   1. ENABLE2K       public domain: the word is valid (no proper nouns or abbreviations)
#   2. SCOWL 2020.12.07, sizes 10-50 (English, American, British): a spell checker's list
#                     of common words, so it is an ordinary dictionary word
#   3. wordfreq 3.x   Zipf frequency >= 2.5 in English text (books, news, subtitles, the
#                     web): people actually use it. 2.5 is about once in 3 million words.
# It is EXTRA if 1 and 2 agree and its frequency is between 2.0 and 2.5.
# Neither, whatever the sources say:
#   - a word on LDNOOBW's English list (slurs, obscenities; CC BY 4.0), or one of its plain
#     inflections (-s, -es, -d, -ed, -ing, -er, -ers): RAPE takes RAPED and RAPES with it
#   - a word in blocked.txt (our own short list: crude words a family game leaves out)
#   except the words in allowed.txt: ordinary words LDNOOBW catches (BUTTER, ESCORT, SPICES)
#   - a contraction without its apostrophe: SHES, CANT. Left out when SCOWL has the
#     apostrophe form and it is 10 times as common (zipf +1) as the bare word, so WELL
#     (we'll) and SHELL stay, SHES (she's), CANT (can't) and WONT (won't) go.
#
# Usage: python3 make_words.py <enable1.txt> <scowl-2020.12.07/final> <ldnoobw en> <out dir>
#   (wordfreq must be importable: pip install wordfreq==3.1.1)
import os, sys
from wordfreq import zipf_frequency

ANSWER_ZIPF = 2.5
EXTRA_ZIPF = 2.0
SCOWL_SIZES = (10, 20, 35, 40, 50)
SCOWL_KINDS = ('english-words', 'american-words', 'british-words')

def plain(w):
    return w.isascii() and w.isalpha() and w.islower() and 4 <= len(w) <= 9

SUFFIXES = ('', 's', 'es', 'd', 'ed', 'ing', 'er', 'ers')

def main(enable_path, scowl_dir, ldnoobw_path, out_dir):
    here = os.path.dirname(os.path.abspath(__file__))
    enable = {w.strip() for w in open(enable_path) if plain(w.strip())}
    scowl, apostrophes = set(), set()
    for kind in SCOWL_KINDS:
        for size in SCOWL_SIZES:
            p = os.path.join(scowl_dir, '%s.%d' % (kind, size))
            if os.path.exists(p):
                for line in open(p, encoding='latin-1'):
                    w = line.strip()
                    if plain(w):
                        scowl.add(w)
                    elif "'" in w and w.replace("'", '').isalpha() and w.islower():
                        apostrophes.add(w)
        for size in SCOWL_SIZES:                  # contractions have files of their own
            p = os.path.join(scowl_dir, 'english-contractions.%d' % size)
            if kind == 'english-words' and os.path.exists(p):
                apostrophes |= {w.strip() for w in open(p, encoding='latin-1') if "'" in w}
    contraction = {}                          # bare word -> its apostrophe form
    for a in apostrophes:
        bare = a.replace("'", '')
        if plain(bare) and zipf_frequency(a, 'en') >= zipf_frequency(bare, 'en') + 1:
            contraction[bare] = a
    base = {w.strip() for w in open(ldnoobw_path) if w.strip().isalpha() and w.strip().islower()}
    house = {w.strip() for w in open(os.path.join(here, 'blocked.txt')) if w.strip() and not w.startswith('#')}
    blocked = {}
    for w in base:
        for suf in SUFFIXES:
            blocked.setdefault(w + suf, 'blocked (LDNOOBW: %s)' % w)
    for w in house:
        blocked[w] = 'blocked (blocked.txt)'
    allowed = {l.split('#')[0].strip() for l in open(os.path.join(here, 'allowed.txt')) if l.split('#')[0].strip()}
    for w in allowed:
        blocked.pop(w, None)

    answers, extra, report = [], [], []
    for w in sorted(enable | scowl):
        z = zipf_frequency(w, 'en')
        why = []
        if w in blocked: why.append(blocked[w])
        if w in contraction: why.append("a contraction (%s)" % contraction[w])
        if w not in enable: why.append('not in ENABLE')
        if w not in scowl: why.append('not in SCOWL 10-50')
        if not why and z >= ANSWER_ZIPF:
            answers.append(w)
        elif not why and z >= EXTRA_ZIPF:
            extra.append(w)
        else:
            if z < EXTRA_ZIPF: why.append('rare (zipf %.2f)' % z)
            report.append('%s\t%s' % (w, '; '.join(why)))
    os.makedirs(out_dir, exist_ok=True)
    for name, rows in (('answers.txt', answers), ('extra.txt', extra), ('REPORT.txt', report)):
        with open(os.path.join(out_dir, name), 'w') as f:
            f.write('\n'.join(rows) + '\n')
    print('answers %d, extra %d, left out %d' % (len(answers), len(extra), len(report)))

if __name__ == '__main__':
    main(*sys.argv[1:5])
