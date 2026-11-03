// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Correct-as-you-type is only as good as its refusal to touch a word that was
/// typed right. These run the shipped word lists and character models over a
/// labelled corpus, so a change to a weight or a threshold shows up as a
/// number rather than as somebody's sentence turning to Cyrillic.
enum LayoutDetectionTests {
    // Key for key, the US and Russian layouts. `!` closes both: a key the two
    // agree on, which a real pair has plenty of.
    static let latin = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>~!()"
    static let cyrillic = "йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ!()"

    private struct Row {
        let input: String
        let typedLanguage: String
        let expected: String
        let category: String
    }

    /// Fixed answers, so a test can build the exact near tie it is about.
    private struct StubEvidence: LayoutLanguageEvidence {
        let frequencies: [String: [String: Double]]
        let likelihoods: [String: Double]

        func supports(_ language: String) -> Bool { true }
        func frequency(of word: String, language: String) -> Double? { frequencies[language]?[word] }
        func logLikelihood(of word: String, language: String) -> Double { likelihoods[word] ?? -12 }
    }

    /// Fixed answers plus a fixed set of one-slip neighbours.
    private struct SlipEvidence: LayoutLanguageEvidence {
        let likelihoods: [String: Double]
        let slips: [String: Double]

        func supports(_ language: String) -> Bool { true }
        func frequency(of word: String, language: String) -> Double? { nil }
        func logLikelihood(of word: String, language: String) -> Double { likelihoods[word] ?? -12 }
        func slipFrequency(of word: String, language: String) -> Double? { slips[word] }
    }

