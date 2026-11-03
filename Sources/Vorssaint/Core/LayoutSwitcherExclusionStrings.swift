// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The two lists on the Layout Switcher page: apps where automatic correction
/// stands down, and words it was told to leave alone.
struct LayoutSwitcherExclusionStrings {
    let appsTitle: String
    let addApp: String
    let remove: String
    let appsCaption: String
    let refusedTitle: String
    let refusedCaption: String
    let refusedEmpty: String
}

extension FeatureStrings {
    /// Written for the Russian and English pair the lists serve; every other
    /// interface language reads the English.
    static func layoutSwitcherExclusions(_ language: AppLanguage) -> LayoutSwitcherExclusionStrings {
        language == .ru ? .ru : .enUS
    }
}

extension LayoutSwitcherExclusionStrings {
    static let enUS = LayoutSwitcherExclusionStrings(
        appsTitle: "Don’t correct as you type in these apps",
        addApp: "Add an app…",
        remove: "Remove",
        appsCaption: "Terminals and code editors are good candidates. The shortcut still works in these apps.",
        refusedTitle: "Words left as typed",
        refusedCaption: "Corrections you took back, with the shortcut or by deleting the word and typing it again. Remove one to have it corrected again.",
        refusedEmpty: "None yet."
    )

    static let ru = LayoutSwitcherExclusionStrings(
        appsTitle: "Не исправлять при наборе в этих приложениях",
        addApp: "Добавить приложение…",
        remove: "Удалить",
        appsCaption: "Подходят терминалы и редакторы кода. Сочетание клавиш в этих приложениях по-прежнему работает.",
        refusedTitle: "Слова, оставленные как набраны",
        refusedCaption: "Исправления, которые вы отменили сочетанием клавиш или стерев слово и набрав его заново. Удалите слово, чтобы оно снова исправлялось.",
        refusedEmpty: "Пока нет."
    )
}
