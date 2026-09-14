// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// What a physical key produces on a given keyboard layout.
///
/// Three callers ask this: the shortcut field draws keycaps, mouse navigation
/// finds the key behind a character, and the layout switcher pairs one layout's
/// glyphs against another's. They differ only in the action and the modifier
/// they ask about, so the UCKeyTranslate call itself lives here once.
enum KeyboardLayoutGlyph {
    /// Carbon passes modifiers to UCKeyTranslate already shifted down out of
    /// the high byte its own event records them in, which is the step every
    /// call site used to repeat.
    static func character(in layoutData: Data,
                          keyCode: UInt16,
                          action: Int = kUCKeyActionDown,
                          carbonModifiers: Int = 0,
                          maxLength: Int = 8) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: maxLength)
        let modifierState = UInt32((carbonModifiers >> 8) & 0xFF)
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return OSStatus(paramErr) }
            return UCKeyTranslate(base,
                                  keyCode,
                                  UInt16(action),
                                  modifierState,
                                  UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState,
                                  characters.count,
                                  &length,
                                  &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    /// The layout data behind an input source, or nil for a source that types
    /// through a method rather than a layout of its own.
    static func layoutData(for source: TISInputSource) -> Data? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    static func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
