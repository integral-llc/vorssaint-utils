// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where the decoding runs.
enum TranscriptionLocation: String, CaseIterable {
    /// whisper.cpp on this Mac's GPU.
    case local
    /// A whisper.cpp server the user runs, so this machine stays cool.
    case remote

    static func sanitized(_ raw: String?) -> TranscriptionLocation {
        TranscriptionLocation(rawValue: raw ?? "") ?? .local
    }
}

/// The helper executables the pipeline shells out to.
enum TranscriberHelper: String, CaseIterable {
    case ytDlp = "yt-dlp"
    case ffmpeg
    case ffprobe
    case whisperCli = "whisper-cli"

    /// yt-dlp is the only one that rots on its own: YouTube rotates its player
    /// and a build that worked last month stops extracting. The rest have no
    /// equivalent adversary and stay at whatever the build installed.
    var updatesItself: Bool { self == .ytDlp }
}

/// What the pipeline is doing, for the progress surface.
enum TranscriptionPhase: Equatable {
    case idle
    case readingTitle
    case downloadingAudio(fraction: Double)
    case measuringAudio
    case uploading(fraction: Double)
    case transcribing(fraction: Double)
    case finished
    case failed
}

/// Why a run stopped, as a case rather than a sentence.
///
/// The service cannot carry user-facing text here: every string this app shows
/// has to exist in all thirteen languages, and a literal in a service is a
/// string that never reaches the catalog. The wording lives in
/// `YouTubeTranscriberStrings`, keyed off these cases.
enum TranscriptionFailure: Error, Equatable {
    case helperMissing(TranscriberHelper)
    case helperStale
    case videoUnavailable
    case videoPrivate
    case videoMembersOnly
    case videoAgeRestricted
    case videoGeoBlocked
    case liveNotFinished
    case networkUnreachable
    case notMedia
    case diskFull
    case remoteUnreachable
    case remoteRejected(status: Int)
    case cancelled
    case helperFailed(TranscriberHelper, exitCode: Int32)
    case unknown
}

enum YouTubeTranscriberSupport {
    static let maximumLogLines = 400

    /// A local path is anything the user could have dragged in; everything
    /// else is handed to yt-dlp, which knows far more sites than a check here
    /// could keep up with.
    static func isLocalFile(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("file://") || trimmed.hasPrefix("~/")
    }

    static func isProbablyRemote(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLocalFile(trimmed) else { return false }
        return trimmed.contains("://") || trimmed.contains(".")
    }

    /// yt-dlp writes its progress as `[download]  42.3% of ...`, rewriting the
    /// same terminal line, so the percentage is scraped rather than reported.
    static func downloadFraction(in line: String) -> Double? {
        guard line.contains("[download]") else { return nil }
        guard let percentRange = line.range(of: #"\d{1,3}(\.\d+)?%"#, options: .regularExpression)
        else { return nil }
        let number = line[percentRange].dropLast()
        guard let value = Double(number) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    /// whisper.cpp prints `[00:00:12.000 --> 00:00:15.000]` per segment, which
    /// is the only progress it offers.
    static func transcribedSeconds(in line: String) -> Double? {
        guard let arrow = line.range(of: "-->") else { return nil }
        let tail = line[arrow.upperBound...]
        guard let stampRange = tail.range(of: #"\d{2}:\d{2}:\d{2}[.,]\d{1,3}"#,
                                          options: .regularExpression)
        else { return nil }
        return seconds(fromTimestamp: String(tail[stampRange]))
    }

    static func seconds(fromTimestamp stamp: String) -> Double? {
        let normalized = stamp.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func fraction(transcribed: Double, of total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(transcribed / total, 0), 1)
    }

    /// whisper.cpp's HTTP API returns each segment with a leading space and the
    /// local writer does not, so both are trimmed to read the same.
    static func normalizedTranscript(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// A remote host typed without a scheme reaches a plaintext server, which
    /// would put the audio on the wire in the clear. Default to TLS and make
    /// the user ask for anything else.
    static func remoteURL(from host: String, path: String) -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme)?.appendingPathComponent(path)
    }

    /// Keeps the tail of a process log without letting a long run grow it
    /// without bound.
    static func appending(_ line: String, to log: [String]) -> [String] {
        var next = log
        next.append(line)
        if next.count > maximumLogLines {
            next.removeFirst(next.count - maximumLogLines)
        }
        return next
    }

    /// A SHA2-256SUMS line is `<hex>  <name>`. Reading the sum for the asset
    /// actually being installed, rather than the first line, is what stops a
    /// release that lists several files from verifying against the wrong one.
    static func checksum(for asset: String, in sums: String) -> String? {
        for line in sums.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts.last.map(String.init) == asset else { continue }
            return String(parts[0]).lowercased()
        }
        return nil
    }

    /// Reads a stopped run's output and says what went wrong.
    ///
    /// The needles are English because they are substrings of yt-dlp's and
    /// whisper.cpp's own output, not of anything this app writes. They are also
    /// the fragile part: upstream rewords a message and the match goes quiet,
    /// which is why the fallback is a plain "it exited with this code" rather
    /// than a guess.
    static func diagnose(log: [String], helper: TranscriberHelper, exitCode: Int32) -> TranscriptionFailure {
        guard exitCode != 0 else { return .unknown }
        let haystack = log.joined(separator: "\n").lowercased()

        func mentions(_ needles: [String]) -> Bool {
            needles.contains { haystack.contains($0) }
        }

        if mentions(["no such file or directory", "launch path not accessible",
                     "command not found"]) {
            return .helperMissing(helper)
        }
        if mentions(["sign in to confirm", "confirm you’re not a bot",
                     "confirm you're not a bot", "unable to extract",
                     "nsig extraction failed", "player response"]) {
            return .helperStale
        }
        if mentions(["members-only", "join this channel"]) { return .videoMembersOnly }
        if mentions(["age-restricted", "confirm your age", "inappropriate for some users"]) {
            return .videoAgeRestricted
        }
        if mentions(["private video", "this video is private"]) { return .videoPrivate }
        if mentions(["not available in your country", "geo restricted", "geo-restricted"]) {
            return .videoGeoBlocked
        }
        if mentions(["this live event will begin", "live event has not started",
                     "premieres in"]) {
            return .liveNotFinished
        }
        if mentions(["video unavailable", "removed by the uploader",
                     "account associated with this video has been terminated"]) {
            return .videoUnavailable
        }
        if mentions(["unable to download webpage", "network is unreachable",
                     "temporary failure in name resolution", "connection refused",
                     "could not resolve host"]) {
            return .networkUnreachable
        }
        if mentions(["no space left on device"]) { return .diskFull }
        if mentions(["invalid data found when processing input",
                     "does not contain any stream"]) {
            return .notMedia
        }
        return .helperFailed(helper, exitCode: exitCode)
    }
}
