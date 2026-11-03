// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LayoutCorrectionConfidence: Equatable {
    case high
    case low
}

/// Decides whether a finished word was meant for the other layout.
///
/// The same keystrokes always have two spellings: the one that was typed and
/// the one the other layout would have produced. Both are scored the same way,
/// on word list membership, word frequency and how word-like the characters
/// read, and the larger score wins by its margin. A word that is fine on both
/// layouts comes out with a small margin and is left alone, which is the whole
/// point: nothing here needs a list of exceptions to stay out of the way.
///
/// Weights and thresholds were tuned together on `Tests/Fixtures/layout-corpus.tsv`
/// and the test suite holds them to its gates. Move one and rerun it.
struct LayoutDecisionScorer {
    enum Decision: Equatable {
        case keep
        case switchLayout
        case undecided
    }

    struct Verdict: Equatable {
        let decision: Decision
        let confidence: LayoutCorrectionConfidence
        /// How far the winning spelling is ahead. Comparable across candidate
        /// layouts, so the service can pick the best of several.
        let margin: Double
    }

    struct Weights {
        var membership = 4.0
        var frequency = 0.5
        var characterModel = 1.0
        /// Charged to the typed spelling per punctuation key that the other
        /// layout would have read as a letter.
        var layoutArtifact = 3.0
        /// Per time the user has typed the word and let it stand, up to the
        /// cap: enough to settle a word no list carries, never enough to
        /// outvote a list entry on its own.
        var personal = 0.3
        var personalCap = 10.0
    }

    struct Thresholds {
        /// Margin either spelling must clear to be believed at all.
        var decisive = 1.5
        /// For a word neither list carries, the bar in total log-likelihood
        /// instead: per character it is steep for a short word and eases as
        /// the predictions add up, but never below `decisiveFloor`.
        var decisiveEvidence = 10.0
        var decisiveFloor = 0.6
        /// A word of fewer letters than this is settled by the sentence it
        /// is in, or by nothing: `vs.` against `мы.` is two letters and a
        /// full stop, and the lists alone cannot tell the abbreviation from
        /// the pronoun.
        var shortWord = 3
        /// Up to this many letters, two listed spellings are weighed on the
        /// lists alone. `fps` and `азы` are both words; what the character
        /// models make of three letters says more about abbreviations than
        /// about layouts.
        var listedShortWord = 3
        var highConfidence = 4.0
        /// Below this length every missing character raises the bar for high
        /// confidence, because a single list entry tips a short word.
        var lengthPivot = 7
        var lengthPenalty = 1.0
        /// The mapped spelling has to read at least this word-like before
        /// punctuation in the typed one counts against it. Code is full of
        /// brackets; `[]int` maps to nothing a Russian reader would accept.
        var artifactTargetFloor = -4.0
        /// Inside a near tie, the far more frequent spelling gets a nudge.
        /// The word lists carry a tail of junk two-letter entries that would
        /// otherwise tie against a word as common as `ты`.
        var frequencyLeanWeight = 0.3
        var frequencyLeanCap = 1.5
        var absentFrequency = 3.0
        /// A target this common, and this far ahead of the typed spelling, is
        /// a plain slip however short the word is.
        var commonTargetFrequency = 4.0
        var dominanceGap = 1.0
        /// Inside a near tie the sentence so far speaks louder than word
        /// frequency, and below this it is not speaking at all.
        var contextWeight = 4.0
        var contextActive = 0.05
    }

    /// Punctuation that turns up inside or against a word in ordinary writing
    /// and in code, so finding it there says nothing about the layout.
    static let ordinaryPunctuation: Set<Character> = ["'", ",", ".", "\"", "<", ">"]

    let evidence: LayoutLanguageEvidence
    var vocabulary: LayoutPersonalVocabulary?
    var weights = Weights()
    var thresholds = Thresholds()

    init(evidence: LayoutLanguageEvidence) {
        self.evidence = evidence
    }

