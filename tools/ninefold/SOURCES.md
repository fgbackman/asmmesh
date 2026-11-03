# Where Ninefold's words come from

`make_words.py` builds `words/answers.txt` and `words/extra.txt` from three sources. A word
counts only when they agree (see the top of `make_words.py`). Rebuilding also writes
`words/REPORT.txt` (not kept in git, about 3 MB): every word left out, and why.

| Source              | Version       | Used for                                 | Licence                                                    |
|---------------------|---------------|------------------------------------------|------------------------------------------------------------|
| ENABLE2K            | enable1.txt   | is it a valid word (no names, no abbreviations) | public domain                                       |
| SCOWL               | 2020.12.07    | is it an ordinary dictionary word (sizes 10-50) | copyright Kevin Atkinson; free use with this notice kept (see SCOWL's README) |
| wordfreq            | 3.1.1         | do people actually use it (Zipf frequency) | data CC BY-SA 4.0, code Apache 2.0 (Robyn Speer)         |

Get them:
- ENABLE: https://raw.githubusercontent.com/dolph/dictionary/master/enable1.txt
- SCOWL: https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz
- wordfreq: `pip install wordfreq==3.1.1`

Because the frequency cut-off uses wordfreq's data, the lists carry its CC BY-SA 4.0 terms:
credit wordfreq when they ship, and share changes to them the same way.
