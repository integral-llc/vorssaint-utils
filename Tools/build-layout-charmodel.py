#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Builds Resources/LayoutSwitcher/<language>_charmodel.dat.

The character models tell a word the lists have never seen from the nonsense
its keystrokes spell on the other layout. The earlier models counted every
entry of the word list once, so `ghbdtn` was judged against what dictionary
headwords look like. Text is not a dictionary: the shapes people type are the
shapes of common words, and a model that has seen `привет` as often as
`приветствовавшийся` is unsure about both. Each word here counts
ln(1 + occurrences) times, the FrequencyWords subtitle counts, which pulls the
model toward everyday text without letting `не` drown everything else.

Order 3 with interpolated Kneser-Ney smoothing (`CharacterNGramModel.swift`)
separated typed-right from typed-wrong words better than every alternative
measured: orders 4 and 5, additive smoothing, unweighted counts, the full
subtitle lists.

The file carries raw weighted counts for every n-gram up to the order, with
`^` and `$` standing for the start and end of a word; the smoothing is applied
when the file is read. Same FrequencyWords commit and checksums as
`build-layout-subtitle-words.py`, so a rerun writes the same bytes.

Usage: build-layout-charmodel.py [--source DIR]
  --source reads <language>_50k.txt from DIR instead of downloading.
"""

import argparse
import importlib.util
import math
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Resources/LayoutSwitcher"

ORDER = 3
# Absolute discount taken off every seen count. The scorer's thresholds were
# measured against this value together with the order.
DISCOUNT = 0.75
START = "^"
END = "$"


def subtitle_words_module():
    """The sibling script pins the FrequencyWords commit and checksums."""
    path = Path(__file__).with_name("build-layout-subtitle-words.py")
    spec = importlib.util.spec_from_file_location("subtitle_words", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def count_ngrams(words: dict[str, int], order: int) -> dict[str, float]:
    """Every n-gram up to `order` of every word, weighted by ln(1 + count)."""
    counts: dict[str, float] = defaultdict(float)
    for word, count in words.items():
        weight = math.log1p(count)
        padded = START * (order - 1) + word + END
        for end in range(order - 1, len(padded)):
            for length in range(1, order + 1):
                counts[padded[end - length + 1:end + 1]] += weight
    return counts


def render(language: str, counts: dict[str, float]) -> str:
    header = f"# charmodel v3 lang={language} order={ORDER} discount={DISCOUNT} weight=log1p\n"
    body = "".join(f"{gram}\t{count:.2f}\n" for gram, count in sorted(counts.items()))
    return header + body


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    arguments = parser.parse_args()
    subtitles = subtitle_words_module()
    for language, alphabet in subtitles.ALPHABETS.items():
        words = subtitles.parse_counts(subtitles.fetch(language, arguments.source), alphabet)
        counts = count_ngrams(words, ORDER)
        (DATA / f"{language}_charmodel.dat").write_text(render(language, counts), encoding="utf-8")
        print(f"{language}: {len(words)} words, {len(counts)} n-grams")
    return 0


if __name__ == "__main__":
    sys.exit(main())
