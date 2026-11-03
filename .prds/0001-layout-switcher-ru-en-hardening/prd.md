# PRD-0001: Layout Switcher RU/EN hardening (WaySwitch lessons)

**Status:** done
**Created:** 2026-11-02
**Author:** Eugene Rata

---

## Problem Statement

Automatic mode in the Layout Switcher fixes words typed on the wrong keyboard layout between Russian and English. We compared it head to head with WaySwitch, an open-source Linux switcher for the same language pair. The same inputs went through both detectors: our labelled corpus, 6000 words neither dictionary carries, 6000 one-letter typos, 1832 proper names, 133k code tokens from this repo, and URLs.

What a user typing Russian and English runs into today:

0. **Everyday conversational words are missing from our word lists.** Our lists come from wordfreq, which leans on written sources. Chat-style forms (`позабочусь`, `облажался`, `перезвони`, `возражаешь`) are absent, so a wrong-layout typing of them is only "doubtful". The confidence gate then holds it back. WaySwitch's open-source lists (FrequencyWords, built from OpenSubtitles 2018) carry 5,620 Russian and 8,706 English words that ours lack. On those words we fix 84.6%, and 87% of the fixes come out low-confidence, so the gate holds most of them.
1. **Russian words outside our word list almost never get fixed when they contain б, ю or э.** Those letters sit on the comma, full-stop and apostrophe keys. A guard meant to protect `file.txt` and `example.com` refuses any such word unless it is in the dictionary. That is about 23% of Russian vocabulary: inflections, slang, rare words, names. Measured recall on Russian words unknown to both detectors: ours 71.7%, WaySwitch 98.5%.
2. **A URL typed on the Russian layout is never fixed.** `реезыЖ..пщщпдуюсщь` stays as typed instead of becoming `https://google.com`. We fixed 0 of 6 test URLs; WaySwitch fixed 6 of 6.
3. **The switcher fights the user.** If someone backspaces over an automatic correction and types the original word again by hand, we correct it again. Nothing reads a manual layout switch in the middle of a word as "I am fixing this myself" either.
4. **There is no way to keep automatic mode out of one app.** Terminals, IDEs, remote desktops and apps with odd text handling are where nearly all of our remaining false corrections happen (0.10% of code tokens). The only options are switching the whole feature off or putting up with it.
5. **Refused words are invisible.** One undo refuses a word forever, which is the right default. But the only way to take back an accidental refusal is "Forget learned words", which also wipes everything else.

What WaySwitch does worse, measured, and must not be copied: 6.38% false corrections on code tokens, 90% (vs our 98.3%) of two-way-valid words left alone, and an early 4th-letter trigger that misfires on 0.27% of English typos.

## Solution

Six changes, all limited to the Russian/English pair. Every other layout pair keeps exactly today's behaviour.

0. **Merge FrequencyWords into our word lists.** We reuse the open-source lists rather than build our own. Only words of 4 letters or more that we don't already have are added, with their frequencies converted to our scale. Measured: recall on those words goes from 84.6% to 100%, and the low-confidence share from 87% to 4%. False corrections are unchanged on the corpus, typos, names, punctuation tokens and 133k code tokens. Our character models stay as they are.
1. **Narrower punctuation guard.** For a ru/en pair, a word that needs a punctuation key to be a letter is refused only when the punctuation really looks machine-made: a quote or angle bracket, a leading dot or apostrophe, or any digit in the word. Ordinary Russian words with б, ю and э are judged like any other word. Measured: Russian unknown-word recall 71.7% to 92.3%; code false corrections 0.10% to 0.11%; no change on the corpus, filenames, domains, contractions or abbreviations.
2. **URL rule.** A finished token typed on the Russian layout whose English reading starts with `http://`, `https://`, `ftp://` or `www.` is rewritten to the English reading, and the layout follows.
3. **No more fighting.**
   - Retyping the original over an automatic correction counts as an undo: the word is left alone and refused from then on, the same as undoing with the shortcut.
   - A manual layout switch while a word is being typed means automatic mode leaves that word alone. Its own switches don't count.
