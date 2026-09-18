// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What is known about a spelling in one language. The scorer weighs two
/// spellings of the same keystrokes against each other and only ever asks
/// these two questions, so the data behind them can change without it.
protocol LayoutLanguageEvidence {
    func supports(_ language: String) -> Bool
    /// Zipf frequency, about 1 for rare up to about 7.5 for the commonest
    /// words, or nil when the language's word list does not carry the word.
    func frequency(of word: String, language: String) -> Double?
    func logLikelihood(of word: String, language: String) -> Double
}

/// Word lists and character models shipped with the app, one pair per
/// language, named `<language>_words.txt` and `<language>_charmodel.dat`.
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
        return frequencies.isEmpty ? nil : Language(frequencies: frequencies, model: model)
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
