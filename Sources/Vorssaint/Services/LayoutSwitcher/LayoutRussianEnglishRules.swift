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

    /// A token typed on the Latin layout that opens a quotation and does not
    /// close it: `'hello`, `'em`, `'ktrnhjkbp\`h`. In English the apostrophe
    /// is never part of the word; it opens a quote or marks an elision, and
    /// the word starts after it. On the Russian layout the same key is э,
    /// which opens thousands of words. Scored with the quote on, the English
    /// reading is charged for a character no word model has seen and the
    /// Russian one wins by that alone, so `'at` would become `эфе`. Scored
    /// without it, `at` keeps and `электролизёр` still wins on its merits.
    ///
    /// The sentence so far is not consulted for such a token either. An
    /// opening quote is exactly where a Russian sentence switches to an
    /// English term, so the momentum of the words before it says nothing
    /// about this one. A token that closes the quote too, `'VUWL'`, is a
    /// literal and stays machine text.
    ///
    /// A correction taken back is refused under the spelling with the quote,
    /// so that spelling is the one looked up; stripped, it would never match.
    func opensQuotation(_ core: String, in token: String,
                        typedLanguage: String, mappedLanguage: String) -> Bool {
        typedLanguage == "en" && mappedLanguage == "ru"
            && core.first == "'" && core.count > 1 && !token.dropFirst().contains("'")
            && vocabulary?.isRefused(core) != true
    }

    /// Punctuation the way code and file names use it, on the English reading
    /// of a token. `б`, `ю` and `э` sit on the comma, full stop and apostrophe
    /// keys, and refusing every unknown word that needs one of them refused a
    /// quarter of Russian. What is left to refuse is what Russian never looks
    /// like: quotes and angle brackets (`"npm"`, `<div>`), a leading dot or
    /// apostrophe (`.absent`, `'a'`), and digits (`v1.2`). An apostrophe that
    /// only opens a quotation never reaches this: `opensQuotation` has it
    /// read as the letter it may be.
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
