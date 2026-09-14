// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// Installs a newer yt-dlp beside the bundled one.
///
/// This is the only path in the app that puts a new executable on disk and then
/// runs it. What that buys is the one helper whose usefulness expires: YouTube
/// rotates its player and the build shipped with the app stops extracting.
/// What it costs is stated plainly rather than hidden:
///
/// - The download is checked against the SHA2-256SUMS from the same release, so
///   it catches a corrupted transfer. It is not a trust anchor, because anyone
///   able to serve the release can serve a matching sum. The real anchor is TLS
///   plus the upstream account.
/// - The installed file is not covered by this app's Developer ID signature and
///   is not notarized. macOS quarantines a download and refuses to exec it, so
///   installing one means clearing that attribute.
///
/// Because of that it only ever runs when the user asks for it, from Settings.
/// Nothing here fires on its own or retries a failed run behind an update.
enum HelperUpdater {
    enum Outcome: Equatable {
        case upToDate(version: String)
        case installed(version: String)
        case offline
        case releaseUnreadable
        case checksumMissing
        case checksumMismatch
        case installFailed
    }

    private static let releaseFeed =
        URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
    private static let assetName = "yt-dlp_macos"
    private static let checksumAssetName = "SHA2-256SUMS"

    static func installedVersion() -> String? {
        guard let path = TranscriberHelpers.path(for: .ytDlp) else { return nil }
        let result = Shell.run(path, ["--version"], timeout: 20)
        guard result.status == 0 else { return nil }
        let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    /// Fetches, verifies and installs. Blocking, so callers run it off the main
    /// thread; the settings pane does that on a utility queue.
    static func update(currentVersion: String?) -> Outcome {
        guard let release = fetchRelease() else { return .offline }
        if let currentVersion, currentVersion == release.tag {
            return .upToDate(version: release.tag)
        }
        guard let assetURL = release.assets[assetName] else { return .releaseUnreadable }
        guard let checksumURL = release.assets[checksumAssetName] else { return .checksumMissing }
        guard let sums = fetchText(checksumURL),
              let expected = YouTubeTranscriberSupport.checksum(for: assetName, in: sums)
        else { return .checksumMissing }
        guard let staged = download(assetURL) else { return .offline }
        defer { try? FileManager.default.removeItem(at: staged) }

        guard let actual = sha256(ofFileAt: staged), actual == expected else {
            return .checksumMismatch
        }
        return install(staged) ? .installed(version: release.tag) : .installFailed
    }

    // MARK: - Release feed

    private struct Release {
        let tag: String
        let assets: [String: URL]
    }

    private static func fetchRelease() -> Release? {
        guard let data = fetch(releaseFeed),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let assets = object["assets"] as? [[String: Any]]
        else { return nil }
        var urls: [String: URL] = [:]
        for asset in assets {
            guard let name = asset["name"] as? String,
                  let raw = asset["browser_download_url"] as? String,
                  let url = URL(string: raw)
            else { continue }
            urls[name] = url
        }
        return Release(tag: tag, assets: urls)
    }

    // MARK: - Transfer

    private static func fetch(_ url: URL) -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return synchronousData(for: request)
    }

    private static func fetchText(_ url: URL) -> String? {
        fetch(url).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func download(_ url: URL) -> URL? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 600
        guard let data = synchronousData(for: request) else { return nil }
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("yt-dlp-\(UUID().uuidString)")
        guard (try? data.write(to: staged, options: .atomic)) != nil else { return nil }
        return staged
    }

    private static func synchronousData(for request: URLRequest) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var payload: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                lock.withLock { payload = data }
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + request.timeoutInterval + 5) == .success else {
            task.cancel()
            return nil
        }
        return lock.withLock { payload }
    }

    static func sha256(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Install

    private static func install(_ staged: URL) -> Bool {
        let directory = TranscriberHelpers.updatableDirectory
        let destination = directory.appendingPathComponent(TranscriberHelper.ytDlp.rawValue)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let incoming = directory.appendingPathComponent(".yt-dlp.incoming")
            try? FileManager.default.removeItem(at: incoming)
            try FileManager.default.copyItem(at: staged, to: incoming)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: incoming.path)
            clearQuarantine(incoming)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: incoming)
            } else {
                try FileManager.default.moveItem(at: incoming, to: destination)
            }
            return true
        } catch {
            return false
        }
    }

    /// Gatekeeper refuses to exec a quarantined binary that nobody it trusts
    /// signed, so an installed helper cannot keep the attribute and still run.
    private static func clearQuarantine(_ url: URL) {
        _ = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return removexattr(path, "com.apple.quarantine", 0)
        }
    }
}