    static func run(_ suite: TestSuite) {
        gateChecks(suite)
        bufferChecks(suite)
        contextChecks(suite)
        vocabularyChecks(suite)
        modelChecks(suite)
        slipChecks(suite)

        let table = LayoutSwitcherSupport.table(from: glyphs(latin), to: glyphs(cyrillic))
        suite.expect(table.mapForward("Ghbdtn") == "Привет" && table.mapReverse("Привет") == "Ghbdtn",
                     "a capitalised word maps through the shifted layer and back")

        let evidence = BundledLanguageEvidence(directory: URL(fileURLWithPath: "Resources/LayoutSwitcher"))
        suite.expect(evidence.supports("en") && evidence.supports("ru"),
                     "the shipped word lists and character models load")
        suite.expect(!evidence.supports("xx"), "a language with no shipped data is not claimed")
        guard evidence.supports("en"), evidence.supports("ru") else { return }

        let scorer = LayoutDecisionScorer(evidence: evidence)
        func verdict(_ word: String, typedLanguage: String) -> LayoutDecisionScorer.Verdict? {
            let typedOnLatin = typedLanguage == "en"
            guard let mapped = typedOnLatin ? table.mapForward(word) : table.mapReverse(word)
            else { return nil }
            return scorer.verdict(typed: word, typedLanguage: typedLanguage,
                                  mapped: mapped, mappedLanguage: typedOnLatin ? "ru" : "en")
        }
        func judgement(_ token: String, typedLanguage: String) -> LayoutDecisionScorer.Judgement {
            let typedOnLatin = typedLanguage == "en"
            guard let mapped = typedOnLatin ? table.mapForward(token) : table.mapReverse(token)
            else { return .undecided }
            return scorer.judgement(typed: token, typedLanguage: typedLanguage,
                                    mapped: mapped, mappedLanguage: typedOnLatin ? "ru" : "en")
        }
        func rewritten(_ token: String, typedLanguage: String) -> String? {
            guard case .rewrite(_, let replacement, _) = judgement(token, typedLanguage: typedLanguage)
            else { return nil }
            return replacement
        }
        // The comma and full stop keys are `б` and `ю` on the other layout, so
        // the end of a token reads two ways and only one of them is a word.
        for (token, language, expected) in [
            ("k.,k.", "en", "люблю"), ("[kt,", "en", "хлеб"), ("gjcktle.obt", "en", "последующие"),
            ("ghbdtn,", "en", "привет,"), ("ghbdtn!", "en", "привет!"),
            ("руддщб", "ru", "hello,"), ("руддщю", "ru", "hello."), ("цщкдв!", "ru", "world!"),
            ("(ghbdtn)", "en", "(привет)"), ("(руддщ!", "ru", "(hello!"),
        ] {
            suite.expect(rewritten(token, typedLanguage: language) == expected,
                         "\(token) becomes \(expected), got \(rewritten(token, typedLanguage: language) ?? "nothing")")
        }
        for token in ["file.txt", "example.com", "readme.md", "e.g.", "test,", "hello.", "don't"] {
            suite.expect(rewritten(token, typedLanguage: "en") == nil,
                         "\(token) is left alone: its other spelling is not a word")
        }
        suite.expect(judgement("(test)", typedLanguage: "en") == .keep(word: "test"),
                     "brackets around a word are not part of it")
        suite.expect(judgement("test,", typedLanguage: "en") == .keep(word: "test"),
                     "a kept word is remembered without the punctuation attached to it")

        // The report that started this: an English word, typed on the English
        // layout, retyped as Cyrillic the moment the space landed.
        for word in ["test", "Test", "hello", "layout", "the", "working"] {
            suite.expect(verdict(word, typedLanguage: "en")?.decision == .keep,
                         "\(word) typed on the right layout is left alone")
        }
        for word in ["привет", "Спасибо", "работает"] {
            suite.expect(verdict(word, typedLanguage: "ru")?.decision == .keep,
                         "\(word) typed on the right layout is left alone")
        }
        for (typed, language) in [("ghbdtn", "en"), ("Cgfcb,j", "en"), ("руддщ", "ru"), ("ыщьуерштп", "ru")] {
            let result = verdict(typed, typedLanguage: language)
            suite.expect(result?.decision == .switchLayout && result?.confidence == .high,
                         "\(typed) is recognised as the other layout's word")
        }
        // Three letters that are a word on both layouts: the lists decide, so
        // an abbreviation stays put and a slip into a common word does not.
        for word in ["fps", "gtx", "idf", "cbn", "afp"] {
            suite.expect(verdict(word, typedLanguage: "en")?.decision == .undecided,
                         "\(word) is listed on both layouts and left alone")
        }
        for (typed, expected) in [("ult", "где"), ("nen", "тут"), ("tot", "еще")] {
            suite.expect(rewritten(typed, typedLanguage: "en") == expected,
                         "\(typed) is the far commoner \(expected)")
        }
        // Long words no list carries: settled on their characters in total.
        for (typed, language) in [("rkzepybxfdibq", "en"), ("evelhbdibq", "en"), ("dnbcyedibqcz", "en"),
                                  ("вфскнщсныешешы", "ru")] {
            suite.expect(verdict(typed, typedLanguage: language)?.decision == .switchLayout,
                         "\(typed) is a long word typed on the other layout")
        }
        for word in ["zugreifen", "erfasst", "aktiviert", "Dytiscidae", "unremittingly"] {
            suite.expect(verdict(word, typedLanguage: "en")?.decision != .switchLayout,
                         "\(word) is not Russian however long it is")
        }
        // Punctuation that the other layout reads as a letter counts against
        // the typed spelling, but only when the result is a plausible word.
        for code in ["[str", "{Ver", "{Vers", "{Name", "{Header", "Node{Name", "err;", "a;b"] {
            suite.expect(verdict(code, typedLanguage: "en")?.decision != .switchLayout,
                         "\(code) is code, and a lone bracket does not make it Russian")
        }
        for typed in ["[dfnbn", "{jhjij", "c]tk", "ye;yj", "gj[j;t", "gjl]t[fk", "j,]`v", ";tyz", "[vsrfnm"] {
            let result = verdict(typed, typedLanguage: "en")
            suite.expect(result?.decision == .switchLayout && result?.confidence == .high,
                         "\(typed) is Russian typed through the punctuation keys")
        }
        // Subtitles seldom write ё, so `Хрущёв` reads too unlikely for the
        // brackets to count against the typed spelling; it still switches.
        suite.expect(verdict("{heo`d", typedLanguage: "en")?.decision == .switchLayout,
                     "a name with ё typed through the punctuation keys is still recognised")

        corpusChecks(suite) { word, language in
            // The same road a finished word takes in the app, filter included,
            // so the numbers printed are the numbers somebody typing gets.
            guard LayoutSwitcherSupport.isCorrectable(word, minimumLength: 2) else { return nil }
            switch judgement(word, typedLanguage: language) {
            case .rewrite(_, _, let verdict): return verdict
            case .keep: return LayoutDecisionScorer.Verdict(decision: .keep, confidence: .high, margin: 0)
            case .undecided: return nil
            }
        }
    }

