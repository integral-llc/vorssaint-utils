// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Cast to TV in the island: the TV heads the top row and says how the
/// link to it stands, what it plays leads the page with its controls, and
/// the page plays the link just copied, or one pasted into its field.
/// Pairing and the list of TVs stay on the feature's page in Settings,
/// where an empty page leads.
struct NotchTVCastView: View {
    @ObservedObject private var service = TVCastService.shared
    @ObservedObject private var live = TVCastNowPlayingService.shared
    @ObservedObject private var clipboard = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    private var selectedName: String { service.devices.first { $0.id == selectedID }?.name ?? text.tvLabel }
    private var isIdle: Bool { service.activity == .idle }
    /// A send or a pairing holds the page. A control is over in a moment and
    /// leaves it as it is: dimming the page for it would only flicker, and
    /// would take focus from the field. A press in that moment does nothing.
    private var isBusy: Bool {
        switch service.activity {
        case .idle, .controlling: return false
        case .sending, .pairing: return true
        }
    }
    private var transportEnabled: Bool { !isBusy && selectedID != nil && live.state.player != nil }
    private var canSendTypedLink: Bool {
        !isBusy && selectedID != nil && TVCastSupport.videoArgument(from: link) != nil
    }
    /// The TV the page follows; none in a Settings preview, which must not
    /// reach the TV, and none without a page to show it on.
    private var followedID: String? {
        preview || !service.isHelperInstalled ? nil : selectedID
    }
    /// The latest copy the clipboard history holds, when it is a YouTube
    /// link: shown under Play Copied Link without reading the pasteboard.
    private var copiedLink: String? {
        guard clipboard.isRunning, let copied = clipboard.latestPasteboardEntry?.text,
              TVCastSupport.videoArgument(from: copied) != nil else { return nil }
        return copied
    }