4. **Per-app exclusions.** A list of apps in settings, empty by default, where automatic correction and vocabulary learning stop. The shortcut keeps working there because pressing it is a deliberate request.
5. **Refused words list.** Settings shows the words the user refused, and any single one can be removed without forgetting everything else.

Behind all of it: a test suite that reports false corrections and recall per language and per input class, using independent data, so the next regression shows up as a number.

## User Stories

1. As someone chatting in Russian, I want colloquial forms like `перезвони` and `облажался` typed on the English layout to be fixed at once, so that messenger-style text gets the same treatment as formal text.
2. As someone chatting in English, I want conversational words our list lacks to be recognised as English, so that they are known words, not doubtful ones.
3. As a user, I want junk entries from subtitle data (OCR errors, interjections, 2-3 letter fragments) kept out of the word lists, so that a wrong-layout word is never "valid" because of a typo in somebody's subtitles.
4. As a maintainer, I want the merged lists built by a deterministic script from a pinned source revision, so that the data can be rebuilt and audited.
5. As a maintainer, I want FrequencyWords credited next to wordfreq, with the shared CC BY-SA 4.0 license, so that the attribution obligations are met.
6. As a Russian speaker, I want a Russian word with б, ю or э that is missing from the dictionary to be fixed when I type it on the English layout, so that inflected and rare words are not left as gibberish.
7. As a Russian speaker, I want `j,yfhe;e` fixed to `обнаружу`, so that verb forms the word list lacks still get corrected.
8. As a developer, I want `file.txt`, `example.com`, `readme.md`, `e.g.`, `don't` and `o'brien` to stay untouched, so that narrowing the guard never breaks English text with punctuation.
9. As a developer typing Swift or other code, I want tokens like `.absent`, `"npm"`, `<div>` and `0.9][min(3,` to stay untouched, so that code is never turned into Cyrillic.
10. As a user, I want a quoted English word such as `"kaffiyeh"` left alone, so that quotation marks are never read as the letter Э.
11. As a user who typed a URL on the Russian layout, I want `реезыЖ..пщщпдуюсщь` to become `https://google.com` when I press space, so that I do not have to retype the address.
12. As a user, I want `цццюфзздуюсщь` to become `www.apple.com`, so that addresses without a scheme are fixed too.
13. As a user, I want the layout to switch to English after a URL is fixed, so that the rest of what I type lands right.
14. As a user, I want real Russian text never to be read as a URL, so that the URL rule cannot fire on prose.
15. As a user, I want a fixed URL to be undoable with the shortcut like any other correction, so that one undo gesture covers everything.
16. As a user who just backspaced over an automatic correction and typed the original word again, I want the switcher to leave it alone, so that we don't fight over my word.
17. As that same user, I want the word refused from then on, so that I never have to repeat the fight.
18. As a user, I want a manual revert to restore nothing else (no layout change, no extra text), so that my manual fix stays exactly as I typed it.
19. As a user who backspaced over a correction and typed a different word, I want that new word judged normally, so that revert detection doesn't swallow real mistakes.
20. As a user who noticed the wrong layout mid-word and switched it myself, I want automatic mode to leave that word alone, so that my own fix is not rewritten.
21. As a user, I want the next word after that judged normally, so that one manual switch does not turn automatic mode off for the sentence.
22. As a user, I want the switcher's own layout changes never to count as manual switches, so that its own correction does not suppress the next word.
23. As a user who works in a terminal, I want to add Terminal to an exclusion list, so that automatic mode never touches what I type there.
24. As a user, I want the exclusion list to start empty, so that nothing changes for me until I choose.
25. As a user, I want to pick apps for the list the same way I pick them for other features' exclusions, so that the interaction is familiar.
26. As a user, I want the shortcut to still convert the last word or the selection inside an excluded app, so that I keep a deliberate tool where automation is off.
27. As a privacy-conscious user, I want nothing I type in an excluded app to be counted into the learned vocabulary, so that exclusion also means "not remembered".
28. As a user switching from an excluded app to another app, I want the buffer and sentence context reset, so that nothing typed in the excluded app influences the next correction.
29. As a user, I want the exclusion list included in a settings backup, so that moving to a new Mac keeps it. Bundle identifiers are not typed text.
30. As a user, I want to see the words I refused in settings, so that I know why a word is no longer corrected.
31. As a user, I want to remove one refused word, so that an accidental undo does not cost me the correction forever.
32. As a user, I want "Forget learned words" to keep clearing everything, refused words included, so that the existing privacy control keeps its meaning.
33. As a user, I want the refused-words list to stay out of settings backups, so that typed words never travel off the machine, as today.
34. As a user with a pair other than Russian/English, I want behaviour identical to today, so that this work cannot regress my setup.
35. As a maintainer, I want recall and false-correction rates reported per language and per input class (dictionary words, unknown words, typos, names, code, URLs, punctuation tokens), so that a change that helps one class and hurts another is visible.
36. As a maintainer, I want the suite to fail when any class crosses its gate, so that tuning cannot quietly trade one class for another.
37. As a maintainer, I want test fixtures with a recorded source and license, so that shipping them in the repo is safe.
38. As a maintainer, I want the revert, layout-switch and exclusion rules tested as sequences of events without a real event tap, so that timing logic is pinned by tests and not by manual typing.