    private static func gateChecks(_ suite: TestSuite) {
        var gate = LayoutConfidenceGate()
        suite.expect(gate.admits(.high, target: "ru"), "a confident correction fires at once")
        suite.expect(!gate.admits(.low, target: "ru"), "a lone doubtful correction is held back")
        suite.expect(gate.admits(.low, target: "ru"), "two doubtful corrections toward one layout fire")
        suite.expect(!gate.admits(.low, target: "ru") && !gate.admits(.low, target: "en"),
                     "a doubtful correction toward another layout starts the count again")
        gate.reset()
        suite.expect(!gate.admits(.low, target: "en"), "a reset forgets the pending correction")

        for code in ["[]Transition", "map[string]int", "<div>", "{name}", "`code`"] {
            suite.expect(LayoutSwitcherSupport.looksStructured(code), "\(code) reads as code")
        }
        suite.expect(!LayoutSwitcherSupport.looksStructured("j,]t[fnm"),
                     "a closing bracket before an opening one is a Russian word, not a pair")
    }

    private static func bufferChecks(_ suite: TestSuite) {
        typealias Finished = LayoutTypingBuffer.Finished
        let early: Set<Character> = ["!", "?", "(", ")"]
        func typed(_ keys: String, into buffer: inout LayoutTypingBuffer) -> [Finished] {
            keys.compactMap { buffer.type(String($0), earlyBoundaries: early) }
        }

        var buffer = LayoutTypingBuffer()
        suite.expect(typed("ghbdtn ", into: &buffer) == [Finished(token: "ghbdtn", ending: .space)]
                        && buffer.typing.isEmpty && buffer.lastFinished == "ghbdtn",
                     "a space finishes the word and leaves it within the shortcut's reach")
        suite.expect(typed(" ", into: &buffer).isEmpty && buffer.lastFinished.isEmpty,
                     "a second space finishes nothing, and the word is no longer behind the caret")

        buffer = LayoutTypingBuffer()
        suite.expect(typed("ghbdtn!", into: &buffer) == [Finished(token: "ghbdtn!", ending: .punctuation)]
                        && buffer.typing == "ghbdtn!",
                     "punctuation no layout reads as a letter ends the word early and stays part of the token")
        suite.expect(typed(" ", into: &buffer) == [Finished(token: "ghbdtn!", ending: .space)],
                     "the space after it still gets the last word on the token")
        buffer = LayoutTypingBuffer()
        suite.expect(typed("cgfcb,j", into: &buffer).isEmpty,
                     "a comma that is a letter on another layout does not end the word")
        var bare = LayoutTypingBuffer()
        suite.expect(typed("(!?", into: &bare).isEmpty, "punctuation with no word before it finishes nothing")

        buffer = LayoutTypingBuffer()
        suite.expect(typed("ghbdtn\r", into: &buffer) == [Finished(token: "ghbdtn", ending: .newline)]
                        && buffer.lastFinished.isEmpty,
                     "Return finishes the word, and puts it out of the shortcut's reach")
        var tabbed = LayoutTypingBuffer()
        suite.expect(typed("word\t", into: &tabbed).isEmpty && tabbed.typing.isEmpty,
                     "other whitespace ends a word without offering it")

        // Backspacing over the space puts the caret back against the word.
        // Leaving it as finished made the next correction delete one too many.
        buffer = LayoutTypingBuffer()
        _ = typed("word ", into: &buffer)
        buffer.deleteBackward()
        suite.expect(buffer.typing == "word" && buffer.lastFinished.isEmpty,
                     "deleting the space resumes the word")
        buffer.deleteBackward()
        suite.expect(buffer.typing == "wor", "deleting again shortens it")

        buffer = LayoutTypingBuffer()
        _ = typed("ghbdtn!", into: &buffer)
        buffer.replaceTyping("ghbdtn!", with: "привет!")
        suite.expect(buffer.typing == "привет!", "an early correction is reflected in the word being typed")
        _ = typed(" ", into: &buffer)
        buffer.replaceLastFinished("привет!", with: "ghbdtn!")
        suite.expect(buffer.lastFinished == "ghbdtn!", "taking a correction back is reflected in the finished word")
        _ = typed(String(repeating: "a", count: 400), into: &buffer)
        suite.expect(buffer.typing.count == LayoutTypingBuffer.limit, "the buffer stays bounded")

        // What may end a word early is read off the layouts, not listed.
        let us: [Int: String] = [0: "a", 1: ",", 2: "!", 3: "^", 4: "?", 5: ";"]
        let russian: [Int: String] = [0: "ф", 1: "б", 2: "!", 3: ",", 4: "?", 5: "ж"]
        let safe = LayoutSwitcherSupport.earlyBoundaries(in: [us, russian])
        suite.expect(safe == ["!", "?", "^"],
                     "only punctuation that is punctuation on every layout ends a word early, got \(safe.sorted())")
        suite.expect(LayoutSwitcherSupport.earlyBoundaries(in: [us]).isEmpty,
                     "with one layout there is nothing to correct and nothing to end early for")
    }

