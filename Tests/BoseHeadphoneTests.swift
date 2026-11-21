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

        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            await checkCustomMode(suite)
            await checkLiveSettings(suite)
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
                .reply([31, 6, 1, 1, 2], empty),
                .reply([31, 6, 2, UInt8(profile.count)] + profile, saved),
                .reply([31, 6, 1, 1, 2], saved),
                .reply([31, 3, 5, 2, 2, 0], [2]),
                .reply([31, 3, 1, 0], [2]),
                .reply([2, 2, 1, 0], [83])
            ], suite: suite)
            let updated = try await radio.commands.setLevel(7, from: status)
            suite.expect(updated.noiseCancellation == 7 && updated.activeMode == 2
                         && updated.modes.contains { $0.id == 1 && $0.name == "My preset" },
                         "adjusting ANC writes and verifies the dedicated mode without altering the user's presets")
            suite.expect(radio.isFinished && discovery.isFinished, "the custom level is read back before activation")

            let occupied = mode(id: 2, name: "Travel", level: 4, editable: true, configured: true)
            let reusedSlot = Radio([.reply([31, 6, 1, 1, 2], occupied)], suite: suite)
            do {
                _ = try await reusedSlot.commands.setLevel(7, from: status)
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
            .reply([31, 10, 1, 0], [0, 1, 2, 1, 0]),
            .reply([31, 10, 2, 5, 6, 0, 2, 0, 1], [6, 0, 2, 0, 1]),
            .reply([31, 3, 1, 0], [0]),
            .reply([31, 10, 1, 0], [6, 0, 2, 0, 1]),
            .reject([2, 2, 1, 0])
        ], suite: suite)
        do {
            let status = try await radio.commands.setLevel(4, from: initial)
            suite.expect(status.noiseCancellation == 4 && status.activeMode == 0 && status.battery == nil
                         && radio.isFinished,
                         "live adjustment preserves spatial audio and works without an available battery reading")
        } catch {
            suite.expect(false, "live settings fixture failed: \(error)")
        }
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
        }

        private var exchanges: ArraySlice<Exchange>
        private let suite: TestSuite

        init(_ exchanges: [Exchange], suite: TestSuite) {
            self.exchanges = exchanges[...]
            self.suite = suite
        }

        var isFinished: Bool { exchanges.isEmpty }
        var commands: BoseHeadphoneCommands {
            BoseHeadphoneCommands { message in
                guard let expected = self.exchanges.popFirst() else {
                    self.suite.expect(false, "unexpected command \(message.bytes)")
                    throw BoseHeadphoneError.invalidResponse
                }
                self.suite.expect(message.bytes == expected.request,
                                  "expected \(expected.request), received \(message.bytes)")
                return try expected.result.get()
            }
        }
    }
}
