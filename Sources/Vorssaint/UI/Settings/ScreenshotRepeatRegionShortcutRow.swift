// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Records the in-session key for the last outline. Not a `ShortcutPreferenceRow`:
/// that row checks conflicts against, and registers with, the system-wide hot
/// keys, and this one must never leave the capture session.
struct ScreenshotRepeatRegionShortcutRow: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.screenshotRepeatRegionShortcut)
    private var rawValue = ScreenshotRepeatRegionShortcut.defaultShortcut.storageValue
    @State private var errorText: String?
    @State private var isRecording = false

    private var strings: ScreenshotRepeatRegionStrings {
        FeatureStrings.screenshotRepeatRegion(l10n.language)
    }

    private var shortcut: GlobalShortcut {
        GlobalShortcut(storageValue: rawValue) ?? ScreenshotRepeatRegionShortcut.defaultShortcut
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(strings.label)
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut,
                                       isEnabled: true,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                                       recordingChanged: { recording in
                                           isRecording = recording
                                           if recording { errorText = nil }
                                       },
                                       invalidAction: { errorText = l10n.s.shortcutInvalid },
                                       captureAction: { rawValue = $0.storageValue })
                    .frame(width: 108)
                Button(l10n.s.shortcutReset) {
                    rawValue = ScreenshotRepeatRegionShortcut.defaultShortcut.storageValue
                    errorText = nil
                }
                .disabled(shortcut == ScreenshotRepeatRegionShortcut.defaultShortcut)
            }
            Text(errorText ?? (isRecording
                               ? ShortcutRecordingCaption.text(l10n.s, canClear: false)
                               : strings.caption))
                .font(.caption)
                .foregroundStyle(errorText == nil ? Color.secondary : Color.orange)
        }
    }
}