    private static func contextChecks(_ suite: TestSuite) {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var context = LayoutSentenceContext()
        suite.expectClose(context.lean(toward: "en", over: "ru", at: start), 0, "an empty window leans nowhere")
        for offset in 0..<3 { context.record("ru", at: start.addingTimeInterval(Double(offset))) }
        let afterThree = start.addingTimeInterval(3)
        // Counted against the window's capacity, so momentum builds with
        // agreement instead of arriving whole after the first word.
        suite.expectClose(context.lean(toward: "ru", over: "en", at: afterThree), 1.2, "three of five lean part way")
        suite.expectClose(context.lean(toward: "en", over: "ru", at: afterThree), -1.2, "the lean is signed")
        suite.expectClose(context.lean(toward: "en", over: "de", at: afterThree), 0,
                          "a language pair the window has not seen leans nowhere")
        for offset in 3..<9 { context.record("ru", at: start.addingTimeInterval(Double(offset))) }
        suite.expectClose(context.lean(toward: "ru", over: "en", at: start.addingTimeInterval(9)), 2,
                          "the window slides at capacity instead of growing")
        suite.expectClose(context.lean(toward: "ru", over: "en", at: start.addingTimeInterval(30)), 0,
                          "a pause in typing ends the sentence")
        context.record("en", at: start.addingTimeInterval(31))
        suite.expectClose(context.lean(toward: "en", over: "ru", at: start.addingTimeInterval(32)), 0.4,
                          "typing after a pause starts a fresh window")
        context.reset()
        suite.expectClose(context.lean(toward: "en", over: "ru", at: start.addingTimeInterval(32)), 0,
                          "a reset forgets the sentence")

        // Two spellings nothing separates: a word list entry and the same
        // character score on both sides.
        let tie = LayoutDecisionScorer(evidence: StubEvidence(
            frequencies: ["en": ["abc": 3], "ru": ["фис": 3]],
            likelihoods: ["abc": -2, "фис": -2]))
        func tied(_ lean: Double) -> LayoutDecisionScorer.Decision {
            tie.verdict(typed: "abc", typedLanguage: "en", mapped: "фис", mappedLanguage: "ru",
                        contextLean: lean).decision
        }
        suite.expect(tied(0) == .undecided, "a tie with no sentence around it is left alone")
        suite.expect(tied(-2) == .switchLayout, "a Russian sentence tips a tie toward Russian")
        suite.expect(tied(2) == .keep, "an English sentence tips the same tie toward English")

        // The same pair with the letters far apart: three listed letters are
        // still a tie, whatever the character models make of them.
        let lopsided = LayoutDecisionScorer(evidence: StubEvidence(
            frequencies: ["en": ["abc": 3], "ru": ["фис": 3]],
            likelihoods: ["abc": -5, "фис": -2]))
        func lopsidedTie(_ lean: Double) -> LayoutDecisionScorer.Decision {
            lopsided.verdict(typed: "abc", typedLanguage: "en", mapped: "фис", mappedLanguage: "ru",
                             contextLean: lean).decision
        }
        suite.expect(lopsidedTie(0) == .undecided, "a short word listed on both layouts is left to the lists")
        suite.expect(lopsidedTie(-2) == .switchLayout, "and a Russian sentence still tips it")
        evidenceChecks(suite)

        let confident = LayoutDecisionScorer(evidence: StubEvidence(
            frequencies: ["en": ["hello": 6]], likelihoods: ["hello": -1.5]))
        let held = confident.verdict(typed: "hello", typedLanguage: "en", mapped: "руддщ",
                                     mappedLanguage: "ru", contextLean: -2)
        suite.expect(held.decision == .keep && held.confidence == .high,
                     "no sentence overrides a word that is clearly right")
    }

