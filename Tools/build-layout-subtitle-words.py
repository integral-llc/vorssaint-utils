#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Builds Resources/LayoutSwitcher/<language>_subtitle_words.txt.

The wordfreq lists the scorer was tuned on lean on written text and miss the
words people type in chats (`перезвони`, `облажался`). FrequencyWords counts
OpenSubtitles 2018 and has them. Its entries that the wordfreq list lacks are
written to a separate file, so the wordfreq list stays as published and a
rerun reads the same inputs and writes the same bytes.

FrequencyWords has raw counts; the scorer reads zipf. One offset per language,
the median of (zipf - log10(count)) over the words both lists carry, puts the
counts on the wordfreq scale without retuning a threshold.

Subtitles are not all in the language they are filed under. English ones
quote German and Italian (`danke`, `grazie`), and Russian ones carry text
decoded with the wrong code page (`опнярн` is `просто`) and OCR that lost a
first letter (`огда`). None of that is Russian or English, and all of it is
dropped; see `foreign`, `mojibake` and `clipped`.

Usage: build-layout-subtitle-words.py [--source DIR]
  --source reads every <language>_50k.txt from DIR instead of downloading.
"""

import argparse
import hashlib
import math
import statistics
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Resources/LayoutSwitcher"

COMMIT = "525f9b560de45753a5ea01069454e72e9aa541c6"
URL = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/{commit}/content/2018/{language}/{language}_50k.txt"
SHA256 = {
    "ru": "6095f507cc167488ec66ada5a85ac50433503a08ad24a07c6eabdf54352c4e7f",
    "en": "5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458",
    "de": "d9e50546fd7e8b6fe6542a2b33c51d1331092b2a3916ec09f80d97856068705b",
    "fr": "f81f7c570b6433764da99aa30f4dfb08d81c5926301377b709af23a13b1f9596",
    "es": "dcff3ad4316192f4dc4ff7d26e637c6ff314ef1ca0f3f720c5649018a71056c0",
    "it": "bb96cdcb56d28342c1e909db6b2525448b7767136b7e86a2ccc649a1be66fc19",
    "pt": "f97704382f97273ff59488b1885e7ac90d20f81fd92e5fbad3e3ce43633f495c",
    "pt_br": "a61d6f2ede97c5daad5fb3907b72a228f0aff12668be6d24da590d20804fa611",
    "nl": "099bd0c27b514d54284360ad9ce2b4ef7b6903b22e848b67ab10f6aa2adb4baa",
    "sv": "566d0614a54f3c243bca4097c9bb824d46275abff31582157e73c166b7089500",
    "da": "6a83e4deb5e38d873b1ccfb4be4fb25903878c07c8522af708027ac8b540c6b1",
    "no": "d5808d8ec04603b765c09c06a03f0273ccf36bb35a3902287e56b7e7d872ca92",
    "fi": "8bc1d43dd54ea0c4432b1f6ae497759a332e984224819cf8a4f2337681c803b4",
    "pl": "50bf8d30d1ed4f5cedceb3e40e74d793ec6bec0f16d9f3dd0a2c9e313402e10f",
    "cs": "1fb0576ef07cf5a543789d394cde1168573fc9e7adf427fd143249fd5547458d",
    "ro": "af4d7d1fc980ee7f988a5114dd34478dd5c7abd1e66a45c25a5da330f06faba5",
    "hu": "b765780a1277c3b1e326205c972b1ea1631732ec54ab489d13d21618ceab4fec",
    "tr": "480192844e7fdfe9591bbf0b9cfbb96ed5751cfbba7024fd45d8cb7508e07d5c",
    "id": "f2eea0da9735b7040efbfa813f5f875ec931de5a0ec70a6f28213ea60a87bb38",
    "hr": "725f57e0bd122f46d8e358c3542a4e1d126e468075c5e4d6644fd0d21c47bbc3",
    "sl": "00d9dc7a50726e99ab4d5bb50ce8087ce709a1416afad65a9dec0821c03ba442",
    "sk": "10eddbcd086ff26a814a140e1d5b20a1ba0ee8b0870be1a9a09268ba7aeaa094",
    "uk": "881686fe66a168b79f6a9ee2f6cbbf944cfb12bfb7040913ef535cb29bd86ec9",
    "bg": "b0faf13173216e0006ba548d57a621ae1df0fb3e888738df1b9ec09d210903c9",
    "sr": "c84eaf5e324fe5deb0aa491935bff5e9338b6cd687f6f7aacc56988594a39859",
    "mk": "85febe3efafed0d6e3b99287a1268815a938ff9fba3b940c6e9605b393a0f760",
}
ALPHABETS = {
    "ru": frozenset("абвгдеёжзийклмнопрстуфхцчшщъыьэюя"),
    "en": frozenset("abcdefghijklmnopqrstuvwxyz"),
}
# Languages whose subtitles share a script with the target and leak into it.
RIVALS = {
    "en": ("de", "fr", "es", "it", "pt", "pt_br", "nl", "sv", "da", "no",
           "fi", "pl", "cs", "ro", "hu", "tr", "id", "hr", "sl", "sk"),
    "ru": ("uk", "bg", "sr", "mk"),
}
# How much more often a rival has to use a word for it to be the rival's.
# English separates at 10: `danke` is 1169x German, real words stay under 3.
# Russian shares imperatives with Bulgarian (`успокой` 70x, `сложи` 85x), so
# only what no Russian subtitle would say goes: `кажи` 377x, `вратам` 223x.
FOREIGN_RATIO = {"en": 10.0, "ru": 100.0}
# Subtitles carry OCR slips and interjections (`ёто`, `щрн`, `ммм`); none of
# them survives four letters often enough to matter, and real words do.
MINIMUM_LENGTH = 4
# Cyrillic subtitles saved in one code page and read in the other.
CODE_PAGES = (("cp1251", "koi8-r"), ("koi8-r", "cp1251"))
# A mis-decoded word is only believed when it lands on a real, common word.
MOJIBAKE_MINIMUM_ZIPF = 3.0
# `огда` is `когда` with its first letter lost; a real word one letter short
# of another is not a hundred times rarer than it.
CLIPPED_ZIPF_GAP = 2.0


def parse_counts(text: str, alphabet: frozenset[str]) -> dict[str, int]:
    """`word count` lines, lowercased, letters of the alphabet only, first wins."""
    counts = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) != 2 or not parts[1].isdigit():
            continue
        word = parts[0].lower()
        if word and set(word) <= alphabet and word not in counts:
            counts[word] = int(parts[1])
    return counts


def total_count(text: str) -> int:
    """Every counted token, whatever its alphabet: the size of the corpus."""
    return sum(int(parts[1]) for parts in map(str.split, text.splitlines())
               if len(parts) == 2 and parts[1].isdigit())


def parse_zipf(text: str) -> dict[str, float]:
    zipf = {}
    for line in text.splitlines():
        word, _, value = line.partition("\t")
        if word and value:
            zipf[word.lower()] = float(value)
    return zipf


def additions(base: dict[str, float], counts: dict[str, int],
              minimum_length: int = MINIMUM_LENGTH) -> list[tuple[str, float]]:
    """Entries of `counts` missing from `base`, as (word, zipf), most common first."""
    overlap = [base[word] - math.log10(count) for word, count in counts.items() if word in base]
    if not overlap:
        raise ValueError("the two lists share no words, so no offset can be fitted")
    offset = statistics.median(overlap)
    added = [(word, round(offset + math.log10(count), 2))
             for word, count in counts.items()
             if word not in base and len(word) >= minimum_length]
    return sorted(added, key=lambda entry: (-entry[1], entry[0]))


def foreign(word: str, own: dict[str, float], rivals: list[dict[str, float]], ratio: float) -> bool:
    """`own` and `rivals` are relative frequencies, count over corpus size."""
    return any(rival.get(word, 0.0) >= ratio * own[word] for rival in rivals)


def mojibake(word: str, base: dict[str, float]) -> bool:
    for written, read in CODE_PAGES:
        try:
            repaired = word.encode(written).decode(read).lower()
        except UnicodeError:
            continue
        if repaired != word and base.get(repaired, 0.0) >= MOJIBAKE_MINIMUM_ZIPF:
            return True
    return False


def clipped(word: str, zipf: float, base: dict[str, float], alphabet: frozenset[str]) -> bool:
    return any(base.get(letter + word, 0.0) >= zipf + CLIPPED_ZIPF_GAP for letter in alphabet)


def fetch(language: str, source: Path | None) -> str:
    if source:
        payload = (source / f"{language}_50k.txt").read_bytes()
    else:
        with urllib.request.urlopen(URL.format(commit=COMMIT, language=language), timeout=60) as response:
            payload = response.read()
    digest = hashlib.sha256(payload).hexdigest()
    if digest != SHA256[language]:
        raise ValueError(f"{language}_50k.txt has sha256 {digest}, expected {SHA256[language]}")
    return payload.decode("utf-8")


def relative(text: str, alphabet: frozenset[str]) -> dict[str, float]:
    total = total_count(text)
    return {word: count / total for word, count in parse_counts(text, alphabet).items()}


def build(language: str, source: Path | None) -> list[tuple[str, float]]:
    alphabet = ALPHABETS[language]
    base = parse_zipf((DATA / f"{language}_words.txt").read_text(encoding="utf-8"))
    text = fetch(language, source)
    own = relative(text, alphabet)
    rivals = [relative(fetch(rival, source), alphabet) for rival in RIVALS[language]]
    return [(word, zipf) for word, zipf in additions(base, parse_counts(text, alphabet))
            if not foreign(word, own, rivals, FOREIGN_RATIO[language])
            and not (language == "ru" and mojibake(word, base))
            and not clipped(word, zipf, base, alphabet)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    arguments = parser.parse_args()
    for language in ALPHABETS:
        added = build(language, arguments.source)
        lines = "".join(f"{word}\t{zipf}\n" for word, zipf in added)
        (DATA / f"{language}_subtitle_words.txt").write_text(lines, encoding="utf-8")
        print(f"{language}: {len(added)} words added")
    return 0


if __name__ == "__main__":
    sys.exit(main())