## Implementation Decisions

**Scope: Russian and English only.** The new detection rules (narrower guard, URL rule) run only when one side of the comparison is `ru` and the other `en`. For any other pair the existing code path runs unchanged. The behaviour rules (revert, layout guard, exclusions, refused list) don't depend on the language and apply to whatever automatic mode judges. Automatic mode only ships evidence for ru/en anyway.

**0. Word data merge.**
- Source: FrequencyWords 2018 lists for `ru` and `en` (OpenSubtitles, CC BY-SA 4.0), pinned to one upstream commit.
- Kept as is: every existing entry and its frequency.
- Added: FrequencyWords entries that are letters-only in the language's alphabet, at least 4 letters long, and not already present. The 4-letter floor drops the subtitle junk (`ёто`, `щрн`, `врн`) and the one extra code false correction the unfiltered merge caused.
- Frequency conversion: zipf = log10(count) + an offset per language. The offset is the median of (our zipf minus log10(count)) over the words both lists share, which keeps the scorer's thresholds valid without retuning. Measured offsets: ru +0.81, en +0.32 (42.6k and 38.0k shared words).
- Character models are not touched. Ours look 4 letters back and matched or beat WaySwitch's 3-letter models on every independent set.
- The merge is a script in the repo. It downloads the pinned files, verifies their checksums, merges, and writes the two word files byte-for-byte reproducibly.
- The language-data README records both sources, both licenses and the conversion rule.
- Merged size is about 105.6k Russian and 58.7k English entries. Loading stays off the main thread via the existing warm-up, and the first-load parse time is measured before and after.

**1. Token judgement: narrower punctuation guard.**
- Lives in the existing token-judgement extension of the scorer. No new public interface.
- Today: refuse a switch when ordinary punctuation would have to be a letter and the mapped word is not in the dictionary.
- New, for ru/en: refuse only when the typed core contains `"`, `<` or `>`, starts with `.` or `'`, or contains a digit. Otherwise judge it like any other word: still scored, margin and confidence gate unchanged.
- Variants that were measured and rejected:
  - Dropping the guard entirely: code false corrections rise to 0.32%.
  - A pattern rule for extensions and contractions: blocks Russian words with an inner ю.
  - Guarding only a leading dot: code 0.31%.

