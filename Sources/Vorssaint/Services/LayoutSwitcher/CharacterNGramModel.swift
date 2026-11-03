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
/// The asset holds weighted n-gram counts with `^` and `$` standing for the
/// start and end of a word, built by `Tools/build-layout-charmodel.py`. Scores
/// are interpolated Kneser-Ney probabilities averaged per character, so words
/// of different lengths compare directly. Kneser-Ney because a word on the
/// wrong layout is mostly made of pairs the language never writes next to
/// each other, and what matters about `jr` is not how often it occurs but in
/// how few different places: additive smoothing let `wjrfdibq` off lightly
/// wherever a context was rare, and this does not.
struct CharacterNGramModel {
    private static let startSentinel: Character = "^"
    private static let endSentinel: Character = "$"
    /// Pseudo-count behind the last resort, a character the data never saw
    /// in any context.
    private static let unseenCharacterMass = 0.5

    /// What is known about one context: how much follows it in total and in
    /// how many different ways.
    private struct Context {
        var total = 0.0
        var followers = 0
    }

    private let order: Int
    private let discount: Double
    private let vocabulary: Int
    /// The language's alphabet, as the data saw it.
    let letters: [Character]
    /// Raw weighted counts of the top-order n-grams and the contexts they
    /// extend.
    private let counts: [String: Double]
    private let contexts: [String: Context]
    /// For the lower orders, how many distinct characters precede an n-gram
    /// rather than how often it occurs, and the same per context.
    private let continuations: [String: Double]
    private let continuationContexts: [String: Context]

    init?(contentsOf url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.init(contents: contents)
    }

    init?(contents: String) {
        var order = 0
        var discount = 0.0
        var counts: [String: Double] = [:]
        contents.enumerateLines { line, _ in
            if line.hasPrefix("#") {
                for field in line.split(separator: " ") {
                    let parts = field.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    if parts[0] == "order" { order = Int(parts[1]) ?? order }
                    if parts[0] == "discount" { discount = Double(parts[1]) ?? discount }
                }
                return
            }
            guard let tab = line.firstIndex(of: "\t"),
                  let count = Double(line[line.index(after: tab)...]), count > 0
            else { return }
            let gram = String(line[..<tab])
            if !gram.isEmpty { counts[gram] = count }
        }
        guard order >= 2, discount > 0, discount < 1, !counts.isEmpty else { return nil }
        self.order = order
        self.discount = discount
        self.vocabulary = max(counts.keys.reduce(0) { $0 + ($1.count == 1 ? 1 : 0) }, 1)
        self.letters = counts.keys.compactMap { $0.count == 1 ? $0.first : nil }.filter(\.isLetter).sorted()
        self.counts = counts

        var contexts: [String: Context] = [:]
        var continuations: [String: Double] = [:]
        for (gram, count) in counts where gram.count >= 2 {
            contexts[String(gram.dropLast()), default: Context()].total += count
            contexts[String(gram.dropLast()), default: Context()].followers += 1
            continuations[String(gram.dropFirst()), default: 0] += 1
        }
        var continuationContexts: [String: Context] = [:]
        for (gram, count) in continuations where gram.count >= 2 {
            continuationContexts[String(gram.dropLast()), default: Context()].total += count
            continuationContexts[String(gram.dropLast()), default: Context()].followers += 1
        }
        // The empty context: every character that ever follows anything.
        continuationContexts[""] = Context(total: continuations.filter { $0.key.count == 1 }.values.reduce(0, +),
                                           followers: 0)
        self.contexts = contexts
        self.continuations = continuations
        self.continuationContexts = continuationContexts
    }

    /// Average log-probability per character. Higher reads more like a word.
    func logLikelihood(_ word: String) -> Double {
        let characters = Array(String(repeating: String(Self.startSentinel), count: order - 1)
            + word.lowercased() + String(Self.endSentinel))
        var total = 0.0
        for index in (order - 1)..<characters.count {
            total += log(probability(of: characters, at: index, contextLength: order - 1))
        }
        return total / Double(characters.count - (order - 1))
    }

    /// The seen count less the discount, plus what the discounts freed up
    /// spread over the shorter context's opinion. The top order counts
    /// occurrences; every order below counts distinct predecessors instead.
    private func probability(of characters: [Character], at index: Int, contextLength: Int) -> Double {
        let predicted = String(characters[index])
        guard contextLength > 0 else {
            let known = continuationContexts[""]?.total ?? 0
            return ((continuations[predicted] ?? 0) + Self.unseenCharacterMass)
                / (known + Self.unseenCharacterMass * Double(vocabulary))
        }
        let context = String(characters[(index - contextLength)..<index])
        let shorter = probability(of: characters, at: index, contextLength: contextLength - 1)
        let top = contextLength == order - 1
        guard let seen = (top ? contexts : continuationContexts)[context], seen.total > 0 else { return shorter }
        let count = (top ? counts : continuations)[context + predicted] ?? 0
        let reserved = discount * Double(seen.followers) / seen.total
        return max(count - discount, 0) / seen.total + reserved * shorter
    }
}
