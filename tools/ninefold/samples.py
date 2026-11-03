# samples.py: N sample puzzles, made the way the game makes them, for review.
# Each: a 9-letter answer (no other 9-letter anagram among the answers), a centre letter
# leaving 15-60 answers, then every answer and every "also accepted" word of 4+ letters
# that the nine tiles make with the centre letter in it. Pure counting, no judgement.
# Usage: python3 samples.py 200 7 > ../../docs/ninefold/samples-200.md
import random, sys
from collections import Counter

here = sys.path[0]
ANS = [w.strip() for w in open(here + '/words/answers.txt') if w.strip()]
EXT = [w.strip() for w in open(here + '/words/extra.txt') if w.strip()]
FAMILY = {w.strip() for w in open(here + '/words/family.txt') if w.strip()}

def fits(word, tiles):
    need, have = Counter(word), Counter(tiles)
    return all(need[k] <= have[k] for k in need)

def main(n, seed):
    rnd = random.Random(seed)
    nines = [w for w in ANS if len(w) == 9]
    by_letters = Counter(''.join(sorted(w)) for w in nines)
    unique = [w for w in nines if by_letters[''.join(sorted(w))] == 1]
    rnd.shuffle(unique)
    ans_c = [(w, Counter(w)) for w in ANS]
    ext_c = [(w, Counter(w)) for w in EXT]
    out, used = [], set()
    for nine in unique:
        if len(out) >= n:
            break
        tiles = Counter(nine)
        # only words that fit the nine tiles at all
        a_fit = [w for w, c in ans_c if all(c[k] <= tiles[k] for k in c)]
        e_fit = [w for w, c in ext_c if all(c[k] <= tiles[k] for k in c)]
        centres = [ch for ch in sorted(set(nine)) if 15 <= sum(ch in w for w in a_fit) <= 60]
        if not centres:
            continue
        ch = rnd.choice(centres)
        answers = sorted((w for w in a_fit if ch in w), key=lambda w: (-len(w), w))
        extra = sorted((w for w in e_fit if ch in w), key=lambda w: (-len(w), w))
        out.append((nine, ch, answers, extra))
    print('# Ninefold: %d sample puzzles\n' % len(out))
    print('Made by `tools/ninefold/samples.py %d %d` from `words/answers.txt` and `words/extra.txt`.' % (n, seed))
    print('Rule: words of 4-9 letters, using the centre letter, each tile at most once.')
    print('"Also accepted" words are real but rarer: they score, but are never shown as missed.')
    print('Every word is listed, accurate or not to taste. Words the family filter would hide')
    print('(a game setting, on by default) are named again on their own line, so nothing is out of view.')
    print('`tools/ninefold/check_samples.py` checks this file independently.\n')
    for i, (nine, ch, answers, extra) in enumerate(out, 1):
        print('## %d. %s (centre %s): %d answers' % (i, nine.upper(), ch.upper(), len(answers)))
        print(', '.join(w.upper() for w in answers))
        print('Also accepted (%d): %s' % (len(extra), ', '.join(w.upper() for w in extra) or '-'))
        hidden = [w for w in answers + extra if w in FAMILY]
        print('Family filter hides (%d): %s\n' % (len(hidden), ', '.join(w.upper() for w in hidden) or '-'))

if __name__ == '__main__':
    main(int(sys.argv[1]), int(sys.argv[2]))
