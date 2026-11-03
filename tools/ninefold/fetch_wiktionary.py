# fetch_wiktionary.py: downloads the raw Wiktionary page (wikitext) of every word the family
# filter hides (words/family.txt), so its labels (vulgar, offensive, derogatory, slur) can be
# read. Only fetches and saves; judge_family.py reads the labels and decides.
# Run it anywhere with internet (it uses nothing but Python 3's standard library):
#   python3 tools/ninefold/fetch_wiktionary.py
# It writes tools/ninefold/words/wiktionary.json (about 100 pages; takes about a minute).
import json, os, sys, time, urllib.parse, urllib.request

here = os.path.dirname(os.path.abspath(__file__))
words = [w.strip() for w in open(os.path.join(here, 'words', 'family.txt')) if w.strip()]
out, failed = {}, []
for i, w in enumerate(words, 1):
    url = 'https://en.wiktionary.org/w/index.php?action=raw&title=' + urllib.parse.quote(w)
    req = urllib.request.Request(url, headers={'User-Agent': 'ninefold-word-check/1.0 (one-off label check)'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            out[w] = r.read().decode('utf-8')
    except Exception as e:                      # a missing page is an answer too: no labels
        out[w] = None
        failed.append('%s (%s)' % (w, e))
    print('%3d/%d %s' % (i, len(words), w), file=sys.stderr)
    time.sleep(0.4)                              # gently: one page at a time
path = os.path.join(here, 'words', 'wiktionary.json')
json.dump(out, open(path, 'w'), ensure_ascii=False, indent=0)
print('saved %d pages to %s' % (len(out), path))
if failed:
    print('no page for: ' + ', '.join(failed))
