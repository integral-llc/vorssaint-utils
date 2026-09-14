// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One transcription run, from what the user pasted to a transcript on disk.
///
/// Runs on a queue of its own and reports back through `onEvent`; the service
/// owns the published state and does the hop to the main thread.
final class TranscriptionPipeline: @unchecked Sendable {
    enum Event {
        case phase(TranscriptionPhase)
        case title(String)
        case log(String)
        case finished(transcriptPath: String, text: String)
        case failed(TranscriptionFailure)
    }

    struct Request {
        let source: String
        let outputDirectory: URL
        let location: TranscriptionLocation
        let remoteHost: String
        let modelName: String
        let keepAudio: Bool
    }

    private let runner = StreamingProcessRunner()
    private let onEvent: (Event) -> Void
    private var log: [String] = []
    private let logLock = NSLock()

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    func cancel() {
        runner.cancel()
    }

    func run(_ request: Request) {
        runner.reset()
        logLock.withLock { log = [] }

        let audio: String
        if YouTubeTranscriberSupport.isLocalFile(request.source) {
            audio = expanded(request.source)
            guard FileManager.default.isReadableFile(atPath: audio) else {
                return fail(.notMedia)
            }
        } else {
            guard let downloaded = downloadAudio(request) else { return }
            audio = downloaded
        }

        onEvent(.phase(.measuringAudio))
        let duration = probeDuration(of: audio)

        let transcript: String?
        switch request.location {
        case .local:
            transcript = transcribeLocally(audio: audio, request: request, duration: duration)
        case .remote:
            transcript = transcribeRemotely(audio: audio, request: request)
        }

        guard let transcript else { return }
        if !request.keepAudio, !YouTubeTranscriberSupport.isLocalFile(request.source) {
            try? FileManager.default.removeItem(atPath: audio)
        }

        let path = transcriptPath(forAudio: audio, in: request.outputDirectory)
        do {
            try transcript.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            return fail(.diskFull)
        }
        onEvent(.phase(.finished))
        onEvent(.finished(transcriptPath: path, text: transcript))
    }

    // MARK: - Steps

    private func downloadAudio(_ request: Request) -> String? {
        guard let ytDlp = TranscriberHelpers.path(for: .ytDlp) else {
            fail(.helperMissing(.ytDlp))
            return nil
        }
        guard let ffmpeg = TranscriberHelpers.path(for: .ffmpeg) else {
            fail(.helperMissing(.ffmpeg))
            return nil
        }

        onEvent(.phase(.readingTitle))
        var title = ""
        _ = runner.run(executable: ytDlp,
                       arguments: ["--print", "title", "--no-playlist", "--no-warnings",
                                   request.source]) { [weak self] line in
            self?.record(line)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("[") { title = trimmed }
        }
        if !title.isEmpty { onEvent(.title(title)) }
        if runner.isCancelled { fail(.cancelled); return nil }

        onEvent(.phase(.downloadingAudio(fraction: 0)))
        // The file yt-dlp writes is named from the video title, which is not
        // knowable up front. Taking "whatever appeared" rather than "the newest
        // one" matters: the audio is deleted afterwards, and the output folder
        // is the user's Downloads by default.
        let before = audioFiles(in: request.outputDirectory)
        let template = request.outputDirectory
            .appendingPathComponent("%(title)s.%(ext)s").path
        let status = runner.run(
            executable: ytDlp,
            arguments: [request.source,
                        "--extract-audio", "--audio-format", "mp3", "--audio-quality", "0",
                        "--output", template, "--newline", "--no-playlist",
                        "--no-progress-template",
                        "--ffmpeg-location", (ffmpeg as NSString).deletingLastPathComponent]
        ) { [weak self] line in
            guard let self else { return }
            self.record(line)
            if let fraction = YouTubeTranscriberSupport.downloadFraction(in: line) {
                self.onEvent(.phase(.downloadingAudio(fraction: fraction)))
            }
        }
        if runner.isCancelled { fail(.cancelled); return nil }
        guard status == 0 else {
            fail(YouTubeTranscriberSupport.diagnose(log: snapshotLog(),
                                                    helper: .ytDlp,
                                                    exitCode: status))
            return nil
        }
        let appeared = audioFiles(in: request.outputDirectory).subtracting(before)
        guard let produced = newest(of: appeared, in: request.outputDirectory) else {
            fail(.notMedia)
            return nil
        }
        return produced
    }

