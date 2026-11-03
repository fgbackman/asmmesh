# Where Ninefold's words come from

`make_words.py` builds `words/answers.txt` and `words/extra.txt` on accuracy alone: a word
counts only when ENABLE, SCOWL and wordfreq agree and it isn't a contraction without its
apostrophe. `words/family.txt` is separate: the words the family filter hides (a game
setting). They stay real words, and count with the filter off (see the top of
`make_words.py`). Rebuilding also writes
`words/REPORT.txt` (not kept in git, about 3 MB): every word left out, and why.

| Source              | Version       | Used for                                 | Licence                                                    |
|---------------------|---------------|------------------------------------------|------------------------------------------------------------|
| ENABLE2K            | enable1.txt   | is it a valid word (no names, no abbreviations) | public domain                                       |
| SCOWL               | 2020.12.07    | is it an ordinary dictionary word (sizes 10-50) | copyright Kevin Atkinson; free use with this notice kept (see SCOWL's README) |
| wordfreq            | 3.1.1         | do people actually use it (Zipf frequency) | data CC BY-SA 4.0, code Apache 2.0 (Robyn Speer)         |
| LDNOOBW `en`        | commit 5faf2ba | the family filter only: words hidden as written there, never variants | CC BY 4.0 (Shutterstock and contributors) |
| `family-extra.txt`  | here          | the family filter only: forms LDNOOBW lacks (RAPED) and crude words, each in full | ours |

Get them:
- ENABLE: https://raw.githubusercontent.com/dolph/dictionary/master/enable1.txt
- SCOWL: https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz
- wordfreq: `pip install wordfreq==3.1.1`
- LDNOOBW: https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/5faf2ba42d7b1c0977169ec3611df25a3c08eb13/en

Contractions without their apostrophe (SHES, CANT, WONT) are left out when SCOWL's
`english-contractions` lists the apostrophe form and it is at least 10 times as common.

Check any sample of puzzles: `python3 samples.py 200 7 > samples.md` then
`python3 check_samples.py samples.md` (every word fits its tiles, has the centre letter, is
in its list, and nothing that fits is missing).

Because the frequency cut-off uses wordfreq's data, the lists carry its CC BY-SA 4.0 terms:
credit wordfreq when they ship, and share changes to them the same way.