    /// A word neither list carries, 1.3 ahead per character: a near tie at six
    /// letters, settled at thirteen, where that is 18 in total.
    private static func evidenceChecks(_ suite: TestSuite) {
        let long = ("rkzepybxfdibq", "кляузничавший"), short = ("pftlbv", "заедим")
        func scorer(listing listed: [String: [String: Double]] = [:]) -> LayoutDecisionScorer {
            LayoutDecisionScorer(evidence: StubEvidence(frequencies: listed, likelihoods: [
                long.0: -4.3, long.1: -3.0, short.0: -4.3, short.1: -3.0,
                "lt,fhrfltht": -4.3, "дебаркадере": -3.0,
            ]))
        }
        func verdict(_ pair: (String, String), _ scorer: LayoutDecisionScorer,
                     lean: Double = 0) -> LayoutDecisionScorer.Verdict {
            scorer.verdict(typed: pair.0, typedLanguage: "en", mapped: pair.1, mappedLanguage: "ru",
                           contextLean: lean)
        }
        let unlisted = scorer()
        let settled = verdict(long, unlisted)
        suite.expect(settled.decision == .switchLayout && settled.confidence == .low,
                     "a long unlisted word far ahead in total switches, and still waits for a second")
        suite.expect(verdict(long, unlisted, lean: 2).decision == .switchLayout,
                     "a word settled on its own characters is not reopened by the sentence")
        suite.expect(verdict(short, unlisted).decision == .undecided,
                     "the same lead per character on a short word is still a near tie")
        suite.expect(unlisted.verdict(typed: long.1, typedLanguage: "ru", mapped: long.0,
                                      mappedLanguage: "en").decision == .keep,
                     "the evidence settles a word toward the layout it was typed on too")
        suite.expect(verdict(long, scorer(listing: ["en": [long.0: 1], "ru": [long.1: 1]])).decision == .undecided,
                     "listed spellings are judged at the usual bar")
        suite.expect(verdict(("lt,fhrfltht", "дебаркадере"), unlisted).decision == .undecided,
                     "a punctuation key in the word keeps the usual bar")
    }

    /// The character model file: two words, `ab` three times and `ba` once,
    /// counted the way `Tools/build-layout-charmodel.py` counts them.
    private static func modelChecks(_ suite: TestSuite) {
        let counts = ["a\t4", "b\t4", "$\t4", "^a\t3", "^^a\t3", "ab\t3", "^ab\t3", "b$\t3", "ab$\t3",
                      "^b\t1", "^^b\t1", "ba\t1", "^ba\t1", "a$\t1", "ba$\t1"]
        let header = "# charmodel v3 lang=xx order=3 discount=0.75 weight=log1p\n"
        guard let model = CharacterNGramModel(contents: header + counts.joined(separator: "\n") + "\n") else {
            suite.expect(false, "a v3 character model loads")
            return
        }
        suite.expect(model.letters == ["a", "b"], "the alphabet is read off the unigrams, sentinels left out")
        suite.expect(model.logLikelihood("ab") > model.logLikelihood("ba")
                        && model.logLikelihood("ba") > model.logLikelihood("bb")
                        && model.logLikelihood("bb") > model.logLikelihood("bz"),
                     "the commoner word reads best, the unseen one worse, the unseen letter worst")
        suite.expect(model.logLikelihood("AB") == model.logLikelihood("ab"), "case does not count")
        suite.expect(CharacterNGramModel(contents: "# charmodel v2 lang=xx order=4 total_unigrams=8\n"
                                         + counts.joined(separator: "\n") + "\n") == nil,
                     "a model without a discount is refused rather than scored at a bar it was never measured against")
        suite.expect(CharacterNGramModel(contents: header) == nil, "a model with no counts is refused")

        let evidence = BundledLanguageEvidence(directory: URL(fileURLWithPath: "Resources/LayoutSwitcher"))
        suite.expect(evidence.slipFrequency(of: "приветт", language: "ru") == evidence.frequency(of: "привет", language: "ru")
                        && evidence.slipFrequency(of: "пивет", language: "ru") != nil
                        && evidence.slipFrequency(of: "прявет", language: "ru") != nil
                        && evidence.slipFrequency(of: "рпивет", language: "ru") != nil,
                     "a doubled, dropped, replaced or swapped letter is one slip from the word")
        suite.expect(evidence.slipFrequency(of: "uhraf", language: "en") == nil
                        && evidence.slipFrequency(of: "wjrfdibq", language: "en") == nil,
                     "nonsense is one slip from nothing")
        suite.expect(evidence.slipFrequency(of: "привет", language: "xx") == nil,
                     "a language with no data has no neighbours")
    }

