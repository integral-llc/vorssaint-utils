# PRD-0001: Layout Switcher RU/EN hardening (WaySwitch lessons) - Tasks

Derived from [prd.md](./prd.md). Update as implementation progresses. Each task is test-first: a failing test, then the change, then the gates.

## Tasks

### 0. Word data merge
- [x] Pin a FrequencyWords commit and record checksums of the 2018 `ru_50k` and `en_50k` files (language data)
- [x] Tests for the merge script on inline inputs: existing entries kept, short and non-alphabet entries dropped, overlap offset, stable output (tools)
- [x] Merge script in the repo: download pinned files, verify checksums, add entries of 4+ letters, convert counts to zipf by the median overlap offset, write reproducible word files (tools)
- [x] Regenerate both word files; character models untouched (language data)
- [x] Credit FrequencyWords, its license and the conversion rule in the language-data README (language data)
- [x] Measure first-load parse time before and after; warm-up stays off the main thread (language evidence)
- [x] Run `./build.sh --test-suite=layout-detection`: existing corpus gates must stay green

### Test foundation (before the rule changes, so each one is measured)
- [x] Verify licenses for fixture sources (web2 public domain; pick a Russian dictionary with a permissive license) and record them next to the fixtures (test fixtures)
- [x] Add independent fixtures: unknown-word ru/en (right and wrong layout), typos, names, code tokens from this repo, Russian-layout URLs, punctuation tokens (test fixtures)
- [x] Extend the layout-detection suite to report and gate each class per language; current code must fail only the Russian unknown-word and URL gates (layout detection tests)

### 1. Narrower punctuation guard
- [x] Unit cases: б/ю/э words outside the dictionary switch; `file.txt`, `example.com`, `readme.md`, `e.g.`, `don't`, `"kaffiyeh"`, `.absent`, `<div>` stay; a non-ru/en pair takes the old path (layout detection tests)
- [x] Narrow the guard for ru/en pairs only (token judgement)
- [x] Run the full layout-detection suite: existing corpus gates unchanged, new class gates green

### 2. URL rule
- [x] Unit cases for the recogniser: four prefixes, uppercase, long path, near-miss Russian word, English-typed URL, unmappable character (layout detection tests)
- [x] Test that the structured-token filter lets the Cyrillic spelling of a URL through (layout switcher support)
- [x] Add the pure URL recogniser and consult it before the scorer for ru-typed tokens (token judgement / service outcome)
- [x] URL rewrite recorded as an automatic correction so the shortcut undoes it (layout switcher service)

### 3. Revert detection
- [x] Event-sequence tests: retype original refuses, different word judged, typing on clears, backspace-space-space no double rewrite (layout detection tests)
- [x] Extract the last-automatic-correction state into a pure tracker; keep current behaviour green (layout switcher support)
- [x] Add contested and reverted states; on revert refuse through vocabulary and reset context, no layout change (tracker + service)

### 4. Manual layout guard
- [x] Sequence tests with injected clock and notifications: manual mid-word switch skips that word only, own switch ignored, switch between words skips nothing (layout detection tests)
- [x] Observe selected-input-source changes; tag own switches before selecting (layout switcher service)
- [x] Skip rewrite and vocabulary recording for a word marked by a manual switch (layout switcher service)

### 5. App exclusions
- [x] Predicate tests: match, no match, nil bundle id, sanitised list (layout detection tests)
- [x] Register the preference (default empty, included in settings export) (defaults)
- [x] Gate automatic judgement, vocabulary and context recording on the frontmost app; shortcut path untouched (layout switcher service)
- [x] Settings section using the shared app list component (layout switcher settings)
- [x] Strings for every shipped language (layout switcher strings)

### 6. Refused-words list
- [x] Vocabulary tests: list order, remove one, remove a missing word, persistence round trip, forget clears list, key stays out of backup (layout detection tests)
- [x] Add list and remove-one operations to the vocabulary store (layout vocabulary)
- [x] Settings list with per-row remove and empty state (layout switcher settings)
- [x] Strings for every shipped language (layout switcher strings)

### Ship checks
- [x] `./build.sh` with no warnings, `./build.sh --test`, `./build/Vorssaint --selftest`
- [x] Real-app pass on "Russian" and "Russian - PC": Notes, Safari address bar, Messages, Terminal (excluded and not), VS Code

## Discovered During Implementation

- [x] Subtitle additions filtered to Russian and English only: rival-language ratio (en 10x, ru 100x), cp1251/koi8-r mojibake, clipped OCR (tools)
- [x] New strings ship in English and Russian only; other interface languages fall back to English (strings)
- [x] Own layout switches tagged through a pure tracker so the manual-switch guard ignores them (layout switcher service)
- [x] Python merge tests wired into `./build.sh --test` (build)
