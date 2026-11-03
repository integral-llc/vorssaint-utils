# layout-independent.tsv

Words the Layout Switcher's word lists have never seen, so the corpus gates
measure how it judges the unknown instead of how well it remembers. Columns:
`input`, `typedLayout`, `expectedDecision` (`switch` or `keep`), `class`.

| Class | Rows | Source |
|---|---|---|
| `unknown-ru` | 1000 words, typed right and on the English layout | LibreOffice `ru_RU.dic`, lowercase entries of 4+ letters |
| `unknown-en` | 1000 words, typed right and on the Russian layout | `web2` (`/usr/share/dict/web2`), lowercase entries of 4+ letters |
| `name-ru`, `name-en` | 500 each, typed right | capitalised entries of the same two lists |
| `typo-ru`, `typo-en` | 1000 each, typed right | one transposition, drop, neighbouring key or doubled letter in a word from the top 20,000 of `Resources/LayoutSwitcher/<language>_words.txt`; the result is in no list |
| `punctuation` | English tokens with file extensions, dotted names, contractions, quotes, angle brackets and abbreviations, typed right | `web2` words |
| `url` | 15 URLs, each typed through Russian - PC and typed right | written by hand |

"Never seen" means absent from `<language>_words.txt`,
`<language>_subtitle_words.txt` and the FrequencyWords 2018 50k lists.
Rows are picked in MD5 order of the word, so regenerating them from the same
sources gives the same file.

## Sources and licenses

- LibreOffice dictionaries, `ru_RU` at commit
  `4f1df64b2e8e14751aa7c2205d170ca016071315`
  (https://github.com/LibreOffice/dictionaries/tree/4f1df64b2e8e14751aa7c2205d170ca016071315/ru_RU).
  Copyright (c) 1997-2008, Alexander I. Lebedev. All rights reserved.
  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are
  met: redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer;
  redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution; modified versions
  must be clearly marked as such; the name of Alexander I. Lebedev may not
  be used to endorse or promote products derived from this software without
  specific prior written permission. THIS SOFTWARE IS PROVIDED BY THE
  COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
  EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
  OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
  SUCH DAMAGE.
  This fixture is a modified version: a sample of headwords with affix
  flags removed.
- `web2`, Webster's Second International (1934), as shipped in
  `/usr/share/dict/web2`. Its copyright has lapsed; public domain.
- The typo rows derive from the wordfreq-based word lists in
  `Resources/LayoutSwitcher`, CC BY-SA 4.0 (see that directory's README).
