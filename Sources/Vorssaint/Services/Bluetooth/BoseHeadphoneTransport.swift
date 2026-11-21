// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOBluetooth

struct BoseHeadphoneDevice: Identifiable {
    let id: String
    let name: String

    init?(id: String, name: String?, vendorID: UInt16, productID: UInt16) {
        // The Device ID record can use either the Bluetooth SIG or USB vendor namespace.
        guard vendorID == 0x009E || vendorID == 0x05A7,
              productID == 0x4066 || productID == 0x4082 else { return nil }
        self.id = id
        let label = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = label.flatMap { $0.isEmpty ? nil : $0 } ?? "Bose QuietComfort Ultra Headphones"
    }
}

/// IOBluetooth does not promise to retain the target of an async query or
/// connection, so an owner keeps itself alive here until each one calls back.
struct BluetoothQueryLease {
    private var pending: [String: Int] = [:]
    private var owner: AnyObject?

    var isHolding: Bool { owner != nil }

    mutating func begin(_ id: String, owner: AnyObject) {
        pending[id, default: 0] += 1
        self.owner = owner
    }

    mutating func complete(_ id: String) {
        guard let count = pending[id] else { return }
        pending[id] = count > 1 ? count - 1 : nil
        if pending.isEmpty { owner = nil }
    }
}

/// Owns just the control channel. Closing it leaves system pairing and audio alone.
final class BoseHeadphoneTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private struct Opening {
        enum Stage { case services, baseband, serial }
        let device: IOBluetoothDevice
        let completion: CheckedContinuation<Void, Error>
        var stage: Stage = .services
    }

    private static let worker = BluetoothRunLoop(name: "Vorssaint Bose Headphones")
    private let onDisconnect: () -> Void
    private var channel: IOBluetoothRFCOMMChannel?
    private var opening: Opening?
    private var pending: (command: BoseMessage, reply: CheckedContinuation<[UInt8], Error>)?
    private var timer: Timer?
    private var stream = BoseMessageStream()
    private var queries = BluetoothQueryLease()

    init(onDisconnect: @escaping () -> Void) {
        self.onDisconnect = onDisconnect
    }

    static func pairedHeadphones() async -> [BoseHeadphoneDevice] {
        await withCheckedContinuation { continuation in
            worker.perform {
                BoseHeadphoneDiscovery(worker: worker, completion: continuation).start()
            }
        }
    }

    func connect(to address: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            Self.worker.perform { self.open(address, completion: continuation) }
        }
        // The headset can acknowledge RFCOMM before it accepts the first BMAP
        // request, especially when the panel was just closed and reopened.
        try await Task.sleep(for: .milliseconds(500))
    }

    func send(_ command: BoseMessage) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            Self.worker.perform { self.write(command, completion: continuation) }
        }
    }

    func disconnect() {
        Self.worker.perform { self.close(with: .disconnected) }
    }

    private func open(_ address: String, completion: CheckedContinuation<Void, Error>) {
        // Every query and channel open below would page a headset that is not
        // connected, pulling it away from the phone or computer it is in use with.
        guard channel == nil, opening == nil, let device = IOBluetoothDevice(addressString: address),
              BluetoothAudioRoutes.isConnected(device, routes: BluetoothAudioRoutes.connectedAddresses()) else {
            completion.resume(throwing: BoseHeadphoneError.disconnected)
            return
        }
        opening = Opening(device: device, completion: completion)
        // macOS can show the headset connected for audio while its Classic
        // control connection still needs a service refresh and explicit open.
        if let id = device.addressString, device.performSDPQuery(self) == kIOReturnSuccess {
            queries.begin(Self.queryKey(id), owner: self)
            armTimeout(seconds: 1.5) { $0.openBaseband() }
        } else {
            openBaseband()
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        Self.worker.perform {
            if let id = device.addressString { self.queries.complete(Self.queryKey(id)) }
            guard self.opening?.device === device else { return }
            self.openBaseband()
        }
    }

    private func openBaseband() {
        guard let opening, opening.stage == .services else { return }
        if opening.device.isConnected() {
            openSerialChannel(on: opening.device)
            return
        }
        // IOBluetooth missed the audio link. Opening attaches to that link,
        // and runs only when CoreAudio still routes through the headset.
        guard let id = opening.device.addressString,
              BluetoothAudioRoutes.connectedAddresses().contains(id.lowercased()) else {
            close(with: .disconnected)
            return
        }
        self.opening?.stage = .baseband
        if opening.device.openConnection(self) == kIOReturnSuccess {
            queries.begin(Self.connectionKey(id), owner: self)
            armTimeout(seconds: 5)
        } else if opening.device.isConnected() {
            openSerialChannel(on: opening.device)
        } else {
            close(with: .disconnected)
        }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        Self.worker.perform {
            if let id = device.addressString { self.queries.complete(Self.connectionKey(id)) }
            guard let opening = self.opening, opening.device === device, opening.stage == .baseband else { return }
            guard status == kIOReturnSuccess || device.isConnected() else {
                self.close(with: .disconnected)
                return
            }
            self.openSerialChannel(on: device)
        }
    }

    private static func queryKey(_ id: String) -> String { "query \(id)" }
    private static func connectionKey(_ id: String) -> String { "connection \(id)" }

    private func openSerialChannel(on device: IOBluetoothDevice) {
        opening?.stage = .serial
        // Both supported models carry BMAP on their Serial Port channel 2.
        // The vendor-specific BMAP UUID can advertise a separate channel.
        let status = device.openRFCOMMChannelAsync(&channel, withChannelID: 2, delegate: self)
        if status == kIOReturnSuccess {
            armTimeout(seconds: 8)
        } else {
            close(with: .disconnected)
        }
    }

    private func write(_ command: BoseMessage, completion: CheckedContinuation<[UInt8], Error>) {
        guard let channel, opening == nil, pending == nil else {
            completion.resume(throwing: BoseHeadphoneError.disconnected)
            return
        }
        pending = (command, completion)
        var bytes = command.bytes
        let status = bytes.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        if status == kIOReturnSuccess {
            armTimeout(seconds: 3)
        } else {
            close(with: .disconnected)
        }
    }

    private func armTimeout(seconds: TimeInterval,
                            action: @escaping (BoseHeadphoneTransport) -> Void = { $0.close(with: .timedOut) }) {
        clearTimeout()
        let timeout = Timer(timeInterval: seconds, repeats: false) { [weak self] timer in
            Self.worker.perform {
                guard let self, self.timer === timer else { return }
                action(self)
            }
        }
        timer = timeout
        RunLoop.current.add(timeout, forMode: .common)
    }

    private func clearTimeout() {
        timer?.invalidate()
        timer = nil
    }

    private func close(with error: BoseHeadphoneError) {
        clearTimeout()
        let oldChannel = channel
        let connection = opening
        let reply = pending?.reply
        channel = nil
        opening = nil
        pending = nil
        stream = BoseMessageStream()
        oldChannel?.setDelegate(nil)
        _ = oldChannel?.close()
        connection?.completion.resume(throwing: error)
        reply?.resume(throwing: error)
    }

    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        Self.worker.perform {
            guard channel === self.channel, let opening = self.opening, opening.stage == .serial else { return }
            guard error == kIOReturnSuccess, channel != nil else { self.close(with: .disconnected); return }
            self.clearTimeout()
            self.opening = nil
            opening.completion.resume()
        }
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        Self.worker.perform {
            guard let channel, channel === self.channel else { return }
            let wasIdle = self.opening == nil && self.pending == nil
            self.close(with: .disconnected)
            if wasIdle { self.onDisconnect() }
        }
    }

    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data: UnsafeMutableRawPointer!, length: Int) {
        guard let data, length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: length))
        Self.worker.perform {
            guard let channel, channel === self.channel else { return }
            for message in self.stream.receive(bytes) {
                guard let pending = self.pending, let result = message.reply(to: pending.command) else { continue }
                self.clearTimeout()
                self.pending = nil
                switch result {
                case .success(let payload): pending.reply.resume(returning: payload)
                case .failure(let error): pending.reply.resume(throwing: error)
                }
            }
        }
    }
}

