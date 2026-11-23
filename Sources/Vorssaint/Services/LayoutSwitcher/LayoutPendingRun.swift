// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The words just behind the caret that nothing has settled yet.
///
/// `z ltkf.` is `я делаю.`, but `z` is one letter and no word list can say
/// which layout it was meant for. Once `ltkf.` is rewritten the sentence has
/// answered, and the words left open before it go over with it. A word that
/// was judged and kept closes the run: it was right where it was, and so is
/// everything before it.
///
/// Only plain letters separated by single spaces join, so the text behind the
/// caret is exactly the words joined by spaces and can be deleted by count.
struct LayoutPendingRun: Equatable {
    struct Word: Equatable {
        let token: String
        /// The service's activity count when the word finished. Orders words
        /// against the verdicts that arrive for them a moment later.
        let activity: UInt64
        /// False for a word that cannot go over itself, such as one with
        /// punctuation in it. It still ends the run for the words after it,
        /// without taking away the ones before it, which may yet follow it.
        let open: Bool
    }

    /// More words than this and the oldest stop being considered.
    static let limit = 8

    private(set) var words: [Word] = []

    /// Every plain word a space finishes joins the run until a verdict
    /// settles it; any other word closes it behind itself. `alreadyCorrected`
    /// is what automatic mode rewrote at its punctuation, which is settled.
    mutating func record(_ finished: LayoutTypingBuffer.Finished, activity: UInt64,
                         tracking: Bool, alreadyCorrected: String?) {
        switch finished.ending {
        case .punctuation:
            // Still being typed: the space after it decides.
            return
        case .newline:
            clear()
        case .space:
            guard tracking else { return clear() }
            append(finished.token, activity: activity,
                   open: !finished.isSkipped && finished.token.allSatisfy(\.isLetter)
                       && finished.token != alreadyCorrected)
        }
    }

    mutating func append(_ token: String, activity: UInt64, open: Bool = true) {
        words.append(Word(token: token, activity: activity, open: open))
        if words.count > Self.limit { words.removeFirst(words.count - Self.limit) }
    }

    /// The word finished at `activity` was judged right as typed, so the run
    /// starts again after it.
    mutating func settle(through activity: UInt64) {
        words.removeAll { $0.activity <= activity }
    }

    mutating func clear() {
        words.removeAll()
    }

    /// A Backspace, told what was behind the caret before it. Fixing a typo
    /// in the word being typed leaves the words before it where they were.
    /// Deleting the space after the last finished word puts the caret back in
    /// it, so it leaves the run and comes back with its next space. Deleting
    /// past that reaches text the run cannot account for.
    mutating func deleted(wasTyping: Bool, hadFinished: Bool) {
        if wasTyping { return }
        if hadFinished, !words.isEmpty {
            words.removeLast()
        } else {
            clear()
        }
    }

    /// The open words directly before the one finished at `activity`, oldest
    /// first. A pause is no reason to stop: it does not move the caret, and
    /// the words before it are still the sentence the rewrite settled.
    func leading(before activity: UInt64) -> [Word] {
        Array(words.filter { $0.activity < activity }.reversed().prefix { $0.open }.reversed())
    }
}

extension LayoutDecisionScorer {
    /// Whether an open word before a rewritten one was meant on the same
    /// layout. The rewrite is the sentence speaking at full strength, which
    /// settles any near tie; what it cannot do is turn a word into one its
    /// language barely uses. `a` stays `a` rather than becoming `ф`, while `z`
    /// becomes `я` and `yt` becomes `не`.
    func followsCorrection(typed: String, typedLanguage: String,
                           mapped: String, mappedLanguage: String) -> Bool {
        guard typed.allSatisfy(\.isLetter), mapped.allSatisfy(\.isLetter) else { return false }
        if typed.count == 1, mapped.count == 1 {
            return Self.isSingleLetterWord(mapped, language: mappedLanguage)
                && !Self.isSingleLetterWord(typed, language: typedLanguage)
        }
        guard let target = knownFrequency(mapped.lowercased(), language: mappedLanguage),
              target >= knownFrequency(typed.lowercased(), language: typedLanguage) ?? -.infinity,
              case .rewrite = judgement(typed: typed, typedLanguage: typedLanguage,
                                        mapped: mapped, mappedLanguage: mappedLanguage,
                                        contextLean: -LayoutSentenceContext.strongestLean)
        else { return false }
        return true
    }

    /// The word lists start at two letters, so the words a single key types
    /// are listed here. A language missing from the table has none known,
    /// and its single letters never follow a correction.
    private static let singleLetterWords: [String: Set<Character>] = [
        "en": ["a", "i"],
        "ru": ["а", "в", "ж", "и", "к", "о", "с", "у", "я"]
    ]

    private static func isSingleLetterWord(_ word: String, language: String) -> Bool {
        guard let letter = word.lowercased().first else { return false }
        return singleLetterWords[language]?.contains(letter) == true
    }
}
