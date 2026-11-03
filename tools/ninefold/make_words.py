# make_words.py: builds Ninefold's word lists. Accuracy decides what is a word; taste is a
# separate, visible layer on top (the family filter), so no moral call can cost a real word.
# Run it again to rebuild; the output must not change unless a source does (versions pinned).
# The rules below were chosen by measuring them against 595 puzzles curated by hand
# (benchmark.py, which prints the current figures).
#
#   answers.txt   the words a round counts, reveals and says you missed
#   extra.txt     real words that are rarer, or spelled the American way: they score, but
#                 are never shown as missed
#   family.txt    words the family filter hides (a game setting, on by default): see TASTE
#   family-candidates.txt  the words judge_family.py looks up (fetch_wiktionary.py reads it)
#   REPORT.txt    every word left out, and why (not in git: ~3 MB)
#
# A REAL WORD (4 to 9 letters a-z) is in all of:
#   1. ENABLE2K (public domain): a valid word, so no names or abbreviations
#   2. SCOWL 2020.12.07 words, sizes 10-60, any spelling (English, American, British).
#      Size 70 and up is where obscure words (TOLA, TAIN, AIRT) come in.
#   and is not:
#   - a contraction typed without its apostrophe (SHES, CANT, WONT): SCOWL's contraction
#     lists have the apostrophe form and it is at least 10 times as common (Zipf +1) as the
#     bare word. WELL (we'll) and SHELL (she'll) stay.
#   - a plural, or a verb's -s form (they're spelled the same): OATS, CARS, RUNS, YEARS,
#     PARENTS, CARBS. See plural_of() for the exact rule (WordNet 3.0 does the grammar).
#     NEWS, ALWAYS, ALAS, SERIES, LENS, BONUS, PHYSICS, POLITICS and OURS stay; nouns that
#     only come in the plural (PANTS, SCISSORS) are plural in form, so they go.
# An ANSWER is a real word that is also
#   3. in SCOWL's English or British lists (British spelling: COLOUR, not COLOR)
#   4. common: wordfreq 3.1.1 Zipf frequency >= ANSWER_ZIPF
#   5. not a name in disguise: a word SCOWL also has capitalised (Anna, Logan, Kent) is an
#      answer only if SCOWL sizes 10-50 have it in lower case too (CHINA, BRAD). wordfreq
#      can't tell "Anna" from "anna", so a name's frequency would pass for the word's. Such
#      a word is still a real word (ORCA, BRIE, LIDO): it is extra.
# Any other real word with Zipf >= EXTRA_ZIPF is EXTRA; rarer ones aren't accepted.
#
# TASTE. family.txt is decided by a dictionary, not by a list's reputation. Candidates are
# words in answers or extra that are, exactly as written, in
#   - LDNOOBW's English list (slurs and obscenities; CC BY 4.0), or
#   - family-extra.txt (ours: inflections LDNOOBW doesn't list and crude words, each one
#     written out in full).
# Each candidate's Wiktionary page (fetch_wiktionary.py) is read by judge_family.py: it is
# hidden only if Wiktionary labels its first meaning, or half or more of its meanings,
# vulgar, offensive, derogatory or a slur (words/family-judged.tsv, with the counts). So
# BUTT, ESCORT, SKEET and SNATCH show; CUNT and the slurs don't.
# Those words stay real words: with the filter off they count like any other.
#
# Usage: python3 make_words.py <enable1.txt> <scowl-2020.12.07/final> <ldnoobw en> <out dir>
#   (pip install wordfreq==3.1.1 nltk==3.10.4, and WordNet: NLTK_DATA pointing at a folder
#   with corpora/wordnet from nltk_data)
import glob, os, sys
from wordfreq import zipf_frequency
from nltk.corpus import wordnet

ANSWER_ZIPF = 2.75
EXTRA_ZIPF = 2.0
SCOWL_SIZES = (10, 20, 35, 40, 50, 55, 60)
COMMON_SIZES = (10, 20, 35, 40, 50)
ALL_KINDS = ('english-words', 'american-words', 'british-words')
BRITISH_KINDS = ('english-words', 'british-words')

def plain(w):
    return w.isascii() and w.isalpha() and w.islower() and 4 <= len(w) <= 9

def main(enable_path, scowl_dir, ldnoobw_path, out_dir):
    here = os.path.dirname(os.path.abspath(__file__))
    enable_all = {w.strip() for w in open(enable_path) if w.strip()}
    enable = {w for w in enable_all if plain(w)}
    real_scowl = scowl_words(scowl_dir, ALL_KINDS, SCOWL_SIZES)
    british = scowl_words(scowl_dir, BRITISH_KINDS, SCOWL_SIZES)
    common = scowl_words(scowl_dir, ALL_KINDS, COMMON_SIZES)
    names = scowl_names(scowl_dir)
    base_words = enable_all | scowl_words(scowl_dir, ALL_KINDS, (10, 20, 35, 40, 50, 55, 60, 70, 80, 95), short=True)
    common_base = scowl_words(scowl_dir, ALL_KINDS, SCOWL_SIZES, short=True)
    contraction = contractions(scowl_dir)

    answers, extra, report = [], [], []
    for w in sorted(enable | real_scowl):
        z = zipf_frequency(w, 'en')
        why = []
        if w not in enable: why.append('not in ENABLE')
        if w not in real_scowl: why.append('not in SCOWL 10-70')
        if w in contraction: why.append('a contraction (%s)' % contraction[w])
        base = plural_of(w, base_words, common_base)
        if base: why.append('a plural or -s form (%s)' % base)
        if not why and z < EXTRA_ZIPF: why.append('rare (zipf %.2f)' % z)
        if why:
            report.append('%s\t%s' % (w, '; '.join(why)))
            continue
        if w in british and z >= ANSWER_ZIPF and (w not in names or w in common):
            answers.append(w)
        else:
            extra.append(w)

    listed = words_in(ldnoobw_path) | words_in(os.path.join(here, 'family-extra.txt'))
    judged = {}                                   # judge_family.py: Wiktionary's own labels
    jpath = os.path.join(here, 'words', 'family-judged.tsv')
    if os.path.exists(jpath):
        for line in open(jpath).read().splitlines()[1:]:
            cols = line.split('\t')
            judged[cols[0]] = cols[1]
    # a listed word is hidden unless Wiktionary's labels say it isn't offensive; a word
    # not judged yet stays hidden until it is (fetch_wiktionary.py, judge_family.py)
    candidates = sorted(w for w in set(answers) | set(extra) if w in listed)
    family = [w for w in candidates if judged.get(w, 'hide') == 'hide']

    os.makedirs(out_dir, exist_ok=True)
    for fname, rows in (('answers.txt', answers), ('extra.txt', extra),
                        ('family.txt', family), ('family-candidates.txt', candidates),
                        ('REPORT.txt', report)):
        with open(os.path.join(out_dir, fname), 'w') as f:
            f.write('\n'.join(rows) + '\n')
    print('answers %d, extra %d, hidden by the family filter %d, left out %d'
          % (len(answers), len(extra), len(family), len(report)))

