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

/// One page for the island and the menu panel: the island draws its own
/// tiles and level bar, the panel uses the standard controls around it.
@MainActor
struct QCControlView: View {
    /// Up to this many modes show side by side; more go in a menu.
    private static let maximumInlineModes = 4
    /// Keyboard steps arrive without a drag around them; wait for the last.
    private static let keyboardSettleDelay = Duration.milliseconds(300)

    @Environment(\.notchPresentation) private var inIsland
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BoseHeadphonesService.shared
    @State private var panelID = UUID()
    @State private var level = 0.0
    @State private var pendingLevel: QCPendingLevel?
    @State private var dragging = false
    @State private var pendingCommit: Task<Void, Never>?

    private var text: QCControlStrings { FeatureStrings.qcControl(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { service.panelOpened(panelID) }
        .onDisappear {
            pendingCommit?.cancel()
            service.panelClosed(panelID)
        }
        // Only the level itself moves the slider: battery updates arrive about
        // once a minute and must not discard a change waiting to be sent.
        .onChange(of: service.status?.noiseCancellation, initial: true) { _, noiseCancellation in
            guard !dragging, let noiseCancellation else { return }
            pendingLevel = nil
            level = Double(noiseCancellation)
        }
        // A level waiting to be sent belongs to the mode and headset it was
        // made in; switching either drops it rather than rewriting the new one.
        .onChange(of: editOrigin) {
            discardPendingLevel()
        }
    }

    private var editOrigin: QCPendingLevel.Origin? {
        QCPendingLevel.Origin(deviceID: service.device?.id, status: service.status)
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
                controls(device, status: status)
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

    // MARK: - Connected

    private func controls(_ device: BoseHeadphoneDevice, status: BoseHeadphoneStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(device, status: status)
            modes(status).disabled(service.busy)
            if status.noiseCancellation != nil || status.canSetLevel {
                noiseCancellation(status)
            }
            if !status.canSetLevel { message(text.noCustomMode) }
        }
    }

    private func header(_ device: BoseHeadphoneDevice, status: BoseHeadphoneStatus) -> some View {
        HStack(spacing: 6) {
            if service.devices.count > 1 {
                deviceMenu(label: device.name)
            } else {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if service.busy {
                ProgressView().controlSize(.mini)
            }
            if let battery = status.battery {
                let percent = (Double(battery) / 100).formatted(.percent.locale(l10n.language.formattingLocale()))
                Label(percent, systemImage: Self.batterySymbol(battery))
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(l10n.s.batteryLabel)
                    .accessibilityValue(percent)
            }
        }
    }

    @ViewBuilder
    private func modes(_ status: BoseHeadphoneStatus) -> some View {
        let modes = status.modes
        if modes.count <= Self.maximumInlineModes {
            if inIsland {
                HStack(spacing: 4) {
                    ForEach(modes) { mode in
                        NotchActionTile(symbol: Self.symbol(for: mode), title: mode.name,
                                        active: mode.id == status.activeMode) {
                            if mode.id != status.activeMode { service.selectMode(mode.id) }
                        }
                    }
                }
            } else {
                Picker(text.listeningMode, selection: modeSelection(status)) {
                    ForEach(modes) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
        } else {
            LabeledContent(text.listeningMode) {
                if inIsland {
                    let selection = modes.first { $0.id == status.activeMode }?.name ?? "#\(Int(status.activeMode) + 1)"
                    NotchMenuButton(title: text.listeningMode, items: modes.map { mode in
                        NotchMenuItem(title: mode.name, checked: mode.id == status.activeMode,
                                      enabled: mode.id != status.activeMode) { service.selectMode(mode.id) }
                    }) {
                        NotchBandMenuLabel(title: selection)
                    }
                } else {
                    Picker(text.listeningMode, selection: modeSelection(status)) {
                        ForEach(modes) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .font(.system(size: 11.5, weight: .medium))
        }
    }

    private func modeSelection(_ status: BoseHeadphoneStatus) -> Binding<UInt8> {
        Binding(get: { status.activeMode },
                set: { id in if id != status.activeMode { service.selectMode(id) } })
    }

    private func noiseCancellation(_ status: BoseHeadphoneStatus) -> some View {
        let value = Binding(get: { level }, set: { newValue in
            level = newValue
            if let editOrigin {
                pendingLevel = QCPendingLevel(level: Int(newValue.rounded()), origin: editOrigin)
            }
            scheduleCommit()
        })
        let reading = Int(level.rounded())
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(text.noiseCancellation)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 4)
                Text(reading, format: .number)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            if inIsland {
                NotchLevelSlider(value: value, label: text.noiseCancellation, range: 0...10,
                                 trackThickness: 8, valueLabel: "\(reading)",
                                 onEditingChanged: editingChanged)
                    .frame(height: 24)
            } else {
                Slider(value: value, in: 0...10, onEditingChanged: editingChanged)
                    .controlSize(.small)
                    .accessibilityLabel(text.noiseCancellation)
                    .accessibilityValue("\(reading)")
            }
        }
        .disabled(!status.canSetLevel || service.busy)
    }

    private func editingChanged(_ editing: Bool) {
        dragging = editing
        if editing {
            pendingCommit?.cancel()
        } else {
            commitLevel()
        }
    }

    private func scheduleCommit() {
        pendingCommit?.cancel()
        guard !dragging else { return }
        pendingCommit = Task {
            try? await Task.sleep(for: Self.keyboardSettleDelay)
            guard !Task.isCancelled else { return }
            commitLevel()
        }
    }

    /// Writes only what the person moved to, never the value a fresh reading
    /// put on the slider, and only to the mode it was moved in.
    private func commitLevel() {
        pendingCommit?.cancel()
        pendingCommit = nil
        guard let pending = pendingLevel else { return }
        pendingLevel = nil
        if let target = pending.commitTarget(deviceID: service.device?.id, status: service.status) {
            level = Double(target)
            service.setNoiseCancellation(target, inMode: pending.origin.activeMode)
        } else if let current = service.status?.noiseCancellation {
            level = Double(current)
        }
    }

    private func discardPendingLevel() {
        pendingCommit?.cancel()
        pendingCommit = nil
        pendingLevel = nil
        if !dragging, let current = service.status?.noiseCancellation { level = Double(current) }
    }

    // MARK: - Shared pieces

    private func deviceMenu(label: String) -> some View {
        let items = service.devices.map { device in
            NotchMenuItem(title: device.name, checked: device.id == service.device?.id,
                          enabled: device.id != service.device?.id) { service.connect(to: device.id) }
        }
        return Group {
            if inIsland {
                NotchMenuButton(title: text.choose, items: items) {
                    NotchBandMenuLabel(title: label)
                }
            } else {
                Menu(label) {
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
                .fixedSize()
                .accessibilityLabel(text.choose)
            }
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

    static func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Bose's factory modes keep their preset when renamed; modes people
    /// build in the Bose app get a neutral glyph.
    static func symbol(for mode: BoseHeadphoneMode) -> String {
        switch mode.preset {
        case 1: return "waveform.slash"
        case 2: return "ear.fill"
        case 7: return "tram.fill"
        case 8: return "leaf.fill"
        case 9: return "figure.run"
        case 10: return "house.fill"
        case 11: return "briefcase.fill"
        case 12: return "music.note"
        case 13: return "moon.fill"
        case 14: return "sparkles"
        case 15: return "airplane"
        case 34: return "waveform.and.person.filled"
        case 36: return "film.fill"
        default: return "slider.horizontal.3"
        }
    }
}
