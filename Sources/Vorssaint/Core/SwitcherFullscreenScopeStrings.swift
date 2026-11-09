// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The row under "Show only the current desktop" that decides whether
/// fullscreen windows on other desktops still join the list.
struct SwitcherFullscreenScopeStrings {
    let label: String
    let caption: String
}

extension FeatureStrings {
    /// Russian and English like the fork's other additions; every other
    /// interface language reads the English.
    static func switcherFullscreenScope(_ language: AppLanguage) -> SwitcherFullscreenScopeStrings {
        language == .ru ? .ru : .enUS
    }
}

extension SwitcherFullscreenScopeStrings {
    static let enUS = SwitcherFullscreenScopeStrings(
        label: "Fullscreen windows from other desktops",
        caption: "Turn off to list this desktop only. A fullscreen app then shows up only on its own fullscreen Space."
    )

    static let ru = SwitcherFullscreenScopeStrings(
        label: "Полноэкранные окна с других рабочих столов",
        caption: "Выключите, чтобы показывать только этот рабочий стол. Полноэкранное приложение тогда видно только в своём полноэкранном пространстве."
    )
}
