// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What only holds between the Russian and English layouts.
///
/// Every other pair is judged by the general rules alone. These two were
/// measured on Russian and English text and have nothing to say about, say,
/// German against French, where the punctuation keys land on other letters.
extension LayoutDecisionScorer {
    static let urlPrefixes = ["http://", "https://", "ftp://", "www."]

    static func isRussianEnglish(_ typedLanguage: String, _ mappedLanguage: String) -> Bool {
        (typedLanguage == "ru" && mappedLanguage == "en") || (typedLanguage == "en" && mappedLanguage == "ru")
    }

    /// A URL typed through the Russian layout. No word list knows an address,
    /// and its Cyrillic spelling is a string of nonsense, so the scorer can
    /// never settle one; the scheme in the English reading settles it alone.
    func mistypedURL(typed: String, typedLanguage: String,
                     mapped: String, mappedLanguage: String) -> Judgement? {
        guard typedLanguage == "ru", mappedLanguage == "en",
              Self.urlPrefixes.contains(where: { mapped.lowercased().hasPrefix($0) }),
              vocabulary?.isRefused(typed) != true
        else { return nil }
        let verdict = Verdict(decision: .switchLayout, confidence: .high, margin: thresholds.highConfidence)
        return .rewrite(word: typed, replacement: mapped, verdict: verdict)
    }

    /// Punctuation the way code and file names use it, on the English reading
    /// of a token. `б`, `ю` and `э` sit on the comma, full stop and apostrophe
    /// keys, and refusing every unknown word that needs one of them refused a
    /// quarter of Russian. What is left to refuse is what Russian never looks
    /// like: quotes and angle brackets (`"npm"`, `<div>`), a leading dot or
    /// apostrophe (`.absent`, `'a'`), and digits (`v1.2`).
    static func readsAsMachineText<Text: Collection>(_ english: Text) -> Bool where Text.Element == Character {
        if english.first == "." || english.first == "'" { return true }
        return english.contains { $0 == "\"" || $0 == "<" || $0 == ">" || $0.isNumber }
    }
}

extension LayoutSwitcherSupport {
    /// How the URL prefixes come out when typed through any of the `russian`
    /// layouts while one of the `english` ones was meant, lowercased. A
    /// finished token starting with one is judged even though it looks
    /// structured: `https:` puts a capital Ж in the middle of the Cyrillic,
    /// which reads as camel case.
    static func mistypedURLSpellings<Key: Hashable & Comparable>(english: [[Key: String]],
                                                                 russian: [[Key: String]]) -> Set<String> {
        var spellings = Set<String>()
        for englishGlyphs in english {
            for russianGlyphs in russian {
                let table = self.table(from: englishGlyphs, to: russianGlyphs)
                spellings.formUnion(LayoutDecisionScorer.urlPrefixes.compactMap { table.mapForward($0)?.lowercased() })
            }
        }
        return spellings
    }
}
