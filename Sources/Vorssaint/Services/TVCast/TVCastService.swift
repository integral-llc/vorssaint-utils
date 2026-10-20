// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import os

/// What the service is busy with. One ytcast run at a time: ytcast rewrites
/// its whole cache file when a run ends, so two runs, or a run and an edit,
/// would each throw away what the other wrote.
enum TVCastActivity: Equatable {
    case idle
    case pairing
    /// Carries the name of the TV the video is going to.
    case sending(String)
}

/// Which kind of request an outcome answers, so Settings shows a failure
/// beside the control that caused it rather than under every section.
enum TVCastRequest: Equatable {
    case pair, send, edit
}

/// How the latest request ended.
enum TVCastOutcome: Equatable {
    /// The id lets Settings pick the TV it just paired.
    case paired(id: String, name: String)
    case sent(String)
    case failed(TVCastFailure, during: TVCastRequest)
}

/// Pairs TVs and sends videos to them through the bundled ytcast, and keeps
/// the list of TVs that ytcast's cache file holds.
final class TVCastService: ObservableObject {
    static let shared = TVCastService()

    /// Only TVs paired with a code. ytcast reaches a discovered one over the
    /// local network, with DIAL, Wake-on-LAN and SSDP, which Vorssaint never
    /// asks it to do.
    @Published private(set) var devices: [TVCastDevice] = []
    @Published private(set) var activity: TVCastActivity = .idle
    @Published private(set) var outcome: TVCastOutcome?

    /// The only runs Vorssaint makes. ytcast's other modes (`-l`, `-s`, a
    /// cast with no saved TV) search the local network, which a TV paired
    /// with a code never needs, so they cannot be expressed here.
    private enum Command {
        case pair(code: String)
        case cast(deviceID: String, video: String)

        var arguments: [String] {
            switch self {
            case .pair(let code):
                return TVCastSupport.pairArguments(code: code)
            case .cast(let deviceID, let video):
                return TVCastSupport.castArguments(deviceID: deviceID, video: video)
            }
        }

        var isPairing: Bool {
            if case .pair = self { return true }
            return false
        }
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "tvcast")
    private static let helperName = "ytcast"
    /// ytcast gives each request 30 s, and a send can chain four: the token
    /// refresh, Connect's own refresh when that fails, the session ids and
    /// Play. Past that the run is stuck rather than slow.
    private static let runTimeout: TimeInterval = 130
    private static let maxOutputBytes = 64 * 1024
    /// ytcast's `XDG_CACHE_HOME`. Inside the app's own container rather than
    /// ~/.cache, so the pairing tokens stay with the app and no other ytcast
    /// on this Mac reads or rewrites the list. The container follows the
    /// bundle id, so the official and the Developer build keep separate
    /// lists: two apps running ytcast on one file drop each other's TVs.
    private static let stateDirectory = PrivateFileStore.containerURL?
        .appendingPathComponent("TVCast", isDirectory: true)
    private static let cacheURL = stateDirectory?.appendingPathComponent(TVCastSupport.cacheSubpath)

    private let queue = DispatchQueue(label: "com.vorssaint.utils.tvcast", qos: .userInitiated)
    private let lock = NSLock()
    private var running: BoundedProcessCancellation?

    private init() {}

    /// False for a build without ytcast, so Settings can say so up front
    /// instead of after a click.
    var isHelperInstalled: Bool { BundledHelper.path(named: Self.helperName) != nil }

    /// Called by the feature runtime when availability changes. A feature
    /// switched off in the hub must not leave ytcast running.
    func syncWithPreferences() {
        if AppFeature.tvCast.isAvailable {
            reload()
        } else {
            lock.withLock { running }?.cancel()
        }
    }

    func reload() {
        queue.async { [weak self] in
            let devices = Self.loadDevices()
            DispatchQueue.main.async { self?.devices = devices }
        }
    }

    func pair(code: String, name: String) {
        guard activity == .idle, AppFeature.tvCast.isAvailable else { return }
        guard let digits = TVCastSupport.pairingCode(from: code) else {
            outcome = .failed(.invalidCode, during: .pair)
            return
        }
        activity = .pairing
        outcome = nil
        let cancellation = beginRun()
        queue.async { [weak self] in
            let result = Self.performPairing(code: digits, name: name, cancellation: cancellation)
            self?.finishRun(cancellation, with: result)
        }
    }

    /// Does nothing for input that is not one YouTube video; Settings keeps
    /// Send disabled until it is.
    func send(_ input: String, to id: String) {
        guard activity == .idle, AppFeature.tvCast.isAvailable,
              let video = TVCastSupport.videoArgument(from: input) else { return }
        let name = devices.first { $0.id == id }?.name ?? id
        activity = .sending(name)
        outcome = nil
        let cancellation = beginRun()
        queue.async { [weak self] in
            let result = Self.performSend(video: video, to: id, name: name, cancellation: cancellation)
            self?.finishRun(cancellation, with: result)
        }
    }

    func rename(_ id: String, to name: String) {
        edit { TVCastSupport.renaming(id, to: name, inCache: $0) }
    }

    func remove(_ id: String) {
        edit { TVCastSupport.removing(id, fromCache: $0) }
    }

    // MARK: - Private

    private func beginRun() -> BoundedProcessCancellation {
        let cancellation = BoundedProcessCancellation()
        lock.withLock { running = cancellation }
        return cancellation
    }

