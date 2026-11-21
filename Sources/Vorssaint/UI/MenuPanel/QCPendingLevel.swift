// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// A noise level the person moved to that has not been sent yet. It belongs
/// to the headset and listening mode it was made in: sent after either
/// changed, it would rewrite the mode the person just picked.
struct QCPendingLevel: Equatable {
    struct Origin: Equatable {
        let deviceID: String
        let activeMode: UInt8

        init?(deviceID: String?, status: BoseHeadphoneStatus?) {
            guard let deviceID, let status else { return nil }
            self.deviceID = deviceID
            activeMode = status.activeMode
        }
    }

    let level: Int
    let origin: Origin

    /// The level to send now, or nil when it no longer applies or would
    /// change nothing.
    func commitTarget(deviceID: String?, status: BoseHeadphoneStatus?) -> Int? {
        guard let status, Origin(deviceID: deviceID, status: status) == origin, status.canSetLevel else {
            return nil
        }
        // A level the headset's own buttons set is reapplied as a fixed level.
        guard level != status.noiseCancellation || status.liveSettings?.last == 0 else { return nil }
        return level
    }
}