PRONOUNS = {'ours', 'yours', 'hers', 'theirs', 'whose'}   # end in s, are no plurals

def plural_of(w, base_words, common_base):
    # the base form if w is a plural or a verb's -s form (OATS -> OAT, RUNS -> RUN,
    # PARENTS -> PARENT, CARBS -> CARB), else None. Bases are WordNet's (_morphy) and the
    # word less -s, -es, or -ies + y, when the base is a word (ENABLE or SCOWL).
    #   - a base WordNet has as a noun or verb makes w a plural, unless w is an adverb whose
    #     -s form is the usual one (ALAS, not LOTS)
    #   - a base WordNet doesn't know (BIKER, CARB, CELEB) makes w a plural if SCOWL's
    #     sizes 10-60 have it, or WordNet doesn't list w itself (ALWAYS stays: ALWAY is
    #     only a rare ENABLE word)
    #   - a base WordNet has only as an adjective (VISUAL, ILLEGAL, OTHER) makes w a plural
    #     unless WordNet lists w itself as a word: NEWS (NEW) stays
    # Fields named -ICS that WordNet lists (PHYSICS, POLITICS) are words of their own;
    # CLINICS, TOPICS aren't. Nouns that only come in the plural (PANTS, SCISSORS) are
    # plural in form, so they go too.
    if not w.endswith('s') or w.endswith('ss') or w in PRONOUNS:
        return None
    own = {s.pos() for s in wordnet.synsets(w) if w in [l.name() for l in s.lemmas()]}
    if w.endswith('ics') and 'n' in own:
        return None
    bases = [b for pos in (wordnet.NOUN, wordnet.VERB) for b in wordnet._morphy(w, pos) if b != w]
    bases += [w[:-1]]
    if w.endswith('es'): bases.append(w[:-2])
    if w.endswith('ies'): bases.append(w[:-3] + 'y')
    for base in bases:
        if base not in base_words:
            continue
        if wordnet.synsets(base, wordnet.NOUN) or wordnet.synsets(base, wordnet.VERB):
            if 'r' in own and zipf_frequency(w, 'en') > zipf_frequency(base, 'en'):
                continue
            return base
        if wordnet.synsets(base):             # an adjective used as a noun: VISUALS, OTHERS
            if not own:
                return base
        elif base in common_base or not own:  # WordNet doesn't know it: BIKER, CARB
            return base
    return None

def scowl_words(scowl_dir, kinds, sizes, short=False):
    # short: any length, for base forms (CAR, TEA)
    ok = (lambda w: w.isascii() and w.isalpha() and w.islower()) if short else plain
    words = set()
    for kind in kinds:
        for size in sizes:
            p = os.path.join(scowl_dir, '%s.%d' % (kind, size))
            if os.path.exists(p):
                words |= {w.strip() for w in open(p, encoding='latin-1') if ok(w.strip())}
    return words

def scowl_names(scowl_dir):
    # every capitalised word SCOWL has (names, places, brands), lower-cased
    names = set()
    for p in glob.glob(os.path.join(scowl_dir, '*proper-names.*')) + glob.glob(os.path.join(scowl_dir, '*-upper.*')):
        for line in open(p, encoding='latin-1'):
            w = line.strip()
            if w[:1].isupper() and w.isalpha():
                names.add(w.lower())
    return names

def contractions(scowl_dir):
    # bare word -> its apostrophe form, when that form is 10 times as common
    forms = set()
    for p in glob.glob(os.path.join(scowl_dir, '*-words.*')) + glob.glob(os.path.join(scowl_dir, 'english-contractions.*')):
        size = p.rsplit('.', 1)[1]
        if not size.isdigit() or int(size) > 60:
            continue
        for line in open(p, encoding='latin-1'):
            w = line.strip()
            if "'" in w and w.replace("'", '').isalpha() and w.islower():
                forms.add(w)
    out = {}
    for a in forms:
        bare = a.replace("'", '')
        if plain(bare) and zipf_frequency(a, 'en') >= zipf_frequency(bare, 'en') + 1:
            out[bare] = a
    return out

def words_in(path):
    # one word per line; '#' starts a comment
    return {l.split('#')[0].strip() for l in open(path) if l.split('#')[0].strip()}

if __name__ == '__main__':
    main(*sys.argv[1:5])
