// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Which language the sentence being typed has been in so far.
///
/// Some words are fine on both layouts, and nothing about the word itself can
/// settle them. The few words before it usually can. The lean this produces is
/// only ever consulted inside a near tie, so it breaks ties and never argues
/// with a word that is clearly right on its own.
///
/// Time comes in as a parameter, so the pause rule is pinned by tests without
/// a clock to fake.
struct LayoutSentenceContext {
    static let windowSize = 5
    /// A gap this long means a new thought, quite possibly in the other language.
    static let pause: TimeInterval = 5
    private static let weight = 1.0

    private var window: [String] = []
    private var lastActivity: Date?

    /// Signed momentum, positive toward `typed`. Counted against the window's
    /// capacity rather than its contents, so it builds with sustained
    /// agreement instead of snapping to full strength after one word.
    func lean(toward typed: String, over mapped: String, at now: Date) -> Double {
        guard let lastActivity, now.timeIntervalSince(lastActivity) <= Self.pause else { return 0 }
        let difference = window.reduce(0) { $0 + ($1 == typed ? 1 : 0) - ($1 == mapped ? 1 : 0) }
        return 2 * Self.weight * Double(difference) / Double(Self.windowSize)
    }

    mutating func record(_ language: String, at now: Date) {
        if let lastActivity, now.timeIntervalSince(lastActivity) > Self.pause { window.removeAll() }
        window.append(language)
        if window.count > Self.windowSize { window.removeFirst(window.count - Self.windowSize) }
        lastActivity = now
    }

    mutating func reset() {
        window.removeAll()
        lastActivity = nil
    }
}
