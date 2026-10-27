// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Cast to TV in the island: the TV heads the top row, its playback
/// controls end it, and the page plays the link just copied, or one pasted
/// into its field. Pairing and the list of TVs stay on the feature's page in
/// Settings, where an empty page leads.
struct NotchTVCastView: View {
    @ObservedObject private var service = TVCastService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var link = ""
    @State private var pickedID: String?
    /// Play Copied Link found nothing to play. Cleared by typing, and by any
    /// send starting, here or in Settings.
    @State private var copiedLinkMissing = false
    /// The link the field sent, until that send ends. Only its success
    /// clears the field: a typed link survives Play Copied Link or a send
    /// from Settings, and a failed send keeps it for another try.
    @State private var sentFromField: String?
    @FocusState private var linkFocused: Bool
    private var text: TVCastStrings { FeatureStrings.tvCast(l10n.language) }

    private var selectedID: String? { TVCastSupport.selectedDeviceID(pickedID, in: service.devices) }
    private var isIdle: Bool { service.activity == .idle }
    private var canSendTypedLink: Bool {
        isIdle && selectedID != nil && TVCastSupport.videoArgument(from: link) != nil
    }

    var body: some View {
        Group {
            if !service.isHelperInstalled {
                NotchEmptyView(symbol: "exclamationmark.triangle", message: text.failureHelperMissing)
            } else if service.devices.isEmpty {
                NotchTVCastSetupView()
            } else {
                player.notchBand(leading: { tvMenu }, trailing: { playbackControls })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { service.reload() }
        .onChange(of: link) { copiedLinkMissing = false }
        .onChange(of: service.activity) { _, activity in
            if activity == .idle { finishFieldSend() } else { copiedLinkMissing = false }
        }
    }

    private var player: some View {
        VStack(spacing: 10) {
            NotchPillButton(title: text.playCopiedLinkButton, prominent: true, action: playCopiedLink)
                .disabled(!isIdle || selectedID == nil)
            HStack(spacing: 8) {
                linkField
                // Return sends too, but a field alone gives no sign of it. Kept a
                // pill while waiting for a link, so it still reads as a button.
                NotchPillButton(title: text.sendButton, prominent: true, action: sendTypedLink)
                    .disabled(!canSendTypedLink)
                    .opacity(canSendTypedLink ? 1 : 0.45)
            }
            NotchTVCastStatusLine(status: status)
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The chosen TV by name. A pick lasts while the page shows; otherwise
    /// the TV sent to last comes first, as in Settings.
    private var tvMenu: some View {
        let name = service.devices.first { $0.id == selectedID }?.name ?? text.tvLabel
        return NotchMenuButton(title: text.tvLabel, items: service.devices.map { device in
            NotchMenuItem(title: device.name, checked: device.id == selectedID) { pickedID = device.id }
        }, cornerRadius: 9) {
            NotchBandMenuLabel(title: name, symbol: NotchModule.tvCast.symbol, truncation: .middle)
        }
        .help(name)
        .accessibilityValue(name)
    }

    /// Beside the camera, as the Watch page's actions are. What the TV is
    /// doing is not known here, so each command has its own button rather
    /// than one toggle that could offer the wrong one.
    private var playbackControls: some View {
        HStack(spacing: NotchLayout.tvCastPlaybackSpacing) {
            ForEach(TVCastPlayback.allCases, id: \.self) { playback in
                NotchIconButton(symbol: playback.symbol, title: text.title(for: playback)) {
                    if let id = selectedID { service.control(playback, on: id) }
                }
                .disabled(!isIdle || selectedID == nil)
            }
        }
    }

    private var linkField: some View {
        TextField(text.videoLinkLabel, text: $link, prompt: Text(text.videoLinkPlaceholder))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($linkFocused)
            .onSubmit(sendTypedLink)
            .disabled(!isIdle)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(linkFocused ? 0.34 : 0), lineWidth: 1)
            }
            .accessibilityLabel(text.videoLinkLabel)
    }

    /// What is happening now first, then what the page or the last send or
    /// control has to say, and otherwise the reminder Settings gives beside
    /// its button.
    private var status: NotchTVCastStatusLine.Status {
        if let name = service.activity.tvName {
            return .init(kind: .progress, message: String(format: text.sendingFormat, name))
        }
        if copiedLinkMissing { return .init(kind: .warning, message: text.noCopiedLink) }
        if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           TVCastSupport.videoArgument(from: link) == nil {
            return .init(kind: .hint, message: text.invalidVideo)
        }
        switch service.outcome {
        case .sent(let name): return .init(kind: .success, message: String(format: text.sentFormat, name))
        case .controlled(let playback, let name):
            return .init(kind: .success, message: text.controlledMessage(playback, on: name))
        case .failed(let failure, during: .send), .failed(let failure, during: .control):
            return .init(kind: .warning, message: text.message(for: failure))
        default: return .init(kind: .hint, message: text.keepYouTubeOpenHint)
        }
    }

    /// The pasteboard is read on this press only: reading it unasked, on
    /// appearing or on a timer, would raise macOS's paste prompt.
    private func playCopiedLink() {
        guard isIdle, let id = selectedID else { return }
        guard let copied = NSPasteboard.general.string(forType: .string),
              TVCastSupport.videoArgument(from: copied) != nil else {
            copiedLinkMissing = true
            return
        }
        service.send(copied, to: id)
    }

    /// An invalid link already says so in the status line.
    private func sendTypedLink() {
        guard canSendTypedLink, let id = selectedID else { return }
        sentFromField = link
        service.send(link, to: id)
    }

    /// Empties the field for the next link once its own send played, and
    /// takes focus back, which the field lost while it was disabled.
    private func finishFieldSend() {
        guard let sent = sentFromField else { return }
        sentFromField = nil
        guard case .sent = service.outcome, link == sent else { return }
        link = ""
        linkFocused = true
    }
}

/// No TVs yet: pairing needs the TV's code, typed in Settings, so the page
/// leads there. TVs the command line's ytcast already paired come in with
/// one press, as Settings offers.
private struct NotchTVCastSetupView: View {
    @ObservedObject private var service = TVCastService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: TVCastStrings { FeatureStrings.tvCast(l10n.language) }

    var body: some View {
        NotchEmptyView(symbol: NotchModule.tvCast.symbol, message: text.noTVsIslandHint) {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(alignment: .leading, spacing: 6) { buttons }
                }
                if case .failed(let failure, during: .edit) = service.outcome {
                    NotchTVCastStatusLine(status: .init(kind: .warning, message: text.message(for: failure)))
                }
            }
        }
    }

    /// Importing is the step that fills the page at once, so it leads.
    @ViewBuilder private var buttons: some View {
        let importable = service.importableCount > 0
        if importable {
            NotchPillButton(title: text.importButton, prominent: true, action: service.importFromCommandLine)
                .disabled(service.activity != .idle)
        }
        NotchPillButton(title: l10n.s.menuSettings, prominent: !importable, action: openSettings)
    }

    private func openSettings() {
        NotchService.shared.perform {
            SettingsRouter.shared.request(AppFeature.tvCast.settingsDestination)
            (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        }
    }
}

/// One line under the controls, in the colors and symbols Settings uses
/// for the same progress, success and failure.
private struct NotchTVCastStatusLine: View {
    enum Kind {
        case progress, success, warning, hint
    }

    struct Status {
        let kind: Kind
        let message: String
    }

    let status: Status

    var body: some View {
        HStack(spacing: 5) {
            switch status.kind {
            case .progress: ProgressView().controlSize(.mini)
            case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .hint: EmptyView()
            }
            Text(status.message)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