    /// `mapped` is `typed` as the other layout spells it, character for character.
    /// `contextLean` is the sentence's momentum, positive toward the typed language.
    func verdict(typed: String, typedLanguage: String,
                 mapped: String, mappedLanguage: String,
                 contextLean: Double = 0) -> Verdict {
        if vocabulary?.isRefused(typed) == true {
            return Verdict(decision: .keep, confidence: .high, margin: .greatestFiniteMagnitude)
        }
        let typedLower = typed.lowercased()
        let mappedLower = mapped.lowercased()
        let typedScore = score(typedLower, language: typedLanguage)
            - weights.layoutArtifact * Double(artifacts(typed: typed, mapped: mapped,
                                                        mappedLanguage: mappedLanguage))
        let mappedScore = score(mappedLower, language: mappedLanguage)
        let typedFrequency = knownFrequency(typedLower, language: typedLanguage)
        let mappedFrequency = knownFrequency(mappedLower, language: mappedLanguage)
        if typedFrequency == nil, mappedFrequency == nil,
           isSlip(typedLower, language: typedLanguage, over: mappedLower, language: mappedLanguage) {
            return Verdict(decision: .keep, confidence: .low, margin: thresholds.decisive)
        }

        // A word that is decisive on its own is never reopened: that is what
        // keeps a Russian sentence from turning `here` into Cyrillic. Only a
        // near tie listens to the sentence, and only a near tie with no
        // sentence around it falls back on which spelling is the commoner word.
        // A word the user has typed before is on a list of their own.
        let decisive = decisiveMargin(typed: typed, mapped: mapped,
                                      listed: typedFrequency != nil || mappedFrequency != nil
                                          || personalBonus(typedLower) > 0)
        var margin = typedScore - mappedScore
        if typedFrequency != nil, mappedFrequency != nil, isShortPlainPair(typed, mapped) {
            margin -= weights.characterModel
                * (evidence.logLikelihood(of: typedLower, language: typedLanguage)
                    - evidence.logLikelihood(of: mappedLower, language: mappedLanguage))
        }
        if abs(margin) < decisive {
            if abs(contextLean) >= thresholds.contextActive {
                margin += thresholds.contextWeight * contextLean
            } else {
                let lean = thresholds.frequencyLeanWeight
                    * ((typedFrequency ?? thresholds.absentFrequency)
                        - (mappedFrequency ?? thresholds.absentFrequency))
                margin += max(-thresholds.frequencyLeanCap, min(thresholds.frequencyLeanCap, lean))
            }
        }

        if margin > decisive {
            return Verdict(decision: .keep,
                           confidence: confidence(margin: margin, length: typed.count),
                           margin: margin)
        }
        if -margin > decisive {
            let dominant = (mappedFrequency ?? 0) >= thresholds.commonTargetFrequency
                && (mappedFrequency ?? 0) - (typedFrequency ?? thresholds.absentFrequency)
                    >= thresholds.dominanceGap
            return Verdict(decision: .switchLayout,
                           confidence: dominant ? .high : confidence(margin: -margin, length: typed.count),
                           margin: -margin)
        }
        return Verdict(decision: .undecided, confidence: .low, margin: abs(margin))
    }

    /// A word in no list that is one slip away from a listed word of the
    /// layout it was typed on, while its other spelling is one slip away from
    /// nothing, is a typo and not a layout slip: `гркфа` is `графа` with two
    /// letters swapped, and `uhraf` is near nothing in English. Measured on
    /// six thousand typos and six and a half thousand words typed on the
    /// wrong layout, the rule covers 97% of the typos and four of the slips.
    private func isSlip(_ typed: String, language typedLanguage: String,
                        over mapped: String, language mappedLanguage: String) -> Bool {
        guard typed.allSatisfy(\.isLetter), mapped.allSatisfy(\.isLetter) else { return false }
        return evidence.slipFrequency(of: typed, language: typedLanguage) != nil
            && evidence.slipFrequency(of: mapped, language: mappedLanguage) == nil
    }

    private func isShortPlainPair(_ typed: String, _ mapped: String) -> Bool {
        min(typed.count, mapped.count) <= thresholds.listedShortWord
            && typed.allSatisfy(\.isLetter) && mapped.allSatisfy(\.isLetter)
    }

