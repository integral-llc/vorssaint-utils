// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Starts lazily and asynchronously. A serial dispatch queue alone is not a
/// stable thread/run loop for IOBluetooth's notification registrations.
final class BluetoothRunLoop {
    static let shared = BluetoothRunLoop()
    private let name: String
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var pending: [() -> Void] = []
    private var started = false
    private var draining = false

    init(name: String = "Vorssaint Bluetooth Accessories") {
        self.name = name
    }

    func perform(_ work: @escaping () -> Void) {
        let action = lock.withLock { () -> (launch: Bool, runLoop: CFRunLoop?) in
            pending.append(work)
            if let runLoop, !draining {
                draining = true
                return (false, runLoop)
            }
            guard !started else { return (false, nil) }
            started = true
            return (true, nil)
        }
        if let runLoop = action.runLoop { scheduleDrain(on: runLoop) }
        if action.launch {
            let thread = Thread { self.run() }
            thread.name = name
            thread.qualityOfService = .utility
            thread.start()
        }
    }

    // Keep the drain reserved until the active native call returns: a nested
    // framework run loop must not start another source or unregister the
    // source whose start is still on the stack.
    private func scheduleDrain(on runLoop: CFRunLoop) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { self.drain() }
        CFRunLoopWakeUp(runLoop)
    }

    private func drain() {
        while let work = lock.withLock({ () -> (() -> Void)? in
            guard !pending.isEmpty else { draining = false; return nil }
            return pending.removeFirst()
        }) {
            autoreleasepool(invoking: work)
        }
    }

    private func run() {
        let runLoop = CFRunLoopGetCurrent()!
        // No polling: the port only keeps the run loop alive between events.
        RunLoop.current.add(NSMachPort(), forMode: .common)
        lock.withLock {
            self.runLoop = runLoop
            draining = true
        }
        scheduleDrain(on: runLoop)
        while true {
            autoreleasepool {
                _ = CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, true)
            }
        }
    }
}
