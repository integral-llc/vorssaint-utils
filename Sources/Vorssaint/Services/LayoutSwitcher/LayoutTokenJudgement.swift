// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// From a token as it sits in the text to what, if anything, replaces it.
///
/// A token is a word plus whatever is attached to it, and the keys that type
/// `,` and `.` on one layout type `б` and `ю` on another. So the end of a
/// token can be read two ways. `k.,k.` is `люблю` and every key in it was a
/// letter; `руддщб` is `hello,` and the last key was a comma. Scoring the
/// token whole gets the second kind wrong on both sides, since no word list
/// carries `hello,`. Each reading is scored on the word alone, and the one
/// that reads the tail as letters has to land on a known word to win.
extension LayoutDecisionScorer {
    enum Judgement: Equatable {
        /// Replace the whole token with `replacement`. `word` is what was
        /// typed without the punctuation around it: the thing to refuse if
        /// the user takes the correction back.
        case rewrite(word: String, replacement: String, verdict: Verdict)
        /// The word was typed on the right layout. `word` is it without the
        /// punctuation around it, which is the form worth remembering.
        case keep(word: String)
        case undecided
    }

    func judgement(typed: String, typedLanguage: String,
                   mapped: String, mappedLanguage: String,
                   contextLean: Double = 0) -> Judgement {
        let pairs = Array(zip(typed, mapped))
        guard pairs.count == typed.count, pairs.count == mapped.count else { return .undecided }
        if let url = mistypedURL(typed: typed, typedLanguage: typedLanguage,
                                 mapped: mapped, mappedLanguage: mappedLanguage) {
            return url
        }
        if Self.isQuotedLiteral(typed) { return .undecided }

        // Punctuation under both readings: `!`, a bracket, or `^` that the
        // other layout types as a comma. Not part of any word on either side
        // of it, and it follows the word into whichever spelling wins.
        var start = 0
        while start < pairs.count, !Self.isWordy(pairs[start].0), !Self.isWordy(pairs[start].1) { start += 1 }
        var end = pairs.count
        while end > start, !Self.isWordy(pairs[end - 1].0), !Self.isWordy(pairs[end - 1].1) { end -= 1 }
        // A letter under one reading and punctuation under the other.
        var coreEnd = end
        while coreEnd > start, Self.isWordy(pairs[coreEnd - 1].0) != Self.isWordy(pairs[coreEnd - 1].1) {
            coreEnd -= 1
        }
        if Self.isAbbreviation(pairs[start..<coreEnd].map(\.0)) { return .undecided }
        let pureHead = String(pairs[..<start].map(\.1))
        let pureTail = String(pairs[end...].map(\.1))

        func verdict(upTo limit: Int) -> Verdict? {
            guard limit > start else { return nil }
            let core = pairs[start..<limit]
            let typedCore = String(core.map(\.0)), mappedCore = String(core.map(\.1))
            // An opening quote is not part of the English word it precedes,
            // and the sentence before it has no say over what it quotes.
            let quoted = opensQuotation(typedCore, in: typed,
                                        typedLanguage: typedLanguage, mappedLanguage: mappedLanguage)
            let englishCore = quoted ? String(typedCore.dropFirst()) : typedCore
            let result = self.verdict(typed: englishCore, typedLanguage: typedLanguage,
                                      mapped: mappedCore, mappedLanguage: mappedLanguage,
                                      contextLean: quoted ? 0 : contextLean)
            // `file.txt` has a Cyrillic spelling and so does `example.com`.
            // Where ordinary punctuation would have to be a letter, only a
            // known word is reason enough to believe it was one. Between
            // Russian and English that holds only where the English reading
            // looks like machine text; `б`, `ю` and `э` are on those keys.
            let leansOnPunctuation = core.contains {
                Self.isWordy($0.0) != Self.isWordy($0.1)
                    && (Self.ordinaryPunctuation.contains($0.0) || Self.ordinaryPunctuation.contains($0.1))
            }
            guard result.decision == .switchLayout, leansOnPunctuation,
                  knownFrequency(mappedCore.lowercased(), language: mappedLanguage) == nil
            else { return result }
            if Self.isRussianEnglish(typedLanguage, mappedLanguage),
               !Self.readsAsMachineText(typedLanguage == "en" ? englishCore : mappedCore) {
                return result
            }
            return Verdict(decision: .undecided, confidence: .low, margin: result.margin)
        }

        // The reading that swallows the tail has to be a better word than the
        // core it swallows: `at.` is `at` and a full stop long before it is
        // `фею`, however badly `at.` reads as one English word.
        if coreEnd < end, let letters = verdict(upTo: end), letters.decision == .switchLayout,
           let whole = knownFrequency(String(pairs[start..<end].map(\.1)).lowercased(), language: mappedLanguage),
           whole > knownFrequency(String(pairs[start..<coreEnd].map(\.0)).lowercased(), language: typedLanguage) ?? -.infinity {
            return .rewrite(word: String(pairs[start..<end].map(\.0)),
                            replacement: pureHead + String(pairs[start..<end].map(\.1)) + pureTail,
                            verdict: letters)
        }
        guard let word = verdict(upTo: coreEnd) else { return .undecided }
        switch word.decision {
        case .switchLayout:
            // The tail was punctuation, so it stays punctuation: whichever of
            // the two characters is not a letter is the one that was meant.
            let tail = String(pairs[coreEnd..<end].map { Self.isWordy($0.0) ? $0.1 : $0.0 })
            return .rewrite(word: String(pairs[start..<coreEnd].map(\.0)),
                            replacement: pureHead + String(pairs[start..<coreEnd].map(\.1)) + tail + pureTail,
                            verdict: word)
        case .keep:
            return .keep(word: String(pairs[start..<coreEnd].map(\.0)))
        case .undecided:
            return .undecided
        }
    }

    private static func isWordy(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// `"c"`, `'em'`: a quote opened and closed inside one token is a literal
    /// in code or a quoted term in prose, and on the Russian layout the two
    /// quote keys are `э` and `Э`, so the lists hold junk such as `эс` that
    /// would otherwise claim it. No Russian word opens and closes on `э`.
    static func isQuotedLiteral(_ token: String) -> Bool {
        guard let first = token.first, first == "\"" || first == "'", token.count > 2 else { return false }
        return token.dropFirst().contains(first)
    }

    /// Up to four capitals and nothing else is an abbreviation, `KB`, `TLS`,
    /// `DDC`, and the lists carry a listed word for too many of them (`ЛИ`,
    /// `ВВС`). A word shouted on the wrong layout is left alone with them;
    /// the corpora hold none, and the stakes in code are higher.
    static func isAbbreviation<Core: Collection>(_ core: Core) -> Bool where Core.Element == Character {
        (2...4).contains(core.count) && core.allSatisfy(\.isUppercase)
    }
}