    var body: some View {
        Group {
            if !service.isHelperInstalled {
                NotchEmptyView(symbol: "exclamationmark.triangle", message: text.failureHelperMissing)
            } else if service.devices.isEmpty {
                NotchTVCastSetupView()
            } else {
                player.notchBand(leading: { tvMenu }, trailing: { linkStatus })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            service.reload()
            live.watch(followedID)
        }
        .onDisappear { live.watch(nil) }
        .onChange(of: followedID) { _, id in live.watch(id) }
        .onChange(of: link) { copiedLinkMissing = false }
        .onChange(of: service.activity) { _, activity in
            if activity == .idle { finishFieldSend() } else { copiedLinkMissing = false }
        }
    }

    private var player: some View {
        VStack(spacing: NotchLayout.tvCastSpacing) {
            nowPlaying
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            copiedLinkButton
            HStack(spacing: 8) {
                linkField
                // Return sends too, but a field alone gives no sign of it. Kept a
                // pill while waiting for a link, so it still reads as a button.
                NotchPillButton(title: text.sendButton, prominent: true, action: sendTypedLink)
                    .disabled(!canSendTypedLink)
                    .opacity(canSendTypedLink ? 1 : 0.45)
            }
            NotchTVCastStatusLine(status: status, alignment: .leading)
                .frame(maxWidth: .infinity, minHeight: NotchLayout.tvCastStatusHeight, alignment: .topLeading)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The chosen TV by name. A pick lasts while the page shows; otherwise
    /// the TV sent to last comes first, as in Settings.
    private var tvMenu: some View {
        NotchMenuButton(title: text.tvLabel, items: service.devices.map { device in
            NotchMenuItem(title: device.name, checked: device.id == selectedID) { pickedID = device.id }
        }, cornerRadius: 9) {
            NotchBandMenuLabel(title: selectedName, symbol: NotchModule.tvCast.symbol, truncation: .middle)
        }
        .help(selectedName)
        .accessibilityValue(selectedName)
    }

    /// How the link to the TV stands, beside the camera.
    private var linkStatus: some View {
        let (label, color): (String, Color) = switch live.state.link {
        case .connected: (text.connectedStatus, .green)
        case .connecting: (text.connectingStatus, .white.opacity(0.35))
        case .away: (text.offlineStatus, .white.opacity(0.35))
        case .failed: (text.offlineStatus, .orange)
        }
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityElement(children: .combine)
    }

    private var nowPlaying: some View {
        HStack(spacing: NotchLayout.tvCastCardSpacing) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(text.nowPlayingCaption)
                    .font(.system(size: 9.5, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                videoTitle
                Text(videoSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let player = live.state.player, player.duration > 0 {
                    timeline(player).padding(.top, 2)
                }
            }
            .lineLimit(1)
            .frame(minWidth: NotchLayout.tvCastTitleMinimumWidth, maxWidth: .infinity, alignment: .leading)
            transport
        }
        .frame(height: NotchLayout.tvCastNowPlayingHeight)
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape.fill(.white.opacity(0.06))
            if let image = live.thumbnail, live.state.player != nil {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: NotchModule.tvCast.symbol)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: NotchLayout.tvCastThumbnailWidth, height: NotchLayout.tvCastThumbnailHeight)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }

    /// While YouTube is asked, a placeholder of a title's length holds the
    /// line; a video it says nothing about goes by YouTube's name.
    @ViewBuilder private var videoTitle: some View {
        let title = Text(live.state.player == nil ? emptyTitle : live.details?.title ?? "YouTube")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(live.state.player == nil ? .secondary : .primary)
        if live.state.player != nil, live.lookingUp {
            Text(verbatim: "A video title of this length").font(.system(size: 13, weight: .semibold))
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        } else {
            title
        }
    }

    private var emptyTitle: String {
        live.state.link == .connecting ? text.connectingStatus : text.nothingPlaying
    }

    private var videoSubtitle: String {
        guard live.state.player != nil else { return selectedName }
        let channel = live.details?.channel ?? ""
        return channel.isEmpty ? "YouTube" : channel + " · YouTube"
    }

    /// The video's longest reading holds each side's width, so the bar keeps
    /// its length as the clock runs.
    private func timeline(_ player: TVCastPlayer) -> some View {
        TimelineView(.animation(minimumInterval: 1, paused: player.phase != .playing)) { context in
            let position = player.position(at: context.date)
            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Text(NotchLockScreenSupport.timestamp(player.duration)).hidden()
                    Text(NotchLockScreenSupport.timestamp(position))
                }
                NotchMeter(value: position / player.duration, height: 4)
                Text(NotchLockScreenSupport.timestamp(player.duration))
            }
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    /// Play or pause, whichever the TV's state calls for, then stop. With
    /// nothing playing there is nothing to control.
    private var transport: some View {
        let toggle: TVCastPlayback = live.state.player?.isUnderWay == true ? .pause : .play
        return HStack(spacing: NotchLayout.tvCastTransportSpacing) {
            Button { control(toggle) } label: {
                Image(systemName: toggle.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: toggle)
                    .frame(width: NotchLayout.tvCastToggleSize, height: NotchLayout.tvCastToggleSize)
                    .background(.white, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.tvCastToggleSize / 2, highlights: false))
            .help(text.title(for: toggle))
            .accessibilityLabel(text.title(for: toggle))
            Button { control(.stop) } label: {
                Image(systemName: TVCastPlayback.stop.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: NotchLayout.tvCastStopSize, height: NotchLayout.tvCastStopSize)
                    .background(.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.tvCastStopSize / 2))
            .help(text.stopButton)
            .accessibilityLabel(text.stopButton)
        }
        .disabled(!transportEnabled)
    }

    /// Its own shortcut, as the island's other pages give their main action
    /// one; a preview in Settings must not take it from the window it sits in.
    private var copiedLinkButton: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button(action: playCopiedLink) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text.playCopiedLinkButton)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    if let shown = copiedLink.flatMap(TVCastSupport.displayLink(for:)) {
                        Text(shown)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: "⇧⌘V")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(height: NotchLayout.tvCastCopiedLinkHeight)
            .background(Color.blue.opacity(0.14), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 10, lifts: false))
        .keyboardShortcut(preview ? nil : KeyboardShortcut("v", modifiers: [.command, .shift]))
        .disabled(isBusy || selectedID == nil)
        .help(text.playCopiedLinkButton)
        .accessibilityLabel(text.playCopiedLinkButton)
        .accessibilityValue(copiedLink.flatMap(TVCastSupport.displayLink(for:)) ?? "")
    }

