// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Week or month at the top of a short island's Calendar page, drawn in the
/// island's own capsules: a system segmented control is drawn for a window
/// and reads as a stranger on the black island.
struct NotchCalendarLayoutSwitch: View {
    @Binding var selection: NotchCalendarLayout
    let text: NotchCalendarStrings
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(NotchCalendarLayout.allCases, id: \.self) { option in
                segment(option)
            }
        }
        .padding(NotchCalendarLayout.switchInset)
        .background(.white.opacity(0.08), in: Capsule())
        .frame(width: NotchCalendarLayout.switchWidth, height: NotchCalendarLayout.switchHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func segment(_ option: NotchCalendarLayout) -> some View {
        let selected = option == selection
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { selection = option }
        } label: {
            Text(title(option))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        Capsule().fill(.white.opacity(0.18))
                            .matchedGeometryEffect(id: "selection", in: highlight)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func title(_ option: NotchCalendarLayout) -> String {
        switch option {
        case .week: return text.weekView
        case .month: return text.month
        }
    }
}
