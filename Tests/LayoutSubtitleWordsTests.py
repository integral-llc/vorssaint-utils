#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""The subtitle word merge, on inputs small enough to read at a glance."""

import importlib.util
import math
import sys
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "Tools/build-layout-subtitle-words.py"
spec = importlib.util.spec_from_file_location("subtitle_words", TOOL)
subtitle_words = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subtitle_words)

RU = subtitle_words.ALPHABETS["ru"]


class ParseCountsTests(unittest.TestCase):
    def test_keeps_alphabet_words_lowercased_first_wins(self) -> None:
        text = "Привет 10\nпривет 3\nhello 7\nчто-то 5\nрыба x\nкот 4 extra\n"
        self.assertEqual(subtitle_words.parse_counts(text, RU), {"привет": 10})


class AdditionsTests(unittest.TestCase):
    base = {"привет": 5.0, "дом": 4.0}

    def test_existing_entries_are_never_repeated(self) -> None:
        added = subtitle_words.additions(self.base, {"привет": 1000, "перезвони": 10})
        self.assertEqual([word for word, _ in added], ["перезвони"])

    def test_short_words_are_dropped(self) -> None:
        added = subtitle_words.additions(self.base, {"привет": 1000, "щрн": 50, "ммм": 40})
        self.assertEqual(added, [])

    def test_offset_is_the_median_over_the_overlap(self) -> None:
        counts = {"привет": 1000, "дом": 100, "перезвони": 10}
        offset = statistics_median([5.0 - math.log10(1000), 4.0 - math.log10(100)])
        added = subtitle_words.additions(self.base, counts)
        self.assertEqual(added, [("перезвони", round(offset + 1.0, 2))])

    def test_order_is_stable_most_common_first(self) -> None:
        counts = {"привет": 1000, "вашего": 10, "абажур": 10, "облажался": 100}
        added = subtitle_words.additions(self.base, counts)
        self.assertEqual([word for word, _ in added], ["облажался", "абажур", "вашего"])

    def test_disjoint_lists_refuse_to_guess_an_offset(self) -> None:
        with self.assertRaises(ValueError):
            subtitle_words.additions(self.base, {"перезвони": 10})


class NotRussianOrEnglishTests(unittest.TestCase):
    def test_a_word_a_rival_says_far_more_often_is_the_rivals(self) -> None:
        own = {"danke": 0.00001, "hello": 0.001}
        german = {"danke": 0.01, "hello": 0.0001}
        self.assertTrue(subtitle_words.foreign("danke", own, [german], 10.0))
        self.assertFalse(subtitle_words.foreign("hello", own, [german], 10.0))

    def test_a_word_shared_at_a_similar_rate_stays(self) -> None:
        own = {"успокой": 0.0001}
        bulgarian = {"успокой": 0.007}
        self.assertFalse(subtitle_words.foreign("успокой", own, [bulgarian], 100.0))

    def test_text_read_in_the_wrong_code_page_is_dropped(self) -> None:
        base = {"просто": 5.5}
        garbled = "просто".encode("koi8-r").decode("cp1251").lower()
        self.assertTrue(subtitle_words.mojibake(garbled, base))
        self.assertFalse(subtitle_words.mojibake("перезвони", base))

    def test_a_word_missing_its_first_letter_is_dropped(self) -> None:
        base = {"когда": 6.4}
        self.assertTrue(subtitle_words.clipped("огда", 3.0, base, RU))
        self.assertFalse(subtitle_words.clipped("огда", 5.0, base, RU))
        self.assertFalse(subtitle_words.clipped("перезвони", 3.0, base, RU))

    def test_corpus_size_counts_every_alphabet(self) -> None:
        self.assertEqual(subtitle_words.total_count("привет 10\nhello 5\nmalformed\n"), 15)


def statistics_median(values: list[float]) -> float:
    ordered = sorted(values)
    middle = len(ordered) // 2
    return ordered[middle] if len(ordered) % 2 else (ordered[middle - 1] + ordered[middle]) / 2


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=1).result
    sys.exit(0 if result.wasSuccessful() else 1)
