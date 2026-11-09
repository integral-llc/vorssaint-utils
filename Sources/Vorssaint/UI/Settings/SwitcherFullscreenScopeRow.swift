// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Shown only while current-desktop mode and fullscreen windows are both on,
/// the one combination where fullscreen windows from other desktops get listed.
struct SwitcherFullscreenScopeRow: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.switcherFullscreenFromOtherDesktops) private var includesOtherDesktops = true

    private var strings: SwitcherFullscreenScopeStrings {
        FeatureStrings.switcherFullscreenScope(l10n.language)
    }

    var body: some View {
        SettingsRow(symbol: "rectangle.on.rectangle", title: strings.label, caption: strings.caption) {
            Toggle(strings.label, isOn: $includesOtherDesktops)
                .labelsHidden()
                .onChange(of: includesOtherDesktops) { _, _ in
                    AppSwitcher.shared.syncWithPreferences()
                }
        }
    }
}