    private func probeDuration(of path: String) -> Double {
        guard let ffprobe = TranscriberHelpers.path(for: .ffprobe) else { return 0 }
        var collected = ""
        let status = runner.run(executable: ffprobe,
                                arguments: ["-v", "error", "-show_entries", "format=duration",
                                            "-of", "default=noprint_wrappers=1:nokey=1", path]) { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { collected = trimmed }
        }
        guard status == 0, let duration = Double(collected), duration > 0 else { return 0 }
        return duration
    }

    private func transcribeLocally(audio: String, request: Request, duration: Double) -> String? {
        guard let whisper = TranscriberHelpers.path(for: .whisperCli) else {
            fail(.helperMissing(.whisperCli))
            return nil
        }
        guard let model = TranscriberHelpers.modelPath(named: request.modelName) else {
            fail(.helperMissing(.whisperCli))
            return nil
        }

        onEvent(.phase(.transcribing(fraction: 0)))
        let base = (audio as NSString).deletingPathExtension
        let status = runner.run(
            executable: whisper,
            arguments: ["-m", model, "-f", audio, "-l", "auto", "-bs", "1",
                        "-otxt", "-of", base, "-pp", "-fa"]
        ) { [weak self] line in
            guard let self else { return }
            self.record(line)
            if let seconds = YouTubeTranscriberSupport.transcribedSeconds(in: line) {
                let fraction = YouTubeTranscriberSupport.fraction(transcribed: seconds, of: duration)
                self.onEvent(.phase(.transcribing(fraction: fraction)))
            }
        }
        if runner.isCancelled { fail(.cancelled); return nil }
        guard status == 0 else {
            fail(YouTubeTranscriberSupport.diagnose(log: snapshotLog(),
                                                    helper: .whisperCli,
                                                    exitCode: status))
            return nil
        }
        guard let raw = try? String(contentsOfFile: base + ".txt", encoding: .utf8) else {
            fail(.unknown)
            return nil
        }
        return YouTubeTranscriberSupport.normalizedTranscript(raw)
    }

    private func transcribeRemotely(audio: String, request: Request) -> String? {
        guard let url = YouTubeTranscriberSupport.remoteURL(from: request.remoteHost,
                                                            path: "v1/audio/transcriptions")
        else {
            fail(.remoteUnreachable)
            return nil
        }
        onEvent(.phase(.uploading(fraction: 0)))
        let result = RemoteTranscriber.transcribe(audioPath: audio, endpoint: url) { [weak self] fraction in
            self?.onEvent(.phase(.uploading(fraction: fraction)))
        }
        if runner.isCancelled { fail(.cancelled); return nil }
        switch result {
        case .success(let text):
            return YouTubeTranscriberSupport.normalizedTranscript(text)
        case .failure(let failure):
            fail(failure)
            return nil
        }
    }

    // MARK: - Helpers

    private func transcriptPath(forAudio audio: String, in directory: URL) -> String {
        let base = URL(fileURLWithPath: audio).deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent(base).appendingPathExtension("txt").path
    }

    private func audioFiles(in directory: URL) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(
            atPath: directory.path)) ?? []
        return Set(contents.filter { ($0 as NSString).pathExtension.lowercased() == "mp3" })
    }

    /// More than one can appear when yt-dlp retries under a slightly different
    /// name; the last one written is the finished one.
    private func newest(of names: Set<String>, in directory: URL) -> String? {
        names
            .map { directory.appendingPathComponent($0).path }
            .map { (path: $0, date: modificationDate(of: $0)) }
            .max { $0.date < $1.date }
            .map { $0.path }
    }

    private func modificationDate(of path: String) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    private func expanded(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("file://") {
            value = URL(string: value)?.path ?? value
        }
        return (value as NSString).expandingTildeInPath
    }

    private func record(_ line: String) {
        logLock.withLock { log = YouTubeTranscriberSupport.appending(line, to: log) }
        onEvent(.log(line))
    }

    private func snapshotLog() -> [String] {
        logLock.withLock { log }
    }

    private func fail(_ failure: TranscriptionFailure) {
        onEvent(.phase(.failed))
        onEvent(.failed(failure))
    }
}
