// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Layout switches the service made itself.
///
/// The system announces every switch the same way, and one made by hand in
/// the middle of a word means the user is fixing that word. A switch that
/// follows a correction is not that, so it is noted before it is made and
/// recognised when the announcement comes back.
struct LayoutOwnSwitches: Equatable {
    /// The announcement arrives within milliseconds. A second is room for a
    /// busy main thread, and short enough that a later switch by hand to the
    /// same layout is still read as the user's.
    static let window: TimeInterval = 1

    private var expected: [String: Date] = [:]

    mutating func expect(_ layoutID: String, at now: Date) {
        expected = expected.filter { $0.value > now }
        expected[layoutID] = now.addingTimeInterval(Self.window)
    }

    /// True when a switch to `layoutID` is one this service made. Each one
    /// accounts for a single announcement.
    mutating func claim(_ layoutID: String, at now: Date) -> Bool {
        guard let deadline = expected.removeValue(forKey: layoutID) else { return false }
        return deadline > now
    }
}