    /// The character models score per character, so one margin asks a long
    /// word for far more evidence in total than a short one. Where neither
    /// spelling is a listed word the characters are all there is to go on,
    /// and `кляузничавший` scoring 1.3 ahead on each of its fourteen
    /// predictions is no near tie, while a four-letter word has to be ahead
    /// by 2.0 on each of its five. Plain letters only: punctuation keys are
    /// judged by their own rules, and code strings them between words.
    private func decisiveMargin(typed: String, mapped: String, listed: Bool) -> Double {
        let length = min(typed.count, mapped.count)
        if length < thresholds.shortWord { return thresholds.highConfidence }
        guard !listed, typed.allSatisfy(\.isLetter), mapped.allSatisfy(\.isLetter) else {
            return thresholds.decisive
        }
        // One prediction per character plus the end of the word.
        return max(thresholds.decisiveFloor, thresholds.decisiveEvidence / Double(length + 1))
    }

    private func confidence(margin: Double, length: Int) -> LayoutCorrectionConfidence {
        let shortfall = max(0, thresholds.lengthPivot - length)
        return margin >= thresholds.highConfidence + thresholds.lengthPenalty * Double(shortfall)
            ? .high : .low
    }

    /// The word lists hold no hyphenated entries and the character models were
    /// trained on them, so `что-то` as a whole earns nothing from either.
    /// Scoring each part and weighting by length keeps the result on the scale
    /// of a single word. The hyphen sits on the same key in both spellings, so
    /// both split at the same places.
    private func score(_ word: String, language: String) -> Double {
        let parts = Self.hyphenatedParts(of: word)
        guard !parts.isEmpty else { return plainScore(word, language: language) }
        let length = parts.reduce(0) { $0 + $1.count }
        let mean = parts.reduce(0.0) { $0 + Double($1.count) * plainScore($1, language: language) }
            / Double(length)
        // The compound is remembered as typed, hyphen and all, so its habit
        // is looked up whole; the parts only know about themselves.
        return mean + personalBonus(word)
    }

    private func plainScore(_ word: String, language: String) -> Double {
        var score = weights.characterModel * evidence.logLikelihood(of: word, language: language)
        if let frequency = evidence.frequency(of: word, language: language) {
            score += weights.membership + weights.frequency * frequency
        }
        return score + personalBonus(word)
    }

    private func personalBonus(_ word: String) -> Double {
        guard let count = vocabulary?.typedCount(of: word), count > 0 else { return 0 }
        return weights.personal * min(Double(count), weights.personalCap)
    }

    /// Empty for a word with no hyphen, which is scored whole.
    private static func hyphenatedParts(of word: String) -> [String] {
        word.contains("-") ? word.split(separator: "-").map(String.init) : []
    }

    /// A compound is a known word only when every part is, and only as common
    /// as its rarest part.
    func knownFrequency(_ word: String, language: String) -> Double? {
        let parts = Self.hyphenatedParts(of: word)
        guard !parts.isEmpty else { return evidence.frequency(of: word, language: language) }
        var rarest = Double.greatestFiniteMagnitude
        for part in parts {
            guard let frequency = evidence.frequency(of: part, language: language) else { return nil }
            rarest = min(rarest, frequency)
        }
        return rarest
    }

    /// Keys that type punctuation on one layout and a letter on the other.
    /// `[jhjij` has a bracket no English word starts with; its other spelling
    /// is `хорошо`. An identifier fails the capital test, a slice type fails
    /// the floor: neither maps to anything word-like.
    private func artifacts(typed: String, mapped: String, mappedLanguage: String) -> Int {
        guard typed.count == mapped.count,
              !typed.dropFirst().contains(where: \.isUppercase)
        else { return 0 }
        let count = zip(typed, mapped).reduce(0) { total, pair in
            let isArtifact = !pair.0.isLetter && !pair.0.isNumber && pair.1.isLetter
                && !Self.ordinaryPunctuation.contains(pair.0)
            return total + (isArtifact ? 1 : 0)
        }
        guard count > 0,
              evidence.logLikelihood(of: mapped.lowercased(), language: mappedLanguage)
                >= thresholds.artifactTargetFloor
        else { return 0 }
        return count
    }
}
