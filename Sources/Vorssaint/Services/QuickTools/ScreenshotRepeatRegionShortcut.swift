// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

extension DefaultsKey {
    static let screenshotRepeatRegionShortcut = "screenshotRepeatRegionShortcut" // GlobalShortcut storage value
}

/// The recordable key that captures the outlined last region while a capture
/// session is on screen. It lives only inside the session's key monitor and is
/// never registered as a system-wide hot key, so the default Command-Return
/// keeps working everywhere else. R still repeats the region too.
enum ScreenshotRepeatRegionShortcut {
    static let defaultShortcut = GlobalShortcut(keyCode: Int64(kVK_Return), modifiers: [.command])

    /// A primary modifier is required: bare letters, digits, arrows, Return
    /// and Space already drive the session.
    static func saved(_ defaults: UserDefaults = .standard) -> GlobalShortcut {
        defaults.string(forKey: DefaultsKey.screenshotRepeatRegionShortcut)
            .flatMap { GlobalShortcut(storageValue: $0) } ?? defaultShortcut
    }

    /// Return and the keypad Enter are one key to the session's own confirm,
    /// so they stay one key here too.
    static func matches(_ shortcut: GlobalShortcut,
                        keyCode: Int,
                        modifiers: GlobalShortcutModifiers) -> Bool {
        modifiers == shortcut.modifiers
            && normalized(Int64(keyCode)) == normalized(shortcut.keyCode)
    }

    /// The compact key cap the capture guide shows.
    static func hint(for shortcut: GlobalShortcut) -> String {
        let key = isReturn(shortcut.keyCode) ? "↩" : shortcut.keyCaps.last ?? ""
        return shortcut.modifiers.keyCaps.joined() + key
    }

    private static func isReturn(_ keyCode: Int64) -> Bool {
        keyCode == Int64(kVK_Return) || keyCode == Int64(kVK_ANSI_KeypadEnter)
    }

    private static func normalized(_ keyCode: Int64) -> Int64 {
        isReturn(keyCode) ? Int64(kVK_Return) : keyCode
    }
}
