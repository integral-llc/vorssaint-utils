// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

@MainActor
struct QCControlSection: View {
    var collapsible = true

    var body: some View {
        PanelSection(.qcControl, title: QCControlStrings.title, collapsible: collapsible) {
            QCControlView().panelCard()
        }
    }
}

@MainActor
struct QCControlView: View {
    @Environment(\.notchPresentation) private var inIsland
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BoseHeadphonesService.shared
    @State private var panelID = UUID()
    @State private var level = 0.0

    private var text: QCControlStrings { FeatureStrings.qcControl(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { service.panelOpened(panelID) }
        .onDisappear { service.panelClosed(panelID) }
        .onChange(of: service.status, initial: true) { _, status in
            if let noiseCancellation = status?.noiseCancellation { level = Double(noiseCancellation) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .idle, .noDevices:
            message(text.pair)
            HStack {
                Button(text.find, action: service.findHeadphones)
                settingsButton()
            }
            .controlSize(.small)
        case .checkingBluetooth:
            ProgressView(text.checking).controlSize(.small)
        case .finding, .connecting:
            ProgressView(service.phase == .finding ? text.find : text.connecting).controlSize(.small)
        case .choosing:
            deviceMenu(label: text.choose)
        case .ready:
            if let device = service.device, let status = service.status {
                controls(device, status: status).disabled(service.busy)
            }
        case .bluetoothOff:
            message(text.bluetoothOff)
            settingsButton()
        case .permissionDenied:
            message(text.permission)
            settingsButton(privacy: true)
            Button(text.find, action: service.findHeadphones).controlSize(.small)
        case .unsupported:
            message(text.connectionFailed)
        case .failed(let error):
            message(errorMessage(error))
            Button(text.find, action: service.findHeadphones).controlSize(.small)
        }
    }

    private func controls(_ device: BoseHeadphoneDevice, status: BoseHeadphoneStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if service.devices.count > 1 {
                    deviceMenu(label: device.name)
                } else {
                    Text(device.name).font(.callout.weight(.semibold)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let battery = status.battery {
                    let percent = (Double(battery) / 100).formatted(.percent.locale(l10n.language.formattingLocale()))
                    Label(percent, systemImage: "battery.100percent")
                        .font(.caption.monospacedDigit())
                        .accessibilityLabel(l10n.s.batteryLabel)
                        .accessibilityValue(percent)
                }
            }
            Divider()
            LabeledContent(text.listeningMode) {
                let current = status.modes.first { $0.id == status.activeMode }
                let selection = current?.name ?? "#\(Int(status.activeMode) + 1)"
                let items = status.modes.map { mode in
                    NotchMenuItem(title: mode.name, checked: mode.id == status.activeMode,
                                  enabled: mode.id != status.activeMode) { service.selectMode(mode.id) }
                }
                menu(title: text.listeningMode, selection: selection, items: items)
                    .accessibilityValue(selection)
            }
            .font(.callout)
            if status.noiseCancellation != nil || status.canSetLevel {
                noiseControls(status)
            }
            if !status.canSetLevel { message(text.noCustomMode) }
            HStack {
                Button(text.refresh, action: service.refresh)
                    .controlSize(.small)
                if service.busy {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func noiseControls(_ status: BoseHeadphoneStatus) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LabeledContent(text.noiseCancellation) {
                Text(level, format: .number.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            HStack {
                Slider(value: $level, in: 0...10, step: 1) { Text(text.noiseCancellation) }
                    .labelsHidden()
                Button(text.apply) { service.setNoiseCancellation(Int(level)) }
                    .disabled(Int(level) == status.noiseCancellation && status.liveSettings?.last != 0)
            }
            .disabled(!status.canSetLevel)
            .controlSize(.small)
        }
        .font(.callout)
    }

    private func deviceMenu(label: String) -> some View {
        let items = service.devices.map { device in
            NotchMenuItem(title: device.name, checked: device.id == service.device?.id,
                          enabled: device.id != service.device?.id) { service.connect(to: device.id) }
        }
        return menu(title: text.choose, selection: label, items: items)
    }

    @ViewBuilder
    private func menu(title: String, selection: String, items: [NotchMenuItem]) -> some View {
        if inIsland {
            NotchMenuButton(title: title, items: items) {
                NotchBandMenuLabel(title: selection)
            }
        } else {
            Menu(selection) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    Button(action: item.action) {
                        if item.checked { Label(item.title, systemImage: "checkmark") }
                        else { Text(item.title) }
                    }
                    .disabled(!item.enabled)
                }
            }
            .controlSize(.small)
            .accessibilityLabel(title)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsButton(privacy: Bool = false) -> some View {
        Button(l10n.s.permissionOpenSettings) {
            let pane = privacy ? "com.apple.preference.security?Privacy_Bluetooth" : "com.apple.BluetoothSettings"
            if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
        }
        .buttonStyle(.link)
        .controlSize(.small)
    }

    private func errorMessage(_ error: BoseHeadphoneError) -> String {
        switch error {
        case .disconnected, .timedOut: return text.connectionFailed
        case .rejected, .invalidResponse: return text.controlFailed
        case .noCustomMode: return text.noCustomMode
        }
    }
}
