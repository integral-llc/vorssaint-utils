// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BoseHeadphoneTests {
    static func run(_ suite: TestSuite) {
        let first: [UInt8] = [2, 2, 3, 1, 84]
        let second: [UInt8] = [31, 3, 6, 1, 2]
        var stream = BoseMessageStream()
        suite.expect(stream.receive(Array(first.prefix(3))).isEmpty, "a partial RFCOMM header does not produce a packet")
        let messages = stream.receive(Array(first.dropFirst(3)) + Array(second.prefix(4)))
        suite.expect(messages.map(\.bytes) == [first], "one read may end a packet and start the next")
        suite.expect(stream.receive([2] + first).map(\.bytes) == [second, first],
                     "coalesced RFCOMM packets are decoded in order")

        let query = BoseMessage(function: 6, payload: [2])
        let unrelatedSlot = stream.receive([31, 6, 3, 1, 1]).first
        let matchingSlot = stream.receive([31, 6, 3, 1, 2]).first
        let rejection = stream.receive([31, 6, 4, 1, 4]).first
        suite.expect(unrelatedSlot?.reply(to: query) == nil && matchingSlot?.reply(to: query) == .success([2]),
                     "only the requested mode can satisfy a mode query")
        suite.expect(rejection?.reply(to: query) == .failure(.rejected), "device errors finish the matching query")
        let renamed = BoseHeadphoneDevice(id: "headset", name: "Desk Audio", vendorID: 0x009E, productID: 0x4066)
        let unnamed = BoseHeadphoneDevice(id: "headset-2", name: nil, vendorID: 0x05A7, productID: 0x4082)
        suite.expect(renamed?.name == "Desk Audio" && unnamed?.name == "Bose QuietComfort Ultra Headphones",
                     "hardware identity finds renamed and unnamed QuietComfort Ultra headphones")
        suite.expect(BoseHeadphoneDevice(id: "other", name: "Bose QuietComfort Ultra Headphones",
                                        vendorID: 0x004C, productID: 0x4066) == nil
                     && BoseHeadphoneDevice(id: "buds", name: "Bose QuietComfort Ultra Headphones",
                                            vendorID: 0x009E, productID: 0x4062) == nil,
                     "a matching label never makes another vendor or an unsupported model eligible")
        suite.expect(AppFeature.qcControl.group == .sound && !AppFeature.qcControl.installedByDefault
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.panelShowQCControl),
                     "the opt-in sound module retains its panel visibility in settings backups")
        checkIslandSection(suite)
        checkQueryLease(suite)
        checkPendingLevel(suite)
        suite.expect(BluetoothAudioRoutes.address(fromUID: "BC-87-FA-97-BD-3C:output") == "bc-87-fa-97-bd-3c"
                     && BluetoothAudioRoutes.address(fromUID: "BC-87-FA-97-BD-3C:input") == "bc-87-fa-97-bd-3c",
                     "a Bluetooth audio route maps to the IOBluetooth address of its headset")
        suite.expect(["BuiltInSpeakerDevice", "1E6D5077-0000-0000-0720-0104B5462878", "BC-87-FA-97-BD:output",
                      "BC-87-FA-97-BD-3G:output", ""].allSatisfy { BluetoothAudioRoutes.address(fromUID: $0) == nil },
                     "routes that do not name a Bluetooth address never count as a connected headset")

        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            await checkCustomMode(suite)
            await checkLiveSettings(suite)
            await checkBatteryUpdates(suite)
            finished.signal()
        }
        suite.expect(finished.wait(timeout: .now() + 5) == .success, "the command fixtures complete")
    }

    private static func checkIslandSection(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.qc-control-island.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            suite.expect(false, "QC Control settings can be isolated")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        let action = NotchQuickAction.module(.qcControl)
        let availability = AppFeature.qcControl.availabilityKey
        defaults.set(false, forKey: availability)
        suite.expect(NotchModule.qcControl.title(.enUS) == QCControlStrings.title
                     && NotchQuickAction.optionalActions.contains(action)
                     && !action.isAvailable(in: defaults),
                     "QC Control is listed in the Content editor and waits for feature installation")
        defaults.set(true, forKey: availability)
        suite.expect(NotchSupport.modules(in: defaults).contains(.qcControl) && action.isAvailable(in: defaults),
                     "installing QC Control adds the section to the island and its Layout button picker")
        defaults.set("qcControl", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!action.isAvailable(in: defaults) && NotchModule.qcControl.isAvailable(in: defaults),
                     "hiding the island section keeps the underlying feature installed")
    }

    private static func checkQueryLease(_ suite: TestSuite) {
        final class Owner {}
        var lease = BluetoothQueryLease()
        weak var released: Owner?
        do {
            let owner = Owner()
            released = owner
            lease.begin("a", owner: owner)
            lease.begin("a", owner: owner)
            lease.begin("b", owner: owner)
        }
        lease.complete("a")
        lease.complete("unknown")
        lease.complete("b")
        suite.expect(released != nil && lease.isHolding,
                     "the owner outlives its last reference while an SDP query is outstanding")
        lease.complete("a")
        suite.expect(released == nil && !lease.isHolding,
                     "the owner is released once every query it started has called back")
        lease.complete("a")
        suite.expect(!lease.isHolding, "a late duplicate callback does not resurrect the lease")
    }

    private static func checkCustomMode(_ suite: TestSuite) async {
        let quiet = mode(id: 0, level: 10, preset: 1)
        let user = mode(id: 1, name: "My preset", level: 3, editable: true, configured: true)
        let empty = mode(id: 2, level: 0, editable: true)
        let saved = mode(id: 2, name: BoseHeadphoneMode.appModeName, level: 7, editable: true, configured: true)
        let discovery = Radio([
            .reply([31, 2, 1, 0], [1, 2, 0, 0, 0, 0]),
            .reply([31, 6, 1, 1, 0], quiet),
            .reply([31, 6, 1, 1, 1], user),
            .reply([31, 6, 1, 1, 2], empty),
            .reply([31, 3, 1, 0], [0]),
            .reject([31, 10, 1, 0]),
            .reply([2, 2, 1, 0], [84, 255, 255, 0])
        ], suite: suite)
        do {
            let status = try await discovery.commands.read()
            suite.expect(status.modes.map(\.name) == ["Quiet", "My preset"] && status.battery == 84
                         && status.noiseCancellation == 10 && status.customSlot?.id == 2,
                         "device modes and battery decode without treating empty slots as listening modes")

            let name = Array(BoseHeadphoneMode.appModeName.utf8)
            let profile: [UInt8] = [2, 0, 0] + name + [UInt8](repeating: 0, count: 32 - name.count) + [3, 0, 2, 0]
            let radio = Radio([
                .reply([31, 3, 1, 0], [0]),
                .reply([31, 6, 1, 1, 2], empty),
                .reply([31, 6, 2, UInt8(profile.count)] + profile, saved),
                .reply([31, 6, 1, 1, 2], saved),
                .reply([31, 3, 5, 2, 2, 0], [2]),
                .reply([31, 3, 1, 0], [2]),
                .reply([2, 2, 1, 0], [83])
            ], suite: suite)
            let updated = try await radio.commands.setLevel(7, inMode: 0, from: status)
            suite.expect(updated.noiseCancellation == 7 && updated.activeMode == 2
                         && updated.modes.contains { $0.id == 1 && $0.name == "My preset" },
                         "adjusting ANC writes and verifies the dedicated mode without altering the user's presets")
            suite.expect(radio.isFinished && discovery.isFinished, "the custom level is read back before activation")

            let occupied = mode(id: 2, name: "Travel", level: 4, editable: true, configured: true)
            let reusedSlot = Radio([.reply([31, 3, 1, 0], [0]), .reply([31, 6, 1, 1, 2], occupied)], suite: suite)
            do {
                _ = try await reusedSlot.commands.setLevel(7, inMode: 0, from: status)
                suite.expect(false, "a slot changed by the Bose app must not be overwritten")
            } catch {
                suite.expect(error as? BoseHeadphoneError == .noCustomMode && reusedSlot.isFinished,
                             "rechecking the slot protects presets created since discovery")
            }
        } catch {
            suite.expect(false, "custom mode fixture failed: \(error)")
        }
    }

    private static func checkLiveSettings(_ suite: TestSuite) async {
        let quiet = mode(id: 0, level: 10, preset: 1)
        guard let mode = BoseHeadphoneMode(quiet) else {
            suite.expect(false, "quiet fixture must decode")
            return
        }
        let initial = BoseHeadphoneStatus(allModes: [mode], activeMode: 0, battery: 90,
                                         liveSettings: [0, 1, 2, 1, 0])
        let radio = Radio([
            .reply([31, 3, 1, 0], [0]),
            .reply([31, 10, 1, 0], [0, 1, 2, 1, 0]),
            .reply([31, 10, 2, 5, 6, 0, 2, 0, 1], [6, 0, 2, 0, 1]),
            .reply([31, 3, 1, 0], [0]),
            .reply([31, 10, 1, 0], [6, 0, 2, 0, 1]),
            .reject([2, 2, 1, 0])
        ], suite: suite)
        do {
            let status = try await radio.commands.setLevel(4, inMode: 0, from: initial)
            suite.expect(status.noiseCancellation == 4 && status.activeMode == 0 && status.battery == nil
                         && radio.isFinished,
                         "live adjustment preserves spatial audio and works without an available battery reading")
        } catch {
            suite.expect(false, "live settings fixture failed: \(error)")
        }
        await checkModeSwitchedOnHeadset(suite)
    }

    /// The app still shows Quiet, but the headset's own button already moved
    /// to Aware: the level must not land on Aware, and the page must catch up.
    private static func checkModeSwitchedOnHeadset(_ suite: TestSuite) async {
        guard let quiet = BoseHeadphoneMode(mode(id: 0, level: 10, preset: 1)),
              let aware = BoseHeadphoneMode(mode(id: 1, level: 0, preset: 2)) else {
            suite.expect(false, "mode fixtures must decode")
            return
        }
        let cached = BoseHeadphoneStatus(allModes: [quiet, aware], activeMode: 0, battery: 80,
                                        liveSettings: [0, 0, 2, 0, 1])
        let radio = Radio([
            .reply([31, 3, 1, 0], [1]),
            .reply([31, 3, 1, 0], [1]),
            .reply([31, 10, 1, 0], [10, 0, 0, 0, 1]),
            .reply([2, 2, 1, 0], [80, 0xFF, 0xFF, 0])
        ], suite: suite)
        do {
            let refreshed = try await radio.commands.setLevel(4, inMode: 0, from: cached)
            suite.expect(refreshed.activeMode == 1 && refreshed.noiseCancellation == 0 && radio.isFinished,
                         "a mode switched on the headset is read back instead of being overwritten")
            suite.expect(radio.sent.allSatisfy { $0[2] & 0x0F == BoseMessage.Operation.read.rawValue },
                         "no level is written when the headset left the mode it was chosen in")
        } catch {
            suite.expect(false, "a mode switched on the headset must refresh, not fail: \(error)")
        }

        // A switch that lands between the check and the write is caught by the readback.
        let raced = Radio([
            .reply([31, 3, 1, 0], [0]),
            .reply([31, 10, 1, 0], [0, 0, 2, 0, 1]),
            .reply([31, 10, 2, 5, 6, 0, 2, 0, 1], [6, 0, 2, 0, 1]),
            .reply([31, 3, 1, 0], [1]),
            .reply([31, 10, 1, 0], [6, 0, 2, 0, 1]),
            .reply([2, 2, 1, 0], [80, 0xFF, 0xFF, 0])
        ], suite: suite)
        do {
            _ = try await raced.commands.setLevel(4, inMode: 0, from: cached)
            suite.expect(false, "a level that may have landed on another mode must not be reported as applied")
        } catch {
            suite.expect(error as? BoseHeadphoneError == .invalidResponse && raced.isFinished,
                         "a mode switch during the write is reported instead of claimed as success")
        }
    }

    private static func checkBatteryUpdates(_ suite: TestSuite) async {
        // Captured from a QC Ultra: the subscription echoes blocks 31 and 2,
        // then a status arrives about every 55 s without a request.
        let pushed = BoseMessage(block: 2, function: 2, operation: .status, payload: [0x50, 0xFF, 0xFF, 0x00])
        suite.expect(pushed.batteryLevel == 80, "an unsolicited battery status carries the headset's level")
        suite.expect(BoseMessage(block: 2, function: 2, payload: [0x50]).batteryLevel == nil
                     && BoseMessage(block: 2, function: 2, operation: .status, payload: [0xFF]).batteryLevel == nil
                     && BoseMessage(block: 31, function: 2, operation: .status, payload: [0x50]).batteryLevel == nil,
                     "only a battery status with a valid percentage updates the battery")

        let subscribe: [UInt8] = [9, 2, 2, 5, 0x01, 0, 0, 0, 0x04]
        let granted = Radio([.reply(subscribe, [0, 0, 0, 0x04])], suite: suite)
        let declined = Radio([.reply(subscribe, [0, 0, 0, 0])], suite: suite)
        let rejected = Radio([.reject(subscribe)], suite: suite)
        do {
            let accepted = try await granted.commands.subscribeToBatteryUpdates()
            let ignored = try await declined.commands.subscribeToBatteryUpdates()
            let refused = try await rejected.commands.subscribeToBatteryUpdates()
            suite.expect(accepted && !ignored && !refused
                         && granted.isFinished && declined.isFinished && rejected.isFinished,
                         "battery updates count as on only when the headset grants the Status block")
        } catch {
            suite.expect(false, "battery subscription fixture failed: \(error)")
        }
        await checkUnansweredSubscription(suite)

        guard let quiet = BoseHeadphoneMode(mode(id: 0, level: 10, preset: 1)) else {
            suite.expect(false, "quiet fixture must decode")
            return
        }
        let before = BoseHeadphoneStatus(allModes: [quiet], activeMode: 0, battery: 81, liveSettings: [0, 0, 2, 0, 1])
        let after = before.updating(battery: 80)
        suite.expect(after.battery == 80 && before.battery == 81 && after.activeMode == before.activeMode
                     && after.liveSettings == before.liveSettings && after.allModes == before.allModes,
                     "a battery update changes the level and nothing else")
    }

    /// A subscription reply that never comes must cost only the battery
    /// updates: the timeout stays on the optional path, the session keeps
    /// answering, and the controls already read stay usable.
    private static func checkUnansweredSubscription(_ suite: TestSuite) async {
        let subscribe: [UInt8] = [9, 2, 2, 5, 0x01, 0, 0, 0, 0x04]
        let radio = Radio([
            .timeOut(subscribe),
            .reply([31, 3, 5, 2, 1, 0], [1]),
            .reply([31, 3, 1, 0], [1]),
            .reply([2, 2, 1, 0], [79, 0xFF, 0xFF, 0])
        ], suite: suite)
        guard let quiet = BoseHeadphoneMode(mode(id: 0, level: 10, preset: 1)),
              let aware = BoseHeadphoneMode(mode(id: 1, level: 0, preset: 2)) else {
            suite.expect(false, "mode fixtures must decode")
            return
        }
        let status = BoseHeadphoneStatus(allModes: [quiet, aware], activeMode: 0, battery: 80, liveSettings: nil)
        do {
            let subscribed = try await radio.commands.subscribeToBatteryUpdates()
            let switched = try await radio.commands.select(1, from: status)
            suite.expect(!subscribed && switched.activeMode == 1 && switched.battery == 79
                         && radio.isFinished && radio.optionalRequests == [subscribe],
                         "an unanswered battery subscription times out alone and the controls keep working")
        } catch {
            suite.expect(false, "an unanswered battery subscription must not fail the session: \(error)")
        }
    }

    private static func checkPendingLevel(_ suite: TestSuite) {
        guard let quiet = BoseHeadphoneMode(mode(id: 0, level: 10, preset: 1)),
              let user = BoseHeadphoneMode(mode(id: 1, name: "Desk", level: 10, editable: true, configured: true)) else {
            suite.expect(false, "mode fixtures must decode")
            return
        }
        let live: [UInt8] = [0, 0, 2, 0, 1]
        let inQuiet = BoseHeadphoneStatus(allModes: [quiet, user], activeMode: 0, battery: 80, liveSettings: live)
        guard let origin = QCPendingLevel.Origin(deviceID: "headset", status: inQuiet) else {
            suite.expect(false, "a connected status gives an edit its origin")
            return
        }
        let pending = QCPendingLevel(level: 6, origin: origin)
        suite.expect(pending.commitTarget(deviceID: "headset", status: inQuiet) == 6,
                     "a level moved in the active mode is sent")
        suite.expect(pending.commitTarget(deviceID: "headset", status: inQuiet.updating(battery: 79)) == 6,
                     "a battery update arriving during the edit keeps it")

        // Both modes report level 10, so only the origin can tell them apart.
        let inDesk = BoseHeadphoneStatus(allModes: [quiet, user], activeMode: 1, battery: 80, liveSettings: live)
        suite.expect(inQuiet.noiseCancellation == inDesk.noiseCancellation
                     && pending.commitTarget(deviceID: "headset", status: inDesk) == nil,
                     "switching to a mode with the same level drops the pending edit")
        suite.expect(pending.commitTarget(deviceID: "other", status: inQuiet) == nil
                     && pending.commitTarget(deviceID: nil, status: inQuiet) == nil
                     && pending.commitTarget(deviceID: "headset", status: nil) == nil,
                     "another or a lost headset drops the pending edit")

        let unchanged = QCPendingLevel(level: 10, origin: origin)
        let buttonSet = BoseHeadphoneStatus(allModes: [quiet, user], activeMode: 0, battery: 80,
                                            liveSettings: [0, 0, 2, 0, 0])
        suite.expect(unchanged.commitTarget(deviceID: "headset", status: inQuiet) == nil
                     && unchanged.commitTarget(deviceID: "headset", status: buttonSet) == 10,
                     "an unchanged level is not resent unless the headset's buttons set it")
        let locked = BoseHeadphoneStatus(allModes: [quiet], activeMode: 0, battery: 80, liveSettings: nil)
        suite.expect(pending.commitTarget(deviceID: "headset", status: locked) == nil,
                     "nothing is sent when the level cannot be set")
    }

    private static func mode(id: UInt8, name: String = "", level: UInt8, preset: UInt8 = 0,
                             editable: Bool = false, configured: Bool = false) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 47)
        bytes[0] = id
        bytes[2] = preset
        bytes[3] = editable ? 1 : 0
        bytes[4] = configured ? 1 : 0
        bytes.replaceSubrange(6..<(6 + name.utf8.count), with: name.utf8)
        bytes[41] = 1
        bytes[42] = 10 - level
        bytes[44] = 2
        return bytes
    }

    private final class Radio {
        struct Exchange {
            let request: [UInt8]
            let result: Result<[UInt8], BoseHeadphoneError>

            static func reply(_ request: [UInt8], _ payload: [UInt8]) -> Self {
                Self(request: request, result: .success(payload))
            }

            static func reject(_ request: [UInt8]) -> Self {
                Self(request: request, result: .failure(.rejected))
            }

            /// The headset never answers; the transport reports a timeout.
            static func timeOut(_ request: [UInt8]) -> Self {
                Self(request: request, result: .failure(.timedOut))
            }
        }

        private var exchanges: ArraySlice<Exchange>
        private let suite: TestSuite
        /// Requests sent on the path whose timeout leaves the channel open.
        private(set) var optionalRequests: [[UInt8]] = []
        /// Every request, in order, on either path.
        private(set) var sent: [[UInt8]] = []

        init(_ exchanges: [Exchange], suite: TestSuite) {
            self.exchanges = exchanges[...]
            self.suite = suite
        }

        var isFinished: Bool { exchanges.isEmpty }
        var commands: BoseHeadphoneCommands {
            BoseHeadphoneCommands(send: { try self.exchange($0) }, sendOptional: { message in
                self.optionalRequests.append(message.bytes)
                return try self.exchange(message)
            })
        }

        private func exchange(_ message: BoseMessage) throws -> [UInt8] {
            sent.append(message.bytes)
            guard let expected = exchanges.popFirst() else {
                suite.expect(false, "unexpected command \(message.bytes)")
                throw BoseHeadphoneError.invalidResponse
            }
            suite.expect(message.bytes == expected.request, "expected \(expected.request), received \(message.bytes)")
            return try expected.result.get()
        }
    }
}
