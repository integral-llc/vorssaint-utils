// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Owns one transcription at a time and publishes what it is doing.
final class YouTubeTranscriberService: ObservableObject {
    static let shared = YouTubeTranscriberService()

    @Published private(set) var phase: TranscriptionPhase = .idle
    @Published private(set) var title = ""
    @Published private(set) var transcript = ""
    @Published private(set) var transcriptPath: String?
    @Published private(set) var failure: TranscriptionFailure?
    @Published private(set) var log: [String] = []

    var isRunning: Bool {
        switch phase {
        case .idle, .finished, .failed: return false
        default: return true
        }
    }

    private let queue = DispatchQueue(label: "com.vorssaint.utils.transcriber", qos: .utility)
    private var pipeline: TranscriptionPipeline?
    private let lock = NSLock()

    private init() {}

    /// Called by the feature runtime when availability changes. A feature
    /// switched off in the hub must not leave a helper running.
    func syncWithPreferences() {
        guard !AppFeature.youtubeTranscriber.isAvailable else { return }
        cancel()
    }

    func suspend() {
        cancel()
    }

    var missingHelpers: [TranscriberHelper] { TranscriberHelpers.missingHelpers }

    func start(source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        guard AppFeature.youtubeTranscriber.isAvailable else { return }

        phase = .readingTitle
        title = ""
        transcript = ""
        transcriptPath = nil
        failure = nil
        log = []

        let defaults = UserDefaults.standard
        let request = TranscriptionPipeline.Request(
            source: trimmed,
            outputDirectory: outputDirectory(),
            location: TranscriptionLocation.sanitized(
                defaults.string(forKey: DefaultsKey.transcriberLocation)),
            remoteHost: defaults.string(forKey: DefaultsKey.transcriberRemoteHost) ?? "",
            modelName: defaults.string(forKey: DefaultsKey.transcriberModel)
                ?? Defaults.defaultTranscriberModel,
            keepAudio: defaults.bool(forKey: DefaultsKey.transcriberKeepAudio)
        )

        let pipeline = TranscriptionPipeline { [weak self] event in
            self?.handle(event)
        }
        lock.withLock { self.pipeline = pipeline }
        queue.async { [weak self] in
            pipeline.run(request)
            self?.lock.withLock { self?.pipeline = nil }
        }
    }

    func cancel() {
        let running = lock.withLock { pipeline }
        running?.cancel()
    }

    // MARK: - Private

    private func handle(_ event: TranscriptionPipeline.Event) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch event {
            case .phase(let phase):
                self.phase = phase
            case .title(let title):
                self.title = title
            case .log(let line):
                self.log = YouTubeTranscriberSupport.appending(line, to: self.log)
            case .finished(let path, let text):
                self.transcriptPath = path
                self.transcript = text
            case .failed(let failure):
                self.failure = failure
            }
        }
    }

    private func outputDirectory() -> URL {
        let configured = UserDefaults.standard.string(forKey: DefaultsKey.transcriberOutputFolder)
        if let configured, !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        return downloads
    }
}
