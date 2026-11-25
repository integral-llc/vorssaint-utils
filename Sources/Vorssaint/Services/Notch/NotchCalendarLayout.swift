// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the Calendar page of a short island opens with, as its month switch
/// last left it. A tall island always shows the month beside the agenda, so
/// the switch only exists below that. Read through `@AppStorage`, which falls
/// back to the declared default for a value it does not know.
enum NotchCalendarLayout: String, CaseIterable {
    case week
    case month

    static let defaultValue = Self.week

    /// The page's week and month switch, centred above the strip or the grid.
    static let switchWidth: CGFloat = 168
    static let switchHeight: CGFloat = 26
    static let switchInset: CGFloat = 2
    /// The height the switch takes from the page, its gap below included.
    static var switchBand: CGFloat { switchHeight + NotchLayout.rowSpacing }

    /// The switch shows only where the whole-page month grid still keeps its
    /// six rows under it; on a lower page the month title alone toggles.
    static func showsSwitch(pageHeight: CGFloat) -> Bool {
        pageHeight - switchBand >= NotchLayout.calendarMonthMinimumHeight
    }

    /// The month above the agenda keeps its rows short, so a card or two of
    /// upcoming events still shows under it.
    static let stackedRowHeight: CGFloat = 22
    static let stackedAgendaMinimumHeight: CGFloat = 100
    static var stackedGridHeight: CGFloat { NotchLayout.calendarMonthWeekdayHeight + 6 * stackedRowHeight }

    /// Whether a page this tall holds the month grid and the agenda together;
    /// a shorter one gives the grid the whole page, as a day picker.
    static func stacksAgenda(pageHeight: CGFloat) -> Bool {
        pageHeight - stackedGridHeight - NotchLayout.rowSpacing >= stackedAgendaMinimumHeight
    }
}
