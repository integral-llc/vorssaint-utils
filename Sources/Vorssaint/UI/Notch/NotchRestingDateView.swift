// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The date as text, kept current on its own. Whoever shows it decides where
/// it goes; the service has already reserved the widest form of every part.
struct NotchRestingDateText: View {
    enum Part { case leading, trailing, whole }
    let part: Part
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchIdleDateFormat) private var format = NotchDateFormat.defaultPattern

    var body: some View {
        // Hourly still catches midnight on days that daylight saving makes 23 or 25 hours long.
        let interval: TimeInterval = NotchDatePattern(NotchDateFormat.sanitized(format)).showsTime ? 60 : 3600
        TimelineView(.periodic(from: Calendar.autoupdatingCurrent.startOfDay(for: Date()), by: interval)) { timeline in
            let text = text(on: timeline.date)
            if text.isEmpty {
                Image(systemName: "calendar").font(.system(size: 12))
            } else {
                Text(text).font(.system(size: NotchLayout.restingTextSize, weight: .medium)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private func text(on date: Date) -> String {
        switch part {
        case .whole: return NotchDateFormat.wholeText(format, language: l10n.language, date: date)
        case .leading: return NotchDateFormat.text(format, language: l10n.language, date: date).leading
        case .trailing: return NotchDateFormat.text(format, language: l10n.language, date: date).trailing
        }
    }
}

/// The resting island while it shows the date, alone or after the battery.
struct NotchRestingDateView: View {
    @ObservedObject var service: NotchService

    private var showsBattery: Bool { service.idleContent == .battery }

    var body: some View {
        let geometry = service.geometry
        if let width = geometry.restingRowWidth {
            // Alone the date is centered; after the battery it keeps to the right.
            HStack(spacing: NotchLayout.restingItemGap) {
                if showsBattery {
                    battery.frame(width: NotchLayout.restingSymbolWidth)
                    charge
                    Spacer(minLength: 0)
                }
                NotchRestingDateText(part: .whole)
            }
            .padding(.horizontal, NotchLayout.restingTextOuterInset)
            .frame(width: width)
        } else if geometry.restingWingWidth > 0 {
            // Everything stays against the camera, so a shorter day only frees the outer edge.
            wing(leading: true) {
                if showsBattery { battery } else { NotchRestingDateText(part: .leading) }
            }.frame(width: geometry.restingWingWidth)
            Color.clear.frame(width: geometry.cameraWidth)
            wing(leading: false) {
                if showsBattery {
                    charge
                    Spacer(minLength: NotchLayout.restingItemGap)
                    NotchRestingDateText(part: .whole)
                } else {
                    NotchRestingDateText(part: .trailing)
                }
            }.frame(width: geometry.restingWingWidth)
        } else {
            Color.clear
        }
    }

    private var battery: some View { Image(systemName: "battery.100percent").font(.system(size: 12)) }

    @ViewBuilder private var charge: some View {
        if let percent = service.power.chargePercent {
            Text("\(percent)%").font(.system(size: NotchLayout.restingValueSize, weight: .medium)).monospacedDigit()
        }
    }

    private func wing<Content: View>(leading: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .padding(leading ? .leading : .trailing, NotchLayout.restingTextOuterInset)
            .padding(leading ? .trailing : .leading, NotchLayout.restingTextInnerInset)
            .frame(maxWidth: .infinity, alignment: leading ? .trailing : .leading)
    }
}
