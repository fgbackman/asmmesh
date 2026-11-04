# make_chat_filter.py: writes src/cf_words.inc, the chat filter's words (cf_core.s), from
# words/family.txt: the words Wiktionary labels vulgar, offensive, derogatory or a slur
# (judge_family.py). Plus short ones family.txt can't have (it holds 4-9 letters only),
# each also judged there, kept in family-short.txt. Run it again after the lists change.
import os
here = os.path.dirname(os.path.abspath(__file__))
words = set(open(os.path.join(here, 'words', 'family.txt')).read().split())
short = os.path.join(here, 'family-short.txt')
if os.path.exists(short):
    words |= {l.split('#')[0].strip() for l in open(short) if l.split('#')[0].strip()}
words = sorted(w for w in words if w.isascii() and w.isalpha() and w.islower() and len(w) <= 15)
out = os.path.join(here, '..', '..', 'src', 'cf_words.inc')
with open(out, 'w') as f:
    f.write('// cf_words.inc — made by tools/ninefold/make_chat_filter.py: the chat filter\'s words\n')
    f.write('Lcf_words:\n')
    for w in words:
        f.write('    .asciz "%s"\n' % w)
    f.write('    .byte 0\n')
print('%d words -> %s' % (len(words), out))
