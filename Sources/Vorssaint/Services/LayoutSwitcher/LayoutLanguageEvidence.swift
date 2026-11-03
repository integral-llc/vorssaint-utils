// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What is known about a spelling in one language. The scorer weighs two
/// spellings of the same keystrokes against each other and only ever asks
/// these three questions, so the data behind them can change without it.
protocol LayoutLanguageEvidence {
    func supports(_ language: String) -> Bool
    /// Zipf frequency, about 1 for rare up to about 7.5 for the commonest
    /// words, or nil when the language's word list does not carry the word.
    func frequency(of word: String, language: String) -> Double?
    func logLikelihood(of word: String, language: String) -> Double
    /// The highest frequency among listed words one slip away from `word`:
    /// a letter dropped, added, replaced or swapped with its neighbour. nil
    /// when no listed word is that close.
    func slipFrequency(of word: String, language: String) -> Double?
}

extension LayoutLanguageEvidence {
    func slipFrequency(of word: String, language: String) -> Double? { nil }
}

/// Word lists and character models shipped with the app, one pair per
/// language, named `<language>_words.txt` and `<language>_charmodel.dat`, plus
/// an optional `<language>_subtitle_words.txt` that only adds words.
///
/// A language is supported only when both halves load. Half the evidence
/// would still produce a margin, just not one the thresholds were measured
/// against, and a wrong margin here rewrites what somebody typed.
final class BundledLanguageEvidence: LayoutLanguageEvidence {
    private struct Language {
        let frequencies: [String: Double]
        let model: CharacterNGramModel
    }

    /// A line without a frequency still names a word; it counts as middling.
    private static let neutralFrequency = 3.0
    /// Below anything a model says about real text, and finite: an infinite
    /// score would turn a caller that skipped `supports` into a certain switch.
    private static let unknownLanguageLikelihood = -20.0

    private let lock = NSLock()
    private let directory: URL?
    /// nil records a language that was looked for and is not there, so a
    /// missing one is not read from disk again on every word.
    private var languages: [String: Language?] = [:]

    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("LayoutSwitcher")) {
        self.directory = directory
    }

    func supports(_ language: String) -> Bool { loaded(language) != nil }

    func frequency(of word: String, language: String) -> Double? {
        loaded(language)?.frequencies[word.lowercased()]
    }

    func logLikelihood(of word: String, language: String) -> Double {
        loaded(language)?.model.logLikelihood(word) ?? Self.unknownLanguageLikelihood
    }

    /// Every spelling one edit away is tried against the list: some seven
    /// hundred lookups for a ten-letter word, which is on the order of what
    /// scoring the word already costs.
    func slipFrequency(of word: String, language: String) -> Double? {
        guard let language = loaded(language) else { return nil }
        let letters = Array(word.lowercased())
        var best: Double?
        func consider(_ candidate: [Character]) {
            guard let frequency = language.frequencies[String(candidate)] else { return }
            best = max(best ?? -.infinity, frequency)
        }
        for index in 0...letters.count {
            if index < letters.count {
                var dropped = letters
                dropped.remove(at: index)
                consider(dropped)
                for letter in language.model.letters where letter != letters[index] {
                    var replaced = letters
                    replaced[index] = letter
                    consider(replaced)
                }
            }
            if index + 1 < letters.count {
                var swapped = letters
                swapped.swapAt(index, index + 1)
                consider(swapped)
            }
            for letter in language.model.letters {
                var added = letters
                added.insert(letter, at: index)
                consider(added)
            }
        }
        return best
    }

    /// True once the language is in memory. Never waits: the first read parses
    /// megabytes, and the caller is the main thread between two keystrokes.
    func isReady(_ language: String) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }
        guard let known = languages[language] else { return false }
        return known != nil
    }

    /// The lists are a few megabytes of text. Parsing them on the first word
    /// typed would stall that word, so the service asks ahead of time.
    func warmUp(_ languages: [String]) {
        languages.forEach { _ = loaded($0) }
    }

    private func loaded(_ language: String) -> Language? {
        lock.withLock {
            if let known = languages[language] { return known }
            let value = read(language)
            languages[language] = .some(value)
            return value
        }
    }

    private func read(_ language: String) -> Language? {
        // The code comes from an input source's metadata and becomes part of a
        // file name, so anything that is not a plain language tag is refused.
        guard let directory, !language.isEmpty,
              language.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }),
              let model = CharacterNGramModel(
                contentsOf: directory.appendingPathComponent("\(language)_charmodel.dat")),
              let words = try? String(
                contentsOf: directory.appendingPathComponent("\(language)_words.txt"), encoding: .utf8)
        else { return nil }
        let frequencies = Self.frequencies(in: words)
        guard !frequencies.isEmpty else { return nil }
        // Chat words from subtitles, scaled to the same zipf. Optional, and
        // never allowed to restate a frequency the main list already gives.
        let subtitles = (try? String(
            contentsOf: directory.appendingPathComponent("\(language)_subtitle_words.txt"), encoding: .utf8))
            .map(Self.frequencies(in:)) ?? [:]
        return Language(frequencies: frequencies.merging(subtitles) { main, _ in main }, model: model)
    }

    static func frequencies(in contents: String) -> [String: Double] {
        var frequencies: [String: Double] = [:]
        contents.enumerateLines { line, _ in
            // Split on the first tab by hand: `split` drops an empty first
            // field, and a line that is only a number would become a word.
            let tab = line.firstIndex(of: "\t")
            let word = line[..<(tab ?? line.endIndex)].trimmingCharacters(in: .whitespaces).lowercased()
            guard !word.isEmpty else { return }
            let frequency = tab.flatMap {
                Double(line[line.index(after: $0)...].trimmingCharacters(in: .whitespaces))
            }
            frequencies[word] = frequency ?? neutralFrequency
        }
        return frequencies
    }
}
