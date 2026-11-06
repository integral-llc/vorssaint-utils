// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The row under "Show the last capture outline" that sets the key capturing it.
struct ScreenshotRepeatRegionStrings {
    let label: String
    let caption: String
}

extension FeatureStrings {
    /// Russian and English like the fork's other additions; every other
    /// interface language reads the English.
    static func screenshotRepeatRegion(_ language: AppLanguage) -> ScreenshotRepeatRegionStrings {
        language == .ru ? .ru : .enUS
    }
}

extension ScreenshotRepeatRegionStrings {
    static let enUS = ScreenshotRepeatRegionStrings(
        label: "Capture the last outline",
        caption: "While the capture screen shows the last outline, this takes that region in one press. R does the same."
    )

    static let ru = ScreenshotRepeatRegionStrings(
        label: "Снять последний контур",
        caption: "Когда на экране съёмки виден последний контур, это сочетание снимает ту же область одним нажатием. Клавиша R делает то же самое."
    )
}
