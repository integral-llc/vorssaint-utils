// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

extension NotchLayout {
    /// A button, a field and a status line, or the empty page's glyph, hint
    /// and buttons: a short page, not a list, so it keeps this height instead
    /// of growing to the chosen island size the way the list pages do.
    static let tvCastPageHeight: CGFloat = 144
    /// Play, pause and stop beside the camera, 28 points each. Spaced
    /// tighter than the row's 6 so the three fill exactly the narrowest side
    /// a row that wraps the camera keeps: `pageBandSide` past the clearance.
    static let tvCastPlaybackSpacing: CGFloat = 4
    static let tvCastPlaybackWidth: CGFloat = 28 * 3 + tvCastPlaybackSpacing * 2
}
