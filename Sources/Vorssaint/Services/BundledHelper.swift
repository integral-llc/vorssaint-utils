// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Third-party executables the build stages in Contents/Helpers and signs
/// with the app.
enum BundledHelper {
    /// The executable to run, or nil when this build does not carry it. Nil is
    /// a real answer here rather than a fallback to whatever is on PATH:
    /// running an arbitrary same-named binary from the user's shell
    /// environment is not something a signed app should do quietly.
    static func path(named name: String) -> String? {
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: name),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        let staged = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers")
            .appendingPathComponent(name)
        return FileManager.default.isExecutableFile(atPath: staged.path) ? staged.path : nil
    }
}
