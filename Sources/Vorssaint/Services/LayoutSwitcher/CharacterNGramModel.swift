// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What words of one language look like, a few characters at a time.
///
/// `ghbdtn` is six Latin letters no English word strings together, and the
/// model says so without needing the word in any list; its other spelling,
/// `привет`, reads as ordinary Russian. That gap is what decides a word the
/// word lists have never seen: a name, slang, an inflection.
///
/// The asset holds raw n-gram counts with `^` and `$` standing for the start
/// and end of a word. Scores are additive-smoothed conditional probabilities
/// averaged per character, so words of different lengths compare directly.
struct CharacterNGramModel {
    private static let startSentinel: Character = "^"
    private static let endSentinel: Character = "$"
    /// Lidstone pseudo-count. The decision thresholds were measured against
    /// this value; changing one without the other moves every margin.
    private static let smoothing = 0.1

    private let order: Int
    private let totalUnigrams: Int
    private let vocabulary: Int
    private let counts: [String: Int]

    init?(contentsOf url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.init(contents: contents)
    }

    init?(contents: String) {
        var order = 4
        var totalUnigrams = 0
        var counts: [String: Int] = [:]
        contents.enumerateLines { line, _ in
            if line.hasPrefix("#") {
                for field in line.split(separator: " ") {
                    let parts = field.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    if parts[0] == "order" { order = Int(parts[1]) ?? order }
                    if parts[0] == "total_unigrams" { totalUnigrams = Int(parts[1]) ?? totalUnigrams }
                }
                return
            }
            guard let tab = line.firstIndex(of: "\t"),
                  let count = Int(line[line.index(after: tab)...]), count > 0
            else { return }
            let gram = String(line[..<tab])
            if !gram.isEmpty { counts[gram] = count }
        }
        guard order >= 1, totalUnigrams > 0, !counts.isEmpty else { return nil }
        self.order = order
        self.totalUnigrams = totalUnigrams
        self.vocabulary = max(counts.keys.reduce(0) { $0 + ($1.count == 1 ? 1 : 0) }, 1)
        self.counts = counts
    }

    /// Average log-probability per character. Higher reads more like a word.
    func logLikelihood(_ word: String) -> Double {
        let characters = Array(String(repeating: String(Self.startSentinel), count: order - 1)
            + word.lowercased() + String(Self.endSentinel))
        var total = 0.0
        for index in (order - 1)..<characters.count {
            total += log(probability(of: characters, at: index))
        }
        return total / Double(characters.count - (order - 1))
    }

    /// The longest context the model has seen decides; an unseen one says
    /// nothing about what follows it, so the next shorter one is asked.
    private func probability(of characters: [Character], at index: Int) -> Double {
        let predicted = String(characters[index])
        var length = order - 1
        while length >= 1 {
            let context = String(characters[(index - length)..<index])
            if let seen = counts[context], seen > 0 {
                let together = counts[context + predicted] ?? 0
                return (Double(together) + Self.smoothing)
                    / (Double(seen) + Self.smoothing * Double(vocabulary))
            }
            length -= 1
        }
        return (Double(counts[predicted] ?? 0) + Self.smoothing)
            / (Double(totalUnigrams) + Self.smoothing * Double(vocabulary))
    }
}