/// Resolve hardware identity using the Bluetooth Device ID profile (PnP Information).
private final class BoseHeadphoneDiscovery: NSObject {
    private static let deviceID = IOBluetoothSDPUUID(uuid16: 0x1200)
    private let worker: BluetoothRunLoop
    private let completion: CheckedContinuation<[BoseHeadphoneDevice], Never>
    private var matches: [BoseHeadphoneDevice] = []
    private var awaiting: Set<String> = []
    private var queries = BluetoothQueryLease()
    private var timeout: Timer?

    init(worker: BluetoothRunLoop, completion: CheckedContinuation<[BoseHeadphoneDevice], Never>) {
        self.worker = worker
        self.completion = completion
    }

    func start() {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let routes = BluetoothAudioRoutes.connectedAddresses()
        var seen = Set<String>()
        for device in paired {
            // A headset that is paired but in use elsewhere stays off the list,
            // so a single match never gets connected out from under its owner.
            guard BluetoothAudioRoutes.isConnected(device, routes: routes), let id = device.addressString, seen.insert(id).inserted else { continue }
            if readIdentity(device, id: id) { continue }
            // A fresh audio connection may not have a Device ID cached yet.
            guard Self.isHeadset(device), device.performSDPQuery(self) == kIOReturnSuccess else { continue }
            queries.begin(id, owner: self)
            awaiting.insert(id)
        }
        if awaiting.isEmpty {
            finish()
        } else {
            // Answers that miss the deadline are dropped; the lease keeps the
            // discovery alive until they arrive anyway.
            let deadline = Timer(timeInterval: 3, repeats: false) { [self] _ in
                worker.perform { [self] in
                    if timeout != nil { finish() }
                }
            }
            timeout = deadline
            RunLoop.current.add(deadline, forMode: .common)
        }
    }

    private static func isHeadset(_ device: IOBluetoothDevice) -> Bool {
        guard device.deviceClassMajor == kBluetoothDeviceClassMajorAudio else { return false }
        return device.deviceClassMinor == kBluetoothDeviceClassMinorAudioHeadset
            || device.deviceClassMinor == kBluetoothDeviceClassMinorAudioHeadphones
            || device.deviceClassMinor == kBluetoothDeviceClassMinorAudioHandsFree
    }

    @discardableResult
    private func readIdentity(_ device: IOBluetoothDevice, id: String) -> Bool {
        guard let info = device.getServiceRecord(for: Self.deviceID),
              let vendor = info.getAttributeDataElement(0x0201)?.getNumberValue()?.uint16Value,
              let product = info.getAttributeDataElement(0x0202)?.getNumberValue()?.uint16Value else { return false }
        if let headset = BoseHeadphoneDevice(id: id, name: device.name, vendorID: vendor, productID: product) {
            matches.append(headset)
        }
        return true
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        worker.perform { [self] in
            guard let id = device.addressString else { return }
            queries.complete(id)
            guard awaiting.remove(id) != nil else { return }
            if status == kIOReturnSuccess { readIdentity(device, id: id) }
            if awaiting.isEmpty { finish() }
        }
    }

    private func finish() {
        timeout?.invalidate()
        timeout = nil
        awaiting.removeAll()
        completion.resume(returning: matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
}
