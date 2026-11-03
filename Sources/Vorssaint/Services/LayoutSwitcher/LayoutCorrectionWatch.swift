// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What automatic mode last rewrote, and whether the user is taking it back
/// by hand.
///
/// Backspacing over `привет` and typing `ghbdtn` again is the same answer as
/// pressing the shortcut: the word was meant. Without this the space after it
/// brings the same correction back, and the two keep trading the word.
struct LayoutCorrectionWatch: Equatable {
    struct Correction: Equatable {
        let original: String
        let corrected: String
        /// The word inside `original`, without the punctuation around it.
        let word: String
        /// nil when the layout did not follow the word, so there is none to restore.
        let previousSourceID: String?
    }

    /// The correction the shortcut would take back.
    private(set) var last: Correction?
    /// The user deleted into the corrected word, so what they type next may be
    /// the original coming back.
    private var isContested = false

    mutating func record(_ correction: Correction) {
        last = correction
        isContested = false
    }

    /// Text typed past the correction lets it stand, unless the user is in the
    /// middle of replacing it.
    mutating func typed(_ text: String) {
        guard !text.allSatisfy(\.isWhitespace), !isContested else { return }
        last = nil
    }

    /// After a Backspace, with the buffer as it now stands. Removing only the
    /// space after the word puts the caret back against it; one more key and
    /// the word itself is going.
    mutating func deleted(typing: String, lastFinished: String) {
        guard let last, lastFinished.isEmpty,
              typing.count < last.corrected.count, last.corrected.hasPrefix(typing)
        else { return }
        isContested = true
    }

    /// The correction a finished token takes back, if it is the original typed
    /// again over it. Any finished token ends the contest either way.
    mutating func finished(_ token: String) -> Correction? {
        guard isContested, let contested = last else { return nil }
        last = nil
        isContested = false
        return token == contested.original ? contested : nil
    }

    mutating func clear() {
        last = nil
        isContested = false
    }
}
