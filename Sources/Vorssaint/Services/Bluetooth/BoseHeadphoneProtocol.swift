// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// BMAP over Bluetooth Classic, using the wire formats documented by bozo and bosectl.
// https://github.com/NerdySouth/bozo/blob/main/docs/BMAP.md
// https://github.com/aaronsb/bosectl/blob/integration/NOTES.md
enum BoseHeadphoneError: Error, Equatable {
    case disconnected, timedOut, rejected, invalidResponse, noCustomMode
}

struct BoseMessage: Equatable {
    enum Operation: UInt8 {
        case read = 1, writeAndRead = 2, status = 3, error = 4, start = 5, result = 6
    }

    let block: UInt8
    let function: UInt8
    let flags: UInt8
    let payload: [UInt8]

    init(block: UInt8 = 31, function: UInt8, operation: Operation = .read, payload: [UInt8] = []) {
        self.block = block
        self.function = function
        self.flags = operation.rawValue
        self.payload = payload
    }

    fileprivate init(header: ArraySlice<UInt8>, payload: ArraySlice<UInt8>) {
        block = header[header.startIndex]
        function = header[header.startIndex + 1]
        flags = header[header.startIndex + 2]
        self.payload = Array(payload)
    }

    var bytes: [UInt8] { [block, function, flags, UInt8(payload.count)] + payload }

    func reply(to request: Self) -> Result<[UInt8], BoseHeadphoneError>? {
        guard block == request.block, function == request.function, flags >> 4 == 0 else { return nil }
        switch Operation(rawValue: flags) {
        case .error: return .failure(.rejected)
        case .status, .result:
            // Mode configurations include the slot number. Other slots can arrive unsolicited.
            if block == 31, function == 6, payload.first != request.payload.first { return nil }
            return .success(payload)
        default: return nil
        }
    }
}

struct BoseMessageStream {
    private var remainder: [UInt8] = []

    mutating func receive(_ bytes: [UInt8]) -> [BoseMessage] {
        remainder.append(contentsOf: bytes)
        var messages: [BoseMessage] = []
        var offset = 0
        while remainder.count - offset >= 4 {
            let payloadStart = offset + 4
            let end = payloadStart + Int(remainder[offset + 3])
            guard end <= remainder.count else { break }
            messages.append(BoseMessage(header: remainder[offset..<payloadStart],
                                        payload: remainder[payloadStart..<end]))
            offset = end
        }
        remainder.removeFirst(offset)
        return messages
    }
}

struct BoseHeadphoneMode: Identifiable, Equatable {
    static let appModeName = "Vorssaint ANC"
    private static let presetNames: [UInt8: String] = [
        1: "Quiet", 2: "Aware", 7: "Commute", 8: "Outdoor", 9: "Workout", 10: "Home",
        11: "Work", 12: "Music", 13: "Focus", 14: "Relax", 15: "Flight", 34: "Immersion", 36: "Cinema"
    ]

    private let configuration: [UInt8]

    init?(_ configuration: [UInt8]) {
        guard configuration.count == 47 || configuration.count == 48 else { return nil }
        self.configuration = configuration
    }

