// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The date as the island divides it around a camera today.
struct NotchDatePreview: View {
    let pattern: String
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = NotchDateFormat.text(pattern, language: l10n.language)
        HStack(spacing: 14) {
            if text.leading.isEmpty { Image(systemName: "calendar").font(.system(size: 11)) }
            else { Text(text.leading) }
            RoundedRectangle(cornerRadius: 4).fill(.black).frame(width: 20, height: 12)
            Text(text.trailing)
        }
        .font(.system(size: 9, weight: .medium)).lineLimit(1)
        .foregroundStyle(.white).padding(10).background(.black, in: Capsule())
    }
}

/// Adds the date to whatever the island shows at rest, in a format of the user's choosing.
struct NotchDateFormatEditor: View {
    @Binding var enabled: Bool
    /// Choosing Custom keeps the current preset as the text to start from, so
    /// the stored format alone cannot say the field should be showing. The
    /// settings page owns it because its tabs rebuild their content.
    @Binding var editing: Bool
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchIdleDateFormat) private var format = NotchDateFormat.defaultPattern
    private var editor: NotchEditorStrings { FeatureStrings.notchEditor(l10n.language) }
    private var isCustom: Bool { editing || !NotchDateFormat.presets.contains(format) }

    private var choice: Binding<String?> {
        Binding(get: { isCustom ? nil : format },
                set: { preset in
                    editing = preset == nil
                    if let preset { format = preset }
                })
    }

    /// Kept as typed, so a space can be followed by more text. Every reader
    /// validates the stored value itself.
    private var typed: Binding<String> {
        Binding(get: { format }, set: { format = String($0.prefix(NotchDateFormat.maximumLength)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(editor.date, isOn: $enabled)
            if enabled {
                HStack {
                    Text(editor.dateFormat)
                    Spacer(minLength: 10)
                    Picker(editor.dateFormat, selection: choice) {
                        ForEach(NotchDateFormat.presets, id: \.self) { preset in
                            // The pattern tells apart formats that read alike on days such as 02/02.
                            Text("\(example(preset))   (\(preset))").tag(String?.some(preset))
                        }
                        Divider()
                        Text(editor.dateCustom).tag(String?.none)
                    }.labelsHidden().fixedSize()
                }
                HStack(spacing: 12) {
                    if isCustom {
                        TextField(editor.dateFormat, text: typed, prompt: Text(NotchDateFormat.defaultPattern))
                            .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled().accessibilityLabel(editor.dateFormat)
                    } else {
                        Spacer(minLength: 0)
                    }
                    NotchDatePreview(pattern: format).accessibilityHidden(true)
                }
                if isCustom {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(NotchDateToken.allCases, id: \.self) { token in
                            chip(token.rawValue, adds: NotchDateFormat.appending(token, to: format)) {
                                Text(example(token.rawValue)).lineLimit(1)
                            }
                        }
                        // Many keyboards hide this character behind a modifier.
                        chip(separator, adds: divided) { Image(systemName: "rectangle.split.2x1") }
                    }
                    Text(editor.dateFormatHint).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var separator: String { String(NotchDatePattern.separator) }

    /// Only the first separator divides the wings, so a second is not offered.
    private var divided: String? {
        let result = format.trimmingCharacters(in: .whitespaces) + " \(separator) "
        return format.contains(separator) || result.count > NotchDateFormat.maximumLength ? nil : result
    }

    private func chip<Detail: View>(_ code: String, adds result: String?, @ViewBuilder detail: () -> Detail) -> some View {
        Button { if let result { format = result } } label: {
            HStack(spacing: 6) {
                Text(code).font(.system(size: 11, weight: .semibold, design: .monospaced))
                detail().font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).disabled(result == nil).opacity(result == nil ? 0.4 : 1)
    }

    private func example(_ pattern: String) -> String {
        let text = NotchDateFormat.text(pattern, language: l10n.language)
        return [text.leading, text.trailing].filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}
