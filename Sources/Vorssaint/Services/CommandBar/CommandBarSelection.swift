// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// What the person had selected in the app in front when the bar opened.
///
/// This is what turns the bar from a place you go to into something that acts
/// on what you are already doing: select a link and the bar offers to clean
/// it, select a paragraph and it offers to change its case, count it or keep
/// it. Nothing is read while the bar is closed, and the text never leaves the
/// Mac or reaches disk.
enum CommandBarSelectionReader {
    /// A selection longer than this is a document, not a phrase; offering to
    /// retype it would be slower than doing it by hand.
    static let maximumLength = 20_000

    /// The selected text of whatever is in front, read through Accessibility.
    /// Blocking, so callers run it off the main thread. Empty when nothing is
    /// selected, when the app does not tell Accessibility what is selected, or
    /// when the front app is us (the field's own text is not a selection).
    static func readSelectedText() -> String {
        guard AXIsProcessTrusted() else { return "" }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return "" }
        // Asked of the app in front, not of the system-wide element: a timeout
        // set on the system-wide element is the DEFAULT FOR THE WHOLE PROCESS,
        // and every other Accessibility call in the app would inherit this
        // short leash for the rest of the session. The app in front is the one
        // holding the selection anyway; the bar's panel takes keys without
        // activating, so focus never left it.
        let app = AXUIElementCreateApplication(front.processIdentifier)
        // A hung app must not hold the opening of the bar.
        AXUIElementSetMessagingTimeout(app, 0.35)
        guard let focused = copyElement(app, kAXFocusedUIElementAttribute),
              let text = copyString(focused, kAXSelectedTextAttribute) else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= maximumLength ? trimmed : ""
    }

    /// The `length` UTF-16 units of text that end at the caret, or nil when
    /// there is a selection, not that much text, or an app that does not say.
    /// Blocking, on the same short leash as the selection.
    ///
    /// The layout switcher asks this after Return, to tell a new line in a
    /// document from a message that was just sent: nil has to mean "do not
    /// touch the text", so every doubt ends in nil.
    static func readTextBeforeCaret(length: Int) -> String? {
        guard length > 0, AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let app = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.35)
        guard let focused = copyElement(app, kAXFocusedUIElementAttribute),
              let rawSelection = copyValue(focused, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rawSelection) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        guard AXValueGetValue(rawSelection as! AXValue, .cfRange, &selection),
              selection.length == 0, selection.location >= length else { return nil }
        var wanted = CFRange(location: selection.location - length, length: length)
        guard let parameter = AXValueCreate(.cfRange, &wanted) else { return nil }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXStringForRangeParameterizedAttribute as CFString, parameter, &text) == .success
        else { return nil }
        return text as? String
    }

    // MARK: - Accessibility reading

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = copyValue(element, attribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let raw = copyValue(element, attribute),
              CFGetTypeID(raw) == CFStringGetTypeID() else { return nil }
        return raw as? String
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }
}
