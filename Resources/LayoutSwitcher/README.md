# Layout switcher language data

One pair of files per language the automatic mode can judge:

- `<language>_words.txt`: `word<TAB>zipf`, one entry per line. Zipf runs from
  about 1 (rare) to about 7.5 (the commonest words).
- `<language>_charmodel.dat`: weighted character n-gram counts, order 3,
  with `^` and `$` standing for the start and end of a word. The header line
  carries `order` and the Kneser-Ney `discount` the counts are read with.

A language is judged only when both of its files are present. Both layouts of
a pair need one, otherwise automatic mode leaves that pair to the shortcut.

The word lists derive from [wordfreq](https://github.com/rspeer/wordfreq)
3.1.1 (top 50,000 English and 100,000 Russian entries, letters only). The
wordfreq data is licensed CC BY-SA 4.0, and these files are distributed under
the same terms.

The character models are built by `Tools/build-layout-charmodel.py` from the
FrequencyWords 50k lists named below: every n-gram of every entry, counted
ln(1 + occurrences) times, so the models describe the text people type rather
than a dictionary. Same source commit, checksums and license as the subtitle
lists. Order 3 with interpolated Kneser-Ney smoothing beat orders 4 and 5,
additive smoothing and unweighted counts on words no list carries, which is
the only place the models decide anything.

`<language>_subtitle_words.txt` is optional and only adds words: chat words
the written-text list misses (`перезвони`, `облажался`). Same format, read
after `<language>_words.txt`, which wins wherever both carry a word. Built by
`Tools/build-layout-subtitle-words.py` from
[FrequencyWords](https://github.com/hermitdave/FrequencyWords) (OpenSubtitles
2018, content CC BY-SA 4.0) at commit
`525f9b560de45753a5ea01069454e72e9aa541c6`, checksums pinned in the script:

- Only words of 4+ letters in the language's alphabet that the main list lacks.
- zipf = log10(count) + the median of (zipf - log10(count)) over the words
  both lists share, so the scorer's thresholds hold without retuning.
- Dropped as not Russian or English: words another FrequencyWords language
  uses far more often (10x for English, 100x for Russian, which shares
  imperatives with Bulgarian), Russian text read in the wrong code page, and
  OCR that lost a first letter.

The scorer's weights and thresholds in `LayoutDecisionScorer.swift` were tuned
against these exact files. Regenerate them and `./build.sh --test-suite=layout-detection`
has to pass its corpus gates again before anything ships.
