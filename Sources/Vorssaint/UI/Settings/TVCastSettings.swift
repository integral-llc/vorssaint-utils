// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct TVCastSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = TVCastService.shared
    @State private var link = ""
    @State private var pickedID: String?
    @State private var newName = ""
    @State private var code = ""
    @State private var renaming: TVCastDevice?
    @State private var renameDraft = ""
    @State private var removing: TVCastDevice?
    /// Bumped by Pair Again; the scroll and the focus follow on the next
    /// update, once the menu that asked for them has closed.
    @State private var pairAgainRequest = 0
    @FocusState private var codeFocused: Bool

    private static let addSectionID = "tvCast.add"

    private var text: TVCastStrings { FeatureStrings.tvCast(l10n.language) }
    private var isIdle: Bool { service.activity == .idle }
    private var isPairing: Bool { service.activity == .pairing }
    private var selectedID: String? { TVCastSupport.selectedDeviceID(pickedID, in: service.devices) }
    private var linkIsValid: Bool { TVCastSupport.videoArgument(from: link) != nil }
    private var canSend: Bool { linkIsValid && selectedID != nil && isIdle && service.isHelperInstalled }
    private var canPair: Bool {
        TVCastSupport.pairingCode(from: code) != nil && isIdle && service.isHelperInstalled
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                helperNotice
                sendSection
                devicesSection
                addSection
            }
            .formStyle(.grouped)
            .onChange(of: pairAgainRequest) { _, _ in
                withAnimation { proxy.scrollTo(Self.addSectionID, anchor: .bottom) }
                codeFocused = true
            }
        }
        .onAppear { service.reload() }
        .onChange(of: service.outcome) { _, outcome in
            switch outcome {
            case .paired(let id, _):
                code = ""
                newName = ""
                pickedID = id
            case .imported(let ids) where pickedID == nil:
                // The list is published with the outcome, so its order,
                // last used first, decides which imported TV is picked.
                pickedID = service.devices.first { ids.contains($0.id) }?.id
            default:
                break
            }
        }
        .alert(text.renameTitle, isPresented: isPresented($renaming), presenting: renaming) { device in
            TextField(text.nameLabel, text: $renameDraft, prompt: Text(text.namePlaceholder))
            Button(text.cancelButton, role: .cancel) {}
            Button(text.saveButton) { commitRename(device) }
        }
        .confirmationDialog(String(format: text.removeConfirmFormat, removing?.name ?? ""),
                            isPresented: isPresented($removing),
                            titleVisibility: .visible,
                            presenting: removing) { device in
            Button(text.removeButton, role: .destructive) { service.remove(device.id) }
            Button(text.cancelButton, role: .cancel) {}
        } message: { _ in
            Text(text.removeConfirmMessage)
        }
    }

    // MARK: - Sections

    /// First on the page, as the transcriber shows its missing helpers, so a
    /// build without ytcast says so before anyone types a code.
    @ViewBuilder
    private var helperNotice: some View {
        if !service.isHelperInstalled {
            Section {
                Label(text.failureHelperMissing, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sendSection: some View {
        Section(text.sendSection) {
            TextField(text.videoLinkLabel, text: $link, prompt: Text(text.videoLinkPlaceholder))
                .textFieldStyle(.roundedBorder)
                .disabled(sendProgress != nil)
                .onSubmit(send)
            if !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !linkIsValid {
                Text(text.invalidVideo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if service.devices.isEmpty && service.importableCount > 0 {
                // Without TVs the TVs section is hidden, so the offer, and
                // what went wrong with it, stand where the picker will be.
                importOffer
                statusRow(progress: nil, success: nil, failure: failure(during: .edit))
            } else if service.devices.isEmpty {
                Text(text.noTVsHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker(text.tvLabel, selection: selection) {
                    ForEach(service.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                Button(text.sendButton, action: send)
                    .disabled(!canSend)
                statusRow(progress: sendProgress, success: sendSuccess, failure: failure(during: .send))
                Text(text.keepYouTubeOpenHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var devicesSection: some View {
        if !service.devices.isEmpty {
            Section(text.tvsSection) {
                ForEach(service.devices) { device in
                    deviceRow(device)
                }
                if service.importableCount > 0 {
                    importOffer
                }
                statusRow(progress: nil, success: nil, failure: failure(during: .edit))
            }
        }
    }

    /// TVs the command line's ytcast paired that this list lacks. Disabled
    /// while ytcast runs, like the other edits: it would wait behind the run
    /// with no sign of it.
    @ViewBuilder
    private var importOffer: some View {
        Text(text.importCaption)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Button(text.importButton, action: importFromCommandLine)
            .disabled(!isIdle)
    }

    private var addSection: some View {
        Section(text.addSection) {
            Text(text.addInstructions)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(text.nameLabel, text: $newName, prompt: Text(text.namePlaceholder))
                .textFieldStyle(.roundedBorder)
                .disabled(isPairing)
            TextField(text.codeLabel, text: $code, prompt: Text(text.codePlaceholder))
                .textFieldStyle(.roundedBorder)
                .focused($codeFocused)
                .disabled(isPairing)
                .onSubmit(pair)
            Button(text.pairButton, action: pair)
                .disabled(!canPair)
            statusRow(progress: isPairing ? text.pairingStatus : nil,
                      success: pairSuccess,
                      failure: failure(during: .pair))
        }
        .id(Self.addSectionID)
    }

    // MARK: - Rows

    private func deviceRow(_ device: TVCastDevice) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                    if device.lastUsed {
                        lastUsedBadge
                    }
                }
                if device.pairedWithCode {
                    Text(text.pairedWithCodeCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            let actionsLabel = String(format: text.actionsFormat, device.name)
            Menu {
                deviceActions(device)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!isIdle)
            .help(actionsLabel)
            .accessibilityLabel(actionsLabel)
        }
        .contextMenu { deviceActions(device) }
    }

    private var lastUsedBadge: some View {
        Text(text.lastUsedBadge)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    /// Only a TV paired with a code carries a name Vorssaint can change; a
    /// discovered one reports its own. Disabled while ytcast runs: an edit
    /// would wait behind the run with no sign of it, and Pair Again would
    /// rewrite the fields of a pairing in progress.
    private func deviceActions(_ device: TVCastDevice) -> some View {
        Group {
            if device.pairedWithCode {
                Button(text.renameButton) { beginRename(device) }
            }
            Button(text.pairAgainButton) { pairAgain(device) }
            Divider()
            Button(text.removeButton, role: .destructive) { removing = device }
        }
        .disabled(!isIdle)
    }

    /// One place for the progress, success and failure line every section
    /// shows, in the transcriber's colors and symbols.
    @ViewBuilder
    private func statusRow(progress: String?, success: String?, failure: TVCastFailure?) -> some View {
        if let progress {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let success {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let failure {
            Label(text.message(for: failure), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - State

    private var selection: Binding<String> {
        Binding(get: { selectedID ?? "" }, set: { pickedID = $0 })
    }

    private var sendProgress: String? {
        guard case .sending(let name) = service.activity else { return nil }
        return String(format: text.sendingFormat, name)
    }

    private var sendSuccess: String? {
        guard case .sent(let name) = service.outcome else { return nil }
        return String(format: text.sentFormat, name)
    }

    private var pairSuccess: String? {
        guard case .paired(_, let name) = service.outcome else { return nil }
        return String(format: text.pairedFormat, name)
    }

    private func failure(during request: TVCastRequest) -> TVCastFailure? {
        guard case .failed(let failure, let failedRequest) = service.outcome,
              failedRequest == request else { return nil }
        return failure
    }

    private func isPresented<Item>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }

    // MARK: - Actions

    private func send() {
        guard canSend, let id = selectedID else { return }
        service.send(link, to: id)
    }

    private func pair() {
        guard canPair else { return }
        service.pair(code: code, name: newName)
    }

    private func importFromCommandLine() {
        guard isIdle else { return }
        service.importFromCommandLine()
    }

    private func pairAgain(_ device: TVCastDevice) {
        newName = device.name
        code = ""
        pairAgainRequest += 1
    }

    private func beginRename(_ device: TVCastDevice) {
        renameDraft = device.name
        renaming = device
    }

    /// A blank name keeps the old one rather than reaching the cache, which
    /// refuses it.
    private func commitRename(_ device: TVCastDevice) {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != device.name else { return }
        service.rename(device.id, to: name)
    }
}
