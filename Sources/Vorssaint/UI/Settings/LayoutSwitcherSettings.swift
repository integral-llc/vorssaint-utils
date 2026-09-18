// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct LayoutSwitcherSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = LayoutSwitcherService.shared
    @AppStorage(DefaultsKey.layoutSwitcherEnabled) private var enabled = false
    @AppStorage(DefaultsKey.layoutSwitcherAutomatic) private var automatic = false
    @AppStorage(DefaultsKey.layoutSwitcherMinimumWordLength) private var minimumLength =
        Defaults.defaultLayoutSwitcherWordLength

    /// The button's only feedback: nothing else on the page changes when the
    /// words go. Reopening the page offers it again.
    @State private var learnedForgotten = false

    private var text: LayoutSwitcherStrings { FeatureStrings.layoutSwitcher(l10n.language) }

    var body: some View {
        Form {
            Section {
                Toggle(text.enable, isOn: $enabled)
                    .onChange(of: enabled) { _, value in
                        LayoutSwitcherService.shared.syncWithPreferences()
                        guard value, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(text.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section {
                ShortcutPreferenceRow(role: .layoutSwitcher,
                                      isEnabled: enabled,
                                      label: text.shortcutLabel) {
                    LayoutSwitcherService.shared.syncWithPreferences()
                }
                Text(text.shortcutCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section {
                Toggle(text.automatic, isOn: $automatic)
                    .onChange(of: automatic) { _, _ in
                        LayoutSwitcherService.shared.syncWithPreferences()
                    }
                Text(text.automaticCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: $minimumLength,
                        in: Defaults.allowedLayoutSwitcherWordLengthRange,
                        step: 1) {
                    HStack {
                        Text(text.minimumLength)
                        Spacer()
                        Text("\(minimumLength)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .onChange(of: minimumLength) { _, _ in
                    LayoutSwitcherService.shared.syncWithPreferences()
                }
                .disabled(!automatic)
                Text(text.minimumLengthCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!enabled)

            Section {
                Button(learnedForgotten ? text.learnedForgotten : text.forgetLearned) {
                    LayoutSwitcherService.shared.forgetLearnedWords()
                    learnedForgotten = true
                }
                .disabled(learnedForgotten)
                Text(text.forgetLearnedCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
    }
}