    private var linkField: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField(text.videoLinkLabel, text: $link, prompt: Text(text.videoLinkPlaceholder))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($linkFocused)
                .onSubmit(sendTypedLink)
                .accessibilityLabel(text.videoLinkLabel)
        }
        .disabled(isBusy)
        .padding(.horizontal, 10)
        .frame(height: NotchLayout.tvCastFieldHeight)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(linkFocused ? 0.34 : 0), lineWidth: 1)
        }
    }

    /// What is happening now first, then what the page or the last request
    /// has to say, then what the TV plays, and otherwise the reminder
    /// Settings gives beside its button. A control's own success says
    /// nothing: the player above already shows it.
    private var status: NotchTVCastStatusLine.Status {
        if case .sending(let name) = service.activity {
            return .init(kind: .progress, message: String(format: text.sendingFormat, name))
        }
        if copiedLinkMissing { return .init(kind: .warning, message: text.noCopiedLink) }
        if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           TVCastSupport.videoArgument(from: link) == nil {
            return .init(kind: .hint, message: text.invalidVideo)
        }
        if case .failed(let failure, let request) = service.outcome, request == .send || request == .control {
            return .init(kind: .warning, message: text.message(for: failure))
        }
        if case .failed(let failure) = live.state.link {
            return .init(kind: .warning, message: text.message(for: failure))
        }
        if let player = live.state.player {
            return player.isUnderWay
                ? .init(kind: .playing, message: String(format: text.sentFormat, selectedName))
                : .init(kind: .paused, message: String(format: text.pausedFormat, selectedName))
        }
        if case .sent(let name) = service.outcome {
            return .init(kind: .success, message: String(format: text.sentFormat, name))
        }
        return .init(kind: .hint, message: text.keepYouTubeOpenHint)
    }

    private func control(_ playback: TVCastPlayback) {
        if let id = selectedID { service.control(playback, on: id) }
    }

    /// What the row shows is what plays. Without it the pasteboard is read
    /// on this press only: reading it unasked, on appearing or on a timer,
    /// would raise macOS's paste prompt.
    private func playCopiedLink() {
        guard isIdle, let id = selectedID else { return }
        guard let copied = copiedLink ?? NSPasteboard.general.string(forType: .string),
              TVCastSupport.videoArgument(from: copied) != nil else {
            copiedLinkMissing = true
            return
        }
        service.send(copied, to: id)
    }

    /// An invalid link already says so in the status line.
    private func sendTypedLink() {
        guard isIdle, canSendTypedLink, let id = selectedID else { return }
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
        /// What the TV does: a dot, green while it plays.
        case playing, paused
    }

    struct Status {
        let kind: Kind
        let message: String
    }

    let status: Status
    /// Centered under an empty page's message, leading on the player's page.
    var alignment: TextAlignment = .center

    var body: some View {
        HStack(spacing: 5) {
            switch status.kind {
            case .progress: ProgressView().controlSize(.mini)
            case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .hint: EmptyView()
            case .playing, .paused:
                Circle().fill(status.kind == .playing ? Color.green : .white.opacity(0.35)).frame(width: 6, height: 6)
            }
            Text(status.message)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .multilineTextAlignment(alignment)
        .accessibilityElement(children: .combine)
    }
}
