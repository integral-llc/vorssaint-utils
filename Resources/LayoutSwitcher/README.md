# Layout switcher language data

One pair of files per language the automatic mode can judge:

- `<language>_words.txt`: `word<TAB>zipf`, one entry per line. Zipf runs from
  about 1 (rare) to about 7.5 (the commonest words).
- `<language>_charmodel.dat`: raw character n-gram counts, order 4, with `^`
  and `$` standing for the start and end of a word. The header line carries
  `order` and `total_unigrams`.

A language is judged only when both of its files are present. Both layouts of
a pair need one, otherwise automatic mode leaves that pair to the shortcut.

Derived from [wordfreq](https://github.com/rspeer/wordfreq) 3.1.1 (top 50,000
English and 100,000 Russian entries, letters only). The wordfreq data is
licensed CC BY-SA 4.0, and these files are distributed under the same terms.

The scorer's weights and thresholds in `LayoutDecisionScorer.swift` were tuned
against these exact files. Regenerate them and `./build.sh --test-suite=layout-detection`
has to pass its corpus gates again before anything ships.