**2. URL rule.**
- A small pure recogniser, consulted for a finished token before the scorer: given the typed token, its mapped reading and both languages, it returns a rewrite or nothing.
- Fires only when the typed side is ru, the mapped side is en, and the mapped reading starts, case-insensitively, with `http://`, `https://`, `ftp://` or `www.`.
- The mapped reading comes from the glyph table built from the user's enabled layouts. Nothing is hardcoded, so it works for the "Russian" and "Russian - PC" layouts alike, as long as every character maps.
- The rewrite has high confidence (no gate), switches the layout, and is recorded as an automatic correction so the shortcut undoes it.
- The existing "looks structured" filter runs on the typed token. The Cyrillic spelling of a URL carries no `://`, `@` or `/`, so the filter does not block it. That is verified by a test, not assumed.

**3. Revert detection.**
- A small pure state tracker owns "the last automatic correction" and what happened to it since: still standing, contested (the user deleted back into it), or reverted.
- Contested: a Backspace sequence that empties the typing buffer and reaches into the corrected word.
- Reverted: the next finished token at that position equals the original typed token.
- Outcome of a revert: no rewrite, the word is refused through the existing vocabulary refusal, and the sentence context is reset, the same as a shortcut undo. Layout is not changed: the user already typed on the layout they wanted.
- Any other token at that position clears the contested state, and the token is judged normally.
- Today the last-correction record is cleared on the first non-space character. That moves into the tracker, so typing a different word keeps today's behaviour.

**4. Manual layout guard.**
- The service observes the selected-input-source notification. Other services in the app already do; the Layout Switcher does not yet.
- Switches the service makes itself (after a correction, or undoing one) are tagged before the call and ignored when the notification arrives.
- A manual switch while the typing buffer holds a word marks that word as skipped. Its finished token is neither rewritten nor counted into the vocabulary.
- The mark clears at the word boundary. The next word is judged normally.

**5. App exclusions.**
- New registered preference: a list of bundle identifiers, default empty, sanitised with the existing bundle-identifier sanitiser, included in settings export.
- A pure predicate decides "automatic mode allowed for this bundle identifier". It is checked when a finished word is about to be judged, using the frontmost app.
- In an excluded app: no automatic correction, no vocabulary recording, no context recording. Switching apps already resets context; the reset stays.
- The shortcut path does not consult the list.
- Settings uses the existing reusable app list component, the same one the Window Maximizer and Dock Preview exclusions use.

**6. Refused-words list.**
- The vocabulary store gains two operations: list refused words (most recent first) and remove one refused word. Removal persists at once, like refusal.
- Settings shows the list under the existing "Forget learned words" control, each row with a remove button. Empty state is one caption line.
- The storage key stays unregistered and outside settings export, as today. "Forget learned words" still clears everything.

**7. Strings.** Every new settings string goes into the Layout Switcher strings for every language the app ships, following the existing per-language pattern.

**Explicitly not changed:**
- Scorer weights and thresholds.
- Character models. Word lists change only through the merge in item 0.
- The confidence gate.
- Sentence context.
- The minimum length setting.
- Return handling.

## Testing Decisions

What makes a good test here: it feeds tokens or event sequences in and checks the rewrite, the refusal or the absence of action that comes out. No test reaches into the scorer's intermediate margins except where an existing test already does. Corpus gates measure the user-visible rate, not internal numbers.

Modules under test:

- **Word data merge.**
  - The merge script is tested on small inline inputs: existing entries untouched, short and non-alphabet entries dropped, offset computed from the overlap, output stable across runs.
  - The shipped lists must pass every existing corpus gate and every new class gate. In particular, no wrong-layout row in the corpus may turn into "keep" because a merged word now matches it.
- **Token judgement (guard).**
  - Unit cases: Russian words with б/ю/э typed on English that are missing from the dictionary.
  - Must stay untouched: `file.txt`, `example.com`, `readme.md`, `e.g.`, `test,`, `hello.`, `don't`, `"kaffiyeh"`, `.absent`, `<div>`.
  - Must keep passing: the existing `k.,k.`, `[kt,` and `руддщб` cases.
  - A non-ru/en pair runs through the old path unchanged.
