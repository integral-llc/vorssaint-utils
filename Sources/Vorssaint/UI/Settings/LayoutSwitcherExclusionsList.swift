// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Apps where automatic correction stands down. The shortcut ignores the list.
struct LayoutSwitcherExclusionsList: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var apps: [String] = Self.savedApps

    private var text: LayoutSwitcherExclusionStrings {
        FeatureStrings.layoutSwitcherExclusions(l10n.language)
    }

    var body: some View {
        AppBundleList(title: text.appsTitle,
                      caption: text.appsCaption,
                      addTitle: text.addApp,
                      removeLabel: text.remove,
                      bundleIDs: apps,
                      // Terminals and editors are often running from outside
                      // the Applications folders.
                      reachesEveryApp: true,
                      onAdd: { save(apps + [$0]) },
                      onRemove: { bundleID in save(apps.filter { $0 != bundleID }) })
    }

    private static var savedApps: [String] {
        Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard.stringArray(forKey: DefaultsKey.layoutSwitcherExcludedApps) ?? [])
    }

    private func save(_ bundleIDs: [String]) {
        let sanitized = Defaults.sanitizedBundleIdentifierList(bundleIDs)
        UserDefaults.standard.set(sanitized, forKey: DefaultsKey.layoutSwitcherExcludedApps)
        apps = sanitized
        LayoutSwitcherService.shared.syncWithPreferences()
    }
}

/// Words a correction was taken back on, newest first. Removing one lets
/// automatic mode correct it again.
struct LayoutSwitcherRefusedWordsList: View {
    @ObservedObject private var l10n = L10n.shared
    let words: [String]
    let onRemove: (String) -> Void

    /// Collapsed: the list grows with every correction taken back, and the
    /// page is about the settings above it.
    @State private var isExpanded = false

    private var text: LayoutSwitcherExclusionStrings {
        FeatureStrings.layoutSwitcherExclusions(l10n.language)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if words.isEmpty {
                Text(text.refusedEmpty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(words, id: \.self) { word in
                HStack {
                    Text(word)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button {
                        onRemove(word)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text.remove)
                }
            }
            Text(text.refusedCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(text.refusedTitle)
                Spacer()
                if !words.isEmpty {
                    Text("\(words.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
