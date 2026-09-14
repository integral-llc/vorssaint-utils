// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where the pipeline's helper executables and model live.
///
/// The build stages them inside the bundle and signs them with the app, so a
/// stock install has everything and nothing has to be fetched on first run.
/// yt-dlp is the exception: it is the one helper that has to be replaceable at
/// runtime, and a write inside a signed bundle would break the signature, so an
/// updated copy goes to Application Support and is preferred from there.
enum TranscriberHelpers {
    static var updatableDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Vorssaint/Helpers", isDirectory: true)
    }

    static var modelDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Vorssaint/Models", isDirectory: true)
    }

    /// The executable to run, or nil when the helper is not installed. Nil is a
    /// real answer here rather than a fallback to whatever is on PATH: running
    /// an arbitrary same-named binary from the user's shell environment is not
    /// something a signed app should do quietly.
    static func path(for helper: TranscriberHelper) -> String? {
        if helper.updatesItself {
            let updated = updatableDirectory.appendingPathComponent(helper.rawValue)
            if FileManager.default.isExecutableFile(atPath: updated.path) {
                return updated.path
            }
        }
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: helper.rawValue),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        let staged = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers")
            .appendingPathComponent(helper.rawValue)
        if FileManager.default.isExecutableFile(atPath: staged.path) {
            return staged.path
        }
        return nil
    }

    static func isInstalled(_ helper: TranscriberHelper) -> Bool {
        path(for: helper) != nil
    }

    static var missingHelpers: [TranscriberHelper] {
        TranscriberHelper.allCases.filter { !isInstalled($0) }
    }

    /// The whisper model file, or nil when it was never installed. It is far
    /// too large to ship inside the app, so it is fetched once and kept beside
    /// the updatable helpers.
    static func modelPath(named name: String) -> String? {
        let url = modelDirectory.appendingPathComponent(name)
        return FileManager.default.isReadableFile(atPath: url.path) ? url.path : nil
    }
}
