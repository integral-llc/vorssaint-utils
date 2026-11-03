// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Gates per kind of input, on words the word lists have never seen and on
/// this repository's own code. One overall rate would let a change buy recall
/// on Russian with false corrections in a terminal; a rate per class cannot.
/// See `Tests/Fixtures/layout-independent.md` for where every row comes from.
enum LayoutIndependentCorpusTests {
    private struct Gate {
        /// Share of `switch` rows rewritten, at least.
        let recall: Double?
        /// Share of `keep` rows rewritten, at most.
        let falseCorrections: Double
    }

    private struct Tally {
        var switchRows = 0, switched = 0, keepRows = 0, rewritten = 0
        var falseSamples: [String] = []

        var recall: Double { switchRows == 0 ? 1 : Double(switched) / Double(switchRows) }
        var falseRate: Double { keepRows == 0 ? 0 : Double(rewritten) / Double(keepRows) }

        mutating func add(expected: String, rewritten isRewritten: Bool, input: String) {
            if expected == "switch" {
                switchRows += 1
                if isRewritten { switched += 1 }
            } else {
                keepRows += 1
                if isRewritten {
                    rewritten += 1
                    falseSamples.append(input)
                }
            }
        }
    }

    /// Set just under what the shipped data measured on 2026-11-03, so noise
    /// passes and a real regression does not: unknown words 98.9% (ru) and
    /// 99.4% (en) with no false correction, code 0.047%, the rest 0.
    private static let gates: [String: Gate] = [
        "unknown-ru": Gate(recall: 0.985, falseCorrections: 0.001),
        "unknown-en": Gate(recall: 0.99, falseCorrections: 0.001),
        "typo-ru": Gate(recall: nil, falseCorrections: 0.001),
        "typo-en": Gate(recall: nil, falseCorrections: 0.001),
        "name-ru": Gate(recall: nil, falseCorrections: 0.001),
        "name-en": Gate(recall: nil, falseCorrections: 0.001),
        "punctuation": Gate(recall: nil, falseCorrections: 0),
        "url": Gate(recall: 1, falseCorrections: 0),
        "code": Gate(recall: nil, falseCorrections: 0.0007),
    ]

    static func run(_ suite: TestSuite) {
        let evidence = BundledLanguageEvidence(directory: URL(fileURLWithPath: "Resources/LayoutSwitcher"))
        guard evidence.supports("en"), evidence.supports("ru") else {
            suite.expect(false, "the shipped language data loads")
            return
        }
        let scorer = LayoutDecisionScorer(evidence: evidence)
        var tallies: [String: Tally] = [:]
        for row in fixtureRows() {
            let rewritten = isRewritten(row.input, typedLanguage: row.typedLanguage, scorer: scorer)
            tallies[row.category, default: Tally()].add(expected: row.expected, rewritten: rewritten, input: row.input)
        }
        for token in codeTokens() {
            let rewritten = isRewritten(token, typedLanguage: "en", scorer: scorer)
            tallies["code", default: Tally()].add(expected: "keep", rewritten: rewritten, input: token)
        }
        for (category, gate) in gates.sorted(by: { $0.key < $1.key }) {
            guard let tally = tallies[category], tally.switchRows + tally.keepRows > 0 else {
                suite.expect(false, "the independent corpus has rows for \(category)")
                continue
            }
            print(String(format: "layout %@: recall %.2f%% (%d)  false %.3f%% (%d of %d) %@", category,
                         tally.recall * 100, tally.switchRows, tally.falseRate * 100, tally.rewritten,
                         tally.keepRows, tally.falseSamples.prefix(6).joined(separator: " ")))
            if let recall = gate.recall {
                suite.expect(tally.recall >= recall, "\(category): recall \(tally.recall) is at least \(recall)")
            }
            suite.expect(tally.falseRate <= gate.falseCorrections,
                         "\(category): false corrections \(tally.falseRate) stay at most \(gate.falseCorrections)")
        }
    }

    /// The road a finished word takes in the app: the filter, then judgement.
    private static func isRewritten(_ token: String, typedLanguage: String, scorer: LayoutDecisionScorer) -> Bool {
        guard LayoutSwitcherSupport.isCorrectable(token, minimumLength: Defaults.defaultLayoutSwitcherWordLength,
                                                  urlSpellings: LayoutRuEnTokenTests.urlSpellings)
        else { return false }
        if case .rewrite = LayoutRuEnTokenTests.judgement(scorer, token, typedLanguage: typedLanguage,
                                                         table: LayoutRuEnTokenTests.pcTable) {
            return true
        }
        return false
    }

    private static func fixtureRows() -> [(input: String, typedLanguage: String, expected: String, category: String)] {
        guard let contents = try? String(contentsOfFile: "Tests/Fixtures/layout-independent.tsv", encoding: .utf8)
        else { return [] }
        return contents.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard !line.hasPrefix("#"), fields.count == 4 else { return nil }
            return (fields[0], fields[1], fields[2], fields[3])
        }
    }

    /// Every distinct whitespace-separated token in the app's Swift sources:
    /// identifiers, members, string literals, punctuation runs. Read live, so
    /// the gate follows the code as it grows.
    private static func codeTokens() -> Set<String> {
        guard let files = FileManager.default.enumerator(atPath: "Sources/Vorssaint") else { return [] }
        var tokens = Set<String>()
        for case let path as String in files where path.hasSuffix(".swift") {
            guard let text = try? String(contentsOfFile: "Sources/Vorssaint/" + path, encoding: .utf8) else { continue }
            for token in text.split(whereSeparator: \.isWhitespace) where (3...24).contains(token.count)
                && token.allSatisfy({ $0.isASCII && !$0.isWhitespace }) && token.contains(where: \.isLetter) {
                tokens.insert(String(token))
            }
        }
        return tokens
    }
}
