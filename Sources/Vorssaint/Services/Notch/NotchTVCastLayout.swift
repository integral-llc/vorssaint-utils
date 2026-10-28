// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

extension NotchLayout {
    /// What the TV plays: its picture, 16:9, beside the title and the clock,
    /// with play or pause and stop at the end.
    static let tvCastNowPlayingHeight: CGFloat = 56
    static let tvCastThumbnailWidth: CGFloat = 96
    static let tvCastThumbnailHeight: CGFloat = 54
    static let tvCastToggleSize: CGFloat = 36
    static let tvCastStopSize: CGFloat = 28
    static let tvCastTransportSpacing: CGFloat = 6
    /// Play Copied Link, its title over the link it plays.
    static let tvCastCopiedLinkHeight: CGFloat = 36
    static let tvCastFieldHeight: CGFloat = 28
    /// Two lines of the status, the most it wraps to.
    static let tvCastStatusHeight: CGFloat = 28
    static let tvCastSpacing: CGFloat = 7
    /// The narrowest the title keeps beside the picture and the transport.
    static let tvCastTitleMinimumWidth: CGFloat = 96
    static let tvCastCardSpacing: CGFloat = 10

    /// The player, a rule, Play Copied Link, the field and the status: a
    /// short page, not a list, so it keeps this height instead of growing to
    /// the chosen island size the way the list pages do.
    static let tvCastPageHeight: CGFloat = tvCastNowPlayingHeight + tvCastSpacing + 1 + tvCastSpacing
        + tvCastCopiedLinkHeight + tvCastSpacing + tvCastFieldHeight + tvCastSpacing + tvCastStatusHeight

    /// The player's row at its narrowest: picture, title and transport.
    static let tvCastNowPlayingMinimumWidth: CGFloat = tvCastThumbnailWidth + tvCastCardSpacing
        + tvCastTitleMinimumWidth + tvCastCardSpacing + tvCastToggleSize + tvCastTransportSpacing + tvCastStopSize
}
