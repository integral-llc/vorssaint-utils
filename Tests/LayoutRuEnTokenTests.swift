// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Russian/English rules: which punctuation keys still stand for letters,
/// URLs typed through the Russian layout, and the extra word data.
enum LayoutRuEnTokenTests {
    private struct StubEvidence: LayoutLanguageEvidence {
        let likelihoods: [String: Double]

        func supports(_ language: String) -> Bool { true }
        func frequency(of word: String, language: String) -> Double? { nil }
        func logLikelihood(of word: String, language: String) -> Double { likelihoods[word] ?? -12 }
    }

    private struct Refusing: LayoutPersonalVocabulary {
        let refused: Set<String>

        func isRefused(_ word: String) -> Bool { refused.contains(word.lowercased()) }
        func typedCount(of word: String) -> Int { 0 }
    }

    static func run(_ suite: TestSuite) {
        subtitleWordChecks(suite)
        let evidence = BundledLanguageEvidence(directory: URL(fileURLWithPath: "Resources/LayoutSwitcher"))
        guard evidence.supports("en"), evidence.supports("ru") else {
            suite.expect(false, "the shipped language data loads")
            return
        }
        let scorer = LayoutDecisionScorer(evidence: evidence)
        punctuationChecks(suite, scorer: scorer)
        urlChecks(suite, scorer: scorer)
        otherPairChecks(suite)
    }

    static let table = LayoutSwitcherSupport.table(from: LayoutDetectionTests.glyphs(LayoutDetectionTests.latin),
                                                   to: LayoutDetectionTests.glyphs(LayoutDetectionTests.cyrillic))

    /// Russian - PC puts `.` on the slash key, which is how a URL typed
    /// through it comes out.
    static let pcTable: LayoutGlyphTable = {
        LayoutSwitcherSupport.table(from: LayoutDetectionTests.glyphs(LayoutDetectionTests.latin + "/"),
                                    to: LayoutDetectionTests.glyphs(LayoutDetectionTests.cyrillic + "."))
    }()

    static func judgement(_ scorer: LayoutDecisionScorer, _ token: String, typedLanguage: String,
                          table: LayoutGlyphTable = table) -> LayoutDecisionScorer.Judgement {
        let typedOnLatin = typedLanguage == "en"
        guard let mapped = typedOnLatin ? table.mapForward(token) : table.mapReverse(token)
        else { return .undecided }
        return scorer.judgement(typed: token, typedLanguage: typedLanguage,
                                mapped: mapped, mappedLanguage: typedOnLatin ? "ru" : "en")
    }

    static func rewritten(_ scorer: LayoutDecisionScorer, _ token: String, typedLanguage: String,
                          table: LayoutGlyphTable = table) -> String? {
        guard case .rewrite(_, let replacement, _) = judgement(scorer, token, typedLanguage: typedLanguage,
                                                                 table: table)
        else { return nil }
        return replacement
    }