    /// One slip from a word of its own layout, and not from one of the other.
    private static func slipChecks(_ suite: TestSuite) {
        func verdict(slips: [String: Double]) -> LayoutDecisionScorer.Verdict {
            let scorer = LayoutDecisionScorer(evidence: SlipEvidence(
                likelihoods: ["fnty": -5, "атен": -2], slips: slips))
            return scorer.verdict(typed: "fnty", typedLanguage: "en", mapped: "атен", mappedLanguage: "ru")
        }
        suite.expect(verdict(slips: [:]).decision == .switchLayout,
                     "three per character ahead, an unlisted four-letter word switches on its characters")
        let typo = verdict(slips: ["fnty": 4])
        suite.expect(typo.decision == .keep && typo.confidence == .low,
                     "a typo of an English word is kept, and not confidently enough to count as typed right")
        suite.expect(verdict(slips: ["fnty": 4, "атен": 2]).decision == .switchLayout,
                     "with a neighbour on both sides the characters decide")
        suite.expect(verdict(slips: ["атен": 2]).decision == .switchLayout,
                     "a neighbour on the other side only is no reason to keep")
    }

    private static func vocabularyChecks(_ suite: TestSuite) {
        let memory = LayoutVocabulary(capacity: 4, persistEvery: 2, defaults: nil)
        memory.recordTyped("Kubectl")
        suite.expect(memory.typedCount(of: "kubectl") == 1 && memory.typedCount(of: "KUBECTL") == 1,
                     "a typed word is counted whatever its case")
        memory.recordTyped("pa55word")
        memory.recordTyped("")
        suite.expect(memory.typedCount(of: "pa55word") == 0,
                     "a token with a digit in it is not vocabulary and is not kept")
        memory.refuse("Tim")
        suite.expect(memory.isRefused("tim") && !memory.isRefused("kubectl"),
                     "a word taken back is remembered as refused")
        for index in 0..<200 { memory.recordTyped("word" + String(repeating: "a", count: index)) }
        suite.expect(memory.storedWordCount <= 4 + LayoutVocabulary.slack(forCapacity: 4),
                     "the counts stay bounded however long the session runs")
        memory.clear()
        suite.expect(!memory.isRefused("tim") && memory.storedWordCount == 0, "forgetting forgets everything")

        let suiteName = "com.vorssaint.tests.layout-vocabulary"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            suite.expect(false, "the test defaults suite opens")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = LayoutVocabulary(capacity: 100, persistEvery: 2, defaults: defaults)
        first.recordTyped("grafana")
        suite.expect(defaults.data(forKey: DefaultsKey.layoutSwitcherVocabulary) == nil,
                     "typed words are written in batches, not one defaults write per word")
        first.recordTyped("grafana")
        first.refuse("tim")
        let second = LayoutVocabulary(capacity: 100, persistEvery: 2, defaults: defaults)
        suite.expect(second.typedCount(of: "grafana") == 2 && second.isRefused("tim"),
                     "what was learned survives a restart")
        second.recordTyped("pending")
        second.flush()
        suite.expect(LayoutVocabulary(capacity: 100, persistEvery: 2, defaults: defaults)
                        .typedCount(of: "pending") == 1,
                     "a flush writes the words a batch had not reached yet")
        second.clear()
        suite.expect(defaults.data(forKey: DefaultsKey.layoutSwitcherVocabulary) == nil,
                     "forgetting removes the stored copy too")
        defaults.set(Data("not json".utf8), forKey: DefaultsKey.layoutSwitcherVocabulary)
        suite.expect(LayoutVocabulary(capacity: 100, persistEvery: 2, defaults: defaults).storedWordCount == 0,
                     "a stored copy that does not decode is ignored, not fatal")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.layoutSwitcherVocabulary),
                     "words somebody typed never travel in a settings backup")

        let habit = LayoutVocabulary(capacity: 100, persistEvery: 100, defaults: nil)
        var personal = LayoutDecisionScorer(evidence: StubEvidence(
            frequencies: [:], likelihoods: ["zork": -3, "ящкл": -3]))
        personal.vocabulary = habit
        func zork() -> LayoutDecisionScorer.Decision {
            personal.verdict(typed: "zork", typedLanguage: "en", mapped: "ящкл", mappedLanguage: "ru").decision
        }
        suite.expect(zork() == .undecided, "an unknown word starts out undecided")
        for _ in 0..<6 { habit.recordTyped("zork") }
        suite.expect(zork() == .keep, "a word typed often enough is recognised as the user's own")
        habit.refuse("ghbdtn")
        var refusing = LayoutDecisionScorer(evidence: StubEvidence(
            frequencies: ["ru": ["привет": 6]], likelihoods: ["привет": -1.5]))
        suite.expect(refusing.verdict(typed: "ghbdtn", typedLanguage: "en", mapped: "привет",
                                      mappedLanguage: "ru").decision == .switchLayout,
                     "the stub word switches when nothing was refused")
        refusing.vocabulary = habit
        suite.expect(refusing.verdict(typed: "ghbdtn", typedLanguage: "en", mapped: "привет",
                                      mappedLanguage: "ru").decision == .keep,
                     "a refused word is never switched again, whatever the evidence")
    }

    private static func corpusChecks(_ suite: TestSuite,
                                     verdict: (String, String) -> LayoutDecisionScorer.Verdict?) {
        // nil from `verdict` means the word was never rewritten: filtered out,
        // unmappable or undecided.
        let rows = corpus()
        suite.expect(rows.count >= 2000, "the corpus loads (\(rows.count) rows)")

        var realWords = 0, falsePositives = 0, wrongLayout = 0, recalled = 0
        var ambiguous = 0, ambiguousHeld = 0
        var confidentFalsePositives: [String] = []
        for row in rows {
            let result = verdict(row.input, row.typedLanguage)
            let switched = result?.decision == .switchLayout
            switch row.category {
            case "real-en", "real-ru", "regression":
                realWords += 1
                if switched { falsePositives += 1 }
                if switched, result?.confidence == .high { confidentFalsePositives.append(row.input) }
            case "ru-on-en", "en-on-ru":
                wrongLayout += 1
                if switched { recalled += 1 }
            case "ambiguous":
                ambiguous += 1
                if !switched { ambiguousHeld += 1 }
            default:
                break
            }
        }
        guard realWords > 0, wrongLayout > 0, ambiguous > 0 else {
            suite.expect(false, "the corpus carries every category the gates need")
            return
        }
        let falsePositiveRate = Double(falsePositives) / Double(realWords)
        let recall = Double(recalled) / Double(wrongLayout)
        let fired = falsePositives + recalled
        let precision = fired == 0 ? 1 : Double(recalled) / Double(fired)
        let heldRate = Double(ambiguousHeld) / Double(ambiguous)
        print(String(format: "layout corpus: FP %.3f%%  recall %.2f%%  precision %.2f%%  ambiguous held %.1f%%",
                     falsePositiveRate * 100, recall * 100, precision * 100, heldRate * 100))
        suite.expect(falsePositiveRate < 0.005, "fewer than 0.5% of real words are switched (\(falsePositiveRate))")
        suite.expect(recall > 0.97, "more than 97% of wrong-layout words are caught (\(recall))")
        suite.expect(precision > 0.99, "more than 99% of switches are right (\(precision))")
        suite.expect(heldRate >= 0.95, "words valid on both layouts are left alone (\(heldRate))")
        suite.expect(confidentFalsePositives.isEmpty,
                     "no real word is switched with confidence: \(confidentFalsePositives)")
    }

    static func glyphs(_ keys: String) -> [Int: String] {
        Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.offset, String($0.element)) })
    }

    private static func corpus() -> [Row] {
        guard let contents = try? String(contentsOfFile: "Tests/Fixtures/layout-corpus.tsv", encoding: .utf8)
        else { return [] }
        return contents.components(separatedBy: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 4 else { return nil }
            return Row(input: fields[0], typedLanguage: fields[1], expected: fields[2], category: fields[3])
        }
    }
}
