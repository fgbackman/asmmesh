# judge_family.py: decides the family filter from Wiktionary's own labels, not from a word
# list's reputation. For each word in words/family.txt it reads the word's English
# definitions in words/wiktionary.json (fetch_wiktionary.py) and their labels
# ({{lb|en|...}}, {{lbl|...}}, {{label|...}}). A word stays hidden only when Wiktionary marks
#   - its first definition, or
#   - half or more of its definitions
# with one of BAD (vulgar, offensive, derogatory, slur, pejorative, obscene, taboo...).
# Labels on a part of speech's headword line ({{tlb|en|vulgar}}) count for all its
# definitions. A word that is only a form of another (RAPED) is judged as that word.
# Plain "slang", "informal" or a topic ("sex", "anatomy") don't count: they say how a word
# is used, not that it is offensive.
# Writes words/family-judged.tsv (word, decision, counts, first definition) and prints it.
# Usage: python3 judge_family.py
import json, os, re

here = os.path.dirname(os.path.abspath(__file__))
BAD = {'vulgar', 'offensive', 'derogatory', 'slur', 'ethnic slur', 'pejorative', 'obscene',
       'taboo', 'profane', 'profanity', 'swear word', 'vulgar slang', 'offensive slang',
       'disparaging', 'ethnic slurs', 'homophobic slur', 'racial slur', 'sexual slur',
       'misogynistic', 'ableist', 'insulting'}
LABEL = re.compile(r'\{\{(?:lb|lbl|label|tlb)\|en\|([^}]*)\}\}')
QUAL = re.compile(r'\{\{(?:q|qual|qualifier|i|U)\|([^}]*)\}\}')   # e.g. {{U|offensive}}

def english(page):
    m = re.search(r'^==English==\s*$', page, re.M)
    if not m:
        return ''
    rest = page[m.end():]
    n = re.search(r'^==[^=].*==\s*$', rest, re.M)  # the next language
    return rest[:n.start()] if n else rest

FORM_OF = re.compile(r'\{\{(?:[a-z -]+ of|infl of|inflection of|en-[a-z ]+ of)\|en\|([^|}]+)')
HEADING = re.compile(r'^=+\s*([^=]+?)\s*=+\s*$')

def labels_in(text, pattern):
    out = set()
    for m in pattern.finditer(text):
        for a in m.group(1).split('|'):
            a = a.strip().lower()
            if a and '=' not in a and a not in ('_', 'or', 'and', 'chiefly', 'often', 'usually', 'sometimes', 'now'):
                out.add(a)
    return out

TLB = re.compile(r'\{\{tlb\|en\|([^}]*)\}\}')

def senses(page):
    # (labels, text, base) for each English definition. Labels on the headword line
    # ({{tlb|en|...}}) apply to every definition of that part of speech; base is set when
    # the definition only says the word is a form of another (RAPED: past tense of RAPE).
    out, section = [], set()
    for line in english(page).splitlines():
        if HEADING.match(line):
            section = set()
            continue
        if not line.startswith('#'):
            if line.startswith('{{'):              # the headword line: its labels cover all
                section |= labels_in(line, TLB) | labels_in(line, LABEL)
            continue
        if not re.match(r'^#(?![#:*])', line):
            continue
        labels = labels_in(line, LABEL) | labels_in(line, QUAL) | section
        base = FORM_OF.search(line)
        text = re.sub(r'\{\{[^}]*\}\}', '', line[1:])
        text = re.sub(r'\[\[(?:[^]|]*\|)?([^]]*)\]\]', r'\1', text).strip()
        out.append((labels, text, base.group(1).strip() if base else None))
    return out

def judge(w, pages, seen=()):
    s = senses(pages.get(w) or '')
    if not s:
        return None
    if all(b for _, _, b in s):                  # only a form of another word: as that word
        base = s[0][2]
        if base in pages and base not in seen:
            j = judge(base, pages, seen + (w,))
            if j:
                return (j[0], 'as ' + base + ': ' + j[1], j[2], j[3])
    own = [x for x in s if not x[2]]             # "form of" definitions don't count when
    s = own or s                                 #   the word has meanings of its own
    bad = [any(l in BAD for l in labels) for labels, _, _ in s]
    hide = bad[0] or 2 * sum(bad) >= len(bad)
    return ('hide' if hide else 'show', '%d of %d marked' % (sum(bad), len(s)),
            ','.join(sorted(s[0][0]))[:40], s[0][1][:70])

def main():
    pages = json.load(open(os.path.join(here, 'words', 'wiktionary.json')))
    rows = []
    for w in sorted(pages):
        j = judge(w, pages) or ('show', 'no English definitions', '', '')
        rows.append((w,) + j)
    with open(os.path.join(here, 'words', 'family-judged.tsv'), 'w') as f:
        f.write('word\tdecision\tlabelled\tfirst labels\tfirst definition\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    for r in rows:
        print('%-10s %-4s %-22s %-40s %s' % r)
    print('hide %d, show %d' % (sum(r[1] == 'hide' for r in rows), sum(r[1] == 'show' for r in rows)))

if __name__ == '__main__':
    main()