- **URL recogniser.** All four prefixes, uppercase input, a long path, a Russian word that starts with the same letters but is not a URL, an English-typed URL left alone, and a token with an unmappable character left alone.
- **Revert tracker.** Event-sequence tests:
  - correct, backspace into the word, retype the original, space: refused, no rewrite;
  - same but a different word: judged;
  - correct, then type on: tracker cleared;
  - correct, backspace only the space, space again: no double rewrite.
- **Manual layout guard.** Sequences with an injected clock and injected notifications: a manual switch mid-word skips that word only; an own switch is ignored; a switch between words skips nothing.
- **App exclusion predicate.** Matching, non-matching, nil bundle identifier, and a sanitised list.
- **Vocabulary.** Listing order, removing one refused word, removing a word that is not there, persistence round trip, and "forget" still clearing the list. The existing check that the vocabulary key stays out of backups must still pass.
- **Independent corpus gates.** New fixtures with a recorded source and license:
  - Russian and English words absent from both the shipped word lists and WaySwitch's lists, each typed right and typed wrong. English from the public-domain web2 list; Russian from a dictionary whose license is verified first.
  - One-letter typos of real words typed on the right layout.
  - Proper names.
  - Code tokens taken from this repository.
  - URLs typed on the Russian layout.
  - Punctuation-bearing English tokens.

  Gates are set just below the measured values so they catch regressions without flaking:

  | Class | Gate |
  |---|---|
  | Russian unknown-word recall | at least 90% |
  | English unknown-word recall | at least 94% |
  | False corrections on unknown words | at most 0.1% |
  | False corrections on typos, each language | at most 0.15% |
  | False corrections on names | at most 0.2% |
  | False corrections on code tokens | at most 0.15% |
  | URL recall | 100% |
  | False corrections on punctuation tokens | 0 |

  The existing corpus gates stay as they are.

Prior art: the layout-detection test suite already loads a labelled TSV corpus, runs the same filter-plus-judgement path the app uses, prints rates and asserts gates. It also has stub evidence for unit cases and pure tests of the typing buffer, confidence gate and sentence context. New suites follow that shape and run under the same `--test-suite=layout-detection` switch.

## Out of Scope

- Any language pair other than Russian/English, including adding language data.
- WaySwitch's early switch at the 4th letter. Measured: same final text as our fix on space, 0.27% false corrections on English typos, misfires on German strings, and a race with fast typing during the mid-word rewrite.
- Stem or prefix matching as a confidence signal. Measured: recall up about 1%, typo false corrections roughly four times higher, and those fire with high confidence.
- Sensitivity presets. WaySwitch's "aggressive" costs 0.37% on typos.
- A configurable undo count. One undo stays the rule.
- Russian typo extras: particles (`чтото`), joined words, two capitals, accidental Caps Lock, `пирогб` to `пирог,`. Transliteration and number-to-words are out too.
- Fixing the whole phrase at once, and retroactively fixing a word the confidence gate held back.
- Pre-filled exclusions for terminals and IDEs.
- Replacing our scorer or character models with WaySwitch's.
- Adding FrequencyWords entries shorter than 4 letters.

## Further Notes

- Measurements come from a throwaway harness that compiled the shipped scorer sources against the shipped data and ran WaySwitch v1.0.0's detector on the same inputs. The independent fixtures in this PRD turn those one-off numbers into permanent gates.
- WaySwitch code is MIT; this PRD ports none of it. The word data comes from FrequencyWords, the upstream WaySwitch builds from, not from WaySwitch's repo. It is CC BY-SA 4.0, the same license as the wordfreq data already shipped, so the merged files stay under CC BY-SA 4.0 with both sources credited. Test fixture sources need their own license check before they are committed, recorded next to the fixture.
- Merge measurements were run with the narrower guard (item 1) already applied. The order in the tasks matters: data first, then gates, then rules, so each step's effect is visible on its own.
- Real-app checks before shipping: Notes, Safari address bar, Messages, Terminal, VS Code. Use both the "Russian" and "Russian - PC" input sources, because their punctuation keys differ and the URL rule depends on the user's actual table.