    private static func subtitleWordChecks(_ suite: TestSuite) {
        let shipped = BundledLanguageEvidence(directory: URL(fileURLWithPath: "Resources/LayoutSwitcher"))
        suite.expect(shipped.frequency(of: "перезвони", language: "ru") != nil,
                     "a chat word from the subtitle list is a known Russian word")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-subtitles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: "Resources/LayoutSwitcher/en_charmodel.dat"),
                                             to: directory.appendingPathComponent("en_charmodel.dat"))
            try "hello\t5.0\n".write(to: directory.appendingPathComponent("en_words.txt"),
                                     atomically: true, encoding: .utf8)
            let bare = BundledLanguageEvidence(directory: directory)
            suite.expect(bare.supports("en") && bare.frequency(of: "zork", language: "en") == nil,
                         "the subtitle list is optional")
            try "hello\t2.0\nzork\t3.1\n".write(to: directory.appendingPathComponent("en_subtitle_words.txt"),
                                                atomically: true, encoding: .utf8)
            let merged = BundledLanguageEvidence(directory: directory)
            suite.expect(merged.frequency(of: "zork", language: "en") == 3.1,
                         "the subtitle list adds words the main list lacks")
            suite.expect(merged.frequency(of: "hello", language: "en") == 5.0,
                         "the main list's frequency wins over the subtitle list's")
        } catch {
            suite.expect(false, "temporary language data could be written: \(error)")
        }
    }

    private static func punctuationChecks(_ suite: TestSuite, scorer: LayoutDecisionScorer) {
        // б, ю and э live on the comma, full stop and apostrophe keys. None of
        // these words is in either list; each is plainly Russian.
        for (typed, expected) in [("hfp,jqysq", "разбойный"),
                                  ("if,kjyty", "шаблонен"), ("j,otpyfxbvjcnm", "общезначимость"),
                                  ("pfhe,wjdsdf.obqcz", "зарубцовывающийся")] {
            let result = rewritten(scorer, typed, typedLanguage: "en")
            suite.expect(result == expected, "\(typed) becomes \(expected), got \(result ?? "nothing")")
        }
        // Punctuation where a machine or English puts it stays punctuation.
        for token in ["file.txt", "example.com", "readme.md", "e.g.", "test,", "hello.", "don't",
                      "o'brien", "\"kaffiyeh\"", ".absent", ".fr", "<div>", "0.9][min(3,", "v1.2"] {
            let result = rewritten(scorer, token, typedLanguage: "en")
            suite.expect(result == nil, "\(token) is left alone, got \(result ?? "")")
        }
    }

    static let urlSpellings = LayoutSwitcherSupport.mistypedURLSpellings(
        english: [LayoutDetectionTests.glyphs(LayoutDetectionTests.latin + "/")],
        russian: [LayoutDetectionTests.glyphs(LayoutDetectionTests.cyrillic + ".")])

    private static func urlChecks(_ suite: TestSuite, scorer: LayoutDecisionScorer) {
        suite.expect(LayoutSwitcherSupport.mistypedURLSpellings(
                        english: [LayoutDetectionTests.glyphs(LayoutDetectionTests.latin + "/")],
                        russian: [[Int: String]]()).isEmpty,
                     "without a Russian layout no token gets past the structure filter as a URL")
        suite.expect(urlSpellings == ["реезЖ..", "реезыЖ..", "аезЖ..", "цццю"].reduce(into: Set<String>()) {
            $0.insert($1.lowercased())
        }, "the URL prefixes are spelled out from the layouts themselves (\(urlSpellings.sorted()))")
        suite.expect(!LayoutSwitcherSupport.isCorrectable("реезыЖ..пщщпдуюсщь", minimumLength: 3),
                     "without the spellings, a Cyrillic URL reads as camel case")
        for (typed, expected) in [("реезыЖ..пщщпдуюсщь", "https://google.com"),
                                  ("реезЖ..учфьздующкп", "http://example.org"),
                                  ("аезЖ..ашдуыютуе", "ftp://files.net"),
                                  ("цццюфзздуюсщь", "www.apple.com"),
                                  ("РЕЕЗЫЖ..пщщпдуюсщь", "HTTPS://google.com"),
                                  ("реезыЖ..пшергиюсщь.штеупкфд-ддс", "https://github.com/integral-llc")] {
            let result = rewritten(scorer, typed, typedLanguage: "ru", table: pcTable)
            suite.expect(result == expected, "\(typed) becomes \(expected), got \(result ?? "nothing")")
            suite.expect(LayoutSwitcherSupport.isCorrectable(typed, minimumLength: 3, urlSpellings: urlSpellings),
                         "\(typed) is not turned away as structured before it is judged")
            if case .rewrite(_, _, let verdict) = judgement(scorer, typed, typedLanguage: "ru", table: pcTable) {
                suite.expect(verdict.confidence == .high, "a URL is fixed at once, not held for a second word")
            }
        }
        suite.expect(rewritten(scorer, "реестр", typedLanguage: "ru", table: pcTable) == nil,
                     "a Russian word that starts like a scheme is not a URL")
        suite.expect(rewritten(scorer, "https://google.com", typedLanguage: "en", table: pcTable) == nil,
                     "a URL typed on the English layout is left alone")

        var refusing = scorer
        refusing.vocabulary = Refusing(refused: ["цццюфзздуюсщь"])
        suite.expect(rewritten(refusing, "цццюфзздуюсщь", typedLanguage: "ru", table: pcTable) == nil,
                     "a URL correction that was taken back is not made again")
    }

    /// Both rules belong to the Russian/English pair. Any other pair keeps
    /// the stricter guard and gets no URL rule.
    private static func otherPairChecks(_ suite: TestSuite) {
        let scorer = LayoutDecisionScorer(evidence: StubEvidence(likelihoods: ["убеди": -2, "https://google.com": -2]))
        func decision(_ typed: String, _ typedLanguage: String, _ mapped: String,
                      _ mappedLanguage: String) -> LayoutDecisionScorer.Judgement {
            scorer.judgement(typed: typed, typedLanguage: typedLanguage, mapped: mapped, mappedLanguage: mappedLanguage)
        }
        if case .rewrite = decision("e,tlb", "en", "убеди", "ru") {} else {
            suite.expect(false, "on ru/en a comma that is plainly б is read as a letter")
        }
        suite.expect(decision("e,tlb", "en", "убеди", "uk") == .undecided,
                     "on another pair an unknown word that needs a comma to be a letter stays undecided")
        if case .rewrite = decision("реезыЖ..пщщпдуюсщь", "uk", "https://google.com", "en") {
            suite.expect(false, "the URL rule does not run for another pair")
        }
    }
}