    /// On the queue, once a run is over. The list is read again because a
    /// send moves LastUsed and a pairing adds or replaces a TV. A run stopped
    /// by uninstalling reports nothing: nobody is left to read it.
    private func finishRun(_ cancellation: BoundedProcessCancellation, with result: TVCastOutcome) {
        lock.withLock { if running === cancellation { running = nil } }
        let devices = Self.loadDevices()
        let outcome = cancellation.isCancelled ? nil : result
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.devices = devices
            self.activity = .idle
            self.outcome = outcome
        }
    }

    private func edit(_ change: @escaping (Data) -> Data?) {
        guard AppFeature.tvCast.isAvailable else { return }
        queue.async { [weak self] in
            // Cleared once the edit starts, behind whatever was queued ahead
            // of it, so a result reported in between cannot outlive it and
            // the outcome always answers the latest request.
            DispatchQueue.main.async { self?.outcome = nil }
            let changed = Self.readCache().flatMap(change)
            let saved = changed.map(Self.writeCache) ?? false
            if changed == nil { Self.log.error("the TV list had no entry to change") }
            let devices = Self.loadDevices()
            DispatchQueue.main.async {
                guard let self else { return }
                self.devices = devices
                if !saved { self.outcome = .failed(.cacheUnreadable, during: .edit) }
            }
        }
    }

    private static func performPairing(code: String, name: String,
                                       cancellation: BoundedProcessCancellation) -> TVCastOutcome {
        let snapshot = readCache()
        let output: String
        switch run(.pair(code: code), snapshot: snapshot, cancellation: cancellation) {
        case .failure(let failure): return .failed(failure, during: .pair)
        case .success(let printed): output = printed
        }
        // A pairing identical to the saved one changes nothing in the file;
        // the id ytcast printed still names the TV.
        guard let after = readCache(),
              let id = TVCastSupport.changedDeviceID(before: snapshot, after: after)
                ?? TVCastSupport.pairedDeviceID(printedIn: output, cache: after) else {
            log.error("ytcast paired a TV but neither the cache nor its output shows which one")
            return .failed(.cacheUnreadable, during: .pair)
        }
        guard let settled = TVCastSupport.settledPairing(of: id, typedName: name, inCache: after),
              writeCache(settled.cache) else {
            return .failed(.cacheUnreadable, during: .pair)
        }
        return .paired(id: id, name: settled.name)
    }

    private static func performSend(video: String, to id: String, name: String,
                                    cancellation: BoundedProcessCancellation) -> TVCastOutcome {
        // ytcast v1.4.1 falls back to SSDP discovery on the local network
        // (multicast, behind the Local Network prompt) when its cache is empty
        // or `-d` matches no saved TV, and reaches a discovered TV with DIAL
        // and Wake-on-LAN. A code-paired TV is reached through YouTube alone,
        // so the TV must be saved, and paired with a code, before ytcast runs.
        let snapshot = readCache()
        guard TVCastSupport.devices(fromCache: snapshot).contains(where: { $0.id == id && $0.pairedWithCode }) else {
            return .failed(.deviceNotFound, during: .send)
        }
        if case .failure(let failure) = run(.cast(deviceID: id, video: video), snapshot: snapshot,
                                            cancellation: cancellation) {
            return .failed(failure, during: .send)
        }
        return .sent(name)
    }

    /// ytcast's output when it succeeded. `snapshot` is the cache as it was
    /// before the run, to put back what ytcast loses.
    private static func run(_ command: Command, snapshot: Data?,
                            cancellation: BoundedProcessCancellation) -> Result<String, TVCastFailure> {
        guard let helper = BundledHelper.path(named: helperName) else { return .failure(.helperMissing) }
        guard let directory = stateDirectory, let cacheURL,
              PrivateFileStore.createDirectory(at: cacheURL.deletingLastPathComponent()) else {
            return .failure(.cacheUnreadable)
        }
        // Nothing names the account: without it ytcast introduces itself to
        // YouTube and on the TV as plain "ytcast", not account@computer.
        let environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "XDG_CACHE_HOME": directory.path,
        ]
        let result = BoundedProcessRunner.run(helper, command.arguments,
                                              timeout: runTimeout,
                                              maxOutputBytes: maxOutputBytes,
                                              environment: environment,
                                              cancellation: cancellation)
        let output = String(decoding: result.output, as: UTF8.self)
        repairCache(snapshot: snapshot, pairingOutput: command.isPairing ? output : nil)
        guard let failure = TVCastSupport.failure(fromOutput: output, status: result.status,
                                                  timedOut: result.timedOut) else { return .success(output) }
        if !cancellation.isCancelled {
            // ytcast's own words can quote a request URL, so they stay private.
            log.error("ytcast failed: \(String(describing: failure), privacy: .private)")
        }
        return .failure(failure)
    }

    /// Runs after every ytcast run, cancelled or not: a damaged list is
    /// lost for good once the next run reads it.
    private static func repairCache(snapshot: Data?, pairingOutput: String?) {
        guard let repaired = TVCastSupport.repairedCache(snapshot: snapshot, after: readCache(),
                                                         pairingOutput: pairingOutput) else { return }
        log.error("ytcast left the TV list damaged or short; restoring the TVs it lost")
        _ = writeCache(repaired)
    }

    private static func loadDevices() -> [TVCastDevice] {
        TVCastSupport.devices(fromCache: readCache()).filter(\.pairedWithCode)
    }

    /// Nil when there is no list yet, which is not an error.
    private static func readCache() -> Data? {
        guard let cacheURL else { return nil }
        do {
            return try Data(contentsOf: cacheURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            log.error("could not read the TV list: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Through PrivateFileStore: atomic, so a crash never leaves half a list
    /// behind, and owner-only, because the file holds every pairing token.
    private static func writeCache(_ data: Data) -> Bool {
        guard let cacheURL, PrivateFileStore.write(data, to: cacheURL) else {
            log.error("could not save the TV list")
            return false
        }
        return true
    }
}