    var id: UInt8 { configuration[0] }
    /// The factory mode this one is based on; renaming a mode keeps it.
    var preset: UInt8 { configuration[2] }
    private var editable: Bool { configuration[3] != 0 }
    private var configured: Bool { configuration[4] != 0 }
    var isSelectable: Bool { !editable || configured }
    var name: String {
        let name = String(decoding: configuration[6..<38].prefix { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? Self.presetNames[configuration[2], default: "#\(Int(id) + 1)"] : name
    }
    var noiseCancellation: Int? { Self.level(forStep: configuration[42]) }
    var canUseForCustomLevel: Bool {
        editable && configuration[41] & 1 != 0 && (!configured || name == Self.appModeName)
    }

    static func level(forStep step: UInt8) -> Int? { step <= 10 ? 10 - Int(step) : nil }

    func customConfiguration(level: Int) -> [UInt8]? {
        guard canUseForCustomLevel, (0...10).contains(level) else { return nil }
        let nameBytes = Array(Self.appModeName.utf8)
        var update = Array(configuration.prefix(3))
        update += nameBytes + Array(repeating: 0, count: 32 - nameBytes.count)
        // A manual level needs both automatic variation and wind reduction off.
        update += [UInt8(10 - level), 0, configuration[44], 0]
        if configuration.count == 48 { update.append(1) }
        return update
    }
}

struct BoseHeadphoneStatus: Equatable {
    var allModes: [BoseHeadphoneMode]
    let activeMode: UInt8
    let battery: Int?
    let liveSettings: [UInt8]?

    var modes: [BoseHeadphoneMode] { allModes.filter(\.isSelectable) }
    var noiseCancellation: Int? {
        if let step = liveSettings?.first { return BoseHeadphoneMode.level(forStep: step) }
        return modes.first { $0.id == activeMode }?.noiseCancellation
    }

    var customSlot: BoseHeadphoneMode? {
        let writable = allModes.filter(\.canUseForCustomLevel)
        return writable.first { $0.name == BoseHeadphoneMode.appModeName } ?? writable.first
    }

    var canSetLevel: Bool { liveSettings != nil || customSlot != nil }
}

struct BoseHeadphoneCommands {
    let send: (BoseMessage) async throws -> [UInt8]

    func read() async throws -> BoseHeadphoneStatus {
        let capabilities = try await request(2)
        guard capabilities.count >= 6 else { throw BoseHeadphoneError.invalidResponse }
        let count = Int(capabilities[0]) + Int(capabilities[1])
        guard (1...32).contains(count) else { throw BoseHeadphoneError.invalidResponse }
        var modes: [BoseHeadphoneMode] = []
        for index in 0..<count {
            do { modes.append(try await readMode(UInt8(index))) }
            catch BoseHeadphoneError.rejected { continue }
        }
        guard modes.contains(where: \.isSelectable) else { throw BoseHeadphoneError.invalidResponse }
        return try await readStatus(modes: modes, checkLiveSettings: true)
    }

    func select(_ id: UInt8, from status: BoseHeadphoneStatus) async throws -> BoseHeadphoneStatus {
        guard status.modes.contains(where: { $0.id == id }) else { throw BoseHeadphoneError.invalidResponse }
        try await activate(id)
        let updated = try await readStatus(modes: status.allModes, checkLiveSettings: status.liveSettings != nil)
        guard updated.activeMode == id else { throw BoseHeadphoneError.invalidResponse }
        return updated
    }

    func setLevel(_ level: Int, from status: BoseHeadphoneStatus) async throws -> BoseHeadphoneStatus {
        guard (0...10).contains(level) else { throw BoseHeadphoneError.invalidResponse }
        if status.liveSettings != nil {
            return try await setLiveLevel(level, modes: status.allModes)
        }
        return try await setCustomLevel(level, status: status)
    }

    private func setLiveLevel(_ level: Int, modes: [BoseHeadphoneMode]) async throws -> BoseHeadphoneStatus {
        guard var settings = try await readLiveSettings() else { throw BoseHeadphoneError.invalidResponse }
        settings[0] = UInt8(10 - level)
        settings[1] = 0
        settings[3] = 0
        settings[4] = 1
        _ = try await request(10, .writeAndRead, settings)
        let updated = try await readStatus(modes: modes, checkLiveSettings: true)
        guard updated.liveSettings == settings else { throw BoseHeadphoneError.invalidResponse }
        return updated
    }

    private func setCustomLevel(_ level: Int, status: BoseHeadphoneStatus) async throws -> BoseHeadphoneStatus {
        guard let slot = status.customSlot else { throw BoseHeadphoneError.noCustomMode }
        let latest = try await readMode(slot.id)
        guard let configuration = latest.customConfiguration(level: level) else { throw BoseHeadphoneError.noCustomMode }
        _ = try await request(6, .writeAndRead, configuration)
        let saved = try await readMode(slot.id)
        guard saved.isSelectable, saved.name == BoseHeadphoneMode.appModeName, saved.noiseCancellation == level else {
            throw BoseHeadphoneError.invalidResponse
        }
        try await activate(slot.id)
        let modes = status.allModes.map { $0.id == slot.id ? saved : $0 }
        let updated = try await readStatus(modes: modes, checkLiveSettings: false)
        guard updated.activeMode == slot.id else { throw BoseHeadphoneError.invalidResponse }
        return updated
    }

    private func readStatus(modes: [BoseHeadphoneMode], checkLiveSettings: Bool) async throws -> BoseHeadphoneStatus {
        guard let active = try await request(3).first else { throw BoseHeadphoneError.invalidResponse }
        let liveSettings = checkLiveSettings ? try await readLiveSettings() : nil
        var battery: Int?
        do {
            if let level = try await send(BoseMessage(block: 2, function: 2)).first, level <= 100 {
                battery = Int(level)
            }
        } catch BoseHeadphoneError.rejected {
            // Battery reporting is optional and independent from listening modes.
        }
        return BoseHeadphoneStatus(allModes: modes, activeMode: active, battery: battery, liveSettings: liveSettings)
    }

    private func readMode(_ id: UInt8) async throws -> BoseHeadphoneMode {
        let payload = try await request(6, .read, [id])
        guard let mode = BoseHeadphoneMode(payload), mode.id == id else { throw BoseHeadphoneError.invalidResponse }
        return mode
    }

    private func readLiveSettings() async throws -> [UInt8]? {
        do {
            let settings = try await request(10)
            guard settings.count == 5, settings[0] <= 10 else { return nil }
            return settings
        } catch BoseHeadphoneError.rejected {
            return nil
        }
    }

    private func activate(_ id: UInt8) async throws {
        _ = try await request(3, .start, [id, 0])
    }

    private func request(_ function: UInt8, _ operation: BoseMessage.Operation = .read,
                         _ payload: [UInt8] = []) async throws -> [UInt8] {
        try await send(BoseMessage(function: function, operation: operation, payload: payload))
    }
}
