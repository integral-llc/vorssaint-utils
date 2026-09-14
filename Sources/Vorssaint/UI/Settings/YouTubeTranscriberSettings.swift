// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct YouTubeTranscriberSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = YouTubeTranscriberService.shared
    @AppStorage(DefaultsKey.transcriberLocation) private var locationRaw =
        TranscriptionLocation.local.rawValue
    @AppStorage(DefaultsKey.transcriberRemoteHost) private var remoteHost = ""
    @AppStorage(DefaultsKey.transcriberKeepAudio) private var keepAudio = false
    @AppStorage(DefaultsKey.transcriberOutputFolder) private var outputFolder = ""
    @State private var source = ""
    @State private var updateStatus: String?
    @State private var isUpdating = false

    private var text: YouTubeTranscriberStrings { FeatureStrings.youtubeTranscriber(l10n.language) }
    private var location: TranscriptionLocation { TranscriptionLocation.sanitized(locationRaw) }

    var body: some View {
        Form {
            runSection
            resultSection
            engineSection
            outputSection
            helperSection
        }
        .formStyle(.grouped)
    }

    private var runSection: some View {
        Section {
            TextField(text.sourceLabel, text: $source, prompt: Text(text.sourcePlaceholder))
                .textFieldStyle(.roundedBorder)
                .disabled(service.isRunning)
                .onSubmit(start)
            HStack {
                Button(service.isRunning ? text.cancel : text.start) {
                    service.isRunning ? service.cancel() : start()
                }
                .disabled(source.trimmingCharacters(in: .whitespaces).isEmpty && !service.isRunning)
                Spacer()
                if let label = text.label(for: service.phase) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = progressFraction {
                ProgressView(value: fraction)
            }
            if let failure = service.failure {
                Label(text.message(for: failure), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let path = service.transcriptPath {
            Section {
                if !service.title.isEmpty {
                    Text(service.title).font(.headline)
                }
                Text(service.transcript.prefix(600))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button(text.openTranscript) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    Button(text.showInFinder) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    Button(text.copyTranscript) {
                        GeneralPasteboardAccess.shared.async {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(service.transcript, forType: .string)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var engineSection: some View {
        Section {
            Picker(text.locationLabel, selection: $locationRaw) {
                Text(text.locationLocal).tag(TranscriptionLocation.local.rawValue)
                Text(text.locationRemote).tag(TranscriptionLocation.remote.rawValue)
            }
            if location == .remote {
                TextField(text.remoteHostLabel,
                          text: $remoteHost,
                          prompt: Text(text.remoteHostPlaceholder))
                    .textFieldStyle(.roundedBorder)
                Text(text.remoteHostCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(service.isRunning)
    }

    private var outputSection: some View {
        Section {
            HStack {
                Text(text.outputFolder)
                Spacer()
                Text(outputFolder.isEmpty ? "~/Downloads" : outputFolder)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Button("…", action: chooseFolder)
                    .buttonStyle(.borderless)
            }
            Text(text.outputFolderCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(text.keepAudio, isOn: $keepAudio)
            Text(text.keepAudioCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var helperSection: some View {
        Section(text.helpersSection) {
            let missing = service.missingHelpers
            if missing.isEmpty {
                Label(text.helpersReady, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label(String(format: text.helpersMissingFormat,
                             missing.map(\.rawValue).joined(separator: ", ")),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(text.updateButton, action: updateHelper)
                    .disabled(isUpdating)
                if let updateStatus {
                    Text(updateStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(text.updateCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var progressFraction: Double? {
        switch service.phase {
        case .downloadingAudio(let fraction), .uploading(let fraction),
             .transcribing(let fraction):
            return fraction
        default:
            return nil
        }
    }

    private func start() {
        service.start(source: source)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url.path
    }

    private func updateHelper() {
        isUpdating = true
        updateStatus = text.updateChecking
        DispatchQueue.global(qos: .utility).async {
            let current = HelperUpdater.installedVersion()
            let outcome = HelperUpdater.update(currentVersion: current)
            DispatchQueue.main.async {
                isUpdating = false
                switch outcome {
                case .upToDate(let version):
                    updateStatus = String(format: text.updateUpToDateFormat, version)
                case .installed(let version):
                    updateStatus = String(format: text.updateInstalledFormat, version)
                case .offline, .releaseUnreadable, .checksumMissing,
                     .checksumMismatch, .installFailed:
                    updateStatus = text.updateFailed
                }
            }
        }
    }
}
