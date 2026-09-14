// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs one long helper and reports its output line by line while it runs.
///
/// `BoundedProcessRunner` already covers the app's other process work and is
/// the right shape for it: run, wait, read everything, give up after a few
/// seconds. Nothing here fits that. A download or a decode runs for minutes,
/// has to show progress while it does, and has to be stoppable, so this is a
/// second runner rather than a widening of that one.
final class StreamingProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// Progress arrives on a background queue; the caller decides where it goes.
    func run(executable: String,
             arguments: [String],
             onLine: @escaping (String) -> Void) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // The helpers are addressed by absolute path and must not pick anything
        // up out of the user's shell environment.
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let reader = pipe.fileHandleForReading
        let drained = DispatchSemaphore(value: 0)
        let partial = LineAccumulator()
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                partial.flush(into: onLine)
                drained.signal()
                return
            }
            partial.append(chunk, emit: onLine)
        }

        let shouldStart = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            self.process = process
            return true
        }
        guard shouldStart else {
            reader.readabilityHandler = nil
            return -1
        }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            lock.withLock { self.process = nil }
            return -1
        }

        process.waitUntilExit()
        _ = drained.wait(timeout: .now() + 2)
        reader.readabilityHandler = nil
        partial.flush(into: onLine)
        lock.withLock { self.process = nil }
        return process.terminationStatus
    }

    func cancel() {
        let running = lock.withLock { () -> Process? in
            cancelled = true
            return process
        }
        running?.terminate()
    }

    func reset() {
        lock.withLock { cancelled = false }
    }

    var isCancelled: Bool { lock.withLock { cancelled } }
}

/// Turns a byte stream into lines.
///
/// Both helpers rewrite one terminal line with a carriage return to animate
/// progress, so a `\r` run collapses to its last segment the way a terminal
/// shows it. A chunk can also split a line in half, so the remainder is held
/// until the rest arrives.
private final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var remainder = ""

    func append(_ chunk: Data, emit: (String) -> Void) {
        let text = String(decoding: chunk, as: UTF8.self)
        var lines: [String] = []
        lock.withLock {
            remainder += text
            let pieces = remainder.components(separatedBy: "\n")
            remainder = pieces.last ?? ""
            for piece in pieces.dropLast() {
                if let latest = piece.components(separatedBy: "\r").last, !latest.isEmpty {
                    lines.append(latest)
                }
            }
        }
        for line in lines { emit(line) }
    }

    func flush(into emit: (String) -> Void) {
        let tail = lock.withLock { () -> String in
            let value = remainder
            remainder = ""
            return value
        }
        guard let latest = tail.components(separatedBy: "\r").last, !latest.isEmpty else { return }
        emit(latest)
    }
}
