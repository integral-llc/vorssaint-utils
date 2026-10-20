// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

extension NotchLayout {
    /// A button, a field and a status line, or the empty page's glyph, hint
    /// and buttons: a short page, not a list, so it keeps this height instead
    /// of growing to the chosen island size the way the list pages do.
    static let tvCastPageHeight: CGFloat = 144
}
